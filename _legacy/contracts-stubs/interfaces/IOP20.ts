/**
 * IOP20 — Standard OP_20 Fungible Token Interface for OP_NET (Bitcoin L1)
 *
 * Analogous to ERC-20 on Ethereum. Defines the standard interface for
 * fungible tokens deployed on the OP_NET smart contract layer.
 *
 * Protocol tokens (e.g. MIM, sMagic) extend this with mint/burn authority
 * restricted to authorized contracts (Cauldron, staking, etc.).
 */

// TODO: Import OP_NET SDK base types when available
// import { Address, u256, Calldata, DeployableContract } from '@opnet/sdk';

/** Represents a Bitcoin address on OP_NET. */
type Address = string;

/** 256-bit unsigned integer for token amounts and supplies. */
type u256 = u64; // TODO: Replace with proper u256 from OP_NET SDK

/**
 * Standard OP_20 fungible token interface.
 *
 * All amounts use the token's native decimal precision (e.g. 18 decimals
 * means 1 token = 1_000_000_000_000_000_000 base units).
 */
export interface IOP20 {
    // =========================================================================
    //  Metadata (read-only)
    // =========================================================================

    /**
     * Returns the human-readable name of the token.
     * @returns Token name (e.g. "Magic Internet Money")
     */
    name(): string;

    /**
     * Returns the ticker symbol of the token.
     * @returns Token symbol (e.g. "MIM")
     */
    symbol(): string;

    /**
     * Returns the number of decimal places the token uses.
     * @returns Decimals (typically 18 for OP_NET tokens)
     */
    decimals(): u8;

    // =========================================================================
    //  Supply
    // =========================================================================

    /**
     * Returns the total circulating supply of the token.
     * @returns Total supply in base units
     */
    totalSupply(): u256;

    // =========================================================================
    //  Balance & Allowance Queries
    // =========================================================================

    /**
     * Returns the token balance held by `owner`.
     * @param owner - Address to query
     * @returns Balance in base units
     */
    balanceOf(owner: Address): u256;

    /**
     * Returns the remaining amount that `spender` is allowed to transfer
     * on behalf of `owner` via `transferFrom`.
     * @param owner   - Token holder
     * @param spender - Approved spender
     * @returns Remaining allowance in base units
     */
    allowance(owner: Address, spender: Address): u256;

    // =========================================================================
    //  Transfers
    // =========================================================================

    /**
     * Transfers `amount` tokens from the caller to `to`.
     * @param to     - Recipient address
     * @param amount - Amount in base units
     * @returns True if the transfer succeeded
     *
     * Emits: Transfer(from, to, amount)
     */
    transfer(to: Address, amount: u256): bool;

    /**
     * Transfers `amount` tokens from `from` to `to`, consuming the caller's
     * allowance on `from`.
     * @param from   - Source address (must have sufficient allowance for caller)
     * @param to     - Recipient address
     * @param amount - Amount in base units
     * @returns True if the transfer succeeded
     *
     * Emits: Transfer(from, to, amount)
     */
    transferFrom(from: Address, to: Address, amount: u256): bool;

    // =========================================================================
    //  Approval
    // =========================================================================

    /**
     * Approves `spender` to transfer up to `amount` tokens on behalf of the caller.
     *
     * WARNING: Changing an allowance from non-zero to non-zero is vulnerable to
     * a front-running attack. Callers should set the allowance to 0 first, then
     * set the desired value.
     *
     * @param spender - Address authorized to spend
     * @param amount  - Maximum amount spender may transfer
     * @returns True if the approval succeeded
     *
     * Emits: Approval(owner, spender, amount)
     */
    approve(spender: Address, amount: u256): bool;

    // =========================================================================
    //  Mint / Burn Authority (Protocol-only)
    // =========================================================================

    /**
     * Mints `amount` new tokens to `to`. Increases totalSupply.
     *
     * Restricted to authorized protocol contracts (e.g. Cauldron, staking).
     * Reverts if the caller is not an authorized minter.
     *
     * @param to     - Recipient of minted tokens
     * @param amount - Amount to mint in base units
     * @returns True if the mint succeeded
     *
     * Emits: Transfer(ADDRESS_ZERO, to, amount)
     *
     * TODO: Access control via OP_NET SDK — restrict to authorized callers
     */
    mint(to: Address, amount: u256): bool;

    /**
     * Burns `amount` tokens from `from`. Decreases totalSupply.
     *
     * Restricted to authorized protocol contracts or the token holder.
     * If the caller is not `from`, an adequate allowance must exist.
     *
     * @param from   - Address whose tokens are burned
     * @param amount - Amount to burn in base units
     * @returns True if the burn succeeded
     *
     * Emits: Transfer(from, ADDRESS_ZERO, amount)
     *
     * TODO: Access control via OP_NET SDK — restrict to authorized callers
     */
    burn(from: Address, amount: u256): bool;
}

// =============================================================================
//  Events
// =============================================================================

// TODO: Define events using OP_NET SDK event system
//
// @event Transfer {
//     from:   Address;
//     to:     Address;
//     amount: u256;
// }
//
// @event Approval {
//     owner:   Address;
//     spender: Address;
//     amount:  u256;
// }

// =============================================================================
//  Storage Layout (reference for implementations)
// =============================================================================

// TODO: Define storage pointers using OP_NET SDK
//
// Pointer BALANCES:        Map<Address, u256>
// Pointer ALLOWANCES:      Map<Address, Map<Address, u256>>
// Pointer TOTAL_SUPPLY:    u256
// Pointer AUTHORIZED_MINTERS: Map<Address, bool>
