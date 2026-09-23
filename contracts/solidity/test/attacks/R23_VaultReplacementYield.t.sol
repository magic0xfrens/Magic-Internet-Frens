// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PerpVaultEngineWriteoffTest} from "../audit_full_scope/PerpVaultEngineWriteoff.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

/// Production engine/vault; fee attribution uses the authorized hook role.
/// Pool and registry are stubs. No target storage writes or simulated engine fees.
contract R23VaultReplacementYield is PerpVaultEngineWriteoffTest {
    function test_replacementBlockedUntilEarnedClaimPaid() public {
        vm.prank(ALICE);
        uint256 shares = vault.depositToken(1000 ether);
        _accrue(5 ether);
        vm.prank(ALICE);
        (uint256 principal, uint256 queued) = vault.withdrawToken(shares);
        assertGt(principal, 0);
        assertEq(queued, 0);
        uint256 due = vault.pendingTokYield(ALICE);
        assertGt(due, 0);
        assertTrue(vault.hasStakers(), "earned claim must retain payment authority");
        uint256 pot = engine.tokYieldEth();
        uint256 balance = ALICE.balance;
        PerpVault replacement = new PerpVault(address(engine), address(registry));
        vm.expectRevert(PerpEngine.BadParam.selector);
        engine.setVault(address(replacement));
        assertEq(ALICE.balance, balance);
        assertEq(engine.tokYieldEth(), pot);
        assertEq(vault.pendingTokYield(ALICE), due);
        vm.prank(ALICE);
        assertEq(vault.claimTokYield(), due);
        assertEq(ALICE.balance - balance, due);
        assertEq(engine.tokYieldEth(), pot - due);
        assertFalse(vault.hasStakers());
        engine.setVault(address(replacement));
        assertEq(engine.vault(), address(replacement));
    }

    function test_orphanYieldAndRoundingResidueDoNotBlockReplacement() public {
        _accrue(1 ether);
        vm.prank(ALICE);
        uint256 shares = vault.depositToken(1000 ether);
        assertEq(vault.pendingTokYield(ALICE), 0);
        _accrue(1 ether + 1);
        vm.prank(ALICE);
        vault.withdrawToken(shares);
        vm.prank(ALICE);
        vault.claimTokYield();
        assertGt(engine.tokYieldEth(), 0);
        assertFalse(vault.hasStakers());
        engine.setVault(address(0));
    }

    function test_allDepartedUsersMustClaimBeforeReplacement() public {
        vm.prank(ALICE);
        uint256 a = vault.depositToken(1000 ether);
        vm.prank(BOB);
        uint256 b = vault.depositToken(9000 ether);
        _accrue(5 ether);
        vm.prank(ALICE); vault.withdrawToken(a);
        vm.prank(BOB); vault.withdrawToken(b);
        assertTrue(vault.hasStakers());
        vm.prank(BOB); vault.claimTokYield();
        assertTrue(vault.hasStakers());
        vm.expectRevert(PerpEngine.BadParam.selector);
        engine.setVault(address(0));
        vm.prank(ALICE); vault.claimTokYield();
        assertFalse(vault.hasStakers());
        engine.setVault(address(0));
    }

    function test_lazyWriteoffDoesNotLeaveReplacementLocked() public {
        vm.prank(ALICE);
        uint256 shares = vault.depositToken(1000 ether);
        _accrue(5 ether);
        vm.prank(ALICE); vault.withdrawToken(shares);
        assertTrue(vault.hasStakers());
        _roundTrip();
        assertEq(vault.pendingTokYield(ALICE), 0);
        assertFalse(vault.hasStakers());
        engine.setVault(address(0));
    }
}
