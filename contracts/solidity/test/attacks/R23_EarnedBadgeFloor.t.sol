// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LocalLifecycleBoot} from "../audit_full_scope/LocalLifecycleAdapters.t.sol";
import {YNoFrens} from "./YBase.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

contract R23EarnedBadgeFloor is LocalLifecycleBoot {
    function test_swapEarnedBadgeCannotRedeemFundedArtBacking() public {
        _boot(60 ether, 0);
        perp = new PerpEngine(pm, address(hook), address(registry), address(new YNoFrens()),
            address(0xD1D1), address(0x7E7E), address(this));
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 40 ether}(40 ether);
        // Explicit fixture inventory, as in the existing perp local lifecycle lane.
        deal(token, address(this), 400_000_000 ether, true);
        IERC20Minimal(token).approve(address(perp), 400_000_000 ether);
        perp.fundPlvToken(400_000_000 ether);
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        _warp(25 hours);
        vm.roll(vm.getBlockNumber() + 40);
        // Initialize observations through ordinary trading, never public poke.
        _buy(0.001 ether, attacker);

        CollectionLedger ledger = new CollectionLedger(address(registry));
        registry.setCollectionLedger(address(ledger));
        CauldronCollection col = CauldronCollection(hook.collection());
        // Earn art from paid swap credit and real commit/resolve. Zero random
        // odds plus pity=1 make the second funded ticket a deterministic win.
        hook.setNftCurve(0.007 ether, 0);
        hook.setOddsParams(1 ether, 1);
        hook.setMaxOdds(0);
        // Untagged native flow attributes and commits to tx.origin.
        _buy(0.01 ether, tx.origin);
        assertEq(hook.pendingOf(tx.origin), 2);
        uint256 commitBlock = vm.getBlockNumber();
        vm.roll(commitBlock + 1);
        vm.setBlockhash(commitBlock, bytes32(uint256(123)));
        (uint256 processed, uint256 won) = hook.resolveTickets(2);
        assertEq(processed, 2);
        assertEq(won, 1);
        assertEq(col.totalMinted(), 1);
        assertEq(col.ownerOf(1), tx.origin);
        assertEq(hook.pendingOf(tx.origin), 0);
        hook.setLegacyBuyback(address(registry), 1000, 0.001 ether);
        hook.fundLegacyBuffer{value: 0.1 ether}();
        _buy(0.1 ether, victim);
        vm.roll(vm.getBlockNumber() + 1);
        _buy(0.001 ether, victim);
        assertGt(hook.legacyOwedToReserve(), 0, "buyback funded reserve delivery");
        registry.materializeLegacyReserve();
        uint256 backing = ledger.entitledTokens(1);
        assertGt(backing, 0, "real reserve-backed art entitlement");

        address shortOwner = address(0xA001);
        vm.deal(shortOwner, 1 ether);
        vm.prank(shortOwner);
        uint256 position = perp.openShort{value: 0.01 ether}(2, 0, 0, 0.01 ether);
        assertEq(perp.openCount(), 1);
        assertFalse(perp.isLiquidatable(position), "healthy before triggering swap");
        uint256 mintedBefore = col.liquidatorMinted();
        address liquidator = tx.origin;
        uint256 owedBefore = perp.badgesOwed(liquidator);
        _buy(45 ether, attacker);
        assertEq(perp.openCount(), 0, "ordinary swap liquidated position");
        assertEq(col.liquidatorMinted() - mintedBefore + perp.badgesOwed(liquidator) - owedBefore,
            1, "exactly one earned badge");
        if (perp.badgesOwed(liquidator) > owedBefore) {
            vm.prank(liquidator);
            perp.claimLiquidatorBadges(1);
        }
        uint256 badge = col.LIQUIDATOR_ID_BASE() + mintedBefore + 1;
        assertEq(col.ownerOf(badge), liquidator);
        uint256 beforeClaim = ledger.entitledTokens(1);
        assertGe(beforeClaim, backing);
        uint256 holderTokens = IERC20Minimal(token).balanceOf(liquidator);
        vm.expectRevert(bytes("not art"));
        vm.prank(liquidator);
        registry.recycleCollectionNFT(1, badge);
        assertEq(col.ownerOf(badge), liquidator);
        assertEq(ledger.entitledTokens(1), beforeClaim, "art backing conserved");
        assertEq(IERC20Minimal(token).balanceOf(liquidator), holderTokens, "no floor payout for badge");
    }
}
