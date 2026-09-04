import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the mintNFT function call.
 */
export type MintNFT = CallResult<
    {
        tokenId: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getTaxRate function call.
 */
export type GetTaxRate = CallResult<
    {
        taxRate: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getHolderTaxRate function call.
 */
export type GetHolderTaxRate = CallResult<
    {
        taxRate: bigint;
        bestClassIdx: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getMaxBorrow function call.
 */
export type GetMaxBorrow = CallResult<
    {
        maxBorrow: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getLiquidationGrace function call.
 */
export type GetLiquidationGrace = CallResult<
    {
        grace: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the lockNFT function call.
 */
export type LockNFT = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the unlockNFT function call.
 */
export type UnlockNFT = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the isLocked function call.
 */
export type IsLocked = CallResult<
    {
        locked: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the addCauldron function call.
 */
export type AddCauldron = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the removeCauldron function call.
 */
export type RemoveCauldron = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the isCauldron function call.
 */
export type IsCauldron = CallResult<
    {
        isCauldron: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the mintFor function call.
 */
export type MintFor = CallResult<
    {
        tokenId: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the reserveBatch function call.
 */
export type ReserveBatch = CallResult<
    {
        lastTokenId: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the totalMinted function call.
 */
export type TotalMinted = CallResult<
    {
        count: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getReserveInfo function call.
 */
export type GetReserveInfo = CallResult<
    {
        nextReserveIndex: bigint;
        totalReserved: bigint;
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
 * @description Represents the result of the setMintPrice function call.
 */
export type SetMintPrice = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getMintPrice function call.
 */
export type GetMintPrice = CallResult<
    {
        price: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getTreasury function call.
 */
export type GetTreasury = CallResult<
    {
        treasury: Address;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setCauldronRegistry function call.
 */
export type SetCauldronRegistry = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setFrenForge function call.
 */
export type SetFrenForge = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getFrenForge function call.
 */
export type GetFrenForge = CallResult<
    {
        forge: Address;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the markOGInscriber function call.
 */
export type MarkOGInscriber = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the isOGInscriber function call.
 */
export type IsOGInscriber = CallResult<
    {
        isOG: boolean;
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
 * @description Represents the result of the registerClass function call.
 */
export type RegisterClass = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the updateClass function call.
 */
export type UpdateClass = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getClassDef function call.
 */
export type GetClassDef = CallResult<
    {
        numBodies: bigint;
        numFaces: bigint;
        numItems: bigint;
        taxBPS: bigint;
        mintTier: bigint;
        enabled: bigint;
        mintable: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getNumClasses function call.
 */
export type GetNumClasses = CallResult<
    {
        count: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the transformToken function call.
 */
export type TransformToken = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setTokenTraits function call.
 */
export type SetTokenTraits = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setBatchTraits function call.
 */
export type SetBatchTraits = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getTokenTraits function call.
 */
export type GetTokenTraits = CallResult<
    {
        classIdx: bigint;
        bodyIdx: bigint;
        faceIdx: bigint;
        itemIdx: bigint;
        subitemIdx: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getTokenTraitKeys function call.
 */
export type GetTokenTraitKeys = CallResult<
    {
        bodyKey: bigint;
        faceKey: bigint;
        itemKey: bigint;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// IMiFrens
// ------------------------------------------------------------------
export interface IMiFrens extends IOP_NETContract {
    mintNFT(): Promise<MintNFT>;
    getTaxRate(tokenId: bigint): Promise<GetTaxRate>;
    getHolderTaxRate(holder: Address): Promise<GetHolderTaxRate>;
    getMaxBorrow(tokenId: bigint): Promise<GetMaxBorrow>;
    getLiquidationGrace(tokenId: bigint): Promise<GetLiquidationGrace>;
    lockNFT(tokenId: bigint): Promise<LockNFT>;
    unlockNFT(tokenId: bigint): Promise<UnlockNFT>;
    isLocked(tokenId: bigint): Promise<IsLocked>;
    addCauldron(cauldron: Address): Promise<AddCauldron>;
    removeCauldron(cauldron: Address): Promise<RemoveCauldron>;
    isCauldron(account: Address): Promise<IsCauldron>;
    mintFor(to: Address): Promise<MintFor>;
    reserveBatch(to: Address, count: bigint): Promise<ReserveBatch>;
    totalMinted(): Promise<TotalMinted>;
    getReserveInfo(): Promise<GetReserveInfo>;
    setTreasury(treasury: Address): Promise<SetTreasury>;
    setMintPrice(price: bigint): Promise<SetMintPrice>;
    getMintPrice(): Promise<GetMintPrice>;
    getTreasury(): Promise<GetTreasury>;
    setCauldronRegistry(registry: Address): Promise<SetCauldronRegistry>;
    setFrenForge(forge: Address): Promise<SetFrenForge>;
    getFrenForge(): Promise<GetFrenForge>;
    markOGInscriber(tokenId: bigint): Promise<MarkOGInscriber>;
    isOGInscriber(tokenId: bigint): Promise<IsOGInscriber>;
    tokenURI(tokenId: bigint): Promise<TokenURI>;
    registerClass(
        classIdx: bigint,
        numBodies: bigint,
        numFaces: bigint,
        numItems: bigint,
        taxBPS: bigint,
        mintTier: bigint,
    ): Promise<RegisterClass>;
    updateClass(
        classIdx: bigint,
        numBodies: bigint,
        numFaces: bigint,
        numItems: bigint,
        taxBPS: bigint,
        mintTier: bigint,
        enabled: bigint,
        mintable: bigint,
    ): Promise<UpdateClass>;
    getClassDef(classIdx: bigint): Promise<GetClassDef>;
    getNumClasses(): Promise<GetNumClasses>;
    transformToken(
        tokenId: bigint,
        newClassIdx: bigint,
        newBodyIdx: bigint,
        newFaceIdx: bigint,
        newItemIdx: bigint,
    ): Promise<TransformToken>;
    setTokenTraits(
        tokenId: bigint,
        classIdx: bigint,
        bodyIdx: bigint,
        faceIdx: bigint,
        itemIdx: bigint,
    ): Promise<SetTokenTraits>;
    setBatchTraits(startId: bigint, count: bigint): Promise<SetBatchTraits>;
    getTokenTraits(tokenId: bigint): Promise<GetTokenTraits>;
    getTokenTraitKeys(tokenId: bigint): Promise<GetTokenTraitKeys>;
}
