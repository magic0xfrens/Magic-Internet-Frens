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
 * @description Represents the result of the _mint_external function call.
 */
export type mintExternal = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<MintedEvent>[]
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
 * @description Represents the result of the _isMinter function call.
 */
export type isMinter = CallResult<
    {
        result: boolean;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// IMIFToken
// ------------------------------------------------------------------
export interface IMIFToken extends IOP_NETContract {
    _mint_external(to: Address, amount: bigint): Promise<mintExternal>;
    _addMinter(minter: Address): Promise<addMinter>;
    _removeMinter(minter: Address): Promise<removeMinter>;
    _isMinter(account: Address): Promise<isMinter>;
}
