import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    encodeSelector,
    OP20,
    Revert,
    SafeMath,
    StoredU256,
    StoredU256Map,
} from '@btc-vision/btc-runtime/runtime';

/**
 * MiFrenToken - OP20 token with integrated NFT minting/burning on swap
 *
 * Mechanics:
 * - Buy tokens → mint NFT
 * - Sell tokens → burn NFT (unless saved)
 * - Pay fee → save NFT from burning
 */

@final
export class MiFrenToken extends OP20 {
    // Storage pointers
    private readonly nftContract: StoredAddress;
    private readonly saveFeeBasisPoints: StoredU256; // Fee to save NFT (in basis points, e.g., 1000 = 10%)
    private readonly feeRecipient: StoredAddress;

    // Track which addresses have saved their NFTs
    private readonly savedNFTs: StoredU256Map; // address => tokenId (0 if not saved)

    // Track pending mints (to handle async NFT minting)
    private readonly pendingMints: StoredU256Map; // address => pending count

    constructor() {
        super('Magic Internet Frens', 'MIFREN', u256.fromU32(18), u256.Zero);

        this.nftContract = new StoredAddress(
            this.createPointer('nft_contract'),
            Address.dead(),
        );

        this.saveFeeBasisPoints = new StoredU256(
            this.createPointer('save_fee_bp'),
            u256.fromU32(1000), // Default: 10% fee to save NFT
        );

        this.feeRecipient = new StoredAddress(
            this.createPointer('fee_recipient'),
            Address.dead(),
        );

        this.savedNFTs = new StoredU256Map(this.createPointer('saved_nfts'));
        this.pendingMints = new StoredU256Map(this.createPointer('pending_mints'));
    }

    // ========================
    // Admin Functions
    // ========================

    public setNFTContract(nftContractAddress: Address): void {
        this.onlyOwner(Blockchain.tx.sender);
        this.nftContract.set(nftContractAddress);
    }

    public setSaveFee(basisPoints: u256): void {
        this.onlyOwner(Blockchain.tx.sender);
        if (basisPoints > u256.fromU32(10000)) {
            throw new Revert('Fee cannot exceed 100%');
        }
        this.saveFeeBasisPoints.set(basisPoints);
    }

    public setFeeRecipient(recipient: Address): void {
        this.onlyOwner(Blockchain.tx.sender);
        this.feeRecipient.set(recipient);
    }

    // ========================
    // Core Token Logic with NFT Integration
    // ========================

    /**
     * Override transfer to handle NFT mint/burn logic
     * This gets called on DEX swaps
     */
    public override _transfer(from: Address, to: Address, amount: u256): void {
        const isFromDEX = this._isDEXAddress(from);
        const isToDEX = this._isDEXAddress(to);

        // BUY: User buying tokens from DEX → Mint NFT
        if (isFromDEX && !isToDEX) {
            this._handleBuy(to, amount);
        }

        // SELL: User selling tokens to DEX → Burn NFT (unless saved)
        if (!isFromDEX && isToDEX) {
            this._handleSell(from, amount);
        }

        // Execute the actual token transfer
        super._transfer(from, to, amount);
    }

    private _handleBuy(buyer: Address, amount: u256): void {
        // Mint NFT for buyer
        const nftAddr = this.nftContract.get();
        if (nftAddr.equals(Address.dead())) {
            return; // NFT contract not set yet
        }

        // Increment pending mints
        const currentPending = this.pendingMints.get(buyer);
        this.pendingMints.set(buyer, SafeMath.add(currentPending, u256.One));

        // Call NFT contract to mint
        this._mintNFT(nftAddr, buyer);
    }

    private _handleSell(seller: Address, amount: u256): void {
        // Check if user has saved their NFT
        const savedTokenId = this.savedNFTs.get(seller);
        if (!savedTokenId.isZero()) {
            // NFT is saved, don't burn
            return;
        }

        // Burn NFT
        const nftAddr = this.nftContract.get();
        if (nftAddr.equals(Address.dead())) {
            return;
        }

        this._burnNFT(nftAddr, seller);
    }

    // ========================
    // NFT Save Mechanism
    // ========================

    /**
     * Allow user to pay fee to save their NFT from being burned on sell
     * @param tokenId - The NFT token ID to save
     */
    public saveNFT(tokenId: u256): void {
        const sender = Blockchain.tx.sender;

        // Verify user owns this NFT
        if (!this._ownsNFT(sender, tokenId)) {
            throw new Revert('You do not own this NFT');
        }

        // Calculate save fee
        const balance = this.balanceOf(sender);
        const feeBP = this.saveFeeBasisPoints.get();
        const feeAmount = SafeMath.div(
            SafeMath.mul(balance, feeBP),
            u256.fromU32(10000)
        );

        // Charge fee
        const recipient = this.feeRecipient.get();
        if (!recipient.equals(Address.dead())) {
            this._transfer(sender, recipient, feeAmount);
        }

        // Mark NFT as saved
        this.savedNFTs.set(sender, tokenId);

        // Emit event
        this.createEvent(
            'NFTSaved',
            [sender.toBytes(), tokenId.toBytes()],
        );
    }

    /**
     * Unsave NFT (make it burnable again on sell)
     */
    public unsaveNFT(): void {
        const sender = Blockchain.tx.sender;
        this.savedNFTs.set(sender, u256.Zero);

        this.createEvent(
            'NFTUnsaved',
            [sender.toBytes()],
        );
    }

    // ========================
    // Helper Functions
    // ========================

    private _isDEXAddress(addr: Address): bool {
        // TODO: Implement DEX pool detection
        // For now, check against known MotoSwap/NativeSwap addresses
        // This would be configured by admin
        return false;
    }

    private _mintNFT(nftContract: Address, recipient: Address): void {
        // Call NFT contract's mint function
        const selector = encodeSelector('mint');
        const calldata = new BytesWriter(selector.length + 20);
        calldata.writeSelector(selector);
        calldata.writeAddress(recipient);

        Blockchain.call(nftContract, calldata.getBuffer());
    }

    private _burnNFT(nftContract: Address, owner: Address): void {
        // Call NFT contract's burn function
        const selector = encodeSelector('burn');
        const calldata = new BytesWriter(selector.length + 20);
        calldata.writeSelector(selector);
        calldata.writeAddress(owner);

        Blockchain.call(nftContract, calldata.getBuffer());
    }

    private _ownsNFT(owner: Address, tokenId: u256): bool {
        // Query NFT contract for ownership
        const nftContract = this.nftContract.get();
        const selector = encodeSelector('ownerOf');
        const calldata = new BytesWriter(selector.length + 32);
        calldata.writeSelector(selector);
        calldata.writeU256(tokenId);

        const result = Blockchain.call(nftContract, calldata.getBuffer());
        // Parse result and check if matches owner
        // TODO: Implement proper result parsing
        return true;
    }

    // ========================
    // View Functions
    // ========================

    public getSaveFee(): u256 {
        return this.saveFeeBasisPoints.get();
    }

    public isNFTSaved(user: Address): u256 {
        return this.savedNFTs.get(user);
    }

    public getPendingMints(user: Address): u256 {
        return this.pendingMints.get(user);
    }
}
