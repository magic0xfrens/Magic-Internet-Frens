import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the summonGenesis function call.
 */
export type SummonGenesis = CallResult<
    {
        token: Address;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the triggerRebirth function call.
 */
export type TriggerRebirth = CallResult<
    {
        token: Address;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the claimTokens function call.
 */
export type ClaimTokens = CallResult<
    {
        balance: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getCurrentToken function call.
 */
export type GetCurrentToken = CallResult<
    {
        token: Address;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the getCurrentGeneration function call.
 */
export type GetCurrentGeneration = CallResult<
    {
        generation: bigint;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// ICauldronRegistry
// ------------------------------------------------------------------
export interface ICauldronRegistry extends IOP_NETContract {
    summonGenesis(tokenAddress: Address, poolAddress: Address, name: string, symbol: string): Promise<SummonGenesis>;
    triggerRebirth(
        newTokenAddress: Address,
        newPoolAddress: Address,
        name: string,
        symbol: string,
    ): Promise<TriggerRebirth>;
    claimTokens(generation: bigint): Promise<ClaimTokens>;
    getCurrentToken(): Promise<GetCurrentToken>;
    getCurrentGeneration(): Promise<GetCurrentGeneration>;
}
