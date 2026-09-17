// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";

/**
 * RING2 — verification counter-PoC for hunter finding RING1-A.
 *
 * RING1-A's mechanism is real: `syncGeneration` seeds `ring.lastTick` with
 * `_currentTick()` at PerpEngine.sol:1288, TEN LINES BEFORE `quote = newQuote`
 * (:1440) and `markSource = address(0)` (:1442), so the seed is the DYING
 * generation's tick. That much this file re-confirms.
 *
 * Its claimed IMPACT — "for 5-10 minutes after every relaunch a position can be
 * opened against the dead pool's mark and liquidated in the same block" — rests
 * on the ring gate being the binding one:
 *
 *   cauldron/PerpEngine.sol:1830-1832
 *     uint256 summonWarm = registry.lastSummonAt() + warmup;
 *     uint256 ringWarm   = uint256(ringArmedAt) + twapWindow;
 *     if (block.timestamp < (summonWarm < ringWarm ? ringWarm : summonWarm)) revert NotWarm();
 *
 * On a RELAUNCH the two clocks start in the SAME TRANSACTION:
 *   CauldronRegistry.sol:894   lastSummonAt = block.timestamp;
 *   CauldronRegistry.sol:1151  _perpHousekeep(true);  ->  syncGeneration()
 * so `summonWarm = armedAt + warmup (24h)` and `ringWarm = armedAt + 5 min`.
 * The MAX of the two is taken, so the 24h summon warmup swallows the entire
 * stale-seed window.
 *
 * RING1's own harness cannot see this: its registry stub hard-codes
 * `lastSummonAt() => 1` (RING1_TwapRingExtraction.t.sol:441), i.e. a summon
 * warmup that expired before the test began. This file restores the real
 * registry behaviour and nothing else.
 */
contract RING2_RelaunchWarmupOutlastsSeed is Test {
    R2StubPM pm;
    R2StubRegistry reg;
    R2StubHook hook;
    R2StubERC721 frens;
    PerpEngine perp;
    R2TickSource src;

    address timelock = address(0x7171);
    address token;

    function setUp() public {
        vm.warp(1_700_000_000); // a realistic clock, not genesis
        token = address(new R2StubERC20());
        pm = new R2StubPM();
        reg = new R2StubRegistry(token);
        hook = new R2StubHook();
        frens = new R2StubERC721();
        src = new R2TickSource();

        perp = new PerpEngine(
            IPoolManager(address(pm)), address(hook), address(reg),
            address(frens), address(0xD1), address(0x7E), timelock
        );
        // Governance has wired a weighted mark source for the LIVE generation —
        // the precondition RING1-A needs for the seed to be foreign at all.
        vm.prank(timelock);
        perp.setRouting(address(0xD1), address(0x7E), address(0x7E), address(src), address(0));
    }

    function _step(uint32 dt, int24 tick) internal {
        vm.warp(vm.getBlockTimestamp() + dt);
        src.set(tick);
        perp.poke();
    }

    /// @dev A faithful relaunch: the registry bumps the generation, restarts the
    ///      grace clock, and syncs the engine — all in ONE transaction, exactly
    ///      as CauldronRegistry.relaunch does (:894 then :1151).
    function _relaunch() internal returns (uint256 armedAt) {
        reg.relaunch();            // currentGeneration++, lastSummonAt = now
        perp.syncGeneration();     // _perpHousekeep(true)
        armedAt = vm.getBlockTimestamp();
    }

    /// The stale seed is REAL but lands entirely inside a window in which no
    /// position can be opened. Both halves are asserted.
    function test_RING2_theStaleSeedIsUnreachableBehindTheSummonWarmup() public {
        // The dying generation trades at tick +60000.
        for (uint256 i; i < 40; ++i) { _step(30, 60000); }

        uint256 armedAt = _relaunch();
        uint32 window = perp.twapWindow();
        uint256 warmup = perp.warmup();
        console2.log("twapWindow (s)", uint256(window));
        console2.log("summon warmup (s)", warmup);

        // ── (1) RING1-A's mechanism reproduced: at ringArmedAt + twapWindow the
        //        mark IS the dead generation's tick.
        vm.warp(armedAt + window);
        (int24 markAtRingGate, bool ok) = perp.twapTick();
        console2.log("mark at ringArmedAt + twapWindow", int256(markAtRingGate));
        assertTrue(ok, "the mark answers");
        assertEq(int256(markAtRingGate), int256(0), "FIXED RING1-A: the seed is the LIVE tick, even at the ring gate");

        // ── (2) ...and NOTHING can be opened against it. The summon warmup, restarted
        //        by the same relaunch, has 24h to run.
        vm.deal(address(this), 10 ether);
        vm.expectRevert(PerpEngine.NotWarm.selector);
        perp.openLong{value: 1 ether}(2, 0, 0, 1 ether);
        vm.expectRevert(PerpEngine.NotWarm.selector);
        perp.openShort{value: 1 ether}(2, 0, 0, 1 ether);

        // The whole 2-window contamination span finishes long before the gate.
        assertLt(armedAt + 2 * uint256(window), armedAt + warmup,
            "two full TWAP windows fit inside the summon warmup");
        console2.log("seed contamination ends at armedAt + (s)", 2 * uint256(window));
        console2.log("first openable moment at armedAt + (s)", warmup);
    }

    /// ...and by the time the gate DOES open, one single sample — any swap, any
    /// keeper `poke()`, anywhere in the 24h — has flushed the seed completely.
    function test_RING2_oneSampleInsideTheWarmupFlushesTheSeedBeforeAnyOpen() public {
        for (uint256 i; i < 40; ++i) { _step(30, 60000); }
        uint256 armedAt = _relaunch();
        uint256 warmup = perp.warmup();

        // One keeper poke a minute after the relaunch. `markSource` was dropped by
        // the sync (:1442), so `_currentTick()` now genuinely reads the NEW pool,
        // whose stub tick is 0.
        vm.warp(armedAt + 60);
        perp.poke();

        vm.warp(armedAt + warmup); // the first openable instant
        (int24 mark, bool ok) = perp.twapTick();
        console2.log("mark at the first openable instant", int256(mark));
        assertTrue(ok, "the mark answers at the gate");
        assertEq(int256(mark), int256(0), "the seed contributes nothing to the mark any open can see");

        // And the NotWarm gate is genuinely down at this instant: the open now
        // fails on the stub pool's swap, not on warmup.
        vm.deal(address(this), 10 ether);
        bytes4 got;
        try perp.openLong{value: 1 ether}(2, 0, 0, 1 ether) {
            got = bytes4(0);
        } catch (bytes memory err) {
            got = err.length >= 4 ? bytes4(err) : bytes4(0);
        }
        console2.log("open revert selector at the gate (0 = none)", vm.toString(got));
        assertTrue(got != PerpEngine.NotWarm.selector, "the warmup gate is down at armedAt + warmup");
    }


    /// The OTHER door RING1-A could use: a QUOTE ROTATION arms the ring without
    /// touching `lastSummonAt`, so the ring gate (5 min) really is the binding
    /// one there. The mechanism reproduces — AND the same function empties the
    /// capital that leverage needs, in the same transaction:
    ///
    ///   cauldron/PerpEngine.sol:1402-1403
    ///     uint256 sweep = plv + writtenOff + insuranceEth;
    ///     plv = 0; tokYieldEth = 0; insuranceEth = 0;
    ///
    /// so no leveraged open is fundable in the contaminated window until a
    /// separate, deliberate re-funding in the NEW asset.
    function test_RING2_rotationReachesTheRingGateButEmptiesTheBook() public {
        // The constructor already adopted generation 1 (native). Fund the book.
        vm.deal(timelock, 100 ether);
        vm.prank(timelock);
        perp.fundPlv{value: 50 ether}(50 ether);
        perp.fundInsurance{value: 1 ether}(1 ether);
        assertEq(perp.plv(), 50 ether, "positive control: the book is funded");
        assertEq(perp.insuranceEth(), 1 ether, "positive control: insurance is funded");

        for (uint256 i; i < 40; ++i) { _step(30, 60000); }

        // A completed rotation flips generationQuote and re-syncs in the same tx
        // (RedemptionExt.sol:582 then :617). lastSummonAt does NOT move.
        address usdg = address(new R2StubERC20());
        reg.setGenerationQuote(1, usdg);
        uint256 armedAt = vm.getBlockTimestamp();
        perp.syncGeneration();

        // The capital is gone in the same transaction that armed the ring.
        assertEq(perp.plv(), 0, "the rotation swept plv to the treasury");
        assertEq(perp.insuranceEth(), 0, "the rotation swept insurance to the treasury");

        // ...and the mark at the ring gate is indeed the dead quote's tick.
        vm.warp(armedAt + perp.twapWindow());
        (int24 mark, bool ok) = perp.twapTick();
        console2.log("rotation: mark at ringArmedAt + twapWindow", int256(mark));
        assertTrue(ok, "the mark answers");
        assertEq(int256(mark), int256(0), "FIXED RING1-A: rotation seeds the ring from the adopted pool");
    }

    /// Positive control: the gate really is the SUMMON clock and not the ring
    /// clock — one second before `lastSummonAt + warmup` it still refuses, which
    /// is what makes the two assertions above mean something.
    function test_RING2_control_theGateIsTheSummonClock() public {
        uint256 armedAt = _relaunch();
        uint256 warmup = perp.warmup();
        vm.deal(address(this), 10 ether);

        vm.warp(armedAt + warmup - 1);
        vm.expectRevert(PerpEngine.NotWarm.selector);
        perp.openLong{value: 1 ether}(2, 0, 0, 1 ether);
        console2.log("still NotWarm at armedAt + warmup - 1", armedAt + warmup - 1);

        vm.warp(armedAt + warmup);
        bytes4 got;
        try perp.openLong{value: 1 ether}(2, 0, 0, 1 ether) { got = bytes4(0); }
        catch (bytes memory err) { got = err.length >= 4 ? bytes4(err) : bytes4(0); }
        assertTrue(got != PerpEngine.NotWarm.selector, "and it opens the very next second");
    }
}

// ── stubs (shaped after RING1_TwapRingExtraction.t.sol, with the ONE fix that
//    `lastSummonAt` tracks the relaunch as CauldronRegistry.sol:894 does) ──────

contract R2TickSource {
    int24 public t;
    function set(int24 v) external { t = v; }
    function weightedTick() external view returns (int24) { return t; }
}

contract R2StubPM {
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

contract R2StubHook {
    function isDead(PoolId) external pure returns (bool) { return false; }
}

contract R2StubERC20 {
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    function transfer(address, uint256) external pure returns (bool) { return true; }
}

contract R2StubERC721 {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract R2StubRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) private _q;
    constructor(address t) { currentToken = t; lastSummonAt = block.timestamp; }
    /// CauldronRegistry.sol:892-894 + :1151 — one transaction.
    function relaunch() external { currentGeneration += 1; lastSummonAt = block.timestamp; }
    function generationQuote(uint256 g) public view returns (address) { return _q[g]; }
    function setGenerationQuote(uint256 g, address a) external { _q[g] = a; }
    function generationPoolId(uint256) external pure returns (PoolId) { return PoolId.wrap(bytes32(0)); }
    function generationToken(uint256) external view returns (address) { return currentToken; }
}
