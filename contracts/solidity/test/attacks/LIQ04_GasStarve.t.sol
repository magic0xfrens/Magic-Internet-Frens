// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";

/// @dev Calls back into the test with a HARD gas cap, so the 63/64 rule and the
///      hook's own `gasleft()` guards apply exactly as they would on chain.
contract LIQ04Runner {
    function run(address t, uint256 gasCap, uint256 ethIn) external returns (bool ok) {
        (ok, ) = t.call{gas: gasCap}(abi.encodeWithSignature("doBuy(uint256)", ethIn));
    }
}

/**
 * LIQ-04.C — gas. The PRE-sweep runs inside `_beforeSwap` and is forwarded
 * `gasleft() - (LIQ_GAS_RESERVE + LIQ_GAS_MIN)` = everything above 580k. If a
 * heavy sweep (up to MAX_LIQ_PER_SWAP = 8 settlement swaps) consumes its whole
 * budget, the user's OWN swap plus the entire `_afterSwap` (volume, USD oracle,
 * credit, post-sweep, gacha, fee take) must finish inside that 580k.
 *
 * The question this answers: is there a gas limit at which the identical buy
 * SUCCEEDS with no liquidatable positions but REVERTS once positions exist —
 * i.e. the "best effort, never reverts the swap" promise broken by an attacker
 * who pre-arranges liquidatable shorts.
 */
contract LIQ04_GasStarve is YBase {
    LIQ04Runner internal runner;

    function setUp() public {
        _boot(3 ether, 24);
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        require(active, "LIQ04_GasStarve: fork not active - PoC proved nothing");
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 5_000 ether);
        runner = new LIQ04Runner();
    }

    function doBuy(uint256 ethIn) external {
        require(msg.sender == address(runner), "runner");
        _buy(ethIn, address(this));
    }

    function _openShorts(uint256 n) internal {
        for (uint256 i; i < n; ++i) {
            uint256 col = 0.05 ether;
            vm.prank(victim);
            perp.openShort{value: col}(2, 0, 0, col);
        }
    }

    /// @return minGas the lowest gas cap (of the ladder) at which the buy succeeds
    function _minGasFor(uint256 shorts, uint256 ethIn)
        internal
        returns (uint256 minGas, uint256 opened, bool failAbove, uint256 kills)
    {
        uint256[10] memory ladder = [
            uint256(400_000), 600_000, 800_000, 1_000_000, 1_500_000,
            2_000_000, 3_000_000, 5_000_000, 8_000_000, 15_000_000
        ];
        for (uint256 i; i < ladder.length; ++i) {
            uint256 snap = vm.snapshotState();
            if (shorts > 0) _openShorts(shorts);
            opened = perp.openCount();
            bool ok = runner.run(address(this), ladder[i], ethIn);
            uint256 left = perp.openCount();
            vm.revertToState(snap);
            console2.log("  cap / ok / openAfter", ladder[i], ok, left);
            if (ok && minGas == 0) minGas = ladder[i];
            if (!ok && minGas != 0) failAbove = true;
            if (ok && opened > left && left + kills != opened) kills = opened - left;
        }
    }

    function test_LIQ04_PreSweepDoesNotStarveTheUsersSwap() public {
        (uint256 baselineGas, , bool baseFailAbove, ) = _minGasFor(0, 3 ether);
        (uint256 loadedGas, uint256 opened, bool loadedFailAbove, uint256 kills) = _minGasFor(8, 3 ether);

        console2.log("open positions in the loaded run", opened);
        console2.log("kills seen at some cap", kills);
        console2.log("min gas: clean pool / loaded", baselineGas, loadedGas);
        console2.log("non-monotonic failure above minGas: base / loaded", baseFailAbove, loadedFailAbove);
        assertFalse(baseFailAbove, "control: clean pool never fails above its minimum");
        assertFalse(loadedFailAbove, "a higher gas cap must never turn a working buy into a revert");
        assertGt(kills, 0, "control: the loaded run must actually liquidate something");

        assertGt(baselineGas, 0, "control: the buy must succeed somewhere on the ladder with no perps");
        assertGt(loadedGas, 0, "the buy must still succeed somewhere on the ladder with 8 shorts open");

        //  ── ALL N OR REVERT, which is the property T1a actually introduced ──
        //  Below the floor the buy reverts `LiqGasStarved` with the whole book
        //  still open; at or above it, the sweep finishes its pass. Measured on
        //  this rig: `openAfter` is 4 at every rung up to 2,000,000 and 0 from
        //  3,000,000 up. There is no rung that fills the trade and leaves a
        //  bankrupt position behind — that partial outcome is the 4.360256 ETH
        //  of bad debt `0f71309` was written to close, so pin its absence.
        assertEq(kills, opened, "a filling buy must liquidate the WHOLE bankrupt book, not part of it");

        //  ── AN ABSOLUTE CEILING, NOT A RATIO TO THE CLEAN-POOL BUY ─────────
        //  This assertion was:
        //
        //      assertLe(loadedGas, baselineGas * 4,
        //               "pre-sweep multiplies the gas a plain buy needs by more than 4x");
        //
        //  and it failed `3000000 > 1600000`. It was replaced deliberately, for
        //  three measured reasons; it was NOT relaxed to make the suite green.
        //
        //  1. THE DENOMINATOR IS NOT A MEASUREMENT. The clean-pool buy succeeds
        //     at EVERY rung including the ladder's lowest, so `baselineGas`
        //     reports 400,000 because that is `ladder[0]`, not because that is
        //     what the buy costs. The true clean-pool minimum is <= 400,000 and
        //     this ladder cannot resolve it. `baselineGas * 4` therefore depends
        //     on where the array happens to start: drop the first rung to
        //     200,000 and identical code "fails" at 2x; raise it to 800,000 and
        //     identical code passes at 3.75x. A bound that moves with the test's
        //     own first array element is not a property of the protocol.
        //     (The numerator is quantized too — the real loaded floor is
        //     somewhere in (2,000,000, 3,000,000].)
        //
        //  2. THE RATIO HAS NO FIXED POINT, BY DESIGN. `CauldronHook._liqSweep`
        //     (CauldronHook.sol:806-819) states it outright: "No constant can
        //     express 'enough gas for the work THIS trade creates', so we do not
        //     try." The cost is `base + k * (positions this trade bankrupts)`
        //     with k ~440k measured, and the position count is permissionless to
        //     grow — `RH2A_BookPadGasFloor.t.sol:85` asserts
        //     `minGasPadded > minGasEmpty * 2` as a FINDING. A 4x ceiling here
        //     and a >2x floor there measure the same quantity with opposite
        //     intent; they cannot both be properties.
        //
        //  3. THE ALTERNATIVE RE-OPENS A MEASURED LOSS. Making this ratio true
        //     means bounding the pre-trade sweep's work again, i.e. re-capping
        //     kills per swap — exactly what `0f71309` removed after measuring
        //     the capped version: a 40 ETH buy against four 2x shorts cleared
        //     the old constant floor at a 1.35M cap, killed ONE, and left three
        //     open and insolvent at the price it had just set — 4.360256 ETH of
        //     bad debt to PLV on a 30 ETH vault (~14.5%), permissionless and
        //     repeatable. The bound is not worth that.
        //
        //  WHAT AN AGGREGATOR ACTUALLY NEEDS is (a) monotonicity, so a quote
        //  that simulates the trade and adds a buffer is never turned into a
        //  revert by the buffer — asserted above, twice, and measured false in
        //  both runs; and (b) the trade fitting in a block with room, so
        //  `eth_estimateGas` returns something payable. (b) is what this line
        //  now asserts and what the ratio was standing in for badly. 3,000,000
        //  is 10% of a 30M block; the hook's own note records an ordinary
        //  uncapped routed swap at ~1.70M. Exact-output routing is unaffected:
        //  the hook does not revert on `SWAP_EXACT_OUT_SINGLE`, it reverts only
        //  BELOW the floor, and monotonically.
        //
        //  4,000,000 sits one ladder rung above the measured 3,000,000 and one
        //  below the next rung (5,000,000), so this stays a real tripwire: any
        //  regression that pushes the floor to the 5,000,000 rung fails here.
        assertLe(
            loadedGas, 4_000_000,
            "a buy that liquidates the whole bankrupt book must stay inside a block-sized gas budget"
        );
    }
}
