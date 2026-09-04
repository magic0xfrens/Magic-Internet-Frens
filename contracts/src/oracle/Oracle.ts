import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    encodeSelector,
    OP_NET,
    Revert,
    SafeMath,
    Selector,
    StoredU256,
    StoredU64,
} from '@btc-vision/btc-runtime/runtime';

import { STALENESS_BLOCKS, ORACLE_MAX_DEVIATION_BPS, BPS_PRECISION } from '../lib/constants';
import {
    ERR_ORACLE_NO_PRICE,
    ERR_ORACLE_STALE,
    ERR_ORACLE_ZERO_PRICE,
    ERR_ORACLE_NOT_ADMIN,
    ERR_ORACLE_ZERO_ADDR,
    ERR_ORACLE_DEVIATION,
} from '../lib/errors';
import { PriceUpdatedEvent, AdminTransferredEvent } from '../events/OracleEvents';

/**
 * Oracle -- BTC/USD Price Oracle for the Magic Internet Frens Protocol.
 *
 * Admin-set price with update tracking and staleness checks.
 * Price is stored as u256 with 18 decimals of precision.
 * Example: BTC at $60,000 => 60000 * 10^18
 */
@final
export class Oracle extends OP_NET {
    // -----------------------------------------------------------------------
    // Storage Pointers (auto-allocated)
    // -----------------------------------------------------------------------

    private readonly adminAddrPointer: u16 = Blockchain.nextPointer;
    private readonly pricePointer: u16 = Blockchain.nextPointer;
    private readonly lastUpdatePointer: u16 = Blockchain.nextPointer;
    private readonly updateCountPointer: u16 = Blockchain.nextPointer;

    // -----------------------------------------------------------------------
    // Storage Instances
    // -----------------------------------------------------------------------

    /** Admin address encoded as u256 */
    private readonly _adminAddr: StoredU256;

    /** BTC/USD price with 18 decimals */
    private readonly _price: StoredU256;

    /** Block number of last price update */
    private readonly _lastUpdate: StoredU64;

    /** Total number of price updates */
    private readonly _updateCount: StoredU256;

    // -----------------------------------------------------------------------
    // Selectors
    // -----------------------------------------------------------------------

    private readonly getPriceSelector: Selector = encodeSelector('getPrice()');
    private readonly setPriceSelector: Selector = encodeSelector('setPrice(uint256)');
    private readonly isFreshSelector: Selector = encodeSelector('isFresh()');
    private readonly lastUpdateSelector: Selector = encodeSelector('lastUpdate()');
    private readonly adminSelector: Selector = encodeSelector('admin()');
    private readonly updateCountSelector: Selector = encodeSelector('updateCount()');
    private readonly transferAdminSelector: Selector = encodeSelector('transferAdmin(address)');

    // -----------------------------------------------------------------------
    // Constructor (runs on EVERY call)
    // -----------------------------------------------------------------------

    public constructor() {
        super();

        this._adminAddr = new StoredU256(this.adminAddrPointer, u256.Zero);
        this._price = new StoredU256(this.pricePointer, u256.Zero);
        this._lastUpdate = new StoredU64(this.lastUpdatePointer, 0);
        this._updateCount = new StoredU256(this.updateCountPointer, u256.Zero);
    }

    // -----------------------------------------------------------------------
    // Deployment (runs ONCE)
    // -----------------------------------------------------------------------

    public override onDeployment(_calldata: Calldata): void {
        const deployer: Address = Blockchain.tx.sender;
        this._adminAddr.set(this._addressToU256(deployer));
        this._lastUpdate.set(0);
        this._updateCount.set(u256.Zero);
    }

    // -----------------------------------------------------------------------
    // Address <-> u256 Helpers
    // -----------------------------------------------------------------------

    private _addressToU256(addr: Address): u256 {
        const bytes: Uint8Array = addr.toBytes();
        return u256.fromBytesBE(bytes);
    }

    private _u256ToAddress(val: u256): Address {
        const bytes: Uint8Array = val.toBytesBE();
        return Address.fromBytes(bytes);
    }

    private _getAdmin(): Address {
        return this._u256ToAddress(this._adminAddr.get());
    }

    // -----------------------------------------------------------------------
    // Access Control
    // -----------------------------------------------------------------------

    private _onlyAdmin(): void {
        const sender: Address = Blockchain.tx.sender;
        const admin: Address = this._getAdmin();
        if (!sender.equals(admin)) {
            throw new Revert(ERR_ORACLE_NOT_ADMIN);
        }
    }

    // -----------------------------------------------------------------------
    // callMethod Router
    // -----------------------------------------------------------------------

    public override callMethod(calldata: Calldata): BytesWriter {
        const selector: Selector = calldata.readSelector();

        switch (selector) {
            case this.getPriceSelector:
                return this._getPrice(calldata);
            case this.setPriceSelector:
                return this._setPrice(calldata);
            case this.isFreshSelector:
                return this._isFresh(calldata);
            case this.lastUpdateSelector:
                return this._lastUpdateView(calldata);
            case this.adminSelector:
                return this._adminView(calldata);
            case this.updateCountSelector:
                return this._updateCountView(calldata);
            case this.transferAdminSelector:
                return this._transferAdmin(calldata);
            default:
                return super.callMethod(calldata);
        }
    }

    // -----------------------------------------------------------------------
    // Read Methods
    // -----------------------------------------------------------------------

    @method()
    @returns({ name: 'price', type: ABIDataTypes.UINT256 })
    private _getPrice(_calldata: Calldata): BytesWriter {
        const lastUpdate: u64 = this._lastUpdate.get();
        if (lastUpdate == 0) {
            throw new Revert(ERR_ORACLE_NO_PRICE);
        }

        const currentBlock: u64 = Blockchain.block.number;
        if (currentBlock - lastUpdate > STALENESS_BLOCKS) {
            throw new Revert(ERR_ORACLE_STALE);
        }

        const price: u256 = this._price.get();
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(price);
        return writer;
    }

    @method()
    @returns({ name: 'fresh', type: ABIDataTypes.BOOL })
    private _isFresh(_calldata: Calldata): BytesWriter {
        const lastUpdate: u64 = this._lastUpdate.get();
        let fresh: bool = false;
        if (lastUpdate > 0) {
            const currentBlock: u64 = Blockchain.block.number;
            fresh = (currentBlock - lastUpdate) <= STALENESS_BLOCKS;
        }
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(fresh);
        return writer;
    }

    @method()
    @returns({ name: 'timestamp', type: ABIDataTypes.UINT256 })
    private _lastUpdateView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(u256.fromU64(this._lastUpdate.get()));
        return writer;
    }

    @method()
    @returns({ name: 'admin', type: ABIDataTypes.ADDRESS })
    private _adminView(_calldata: Calldata): BytesWriter {
        const admin: Address = this._getAdmin();
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeAddress(admin);
        return writer;
    }

    @method()
    @returns({ name: 'count', type: ABIDataTypes.UINT256 })
    private _updateCountView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._updateCount.get());
        return writer;
    }

    // -----------------------------------------------------------------------
    // Write Methods (Admin-only)
    // -----------------------------------------------------------------------

    @method({ name: 'price', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _setPrice(calldata: Calldata): BytesWriter {
        this._onlyAdmin();

        const newPrice: u256 = calldata.readU256();
        if (newPrice.isZero()) {
            throw new Revert(ERR_ORACLE_ZERO_PRICE);
        }

        // Enforce price deviation bounds (max 10% change per update)
        const oldPrice: u256 = this._price.get();
        if (!oldPrice.isZero()) {
            let deviation: u256;
            if (u256.gt(newPrice, oldPrice)) {
                deviation = SafeMath.sub(newPrice, oldPrice);
            } else {
                deviation = SafeMath.sub(oldPrice, newPrice);
            }
            // deviationBps = deviation * BPS_PRECISION / oldPrice
            const deviationBps: u256 = SafeMath.div(
                SafeMath.mul(deviation, BPS_PRECISION),
                oldPrice,
            );
            if (u256.gt(deviationBps, ORACLE_MAX_DEVIATION_BPS)) {
                throw new Revert(ERR_ORACLE_DEVIATION);
            }
        }

        const currentBlock: u64 = Blockchain.block.number;

        this._price.set(newPrice);
        this._lastUpdate.set(currentBlock);
        this._updateCount.set(SafeMath.add(this._updateCount.get(), u256.One));

        this.emitEvent(new PriceUpdatedEvent(newPrice, currentBlock));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'newAdmin', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _transferAdmin(calldata: Calldata): BytesWriter {
        this._onlyAdmin();

        const newAdmin: Address = calldata.readAddress();
        if (newAdmin.equals(Address.dead())) {
            throw new Revert(ERR_ORACLE_ZERO_ADDR);
        }

        const oldAdmin: Address = this._getAdmin();
        this._adminAddr.set(this._addressToU256(newAdmin));

        this.emitEvent(new AdminTransferredEvent(oldAdmin, newAdmin));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }
}
