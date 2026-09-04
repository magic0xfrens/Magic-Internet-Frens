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
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ILiquidatorMintable, LiqStats} from "./ILiquidatorMintable.sol";
import {PerpSwapLib} from "./PerpSwapLib.sol";

interface IPerpRegistry {
    function currentToken() external view returns (address);
    function currentGeneration() external view returns (uint256);
    function lastSummonAt() external view returns (uint256);
    function generationPoolId(uint256) external view returns (PoolId);
    function generationToken(uint256) external view returns (address);
    function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256);
    function claimByBurnUpTo(uint256 fromGen, uint256 maxAmount) external returns (uint256);
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
    address public nftBeneficiary;
    uint256 public openFeeBps = 690;
    uint256 public ogDiscountBps = 5_000;
    uint256 public liqPenaltyBps = 690;
    uint256 public divShareBps = 6_000;
    // Liquidator's cut of the penalty. 145 bps × the 6.9% penalty ≈ 0.1% of the
    // liquidated collateral — a tiny ETH tip; the Liquidatoor BADGE is the real
    // prize. (Also sizes the death-clearing keeper reward, but death-clearing is
    // now largely automatic via the relaunch auto-migrate.) Owner/timelock-tunable.
    uint256 public keeperBps = 145; // ≈ 0.1% of collateral to the liquidator
    uint256 public warmup = 24 hours;
    uint256 public maxLeverageCeiling = 3;
    uint256 public maintenanceBps = 1_500;
    uint256 public maxNotionalBps = 500;      // per-position notional ≤ 5% of depth
    uint256 public maxOiBps = 3_000;          // per-side OI ≤ 30% of depth
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
    uint256 public insuranceEth;
    /// @notice Of every ROUTED fee (open fee + liq penalty): this share stays in
    ///         the PLV as LP yield (raises share price), and `insuranceBps` funds
    ///         the buffer. The remainder splits dividend/treasury as before.
    uint256 public vaultYieldBps = 3_000;     // 30% of routed fees → LP yield
    uint256 public insuranceBps = 1_000;      // 10% of routed fees → insurance
    /// @notice Max share of vault assets lent to traders (per side). The rest is
    ///         always instantly withdrawable — the LP liquidity buffer. (80%)
    uint256 public maxUtilBps = 8_000;
    /// @notice Bad-debt circuit breaker: once insurance is depleted below this
    ///         (in wei), new opens are paused until it refills from fees. 0 = off.
    uint256 public insuranceFloor;
    /// @notice Funding: annualized-ish rate applied to the net-imbalance fraction,
    ///         charged to the crowded side per second, accruing to the PLV.
    uint256 public fundingRateBpsPerDay = 100; // 1%/day at 100% imbalance

    // ── Phase-3 hardening knobs (owner-tunable) ──
    uint32 public twapWindow = 5 minutes;     // liquidation-mark averaging window
                                              // (5m resists flash-manip; 30m lags too much)
    uint256 public maxLiqBps = 2_000;         // ETH-notional liquidated ≤ 20% of depth / block
    uint256 public maxFundingBps = 5_000;     // |funding P&L| ≤ 50% of collateral (anti-drain cap)

    uint256[] public tierDepthWei;
    uint8[]  public tierLeverage;

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
    Observation[OBS_CARDINALITY] public observations;
    uint16 public obsIndex;          // next slot to write
    int56 public tickCumulative;     // Σ tick·dt up to lastObsTs
    uint32 public lastObsTs;         // last time tickCumulative was INTEGRATED
    int24 public lastTick;
    /// @dev Last time a RING ENTRY was appended. Kept separate from `lastObsTs`
    ///      (audit A-02) so the integration clock can advance on EVERY observation
    ///      while ring appends stay throttled to OBS_INTERVAL — the two used to
    ///      share one clock, which is what let a stale tick poison the mark.
    ///      Packs into the same slot as the four fields above (16+56+32+24+32 bits).
    uint32 public lastRingTs;

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
    int256 public fundingIndex;
    uint64 public lastFundingAt;

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

    // ── Enumerable open set — lets ANY swap (any interface) scan + liquidate
    //    underwater positions without a hint. O(1) add/remove (swap-and-pop).
    uint256[] internal _openIds;                    // live position ids
    mapping(uint256 => uint256) internal _openPos;  // id → 1-based index in _openIds
    uint256 public sweepCursor;                     // rotating scan start
    uint256 internal constant SWEEP_SCAN = 12;      // positions checked per swap
    uint256 public longOiEth;    // Σ ETH borrowed by open longs
    uint256 public shortOiToken; // Σ token owed by open shorts

    // ── per-iteration sync: one engine serves every generation ──
    uint256 public syncedGeneration; // the gen this engine's token-side is armed for
    address public syncedToken;      // that gen's token (what plvToken is denominated in)

    /// @dev This engine denominates collateral, principal, funding, payouts and
    ///      the insurance buffer in NATIVE ETH — `openLong`/`openShort` are
    ///      payable and every payout is a `call{value:}`. A generation quoted in
    ///      an ERC20 cannot be served correctly until that is converted, and
    ///      serving it anyway would mis-denominate real user funds: collateral
    ///      posted in ETH against a book priced in USDG.
    ///
    ///      Refused explicitly rather than left to misbehave, so the frontend can
    ///      say "perps are ETH-only for this brew" instead of failing opaquely.
    error QuoteNotSupported();
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
        tierLeverage = [uint8(2), 3, 4, 5];
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
    function _key() internal view returns (PoolKey memory) {
        return PoolKey({currency0: Currency.wrap(address(0)), currency1: Currency.wrap(registry.currentToken()),
            fee: POOL_FEE, tickSpacing: TICK_SPACING, hooks: IHooks(hookAddr)});
    }
    function _sqrtP() internal view returns (uint160 s) { (s,,,) = poolManager.getSlot0(_key().toId()); }
    function _currentTick() internal view returns (int24 t) { (, t,,) = poolManager.getSlot0(_key().toId()); }

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
        return ok ? TickMath.getSqrtPriceAtTick(t) : _sqrtP();
    }

    function activeEthDepth() public view returns (uint256) {
        PoolId id = _key().toId();
        uint160 sp = _sqrtP();
        if (sp == 0) return 0;
        uint128 L = poolManager.getLiquidity(id);
        if (L == 0) return 0;
        uint256 term = FullMath.mulDiv(uint256(L), uint256(SQRT_MAX) - sp, uint256(SQRT_MAX));
        return FullMath.mulDiv(term, Q96, sp);
    }

    function maxLeverage() public view returns (uint8 lev) {
        uint256 depth = activeEthDepth();
        lev = tierLeverage.length > 0 ? tierLeverage[0] : 2;
        uint256 tiers = tierDepthWei.length;
        for (uint256 i = 0; i < tiers;) {
            if (depth >= tierDepthWei[i]) lev = tierLeverage[i + 1];
            unchecked { ++i; }
        }
        if (lev > maxLeverageCeiling) lev = uint8(maxLeverageCeiling);
    }

    /// @dev token→ETH value at sqrtPrice sp. Pool price p = (sp/Q96)² = token/ETH,
    ///      so ETH value = size/p = size·(Q96/sp)².
    function _quoteAt(uint256 size, uint256 sp) internal pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(size, Q96, sp), Q96, sp);
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
    function openLong(uint8 leverage, uint256 minTokenOut, uint256 liqHint) public payable nonReentrant notNested returns (uint256 id) {
        if (msg.value == 0) revert ZeroValue();
        _guardOpen(leverage);
        _pokeFunding();

        uint256 collateral = _takeFee(msg.value, true);
        if (collateral < minCollateral) revert DustPosition(); // dust filter
        uint256 borrow = collateral * (leverage - 1);
        if (borrow > plv) revert PlvInsufficient();
        // Community PLV: cap utilization so a share of depositor liquidity stays
        // instantly withdrawable, and pause opens if the insurance buffer is
        // depleted below the circuit-breaker floor (bad-debt protection).
        if (vault != address(0)) {
            if (longOiEth + borrow > (totalEth() * maxUtilBps) / BPS) revert UtilCapped();
            if (insuranceFloor > 0 && insuranceEth < insuranceFloor) revert InsurancePaused();
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
    function openShort(uint8 leverage, uint256 minEthOut, uint256 liqHint) public payable nonReentrant notNested returns (uint256 id) {
        if (msg.value == 0) revert ZeroValue();
        _guardOpen(leverage);
        _pokeFunding();

        uint256 collateral = _takeFee(msg.value, false);
        if (collateral < minCollateral) revert DustPosition(); // dust filter
        // Notional (in ETH) = collateral × leverage; borrow that much TOKEN value.
        uint256 notionalEth = collateral * leverage;
        _checkNotional(notionalEth);
        uint256 tokenToSell = _ethToToken(notionalEth); // ETH notional → token at spot
        if (tokenToSell > plvToken) revert PlvInsufficient();
        // Community PLV: token-side utilization cap + insurance circuit breaker.
        if (vault != address(0)) {
            if (shortOiToken + tokenToSell > (totalTokenAssets() * maxUtilBps) / BPS) revert UtilCapped();
            if (insuranceFloor > 0 && insuranceEth < insuranceFloor) revert InsurancePaused();
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
        uint256 notional = _quoteMark(p.size);
        if (!_underwaterVal(p, notional)) revert Healthy();
        // Per-block throttle: bound the ETH-notional liquidated per block so an
        // attacker can't engineer an unbounded atomic cascade.
        if (block.timestamp != liqBlock) { liqBlock = block.timestamp; liqEthThisBlock = 0; }
        uint256 cap = (activeEthDepth() * maxLiqBps) / BPS;
        if (cap > 0 && liqEthThisBlock + notional > cap) revert LiqCapped();
        liqEthThisBlock += notional;
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

    /// @dev Liquidate one hinted position if it's genuinely underwater at the
    ///      mark + within the per-block cap; otherwise a silent no-op. Assumes
    ///      the caller has set `_inLocked`/`_liqReentry` and poked funding.
    function _tryLiquidate(uint256 id, address liquidator) internal {
        Position memory p = positions[id];
        if (p.trader == address(0)) return;      // stale/closed hint
        // Compute the TWAP mark ONCE (a 32-slot loop) and reuse its value for BOTH
        // the underwater test AND the per-block-cap notional. (Gas audit G-02.)
        uint256 notional = _quoteMark(p.size);
        if (!_underwaterVal(p, notional)) return;   // healthy at the mark → skip
        // Same per-block throttle as liquidate(): bound the ETH-notional
        // liquidated per block so a swap can't engineer an unbounded cascade.
        if (block.timestamp != liqBlock) { liqBlock = block.timestamp; liqEthThisBlock = 0; }
        uint256 cap = (activeEthDepth() * maxLiqBps) / BPS;
        if (cap > 0 && liqEthThisBlock + notional > cap) return; // capped → skip
        liqEthThisBlock += notional;
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
        if (gen == syncedGeneration) revert AlreadySynced();
        if (openCount != 0) revert PositionsOpen(); // force-close everything first

        uint256 fromGen = syncedGeneration;
        uint256 migratedIn;
        // Migrate the engine's leftover (now-dead) inventory into the new token,
        // 1:1. Best-effort: if migration isn't available the sync still proceeds
        // (owner can re-seed via fundPlvToken), nothing bricks.
        if (fromGen != 0 && fromGen < gen && syncedToken != address(0)) {
            uint256 oldBal = IERC20(syncedToken).balanceOf(address(this));
            if (oldBal > 0) {
                // CAPACITY-AWARE (audit H-03): migrate as much as the reserve can
                // actually deliver, exactly 1:1. The strict `claimByBurn` would
                // revert on a thin reserve and strand the engine on a dead token;
                // the pre-fix version silently burned the whole book for dust.
                try registry.claimByBurnUpTo(fromGen, oldBal) returns (uint256 got) { migratedIn = got; }
                catch { /* migration unavailable → keep old, owner can re-seed */ }
            }
        }

        // Re-arm the token side to whatever the engine now actually holds of the
        // current token, and clear the stale per-token OI (already 0 via settles).
        address newTok = registry.currentToken();
        uint256 newInv = newTok != address(0) ? IERC20(newTok).balanceOf(address(this)) : 0;
        plvToken = newInv;
        shortOiToken = 0;
        longOiEth = 0;

        // Reset the TWAP oracle — old-pool ticks are meaningless for the new token.
        delete observations;
        tickCumulative = 0;
        obsIndex = 1;
        lastObsTs = uint32(block.timestamp);
        lastRingTs = uint32(block.timestamp);
        lastTick = _currentTick();
        observations[0] = Observation(uint32(block.timestamp), 0);

        //  ETH-QUOTED GENERATIONS ONLY, for now. Checked HERE — at the single
        //  point the engine adopts a generation — rather than on every open, so
        //  an unsupported brew can never become live to trade against at all.
        //  The swap direction above is already quote-agnostic; the value legs
        //  (payable opens, call{value:} payouts, plvEth, insuranceEth) are not.
        if (Currency.unwrap(_key().currency0) != address(0)) revert QuoteNotSupported();

        syncedGeneration = gen;
        syncedToken = newTok;
        emit GenerationSynced(fromGen, gen, migratedIn, newInv);
    }

    /// @notice Whether a position is liquidatable at the current TWAP mark.
    function isLiquidatable(uint256 id) external view returns (bool) {
        Position memory p = positions[id];
        if (p.trader == address(0)) return false;
        return _underwater(p);
    }

    /// @dev Underwater test at the TWAP MARK (a one-block flash-move can't trip it).
    function _underwater(Position memory p) internal view returns (bool) {
        return _underwaterVal(p, _quoteMark(p.size));
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
        if (block.timestamp < registry.lastSummonAt() + warmup) revert NotWarm();
        if (_isDead()) revert TokenDead(); // no leverage into a death
        if (leverage < 1 || leverage > maxLeverage()) revert BadLeverage();
    }
    function _isDead() internal view returns (bool) {
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
        uint256 sp = _sqrtP();
        return FullMath.mulDiv(FullMath.mulDiv(eth, sp, Q96), sp, Q96);
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
    function _sendEth(address to, uint256 amount) internal {
        (bool ok, ) = to.call{value: amount}(""); if (!ok) revert EthSend();
    }

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
        (bool ok, ) = to.call{value: amount, gas: 30_000}("");
        if (!ok) { unchecked { payoutOwed[to] += amount; } emit PayoutOwed(to, amount); }
    }

    /// @notice Withdraw a settlement payout that could not be pushed to you (your
    ///         `receive()` reverted or ran out of the 30k forwarding budget).
    function claimPayout() external nonReentrant returns (uint256 amount) {
        amount = payoutOwed[msg.sender];
        if (amount == 0) revert ZeroValue();
        payoutOwed[msg.sender] = 0;                     // effects before interaction
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert EthSend();
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
        if (gasleft() > 300_000) {
            address col = IPerpHook(hookAddr).collection();
            if (col.code.length != 0) {
                uint256 fwd;
                unchecked { fwd = gasleft() - 120_000; } // safe: guarded > 300k
                (bool ok, ) = col.call{gas: fwd}(
                    abi.encodeWithSelector(
                        ILiquidatorMintable.mintLiquidatorWithStats.selector, to, st
                    )
                );
                if (ok) minted = 1;
                //  A collection deployed before stats existed has no such
                //  function, so the call reverts on an unknown selector. Fall
                //  back to the original mint rather than dropping the badge.
                if (!ok && gasleft() > 200_000) {
                    unchecked { fwd = gasleft() - 120_000; }
                    (ok, ) = col.call{gas: fwd}(
                        abi.encodeWithSelector(ILiquidatorMintable.mintLiquidator.selector, to)
                    );
                    if (ok) minted = 1;
                }
            }
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
    function _settleCur(Currency c, uint256 amount, bool isNative) private {
        if (isNative) { poolManager.settle{value: amount}(); }
        else { poolManager.sync(c); _safeTransfer(Currency.unwrap(c), address(poolManager), amount); poolManager.settle(); }
    }
    function _take(Currency c, address to, uint256 amount) private { if (amount > 0) poolManager.take(c, to, amount); }
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        if (!(ok && (data.length == 0 || abi.decode(data, (bool))))) revert BadParam();
    }

    // ── vault funding + admin ──
    /// @notice Seed the ETH side (fronts long leverage). owner-ONLY + share-less:
    ///         this is a PERMANENT donation to the ETH PLV (raises share price, no
    ///         shares minted → not withdrawable). Community capital MUST go through
    ///         `PerpVault.depositEth` instead so it's share-backed & recoverable.
    ///         (Audit L-02)
    function fundPlv() external payable onlyOwner notNested { plv += msg.value; emit PlvFunded(msg.value, 0); }
    /// @notice Seed the TOKEN side (lent to shorts). owner-ONLY + share-less — a
    ///         permanent donation; use `PerpVault.depositToken` for recoverable
    ///         inventory. Caller must approve the token. (Audit L-02)
    function fundPlvToken(uint256 amount) external onlyOwner notNested {
        IERC20(registry.currentToken()).transferFrom(msg.sender, address(this), amount);
        plvToken += amount; emit PlvFunded(0, amount);
    }
    /// @notice Seed insurance directly (owner or anyone topping up the buffer).
    function fundInsurance() external payable { insuranceEth += msg.value; }

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

    function _creditPerp(bool ethSide) private {
        if (msg.sender != hookAddr) revert OnlyHook();
        if (ethSide) {
            plv += msg.value;
        } else {
            tokYieldEth += msg.value;
            tokYieldCumulative += msg.value;
        }
        emit VaultFunded(ethSide, msg.value);
    }

    // ── Community PLV: vault-only deposit/withdraw of working capital ────────
    /// @notice The PerpVault routes a depositor's ETH into the ETH PLV.
    function fundFromVault() external payable onlyVault { plv += msg.value; emit VaultFunded(true, msg.value); }
    /// @notice The PerpVault pulls FREE ETH (≤ plv) back out to pay a withdrawal.
    ///         Lent-out ETH (longOiEth) can't be pulled — it returns as positions
    ///         close, which is what the vault's utilization cap + queue manage.
    function withdrawPlvTo(uint256 amount, address to) external onlyVault notNested nonReentrant {
        if (amount > plv) revert PlvInsufficient();
        plv -= amount; _sendEth(to, amount); emit VaultWithdrawn(true, amount, to);
    }
    /// @notice The PerpVault pulls a token staker's accrued short-side ETH reward
    ///         out of the segregated `tokYieldEth` pot (never touches `plv`).
    function withdrawTokYieldTo(uint256 amount, address to) external onlyVault notNested nonReentrant {
        if (amount > tokYieldEth) revert PlvInsufficient();
        tokYieldEth -= amount; _sendEth(to, amount); emit VaultWithdrawn(true, amount, to);
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
    function setTwapWindow(uint32 _window) external onlyOwner {
        if (_window < MIN_TWAP) revert BadParam();
        twapWindow = _window;
    }
    function setTiers(uint256[] calldata depths, uint8[] calldata levs) external onlyOwner {
        if (levs.length != depths.length + 1) revert BadParam(); tierDepthWei = depths; tierLeverage = levs;
    }
    function setRouting(address _dividend, address _treasury) external onlyOwner { dividend = _dividend; treasury = _treasury; }
    /// @notice Where perp-volume gacha creatures accrue (keep NON-tax-exempt).
    function setNftBeneficiary(address _who) external onlyOwner { nftBeneficiary = _who; }
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
    function setVault(address _vault) external onlyOwner {
        if (vault != address(0) && (plv != 0 || plvToken != 0 || tokYieldEth != 0)) revert BadParam();
        vault = _vault;
    }
    /// @notice Fee split: `_yieldBps` of routed fees → LP yield, `_insBps` →
    ///         insurance. Their sum must leave room for div/treasury (≤ BPS).
    function setVaultSplit(uint256 _yieldBps, uint256 _insBps) external onlyOwner {
        if (_yieldBps + _insBps > BPS) revert BadParam();
        vaultYieldBps = _yieldBps; insuranceBps = _insBps;
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
        uint256 protect = insuranceFloor > riskMin ? insuranceFloor : riskMin;
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
