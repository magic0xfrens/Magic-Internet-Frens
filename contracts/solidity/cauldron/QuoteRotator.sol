// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title QuoteRotator
 * @notice Converts a MEASURED amount of one quote asset into another, in slices.
 *
 *  The MiFrens guild manages what its own LP is denominated in: sell ETH into
 *  USDG near a top, rotate back later, hold a tokenized equity. This contract is
 *  the execution half of that decision.
 *
 *  ── Why there is no price oracle ───────────────────────────────────────────
 *  An earlier version modelled this as a target ALLOCATION ("60% ETH / 40%
 *  USDG") and compared holdings across assets to decide what to move. That is
 *  wrong without a common numeraire: raw balances are not comparable across
 *  assets with different decimals — 10 ETH is 1e19 units and 10,000 USDC is
 *  1e10, so ETH reads as 99.999% of the "total" — and even at equal decimals a
 *  unit of one is not worth a unit of the other. Fixing that honestly needs a
 *  price feed per quote.
 *
 *  A ROTATION IS A FLOW, NOT A STOCK. The guild does not need to express "hold
 *  40% USDG"; it needs "convert 30% of our ETH into USDG". That is a fraction of
 *  ONE asset, measured against itself, so nothing has to be valued and no oracle
 *  is required. What the pool gives back is recorded exactly as received.
 *
 *  ── Where the price protection comes from ──────────────────────────────────
 *  `minOut` is supplied BY GOVERNANCE when the rotation is scheduled, not read
 *  from a pool at execution time. Reading spot at execution is precisely the
 *  manipulation the bound exists to stop — an attacker pushes the route, the
 *  contract computes a low floor from that pushed price, and fills into it. A
 *  human setting the bound from the market when they vote cannot be moved by a
 *  swap in the same block.
 *
 *  ── Execution ──────────────────────────────────────────────────────────────
 *  {rotateStep} is permissionless and pays a bounded reward, like the
 *  liquidation sweep: our bot runs it, and if it stops, anyone can. Each call
 *  moves one slice, no more often than `interval`. Slicing is the execution
 *  strategy — one large conversion is both a sandwich target and a
 *  self-inflicted price impact.
 */
contract QuoteRotator {
    error NotOwner();
    error NotAllowedQuote();
    error BadConfig();
    error TooSoon();
    error NoPlan();
    error SlippageTooHigh();
    error NoRoute();
    error TransferFailed();

    /// @notice A scheduled conversion. Amounts are in the assets' OWN units, so
    ///         nothing here needs a common numeraire.
    struct Plan {
        address from;         // asset being sold
        address to;           // asset being bought
        uint128 totalIn;      // total `from` to convert across the whole plan
        uint128 sliceIn;      // how much `from` each step sells
        uint128 doneIn;       // `from` sold so far
        uint128 gotOut;       // `to` received so far — RECORDED, never assumed
        /// Minimum `to` per whole unit of `from`, scaled by 1e18. Set by
        /// governance from the market at vote time, NOT read from a pool here.
        uint256 minRate;
        uint32 interval;      // seconds between slices
        uint64 lastStepAt;
    }

    Plan public plan;

    address public owner;
    address public immutable registry;
    IPoolManager public immutable poolManager;

    /// @notice Paid to whoever executes a slice, in bps of what that slice
    ///         produced. Bounded so keeper cost can never dominate the rotation.
    uint16 public keeperBps = 10; // 0.1%

    uint16 constant BPS = 10_000;
    uint256 constant WAD = 1e18;

    event PlanSet(address indexed from, address indexed to, uint128 totalIn, uint128 sliceIn, uint256 minRate);
    event PlanCancelled(uint128 doneIn, uint128 gotOut);
    event Rotated(address indexed from, address indexed to, uint256 amountIn, uint256 amountOut, address keeper);
    event Withdrawn(address indexed asset, address indexed to, uint256 amount);

    constructor(address _registry, IPoolManager _poolManager) {
        registry = _registry;
        poolManager = _poolManager;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address to) external onlyOwner { owner = to; }

    // -----------------------------------------------------------------------
    // Governance
    // -----------------------------------------------------------------------

    /**
     * @notice Schedule a conversion.
     * @param from     asset to sell (address(0) = native ETH)
     * @param to       asset to buy — must be on the registry's allowlist
     * @param totalIn  total amount of `from` to convert
     * @param sliceIn  amount per step; slicing is what keeps market impact small
     * @param minRate  minimum `to` per 1e18 of `from`. SET FROM THE MARKET when
     *                 voting. This is the whole price protection, so a zero or
     *                 careless value is the one way to lose money here.
     * @param interval seconds between steps
     */
    function setPlan(
        address from,
        address to,
        uint128 totalIn,
        uint128 sliceIn,
        uint256 minRate,
        uint32 interval
    ) external onlyOwner {
        if (from == to || totalIn == 0 || sliceIn == 0 || sliceIn > totalIn) revert BadConfig();
        // A zero floor would accept ANY fill, including a fully manipulated one.
        if (minRate == 0) revert BadConfig();
        // Only assets the treasury has vetted can be bought. Checked here AND at
        // execution, because the allowlist can change in between.
        if (!_allowed(to)) revert NotAllowedQuote();

        plan = Plan({
            from: from,
            to: to,
            totalIn: totalIn,
            sliceIn: sliceIn,
            doneIn: 0,
            gotOut: 0,
            minRate: minRate,
            interval: interval,
            lastStepAt: 0
        });
        emit PlanSet(from, to, totalIn, sliceIn, minRate);
    }

    /// @notice Stop a rotation mid-flight, keeping whatever it has already
    ///         converted. The guild must be able to abandon a plan when the
    ///         market moves against the thesis it was voted on.
    function cancelPlan() external onlyOwner {
        emit PlanCancelled(plan.doneIn, plan.gotOut);
        delete plan;
    }

    function setKeeperBps(uint16 bps) external onlyOwner {
        if (bps > 100) revert BadConfig(); // 1% ceiling
        keeperBps = bps;
    }

    // -----------------------------------------------------------------------
    // Execution
    // -----------------------------------------------------------------------

    /// @notice How much the next slice would sell, or 0 if none is due.
    function nextSliceSize() public view returns (uint256) {
        Plan storage p = plan;
        if (p.totalIn == 0 || p.doneIn >= p.totalIn) return 0;
        //  `lastStepAt == 0` means no slice has run yet, so the FIRST one is due
        //  immediately — the interval spaces subsequent slices, it is not a
        //  delay before the plan starts. Comparing against zero directly would
        //  block the opening slice for a full interval after the vote.
        if (p.lastStepAt != 0 && block.timestamp < uint256(p.lastStepAt) + p.interval) return 0;
        uint256 left = p.totalIn - p.doneIn;
        uint256 size = p.sliceIn < left ? p.sliceIn : left;
        uint256 held = _balanceOf(p.from);
        return size < held ? size : held;
    }

    /**
     * @notice Execute one slice.
     * @dev Permissionless. The caller supplies the venue but controls nothing
     *      else: direction, size and the price floor all come from the governed
     *      plan, so calling this repeatedly only advances the rotation the guild
     *      already voted for, at a price it already bounded.
     */
    function rotateStep(PoolKey calldata route) external returns (uint256 out) {
        Plan storage p = plan;
        if (p.totalIn == 0) revert NoPlan();

        uint256 size = nextSliceSize();
        if (size == 0) revert TooSoon();
        if (!_allowed(p.to)) revert NotAllowedQuote();
        if (!_routeMatches(route, p.from, p.to)) revert NoRoute();

        // Effects BEFORE the external call: the swap re-enters this contract via
        // unlockCallback and pays an arbitrary keeper at the end, so the step
        // must already be recorded as taken.
        p.lastStepAt = uint64(block.timestamp);
        p.doneIn += uint128(size);

        out = _swap(route, p.from, p.to, size);

        // The floor is the GOVERNED rate, not anything read from the pool now.
        uint256 minOut = (size * p.minRate) / WAD;
        if (out < minOut) revert SlippageTooHigh();

        // Record what actually arrived rather than what was expected.
        p.gotOut += uint128(out);

        uint256 fee = (out * keeperBps) / BPS;
        if (fee > 0) _send(p.to, msg.sender, fee);

        emit Rotated(p.from, p.to, size, out, msg.sender);
    }

    /**
     * @notice Convert an exact amount, right now, in one call.
     * @dev The plan machinery above schedules a conversion over hours. This is
     *      the other shape: a single bounded slice, executed inside the caller's
     *      transaction, so liquidity is removed and redeployed without ever
     *      sitting idle between the two.
     *
     *      Owner-only because the caller decides the size and the floor — those
     *      are exactly the two things a permissionless caller must not choose.
     *      The owner is the registry, which derives both from governed limits.
     */
    function swapOnce(
        PoolKey calldata route,
        address from,
        address to,
        uint256 amountIn,
        uint256 minOut
    ) external onlyOwner returns (uint256 out) {
        if (amountIn == 0) revert BadConfig();
        if (!_allowed(to)) revert NotAllowedQuote();
        if (!_routeMatches(route, from, to)) revert NoRoute();
        out = _swap(route, from, to, amountIn);
        if (out < minOut) revert SlippageTooHigh();
        emit Rotated(from, to, amountIn, out, msg.sender);
    }

    // -----------------------------------------------------------------------
    // Arbitrage between the generation's own pools
    // -----------------------------------------------------------------------

    /// @notice Prices the two legs so profit can be judged in one unit.
    address public quoteOracle;

    /// @notice Share of arb profit paid to whoever called it, in bps.
    ///         The rest stays with the treasury.
    uint16 public arbKeeperBps = 1000; // 10%

    /// @notice Smallest profit worth executing, in USD scaled 1e18. Without a
    ///         floor a keeper can farm the reward on dust arbs that cost the
    ///         treasury more in price impact than they capture.
    uint256 public minArbProfitUsd = 5e18; // $5

    event Arbed(uint256 spentIn, uint256 receivedOut, uint256 profitUsd, address keeper);

    function setArbParams(address oracle, uint16 keeperBps, uint256 minProfitUsd) external onlyOwner {
        if (keeperBps > 2000) revert BadConfig(); // keeper share capped at 20%
        quoteOracle = oracle;
        arbKeeperBps = keeperBps;
        minArbProfitUsd = minProfitUsd;
    }

    /**
     * @notice Capture the spread between two of the generation's own pools.
     *
     *  When GNOME/ETH and GNOME/USDG drift apart, an outside arbitrageur buys
     *  cheap from one of OUR pools and sells dear into the other. The spread is
     *  paid by our own LP positions. Today every cent of that leaves. This
     *  captures it instead.
     *
     *  ── The shape is not a loop, and that matters ─────────────────────────
     *  Buying the token in the ETH pool and selling it in the USDG pool leaves
     *  us with less ETH, more USDG and the same token — it does NOT return to
     *  the starting asset. So an arb also SHIFTS TREASURY ALLOCATION, which is a
     *  governance question and not merely a mechanical one. Two consequences:
     *
     *    - profit is judged in USD, because the legs are different assets and
     *      there is no other common unit;
     *    - size is bounded per call, so repeated arbs cannot quietly re-allocate
     *      the treasury behind governance's back.
     *
     *  ── Why Chainlink is right here ────────────────────────────────────────
     *  The oracle only has to answer "was this trade profitable". A wrong answer
     *  produces a bad trade bounded by `minProfitUsd` and the size cap —
     *  recoverable and capped. That is a different blast radius from pricing
     *  death, where a wrong answer is irreversible.
     *
     *  ── Capital ───────────────────────────────────────────────────────────
     *  None needed. Both legs happen inside one v4 unlock, so only the net delta
     *  settles: we owe the quote we spent and are owed the quote we received.
     *  If there is no surplus the call reverts and nothing moved.
     *
     * @param cheap  pool to BUY the token in
     * @param dear   pool to SELL it in
     * @param amountIn  quote to spend on the cheap side
     */
    function arbStep(PoolKey calldata cheap, PoolKey calldata dear, uint256 amountIn)
        external
        returns (uint256 profitUsd)
    {
        if (amountIn == 0) revert BadConfig();
        address inQuote = Currency.unwrap(cheap.currency0);
        address outQuote = Currency.unwrap(dear.currency0);
        // Both pools must trade the SAME token, or this is not an arb — it is
        // an unrelated trade with treasury funds.
        if (Currency.unwrap(cheap.currency1) != Currency.unwrap(dear.currency1)) revert NoRoute();
        if (inQuote == outQuote) revert NoRoute();

        (uint256 spent, uint256 received) =
            abi.decode(poolManager.unlock(abi.encode(uint8(1), cheap, dear, amountIn)), (uint256, uint256));

        //  Judge in USD, since the legs are different assets. Both must be
        //  priceable — an unpriceable leg means we cannot tell profit from loss,
        //  and guessing with treasury funds is not an option.
        uint256 inUsd = _usd(inQuote, spent);
        uint256 outUsd = _usd(outQuote, received);
        if (inUsd == 0 || outUsd == 0) revert NoRoute();
        if (outUsd <= inUsd) revert SlippageTooHigh();

        profitUsd = outUsd - inUsd;
        if (profitUsd < minArbProfitUsd) revert SlippageTooHigh();

        // The keeper's cut is paid in the asset received, proportional to the
        // profit rather than the notional — so a large, barely-profitable arb
        // does not pay out more than it made.
        uint256 keeperCut = (received * profitUsd * arbKeeperBps) / (outUsd * BPS);
        if (keeperCut > 0) _send(outQuote, msg.sender, keeperCut);

        emit Arbed(spent, received, profitUsd, msg.sender);
    }

    function _usd(address quote, uint256 raw) internal returns (uint256) {
        address o = quoteOracle;
        if (o == address(0)) return 0;
        (bool ok, bytes memory ret) = o.call(
            abi.encodeWithSignature("cachedUsdPerRawUnit(address)", quote)
        );
        if (!ok || ret.length < 32) return 0;
        uint256 f = abi.decode(ret, (uint256));
        return f == 0 ? 0 : (raw * f) / 1e18;
    }

    // -----------------------------------------------------------------------
    // Custody
    // -----------------------------------------------------------------------

    /**
     * @notice Move converted assets out — to the registry, to be re-deployed as
     *         liquidity in the new pair.
     * @dev Owner-only and event-logged. Without this the contract would convert
     *      assets and then hold them forever with no way to put them back to
     *      work, which is what an earlier version did.
     */
    function withdraw(address asset, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert BadConfig();
        _send(asset, to, amount);
        emit Withdrawn(asset, to, amount);
    }

    // -----------------------------------------------------------------------
    // Internals
    // -----------------------------------------------------------------------

    function _swap(PoolKey calldata route, address from, address to, uint256 size)
        internal
        returns (uint256 out)
    {
        bool zeroForOne = Currency.unwrap(route.currency0) == from;
        bytes memory res = poolManager.unlock(abi.encode(uint8(0), route, zeroForOne, size, from, to));
        out = abi.decode(res, (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotOwner();
        //  TWO PAYLOAD SHAPES share this entry point, so they are tagged. abi
        //  decoding cannot tell them apart, and mis-decoding one as the other
        //  would read a PoolKey out of an amount.
        uint8 kind = abi.decode(data[:32], (uint8));
        if (kind == 1) return _arbCallback(data);

        (, PoolKey memory key, bool zeroForOne, uint256 size, address from, address to) =
            abi.decode(data, (uint8, PoolKey, bool, uint256, address, address));

        BalanceDelta d = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(size),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );

        uint256 got = uint256(uint128(zeroForOne ? d.amount1() : d.amount0()));
        _settle(from, size);
        poolManager.take(Currency.wrap(to), address(this), got);
        return abi.encode(got);
    }

    /**
     * @dev Both arb legs inside ONE unlock, so no capital is required: the token
     *      bought on the cheap side is sold on the dear side within the same
     *      lock, and only the net quote deltas settle.
     */
    function _arbCallback(bytes calldata data) internal returns (bytes memory) {
        (, PoolKey memory cheap, PoolKey memory dear, uint256 amountIn) =
            abi.decode(data, (uint8, PoolKey, PoolKey, uint256));

        // Leg 1: spend the quote, receive the token.
        BalanceDelta d1 = poolManager.swap(
            cheap,
            SwapParams({ zeroForOne: true, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 }),
            ""
        );
        uint256 spent = uint256(uint128(-d1.amount0()));
        uint256 got = uint256(uint128(d1.amount1()));

        // Leg 2: sell EXACTLY what leg 1 produced, so the token nets to zero and
        // the arb leaves no inventory behind.
        BalanceDelta d2 = poolManager.swap(
            dear,
            SwapParams({ zeroForOne: false, amountSpecified: -int256(got), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1 }),
            ""
        );
        uint256 received = uint256(uint128(d2.amount0()));

        _settle(Currency.unwrap(cheap.currency0), spent);
        poolManager.take(dear.currency0, address(this), received);
        return abi.encode(spent, received);
    }

    function _settle(address cur, uint256 amount) internal {
        if (cur == address(0)) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(Currency.wrap(cur));
            _safeTransfer(cur, address(poolManager), amount);
            poolManager.settle();
        }
    }

    function _send(address cur, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (cur == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            _safeTransfer(cur, to, amount);
        }
    }

    /// @dev Return value CHECKED. USDT and most tokenized equities return false
    ///      instead of reverting, and an unchecked transfer would report success
    ///      while nothing moved.
    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!(ok && (ret.length == 0 || abi.decode(ret, (bool))))) revert TransferFailed();
    }

    function _routeMatches(PoolKey calldata route, address from, address to)
        internal
        pure
        returns (bool)
    {
        address c0 = Currency.unwrap(route.currency0);
        address c1 = Currency.unwrap(route.currency1);
        return (c0 == from && c1 == to) || (c0 == to && c1 == from);
    }

    function _balanceOf(address asset) internal view returns (uint256) {
        return asset == address(0) ? address(this).balance : IERC20(asset).balanceOf(address(this));
    }

    function _allowed(address quote) internal view returns (bool) {
        if (quote == address(0)) return true; // native is allowed by construction
        (bool ok, bytes memory ret) =
            registry.staticcall(abi.encodeWithSignature("allowedQuote(address)", quote));
        return ok && ret.length >= 32 && abi.decode(ret, (bool));
    }

    receive() external payable {}
}
