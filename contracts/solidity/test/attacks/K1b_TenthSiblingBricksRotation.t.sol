// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FinalAuditBase} from "../final/FinalAuditBase.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

/**
 * K1b — the sibling cap is a one-way ratchet.
 *
 *  `CauldronHook.linkVolume` refuses a 10th DISTINCT sibling
 *  (`MAX_SIBLINGS = 9`, CauldronHook.sol:773, gate at :1644) and
 *  `RedemptionExt.sol:473` calls `linkVolume` UNCONDITIONALLY inside a
 *  rotation, so the 10th distinct rotation destination reverts the WHOLE
 *  rotation, not just the bookkeeping. Nothing in the hook removes a sibling,
 *  so within a generation the slot can never be freed.
 *
 *  STATUS: the attack LANDS and is NOT fixed — the unlink costs 236 bytes and
 *  CauldronHook has 59 free under EIP-170. See the SPACE row for L3 in
 *  audit/FINAL_BLIND_2026-09-13/LEDGER.md. This file is the standing PoC.
 */
contract K1b_TenthSiblingBricksRotation is FinalAuditBase {
    PoolId internal constant PRIMARY = PoolId.wrap(bytes32(uint256(0xA1)));

    function setUp() public {
        // Same off-chain rig K1a uses: the real hook bytecode, with the test
        // standing in for the PoolManager and a real registry address.
        _deployOffchain(address(this));
    }

    function _sib(uint256 n) internal pure returns (PoolId) {
        return PoolId.wrap(bytes32(uint256(0xB000 + n)));
    }

    function test_K1b_tenthDistinctSiblingBricksRotation() public {
        // 1. Nine distinct siblings link fine.
        for (uint256 i = 0; i < 9; ++i) {
                vm.prank(address(registry));
            hook.linkVolume(PRIMARY, _sib(i));
        }
        // Re-linking an existing one is idempotent and does NOT revert.
        vm.prank(address(registry));
        hook.linkVolume(PRIMARY, _sib(3));

        // 2. The tenth DISTINCT one reverts — and it reverts the caller, which
        //    is the whole rotation, not just the link.
        uint256 gasBefore = gasleft();
        bool ok = hook.isDead(PRIMARY); // untracked -> false, but walks nothing
        emit log_named_uint("isDead_gas_9_siblings", gasBefore - gasleft());
        assertFalse(ok, "untracked primary is never dead");

        vm.expectRevert(CauldronHook.OnlyRegistry.selector);
        vm.prank(address(registry));
        hook.linkVolume(PRIMARY, _sib(9));

        // 3. There is NO unlink at ANY privilege level: the hook exposes no
        //    call that removes a sibling, so the slot can never be freed and
        //    every later rotation into a NEW quote reverts for the rest of the
        //    generation. Asserted by ABI absence, which is what "no escape"
        //    means here.
        (bool found,) = address(hook).call(
            abi.encodeWithSignature("unlinkVolume(bytes32,bytes32)", PRIMARY, _sib(0))
        );
        assertFalse(found, "OPEN L3: no unlinkVolume exists; the cap is a one-way ratchet");

        // 4. And the tenth still reverts afterwards — nothing self-heals.
        vm.expectRevert(CauldronHook.OnlyRegistry.selector);
        vm.prank(address(registry));
        hook.linkVolume(PRIMARY, _sib(9));
    }
}
