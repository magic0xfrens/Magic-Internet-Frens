// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

/**
 * K3a — a QUEUED exit whose backing was wiped is written down only LAZILY, inside
 * {PerpVault.claimPendingEth}. Until the claimant calls it, the nominal claim
 * stands at full size. {PerpVault.deposit} has NO solvency gate: it prices the
 * new stake at `assetsEth() = totalEth() - pendingEth`, which SATURATES AT ZERO,
 * so a depositor into a queue-underwater vault mints shares worth nothing and
 * hands 100% of their principal to the stale queue entry.
 */
contract K3a_StaleQueueEatsDeposit is Test {
    MockEngine engine;
    PerpVault vault;
    address alice = address(0xA11CE); // the queued LP
    address bob = address(0xB0B);     // the victim depositor

    function setUp() public {
        engine = new MockEngine();
        vault = new PerpVault(address(engine), address(engine));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // ── POSITIVE CONTROL: a solvent vault pays a queued exit and a fresh
    //    depositor keeps their money. ────────────────────────────────────────
    function _solventRun() internal returns (uint256 bobRedeemable, uint256 aliceGot) {
        vm.prank(alice);
        uint256 sh = vault.depositEth{value: 10 ether}();
        engine.lend(10 ether);                 // 100% utilised → nothing free
        vm.prank(alice);
        vault.withdrawEth(sh);                 // fully queued
        engine.repay(10 ether, 0);             // positions close, capital returns

        uint256 before = alice.balance;
        vm.prank(bob);
        vault.depositEth{value: 10 ether}();
        (bobRedeemable,,) = vault.ethPosition(bob);
        vm.prank(alice);
        vault.claimPendingEth();
        aliceGot = alice.balance - before;
    }

    function test_positive_solventVault_queueAndDepositBothWhole() public {
        (uint256 bobRedeemable, uint256 aliceGot) = _solventRun();
        assertApproxEqAbs(aliceGot, 10 ether, 1e12, "alice's queued exit paid in full");
        assertApproxEqAbs(bobRedeemable, 10 ether, 1e12, "bob keeps his deposit");
    }

    // ── REGRESSION (was the ATTACK): same flow, but the lent capital is lost
    //    before bob deposits. {PerpVault.deposit} now REFUSES while the queue
    //    outruns the backing, and the honest recovery path still works. ────────
    function _insolventRun()
        internal
        returns (bool bobRefused, uint256 aliceGot, uint256 bobRedeemable, uint256 bobPaid)
    {
        vm.prank(alice);
        uint256 sh = vault.depositEth{value: 10 ether}();
        engine.lend(10 ether);
        vm.prank(alice);
        (uint256 paid, uint256 queued) = vault.withdrawEth(sh);
        assertEq(paid, 0, "nothing free");
        assertApproxEqAbs(queued, 10 ether, 1e12, "10 ETH queued");

        engine.wipe(10 ether); // total bad debt: totalEth() == 0, pendingEth == 10e18
        assertEq(engine.totalEth(), 0, "backing wiped");
        assertApproxEqAbs(vault.pendingEth(), 10 ether, 1e12, "stale claim stands at full size");

        uint256 aliceBefore = alice.balance;

        //  ── INVERTED BY 6634f2a ────────────────────────────────────────────
        //  The ORIGINAL block, verbatim:
        //
        //      // THE FIX: no new money into an insolvent queue.
        //      vm.prank(bob);
        //      try vault.depositEth{value: 10 ether}() { bobRefused = false; }
        //      catch (bytes memory err) {
        //          bobRefused = bytes4(err) == PerpVault.QueueInsolvent.selector;
        //      }
        //
        //  {deposit} now calls {_syncEthQueue} BEFORE its `QueueInsolvent` check
        //  (PerpVault.sol:298). The sync writes the dead queue down to the zero
        //  backing and retires it, so `pendingEth() > engine.totalEth()` is false
        //  by the time the gate is read and bob is admitted on the first try.
        //  The gate is untouched and still in place; it is simply pre-empted.
        //  The PROPERTY K3a exists to protect is unchanged and asserted below:
        //  the stale queue takes nothing of bob's money and his stake is worth
        //  what he paid. Recognising the loss beats latching the door.
        (bobRefused, bobPaid, bobRedeemable) = _bobDeposits();

        //  Alice's claim is worth zero and is now already banked, so the claim
        //  reverts `ZeroAmount` exactly as it does for anyone with no pending
        //  balance. Either way she takes nothing of bob's deposit.
        vm.prank(alice);
        try vault.claimPendingEth() {} catch {}
        aliceGot = alice.balance - aliceBefore;
    }

    /// @dev Split out to keep {_insolventRun} under the viaIR stack limit.
    function _bobDeposits() internal returns (bool refused, uint256 paid, uint256 redeemable) {
        uint256 before = bob.balance;
        vm.prank(bob);
        try vault.depositEth{value: 10 ether}() { refused = false; }
        catch (bytes memory err) {
            refused = bytes4(err) == PerpVault.QueueInsolvent.selector;
        }
        paid = before - bob.balance;
        (redeemable,,) = vault.ethPosition(bob);
    }

    function test_attack_staleQueueTakes100PctOfAFreshDeposit() public {
        (bool bobRefused, uint256 aliceGot, uint256 bobRedeemable, uint256 bobPaid) = _insolventRun();
        //  ORIGINAL, verbatim:
        //      assertTrue(bobRefused, "the deposit into an insolvent queue is REFUSED (QueueInsolvent)");
        assertFalse(bobRefused, "the gate is PRE-EMPTED: the dead queue is recognised, not latched against");
        assertEq(aliceGot, 0, "alice's worthless claim is recognised as worthless, not paid from bob");
        assertEq(vault.pendingEth(), 0, "the stale queue is drained by its own haircut");
        assertEq(bobPaid, 10 ether, "bob's later, honest deposit still goes in");
        assertApproxEqAbs(bobRedeemable, 10 ether, 1e12, "and it is worth what he paid - nobody eats it");
    }
}

contract MockEngine {
    address public vault;
    uint256 public plv;
    uint256 public lentEth;

    function quote() external pure returns (address) { return address(0); }
    function currentToken() external pure returns (address) { return address(0); }
    function fundFromVault(uint256 amount) external payable { plv += amount; }
    function withdrawPlvTo(uint256 amount, address to) external {
        require(amount <= plv, "free");
        plv -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "send");
    }
    function fundTokenFromVault(uint256) external pure { revert("n/a"); }
    function withdrawPlvTokenTo(uint256, address) external pure { revert("n/a"); }
    function totalEth() external view returns (uint256) { return plv + lentEth; }
    function freeEth() external view returns (uint256) { return plv; }
    function totalTokenAssets() external pure returns (uint256) { return 0; }
    function freeToken() external pure returns (uint256) { return 0; }
    function tokYieldCumulative() external pure returns (uint256) { return 0; }
    function withdrawTokYieldTo(uint256, address) external pure { revert("n/a"); }

    function lend(uint256 a) external { plv -= a; lentEth += a; }
    function repay(uint256 a, uint256 profit) external { lentEth -= a; plv += a + profit; }
    /// @dev Bad debt: the lent capital never comes back (mirrors _absorbPlvLoss
    ///      driving plv to 0 with longOiEth already retired in _settle).
    function wipe(uint256 a) external {
        lentEth -= a;
        payable(address(0xdead)).transfer(a);
    }
    receive() external payable {}
}
