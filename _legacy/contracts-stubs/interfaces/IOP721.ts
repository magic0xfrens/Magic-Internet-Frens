/**
 * IOP721 — Standard OP_721 Non-Fungible Token Interface for OP_NET (Bitcoin L1)
 *
 * Analogous to ERC-721 on Ethereum. Defines the standard interface for
 * non-fungible tokens deployed on the OP_NET smart contract layer.
 *
 * Used by MagicFrens for NFT collateral that backs lending positions
 * in the Cauldron contracts.
 */

// TODO: Import OP_NET SDK base types when available
// import { Address, u256, Calldata, DeployableContract } from '@opnet/sdk';

/** Represents a Bitcoin address on OP_NET. */
type Address = string;

/** 256-bit unsigned integer for token IDs and counts. */
type u256 = u64; // TODO: Replace with proper u256 from OP_NET SDK

/** Sentinel value representing the zero / null address. */
// TODO: const ADDRESS_ZERO: Address = ... (from OP_NET SDK)

/**
 * Standard OP_721 non-fungible token interface.
 *
 * Each token is identified by a unique `u256` tokenId. Tokens are
 * non-divisible — they cannot be split into fractional parts.
 */
export interface IOP721 {
    // =========================================================================
    //  Metadata
    // =========================================================================

    /**
     * Returns the human-readable name of the NFT collection.
     * @returns Collection name (e.g. "Magic Internet Frens")
     */
    name(): string;

    /**
     * Returns the ticker symbol of the NFT collection.
     * @returns Collection symbol (e.g. "MFRENS")
     */
    symbol(): string;

    /**
     * Returns a URI pointing to the metadata JSON for `tokenId`.
     * The metadata should conform to the OP_NET metadata standard.
     *
     * @param tokenId - The NFT token ID
     * @returns URI string (e.g. "ipfs://Qm.../1.json" or an on-chain data URI)
     */
    tokenURI(tokenId: u256): string;

    // =========================================================================
    //  Supply
    // =========================================================================

    /**
     * Returns the total number of NFTs currently in existence.
     * Burned tokens are not counted.
     * @returns Total supply count
     */
    totalSupply(): u256;

    // =========================================================================
    //  Ownership & Balance Queries
    // =========================================================================

    /**
     * Returns the owner of `tokenId`.
     * Reverts if the token does not exist (has been burned or was never minted).
     *
     * @param tokenId - The NFT token ID
     * @returns Owner address
     */
    ownerOf(tokenId: u256): Address;

    /**
     * Returns the number of NFTs held by `owner`.
     * @param owner - Address to query
     * @returns NFT count
     */
    balanceOf(owner: Address): u256;

    // =========================================================================
    //  Transfers
    // =========================================================================

    /**
     * Transfers `tokenId` from `from` to `to`.
     *
     * The caller must be:
     *   - the current owner, OR
     *   - an approved operator for the owner (via setApprovalForAll), OR
     *   - the specifically approved address for this tokenId (via approve).
     *
     * @param from    - Current owner of the token
     * @param to      - Recipient address (must not be ADDRESS_ZERO)
     * @param tokenId - The NFT token ID to transfer
     *
     * Emits: Transfer(from, to, tokenId)
     *
     * TODO: Consider adding safeTransferFrom with receiver callback
     *       once OP_NET supports cross-contract callback interfaces.
     */
    transferFrom(from: Address, to: Address, tokenId: u256): bool;

    // =========================================================================
    //  Single-Token Approval
    // =========================================================================

    /**
     * Approves `approved` to transfer `tokenId` on behalf of the owner.
     * Only one address can be approved per token at a time. Setting
     * `approved` to ADDRESS_ZERO clears the approval.
     *
     * The caller must be the current owner or an approved operator.
     *
     * @param approved - Address to approve (or ADDRESS_ZERO to revoke)
     * @param tokenId  - The NFT token ID
     *
     * Emits: Approval(owner, approved, tokenId)
     */
    approve(approved: Address, tokenId: u256): void;

    /**
     * Returns the address approved for `tokenId`, or ADDRESS_ZERO if none.
     * @param tokenId - The NFT token ID
     * @returns Approved address
     */
    getApproved(tokenId: u256): Address;

    // =========================================================================
    //  Operator Approval (collection-wide)
    // =========================================================================

    /**
     * Grants or revokes `operator` permission to transfer ALL of the
     * caller's NFTs.
     *
     * @param operator - Address to grant/revoke operator status
     * @param approved - True to grant, false to revoke
     *
     * Emits: ApprovalForAll(owner, operator, approved)
     */
    setApprovalForAll(operator: Address, approved: bool): void;

    /**
     * Returns whether `operator` is an approved operator for `owner`.
     * @param owner    - Token holder
     * @param operator - Potential operator
     * @returns True if `operator` is approved for all of `owner`'s tokens
     */
    isApprovedForAll(owner: Address, operator: Address): bool;
}

// =============================================================================
//  Events
// =============================================================================

// TODO: Define events using OP_NET SDK event system
//
// @event Transfer {
//     from:    Address;
//     to:      Address;
//     tokenId: u256;
// }
//
// @event Approval {
//     owner:    Address;
//     approved: Address;
//     tokenId:  u256;
// }
//
// @event ApprovalForAll {
//     owner:    Address;
//     operator: Address;
//     approved: bool;
// }

// =============================================================================
//  Storage Layout (reference for implementations)
// =============================================================================

// TODO: Define storage pointers using OP_NET SDK
//
// Pointer OWNERS:             Map<u256, Address>        — tokenId -> owner
// Pointer BALANCES:           Map<Address, u256>        — owner -> count
// Pointer TOKEN_APPROVALS:    Map<u256, Address>        — tokenId -> approved
// Pointer OPERATOR_APPROVALS: Map<Address, Map<Address, bool>> — owner -> operator -> bool
// Pointer TOKEN_URIS:         Map<u256, string>         — tokenId -> URI
// Pointer TOTAL_SUPPLY:       u256
