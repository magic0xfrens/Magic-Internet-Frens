/**
 * Oracle.ts -- BTC/USD Price Oracle for the Magic Internet Frens Protocol
 * =========================================================================
 * Target: OP_NET (Bitcoin L1) -- AssemblyScript Smart Contract
 *
 * V1: Admin-set price with update tracking and staleness checks.
 * V2 (planned): TWAP integration from OP_NET DEX pairs.
 *
 * Price is stored as u256 with 18 decimals of precision.
 * Example: BTC at $60,000 => 60000 * 10^18 => 60000_000000000000000000
 *
 * Staleness window: 1 hour (3600 seconds). Any call to getPrice() will
 * revert if the last update is older than this threshold.
 */

// TODO: OP_NET SDK -- import the OP_NET runtime, storage, and contract base class
// import {
//   Blockchain,
//   BytesWriter,
//   Calldata,
//   encodeSelector,
//   Map,
//   OP_20,
//   Selector,
//   StoredU256,
//   StoredU64,
//   StoredAddress,
//   Address,
//   u256,
// } from "@opnet/btc-runtime";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Maximum allowed age of a price update before it is considered stale (seconds). */
const STALENESS_THRESHOLD: u64 = 3600; // 1 hour

/** 18-decimal precision multiplier: 10^18 */
// const PRECISION: u256 = u256.fromU64(10).pow(18);

// ---------------------------------------------------------------------------
// Storage slot keys (deterministic, collision-resistant)
// ---------------------------------------------------------------------------

const SLOT_ADMIN:          u64 = 0;  // Address -- the oracle admin
const SLOT_PRICE:          u64 = 1;  // u256   -- current BTC/USD price (18 dec)
const SLOT_LAST_UPDATE:    u64 = 2;  // u64    -- block timestamp of last setPrice
const SLOT_UPDATE_COUNT:   u64 = 3;  // u256   -- total number of updates

// TODO: V2 TWAP slots
const SLOT_TWAP_CUMULATIVE:     u64 = 10; // u256 -- cumulative price for TWAP
const SLOT_TWAP_LAST_TIMESTAMP: u64 = 11; // u64  -- last TWAP observation time
const SLOT_TWAP_WINDOW:         u64 = 12; // u64  -- TWAP window in seconds (default 1800 = 30 min)

// ---------------------------------------------------------------------------
// Event selectors
// ---------------------------------------------------------------------------

// TODO: OP_NET SDK -- define event selectors
// const EVENT_PRICE_UPDATED = encodeSelector("PriceUpdated(u256,u64)");
// const EVENT_ADMIN_TRANSFERRED = encodeSelector("AdminTransferred(address,address)");

// ---------------------------------------------------------------------------
// Oracle Contract
// ---------------------------------------------------------------------------

// TODO: OP_NET SDK -- extend the OP_NET contract base class
// export class Oracle extends Contract {

export class Oracle {

  // =========================================================================
  // Storage accessors (lazy-loaded from on-chain state)
  // =========================================================================

  // TODO: OP_NET SDK -- replace with actual StoredAddress / StoredU256 / StoredU64
  private _admin: string = "";           // StoredAddress
  private _price: u64 = 0;              // StoredU256 (placeholder; real impl uses u256)
  private _lastUpdate: u64 = 0;         // StoredU64
  private _updateCount: u64 = 0;        // StoredU256

  // =========================================================================
  // Constructor / Initializer
  // =========================================================================

  /**
   * Called once at deployment. Sets the deployer as the initial admin.
   */
  constructor() {
    // TODO: OP_NET SDK -- read msg.sender / Blockchain.tx.sender
    // this._admin = Blockchain.tx.sender;
    // StoredAddress.store(SLOT_ADMIN, Blockchain.tx.sender);

    this._lastUpdate = 0;
    this._updateCount = 0;
  }

  // =========================================================================
  // Public / External -- Read functions
  // =========================================================================

  /**
   * getPrice(): u256
   *
   * Returns the current BTC/USD price with 18 decimals of precision.
   * Reverts if:
   *   - No price has ever been set (lastUpdate == 0)
   *   - The price is stale (older than STALENESS_THRESHOLD)
   */
  getPrice(): u64 /* u256 */ {
    // TODO: OP_NET SDK -- load from persistent storage
    // const price: u256 = StoredU256.load(SLOT_PRICE);
    // const lastUpdate: u64 = StoredU64.load(SLOT_LAST_UPDATE);

    const lastUpdate = this._lastUpdate;
    const price = this._price;

    // --- Guard: price must have been set at least once ---
    assert(lastUpdate > 0, "Oracle: no price set");

    // --- Guard: staleness check ---
    // TODO: OP_NET SDK -- use Blockchain.block.timestamp
    // const now: u64 = Blockchain.block.timestamp;
    const now: u64 = this._mockTimestamp(); // placeholder
    assert(now - lastUpdate <= STALENESS_THRESHOLD, "Oracle: price is stale");

    return price;
  }

  /**
   * lastUpdate(): u64
   *
   * Returns the block timestamp of the most recent price update.
   */
  lastUpdate(): u64 {
    // TODO: OP_NET SDK -- return StoredU64.load(SLOT_LAST_UPDATE);
    return this._lastUpdate;
  }

  /**
   * updateCount(): u256
   *
   * Returns the total number of price updates that have been performed.
   */
  updateCount(): u64 /* u256 */ {
    // TODO: OP_NET SDK -- return StoredU256.load(SLOT_UPDATE_COUNT);
    return this._updateCount;
  }

  /**
   * admin(): Address
   *
   * Returns the current admin address.
   */
  admin(): string /* Address */ {
    // TODO: OP_NET SDK -- return StoredAddress.load(SLOT_ADMIN);
    return this._admin;
  }

  /**
   * isFresh(): bool
   *
   * Convenience view: returns true if the current price is within the
   * staleness window, false otherwise. Does NOT revert.
   */
  isFresh(): bool {
    const lastUpdate = this._lastUpdate;
    if (lastUpdate == 0) return false;

    // TODO: OP_NET SDK -- use Blockchain.block.timestamp
    const now: u64 = this._mockTimestamp();
    return (now - lastUpdate) <= STALENESS_THRESHOLD;
  }

  // =========================================================================
  // Public / External -- Write functions (Admin-only)
  // =========================================================================

  /**
   * setPrice(price: u256): void
   *
   * Admin-only. Sets the BTC/USD price and records the current block
   * timestamp. Emits PriceUpdated(price, timestamp).
   *
   * @param price  BTC/USD price with 18 decimals (must be > 0)
   */
  setPrice(price: u64 /* u256 */): void {
    this._onlyAdmin();

    // --- Guard: price must be positive ---
    assert(price > 0, "Oracle: price must be > 0");

    // TODO: OP_NET SDK -- use Blockchain.block.timestamp
    const now: u64 = this._mockTimestamp();

    // --- V2 TWAP: update cumulative price before overwriting ---
    // TODO: V2 TWAP -- accumulate price * elapsed time
    // this._updateTWAPCumulative(now);

    // --- Store new price and timestamp ---
    // TODO: OP_NET SDK -- persistent storage writes
    // StoredU256.store(SLOT_PRICE, price);
    // StoredU64.store(SLOT_LAST_UPDATE, now);
    // StoredU256.store(SLOT_UPDATE_COUNT, StoredU256.load(SLOT_UPDATE_COUNT) + u256.One);

    this._price = price;
    this._lastUpdate = now;
    this._updateCount += 1;

    // --- Emit event ---
    // TODO: OP_NET SDK -- emit PriceUpdated event
    // Blockchain.emit(EVENT_PRICE_UPDATED, [price, u256.fromU64(now)]);
  }

  /**
   * transferAdmin(newAdmin: Address): void
   *
   * Admin-only. Transfers the admin role to a new address.
   * The new admin address must not be zero.
   */
  transferAdmin(newAdmin: string /* Address */): void {
    this._onlyAdmin();

    // --- Guard: new admin must not be zero address ---
    assert(newAdmin.length > 0, "Oracle: zero address");

    // TODO: OP_NET SDK -- persistent storage write
    // const oldAdmin = StoredAddress.load(SLOT_ADMIN);
    // StoredAddress.store(SLOT_ADMIN, newAdmin);
    // Blockchain.emit(EVENT_ADMIN_TRANSFERRED, [oldAdmin, newAdmin]);

    this._admin = newAdmin;
  }

  // =========================================================================
  // V2 TWAP -- Time-Weighted Average Price (planned)
  // =========================================================================

  /**
   * TODO: V2 TWAP -- getTWAP(window: u64): u256
   *
   * Returns the time-weighted average price over the specified window.
   * Uses cumulative price observations recorded on every setPrice() call
   * and, in V2, from DEX pair sync events.
   *
   * Implementation sketch:
   *   1. Load current cumulative price and timestamp.
   *   2. Load the observation closest to (now - window).
   *   3. TWAP = (cumulativeNow - cumulativeOld) / (timestampNow - timestampOld)
   *
   * For CauldronV2, a 30-minute TWAP window is required.
   */
  // getTWAP(window: u64 = 1800): u256 {
  //   // TODO: OP_NET SDK -- implement observation ring buffer
  //   // const observations = this._loadObservations();
  //   // ... binary search for oldest observation within window ...
  //   // return (cumCurrent - cumOld) / (tsCurrent - tsOld);
  // }

  /**
   * TODO: V2 TWAP -- _updateTWAPCumulative(now: u64): void
   *
   * Internal helper called by setPrice() to accumulate
   * (currentPrice * elapsed) into the cumulative price slot.
   */
  // private _updateTWAPCumulative(now: u64): void {
  //   const lastTs = StoredU64.load(SLOT_TWAP_LAST_TIMESTAMP);
  //   if (lastTs > 0) {
  //     const elapsed = now - lastTs;
  //     const currentPrice = StoredU256.load(SLOT_PRICE);
  //     const cumulative = StoredU256.load(SLOT_TWAP_CUMULATIVE);
  //     StoredU256.store(SLOT_TWAP_CUMULATIVE, cumulative + currentPrice * u256.fromU64(elapsed));
  //   }
  //   StoredU64.store(SLOT_TWAP_LAST_TIMESTAMP, now);
  // }

  /**
   * TODO: V2 TWAP -- Observation ring buffer
   *
   * For production TWAP, a ring buffer of (timestamp, cumulativePrice)
   * observations is needed. This allows computing TWAP over arbitrary
   * windows without requiring the caller to track historical state.
   *
   * struct Observation {
   *   timestamp: u64;
   *   cumulativePrice: u256;
   * }
   *
   * Storage layout:
   *   SLOT_OBSERVATIONS_LENGTH  -- u64, number of observations stored
   *   SLOT_OBSERVATIONS_INDEX   -- u64, current write index (circular)
   *   SLOT_OBSERVATIONS_BASE + i * 2     -- timestamp of observation i
   *   SLOT_OBSERVATIONS_BASE + i * 2 + 1 -- cumulativePrice of observation i
   *
   * Max observations: 48 (covers 24h at 30-min intervals)
   */

  /**
   * TODO: V2 DEX Integration
   *
   * When OP_NET DEX pairs are available, the oracle can be upgraded to
   * pull price from on-chain liquidity pools (e.g., BTC/MIF pair).
   *
   * The flow:
   *   1. On each swap/sync in the DEX pair, update the cumulative price.
   *   2. Oracle reads the pair's cumulative price and computes TWAP.
   *   3. Admin-set price becomes a fallback or sanity-check bound.
   *
   * This makes the oracle decentralized and resistant to single-admin
   * manipulation.
   */

  // =========================================================================
  // Internal helpers
  // =========================================================================

  /**
   * _onlyAdmin(): void
   *
   * Reverts if the caller is not the current admin.
   */
  private _onlyAdmin(): void {
    // TODO: OP_NET SDK -- compare Blockchain.tx.sender with stored admin
    // const admin = StoredAddress.load(SLOT_ADMIN);
    // assert(Blockchain.tx.sender == admin, "Oracle: caller is not admin");
  }

  /**
   * _mockTimestamp(): u64
   *
   * Placeholder for Blockchain.block.timestamp until OP_NET SDK is integrated.
   */
  private _mockTimestamp(): u64 {
    // TODO: OP_NET SDK -- replace with Blockchain.block.timestamp
    return 0;
  }

  // =========================================================================
  // Calldata router (OP_NET entry point)
  // =========================================================================

  /**
   * TODO: OP_NET SDK -- implement the calldata router
   *
   * OP_NET contracts receive raw calldata and must decode the function
   * selector + arguments. This is the main entry point.
   *
   * export function execute(calldata: Calldata): BytesWriter {
   *   const selector = calldata.readSelector();
   *
   *   switch (selector) {
   *     case encodeSelector("getPrice()"):
   *       return oracle.getPrice().toBytes();
   *
   *     case encodeSelector("setPrice(u256)"):
   *       const price = calldata.readU256();
   *       oracle.setPrice(price);
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("lastUpdate()"):
   *       return u256.fromU64(oracle.lastUpdate()).toBytes();
   *
   *     case encodeSelector("updateCount()"):
   *       return oracle.updateCount().toBytes();
   *
   *     case encodeSelector("admin()"):
   *       return oracle.admin().toBytes();
   *
   *     case encodeSelector("isFresh()"):
   *       return u256.fromBool(oracle.isFresh()).toBytes();
   *
   *     case encodeSelector("transferAdmin(address)"):
   *       const newAdmin = calldata.readAddress();
   *       oracle.transferAdmin(newAdmin);
   *       return BytesWriter.empty();
   *
   *     default:
   *       throw new Error("Oracle: unknown selector");
   *   }
   * }
   */
}
