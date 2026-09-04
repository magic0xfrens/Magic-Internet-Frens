import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    encodeSelector,
    OP721,
    OP721InitParameters,
    Revert,
    SafeMath,
    StoredU256,
    StoredAddress,
    AddressMemoryMap,
    StoredMapU256,
} from '@btc-vision/btc-runtime/runtime';

import { CallResult } from '@btc-vision/btc-runtime/runtime/env/BlockchainEnvironment';
import { sha256 } from '@btc-vision/btc-runtime/runtime/env/global';

import {
    MAX_NFT_SUPPLY,
    MAX_BATCH_SIZE,
    MAX_MINTS_PER_ADDRESS,
    MAX_NFT_CLASSES,
    TREASURY_RESERVE,
    RESERVE_TRAITS,
    RESERVED_IDS,
    CLASS_WEIGHT_WIZARD,
    CLASS_WEIGHT_KING,
    CLASS_WEIGHT_KNIGHT,
    CLASS_WEIGHT_APPRENTICE,
    CLASS_WEIGHT_PEASANT,
    CLASS_WEIGHT_GNOME,
    CAULDRON_TAX_RATE_BPS,
} from '../lib/constants';
import {
    ERR_NFT_MAX_SUPPLY,
    ERR_NFT_NOT_EXIST,
    ERR_NFT_LOCKED,
    ERR_NFT_NOT_LOCKED,
    ERR_NFT_NOT_CAULDRON,
    ERR_NFT_ZERO_ADDR,
    ERR_NFT_BATCH_TOO_LARGE,
    ERR_NFT_MINT_CAP,
    ERR_NFT_INVALID_CLASS,
    ERR_NFT_INVALID_TRAIT_IDX,
    ERR_NFT_MAX_CLASSES,
    ERR_NFT_CLASS_IDX_MISMATCH,
    ERR_NFT_INVALID_CLASS_DEF,
    ERR_NFT_FORGE_CALL_FAILED,
    ERR_NFT_COMBO_TAKEN,
    ERR_NFT_COMBO_EXHAUSTED,
    ERR_NFT_NOT_AUTHORIZED,
} from '../lib/errors';
import {
    NFTMintedEvent,
    NFTLockedEvent,
    NFTUnlockedEvent,
    CauldronSummonReadyEvent,
    TraitsUpdatedEvent,
} from '../events/NFTEvents';

// Max borrow per class (in u256, MIF 18 decimals)
const MAX_BORROW_WIZARD: u256 = u256.fromString('10000000000000000000');  // 10 BTC equiv
const MAX_BORROW_KING: u256 = u256.fromString('2000000000000000000');     // 2 BTC equiv
const MAX_BORROW_KNIGHT: u256 = u256.fromString('500000000000000000');    // 0.5 BTC equiv
const MAX_BORROW_APPRENTICE: u256 = u256.fromString('500000000000000000'); // 0.5 BTC equiv
const MAX_BORROW_PEASANT: u256 = u256.fromString('100000000000000000');   // 0.1 BTC equiv
const MAX_BORROW_GNOME: u256 = u256.fromString('500000000000000000');     // 0.5 BTC equiv
const MAX_BORROW_ELF: u256 = u256.fromString('500000000000000000');       // 0.5 BTC equiv

// Liquidation grace blocks per class
const GRACE_WIZARD: u256 = u256.fromU64(3);
const GRACE_KING: u256 = u256.fromU64(2);
const GRACE_KNIGHT: u256 = u256.One;
const GRACE_APPRENTICE: u256 = u256.One;
const GRACE_PEASANT: u256 = u256.Zero;
const GRACE_GNOME: u256 = u256.Zero;
const GRACE_ELF: u256 = u256.Zero;

/**
 * MiFrens -- MiFrens NFT (OP_721) for the Magic Internet Frens Protocol.
 *
 * Core NFT contract: minting, transfers, trait indices, locks, cauldron integration.
 * On-chain trait inscription and SVG rendering live in the FrenForge contract.
 *
 * 7 Classes with weighted random assignment on mint:
 *   Wizard     (44%)  -- 0% tax, 3 grace blocks, 10 BTC borrow
 *   King       (22%)  -- 0.5% tax, 2 grace blocks, 2 BTC borrow
 *   Knight    (17.5%) -- 1% tax, 1 grace block, 0.5 BTC borrow
 *   Apprentice (3.3%) -- 1% tax, 1 grace block, 0.5 BTC borrow
 *   Peasant    (2.2%) -- 2% tax, 0 grace blocks, 0.1 BTC borrow
 *   Gnome      (6.6%) -- 0.5% tax, 0 grace blocks, 0.5 BTC borrow
 *   Elf        (4.4%) -- 0.5% tax, 0 grace blocks, 0.5 BTC borrow
 *
 * NFTs are locked (non-transferable) while a Cauldron position is open.
 */
@final
export class MiFrens extends OP721 {
    // -----------------------------------------------------------------------
    // Storage Pointers
    // -----------------------------------------------------------------------

    private readonly tierMapPointer: u16 = Blockchain.nextPointer;
    private readonly lockedMapPointer: u16 = Blockchain.nextPointer;
    private readonly cauldronWhitelistPointer: u16 = Blockchain.nextPointer;
    private readonly randomNoncePointer: u16 = Blockchain.nextPointer;
    private readonly cauldronRegistryPointer: u16 = Blockchain.nextPointer;
    private readonly cauldronSummonedPointer: u16 = Blockchain.nextPointer;
    private readonly treasuryPointer: u16 = Blockchain.nextPointer;
    private readonly mintPricePointer: u16 = Blockchain.nextPointer;
    private readonly traitDataPointer: u16 = Blockchain.nextPointer;
    private readonly classCountsPointer: u16 = Blockchain.nextPointer;
    private readonly classRegistryPointer: u16 = Blockchain.nextPointer;
    private readonly numRegisteredClassesPointer: u16 = Blockchain.nextPointer;
    private readonly classCountsHiPointer: u16 = Blockchain.nextPointer;
    private readonly forgePointer: u16 = Blockchain.nextPointer;
    private readonly usedCombosPointer: u16 = Blockchain.nextPointer;
    private readonly lastMintedClassPointer: u16 = Blockchain.nextPointer;
    private readonly nextReserveIndexPointer: u16 = Blockchain.nextPointer;

    // -----------------------------------------------------------------------
    // Storage Instances
    // -----------------------------------------------------------------------

    private _lockedTokens!: StoredMapU256;
    private _cauldronWhitelist!: AddressMemoryMap;
    private _randomNonce!: StoredU256;
    private _cauldronRegistry!: StoredAddress;
    private _cauldronSummoned!: StoredU256;
    private _treasury!: StoredAddress;
    private _mintPrice!: StoredU256;
    private _traitData!: StoredMapU256;
    private _classCounts!: AddressMemoryMap;
    private _classRegistry!: StoredMapU256;
    private _numRegisteredClasses!: StoredU256;
    private _classCountsHi!: AddressMemoryMap;
    private _forge!: StoredAddress;
    private _usedCombos!: StoredMapU256;
    private _lastMintedClass!: StoredU256;
    private _nextReserveIndex!: StoredU256;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    public constructor() {
        super();

        this._lockedTokens = new StoredMapU256(this.lockedMapPointer);
        this._cauldronWhitelist = new AddressMemoryMap(this.cauldronWhitelistPointer);
        this._randomNonce = new StoredU256(this.randomNoncePointer, new Uint8Array(0));
        this._cauldronRegistry = new StoredAddress(this.cauldronRegistryPointer);
        this._cauldronSummoned = new StoredU256(this.cauldronSummonedPointer, new Uint8Array(0));
        this._treasury = new StoredAddress(this.treasuryPointer);
        this._mintPrice = new StoredU256(this.mintPricePointer, new Uint8Array(0));
        this._traitData = new StoredMapU256(this.traitDataPointer);
        this._classCounts = new AddressMemoryMap(this.classCountsPointer);
        this._classRegistry = new StoredMapU256(this.classRegistryPointer);
        this._numRegisteredClasses = new StoredU256(this.numRegisteredClassesPointer, new Uint8Array(0));
        this._classCountsHi = new AddressMemoryMap(this.classCountsHiPointer);
        this._forge = new StoredAddress(this.forgePointer);
        this._usedCombos = new StoredMapU256(this.usedCombosPointer);
        this._lastMintedClass = new StoredU256(this.lastMintedClassPointer, new Uint8Array(0));
        this._nextReserveIndex = new StoredU256(this.nextReserveIndexPointer, new Uint8Array(0));
    }

    // -----------------------------------------------------------------------
    // Deployment
    // -----------------------------------------------------------------------

    public override onDeployment(calldata: Calldata): void {
        const treasury: Address = calldata.readAddress();
        const mintPrice: u256 = calldata.readU256();

        this._treasury.value = treasury;
        this._mintPrice.value = mintPrice;

        this.instantiate(new OP721InitParameters(
            'Magic Internet Frens',
            'MiFrens',
            'https://www.mifrens.xyz/nft/',
            MAX_NFT_SUPPLY,
            'https://www.mifrens.xyz/mifrens-banner.svg',  // banner
            'https://www.mifrens.xyz/mifrens-logo.svg',  // icon
            'https://www.mifrens.xyz',                    // website
            'Magic Internet Frens - 777 Unique Frens on Bitcoin L1', // description
        ));

        // Register the 7 original classes
        //                     classIdx  bodies  faces  items  enabled  mintable  taxBPS  mintTier
        this._classRegistry.set(u256.Zero,              this._packClassDef(8, 12, 5, 1, 1, 0,   3));     // Wizard   -> Archmage
        this._classRegistry.set(u256.One,               this._packClassDef(5, 12, 4, 1, 1, 50,  2));     // King     -> Noble
        this._classRegistry.set(u256.fromU64(2),        this._packClassDef(4, 12, 4, 1, 1, 100, 0xFF)); // Knight   -> Commoner
        this._classRegistry.set(u256.fromU64(3),        this._packClassDef(3, 12, 1, 1, 1, 100, 1));     // Apprentice -> Adept
        this._classRegistry.set(u256.fromU64(4),        this._packClassDef(2, 12, 3, 1, 1, 200, 0xFF)); // Peasant  -> Commoner
        this._classRegistry.set(u256.fromU64(5),        this._packClassDef(2, 12, 3, 1, 1, 50,  0xFF)); // Gnome    -> Commoner
        this._classRegistry.set(u256.fromU64(6),        this._packClassDef(3, 12, 1, 1, 1, 50,  0xFF)); // Elf      -> Commoner
        this._numRegisteredClasses.value = u256.fromU64(7);

        // Treasury reserve is now minted post-deployment via reserveBatch()
        // + setBatchTraits() to stay within the 10B gas limit.
        // See configure-contracts.ts for the batch minting steps.
    }

    // -----------------------------------------------------------------------
    // Transfer Override -- Check lock status before any transfer
    // -----------------------------------------------------------------------

    protected _transfer(from: Address, to: Address, tokenId: u256): void {
        const locked: u256 = this._lockedTokens.get(tokenId);
        if (u256.eq(locked, u256.One)) {
            throw new Revert(ERR_NFT_LOCKED);
        }

        const packed: u256 = this._traitData.get(tokenId);
        const classIdx: u64 = this._extractClassIdx(packed);
        this._decrementClassCount(from, classIdx);
        this._incrementClassCount(to, classIdx);

        super._transfer(from, to, tokenId);
    }

    // -----------------------------------------------------------------------
    // Mint
    // -----------------------------------------------------------------------

    @method()
    @returns({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    public mintNFT(_calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const sender: Address = Blockchain.tx.sender;

        if (u256.ge(this.totalSupply, MAX_NFT_SUPPLY)) {
            throw new Revert(ERR_NFT_MAX_SUPPLY);
        }

        if (u256.ge(this._balanceOf(sender), MAX_MINTS_PER_ADDRESS)) {
            throw new Revert(ERR_NFT_MINT_CAP);
        }

        // Payment verification is NOT needed here — mintNFT is deployer-only.
        // Public mints go through FrenForge.mint() which verifies payment via
        // treasuryScriptHash before calling nft.mintFor().

        const currentId: u256 = this._advancePublicId();
        const traits: u256 = this._assignRandomTraits();

        this._traitData.set(currentId, traits);
        this._lockedTokens.set(currentId, u256.Zero);

        const classIdx: u64 = this._extractClassIdx(traits);
        this._incrementClassCount(sender, classIdx);

        this._mint(sender, currentId);

        this.emitEvent(new NFTMintedEvent(sender, currentId));

        if (u256.eq(this.totalSupply, MAX_NFT_SUPPLY)) {
            this._summonCauldron();
        }

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(currentId);
        return writer;
    }

    // -----------------------------------------------------------------------
    // NFT Query Methods
    // -----------------------------------------------------------------------

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'taxRate', type: ABIDataTypes.UINT256 })
    public getTaxRate(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);
        const packed: u256 = this._traitData.get(tokenId);
        const classIdx: u64 = this._extractClassIdx(packed);
        const def: u256 = this._classRegistry.get(u256.fromU64(classIdx));
        const taxRate: u256 = u256.fromU64(this._classTaxBPS(def));
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(taxRate);
        return writer;
    }

    /**
     * Returns the best (lowest) tax rate in BPS for a holder address
     * based on the classes of NFTs they hold.
     */
    @method({ name: 'holder', type: ABIDataTypes.ADDRESS })
    @returns(
        { name: 'taxRate', type: ABIDataTypes.UINT256 },
        { name: 'bestClassIdx', type: ABIDataTypes.UINT256 },
    )
    public getHolderTaxRate(calldata: Calldata): BytesWriter {
        const holder: Address = calldata.readAddress();
        const packedLo: u256 = this._classCounts.get(holder);
        const packedHi: u256 = this._classCountsHi.get(holder);
        const numClasses: u64 = this._numRegisteredClasses.value.toU64();

        let bestTax: u64 = CAULDRON_TAX_RATE_BPS.toU64(); // default non-holder rate
        let bestClass: u64 = u64.MAX_VALUE; // sentinel = no fren owned

        for (let i: u64 = 0; i < numClasses; i++) {
            const count: u64 = this._getClassCountFromPacked(i, packedLo, packedHi);
            if (count == 0) continue;

            const def: u256 = this._classRegistry.get(u256.fromU64(i));
            const taxBPS: u64 = this._classTaxBPS(def);

            if (taxBPS == 0) {
                // Can't do better than 0 — early exit
                bestTax = 0;
                bestClass = i;
                break;
            }
            if (taxBPS < bestTax) {
                bestTax = taxBPS;
                bestClass = i;
            }
        }

        const writer: BytesWriter = new BytesWriter(64);
        writer.writeU256(u256.fromU64(bestTax));
        writer.writeU256(u256.fromU64(bestClass));
        return writer;
    }

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'maxBorrow', type: ABIDataTypes.UINT256 })
    public getMaxBorrow(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);
        const packed: u256 = this._traitData.get(tokenId);
        const classIdx: u64 = this._extractClassIdx(packed);
        const maxBorrow: u256 = this._classToMaxBorrow(classIdx);
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(maxBorrow);
        return writer;
    }

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'grace', type: ABIDataTypes.UINT256 })
    public getLiquidationGrace(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);
        const packed: u256 = this._traitData.get(tokenId);
        const classIdx: u64 = this._extractClassIdx(packed);
        const grace: u256 = this._classToGrace(classIdx);
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(grace);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Lock / Unlock (Cauldron integration)
    // -----------------------------------------------------------------------

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public lockNFT(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        this._onlyCauldron(sender);

        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);

        const locked: u256 = this._lockedTokens.get(tokenId);
        if (u256.eq(locked, u256.One)) {
            throw new Revert(ERR_NFT_LOCKED);
        }

        this._lockedTokens.set(tokenId, u256.One);
        this.emitEvent(new NFTLockedEvent(tokenId, sender));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public unlockNFT(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        this._onlyCauldron(sender);

        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);

        const locked: u256 = this._lockedTokens.get(tokenId);
        if (!u256.eq(locked, u256.One)) {
            throw new Revert(ERR_NFT_NOT_LOCKED);
        }

        this._lockedTokens.set(tokenId, u256.Zero);
        this.emitEvent(new NFTUnlockedEvent(tokenId, sender));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'locked', type: ABIDataTypes.BOOL })
    public isLocked(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);
        const locked: u256 = this._lockedTokens.get(tokenId);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(u256.eq(locked, u256.One));
        return writer;
    }

    // -----------------------------------------------------------------------
    // Admin Methods
    // -----------------------------------------------------------------------

    @method({ name: 'cauldron', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public addCauldron(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const cauldron: Address = calldata.readAddress();
        if (cauldron.equals(Address.zero())) {
            throw new Revert(ERR_NFT_ZERO_ADDR);
        }
        this._cauldronWhitelist.set(cauldron, u256.One);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'cauldron', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public removeCauldron(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const cauldron: Address = calldata.readAddress();
        this._cauldronWhitelist.set(cauldron, u256.Zero);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'account', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'isCauldron', type: ABIDataTypes.BOOL })
    public isCauldron(calldata: Calldata): BytesWriter {
        const account: Address = calldata.readAddress();
        const val: u256 = this._cauldronWhitelist.get(account);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(u256.eq(val, u256.One));
        return writer;
    }

    /**
     * mintFor(to) -- Gated mint callable only by whitelisted contracts (FrenForge).
     * Mints to the specified address. The caller (FrenForge) is responsible for
     * verifying the user provided valid trait data before calling this.
     */
    @method({ name: 'to', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    public mintFor(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        if (!sender.equals(this._forge.value)) {
            throw new Revert(ERR_NFT_NOT_AUTHORIZED);
        }

        const to: Address = calldata.readAddress();
        if (to.equals(Address.zero())) {
            throw new Revert(ERR_NFT_ZERO_ADDR);
        }

        if (u256.ge(this.totalSupply, MAX_NFT_SUPPLY)) {
            throw new Revert(ERR_NFT_MAX_SUPPLY);
        }

        if (u256.ge(this._balanceOf(to), MAX_MINTS_PER_ADDRESS)) {
            throw new Revert(ERR_NFT_MINT_CAP);
        }

        // Payment verification is handled by the calling contract (FrenForge).
        // FrenForge.mint() checks Blockchain.tx.outputs for treasury payment
        // before invoking this method.

        const currentId: u256 = this._advancePublicId();
        const traits: u256 = this._assignRandomTraits();

        this._traitData.set(currentId, traits);
        this._lockedTokens.set(currentId, u256.Zero);

        const classIdx: u64 = this._extractClassIdx(traits);
        this._incrementClassCount(to, classIdx);

        this._mint(to, currentId);

        this.emitEvent(new NFTMintedEvent(to, currentId));

        if (u256.eq(this.totalSupply, MAX_NFT_SUPPLY)) {
            this._summonCauldron();
        }

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(currentId);
        return writer;
    }

    /**
     * reserveBatch(to, count, packed0, packed1, ...) -- Deployer-only batch mint
     * at scattered reserved token IDs (from RESERVED_IDS constant).
     *
     * Skips payment verification and per-address mint cap.
     * Reads `count` packed u256 trait values from calldata (same format as setBatchTraits).
     * Can be called at any time — before, during, or after public minting.
     */
    @method(
        { name: 'to', type: ABIDataTypes.ADDRESS },
        { name: 'count', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'lastTokenId', type: ABIDataTypes.UINT256 })
    public reserveBatch(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const to: Address = calldata.readAddress();
        if (to.equals(Address.zero())) {
            throw new Revert(ERR_NFT_ZERO_ADDR);
        }

        const count: u256 = calldata.readU256();
        const countU64: u64 = count.toU64();
        if (countU64 == 0 || countU64 > MAX_BATCH_SIZE) {
            throw new Revert(ERR_NFT_BATCH_TOO_LARGE);
        }

        let reserveIdx: u64 = this._nextReserveIndex.value.toU64();
        let lastId: u256 = u256.Zero;

        for (let i: u64 = 0; i < countU64; i++) {
            if (reserveIdx + i >= TREASURY_RESERVE) {
                throw new Revert(ERR_NFT_MAX_SUPPLY);
            }

            const tokenId: u256 = u256.fromU64(RESERVED_IDS[(reserveIdx + i) as u32] as u64);
            const packed: u256 = calldata.readU256();

            // Dedup: claim the trait combo
            const combo: u256 = this._comboKey(packed);
            if (!u256.eq(this._usedCombos.get(combo), u256.Zero)) {
                throw new Revert(ERR_NFT_COMBO_TAKEN);
            }
            this._usedCombos.set(combo, u256.One);

            this._traitData.set(tokenId, packed);
            this._lockedTokens.set(tokenId, u256.Zero);

            const classIdx: u64 = this._extractClassIdx(packed);
            this._incrementClassCount(to, classIdx);

            this._mint(to, tokenId);

            this.emitEvent(new NFTMintedEvent(to, tokenId));

            lastId = tokenId;

            if (u256.eq(this.totalSupply, MAX_NFT_SUPPLY)) {
                this._summonCauldron();
            }
        }

        this._nextReserveIndex.value = u256.fromU64(reserveIdx + countU64);

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(lastId);
        return writer;
    }

    @method()
    @returns({ name: 'count', type: ABIDataTypes.UINT256 })
    public totalMinted(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this.totalSupply);
        return writer;
    }

    @method()
    @returns(
        { name: 'nextReserveIndex', type: ABIDataTypes.UINT256 },
        { name: 'totalReserved', type: ABIDataTypes.UINT256 },
    )
    public getReserveInfo(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(64);
        writer.writeU256(this._nextReserveIndex.value);
        writer.writeU256(u256.fromU64(TREASURY_RESERVE));
        return writer;
    }

    @method({ name: 'treasury', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setTreasury(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const treasury: Address = calldata.readAddress();
        if (treasury.equals(Address.zero())) {
            throw new Revert(ERR_NFT_ZERO_ADDR);
        }
        this._treasury.value = treasury;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'price', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setMintPrice(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const price: u256 = calldata.readU256();
        this._mintPrice.value = price;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'price', type: ABIDataTypes.UINT256 })
    public getMintPrice(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._mintPrice.value);
        return writer;
    }

    @method()
    @returns({ name: 'treasury', type: ABIDataTypes.ADDRESS })
    public getTreasury(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeAddress(this._treasury.value);
        return writer;
    }

    @method({ name: 'registry', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setCauldronRegistry(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const registry: Address = calldata.readAddress();
        this._cauldronRegistry.value = registry;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'forge', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setFrenForge(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const forge: Address = calldata.readAddress();
        if (forge.equals(Address.zero())) {
            throw new Revert(ERR_NFT_ZERO_ADDR);
        }
        this._forge.value = forge;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'forge', type: ABIDataTypes.ADDRESS })
    public getFrenForge(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeAddress(this._forge.value);
        return writer;
    }

    // -----------------------------------------------------------------------
    // OG Inscriber (stored in _traitData packed field)
    // -----------------------------------------------------------------------

    /**
     * markOGInscriber(tokenId) -- Called by FrenForge to flag a token as OG inscriber.
     * Sets the isOG bit in the token's packed trait data.
     */
    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public markOGInscriber(calldata: Calldata): BytesWriter {
        if (!Blockchain.tx.sender.equals(this._forge.value)) {
            throw new Revert(ERR_NFT_NOT_AUTHORIZED);
        }
        const tokenId: u256 = calldata.readU256();
        const packed: u256 = this._traitData.get(tokenId);
        const classIdx: u64 = this._extractClassIdx(packed);
        const subitemIdx: u64 = this._extractSubitemIdx(packed);
        const newLo1: u64 = this._packLo1(classIdx, subitemIdx, 1);
        this._traitData.set(tokenId, new u256(newLo1, packed.lo2, packed.hi1, packed.hi2));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * isOGInscriber(tokenId) -- View: reads isOG flag from packed trait data.
     */
    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'isOG', type: ABIDataTypes.BOOL })
    public isOGInscriber(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        const packed: u256 = this._traitData.get(tokenId);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(this._extractIsOG(packed));
        return writer;
    }

    // -----------------------------------------------------------------------
    // tokenURI -- Delegates to FrenForge if set, otherwise fallback to baseURI
    // -----------------------------------------------------------------------

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'uri', type: ABIDataTypes.STRING })
    public tokenURI(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);

        // If no FrenForge set, fallback to baseURI + tokenId (backward compatible)
        if (this._forge.isDead()) {
            const uri: string = this.baseURI + tokenId.toString();
            const w: BytesWriter = new BytesWriter(4 + String.UTF8.byteLength(uri));
            w.writeStringWithLength(uri);
            return w;
        }

        // Read traits locally to avoid re-entrant cross-contract call chain
        // (MiFrens → FrenForge → MiFrens would exceed call depth limit).
        const packed: u256 = this._traitData.get(tokenId);
        const classIdx: u256 = u256.fromU64(this._extractClassIdx(packed));
        const bodyIdx: u256 = u256.fromU64(packed.lo2);
        const faceIdx: u256 = u256.fromU64(packed.hi1);
        const itemIdx: u256 = u256.fromU64(packed.hi2);
        const subitemIdx: u256 = u256.fromU64(this._extractSubitemIdx(packed));

        // Call FrenForge.renderTokenURI(tokenId, classIdx, bodyIdx, faceIdx, itemIdx, subitemIdx)
        const forgeAddr: Address = this._forge.value;
        const cw: BytesWriter = new BytesWriter(196); // 4 selector + 6 * 32 params
        cw.writeSelector(encodeSelector('renderTokenURI(uint256,uint256,uint256,uint256,uint256,uint256)'));
        cw.writeU256(tokenId);
        cw.writeU256(classIdx);
        cw.writeU256(bodyIdx);
        cw.writeU256(faceIdx);
        cw.writeU256(itemIdx);
        cw.writeU256(subitemIdx);

        const result: CallResult = Blockchain.call(forgeAddr, cw, false);
        if (!result.success) {
            // Graceful fallback to baseURI + tokenId
            const fallback: string = this.baseURI + tokenId.toString();
            const fw: BytesWriter = new BytesWriter(4 + String.UTF8.byteLength(fallback));
            fw.writeStringWithLength(fallback);
            return fw;
        }

        const uri: string = result.data.readStringWithLength();
        const writer: BytesWriter = new BytesWriter(4 + String.UTF8.byteLength(uri));
        writer.writeStringWithLength(uri);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Class Registry Admin Methods
    // -----------------------------------------------------------------------

    @method(
        { name: 'classIdx', type: ABIDataTypes.UINT256 },
        { name: 'numBodies', type: ABIDataTypes.UINT256 },
        { name: 'numFaces', type: ABIDataTypes.UINT256 },
        { name: 'numItems', type: ABIDataTypes.UINT256 },
        { name: 'taxBPS', type: ABIDataTypes.UINT256 },
        { name: 'mintTier', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public registerClass(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const classIdx: u64 = calldata.readU256().toU64();
        const numBodies: u64 = calldata.readU256().toU64();
        const numFaces: u64 = calldata.readU256().toU64();
        const numItems: u64 = calldata.readU256().toU64();
        const taxBPS: u64 = calldata.readU256().toU64();
        const mintTier: u64 = calldata.readU256().toU64();

        const currentCount: u64 = this._numRegisteredClasses.value.toU64();
        if (classIdx != currentCount) {
            throw new Revert(ERR_NFT_CLASS_IDX_MISMATCH);
        }
        if (currentCount >= MAX_NFT_CLASSES) {
            throw new Revert(ERR_NFT_MAX_CLASSES);
        }
        if (numBodies == 0 || numFaces == 0 || numItems == 0) {
            throw new Revert(ERR_NFT_INVALID_CLASS_DEF);
        }

        const def: u256 = this._packClassDef(numBodies, numFaces, numItems, 1, 1, taxBPS, mintTier);
        this._classRegistry.set(u256.fromU64(classIdx), def);
        this._numRegisteredClasses.value = u256.fromU64(currentCount + 1);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method(
        { name: 'classIdx', type: ABIDataTypes.UINT256 },
        { name: 'numBodies', type: ABIDataTypes.UINT256 },
        { name: 'numFaces', type: ABIDataTypes.UINT256 },
        { name: 'numItems', type: ABIDataTypes.UINT256 },
        { name: 'taxBPS', type: ABIDataTypes.UINT256 },
        { name: 'mintTier', type: ABIDataTypes.UINT256 },
        { name: 'enabled', type: ABIDataTypes.UINT256 },
        { name: 'mintable', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public updateClass(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const classIdx: u64 = calldata.readU256().toU64();
        const numBodies: u64 = calldata.readU256().toU64();
        const numFaces: u64 = calldata.readU256().toU64();
        const numItems: u64 = calldata.readU256().toU64();
        const taxBPS: u64 = calldata.readU256().toU64();
        const mintTier: u64 = calldata.readU256().toU64();
        const enabled: u64 = calldata.readU256().toU64();
        const mintable: u64 = calldata.readU256().toU64();

        const currentCount: u64 = this._numRegisteredClasses.value.toU64();
        if (classIdx >= currentCount) {
            throw new Revert(ERR_NFT_INVALID_CLASS);
        }
        if (numBodies == 0 || numFaces == 0 || numItems == 0) {
            throw new Revert(ERR_NFT_INVALID_CLASS_DEF);
        }

        const def: u256 = this._packClassDef(numBodies, numFaces, numItems, enabled, mintable, taxBPS, mintTier);
        this._classRegistry.set(u256.fromU64(classIdx), def);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'classIdx', type: ABIDataTypes.UINT256 })
    @returns(
        { name: 'numBodies', type: ABIDataTypes.UINT256 },
        { name: 'numFaces', type: ABIDataTypes.UINT256 },
        { name: 'numItems', type: ABIDataTypes.UINT256 },
        { name: 'taxBPS', type: ABIDataTypes.UINT256 },
        { name: 'mintTier', type: ABIDataTypes.UINT256 },
        { name: 'enabled', type: ABIDataTypes.UINT256 },
        { name: 'mintable', type: ABIDataTypes.UINT256 },
    )
    public getClassDef(calldata: Calldata): BytesWriter {
        const classIdx: u64 = calldata.readU256().toU64();
        const currentCount: u64 = this._numRegisteredClasses.value.toU64();
        if (classIdx >= currentCount) {
            throw new Revert(ERR_NFT_INVALID_CLASS);
        }

        const def: u256 = this._classRegistry.get(u256.fromU64(classIdx));

        const writer: BytesWriter = new BytesWriter(224);
        writer.writeU256(u256.fromU64(this._classNumBodies(def)));
        writer.writeU256(u256.fromU64(this._classNumFaces(def)));
        writer.writeU256(u256.fromU64(this._classNumItems(def)));
        writer.writeU256(u256.fromU64(this._classTaxBPS(def)));
        writer.writeU256(u256.fromU64(this._classMintTier(def)));
        writer.writeU256(u256.fromU64(this._classEnabled(def)));
        writer.writeU256(u256.fromU64(this._classMintable(def)));
        return writer;
    }

    @method()
    @returns({ name: 'count', type: ABIDataTypes.UINT256 })
    public getNumClasses(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._numRegisteredClasses.value);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Transform Token (Cauldron-gated -- for SpellCaster contract)
    // -----------------------------------------------------------------------

    @method(
        { name: 'tokenId', type: ABIDataTypes.UINT256 },
        { name: 'newClassIdx', type: ABIDataTypes.UINT256 },
        { name: 'newBodyIdx', type: ABIDataTypes.UINT256 },
        { name: 'newFaceIdx', type: ABIDataTypes.UINT256 },
        { name: 'newItemIdx', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public transformToken(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        this._onlyCauldron(sender);

        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);

        const newClassIdxU64: u64 = calldata.readU256().toU64();
        const newBodyIdxU64: u64 = calldata.readU256().toU64();
        const newFaceIdxU64: u64 = calldata.readU256().toU64();
        const newItemIdxU64: u64 = calldata.readU256().toU64();

        // Validate class is registered and enabled
        const numClasses: u64 = this._numRegisteredClasses.value.toU64();
        if (newClassIdxU64 >= numClasses) {
            throw new Revert(ERR_NFT_INVALID_CLASS);
        }
        const def: u256 = this._classRegistry.get(u256.fromU64(newClassIdxU64));
        if (this._classEnabled(def) == 0) {
            throw new Revert(ERR_NFT_INVALID_CLASS);
        }

        // Validate trait indices within class bounds
        if (newBodyIdxU64 >= this._classNumBodies(def)) {
            throw new Revert(ERR_NFT_INVALID_TRAIT_IDX);
        }
        if (newFaceIdxU64 >= this._classNumFaces(def)) {
            throw new Revert(ERR_NFT_INVALID_TRAIT_IDX);
        }
        if (newItemIdxU64 >= this._classNumItems(def)) {
            throw new Revert(ERR_NFT_INVALID_TRAIT_IDX);
        }

        // Update trait data
        const oldPacked: u256 = this._traitData.get(tokenId);
        const oldClassIdx: u64 = this._extractClassIdx(oldPacked);

        // Preserve subitem/OG from old packed value
        const oldSubitemIdx: u64 = this._extractSubitemIdx(oldPacked);
        const oldIsOG: u64 = this._extractIsOG(oldPacked) ? 1 : 0;
        const newLo1: u64 = this._packLo1(newClassIdxU64, oldSubitemIdx, oldIsOG);
        const newPacked: u256 = new u256(newLo1, newBodyIdxU64, newFaceIdxU64, newItemIdxU64);

        // Dedup: use clean 4-trait combo keys (no subitem/OG)
        const oldCombo: u256 = this._comboKey(oldPacked);
        const newCombo: u256 = new u256(newClassIdxU64, newBodyIdxU64, newFaceIdxU64, newItemIdxU64);
        if (!u256.eq(newCombo, oldCombo) && !u256.eq(this._usedCombos.get(newCombo), u256.Zero)) {
            throw new Revert(ERR_NFT_COMBO_TAKEN);
        }
        this._usedCombos.set(oldCombo, u256.Zero);
        this._usedCombos.set(newCombo, u256.One);

        this._traitData.set(tokenId, newPacked);

        // Update class counts if class changed
        if (oldClassIdx != newClassIdxU64) {
            const owner: Address = this._ownerOf(tokenId);
            this._decrementClassCount(owner, oldClassIdx);
            this._incrementClassCount(owner, newClassIdxU64);
        }

        this.emitEvent(new TraitsUpdatedEvent(tokenId, newPacked));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Trait Metadata (deployer-updatable)
    // -----------------------------------------------------------------------

    @method(
        { name: 'tokenId', type: ABIDataTypes.UINT256 },
        { name: 'classIdx', type: ABIDataTypes.UINT256 },
        { name: 'bodyIdx', type: ABIDataTypes.UINT256 },
        { name: 'faceIdx', type: ABIDataTypes.UINT256 },
        { name: 'itemIdx', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setTokenTraits(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);

        const classIdx: u256 = calldata.readU256();
        const bodyIdx: u256 = calldata.readU256();
        const faceIdx: u256 = calldata.readU256();
        const itemIdx: u256 = calldata.readU256();

        const oldPacked: u256 = this._traitData.get(tokenId);
        const oldClassIdx: u64 = this._extractClassIdx(oldPacked);
        const newClassIdx: u64 = classIdx.toU64();

        // Preserve subitem/OG from old packed value
        const oldSubitemIdx: u64 = this._extractSubitemIdx(oldPacked);
        const oldIsOG: u64 = this._extractIsOG(oldPacked) ? 1 : 0;
        const newLo1: u64 = this._packLo1(newClassIdx, oldSubitemIdx, oldIsOG);
        const packed: u256 = new u256(
            newLo1,
            bodyIdx.toU64(),
            faceIdx.toU64(),
            itemIdx.toU64(),
        );

        // Dedup: use clean 4-trait combo keys (no subitem/OG)
        const oldCombo: u256 = this._comboKey(oldPacked);
        const newCombo: u256 = new u256(newClassIdx, bodyIdx.toU64(), faceIdx.toU64(), itemIdx.toU64());
        if (!u256.eq(newCombo, oldCombo) && !u256.eq(this._usedCombos.get(newCombo), u256.Zero)) {
            throw new Revert(ERR_NFT_COMBO_TAKEN);
        }
        // Free old, claim new
        this._usedCombos.set(oldCombo, u256.Zero);
        this._usedCombos.set(newCombo, u256.One);

        this._traitData.set(tokenId, packed);

        if (oldClassIdx != newClassIdx) {
            const owner: Address = this._ownerOf(tokenId);
            this._decrementClassCount(owner, oldClassIdx);
            this._incrementClassCount(owner, newClassIdx);
        }

        this.emitEvent(new TraitsUpdatedEvent(tokenId, packed));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method(
        { name: 'startId', type: ABIDataTypes.UINT256 },
        { name: 'count', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setBatchTraits(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const startId: u256 = calldata.readU256();
        const count: u256 = calldata.readU256();
        const countU64: u64 = count.toU64();

        if (countU64 > MAX_BATCH_SIZE) {
            throw new Revert(ERR_NFT_BATCH_TOO_LARGE);
        }

        for (let i: u64 = 0; i < countU64; i++) {
            const packed: u256 = calldata.readU256();
            const tokenId: u256 = SafeMath.add(startId, u256.fromU64(i));
            this._requireExists(tokenId);

            const oldPacked: u256 = this._traitData.get(tokenId);
            const oldClassIdx: u64 = this._extractClassIdx(oldPacked);
            const newClassIdx: u64 = this._extractClassIdx(packed);

            // Dedup: use clean 4-trait combo keys (no subitem/OG)
            const oldCombo: u256 = this._comboKey(oldPacked);
            const newCombo: u256 = this._comboKey(packed);
            if (!u256.eq(newCombo, oldCombo) && !u256.eq(this._usedCombos.get(newCombo), u256.Zero)) {
                throw new Revert(ERR_NFT_COMBO_TAKEN);
            }
            this._usedCombos.set(oldCombo, u256.Zero);
            this._usedCombos.set(newCombo, u256.One);

            this._traitData.set(tokenId, packed);

            if (oldClassIdx != newClassIdx) {
                const owner: Address = this._ownerOf(tokenId);
                this._decrementClassCount(owner, oldClassIdx);
                this._incrementClassCount(owner, newClassIdx);
            }

            this.emitEvent(new TraitsUpdatedEvent(tokenId, packed));
        }

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns(
        { name: 'classIdx', type: ABIDataTypes.UINT256 },
        { name: 'bodyIdx', type: ABIDataTypes.UINT256 },
        { name: 'faceIdx', type: ABIDataTypes.UINT256 },
        { name: 'itemIdx', type: ABIDataTypes.UINT256 },
        { name: 'subitemIdx', type: ABIDataTypes.UINT256 },
    )
    public getTokenTraits(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);

        const packed: u256 = this._traitData.get(tokenId);

        const writer: BytesWriter = new BytesWriter(160); // 5 × 32
        writer.writeU256(u256.fromU64(this._extractClassIdx(packed)));   // classIdx
        writer.writeU256(u256.fromU64(packed.lo2));                       // bodyIdx
        writer.writeU256(u256.fromU64(packed.hi1));                       // faceIdx
        writer.writeU256(u256.fromU64(packed.hi2));                       // itemIdx
        writer.writeU256(u256.fromU64(this._extractSubitemIdx(packed))); // subitemIdx
        return writer;
    }

    /**
     * Returns the traitKeys needed to render a token's SVG.
     * Clients call the FrenForge contract for each key.
     */
    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns(
        { name: 'bodyKey', type: ABIDataTypes.UINT256 },
        { name: 'faceKey', type: ABIDataTypes.UINT256 },
        { name: 'itemKey', type: ABIDataTypes.UINT256 },
    )
    public getTokenTraitKeys(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        this._requireExists(tokenId);

        const packed: u256 = this._traitData.get(tokenId);
        const classIdx: u64 = this._extractClassIdx(packed);
        const bodyIdx: u64 = packed.lo2;
        const faceIdx: u64 = packed.hi1;
        const itemIdx: u64 = packed.hi2;

        const bodyKey: u256 = u256.fromU64(classIdx * 256 + bodyIdx);
        const faceClassIdx: u64 = (classIdx == 5) ? 5 : (classIdx == 6) ? 6 : 0;
        const faceKey: u256 = u256.fromU64(65536 + faceClassIdx * 256 + faceIdx);
        const itemKey: u256 = u256.fromU64(131072 + classIdx * 256 + itemIdx);

        const w: BytesWriter = new BytesWriter(96);
        w.writeU256(bodyKey);
        w.writeU256(faceKey);
        w.writeU256(itemKey);
        return w;
    }


    // -----------------------------------------------------------------------
    // Internal: Cauldron Summoning
    // -----------------------------------------------------------------------

    private _summonCauldron(): void {
        const summoned: u256 = this._cauldronSummoned.value;
        if (u256.eq(summoned, u256.One)) {
            return;
        }
        this._cauldronSummoned.value = u256.One;
        this.emitEvent(new CauldronSummonReadyEvent(MAX_NFT_SUPPLY));
    }

    // -----------------------------------------------------------------------
    // Internal: Random Trait Assignment (weighted class selection)
    // -----------------------------------------------------------------------

    private _randomInRange(max: u64): u64 {
        const nonce: u256 = this._randomNonce.value;
        this._randomNonce.value = SafeMath.add(nonce, u256.One);

        const blockNumber: u256 = u256.fromU64(Blockchain.block.number);
        const sender: Address = Blockchain.tx.sender;

        const entropyWriter: BytesWriter = new BytesWriter(96);
        entropyWriter.writeU256(nonce);
        entropyWriter.writeU256(blockNumber);
        entropyWriter.writeAddress(sender);
        const hashResult: Uint8Array = sha256(entropyWriter.getBuffer());
        const hashArr: u8[] = this._uint8ToU8Array(hashResult);
        const mixed: u256 = u256.fromBytesBE(hashArr);

        const modulus: u256 = u256.fromU64(max + 1);
        const result: u256 = SafeMath.mod(mixed, modulus);
        return result.toU64();
    }

    private _assignRandomTraits(): u256 {
        // Retry up to 50 times to find a unique combo.
        // Total combos across all classes = 1092, max supply = 777, so collisions
        // are possible but a unique combo will always exist until supply is exhausted.
        const lastClass: u64 = this._lastMintedClass.value.toU64();

        for (let attempt: u32 = 0; attempt < 50; attempt++) {
            // Single weighted roll mod 10000 determines class
            const roll: u64 = this._randomInRange(9999);

            let classIdx: u64;
            if (roll < CLASS_WEIGHT_WIZARD) {
                classIdx = 0;
            } else if (roll < CLASS_WEIGHT_KING) {
                classIdx = 1;
            } else if (roll < CLASS_WEIGHT_KNIGHT) {
                classIdx = 2;
            } else if (roll < CLASS_WEIGHT_APPRENTICE) {
                classIdx = 3;
            } else if (roll < CLASS_WEIGHT_PEASANT) {
                classIdx = 4;
            } else if (roll < CLASS_WEIGHT_GNOME) {
                classIdx = 5;
            } else {
                classIdx = 6;
            }

            // Skip if same class as previous mint (relax for last 5 retries)
            if (classIdx == lastClass && attempt < 45) continue;

            // Read class def for art bounds
            const classDef: u256 = this._classRegistry.get(u256.fromU64(classIdx));

            // Skip disabled or non-mintable classes
            if (this._classEnabled(classDef) == 0) continue;
            if (this._classMintable(classDef) == 0) continue;
            const numBodies: u64 = this._classNumBodies(classDef);
            const numFaces: u64 = this._classNumFaces(classDef);
            const numItems: u64 = this._classNumItems(classDef);

            const bodyIdx: u64 = this._randomInRange(numBodies - 1);
            const faceIdx: u64 = this._randomInRange(numFaces - 1);
            const itemIdx: u64 = this._randomInRange(numItems - 1);

            const combo: u256 = new u256(classIdx, bodyIdx, faceIdx, itemIdx);

            // Check uniqueness + skip combos reserved for treasury
            if (u256.eq(this._usedCombos.get(combo), u256.Zero)) {
                if (this._isReservedCombo(classIdx, bodyIdx, faceIdx, itemIdx)) continue;

                this._usedCombos.set(combo, u256.One);

                // Determine subitem based on class
                let subitemIdx: u64 = 0;
                if (classIdx == 4) {
                    // Peasant: random headgear (0=none, 1=mumu, 2=bobo)
                    subitemIdx = this._randomInRange(2);
                } else {
                    // Other classes: rare block-based subitems (~1.5% each)
                    const blockNum: u64 = Blockchain.block.number;
                    if (blockNum % 666 < 10) {
                        subitemIdx = 2; // skull
                    } else if (blockNum % 777 < 12) {
                        subitemIdx = 1; // potion
                    }
                }

                // Update last minted class for consecutive-class prevention
                this._lastMintedClass.value = u256.fromU64(classIdx);

                return new u256(
                    this._packLo1(classIdx, subitemIdx, 0),
                    bodyIdx, faceIdx, itemIdx,
                );
            }
            // Collision — retry with bumped nonce (already incremented by _randomInRange)
        }

        throw new Revert(ERR_NFT_COMBO_EXHAUSTED);
    }

    // -----------------------------------------------------------------------
    // Internal: Per-Address Class Count Packing (up to 16 classes across 2 u256 slots)
    // -----------------------------------------------------------------------
    // Each u256 holds 8 x u32 counts:
    //   _classCounts (lo slot): classes 0-7
    //   _classCountsHi (hi slot): classes 8-15
    // Within a u256:
    //   lo1: [slot0(low32)] [slot1(high32)]
    //   lo2: [slot2(low32)] [slot3(high32)]
    //   hi1: [slot4(low32)] [slot5(high32)]
    //   hi2: [slot6(low32)] [slot7(high32)]

    private _incrementClassCount(holder: Address, classIdx: u64): void {
        if (classIdx < 8) {
            const packed: u256 = this._classCounts.get(holder);
            const updated: u256 = this._adjustClassCount(packed, classIdx, 1);
            this._classCounts.set(holder, updated);
        } else {
            const packed: u256 = this._classCountsHi.get(holder);
            const updated: u256 = this._adjustClassCount(packed, classIdx - 8, 1);
            this._classCountsHi.set(holder, updated);
        }
    }

    private _decrementClassCount(holder: Address, classIdx: u64): void {
        if (classIdx < 8) {
            const packed: u256 = this._classCounts.get(holder);
            const updated: u256 = this._adjustClassCount(packed, classIdx, -1);
            this._classCounts.set(holder, updated);
        } else {
            const packed: u256 = this._classCountsHi.get(holder);
            const updated: u256 = this._adjustClassCount(packed, classIdx - 8, -1);
            this._classCountsHi.set(holder, updated);
        }
    }

    /**
     * Generic class count adjustment. slotOffset is 0-7 within a single u256.
     * Each u64 limb holds 2 x u32 counts: low32 = even offset, high32 = odd offset.
     */
    private _adjustClassCount(packed: u256, slotOffset: u64, delta: i32): u256 {
        let lo1: u64 = packed.lo1;
        let lo2: u64 = packed.lo2;
        let hi1: u64 = packed.hi1;
        let hi2: u64 = packed.hi2;

        // Determine which limb and which half (low32 or high32)
        const limbIdx: u64 = slotOffset >> 1;  // 0=lo1, 1=lo2, 2=hi1, 3=hi2
        const isHigh: bool = (slotOffset & 1) == 1;

        let limb: u64;
        if (limbIdx == 0) limb = lo1;
        else if (limbIdx == 1) limb = lo2;
        else if (limbIdx == 2) limb = hi1;
        else limb = hi2;

        let count: u64;
        if (isHigh) {
            count = (limb >> 32) & 0xFFFFFFFF;
        } else {
            count = limb & 0xFFFFFFFF;
        }

        if (delta < 0 && count == 0) return packed;
        const newCount: u64 = (count as i64 + (delta as i64)) as u64;

        if (isHigh) {
            limb = (limb & 0x00000000FFFFFFFF) | ((newCount & 0xFFFFFFFF) << 32);
        } else {
            limb = (limb & 0xFFFFFFFF00000000) | (newCount & 0xFFFFFFFF);
        }

        if (limbIdx == 0) lo1 = limb;
        else if (limbIdx == 1) lo2 = limb;
        else if (limbIdx == 2) hi1 = limb;
        else hi2 = limb;

        return new u256(lo1, lo2, hi1, hi2);
    }

    /**
     * Read a single class's count from the two packed u256 slots.
     */
    private _getClassCountFromPacked(classIdx: u64, packedLo: u256, packedHi: u256): u64 {
        let packed: u256;
        let offset: u64;
        if (classIdx < 8) {
            packed = packedLo;
            offset = classIdx;
        } else {
            packed = packedHi;
            offset = classIdx - 8;
        }

        const limbIdx: u64 = offset >> 1;
        const isHigh: bool = (offset & 1) == 1;

        let limb: u64;
        if (limbIdx == 0) limb = packed.lo1;
        else if (limbIdx == 1) limb = packed.lo2;
        else if (limbIdx == 2) limb = packed.hi1;
        else limb = packed.hi2;

        if (isHigh) {
            return (limb >> 32) & 0xFFFFFFFF;
        } else {
            return limb & 0xFFFFFFFF;
        }
    }

    // -----------------------------------------------------------------------
    // Internal: Class Registry Pack / Unpack
    // -----------------------------------------------------------------------
    // lo1 (u64): [numBodies:u16][numFaces:u16][numItems:u16][enabled:u8][mintable:u8]
    // lo2 (u64): [taxBPS:u32][mintTier:u16][reserved:u16]
    // hi1, hi2: reserved

    private _packClassDef(
        numBodies: u64, numFaces: u64, numItems: u64,
        enabled: u64, mintable: u64,
        taxBPS: u64, mintTier: u64,
    ): u256 {
        const lo1: u64 =
            ((numBodies & 0xFFFF) << 48) |
            ((numFaces & 0xFFFF) << 32) |
            ((numItems & 0xFFFF) << 16) |
            ((enabled & 0xFF) << 8) |
            (mintable & 0xFF);
        const lo2: u64 =
            ((taxBPS & 0xFFFFFFFF) << 32) |
            ((mintTier & 0xFFFF) << 16);
        return new u256(lo1, lo2, 0, 0);
    }

    private _classNumBodies(def: u256): u64 { return (def.lo1 >> 48) & 0xFFFF; }
    private _classNumFaces(def: u256): u64 { return (def.lo1 >> 32) & 0xFFFF; }
    private _classNumItems(def: u256): u64 { return (def.lo1 >> 16) & 0xFFFF; }
    private _classEnabled(def: u256): u64 { return (def.lo1 >> 8) & 0xFF; }
    private _classMintable(def: u256): u64 { return def.lo1 & 0xFF; }
    private _classTaxBPS(def: u256): u64 { return (def.lo2 >> 32) & 0xFFFFFFFF; }
    private _classMintTier(def: u256): u64 { return (def.lo2 >> 16) & 0xFFFF; }

    // -----------------------------------------------------------------------
    // Internal: Trait Packing Helpers
    // -----------------------------------------------------------------------
    // lo1 bitfield: [classIdx:bits 0-7] [subitemIdx:bits 8-15] [isOG:bit 16]

    private _extractClassIdx(packed: u256): u64 { return packed.lo1 & 0xFF; }
    private _extractSubitemIdx(packed: u256): u64 { return (packed.lo1 >> 8) & 0xFF; }
    private _extractIsOG(packed: u256): bool { return ((packed.lo1 >> 16) & 1) == 1; }
    private _packLo1(classIdx: u64, subitemIdx: u64, isOG: u64): u64 {
        return classIdx | (subitemIdx << 8) | (isOG << 16);
    }
    /** Strip subitem/OG bits from lo1 — keeps only the 4 main trait indices for _usedCombos keys */
    private _comboKey(packed: u256): u256 {
        return new u256(packed.lo1 & 0xFF, packed.lo2, packed.hi1, packed.hi2);
    }

    /**
     * Check if a trait combo is reserved for treasury (defined in RESERVE_TRAITS constant).
     * Public mints must skip these combos so reserveBatch() can always claim them.
     */
    private _isReservedCombo(classIdx: u64, bodyIdx: u64, faceIdx: u64, itemIdx: u64): bool {
        for (let i: u32 = 0; i < (RESERVE_TRAITS.length as u32); i += 4) {
            if (
                (RESERVE_TRAITS[i] as u64) == classIdx &&
                (RESERVE_TRAITS[i + 1] as u64) == bodyIdx &&
                (RESERVE_TRAITS[i + 2] as u64) == faceIdx &&
                (RESERVE_TRAITS[i + 3] as u64) == itemIdx
            ) {
                return true;
            }
        }
        return false;
    }

    // -----------------------------------------------------------------------
    // Internal: Class Benefit Helpers
    // -----------------------------------------------------------------------

    private _classToMaxBorrow(classIdx: u64): u256 {
        if (classIdx == 0) return MAX_BORROW_WIZARD;
        if (classIdx == 1) return MAX_BORROW_KING;
        if (classIdx == 2) return MAX_BORROW_KNIGHT;
        if (classIdx == 3) return MAX_BORROW_APPRENTICE;
        if (classIdx == 4) return MAX_BORROW_PEASANT;
        if (classIdx == 5) return MAX_BORROW_GNOME;
        if (classIdx == 6) return MAX_BORROW_ELF;
        return MAX_BORROW_PEASANT;
    }

    private _classToGrace(classIdx: u64): u256 {
        if (classIdx == 0) return GRACE_WIZARD;
        if (classIdx == 1) return GRACE_KING;
        if (classIdx == 2) return GRACE_KNIGHT;
        if (classIdx == 3) return GRACE_APPRENTICE;
        if (classIdx == 4) return GRACE_PEASANT;
        if (classIdx == 5) return GRACE_GNOME;
        if (classIdx == 6) return GRACE_ELF;
        return GRACE_PEASANT;
    }

    // -----------------------------------------------------------------------
    // Internal: Helpers
    // -----------------------------------------------------------------------

    private _uint8ToU8Array(data: Uint8Array): u8[] {
        const arr = new Array<u8>(data.length);
        for (let i: i32 = 0; i < data.length; i++) {
            arr[i] = data[i];
        }
        return arr;
    }

    // -----------------------------------------------------------------------
    // Internal: Access Control
    // -----------------------------------------------------------------------

    private _onlyCauldron(caller: Address): void {
        const isCauldron: u256 = this._cauldronWhitelist.get(caller);
        if (!u256.eq(isCauldron, u256.One)) {
            throw new Revert(ERR_NFT_NOT_CAULDRON);
        }
    }

    private _requireExists(tokenId: u256): void {
        if (!this._exists(tokenId)) {
            throw new Revert(ERR_NFT_NOT_EXIST);
        }
    }

    // -----------------------------------------------------------------------
    // Internal: Scattered Reserve Helpers
    // -----------------------------------------------------------------------

    /**
     * Binary search on the sorted RESERVED_IDS array.
     * Returns true if the given token ID is reserved for treasury.
     * 77 entries → max 7 iterations. Uses bounded for loop (OPNet convention).
     */
    private _isReservedId(id: u64): bool {
        let lo: u32 = 0;
        let hi: u32 = TREASURY_RESERVE as u32;
        // Binary search: log2(77) < 7, so 8 iterations is always sufficient.
        for (let iter: u32 = 0; iter < 8; iter++) {
            if (lo >= hi) break;
            const mid: u32 = (lo + hi) >> 1;
            const midVal: u64 = RESERVED_IDS[mid] as u64;
            if (midVal == id) return true;
            if (midVal < id) lo = mid + 1;
            else hi = mid;
        }
        return false;
    }

    /**
     * Get the next available public token ID, skipping any reserved IDs.
     * Advances _nextTokenId past the returned ID.
     * Uses bounded for loop — max consecutive reserved IDs in any band is 13,
     * so 20 iterations is always sufficient.
     */
    private _advancePublicId(): u256 {
        let id: u256 = this._nextTokenId.value;
        // Skip reserved IDs (bounded: max 13 consecutive in any 100-ID band)
        for (let skip: u32 = 0; skip < 20; skip++) {
            if (!this._isReservedId(id.toU64())) break;
            id = SafeMath.add(id, u256.One);
        }
        // Set _nextTokenId past this ID
        this._nextTokenId.value = SafeMath.add(id, u256.One);
        return id;
    }
}
