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
    AddressMemoryMap,
} from '@btc-vision/btc-runtime/runtime';
import { CallResult } from '@btc-vision/btc-runtime/runtime/env/BlockchainEnvironment';

import {
    PRECISION_18,
    REENTRANCY_UNLOCKED,
    REENTRANCY_LOCKED,
    MIN_ELDER_STREAK,
} from '../lib/constants';
import {
    ERR_ELDER_NOT_ADMIN,
    ERR_ELDER_ALREADY_CHECKED_IN,
    ERR_ELDER_NO_REWARDS,
    ERR_ELDER_NOT_AUTHORIZED,
    ERR_ELDER_NO_WEIGHT,
    ERR_ELDER_REENTRANT,
    ERR_ELDER_NOT_SUMMONED,
    ERR_ELDER_ZERO_ADDR,
    ERR_ELDER_ZERO_AMOUNT,
    ERR_ELDER_NOT_DEPOSITOR,
    ERR_ELDER_GEN_ZERO,
} from '../lib/errors';
import {
    OathTakenEvent,
    OathBrokenEvent,
    ManaDepositedEvent,
    ManaHarvestedEvent,
} from '../events/ElderCircleEvents';

/**
 * ElderCircle - Loyalty Streak & Fee Distribution Contract
 *
 * Tracks consecutive generation check-ins for holders who never sell.
 * Distributes trading fees proportional to streak * balance using a
 * MasterChef-style O(1) reward accumulator.
 */
@final
export class ElderCircle extends OP_NET {
    // -----------------------------------------------------------------------
    // Storage Pointers
    // -----------------------------------------------------------------------
    private readonly registryPointer: u16 = Blockchain.nextPointer;
    private readonly tokenPointer: u16 = Blockchain.nextPointer;
    private readonly currentGenPointer: u16 = Blockchain.nextPointer;
    private readonly totalWeightPointer: u16 = Blockchain.nextPointer;
    private readonly accRewardPerWeightPointer: u16 = Blockchain.nextPointer;
    private readonly holderStreakPointer: u16 = Blockchain.nextPointer;
    private readonly holderLastGenPointer: u16 = Blockchain.nextPointer;
    private readonly holderRewardDebtPointer: u16 = Blockchain.nextPointer;
    private readonly holderPendingPointer: u16 = Blockchain.nextPointer;
    private readonly holderBalanceSnapshotPointer: u16 = Blockchain.nextPointer;
    private readonly authorizedTokensPointer: u16 = Blockchain.nextPointer;
    private readonly reentrancyPointer: u16 = Blockchain.nextPointer;
    private readonly authorizedDepositorsPointer: u16 = Blockchain.nextPointer;

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------
    private _registry!: StoredAddress;
    private _token!: StoredAddress;
    private _currentGen!: StoredU256;
    private _totalWeight!: StoredU256;
    private _accRewardPerWeight!: StoredU256;

    private _holderStreak!: AddressMemoryMap;
    private _holderLastGen!: AddressMemoryMap;
    private _holderRewardDebt!: AddressMemoryMap;
    private _holderPending!: AddressMemoryMap;
    private _holderBalanceSnapshot!: AddressMemoryMap;
    private _authorizedTokens!: AddressMemoryMap;
    private _authorizedDepositors!: AddressMemoryMap;

    private _reentrancyGuard!: StoredU256;

    public constructor() {
        super();

        this._registry = new StoredAddress(this.registryPointer);
        this._token = new StoredAddress(this.tokenPointer);
        this._currentGen = new StoredU256(this.currentGenPointer, new Uint8Array(0));
        this._totalWeight = new StoredU256(this.totalWeightPointer, new Uint8Array(0));
        this._accRewardPerWeight = new StoredU256(this.accRewardPerWeightPointer, new Uint8Array(0));

        this._holderStreak = new AddressMemoryMap(this.holderStreakPointer);
        this._holderLastGen = new AddressMemoryMap(this.holderLastGenPointer);
        this._holderRewardDebt = new AddressMemoryMap(this.holderRewardDebtPointer);
        this._holderPending = new AddressMemoryMap(this.holderPendingPointer);
        this._holderBalanceSnapshot = new AddressMemoryMap(this.holderBalanceSnapshotPointer);
        this._authorizedTokens = new AddressMemoryMap(this.authorizedTokensPointer);
        this._authorizedDepositors = new AddressMemoryMap(this.authorizedDepositorsPointer);

        this._reentrancyGuard = new StoredU256(this.reentrancyPointer, new Uint8Array(0));
    }

    public override onDeployment(calldata: Calldata): void {
        const registry: Address = calldata.readAddress();
        const token: Address = calldata.readAddress();

        this._registry.value = registry;
        this._token.value = token;
        this._reentrancyGuard.value = REENTRANCY_UNLOCKED;

        // Authorize the initial token
        this._authorizedTokens.set(token, u256.One);
    }

    // -----------------------------------------------------------------------
    // Public Methods
    // -----------------------------------------------------------------------

    /**
     * checkin() - Register for the current generation.
     * If lastGen == currentGen - 1: streak++, else streak = 1.
     * Updates holder weight in totalWeight.
     */
    @method()
    @returns({ name: 'streak', type: ABIDataTypes.UINT256 })
    public checkin(_calldata: Calldata): BytesWriter {
        const sender: Address = Blockchain.tx.sender;

        // Sync current generation from registry
        const currentGen: u256 = this._fetchCurrentGeneration();
        this._currentGen.value = currentGen;

        // Guard against generation 0 (contract not yet initialized / no generations)
        if (currentGen.isZero()) {
            throw new Revert(ERR_ELDER_GEN_ZERO);
        }

        const lastGen: u256 = this._holderLastGen.get(sender);

        // Prevent double check-in
        if (u256.eq(lastGen, currentGen)) {
            throw new Revert(ERR_ELDER_ALREADY_CHECKED_IN);
        }

        // Settle any existing rewards before changing weight
        this._settle(sender);

        // Determine new streak
        const prevGen: u256 = SafeMath.sub(currentGen, u256.One);
        let newStreak: u256;
        if (u256.eq(lastGen, prevGen)) {
            // Consecutive: increment streak
            const oldStreak: u256 = this._holderStreak.get(sender);
            newStreak = SafeMath.add(oldStreak, u256.One);
        } else {
            // Gap or first check-in: start at 1
            newStreak = u256.One;
        }

        // Remove old weight, add new weight
        const oldBalance: u256 = this._holderBalanceSnapshot.get(sender);
        const oldStreakVal: u256 = this._holderStreak.get(sender);
        const oldWeight: u256 = SafeMath.mul(oldStreakVal, oldBalance);

        // Fetch current balance from token
        const currentBalance: u256 = this._fetchBalance(sender);
        const newWeight: u256 = SafeMath.mul(newStreak, currentBalance);

        // Update totalWeight
        let totalWeight: u256 = this._totalWeight.value;
        totalWeight = SafeMath.sub(totalWeight, oldWeight);
        totalWeight = SafeMath.add(totalWeight, newWeight);
        this._totalWeight.value = totalWeight;

        // Store updated holder state
        this._holderStreak.set(sender, newStreak);
        this._holderLastGen.set(sender, currentGen);
        this._holderBalanceSnapshot.set(sender, currentBalance);

        // Reset reward debt for new weight
        const acc: u256 = this._accRewardPerWeight.value;
        const newDebt: u256 = SafeMath.div(SafeMath.mul(newWeight, acc), PRECISION_18);
        this._holderRewardDebt.set(sender, newDebt);

        this.emitEvent(new OathTakenEvent(sender, currentGen, newStreak));

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(newStreak);
        return writer;
    }

    /**
     * claimRewards() - Settle and transfer pending rewards to caller.
     */
    @method()
    @returns({ name: 'amount', type: ABIDataTypes.UINT256 })
    public claimRewards(_calldata: Calldata): BytesWriter {
        this._nonReentrant();

        const sender: Address = Blockchain.tx.sender;
        this._settle(sender);

        const pending: u256 = this._holderPending.get(sender);
        if (pending.isZero()) {
            this._reentrancyGuard.value = REENTRANCY_UNLOCKED;
            throw new Revert(ERR_ELDER_NO_REWARDS);
        }

        // Clear pending
        this._holderPending.set(sender, u256.Zero);

        // Transfer rewards
        this._transferTokens(sender, pending);

        this.emitEvent(new ManaHarvestedEvent(sender, pending));

        this._reentrancyGuard.value = REENTRANCY_UNLOCKED;

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(pending);
        return writer;
    }

    /**
     * depositFees(amount) - Update the reward accumulator.
     * Called by keeper or anyone who sends fees to this contract.
     */
    @method({ name: 'amount', type: ABIDataTypes.UINT256 })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public depositFees(calldata: Calldata): BytesWriter {
        // Restrict to authorized depositors
        const sender: Address = Blockchain.tx.sender;
        const isAuthorized: u256 = this._authorizedDepositors.get(sender);
        if (!u256.eq(isAuthorized, u256.One)) {
            throw new Revert(ERR_ELDER_NOT_DEPOSITOR);
        }

        const amount: u256 = calldata.readU256();

        if (amount.isZero()) {
            throw new Revert(ERR_ELDER_ZERO_AMOUNT);
        }

        const totalWeight: u256 = this._totalWeight.value;
        if (totalWeight.isZero()) {
            throw new Revert(ERR_ELDER_NO_WEIGHT);
        }

        // acc += amount * 1e18 / totalWeight
        const scaled: u256 = SafeMath.mul(amount, PRECISION_18);
        const delta: u256 = SafeMath.div(scaled, totalWeight);
        const acc: u256 = this._accRewardPerWeight.value;
        const newAcc: u256 = SafeMath.add(acc, delta);
        this._accRewardPerWeight.value = newAcc;

        this.emitEvent(new ManaDepositedEvent(amount, newAcc));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    /**
     * notifyTransfer(from) - Called by CauldronToken on outgoing transfer.
     * Settles rewards, then resets the sender's streak to 0.
     */
    @method({ name: 'from', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public notifyTransfer(calldata: Calldata): BytesWriter {
        const caller: Address = Blockchain.tx.sender;

        // Only authorized tokens may call this
        const authorized: u256 = this._authorizedTokens.get(caller);
        if (!u256.eq(authorized, u256.One)) {
            throw new Revert(ERR_ELDER_NOT_AUTHORIZED);
        }

        const from: Address = calldata.readAddress();
        const previousStreak: u256 = this._holderStreak.get(from);

        // Nothing to do if streak is already zero
        if (previousStreak.isZero()) {
            const writer: BytesWriter = new BytesWriter(1);
            writer.writeBoolean(true);
            return writer;
        }

        // Settle pending rewards before resetting
        this._settle(from);

        // Remove holder's weight from total
        const balance: u256 = this._holderBalanceSnapshot.get(from);
        const oldWeight: u256 = SafeMath.mul(previousStreak, balance);
        let totalWeight: u256 = this._totalWeight.value;
        totalWeight = SafeMath.sub(totalWeight, oldWeight);
        this._totalWeight.value = totalWeight;

        // Reset streak
        this._holderStreak.set(from, u256.Zero);
        this._holderBalanceSnapshot.set(from, u256.Zero);
        this._holderRewardDebt.set(from, u256.Zero);

        this.emitEvent(new OathBrokenEvent(from, previousStreak));

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Admin Methods
    // -----------------------------------------------------------------------

    @method({ name: 'token', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setTokenAddress(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const token: Address = calldata.readAddress();
        this._token.value = token;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'registry', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public setRegistryAddress(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const registry: Address = calldata.readAddress();
        this._registry.value = registry;

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'token', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public authorizeToken(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const token: Address = calldata.readAddress();
        this._authorizedTokens.set(token, u256.One);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'token', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public deauthorizeToken(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const token: Address = calldata.readAddress();
        this._authorizedTokens.set(token, u256.Zero);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'depositor', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public authorizeDepositor(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const depositor: Address = calldata.readAddress();
        this._authorizedDepositors.set(depositor, u256.One);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    @method({ name: 'depositor', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'success', type: ABIDataTypes.BOOL })
    public deauthorizeDepositor(calldata: Calldata): BytesWriter {
        this.onlyDeployer(Blockchain.tx.sender);

        const depositor: Address = calldata.readAddress();
        this._authorizedDepositors.set(depositor, u256.Zero);

        const writer: BytesWriter = new BytesWriter(1);
        writer.writeBoolean(true);
        return writer;
    }

    // -----------------------------------------------------------------------
    // View Methods
    // -----------------------------------------------------------------------

    @method({ name: 'holder', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'streak', type: ABIDataTypes.UINT256 })
    public getStreak(calldata: Calldata): BytesWriter {
        const holder: Address = calldata.readAddress();
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._holderStreak.get(holder));
        return writer;
    }

    @method({ name: 'holder', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'pending', type: ABIDataTypes.UINT256 })
    public getPending(calldata: Calldata): BytesWriter {
        const holder: Address = calldata.readAddress();
        const streak: u256 = this._holderStreak.get(holder);
        const balance: u256 = this._holderBalanceSnapshot.get(holder);
        const weight: u256 = SafeMath.mul(streak, balance);
        const acc: u256 = this._accRewardPerWeight.value;
        const accumulated: u256 = SafeMath.div(SafeMath.mul(weight, acc), PRECISION_18);
        const debt: u256 = this._holderRewardDebt.get(holder);
        const newPending: u256 = SafeMath.sub(accumulated, debt);
        const storedPending: u256 = this._holderPending.get(holder);
        const total: u256 = SafeMath.add(storedPending, newPending);

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(total);
        return writer;
    }

    @method({ name: 'holder', type: ABIDataTypes.ADDRESS })
    @returns({ name: 'weight', type: ABIDataTypes.UINT256 })
    public getWeight(calldata: Calldata): BytesWriter {
        const holder: Address = calldata.readAddress();
        const streak: u256 = this._holderStreak.get(holder);
        const balance: u256 = this._holderBalanceSnapshot.get(holder);

        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(SafeMath.mul(streak, balance));
        return writer;
    }

    @method()
    @returns({ name: 'totalWeight', type: ABIDataTypes.UINT256 })
    public getTotalWeight(_calldata: Calldata): BytesWriter {
        const writer: BytesWriter = new BytesWriter(32);
        writer.writeU256(this._totalWeight.value);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    /**
     * _settle(holder) - Refreshes balance snapshot, adjusts totalWeight if
     * balance changed, calculates pending rewards, updates debt.
     */
    private _settle(holder: Address): void {
        const streak: u256 = this._holderStreak.get(holder);
        if (streak.isZero()) {
            return;
        }

        const snapshotBalance: u256 = this._holderBalanceSnapshot.get(holder);
        const currentBalance: u256 = this._fetchBalance(holder);

        // If balance changed since last snapshot, adjust totalWeight
        if (!u256.eq(snapshotBalance, currentBalance)) {
            const oldWeight: u256 = SafeMath.mul(streak, snapshotBalance);
            const newWeight: u256 = SafeMath.mul(streak, currentBalance);

            let totalWeight: u256 = this._totalWeight.value;
            totalWeight = SafeMath.sub(totalWeight, oldWeight);
            totalWeight = SafeMath.add(totalWeight, newWeight);
            this._totalWeight.value = totalWeight;

            this._holderBalanceSnapshot.set(holder, currentBalance);
        }

        // Calculate pending rewards
        const weight: u256 = SafeMath.mul(streak, currentBalance);
        const acc: u256 = this._accRewardPerWeight.value;
        const accumulated: u256 = SafeMath.div(SafeMath.mul(weight, acc), PRECISION_18);
        const debt: u256 = this._holderRewardDebt.get(holder);
        const newPending: u256 = SafeMath.sub(accumulated, debt);

        if (!newPending.isZero()) {
            const existingPending: u256 = this._holderPending.get(holder);
            this._holderPending.set(holder, SafeMath.add(existingPending, newPending));
        }

        // Update debt to current accumulated
        this._holderRewardDebt.set(holder, accumulated);
    }

    private _nonReentrant(): void {
        const guard: u256 = this._reentrancyGuard.value;
        if (u256.eq(guard, REENTRANCY_LOCKED)) {
            throw new Revert(ERR_ELDER_REENTRANT);
        }
        this._reentrancyGuard.value = REENTRANCY_LOCKED;
    }

    /**
     * Fetch current generation from CauldronRegistry.
     */
    private _fetchCurrentGeneration(): u256 {
        if (this._registry.isDead()) {
            throw new Revert(ERR_ELDER_NOT_SUMMONED);
        }

        const registry: Address = this._registry.value;
        const writer: BytesWriter = new BytesWriter(4);
        writer.writeSelector(encodeSelector('getCurrentGeneration()'));

        const result: CallResult = Blockchain.call(registry, writer, true);
        return result.data.readU256();
    }

    /**
     * Fetch balance of holder from current CauldronToken.
     */
    private _fetchBalance(holder: Address): u256 {
        if (this._token.isDead()) {
            return u256.Zero;
        }

        const token: Address = this._token.value;
        const writer: BytesWriter = new BytesWriter(36);
        writer.writeSelector(encodeSelector('balanceOf(address)'));
        writer.writeAddress(holder);

        const result: CallResult = Blockchain.call(token, writer, false);
        if (!result.success) {
            return u256.Zero;
        }

        return result.data.readU256();
    }

    /**
     * Transfer tokens from this contract to recipient.
     */
    private _transferTokens(to: Address, amount: u256): void {
        if (this._token.isDead()) {
            throw new Revert(ERR_ELDER_NOT_SUMMONED);
        }

        const token: Address = this._token.value;
        const writer: BytesWriter = new BytesWriter(68);
        writer.writeSelector(encodeSelector('transfer(address,uint256)'));
        writer.writeAddress(to);
        writer.writeU256(amount);

        Blockchain.call(token, writer, true);
    }
}
