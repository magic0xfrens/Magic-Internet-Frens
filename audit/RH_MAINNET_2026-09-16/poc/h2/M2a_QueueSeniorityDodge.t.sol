// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

/// Controllable engine: models the PLV's ETH side. `injectLoss` socialises a
/// bad-debt loss exactly the way `_absorbPlvLoss` does — it shrinks the ETH the
/// engine holds (here on the lent leg, so `freeEth` is untouched and the queue's
/// seniority is what decides who eats it).
contract LossEngine {
    address public vault;
    uint256 public plv;      // free ETH (freeEth)
    uint256 public lentEth;  // ETH lent to longs (part of totalEth, not free)

    function setVault(address v) external { vault = v; }
    function quote() external pure returns (address) { return address(0); }
    function currentToken() external view returns (address) { return address(this); }

    function fundFromVault(uint256 amount) external payable { plv += amount; }
    function withdrawPlvTo(uint256 amount, address to) external {
        require(amount <= plv, "free");
        plv -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "send");
    }
    function totalEth() external view returns (uint256) { return plv + lentEth; }
    function freeEth() external view returns (uint256) { return plv; }

    // token side unused here
    function fundTokenFromVault(uint256) external {}
    function withdrawPlvTokenTo(uint256, address) external {}
    function totalTokenAssets() external pure returns (uint256) { return 0; }
    function freeToken() external pure returns (uint256) { return 0; }
    function tokYieldCumulative() external pure returns (uint256) { return 0; }
    function tokYieldEth() external pure returns (uint256) { return 0; }
    function withdrawTokYieldTo(uint256, address) external {}

    // simulation levers
    function lend(uint256 a) external { plv -= a; lentEth += a; }
    function repay(uint256 a) external { lentEth -= a; plv += a; }   // no profit, no loss
    function injectLoss(uint256 a) external { lentEth -= a; }        // bad debt: value gone
    receive() external payable {}
}

contract M2a_QueueSeniorityDodge is Test {
    LossEngine engine;
    PerpVault vault;

    address lpA = address(0xA11CE);
    address lpB = address(0xB0B);

    function setUp() public {
        engine = new LossEngine();
        vault = new PerpVault(address(engine), address(engine));
        engine.setVault(address(vault));
        vm.deal(lpA, 100 ether);
        vm.deal(lpB, 100 ether);
    }

    // ── POSITIVE CONTROL ──────────────────────────────────────────────────
    // Two LPs both stay staked through a loss. Pro-rata: each eats HALF.
    function test_control_bothStay_shareLossEqually() public {
        _seed(); // both deposit 5, then 8 ETH lent out
        // Loss of 3 ETH while both are still live stakers.
        engine.injectLoss(3 ether);

        // Bring lent ETH back so both can redeem freely.
        engine.repay(engine.lentEth());

        uint256 aOut = _redeemAll(lpA);
        uint256 bOut = _redeemAll(lpB);

        // Each staked 5, total held after loss = 7, split pro-rata ~3.5 each.
        assertApproxEqAbs(aOut, 3.5 ether, 1e12, "A ~3.5");
        assertApproxEqAbs(bOut, 3.5 ether, 1e12, "B ~3.5");
        // Losses roughly equal — the honest, pro-rata outcome.
        assertApproxEqAbs(5 ether - aOut, 5 ether - bOut, 1e12, "equal loss");
    }

    // ── ATTACK ────────────────────────────────────────────────────────────
    // LP-A withdraws-to-QUEUE just before the loss. The queue is senior, so A
    // eats ~0 and the staying LP-B eats the ENTIRE loss.
    function test_attack_queueBeforeLoss_dodgesEntireLoss() public {
        _seed(); // both deposit 5, 8 ETH lent (free=2)

        // A exits: 2 paid instantly, 3 QUEUED (free < owed because 8 is lent).
        uint256 shA = vault.ethShareOf(lpA);
        vm.prank(lpA);
        (uint256 paidA, uint256 queuedA) = vault.withdrawEth(shA);
        assertEq(queuedA, 3 ether, "A queued 3");

        // The SAME 3 ETH loss now lands. Queue nominal (3) <= backing (5) -> the
        // haircut never triggers: A's senior claim is fully covered.
        engine.injectLoss(3 ether);

        // Liquidity returns; A claims the full queued 3.
        engine.repay(engine.lentEth());
        vm.prank(lpA);
        uint256 claimedA = vault.claimPendingEth();

        uint256 aTotal = paidA + claimedA; // total A pulled out
        uint256 bOut = _redeemAll(lpB);

        // A recovers its full 5 ETH principal — ZERO loss.
        assertApproxEqAbs(aTotal, 5 ether, 1e12, "A escapes whole loss");
        // B, who did nothing, eats the ENTIRE 3 ETH loss (5 -> 2).
        assertApproxEqAbs(bOut, 2 ether, 1e12, "B eats 100% of loss");
        // The dodge: A's loss is ~0 while a pro-rata split would have cost A 1.5.
        assertLt(5 ether - aTotal, 1e12, "A loss ~0");
        assertGt(5 ether - bOut, 2.9 ether, "B loss ~3");
    }

    // ── helpers ───────────────────────────────────────────────────────────
    function _seed() internal {
        vm.prank(lpA);
        vault.deposit{value: 5 ether}(5 ether);
        vm.prank(lpB);
        vault.deposit{value: 5 ether}(5 ether);
        // Lend 8 of the 10 out so any large withdrawal must queue.
        engine.lend(8 ether);
    }

    function _redeemAll(address who) internal returns (uint256 got) {
        uint256 before = who.balance;
        uint256 sh = vault.ethShareOf(who);
        if (sh == 0) return 0;
        vm.prank(who);
        (uint256 paid, uint256 queued) = vault.withdrawEth(sh);
        if (queued > 0) {
            vm.prank(who);
            vault.claimPendingEth();
        }
        got = who.balance - before;
        paid; // silence
    }
}
