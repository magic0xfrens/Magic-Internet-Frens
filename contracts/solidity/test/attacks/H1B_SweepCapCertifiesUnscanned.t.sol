// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";

interface IPerpH1B {
    function openCount() external view returns (uint256);
    function nextId() external view returns (uint256);
    function isLiquidatable(uint256 id) external view returns (bool);
    function liquidate(uint256 id) external;
}

/**
 * H1B — the pre-trade sweep certifies a book it never scanned.
 *
 * `PerpEngine._doSweep` loops `while (scanned < len && kills < MAX_LIQ_PER_SWAP)`
 * but assigns `complete = false` in exactly ONE place: the SWEEP_KILL_RESERVE
 * break. When the loop instead exits because `kills` hit the cap (8) with book
 * still unscanned, `complete` stays TRUE — so `CauldronHook._liqSweep` treats the
 * PRE-trade sweep as a clean bill of health and lets the swap through, having
 * killed 8 and certified the rest of a <=64 slot book as safe.
 *
 * The harm is exactly the one the flag was invented for (H1): a trade that
 * bankrupts more than 8 positions executes anyway and strands the remainder
 * insolvent at the price it just set.
 *
 * PRE-FIX this test's final assertion FAILS (the crash swap succeeds and leaves
 * liquidatable positions open). POST-FIX the crash swap reverts LiqGasStarved.
 */
contract H1B_SweepCapCertifiesUnscanned is YBase {
    uint256 internal opened;
    uint256 internal strandedAfter;
    bool internal crashReverted;
    bool internal ran;

    uint256 internal constant N_LONGS = 20;

    function doSell(uint256 tokenIn) external {
        require(msg.sender == address(this), "self");
        _sell(tokenIn, attacker);
    }

    function _openLongs() internal {
        vm.deal(attacker, 10_000 ether);
        for (uint256 i = 0; i < N_LONGS; i++) {
            vm.prank(attacker);
            (bool ok,) = address(perp).call{value: 0.05 ether, gas: 4_000_000}(
                abi.encodeWithSignature(
                    "openLong(uint8,uint256,uint256,uint256)", uint8(2), uint256(0), uint256(0), uint256(0.05 ether)
                )
            );
            if (!ok) { console2.log("open failed at i:", i); break; }
            opened++;
            // let the TWAP ring track the price this open just made, so the next
            // one is not born underwater against a stale mark
            _warp(180);
            vm.roll(block.number + 1);
            perp.poke();
        }
    }

    function _liqOpen() internal view returns (uint256 n) {
        uint256 last = IPerpH1B(address(perp)).nextId();
        for (uint256 id = 1; id < last; id++) {
            if (IPerpH1B(address(perp)).isLiquidatable(id)) n++;
        }
    }

    function _run() internal {
        _boot(60 ether, 0);
        if (!active) return;
        _bootPerp(60 ether, 4_000_000 ether);
        ran = true;

        // The attacker acquires inventory at the BASE price, before the longs
        // push it up. Dumping it later is what takes the book underwater.
        uint256 bag = _buy(45 ether, attacker);

        _openLongs();
        console2.log("longs opened:", opened);

        _warp(2 hours);
        vm.roll(block.number + 10);
        perp.poke();
        console2.log("openCount before crash:", IPerpH1B(address(perp)).openCount());
        console2.log("liquidatable before crash:", _liqOpen());

        // THE CRASH. One ordinary sell, fully funded with gas, whose projected
        // post-trade price condemns far more than MAX_LIQ_PER_SWAP positions.
        //  NOTE: `vm.revertToState` rolls back THIS CONTRACT'S storage too, so
        //  every result is carried out in locals and written to storage only
        //  after the revert. Recording inside the branch made this test pass
        //  vacuously against the fixed engine.
        uint256 snap = vm.snapshotState();
        (bool ok,) = address(this).call{gas: 28_000_000}(abi.encodeWithSelector(this.doSell.selector, bag));
        uint256 stranded = ok ? _liqOpen() : 0;
        uint256 openAfter = ok ? IPerpH1B(address(perp)).openCount() : 0;
        vm.revertToState(snap);
        crashReverted = !ok;
        strandedAfter = stranded;
        console2.log("crash swap reverted:", crashReverted);
        console2.log("openCount after crash:", openAfter);
        console2.log("liquidatable positions still open after the crash:", stranded);
    }

    function test_H1B_preTradeSweepMayNotCertifyAnUnscannedBook() public {
        _run();
        assertTrue(ran, "fork harness did not boot (FORK_RPC unset?)");
        assertGt(opened, 8, "could not build a book larger than MAX_LIQ_PER_SWAP");

        // THE PROPERTY: a swap is never allowed to complete while the pre-trade
        // sweep left liquidatable positions unscanned. Either the sweep cleared
        // the whole book, or the swap refused to run.
        assertEq(strandedAfter, 0, "swap filled and stranded liquidatable positions open");
        // ...and the mechanism: the pre-trade sweep refused to certify the book
        // it had not finished scanning, so the trade never ran.
        assertTrue(crashReverted, "pre-trade sweep certified an unscanned book and let the trade through");
    }

    /// LIVENESS. The refusal above is keyed to the PROJECTION of the pending
    /// trade, not to the book's size, so the pool is not frozen: the same flow
    /// goes through in slices that each condemn at most MAX_LIQ_PER_SWAP, and
    /// whatever a slice leaves underwater is reachable by the permissionless
    /// {PerpEngine.liquidate}, which does not route through the swap path.
    function test_H1B_theRefusedFlowStillGoesThroughAndTheBookStillDrains() public {
        _boot(60 ether, 0);
        if (!active) return;
        ran = true;

        _bootPerp(60 ether, 4_000_000 ether);
        uint256 bag = _buy(45 ether, attacker);
        _openLongs();
        assertGt(opened, 8, "could not build a book larger than MAX_LIQ_PER_SWAP");
        _warp(2 hours);
        vm.roll(block.number + 10);
        perp.poke();

        // The one-shot dump is refused (that is the fix).
        uint256 snap = vm.snapshotState();
        (bool big,) = address(this).call{gas: 28_000_000}(abi.encodeWithSelector(this.doSell.selector, bag));
        vm.revertToState(snap);
        console2.log("one-shot dump filled:", big);

        // The SAME flow, in slices. Each slice's pre-trade sweep clears what that
        // slice condemns, so the market keeps trading.
        uint256 fills;
        uint256 sold;
        for (uint256 i = 0; i < 10; i++) {
            (bool okS,) = address(this).call{gas: 28_000_000}(abi.encodeWithSelector(this.doSell.selector, bag / 10));
            if (okS) { fills++; sold += bag / 10; }
            vm.roll(block.number + 1);
            _warp(13);
            perp.poke();
        }
        console2.log("slices filled:", fills);
        console2.log("openCount after the sliced dump:", IPerpH1B(address(perp)).openCount());

        // Anything still underwater is drainable from OUTSIDE a swap.
        uint256 killed;
        for (uint256 round = 0; round < 40 && _liqOpen() > 0; round++) {
            uint256 last = IPerpH1B(address(perp)).nextId();
            for (uint256 id = 1; id < last; id++) {
                if (!IPerpH1B(address(perp)).isLiquidatable(id)) continue;
                vm.prank(trader);
                (bool k,) = address(perp).call(abi.encodeWithSignature("liquidate(uint256)", id));
                if (k) { killed++; break; }
            }
            vm.roll(block.number + 1);
            _warp(13);
            perp.poke();
        }
        console2.log("keeper kills:", killed);
        console2.log("liquidatable left:", _liqOpen());

        assertTrue(ran, "fork harness did not boot (FORK_RPC unset?)");
        assertGt(fills, 0, "the pool is frozen: no sell of any size fills");
        assertGt(sold, 0, "no flow got through at all");
        assertEq(_liqOpen(), 0, "book could not be drained - pool is freezable");
    }
}
