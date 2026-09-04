import { u256 } from '@btc-vision/as-bignum/assembly';
import { Address, BytesWriter, NetEvent } from '@btc-vision/btc-runtime/runtime';

/** Emitted when a holder checks in for the current generation. */
@final
export class OathTakenEvent extends NetEvent {
    constructor(holder: Address, generation: u256, streak: u256) {
        const data: BytesWriter = new BytesWriter(96);
        data.writeAddress(holder);
        data.writeU256(generation);
        data.writeU256(streak);
        super('OathTaken', data);
    }
}

/** Emitted when a holder's streak is reset (outgoing transfer detected). */
@final
export class OathBrokenEvent extends NetEvent {
    constructor(holder: Address, previousStreak: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(holder);
        data.writeU256(previousStreak);
        super('OathBroken', data);
    }
}

/** Emitted when trading fees are deposited into the reward pool. */
@final
export class ManaDepositedEvent extends NetEvent {
    constructor(amount: u256, newAccPerWeight: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeU256(amount);
        data.writeU256(newAccPerWeight);
        super('ManaDeposited', data);
    }
}

/** Emitted when a holder claims accumulated rewards. */
@final
export class ManaHarvestedEvent extends NetEvent {
    constructor(holder: Address, amount: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(holder);
        data.writeU256(amount);
        super('ManaHarvested', data);
    }
}
