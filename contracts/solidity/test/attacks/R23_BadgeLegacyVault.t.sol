// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {UnifiedVaultDonationTest} from "../audit_full_scope/UnifiedVaultDonation.t.sol";
import {CauldronVault} from "../../cauldron/CauldronVault.sol";

contract R23BadgeLegacyVault is UnifiedVaultDonationTest {
    function test_badgeRejectedWithoutConsumingLegacyArtBacking() public {
        vault = address(floorVault);
        collection.setLiquidatorMinter(address(this));
        uint256 badge = collection.mintLiquidator(holder);
        _donate(2);
        uint256 beforeBalance = holder.balance;
        vm.expectRevert(CauldronVault.NotOwner.selector);
        vm.prank(holder);
        floorVault.redeem(badge);
        assertEq(collection.ownerOf(badge), holder);
        assertEq(floorVault.redeemed(), 0);
        assertEq(floorVault.outstanding(), 2);
        assertEq(holder.balance, beforeBalance);
        assertEq(address(floorVault).balance, 2);
        // Both legitimate art claims must remain usable after badge rejection.
        vm.startPrank(holder);
        assertEq(floorVault.redeem(1), 1);
        assertEq(floorVault.redeem(2), 1);
        vm.stopPrank();
        assertEq(holder.balance - beforeBalance, 2);
        assertEq(floorVault.outstanding(), 0);
    }
}
