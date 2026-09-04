import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the getGeneration function call.
 */
export type GetGeneration = CallResult<
    {
        generation: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the mint function call.
 */
export type Mint = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the isAlive function call.
 */
export type IsAlive = CallResult<
    {
        alive: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setElderCircle function call.
 */
export type SetElderCircle = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the markDead function call.
 */
export type MarkDead = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setRouter function call.
 */
export type SetRouter = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setWbtc function call.
 */
export type SetWbtc = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setSwapThreshold function call.
 */
export type SetSwapThreshold = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getAccumulatedTax function call.
 */
export type GetAccumulatedTax = CallResult<
    {
        accumulated: bigint;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// ICauldronToken
// ------------------------------------------------------------------
export interface ICauldronToken extends IOP_NETContract {
    getGeneration(): Promise<GetGeneration>;
    mint(to: Address, amount: bigint): Promise<Mint>;
    isAlive(): Promise<IsAlive>;
    setElderCircle(elderCircle: Address): Promise<SetElderCircle>;
    markDead(): Promise<MarkDead>;
    setRouter(router: Address): Promise<SetRouter>;
    setWbtc(wbtc: Address): Promise<SetWbtc>;
    setSwapThreshold(threshold: bigint): Promise<SetSwapThreshold>;
    getAccumulatedTax(): Promise<GetAccumulatedTax>;
}
