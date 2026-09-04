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
    BLOCKS_PER_DAY,
    BASE_RATE,
    KINK_RATE,
    KINK_UTILIZATION,
    MAX_RATE,
    REENTRANCY_UNLOCKED,
    REENTRANCY_LOCKED,
    INITIAL_TCR_BPS,
    TCR_FLOOR_BPS,
    TCR_CEILING_BPS,
    TCR_DAILY_MAX_DELTA_BPS,
    CIRCUIT_BREAKER_DROP_BPS,
    CIRCUIT_BREAKER_RESUME_BLOCKS,
    FREN_DAILY_MINT_CAP_BPS,
    MINT_REDEEM_FEE_BPS,
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
    ERR_CAULDRON_CIRCUIT_BREAKER,
    ERR_CAULDRON_TCR_COOLDOWN,
    ERR_CAULDRON_TCR_DELTA_TOO_LARGE,
    ERR_CAULDRON_TCR_BELOW_FLOOR,
    ERR_CAULDRON_TCR_ABOVE_CEILING,
    ERR_CAULDRON_FREN_MINT_CAP,
    ERR_CAULDRON_INSUFFICIENT_BTC,
    ERR_CAULDRON_INSUFFICIENT_FREN,
    ERR_CAULDRON_INSUFFICIENT_MIF,
    ERR_CAULDRON_FREN_PRICE_ZERO,
    ERR_CAULDRON_RESERVE_DEPLETED,
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
import {
    MintMIFEvent,
    RedeemMIFEvent,
    TCRAdjustedEvent,
    CircuitBreakerTrippedEvent,
    CircuitBreakerResumedEvent,
} from '../events/MintRedeemEvents';

/**
 * CauldronV2 -- Algorithmic Stablecoin + CDP Lending Market.
 *
 * Extends the original Cauldron with:
 *   - mintMIF(): deposit BTC (TCR%) + burn FREN (1-TCR%) -> mint MIF
 *   - redeemMIF(): burn MIF -> receive BTC (ECR%) + freshly minted FREN (1-ECR%)
 *   - TCR/ECR management, circuit breaker, daily FREN mint cap
 *
 * The BTC reserve for MIF backing is SEPARATE from CDP collateral.
 */
@final
export class CauldronV2 extends OP_NET {
    // -----------------------------------------------------------------------
    // Storage Pointers (0-13: identical to Cauldron)
    // -----------------------------------------------------------------------

    private readonly adminAddrPointer: u16 = Blockchain.nextPointer;         // 0
    private readonly oracleAddrPointer: u16 = Blockchain.nextPointer;        // 1
    private readonly mifAddrPointer: u16 = Blockchain.nextPointer;           // 2
    private readonly nftAddrPointer: u16 = Blockchain.nextPointer;           // 3
    private readonly frenAddrPointer: u16 = Blockchain.nextPointer;          // 4

    private readonly totalCollateralPointer: u16 = Blockchain.nextPointer;   // 5
    private readonly totalDebtPointer: u16 = Blockchain.nextPointer;         // 6
    private readonly totalBorrowCapPointer: u16 = Blockchain.nextPointer;    // 7
    private readonly accruedFeesPointer: u16 = Blockchain.nextPointer;       // 8
    private readonly lastAccruePointer: u16 = Blockchain.nextPointer;        // 9
    private readonly reentrancyPointer: u16 = Blockchain.nextPointer;        // 10
    private readonly pausedPointer: u16 = Blockchain.nextPointer;            // 11

    private readonly userCollateralPointer: u16 = Blockchain.nextPointer;    // 12
    private readonly userDebtPointer: u16 = Blockchain.nextPointer;          // 13

    // --- CauldronV2 new storage pointers (14-25) ---

    private readonly tcrBpsPointer: u16 = Blockchain.nextPointer;            // 14
    private readonly lastTCRAdjustTsPointer: u16 = Blockchain.nextPointer;   // 15
    private readonly totalBTCReservePointer: u16 = Blockchain.nextPointer;   // 16
    private readonly frenOracleAddrPointer: u16 = Blockchain.nextPointer;    // 17
    private readonly circuitBreakerActivePointer: u16 = Blockchain.nextPointer; // 18
    private readonly circuitBreakerBlockPointer: u16 = Blockchain.nextPointer;  // 19
    private readonly frenRefPricePointer: u16 = Blockchain.nextPointer;      // 20
    private readonly dailyFrenMintedPointer: u16 = Blockchain.nextPointer;   // 21
    private readonly dailyMintDayPointer: u16 = Blockchain.nextPointer;      // 22
    private readonly dailyCapBaseSupplyPointer: u16 = Blockchain.nextPointer; // 23
    private readonly totalMIFSupplyPointer: u16 = Blockchain.nextPointer;    // 24
    private readonly mintRedeemFeesPointer: u16 = Blockchain.nextPointer;    // 25

    // Audit fix storage pointers
    private readonly accruedBTCPenaltiesPointer: u16 = Blockchain.nextPointer; // 26
    private readonly pendingAdminPointer: u16 = Blockchain.nextPointer;        // 27
    private readonly totalDebtSharesPointer: u16 = Blockchain.nextPointer;     // 28

    // -----------------------------------------------------------------------
    // Storage Instances -- CDP (inherited from Cauldron)
    // -----------------------------------------------------------------------

    private readonly _adminAddr: StoredU256;
    private readonly _oracleAddr: StoredU256;
    private readonly _mifAddr: StoredU256;
    private readonly _nftAddr: StoredU256;
    private readonly _frenAddr: StoredU256;

    private readonly _totalCollateral: StoredU256;
    private readonly _totalDebt: StoredU256;
    private readonly _totalBorrowCap: StoredU256;
    private readonly _accruedFees: StoredU256;
    private readonly _lastAccrueTs: StoredU64;
    private readonly _reentrancyGuard: StoredU256;
    private readonly _paused: StoredBoolean;

    private readonly _userCollateral: AddressMemoryMap;
    private readonly _userDebt: AddressMemoryMap; // H-7: stores debt SHARES, not raw debt

    // -----------------------------------------------------------------------
    // Storage Instances -- Algorithmic Stablecoin (new)
    // -----------------------------------------------------------------------

    private readonly _tcrBps: StoredU256;
    private readonly _lastTCRAdjustTs: StoredU64;
    private readonly _totalBTCReserve: StoredU256;
    private readonly _frenOracleAddr: StoredU256;
    private readonly _circuitBreakerActive: StoredBoolean;
    private readonly _circuitBreakerBlock: StoredU256;
    private readonly _frenRefPrice: StoredU256;
    private readonly _dailyFrenMinted: StoredU256;
    private readonly _dailyMintDay: StoredU256;
    private readonly _dailyCapBaseSupply: StoredU256;
    private readonly _totalMIFSupply: StoredU256;
    private readonly _mintRedeemFees: StoredU256;

    // Audit fix storage
    private readonly _accruedBTCPenalties: StoredU256;  // C-2: separate BTC penalty pool
    private readonly _pendingAdmin: StoredU256;          // H-6: two-step admin transfer
    private readonly _totalDebtShares: StoredU256;       // H-7: total debt shares outstanding

    // -----------------------------------------------------------------------
    // Cross-contract selectors
    // -----------------------------------------------------------------------

    private readonly ORACLE_GET_PRICE: u32 = encodeSelector('getPrice()');
    private readonly MIF_MINT: u32 = encodeSelector('mint(address,uint256)');
    private readonly MIF_BURN: u32 = encodeSelector('burn(uint256)');
    private readonly NFT_OWNER_OF: u32 = encodeSelector('ownerOf(uint256)');
    // getTier removed — borrow/grace are now class-based (getMaxBorrow, getLiquidationGrace)
    private readonly NFT_GET_TAX_RATE: u32 = encodeSelector('getTaxRate(uint256)');
    private readonly FREN_DISTRIBUTE: u32 = encodeSelector('distributeReward(uint256)');
    private readonly FREN_MINT: u32 = encodeSelector('mintFREN(address,uint256)');
    private readonly FREN_BURN_FROM: u32 = encodeSelector('burn(uint256)');
    private readonly FREN_TOTAL_SUPPLY: u32 = encodeSelector('totalSupply()');
    private readonly MIF_BURN_FROM: u32 = encodeSelector('burnFrom(address,uint256)');
    private readonly FREN_BURN_FROM_ADDR: u32 = encodeSelector('burnFrom(address,uint256)');

    // -----------------------------------------------------------------------
    // Method Selectors -- CDP (inherited)
    // -----------------------------------------------------------------------

    private readonly depositSelector: Selector = encodeSelector('deposit(uint256)');
    private readonly borrowSelector: Selector = encodeSelector('borrow(uint256)');
    private readonly repaySelector: Selector = encodeSelector('repay(uint256)');
    private readonly withdrawSelector: Selector = encodeSelector('withdraw(uint256)');
    private readonly liquidateSelector: Selector = encodeSelector('liquidate(address)');
    private readonly accrueSelector: Selector = encodeSelector('accrue()');
    private readonly distributeFeesSelector: Selector = encodeSelector('distributeFees()');

    private readonly getPositionSelector: Selector = encodeSelector('getPosition(address)');
    private readonly getPositionLTVSelector: Selector = encodeSelector('getPositionLTV(address)');
    private readonly isLiquidatableSelector: Selector = encodeSelector('isLiquidatable(address)');
    private readonly getInterestRateSelector: Selector = encodeSelector('getCurrentInterestRate()');
    private readonly totalCollateralSelector: Selector = encodeSelector('totalCollateral()');
    private readonly totalDebtSelector: Selector = encodeSelector('totalDebt()');
    private readonly accruedFeesSelector: Selector = encodeSelector('accruedFees()');

    private readonly setBorrowCapSelector: Selector = encodeSelector('setTotalBorrowCap(uint256)');
    private readonly pauseSelector: Selector = encodeSelector('pause()');
    private readonly unpauseSelector: Selector = encodeSelector('unpause()');
    private readonly setOracleSelector: Selector = encodeSelector('setOracle(address)');
    private readonly transferAdminSelector: Selector = encodeSelector('transferAdmin(address)');
    private readonly acceptAdminSelector: Selector = encodeSelector('acceptAdmin()');
    private readonly distributeBTCPenaltiesSelector: Selector = encodeSelector('distributeBTCPenalties()');
    private readonly accruedBTCPenaltiesSelector: Selector = encodeSelector('accruedBTCPenalties()');
    private readonly setMifSelector: Selector = encodeSelector('setMIFToken(address)');
    private readonly setNftSelector: Selector = encodeSelector('setNFTContract(address)');
    private readonly setFrenSelector: Selector = encodeSelector('setFRENToken(address)');

    // -----------------------------------------------------------------------
    // Method Selectors -- Algorithmic Stablecoin (new)
    // -----------------------------------------------------------------------

    private readonly mintMIFSelector: Selector = encodeSelector('mintMIF(uint256)');
    private readonly redeemMIFSelector: Selector = encodeSelector('redeemMIF(uint256)');

    private readonly getTCRSelector: Selector = encodeSelector('getTCR()');
    private readonly getECRSelector: Selector = encodeSelector('getECR()');
    private readonly totalBTCReserveSelector: Selector = encodeSelector('totalBTCReserve()');
    private readonly totalMIFMintedSelector: Selector = encodeSelector('totalMIFMinted()');
    private readonly isCircuitBreakerActiveSelector: Selector = encodeSelector('isCircuitBreakerActive()');
    private readonly getDailyFRENMintedSelector: Selector = encodeSelector('getDailyFRENMinted()');
    private readonly getDailyFRENMintCapSelector: Selector = encodeSelector('getDailyFRENMintCap()');
    private readonly getFRENPriceSelector: Selector = encodeSelector('getFRENPrice()');
    private readonly getMintInfoSelector: Selector = encodeSelector('getMintInfo(uint256)');
    private readonly getRedeemInfoSelector: Selector = encodeSelector('getRedeemInfo(uint256)');
    private readonly mintRedeemFeesSelector: Selector = encodeSelector('mintRedeemFees()');

    private readonly setTCRSelector: Selector = encodeSelector('setTCR(uint256)');
    private readonly setFRENOracleSelector: Selector = encodeSelector('setFRENOracle(address)');
    private readonly tripCircuitBreakerSelector: Selector = encodeSelector('tripCircuitBreaker()');
    private readonly resumeCircuitBreakerSelector: Selector = encodeSelector('resumeCircuitBreaker()');

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    public constructor() {
        super();

        // CDP storage
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

        // Algorithmic stablecoin storage
        this._tcrBps = new StoredU256(this.tcrBpsPointer, INITIAL_TCR_BPS);
        this._lastTCRAdjustTs = new StoredU64(this.lastTCRAdjustTsPointer, 0);
        this._totalBTCReserve = new StoredU256(this.totalBTCReservePointer, u256.Zero);
        this._frenOracleAddr = new StoredU256(this.frenOracleAddrPointer, u256.Zero);
        this._circuitBreakerActive = new StoredBoolean(this.circuitBreakerActivePointer, false);
        this._circuitBreakerBlock = new StoredU256(this.circuitBreakerBlockPointer, u256.Zero);
        this._frenRefPrice = new StoredU256(this.frenRefPricePointer, u256.Zero);
        this._dailyFrenMinted = new StoredU256(this.dailyFrenMintedPointer, u256.Zero);
        this._dailyMintDay = new StoredU256(this.dailyMintDayPointer, u256.Zero);
        this._dailyCapBaseSupply = new StoredU256(this.dailyCapBaseSupplyPointer, u256.Zero);
        this._totalMIFSupply = new StoredU256(this.totalMIFSupplyPointer, u256.Zero);
        this._mintRedeemFees = new StoredU256(this.mintRedeemFeesPointer, u256.Zero);

        // Audit fix storage
        this._accruedBTCPenalties = new StoredU256(this.accruedBTCPenaltiesPointer, u256.Zero);
        this._pendingAdmin = new StoredU256(this.pendingAdminPointer, u256.Zero);
        this._totalDebtShares = new StoredU256(this.totalDebtSharesPointer, u256.Zero);
    }

    // -----------------------------------------------------------------------
    // Deployment
    // -----------------------------------------------------------------------

    public override onDeployment(calldata: Calldata): void {
        const oracle: Address = calldata.readAddress();
        const mif: Address = calldata.readAddress();
        const nft: Address = calldata.readAddress();
        const fren: Address = calldata.readAddress();
        const frenOracle: Address = calldata.readAddress();

        const deployer: Address = Blockchain.tx.sender;
        this._adminAddr.set(this._addressToU256(deployer));
        this._oracleAddr.set(this._addressToU256(oracle));
        this._mifAddr.set(this._addressToU256(mif));
        this._nftAddr.set(this._addressToU256(nft));
        this._frenAddr.set(this._addressToU256(fren));
        this._frenOracleAddr.set(this._addressToU256(frenOracle));

        this._lastAccrueTs.set(Blockchain.block.number);
        this._reentrancyGuard.set(REENTRANCY_UNLOCKED);
        this._tcrBps.set(INITIAL_TCR_BPS);
        this._lastTCRAdjustTs.set(Blockchain.block.number);
    }

    // -----------------------------------------------------------------------
    // callMethod Router
    // -----------------------------------------------------------------------

    public override callMethod(calldata: Calldata): BytesWriter {
        const selector: Selector = calldata.readSelector();

        switch (selector) {
            // --- CDP operations (inherited) ---
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

            // CDP views
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

            // CDP admin
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

            // --- Algorithmic stablecoin operations (new) ---
            case this.mintMIFSelector:
                return this._mintMIF(calldata);
            case this.redeemMIFSelector:
                return this._redeemMIF(calldata);

            // Algo views
            case this.getTCRSelector:
                return this._getTCRView(calldata);
            case this.getECRSelector:
                return this._getECRView(calldata);
            case this.totalBTCReserveSelector:
                return this._totalBTCReserveView(calldata);
            case this.totalMIFMintedSelector:
                return this._totalMIFMintedView(calldata);
            case this.isCircuitBreakerActiveSelector:
                return this._isCircuitBreakerActiveView(calldata);
            case this.getDailyFRENMintedSelector:
                return this._getDailyFRENMintedView(calldata);
            case this.getDailyFRENMintCapSelector:
                return this._getDailyFRENMintCapView(calldata);
            case this.getFRENPriceSelector:
                return this._getFRENPriceView(calldata);
            case this.getMintInfoSelector:
                return this._getMintInfo(calldata);
            case this.getRedeemInfoSelector:
                return this._getRedeemInfo(calldata);
            case this.mintRedeemFeesSelector:
                return this._mintRedeemFeesView(calldata);

            // Algo admin
            case this.setTCRSelector:
                return this._setTCR(calldata);
            case this.setFRENOracleSelector:
                return this._setFRENOracle(calldata);
            case this.tripCircuitBreakerSelector:
                return this._tripCircuitBreaker(calldata);
            case this.resumeCircuitBreakerSelector:
                return this._resumeCircuitBreaker(calldata);

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

    private _getFRENOracle(): Address {
        return this._u256ToAddress(this._frenOracleAddr.get());
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

    private _whenCircuitBreakerInactive(): void {
        if (this._circuitBreakerActive.value) {
            // Check auto-resume: if enough blocks have passed, resume
            const trippedBlock: u256 = this._circuitBreakerBlock.get();
            const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
            const elapsed: u256 = SafeMath.sub(currentBlock, trippedBlock);

            if (u256.ge(elapsed, CIRCUIT_BREAKER_RESUME_BLOCKS)) {
                this._circuitBreakerActive.value = false;
                this.emitEvent(new CircuitBreakerResumedEvent(currentBlock));
            } else {
                throw new Revert(ERR_CAULDRON_CIRCUIT_BREAKER);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Cross-Contract Calls
    // -----------------------------------------------------------------------

    private _getOraclePrice(): u256 {
        const oracle: Address = this._getOracle();
        const writer: BytesWriter = new BytesWriter(4);
        writer.writeSelector(this.ORACLE_GET_PRICE);
        const result: CallResult = Blockchain.call(oracle, writer, true);
        return result.readU256();
    }

    private _getFRENOraclePrice(): u256 {
        const frenOracle: Address = this._getFRENOracle();
        const writer: BytesWriter = new BytesWriter(4);
        writer.writeSelector(this.ORACLE_GET_PRICE);
        const result: CallResult = Blockchain.call(frenOracle, writer, true);
        const price: u256 = result.readU256();
        if (price.isZero()) {
            throw new Revert(ERR_CAULDRON_FREN_PRICE_ZERO);
        }
        return price;
    }

    private _callMIFMint(to: Address, amount: u256): void {
        const mif: Address = this._getMIF();
        const writer: BytesWriter = new BytesWriter(68);
        writer.writeSelector(this.MIF_MINT);
        writer.writeAddress(to);
        writer.writeU256(amount);
        Blockchain.call(mif, writer, true);
    }

    private _callFRENMint(to: Address, amount: u256): void {
        const fren: Address = this._getFREN();
        const writer: BytesWriter = new BytesWriter(68);
        writer.writeSelector(this.FREN_MINT);
        writer.writeAddress(to);
        writer.writeU256(amount);
        Blockchain.call(fren, writer, true);
    }

    private _callFRENTotalSupply(): u256 {
        const fren: Address = this._getFREN();
        const writer: BytesWriter = new BytesWriter(4);
        writer.writeSelector(this.FREN_TOTAL_SUPPLY);
        const result: CallResult = Blockchain.call(fren, writer, true);
        return result.readU256();
    }

    /** Call NFT.getTaxRate(tokenId) -> u256 tax rate BPS */
    private _callNFTGetTaxRate(tokenId: u256): u256 {
        const nft: Address = this._getNFT();
        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(this.NFT_GET_TAX_RATE);
        writer.writeU256(tokenId);
        const result: CallResult = Blockchain.call(nft, writer, true);
        return result.readU256();
    }

    private _callFRENDistribute(amount: u256): void {
        const fren: Address = this._getFREN();
        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(this.FREN_DISTRIBUTE);
        writer.writeU256(amount);
        Blockchain.call(fren, writer, true);
    }

    /** Call MIF.burnFrom(from, amount) */
    private _callMIFBurnFrom(from: Address, amount: u256): void {
        const mif: Address = this._getMIF();
        const writer: BytesWriter = new BytesWriter(68);
        writer.writeSelector(this.MIF_BURN_FROM);
        writer.writeAddress(from);
        writer.writeU256(amount);
        Blockchain.call(mif, writer, true);
    }

    /** Call FREN.burnFrom(from, amount) */
    private _callFRENBurnFrom(from: Address, amount: u256): void {
        const fren: Address = this._getFREN();
        const writer: BytesWriter = new BytesWriter(68);
        writer.writeSelector(this.FREN_BURN_FROM_ADDR);
        writer.writeAddress(from);
        writer.writeU256(amount);
        Blockchain.call(fren, writer, true);
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

    // -----------------------------------------------------------------------
    // Oracle: Collateral Valuation
    // -----------------------------------------------------------------------

    private _collateralToMIF(collateralSats: u256): u256 {
        if (collateralSats.isZero()) return u256.Zero;
        const btcPrice: u256 = this._getOraclePrice();
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

    private _calculateInterestRate(utilizationBPS: u256): u256 {
        if (u256.le(utilizationBPS, KINK_UTILIZATION)) {
            const spread: u256 = SafeMath.sub(KINK_RATE, BASE_RATE);
            return SafeMath.add(
                BASE_RATE,
                SafeMath.div(SafeMath.mul(spread, utilizationBPS), KINK_UTILIZATION),
            );
        } else {
            const excess: u256 = SafeMath.sub(utilizationBPS, KINK_UTILIZATION);
            const range: u256 = SafeMath.sub(BPS_PRECISION, KINK_UTILIZATION);
            const spread: u256 = SafeMath.sub(MAX_RATE, KINK_RATE);
            const excessSq: u256 = SafeMath.mul(excess, excess);
            const rangeSq: u256 = SafeMath.mul(range, range);
            return SafeMath.add(
                KINK_RATE,
                SafeMath.div(SafeMath.mul(excessSq, spread), rangeSq),
            );
        }
    }

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

        const numerator: u256 = SafeMath.mul(SafeMath.mul(totalDebt, rateBPS), elapsedBlocks);
        const denominator: u256 = SafeMath.mul(BPS_PRECISION, BLOCKS_PER_YEAR);
        const interest: u256 = SafeMath.div(numerator, denominator);

        if (!interest.isZero()) {
            this._totalDebt.set(SafeMath.add(totalDebt, interest));
            this._accruedFees.set(SafeMath.add(this._accruedFees.get(), interest));
            this.emitEvent(new AccrueEvent(interest, currentBlock));
        }

        this._lastAccrueTs.set(currentBlock);
    }

    // =======================================================================
    // CDP Core Operations (identical logic to Cauldron)
    // =======================================================================

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

        this._accrueInterest();

        const currentCol: u256 = this._userCollateral.get(sender);
        this._userCollateral.set(sender, SafeMath.add(currentCol, amount));
        this._totalCollateral.set(SafeMath.add(this._totalCollateral.get(), amount));

        this.emitEvent(new DepositEvent(sender, amount));
        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

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

        this._accrueInterest();

        const openingFee: u256 = SafeMath.div(SafeMath.mul(amount, BORROW_FEE_BPS), BPS_PRECISION);
        const totalDebtIncrease: u256 = SafeMath.add(amount, openingFee);

        // H-7: Calculate new shares for this debt increase
        const totalDebt: u256 = this._totalDebt.get();
        const totalShares: u256 = this._totalDebtShares.get();
        let newShares: u256;
        if (totalShares.isZero() || totalDebt.isZero()) {
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

        const newTotalDebt: u256 = SafeMath.add(totalDebt, totalDebtIncrease);
        const newTotalShares: u256 = SafeMath.add(totalShares, newShares);
        const actualUserDebt: u256 = SafeMath.div(
            SafeMath.mul(updatedShares, newTotalDebt), newTotalShares,
        );
        const currentLTV: u256 = SafeMath.div(SafeMath.mul(actualUserDebt, BPS_PRECISION), colValueMIF);
        if (u256.gt(currentLTV, LTV_BPS)) {
            throw new Revert(ERR_CAULDRON_EXCEEDS_LTV);
        }

        // Update global state
        this._totalDebt.set(newTotalDebt);
        this._totalDebtShares.set(newTotalShares);

        const borrowCap: u256 = this._totalBorrowCap.get();
        if (!borrowCap.isZero() && u256.gt(newTotalDebt, borrowCap)) {
            throw new Revert(ERR_CAULDRON_EXCEEDS_BORROW_CAP);
        }

        this._accruedFees.set(SafeMath.add(this._accruedFees.get(), openingFee));
        this._callMIFMint(sender, amount);

        this.emitEvent(new BorrowEvent(sender, amount, openingFee));
        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

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

        this._accrueInterest();

        // H-7: read shares and convert to actual debt
        const currentShares: u256 = this._userDebt.get(sender);
        if (currentShares.isZero()) {
            throw new Revert(ERR_CAULDRON_NO_DEBT);
        }
        const actualDebt: u256 = this._sharesToDebt(currentShares);

        let repayAmount: u256;
        let sharesToBurn: u256;
        if (u256.ge(amount, actualDebt)) {
            repayAmount = actualDebt;
            sharesToBurn = currentShares;
        } else {
            repayAmount = amount;
            const totalDebt: u256 = this._totalDebt.get();
            const totalShares: u256 = this._totalDebtShares.get();
            sharesToBurn = SafeMath.div(SafeMath.mul(repayAmount, totalShares), totalDebt);
        }

        this._userDebt.set(sender, SafeMath.sub(currentShares, sharesToBurn));
        this._totalDebt.set(SafeMath.sub(this._totalDebt.get(), repayAmount));
        this._totalDebtShares.set(SafeMath.sub(this._totalDebtShares.get(), sharesToBurn));

        this._callMIFBurnFrom(sender, repayAmount);

        this.emitEvent(new RepayEvent(sender, repayAmount));
        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

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

        this._accrueInterest();

        const currentCol: u256 = this._userCollateral.get(sender);
        if (u256.gt(amount, currentCol)) {
            throw new Revert(ERR_CAULDRON_INSUFFICIENT_COL);
        }

        const newCol: u256 = SafeMath.sub(currentCol, amount);
        this._userCollateral.set(sender, newCol);

        // H-7: convert shares to actual debt for LTV check
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

        this._totalCollateral.set(SafeMath.sub(this._totalCollateral.get(), amount));
        this.emitEvent(new WithdrawEvent(sender, amount));
        this._nonReentrant_exit();

        // C-3: return amount for frontend extraOutputs
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(amount);
        return writer;
    }

    @method({ name: 'user', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'collateralOut', type: ABIDataTypes.UINT256 })
    private _liquidate(calldata: Calldata): BytesWriter {
        this._nonReentrant_enter();
        this._whenNotPaused();

        const liquidator: Address = Blockchain.tx.sender;
        const user: Address = calldata.readAddress();

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

        const colValueMIF: u256 = this._collateralToMIF(userCol);
        const currentLTV: u256 = SafeMath.div(
            SafeMath.mul(userDebt, BPS_PRECISION),
            colValueMIF,
        );
        if (u256.le(currentLTV, LIQUIDATION_BPS)) {
            throw new Revert(ERR_CAULDRON_HEALTHY);
        }

        const penaltyAmount: u256 = SafeMath.div(
            SafeMath.mul(userCol, LIQUIDATION_PENALTY_BPS),
            BPS_PRECISION,
        );
        const collateralToLiquidator: u256 = SafeMath.sub(userCol, penaltyAmount);

        this._userCollateral.set(user, u256.Zero);
        this._userDebt.set(user, u256.Zero);

        this._totalCollateral.set(SafeMath.sub(this._totalCollateral.get(), userCol));
        this._totalDebt.set(SafeMath.sub(this._totalDebt.get(), userDebt));
        this._totalDebtShares.set(SafeMath.sub(this._totalDebtShares.get(), userShares));

        // C-2: BTC penalty goes to separate pool (not MIF accrued fees)
        this._accruedBTCPenalties.set(
            SafeMath.add(this._accruedBTCPenalties.get(), penaltyAmount),
        );

        this._callMIFBurnFrom(liquidator, userDebt);

        this.emitEvent(new LiquidateEvent(liquidator, user, userDebt, collateralToLiquidator));
        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(collateralToLiquidator);
        return writer;
    }

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _accruePublic(_calldata: Calldata): BytesWriter {
        this._accrueInterest();
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _distributeFees(_calldata: Calldata): BytesWriter {
        this._onlyAdmin();

        const fees: u256 = this._accruedFees.get();
        if (fees.isZero()) {
            throw new Revert(ERR_CAULDRON_NO_FEES);
        }

        this._accruedFees.set(u256.Zero);
        this._callFRENDistribute(fees);
        this.emitEvent(new FeesDistributedEvent(fees));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // =======================================================================
    // Algorithmic Stablecoin -- Mint & Redeem
    // =======================================================================

    /**
     * mintMIF(mifAmount): Deposit BTC (TCR%) + burn FREN (1-TCR%) -> mint MIF.
     *
     * BTC needed = mifAmount * TCR / BPS / btcPrice * SATS_PER_BTC
     * FREN needed = mifAmount * (BPS - TCR) / BPS / frenPrice * 1e18
     * Fee = 0.3% of mifAmount
     */
    @method({ name: 'mifAmount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _mintMIF(calldata: Calldata): BytesWriter {
        this._nonReentrant_enter();
        this._whenNotPaused();
        this._whenCircuitBreakerInactive();

        const sender: Address = Blockchain.tx.sender;
        const mifAmount: u256 = calldata.readU256();

        if (mifAmount.isZero()) {
            throw new Revert(ERR_CAULDRON_ZERO_AMOUNT);
        }

        // Calculate fee
        const fee: u256 = SafeMath.div(SafeMath.mul(mifAmount, MINT_REDEEM_FEE_BPS), BPS_PRECISION);

        // Get prices
        const btcPrice: u256 = this._getOraclePrice();   // 18 decimals (USD per BTC)
        const frenPrice: u256 = this._getFRENOraclePrice(); // 18 decimals (USD per FREN)
        const tcr: u256 = this._tcrBps.get();

        // H-5 fix: multiply all numerators first, then divide by product of denominators
        // btcNeeded = mifAmount * tcr * SATS_PER_BTC / (BPS_PRECISION * btcPrice)
        const btcNeeded: u256 = SafeMath.div(
            SafeMath.mul(SafeMath.mul(mifAmount, tcr), SATS_PER_BTC),
            SafeMath.mul(BPS_PRECISION, btcPrice),
        );

        // frenNeeded = mifAmount * frenFraction * PRECISION_18 / (BPS_PRECISION * frenPrice)
        const frenFraction: u256 = SafeMath.sub(BPS_PRECISION, tcr);
        const frenNeeded: u256 = SafeMath.div(
            SafeMath.mul(SafeMath.mul(mifAmount, frenFraction), PRECISION_18),
            SafeMath.mul(BPS_PRECISION, frenPrice),
        );

        // Verify BTC was actually sent to this contract in the transaction
        this._verifyBTCDeposit(btcNeeded);

        // Burn FREN from the sender (enforced via cross-contract call)
        if (!frenNeeded.isZero()) {
            this._callFRENBurnFrom(sender, frenNeeded);
        }

        // Update BTC reserve (separate from CDP collateral pool)
        const currentReserve: u256 = this._totalBTCReserve.get();
        this._totalBTCReserve.set(SafeMath.add(currentReserve, btcNeeded));

        // Track fees
        this._mintRedeemFees.set(SafeMath.add(this._mintRedeemFees.get(), fee));

        // Update total MIF minted via algo mechanism
        this._totalMIFSupply.set(SafeMath.add(this._totalMIFSupply.get(), mifAmount));

        // Mint MIF to user (minus fee)
        const mifToUser: u256 = SafeMath.sub(mifAmount, fee);
        this._callMIFMint(sender, mifToUser);

        this.emitEvent(new MintMIFEvent(sender, btcNeeded, frenNeeded, mifToUser, tcr));
        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * redeemMIF(mifAmount): Burn MIF -> receive BTC (ECR%) + freshly minted FREN (1-ECR%).
     *
     * ECR = (totalBTCReserve * btcPrice / SATS_PER_BTC) * BPS / totalMIFSupply (capped at 100%)
     * BTC out = effectiveMif * ECR / BPS / btcPrice * SATS_PER_BTC
     * FREN out = effectiveMif * (BPS - ECR) / BPS / frenPrice * 1e18
     */
    @method({ name: 'mifAmount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _redeemMIF(calldata: Calldata): BytesWriter {
        this._nonReentrant_enter();
        this._whenNotPaused();
        this._whenCircuitBreakerInactive();

        const sender: Address = Blockchain.tx.sender;
        const mifAmount: u256 = calldata.readU256();

        if (mifAmount.isZero()) {
            throw new Revert(ERR_CAULDRON_ZERO_AMOUNT);
        }

        // Calculate fee
        const fee: u256 = SafeMath.div(SafeMath.mul(mifAmount, MINT_REDEEM_FEE_BPS), BPS_PRECISION);
        const effectiveMif: u256 = SafeMath.sub(mifAmount, fee);

        // Get prices
        const btcPrice: u256 = this._getOraclePrice();
        const frenPrice: u256 = this._getFRENOraclePrice();

        // Calculate ECR
        const ecr: u256 = this._calculateECR(btcPrice);

        // H-5 fix: multiply all numerators first, then divide by product of denominators
        // btcOut = effectiveMif * ecr * SATS_PER_BTC / (BPS_PRECISION * btcPrice)
        const btcOut: u256 = SafeMath.div(
            SafeMath.mul(SafeMath.mul(effectiveMif, ecr), SATS_PER_BTC),
            SafeMath.mul(BPS_PRECISION, btcPrice),
        );

        // Check reserve can cover BTC payout
        const currentReserve: u256 = this._totalBTCReserve.get();
        if (u256.gt(btcOut, currentReserve)) {
            throw new Revert(ERR_CAULDRON_RESERVE_DEPLETED);
        }

        // frenOut = effectiveMif * frenFraction * PRECISION_18 / (BPS_PRECISION * frenPrice)
        const frenFraction: u256 = SafeMath.sub(BPS_PRECISION, ecr);
        const frenOut: u256 = SafeMath.div(
            SafeMath.mul(SafeMath.mul(effectiveMif, frenFraction), PRECISION_18),
            SafeMath.mul(BPS_PRECISION, frenPrice),
        );

        // Enforce daily FREN mint cap
        this._enforceDailyFrenCap(frenOut);

        // Burn MIF from the redeemer before paying out
        this._callMIFBurnFrom(sender, mifAmount);

        // Update BTC reserve
        this._totalBTCReserve.set(SafeMath.sub(currentReserve, btcOut));

        // Track fees
        this._mintRedeemFees.set(SafeMath.add(this._mintRedeemFees.get(), fee));

        // Update total MIF supply
        const totalMIF: u256 = this._totalMIFSupply.get();
        if (u256.gt(mifAmount, totalMIF)) {
            this._totalMIFSupply.set(u256.Zero);
        } else {
            this._totalMIFSupply.set(SafeMath.sub(totalMIF, mifAmount));
        }

        // Mint FREN to redeemer (via cross-contract call to FREN.mintFREN)
        if (!frenOut.isZero()) {
            this._callFRENMint(sender, frenOut);
        }

        // BTC is returned to user via OP_NET transaction outputs
        // (caller sets up extraOutputs before sendTransaction)

        this.emitEvent(new RedeemMIFEvent(sender, mifAmount, btcOut, frenOut, ecr));
        this._nonReentrant_exit();

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // ECR Calculation
    // -----------------------------------------------------------------------

    private _calculateECR(btcPrice: u256): u256 {
        const totalMIF: u256 = this._totalMIFSupply.get();
        if (totalMIF.isZero()) return BPS_PRECISION; // 100% if no MIF minted

        const reserve: u256 = this._totalBTCReserve.get();
        if (reserve.isZero()) return u256.Zero;

        // reserveValueUSD = reserve * btcPrice / SATS_PER_BTC (18 decimals)
        const reserveValue: u256 = SafeMath.div(SafeMath.mul(reserve, btcPrice), SATS_PER_BTC);

        // ECR = reserveValue * BPS / totalMIF
        let ecr: u256 = SafeMath.div(SafeMath.mul(reserveValue, BPS_PRECISION), totalMIF);

        // Cap at 100%
        if (u256.gt(ecr, BPS_PRECISION)) {
            ecr = BPS_PRECISION;
        }

        return ecr;
    }

    // -----------------------------------------------------------------------
    // Daily FREN Mint Cap
    // -----------------------------------------------------------------------

    private _enforceDailyFrenCap(frenAmount: u256): void {
        const currentBlock: u64 = Blockchain.block.number;
        const currentDay: u256 = u256.fromU64(currentBlock / BLOCKS_PER_DAY);
        const lastDay: u256 = this._dailyMintDay.get();

        if (!u256.eq(currentDay, lastDay)) {
            // New day: reset counter and snapshot FREN total supply
            this._dailyMintDay.set(currentDay);
            this._dailyFrenMinted.set(u256.Zero);
            this._dailyCapBaseSupply.set(this._callFRENTotalSupply());
        }

        // Calculate cap: 2% of FREN supply at day start
        const baseSupply: u256 = this._dailyCapBaseSupply.get();
        const dailyCap: u256 = SafeMath.div(
            SafeMath.mul(baseSupply, FREN_DAILY_MINT_CAP_BPS),
            BPS_PRECISION,
        );

        const alreadyMinted: u256 = this._dailyFrenMinted.get();
        const newTotal: u256 = SafeMath.add(alreadyMinted, frenAmount);

        if (u256.gt(newTotal, dailyCap)) {
            throw new Revert(ERR_CAULDRON_FREN_MINT_CAP);
        }

        this._dailyFrenMinted.set(newTotal);
    }

    // =======================================================================
    // CDP View Functions
    // =======================================================================

    @method({ name: 'user', type: ABIDataTypes.ADDRESS })
    @returns(
        { name: 'collateral', type: ABIDataTypes.UINT256 },
        { name: 'debt', type: ABIDataTypes.UINT256 },
    )
    private _getPosition(calldata: Calldata): BytesWriter {
        const user: Address = calldata.readAddress();
        // H-7: convert shares to actual debt
        const shares: u256 = this._userDebt.get(user);
        const debt: u256 = this._sharesToDebt(shares);
        const writer: BytesWriter = new BytesWriter(64);
        writer.writeU256(this._userCollateral.get(user));
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
                const ltv: u256 = SafeMath.div(SafeMath.mul(debt, BPS_PRECISION), colValueMIF);
                liquidatable = u256.gt(ltv, LIQUIDATION_BPS);
            } else {
                liquidatable = true;
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

    // =======================================================================
    // Algorithmic Stablecoin View Functions
    // =======================================================================

    @method()
    @returns({ name: 'tcr', type: ABIDataTypes.UINT256 })
    private _getTCRView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._tcrBps.get());
        return writer;
    }

    @method()
    @returns({ name: 'ecr', type: ABIDataTypes.UINT256 })
    private _getECRView(_calldata: Calldata): BytesWriter {
        const btcPrice: u256 = this._getOraclePrice();
        const ecr: u256 = this._calculateECR(btcPrice);
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(ecr);
        return writer;
    }

    @method()
    @returns({ name: 'reserve', type: ABIDataTypes.UINT256 })
    private _totalBTCReserveView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._totalBTCReserve.get());
        return writer;
    }

    @method()
    @returns({ name: 'supply', type: ABIDataTypes.UINT256 })
    private _totalMIFMintedView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._totalMIFSupply.get());
        return writer;
    }

    @method()
    @returns({ name: 'active', type: ABIDataTypes.BOOL })
    private _isCircuitBreakerActiveView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(this._circuitBreakerActive.value);
        return writer;
    }

    @method()
    @returns({ name: 'minted', type: ABIDataTypes.UINT256 })
    private _getDailyFRENMintedView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._dailyFrenMinted.get());
        return writer;
    }

    @method()
    @returns({ name: 'cap', type: ABIDataTypes.UINT256 })
    private _getDailyFRENMintCapView(_calldata: Calldata): BytesWriter {
        const baseSupply: u256 = this._dailyCapBaseSupply.get();
        const cap: u256 = SafeMath.div(
            SafeMath.mul(baseSupply, FREN_DAILY_MINT_CAP_BPS),
            BPS_PRECISION,
        );
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(cap);
        return writer;
    }

    @method()
    @returns({ name: 'price', type: ABIDataTypes.UINT256 })
    private _getFRENPriceView(_calldata: Calldata): BytesWriter {
        const price: u256 = this._getFRENOraclePrice();
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(price);
        return writer;
    }

    /**
     * getMintInfo(mifAmount): Preview the cost to mint a given amount of MIF.
     * Returns: (btcNeeded, frenNeeded, fee)
     */
    @method({ name: 'mifAmount', type: ABIDataTypes.UINT256 })
    @returns(
        { name: 'btcNeeded', type: ABIDataTypes.UINT256 },
        { name: 'frenNeeded', type: ABIDataTypes.UINT256 },
        { name: 'fee', type: ABIDataTypes.UINT256 },
    )
    private _getMintInfo(calldata: Calldata): BytesWriter {
        const mifAmount: u256 = calldata.readU256();
        const btcPrice: u256 = this._getOraclePrice();
        const frenPrice: u256 = this._getFRENOraclePrice();
        const tcr: u256 = this._tcrBps.get();

        const fee: u256 = SafeMath.div(SafeMath.mul(mifAmount, MINT_REDEEM_FEE_BPS), BPS_PRECISION);

        // H-5 fix: multiply all numerators first
        const btcNeeded: u256 = SafeMath.div(
            SafeMath.mul(SafeMath.mul(mifAmount, tcr), SATS_PER_BTC),
            SafeMath.mul(BPS_PRECISION, btcPrice),
        );

        const frenFraction: u256 = SafeMath.sub(BPS_PRECISION, tcr);
        const frenNeeded: u256 = SafeMath.div(
            SafeMath.mul(SafeMath.mul(mifAmount, frenFraction), PRECISION_18),
            SafeMath.mul(BPS_PRECISION, frenPrice),
        );

        const writer: BytesWriter = new BytesWriter(96);
        writer.writeU256(btcNeeded);
        writer.writeU256(frenNeeded);
        writer.writeU256(fee);
        return writer;
    }

    /**
     * getRedeemInfo(mifAmount): Preview what a redemption of MIF yields.
     * Returns: (btcOut, frenOut, fee)
     */
    @method({ name: 'mifAmount', type: ABIDataTypes.UINT256 })
    @returns(
        { name: 'btcOut', type: ABIDataTypes.UINT256 },
        { name: 'frenOut', type: ABIDataTypes.UINT256 },
        { name: 'fee', type: ABIDataTypes.UINT256 },
    )
    private _getRedeemInfo(calldata: Calldata): BytesWriter {
        const mifAmount: u256 = calldata.readU256();
        const btcPrice: u256 = this._getOraclePrice();
        const frenPrice: u256 = this._getFRENOraclePrice();

        const fee: u256 = SafeMath.div(SafeMath.mul(mifAmount, MINT_REDEEM_FEE_BPS), BPS_PRECISION);
        const effectiveMif: u256 = SafeMath.sub(mifAmount, fee);

        const ecr: u256 = this._calculateECR(btcPrice);

        // H-5 fix: multiply all numerators first
        const btcOut: u256 = SafeMath.div(
            SafeMath.mul(SafeMath.mul(effectiveMif, ecr), SATS_PER_BTC),
            SafeMath.mul(BPS_PRECISION, btcPrice),
        );

        const frenFraction: u256 = SafeMath.sub(BPS_PRECISION, ecr);
        const frenOut: u256 = SafeMath.div(
            SafeMath.mul(SafeMath.mul(effectiveMif, frenFraction), PRECISION_18),
            SafeMath.mul(BPS_PRECISION, frenPrice),
        );

        const writer: BytesWriter = new BytesWriter(96);
        writer.writeU256(btcOut);
        writer.writeU256(frenOut);
        writer.writeU256(fee);
        return writer;
    }

    @method()
    @returns({ name: 'fees', type: ABIDataTypes.UINT256 })
    private _mintRedeemFeesView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._mintRedeemFees.get());
        return writer;
    }

    // =======================================================================
    // Admin Functions -- CDP
    // =======================================================================

    @method({ name: 'cap', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setBorrowCap(calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        this._totalBorrowCap.set(calldata.readU256());
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

    // =======================================================================
    // Admin Functions -- Algorithmic Stablecoin
    // =======================================================================

    /**
     * setTCR(newTcr): Adjust the Target Collateral Ratio.
     * Rate-limited: max 0.5% change per day. Bounded 75%-100%.
     */
    @method({ name: 'newTcr', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setTCR(calldata: Calldata): BytesWriter {
        this._onlyAdmin();

        const newTcr: u256 = calldata.readU256();

        // Bounds check
        if (u256.lt(newTcr, TCR_FLOOR_BPS)) {
            throw new Revert(ERR_CAULDRON_TCR_BELOW_FLOOR);
        }
        if (u256.gt(newTcr, TCR_CEILING_BPS)) {
            throw new Revert(ERR_CAULDRON_TCR_ABOVE_CEILING);
        }

        // Rate-limit check (block-based: 1 day = BLOCKS_PER_DAY blocks)
        const currentBlock: u64 = Blockchain.block.number;
        const lastAdjust: u64 = this._lastTCRAdjustTs.get();
        if (currentBlock < lastAdjust + BLOCKS_PER_DAY) {
            throw new Revert(ERR_CAULDRON_TCR_COOLDOWN);
        }

        // Delta check
        const oldTcr: u256 = this._tcrBps.get();
        let delta: u256;
        if (u256.gt(newTcr, oldTcr)) {
            delta = SafeMath.sub(newTcr, oldTcr);
        } else {
            delta = SafeMath.sub(oldTcr, newTcr);
        }
        if (u256.gt(delta, TCR_DAILY_MAX_DELTA_BPS)) {
            throw new Revert(ERR_CAULDRON_TCR_DELTA_TOO_LARGE);
        }

        this._tcrBps.set(newTcr);
        this._lastTCRAdjustTs.set(currentBlock);

        this.emitEvent(new TCRAdjustedEvent(oldTcr, newTcr, currentBlock));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'oracle', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setFRENOracle(calldata: Calldata): BytesWriter {
        this._onlyAdmin();
        const oracle: Address = calldata.readAddress();
        if (oracle.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_ZERO_ADDR);
        }
        this._frenOracleAddr.set(this._addressToU256(oracle));
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _tripCircuitBreaker(_calldata: Calldata): BytesWriter {
        this._onlyAdmin();

        const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
        this._circuitBreakerActive.value = true;
        this._circuitBreakerBlock.set(currentBlock);

        // Snapshot current FREN price as reference for drop detection
        const frenPrice: u256 = this._getFRENOraclePrice();
        this._frenRefPrice.set(frenPrice);

        this.emitEvent(new CircuitBreakerTrippedEvent(currentBlock, frenPrice));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _resumeCircuitBreaker(_calldata: Calldata): BytesWriter {
        this._onlyAdmin();

        const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
        this._circuitBreakerActive.value = false;

        this.emitEvent(new CircuitBreakerResumedEvent(currentBlock));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }
}
