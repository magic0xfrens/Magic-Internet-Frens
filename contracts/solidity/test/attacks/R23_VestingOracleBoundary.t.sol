// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MigrationVestingTest} from "../MigrationVesting.t.sol";

contract R23VestingPolicy {
    uint256 immutable mode;
    constructor(uint256 m) { mode = m; }
    function isInstant(address) external view returns (bool) {
        if (mode == 0) revert("policy unavailable");
        if (mode == 1) assembly ("memory-safe") { return(0, 0) }
        assembly ("memory-safe") { mstore(0, 2) return(0, 32) }
    }
}

/// Synthetic owner-configured dependency failures; not permissionless policy control.
contract R23VestingOracleBoundaryTest is MigrationVestingTest {
    function _assertConservativeMigration() internal {
        _startVest(alice, 1_000e18);
        assertEq(genA.balanceOf(alice), 0, "dead balance consumed");
        assertEq(genB.balanceOf(alice), 0, "must not grant instant access");
        assertEq(genB.balanceOf(address(vest)), 1_000e18, "escrow funded");
        assertEq(vest.locked(alice), 1_000e18, "normal vest remains available");
        assertEq(vest.grantCount(alice), 1, "grant recorded");
    }

    function test_R23_RevertingPolicyFallsBack() public {
        vest.setStakerOracle(address(new R23VestingPolicy(0)));
        _assertConservativeMigration();
    }

    function test_R23_EmptyPolicyFallsBack() public {
        vest.setStakerOracle(address(new R23VestingPolicy(1)));
        _assertConservativeMigration();
    }

    function test_R23_NonCanonicalBoolFallsBack() public {
        vest.setStakerOracle(address(new R23VestingPolicy(2)));
        _assertConservativeMigration();
    }

    function test_R23_CodeLessPolicyFallsBack() public {
        address policy = address(0x123456);
        assertEq(policy.code.length, 0, "explicit code-less precondition");
        vest.setStakerOracle(policy);
        _assertConservativeMigration();
    }
}
