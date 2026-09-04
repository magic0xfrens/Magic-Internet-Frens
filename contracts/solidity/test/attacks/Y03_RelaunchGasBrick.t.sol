// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

import {YBase, YRelaunchRunner} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  Y-03 — RELAUNCH GAS BRICK  (resolves audit Z-07, then regresses the fix)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  Z-07 was "Likely / Residual — no PoC": two consumers inside `relaunch()` —
 *  `hook.forceClosePerps()` (up to 64 real settlement swaps) and
 *  `hook.resolveTickets(300)` (up to 300 NFT mints) — were called with NO gas
 *  cap, so under the EVM 63/64 rule an out-of-gas child consumes all but 1/64
 *  of the gas and the `try/catch` resumes with far too little to finish the
 *  rebirth: relaunch reverts. A full perp book costs only ~0.2 ETH to build
 *  (64 × minCollateral dust longs, leverage-1 → zero OI so no cap binds).
 *
 *  FIX (applied this pass): both sub-calls are now capped to
 *  `gasleft() - RELAUNCH_TAIL_RESERVE`, so an OOG child consumes only its
 *  budget and the rebirth always completes; survivors are cleared afterwards by
 *  the permissionless `forceCloseDead` / `resolveTickets` paths.
 *
 *  This suite drives `relaunch()` through a runner with a HARD gas cap (so the
 *  63/64 rule bites exactly as it would against an L2 block-gas limit) and a
 *  maximally-spammed book, and asserts the rebirth SURVIVES.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract Y03_RelaunchGasBrick is YBase {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    YRelaunchRunner runner;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        _bootPerp(60 ether, 200_000_000 ether);
        runner = new YRelaunchRunner();
        vm.roll(block.number + 60);
    }

    /// @notice REGRESSION (Z-07): a maximally-spammed perp book no longer bricks
    ///         the rebirth under a constrained gas budget. The relaunch is run
    ///         with a hard cap that is comfortably enough for the rebirth tail but
    ///         NOT enough to force-close all 64 positions — exactly the condition
    ///         that used to strand the parent at 1/64 of its gas. With the sub-call
    ///         cap, the rebirth completes; any un-closed positions are then cleared
    ///         permissionlessly and the engine re-arms.
    function test_FIXED_Z07_FullBookRelaunchSurvivesAGasCap() public {
        if (!active) return;

        // Fill the book to the hard cap with leverage-1 dust longs (zero OI).
        uint256 cap = perp.MAX_OPEN_POSITIONS();
        for (uint256 i; i < cap; i++) {
            address bot = address(uint160(0xD05700 + i));
            vm.deal(bot, 0.01 ether);
            vm.prank(bot, bot);
            perp.openLong{value: 0.004 ether}(1, 0, 0, 0.004 ether);
        }
        assertEq(perp.openCount(), cap, "book filled to the cap");

        // Make the pool dead + past the wall-clock death window (audit Z-05).
        hook.setDeathThreshold(type(uint256).max);
        _warp(registry.minLifetime() + 1 days + 1);

        // Run relaunch with a hard cap. 24M is plenty for the rebirth tail
        // (~8-10M) yet cannot force-close 64 × ~450k (~29M) — the pre-fix brick
        // condition. With the cap the rebirth must still complete.
        bool ok = runner.tryRelaunch(address(registry), 24_000_000);
        assertTrue(ok, "FIXED: rebirth completes under a constrained gas budget");
        assertEq(registry.currentGeneration(), 2, "reborn to gen 2");

        // Any survivors of the bounded force-close are cleared permissionlessly,
        // then the engine re-arms on the new generation — nothing is stranded.
        uint256 guard;
        while (perp.openCount() != 0 && guard < 8) {
            perp.forceCloseAllDead();
            unchecked { guard++; }
        }
        assertEq(perp.openCount(), 0, "leftovers cleared post-relaunch");

        if (perp.syncedGeneration() != 2) perp.syncGeneration();
        assertEq(perp.syncedGeneration(), 2, "engine re-armed on gen 2");
    }

    /// @notice SAFE: with generous gas the whole book is force-closed inside the
    ///         single relaunch call (the A-03 one-call-drains guarantee), and the
    ///         engine re-arms automatically — the cap never makes the good path
    ///         worse.
    function test_SAFE_Z07_FullBookRelaunchDrainsWithAmpleGas() public {
        if (!active) return;

        uint256 cap = perp.MAX_OPEN_POSITIONS();
        for (uint256 i; i < cap; i++) {
            address bot = address(uint160(0xD06700 + i));
            vm.deal(bot, 0.01 ether);
            vm.prank(bot, bot);
            perp.openLong{value: 0.004 ether}(1, 0, 0, 0.004 ether);
        }
        hook.setDeathThreshold(type(uint256).max);
        _warp(registry.minLifetime() + 1 days + 1);

        registry.relaunch(); // full gas
        assertEq(registry.currentGeneration(), 2, "reborn");
        assertEq(perp.openCount(), 0, "whole book drained in-call");
        assertEq(perp.syncedGeneration(), 2, "engine re-armed automatically");
    }
}
