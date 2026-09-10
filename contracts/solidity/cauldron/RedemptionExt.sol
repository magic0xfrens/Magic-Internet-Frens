// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {PoolOps, IPositionManagerOps, ReserveRef} from "./PoolOps.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CauldronBase, IMiFrensContinuable} from "./CauldronBase.sol";

/**
 * @title RedemptionExt
 * @notice DELEGATECALL FACET for the Cauldron registry's OG-redemption ops. Split
 *         out of {CauldronRegistry} to reclaim EIP-170 headroom for the
 *         progressive-seed wiring. Holds the bodies of `redeemOgFren`,
 *         `buyTreasuryOgFren`, `donateToReserve`, and `materializeLegacyReserve`.
 *
 *  ── How it runs ─────────────────────────────────────────────────────────────
 *  The registry keeps thin forwarders that `delegatecall` this contract with the
 *  original calldata (see {CauldronRegistry._forwardToExt}). Because it is
 *  delegatecalled, `address(this)` and all storage/custody are the REGISTRY's:
 *    - it reads + writes the registry's storage (shared via {CauldronBase} — the
 *      two contracts' storage layouts are IDENTICAL by construction, verified with
 *      `forge inspect ... storageLayout`);
 *    - it holds the tokens/ETH and owns the position NFTs (so PoolOps' own
 *      delegatecalls and the MiFrens `custodyTransfer` resolve to the registry);
 *    - the former `positionManager` / `hook` IMMUTABLES are STORAGE in the base —
 *      immutables would resolve to zero here (they live in each contract's own
 *      code, and this facet's code never set them).
 *
 *  ── Calling it directly is harmless ──────────────────────────────────────────
 *  A direct call to a deployed RedemptionExt runs against ITS OWN (empty) storage:
 *  `summoned` is false, `genesisShares`/`mifrens`/`positionManager` are zero, and
 *  it custodies nothing — so every entrypoint reverts (NotSummoned / BadConfig /
 *  zero-address call) before it can touch any real value. No lock-down needed.
 *
 *  Behaviour is byte-for-byte the pre-split monolith; only the location changed.
 */
/// @notice The hook's generation-volume registration.
interface ITreasuryGovernor {
    function allowance() external view returns (address quote, uint16 remainingBps);
    function consume(uint16 bps) external;
}

interface IQuoteRotator {
    function swapOnce(PoolKey calldata route, address from, address to, uint256 amountIn, uint256 minOut)
        external returns (uint256);
    function withdraw(address asset, address to, uint256 amount) external;
}

interface IHookVolume {
    function linkVolume(PoolId primary, PoolId secondary) external;
}

contract RedemptionExt is CauldronBase {
    /**
     * @notice RECYCLE a genesis (OG) MiFren for its LIVE floor share of WHATEVER
     *         token the eternal machine is currently running. OG-ONLY by design —
     *         reverts for any id > genesisShares (the non-OG volume tranche has its
     *         OWN collection floor via recycleCollectionNFT, NOT this reserve). The
     *         NFT is NOT burned — it moves to the TREASURY (the registry) to be
     *         resold at 2× floor via `buyTreasuryOgFren`. The fren stops earning the
     *         instant it moves (the collection's transfer hook breaks its spell).
     *
     *  The floor is DYNAMIC (`floorPerFren()` = reserve / genesisShares) and
     *  RATCHETS UP: each redeem pulls `F` from the reserve, but the matching resale
     *  puts `2F` back + re-enchant fees add more → the reserve (and floor) only
     *  grows over time. Non-dilutive: tokens come from the out-of-range reserve
     *  (never circulating); circulating supply is unchanged.
     */
    function redeemOgFren(uint256 mifrenTokenId) external nonReentrant returns (uint256 amount) {
        if (_redeemBlocked()) revert RedemptionPaused(); // circuit-breaker (forced open while armed)
        if (!summoned) revert NotSummoned();
        // OG-only: only genesis ids (1..genesisShares) may redeem — a later
        // volume-minted MiFren can never siphon a founder's reserve share.
        if (mifrenTokenId == 0 || mifrenTokenId > genesisShares) revert BadConfig();
        if (IERC721(mifrens).ownerOf(mifrenTokenId) != msg.sender) revert NotOwnerOf();

        uint256 F = floorPerFren();
        if (F == 0) revert BadConfig();
        // Effects first: debit the reserve accounting + move the NFT to treasury
        // (breaks its spell, sets everMoved). Then pull the tokens from the LP; a
        // short reserve reverts the whole tx, so the fren is never lost for free.
        if (genesisReserveOutstanding >= F) genesisReserveOutstanding -= F;
        IMiFrensContinuable(mifrens).custodyTransfer(msg.sender, address(this), mifrenTokenId);

        uint256 g = currentGeneration;
        amount = PoolOps.claimFromReserve(
            IPositionManagerOps(address(positionManager)),
            generationReservePositionId[g], generationPoolKey[g],
            reserveTickLower[g], reserveTickUpper[g], F, msg.sender
        );
        // The reserve was already debited and the fren already moved to the treasury.
        // A short reserve must revert so BOTH roll back — never let an OG surrender
        // their fren for less than the floor. Tolerance covers liquidity rounding
        // only (see PoolOps.CLAIM_DUST). (Audit H-03.)
        if (amount + 1e12 < F) revert NoBalance();
        emit FrenRedeemed(mifrenTokenId, msg.sender, amount, g);
    }

    /**
     * @notice BUY a treasury-held (recycled) genesis fren for 2× the live floor,
     *         paid in the current token. The 2× payment is added to the reserve
     *         (out-of-range LP) → the floor grows for EVERY remaining fren. The
     *         fren arrives un-enchanted; the new owner must re-enchant (a paid,
     *         reserve-growing action for a moved fren) to earn the dividend.
     */
    function buyTreasuryOgFren(uint256 mifrenTokenId) external nonReentrant returns (uint256 paid) {
        if (!summoned) revert NotSummoned();
        if (mifrenTokenId == 0 || mifrenTokenId > genesisShares) revert BadConfig();
        // Must currently sit in the treasury (the registry owns it).
        if (IERC721(mifrens).ownerOf(mifrenTokenId) != address(this)) revert NotOwnerOf();

        paid = 2 * floorPerFren();
        if (paid == 0) revert BadConfig();

        paid = _pullGrow(msg.sender, paid);
        IMiFrensContinuable(mifrens).custodyTransfer(address(this), msg.sender, mifrenTokenId);
        emit FrenBought(mifrenTokenId, msg.sender, paid, currentGeneration);
    }

    /**
     * @notice Permissionlessly GROW the genesis floor: donate `amount` of the
     *         current token into the reserve. Anyone can raise the floor; the
     *         MiFrensDividend routes paid re-enchant fees through here so a moved
     *         fren's re-activation fee compounds the floor. Pulls via transferFrom
     *         (caller must approve first).
     */
    function donateToReserve(uint256 amount) external nonReentrant {
        if (!summoned) revert NotSummoned();
        if (amount == 0) revert BadConfig();
        _pullGrow(msg.sender, amount);
    }

    /// @notice Permissionless: deposit the hook's held live-buyback tokens into the
    ///         shared reserve LP and credit the collection ledger IN ONE STEP — so a
    ///         legacy credit can never out-run the reserve backing it (Invariant R
    ///         holds by construction, not by the reserve's slack). Anyone (a keeper,
    ///         the frontend) can call it; cheap + safe to call with nothing pending.
    function materializeLegacyReserve() external nonReentrant returns (uint256 added) {
        if (!summoned) revert NotSummoned();
        uint256 g = currentGeneration;
        uint256 og;
        (added, og) = PoolOps.materializeLegacy(
            IPositionManagerOps(address(positionManager)), address(hook), address(this),
            address(collectionLedger), mifrens, genesisShares, g, generationCollection[g],
            generationToken[g],
            ReserveRef(generationReservePositionId[g], generationPoolKey[g], reserveTickLower[g], reserveTickUpper[g]),
            true
        );
        genesisPending += og;
        if (added > 0) emit LegacyMaterialized(g, added);
    }

    /// @dev Pull `amount` current token from `from`, add it to the out-of-range
    ///      reserve LP, and credit the reserve accounting → the floor ratchets up.
    ///      Returns the amount actually added.
    function _pullGrow(address from, uint256 amount) private returns (uint256 added) {
        uint256 g = currentGeneration;
        if (!IERC20(generationToken[g]).transferFrom(from, address(this), amount)) revert NoBalance();
        added = PoolOps.addToReserve(
            IPositionManagerOps(address(positionManager)),
            generationReservePositionId[g], generationPoolKey[g],
            reserveTickLower[g], reserveTickUpper[g], amount
        );
        // PAY-FOR-NOTHING GUARD (audit F-07). `addToReserve` returns 0 — WITHOUT
        // reverting — whenever the amount maps to zero liquidity units in the reserve
        // band (`ReserveLib.liquidityForTokenOut` rounds down) or the generation has
        // no reserve position at all (the `_seedReserve` dust guard leaves
        // `generationReservePositionId[g] == 0`). The caller's tokens have already
        // been pulled in by then, so the old code kept the payment, grew the floor by
        // nothing, and — in `buyTreasuryOgFren` — still handed over the fren. Revert
        // instead: a donation that cannot reach the reserve must not be collected.
        if (added == 0) revert NoBalance();
        genesisReserveOutstanding += added;
        emit FloorGrew(added, genesisReserveOutstanding, floorPerFren());
    }

    // -----------------------------------------------------------------------
    // QUOTE ROTATION -- the guild manages what the LP is denominated in
    // -----------------------------------------------------------------------

    /**
     * @notice Move ONE slice of liquidity from the live pair into another quote,
     *         end to end, in a single transaction.
     *
     *  Remove a chunk -> swap it -> redeploy it. Liquidity is out of the market
     *  only for the few opcodes between those three steps, never between
     *  transactions.
     *
     *  THIS REPLACED A TWO-PHASE DESIGN and the reason matters. That version
     *  pulled the whole rotation (say 30% of the pool) out in one call, parked
     *  it in the rotator, and converted it over hours. For those hours nearly a
     *  third of the pool's depth simply was not there: every trader ate worse
     *  execution, the price moved further on the same flow, and the protocol
     *  earned nothing on the idle balance. Slicing the WHOLE cycle instead of
     *  just the swap keeps the pool whole throughout.
     *
     *  Repeat this call to rotate further. Each one is independently bounded, so
     *  there is no long-lived pending state to unwind if the guild changes its
     *  mind — it simply stops calling.
     *
     * @param sliceBps  share of CURRENT liquidity to move (capped below). The
     *        DESTINATION is not a parameter — it comes from the approved
     *        envelope, so a caller cannot redirect the treasury.
     * @param minOut    floor on the swap. A pumped route produces NO fill rather
     *        than a bad one, which is what makes announcing the destination safe.
     * @param route     the pool to trade through
     */
    /**
     * @notice Point the registry at its rotator and its treasury governor.
     *
     *  ── THE FORWARDER EXISTED; THIS DID NOT (red-team) ──────────────────
     *  `CauldronRegistry.setRotationWiring` has always been present as a thin
     *  `_forwardToExt()` stub, but this facet never implemented the function it
     *  forwards to, and the facet has no fallback. Every call therefore
     *  delegatecalled into a missing selector and reverted.
     *
     *  `quoteRotator` (CauldronBase slot 50) and `treasuryGovernor` (slot 51)
     *  were consequently written by NOTHING, anywhere in the codebase — declared
     *  and read, never assigned. Since {rotateSlice} reverts `NotConfigured`
     *  when either is zero, the entire treasury-rotation feature was unreachable
     *  on every deployment that has ever existed: the envelope vote, the
     *  slicing, the venue allowlist and the whole rotation UI sat behind a
     *  setter that could not be called. No deploy script could have fixed it.
     *
     *  Implemented HERE rather than in the registry because that is where the
     *  forwarder already points, and because the registry has 62 bytes of
     *  EIP-170 margin — the reason these ops live in a facet at all. Running
     *  under delegatecall, `address(this)` is the registry, so this writes the
     *  registry's own slots.
     *
     *  Owner-gated, and deliberately NOT one-shot: a rotator or governor that
     *  turns out to be broken must be replaceable, and the alternative — a
     *  frozen pointer to a contract nobody can fix — is the failure this whole
     *  finding is an instance of. Zero is rejected on both because a zero here
     *  silently disables rotation rather than announcing it.
     */
    /// @notice The registry has no rotator/governor wired: a DEPLOYMENT problem.
    error RotationNotWired();
    /// @notice Wired, but no live governance envelope: a GOVERNANCE state.
    error NoRotationApproved();

    function setRotationWiring(address rotator, address governor) external onlyOwner {
        if (rotator == address(0) || governor == address(0)) revert NotConfigured();
        quoteRotator = rotator;
        treasuryGovernor = governor;
        emit RotationWired(rotator, governor);
    }

    event RotationWired(address indexed rotator, address indexed governor);

    function rotateSlice(
        uint16 sliceBps,
        uint256 minOut,
        PoolKey calldata route
    ) external returns (uint256 moved, uint256 positionId) {
        return rotateSliceFrom(0, sliceBps, minOut, route);
    }

    /// @notice Rotate a slice out of a CHOSEN leg. `fromLeg` 0 is the primary
    ///         pool; 1..legCount are the rotated legs. See the note inside on why
    ///         this exists and how merging falls out of it.
    function rotateSliceFrom(
        uint8 fromLeg,
        uint16 sliceBps,
        uint256 minOut,
        PoolKey calldata route
    ) public returns (uint256 moved, uint256 positionId) {
        //  ── "NOT WIRED" AND "NOT APPROVED" ARE DIFFERENT PROBLEMS ──────────
        //  Both used to revert `NotConfigured`, which is how B-15 stayed hidden:
        //  a deployment whose rotation wiring was never set looked exactly like
        //  one simply waiting on a governance vote. The first needs a deploy fix
        //  and the second needs a vote, so an operator reading the revert has to
        //  be able to tell them apart.
        address rot = quoteRotator;
        if (rot == address(0)) revert RotationNotWired();

        //  PERMISSIONLESS, WITHIN WHAT THE GUILD APPROVED.
        //
        //  Not onlyOwner: an owner who can refuse to execute an approved
        //  rotation holds the same veto as one who can execute an unapproved
        //  one. The destination and the ceiling come from the vote, so a caller
        //  chooses only the timing — and `minOut` bounds what timing can cost.
        address gov = treasuryGovernor;
        if (gov == address(0)) revert RotationNotWired();
        (address toQuote, uint16 remaining) = ITreasuryGovernor(gov).allowance();
        //  Wired, but the guild has approved nothing (or the envelope expired /
        //  is spent). Distinct from `RotationNotWired` above: this one is fixed
        //  by a vote, not by a deployment.
        if (toQuote == address(0)) revert NoRotationApproved();
        if (sliceBps > remaining) revert BadConfig();        // envelope exhausted

        //  Re-checked even though the governor checked it twice: this is the
        //  last point before liquidity actually moves.
        if (!allowedQuote[toQuote]) revert NotConfigured();
        //  A slice is a SLICE. Capped well below the 50% removal limit so no
        //  single call can take a meaningful bite out of live depth, and so the
        //  swap it performs stays small enough not to move the route's price.
        if (sliceBps == 0 || sliceBps > MAX_SLICE_BPS) revert BadConfig();

        uint256 gen = currentGeneration;
        address token = generationToken[gen];

        //  ── WHICH LEG DOES THIS SLICE COME FROM? ───────────────────────────
        //  It was always the primary. That made the treasury one-directional:
        //  every rotation drained the ORIGINAL quote, so a guild could go
        //  ETH -> USDG but never USDG -> anything, never rebalance between two
        //  destinations, and never merge a split back together. Reaching
        //  50/30/20 meant successive bites of the original asset and nothing
        //  else was expressible.
        //
        //  `fromLeg` names the source: 0 is the primary (the previous, and still
        //  default, behaviour), and 1..n are the rotated legs in
        //  `generationLegs`. Merging needs no new verb — it is rotating one leg
        //  entirely into another leg's pair.
        address fromQuote;
        uint256 srcPositionId;
        PoolKey memory srcKey;
        if (fromLeg == 0) {
            fromQuote = generationQuote[gen];
            srcPositionId = generationPositionId[gen];
            srcKey = generationPoolKey[gen];
        } else {
            TreasuryLeg storage l = generationLegs[gen][fromLeg - 1];
            fromQuote = l.quote;
            srcPositionId = l.positionId;
            srcKey = l.key;
        }
        //  A leg cannot rotate into itself: it would remove liquidity, swap the
        //  pair against itself and put it back, burning the envelope and fees
        //  for no movement.
        if (fromQuote == toQuote) revert BadConfig();

        // 1. Take the slice out of the chosen pair. The position survives — this
        //    is a reallocation, not an exit.
        (uint256 quoteOut, uint256 tokenOut) = PoolOps.removePartial(
            IPositionManagerOps(address(positionManager)),
            srcPositionId,
            srcKey,
            token,
            fromQuote,
            sliceBps
        );
        if (quoteOut == 0 || tokenOut == 0) revert BadConfig();

        // 2. Convert the quote side. The token side is the same asset in either
        //    pair, so it needs no conversion and never leaves this contract.
        PoolOps.sendAsset(fromQuote, rot, quoteOut);
        moved = IQuoteRotator(rot).swapOnce(route, fromQuote, toQuote, quoteOut, minOut);
        IQuoteRotator(rot).withdraw(toQuote, address(this), moved);

        // 3. Redeploy immediately into the destination pair, opening it on the
        //    first slice and topping it up on every later one.
        PoolId poolId;
        (poolId, positionId) = PoolOps.openOrAddPair(
            poolManager,
            IPositionManagerOps(address(positionManager)),
            address(hook),
            token,
            toQuote,
            moved,
            tokenOut,
            TICK_SPACING,
            POOL_FEE
        );

        // Count the new pair toward this generation, or splitting liquidity
        // would read as the generation dying.
        IHookVolume(address(hook)).linkVolume(generationPoolId[gen], poolId);

        //  ── RECORD THE LEG, OR RELAUNCH CANNOT GIVE IT BACK ────────────────
        //  `positionId` used to be returned and dropped. Nothing stored it, so
        //  nothing could unwind it: `_removeLiquidity` recovers the primary, the
        //  reserve and the seeder's bands, and a rotated leg is none of those.
        //  A guild that voted half its treasury into a stable would have found
        //  that half still in the old pool after the rebirth, funding nothing.
        //
        //  Upsert by QUOTE rather than append: `openOrAddPair` tops up the same
        //  position on every later slice into the same pair, so appending would
        //  record the same id N times and unwind it N times at teardown.
        _recordLeg(gen, toQuote, positionId, route);
        // Booked AFTER the move succeeds, so a reverted slice does not burn
        // envelope the treasury never actually spent.
        ITreasuryGovernor(gov).consume(sliceBps);

        //  ── WHEN THE ROTATION FINISHES, THE GENERATION'S QUOTE MUST FOLLOW ──
        //  `generationQuote[gen]` was written in exactly ONE place in the whole
        //  tree — `CauldronRegistry.relaunch` (:917) — so a LIVE rotation moved
        //  the liquidity and left the recorded denomination pointing at the
        //  asset the pool no longer principally trades. Every downstream reader
        //  inherited that staleness; the perp engine is the one that matters,
        //  because `PerpEngine.quote` is adopted only in `syncGeneration`
        //  (:1017) and that refuses without a generation change (:977) — so
        //  nothing, privileged or not, could re-point it for the rest of the
        //  generation. It would have kept marking, funding and liquidating
        //  against the pool this rotation had been draining.
        //
        //  FLIPPED AT COMPLETION, NOT PER SLICE, for two reasons. A rotation is
        //  sliced, so mid-rotation the pool is genuinely SPLIT and neither asset
        //  is the honest answer. And `fromQuote` above is read from this same
        //  slot: flipping it early would make the next slice try to rotate the
        //  destination into itself.
        //
        //  `allowance()` returns address(0) once the envelope is exhausted (or
        //  expired), which is exactly "there are no more slices coming". A
        //  partial rotation that simply stops therefore leaves the quote alone,
        //  which is correct — 30% moved does not redenominate a generation.
        (address stillRotating,) = ITreasuryGovernor(gov).allowance();
        if (stillRotating == address(0)) {
            generationQuote[gen] = toQuote;
            emit GenerationRequoted(gen, fromQuote, toQuote);
        }

        emit SliceRotated(gen, fromQuote, toQuote, quoteOut, moved, sliceBps);
    }

    /// @notice The generation's recorded denomination changed because a live
    ///         rotation completed. Downstream readers (notably the perp engine,
    ///         via {PerpEngine.syncGeneration}) re-adopt from this.
    event LegOpened(uint256 indexed gen, address indexed quote, uint256 positionId);
    event LegRecovered(uint256 indexed gen, address indexed quote, uint256 quoteOut, uint256 tokenOut);
    event GenerationRequoted(uint256 indexed gen, address indexed from, address indexed to);

    /// @dev Ceiling on a single slice.
    ///
    ///  ── SIZED SO A FULL ROTATION FITS INSIDE ONE VOTE ───────────────────
    ///  This was 500 (5%), which made a complete de-risking rotation
    ///  impossible in any useful timeframe. Each slice removes its share of
    ///  what REMAINS, so the position decays geometrically: at 5% a slice, 59
    ///  calls are needed to get the source quote under 5% of where it started,
    ///  and at 8 slices per envelope that is 8 envelopes — roughly 80 days once
    ///  the 3-day vote and 7-day cooldown are counted. A treasury that votes to
    ///  move into a stable because it thinks the market is topping cannot wait
    ///  a quarter to act on it; by then the decision is about a different
    ///  market.
    ///
    ///  At 25% a slice the same 95% conversion is 11 calls, which fits in a
    ///  single envelope and completes within about a day of the vote clearing.
    ///
    ///  What did NOT change is the guard that actually protects holders:
    ///  {PoolOps.MAX_ROTATION_BPS} still caps any ONE call at 50% of the live
    ///  position, so no single transaction can empty the pair, and every slice
    ///  still carries its own `minOut`. This raises the CADENCE a governance
    ///  vote can achieve; it does not weaken the per-call floor.
    uint16 internal constant MAX_SLICE_BPS = 2500; // 25%

    event SliceRotated(
        uint256 indexed gen, address indexed from, address indexed to,
        uint256 quoteIn, uint256 quoteOut, uint16 sliceBps
    );

    event QuoteRotatorSet(address rotator);
    event RotationBegun(uint256 indexed gen, address indexed quote, uint256 amount, uint16 bps);

    /**
     * @notice Deploy converted proceeds as liquidity in the new pair, and tell
     *         the hook the pair belongs to this generation.
     *
     *  The return leg. Handles a FIRST rotation and a rotation BACK identically:
     *  {PoolOps.openOrAddPair} initializes a fresh pair or tops up a live one, so
     *  the guild can move into USDG and later move back into ETH without a
     *  different code path.
     *
     *  linkVolume is the part that must not be forgotten. Death is judged on 24h
     *  volume, and once liquidity is split the primary pool alone can fall under
     *  the threshold while the generation is healthy — relaunching something
     *  perfectly alive. Registering the sibling here is what makes the hook count
     *  the generation rather than one pool.
     *
     * @param quote       the pair's quote asset (already converted, held here)
     * @param quoteAmount how much of it to deploy
     * @param tokenAmount how much of the generation's token to pair with it
     */
    function completeRotation(address quote, uint256 quoteAmount, uint256 tokenAmount)
        external
        onlyOwner
        returns (uint256 positionId)
    {
        if (!allowedQuote[quote]) revert NotConfigured();
        uint256 gen = currentGeneration;

        PoolId poolId;
        (poolId, positionId) = PoolOps.openOrAddPair(
            poolManager,
            IPositionManagerOps(address(positionManager)),
            address(hook),
            generationToken[gen],
            quote,
            quoteAmount,
            tokenAmount,
            TICK_SPACING,
            POOL_FEE
        );

        // Count this pair's volume toward the generation, or splitting liquidity
        // would look like the generation dying.
        IHookVolume(address(hook)).linkVolume(generationPoolId[gen], poolId);

        emit RotationCompleted(gen, quote, poolId, quoteAmount, tokenAmount);
    }

    event RotationCompleted(
        uint256 indexed gen, address indexed quote, PoolId poolId, uint256 quoteAmount, uint256 tokenAmount
    );
    /// @notice Whether the genesis redemption floor is claimable at spot RIGHT NOW,
    ///         and the current per-fren floor. The reserve is a single-sided token
    ///         band placed BELOW the launch tick; it only pays pure token while spot
    ///         stays ABOVE the band's upper tick. If the token appreciates past its
    ///         ~69x ceiling (spot trades INTO the band), claims temporarily
    ///         short-deliver and revert (audit Y-01) — so the frontend should read
    ///         this and show "floor temporarily out of range during a pump" instead
    ///         of a bare revert. `floorPerFren()` keeps returning the advertised
    ///         value regardless; this is the reachability signal that pairs with it.
    ///
    ///  Lives on the FACET, reached through the registry's fallback, purely to
    ///  keep the registry under EIP-170. Callers see no difference.
    function floorClaimableNow() external view returns (bool claimable, uint256 perFren) {
        perFren = floorPerFren();
        uint256 g = currentGeneration;
        if (!summoned || perFren == 0) return (false, perFren);
        (, int24 tick,,) = StateLibrary.getSlot0(poolManager, generationPoolId[g]);
        claimable = tick > reserveTickUpper[g];
    }

    // -----------------------------------------------------------------------
    // TREASURY LEGS -- readers (see {CauldronBase.TreasuryLeg})
    // -----------------------------------------------------------------------

    /// @notice How many rotated legs a generation holds beyond its primary pool.
    function legCount(uint256 gen) external view returns (uint256) {
        return generationLegs[gen].length;
    }

    /// @notice Read one leg: its quote, its position id, and the pool it sits in.
    function legAt(uint256 gen, uint256 i)
        external
        view
        returns (address quote, uint256 positionId, PoolKey memory key)
    {
        TreasuryLeg storage l = generationLegs[gen][i];
        return (l.quote, l.positionId, l.key);
    }

    /// @dev Upsert a leg by quote. See the call site for why it is not an append.
    function _recordLeg(uint256 gen, address quote, uint256 positionId, PoolKey memory key) private {
        TreasuryLeg[] storage legs = generationLegs[gen];
        uint256 n = legs.length;
        for (uint256 i; i < n; ++i) {
            if (legs[i].quote == quote) { legs[i].positionId = positionId; return; }
        }
        legs.push(TreasuryLeg({quote: quote, positionId: positionId, key: key}));
        emit LegOpened(gen, quote, positionId);
    }

    /**
     * @notice Unwind every rotated leg of `gen` back to the registry.
     *
     *  Called by `CauldronRegistry._removeLiquidity` during relaunch, and safe to
     *  call directly afterwards for a generation whose rebirth predates this.
     *  Idempotent: legs are deleted as they are taken, so a second call recovers
     *  nothing rather than reverting.
     *
     *  BEST-EFFORT PER LEG, deliberately. One pair that cannot be unwound — a
     *  pool someone broke, a token that started reverting on transfer — must not
     *  block the rebirth and strand every OTHER leg with it. A failed leg stays
     *  recorded, so it can be retried once whatever broke is fixed.
     */
    function recoverLegs(uint256 gen) public returns (uint256 quoteOut, uint256 tokenOut) {
        TreasuryLeg[] storage legs = generationLegs[gen];
        address token = generationToken[gen];
        IPositionManagerOps pm = IPositionManagerOps(address(positionManager));

        uint256 i = legs.length;
        while (i > 0) {
            --i;
            TreasuryLeg memory l = legs[i];
            try PoolOps.removeAll(pm, l.positionId, l.key, token) returns (uint256 q, uint256 t) {
                quoteOut += q;
                tokenOut += t;
                legs[i] = legs[legs.length - 1];
                legs.pop();
                emit LegRecovered(gen, l.quote, q, t);
            } catch {
                // Left in place on purpose — see the note above.
            }
        }
    }

}
