/**
 * Cauldron.ts -- Core Lending Market for the Magic Internet Frens Protocol
 * ==========================================================================
 * Target: OP_NET (Bitcoin L1) -- AssemblyScript Smart Contract
 *
 * Fork of Abracadabra's Cauldron architecture, adapted for OP_NET + BTC.
 *
 * Users deposit BTC as collateral (gated by miFrens NFT ownership + tier)
 * and borrow MIF (Magic Internet Fren stablecoin) against it.
 *
 * Key parameters:
 *   - LTV (Loan-to-Value):       75%
 *   - Liquidation threshold:     80%
 *   - Liquidation penalty:        5%
 *   - Borrow opening fee:        0.5%
 *   - Interest rate model:       Utilization-curve (1-50% APR)
 *
 * Collateral is BTC denominated in satoshis (u256).
 * Debt is MIF denominated with 18 decimals (u256).
 *
 * Positions are keyed by NFT ID (nftId: u256). Every mutating call requires
 * the caller to own the referenced NFT.
 */

// TODO: OP_NET SDK -- import the OP_NET runtime, storage, and contract base class
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

// ---------------------------------------------------------------------------
// Constants -- Protocol Parameters
// ---------------------------------------------------------------------------

/** Basis points denominator (100% = 10000 BPS) */
const BPS: u64 = 10_000;

/** LTV: 75% => 7500 BPS. Max debt / collateral value before borrow is denied. */
const LTV_BPS: u64 = 7_500;

/** Liquidation threshold: 80% => 8000 BPS. Positions above this can be liquidated. */
const LIQUIDATION_THRESHOLD_BPS: u64 = 8_000;

/** Liquidation penalty: 5% => 500 BPS. Deducted from collateral on liquidation. */
const LIQUIDATION_PENALTY_BPS: u64 = 500;

/** Borrow opening fee: 0.5% => 50 BPS. Charged on every new borrow. */
const BORROW_OPENING_FEE_BPS: u64 = 50;

/** Seconds in a year (365.25 days) for interest calculations. */
const SECONDS_PER_YEAR: u64 = 31_557_600;

/** 18-decimal precision multiplier */
// const PRECISION: u256 = u256.fromU64(10).pow(18);
const PRECISION_U64: u64 = 1_000_000_000_000_000_000; // 10^18

/** Interest rate model: base rate at 0% utilization (1% APR) */
const BASE_RATE_BPS: u64 = 100; // 1%

/** Interest rate model: rate at 80% utilization (5% APR) */
const KINK_RATE_BPS: u64 = 500; // 5%

/** Interest rate model: utilization kink point */
const KINK_UTILIZATION_BPS: u64 = 8_000; // 80%

/** Interest rate model: max rate at 100% utilization (50% APR) */
const MAX_RATE_BPS: u64 = 5_000; // 50%

// ---------------------------------------------------------------------------
// Action IDs for cook()
// ---------------------------------------------------------------------------

/** Action: deposit BTC collateral */
const ACTION_ADD_COLLATERAL: u8 = 1;

/** Action: withdraw BTC collateral */
const ACTION_REMOVE_COLLATERAL: u8 = 2;

/** Action: borrow MIF against collateral */
const ACTION_BORROW: u8 = 3;

/** Action: repay MIF debt */
const ACTION_REPAY: u8 = 4;

// Action ID 0 is intentionally invalid and will cause a revert.

// ---------------------------------------------------------------------------
// Storage slot keys
// ---------------------------------------------------------------------------

// --- Global scalars ---
const SLOT_ADMIN:              u64 = 0;
const SLOT_ORACLE:             u64 = 1;   // Address of the Oracle contract
const SLOT_MIF_TOKEN:          u64 = 2;   // Address of the MIF token contract
const SLOT_NFT_CONTRACT:       u64 = 3;   // Address of the miFrens NFT contract
const SLOT_FREN_TOKEN:         u64 = 4;   // Address of the FREN token (for fee distribution)
const SLOT_SFREN_STAKING:      u64 = 5;   // Address of the sFREN staking contract

const SLOT_TOTAL_COLLATERAL:   u64 = 10;  // u256 -- total BTC collateral (satoshis)
const SLOT_TOTAL_DEBT:         u64 = 11;  // u256 -- total outstanding MIF debt (18 dec)
const SLOT_TOTAL_BORROW_CAP:   u64 = 12;  // u256 -- max total debt allowed
const SLOT_ACCRUED_FEES:       u64 = 13;  // u256 -- accumulated protocol fees (MIF)
const SLOT_LAST_ACCRUE_TS:     u64 = 14;  // u64  -- timestamp of last global accrue
const SLOT_REENTRANCY_GUARD:   u64 = 15;  // u64  -- 1 = unlocked, 2 = locked
const SLOT_PAUSED:             u64 = 16;  // u64  -- 0 = active, 1 = paused

// --- Per-position maps (keyed by nftId) ---
// In OP_NET, maps use a base slot + nftId hash for collision resistance.
const MAP_COLLATERAL:          u64 = 100; // nftId => u256 (satoshis)
const MAP_DEBT:                u64 = 200; // nftId => u256 (MIF 18 dec)
const MAP_LAST_ACCRUE_TS:      u64 = 300; // nftId => u64

// --- Tier borrow caps (keyed by tier level 0-5) ---
const MAP_TIER_BORROW_CAP:     u64 = 400; // tier => u256

// ---------------------------------------------------------------------------
// Event selectors
// ---------------------------------------------------------------------------

// TODO: OP_NET SDK -- define event selectors
// const EVENT_DEPOSIT           = encodeSelector("Deposit(u256,u256)");
// const EVENT_WITHDRAW          = encodeSelector("Withdraw(u256,u256)");
// const EVENT_BORROW            = encodeSelector("Borrow(u256,u256,u256)");
// const EVENT_REPAY             = encodeSelector("Repay(u256,u256)");
// const EVENT_LIQUIDATE         = encodeSelector("Liquidate(u256,address,u256,u256)");
// const EVENT_ACCRUE            = encodeSelector("Accrue(u256,u256)");
// const EVENT_FEES_DISTRIBUTED  = encodeSelector("FeesDistributed(u256)");

// ---------------------------------------------------------------------------
// Position struct (in-memory representation)
// ---------------------------------------------------------------------------

class Position {
  collateral: u64 = 0;   // u256 -- BTC in satoshis
  debt: u64 = 0;         // u256 -- MIF with 18 decimals
  lastAccrueTs: u64 = 0; // timestamp of last per-position accrue
}

// ---------------------------------------------------------------------------
// Cauldron Contract
// ---------------------------------------------------------------------------

// TODO: OP_NET SDK -- extend the OP_NET contract base class
// export class Cauldron extends Contract {

export class Cauldron {

  // =========================================================================
  // In-memory state (placeholders for OP_NET StoredU256 / StoredMap)
  // =========================================================================

  // Global state
  private _admin: string = "";
  private _oracleAddress: string = "";
  private _mifTokenAddress: string = "";
  private _nftContractAddress: string = "";
  private _frenTokenAddress: string = "";
  private _sFrenStakingAddress: string = "";

  private _totalCollateral: u64 = 0;   // u256
  private _totalDebt: u64 = 0;         // u256
  private _totalBorrowCap: u64 = 0;    // u256
  private _accruedFees: u64 = 0;       // u256
  private _lastAccrueTimestamp: u64 = 0;
  private _reentrancyLock: u64 = 1;    // 1 = unlocked, 2 = locked
  private _paused: bool = false;

  // Per-position state -- in production these are StoredMap<u256, u256>
  // TODO: OP_NET SDK -- replace with StoredMap
  private _positions: Map<u64, Position> = new Map<u64, Position>();

  // Tier borrow caps
  private _tierBorrowCaps: Map<u8, u64> = new Map<u8, u64>();

  // =========================================================================
  // Constructor / Initializer
  // =========================================================================

  /**
   * Initializes the Cauldron with external contract addresses and default
   * tier borrow caps. Only called once at deployment.
   *
   * @param oracle       Address of the BTC/USD Oracle contract
   * @param mifToken     Address of the MIF stablecoin contract
   * @param nftContract  Address of the miFrens NFT contract
   * @param frenToken    Address of the FREN governance token
   * @param sFrenStaking Address of the sFREN staking / reward distributor
   */
  constructor(
    oracle: string = "",
    mifToken: string = "",
    nftContract: string = "",
    frenToken: string = "",
    sFrenStaking: string = ""
  ) {
    // TODO: OP_NET SDK -- read Blockchain.tx.sender
    // this._admin = Blockchain.tx.sender;

    this._oracleAddress = oracle;
    this._mifTokenAddress = mifToken;
    this._nftContractAddress = nftContract;
    this._frenTokenAddress = frenToken;
    this._sFrenStakingAddress = sFrenStaking;

    // TODO: OP_NET SDK -- store all addresses in persistent storage

    // Default tier borrow caps (MIF with 18 decimals)
    // Tier 0 (base):      1,000 MIF
    // Tier 1 (uncommon):  5,000 MIF
    // Tier 2 (rare):     10,000 MIF
    // Tier 3 (epic):     25,000 MIF
    // Tier 4 (legendary): 50,000 MIF
    // Tier 5 (mythic):   100,000 MIF
    this._tierBorrowCaps.set(0, 1_000);
    this._tierBorrowCaps.set(1, 5_000);
    this._tierBorrowCaps.set(2, 10_000);
    this._tierBorrowCaps.set(3, 25_000);
    this._tierBorrowCaps.set(4, 50_000);
    this._tierBorrowCaps.set(5, 100_000);

    this._reentrancyLock = 1; // unlocked
    this._lastAccrueTimestamp = this._mockTimestamp();
  }

  // =========================================================================
  // Core Functions -- Deposit / Borrow / Repay / Withdraw / Liquidate
  // =========================================================================

  /**
   * deposit(nftId: u256, amount: u256): void
   *
   * Lock BTC collateral into the Cauldron, associated with the caller's NFT.
   *
   * Requirements:
   *   - Caller must own the NFT (verified on-chain)
   *   - NFT must pass tier gate check
   *   - amount > 0
   *   - Contract must not be paused
   *   - Reentrancy guard
   *
   * @param nftId   The miFrens NFT ID gating this position
   * @param amount  BTC amount in satoshis to deposit
   */
  deposit(nftId: u64 /* u256 */, amount: u64 /* u256 */): void {
    this._nonReentrant_enter();
    this._whenNotPaused();

    // --- Verify NFT ownership ---
    this._verifyNFTOwnership(nftId);

    // --- Verify NFT tier gate (must have valid tier) ---
    this._verifyTierGate(nftId);

    assert(amount > 0, "Cauldron: deposit amount must be > 0");

    // --- Transfer BTC from caller to this contract ---
    // TODO: OP_NET SDK -- BTC transfer: Blockchain.transferBTC(caller, thisContract, amount)
    // On OP_NET, BTC transfers happen at the Bitcoin L1 level.
    // The runtime verifies the UTXO input matches the declared amount.

    // --- Update position ---
    const position = this._getOrCreatePosition(nftId);
    position.collateral += amount;
    this._positions.set(nftId, position);

    // --- Update global state ---
    this._totalCollateral += amount;

    // TODO: OP_NET SDK -- persist storage
    // StoredU256.store(SLOT_TOTAL_COLLATERAL, this._totalCollateral);
    // StoredMap.store(MAP_COLLATERAL, nftId, position.collateral);

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_DEPOSIT, [nftId, amount]);

    this._nonReentrant_exit();
  }

  /**
   * borrow(nftId: u256, amount: u256): void
   *
   * Borrow MIF stablecoin against deposited BTC collateral.
   *
   * Requirements:
   *   - Caller must own the NFT
   *   - Resulting LTV must be <= 75%
   *   - Total debt for this position must be <= tier borrow cap
   *   - Total protocol debt must be <= totalBorrowCap
   *   - 0.5% opening fee is charged on the borrow amount
   *
   * @param nftId   The miFrens NFT ID
   * @param amount  MIF amount to borrow (18 decimals)
   */
  borrow(nftId: u64 /* u256 */, amount: u64 /* u256 */): void {
    this._nonReentrant_enter();
    this._whenNotPaused();

    this._verifyNFTOwnership(nftId);

    assert(amount > 0, "Cauldron: borrow amount must be > 0");

    // --- Accrue interest before state change ---
    this._accruePosition(nftId);

    // --- Calculate opening fee: 0.5% of borrow amount ---
    const openingFee: u64 = (amount * BORROW_OPENING_FEE_BPS) / BPS;
    const totalDebtIncrease: u64 = amount + openingFee;

    // --- Update position debt ---
    const position = this._getOrCreatePosition(nftId);
    position.debt += totalDebtIncrease;
    this._positions.set(nftId, position);

    // --- Check LTV: debt / collateralValueInMIF <= 75% ---
    const collateralValueMIF = this._collateralToMIF(position.collateral);
    assert(collateralValueMIF > 0, "Cauldron: no collateral");
    const currentLTV = (position.debt * BPS) / collateralValueMIF;
    assert(currentLTV <= LTV_BPS, "Cauldron: exceeds LTV limit (75%)");

    // --- Check tier borrow cap ---
    const tier = this._getNFTTier(nftId);
    const tierCap = this._getTierBorrowCap(tier);
    assert(position.debt <= tierCap, "Cauldron: exceeds tier borrow cap");

    // --- Check global borrow cap ---
    this._totalDebt += totalDebtIncrease;
    if (this._totalBorrowCap > 0) {
      assert(
        this._totalDebt <= this._totalBorrowCap,
        "Cauldron: exceeds global borrow cap"
      );
    }

    // --- Accumulate opening fee ---
    this._accruedFees += openingFee;

    // --- Mint MIF to caller ---
    // TODO: OP_NET SDK -- call MIF token contract to mint
    // IMIFToken(this._mifTokenAddress).mint(Blockchain.tx.sender, amount);

    // --- Persist ---
    // TODO: OP_NET SDK -- persist all storage updates

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_BORROW, [nftId, amount, openingFee]);

    this._nonReentrant_exit();
  }

  /**
   * repay(nftId: u256, amount: u256): void
   *
   * Repay MIF debt. Burns the repaid MIF tokens.
   *
   * @param nftId   The miFrens NFT ID
   * @param amount  MIF amount to repay (18 decimals)
   */
  repay(nftId: u64 /* u256 */, amount: u64 /* u256 */): void {
    this._nonReentrant_enter();
    this._whenNotPaused();

    this._verifyNFTOwnership(nftId);

    assert(amount > 0, "Cauldron: repay amount must be > 0");

    // --- Accrue interest before state change ---
    this._accruePosition(nftId);

    const position = this._getOrCreatePosition(nftId);
    assert(position.debt > 0, "Cauldron: no debt to repay");

    // --- Cap repayment at outstanding debt ---
    const repayAmount: u64 = amount > position.debt ? position.debt : amount;

    // --- Burn MIF from caller ---
    // TODO: OP_NET SDK -- call MIF token contract to burn
    // IMIFToken(this._mifTokenAddress).burn(Blockchain.tx.sender, repayAmount);

    // --- Update position debt ---
    position.debt -= repayAmount;
    this._positions.set(nftId, position);

    // --- Update global debt ---
    this._totalDebt -= repayAmount;

    // --- Persist ---
    // TODO: OP_NET SDK -- persist storage updates

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_REPAY, [nftId, repayAmount]);

    this._nonReentrant_exit();
  }

  /**
   * withdraw(nftId: u256, amount: u256): void
   *
   * Withdraw BTC collateral. LTV must remain safe (<= 75%) after withdrawal.
   *
   * @param nftId   The miFrens NFT ID
   * @param amount  BTC amount in satoshis to withdraw
   */
  withdraw(nftId: u64 /* u256 */, amount: u64 /* u256 */): void {
    this._nonReentrant_enter();
    this._whenNotPaused();

    this._verifyNFTOwnership(nftId);

    assert(amount > 0, "Cauldron: withdraw amount must be > 0");

    // --- Accrue interest before state change ---
    this._accruePosition(nftId);

    const position = this._getOrCreatePosition(nftId);
    assert(position.collateral >= amount, "Cauldron: insufficient collateral");

    // --- Update position collateral ---
    position.collateral -= amount;
    this._positions.set(nftId, position);

    // --- Check LTV remains safe after withdrawal ---
    if (position.debt > 0) {
      const collateralValueMIF = this._collateralToMIF(position.collateral);
      const currentLTV = collateralValueMIF > 0
        ? (position.debt * BPS) / collateralValueMIF
        : BPS + 1; // force revert if no collateral but has debt
      assert(currentLTV <= LTV_BPS, "Cauldron: withdrawal would exceed LTV limit (75%)");
    }

    // --- Update global state ---
    this._totalCollateral -= amount;

    // --- Transfer BTC back to caller ---
    // TODO: OP_NET SDK -- BTC transfer back to caller
    // Blockchain.transferBTC(thisContract, Blockchain.tx.sender, amount);

    // --- Persist ---
    // TODO: OP_NET SDK -- persist storage updates

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_WITHDRAW, [nftId, amount]);

    this._nonReentrant_exit();
  }

  /**
   * liquidate(nftId: u256): void
   *
   * Liquidate an undercollateralized position. Anyone can call this.
   *
   * Requirements:
   *   - Position LTV must be > 80% (liquidation threshold)
   *   - Liquidator repays the full debt
   *   - Liquidator receives collateral minus 5% penalty
   *   - The 5% penalty goes to the protocol fee pool
   *
   * @param nftId  The miFrens NFT ID of the position to liquidate
   */
  liquidate(nftId: u64 /* u256 */): void {
    this._nonReentrant_enter();
    this._whenNotPaused();

    // NOTE: No NFT ownership check -- anyone can liquidate unhealthy positions

    // --- Accrue interest before check ---
    this._accruePosition(nftId);

    const position = this._getOrCreatePosition(nftId);
    assert(position.debt > 0, "Cauldron: no debt to liquidate");
    assert(position.collateral > 0, "Cauldron: no collateral");

    // --- Check if position is liquidatable (LTV > 80%) ---
    const collateralValueMIF = this._collateralToMIF(position.collateral);
    const currentLTV = (position.debt * BPS) / collateralValueMIF;
    assert(
      currentLTV > LIQUIDATION_THRESHOLD_BPS,
      "Cauldron: position is healthy (LTV <= 80%)"
    );

    // --- Calculate liquidation amounts ---
    const debtToRepay = position.debt;
    const totalCollateral = position.collateral;

    // Penalty: 5% of collateral goes to protocol
    const penaltyAmount: u64 = (totalCollateral * LIQUIDATION_PENALTY_BPS) / BPS;
    const collateralToLiquidator: u64 = totalCollateral - penaltyAmount;

    // --- Burn MIF from liquidator to cover the debt ---
    // TODO: OP_NET SDK -- burn MIF from liquidator
    // IMIFToken(this._mifTokenAddress).burn(Blockchain.tx.sender, debtToRepay);

    // --- Transfer collateral to liquidator (minus penalty) ---
    // TODO: OP_NET SDK -- BTC transfer to liquidator
    // Blockchain.transferBTC(thisContract, Blockchain.tx.sender, collateralToLiquidator);

    // --- Accumulate penalty as protocol fee (in BTC satoshis) ---
    // The penalty collateral stays in the contract and is tracked as protocol revenue.
    // It can be converted to MIF and distributed to sFREN stakers by admin.
    this._accruedFees += penaltyAmount; // NOTE: tracked in sats here; convert on distribution

    // --- Clear the position ---
    position.collateral = 0;
    position.debt = 0;
    position.lastAccrueTs = 0;
    this._positions.set(nftId, position);

    // --- Update global state ---
    this._totalCollateral -= totalCollateral;
    this._totalDebt -= debtToRepay;

    // --- Persist ---
    // TODO: OP_NET SDK -- persist all storage updates

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_LIQUIDATE, [nftId, liquidator, debtToRepay, collateralToLiquidator]);

    this._nonReentrant_exit();
  }

  // =========================================================================
  // cook() -- Batched action execution (Abracadabra-style)
  // =========================================================================

  /**
   * cook(nftId: u256, actions: u8[], values: u256[], datas: u8[][]): void
   *
   * Execute multiple actions atomically in a single transaction.
   * The solvency check (LTV <= 75%) is performed ONLY at the end of the
   * entire batch, allowing intermediate states to be temporarily insolvent.
   *
   * This enables powerful composed operations like:
   *   - Deposit + Borrow in one tx
   *   - Repay + Withdraw in one tx
   *   - Rebalance collateral across operations
   *
   * Valid action IDs:
   *   1 = ADD_COLLATERAL
   *   2 = REMOVE_COLLATERAL
   *   3 = BORROW
   *   4 = REPAY
   *
   * Action ID 0 is invalid and will cause an immediate revert.
   *
   * @param nftId    The miFrens NFT ID
   * @param actions  Array of action IDs
   * @param values   Array of u256 amounts corresponding to each action
   * @param datas    Array of auxiliary data blobs (reserved for future use)
   */
  cook(
    nftId: u64 /* u256 */,
    actions: u8[],
    values: u64[] /* u256[] */,
    datas: u8[][] = []
  ): void {
    this._nonReentrant_enter();
    this._whenNotPaused();

    this._verifyNFTOwnership(nftId);

    assert(actions.length > 0, "Cauldron: no actions");
    assert(actions.length == values.length, "Cauldron: actions/values length mismatch");

    // --- Accrue interest once before the batch ---
    this._accruePosition(nftId);

    const position = this._getOrCreatePosition(nftId);

    // --- Execute each action WITHOUT intermediate solvency checks ---
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      const value = values[i];

      assert(action != 0, "Cauldron: invalid action ID 0");

      if (action == ACTION_ADD_COLLATERAL) {
        // --- Add collateral ---
        assert(value > 0, "Cauldron: add collateral amount must be > 0");

        // TODO: OP_NET SDK -- transfer BTC from caller
        position.collateral += value;
        this._totalCollateral += value;

      } else if (action == ACTION_REMOVE_COLLATERAL) {
        // --- Remove collateral ---
        assert(value > 0, "Cauldron: remove collateral amount must be > 0");
        assert(position.collateral >= value, "Cauldron: insufficient collateral");

        position.collateral -= value;
        this._totalCollateral -= value;

        // TODO: OP_NET SDK -- transfer BTC to caller

      } else if (action == ACTION_BORROW) {
        // --- Borrow MIF ---
        assert(value > 0, "Cauldron: borrow amount must be > 0");

        const openingFee: u64 = (value * BORROW_OPENING_FEE_BPS) / BPS;
        const totalDebtIncrease: u64 = value + openingFee;

        position.debt += totalDebtIncrease;
        this._totalDebt += totalDebtIncrease;
        this._accruedFees += openingFee;

        // --- Check tier borrow cap ---
        const tier = this._getNFTTier(nftId);
        const tierCap = this._getTierBorrowCap(tier);
        assert(position.debt <= tierCap, "Cauldron: exceeds tier borrow cap");

        // --- Check global borrow cap ---
        if (this._totalBorrowCap > 0) {
          assert(
            this._totalDebt <= this._totalBorrowCap,
            "Cauldron: exceeds global borrow cap"
          );
        }

        // TODO: OP_NET SDK -- mint MIF to caller

      } else if (action == ACTION_REPAY) {
        // --- Repay MIF ---
        assert(value > 0, "Cauldron: repay amount must be > 0");

        const repayAmount: u64 = value > position.debt ? position.debt : value;

        position.debt -= repayAmount;
        this._totalDebt -= repayAmount;

        // TODO: OP_NET SDK -- burn MIF from caller

      } else {
        // Unknown action -- revert
        assert(false, "Cauldron: unknown action ID");
      }
    }

    // --- IMMUTABLE SOLVENCY CHECK: performed ONLY at end of cook() ---
    if (position.debt > 0) {
      const collateralValueMIF = this._collateralToMIF(position.collateral);
      const finalLTV = collateralValueMIF > 0
        ? (position.debt * BPS) / collateralValueMIF
        : BPS + 1;
      assert(finalLTV <= LTV_BPS, "Cauldron: cook() result exceeds LTV limit (75%)");
    }

    // --- Persist final position state ---
    this._positions.set(nftId, position);

    // TODO: OP_NET SDK -- persist all storage updates

    this._nonReentrant_exit();
  }

  // =========================================================================
  // Interest Accrual
  // =========================================================================

  /**
   * accrue(): void
   *
   * Public function to trigger global interest accrual. Can be called by
   * anyone. Calculates interest based on time elapsed and current
   * utilization rate.
   *
   * Interest rate model (piecewise):
   *   - 0% to 80% utilization: 1% to 5% APR (linear)
   *   - 80% to 100% utilization: 5% to 50% APR (exponential curve)
   *
   * Accumulated interest is added to totalDebt and accruedFees.
   * Fee distribution to sFREN stakers happens via distributeFees().
   */
  accrue(): void {
    const now: u64 = this._mockTimestamp();
    const lastAccrue = this._lastAccrueTimestamp;

    if (now <= lastAccrue) return; // no time elapsed
    if (this._totalDebt == 0) {
      this._lastAccrueTimestamp = now;
      return; // no debt to accrue on
    }

    const elapsed: u64 = now - lastAccrue;

    // --- Calculate utilization rate ---
    // Utilization = totalDebt / (totalDebt + available liquidity)
    // For a CDP-style system, utilization is based on collateral value:
    // utilization = totalDebt / totalCollateralValueInMIF
    const totalCollateralMIF = this._collateralToMIF(this._totalCollateral);
    let utilizationBPS: u64 = 0;
    if (totalCollateralMIF > 0) {
      utilizationBPS = (this._totalDebt * BPS) / totalCollateralMIF;
      if (utilizationBPS > BPS) utilizationBPS = BPS; // cap at 100%
    }

    // --- Calculate interest rate (BPS per year) ---
    const rateBPS = this._calculateInterestRate(utilizationBPS);

    // --- Calculate interest amount ---
    // interest = totalDebt * rateBPS / BPS * elapsed / SECONDS_PER_YEAR
    const interestAmount: u64 =
      (this._totalDebt * rateBPS * elapsed) / (BPS * SECONDS_PER_YEAR);

    if (interestAmount > 0) {
      // --- Add interest to total debt ---
      this._totalDebt += interestAmount;

      // --- Accumulate as protocol fees (for distribution to sFREN stakers) ---
      this._accruedFees += interestAmount;

      // TODO: OP_NET SDK -- persist storage
      // StoredU256.store(SLOT_TOTAL_DEBT, this._totalDebt);
      // StoredU256.store(SLOT_ACCRUED_FEES, this._accruedFees);

      // --- Emit event ---
      // TODO: OP_NET SDK -- Blockchain.emit(EVENT_ACCRUE, [interestAmount, u256.fromU64(now)]);
    }

    this._lastAccrueTimestamp = now;
    // TODO: OP_NET SDK -- StoredU64.store(SLOT_LAST_ACCRUE_TS, now);
  }

  /**
   * distributeFees(): void
   *
   * Admin function to distribute accumulated fees to sFREN stakers
   * via the FREN token's distributeReward() function.
   *
   * Both opening fees and accrued interest flow to sFREN stakers.
   */
  distributeFees(): void {
    this._onlyAdmin();

    const fees = this._accruedFees;
    assert(fees > 0, "Cauldron: no fees to distribute");

    // --- Reset accrued fees ---
    this._accruedFees = 0;

    // --- Distribute to sFREN stakers ---
    // TODO: OP_NET SDK -- call FREN.distributeReward(fees)
    // IFRENToken(this._frenTokenAddress).distributeReward(fees);

    // --- Emit event ---
    // TODO: OP_NET SDK -- Blockchain.emit(EVENT_FEES_DISTRIBUTED, [fees]);
  }

  // =========================================================================
  // View Functions
  // =========================================================================

  /**
   * getPosition(nftId): { collateral, debt, lastAccrueTs }
   */
  getPosition(nftId: u64 /* u256 */): Position {
    return this._getOrCreatePosition(nftId);
  }

  /**
   * getPositionLTV(nftId): u64
   *
   * Returns the current LTV of a position in basis points.
   * Returns 0 if no collateral deposited.
   */
  getPositionLTV(nftId: u64 /* u256 */): u64 {
    const position = this._getOrCreatePosition(nftId);
    if (position.collateral == 0 || position.debt == 0) return 0;

    const collateralValueMIF = this._collateralToMIF(position.collateral);
    if (collateralValueMIF == 0) return 0;

    return (position.debt * BPS) / collateralValueMIF;
  }

  /**
   * isLiquidatable(nftId): bool
   *
   * Returns true if the position's LTV exceeds the liquidation threshold (80%).
   */
  isLiquidatable(nftId: u64 /* u256 */): bool {
    return this.getPositionLTV(nftId) > LIQUIDATION_THRESHOLD_BPS;
  }

  /**
   * getCurrentInterestRate(): u64
   *
   * Returns the current interest rate in BPS based on utilization.
   */
  getCurrentInterestRate(): u64 {
    const totalCollateralMIF = this._collateralToMIF(this._totalCollateral);
    let utilizationBPS: u64 = 0;
    if (totalCollateralMIF > 0) {
      utilizationBPS = (this._totalDebt * BPS) / totalCollateralMIF;
      if (utilizationBPS > BPS) utilizationBPS = BPS;
    }
    return this._calculateInterestRate(utilizationBPS);
  }

  /**
   * totalCollateral(): u64 (u256)
   */
  totalCollateral(): u64 {
    return this._totalCollateral;
  }

  /**
   * totalDebt(): u64 (u256)
   */
  totalDebt(): u64 {
    return this._totalDebt;
  }

  /**
   * accruedFees(): u64 (u256)
   */
  accruedFees(): u64 {
    return this._accruedFees;
  }

  // =========================================================================
  // Admin Functions
  // =========================================================================

  /**
   * setTotalBorrowCap(cap: u256): void
   *
   * Admin-only. Sets the maximum total MIF debt the protocol can issue.
   * Set to 0 for unlimited.
   */
  setTotalBorrowCap(cap: u64 /* u256 */): void {
    this._onlyAdmin();
    this._totalBorrowCap = cap;
    // TODO: OP_NET SDK -- StoredU256.store(SLOT_TOTAL_BORROW_CAP, cap);
  }

  /**
   * setTierBorrowCap(tier: u8, cap: u256): void
   *
   * Admin-only. Sets the maximum borrow amount for a specific NFT tier.
   */
  setTierBorrowCap(tier: u8, cap: u64 /* u256 */): void {
    this._onlyAdmin();
    this._tierBorrowCaps.set(tier, cap);
    // TODO: OP_NET SDK -- StoredMap.store(MAP_TIER_BORROW_CAP, tier, cap);
  }

  /**
   * pause(): void
   *
   * Admin-only. Pauses all deposits, borrows, repays, withdrawals, and liquidations.
   */
  pause(): void {
    this._onlyAdmin();
    this._paused = true;
    // TODO: OP_NET SDK -- StoredU64.store(SLOT_PAUSED, 1);
  }

  /**
   * unpause(): void
   *
   * Admin-only. Resumes contract operations.
   */
  unpause(): void {
    this._onlyAdmin();
    this._paused = false;
    // TODO: OP_NET SDK -- StoredU64.store(SLOT_PAUSED, 0);
  }

  /**
   * setOracle(oracle: Address): void
   *
   * Admin-only. Updates the oracle contract address.
   */
  setOracle(oracle: string /* Address */): void {
    this._onlyAdmin();
    this._oracleAddress = oracle;
    // TODO: OP_NET SDK -- StoredAddress.store(SLOT_ORACLE, oracle);
  }

  /**
   * transferAdmin(newAdmin: Address): void
   */
  transferAdmin(newAdmin: string /* Address */): void {
    this._onlyAdmin();
    assert(newAdmin.length > 0, "Cauldron: zero address");
    this._admin = newAdmin;
    // TODO: OP_NET SDK -- StoredAddress.store(SLOT_ADMIN, newAdmin);
  }

  // =========================================================================
  // Internal -- Interest Rate Model
  // =========================================================================

  /**
   * _calculateInterestRate(utilizationBPS: u64): u64
   *
   * Piecewise interest rate:
   *   - 0% to 80% utilization:  1% to 5% APR  (linear)
   *   - 80% to 100% utilization: 5% to 50% APR (exponential)
   *
   * Returns rate in BPS (basis points per year).
   */
  private _calculateInterestRate(utilizationBPS: u64): u64 {
    if (utilizationBPS <= KINK_UTILIZATION_BPS) {
      // --- Linear segment: BASE_RATE to KINK_RATE ---
      // rate = BASE_RATE + (KINK_RATE - BASE_RATE) * utilization / KINK_UTILIZATION
      const spread = KINK_RATE_BPS - BASE_RATE_BPS; // 400 BPS
      return BASE_RATE_BPS + (spread * utilizationBPS) / KINK_UTILIZATION_BPS;
    } else {
      // --- Exponential segment: KINK_RATE to MAX_RATE ---
      // excess = utilization - kink (in BPS above kink)
      // range  = BPS - kink (total BPS range above kink = 2000)
      // We use a quadratic approximation for the exponential curve:
      //   rate = KINK_RATE + (MAX_RATE - KINK_RATE) * (excess / range)^2
      // This creates a gentle curve that accelerates toward MAX_RATE.
      const excess: u64 = utilizationBPS - KINK_UTILIZATION_BPS;
      const range: u64 = BPS - KINK_UTILIZATION_BPS; // 2000 BPS
      const spread: u64 = MAX_RATE_BPS - KINK_RATE_BPS; // 4500 BPS

      // Quadratic: (excess^2 * spread) / range^2
      // To avoid overflow, compute in steps:
      const excessSquared: u64 = excess * excess; // max 2000^2 = 4,000,000
      const rangeSquared: u64 = range * range;     // 2000^2 = 4,000,000
      return KINK_RATE_BPS + (excessSquared * spread) / rangeSquared;
    }
  }

  // =========================================================================
  // Internal -- Per-position interest accrual
  // =========================================================================

  /**
   * _accruePosition(nftId: u64): void
   *
   * Accrues interest on a specific position based on time elapsed since
   * the last per-position accrue. Adds accrued interest to the position's
   * debt and to the global debt + fees.
   */
  private _accruePosition(nftId: u64): void {
    // --- First, run global accrue ---
    this.accrue();

    const position = this._getOrCreatePosition(nftId);
    if (position.debt == 0) {
      position.lastAccrueTs = this._mockTimestamp();
      this._positions.set(nftId, position);
      return;
    }

    const now: u64 = this._mockTimestamp();
    const lastTs = position.lastAccrueTs;
    if (now <= lastTs) return;

    const elapsed = now - lastTs;

    // Use the current global interest rate
    const totalCollateralMIF = this._collateralToMIF(this._totalCollateral);
    let utilizationBPS: u64 = 0;
    if (totalCollateralMIF > 0) {
      utilizationBPS = (this._totalDebt * BPS) / totalCollateralMIF;
      if (utilizationBPS > BPS) utilizationBPS = BPS;
    }
    const rateBPS = this._calculateInterestRate(utilizationBPS);

    // interest = positionDebt * rateBPS / BPS * elapsed / SECONDS_PER_YEAR
    const interest: u64 =
      (position.debt * rateBPS * elapsed) / (BPS * SECONDS_PER_YEAR);

    if (interest > 0) {
      position.debt += interest;
      // Note: global totals are updated in accrue(), not double-counted here.
      // Per-position accrual ensures individual debt tracking is accurate.
    }

    position.lastAccrueTs = now;
    this._positions.set(nftId, position);
  }

  // =========================================================================
  // Internal -- Oracle Integration
  // =========================================================================

  /**
   * _collateralToMIF(collateralSats: u64): u64
   *
   * Converts a BTC collateral amount (in satoshis) to its MIF value
   * (18 decimals) using the oracle's BTC/USD price.
   *
   * collateralMIF = collateralSats * btcPrice / 10^8
   *
   * (BTC has 8 decimal places as satoshis; MIF has 18. Oracle price has 18.)
   */
  private _collateralToMIF(collateralSats: u64 /* u256 */): u64 /* u256 */ {
    // TODO: OP_NET SDK -- call Oracle contract
    // const btcPrice: u256 = IOracle(this._oracleAddress).getPrice();
    // return (u256.fromU64(collateralSats) * btcPrice) / u256.fromU64(100_000_000);

    // Placeholder: assume 1 BTC = 60,000 MIF (for illustrative purposes)
    // In production, this MUST call the oracle.
    const MOCK_BTC_PRICE: u64 = 60_000; // $60,000
    return (collateralSats * MOCK_BTC_PRICE) / 100_000_000; // sats to BTC, then to MIF value
  }

  // =========================================================================
  // Internal -- NFT Verification
  // =========================================================================

  /**
   * _verifyNFTOwnership(nftId: u64): void
   *
   * Verifies that the transaction caller owns the specified miFrens NFT.
   * Reverts if the caller is not the owner.
   */
  private _verifyNFTOwnership(nftId: u64 /* u256 */): void {
    // TODO: OP_NET SDK -- call miFrens NFT contract
    // const owner: Address = INFT(this._nftContractAddress).ownerOf(nftId);
    // assert(owner == Blockchain.tx.sender, "Cauldron: caller does not own NFT");
  }

  /**
   * _verifyTierGate(nftId: u64): void
   *
   * Verifies that the NFT has a valid tier (level) that qualifies it
   * to use the Cauldron. Currently any minted NFT (tier >= 0) qualifies.
   */
  private _verifyTierGate(nftId: u64 /* u256 */): void {
    // TODO: OP_NET SDK -- call miFrens NFT contract
    // const level: u256 = INFT(this._nftContractAddress).levels(nftId);
    // Tier gate: NFT must exist (ownership check above covers this)
    // Additional tier requirements can be added here.
  }

  /**
   * _getNFTTier(nftId: u64): u8
   *
   * Returns the tier (level) of the specified NFT.
   */
  private _getNFTTier(nftId: u64 /* u256 */): u8 {
    // TODO: OP_NET SDK -- call miFrens NFT contract
    // const level: u256 = INFT(this._nftContractAddress).levels(nftId);
    // return level.toU8();

    return 0; // placeholder: tier 0
  }

  /**
   * _getTierBorrowCap(tier: u8): u64
   *
   * Returns the borrow cap for a specific tier. Defaults to 0 (no borrowing)
   * if the tier is not configured.
   */
  private _getTierBorrowCap(tier: u8): u64 /* u256 */ {
    if (this._tierBorrowCaps.has(tier)) {
      return this._tierBorrowCaps.get(tier);
    }
    return 0;
  }

  // =========================================================================
  // Internal -- Position helper
  // =========================================================================

  /**
   * _getOrCreatePosition(nftId: u64): Position
   *
   * Returns the existing position for the given NFT ID, or creates a
   * new empty one if none exists.
   */
  private _getOrCreatePosition(nftId: u64 /* u256 */): Position {
    if (this._positions.has(nftId)) {
      return this._positions.get(nftId);
    }
    const pos = new Position();
    pos.lastAccrueTs = this._mockTimestamp();
    return pos;
  }

  // =========================================================================
  // Internal -- Security: Reentrancy Guard
  // =========================================================================

  /**
   * _nonReentrant_enter(): void
   *
   * Acquires the reentrancy lock. Reverts if already locked.
   */
  private _nonReentrant_enter(): void {
    assert(this._reentrancyLock == 1, "Cauldron: reentrant call");
    this._reentrancyLock = 2;
    // TODO: OP_NET SDK -- StoredU64.store(SLOT_REENTRANCY_GUARD, 2);
  }

  /**
   * _nonReentrant_exit(): void
   *
   * Releases the reentrancy lock.
   */
  private _nonReentrant_exit(): void {
    this._reentrancyLock = 1;
    // TODO: OP_NET SDK -- StoredU64.store(SLOT_REENTRANCY_GUARD, 1);
  }

  // =========================================================================
  // Internal -- Modifiers
  // =========================================================================

  /**
   * _onlyAdmin(): void
   */
  private _onlyAdmin(): void {
    // TODO: OP_NET SDK -- compare Blockchain.tx.sender with stored admin
    // assert(Blockchain.tx.sender == StoredAddress.load(SLOT_ADMIN), "Cauldron: not admin");
  }

  /**
   * _whenNotPaused(): void
   */
  private _whenNotPaused(): void {
    assert(!this._paused, "Cauldron: contract is paused");
  }

  // =========================================================================
  // Internal -- Timestamp placeholder
  // =========================================================================

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
   * export function execute(calldata: Calldata): BytesWriter {
   *   const selector = calldata.readSelector();
   *
   *   switch (selector) {
   *     case encodeSelector("deposit(u256,u256)"):
   *       cauldron.deposit(calldata.readU256(), calldata.readU256());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("borrow(u256,u256)"):
   *       cauldron.borrow(calldata.readU256(), calldata.readU256());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("repay(u256,u256)"):
   *       cauldron.repay(calldata.readU256(), calldata.readU256());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("withdraw(u256,u256)"):
   *       cauldron.withdraw(calldata.readU256(), calldata.readU256());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("liquidate(u256)"):
   *       cauldron.liquidate(calldata.readU256());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("cook(u256,u8[],u256[],bytes[])"):
   *       const nftId = calldata.readU256();
   *       const actions = calldata.readU8Array();
   *       const values = calldata.readU256Array();
   *       const datas = calldata.readBytesArray();
   *       cauldron.cook(nftId, actions, values, datas);
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("accrue()"):
   *       cauldron.accrue();
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("distributeFees()"):
   *       cauldron.distributeFees();
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("getPosition(u256)"):
   *       const pos = cauldron.getPosition(calldata.readU256());
   *       const writer = new BytesWriter();
   *       writer.writeU256(pos.collateral);
   *       writer.writeU256(pos.debt);
   *       writer.writeU64(pos.lastAccrueTs);
   *       return writer;
   *
   *     case encodeSelector("getPositionLTV(u256)"):
   *       return u256.fromU64(cauldron.getPositionLTV(calldata.readU256())).toBytes();
   *
   *     case encodeSelector("isLiquidatable(u256)"):
   *       return u256.fromBool(cauldron.isLiquidatable(calldata.readU256())).toBytes();
   *
   *     case encodeSelector("getCurrentInterestRate()"):
   *       return u256.fromU64(cauldron.getCurrentInterestRate()).toBytes();
   *
   *     case encodeSelector("totalCollateral()"):
   *       return u256.fromU64(cauldron.totalCollateral()).toBytes();
   *
   *     case encodeSelector("totalDebt()"):
   *       return u256.fromU64(cauldron.totalDebt()).toBytes();
   *
   *     case encodeSelector("accruedFees()"):
   *       return u256.fromU64(cauldron.accruedFees()).toBytes();
   *
   *     // --- Admin functions ---
   *     case encodeSelector("setTotalBorrowCap(u256)"):
   *       cauldron.setTotalBorrowCap(calldata.readU256());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("setTierBorrowCap(u8,u256)"):
   *       cauldron.setTierBorrowCap(calldata.readU8(), calldata.readU256());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("pause()"):
   *       cauldron.pause();
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("unpause()"):
   *       cauldron.unpause();
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("setOracle(address)"):
   *       cauldron.setOracle(calldata.readAddress());
   *       return BytesWriter.empty();
   *
   *     case encodeSelector("transferAdmin(address)"):
   *       cauldron.transferAdmin(calldata.readAddress());
   *       return BytesWriter.empty();
   *
   *     default:
   *       throw new Error("Cauldron: unknown selector");
   *   }
   * }
   */
}
