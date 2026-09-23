// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReauditLocalManagers} from "../audit_reaudit/RotationTotalityLocal.t.sol";
import {MigrationVesting} from "../../cauldron/MigrationVesting.sol";
import {CauldronBase} from "../../cauldron/CauldronBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract R23EmptyVestingPolicy {
    function isInstant(address) external pure returns (bool) {
        assembly ("memory-safe") { return(0, 0) }
    }
}

contract R23VestingRegistryLocal is ReauditLocalManagers {
    function test_R23_MalformedPolicyPreservesGatedMigrationAndClaim() public {
        _boot(20 ether, 0);
        address dead = token;
        uint256 amount = _buy(0.1 ether, victim);
        assertGt(amount, 0, "funded circulating balance");
        uint256 later = vm.getBlockTimestamp() + 25 hours;
        vm.warp(later);
        assertEq(vm.getBlockTimestamp(), later);
        (address live,) = registry.relaunch();
        assertEq(registry.currentGeneration(), 2);
        MigrationVesting vest = new MigrationVesting(
            address(registry), address(this), 72 hours, address(new R23EmptyVestingPolicy())
        );
        registry.armEmergency();
        registry.setClaimGate(address(vest));
        vm.expectRevert(CauldronBase.VestingEnforced.selector);
        vm.prank(victim);
        registry.claimByBurn(1, amount);
        vm.startPrank(victim);
        IERC20(dead).approve(address(vest), amount);
        uint256 escrowed = vest.startVest(1, amount);
        vm.stopPrank();
        // PoolOps.migrateOne permits CLAIM_DUST (1e12) reserve rounding.
        // Vesting must account for actual receipt, never the nominal burn.
        assertGt(escrowed, 0);
        assertLe(escrowed, amount);
        assertLe(amount - escrowed, 1e12, "documented reserve dust bound");
        assertEq(IERC20(dead).balanceOf(victim), 0);
        assertEq(IERC20(live).balanceOf(address(vest)), escrowed);
        assertEq(IERC20(live).balanceOf(victim), 0, "no instant bypass");
        assertEq(vest.locked(victim), escrowed);
        later = vm.getBlockTimestamp() + 72 hours;
        vm.warp(later);
        assertEq(vm.getBlockTimestamp(), later);
        vest.claimFor(victim);
        assertEq(IERC20(live).balanceOf(victim), escrowed, "beneficiary receives exact reserve claim");
        assertEq(IERC20(live).balanceOf(address(vest)), 0);
        assertEq(vest.grantCount(victim), 0);
    }
}
