// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ICauldronCollection} from "./ICauldron.sol";

/**
 * @title GachaLib
 * @notice The crystal-resolution loop, moved out of {CauldronHook} for EIP-170
 *         headroom. A LINKED library: `external`, deployed once, DELEGATECALLed.
 *
 *  ── WHY THIS ONE ────────────────────────────────────────────────────────────
 *  The hook sits at the 24,576-byte ceiling and pre-emptive liquidation needs
 *  room in it. Extraction only pays when the moved body is large relative to
 *  what has to be marshalled across the call — moving a small function with
 *  many scalar arguments made {PerpEngine} BIGGER, measured. This loop is the
 *  opposite shape: ~45 lines of body, and almost everything it touches is a
 *  storage MAPPING or ARRAY, which an external library receives as a storage
 *  reference costing one word of calldata regardless of size.
 *
 *  ── WHAT DID NOT CHANGE ─────────────────────────────────────────────────────
 *  The body is the hook's `_resolveTickets`, verbatim, with storage reached
 *  through the passed references instead of the hook's own names. Events are
 *  emitted from inside the DELEGATECALL, so they carry the HOOK's address and an
 *  indexer cannot tell the difference — the same property {FeeRouteLib} already
 *  relies on. The two plain-uint scalars the loop mutates (`batchCursor`,
 *  `outstandingCrystals`) cannot be passed by reference, so they go in by value
 *  and come back as return values for the hook to store.
 */
library GachaLib {
    /// @dev One commit: the crystals a player opened in a single play, rolled
    ///      lazily in FIFO order against the blockhash of the commit block.
    struct Batch {
        address player;      // who the creature mints to on a win
        address collection;  // the iteration's collection (so tickets survive relaunch)
        uint48 commitBlock;  // block the crystals were opened in (seeds the rolls)
        uint16 oddsBps;      // win probability, fixed at commit from play size
        uint16 count;        // crystals in this batch
        uint16 resolved;     // how many rolled so far
    }

    //  Declared here so the library can emit them; identical signatures to the
    //  hook's own declarations, so the logs are indistinguishable.
    event TicketWon(address indexed player, uint256 indexed ticketId, uint256 tokenId);
    event TicketLost(address indexed player, uint256 indexed ticketId);

    /**
     * @notice Resolve up to `maxCount` pending crystals, in commit order.
     *
     *  Each crystal's outcome is seeded by the blockhash of its commit block —
     *  unknown at commit, so it cannot be foreseen, grinded, or re-rolled by
     *  reverting. Stops (no revert) at a batch committed in the current block,
     *  and re-stamps a batch whose blockhash has aged out of the 256-block window
     *  so it is rolled against a fresh, still-unknown seed on a later call.
     *
     * @return newCursor      value for the hook to store into `batchCursor`
     * @return newOutstanding value for the hook to store into `outstandingCrystals`
     * @return processed      crystals rolled this call
     * @return won            creatures minted this call
     */
    function resolveTickets(
        Batch[] storage batches,
        mapping(address => uint256) storage missStreak,
        mapping(address => uint256) storage pendingOf,
        mapping(address => uint256) storage outstandingOf,
        mapping(address => uint256) storage opened,
        uint256 batchCursor,
        uint256 pityThreshold,
        uint256 outstandingCrystals,
        uint256 maxCount
    ) external returns (uint256 newCursor, uint256 newOutstanding, uint256 processed, uint256 won) {
        uint256 bi = batchCursor;
        uint256 end = batches.length;
        while (processed < maxCount && bi < end) {
            Batch storage b = batches[bi];
            if (block.number <= b.commitBlock) break; // seed not known yet
            bytes32 bh = blockhash(b.commitBlock);
            if (bh == 0) {
                b.commitBlock = uint48(block.number);
                break; // FIFO: resume from here on the next call
            }
            address player = b.player;
            address col = b.collection;
            uint256 odds = b.oddsBps;
            uint256 minted = ICauldronCollection(col).totalMinted();
            uint256 max = ICauldronCollection(col).maxSupply();
            uint256 r = b.resolved;
            uint256 total = b.count;
            while (processed < maxCount && r < total) {
                uint256 roll = uint256(keccak256(abi.encodePacked(bh, player, bi, r))) % 10_000;
                bool forced = missStreak[player] >= pityThreshold;
                bool win = (forced || roll < odds) && minted < max;
                pendingOf[player] -= 1;
                outstandingCrystals -= 1;
                outstandingOf[col] -= 1;
                if (win) {
                    missStreak[player] = 0;
                    opened[player] += 1;
                    uint256 tokenId = ICauldronCollection(col).mint(player);
                    unchecked { minted++; won++; }
                    emit TicketWon(player, bi, tokenId);
                } else {
                    if (roll >= odds && minted < max) missStreak[player] += 1;
                    emit TicketLost(player, bi);
                }
                unchecked { r++; processed++; }
            }
            b.resolved = uint16(r);
            if (r == total) { unchecked { bi++; } } else break;
        }
        newCursor = bi;
        newOutstanding = outstandingCrystals;
    }
}
