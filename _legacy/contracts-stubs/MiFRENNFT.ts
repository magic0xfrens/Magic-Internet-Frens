/**
 * MiFRENNFT.ts — MiFREN NFT (OP_721) for the Magic Internet Frens Protocol
 *
 * Name: "MiFREN"
 * Symbol: "MIFREN"
 * Max Supply: 10,000
 *
 * 4 Tiers with probability-based random assignment on mint:
 *   Bronze  (60%) — 0% fee discount, 0 grace blocks, 0.1 BTC max borrow
 *   Silver  (25%) — 10% fee discount, 1 grace block,  0.5 BTC max borrow
 *   Gold    (10%) — 25% fee discount, 2 grace blocks, 2 BTC max borrow
 *   Diamond  (5%) — 50% fee discount, 3 grace blocks, 10 BTC max borrow
 *
 * NFTs are locked (non-transferable) while a Cauldron position is open.
 * Revenue split: 70% treasury, 30% sFREN stakers.
 *
 * Follows the OP_721 token standard on OP_NET (Bitcoin L1).
 */

// TODO: OP_NET SDK — import base contract and decorators
// e.g.: import { OP721, Address, u256, Mapping, Blockchain, Events, Revert } from "@opnet/runtime";

// ============================================================================
// Constants
// ============================================================================

const NFT_NAME: string = "MiFREN";
const NFT_SYMBOL: string = "MIFREN";
const MAX_SUPPLY: u32 = 10_000;

// Tier probability thresholds (cumulative, out of 10000 basis points)
const TIER_BRONZE_THRESHOLD: u32 = 6000;  // 0–5999     = 60%
const TIER_SILVER_THRESHOLD: u32 = 8500;  // 6000–8499  = 25%
const TIER_GOLD_THRESHOLD: u32 = 9500;    // 8500–9499  = 10%
// 9500–9999 = Diamond = 5%

// Revenue split basis points (out of 10000)
const TREASURY_SHARE_BPS: u32 = 7000;  // 70%
const STAKER_SHARE_BPS: u32 = 3000;    // 30%

// ============================================================================
// Enums & Data Structures
// ============================================================================

/**
 * NFT Tier enum.
 * Encoded as u8 for compact on-chain storage.
 */
enum Tier {
    Bronze = 0,
    Silver = 1,
    Gold = 2,
    Diamond = 3,
}

/**
 * Benefits associated with each tier.
 */
class TierBenefits {
    /** Fee discount in basis points (0, 1000, 2500, 5000) */
    feeDiscountBps: u32;
    /** Extra blocks before liquidation kicks in */
    liquidationGraceBlocks: u32;
    /** Maximum BTC that can be borrowed (in satoshis for precision) */
    maxBorrowSats: u64;

    constructor(feeDiscountBps: u32, liquidationGraceBlocks: u32, maxBorrowSats: u64) {
        this.feeDiscountBps = feeDiscountBps;
        this.liquidationGraceBlocks = liquidationGraceBlocks;
        this.maxBorrowSats = maxBorrowSats;
    }
}

// Pre-computed tier benefits lookup
// BTC amounts in satoshis: 0.1 BTC = 10_000_000, 0.5 BTC = 50_000_000,
//                          2 BTC = 200_000_000, 10 BTC = 1_000_000_000
function getTierBenefits(tier: Tier): TierBenefits {
    switch (tier) {
        case Tier.Bronze:
            return new TierBenefits(0, 0, 10_000_000);
        case Tier.Silver:
            return new TierBenefits(1000, 1, 50_000_000);
        case Tier.Gold:
            return new TierBenefits(2500, 2, 200_000_000);
        case Tier.Diamond:
            return new TierBenefits(5000, 3, 1_000_000_000);
        default:
            return new TierBenefits(0, 0, 10_000_000);
    }
}

/**
 * Returns a human-readable string name for a tier.
 */
function tierToString(tier: Tier): string {
    switch (tier) {
        case Tier.Bronze:  return "Bronze";
        case Tier.Silver:  return "Silver";
        case Tier.Gold:    return "Gold";
        case Tier.Diamond: return "Diamond";
        default:           return "Unknown";
    }
}

// ============================================================================
// Events
// ============================================================================

/**
 * TODO: OP_NET SDK — define events using the platform's event system.
 *
 * - Transfer(from, to, tokenId)
 * - Approval(owner, approved, tokenId)
 * - ApprovalForAll(owner, operator, approved)
 * - Minted(owner, tokenId, tier)
 * - NFTLocked(tokenId, lockedBy)
 * - NFTUnlocked(tokenId, unlockedBy)
 * - RevenueDistributed(totalAmount, treasuryAmount, stakerAmount)
 */

// ============================================================================
// Contract: MiFRENNFT
// ============================================================================

// TODO: OP_NET SDK — extend the base OP_721 contract class
// export class MiFRENNFT extends OP721 {

export class MiFRENNFT {

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /** Contract deployer / admin */
    private owner: string = ""; // TODO: OP_NET SDK — Address type

    /** Next token ID to mint (0-indexed, so first mint is tokenId 0) */
    private nextTokenId: u32 = 0;

    /** Token ownership: tokenId -> owner address */
    // TODO: OP_NET SDK — Mapping<u256, Address>
    private owners: Map<u32, string> = new Map();

    /** Owner balances: address -> number of NFTs owned */
    // TODO: OP_NET SDK — Mapping<Address, u256>
    private balanceCounts: Map<string, u32> = new Map();

    /** Token approvals: tokenId -> approved address */
    // TODO: OP_NET SDK — Mapping<u256, Address>
    private tokenApprovals: Map<u32, string> = new Map();

    /** Operator approvals: owner -> (operator -> approved) */
    // TODO: OP_NET SDK — Mapping<Address, Mapping<Address, bool>>
    private operatorApprovals: Map<string, Map<string, bool>> = new Map();

    /** Tier assignment: tokenId -> Tier */
    // TODO: OP_NET SDK — Mapping<u256, u8>
    private tokenTiers: Map<u32, Tier> = new Map();

    /** Lock status: tokenId -> is locked (non-transferable while Cauldron position open) */
    // TODO: OP_NET SDK — Mapping<u256, bool>
    private lockedTokens: Map<u32, bool> = new Map();

    /** Whitelisted Cauldron contracts that can lock/unlock NFTs */
    // TODO: OP_NET SDK — Mapping<Address, bool>
    private cauldronContracts: Map<string, bool> = new Map();

    /** Treasury address for revenue distribution */
    private treasuryAddress: string = ""; // TODO: OP_NET SDK — Address type

    /** sFREN staking contract address for revenue distribution */
    private sfrenStakingAddress: string = ""; // TODO: OP_NET SDK — Address type

    /** Mint price in satoshis */
    private mintPriceSats: u64 = 0; // TODO: OP_NET SDK — set via owner or constructor

    /** Nonce for pseudo-random tier assignment (supplemented by block data) */
    private randomNonce: u64 = 0;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor() {
        // TODO: OP_NET SDK — this.owner = Blockchain.msgSender();
        // TODO: OP_NET SDK — initialize persistent storage
    }

    // -----------------------------------------------------------------------
    // OP_721 Metadata (view)
    // -----------------------------------------------------------------------

    public name(): string {
        return NFT_NAME;
    }

    public symbol(): string {
        return NFT_SYMBOL;
    }

    public getMaxSupply(): u32 {
        return MAX_SUPPLY;
    }

    public totalMinted(): u32 {
        return this.nextTokenId;
    }

    // -----------------------------------------------------------------------
    // OP_721 Core Methods
    // -----------------------------------------------------------------------

    /**
     * Returns the owner of `tokenId`.
     */
    public ownerOf(tokenId: u32): string {
        assert(this.owners.has(tokenId), "MIFREN: token does not exist");
        return this.owners.get(tokenId);
    }

    /**
     * Returns the number of NFTs owned by `account`.
     */
    public balanceOf(account: string): u32 {
        assert(account != "", "MIFREN: balance query for zero address");
        if (this.balanceCounts.has(account)) {
            return this.balanceCounts.get(account);
        }
        return 0;
    }

    /**
     * Returns the approved address for `tokenId`, or empty string if none.
     */
    public getApproved(tokenId: u32): string {
        assert(this.owners.has(tokenId), "MIFREN: token does not exist");
        if (this.tokenApprovals.has(tokenId)) {
            return this.tokenApprovals.get(tokenId);
        }
        return "";
    }

    /**
     * Returns true if `operator` is approved to manage all of `owner`'s tokens.
     */
    public isApprovedForAll(owner: string, operator: string): bool {
        if (this.operatorApprovals.has(owner)) {
            const operators = this.operatorApprovals.get(owner);
            if (operators.has(operator)) {
                return operators.get(operator);
            }
        }
        return false;
    }

    /**
     * Approves `to` to manage `tokenId`. Caller must be owner or approved operator.
     */
    public approve(to: string, tokenId: u32): void {
        const tokenOwner = this.ownerOf(tokenId);
        assert(to != tokenOwner, "MIFREN: approval to current owner");

        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder
        assert(
            caller == tokenOwner || this.isApprovedForAll(tokenOwner, caller),
            "MIFREN: caller is not owner nor approved for all"
        );

        this.tokenApprovals.set(tokenId, to);
        // TODO: OP_NET SDK — Events.emit("Approval", [tokenOwner, to, tokenId]);
    }

    /**
     * Sets or revokes `operator` as an approved operator for the caller.
     */
    public setApprovalForAll(operator: string, approved: bool): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder
        assert(operator != caller, "MIFREN: approve to caller");

        if (!this.operatorApprovals.has(caller)) {
            this.operatorApprovals.set(caller, new Map<string, bool>());
        }
        const operators = this.operatorApprovals.get(caller);
        operators.set(operator, approved);

        // TODO: OP_NET SDK — Events.emit("ApprovalForAll", [caller, operator, approved]);
    }

    /**
     * Transfers `tokenId` from `from` to `to`.
     * Caller must be owner, approved, or operator.
     * Token must NOT be locked.
     */
    public transferFrom(from: string, to: string, tokenId: u32): void {
        assert(this._isApprovedOrOwner(tokenId), "MIFREN: caller not authorized");
        assert(!this._isLocked(tokenId), "MIFREN: token is locked (active Cauldron position)");

        this._transfer(from, to, tokenId);
    }

    // -----------------------------------------------------------------------
    // Minting (payable in BTC)
    // -----------------------------------------------------------------------

    /**
     * Mints a new MiFREN NFT to the caller. Payment in BTC is required.
     * A random tier is assigned based on the defined probability distribution.
     *
     * Revenue is split: 70% treasury, 30% sFREN stakers.
     */
    public mint(): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder
        // TODO: OP_NET SDK — const btcSent = Blockchain.msgValue(); // satoshis
        const btcSent: u64 = 0; // placeholder

        assert(this.nextTokenId < MAX_SUPPLY, "MIFREN: max supply reached");
        assert(btcSent >= this.mintPriceSats, "MIFREN: insufficient BTC payment");

        // Assign a random tier
        const tier = this._assignRandomTier();

        // Mint the token
        const tokenId = this.nextTokenId;
        this.nextTokenId++;

        this.owners.set(tokenId, caller);
        this.tokenTiers.set(tokenId, tier);
        this.lockedTokens.set(tokenId, false);

        const currentBalance = this.balanceOf(caller);
        this.balanceCounts.set(caller, currentBalance + 1);

        // Distribute revenue
        this._distributeRevenue(btcSent);

        // TODO: OP_NET SDK — Events.emit("Transfer", [Address.zero(), caller, tokenId]);
        // TODO: OP_NET SDK — Events.emit("Minted", [caller, tokenId, tier]);
    }

    // -----------------------------------------------------------------------
    // Tier Queries
    // -----------------------------------------------------------------------

    /**
     * Returns the tier of `tokenId` as a Tier enum value (0=Bronze, 1=Silver, 2=Gold, 3=Diamond).
     */
    public getTier(tokenId: u32): Tier {
        assert(this.owners.has(tokenId), "MIFREN: token does not exist");
        return this.tokenTiers.get(tokenId);
    }

    /**
     * Returns the tier name as a string.
     */
    public getTierName(tokenId: u32): string {
        return tierToString(this.getTier(tokenId));
    }

    /**
     * Returns the full benefits struct for a given tokenId.
     */
    public getTierBenefits(tokenId: u32): TierBenefits {
        return getTierBenefits(this.getTier(tokenId));
    }

    /**
     * Returns the fee discount in basis points for a given tokenId.
     */
    public getFeeDiscount(tokenId: u32): u32 {
        return getTierBenefits(this.getTier(tokenId)).feeDiscountBps;
    }

    /**
     * Returns the liquidation grace blocks for a given tokenId.
     */
    public getLiquidationGrace(tokenId: u32): u32 {
        return getTierBenefits(this.getTier(tokenId)).liquidationGraceBlocks;
    }

    /**
     * Returns the max borrow amount in satoshis for a given tokenId.
     */
    public getMaxBorrow(tokenId: u32): u64 {
        return getTierBenefits(this.getTier(tokenId)).maxBorrowSats;
    }

    // -----------------------------------------------------------------------
    // Holder Gate Check
    // -----------------------------------------------------------------------

    /**
     * Returns true if `account` holds at least one MiFREN NFT.
     * Used by the Cauldron as a gate check for enhanced features.
     */
    public isHolder(account: string): bool {
        return this.balanceOf(account) > 0;
    }

    // -----------------------------------------------------------------------
    // NFT Locking (Cauldron only)
    // -----------------------------------------------------------------------

    /**
     * Locks `tokenId`, making it non-transferable.
     * Called by a Cauldron contract when a borrowing position is opened.
     *
     * @param tokenId — the NFT to lock
     */
    public lockNFT(tokenId: u32): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder

        assert(
            this.cauldronContracts.has(caller) && this.cauldronContracts.get(caller),
            "MIFREN: caller is not an authorized Cauldron"
        );
        assert(this.owners.has(tokenId), "MIFREN: token does not exist");
        assert(!this._isLocked(tokenId), "MIFREN: token is already locked");

        this.lockedTokens.set(tokenId, true);

        // TODO: OP_NET SDK — Events.emit("NFTLocked", [tokenId, caller]);
    }

    /**
     * Unlocks `tokenId`, restoring transferability.
     * Called by a Cauldron contract when a borrowing position is closed.
     *
     * @param tokenId — the NFT to unlock
     */
    public unlockNFT(tokenId: u32): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder

        assert(
            this.cauldronContracts.has(caller) && this.cauldronContracts.get(caller),
            "MIFREN: caller is not an authorized Cauldron"
        );
        assert(this.owners.has(tokenId), "MIFREN: token does not exist");
        assert(this._isLocked(tokenId), "MIFREN: token is not locked");

        this.lockedTokens.set(tokenId, false);

        // TODO: OP_NET SDK — Events.emit("NFTUnlocked", [tokenId, caller]);
    }

    /**
     * Returns true if `tokenId` is currently locked.
     */
    public isLocked(tokenId: u32): bool {
        assert(this.owners.has(tokenId), "MIFREN: token does not exist");
        return this._isLocked(tokenId);
    }

    // -----------------------------------------------------------------------
    // Admin: Cauldron Whitelist (owner only)
    // -----------------------------------------------------------------------

    /**
     * Adds a Cauldron contract address to the whitelist (can lock/unlock NFTs).
     */
    public addCauldron(cauldron: string): void {
        this._onlyOwner();
        assert(cauldron != "", "MIFREN: cauldron is zero address");
        this.cauldronContracts.set(cauldron, true);
    }

    /**
     * Removes a Cauldron contract address from the whitelist.
     */
    public removeCauldron(cauldron: string): void {
        this._onlyOwner();
        assert(
            this.cauldronContracts.has(cauldron) && this.cauldronContracts.get(cauldron),
            "MIFREN: address is not a whitelisted Cauldron"
        );
        this.cauldronContracts.set(cauldron, false);
    }

    /**
     * Returns true if `account` is a whitelisted Cauldron contract.
     */
    public isCauldron(account: string): bool {
        return this.cauldronContracts.has(account) && this.cauldronContracts.get(account);
    }

    // -----------------------------------------------------------------------
    // Admin: Configuration (owner only)
    // -----------------------------------------------------------------------

    /**
     * Sets the mint price in satoshis.
     */
    public setMintPrice(priceSats: u64): void {
        this._onlyOwner();
        this.mintPriceSats = priceSats;
    }

    /**
     * Returns the current mint price in satoshis.
     */
    public getMintPrice(): u64 {
        return this.mintPriceSats;
    }

    /**
     * Sets the treasury address for revenue distribution.
     */
    public setTreasuryAddress(treasury: string): void {
        this._onlyOwner();
        assert(treasury != "", "MIFREN: treasury is zero address");
        this.treasuryAddress = treasury;
    }

    /**
     * Sets the sFREN staking contract address for revenue distribution.
     */
    public setSFRENStakingAddress(staking: string): void {
        this._onlyOwner();
        assert(staking != "", "MIFREN: staking address is zero");
        this.sfrenStakingAddress = staking;
    }

    // -----------------------------------------------------------------------
    // Owner Management
    // -----------------------------------------------------------------------

    public transferOwnership(newOwner: string): void {
        this._onlyOwner();
        assert(newOwner != "", "MIFREN: new owner is zero address");
        this.owner = newOwner;
    }

    public getOwner(): string {
        return this.owner;
    }

    // -----------------------------------------------------------------------
    // Internal: Random Tier Assignment
    // -----------------------------------------------------------------------

    /**
     * Assigns a random tier based on the probability distribution:
     *   Bronze:  60%
     *   Silver:  25%
     *   Gold:    10%
     *   Diamond:  5%
     *
     * Uses a pseudo-random number derived from block data and an incrementing nonce.
     * This is NOT cryptographically secure but is sufficient for on-chain NFT tier
     * assignment where the stakes are limited to cosmetic/utility differences.
     */
    private _assignRandomTier(): Tier {
        // TODO: OP_NET SDK — derive randomness from block data:
        //   const blockHash = Blockchain.previousBlockHash();
        //   const blockTimestamp = Blockchain.blockTimestamp();
        //   const blockNumber = Blockchain.blockNumber();
        //   const msgSender = Blockchain.msgSender();
        //
        //   Combine these inputs with a nonce and hash for pseudo-randomness:
        //   const seed = keccak256(abi.encodePacked(blockHash, blockTimestamp, msgSender, this.randomNonce));

        this.randomNonce++;

        // Generate a value in [0, 9999] from the seed
        // TODO: OP_NET SDK — const roll: u32 = u32(seed % 10000);
        const roll: u32 = <u32>(this.randomNonce % 10000); // placeholder deterministic

        if (roll < TIER_BRONZE_THRESHOLD) {
            return Tier.Bronze;
        } else if (roll < TIER_SILVER_THRESHOLD) {
            return Tier.Silver;
        } else if (roll < TIER_GOLD_THRESHOLD) {
            return Tier.Gold;
        } else {
            return Tier.Diamond;
        }
    }

    // -----------------------------------------------------------------------
    // Internal: Revenue Distribution
    // -----------------------------------------------------------------------

    /**
     * Splits mint revenue according to the protocol's defined ratio:
     *   70% to treasury
     *   30% to sFREN stakers
     *
     * @param totalSats — total BTC payment in satoshis
     */
    private _distributeRevenue(totalSats: u64): void {
        const treasuryAmount: u64 = (totalSats * TREASURY_SHARE_BPS) / 10000;
        const stakerAmount: u64 = totalSats - treasuryAmount; // remainder to stakers (avoids rounding dust)

        // TODO: OP_NET SDK — transfer BTC to treasury:
        //   if (this.treasuryAddress != Address.zero()) {
        //       Blockchain.transfer(this.treasuryAddress, treasuryAmount);
        //   }

        // TODO: OP_NET SDK — transfer BTC to sFREN staking contract:
        //   if (this.sfrenStakingAddress != Address.zero()) {
        //       Blockchain.transfer(this.sfrenStakingAddress, stakerAmount);
        //   }

        // TODO: OP_NET SDK — Events.emit("RevenueDistributed", [totalSats, treasuryAmount, stakerAmount]);
    }

    // -----------------------------------------------------------------------
    // Internal: Transfer Logic
    // -----------------------------------------------------------------------

    /**
     * Internal transfer. Updates ownership, balances, and clears approvals.
     */
    private _transfer(from: string, to: string, tokenId: u32): void {
        assert(this.ownerOf(tokenId) == from, "MIFREN: transfer from incorrect owner");
        assert(to != "", "MIFREN: transfer to zero address");

        // Clear previous approval
        this.tokenApprovals.delete(tokenId);

        // Update balances
        const fromBalance = this.balanceOf(from);
        this.balanceCounts.set(from, fromBalance - 1);
        const toBalance = this.balanceOf(to);
        this.balanceCounts.set(to, toBalance + 1);

        // Transfer ownership
        this.owners.set(tokenId, to);

        // TODO: OP_NET SDK — Events.emit("Transfer", [from, to, tokenId]);
    }

    /**
     * Returns true if the caller is the owner or an approved address for `tokenId`.
     */
    private _isApprovedOrOwner(tokenId: u32): bool {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder

        const tokenOwner = this.ownerOf(tokenId);
        return (
            caller == tokenOwner ||
            this.getApproved(tokenId) == caller ||
            this.isApprovedForAll(tokenOwner, caller)
        );
    }

    /**
     * Returns true if `tokenId` is locked.
     */
    private _isLocked(tokenId: u32): bool {
        if (this.lockedTokens.has(tokenId)) {
            return this.lockedTokens.get(tokenId);
        }
        return false;
    }

    /**
     * Reverts if the caller is not the contract owner.
     */
    private _onlyOwner(): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder
        assert(caller == this.owner, "MIFREN: caller is not the owner");
    }
}
