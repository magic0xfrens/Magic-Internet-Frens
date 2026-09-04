// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {SeedLib} from "./SeedLib.sol";
import {ISeeder, SeederConfig} from "./ISeeder.sol";

/**
 * @title CauldronSeeder
 * @notice PROGRESSIVE launch seed for a Cauldron iteration. The registry seeds
 *         only a thin slice at summon and hands the rest of the ACTIVE tranche
 *         (ledger A: ETH + tokens) to THIS contract, which streams it into the
 *         pool over a configurable window as single-sided bands adjacent to spot.
 *
 *  ── IN-SWAP, KEEPERLESS (the model) ──────────────────────────────────────────
 *  Placement uses the CORE `poolManager.modifyLiquidity` (NOT the periphery
 *  PositionManager, which opens its own `unlock` and so can't run inside a swap).
 *  Two placement entrypoints share one body:
 *    • {pokeInSwap} — called by the HOOK's afterSwap, which already holds the
 *      PoolManager unlock, so it adds liquidity DIRECTLY (no nested unlock). This
 *      makes streaming a keeperless side-effect of organic trading. Toggle it off
 *      by clearing the hook's seeder pointer (`hook.setSeeder(0)`).
 *    • {poke} — permissionless standalone fallback: opens its own `unlock` and
 *      places in the callback. Anyone can nudge the stream; because the target is
 *      a pure function of elapsed time it needs no catch-up loop and can't be
 *      accelerated, over-deployed, or blocked (see {SeedLib.deployedTargetWad}).
 *  {startSeed} (the floor slice) and {withdrawAll} (teardown) also self-`unlock`.
 *
 *  ── SAFETY — SACROSANCT RESERVE ──────────────────────────────────────────────
 *  This contract only ever custodies ledger A. The redemption reserve (ledger B,
 *  the out-of-range band) is placed by the registry at summon and lives in the
 *  pool, never here → "minter redemption stays safe" is STRUCTURAL.
 *
 *  ── POSITIONS + TEARDOWN ─────────────────────────────────────────────────────
 *  Bands are core positions owned by THIS contract at salt 0, so repeated placements
 *  into the same (tickLower,tickUpper) MERGE — the distinct-range set stays small and
 *  bounded ({MAX_RANGES}). At death the registry calls {withdrawAll}, which removes
 *  every tracked range (whatever ETH/token mix it now holds after trading) plus any
 *  un-streamed loose funds, and forwards it all to the registry. Nothing stranded.
 */
contract CauldronSeeder is ISeeder, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error OnlyRegistry();
    error OnlyHook();
    error OnlyPoolManager();
    error AlreadySeeding();
    error BadConfig();
    error Reentrancy();
    error BandCap();

    address public immutable registry;
    IPoolManager public immutable poolManager;
    /// @dev Kept for constructor/ABI compatibility with the deploy script + tests;
    ///      unused now that placement is core-level (no periphery PositionManager).
    address public immutable positionManager;

    // ── active campaign (one at a time; set at summon) ──────────────────────
    PoolKey internal _key;
    address public token;
    uint256 public gen;
    uint64 public startTs;
    uint64 public window;
    uint256 public seedFloorWad;
    uint256 public ethTotal;      // ledger-A ETH budget
    uint256 public tokenTotal;    // ledger-A token budget
    uint256 public placedWad;     // fraction (WAD) deployed so far (of the STREAM budget)
    uint256 public minStepWad;    // throttle: skip a poke deploying less than this
    uint256 public baseWad;       // fraction placed as the two-sided full-range base
    int24 internal _spacing;
    int24 internal _bandWidth;    // width (ticks) of each mini-band
    bool public seeding;
    bool public complete;
    bool internal _basePlaced; // the two-sided full-range base is laid once, lazily

    /// @notice Distinct (tickLower,tickUpper) ranges this campaign has minted into
    ///         (salt 0 → same-range placements merge). Iterated at teardown.
    struct Range { int24 lo; int24 hi; }
    Range[] public ranges;
    /// @dev Last tracked band per side, used as the side-correct fallback once
    ///      {MAX_RANGES} is exhausted (audit F-05). (0,0) = none tracked yet.
    Range internal _lastAsk;
    Range internal _lastBid;
    /// @dev Hard cap so teardown gas stays bounded. If hit, placement reverts (a
    ///      swallowed no-op in-swap; permissionless poke likewise) — streaming
    ///      pauses but NOTHING is stranded: withdrawAll still recovers tracked
    ///      positions + the un-streamed loose balance.
    uint256 internal constant MAX_RANGES = 64;

    uint256 private _locked;
    modifier lock() { if (_locked == 1) revert Reentrancy(); _locked = 1; _; _locked = 0; }
    modifier onlyRegistry() { if (msg.sender != registry) revert OnlyRegistry(); _; }

    // unlockCallback action tags
    uint8 private constant ACT_PLACE = 1;
    uint8 private constant ACT_WITHDRAW = 2;

    event SeedStarted(uint256 indexed gen, uint256 ethTotal, uint256 tokenTotal, uint64 window);
    event Poked(uint256 fromWad, uint256 toWad, int24 tick);
    event SeedComplete(uint256 indexed gen);
    event BasePlaced(uint256 indexed gen, uint128 fullRangeLiquidity);

    constructor(address _registry, address _positionManager, address _poolManager) {
        registry = _registry;
        positionManager = _positionManager; // unused (core placement); kept for ABI compat
        poolManager = IPoolManager(_poolManager);
    }

    receive() external payable {}

    // -----------------------------------------------------------------------
    // ENTRY POINTS
    // -----------------------------------------------------------------------

    /// @notice Begin a campaign (registry-only, at summon). Pulls ledger-A tokens
    ///         (registry approves first), receives ledger-A ETH as msg.value, and
    ///         places the seed-floor slice (via a self-`unlock`).
    function startSeed(SeederConfig calldata cfg) external payable onlyRegistry lock {
        if (seeding) revert AlreadySeeding();
        if (cfg.seedFloorWad == 0 || cfg.seedFloorWad > 1e18) revert BadConfig();
        if (cfg.bandWidth < cfg.spacing) revert BadConfig();
        if (msg.value != cfg.ethTotal) revert BadConfig();

        if (cfg.baseWad > 0.5e18) revert BadConfig(); // base is a MINORITY slice

        _key = cfg.key;
        token = cfg.token;
        gen = cfg.gen;
        startTs = uint64(block.timestamp);
        window = cfg.window;
        seedFloorWad = cfg.seedFloorWad;
        ethTotal = cfg.ethTotal;
        tokenTotal = cfg.tokenTotal;
        minStepWad = cfg.minStepWad;
        baseWad = cfg.baseWad;
        _spacing = cfg.spacing;
        _bandWidth = cfg.bandWidth;
        seeding = true;
        // FULL per-campaign reset (audit H-02). `withdrawAll` leaves `complete` and
        // `_basePlaced` set; without clearing them here every generation after the
        // first would report complete immediately, `_pendingStep` would return 0
        // forever, and ~90% of ledger A would sit in this contract for the whole
        // life of the generation (no depth, no spot-straddling base for perps).
        complete = false;
        _basePlaced = false;
        _lastEthOut = 0;
        _lastTokenOut = 0;
        // Ranges are per-CAMPAIGN: they are tick coordinates in THIS generation's pool
        // (audit Z-04b). `withdrawAll` clears them, but the break-glass `rescue` path
        // does not, so without this a post-rescue rebirth inherited the dead pool's
        // ranges — `_reserveRange` would then match/reuse them, placing into the new
        // pool at the old pool's ticks and burning the bounded range budget.
        delete ranges;
        // Per-side fallbacks are tick coordinates in the OLD pool too (audit F-05).
        delete _lastAsk;
        delete _lastBid;

        require(IERC20(cfg.token).transferFrom(registry, address(this), cfg.tokenTotal), "pull");

        // ONE self-unlock does both t0 placements: the two-sided full-range BASE
        // (spot-straddling → perps get depth + the book is continuous, no teleport)
        // and the single-sided FLOOR slice (anti-snipe). Base is placed ONCE and
        // never removed until relaunch teardown → no mid-life liquidity removal,
        // no callable, fully automatic.
        poolManager.unlock(abi.encode(ACT_PLACE, cfg.seedFloorWad));
        placedWad = cfg.seedFloorWad;
        if (placedWad >= 1e18) { complete = true; emit SeedComplete(gen); }
        emit SeedStarted(cfg.gen, cfg.ethTotal, cfg.tokenTotal, cfg.window);
    }

    /// @notice PERMISSIONLESS standalone nudge (self-`unlock`). No-op when complete,
    ///         throttled, or not seeding. Cannot be accelerated/over-deployed (the
    ///         target is a pure function of elapsed time).
    function poke() external lock {
        uint256 step = _pendingStep();
        if (step == 0) return;
        poolManager.unlock(abi.encode(ACT_PLACE, step));
        _advance(step);
    }

    /// @notice HOOK-ONLY in-swap nudge. The caller (the pool's hook, in afterSwap)
    ///         already holds the unlock, so we place DIRECTLY. Best-effort by the
    ///         hook (gas-bounded, result-ignored) so it can never revert a swap.
    function pokeInSwap() external lock {
        if (msg.sender != address(_key.hooks)) revert OnlyHook();
        uint256 step = _pendingStep();
        if (step == 0) return;
        _placeStep(step); // already unlocked by the swap
        _advance(step);
    }

    /// @dev The throttled step to deploy right now (0 = nothing to do).
    function _pendingStep() private view returns (uint256) {
        if (!seeding || complete) return 0;
        uint256 target = SeedLib.deployedTargetWad(startTs, window, block.timestamp, seedFloorWad);
        uint256 step = target > placedWad ? target - placedWad : 0;
        if (step == 0) return 0;
        if (step < minStepWad && target < 1e18) return 0; // wait for a meaningful step
        return step;
    }

    /// @dev Advance bookkeeping after a placement (target may exceed placed+step by
    ///      the tiny throttle remainder; snap placed to the schedule target).
    function _advance(uint256 step) private {
        uint256 target = SeedLib.deployedTargetWad(startTs, window, block.timestamp, seedFloorWad);
        uint256 from = placedWad;
        placedWad = target;
        (, int24 tick,,) = poolManager.getSlot0(_key.toId());
        emit Poked(from, target, tick);
        if (target >= 1e18) { complete = true; emit SeedComplete(gen); }
        step; // silence unused (kept for signature symmetry / future weighting)
    }

    // -----------------------------------------------------------------------
    // UNLOCK CALLBACK — placement + teardown bodies (run inside an unlock)
    // -----------------------------------------------------------------------

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        uint8 act = abi.decode(data[:32], (uint8));
        if (act == ACT_PLACE) {
            (, uint256 stepWad) = abi.decode(data, (uint8, uint256));
            _placeStep(stepWad);
        } else {
            (, address to) = abi.decode(data, (uint8, address));
            _teardown(to);
        }
        return "";
    }

    /// @dev Place one step as an ASK band (token, just below spot) + a BID band (ETH,
    ///      just above spot), both single-sided, via core modifyLiquidity. Assumes
    ///      the PoolManager is already unlocked (self-unlock or in-swap). On the FIRST
    ///      placement it also lays the two-sided full-range BASE (once), so the pool
    ///      always has spot-straddling depth (perps) + continuity (no teleport) with
    ///      NO later liquidity removal.
    function _placeStep(uint256 stepWad) private {
        if (!_basePlaced) {
            _basePlaced = true;
            if (baseWad > 0) _placeBase();
        }
        (, int24 tick,,) = poolManager.getSlot0(_key.toId());
        // Streaming deploys the NON-base portion of ledger A over the schedule.
        uint256 streamTok = tokenTotal - (tokenTotal * baseWad) / 1e18;
        uint256 streamEth = ethTotal - (ethTotal * baseWad) / 1e18;
        uint256 tokenStep = (streamTok * stepWad) / 1e18;
        uint256 ethStep = (streamEth * stepWad) / 1e18;

        // ASK: token band just below current tick (pure token1).
        (int24 aLo, int24 aHi) = SeedLib.askBand(0, 1, tick, _spacing, _bandWidth);
        // BID: ETH band just above current tick (pure token0).
        (int24 bLo, int24 bHi) = SeedLib.bidBand(0, 1, tick, _spacing, _bandWidth);
        // Reserve BEFORE sizing: at the range cap we fall back to an already-tracked
        // band, and the liquidity must be computed for the band we actually use.
        // SIDE-CORRECT FALLBACK (audit F-05): the fallback must stay on the SAME side
        // of spot as the band it replaces — see {_reserveRange}.
        (aLo, aHi) = _reserveRange(aLo, aHi, true);
        (bLo, bHi) = _reserveRange(bLo, bHi, false);

        // A declined (empty) band from {_reserveRange} sizes to zero liquidity and is
        // skipped below — `getLiquidityForAmount*` would divide by zero on lo == hi.
        uint128 aLiq = aHi > aLo
            ? LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(aLo), TickMath.getSqrtPriceAtTick(aHi), tokenStep
            )
            : 0;
        uint128 bLiq = bHi > bLo
            ? LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(bLo), TickMath.getSqrtPriceAtTick(bHi), ethStep
            )
            : 0;

        BalanceDelta total;
        if (aLiq > 0) {
            (BalanceDelta d,) = poolManager.modifyLiquidity(
                _key, ModifyLiquidityParams(aLo, aHi, int256(uint256(aLiq)), bytes32(0)), ""
            );
            total = total + d;
        }
        if (bLiq > 0) {
            (BalanceDelta d,) = poolManager.modifyLiquidity(
                _key, ModifyLiquidityParams(bLo, bHi, int256(uint256(bLiq)), bytes32(0)), ""
            );
            total = total + d;
        }
        _settle(total);
    }

    /// @dev Remove EVERY tracked range's liquidity + take the proceeds here, then
    ///      forward all balances (recovered + un-streamed loose) to `to`.
    function _teardown(address to) private {
        uint256 n = ranges.length;
        BalanceDelta total;
        PoolId pid = _key.toId();
        for (uint256 i; i < n; i++) {
            Range storage r = ranges[i];
            (uint128 liq,,) = poolManager.getPositionInfo(pid, address(this), r.lo, r.hi, bytes32(0));
            if (liq == 0) continue;
            (BalanceDelta d,) = poolManager.modifyLiquidity(
                _key, ModifyLiquidityParams(r.lo, r.hi, -int256(uint256(liq)), bytes32(0)), ""
            );
            total = total + d;
        }
        _settle(total); // take() the positive proceeds to this contract

        // Forward everything (recovered + any un-streamed ledger-A) to the registry,
        // recording the amounts for withdrawAll's return values.
        uint256 tbal = IERC20(token).balanceOf(address(this));
        if (tbal > 0) IERC20(token).transfer(to, tbal);
        uint256 ebal = address(this).balance;
        if (ebal > 0) { (bool ok,) = to.call{value: ebal}(""); require(ok, "eth"); }
        _lastEthOut = ebal;
        _lastTokenOut = tbal;
    }

    /// @dev BASE: lay `baseWad` of ledger A as ONE two-sided full-range position
    ///      straddling spot — placed ONCE at the first placement and never removed
    ///      until relaunch teardown. This is what gives the pool spot-straddling
    ///      depth (so the perp engine can open leverage) AND full continuity (a swap
    ///      never crosses a zero-liquidity gap → no teleport, smooth liquidations),
    ///      with NO mid-life liquidity removal, no callable, fully automatic. A
    ///      full-range spread is thin per tick, so it barely dents the single-sided
    ///      floor's near-spot anti-snipe depth. Leftover (the asset the current-price
    ///      ratio couldn't fully pair) stays as ledger A, recovered at teardown.
    function _placeBase() private {
        (uint160 sp,,,) = poolManager.getSlot0(_key.toId());
        int24 minT = (TickMath.MIN_TICK / _spacing) * _spacing;
        int24 maxT = (TickMath.MAX_TICK / _spacing) * _spacing;
        uint256 baseEth = (ethTotal * baseWad) / 1e18;
        uint256 baseTok = (tokenTotal * baseWad) / 1e18;
        uint128 L = LiquidityAmounts.getLiquidityForAmounts(
            sp, TickMath.getSqrtPriceAtTick(minT), TickMath.getSqrtPriceAtTick(maxT), baseEth, baseTok
        );
        if (L > 0) {
            // Track before placing (recoverable at teardown). The base is two-sided
            // full-range, so it belongs to NEITHER side's fallback — push it directly
            // instead of going through {_reserveRange}, which would otherwise install
            // a full-range band as an ask/bid fallback (audit F-05).
            ranges.push(Range(minT, maxT));
            (BalanceDelta d,) = poolManager.modifyLiquidity(
                _key, ModifyLiquidityParams(minT, maxT, int256(uint256(L)), bytes32(0)), ""
            );
            _settle(d);
            emit BasePlaced(gen, L);
        }
    }

    /// @dev Settle a net BalanceDelta from this contract's perspective: pay owed
    ///      (negative) currencies, take owed-to-us (positive) ones. currency0 = ETH
    ///      (native), currency1 = the brew token (ERC20).
    function _settle(BalanceDelta d) private {
        int128 d1 = d.amount1();
        if (d1 < 0) {
            poolManager.sync(_key.currency1);
            IERC20(token).transfer(address(poolManager), uint256(uint128(-d1)));
            poolManager.settle();
        } else if (d1 > 0) {
            poolManager.take(_key.currency1, address(this), uint256(uint128(d1)));
        }
        int128 d0 = d.amount0();
        if (d0 < 0) {
            poolManager.settle{value: uint256(uint128(-d0))}();
        } else if (d0 > 0) {
            poolManager.take(_key.currency0, address(this), uint256(uint128(d0)));
        }
    }

    /// @dev Reserve a placement range. Returns the range that will actually be used:
    ///      the requested one if it is already tracked or there is room, otherwise
    ///      the most recently tracked range (audit L-01).
    ///
    ///      DEGRADE, DON'T HALT. The old version REVERTED at the cap, which silently
    ///      stopped the whole stream for the rest of the launch (a swallowed no-op
    ///      in-swap, a revert on permissionless poke). Reusing a tracked range keeps
    ///      streaming, keeps teardown gas bounded, and — because the range IS
    ///      tracked — keeps every wei recoverable by `withdrawAll`. We never place
    ///      into an untracked (and therefore unrecoverable) range.
    ///
    ///      SIDE-CORRECTNESS (audit F-05). The fallback used to be `ranges[n-1]` —
    ///      the most recently PUSHED range, whichever side of spot it happens to be
    ///      on. `_placeStep` reserves the ask band and then the bid band, so at the
    ///      cap BOTH resolved to that same one range. Sizing then breaks badly,
    ///      because the two sides are sized with opposite formulas:
    ///        * the ask amount is turned into liquidity with
    ///          `getLiquidityForAmount1` (pure token1, range BELOW spot), and
    ///        * the bid amount with `getLiquidityForAmount0` (pure token0/ETH,
    ///          range ABOVE spot).
    ///      Feeding an ask amount into a range that sits ABOVE spot mints a position
    ///      the pool settles entirely in ETH, so `_settle` is asked for an ETH debit
    ///      that bears no relation to `ethStep` and that this contract does not hold
    ///      — the placement reverts (swallowed in-swap, a hard revert on the
    ///      permissionless `poke`), so the stream halts exactly as the cap was
    ///      designed to avoid. The cap is genuinely reachable: a new band is tracked
    ///      every time the aligned tick moves one spacing, so ~64 spacings of drift
    ///      (well inside one launch window of real trading) exhausts it.
    ///      We therefore remember the last tracked band PER SIDE and fall back to
    ///      the matching one, so an ask always degrades into an ask and a bid into a
    ///      bid.
    function _reserveRange(int24 lo, int24 hi, bool isAsk) private returns (int24, int24) {
        uint256 n = ranges.length;
        for (uint256 i; i < n; i++) {
            if (ranges[i].lo == lo && ranges[i].hi == hi) {
                if (isAsk) _lastAsk = Range(lo, hi); else _lastBid = Range(lo, hi);
                return (lo, hi);
            }
        }
        if (n >= MAX_RANGES) {
            Range storage r = isAsk ? _lastAsk : _lastBid;
            // No same-side band was ever tracked (only possible if the cap filled
            // entirely from the other side, e.g. the full-range base plus one side):
            // decline the placement rather than mis-side it. Returning an empty band
            // makes the liquidity computation yield 0, which `_placeStep` skips.
            if (r.lo == 0 && r.hi == 0) return (0, 0);
            return (r.lo, r.hi);
        }
        ranges.push(Range(lo, hi));
        if (isAsk) _lastAsk = Range(lo, hi); else _lastBid = Range(lo, hi);
        return (lo, hi);
    }

    // -----------------------------------------------------------------------
    // TEARDOWN / RESCUE (registry-only)
    // -----------------------------------------------------------------------

    /// @notice TEARDOWN at death/relaunch: unwind every band + forward all funds to
    ///         `to` (the registry). Bounded by the tracked-range set. Ends the
    ///         campaign so the seeder can be reused for the next generation.
    function withdrawAll(address to) external onlyRegistry lock returns (uint256 ethOut, uint256 tokenOut) {
        poolManager.unlock(abi.encode(ACT_WITHDRAW, to));
        // _teardown recorded exactly what it forwarded to `to`.
        ethOut = _lastEthOut;
        tokenOut = _lastTokenOut;
        delete ranges;
        seeding = false;
        complete = true;
    }

    // scratch accounting for withdrawAll's return values (written by _teardown)
    uint256 private _lastEthOut;
    uint256 private _lastTokenOut;

    /// @notice Registry-only escape hatch for an aborted campaign: return loose
    ///         ledger-A funds (no pool interaction). Only ever touches ledger A.
    ///
    ///  DOES NOT END THE CAMPAIGN (audit Z-04 — High). This used to set
    ///  `seeding = false` while leaving every already-placed core position untouched.
    ///  Both registry paths to the ONLY recovery function are gated on that flag
    ///  (`CauldronRegistry._removeLiquidity` and `migrateToSuccessor` each call
    ///  `withdrawAll` only `if (ISeeder(_seeder).seeding())`), and `withdrawAll` is
    ///  `onlyRegistry` — so one `rescueSeeder()` made the placed book unreachable
    ///  FOREVER. On a progressive generation that book is also the only source of
    ///  relaunch ETH, so `relaunch()` then reverted `NoLiquidityToSeed` and the
    ///  machine could never be reborn.
    ///
    ///  `startSeed` places the base + seed-floor slice in the SAME transaction, so a
    ///  campaign holding only loose funds never exists; this hatch is therefore always
    ///  partial by construction. Leaving `seeding` armed keeps `withdrawAll` reachable
    ///  so the positions are still recovered at the next relaunch/handoff. The next
    ///  generation cannot start until that teardown runs, which is the correct order.
    function rescue(address to) external onlyRegistry lock {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) IERC20(token).transfer(to, bal);
        uint256 e = address(this).balance;
        if (e > 0) { (bool ok,) = to.call{value: e}(""); require(ok, "eth"); }
    }

    // -----------------------------------------------------------------------
    // VIEWS
    // -----------------------------------------------------------------------
    function deployedWad() external view returns (uint256) { return placedWad; }
    function rangeCount() external view returns (uint256) { return ranges.length; }
    function isComplete() external view returns (bool) { return complete; }
}
