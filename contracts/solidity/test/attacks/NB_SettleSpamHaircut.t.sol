// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockEngine, MockRegistry} from "./R2Mock.sol";

/**
 *  NB — settlePendingEth IS NOT IDEMPOTENT, AND ANYONE MAY CALL IT ON ANYONE.
 *
 *  PerpVault.sol:415-418
 *      function settlePendingEth(address user) external nonReentrant returns (uint256 stillOwed) {
 *          if (pendingEthOf[user] == 0) revert ZeroAmount();
 *          return _bankEthWriteDown(user);
 *      }
 *  PerpVault.sol:383-394
 *      function _bankEthWriteDown(address user) private returns (uint256 owed) {
 *          owed = pendingEthOf[user];
 *          ...
 *          uint256 capped = _haircut(owed, engine.totalEth(), pendingEth);
 *          if (capped < owed) { ... pendingEth -= (owed - capped); pendingEthOf[user] = capped; owed = capped; }
 *      }
 *  PerpVault.sol:371-377
 *      function _haircut(uint256 owed, uint256 backing, uint256 claims) ... {
 *          if (claims == 0 || backing >= claims) return owed;
 *          return FullMath.mulDiv(owed, backing, claims);
 *      }
 *
 *  Each application shrinks BOTH the victim's nominal and the queue total
 *  `pendingEth`. Re-applying it to the SAME user re-divides his already-reduced
 *  claim by an already-reduced denominator that still carries everyone else's
 *  FULL nominal. Repeating drives one queued address toward zero while every
 *  other queued address keeps its nominal and then claims the whole backing.
 *
 *  Invariant under test (I-NB): a write-down is pro-rata. Two identically-sized
 *  queued claims standing against the same backing must be paid the same.
 */
contract NB_SettleSpamHaircut is Test {
    MockEngine eng;
    MockRegistry reg;
    PerpVault vault;

    address attacker = address(0xA77ACC);
    address victim   = address(0xBEEF01);

    struct R {
        uint256 pendingVictimAfterSpam;
        uint256 pendingAttackerAfterSpam;
        uint256 victimPaid;
        uint256 attackerPaid;
        uint256 backing;
    }

    function setUp() public {
        eng = new MockEngine();
        reg = new MockRegistry();
        vault = new PerpVault(address(eng), address(reg));
        eng.setVault(address(vault));
        vm.deal(attacker, 100 ether);
        vm.deal(victim, 100 ether);
    }

    /// @dev Two equal LPs, both queued, backing halved by bad debt.
    function _queueBoth() internal {
        vm.prank(attacker); vault.depositEth{value: 10 ether}();
        vm.prank(victim);   vault.depositEth{value: 10 ether}();
        eng.lend(20 ether);                       // nothing free -> exits queue
        uint256 sa = vault.ethShareOf(attacker);
        uint256 sv = vault.ethShareOf(victim);
        vm.prank(attacker); vault.withdrawEth(sa);
        vm.prank(victim);   vault.withdrawEth(sv);
        eng.absorbLentLoss(10 ether);             // half the book is bad debt
        eng.repay(eng.lentEth());                 // the rest comes back free
    }

    /// CONTROL: one settle each, then both claim -> equal pay, pro-rata.
    function _fair() internal returns (R memory r) {
        _queueBoth();
        r.backing = eng.totalEth();
        vm.prank(attacker); vault.settlePendingEth(victim);
        vm.prank(attacker); vault.settlePendingEth(attacker);
        r.pendingVictimAfterSpam   = vault.pendingEthOf(victim);
        r.pendingAttackerAfterSpam = vault.pendingEthOf(attacker);
        uint256 vb = victim.balance;
        vm.prank(victim);   vault.claimPendingEth();
        r.victimPaid = victim.balance - vb;
        uint256 ab = attacker.balance;
        vm.prank(attacker); vault.claimPendingEth();
        r.attackerPaid = attacker.balance - ab;
    }

    /// ATTACK: the attacker settles the VICTIM 80 times, himself never.
    function _spam() internal returns (R memory r) {
        _queueBoth();
        r.backing = eng.totalEth();
        for (uint256 i = 0; i < 80; i++) {
            vm.prank(attacker);
            vault.settlePendingEth(victim);
        }
        r.pendingVictimAfterSpam   = vault.pendingEthOf(victim);
        r.pendingAttackerAfterSpam = vault.pendingEthOf(attacker);
        uint256 ab = attacker.balance;
        vm.prank(attacker); vault.claimPendingEth();
        r.attackerPaid = attacker.balance - ab;
        uint256 vb = victim.balance;
        vm.prank(victim);   vault.claimPendingEth();
        r.victimPaid = victim.balance - vb;
    }

    function test_NB_positive_single_settle_is_pro_rata() public {
        R memory r = _fair();
        console2.log("backing", r.backing);
        console2.log("victim paid  ", r.victimPaid);
        console2.log("attacker paid", r.attackerPaid);
        assertGt(r.backing, 0, "backing exists");
        assertApproxEqAbs(r.victimPaid, r.attackerPaid, 1e15, "one settle each is pro-rata");
    }

    function test_NB_repeated_settle_confiscates_the_victims_claim() public {
        R memory r = _spam();
        console2.log("backing", r.backing);
        console2.log("victim pending after 80 settles  ", r.pendingVictimAfterSpam);
        console2.log("attacker pending after 80 settles", r.pendingAttackerAfterSpam);
        console2.log("victim paid  ", r.victimPaid);
        console2.log("attacker paid", r.attackerPaid);
        assertGt(r.backing, 0, "backing exists");
        assertApproxEqAbs(
            r.victimPaid, r.attackerPaid, 1e17,
            "I-NB BROKEN: repeated settlePendingEth moved the victim's pro-rata share to the attacker"
        );
    }

    // ── REGRESSION (fixed): the write-down is now GLOBAL, not per-user ───────
    //  I-NB as implemented: after ANY sequence of settle/claim calls, in ANY
    //  order, with ANY number of repetitions, every queued claimant holds
    //  `units * ethQueueIndex` — their unchanging queued nominal scaled by the
    //  one index the shortfall moved. Equal claims are therefore paid equally.

    /// ORDER-INDEPENDENCE: settle(A) then settle(B) == settle(B) then settle(A).
    function test_NB_settle_order_does_not_change_entitlements() public {
        uint256 snap = vm.snapshotState();
        _queueBoth();
        vm.prank(attacker); vault.settlePendingEth(victim);
        vm.prank(attacker); vault.settlePendingEth(attacker);
        uint256 vAB = vault.pendingEthOf(victim);
        uint256 aAB = vault.pendingEthOf(attacker);
        vm.revertToState(snap);

        _queueBoth();
        vm.prank(victim); vault.settlePendingEth(attacker);
        vm.prank(victim); vault.settlePendingEth(victim);
        uint256 vBA = vault.pendingEthOf(victim);
        uint256 aBA = vault.pendingEthOf(attacker);

        console2.log("A-then-B: victim", vAB, "attacker", aAB);
        console2.log("B-then-A: victim", vBA, "attacker", aBA);
        assertGt(vAB, 0, "non-trivial entitlement");
        assertEq(vAB, vBA, "victim entitlement is order-independent");
        assertEq(aAB, aBA, "attacker entitlement is order-independent");
        assertEq(vAB, aAB, "equal claims, equal entitlement");
    }

    /// IDEMPOTENCE: 50 settles leave byte-identical state to 1 settle.
    function test_NB_repetition_is_idempotent() public {
        uint256 snap = vm.snapshotState();
        _queueBoth();
        vm.prank(attacker); vault.settlePendingEth(victim);
        uint256 idx1 = vault.ethQueueIndex();
        uint256 units1 = vault.ethQueueUnits();
        uint256 v1 = vault.pendingEthOf(victim);
        uint256 a1 = vault.pendingEthOf(attacker);
        vm.revertToState(snap);

        _queueBoth();
        for (uint256 i = 0; i < 50; i++) { vm.prank(attacker); vault.settlePendingEth(victim); }
        console2.log("1 settle : index", idx1, "victim", v1);
        console2.log("50 settles: index", vault.ethQueueIndex(), "victim", vault.pendingEthOf(victim));
        assertGt(v1, 0, "non-trivial entitlement");
        assertEq(vault.ethQueueIndex(), idx1, "index unchanged by repetition");
        assertEq(vault.ethQueueUnits(), units1, "units unchanged by repetition");
        assertEq(vault.pendingEthOf(victim), v1, "victim entitlement unchanged by repetition");
        assertEq(vault.pendingEthOf(attacker), a1, "attacker entitlement unchanged by repetition");
    }
}
