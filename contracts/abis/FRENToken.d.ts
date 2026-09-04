import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------
export type MintedEvent = {
    readonly to: Address;
    readonly amount: bigint;
};

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the _mintFREN function call.
 */
export type mintFREN = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<MintedEvent>[]
>;

/**
 * @description Represents the result of the _stake function call.
 */
export type stake = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _unstake function call.
 */
export type unstake = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _claimUnstake function call.
 */
export type claimUnstake = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _distributeReward function call.
 */
export type distributeReward = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _addDistributor function call.
 */
export type addDistributor = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _removeDistributor function call.
 */
export type removeDistributor = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _isDistributor function call.
 */
export type isDistributor = CallResult<
    {
        result: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _sfrenBalanceOf function call.
 */
export type sfrenBalanceOf = CallResult<
    {
        balance: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _sfrenTotalSupply function call.
 */
export type sfrenTotalSupply = CallResult<
    {
        supply: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _totalStakedView function call.
 */
export type totalStakedView = CallResult<
    {
        total: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _exchangeRate function call.
 */
export type exchangeRate = CallResult<
    {
        rate: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _pendingUnstakeView function call.
 */
export type pendingUnstakeView = CallResult<
    {
        amount: bigint;
        timestamp: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _addMinter function call.
 */
export type addMinter = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _removeMinter function call.
 */
export type removeMinter = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _isMinterView function call.
 */
export type isMinterView = CallResult<
    {
        result: boolean;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// IFRENToken
// ------------------------------------------------------------------
export interface IFRENToken extends IOP_NETContract {
    _mintFREN(to: Address, amount: bigint): Promise<mintFREN>;
    _stake(amount: bigint): Promise<stake>;
    _unstake(sfrenAmount: bigint): Promise<unstake>;
    _claimUnstake(): Promise<claimUnstake>;
    _distributeReward(amount: bigint): Promise<distributeReward>;
    _addDistributor(distributor: Address): Promise<addDistributor>;
    _removeDistributor(distributor: Address): Promise<removeDistributor>;
    _isDistributor(account: Address): Promise<isDistributor>;
    _sfrenBalanceOf(account: Address): Promise<sfrenBalanceOf>;
    _sfrenTotalSupply(): Promise<sfrenTotalSupply>;
    _totalStakedView(): Promise<totalStakedView>;
    _exchangeRate(): Promise<exchangeRate>;
    _pendingUnstakeView(account: Address): Promise<pendingUnstakeView>;
    _addMinter(minter: Address): Promise<addMinter>;
    _removeMinter(minter: Address): Promise<removeMinter>;
    _isMinterView(account: Address): Promise<isMinterView>;
}
