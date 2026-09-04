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
    SafeMath,
    Selector,
    StoredU256,
    StoredU64,
    AddressMemoryMap,
} from '@btc-vision/btc-runtime/runtime';

import { MAX_FREN_SUPPLY, UNSTAKE_TIMELOCK_BLOCKS } from '../lib/constants';
import {
    ERR_FREN_NOT_OWNER,
    ERR_FREN_EXCEEDS_MAX,
    ERR_FREN_ZERO_AMOUNT,
    ERR_FREN_INSUFFICIENT,
    ERR_FREN_ZERO_SFREN,
    ERR_FREN_SFREN_INSUFFICIENT,
    ERR_FREN_NO_STAKERS,
    ERR_FREN_NOT_DISTRIBUTOR,
    ERR_FREN_ZERO_ADDR,
    ERR_FREN_NO_PENDING,
    ERR_FREN_TIMELOCK,
    ERR_FREN_PENDING_EXISTS,
    ERR_FREN_NOT_MINTER,
    ERR_FREN_NOT_A_MINTER,
} from '../lib/errors';
import {
    StakedEvent,
    UnstakeInitiatedEvent,
    UnstakeClaimedEvent,
    RewardDistributedEvent,
} from '../events/FRENEvents';

/**
 * FRENToken -- $FREN Governance + Staking Token (OP_20) for Magic Internet Frens.
 *
 * Name: "FREN"
 * Symbol: "FREN"
 * Decimals: 18
 * Max Supply: 1,000,000,000 (1 billion with 18 decimals = 1e27)
 *
 * Implements sFREN staking using the xSUSHI model:
 *   - stake(amount): lock FREN, receive sFREN proportional to exchange rate
 *   - unstake(amount): burn sFREN, start 24h timelock
 *   - claimUnstake(): claim matured FREN
 *   - distributeReward(amount): Cauldron pushes FREN into staking pool
 *
 * Exchange rate: totalStakedFREN / totalSFRENSupply
 * Single pending unstake per address (OP_NET storage limitation).
 */
@final
export class FRENToken extends OP20 {
    // -----------------------------------------------------------------------
    // Storage Pointers (OP20 uses 0-6, custom start at 7+)
    // -----------------------------------------------------------------------

    private readonly totalStakedPointer: u16 = Blockchain.nextPointer;
    private readonly totalSFRENPointer: u16 = Blockchain.nextPointer;
    private readonly sfrenBalancesPointer: u16 = Blockchain.nextPointer;
    private readonly distributorsPointer: u16 = Blockchain.nextPointer;
    private readonly pendingAmountsPointer: u16 = Blockchain.nextPointer;
    private readonly pendingTimestampsPointer: u16 = Blockchain.nextPointer;
    private readonly mintersPointer: u16 = Blockchain.nextPointer;

    // -----------------------------------------------------------------------
    // Storage Instances
    // -----------------------------------------------------------------------

    /** Total FREN tokens locked in the staking pool */
    private readonly _totalStakedFREN: StoredU256;

    /** Total sFREN receipt tokens in circulation */
    private readonly _totalSFRENSupply: StoredU256;

    /** sFREN balance per address: address -> u256 balance */
    private readonly _sfrenBalances: AddressMemoryMap;

    /** Reward distributor whitelist: address -> u256.One if whitelisted */
    private readonly _distributors: AddressMemoryMap;

    /** Pending unstake amounts per address: address -> u256 FREN amount */
    private readonly _pendingAmounts: AddressMemoryMap;

    /** Pending unstake timestamps per address: address -> u256(timestamp) */
    private readonly _pendingTimestamps: AddressMemoryMap;

    /** Minter whitelist: address -> u256.One if whitelisted */
    private readonly _minters: AddressMemoryMap;

    // -----------------------------------------------------------------------
    // Selectors for custom staking methods
    // -----------------------------------------------------------------------

    private readonly stakeSelector: Selector = encodeSelector('stake(uint256)');
    private readonly unstakeSelector: Selector = encodeSelector('unstake(uint256)');
    private readonly claimUnstakeSelector: Selector = encodeSelector('claimUnstake()');
    private readonly distributeRewardSelector: Selector = encodeSelector('distributeReward(uint256)');
    private readonly sfrenBalanceOfSelector: Selector = encodeSelector('sfrenBalanceOf(address)');
    private readonly sfrenTotalSupplySelector: Selector = encodeSelector('sfrenTotalSupply()');
    private readonly totalStakedSelector: Selector = encodeSelector('totalStakedFREN()');
    private readonly exchangeRateSelector: Selector = encodeSelector('getFRENPerSFREN()');
    private readonly addDistributorSelector: Selector = encodeSelector('addRewardDistributor(address)');
    private readonly removeDistributorSelector: Selector = encodeSelector('removeRewardDistributor(address)');
    private readonly isDistributorSelector: Selector = encodeSelector('isRewardDistributor(address)');
    private readonly mintFRENSelector: Selector = encodeSelector('mintFREN(address,uint256)');
    private readonly pendingUnstakeSelector: Selector = encodeSelector('getPendingUnstake(address)');
    private readonly addMinterSelector: Selector = encodeSelector('addMinter(address)');
    private readonly removeMinterSelector: Selector = encodeSelector('removeMinter(address)');
    private readonly isMinterSelector: Selector = encodeSelector('isMinter(address)');

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    public constructor() {
        super();

        this._totalStakedFREN = new StoredU256(this.totalStakedPointer, u256.Zero);
        this._totalSFRENSupply = new StoredU256(this.totalSFRENPointer, u256.Zero);
        this._sfrenBalances = new AddressMemoryMap(this.sfrenBalancesPointer);
        this._distributors = new AddressMemoryMap(this.distributorsPointer);
        this._pendingAmounts = new AddressMemoryMap(this.pendingAmountsPointer);
        this._pendingTimestamps = new AddressMemoryMap(this.pendingTimestampsPointer);
        this._minters = new AddressMemoryMap(this.mintersPointer);
    }

    // -----------------------------------------------------------------------
    // Deployment
    // -----------------------------------------------------------------------

    public override onDeployment(_calldata: Calldata): void {
        this.instantiate(new OP20InitParameters(
            MAX_FREN_SUPPLY, // maxSupply: 1 billion * 10^18
            18,              // decimals
            'FREN',          // name
            'FREN',          // symbol
        ));
    }

    // -----------------------------------------------------------------------
    // callMethod Router
    // -----------------------------------------------------------------------

    public override callMethod(calldata: Calldata): BytesWriter {
        const selector: Selector = calldata.readSelector();

        switch (selector) {
            case this.stakeSelector:
                return this._stake(calldata);
            case this.unstakeSelector:
                return this._unstake(calldata);
            case this.claimUnstakeSelector:
                return this._claimUnstake(calldata);
            case this.distributeRewardSelector:
                return this._distributeReward(calldata);
            case this.sfrenBalanceOfSelector:
                return this._sfrenBalanceOf(calldata);
            case this.sfrenTotalSupplySelector:
                return this._sfrenTotalSupply(calldata);
            case this.totalStakedSelector:
                return this._totalStakedView(calldata);
            case this.exchangeRateSelector:
                return this._exchangeRate(calldata);
            case this.addDistributorSelector:
                return this._addDistributor(calldata);
            case this.removeDistributorSelector:
                return this._removeDistributor(calldata);
            case this.isDistributorSelector:
                return this._isDistributor(calldata);
            case this.mintFRENSelector:
                return this._mintFREN(calldata);
            case this.pendingUnstakeSelector:
                return this._pendingUnstakeView(calldata);
            case this.addMinterSelector:
                return this._addMinter(calldata);
            case this.removeMinterSelector:
                return this._removeMinter(calldata);
            case this.isMinterSelector:
                return this._isMinterView(calldata);
            default:
                return super.callMethod(calldata);
        }
    }

    // -----------------------------------------------------------------------
    // FREN Minting (deployer only, respects max supply)
    // -----------------------------------------------------------------------

    @method(
        { name: 'to', type: ABIDataTypes.ADDRESS },
        { name: 'amount', type: ABIDataTypes.UINT256 },
    )
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    @emit('Minted')
    private _mintFREN(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;

        // Allow deployer OR whitelisted minters (CauldronV2) to mint
        const isMinter: u256 = this._minters.get(sender);
        if (!u256.eq(isMinter, u256.One)) {
            this.onlyDeployer(sender);
        }

        const to: Address = calldata.readAddress();
        const amount: u256 = calldata.readU256();

        if (amount.isZero()) {
            throw new Revert(ERR_FREN_ZERO_AMOUNT);
        }

        // _mint handles max supply check internally in OP20
        this._mint(to, amount);

        return new BytesWriter(0);
    }

    // -----------------------------------------------------------------------
    // sFREN Staking -- xSUSHI Model
    // -----------------------------------------------------------------------

    /**
     * stake(amount): Lock FREN, receive sFREN proportional to exchange rate.
     * sFREN minted = amount * totalSFRENSupply / totalStakedFREN
     * If pool is empty (first staker), sFREN = amount (1:1).
     */
    @method({ name: 'amount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _stake(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        const amount: u256 = calldata.readU256();

        if (amount.isZero()) {
            throw new Revert(ERR_FREN_ZERO_AMOUNT);
        }

        // Check caller has enough FREN
        const senderBalance: u256 = this._balanceOf(sender);
        if (u256.lt(senderBalance, amount)) {
            throw new Revert(ERR_FREN_INSUFFICIENT);
        }

        // Calculate sFREN to mint
        const totalStaked: u256 = this._totalStakedFREN.get();
        const totalSFREN: u256 = this._totalSFRENSupply.get();
        let sfrenToMint: u256;

        if (totalSFREN.isZero() || totalStaked.isZero()) {
            // First staker: 1:1 ratio
            sfrenToMint = amount;
        } else {
            // sFREN = amount * totalSFRENSupply / totalStakedFREN
            sfrenToMint = SafeMath.div(
                SafeMath.mul(amount, totalSFREN),
                totalStaked,
            );
        }

        if (sfrenToMint.isZero()) {
            throw new Revert(ERR_FREN_ZERO_SFREN);
        }

        // Burn FREN from sender (locks it into the staking pool)
        this._burn(sender, amount);

        // Update staking pool totals
        this._totalStakedFREN.set(SafeMath.add(totalStaked, amount));

        // Mint sFREN to sender
        const currentSFREN: u256 = this._sfrenBalances.get(sender);
        this._sfrenBalances.set(sender, SafeMath.add(currentSFREN, sfrenToMint));
        this._totalSFRENSupply.set(SafeMath.add(totalSFREN, sfrenToMint));

        this.emitEvent(new StakedEvent(sender, amount, sfrenToMint));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * unstake(sfrenAmount): Burn sFREN, start 24h timelock to claim FREN.
     * FREN returned = sfrenAmount * totalStakedFREN / totalSFRENSupply
     * Single pending unstake per address.
     */
    @method({ name: 'sfrenAmount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _unstake(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        const sfrenAmount: u256 = calldata.readU256();

        if (sfrenAmount.isZero()) {
            throw new Revert(ERR_FREN_ZERO_AMOUNT);
        }

        // Check sFREN balance
        const senderSFREN: u256 = this._sfrenBalances.get(sender);
        if (u256.lt(senderSFREN, sfrenAmount)) {
            throw new Revert(ERR_FREN_SFREN_INSUFFICIENT);
        }

        // Check no existing pending unstake
        const existingPending: u256 = this._pendingAmounts.get(sender);
        if (!existingPending.isZero()) {
            throw new Revert(ERR_FREN_PENDING_EXISTS);
        }

        // Calculate FREN to return at current ratio
        const totalStaked: u256 = this._totalStakedFREN.get();
        const totalSFREN: u256 = this._totalSFRENSupply.get();

        // FREN = sfrenAmount * totalStakedFREN / totalSFRENSupply
        const frenToReturn: u256 = SafeMath.div(
            SafeMath.mul(sfrenAmount, totalStaked),
            totalSFREN,
        );

        if (frenToReturn.isZero()) {
            throw new Revert(ERR_FREN_ZERO_AMOUNT);
        }

        // Burn sFREN
        this._sfrenBalances.set(sender, SafeMath.sub(senderSFREN, sfrenAmount));
        this._totalSFRENSupply.set(SafeMath.sub(totalSFREN, sfrenAmount));

        // Remove FREN from staking pool
        this._totalStakedFREN.set(SafeMath.sub(totalStaked, frenToReturn));

        // Store pending unstake with block number
        const currentBlock: u64 = Blockchain.block.number;
        this._pendingAmounts.set(sender, frenToReturn);
        this._pendingTimestamps.set(sender, u256.fromU64(currentBlock));

        this.emitEvent(new UnstakeInitiatedEvent(sender, sfrenAmount, frenToReturn));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * claimUnstake(): Claim matured pending FREN after 24h timelock.
     */
    @method()
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _claimUnstake(_calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;

        const pendingAmount: u256 = this._pendingAmounts.get(sender);
        if (pendingAmount.isZero()) {
            throw new Revert(ERR_FREN_NO_PENDING);
        }

        const pendingBlock: u256 = this._pendingTimestamps.get(sender);
        const initiatedAtBlock: u64 = pendingBlock.toU64();
        const currentBlock: u64 = Blockchain.block.number;

        if (currentBlock < initiatedAtBlock + UNSTAKE_TIMELOCK_BLOCKS) {
            throw new Revert(ERR_FREN_TIMELOCK);
        }

        // Clear pending unstake
        this._pendingAmounts.set(sender, u256.Zero);
        this._pendingTimestamps.set(sender, u256.Zero);

        // Mint FREN back to sender (was burned during stake)
        this._mint(sender, pendingAmount);

        this.emitEvent(new UnstakeClaimedEvent(sender, pendingAmount));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Reward Distribution (Distributor-only -- Cauldron contracts)
    // -----------------------------------------------------------------------

    /**
     * distributeReward(amount): Cauldron pushes FREN into staking pool.
     * Increases totalStakedFREN without minting sFREN -> ratio appreciates.
     * The caller must have already transferred FREN to this contract.
     */
    @method({ name: 'amount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _distributeReward(calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;
        const amount: u256 = calldata.readU256();

        // Check distributor whitelist
        const isDistrib: u256 = this._distributors.get(sender);
        if (!u256.eq(isDistrib, u256.One)) {
            throw new Revert(ERR_FREN_NOT_DISTRIBUTOR);
        }

        if (amount.isZero()) {
            throw new Revert(ERR_FREN_ZERO_AMOUNT);
        }

        const totalSFREN: u256 = this._totalSFRENSupply.get();
        if (totalSFREN.isZero()) {
            throw new Revert(ERR_FREN_NO_STAKERS);
        }

        // Increase the staked FREN pool -- makes each sFREN worth more
        const totalStaked: u256 = this._totalStakedFREN.get();
        this._totalStakedFREN.set(SafeMath.add(totalStaked, amount));

        this.emitEvent(new RewardDistributedEvent(sender, amount));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Distributor Management (Deployer-only)
    // -----------------------------------------------------------------------

    @method({ name: 'distributor', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _addDistributor(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const distributor: Address = calldata.readAddress();
        if (distributor.equals(Address.dead())) {
            throw new Revert(ERR_FREN_ZERO_ADDR);
        }
        this._distributors.set(distributor, u256.One);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'distributor', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _removeDistributor(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);
        const distributor: Address = calldata.readAddress();
        this._distributors.set(distributor, u256.Zero);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'account', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'result', type: ABIDataTypes.BOOL })
    private _isDistributor(calldata: Calldata): BytesWriter {
        const account: Address = calldata.readAddress();
        const val: u256 = this._distributors.get(account);
        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(u256.eq(val, u256.One));
        return writer;
    }

    // -----------------------------------------------------------------------
    // View Methods
    // -----------------------------------------------------------------------

    @method({ name: 'account', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'balance', type: ABIDataTypes.UINT256 })
    private _sfrenBalanceOf(calldata: Calldata): BytesWriter {
        const account: Address = calldata.readAddress();
        const balance: u256 = this._sfrenBalances.get(account);
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(balance);
        return writer;
    }

    @method()
    @returns({ name: 'supply', type: ABIDataTypes.UINT256 })
    private _sfrenTotalSupply(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._totalSFRENSupply.get());
        return writer;
    }

    @method()
    @returns({ name: 'total', type: ABIDataTypes.UINT256 })
    private _totalStakedView(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._totalStakedFREN.get());
        return writer;
    }

    /**
     * Exchange rate: FREN per sFREN = totalStakedFREN * PRECISION / totalSFREN.
     * Returns PRECISION (1e18) if no sFREN exists (1:1 ratio).
     */
    @method()
    @returns({ name: 'rate', type: ABIDataTypes.UINT256 })
    private _exchangeRate(_calldata: Calldata): BytesWriter {
        const totalSFREN: u256 = this._totalSFRENSupply.get();
        const totalStaked: u256 = this._totalStakedFREN.get();
        const PRECISION: u256 = u256.fromString('1000000000000000000'); // 1e18

        let rate: u256;
        if (totalSFREN.isZero()) {
            rate = PRECISION; // 1:1
        } else {
            rate = SafeMath.div(SafeMath.mul(totalStaked, PRECISION), totalSFREN);
        }

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(rate);
        return writer;
    }

    /**
     * Returns pending unstake (amount, timestamp) for an address.
     */
    @method({ name: 'account', type: ABIDataTypes.ADDRESS })
    @returns(
        { name: 'amount', type: ABIDataTypes.UINT256 },
        { name: 'timestamp', type: ABIDataTypes.UINT256 },
    )
    private _pendingUnstakeView(calldata: Calldata): BytesWriter {
        const account: Address = calldata.readAddress();
        const amount: u256 = this._pendingAmounts.get(account);
        const timestamp: u256 = this._pendingTimestamps.get(account);

        const writer: BytesWriter = new BytesWriter(64);
        writer.writeU256(amount);
        writer.writeU256(timestamp);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Minter Management (Deployer-only)
    // -----------------------------------------------------------------------

    @method({ name: 'minter', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _addMinter(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const minter: Address = calldata.readAddress();
        if (minter.equals(Address.dead())) {
            throw new Revert(ERR_FREN_ZERO_ADDR);
        }

        this._minters.set(minter, u256.One);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'minter', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    private _removeMinter(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const minter: Address = calldata.readAddress();
        const isMinter: u256 = this._minters.get(minter);
        if (!u256.eq(isMinter, u256.One)) {
            throw new Revert(ERR_FREN_NOT_A_MINTER);
        }

        this._minters.set(minter, u256.Zero);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'account', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'result', type: ABIDataTypes.BOOL })
    private _isMinterView(calldata: Calldata): BytesWriter {
        const account: Address = calldata.readAddress();
        const isMinter: u256 = this._minters.get(account);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(u256.eq(isMinter, u256.One));
        return writer;
    }
}
