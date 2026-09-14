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
 *  `outstandingCrystals`) are grouped into {State} so they too cross as ONE
 *  storage reference and are written in place — they briefly went by value and
 *  came back as return values, which is exactly the shape a re-entrant resolve
 *  turns into a stale overwrite (GACHA1-g).
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

    /// @dev The two loop scalars, as ONE storage reference so the loop writes
    ///      them in place (GACHA1-g).
    struct State {
        uint256 batchCursor;         // index of the batch being resolved
        uint256 outstandingCrystals; // unresolved crystals across all players
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
     * @return processed      crystals rolled this call
     * @return won            creatures minted this call
     */
    function resolveTickets(
        Batch[] storage batches,
        mapping(address => uint256) storage missStreak,
        mapping(address => uint256) storage pendingOf,
        mapping(address => uint256) storage outstandingOf,
        mapping(address => uint256) storage opened,
        State storage st,
        uint256 pityThreshold,
        uint256 maxCount
    ) external returns (uint256 processed, uint256 won) {
        uint256 bi = st.batchCursor;
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
                st.outstandingCrystals -= 1;
                outstandingOf[col] -= 1;
                //  EFFECTS BEFORE THE ONLY EXTERNAL INTERACTION (GACHA1-g). The
                //  crystal is consumed and the batch cursor advanced BEFORE the
                //  mint, so a re-entrant resolve — impossible today (`_mint`, a
                //  view validator, `nonReentrant` on both callers) but one
                //  `_safeMint` away — finds the queue already moved past this roll
                //  instead of rolling it again.
                unchecked { r++; processed++; }
                b.resolved = uint16(r);
                if (win) {
                    missStreak[player] = 0;
                    opened[player] += 1;
                    //  A MINT THAT REVERTS MUST NOT WEDGE THE QUEUE (GACHA1-b). The
                    //  cursor can never pass a batch whose mint reverts, so one
                    //  transfer-validator policy that rejects the hook as operator
                    //  would freeze every player's crystals forever. The crystal is
                    //  already spent; a failed mint is recorded as a loss, WITHOUT
                    //  counting against the player's pity streak — it was not their
                    //  miss.
                    try ICauldronCollection(col).mint(player) returns (uint256 tokenId) {
                        unchecked { minted++; won++; }
                        emit TicketWon(player, bi, tokenId);
                    } catch {
                        emit TicketLost(player, bi);
                    }
                } else {
                    if (roll >= odds && minted < max) missStreak[player] += 1;
                    emit TicketLost(player, bi);
                }
            }
            if (r == total) { unchecked { bi++; } } else break;
        }
        //  MONOTONIC. A re-entrant inner resolve (impossible today, see above)
        //  may have advanced the cursor past this frame's `bi`; a plain write
        //  here would rewind it. Harmless — `b.resolved` stops any re-roll and
        //  the next call self-heals — but a cursor that only moves forward costs
        //  nothing and removes the transient lie.
        if (bi > st.batchCursor) st.batchCursor = bi;
    }
}
