import { u256 } from '@btc-vision/as-bignum/assembly';
import { Address, BytesWriter, NetEvent } from '@btc-vision/btc-runtime/runtime';

@final
export class StakedEvent extends NetEvent {
    constructor(user: Address, frenAmount: u256, sfrenMinted: u256) {
        const data: BytesWriter = new BytesWriter(96);
        data.writeAddress(user);
        data.writeU256(frenAmount);
        data.writeU256(sfrenMinted);
        super('Staked', data);
    }
}

@final
export class UnstakeInitiatedEvent extends NetEvent {
    constructor(user: Address, sfrenBurned: u256, frenAmount: u256) {
        const data: BytesWriter = new BytesWriter(96);
        data.writeAddress(user);
        data.writeU256(sfrenBurned);
        data.writeU256(frenAmount);
        super('UnstakeInitiated', data);
    }
}

@final
export class UnstakeClaimedEvent extends NetEvent {
    constructor(user: Address, frenAmount: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(user);
        data.writeU256(frenAmount);
        super('UnstakeClaimed', data);
    }
}

@final
export class RewardDistributedEvent extends NetEvent {
    constructor(from: Address, amount: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(from);
        data.writeU256(amount);
        super('RewardDistributed', data);
    }
}
