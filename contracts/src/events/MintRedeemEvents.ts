import { u256 } from '@btc-vision/as-bignum/assembly';
import { Address, BytesWriter, NetEvent } from '@btc-vision/btc-runtime/runtime';

@final
export class MintMIFEvent extends NetEvent {
    constructor(user: Address, btcIn: u256, frenIn: u256, mifMinted: u256, tcrBps: u256) {
        const data: BytesWriter = new BytesWriter(160); // 32 + 32 + 32 + 32 + 32
        data.writeAddress(user);
        data.writeU256(btcIn);
        data.writeU256(frenIn);
        data.writeU256(mifMinted);
        data.writeU256(tcrBps);
        super('MintMIF', data);
    }
}

@final
export class RedeemMIFEvent extends NetEvent {
    constructor(user: Address, mifBurned: u256, btcOut: u256, frenMinted: u256, ecrBps: u256) {
        const data: BytesWriter = new BytesWriter(160);
        data.writeAddress(user);
        data.writeU256(mifBurned);
        data.writeU256(btcOut);
        data.writeU256(frenMinted);
        data.writeU256(ecrBps);
        super('RedeemMIF', data);
    }
}

@final
export class TCRAdjustedEvent extends NetEvent {
    constructor(oldTcr: u256, newTcr: u256, timestamp: u64) {
        const data: BytesWriter = new BytesWriter(72); // 32 + 32 + 8
        data.writeU256(oldTcr);
        data.writeU256(newTcr);
        data.writeU64(timestamp);
        super('TCRAdjusted', data);
    }
}

@final
export class CircuitBreakerTrippedEvent extends NetEvent {
    constructor(blockNumber: u256, frenPrice: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeU256(blockNumber);
        data.writeU256(frenPrice);
        super('CircuitBreakerTripped', data);
    }
}

@final
export class CircuitBreakerResumedEvent extends NetEvent {
    constructor(blockNumber: u256) {
        const data: BytesWriter = new BytesWriter(32);
        data.writeU256(blockNumber);
        super('CircuitBreakerResumed', data);
    }
}
