import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the checkin function call.
 */
export type Checkin = CallResult<
    {
        streak: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the claimRewards function call.
 */
export type ClaimRewards = CallResult<
    {
        amount: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the depositFees function call.
 */
export type DepositFees = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the notifyTransfer function call.
 */
export type NotifyTransfer = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setTokenAddress function call.
 */
export type SetTokenAddress = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setRegistryAddress function call.
 */
export type SetRegistryAddress = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the authorizeToken function call.
 */
export type AuthorizeToken = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the deauthorizeToken function call.
 */
export type DeauthorizeToken = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the authorizeDepositor function call.
 */
export type AuthorizeDepositor = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the deauthorizeDepositor function call.
 */
export type DeauthorizeDepositor = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getStreak function call.
 */
export type GetStreak = CallResult<
    {
        streak: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getPending function call.
 */
export type GetPending = CallResult<
    {
        pending: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getWeight function call.
 */
export type GetWeight = CallResult<
    {
        weight: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getTotalWeight function call.
 */
export type GetTotalWeight = CallResult<
    {
        totalWeight: bigint;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// IElderCircle
// ------------------------------------------------------------------
export interface IElderCircle extends IOP_NETContract {
    checkin(): Promise<Checkin>;
    claimRewards(): Promise<ClaimRewards>;
    depositFees(amount: bigint): Promise<DepositFees>;
    notifyTransfer(from: Address): Promise<NotifyTransfer>;
    setTokenAddress(token: Address): Promise<SetTokenAddress>;
    setRegistryAddress(registry: Address): Promise<SetRegistryAddress>;
    authorizeToken(token: Address): Promise<AuthorizeToken>;
    deauthorizeToken(token: Address): Promise<DeauthorizeToken>;
    authorizeDepositor(depositor: Address): Promise<AuthorizeDepositor>;
    deauthorizeDepositor(depositor: Address): Promise<DeauthorizeDepositor>;
    getStreak(holder: Address): Promise<GetStreak>;
    getPending(holder: Address): Promise<GetPending>;
    getWeight(holder: Address): Promise<GetWeight>;
    getTotalWeight(): Promise<GetTotalWeight>;
}
