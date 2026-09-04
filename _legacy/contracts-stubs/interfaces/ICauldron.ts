/**
 * ICauldron — Cauldron Lending Market Interface for OP_NET (Bitcoin L1)
 *
 * The Cauldron is the core lending primitive of the MagicFrens protocol.
 * Users deposit NFT collateral, borrow MIM (Magic Internet Money) against
 * it, repay their debt, and withdraw collateral when their position is clear.
 *
 * Inspired by Abracadabra's Cauldron architecture, adapted for NFT-backed
 * lending on Bitcoin via OP_NET.
 *
 * Key concepts:
 *   - Each position is keyed by an NFT token ID (the collateral).
 *   - Interest accrues globally via `accrue()` and is tracked per-position.
 *   - `cook()` enables batched multi-action calls in a single transaction.
 *   - Liquidation is triggered when a position's LTV exceeds the threshold.
 */

// TODO: Import OP_NET SDK base types when available
// import { Address, u256, Calldata, DeployableContract } from '@opnet/sdk';

/** Represents a Bitcoin address on OP_NET. */
type Address = string;

/** 256-bit unsigned integer for amounts, IDs, and accumulators. */
type u256 = u64; // TODO: Replace with proper u256 from OP_NET SDK

/** Byte array for encoded action parameters in cook(). */
type Bytes = Uint8Array;

// =============================================================================
//  Data Structures
// =============================================================================

/**
 * Represents a single lending position backed by an NFT.
 */
export class Position {
    /** The OP_721 token ID used as collateral. */
    nftId: u256 = 0;

    /** Address of the borrower who owns this position. */
    borrower: Address = '';

    /** Principal amount of MIM borrowed (base units, 18 decimals). */
    borrowAmount: u256 = 0;

    /**
     * Snapshot of the global interest accumulator at last interaction.
     * Used to calculate accrued interest since the position was last touched.
     */
    lastAccruedIndex: u256 = 0;

    /** Block number at which the position was opened. */
    createdAtBlock: u64 = 0;
}

/**
 * Snapshot of overall protocol statistics.
 */
export class ProtocolStats {
    /** Total MIM borrowed across all positions (base units). */
    totalBorrowed: u256 = 0;

    /** Total number of active (open) positions. */
    activePositions: u64 = 0;

    /** Current annual interest rate in basis points (e.g. 500 = 5%). */
    interestRateBps: u64 = 0;

    /** Liquidation LTV threshold in basis points (e.g. 7500 = 75%). */
    liquidationThresholdBps: u64 = 0;

    /** Global interest accumulator — monotonically increasing. */
    accrualIndex: u256 = 0;

    /** Block number of last accrue() call. */
    lastAccrualBlock: u64 = 0;
}

/**
 * Action codes for the cook() batch function.
 */
export namespace CauldronAction {
    /** Deposit NFT collateral into the Cauldron. */
    export const DEPOSIT: u8 = 1;
    /** Borrow MIM against deposited collateral. */
    export const BORROW: u8 = 2;
    /** Repay outstanding MIM debt. */
    export const REPAY: u8 = 3;
    /** Withdraw NFT collateral (requires zero debt). */
    export const WITHDRAW: u8 = 4;
    /** Liquidate an under-collateralized position. */
    export const LIQUIDATE: u8 = 5;
}

// =============================================================================
//  Interface
// =============================================================================

/**
 * Cauldron lending market interface.
 *
 * All MIM amounts are in base units (18 decimals).
 * NFT IDs correspond to OP_721 token IDs.
 */
export interface ICauldron {
    // =========================================================================
    //  Core Lending Operations
    // =========================================================================

    /**
     * Deposits an NFT as collateral into the Cauldron.
     *
     * The caller must own the NFT and have approved the Cauldron contract
     * (via OP_721 approve or setApprovalForAll).
     *
     * @param nftId  - OP_721 token ID to deposit as collateral
     * @param amount - Reserved for future use (e.g. fractional collateral);
     *                 set to 0 for standard NFT deposit
     * @returns True if the deposit succeeded
     *
     * Emits: Deposit(caller, nftId)
     *
     * TODO: Transfer NFT from caller to Cauldron via OP_NET SDK cross-contract call
     */
    deposit(nftId: u256, amount: u256): bool;

    /**
     * Borrows MIM against deposited NFT collateral.
     *
     * The position's resulting LTV must remain below the liquidation threshold.
     * Automatically calls `accrue()` before calculating the borrow.
     *
     * @param nftId  - OP_721 token ID (must be deposited by caller)
     * @param amount - Amount of MIM to borrow (base units, 18 decimals)
     * @returns True if the borrow succeeded
     *
     * Emits: Borrow(caller, nftId, amount)
     *
     * TODO: Mint MIM to caller via IOP20.mint() cross-contract call
     * TODO: Query IOracle.getPrice() for collateral valuation
     */
    borrow(nftId: u256, amount: u256): bool;

    /**
     * Repays MIM debt on a position.
     *
     * The caller must have approved the Cauldron to spend their MIM tokens.
     * Automatically calls `accrue()` before calculating repayment.
     *
     * @param nftId  - OP_721 token ID identifying the position
     * @param amount - Amount of MIM to repay (base units). Use u256.MAX for full repayment.
     * @returns True if the repayment succeeded
     *
     * Emits: Repay(caller, nftId, amount)
     *
     * TODO: Burn repaid MIM via IOP20.burn() cross-contract call
     */
    repay(nftId: u256, amount: u256): bool;

    /**
     * Withdraws NFT collateral from the Cauldron.
     *
     * The position must have zero outstanding debt (borrow + accrued interest).
     * Only the original borrower (position owner) can withdraw.
     *
     * @param nftId  - OP_721 token ID to withdraw
     * @param amount - Reserved for future use; set to 0 for standard NFT withdrawal
     * @returns True if the withdrawal succeeded
     *
     * Emits: Withdraw(caller, nftId)
     *
     * TODO: Transfer NFT from Cauldron back to caller via OP_NET SDK
     */
    withdraw(nftId: u256, amount: u256): bool;

    /**
     * Liquidates an under-collateralized position.
     *
     * Anyone can call this when a position's LTV exceeds the liquidation
     * threshold. The liquidator repays the debt and receives the NFT collateral
     * (potentially at a discount defined by the liquidation incentive).
     *
     * Automatically calls `accrue()` before evaluating.
     *
     * @param nftId - OP_721 token ID of the position to liquidate
     * @returns True if the liquidation succeeded
     *
     * Emits: Liquidate(liquidator, borrower, nftId, debtRepaid)
     *
     * TODO: Query IOracle.getPrice() for current collateral valuation
     * TODO: Burn repaid MIM from liquidator via IOP20
     * TODO: Transfer NFT collateral to liquidator via IOP721
     */
    liquidate(nftId: u256): bool;

    // =========================================================================
    //  Batch Execution
    // =========================================================================

    /**
     * Executes multiple Cauldron actions in a single transaction.
     *
     * This is the primary gas-efficient entry point. Actions are executed
     * sequentially — each action can depend on the state changes of
     * preceding actions within the same cook() call.
     *
     * @param nftId   - OP_721 token ID (applies to all actions in this batch)
     * @param actions - Array of action codes (see CauldronAction namespace)
     * @param values  - Array of u256 amounts corresponding to each action
     * @param datas   - Array of encoded extra parameters for each action
     * @returns True if all actions succeeded
     *
     * Example — deposit + borrow in one call:
     *   cook(nftId, [DEPOSIT, BORROW], [0, borrowAmt], [[], []])
     *
     * TODO: Implement sequential action dispatch loop
     */
    cook(
        nftId: u256,
        actions: Array<u8>,
        values: Array<u256>,
        datas: Array<Bytes>,
    ): bool;

    // =========================================================================
    //  Interest Accrual
    // =========================================================================

    /**
     * Accrues interest globally across all positions.
     *
     * Updates the global accrual index based on blocks elapsed since the
     * last accrual. Should be called before any state-changing operation
     * (borrow, repay, liquidate) to ensure interest is up to date.
     *
     * Can be called by anyone (permissionless).
     *
     * Emits: Accrue(newAccrualIndex, interestAccrued, blockNumber)
     *
     * TODO: Compute compound interest using OP_NET block numbers
     */
    accrue(): void;

    // =========================================================================
    //  View Methods — Position Queries
    // =========================================================================

    /**
     * Returns the full position data for the given NFT collateral.
     * @param nftId - OP_721 token ID
     * @returns Position struct (zero-filled if no position exists)
     */
    getPosition(nftId: u256): Position;

    /**
     * Returns the total outstanding debt for a position, including
     * accrued interest up to the current block.
     *
     * @param nftId - OP_721 token ID
     * @returns Total debt in MIM base units (principal + interest)
     *
     * TODO: Calculate using global accrualIndex and position's lastAccruedIndex
     */
    getPositionDebt(nftId: u256): u256;

    /**
     * Returns the current loan-to-value ratio for a position in basis points.
     *
     * @param nftId - OP_721 token ID
     * @returns LTV in basis points (e.g. 5000 = 50%)
     *
     * TODO: Query IOracle.getPrice() for collateral value
     */
    getPositionLTV(nftId: u256): u256;

    /**
     * Checks whether a position is eligible for liquidation.
     * @param nftId - OP_721 token ID
     * @returns True if the position's LTV exceeds the liquidation threshold
     */
    isLiquidatable(nftId: u256): bool;

    /**
     * Returns all position NFT IDs for a given borrower address.
     * @param borrower - Address of the borrower
     * @returns Array of OP_721 token IDs
     *
     * TODO: Iterate storage using OP_NET SDK storage enumeration
     */
    getPositionsByBorrower(borrower: Address): Array<u256>;

    // =========================================================================
    //  View Methods — Protocol Statistics
    // =========================================================================

    /**
     * Returns a snapshot of aggregate protocol statistics.
     * @returns ProtocolStats struct
     */
    getProtocolStats(): ProtocolStats;

    /**
     * Returns the current collateralization ratio of the entire protocol
     * in basis points.
     *
     * @returns Protocol-wide collateral ratio (e.g. 15000 = 150%)
     *
     * TODO: Sum all collateral values via IOracle and compare to totalBorrowed
     */
    getProtocolCollateralRatio(): u256;

    /**
     * Returns the address of the oracle contract used for price feeds.
     * @returns Oracle contract address
     */
    oracle(): Address;

    /**
     * Returns the address of the MIM (OP_20) token contract.
     * @returns MIM token contract address
     */
    mimToken(): Address;

    /**
     * Returns the address of the NFT (OP_721) collateral contract.
     * @returns NFT collateral contract address
     */
    collateralToken(): Address;
}

// =============================================================================
//  Events
// =============================================================================

// TODO: Define events using OP_NET SDK event system
//
// @event Deposit {
//     caller: Address;
//     nftId:  u256;
// }
//
// @event Withdraw {
//     caller: Address;
//     nftId:  u256;
// }
//
// @event Borrow {
//     caller: Address;
//     nftId:  u256;
//     amount: u256;
// }
//
// @event Repay {
//     caller: Address;
//     nftId:  u256;
//     amount: u256;
// }
//
// @event Liquidate {
//     liquidator: Address;
//     borrower:   Address;
//     nftId:      u256;
//     debtRepaid: u256;
// }
//
// @event Accrue {
//     newAccrualIndex: u256;
//     interestAccrued: u256;
//     blockNumber:     u64;
// }

// =============================================================================
//  Storage Layout (reference for implementations)
// =============================================================================

// TODO: Define storage pointers using OP_NET SDK
//
// Pointer POSITIONS:               Map<u256, Position>      — nftId -> Position
// Pointer BORROWER_POSITIONS:      Map<Address, Array<u256>> — borrower -> nftIds
// Pointer TOTAL_BORROWED:          u256
// Pointer ACCRUAL_INDEX:           u256
// Pointer LAST_ACCRUAL_BLOCK:      u64
// Pointer INTEREST_RATE_BPS:       u64
// Pointer LIQUIDATION_THRESHOLD:   u64
// Pointer ORACLE_ADDRESS:          Address
// Pointer MIM_TOKEN_ADDRESS:       Address
// Pointer COLLATERAL_TOKEN_ADDRESS: Address
