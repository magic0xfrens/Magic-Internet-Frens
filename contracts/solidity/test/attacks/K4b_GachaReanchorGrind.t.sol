// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FinalAuditBase} from "../final/FinalAuditBase.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * K4b — the crystal gacha's expired-seed RE-ANCHOR is UNCAPPED.
 *
 * `CauldronHook._resolveTickets` (CauldronHook.sol:2394-2398):
 *      if (bh == 0) {
 *          b.commitBlock = uint48(block.number);
 *          break; // FIFO: resume from here on the next call
 *      }
 *
 * The seed `blockhash(commitBlock)` is public one block after the commit, so the
 * player knows the outcome of every ticket in their batch before anybody resolves
 * it. Resolution is permissionless but nothing OBLIGES it: if the roll is a loss the
 * player simply lets the batch age past 256 blocks and re-anchors it, for the price
 * of one transaction, AS MANY TIMES AS THEY LIKE.
 *
 * {CauldronCollection._reveal} caps exactly this at ONE re-anchor per token
 * (`reanchored`, CauldronCollection.sol:254/302) with a note describing the attack.
 * The hook's ticket queue never got the cap.
 */
contract K4b_GachaReanchorGrind is FinalAuditBase {
    CauldronCollection internal col;
    address internal constant PM_STUB = address(0xBEEF01);
    address internal player;

    uint256 internal constant NFT_CREDIT_SLOT = 29; // forge inspect CauldronHook storageLayout

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

    function _grantCredit(uint256 amount) internal {
        uint256 epoch = hook.creditEpoch();
        bytes32 inner = keccak256(abi.encode(epoch, NFT_CREDIT_SLOT));
        bytes32 slot = keccak256(abi.encode(player, inner));
        vm.store(address(hook), slot, bytes32(amount));
    }

    /// @dev The roll `_resolveTickets` will compute for ticket 0 of batch 0.
    function _rollFor(uint256 commitBlock) internal view returns (uint256) {
        bytes32 bh = blockhash(commitBlock);
        return uint256(keccak256(abi.encodePacked(bh, player, uint256(0), uint256(0)))) % 10_000;
    }

    /// @dev Grind: only ever resolve a batch whose precomputed roll WINS; otherwise
    ///      let the seed expire and re-anchor. Returns how many re-anchors it took
    ///      and whether the single ticket ultimately won.
    function _grindUntilWin(uint256 odds, uint256 maxRounds)
        internal
        returns (uint256 reanchors, bool won, uint256 mintedAfter)
    {
        uint256 commitBlock = vm.getBlockNumber();
        for (uint256 i; i < maxRounds; ++i) {
            vm.roll(commitBlock + 1);
            // The viaIR build can sink cheatcode-sensitive reads: prove the roll took.
            require(vm.getBlockNumber() == commitBlock + 1, "vm.roll had no effect");
            if (_rollFor(commitBlock) < odds) {
                hook.resolveTickets(30);
                break;
            }
            // Losing seed: never resolve it. Let it expire, re-anchor for free.
            vm.roll(commitBlock + 300);
            hook.resolveTickets(30);
            // Ground truth from the hook itself. Before the fix, nothing was ever
            // consumed here — every expiry took the `bh == 0` RE-ANCHOR branch.
            // AFTER the fix (R3A) the cap bites on the SECOND expiry: the batch
            // commits its base outcome (a loss) and is consumed, so the grind ends.
            if (hook.outstandingTickets() == 0) break;
            commitBlock = vm.getBlockNumber();
            reanchors += 1;
        }
        mintedAfter = col.totalMinted();
        won = mintedAfter > 0;
    }

    function test_K4b_expired_ticket_seed_can_be_reground_without_limit() public {
        // A tiny play size → the honest odds are a few hundred bps at most.
        uint256 playWei = 0.05 ether;
        uint256 odds = hook.oddsForPlay(playWei);
        assertGt(odds, 0, "odds are live"); assertLt(odds, 1_000, "honest odds are under 10%");

        _grantCredit(type(uint128).max);
        uint256 n = hook.commitCrystals(player, 1, playWei);
        assertEq(n, 1, "one crystal committed");
        assertEq(hook.outstandingTickets(), 1, "ticket queued");

        uint256 startBlock = vm.getBlockNumber();
        (uint256 reanchors, bool won, uint256 minted) = _grindUntilWin(odds, 400);
        assertGt(vm.getBlockNumber(), startBlock, "time travel actually happened");

        emit log_named_uint("honest odds (bps)", odds);
        emit log_named_uint("free re-anchors used", reanchors);
        emit log_named_uint("NFTs minted from ONE crystal", minted);

        // REGRESSION (was: assertGt(reanchors, 1) / assertTrue(won)). The cap the
        // collection enforces now exists in GachaLib too: one re-anchor per batch,
        // then the base outcome is committed. The grind cannot run past it.
        assertLe(reanchors, 1, "re-anchor capped at ONE (GachaLib.REANCHORED_SLOT)");
        assertFalse(won, "a low-odds ticket can no longer be ground into a win");
        assertEq(minted, 0, "no NFT from the ground crystal");
        assertEq(hook.outstandingTickets(), 0, "ticket consumed exactly once, no wedge");
    }
}
