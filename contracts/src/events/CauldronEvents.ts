import { u256 } from '@btc-vision/as-bignum/assembly';
import { Address, BytesWriter, NetEvent } from '@btc-vision/btc-runtime/runtime';

@final
export class DepositEvent extends NetEvent {
    constructor(user: Address, amount: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(user);
        data.writeU256(amount);
        super('Deposit', data);
    }
}

@final
export class BorrowEvent extends NetEvent {
    constructor(user: Address, amount: u256, fee: u256) {
        const data: BytesWriter = new BytesWriter(96);
        data.writeAddress(user);
        data.writeU256(amount);
        data.writeU256(fee);
        super('Borrow', data);
    }
}

@final
export class RepayEvent extends NetEvent {
    constructor(user: Address, amount: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(user);
        data.writeU256(amount);
        super('Repay', data);
    }
}

@final
export class WithdrawEvent extends NetEvent {
    constructor(user: Address, amount: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(user);
        data.writeU256(amount);
        super('Withdraw', data);
    }
}

@final
export class LiquidateEvent extends NetEvent {
    constructor(liquidator: Address, user: Address, debtRepaid: u256, collateralSeized: u256) {
        const data: BytesWriter = new BytesWriter(128);
        data.writeAddress(liquidator);
        data.writeAddress(user);
        data.writeU256(debtRepaid);
        data.writeU256(collateralSeized);
        super('Liquidate', data);
    }
}

@final
export class FeesDistributedEvent extends NetEvent {
    constructor(amount: u256) {
        const data: BytesWriter = new BytesWriter(32);
        data.writeU256(amount);
        super('FeesDistributed', data);
    }
}

@final
export class AccrueEvent extends NetEvent {
    constructor(interest: u256, timestamp: u64) {
        const data: BytesWriter = new BytesWriter(40);
        data.writeU256(interest);
        data.writeU64(timestamp);
        super('Accrue', data);
    }
}

@final
export class BTCPenaltiesDistributedEvent extends NetEvent {
    constructor(amount: u256) {
        const data: BytesWriter = new BytesWriter(32);
        data.writeU256(amount);
        super('BTCPenaltiesDistributed', data);
    }
}

@final
export class AdminTransferInitiatedEvent extends NetEvent {
    constructor(currentAdmin: Address, pendingAdmin: Address) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(currentAdmin);
        data.writeAddress(pendingAdmin);
        super('AdminTransferInitiated', data);
    }
}

@final
export class AdminTransferAcceptedEvent extends NetEvent {
    constructor(newAdmin: Address) {
        const data: BytesWriter = new BytesWriter(32);
        data.writeAddress(newAdmin);
        super('AdminTransferAccepted', data);
    }
}
