// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {PoolOps, IPositionManagerOps, ReserveRef} from "./PoolOps.sol";
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

    /// @notice Point the registry at the contract that converts rotation
    ///         proceeds. Owner-only, read through the registry's own storage.
    function setQuoteRotator(address r) external onlyOwner {
        quoteRotator = r;
        emit QuoteRotatorSet(r);
    }

    /**
     * @notice Withdraw a measured share of the LIVE pair's liquidity and hand the
     *         quote side to the rotator to convert.
     *
     *  Step one of the fund-manager path. The TOKEN side deliberately stays with
     *  the registry: it is the same token in either pair, so there is nothing to
     *  convert and moving it would only add a hop and a custody boundary.
     *
     *  This does NOT create the destination pool. A rotation runs over hours in
     *  slices and the amount of new quote it yields is not known until it
     *  finishes, so committing to a pool price up front would mean guessing it.
     *  Seeding happens afterwards, against the amount actually received.
     *
     *  Lives in this facet rather than the registry purely for EIP-170 headroom;
     *  under delegatecall it runs on the registry's storage and custody, so the
     *  liquidity and the recovered assets never leave the registry's control.
     */
    function beginRotation(uint16 bps) external onlyOwner returns (uint256 quoteOut) {
        address rot = quoteRotator;
        if (rot == address(0)) revert NotConfigured();

        uint256 gen = currentGeneration;
        address quote = generationQuote[gen];

        (quoteOut, ) = PoolOps.removePartial(
            IPositionManagerOps(address(positionManager)),
            generationPositionId[gen],
            generationPoolKey[gen],
            generationToken[gen],
            quote,
            bps
        );
        if (quoteOut > 0) PoolOps.sendAsset(quote, rot, quoteOut);
        emit RotationBegun(gen, quote, quoteOut, bps);
    }

    event QuoteRotatorSet(address rotator);
    event RotationBegun(uint256 indexed gen, address indexed quote, uint256 amount, uint16 bps);
}
