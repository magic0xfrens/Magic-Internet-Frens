import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    encodeSelector,
    OP_NET,
    Revert,
    SafeMath,
    StoredU256,
    StoredAddress,
    StoredMapU256,
} from '@btc-vision/btc-runtime/runtime';
import { CallResult } from '@btc-vision/btc-runtime/runtime/env/BlockchainEnvironment';
import { sha256 } from '@btc-vision/btc-runtime/runtime/env/global';

import {
    TOTAL_TRAIT_LAYERS,
    MERKLE_TREE_DEPTH,
    BYTES_PER_SLOT,
    CHUNK_KEY_MULTIPLIER,
    CANVAS_SIDE,
    CROP_SIDE,
    CROP_OFFSETS,
    REENTRANCY_UNLOCKED,
    REENTRANCY_LOCKED,
} from '../lib/constants';
import { quantizeColors, encodePNG4bit } from '../lib/png';
import {
    ERR_FORGE_NOT_ADMIN,
    ERR_FORGE_NOT_ART_AUTH,
    ERR_FORGE_NFT_NOT_SET,
    ERR_FORGE_MERKLE_ROOT_NOT_SET,
    ERR_FORGE_INVALID_MERKLE_PROOF,
    ERR_FORGE_INVALID_PROOF_LEN,
    ERR_FORGE_INVALID_LEAF_INDEX,
    ERR_FORGE_TRAIT_ALREADY_INSCRIBED,
    ERR_FORGE_TRAIT_NOT_INSCRIBED,
    ERR_FORGE_TRAIT_DATA_EMPTY,
    ERR_FORGE_PALETTE_NOT_SET,
    ERR_FORGE_ZERO_ADDR,
    ERR_FORGE_TOKEN_NOT_EXIST,
    ERR_FORGE_MINT_FAILED,
    ERR_FORGE_PAYMENT_REQUIRED,
    ERR_FORGE_INVALID_PART,
    ERR_FORGE_REENTRANT,
} from '../lib/errors';
import {
    TraitInscribedEvent,
} from '../events/NFTEvents';

// ---------------------------------------------------------------------------
// Lookup Tables (StaticArray<u8> — zero-alloc, compile-time)
// ---------------------------------------------------------------------------

// 28×28 BTC ₿ logo bitmap — packed row-major, MSB first. 784 bits = 98 bytes.
// Logo cells (1) get light orange background, non-logo cells (0) get standard BTC orange.
// @ts-ignore: decorator
@inline
const BTC_LOGO_BITS: StaticArray<u8> = [
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   3,  48,   0,   0,  51,   0,   0,  15, 248,   0,
    0, 255, 192,   0,   3,  14,   0,   0,  48,  96,   0,   3,   6,   0,
    0,  48, 224,   0,   3, 252,   0,   0,  63, 224,   0,   3,   7,   0,
    0,  48,  48,   0,   3,   7,   0,   0, 255, 224,   0,  15, 252,   0,
    0,  51,   0,   0,   3,  48,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
];

const GRID_TOTAL: u64 = 784; // 28 × 28

// Nibble → ASCII hex byte (16 entries: 0-9, a-f)
// @ts-ignore: decorator
@inline
const HEX_LUT: StaticArray<u8> = [
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, // 0-9
    97, 98, 99, 100, 101, 102,               // a-f
];

// SVG fragment bytes for path-based rendering
// @ts-ignore: decorator
@inline
const PATH_OPEN: StaticArray<u8> = [60, 112, 97, 116, 104, 32, 100, 61, 34]; // '<path d="'
// @ts-ignore: decorator
@inline
const PATH_FILL: StaticArray<u8> = [34, 32, 102, 105, 108, 108, 61, 34, 35]; // '" fill="#'
// @ts-ignore: decorator
@inline
const PATH_CLOSE: StaticArray<u8> = [34, 47, 62]; // '"/>'
// @ts-ignore: decorator
@inline
const SVG_CLOSE: StaticArray<u8> = [60, 47, 115, 118, 103, 62]; // '</svg>'

// Base64 encoding table (A-Z, a-z, 0-9, +, /)
// @ts-ignore: decorator
@inline
const B64_TABLE: StaticArray<u8> = [
    65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90, // A-Z
    97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122, // a-z
    48,49,50,51,52,53,54,55,56,57, // 0-9
    43,47, // +/
];

// Per-class background colors (RGB888): Wizard, King, Knight, Apprentice, Peasant, Gnome, Elf
// @ts-ignore: decorator
@inline
const CLASS_BG_COLORS: StaticArray<u8> = [
    0xa7, 0x8b, 0xfa,  // 0: Wizard  (#a78bfa)
    0xff, 0xd7, 0x00,  // 1: King    (#FFD700)
    0x75, 0xc9, 0xee,  // 2: Knight  (#75c9ee)
    0xf7, 0x93, 0x1a,  // 3: Apprentice (#F7931A)
    0x9c, 0xa3, 0xaf,  // 4: Peasant (#9ca3af)
    0xe9, 0x48, 0x48,  // 5: Gnome   (#E94848)
    0x4a, 0xde, 0x80,  // 6: Elf     (#4ade80)
];

/**
 * FrenForge -- On-chain SVG renderer & mint gateway for MiFrens NFTs.
 *
 * Stores trait image data and global palette via Merkle-verified inscriptions.
 * Cross-contract calls MiFrens to read trait indices for a given tokenId.
 * Renders full SVG images and returns JSON metadata (tokenURI).
 *
 * Base class: OP_NET (no OP721/OP20 overhead -- keeps WASM small).
 */
@final
export class FrenForge extends OP_NET {
    // -----------------------------------------------------------------------
    // Storage Pointers
    // -----------------------------------------------------------------------

    private readonly nftContractPointer: u16 = Blockchain.nextPointer;
    private readonly merkleRootPointer: u16 = Blockchain.nextPointer;
    private readonly traitImageDataPointer: u16 = Blockchain.nextPointer;
    private readonly traitImageStatusPointer: u16 = Blockchain.nextPointer;
    private readonly traitInscriptionBlockPointer: u16 = Blockchain.nextPointer;
    private readonly totalTraitsInscribedPointer: u16 = Blockchain.nextPointer;
    private readonly artAuthorityPointer: u16 = Blockchain.nextPointer;
    private readonly treasuryPointer: u16 = Blockchain.nextPointer;
    private readonly treasuryScriptHashPointer: u16 = Blockchain.nextPointer;
    private readonly _reservedOgPointer: u16 = Blockchain.nextPointer; // Reserved (OG inscribers moved to MiFrens)
    private readonly _reservedBaseURIPointer: u16 = Blockchain.nextPointer; // Reserved (IPFS base URI removed)
    private readonly reentrancyPointer: u16 = Blockchain.nextPointer; // Was _reservedRevealedPointer
    private readonly _reservedUnrevealedPointer: u16 = Blockchain.nextPointer; // Reserved (reveal removed)

    // -----------------------------------------------------------------------
    // Storage Instances
    // -----------------------------------------------------------------------

    private _nftContract!: StoredAddress;
    private _merkleRoot!: StoredU256;
    private _traitImageData!: StoredMapU256;
    private _traitImageStatus!: StoredMapU256;
    private _traitInscriptionBlock!: StoredMapU256;
    private _totalTraitsInscribed!: StoredU256;
    private _artAuthority!: StoredAddress;
    private _treasury!: StoredAddress;
    private _treasuryScriptHash!: StoredU256;
    private _reentrancyGuard!: StoredU256;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    public constructor() {
        super();

        this._nftContract = new StoredAddress(this.nftContractPointer);
        this._merkleRoot = new StoredU256(this.merkleRootPointer, new Uint8Array(0));
        this._traitImageData = new StoredMapU256(this.traitImageDataPointer);
        this._traitImageStatus = new StoredMapU256(this.traitImageStatusPointer);
        this._traitInscriptionBlock = new StoredMapU256(this.traitInscriptionBlockPointer);
        this._totalTraitsInscribed = new StoredU256(this.totalTraitsInscribedPointer, new Uint8Array(0));
        this._artAuthority = new StoredAddress(this.artAuthorityPointer);
        this._treasury = new StoredAddress(this.treasuryPointer);
        this._treasuryScriptHash = new StoredU256(this.treasuryScriptHashPointer, new Uint8Array(0));
        this._reentrancyGuard = new StoredU256(this.reentrancyPointer, new Uint8Array(0));
    }

    // -----------------------------------------------------------------------
    // Deployment
    // -----------------------------------------------------------------------

    public override onDeployment(_calldata: Calldata): void {
        // Art authority defaults to deployer
        this._artAuthority.value = Blockchain.tx.sender;
    }

    // -----------------------------------------------------------------------
    // Admin Methods (deployer only)
    // -----------------------------------------------------------------------

    @method({ name: 'nftContract', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setNFTContract(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const addr: Address = calldata.readAddress();
        if (addr.equals(Address.zero())) {
            throw new Revert(ERR_FORGE_ZERO_ADDR);
        }
        this._nftContract.value = addr;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'root', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setMerkleRoot(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const root: u256 = calldata.readU256();
        this._merkleRoot.value = root;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'authority', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setArtAuthority(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const authority: Address = calldata.readAddress();
        if (authority.equals(Address.zero())) {
            throw new Revert(ERR_FORGE_ZERO_ADDR);
        }
        this._artAuthority.value = authority;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'treasury', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setTreasury(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const treasury: Address = calldata.readAddress();
        if (treasury.equals(Address.zero())) {
            throw new Revert(ERR_FORGE_ZERO_ADDR);
        }
        this._treasury.value = treasury;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * Stores sha256(treasury_bech32_string) for payment verification.
     * During simulation, output.to is the bech32 address string.
     * The contract computes sha256(output.to) and compares against this hash.
     */
    @method({ name: 'scriptHash', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setTreasuryScriptHash(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const hash: u256 = calldata.readU256();
        this._treasuryScriptHash.value = hash;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * batchInscribeAll(data) -- Deployer-only batch inscription.
     *
     * Packed blob format (no Merkle proofs):
     *   [count: u16 BE]
     *   For each entry:
     *     [traitKey: u32 BE] [dataLen: u16 BE] [data: bytes]
     *
     * Skips traits that are already inscribed. Returns number inscribed.
     */
    @method({ name: 'data', type: ABIDataTypes.BYTES })
    @returns({ name: 'count', type: ABIDataTypes.UINT256 })
    public batchInscribeAll(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const blob: Uint8Array = calldata.readBytesWithLength();
        if (blob.length < 2) throw new Revert('batch: empty');

        let off: i32 = 0;

        // Read trait count (u16 BE)
        const count: u32 = ((blob[off] as u32) << 8) | (blob[off + 1] as u32);
        off += 2;

        let inscribed: u32 = 0;

        for (let i: u32 = 0; i < count; i++) {
            // traitKey (u32 BE)
            const tk: u32 =
                ((blob[off] as u32) << 24) |
                ((blob[off + 1] as u32) << 16) |
                ((blob[off + 2] as u32) << 8) |
                (blob[off + 3] as u32);
            off += 4;

            // dataLen (u16 BE)
            const dataLen: u32 =
                ((blob[off] as u32) << 8) | (blob[off + 1] as u32);
            off += 2;

            // data
            const data: Uint8Array = blob.slice(off, off + (dataLen as i32));
            off += dataLen as i32;

            if (data.length == 0) continue;

            const key: u256 = u256.fromU64(tk as u64);

            // Skip already inscribed
            const existing: u256 = this._traitImageStatus.get(key);
            if (!existing.isZero()) continue;

            this._storeChunkedData(key, data);

            const blockHeight: u256 = u256.fromU64(Blockchain.block.number);
            this._traitInscriptionBlock.set(key, blockHeight);

            const total: u256 = this._totalTraitsInscribed.value;
            this._totalTraitsInscribed.value = SafeMath.add(total, u256.One);

            inscribed++;
        }

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(u256.fromU64(inscribed as u64));
        return writer;
    }

    @method(
        { name: 'traitKey', type: ABIDataTypes.UINT256 },
        { name: 'data', type: ABIDataTypes.BYTES },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public updateTraitImage(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const traitKey: u256 = calldata.readU256();
        const data: Uint8Array = calldata.readBytesWithLength();

        if (data.length == 0) {
            throw new Revert(ERR_FORGE_TRAIT_DATA_EMPTY);
        }

        this._storeChunkedData(traitKey, data);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'traitKey', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public deleteTraitImage(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const traitKey: u256 = calldata.readU256();
        const storedLen: u256 = this._traitImageStatus.get(traitKey);
        if (storedLen.isZero()) {
            throw new Revert(ERR_FORGE_TRAIT_NOT_INSCRIBED);
        }

        // Clear chunk data (compute chunk count from stored byte length)
        const dataLen: u64 = storedLen.toU64();
        const chunks: u64 = (dataLen + (BYTES_PER_SLOT as u64) - 1) / (BYTES_PER_SLOT as u64);
        for (let i: u64 = 0; i < chunks; i++) {
            const slotKey: u256 = SafeMath.add(
                SafeMath.mul(traitKey, CHUNK_KEY_MULTIPLIER),
                u256.fromU64(i),
            );
            this._traitImageData.delete(slotKey);
        }

        this._traitImageStatus.set(traitKey, u256.Zero);
        this._traitInscriptionBlock.delete(traitKey);

        const total: u256 = this._totalTraitsInscribed.value;
        if (!total.isZero()) {
            this._totalTraitsInscribed.value = SafeMath.sub(total, u256.One);
        }

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Art Authority Methods
    // -----------------------------------------------------------------------

    @method(
        { name: 'traitKey', type: ABIDataTypes.UINT256 },
        { name: 'data', type: ABIDataTypes.BYTES },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public inscribeTrait(calldata: Calldata): BytesWriter {
        this._onlyArtAuthority();

        const traitKey: u256 = calldata.readU256();
        calldata.readU32(); // consume BYTES length prefix from ABI encoding
        const leafIndex: u32 = calldata.readU32();

        // Read proof length then proof elements
        const proofLen: u32 = calldata.readU32();
        if (proofLen != MERKLE_TREE_DEPTH) {
            throw new Revert(ERR_FORGE_INVALID_PROOF_LEN);
        }
        const proof: u256[] = new Array<u256>(proofLen);
        for (let i: u32 = 0; i < proofLen; i++) {
            proof[i] = calldata.readU256();
        }

        const data: Uint8Array = calldata.readBytesWithLength();
        if (data.length == 0) {
            throw new Revert(ERR_FORGE_TRAIT_DATA_EMPTY);
        }

        // Check not already inscribed
        const existing: u256 = this._traitImageStatus.get(traitKey);
        if (!existing.isZero()) {
            throw new Revert(ERR_FORGE_TRAIT_ALREADY_INSCRIBED);
        }

        // Verify Merkle proof
        const merkleRoot: u256 = this._merkleRoot.value;
        if (merkleRoot.isZero()) {
            throw new Revert(ERR_FORGE_MERKLE_ROOT_NOT_SET);
        }

        // Leaf = sha256(traitKey || data)
        const leafHash: Uint8Array = this._computeLeafHash(traitKey, data);

        if (!this._verifyMerkleProof(proof, leafHash, leafIndex, merkleRoot)) {
            throw new Revert(ERR_FORGE_INVALID_MERKLE_PROOF);
        }

        // Store chunked data
        this._storeChunkedData(traitKey, data);

        // Update inscription block
        const blockHeight: u256 = u256.fromU64(Blockchain.block.number);
        this._traitInscriptionBlock.set(traitKey, blockHeight);

        // Increment total inscribed
        const total: u256 = this._totalTraitsInscribed.value;
        this._totalTraitsInscribed.value = SafeMath.add(total, u256.One);

        this.emitEvent(new TraitInscribedEvent(traitKey, Blockchain.tx.sender, blockHeight));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Gated Mint -- User must provide valid trait data to mint
    // -----------------------------------------------------------------------

    /**
     * mint(traitKey, leafIndex, proof[], data) -- Gated mint entry point.
     *
     * User provides one valid trait key + leaf index + Merkle proof + image data.
     * The renderer verifies the proof, inscribes the trait if new,
     * then cross-contract calls nft.mintFor(user).
     *
     * This ensures only users with access to trait data (via frontend)
     * can mint. Bots would need the entire trait data pipeline.
     */
    @method(
        { name: 'traitKey', type: ABIDataTypes.UINT256 },
        { name: 'data', type: ABIDataTypes.BYTES },
    )
    @returns({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    public mint(calldata: Calldata): BytesWriter {
        // Reentrancy guard
        this._nonReentrant();

        // NFT contract must be set
        if (this._nftContract.isDead()) {
            throw new Revert(ERR_FORGE_NFT_NOT_SET);
        }

        const traitKey: u256 = calldata.readU256();
        calldata.readU32(); // consume BYTES length prefix from ABI encoding
        const leafIndex: u32 = calldata.readU32();

        // Read Merkle proof (fixed length = MERKLE_TREE_DEPTH)
        const proofLen: u32 = calldata.readU32();
        if (proofLen != MERKLE_TREE_DEPTH) {
            throw new Revert(ERR_FORGE_INVALID_PROOF_LEN);
        }
        const proof: u256[] = new Array<u256>(proofLen);
        for (let i: u32 = 0; i < proofLen; i++) {
            proof[i] = calldata.readU256();
        }

        const data: Uint8Array = calldata.readBytesWithLength();
        if (data.length == 0) {
            throw new Revert(ERR_FORGE_TRAIT_DATA_EMPTY);
        }

        // Verify Merkle proof (always required, even if trait already inscribed)
        const merkleRoot: u256 = this._merkleRoot.value;
        if (merkleRoot.isZero()) {
            throw new Revert(ERR_FORGE_MERKLE_ROOT_NOT_SET);
        }

        // Leaf = sha256(traitKey || data)
        const leafHash: Uint8Array = this._computeLeafHash(traitKey, data);

        if (!this._verifyMerkleProof(proof, leafHash, leafIndex, merkleRoot)) {
            throw new Revert(ERR_FORGE_INVALID_MERKLE_PROOF);
        }

        // Inscribe trait/color if not already on-chain
        const existing: u256 = this._traitImageStatus.get(traitKey);
        let isNewInscription: bool = false;
        if (existing.isZero()) {
            this._storeChunkedData(traitKey, data);

            const blockHeight: u256 = u256.fromU64(Blockchain.block.number);
            this._traitInscriptionBlock.set(traitKey, blockHeight);

            const total: u256 = this._totalTraitsInscribed.value;
            this._totalTraitsInscribed.value = SafeMath.add(total, u256.One);

            this.emitEvent(new TraitInscribedEvent(traitKey, Blockchain.tx.sender, blockHeight));
            isNewInscription = true;
        }

        // Verify BTC payment to treasury before minting
        const nft: Address = this._nftContract.value;
        this._verifyMintPayment(nft);

        // Cross-contract call: nft.mintFor(sender)
        const mintWriter: BytesWriter = new BytesWriter(36);
        mintWriter.writeSelector(encodeSelector('mintFor(address)'));
        mintWriter.writeAddress(Blockchain.tx.sender);

        const mintResult: CallResult = Blockchain.call(nft, mintWriter, true);
        if (!mintResult.success) {
            this._releaseReentrancy();
            throw new Revert(ERR_FORGE_MINT_FAILED);
        }
        const tokenId: u256 = mintResult.data.readU256();

        // Auto-mark OG inscriber if this mint inscribed new data
        if (isNewInscription) {
            const ogWriter: BytesWriter = new BytesWriter(36);
            ogWriter.writeSelector(encodeSelector('markOGInscriber(uint256)'));
            ogWriter.writeU256(tokenId);
            const ogResult: CallResult = Blockchain.call(nft, ogWriter, true);
            // OG marking is best-effort — log failure but don't revert the mint
            if (!ogResult.success) {
                // Soft failure: mint succeeds, OG badge not set
            }
        }

        this._releaseReentrancy();

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(tokenId);
        return writer;
    }

    // -----------------------------------------------------------------------
    // View Methods
    // -----------------------------------------------------------------------

    @method()
    @returns({ name: 'authority', type: ABIDataTypes.ADDRESS })
    public getArtAuthority(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeAddress(this._artAuthority.value);
        return writer;
    }

    @method({ name: 'traitKey', type: ABIDataTypes.UINT256 })
    @returns({ name: 'inscribed', type: ABIDataTypes.BOOL })
    public isTraitInscribed(calldata: Calldata): BytesWriter {
        const traitKey: u256 = calldata.readU256();
        const status: u256 = this._traitImageStatus.get(traitKey);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(!status.isZero());
        return writer;
    }

    @method({ name: 'traitKey', type: ABIDataTypes.UINT256 })
    @returns({ name: 'data', type: ABIDataTypes.BYTES })
    public getTraitImage(calldata: Calldata): BytesWriter {
        const traitKey: u256 = calldata.readU256();
        const data: Uint8Array = this._readChunkedData(traitKey);

        const writer: BytesWriter = new BytesWriter(4 + data.length);
        writer.writeBytesWithLength(data);
        return writer;
    }

    @method()
    @returns({ name: 'data', type: ABIDataTypes.BYTES })
    public getGlobalPalette(_calldata: Calldata): BytesWriter {
        const data: Uint8Array = this._readPaletteFromBatches();

        const writer: BytesWriter = new BytesWriter(4 + data.length);
        writer.writeBytesWithLength(data);
        return writer;
    }

    @method()
    @returns(
        { name: 'totalInscribed', type: ABIDataTypes.UINT256 },
    )
    public getInscriptionStats(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._totalTraitsInscribed.value);
        return writer;
    }

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'uri', type: ABIDataTypes.STRING })
    /**
     * tokenURI — Returns on-chain data URI for the token metadata.
     * Renders PNG from inscribed traits and returns data:application/json URI.
     */
    public tokenURI(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();

        // Verify NFT contract is set (token existence proxy)
        if (this._nftContract.isDead()) {
            throw new Revert(ERR_FORGE_NFT_NOT_SET);
        }

        return this._buildTokenURI(tokenId);
    }

    /**
     * renderTokenURI — Called by MiFrens.tokenURI via cross-contract call.
     * MiFrens sends 6 params (tokenId + 5 trait indices).
     * Uses all params directly to avoid calling back to MiFrens.
     */
    @method(
        { name: 'tokenId', type: ABIDataTypes.UINT256 },
        { name: 'classIdx', type: ABIDataTypes.UINT256 },
        { name: 'bodyIdx', type: ABIDataTypes.UINT256 },
        { name: 'faceIdx', type: ABIDataTypes.UINT256 },
        { name: 'itemIdx', type: ABIDataTypes.UINT256 },
        { name: 'subitemIdx', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'uri', type: ABIDataTypes.STRING })
    public renderTokenURI(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        const classIdx: u64 = calldata.readU256().toU64();
        const bodyIdx: u64 = calldata.readU256().toU64();
        const faceIdx: u64 = calldata.readU256().toU64();
        const itemIdx: u64 = calldata.readU256().toU64();
        const subitemIdx: u64 = calldata.readU256().toU64();

        // Use the trait indices passed by MiFrens directly,
        // avoiding a cross-contract callback that triggers ReentrancyGuard.
        return this._buildTokenURIFromTraits(tokenId, classIdx, bodyIdx, faceIdx, itemIdx, subitemIdx);
    }

    /**
     * tokenSvgURI — Returns the on-chain SVG in 1,500-byte chunks.
     * Each chunk fits within OPNet's 2,048-byte receipt limit.
     *
     * Returns (totalParts, svgChunk) where svgChunk is a string fragment.
     * Callers reassemble by concatenating chunks for part=0..totalParts-1.
     */
    @method(
        { name: 'tokenId', type: ABIDataTypes.UINT256 },
        { name: 'part', type: ABIDataTypes.UINT256 },
        { name: 'classIdx', type: ABIDataTypes.UINT256 },
        { name: 'bodyIdx', type: ABIDataTypes.UINT256 },
        { name: 'faceIdx', type: ABIDataTypes.UINT256 },
        { name: 'itemIdx', type: ABIDataTypes.UINT256 },
        { name: 'subitemIdx', type: ABIDataTypes.UINT256 },
    )
    @returns(
        { name: 'totalParts', type: ABIDataTypes.UINT256 },
        { name: 'svgChunk', type: ABIDataTypes.STRING },
    )
    public tokenSvgURI(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        const part: u256 = calldata.readU256();
        const partIdx: u64 = part.toU64();

        // Accept trait indices directly to avoid cross-contract callback
        const classIdx: u64 = calldata.readU256().toU64();
        const bodyIdx: u64 = calldata.readU256().toU64();
        const faceIdx: u64 = calldata.readU256().toU64();
        const itemIdx: u64 = calldata.readU256().toU64();
        const subitemIdx: u64 = calldata.readU256().toU64();

        // Read palette from inscribed color batches
        const palette: Uint8Array = this._readPaletteFromBatches();
        if (palette.length == 0) {
            throw new Revert(ERR_FORGE_PALETTE_NOT_SET);
        }

        // Compute trait keys
        const bodyKey: u64 = classIdx * 256 + bodyIdx;
        const faceClassIdx: u64 = (classIdx == 5) ? 5 : (classIdx == 6) ? 6 : 0;
        const faceKey: u64 = 65536 + faceClassIdx * 256 + faceIdx;
        const itemKey: u64 = 131072 + classIdx * 256 + itemIdx;
        const bodyData: Uint8Array = this._readChunkedData(u256.fromU64(bodyKey));
        const faceData: Uint8Array = this._readChunkedData(u256.fromU64(faceKey));
        const itemData: Uint8Array = this._readChunkedData(u256.fromU64(itemKey));

        // Read subitem data (layerType=3)
        // Peasant (classIdx=4): hats at 3*65536 + 4*256 + layerIdx
        // Other classes: shared subitems at 3*65536 + 0*256 + layerIdx
        let subitemData: Uint8Array = new Uint8Array(0);
        if (subitemIdx > 0) {
            const subitemClassIdx: u64 = (classIdx == 4) ? 4 : 0;
            const subitemKey: u64 = 196608 + subitemClassIdx * 256 + (subitemIdx - 1);
            subitemData = this._readChunkedData(u256.fromU64(subitemKey));
        }

        // Render full SVG
        const svgBuf: Uint8Array = this._renderSVGToBuffer(
            palette, bodyData, faceData, itemData, subitemData,
            classIdx, bodyIdx, faceIdx, itemIdx,
        );

        // Chunk size = 1500 bytes
        const CHUNK_SIZE: u64 = 1500;
        const svgLen: u64 = svgBuf.length as u64;
        const totalParts: u64 = (svgLen + CHUNK_SIZE - 1) / CHUNK_SIZE;

        if (partIdx >= totalParts) {
            throw new Revert(ERR_FORGE_INVALID_PART);
        }

        // Extract chunk
        const startByte: u64 = partIdx * CHUNK_SIZE;
        const endByte: u64 = (startByte + CHUNK_SIZE < svgLen) ? startByte + CHUNK_SIZE : svgLen;
        const chunkLen: u64 = endByte - startByte;

        const chunkBuf: Uint8Array = new Uint8Array(chunkLen as i32);
        for (let i: u64 = 0; i < chunkLen; i++) {
            chunkBuf[i as i32] = svgBuf[(startByte + i) as i32];
        }

        const chunkStr: string = String.UTF8.decode(chunkBuf.buffer);

        // Return (totalParts, svgChunk)
        const writer: BytesWriter = new BytesWriter(32 + 4 + chunkStr.length);
        writer.writeU256(u256.fromU64(totalParts));
        writer.writeStringWithLength(chunkStr);
        return writer;
    }

    /**
     * Returns the body variant display name for a given class + body index.
     */
    private _bodyVariantName(classIdx: u64, bodyIdx: u64): string {
        if (classIdx == 0) {
            if (bodyIdx == 0) return 'I';
            if (bodyIdx == 1) return 'II';
            if (bodyIdx == 2) return 'III';
            if (bodyIdx == 3) return 'IV';
            if (bodyIdx == 4) return 'V';
            if (bodyIdx == 5) return 'VI';
            if (bodyIdx == 6) return 'Manifest';
            if (bodyIdx == 7) return 'BTC';
        }
        if (classIdx == 1) {
            if (bodyIdx == 0) return 'Black';
            if (bodyIdx == 1) return 'Blue';
            if (bodyIdx == 2) return 'Orange';
            if (bodyIdx == 3) return 'Red';
            if (bodyIdx == 4) return 'White';
        }
        if (classIdx == 2) {
            if (bodyIdx == 0) return 'Bronze';
            if (bodyIdx == 1) return 'Gold';
            if (bodyIdx == 2) return 'Orange';
            if (bodyIdx == 3) return 'Silver';
        }
        if (classIdx == 3) {
            if (bodyIdx == 0) return 'I';
            if (bodyIdx == 1) return 'II';
            if (bodyIdx == 2) return 'Orange';
        }
        if (classIdx == 4) {
            if (bodyIdx == 0) return 'I';
            if (bodyIdx == 1) return 'II';
        }
        if (classIdx == 5) {
            if (bodyIdx == 0) return 'I';
            if (bodyIdx == 1) return 'II';
        }
        if (classIdx == 6) {
            if (bodyIdx == 0) return 'I';
            if (bodyIdx == 1) return 'II';
            if (bodyIdx == 2) return 'III';
        }
        return 'Unknown';
    }

    /**
     * Returns the face variant display name for a given face index.
     * Shared naming across all class types (12 faces each).
     */
    private _faceVariantName(faceIdx: u64): string {
        if (faceIdx == 0) return 'Face 1';
        if (faceIdx == 1) return 'Face 2';
        if (faceIdx == 2) return 'Face 3';
        if (faceIdx == 3) return 'Face 4';
        if (faceIdx == 4) return 'Face 5';
        if (faceIdx == 5) return 'Face 6';
        if (faceIdx == 6) return 'Face 7';
        if (faceIdx == 7) return 'Face 8';
        if (faceIdx == 8) return 'Face 9';
        if (faceIdx == 9) return 'Face 10';
        if (faceIdx == 10) return 'Face 11';
        if (faceIdx == 11) return 'Laser Eyes';
        return 'Unknown';
    }

    /**
     * Returns the item variant display name for a given class + item index.
     */
    private _itemVariantName(classIdx: u64, itemIdx: u64): string {
        if (classIdx == 0) {
            if (itemIdx == 0) return 'Staff I';
            if (itemIdx == 1) return 'Staff II';
            if (itemIdx == 2) return 'Staff III';
            if (itemIdx == 3) return 'Staff IV';
            if (itemIdx == 4) return 'Staff Manifest';
        }
        if (classIdx == 1) {
            if (itemIdx == 0) return 'Scepter Black';
            if (itemIdx == 1) return 'Scepter Blue';
            if (itemIdx == 2) return 'Scepter Red';
            if (itemIdx == 3) return 'Scepter White';
        }
        if (classIdx == 2) {
            if (itemIdx == 0) return 'Shield Bronze';
            if (itemIdx == 1) return 'Shield Gold';
            if (itemIdx == 2) return 'Shield Orange';
            if (itemIdx == 3) return 'Shield Silver';
        }
        if (classIdx == 3) return 'Tome';
        if (classIdx == 4) {
            if (itemIdx == 0) return 'Pitchfork';
            if (itemIdx == 1) return 'Shovel';
            if (itemIdx == 2) return 'Hoe';
        }
        if (classIdx == 5) {
            if (itemIdx == 0) return 'Pick I';
            if (itemIdx == 1) return 'Pick II';
            if (itemIdx == 2) return 'Pick III';
        }
        if (classIdx == 6) return 'Bow';
        return 'Unknown';
    }

    /**
     * Internal: returns the token URI as an on-chain data URI.
     * Renders a PNG image from inscribed trait data and encodes it as:
     *   data:application/json;base64,<base64({"name":"<Class> #N","image":"data:image/png;base64,..."})>
     */
    private _buildTokenURI(tokenId: u256): BytesWriter {
        // Cross-contract call to get token traits (used by tokenSvgURI / direct calls)
        const nft: Address = this._nftContract.value;
        const cw: BytesWriter = new BytesWriter(36);
        cw.writeSelector(encodeSelector('getTokenTraits(uint256)'));
        cw.writeU256(tokenId);
        const result: CallResult = Blockchain.call(nft, cw, true);

        if (!result.success) {
            throw new Revert(ERR_FORGE_TOKEN_NOT_EXIST);
        }

        const classIdx: u64 = result.data.readU256().toU64();
        const bodyIdx: u64 = result.data.readU256().toU64();
        const faceIdx: u64 = result.data.readU256().toU64();
        const itemIdx: u64 = result.data.readU256().toU64();
        const subitemIdx: u64 = result.data.readU256().toU64();

        return this._buildTokenURIFromTraits(tokenId, classIdx, bodyIdx, faceIdx, itemIdx, subitemIdx);
    }

    /**
     * Build token URI from pre-resolved trait indices.
     * Used by renderTokenURI (cross-contract from MiFrens) to avoid
     * calling back to MiFrens which triggers ReentrancyGuard.
     */
    private _buildTokenURIFromTraits(
        tokenId: u256,
        classIdx: u64,
        bodyIdx: u64,
        faceIdx: u64,
        itemIdx: u64,
        subitemIdx: u64,
    ): BytesWriter {
        // Read palette from inscribed color batches
        const palette: Uint8Array = this._readPaletteFromBatches();
        if (palette.length == 0) {
            throw new Revert(ERR_FORGE_PALETTE_NOT_SET);
        }

        // Background color: light orange or BTC orange based on ₿ logo grid position
        // Logo cells (tokenId maps to a 1-bit in BTC_LOGO_BITS) get light orange (#FFB84D)
        // Non-logo cells get standard BTC orange (#F7931A)
        const gridPos: u64 = tokenId.toU64() - 1;
        const isLogo: bool = gridPos < GRID_TOTAL && this._isLogoCell(gridPos);
        const bgR: u8 = isLogo ? 0xFF : 0xF7;
        const bgG: u8 = isLogo ? 0xB8 : 0x93;
        const bgB: u8 = isLogo ? 0x4D : 0x1A;

        let bgCanvasValue: u8 = 0;
        const palColors: i32 = palette.length / 3;
        for (let i: i32 = 0; i < palColors; i++) {
            if (palette[i * 3] == bgR && palette[i * 3 + 1] == bgG && palette[i * 3 + 2] == bgB) {
                bgCanvasValue = (i + 1) as u8;
                break;
            }
        }

        let usePalette: Uint8Array = palette;
        if (bgCanvasValue == 0) {
            // Append bg color to palette copy
            usePalette = new Uint8Array(palette.length + 3);
            for (let i: i32 = 0; i < palette.length; i++) {
                usePalette[i] = palette[i];
            }
            usePalette[palette.length] = bgR;
            usePalette[palette.length + 1] = bgG;
            usePalette[palette.length + 2] = bgB;
            bgCanvasValue = (palColors + 1) as u8;
        }

        // Compute trait keys (same logic as tokenSvgURI)
        const bodyKey: u64 = classIdx * 256 + bodyIdx;
        const faceClassIdx: u64 = (classIdx == 5) ? 5 : (classIdx == 6) ? 6 : 0;
        const faceKey: u64 = 65536 + faceClassIdx * 256 + faceIdx;
        const itemKey: u64 = 131072 + classIdx * 256 + itemIdx;
        const bodyData: Uint8Array = this._readChunkedData(u256.fromU64(bodyKey));
        const faceData: Uint8Array = this._readChunkedData(u256.fromU64(faceKey));
        const itemData: Uint8Array = this._readChunkedData(u256.fromU64(itemKey));

        let subitemData: Uint8Array = new Uint8Array(0);
        if (subitemIdx > 0) {
            const subitemClassIdx: u64 = (classIdx == 4) ? 4 : 0;
            const subitemKey: u64 = 196608 + subitemClassIdx * 256 + (subitemIdx - 1);
            subitemData = this._readChunkedData(u256.fromU64(subitemKey));
        }

        // Render 4-bit PNG at 64×64 crop with solid background
        const pngBytes: Uint8Array = this._renderPNG(classIdx, usePalette, bodyData, faceData, itemData, subitemData, bgCanvasValue);
        return this._buildDataUri(tokenId, classIdx, pngBytes);
    }

    /**
     * Build URL-encoded JSON data URI from PNG bytes.
     * Uses data:application/json,{url-encoded JSON} to stay within the
     * ~2000-byte return limit.  Only " { } # and space need encoding;
     * reserved chars like : ; / + = , are valid in data URI content per RFC 2397.
     */
    private _buildDataUri(tokenId: u256, classIdx: u64, pngBytes: Uint8Array): BytesWriter {
        const b64Png: string = this._base64Encode(pngBytes);
        const className: string = this._classIdxToName(classIdx);
        const json: string = '{"name":"' + className + ' #' + tokenId.toString()
            + '","image":"data:image/png;base64,' + b64Png + '"}';

        // URL-encode only non-urlchar characters: " { } # space
        // Reserved chars (: ; / + = ,) are valid in data URI content per RFC 2397
        let urlJson: string = '';
        for (let i: i32 = 0; i < json.length; i++) {
            const ch: i32 = json.charCodeAt(i);
            if (ch == 0x22) {        // "
                urlJson += '%22';
            } else if (ch == 0x7B) { // {
                urlJson += '%7B';
            } else if (ch == 0x7D) { // }
                urlJson += '%7D';
            } else if (ch == 0x23) { // #
                urlJson += '%23';
            } else if (ch == 0x20) { // space
                urlJson += '%20';
            } else {
                urlJson += json.charAt(i);
            }
        }

        const dataUri: string = 'data:application/json,' + urlJson;

        const writer: BytesWriter = new BytesWriter(4 + dataUri.length);
        writer.writeStringWithLength(dataUri);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Internal: BTC Logo Grid
    // -----------------------------------------------------------------------

    private _isLogoCell(gridPos: u64): bool {
        const bitIndex: u32 = gridPos as u32;
        const byteIndex: u32 = bitIndex >> 3;
        const bitOffset: u32 = 7 - (bitIndex & 7); // MSB first
        if (byteIndex >= 98) return false;
        return ((BTC_LOGO_BITS[byteIndex] >> (bitOffset as u8)) & 1) == 1;
    }

    // -----------------------------------------------------------------------
    // Internal: Data Storage (Chunking)
    // -----------------------------------------------------------------------

    /**
     * Stores arbitrary byte data across u256 storage slots.
     * Each slot holds BYTES_PER_SLOT (32) bytes.
     * Slot key = traitKey * CHUNK_KEY_MULTIPLIER + chunkIndex.
     * Status map stores the actual byte length (not chunk count).
     */
    private _storeChunkedData(traitKey: u256, data: Uint8Array): void {
        const totalChunks: u32 = (data.length + BYTES_PER_SLOT - 1) / BYTES_PER_SLOT;
        const baseKey: u256 = SafeMath.mul(traitKey, CHUNK_KEY_MULTIPLIER);

        for (let i: u32 = 0; i < totalChunks; i++) {
            const offset: u32 = i * BYTES_PER_SLOT;
            const remaining: u32 = data.length - offset;
            const chunkLen: u32 = remaining < BYTES_PER_SLOT ? remaining : BYTES_PER_SLOT;

            // Pad to 32 bytes
            const padded: u8[] = new Array<u8>(32);
            for (let j: u32 = 0; j < 32; j++) {
                padded[j] = 0;
            }
            for (let j: u32 = 0; j < chunkLen; j++) {
                padded[j] = data[offset + j];
            }

            const slotKey: u256 = SafeMath.add(baseKey, u256.fromU64(i));
            const value: u256 = u256.fromBytesBE(padded);
            this._traitImageData.set(slotKey, value);
        }

        // Store actual byte length (not chunk count) so reads can trim padding
        this._traitImageStatus.set(traitKey, u256.fromU64(data.length));
    }

    /**
     * Reads chunked data back from storage.
     * Status map stores actual byte length; chunks are derived from it.
     * Returns an array of exactly the original data length (no padding).
     */
    private _readChunkedData(traitKey: u256): Uint8Array {
        const storedLen: u256 = this._traitImageStatus.get(traitKey);
        if (storedLen.isZero()) {
            return new Uint8Array(0);
        }

        const dataLen: u32 = storedLen.toU64() as u32;
        const chunks: u32 = (dataLen + BYTES_PER_SLOT - 1) / BYTES_PER_SLOT;
        const baseKey: u256 = SafeMath.mul(traitKey, CHUNK_KEY_MULTIPLIER);
        const result: Uint8Array = new Uint8Array(dataLen);

        for (let i: u32 = 0; i < chunks; i++) {
            const slotKey: u256 = SafeMath.add(baseKey, u256.fromU64(i));
            const value: u256 = this._traitImageData.get(slotKey);
            const bytes: u8[] = value.toBytes(true);
            const bytesLen: u32 = bytes.length as u32;

            const offset: u32 = i * BYTES_PER_SLOT;
            const remaining: u32 = dataLen - offset;
            const copyLen: u32 = remaining < BYTES_PER_SLOT ? remaining : BYTES_PER_SLOT;

            for (let j: u32 = 0; j < copyLen; j++) {
                result[offset + j] = j < bytesLen ? bytes[j] : 0;
            }
        }

        return result;
    }

    /**
     * Reconstruct the global palette from color batches inscribed during mints.
     * Color batch traitKeys: 0xFF0000 + batchIndex. Batches may be 4 or 5 colors (12 or 15 bytes).
     */
    private _readPaletteFromBatches(): Uint8Array {
        const FIRST_COLOR_KEY: u64 = 16711680; // 0xFF << 16
        const MAX_BATCHES: u32 = 56; // 55 expected, +1 sentinel

        // First pass: count batches and total bytes
        let batchCount: u32 = 0;
        let totalBytes: u32 = 0;
        const batchLengths: u32[] = new Array<u32>(MAX_BATCHES);
        for (let i: u32 = 0; i < MAX_BATCHES; i++) {
            const key: u256 = u256.fromU64(FIRST_COLOR_KEY + i);
            const status: u256 = this._traitImageStatus.get(key);
            if (status.isZero()) break;
            const raw: Uint8Array = this._readChunkedData(key);
            batchLengths[i] = raw.length as u32;
            totalBytes += raw.length as u32;
            batchCount++;
        }

        if (batchCount == 0) return new Uint8Array(0);

        // Second pass: copy into palette
        const palette: Uint8Array = new Uint8Array(totalBytes);
        let offset: u32 = 0;
        for (let i: u32 = 0; i < batchCount; i++) {
            const key: u256 = u256.fromU64(FIRST_COLOR_KEY + i);
            const raw: Uint8Array = this._readChunkedData(key);
            const rawLen: u32 = raw.length as u32;
            for (let j: u32 = 0; j < rawLen; j++) {
                palette[offset + j] = raw[j];
            }
            offset += rawLen;
        }

        return palette;
    }

    // -----------------------------------------------------------------------
    // Internal: Merkle Proof Verification
    // -----------------------------------------------------------------------

    /**
     * Compute Merkle leaf hash: sha256(traitKey || data).
     * This binds the traitKey to the data so the same blob can't
     * be used for a different trait slot.
     */
    private _computeLeafHash(traitKey: u256, data: Uint8Array): Uint8Array {
        const leafWriter: BytesWriter = new BytesWriter(32 + data.length);
        leafWriter.writeU256(traitKey);
        leafWriter.writeBytes(data);
        return sha256(leafWriter.getBuffer());
    }

    private _verifyMerkleProof(
        proof: u256[],
        leafHash: Uint8Array,
        leafIndex: u32,
        root: u256,
    ): bool {
        if (leafIndex >= (TOTAL_TRAIT_LAYERS as u32)) {
            throw new Revert(ERR_FORGE_INVALID_LEAF_INDEX);
        }

        let currentHash: Uint8Array = leafHash;
        let idx: u32 = leafIndex;

        for (let i: i32 = 0; i < proof.length; i++) {
            const sibling: u256 = proof[i];
            const siblingBytes: u8[] = sibling.toBytes(true);

            const pairWriter: BytesWriter = new BytesWriter(64);
            if ((idx & 1) == 0) {
                // Current is left child
                pairWriter.writeBytes(currentHash);
                for (let j: i32 = 0; j < 32; j++) {
                    pairWriter.writeU8(siblingBytes[j]);
                }
            } else {
                // Current is right child
                for (let j: i32 = 0; j < 32; j++) {
                    pairWriter.writeU8(siblingBytes[j]);
                }
                pairWriter.writeBytes(currentHash);
            }

            currentHash = sha256(pairWriter.getBuffer());
            idx = idx >> 1;
        }

        // Compare computed root with stored root
        const computedArr: u8[] = this._uint8ToU8Array(currentHash);
        const computedRoot: u256 = u256.fromBytesBE(computedArr);
        return u256.eq(computedRoot, root);
    }

    // -----------------------------------------------------------------------
    // Internal: BTC Payment Verification
    // -----------------------------------------------------------------------

    /**
     * Cross-contract reads mintPrice from the NFT contract, then verifies
     * that Blockchain.tx.outputs includes a payment to the treasury of at
     * least mintPrice satoshis.
     *
     * Why this is tricky:
     *   - With hasTo flag: output.to = bech32 string, output.scriptPublicKey = null
     *   - Address.toString() returns hex (e.g. "0e607c..."), NOT bech32
     *   - So direct string comparison (hex vs bech32) never matches
     *
     * Solution: store sha256(treasury_bech32_string) via setTreasuryScriptHash.
     * Then compare sha256(output.to) against that stored hash.
     */
    private _verifyMintPayment(nft: Address): void {
        // Read mint price from NFT contract
        const priceWriter: BytesWriter = new BytesWriter(4);
        priceWriter.writeSelector(encodeSelector('getMintPrice()'));
        const priceResult: CallResult = Blockchain.call(nft, priceWriter, true);
        const mintPrice: u64 = priceResult.data.readU256().toU64();

        // Treasury address must be configured
        const treasury: Address = this._treasury.value;
        if (treasury.equals(Address.zero())) {
            throw new Revert(ERR_FORGE_PAYMENT_REQUIRED);
        }

        // sha256(treasury_bech32_string) — set via setTreasuryScriptHash
        const addrHash: u256 = this._treasuryScriptHash.value;
        if (addrHash.isZero()) {
            throw new Revert(ERR_FORGE_PAYMENT_REQUIRED);
        }

        // Scan tx outputs for a payment to the treasury >= mintPrice.
        const outputs = Blockchain.tx.outputs;
        for (let i: i32 = 0; i < outputs.length; i++) {
            const output = outputs[i];
            if (output.value < mintPrice) continue;

            // Strategy 1: Hash-match output.to (bech32 string) against stored hash.
            // With hasTo flag, output.to is the bech32 address string.
            // We compute sha256(output.to as UTF8 bytes) and compare.
            if (output.to !== null) {
                const toBytes: ArrayBuffer = String.UTF8.encode(output.to!);
                const toHash: Uint8Array = sha256(Uint8Array.wrap(toBytes));
                const toArr: u8[] = this._uint8ToU8Array(toHash);
                const toU256: u256 = u256.fromBytesBE(toArr);
                if (u256.eq(toU256, addrHash)) return;
            }

            // Strategy 2: Hash-match scriptPublicKey against stored hash.
            // For real transactions where hasScriptPubKey is set instead.
            const script: Uint8Array | null = output.scriptPublicKey;
            if (script !== null) {
                const scriptHashVal: Uint8Array = sha256(script);
                const scriptArr: u8[] = this._uint8ToU8Array(scriptHashVal);
                const scriptU256: u256 = u256.fromBytesBE(scriptArr);
                if (u256.eq(scriptU256, addrHash)) return;
            }
        }

        throw new Revert(ERR_FORGE_PAYMENT_REQUIRED);
    }

    // -----------------------------------------------------------------------
    // Internal: SVG Rendering
    // -----------------------------------------------------------------------

    /**
     * Renders a 120x120 pixel SVG by compositing 3 compressed trait layers.
     * Returns raw UTF-8 bytes in a Uint8Array — ZERO string allocations in
     * the hot pixel loop.
     *
     * Uses path-based rendering: horizontal RLE scans collect runs, then all
     * runs of the same color are grouped into a single <path d="MX YhW..."/>
     * element. This achieves ~84% size reduction vs one <rect> per run.
     *
     * Each trait blob is stored in compressed format:
     *   [layerType:u8][classIdx:u8][layerIdx:u8]  — 3-byte identity (skipped)
     *   [minX:u8][minY:u8][width:u8][height:u8]   — bounding box
     *   [localPaletteSize:u8]                      — N (1-15)
     *   [globalIdx × N]                            — local-to-global palette map
     *   [4-bit nibble pixel data]                  — 2 pixels/byte, hi nibble first
     *
     * Canvas stores global palette index + 1 (0 = transparent).
     */
    private _renderSVGToBuffer(
        palette: Uint8Array,
        bodyData: Uint8Array,
        faceData: Uint8Array,
        itemData: Uint8Array,
        subitemData: Uint8Array,
        classIdx: u64,
        bodyIdx: u64,
        faceIdx: u64,
        itemIdx: u64,
    ): Uint8Array {
        const side: i32 = CANVAS_SIDE as i32;
        const totalPixels: i32 = side * side;

        // Composite canvas: face → body → item → subitem (face under clothes, subitem on top)
        const canvas: Uint8Array = new Uint8Array(totalPixels);
        this._compositeLayer(canvas, faceData, side);
        this._compositeLayer(canvas, bodyData, side);
        this._compositeLayer(canvas, itemData, side);
        if (subitemData.length > 0) {
            this._compositeLayer(canvas, subitemData, side);
        }

        // Pre-allocate SVG output buffer.
        // Path-based worst case is ~17KB raw SVG. 256KB provides 15x headroom.
        const buf: Uint8Array = new Uint8Array(262144);
        let off: i32 = 0;

        // Get gradient colors as RGB components
        const hash: u64 = this._getTraitHash(bodyIdx, faceIdx, itemIdx);
        const topR: u8 = this._clampColor(0xF7 + ((((hash >> 0) & 0xF) as i32) - 8)) as u8;
        const topG: u8 = this._clampColor(0x93 + ((((hash >> 4) & 0xF) as i32) - 8)) as u8;
        const topB: u8 = this._clampColor(0x1A + ((((hash >> 8) & 0xF) as i32) - 8)) as u8;
        const botR: u8 = this._clampColor(0x3D + ((((hash >> 0) & 0xF) as i32) - 8)) as u8;
        const botG: u8 = this._clampColor(0x24 + ((((hash >> 4) & 0xF) as i32) - 8)) as u8;
        const botB: u8 = this._clampColor(0x07 + ((((hash >> 8) & 0xF) as i32) - 8)) as u8;

        // SVG header part 1 (before top color)
        const hdr1: string = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" shape-rendering="crispEdges">'
            + '<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
            + '<stop offset="0" stop-color="#';
        const hdr1Bytes: Uint8Array = Uint8Array.wrap(String.UTF8.encode(hdr1));
        for (let i: i32 = 0; i < hdr1Bytes.length; i++) {
            buf[off++] = hdr1Bytes[i];
        }

        // Top color (6 hex chars)
        off = this._writeRGBHex(buf, off, topR, topG, topB);

        // Header part 2 (between colors)
        const hdr2: string = '"/><stop offset="1" stop-color="#';
        const hdr2Bytes: Uint8Array = Uint8Array.wrap(String.UTF8.encode(hdr2));
        for (let i: i32 = 0; i < hdr2Bytes.length; i++) {
            buf[off++] = hdr2Bytes[i];
        }

        // Bottom color (6 hex chars)
        off = this._writeRGBHex(buf, off, botR, botG, botB);

        // Header part 3 (close gradient + bg rect)
        const hdr3: string = '"/></linearGradient></defs><rect width="120" height="120" fill="url(#bg)"/>';
        const hdr3Bytes: Uint8Array = Uint8Array.wrap(String.UTF8.encode(hdr3));
        for (let i: i32 = 0; i < hdr3Bytes.length; i++) {
            buf[off++] = hdr3Bytes[i];
        }

        // --- Pass 1: collect horizontal runs ---
        const MAX_RUNS: i32 = 8192;
        const runBuf: Uint8Array = new Uint8Array(MAX_RUNS * 4); // (colorIdx, x, y, w)
        const usedColors: Uint8Array = new Uint8Array(256);
        let numRuns: i32 = 0;

        for (let y: i32 = 0; y < side; y++) {
            const rowBase: i32 = y * side;
            let x: i32 = 0;
            for (; x < side;) {
                const c: u8 = canvas[rowBase + x];
                if (c == 0) {
                    x++;
                    continue;
                }

                // Scan run of same color
                let w: i32 = 1;
                for (let rx: i32 = x + 1; rx < side; rx++) {
                    if (canvas[rowBase + rx] != c) break;
                    w++;
                }

                if (numRuns < MAX_RUNS) {
                    const ri: i32 = numRuns * 4;
                    runBuf[ri] = c;
                    runBuf[ri + 1] = x as u8;
                    runBuf[ri + 2] = y as u8;
                    runBuf[ri + 3] = w as u8;
                    numRuns++;
                }
                usedColors[c] = 1;

                x += w;
            }
        }

        // --- Pass 2: emit one <path> per used color ---
        for (let c: i32 = 1; c < 256; c++) {
            if (usedColors[c] == 0) continue;

            const colorOffset: i32 = (c - 1) * 3;
            if (colorOffset + 2 >= palette.length) continue;

            const r: u8 = palette[colorOffset];
            const g: u8 = palette[colorOffset + 1];
            const b: u8 = palette[colorOffset + 2];

            // Write: <path d="
            off = this._copyStatic(buf, off, PATH_OPEN);

            // Write all runs of this color as MX YhWv1h-Wz closed rects
            for (let i: i32 = 0; i < numRuns; i++) {
                const ri: i32 = i * 4;
                if ((runBuf[ri] as i32) != c) continue;

                const runW: i32 = runBuf[ri + 3] as i32;

                buf[off++] = 77;  // 'M'
                off = this._writeInt(buf, off, runBuf[ri + 1] as i32); // x
                buf[off++] = 32;  // ' '
                off = this._writeInt(buf, off, runBuf[ri + 2] as i32); // y
                buf[off++] = 104; // 'h'
                off = this._writeInt(buf, off, runW);                  // w
                buf[off++] = 118; // 'v'
                buf[off++] = 49;  // '1'
                buf[off++] = 104; // 'h'
                buf[off++] = 45;  // '-'
                off = this._writeInt(buf, off, runW);                  // w
                buf[off++] = 122; // 'z'
            }

            // Write: " fill="#RRGGBB"/>
            off = this._copyStatic(buf, off, PATH_FILL);
            off = this._writeRGBHex(buf, off, r, g, b);
            off = this._copyStatic(buf, off, PATH_CLOSE);
        }

        // Close SVG
        off = this._copyStatic(buf, off, SVG_CLOSE);

        // Return trimmed buffer
        return buf.subarray(0, off);
    }

    /**
     * Decompress a compressed trait blob and composite onto the canvas.
     *
     * Blob format:
     *   Bytes 0-2:  identity (layerType, classIdx, layerIdx) — skipped
     *   Byte  3:    minX
     *   Byte  4:    minY
     *   Byte  5:    width
     *   Byte  6:    height
     *   Byte  7:    localPaletteSize (N, 1-15)
     *   Bytes 8..8+N-1: local palette (global palette indices)
     *   Bytes 8+N..: 4-bit nibble pixel data (hi nibble = first pixel, lo = second)
     *                0 = transparent, 1-15 = local palette index
     *
     * Canvas value convention: 0 = transparent, K = globalPaletteIdx + 1
     * So for nibble value V (1-15): canvas pixel = localPalette[V-1] + 1
     */
    private _compositeLayer(canvas: Uint8Array, layerData: Uint8Array, canvasSide: i32): void {
        // Minimum blob size: 8 (header) + 1 (palette) + 1 (pixel byte) = 10
        if (layerData.length < 10) return;

        // Parse header (skip 3 identity bytes)
        const minX: i32 = layerData[3] as i32;
        const minY: i32 = layerData[4] as i32;
        const bboxW: i32 = layerData[5] as i32;
        const bboxH: i32 = layerData[6] as i32;
        const localPaletteSize: i32 = layerData[7] as i32;

        if (localPaletteSize == 0 || bboxW == 0 || bboxH == 0) return;

        // Read local palette (maps local index 0..N-1 → global palette index)
        const paletteStart: i32 = 8;
        const pixelDataStart: i32 = paletteStart + localPaletteSize;
        if (pixelDataStart >= layerData.length) return;

        // Decode 4-bit nibble pixel data within bounding box
        const totalBBoxPixels: i32 = bboxW * bboxH;
        let byteIdx: i32 = pixelDataStart;

        for (let p: i32 = 0; p < totalBBoxPixels; p++) {
            // Two pixels per byte: hi nibble first, lo nibble second
            const nibbleByteOffset: i32 = byteIdx + (p >> 1);
            if (nibbleByteOffset >= layerData.length) break;

            const rawByte: u8 = layerData[nibbleByteOffset];
            const nibble: u8 = ((p & 1) == 0)
                ? ((rawByte >> 4) & 0x0F) as u8
                : (rawByte & 0x0F) as u8;

            if (nibble == 0) continue; // transparent

            // Map local nibble (1-based) to global palette index
            const localIdx: i32 = (nibble as i32) - 1;
            if (localIdx >= localPaletteSize) continue;

            const globalIdx: u8 = layerData[paletteStart + localIdx];
            // Canvas stores globalIdx + 1 (0 = transparent)
            const canvasValue: u8 = (globalIdx + 1) as u8;

            // Compute absolute canvas position
            const dx: i32 = p % bboxW;
            const dy: i32 = p / bboxW;
            const absX: i32 = minX + dx;
            const absY: i32 = minY + dy;

            if (absX >= canvasSide || absY >= canvasSide) continue;

            const canvasIdx: i32 = absY * canvasSide + absX;
            canvas[canvasIdx] = canvasValue;
        }
    }

    // -----------------------------------------------------------------------
    // Internal: PNG Rendering
    // -----------------------------------------------------------------------

    /**
     * Composites trait layers onto a 120×120 canvas, crops a 64×64 window
     * at native 1:1 pixel resolution, quantizes to ≤16 colors, and encodes
     * as a 4-bit indexed PNG.
     *
     * Crop offset is per-class (from CROP_OFFSETS). Transparent pixels are
     * filled with the class background color (bgCanvasValue).
     *
     * The 4-bit encoding + 16-color quantization ensures the resulting
     * data URI fits within OPNet's 2,048-byte receipt limit.
     */
    private _renderPNG(
        classIdx: u64,
        palette: Uint8Array,
        bodyData: Uint8Array,
        faceData: Uint8Array,
        itemData: Uint8Array,
        subitemData: Uint8Array,
        bgCanvasValue: u8,
    ): Uint8Array {
        const srcSide: i32 = CANVAS_SIDE as i32; // 120
        const cropSide: i32 = CROP_SIDE as i32;  // 64

        // Composite at full 120×120 resolution
        const srcCanvas: Uint8Array = new Uint8Array(srcSide * srcSide);
        this._compositeLayer(srcCanvas, faceData, srcSide);
        this._compositeLayer(srcCanvas, bodyData, srcSide);
        this._compositeLayer(srcCanvas, itemData, srcSide);
        if (subitemData.length > 0) {
            this._compositeLayer(srcCanvas, subitemData, srcSide);
        }

        // Per-class crop offset
        const offIdx: i32 = (classIdx as i32) * 2;
        const cropX: i32 = unchecked(CROP_OFFSETS[offIdx]) as i32;
        const cropY: i32 = unchecked(CROP_OFFSETS[offIdx + 1]) as i32;

        // Crop 64×64 from 120×120 with background fill
        const dstCanvas: Uint8Array = new Uint8Array(cropSide * cropSide);
        for (let dy: i32 = 0; dy < cropSide; dy++) {
            const sy: i32 = cropY + dy;
            for (let dx: i32 = 0; dx < cropSide; dx++) {
                const sx: i32 = cropX + dx;
                const v: u8 = srcCanvas[sy * srcSide + sx];
                dstCanvas[dy * cropSide + dx] = v == 0 ? bgCanvasValue : v;
            }
        }

        // Quantize to ≤16 colors for 4-bit encoding
        const totalPixels: i32 = cropSide * cropSide;
        quantizeColors(dstCanvas, palette, totalPixels, 16);

        return encodePNG4bit(dstCanvas, palette, cropSide, cropSide);
    }

    /**
     * Base64 encoder (byte-level, zero string intermediaries).
     */
    private _base64Encode(data: Uint8Array): string {
        const len: i32 = data.length;
        const outLen: i32 = ((len + 2) / 3) * 4;
        const out: Uint8Array = new Uint8Array(outLen);
        let j: i32 = 0;

        for (let i: i32 = 0; i < len; i += 3) {
            const b0: u32 = data[i] as u32;
            const b1: u32 = (i + 1 < len) ? (data[i + 1] as u32) : 0;
            const b2: u32 = (i + 2 < len) ? (data[i + 2] as u32) : 0;

            const triple: u32 = (b0 << 16) | (b1 << 8) | b2;

            out[j++] = unchecked(B64_TABLE[((triple >> 18) & 0x3F) as i32]);
            out[j++] = unchecked(B64_TABLE[((triple >> 12) & 0x3F) as i32]);
            out[j++] = (i + 1 < len)
                ? unchecked(B64_TABLE[((triple >> 6) & 0x3F) as i32])
                : 61; // '='
            out[j++] = (i + 2 < len)
                ? unchecked(B64_TABLE[(triple & 0x3F) as i32])
                : 61; // '='
        }

        return String.UTF8.decode(out.buffer);
    }

    // -----------------------------------------------------------------------
    // Internal: Buffer Helpers (zero string allocations)
    // -----------------------------------------------------------------------

    /**
     * Copy StaticArray<u8> bytes into buffer. Returns new offset.
     */
    private _copyStatic(buf: Uint8Array, off: i32, src: StaticArray<u8>): i32 {
        const len: i32 = src.length;
        for (let i: i32 = 0; i < len; i++) {
            buf[off + i] = unchecked(src[i]);
        }
        return off + len;
    }

    /**
     * Write integer 0-999 as ASCII digits (no string allocation). Returns new offset.
     */
    private _writeInt(buf: Uint8Array, off: i32, val: i32): i32 {
        if (val >= 100) {
            buf[off++] = (48 + (val / 100)) as u8;
            buf[off++] = (48 + ((val / 10) % 10)) as u8;
            buf[off++] = (48 + (val % 10)) as u8;
        } else if (val >= 10) {
            buf[off++] = (48 + (val / 10)) as u8;
            buf[off++] = (48 + (val % 10)) as u8;
        } else {
            buf[off++] = (48 + val) as u8;
        }
        return off;
    }

    /**
     * Write byte as 2 hex ASCII chars via HEX_LUT. Returns new offset.
     */
    private _writeHexByte(buf: Uint8Array, off: i32, b: u8): i32 {
        buf[off] = unchecked(HEX_LUT[(b >> 4) & 0x0F]);
        buf[off + 1] = unchecked(HEX_LUT[b & 0x0F]);
        return off + 2;
    }

    /**
     * Write 6 hex chars for RGB color. Returns new offset.
     */
    private _writeRGBHex(buf: Uint8Array, off: i32, r: u8, g: u8, b: u8): i32 {
        off = this._writeHexByte(buf, off, r);
        off = this._writeHexByte(buf, off, g);
        off = this._writeHexByte(buf, off, b);
        return off;
    }

    // -----------------------------------------------------------------------
    // Internal: Helpers
    // -----------------------------------------------------------------------

    /**
     * Deterministic 16-bit hash from trait indices.
     * Gives every unique trait combination a unique gradient shift.
     */
    private _getTraitHash(bodyIdx: u64, faceIdx: u64, itemIdx: u64): u64 {
        const seed: u64 = bodyIdx * 7919 + faceIdx * 6271 + itemIdx * 4813;
        return seed & 0xFFFF;
    }

    private _clampColor(v: i32): i32 {
        if (v < 0) return 0;
        if (v > 255) return 255;
        return v;
    }

    private _classIdxToName(classIdx: u64): string {
        if (classIdx == 0) return 'Wizard';
        if (classIdx == 1) return 'King';
        if (classIdx == 2) return 'Knight';
        if (classIdx == 3) return 'Apprentice';
        if (classIdx == 4) return 'Peasant';
        if (classIdx == 5) return 'Gnome';
        if (classIdx == 6) return 'Elf';
        return 'Unknown';
    }

    private _onlyArtAuthority(): void {
        if (this._artAuthority.isDead()) {
            throw new Revert(ERR_FORGE_NOT_ART_AUTH);
        }
        const authority: Address = this._artAuthority.value;
        if (!authority.equals(Blockchain.tx.sender)) {
            throw new Revert(ERR_FORGE_NOT_ART_AUTH);
        }
    }

    private _uint8ToU8Array(data: Uint8Array): u8[] {
        const arr = new Array<u8>(data.length);
        for (let i: i32 = 0; i < data.length; i++) {
            arr[i] = data[i];
        }
        return arr;
    }

    // -----------------------------------------------------------------------
    // Internal: Reentrancy Guard
    // -----------------------------------------------------------------------

    private _nonReentrant(): void {
        const guard: u256 = this._reentrancyGuard.value;
        if (u256.eq(guard, REENTRANCY_LOCKED)) {
            throw new Revert(ERR_FORGE_REENTRANT);
        }
        this._reentrancyGuard.value = REENTRANCY_LOCKED;
    }

    private _releaseReentrancy(): void {
        this._reentrancyGuard.value = REENTRANCY_UNLOCKED;
    }
}
