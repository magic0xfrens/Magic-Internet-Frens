import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    encodeSelector,
    OP20,
    OP20InitParameters,
    Revert,
    Selector,
    StoredU256,
    StoredAddress,
    SafeMath,
    ABIDataTypes,
} from '@btc-vision/btc-runtime/runtime';

/**
 * CauldronToken - An immortal, ever-reborning token summoned by 777 Magic Internet Frens
 *
 * When the 777 Magic Internet Wizard Frens gather and cast their spell through the Cauldron,
 * an eternal creature is born. This creature lives, dies, and is reborn infinitely.
 *
 * Tax Structure:
 * - Magic Fren NFT holders: 0% tax (blessed by the spell)
 * - Non-holders: 3% tax (tribute to the Magic Internet)
 */
@final
export class CauldronToken extends OP20 {
    // Storage pointers
    private readonly generationPointer: u16 = Blockchain.nextPointer;
    private readonly isAlivePointer: u16 = Blockchain.nextPointer;
    private readonly birthBlockPointer: u16 = Blockchain.nextPointer;
    private readonly deathBlockPointer: u16 = Blockchain.nextPointer;
    private readonly nftContractPointer: u16 = Blockchain.nextPointer;
    private readonly feeRecipientPointer: u16 = Blockchain.nextPointer;
    private readonly taxRatePointer: u16 = Blockchain.nextPointer;

    // Storage
    private readonly _generation: StoredU256;
    private readonly _isAlive: StoredU256;
    private readonly _birthBlock: StoredU256;
    private readonly _deathBlock: StoredU256;
    private readonly _nftContract: StoredAddress; // MiFrens NFT for spell casters
    private readonly _feeRecipient: StoredAddress; // Magic Internet treasury
    private readonly _taxRate: StoredU256; // 300 BPS = 3%

    // Selectors
    private readonly getGenerationSelector: Selector = encodeSelector('getGeneration()');
    private readonly isAliveSelector: Selector = encodeSelector('isAlive()');
    private readonly markDeadSelector: Selector = encodeSelector('markDead()');

    public constructor() {
        super();
        this._generation = new StoredU256(this.generationPointer, u256.Zero);
        this._isAlive = new StoredU256(this.isAlivePointer, u256.One);
        this._birthBlock = new StoredU256(this.birthBlockPointer, u256.Zero);
        this._deathBlock = new StoredU256(this.deathBlockPointer, u256.Zero);
        this._nftContract = new StoredAddress(this.nftContractPointer);
        this._feeRecipient = new StoredAddress(this.feeRecipientPointer);
        this._taxRate = new StoredU256(this.taxRatePointer, u256.fromU64(300)); // 3% default
    }

    public override onDeployment(calldata: Calldata): void {
        // Read deployment params: generation, name, symbol, nftContract, feeRecipient
        const generation: u256 = calldata.readU256();
        const name: string = calldata.readStringWithLength();
        const symbol: string = calldata.readStringWithLength();
        const nftContract: Address = calldata.readAddress();
        const feeRecipient: Address = calldata.readAddress();

        this._generation.set(generation);
        this._birthBlock.set(u256.fromU64(Blockchain.block.number));
        this._isAlive.set(u256.One);
        this._nftContract.set(nftContract);
        this._feeRecipient.set(feeRecipient);

        // Initialize as OP20 with unlimited supply, 18 decimals
        this.instantiate(new OP20InitParameters(
            u256.Max,  // Unlimited supply - eternal creature
            18,
            name,
            symbol,
        ));
    }

    public override callMethod(calldata: Calldata): BytesWriter {
        const selector: Selector = calldata.readSelector();

        switch (selector) {
            case this.getGenerationSelector:
                return this._getGeneration(calldata);
            case this.isAliveSelector:
                return this._getIsAlive(calldata);
            case this.markDeadSelector:
                return this._markDead(calldata);
            default:
                return super.callMethod(calldata);
        }
    }

    // TAX SYSTEM: 0% for spell casters (NFT holders), 3% for others
    public override transfer(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        const to: Address = calldata.readAddress();
        const amount: u256 = calldata.readU256();

        this._transferWithTax(sender, to, amount);

        return new BytesWriter(0);
    }

    public override transferFrom(calldata: Calldata): BytesWriter {
        const from: Address = calldata.readAddress();
        const to: Address = calldata.readAddress();
        const amount: u256 = calldata.readU256();

        // Check allowance
        const allowance: u256 = this._allowance(from, Blockchain.tx.sender);
        if (u256.lt(allowance, amount)) {
            throw new Revert('Insufficient allowance');
        }

        this._transferWithTax(from, to, amount);

        // Decrease allowance
        this._approve(from, Blockchain.tx.sender, SafeMath.sub(allowance, amount));

        return new BytesWriter(0);
    }

    /**
     * Transfer with spell caster privileges:
     * - Spell casters (NFT holders): 0% tax (blessed by the Cauldron)
     * - Others: 3% tax (tribute to Magic Internet treasury)
     */
    private _transferWithTax(from: Address, to: Address, amount: u256): void {
        const isSpellCaster: bool = this._checkSpellCaster(from);

        if (isSpellCaster) {
            // 0% tax for those who cast the spell
            this._transfer(from, to, amount);
        } else {
            // 3% tax for non-spell-casters
            const taxRate: u256 = this._taxRate.get();
            const taxAmount: u256 = SafeMath.div(
                SafeMath.mul(amount, taxRate),
                u256.fromU64(10000), // BPS
            );
            const afterTax: u256 = SafeMath.sub(amount, taxAmount);

            // Transfer after-tax amount to recipient
            this._transfer(from, to, afterTax);

            // Transfer tax to Magic Internet treasury
            const feeRecipient: Address = this._feeRecipient.get();
            if (!feeRecipient.equals(Address.dead())) {
                this._transfer(from, feeRecipient, taxAmount);
            }
        }
    }

    /**
     * Check if address is a spell caster (holds Magic Fren NFT)
     */
    private _checkSpellCaster(holder: Address): bool {
        const nftContract: Address = this._nftContract.get();
        if (nftContract.equals(Address.dead())) {
            return false; // No spell casters yet
        }

        // Call NFT.balanceOf(holder)
        const calldata: BytesWriter = new BytesWriter(32);
        calldata.writeAddress(holder);

        const response = Blockchain.call(nftContract, calldata.getBuffer(), u256.Zero);
        const reader = new Calldata(response);
        const balance: u256 = reader.readU256();

        return u256.gt(balance, u256.Zero); // Is spell caster if holds NFT
    }

    @method()
    @returns({ name: 'generation', type: ABIDataTypes.UINT256 })
    private _getGeneration(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._generation.get());
        return writer;
    }

    @method()
    @returns({ name: 'alive', type: ABIDataTypes.BOOL })
    private _getIsAlive(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(u256.eq(this._isAlive.get(), u256.One));
        return writer;
    }

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _markDead(_calldata: Calldata): BytesWriter {
        // Only registry can mark as dead
        this.onlyDeployer(Blockchain.tx.sender);

        this._isAlive.set(u256.Zero);
        this._deathBlock.set(u256.fromU64(Blockchain.block.number));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }
}
