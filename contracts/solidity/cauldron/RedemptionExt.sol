// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {PoolOps, IPositionManagerOps, ReserveRef} from "./PoolOps.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CauldronBase, IMiFrensContinuable, IPerpSync} from "./CauldronBase.sol";

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
    function consume(uint16 bps, bool fromPrimary) external;
    /// Did the guild authorise moving the WHOLE position, and is that mandate
    /// spent? The only thing that may redenominate a generation (red-team R-04).
    function migrationMandateSpent() external view returns (bool);
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

    /// @dev Liquidity left in the primary position below which it counts as
    ///      DRAINED for the purpose of redenominating the generation. Not zero:
    ///      each `removeAll` leaves sub-wei rounding behind, and a generation
    ///      must not be held un-migrated by a rounding crumb. Absolute rather
    ///      than proportional on purpose — a proportional test would be a share
    ///      of a number the caller can shrink, which is the class of bug this
    ///      whole check exists to close.
    uint128 internal constant PRIMARY_DRAINED_DUST = 1_000;

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
        //
        //  ── THE REMAINDER IS THE FLAG, NOT THE DESTINATION (red-team R-03) ──
        //  This tested `toQuote == address(0)`, which is ALSO how a rotation back
        //  to native ether names where it is going. The sentinel for "nothing
        //  approved" was therefore identical to a legitimate destination, and the
        //  guild could pass and execute a vote to return to ETH only to watch
        //  every slice of it revert: rotation was ONE-WAY, so a treasury that
        //  moved into an ERC20 could never come home. `allowance` reports 0
        //  remaining for absent, expired AND spent envelopes alike, so the
        //  remainder answers the liveness question without overloading an address.
        if (remaining == 0) revert NoRotationApproved();
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
            srcPositionId = generationPositionId[gen];
            srcKey = generationPoolKey[gen];
            //  ── THE PRIMARY'S QUOTE IS ITS PAIR'S, NOT THE GENERATION'S ─────
            //  This read `generationQuote[gen]`, and the two DIVERGE the moment a
            //  migration completes: the flip below moves `generationQuote` to the
            //  destination while `generationPositionId`/`generationPoolKey` stay on
            //  the launch pair — they must, because the 69x redemption reserve is
            //  held under that same key (every
            //  `ReserveRef(generationReservePositionId[g], generationPoolKey[g], …)`).
            //
            //  So every later `fromLeg == 0` slice asked {PoolOps.removePartial} to
            //  measure the DESTINATION asset out of the LAUNCH pair. It settles the
            //  wrong currency, `quoteOut` comes back 0 and the call reverts
            //  `BadConfig()` — while a slice out of leg 1 succeeds in the same block
            //  under the same envelope. Measured on the fork harness: after a
            //  completed ETH -> USDG migration the ~32% residual still sitting in
            //  the ETH pair could never be rotated again, for the life of the
            //  generation, and only a relaunch recovered it.
            //
            //  `currency0` is the pair's own quote by construction — the watermark
            //  {PoolOps.openOrAddPair} asserts is `token > quote` — which is the
            //  same slot `recoverLegs` was already corrected to match on (:487).
            //  Before a migration the two are equal, so nothing changes for a fresh
            //  generation; after one, the primary stays addressable.
            fromQuote = Currency.unwrap(srcKey.currency0);
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
        //
        //  ── THE LEG MUST BE RECORDED WITH ITS OWN PAIR (red-team R-02) ──────
        //  This passed `route` — the VENUE the quote side was swapped through
        //  (fromQuote/toQuote, e.g. ETH/USDG) — not the pair the liquidity was
        //  actually deployed into (toQuote/token). `recoverLegs` hands that key
        //  straight to {PoolOps.removeAll}, which uses `key.currency0/currency1`
        //  to settle the position and to MEASURE what came back. With the venue
        //  key it settled the wrong two currencies, reverted inside the
        //  per-leg try/catch, and the leg stayed recorded but unrecovered —
        //  SILENTLY, because that catch exists to stop one bad leg blocking a
        //  rebirth. Measured consequence: after a completed rotation the registry
        //  held ZERO of the destination asset at relaunch, having "recovered"
        //  every leg. This is the pair {PoolOps.openOrAddPair} builds internally
        //  from the same four inputs; the watermark invariant it asserts
        //  (`token > quote`) is what fixes the currency order.
        _recordLeg(
            gen,
            toQuote,
            positionId,
            PoolKey({
                currency0: Currency.wrap(toQuote),
                currency1: Currency.wrap(token),
                fee: POOL_FEE,
                tickSpacing: TICK_SPACING,
                hooks: IHooks(address(hook))
            })
        );
        // Booked AFTER the move succeeds, so a reverted slice does not burn
        // envelope the treasury never actually spent.
        ITreasuryGovernor(gov).consume(sliceBps, fromLeg == 0);

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
        //  ── EXHAUSTION IS NOT COMPLETION (red-team R-04) ────────────────────
        //  This used to flip on `allowance() == address(0)` — "the envelope has
        //  nothing left" — and the comment here claimed that made a partial
        //  rotation safe: "30% moved does not redenominate a generation." That
        //  was WRONG, and measurably so. `allowance` reports nothing left the
        //  moment `movedBps >= maxTotalBps`, and `maxTotalBps` is the size of the
        //  MANDATE, not the size of the pair. A guild that voted "move at most
        //  25%" spent its envelope in ONE slice and redenominated the whole
        //  generation with ~76% of the liquidity still sitting in the old asset.
        //
        //  Two things went wrong downstream. The perp engine re-pointed onto the
        //  minority pool — the thin-pool mark this protocol already knows is
        //  dangerous (CauldronHook.sol:1500-1508) — and relaunch began reading
        //  the generation as denominated in an asset most of its liquidity was
        //  not in.
        //
        //  {TreasuryGovernor.migrationMandateSpent} asks the question this line
        //  actually needs: did the guild authorise moving the WHOLE position, and
        //  is that authority now spent? A budget smaller than the position is
        //  partial by construction and leaves the denomination alone.
        //
        //  ── AND THE BPS MUST BE A SHARE OF THE THING BEING MIGRATED ────────
        //  Intent-plus-exhaustion is an ACCOUNTING test, and this line has now
        //  been wrong twice for the same underlying reason: bps are counted,
        //  and nothing checks what they were a share OF. `consume` books
        //  `movedBps += bps` blind, while `rotateSliceFrom` lets a
        //  PERMISSIONLESS caller pick which leg they come out of. So a stranger
        //  could spend a whole 10,000-bps migration mandate 25 bps at a time out
        //  of a 0.1% dust leg and redenominate the generation with the primary
        //  pair bit-for-bit untouched — then, because `generationPoolKey` still
        //  names the OLD pair while `generationQuote` names the new one, every
        //  later `fromLeg == 0` slice measures in one asset and settles in
        //  another and reverts, freezing the real treasury for the generation.
        //
        //  A migration mandate is about the GENERATION'S POSITION, so only a
        //  slice taken OUT of that position may advance it. Secondary legs are
        //  still rotatable under the same envelope — that is rebalancing, and it
        //  is authorised — but it cannot be what declares the migration done.
        //  With this, `movedBps` is once again a sum of shares of one position,
        //  which is the unit `migrationMandateSpent` already assumes.
        //
        //  Note this deliberately does NOT try to make the flip a full-drain
        //  test. Slices take a share of CURRENT liquidity, so bps compound
        //  rather than sum and an exactly-10,000-bps budget converges on ~68%
        //  moved; demanding a drained position would make completion
        //  unreachable and the whole feature dead. The residual tail is a known,
        //  separately-tracked limitation, not this Critical.
        if (fromLeg == 0 && ITreasuryGovernor(gov).migrationMandateSpent()) {
            generationQuote[gen] = toQuote;

            //  ── RE-POINT THE PERP ENGINE IN THE SAME TRANSACTION ────────────
            //  `PerpEngine.quote` is assigned in exactly ONE place — inside
            //  {PerpEngine.syncGeneration} — and that refuses while any position
            //  is open (PerpEngine.sol:987). `forceCloseDead` / `forceCloseAllDead`
            //  both require the generation to be DEAD (:937, :950). So on a LIVE
            //  generation the engine can only be re-pointed while the book is
            //  empty, and nothing was doing it.
            //
            //  That left a real window. The moment this line flips the quote, the
            //  engine still marks against the pool this rotation just drained
            //  (`_key()` reads its own `quote` slot, PerpEngine.sol:450 — NOT
            //  `generationQuote`, despite what CauldronHook.sol:1499 claims). A
            //  trader opening in that window pins it there: `_guardOpen`
            //  (:1210-1214) checks warmup, death and leverage but never quote
            //  freshness, and once `openCount != 0` no reachable call can correct
            //  it until every position voluntarily closes. Marks, funding and
            //  in-swap liquidations would run off a thin pool that is cheap to
            //  push while the deep sibling sets the real price — exactly the
            //  hazard CauldronHook.sol:1504-1508 describes.
            //
            //  Doing it HERE is safe and needs no new guard: reaching this line
            //  required `linkVolume` to succeed earlier in this same call
            //  (:372), and that reverts `PerpsOpen()` unless `openCount == 0`
            //  (CauldronHook.sol:1518). So the book is provably empty right now,
            //  which is the one condition `syncGeneration` demands. No user can
            //  interleave an open — this is a single transaction.
            //
            //  Best-effort, mirroring `CauldronRegistry._perpHousekeep` (:1063):
            //  a broken or unset engine must never block a governance-approved
            //  rotation. If it does fail, the engine is merely stale — the same
            //  state as before this fix — and `syncGeneration` stays
            //  permissionless for a keeper to retry.
            address eng = address(hook) != address(0) ? hook.perpEngine() : address(0);
            if (eng != address(0)) { try IPerpSync(eng).syncGeneration() {} catch {} }

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

        //  ── ONE DENOMINATION PER SUM (functional audit R-04) ───────────────
        //  `quoteOut` is returned to `CauldronRegistry._removeLiquidity`, added
        //  to `ethRecovered` (:1558) and passed to {PoolOps.seedFunding} as an
        //  amount measured in THIS asset (`generationQuote[oldGen]`, Registry
        //  :922). So only legs actually denominated in it may be added to it.
        //
        //  Legs in any OTHER asset are still fully recovered — the position is
        //  unwound and the proceeds land in this registry exactly as before, so
        //  nothing is stranded that was not stranded already — but they are
        //  booked to `legProceeds` instead of being silently miscounted.
        //
        //  ── MATCH THE PRIMARY POOL, NOT THE RECORDED QUOTE (red-team R-02) ──
        //  This read `generationQuote[gen]`, which a completed rotation flips to
        //  the DESTINATION asset while `generationPositionId`/`generationPoolKey`
        //  keep pointing at the pair the generation launched in. (They must: the
        //  69x redemption reserve is held in that same key — see every
        //  `ReserveRef(generationReservePositionId[g], generationPoolKey[g], ...)`
        //  — so the primary cannot be re-pointed without breaking redemption.)
        //
        //  The sum this feeds is `ethRecovered` in
        //  `CauldronRegistry._removeLiquidity`, which is whatever the PRIMARY
        //  position returned. Matching on the flipped quote therefore added
        //  6-decimal USDG to 18-decimal wei in one integer, and the mixed
        //  magnitude was then requested as raw USDG at seeding —
        //  `TRANSFER_FROM_FAILED`, and a machine that could never be reborn.
        //  Matching on the primary's OWN currency0 keeps one denomination per sum.
        address matchQuote = Currency.unwrap(generationPoolKey[gen].currency0);

        uint256 i = legs.length;
        while (i > 0) {
            --i;
            TreasuryLeg memory l = legs[i];
            try PoolOps.removeAll(pm, l.positionId, l.key, token) returns (uint256 q, uint256 t) {
                //  The TOKEN side is the same asset for every leg (the dying
                //  generation's own token), so it always aggregates.
                tokenOut += t;
                if (l.quote == matchQuote) {
                    quoteOut += q;
                } else if (q > 0) {
                    legProceeds[l.quote] += q;
                    emit LegProceedsBooked(gen, l.quote, q);
                }
                legs[i] = legs[legs.length - 1];
                legs.pop();
                emit LegRecovered(gen, l.quote, q, t);
            } catch {
                // Left in place on purpose — see the note above.
            }
        }
    }

    /// @notice How much of `asset` is held from recovered rotation legs that did
    ///         not match their generation's quote. See {sweepLegProceeds}.
    function legProceedsOf(address asset) external view returns (uint256) {
        return legProceeds[asset];
    }

    /**
     * @notice Move booked foreign leg proceeds out to a sink.
     *
     *  ── WHY THIS IS NOT AUTOMATIC ──────────────────────────────────────────
     *  The obvious answer — "just add it back as liquidity" — is not available
     *  at the moment the proceeds appear. `recoverLegs` runs inside
     *  `_removeLiquidity` (Registry:785), which is TEARING DOWN every pool the
     *  dying generation had; and the NEW generation's quote is not chosen until
     *  {PoolOps.seedFunding} at Registry:921, ninety lines later, from a spec
     *  that is not even read until :830. There is no LP in existence that can
     *  accept a foreign asset at that instant.
     *
     *  Converting instead would need a swap, and therefore a price, inside the
     *  one path that must never be the reason the machine cannot be reborn —
     *  the trade {PoolOps.seedFunding} explicitly refuses to make (PoolOps.sol
     *  :1021-1029). So the proceeds are booked and moved deliberately, after the
     *  rebirth, by a call that cannot affect it.
     *
     *  WHERE IT SHOULD GO, in order of preference:
     *    1. Back into liquidity, when a LATER generation is denominated in this
     *       same asset — then it is ordinary funding and belongs in the pool.
     *       Reachable today by sweeping to the treasury and letting the normal
     *       seeding path use it.
     *    2. To the genesis holders, as a dividend in that asset. The basket is
     *       already multi-asset ({MiFrensDividend.fundToken}), but that function
     *       is `funder`-gated to the HOOK, so the registry cannot call it
     *       directly — wiring that route is a hook-side change, recommended and
     *       deliberately not forced in here.
     *
     *  Owner-gated because the destination is a policy choice, not a mechanical
     *  one, and because the amounts are small by construction (they exist only
     *  when a guild rotated into a second quote and then rebirthed).
     */
    function sweepLegProceeds(address asset, address to) external onlyOwner returns (uint256 amount) {
        if (to == address(0)) revert BadConfig();
        amount = legProceeds[asset];
        if (amount == 0) revert NoBalance();
        //  Cleared BEFORE the transfer: this is the registry's own balance and
        //  `to` is owner-chosen, so a re-entrant sweep must not be able to read
        //  the same booking twice.
        legProceeds[asset] = 0;
        PoolOps.sendAsset(asset, to, amount);
        emit LegProceedsSwept(asset, to, amount);
    }

    /// @notice A recovered leg's proceeds were in an asset other than its
    ///         generation's quote, so they were booked rather than counted
    ///         toward the rebirth's funding figure.
    event LegProceedsBooked(uint256 indexed gen, address indexed asset, uint256 amount);
    event LegProceedsSwept(address indexed asset, address indexed to, uint256 amount);

}
