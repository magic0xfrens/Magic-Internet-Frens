import { Address, AddressMap, ExtendedAddressMap, SchnorrSignature } from '@btc-vision/transaction';
import { CallResult, OPNetEvent, IOP_NETContract } from 'opnet';

// ------------------------------------------------------------------
// Event Definitions
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Call Results
// ------------------------------------------------------------------

/**
 * @description Represents the result of the _deposit function call.
 */
export type deposit = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _borrow function call.
 */
export type borrow = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _repay function call.
 */
export type repay = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _withdraw function call.
 */
export type withdraw = CallResult<
    {
        amount: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _liquidate function call.
 */
export type liquidate = CallResult<
    {
        collateralOut: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _accruePublic function call.
 */
export type accruePublic = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _distributeFees function call.
 */
export type distributeFees = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _getPosition function call.
 */
export type getPosition = CallResult<
    {
        collateral: bigint;
        debt: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _getPositionLTV function call.
 */
export type getPositionLTV = CallResult<
    {
        ltv: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _isLiquidatable function call.
 */
export type isLiquidatable = CallResult<
    {
        liquidatable: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _getInterestRate function call.
 */
export type getInterestRate = CallResult<
    {
        rate: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _totalCollateralView function call.
 */
export type totalCollateralView = CallResult<
    {
        total: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _totalDebtView function call.
 */
export type totalDebtView = CallResult<
    {
        total: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _accruedFeesView function call.
 */
export type accruedFeesView = CallResult<
    {
        fees: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _accruedBTCPenaltiesView function call.
 */
export type accruedBTCPenaltiesView = CallResult<
    {
        penalties: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _setBorrowCap function call.
 */
export type setBorrowCap = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _pause function call.
 */
export type pause = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _unpause function call.
 */
export type unpause = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _setOracle function call.
 */
export type setOracle = CallResult<
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

/**
 * @description Represents the result of the _acceptAdmin function call.
 */
export type acceptAdmin = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _distributeBTCPenalties function call.
 */
export type distributeBTCPenalties = CallResult<
    {
        amount: bigint;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _setMIF function call.
 */
export type setMIF = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _setNFT function call.
 */
export type setNFT = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

/**
 * @description Represents the result of the _setFREN function call.
 */
export type setFREN = CallResult<
    {
        success: boolean;
    },
    OPNetEvent<never>[]
>;

// ------------------------------------------------------------------
// ICauldron
// ------------------------------------------------------------------
export interface ICauldron extends IOP_NETContract {
    _deposit(amount: bigint): Promise<deposit>;
    _borrow(amount: bigint): Promise<borrow>;
    _repay(amount: bigint): Promise<repay>;
    _withdraw(amount: bigint): Promise<withdraw>;
    _liquidate(user: Address): Promise<liquidate>;
    _accruePublic(): Promise<accruePublic>;
    _distributeFees(): Promise<distributeFees>;
    _getPosition(user: Address): Promise<getPosition>;
    _getPositionLTV(user: Address): Promise<getPositionLTV>;
    _isLiquidatable(user: Address): Promise<isLiquidatable>;
    _getInterestRate(): Promise<getInterestRate>;
    _totalCollateralView(): Promise<totalCollateralView>;
    _totalDebtView(): Promise<totalDebtView>;
    _accruedFeesView(): Promise<accruedFeesView>;
    _accruedBTCPenaltiesView(): Promise<accruedBTCPenaltiesView>;
    _setBorrowCap(cap: bigint): Promise<setBorrowCap>;
    _pause(): Promise<pause>;
    _unpause(): Promise<unpause>;
    _setOracle(oracle: Address): Promise<setOracle>;
    _transferAdmin(newAdmin: Address): Promise<transferAdmin>;
    _acceptAdmin(): Promise<acceptAdmin>;
    _distributeBTCPenalties(): Promise<distributeBTCPenalties>;
    _setMIF(mif: Address): Promise<setMIF>;
    _setNFT(nft: Address): Promise<setNFT>;
    _setFREN(fren: Address): Promise<setFREN>;
}
