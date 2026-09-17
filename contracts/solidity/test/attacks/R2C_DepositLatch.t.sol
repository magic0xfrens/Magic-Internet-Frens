// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockEngine, MockRegistry} from "./R2Mock.sol";

/**
 * R2C — the ETH side's `QueueInsolvent` guard is a latch whose ONLY key is held
 * by the queued claimant himself.
 *
 *   PerpVault.sol:274  if (pendingEth > engine.totalEth()) revert QueueInsolvent();
 *   PerpVault.sol:376  function claimPendingEth() ... reads pendingEthOf[msg.sender]
 *
 * `pendingEth` is decremented ONLY inside `claimPendingEth`, and only for
 * `msg.sender`'s own claim. There is no owner path, no permissionless
 * `claimFor`, no expiry. A claimant whose claim has already been written down to
 * ~nothing therefore forfeits ~nothing by never calling it — and the ETH side of
 * the vault can never take another deposit for the life of the engine.
 */
contract R2C_DepositLatch is Test {
    MockEngine eng;
    MockRegistry reg;
    PerpVault vault;

    address holdout = address(0xDEAD01);
    address newLp   = address(0xF00D01);

    function setUp() public {
        eng = new MockEngine();
        reg = new MockRegistry();
        vault = new PerpVault(address(eng), address(reg));
        eng.setVault(address(vault));
        vm.deal(holdout, 100 ether);
        vm.deal(newLp, 100 ether);
    }

    struct R {
        uint256 holdoutWouldHaveGot;   // what refusing actually costs him
        bool depositRevertedWhileHeld;
        bool depositWorksAfterHeClaims;
        uint256 pendingWhileHeld;
        uint256 totalEthWhileHeld;
        bool settleGaveCallerNothing;
        uint256 holdoutEntitlementAfterSettle;
        uint256 holdoutStillPaid;
    }

    function _run() internal returns (R memory r) {
        // 1. Sole LP stakes 10 ETH; the book borrows all of it.
        vm.prank(holdout); vault.depositEth{value: 10 ether}();
        eng.lend(10 ether);

        // 2. He queues out (nothing free, so it all queues at the pre-loss price).
        uint256 s = vault.ethShareOf(holdout);
        vm.prank(holdout); vault.withdrawEth(s);
        assertEq(vault.pendingEth(), 10 ether - 0, "queued nominal");
        assertEq(vault.ethShares(), 0, "no live shares left");

        // 3. Near-total bad debt: `_absorbPlvLoss` (PerpEngine.sol:2243) saturates
        //    `plv` at 0 and the lent principal never comes back.
        eng.absorbLentLoss(10 ether - 0.001 ether);
        eng.repay(eng.lentEth());
        vm.deal(address(eng), 0.001 ether);
        r.totalEthWhileHeld = eng.totalEth();
        r.pendingWhileHeld  = vault.pendingEth();

        // 4. What refusing costs him: simulate the claim and roll it back.
        uint256 snap = vm.snapshotState();
        uint256 b0 = holdout.balance;
        vm.prank(holdout); vault.claimPendingEth();
        r.holdoutWouldHaveGot = holdout.balance - b0;
        vm.revertToState(snap);

        // 5. He simply never calls it. Deposits are still refused RIGHT NOW —
        //    that guard is correct and must survive the fix (R2B(ii) is the bug
        //    you get without it).
        vm.prank(newLp);
        try vault.depositEth{value: 5 ether}() { r.depositRevertedWhileHeld = false; }
        catch { r.depositRevertedWhileHeld = true; }

        // 6. REGRESSION: the holdout is no longer the only key. ANY address may
        //    bank his write-down, and it moves no value to the caller.
        uint256 callerBefore = newLp.balance;
        vm.prank(newLp); vault.settlePendingEth(holdout);
        r.settleGaveCallerNothing = (newLp.balance == callerBefore);
        r.holdoutEntitlementAfterSettle = vault.pendingEthOf(holdout);

        vm.prank(newLp);
        try vault.depositEth{value: 5 ether}() { r.depositWorksAfterHeClaims = true; }
        catch { r.depositWorksAfterHeClaims = false; }

        // 7. ...and the holdout keeps every wei the backing can actually cover.
        uint256 hb = holdout.balance;
        vm.prank(holdout); vault.claimPendingEth();
        r.holdoutStillPaid = holdout.balance - hb;
    }

    function test_R2C_one_holdout_shuts_the_eth_side_for_free() public {
        R memory r = _run();
        console2.log("pendingEth while held :", r.pendingWhileHeld);
        console2.log("engine.totalEth()     :", r.totalEthWhileHeld);
        console2.log("holdout entitlement after a third party settles:", r.holdoutEntitlementAfterSettle);
        console2.log("holdout still paid on his own claim:", r.holdoutStillPaid);

        assertGt(r.pendingWhileHeld, r.totalEthWhileHeld, "queue outruns backing");
        // The gate itself is UNCHANGED: while the queue is unbacked, no new money.
        assertTrue(r.depositRevertedWhileHeld, "insolvent-queue gate still refuses deposits");
        // INVERTED (was: only the holdout's own claim reopens the side).
        assertTrue(r.depositWorksAfterHeClaims, "any third party can now reopen the ETH side");
        assertTrue(r.settleGaveCallerNothing, "settlePendingEth pays the caller nothing");
        // The write-down is pro-rata, not confiscation: he keeps the whole backing.
        assertEq(r.holdoutEntitlementAfterSettle, r.totalEthWhileHeld, "holdout keeps his pro-rata share");
        assertEq(r.holdoutStillPaid, r.totalEthWhileHeld, "and can still claim it himself");
    }
}
