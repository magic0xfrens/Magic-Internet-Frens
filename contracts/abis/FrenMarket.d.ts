import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the setNFTContract function call.
 */
export type SetNFTContract = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setFeeRecipient function call.
 */
export type SetFeeRecipient = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setFeeRecipientHash function call.
 */
export type SetFeeRecipientHash = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setFeeBps function call.
 */
export type SetFeeBps = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the listNFT function call.
 */
export type ListNFT = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the cancelListing function call.
 */
export type CancelListing = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the reserveBuy function call.
 */
export type ReserveBuy = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the claimReserved function call.
 */
export type ClaimReserved = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the cancelReservation function call.
 */
export type CancelReservation = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getListing function call.
 */
export type GetListing = CallResult<
    {
        seller: Address;
        priceSats: bigint;
        active: boolean;
        reservedBy: bigint;
        reserveExpiry: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getActiveListingCount function call.
 */
export type GetActiveListingCount = CallResult<
    {
        count: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getListingByIndex function call.
 */
export type GetListingByIndex = CallResult<
    {
        tokenId: bigint;
        seller: Address;
        priceSats: bigint;
        sellerAddrHi: bigint;
        sellerAddrLo: bigint;
        reservedBy: bigint;
        reserveExpiry: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getFeeBps function call.
 */
export type GetFeeBps = CallResult<
    {
        bps: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getBuyerFeeBps function call.
 */
export type GetBuyerFeeBps = CallResult<
    {
        feeBps: bigint;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// IFrenMarket
// ------------------------------------------------------------------
export interface IFrenMarket extends IOP_NETContract {
    setNFTContract(nftContract: Address): Promise<SetNFTContract>;
    setFeeRecipient(recipient: Address): Promise<SetFeeRecipient>;
    setFeeRecipientHash(hash: bigint): Promise<SetFeeRecipientHash>;
    setFeeBps(bps: bigint): Promise<SetFeeBps>;
    listNFT(
        tokenId: bigint,
        priceSats: bigint,
        sellerAddrHash: bigint,
        sellerAddrHi: bigint,
        sellerAddrLo: bigint,
    ): Promise<ListNFT>;
    cancelListing(tokenId: bigint): Promise<CancelListing>;
    reserveBuy(tokenId: bigint): Promise<ReserveBuy>;
    claimReserved(tokenId: bigint): Promise<ClaimReserved>;
    cancelReservation(tokenId: bigint): Promise<CancelReservation>;
    getListing(tokenId: bigint): Promise<GetListing>;
    getActiveListingCount(): Promise<GetActiveListingCount>;
    getListingByIndex(index: bigint): Promise<GetListingByIndex>;
    getFeeBps(): Promise<GetFeeBps>;
    getBuyerFeeBps(buyer: Address): Promise<GetBuyerFeeBps>;
}
