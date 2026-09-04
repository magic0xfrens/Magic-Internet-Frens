import { u256 } from '@btc-vision/as-bignum/assembly';
import { Address, BytesWriter, NetEvent } from '@btc-vision/btc-runtime/runtime';

@final
export class NFTMintedEvent extends NetEvent {
    constructor(owner: Address, tokenId: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(owner);
        data.writeU256(tokenId);
        super('NFTMinted', data);
    }
}

@final
export class NFTLockedEvent extends NetEvent {
    constructor(tokenId: u256, lockedBy: Address) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeU256(tokenId);
        data.writeAddress(lockedBy);
        super('NFTLocked', data);
    }
}

@final
export class NFTUnlockedEvent extends NetEvent {
    constructor(tokenId: u256, unlockedBy: Address) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeU256(tokenId);
        data.writeAddress(unlockedBy);
        super('NFTUnlocked', data);
    }
}

@final
export class CauldronSummonReadyEvent extends NetEvent {
    constructor(totalMinted: u256) {
        const data: BytesWriter = new BytesWriter(32);
        data.writeU256(totalMinted);
        super('CauldronSummonReady', data);
    }
}

@final
export class TraitsUpdatedEvent extends NetEvent {
    constructor(tokenId: u256, packed: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeU256(tokenId);
        data.writeU256(packed);
        super('TraitsUpdated', data);
    }
}

@final
export class TraitInscribedEvent extends NetEvent {
    constructor(traitKey: u256, inscriber: Address, blockHeight: u256) {
        const data: BytesWriter = new BytesWriter(96);
        data.writeU256(traitKey);
        data.writeAddress(inscriber);
        data.writeU256(blockHeight);
        super('TraitInscribed', data);
    }
}

@final
export class PaletteInscribedEvent extends NetEvent {
    constructor(inscriber: Address, colorCount: u256) {
        const data: BytesWriter = new BytesWriter(64);
        data.writeAddress(inscriber);
        data.writeU256(colorCount);
        super('PaletteInscribed', data);
    }
}
