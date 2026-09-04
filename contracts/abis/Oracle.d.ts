import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the _getPrice function call.
 */
export type getPrice = CallResult<
    {
        price: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _isFresh function call.
 */
export type isFresh = CallResult<
    {
        fresh: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _lastUpdateView function call.
 */
export type lastUpdateView = CallResult<
    {
        timestamp: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _adminView function call.
 */
export type adminView = CallResult<
    {
        admin: Address;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _updateCountView function call.
 */
export type updateCountView = CallResult<
    {
        count: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _setPrice function call.
 */
export type setPrice = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _transferAdmin function call.
 */
export type transferAdmin = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// IOracle
// ------------------------------------------------------------------
export interface IOracle extends IOP_NETContract {
    _getPrice(): Promise<getPrice>;
    _isFresh(): Promise<isFresh>;
    _lastUpdateView(): Promise<lastUpdateView>;
    _adminView(): Promise<adminView>;
    _updateCountView(): Promise<updateCountView>;
    _setPrice(price: bigint): Promise<setPrice>;
    _transferAdmin(newAdmin: Address): Promise<transferAdmin>;
}
