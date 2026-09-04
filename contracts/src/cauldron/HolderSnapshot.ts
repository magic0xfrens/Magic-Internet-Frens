import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    encodeSelector,
    SafeMath,
    StoredMapU256,
} from '@btc-vision/btc-runtime/runtime';
import { CallResult } from '@btc-vision/btc-runtime/runtime/env/BlockchainEnvironment';

/**
 * Holder Snapshot System
 * Efficiently stores and retrieves holder balances per generation
 */
export class HolderSnapshot {
    // Storage: keccak256(generation + address) -> balance
    private readonly snapshots: StoredMapU256;

    // Storage: generation -> total holders count
    private readonly holderCounts: StoredMapU256;

    // Storage: generation + index -> address (as u256)
    private readonly holderAddresses: StoredMapU256;

    constructor(snapshotsPointer: u16, countsPointer: u16, addressesPointer: u16) {
        this.snapshots = new StoredMapU256(snapshotsPointer);
        this.holderCounts = new StoredMapU256(countsPointer);
        this.holderAddresses = new StoredMapU256(addressesPointer);
    }

    /**
     * Create snapshot of all token holders
     */
    public snapshot(generation: u256, tokenAddress: Address): void {
        const totalSupply = this._getTotalSupply(tokenAddress);

        if (totalSupply.isZero()) {
            return;
        }

        // Store snapshot metadata
        this.holderCounts.set(generation, u256.Zero);
    }

    /**
     * Add a holder to snapshot
     */
    public addHolder(generation: u256, holder: Address, balance: u256): void {
        const key = this._makeKey(generation, holder);
        this.snapshots.set(key, balance);

        // Track holder count
        const count = this.holderCounts.get(generation);
        this.holderCounts.set(generation, SafeMath.add(count, u256.One));

        // Store address at index
        const addressKey = this._makeIndexKey(generation, count);
        const addrU256 = this._addressToU256(holder);
        this.holderAddresses.set(addressKey, addrU256);
    }

    /**
     * Get holder balance from snapshot
     */
    public getBalance(generation: u256, holder: Address): u256 {
        const key = this._makeKey(generation, holder);
        return this.snapshots.get(key);
    }

    /**
     * Get total holders in snapshot
     */
    public getHolderCount(generation: u256): u256 {
        return this.holderCounts.get(generation);
    }

    /**
     * Iterate holders (for batch processing)
     */
    public getHolderAt(generation: u256, index: u256): Address {
        const addressKey = this._makeIndexKey(generation, index);
        return this._loadAddress(addressKey);
    }

    /**
     * Make storage key for generation + address
     */
    private _makeKey(generation: u256, holder: Address): u256 {
        // Pack generation (high 8 bytes) + holder (low 24 bytes) into u256
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

    private _makeIndexKey(generation: u256, index: u256): u256 {
        return SafeMath.add(
            SafeMath.mul(generation, u256.fromU64(1000000)),
            index,
        );
    }

    private _addressToU256(addr: Address): u256 {
        const bytes: u8[] = new Array<u8>(32);
        for (let i: i32 = 0; i < 32; i++) {
            bytes[i] = addr[i];
        }
        return u256.fromBytesBE(bytes);
    }

    private _loadAddress(key: u256): Address {
        const addrU256: u256 = this.holderAddresses.get(key);
        const bytes: u8[] = addrU256.toBytesBE();
        const addr: Address = new Address(bytes);
        return addr;
    }

    private _getTotalSupply(tokenAddress: Address): u256 {
        const writer: BytesWriter = new BytesWriter(4);
        writer.writeSelector(encodeSelector('totalSupply()'));

        const result: CallResult = Blockchain.call(tokenAddress, writer, false);
        if (!result.success) {
            return u256.Zero;
        }

        return result.data.readU256();
    }
}
