// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockEngine, MockToken} from "./K3b_TokYieldLockout.t.sol";

contract R23VaultRewardSequence is Test {
    function testFuzz_rewardDebtConservedAcrossUserSequences(uint256 seed) public {
        MockToken token = new MockToken();
        MockEngine engine = new MockEngine(token);
        PerpVault vault = new PerpVault(address(engine), address(engine));
        vm.deal(address(engine), 1000 ether);
        address[4] memory users;
        for (uint256 i; i < 4; ++i) {
            users[i] = address(uint160(0xA000 + i));
            token.mint(users[i], 100 ether);
            vm.prank(users[i]); token.approve(address(vault), type(uint256).max);
        }
        uint256 credited;
        uint256 paid;
        uint256 forfeited;
        for (uint256 step; step < 64; ++step) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, step)));
            address user = users[(entropy >> 8) % 4];
            uint256 action = entropy % 5;
            if (action == 0) {
                uint256 amount = 1 + (entropy >> 32) % 1 ether;
                engine.accrueTokYield(amount);
                credited += amount;
            } else if (action == 1) {
                vm.prank(user); vault.depositToken(1 ether);
            } else if (action == 2) {
                uint256 shares = vault.tokShareOf(user);
                if (shares != 0) {
                    vm.prank(user); vault.withdrawToken(shares);
                }
            } else if (action == 3) {
                uint256 due = vault.pendingTokYield(user);
                if (due != 0) {
                    uint256 beforeBalance = user.balance;
                    vm.prank(user); uint256 actual = vault.claimTokYield();
                    assertEq(actual, due);
                    assertEq(user.balance - beforeBalance, due);
                    paid += actual;
                }
            } else {
                forfeited += engine.tokYieldEth();
                engine.rotationWriteOff();
            }
            assertEq(credited, paid + forfeited + engine.tokYieldEth());
            uint256 settled;
            uint256 claimable;
            for (uint256 i; i < 4; ++i) {
                if (vault.stakerEpoch(users[i]) == vault.yieldEpoch()) {
                    settled += vault.tokRewardOwed(users[i]);
                }
                claimable += vault.pendingTokYield(users[i]);
            }
            // Slot 24 independently pinned by PERPVAULT_SURFACE_CHECK.json;
            // read only, never force state to manufacture a reachable sequence.
            assertEq(uint256(vm.load(address(vault), bytes32(uint256(24)))), settled);
            assertLe(claimable, engine.tokYieldEth());
            if (claimable != 0) assertTrue(vault.hasStakers());
        }
    }
}
