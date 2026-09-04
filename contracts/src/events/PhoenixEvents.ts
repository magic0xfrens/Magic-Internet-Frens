import { u256 } from '@btc-vision/as-bignum/assembly';
import { Address, BytesWriter, NetEvent } from '@btc-vision/btc-runtime/runtime';

@final
export class CauldronSummonedEvent extends NetEvent {
    constructor(
        generation: u256,
        tokenAddress: Address,
        poolAddress: Address,
        name: string,
        symbol: string,
    ) {
        const data: BytesWriter = new BytesWriter(160);
        data.writeU256(generation);
        data.writeAddress(tokenAddress);
        data.writeAddress(poolAddress);
        data.writeStringWithLength(name);
        data.writeStringWithLength(symbol);
        super('CauldronSummoned', data);
    }
}

@final
export class CauldronDiedEvent extends NetEvent {
    constructor(
        generation: u256,
        tokenAddress: Address,
        finalVolume: u256,
        btcAmount: u256,
        tokenAmount: u256,
    ) {
        const data: BytesWriter = new BytesWriter(160);
        data.writeU256(generation);
        data.writeAddress(tokenAddress);
        data.writeU256(finalVolume);
        data.writeU256(btcAmount);
        data.writeU256(tokenAmount);
        super('CauldronDied', data);
    }
}

@final
export class CauldronRebornEvent extends NetEvent {
    constructor(
        generation: u256,
        newTokenAddress: Address,
        newPoolAddress: Address,
        name: string,
        symbol: string,
    ) {
        const data: BytesWriter = new BytesWriter(160);
        data.writeU256(generation);
        data.writeAddress(newTokenAddress);
        data.writeAddress(newPoolAddress);
        data.writeStringWithLength(name);
        data.writeStringWithLength(symbol);
        super('CauldronReborn', data);
    }
}

@final
export class HolderClaimedEvent extends NetEvent {
    constructor(
        generation: u256,
        holder: Address,
        amount: u256,
    ) {
        const data: BytesWriter = new BytesWriter(96);
        data.writeU256(generation);
        data.writeAddress(holder);
        data.writeU256(amount);
        super('HolderClaimed', data);
    }
}
