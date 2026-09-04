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
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {INFTContract} from "./interfaces/INFTContract.sol";
import {ICauldronCollection} from "./cauldron/ICauldron.sol";
import {IDeathChecker} from "./cauldron/IDeathChecker.sol";
import {ISurtaxPolicy, IOddsPolicy, ICurvePolicy} from "./cauldron/IPolicies.sol";

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

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------
    error ZeroAddress();
    error NothingToWithdraw();
    error OnlyRegistry();
    error NoETHToRelease();
    error NotOpener();
    error RegistryAlreadySet();

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_TAX_BPS = 1_000;       // hard ceiling: 10%
    uint256 public constant BLOCKS_PER_HOUR = 300;     // ~12s blocks
    uint256 public constant HOURS_PER_DAY = 24;
    uint256 public constant BLOCKS_PER_DAY = 7_200;    // 300 * 24

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

    // --- Volume tracking ---
    mapping(PoolId => uint256[24]) private _volumeBuckets;
    mapping(PoolId => uint256) private _lastBucketIndex;
    mapping(PoolId => uint256) private _lastUpdateBlock;
    mapping(PoolId => bool) public trackedPools;

    // --- Fee accounting ---
    /// @notice Accumulated ETH reserved for relaunches (self-funding)
    uint256 public relaunchETH;

    /// @notice Accumulated ERC20 fees per token (withdrawable by treasury)
    mapping(address => uint256) public accumulatedTokenFees;

    // --- Volume-minted NFT collection (per active brew) ---
    /// @notice The active brew's NFT collection. Swaps accrue mint credit; the
    ///         collection mints from that credit. Set by the registry on each
    ///         summon/relaunch so credit always maps to the live generation.
    address public collection;

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
    uint256 public mintBaseline;

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
    uint256 public batchCursor;         // index of the batch being resolved
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
    ///         Carved off the TOP, before the floor split. Small by design.
    uint256 public guildBps = 100; // 1%

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
    event CrystalsCommitted(address indexed player, uint256 count, uint256 oddsBps);
    event TicketWon(address indexed player, uint256 indexed ticketId, uint256 tokenId);
    event TicketLost(address indexed player, uint256 indexed ticketId);
    event OpenerSet(address indexed who, bool allowed);
    event FeeTaken(PoolId indexed poolId, address indexed swapper, uint256 fee, uint256 rateBps);
    event RelaunchETHReleased(address indexed to, uint256 amount);
    event TokenFeesWithdrawn(address indexed token, address indexed to, uint256 amount);
    event PoolTracked(PoolId indexed poolId);
    event DeathThresholdUpdated(uint256 newThreshold);
    event DefaultTaxUpdated(uint256 newBps);
    event DeathCheckerSet(address indexed checker);
    event PoliciesSet(address surtax, address odds, address curve);

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

    function _afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24
    ) internal override returns (bytes4) {
        PoolId id = key.toId();
        trackedPools[id] = true;
        _lastUpdateBlock[id] = block.number;
        poolInitBlock[id] = block.number; // anchor the anti-sniper window
        emit PoolTracked(id);
        return BaseHook.afterInitialize.selector;
    }

    /**
     * @dev afterSwap: record volume + take tiered fee via return delta.
     *
     *  ETH fees go to relaunchETH (self-funding the next generation).
     *  Token fees go to accumulatedTokenFees (withdrawable by treasury).
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        PoolId id = key.toId();

        // --- Volume tracking ---
        if (trackedPools[id]) {
            int128 amount0 = delta.amount0();
            uint256 absVolume = amount0 >= 0
                ? uint256(uint128(amount0))
                : uint256(uint128(-amount0));
            _recordVolume(id, absVolume);
            cumulativeVolume += absVolume;

            // Accrue crystal credit to the player carried in hookData (never
            // `sender`, which is the router). Empty hookData accrues nothing, so
            // aggregator swaps stay cheap and can never revert here. Buys are
            // weighted higher than sells (buyWeightBps/sellWeightBps).
            if (collection != address(0) && absVolume > 0 && hookData.length >= 32) {
                address player = abi.decode(hookData, (address));
                if (player != address(0)) {
                    // Buy = player acquires the token (ETH is the input, zeroForOne).
                    bool isBuy = params.zeroForOne;
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
                    // Forward to the quest contract (space for post-mintout
                    // engagement). Low-level + ignored result so it can never
                    // revert a swap.
                    if (quest != address(0)) {
                        quest.call(
                            abi.encodeWithSignature("onSwap(address,uint256)", player, weighted)
                        );
                    }
                }
            }
        }

        // --- Fee collection (ETH leg only) ---
        // The fee is ALWAYS taken in ETH so every swap funds the machine.
        //   - Buys  (ETH is the INPUT): charged in _beforeSwap.
        //   - Sells (ETH is the OUTPUT / unspecified leg): charged HERE.
        // We only act when the unspecified currency is ETH (currency0); the
        // buy case is already handled before the swap, so this never double-charges.
        bool exactInput = params.amountSpecified < 0;
        bool unspecifiedIsEth = exactInput ? (!params.zeroForOne) : (params.zeroForOne);
        if (!unspecifiedIsEth) {
            return (BaseHook.afterSwap.selector, 0);
        }
        // Fee-exempt buyer (deployer snipe) → no sell-leg fee either.
        if (_isExemptPlayer(sender, hookData)) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // ETH sits on the currency0 leg (the unspecified currency here).
        int128 ethDelta = delta.amount0();
        uint256 ethAmount = ethDelta >= 0
            ? uint256(uint128(ethDelta))
            : uint256(uint128(-ethDelta));

        uint256 fee = _takeEthFee(key, sender, ethAmount);
        return (BaseHook.afterSwap.selector, int128(uint128(fee)));
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
        // Act only on exact-input buys (ETH in). currency0 is always ETH.
        bool exactInput = params.amountSpecified < 0;
        bool inputIsEth = params.zeroForOne && Currency.unwrap(key.currency0) == address(0);
        if (!exactInput || !inputIsEth) {
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
        uint256 fee = _takeEthFee(key, sender, amountIn);
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
    function _routeEthFee(uint256 feeAmount) private {
        uint256 remaining = feeAmount;

        // 1. Genesis MiFrens dividend.
        if (guild != address(0) && guildBps > 0) {
            uint256 toGuild = (feeAmount * guildBps) / BPS;
            if (toGuild > 0) {
                (bool okG, ) = guild.call{value: toGuild}("");
                if (okG) {
                    remaining -= toGuild;
                    emit GuildFunded(guild, toGuild);
                }
            }
        }

        // 2. Floor vault takes floorBps of the remainder; rest -> relaunch.
        uint256 toFloor = 0;
        if (vault != address(0) && floorBps > 0) {
            toFloor = (remaining * floorBps) / BPS;
            if (toFloor > 0) {
                (bool ok, ) = vault.call{value: toFloor}("");
                if (ok) emit FloorFunded(vault, toFloor);
                else toFloor = 0; // vault rejected -> keep for relaunch
            }
        }
        relaunchETH += remaining - toFloor;
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
        // Unpredictable jitter, also fading with the window, so late-window blocks
        // can still randomly spike — a sniper can't pick a guaranteed-cheap block.
        uint256 rnd = uint256(
            keccak256(abi.encodePacked(block.prevrandao, PoolId.unwrap(id), block.number))
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
    function _takeEthFee(PoolKey calldata key, address sender, uint256 ethAmount)
        private
        returns (uint256 total)
    {
        PoolId id = key.toId();
        uint256 taxRate = _getHolderTaxRate(sender);
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

        poolManager.take(key.currency0, address(this), total);
        if (baseFee > 0) _routeEthFee(baseFee);
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
        uint256 lastBlock = _lastUpdateBlock[id];

        if (block.number > lastBlock + BLOCKS_PER_DAY) {
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

        _volumeBuckets[id][currentBucket] += amount;
        _lastBucketIndex[id] = currentBucket;
        _lastUpdateBlock[id] = block.number;

        emit VolumeRecorded(id, amount, currentBucket);
    }

    function getVolume24h(PoolId id) public view returns (uint256 total) {
        if (block.number > _lastUpdateBlock[id] + BLOCKS_PER_DAY) return 0;
        for (uint256 i = 0; i < HOURS_PER_DAY; i++) {
            total += _volumeBuckets[id][i];
        }
    }

    function isDead(PoolId id) external view returns (bool) {
        if (!trackedPools[id]) return false;
        uint256 vol = getVolume24h(id);
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
        return (block.number / BLOCKS_PER_HOUR) % HOURS_PER_DAY;
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
    // Treasury: Withdraw accumulated ERC20 fees
    // -----------------------------------------------------------------------

    function withdrawTokenFees(address token) external {
        uint256 amount = accumulatedTokenFees[token];
        if (amount == 0) revert NothingToWithdraw();

        accumulatedTokenFees[token] = 0;
        IERC20(token).transfer(treasury, amount);

        emit TokenFeesWithdrawn(token, treasury, amount);
    }

    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    function setDeathThreshold(uint256 _threshold) external onlyOwner {
        deathThreshold = _threshold;
        emit DeathThresholdUpdated(_threshold);
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

    function trackPool(PoolId id) external onlyOwner {
        trackedPools[id] = true;
        _lastUpdateBlock[id] = block.number;
        emit PoolTracked(id);
    }

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
        emit CollectionSet(_collection, creditEpoch);
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
    ///         Capped low (<= 5%) so it stays a tribute, never a drain.
    function setGuildBps(uint256 _bps) external onlyOwner {
        require(_bps <= 500, "guild bps too high");
        guildBps = _bps;
    }

    /// @notice Owner-tunable rising-curve params.
    function setNftCurve(uint256 _base, uint256 _step) external onlyOwner {
        require(_base > 0, "zero");
        volumePerNFT = _base;
        nftPriceStep = _step;
    }

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
        for (uint256 i = 0; i < count; i++) cost += nftPriceAt(startPos + i);
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
        uint256 bi = batchCursor;
        uint256 end = batches.length;
        while (processed < maxCount && bi < end) {
            Batch storage b = batches[bi];
            if (block.number <= b.commitBlock) break; // seed not known yet
            bytes32 bh = blockhash(b.commitBlock);
            if (bh == 0) bh = keccak256(abi.encodePacked("CAULDRON_TICKET_FALLBACK", b.commitBlock, bi));

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
        if (!isOpener[sender]) return false;
        if (hookData.length < 32) return false;
        return taxExempt[abi.decode(hookData, (address))];
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
