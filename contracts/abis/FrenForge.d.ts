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
 * @description Represents the result of the setMerkleRoot function call.
 */
export type SetMerkleRoot = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setArtAuthority function call.
 */
export type SetArtAuthority = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setTreasury function call.
 */
export type SetTreasury = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setTreasuryScriptHash function call.
 */
export type SetTreasuryScriptHash = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the batchInscribeAll function call.
 */
export type BatchInscribeAll = CallResult<
    {
        count: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the updateTraitImage function call.
 */
export type UpdateTraitImage = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the deleteTraitImage function call.
 */
export type DeleteTraitImage = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the inscribeTrait function call.
 */
export type InscribeTrait = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the mint function call.
 */
export type Mint = CallResult<
    {
        tokenId: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getArtAuthority function call.
 */
export type GetArtAuthority = CallResult<
    {
        authority: Address;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the isTraitInscribed function call.
 */
export type IsTraitInscribed = CallResult<
    {
        inscribed: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getTraitImage function call.
 */
export type GetTraitImage = CallResult<
    {
        data: Uint8Array;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getGlobalPalette function call.
 */
export type GetGlobalPalette = CallResult<
    {
        data: Uint8Array;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getInscriptionStats function call.
 */
export type GetInscriptionStats = CallResult<
    {
        totalInscribed: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the tokenURI function call.
 */
export type TokenURI = CallResult<
    {
        uri: string;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the renderTokenURI function call.
 */
export type RenderTokenURI = CallResult<
    {
        uri: string;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the tokenSvgURI function call.
 */
export type TokenSvgURI = CallResult<
    {
        totalParts: bigint;
        svgChunk: string;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// IFrenForge
// ------------------------------------------------------------------
export interface IFrenForge extends IOP_NETContract {
    setNFTContract(nftContract: Address): Promise<SetNFTContract>;
    setMerkleRoot(root: bigint): Promise<SetMerkleRoot>;
    setArtAuthority(authority: Address): Promise<SetArtAuthority>;
    setTreasury(treasury: Address): Promise<SetTreasury>;
    setTreasuryScriptHash(scriptHash: bigint): Promise<SetTreasuryScriptHash>;
    batchInscribeAll(data: Uint8Array): Promise<BatchInscribeAll>;
    updateTraitImage(traitKey: bigint, data: Uint8Array): Promise<UpdateTraitImage>;
    deleteTraitImage(traitKey: bigint): Promise<DeleteTraitImage>;
    inscribeTrait(traitKey: bigint, data: Uint8Array): Promise<InscribeTrait>;
    mint(traitKey: bigint, data: Uint8Array): Promise<Mint>;
    getArtAuthority(): Promise<GetArtAuthority>;
    isTraitInscribed(traitKey: bigint): Promise<IsTraitInscribed>;
    getTraitImage(traitKey: bigint): Promise<GetTraitImage>;
    getGlobalPalette(): Promise<GetGlobalPalette>;
    getInscriptionStats(): Promise<GetInscriptionStats>;
    tokenURI(tokenId: bigint): Promise<TokenURI>;
    renderTokenURI(
        tokenId: bigint,
        classIdx: bigint,
        bodyIdx: bigint,
        faceIdx: bigint,
        itemIdx: bigint,
        subitemIdx: bigint,
    ): Promise<RenderTokenURI>;
    tokenSvgURI(
        tokenId: bigint,
        part: bigint,
        classIdx: bigint,
        bodyIdx: bigint,
        faceIdx: bigint,
        itemIdx: bigint,
        subitemIdx: bigint,
    ): Promise<TokenSvgURI>;
}
