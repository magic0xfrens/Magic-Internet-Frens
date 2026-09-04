import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    CallResult,
    Calldata,
    encodeSelector,
    OP_NET,
    Revert,
    SafeMath,
    Selector,
    StoredU256,
    StoredU64,
    StoredBoolean,
    AddressMemoryMap,
} from '@btc-vision/btc-runtime/runtime';

import {
    BPS_PRECISION,
    PRECISION_18,
    SATS_PER_BTC,
    LTV_BPS,
    LIQUIDATION_BPS,
    LIQUIDATION_PENALTY_BPS,
    BORROW_FEE_BPS,
    BLOCKS_PER_YEAR,
    BASE_RATE,
    KINK_RATE,
    KINK_UTILIZATION,
    MAX_RATE,
    REENTRANCY_UNLOCKED,
    REENTRANCY_LOCKED,
} from '../lib/constants';
import {
    ERR_CAULDRON_REENTRANT,
    ERR_CAULDRON_PAUSED,
    ERR_CAULDRON_NOT_ADMIN,
    ERR_CAULDRON_ZERO_AMOUNT,
    ERR_CAULDRON_NOT_NFT_OWNER,
    ERR_CAULDRON_EXCEEDS_LTV,
    ERR_CAULDRON_EXCEEDS_BORROW_CAP,
    ERR_CAULDRON_NO_DEBT,
    ERR_CAULDRON_INSUFFICIENT_COL,
    ERR_CAULDRON_HEALTHY,
    ERR_CAULDRON_NO_COLLATERAL,
    ERR_CAULDRON_ZERO_ADDR,
    ERR_CAULDRON_NO_FEES,
    ERR_CAULDRON_BTC_NOT_VERIFIED,
    ERR_CAULDRON_NO_BTC_PENALTIES,
    ERR_CAULDRON_PENDING_ADMIN_ZERO,
    ERR_CAULDRON_NOT_PENDING_ADMIN,
} from '../lib/errors';
import {
    DepositEvent,
    BorrowEvent,
    RepayEvent,
    WithdrawEvent,
    LiquidateEvent,
    FeesDistributedEvent,
    AccrueEvent,
    BTCPenaltiesDistributedEvent,
    AdminTransferInitiatedEvent,
    AdminTransferAcceptedEvent,
} from '../events/CauldronEvents';

/**
 * Cauldron -- Core Lending Market for the Magic Internet Frens Protocol.
 *
 * Fork of Abracadabra's Cauldron architecture, adapted for OP_NET + BTC.
 *
 * Users deposit BTC as collateral and borrow MIF stablecoin against it.
 *
 * Parameters:
 *   - LTV:                75%
 *   - Liquidation:        80%
 *   - Liquidation penalty: 5%
 *   - Borrow opening fee: 0.5%
 *   - Interest rate:      1-50% APR (kink at 80% utilization)
 *
 * Cross-contract calls:
 *   - Oracle.getPrice() for BTC/USD pricing
 *   - MIF.mint(address,uint256) for minting stablecoins
 *   - NFT.ownerOf(uint256) for ownership verification
 *   - NFT.getMaxBorrow(uint256) / getLiquidationGrace(uint256) for class-based benefits
 *   - FREN.distributeReward(uint256) for fee distribution
 */
@final
export class Cauldron extends OP_NET {
    // -----------------------------------------------------------------------
    // Storage Pointers
    // -----------------------------------------------------------------------

    private readonly adminAddrPointer: u16 = Blockchain.nextPointer;
    private readonly oracleAddrPointer: u16 = Blockchain.nextPointer;
    private readonly mifAddrPointer: u16 = Blockchain.nextPointer;
    private readonly nftAddrPointer: u16 = Blockchain.nextPointer;
    private readonly frenAddrPointer: u16 = Blockchain.nextPointer;

    private readonly totalCollateralPointer: u16 = Blockchain.nextPointer;
    private readonly totalDebtPointer: u16 = Blockchain.nextPointer;
    private readonly totalBorrowCapPointer: u16 = Blockchain.nextPointer;
    private readonly accruedFeesPointer: u16 = Blockchain.nextPointer;
    private readonly lastAccruePointer: u16 = Blockchain.nextPointer;
    private readonly reentrancyPointer: u16 = Blockchain.nextPointer;
    private readonly pausedPointer: u16 = Blockchain.nextPointer;

    private readonly userCollateralPointer: u16 = Blockchain.nextPointer;
    private readonly userDebtPointer: u16 = Blockchain.nextPointer;

    // Audit fix storage pointers
    private readonly accruedBTCPenaltiesPointer: u16 = Blockchain.nextPointer;
    private readonly pendingAdminPointer: u16 = Blockchain.nextPointer;
    private readonly totalDebtSharesPointer: u16 = Blockchain.nextPointer;

    // -----------------------------------------------------------------------
    // Storage Instances
    // -----------------------------------------------------------------------

    // Contract addresses stored as u256 (address bytes encoded)
    private readonly _adminAddr: StoredU256;
    private readonly _oracleAddr: StoredU256;
    private readonly _mifAddr: StoredU256;
    private readonly _nftAddr: StoredU256;
    private readonly _frenAddr: StoredU256;

    // Global protocol state
    private readonly _totalCollateral: StoredU256;
    private readonly _totalDebt: StoredU256;
    private readonly _totalBorrowCap: StoredU256;
    private readonly _accruedFees: StoredU256;
    private readonly _lastAccrueTs: StoredU64;
    private readonly _reentrancyGuard: StoredU256;
    private readonly _paused: StoredBoolean;

    // Per-user state (keyed by user address)
    private readonly _userCollateral: AddressMemoryMap;
    private readonly _userDebt: AddressMemoryMap; // H-7: stores debt SHARES, not raw debt

    // Audit fix storage
    private readonly _accruedBTCPenalties: StoredU256;  // C-2: separate BTC penalty pool
    private readonly _pendingAdmin: StoredU256;          // H-6: two-step admin transfer
    private readonly _totalDebtShares: StoredU256;       // H-7: total debt shares outstanding

    // -----------------------------------------------------------------------
    // Cross-contract selectors (pre-computed)
    // -----------------------------------------------------------------------

    private readonly ORACLE_GET_PRICE: u32 = encodeSelector('getPrice()');
    private readonly MIF_MINT: u32 = encodeSelector('mint(address,uint256)');
    private readonly MIF_BURN: u32 = encodeSelector('burn(uint256)');
    private readonly MIF_BURN_FROM: u32 = encodeSelector('burnFrom(address,uint256)');
    private readonly NFT_OWNER_OF: u32 = encodeSelector('ownerOf(uint256)');
    // getTier removed — borrow/grace are now class-based (getMaxBorrow, getLiquidationGrace)
    private readonly NFT_GET_TAX_RATE: u32 = encodeSelector('getTaxRate(uint256)');
    private readonly FREN_DISTRIBUTE: u32 = encodeSelector('distributeReward(uint256)');

    // -----------------------------------------------------------------------
    // Method Selectors
    // -----------------------------------------------------------------------

    private readonly depositSelector: Selector = encodeSelector('deposit(uint256)');
    private readonly borrowSelector: Selector = encodeSelector('borrow(uint256)');
    private readonly repaySelector: Selector = encodeSelector('repay(uint256)');
    private readonly withdrawSelector: Selector = encodeSelector('withdraw(uint256)');
    private readonly liquidateSelector: Selector = encodeSelector('liquidate(address)');
    private readonly accrueSelector: Selector = encodeSelector('accrue()');
    private readonly distributeFeesSelector: Selector = encodeSelector('distributeFees()');

    // View selectors
    private readonly getPositionSelector: Selector = encodeSelector('getPosition(address)');
    private readonly getPositionLTVSelector: Selector = encodeSelector('getPositionLTV(address)');
    private readonly isLiquidatableSelector: Selector = encodeSelector('isLiquidatable(address)');
    private readonly getInterestRateSelector: Selector = encodeSelector('getCurrentInterestRate()');
    private readonly totalCollateralSelector: Selector = encodeSelector('totalCollateral()');
    private readonly totalDebtSelector: Selector = encodeSelector('totalDebt()');
    private readonly accruedFeesSelector: Selector = encodeSelector('accruedFees()');

    // View selectors (new)
    private readonly accruedBTCPenaltiesSelector: Selector = encodeSelector('accruedBTCPenalties()');

    // Admin selectors
    private readonly setBorrowCapSelector: Selector = encodeSelector('setTotalBorrowCap(uint256)');
    private readonly pauseSelector: Selector = encodeSelector('pause()');
    private readonly unpauseSelector: Selector = encodeSelector('unpause()');
    private readonly setOracleSelector: Selector = encodeSelector('setOracle(address)');
    private readonly transferAdminSelector: Selector = encodeSelector('transferAdmin(address)');
    private readonly acceptAdminSelector: Selector = encodeSelector('acceptAdmin()');
    private readonly distributeBTCPenaltiesSelector: Selector = encodeSelector('distributeBTCPenalties()');
    private readonly setMifSelector: Selector = encodeSelector('setMIFToken(address)');
    private readonly setNftSelector: Selector = encodeSelector('setNFTContract(address)');
    private readonly setFrenSelector: Selector = encodeSelector('setFRENToken(address)');

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    public constructor() {
        super();

        this._adminAddr = new StoredU256(this.adminAddrPointer, u256.Zero);
        this._oracleAddr = new StoredU256(this.oracleAddrPointer, u256.Zero);
        this._mifAddr = new StoredU256(this.mifAddrPointer, u256.Zero);
        this._nftAddr = new StoredU256(this.nftAddrPointer, u256.Zero);
        this._frenAddr = new StoredU256(this.frenAddrPointer, u256.Zero);

        this._totalCollateral = new StoredU256(this.totalCollateralPointer, u256.Zero);
        this._totalDebt = new StoredU256(this.totalDebtPointer, u256.Zero);
        this._totalBorrowCap = new StoredU256(this.totalBorrowCapPointer, u256.Zero);
        this._accruedFees = new StoredU256(this.accruedFeesPointer, u256.Zero);
        this._lastAccrueTs = new StoredU64(this.lastAccruePointer, 0);
        this._reentrancyGuard = new StoredU256(this.reentrancyPointer, REENTRANCY_UNLOCKED);
        this._paused = new StoredBoolean(this.pausedPointer, false);

        this._userCollateral = new AddressMemoryMap(this.userCollateralPointer);
        this._userDebt = new AddressMemoryMap(this.userDebtPointer);

        // Audit fix storage
        this._accruedBTCPenalties = new StoredU256(this.accruedBTCPenaltiesPointer, u256.Zero);
        this._pendingAdmin = new StoredU256(this.pendingAdminPointer, u256.Zero);
        this._totalDebtShares = new StoredU256(this.totalDebtSharesPointer, u256.Zero);
    }

    // -----------------------------------------------------------------------
    // Deployment
    // -----------------------------------------------------------------------

    public override onDeployment(calldata: Calldata): void {
        // Read contract addresses from deployment calldata
        const oracle: Address = calldata.readAddress();
        const mif: Address = calldata.readAddress();
        const nft: Address = calldata.readAddress();
        const fren: Address = calldata.readAddress();

        const deployer: Address = Blockchain.tx.sender;
        this._adminAddr.set(this._addressToU256(deployer));
        this._oracleAddr.set(this._addressToU256(oracle));
        this._mifAddr.set(this._addressToU256(mif));
        this._nftAddr.set(this._addressToU256(nft));
        this._frenAddr.set(this._addressToU256(fren));

        this._lastAccrueTs.set(Blockchain.block.number);
        this._reentrancyGuard.set(REENTRANCY_UNLOCKED);
    }

    // -----------------------------------------------------------------------
    // callMethod Router
    // -----------------------------------------------------------------------

    public override callMethod(calldata: Calldata): BytesWriter {
        const selector: Selector = calldata.readSelector();

        switch (selector) {
            // Core lending operations
            case this.depositSelector:
                return this._deposit(calldata);
            case this.borrowSelector:
                return this._borrow(calldata);
            case this.repaySelector:
                return this._repay(calldata);
            case this.withdrawSelector:
                return this._withdraw(calldata);
            case this.liquidateSelector:
                return this._liquidate(calldata);
            case this.accrueSelector:
                return this._accruePublic(calldata);
            case this.distributeFeesSelector:
                return this._distributeFees(calldata);

            // View functions
            case this.getPositionSelector:
                return this._getPosition(calldata);
            case this.getPositionLTVSelector:
                return this._getPositionLTV(calldata);
            case this.isLiquidatableSelector:
                return this._isLiquidatable(calldata);
            case this.getInterestRateSelector:
                return this._getInterestRate(calldata);
            case this.totalCollateralSelector:
                return this._totalCollateralView(calldata);
            case this.totalDebtSelector:
                return this._totalDebtView(calldata);
            case this.accruedFeesSelector:
                return this._accruedFeesView(calldata);
            case this.accruedBTCPenaltiesSelector:
                return this._accruedBTCPenaltiesView(calldata);

            // Admin functions
            case this.setBorrowCapSelector:
                return this._setBorrowCap(calldata);
            case this.pauseSelector:
                return this._pause(calldata);
            case this.unpauseSelector:
                return this._unpause(calldata);
            case this.setOracleSelector:
                return this._setOracle(calldata);
            case this.transferAdminSelector:
                return this._transferAdmin(calldata);
            case this.acceptAdminSelector:
                return this._acceptAdmin(calldata);
            case this.distributeBTCPenaltiesSelector:
                return this._distributeBTCPenalties(calldata);
            case this.setMifSelector:
                return this._setMIF(calldata);
            case this.setNftSelector:
                return this._setNFT(calldata);
            case this.setFrenSelector:
                return this._setFREN(calldata);

            default:
                return super.callMethod(calldata);
        }
    }

    // -----------------------------------------------------------------------
    // Address Helpers
    // -----------------------------------------------------------------------

    private _addressToU256(addr: Address): u256 {
        return u256.fromBytesBE(addr.toBytes());
    }

    private _u256ToAddress(val: u256): Address {
        return Address.fromBytes(val.toBytesBE());
    }

    private _getAdmin(): Address {
        return this._u256ToAddress(this._adminAddr.get());
    }

    private _getOracle(): Address {
        return this._u256ToAddress(this._oracleAddr.get());
    }

    private _getMIF(): Address {
        return this._u256ToAddress(this._mifAddr.get());
    }

    private _getNFT(): Address {
        return this._u256ToAddress(this._nftAddr.get());
    }

    private _getFREN(): Address {
        return this._u256ToAddress(this._frenAddr.get());
    }

    // -----------------------------------------------------------------------
    // Security: Reentrancy Guard
    // -----------------------------------------------------------------------

    private _nonReentrant_enter(): void {
        const guard: u256 = this._reentrancyGuard.get();
        if (u256.eq(guard, REENTRANCY_LOCKED)) {
            throw new Revert(ERR_CAULDRON_REENTRANT);
        }
        this._reentrancyGuard.set(REENTRANCY_LOCKED);
    }

    private _nonReentrant_exit(): void {
        this._reentrancyGuard.set(REENTRANCY_UNLOCKED);
    }

    // -----------------------------------------------------------------------
    // Access Control
    // -----------------------------------------------------------------------

    private _onlyAdmin(): void {
        const sender: Address = Blockchain.tx.sender;
        const admin: Address = this._getAdmin();
        if (!sender.equals(admin)) {
            throw new Revert(ERR_CAULDRON_NOT_ADMIN);
        }
    }

    private _whenNotPaused(): void {
        if (this._paused.value) {
            throw new Revert(ERR_CAULDRON_PAUSED);
        }
    }

    // -----------------------------------------------------------------------
    // Cross-Contract Calls
    // -----------------------------------------------------------------------

    /** Call Oracle.getPrice() -> returns u256 price with 18 decimals */
    private _getOraclePrice(): u256 {
        const oracle: Address = this._getOracle();
        const writer: BytesWriter = new BytesWriter(4);
        writer.writeSelector(this.ORACLE_GET_PRICE);

        const result: CallResult = Blockchain.call(oracle, writer, true);
        // Result contains u256 price
        const price: u256 = result.readU256();
        return price;
    }

    /** Call MIF.mint(to, amount) */
    private _callMIFMint(to: Address, amount: u256): void {
        const mif: Address = this._getMIF();
        const writer: BytesWriter = new BytesWriter(68); // 4 + 32 + 32
        writer.writeSelector(this.MIF_MINT);
        writer.writeAddress(to);
        writer.writeU256(amount);

        Blockchain.call(mif, writer, true);
    }

    /** Call NFT.ownerOf(tokenId) -- not used directly in per-user model */
    // NFT ownership verification is done if we gate by NFT. In this
    // per-address model, we skip direct NFT gating on deposit/borrow
    // but keep the cross-contract call infrastructure for future use.

    /** Call NFT.getTaxRate(tokenId) -> u256 tax rate BPS */
    private _callNFTGetTaxRate(tokenId: u256): u256 {
        const nft: Address = this._getNFT();
        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(this.NFT_GET_TAX_RATE);
        writer.writeU256(tokenId);

        const result: CallResult = Blockchain.call(nft, writer, true);
        return result.readU256();
    }

    /** Call MIF.burnFrom(from, amount) */
    private _callMIFBurnFrom(from: Address, amount: u256): void {
        const mif: Address = this._getMIF();
        const writer: BytesWriter = new BytesWriter(68); // 4 + 32 + 32
        writer.writeSelector(this.MIF_BURN_FROM);
        writer.writeAddress(from);
        writer.writeU256(amount);

        Blockchain.call(mif, writer, true);
    }

    /**
     * Verify that the transaction includes a BTC output to this contract's address
     * matching at least the expected amount in satoshis.
     */
    private _verifyBTCDeposit(expectedSats: u256): void {
        const outputs = Blockchain.tx.outputs;
        const contractAddr: Address = Blockchain.contractAddress;
        let verified: bool = false;

        for (let i: i32 = 0; i < outputs.length; i++) {
            const output = outputs[i];
            if (output.address.equals(contractAddr)) {
                if (u256.ge(output.value, expectedSats)) {
                    verified = true;
                    break;
                }
            }
        }

        if (!verified) {
            throw new Revert(ERR_CAULDRON_BTC_NOT_VERIFIED);
        }
    }

    /** Call FREN.distributeReward(amount) */
    private _callFRENDistribute(amount: u256): void {
        const fren: Address = this._getFREN();
        const writer: BytesWriter = new BytesWriter(36); // 4 + 32
        writer.writeSelector(this.FREN_DISTRIBUTE);
        writer.writeU256(amount);

        Blockchain.call(fren, writer, true);
    }

    // -----------------------------------------------------------------------
    // Oracle: Collateral Valuation
    // -----------------------------------------------------------------------

    /**
     * Convert BTC collateral (u256 satoshis) to MIF value (u256 18 decimals).
     * collateralMIF = collateralSats * btcPrice / SATS_PER_BTC
     */
    private _collateralToMIF(collateralSats: u256): u256 {
        if (collateralSats.isZero()) return u256.Zero;

        const btcPrice: u256 = this._getOraclePrice();
        // btcPrice is already 18 decimals, collateralSats is in sats (8 decimals implicit)
        // value = sats * price / 10^8
        return SafeMath.div(SafeMath.mul(collateralSats, btcPrice), SATS_PER_BTC);
    }

    // -----------------------------------------------------------------------
    // H-7: Debt Shares Helper
    // -----------------------------------------------------------------------

    /** Convert debt shares to actual debt amount: shares * totalDebt / totalShares */
    private _sharesToDebt(shares: u256): u256 {
        if (shares.isZero()) return u256.Zero;
        const totalShares: u256 = this._totalDebtShares.get();
        if (totalShares.isZero()) return u256.Zero;
        const totalDebt: u256 = this._totalDebt.get();
        return SafeMath.div(SafeMath.mul(shares, totalDebt), totalShares);
    }

    // -----------------------------------------------------------------------
    // Interest Rate Model
    // -----------------------------------------------------------------------

    /**
     * Calculate interest rate in BPS based on utilization.
     * Piecewise: linear from BASE_RATE to KINK_RATE below kink,
     * quadratic from KINK_RATE to MAX_RATE above kink.
     */
    private _calculateInterestRate(utilizationBPS: u256): u256 {
        if (u256.le(utilizationBPS, KINK_UTILIZATION)) {
            // Linear segment: BASE_RATE + (KINK_RATE - BASE_RATE) * util / KINK_UTIL
            const spread: u256 = SafeMath.sub(KINK_RATE, BASE_RATE);
            return SafeMath.add(
                BASE_RATE,
                SafeMath.div(SafeMath.mul(spread, utilizationBPS), KINK_UTILIZATION),
            );
        } else {
            // Quadratic segment above kink
            const excess: u256 = SafeMath.sub(utilizationBPS, KINK_UTILIZATION);
            const range: u256 = SafeMath.sub(BPS_PRECISION, KINK_UTILIZATION); // 2000 BPS
            const spread: u256 = SafeMath.sub(MAX_RATE, KINK_RATE);

            // rate = KINK_RATE + spread * excess^2 / range^2
            const excessSq: u256 = SafeMath.mul(excess, excess);
            const rangeSq: u256 = SafeMath.mul(range, range);
            return SafeMath.add(
                KINK_RATE,
                SafeMath.div(SafeMath.mul(excessSq, spread), rangeSq),
            );
        }
    }

    /** Calculate current utilization in BPS */
    private _getUtilizationBPS(): u256 {
        const totalDebt: u256 = this._totalDebt.get();
        if (totalDebt.isZero()) return u256.Zero;

        const totalColMIF: u256 = this._collateralToMIF(this._totalCollateral.get());
        if (totalColMIF.isZero()) return BPS_PRECISION;

        let util: u256 = SafeMath.div(SafeMath.mul(totalDebt, BPS_PRECISION), totalColMIF);
        if (u256.gt(util, BPS_PRECISION)) {
            util = BPS_PRECISION;
        }
        return util;
    }

    // -----------------------------------------------------------------------
    // Interest Accrual
    // -----------------------------------------------------------------------

    private _accrueInterest(): void {
        const currentBlock: u64 = Blockchain.block.number;
        const lastAccrue: u64 = this._lastAccrueTs.get();

        if (currentBlock <= lastAccrue) return;

        const totalDebt: u256 = this._totalDebt.get();
        if (totalDebt.isZero()) {
            this._lastAccrueTs.set(currentBlock);
            return;
        }

        const elapsedBlocks: u256 = u256.fromU64(currentBlock - lastAccrue);
        const utilizationBPS: u256 = this._getUtilizationBPS();
        const rateBPS: u256 = this._calculateInterestRate(utilizationBPS);

        // interest = totalDebt * rateBPS * elapsedBlocks / (BPS * BLOCKS_PER_YEAR)
        const numerator: u256 = SafeMath.mul(
            SafeMath.mul(totalDebt, rateBPS),
            elapsedBlocks,
        );
        const denominator: u256 = SafeMath.mul(BPS_PRECISION, BLOCKS_PER_YEAR);
        const interest: u256 = SafeMath.div(numerator, denominator);

        if (!interest.isZero()) {
            this._totalDebt.set(SafeMath.add(totalDebt, interest));
            this._accruedFees.set(SafeMath.add(this._accruedFees.get(), interest));
            this.emitEvent(new AccrueEvent(interest, currentBlock));
        }

        this._lastAccrueTs.set(currentBlock);
    }

    // -----------------------------------------------------------------------
    // Core Operations
    // -----------------------------------------------------------------------

    /**
     * deposit(amount): Deposit BTC collateral (u256 satoshis).
     */
    @method({ name: 'amount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _deposit(calldata: Calldata): BytesWriter {
        this._nonReentrant_enter();
        this._whenNotPaused();

        const sender: Address = Blockchain.tx.sender;
        const amount: u256 = calldata.readU256();

        if (amount.isZero()) {
            throw new Revert(ERR_CAULDRON_ZERO_AMOUNT);
        }

        // Verify BTC was actually sent to this contract in the transaction
        this._verifyBTCDeposit(amount);

        // Accrue interest before state change
        this._accrueInterest();

        // Update user collateral
        const currentCol: u256 = this._userCollateral.get(sender);
        this._userCollateral.set(sender, SafeMath.add(currentCol, amount));

        // Update global collateral
        this._totalCollateral.set(
            SafeMath.add(this._totalCollateral.get(), amount),
        );

        this.emitEvent(new DepositEvent(sender, amount));

        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * borrow(amount): Borrow MIF stablecoin against collateral.
     * Checks LTV <= 75%, charges 0.5% opening fee.
     * H-7: Uses debt shares model for fair interest distribution.
     */
    @method({ name: 'amount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _borrow(calldata: Calldata): BytesWriter {
        this._nonReentrant_enter();
        this._whenNotPaused();

        const sender: Address = Blockchain.tx.sender;
        const amount: u256 = calldata.readU256();

        if (amount.isZero()) {
            throw new Revert(ERR_CAULDRON_ZERO_AMOUNT);
        }

        // Accrue interest before state change
        this._accrueInterest();

        // Calculate opening fee: 0.5% of borrow amount
        const openingFee: u256 = SafeMath.div(
            SafeMath.mul(amount, BORROW_FEE_BPS),
            BPS_PRECISION,
        );
        const totalDebtIncrease: u256 = SafeMath.add(amount, openingFee);

        // H-7: Calculate new shares for this debt increase
        const totalDebt: u256 = this._totalDebt.get();
        const totalShares: u256 = this._totalDebtShares.get();
        let newShares: u256;
        if (totalShares.isZero() || totalDebt.isZero()) {
            // First borrow: 1:1 shares to debt
            newShares = totalDebtIncrease;
        } else {
            newShares = SafeMath.div(SafeMath.mul(totalDebtIncrease, totalShares), totalDebt);
        }

        // Update user debt shares
        const currentShares: u256 = this._userDebt.get(sender);
        const updatedShares: u256 = SafeMath.add(currentShares, newShares);
        this._userDebt.set(sender, updatedShares);

        // Check LTV using actual debt (converted from shares)
        const userCol: u256 = this._userCollateral.get(sender);
        const colValueMIF: u256 = this._collateralToMIF(userCol);
        if (colValueMIF.isZero()) {
            throw new Revert(ERR_CAULDRON_NO_COLLATERAL);
        }

        // Compute actual debt after this borrow for LTV check
        const newTotalDebt: u256 = SafeMath.add(totalDebt, totalDebtIncrease);
        const newTotalShares: u256 = SafeMath.add(totalShares, newShares);
        const actualUserDebt: u256 = SafeMath.div(
            SafeMath.mul(updatedShares, newTotalDebt), newTotalShares,
        );
        const currentLTV: u256 = SafeMath.div(
            SafeMath.mul(actualUserDebt, BPS_PRECISION),
            colValueMIF,
        );
        if (u256.gt(currentLTV, LTV_BPS)) {
            throw new Revert(ERR_CAULDRON_EXCEEDS_LTV);
        }

        // Update global state
        this._totalDebt.set(newTotalDebt);
        this._totalDebtShares.set(newTotalShares);

        // Check global borrow cap
        const borrowCap: u256 = this._totalBorrowCap.get();
        if (!borrowCap.isZero() && u256.gt(newTotalDebt, borrowCap)) {
            throw new Revert(ERR_CAULDRON_EXCEEDS_BORROW_CAP);
        }

        // Accumulate opening fee
        this._accruedFees.set(SafeMath.add(this._accruedFees.get(), openingFee));

        // Mint MIF to borrower via cross-contract call
        this._callMIFMint(sender, amount);

        this.emitEvent(new BorrowEvent(sender, amount, openingFee));

        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * repay(amount): Repay MIF debt. Burns repaid tokens.
     * H-7: Uses debt shares model — converts shares to actual debt.
     */
    @method({ name: 'amount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _repay(calldata: Calldata): BytesWriter {
        this._nonReentrant_enter();
        this._whenNotPaused();

        const sender: Address = Blockchain.tx.sender;
        const amount: u256 = calldata.readU256();

        if (amount.isZero()) {
            throw new Revert(ERR_CAULDRON_ZERO_AMOUNT);
        }

        // Accrue interest before state change
        this._accrueInterest();

        const currentShares: u256 = this._userDebt.get(sender);
        if (currentShares.isZero()) {
            throw new Revert(ERR_CAULDRON_NO_DEBT);
        }

        // Convert shares to actual debt
        const actualDebt: u256 = this._sharesToDebt(currentShares);

        // Cap repayment at outstanding debt
        let repayAmount: u256;
        let sharesToBurn: u256;
        if (u256.ge(amount, actualDebt)) {
            // Full repay: burn all shares (avoids dust)
            repayAmount = actualDebt;
            sharesToBurn = currentShares;
        } else {
            repayAmount = amount;
            const totalDebt: u256 = this._totalDebt.get();
            const totalShares: u256 = this._totalDebtShares.get();
            sharesToBurn = SafeMath.div(SafeMath.mul(repayAmount, totalShares), totalDebt);
        }

        // Update user debt shares
        this._userDebt.set(sender, SafeMath.sub(currentShares, sharesToBurn));

        // Update global debt and shares
        this._totalDebt.set(SafeMath.sub(this._totalDebt.get(), repayAmount));
        this._totalDebtShares.set(SafeMath.sub(this._totalDebtShares.get(), sharesToBurn));

        // Burn MIF from the sender's balance via cross-contract call
        this._callMIFBurnFrom(sender, repayAmount);

        this.emitEvent(new RepayEvent(sender, repayAmount));

        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * withdraw(amount): Withdraw BTC collateral. LTV must remain safe.
     * C-3: Returns withdrawn amount (u256) so frontend can set up extraOutputs.
     * H-7: LTV check converts debt shares to actual debt.
     */
    @method({ name: 'amount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'amount', type: ABIDataTypes.UINT256 })
    private _withdraw(calldata: Calldata): BytesWriter {
        this._nonReentrant_enter();
        this._whenNotPaused();

        const sender: Address = Blockchain.tx.sender;
        const amount: u256 = calldata.readU256();

        if (amount.isZero()) {
            throw new Revert(ERR_CAULDRON_ZERO_AMOUNT);
        }

        // Accrue interest before state change
        this._accrueInterest();

        const currentCol: u256 = this._userCollateral.get(sender);
        if (u256.gt(amount, currentCol)) {
            throw new Revert(ERR_CAULDRON_INSUFFICIENT_COL);
        }

        // Update collateral (checks-effects first)
        const newCol: u256 = SafeMath.sub(currentCol, amount);
        this._userCollateral.set(sender, newCol);

        // Check LTV remains safe after withdrawal (H-7: use shares->debt)
        const currentShares: u256 = this._userDebt.get(sender);
        if (!currentShares.isZero()) {
            const currentDebt: u256 = this._sharesToDebt(currentShares);
            if (newCol.isZero()) {
                throw new Revert(ERR_CAULDRON_EXCEEDS_LTV);
            }
            const colValueMIF: u256 = this._collateralToMIF(newCol);
            if (colValueMIF.isZero()) {
                throw new Revert(ERR_CAULDRON_EXCEEDS_LTV);
            }
            const newLTV: u256 = SafeMath.div(
                SafeMath.mul(currentDebt, BPS_PRECISION),
                colValueMIF,
            );
            if (u256.gt(newLTV, LTV_BPS)) {
                throw new Revert(ERR_CAULDRON_EXCEEDS_LTV);
            }
        }

        // Update global collateral
        this._totalCollateral.set(SafeMath.sub(this._totalCollateral.get(), amount));

        this.emitEvent(new WithdrawEvent(sender, amount));

        this._nonReentrant_exit();

        // C-3: return amount for frontend extraOutputs
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(amount);
        return writer;
    }

    /**
     * liquidate(user): Liquidate an undercollateralized position.
     * Anyone can call. LTV must be > 80%.
     * Liquidator repays debt, receives collateral minus 5% penalty.
     * C-2: Penalty goes to separate BTC penalties pool (not MIF fees).
     * H-7: Converts debt shares to actual debt for burn amount.
     */
    @method({ name: 'user', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'collateralOut', type: ABIDataTypes.UINT256 })
    private _liquidate(calldata: Calldata): BytesWriter {
        this._nonReentrant_enter();
        this._whenNotPaused();

        const liquidator: Address = Blockchain.tx.sender;
        const user: Address = calldata.readAddress();

        // Accrue interest before check
        this._accrueInterest();

        // H-7: read shares and convert to actual debt
        const userShares: u256 = this._userDebt.get(user);
        if (userShares.isZero()) {
            throw new Revert(ERR_CAULDRON_NO_DEBT);
        }
        const userDebt: u256 = this._sharesToDebt(userShares);

        const userCol: u256 = this._userCollateral.get(user);
        if (userCol.isZero()) {
            throw new Revert(ERR_CAULDRON_NO_COLLATERAL);
        }

        // Check if position is liquidatable (LTV > 80%)
        const colValueMIF: u256 = this._collateralToMIF(userCol);
        const currentLTV: u256 = SafeMath.div(
            SafeMath.mul(userDebt, BPS_PRECISION),
            colValueMIF,
        );
        if (u256.le(currentLTV, LIQUIDATION_BPS)) {
            throw new Revert(ERR_CAULDRON_HEALTHY);
        }

        // Calculate liquidation amounts
        const penaltyAmount: u256 = SafeMath.div(
            SafeMath.mul(userCol, LIQUIDATION_PENALTY_BPS),
            BPS_PRECISION,
        );
        const collateralToLiquidator: u256 = SafeMath.sub(userCol, penaltyAmount);

        // Clear position (checks-effects first)
        this._userCollateral.set(user, u256.Zero);
        this._userDebt.set(user, u256.Zero);

        // Update global state
        this._totalCollateral.set(SafeMath.sub(this._totalCollateral.get(), userCol));
        this._totalDebt.set(SafeMath.sub(this._totalDebt.get(), userDebt));
        this._totalDebtShares.set(SafeMath.sub(this._totalDebtShares.get(), userShares));

        // C-2: BTC penalty goes to separate pool (not MIF accrued fees)
        this._accruedBTCPenalties.set(
            SafeMath.add(this._accruedBTCPenalties.get(), penaltyAmount),
        );

        // Burn the user's debt worth of MIF from the liquidator
        this._callMIFBurnFrom(liquidator, userDebt);

        this.emitEvent(new LiquidateEvent(liquidator, user, userDebt, collateralToLiquidator));

        this._nonReentrant_exit();

        // Return collateral amount so frontend can set up extraOutputs for BTC payout
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(collateralToLiquidator);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Public: Accrue interest
    // -----------------------------------------------------------------------

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _accruePublic(_calldata: Calldata): BytesWriter {
        this._accrueInterest();
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Fee Distribution (Admin-only)
    // -----------------------------------------------------------------------

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _distributeFees(_calldata: Calldata): BytesWriter {
        this._onlyAdmin();

        const fees: u256 = this._accruedFees.get();
        if (fees.isZero()) {
            throw new Revert(ERR_CAULDRON_NO_FEES);
        }

        // Reset accrued fees (effects before interactions)
        this._accruedFees.set(u256.Zero);

        // Distribute to FREN stakers via cross-contract call
        this._callFRENDistribute(fees);

        this.emitEvent(new FeesDistributedEvent(fees));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // View Functions
    // -----------------------------------------------------------------------

    @method({ name: 'user', type: ABIDataTypes.ADDRESS })
    @returns(
        { name: 'collateral', type: ABIDataTypes.UINT256 },
        { name: 'debt', type: ABIDataTypes.UINT256 },
    )
    private _getPosition(calldata: Calldata): BytesWriter {
        const user: Address = calldata.readAddress();
        const col: u256 = this._userCollateral.get(user);
        // H-7: convert shares to actual debt for display
        const shares: u256 = this._userDebt.get(user);
        const debt: u256 = this._sharesToDebt(shares);

        const writer: BytesWriter = new BytesWriter(64);
        writer.writeU256(col);
        writer.writeU256(debt);
        return writer;
    }

    @method({ name: 'user', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'ltv', type: ABIDataTypes.UINT256 })
    private _getPositionLTV(calldata: Calldata): BytesWriter {
        const user: Address = calldata.readAddress();
        const col: u256 = this._userCollateral.get(user);
        // H-7: convert shares to actual debt
        const shares: u256 = this._userDebt.get(user);
        const debt: u256 = this._sharesToDebt(shares);

        let ltv: u256 = u256.Zero;
        if (!col.isZero() && !debt.isZero()) {
            const colValueMIF: u256 = this._collateralToMIF(col);
            if (!colValueMIF.isZero()) {
                ltv = SafeMath.div(SafeMath.mul(debt, BPS_PRECISION), colValueMIF);
            }
        }

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(ltv);
        return writer;
    }

    @method({ name: 'user', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'liquidatable', type: ABIDataTypes.BOOL })
    private _isLiquidatable(calldata: Calldata): BytesWriter {
        const user: Address = calldata.readAddress();
        const col: u256 = this._userCollateral.get(user);
        // H-7: convert shares to actual debt
        const shares: u256 = this._userDebt.get(user);
        const debt: u256 = this._sharesToDebt(shares);

        let liquidatable: bool = false;
        if (!col.isZero() && !debt.isZero()) {
            const colValueMIF: u256 = this._collateralToMIF(col);
            if (!colValueMIF.isZero()) {
                const ltv: u256 = SafeMath.div(
                    SafeMath.mul(debt, BPS_PRECISION),
                    colValueMIF,
                );
                liquidatable = u256.gt(ltv, LIQUIDATION_BPS);
            } else {
                liquidatable = true; // no collateral value = liquidatable
            }
        }

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(liquidatable);
        return writer;
    }

    @method()
    @returns({ name: 'rate', type: ABIDataTypes.UINT256 })
    private _getInterestRate(_calldata: Calldata): BytesWriter {
        const utilBPS: u256 = this._getUtilizationBPS();
        const rate: u256 = this._calculateInterestRate(utilBPS);
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(rate);
        return writer;
    }

    @method()
    @returns({ name: 'total', type: ABIDataTypes.UINT256 })
    private _totalCollateralView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._totalCollateral.get());
        return writer;
    }

    @method()
    @returns({ name: 'total', type: ABIDataTypes.UINT256 })
    private _totalDebtView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._totalDebt.get());
        return writer;
    }

    @method()
    @returns({ name: 'fees', type: ABIDataTypes.UINT256 })
    private _accruedFeesView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._accruedFees.get());
        return writer;
    }

    // C-2: BTC penalties view
    @method()
    @returns({ name: 'penalties', type: ABIDataTypes.UINT256 })
    private _accruedBTCPenaltiesView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._accruedBTCPenalties.get());
        return writer;
    }

    // -----------------------------------------------------------------------
    // Admin Functions
    // -----------------------------------------------------------------------

    @method({ name: 'cap', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setBorrowCap(calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        const cap: u256 = calldata.readU256();
        this._totalBorrowCap.set(cap);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _pause(_calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        this._paused.value = true;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _unpause(_calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        this._paused.value = false;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // M-5: All admin setters use Address.zero() instead of Address.dead()
    @method({ name: 'oracle', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setOracle(calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        const oracle: Address = calldata.readAddress();
        if (oracle.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_ZERO_ADDR);
        }
        this._oracleAddr.set(this._addressToU256(oracle));
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // H-6: Two-step admin transfer — sets pending, doesn't transfer immediately
    @method({ name: 'newAdmin', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _transferAdmin(calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        const newAdmin: Address = calldata.readAddress();
        if (newAdmin.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_PENDING_ADMIN_ZERO);
        }
        this._pendingAdmin.set(this._addressToU256(newAdmin));

        this.emitEvent(new AdminTransferInitiatedEvent(this._getAdmin(), newAdmin));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // H-6: Accept admin role — only callable by pending admin
    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _acceptAdmin(_calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        const pendingAdminVal: u256 = this._pendingAdmin.get();
        if (pendingAdminVal.isZero()) {
            throw new Revert(ERR_CAULDRON_PENDING_ADMIN_ZERO);
        }
        const pendingAdmin: Address = this._u256ToAddress(pendingAdminVal);
        if (!sender.equals(pendingAdmin)) {
            throw new Revert(ERR_CAULDRON_NOT_PENDING_ADMIN);
        }
        this._adminAddr.set(pendingAdminVal);
        this._pendingAdmin.set(u256.Zero);

        this.emitEvent(new AdminTransferAcceptedEvent(sender));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // C-2: Distribute BTC penalties — admin only, returns amount for extraOutputs
    @method()
    @returns({ name: 'amount', type: ABIDataTypes.UINT256 })
    private _distributeBTCPenalties(_calldata: Calldata): BytesWriter {
        this._onlyAdmin();

        const amount: u256 = this._accruedBTCPenalties.get();
        if (amount.isZero()) {
            throw new Revert(ERR_CAULDRON_NO_BTC_PENALTIES);
        }

        this._accruedBTCPenalties.set(u256.Zero);

        this.emitEvent(new BTCPenaltiesDistributedEvent(amount));

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(amount);
        return writer;
    }

    @method({ name: 'mif', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setMIF(calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        const mif: Address = calldata.readAddress();
        if (mif.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_ZERO_ADDR);
        }
        this._mifAddr.set(this._addressToU256(mif));
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'nft', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setNFT(calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        const nft: Address = calldata.readAddress();
        if (nft.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_ZERO_ADDR);
        }
        this._nftAddr.set(this._addressToU256(nft));
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'fren', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setFREN(calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        const fren: Address = calldata.readAddress();
        if (fren.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_ZERO_ADDR);
        }
        this._frenAddr.set(this._addressToU256(fren));
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }
}
