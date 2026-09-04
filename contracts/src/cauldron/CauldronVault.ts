import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    encodeSelector,
    OP_NET,
    StoredAddress,
    AddressMemoryMap,
    Revert,
} from '@btc-vision/btc-runtime/runtime';
import { CallResult } from '@btc-vision/btc-runtime/runtime/env/BlockchainEnvironment';

/**
 * CauldronVault - Holds liquidity until token dies
 *
 * Liquidity is locked until VolumeOracle confirms death
 * Then liquidity migrates to new Cauldron generation
 */
@final
export class CauldronVault extends OP_NET {
    // Storage pointers
    private readonly registryPointer: u16 = Blockchain.nextPointer;
    private readonly volumeOraclePointer: u16 = Blockchain.nextPointer;
    private readonly currentPoolPointer: u16 = Blockchain.nextPointer;
    private readonly lockedPoolsPointer: u16 = Blockchain.nextPointer;

    // Storage
    private _registry!: StoredAddress;
    private _volumeOracle!: StoredAddress;
    private _currentPool!: StoredAddress;
    private _lockedPools!: AddressMemoryMap;

    public constructor() {
        super();
        this._registry = new StoredAddress(this.registryPointer);
        this._volumeOracle = new StoredAddress(this.volumeOraclePointer);
        this._currentPool = new StoredAddress(this.currentPoolPointer);
        this._lockedPools = new AddressMemoryMap(this.lockedPoolsPointer);
    }

    public override onDeployment(calldata: Calldata): void {
        const registry: Address = calldata.readAddress();
        const oracle: Address = calldata.readAddress();

        this._registry.value = registry;
        this._volumeOracle.value = oracle;
    }

    @method({ name: 'registry', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setRegistry(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const registry: Address = calldata.readAddress();
        this._registry.value = registry;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'oracle', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setOracle(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const oracle: Address = calldata.readAddress();
        this._volumeOracle.value = oracle;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'pool', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public lockLiquidity(calldata: Calldata): BytesWriter {
        this._onlyRegistry();

        const pool: Address = calldata.readAddress();
        this._lockedPools.set(pool, u256.One);
        this._currentPool.value = pool;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'pool', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'canMigrate', type: ABIDataTypes.BOOL })
    public canMigrate(calldata: Calldata): BytesWriter {
        const pool: Address = calldata.readAddress();

        const locked: u256 = this._lockedPools.get(pool);
        if (!u256.eq(locked, u256.One)) {
            const writer: BytesWriter = new BytesWriter(1);
            writer.writeBoolean(false);
            return writer;
        }

        const isDead: bool = this._callOracleIsDead(pool);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(isDead);
        return writer;
    }

    @method(
        { name: 'oldPool', type: ABIDataTypes.ADDRESS },
        { name: 'newPool', type: ABIDataTypes.ADDRESS },
        { name: 'btcAmount', type: ABIDataTypes.UINT256 },
        { name: 'tokenAmount', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public migrateLiquidity(calldata: Calldata): BytesWriter {
        this._onlyRegistry();

        const oldPool: Address = calldata.readAddress();
        const newPool: Address = calldata.readAddress();
        const _btcAmount: u256 = calldata.readU256();
        const _tokenAmount: u256 = calldata.readU256();

        const isDead: bool = this._callOracleIsDead(oldPool);
        if (!isDead) {
            throw new Revert('Token still alive');
        }

        this._lockedPools.set(oldPool, u256.Zero);
        this._lockedPools.set(newPool, u256.One);
        this._currentPool.value = newPool;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    private _onlyRegistry(): void {
        const registry: Address = this._registry.value;
        if (!Blockchain.tx.sender.equals(registry)) {
            throw new Revert('Only registry');
        }
    }

    private _callOracleIsDead(pool: Address): bool {
        if (this._volumeOracle.isDead()) {
            return false;
        }

        const oracle: Address = this._volumeOracle.value;
        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(encodeSelector('isDead(address)'));
        writer.writeAddress(pool);

        const result: CallResult = Blockchain.call(oracle, writer, false);
        if (!result.success) {
            return false;
        }

        return result.data.readBoolean();
    }
}
