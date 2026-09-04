/**
 * FRENToken.ts — $FREN Governance + Staking Token (OP_20) for Magic Internet Frens
 *
 * Name: "FREN"
 * Symbol: "FREN"
 * Decimals: 18
 * Max Supply: 1,000,000,000 (1 billion)
 *
 * Implements sFREN staking using the xSUSHI model:
 *   - stake(amount): lock FREN, receive sFREN receipt tokens
 *   - unstake(amount): burn sFREN, start 24h timelock, then claim FREN
 *   - distributeReward(amount): Cauldron pushes MIF fees into staking pool
 *   - sFREN/FREN ratio appreciates over time as fees compound
 *
 * Follows the OP_20 token standard on OP_NET (Bitcoin L1).
 */

// TODO: OP_NET SDK — import base contract and decorators
// e.g.: import { OP20, Address, u256, Mapping, Blockchain, Events, Revert } from "@opnet/runtime";

// ============================================================================
// Constants
// ============================================================================

const TOKEN_NAME: string = "FREN";
const TOKEN_SYMBOL: string = "FREN";
const TOKEN_DECIMALS: u8 = 18;

/** 1 billion tokens with 18 decimals. Stored as u64 placeholder; real impl uses u256. */
// TODO: OP_NET SDK — const MAX_SUPPLY: u256 = u256.from("1000000000000000000000000000");
const MAX_SUPPLY: u64 = 1_000_000_000; // placeholder, actual value is 1e27 in u256

/** 24-hour timelock for unstaking (in seconds) */
const UNSTAKE_TIMELOCK: u64 = 86400; // 24 * 60 * 60

// ============================================================================
// Data Structures
// ============================================================================

/**
 * Represents a pending unstake that is subject to the 24-hour timelock.
 */
class PendingUnstake {
    /** Amount of FREN to be returned after timelock */
    frenAmount: u64;
    /** Block timestamp when the unstake was initiated */
    initiatedAt: u64;

    constructor(frenAmount: u64, initiatedAt: u64) {
        this.frenAmount = frenAmount;
        this.initiatedAt = initiatedAt;
    }
}

// ============================================================================
// Events
// ============================================================================

/**
 * TODO: OP_NET SDK — define events using the platform's event system.
 *
 * - Transfer(from, to, amount)           — standard OP_20
 * - Approval(owner, spender, amount)     — standard OP_20
 * - Staked(user, frenAmount, sfrenMinted)
 * - UnstakeInitiated(user, sfrenBurned, frenAmount, claimableAt)
 * - UnstakeClaimed(user, frenAmount)
 * - RewardDistributed(from, mifAmount)
 */

// ============================================================================
// Contract: FRENToken
// ============================================================================

// TODO: OP_NET SDK — extend the base OP_20 contract class
// export class FRENToken extends OP20 {

export class FRENToken {

    // -----------------------------------------------------------------------
    // FREN Token State (OP_20)
    // -----------------------------------------------------------------------

    private owner: string = ""; // TODO: OP_NET SDK — Address type
    private _totalSupply: u64 = 0; // TODO: OP_NET SDK — u256

    // TODO: OP_NET SDK — persistent Mapping<Address, u256>
    private balances: Map<string, u64> = new Map();
    private allowances: Map<string, Map<string, u64>> = new Map();

    // -----------------------------------------------------------------------
    // sFREN Staking State
    // -----------------------------------------------------------------------

    /** Total FREN tokens locked in the staking pool */
    private totalStakedFREN: u64 = 0;

    /** Total sFREN receipt tokens in circulation */
    private totalSFRENSupply: u64 = 0;

    /** sFREN balance per address */
    // TODO: OP_NET SDK — Mapping<Address, u256>
    private sfrenBalances: Map<string, u64> = new Map();

    /** Pending unstake records per address (can have multiple pending) */
    // TODO: OP_NET SDK — Mapping<Address, PendingUnstake[]>
    private pendingUnstakes: Map<string, PendingUnstake[]> = new Map();

    /** Whitelisted addresses allowed to call distributeReward (Cauldron contracts) */
    // TODO: OP_NET SDK — Mapping<Address, bool>
    private rewardDistributors: Map<string, bool> = new Map();

    /** Reference to the MIF token contract for reward accounting */
    private mifTokenAddress: string = ""; // TODO: OP_NET SDK — Address type

    // -----------------------------------------------------------------------
    // Constructor / Initialization
    // -----------------------------------------------------------------------

    constructor() {
        // TODO: OP_NET SDK — this.owner = Blockchain.msgSender();
        // TODO: OP_NET SDK — initialize persistent storage mappings
    }

    // -----------------------------------------------------------------------
    // OP_20 Metadata (view)
    // -----------------------------------------------------------------------

    public name(): string {
        return TOKEN_NAME;
    }

    public symbol(): string {
        return TOKEN_SYMBOL;
    }

    public decimals(): u8 {
        return TOKEN_DECIMALS;
    }

    public totalSupply(): u64 {
        return this._totalSupply;
    }

    public maxSupply(): u64 {
        return MAX_SUPPLY;
    }

    // -----------------------------------------------------------------------
    // OP_20 Core Methods
    // -----------------------------------------------------------------------

    public balanceOf(account: string): u64 {
        if (this.balances.has(account)) {
            return this.balances.get(account);
        }
        return 0;
    }

    public allowance(owner: string, spender: string): u64 {
        if (this.allowances.has(owner)) {
            const ownerAllowances = this.allowances.get(owner);
            if (ownerAllowances.has(spender)) {
                return ownerAllowances.get(spender);
            }
        }
        return 0;
    }

    public transfer(to: string, amount: u64): bool {
        // TODO: OP_NET SDK — const sender = Blockchain.msgSender();
        const sender: string = ""; // placeholder
        this._transfer(sender, to, amount);
        return true;
    }

    public approve(spender: string, amount: u64): bool {
        // TODO: OP_NET SDK — const owner = Blockchain.msgSender();
        const owner: string = ""; // placeholder
        this._approve(owner, spender, amount);
        return true;
    }

    public transferFrom(from: string, to: string, amount: u64): bool {
        // TODO: OP_NET SDK — const spender = Blockchain.msgSender();
        const spender: string = ""; // placeholder
        this._spendAllowance(from, spender, amount);
        this._transfer(from, to, amount);
        return true;
    }

    // -----------------------------------------------------------------------
    // FREN Minting (owner only, respects max supply)
    // -----------------------------------------------------------------------

    /**
     * Mints FREN tokens to `to`. Cannot exceed MAX_SUPPLY.
     * Only callable by the contract owner (initial distribution, vesting, etc.).
     *
     * @param to     — recipient address
     * @param amount — amount to mint
     */
    public mintFREN(to: string, amount: u64): void {
        this._onlyOwner();
        assert(this._totalSupply + amount <= MAX_SUPPLY, "FREN: would exceed max supply");
        assert(amount > 0, "FREN: mint amount must be > 0");

        this._totalSupply += amount;
        const currentBalance = this.balanceOf(to);
        this.balances.set(to, currentBalance + amount);

        // TODO: OP_NET SDK — Events.emit("Transfer", [Address.zero(), to, amount]);
    }

    // -----------------------------------------------------------------------
    // sFREN Staking — xSUSHI Model
    // -----------------------------------------------------------------------

    /**
     * Returns the current sFREN balance for `account`.
     */
    public sfrenBalanceOf(account: string): u64 {
        if (this.sfrenBalances.has(account)) {
            return this.sfrenBalances.get(account);
        }
        return 0;
    }

    /**
     * Returns the total sFREN supply in circulation.
     */
    public sfrenTotalSupply(): u64 {
        return this.totalSFRENSupply;
    }

    /**
     * Returns the total FREN locked in the staking pool.
     */
    public getTotalStakedFREN(): u64 {
        return this.totalStakedFREN;
    }

    /**
     * Returns the current exchange rate: how much FREN 1 sFREN is worth.
     * When no sFREN is minted, the rate is 1:1.
     * As rewards compound, the ratio increases (sFREN becomes more valuable).
     *
     * Formula: frenPerSFREN = totalStakedFREN / totalSFRENSupply
     */
    public getFRENPerSFREN(): u64 {
        if (this.totalSFRENSupply == 0) {
            // 1:1 ratio initially (represented in base units)
            // TODO: OP_NET SDK — return u256.from(10).pow(18) for 1.0 with 18 decimals
            return 1;
        }
        // TODO: OP_NET SDK — use safe math with u256 precision:
        // return (totalStakedFREN * 1e18) / totalSFRENSupply
        return this.totalStakedFREN / this.totalSFRENSupply;
    }

    /**
     * Returns the current exchange rate: how much sFREN you get for 1 FREN.
     *
     * Formula: sfrenPerFREN = totalSFRENSupply / totalStakedFREN
     */
    public getSFRENPerFREN(): u64 {
        if (this.totalStakedFREN == 0) {
            return 1;
        }
        // TODO: OP_NET SDK — use safe math with u256 precision:
        // return (totalSFRENSupply * 1e18) / totalStakedFREN
        return this.totalSFRENSupply / this.totalStakedFREN;
    }

    /**
     * Stakes `amount` FREN tokens. The caller's FREN is locked in the pool
     * and they receive sFREN receipt tokens proportional to the current ratio.
     *
     * sFREN minted = amount * totalSFRENSupply / totalStakedFREN
     * If pool is empty (first staker), sFREN minted = amount (1:1).
     *
     * @param amount — FREN tokens to stake
     */
    public stake(amount: u64): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder

        assert(amount > 0, "FREN: stake amount must be > 0");

        const callerBalance = this.balanceOf(caller);
        assert(callerBalance >= amount, "FREN: insufficient FREN balance");

        // Calculate sFREN to mint using the xSUSHI formula
        let sfrenToMint: u64;

        if (this.totalSFRENSupply == 0 || this.totalStakedFREN == 0) {
            // First staker: 1:1 ratio
            sfrenToMint = amount;
        } else {
            // sFREN = amount * totalSFRENSupply / totalStakedFREN
            // TODO: OP_NET SDK — use u256 safe math to prevent overflow
            sfrenToMint = (amount * this.totalSFRENSupply) / this.totalStakedFREN;
        }

        assert(sfrenToMint > 0, "FREN: stake amount too small");

        // Lock the FREN: deduct from caller balance (tokens stay in contract)
        this.balances.set(caller, callerBalance - amount);
        this.totalStakedFREN += amount;

        // Mint sFREN to caller
        const currentSFREN = this.sfrenBalanceOf(caller);
        this.sfrenBalances.set(caller, currentSFREN + sfrenToMint);
        this.totalSFRENSupply += sfrenToMint;

        // TODO: OP_NET SDK — Events.emit("Staked", [caller, amount, sfrenToMint]);
    }

    /**
     * Initiates an unstake of `sfrenAmount` sFREN tokens.
     * Burns the sFREN immediately and starts a 24-hour timelock.
     * After the timelock, the caller can claim their proportional FREN.
     *
     * FREN returned = sfrenAmount * totalStakedFREN / totalSFRENSupply
     *
     * @param sfrenAmount — sFREN tokens to unstake
     */
    public unstake(sfrenAmount: u64): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder

        assert(sfrenAmount > 0, "FREN: unstake amount must be > 0");

        const callerSFREN = this.sfrenBalanceOf(caller);
        assert(callerSFREN >= sfrenAmount, "FREN: insufficient sFREN balance");

        // Calculate FREN amount to return (at current ratio)
        // FREN = sfrenAmount * totalStakedFREN / totalSFRENSupply
        // TODO: OP_NET SDK — use u256 safe math
        const frenToReturn: u64 = (sfrenAmount * this.totalStakedFREN) / this.totalSFRENSupply;
        assert(frenToReturn > 0, "FREN: unstake amount too small");

        // Burn sFREN immediately
        this.sfrenBalances.set(caller, callerSFREN - sfrenAmount);
        this.totalSFRENSupply -= sfrenAmount;

        // Remove FREN from staking pool (earmarked for this unstake)
        this.totalStakedFREN -= frenToReturn;

        // Create pending unstake with 24-hour timelock
        // TODO: OP_NET SDK — const now = Blockchain.blockTimestamp();
        const now: u64 = 0; // placeholder
        const pending = new PendingUnstake(frenToReturn, now);

        if (!this.pendingUnstakes.has(caller)) {
            this.pendingUnstakes.set(caller, []);
        }
        const unstakes = this.pendingUnstakes.get(caller);
        unstakes.push(pending);

        const claimableAt = now + UNSTAKE_TIMELOCK;
        // TODO: OP_NET SDK — Events.emit("UnstakeInitiated", [caller, sfrenAmount, frenToReturn, claimableAt]);
    }

    /**
     * Claims all matured pending unstakes for the caller.
     * Only unstakes that have passed the 24-hour timelock are released.
     * Unclaimed (still locked) unstakes remain in the queue.
     */
    public claimUnstake(): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder
        // TODO: OP_NET SDK — const now = Blockchain.blockTimestamp();
        const now: u64 = 0; // placeholder

        assert(this.pendingUnstakes.has(caller), "FREN: no pending unstakes");

        const unstakes = this.pendingUnstakes.get(caller);
        assert(unstakes.length > 0, "FREN: no pending unstakes");

        let totalClaimable: u64 = 0;
        const remaining: PendingUnstake[] = [];

        for (let i = 0; i < unstakes.length; i++) {
            const pending = unstakes[i];
            if (now >= pending.initiatedAt + UNSTAKE_TIMELOCK) {
                // Matured — add to claimable
                totalClaimable += pending.frenAmount;
            } else {
                // Still locked — keep in queue
                remaining.push(pending);
            }
        }

        assert(totalClaimable > 0, "FREN: no claimable unstakes (still in timelock)");

        // Update pending unstakes (remove claimed entries)
        if (remaining.length > 0) {
            this.pendingUnstakes.set(caller, remaining);
        } else {
            this.pendingUnstakes.delete(caller);
        }

        // Return FREN to caller
        const callerBalance = this.balanceOf(caller);
        this.balances.set(caller, callerBalance + totalClaimable);

        // TODO: OP_NET SDK — Events.emit("UnstakeClaimed", [caller, totalClaimable]);
    }

    /**
     * Returns all pending unstake records for `account`.
     */
    public getPendingUnstakes(account: string): PendingUnstake[] {
        if (this.pendingUnstakes.has(account)) {
            return this.pendingUnstakes.get(account);
        }
        return [];
    }

    /**
     * Returns the total FREN amount in pending (locked) unstakes for `account`.
     */
    public getPendingUnstakeTotal(account: string): u64 {
        const unstakes = this.getPendingUnstakes(account);
        let total: u64 = 0;
        for (let i = 0; i < unstakes.length; i++) {
            total += unstakes[i].frenAmount;
        }
        return total;
    }

    // -----------------------------------------------------------------------
    // Reward Distribution (Cauldron only)
    // -----------------------------------------------------------------------

    /**
     * Called by a whitelisted Cauldron contract to distribute MIF fee rewards
     * into the sFREN staking pool.
     *
     * This increases the totalStakedFREN without minting new sFREN,
     * which causes the sFREN/FREN ratio to increase. Each sFREN token
     * becomes redeemable for more FREN over time (compounding).
     *
     * In practice, the Cauldron converts its fee revenue to FREN on the
     * open market and then calls this function with the acquired FREN amount.
     *
     * @param amount — FREN tokens to add to the staking pool
     */
    public distributeReward(amount: u64): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder

        assert(
            this.rewardDistributors.has(caller) && this.rewardDistributors.get(caller),
            "FREN: caller is not an authorized reward distributor"
        );
        assert(amount > 0, "FREN: reward amount must be > 0");
        assert(this.totalSFRENSupply > 0, "FREN: no stakers to receive rewards");

        // The FREN tokens should have been transferred to this contract already.
        // We simply increase the pool's tracked FREN, making each sFREN worth more.
        // TODO: OP_NET SDK — verify that the contract's FREN balance increased by `amount`
        //   via a prior transfer or direct balance check.
        this.totalStakedFREN += amount;

        // TODO: OP_NET SDK — Events.emit("RewardDistributed", [caller, amount]);
    }

    // -----------------------------------------------------------------------
    // Admin: Reward Distributor Management (owner only)
    // -----------------------------------------------------------------------

    /**
     * Adds `distributor` to the whitelist of addresses allowed to call
     * distributeReward(). Only the contract owner may call this.
     */
    public addRewardDistributor(distributor: string): void {
        this._onlyOwner();
        assert(distributor != "", "FREN: distributor is zero address");
        this.rewardDistributors.set(distributor, true);
    }

    /**
     * Removes `distributor` from the reward distributor whitelist.
     */
    public removeRewardDistributor(distributor: string): void {
        this._onlyOwner();
        assert(
            this.rewardDistributors.has(distributor) && this.rewardDistributors.get(distributor),
            "FREN: address is not a distributor"
        );
        this.rewardDistributors.set(distributor, false);
    }

    /**
     * Returns true if `account` is a whitelisted reward distributor.
     */
    public isRewardDistributor(account: string): bool {
        return this.rewardDistributors.has(account) && this.rewardDistributors.get(account);
    }

    // -----------------------------------------------------------------------
    // Admin: MIF Token Address (owner only)
    // -----------------------------------------------------------------------

    /**
     * Sets the MIF token contract address. Used for reward distribution accounting.
     */
    public setMIFTokenAddress(mifAddress: string): void {
        this._onlyOwner();
        assert(mifAddress != "", "FREN: MIF address is zero");
        this.mifTokenAddress = mifAddress;
    }

    public getMIFTokenAddress(): string {
        return this.mifTokenAddress;
    }

    // -----------------------------------------------------------------------
    // Owner Management
    // -----------------------------------------------------------------------

    public transferOwnership(newOwner: string): void {
        this._onlyOwner();
        assert(newOwner != "", "FREN: new owner is zero address");
        this.owner = newOwner;
    }

    public getOwner(): string {
        return this.owner;
    }

    // -----------------------------------------------------------------------
    // Internal Helpers
    // -----------------------------------------------------------------------

    private _onlyOwner(): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder
        assert(caller == this.owner, "FREN: caller is not the owner");
    }

    private _transfer(from: string, to: string, amount: u64): void {
        assert(from != "", "FREN: transfer from zero address");
        assert(to != "", "FREN: transfer to zero address");

        const fromBalance = this.balanceOf(from);
        assert(fromBalance >= amount, "FREN: transfer amount exceeds balance");

        this.balances.set(from, fromBalance - amount);
        const toBalance = this.balanceOf(to);
        this.balances.set(to, toBalance + amount);

        // TODO: OP_NET SDK — Events.emit("Transfer", [from, to, amount]);
    }

    private _approve(owner: string, spender: string, amount: u64): void {
        assert(owner != "", "FREN: approve from zero address");
        assert(spender != "", "FREN: approve to zero address");

        if (!this.allowances.has(owner)) {
            this.allowances.set(owner, new Map<string, u64>());
        }
        const ownerAllowances = this.allowances.get(owner);
        ownerAllowances.set(spender, amount);

        // TODO: OP_NET SDK — Events.emit("Approval", [owner, spender, amount]);
    }

    private _spendAllowance(owner: string, spender: string, amount: u64): void {
        const currentAllowance = this.allowance(owner, spender);
        if (currentAllowance != u64.MAX_VALUE) {
            assert(currentAllowance >= amount, "FREN: insufficient allowance");
            this._approve(owner, spender, currentAllowance - amount);
        }
    }
}
