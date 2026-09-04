/**
 * CauldronV2.ts -- Phase 2: Partial Collateral + Seigniorage
 * =============================================================
 * Target: OP_NET (Bitcoin L1) -- AssemblyScript Smart Contract
 *
 * Extends Cauldron V1 with:
 *
 *   1. TCR (Target Collateral Ratio): Governance-adjustable ratio that
 *      determines how much BTC vs FREN is required to mint MIF.
 *      - Starts at 100% (fully BTC-backed)
 *      - Floor: 75% (hard minimum, never drops below)
 *      - Adjustment: max 0.5% per day
 *
 *   2. Partial FREN Minting: Users deposit (TCR%) BTC + (1-TCR%) FREN
 *      to mint MIF. As TCR decreases, more FREN is burned and less BTC
 *      is locked, creating seigniorage for the protocol.
 *
 *   3. Redemption: Burn MIF to receive (ECR%) BTC + (1-ECR%) newly minted FREN.
 *      ECR = Effective Collateral Ratio = actual BTC reserves / total MIF supply.
 *
 *   4. FREN Daily Mint Cap: Max 2% of FREN total supply can be minted per day
 *      through redemptions. Prevents hyperinflation spirals.
 *
 *   5. Circuit Breaker: Pauses minting/redemption if FREN drops >30% in 24h.
 *      Uses price snapshot tracking to detect rapid price declines.
 *
 *   6. TWAP Oracle: Uses 30-minute TWAP (not spot) for all price calculations.
 *
 * This contract inherits all Cauldron V1 functionality (deposit, borrow,
 * repay, withdraw, liquidate, cook, accrue) and adds the V2 minting and
 * redemption mechanics on top.
 */

// TODO: OP_NET SDK -- import the OP_NET runtime
// import {
//   Blockchain,
//   BytesWriter,
//   Calldata,
//   encodeSelector,
//   Map,
//   StoredU256,
//   StoredU64,
//   StoredAddress,
//   StoredMap,
//   Address,
//   u256,
// } from "@opnet/btc-runtime";

// Import Cauldron V1 base (all V1 functionality is inherited)
import { Cauldron } from "./Cauldron";

// ---------------------------------------------------------------------------
// Constants -- V2 Protocol Parameters
// ---------------------------------------------------------------------------

/** Basis points denominator */
const BPS: u64 = 10_000;

/** Initial TCR: 100% => 10000 BPS (fully BTC-backed at launch) */
const INITIAL_TCR_BPS: u64 = 10_000;

/** TCR Floor: 75% => 7500 BPS (hard minimum, governance cannot go below) */
const TCR_FLOOR_BPS: u64 = 7_500;

/** Max TCR adjustment per day: 0.5% => 50 BPS */
const MAX_TCR_ADJUSTMENT_PER_DAY_BPS: u64 = 50;

/** FREN daily mint cap: 2% of total supply => 200 BPS */
const FREN_DAILY_MINT_CAP_BPS: u64 = 200;

/** Circuit breaker threshold: 30% drop => 3000 BPS */
const CIRCUIT_BREAKER_DROP_BPS: u64 = 3_000;

/** Circuit breaker observation window: 24 hours in seconds */
const CIRCUIT_BREAKER_WINDOW: u64 = 86_400;

/** TWAP window for oracle: 30 minutes in seconds */
const TWAP_WINDOW: u64 = 1_800;

/** Seconds in a day */
const SECONDS_PER_DAY: u64 = 86_400;

/** 18-decimal precision multiplier: 10^18 */
const PRECISION_U64: u64 = 1_000_000_000_000_000_000;

/** Number of price snapshots to keep (one every 30 min for 24h = 48) */
const MAX_PRICE_SNAPSHOTS: u64 = 48;

/** Snapshot interval: 30 minutes */
const SNAPSHOT_INTERVAL: u64 = 1_800;

// ---------------------------------------------------------------------------
// V2 Storage slot keys (offset from V1 slots to avoid collision)
// ---------------------------------------------------------------------------

const SLOT_V2_TCR:                    u64 = 500;  // u64  -- current TCR in BPS
const SLOT_V2_TCR_LAST_ADJUST_TS:    u64 = 501;  // u64  -- timestamp of last TCR adjustment
const SLOT_V2_TCR_LAST_ADJUST_DIR:   u64 = 502;  // u64  -- 0 = decrease, 1 = increase

const SLOT_V2_BTC_RESERVES:          u64 = 510;  // u256 -- total BTC reserves (satoshis) for V2 minting
const SLOT_V2_MIF_SUPPLY:            u64 = 511;  // u256 -- total MIF supply minted via V2

const SLOT_V2_FREN_MINTED_TODAY:     u64 = 520;  // u256 -- FREN minted today via redemptions
const SLOT_V2_FREN_MINT_DAY:         u64 = 521;  // u64  -- day number for mint cap tracking

const SLOT_V2_CIRCUIT_BREAKER:       u64 = 530;  // u64  -- 0 = normal, 1 = tripped
const SLOT_V2_CIRCUIT_BREAKER_TS:    u64 = 531;  // u64  -- timestamp when breaker was tripped

// Price snapshots ring buffer
const SLOT_V2_SNAPSHOTS_INDEX:       u64 = 540;  // u64  -- current write index
const SLOT_V2_SNAPSHOTS_COUNT:       u64 = 541;  // u64  -- total snapshots recorded
const SLOT_V2_SNAPSHOT_LAST_TS:      u64 = 542;  // u64  -- timestamp of last snapshot
const SLOT_V2_SNAPSHOTS_BASE:        u64 = 600;  // base slot for snapshot data
// Each snapshot occupies 2 slots: [timestamp: u64, price: u256]
// SLOT_V2_SNAPSHOTS_BASE + i*2     = timestamp
// SLOT_V2_SNAPSHOTS_BASE + i*2 + 1 = FREN price (u256, 18 decimals)

// ---------------------------------------------------------------------------
// V2 Event selectors
// ---------------------------------------------------------------------------

// TODO: OP_NET SDK -- define event selectors
// const EVENT_V2_MINT              = encodeSelector("V2Mint(address,u256,u256,u256)");
// const EVENT_V2_REDEEM            = encodeSelector("V2Redeem(address,u256,u256,u256)");
// const EVENT_TCR_ADJUSTED         = encodeSelector("TCRAdjusted(u64,u64)");
// const EVENT_CIRCUIT_BREAKER_TRIP = encodeSelector("CircuitBreakerTripped(u256,u256)");
// const EVENT_CIRCUIT_BREAKER_RESET= encodeSelector("CircuitBreakerReset()");

// ---------------------------------------------------------------------------
// Price Snapshot struct
// ---------------------------------------------------------------------------

class PriceSnapshot {
  timestamp: u64 = 0;
  frenPrice: u64 = 0; // u256 -- FREN/USD with 18 decimals
}

// ---------------------------------------------------------------------------
// CauldronV2 Contract
// ---------------------------------------------------------------------------

// TODO: OP_NET SDK -- extend Cauldron (which extends Contract)
// export class CauldronV2 extends Cauldron {

export class CauldronV2 extends Cauldron {

  // =========================================================================
  // V2 State (in-memory placeholders for OP_NET StoredU256 / StoredMap)
  // =========================================================================

  /** Current Target Collateral Ratio in BPS */
  private _tcrBPS: u64 = INITIAL_TCR_BPS;

  /** Timestamp of the last TCR adjustment */
  private _tcrLastAdjustTimestamp: u64 = 0;

  /** Total BTC reserves held for V2 minting (satoshis) */
  private _btcReserves: u64 = 0; // u256

  /** Total MIF supply minted through V2 mechanism */
  private _v2MifSupply: u64 = 0; // u256

  /** FREN minted today (for daily cap tracking) */
  private _frenMintedToday: u64 = 0; // u256

  /** Day number for FREN mint cap reset */
  private _frenMintDay: u64 = 0;

  /** Circuit breaker state: false = normal, true = tripped */
  private _circuitBreakerTripped: bool = false;

  /** Timestamp when circuit breaker was tripped */
  private _circuitBreakerTimestamp: u64 = 0;

  /** Price snapshots ring buffer */
  private _priceSnapshots: PriceSnapshot[] = [];
  private _snapshotIndex: u64 = 0;
  private _snapshotCount: u64 = 0;
  private _lastSnapshotTimestamp: u64 = 0;

  // =========================================================================
  // Constructor
  // =========================================================================

  constructor(
    oracle: string = "",
    mifToken: string = "",
    nftContract: string = "",
    frenToken: string = "",
    sFrenStaking: string = ""
  ) {
    super(oracle, mifToken, nftContract, frenToken, sFrenStaking);

    this._tcrBPS = INITIAL_TCR_BPS;
    this._tcrLastAdjustTimestamp = this._mockTimestamp();

    // Initialize price snapshot buffer
    for (let i: u64 = 0; i < MAX_PRICE_SNAPSHOTS; i++) {
      this._priceSnapshots.push(new PriceSnapshot());
    }

    // TODO: OP_NET SDK -- persist V2 initial state to storage
    // StoredU64.store(SLOT_V2_TCR, INITIAL_TCR_BPS);
    // StoredU64.store(SLOT_V2_TCR_LAST_ADJUST_TS, Blockchain.block.timestamp);
  }

  // =========================================================================
  // V2 Core Functions -- Mint / Redeem
  // =========================================================================

  /**
   * mintV2(btcAmount: u256, frenAmount: u256, mifOut: u256): void
   *
   * Mint MIF using partial BTC collateral + partial FREN burn.
   *
   * The user provides:
   *   - btcAmount:  BTC in satoshis (must be >= TCR% of the total MIF value)
   *   - frenAmount: FREN to burn (must be >= (1-TCR%) of the total MIF value)
   *   - mifOut:     desired MIF output amount (18 decimals)
   *
   * Requirements:
   *   - Circuit breaker must not be tripped
   *   - btcAmount >= TCR% of mifOut (valued at BTC/USD price)
   *   - frenAmount >= (1-TCR%) of mifOut (valued at FREN/USD TWAP)
   *   - Uses 30-minute TWAP oracle for all price lookups
   *
   * @param btcAmount  BTC collateral to lock (satoshis)
   * @param frenAmount FREN to burn (18 decimals)
   * @param mifOut     MIF amount to mint (18 decimals)
   */
  mintV2(
    btcAmount: u64 /* u256 */,
    frenAmount: u64 /* u256 */,
    mifOut: u64 /* u256 */
  ): void {
    this._nonReentrant_enter_v2();
    this._whenNotPaused_v2();
    this._whenCircuitBreakerNotTripped();

    assert(mifOut > 0, "CauldronV2: mifOut must be > 0");

    // --- Record price snapshot if enough time has passed ---
    this._maybeRecordSnapshot();

    // --- Check circuit breaker (may trip if FREN dropped >30%) ---
    this._checkCircuitBreaker();
    // Re-check after potential trip
    this._whenCircuitBreakerNotTripped();

    // --- Get prices from TWAP oracle ---
    const btcPriceUSD = this._getBTCPriceTWAP();   // u256, 18 dec
    const frenPriceUSD = this._getFRENPriceTWAP();  // u256, 18 dec

    // --- Calculate required BTC and FREN ---
    // Required BTC value = TCR% of mifOut
    // Required FREN value = (1 - TCR%) of mifOut
    const requiredBTCValue: u64 = (mifOut * this._tcrBPS) / BPS;      // MIF value in USD terms
    const requiredFRENValue: u64 = mifOut - requiredBTCValue;          // remainder in FREN

    // --- Convert required values to token amounts ---
    // btcRequired (sats) = requiredBTCValue * 10^8 / btcPriceUSD
    // frenRequired (18 dec) = requiredFRENValue * 10^18 / frenPriceUSD
    // NOTE: Exact math with u256 in production
    // TODO: OP_NET SDK -- use u256 arithmetic for precision

    assert(btcPriceUSD > 0, "CauldronV2: BTC price is zero");

    // Validate the user provided enough BTC
    const btcValueProvided: u64 = this._satoshisToUSDValue(btcAmount, btcPriceUSD);
    assert(btcValueProvided >= requiredBTCValue, "CauldronV2: insufficient BTC for TCR");

    // Validate the user provided enough FREN (if TCR < 100%)
    if (requiredFRENValue > 0) {
      assert(frenPriceUSD > 0, "CauldronV2: FREN price is zero");
      const frenValueProvided: u64 = this._frenToUSDValue(frenAmount, frenPriceUSD);
      assert(frenValueProvided >= requiredFRENValue, "CauldronV2: insufficient FREN for mint");
    }

    // --- Transfer BTC from caller to reserves ---
    // TODO: OP_NET SDK -- BTC transfer
    // Blockchain.transferBTC(Blockchain.tx.sender, address(this), btcAmount);
    this._btcReserves += btcAmount;

    // --- Burn FREN from caller ---
    if (frenAmount > 0) {
      // TODO: OP_NET SDK -- call FREN token burn
      // IFRENToken(this._frenTokenAddress).burn(Blockchain.tx.sender, frenAmount);
    }

    // --- Mint MIF to caller ---
    // TODO: OP_NET SDK -- call MIF token mint
    // IMIFToken(this._mifTokenAddress).mint(Blockchain.tx.sender, mifOut);
    this._v2MifSupply += mifOut;

    // --- Persist ---
    // TODO: OP_NET SDK -- persist all storage updates

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_V2_MINT, [caller, mifOut, btcAmount, frenAmount]);

    this._nonReentrant_exit_v2();
  }

  /**
   * redeemV2(mifAmount: u256): void
   *
   * Burn MIF to receive back:
   *   - ECR% of the value in BTC
   *   - (1 - ECR%) of the value in newly minted FREN
   *
   * ECR (Effective Collateral Ratio) = actual BTC reserves / total MIF supply
   *
   * If ECR >= 100%, redeemer gets full BTC value (no FREN minted).
   * If ECR < 100%, the shortfall is covered by minting new FREN.
   *
   * FREN mint is subject to the daily 2% cap. If the cap is reached,
   * remaining redemptions in the same day will revert.
   *
   * @param mifAmount  MIF amount to burn/redeem (18 decimals)
   */
  redeemV2(mifAmount: u64 /* u256 */): void {
    this._nonReentrant_enter_v2();
    this._whenNotPaused_v2();
    this._whenCircuitBreakerNotTripped();

    assert(mifAmount > 0, "CauldronV2: redeem amount must be > 0");

    // --- Record price snapshot if enough time has passed ---
    this._maybeRecordSnapshot();

    // --- Check circuit breaker ---
    this._checkCircuitBreaker();
    this._whenCircuitBreakerNotTripped();

    // --- Calculate ECR ---
    const ecrBPS = this._calculateECR();

    // --- Get prices ---
    const btcPriceUSD = this._getBTCPriceTWAP();
    const frenPriceUSD = this._getFRENPriceTWAP();

    // --- Calculate BTC and FREN redemption amounts ---
    // BTC value to return = ECR% of mifAmount (capped at 100%)
    const ecrCapped: u64 = ecrBPS > BPS ? BPS : ecrBPS;
    const btcValueToReturn: u64 = (mifAmount * ecrCapped) / BPS;
    const frenValueToMint: u64 = mifAmount - btcValueToReturn;

    // --- Convert BTC value to satoshis ---
    // btcSats = btcValueToReturn * 10^8 / btcPriceUSD
    assert(btcPriceUSD > 0, "CauldronV2: BTC price is zero");
    const btcSatsToReturn: u64 = this._usdValueToSatoshis(btcValueToReturn, btcPriceUSD);

    assert(btcSatsToReturn <= this._btcReserves, "CauldronV2: insufficient BTC reserves");

    // --- Calculate FREN to mint ---
    let frenToMint: u64 = 0;
    if (frenValueToMint > 0) {
      assert(frenPriceUSD > 0, "CauldronV2: FREN price is zero");
      frenToMint = this._usdValueToFREN(frenValueToMint, frenPriceUSD);

      // --- Check FREN daily mint cap: 2% of total supply ---
      this._resetDailyMintCapIfNeeded();
      const frenTotalSupply = this._getFRENTotalSupply();
      const dailyCap: u64 = (frenTotalSupply * FREN_DAILY_MINT_CAP_BPS) / BPS;
      assert(
        this._frenMintedToday + frenToMint <= dailyCap,
        "CauldronV2: FREN daily mint cap exceeded (2% of supply)"
      );
      this._frenMintedToday += frenToMint;
    }

    // --- Burn MIF from caller ---
    // TODO: OP_NET SDK -- call MIF token burn
    // IMIFToken(this._mifTokenAddress).burn(Blockchain.tx.sender, mifAmount);
    this._v2MifSupply -= mifAmount;

    // --- Transfer BTC to caller ---
    // TODO: OP_NET SDK -- BTC transfer
    // Blockchain.transferBTC(address(this), Blockchain.tx.sender, btcSatsToReturn);
    this._btcReserves -= btcSatsToReturn;

    // --- Mint FREN to caller (if any) ---
    if (frenToMint > 0) {
      // TODO: OP_NET SDK -- call FREN token mint
      // IFRENToken(this._frenTokenAddress).mint(Blockchain.tx.sender, frenToMint);
    }

    // --- Persist ---
    // TODO: OP_NET SDK -- persist all storage updates

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_V2_REDEEM, [caller, mifAmount, btcSatsToReturn, frenToMint]);

    this._nonReentrant_exit_v2();
  }

  // =========================================================================
  // TCR Management (Governance)
  // =========================================================================

  /**
   * adjustTCR(newTCR_BPS: u64): void
   *
   * Governance function to adjust the Target Collateral Ratio.
   *
   * Constraints:
   *   - Caller must be admin (governance)
   *   - newTCR >= TCR_FLOOR (75%)
   *   - newTCR <= 100% (10000 BPS)
   *   - Change from current TCR must be <= 0.5% (50 BPS) per day
   *   - At least 24 hours must have passed since the last adjustment
   *
   * @param newTCR_BPS  The new TCR value in basis points
   */
  adjustTCR(newTCR_BPS: u64): void {
    this._onlyAdmin_v2();

    // --- Validate range ---
    assert(newTCR_BPS >= TCR_FLOOR_BPS, "CauldronV2: TCR below floor (75%)");
    assert(newTCR_BPS <= BPS, "CauldronV2: TCR above 100%");

    // --- Validate timing: at least 24 hours since last adjustment ---
    const now: u64 = this._mockTimestamp_v2();
    const timeSinceLastAdjust = now - this._tcrLastAdjustTimestamp;
    assert(
      timeSinceLastAdjust >= SECONDS_PER_DAY,
      "CauldronV2: TCR can only be adjusted once per day"
    );

    // --- Validate magnitude: max 0.5% change per day ---
    let delta: u64;
    if (newTCR_BPS > this._tcrBPS) {
      delta = newTCR_BPS - this._tcrBPS;
    } else {
      delta = this._tcrBPS - newTCR_BPS;
    }
    assert(
      delta <= MAX_TCR_ADJUSTMENT_PER_DAY_BPS,
      "CauldronV2: TCR adjustment exceeds 0.5% per day"
    );

    // --- Apply ---
    const oldTCR = this._tcrBPS;
    this._tcrBPS = newTCR_BPS;
    this._tcrLastAdjustTimestamp = now;

    // TODO: OP_NET SDK -- persist
    // StoredU64.store(SLOT_V2_TCR, newTCR_BPS);
    // StoredU64.store(SLOT_V2_TCR_LAST_ADJUST_TS, now);

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_TCR_ADJUSTED, [oldTCR, newTCR_BPS]);
  }

  // =========================================================================
  // Circuit Breaker
  // =========================================================================

  /**
   * _checkCircuitBreaker(): void
   *
   * Checks if FREN price has dropped more than 30% in the last 24 hours.
   * If so, trips the circuit breaker which pauses V2 minting and redemption.
   *
   * Uses the price snapshot ring buffer to compare current price against
   * the price 24 hours ago.
   */
  private _checkCircuitBreaker(): void {
    if (this._circuitBreakerTripped) return; // already tripped

    const currentPrice = this._getFRENPriceTWAP();
    if (currentPrice == 0) return; // no price available

    // Find the oldest snapshot within the 24h window
    const price24hAgo = this._getSnapshotPrice24hAgo();
    if (price24hAgo == 0) return; // not enough history

    // Check if price dropped > 30%
    // drop% = (price24hAgo - currentPrice) / price24hAgo * 10000
    if (currentPrice >= price24hAgo) return; // price went up, no concern

    const dropBPS: u64 = ((price24hAgo - currentPrice) * BPS) / price24hAgo;

    if (dropBPS > CIRCUIT_BREAKER_DROP_BPS) {
      // --- TRIP THE CIRCUIT BREAKER ---
      this._circuitBreakerTripped = true;
      this._circuitBreakerTimestamp = this._mockTimestamp_v2();

      // TODO: OP_NET SDK -- persist
      // StoredU64.store(SLOT_V2_CIRCUIT_BREAKER, 1);
      // StoredU64.store(SLOT_V2_CIRCUIT_BREAKER_TS, now);

      // --- Emit event ---
      // TODO: OP_NET SDK -- Blockchain.emit(EVENT_CIRCUIT_BREAKER_TRIP, [price24hAgo, currentPrice]);
    }
  }

  /**
   * resetCircuitBreaker(): void
   *
   * Admin-only function to manually reset the circuit breaker after
   * the situation has been assessed. This is an emergency governance action.
   *
   * In production, consider adding a time-lock or multi-sig requirement.
   */
  resetCircuitBreaker(): void {
    this._onlyAdmin_v2();
    assert(this._circuitBreakerTripped, "CauldronV2: circuit breaker not tripped");

    this._circuitBreakerTripped = false;
    this._circuitBreakerTimestamp = 0;

    // TODO: OP_NET SDK -- persist
    // StoredU64.store(SLOT_V2_CIRCUIT_BREAKER, 0);
    // StoredU64.store(SLOT_V2_CIRCUIT_BREAKER_TS, 0);

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_CIRCUIT_BREAKER_RESET, []);
  }

  // =========================================================================
  // Price Snapshots (for circuit breaker)
  // =========================================================================

  /**
   * _maybeRecordSnapshot(): void
   *
   * Records a FREN price snapshot if at least SNAPSHOT_INTERVAL (30 min)
   * has passed since the last snapshot. Uses a ring buffer of 48 entries
   * (covers 24 hours).
   */
  private _maybeRecordSnapshot(): void {
    const now = this._mockTimestamp_v2();
    if (now - this._lastSnapshotTimestamp < SNAPSHOT_INTERVAL) return;

    const frenPrice = this._getFRENPriceTWAP();
    if (frenPrice == 0) return; // no price available, skip

    // Write to ring buffer
    const idx = this._snapshotIndex % MAX_PRICE_SNAPSHOTS;
    if (idx < <u64>this._priceSnapshots.length) {
      this._priceSnapshots[<i32>idx].timestamp = now;
      this._priceSnapshots[<i32>idx].frenPrice = frenPrice;
    }

    this._snapshotIndex++;
    if (this._snapshotCount < MAX_PRICE_SNAPSHOTS) {
      this._snapshotCount++;
    }
    this._lastSnapshotTimestamp = now;

    // TODO: OP_NET SDK -- persist snapshot to storage
    // StoredU64.store(SLOT_V2_SNAPSHOTS_BASE + idx * 2, now);
    // StoredU256.store(SLOT_V2_SNAPSHOTS_BASE + idx * 2 + 1, frenPrice);
    // StoredU64.store(SLOT_V2_SNAPSHOTS_INDEX, this._snapshotIndex);
    // StoredU64.store(SLOT_V2_SNAPSHOTS_COUNT, this._snapshotCount);
    // StoredU64.store(SLOT_V2_SNAPSHOT_LAST_TS, now);
  }

  /**
   * _getSnapshotPrice24hAgo(): u64
   *
   * Returns the FREN price from approximately 24 hours ago by searching
   * the ring buffer for the closest snapshot to (now - 24h).
   * Returns 0 if no suitable snapshot is found.
   */
  private _getSnapshotPrice24hAgo(): u64 /* u256 */ {
    if (this._snapshotCount == 0) return 0;

    const now = this._mockTimestamp_v2();
    const targetTs = now > CIRCUIT_BREAKER_WINDOW ? now - CIRCUIT_BREAKER_WINDOW : 0;

    let bestPrice: u64 = 0;
    let bestDelta: u64 = u64.MAX_VALUE;

    // Scan all snapshots to find the one closest to targetTs
    const count = this._snapshotCount < MAX_PRICE_SNAPSHOTS
      ? this._snapshotCount
      : MAX_PRICE_SNAPSHOTS;

    for (let i: u64 = 0; i < count; i++) {
      const snap = this._priceSnapshots[<i32>i];
      if (snap.timestamp == 0) continue;

      let delta: u64;
      if (snap.timestamp > targetTs) {
        delta = snap.timestamp - targetTs;
      } else {
        delta = targetTs - snap.timestamp;
      }

      if (delta < bestDelta) {
        bestDelta = delta;
        bestPrice = snap.frenPrice;
      }
    }

    // Only accept if the snapshot is within a reasonable range (6 hours tolerance)
    if (bestDelta > SECONDS_PER_DAY / 4) return 0;

    return bestPrice;
  }

  // =========================================================================
  // ECR Calculation
  // =========================================================================

  /**
   * _calculateECR(): u64
   *
   * ECR (Effective Collateral Ratio) = BTC reserves value / total MIF supply
   *
   * Returns in BPS (10000 = 100%). Can exceed 10000 if over-collateralized.
   * Returns 10000 if no MIF supply (fully collateralized by definition).
   */
  private _calculateECR(): u64 {
    if (this._v2MifSupply == 0) return BPS; // 100%

    const btcPriceUSD = this._getBTCPriceTWAP();
    const reserveValueUSD = this._satoshisToUSDValue(this._btcReserves, btcPriceUSD);

    if (reserveValueUSD == 0) return 0;

    return (reserveValueUSD * BPS) / this._v2MifSupply;
  }

  /**
   * getECR(): u64
   *
   * Public view: returns the current Effective Collateral Ratio in BPS.
   */
  getECR(): u64 {
    return this._calculateECR();
  }

  /**
   * getTCR(): u64
   *
   * Public view: returns the current Target Collateral Ratio in BPS.
   */
  getTCR(): u64 {
    return this._tcrBPS;
  }

  /**
   * isCircuitBreakerTripped(): bool
   *
   * Public view: returns whether the circuit breaker is currently active.
   */
  isCircuitBreakerTripped(): bool {
    return this._circuitBreakerTripped;
  }

  /**
   * btcReserves(): u64
   *
   * Public view: total BTC reserves (satoshis).
   */
  btcReserves(): u64 {
    return this._btcReserves;
  }

  /**
   * v2MifSupply(): u64
   *
   * Public view: total MIF minted via V2 mechanism.
   */
  v2MifSupply(): u64 {
    return this._v2MifSupply;
  }

  /**
   * frenMintedToday(): u64
   *
   * Public view: FREN minted today through redemptions.
   */
  frenMintedToday(): u64 {
    return this._frenMintedToday;
  }

  /**
   * frenDailyMintCapRemaining(): u64
   *
   * Public view: how much FREN can still be minted today.
   */
  frenDailyMintCapRemaining(): u64 {
    this._resetDailyMintCapIfNeeded();
    const frenTotalSupply = this._getFRENTotalSupply();
    const dailyCap: u64 = (frenTotalSupply * FREN_DAILY_MINT_CAP_BPS) / BPS;
    if (this._frenMintedToday >= dailyCap) return 0;
    return dailyCap - this._frenMintedToday;
  }

  // =========================================================================
  // Internal -- TWAP Oracle Integration
  // =========================================================================

  /**
   * _getBTCPriceTWAP(): u64
   *
   * Returns the BTC/USD price using a 30-minute TWAP from the oracle.
   * In V1, falls back to spot price if TWAP is not available.
   */
  private _getBTCPriceTWAP(): u64 /* u256 */ {
    // TODO: OP_NET SDK -- call Oracle contract with TWAP window
    // try {
    //   return IOracle(this._oracleAddress).getTWAP(TWAP_WINDOW);
    // } catch {
    //   // Fallback to spot price if TWAP not available (V1 oracle)
    //   return IOracle(this._oracleAddress).getPrice();
    // }

    // Placeholder
    return 60_000; // $60,000 mock
  }

  /**
   * _getFRENPriceTWAP(): u64
   *
   * Returns the FREN/USD price using a 30-minute TWAP.
   * This requires a separate FREN price oracle or DEX pair.
   */
  private _getFRENPriceTWAP(): u64 /* u256 */ {
    // TODO: OP_NET SDK -- call FREN price oracle or DEX pair TWAP
    // return IFRENOracle(this._frenOracleAddress).getTWAP(TWAP_WINDOW);

    // Placeholder
    return 1; // $1.00 mock
  }

  // =========================================================================
  // Internal -- Value Conversions
  // =========================================================================

  /**
   * _satoshisToUSDValue(sats, btcPrice): u64
   *
   * Converts satoshis to USD value (18 decimals).
   * value = sats * btcPrice / 10^8
   */
  private _satoshisToUSDValue(sats: u64 /* u256 */, btcPriceUSD: u64 /* u256 */): u64 /* u256 */ {
    // TODO: OP_NET SDK -- use u256 math for precision
    // return (u256.fromU64(sats) * btcPriceUSD) / u256.fromU64(100_000_000);
    return (sats * btcPriceUSD) / 100_000_000;
  }

  /**
   * _usdValueToSatoshis(usdValue, btcPrice): u64
   *
   * Converts USD value (18 decimals) to satoshis.
   * sats = usdValue * 10^8 / btcPrice
   */
  private _usdValueToSatoshis(usdValue: u64 /* u256 */, btcPriceUSD: u64 /* u256 */): u64 /* u256 */ {
    // TODO: OP_NET SDK -- use u256 math
    // return (usdValue * u256.fromU64(100_000_000)) / btcPriceUSD;
    if (btcPriceUSD == 0) return 0;
    return (usdValue * 100_000_000) / btcPriceUSD;
  }

  /**
   * _frenToUSDValue(frenAmount, frenPrice): u64
   *
   * Converts FREN amount (18 decimals) to USD value (18 decimals).
   * value = frenAmount * frenPrice / 10^18
   */
  private _frenToUSDValue(frenAmount: u64 /* u256 */, frenPriceUSD: u64 /* u256 */): u64 /* u256 */ {
    // TODO: OP_NET SDK -- use u256 math
    // return (u256.fromU64(frenAmount) * frenPriceUSD) / PRECISION;
    return (frenAmount * frenPriceUSD) / PRECISION_U64;
  }

  /**
   * _usdValueToFREN(usdValue, frenPrice): u64
   *
   * Converts USD value (18 decimals) to FREN amount (18 decimals).
   * fren = usdValue * 10^18 / frenPrice
   */
  private _usdValueToFREN(usdValue: u64 /* u256 */, frenPriceUSD: u64 /* u256 */): u64 /* u256 */ {
    // TODO: OP_NET SDK -- use u256 math
    // return (usdValue * PRECISION) / frenPriceUSD;
    if (frenPriceUSD == 0) return 0;
    return (usdValue * PRECISION_U64) / frenPriceUSD;
  }

  // =========================================================================
  // Internal -- FREN Supply Query
  // =========================================================================

  /**
   * _getFRENTotalSupply(): u64
   *
   * Returns the current total supply of the FREN token.
   */
  private _getFRENTotalSupply(): u64 /* u256 */ {
    // TODO: OP_NET SDK -- call FREN token totalSupply()
    // return IFRENToken(this._frenTokenAddress).totalSupply();

    return 1_000_000; // 1M mock
  }

  // =========================================================================
  // Internal -- Daily Mint Cap Reset
  // =========================================================================

  /**
   * _resetDailyMintCapIfNeeded(): void
   *
   * Resets the FREN minted-today counter if a new day has started.
   * Day boundary is determined by integer division of timestamp by SECONDS_PER_DAY.
   */
  private _resetDailyMintCapIfNeeded(): void {
    const now = this._mockTimestamp_v2();
    const currentDay: u64 = now / SECONDS_PER_DAY;

    if (currentDay > this._frenMintDay) {
      this._frenMintDay = currentDay;
      this._frenMintedToday = 0;

      // TODO: OP_NET SDK -- persist
      // StoredU64.store(SLOT_V2_FREN_MINT_DAY, currentDay);
      // StoredU256.store(SLOT_V2_FREN_MINTED_TODAY, 0);
    }
  }

  // =========================================================================
  // Internal -- Security (V2 wrappers for reentrancy + pause + circuit breaker)
  // =========================================================================

  // NOTE: V2 uses its own reentrancy guard wrappers to ensure they work
  // independently from V1's guard when both V1 and V2 functions are called
  // in the same transaction context.

  private _v2ReentrancyLock: u64 = 1;

  private _nonReentrant_enter_v2(): void {
    assert(this._v2ReentrancyLock == 1, "CauldronV2: reentrant call");
    this._v2ReentrancyLock = 2;
  }

  private _nonReentrant_exit_v2(): void {
    this._v2ReentrancyLock = 1;
  }

  private _whenNotPaused_v2(): void {
    // TODO: OP_NET SDK -- check paused state from V1 storage
    // assert(!this._paused, "CauldronV2: contract is paused");
  }

  private _whenCircuitBreakerNotTripped(): void {
    assert(!this._circuitBreakerTripped, "CauldronV2: circuit breaker is active");
  }

  private _onlyAdmin_v2(): void {
    // TODO: OP_NET SDK -- compare Blockchain.tx.sender with stored admin
    // assert(Blockchain.tx.sender == StoredAddress.load(SLOT_ADMIN), "CauldronV2: not admin");
  }

  private _mockTimestamp_v2(): u64 {
    // TODO: OP_NET SDK -- replace with Blockchain.block.timestamp
    return 0;
  }

  // =========================================================================
  // Calldata router (OP_NET entry point) -- V2 additions
  // =========================================================================

  /**
   * TODO: OP_NET SDK -- extend the V1 calldata router with V2 selectors
   *
   * export function execute(calldata: Calldata): BytesWriter {
   *   const selector = calldata.readSelector();
   *
   *   // --- V2-specific selectors ---
   *   switch (selector) {
   *     case encodeSelector("mintV2(u256,u256,u256)"):
   *       const btcAmt = calldata.readU256();
   *       const frenAmt = calldata.readU256();
   *       const mifOut = calldata.readU256();
   *       cauldronV2.mintV2(btcAmt, frenAmt, mifOut);
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("redeemV2(u256)"):
   *       cauldronV2.redeemV2(calldata.readU256());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("adjustTCR(u64)"):
   *       cauldronV2.adjustTCR(calldata.readU64());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("resetCircuitBreaker()"):
   *       cauldronV2.resetCircuitBreaker();
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("getECR()"):
   *       return u256.fromU64(cauldronV2.getECR()).toBytes();
   *
   *     case encodeSelector("getTCR()"):
   *       return u256.fromU64(cauldronV2.getTCR()).toBytes();
   *
   *     case encodeSelector("isCircuitBreakerTripped()"):
   *       return u256.fromBool(cauldronV2.isCircuitBreakerTripped()).toBytes();
   *
   *     case encodeSelector("btcReserves()"):
   *       return u256.fromU64(cauldronV2.btcReserves()).toBytes();
   *
   *     case encodeSelector("v2MifSupply()"):
   *       return u256.fromU64(cauldronV2.v2MifSupply()).toBytes();
   *
   *     case encodeSelector("frenMintedToday()"):
   *       return u256.fromU64(cauldronV2.frenMintedToday()).toBytes();
   *
   *     case encodeSelector("frenDailyMintCapRemaining()"):
   *       return u256.fromU64(cauldronV2.frenDailyMintCapRemaining()).toBytes();
   *
   *     default:
   *       // Fall through to V1 calldata router
   *       return super.execute(calldata);
   *   }
   * }
   */
}

// NOTE: PRECISION_U64 is defined at the top of this file alongside the other
// V2 constants. The Cauldron V1 module defines its own copy as well.
