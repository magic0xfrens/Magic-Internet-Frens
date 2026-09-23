// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReauditLocalManagers} from "../audit_reaudit/RotationTotalityLocal.t.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {CauldronVault} from "../../cauldron/CauldronVault.sol";

contract R23LedgerRegistryLocal is ReauditLocalManagers {
    function test_pendingFundedBuybackReleasedWhenEmptyCollectionDies() public {
        _boot(20 ether, 0);
        CollectionLedger ledger = new CollectionLedger(address(registry));
        registry.setCollectionLedger(address(ledger));
        hook.setLegacyBuyback(address(registry), 1000, 0.001 ether);
        hook.fundLegacyBuffer{value: 0.1 ether}();
        vm.roll(block.number + 40);
        _buy(0.1 ether, victim);
        // The first call only seeds the buyback's reference; it cannot spend
        // against a sample born in the triggering swap's block.
        vm.roll(block.number + 1);
        _buy(0.001 ether, victim);
        uint256 pending = hook.legacyOwedToReserve();
        assertGt(pending, 0, "real buyback must acquire tokens");
        CauldronVault vault = CauldronVault(payable(registry.generationVault(1)));
        assertEq(vault.outstanding(), 0, "fixture has no volume-minted claimants");
        assertEq(ledger.totalEntitled(), 0, "pending not yet materialized");
        vm.warp(vm.getBlockTimestamp() + 25 hours);
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2);
        assertTrue(ledger.crystallized(1));
        assertTrue(ledger.isDeadEnd(1));
        assertEq(ledger.entitledTokens(1), 0, "no permanently unclaimable reserve allocation");
        assertEq(ledger.totalEntitled(), 0);
        assertEq(hook.legacyOwedToReserve(), 0, "pending buyback flushed");
    }
}
