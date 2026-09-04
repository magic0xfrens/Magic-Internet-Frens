// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title CollectionLedger
 * @notice The cap table for the eternal machine's PER-ITERATION collection floors.
 *
 *  Every volume collection (gacha/volume-minted NFTs of a brew) earns a token-
 *  denominated floor from the fees + royalties ITS OWN volume generated. Unlike the
 *  old model (an ETH vault that only crystallized at death), a collection is now
 *  redeemable **while alive**: fees/royalties market-buy the live token, credit the
 *  ledger, and a holder can recycle an NFT for its floor share at any time — NFT →
 *  treasury (not burned), resellable at 2× floor which RATCHETS the floor up. Death
 *  just FREEZES the mint count; nothing migrates because value already lives in the
 *  registry's single out-of-range reserve LP (shared with genesis + migration) and
 *  an entitlement is a pure NUMBER meaning "X of whatever token is live now".
 *
 *  ── Invariants (fuzz-tested) ─────────────────────────────────────────────────
 *    totalEntitled == Σ entitledTokens[gen]
 *  and the registry guarantees the reserve LP holds ≥ totalEntitled for legacy (on
 *  top of genesis + migration — "Invariant R"). Every op preserves it exactly.
 *
 *  ── Accumulator (per collection `gen`) ───────────────────────────────────────
 *    outstanding(gen) = supply(gen) − retired[gen]
 *      supply    = live ? collection.totalMinted() (passed in) : frozenSupply[gen]
 *      retired   = NFTs sitting in the treasury (redeem +1, buyback −1)
 *    floorPerNFT(gen) = entitledTokens[gen] / outstanding(gen)
 *    redeem:   entitled −= floor ; retired += 1   (others' floor UNCHANGED)
 *    buyback:  entitled += paid  ; retired −= 1   (floor RATCHETS up)
 *    credit:   entitled += tokens                 (floor grows for all)
 *  The registry passes `mintedNow = collection.totalMinted()` so `supply` tracks
 *  live mints without wiring the ledger into the mint path. `crystallize` snapshots
 *  it into `frozenSupply` so post-death reads need no external call.
 *
 *  Pure accounting: holds no tokens, makes no external calls. The registry is the
 *  sole caller and does every actual token move (claimFromReserve / addToReserve).
 */
contract CollectionLedger {
    /// @notice The Cauldron registry — the only address allowed to mutate the cap
    ///         table. It owns the reserve LP and performs the token moves.
    address public immutable registry;

    /// @notice generation => tokens this collection's outstanding NFTs may redeem
    ///         (denominated in the LIVE iteration token; migrates as a pure number).
    mapping(uint256 => uint256) public entitledTokens;
    /// @notice generation => NFTs currently in the treasury (recycled, not yet bought
    ///         back). outstanding = supply − retired. redeem +1, buyback −1.
    mapping(uint256 => uint256) public retired;
    /// @notice generation => mint count snapshotted at death. 0 while alive (the
    ///         registry passes the live count instead). After crystallize, reads
    ///         need no external call.
    mapping(uint256 => uint256) public frozenSupply;
    /// @notice generation => whether the brew has died and frozen its supply. Redeem
    ///         works BOTH before and after; this only switches the supply source.
    mapping(uint256 => bool) public crystallized;

    /// @notice Σ entitledTokens over every collection = the legacy claim on the
    ///         shared reserve. The registry sizes the reserve to cover this.
    uint256 public totalEntitled;

    event Crystallized(uint256 indexed gen, uint256 frozenSupply, uint256 entitled);
    event Credited(uint256 indexed gen, uint256 tokens, uint256 newEntitled);
    event Redeemed(uint256 indexed gen, uint256 payout, uint256 newFloor);
    event BoughtBack(uint256 indexed gen, uint256 paid, uint256 newFloor);

    error OnlyRegistry();
    error AlreadyCrystallized();
    error NothingOutstanding();
    error NothingRetired();
    error ZeroAmount();

    constructor(address _registry) {
        require(_registry != address(0), "registry");
        registry = _registry;
    }

    modifier onlyRegistry() {
        if (msg.sender != registry) revert OnlyRegistry();
        _;
    }

    // ── Views ────────────────────────────────────────────────────────────────

    /// @notice Live entitled-NFT count. `mintedNow` = collection.totalMinted() for a
    ///         live brew; ignored once crystallized (uses the frozen snapshot).
    function outstanding(uint256 gen, uint256 mintedNow) public view returns (uint256) {
        uint256 supply = crystallized[gen] ? frozenSupply[gen] : mintedNow;
        uint256 r = retired[gen];
        return supply > r ? supply - r : 0;
    }

    /// @notice Tokens one NFT of collection `gen` can redeem right now (in the live
    ///         token), given the live mint count. 0 if no entitled NFTs.
    function floorPerNFT(uint256 gen, uint256 mintedNow) public view returns (uint256) {
        uint256 n = outstanding(gen, mintedNow);
        if (n == 0) return 0;
        return entitledTokens[gen] / n;
    }

    // ── Registry-driven mutations (each preserves totalEntitled == Σ) ──────────

    /// @notice Add tokens to a collection's entitlement — the LIVE buyback (fee ETH
    ///         → token) and secondary-royalty inflow both route here via the
    ///         registry. Works before OR after death. Grows the floor for every
    ///         outstanding NFT.
    function credit(uint256 gen, uint256 tokens) external onlyRegistry {
        if (tokens == 0) revert ZeroAmount();
        entitledTokens[gen] += tokens;
        totalEntitled += tokens;
        emit Credited(gen, tokens, entitledTokens[gen]);
    }

    /// @notice Recycle one NFT of collection `gen`: return its floor payout and debit
    ///         the pot so every OTHER NFT's floor is unchanged; the NFT moves to the
    ///         treasury (retired += 1). The registry then pulls `payout` from the
    ///         reserve and moves the NFT. `mintedNow` sizes the live floor.
    function redeem(uint256 gen, uint256 mintedNow) external onlyRegistry returns (uint256 payout) {
        uint256 n = outstanding(gen, mintedNow);
        if (n == 0) revert NothingOutstanding();
        payout = entitledTokens[gen] / n; // round DOWN → Σ never drifts above reserve
        entitledTokens[gen] -= payout;
        retired[gen] += 1;
        totalEntitled -= payout;
        emit Redeemed(gen, payout, floorPerNFT(gen, mintedNow));
    }

    /// @notice Buy back a treasury-held NFT of collection `gen` for `paid` tokens
    ///         (the registry enforces paid == 2× floor + adds them to the reserve).
    ///         Credits the pot + un-retires the NFT → the floor ratchets up.
    function buyback(uint256 gen, uint256 mintedNow, uint256 paid) external onlyRegistry {
        if (paid == 0) revert ZeroAmount();
        if (retired[gen] == 0) revert NothingRetired();
        entitledTokens[gen] += paid;
        retired[gen] -= 1;
        totalEntitled += paid;
        emit BoughtBack(gen, paid, floorPerNFT(gen, mintedNow));
    }

    /// @notice Freeze a dead collection's supply so post-death reads need no external
    ///         call. Redemption already worked while alive; this only snapshots the
    ///         mint count and optionally folds a final `extraEntitled` (e.g. the last
    ///         fee/green-candle sizing) into the pot. One-time per generation.
    function crystallize(uint256 gen, uint256 mintedAtDeath, uint256 extraEntitled)
        external
        onlyRegistry
    {
        if (crystallized[gen]) revert AlreadyCrystallized();
        crystallized[gen] = true;
        frozenSupply[gen] = mintedAtDeath;
        if (extraEntitled != 0) {
            entitledTokens[gen] += extraEntitled;
            totalEntitled += extraEntitled;
        }
        emit Crystallized(gen, mintedAtDeath, entitledTokens[gen]);
    }
}
