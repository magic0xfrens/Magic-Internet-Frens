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
    // ── TWAP ring, shared with PerpEngine ─────────────────────────────────
    //  The struct is declared HERE so the engine's `observations` storage array
    //  and this library's storage-reference parameter are the same type. The
    //  constants mirror the engine's (which it keeps for its own array length);
    //  they are inlined everywhere and must stay equal.
    struct Observation { uint32 ts; int56 tickCumulative; }
    uint16 internal constant OBS_CARDINALITY = 32;
    uint16 internal constant OBS_MASK = OBS_CARDINALITY - 1;
    uint32 internal constant MIN_TWAP = 1 seconds;
    /// @dev The ring's scalar state, grouped so it crosses into this library as
    ///      ONE storage reference. Packs into a single slot (20 bytes), exactly as
    ///      the five separate declarations it replaces already did.
    struct Ring {
        uint16 obsIndex;        // next slot to write
        int56 tickCumulative;   // sum of tick*dt up to lastObsTs
        uint32 lastObsTs;       // last time tickCumulative was INTEGRATED
        int24 lastTick;         // last observed tick — never left stale
        uint32 lastRingTs;      // last time a ring slot was WRITTEN
    }

    /// @dev Safety margin applied to the swap's INPUT before projecting, in bps.
    ///      A constant rather than an argument for the same EIP-170 reason as the
    ///      orientation above.
    ///
    ///      1500, not 500. Measured on the four-short cascade: at 500 the worst
    ///      case still charged PLV 25.81 mETH (at a 0.8 ETH buy, where the
    ///      settlements' own impact tips the last positions); at 1500 the charge
    ///      is ZERO at every size tested, and the over-liquidation scan STILL
    ///      finds no trade size that survives the real trade yet dies to the
    ///      projection. So this buys complete staker protection at no measured
    ///      cost to traders — which is the right way to spend the error budget,
    ///      since a trader consented to liquidation risk and a staker did not.
    uint256 internal constant SLACK_BPS = 1500;

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

    /**
     * @notice CONSERVATIVE projection of the pool price AFTER a pending swap, so a
     *         liquidation can happen BEFORE the trade that would cause the loss.
     *
     *  ── WHY THIS IS EXACT ENOUGH TO TRUST ──────────────────────────────────
     *  The active book is placed FULL RANGE (`PoolOps.SEED_BASE_WAD == 1e18`), so
     *  it behaves as constant product and the post-swap price has a closed form.
     *  With reserves E (quote) and T (token), price of token in quote is E/T:
     *
     *      BUY  (adds dE of quote):  P' = P * (1 + dE/E)^2   ->  sqrtP' = sqrtP * (1 + dE/E)
     *      SELL (adds dT of token):  P' = P / (1 + dT/T)^2   ->  sqrtP' = sqrtP / (1 + dT/T)
     *
     *  No tick-crossing integration is needed because there are no gaps to cross.
     *  If the book ever stops being full range this must be revisited — a banded
     *  book can teleport past an empty region and this projection would UNDERSTATE
     *  the move, which is the unsafe direction.
     *
     *  ── WHICH WAY IS SAFE TO BE WRONG ──────────────────────────────────────
     *  Deliberately biased toward projecting a LARGER move than will occur:
     *
     *    * `amountIn` is the GROSS input. The hook skims its fee in `beforeSwap`,
     *      so strictly less than this reaches the pool.
     *    * `slackBps` adds an explicit safety margin on top.
     *
     *  Over-projecting liquidates marginally EARLY; under-projecting lets a
     *  position pass through the trade and become bad debt that is socialised onto
     *  PLV stakers via `_absorbPlvLoss`. A leveraged trader consented to
     *  liquidation risk; a staker did not consent to underwriting it. So the error
     *  budget is spent on the trader's side, on purpose.
     *
     *  ── ORIENTATION ────────────────────────────────────────────────────────
     *  `sqrtPriceX96` is sqrt(currency1 per currency0), so which way a BUY moves it
     *  depends on which side the quote sits. Getting this backwards would liquidate
     *  exactly the wrong book, so it is passed in explicitly by the caller that
     *  already knows (`quoteIsCurrency0`) rather than re-derived here.
     *
     * @param sqrtP           current sqrtPriceX96
     * @param reserveIn       active depth of the asset being ADDED
     * @param reserveOut      active depth of the asset being TAKEN (exact-output)
     * @param amountSpecified v4's own signed amount: negative = exact input,
     *                        positive = exact output
     * @param isBuy           true when the QUOTE is the input (token gets dearer)
     * @param limit     the swap's own sqrtPriceLimitX96; 0 = none
     * @return projected sqrtPriceX96, clamped to the limit and TickMath's range
     */
    function projectedSqrtPriceX96(
        uint160 sqrtP,
        uint256 reserveIn,
        uint256 reserveOut,
        int256 amountSpecified,
        bool isBuy,
        uint160 limit
    ) external pure returns (uint160) {
        //  ── BOTH SWAP SHAPES, ONE CLOSED FORM ───────────────────────────────
        //  Negative `amountSpecified` is exact-INPUT and already IS the input.
        //  Positive is exact-OUTPUT, and under constant product the input it will
        //  cost is just as closed-form: taking `dOut` out of `reserveOut` costs
        //      dIn = reserveIn * dOut / (reserveOut - dOut)
        //  rounded UP. An output at or beyond the whole reserve is clamped to
        //  `reserveIn`, the same 2x-ratio cap the exact-input branch uses and
        //  justified there.
        //
        //  Handling exact-output here rather than refusing it is what keeps the
        //  hook ROUTABLE: reverting on `SWAP_EXACT_OUT_SINGLE` would fail the
        //  Universal Router and every aggregator that quotes exact-output.
        uint256 amountIn;
        if (amountSpecified < 0) {
            amountIn = uint256(-amountSpecified);
        } else if (amountSpecified > 0) {
            uint256 dOut = uint256(amountSpecified);
            amountIn = (reserveOut == 0 || dOut >= reserveOut)
                ? reserveIn
                : FullMath.mulDivRoundingUp(reserveIn, dOut, reserveOut - dOut);
        }
        //  ORIENTATION IS AN INVARIANT HERE, NOT A PARAMETER. The registry's quote
        //  watermark keeps every allowed quote sorting below every mined iteration
        //  token, and `PerpEngine._key()` pins the quote to currency0 — so
        //  `quoteIsCurrency0` is always true for these pools. `quoteAt` in this same
        //  library already bakes in the same assumption. Passing it cost ABI
        //  marshalling in the engine, which is at its EIP-170 ceiling, for a
        //  degree of freedom the protocol does not actually have.
        bool quoteIsCurrency0 = true;
        uint256 slackBps = SLACK_BPS;
        //  No price, or a reserve we cannot trust, means no projection we can
        //  stand behind. Return the CURRENT price so the caller degrades to
        //  "liquidate only what is already underwater" rather than acting on a
        //  fabricated number.
        if (sqrtP == 0 || reserveIn == 0 || amountIn == 0) return sqrtP;

        //  ratio = 1 + (amountIn * (1 + slack)) / reserveIn, in 1e18 fixed point.
        uint256 inflated = amountIn + FullMath.mulDiv(amountIn, slackBps, 10_000);
        //  Cap the modelled input at the reserve, i.e. at a 2x ratio (4x in price).
        //  This is the one place the projection knowingly UNDERSTATES — a trade
        //  larger than the reserve moves price further than 4x — and it is safe
        //  because 4x already exceeds any move a leveraged position can survive:
        //  a short's backing is at most 2x its notional, so 4x is insolvent; a
        //  long at 2x or more has principal >= half its notional, so a 4x fall is
        //  under water; and a 1x long has no debt to liquidate. Every position
        //  the cap could hide is one it trips anyway. What the cap buys is
        //  arithmetic that stays well conditioned for absurd nominals.
        if (inflated > reserveIn) inflated = reserveIn;
        //  ROUND THE RATIO UP, ALWAYS. Truncation is not neutral here: it shrinks
        //  the projected move, which is the one direction this function must never
        //  err in. Caught by LIQ-02.2, where the sell projection undershot the real
        //  move by ~3.5e-16 relative — tiny, but a bound that fails at zero slack
        //  is not a bound, and relying on `slackBps` to paper over an arithmetic
        //  bias would hide the bias rather than fix it.
        //
        //  A LARGER ratio is conservative on BOTH branches: it multiplies the "up"
        //  case further up, and divides the "down" case further down.
        uint256 ratio = 1e18 + FullMath.mulDivRoundingUp(inflated, 1e18, reserveIn);

        //  A BUY makes the token dearer in quote terms. Whether that RAISES or
        //  LOWERS sqrtPriceX96 depends on orientation: with the quote as
        //  currency0 the price is "token per quote", which FALLS as the token
        //  gets dearer.
        bool up = isBuy ? !quoteIsCurrency0 : quoteIsCurrency0;

        //  Same reasoning applied to the final multiply: round AWAY from the
        //  current price on each branch. The "down" branch already truncates in
        //  the safe direction, so it stays a plain mulDiv.
        uint256 out = up
            ? FullMath.mulDivRoundingUp(uint256(sqrtP), ratio, 1e18)
            : FullMath.mulDiv(uint256(sqrtP), 1e18, ratio);

        //  ── THE TRADE CANNOT MOVE PRICE PAST ITS OWN LIMIT ─────────────────
        //  Without this clamp a swap with a huge `amountSpecified` and a limit at
        //  spot would fill NOTHING yet project an enormous move — liquidating every
        //  position on one side for the price of gas. The limit is a hard bound
        //  the PoolManager enforces, so clamping to it keeps the projection a real
        //  bound rather than a griefing lever. Only honoured when the limit sits
        //  on the trade's side of spot; a limit on the wrong side makes the swap
        //  itself revert (`PriceLimitAlreadyExceeded`), taking any pre-sweep
        //  liquidations with it, so it is simply ignored here.
        if (limit != 0) {
            if (up ? (limit > sqrtP && out > limit) : (limit < sqrtP && out < limit)) out = limit;
        }
        uint256 lo = uint256(TickMath.MIN_SQRT_PRICE) + 1;
        uint256 hi = uint256(TickMath.MAX_SQRT_PRICE) - 1;
        if (out < lo) out = lo;
        if (out > hi) out = hi;
        return uint160(out);
    }

    /**
     * @notice The liquidation mark: time-weighted average tick over `window`.
     *         {PerpEngine.twapTick}'s body, moved here for EIP-170 headroom.
     *
     *  Storage-reference extraction: the 32-slot ring arrives as ONE word of
     *  calldata, the five scalars as five more. Same algorithm, same results —
     *  every TWAP-dependent test in the suite is the differential check.
     */
    function twapTick(
        Observation[OBS_CARDINALITY] storage observations,
        Ring storage r,
        uint32 twapWindow
    ) external view returns (int24 tick, bool ok) {
        uint16 next = r.obsIndex;
        int56 tickCumulative = r.tickCumulative;
        int24 lastTick = r.lastTick;
        uint32 lastObsTs = r.lastObsTs;
        uint32 nowTs = uint32(block.timestamp);
        if (nowTs <= MIN_TWAP) return (0, false);
        uint32 target;
        unchecked { target = nowTs - twapWindow; }
        uint16 n;      // how many observations are populated
        uint16 start;  // physical index of the OLDEST
        if (observations[next & OBS_MASK].ts != 0) {
            n = OBS_CARDINALITY; start = next;   // wrapped: `next` is the oldest
        } else {
            n = next; start = 0;                 // not yet wrapped: 0..next-1
        }
        if (n == 0) return (0, false);
        uint32 useTs; int56 useCum;
        Observation memory oldest = observations[start];
        if (oldest.ts > target) {
            unchecked { if (nowTs - oldest.ts < MIN_TWAP) return (0, false); }
            useTs = oldest.ts; useCum = oldest.tickCumulative;
        } else {
            uint16 lo; uint16 hi = n - 1;
            while (lo < hi) {
                uint16 mid = (lo + hi + 1) >> 1;
                if (observations[(start + mid) & OBS_MASK].ts <= target) lo = mid;
                else hi = mid - 1;
            }
            Observation memory best = observations[(start + lo) & OBS_MASK];
            useTs = best.ts; useCum = best.tickCumulative;
        }
        int56 cumNow;
        int56 span;
        unchecked {
            cumNow = tickCumulative + int56(lastTick) * int56(uint56(nowTs - lastObsTs));
            span = int56(uint56(nowTs - useTs));
        }
        if (span == 0) return (0, false);
        tick = int24((cumNow - useCum) / span);
        ok = true;
    }

    /**
     * @notice Integrate the tick since the last call and, if `obsInterval` has
     *         elapsed, write a ring slot. {PerpEngine._writeObs}'s body.
     *
     *  `currentTick` is passed in rather than read here because only the engine
     *  knows its mark source; it is evaluated before the call, which yields the
     *  same value the original read after the ring write (a pure view of pool /
     *  mark state that the write does not touch).
     */
    function writeObs(
        Observation[OBS_CARDINALITY] storage observations,
        Ring storage r,
        uint32 obsInterval,
        int24 currentTick
    ) external {
        uint32 nowTs = uint32(block.timestamp);
        unchecked {
            uint32 dt = nowTs - r.lastObsTs;
            if (dt > 0) {
                r.tickCumulative += int56(r.lastTick) * int56(uint56(dt));
                r.lastObsTs = nowTs;
            }
            if (nowTs - r.lastRingTs >= obsInterval) {
                observations[r.obsIndex] = Observation(nowTs, r.tickCumulative);
                r.obsIndex = (r.obsIndex + 1) & OBS_MASK;
                r.lastRingTs = nowTs;
            }
        }
        r.lastTick = currentTick; // ALWAYS refresh — never leave a stale tick
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
        return _spend(sp, L, budget, down);
    }

    /**
     * @notice The DEAD-PATH PRICE BAND, as a sqrt-price limit.
     *
     *  ── WHY A LIMIT AND NOT A REVERT (red-team T3d x LIQ-02) ───────────────
     *  The first cut of the band REVERTED when a forced close realised a price
     *  more than 10% off the engine's TWAP mark. That closed T3d (a stranger
     *  force-closing a SOLVENT position at any price for the keeper cut) but
     *  re-opened LIQ-02: a short bigger than the pool's token side can only ever
     *  be cleared in bites, and its terminal bite is on the DEATH path, so a
     *  reverting band made the book unclearable and blocked the relaunch
     *  (XL1_LiqTwapAndDepthCap:520). Both properties hold at once if the band is
     *  a PRICE LIMIT instead: the pool fills whatever it can INSIDE the band, the
     *  remainder rebooks (or, on the terminal death path, is written off by name),
     *  and nobody is ever filled outside the band. Same shape as {spendLimit},
     *  which is already how LIQ-02 was closed.
     *
     *  ── THE ARITHMETIC ─────────────────────────────────────────────────────
     *  {PerpEngine._quoteAt} values a position at `size·(Q96/sp)²`, so VALUE moves
     *  with the inverse SQUARE of the sqrt price and a ±10% value band is a
     *  1/√(1±0.1) sqrt-price band:
     *    selling  — proceeds must clear 90% of mark  → sp ≤ mark·√(1/0.90) = 1.054093
     *    buying   — cost must stay under 110% of mark → sp ≥ mark·√(1/1.10) = 0.953463
     *
     * @param mark the engine's TWAP mark sqrt price. ZERO disables the band and
     *        returns 0 (= the direction's extreme), which is the pre-band behaviour.
     * @param sp   the live sqrt price. When it is ALREADY outside the band the
     *        limit is pinned one wei away from it, so the swap fills ~nothing
     *        rather than reverting — the caller's partial-fill path takes over.
     * @param buy  true = acquiring the token (price moves DOWN, the band is a
     *        FLOOR); false = selling it (price moves UP, the band is a CEILING).
     */
    /// @param quoteIsCurrency0 the engine's value convention (`value ∝ (Q96/sp)²`,
    ///        {PerpEngine._quoteAt}) only holds while the quote sorts FIRST. On a
    ///        pool where an ERC20 quote sorts second it is already inverted, and a
    ///        limit on the wrong side of the live price would make v4 revert the
    ///        settle and brick the book — so that configuration gets NO band and
    ///        keeps exactly its pre-band behaviour. Gated here rather than in the
    ///        engine, which has double-digit bytes of EIP-170 headroom.
    function bandLimit(uint160 mark, uint160 sp, bool buy, bool quoteIsCurrency0)
        external
        pure
        returns (uint160)
    {
        return quoteIsCurrency0 ? _band(mark, sp, buy) : 0;
    }

    /**
     * @notice The limit a bounded exact-output BUY-BACK must respect: the TIGHTER
     *         of what the budget can pay for ({spendLimit}) and what the mark band
     *         permits ({bandLimit}). Folded into one call so {PerpEngine._buyUpTo}
     *         pays for one external hop instead of two plus the comparison
     *         (EIP-170 — the engine has double-digit bytes of headroom).
     *
     *  A buy moves the price DOWN when the quote is currency0, so "tighter" is the
     *  HIGHER sqrt price. `mark == 0` means the caller did not ask for a band.
     */
    /// @param band an ALREADY-COMPUTED {bandLimit} (0 = no band). Deliberately not
    ///        the raw mark: the caller has it, and re-deriving it here once applied
    ///        the 0.953463 factor a SECOND time and silently tightened the band to
    ///        ~91% of the mark.
    function closeLimit(uint160 sp, uint128 L, uint256 budget, bool down, uint160 band)
        external
        pure
        returns (uint160)
    {
        uint160 lim = _spend(sp, L, budget, down);
        return band > lim ? band : lim;
    }

    function _band(uint160 mark, uint160 sp, bool buy) private pure returns (uint160) {
        if (mark == 0 || sp == 0) return 0;
        uint256 r = (uint256(mark) * (buy ? 953463 : 1054093)) / 1e6;
        if (buy) {
            // Price moves DOWN into the band, so the limit is a FLOOR.
            if (r >= uint256(sp)) return sp - 1;        // already past it: fill ~nothing
            return uint160(r < MIN_LIMIT ? MIN_LIMIT : r);
        }
        // Price moves UP into the band, so the limit is a CEILING.
        if (r <= uint256(sp)) return sp + 1;            // already past it: fill ~nothing
        return uint160(r >= SQRT_MAX ? SQRT_MAX - 1 : r);
    }

    function _spend(uint160 sp, uint128 L, uint256 budget, bool down)
        private
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
