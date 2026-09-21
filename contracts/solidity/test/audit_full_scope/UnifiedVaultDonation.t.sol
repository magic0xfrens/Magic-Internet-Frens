// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {CauldronVault} from "../../cauldron/CauldronVault.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/// Production collection/vault/ledger; this fixture supplies the authorized
/// hook and registry roles. No production storage is force-written.
contract UnifiedVaultDonationTest is Test {
    address public vault; // The production hook's explicit ETH-floor mode getter.
    CauldronCollection internal collection;
    CauldronVault internal floorVault;
    CollectionLedger internal ledger;
    address internal holder = address(0xA11CE);
    address internal donor = address(0xD0A0);

    function setUp() public {
        collection = new CauldronCollection(
            "Audit brew", "AB", address(this), address(this), 10,
            MetadataMode.BaseURI, "ipfs://audit/", address(0), address(0), 0
        );
        floorVault = new CauldronVault(address(collection), address(this), 0);
        collection.setVault(address(floorVault));
        ledger = new CollectionLedger(address(this));
        collection.mint(holder);
        collection.mint(holder);
        // Mechanism-only claim accounting, not a funded registry reserve test.
        ledger.credit(1, 100 ether);
        vm.deal(donor, 1 ether);
    }

    function _donate(uint256 amount) internal {
        vm.prank(donor);
        (bool ok,) = address(floorVault).call{value: amount}("");
        assertTrue(ok);
        assertEq(floorVault.accountedDeposits(), 0, "outsider is not protocol funding");
    }

    function test_donationCannotRearmBurningWhileUnifiedFloorIsActive() public {
        assertEq(vault, address(0), "unified configuration");
        _donate(2);
        assertEq(floorVault.floorPerNFT(), 0, "disabled mode has no redeemable ETH floor");
        vm.prank(holder);
        vm.expectRevert(CauldronVault.UnifiedFloorActive.selector);
        floorVault.redeem(1);
        assertEq(collection.ownerOf(1), holder);
        assertEq(floorVault.redeemed(), 0);
        assertEq(ledger.outstanding(1, collection.totalMinted()), 2);
    }

    function test_forcedBalanceCannotRearmUnifiedVault() public {
        // Models forced ETH: receive/accountedDeposits is deliberately bypassed.
        vm.deal(address(floorVault), 1 ether);
        vm.prank(holder);
        vm.expectRevert(CauldronVault.UnifiedFloorActive.selector);
        floorVault.redeem(1);
        assertEq(collection.ownerOf(1), holder);
        assertEq(address(floorVault).balance, 1 ether);
    }

    function test_explicitLegacyFloorStillPaysDonation() public {
        vault = address(floorVault);
        _donate(2);
        assertEq(floorVault.floorPerNFT(), 1);
        uint256 before = holder.balance;
        vm.prank(holder);
        assertEq(floorVault.redeem(1), 1);
        assertEq(holder.balance - before, 1);
        assertEq(floorVault.redeemed(), 1);
        assertEq(floorVault.outstanding(), 1);
    }

    function test_differentActiveVaultCannotEnableBurn() public {
        vault = address(0xBEEF);
        _assertInactiveGetter();
    }

    function test_revertingGetterFailsClosed() public {
        vm.mockCallRevert(address(this), abi.encodeWithSignature("vault()"), hex"12345678");
        _assertInactiveGetter();
    }

    function test_unsupportedGetterFailsClosed() public {
        vm.mockCall(address(this), abi.encodeWithSignature("vault()"), bytes(""));
        _assertInactiveGetter();
    }

    function test_eoaMinterFailsClosed() public {
        vm.mockCall(address(collection), abi.encodeWithSignature("minter()"), abi.encode(address(0xDEAD)));
        _assertInactiveGetter();
    }

    function test_malformedAddressGetterFailsClosed() public {
        vm.mockCall(address(this), abi.encodeWithSignature("vault()"), abi.encode(type(uint256).max));
        _assertInactiveGetter();
    }

    function _assertInactiveGetter() internal {
        vm.deal(address(floorVault), 1 ether);
        assertEq(floorVault.floorPerNFT(), 0);
        vm.prank(holder);
        vm.expectRevert(CauldronVault.UnifiedFloorActive.selector);
        floorVault.redeem(1);
        assertEq(collection.ownerOf(1), holder);
        assertEq(floorVault.redeemed(), 0);
    }
}
