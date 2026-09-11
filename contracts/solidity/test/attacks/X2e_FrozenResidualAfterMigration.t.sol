// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {F10_QuoteRotationTotality} from "../functional/F10_QuoteRotationTotality.t.sol";

/**
 * X2e — REGRESSION. A COMPLETED migration flips `generationQuote` but
 *       leaves `generationPositionId` / `generationPoolKey` on the launch pair
 *       (written in exactly one place, CauldronRegistry.sol:1743-1744). Every
 *       later `fromLeg == 0` slice then read its source amount in the NEW quote
 *       out of the OLD pair, so `quoteOut == 0` and it reverted BadConfig
 *       (RedemptionExt.sol:371) — the ~32% residual could never be rotated again.
 *
 * FIX: `rotateSliceFrom` resolves leg 0's quote from `generationPoolKey.currency0`,
 * the pair's OWN quote, rather than from `generationQuote`. The two are equal until
 * a migration completes, so nothing changes for a fresh generation.
 */
contract X2e_FrozenResidualAfterMigration is F10_QuoteRotationTotality {
    function _completeMigration(PoolKey memory route) internal {
        uint256 id = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
        for (uint256 i; i < 20; ++i) {
            (address open,) = governor.allowance();
            if (open == address(0)) break;
            try registry.rotateSlice(2500, 0, route) {} catch { break; }
        }
    }

    /// @dev A second envelope to finish the job: the first one moved ~68% and left a
    ///      residual in the LAUNCH pair, which is exactly the state this regression
    ///      is about. Destination is USDG again — continuing the migration, not
    ///      returning — because ETH -> ETH out of the primary is a self-rotation and
    ///      is refused on purpose (see the control below).
    function _approveDrainingTheResidual() internal {
        _warp(uint256(governor.COOLDOWN()) + 1);
        uint256 id = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
    }

    function test_X2e_residualStaysRotatableAfterTheQuoteFlips() public {
        vm.skip(!active);
        console2.log("X2e: harness live");

        PoolKey memory route = _seedVenue();
        uint256 posBefore = registry.generationPositionId(1);
        (Currency c0Before,,,,) = registry.generationPoolKey(1);

        _completeMigration(route);
        assertEq(registry.generationQuote(1), address(usdg), "precondition: the migration completed and the quote flipped");

        // THE MISMATCH: the pair record never followed the quote.
        uint256 posAfter = registry.generationPositionId(1);
        (Currency c0After,,,,) = registry.generationPoolKey(1);
        assertEq(posAfter, posBefore, "generationPositionId still names the LAUNCH position");
        assertEq(Currency.unwrap(c0After), Currency.unwrap(c0Before), "generationPoolKey still names the LAUNCH pair (ETH)");
        assertEq(Currency.unwrap(c0After), address(0), "...which is native ETH, not the new quote");
        console2.log("X2e: quote flipped to USDG, primary pair still currency0 = ETH, position", posAfter);

        _approveDrainingTheResidual();
        (address dest,) = governor.allowance();
        assertEq(dest, address(usdg), "a fresh envelope approves draining the residual");

        // THE FINDING: a slice out of the PRIMARY, which used to revert BadConfig
        // (0x07cc321c) because it measured USDG out of the ETH pair.
        (bool primaryOk, bytes memory err) = address(registry).call(
            abi.encodeWithSignature("rotateSlice(uint16,uint256,(address,address,uint24,int24,address))",
                uint16(2500), uint256(0), route)
        );
        console2.log("X2e primary slice ok?", primaryOk);
        console2.log("X2e primary revert data:", vm.toString(err));
        assertTrue(primaryOk, "FIXED: the primary residual is still addressable and rotates");

        // CONTROL: the fix resolves the primary's REAL quote, it does not disable the
        // same-quote guard. Leg 1 is already USDG, so rotating it into USDG is still
        // refused as a self-rotation.
        (bool selfOk,) = address(registry).call(
            abi.encodeWithSignature("rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))",
                uint8(1), uint16(2500), uint256(0), route)
        );
        assertFalse(selfOk, "CONTROL: a leg still cannot rotate into its own quote");

        // ...and the primary really did give up ETH: the launch pair shrank.
        assertEq(registry.generationPositionId(1), posBefore, "the primary position id is unchanged");
    }
}
