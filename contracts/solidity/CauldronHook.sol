// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// BaseHook was removed from v4-periphery (#510 "move to hook repo"); vendored
// locally against the installed v4-core so the Cauldron stays self-contained.
import {BaseHook} from "./vendor/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {INFTContract} from "./interfaces/INFTContract.sol";
import {ICauldronCollection} from "./cauldron/ICauldron.sol";
import {IDeathChecker} from "./cauldron/IDeathChecker.sol";
import {ISurtaxPolicy, IOddsPolicy, ICurvePolicy, IFeeRouter} from "./cauldron/IPolicies.sol";
import {LegacyBuyLib} from "./cauldron/LegacyBuyLib.sol";

/// @notice The hook-native perp engine — auto-liquidated from afterSwap.
/// @notice The registry's treasury-curated quote allowlist. The hook reads it to
///         work out which side of a pool is the quote.
interface IRegistryQuotes {
    function allowedQuote(address quote) external view returns (bool);
}

interface IPerpEngineLiq {
    function liquidateInSwap(uint256 id, address liquidator) external;
    function liquidateManyInSwap(uint256[] calldata ids, address liquidator) external;
    function sweepLiquidations(address liquidator) external;
}

/// @notice A collection whose Liquidatoor badge minter the hook can auto-wire.
interface ICollectionLiquidator {
    function setLiquidatorMinter(address minter) external;
}

/// @notice The registry entry that records a legacy buyback against the live
///         collection's pending entitlement (accounting only, no token move).
interface ILegacyNote {
    function noteLegacyBuy(uint256 tokensBought) external;
}

/// @notice The perp engine's relaunch force-close (oldest-first, all dead positions).
interface IPerpForceClose {
    function forceCloseAllDead() external;
}

/// @notice The perp engine entries that credit a redirected perp-swap fee to the
///         staker pots — buys → ETH side (PLV), sells → token side (tokYieldEth).
interface IPerpFeeCredit {
    function creditPerpFee() external payable;
    function creditPerpFeeToken() external payable;
}

/// @notice The progressive seeder's IN-SWAP nudge. `pokeInSwap` adds the streamed
///         band via CORE modifyLiquidity while we already hold the unlock (see
///         CauldronSeeder). Best-effort from afterSwap; result ignored.
interface ISeederInSwap {
    function pokeInSwap() external;
}

/**
 * @title CauldronHook
 * @notice Uniswap V4 hook — the beating heart of the Cauldron protocol.
 *
 *  THREE JOBS, ZERO EXTERNAL DEPENDENCIES:
 *
 *  1. VOLUME TRACKING -- On-chain sliding-window 24h volume (24 hourly buckets).
 *     Fully computed inside afterSwap(). No oracles. No keepers.
 *     When volume < deathThreshold the pool is "dead" and rebirth is unlocked.
 *
 *  2. SWAP FEE COLLECTION -- V4 flash accounting breaks fee-on-transfer tokens,
 *     so the hook collects tiered fees via afterSwap return deltas.
 *     Fees accumulate in this contract as native ETH + ERC20s.
 *
 *  3. SELF-FUNDING RELAUNCH -- Accumulated ETH fees ARE the next generation's
 *     liquidity. The registry calls releaseRelaunchETH() to pull ETH for the
 *     new pool. No external funding required (after genesis).
 *
 *  Tax tiers (from NFT contract):
 *    Wizard -> 0 BPS | King/Gnome -> 50 BPS | Knight/Apprentice -> 100 BPS
 *    Peasant -> 200 BPS | Non-holder -> 300 BPS (3%)
 *
 *  Hook permissions: afterInitialize, afterSwap, afterSwapReturnDelta
 */
contract CauldronHook is BaseHook, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------
    error ZeroAddress();
    error OnlyRegistry();
    error NoETHToRelease();
    error NotOpener();
    error RegistryAlreadySet();
    error OnlySelf();
    /// @dev The one swap quadrant the hook cannot charge an ETH fee on (audit Z-01).
    error ExactOutSellUnsupported();

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_TAX_BPS = 1_000;       // hard ceiling: 10%
    // Gas the hook keeps for itself (fee + return + PoolManager reentrancy unlock)
    // before forwarding the rest to the in-swap auto-liquidation. Ensures the
    // parent swap can always finish even if the liq path runs out of gas.
    uint256 internal constant LIQ_GAS_RESERVE = 180_000;
    uint256 internal constant LIQ_GAS_MIN = 250_000;   // don't bother firing under this
    // Native in-swap gacha (direct Uniswap/aggregator buys forge crystals with no
    // router). Fired LAST in afterSwap with leftover gas, isolated in a self-call.
    uint256 internal constant GACHA_GAS_RESERVE = 200_000; // keep for fee collection + return
    uint256 internal constant GACHA_GAS_MIN = 500_000;     // need room for commit+resolve+mint
    uint256 internal constant NATIVE_COMMIT_MAX = 4;       // crystals committed per native swap
    uint256 internal constant NATIVE_RESOLVE_MAX = 6;      // matured crystals resolved per native swap
    // ── VOLUME WINDOW CLOCK (audit Z-05 — High, L2) ─────────────────────────────
    // The sliding volume window used to be counted in BLOCKS: `BLOCKS_PER_HOUR = 300`
    // and `BLOCKS_PER_DAY = 7200`, both hard-coded to Ethereum's ~12s cadence. On
    // Arbitrum Nitro — and therefore on every Orbit chain, including the intended
    // deployment target — `block.number` does NOT count L2 blocks; it reports the
    // PARENT chain's block number. The wall-clock meaning of those constants was thus
    // a property of the settlement layer rather than of the protocol:
    //     parent = Ethereum L1  (~12s)  : 7200 blocks = 24 h   (as designed)
    //     parent = Arbitrum One (~0.25s): 7200 blocks = 30 min (48x too fast)
    // On the latter a healthy, liquid token read DEAD after thirty minutes of quiet
    // and ANY passer-by could permanently retire it via the permissionless
    // `relaunch()` roughly an hour after launch (the `minLifetime` gate is in
    // seconds). Both constants were `constant`, so there was no setter and no
    // migration path, and the hook has < 100 bytes of EIP-170 headroom.
    //
    // The window is now denominated in WALL-CLOCK SECONDS, which carries the intended
    // meaning identically on L1, on an Orbit L2 and on an Orbit L3.
    uint256 public constant HOURS_PER_DAY = 24;
    uint256 internal constant SECONDS_PER_HOUR = 1 hours;
    uint256 internal constant SECONDS_PER_DAY = 1 days;
    // (`BLOCKS_PER_HOUR` / `BLOCKS_PER_DAY` were removed with the block-based clock:
    //  keeping them would have advertised a window the contract no longer honours.)

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /// @notice Volume below this in 24h (in currency0 terms) = dead
    uint256 public deathThreshold;

    /// @notice Optional pluggable death-detection module. When set, `isDead()`
    ///         delegates to it (passing the live 24h volume + threshold), so the
    ///         death RULE can be upgraded — unique traders, liquidity depth, a
    ///         schedule, etc. — WITHOUT an upgradeable proxy. Zero = built-in
    ///         "volume < threshold" rule. Owner/registry-set (timelocked on
    ///         mainnet via the registry's emergency admin).
    IDeathChecker public deathChecker;

    /// @notice Optional pluggable POLICY modules (surtax curve, gacha odds, mint
    ///         curve). Each is a pure view returning a number; when set, the hook
    ///         delegates to it (with a safe fallback to the built-in rule), so the
    ///         launch/economic RULES can be upgraded without an upgradeable proxy.
    ///         Owner/registry-set. Zero = built-in default.
    ISurtaxPolicy public surtaxPolicy;
    IOddsPolicy public oddsPolicy;
    ICurvePolicy public curvePolicy;

    /// @notice Optional pluggable ETH fee-split STRUCTURE. When set, the hook asks
    ///         it how to divide each fee (guild/floor/relaunch) and does the sends
    ///         itself — custody never leaves the hook. Sum must equal the fee or the
    ///         hook falls back to its built-in split. Zero = built-in default.
    IFeeRouter public feeRouter;

    /// @notice Flat hook trading fee (bps) applied when no per-holder tiered NFT
    ///         contract is wired. Owner-tunable, capped at MAX_TAX_BPS (10%).
    ///         Default 300 = 3%. This is the fee charged in ETH on every swap.
    uint256 public defaultTaxBps = 300;

    /// @notice NFT contract for tiered tax lookup
    address public nftContract;

    /// @notice Treasury address for ERC20 fee withdrawals
    address public treasury;

    /// @notice Registry address — only it can pull relaunch ETH
    address public registry;
    /// @notice A proposed successor controller, and when the swap becomes
    ///         executable. See {proposeRegistryOverride} (audit M-01).
    address public pendingRegistry;
    uint256 internal registrySwapReadyAt;
    /// @notice Mandatory announcement delay on a controller swap. Immutable by
    ///         being a constant: the owner cannot shorten their own notice period.
    uint256 public constant REGISTRY_SWAP_DELAY = 7 days;

    // --- Volume tracking ---
    /// @dev GAS (audit G-10): buckets are `uint128`, so TWO share a storage slot and
    ///      the 24-bucket sum in {getVolume24h} costs 12 SLOADs instead of 24. That
    ///      view backs `isDead`, which runs on every perp open and on the relaunch
    ///      gate — it measured ~66k gas as a full-width array. A bucket holds one
    ///      hour of currency0 (ETH) volume in wei; uint128 caps at 3.4e38 wei
    ///      (3.4e20 ETH), so the narrowing is unreachable in practice and the add
    ///      below saturates rather than wrapping if it ever were.
    mapping(PoolId => uint128[24]) private _volumeBuckets;

    mapping(PoolId => uint256) private _lastBucketIndex;
    mapping(PoolId => uint256) private _lastUpdateTs;   // wall-clock (audit Z-05)
    mapping(PoolId => bool) public trackedPools;

    // --- Fee accounting ---
    /// @notice Accumulated ETH reserved for relaunches (self-funding)
    uint256 public relaunchETH;

    // NOTE (audit I-01): the `accumulatedTokenFees` mapping and its
    // `withdrawTokenFees` withdrawal were REMOVED. The hook takes its fee purely in
    // ETH by design (see the header), so nothing ever wrote that mapping and every
    // call reverted `NothingToWithdraw` — a dead surface that implied a token-fee
    // path the protocol does not have.

    // --- Volume-minted NFT collection (per active brew) ---
    /// @notice The active brew's NFT collection. Swaps accrue mint credit; the
    ///         collection mints from that credit. Set by the registry on each
    ///         summon/relaunch so credit always maps to the live generation.
    address public collection;

    /// @notice The hook-native PerpEngine. When set, every swap that carries a
    ///         liquidation hint in `hookData` is checked against it in afterSwap
    ///         — so a buy/sell that tips a position past the TWAP mark AUTO-
    ///         liquidates it and mints the swapper a Liquidatoor badge. The call
    ///         is best-effort (try/catch) so it can never revert a user's swap,
    ///         and is skipped when the engine itself is the swapper (its own
    ///         open/close would otherwise re-enter). Registry/owner-set.
    address public perpEngine;

    // --- Legacy-floor live buyback (P2b) ---------------------------------------
    /// @notice The registry, credited when a legacy buyback executes (it notes the
    ///         bought tokens against the live collection's pending entitlement).
    ///         Zero = live buyback OFF (fees route as before). Registry/owner-set.
    address public legacyRegistry;
    /// @notice Portion (bps) of the POST-guild fee routed to the legacy buyback
    ///         buffer instead of the floor vault. 0 = off.
    uint256 internal legacyBps;
    /// @notice ETH accumulated toward the next legacy buyback.
    uint256 public legacyBuffer;
    /// @notice Buffer size that triggers a buyback (amortizes the nested-swap gas).
    uint256 internal legacyThreshold = 0.02 ether;
    /// @notice The LIVE generation's PoolKey, pushed by the registry at each
    ///         summon/relaunch. The legacy buyback spends ONLY into this key (audit
    ///         C-01b) — never into the key of whatever swap triggered it, which an
    ///         attacker controls. Also the single source of truth for "our pool".
    PoolKey internal _liveKey;
    /// @notice Tokens bought by the live buyback + HELD here, awaiting the registry's
    ///         `materializeLegacyReserve` sweep (which deposits them into the shared
    ///         reserve LP and credits the ledger IN ONE STEP — so the ledger only
    ///         ever credits tokens that are actually in the reserve → Invariant R
    ///         holds by construction, not by the reserve's slack). Cannot addToReserve
    ///         inline (this runs nested in afterSwap with the PoolManager locked).
    uint256 public legacyOwedToReserve;
    /// @notice Reentrancy guard for the hook's OWN buyback swap: when set, before/
    ///         afterSwap early-return so the self-buy never re-charges fees or
    ///         re-fires liquidation/gacha/legacy. Transient (auto-clears per tx).
    bool private transient _inSelfBuy;
    /// @notice Transient: set while the registry drives the relaunch force-close, so
    ///         the engine's dying-pool settlement swaps skip the fee + legacy buyback
    ///         (no nesting) WITHOUT permanently exempting the engine — perp swaps pay
    ///         full fees the rest of the time. Auto-clears per tx.
    bool private transient _inRelaunchClose;
    /// @dev Gas kept back so the buyback self-call can never OOG the parent swap.
    uint256 internal constant LEGACY_GAS_RESERVE = 220_000;
    uint256 internal constant LEGACY_GAS_MIN = 300_000;
    /// @dev Price limit for the ETH→token buyback swap (MIN_SQRT_PRICE + 1 = no floor).
    uint160 internal constant MIN_SQRT_LIMIT = 4295128740;

    event LegacyBuyback(uint256 ethSpent, uint256 tokensBought);

    // --- Progressive seed in-swap nudge (keeperless streaming) -----------------
    /// @notice The progressive {CauldronSeeder}. When set, afterSwap calls its
    ///         `pokeInSwap()` best-effort (gas-bounded, result-ignored) so the active
    ///         tranche streams in as a side-effect of organic trading — no keeper.
    ///         Clear it (`setSeeder(0)`) to disable the in-swap nudge; the seeder's
    ///         permissionless `poke()` still works as a fallback. Registry/owner-set.
    address public seeder;
    /// @dev Gas kept back / floor so the poke can never OOG the parent swap. A poke
    ///      places up to two core positions + settles (~350k worst case), so we only
    ///      fire when at least RESERVE + that budget remains — otherwise the poke
    ///      would OOG mid-placement, roll back, and waste gas on a doomed attempt.
    uint256 internal constant SEED_POKE_GAS_RESERVE = 350_000;
    uint256 internal constant SEED_POKE_GAS_MIN = 750_000;

    /// @notice Volume credit per player (weighted, ETH-terms). Realised into
    ///         NFTs via openNFTs(). Reset to the new brew's namespace by bumping
    ///         `creditEpoch` on every setCollection.
    mapping(uint256 => mapping(address => uint256)) public nftCredit;
    uint256 public creditEpoch;

    /// @notice Rising-difficulty mint curve (Bitcoin-style). The credit cost of
    ///         the k-th NFT = volumePerNFT + k * nftPriceStep (k = 0-indexed
    ///         position), so early minters get an edge and it mints out at a
    ///         volume target. Owner-tunable.
    uint256 public volumePerNFT = 0.02 ether;   // base cost (NFT #1)
    uint256 public nftPriceStep = 0.00002 ether; // per-position increase

    /// @notice The collection's `totalMinted` at the moment it was wired to this
    ///         hook. The rising curve is indexed from HERE, not from absolute
    ///         tokenId — so when a brew CONTINUES an existing collection (e.g.
    ///         iteration #2 keeps minting the genesis MiFrens, which already has
    ///         1111 minted), its volume mints still start at curve position 0.
    ///         Fresh collections wire in at 0, so behaviour is unchanged.
    uint256 internal mintBaseline;

    /// @notice Cap NFTs minted per call (gas safety).
    uint256 public constant MAX_MINTS_PER_CALL = 30;

    // ── CRYSTAL GACHA (commit-reveal lottery, grind-resistant) ──────────────
    // Volume credit buys CRYSTALS along the rising curve. Breaking a crystal
    // doesn't mint instantly — it enqueues a TICKET whose creature-or-nothing
    // outcome is rolled LATER from its commit block's hash (unknowable when you
    // played, so it can't be foreseen, grinded, or re-rolled by reverting).
    // Win chance scales with the ETH size of the play; a pity counter guarantees
    // a creature after enough misses. A MISS isn't wasted — its swap fee already
    // lifted the floor vault for every holder.
    struct Batch {
        address player;      // who the creature mints to on a win
        address collection;  // the iteration's collection (so tickets survive relaunch)
        uint48 commitBlock;  // block the crystals were opened in (seeds the rolls)
        uint16 oddsBps;      // win probability, fixed at commit from play size
        uint16 count;        // crystals in this batch
        uint16 resolved;     // how many rolled so far
    }
    Batch[] public batches;             // FIFO queue of commit batches
    uint256 internal batchCursor;         // index of the batch being resolved
    uint256 public outstandingCrystals; // unresolved crystals across all players
    mapping(address => uint256) public outstandingOf; // per-collection unresolved
    mapping(address => uint256) public opened;      // creatures a player has won (lifetime)
    mapping(address => uint256) public committedOf; // crystals a player has opened
    mapping(address => uint256) public pendingOf;   // a player's unresolved crystals
    mapping(address => uint256) public missStreak;  // consecutive misses (reset on win)

    /// @notice Lifetime weighted volume per player + global (generic oracle).
    mapping(address => uint256) public lifetimeVolumeOf;
    uint256 public totalLifetimeVolume;
    /// @notice Raw (unweighted) cumulative volume across all tracked pools.
    uint256 public cumulativeVolume;

    /// @notice Buy/sell credit weighting (buys favoured). Owner-tunable.
    uint256 public buyWeightBps = 15_000;  // 1.5x
    uint256 public sellWeightBps = 5_000;  // 0.5x
    uint256 public constant MAX_WEIGHT_BPS = 30_000; // 3x cap
    /// @notice When true, swaps that arrive WITHOUT router hookData (direct
    ///         Uniswap / aggregator buys) accrue crystal credit to `tx.origin` —
    ///         so every buyer earns NFT chances, not just our UI. Owner can turn
    ///         it off if untagged-swap gas ever becomes a concern.
    bool public creditUntaggedSwaps = true;

    /// @notice Odds curve: win chance scales with the ETH size of the play, from
    ///         ~0 up to maxOddsBps at oddsFullVolumeWei (never 100% from size —
    ///         only the pity counter guarantees a creature).
    uint256 public oddsFullVolumeWei = 0.5 ether;
    uint256 public maxOddsBps = 9_000;                 // 90%
    uint256 public constant ODDS_HARD_CAP_BPS = 9_500; // setter ceiling
    uint256 public pityThreshold = 8;                  // misses forcing a win

    /// @notice Addresses allowed to open/commit crystals (the gacha router), so
    ///         odds always use the router's honest on-chain play size.
    mapping(address => bool) public isOpener;

    /// @notice Fee-exempt buyers — pay ZERO base tax + ZERO anti-sniper surtax.
    ///         Used for the one-time deployer "snipe" that funds the OG airdrop
    ///         at launch without diluting presalers. Owner/registry-settable.
    ///         Checked against the swap's hookData player, so it only exempts the
    ///         intended wallet, never the router itself.
    mapping(address => bool) public taxExempt;

    /// @notice The active brew's floor vault. A share of ETH fees goes here to
    ///         back every minted NFT with a redeemable floor (set per brew).
    address public vault;

    /// @notice Share of ETH swap fees routed to the floor vault (bps).
    ///         100% by default — all fees back the NFT floor while the brew is
    ///         alive; whatever isn't redeemed sweeps into the next launch's LP.
    uint256 public floorBps = 10_000;

    /// @notice Quest hook — an optional per-brew contract that keeps volume
    ///         meaningful after the collection mints out (rewards, churn, etc).
    ///         The hook forwards swap events to it; it never blocks a swap.
    address public quest;

    /// @notice The genesis MiFrens fee dividend (MiFrensDividend). A tiny,
    ///         PERMANENT slice of every brew's ETH fees streams here so the OG
    ///         genesis holders earn from every iteration forever. Persistent —
    ///         not repointed per brew (unlike vault/collection).
    address public guild;

    /// @notice Share of ETH swap fees streamed to the genesis dividend (bps).
    ///         Carved off the TOP, before the floor split. The OG frens
    ///         bootstrapped the whole machine with their mint ETH, so they earn a
    ///         real founder's cut of EVERY brew's volume — not a token gesture.
    ///         15% default; the remaining 85% backs the live collection's floor.
    ///         Owner/timelock-tunable (setGuildBps), capped implicitly by the fee.
    uint256 public guildBps = 1500; // 15%

    /// @notice The CURRENT iteration's proposer — whoever authored the winning
    ///         relaunch proposal (BrewSpec.proposer). The registry pushes this once
    ///         per relaunch (setActiveProposer). Genesis has none (owner-summoned) →
    ///         stays 0 → the proposer slice is simply skipped for iteration #1.
    address public activeProposer;

    /// @notice Tiny slice of each ETH swap fee (bps) streamed to `activeProposer` —
    ///         the decentralization flywheel: anyone can propose a token + kick the
    ///         eternal machine forward and earn a trickle from their iteration's
    ///         volume. Carved off the TOP of the fee (like the guild slice). Default
    ///         50 = 0.5% of the fee (≈0.005% of a taxed swap). Owner-tunable, hard-
    ///         capped so it can never cannibalize the floor/guild.
    uint256 public proposerBps = 50; // 0.5% of the fee
    uint256 public constant MAX_PROPOSER_BPS = 500; // 5% of the fee — hard ceiling

    /// @notice Claimable proposer earnings (pull pattern — see _routeEthFee). The
    ///         ETH sits in the hook (like relaunchETH/legacyBuffer, both tracked by
    ///         var not raw balance) until the proposer withdraws it.
    mapping(address => uint256) public proposerOwed;

    // --- Sniper protection (per-iteration launch surtax) ---
    /// @notice Block a pool was initialized (each iteration). Set once, in
    ///         afterInitialize. Basis for the decaying launch surtax.
    mapping(PoolId => uint256) public poolInitBlock;

    /// @notice Length (in blocks) of the anti-sniper window after each launch.
    ///         Tunable live via setSnipeParams (no redeploy). Short by design —
    ///         the decay does most of the work in the very first blocks.
    uint256 public snipeWindowBlocks = 30; // ~6 min at 12s blocks

    /// @notice Peak surtax at block 0 (bps), decaying toward 0 by the end of the
    ///         window. Charged ON TOP of the base fee and routed 100% to the
    ///         genesis MiFrens dividend — snipers pay the OG holders. Default is
    ///         set so the FIRST block is a ~99% total tax (with the 3% base).
    uint256 public snipeMaxBps = 9_600; // ~96% surtax + 3% base = ~99% at launch

    /// @notice Hard ceiling for the sniper surtax (bps).
    uint256 public constant MAX_SNIPE_BPS = 9_900; // 99%

    /// @notice Absolute cap on total fee (base + surtax) so a swap always leaves
    ///         something to execute (never a 100% tax → zero-output revert path).
    uint256 public constant MAX_TOTAL_FEE_BPS = 9_900; // 99%

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    event VolumeRecorded(PoolId indexed poolId, uint256 amount, uint256 bucket);
    event CreditAccrued(address indexed player, uint256 amount);
    event NFTsOpened(address indexed player, uint256 count, uint256 creditSpent);
    event CollectionSet(address indexed collection, uint256 epoch);
    event FloorFunded(address indexed vault, uint256 amount);
    event GuildFunded(address indexed guild, uint256 amount);
    event GuildSet(address indexed guild, uint256 bps);
    event ProposerFunded(address indexed proposer, uint256 amount);
    event ActiveProposerSet(address indexed proposer);
    event CrystalsCommitted(address indexed player, uint256 count, uint256 oddsBps);
    event TicketWon(address indexed player, uint256 indexed ticketId, uint256 tokenId);
    event TicketLost(address indexed player, uint256 indexed ticketId);
    event OpenerSet(address indexed who, bool allowed);
    event FeeTaken(PoolId indexed poolId, address indexed swapper, uint256 fee, uint256 rateBps);
    event RelaunchETHReleased(address indexed to, uint256 amount);
    event PoolTracked(PoolId indexed poolId);
    event DeathThresholdUpdated(uint256 newThreshold);
    event DefaultTaxUpdated(uint256 newBps);
    event DeathCheckerSet(address indexed checker);
    event PoliciesSet(address surtax, address odds, address curve);
    event FeeRouterSet(address router);
    event RegistryOverrideProposed(address indexed successor, uint256 readyAt);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------
    /// @param _owner Explicit owner. Hooks are CREATE2-deployed (often via the
    ///        canonical factory), so `msg.sender` in the constructor is the
    ///        factory, not the deployer — the owner must be passed in.
    constructor(
        IPoolManager _poolManager,
        uint256 _deathThreshold,
        address _nftContract,
        address _treasury,
        address _owner
    ) BaseHook(_poolManager) Ownable(_owner) {
        deathThreshold = _deathThreshold;
        nftContract = _nftContract;
        treasury = _treasury;
    }

    // -----------------------------------------------------------------------
    // Hook Permissions
    // -----------------------------------------------------------------------

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------------------------------
    // Hook Callbacks
    // -----------------------------------------------------------------------

    /// @dev ADOPTION GATE (audit C-01). V4 lets ANYONE initialize a pool naming any
    ///      hook, so this callback is an untrusted entrypoint. The hook's whole fee
    ///      engine assumes currency0 is native ETH and denominates its accounting in
    ///      ETH — so a foreign pool (worse, a pool with NO ether leg) could mint
    ///      phantom `relaunchETH` and permanently brick `releaseRelaunchETH`, and
    ///      could steer the legacy buyback into an attacker-priced book.
    ///      We therefore only ever ADOPT pools the registry itself created, paired
    ///      against native ETH. Returning the selector WITHOUT tracking (rather than
    ///      reverting) is deliberate: a revert here would let anyone grief pool
    ///      creation, whereas simply declining to track means the hook serves that
    ///      pool no fee logic at all (every hot path is `trackedPools`-gated).
    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160,
        int24
    ) internal override returns (bytes4) {
        if (sender != registry) return BaseHook.afterInitialize.selector;

        //  Which side is the quote? One allowlist read on currency0 settles it:
        //  the registry validates the quote BEFORE creating the pool, so exactly
        //  one side is a permitted quote — if it is not currency0 it is
        //  currency1. Checking both sides here would be a second external call
        //  to re-derive what the caller already guaranteed, and this hook has no
        //  bytecode budget to spare (EIP-170).
        //
        //  Trusting the registry is sound because `sender != registry` above is
        //  the actual security property (audit C-01). The old
        //  `currency0 != address(0)` line was never doing that work — it
        //  asserted the fee logic's ETH assumption, which is what is being
        //  generalised here.
        bool q0 = IRegistryQuotes(registry).allowedQuote(Currency.unwrap(key.currency0));

        PoolId id = key.toId();
        quoteIsCurrency0[id] = q0;
        trackedPools[id] = true;
        _lastUpdateTs[id] = block.timestamp;
        poolInitBlock[id] = block.number; // anchor the anti-sniper window
        emit PoolTracked(id);
        return BaseHook.afterInitialize.selector;
    }

    /// @dev Whether this swap's pool is one the protocol actually serves. Every
    ///      value-moving path in before/afterSwap is gated on this (audit C-01):
    ///      an unadopted pool gets NO fee take, NO volume/credit accrual, NO
    ///      buyback and NO seeder poke — the hook is simply inert for it.
    ///      Takes the ALREADY-COMPUTED PoolId: `key.toId()` is a keccak256 over the
    ///      5-field PoolKey, and the swap path used to hash it three separate times
    ///      (here, for volume, and again in `_takeEthFee`). Hash once, pass it down.
    ///      (Gas audit G-09.)
    /// @notice Which side of a tracked pool is the QUOTE (the asset the iteration
    ///         token is priced in). True = currency0.
    ///
    ///  Native ETH is `address(0)`, which always sorts first, so for an ETH pair
    ///  this is always true and every "quote is currency0" assumption held. An
    ///  ERC20 quote sorts by address against a token deployed with plain CREATE,
    ///  so it lands on EITHER side. Recorded once at adoption and read from
    ///  there: deriving it per call site is how a buy gets counted as a sell.
    mapping(PoolId => bool) internal quoteIsCurrency0;

    /// @notice Pools whose volume counts toward the SAME generation.
    ///
    ///  Death is measured on 24h volume, and a generation's liquidity can be
    ///  split across more than one pool once the guild pairs it against a second
    ///  quote. Read per-pool, the primary's volume can fall under the death
    ///  threshold purely because trading moved to the sibling — relaunching a
    ///  generation that is perfectly alive.
    ///
    ///  DECLARED LAST, deliberately. New storage goes at the END so existing
    ///  slots keep their numbers; inserting it mid-layout renumbered everything
    ///  after it and broke a test that writes `legacyOwedToReserve` by slot.
    mapping(PoolId => PoolId[]) private _volumeSiblings;


    /**
     * @dev afterSwap: record volume + take tiered fee via return delta.
     *
     *  ETH fees go to relaunchETH (self-funding the next generation). The fee is
     *  ALWAYS taken in ETH — there is no token-fee path (audit I-01).
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // The hook's OWN legacy buyback swap, or the relaunch force-close — skip ALL
        // afterSwap logic (fee, vol, liquidation, gacha, legacy) so neither nests.
        if (_inSelfBuy || _inRelaunchClose) return (BaseHook.afterSwap.selector, 0);
        PoolId id = key.toId(); // hashed ONCE for this whole callback (G-09)
        // ADOPTION GATE (audit C-01): a pool the protocol never created gets no fee,
        // no accounting and no spending. Cheap early-out on the hot path.
        if (!trackedPools[id]) return (BaseHook.afterSwap.selector, 0);
        // Which side is the quote, read ONCE for this callback. Every direction,
        // volume and fee-side decision below derives from it.
        bool q0 = quoteIsCurrency0[id];

        // Buys buffer their fee in beforeSwap (and afterSwap early-returns for them),
        // so try the buyback up-front too — either leg can trigger it.
        _maybeLegacyBuyback(id, key);
        // Progressive seed: stream the next sliver in-swap (keeperless), best-effort.
        _maybePoke();

        // Set when this is a NATIVE (non-router) swap whose buyer should forge
        // crystals in-swap — fired at the end of afterSwap (see native gacha).
        address gachaPlayer;
        uint256 gachaWei;

        // --- Volume tracking ---
        if (trackedPools[id]) {
            // Volume is measured in QUOTE terms. With an ERC20 quote that may be
            // currency1, so read the side adoption recorded rather than amount0.
            int128 quoteAmt = q0 ? delta.amount0() : delta.amount1();
            uint256 absVolume = quoteAmt >= 0
                ? uint256(uint128(quoteAmt))
                : uint256(uint128(-quoteAmt));
            _recordVolume(id, absVolume);
            cumulativeVolume += absVolume;

            // Accrue crystal credit to the buyer. Router swaps carry the player in
            // hookData; a swap with NO router hookData (direct Uniswap / aggregator)
            // falls back to `tx.origin` when `creditUntaggedSwaps` is on — so ANYONE
            // who buys through the pool earns crystals, not just our UI. This isn't
            // farmable: credit is proportional to VOLUME, and volume costs real fees
            // + price impact, so every crystal is paid for. `sender` (the router) is
            // NEVER credited. Buys are weighted higher than sells. All arithmetic
            // saturates + no external call reverts, so a swap can never revert here.
            // LIVE-POOL GATE (audit Z-09). `_served` only asks whether the pool is
            // TRACKED, and retired generations stay tracked forever, so a swap on any
            // past generation's pool still minted crystal credit in the CURRENT epoch
            // and inflated the lifetime/cumulative volume oracles. An attacker could
            // re-provide liquidity to a dead, worthless pool they price themselves and
            // farm the newborn collection with no exposure to the live token. Credit is
            // now accrued only for the pool the registry has declared live.
            if (
                collection != address(0) && absVolume > 0
                    && Currency.unwrap(key.currency1) == Currency.unwrap(_liveKey.currency1)
            ) {
                // ATTRIBUTION. A trusted router tags the real buyer in hookData;
                // otherwise we credit `tx.origin`.
                //
                // `tx.origin` IS DELIBERATE (audit L-03, accepted). It is wrong for
                // ERC-4337 smart accounts, where it is the BUNDLER — but every
                // alternative is worse for the case that actually dominates: a user
                // clicking Buy in any Uniswap UI or aggregator arrives with
                // `sender` = the ROUTER, so crediting `sender` would send the
                // crystal (and the NFT it forges) to the router contract instead of
                // the person who paid. Crediting the EOA that signed the tx is the
                // only attribution that reaches the buyer without a trusted tag.
                // Smart-account users should route through a tagging opener, and
                // `creditUntaggedSwaps` can disable this path entirely.
                bool tagged = hookData.length >= 32;
                address player = tagged
                    ? abi.decode(hookData, (address))
                    : (creditUntaggedSwaps ? tx.origin : address(0));
                // The registry's relaunch green-candle buy funds the migration
                // reserve — it is NOT a real trader. Skip ALL credit/volume/gacha
                // accrual for it, else its (large) reserve buy would inflate
                // totalLifetimeVolume + mint out the newborn NFT collection.
                if (player == registry) player = address(0);
                if (player != address(0)) {
                    // Buy = player acquires the iteration token, i.e. pays the quote
                    // in. That is `zeroForOne` only while the quote is currency0;
                    // with the quote at currency1 it is exactly inverted, and
                    // reading it raw would weight every buy as a sell.
                    bool isBuy = params.zeroForOne == q0;
                    uint256 weighted = (absVolume * (isBuy ? buyWeightBps : sellWeightBps)) / BPS;
                    // Saturate on add so a monster swap can never revert the swap
                    // path via overflow (audit I1). Realistically unreachable.
                    unchecked {
                        uint256 c = nftCredit[creditEpoch][player];
                        uint256 nc = c + weighted;
                        nftCredit[creditEpoch][player] = nc < c ? type(uint256).max : nc;
                        uint256 lv = lifetimeVolumeOf[player];
                        uint256 nlv = lv + weighted;
                        lifetimeVolumeOf[player] = nlv < lv ? type(uint256).max : nlv;
                        uint256 tv = totalLifetimeVolume;
                        uint256 ntv = tv + weighted;
                        totalLifetimeVolume = ntv < tv ? type(uint256).max : ntv;
                    }
                    emit CreditAccrued(player, weighted);
                    // Forward to the quest contract (post-mintout engagement) only on
                    // the router path, so untagged aggregator swaps stay cheap. Low-
                    // level + ignored result so it can never revert a swap.
                    if (tagged && quest != address(0)) {
                        quest.call(
                            abi.encodeWithSignature("onSwap(address,uint256)", player, weighted)
                        );
                    } else if (!tagged) {
                        // NATIVE path (direct Uniswap / aggregator): remember the
                        // buyer so we forge their crystals at the end of afterSwap —
                        // no router. The router path commits/resolves itself.
                        gachaPlayer = player;
                        gachaWei = weighted;
                    }
                }
            }
        }

        // --- Auto-liquidation sweep (hook-native perps) ---
        // If this swap carries a liquidation hint (hookData = abi.encode(player,
        // liqHint)), fire the engine at the hinted position. It only acts if the
        // position is genuinely underwater at the TWAP mark, crediting `player`
        // (the swapper) with the keeper reward + a Liquidatoor badge. Skipped
        // when the engine ITSELF is swapping (its own open/close would re-enter
        // its nonReentrant guard).
        //
        // GAS SAFETY: liquidateInSwap does REAL nested pool swaps to settle the
        // position, which are expensive. We forward it (gasleft − LIQ_GAS_RESERVE)
        // and keep the reserve for THIS afterSwap to finish (fee take + return +
        // the PoolManager's reentrancy-guard unlock). So an under-water liq that
        // needs more gas than we can spare simply no-ops instead of starving the
        // parent swap ("out of gas: not enough gas for reentrancy sentry"). The
        // keeper / post-open / next-trade paths still catch anything skipped here.
        // Auto-liquidation sweep — HINT-FREE, so EVERY swap on ANY interface
        // (Uniswap, aggregators, bots, our UI) opportunistically liquidates any
        // underwater position. The engine scans a bounded rotating window and
        // credits the swapper (`tx.origin`, the EOA that sent the tx) a keeper
        // reward + a Liquidatoor badge per kill. Skipped only when the engine
        // ITSELF is swapping (its own settlement would re-enter). We keep
        // LIQ_GAS_RESERVE for this afterSwap to finish, forwarding the rest — so
        // the sweep can never OOG the parent swap (best-effort; low-level call
        // with ignored result).
        if (perpEngine != address(0) && sender != perpEngine) {
            uint256 g = gasleft();
            if (g > LIQ_GAS_RESERVE + LIQ_GAS_MIN) {
                perpEngine.call{gas: g - LIQ_GAS_RESERVE}(
                    abi.encodeWithSelector(IPerpEngineLiq.sweepLiquidations.selector, tx.origin)
                );
            }
        }

        // --- NATIVE in-swap gacha ---
        // A direct/aggregator buy (no router hookData) forges crystals RIGHT HERE:
        // commit the buyer's fresh credit + resolve matured tickets — so a raw
        // Uniswap swap mints NFTs with NO router. Isolated self-call, gas-bounded
        // (keeps GACHA_GAS_RESERVE for fee collection + return), result ignored —
        // it can NEVER revert or OOG the swap. Post-mintout it simply no-ops
        // (commit returns 0, resolve misses), so trading keeps working after
        // the collection sells out.
        if (gachaPlayer != address(0)) {
            uint256 gg = gasleft();
            if (gg > GACHA_GAS_MIN) {
                address(this).call{gas: gg - GACHA_GAS_RESERVE}(
                    abi.encodeWithSelector(this.nativeGachaStep.selector, gachaPlayer, gachaWei)
                );
            }
        }

        // --- Fee collection (ETH leg only) ---
        // The fee is ALWAYS taken in ETH so every swap funds the machine.
        //   - Buys  (ETH is the INPUT): charged in _beforeSwap.
        //   - Sells (ETH is the OUTPUT / unspecified leg): charged HERE.
        // We only act when the unspecified currency is the QUOTE; the buy case is
        // already handled before the swap, so this never double-charges.
        //
        // The original expression answered "is the unspecified currency
        // currency0?" — correct while the quote was always ETH at currency0.
        // Derived once and compared against the recorded quote side, it stays
        // correct when an ERC20 quote sorts to currency1 instead; used raw it
        // would charge the fee on the TOKEN leg, taking fees in a token that is
        // about to die.
        bool exactInput = params.amountSpecified < 0;
        bool unspecifiedIsCurrency0 = exactInput ? (!params.zeroForOne) : (params.zeroForOne);
        if (unspecifiedIsCurrency0 != q0) {
            return (BaseHook.afterSwap.selector, 0);
        }
        // Fee-exempt buyer (deployer snipe) → no sell-leg fee either.
        if (_isExemptPlayer(sender, hookData)) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // The quote sits on the unspecified leg here, whichever side that is.
        int128 quoteOut = q0 ? delta.amount0() : delta.amount1();
        uint256 ethAmount = quoteOut >= 0
            ? uint256(uint128(quoteOut))
            : uint256(uint128(-quoteOut));

        uint256 fee = _takeEthFee(id, key, sender, hookData, ethAmount, false); // afterSwap = SELL leg
        _maybeLegacyBuyback(id, key);
        return (BaseHook.afterSwap.selector, int128(uint128(fee)));
    }

    /// @dev LEGACY BUYBACK: when the buffer is full, fire a gas-bounded self-call to
    ///      market-buy the token (backing the live collection's floor). Isolated +
    ///      gas-capped + result-ignored → it can NEVER revert or OOG the parent swap
    ///      (mirrors the native-gacha safety pattern). No-ops if it can't run.
    ///      Called on BOTH legs (top of afterSwap for buys — whose fee was already
    ///      buffered in beforeSwap — and after the sell fee) so either side triggers.
    ///      SPEND GATE (audit C-01b): the buy is executed against the LIVE key the
    ///      registry recorded, never the key of whatever swap happened to trigger
    ///      us. Driving it off the caller's key let an attacker point the hook's
    ///      own ETH at a book they priced and control.
    function _maybeLegacyBuyback(PoolId id, PoolKey calldata key) private {
        if (legacyRegistry == address(0) || legacyBuffer < legacyThreshold) return;
        //  ETH-LAYOUT ONLY, for now. `legacyBuyStep` hardcodes `zeroForOne: true`
        //  and settles with `settle{value:}`. On a pool whose iteration token
        //  sorts to currency0, `zeroForOne: true` swaps TOKEN OUT — it would
        //  SELL the token this buyback exists to BUY, and the native settle
        //  would revert against an ERC20 quote anyway.
        //
        //  Skipping is safe and costs nothing: the floor share simply stays in
        //  the buffer and rolls to the relaunch reserve, exactly as it does when
        //  `legacyRegistry` is unset. Generalising the swap direction and the
        //  settle path is tracked in docs/QUOTE_ASSET_PLAN.md §5.
        if (!quoteIsCurrency0[id]) return;
        PoolKey memory live = _liveKey;
        // Only ever fire on (and into) the protocol's own live pool.
        if (Currency.unwrap(live.currency1) == address(0)) return; // not wired yet
        if (PoolId.unwrap(id) != PoolId.unwrap(live.toId())) return;
        key; // (the caller's key is intentionally UNUSED — we spend into `live`)
        uint256 gl = gasleft();
        if (gl > LEGACY_GAS_MIN) {
            address(this).call{gas: gl - LEGACY_GAS_RESERVE}(
                abi.encodeWithSelector(this.legacyBuyStep.selector, live)
            );
        }
    }

    /// @dev PROGRESSIVE SEED in-swap nudge: advance the streamer as a side effect of
    ///      trading. The seeder adds its band via CORE modifyLiquidity (we already
    ///      hold the unlock here), so — unlike the periphery PositionManager — it does
    ///      NOT re-enter `unlock`. Gas-bounded + result-ignored (like the legacy
    ///      buyback) so it can NEVER revert or OOG the parent swap; `pokeInSwap` is a
    ///      no-op when complete / throttled. No-ops if unset (in-swap streaming off).
    function _maybePoke() private {
        address s = seeder;
        if (s == address(0)) return;
        uint256 g = gasleft();
        if (g > SEED_POKE_GAS_MIN) {
            s.call{gas: g - SEED_POKE_GAS_RESERVE}(abi.encodeWithSelector(ISeederInSwap.pokeInSwap.selector));
        }
    }

    /// @notice Self-only: spend the buffered ETH on a market-buy of the token and
    ///         note the bought amount against the live collection's pending legacy
    ///         entitlement (the registry credits it; it crystallizes at death and
    ///         is covered by the reserve at the next relaunch). The `_inSelfBuy`
    ///         guard makes this nested swap pay no fee + never recurse. Best-effort:
    ///         if the registry note reverts we keep the tokens (buffer already spent
    ///         = real buyback pressure regardless).
    function legacyBuyStep(PoolKey calldata key) external {
        if (msg.sender != address(this)) revert OnlySelf();
        uint256 amt = legacyBuffer;
        if (amt < legacyThreshold) return;
        legacyBuffer = 0;

        // The swap/settle/take mechanics live in a LINKED library so this hook
        // stays under the EIP-170 limit. It is delegatecalled, so it runs in this
        // contract's context — the ETH settled is ours and the token taken lands
        // here. All bookkeeping stays on this side, which keeps every public
        // getter the indexer reads exactly where it was.
        _inSelfBuy = true;
        (uint256 spent, uint256 got) = LegacyBuyLib.buyStep(poolManager, key, amt);
        _inSelfBuy = false;

        // Return the unspent remainder to the buffer so it funds the next buy
        // (the price limit can bind and consume less than `amt`).
        if (spent < amt) { unchecked { legacyBuffer += amt - spent; } }

        // DEFER the ledger credit: we hold the tokens and track them. The registry's
        // permissionless `materializeLegacyReserve` deposits them into the reserve LP
        // AND credits the ledger together, so a credit never out-runs the reserve
        // (can't addToReserve here — nested in afterSwap, PoolManager locked).
        legacyOwedToReserve += got;
        emit LegacyBuyback(amt, got);
    }

    /// @notice Add ETH to the legacy buyback buffer — the entry point for NFT
    ///         secondary ROYALTIES (via a RoyaltyRouter) so they market-buy the token
    ///         and back the live collection's floor, same as swap-fee funding.
    ///         Permissionless (a donation only grows the floor). Kept SEPARATE from
    ///         the empty `receive()` because the hook receives raw ETH internally
    ///         (fee takes) that must NOT be double-counted into the buffer.
    function fundLegacyBuffer() external payable {
        legacyBuffer += msg.value;
    }

    /// @notice Registry-only: hand the held live-buyback tokens to the registry so it
    ///         can deposit them into the reserve + credit the ledger atomically. Caps
    ///         at the actual balance (defensive). Returns the amount transferred.
    /// @dev DEBIT ONLY WHAT ACTUALLY MOVED (audit F-03). This used to zero
    ///      `legacyOwedToReserve` unconditionally and only THEN clamp the transfer to
    ///      the live balance, so any state where `balance < owed` silently destroyed
    ///      the difference: those tokens stay in the hook, are credited to no
    ///      collection's floor, and no later sweep can recover them because the
    ///      counter that remembers them is gone. Debiting the transferred amount
    ///      keeps the remainder claimable by the next sweep, and preserves the
    ///      "ledger credit never out-runs the reserve" property either way (the
    ///      registry credits exactly the returned `amt`).
    function sweepLegacyReserve(address token, address to) external returns (uint256 amt) {
        if (msg.sender != legacyRegistry) revert OnlySelf();
        uint256 owed = legacyOwedToReserve;
        uint256 bal = IERC20(token).balanceOf(address(this));
        amt = owed > bal ? bal : owed;
        legacyOwedToReserve = owed - amt;
        if (amt > 0) IERC20(token).transfer(to, amt);
    }

    /**
     * @dev beforeSwap: charge the ETH trading fee on BUYS (exact-input swaps
     *      where ETH is the input). Sells + exact-output buys are charged on the
     *      ETH output in afterSwap. This guarantees every swap pays its fee in
     *      ETH — funding the floor vault, the genesis dividend, and the relaunch
     *      reserve — so no fee value is ever stranded in a soon-to-die token.
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // The hook's OWN legacy buyback, or the relaunch force-close → charge nothing.
        if (_inSelfBuy || _inRelaunchClose) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        // ADOPTION GATE (audit C-01): never charge a fee in a pool we don't serve.
        PoolId id = key.toId(); // hashed ONCE for this whole callback (G-09)
        if (!trackedPools[id]) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        // Act only on exact-input buys (the QUOTE is the input).
        bool q0 = quoteIsCurrency0[id];
        bool exactInput = params.amountSpecified < 0;
        // FEE-BYPASS GUARD (audit Z-01 — High). Of the four swap quadrants, the
        // EXACT-OUTPUT SELL (amountSpecified > 0, !zeroForOne) is the only one nobody
        // charged: `_beforeSwap` skips it for not being exact-input, and `_afterSwap`
        // early-returns because its `unspecifiedIsEth` test is false — the unspecified
        // leg is the TOKEN, so V4's afterSwap return delta physically cannot take an
        // ETH fee there. The swap therefore executed with ZERO fee (measured: 0 wei vs
        // 4.24e15 wei on the identical exact-input sell) while still accruing crystal
        // credit and lifetime volume. Since the hook is ETH-fee-only by design, the
        // quadrant is refused rather than served for free; the exact-INPUT sell is the
        // economically equivalent route and is unaffected.
        //  Read against the QUOTE side: a "sell" is the trader giving up the
        //  iteration token, which is `!zeroForOne` only while the quote is
        //  currency0. Left raw, an ERC20 quote at currency1 would invert the
        //  quadrant and refuse exact-output BUYS while serving the very
        //  fee-bypass this guard exists to close.
        //  A BUY is the trader paying the quote in, which is `zeroForOne` only
        //  while the quote is currency0 — with an ERC20 quote at currency1 the
        //  quadrant inverts. One derivation serves both tests below; deriving it
        //  twice is how the two drift apart.
        bool inputIsQuote = params.zeroForOne == q0;
        if (!exactInput && !inputIsQuote) revert ExactOutSellUnsupported();
        if (!exactInput || !inputIsQuote) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        // Fee-exempt buyer (the deployer snipe) → charge nothing.
        if (_isExemptPlayer(sender, hookData)) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Skim the ETH fee (base tax + anti-sniper surtax) off the input before
        // the swap. The positive specified delta tells the PoolManager the hook
        // consumed `fee` of the input, so only (amountIn - fee) is swapped.
        uint256 amountIn = uint256(-params.amountSpecified);
        uint256 fee = _takeEthFee(id, key, sender, hookData, amountIn, true); // beforeSwap = BUY leg (ETH in)
        if (fee == 0) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(int128(int256(fee)), 0),
            0
        );
    }

    /**
     * @dev Split an ETH fee: guildBps -> genesis MiFrens dividend (permanent
     *      tribute, off the top), then floorBps of the remainder -> the active
     *      brew's floor vault, and whatever's left -> the relaunch reserve.
     */
    /// @dev Route a PERP swap's base fee: 30% → the genesis dividend (OGs earn from
    ///      perp volume too), 70% → the ETH PLV (yield for the stakers who back
    ///      leverage). Any send failure rolls into the relaunch reserve so a perp
    ///      swap can never brick on fee routing. Perp swaps keep PAYING the fee
    ///      (revenue) — this only changes WHERE it goes vs an organic swap.
    function _routePerpFee(uint256 amount, bool isBuy) private {
        uint256 toGuild = (amount * 3000) / BPS;   // 30% → OGs
        uint256 toStakers = amount - toGuild;      // 70% → the side-attributed stakers
        uint256 leftover;
        if (toGuild > 0 && guild != address(0)) {
            (bool okG, ) = guild.call{value: toGuild}("");
            if (okG) emit GuildFunded(guild, toGuild); else leftover += toGuild;
        } else { leftover += toGuild; }
        if (toStakers > 0) {
            // Buy (ETH→token, ~long activity) → ETH stakers; sell (token→ETH, ~short
            // activity) → token stakers. Fee follows the side whose trade drove it.
            bytes4 sel = isBuy ? IPerpFeeCredit.creditPerpFee.selector : IPerpFeeCredit.creditPerpFeeToken.selector;
            (bool okS, ) = perpEngine.call{value: toStakers}(abi.encodeWithSelector(sel));
            if (!okS) leftover += toStakers;
        }
        relaunchETH += leftover;
    }

    function _routeEthFee(uint256 feeAmount) private {
        if (feeAmount == 0) return;

        // PROPOSER FLYWHEEL: carve a tiny slice off the TOP for the current
        // iteration's proposer (whoever kicked the machine forward). PULL pattern —
        // the slice is ACCRUED to a claimable balance, never pushed. `activeProposer`
        // is attacker-controlled (anyone can propose), so a push here would be an
        // untrusted external call in the swap hot path; accrual keeps the swap path
        // call-free and re-entrancy-proof. Claimed later via `claimProposerFees`.
        address prop = activeProposer;
        if (prop != address(0) && proposerBps > 0) {
            uint256 wantProp = (feeAmount * proposerBps) / BPS;
            if (wantProp > 0) {
                proposerOwed[prop] += wantProp;
                feeAmount -= wantProp;
                emit ProposerFunded(prop, wantProp);
            }
        }

        // Compute the split. A pluggable IFeeRouter can restructure it (the hook
        // still does the sends → custody never leaves here). Its three parts must
        // sum EXACTLY to feeAmount; any revert/mismatch → built-in split. This is
        // how the fee STRUCTURE upgrades without ever exposing a fund-flow to a
        // rug — a bad router can only fall back, never misroute.
        uint256 wantGuild;
        uint256 wantFloor;
        uint256 wantRelaunch;
        bool routed;
        IFeeRouter fr = feeRouter;
        if (address(fr) != address(0)) {
            try fr.route(feeAmount, guild, vault, guildBps, floorBps) returns (uint256 g, uint256 f, uint256 r) {
                if (g + f + r == feeAmount) { wantGuild = g; wantFloor = f; wantRelaunch = r; routed = true; }
            } catch { /* fall through to built-in */ }
        }
        if (!routed) {
            // Built-in: guildBps off the top → floorBps of remainder → rest relaunch.
            // FULL-UNIFY: floorBps is computed even with no ETH vault — the floor
            // share becomes token BUY PRESSURE (routed to the legacy buffer below)
            // that funds the live collection's TOKEN floor.
            wantGuild = (guild != address(0) && guildBps > 0) ? (feeAmount * guildBps) / BPS : 0;
            uint256 rem = feeAmount - wantGuild;
            wantFloor = floorBps > 0 ? (rem * floorBps) / BPS : 0;
            wantRelaunch = rem - wantFloor;
        }

        // LEGACY LIVE BUYBACK: carve legacyBps of the post-guild remainder into the
        // buyback buffer (funds a market-buy that backs the live collection's floor
        // — see legacyBuyStep). Taken from the floor share first, then relaunch.
        if (legacyRegistry != address(0) && legacyBps > 0) {
            uint256 want = ((feeAmount - wantGuild) * legacyBps) / BPS;
            uint256 fromFloor = want > wantFloor ? wantFloor : want;
            wantFloor -= fromFloor;
            uint256 fromRelaunch = want - fromFloor;
            if (fromRelaunch > wantRelaunch) fromRelaunch = wantRelaunch;
            wantRelaunch -= fromRelaunch;
            legacyBuffer += fromFloor + fromRelaunch;
        }

        // Do the sends. A rejecting guild/floor sink is caught and its share rolls
        // into the relaunch reserve, so a swap can never brick on the fee routing.
        uint256 leftover = 0;
        if (wantGuild > 0 && guild != address(0)) {
            (bool okG, ) = guild.call{value: wantGuild}("");
            if (okG) emit GuildFunded(guild, wantGuild);
            else leftover += wantGuild;
        } else { leftover += wantGuild; }
        if (wantFloor > 0) {
            if (vault != address(0)) {
                (bool okF, ) = vault.call{value: wantFloor}("");
                if (okF) emit FloorFunded(vault, wantFloor);
                else leftover += wantFloor;
            } else if (legacyRegistry != address(0)) {
                // FULL-UNIFY (no ETH vault): the floor share joins the legacy buffer
                // → a market-buy of the token that backs the live collection's floor.
                legacyBuffer += wantFloor;
            } else {
                leftover += wantFloor; // no vault + no buyback → fold into relaunch
            }
        }
        relaunchETH += wantRelaunch + leftover;
    }

    /// @notice Anti-sniper surtax (bps) for a pool at the CURRENT block. Peaks at
    ///         launch (~99% total tax with the base) and decays to 0 by the end of
    ///         the window. A per-block random jitter (from this block's
    ///         `prevrandao`, unknown when a sniper submits) is folded in so there
    ///         is no cleanly-predictable "cheap" block to schedule an entry into —
    ///         you can't just ape the block after a fixed window.
    function snipeSurtaxBps(PoolId id) public view returns (uint256) {
        ISurtaxPolicy pol = surtaxPolicy;
        if (address(pol) != address(0)) {
            try pol.surtaxBps(id, poolInitBlock[id], snipeMaxBps, snipeWindowBlocks) returns (uint256 b) {
                // Clamp to the hard cap so a module can't exceed the max surtax.
                return b > MAX_SNIPE_BPS ? MAX_SNIPE_BPS : b;
            } catch { /* fall through to built-in */ }
        }
        return _defaultSurtaxBps(id);
    }

    /// @dev Built-in anti-sniper surtax curve (linear decay + prevrandao jitter).
    function _defaultSurtaxBps(PoolId id) internal view returns (uint256) {
        uint256 maxBps = snipeMaxBps;
        uint256 window = snipeWindowBlocks;
        if (maxBps == 0 || window == 0) return 0;
        uint256 start = poolInitBlock[id];
        if (start == 0) return 0;
        uint256 elapsed = block.number - start;
        if (elapsed >= window) return 0;

        uint256 remaining = window - elapsed;
        // Deterministic decay: high at launch, fading to 0 across the window.
        uint256 decayed = (maxBps * remaining) / window;
        // Per-block jitter, also fading with the window, so late-window blocks can
        // still randomly spike — a sniper can't pick a guaranteed-cheap block.
        //
        // ENTROPY (audit L-02). `prevrandao` is useless here: it is a constant (1)
        // on Arbitrum/Orbit. The previous blockhash varies per block but is KNOWN to
        // everyone during block N, so a sniper submitting into N could compute the
        // exact surtax and skip expensive blocks. We therefore also fold in the
        // pool's LIVE tick, which moves with the very trade being priced and is not
        // knowable at submission time. Effect is bounded either way: the decay term
        // dominates early and the jitter can only ever RAISE the rate (max below).
        (, int24 tick,,) = poolManager.getSlot0(id);
        uint256 rnd = uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), PoolId.unwrap(id), block.number, tick))
        ) % (maxBps + 1);
        uint256 jitter = (rnd * remaining) / window;
        return decayed > jitter ? decayed : jitter;
    }

    /**
     * @dev Take the ETH fee for `ethAmount`: the base holder tax PLUS the decaying
     *      anti-sniper surtax. The base is routed normally (guild/floor/relaunch);
     *      the surtax goes 100% to the genesis MiFrens dividend — snipers who pile
     *      into a fresh iteration end up paying the OG holders. Returns the total
     *      ETH taken (the hook's returnDelta on the ETH leg).
     */
    function _takeEthFee(
        PoolId id, PoolKey calldata key, address sender, bytes calldata hookData,
        uint256 ethAmount, bool isBuy
    )
        private
        returns (uint256 total)
    {
        // Tax the TRADER, not the router (audit L-04). `sender` is whoever called
        // `poolManager.swap` — for any routed trade that is the router, so a holder
        // trading through our own gacha router, a universal router or an aggregator
        // was charged the router's (default) tier and could never reach their
        // discount. Resolve the same identity the exemption check uses: the tagged
        // player when the sender is a trusted opener, else the sender itself.
        uint256 taxRate = _getHolderTaxRate(_taxedPlayer(sender, hookData));
        // Clamp the combined rate so a swap always leaves >=1% to execute.
        uint256 totalBps = taxRate + snipeSurtaxBps(id);
        if (totalBps > MAX_TOTAL_FEE_BPS) totalBps = MAX_TOTAL_FEE_BPS;
        total = (ethAmount * totalBps) / BPS;
        if (total == 0) return 0;

        // Base portion routes normally (guild 1% / floor / relaunch); the surtax
        // remainder goes 100% to the genesis dividend.
        uint256 baseBps = taxRate < totalBps ? taxRate : totalBps;
        uint256 baseFee = (ethAmount * baseBps) / BPS;
        uint256 surtax = total - baseFee;

        // Take the fee on the QUOTE side, whichever currency that is. `take`
        // is currency-agnostic; only the choice of side needed generalising.
        poolManager.take(quoteIsCurrency0[id] ? key.currency0 : key.currency1, address(this), total);
        // PERP-swap fees (sender == the engine) reward the OGs + the people funding
        // the perps (30% dividend / 70% ETH PLV) instead of the collection floor —
        // perp volume feeds the perp stakers. All other swaps route normally.
        if (baseFee > 0) {
            if (sender == perpEngine && perpEngine != address(0)) _routePerpFee(baseFee, isBuy);
            else _routeEthFee(baseFee);
        }
        if (surtax > 0) {
            if (guild != address(0)) {
                (bool ok, ) = guild.call{value: surtax}("");
                if (ok) emit GuildFunded(guild, surtax);
                else _routeEthFee(surtax); // fallback if guild rejects
            } else {
                _routeEthFee(surtax);
            }
        }
        emit FeeTaken(id, sender, total, totalBps);
    }

    /// @notice Owner-tunable anti-sniper window (blocks) + peak surtax (bps).
    function setSnipeParams(uint256 windowBlocks, uint256 maxBps) external onlyOwner {
        require(maxBps <= MAX_SNIPE_BPS, "snipe bps too high");
        snipeWindowBlocks = windowBlocks;
        snipeMaxBps = maxBps;
    }

    // -----------------------------------------------------------------------
    // Volume Tracking
    // -----------------------------------------------------------------------

    function _recordVolume(PoolId id, uint256 amount) private {
        uint256 currentBucket = _getCurrentBucket();
        uint256 lastBucket = _lastBucketIndex[id];
        uint256 lastTs = _lastUpdateTs[id];

        if (block.timestamp > lastTs + SECONDS_PER_DAY) {
            for (uint256 i = 0; i < HOURS_PER_DAY; i++) {
                _volumeBuckets[id][i] = 0;
            }
        } else if (currentBucket != lastBucket) {
            uint256 steps = currentBucket > lastBucket
                ? currentBucket - lastBucket
                : HOURS_PER_DAY - lastBucket + currentBucket;
            if (steps > HOURS_PER_DAY) steps = HOURS_PER_DAY;

            for (uint256 i = 1; i <= steps; i++) {
                _volumeBuckets[id][(lastBucket + i) % HOURS_PER_DAY] = 0;
            }
        }

        // Saturating add: a bucket can never wrap (see the uint128 note above).
        uint256 bucketTotal = uint256(_volumeBuckets[id][currentBucket]) + amount;
        _volumeBuckets[id][currentBucket] =
            bucketTotal > type(uint128).max ? type(uint128).max : uint128(bucketTotal);
        _lastBucketIndex[id] = currentBucket;
        _lastUpdateTs[id] = block.timestamp;

        emit VolumeRecorded(id, amount, currentBucket);
    }

    function getVolume24h(PoolId id) public view returns (uint256 total) {
        if (block.timestamp > _lastUpdateTs[id] + SECONDS_PER_DAY) return 0;
        uint128[24] storage b = _volumeBuckets[id];
        unchecked {
            // 24 uint128 buckets pack into 12 slots; the sum cannot overflow a
            // uint256 (24 * 2^128 << 2^256), so `unchecked` is safe here.
            for (uint256 i = 0; i < HOURS_PER_DAY; ++i) total += b[i];
        }
    }

    /// @notice Link a secondary pool's volume to a generation's primary pool.
    ///         Only the registry, which is what creates the pools, may do this.
    function linkVolume(PoolId primary, PoolId secondary) external {
        if (msg.sender != registry) revert OnlyRegistry();
        PoolId[] storage sib = _volumeSiblings[primary];
        // Idempotent: re-linking must not double-count the same pool forever.
        for (uint256 i; i < sib.length; ++i) {
            if (PoolId.unwrap(sib[i]) == PoolId.unwrap(secondary)) return;
        }
        sib.push(secondary);
        emit VolumeLinked(primary, secondary);
    }

    event VolumeLinked(PoolId indexed primary, PoolId indexed secondary);

    function isDead(PoolId id) external view returns (bool) {
        if (!trackedPools[id]) return false;
        //  A GENERATION's volume, not one pool's. Liquidity can be split across
        //  quotes, and read per-pool the primary could fall under the threshold
        //  purely because trading moved to the sibling — relaunching a
        //  generation that is perfectly alive.
        uint256 vol = getVolume24h(id);
        PoolId[] storage sib = _volumeSiblings[id];
        for (uint256 i; i < sib.length; ++i) vol += getVolume24h(sib[i]);
        IDeathChecker checker = deathChecker;
        if (address(checker) != address(0)) {
            // Delegate to the pluggable rule. A reverting/mis-behaving module must
            // never brick relaunch, so fall back to the built-in rule on failure.
            try checker.isDead(id, vol, deathThreshold) returns (bool dead) {
                return dead;
            } catch {
                return vol < deathThreshold;
            }
        }
        return vol < deathThreshold;
    }

    function _getCurrentBucket() private view returns (uint256) {
        return (block.timestamp / SECONDS_PER_HOUR) % HOURS_PER_DAY;
    }

    // -----------------------------------------------------------------------
    // Tax Lookup
    // -----------------------------------------------------------------------

    function _getHolderTaxRate(address holder) private view returns (uint256) {
        if (nftContract == address(0)) return defaultTaxBps;

        try INFTContract(nftContract).getHolderTaxRate(holder) returns (uint256 rate) {
            return rate;
        } catch {
            return defaultTaxBps;
        }
    }

    /// @notice Owner-tunable flat trading fee (bps), used when no tiered NFT
    ///         contract is wired. Capped at MAX_TAX_BPS (10%).
    function setDefaultTaxBps(uint256 _bps) external onlyOwner {
        require(_bps <= MAX_TAX_BPS, "tax too high");
        defaultTaxBps = _bps;
        emit DefaultTaxUpdated(_bps);
    }

    // -----------------------------------------------------------------------
    // SELF-FUNDING: Release ETH to registry for new pool seeding
    // -----------------------------------------------------------------------

    /**
     * @notice Release all accumulated ETH fees to the registry for seeding
     *         the next generation's V4 pool. Only callable by registry.
     *         This is how the protocol funds itself -- no external ETH needed.
     */
    function releaseRelaunchETH() external returns (uint256 amount) {
        if (msg.sender != registry) revert OnlyRegistry();

        amount = relaunchETH;
        if (amount == 0) revert NoETHToRelease();

        relaunchETH = 0;

        (bool ok, ) = registry.call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit RelaunchETHReleased(registry, amount);
    }


    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    function setDeathThreshold(uint256 _threshold) external onlyOwner {
        deathThreshold = _threshold;
        emit DeathThresholdUpdated(_threshold);
    }

    /// @notice Registry-only: force-close ALL dead perp positions during relaunch,
    ///         behind a transient flag so the engine's dying-pool settlement swaps
    ///         skip the fee + legacy buyback (no nesting) — WITHOUT permanently
    ///         exempting the engine, so perp swaps keep paying fees normally. Called
    ///         once at rebirth (best-effort — a revert can't brick relaunch since the
    ///         registry's call is try/catch'd on its side).
    function forceClosePerps() external {
        if (msg.sender != registry) revert OnlyRegistry();
        address eng = perpEngine;
        if (eng == address(0)) return;
        _inRelaunchClose = true;
        try IPerpForceClose(eng).forceCloseAllDead() {} catch {}
        _inRelaunchClose = false;
    }

    /// @notice Registry-only: record the LIVE generation's PoolKey. Pushed at every
    ///         summon/relaunch. The legacy buyback spends only into this key, and
    ///         `liveKey()` lets integrators read the canonical pool (audit C-01b).
    function setLiveKey(PoolKey calldata k) external {
        if (msg.sender != registry) revert OnlyRegistry();
        if (Currency.unwrap(k.currency0) != address(0)) revert ZeroAddress();
        _liveKey = k;
    }

    /// @notice The protocol's live pool key (the only pool the hook ever spends into).
    function liveKey() external view returns (PoolKey memory) {
        return _liveKey;
    }

    /// @notice Configure the legacy live buyback (owner/registry). `registry_` = the
    ///         Cauldron registry (0 = OFF), `bps` = share of the post-guild fee that
    ///         funds buybacks, `threshold` = buffer size that triggers a buy.
    function setLegacyBuyback(address registry_, uint256 bps, uint256 threshold) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        require(bps <= BPS, "bps");
        legacyRegistry = registry_;
        legacyBps = bps;
        if (threshold > 0) legacyThreshold = threshold;
    }

    /// @notice Swap the death-detection RULE by pointing at a new IDeathChecker
    ///         module (or address(0) to revert to the built-in volume rule).
    ///         Owner/registry-gated — on mainnet the owner is the emergency
    ///         multisig behind the timelock, so an upgrade is announced + delayed
    ///         and holders can watch it. This is how the death logic is upgraded
    ///         WITHOUT an upgradeable proxy on the money contracts.
    function setDeathChecker(address _checker) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        deathChecker = IDeathChecker(_checker);
        emit DeathCheckerSet(_checker);
    }

    /// @notice Swap the pluggable POLICY modules (surtax curve, gacha odds, mint
    ///         curve). Pass address(0) for any to keep the built-in rule. Same
    ///         trust model as setDeathChecker: owner/registry, and every module is
    ///         a clamped, fallback-guarded pure view that can never move funds.
    function setPolicies(address _surtax, address _odds, address _curve) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        surtaxPolicy = ISurtaxPolicy(_surtax);
        oddsPolicy = IOddsPolicy(_odds);
        curvePolicy = ICurvePolicy(_curve);
        emit PoliciesSet(_surtax, _odds, _curve);
    }

    /// @notice Swap the ETH fee-split STRUCTURE. address(0) = built-in split. Same
    ///         trust model as setPolicies (owner/registry, timelocked on mainnet);
    ///         the router only returns amounts — the hook does the sends and falls
    ///         back to the built-in split on any mismatch, so it can never misroute.
    function setFeeRouter(address _router) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        feeRouter = IFeeRouter(_router);
        emit FeeRouterSet(_router);
    }

    function setNftContract(address _nft) external onlyOwner {
        nftContract = _nft;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }

    /// @notice One-time wiring of the registry allowed to pull the relaunch ETH
    ///         reserve. IMMUTABLE after the first set: a mutable setter would let
    ///         the hook owner repoint `registry` to an address they control and
    ///         drain `relaunchETH` via releaseRelaunchETH() (audit F1). Set once
    ///         at deploy, then locked forever.
    function setRegistry(address _registry) external onlyOwner {
        if (registry != address(0)) revert RegistryAlreadySet();
        if (_registry == address(0)) revert ZeroAddress();
        registry = _registry;
    }

    /// @notice V2 UPGRADE, step 1 of 2: PROPOSE a successor registry. The hook keeps
    ///         serving the SAME pools (no PoolKey change → no LP teardown), only the
    ///         controller changes.
    ///
    ///  ARMED + DELAYED (audit M-01). `setRegistry` is one-shot and its comment
    ///  explains exactly why — a mutable setter lets the hook owner re-point
    ///  `registry` at an address they control and drain `relaunchETH` via
    ///  `releaseRelaunchETH()`. The old unconstrained `setRegistryOverride` handed
    ///  that power straight back. Now the swap must be announced on-chain and wait
    ///  out REGISTRY_SWAP_DELAY, so holders (and the guardian) can see it coming.
    function proposeRegistryOverride(address _registry) external onlyOwner {
        if (_registry == address(0)) revert ZeroAddress();
        pendingRegistry = _registry;
        registrySwapReadyAt = block.timestamp + REGISTRY_SWAP_DELAY;
        emit RegistryOverrideProposed(_registry, registrySwapReadyAt);
    }

    /// @notice Cancel a pending controller swap. Owner-only, no delay (it can only
    ///         ever ABORT a move, never make one).
    function cancelRegistryOverride() external onlyOwner {
        pendingRegistry = address(0);
        registrySwapReadyAt = 0;
        emit RegistryOverrideProposed(address(0), 0);
    }

    /// @notice V2 UPGRADE, step 2 of 2: execute the announced swap once the delay
    ///         has elapsed. The accumulated relaunch reserve is FLUSHED to the
    ///         OUTGOING registry first, so a controller swap can never capture ETH
    ///         the previous registry accrued. The successor must also be granted
    ///         setOpener + setTaxExempt (separate ops) for the green-candle path.
    function executeRegistryOverride() external onlyOwner {
        address next = pendingRegistry;
        if (next == address(0)) revert ZeroAddress();
        if (block.timestamp < registrySwapReadyAt) revert RegistryAlreadySet();
        if (relaunchETH > 0) {
            uint256 amount = relaunchETH;
            relaunchETH = 0;
            (bool ok, ) = registry.call{value: amount}("");
            require(ok, "ETH transfer failed");
            emit RelaunchETHReleased(registry, amount);
        }
        registry = next;
        pendingRegistry = address(0);
        registrySwapReadyAt = 0;
    }

    // NOTE: the owner-only `trackPool(PoolId)` was REMOVED (audit Z-05b). Pools are
    // adopted exclusively in `_afterInitialize`, which is what enforces "the registry
    // created it AND currency0 is native ETH" (audit C-01). `trackPool` let the owner
    // mark an arbitrary, attacker-priced pool as served, re-opening that gate by hand;
    // nothing in the protocol, the deploy scripts or the frontend ever called it. Its
    // removal also reclaims the EIP-170 headroom the wall-clock volume window needs.

    // -----------------------------------------------------------------------
    // Volume-minted NFTs
    // -----------------------------------------------------------------------

    /**
     * @notice Point the hook at the active brew's collection and bump the credit
     *         epoch so prior-generation credit can't mint the new collection.
     *         Registry-only (called on each summon / relaunch).
     */
    function setCollection(address _collection) external {
        if (msg.sender != registry) revert OnlyRegistry();
        collection = _collection;
        // Anchor the rising curve to whatever is already minted (0 for a fresh
        // collection, 1111 for the continued genesis MiFrens on iteration #2).
        mintBaseline = _collection == address(0)
            ? 0
            : ICauldronCollection(_collection).totalMinted();
        creditEpoch += 1;
        // Auto-wire the new collection's Liquidatoor badge minter to the perp
        // engine, so every summon/relaunch mints badges with no manual step.
        _wireLiquidator(_collection);
        emit CollectionSet(_collection, creditEpoch);
    }

    /// @dev Point `_collection`'s badge minter at the perp engine (best-effort —
    ///      a collection that doesn't grant the hook this right just no-ops, so
    ///      it can never brick a summon/relaunch).
    ///
    ///      The badge RENDERER is deliberately not set here. It is wired by
    ///      {CauldronFactory} at collection creation instead: this hook is
    ///      against the EIP-170 ceiling, and the factory has room to spare.
    function _wireLiquidator(address _collection) private {
        if (_collection == address(0) || perpEngine == address(0)) return;
        try ICollectionLiquidator(_collection).setLiquidatorMinter(perpEngine) {} catch {}
    }

    /// @notice Point the hook at the active brew's floor vault (registry-only).
    function setVault(address _vault) external {
        if (msg.sender != registry) revert OnlyRegistry();
        vault = _vault;
    }

    /// @notice Point the hook at the active brew's quest contract (registry/owner).
    function setQuest(address _quest) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        quest = _quest;
    }

    /// @notice Wire (or clear) the progressive {CauldronSeeder} the hook nudges
    ///         in-swap. One persistent seeder serves every generation. Zero =
    ///         in-swap streaming OFF (the seeder's permissionless poke() still
    ///         works). Registry/owner-set.
    function setSeeder(address _seeder) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        seeder = _seeder;
    }

    /// @notice Wire (or clear) the hook-native PerpEngine so swaps can auto-
    ///         liquidate hinted positions in afterSwap. Registry/owner-set; one
    ///         engine serves every generation, so this rarely changes.
    function setPerpEngine(address _engine) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        perpEngine = _engine;
        // Re-wire the CURRENT collection's badge minter to the (new) engine, so
        // wiring the engine after a summon retro-actively enables badges.
        _wireLiquidator(collection);
    }

    /// @notice Owner-tunable share of ETH fees routed to the NFT floor (bps).
    function setFloorBps(uint256 _bps) external onlyOwner {
        require(_bps <= BPS, "bps");
        floorBps = _bps;
    }

    /// @notice Point the hook at the genesis MiFrens dividend (registry/owner).
    ///         Persistent across brews — set once at genesis wiring.
    function setGuild(address _guild) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        guild = _guild;
        emit GuildSet(_guild, guildBps);
    }

    /// @notice Owner-tunable share of ETH fees streamed to the genesis dividend.
    ///         Capped so it stays a tribute, never a drain.
    /// @dev The cap is the DEPLOYED DEFAULT (audit I-02). It used to be 500 while
    ///      `guildBps` initialises to 1500, which made the setter a one-way ratchet:
    ///      once called, the guild share could never be returned to the value the
    ///      protocol actually shipped with.
    function setGuildBps(uint256 _bps) external onlyOwner {
        require(_bps <= 1500, "guild bps too high");
        guildBps = _bps;
    }

    /// @notice Registry pushes the winning proposal's author at each relaunch, so
    ///         the proposer slice follows the live iteration. Registry (or owner for
    ///         break-glass) only. Address(0) disables the slice for that iteration.
    function setActiveProposer(address who) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        activeProposer = who;
        emit ActiveProposerSet(who);
    }

    /// @notice Tune the proposer incentive (bps of the fee). Owner/timelock, capped.
    function setProposerBps(uint256 _bps) external onlyOwner {
        require(_bps <= MAX_PROPOSER_BPS, "proposer bps too high");
        proposerBps = _bps;
    }

    /// @notice Withdraw accrued proposer earnings (pull pattern). Anyone claims their
    ///         OWN balance; CEI + nonReentrant so the untrusted recipient can't
    ///         re-enter. Keeps the swap hot path free of external calls.
    function claimProposerFees() external nonReentrant returns (uint256 amount) {
        amount = proposerOwed[msg.sender];
        if (amount == 0) revert NoETHToRelease();
        proposerOwed[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "ETH transfer failed");
        emit ProposerFunded(msg.sender, 0); // 0 amount = a claim marker
    }

    /// @notice Owner-tunable rising-curve params.
    function setNftCurve(uint256 _base, uint256 _step) external onlyOwner {
        require(_base > 0, "zero");
        volumePerNFT = _base;
        nftPriceStep = _step;
    }
    /// @notice Toggle crediting untagged (direct-Uniswap/aggregator) buys to tx.origin.
    function setCreditUntaggedSwaps(bool on) external onlyOwner { creditUntaggedSwaps = on; }

    /// @notice Registry-set flat mint-out curve for the brew being wired: each of
    ///         the collection's NFTs forges at `_base` credit, so total mint-out
    ///         volume ≈ `_base * maxSupply` (a proposer-chosen target). Step 0
    ///         keeps the target exact. Called on each relaunch from the winning
    ///         proposal's `volumePerNFT` (0 = leave the current curve untouched).
    function setNftCurveFrom(uint256 _base) external {
        if (msg.sender != registry) revert OnlyRegistry();
        if (_base == 0) return;
        volumePerNFT = _base;
        nftPriceStep = 0;
    }

    /// @dev Credit cost of the crystal at 0-indexed collection position `k`.
    function nftPriceAt(uint256 k) public view returns (uint256) {
        ICurvePolicy pol = curvePolicy;
        if (address(pol) != address(0)) {
            try pol.priceAt(k, volumePerNFT, nftPriceStep) returns (uint256 c) {
                // A zero cost would let credit mint infinite NFTs — guard it.
                if (c > 0) return c;
            } catch { /* fall through */ }
        }
        return volumePerNFT + k * nftPriceStep;
    }

    /// @notice Player's spendable crystal credit for the current iteration.
    function creditOf(address player) external view returns (uint256) {
        return nftCredit[creditEpoch][player];
    }

    /// @dev Curve position for the NEXT crystal: minted + reserved (pending,
    ///      unresolved) crystals, offset by the brew's baseline. Counting the
    ///      reserved ones stops concurrent commits (before resolution) from all
    ///      pricing at the same slot (audit L1).
    function _curvePos() internal view returns (uint256) {
        uint256 minted = ICauldronCollection(collection).totalMinted();
        return minted + outstandingOf[collection] - mintBaseline;
    }

    /// @notice Crystals a player can open right now at today's curve prices.
    function crystalsReady(address player) public view returns (uint256 ready) {
        if (collection == address(0)) return 0;
        uint256 startPos = _curvePos();
        uint256 credit = nftCredit[creditEpoch][player];
        uint256 spent = 0;
        while (ready < MAX_MINTS_PER_CALL) {
            uint256 price = nftPriceAt(startPos + ready);
            if (spent + price > credit) break;
            spent += price;
            ready += 1;
        }
    }

    /// @notice Total credit to open the next `count` crystals at today's prices.
    function costOfNextCrystals(uint256 count) public view returns (uint256 cost) {
        if (collection == address(0)) return 0;
        uint256 startPos = _curvePos();
        for (uint256 i = 0; i < count;) { cost += nftPriceAt(startPos + i); unchecked { ++i; } }
    }

    /// @notice Win probability (bps) for a crystal opened by a play of `playWei`
    ///         ETH. Scales linearly to maxOddsBps at oddsFullVolumeWei, never
    ///         beyond — only the pity counter guarantees a creature.
    function oddsForPlay(uint256 playWei) public view returns (uint256 bps) {
        IOddsPolicy pol = oddsPolicy;
        if (address(pol) != address(0)) {
            try pol.oddsBps(playWei, maxOddsBps, oddsFullVolumeWei) returns (uint256 b) {
                // Clamp to the hard cap so a module can never guarantee a win.
                return b > ODDS_HARD_CAP_BPS ? ODDS_HARD_CAP_BPS : b;
            } catch { /* fall through */ }
        }
        if (oddsFullVolumeWei == 0) return maxOddsBps;
        bps = (playWei * maxOddsBps) / oddsFullVolumeWei;
        if (bps > maxOddsBps) bps = maxOddsBps;
    }

    /// @notice Unresolved crystals across all players.
    function outstandingTickets() external view returns (uint256) {
        return outstandingCrystals;
    }

    /// @notice Whether the current collection is fully minted out.
    function mintedOut() external view returns (bool) {
        if (collection == address(0)) return false;
        return ICauldronCollection(collection).totalMinted()
            >= ICauldronCollection(collection).maxSupply();
    }

    /// @notice Progress toward the player's next crystal.
    /// @return inCurrent credit banked toward the next (unaffordable) crystal
    /// @return threshold that crystal's price (current difficulty)
    /// @return ready whole crystals openable now
    function progress(address player)
        external
        view
        returns (uint256 inCurrent, uint256 threshold, uint256 ready)
    {
        if (collection == address(0)) return (0, nftPriceAt(0), 0);
        uint256 startPos = _curvePos();
        uint256 credit = nftCredit[creditEpoch][player];
        uint256 spent = 0;
        while (ready < MAX_MINTS_PER_CALL) {
            uint256 price = nftPriceAt(startPos + ready);
            if (spent + price > credit) break;
            spent += price;
            ready += 1;
        }
        threshold = nftPriceAt(startPos + ready);
        inCurrent = credit - spent;
    }

    /**
     * @notice Open up to `maxCount` crystals for `player`: spend the player's
     *         credit at today's curve prices and enqueue a lottery ticket per
     *         crystal. Nothing mints here — each ticket's creature-or-nothing
     *         outcome is rolled later by `resolveTickets` from its commit block's
     *         hash, at a win chance set by `playWei` (the ETH size of this play).
     *         Opener-gated so odds always use the router's honest play size.
     */
    function commitCrystals(address player, uint256 maxCount, uint256 playWei)
        external
        nonReentrant
        returns (uint256 n)
    {
        if (!isOpener[msg.sender]) revert NotOpener();
        return _commitCrystals(player, maxCount, playWei);
    }

    /// @dev Commit body — shared by the router path ({commitCrystals}) and the
    ///      NATIVE in-swap path ({nativeGachaStep}), so a raw Uniswap buy forges
    ///      crystals with no router. Returns 0 (never reverts) when sold out.
    function _commitCrystals(address player, uint256 maxCount, uint256 playWei)
        internal
        returns (uint256 n)
    {
        address col = collection;
        if (col == address(0)) return 0;
        uint256 minted = ICauldronCollection(col).totalMinted();
        uint256 max = ICauldronCollection(col).maxSupply();
        // Never enqueue more than remaining supply could mint if EVERY outstanding
        // crystal for this collection won, so resolution can't exceed maxSupply.
        uint256 reserved = outstandingOf[col];
        uint256 room = max > minted + reserved ? max - minted - reserved : 0;
        if (room == 0) return 0;
        if (maxCount > room) maxCount = room;

        // Price from minted + reserved so this commit follows any crystals already
        // pending resolution (audit L1) — concurrent commits don't share a slot.
        uint256 startPos = minted + reserved - mintBaseline;
        uint256 epoch = creditEpoch;
        uint256 credit = nftCredit[epoch][player];
        uint256 spent = 0;
        while (n < maxCount && n < MAX_MINTS_PER_CALL) {
            uint256 price = nftPriceAt(startPos + n);
            if (credit - spent < price) break;
            spent += price;
            unchecked { n++; }
        }
        if (n == 0) return 0;
        // `Batch.count` is uint16. `n` is bounded by MAX_MINTS_PER_CALL (30) today,
        // so this is unreachable — but the cast below is unchecked and would
        // silently TRUNCATE if that constant were ever raised (audit I-07).
        if (n > type(uint16).max) n = type(uint16).max;

        nftCredit[epoch][player] = credit - spent;
        committedOf[player] += n;
        pendingOf[player] += n;
        outstandingCrystals += n;
        outstandingOf[col] += n;

        uint16 odds = uint16(oddsForPlay(playWei));
        batches.push(Batch({
            player: player,
            collection: col,
            commitBlock: uint48(block.number),
            oddsBps: odds,
            count: uint16(n),
            resolved: 0
        }));
        emit CrystalsCommitted(player, n, odds);
    }

    /**
     * @notice Resolve up to `maxCount` pending crystals, in commit order. Each
     *         crystal's outcome is seeded by the blockhash of its commit block —
     *         unknown at commit, so it can't be foreseen, grinded, or re-rolled by
     *         reverting. Permissionless; stops (no revert) at a batch committed
     *         this block. A win mints the batch's collection (so tickets survive
     *         relaunch); a miss builds the pity counter. Sold-out crystals resolve
     *         as misses (their swap fee already lifted the floor).
     */
    function resolveTickets(uint256 maxCount)
        public
        nonReentrant
        returns (uint256 processed, uint256 won)
    {
        return _resolveTickets(maxCount);
    }

    /// @dev Resolve body — shared by the permissionless {resolveTickets} and the
    ///      in-swap native path. Mints via {CauldronCollection.mint} (plain `_mint`,
    ///      no receiver callback). Sold-out crystals resolve as misses; stops (no
    ///      revert) at a batch committed this block.
    function _resolveTickets(uint256 maxCount)
        internal
        returns (uint256 processed, uint256 won)
    {
        uint256 bi = batchCursor;
        uint256 end = batches.length;
        while (processed < maxCount && bi < end) {
            Batch storage b = batches[bi];
            if (block.number <= b.commitBlock) break; // seed not known yet
            bytes32 bh = blockhash(b.commitBlock);
            // EXPIRED SEED (audit M-04): substituting a DETERMINISTIC fallback made
            // the outcome computable from `commitBlock` + `bi`, both known at commit
            // time. A player who let their batch age past 256 blocks knew their roll
            // in advance and could choose whether to resolve at all — and because a
            // miss feeds the pity counter, selective resolution is a real lever on
            // future odds. RE-ANCHOR to a fresh future block instead: FIFO order and
            // every ticket are preserved, but the roll is always unknowable.
            if (bh == 0) {
                b.commitBlock = uint48(block.number);
                break; // FIFO: resume from here on the next call
            }

            address player = b.player;
            address col = b.collection;
            uint256 odds = b.oddsBps;
            uint256 minted = ICauldronCollection(col).totalMinted();
            uint256 max = ICauldronCollection(col).maxSupply();
            uint256 r = b.resolved;
            uint256 total = b.count;

            while (processed < maxCount && r < total) {
                uint256 roll = uint256(keccak256(abi.encodePacked(bh, player, bi, r))) % 10_000;
                bool forced = missStreak[player] >= pityThreshold;
                bool win = (forced || roll < odds) && minted < max;

                pendingOf[player] -= 1;
                outstandingCrystals -= 1;
                outstandingOf[col] -= 1;
                if (win) {
                    missStreak[player] = 0;
                    opened[player] += 1;
                    uint256 tokenId = ICauldronCollection(col).mint(player);
                    unchecked { minted++; won++; }
                    emit TicketWon(player, bi, tokenId);
                } else {
                    if (roll >= odds && minted < max) missStreak[player] += 1;
                    emit TicketLost(player, bi);
                }
                unchecked { r++; processed++; }
            }
            b.resolved = uint16(r);
            if (r == total) { unchecked { bi++; } } else break;
        }
        batchCursor = bi;
    }

    /// @notice NATIVE in-swap gacha for a direct (non-router) buy: commit the
    ///         buyer's fresh credit into crystals + resolve matured ones — so a
    ///         raw Uniswap/aggregator swap forges NFTs with NO router wrapper.
    ///         Self-call ONLY: afterSwap fires it gas-bounded + result-ignored, so
    ///         it can never revert or OOG the swap. `nonReentrant` shares the guard
    ///         with commit/resolve so the mint's validator callback can't re-enter.
    function nativeGachaStep(address player, uint256 playWei) external nonReentrant {
        if (msg.sender != address(this)) revert OnlySelf();
        _commitCrystals(player, NATIVE_COMMIT_MAX, playWei);
        _resolveTickets(NATIVE_RESOLVE_MAX);
    }

    // ── Gacha admin ─────────────────────────────────────────────────────────

    /// @notice Authorize the gacha router allowed to open crystals (registry/owner).
    function setOpener(address who, bool allowed) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        isOpener[who] = allowed;
        emit OpenerSet(who, allowed);
    }

    /// @notice Flag a buyer as fee-exempt (owner/registry). Only the deployer
    ///         snipe wallet should ever be set; it lets a launch buy skip the
    ///         base tax + anti-sniper surtax so the OG airdrop can be funded from
    ///         the market without diluting presalers.
    function setTaxExempt(address who, bool exempt) external {
        if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
        taxExempt[who] = exempt;
    }

    /// @dev Decode the hookData player (the gacha router tags every swap with the
    ///      real buyer) and report whether they're fee-exempt. Empty hookData →
    ///      not exempt (normal traders pay).
    /// @dev Exemption is honoured ONLY when the swap arrives from a trusted opener
    ///      (the gacha router), which honestly tags hookData with the real player.
    ///      A direct swapper controls hookData freely, so trusting it unconditionally
    ///      would let ANYONE dodge the hook fee by tagging an exempt address (audit
    ///      F-13). Gating on isOpener[sender] closes that: only the router's tagged
    ///      exempt player (the deployer's one-time launch buy) skips the fee.
    function _isExemptPlayer(address sender, bytes calldata hookData) private view returns (bool) {
        return taxExempt[_taxedPlayer(sender, hookData)] && isOpener[sender];
    }

    /// @dev The identity a swap is taxed as. Only a TRUSTED opener (the gacha
    ///      router, the registry) may name a different player via hookData — a
    ///      direct swapper controls hookData freely, so trusting it unconditionally
    ///      would let anyone claim someone else's tier or exemption (audit F-13).
    function _taxedPlayer(address sender, bytes calldata hookData) private view returns (address) {
        if (!isOpener[sender] || hookData.length < 32) return sender;
        address p = abi.decode(hookData, (address));
        return p == address(0) ? sender : p;
    }

    /// @notice Tune the odds curve: `fullVolumeWei` play size hits maxOddsBps;
    ///         `pity` forces a creature after that many consecutive misses.
    function setOddsParams(uint256 fullVolumeWei, uint256 pity) external onlyOwner {
        oddsFullVolumeWei = fullVolumeWei;
        pityThreshold = pity;
    }

    /// @notice Max win chance from bet size (bps), capped so size alone never
    ///         guarantees a creature — only pity does.
    function setMaxOdds(uint256 bps) external onlyOwner {
        require(bps <= ODDS_HARD_CAP_BPS, "odds cap");
        maxOddsBps = bps;
    }

    /// @notice Owner-tunable buy/sell credit weighting.
    function setWeights(uint256 buyBps, uint256 sellBps) external onlyOwner {
        require(buyBps <= MAX_WEIGHT_BPS && sellBps <= MAX_WEIGHT_BPS, "weight");
        buyWeightBps = buyBps;
        sellWeightBps = sellBps;
    }

    receive() external payable {}
}
