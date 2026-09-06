// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {PoolOps, IPositionManagerOps, ReserveRef} from "./PoolOps.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
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
     * @param toQuote   destination asset; must be on the registry's allowlist
     * @param sliceBps  share of CURRENT liquidity to move (capped below)
     * @param minOut    floor on the swap, set from the market by the caller
     * @param route     the pool to trade through
     */
    function rotateSlice(
        address toQuote,
        uint16 sliceBps,
        uint256 minOut,
        PoolKey calldata route
    ) external onlyOwner returns (uint256 moved, uint256 positionId) {
        address rot = quoteRotator;
        if (rot == address(0)) revert NotConfigured();
        if (!allowedQuote[toQuote]) revert NotConfigured();
        //  A slice is a SLICE. Capped well below the 50% removal limit so no
        //  single call can take a meaningful bite out of live depth, and so the
        //  swap it performs stays small enough not to move the route's price.
        if (sliceBps == 0 || sliceBps > MAX_SLICE_BPS) revert BadConfig();

        uint256 gen = currentGeneration;
        address fromQuote = generationQuote[gen];
        address token = generationToken[gen];

        // 1. Take the slice out of the live pair. The position survives — this
        //    is a reallocation, not an exit.
        (uint256 quoteOut, uint256 tokenOut) = PoolOps.removePartial(
            IPositionManagerOps(address(positionManager)),
            generationPositionId[gen],
            generationPoolKey[gen],
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
        emit SliceRotated(gen, fromQuote, toQuote, quoteOut, moved, sliceBps);
    }

    /// @dev Ceiling on a single slice. Small on purpose: the point of slicing is
    ///      that no one call meaningfully thins the pool or moves the route.
    uint16 internal constant MAX_SLICE_BPS = 500; // 5%

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
}
