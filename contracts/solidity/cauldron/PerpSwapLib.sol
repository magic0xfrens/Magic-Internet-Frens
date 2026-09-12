// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {ILiquidatorMintable, LiqStats} from "./ILiquidatorMintable.sol";

/**
 * @title PerpSwapLib
 * @notice The perp engine's pool-swap leg, lifted out of {PerpEngine}.
 *
 *  A LINKED library — `external`, so Solidity deploys it separately and reaches
 *  it by `delegatecall`. It runs in the engine's context: `address(this)` is the
 *  engine, settled value comes from the engine's balance, and taken currency
 *  lands on the engine. Behaviour is identical to the inlined version.
 *
 *  Why it moved: PerpEngine was 536 bytes over the EIP-170 limit BEFORE any
 *  quote work — already undeployable, and not caught by `forge script`, which
 *  does not enforce code size in simulation.
 *
 *  Holds no state. Every position, balance and accounting write stays in the
 *  engine.
 */
library PerpSwapLib {
    uint256 internal constant Q96X = 0x1000000000000000000000000;

    /// @notice `10**decimals()` of `q`, read defensively; 1e18 for native or for any
    ///         token that has no `decimals()` or answers nonsense. Here for EIP-170:
    ///         the encode + staticcall + decode is ~120 B and {PerpEngine} calls it
    ///         once, on the cold rotation path.
    function unitOf(address q) external view returns (uint256) {
        return _unitOf(q);
    }

    function _unitOf(address q) private view returns (uint256) {
        if (q == address(0)) return 1e18;
        (bool ok, bytes memory ret) = q.staticcall(abi.encodeWithSignature("decimals()"));
        if (!ok || ret.length < 32) return 1e18;
        uint256 d = abi.decode(ret, (uint256));
        return d > 36 ? 1e18 : 10 ** d;
    }

    /**
     * @notice How many RAW units of `q` carry the same VALUE as 1e18 wei of ether,
     *         1e18-scaled. {PerpEngine._q} multiplies its wei-written thresholds by
     *         this, so `_q(25 ether)` means "25 ether WORTH of `q`".
     *
     *  ── A UNIT COUNT IS NOT A VALUE (red-team F-03) ────────────────────────
     *  The engine used `unitOf` here, which answers a different question: it turned
     *  "25 ether of pool depth" into 25e6 raw units of a 6-decimal stable — $25 —
     *  and with it switched off the leverage tiering, the dust filter and the
     *  insurance circuit breaker on every non-ether-quoted generation. Decimals
     *  carry no price, so the price has to come from the oracle the protocol
     *  already runs. `usdPerRawUnit` is 1e18-scaled USD per RAW unit, which already
     *  contains the decimals, so the ratio of the two legs is the whole answer.
     *
     *  Here rather than in the engine for EIP-170: two encodes, two staticcalls and
     *  two decodes, on the cold rotation path, against single-digit headroom there.
     *
     * @param oracle {QuoteOracle}, or zero when none is wired.
     * @return f Never 0 — an unpriceable quote falls back to its unit count, and a
     *         unit count below 1e6 (a degenerate or hostile `decimals()`, including
     *         0, which would drive every threshold to exactly zero) falls back to
     *         1e18. The fallback is STRICTER than the truth for a cheap quote, which
     *         is the safe direction for a protection: it can only over-apply, and
     *         governance can retune every one of these thresholds by hand.
     */
    function quoteFactor(address oracle, address q) external view returns (uint256 f) {
        if (q == address(0)) return 1e18;
        if (oracle != address(0)) {
            uint256 pNative = _usdPerRawUnit(oracle, address(0));
            uint256 pQuote = _usdPerRawUnit(oracle, q);
            //  0 means "cannot judge" (QuoteOracle.sol:200), never "free".
            if (pNative != 0 && pQuote != 0) {
                f = FullMath.mulDiv(1e18, pNative, pQuote);
                if (f != 0) return f;
            }
        }
        f = _unitOf(q);
        if (f < 1e6) f = 1e18;
    }

    function _usdPerRawUnit(address oracle, address q) private view returns (uint256) {
        (bool ok, bytes memory ret) =
            oracle.staticcall(abi.encodeWithSignature("usdPerRawUnit(address)", q));
        if (!ok || ret.length < 32) return 0;
        return abi.decode(ret, (uint256));
    }

    /// @notice tick -> sqrtPriceX96.
    ///
    ///  Here for EIP-170 headroom, and it is the single biggest win available:
    ///  `TickMath` is an INTERNAL library whose `getSqrtPriceAtTick` body is a long
    ///  chain of magic-constant multiplications, so {PerpEngine} was inlining the
    ///  whole thing for its ONE call site while sitting at the ceiling. Pure, one
    ///  value argument, identical result.
    function sqrtPriceAtTick(int24 t) external pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(t);
    }

    /// @notice Best-effort Liquidatoor badge mint: the stats-bearing mint first, the
    ///         pre-stats `mintLiquidator` as a fallback for a collection deployed
    ///         before stats existed. Reports rather than reverting, so a liquidation
    ///         is never taken down by its own reward.
    ///
    ///  Here for EIP-170 headroom — two `abi.encodeWithSelector`s (one carrying a
    ///  struct, so a full memory encode) plus two gas-metered calls was the largest
    ///  self-contained block left in {PerpEngine}, and it takes only value
    ///  arguments. As an EXTERNAL library function this runs by DELEGATECALL, so the
    ///  collection still sees the ENGINE as `msg.sender`, which every mint gate
    ///  depends on. `gasleft()` inside the delegatecall is 63/64 of the engine's and
    ///  both thresholds carry six-figure margins, so the fall-through is unchanged;
    ///  the floor below makes the subtraction safe on its own rather than relying on
    ///  the caller's guard.
    function tryMintBadge(address col, address to, LiqStats memory st) external returns (bool ok) {
        if (col.code.length == 0 || gasleft() < 200_000) return false;
        uint256 fwd;
        unchecked { fwd = gasleft() - 120_000; }
        (ok, ) = col.call{gas: fwd}(
            abi.encodeWithSelector(ILiquidatorMintable.mintLiquidatorWithStats.selector, to, st)
        );
        if (!ok && gasleft() > 200_000) {
            unchecked { fwd = gasleft() - 120_000; }
            (ok, ) = col.call{gas: fwd}(
                abi.encodeWithSelector(ILiquidatorMintable.mintLiquidator.selector, to)
            );
        }
    }

    /// @notice token size -> quote value at `sp`. {PerpEngine._quoteAt}'s body.
    ///
    ///  These three live here purely for EIP-170 headroom. `FullMath.mulDiv` is an
    ///  INTERNAL library, so every call site inlined its assembly: six copies in
    ///  PerpEngine, which is at the ceiling, versus one here where there are
    ///  kilobytes. Pure value arguments, no storage, so the move is mechanical.
    function quoteAt(uint256 size, uint256 sp) external pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(size, Q96X, sp), Q96X, sp);
    }

    /// @notice quote amount -> token amount at `sp`. {PerpEngine._ethToToken}'s body.
    function ethToToken(uint256 eth, uint256 sp) external pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(eth, sp, Q96X), sp, Q96X);
    }

    /// @notice Active quote-side depth of a pool from its liquidity and sqrt price.
    ///         {PerpEngine.activeEthDepth}'s body.
    function ethDepth(uint128 L, uint160 sp) external pure returns (uint256) {
        if (sp == 0 || L == 0) return 0;
        uint256 term = FullMath.mulDiv(uint256(L), uint256(SQRT_MAX) - sp, uint256(SQRT_MAX));
        return FullMath.mulDiv(term, Q96X, sp);
    }

    /// @notice ERC20 `transfer` with the return value CHECKED, REPORTING failure
    ///         instead of reverting.
    ///
    ///  Lives here rather than inline in {PerpEngine} for EIP-170 headroom: the
    ///  engine had three byte-identical copies of `encodeWithSelector` + `call` +
    ///  decode, and the engine is 67 bytes from the limit while this library has
    ///  kilobytes. `external`, so it is a DELEGATECALL from the engine — the token
    ///  still sees the engine as `msg.sender`, which is what every caller needs.
    ///
    ///  Reporting rather than reverting is load-bearing, not stylistic: a
    ///  blacklistable token (true of most tokenized equities) can make ONE
    ///  recipient permanently unpayable, and a non-standard token returns false
    ///  rather than reverting. Callers that must not be griefed by either
    ///  ({PerpEngine._payOut}, {PerpEngine.retirePayout}) need the boolean;
    ///  callers that should abort ({PerpEngine._safeTransfer}) revert on it.
    function tryTransferFrom(address token, address from, uint256 amount) external returns (bool) {
        (bool called, bytes memory ret) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount)
        );
        return called && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    /// @notice Twin of {tryTransferFrom} for plain `transfer`. See that note.
    function tryTransfer(address token, address to, uint256 amount) external returns (bool) {
        (bool called, bytes memory ret) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        return called && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    /// @notice One leg of a perp's pool interaction.
    /// @param buy       true = acquire the iteration token (pay the quote in)
    /// @param exactOut  true = `amount` is the exact TOKEN out; else exact quote in
    /// @param amount    the specified side's amount
    struct Req {
        bool buy;
        bool exactOut;
        uint256 amount;
        /// @notice sqrtPrice the swap may not pass. 0 = the direction's extreme,
        ///         i.e. the historical behaviour. See {spendLimit}.
        uint160 limit;
    }

    /**
     * @notice Execute one leg and settle both sides.
     * @param quoteIsCurrency0 which side of the pool is the QUOTE.
     *
     *  v4 orders currencies by address. Native ETH is `address(0)` and always
     *  sorts first, so "quote = currency0" held for free; an ERC20 quote sorts
     *  against a CREATE-deployed token and lands on either side. Passed in
     *  rather than re-derived here so the engine and this library can never
     *  disagree about which leg is which — that disagreement would make a long
     *  sell and read the deltas backwards.
     *
     * @return spent the amount paid in
     * @return got   the amount received
     */
    function swapLeg(
        IPoolManager poolManager,
        PoolKey memory key,
        Req memory r,
        bool quoteIsCurrency0,
        bytes memory hookData
    ) external returns (uint256 spent, uint256 got) {
        Currency quote = quoteIsCurrency0 ? key.currency0 : key.currency1;
        Currency tok = quoteIsCurrency0 ? key.currency1 : key.currency0;

        // A BUY pays the quote in for the token out, which is `zeroForOne` only
        // while the quote is currency0. The price limit follows the resulting
        // direction, not the intent.
        bool z = r.buy == quoteIsCurrency0;
        //  A CALLER-SUPPLIED LIMIT IS WHAT MAKES AN EXACT-OUTPUT BUY SAFE.
        //  With the direction's extreme as the only limit, an exact-output buy for
        //  more token than the pool can supply walks the price to MIN_SQRT_PRICE
        //  and the quote leg either overflows v4's own int128 accounting
        //  (`SafeCastOverflow`) or asks for more value than the caller holds. Both
        //  make the position UNCLOSABLE at every privilege level. A finite limit
        //  turns that into a PARTIAL fill, which the caller can repeat.
        //  See {PerpEngine._buyUpTo}. (red-team LIQ-02)
        uint160 limit = r.limit != 0 ? r.limit : (z ? MIN_LIMIT : SQRT_MAX - 1);

        int256 spec;
        if (r.buy) {
            // exactOut → positive (exact token out); else negative (exact quote in)
            spec = r.exactOut ? int256(r.amount) : -int256(r.amount);
        } else {
            spec = -int256(r.amount);
        }

        BalanceDelta d = poolManager.swap(
            key,
            SwapParams({zeroForOne: z, amountSpecified: spec, sqrtPriceLimitX96: limit}),
            hookData
        );

        // The quote leg is amount0 when the quote is currency0, else amount1.
        int128 quoteAmt = quoteIsCurrency0 ? d.amount0() : d.amount1();
        int128 tokAmt = quoteIsCurrency0 ? d.amount1() : d.amount0();

        if (r.buy) {
            spent = uint256(uint128(-quoteAmt));
            got = uint256(uint128(tokAmt));
            _settle(poolManager, quote, spent);
            if (got > 0) poolManager.take(tok, address(this), got);
        } else {
            spent = uint256(uint128(-tokAmt));
            got = uint256(uint128(quoteAmt));
            _settle(poolManager, tok, spent);
            if (got > 0) poolManager.take(quote, address(this), got);
        }
    }

    /// @dev Pay what we owe. Native settles with value; an ERC20 settles by
    ///      sync-transfer-settle, which is the v4 flow for token currencies.
    function _settle(IPoolManager poolManager, Currency c, uint256 amount) private {
        if (amount == 0) return;
        if (Currency.unwrap(c) == address(0)) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(c);
            //  Return value CHECKED: a token that returns false instead of
            //  reverting would leave the settle short, and v4 requires deltas to
            //  net to zero at unlock close — so the failure would surface as the
            //  USER's swap reverting, with no clue why.
            (bool ok, bytes memory ret) = Currency.unwrap(c).call(
                abi.encodeWithSelector(IERC20.transfer.selector, address(poolManager), amount)
            );
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer");
            poolManager.settle();
        }
    }

    /// @notice Convert the engine's leftover balance of a DEAD generation's token
    ///         into the live one, 1:1, via the registry's burn-claim.
    /// @dev CAPACITY-AWARE (audit H-03): claims as much as the reserve can
    ///      actually deliver. The strict `claimByBurn` reverts on a thin reserve
    ///      and would strand the engine holding a dead token.
    ///
    ///      Best-effort by design — if migration is unavailable the caller keeps
    ///      the old inventory and the owner can re-seed, rather than the sync
    ///      reverting and leaving the engine armed on a dead generation.
    /// @notice A dead-generation inventory migration moved LESS than the engine
    ///         held — `stranded` of `oldToken` is still sitting in the engine and
    ///         is no longer counted as token principal. `reason` is the raw revert
    ///         data when the claim reverted outright, empty when it merely came up
    ///         short against a thin reserve.
    /// @dev Emitted from a delegatecalled library, so the log carries the PERP
    ///      ENGINE's address — which is what an operator or indexer watches.
    event InventoryMigrationShortfall(
        uint256 indexed fromGen, address indexed oldToken, uint256 stranded, bytes reason
    );

    function migrateInventory(address registry, address oldToken, uint256 fromGen)
        external
        returns (uint256 migratedIn)
    {
        uint256 oldBal = IERC20(oldToken).balanceOf(address(this));
        if (oldBal == 0) return 0;
        (bool ok, bytes memory ret) = registry.call(
            abi.encodeWithSignature("claimByBurnUpTo(uint256,uint256)", fromGen, oldBal)
        );
        if (ok && ret.length >= 32) migratedIn = abi.decode(ret, (uint256));
        //  A FAILED MIGRATION MUST BE LOUD.
        //  `syncGeneration` re-points `plvToken` at the engine's balance of the NEW
        //  token the instant this returns, so whatever does NOT migrate is token
        //  principal that disappears from the LP's books with no error anywhere.
        //  That is not hypothetical: when the registry's `claimByBurnUpTo` body
        //  moved to {RedemptionExt}, a registry without that facet wired answered
        //  `NotConfigured()` here, this returned 0, and the engine's whole token
        //  side went to zero silently.
        //  Reverting is still not an option — the sync runs inside relaunch's
        //  try/catch and a revert would leave the engine armed on a dead
        //  generation (the reason this is best-effort in the first place). So
        //  RECORD the shortfall instead: the operator sees the amount and the raw
        //  reason, the stranded balance is still in the engine, and the token side
        //  is re-seeded with `fundPlvToken` once the cause is fixed.
        if (migratedIn < oldBal) {
            emit InventoryMigrationShortfall(fromGen, oldToken, oldBal - migratedIn, ok ? bytes("") : ret);
        }
    }

    /**
     * @notice The sqrtPrice at which spending `budget` of the QUOTE against
     *         constant liquidity `L` from `sp` would be exhausted — i.e. the price
     *         limit that caps a buy's cost at `budget`.
     *
     *  Here rather than in {PerpEngine} for EIP-170: two `FullMath.mulDiv` bodies
     *  inline their whole assembly at every call site, and the engine is at the
     *  ceiling. Pure, four scalar arguments.
     *
     * @param down true when the QUOTE is currency0, so paying quote in moves the
     *        pool price DOWN; false when it moves UP.
     * @return The limit, clamped into v4's representable range. Never 0, so the
     *         caller can always pass it straight through as {Req.limit}.
     *
     *  THE BOUND IS EXACT WHILE LIQUIDITY IS CONSTANT and CONSERVATIVE when the
     *  swap crosses into a THINNER band — which is the case that matters, because
     *  a thin band is what makes a buy-back unaffordable in the first place.
     *  Crossing into a DEEPER band costs more to reach the same price, but a
     *  deeper band is also one where the buy-back was affordable to begin with.
     */
    function spendLimit(uint160 sp, uint128 L, uint256 budget, bool down)
        external
        pure
        returns (uint160)
    {
        if (sp == 0 || L == 0) return down ? MIN_LIMIT : SQRT_MAX - 1;
        if (down) {
            // amount0 in = L * (Q96/sp' - Q96/sp)  =>  sp' = Q96*L / (Q96*L/sp + budget)
            uint256 a = FullMath.mulDiv(Q96X, uint256(L), uint256(sp));
            uint256 r = FullMath.mulDiv(Q96X, uint256(L), a + budget);
            return uint160(r < MIN_LIMIT ? MIN_LIMIT : (r >= uint256(sp) ? uint256(sp) - 1 : r));
        }
        // amount1 in = L * (sp' - sp) / Q96  =>  sp' = sp + budget*Q96/L
        uint256 up = uint256(sp) + FullMath.mulDiv(budget, Q96X, uint256(L));
        return uint160(up >= SQRT_MAX ? SQRT_MAX - 1 : up);
    }

    uint160 internal constant MIN_LIMIT = 4295128740;
    uint160 internal constant SQRT_MAX = 1461446703485210103287273052203988822378723970342;
}
