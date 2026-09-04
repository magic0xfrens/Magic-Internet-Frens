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
} from '@btc-vision/btc-runtime/runtime';
import { CallResult } from '@btc-vision/btc-runtime/runtime/env/BlockchainEnvironment';
import {
    REENTRANCY_UNLOCKED,
    REENTRANCY_LOCKED,
    DEFAULT_SWAP_THRESHOLD,
} from '../lib/constants';
import {
    ERR_CAULDRON_TOKEN_REENTRANT,
    ERR_CAULDRON_TOKEN_ROUTER_ZERO,
    ERR_CAULDRON_TOKEN_WBTC_ZERO,
    ERR_CAULDRON_TOKEN_THRESHOLD_ZERO,
    ERR_CAULDRON_TOKEN_ALREADY_DEAD,
    ERR_CAULDRON_TOKEN_ZERO_NFT,
    ERR_CAULDRON_TOKEN_ZERO_FEE_RECIPIENT,
} from '../lib/errors';

/**
 * CauldronToken - An immortal, ever-reborning token
 *
 * Each generation has unique AI-generated metadata (name, symbol)
 * When volume dies, a new Cauldron token is summoned with the same liquidity
 *
 * Tiered Tax (resolved via MiFrens.getHolderTaxRate):
 *   Wizard   → 0%   | King/Gnome      → 0.5%
 *   Knight/Apprentice → 1% | Peasant → 2% | Non-holder → 3%
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
    private readonly _reservedTaxRatePointer: u16 = Blockchain.nextPointer; // formerly taxRatePointer — slot preserved for layout stability
    private readonly elderCirclePointer: u16 = Blockchain.nextPointer;
    private readonly reentrancyPointer: u16 = Blockchain.nextPointer;
    // Auto-swap storage pointers (appended after existing pointers)
    private readonly routerPointer: u16 = Blockchain.nextPointer;
    private readonly wbtcPointer: u16 = Blockchain.nextPointer;
    private readonly swapThresholdPointer: u16 = Blockchain.nextPointer;
    private readonly accumulatedTaxPointer: u16 = Blockchain.nextPointer;
    private readonly isSwappingPointer: u16 = Blockchain.nextPointer;

    // Storage
    private _generation!: StoredU256;
    private _isAlive!: StoredU256;
    private _birthBlock!: StoredU256;
    private _deathBlock!: StoredU256;
    private _nftContract!: StoredAddress;
    private _feeRecipient!: StoredAddress;
    private _elderCircle!: StoredAddress;
    private _reentrancyGuard!: StoredU256;
    // Auto-swap storage
    private _router!: StoredAddress;
    private _wbtc!: StoredAddress;
    private _swapThreshold!: StoredU256;
    private _accumulatedTax!: StoredU256;
    private _isSwapping!: StoredU256;

    // Selectors for cross-contract router call
    private readonly SWAP_SELECTOR: u32 = encodeSelector(
        'swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)',
    );

    // Admin method selectors
    private readonly setRouterSelector: Selector = encodeSelector('setRouter(address)');
    private readonly setWbtcSelector: Selector = encodeSelector('setWbtc(address)');
    private readonly setSwapThresholdSelector: Selector = encodeSelector('setSwapThreshold(uint256)');
    private readonly getAccumulatedTaxSelector: Selector = encodeSelector('getAccumulatedTax()');

    // Pre-computed selectors for cross-contract calls (LOW-001, LOW-002)
    private readonly NOTIFY_TRANSFER_SELECTOR: u32 = encodeSelector('notifyTransfer(address)');
    private readonly GET_HOLDER_TAX_RATE_SELECTOR: u32 = encodeSelector('getHolderTaxRate(address)');

    public constructor() {
        super();
        this._generation = new StoredU256(this.generationPointer, new Uint8Array(0));
        this._isAlive = new StoredU256(this.isAlivePointer, new Uint8Array(0));
        this._birthBlock = new StoredU256(this.birthBlockPointer, new Uint8Array(0));
        this._deathBlock = new StoredU256(this.deathBlockPointer, new Uint8Array(0));
        this._nftContract = new StoredAddress(this.nftContractPointer);
        this._feeRecipient = new StoredAddress(this.feeRecipientPointer);
        this._elderCircle = new StoredAddress(this.elderCirclePointer);
        this._reentrancyGuard = new StoredU256(this.reentrancyPointer, new Uint8Array(0));
        // Auto-swap storage
        this._router = new StoredAddress(this.routerPointer);
        this._wbtc = new StoredAddress(this.wbtcPointer);
        this._swapThreshold = new StoredU256(this.swapThresholdPointer, new Uint8Array(0));
        this._accumulatedTax = new StoredU256(this.accumulatedTaxPointer, new Uint8Array(0));
        this._isSwapping = new StoredU256(this.isSwappingPointer, new Uint8Array(0));
    }

    public override onDeployment(calldata: Calldata): void {
        const generation: u256 = calldata.readU256();
        const name: string = calldata.readStringWithLength();
        const symbol: string = calldata.readStringWithLength();
        const nftContract: Address = calldata.readAddress();
        const feeRecipient: Address = calldata.readAddress();

        // LOW-003: zero-address validation
        if (nftContract.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_TOKEN_ZERO_NFT);
        }
        if (feeRecipient.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_TOKEN_ZERO_FEE_RECIPIENT);
        }

        this._generation.value = generation;
        this._birthBlock.value = u256.fromU64(Blockchain.block.number);
        this._isAlive.value = u256.One;
        this._nftContract.value = nftContract;
        this._feeRecipient.value = feeRecipient;

        // HIGH-003: initialize reentrancy guard to UNLOCKED
        this._reentrancyGuard.value = REENTRANCY_UNLOCKED;

        this._swapThreshold.value = DEFAULT_SWAP_THRESHOLD;

        this.instantiate(new OP20InitParameters(
            u256.Max,
            18,
            name,
            symbol,
        ));
    }

    // -----------------------------------------------------------------------
    // Transfer Override: Tax logic applied at _transfer level
    // This catches both transfer() and transferFrom() automatically
    // -----------------------------------------------------------------------

    protected _transfer(from: Address, to: Address, amount: u256): void {
        // When a swap is in progress the router calls back into us via
        // transferFrom → _transfer. Allow that as a plain transfer with no
        // tax, no recursion, no reentrancy check (we are already locked).
        if (u256.eq(this._isSwapping.value, u256.One)) {
            super._transfer(from, to, amount);
            return;
        }

        // H-1 fix: reentrancy guard on _transfer (cross-contract calls below)
        if (u256.eq(this._reentrancyGuard.value, REENTRANCY_LOCKED)) {
            throw new Revert(ERR_CAULDRON_TOKEN_REENTRANT);
        }
        this._reentrancyGuard.value = REENTRANCY_LOCKED;

        // Freeze all transfers once dead — balances become the immutable snapshot
        if (u256.eq(this._isAlive.value, u256.Zero)) {
            throw new Revert('Token is dead — balances frozen');
        }

        // H-2 fix: skip tax entirely if feeRecipient is dead/unset
        if (this._feeRecipient.isDead()) {
            super._transfer(from, to, amount);
        } else {
            const taxRate: u256 = this._getHolderTaxRate(from);

            if (u256.eq(taxRate, u256.Zero)) {
                super._transfer(from, to, amount);
            } else {
                const taxAmount: u256 = SafeMath.div(
                    SafeMath.mul(amount, taxRate),
                    u256.fromU64(10000),
                );
                const afterTax: u256 = SafeMath.sub(amount, taxAmount);

                super._transfer(from, to, afterTax);

                // Send tax to the contract itself for accumulation
                const contractAddr: Address = Blockchain.contractAddress;
                super._transfer(from, contractAddr, taxAmount);

                // Track accumulated tax
                this._accumulatedTax.value = SafeMath.add(
                    this._accumulatedTax.value,
                    taxAmount,
                );

                // Attempt auto-swap if threshold is met
                this._trySwapTax();
            }
        }

        // Notify ElderCircle of outgoing transfer (non-failing)
        this._notifyElderCircle(from);

        this._reentrancyGuard.value = REENTRANCY_UNLOCKED;
    }

    // -----------------------------------------------------------------------
    // Custom Methods (decorated for opnet-transform routing)
    // -----------------------------------------------------------------------

    @method()
    @returns({ name: 'generation', type: ABIDataTypes.UINT256 })
    public getGeneration(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._generation.value);
        return writer;
    }

    @method({ name: 'to', type: ABIDataTypes.ADDRESS }, { name: 'amount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public mint(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const to: Address = calldata.readAddress();
        const amount: u256 = calldata.readU256();
        this._mint(to, amount);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'alive', type: ABIDataTypes.BOOL })
    public isAlive(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(u256.eq(this._isAlive.value, u256.One));
        return writer;
    }

    @method({ name: 'elderCircle', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setElderCircle(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const elderCircle: Address = calldata.readAddress();
        this._elderCircle.value = elderCircle;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public markDead(_calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        // MEDIUM-003: prevent double-death (protects deathBlock from corruption)
        if (u256.eq(this._isAlive.value, u256.Zero)) {
            throw new Revert(ERR_CAULDRON_TOKEN_ALREADY_DEAD);
        }

        this._isAlive.value = u256.Zero;
        this._deathBlock.value = u256.fromU64(Blockchain.block.number);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // callMethod Router -- extend OP20's built-in methods
    // -----------------------------------------------------------------------

    public callMethod(calldata: Calldata): BytesWriter {
        const selector: Selector = calldata.readSelector();

        switch (selector) {
            case this.setRouterSelector:
                return this.setRouter(calldata);
            case this.setWbtcSelector:
                return this.setWbtc(calldata);
            case this.setSwapThresholdSelector:
                return this.setSwapThreshold(calldata);
            case this.getAccumulatedTaxSelector:
                return this.getAccumulatedTax(calldata);
            default:
                return super.callMethod(calldata);
        }
    }

    // -----------------------------------------------------------------------
    // Admin Methods (deployer-only)
    // -----------------------------------------------------------------------

    @method({ name: 'router', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setRouter(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const router: Address = calldata.readAddress();
        if (router.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_TOKEN_ROUTER_ZERO);
        }
        this._router.value = router;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'wbtc', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setWbtc(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const wbtc: Address = calldata.readAddress();
        if (wbtc.equals(Address.zero())) {
            throw new Revert(ERR_CAULDRON_TOKEN_WBTC_ZERO);
        }
        this._wbtc.value = wbtc;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'threshold', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setSwapThreshold(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const threshold: u256 = calldata.readU256();
        if (u256.eq(threshold, u256.Zero)) {
            throw new Revert(ERR_CAULDRON_TOKEN_THRESHOLD_ZERO);
        }
        this._swapThreshold.value = threshold;
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method()
    @returns({ name: 'accumulated', type: ABIDataTypes.UINT256 })
    public getAccumulatedTax(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._accumulatedTax.value);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Auto-Swap Logic
    // -----------------------------------------------------------------------

    /**
     * Attempt to swap accumulated tax tokens to WBTC via MotoSwap Router.
     * Only triggers when:
     *   - router and WBTC addresses are configured (non-zero)
     *   - accumulated tax >= swap threshold
     * Uses _isSwapping flag to allow the router's callback transfer to bypass
     * tax + reentrancy logic (see _transfer above).
     */
    private _trySwapTax(): void {
        // Guard: skip if router or WBTC not configured
        if (this._router.isDead() || this._wbtc.isDead()) {
            return;
        }

        const accumulated: u256 = this._accumulatedTax.value;
        const threshold: u256 = this._swapThreshold.value;

        // Not enough accumulated or threshold unset
        if (u256.lt(accumulated, threshold) || u256.eq(threshold, u256.Zero)) {
            return;
        }

        const routerAddr: Address = this._router.value;
        const wbtcAddr: Address = this._wbtc.value;
        const contractAddr: Address = Blockchain.contractAddress;
        const treasury: Address = this._feeRecipient.value;

        // Set swapping flag — allows router callback transfers to bypass tax
        this._isSwapping.value = u256.One;

        // MEDIUM-001: Reset then set allowance to prevent accumulation
        const prevAllowance: u256 = this._allowance(contractAddr, routerAddr);
        if (!prevAllowance.isZero()) {
            this._decreaseAllowance(contractAddr, routerAddr, prevAllowance);
        }
        this._increaseAllowance(contractAddr, routerAddr, accumulated);

        // Build swap calldata:
        // swapExactTokensForTokensSupportingFeeOnTransferTokens(
        //   uint256 amountIn,
        //   uint256 amountOutMin,
        //   address[] path,
        //   address to,
        //   uint256 deadline
        // )
        const path: Address[] = [contractAddr, wbtcAddr];
        // 4 (selector) + 32*3 (amountIn, amountOutMin, deadline) + 32 (to addr)
        // + 2 (array length prefix) + 32*2 (two addresses in path)
        const writer: BytesWriter = new BytesWriter(4 + 32 + 32 + 2 + 64 + 32 + 32);
        writer.writeSelector(this.SWAP_SELECTOR);
        writer.writeU256(accumulated);       // amountIn
        writer.writeU256(u256.Zero);         // amountOutMin: same-block execution on OPNet
        writer.writeAddressArray(path);      // path: [this token, WBTC]
        writer.writeAddress(treasury);       // to: fee recipient (treasury)
        writer.writeU256(u256.Max);          // deadline: no expiry (same-block execution)

        // Non-failing call — if swap reverts, tax stays accumulated for next try
        const result: CallResult = Blockchain.call(routerAddr, writer, false);

        if (result.success) {
            // Reset accumulated tax on successful swap
            this._accumulatedTax.value = u256.Zero;
        } else {
            // MEDIUM-001: Reset allowance on failed swap to prevent accumulation
            const remaining: u256 = this._allowance(contractAddr, routerAddr);
            if (!remaining.isZero()) {
                this._decreaseAllowance(contractAddr, routerAddr, remaining);
            }
        }

        // Clear swapping flag
        this._isSwapping.value = u256.Zero;
    }

    // -----------------------------------------------------------------------
    // Internal Helpers
    // -----------------------------------------------------------------------

    private _notifyElderCircle(from: Address): void {
        if (this._elderCircle.isDead()) {
            return;
        }

        const ec: Address = this._elderCircle.value;
        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(this.NOTIFY_TRANSFER_SELECTOR);
        writer.writeAddress(from);

        // Non-failing: if ElderCircle reverts, the transfer still succeeds
        Blockchain.call(ec, writer, false);
    }

    /**
     * Query MiFrens.getHolderTaxRate(address) for the tiered tax rate in BPS.
     * Returns 300 (3%) if the NFT contract is not set or the call fails.
     */
    private _getHolderTaxRate(holder: Address): u256 {
        if (this._nftContract.isDead()) {
            return u256.fromU64(300); // 3% default when no NFT contract
        }

        const nftContract: Address = this._nftContract.value;

        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(this.GET_HOLDER_TAX_RATE_SELECTOR);
        writer.writeAddress(holder);

        const result: CallResult = Blockchain.call(nftContract, writer, false);
        if (!result.success) {
            return u256.fromU64(300); // 3% fallback on call failure
        }

        return result.data.readU256();
    }
}
