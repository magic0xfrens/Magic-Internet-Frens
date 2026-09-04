/**
 * MIFToken.ts — $MIF Stablecoin (OP_20) for the Magic Internet Frens Protocol
 *
 * Name: "Magic Internet Frens Dollar"
 * Symbol: "MIF"
 * Decimals: 18
 *
 * Mint authority is restricted to whitelisted Cauldron contracts.
 * Anyone may burn their own tokens. The contract owner can manage
 * the Cauldron whitelist via addMinter / removeMinter.
 *
 * Follows the OP_20 token standard on OP_NET (Bitcoin L1).
 */

// TODO: OP_NET SDK — import base contract and decorators
// e.g.: import { OP20, Address, u256, Mapping, Blockchain, Events, Revert } from "@opnet/runtime";

// ============================================================================
// Constants
// ============================================================================

const TOKEN_NAME: string = "Magic Internet Frens Dollar";
const TOKEN_SYMBOL: string = "MIF";
const TOKEN_DECIMALS: u8 = 18;

// ============================================================================
// Events
// ============================================================================

/**
 * Standard OP_20 events plus Mint and Burn.
 *
 * TODO: OP_NET SDK — define events using the platform's event system.
 * Typically: Events.emit("Transfer", [from, to, amount])
 */

// class TransferEvent { from: Address; to: Address; amount: u256; }
// class ApprovalEvent { owner: Address; spender: Address; amount: u256; }
// class MintEvent     { to: Address; amount: u256; }
// class BurnEvent     { from: Address; amount: u256; }
// class MinterAddedEvent   { minter: Address; }
// class MinterRemovedEvent { minter: Address; }

// ============================================================================
// Contract: MIFToken
// ============================================================================

// TODO: OP_NET SDK — extend the base OP_20 contract class
// export class MIFToken extends OP20 {

export class MIFToken {

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /** Contract deployer / owner — only address that can manage minters */
    private owner: string = ""; // TODO: OP_NET SDK — use Address type

    /** Total supply of $MIF in circulation */
    private _totalSupply: u64 = 0; // TODO: OP_NET SDK — use u256 for 18-decimal precision

    /** Balance mapping: address -> balance */
    // TODO: OP_NET SDK — private balances: Mapping<Address, u256>;
    private balances: Map<string, u64> = new Map();

    /** Allowance mapping: owner -> (spender -> allowance) */
    // TODO: OP_NET SDK — private allowances: Mapping<Address, Mapping<Address, u256>>;
    private allowances: Map<string, Map<string, u64>> = new Map();

    /** Whitelisted minters (Cauldron contracts that may call mint) */
    // TODO: OP_NET SDK — private minters: Mapping<Address, bool>;
    private minters: Map<string, bool> = new Map();

    // -----------------------------------------------------------------------
    // Constructor / Initialization
    // -----------------------------------------------------------------------

    /**
     * Called once at deployment. Sets the deployer as the owner.
     * No initial supply is minted — Cauldron contracts mint on demand.
     */
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
        // TODO: OP_NET SDK — return u256 from persistent storage
        return this._totalSupply;
    }

    // -----------------------------------------------------------------------
    // OP_20 Core Methods
    // -----------------------------------------------------------------------

    /**
     * Returns the token balance for `account`.
     */
    public balanceOf(account: string): u64 {
        // TODO: OP_NET SDK — return this.balances.get(account) using Address type + u256
        if (this.balances.has(account)) {
            return this.balances.get(account);
        }
        return 0;
    }

    /**
     * Returns the remaining allowance that `spender` is permitted to spend
     * on behalf of `owner`.
     */
    public allowance(owner: string, spender: string): u64 {
        // TODO: OP_NET SDK — use Address type + u256 from persistent storage
        if (this.allowances.has(owner)) {
            const ownerAllowances = this.allowances.get(owner);
            if (ownerAllowances.has(spender)) {
                return ownerAllowances.get(spender);
            }
        }
        return 0;
    }

    /**
     * Moves `amount` tokens from the caller to `to`.
     * Emits a Transfer event. Returns true on success.
     */
    public transfer(to: string, amount: u64): bool {
        // TODO: OP_NET SDK — const sender = Blockchain.msgSender();
        const sender: string = ""; // placeholder

        this._transfer(sender, to, amount);
        return true;
    }

    /**
     * Sets `amount` as the allowance of `spender` over the caller's tokens.
     * Emits an Approval event. Returns true on success.
     */
    public approve(spender: string, amount: u64): bool {
        // TODO: OP_NET SDK — const owner = Blockchain.msgSender();
        const owner: string = ""; // placeholder

        this._approve(owner, spender, amount);
        return true;
    }

    /**
     * Moves `amount` tokens from `from` to `to` using the caller's allowance.
     * Deducts from the caller's allowance. Emits a Transfer event.
     * Returns true on success.
     */
    public transferFrom(from: string, to: string, amount: u64): bool {
        // TODO: OP_NET SDK — const spender = Blockchain.msgSender();
        const spender: string = ""; // placeholder

        this._spendAllowance(from, spender, amount);
        this._transfer(from, to, amount);
        return true;
    }

    // -----------------------------------------------------------------------
    // Mint (Cauldron only)
    // -----------------------------------------------------------------------

    /**
     * Mints `amount` tokens to address `to`.
     * Only callable by whitelisted Cauldron contracts (minters).
     *
     * @param to     — recipient of the newly minted tokens
     * @param amount — number of tokens to mint (18-decimal precision)
     */
    public mint(to: string, amount: u64): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder

        // Only whitelisted minters may call
        assert(this.minters.has(caller) && this.minters.get(caller), "MIF: caller is not a minter");
        assert(amount > 0, "MIF: mint amount must be > 0");

        this._totalSupply += amount;

        const currentBalance: u64 = this.balanceOf(to);
        this.balances.set(to, currentBalance + amount);

        // TODO: OP_NET SDK — Events.emit("Mint", [to, amount]);
        // TODO: OP_NET SDK — Events.emit("Transfer", [Address.zero(), to, amount]);
    }

    // -----------------------------------------------------------------------
    // Burn (anyone can burn their own tokens)
    // -----------------------------------------------------------------------

    /**
     * Burns `amount` tokens from the caller's balance, reducing total supply.
     *
     * @param amount — number of tokens to burn
     */
    public burn(amount: u64): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder

        const balance: u64 = this.balanceOf(caller);
        assert(balance >= amount, "MIF: burn amount exceeds balance");
        assert(amount > 0, "MIF: burn amount must be > 0");

        this.balances.set(caller, balance - amount);
        this._totalSupply -= amount;

        // TODO: OP_NET SDK — Events.emit("Burn", [caller, amount]);
        // TODO: OP_NET SDK — Events.emit("Transfer", [caller, Address.zero(), amount]);
    }

    // -----------------------------------------------------------------------
    // Minter Management (owner only)
    // -----------------------------------------------------------------------

    /**
     * Adds `minter` to the whitelist of addresses permitted to call mint().
     * Only the contract owner may call this.
     *
     * @param minter — Cauldron contract address to whitelist
     */
    public addMinter(minter: string): void {
        this._onlyOwner();
        assert(minter != "", "MIF: minter is zero address");
        // TODO: OP_NET SDK — assert(minter != Address.zero(), ...)

        this.minters.set(minter, true);

        // TODO: OP_NET SDK — Events.emit("MinterAdded", [minter]);
    }

    /**
     * Removes `minter` from the whitelist.
     * Only the contract owner may call this.
     *
     * @param minter — Cauldron contract address to remove
     */
    public removeMinter(minter: string): void {
        this._onlyOwner();
        assert(this.minters.has(minter) && this.minters.get(minter), "MIF: address is not a minter");

        this.minters.set(minter, false);

        // TODO: OP_NET SDK — Events.emit("MinterRemoved", [minter]);
    }

    /**
     * Returns true if `account` is a whitelisted minter.
     */
    public isMinter(account: string): bool {
        return this.minters.has(account) && this.minters.get(account);
    }

    // -----------------------------------------------------------------------
    // Owner Management
    // -----------------------------------------------------------------------

    /**
     * Transfers ownership of the contract to `newOwner`.
     * Only the current owner may call this.
     */
    public transferOwnership(newOwner: string): void {
        this._onlyOwner();
        assert(newOwner != "", "MIF: new owner is zero address");
        // TODO: OP_NET SDK — assert(newOwner != Address.zero(), ...)

        this.owner = newOwner;
    }

    /**
     * Returns the current contract owner address.
     */
    public getOwner(): string {
        return this.owner;
    }

    // -----------------------------------------------------------------------
    // Internal Helpers
    // -----------------------------------------------------------------------

    /**
     * Reverts if the caller is not the contract owner.
     */
    private _onlyOwner(): void {
        // TODO: OP_NET SDK — const caller = Blockchain.msgSender();
        const caller: string = ""; // placeholder
        assert(caller == this.owner, "MIF: caller is not the owner");
    }

    /**
     * Internal transfer logic. Validates balances and moves tokens.
     */
    private _transfer(from: string, to: string, amount: u64): void {
        assert(from != "", "MIF: transfer from zero address");
        assert(to != "", "MIF: transfer to zero address");
        // TODO: OP_NET SDK — validate against Address.zero()

        const fromBalance: u64 = this.balanceOf(from);
        assert(fromBalance >= amount, "MIF: transfer amount exceeds balance");

        this.balances.set(from, fromBalance - amount);
        const toBalance: u64 = this.balanceOf(to);
        this.balances.set(to, toBalance + amount);

        // TODO: OP_NET SDK — Events.emit("Transfer", [from, to, amount]);
    }

    /**
     * Internal approve logic.
     */
    private _approve(owner: string, spender: string, amount: u64): void {
        assert(owner != "", "MIF: approve from zero address");
        assert(spender != "", "MIF: approve to zero address");

        if (!this.allowances.has(owner)) {
            this.allowances.set(owner, new Map<string, u64>());
        }
        const ownerAllowances = this.allowances.get(owner);
        ownerAllowances.set(spender, amount);

        // TODO: OP_NET SDK — Events.emit("Approval", [owner, spender, amount]);
    }

    /**
     * Internal: deducts `amount` from the allowance `owner` has granted to `spender`.
     * If allowance is max-u64 (infinite approval), does not deduct.
     */
    private _spendAllowance(owner: string, spender: string, amount: u64): void {
        const currentAllowance: u64 = this.allowance(owner, spender);

        // Skip deduction for "infinite" allowances
        // TODO: OP_NET SDK — compare against u256.MAX
        if (currentAllowance != u64.MAX_VALUE) {
            assert(currentAllowance >= amount, "MIF: insufficient allowance");
            this._approve(owner, spender, currentAllowance - amount);
        }
    }
}
