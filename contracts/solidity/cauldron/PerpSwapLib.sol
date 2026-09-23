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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev An open perp position. Declared at FILE level rather than inside
///      {PerpEngine} so {PerpSwapLib.requoteBook} can take the engine's `positions`
///      mapping as a storage reference. Same fields, same order, same storage
///      layout — the struct moved, nothing about it changed.
struct Position {
    address trader;
    bool    isLong;
    uint128 collateral;   // quote stake (net of open fee)
    uint256 size;         // token: long → held; short → owed
    uint256 principal;    // long → quote borrowed; short → quote proceeds held
    uint64  openedAt;
    uint8   leverage;
    int256  entryFunding; // funding index snapshot at open
}

/// @dev The engine's own getters, read by {PerpSwapLib.requoteBook} through a
///      self-call because the engine has no bytes to pass them in.
interface IRequoteEngine {
    function quote() external view returns (address);
    function vault() external view returns (address);
    function registry() external view returns (address);
    function syncedGeneration() external view returns (uint256);
    function payoutOwedTotal() external view returns (uint256);
    function owner() external view returns (address);
    function treasury() external view returns (address);
    function poke() external;
}

interface IVaultQuoteStake {
    function hasQuoteStake() external view returns (bool);
}

interface IRequoteRegistry {
    function currentGeneration() external view returns (uint256);
    function generationQuote(uint256 gen) external view returns (address);
}

/// @dev The {QuoteRotator} surface {PerpSwapLib.requoteBook} converts through.
interface IRequoteRotator {
    function quoteOracle() external view returns (address);
    function venueFor(address a, address b) external view returns (PoolKey memory route, bool ok);
    function swapOnce(PoolKey calldata route, address from, address to, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 out);
    function withdraw(address asset, address to, uint256 amount) external;
}

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
        return _quoteFactor(oracle, q);
    }

    function _quoteFactor(address oracle, address q) private view returns (uint256 f) {
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

    // ═══════════════════════════════════════════════════════════════════════
    //  CARRY THE BOOK ACROSS A QUOTE ROTATION (rotation totality, 2026-09-23)
    // ═══════════════════════════════════════════════════════════════════════

    /// Only the registry (the rotation's flip) may carry the book.
    error RequoteNotRegistry();
    /// The rotator's oracle cannot price one side, so no claim can be restated.
    error RequoteUnpriced();
    /// Settlement payouts are owed in the old asset to addresses no loop can reach.
    error RequotePayoutsOwed();
    /// The vault refused to re-express its own ledger — nothing may move without it.
    error RequoteVault();
    /// The conversion did not deliver what it reported.
    error RequoteShort();

    /**
     * @notice Re-denominate the WHOLE perp book into the generation's new quote,
     *         with positions still open. Called by {PerpEngine.requoteBook}, which
     *         the registry calls at a rotation's flip; DELEGATECALLed, so
     *         `address(this)` is the engine and this code runs on its storage.
     *
     *  ── WHY (red-team D-1) ────────────────────────────────────────────────
     *  The engine used to refuse a new quote while any position was open, so the
     *  flip PARKED it and made the book force-closeable — against the old pool,
     *  which the rotation had just drained of ~97% of its liquidity. Measured
     *  (F14c): a solvent long force-sold into that depth was paid 0 and the short
     *  that closed after it made +0.78 ETH; insurance covered the gap. Carrying
     *  the book removes the forced sale entirely: positions keep living on the
     *  NEW pool and close there, in the new asset, whenever their owner (or an
     *  honest liquidation) decides.
     *
     *  ── WHAT MOVES, AND AT WHICH RATE ─────────────────────────────────────
     *   tokens (long `size` held, short `size` owed)  untouched — both pools trade
     *                                                 the same generation token
     *   money the engine HOLDS in the old quote:      SWAPPED once, together, and
     *     plv, each short's collateral + proceeds,    each re-expressed at the rate
     *     insuranceEth, tokYieldEth                   the swap actually REALIZED
     *   claims that are NOT money:                    RESTATED at the ORACLE rate —
     *     each long's principal and collateral,       that ETH already bought the
     *     longOiEth (their sum)                       long's tokens; nothing to swap
     *   the funding index                             untouched: it is a rate, and
     *                                                 funding owed follows collateral
     *   the TWAP ring                                 SHIFTED by the oracle tick
     *                                                 offset, never reset (see below)
     *
     *  Longs are restated at the oracle rather than the realized rate on purpose
     *  (owner decision): the swap's slippage belongs to the money that was
     *  actually swapped. Restating a long's DEBT at the realized rate would move
     *  that slippage from the long onto the stakers it owes.
     *
     *  ── ALL OR NOTHING ────────────────────────────────────────────────────
     *  Every failure reverts — unpriceable pair, owed payouts, a venue that cannot
     *  clear the rotator's oracle floor, a vault that will not re-express its
     *  ledger — and the registry does NOT try/catch this call, so the flipping
     *  slice reverts with it. There is no half-converted book, and no window in
     *  which one unit is priced while another is paid.
     *
     *  ── HOW IT REACHES THE ENGINE'S FIGURES (EIP-170) ─────────────────────
     *  The engine has no bytes to pass six figures in and write six back, so it
     *  passes their storage SLOTS instead, packed 16 bits apiece in `slots` and
     *  resolved by its compiler from its own layout (`plv.slot` etc.). All six are
     *  full-slot `uint256`s, so a plain SLOAD/SSTORE is exact. Everything else is
     *  read through the engine's public getters.
     *
     *  Inert when there is nothing to carry: the quote already agrees, or the
     *  engine is not on the live generation ({PerpEngine.syncGeneration} adopts
     *  the generation and its quote together then, as it always has).
     */
    function _requoteBook(
        mapping(uint256 => Position) storage positions,
        uint256[] storage openIds,
        Observation[OBS_CARDINALITY] storage observations,
        Ring storage ring,
        address rot,
        uint256 slots
    ) internal {
        IRequoteEngine me = IRequoteEngine(address(this));
        address oq = me.quote();
        address nq;
        {
            //  DELEGATECALL preserves `msg.sender`: this is the registry's call.
            IRequoteRegistry reg = IRequoteRegistry(me.registry());
            if (msg.sender != address(reg)) revert RequoteNotRegistry();
            uint256 gen = reg.currentGeneration();
            nq = reg.generationQuote(gen);
            if (nq == oq || me.syncedGeneration() != gen) return;
        }
        if (me.payoutOwedTotal() != 0) revert RequotePayoutsOwed();
        (uint256 fOld, uint256 fNew) = _factors(rot, oq, nq);
        address vault = me.vault();

        me.poke(); // settle funding and sample the OLD pool up to now
        //  Losses and yield recognised in the OLD unit, before anything moves.
        _vaultHook(vault, abi.encodeWithSignature("beforeBookRequote()"));

        uint256 oldTotal = _ld(slots, 0) + _ld(slots, 1);
        uint256 spent = _ld(slots, 0) + _ld(slots, 2) + _ld(slots, 3) + _shortBacking(positions, openIds);
        uint256 got = spent != 0 ? _convert(rot, oq, nq, spent) : 0;

        (uint256 longOi, uint256 shortsNew) = _restatePositions(positions, openIds, fOld, fNew, got, spent);
        (uint256 newPlv, uint256 kNum, uint256 kDen) = _restatePots(slots, got, spent, shortsNew, fOld, fNew);
        _st(slots, 1, longOi);

        //  Adopt: the engine now speaks the new asset. The weighted mark priced
        //  the OLD pair, so it is dropped; the carried ring marks until re-armed.
        _stAddr(slots, 96, nq);
        _stAddr(slots, 120, address(0));

        _shiftRing(observations, ring, fOld, fNew);
        //  Remember the rotator: a later RELAUNCH back to the native quote carries
        //  the (then empty) book through it too — see {syncQuoteChangeAt}.
        bytes32 rs = ROT_SLOT;
        assembly ("memory-safe") { sstore(rs, rot) }
        _vaultHook(
            vault,
            abi.encodeWithSignature(
                "afterBookRequote(uint256,uint256,uint256,uint256)", oldTotal, newPlv + longOi, kNum, kDen
            )
        );
    }

    /// @dev Raw units per 1e18 wei for both sides, from the ROTATOR's oracle:
    ///      rotation cannot run without it (its slice floor needs it), so it is
    ///      always there when this is reached — unlike the engine's own optional
    ///      `quoteOracle` (RT-5).
    function _factors(address rot, address oq, address nq) private view returns (uint256 fOld, uint256 fNew) {
        address oracle = IRequoteRotator(rot).quoteOracle();
        fOld = _factorStrict(oracle, oq);
        fNew = _factorStrict(oracle, nq);
    }

    /// @dev Re-express every PHYSICAL pot at the realized rate `got/spent`, write
    ///      them back, and move the yield cumulative and `quoteUnit`. Stakers take
    ///      their pro-rata share plus every rounding remainder — the physical
    ///      figures sum to exactly what arrived, never more.
    function _restatePots(uint256 slots, uint256 got, uint256 spent, uint256 shortsNew, uint256 fOld, uint256 fNew)
        private
        returns (uint256 newPlv, uint256 kNum, uint256 kDen)
    {
        uint256 ins;
        uint256 ty;
        if (spent != 0) {
            ins = FullMath.mulDiv(_ld(slots, 2), got, spent);
            ty = FullMath.mulDiv(_ld(slots, 3), got, spent);
        }
        newPlv = got - shortsNew - ins - ty;
        _st(slots, 0, newPlv);
        _st(slots, 2, ins);
        _st(slots, 3, ty);
        //  The token-side yield ledger moves at the pot's rate: the realized one,
        //  or the oracle's when there was no pot to realize a rate on.
        (kNum, kDen) = spent != 0 ? (got, spent) : (fNew, fOld);
        _st(slots, 4, FullMath.mulDiv(_ld(slots, 4), kNum, kDen));
        _st(slots, 5, fNew); // quoteUnit: raw new-quote units worth 1e18 wei
    }

    bytes32 private constant ROT_SLOT = keccak256("cauldron.perp.requote.rotator");

    /// Same selector as {PerpEngine.VaultStaked} — the refusal is unchanged.
    error VaultStaked();
    /// Same signature as {PerpEngine.TokYieldWrittenOff}, emitted as the engine.
    event TokYieldWrittenOff(address indexed asset, uint256 amount);

    /**
     * @notice The quote-change half of {PerpEngine.syncGeneration}: a RELAUNCH
     *         into a different quote (relaunch forces native, so this is the way
     *         home after a rotation). The engine has already checked the book is
     *         empty and zeroed `longOiEth`; it writes `quote` itself afterwards.
     *
     *  ── CARRIED, NOT VETOED (adversarial A6) ─────────────────────────────
     *  This used to be a veto: any quote-side stake made a non-owner sync revert
     *  `VaultStaked`, so after a rotation the relaunch's own (try-caught) sync
     *  failed and the engine sat on the dead generation — perps off for the new
     *  one — until every staker had exited. Measured in RQ1.A6. Now, if a
     *  rotation ever carried this book (its rotator is remembered), the empty
     *  book's money converts through that rotator's curated venue under its
     *  oracle floor, exactly as at the flip; all-or-nothing, so a sync that
     *  cannot convert reverts and stays permissionlessly retryable.
     *
     *  The OWNER keeps the old path as an explicit escape hatch: the veto does not
     *  apply to it, and it writes the old-asset figures off to the treasury.
     */
    function syncQuoteChangeAt(uint256 slots) external {
        IRequoteEngine me = IRequoteEngine(address(this));
        if (me.payoutOwedTotal() != 0) revert VaultStaked();
        address oq = me.quote();
        address nq;
        {
            IRequoteRegistry reg = IRequoteRegistry(me.registry());
            nq = reg.generationQuote(reg.currentGeneration());
        }
        address rot;
        bytes32 rs = ROT_SLOT;
        assembly ("memory-safe") { rot := sload(rs) }
        address owner_ = me.owner();
        if (rot != address(0) && msg.sender != owner_) {
            _carryEmpty(rot, oq, nq, slots, me.vault());
            return;
        }
        //  The original path, behaviour unchanged.
        address v = me.vault();
        if (msg.sender != owner_ && v != address(0) && IVaultQuoteStake(v).hasQuoteStake()) revert VaultStaked();
        uint256 ty = _ld(slots, 3);
        emit TokYieldWrittenOff(oq, ty);
        uint256 sweep = _ld(slots, 0) + ty + _ld(slots, 2);
        _st(slots, 0, 0);
        _st(slots, 3, 0);
        _st(slots, 2, 0);
        address tre = me.treasury();
        if (sweep != 0 && tre != address(0)) {
            //  Capped, and retired either way — the engine's `_tryPush(.., true)`.
            if (oq == address(0)) {
                (bool sent, ) = tre.call{value: sweep, gas: 30_000}("");
                sent;
            } else {
                (bool called, ) = oq.call(abi.encodeWithSelector(IERC20.transfer.selector, tre, sweep));
                called;
            }
        }
        _st(slots, 5, _quoteFactor(_ldAddr(slots, 144), nq));
    }

    /// @dev {requoteBook}'s conversion for an EMPTY book (relaunch).
    function _carryEmpty(address rot, address oq, address nq, uint256 slots, address vault) private {
        (uint256 fOld, uint256 fNew) = _factors(rot, oq, nq);
        _vaultHook(vault, abi.encodeWithSignature("beforeBookRequote()"));
        uint256 oldTotal = _ld(slots, 0) + _ld(slots, 1);
        uint256 spent = _ld(slots, 0) + _ld(slots, 2) + _ld(slots, 3);
        uint256 got = spent != 0 ? _convert(rot, oq, nq, spent) : 0;
        (uint256 newPlv, uint256 kNum, uint256 kDen) = _restatePots(slots, got, spent, 0, fOld, fNew);
        _vaultHook(
            vault,
            abi.encodeWithSignature(
                "afterBookRequote(uint256,uint256,uint256,uint256)", oldTotal, newPlv + _ld(slots, 1), kNum, kDen
            )
        );
    }

    /// @dev An address variable at (16-bit slot, 8-bit byte offset) from bit `at`.
    function _ldAddr(uint256 slots, uint256 at) private view returns (address a) {
        uint256 s = (slots >> at) & 0xffff;
        uint256 sh = ((slots >> (at + 16)) & 0xff) * 8;
        assembly ("memory-safe") { a := and(shr(sh, sload(s)), 0xffffffffffffffffffffffffffffffffffffffff) }
    }

    /// @dev {requoteBook} with its storage references rebuilt from packed slots.
    function requoteBookAt(address rot, uint256 slots, uint256 refs) external {
        _requoteBook(
            _posAt(refs & 0xffff), _idsAt((refs >> 16) & 0xffff),
            _obsAt((refs >> 32) & 0xffff), _ringAt((refs >> 48) & 0xffff), rot, slots
        );
    }

    function _posAt(uint256 s) private pure returns (mapping(uint256 => Position) storage m) {
        assembly { m.slot := s }
    }
    function _idsAt(uint256 s) private pure returns (uint256[] storage a) {
        assembly { a.slot := s }
    }
    function _obsAt(uint256 s) private pure returns (Observation[OBS_CARDINALITY] storage o) {
        assembly { o.slot := s }
    }
    function _ringAt(uint256 s) private pure returns (Ring storage r) {
        assembly { r.slot := s }
    }

    /// @dev The `i`-th packed engine slot (see {requoteBook}).
    function _slot(uint256 slots, uint256 i) private pure returns (uint256) {
        return (slots >> (16 * i)) & 0xffff;
    }

    function _ld(uint256 slots, uint256 i) private view returns (uint256 v) {
        uint256 s = _slot(slots, i);
        assembly { v := sload(s) }
    }

    function _st(uint256 slots, uint256 i, uint256 v) private {
        uint256 s = _slot(slots, i);
        assembly { sstore(s, v) }
    }

    /// @dev Write an address variable packed at (16-bit slot, 8-bit byte offset)
    ///      starting at bit `at` of `slots`, preserving its slot-mates.
    function _stAddr(uint256 slots, uint256 at, address a) private {
        uint256 s = (slots >> at) & 0xffff;
        uint256 sh = ((slots >> (at + 16)) & 0xff) * 8;
        assembly {
            let m := shl(sh, 0xffffffffffffffffffffffffffffffffffffffff)
            sstore(s, or(and(sload(s), not(m)), shl(sh, a)))
        }
    }

    /// @dev Raw units of `q` worth 1e18 wei — {quoteFactor}, but it refuses to
    ///      fall back to decimals: a guessed rate here would restate real debts.
    function _factorStrict(address oracle, address q) private view returns (uint256) {
        if (q == address(0)) return 1e18;
        if (oracle == address(0)) revert RequoteUnpriced();
        uint256 pNative = _usdPerRawUnit(oracle, address(0));
        uint256 pQuote = _usdPerRawUnit(oracle, q);
        if (pNative == 0 || pQuote == 0) revert RequoteUnpriced();
        return FullMath.mulDiv(1e18, pNative, pQuote);
    }

    /// @dev Old-quote money the shorts hold: collateral plus the proceeds of the
    ///      token they sold. It sits in the engine's balance, outside `plv`.
    function _shortBacking(mapping(uint256 => Position) storage positions, uint256[] storage openIds)
        private
        view
        returns (uint256 backing)
    {
        uint256 n = openIds.length;
        for (uint256 i; i < n; ++i) {
            Position storage p = positions[openIds[i]];
            if (!p.isLong) backing += uint256(p.collateral) + p.principal;
        }
    }

    /// @dev Swap `spent` of the old quote into the new one through the rotator's
    ///      curated venue. `minOut` 0: the rotator's ORACLE floor binds anyway and
    ///      is the tighter of the two. Checked by balance, not by return value.
    function _convert(address rot, address oq, address nq, uint256 spent) private returns (uint256 got) {
        //  The rotator's CURATED venue for this pair — the same allowlist every
        //  slice is held to. The engine never names a venue, so it cannot name a price.
        (PoolKey memory route, bool ok) = IRequoteRotator(rot).venueFor(oq, nq);
        if (!ok) revert RequoteUnpriced();
        if (oq == address(0)) {
            (bool sent, ) = rot.call{value: spent}("");
            if (!sent) revert RequoteShort();
        } else {
            (bool called, bytes memory ret) =
                oq.call(abi.encodeWithSelector(IERC20.transfer.selector, rot, spent));
            if (!(called && (ret.length == 0 || abi.decode(ret, (bool))))) revert RequoteShort();
        }
        uint256 before = _held(nq);
        got = IRequoteRotator(rot).swapOnce(route, oq, nq, spent, 0);
        IRequoteRotator(rot).withdraw(nq, address(this), got);
        if (_held(nq) < before + got) revert RequoteShort();
    }

    function _held(address asset) private view returns (uint256) {
        return asset == address(0) ? address(this).balance : IERC20(asset).balanceOf(address(this));
    }

    /// @dev Longs at the ORACLE rate (their debt rounds UP — it is owed to
    ///      stakers); shorts at the REALIZED rate (their backing was swapped).
    function _restatePositions(
        mapping(uint256 => Position) storage positions,
        uint256[] storage openIds,
        uint256 fOld,
        uint256 fNew,
        uint256 got,
        uint256 spent
    ) private returns (uint256 longOi, uint256 shortsNew) {
        uint256 n = openIds.length;
        for (uint256 i; i < n; ++i) {
            Position storage p = positions[openIds[i]];
            uint256 c;
            uint256 pr;
            if (p.isLong) {
                c = FullMath.mulDiv(p.collateral, fNew, fOld);
                pr = FullMath.mulDivRoundingUp(p.principal, fNew, fOld);
                longOi += pr;
            } else {
                c = FullMath.mulDiv(p.collateral, got, spent);
                pr = FullMath.mulDiv(p.principal, got, spent);
                shortsNew += c + pr;
            }
            if (c > type(uint128).max) revert RequoteUnpriced();
            p.collateral = uint128(c);
            p.principal = pr;
        }
    }

    /**
     * @dev Re-express the TWAP history in the new pool's ticks instead of
     *      wiping it. The price is token per RAW quote unit, so every new-pool
     *      tick sits log_1.0001(fOld / fNew) above its old-pool twin. Adding
     *      `d * ts` to each stored cumulative shifts every TWAP window by exactly
     *      `d`, because a window is (cumB - cumA) / (tsB - tsA).
     *
     *      Resetting instead (what an empty-book adoption does) would leave a
     *      LIVE book marked off the new pool's spot for a whole warm-up window —
     *      the cheapest price in the system to push, at exactly the moment every
     *      carried position is exposed to it. The offset comes from the oracle,
     *      not the pools' spot ticks, so nobody can move it within the block.
     */
    function _shiftRing(Observation[OBS_CARDINALITY] storage obs, Ring storage r, uint256 fOld, uint256 fNew)
        private
    {
        uint256 sq = Math.sqrt(FullMath.mulDiv(fOld, uint256(1) << 192, fNew));
        if (sq < TickMath.MIN_SQRT_PRICE || sq >= TickMath.MAX_SQRT_PRICE) revert RequoteUnpriced();
        int56 d = int56(TickMath.getTickAtSqrtPrice(uint160(sq)));
        unchecked {
            for (uint256 i; i < OBS_CARDINALITY; ++i) {
                uint32 ts = obs[i].ts;
                if (ts != 0) obs[i].tickCumulative += d * int56(uint56(ts));
            }
            r.tickCumulative += d * int56(uint56(r.lastObsTs));
        }
        int256 lt = int256(r.lastTick) + d;
        if (lt < TickMath.MIN_TICK || lt > TickMath.MAX_TICK) revert RequoteUnpriced();
        r.lastTick = int24(lt);
    }

    /// @dev The vault's two ledger hooks. Fail CLOSED: a vault that cannot
    ///      re-express its queue would price new-unit backing against old-unit
    ///      claims (the D-2 saturation), so the whole requote reverts instead.
    function _vaultHook(address vault, bytes memory data) private {
        if (vault == address(0)) return;
        (bool ok, ) = vault.call(data);
        if (!ok) revert RequoteVault();
    }
}
