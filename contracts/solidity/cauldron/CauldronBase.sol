// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {ICauldronGovernor, MetadataMode} from "./ICauldron.sol";

// ---------------------------------------------------------------------------
// Shared interfaces — declared here (not in CauldronRegistry) so BOTH the
// registry AND the delegatecall facet (RedemptionExt) see identical types.
// ---------------------------------------------------------------------------

interface ICauldronFactory {
    struct Config {
        string name; string symbol; address hook; address registry;
        uint256 maxSupply; MetadataMode mode; string baseURI; address renderer;
        address royaltyReceiver; uint96 royaltyBps;
    }
    function deployBrew(Config calldata c) external returns (address collection, address vault);
    function deployVault(address collection, address registry, uint256 floorOffset) external returns (address vault);
}

/// @notice The canonical MiFrens collection surface the registry drives when
///         iteration #2 CONTINUES it (keeps minting the rest of the art).
interface IMiFrensContinuable {
    function setMinter(address minter) external;
    function setVault(address vault) external;
    function totalMinted() external view returns (uint256);
    /// @notice Registry-gated transfer (no approval needed) used to move a recycled
    ///         fren into the treasury and back out to a buyer. The registry checks
    ///         ownership before calling.
    function custodyTransfer(address from, address to, uint256 tokenId) external;
    /// @notice Whether a genesis fren has ever moved (recycled/transferred) — used
    ///         to gate the paid re-enchant (original OGs are grandfathered free).
    function everMoved(uint256 tokenId) external view returns (bool);
}

interface IVaultClose {
    function close() external returns (uint256 swept);
}

/// @notice The perp engine's relaunch housekeeping — force-close all dead positions
///         (oldest-first, deterministic) then re-arm the token side on the new gen.
interface IPerpSync {
    function syncGeneration() external;
}

interface ICollectionLedger {
    function totalEntitled() external view returns (uint256);
}

/// @notice Minimal V4 PositionManager interface — only the calls the registry
///         makes. Defined locally because the full v4-periphery IPositionManager
///         extends IPermit2Forwarder, which drags permit2's =0.8.17 solc pin
///         into our ^0.8.26 compilation unit.
interface IPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}

/**
 * @title CauldronBase
 * @notice SHARED STORAGE + type surface for the Cauldron registry and its
 *         delegatecall facet(s). This is the crux of the EIP-170 facet split:
 *         {CauldronRegistry} and {RedemptionExt} BOTH derive from this base and
 *         add NO new state variables, so their compiled storage layouts are
 *         IDENTICAL BY CONSTRUCTION — a hard requirement for the delegatecall
 *         pair (the facet runs its code against the registry's storage, so the
 *         two must agree slot-for-slot). Verify with:
 *
 *           forge inspect CauldronRegistry storageLayout
 *           forge inspect RedemptionExt   storageLayout   # must be byte-identical
 *
 *  ⚠️ IMMUTABLE GOTCHA: `poolManager` / `positionManager` / `hook` were
 *     `immutable` in the monolith. Immutables resolve against the EXECUTING
 *     contract's code, so under delegatecall the facet would read them as ZERO.
 *     They are STORAGE vars here; the registry constructor writes them.
 *
 *  This is a NEW deploy (not a proxy upgrade): the layout need NOT match the
 *  pre-refactor registry — it only needs registry-layout == facet-layout. The
 *  three former immutables + `redemptionExt` are APPENDED after the original
 *  vars, so slots 0..40 still match `docs/registry-storage-baseline.txt`.
 */
abstract contract CauldronBase is Ownable, ReentrancyGuard {
    // -----------------------------------------------------------------------
    // Errors (shared)
    // -----------------------------------------------------------------------
    /// @dev Native ETH cannot be removed from the quote allowlist: it is the
    ///      fallback every generation can launch against, and the sink a failed
    ///      non-ETH payout rolls into.
    error NativeQuoteRequired();
    error AlreadySummoned();
    error NotSummoned();
    error TokenStillAlive();
    error NoBalance();
    error UnknownGeneration();
    error CannotClaimCurrentGen();
    error InsufficientETH();
    error NoLiquidityToSeed();
    error TooYoung();
    error NoProposal();
    error NotAdmin();
    error Timelocked();
    error EthSend();
    error BadConfig();
    error TooHigh();
    error NotOwnerOf();
    error Fee();
    error RedemptionPaused();
    error NotPoolManager();
    error VestingEnforced();
    error NotConfigured();

    // -----------------------------------------------------------------------
    // Events (shared — emitted from redemption paths, incl. the delegatecall
    // facet; declared here so BOTH the registry and facet ABIs carry them and
    // the indexer decodes them regardless of which contract emits).
    // -----------------------------------------------------------------------
    /// @notice A genesis fren was RECYCLED: the holder redeemed `amount` of the
    ///         live token from the reserve and the NFT moved to the treasury.
    event FrenRedeemed(
        uint256 indexed mifrenTokenId, address indexed holder, uint256 amount, uint256 indexed generation
    );
    /// @notice A treasury-held fren was BOUGHT for `paid` tokens (2× floor).
    event FrenBought(uint256 indexed mifrenTokenId, address indexed buyer, uint256 paid, uint256 indexed generation);
    /// @notice The genesis reserve grew (buyback or re-enchant fee) → floor ratchet.
    event FloorGrew(uint256 addedToReserve, uint256 newReserve, uint256 newFloorPerFren);
    event LegacyMaterialized(uint256 indexed gen, uint256 added);

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------
    uint256 public constant TOTAL_SUPPLY = 777_000_000e18;         // 777M tokens
    uint24  public constant POOL_FEE = 0;                          // 0% LP fee
    int24   public constant TICK_SPACING = 200;                    // tick granularity
    int24 internal constant RESERVE_CEILING_OFFSET = 42400;        // ≈ 69x (default)
    uint256 public constant GEN1_ACTIVE_TOKENS = (TOTAL_SUPPLY * 4) / 5; // 80%
    /// @notice Fee to opt into auto-migration for a non-fren wallet.
    uint256 public constant AUTO_MIGRATE_FEE = 0.069 ether;
    /// @notice Hard ceiling on a brew's NFT collection size. Must stay well below the
    ///         collections' LIQUIDATOR_ID_BASE (1e6), at or above which the
    ///         collection constructor reverts — and a revert inside `relaunch()`
    ///         rolls back `markConsumed`, freezing the machine. (Audit C-02.)
    uint256 public constant MAX_NFT_SUPPLY = 100_000;

    // -----------------------------------------------------------------------
    // STORAGE — declaration order below is LOAD-BEARING. It reproduces
    // `docs/registry-storage-baseline.txt` slots 0..40 exactly; anything added
    // must be APPENDED (never inserted) so the registry/facet layouts stay equal
    // and the baseline diff stays clean. Do not reorder.
    // -----------------------------------------------------------------------

    // ── PER-ITERATION reserve ceiling (tunable, like token name/symbol) ────── (slot 0)
    int24 internal nextReserveCeilingOffset = RESERVE_CEILING_OFFSET;

    bool public summoned;
    /// @dev Armed only for the duration of a relaunch green-candle buy. INTERNAL
    ///      (not private) so the registry can arm/disarm it around the seed buy.
    bool internal _seedBuyUnlocked;
    uint256 public currentGeneration;
    address public currentToken;

    /// @notice generation -> token address
    mapping(uint256 => address) public generationToken;
    /// @notice Who authored the winning proposal for each iteration.
    mapping(uint256 => address) public generationProposer;
    /// @notice V2 BRANCH SEAM (empty in V1). The parent generation each iteration
    ///         descended from.
    mapping(uint256 => uint256) public generationParent;
    /// @notice generation -> V4 pool ID
    mapping(uint256 => PoolId) public generationPoolId;
    /// @notice generation -> PoolKey (stored for LP removal)
    mapping(uint256 => PoolKey) public generationPoolKey;
    /// @notice generation -> ACTIVE position NFT token ID (full-range, sets price)
    mapping(uint256 => uint256) public generationPositionId;
    /// @notice generation -> RESERVE position NFT id (out-of-range single-sided
    ///         token; the migration + genesis supply lives here, claimed 1:1).
    mapping(uint256 => uint256) public generationReservePositionId;
    /// @notice generation -> reserve tick band (needed to size exact-N claims).
    mapping(uint256 => int24) public reserveTickLower;
    mapping(uint256 => int24) public reserveTickUpper;
    /// @notice Unclaimed genesis bonus carried forward — re-reserved every gen.
    uint256 public genesisReserveOutstanding;

    /// @notice generation + holder -> claimed
    mapping(uint256 => mapping(address => bool)) public claimed;
    /// @notice generation -> NFT collection minted from that brew's volume
    mapping(uint256 => address) public generationCollection;
    /// @notice generation -> that brew's NFT floor vault
    mapping(uint256 => address) public generationVault;

    /// @notice The legacy-floor cap table (see CollectionLedger). Zero = off.
    ICollectionLedger public collectionLedger;
    /// @notice OG share of iteration-#2 live buybacks, folded into
    ///         `genesisReserveOutstanding` at the next relaunch.
    uint256 internal genesisPending;

    /// @notice Factory that deploys each brew's collection + vault.
    ICauldronFactory public factory;
    /// @notice Proposal governor. When set + populated, relaunch launches the winner.
    ICauldronGovernor public governor;

    /// @notice Per-brew NFT collection supply cap.
    uint256 public nftMaxSupply = 3333;

    /// @notice EIP-2981 royalty receiver for EVERY brew's collection.
    address public royaltyDividend;
    /// @notice Secondary-sale royalty (bps). Default 5%.
    uint96 public royaltyBps = 500;

    /// @notice Genesis brew NFT metadata (iteration #1), owner-set before ignition.
    MetadataMode public genesisMode;
    string public genesisBaseURI;
    address public genesisRenderer;

    /// @notice The MiFrens ERC721 whose holders may claim the genesis bonus.
    address public mifrens;
    /// @notice Bonus share of gen-1 supply reserved for MiFrens holders (bps).
    uint256 public genesisBonusBps;
    /// @notice Number of equal shares the bonus pool is split into (MiFrens supply).
    uint256 public genesisShares;
    /// @notice The INITIAL per-fren reserve share, fixed at summon.
    uint256 public genesisSharePerFren;

    /// @notice Re-enchant fee multiple (bps of the LIVE floor). Default 15000 = 1.5×.
    uint256 public enchantFeeMultBps = 15_000;

    /// @notice PROTECTION circuit-breaker for the redemption path. Default false.
    bool public redemptionPaused;
    /// @notice Guardian that can VETO (cancel) an armed emergency action.
    address public guardian;

    /// @notice V2 UPGRADE TARGET — the next-generation controller.
    address public successor;
    /// @notice ANTI-DUMP VESTING GATE. Non-zero routes instant migration through
    ///         the {MigrationVesting} escrow. Zero = feature off.
    address public claimGate;

    /// @notice OG-holder airdrop reserve → sent off-LP to `airdropWallet` at summon.
    address public airdropWallet;
    uint256 public airdropReserve;

    /// @notice OWNER-PROVIDED prime-buy ETH (personal, kept separate from the seed).
    uint256 public primeBuyEth;
    /// @notice Who may top up / reclaim the prime buy.
    address public primeFunder;

    /// @notice When an armed emergency action becomes executable (0 = not armed).
    uint256 public emergencyReadyAt;
    /// @notice Timestamp the current generation was summoned/reborn.
    uint256 public lastSummonAt;
    /// @notice Minimum seconds a brew must live before it can be relaunched.
    uint256 public minLifetime = 1 hours;

    /// @notice Wallets that opted into hands-off, keeper-executed migration. (slot 40)
    mapping(address => bool) public autoMigrate;

    // ── APPENDED (post-baseline) — former immutables promoted to storage so the
    //    RedemptionExt facet reads them correctly under delegatecall, plus the
    //    facet pointer. Present in BOTH children → layouts stay identical. ──────
    IPoolManager public poolManager;         // slot 41 (was immutable)
    IPositionManager public positionManager; // slot 42 (was immutable)
    CauldronHook public hook;                // slot 43 (was immutable)
    /// @notice The RedemptionExt facet the registry delegatecalls the OG-redemption
    ///         ops into. Set once at deploy via {CauldronRegistry.setRedemptionExt}.
    address public redemptionExt;            // slot 44

    // ── PROGRESSIVE SEED (opt-in; default off → the atomic green-candle path is
    //    unchanged). Carried in the base so the registry/facet layouts stay equal
    //    even though only the registry uses them. See {CauldronSeeder}. ──────────
    /// @notice The persistent progressive seeder (0 = atomic seed, feature off).
    address public seeder;                    // slot 45
    /// @notice Launch window (seconds) the NEXT summon/relaunch streams the active
    ///         tranche over. 0 = atomic (one-shot seed). Progressive fires only when
    ///         BOTH `seeder != 0` AND `nextSeedWindow > 0`.
    uint64 public nextSeedWindow;             // slot 46

    /// @notice IGNITION ROLE (audit Z-06). The one address, besides the owner, that
    ///         may fire the one-time genesis {CauldronRegistry.summon}.
    ///
    ///  The deploy script used to hand registry OWNERSHIP to the presale contract so
    ///  that `finalize()` could summon. But `MiFrensGenesis` calls exactly one registry
    ///  function and exposes no forwarder and no fallback, so that handoff BURNED every
    ///  `onlyOwner` setter — `setGovernor`, `setFactory`, `setSeeder`, `setSeedWindow`,
    ///  `setReserveCeiling`, `setCollectionLedger`, ... — permanently, contradicting
    ///  their own NatSpec ("Owner = timelock, chosen per iteration"). A spammed governor
    ///  or a broken factory, both called from inside `relaunch()`, could never be
    ///  replaced. Splitting ignition into its own role lets ownership stay with the
    ///  governance timelock while the presale keeps exactly the right it needs.
    address public igniter;                   // slot 47

    /// @notice Quote assets an iteration may pair against. `address(0)` (native
    ///         ETH) is allowed from construction, so this starts as today's
    ///         behaviour and stays that way until governance widens it.
    ///
    ///  Curated by the OWNER (the governance timelock) and never by a proposer.
    ///  A proposer curating their own set is the obvious capture vector: they
    ///  add a token they control and drain the pool into it. The split is
    ///  deliberate — the treasury decides what is SAFE, governance decides what
    ///  is STRATEGIC.
    ///
    ///  Appended at the end: this contract is the shared storage layout for the
    ///  registry AND its delegatecall facet, so the two must stay byte-identical
    ///  (asserted by FacetLayoutInvariant). Inserting anywhere above would shift
    ///  every following slot and silently corrupt the facet's view of state.
    mapping(address => bool) public allowedQuote;   // slot 48

    // -----------------------------------------------------------------------
    // Shared views / guards (used by BOTH the registry and the facet)
    // -----------------------------------------------------------------------

    /// @notice LIVE redemption value per genesis fren = reserve backing / genesis
    ///         count. Ratchets up with buybacks + re-enchant fees.
    function floorPerFren() public view returns (uint256) {
        uint256 shares = genesisShares;
        if (shares == 0) return 0;
        return genesisReserveOutstanding / shares;
    }

    /// @dev THE EXIT GUARANTEE. Redemptions are blocked ONLY by the fast circuit-
    ///      breaker AND only while NO custody action is armed — the instant an
    ///      emergency is armed the exit is forced OPEN so holders can always leave
    ///      at floor BEFORE anything moves.
    function _redeemBlocked() internal view returns (bool) {
        return redemptionPaused && emergencyReadyAt == 0;
    }

    constructor() Ownable(msg.sender) {}
}
