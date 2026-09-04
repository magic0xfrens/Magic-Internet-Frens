import { u256 } from '@btc-vision/as-bignum/assembly';
import { Address, BytesWriter, NetEvent } from '@btc-vision/btc-runtime/runtime';

@final
export class PriceUpdatedEvent extends NetEvent {
    constructor(price: u256, timestamp: u64) {
        const data: BytesWriter = new BytesWriter(40); // 32 + 8
        data.writeU256(price);
        data.writeU64(timestamp);
        super('PriceUpdated', data);
    }
}

@final
export class AdminTransferredEvent extends NetEvent {
    constructor(oldAdmin: Address, newAdmin: Address) {
        const data: BytesWriter = new BytesWriter(64); // 2 addresses
        data.writeAddress(oldAdmin);
        data.writeAddress(newAdmin);
        super('AdminTransferred', data);
    }
}
