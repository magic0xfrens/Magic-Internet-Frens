// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {LocalLifecycleBoot} from "../audit_full_scope/LocalLifecycleAdapters.t.sol";
import {YNoFrens, YRelaunchRunner} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/// Local lane: real PoolManager/PositionManager/Permit2, production hook,
/// registry, facet and engine. Mock governor (YGov) supplies the winning brew.
/// Property: a relaunch that COMPLETES must not leave perp positions open —
/// CauldronHook.forceClosePerps reverts PerpsOpen for survivors, but the
/// registry skips that call entirely when gasleft() <= RELAUNCH_TAIL_RESERVE.
contract R23RelaunchGasSkip is LocalLifecycleBoot {
    address internal longTrader = address(0x10A6);
    address internal shortTrader = address(0x5A07);
    uint256 internal longId;
    uint256 internal shortId;

    function _openBookAndKill() internal {
        _boot(20 ether, 0);
        perp = new PerpEngine(pm, address(hook), address(registry), address(new YNoFrens()),
            address(0xD1D1), address(0x7E7E), address(this));
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 60 ether}(60 ether);
        deal(token, address(this), 200_000_000 ether, true);
        IERC20Minimal(token).approve(address(perp), 200_000_000 ether);
        perp.fundPlvToken(200_000_000 ether);
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        _warp(25 hours);
        vm.roll(vm.getBlockNumber() + 40);
        // Observations through ordinary trading, never public poke.
        _buy(0.001 ether, attacker);

        vm.deal(longTrader, 2 ether);
        vm.prank(longTrader, longTrader);
        longId = perp.openLong{value: 0.5 ether}(2, 0, 0, 0.5 ether);
        vm.deal(shortTrader, 2 ether);
        vm.prank(shortTrader, shortTrader);
        shortId = perp.openShort{value: 0.5 ether}(2, 0, 0, 0.5 ether);
        assertEq(perp.openCount(), 2, "two funded positions open");

        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        assertTrue(hook.isDead(registry.generationPoolId(1)), "generation 1 dead");
    }

    /// Control: ample gas force-closes the book in-call and re-arms the engine.
    function test_fullGasRelaunchClosesBook() public {
        _openBookAndKill();
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2);
        assertEq(perp.openCount(), 0, "book drained in-call");
        assertEq(perp.syncedGeneration(), 2, "engine re-armed");
    }

    /// Property: no gas budget yields a completed relaunch with open positions.
    function test_noGasBudgetCompletesRelaunchWithOpenPerps() public {
        _openBookAndKill();
        YRelaunchRunner runner = new YRelaunchRunner();
        uint256 snap = vm.snapshotState();
        uint256 successes;
        uint256 stranded;
        uint256 firstStrandedCap;
        for (uint256 cap = 6_000_000; cap <= 26_000_000; cap += 500_000) {
            vm.revertToState(snap);
            bool ok = runner.tryRelaunch(address(registry), cap);
            if (!ok) continue;
            successes++;
            uint256 open = perp.openCount();
            console2.log("relaunch ok at cap", cap, "openCount after", open);
            if (open != 0) {
                stranded++;
                if (firstStrandedCap == 0) firstStrandedCap = cap;
            }
        }
        console2.log("successful caps", successes, "stranded successes", stranded);
        assertGt(successes, 0, "scan reached at least one completed relaunch");

        if (firstStrandedCap != 0) {
            // Characterize recoverability at the first stranding budget.
            vm.revertToState(snap);
            assertTrue(runner.tryRelaunch(address(registry), firstStrandedCap));
            assertEq(registry.currentGeneration(), 2, "rebirth completed");
            console2.log("engine syncedGeneration", perp.syncedGeneration());
            (bool okSync,) = address(perp).call(abi.encodeWithSignature("syncGeneration()"));
            (bool okForce,) = address(perp).call(abi.encodeWithSignature("forceCloseAllDead()"));
            vm.prank(longTrader, longTrader);
            (bool okLong,) = address(perp).call(abi.encodeWithSignature("close(uint256,uint256)", longId, 0));
            vm.prank(shortTrader, shortTrader);
            (bool okShort,) = address(perp).call(abi.encodeWithSignature("close(uint256,uint256)", shortId, 0));
            console2.log("syncGeneration ok", okSync);
            console2.log("forceCloseAllDead ok", okForce);
            console2.log("long close ok", okLong);
            console2.log("short close ok", okShort);
            console2.log("openCount after recovery attempts", perp.openCount());
        }
        assertEq(stranded, 0, "a completed relaunch must never leave perps open");
    }
}
