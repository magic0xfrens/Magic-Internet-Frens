import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    encodeSelector,
    OP_NET,
    StoredU256,
    StoredAddress,
    StoredMapU256,
    SafeMath,
    Revert,
} from '@btc-vision/btc-runtime/runtime';
import { CallResult } from '@btc-vision/btc-runtime/runtime/env/BlockchainEnvironment';

import {
    CauldronSummonedEvent,
    CauldronDiedEvent,
    CauldronRebornEvent,
    HolderClaimedEvent,
} from '../events/PhoenixEvents';
import {
    CAULDRON_INITIAL_TOKENS,
    CAULDRON_INITIAL_BTC_SATS,
} from '../lib/constants';

/**
 * CauldronRegistry - Orchestrates the immortal Cauldron token
 *
 * Handles:
 * - Genesis summoning when 777 NFTs minted
 * - Death detection and rebirth triggering (AI-generated identity)
 * - Holder snapshots and claims
 */
@final
export class CauldronRegistry extends OP_NET {
    // Storage pointers
    private readonly currentGenerationPointer: u16 = Blockchain.nextPointer;
    private readonly currentTokenPointer: u16 = Blockchain.nextPointer;
    private readonly currentPoolPointer: u16 = Blockchain.nextPointer;
    private readonly cauldronVaultPointer: u16 = Blockchain.nextPointer;
    private readonly volumeOraclePointer: u16 = Blockchain.nextPointer;
    private readonly nftContractPointer: u16 = Blockchain.nextPointer;
    private readonly summonedPointer: u16 = Blockchain.nextPointer;

    // Generation history & claims
    private readonly generationTokensPointer: u16 = Blockchain.nextPointer;
    private readonly claimedPointer: u16 = Blockchain.nextPointer;
    private readonly liquiditySnapshotsPointer: u16 = Blockchain.nextPointer;
    private readonly liquidityTokensPointer: u16 = Blockchain.nextPointer;

    // Storage
    private _currentGeneration!: StoredU256;
    private _currentToken!: StoredAddress;
    private _currentPool!: StoredAddress;
    private _cauldronVault!: StoredAddress;
    private _volumeOracle!: StoredAddress;
    private _nftContract!: StoredAddress;
    private _summoned!: StoredU256;

    // generation -> token address (stored as u256 for map compatibility)
    private _generationTokens!: StoredMapU256;
    // claimed: generation + holder -> claimed (1/0)
    private _claimed!: StoredMapU256;
    // liquidity snapshots: generation -> btc amount
    private _liquidityBTC!: StoredMapU256;
    private _liquidityTokens!: StoredMapU256;

    public constructor() {
        super();
        this._currentGeneration = new StoredU256(this.currentGenerationPointer, new Uint8Array(0));
        this._currentToken = new StoredAddress(this.currentTokenPointer);
        this._currentPool = new StoredAddress(this.currentPoolPointer);
        this._cauldronVault = new StoredAddress(this.cauldronVaultPointer);
        this._volumeOracle = new StoredAddress(this.volumeOraclePointer);
        this._nftContract = new StoredAddress(this.nftContractPointer);
        this._summoned = new StoredU256(this.summonedPointer, new Uint8Array(0));

        this._generationTokens = new StoredMapU256(this.generationTokensPointer);
        this._claimed = new StoredMapU256(this.claimedPointer);
        this._liquidityBTC = new StoredMapU256(this.liquiditySnapshotsPointer);
        this._liquidityTokens = new StoredMapU256(this.liquidityTokensPointer);
    }

    public override onDeployment(calldata: Calldata): void {
        const nftContract: Address = calldata.readAddress();
        const vault: Address = calldata.readAddress();
        const oracle: Address = calldata.readAddress();

        this._nftContract.value = nftContract;
        this._cauldronVault.value = vault;
        this._volumeOracle.value = oracle;
    }

    // -----------------------------------------------------------------------
    // Public Methods (decorated for opnet-transform routing)
    // -----------------------------------------------------------------------

    @method(
        { name: 'tokenAddress', type: ABIDataTypes.ADDRESS },
        { name: 'poolAddress', type: ABIDataTypes.ADDRESS },
        { name: 'name', type: ABIDataTypes.STRING },
        { name: 'symbol', type: ABIDataTypes.STRING },
    )
    @returns({ name: 'token', type: ABIDataTypes.ADDRESS })
    public summonGenesis(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const summoned: u256 = this._summoned.value;
        if (u256.eq(summoned, u256.One)) {
            throw new Revert('Already summoned');
        }

        const tokenAddress: Address = calldata.readAddress();
        const poolAddress: Address = calldata.readAddress();
        const name: string = calldata.readStringWithLength();
        const symbol: string = calldata.readStringWithLength();

        this._currentGeneration.value = u256.One;
        this._currentToken.value = tokenAddress;
        this._currentPool.value = poolAddress;
        this._summoned.value = u256.One;

        // Record token address for this generation (used by claimTokens to read frozen balances)
        this._generationTokens.set(u256.One, this._addressToU256(tokenAddress));

        this._liquidityBTC.set(u256.One, CAULDRON_INITIAL_BTC_SATS);
        this._liquidityTokens.set(u256.One, CAULDRON_INITIAL_TOKENS);

        this.emitEvent(new CauldronSummonedEvent(
            u256.One,
            tokenAddress,
            poolAddress,
            name,
            symbol,
        ));

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeAddress(tokenAddress);
        return writer;
    }

    @method(
        { name: 'newTokenAddress', type: ABIDataTypes.ADDRESS },
        { name: 'newPoolAddress', type: ABIDataTypes.ADDRESS },
        { name: 'name', type: ABIDataTypes.STRING },
        { name: 'symbol', type: ABIDataTypes.STRING },
    )
    @returns({ name: 'token', type: ABIDataTypes.ADDRESS })
    public triggerRebirth(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const currentGen: u256 = this._currentGeneration.value;
        const currentToken: Address = this._currentToken.value;
        const currentPool: Address = this._currentPool.value;

        const isDead: bool = this._checkTokenDead(currentPool);
        if (!isDead) {
            throw new Revert('Token still alive');
        }

        this._markTokenDead(currentToken);

        const newTokenAddress: Address = calldata.readAddress();
        const newPoolAddress: Address = calldata.readAddress();
        const name: string = calldata.readStringWithLength();
        const symbol: string = calldata.readStringWithLength();

        this.emitEvent(new CauldronDiedEvent(
            currentGen,
            currentToken,
            u256.Zero,
            u256.Zero,
            u256.Zero,
        ));

        const nextGen: u256 = SafeMath.add(currentGen, u256.One);

        this._currentGeneration.value = nextGen;
        this._currentToken.value = newTokenAddress;
        this._currentPool.value = newPoolAddress;

        // Record token address for this generation
        this._generationTokens.set(nextGen, this._addressToU256(newTokenAddress));

        this.emitEvent(new CauldronRebornEvent(
            nextGen,
            newTokenAddress,
            newPoolAddress,
            name,
            symbol,
        ));

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeAddress(newTokenAddress);
        return writer;
    }

    @method({ name: 'generation', type: ABIDataTypes.UINT256 })
    @returns({ name: 'balance', type: ABIDataTypes.UINT256 })
    public claimTokens(calldata: Calldata): BytesWriter {
        const generation: u256 = calldata.readU256();
        const sender: Address = Blockchain.tx.sender;

        const currentGen: u256 = this._currentGeneration.value;
        if (u256.ge(generation, currentGen)) {
            throw new Revert('Cannot claim current/future gen');
        }

        const claimKey: u256 = this._makeClaimKey(generation, sender);
        const claimed: u256 = this._claimed.get(claimKey);
        if (u256.eq(claimed, u256.One)) {
            throw new Revert('Already claimed');
        }

        // Read balance directly from the dead token (transfers are frozen, balances are immutable)
        const deadTokenU256: u256 = this._generationTokens.get(generation);
        if (deadTokenU256.isZero()) {
            throw new Revert('Unknown generation');
        }
        const deadToken: Address = this._u256ToAddress(deadTokenU256);
        const balance: u256 = this._getBalanceOf(deadToken, sender);

        if (balance.isZero()) {
            throw new Revert('No balance');
        }

        this._claimed.set(claimKey, u256.One);

        const currentToken: Address = this._currentToken.value;
        this._mintTokens(currentToken, sender, balance);

        this.emitEvent(new HolderClaimedEvent(generation, sender, balance));

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(balance);
        return writer;
    }

    @method()
    @returns({ name: 'token', type: ABIDataTypes.ADDRESS })
    public getCurrentToken(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeAddress(this._currentToken.value);
        return writer;
    }

    @method()
    @returns({ name: 'generation', type: ABIDataTypes.UINT256 })
    public getCurrentGeneration(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._currentGeneration.value);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    private _mintTokens(tokenAddress: Address, to: Address, amount: u256): void {
        const writer: BytesWriter = new BytesWriter(68);
        writer.writeSelector(encodeSelector('mint(address,uint256)'));
        writer.writeAddress(to);
        writer.writeU256(amount);

        Blockchain.call(tokenAddress, writer, true);
    }

    private _markTokenDead(tokenAddress: Address): void {
        const writer: BytesWriter = new BytesWriter(4);
        writer.writeSelector(encodeSelector('markDead()'));

        Blockchain.call(tokenAddress, writer, true);
    }

    private _checkTokenDead(poolAddress: Address): bool {
        if (this._volumeOracle.isDead()) {
            return false;
        }

        const oracle: Address = this._volumeOracle.value;
        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(encodeSelector('isDead(address)'));
        writer.writeAddress(poolAddress);

        const result: CallResult = Blockchain.call(oracle, writer, false);
        if (!result.success) {
            return false;
        }

        return result.data.readBoolean();
    }

    private _getBalanceOf(tokenAddress: Address, holder: Address): u256 {
        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(encodeSelector('balanceOf(address)'));
        writer.writeAddress(holder);

        const result: CallResult = Blockchain.call(tokenAddress, writer, false);
        if (!result.success) {
            return u256.Zero;
        }

        return result.data.readU256();
    }

    private _addressToU256(addr: Address): u256 {
        const bytes: u8[] = new Array<u8>(32);
        for (let i: i32 = 0; i < 32; i++) {
            bytes[i] = addr[i];
        }
        return u256.fromBytesBE(bytes);
    }

    private _u256ToAddress(val: u256): Address {
        const raw: Uint8Array = val.toUint8Array(true);
        const bytes: u8[] = new Array<u8>(32);
        for (let i: i32 = 0; i < 32; i++) {
            bytes[i] = raw[i];
        }
        return new Address(bytes);
    }

    private _makeClaimKey(generation: u256, holder: Address): u256 {
        const genU64: u64 = generation.toU64();
        const result: u8[] = new Array<u8>(32);

        result[0] = u8(genU64 >> 56);
        result[1] = u8(genU64 >> 48);
        result[2] = u8(genU64 >> 40);
        result[3] = u8(genU64 >> 32);
        result[4] = u8(genU64 >> 24);
        result[5] = u8(genU64 >> 16);
        result[6] = u8(genU64 >> 8);
        result[7] = u8(genU64);

        for (let i: i32 = 0; i < 24; i++) {
            result[i + 8] = holder[i];
        }

        return u256.fromBytesBE(result);
    }
}
