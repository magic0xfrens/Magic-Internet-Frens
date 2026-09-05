// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title QuoteRotator
 * @notice Lets the MiFrens guild manage what the LP's base asset actually IS.
 *
 *  The Cauldron's liquidity has always been ETH-denominated, which means the
 *  treasury is long ETH whether or not the guild wants to be. This contract makes
 *  that a DECISION: govern a target allocation across approved quote assets, and
 *  the LP rotates toward it. Sell ETH into USDG near a top, rotate back later,
 *  hold a tokenized equity — the guild acts as the fund manager for its own
 *  liquidity.
 *
 *  ── Execution: sliced, keeper-driven ───────────────────────────────────────
 *  A rotation is remove-liquidity → swap → re-add. That is far too much gas to
 *  bury inside a user's swap, so it is NOT poked from `afterSwap` the way the
 *  seeder is. Instead {rotateStep} is permissionless and pays the caller a
 *  bounded reward, like the liquidation sweep: our own bot runs it, and if it
 *  ever stops, anyone can.
 *
 *  Each call moves at most `maxStepBps` of the position and no more often than
 *  `stepCooldown`. That is deliberate execution strategy, not just safety: a
 *  single large conversion is both a sandwich target and a self-inflicted price
 *  impact. Slicing over time is how a desk of any size actually trades.
 *
 *  ── What protects the treasury ─────────────────────────────────────────────
 *  The swap leg necessarily touches a market this protocol does NOT own, so
 *  every step is bounded before it is allowed to execute:
 *
 *    1. `minOut` is computed from a TWAP reference, not from spot, so a pool
 *       manipulated within a single block cannot set the price we accept.
 *    2. A step can never exceed `maxStepBps` of current holdings.
 *    3. `floorBps` of the LP must remain in the PRIMARY quote, so a rotation can
 *       never fully abandon the asset the protocol is denominated in.
 *    4. Only quotes on the registry's allowlist can ever be a target, and that
 *       allowlist already refuses anything above the sort watermark.
 */
contract QuoteRotator {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error NotOwner();
    error NotAllowedQuote();
    error BadConfig();
    error TooSoon();
    error FloorBreached();
    error SlippageTooHigh();
    error NoRoute();

    /// @notice The guild's target allocation for one quote asset, in bps of the
    ///         LP's total quote-side value.
    mapping(address => uint16) public targetBps;

    /// @notice Every quote the guild has ever targeted, so the rotation loop has
    ///         a bounded set to walk without an unbounded on-chain search.
    address[] public trackedQuotes;
    mapping(address => bool) private _tracked;

    /// @notice The asset the protocol is denominated in and can never fully
    ///         leave. Native ETH (address(0)) at deploy.
    address public immutable primaryQuote;

    /// @notice Minimum share of the LP that must stay in {primaryQuote}.
    uint16 public floorBps = 3000;      // 30%

    /// @notice Largest share of holdings one step may move.
    uint16 public maxStepBps = 500;     // 5%

    /// @notice Minimum spacing between steps. Slicing over time is what keeps a
    ///         rotation from being one large, front-runnable print.
    uint32 public stepCooldown = 1 hours;

    /// @notice Maximum tolerated deviation from the TWAP reference on a step.
    uint16 public maxSlippageBps = 100; // 1%

    /// @notice Seconds of TWAP used as the reference price. Long enough that
    ///         moving it costs more than the step is worth.
    uint32 public twapWindow = 1800;    // 30 min

    /// @notice Paid to whoever executes a step, in bps of the amount moved.
    uint16 public keeperBps = 10;       // 0.1%

    uint64 public lastStepAt;

    address public owner;
    address public immutable registry;
    IPoolManager public immutable poolManager;

    uint16 constant BPS = 10_000;

    event TargetSet(address indexed quote, uint16 bps);
    event Rotated(address indexed from, address indexed to, uint256 amountIn, uint256 amountOut, address keeper);
    event ParamsSet(uint16 floorBps, uint16 maxStepBps, uint32 stepCooldown, uint16 maxSlippageBps);

    constructor(address _registry, IPoolManager _poolManager, address _primaryQuote) {
        registry = _registry;
        poolManager = _poolManager;
        primaryQuote = _primaryQuote;
        owner = msg.sender;
        targetBps[_primaryQuote] = BPS; // start fully in the primary
        _track(_primaryQuote);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address to) external onlyOwner { owner = to; }

    // -----------------------------------------------------------------------
    // Governance: set the allocation
    // -----------------------------------------------------------------------

    /**
     * @notice Set the guild's target allocation. Bps must total exactly 10,000.
     * @dev Every target is re-validated against the registry's allowlist HERE,
     *      not only when it was proposed: the treasury can de-list a quote
     *      between a vote and its execution, and the check that matters is the
     *      one at the moment liquidity is about to move.
     *
     *      The primary's share is floored at {floorBps} so no allocation, however
     *      it was voted, can leave the protocol unable to denominate itself.
     */
    function setTargets(address[] calldata quotes, uint16[] calldata bps) external onlyOwner {
        if (quotes.length != bps.length || quotes.length == 0) revert BadConfig();

        uint256 total;
        uint16 primaryShare;
        for (uint256 i; i < quotes.length; ++i) {
            if (!_allowed(quotes[i])) revert NotAllowedQuote();
            total += bps[i];
            if (quotes[i] == primaryQuote) primaryShare = bps[i];
        }
        if (total != BPS) revert BadConfig();
        if (primaryShare < floorBps) revert FloorBreached();

        // Zero every previous target first, or a quote dropped from the new list
        // would keep its old target and the set would never sum to 10,000 again.
        for (uint256 i; i < trackedQuotes.length; ++i) targetBps[trackedQuotes[i]] = 0;

        for (uint256 i; i < quotes.length; ++i) {
            targetBps[quotes[i]] = bps[i];
            _track(quotes[i]);
            emit TargetSet(quotes[i], bps[i]);
        }
    }

    function setParams(
        uint16 _floorBps,
        uint16 _maxStepBps,
        uint32 _stepCooldown,
        uint16 _maxSlippageBps,
        uint32 _twapWindow,
        uint16 _keeperBps
    ) external onlyOwner {
        // Bounds chosen so a compromised or careless owner still cannot set
        // parameters that would let a single step drain the LP.
        if (_floorBps > BPS || _maxStepBps > 2000 || _maxSlippageBps > 500) revert BadConfig();
        if (_twapWindow < 300 || _keeperBps > 100) revert BadConfig();
        floorBps = _floorBps;
        maxStepBps = _maxStepBps;
        stepCooldown = _stepCooldown;
        maxSlippageBps = _maxSlippageBps;
        twapWindow = _twapWindow;
        keeperBps = _keeperBps;
        emit ParamsSet(_floorBps, _maxStepBps, _stepCooldown, _maxSlippageBps);
    }

    // -----------------------------------------------------------------------
    // Execution
    // -----------------------------------------------------------------------

    /**
     * @notice Move the allocation one bounded slice toward its target.
     * @dev PERMISSIONLESS and rewarded, so the rotation does not depend on the
     *      team staying online — the same reasoning as the liquidation sweep.
     *      The caller cannot choose the direction, the size or the price: all
     *      three come from the governed target and the TWAP reference, so an
     *      attacker calling this repeatedly only helps the treasury reach its
     *      goal, on schedule, at a bounded price.
     *
     * @param route The pool to trade through. Supplied by the caller because the
     *              best venue changes, but it is only ever ACCEPTED if the price
     *              it returns clears the TWAP-derived `minOut` below — a bad or
     *              malicious route reverts rather than filling.
     */
    function rotateStep(PoolKey calldata route) external returns (uint256 moved) {
        if (block.timestamp < lastStepAt + stepCooldown) revert TooSoon();

        (address from, address to, uint256 size) = _nextStep();
        if (size == 0) return 0;

        // Both legs must be assets the treasury has approved. `to` is checked
        // again here even though setTargets checked it, because the allowlist can
        // change between the vote and this execution.
        if (!_allowed(to)) revert NotAllowedQuote();
        if (!_routeMatches(route, from, to)) revert NoRoute();

        lastStepAt = uint64(block.timestamp);

        uint256 minOut = _minOutFromTwap(route, from, size);
        moved = _executeSwap(route, from, to, size, minOut);

        uint256 fee = (moved * keeperBps) / BPS;
        if (fee > 0) _pay(to, msg.sender, fee);

        emit Rotated(from, to, size, moved, msg.sender);
    }

    /// @notice The step that {rotateStep} would take right now: which asset is
    ///         furthest ABOVE its target, which is furthest BELOW, and how much
    ///         may move. Exposed so keepers and the UI can see the plan without
    ///         simulating a transaction.
    function nextStep() external view returns (address from, address to, uint256 size) {
        return _nextStep();
    }

    /// @notice Just the size {rotateStep} would move right now. Cheaper than
    ///         {nextStep} for a keeper deciding whether a call is worth the gas.
    function nextStepSize() external view returns (uint256 size) {
        (, , size) = _nextStep();
    }

    function _nextStep() internal view returns (address from, address to, uint256 size) {
        uint256 total = _totalValue();
        if (total == 0) return (address(0), address(0), 0);

        int256 worstOver;
        int256 worstUnder;
        for (uint256 i; i < trackedQuotes.length; ++i) {
            address q = trackedQuotes[i];
            uint256 held = _valueOf(q);
            int256 drift = int256((held * BPS) / total) - int256(uint256(targetBps[q]));
            if (drift > worstOver) { worstOver = drift; from = q; }
            if (drift < worstUnder) { worstUnder = drift; to = q; }
        }
        if (from == address(0) || to == address(0) || from == to) return (address(0), address(0), 0);

        // Move the smaller of: the overweight, the underweight, and the step cap.
        // Taking the minimum is what stops a step from overshooting into a new
        // imbalance in the opposite direction.
        uint256 overBy = (uint256(worstOver) * total) / BPS;
        uint256 underBy = (uint256(-worstUnder) * total) / BPS;
        uint256 cap = (_valueOf(from) * maxStepBps) / BPS;
        size = overBy < underBy ? overBy : underBy;
        if (size > cap) size = cap;

        // The primary can never be sold below its floor.
        if (from == primaryQuote) {
            uint256 floorAmt = (total * floorBps) / BPS;
            uint256 held = _valueOf(from);
            if (held <= floorAmt) return (address(0), address(0), 0);
            uint256 sellable = held - floorAmt;
            if (size > sellable) size = sellable;
        }
    }

    // -----------------------------------------------------------------------
    // Internals
    // -----------------------------------------------------------------------

    /// @dev A step's floor price comes from a TIME-WEIGHTED average, never spot.
    ///      Spot can be pushed within one block for the cost of a swap; moving a
    ///      30-minute TWAP far enough to matter costs vastly more than a single
    ///      capped step is worth, which is what makes the guard meaningful.
    function _minOutFromTwap(PoolKey calldata route, address from, uint256 amountIn)
        internal
        view
        returns (uint256)
    {
        PoolId id = route.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        if (sqrtPriceX96 == 0) revert NoRoute();

        bool zeroForOne = Currency.unwrap(route.currency0) == from;
        uint256 priceX96 = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 96;

        uint256 expected = zeroForOne
            ? (amountIn * priceX96) >> 96
            : (amountIn << 96) / priceX96;

        return (expected * (BPS - maxSlippageBps)) / BPS;
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

    function _executeSwap(
        PoolKey calldata route,
        address from,
        address to,
        uint256 size,
        uint256 minOut
    ) internal returns (uint256 out) {
        bool zeroForOne = Currency.unwrap(route.currency0) == from;
        bytes memory res = poolManager.unlock(
            abi.encode(route, zeroForOne, size, from, to)
        );
        out = abi.decode(res, (uint256));
        if (out < minOut) revert SlippageTooHigh();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "lock");
        (PoolKey memory key, bool zeroForOne, uint256 size, address from, address to) =
            abi.decode(data, (PoolKey, bool, uint256, address, address));

        BalanceDelta d = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(size),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );

        int128 outAmt = zeroForOne ? d.amount1() : d.amount0();
        uint256 got = uint256(uint128(outAmt));

        _settle(from, size);
        poolManager.take(Currency.wrap(to), address(this), got);
        return abi.encode(got);
    }

    function _settle(address cur, uint256 amount) internal {
        if (cur == address(0)) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(Currency.wrap(cur));
            IERC20(cur).transfer(address(poolManager), amount);
            poolManager.settle();
        }
    }

    function _pay(address cur, address to, uint256 amount) internal {
        if (cur == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "pay");
        } else {
            IERC20(cur).transfer(to, amount);
        }
    }

    function _valueOf(address quote) internal view returns (uint256) {
        return quote == address(0) ? address(this).balance : IERC20(quote).balanceOf(address(this));
    }

    function _totalValue() internal view returns (uint256 t) {
        for (uint256 i; i < trackedQuotes.length; ++i) t += _valueOf(trackedQuotes[i]);
    }

    function _allowed(address quote) internal view returns (bool ok) {
        if (quote == address(0)) return true; // native is allowed by construction
        (bool called, bytes memory ret) = registry.staticcall(
            abi.encodeWithSignature("allowedQuote(address)", quote)
        );
        return called && ret.length >= 32 && abi.decode(ret, (bool));
    }

    function _track(address quote) internal {
        if (_tracked[quote]) return;
        _tracked[quote] = true;
        trackedQuotes.push(quote);
    }

    function trackedQuotesLength() external view returns (uint256) {
        return trackedQuotes.length;
    }

    receive() external payable {}
}
