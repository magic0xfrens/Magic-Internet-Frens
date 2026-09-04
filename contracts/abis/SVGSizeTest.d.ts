import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the testReturn function call.
 */
export type TestReturn = CallResult<
    {
        result: string;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the testDataURI function call.
 */
export type TestDataURI = CallResult<
    {
        result: string;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the testBase64URI function call.
 */
export type TestBase64URI = CallResult<
    {
        result: string;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// ISVGSizeTest
// ------------------------------------------------------------------
export interface ISVGSizeTest extends IOP_NETContract {
    testReturn(size: bigint): Promise<TestReturn>;
    testDataURI(svgSize: bigint): Promise<TestDataURI>;
    testBase64URI(rawSize: bigint): Promise<TestBase64URI>;
}
