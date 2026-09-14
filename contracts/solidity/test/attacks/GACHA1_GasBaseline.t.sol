// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FinalAuditBase} from "../final/FinalAuditBase.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/// Gas baseline for the crystal resolve loop. Identical file is run against the
/// pre-extraction tree and the post-extraction tree.
contract GACHA1_GasBaseline is FinalAuditBase {
    CauldronCollection internal col;
    address internal constant PM_STUB = address(0xBEEF03);
    address internal player;
    uint256 internal constant NFT_CREDIT_SLOT = 29;

    function setUp() public {
        player = address(this);
        _deployOffchain(PM_STUB);
        col = new CauldronCollection(
            "Creature", "CRT", address(hook), address(registry), 1000,
            MetadataMode.BaseURI, "ipfs://c/", address(0), address(0), 0
        );
        vm.prank(address(registry));
        hook.setCollection(address(col));
        hook.setOpener(address(this), true);
        vm.roll(1000);
    }

    function _grantCredit(address who, uint256 amount) internal {
        uint256 epoch = hook.creditEpoch();
        bytes32 inner = keccak256(abi.encode(epoch, NFT_CREDIT_SLOT));
        vm.store(address(hook), keccak256(abi.encode(who, inner)), bytes32(amount));
    }

    function _gasFor(uint256 crystals) internal returns (uint256 used) {
        _grantCredit(player, type(uint128).max);
        hook.commitCrystals(player, crystals, 0.5 ether);
        vm.roll(vm.getBlockNumber() + 1);
        uint256 g0 = gasleft();
        hook.resolveTickets(crystals);
        used = g0 - gasleft();
    }

    function test_gas_resolve() public {
        uint256 g1 = _gasFor(1);
        uint256 g4 = _gasFor(4);
        uint256 g6 = _gasFor(6);
        uint256 g8 = _gasFor(8);
        emit log_named_uint("RESOLVE_1", g1);
        emit log_named_uint("RESOLVE_4", g4);
        emit log_named_uint("RESOLVE_6", g6);
        emit log_named_uint("RESOLVE_8", g8);
        assertGt(g1, 0, "measured");
    }

    /// Full in-swap step: commit 4 + resolve 6, exactly what afterSwap fires.
    function test_gas_nativeGachaStep() public {
        _grantCredit(player, type(uint128).max);
        hook.commitCrystals(player, 6, 0.5 ether);
        vm.roll(vm.getBlockNumber() + 1);
        uint256 g0 = gasleft();
        vm.prank(address(hook));
        hook.nativeGachaStep(player, 0.5 ether);
        uint256 used = g0 - gasleft();
        emit log_named_uint("NATIVE_STEP", used);
        assertGt(used, 0, "measured");
    }
}
