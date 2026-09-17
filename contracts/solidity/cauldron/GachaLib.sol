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
     * @dev Base of an ERC-7201-style namespaced mapping `batchIndex => bool`
     *      recording whether a batch has already spent its ONE expiry re-anchor.
     *
     *  ── ONE RE-ANCHOR, EVER (red-team R3A) ──────────────────────────────────
     *  The re-anchor above used to be UNCAPPED, and that is a free, unlimited
     *  re-roll of a mint-or-nothing draw: the outcome of a committed batch is
     *  public the moment its commit block is mined, so a player who peeks and
     *  sees a loser simply declines to resolve it. 256 blocks later `blockhash`
     *  returns zero and ANY later `resolveTickets` call — gas only, no fee —
     *  re-stamps the batch to a fresh block, i.e. a brand-new draw. Measured at
     *  20 re-anchors turning a 900-bps ticket into a mint. The two sibling reveal
     *  paths already cap exactly this at one ({CauldronCollection.reanchored},
     *  {MiFrensGenesis.reanchored}); the gacha path, which governs the NFT itself
     *  rather than cosmetic rarity, had no cap at all.
     *
     *  The flag lives in a HASHED namespace rather than in {Batch} on purpose:
     *  this library is DELEGATECALLed, so it writes into the hook's storage, and
     *  a hashed slot cannot collide with any slot the hook declares. Adding a
     *  field to {Batch} would instead change the hook's public
     *  `batches(uint256)` getter (an ABI break for the indexer and the frontend)
     *  and its push site. Behaviour, not layout, is what needed to change.
     */
    bytes32 private constant REANCHORED_SLOT = keccak256("cauldron.gacha.reanchored.v1");

    function _reanchored(uint256 bi) private view returns (bool v) {
        bytes32 s = keccak256(abi.encode(bi, REANCHORED_SLOT));
        assembly ("memory-safe") { v := iszero(iszero(sload(s))) }
    }

    function _markReanchored(uint256 bi) private {
        bytes32 s = keccak256(abi.encode(bi, REANCHORED_SLOT));
        assembly ("memory-safe") { sstore(s, 1) }
    }

    /**
     * @dev Base of a second namespaced mapping `batchIndex => bytes32`: the
     *      batch's PINNED seed, `blockhash(commitBlock)` copied into storage
     *      while it was still inside the EVM's 256-block horizon.
     *
     *  ── WHY (red-team T3B) ─────────────────────────────────────────────────
     *  `blockhash` returns zero past 256 blocks. That is an EVM constant, not a
     *  tunable: on a 12-second chain it is ~51 minutes, on Robinhood Chain —
     *  measured at 0.1012 s/block — it is 25.9 SECONDS, and the second expiry
     *  that forfeits the batch lands at 51.8 seconds. An honest player who pays
     *  for a 9,000-bps draw and hits a slow RPC loses the whole stake, with no
     *  attacker involved.
     *
     *  Pinning fixes that WITHOUT handing anyone a second draw. The pinned value
     *  is the ORIGINAL commit block's hash — the very seed the player could
     *  already read off-chain — so a pinned batch's outcome is frozen: waiting
     *  cannot improve it, and there is nothing to re-roll. Any single
     *  `resolveTickets` call that lands inside the batch's first 256 blocks
     *  (every swap fires one via `nativeGachaStep`, and all three router
     *  entrypoints call it) immunises the batch FOREVER.
     *
     *  What is deliberately NOT changed: a batch that no call touches at all
     *  inside its window still gets exactly ONE re-anchor and then commits a
     *  loss. That terminal forfeit is the only outcome a player who peeks at a
     *  losing seed and declines to resolve cannot profit from; every softer
     *  ending (refund, extra re-anchor, longer grace) is a free option on a
     *  draw whose result is already public. See {REANCHORED_SLOT}.
     *
     *  Hashed namespace, same reason as {REANCHORED_SLOT}: this library is
     *  DELEGATECALLed into the hook's storage, and adding a field to {Batch}
     *  would break the hook's public `batches(uint256)` getter for the indexer
     *  and the frontend.
     */
    bytes32 private constant SEED_SLOT = keccak256("cauldron.gacha.seed.v1");

    /// @dev How far past the cursor the pin sweep reaches. Batches behind a
    ///      long head batch age out too when `maxCount` is exhausted before the
    ///      loop reaches them, so the sweep cannot only cover the head. Bounded
    ///      so the gas-capped in-swap path ({CauldronHook.nativeGachaStep}) can
    ///      still afford it.
    uint256 private constant PIN_SPAN = 4;

    function _seed(uint256 bi) private view returns (bytes32 v) {
        bytes32 s = keccak256(abi.encode(bi, SEED_SLOT));
        assembly ("memory-safe") { v := sload(s) }
    }

    function _pinSeed(uint256 bi, bytes32 v) private {
        bytes32 s = keccak256(abi.encode(bi, SEED_SLOT));
        assembly ("memory-safe") { sstore(s, v) }
    }

    /// @dev Copy the still-live blockhash of every unresolved batch in
    ///      `[from, from+PIN_SPAN)` into storage. `blockhash` of the current or
    ///      a future block is zero and is skipped — nothing is ever pinned to a
    ///      seed that is not yet determined, so pinning can never fix an outcome
    ///      the roller could have chosen.
    function _pinSeeds(Batch[] storage batches, uint256 from, uint256 end) private {
        uint256 stop = from + PIN_SPAN;
        if (stop > end) stop = end;
        for (uint256 k = from; k < stop; ) {
            if (_seed(k) == bytes32(0)) {
                bytes32 bh = blockhash(batches[k].commitBlock);
                if (bh != bytes32(0)) _pinSeed(k, bh);
            }
            unchecked { k++; }
        }
    }

    /**
     * @notice Resolve up to `maxCount` pending crystals, in commit order.
     *
     *  Each crystal's outcome is seeded by the blockhash of its commit block —
     *  unknown at commit, so it cannot be foreseen, grinded, or re-rolled by
     *  reverting. Stops (no revert) at a batch committed in the current block,
     *  and re-stamps a batch whose blockhash has aged out of the 256-block window
     *  so it is rolled against a fresh, still-unknown seed on a later call — ONCE
     *  per batch, ever (see {REANCHORED_SLOT}); a batch that ages out a second
     *  time commits its base outcome rather than drawing again.
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
            //  PINNED seed first (T3B): once any call has copied this batch's
            //  commit-block hash into storage the outcome is frozen and the
            //  256-block wall-clock deadline no longer applies. Falls back to
            //  the live `blockhash` for a batch nothing has pinned yet.
            bytes32 bh = _seed(bi);
            if (bh == bytes32(0)) bh = blockhash(b.commitBlock);
            //  Set when the batch has aged out AND already spent its single
            //  re-anchor: the remaining crystals commit their base outcome (a
            //  loss) instead of being re-rolled. See {REANCHORED_SLOT}.
            bool expired;
            if (bh == 0) {
                if (!_reanchored(bi)) {
                    _markReanchored(bi);
                    b.commitBlock = uint48(block.number);
                    break; // FIFO: resume from here on the next call
                }
                //  SECOND EXPIRY: the honest re-draw was offered and declined.
                //  We must NOT roll against `bh == 0` — that seed is known, which
                //  is the deterministic-fallback hazard the sibling paths document.
                //  Commit the base outcome instead, so the batch always resolves
                //  and the queue can never wedge.
                expired = true;
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
                //  An expired batch cannot win on its roll — the seed is zero and
                //  therefore known — but the PITY guarantee still pays out, because
                //  that outcome was already owed and is not seed-dependent.
                bool win = (forced || (!expired && roll < odds)) && minted < max;
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
                    //  A forfeited (twice-expired) crystal is not counted as a
                    //  miss: it was not a draw the player lost, so it must not
                    //  buy pity credit toward a forced win either.
                    if (!expired && roll >= odds && minted < max) missStreak[player] += 1;
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
        //  PIN THE SEEDS OF WHAT IS LEFT (T3B). Runs after the cursor is final,
        //  so it covers the batch the loop stopped inside (partially resolved,
        //  `maxCount` exhausted) and the next few behind it. Costs one SLOAD per
        //  already-pinned batch in steady state.
        _pinSeeds(batches, st.batchCursor, end);
    }
}
