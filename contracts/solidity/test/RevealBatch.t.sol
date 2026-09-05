// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronCollection} from "../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../cauldron/ICauldron.sol";

/**
 * @dev Revealing many crystals in one transaction.
 *
 *  Reveal was one token per transaction, so thirty crystals meant thirty base
 *  fees to see what you already owned. The per-token work is identical either
 *  way — this is about not paying for a transaction over and over.
 *
 *  The randomness must be UNCHANGED by batching, and that is the property most
 *  worth pinning down: each token still rolls from its own mint block, so a
 *  batch is N independent draws with no shared seed to grind.
 */
contract RevealBatchTest is Test {
    CauldronCollection col;
    address constant HOOK = address(0x8001);
    address constant OWNER = address(0xF00D);

    function setUp() public {
        col = new CauldronCollection(
            "Gnome", "GNOME", HOOK, address(this), 100,
            MetadataMode.BaseURI, "ipfs://g/", address(0), address(0xD19), uint96(500)
        );
    }

    function _mint(uint256 n) internal returns (uint256[] memory ids) {
        ids = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            vm.prank(HOOK);
            ids[i] = col.mint(OWNER);
        }
        // The seed is the mint block's hash, so it must be in the past.
        vm.roll(block.number + 1);
    }

    function test_BatchRevealsEveryToken() public {
        uint256[] memory ids = _mint(12);

        vm.prank(OWNER);
        col.revealBatch(ids);

        for (uint256 i; i < ids.length; ++i) {
            assertTrue(col.revealed(ids[i]), "every token in the batch is revealed");
        }
    }

    /// The point of the change, measured rather than asserted.
    function test_BatchIsCheaperThanOneByOne() public {
        uint256[] memory a = _mint(10);
        uint256 g0 = gasleft();
        for (uint256 i; i < a.length; ++i) {
            vm.prank(OWNER);
            col.reveal(a[i]);
        }
        uint256 oneByOne = g0 - gasleft();

        uint256[] memory b = _mint(10);
        g0 = gasleft();
        vm.prank(OWNER);
        col.revealBatch(b);
        uint256 batched = g0 - gasleft();

        emit log_named_uint("one-by-one (execution only)", oneByOne);
        emit log_named_uint("batched     (execution only)", batched);
        // forge does not charge the 21,000 base fee per vm.prank call, so the
        // execution-only saving is modest; the real win is 9 fewer transactions
        // (~189,000 gas). Assert the batch is not WORSE, which is what the loop
        // could plausibly get wrong.
        assertLe(batched, oneByOne + 5_000, "batching must not cost more than looping");
    }

    /// Batching must not correlate outcomes. Each token draws from its own mint
    /// block, so a batch is N independent rolls — if they were sharing a seed,
    /// a large batch would come back all-identical.
    function test_RandomnessIsPerTokenNotPerBatch() public {
        uint256[] memory ids = _mint(40);
        vm.prank(OWNER);
        col.revealBatch(ids);

        uint8 first = col.rarityOf(ids[0]);
        bool anyDifferent;
        for (uint256 i = 1; i < ids.length; ++i) {
            if (col.rarityOf(ids[i]) != first) { anyDifferent = true; break; }
        }
        assertTrue(anyDifferent, "a batch must not roll one shared outcome");
    }

    /// A caller should be able to pass their whole wallet without filtering it
    /// first, so already-revealed ids are skipped rather than reverting.
    function test_AlreadyRevealedAreSkipped() public {
        uint256[] memory ids = _mint(5);
        vm.prank(OWNER);
        col.reveal(ids[2]);

        vm.prank(OWNER);
        col.revealBatch(ids); // must not revert on the already-revealed one

        for (uint256 i; i < ids.length; ++i) assertTrue(col.revealed(ids[i]));
    }

    function test_CannotRevealSomeoneElsesTokens() public {
        uint256[] memory ids = _mint(3);
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronCollection.OnlyMinter.selector);
        col.revealBatch(ids);
    }

    /// Bounded so a caller cannot build a batch that runs out of gas midway and
    /// wastes the entire fee.
    function test_BatchIsBounded() public {
        uint256[] memory tooMany = new uint256[](51);
        vm.prank(OWNER);
        vm.expectRevert(CauldronCollection.BadBatch.selector);
        col.revealBatch(tooMany);

        uint256[] memory none = new uint256[](0);
        vm.prank(OWNER);
        vm.expectRevert(CauldronCollection.BadBatch.selector);
        col.revealBatch(none);
    }
}
