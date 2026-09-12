// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ILiquidatorMintable, LiqStats} from "./ILiquidatorMintable.sol";
import {PerpSwapLib} from "./PerpSwapLib.sol";

interface IPerpRegistry {
    function currentToken() external view returns (address);
    /// The quote a generation is priced in (0 = native ETH). Read as a mapping
    /// rather than via a convenience getter: the registry is at the EIP-170
    /// ceiling and cannot afford the extra dispatcher entry.
    function generationQuote(uint256 gen) external view returns (address);
    function currentGeneration() external view returns (uint256);
    function lastSummonAt() external view returns (uint256);
    function generationPoolId(uint256) external view returns (PoolId);
    function generationToken(uint256) external view returns (address);
    function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256);
    function claimByBurnUpTo(uint256 fromGen, uint256 maxAmount) external returns (uint256);
}

/// @notice The liquidity-weighted mark across a generation's pools. Zero-argument
///         because the engine calls it from a `view` on the hot path and cannot
///         spare the bytecode to encode arguments — the source knows its own pool
///         set. See {PerpMarkSource} and {PerpEngine._currentTick}.
interface IMarkSource {
    function weightedTick() external view returns (int24);
}

/// @dev Just enough of {PerpVault} to ask whether anyone still has value in it.
interface IPerpVaultStake {
    function hasStakers() external view returns (bool);
    /// @dev Does the QUOTE-denominated side still hold anyone's value?
    function hasQuoteStake() external view returns (bool);
}

interface IPerpHook {
    function isDead(PoolId id) external view returns (bool);
    /// @notice The active brew's NFT collection — where Liquidatoor badges mint.
    function collection() external view returns (address);
}

/**
 * @title PerpEngine — Phase 3 (LONGS + SHORTS, hardened)
 * @notice Hook-native, REAL-price-impact leverage on the current Cauldron
 *         iteration. Open/close/liquidate execute ACTUAL pool swaps, so leverage
 *         moves the real chart — and a short liquidation buys the token back,
 *         pumping spot (the reflexive squeeze). See design/perp-engine.md.
 *
 *  - LONG: borrows ETH from the PLV to buy token (price up). Closes by selling.
 *  - SHORT: borrows TOKEN from the PLV's token inventory, sells it (price down),
 *    holds ETH. Closes by buying the token back (price UP → squeeze) + returning
 *    it to the inventory. The inventory is seeded by an allocation of supply.
 *
 *  RISK LIMITS: leverage auto-capped by active-ETH depth (tiers) × deployer
 *  ceiling; per-position notional capped to a share of depth (bounded slippage →
 *  no single-position bad debt); long OI ≤ PLV ETH, short OI ≤ PLV token — the
 *  system can never lend what it doesn't hold. A funding index charges the
 *  crowded side (accrues to the PLV) to tether OI toward balance.
 *
 *  PHASE-3 HARDENING:
 *   • TWAP MARK — liquidations are triggered off a time-weighted average tick
 *     (own on-chain observation ring), so a single-block flash-move can't farm
 *     liquidations; execution still swaps at spot. Falls back to spot until the
 *     window has history (the 24h warmup covers the cold start).
 *   • PER-BLOCK LIQUIDATION CAP — the ETH-notional liquidated per block is capped
 *     to a share of depth, so an attacker can't engineer an unbounded atomic
 *     cascade (cross-block cascades still happen — that's the fun, just bounded).
 *   • DEATH FORCE-CLOSE — opens are blocked once the token is dead; any open
 *     position can be permissionlessly force-closed at that point (solvent,
 *     no penalty) so nothing is trapped across a relaunch.
 *
 *  FEES: 6.9%-of-collateral open fee (halved for genesis MiFren holders) + 6.9%
 *  liquidation penalty, split 60% OG-dividend / 40% treasury.
 */
contract PerpEngine is IUnlockCallback, Ownable, ReentrancyGuard {
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;
    address public immutable hookAddr;
    IPerpRegistry public immutable registry;
    IERC721 public immutable mifrens;

    uint24 public constant POOL_FEE = 0;
    int24 public constant TICK_SPACING = 200;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
    uint160 internal constant SQRT_MAX = 1461446703485210103287273052203988822378723970342;
    uint160 internal constant MIN_LIMIT = 4295128740;
    uint8 internal constant MODE_NORMAL = 0;
    uint8 internal constant MODE_LIQUIDATION = 1;
    uint8 internal constant MODE_DEATH = 2;

    // ── config (owner-tunable) ──
    address public dividend;
    address public treasury;
    /// @notice Who receives the crystal-gacha NFTs minted by PERP swap volume.
    ///         Perps generate real pool volume → the hook rolls the gacha → those
    ///         creatures accrue HERE (default: treasury) instead of being stranded
    ///         in the engine. NOTE: keep this NON-tax-exempt so perp swaps still
    ///         pay the hook fee into the OG dividend.
    address internal nftBeneficiary;
    uint256 internal openFeeBps = 690;
    uint256 internal ogDiscountBps = 5_000;
    //  `internal` to reclaim EIP-170 headroom for the R-07 staleness check in
    //  {_isDead}. Cold config with no on-chain, test, frontend or indexer reader
    //  (verified by grep across the repo) — read it from storage off-chain, the
    //  same trade already made for `markSource` at :462.
    uint256 internal liqPenaltyBps = 690;
    uint256 internal divShareBps = 6_000;
    // Liquidator's cut of the penalty. 145 bps × the 6.9% penalty ≈ 0.1% of the
    // liquidated collateral — a tiny ETH tip; the Liquidatoor BADGE is the real
    // prize. (Also sizes the death-clearing keeper reward, but death-clearing is
    // now largely automatic via the relaunch auto-migrate.) Owner/timelock-tunable.
    uint256 public keeperBps = 145; // ≈ 0.1% of collateral to the liquidator
    uint256 public warmup = 24 hours;
    uint256 internal maxLeverageCeiling = 3;
    uint256 public maintenanceBps = 1_500;
    uint256 public maxNotionalBps = 500;      // per-position notional ≤ 5% of depth
    //  `internal` to fund the R-07/L-2 guards against the EIP-170 ceiling. No
    //  reader anywhere in the tree (tests, deploy scripts, frontend, indexer or
    //  another contract) — verified by grep. Read it from storage off-chain, the
    //  same trade already made for `markSource` and the tier arrays.
    uint256 internal maxOiBps = 3_000;          // per-side OI ≤ 30% of depth
    /// @notice DUST FILTER: minimum ETH collateral to open a position. Stops bots
    ///         from spamming millions of dust positions (which would bloat the
    ///         liquidation set + heatmap and grief the batch auto-liquidator).
    ///         Owner-tunable. 0 = no floor.
    uint256 public minCollateral = 0.003 ether;
    /// @notice Hard cap on how many positions a single swap's batch auto-liq will
    ///         process — bounds gas so a swap can NEVER run out of gas on the
    ///         liquidation sweep, no matter how many hints are passed.
    uint256 internal constant MAX_LIQ_PER_SWAP = 8;
    /// @notice Hard cap on TOTAL live positions (audit A-03). `forceCloseAllDead`
    ///         clears at most FORCE_CLOSE_MAX per call, and the registry drives it
    ///         ONCE at relaunch — so if the book can grow beyond that bound, the
    ///         leftovers survive the rebirth and `syncGeneration` reverts
    ///         `PositionsOpen` FOREVER, stranding the entire token-side inventory in
    ///         a dead token. Worse, after the rebirth those positions can no longer
    ///         be closed at all: `_settle` would swap their old-generation sizes
    ///         against the NEW pool. Keeping the cap strictly below the force-close
    ///         bound makes "one relaunch clears the whole book" STRUCTURAL.
    ///         Deliberately a CONSTANT, not a tunable: it underwrites a structural
    ///         guarantee, so there must be no way to configure it into violation.
    uint256 public constant MAX_OPEN_POSITIONS = 64;
    /// @dev Positions cleared per `forceCloseAllDead` call. Must stay ABOVE
    ///      `maxOpenPositions` so a single call always drains the book.
    uint256 internal constant FORCE_CLOSE_MAX = 96;

    // ── Community PLV (LP-for-perps) ──
    /// @notice The PerpVault that supplies depositor liquidity + earns yield. When
    ///         set, deposits/withdrawals flow through it and a slice of fees is
    ///         routed to LP yield + the insurance buffer. Zero = owner-seeded only.
    address public vault;
    /// @notice ETH bad-debt buffer. A shortfall on close/liquidation (proceeds <
    ///         debt) is covered from here FIRST, so depositor principal is only
    ///         touched once this is exhausted. Auto-accrues from `insuranceBps`.
    /// @notice What this engine's book is denominated in: collateral, principal,
    ///         `plv`, `insuranceEth`, funding and every payout. `address(0)` is
    ///         native ETH.
    ///
    ///  Set when the engine adopts a generation and re-read on every sync, so it
    ///  always matches the pool it is trading against. The accounting itself was
    ///  always unit-agnostic — `plv` and the rest are plain counters — so only
    ///  the TRANSPORT differs: native arrives as `msg.value` and leaves by
    ///  `call{value:}`, an ERC20 arrives by `transferFrom` and leaves by
    ///  `transfer`.
    address public quote;

    /// @dev True when the book is denominated in native ETH.
    function _quoteIsNative() internal view returns (bool) { return quote == address(0); }

    /// @dev Pull `amount` of the quote from `from` into this engine.
    ///
    ///  Native: the value must already have arrived with the call, so this only
    ///  asserts it. ERC20: pulled by `transferFrom`, which requires a prior
    ///  approval — and any ETH sent alongside would be stranded, so it is
    ///  refused rather than silently kept.
    function _pullQuote(address from, uint256 amount) internal {
        if (_quoteIsNative()) {
            if (msg.value != amount) revert BadParam();
        } else {
            if (msg.value != 0) revert BadParam();
            //  Return value CHECKED. A non-standard token (USDT and most
            //  tokenized equities) returns false rather than reverting, and an
            //  unchecked pull would credit collateral that never arrived —
            //  a free position, paid for by everyone else's. The encode/call/decode
            //  itself lives in {PerpSwapLib} for EIP-170 headroom; as a DELEGATECALL
            //  its `address(this)` is still this engine, which is the pull target.
            if (!PerpSwapLib.tryTransferFrom(quote, from, amount)) revert BadParam();
        }
    }

    /// @dev Push `amount` of the quote to `to`, reverting on failure. For
    ///      recipients the protocol chooses (dividend, treasury) — an attacker
    ///      controlled one must use {_payOut} instead.
    function _pushQuote(address to, uint256 amount) internal {
        if (amount == 0) return;
        if (_quoteIsNative()) {
            (bool ok, ) = to.call{value: amount}("");
            if (!ok) revert EthSend();
        } else {
            _safeTransfer(quote, to, amount);
        }
    }

    uint256 public insuranceEth;
    /// @notice Of every ROUTED fee (open fee + liq penalty): this share stays in
    ///         the PLV as LP yield (raises share price), and `insuranceBps` funds
    ///         the buffer. The remainder splits dividend/treasury as before.
    uint256 internal vaultYieldBps = 3_000;   // 30% of routed fees → LP yield
    uint256 internal insuranceBps = 1_000;      // 10% of routed fees → insurance
    /// @notice Max share of vault assets lent to traders (per side). The rest is
    ///         always instantly withdrawable — the LP liquidity buffer. (80%)
    //  `internal` to fund the R-07/L-2 guards against the EIP-170 ceiling. No
    //  reader anywhere in the tree (tests, deploy scripts, frontend, indexer or
    //  another contract) — verified by grep. Read it from storage off-chain, the
    //  same trade already made for `markSource` and the tier arrays.
    uint256 internal maxUtilBps = 8_000;
    /// @notice Bad-debt circuit breaker: once insurance is depleted below this
    ///         (in wei), new opens are paused until it refills from fees. 0 = off.
    uint256 internal insuranceFloor;
    /// @notice Funding: annualized-ish rate applied to the net-imbalance fraction,
    ///         charged to the crowded side per second, accruing to the PLV.
    uint256 public fundingRateBpsPerDay = 100; // 1%/day at 100% imbalance

    // ── Phase-3 hardening knobs (owner-tunable) ──
    uint32 public twapWindow = 5 minutes;     // liquidation-mark averaging window
                                              // (5m resists flash-manip; 30m lags too much)
    uint256 public maxLiqBps = 2_000;         // ETH-notional liquidated ≤ 20% of depth / block
    uint256 public maxFundingBps = 5_000;     // |funding P&L| ≤ 50% of collateral (anti-drain cap)

    //  `internal`: a DYNAMIC-ARRAY auto-getter is the most expensive kind (bounds
    //  check + element return, one per array), and neither has a single reader
    //  outside this contract. Reclaimed for the R-07 check in {_isDead}.
    uint256[] internal tierDepthWei;
    ///  ── PACKED, NOT A SECOND ARRAY (EIP-170) ────────────────────────────
    ///  One leverage per tier, 8 bits each, tier 0 in the low byte: up to 32
    ///  tiers, which is 8x any configuration this protocol has ever used. A
    ///  second dynamic storage array cost 200+ B in {setTiers}'s calldata copy
    ///  alone, in a contract at the EIP-170 ceiling. The external signature and
    ///  the governance capability are unchanged.
    uint256 internal tierLevPacked;

    // ── TWAP oracle: a ring of cumulative-tick observations (Uniswap-style) ──
    // Writes are TIME-throttled (≥ OBS_INTERVAL apart) so the ring can't be
    // flooded to evict history — filling all slots takes CARDINALITY·OBS_INTERVAL
    // (~68 min) REGARDLESS of block time, so the ring is flood-proof on any chain.
    // Right-sized ring: a 5-min TWAP window at 30s min-spacing needs ~10 slots; 32
    // gives ≥16 min of history with ample margin. (Was 128 — a 5-min mark never
    // reads that far back, so `twapTick`'s per-liquidation loop was cold-reading 4×
    // more slots than it could ever use. Gas audit G-01.)
    uint16 internal constant OBS_CARDINALITY = 32;
    /// @dev OBS_CARDINALITY is a power of two, so ring wrap-around is a MASK rather
    ///      than a modulo — cheaper in gas and in bytecode. (Gas audit G-07.)
    uint16 internal constant OBS_MASK = OBS_CARDINALITY - 1;
    uint32 internal constant OBS_INTERVAL = 15 seconds; // min spacing between writes
    uint32 internal constant MIN_TWAP = 1 seconds;      // shortest mark we'll trust (fast L2: sub-second blocks → even 1s spans many blocks)
                                                        // (floor for a tunable window)
    struct Observation { uint32 ts; int56 tickCumulative; }
    //  `internal`, not `public` (EIP-170). The auto-generated array getter cost
    //  a dispatcher entry plus a bounds-checked struct return, and NOTHING read it
    //  — not a test, script, indexer or frontend (verified by grep). Everything
    //  anyone actually wants from the ring is already exposed by {twapTick} and
    //  {markSqrtPriceX96}; the raw slots are readable from storage off-chain. Same
    //  trade already made for `lastTick`, `maxUtilBps` and the tier arrays.
    Observation[OBS_CARDINALITY] internal observations;
    uint16 internal obsIndex;          // next slot to write
    int56 internal tickCumulative;     // Σ tick·dt up to lastObsTs
    uint32 internal lastObsTs;         // last time tickCumulative was INTEGRATED
    //  `internal` to fund the R-07/L-2 guards against the EIP-170 ceiling. No
    //  reader anywhere in the tree (tests, deploy scripts, frontend, indexer or
    //  another contract) — verified by grep. Read it from storage off-chain, the
    //  same trade already made for `markSource` and the tier arrays.
    int24 internal lastTick;
    /// @dev Last time a RING ENTRY was appended. Kept separate from `lastObsTs`
    ///      (audit A-02) so the integration clock can advance on EVERY observation
    ///      while ring appends stay throttled to OBS_INTERVAL — the two used to
    ///      share one clock, which is what let a stale tick poison the mark.
    ///      Packs into the same slot as the four fields above (16+56+32+24+32 bits).
    uint32 internal lastRingTs;
    /// @dev When the observation ring was last WIPED ({syncGeneration}). A wiped
    ///      ring reports a mark off one second of history: measured, the same 10 s
    ///      push moved the mark tick 1929 on a warm ring and 54545 on a fresh one,
    ///      still `ok == true`, because the fallback in {twapTick} only asks for
    ///      MIN_TWAP (1 s). The 24h open-warmup covers the COLD start but is read
    ///      off `registry.lastSummonAt()`, which a mid-generation quote rotation
    ///      does not move — so opens stayed live against the collapsed mark.
    ///      {_guardOpen} re-arms off this instead. (red-team H-4)
    uint32 internal ringArmedAt;

    // ── per-timestamp liquidation throttle ──
    // Keyed on block.timestamp, not block.number: on Arbitrum/Orbit block.number
    // is the L1 number (one value shared across ~13s of sub-second L2 blocks), so
    // a block.number key would let the cap span dozens of L2 blocks. timestamp is
    // per-L2-block, giving a tight (~per-second) throttle. Within a single atomic
    // tx both are constant, so the anti-cascade guarantee is identical.
    uint256 internal liqBlock;         // holds the last block.timestamp seen
    uint256 internal liqEthThisBlock;  // ETH-notional liquidated in that timestamp

    // ── hook-driven (in-swap) liquidation ──
    // `_inLocked` = we're already inside PoolManager's lock (the hook called us
    // from afterSwap), so swaps run directly instead of opening a new unlock.
    // `_liqReentry` = a lightweight guard so a hook-path liquidation can't nest.
    bool internal _inLocked;
    bool internal _liqReentry;

    // ── Perp Liquidity Vault (two-sided) ──
    uint256 public plv;         // ETH available to front long borrows
    uint256 public plvToken;    // token available to lend to shorts

    // ── side-attributed LP yield (Community PLV payout model) ──
    /// @notice Segregated ETH pot rewarding the TOKEN side (short-attributed
    ///         fees). Kept OUT of `plv`/`totalEth()` so it never inflates the
    ///         ETH-side share price — token stakers claim it via the vault.
    uint256 public tokYieldEth;
    /// @notice Lifetime ETH ever routed to the token side (monotonic ↑). The
    ///         vault folds deltas of this into its per-token-share accumulator.
    uint256 public tokYieldCumulative;

    // ── funding index (scaled 1e18); + means longs pay, − means shorts pay ──
    int256 internal fundingIndex;
    uint64 internal lastFundingAt;

    struct Position {
        address trader;
        bool    isLong;
        uint128 collateral;   // ETH stake (net of open fee)
        uint256 size;         // token: long → held; short → owed
        uint256 principal;    // long → ETH borrowed; short → ETH proceeds held
        uint64  openedAt;
        uint8   leverage;
        int256  entryFunding; // funding index snapshot at open
    }
    mapping(uint256 => Position) public positions;
    uint256 public nextId = 1;
    uint256 public openCount;    // live open positions (must be 0 to sync a new gen)

    /// @notice Liquidatoor badges earned but not yet minted (gas audit G-03 — the
    ///         badge is claimed via `claimLiquidatorBadges`, not minted in-swap).
    mapping(address => uint256) public badgesOwed;

    /// @notice ETH a settlement could not PUSH to a trader/keeper (their `receive()`
    ///         reverted). Claimed via {claimPayout}. This is what stops one hostile
    ///         trader from freezing every settlement path. (Audit H-04.)
    mapping(address => uint256) public payoutOwed;
    /// @notice Old-generation token inventory the best-effort migration left behind,
    ///         keyed by that token, so the books say "we hold X of the old token,
    ///         unmigrated" instead of implying zero.
    mapping(address => uint256) public strandedToken;
    /// @dev Σ of every unclaimed {payoutOwed} entry. The mapping itself cannot be
    ///      enumerated, so {syncGeneration}'s rotation guard reads this aggregate to
    ///      learn whether anyone is still owed the OLD quote.
    ///
    ///      PUBLIC deliberately. This is the one counter that can still REFUSE a
    ///      quote adoption, so "why did the sync not take?" has to be answerable
    ///      without a storage read: a non-zero value here names the reason, and
    ///      {retirePayout} is the lever. It was briefly `internal` to buy EIP-170
    ///      headroom; moving `TickMath.getSqrtPriceAtTick` into {PerpSwapLib} bought
    ///      far more, so the getter is back.
    uint256 public payoutOwedTotal;

    // ── Enumerable open set — lets ANY swap (any interface) scan + liquidate
    //    underwater positions without a hint. O(1) add/remove (swap-and-pop).
    uint256[] internal _openIds;                    // live position ids
    mapping(uint256 => uint256) internal _openPos;  // id → 1-based index in _openIds
    uint256 internal sweepCursor;                     // rotating scan start
    uint256 internal constant SWEEP_SCAN = 12;      // positions checked per swap
    /// @dev Gas a single in-swap liquidation needs to finish. Measured at ~388k
    ///      for one real kill (swap + settle + payouts); rounded up so the last
    ///      iteration the loop starts can always complete rather than reverting
    ///      the whole sweep. Pairs with {CauldronHook.LIQ_GAS_MIN}. See {_doSweep}.
    uint256 internal constant SWEEP_KILL_RESERVE = 420_000;
    uint256 public longOiEth;    // Σ ETH borrowed by open longs
    uint256 public shortOiToken; // Σ token owed by open shorts

    // ── per-iteration sync: one engine serves every generation ──
    uint256 public syncedGeneration; // the gen this engine's token-side is armed for
    address public syncedToken;      // that gen's token (what plvToken is denominated in)

    //  ── THIS ENGINE IS QUOTE-AGNOSTIC. THE `*Eth` NAMES ARE VESTIGIAL. ──────
    //
    //  A comment here used to say the opposite — that collateral, principal,
    //  funding and payouts were NATIVE ETH, that an ERC20-quoted generation
    //  "cannot be served correctly", and that it was refused via a
    //  `QuoteNotSupported` error. That predates the quote-agnostic conversion
    //  and every part of it is now wrong. The error it named was never thrown,
    //  which made the whole thing read like an unwired safety guard (audit Q-03).
    //
    //  What is actually true: `plv`, `collateral`, `principal`, `residual` and
    //  every payout are denominated in the GENERATION'S QUOTE. `_pullQuote` /
    //  `_pushQuote` move it, `_settle` swaps into it, and the price helpers work
    //  off the pool's Q96 `sqrtPrice`, which already encodes the decimal ratio
    //  between quote and token — so there is no 18-vs-6 decimal correction to
    //  make and none is missing. Identifiers like `longOiEth`, `activeEthDepth`
    //  and `buyEth` mean "in quote units"; they were named when the only quote
    //  was ether and renaming them all does not fit the EIP-170 budget.
    //
    //  The error and its comment are removed rather than left as a trap: the
    //  next reader who "fixes" the missing revert breaks multi-quote perps, and
    //  it costs 18 bytes the engine does not have.
    error NotWarm();
    error BadLeverage();
    error PlvInsufficient();
    error OiCapped();
    error NotTrader();
    error NotOpen();
    error Healthy();
    error Slippage();
    error EthSend();
    error ZeroValue();
    error TokenDead();
    error NotDead();
    error LiqCapped();
    error AlreadySynced();
    error PositionsOpen();
    error OnlyHook();
    error Reentrant();
    error NotVault();
    error UtilCapped();
    error InsurancePaused();
    error DustPosition();
    error BadParam();
    /// @notice The LP vault still holds quote-side value, so the engine may not
    ///         adopt a different quote yet. See {syncGeneration} (red-team R-08).
    ///         Named for the STAKE, not the event `VaultFunded` above it.
    error VaultStaked();
    error OwnershipCannotBeRenounced();

    /// @notice Ownership of this engine CANNOT be renounced.
    ///
    ///  {Ownable} ships `renounceOwnership()` live and unguarded, and this engine
    ///  holds trader collateral, the LP's `plv`, the token inventory lent to
    ///  shorts and the insurance buffer. The owner is the ONLY party who can call
    ///  {setRisk}, {setFees}, {setGuards}, {setVault}, {setVaultLimits},
    ///  {setMinCollateral}, {setMarkSource} or {skimInsurance} — i.e. every lever
    ///  that re-tunes the liquidation mark, the funding rate, the utilization cap
    ///  and the insurance floor after a quote rotation has moved the ground under
    ///  the book. One renounce, deliberate or fat-fingered, freezes all of them
    ///  forever with no recovery path on a live perp engine. There is no upside to
    ///  renouncing: the owner cannot touch a trader's position or an LP's shares.
    ///  Hand ownership to the timelock with `transferOwnership` instead.
    function renounceOwnership() public pure override {
        revert OwnershipCannotBeRenounced();
    }

    event Opened(uint256 indexed id, address indexed trader, bool isLong, uint256 collateral, uint256 size, uint8 leverage);
    event Closed(uint256 indexed id, address indexed trader, uint256 payout, int256 pnl);
    event Liquidated(uint256 indexed id, address indexed keeper, uint256 penalty);
    /// @notice A Liquidatoor badge was struck for `to` (the liquidator) as the
    ///         collectible trophy for liquidating position `id`. `badgeId` = 0
    ///         means the active collection wasn't wired for badges (skipped).
    event LiquidatoorAwarded(uint256 indexed id, address indexed to, uint256 badgeId);
    event FeeRouted(uint256 toDividend, uint256 toTreasury);
    event PlvFunded(uint256 eth, uint256 token);
    event BadDebt(uint256 shortfall, uint256 covered);
    event PayoutOwed(address indexed to, uint256 amount);
    /// @notice Token inventory that did NOT survive a generation migration, keyed by
    ///         the token it is still denominated in. The engine still HOLDS it.
    event TokenInventoryStranded(address indexed token, uint256 amount, uint256 migrated);
    /// @notice Token-side (short) LP reward that could not follow a quote rotation:
    ///         it was accrued in `asset` and the engine now pays in another one, so
    ///         it is swept to the treasury and written off here BY NAME rather than
    ///         disappearing into a counter reset. See {syncGeneration}.
    event TokYieldWrittenOff(address indexed asset, uint256 amount);
    event VaultFunded(bool isEth, uint256 amount);
    event VaultWithdrawn(bool isEth, uint256 amount, address to);
    event GenerationSynced(uint256 indexed fromGen, uint256 indexed toGen, uint256 migratedIn, uint256 newInventory);

    constructor(
        IPoolManager _poolManager, address _hook, address _registry, address _mifrens,
        address _dividend, address _treasury, address _owner
    ) Ownable(_owner) {
        poolManager = _poolManager; hookAddr = _hook; registry = IPerpRegistry(_registry);
        mifrens = IERC721(_mifrens); dividend = _dividend; treasury = _treasury;
        nftBeneficiary = _treasury; // perp-volume creatures → treasury by default
        tierDepthWei = [uint256(25 ether), 100 ether, 300 ether];
        tierLevPacked = 2 | (3 << 8) | (4 << 16) | (5 << 24);
        lastFundingAt = uint64(block.timestamp);
        // Seed the TWAP oracle with the live tick so the mark is meaningful from
        // block one (the ring fills as trades/pokes arrive).
        lastObsTs = uint32(block.timestamp);
        lastRingTs = uint32(block.timestamp);
        lastTick = _currentTick();
        observations[0] = Observation(uint32(block.timestamp), 0);
        obsIndex = 1;
        // Arm the token-side for whatever generation is live at deploy (0 if the
        // engine is deployed before the first summon — the first syncGeneration()
        // then arms gen-1). One engine serves every generation from here on.
        syncedGeneration = registry.currentGeneration();
        syncedToken = registry.currentToken();
    }

    /// @dev Block re-entry into any user entrypoint while an IN-SWAP liquidation
    ///      is settling (`_inLocked`). The hook-driven `liquidateInSwap` pays ETH
    ///      to an attacker-controlled keeper mid-settlement; without this, that
    ///      keeper could re-enter open/close/liquidate (the OZ `nonReentrant`
    ///      lock isn't engaged on the in-swap path). The engine never calls its
    ///      own entrypoints, so this never blocks legitimate flow. (Audit M-01)
    modifier notNested() {
        if (_inLocked || _liqReentry) revert Reentrant();
        _;
    }
    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    // ── Community PLV: views the PerpVault reads for share pricing ──────────
    /// @notice Total ETH the ETH-vault owns: free (lendable) + lent to open longs.
    ///         Insurance is NOT counted — it's a separate buffer, not LP equity.
    function totalEth() public view returns (uint256) { return plv + longOiEth; }
    /// @notice ETH instantly withdrawable (the un-lent buffer).
    function freeEth() external view returns (uint256) { return plv; }
    /// @notice Total token the token-vault owns: free inventory + lent to shorts.
    function totalTokenAssets() public view returns (uint256) { return plvToken + shortOiToken; }
    /// @notice Token inventory instantly withdrawable.
    function freeToken() external view returns (uint256) { return plvToken; }
    // (utilizationBps view removed to reclaim EIP-170 headroom for setTwapWindow —
    //  it had no on-chain/frontend/indexer consumers.)

    // ── pool + price ──
    /// @dev The live pool's key. Currencies are ORDERED BY ADDRESS as v4
    ///      requires: native ETH is address(0) and always sorts first, but an
    ///      ERC20 quote sorts against a CREATE-deployed token and may land
    ///      either side. Building the key with the quote pinned to currency0
    ///      would produce a key that hashes to a pool which does not exist.
    function _key() internal view returns (PoolKey memory) {
        address q = quote;
        address t = registry.currentToken();
        (address c0, address c1) = q < t ? (q, t) : (t, q);
        return PoolKey({currency0: Currency.wrap(c0), currency1: Currency.wrap(c1),
            fee: POOL_FEE, tickSpacing: TICK_SPACING, hooks: IHooks(hookAddr)});
    }
    function _sqrtP() internal view returns (uint160 s) { (s,,,) = poolManager.getSlot0(_key().toId()); }

    /// @notice Optional liquidity-weighted mark across the generation's pools.
    ///         Zero = read the primary pool's tick (the original behaviour).
    ///         Set through {setRouting}. See {PerpMarkSource}.
    ///
    ///  INTERNAL, not public: the auto-getter costs ~40 bytes and this contract
    ///  is at the EIP-170 ceiling. It is a cold config value — read it from
    ///  storage off-chain, or observe it the way the tests do, through the mark
    ///  it produces. Behaviour is the thing worth asserting anyway.
    address internal markSource;

    /// @dev 10**decimals of the LIVE quote; 1e18 for native. Adopted alongside
    ///      `quote` in {syncGeneration}.
    /// @dev Raw units of the live `quote` that carry the same VALUE as 1e18 wei of
    ///      ether, 1e18-scaled. 1e18 for a native-quoted brew. Re-derived at every
    ///      adoption by {PerpSwapLib.quoteFactor}; see {_q}.
    uint256 internal quoteUnit = 1e18;
    /// @dev The {QuoteOracle} the value scaling above is derived from. Set with the
    ///      rest of the engine's outbound wiring through {setRouting}; zero leaves
    ///      {_q} on unit scaling, which is the pre-oracle behaviour. `internal`, not
    ///      `public`: this contract has single-digit bytes of EIP-170 headroom and a
    ///      getter for a cold config slot is not worth one of them.
    address internal quoteOracle;

    /// @dev Re-express an 18-decimal (wei-written) CONFIG threshold in the live
    ///      quote's own units.
    ///
    ///  ── AN ABSOLUTE WEI CONSTANT IS A DENOMINATION BUG (red-team T02) ─────
    ///  Every absolute threshold in this contract was written in ether/wei and then
    ///  compared against a QUOTE-denominated amount. On a 6-decimal quote
    ///  `minCollateral = 0.003 ether` demanded 3e15 raw units — about $3bn — so a
    ///  $50,000 open reverted `DustPosition` and the entire book was closed for
    ///  business. A prior review filed that as "fails safe"; it fails CLOSED, which
    ///  takes the perp down. `insuranceFloor` (0.05 ether at deploy) and the
    ///  `tierDepthWei` leverage tiers fail identically, so all of them scale here
    ///  rather than each being patched where it happens to be read.
    ///
    ///  ── AND THE SCALE IS A VALUE, NOT A UNIT COUNT (red-team F-03) ────────
    ///  The first cut of this scaled by `10**decimals()`. But every constant here
    ///  is a VALUE statement: `tierDepthWei = [25, 100, 300] ether` means "≈ $80k /
    ///  $320k / $1M of pool depth", and unit-scaling turned it into $25 / $100 /
    ///  $300 on a 6-decimal stable — the leverage ceiling then applies at any
    ///  liquidity, the dust filter passes 3000 raw units of a $1 token, and the
    ///  insurance circuit breaker never trips. `decimals() == 0` made all three
    ///  exactly zero. `quoteUnit` is now the VALUE factor (see its declaration),
    ///  derived from the quote oracle at adoption and falling back to a clamped
    ///  unit count only when the quote is unpriceable.
    ///  No `u == 1e18` fast path: this is inlined at six call sites and the branch
    ///  cost bytes at every one of them. `wei18` is a config threshold (≤ 300 ether
    ///  by construction), so `wei18 * u` cannot overflow for any factor this
    ///  protocol can produce, and the native case multiplies and divides by 1e18.
    function _q(uint256 wei18) internal view returns (uint256) {
        return (wei18 * quoteUnit) / 1e18;
    }


    /**
     * @dev The tick the whole mark is built from.
     *
     *  ── WHY THE WEIGHTING GOES *HERE* (audit P-1 / Q-07) ───────────────────
     *  Every downstream consumer already funnels through this one function:
     *  `_writeObs` samples it into the TWAP ring, `twapTick()` integrates the
     *  ring, `markSqrtPriceX96()` converts that to a price, and `_quoteMark` →
     *  `_underwater` decides liquidations off it. So replacing this single read
     *  makes the entire stack multi-pool aware without touching the observation
     *  machinery, the binary search, or any settlement path — and the sample
     *  still goes through the TWAP, so a flash move in any one pool is averaged
     *  away exactly as before.
     *
     *  ── FAIL-SOFT, DELIBERATELY ────────────────────────────────────────────
     *  `staticcall` and not an interface call: this runs inside every swap's
     *  `afterSwap` and inside every liquidation check, so a mark source that
     *  reverts, self-destructs, returns garbage or is simply unset must degrade
     *  to the primary pool's tick rather than take trading and liquidation down
     *  with it. Wiring a mark source can therefore never be worse than not
     *  wiring one, which is what makes it safe to roll out on a live generation.
     *
     *  It is `staticcall` rather than `call` for a second reason: this is reached
     *  from `view` functions the vault and the frontend depend on, and a mark
     *  source must never be able to write to anything or re-enter the engine
     *  mid-liquidation.
     */
    ///  ── WHY ASSEMBLY ───────────────────────────────────────────────────────
    ///  The equivalent `m.staticcall(abi.encodeWithSelector(...))` plus
    ///  `abi.decode` costs ~90 bytes more, because it allocates a `bytes memory`
    ///  for a four-byte call and a thirty-two byte answer. This contract has
    ///  single-digit bytes of EIP-170 headroom; the hand-rolled version is what
    ///  makes the feature fit at all. It uses only the 0x00 scratch slot, so it
    ///  is memory-safe, and it rejects any answer that is not exactly one word.
    function _currentTick() internal view returns (int24 t) {
        address m = markSource;
        if (m != address(0)) {
            bytes4 sel = IMarkSource.weightedTick.selector;
            bool ok;
            int256 v;
            assembly ("memory-safe") {
                mstore(0x00, sel)
                ok := staticcall(gas(), m, 0x00, 0x04, 0x00, 0x20)
                //  A short or empty return would leave the scratch slot holding
                //  our own selector and read as a nonsense tick, so demand a full
                //  word before trusting it.
                ok := and(ok, eq(returndatasize(), 0x20))
                v := mload(0x00)
            }
            if (ok) return int24(v);
        }
        (, t,,) = poolManager.getSlot0(_key().toId());
    }

    // ── TWAP oracle ──────────────────────────────────────────────────────
    /// @notice Keep the engine's time-based state fresh between trades: records a
    ///         TWAP observation AND accrues the funding index. Open to keepers so
    ///         the mark and funding stay current even when nobody is trading.
    function poke() external { _pokeFunding(); }

    /**
     * @dev Sample the oracle.
     *
     *  MARK POISONING (audit A-02 — Critical). This used to bail out entirely when
     *  `dt < OBS_INTERVAL`, which left `lastTick` holding a STALE value. An attacker
     *  could exploit that with one atomic round-trip:
     *    1. CRASH spot with a large sell. The hook's afterSwap sweep pokes us, a
     *       write lands, and `lastTick` is frozen at the crashed tick.
     *    2. RESTORE spot by buying back in the SAME transaction. `dt == 0`, so the
     *       old code returned early and `lastTick` stayed CRASHED.
     *    3. Wait. `twapTick` extrapolates the un-recorded tail as
     *       `lastTick * (now - lastObsTs)`, so the crashed tick is integrated over
     *       the entire window even though spot never actually moved.
     *  The mark then reads far below reality and SOLVENT positions become
     *  liquidatable — the attacker collects the keeper reward and the trader is
     *  wrongly closed, for only the cost of the round-trip's fee and slippage.
     *
     *  Fix: ALWAYS integrate the elapsed interval and ALWAYS refresh `lastTick`, so
     *  the tail is extrapolated at the tick that is genuinely in force. Ring
     *  APPENDS remain throttled on their own clock (`lastRingTs`), preserving the
     *  flood-resistance that made the ring un-evictable.
     */
    ///
    ///  EPOCH-ROLLOVER SAFETY (audit F-10). Timestamps are packed as `uint32`, the
    ///  same trick Uniswap's oracle uses — but Uniswap performs every timestamp
    ///  DELTA inside an `unchecked` block, and this contract did not. `uint32` wraps
    ///  at 2^32 seconds (07 Feb 2106), after which `uint32(block.timestamp)` is
    ///  SMALLER than the stored `lastObsTs`, and a CHECKED `nowTs - lastObsTs`
    ///  PANICS instead of yielding the correct modulo-2^32 delta.
    ///  `_writeObs` is reached from `_pokeFunding`, which every single mutating perp
    ///  entrypoint calls — open, close, liquidate, `forceCloseDead`,
    ///  `forceCloseAllDead`, the in-swap sweep and `poke`. A panic there is not a
    ///  degraded oracle, it is a PERMANENT, unrecoverable brick: no position can
    ///  ever be closed, and because `forceCloseAllDead` also reverts, `openCount`
    ///  never returns to 0 and `syncGeneration` reverts `PositionsOpen` forever.
    ///  Doing the deltas `unchecked` restores Uniswap's semantics, under which the
    ///  arithmetic is exact for any span shorter than 2^32 seconds.
    function _writeObs() internal {
        uint32 nowTs = uint32(block.timestamp);
        unchecked {
            uint32 dt = nowTs - lastObsTs;
            if (dt > 0) {
                // Integrate the interval at the tick that was in force FOR it.
                tickCumulative += int56(lastTick) * int56(uint56(dt));
                lastObsTs = nowTs;
            }
            // Ring appends stay throttled on their OWN clock → still flood-proof.
            if (nowTs - lastRingTs >= OBS_INTERVAL) {
                observations[obsIndex] = Observation(nowTs, tickCumulative);
                obsIndex = (obsIndex + 1) & OBS_MASK;
                lastRingTs = nowTs;
            }
        }
        lastTick = _currentTick(); // ALWAYS refresh — never leave a stale tick
    }

    /// @notice Time-weighted average tick for the liquidation mark. Prefers a
    ///         lookback ≥ `twapWindow`; if the ring can't reach that far it falls
    ///         back to the OLDEST observation available, but only if that still
    ///         spans ≥ MIN_TWAP — so a flash-move can NEVER become the mark.
    ///         `ok=false` only at genuine cold-start (< MIN_TWAP of history),
    ///         which the 24h open-warmup covers.
    ///  GAS (gas audit G-06). Observations are written in strictly increasing
    ///  timestamp order into a wrapping ring, so the populated slots are already
    ///  SORTED when read from the oldest. `obsIndex` is the next slot to write,
    ///  which is therefore the OLDEST entry once the ring has wrapped. That lets us
    ///  BINARY SEARCH for the newest observation at or before `target` — about 5
    ///  SLOADs instead of the 32 the old linear scan always paid, on a path that
    ///  now runs on every open, close, liquidation and funding poke.
    ///  Every timestamp delta below is `unchecked` for the same reason as
    ///  {_writeObs} (audit F-10): `uint32` wrapping must yield the modulo-2^32
    ///  difference, not a panic. `twapTick` is a view, but it is called from
    ///  `markSqrtPriceX96` → `_quoteMark` → `_underwater`, i.e. from inside every
    ///  liquidation and settlement, so a panic here bricks those too.
    function twapTick() public view returns (int24 tick, bool ok) {
        uint32 nowTs = uint32(block.timestamp);
        if (nowTs <= MIN_TWAP) return (0, false);
        uint32 target;
        unchecked { target = nowTs - twapWindow; }

        // Locate the populated span in chronological order.
        uint16 next = obsIndex;
        uint16 n;      // how many observations are populated
        uint16 start;  // physical index of the OLDEST
        if (observations[next & OBS_MASK].ts != 0) {
            n = OBS_CARDINALITY; start = next;   // wrapped: `next` is the oldest
        } else {
            n = next; start = 0;                 // not yet wrapped: 0..next-1
        }
        if (n == 0) return (0, false);

        uint32 useTs; int56 useCum;
        Observation memory oldest = observations[start];
        if (oldest.ts > target) {
            // Ring can't reach back to the window — fall back to the OLDEST entry,
            // but only if it still spans MIN_TWAP so a flash move can't be the mark.
            unchecked { if (nowTs - oldest.ts < MIN_TWAP) return (0, false); }
            useTs = oldest.ts; useCum = oldest.tickCumulative;
        } else {
            // Largest i in [0, n) with obs(i).ts <= target.
            uint16 lo; uint16 hi = n - 1;
            while (lo < hi) {
                uint16 mid = (lo + hi + 1) >> 1;
                if (observations[(start + mid) & OBS_MASK].ts <= target) lo = mid;
                else hi = mid - 1;
            }
            Observation memory best = observations[(start + lo) & OBS_MASK];
            useTs = best.ts; useCum = best.tickCumulative;
        }
        int56 cumNow;
        int56 span;
        unchecked {
            cumNow = tickCumulative + int56(lastTick) * int56(uint56(nowTs - lastObsTs));
            span = int56(uint56(nowTs - useTs));
        }
        if (span == 0) return (0, false);
        tick = int24((cumNow - useCum) / span);
        ok = true;
    }

    /// @dev The manipulation-resistant mark sqrtPrice (TWAP tick; spot fallback).
    function markSqrtPriceX96() public view returns (uint160) {
        (int24 t, bool ok) = twapTick();
        return ok ? PerpSwapLib.sqrtPriceAtTick(t) : _sqrtP();
    }

    function activeEthDepth() public view returns (uint256) {
        PoolId id = _key().toId();
        uint160 sp = _sqrtP();
        if (sp == 0) return 0;
        return PerpSwapLib.ethDepth(poolManager.getLiquidity(id), sp);
    }

    function maxLeverage() public view returns (uint8 lev) {
        uint256 depth = activeEthDepth();
        uint256 p = tierLevPacked;
        lev = uint8(p & 0xff);
        if (lev == 0) lev = 2;                       // never configured -> the floor
        uint256 tiers = tierDepthWei.length;
        for (uint256 i = 0; i < tiers;) {
            if (depth >= _q(tierDepthWei[i])) lev = uint8((p >> ((i + 1) << 3)) & 0xff);
            unchecked { ++i; }
        }
        if (lev > maxLeverageCeiling) lev = uint8(maxLeverageCeiling);
    }

    /// @dev token→ETH value at sqrtPrice sp. Pool price p = (sp/Q96)² = token/ETH,
    ///      so ETH value = size/p = size·(Q96/sp)².
    ///  Body in {PerpSwapLib} for EIP-170 headroom: `FullMath.mulDiv` is an
    ///  INTERNAL library, so each of its call sites inlined the assembly — six
    ///  copies in this contract, which is at the ceiling, against kilobytes free
    ///  there. Pure value arguments, so the move is mechanical.
    function _quoteAt(uint256 size, uint256 sp) internal view returns (uint256) {
        return PerpSwapLib.quoteAt(size, sp);
    }
    /// @dev token→ETH at SPOT (used for funding sizing).
    function _quoteEth(uint256 size) internal view returns (uint256) { return _quoteAt(size, _sqrtP()); }
    /// @dev token→ETH at the TWAP MARK (used for liquidation triggers).
    function _quoteMark(uint256 size) internal view returns (uint256) { return _quoteAt(size, markSqrtPriceX96()); }

    // ── funding: accrue the global index by imbalance × elapsed ──
    function _pokeFunding() internal {
        _writeObs(); // sample the pre-trade tick for the TWAP mark
        uint256 dt = block.timestamp - lastFundingAt;
        if (dt == 0) return;
        lastFundingAt = uint64(block.timestamp);
        // Value the short OI at the manipulation-resistant MARK, not spot (audit
        // L-05). Liquidation already uses the mark; sizing the funding imbalance at
        // spot let an actor who can move price within a block bias the funding
        // direction. Every economically-significant valuation now uses one source.
        uint256 shortEth = _quoteMark(shortOiToken); // token OI valued in ETH
        uint256 total = longOiEth + shortEth;
        if (total == 0) return;
        // signed imbalance fraction × rate × dt → index step (1e18 scaled)
        int256 imbalance = int256(longOiEth) - int256(shortEth);
        int256 step = (imbalance * int256(fundingRateBpsPerDay) * int256(dt) * 1e18)
            / (int256(total) * int256(BPS) * int256(1 days));
        fundingIndex += step;
    }
    /// @dev Signed funding P&L for a position since open (ETH). Positive = this
    ///      position is on the CROWDED side and PAYS; negative = it's on the
    ///      underweight side and RECEIVES. It's a real transfer mediated by the
    ///      PLV (crowded pays in, underweight draws out) — solvent because the
    ///      crowded side's larger notional always pays in ≥ what the underweight
    ///      side draws. Bounded to ±maxFundingBps of collateral so funding can
    ///      never be weaponized to drain the vault or wipe a position.
    function _fundingDelta(Position memory p) internal view returns (int256) {
        int256 diff = fundingIndex - p.entryFunding;
        int256 signed = p.isLong ? diff : -diff; // +: crowded side → pays
        // Notional pinned to entry (collateral × leverage) — price-independent, so
        // funding can't be gamed by moving spot before close.
        uint256 notional = uint256(p.collateral) * p.leverage;
        int256 raw = (signed * int256(notional)) / 1e18;
        int256 cap = int256((uint256(p.collateral) * maxFundingBps) / BPS);
        if (raw > cap) raw = cap;
        if (raw < -cap) raw = -cap;
        return raw;
    }
    /// @notice Signed funding P&L for a live position (UI + solvency assertions).
    function fundingDelta(uint256 id) external view returns (int256) {
        Position memory p = positions[id];
        if (p.trader == address(0)) return 0;
        return _fundingDelta(p);
    }

    // ---------------------------------------------------------------------
    // Open
    // ---------------------------------------------------------------------
    struct SwapReq { bool buy; bool exactOut; uint256 amount; }

    // NOTE (EIP-170): the 2-arg `openLong(uint8,uint256)` overload was removed. It
    // was a pure forwarder to the 3-arg form, and every caller (the frontend, the
    // router, the tests) uses the 3-arg signature with `liqHint = 0`. Its dispatcher
    // entry + forwarding stub bought the headroom for the audit fixes.
    /// @notice Open a long. `liqHint` is vestigial (the post-open sweep is HINT-FREE
    ///         — see {_sweepAfterOpen}); pass 0. Kept only for ABI stability.
    /// @notice Collateral is stated explicitly as `amount` so a non-native quote
    ///         can be pulled by `transferFrom`. For a NATIVE book it must equal
    ///         `msg.value`; for an ERC20 book no value may be sent and the
    ///         caller must have approved this engine first.
    function openLong(uint8 leverage, uint256 minTokenOut, uint256 liqHint, uint256 amount)
        public payable nonReentrant notNested returns (uint256 id)
    {
        if (amount == 0) revert ZeroValue();
        _pullQuote(msg.sender, amount);
        _guardOpen(leverage);
        _pokeFunding();

        uint256 collateral = _takeFee(amount, true);
        if (collateral < _q(minCollateral)) revert DustPosition(); // dust filter, in QUOTE units
        uint256 borrow = collateral * (leverage - 1);
        if (borrow > plv) revert PlvInsufficient();
        // Community PLV: cap utilization so a share of depositor liquidity stays
        // instantly withdrawable, and pause opens if the insurance buffer is
        // depleted below the circuit-breaker floor (bad-debt protection).
        if (vault != address(0)) {
            if (longOiEth + borrow > (totalEth() * maxUtilBps) / BPS) revert UtilCapped();
            if (insuranceFloor > 0 && insuranceEth < _q(insuranceFloor)) revert InsurancePaused();
        }
        uint256 buyEth = collateral + borrow;
        _checkNotional(buyEth);
        if (longOiEth + borrow > (activeEthDepth() * maxOiBps) / BPS) revert OiCapped();

        plv -= borrow; longOiEth += borrow;
        uint256 sizeOut = _swapExactIn(true, buyEth); // ETH → token (price UP)
        if (sizeOut < minTokenOut) revert Slippage();

        id = _book(msg.sender, true, collateral, sizeOut, borrow, leverage);
        liqHint; // (legacy arg — the sweep below is hint-free)
        _sweepAfterOpen(msg.sender); // best-effort liquidate (gas-reserved + try/catch → never reverts the open)
    }

    /// @notice Open a short AND optionally rekt someone (see {openLong} liqHint).
    /// @notice Collateral is stated explicitly as `amount` so a non-native quote
    ///         can be pulled by `transferFrom`. For a NATIVE book it must equal
    ///         `msg.value`; for an ERC20 book no value may be sent and the
    ///         caller must have approved this engine first.
    function openShort(uint8 leverage, uint256 minEthOut, uint256 liqHint, uint256 amount)
        public payable nonReentrant notNested returns (uint256 id)
    {
        if (amount == 0) revert ZeroValue();
        _pullQuote(msg.sender, amount);
        _guardOpen(leverage);
        _pokeFunding();

        uint256 collateral = _takeFee(amount, false);
        if (collateral < _q(minCollateral)) revert DustPosition(); // dust filter, in QUOTE units
        // Notional (in ETH) = collateral × leverage; borrow that much TOKEN value.
        uint256 notionalEth = collateral * leverage;
        _checkNotional(notionalEth);
        uint256 tokenToSell = _ethToToken(notionalEth); // ETH notional → token at spot
        if (tokenToSell > plvToken) revert PlvInsufficient();
        // Community PLV: token-side utilization cap + insurance circuit breaker.
        if (vault != address(0)) {
            if (shortOiToken + tokenToSell > (totalTokenAssets() * maxUtilBps) / BPS) revert UtilCapped();
            if (insuranceFloor > 0 && insuranceEth < _q(insuranceFloor)) revert InsurancePaused();
        }
        if (shortOiToken + tokenToSell > (_ethToToken(activeEthDepth()) * maxOiBps) / BPS) revert OiCapped();

        plvToken -= tokenToSell; shortOiToken += tokenToSell;
        uint256 proceeds = _swapExactIn(false, tokenToSell); // sell borrowed token (price DOWN)
        if (proceeds < minEthOut) revert Slippage();

        // The engine holds collateral + proceeds ETH as backing for the token debt.
        id = _book(msg.sender, false, collateral, tokenToSell, proceeds, leverage);
        liqHint; // (legacy arg — the sweep below is hint-free)
        _sweepAfterOpen(msg.sender); // best-effort liquidate (gas-reserved + try/catch → never reverts the open)
    }

    // ---------------------------------------------------------------------
    // Close / liquidate
    // ---------------------------------------------------------------------
    function close(uint256 id, uint256 minOut) external nonReentrant notNested {
        Position memory p = positions[id];
        if (p.trader != msg.sender) revert NotTrader();
        _pokeFunding();
        _settle(id, p, minOut, MODE_NORMAL, address(0));
    }

    function liquidate(uint256 id) external nonReentrant notNested {
        Position memory p = positions[id];
        if (p.trader == address(0)) revert NotOpen();
        _pokeFunding();
        // Mark loop ONCE, reused for the health test + the per-block-cap notional.
        (bool trip, bool insolvent, uint256 notional) = _liqTest(p);
        if (!trip) revert Healthy();
        if (!_throttle(insolvent, notional)) revert LiqCapped();
        _settle(id, p, 0, MODE_LIQUIDATION, msg.sender);
    }

    /// @notice HINT-FREE auto-liquidation for ANY swap on ANY interface. The hook
    ///         calls this from afterSwap on every trade (Uniswap, aggregators,
    ///         bots, our UI) — it scans a bounded, ROTATING window of open
    ///         positions and liquidates whatever is underwater at the mark,
    ///         crediting `liquidator` (the swapper / tx.origin) a keeper reward +
    ///         a Liquidatoor badge per kill. Gas is bounded (≤ SWEEP_SCAN checks,
    ///         ≤ MAX_LIQ_PER_SWAP kills) so it can never OOG the parent swap, and
    ///         the cursor rotates so every position is eventually checked across
    ///         swaps. Hook-only, best-effort (never reverts the triggering swap).
    function sweepLiquidations(address liquidator) external {
        if (msg.sender != hookAddr) revert OnlyHook();
        _doSweep(liquidator, true);   // in-swap: settle swaps run in-place
    }

    /// @dev Post-open sweep entrypoint — called by the engine ON ITSELF (external
    ///      so it can be wrapped in try/catch), running a FRESH unlock. Lets an
    ///      open ALSO liquidate underwater positions without the liquidation
    ///      cascade ever reverting the trader's own open (best-effort).
    function selfSweep(address liquidator) external {
        if (msg.sender != address(this)) revert OnlyHook();
        _doSweep(liquidator, false);
    }
    /// @dev Fire the post-open sweep best-effort, reserving gas so it can never
    ///      revert the open, and capping it so a cascade can't consume everything.
    function _sweepAfterOpen(address liquidator) internal {
        uint256 g = gasleft();
        if (g <= 250_000) return;               // not enough to bother
        uint256 fwd = g - 120_000;              // keep a reserve for the open to finish
        try this.selfSweep{gas: fwd}(liquidator) {} catch {}
    }

    /// @dev Shared bounded rotating-window sweep. `inLocked` = we're already inside
    ///      PoolManager's lock (hook path → in-place swaps) vs a fresh unlock
    ///      (post-open path). Best-effort; the `_liqReentry` guard blocks nesting.
    function _doSweep(address liquidator, bool inLocked) internal {
        if (_liqReentry) return;
        // SAMPLE THE ORACLE FIRST, ALWAYS (audit Z-02). This used to sit AFTER the
        // empty-book early-return, which meant that while no position was open no
        // swap ever wrote an observation: `lastTick` stayed frozen at whatever it was
        // when the book last emptied, `_writeObs` then integrated the whole quiet
        // period at that stale tick, and `twapTick()` extrapolated it over the entire
        // lookback. The mark therefore returned the PRE-quiet-period price no matter
        // how far spot had moved, and the first position opened afterwards was born
        // liquidatable (or, in the mirror case, insolvent-but-unliquidatable, which
        // charges the PLV). Poking unconditionally is what actually makes the design
        // keeperless; it costs one observation write on an otherwise idle sweep.
        _pokeFunding();
        uint256 len = _openIds.length;
        if (len == 0) return;
        _liqReentry = true;
        _inLocked = inLocked;
        uint256 cursor = sweepCursor;
        uint256 scanned;
        uint256 kills;
        while (scanned < SWEEP_SCAN && scanned < len && kills < MAX_LIQ_PER_SWAP) {
            //  ── STOP BEFORE RUNNING OUT, NOT AFTER (red-team L-2) ───────────
            //  The hook fires this with a fixed gas budget and discards the
            //  result (CauldronHook.sol:912), so an OOG in here is not a partial
            //  sweep — the whole call reverts and EVERY kill in it is rolled
            //  back, silently. That made the book an attacker's lever: each
            //  parked liquidatable position raised the gas bar for the sweep by
            //  ~230k for everyone, so ~0.021 ETH of dust positions (minCollateral
            //  is 0.003 ether, :131) pushed the bar past what ordinary swaps
            //  carry and switched keeperless liquidation off pool-wide. Measured:
            //  just under the bar, ZERO of four liquidatable positions died and
            //  the swap still filled.
            //
            //  Breaking on the reserve makes the sweep DEGRADE instead: it banks
            //  the kills it could afford and leaves the rest for the next swap,
            //  which is the behaviour the bounded scan was already reaching for.
            if (gasleft() < SWEEP_KILL_RESERVE) break;
            uint256 n = _openIds.length;
            if (n == 0) break;
            if (cursor >= n) cursor = 0;
            uint256 id = _openIds[cursor];
            _tryLiquidate(id, liquidator);
            // If it liquidated, _removeOpen swap-popped the LAST id into `cursor`,
            // so DON'T advance (re-check the slot's new occupant); else advance.
            if (_openIds.length < n) { kills++; } else { cursor++; }
            scanned++;
        }
        sweepCursor = cursor;
        _inLocked = false;
        _liqReentry = false;
    }

    /// @dev Liquidate one position if {_liqTest} trips it and the per-block
    ///      throttle admits it; otherwise a silent no-op. Assumes the caller has
    ///      set `_inLocked`/`_liqReentry` and poked funding.
    ///  THIS IS THE PATH THAT CLOSES A POSITION INSIDE THE SWAP THAT KILLED IT, so
    ///  it must use exactly the same trigger as {liquidate} — see {_liqTest}.
    function _tryLiquidate(uint256 id, address liquidator) internal {
        Position memory p = positions[id];
        if (p.trader == address(0)) return;      // stale/closed hint
        (bool trip, bool insolvent, uint256 notional) = _liqTest(p);
        if (!trip) return;                          // healthy → skip
        if (!_throttle(insolvent, notional)) return; // capped → skip
        _settle(id, p, 0, MODE_LIQUIDATION, liquidator);
    }

    /// @notice Permissionless force-close once the token is DEAD, so no position
    ///         is trapped across a relaunch. Solvent (overcollateralized), no
    ///         liquidation penalty — but the caller earns a small keeper reward
    ///         (keeperBps of residual), so bots clear every position the instant a
    ///         token dies, well before a relaunch could strand it. The trader
    ///         keeps the rest of their equity.
    function forceCloseDead(uint256 id) external nonReentrant notNested {
        Position memory p = positions[id];
        if (p.trader == address(0)) revert NotOpen();
        if (!_isDead()) revert NotDead();
        _pokeFunding();
        _settle(id, p, 0, MODE_DEATH, msg.sender);
    }

    /// @notice Force-close EVERY open position on the dead token — OLDEST-FIRST
    ///         (lowest id = earliest opened, since ids are monotonic), deterministic
    ///         so no one can game the close order. Bounded to 64 per call (gas-safe;
    ///         a rare overflow finishes on the next call / the per-id path). Called
    ///         best-effort by the registry at relaunch (engine is tax-exempt, so the
    ///         settlement swaps don't touch the hook fee/buyback), so a staker's PLV
    ///         auto-migrates with no manual step. Reverts if not dead (no-op guard).
    function forceCloseAllDead() external nonReentrant notNested {
        if (!_isDead()) revert NotDead();
        _pokeFunding();
        // Close the front of the open set repeatedly — O(n) (the old per-close
        // min-scan was O(n²) and could OOG under many positions). `_settle`
        // swap-pops the closed id, so `_openIds[0]` always holds the next to close.
        // Deterministic + MEV-free (the caller can't influence which id is at [0]).
        // MAX_OPEN_POSITIONS (< FORCE_CLOSE_MAX) guarantees ONE call drains the
        // book — see the A-03 note on that constant.
        uint256 iters;
        while (openCount != 0 && iters < FORCE_CLOSE_MAX) {
            uint256 id = _openIds[0];
            _settle(id, positions[id], 0, MODE_DEATH, msg.sender);
            unchecked { iters++; }
        }
    }

    /// @notice Re-arm the engine for a NEW generation after a relaunch — the only
    ///         per-iteration housekeeping (one engine serves every generation).
    ///         Permissionless. Requires all positions force-closed first (so the
    ///         old-token accounting is settled), then:
    ///           1. MIGRATES the leftover dead-token inventory 1:1 into the new
    ///              token via the registry (burn old → get new from the reserve),
    ///           2. re-points plvToken to the engine's real new-token balance, and
    ///           3. resets the TWAP oracle for the new pool.
    ///         The ETH vault (plv) carries over untouched.
    function syncGeneration() external nonReentrant notNested {
        uint256 gen = registry.currentGeneration();
        //  A ROTATION CHANGES THE QUOTE WITHOUT CHANGING THE GENERATION.
        //  This used to refuse on `gen == syncedGeneration` alone, which made a
        //  live quote rotation unfollowable: `quote` is assigned only below, so
        //  the engine kept marking, funding and liquidating against the asset
        //  the generation launched with — the pool the rotation had drained —
        //  with no reachable call able to correct it until the next relaunch.
        //  Re-syncing on a quote change closes that, and costs nothing when the
        //  quote has not moved (the common case still reverts `AlreadySynced`).
        address newQuote = registry.generationQuote(gen);
        if (gen == syncedGeneration && newQuote == quote) revert AlreadySynced();
        if (openCount != 0) revert PositionsOpen(); // force-close everything first

        uint256 fromGen = syncedGeneration;
        uint256 migratedIn;
        bool migrating;
        // Migrate the engine's leftover (now-dead) inventory into the new token,
        // 1:1. Best-effort: if migration isn't available the sync still proceeds
        // (owner can re-seed via fundPlvToken), nothing bricks.
        if (fromGen != 0 && fromGen < gen && syncedToken != address(0)) {
            migrating = true;
            migratedIn = PerpSwapLib.migrateInventory(address(registry), syncedToken, fromGen);
        }

        // Re-arm the token side to whatever the engine now actually holds of the
        // current token, and clear the stale per-token OI (already 0 via settles).
        address newTok = registry.currentToken();
        uint256 newInv = newTok != address(0) ? IERC20(newTok).balanceOf(address(this)) : 0;
        //  ── TRACK THE SHORTFALL, DO NOT PAPER OVER IT ─────────────────────
        //  This was a bare `plvToken = newInv`. The migration above is BEST-EFFORT,
        //  so when it brought nothing across, the LP's token principal was silently
        //  overwritten with zero and the books stopped mentioning it — the accounting
        //  lied, and recovery depended on somebody noticing. Record what did NOT come
        //  across, against the token it is still denominated in: the engine is still
        //  HOLDING it, so recovery becomes mechanical. Deliberately does not revert —
        //  a reverting sync is the brick shape.
        //  ── ONLY A GENERATION CHANGE CAN STRAND INVENTORY (red-team F-05) ──
        //  On a QUOTE ROTATION `gen == syncedGeneration`, so the migration above is
        //  skipped and `migratedIn` stays 0 — because `newTok == syncedToken` and
        //  there was nothing to move, not because a move failed. Booking that as a
        //  shortfall recorded the ENTIRE live inventory to `strandedToken` (and
        //  announced it) one line before `plvToken` was re-set to the same real
        //  balance, so the books claimed the engine held it twice. Only the path
        //  that actually ATTEMPTED a migration can report one falling short.
        uint256 unmigrated = migrating && plvToken > migratedIn ? plvToken - migratedIn : 0;
        if (unmigrated != 0) {
            strandedToken[syncedToken] += unmigrated;
            emit TokenInventoryStranded(syncedToken, unmigrated, migratedIn);
        }
        plvToken = newInv;
        shortOiToken = 0;
        longOiEth = 0;

        // Reset the TWAP oracle — old-pool ticks are meaningless for the new token.
        delete observations;
        tickCumulative = 0;
        obsIndex = 1;
        lastObsTs = uint32(block.timestamp);
        lastRingTs = uint32(block.timestamp);
        ringArmedAt = uint32(block.timestamp);
        lastTick = _currentTick();
        observations[0] = Observation(uint32(block.timestamp), 0);

        //  ADOPT THE GENERATION'S QUOTE. Done at the single point the engine
        //  takes on a generation, so `quote` can never disagree with the pool it
        //  is trading against.
        //
        //  Refused while positions are still open in the OLD quote: their
        //  collateral, principal and payouts are denominated in it, and
        //  switching underneath them would re-denominate live user funds. The
        //  caller already requires openCount == 0 to sync, so this is a belt on
        //  that brace rather than a new restriction.
        //  `newQuote` was read at the top of this function (the guard needs it),
        //  so it is reused here rather than fetched twice.
        if (newQuote != quote && openCount != 0) revert PositionsOpen();
        //  ── NOR WHILE THE LP VAULT STILL HOLDS QUOTE-SIDE VALUE (R-08) ──────
        //  `plv` is a bare COUNTER of the quote asset, and `_sendEth` — the only
        //  way it is ever paid out — routes through `_pushQuote` (:1553), which
        //  pays in whatever `quote` says TODAY. Adopting a new quote therefore
        //  re-denominates every staked wei without moving any of it: an 18-decimal
        //  ETH balance starts being paid as a 6-decimal stable the engine does not
        //  hold, so `PerpVault.withdrawEth` reverts `BadParam()` inside
        //  `_safeTransfer` (:1473) and the staked ether is unreachable. Worse, the
        //  vault goes on pricing shares off that same counter (PerpVault.sol:116),
        //  so the next honest depositor in the NEW asset can be redeemed against
        //  by the stale ETH-side shares.
        //
        //  Refusing is the whole fix, and it needs no swap: `quote` stays put, so
        //  payouts stay native and every LP can exit normally. {_isDead} reads the
        //  divergence as death (see its note), which force-closes the book and
        //  stops new leverage, so the engine PARKS rather than mispaying. Once the
        //  vault has drained, `syncGeneration` is permissionless and adopts the new
        //  quote on the next call.
        //
        //  Only ever bites on a LIVE ROTATION: a relaunch clamps its quote to
        //  native (red-team B-05), so the rebirth path sees `newQuote == quote`
        //  and never reaches this line.
        if (newQuote != quote) {
            //  ── DEMANDING ZERO WAS A PERMANENT FREEZE (red-team X8-01) ────
            //  The first version of this guard required
            //  `plv | tokYieldEth | insuranceEth | payoutOwedTotal == 0`. THREE of
            //  those four cannot be driven to zero by a healthy engine:
            //    * `insuranceEth` is floored. {skimInsurance} protects
            //      max(insuranceFloor, riskMin) and deploy/DeployPerp.s.sol arms
            //      INSURANCE_FLOOR_WEI = 0.05 ether, so not one wei is skimmable
            //      below it — and the engine REQUIRES the buffer above that floor or
            //      every open reverts `InsurancePaused`. The guard demanded exactly
            //      the state that breaks the engine.
            //    * orphaned `tokYieldEth` (credited at zero token shares) is
            //      attributable to nobody and therefore never payable out (R-09), and
            //    * `plv` keeps a wei of redemption-floor dust behind the last staker.
            //  The sync then failed forever, `_isDead()` read true on the diverged
            //  quote, and the book was force-closed and frozen for the rest of the
            //  generation — at zero attacker cost, from the shipped default.
            //
            //  REDENOMINATE, don't refuse. Only what is genuinely owed BY NAME still
            //  gates, and both are satisfiable — {retirePayout} clears a stranded
            //  payout, and stakers can always exit:
            if (payoutOwedTotal != 0) revert VaultStaked();
            //  ── AND THE TOKEN SIDE MUST NOT GET A VETO (red-team F-01) ─────
            //  This asked `hasStakers()`, which is `(ethShares | tokShares |
            //  pendingEth | pendingTok) != 0`. The token side is NOT redenominated
            //  by a quote rotation — `tokShares`/`pendingTok` count the
            //  generation's TOKEN — so it has nothing to be protected from here,
            //  and it cannot be cleared without its owner's cooperation. One dust
            //  {PerpVault.depositToken} (≈ assetsTok()/1e6, enough for one share)
            //  therefore vetoed every future adoption, `_isDead()` read the
            //  divergence as death, and leverage was off for the whole generation
            //  with no governance escape — the X8-01 permanent-freeze shape,
            //  re-entered through the token side at negligible cost. The deploy
            //  script's own PLV_SEED_ETH reaches the same state by doing nothing
            //  wrong. Ask the QUOTE-side question the vault's header (PerpVault.sol
            //  :174-186) always documented as the one being asked:
            if (vault != address(0) && IPerpVaultStake(vault).hasQuoteStake()) revert VaultStaked();
            //  ...and with nobody left owning them, the protocol's own old-asset
            //  equity is swept to the treasury IN THE OLD ASSET — `quote` has not
            //  flipped yet, so `_payOut` still pays the right thing — and the
            //  counters are zeroed so no old-unit figure survives to claim units of
            //  the NEW asset. Opens
            //  stay paused until someone re-funds insurance in the new asset through
            //  the permissionless {fundInsurance} — honest, because there IS no
            //  buffer in the new asset yet. A pause, not a brick.
            //  ── AN EXPLICIT, LOGGED WRITE-OFF (red-team F-01) ──────────────
            //  `hasQuoteStake()` no longer covers the token side, so token stakers
            //  CAN still be present at this line — and `tokYieldEth` is their
            //  accrued short-side reward, denominated in the OLD quote. It cannot
            //  survive the flip (`_pushQuote` would pay an old-asset figure in the
            //  NEW asset, the exact redenomination e964d54 closed) and paying it on
            //  the way out needs a reachable per-asset parked pot this contract has
            //  no EIP-170 room for. So it is written off ON THE RECORD, naming the
            //  asset and the amount, and the value lands in the treasury with the
            //  rest of the sweep where governance can make the stakers whole. A
            //  bounded, announced, one-time loss of accrued REWARD in place of a
            //  permanent attacker-triggerable shutdown of the whole engine. Token
            //  PRINCIPAL (`plvToken`) is not touched here and stays withdrawable.
            uint256 writtenOff = tokYieldEth;
            emit TokYieldWrittenOff(quote, writtenOff);
            uint256 sweep = plv + writtenOff + insuranceEth;
            plv = 0; tokYieldEth = 0; insuranceEth = 0;
            if (sweep != 0 && treasury != address(0)) {
                //  DELIBERATELY NOT `_payOut`. That credits `payoutOwed` when the
                //  push fails — booking an OLD-asset amount that {claimPayout} would
                //  then pay out in the NEW one, which is the exact redenomination
                //  this block exists to prevent. A treasury that cannot accept the
                //  sweep leaves the value as engine residue owned by nobody, which
                //  is inert and cannot mispay anyone. Capped gas so a reverting
                //  treasury cannot burn the adoption's budget either.
                _tryPush(treasury, sweep, true); // retired either way — see above
            }
            //  ── THE MARK SOURCE MUST NOT SURVIVE THE ROTATION (red-team T02) ──
            //  {PerpMarkSource.primary} stays armed on the OLD pair, and the engine
            //  is not its owner so it cannot re-point it. Measured position-value
            //  overstatement on a rotated book: 112,805,296x. `_isDead` cannot catch
            //  it either — that test compares `quote` against `generationQuote`, and
            //  by this line those AGREE. So the pointer is dropped here and
            //  {_currentTick} fails soft to THIS engine's own `_key()`, which is
            //  correct for the new quote by construction. Governance re-arms the
            //  weighted mark on the new pair through {setRouting} when it is ready;
            //  until then the primary pool's tick is used, exactly as it is on any
            //  engine with no mark source wired.
            markSource = address(0);
            //  And the decimals the thresholds are compared in (see {_q}).
            //  ── AND THE VALUE THE THRESHOLDS ARE COMPARED IN (see {_q}) ────
            //  This was `unitOf(newQuote)`, which rescaled the UNITS only: on a
            //  6-decimal quote `25 ether` of tier depth became 25e6 raw = $25, and
            //  the leverage tiers, the dust filter and the insurance circuit
            //  breaker all lost ~1e12 of economic meaning (red-team F-03).
            quoteUnit = PerpSwapLib.quoteFactor(quoteOracle, newQuote);
        }
        quote = newQuote;

        syncedGeneration = gen;
        syncedToken = newTok;
        emit GenerationSynced(fromGen, gen, migratedIn, newInv);
    }

    /// @notice Whether a position is liquidatable right now — the same test the
    ///         keeper path and the in-swap sweep use. See {_liqTest}.
    function isLiquidatable(uint256 id) external view returns (bool) {
        Position memory p = positions[id];
        if (p.trader == address(0)) return false;
        return _underwater(p);
    }

    /// @dev The liquidation trigger, for the views. See {_liqTest}.
    function _underwater(Position memory p) internal view returns (bool trip) {
        (trip, , ) = _liqTest(p);
    }

    /**
     * @dev THE LIQUIDATION TRIGGER: the WORSE of the TWAP mark and live SPOT.
     *
     *  ── WHY TWO PRICES (red-team LIQ-01, measured on Sepolia r42) ───────────
     *  The mark was the ONLY test, and the mark is a `twapWindow`-long average. So
     *  a single large swap could carry a position from healthy to deeply insolvent
     *  INSIDE the trade that the hook's afterSwap sweep runs on: the sweep asked
     *  the mark, the mark still reported the pre-trade price, the position survived
     *  the swap that killed it, and by the time the average caught up the loss was
     *  whatever the market had done in the meantime. Measured: 0.05 ETH of
     *  collateral carrying a 4.43 ETH realised loss (-9526%), every wei of it bad
     *  debt against `insuranceEth` and then the stakers' PLV.
     *
     *  ── THE MANIPULATION TRADE-OFF, STATED ─────────────────────────────────
     *  The TWAP stays the PRIMARY test and keeps its `maintenanceBps` buffer, so an
     *  ORDINARY liquidation — a position that has merely eaten into its margin —
     *  still needs a SUSTAINED move and CANNOT be triggered by a one-block push.
     *  That is the property the TWAP exists for and it is not weakened here.
     *
     *  SPOT is a SECOND trigger carrying NO maintenance buffer at all: it fires
     *  only when the position is ALREADY INSOLVENT at the price the pool just
     *  filled at — its own backing can no longer repay its own debt. That is a
     *  strictly WIDER margin than the mark's, and it is the right place to draw the
     *  line, because the two sides of the trade-off are not symmetric:
     *    * a merely-unhealthy position costs the vault NOTHING to leave open, so
     *      there is no hurry and the manipulation-resistant average should decide;
     *    * past zero equity every further block is bad debt the vault eats, and
     *      waiting cannot make it smaller.
     *  An attacker who wants to trip the spot leg must therefore push spot past a
     *  victim's ENTIRE equity, not merely through its maintenance buffer, and must
     *  pay that impact into the same pool the liquidation's own settlement swap
     *  then unwinds against. The control for this is asserted in
     *  test/attacks/XL1_LiqTwapAndDepthCap.t.sol.
     *
     * @return trip      liquidatable at all.
     * @return insolvent backing cannot cover the debt at one of the two prices.
     *                   This is the flag that EXEMPTS the per-block throttle —
     *                   see {_throttle}.
     * @return notional  the mark ETH-notional, reused as the throttle's magnitude
     *                   (the mark is a 32-slot loop, so it is computed once —
     *                   gas audit G-02).
     */
    function _liqTest(Position memory p) internal view returns (bool trip, bool insolvent, uint256 notional) {
        notional = _quoteMark(p.size);
        trip = _underwaterVal(p, notional);
        insolvent = _insolventVal(p, notional);
        if (!insolvent) {
            //  `_sqrtP() == 0` means the pool is not initialized, in which case
            //  there is no spot price to judge by — leave the mark's answer alone
            //  rather than dividing by zero on a path the hook cannot afford to
            //  have revert.
            uint160 sp = _sqrtP();
            if (sp != 0) insolvent = _insolventVal(p, _quoteAt(p.size, sp));
        }
        if (insolvent) trip = true;
    }

    /// @dev ZERO-BUFFER solvency at `val`: can the position's own backing still
    ///      repay its own debt? True here means the VAULT is already carrying the
    ///      difference, so every block of delay grows the hole.
    function _insolventVal(Position memory p, uint256 val) internal pure returns (bool) {
        return p.isLong ? val < p.principal : val > uint256(p.collateral) + p.principal;
    }

    /**
     * @dev The per-block liquidation throttle: bound the ETH-notional liquidated
     *      per block so nobody can engineer an unbounded ATOMIC cascade.
     *
     *  ── A THROTTLE MUST NEVER CREATE PERMANENT BAD DEBT (red-team LIQ-01) ───
     *  `cap` is a share of ACTIVE POOL DEPTH, so a position whose notional had
     *  grown past that depth could not fit under it at ANY `maxLiqBps` — 100% still
     *  reverted `LiqCapped()` on the live engine, because notional 4.35 ETH >
     *  depth 2.6 ETH. The anti-cascade throttle was converting a solvable
     *  liquidation into permanently UNLIQUIDATABLE bad debt, which is strictly
     *  worse than the cascade it exists to bound.
     *
     *  An INSOLVENT position is therefore EXEMPT. The cascade the cap guards
     *  against is one of merely-unhealthy positions being force-closed together to
     *  push the price; delaying an insolvent close never makes the vault whole, it
     *  only grows the hole, and the close itself REDUCES the vault's exposure. The
     *  notional is still BOOKED against the block's budget, so one large insolvent
     *  close still crowds out the discretionary ones queued behind it in the same
     *  block — the cap keeps doing its real job.
     *
     * @return true when the liquidation may proceed.
     */
    function _throttle(bool insolvent, uint256 notional) internal returns (bool) {
        if (block.timestamp != liqBlock) { liqBlock = block.timestamp; liqEthThisBlock = 0; }
        uint256 cap = (activeEthDepth() * maxLiqBps) / BPS;
        if (!insolvent && cap > 0 && liqEthThisBlock + notional > cap) return false;
        liqEthThisBlock += notional;
        return true;
    }

    /// @dev Underwater test given the position's ALREADY-COMPUTED mark value
    ///      (`val = size @ TWAP mark`). The mark is a 32-slot loop, so callers in
    ///      the liquidation hot path compute it ONCE and pass `val` in here AND
    ///      reuse it as the per-block-cap notional — never looping twice. (Gas
    ///      audit G-02: was recomputed 2-3× per liquidation.)
    function _underwaterVal(Position memory p, uint256 val) internal view returns (bool) {
        if (p.isLong) {
            // token worth less than debt + maintenance buffer
            return val < p.principal + (p.principal * maintenanceBps) / BPS;
        } else {
            // buying the owed token back costs more than the ETH backing − buffer
            uint256 backing = uint256(p.collateral) + p.principal;
            uint256 buffer = (backing * maintenanceBps) / BPS;
            return val + buffer > backing;
        }
    }

    function _settle(uint256 id, Position memory p, uint256 minOut, uint8 mode, address keeper) internal {
        delete positions[id];
        _removeOpen(id); // enumerable set
        openCount--;
        uint256 residual;
        bool ownerSlippage = mode == MODE_NORMAL; // only the trader's own close enforces minOut

        if (p.isLong) {
            longOiEth -= p.principal;
            uint256 proceeds = _swapExactIn(false, p.size); // sell held token → ETH
            if (ownerSlippage && proceeds < minOut) revert Slippage();
            uint256 repay = proceeds >= p.principal ? p.principal : proceeds;
            plv += repay;
            // Bad debt (proceeds < principal): `plv` already booked the reduced
            // return, so REPLENISH it from insurance up to the buffer. Only an
            // insurance-exhausting gap leaves a residual LP loss (already
            // reflected in plv). (Audit V-01: long path replenishes plv.)
            if (proceeds < p.principal) _replenishPlv(p.principal - proceeds);
            residual = proceeds - repay;
        } else {
            shortOiToken -= p.size;
            // Buy back EXACTLY the borrowed token (price UP → squeeze) so the
            // inventory is made whole, paying ETH from the position's backing.
            uint256 backing = uint256(p.collateral) + p.principal;
            uint256 cost = _buyExactOut(p.size); // ETH → exactly p.size token
            plvToken += p.size;                  // inventory returned in full
            // The buy-back may have spent MORE ETH than this position's backing;
            // that overspend came out of the engine's raw ETH (the PLV). ABSORB
            // it — insurance first, then LP principal — so `plv` matches reality.
            // (Audit V-01: short path must DECREASE plv, not increase it.)
            if (cost > backing) _absorbPlvLoss(cost - backing);
            residual = backing > cost ? backing - cost : 0;
            if (ownerSlippage && residual < minOut) revert Slippage();
        }

        // Settlement tail — funding transfer + (on a liquidation) the penalty and
        // keeper cut. Pure arithmetic, extracted to {PerpOps} for EIP-170 headroom
        // (audit I-06); semantics are unchanged. Funding is a REAL transfer via the
        // PLV: crowded side pays IN, underweight side draws OUT, neither overdraws.
        //  FUNDING IS NOT A CLOSED TRANSFER (audit A-04). The paying side is capped
        //  by its OWN residual — an underwater position (and EVERY liquidated long,
        //  where `repay = proceeds` leaves `residual == 0`) pays less than it owes —
        //  while the receiving side used to draw in full against the whole vault.
        //  The difference came straight out of LP principal.
        //  Receivers are now paid from the INSURANCE buffer first, exactly like
        //  every other bad-debt path in this contract (`_replenishPlv` /
        //  `_absorbPlvLoss`), so an unmatched funding claim consumes the buffer that
        //  exists for it before it can touch depositor capital.
        int256 fd = _fundingDelta(p);
        if (fd > 0) {
            uint256 pay = uint256(fd);
            if (pay > residual) pay = residual;      // can't pay more than it has
            plv += pay; residual -= pay;
        } else if (fd < 0) {
            uint256 credit = uint256(-fd);
            uint256 fromIns = credit < insuranceEth ? credit : insuranceEth;
            insuranceEth -= fromIns;                 // buffer absorbs it first
            uint256 rest = credit - fromIns;
            if (rest > plv) rest = plv;              // never overdraw the vault
            plv -= rest;
            residual += fromIns + rest;
        }

        if (mode == MODE_LIQUIDATION) {
            uint256 penalty = (uint256(p.collateral) * liqPenaltyBps) / BPS;
            if (penalty > residual) penalty = residual;
            uint256 toKeeper = (penalty * keeperBps) / BPS;
            residual -= penalty;
            _routeFee(penalty - toKeeper, p.isLong); // long liq → ETH side, short liq → token side
            if (toKeeper > 0) _payOut(keeper, toKeeper);
            emit Liquidated(id, keeper, penalty);
            // Strike the Liquidatoor badge — the collectible trophy for the fren
            // responsible for this liquidation (keeper call → caller; in-swap →
            // the swapper). Best-effort so it can never brick a liquidation.
            //
            // The stats are recorded ON-CHAIN with the badge so the trophy can be
            // rendered from chain state alone. Entry is derived from the position
            // (principal/size for a long, proceeds/size for a short); liq price is
            // the mark that triggered this close.
            _awardBadge(id, keeper, _killStats(p, toKeeper));
        } else if (mode == MODE_DEATH && keeper != address(0)) {
            // small keeper reward incentivizes prompt death-clearing (no penalty).
            uint256 reward = (residual * keeperBps) / BPS;
            if (reward > 0) { _payOut(keeper, reward); residual -= reward; }
        }
        if (residual > 0) _payOut(p.trader, residual);
        emit Closed(id, p.trader, residual, int256(residual) - int256(uint256(p.collateral)));
    }

    // ---------------------------------------------------------------------
    // Swaps (real pool impact)
    // ---------------------------------------------------------------------
    /// @dev Run a swap request either by opening a fresh PoolManager lock (normal
    ///      path) or directly when we're ALREADY inside a lock (`_inLocked`, i.e.
    ///      a hook-driven in-swap liquidation) — the manager is unlocked during
    ///      the hook's afterSwap, so re-`unlock`ing would revert.
    function _run(SwapReq memory r) internal returns (bytes memory) {
        // In-lock path passes the struct straight through — no encode/decode
        // round-trip (gas audit G-05); only `unlock` needs the bytes marshalling.
        return _inLocked ? _swapBody(r) : poolManager.unlock(abi.encode(r));
    }
    /// @dev Exact-INPUT swap. buy=true → spend `amount` ETH for token (returns
    ///      token out); buy=false → sell `amount` token for ETH (returns ETH out).
    function _swapExactIn(bool buy, uint256 amount) internal returns (uint256 out) {
        out = abi.decode(_run(SwapReq(buy, false, amount)), (uint256));
    }
    /// @dev Exact-OUTPUT buy: acquire EXACTLY `tokenOut` token, paying ETH.
    ///      Returns the ETH spent. Used to make the short inventory whole.
    function _buyExactOut(uint256 tokenOut) internal returns (uint256 ethSpent) {
        ethSpent = abi.decode(_run(SwapReq(true, true, tokenOut)), (uint256));
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotTrader();
        return _swapBody(abi.decode(raw, (SwapReq)));
    }

    /// @dev The swap body — shared by the unlock path (`unlockCallback`) and the
    ///      in-lock path (`_run` when `_inLocked`). Performs the pool swap and
    ///      settles both currency legs; returns the ABI-encoded result.
    function _swapBody(SwapReq memory r) internal returns (bytes memory) {
        PoolKey memory key = _key();
        //  WHICH SIDE IS WHICH. v4 orders currencies by address: native ETH is
        //  address(0) and always sorts first, so "quote = currency0" held for
        //  free. An ERC20 quote sorts against a CREATE-deployed token and can
        //  land on either side, which would invert every leg below.
        //
        //  Derived from `syncedToken` rather than stored: the engine already
        //  pins the generation's token when it arms, so this cannot drift.
        bool q0 = Currency.unwrap(key.currency1) == syncedToken;

        // Attribute the gacha volume to the NFT beneficiary (treasury) so the
        // creatures minted by perp volume land there, not stranded in the engine.
        (uint256 spent, uint256 got) = PerpSwapLib.swapLeg(
            poolManager,
            key,
            PerpSwapLib.Req({buy: r.buy, exactOut: r.exactOut, amount: r.amount}),
            q0,
            abi.encode(nftBeneficiary)
        );
        if (r.buy) return abi.encode(r.exactOut ? spent : got);
        return abi.encode(got);
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------
    function _guardOpen(uint8 leverage) internal view {
        //  TWO gates, one comparison (EIP-170). The SUMMON warmup, and — since a
        //  mid-generation quote rotation does not move `lastSummonAt` but
        //  {syncGeneration} does delete the whole observation ring, after which
        //  `twapTick`'s oldest-entry fallback trusts as little as MIN_TWAP (1 s) of
        //  history — the RING warmup too. No position may be opened until the ring
        //  genuinely spans `twapWindow` again. (red-team H-4)
        uint256 summonWarm = registry.lastSummonAt() + warmup;
        uint256 ringWarm = uint256(ringArmedAt) + twapWindow;
        if (block.timestamp < (summonWarm < ringWarm ? ringWarm : summonWarm)) revert NotWarm();
        if (_isDead()) revert TokenDead(); // no leverage into a death
        if (leverage < 1 || leverage > maxLeverage()) revert BadLeverage();
    }
    ///  ── A KEY THE ENGINE CAN NO LONGER TRADE IS AS GOOD AS DEAD (R-07) ────
    ///  `quote` is a CACHE, adopted only in {syncGeneration} (:1027), which
    ///  refuses while `openCount != 0` (:987). A live rotation that completes
    ///  while this engine is unwired — which {CauldronHook.linkVolume}'s own note
    ///  used to recommend ("or unset the engine") — leaves that cache pointing at
    ///  the asset the treasury has just drained, and nothing could put it right:
    ///  `forceCloseDead`/`forceCloseAllDead` both demand a DEAD pool, the
    ///  pre-rotation pool is drained but very much alive, so `openCount` never
    ///  fell and `syncGeneration` reverted `PositionsOpen()` for the rest of the
    ///  generation. Meanwhile the engine went on marking, funding and liquidating
    ///  against a pool that is cheap to push (CauldronHook.sol:1500-1508), and
    ///  `_guardOpen` (:1210) kept selling leverage into it.
    ///
    ///  Treating a diverged quote as death fixes both halves with one test, and
    ///  neither is a new restriction: it makes the book FORCE-CLOSEABLE by anyone
    ///  (so the engine can be re-pointed without waiting for a rebirth), and it
    ///  makes `_guardOpen` refuse new leverage into an engine that cannot price
    ///  itself. When the quote agrees — every ordinary block — this is one
    ///  comparison and the behaviour is unchanged.
    function _isDead() internal view returns (bool) {
        if (quote != registry.generationQuote(registry.currentGeneration())) return true;
        try IPerpHook(hookAddr).isDead(_key().toId()) returns (bool d) { return d; } catch { return false; }
    }
    function _takeFee(uint256 sent, bool longSide) internal returns (uint256 collateral) {
        uint256 fee = (sent * openFeeBps) / BPS;
        if (mifrens.balanceOf(msg.sender) > 0) fee = (fee * (BPS - ogDiscountBps)) / BPS;
        collateral = sent - fee;
        _routeFee(fee, longSide);
    }
    function _checkNotional(uint256 notionalEth) internal view {
        if (notionalEth > (activeEthDepth() * maxNotionalBps) / BPS) revert BadLeverage();
    }
    function _book(address trader, bool isLong, uint256 collateral, uint256 size, uint256 principal, uint8 leverage)
        internal returns (uint256 id)
    {
        // A-03: refuse to grow the book past what one force-close can clear.
        if (openCount >= MAX_OPEN_POSITIONS) revert OiCapped();
        id = nextId++;
        openCount++;
        positions[id] = Position(trader, isLong, uint128(collateral), size, principal,
            uint64(block.timestamp), leverage, fundingIndex);
        _openIds.push(id); _openPos[id] = _openIds.length; // enumerable add
        emit Opened(id, trader, isLong, collateral, size, leverage);
    }
    /// @dev Remove a settled position from the enumerable open set (swap-and-pop).
    function _removeOpen(uint256 id) internal {
        uint256 idx = _openPos[id];
        if (idx == 0) return;
        uint256 lastId = _openIds[_openIds.length - 1];
        _openIds[idx - 1] = lastId;
        _openPos[lastId] = idx;
        _openIds.pop();
        delete _openPos[id];
    }
    /// @dev ETH→token amount at spot: tokens = eth·p = eth·(sp/Q96)².
    function _ethToToken(uint256 eth) internal view returns (uint256) {
        return PerpSwapLib.ethToToken(eth, _sqrtP());
    }

    function _routeFee(uint256 amount, bool longSide) internal {
        if (amount == 0) return;
        // Community PLV: carve LP yield + insurance FIRST (both stay in the engine
        // as ETH — plv grows → share price up; insuranceEth buffers bad debt).
        // Only active once a vault is wired; otherwise 100% splits div/treasury.
        if (vault != address(0)) {
            uint256 toVault = (amount * vaultYieldBps) / BPS;
            uint256 toIns = (amount * insuranceBps) / BPS;
            // Side-attributed: LONG fees reward the ETH side (plv → share price ↑);
            // SHORT fees reward the TOKEN side (segregated `tokYieldEth`, claimed as
            // ETH via the vault). If no token stakers exist yet, the yield simply
            // waits in the pot for the first one (the vault's accumulator doesn't
            // advance at zero shares) — no ETH is ever stranded.
            if (longSide) {
                plv += toVault;                       // ETH-side LP yield
            } else {
                tokYieldEth += toVault;               // token-side reward pot (ETH)
                tokYieldCumulative += toVault;        // monotonic accrual marker
            }
            insuranceEth += toIns;       // shared bad-debt buffer
            amount -= toVault + toIns;
            if (amount == 0) { emit FeeRouted(0, 0); return; }
        }
        uint256 toDiv = (amount * divShareBps) / BPS;
        uint256 toTre = amount - toDiv;
        if (toDiv > 0 && dividend != address(0)) _payOut(dividend, toDiv);
        if (toTre > 0 && treasury != address(0)) _payOut(treasury, toTre);
        emit FeeRouted(toDiv, toTre);
    }
    function _sendEth(address to, uint256 amount) internal { _pushQuote(to, amount); }

    /// @dev SETTLEMENT-SAFE payout (audit H-04). Used for the two recipients a
    ///      SETTLEMENT pays that an attacker controls: the position's trader and the
    ///      keeper. A contract whose `receive()` reverts could otherwise make its own
    ///      position permanently unsettleable — which cascades: `forceCloseAllDead`
    ///      reverts wholesale, so `openCount` never reaches 0, so `syncGeneration`
    ///      reverts `PositionsOpen` forever and the engine is stranded on a DEAD
    ///      token with the entire short inventory denominated in it. Crediting
    ///      instead of reverting removes the griefing primitive entirely; the funds
    ///      remain fully claimable via {claimPayout}. Bounded gas so a recipient
    ///      cannot consume the settlement's budget either.
    function _payOut(address to, uint256 amount) internal {
        if (amount == 0) return;
        if (!_tryPush(to, amount, true)) {
            unchecked { payoutOwed[to] += amount; payoutOwedTotal += amount; }
            emit PayoutOwed(to, amount);
        }
    }

    /// @dev Push the quote to `to` and REPORT failure instead of reverting. Shared
    ///      by all three pushes that must survive a hostile recipient: {_payOut},
    ///      the rotation sweep, and {retirePayout}.
    ///
    ///  `capped` bounds the NATIVE forward to the 30k settlement budget so a
    ///  recipient cannot eat a liquidation's — or an adoption's — gas.
    ///  {retirePayout} passes false, because a recipient that merely overran that
    ///  budget should be PAID at the last chance rather than written off.
    ///
    ///  The ERC20 leg has the same griefing surface by a different mechanism: a
    ///  blacklistable token (true of most tokenized equities) can make one recipient
    ///  permanently unpayable, and a non-standard token returns false rather than
    ///  reverting. Both are reported, so the credit-instead-of-revert guarantee
    ///  holds whatever the book is denominated in.
    function _tryPush(address to, uint256 amount, bool capped) private returns (bool ok) {
        if (_quoteIsNative()) {
            if (capped) { (ok, ) = to.call{value: amount, gas: 30_000}(""); }
            else { (ok, ) = to.call{value: amount}(""); }
        } else {
            ok = PerpSwapLib.tryTransfer(quote, to, amount);
        }
    }

    /// @notice Retire a settlement payout its recipient cannot accept, so one
    ///         stranded wei can never veto a quote adoption. Timelock-only.
    ///
    ///  ── THE GUARD MUST NOT DEPEND ON A THIRD PARTY (red-team X3i) ─────────
    ///  {syncGeneration} refuses to adopt a new quote while `payoutOwedTotal != 0`,
    ///  and that counter was cleared ONLY by {claimPayout}, which is
    ///  `msg.sender`-keyed with no override. So ONE WEI owed to a contract whose
    ///  `receive()` reverts pinned it non-zero FOREVER — and the rotation itself
    ///  still completed, because {RedemptionExt} wraps the sync in `try {} catch {}`
    ///  (RedemptionExt.sol:562). The engine was left stranded on the OLD quote for
    ///  the rest of the generation: exactly the F-10/F-11 state the guard exists to
    ///  prevent, reached through a different door. No attacker needed — the
    ///  dividend and treasury fee sinks reach it on their own.
    ///
    ///  The owner cannot profit by calling this: the value goes to `to` or it goes
    ///  nowhere. It CANNOT be redirected. The retry forwards ALL remaining gas, so a
    ///  recipient that only overran the 30k settlement budget is paid in full here;
    ///  and the recipient may self-claim via {claimPayout} at any time beforehand.
    ///  Only a recipient that reverts outright at full gas is written off, and its
    ///  wei then stays in the engine as residue owned by nobody — the same class as
    ///  the R-09 `plv` dust — where it can never again veto a rotation.
    ///
    ///  Deliberately NOT a drop of the counter from the guard: that counter is
    ///  load-bearing for the redenomination fix (e964d54).
    ///
    ///  ── AND PERMISSIONLESS WHILE THE ENGINE IS DIVERGED (S01 liveness) ────
    ///  This was `onlyOwner` outright, which quietly narrowed a liveness promise:
    ///  `payoutOwedTotal` is the one counter that can still REFUSE a quote
    ///  adoption, so one wei owed to a refusing sink put a diverged engine's
    ///  recovery behind a privileged key — and
    ///  {S01_PerpQuoteDeadlock.test_invariant_divergedEngineIsPermissionlesslyRecoverable}
    ///  promises that "nothing privileged should be required to put it right".
    ///  So while `quote` disagrees with the generation's quote — exactly when this
    ///  entry is what stands between the engine and recovery — ANYONE may call it.
    ///  Once the engine is back in step it is owner-only again, which is where the
    ///  griefing surface would otherwise live.
    ///  No `nonReentrant`: both effects below land BEFORE the push, so a recipient
    ///  reentering this finds `payoutOwed[to] == 0` and reverts, and the asset branch
    ///  is chosen before any external code runs — a reentrant adoption cannot change
    ///  what gets sent. Strict CEI is the guard.
    ///  ── A STRANGER MAY UNBLOCK A ROTATION, NOT BURN A CLAIM (F-02) ────────
    ///  The push's return value used to be DISCARDED, so the entry was retired
    ///  whether or not the value moved. Combined with the permissionless branch
    ///  that is a burn-someone-else's-escrow primitive: any address could pick a
    ///  recipient that happens to be TRANSIENTLY unpayable — paused for an upgrade,
    ///  blacklisted by the quote token, reverting for a block — and permanently
    ///  destroy its settlement proceeds, which {claimPayout} would have preserved.
    ///  So an unprivileged caller may only retire an entry whose value ACTUALLY
    ///  went somewhere: the liveness promise is kept for every recipient that can
    ///  be paid (which is every case the invariant was written for), and a
    ///  recipient that refuses at FULL gas is a WRITE-OFF only the owner may take.
    function retirePayout(address to) external {
        uint256 amount = payoutOwed[to];
        if (amount == 0) revert ZeroValue();
        //  THE OWNER MAY ALWAYS WRITE OFF, DIVERGED OR NOT. Making the successful
        //  push a condition for EVERY caller would hand a permanently-refusing
        //  recipient the veto back (red-team X3i: `payoutOwedTotal` is the one
        //  counter that can still refuse a quote adoption, and nothing may pin it
        //  forever). So the push result gates the UNPRIVILEGED caller only.
        bool priv = msg.sender == owner();
        if (!priv) {
            //  Converged: this is ordinary bookkeeping and belongs to the timelock.
            //  Diverged: this entry is what stands between the engine and recovery,
            //  so anyone may clear it — see the liveness note above.
            if (quote == registry.generationQuote(registry.currentGeneration())) _checkOwner();
        }
        payoutOwed[to] = 0;                     // effects before interaction
        payoutOwedTotal -= amount;
        //  ONE LAST PUSH AT FULL GAS — not the 30k settlement budget that stranded
        //  it — so a recipient that merely overran that budget is genuinely PAID
        //  here instead of written off. Only an outright revert loses the claim, and
        //  that wei then stays in the engine as residue owned by nobody, where it
        //  can never again veto a rotation.
        //  Checked (F-02): retired unconditionally for the OWNER — that is the
        //  deliberate write-off, and the wei stays as residue owned by nobody that
        //  can never again veto a rotation — but a permissionless caller reverts if
        //  nothing moved, which rolls both effects back and leaves the claim intact.
        if (!_tryPush(to, amount, false) && !priv) revert EthSend();
        //  No dedicated event (EIP-170): the owner is a timelock, which emits its
        //  own CallExecuted for this exact calldata, and `payoutOwed(to)` going to
        //  zero alongside `payoutOwedTotal` is the on-chain record. An indexer has
        //  strictly more to work with here than it would from one more log topic.
    }

    /// @notice Withdraw a settlement payout that could not be pushed to you (your
    ///         `receive()` reverted or ran out of the 30k forwarding budget).
    function claimPayout() external nonReentrant returns (uint256 amount) {
        amount = payoutOwed[msg.sender];
        if (amount == 0) revert ZeroValue();
        payoutOwed[msg.sender] = 0;                     // effects before interaction
        payoutOwedTotal -= amount;
        _pushQuote(msg.sender, amount);
    }
    /// @dev LONG bad debt: `plv` already booked the reduced repayment, so ADD the
    ///      insurance cover back into plv to make depositors whole up to the
    ///      buffer. Any uncovered remainder is already reflected as a lower plv.
    function _replenishPlv(uint256 shortfall) internal {
        uint256 cover = shortfall < insuranceEth ? shortfall : insuranceEth;
        if (cover > 0) { insuranceEth -= cover; plv += cover; }
        emit BadDebt(shortfall, cover);
    }
    /// @dev SHORT bad debt: the buy-back overspent the engine's raw ETH by `loss`,
    ///      which was NOT yet booked against plv. Absorb it — insurance first,
    ///      then LP principal (saturating so an extreme gap can't underflow/brick
    ///      the liquidation) — so plv stays consistent with the real ETH balance.
    function _absorbPlvLoss(uint256 loss) internal {
        uint256 fromIns = loss < insuranceEth ? loss : insuranceEth;
        insuranceEth -= fromIns;
        uint256 rest = loss - fromIns;
        if (rest > 0) plv = plv > rest ? plv - rest : 0; // socialized LP loss
        emit BadDebt(loss, fromIns);
    }
    /// @dev Mint the Liquidatoor badge to `to` from the ACTIVE brew's collection
    ///      (read live off the hook, so it always targets whatever iteration is
    ///      trading now). Fully best-effort: if the collection isn't wired to
    ///      accept badges from this engine, we emit with badgeId 0 and move on —
    ///      a liquidation must never revert on the trophy.
    /// @dev HYBRID badge (gas audit G-03): AUTO-MINT the trophy in-swap when there's
    ///      gas headroom (matching the creature-NFT UX — it just appears), and only
    ///      FALL BACK to a claimable credit when gas is tight or the collection
    ///      rejects it. A synchronous mint (~78k + metadata) on top of a ~450k short
    ///      settlement used to tip the whole thing over a normal swap's budget, so it
    ///      silently no-oped; the guard + bounded-gas try means the liquidation NEVER
    ///      reverts on the trophy, yet the fren usually gets it instantly. Unminted
    ///      credit is claimed later via `claimLiquidatorBadges`. Attribution is
    ///      preserved by the event either way.
    ///  CODE CHECK (audit L-06): a low-level call to an address with NO code returns
    ///  `true`. Without the `col.code.length` guard below, any window in which the
    ///  hook has no live collection wired reported a SUCCESSFUL mint — so the badge
    ///  was neither struck nor credited to `badgesOwed`, and the event told indexers
    ///  it had been. Now every failure path (OOG / unwired / rejecting collection)
    ///  falls back to the claimable credit, as the hybrid design intends.
    /// @dev Snapshot what a liquidation actually was, for the badge that
    ///      commemorates it. Prices are ETH per token in wei:
    ///        entry — what the position paid per token when it opened, i.e.
    ///                borrowed ETH over token size for a long, and proceeds over
    ///                size owed for a short (both are `principal / size`).
    ///        liq   — the TWAP mark that triggered this close, quoted for the
    ///                same size so it is directly comparable to entry.
    ///      Both are clamped into uint128; a price that large cannot occur with a
    ///      777M-supply token, but truncation would misreport rather than revert.
    function _killStats(Position memory p, uint256 bounty)
        internal
        view
        returns (LiqStats memory st)
    {
        uint256 entry = p.size == 0 ? 0 : (p.principal * 1e18) / p.size;
        uint256 mark = p.size == 0 ? 0 : (_quoteMark(p.size) * 1e18) / p.size;
        st = LiqStats({
            victim: p.trader,
            wasLong: p.isLong,
            leverage: p.leverage,
            collateralWei: p.collateral > type(uint96).max
                ? type(uint96).max
                : uint96(p.collateral),
            bountyWei: bounty > type(uint96).max ? type(uint96).max : uint96(bounty),
            blockNo: uint64(block.number),
            entryPrice: entry > type(uint128).max ? type(uint128).max : uint128(entry),
            liqPrice: mark > type(uint128).max ? type(uint128).max : uint128(mark)
        });
    }

    function _awardBadge(uint256 id, address to, LiqStats memory st) internal {
        if (to == address(0)) return;
        uint256 minted;
        //  The stats-bearing mint writes three extra storage slots (~66k), so the
        //  floor is raised to match. Leaving it at 220k would not have reverted —
        //  the mint would simply have run out of gas and fallen through to
        //  `badgesOwed`, silently turning every badge into a claimable IOU.
        //  Both encodes and both gas-metered calls live in {PerpSwapLib.tryMintBadge}
        //  for EIP-170 headroom, including the pre-stats `mintLiquidator` fallback
        //  for a collection deployed before stats existed. It is a DELEGATECALL, so
        //  the collection still sees THIS ENGINE as `msg.sender`.
        if (gasleft() > 300_000) {
            if (PerpSwapLib.tryMintBadge(IPerpHook(hookAddr).collection(), to, st)) minted = 1;
        }
        if (minted == 0) { unchecked { badgesOwed[to] += 1; } }
        emit LiquidatoorAwarded(id, to, minted);
    }

    /// @notice Claim `n` of the Liquidatoor badges you've earned into the LIVE
    ///         collection (the fallback for liquidations too gas-tight to auto-mint
    ///         in-swap). Bounded by `n` so a big backlog can't OOG; the rest stays
    ///         owed. Reverts if no collection is wired (retry later).
    function claimLiquidatorBadges(uint256 n) external nonReentrant {
        uint256 owed = badgesOwed[msg.sender];
        if (n == 0 || n > owed) n = owed; // n==0 (nothing owed) → the loop no-ops
        address col = IPerpHook(hookAddr).collection();
        // Mirror of the L-06 guard in _awardBadge: without this, a code-less
        // collection would let the loop "succeed" and BURN the owed count for
        // nothing. Revert instead so the badges stay claimable once one is wired.
        if (col.code.length == 0) revert BadParam();
        badgesOwed[msg.sender] = owed - n;
        // Attribution was already emitted at liquidation time; the badgeIds are
        // observable from the collection's own mint events, so no event here.
        for (uint256 i = 0; i < n;) { ILiquidatorMintable(col).mintLiquidator(msg.sender); unchecked { ++i; } }
    }
    function _safeTransfer(address token, address to, uint256 amount) private {
        if (!PerpSwapLib.tryTransfer(token, to, amount)) revert BadParam();
    }

    // ── vault funding + admin ──
    /// @notice Seed the ETH side (fronts long leverage). owner-ONLY + share-less:
    ///         this is a PERMANENT donation to the ETH PLV (raises share price, no
    ///         shares minted → not withdrawable). Community capital MUST go through
    ///         `PerpVault.depositEth` instead so it's share-backed & recoverable.
    ///         (Audit L-02)
    /// @notice Fund the PLV. `amount` is stated explicitly so a non-native quote
    ///         can be pulled by `transferFrom`; for a native book it must equal
    ///         `msg.value`.
    function fundPlv(uint256 amount) external payable onlyOwner notNested {
        _pullQuote(msg.sender, amount);
        plv += amount;
        emit PlvFunded(amount, 0);
    }
    /// @notice Seed the TOKEN side (lent to shorts). owner-ONLY + share-less — a
    ///         permanent donation; use `PerpVault.depositToken` for recoverable
    ///         inventory. Caller must approve the token. (Audit L-02)
    function fundPlvToken(uint256 amount) external onlyOwner notNested {
        IERC20(registry.currentToken()).transferFrom(msg.sender, address(this), amount);
        plvToken += amount; emit PlvFunded(0, amount);
    }
    /// @notice Seed insurance directly (owner or anyone topping up the buffer).
    /// @notice Fund the insurance buffer (see fundPlv on the amount argument).
    function fundInsurance(uint256 amount) external payable {
        _pullQuote(msg.sender, amount);
        insuranceEth += amount;
    }

    /// @notice HOOK-ONLY: credit a redirected perp-swap trading fee into the ETH PLV
    ///         → yield for the ETH stakers who back leverage (they bear the bad-debt
    ///         tail, so perp volume rewards them). Called by the hook DURING the
    ///         engine's own swap (mid-unlock), so NO notNested — it's pure accounting
    ///         (no pool touch, no external call), safe to nest.
    function creditPerpFee() external payable { _creditPerp(true); }
    /// @notice HOOK-ONLY: credit a redirected perp-swap SELL fee into the token-side
    ///         ETH reward pot (`tokYieldEth`) → yield for the TOKEN stakers backing
    ///         shorts. Buys reward ETH stakers, sells reward token stakers — the hook
    ///         splits by direction. Pure accounting, safe to nest mid-swap.
    function creditPerpFeeToken() external payable { _creditPerp(false); }

    /**
     * @notice Pull a non-native perp fee the hook has approved to this engine.
     * @dev PULL rather than push, because a balance cannot distinguish a fee
     *      from a stray transfer — and a stray would silently inflate the PLV,
     *      diluting every staker. The hook approves, then calls this.
     *
     *  ── ETH-SIDE ONLY, DELIBERATELY (audit B-03) ──────────────────────────
     *  The NATIVE path splits perp fees by side — buys reward the ETH stakers
     *  (`plv`), sells reward the token stakers (`tokYieldEth`) — via two
     *  selectors ({creditPerpFee}/{creditPerpFeeToken}). This ERC20 path credits
     *  `plv` for BOTH sides: a non-native generation's token stakers do not yet
     *  earn their sell-side share. That is a REDISTRIBUTION between two protocol
     *  staker classes, not a loss — the fee is fully pulled and accounted, and
     *  solvency is unaffected. Splitting it needs a second asset entrypoint the
     *  engine has no EIP-170 headroom for (single-digit bytes spare), so it is
     *  deferred with the rest of the non-native perp work rather than shipped
     *  half-fitting. Fixing it means a `creditPerpFeeAssetToken` twin (or a side
     *  flag threaded through {FeeRouteLib.routePerp}) once the byte budget exists.
     */
    function creditPerpFeeAsset(address asset, uint256 amount) external {
        if (msg.sender != hookAddr) revert OnlyHook();
        // Only the asset this book is denominated in; anything else cannot be
        // credited to a plv/tokYield figure measured in the quote.
        if (asset != quote || asset == address(0)) revert BadParam();
        _pullIntoPlv(amount);
    }

    /// @dev The body {creditPerpFeeAsset} and {fundFromVault} shared byte for byte
    ///      (EIP-170). Pull the quote in, bank it as ETH-side PLV, announce it.
    function _pullIntoPlv(uint256 amount) private {
        _pullQuote(msg.sender, amount);
        plv += amount;
        emit VaultFunded(true, amount);
    }

    function _creditPerp(bool ethSide) private {
        if (msg.sender != hookAddr) revert OnlyHook();
        //  ── NATIVE ONLY, LIKE ITS THREE SIBLINGS (red-team H-3) ───────────
        //  `fundPlv`, `fundInsurance` and `fundFromVault` all route through
        //  {_pullQuote}, which refuses `msg.value` on an ERC20 book. This one
        //  banked `msg.value` straight into `plv`/`tokYieldEth` — counters
        //  denominated in the quote — so native wei inflated an ERC20 claim the
        //  engine never received. Reachable: {CauldronHook} hands
        //  {FeeRouteLib._deliver} its `_feeAsset`, which picks the native
        //  selector at `address(0)`, and `_feeAsset` diverges from
        //  `generationQuote` mid-rotation (cauldron/RedemptionExt.sol:487).
        if (!_quoteIsNative()) revert BadParam();
        //  NATIVE path. A non-native quote delivers its perp fee through
        //  {creditPerpFeeAsset} instead (the hook's {FeeRouteLib.routePerp}
        //  approves + pulls), so a USDG/xNVDA pool CAN now fund the engine — see
        //  the B-03 note there for the one behavioural gap (asset sells credit
        //  the ETH side rather than the token side).
        uint256 amount = msg.value;
        if (ethSide) {
            plv += amount;
        } else {
            tokYieldEth += amount;
            tokYieldCumulative += amount;
        }
        emit VaultFunded(ethSide, amount);
    }


    // ── Community PLV: vault-only deposit/withdraw of working capital ────────
    /// @notice The PerpVault routes a depositor's ETH into the ETH PLV.
    /// @notice The vault routes a depositor's stake into the PLV. `amount` is
    ///         explicit so a non-native quote can be pulled; for a native book
    ///         it must equal msg.value.
    function fundFromVault(uint256 amount) external payable onlyVault {
        _pullIntoPlv(amount);
    }
    /// @notice The PerpVault pulls FREE ETH (≤ plv) back out to pay a withdrawal.
    ///         Lent-out ETH (longOiEth) can't be pulled — it returns as positions
    ///         close, which is what the vault's utilization cap + queue manage.
    function withdrawPlvTo(uint256 amount, address to) external onlyVault notNested nonReentrant {
        if (amount > plv) revert PlvInsufficient();
        plv -= amount; _vaultPaid(amount, to);
    }
    /// @dev The tail the two quote-side vault pulls share, byte for byte (EIP-170).
    ///      Kept AFTER the counter is debited so the CEI order of both callers is
    ///      exactly what it was: effects, then the single external send.
    function _vaultPaid(uint256 amount, address to) private {
        _sendEth(to, amount); emit VaultWithdrawn(true, amount, to);
    }
    /// @notice The PerpVault pulls a token staker's accrued short-side ETH reward
    ///         out of the segregated `tokYieldEth` pot (never touches `plv`).
    function withdrawTokYieldTo(uint256 amount, address to) external onlyVault notNested nonReentrant {
        if (amount > tokYieldEth) revert PlvInsufficient();
        tokYieldEth -= amount; _vaultPaid(amount, to);
    }
    /// @notice The PerpVault routes a depositor's TOKEN into the short inventory.
    function fundTokenFromVault(uint256 amount) external onlyVault {
        IERC20(registry.currentToken()).transferFrom(msg.sender, address(this), amount);
        plvToken += amount; emit VaultFunded(false, amount);
    }
    /// @notice The PerpVault pulls FREE token inventory (≤ plvToken) out to pay a
    ///         withdrawal. Lent inventory returns as shorts close.
    function withdrawPlvTokenTo(uint256 amount, address to) external onlyVault notNested nonReentrant {
        if (amount > plvToken) revert PlvInsufficient();
        plvToken -= amount;
        _safeTransfer(registry.currentToken(), to, amount);
        emit VaultWithdrawn(false, amount, to);
    }

    function setFees(uint256 _openBps, uint256 _ogDiscBps, uint256 _liqBps, uint256 _divShareBps, uint256 _keeperBps) external onlyOwner {
        if (!(_openBps <= 2000 && _ogDiscBps <= BPS && _liqBps <= 2000 && _divShareBps <= BPS && _keeperBps <= BPS)) revert BadParam();
        openFeeBps = _openBps; ogDiscountBps = _ogDiscBps; liqPenaltyBps = _liqBps; divShareBps = _divShareBps; keeperBps = _keeperBps;
    }
    function setRisk(uint256 _warmup, uint256 _ceiling, uint256 _maintBps, uint256 _maxNotBps, uint256 _maxOiBps, uint256 _fundingBpsDay) external onlyOwner {
        // warmup >= MIN_TWAP so no position can open before the TWAP oracle has
        // enough history to give a manipulation-resistant mark — otherwise
        // markSqrtPriceX96() would fall back to SPOT and liquidations during the
        // cold-start window would be flash-manipulable. (Audit L-03)
        if (_warmup < MIN_TWAP) revert BadParam();
        // `_fundingBpsDay` was the ONE unbounded parameter on this setter (audit
        // F-04). `_pokeFunding` computes
        //   step = imbalance * rate * dt * 1e18 / (total * BPS * 1 days)
        // in SIGNED 256-bit arithmetic, so an out-of-range rate is not merely an
        // aggressive economic setting:
        //   * `int256(_fundingBpsDay)` above 2^255 wraps NEGATIVE, silently
        //     INVERTING the funding direction (the crowded side gets paid), and
        //   * a merely-large rate overflows the checked multiplication, so
        //     `_pokeFunding` REVERTS — and it is called by open, close, liquidate,
        //     `forceCloseAllDead` and `poke`. A reverting `forceCloseAllDead`
        //     leaves `openCount != 0` forever, which makes `syncGeneration` revert
        //     `PositionsOpen` forever, stranding the entire token inventory in a
        //     dead generation. One bad governance call bricks the engine.
        // Bound it like every sibling: 100% of notional per day is already far
        // beyond any sane funding rate.
        if (!(_ceiling >= 1 && _ceiling <= 10 && _maintBps <= 5000 && _maxNotBps <= BPS
            && _maxOiBps <= BPS && _fundingBpsDay <= BPS)) revert BadParam();
        warmup = _warmup; maxLeverageCeiling = _ceiling; maintenanceBps = _maintBps;
        maxNotionalBps = _maxNotBps; maxOiBps = _maxOiBps; fundingRateBpsPerDay = _fundingBpsDay;
    }

    /// @notice Tune the liquidation-mark TWAP averaging window (owner/timelock).
    ///         Floor = MIN_TWAP (1s): shorter = the mark hugs spot closer (liqs
    ///         match the chart sooner + fewer born-underwater opens) but is easier
    ///         to flash-manipulate; longer = more manipulation-resistant but laggier.
    ///         On a sub-second-block L2 even 1s spans many blocks, so it's a usable
    ///         floor — tune live via the timelock to whatever the pool can defend.
    //  `setTwapWindow` was removed to pay for the mark source. {setGuards} below
    //  already sets `twapWindow` under a strictly stronger validation (the same
    //  MIN_TWAP floor plus a 2-hour ceiling), so nothing became unreachable —
    //  pass the current `maxLiqBps` / `maxFundingBps` alongside the new window.
    function setTiers(uint256[] calldata depths, uint8[] calldata levs) external onlyOwner {
        uint256 n = levs.length;
        if (n != depths.length + 1 || n > 32) revert BadParam();
        tierDepthWei = depths;
        uint256 p;
        for (uint256 i = 0; i < n;) { p |= uint256(levs[i]) << (i << 3); unchecked { ++i; } }
        tierLevPacked = p;
    }
    /// @notice The engine's outbound addresses, set together.
    ///
    ///  `_nftBeneficiary` is where perp-volume gacha creatures accrue (keep it
    ///  NON-tax-exempt). `_markSource` is the liquidity-weighted mark — see
    ///  {_currentTick} and {PerpMarkSource}; zero leaves the mark reading the
    ///  primary pool's tick, which is the pre-existing behaviour.
    ///
    ///  ONE SETTER RATHER THAN THREE. This contract has single-digit bytes of
    ///  EIP-170 headroom, and each additional external function costs a dispatch
    ///  entry plus a prologue for a cold path nobody calls in a normal month.
    ///  Folding them together is what paid for the mark source.
    ///  `_quoteOracle` is the {QuoteOracle} {_q} prices its wei-written thresholds
    ///  through (red-team F-03). Zero leaves them unit-scaled, which is the
    ///  pre-oracle behaviour; it is read defensively and only ever at an adoption.
    function setRouting(
        address _dividend,
        address _treasury,
        address _nftBeneficiary,
        address _markSource,
        address _quoteOracle
    )
        external
        onlyOwner
    {
        dividend = _dividend;
        treasury = _treasury;
        nftBeneficiary = _nftBeneficiary;
        markSource = _markSource;
        quoteOracle = _quoteOracle;
    }

    /// @notice Fee split: `_yieldBps` of routed fees → LP yield, `_insBps` →
    ///         insurance. Their sum must leave room for div/treasury (≤ BPS).
    function setVaultSplit(uint256 _yieldBps, uint256 _insBps) external onlyOwner {
        if (_yieldBps + _insBps > BPS) revert BadParam();
        vaultYieldBps = _yieldBps; insuranceBps = _insBps;
    }
    /// @notice Phase-3 hardening params: TWAP window, per-block liq cap, funding cap.
    function setGuards(uint32 _twapWindow, uint256 _maxLiqBps, uint256 _maxFundingBps) external onlyOwner {
        if (!(_twapWindow >= MIN_TWAP && _twapWindow <= 2 hours && _maxLiqBps <= BPS && _maxFundingBps <= BPS)) revert BadParam();
        twapWindow = _twapWindow; maxLiqBps = _maxLiqBps; maxFundingBps = _maxFundingBps;
    }

    // ── Community PLV config ────────────────────────────────────────────────
    /// @notice Wire (or clear) the PerpVault that supplies depositor liquidity.
    ///         DRAIN GUARD (Audit H-01): once a vault is wired, it can only be
    ///         re-pointed while the PLV is EMPTY (plv/plvToken/tokYieldEth all 0).
    ///         So even the owner (a timelock+multisig on mainnet) cannot swap the
    ///         vault out from under staked funds and drain them via the onlyVault
    ///         withdraw path — depositor principal must first exit the legit way.
    ///  ── ASK WHO IS OWED, NOT WHAT IS HELD (red-team R-09) ─────────────────
    ///  This tested `plv != 0 || plvToken != 0 || tokYieldEth != 0`. Both of the
    ///  residues that outlive the last depositor are unownable — orphaned
    ///  short-side yield (credited at zero token shares, attributable to nobody
    ///  and therefore never payable out) and one wei of `plv` left by ordinary
    ///  floor-rounding — so the guard latched permanently on state that belongs
    ///  to no one, and the ONLY lever for replacing a broken vault on a live
    ///  engine was gone. Measured: one wei was enough.
    ///  {PerpVault.hasStakers} answers the question the guard was always asking.
    ///
    ///  ── AND IT STAYS `hasStakers`, NOT `hasQuoteStake` (red-team F-01) ────
    ///  {syncGeneration} was moved to the quote-side-only question because a quote
    ///  rotation does not redenominate the token side, so the token side has
    ///  nothing to be protected from there. THIS guard is the opposite case: a new
    ///  vault gets the `onlyVault` withdraw path over `plvToken`, which IS token-side
    ///  principal, so re-pointing the vault while token stakers hold shares hands
    ///  their principal to whatever contract the owner names — the H-01 drain this
    ///  guard exists for. A genuine token staker is owed money and may veto here.
    ///  The cost is that a dust token deposit can also block replacing a BUGGY
    ///  vault; the engine itself keeps running either way, so that is a griefing
    ///  nuisance and not the permanent freeze F-01 reported, and it is strictly
    ///  preferable to making staked principal re-pointable.
    function setVault(address _vault) external onlyOwner {
        if (vault != address(0) && IPerpVaultStake(vault).hasStakers()) revert BadParam();
        vault = _vault;
    }
    /// @notice Utilization cap (max % of vault lent to traders) + insurance
    ///         circuit-breaker floor (pause opens while insurance < floor).
    function setVaultLimits(uint256 _maxUtilBps, uint256 _insuranceFloor) external onlyOwner {
        if (_maxUtilBps > BPS) revert BadParam();
        maxUtilBps = _maxUtilBps; insuranceFloor = _insuranceFloor;
    }
    /// @notice Dust filter: minimum ETH collateral to open a position (anti-spam).
    function setMinCollateral(uint256 _minCollateral) external onlyOwner {
        if (_minCollateral > 1 ether) revert BadParam(); // sane ceiling
        minCollateral = _minCollateral;
    }
    /// @notice Skim the insurance buffer to the treasury — but ONLY the surplus
    ///         above `insuranceFloor` (the protected minimum), and NEVER depositor
    ///         principal (plv/plvToken are untouched by this). So the owner can
    ///         recover excess buffer without ever pulling the protection that's
    ///         actively backing open positions.
    ///  RISK-BASED FLOOR (audit M-05): `insuranceFloor` defaults to 0 and is never
    ///  set by the deploy script, so the configured guard alone protected NOTHING —
    ///  the owner could withdraw the whole buffer that is actively backing open
    ///  positions, after which the next short shortfall socialises straight onto LP
    ///  principal via `_absorbPlvLoss`. We therefore protect the GREATER of the
    ///  configured floor and a minimum scaled to live open interest, so the buffer
    ///  can never be emptied while positions depend on it.
    function skimInsurance(uint256 amount, address to) external onlyOwner {
        if (to == address(0)) revert BadParam();
        uint256 riskMin = ((longOiEth + _quoteEth(shortOiToken)) * maintenanceBps) / BPS;
        uint256 floorQ = _q(insuranceFloor);
        uint256 protect = floorQ > riskMin ? floorQ : riskMin;
        if (insuranceEth < protect + amount) revert BadParam();
        insuranceEth -= amount;
        _sendEth(to, amount);
    }

    // ── frontend views ────────────────────────────────────────────────────
    /// @notice Snapshot for the trading UI: OI (both sides, in ETH), vault
    ///         balances, the current mark, and whether opens are live.
    // NOTE: the bundled `stats()` view was removed to reclaim EIP-170 headroom for
    // the hybrid badge. The API/frontend already read the individual getters
    // (longOiEth, plv, plvToken, activeEthDepth, maxLeverage, markSqrtPriceX96,
    // fundingIndex, isDead) directly — stats() was only a one-call convenience.
    /// @notice Live health of a position for the UI: mark value, debt/backing,
    ///         and whether it's currently liquidatable.
    function positionHealth(uint256 id) external view returns (
        bool isLong, uint256 markValueEth, uint256 debtOrBackingEth, bool liquidatable
    ) {
        Position memory p = positions[id];
        if (p.trader == address(0)) return (false, 0, 0, false);
        isLong = p.isLong;
        markValueEth = _quoteMark(p.size);
        debtOrBackingEth = p.isLong ? p.principal : (uint256(p.collateral) + p.principal);
        liquidatable = _underwater(p);
    }

    receive() external payable {}
}
