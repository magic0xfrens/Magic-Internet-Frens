// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReauditLocalManagers} from "../audit_reaudit/RotationTotalityLocal.t.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";

contract R23BadgeFloorLocal is ReauditLocalManagers {
    function test_badgeCannotConsumeArtFloor() public {
        _boot(20 ether, 0);
        perp = new PerpEngine(pm, address(hook), address(registry), address(0), address(0xD1D1), address(0x7E7E), address(this));
        hook.setPerpEngine(address(perp));
        CollectionLedger ledger = new CollectionLedger(address(registry));
        registry.setCollectionLedger(address(ledger));
        CauldronCollection col = CauldronCollection(registry.generationCollection(1));
        // Isolate admission from earning an art draw / keeper badge. Real
        // collection code, but authorized minter roles are impersonated here.
        vm.prank(address(hook));
        col.mint(address(0xA117));
        address badgeMinter = col.liquidatorMinter();
        assertTrue(badgeMinter != address(0), "production badge wiring exists");
        vm.prank(badgeMinter);
        uint256 badge = col.mintLiquidator(victim);
        assertEq(col.totalMinted(), 1);
        hook.setLegacyBuyback(address(registry), 1000, 0.001 ether);
        hook.fundLegacyBuffer{value: 0.1 ether}();
        vm.roll(block.number + 40);
        _buy(0.1 ether, victim);
        vm.roll(block.number + 1);
        _buy(0.001 ether, victim);
        assertGt(hook.legacyOwedToReserve(), 0);
        registry.materializeLegacyReserve();
        assertGt(ledger.entitledTokens(1), 0, "funded art entitlement");
        uint256 artBacking = ledger.entitledTokens(1);
        vm.prank(victim);
        (bool accepted, bytes memory result) = address(registry).call(
            abi.encodeCall(registry.recycleCollectionNFT, (1, badge))
        );
        if (accepted) {
            emit log_named_uint("art backing before badge claim", artBacking);
            emit log_named_uint("tokens paid for badge", abi.decode(result, (uint256)));
            emit log_named_uint("art backing after badge claim", ledger.entitledTokens(1));
            assertEq(col.ownerOf(badge), address(registry), "badge taken into treasury");
        }
        assertFalse(accepted, "badge must not consume art entitlement");
    }
}
