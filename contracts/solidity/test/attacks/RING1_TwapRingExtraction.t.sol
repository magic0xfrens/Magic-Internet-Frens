// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";

/**
 * RING1 — differential test of the TWAP RING EXTRACTION (commit c34a262).
 *
 * The five ring scalars moved into `PerpSwapLib.Ring internal ring;` and both
 * `twapTick` and `_writeObs` became EXTERNAL library functions taking the
 * 32-slot `observations` array and `ring` as STORAGE REFERENCES (delegatecall).
 *
 *   cauldron/PerpEngine.sol:320-323
 *     PerpSwapLib.Observation[OBS_CARDINALITY] internal observations;
 *     PerpSwapLib.Ring internal ring;
 *   cauldron/PerpEngine.sol:757-762
 *     function _writeObs() internal {
 *         PerpSwapLib.writeObs(observations, ring, OBS_INTERVAL, _currentTick());
 *     }
 *   cauldron/PerpEngine.sol:782-785
 *     function twapTick() public view returns (int24 tick, bool ok) {
 *         return PerpSwapLib.twapTick(observations, ring, twapWindow);
 *     }
 *
 * `OldRingMirror` below is the PRE-CHANGE implementation copied VERBATIM from
 * `git show 0d2c39c:contracts/solidity/cauldron/PerpEngine.sol` (lines 300-328,
 * 542-546, 753-769, 790-833), with the one difference that `_currentTick()` is
 * passed in — which is precisely the hoist under test.
 *
 * The engine's `_currentTick()` is pinned to a controllable mark source so both
 * implementations see the SAME tick at the SAME timestamp; then every step
 * asserts `(tick, ok)` equality. Any drift in the extracted constants
 * (MIN_TWAP / OBS_MASK / OBS_INTERVAL), any mis-ordered storage read, or any
 * mis-targeted reset shows up as an inequality.
 */
contract RING1_TwapRingExtraction is Test {
    RStubPM pm;
    RStubRegistry reg;
    RStubHook hook;
    RStubERC721 frens;
    PerpEngine perp;
    OldRingMirror mirror;
    TickSource src;

    address timelock = address(0x7171);
    address token;

    function setUp() public {
        token = address(new RStubERC20());
        pm = new RStubPM();
        reg = new RStubRegistry(token);
        hook = new RStubHook();
        frens = new RStubERC721();
        src = new TickSource();

        // The engine's constructor seeds the ring with `_currentTick()`. No mark
        // source is wired yet, so it reads the stub pool's tick, which is 0.
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(hook), address(reg),
            address(frens), address(0xD1), address(0x7E), timelock
        );
        // Mirror seeded in the SAME block with the SAME tick (0).
        mirror = new OldRingMirror(0, perp.twapWindow());

        // Pin `_currentTick()` to a source we control so both implementations
        // are driven by an identical tick series.
        vm.prank(timelock);
        perp.setRouting(address(0xD1), address(0x7E), address(0x7E), address(src), address(0));
    }

    /// @dev One driven step: warp `dt`, set the tick, poke both rings, and return
    ///      both readings. All conditional logic lives here; the top-level test
    ///      asserts on the values this hands back.
    function _step(uint32 dt, int24 tick)
        internal
        returns (int24 aTick, bool aOk, int24 bTick, bool bOk)
    {
        vm.warp(vm.getBlockTimestamp() + dt);
        src.set(tick);
        perp.poke();          // -> _pokeFunding -> _writeObs -> PerpSwapLib.writeObs
        mirror.writeObs(tick); // the pre-change body, verbatim
        (aTick, aOk) = perp.twapTick();
        (bTick, bOk) = mirror.twapTick();
    }

    // ── POSITIVE CONTROL ──────────────────────────────────────────────────────
    // Before asserting equality means anything, prove the harness actually moves
    // the ring: a non-zero tick held for longer than twapWindow must produce a
    // non-zero, `ok == true` mark on BOTH sides.
    function test_control_theHarnessActuallyDrivesTheRing() public {
        int24 a;
        bool aOk;
        int24 b;
        bool bOk;
        for (uint256 i; i < 40; ++i) {
            (a, aOk, b, bOk) = _step(30, 5000);
        }
        assertTrue(aOk, "engine mark is usable");
        assertTrue(bOk, "mirror mark is usable");
        assertEq(int256(a), int256(5000), "engine averaged the driven tick");
        assertEq(int256(b), int256(5000), "mirror averaged the driven tick");
        console2.log("control engine tick", int256(a));
        console2.log("control mirror tick", int256(b));
    }

    // ── DIFFERENTIAL: a scripted sequence of pokes and warps ─────────────────
    // Sub-interval pokes (dt < OBS_INTERVAL) that integrate but do not append,
    // exact-interval pokes, long gaps, sign changes, and >32 appends to force
    // ring wrap-around.
    struct Diff { uint256 steps; uint256 mismatches; uint256 okMismatches; int24 lastA; int24 lastB; bool lastAOk; bool lastBOk; }

    function _drive() internal returns (Diff memory d) {
        uint32[8] memory dts = [uint32(1), 7, 15, 16, 3, 120, 900, 31];
        int24[8] memory ticks = [int24(0), 1200, -3400, 50, -50, 17000, -17000, 900];
        for (uint256 i; i < 96; ++i) {
            (int24 a, bool aOk, int24 b, bool bOk) = _step(dts[i % 8], ticks[i % 8]);
            d.steps++;
            if (a != b) d.mismatches++;
            if (aOk != bOk) d.okMismatches++;
            d.lastA = a; d.lastB = b; d.lastAOk = aOk; d.lastBOk = bOk;
        }
    }

    function test_RING_extractedTwapMatchesThePreChangeImplementation() public {
        Diff memory d = _drive();
        console2.log("steps", d.steps);
        console2.log("tick mismatches", d.mismatches);
        console2.log("ok mismatches", d.okMismatches);
        console2.log("last engine tick", int256(d.lastA));
        console2.log("last mirror tick", int256(d.lastB));
        assertGt(d.steps, 90, "the sequence ran");
        assertTrue(d.lastAOk, "the ring is warm at the end (not a vacuous 0,false==0,false run)");
        assertEq(d.mismatches, 0, "extracted twapTick drifted from the pre-change body");
        assertEq(d.okMismatches, 0, "extracted twapTick's ok flag drifted");
    }

    // ── DIFFERENTIAL ACROSS A GENERATION RESET ───────────────────────────────
    // `syncGeneration` resets the ring. A reset that missed a `ring.*` field
    // would leave the PREVIOUS generation's cumulative tick in place and the
    // first post-relaunch mark would be computed against a dead pool's price.
    struct ResetR { int24 tickAfter; bool okAfter; int24 mirrorTick; bool mirrorOk; uint256 mismatches; }

    function _resetRun() internal returns (ResetR memory r) {
        // Build a long history at a high tick.
        for (uint256 i; i < 40; ++i) { _step(30, 60000); }
        (int24 pre,) = perp.twapTick();
        assertEq(int256(pre), int256(60000), "pre-reset mark is the old generation's price");

        // Relaunch: the registry hands the engine a new generation, the engine
        // resets the ring (PerpEngine.sol:1282-1289).
        reg.bumpGeneration();
        src.set(-60000);
        perp.syncGeneration();
        //  `syncGeneration` seeds `ring.lastTick` from `_currentTick()` at
        //  PerpEngine.sol:1288 — which still sees the mark source, because the
        //  source is not dropped until PerpEngine.sol:1442. Re-arm it so both
        //  implementations keep seeing the same tick series afterwards.
        //  0, not -60000. The mirror replicates the PRE-CHANGE body, which seeded
        //  `lastTick` from `_currentTick()` while the OLD markSource was still
        //  armed. RING1-A moved that seed below the adoption, so the engine now
        //  reads the live pool (RStubPM's 1:1 slot0 = tick 0) — which is the whole
        //  point of the fix. Seeding the mirror the same way keeps this a test of
        //  the ring MECHANICS (cumulative, index, timestamps) rather than of the
        //  seed value, which RING1-A/RING2 pin directly.
        mirror.reset(0);
        vm.prank(timelock);
        perp.setRouting(address(0xD1), address(0x7E), address(0x7E), address(src), address(0));

        // Now drive the NEW price and compare all the way.
        for (uint256 i; i < 40; ++i) {
            (int24 a, bool aOk, int24 b, bool bOk) = _step(30, -60000);
            if (a != b || aOk != bOk) r.mismatches++;
            r.tickAfter = a; r.okAfter = aOk; r.mirrorTick = b; r.mirrorOk = bOk;
        }
    }

    function test_RING_generationResetTargetsEveryRingField() public {
        ResetR memory r = _resetRun();
        console2.log("post-reset engine tick", int256(r.tickAfter));
        console2.log("post-reset mirror tick", int256(r.mirrorTick));
        console2.log("post-reset mismatches", r.mismatches);
        assertTrue(r.okAfter, "post-reset mark is usable");
        assertEq(r.mismatches, 0, "post-reset ring drifted from the pre-change body");
        assertEq(int256(r.tickAfter), int256(-60000), "no stale cumulative survived the reset");
    }


    // ─────────────────────────────────────────────────────────────────────────
    //  RING1-A. The reset SEEDS `ring.lastTick` with a tick read BEFORE the new
    //  generation is adopted, and the ring-warmup gate expires at exactly the
    //  moment that seed still accounts for 100% of the average.
    //
    //  cauldron/PerpEngine.sol:1281-1289
    //      // Reset the TWAP oracle - old-pool ticks are meaningless for the new token.
    //      delete observations;
    //      ring.tickCumulative = 0;
    //      ring.obsIndex = 1;
    //      ring.lastObsTs = uint32(block.timestamp);
    //      ring.lastRingTs = uint32(block.timestamp);
    //      ringArmedAt = uint32(block.timestamp);
    //      ring.lastTick = _currentTick();            <-- OLD generation's tick
    //      observations[0] = PerpSwapLib.Observation(uint32(block.timestamp), 0);
    //
    //  `_currentTick()` (PerpEngine.sol:694) reads `markSource`, which is not
    //  cleared until PerpEngine.sol:1442 — ten lines LATER — and otherwise reads
    //  `_pid()`, built from the still-OLD `quote` (assigned at :1440).
    //
    //  cauldron/PerpEngine.sol:1830-1832
    //      uint256 ringWarm = uint256(ringArmedAt) + twapWindow;
    //      if (block.timestamp < (summonWarm < ringWarm ? ringWarm : summonWarm)) revert NotWarm();
    //
    //  So the gate opens at ringArmedAt + twapWindow, and with no intervening
    //  observation the mark at that instant is EXACTLY the stale seed.
    // ─────────────────────────────────────────────────────────────────────────
    struct Stale { int24 markAtGateOpen; bool ok; int24 liveTick; }

    function _staleRun() internal returns (Stale memory s) {
        // The old generation trades at tick +60000 with a weighted mark source.
        for (uint256 i; i < 40; ++i) { _step(30, 60000); }

        // Relaunch. The engine resets the ring; the seed is read while the OLD
        // mark source is still armed.
        reg.bumpGeneration();
        uint256 armedAt = vm.getBlockTimestamp();
        perp.syncGeneration();

        // Nothing pokes for the whole ring warmup. The live pool tick is 0 (the
        // stub pool), and the mark source has been dropped by the sync, so
        // `_currentTick()` now genuinely reads 0.
        vm.warp(armedAt + perp.twapWindow());
        (s.markAtGateOpen, s.ok) = perp.twapTick();
        s.liveTick = 0; // RStubPM's slot0 is a 1:1 sqrtPrice
    }

    function test_RING_A_FIXED_relaunchRingIsSeededWithTheNewGenerationsTick() public {
        Stale memory s = _staleRun();
        console2.log("mark at the instant the ring-warmup gate opens", int256(s.markAtGateOpen));
        console2.log("live pool tick at that instant", int256(s.liveTick));
        assertTrue(s.ok, "the mark is LIVE at the gate, not cold-start");
        //  If the reset seeded a tick meaningful for the NEW generation this
        //  would be 0 (the live pool). It is the DEAD generation's +60000.
        //  FIXED (RING1-A): the seed is taken AFTER the new generation is adopted,
        //  so the first mark the gate can show is the LIVE tick, not the dead one.
        assertEq(int256(s.markAtGateOpen), int256(0),
            "the first openable mark of the new generation is the dead generation's price");
        assertEq(int256(s.markAtGateOpen), int256(s.liveTick), "FIXED: mark agrees with the live pool at the gate");
    }

    // ── CONSTANT DRIFT ───────────────────────────────────────────────────────
    // The library declares its OWN MIN_TWAP / OBS_MASK / OBS_CARDINALITY beside
    // the engine's (PerpSwapLib.sol:37-39 vs PerpEngine.sol:306-311). Only
    // OBS_CARDINALITY is compile-checked (it types the shared array). MIN_TWAP is
    // not: the engine uses it to BOUND `twapWindow` while the library uses its
    // own copy to decide whether the ring is warm enough to answer.
    function test_RING_minTwapIsTheLowestAcceptedWindowOnBothSides() public {
        // Engine side: the smallest window `setGuards` accepts.
        vm.prank(timelock);
        perp.setGuards(1, 500, 500);
        assertEq(uint256(perp.twapWindow()), 1, "engine MIN_TWAP == 1s");

        // Library side: exactly MIN_TWAP of history must already be answerable.
        vm.warp(vm.getBlockTimestamp() + 100);
        src.set(4242);
        perp.poke();
        vm.warp(vm.getBlockTimestamp() + 2);
        perp.poke();
        (int24 t, bool ok) = perp.twapTick();
        console2.log("min-window mark tick", int256(t)); console2.log("min-window ok", ok);
        assertTrue(ok, "library MIN_TWAP must not be stricter than the engine's bound");
    }

    // ── GAS ──────────────────────────────────────────────────────────────────
    // Each mark read now pays a DELEGATECALL. `_liqTest` takes one and
    // `_killStats` a second, so a kill pays two. Measure the per-read cost.
    function test_RING_markReadGasCost() public {
        for (uint256 i; i < 40; ++i) { _step(30, 5000); }
        uint256 g0 = gasleft();
        perp.markSqrtPriceX96();
        uint256 warmOuter = g0 - gasleft();
        uint256 g1 = gasleft();
        perp.markSqrtPriceX96();
        uint256 warm2 = g1 - gasleft();
        console2.log("markSqrtPriceX96 gas (first)", warmOuter);
        console2.log("markSqrtPriceX96 gas (repeat)", warm2);
        assertGt(warmOuter, 0, "measured");
        // SWEEP_KILL_RESERVE is 420_000 (PerpEngine.sol:424). Two mark reads per
        // kill must stay a rounding error against that.
        assertLt(warm2 * 2, 420_000 / 4, "two mark reads must not eat the kill reserve");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The PRE-CHANGE ring, copied verbatim from 0d2c39c:cauldron/PerpEngine.sol.
//  Five BARE storage scalars, the inline `_writeObs` body and the inline
//  `twapTick` body. `_currentTick()` is a parameter, which is exactly the hoist
//  the new `PerpSwapLib.writeObs(observations, ring, OBS_INTERVAL, _currentTick())`
//  performs.
// ─────────────────────────────────────────────────────────────────────────────
contract OldRingMirror {
    uint16 internal constant OBS_CARDINALITY = 32;
    uint16 internal constant OBS_MASK = OBS_CARDINALITY - 1;
    uint32 internal constant OBS_INTERVAL = 15 seconds;
    uint32 internal constant MIN_TWAP = 1 seconds;

    struct Observation { uint32 ts; int56 tickCumulative; }
    Observation[OBS_CARDINALITY] internal observations;
    uint16 internal obsIndex;
    int56 internal tickCumulative;
    uint32 internal lastObsTs;
    int24 internal lastTick;
    uint32 internal lastRingTs;

    uint32 public twapWindow;

    constructor(int24 seedTick, uint32 _twapWindow) {
        twapWindow = _twapWindow;
        lastObsTs = uint32(block.timestamp);
        lastRingTs = uint32(block.timestamp);
        lastTick = seedTick;
        observations[0] = Observation(uint32(block.timestamp), 0);
        obsIndex = 1;
    }

    // PerpEngine.sol at 0d2c39c:1284-1289 (syncGeneration's ring reset).
    function reset(int24 seedTick) external {
        delete observations;
        tickCumulative = 0;
        obsIndex = 1;
        lastObsTs = uint32(block.timestamp);
        lastRingTs = uint32(block.timestamp);
        lastTick = seedTick;
        observations[0] = Observation(uint32(block.timestamp), 0);
    }

    function setWindow(uint32 w) external { twapWindow = w; }

    // PerpEngine.sol at 0d2c39c:753-769.
    function writeObs(int24 currentTick) external {
        uint32 nowTs = uint32(block.timestamp);
        unchecked {
            uint32 dt = nowTs - lastObsTs;
            if (dt > 0) {
                tickCumulative += int56(lastTick) * int56(uint56(dt));
                lastObsTs = nowTs;
            }
            if (nowTs - lastRingTs >= OBS_INTERVAL) {
                observations[obsIndex] = Observation(nowTs, tickCumulative);
                obsIndex = (obsIndex + 1) & OBS_MASK;
                lastRingTs = nowTs;
            }
        }
        lastTick = currentTick;
    }

    // PerpEngine.sol at 0d2c39c:790-833.
    function twapTick() public view returns (int24 tick, bool ok) {
        uint32 nowTs = uint32(block.timestamp);
        if (nowTs <= MIN_TWAP) return (0, false);
        uint32 target;
        unchecked { target = nowTs - twapWindow; }

        uint16 next = obsIndex;
        uint16 n;
        uint16 start;
        if (observations[next & OBS_MASK].ts != 0) {
            n = OBS_CARDINALITY; start = next;
        } else {
            n = next; start = 0;
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
}

// ── stubs (shaped after test/attacks/K3c_RotationStrandsPerpEngine.t.sol) ────

/// A mark source whose tick the test drives directly.
contract TickSource {
    int24 public t;
    function set(int24 v) external { t = v; }
    function weightedTick() external view returns (int24) { return t; }
}

contract RStubPM {
    function extsload(bytes32) external pure returns (bytes32) {
        return bytes32(uint256(79228162514264337593543950336));
    }
    function extsload(bytes32 startSlot, uint256 n) external pure returns (bytes32[] memory r) {
        startSlot; r = new bytes32[](n);
        for (uint256 i; i < n; ++i) r[i] = bytes32(uint256(79228162514264337593543950336));
    }
    function extsload(bytes32[] calldata slots) external pure returns (bytes32[] memory r) {
        r = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) r[i] = bytes32(uint256(79228162514264337593543950336));
    }
    function unlock(bytes calldata) external pure returns (bytes memory) { revert("no pool"); }
}

contract RStubHook {
    function isDead(PoolId) external pure returns (bool) { return false; }
}

contract RStubERC20 {
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    function transfer(address, uint256) external pure returns (bool) { return true; }
}

contract RStubERC721 {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract RStubRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    mapping(uint256 => address) private _q;
    constructor(address t) { currentToken = t; }
    function bumpGeneration() external { currentGeneration += 1; }
    function generationQuote(uint256 g) public view returns (address) { return _q[g]; }
    function setGenerationQuote(uint256 g, address a) external { _q[g] = a; }
    function lastSummonAt() external pure returns (uint256) { return 1; }
    function generationPoolId(uint256) external pure returns (PoolId) { return PoolId.wrap(bytes32(0)); }
    function generationToken(uint256) external view returns (address) { return currentToken; }
}
