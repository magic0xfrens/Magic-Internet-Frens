import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    OP_NET,
    Revert,
    StoredU256,
    AddressMemoryMap,
    SafeMath,
} from '@btc-vision/btc-runtime/runtime';

import { ERR_VOLUME_NOT_KEEPER } from '../lib/errors';

/**
 * VolumeOracle - Tracks 24h volume for MotoSwap pools
 *
 * When 24h volume < threshold, token is considered "dead"
 */
@final
export class VolumeOracle extends OP_NET {
    // Storage pointers
    private readonly deathThresholdPointer: u16 = Blockchain.nextPointer;
    private readonly poolVolume24hPointer: u16 = Blockchain.nextPointer;
    private readonly poolLastUpdatePointer: u16 = Blockchain.nextPointer;
    private readonly keepersPointer: u16 = Blockchain.nextPointer;

    // Storage
    private _deathThreshold!: StoredU256;
    private _poolVolume24h!: AddressMemoryMap;
    private _poolLastUpdate!: AddressMemoryMap;
    private _keepers!: AddressMemoryMap;

    // Constants
    private readonly BLOCKS_PER_24H: u256 = u256.fromU64(144);

    public constructor() {
        super();
        this._deathThreshold = new StoredU256(this.deathThresholdPointer, new Uint8Array(0));
        this._poolVolume24h = new AddressMemoryMap(this.poolVolume24hPointer);
        this._poolLastUpdate = new AddressMemoryMap(this.poolLastUpdatePointer);
        this._keepers = new AddressMemoryMap(this.keepersPointer);
    }

    public override onDeployment(calldata: Calldata): void {
        const threshold: u256 = calldata.readU256();
        this._deathThreshold.value = threshold;
    }

    @method({ name: 'threshold', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setDeathThreshold(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const threshold: u256 = calldata.readU256();
        this._deathThreshold.value = threshold;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method(
        { name: 'pool', type: ABIDataTypes.ADDRESS },
        { name: 'volumeSats', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public updateVolume(calldata: Calldata): BytesWriter {
        // Restrict to authorized keepers
        const sender: Address = Blockchain.tx.sender;
        const isKeeper: u256 = this._keepers.get(sender);
        if (!u256.eq(isKeeper, u256.One)) {
            throw new Revert(ERR_VOLUME_NOT_KEEPER);
        }

        const pool: Address = calldata.readAddress();
        const volumeSats: u256 = calldata.readU256();

        const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
        const lastUpdate: u256 = this._poolLastUpdate.get(pool);

        const blocksSinceUpdate: u256 = SafeMath.sub(currentBlock, lastUpdate);
        let currentVolume: u256 = this._poolVolume24h.get(pool);

        if (u256.gt(blocksSinceUpdate, this.BLOCKS_PER_24H)) {
            currentVolume = u256.Zero;
        }

        const newVolume: u256 = SafeMath.add(currentVolume, volumeSats);
        this._poolVolume24h.set(pool, newVolume);
        this._poolLastUpdate.set(pool, currentBlock);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'pool', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'isDead', type: ABIDataTypes.BOOL })
    public isDead(calldata: Calldata): BytesWriter {
        const pool: Address = calldata.readAddress();

        const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
        const lastUpdate: u256 = this._poolLastUpdate.get(pool);
        const blocksSinceUpdate: u256 = SafeMath.sub(currentBlock, lastUpdate);

        let volume: u256;
        if (u256.gt(blocksSinceUpdate, this.BLOCKS_PER_24H)) {
            volume = u256.Zero;
        } else {
            volume = this._poolVolume24h.get(pool);
        }

        const threshold: u256 = this._deathThreshold.value;
        const dead: bool = u256.lt(volume, threshold);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(dead);
        return writer;
    }

    @method({ name: 'pool', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'volume', type: ABIDataTypes.UINT256 })
    public getVolume(calldata: Calldata): BytesWriter {
        const pool: Address = calldata.readAddress();
        const volume: u256 = this._poolVolume24h.get(pool);

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(volume);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Keeper Management (Deployer-only)
    // -----------------------------------------------------------------------

    @method({ name: 'keeper', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public addKeeper(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const keeper: Address = calldata.readAddress();
        this._keepers.set(keeper, u256.One);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'keeper', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public removeKeeper(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const keeper: Address = calldata.readAddress();
        this._keepers.set(keeper, u256.Zero);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'account', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'result', type: ABIDataTypes.BOOL })
    public isKeeper(calldata: Calldata): BytesWriter {
        const account: Address = calldata.readAddress();
        const isKeeper: u256 = this._keepers.get(account);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(u256.eq(isKeeper, u256.One));
        return writer;
    }
}
