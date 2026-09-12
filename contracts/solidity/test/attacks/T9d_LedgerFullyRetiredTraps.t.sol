// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";

/**
 * @notice T9d — REGRESSION for Z-19 (fixed).
 *
 *         Once a generation's supply is FROZEN (it died) and every one of those
 *         NFTs has been recycled, `outstanding(gen) == 0` and both exits are shut:
 *           • `redeem` reverts `NothingOutstanding` (CollectionLedger.sol:119),
 *           • `floorPerNFT == 0`, so `PoolOps.buyCollection`'s
 *             `require(paid > 0, "no floor")` (PoolOps.sol:1455-1456) can never
 *             pass and `retired` can never be decremented.
 *
 *         `credit` used to accrue into that bucket UNCONDITIONALLY, so every later
 *         royalty/buyback raised `totalEntitled` — the figure the registry must
 *         keep the shared reserve LP sized to cover ("Invariant R") and the figure
 *         it subtracts from every future generation's active tranche
 *         (CauldronRegistry.sol:1057). It now refuses, without reverting (the
 *         caller is on `relaunch()`'s critical path).
 *
 *         `test_LiveFullyRecycledGenerationStillAccrues` is the positive control:
 *         while a generation is ALIVE the same zero-outstanding state is temporary,
 *         so the credit must still land.
 */
contract T9dLedgerFullyRetiredTraps is Test {
    CollectionLedger ledger;
    address constant REGISTRY = address(uint160(0xBEEF));

    function setUp() public {
        ledger = new CollectionLedger(REGISTRY);
        vm.startPrank(REGISTRY);
    }

    /// @dev Drain a small generation: 3 NFTs, all recycled.
    function _retireEverything(uint256 gen, uint256 supply, uint256 pot)
        internal
        returns (uint256 paidOut)
    {
        ledger.credit(gen, pot);
        for (uint256 i; i < supply; i++) paidOut += ledger.redeem(gen, supply);
    }

    function test_FullyRetiredGenerationTrapsEveryLaterCredit() public {
        uint256 gen = 7;
        uint256 paidOut = _retireEverything(gen, 3, 300e18);

        assertEq(paidOut, 300e18, "the three holders took the whole pot");
        assertEq(ledger.outstanding(gen, 3), 0, "nothing outstanding");
        assertEq(ledger.retired(gen), 3, "all three NFTs sit in the treasury");
        assertEq(ledger.totalEntitled(), 0, "pot emptied");

        // The brew dies with every NFT already recycled: the supply FREEZES at 3
        // against `retired == 3`, so no NFT can ever be outstanding again.
        ledger.crystallize(gen, 3, 0);
        assertTrue(ledger.isDeadEnd(gen), "frozen supply fully retired => dead end");

        // Both exits really are shut, which is what makes a credit here unclaimable.
        vm.expectRevert(CollectionLedger.NothingOutstanding.selector);
        ledger.redeem(gen, 3);
        assertEq(ledger.floorPerNFT(gen, 3), 0, "floor is zero => buyback unsatisfiable");

        // A later royalty / fee buyback lands on this dead collection.
        vm.expectEmit(true, false, false, true, address(ledger));
        emit CollectionLedger.CreditRejected(gen, 500e18);
        ledger.credit(gen, 500e18); // MUST NOT revert: relaunch() calls through here

        assertEq(ledger.totalEntitled(), 0, "FIXED: the shared reserve is not over-claimed");
        assertEq(ledger.entitledTokens(gen), 0, "FIXED: nothing booked to a bucket with no claimant");

        // Same for the final sizing folded in at death (the twin, one call earlier).
        uint256 gen8 = 8;
        ledger.credit(gen8, 90e18);
        ledger.redeem(gen8, 1); // the single NFT recycles
        assertEq(ledger.retired(gen8), 1, "gen 8 fully recycled while alive");
        vm.expectEmit(true, false, false, true, address(ledger));
        emit CollectionLedger.CreditRejected(gen8, 777e18);
        ledger.crystallize(gen8, 1, 777e18);
        assertEq(ledger.entitledTokens(gen8), 0, "FIXED: crystallize drops the trapped extra too");
        assertEq(ledger.totalEntitled(), 0, "FIXED: totalEntitled still covers only live claims");
    }

    /// POSITIVE CONTROL: a LIVE generation at zero outstanding is not a dead end —
    /// the next forged NFT makes the pot claimable again, so the credit must land.
    function test_LiveFullyRecycledGenerationStillAccrues() public {
        uint256 gen = 11;
        _retireEverything(gen, 3, 300e18);
        assertEq(ledger.outstanding(gen, 3), 0, "nothing outstanding right now");
        assertFalse(ledger.isDeadEnd(gen), "still alive: supply is not frozen");

        ledger.credit(gen, 500e18);
        assertEq(ledger.totalEntitled(), 500e18, "live credit still accrues");

        // And it really is claimable: a 4th NFT is forged, so outstanding is 1 again.
        assertEq(ledger.floorPerNFT(gen, 4), 500e18, "the whole pot is claimable by the new NFT");
        assertEq(ledger.redeem(gen, 4), 500e18, "and it pays out");
    }
}
