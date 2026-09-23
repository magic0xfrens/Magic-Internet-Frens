// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";

contract R23LedgerDeathCredit is Test {
    function test_releasePreservesOtherGenerationsAndRejectsFinalCredit() public {
        CollectionLedger ledger = new CollectionLedger(address(this));
        ledger.credit(2, 77 ether);
        ledger.credit(1, 300 ether);
        for (uint256 i; i < 3; ++i) ledger.redeem(1, 3);
        ledger.credit(1, 500 ether);
        vm.expectEmit(true, false, false, true, address(ledger));
        emit CollectionLedger.EntitlementReleased(1, 500 ether);
        ledger.crystallize(1, 3, 123 ether);
        assertEq(ledger.entitledTokens(1), 0);
        assertEq(ledger.entitledTokens(2), 77 ether);
        assertEq(ledger.totalEntitled(), 77 ether);
        vm.expectRevert(CollectionLedger.AlreadyCrystallized.selector);
        ledger.crystallize(1, 3, 0);
        assertEq(ledger.totalEntitled(), 77 ether);
    }

    function test_newMintBeforeDeathPreservesClaimableCredit() public {
        CollectionLedger ledger = new CollectionLedger(address(this));
        ledger.credit(1, 300 ether);
        for (uint256 i; i < 3; ++i) ledger.redeem(1, 3);
        ledger.credit(1, 500 ether);
        ledger.crystallize(1, 4, 123 ether);
        assertEq(ledger.redeem(1, 4), 623 ether);
        assertEq(ledger.totalEntitled(), 0);
    }

    function test_liveCreditThenDeathMustNotLeaveUnclaimableEntitlement() public {
        CollectionLedger ledger = new CollectionLedger(address(this));
        ledger.credit(1, 300 ether);
        for (uint256 i; i < 3; ++i) ledger.redeem(1, 3);
        ledger.credit(1, 500 ether);
        assertEq(ledger.entitledTokens(1), 500 ether, "live accrual retained");
        ledger.crystallize(1, 3, 0);
        assertTrue(ledger.isDeadEnd(1));
        assertEq(ledger.floorPerNFT(1, 3), 0);
        vm.expectRevert(CollectionLedger.NothingOutstanding.selector);
        ledger.redeem(1, 3);
        // A frozen generation with no possible claimant should not reserve tokens.
        assertEq(ledger.entitledTokens(1), 0, "unclaimable pre-death credit");
        assertEq(ledger.totalEntitled(), 0);
    }
}
