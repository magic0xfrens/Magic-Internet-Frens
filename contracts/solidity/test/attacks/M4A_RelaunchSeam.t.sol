// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/// Lifecycle seam probe: does the relaunch liveness property hold?
contract M4A_RelaunchSeam is YBase {
    struct Res {
        bool booted;
        bool gen2ok;
        bool gen3ok;
        uint256 gen;
        uint256 activeId2;
        uint256 reserveId2;
        bytes err2;
        bytes err3;
    }

    Res internal R;

    function setUp() public {
        _boot(25 ether, 0);
        R.booted = active;
    }

    function _tryRelaunch() internal returns (bool ok, bytes memory err) {
        (ok, err) = address(registry).call(abi.encodeWithSignature("relaunch()"));
    }

    function _run() internal {
        if (!R.booted) return;
        _warp(26 hours);
        assertGt(vm.getBlockTimestamp(), 0, "warp landed");

        (R.gen2ok, R.err2) = _tryRelaunch();
        R.gen = registry.currentGeneration();
        R.activeId2 = registry.generationPositionId(2);
        R.reserveId2 = registry.generationReservePositionId(2);
        console2.log("gen after first relaunch", R.gen);
        console2.log("activeId2", R.activeId2);
        console2.log("reserveId2", R.reserveId2);
        if (!R.gen2ok) console2.logBytes(R.err2);

        _warp(26 hours);
        (R.gen3ok, R.err3) = _tryRelaunch();
        console2.log("gen after second relaunch", registry.currentGeneration());
        if (!R.gen3ok) console2.logBytes(R.err3);
    }

    /// POSITIVE CONTROL: relaunch must always eventually succeed, twice in a row.
    function test_relaunch_liveness_positive_control() public {
        _run();
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        assertTrue(R.booted, "fork harness must be live");
        assertTrue(R.gen2ok, "relaunch #1 must succeed");
        assertTrue(R.gen3ok, "relaunch #2 must succeed");
        assertEq(registry.currentGeneration(), 3, "gen must be 3");
        assertTrue(R.reserveId2 != 0, "gen2 must hold a redemption reserve position");
    }
}
