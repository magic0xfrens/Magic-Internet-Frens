// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {SeedLib} from "./SeedLib.sol";
import {ISeeder, SeederConfig} from "./ISeeder.sol";

/// @dev The registry is Ownable; the prime budget accepts its owner as one of two
///      admins (the other being this contract's deployer), rather than taking a
///      constructor arg — which would break the deploy script's and the fork
///      tests' existing 3-arg signature.
interface IRegistryOwner {
    function owner() external view returns (address);
}

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
    /// @notice Whoever deployed this seeder. A SECOND admin for the prime budget,
    ///         and not a redundant one: the launchpad hands registry ownership to
    ///         the presale so `igniteCauldron()` can reach `summon()`, after which
    ///         `registry.owner()` is a CONTRACT with no way to call {fundPrime}.
    ///         Gating solely on it would make the prime buy fundable only during the
    ///         deploy transaction itself. Cannot be set by an outsider — it is
    ///         `msg.sender` at construction.
    address public immutable deployer;
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

    // ── PRIME BUY (ledger C: EXTERNAL ETH, never ledger A) ──────────────────
    //
    //  The treasury's own ETH, spent buying the brew token off the open market in
    //  tranches that ride the SAME schedule as the liquidity stream. Two reasons it
    //  is tranched rather than a single shot:
    //
    //    1. PRICE IMPACT IS RELATIVE TO DEPTH. A constant-product buy of `e` into a
    //       book holding `E` moves price by `(1 + e/E)^2`. At t0 only `baseWad` of
    //       ledger A is placed, so a lump-sum prime buy lands against the THINNEST
    //       book of the whole launch — the single worst moment to spend it. Paying
    //       out in step with `placedWad` means every tranche meets a deeper book
    //       than the one before, and total impact is bounded by the final depth
    //       instead of the initial depth.
    //    2. IT KEEPS THE TAPE ALIVE. Each tranche is a real swap, so the chart
    //       prints continuously across the seeding window instead of showing one
    //       candle at ignition and then nothing until an outside buyer arrives.
    //
    //  This is ledger C and is accounted separately from ledger A: `withdrawAll`
    //  returns any unspent remainder to the registry and clears the accounting, so
    //  a stale budget can never authorise a swap the contract cannot settle.
    uint256 public primeBudget;   // ETH committed to the prime buy
    uint256 public primeSpent;    // ETH already spent (monotone within a campaign)
    address public primeTo;       // recipient of the bought token (treasury/airdrop)
    /// @dev Dust throttle: skip a tranche smaller than this unless it is the last.
    uint256 public constant PRIME_MIN_WEI = 0.001 ether;

    // ── RATE-LIMITED PRICE REFERENCE (audit Z-17) ───────────────────────────
    //
    //  {poke} is PERMISSIONLESS and {pokeInSwap} runs INSIDE somebody else's swap,
    //  so `getSlot0` is a price the CALLER chose. Both of this contract's actions
    //  used to trust it outright:
    //    • `_primeStep` spent the treasury's budget as a market buy with
    //      `sqrtPriceLimitX96 = MIN_SQRT_PRICE + 1` (the absolute limit — it can
    //      never bind) and no minimum output, and
    //    • `_placeStep` anchored both bands to the live tick.
    //  One EOA could therefore push spot, call `poke()` in the same transaction, and
    //  sell back through the liquidity the protocol had just donated next to its
    //  position while the treasury's tranche bought at the pushed price. MEASURED on
    //  a real v4 PoolManager with production seed params: the treasury received
    //  68,793.99 tokens instead of 46,122,162.16 (−99.85%) and the attacker netted
    //  +12.157 ETH for one block of capital.
    //
    //  The comment on {poke} was true and irrelevant: it defends the SCHEDULE (the
    //  deployment target is a pure function of elapsed time, so nothing can be
    //  accelerated or over-deployed). It says nothing about PRICE, and price is what
    //  the permissionless caller controls.
    //
    //  So we keep a reference tick the caller cannot choose. It only ever moves
    //  {MAX_TICK_DEV} ticks per BLOCK, and it can only adopt spot outright when spot
    //  is already within {MAX_TICK_DEV} of it (see {_syncRef}). Inside ONE block it
    //  therefore still holds a value established in an EARLIER block, and dragging it
    //  D ticks costs D/MAX_TICK_DEV whole BLOCKS of holding a manipulated price
    //  against every arbitrageur — which is not something a flash loan can buy.
    //
    //  THE TWO HALVES ARE THEN TREATED DIFFERENTLY, because only one of them can be
    //  moved out of harm's way:
    //
    //    • PLACEMENT RELOCATES, IT DOES NOT REFUSE. `_placeStep` anchors the ask band
    //      below `min(ref, spot)` and the bid band above `max(ref, spot)`. Whichever
    //      way spot has been pushed, the band the manipulator would trade back THROUGH
    //      is the one pinned to the reference, so their unwind runs out at the honest
    //      price and never reaches it — while the other band still lands adjacent to
    //      live spot. When `ref == spot` (the normal case) the geometry is byte-for-byte
    //      what it always was. This matters because {pokeInSwap} makes streaming a
    //      keeperless side-effect of organic trading: REFUSING here would stop a thin
    //      launch book from streaming on most swaps, i.e. it would break the feature it
    //      is protecting.
    //    • THE PRIME BUY IS GATED. A market order cannot be relocated — it executes at
    //      spot — so it is simply not placed while spot is out of band. Nothing is lost
    //      by waiting: `primePending()` is a pure function of schedule progress, so the
    //      tranche is retried by the next poke and the budget still closes out in full
    //      (asserted end to end in T9b).
    //
    //  SKIP, DON'T REVERT — a revert on the permissionless poke would itself be a
    //  denial of the stream, and {pokeInSwap} is swallowed by the hook anyway.
    int24 internal constant MAX_TICK_DEV = 1000; // ~10.5% of price; 5 production spacings
    /// @dev Extra haircut below the value of `owed` at the WORST tick this contract
    ///      will trade at, covering the pool fee plus the hook's base tax. Sized so a
    ///      prime buy that is paying the anti-sniper surtax (the deploy script may fail
    ///      to set BOTH `setOpener` and `setTaxExempt`, which costs the treasury up to
    ///      96% of the tranche) is REFUSED rather than silently overpaid.
    uint256 internal constant PRIME_SLIP_BPS = 1000; // 10%
    int24 internal _refTick;
    uint64 internal _refBlock; // 0 = uninitialised (set on the first placement)

    uint256 private _locked;
    modifier lock() { if (_locked == 1) revert Reentrancy(); _locked = 1; _; _locked = 0; }
    modifier onlyRegistry() { if (msg.sender != registry) revert OnlyRegistry(); _; }

    // unlockCallback action tags
    uint8 private constant ACT_PLACE = 1;
    uint8 private constant ACT_WITHDRAW = 2;
    uint8 private constant ACT_PRIME = 3;

    event SeedStarted(uint256 indexed gen, uint256 ethTotal, uint256 tokenTotal, uint64 window);
    event Poked(uint256 fromWad, uint256 toWad, int24 tick);
    event SeedComplete(uint256 indexed gen);
    event BasePlaced(uint256 indexed gen, uint128 fullRangeLiquidity);
    event PrimeFunded(address indexed to, uint256 amount, uint256 budget);
    event PrimeBought(uint256 indexed gen, uint256 ethIn, uint256 tokenOut, uint256 spent, uint256 budget);
    /// @notice A poke did nothing because spot was too far from the rate-limited
    ///         reference. Emitted so the stream can never die SILENTLY (audit Z-17/Z-18).
    event PokeSkipped(uint256 indexed gen, int24 tick, int24 refTick);

    constructor(address _registry, address _positionManager, address _poolManager) {
        registry = _registry;
        deployer = msg.sender;
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
        // The price reference is a tick coordinate in the OLD pool as well (audit
        // Z-17). Clearing `_refBlock` re-arms the lazy initialisation two lines below.
        _refBlock = 0;
        _refTick = 0;

        require(IERC20(cfg.token).transferFrom(registry, address(this), cfg.tokenTotal), "pull");

        // Seed the reference from the launch price the REGISTRY just initialised the
        // pool at — the one tick in this campaign's life that no outsider chose.
        _syncRef();

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
        // PRICE REFERENCE FIRST (audit Z-17). The caller chose the block AND, in the
        // sandwich, the tick, so the reference has to be advanced before either action
        // reads a price. Placement still runs when spot is out of band — it relocates
        // (see {_placeStep}); only the treasury's market order waits.
        (bool ok, int24 tick) = _syncRef();

        uint256 step = _pendingStep();
        if (step > 0) {
            poolManager.unlock(abi.encode(ACT_PLACE, step));
            _advance(step);
        }
        // Prime AFTER placing, so the tranche meets the depth this poke just added
        // rather than the depth that preceded it. Runs even when `step == 0`, so a
        // late poke still finishes the budget once the window has closed.
        //
        //  TRY/CATCH, NOT A BARE CALL. `_primeStep` now enforces a minimum output
        //  (audit Z-17), and a binding minOut must NEVER take the liquidity stream
        //  down with it: `poke` is the only permissionless way to advance the
        //  schedule, so a reverting prime tranche would strand ledger A for the rest
        //  of the launch. A refused tranche leaves `primeSpent` untouched and is
        //  retried by the next poke.
        uint256 want = primePending();
        if (want > 0) {
            if (ok) { try poolManager.unlock(abi.encode(ACT_PRIME, want)) {} catch {} }
            else emit PokeSkipped(gen, tick, _refTick);
        }
    }

    /// @notice Commit EXTERNAL ETH to the prime buy and name the recipient of the
    ///         bought token. Callable by the registry's owner, before or during a
    ///         campaign; funding before ignition is the normal path.
    ///
    ///  Gated because `primeTo` decides where bought tokens land. The ETH itself is
    ///  a gift to the campaign — {withdrawAll} returns any unspent remainder to the
    ///  registry at relaunch, so nothing here can be stranded.
    function fundPrime(address to) external payable {
        if (msg.sender != deployer && msg.sender != IRegistryOwner(registry).owner()) revert OnlyRegistry();
        if (to == address(0)) revert BadConfig();
        //  THE RECIPIENT IS PINNED WHILE COMMITTED VALUE EXISTS (audit Z-20).
        //  `primeTo` used to be rewritten on EVERY call, including a zero-value one,
        //  and `deployer` is a plain EOA with no timelock and no renounce path — so
        //  once the budget had been funded (by anyone, as a gift to the campaign) that
        //  EOA could call `fundPrime{value: 0}(attacker)` and redirect the entire
        //  token output of an already-funded budget to itself. The NatSpec above
        //  justifies the gate by saying `primeTo` decides where bought tokens land
        //  without noticing it stayed re-settable after funding.
        //  Re-pointing is still allowed while nothing is at stake — i.e. before the
        //  first funding and after {_teardown} has zeroed both counters — so a genuine
        //  change of treasury address between generations costs one call.
        if (primeTo != to && primeBudget > primeSpent) revert BadConfig();
        primeTo = to;
        primeBudget += msg.value;
        emit PrimeFunded(to, msg.value, primeBudget);
    }

    /// @notice ETH the prime buy should spend right now (0 = nothing to do).
    ///
    ///  The target tracks `placedWad`, so the budget is fully spent exactly when the
    ///  stream completes. Like {_pendingStep} it is a pure function of schedule
    ///  progress: it cannot be accelerated by poking more often, and poking less
    ///  often only defers spending, never loses it.
    function primePending() public view returns (uint256) {
        if (primeTo == address(0) || primeBudget == 0 || !seeding) return 0;
        uint256 target = (primeBudget * placedWad) / 1e18;
        if (target > primeBudget) target = primeBudget;
        if (target <= primeSpent) return 0;
        uint256 want = target - primeSpent;
        // Dust throttle, waived on the final tranche so the budget always closes out.
        if (want < PRIME_MIN_WEI && target < primeBudget) return 0;
        uint256 bal = address(this).balance;
        return want > bal ? bal : want;
    }

    /// @dev One prime tranche: an EXACT-INPUT ETH->token swap whose output goes
    ///      straight to `primeTo`. Assumes the PoolManager is already unlocked.
    ///
    ///      `hookData` tags the swap with this contract so the hook can waive the
    ///      base fee and the anti-sniper surtax — which requires the deployer to
    ///      have set BOTH `setOpener(seeder, true)` and `setTaxExempt(seeder, true)`
    ///      (the hook demands both; see CauldronHook._isExemptPlayer). If either is
    ///      missing the buy still succeeds, it just pays the launch surtax — the
    ///      treasury overpays, nothing breaks or strands.
    function _primeStep(uint256 ethIn) private {
        //  BOUND THE MARKET ORDER (audit Z-17). `_refTick` was validated against an
        //  earlier block by {_syncRef} in this same transaction, so it is the one
        //  price here the caller did not choose. The worst tick we will trade at is
        //  `_refTick - MAX_TICK_DEV` (this is a zeroForOne buy, so it pushes the tick
        //  DOWN and the limit is a LOWER bound). `MIN_SQRT_PRICE + 1` — the previous
        //  value — is the absolute end of the tick range and can never bind.
        int24 lim = _refTick - MAX_TICK_DEV;
        if (lim < TickMath.MIN_TICK) lim = TickMath.MIN_TICK;
        uint160 limitP = TickMath.getSqrtPriceAtTick(lim);
        (uint160 sp,,,) = poolManager.getSlot0(_key.toId());
        // v4 rejects a zeroForOne limit that is not strictly below spot.
        if (limitP >= sp) {
            if (sp <= TickMath.MIN_SQRT_PRICE + 1) return;
            limitP = sp - 1;
        }
        BalanceDelta d = poolManager.swap(
            _key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(ethIn),
                sqrtPriceLimitX96: limitP
            }),
            abi.encode(address(this))
        );
        uint256 owed = uint256(uint128(-d.amount0()));
        uint256 got = uint256(uint128(d.amount1()));
        //  MINIMUM OUTPUT (audit Z-17). Without it, `got` was taken and forwarded
        //  unchecked: the measured sandwich handed the treasury 0.15% of the tokens
        //  its budget should have bought. Valued at `limitP` — the worst price this
        //  swap was allowed to reach — less {PRIME_SLIP_BPS} for the pool fee and the
        //  hook's base tax. Reverting here only aborts the TRANCHE: {poke} runs this
        //  inside its own try/catch, so the liquidity stream is unaffected and the
        //  tranche is retried (nothing is written to `primeSpent`).
        uint256 pxX96 = FullMath.mulDiv(uint256(limitP), uint256(limitP), 1 << 96);
        uint256 minOut = FullMath.mulDiv(owed, pxX96, 1 << 96);
        minOut = (minOut * (10_000 - PRIME_SLIP_BPS)) / 10_000;
        require(got >= minOut, "prime slippage");
        poolManager.settle{value: owed}();
        if (got > 0) poolManager.take(_key.currency1, primeTo, got);
        primeSpent += owed;
        emit PrimeBought(gen, owed, got, primeSpent, primeBudget);
    }

    /// @notice HOOK-ONLY in-swap nudge. The caller (the pool's hook, in afterSwap)
    ///         already holds the unlock, so we place DIRECTLY. Best-effort by the
    ///         hook (gas-bounded, result-ignored) so it can never revert a swap.
    function pokeInSwap() external lock {
        if (msg.sender != address(_key.hooks)) revert OnlyHook();
        // Strictly worse than {poke} without a reference: we are running INSIDE the
        // caller's own swap, at the tick that swap just produced (audit Z-17). The
        // bands relocate against `_refTick`; there is no prime buy on this path.
        _syncRef();
        uint256 step = _pendingStep();
        if (step == 0) return;
        _placeStep(step); // already unlocked by the swap
        _advance(step);
    }

    /// @dev Advance the rate-limited price reference and report whether live spot is
    ///      inside {MAX_TICK_DEV} of it (audit Z-17). Returns `(inBand, liveTick)`.
    ///
    ///      Three cases, and the middle one is the whole defence:
    ///        1. `_refBlock == 0` — first touch of this campaign. Adopt spot. This
    ///           only ever happens inside {startSeed}, which is `onlyRegistry`, at the
    ///           launch price the registry itself just initialised.
    ///        2. `_refBlock == block.number` — the reference was already written THIS
    ///           block. Do NOT write it again: otherwise a caller could poke once to
    ///           re-anchor and again to trade, both inside one sandwich. Judge spot
    ///           against the value standing at the start of the block.
    ///        3. A new block — move the reference toward spot by at most
    ///           {MAX_TICK_DEV}. If spot was already that close, adopt it exactly and
    ///           report in-band; otherwise report OUT of band, having taken one step.
    ///           Repeated over blocks this converges on any honest price move, so the
    ///           stream always resumes, while a manipulator has to hold a false price
    ///           for one block per {MAX_TICK_DEV} ticks of the lie.
    function _syncRef() private returns (bool, int24) {
        (, int24 tick,,) = poolManager.getSlot0(_key.toId());
        uint64 bn = uint64(block.number);
        if (_refBlock == 0) {
            _refTick = tick;
            _refBlock = bn;
            return (true, tick);
        }
        int24 ref = _refTick;
        int24 dev = tick >= ref ? tick - ref : ref - tick;
        if (_refBlock == bn) return (dev <= MAX_TICK_DEV, tick);
        _refBlock = bn;
        if (dev <= MAX_TICK_DEV) {
            _refTick = tick;
            return (true, tick);
        }
        _refTick = tick > ref ? ref + MAX_TICK_DEV : ref - MAX_TICK_DEV;
        return (false, tick);
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
        } else if (act == ACT_PRIME) {
            (, uint256 ethIn) = abi.decode(data, (uint8, uint256));
            _primeStep(ethIn);
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

        //  ANCHOR EACH SIDE TO THE *SAFE* OF (reference, spot) — audit Z-17b. Both
        //  bands used to anchor to live spot, which {poke} and {pokeInSwap} let the
        //  caller choose: a sandwicher pushed spot, had the protocol donate a band
        //  right next to their own position, and sold back through it in the same
        //  transaction. Pinning the band the manipulator must trade back THROUGH to
        //  `_refTick` (which they cannot move inside one block) makes that unwind run
        //  out at the honest price before it ever reaches protocol liquidity:
        //    • spot pushed DOWN  → they unwind UPWARD  → the BID (ETH) band is the
        //      exposed one, so it sits above `max(ref, spot) == ref`.
        //    • spot pushed UP    → they unwind DOWNWARD→ the ASK (token) band is the
        //      exposed one, so it sits below `min(ref, spot) == ref`.
        //  The unexposed side still lands adjacent to live spot, so real depth keeps
        //  arriving where trading actually is, and with `ref == spot` — every honest
        //  poke — the geometry is exactly what it always was.
        int24 ref = _refTick;
        int24 askAt = ref < tick ? ref : tick;
        int24 bidAt = ref > tick ? ref : tick;
        // ASK: token band just below `askAt` (pure token1).
        (int24 aLo, int24 aHi) = SeedLib.askBand(0, 1, askAt, _spacing, _bandWidth);
        // BID: ETH band just above `bidAt` (pure token0).
        (int24 bLo, int24 bHi) = SeedLib.bidBand(0, 1, bidAt, _spacing, _bandWidth);
        // Reserve BEFORE sizing: at the range cap we fall back to an already-tracked
        // band, and the liquidity must be computed for the band we actually use.
        // SIDE-CORRECT FALLBACK (audit F-05): the fallback must stay on the SAME side
        // of spot as the band it replaces — see {_reserveRange}.
        (aLo, aHi) = _reserveRange(aLo, aHi, true, tick);
        (bLo, bHi) = _reserveRange(bLo, bHi, false, tick);

        // A declined (empty) band from {_reserveRange} sizes to zero liquidity and is
        // skipped below — `getLiquidityForAmount*` would divide by zero on lo == hi.
        //
        //  SIDE CHECK AGAINST *LIVE* SPOT, NOT AGAINST THE RECORDED SIDE (audit Z-18).
        //  An ask is sized with `getLiquidityForAmount1` (pure token1) and is only
        //  pure token1 while `currentTick >= tickUpper`; a bid is sized with
        //  `getLiquidityForAmount0` (pure token0/ETH) and is only pure ETH while
        //  `currentTick < tickLower` (SeedLib:21-27). Feed an ask amount into a range
        //  that has drifted ABOVE spot and the pool settles the position in ETH this
        //  contract does not hold — `settle{value:}` reverts, which is a HARD revert
        //  on the permissionless poke and a silently swallowed no-op in-swap, i.e. the
        //  whole stream dies for good. Measured before the fix: 59 pokes of ordinary
        //  200-tick drift, then `placedWad` frozen at 0.74275e18 with 2.30 ETH inside
        //  this contract for the rest of the launch. Sizing to zero is always safe.
        uint128 aLiq = (aHi > aLo && aHi <= tick)
            ? LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(aLo), TickMath.getSqrtPriceAtTick(aHi), tokenStep
            )
            : 0;
        uint128 bLiq = (bHi > bLo && bLo > tick)
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

        // LEDGER C MUST BE CLEARED HERE, NOT IN {startSeed}. The ETH balance above
        // already swept any unspent prime budget back to the registry, so leaving
        // `primeBudget` set would let the NEXT campaign compute a tranche against
        // money this contract no longer holds — `settle{value:}` would then revert
        // and take the whole stream down with it. Clearing in `startSeed` instead
        // would be worse: funding happens BEFORE ignition, so it would wipe the
        // budget every single launch. `primeTo` is deliberately kept — the treasury
        // address does not change between generations, and re-funding is one call.
        primeBudget = 0;
        primeSpent = 0;
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
    ///
    ///      THAT WAS NOT ENOUGH (audit Z-18 — High). `_lastAsk` records the side a
    ///      band was on WHEN IT WAS TRACKED, not when it is reused, and a side is not
    ///      a stable property of a tick range: a token that appreciates makes the tick
    ///      FALL (SeedLib:21-27), so ordinary success drives spot BELOW every tracked
    ///      ask band and the "side-correct" ask fallback is by then an ETH band. It is
    ///      then sized with `getLiquidityForAmount1`, the pool settles it in ETH this
    ///      contract does not hold, and `settle{value:}` reverts — permanently halting
    ///      the stream with no event and no revert anyone sees. Attacker cost: zero.
    ///      It is just what a successful launch does.
    ///
    ///      SO AT THE CAP WE EVICT, NOT REUSE. The band furthest from live spot is the
    ///      least useful one we hold; its liquidity is removed (recovered into this
    ///      contract's loose ledger-A balance, so nothing is stranded and teardown
    ///      still sees a bounded set) and its slot is handed to the band we actually
    ///      want, on the correct side of TODAY's spot. `ranges.length` never grows
    ///      past {MAX_RANGES}, so teardown gas stays bounded exactly as before, and
    ///      the stream keeps running for the whole launch instead of dying at the cap.
    ///      The two-sided full-range BASE is never a candidate: it is the pool's
    ///      spot-straddling depth and is meant to survive until relaunch teardown.
    ///
    ///      ASSUMES THE POOL MANAGER IS ALREADY UNLOCKED — true for every caller
    ///      ({_placeStep} runs inside a self-`unlock` or inside the hook's swap).
    function _reserveRange(int24 lo, int24 hi, bool isAsk, int24 tick) private returns (int24, int24) {
        uint256 n = ranges.length;
        int24 baseLo = (TickMath.MIN_TICK / _spacing) * _spacing;
        uint256 worst = type(uint256).max;
        uint256 worstDist;
        for (uint256 i; i < n; i++) {
            Range storage q = ranges[i];
            if (q.lo == lo && q.hi == hi) {
                if (isAsk) _lastAsk = Range(lo, hi); else _lastBid = Range(lo, hi);
                return (lo, hi);
            }
            if (q.lo == baseLo) continue; // never evict the full-range base
            int256 mid = (int256(q.lo) + int256(q.hi)) / 2;
            int256 diff = mid - int256(tick);
            uint256 dist = uint256(diff < 0 ? -diff : diff);
            if (worst == type(uint256).max || dist > worstDist) { worst = i; worstDist = dist; }
        }
        if (n >= MAX_RANGES) {
            if (worst == type(uint256).max) {
                // Nothing evictable (the cap is entirely the base — unreachable in
                // practice). Fall back to the recorded same-side band; the live-spot
                // side check in {_placeStep} still refuses to mis-size it.
                Range storage r = isAsk ? _lastAsk : _lastBid;
                if (r.lo == 0 && r.hi == 0) return (0, 0);
                return (r.lo, r.hi);
            }
            Range storage e = ranges[worst];
            (uint128 liq,,) =
                poolManager.getPositionInfo(_key.toId(), address(this), e.lo, e.hi, bytes32(0));
            if (liq > 0) {
                (BalanceDelta d,) = poolManager.modifyLiquidity(
                    _key, ModifyLiquidityParams(e.lo, e.hi, -int256(uint256(liq)), bytes32(0)), ""
                );
                _settle(d);
            }
            e.lo = lo;
            e.hi = hi;
            if (isAsk) _lastAsk = Range(lo, hi); else _lastBid = Range(lo, hi);
            return (lo, hi);
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
    /// @notice The rate-limited price reference and the block it was last written in
    ///         (audit Z-17). Diagnosable so a stalled stream is never a mystery.
    function priceRef() external view returns (int24 refTick, uint64 refBlock) {
        return (_refTick, _refBlock);
    }
}
