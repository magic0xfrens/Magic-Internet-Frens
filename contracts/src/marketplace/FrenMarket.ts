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
    StoredAddress,
    StoredU256,
    StoredMapU256,
} from '@btc-vision/btc-runtime/runtime';
import { CallResult } from '@btc-vision/btc-runtime/runtime/env/BlockchainEnvironment';
import { sha256 } from '@btc-vision/btc-runtime/runtime/env/global';

import {
    REENTRANCY_UNLOCKED,
    REENTRANCY_LOCKED,
    BPS_PRECISION,
    RESERVATION_BLOCKS,
} from '../lib/constants';
import {
    ERR_MARKET_NOT_ADMIN,
    ERR_MARKET_ZERO_ADDR,
    ERR_MARKET_NFT_NOT_SET,
    ERR_MARKET_NOT_NFT_OWNER,
    ERR_MARKET_ZERO_PRICE,
    ERR_MARKET_ALREADY_LISTED,
    ERR_MARKET_NOT_LISTED,
    ERR_MARKET_NOT_SELLER,
    ERR_MARKET_PAYMENT_REQUIRED,
    ERR_MARKET_NFT_LOCKED,
    ERR_MARKET_TRANSFER_FAILED,
    ERR_MARKET_REENTRANT,
    ERR_MARKET_CANNOT_BUY_OWN,
    ERR_MARKET_INDEX_OOB,
    ERR_MARKET_FEE_TOO_HIGH,
    ERR_MARKET_FEE_PAYMENT_REQUIRED,
    ERR_MARKET_ALREADY_RESERVED,
    ERR_MARKET_NOT_RESERVER,
    ERR_MARKET_RESERVATION_EXPIRED,
    ERR_MARKET_NO_RESERVATION,
    ERR_MARKET_HAS_ACTIVE_RESERVATION,
} from '../lib/errors';

// ---------------------------------------------------------------------------
// Marketplace Fee Tiers (magic numbers) — mapped from MiFrens holder tax rate
// ---------------------------------------------------------------------------
const MARKET_FEE_WIZARD: u64 = 0;       // 0%     — Wizard holders
const MARKET_FEE_NOBLE: u64 = 111;      // 1.11%  — King/Gnome/Elf holders
const MARKET_FEE_COMMON: u64 = 333;     // 3.33%  — Knight/Apprentice holders
const MARKET_FEE_PEASANT: u64 = 420;    // 4.20%  — Peasant holders
// Non-holders pay the full base fee (690 BPS = 6.9%)

/**
 * FrenMarket — NFT marketplace with two-phase reserve/claim buy pattern.
 *
 * Buy flow:
 *   1. reserveBuy(tokenId)   — locks listing for RESERVATION_BLOCKS blocks (gas-only TX)
 *   2. claimReserved(tokenId) — completes purchase with BTC payment outputs
 *
 * This prevents double-spending: only one buyer can reserve at a time.
 * If the reservation expires without claiming, the listing becomes available again.
 *
 * Listing data layout:
 *   - listingSeller: StoredMapU256  (tokenId → packed seller address as u256)
 *   - listingPrice:  StoredMapU256  (tokenId → price in sats)
 *
 * Reservation data:
 *   - reservedBy:     StoredMapU256  (tokenId → buyer address as u256, 0 = none)
 *   - reserveExpiry:  StoredMapU256  (tokenId → block number when reservation expires)
 *
 * Active listing index:
 *   - activeListingTokenIds: StoredMapU256 (index → tokenId)
 *   - activeListingIndex:    StoredMapU256 (tokenId → index+1, 0 means not listed)
 *   - activeListingCount:    StoredU256
 */

@final
export class FrenMarket extends OP_NET {
    // -----------------------------------------------------------------------
    // Storage Pointers (order must be preserved across upgrades)
    // -----------------------------------------------------------------------

    private readonly nftContractPointer: u16 = Blockchain.nextPointer;
    private readonly listingSellerPointer: u16 = Blockchain.nextPointer;
    private readonly listingPricePointer: u16 = Blockchain.nextPointer;
    private readonly activeListingTokenIdsPointer: u16 = Blockchain.nextPointer;
    private readonly activeListingIndexPointer: u16 = Blockchain.nextPointer;
    private readonly activeListingCountPointer: u16 = Blockchain.nextPointer;
    private readonly reentrancyPointer: u16 = Blockchain.nextPointer;
    private readonly feeRecipientPointer: u16 = Blockchain.nextPointer;
    private readonly feeRecipientHashPointer: u16 = Blockchain.nextPointer;
    private readonly feeBpsPointer: u16 = Blockchain.nextPointer;
    private readonly listingSellerHashPointer: u16 = Blockchain.nextPointer;
    private readonly sellerAddrBytesHiPointer: u16 = Blockchain.nextPointer;
    private readonly sellerAddrBytesLoPointer: u16 = Blockchain.nextPointer;
    // New: reservation storage
    private readonly reservedByPointer: u16 = Blockchain.nextPointer;
    private readonly reserveExpiryPointer: u16 = Blockchain.nextPointer;

    // -----------------------------------------------------------------------
    // Pre-computed Selectors
    // -----------------------------------------------------------------------

    private readonly GET_HOLDER_TAX_RATE_SELECTOR: u32 = encodeSelector('getHolderTaxRate(address)');

    // -----------------------------------------------------------------------
    // Storage Instances
    // -----------------------------------------------------------------------

    private _nftContract!: StoredAddress;
    private _listingSeller!: StoredMapU256;
    private _listingPrice!: StoredMapU256;
    private _activeListingTokenIds!: StoredMapU256;
    private _activeListingIndex!: StoredMapU256;
    private _activeListingCount!: StoredU256;
    private _reentrancyGuard!: StoredU256;
    private _feeRecipient!: StoredAddress;
    private _feeRecipientHash!: StoredU256;
    private _feeBps!: StoredU256;
    private _listingSellerHash!: StoredMapU256;
    private _sellerAddrBytesHi!: StoredMapU256;
    private _sellerAddrBytesLo!: StoredMapU256;
    private _reservedBy!: StoredMapU256;
    private _reserveExpiry!: StoredMapU256;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    public constructor() {
        super();

        this._nftContract = new StoredAddress(this.nftContractPointer);
        this._listingSeller = new StoredMapU256(this.listingSellerPointer);
        this._listingPrice = new StoredMapU256(this.listingPricePointer);
        this._activeListingTokenIds = new StoredMapU256(this.activeListingTokenIdsPointer);
        this._activeListingIndex = new StoredMapU256(this.activeListingIndexPointer);
        this._activeListingCount = new StoredU256(this.activeListingCountPointer, new Uint8Array(0));
        this._reentrancyGuard = new StoredU256(this.reentrancyPointer, new Uint8Array(0));
        this._feeRecipient = new StoredAddress(this.feeRecipientPointer);
        this._feeRecipientHash = new StoredU256(this.feeRecipientHashPointer, new Uint8Array(0));
        this._feeBps = new StoredU256(this.feeBpsPointer, new Uint8Array(0));
        this._listingSellerHash = new StoredMapU256(this.listingSellerHashPointer);
        this._sellerAddrBytesHi = new StoredMapU256(this.sellerAddrBytesHiPointer);
        this._sellerAddrBytesLo = new StoredMapU256(this.sellerAddrBytesLoPointer);
        this._reservedBy = new StoredMapU256(this.reservedByPointer);
        this._reserveExpiry = new StoredMapU256(this.reserveExpiryPointer);
    }

    // -----------------------------------------------------------------------
    // Deployment
    // -----------------------------------------------------------------------

    public override onDeployment(_calldata: Calldata): void {
        // Default fee: 6.9% = 690 BPS
        this._feeBps.value = u256.fromU64(690);
    }

    // -----------------------------------------------------------------------
    // Admin Methods
    // -----------------------------------------------------------------------

    @method({ name: 'nftContract', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setNFTContract(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const addr: Address = calldata.readAddress();
        if (addr.equals(Address.zero())) throw new Revert(ERR_MARKET_ZERO_ADDR);
        this._nftContract.value = addr;
        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    @method({ name: 'recipient', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setFeeRecipient(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const addr: Address = calldata.readAddress();
        if (addr.equals(Address.zero())) throw new Revert(ERR_MARKET_ZERO_ADDR);
        this._feeRecipient.value = addr;
        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    @method({ name: 'hash', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setFeeRecipientHash(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        this._feeRecipientHash.value = calldata.readU256();
        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    @method({ name: 'bps', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setFeeBps(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const bps: u256 = calldata.readU256();
        const MAX_FEE_BPS: u256 = u256.fromU64(1_000);
        if (u256.gt(bps, MAX_FEE_BPS)) {
            throw new Revert(ERR_MARKET_FEE_TOO_HIGH);
        }
        this._feeBps.value = bps;
        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    // -----------------------------------------------------------------------
    // Marketplace Methods
    // -----------------------------------------------------------------------

    /**
     * List an NFT for sale.
     * Caller must own the token. The marketplace takes custody via transferFrom.
     * Token must not be locked in a Cauldron.
     */
    @method(
        { name: 'tokenId', type: ABIDataTypes.UINT256 },
        { name: 'priceSats', type: ABIDataTypes.UINT256 },
        { name: 'sellerAddrHash', type: ABIDataTypes.UINT256 },
        { name: 'sellerAddrHi', type: ABIDataTypes.UINT256 },
        { name: 'sellerAddrLo', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public listNFT(calldata: Calldata): BytesWriter {
        this._acquireReentrancy();

        const tokenId: u256 = calldata.readU256();
        const priceSats: u256 = calldata.readU256();
        const sellerAddrHash: u256 = calldata.readU256();
        const sellerAddrHi: u256 = calldata.readU256();
        const sellerAddrLo: u256 = calldata.readU256();
        const sender: Address = Blockchain.tx.sender;
        const nft: Address = this._nftContract.value;

        if (nft.equals(Address.zero())) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NFT_NOT_SET);
        }
        if (priceSats.isZero()) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_ZERO_PRICE);
        }

        // Check not already listed
        const existingIdx: u256 = this._activeListingIndex.get(tokenId);
        if (!existingIdx.isZero()) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_ALREADY_LISTED);
        }

        // Verify caller owns the token
        this._verifyOwnership(nft, tokenId, sender);

        // Verify token is not locked
        this._verifyNotLocked(nft, tokenId);

        // Transfer NFT to marketplace (caller must have approved this contract)
        this._transferFromNFT(nft, sender, Blockchain.contractAddress, tokenId);

        // Store listing data
        this._listingSeller.set(tokenId, this._addressToU256(sender));
        this._listingPrice.set(tokenId, priceSats);
        this._listingSellerHash.set(tokenId, sellerAddrHash);
        this._sellerAddrBytesHi.set(tokenId, sellerAddrHi);
        this._sellerAddrBytesLo.set(tokenId, sellerAddrLo);

        // Add to active listings index
        const count: u256 = this._activeListingCount.value;
        this._activeListingTokenIds.set(count, tokenId);
        const newCount: u256 = SafeMath.add(count, u256.One);
        this._activeListingIndex.set(tokenId, newCount); // Store index+1 (0 = not listed)
        this._activeListingCount.value = newCount;

        this._releaseReentrancy();

        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    /**
     * Cancel a listing. Returns NFT to seller.
     * Only the original seller can cancel.
     * Cannot cancel while an active (non-expired) reservation exists.
     */
    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public cancelListing(calldata: Calldata): BytesWriter {
        this._acquireReentrancy();

        const tokenId: u256 = calldata.readU256();
        const sender: Address = Blockchain.tx.sender;

        // Verify listing exists
        const idxPlusOne: u256 = this._activeListingIndex.get(tokenId);
        if (idxPlusOne.isZero()) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NOT_LISTED);
        }

        // Verify caller is the seller
        const sellerU256: u256 = this._listingSeller.get(tokenId);
        const senderU256: u256 = this._addressToU256(sender);
        if (!u256.eq(sellerU256, senderU256)) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NOT_SELLER);
        }

        // Check for active reservation — cannot cancel while someone has a valid reservation
        if (this._hasActiveReservation(tokenId)) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_HAS_ACTIVE_RESERVATION);
        }

        // Clear any expired reservation data
        this._clearReservation(tokenId);

        // Return NFT to seller (marketplace is the current owner)
        const nft: Address = this._nftContract.value;
        this._transferNFT(nft, sender, tokenId);

        // Remove from active listings
        this._removeActiveListing(tokenId, idxPlusOne);

        // Clear listing data
        this._clearListingData(tokenId);

        this._releaseReentrancy();

        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    /**
     * Reserve a listed NFT for purchase. Gas-only transaction (no BTC payment).
     * Locks the listing for RESERVATION_BLOCKS blocks. Only one buyer can reserve at a time.
     * After reserving, call claimReserved() with BTC payment to complete the purchase.
     */
    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public reserveBuy(calldata: Calldata): BytesWriter {
        this._acquireReentrancy();

        const tokenId: u256 = calldata.readU256();
        const buyer: Address = Blockchain.tx.sender;
        const nft: Address = this._nftContract.value;

        if (nft.equals(Address.zero())) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NFT_NOT_SET);
        }

        // Verify listing exists
        const idxPlusOne: u256 = this._activeListingIndex.get(tokenId);
        if (idxPlusOne.isZero()) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NOT_LISTED);
        }

        // Cannot reserve own listing
        const sellerU256: u256 = this._listingSeller.get(tokenId);
        const buyerU256: u256 = this._addressToU256(buyer);
        if (u256.eq(sellerU256, buyerU256)) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_CANNOT_BUY_OWN);
        }

        // Check no active reservation exists
        if (this._hasActiveReservation(tokenId)) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_ALREADY_RESERVED);
        }

        // Set reservation
        const currentBlock: u64 = Blockchain.block.number;
        const expiryBlock: u64 = currentBlock + RESERVATION_BLOCKS;
        this._reservedBy.set(tokenId, buyerU256);
        this._reserveExpiry.set(tokenId, u256.fromU64(expiryBlock));

        this._releaseReentrancy();

        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    /**
     * Complete a reserved purchase with BTC payment.
     * Must be called by the reserver within RESERVATION_BLOCKS of the reservation.
     * Verifies BTC payment to seller and marketplace fee in tx outputs.
     */
    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public claimReserved(calldata: Calldata): BytesWriter {
        this._acquireReentrancy();

        const tokenId: u256 = calldata.readU256();
        const buyer: Address = Blockchain.tx.sender;
        const nft: Address = this._nftContract.value;

        if (nft.equals(Address.zero())) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NFT_NOT_SET);
        }

        // Verify listing exists
        const idxPlusOne: u256 = this._activeListingIndex.get(tokenId);
        if (idxPlusOne.isZero()) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NOT_LISTED);
        }

        // Verify reservation exists
        const reserverU256: u256 = this._reservedBy.get(tokenId);
        if (reserverU256.isZero()) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NO_RESERVATION);
        }

        // Verify caller is the reserver
        const buyerU256: u256 = this._addressToU256(buyer);
        if (!u256.eq(reserverU256, buyerU256)) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NOT_RESERVER);
        }

        // Verify reservation not expired
        const expiryBlock: u256 = this._reserveExpiry.get(tokenId);
        const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
        if (u256.gt(currentBlock, expiryBlock)) {
            // Reservation expired — clear it and revert
            this._clearReservation(tokenId);
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_RESERVATION_EXPIRED);
        }

        // Verify BTC payment (fee is tiered based on buyer's NFT holdings)
        const priceSats: u256 = this._listingPrice.get(tokenId);
        const sellerHash: u256 = this._listingSellerHash.get(tokenId);
        const buyerFeeBps: u256 = this._getBuyerFeeBps(buyer);
        this._verifySellerPayment(sellerHash, priceSats);
        this._verifyFeePayment(priceSats, buyerFeeBps);

        // Transfer NFT from marketplace to buyer
        this._transferNFT(nft, buyer, tokenId);

        // Remove from active listings
        this._removeActiveListing(tokenId, idxPlusOne);

        // Clear all listing + reservation data
        this._clearListingData(tokenId);
        this._clearReservation(tokenId);

        this._releaseReentrancy();

        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    /**
     * Cancel a reservation.
     * - Reserver can cancel their own reservation at any time.
     * - Anyone can clear an expired reservation.
     */
    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public cancelReservation(calldata: Calldata): BytesWriter {
        this._acquireReentrancy();

        const tokenId: u256 = calldata.readU256();
        const sender: Address = Blockchain.tx.sender;

        // Check reservation exists
        const reserverU256: u256 = this._reservedBy.get(tokenId);
        if (reserverU256.isZero()) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NO_RESERVATION);
        }

        const senderU256: u256 = this._addressToU256(sender);
        const isReserver: bool = u256.eq(reserverU256, senderU256);

        if (!isReserver) {
            // Non-reserver can only cancel if expired
            const expiryBlock: u256 = this._reserveExpiry.get(tokenId);
            const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
            if (!u256.gt(currentBlock, expiryBlock)) {
                this._releaseReentrancy();
                throw new Revert(ERR_MARKET_NOT_RESERVER);
            }
        }

        this._clearReservation(tokenId);
        this._releaseReentrancy();

        const w: BytesWriter = new BytesWriter(1);
        w.writeBoolean(true);
        return w;
    }

    // -----------------------------------------------------------------------
    // View Methods
    // -----------------------------------------------------------------------

    @method({ name: 'tokenId', type: ABIDataTypes.UINT256 })
    @returns(
        { name: 'seller', type: ABIDataTypes.ADDRESS },
        { name: 'priceSats', type: ABIDataTypes.UINT256 },
        { name: 'active', type: ABIDataTypes.BOOL },
        { name: 'reservedBy', type: ABIDataTypes.UINT256 },
        { name: 'reserveExpiry', type: ABIDataTypes.UINT256 },
    )
    public getListing(calldata: Calldata): BytesWriter {
        const tokenId: u256 = calldata.readU256();
        const idxPlusOne: u256 = this._activeListingIndex.get(tokenId);
        const isActive: bool = !idxPlusOne.isZero();

        const sellerU256: u256 = this._listingSeller.get(tokenId);
        const priceSats: u256 = this._listingPrice.get(tokenId);

        // Return reservation info (0 if no reservation or expired)
        let reserverVal: u256 = u256.Zero;
        let expiryVal: u256 = u256.Zero;
        if (isActive) {
            const rawReserver: u256 = this._reservedBy.get(tokenId);
            if (!rawReserver.isZero()) {
                const rawExpiry: u256 = this._reserveExpiry.get(tokenId);
                const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
                if (!u256.gt(currentBlock, rawExpiry)) {
                    // Active reservation
                    reserverVal = rawReserver;
                    expiryVal = rawExpiry;
                }
                // Else expired — return zeros (auto-cleanup happens on next write)
            }
        }

        const w: BytesWriter = new BytesWriter(129); // 32 + 32 + 1 + 32 + 32
        w.writeU256(sellerU256);
        w.writeU256(priceSats);
        w.writeBoolean(isActive);
        w.writeU256(reserverVal);
        w.writeU256(expiryVal);
        return w;
    }

    @returns({ name: 'count', type: ABIDataTypes.UINT256 })
    public getActiveListingCount(_calldata: Calldata): BytesWriter {
        const w: BytesWriter = new BytesWriter(32);
        w.writeU256(this._activeListingCount.value);
        return w;
    }

    @method({ name: 'index', type: ABIDataTypes.UINT256 })
    @returns(
        { name: 'tokenId', type: ABIDataTypes.UINT256 },
        { name: 'seller', type: ABIDataTypes.ADDRESS },
        { name: 'priceSats', type: ABIDataTypes.UINT256 },
        { name: 'sellerAddrHi', type: ABIDataTypes.UINT256 },
        { name: 'sellerAddrLo', type: ABIDataTypes.UINT256 },
        { name: 'reservedBy', type: ABIDataTypes.UINT256 },
        { name: 'reserveExpiry', type: ABIDataTypes.UINT256 },
    )
    public getListingByIndex(calldata: Calldata): BytesWriter {
        const index: u256 = calldata.readU256();
        const count: u256 = this._activeListingCount.value;

        if (u256.ge(index, count)) {
            throw new Revert(ERR_MARKET_INDEX_OOB);
        }

        const tokenId: u256 = this._activeListingTokenIds.get(index);
        const sellerU256: u256 = this._listingSeller.get(tokenId);
        const priceSats: u256 = this._listingPrice.get(tokenId);
        const addrHi: u256 = this._sellerAddrBytesHi.get(tokenId);
        const addrLo: u256 = this._sellerAddrBytesLo.get(tokenId);

        // Reservation info (zeroed if none or expired)
        let reserverVal: u256 = u256.Zero;
        let expiryVal: u256 = u256.Zero;
        const rawReserver: u256 = this._reservedBy.get(tokenId);
        if (!rawReserver.isZero()) {
            const rawExpiry: u256 = this._reserveExpiry.get(tokenId);
            const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
            if (!u256.gt(currentBlock, rawExpiry)) {
                reserverVal = rawReserver;
                expiryVal = rawExpiry;
            }
        }

        const w: BytesWriter = new BytesWriter(224); // 7 × 32
        w.writeU256(tokenId);
        w.writeU256(sellerU256);
        w.writeU256(priceSats);
        w.writeU256(addrHi);
        w.writeU256(addrLo);
        w.writeU256(reserverVal);
        w.writeU256(expiryVal);
        return w;
    }

    @returns({ name: 'bps', type: ABIDataTypes.UINT256 })
    public getFeeBps(_calldata: Calldata): BytesWriter {
        const w: BytesWriter = new BytesWriter(32);
        w.writeU256(this._feeBps.value);
        return w;
    }

    /**
     * Returns the effective marketplace fee in BPS for a specific buyer,
     * based on their MiFrens NFT holdings. Magic number tiers:
     *   Wizard → 0% | King/Gnome/Elf → 1.11% | Knight/Apprentice → 3.33%
     *   Peasant → 4.20% | Non-holder → 6.9%
     */
    @method({ name: 'buyer', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'feeBps', type: ABIDataTypes.UINT256 })
    public getBuyerFeeBps(calldata: Calldata): BytesWriter {
        const buyer: Address = calldata.readAddress();
        const feeBps: u256 = this._getBuyerFeeBps(buyer);
        const w: BytesWriter = new BytesWriter(32);
        w.writeU256(feeBps);
        return w;
    }

    // -----------------------------------------------------------------------
    // Internal: Reservation Helpers
    // -----------------------------------------------------------------------

    /**
     * Check if a token has an active (non-expired) reservation.
     */
    private _hasActiveReservation(tokenId: u256): bool {
        const reserver: u256 = this._reservedBy.get(tokenId);
        if (reserver.isZero()) return false;

        const expiry: u256 = this._reserveExpiry.get(tokenId);
        const currentBlock: u256 = u256.fromU64(Blockchain.block.number);
        return !u256.gt(currentBlock, expiry);
    }

    /**
     * Clear reservation data for a token.
     */
    private _clearReservation(tokenId: u256): void {
        this._reservedBy.set(tokenId, u256.Zero);
        this._reserveExpiry.set(tokenId, u256.Zero);
    }

    /**
     * Clear all listing data for a token.
     */
    private _clearListingData(tokenId: u256): void {
        this._listingSeller.set(tokenId, u256.Zero);
        this._listingPrice.set(tokenId, u256.Zero);
        this._listingSellerHash.set(tokenId, u256.Zero);
        this._sellerAddrBytesHi.set(tokenId, u256.Zero);
        this._sellerAddrBytesLo.set(tokenId, u256.Zero);
    }

    // -----------------------------------------------------------------------
    // Internal: NFT Cross-Contract Calls
    // -----------------------------------------------------------------------

    private _verifyOwnership(nft: Address, tokenId: u256, owner: Address): void {
        const cw: BytesWriter = new BytesWriter(36);
        cw.writeSelector(encodeSelector('ownerOf(uint256)'));
        cw.writeU256(tokenId);

        const result: CallResult = Blockchain.call(nft, cw, true);
        if (!result.success) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NOT_NFT_OWNER);
        }

        const ownerResult: u256 = result.data.readU256();
        const ownerExpected: u256 = this._addressToU256(owner);
        if (!u256.eq(ownerResult, ownerExpected)) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_NOT_NFT_OWNER);
        }
    }

    private _verifyNotLocked(nft: Address, tokenId: u256): void {
        const cw: BytesWriter = new BytesWriter(36);
        cw.writeSelector(encodeSelector('isLocked(uint256)'));
        cw.writeU256(tokenId);

        const result: CallResult = Blockchain.call(nft, cw, true);
        if (result.success) {
            const locked: bool = result.data.readBoolean();
            if (locked) {
                this._releaseReentrancy();
                throw new Revert(ERR_MARKET_NFT_LOCKED);
            }
        }
    }

    private _transferNFT(nft: Address, to: Address, tokenId: u256): void {
        const cw: BytesWriter = new BytesWriter(68);
        cw.writeSelector(encodeSelector('transfer(address,uint256)'));
        cw.writeAddress(to);
        cw.writeU256(tokenId);

        const result: CallResult = Blockchain.call(nft, cw, true);
        if (!result.success) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_TRANSFER_FAILED);
        }
    }

    private _transferFromNFT(nft: Address, from: Address, to: Address, tokenId: u256): void {
        const cw: BytesWriter = new BytesWriter(100);
        cw.writeSelector(encodeSelector('transferFrom(address,address,uint256)'));
        cw.writeAddress(from);
        cw.writeAddress(to);
        cw.writeU256(tokenId);

        const result: CallResult = Blockchain.call(nft, cw, true);
        if (!result.success) {
            this._releaseReentrancy();
            throw new Revert(ERR_MARKET_TRANSFER_FAILED);
        }
    }

    // -----------------------------------------------------------------------
    // Internal: Fee Tier Resolution
    // -----------------------------------------------------------------------

    /**
     * Query MiFrens.getHolderTaxRate(buyer) and map to marketplace fee tier.
     * Falls back to the stored base fee (690 BPS) if NFT contract is not set
     * or the cross-contract call fails.
     */
    private _getBuyerFeeBps(buyer: Address): u256 {
        const nft: Address = this._nftContract.value;
        if (nft.equals(Address.zero())) {
            return this._feeBps.value;
        }

        const cw: BytesWriter = new BytesWriter(36);
        cw.writeSelector(this.GET_HOLDER_TAX_RATE_SELECTOR);
        cw.writeAddress(buyer);

        const result: CallResult = Blockchain.call(nft, cw, false);
        if (!result.success) {
            return this._feeBps.value;
        }

        const holderTaxRate: u64 = result.data.readU256().toU64();

        // Map holder tax rate → marketplace fee tier (magic numbers)
        if (holderTaxRate == 0) return u256.fromU64(MARKET_FEE_WIZARD);   // 0%
        if (holderTaxRate <= 50) return u256.fromU64(MARKET_FEE_NOBLE);   // 1.11%
        if (holderTaxRate <= 100) return u256.fromU64(MARKET_FEE_COMMON); // 3.33%
        if (holderTaxRate <= 200) return u256.fromU64(MARKET_FEE_PEASANT);// 6.66%
        return this._feeBps.value;                                         // 6.9%
    }

    // -----------------------------------------------------------------------
    // Internal: Payment Verification
    // -----------------------------------------------------------------------

    private _verifySellerPayment(sellerAddrHash: u256, priceSats: u256): void {
        const requiredSats: u64 = priceSats.toU64();
        const outputs = Blockchain.tx.outputs;

        for (let i: i32 = 0; i < outputs.length; i++) {
            const output = outputs[i];
            if (output.value < requiredSats) continue;

            if (output.to !== null) {
                const toBytes: ArrayBuffer = String.UTF8.encode(output.to!);
                const toHash: Uint8Array = sha256(Uint8Array.wrap(toBytes));
                const toArr: u8[] = this._uint8ToU8Array(toHash);
                const toU256: u256 = u256.fromBytesBE(toArr);
                if (u256.eq(toU256, sellerAddrHash)) return;
            }

            const script: Uint8Array | null = output.scriptPublicKey;
            if (script !== null) {
                const scriptHash: Uint8Array = sha256(script);
                const scriptArr: u8[] = this._uint8ToU8Array(scriptHash);
                const scriptU256: u256 = u256.fromBytesBE(scriptArr);
                if (u256.eq(scriptU256, sellerAddrHash)) return;
            }
        }

        this._releaseReentrancy();
        throw new Revert(ERR_MARKET_PAYMENT_REQUIRED);
    }

    private _verifyFeePayment(priceSats: u256, feeBps: u256): void {
        if (feeBps.isZero()) return;

        const feeHashVal: u256 = this._feeRecipientHash.value;
        if (feeHashVal.isZero()) return;

        const feeSats: u256 = SafeMath.div(SafeMath.mul(priceSats, feeBps), BPS_PRECISION);
        if (feeSats.isZero()) return;

        const requiredSats: u64 = feeSats.toU64();
        const outputs = Blockchain.tx.outputs;

        for (let i: i32 = 0; i < outputs.length; i++) {
            const output = outputs[i];
            if (output.value < requiredSats) continue;

            if (output.to !== null) {
                const toBytes: ArrayBuffer = String.UTF8.encode(output.to!);
                const toHash: Uint8Array = sha256(Uint8Array.wrap(toBytes));
                const toArr: u8[] = this._uint8ToU8Array(toHash);
                const toU256: u256 = u256.fromBytesBE(toArr);
                if (u256.eq(toU256, feeHashVal)) return;
            }

            const script: Uint8Array | null = output.scriptPublicKey;
            if (script !== null) {
                const scriptHash: Uint8Array = sha256(script);
                const scriptArr: u8[] = this._uint8ToU8Array(scriptHash);
                const scriptU256: u256 = u256.fromBytesBE(scriptArr);
                if (u256.eq(scriptU256, feeHashVal)) return;
            }
        }

        this._releaseReentrancy();
        throw new Revert(ERR_MARKET_FEE_PAYMENT_REQUIRED);
    }

    // -----------------------------------------------------------------------
    // Internal: Active Listing Management
    // -----------------------------------------------------------------------

    private _removeActiveListing(tokenId: u256, idxPlusOne: u256): void {
        const idx: u256 = SafeMath.sub(idxPlusOne, u256.One);
        const count: u256 = this._activeListingCount.value;
        const lastIdx: u256 = SafeMath.sub(count, u256.One);

        if (!u256.eq(idx, lastIdx)) {
            const lastTokenId: u256 = this._activeListingTokenIds.get(lastIdx);
            this._activeListingTokenIds.set(idx, lastTokenId);
            this._activeListingIndex.set(lastTokenId, idxPlusOne);
        }

        this._activeListingTokenIds.set(lastIdx, u256.Zero);
        this._activeListingIndex.set(tokenId, u256.Zero);
        this._activeListingCount.value = lastIdx;
    }

    // -----------------------------------------------------------------------
    // Internal: Reentrancy Guard
    // -----------------------------------------------------------------------

    private _acquireReentrancy(): void {
        const current: u256 = this._reentrancyGuard.value;
        if (u256.eq(current, REENTRANCY_LOCKED)) {
            throw new Revert(ERR_MARKET_REENTRANT);
        }
        this._reentrancyGuard.value = REENTRANCY_LOCKED;
    }

    private _releaseReentrancy(): void {
        this._reentrancyGuard.value = REENTRANCY_UNLOCKED;
    }

    // -----------------------------------------------------------------------
    // Internal: Helpers
    // -----------------------------------------------------------------------

    private _addressToU256(addr: Address): u256 {
        const arr: u8[] = new Array<u8>(32);
        for (let i: i32 = 0; i < 32; i++) {
            arr[i] = addr[i];
        }
        return u256.fromBytesBE(arr);
    }

    private _uint8ToU8Array(data: Uint8Array): u8[] {
        const arr = new Array<u8>(data.length);
        for (let i: i32 = 0; i < data.length; i++) {
            arr[i] = data[i];
        }
        return arr;
    }
}
