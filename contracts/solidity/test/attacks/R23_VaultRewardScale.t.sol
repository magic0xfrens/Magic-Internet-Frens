// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockEngine, MockToken} from "./K3b_TokYieldLockout.t.sol";

// Mechanism fixture: mirrors engine callback ordering and changes denomination
// counters, without simulating a market conversion or asserting reachable rates.
contract R23ScaleEngine is MockEngine {
    constructor(MockToken token_) MockEngine(token_) {}
    function requote(PerpVault vault, uint256 numerator, uint256 denominator) external {
        vault.beforeBookRequote();
        tokYieldEth = tokYieldEth * numerator / denominator;
        tokYieldCumulative = tokYieldCumulative * numerator / denominator;
        vault.afterBookRequote(0, 0, numerator, denominator);
    }
}

contract R23VaultRewardScale is Test {
    function test_scaledClaimPreservesReplacementGuardUntilPayment() public {
        _scaledClaim(2, 1, false);
    }

    function test_zeroRoundedOwnedClaimCanBeClearedWithoutEnginePayment() public {
        _scaledClaim(1, 1e12, true);
    }

    function _scaledClaim(uint256 numerator, uint256 denominator, bool roundsToZero) private {
        MockToken token = new MockToken();
        R23ScaleEngine engine = new R23ScaleEngine(token);
        PerpVault vault = new PerpVault(address(engine), address(engine));
        address user = address(0xA11CE);
        token.mint(user, 1);
        vm.deal(address(engine), 1 ether);
        vm.startPrank(user);
        token.approve(address(vault), 1);
        uint256 shares = vault.depositToken(1);
        vm.stopPrank();
        engine.accrueTokYield(1);
        vm.prank(user); vault.withdrawToken(shares);
        assertEq(vault.tokRewardOwed(user), 1);
        engine.requote(vault, numerator, denominator);
        assertTrue(vault.hasStakers());
        uint256 due = vault.pendingTokYield(user);
        assertEq(due, roundsToZero ? 0 : 2);
        uint256 beforeBalance = user.balance;
        vm.prank(user); assertEq(vault.claimTokYield(), due);
        assertEq(user.balance - beforeBalance, due);
        assertEq(vault.tokRewardOwed(user), 0);
        assertFalse(vault.hasStakers());
        vm.expectRevert(PerpVault.ZeroAmount.selector);
        vm.prank(user); vault.claimTokYield();
    }
}
