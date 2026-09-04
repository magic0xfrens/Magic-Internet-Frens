import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the setDeathThreshold function call.
 */
export type SetDeathThreshold = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the updateVolume function call.
 */
export type UpdateVolume = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the isDead function call.
 */
export type IsDead = CallResult<
    {
        isDead: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getVolume function call.
 */
export type GetVolume = CallResult<
    {
        volume: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the addKeeper function call.
 */
export type AddKeeper = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the removeKeeper function call.
 */
export type RemoveKeeper = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the isKeeper function call.
 */
export type IsKeeper = CallResult<
    {
        result: boolean;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// IVolumeOracle
// ------------------------------------------------------------------
export interface IVolumeOracle extends IOP_NETContract {
    setDeathThreshold(threshold: bigint): Promise<SetDeathThreshold>;
    updateVolume(pool: Address, volumeSats: bigint): Promise<UpdateVolume>;
    isDead(pool: Address): Promise<IsDead>;
    getVolume(pool: Address): Promise<GetVolume>;
    addKeeper(keeper: Address): Promise<AddKeeper>;
    removeKeeper(keeper: Address): Promise<RemoveKeeper>;
    isKeeper(account: Address): Promise<IsKeeper>;
}
