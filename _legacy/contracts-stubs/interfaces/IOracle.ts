/**
 * IOracle — Oracle Interface for OP_NET (Bitcoin L1)
 *
 * Provides price feed data for NFT collateral valuation in the
 * MagicFrens Cauldron lending protocol.
 *
 * The oracle reports the floor price (or appraised value) of the NFT
 * collection in MIM-denominated terms, enabling the Cauldron to compute
 * loan-to-value ratios and determine liquidation eligibility.
 *
 * Design considerations for Bitcoin L1:
 *   - No native Chainlink or on-chain TWAP available on OP_NET.
 *   - Initial deployment uses an admin-set price (trusted oracle).
 *   - Future iterations may incorporate decentralized price feeds,
 *     Bitcoin-native attestation schemes, or multi-sig oracle committees.
 */

// TODO: Import OP_NET SDK base types when available
// import { Address, u256, Calldata, DeployableContract } from '@opnet/sdk';

/** Represents a Bitcoin address on OP_NET. */
type Address = string;

/** 256-bit unsigned integer for prices and timestamps. */
type u256 = u64; // TODO: Replace with proper u256 from OP_NET SDK

// =============================================================================
//  Data Structures
// =============================================================================

/**
 * Encapsulates a price data point with metadata.
 */
export class PriceData {
    /**
     * The price of one unit of NFT collateral denominated in MIM base units
     * (18 decimals). For example, if one NFT is worth 1000 MIM, this value
     * is 1000 * 10^18.
     */
    price: u256 = 0;

    /** Block number at which this price was recorded. */
    blockNumber: u64 = 0;

    /** The address that submitted this price update. */
    updatedBy: Address = '';
}

// =============================================================================
//  Interface
// =============================================================================

/**
 * Oracle interface for NFT collateral price feeds.
 *
 * All prices are denominated in MIM base units (18 decimals) per single
 * NFT unit. For fungible collateral extensions, this would represent
 * price per token.
 */
export interface IOracle {
    // =========================================================================
    //  Price Queries (read-only)
    // =========================================================================

    /**
     * Returns the current price of one unit of NFT collateral in MIM.
     *
     * This is the primary entry point used by the Cauldron to value
     * collateral for LTV calculations.
     *
     * @returns Price in MIM base units (18 decimals) per NFT
     *
     * Reverts if the price has never been set or is stale beyond
     * the staleness threshold.
     *
     * TODO: Implement staleness check using OP_NET block numbers
     */
    getPrice(): u256;

    /**
     * Returns the full PriceData struct including metadata.
     * @returns PriceData with price, block number, and updater address
     */
    getPriceData(): PriceData;

    /**
     * Returns the block number of the most recent price update.
     * @returns Block number (0 if never updated)
     */
    lastUpdate(): u64;

    /**
     * Returns whether the current price is considered fresh (not stale).
     *
     * A price is stale if more than `stalenessThreshold` blocks have
     * elapsed since the last update.
     *
     * @returns True if the price is fresh and usable
     *
     * TODO: Compare current block number against lastUpdate + stalenessThreshold
     */
    isFresh(): bool;

    // =========================================================================
    //  Price Updates
    // =========================================================================

    /**
     * Triggers a price update from an external data source.
     *
     * In the initial trusted-oracle model, this is equivalent to setPrice()
     * restricted to authorized updaters. In future decentralized models,
     * this may pull from an on-chain aggregation mechanism.
     *
     * Permissionless callers may invoke this to prompt a refresh; the
     * implementation decides whether to accept or ignore the call based
     * on the oracle model in use.
     *
     * Emits: PriceUpdated(newPrice, blockNumber, updater)
     *
     * TODO: Implement price source logic (trusted signer, multi-sig, etc.)
     */
    update(): void;

    // =========================================================================
    //  Admin Functions
    // =========================================================================

    /**
     * Directly sets the NFT collateral price. Admin-only.
     *
     * Restricted to the oracle owner or authorized price feeders.
     * Reverts if the caller is not authorized.
     *
     * @param price - New price in MIM base units (18 decimals) per NFT.
     *                Must be greater than zero.
     *
     * Emits: PriceUpdated(price, blockNumber, caller)
     *
     * TODO: Access control via OP_NET SDK — restrict to admin / authorized feeder
     * TODO: Optionally enforce max price deviation from previous price to prevent manipulation
     */
    setPrice(price: u256): void;

    /**
     * Transfers oracle admin ownership to a new address.
     *
     * @param newAdmin - Address of the new admin
     *
     * Emits: AdminTransferred(previousAdmin, newAdmin)
     *
     * TODO: Access control via OP_NET SDK — restrict to current admin
     */
    transferAdmin(newAdmin: Address): void;

    /**
     * Adds or removes an authorized price feeder address.
     *
     * @param feeder     - Address to authorize or deauthorize
     * @param authorized - True to grant feeder role, false to revoke
     *
     * Emits: FeederUpdated(feeder, authorized)
     *
     * TODO: Access control via OP_NET SDK — restrict to admin
     */
    setAuthorizedFeeder(feeder: Address, authorized: bool): void;

    // =========================================================================
    //  Configuration Queries
    // =========================================================================

    /**
     * Returns the current admin address.
     * @returns Admin address
     */
    admin(): Address;

    /**
     * Returns whether the given address is an authorized price feeder.
     * @param feeder - Address to check
     * @returns True if authorized
     */
    isAuthorizedFeeder(feeder: Address): bool;

    /**
     * Returns the staleness threshold in blocks.
     * If more than this many blocks pass without an update, the price
     * is considered stale and getPrice() will revert.
     *
     * @returns Number of blocks
     */
    stalenessThreshold(): u64;

    /**
     * Sets the staleness threshold. Admin-only.
     * @param blocks - New threshold in blocks
     *
     * TODO: Access control via OP_NET SDK — restrict to admin
     */
    setStalenessThreshold(blocks: u64): void;
}

// =============================================================================
//  Events
// =============================================================================

// TODO: Define events using OP_NET SDK event system
//
// @event PriceUpdated {
//     price:       u256;
//     blockNumber: u64;
//     updater:     Address;
// }
//
// @event AdminTransferred {
//     previousAdmin: Address;
//     newAdmin:      Address;
// }
//
// @event FeederUpdated {
//     feeder:     Address;
//     authorized: bool;
// }

// =============================================================================
//  Storage Layout (reference for implementations)
// =============================================================================

// TODO: Define storage pointers using OP_NET SDK
//
// Pointer CURRENT_PRICE:        u256
// Pointer LAST_UPDATE_BLOCK:    u64
// Pointer LAST_UPDATER:         Address
// Pointer ADMIN:                Address
// Pointer AUTHORIZED_FEEDERS:   Map<Address, bool>
// Pointer STALENESS_THRESHOLD:  u64     — default: e.g. 100 blocks
