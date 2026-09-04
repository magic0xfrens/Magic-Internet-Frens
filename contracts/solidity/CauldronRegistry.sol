// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

import {CauldronToken} from "./CauldronToken.sol";
import {CauldronHook} from "./CauldronHook.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode, LaunchLib} from "./cauldron/ICauldron.sol";
import {PoolOps, IPositionManagerOps, SeedResult} from "./cauldron/PoolOps.sol";

interface ICauldronFactory {
    struct Config {
        string name; string symbol; address hook; address registry;
        uint256 maxSupply; MetadataMode mode; string baseURI; address renderer;
        address royaltyReceiver; uint96 royaltyBps;
    }
    function deployBrew(Config calldata c) external returns (address collection, address vault);
    function deployVault(address collection, address registry) external returns (address vault);
}

/// @notice The canonical MiFrens collection surface the registry drives when
///         iteration #2 CONTINUES it (keeps minting the rest of the art).
interface IMiFrensContinuable {
    function setMinter(address minter) external;
    function setVault(address vault) external;
    function totalMinted() external view returns (uint256);
}

interface IVaultClose {
    function close() external returns (uint256 swept);
}

/// @notice Minimal V4 PositionManager interface — only the calls the registry
///         makes. Defined locally because the full v4-periphery IPositionManager
///         extends IPermit2Forwarder, which drags permit2's =0.8.17 solc pin
///         into our ^0.8.26 compilation unit. (Permit2 approvals now live in
///         the PoolOps library.)
interface IPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}

/**
 * @title CauldronRegistry
 * @notice Fully autonomous orchestrator for the eternal Cauldron token lifecycle.
 *
 *  ZERO EXTERNAL DEPENDENCIES AFTER GENESIS:
 *
 *    `summon()` -- Genesis (owner sends initial ETH, one-time)
 *    `relaunch()` -- Permissionless rebirth: NO params, NO ETH required.
 *                    Recovers ETH from dead pool LP + hook fee reserve.
 *                    Auto-derives name/symbol from cycling creature list.
 *                    Mints nothing extra — migration is conserved 1:1.
 *    `claimTokens(gen)` -- Old holders claim 1:1 on current generation.
 *
 *  Self-funding flow:
 *    Swap fees (ETH) accumulate in CauldronHook.relaunchETH
 *    + Dead pool LP removal recovers ETH from PoolManager
 *    = Total ETH seeds the next generation's V4 pool
 *
 *  The 6 Eternal Creatures (cycling):
 *    Gen 1: Magic Internet Token (MIT)     Gen 4: Infernal Beast (BEAST)
 *    Gen 2: Ethereal Spirit (SPIRIT)       Gen 5: Astral Entity (ASTRAL)
 *    Gen 3: Shadow Wraith (WRAITH)         Gen 6: Storm Elemental (STORM)
 *    Gen 7+: Cycle repeats
 */
contract CauldronRegistry is Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------
    error AlreadySummoned();
    error NotSummoned();
    error TokenStillAlive();
    error AlreadyClaimed();
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

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    event CauldronSummoned(
        uint256 indexed generation,
        address indexed token,
        PoolId poolId,
        string name,
        string symbol
    );

    event CauldronDied(
        uint256 indexed generation,
        address indexed token,
        uint256 deathBlock
    );

    event CauldronReborn(
        uint256 indexed generation,
        address indexed token,
        PoolId poolId,
        string name,
        string symbol
    );

    event HolderClaimed(
        uint256 indexed generation,
        address indexed holder,
        uint256 amount
    );

    event LiquidityRecovered(
        uint256 indexed generation,
        uint256 ethAmount
    );


    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------
    uint256 public constant TOTAL_SUPPLY = 777_000_000e18;         // 777M tokens
    // Relaunch mints NO caller bounty — nothing extra is created, so migration
    // stays perfectly conserved 1:1 and holders are never diluted by a rebirth.
    // No Uniswap LP fee: the LP is protocol-owned (this registry) and recycled
    // at relaunch, so an LP fee would just be a redundant tax on top of the
    // hook fee. All value capture happens via the hook (routable to guild /
    // floor / relaunch). Traders pay only the hook fee.
    uint24  public constant POOL_FEE = 0;                          // 0% LP fee
    int24   public constant TICK_SPACING = 200;                    // tick granularity

    /// @notice The migration/genesis RESERVE is held as an out-of-range,
    ///         single-sided TOKEN liquidity position instead of a wallet balance,
    ///         so 100% of supply reads as LP (no whale-look FUD) yet only ever
    ///         leaves 1:1 against a burn/claim. ETH is currency0, so the pool
    ///         price is token-per-ETH; a token appreciating 69x means the pool
    ///         price FALLS 69x → the reserve's tick range sits BELOW the launch
    ///         tick by this offset. Pure token1 while currentTick > reserveTickUpper.
    ///         ln(69)/ln(1.0001) ≈ 42343, aligned up to TICK_SPACING (200) = 42400.
    int24 public constant RESERVE_CEILING_OFFSET = 42400;          // ≈ 69x

    /// @notice The ACTIVE tradeable band is a FIXED 10% of supply every
    ///         generation (constant depth + consistent launch behaviour); the
    ///         other 90% is the out-of-range reserve, claimed 1:1 by burn.
    uint256 public constant GEN1_ACTIVE_TOKENS = TOTAL_SUPPLY / 10;

    // -----------------------------------------------------------------------
    // Immutables
    // -----------------------------------------------------------------------
    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    CauldronHook public immutable hook;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    bool public summoned;
    uint256 public currentGeneration;
    address public currentToken;

    /// @notice generation -> token address
    mapping(uint256 => address) public generationToken;

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
    /// @notice Unclaimed genesis bonus carried forward — re-reserved every gen so
    ///         an OG can always claim it (genesis persists across iterations).
    uint256 public genesisReserveOutstanding;

    /// @notice generation + holder -> claimed
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// @notice generation -> NFT collection minted from that brew's volume
    mapping(uint256 => address) public generationCollection;

    /// @notice generation -> that brew's NFT floor vault
    mapping(uint256 => address) public generationVault;

    /// @notice Factory that deploys each brew's collection + vault (off-registry
    ///         bytecode to stay under the 24KB limit).
    ICauldronFactory public factory;

    /// @notice Proposal governor. When set + populated, relaunch launches the
    ///         winning proposal (name, ticker, metadata). Else it cycles creatures.
    ICauldronGovernor public governor;

    /// @notice Per-brew NFT collection supply cap.
    uint256 public nftMaxSupply = 3333;

    /// @notice EIP-2981 royalty receiver for EVERY brew's collection — the genesis
    ///         MiFrens dividend. Secondary-sale royalties from all collections flow
    ///         here, so the OG 1111 earn from all protocol NFT trades too.
    address public royaltyDividend;
    /// @notice Secondary-sale royalty (bps) set on each collection. Default 5%.
    uint96 public royaltyBps = 500;

    /// @notice Genesis brew NFT metadata (iteration #1), owner-set before ignition.
    MetadataMode public genesisMode;
    string public genesisBaseURI;
    address public genesisRenderer;

    // --- Genesis bonus: reward the founding MiFrens guild with a slice of the
    //     first iteration's token supply. Default 0 (off) so it's opt-in. ---
    /// @notice The MiFrens ERC721 whose holders may claim the genesis bonus.
    address public mifrens;
    /// @notice Bonus share of gen-1 supply reserved for MiFrens holders (bps).
    uint256 public genesisBonusBps;
    /// @notice Number of equal shares the bonus pool is split into (MiFrens supply).
    uint256 public genesisShares;
    /// @notice Tokens per MiFren, fixed at summon.
    uint256 public genesisSharePerFren;
    /// @notice mifrenTokenId => claimed the genesis bonus.
    mapping(uint256 => bool) public genesisClaimed;

    /// @notice OG-holder airdrop reserve: a fixed amount of iteration-1 tokens
    ///         sent to `airdropWallet` at summon (for off-LP distribution to the
    ///         OG $GNOME holders who migrated from other chains). Owner-set
    ///         pre-summon; carved from the LP seed just like the genesis bonus.
    address public airdropWallet;
    uint256 public airdropReserve;

    /// @notice Break-glass admin that can recover LP + sweep the registry. Set at
    ///         deploy (immutable) — pass a Gnosis Safe multisig on mainnet, the
    ///         deployer EOA on testnet. Kept separate from `owner` on purpose.
    address public immutable emergencyAdmin;
    /// @notice Timelock on every emergency action. IMMUTABLE — set at deploy so
    ///         the admin can't lower it to rug instantly. 0 = instant (testnet);
    ///         e.g. 7 days on mainnet, so a withdrawal must be armed on-chain and
    ///         wait the delay — holders can watch it coming and exit first.
    uint256 public immutable emergencyDelay;
    /// @notice When an armed emergency action becomes executable (0 = not armed).
    ///         One arming authorises one action, then it's consumed.
    uint256 public emergencyReadyAt;

    /// @notice Timestamp the current generation was summoned/reborn. Relaunch is
    ///         blocked until `minLifetime` has elapsed, so a fresh pool (which
    ///         reads "dead" at 0 volume) can't be killed the moment it launches.
    uint256 public lastSummonAt;
    /// @notice Minimum seconds a brew must live before it can be relaunched.
    ///         Adjustable by the break-glass admin during the test phase.
    uint256 public minLifetime = 1 hours;

    event CollectionDeployed(uint256 indexed generation, address collection, MetadataMode mode);
    event GenesisBonusReserved(uint256 pool, uint256 perFren);
    event GenesisBonusClaimed(uint256 indexed mifrenTokenId, address indexed holder, uint256 amount);
    event EmergencyWithdraw(uint256 indexed gen, address indexed to, uint256 eth, uint256 tokens);
    event EmergencyArmed(uint256 readyAt);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------
    constructor(
        address _poolManager,
        address _positionManager,
        address _hook,
        address _emergencyAdmin,
        uint256 _emergencyDelay
    ) Ownable(msg.sender) {
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager);
        hook = CauldronHook(payable(_hook));
        // Testnet: deployer EOA + delay 0. Mainnet: a Safe multisig + e.g. 7 days.
        emergencyAdmin = _emergencyAdmin == address(0) ? msg.sender : _emergencyAdmin;
        emergencyDelay = _emergencyDelay;
    }

    modifier onlyEmergency() {
        if (msg.sender != emergencyAdmin) revert NotAdmin();
        _;
    }

    /// @dev Enforce (and consume) the emergency timelock. When delay is 0 this is
    ///      a no-op (testnet keeps instant recovery); otherwise an action must be
    ///      armed on-chain and the delay elapsed. Consumed inside the tx so a
    ///      revert also rolls back the consumption.
    modifier timelocked() {
        if (emergencyDelay != 0) {
            if (emergencyReadyAt == 0 || block.timestamp < emergencyReadyAt) revert Timelocked();
            emergencyReadyAt = 0;
        }
        _;
    }

    /// @notice Announce an emergency action on-chain; it becomes executable after
    ///         `emergencyDelay`. Holders can watch this event and exit first.
    function armEmergency() external onlyEmergency {
        emergencyReadyAt = block.timestamp + emergencyDelay;
        emit EmergencyArmed(emergencyReadyAt);
    }

    /// @notice Break-glass: pull a generation's LP (ETH + tokens) to the admin.
    ///         Timelocked on mainnet (arm → wait → execute); instant on testnet.
    function emergencyWithdrawLP(uint256 gen) external onlyEmergency timelocked nonReentrant {
        (uint256 eth, uint256 tokens) = _removeLiquidity(gen);
        address tok = generationToken[gen];
        if (tokens > 0) IERC20(tok).transfer(emergencyAdmin, tokens);
        if (eth > 0) {
            (bool ok, ) = emergencyAdmin.call{value: eth}("");
            if (!ok) revert EthSend();
        }
        emit EmergencyWithdraw(gen, emergencyAdmin, eth, tokens);
    }

    /// @notice Break-glass: sweep the registry's ETH (token==0) or an ERC20 to
    ///         the admin. Timelocked on mainnet; instant on testnet.
    function emergencySweep(address token) external onlyEmergency timelocked nonReentrant {
        if (token == address(0)) {
            (bool ok, ) = emergencyAdmin.call{value: address(this).balance}("");
            if (!ok) revert EthSend();
        } else {
            IERC20(token).transfer(emergencyAdmin, IERC20(token).balanceOf(address(this)));
        }
    }

    receive() external payable {}

    // -----------------------------------------------------------------------
    // Wiring (owner, pre-ignition)
    // -----------------------------------------------------------------------

    /// @notice Set the proposal governor that relaunch reads winners from.
    function setGovernor(address _governor) external onlyOwner {
        governor = ICauldronGovernor(_governor);
    }

    /// @notice Tune the min brew lifetime before relaunch (break-glass admin).
    function setMinLifetime(uint256 _seconds) external onlyEmergency {
        minLifetime = _seconds;
    }

    /// @notice Set the collection/vault factory (required before summon).
    function setFactory(address _factory) external onlyOwner {
        factory = ICauldronFactory(_factory);
    }

    /// @notice Per-brew NFT collection supply cap.
    function setNftMaxSupply(uint256 _max) external onlyOwner {
        if (_max == 0) revert BadConfig();
        nftMaxSupply = _max;
    }

    /// @notice Wire the genesis dividend as the EIP-2981 royalty receiver for
    ///         every brew's collection, and set the royalty rate (bps, <= 10%).
    function setRoyalty(address _dividend, uint96 _bps) external onlyOwner {
        if (_bps > 1000) revert TooHigh();
        royaltyDividend = _dividend;
        royaltyBps = _bps;
    }

    /// @notice Genesis (iteration #1) NFT metadata. Use an on-chain renderer or
    ///         a base URI — this is GnomeLand's metadata for the first brew.
    function setGenesisMetadata(MetadataMode mode, string calldata baseURI, address renderer)
        external
        onlyOwner
    {
        genesisMode = mode;
        genesisBaseURI = baseURI;
        genesisRenderer = renderer;
    }

    /**
     * @notice Reserve a slice of iteration #1's supply for the founding MiFrens
     *         guild. Each MiFren can claim one equal share after summon.
     * @param _mifrens MiFrens ERC721 (the presale receipts).
     * @param _bonusBps Share of gen-1 supply reserved (basis points, <= 3000).
     * @param _shares Number of shares to split the pool into (MiFrens supply).
     */
    function setGenesisBonus(address _mifrens, uint256 _bonusBps, uint256 _shares)
        external
        onlyOwner
    {
        if (summoned) revert AlreadySummoned();
        if (_bonusBps > 3000) revert TooHigh();
        if (_mifrens == address(0) || _shares == 0) revert BadConfig();
        mifrens = _mifrens;
        genesisBonusBps = _bonusBps;
        genesisShares = _shares;
    }

    /// @notice Reserve iteration-1 tokens for the OG-holder airdrop, sent to
    ///         `_wallet` at summon. Owner-set pre-summon; capped so LP always
    ///         keeps the majority of supply.
    function setAirdropReserve(address _wallet, uint256 _amount) external onlyOwner {
        if (summoned) revert AlreadySummoned();
        if (_wallet == address(0)) revert BadConfig();
        if (_amount > (TOTAL_SUPPLY * 2000) / 10_000) revert TooHigh();
        airdropWallet = _wallet;
        airdropReserve = _amount;
    }

    // -----------------------------------------------------------------------
    // SUMMON -- Genesis (one-time, owner provides initial ETH)
    // -----------------------------------------------------------------------

    /**
     * @notice Deploy Generation 1, create V4 pool, add full-range liquidity.
     *         Send ETH with this call for the initial liquidity pairing.
     *         Name/symbol auto-derived from creature list.
     *         sqrtPriceX96 auto-computed from ETH:token ratio.
     *
     *         This is the ONLY function that requires external ETH.
     *         All future generations self-fund from swap fees + LP recovery.
     */
    function summon()
        external
        payable
        onlyOwner
        nonReentrant
        returns (address token, PoolId poolId)
    {
        if (summoned) revert AlreadySummoned();
        if (msg.value == 0) revert InsufficientETH();

        summoned = true;
        currentGeneration = 1;
        lastSummonAt = block.timestamp;

        // Iteration #1 is Gnomeland (creature idx 0). Brand every token
        // "<name> by Magic Internet Frens" — suffix hardcoded on-chain.
        (string memory rawName, string memory symbol) = getCreatureForGeneration(1);
        string memory name = LaunchLib.displayName(rawName);

        // 1. Deploy token via CREATE2 (salt = generation)
        token = _deployToken(name, symbol, 1);
        currentToken = token;
        generationToken[1] = token;

        // 2. The token's constructor already minted the full fixed supply to this
        //    registry (the ERC-20 has no mint() — supply is fixed forever).

        // 2b. Size the genesis bonus (a GIFT — holders bought the ART). It lives
        //     inside the RESERVE position and is claimed 1:1; persists across gens.
        if (genesisBonusBps > 0 && genesisShares > 0) {
            uint256 pool = (TOTAL_SUPPLY * genesisBonusBps) / 10_000;
            genesisSharePerFren = pool / genesisShares;
            genesisReserveOutstanding = genesisSharePerFren * genesisShares;
            emit GenesisBonusReserved(genesisReserveOutstanding, genesisSharePerFren);
        }

        // 2c. OG-holder airdrop reserve → sent off-LP to the airdrop wallet.
        uint256 activeTokens = GEN1_ACTIVE_TOKENS;
        uint256 reserveTokens = TOTAL_SUPPLY - activeTokens;
        if (airdropReserve > 0 && airdropWallet != address(0)) {
            reserveTokens = reserveTokens - airdropReserve;
            IERC20(token).transfer(airdropWallet, airdropReserve);
        }

        // 3. Create the pool + seed TWO positions: active (10% + ETH, sets price)
        //    and the out-of-range reserve (the rest — migration + genesis supply
        //    as LP, not a wallet bag → no whale-look FUD, claimed 1:1 by burn).
        poolId = _createPoolAndSeed(token, activeTokens, msg.value, reserveTokens, 1);

        // 4. Deploy the genesis NFT collection + point the volume hook at it.
        _deployCollection(1, name, symbol, genesisMode, genesisBaseURI, genesisRenderer, nftMaxSupply);

        emit CauldronSummoned(1, token, poolId, name, symbol);
    }

    // -----------------------------------------------------------------------
    // RELAUNCH -- Fully autonomous, permissionless, zero params
    // -----------------------------------------------------------------------

    /**
     * @notice Kill the current token, deploy a new generation, create its V4
     *         pool, and seed liquidity. Everything in one transaction.
     *
     *  FULLY AUTONOMOUS:
     *    - No parameters needed (name/symbol auto-derived, price auto-computed)
     *    - No ETH needed (self-funded from hook fees + dead pool LP recovery)
     *    - Permissionless (anyone can call once the pool is confirmed dead)
     *    - Mints nothing extra to the caller — the rebirth is conserved 1:1,
     *      so migrating holders are never diluted by a relaunch
     *
     *  ETH sources:
     *    1. Dead pool LP removal (ETH side of the position)
     *    2. Hook's accumulated ETH swap fees (relaunchETH reserve)
     */
    function relaunch()
        external
        nonReentrant
        returns (address token, PoolId poolId)
    {
        if (!summoned) revert NotSummoned();

        uint256 oldGen = currentGeneration;
        address oldToken = currentToken;
        PoolId oldPoolId = generationPoolId[oldGen];

        // 1. Verify old pool is dead (on-chain volume check, no oracle)
        if (!hook.isDead(oldPoolId)) revert TokenStillAlive();

        // 1a. Grace period: a brand-new pool reads "dead" at 0 volume — don't let
        //     anyone kill it before it's had a fair chance to trade.
        if (block.timestamp < lastSummonAt + minLifetime) revert TooYoung();

        // 1b. The frens must have proposed (and voted) the next brew. No silent
        //     fallback — relaunch is governance-gated, not automatic.
        if (address(governor) == address(0) || !governor.hasProposals()) revert NoProposal();

        // 2. Retire the old generation (event only). The token is NOT frozen —
        //    it stays fully transferable forever, so holders can keep or trade
        //    their old iteration; migrating to the new brew is optional.
        emit CauldronDied(oldGen, oldToken, block.number);

        // 3. Recover ETH + tokens from the dead pool's LP position.
        (uint256 ethFromLP, uint256 tokensFromLP) = _removeLiquidity(oldGen);
        emit LiquidityRecovered(oldGen, ethFromLP);

        // 3a. BURN the recovered dead-pool tokens. The new LP is re-seeded with
        //     the SAME token amount minted fresh (see step 8), so the LP token
        //     supply stays constant across iterations.
        if (tokensFromLP > 0) {
            CauldronToken(oldToken).burn(address(this), tokensFromLP);
        }

        // 3a-bis. Drain any matured tickets for the dying brew BEFORE its vault
        //     closes, so pending winners mint while the floor is still open and
        //     funded — they end up backed, not stranded (audit L2). Bounded loop;
        //     stragglers committed this very block resolve later (documented).
        hook.resolveTickets(300);

        // 3b. Close the dead brew's floor vault: NFT redemption stops and the
        //     remaining floor ETH sweeps here to seed the next launch.
        uint256 vaultSwept = 0;
        address oldVault = generationVault[oldGen];
        if (oldVault != address(0)) {
            vaultSwept = IVaultClose(oldVault).close();
        }

        // 4. Pull accumulated ETH swap fees from hook
        uint256 ethFromHook = 0;
        if (hook.relaunchETH() > 0) {
            ethFromHook = hook.releaseRelaunchETH();
        }

        // All ETH — recovered LP + hook fees + swept floor — seeds the new pool.
        uint256 totalETH = ethFromLP + ethFromHook + vaultSwept;
        if (totalETH == 0) revert NoLiquidityToSeed();

        // 5. New generation
        uint256 newGen = oldGen + 1;
        currentGeneration = newGen;
        lastSummonAt = block.timestamp; // restart the grace clock for the newborn

        // 6. Launch the winning proposal — the frens decided (guaranteed to exist
        //    by the NoProposal guard above).
        MetadataMode mode = genesisMode;
        string memory baseURI = genesisBaseURI;
        address renderer = genesisRenderer;
        uint256 nftSupply = nftMaxSupply;

        (uint256 winId, BrewSpec memory spec) = governor.winner();
        string memory name = spec.name;
        string memory symbol = spec.symbol;
        mode = spec.mode;
        baseURI = spec.baseURI;
        renderer = spec.renderer;
        if (spec.nftSupply > 0) nftSupply = spec.nftSupply;
        uint256 volPerNFT = spec.volumePerNFT; // proposer's mint-out volume target
        governor.markConsumed(winId);

        // Brand: "<name> by Magic Internet Frens" (hardcoded suffix on-chain).
        name = LaunchLib.displayName(name);

        // 7. Deploy new token via CREATE2 (salt = generation)
        token = _deployToken(name, symbol, newGen);
        currentToken = token;
        generationToken[newGen] = token;

        // 8. Seed TWO positions for the newborn. The ACTIVE tradeable band is
        //    FIXED at the same token amount every generation (constant depth →
        //    consistent launch behaviour), paired with all the recovered ETH. The
        //    RESERVE is the rest (~90%) as an out-of-range single-sided token
        //    position; it shrinks 1:1 as holders migrate/claim during the gen and
        //    resets to full on each rebirth (fresh fixed supply, no mint). 90%
        //    always over-covers the migration demand.
        uint256 newActive = GEN1_ACTIVE_TOKENS;
        uint256 newReserve = TOTAL_SUPPLY - newActive;

        // 9. Seed the new pool: fixed active band + ALL the ETH; reserve = rest.
        poolId = _createPoolAndSeed(token, newActive, totalETH, newReserve, newGen);

        // 10. NFT collection for the new brew.
        //     ITERATION #2 is special: it does NOT deploy a fresh collection —
        //     it CONTINUES the canonical genesis MiFrens, minting the rest of
        //     the art (ids GENESIS_SUPPLY+1..MAX) from volume. Iterations #1
        //     (Gnomeland) and #3+ each deploy their own separate collection.
        if (newGen == 2 && mifrens != address(0)) {
            _continueMiFrens(newGen);
        } else {
            _deployCollection(newGen, name, symbol, mode, baseURI, renderer, nftSupply);
        }

        // Apply the proposer's mint-out volume target to the freshly-wired hook
        // curve (flat: total mint-out ≈ volumePerNFT * nftSupply). 0 = unchanged.
        hook.setNftCurveFrom(volPerNFT);

        emit CauldronReborn(newGen, token, poolId, name, symbol);
    }

    // -----------------------------------------------------------------------
    // Internal: Deploy per-brew NFT collection + wire the volume hook
    // -----------------------------------------------------------------------

    function _deployCollection(
        uint256 gen,
        string memory name,
        string memory symbol,
        MetadataMode mode,
        string memory baseURI,
        address renderer,
        uint256 maxSupply
    ) private {
        // Fall back to a placeholder base URI if metadata was never set, so
        // summon can never revert on a missing config.
        if (mode == MetadataMode.BaseURI && bytes(baseURI).length == 0) {
            baseURI = "https://magicfrens.xyz/api/cauldron/";
        }
        if (maxSupply == 0) maxSupply = nftMaxSupply;

        (address col, address vlt) = factory.deployBrew(
            ICauldronFactory.Config({
                name: name,
                symbol: symbol,
                hook: address(hook),   // only the volume hook may mint
                registry: address(this),
                maxSupply: maxSupply,
                mode: mode,
                baseURI: baseURI,
                renderer: renderer,
                royaltyReceiver: royaltyDividend, // genesis dividend earns royalties
                royaltyBps: royaltyBps
            })
        );
        generationCollection[gen] = col;
        generationVault[gen] = vlt;
        hook.setCollection(col);
        hook.setVault(vlt);
        emit CollectionDeployed(gen, col, mode);
    }

    /**
     * @dev Iteration #2: continue the canonical genesis MiFrens collection.
     *      No new collection is deployed — the existing MiFrens keeps minting
     *      the rest of its art from volume. We deploy only a fresh per-iteration
     *      floor vault, wire the volume hook in as the collection's minter, and
     *      repoint the hook. The hook anchors its rising curve to the collection's
     *      current totalMinted (see CauldronHook.mintBaseline), so pricing starts
     *      fresh even though ~1111 are already minted.
     */
    function _continueMiFrens(uint256 gen) private {
        address col = mifrens;
        address vlt = factory.deployVault(col, address(this));
        generationCollection[gen] = col;
        generationVault[gen] = vlt;
        IMiFrensContinuable(col).setVault(vlt);
        IMiFrensContinuable(col).setMinter(address(hook));
        hook.setCollection(col);
        hook.setVault(vlt);
        emit CollectionDeployed(gen, col, MetadataMode.BaseURI);
    }

    // -----------------------------------------------------------------------
    // CLAIM -- Old holders claim on current generation
    // -----------------------------------------------------------------------

    /**
     * @notice OPTIONALLY migrate to the CURRENT generation by BURNING tokens from
     *         any PREVIOUS generation, 1:1. Migration is a choice, not a
     *         requirement — old tokens are never frozen, so a holder who prefers a
     *         past iteration simply keeps (or trades) it.
     *
     *  Non-exploitable & non-inflationary:
     *    - Burns the caller's own previous-gen tokens (real supply destroyed), and
     *      TRANSFERS the same amount of current-gen tokens from the registry's
     *      pre-minted migration pool — no new tokens are ever minted.
     *    - `fromGen` must be strictly less than the current generation.
     *    - 1:1 and bounded by the caller's balance, so a token can't be claimed
     *      twice, and the migration right just follows whoever holds the old token.
     *    - Best-effort: if the pre-minted pool is exhausted the transfer reverts
     *      (atomically un-burning), so the holder keeps their old token — nothing
     *      is ever stranded.
     */
    function claimByBurn(uint256 fromGen, uint256 amount)
        external
        nonReentrant
        returns (uint256 claimedAmount)
    {
        if (fromGen == 0 || fromGen >= currentGeneration) revert CannotClaimCurrentGen();
        address prevToken = generationToken[fromGen];
        if (prevToken == address(0)) revert UnknownGeneration();
        if (amount == 0 || IERC20(prevToken).balanceOf(msg.sender) < amount) revert NoBalance();

        // Burn the caller's previous-gen tokens, then release the same amount of
        // current-gen tokens 1:1 from the RESERVE position (single-sided, out of
        // range → pure token, no ETH, no price move). No mint. If the reserve is
        // short the removal reverts, rolling the burn back with it.
        CauldronToken(prevToken).burn(msg.sender, amount);
        uint256 g = currentGeneration;
        claimedAmount = PoolOps.claimFromReserve(
            IPositionManagerOps(address(positionManager)),
            generationReservePositionId[g], generationPoolKey[g],
            reserveTickLower[g], reserveTickUpper[g], amount, msg.sender
        );

        emit HolderClaimed(fromGen, msg.sender, claimedAmount);
    }

    // -----------------------------------------------------------------------
    // AUTO-MIGRATE -- hands-off, keeper-executed migration (opt-in)
    // -----------------------------------------------------------------------

    /// @notice Fee to opt into auto-migration for a non-fren wallet.
    uint256 public constant AUTO_MIGRATE_FEE = 0.069 ether;
    /// @notice Wallets that opted into hands-off, keeper-executed migration.
    mapping(address => bool) public autoMigrate;

    event AutoMigrateSet(address indexed who);
    event AutoMigrated(uint256 indexed fromGen, address indexed holder, uint256 amount);

    /// @notice Opt in to hands-off migration: a keeper migrates your balance into
    ///         each new iteration for you, so you never have to click. FREE for
    ///         frens (any MiFren holder); 0.069 ETH for everyone else (the fee
    ///         stays in the registry and seeds the next launch).
    function enableAutoMigrate() external payable {
        if (IERC721(mifrens).balanceOf(msg.sender) == 0) {
            if (msg.value < AUTO_MIGRATE_FEE) revert Fee();
        }
        autoMigrate[msg.sender] = true;
        emit AutoMigrateSet(msg.sender);
    }

    /// @notice Keeper entry: migrate a batch of opted-in holders from `fromGen`
    ///         into the current iteration, 1:1 — burn each holder's old-gen
    ///         balance, transfer the same amount of current-gen from the pre-mint
    ///         pool. Permissionless. Best-effort: skips anyone not opted in,
    ///         holding nothing, or whom the pool can't currently cover, so one
    ///         miss never reverts the batch. Double-spend-proof: it burns the real
    ///         old balance, so a wallet can never be migrated twice.
    function autoMigrateBatch(uint256 fromGen, address[] calldata holders)
        external
        nonReentrant
    {
        if (fromGen == 0 || fromGen >= currentGeneration) revert CannotClaimCurrentGen();
        address prevToken = generationToken[fromGen];
        if (prevToken == address(0)) revert UnknownGeneration();
        uint256 g = currentGeneration;
        IPositionManagerOps pm = IPositionManagerOps(address(positionManager));
        PoolKey memory key = generationPoolKey[g];
        uint256 rid = generationReservePositionId[g];
        int24 rlo = reserveTickLower[g];
        int24 rhi = reserveTickUpper[g];
        for (uint256 i = 0; i < holders.length; i++) {
            address h = holders[i];
            if (!autoMigrate[h]) continue;
            uint256 bal = IERC20(prevToken).balanceOf(h);
            if (bal == 0) continue;
            // Burn the holder's old balance, release 1:1 from the reserve to them.
            CauldronToken(prevToken).burn(h, bal);
            uint256 got = PoolOps.claimFromReserve(pm, rid, key, rlo, rhi, bal, h);
            emit AutoMigrated(fromGen, h, got);
        }
    }

    // NOTE: the old `burnUnclaimed` is obsolete in the reserve-LP model — a dead
    // generation's un-migrated supply lives in its LP positions, which relaunch
    // removes + burns wholesale (see _removeLiquidity), so nothing lingers in a
    // wallet to sweep.

    // -----------------------------------------------------------------------
    // GENESIS BONUS -- founding MiFrens claim their gift of iteration #1
    // -----------------------------------------------------------------------

    /**
     * @notice Claim the genesis bonus for a MiFren you own. One claim per NFT.
     *
     *  IMPORTANT: this is a GIFT layered on top of the art you already bought.
     *  It is NOT a promise that the token's value equals what you paid for the
     *  NFT. At launch FDV the airdrop is intentionally a small fraction of mint
     *  cost — that is how supply is distributed fairly. You bought the art.
     */
    function claimGenesis(uint256 mifrenTokenId) external nonReentrant returns (uint256 amount) {
        if (!summoned) revert NotSummoned();
        if (genesisSharePerFren == 0) revert BadConfig();
        // OG-only (audit F-12): the reserve is sized for the genesis tranche, so
        // only genesis ids (1..genesisShares) may claim — a later volume-minted
        // MiFren (id > genesisShares) can never siphon a founder's airdrop share.
        if (mifrenTokenId == 0 || mifrenTokenId > genesisShares) revert BadConfig();
        if (genesisClaimed[mifrenTokenId]) revert AlreadyClaimed();
        if (IERC721(mifrens).ownerOf(mifrenTokenId) != msg.sender) revert NotOwnerOf();

        genesisClaimed[mifrenTokenId] = true;
        amount = genesisSharePerFren;
        if (genesisReserveOutstanding >= amount) genesisReserveOutstanding -= amount;

        // Genesis PERSISTS across iterations: pull the gift from the CURRENT gen's
        // reserve position (single-sided token, out of range) so an OG always
        // receives LIVE tokens, whichever iteration they finally claim in.
        uint256 g = currentGeneration;
        amount = PoolOps.claimFromReserve(
            IPositionManagerOps(address(positionManager)),
            generationReservePositionId[g], generationPoolKey[g],
            reserveTickLower[g], reserveTickUpper[g], amount, msg.sender
        );
        emit GenesisBonusClaimed(mifrenTokenId, msg.sender, amount);
    }

    /**
     * @notice Claim the genesis bonus for MANY MiFrens in ONE transaction — a
     *         single reserve `decreaseLiquidity` for the combined amount, marking
     *         every id claimed. A holder of 20 frens pays one LP removal, not 20.
     *         Already-claimed ids are skipped (not reverted); every remaining id
     *         must be owned by the caller and within the genesis tranche.
     */
    function claimGenesisMany(uint256[] calldata mifrenTokenIds)
        external
        nonReentrant
        returns (uint256 total)
    {
        if (!summoned) revert NotSummoned();
        if (genesisSharePerFren == 0) revert BadConfig();

        uint256 count;
        for (uint256 i = 0; i < mifrenTokenIds.length; i++) {
            uint256 id = mifrenTokenIds[i];
            if (id == 0 || id > genesisShares) revert BadConfig();
            if (genesisClaimed[id]) continue; // idempotent: skip already-claimed
            if (IERC721(mifrens).ownerOf(id) != msg.sender) revert NotOwnerOf();
            genesisClaimed[id] = true;
            count++;
        }
        if (count == 0) revert AlreadyClaimed();

        uint256 amount = genesisSharePerFren * count;
        if (genesisReserveOutstanding >= amount) genesisReserveOutstanding -= amount;

        uint256 g = currentGeneration;
        total = PoolOps.claimFromReserve(
            IPositionManagerOps(address(positionManager)),
            generationReservePositionId[g], generationPoolKey[g],
            reserveTickLower[g], reserveTickUpper[g], amount, msg.sender
        );
        emit GenesisBonusClaimed(0, msg.sender, total); // id 0 = batch marker
    }

    // -----------------------------------------------------------------------
    // Internal: Remove Liquidity from Dead Pool
    // -----------------------------------------------------------------------

    /**
     * @dev Remove BOTH the active + reserve positions of a retired generation and
     *      return the total recovered (ETH, tokens). Encoding is delegated to the
     *      linked PoolOps library. The token is never frozen, so removal is free.
     */
    function _removeLiquidity(uint256 gen)
        private
        returns (uint256 ethRecovered, uint256 tokensRecovered)
    {
        PoolKey memory key = generationPoolKey[gen];
        address deadToken = generationToken[gen];
        IPositionManagerOps pm = IPositionManagerOps(address(positionManager));

        (uint256 e1, uint256 t1) = PoolOps.removeAll(pm, generationPositionId[gen], key, deadToken);
        ethRecovered = e1;
        tokensRecovered = t1;

        uint256 rid = generationReservePositionId[gen];
        if (rid != 0) {
            (uint256 e2, uint256 t2) = PoolOps.removeAll(pm, rid, key, deadToken);
            ethRecovered += e2;
            tokensRecovered += t2;
        }
    }

    // -----------------------------------------------------------------------
    // Internal: Deploy Token via CREATE2
    // -----------------------------------------------------------------------

    /**
     * @dev Deploy a CauldronToken using CREATE2 with generation as salt.
     *      Token addresses are deterministic and predictable.
     *      Passes poolManager address so dead tokens can whitelist LP removal.
     */
    function _deployToken(
        string memory name,
        string memory symbol,
        uint256 gen
    ) private returns (address token) {
        bytes32 salt = bytes32(gen);

        token = address(
            new CauldronToken{salt: salt}(
                name,
                symbol,
                gen,
                address(this),      // registry (also the fixed-supply mint recipient)
                TOTAL_SUPPLY        // full supply minted once in the ctor; no mint() exists
            )
        );
    }

    // -----------------------------------------------------------------------
    // Internal: Create V4 Pool + Seed Full-Range Liquidity
    // -----------------------------------------------------------------------

    /**
     * @dev Create the V4 pool and seed the TWO positions:
     *        1. ACTIVE (full-range): `activeTokens` + all `ethAmount` — sets the
     *           launch price and provides tradeable depth.
     *        2. RESERVE (single-sided, out of range below launch): `reserveTokens`
     *           — the migration + genesis supply, claimed 1:1 by burn. Placing it
     *           here (not a wallet) means 100% of supply reads as LP (no whale
     *           FUD) yet only leaves against a burn.
     *      All PositionManager encoding is delegated to the linked PoolOps library
     *      so the registry fits under EIP-170.
     */
    function _createPoolAndSeed(
        address token,
        uint256 activeTokens,
        uint256 ethAmount,
        uint256 reserveTokens,
        uint256 gen
    ) private returns (PoolId poolId) {
        SeedResult memory r = PoolOps.createAndSeed(
            poolManager, IPositionManagerOps(address(positionManager)), address(hook),
            token, activeTokens, ethAmount, reserveTokens,
            TICK_SPACING, POOL_FEE, RESERVE_CEILING_OFFSET
        );
        poolId = r.poolId;
        generationPoolId[gen] = r.poolId;
        generationPoolKey[gen] = r.key;
        generationPositionId[gen] = r.activePositionId;
        generationReservePositionId[gen] = r.reservePositionId;
        reserveTickLower[gen] = r.reserveTickLower;
        reserveTickUpper[gen] = r.reserveTickUpper;
    }

    // -----------------------------------------------------------------------
    // View Helpers
    // -----------------------------------------------------------------------

    function hasClaimed(uint256 generation_, address holder) external view returns (bool) {
        return claimed[generation_][holder];
    }

    /// @notice Get the creature info for a generation (cycles through 6).
    function getCreatureForGeneration(uint256 gen)
        public
        pure
        returns (string memory name, string memory symbol)
    {
        uint256 idx = (gen - 1) % 6;
        if (idx == 0) return ("Gnomeland", "GNOME");
        if (idx == 1) return ("Ethereal Spirit", "SPIRIT");
        if (idx == 2) return ("Shadow Wraith", "WRAITH");
        if (idx == 3) return ("Infernal Beast", "BEAST");
        if (idx == 4) return ("Astral Entity", "ASTRAL");
        return ("Storm Elemental", "STORM");
    }

    /// @notice Predict the address of a CauldronToken before deployment.
    function predictTokenAddress(uint256 gen) external view returns (address) {
        (string memory name, string memory symbol) = getCreatureForGeneration(gen);
        bytes32 salt = bytes32(gen);

        bytes memory bytecode = abi.encodePacked(
            type(CauldronToken).creationCode,
            abi.encode(name, symbol, gen, address(this), TOTAL_SUPPLY)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))
        );

        return address(uint160(uint256(hash)));
    }
}
