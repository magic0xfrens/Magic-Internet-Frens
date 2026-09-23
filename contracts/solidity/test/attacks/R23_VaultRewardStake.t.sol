// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {K3b_TokYieldLockout, MockEngine, MockToken} from "./K3b_TokYieldLockout.t.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

contract R23VaultRewardStake is K3b_TokYieldLockout {
    function test_earnedYieldMustKeepReplacementGuardActive() public {
        (MockEngine e, PerpVault v, MockToken t) = _fresh();
        vm.startPrank(alice);
        t.approve(address(v), type(uint256).max);
        uint256 shares = v.depositToken(1000 ether);
        vm.stopPrank();
        e.accrueTokYield(5 ether);
        vm.prank(alice);
        v.withdrawToken(shares);
        assertEq(v.tokShares(), 0);
        assertEq(v.tokQueueUnits(), 0);
        assertGt(v.tokRewardOwed(alice), 0, "earned reward survives principal exit");
        assertTrue(v.hasStakers(), "earned claims must prevent replacing their payment authority");
    }
}
