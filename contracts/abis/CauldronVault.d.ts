import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the setRegistry function call.
 */
export type SetRegistry = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the setOracle function call.
 */
export type SetOracle = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the lockLiquidity function call.
 */
export type LockLiquidity = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the canMigrate function call.
 */
export type CanMigrate = CallResult<
    {
        canMigrate: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the migrateLiquidity function call.
 */
export type MigrateLiquidity = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// ICauldronVault
// ------------------------------------------------------------------
export interface ICauldronVault extends IOP_NETContract {
    setRegistry(registry: Address): Promise<SetRegistry>;
    setOracle(oracle: Address): Promise<SetOracle>;
    lockLiquidity(pool: Address): Promise<LockLiquidity>;
    canMigrate(pool: Address): Promise<CanMigrate>;
    migrateLiquidity(
        oldPool: Address,
        newPool: Address,
        btcAmount: bigint,
        tokenAmount: bigint,
    ): Promise<MigrateLiquidity>;
}
