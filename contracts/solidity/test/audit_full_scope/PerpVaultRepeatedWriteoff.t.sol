// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockEngine, MockToken} from "../attacks/K3b_TokYieldLockout.t.sol";

/// Production vault; engine fixture models its cumulative/pot/write-off API.
/// Tests do not write vault storage or impersonate a privileged vault caller.
contract PerpVaultRepeatedWriteoffTest is Test {
    MockEngine internal engine;
    MockToken internal token;
    PerpVault internal vault;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        token = new MockToken();
        engine = new MockEngine(token);
        vault = new PerpVault(address(engine), address(engine));
        vm.deal(address(engine), 100 ether);
        token.mint(alice, 10000 ether);
        token.mint(bob, 10000 ether);
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    function _firstWriteoffAndLateSync() internal {
        vm.prank(alice);
        vault.depositToken(1000 ether);
        engine.accrueTokYield(5 ether);
        engine.rotationWriteOff();
        engine.accrueTokYield(1 ether);
        // Normal new-staker interaction detects the previous rotation while
        // preserving Alice's backed, post-rotation one-ether accrual.
        vm.prank(bob);
        vault.depositToken(9000 ether);
        assertEq(vault.yieldEpoch(), 1);
        assertApproxEqAbs(vault.pendingTokYield(alice), 1 ether, 1e9);
    }

    function test_writeoffWatermarkExcludesTheStillBackedPot() public {
        _firstWriteoffAndLateSync();
        assertEq(
            vault.totalTokYieldPulled() + engine.tokYieldEth(),
            engine.tokYieldCumulative(),
            "pulled plus written off plus current pot equals cumulative"
        );
    }

    function test_secondWriteoffCannotConsumeAnotherStakersNewYield() public {
        _firstWriteoffAndLateSync();
        engine.rotationWriteOff();
        engine.accrueTokYield(10 ether);
        // Both old pots are gone. Only the new ten ether is distributable,
        // shared 10% / 90%, with no resurrection of Alice's former one ether.
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        uint256 alicePaid = vault.claimTokYield();
        assertEq(alice.balance - aliceBefore, alicePaid);
        assertApproxEqAbs(alicePaid, 1 ether, 1e9, "no claim on written-off yield");
        vm.prank(bob);
        uint256 bobPaid = vault.claimTokYield();
        assertApproxEqAbs(bobPaid, 9 ether, 1e9, "new yield is not diverted");
        assertEq(vault.yieldEpoch(), 2);
        assertLe(alicePaid + bobPaid, 10 ether);
    }

    function test_noWriteoffControlPaysBothStakers() public {
        vm.prank(alice);
        vault.depositToken(1000 ether);
        vm.prank(bob);
        vault.depositToken(9000 ether);
        engine.accrueTokYield(10 ether);
        vm.prank(alice);
        assertApproxEqAbs(vault.claimTokYield(), 1 ether, 1e9);
        vm.prank(bob);
        assertApproxEqAbs(vault.claimTokYield(), 9 ether, 1e9);
        assertEq(vault.yieldEpoch(), 0);
    }

    function testFuzz_repeatedWriteoffsPreserveOnlyBackedClaims(uint96 rawYield, uint8 rawCycles) public {
        uint256 reward = bound(uint256(rawYield), 1e10, 1 ether);
        uint256 cycles = bound(uint256(rawCycles), 2, 8);
        vm.prank(alice);
        vault.depositToken(1000 ether);
        vm.prank(bob);
        vault.depositToken(9000 ether);
        engine.accrueTokYield(reward);
        for (uint256 i; i < cycles; ++i) {
            engine.rotationWriteOff();
            engine.accrueTokYield(reward);
            // An ordinary deposit syncs after new fees have already arrived.
            vm.prank(alice);
            vault.depositToken(1 ether);
            assertEq(vault.yieldEpoch(), i + 1);
            assertEq(vault.totalTokYieldPulled() + engine.tokYieldEth(), engine.tokYieldCumulative());
            uint256 aliceDue = vault.pendingTokYield(alice);
            uint256 bobDue = vault.pendingTokYield(bob);
            assertLe(aliceDue + bobDue, reward, "claims cannot resurrect a retired pot");
            // ACC is 1e18 while virtual shares scale deposits by 1e6.
            // Flooring reward*ACC/shares loses < shares/ACC wei; each
            // user's accumulator/debt subtraction adds at most two wei.
            uint256 roundingBound = vault.tokShares() / 1e18 + 4;
            assertApproxEqAbs(aliceDue + bobDue, reward, roundingBound, "backed yield minus bounded rounding");
        }
        uint256 bobExpected = vault.pendingTokYield(bob);
        uint256 aliceExpected = vault.pendingTokYield(alice);
        // Reverse the deterministic test's claim order.
        _assertClaim(bob, bobExpected);
        assertEq(vault.totalTokYieldPulled() + engine.tokYieldEth(), engine.tokYieldCumulative());
        _assertClaim(alice, aliceExpected);
        assertEq(vault.totalTokYieldPulled() + engine.tokYieldEth(), engine.tokYieldCumulative());
    }

    function _assertClaim(address user, uint256 expected) internal {
        uint256 potBefore = engine.tokYieldEth();
        uint256 balanceBefore = user.balance;
        vm.prank(user);
        if (expected == 0) {
            vm.expectRevert(PerpVault.ZeroAmount.selector);
            vault.claimTokYield();
            assertEq(engine.tokYieldEth(), potBefore);
            assertEq(user.balance, balanceBefore);
        } else {
            assertEq(vault.claimTokYield(), expected);
            assertEq(user.balance - balanceBefore, expected);
            assertEq(potBefore - engine.tokYieldEth(), expected);
        }
    }
}
