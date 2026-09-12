// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * @notice T9a — REGRESSION for Z-08 on the per-brew collection (the second,
 *         independently written PoC of the same grind).
 *
 *         `CauldronCollection._reveal` lets the HOLDER decide when to reveal, and
 *         `blockhash(mintBlockOf[id])` is public the instant the mint block is
 *         mined — so the holder computes the outcome first. If it was bad they
 *         simply did not reveal; once the seed aged past 256 blocks `blockhash`
 *         returned 0 and `_reveal` RE-ANCHORED to a fresh block without consuming
 *         the roll. That was an unlimited re-roll loop, not the "exactly ONE
 *         unknowable draw" the in-code comment claimed.
 *
 *         The re-anchor is now capped at one per token, and declining that one too
 *         commits the base tier. Waiting can no longer improve an outcome.
 */
contract T9aRevealRerollGrind is Test {
    CauldronCollection col;

    function setUp() public {
        col = new CauldronCollection(
            "Brew", "BRW",
            address(this),   // minter  (the volume hook, played by this test)
            address(this),   // registry / deployer
            10_000,
            MetadataMode.BaseURI,
            "ipfs://x/",
            address(0),
            address(0),
            0
        );
    }

    /// @dev What `_rollRarity(keccak(bh, id, col))` will produce — the exact same
    ///      computation the contract does, available to the holder off-chain.
    function _predict(uint256 id) internal view returns (uint8) {
        bytes32 bh = blockhash(col.mintBlockOf(id));
        if (bh == 0) return 255; // seed expired: re-anchorable
        uint256 seed = uint256(keccak256(abi.encodePacked(bh, id, address(col))));
        uint16 r = uint16(seed % 10_000);
        if (r < 7900) return 0;
        if (r < 9400) return 1;
        if (r < 9900) return 2;
        return 3;
    }

    /// @dev Grind for tier `want`. Returns the tier finally locked in and how many
    ///      re-anchors it cost. Never reverts; bounded by `maxRerolls`.
    function _grind(uint256 id, uint8 want, uint256 maxRerolls)
        internal
        returns (uint8 got, uint256 rerolls)
    {
        for (uint256 i; i <= maxRerolls; i++) {
            if (col.revealed(id)) break;   // the draw is spent — nothing left to grind
            uint8 p = _predict(id);
            if (p == want) {
                col.reveal(id);            // accept this draw
                break;
            }
            // reject: let the seed rot past the 256-block blockhash window, then
            // call reveal() — which used to re-anchor instead of rolling.
            vm.roll(vm.getBlockNumber() + 300);
            col.reveal(id);
            // Only a re-anchor that did NOT commit bought another draw.
            if (!col.revealed(id)) rerolls++;
            vm.roll(vm.getBlockNumber() + 1);     // new seed now knowable
        }
        return (col.rarityOf(id), rerolls);
    }

    function test_RevealIsRerollableUntilUltra() public {
        vm.roll(1_000);
        uint256 id = col.mint(address(this));
        vm.roll(vm.getBlockNumber() + 1);

        // The honest draw the holder would have been stuck with.
        uint8 honest = _predict(id);
        assertTrue(honest != 3, "control: the honest draw was not Ultra");

        // The grinder rejects everything that is not tier 3 (Ultra, 1% honest odds)
        // and is willing to spend 2,000 transactions doing it.
        (uint8 got, uint256 rerolls) = _grind(id, 3, 2_000);

        emit log_named_uint("honest draw", honest);
        emit log_named_uint("re-anchors the grinder got", rerolls);
        emit log_named_uint("final rarity", got);

        assertTrue(col.revealed(id), "token ended revealed - never bricked");
        assertLe(rerolls, 1, "FIXED: ONE re-anchor, whatever the grinder is willing to spend");
        assertTrue(got == 0 || rerolls == 1,
            "FIXED: a non-base tier can only be one of the two honest draws");
        assertTrue(col.reanchored(id), "the single re-anchor is recorded and spent");
    }

    /// Batch amplification is bounded too: `revealBatch` re-anchors up to 50 tokens
    /// in one transaction, but only ONCE each — the second expiry commits all 50.
    function test_RevealBatchReAnchorsFiftyAtOnce() public {
        vm.roll(2_000);
        uint256[] memory ids = new uint256[](50);
        for (uint256 i; i < 50; i++) ids[i] = col.mint(address(this));
        uint48 mintedAt = col.mintBlockOf(ids[0]);

        vm.roll(vm.getBlockNumber() + 300); // every seed expired
        col.revealBatch(ids);        // ONE tx re-anchors all 50 (the allowed round)

        uint256 reanchored;
        for (uint256 i; i < 50; i++) {
            if (col.mintBlockOf(ids[i]) > mintedAt && !col.revealed(ids[i])) reanchored++;
        }
        assertEq(reanchored, 50, "the one allowed re-anchor, batched");

        // The second round is where the unbounded grind used to live.
        vm.roll(vm.getBlockNumber() + 300);
        col.revealBatch(ids);

        uint256 committed;
        for (uint256 i; i < 50; i++) {
            if (col.revealed(ids[i]) && col.rarityOf(ids[i]) == 0) committed++;
        }
        assertEq(committed, 50, "FIXED: the second expiry COMMITS all 50 at the base tier");

        // A third round changes nothing at all.
        vm.roll(vm.getBlockNumber() + 300);
        col.revealBatch(ids);
        for (uint256 i; i < 50; i++) {
            assertEq(uint256(col.rarityOf(ids[i])), 0, "committed rolls are final");
        }
    }
}
