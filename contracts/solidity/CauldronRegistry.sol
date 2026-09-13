// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
//  `Currency` is a user-defined value type over `address`, so `unwrap` is a
//  compile-time cast and costs this near-EIP-170 contract zero runtime bytes.
import {Currency} from "v4-core/src/types/Currency.sol";

import {CauldronToken} from "./CauldronToken.sol";
import {CauldronHook} from "./CauldronHook.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode, LaunchLib} from "./cauldron/ICauldron.sol";
import {PoolOps, IPositionManagerOps, SeedResult, ReserveRef, SeedParams} from "./cauldron/PoolOps.sol";
import {ISeeder} from "./cauldron/ISeeder.sol";
// Shared storage base + the type surface both the registry and the RedemptionExt
// delegatecall facet see (interfaces moved here so the layouts stay identical).
import {
    CauldronBase,
    ICauldronFactory,
    IMiFrensContinuable,
    IVaultClose,
    IPerpSync,
    ICollectionLedger,
    IPositionManager
} from "./cauldron/CauldronBase.sol";

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
/// @dev The art-repair entrypoint every Cauldron collection ships, gated on its
///      `deployer` — which is this registry. `cauldron/CauldronCollection.sol:316`.
interface ICollectionMetadata {
    function setMetadata(MetadataMode mode, address renderer, string calldata baseURI) external;
}

contract CauldronRegistry is CauldronBase, IUnlockCallback {
    /// @dev `RedemptionExt.recoverLegsAtTeardown(uint256)` — the UNGATED entry, which
    ///      exists only for this call and has no forwarder on purpose (the public
    ///      `recoverLegs` stub below is the gated one). Declared `constant` so solc
    ///      folds the hash at COMPILE time — the same expression written inline
    ///      hashes on every call and cost this contract 156 bytes of its EIP-170
    ///      margin. Never hand-written: a wrong selector fails silently here,
    ///      leaving every rotated leg stranded with nothing to show for it.
    bytes4 private constant RECOVER_LEGS = bytes4(keccak256("recoverLegsAtTeardown(uint256)"));

    // Errors + the shared redemption events/views/storage now live in
    // {CauldronBase} (shared with the RedemptionExt delegatecall facet).

    // -----------------------------------------------------------------------
    // Events (registry-only)
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


    event CollectionDeployed(uint256 indexed generation, address collection, MetadataMode mode);
    event GenesisBonusReserved(uint256 pool, uint256 perFren);
    /// @notice The redemption circuit-breaker was toggled (protection, timelocked).
    event RedemptionPauseSet(bool paused);
    event EmergencyWithdraw(uint256 indexed gen, address indexed to, uint256 eth, uint256 tokens);
    event EmergencyArmed(uint256 readyAt);
    event EmergencyVetoed(address indexed guardian);
    event GuardianSet(address indexed guardian);
    event SuccessorSet(address indexed successor);
    event MigratedToSuccessor(address indexed successor, uint256 generations);
    event ClaimGateSet(address indexed gate);

    // -----------------------------------------------------------------------
    // Immutables (registry-only). The RedemptionExt facet never reads these, and
    // immutables live in code (not storage) so they don't affect the shared
    // layout — safe to keep here rather than promote to CauldronBase storage.
    // NOTE: `poolManager`/`positionManager`/`hook` are the OPPOSITE case — the
    // facet DOES read them under delegatecall, so they are STORAGE in CauldronBase
    // (immutables would resolve to zero in the facet's context).
    // -----------------------------------------------------------------------
    /// @notice Break-glass admin that can recover LP + sweep the registry.
    address public immutable emergencyAdmin;
    /// @notice Timelock on every emergency action. IMMUTABLE (can't be lowered).
    uint256 public immutable emergencyDelay;

    /// @notice Gas kept in reserve for the REST of `relaunch()` when it forwards
    ///         to an unbounded sub-call (audit Z-07). The 63/64 rule means an
    ///         out-of-gas child would otherwise consume all but 1/64 of the gas and
    ///         the `catch` would resume with far too little to finish the rebirth —
    ///         a full perp book (64 positions × ~450k settlement) or a large crystal
    ///         backlog could brick relaunch outright. Capping the sub-calls to
    ///         `gasleft() - RELAUNCH_TAIL_RESERVE` makes an OOG child consume only
    ///         its budget; the rebirth always completes and any un-cleared positions
    ///         / tickets are drained afterwards by the permissionless keeper paths.
    uint256 internal constant RELAUNCH_TAIL_RESERVE = 8_000_000;
    /// @notice Ticket-resolution budget inside relaunch (bounded so it can never
    ///         starve the rebirth). The rest resolve post-relaunch (permissionless).
    uint256 internal constant RELAUNCH_TICKETS = 50;

    /// @notice Emitted when the reserve cannot fully cover all three claimants
    ///         (1:1 migration + genesis floor + collection legacy floors) at a
    ///         relaunch, because the accumulated legacy entitlement met or exceeded
    ///         the new active supply. The reserve is then sized as large as the
    ///         supply allows; the shortfall is observable here rather than silent
    ///         (audit Z-12). Claims are first-come until a future generation with a
    ///         larger recovery restores full coverage.
    event ReserveShortfall(uint256 indexed gen, uint256 legacyEntitled, uint256 activeAvailable);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------
    constructor(
        address _poolManager,
        address _positionManager,
        address _hook,
        address _emergencyAdmin,
        uint256 _emergencyDelay
    ) {
        // Former immutables → STORAGE (see CauldronBase). The RedemptionExt facet
        // reads these under delegatecall, where an immutable would be zero.
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager);
        hook = CauldronHook(payable(_hook));
        // Testnet: deployer EOA + delay 0. Mainnet: a Safe multisig + e.g. 7 days.
        emergencyAdmin = _emergencyAdmin == address(0) ? msg.sender : _emergencyAdmin;
        emergencyDelay = _emergencyDelay;
        // Native ETH is allowed from construction, so a fresh deployment behaves
        // exactly as before and stays that way until governance widens the set.
        allowedQuote[address(0)] = true;
        quoteScale[address(0)] = 1e18;   // wei per wei
        emit QuoteAllowed(address(0), true);
    }

    /// @notice One-time wiring of the {RedemptionExt} facet the OG-redemption ops
    ///         delegatecall into. A delegatecall target has full code-execution
    ///         power over this registry's storage + custody, so it is settable
    ///         ONCE (then frozen) — deploy-script only. Owner = deployer/timelock.
    function setRedemptionExt(address ext) external onlyOwner {
        // Must be a CONTRACT: a delegatecall to a code-less address returns SUCCESS
        // with empty returndata, which would make every forwarded redemption a
        // silent no-op (return 0, move nothing) instead of reverting. Reject EOAs /
        // undeployed targets so a deploy-time fat-finger fails loudly here.
        if (ext.code.length == 0) revert BadConfig();
        if (redemptionExt != address(0)) revert AlreadySummoned(); // frozen after first set
        redemptionExt = ext;
    }

    /// @notice Set the reserve ceiling (tick offset) the NEXT summon/relaunch uses.
    ///         Owner = timelock; picked per iteration alongside the winning brew.
    ///         offset = ln(mult)/ln(1.0001). Bounds are sanity only. Default = 69×.
    function setReserveCeiling(int24 offset) external onlyOwner {
        if (offset < 4000 || offset > 138000) revert BadConfig();
        nextReserveCeilingOffset = offset;
    }

    // -----------------------------------------------------------------------
    // PROGRESSIVE SEED wiring (opt-in; owner/timelock). Default off keeps the
    // atomic green-candle path byte-for-byte unchanged.
    // -----------------------------------------------------------------------
    event SeederSet(address indexed seeder);
    /// @notice A quote asset was added to or removed from the allowlist.
    event QuoteAllowed(address indexed quote, bool allowed);
    event SeedWindowSet(uint64 window);

    /// @notice Wire the persistent progressive seeder ({CauldronSeeder}). Deployed
    ///         once (pointed at this registry) and reused every generation. Set to
    ///         address(0) to turn the feature back off (atomic seed). Owner-gated.
    ///         Propagates to the hook so afterSwap streams it in-swap (keeperless);
    ///         to keep the seeder but disable ONLY the in-swap nudge (fall back to
    ///         permissionless poke), call `hook.setSeeder(0)` directly.
    /// @notice Curate the quote assets an iteration may pair against.
    ///
    ///  OWNER-ONLY, and that is the whole guardrail: a proposer picks FROM this
    ///  set but can never add to it. Letting a proposer add their own quote
    ///  would let them name a token they control and drain the pool into it.
    ///
    ///  Native ETH cannot be removed. It is the fallback every generation can
    ///  always launch against, and the sink a failed non-ETH payout rolls into;
    ///  disallowing it would leave a generation with no valid quote at all.
    ///
    ///  Admission is a treasury judgement, not a code one. A quote is only safe
    ///  here if it is a plain ERC20 (no transfer hook, no rebase — either
    ///  silently breaks every amount the pool accounts for), has independent
    ///  depth so the relaunch conversion cannot be cheaply manipulated, and has
    ///  known decimals. Where it can be paused or blacklisted by a third party —
    ///  true of most tokenized equities — that is a disclosed property of the
    ///  pair, not a surprise.
    /// @notice Move ONE slice of liquidity into another quote: remove, swap and
    ///         redeploy in a single transaction. See RedemptionExt.
    ///
    ///  Forwarded rather than implemented here: the registry sits against the
    ///  EIP-170 ceiling, and the facet already runs on this contract's storage
    ///  and custody under delegatecall.
    function rotateSlice(uint16, uint256, PoolKey calldata) external returns (uint256, uint256) {
        _forwardToExt();
    }

    /// @notice Rotate a slice out of a CHOSEN leg — `fromLeg` 0 is the primary
    ///         pool, 1..legCount are the rotated legs. See RedemptionExt.
    ///
    ///  ── THE FACET HAD THIS; THE DISPATCHER DID NOT (functional audit F-20) ──
    ///  `rotateSlice` above forwards only the 3-arg form, which hard-codes
    ///  `fromLeg = 0` (RedemptionExt.sol:260). The 4-arg form was added to the
    ///  facet with no stub here, and there is no catch-all fallback — so the
    ///  multi-leg rotation that RedemptionExt.sol:307-318 describes as the whole
    ///  point of `fromLeg` (merging two legs, rebalancing between them, moving
    ///  USDG -> anything rather than only ever draining the original quote) had
    ///  no reachable path from any caller.
    ///
    ///  It is also the ONLY write the treasury UI issues for a rotation —
    ///  `src/hooks/useTreasuryRotation.ts:290` calls `rotateSliceFrom` at the
    ///  registry for EVERY slice, including the default `fromLeg = 0` — so the
    ///  rotate button reverted on every press, not merely on the multi-leg path.
    ///
    ///  Third instance of this defect class in this contract pair, after
    ///  `setRotationWiring` (RedemptionExt.sol:215-227) and the three views at
    ///  :1344 below. A facet function is only real once BOTH halves exist.
    function rotateSliceFrom(uint8, uint16, uint256, PoolKey calldata)
        external
        returns (uint256, uint256)
    {
        _forwardToExt();
    }

    /// @notice Wire the rotator and the treasury vote in one call. Combined
    ///         because both are deploy-time wiring and this registry has no
    ///         dispatcher budget for two entries. See RedemptionExt.
    function setRotationWiring(address, address) external { _forwardToExt(); }

    /// @notice Retry the unwind of a PAST generation's rotated legs. See
    ///         RedemptionExt.
    ///
    ///  ── THE DOCUMENTED RETRY HAD NO WAY IN ────────────────────────────────
    ///  `recoverLegs` is best-effort per leg on purpose, so one pool that cannot be
    ///  unwound does not block a rebirth and strand every other leg with it — and
    ///  the failed leg stays recorded precisely so it can be retried. There was no
    ///  stub for it and this contract has no fallback, so the retry reverted as an
    ///  unrecognized selector; calling the facet directly ran against the facet's
    ///  own empty storage and returned (0, 0). The recovery the comment promised
    ///  did not exist.
    ///
    ///  This forwarder cost 15 bytes more than this contract had, which is what the
    ///  preceding `refactor(size)` commit was for.
    function recoverLegs(uint256) external returns (uint256, uint256) { _forwardToExt(); }

    /// @notice Move booked foreign leg proceeds out to a sink. See RedemptionExt.
    ///
    ///  A rotated leg recovered in an asset that is not its generation's quote is
    ///  BOOKED rather than counted toward the rebirth (RedemptionExt's
    ///  `legProceeds`). The facet shipped the only way to move that balance and
    ///  the only way to read it, and NEITHER had a stub here — and this registry
    ///  has no fallback, so both were dead and the booked asset was stuck.
    ///  Fourth instance of the defect class {F20_FacetReachability} tracks.
    function sweepLegProceeds(address, address) external returns (uint256) { _forwardToExt(); }

    //  `legProceedsOf` is deliberately NOT stubbed: the registry has ~40 bytes of
    //  EIP-170 headroom and the value-moving half had to win. The balance stays
    //  observable off-chain from `LegProceedsBooked`/`LegProceedsSwept`, and on
    //  a facet whose storage IS this contract's it can be read directly from the
    //  slot. A read-only gap is recoverable; a stuck asset is not.

    function setAllowedQuote(address quote, bool allowed, uint256 scale) external onlyOwner {
        if (quote == address(0) && !allowed) revert NativeQuoteRequired();
        //  CEILING. Every iteration token is mined ABOVE PoolOps.QUOTE_WATERMARK,
        //  so a quote at or above it could sort ABOVE the token — inverting the
        //  pool and breaking every "quote = currency0" assumption in the seeding
        //  and liquidity math.
        //
        //  Refusing here is what upgrades adoptability from a hope to an
        //  INVARIANT: any allowlisted quote sorts below any token, so ANY
        //  generation can migrate to ANY approved pair. The bound excludes only
        //  the top 6.25% of the address space and no real quote asset lives
        //  there (USDC 0xA0b8, DAI 0x6B17, USDT 0xdAC1).
        if (allowed && uint160(quote) >= uint160(QUOTE_WATERMARK)) revert QuoteAboveWatermark();
        allowedQuote[quote] = allowed;
        // Identity for native ETH; a real value for anything measured in other units.
        if (allowed) quoteScale[quote] = scale == 0 ? 1e18 : scale;
        emit QuoteAllowed(quote, allowed);
    }

    function setSeeder(address _seeder) external onlyOwner {
        seeder = _seeder;
        hook.setSeeder(_seeder);
        emit SeederSet(_seeder);
    }

    /// @notice BREAK-GLASS for an ABORTED progressive campaign: return the seeder's
    ///         loose ledger-A funds to this registry. The seeder's `rescue` is
    ///         `onlyRegistry`, but no registry function called it — the escape hatch
    ///         was unreachable (audit I-03). Emergency-admin gated + timelocked,
    ///         like every other custody action. Only ever touches ledger A; the
    ///         redemption reserve is a separate position the seeder cannot hold.
    function rescueSeeder() external onlyEmergency timelocked nonReentrant {
        address s = seeder;
        if (s == address(0)) revert NotConfigured();
        ISeeder(s).rescue(address(this));
    }

    /// @notice Set the launch window (seconds) the NEXT summon/relaunch streams the
    ///         active tranche over. 0 = atomic. Progressive fires only when this is
    ///         > 0 AND a seeder is set. Owner = timelock, chosen per iteration.
    ///         Bounded to a sane range so a fat-finger can't strand the active LP in
    ///         a decade-long stream or a zero-safety instant.
    function setSeedWindow(uint64 window) external onlyOwner {
        if (window != 0 && (window < 60 || window > 7 days)) revert BadConfig();
        nextSeedWindow = window;
        emit SeedWindowSet(window);
    }

    /// @notice The token fee to RE-enchant a moved fren = enchantFeeMultBps × the
    ///         live floor. The MiFrensDividend reads this and (for a moved fren)
    ///         collects it, routing it into the reserve via `donateToReserve`.
    function enchantFee() external view returns (uint256) {
        return (floorPerFren() * enchantFeeMultBps) / 10_000;
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
        _consumeTimelock();
        _;
    }

    /// @dev Body of {timelocked}, factored out so a function can apply the delay
    ///      CONDITIONALLY (see {setClaimGate}, which timelocks only the restricting
    ///      direction).
    ///
    ///  ARMING IS ALWAYS MANDATORY (audit F-19). This whole check used to be
    ///  wrapped in `if (emergencyDelay != 0)`, so a deployment constructed with a
    ///  zero delay skipped it entirely — and that did far more than remove the
    ///  waiting period. `emergencyReadyAt` was then NEVER set, and
    ///  {CauldronBase._redeemBlocked} keys THE EXIT GUARANTEE off exactly that
    ///  variable:
    ///
    ///      _redeemBlocked() == redemptionPaused && emergencyReadyAt == 0
    ///
    ///  so with a zero delay the guarantee that "arming a custody action forces
    ///  the redemption exit OPEN so holders can always leave at floor first"
    ///  silently did not exist. The admin could `setRedemptionPaused(true)` (which
    ///  is deliberately immediate, being a fast circuit-breaker) and then withdraw
    ///  the LP with holders still locked out — precisely the sequence the forced
    ///  exit was written to prevent. The protection was absent while appearing
    ///  present, and `emergencyDelay` is `immutable`, so a deployment could never
    ///  be corrected.
    ///
    ///  Separating the two concerns fixes it structurally rather than by
    ///  configuration: the ARM decides whether an exit window EXISTS, and
    ///  `emergencyDelay` decides how LONG it is. A custody action now always
    ///  requires a prior `armEmergency()`, so `emergencyReadyAt` is always set —
    ///  and the exit therefore always opens — no matter how the delay was
    ///  configured. A zero delay degrades the window to a transaction boundary
    ///  instead of deleting the mechanism.
    function _consumeTimelock() private {
        if (emergencyReadyAt == 0) revert Timelocked();                       // must be armed
        if (emergencyDelay != 0 && block.timestamp < emergencyReadyAt) revert Timelocked();
        emergencyReadyAt = 0;
    }

    /// @notice Delegate the one-time genesis ignition to `who` (the presale) WITHOUT
    ///         handing over ownership. See {CauldronBase.igniter} (audit Z-06).
    function setIgniter(address who) external onlyOwner {
        igniter = who;
    }

    /// @notice Announce an emergency action on-chain; it becomes executable after
    ///         `emergencyDelay`. Holders can watch this event and exit first.
    function armEmergency() external onlyEmergency {
        emergencyReadyAt = block.timestamp + emergencyDelay;
        emit EmergencyArmed(emergencyReadyAt);
    }

    /// @notice GUARDIAN VETO: cancel a queued emergency action during its window.
    ///         The guardian can ONLY cancel (never propose, never move funds) — a
    ///         pure-upside safety role. Set by the emergencyAdmin (timelock).
    function setGuardian(address who) external {
        // Owner may set it once at deploy (pre-handoff); thereafter only the
        // emergencyAdmin (timelock) can change this safety role.
        if (msg.sender != emergencyAdmin && msg.sender != owner()) revert NotAdmin();
        guardian = who;
        emit GuardianSet(who);
    }

    /// @notice Cancel the armed emergency action. Guardian-only. Turns the "watch
    ///         and flee" window into "watch and BLOCK".
    function vetoEmergency() external {
        if (msg.sender != guardian) revert NotAdmin();
        emergencyReadyAt = 0;
        emit EmergencyVetoed(msg.sender);
    }

    // NOTE: `_redeemBlocked()` (THE EXIT GUARANTEE) now lives in {CauldronBase} —
    // it is shared with the RedemptionExt facet and recycleCollectionNFT.

    /// @notice PROTECTION: pause/unpause the genesis redemption path. Gated to the
    ///         emergencyAdmin (the governance timelock) — a targeted circuit-breaker
    ///         so a discovered bug in redeemOgFren can be halted without the nuclear
    ///         emergencyWithdrawLP. NOT timelocked itself (a live exploit needs a
    ///         fast stop); it only ever DISABLES a permissionless flow, never moves
    ///         funds, so it carries no rug surface.
    function setRedemptionPaused(bool paused) external onlyEmergency {
        redemptionPaused = paused;
        emit RedemptionPauseSet(paused);
    }

    /// @notice Tune the re-enchant fee multiple (bps of the live floor). Gated to
    ///         the emergencyAdmin (timelock). Capped at 100× to prevent a fat-finger
    ///         from making re-enchant impossible. 0 = free re-enchant (disables the
    ///         fee sink). Original never-moved OGs are always free regardless.
    function setEnchantFeeMult(uint256 bps) external onlyEmergency {
        if (bps > 1_000_000) revert TooHigh(); // <= 100×
        enchantFeeMultBps = bps;
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

    // -----------------------------------------------------------------------
    // V2 UPGRADE -- controller handoff (no LP teardown)
    // -----------------------------------------------------------------------

    /// @notice Telegraph the V2 upgrade target. Timelock/emergencyAdmin only. Just
    ///         sets the pointer + emits — the custody MOVE is `migrateToSuccessor`,
    ///         which is separately armed+timelocked so holders get the forced-open
    ///         exit window before anything moves.
    function setSuccessor(address _successor) external onlyEmergency {
        successor = _successor;
        emit SuccessorSet(_successor);
    }

    /// @notice Route the instant 1:1 migration through a vesting escrow (anti-dump).
    ///         Set to a deployed {MigrationVesting} to ENFORCE linear vesting on
    ///         ordinary holders; set back to address(0) to restore instant
    ///         migration. Governance-only. The perp engine is always exempt.
    ///
    ///  ASYMMETRIC TIMELOCK (audit Z-08). Setting a non-zero gate CLOSES the 1:1
    ///  migration path for every ordinary holder instantly — `claimByBurn`,
    ///  `claimByBurnUpTo` and `autoMigrateBatch` all revert `VestingEnforced` — and it
    ///  used to be neither timelocked nor guardian-vetoable, so a single un-announced
    ///  call could trap every old-generation holder indefinitely. That is exactly the
    ///  class of action the arm-and-wait window exists for, and (unlike the redemption
    ///  pause) nothing forced the exit back open to compensate. Restricting now
    ///  requires an armed, vetoable, delayed action; RESTORING instant migration stays
    ///  immediate, so the safe direction is never slowed down.
    function setClaimGate(address gate) external onlyEmergency {
        if (gate != address(0)) _consumeTimelock();
        claimGate = gate;
        emit ClaimGateSet(gate);
    }

    /// @notice Hand the LIVE liquidity to the successor by transferring the CURRENT
    ///         generation's active + reserve position-NFTs' OWNERSHIP — NOT
    ///         withdrawing them. The Uniswap positions (and thus price/liquidity)
    ///         are completely untouched; only the owner-of-record changes, so V2 can
    ///         manage the exact same LP. Loose ETH + current-token balance follow.
    ///         Armed+timelocked (the exit is forced open during the window) and
    ///         guardian-vetoable. NOT callable mid-relaunch. Treasury frens + the
    ///         MiFrens custody pointer are re-homed separately by governance
    ///         (mifrens.setRegistry(successor)); the hook is re-pointed via
    ///         hook.setRegistryOverride(successor) under the same timelock.
    function migrateToSuccessor() external onlyEmergency timelocked nonReentrant {
        address to = successor;
        if (to == address(0)) revert BadConfig();
        uint256 g = currentGeneration;

        // Transfer the live position-NFTs (ownership move — no liquidity withdrawal).
        uint256 activeId = generationPositionId[g];
        uint256 reserveId = generationReservePositionId[g];
        if (activeId != 0) IERC721(address(positionManager)).transferFrom(address(this), to, activeId);
        if (reserveId != 0) IERC721(address(positionManager)).transferFrom(address(this), to, reserveId);

        // PROGRESSIVE GENERATIONS (audit L-08). On a streamed generation
        // `generationPositionId[g]` is 0 — the ACTIVE book lives in the seeder's N
        // core positions, which are owned by the SEEDER and recoverable only via
        // `withdrawAll`, which is `onlyRegistry` on the OLD registry. Without this,
        // a handoff gave the successor the reserve but left the entire active book
        // stranded behind the outgoing controller. Unwind it here so the migration
        // is atomic and both ledgers move together; the recovered ETH + token then
        // leave with the loose balances below.
        address _seeder = seeder;
        if (_seeder != address(0) && ISeeder(_seeder).seeding()) {
            ISeeder(_seeder).withdrawAll(address(this));
        }

        // Follow with any loose balances (the bulk of value is inside the LP above).
        address tok = generationToken[g];
        if (tok != address(0)) {
            uint256 bal = IERC20(tok).balanceOf(address(this));
            if (bal > 0) IERC20(tok).transfer(to, bal);
        }
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            (bool ok, ) = to.call{value: ethBal}("");
            if (!ok) revert EthSend();
        }
        emit MigratedToSuccessor(to, g);
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
        if (_max == 0 || _max > MAX_NFT_SUPPLY) revert BadConfig(); // audit C-02
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
     * @notice REPOINT A LIVE COLLECTION'S ART SOURCE (owner/timelock only).
     *
     *  {setGenesisMetadata} above only seeds the values a FUTURE collection is
     *  deployed with (they are read at `_deployCollection`, line ~862), so it
     *  cannot repair a collection that already exists. `CauldronCollection`
     *  ships exactly the right repair — `setMetadata(mode, renderer, baseURI)`,
     *  `cauldron/CauldronCollection.sol:316` — but it is gated on the
     *  collection's `deployer`, which IS THIS REGISTRY (audit H-01), and no
     *  registry function called it. The repair therefore existed and was
     *  UNREACHABLE: a collection whose renderer reverts (the whole revealed
     *  branch did, before the art adapter) could never be moved to a working
     *  renderer or to a BaseURI art endpoint.
     *
     * @param gen Generation to repoint; 0 means the LIVE one.
     * @dev Same `onlyOwner` gate as every other art/config setter here. On a
     *      real deployment the owner is a TimelockController, so this is a
     *      schedule/execute round trip, not a one-shot call.
     */
    function setCollectionMetadata(
        uint256 gen,
        MetadataMode mode,
        address renderer,
        string calldata baseURI
    ) external onlyOwner {
        address col = generationCollection[gen == 0 ? currentGeneration : gen];
        if (col == address(0)) revert BadConfig();
        ICollectionMetadata(col).setMetadata(mode, renderer, baseURI);
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

    /// @notice Owner sets who may fund/reclaim the prime buy (pre-summon only).
    function setPrimeFunder(address who) external onlyOwner {
        if (summoned) revert AlreadySummoned();
        primeFunder = who;
    }

    /// @notice Pre-fund the genesis prime buy with personal ETH (send 2-3Ξ before
    ///         MiFrens mints out). Spent at summon on a first-block market buy →
    ///         GNOME to the treasury/airdrop wallet. Reclaim anytime pre-summon via
    ///         `sweepPrimeBuy` (post-summon the balance is already spent → 0).
    ///         Gated to `primeFunder` so it works after the presale ownership handoff.
    function fundPrimeBuy() external payable {
        if (msg.sender != primeFunder) revert NotAdmin();
        primeBuyEth += msg.value;
    }

    /// @notice Reclaim any un-spent prime-buy ETH back to the funder.
    function sweepPrimeBuy() external {
        if (msg.sender != primeFunder) revert NotAdmin();
        uint256 amt = primeBuyEth;
        primeBuyEth = 0;
        (bool ok,) = msg.sender.call{value: amt}("");
        if (!ok) revert BadConfig();
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
        nonReentrant
        returns (address token, PoolId poolId)
    {
        // Owner OR the delegated igniter (the presale). Splitting ignition out of
        // ownership is what lets ownership stay with governance — see
        // {CauldronBase.igniter} (audit Z-06). One-shot either way (`summoned`).
        if (msg.sender != owner() && msg.sender != igniter) revert NotAdmin();
        if (summoned) revert AlreadySummoned();
        if (msg.value == 0) revert InsufficientETH();

        summoned = true;
        currentGeneration = 1;
        lastSummonAt = block.timestamp;

        // Iteration #1 is Gnomeland (creature idx 0). Brand every token
        // "<name> by Magic Internet Frens" — suffix hardcoded on-chain.
        (string memory rawName, string memory symbol) = PoolOps.creatureFor(1);
        string memory name = LaunchLib.displayName(rawName);

        // 1. Deploy the generation's fixed-supply token (plain CREATE — audit A-01)
        (token, ) = _deployToken(name, symbol, 1, address(0));
        currentToken = token;
        generationToken[1] = token;
        // generationQuote[1] stays address(0) = native ETH. Generation 1 launches
        // from the presale before any proposal exists to name a quote, and the
        // mapping already defaults to zero, so writing it would only cost gas.

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

        // 3. Create the pool + seed. Default = GREEN-CANDLE buy: seed 100% active at
        //    a deep discount, then buy the reserve back out and re-park it out of
        //    range → a REAL first-block market buy (visible candle). If progressive
        //    seeding is armed (seeder + window), the active tranche instead streams
        //    in over the window (see _seedGeneration). Either way the reserve backs
        //    migration/genesis 1:1. Registry is opener + tax-exempt so a buy isn't taxed.
        poolId = _seedGeneration(token, activeTokens, msg.value, reserveTokens, 1);

        // 3b. PRIME BUY — if the owner pre-funded personal ETH (fundPrimeBuy), do a
        //     REAL first-block market buy of the fresh pool and route the bought
        //     GNOME to the treasury/airdrop wallet (net demand + zero dilution; the
        //     treasury airdrops it to OG holders later). Runs AFTER the reseed so it
        //     hits the exact expected starting price. Registry is opener + tax-exempt
        //     so the buy pays no fee/surtax.
        if (primeBuyEth > 0) {
            uint256 amt = primeBuyEth;
            primeBuyEth = 0;
            // Prefer the treasury/airdrop wallet; fall back to the funder if unset.
            address to = airdropWallet != address(0) ? airdropWallet : primeFunder;
            _seedBuyUnlocked = true;
            PoolOps.primeBuy(poolManager, generationPoolKey[1], amt, to);
            _seedBuyUnlocked = false;
        }

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

        // 2b. AUTO-MIGRATE PERPS (set-and-forget): force-close every open position
        //     WHILE THE OLD POOL IS STILL ALIVE (settlement swaps need it), oldest-
        //     first + deterministic inside the engine. Best-effort — a revert here
        //     can NEVER brick the rebirth (the manual forceCloseDead path remains).
        //     The engine is tax-exempt, so these swaps don't touch the hook fee /
        //     legacy buyback (no nesting). `isDead` was checked ONCE above, so the
        //     force-close volume can't re-gate the rebirth.
        _perpHousekeep(false); // force-close all (old pool alive)

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
        //     GAS-CAPPED + try/catch (audit Z-07): an unbounded mint loop must never
        //     starve the rebirth. Bounded to RELAUNCH_TICKETS with a reserved tail;
        //     the remainder is drained by the permissionless resolveTickets path.
        if (gasleft() > RELAUNCH_TAIL_RESERVE) {
            try hook.resolveTickets{gas: gasleft() - RELAUNCH_TAIL_RESERVE}(RELAUNCH_TICKETS) {} catch {}
        }

        // 3b. Close the dead brew's floor vault: NFT redemption stops and the
        //     remaining floor ETH sweeps here to seed the next launch.
        // 4. The dying generation's floor vault. It is CLOSED later, inside
        //    `PoolOps.seedFunding`, together with the two hook reserve pulls —
        //    none of them may happen until the quote the newborn will actually be
        //    priced in is known, or native ether gets dragged out of the hook to
        //    fund a pool denominated in something it cannot be spent on. (They
        //    also live there because this registry could not afford three
        //    try/catch blocks under EIP-170.) The solvency check that used to be
        //    here now sits next to `markConsumed`, where it can read the real
        //    funded figure instead of a proxy.

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
        //  ── THE QUOTE IS A REQUEST, NEVER AN INSTRUCTION (red-team B-05) ─────
        //
        //  `spec.quote` is attacker-chosen: anyone may propose. It used to be
        //  carried through with only an allowlist re-check, and handed to a seeder
        //  that was written entirely for native ether. That combination was a
        //  permanent, unrecoverable freeze of the whole protocol — FOUR unguarded
        //  reverts in sequence, every one of them BEHIND `governor.markConsumed`
        //  below, so the revert rolled the consumption back, the same proposal won
        //  `_bestUnconsumed()` forever, and every later relaunch died identically:
        //
        //    1. the seed amount was `ethFromLP + ethFromHook + vaultSwept` —
        //       native wei, every term, with nothing converting or rescaling it.
        //       The registry held none of the named quote, so the PositionManager's
        //       pull reverted: measured
        //       ERC20InsufficientBalance(registry, 0, 19999999999999987150), i.e.
        //       20 ETH requested verbatim as USDG (6 decimals in the live
        //       manifest, so also off by 1e12 had it held any).
        //    2. `PoolOps.removeAll` measured recovery as `address(this).balance`,
        //       which does not move when currency0 arrives as an ERC20 — so a
        //       non-native generation reported ZERO recovered and tripped
        //       `NoLiquidityToSeed()`. Masked by the others; found while building
        //       the fix.
        //    3. the green-candle buy settled native ether into a pool whose
        //       currency0 is an ERC20 → `CurrencyNotSettled()`.
        //    4. `hook.setLiveKey` refused any non-native key.
        //
        //  Reachable with no attacker at all: `indexer/deployments/round.json`
        //  advertises USDG and xNVDA as selectable `quoteAssets`, so a proposer
        //  choosing an offered option was enough to end the protocol.
        //
        //  ALL FOUR ARE NOW FIXED, so a non-native rebirth is real rather than
        //  aspirational. What keeps it safe is that the attacker-chosen field is
        //  narrowed twice before it can move value, and neither narrowing can
        //  revert:
        //
        //    HERE — the allowlist is re-checked, because it can change while a
        //    proposal is out for vote and the check that matters is the one at the
        //    moment liquidity moves. A de-listed quote degrades to native.
        //
        //    BELOW — `PoolOps.seedFunding`, once the token is mined, narrows the
        //    request to what the protocol ACTUALLY HOLDS and pulls exactly the
        //    reserve that funds it. A quote nobody can fund degrades to one we
        //    can. That is the same clamp-never-revert discipline as `nftSupply`
        //    (below), `newActive` (step 8) and the mining fallback
        //    (PoolOps.deployTokenAbove), now extended to the last input that was
        //    carried through unclamped.
        address specQuote = spec.quote;
        if (specQuote != address(0) && !allowedQuote[specQuote]) specQuote = address(0);
        string memory name = spec.name;
        string memory symbol = spec.symbol;
        mode = spec.mode;
        baseURI = spec.baseURI;
        renderer = spec.renderer;
        // CLAMP, never revert (audit C-02): an out-of-range supply would revert in
        // the collection constructor, which rolls `markConsumed` back with the tx —
        // so the poisoned proposal would win again forever and freeze the machine.
        // The governor bounds this too; clamping here survives a governor swap.
        if (spec.nftSupply > 0) {
            nftSupply = spec.nftSupply > MAX_NFT_SUPPLY ? MAX_NFT_SUPPLY : spec.nftSupply;
        }
        uint256 volPerNFT = spec.volumePerNFT; // proposer's mint-out volume target

        // Brand: "<name> by Magic Internet Frens" (hardcoded suffix on-chain).
        name = LaunchLib.displayName(name);

        // 7. Deploy the new generation's token (plain CREATE — audit A-01)
        (token, specQuote) = _deployToken(name, symbol, newGen, specQuote);
        currentToken = token;
        generationToken[newGen] = token;

        //  7b. WHAT CAN WE ACTUALLY SEED WITH? (red-team B-05)
        //
        //  Mining runs FIRST because it is the step that can still downgrade the
        //  quote on its own (no salt lands above a pathological asset → it returns
        //  native, PoolOps.deployTokenAbove). Funding runs SECOND so it decides
        //  against the quote that survived, and — critically — so the reserve it
        //  pulls matches the pool that will exist. Pulling before this point drags
        //  native ether out of the hook to fund a pool that may end up denominated
        //  in USDG, where it cannot be spent.
        //
        //  Order also matters for correctness in the other direction: whatever
        //  `seedFunding` returns, the token already sorts ABOVE it, because mining
        //  targets QUOTE_WATERMARK rather than the specific quote and no
        //  allowlistable quote sits at or above that watermark. So a downgrade here
        //  can never invert the pool's currency order.
        //
        //  `totalETH` keeps its name for the native case it is usually carrying,
        //  but it is now denominated in `specQuote`'s OWN units.
        uint256 totalETH;
        uint256 vaultSwept;
        //  `oldQuote` is the denomination `ethFromLP` is MEASURED IN, which is the
        //  primary pair's own currency0 — NOT `generationQuote[oldGen]`. A
        //  completed rotation flips that mapping to the destination asset while
        //  the primary position (and the redemption reserve sharing its key) stay
        //  in the launch pair, so the two disagree exactly when a rotation has
        //  happened. Passing the flipped value asked the seeder for an
        //  ETH-magnitude number denominated in an asset this registry did not
        //  hold: `TRANSFER_FROM_FAILED`, permanently (red-team R-02).
        (specQuote, totalETH, vaultSwept) = PoolOps.seedFunding(
            address(hook),
            specQuote,
            Currency.unwrap(generationPoolKey[oldGen].currency0),
            ethFromLP,
            generationVault[oldGen]
        );

        //  ── THE SOLVENCY CHECK, AND THE CONSUMPTION, IN THAT ORDER ──────────
        //  `markConsumed` used to sit ~50 lines above, immediately after
        //  `governor.winner()`. That made every step between it and the seed a
        //  potential PERMANENT freeze: a revert rolls the consumption back, the
        //  same proposal keeps winning `_bestUnconsumed()`, and every later
        //  relaunch dies identically. Four of the findings in this pass were
        //  exactly that shape.
        //
        //  It is moved HERE, as late as the logic allows, for two reasons. It
        //  shortens the fatal window to (collection deploy → seed), and it lets the
        //  "is there anything to seed with?" question be asked about the REAL
        //  funded amount rather than a three-source proxy that had to be evaluated
        //  before the funding was known. Everything between the old position and
        //  this one is now total by construction: `_deployToken` cannot revert
        //  (plain CREATE, with a native fallback when mining fails) and
        //  `seedFunding` catches both reserve pulls and the vault close.
        //
        //  Reverting on the LEFT of this line is safe and recoverable — the
        //  proposal stays live and a later call can succeed once the machine has
        //  value. Reverting on the RIGHT is what must never happen.
        if (totalETH == 0) revert NoLiquidityToSeed();
        governor.markConsumed(winId);

        // The quote is fixed for this generation's whole life: the engine, the
        // seeder and the floor all read it long after a later generation has
        // launched against something else.
        generationQuote[newGen] = specQuote;

        // PROPOSER FLYWHEEL: record the winning author + point the hook's proposer
        // slice at them, so THIS iteration's volume trickles a tiny fee to whoever
        // proposed it (decentralized incentive to keep the machine moving).
        generationProposer[newGen] = spec.proposer;
        generationParent[newGen] = oldGen; // V1 linear chain; V2 branch graph seam
        hook.setActiveProposer(spec.proposer);

        // 8. Seed TWO positions for the newborn. The new ACTIVE band mirrors the
        //    tokens RESCUED from the dead LP (so depth tracks what survived the
        //    prior gen), MINUS the still-unclaimed genesis airdrop (which must stay
        //    claimable). The RESERVE is everything else = migration demand +
        //    unclaimed genesis — DYNAMIC, sized to actual need, not a fixed
        //    fraction. Conserves exactly: reserve(=TOTAL−newActive) covers the old
        //    circulating supply migrating 1:1 PLUS the OG airdrop carryover.
        // Fold the OG share of iteration-#2 live buybacks into the redemption floor
        // BEFORE sizing, so the new reserve covers the grown OG entitlement and the
        // OG floor "moons" into the new iteration alongside the forged floor.
        genesisReserveOutstanding += genesisPending;
        genesisPending = 0;
        uint256 unclaimedGenesis = genesisReserveOutstanding;
        //  `degenerate` is the SAME test, kept so the branch can be reported below
        //  rather than only taken (red-team S0xTSa).
        bool degenerate = tokensFromLP <= unclaimedGenesis;
        uint256 newActive = degenerate
            ? tokensFromLP // degenerate guard (near-total migration) — never 0-seed
            : tokensFromLP - unclaimedGenesis;
        // OBSERVABLE UNDER-COVERAGE (audit F-06). The Z-12 fix made the LEGACY
        // shortfall observable but left this twin fallback silent, and it is the more
        // dangerous of the two: it fires when the dead pool returned NOTHING
        // (`tokensFromLP == 0` — a fully drained book, or a progressive generation
        // whose teardown recovered no token), and it hard-sets the active band to 80%
        // of supply. `newReserve` is then only 20% of supply while migration demand is
        // ~100%, so the exit guarantee silently degrades to first-come-first-served
        // and late migrants hit `reserve short`. Reuse the same signal the legacy path
        // emits so an indexer/monitor sees BOTH shortfall shapes.
        if (newActive == 0) {
            emit ReserveShortfall(newGen, unclaimedGenesis, 0);
            newActive = GEN1_ACTIVE_TOKENS; // ultra-rare fallback
        } else if (degenerate) {
            //  THE SAME SHORTFALL, ONE STEP LESS EXTREME, AND IT WAS SILENT.
            //  The guard above only reported `tokensFromLP == 0`. The band
            //  `0 < tokensFromLP <= unclaimedGenesis` takes the degenerate branch
            //  too — `newActive` keeps the WHOLE recovered amount and the genesis
            //  airdrop is never carved out — so `newReserve` is short by
            //  `unclaimedGenesis` and late genesis claimants hit "reserve short"
            //  (PoolOps.sol:1378) with nothing anywhere having said so.
            emit ReserveShortfall(newGen, unclaimedGenesis, newActive);
        }

        // 8b. LEGACY FLOOR: flush any un-materialized live buybacks into the dying
        //     collection's ledger FIRST (so sizing covers them), crystallize it, then
        //     carve its reserve out of the new active supply.
        if (address(collectionLedger) != address(0)) {
            _flushLegacyAtRelaunch(oldGen, oldToken);
            PoolOps.crystallizeCollection(
                address(collectionLedger), generationCollection[oldGen], generationVault[oldGen],
                oldGen, vaultSwept, newActive, totalETH
            );
            uint256 legacy = collectionLedger.totalEntitled();
            // CLAMP-TO-ZERO, not skip (audit Z-12). The old `newActive > legacy ?
            // newActive - legacy : newActive` SKIPPED the subtraction entirely when
            // legacy >= newActive, so the reserve was not enlarged for the legacy
            // claim at all and the shortfall was silent. Now: subtract when we can,
            // and when the entitlement meets/exceeds the active supply, enlarge the
            // reserve maximally and EMIT so the under-coverage is observable. The
            // active-pool floor below (GEN1_ACTIVE_TOKENS) keeps the newborn pool
            // tradeable; proportional haircutting across claimants is an owner policy.
            if (newActive > legacy) {
                newActive -= legacy;
            } else {
                emit ReserveShortfall(newGen, legacy, newActive);
                newActive = 0;
            }
            if (newActive == 0) newActive = GEN1_ACTIVE_TOKENS;
        }
        // CLAMP (audit A-05). `newActive` is derived from what the DEAD pool gave
        // back, and that can exceed the fixed supply: `PoolOps.removeAll` collects
        // accrued FEES along with principal, so anyone who calls
        // `poolManager.donate()` on the live pool inflates the recovered amount.
        // The newborn only ever holds TOTAL_SUPPLY, so an un-clamped
        // `TOTAL_SUPPLY - newActive` would UNDERFLOW and revert — permanently
        // bricking `relaunch()` (and rolling back `markConsumed` with it, so the
        // same proposal keeps winning). Clamping keeps the rebirth alive; the
        // surplus simply stays with the registry.
        if (newActive > TOTAL_SUPPLY) newActive = TOTAL_SUPPLY;
        uint256 newReserve = TOTAL_SUPPLY - newActive;

        // 9. Seed the newborn. Default: the migration reserve is funded by a REAL
        //    first-block buy (green candle) — seed 100% active at a deep discount,
        //    buy `newReserve` out, re-park it out of range → active LP lands at
        //    exactly (newActive, totalETH) with the reserve arriving as visible
        //    volume. If progressive seeding is armed, the active tranche streams in
        //    over the window instead (reserve placed silently). See _seedGeneration.
        poolId = _seedGeneration(token, newActive, totalETH, newReserve, newGen);

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

        // Re-arm the perp engine on the NEW token: migrate its dead-token inventory
        // 1:1 (from the reserve just seeded) + reset its TWAP. openCount is now 0
        // (force-closed in step 2b). Best-effort — never bricks the rebirth.
        _perpHousekeep(true); // sync to the new gen

        emit CauldronReborn(newGen, token, poolId, name, symbol);
    }

    /// @dev Best-effort perp relaunch housekeeping (reads the engine off the hook,
    ///      so the registry needs no engine pointer). `sync=false` → force-close all
    ///      dead positions (old pool alive); `sync=true` → re-arm on the new token.
    ///      try/catch so it can NEVER brick the rebirth.
    function _perpHousekeep(bool sync) private {
        if (sync) {
            address eng = hook.perpEngine();
            if (eng != address(0)) { try IPerpSync(eng).syncGeneration() {} catch {} }
        } else {
            // The HOOK force-closes all perps behind a transient "relaunch-close"
            // flag that makes it skip the fee + legacy buyback ONLY for that window
            // (so the dying-pool settlement swaps don't nest). Perp swaps stay fully
            // fee-paying the rest of the time — high-volume revenue is preserved.
            // try/catch + GAS CAP (audit Z-07): a full book (64 × ~450k settlement)
            // can exceed a block, and without a cap the 63/64 rule would leave the
            // parent too little to finish the rebirth. Reserve the tail so an
            // over-large force-close is bounded.
            //  NOT `try`-WRAPPED, AND THAT IS THE POINT. Swallowing this call is
            //  what let a gas-starved relaunch strand the whole perp book: the
            //  close is all-or-nothing, so an OOG mid-loop reverts every settle
            //  it had done, and the survivors can NEVER be cleared afterwards
            //  (`forceCloseDead` is gated on an `_isDead()` that keys off the
            //  now-live newborn token, and `_settle` would have to swap against
            //  a pool this relaunch has already drained). Measured: at a 12M gas
            //  cap, 64 of 64 positions survived and were locked permanently.
            //
            //  {CauldronHook.forceClosePerps} is total EXCEPT for that one
            //  condition — it returns early with no engine wired and swallows
            //  the benign `NotDead` of an already-empty book — so the only thing
            //  that propagates here is a genuine survivor (or an OOG). Letting
            //  it revert rolls the whole rebirth back, `markConsumed` included,
            //  leaving the winning proposal live for a retry with more gas. The
            //  work is bounded (64-position book, ~7.5M gas), so a retry always
            //  fits in a block and this can never wedge the machine.
            uint256 g = gasleft();
            if (g > RELAUNCH_TAIL_RESERVE) {
                hook.forceClosePerps{gas: g - RELAUNCH_TAIL_RESERVE}();
            }
        }
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
        generationVault[gen] = vlt; // kept for crystallize's supply count (holds no ETH)
        hook.setCollection(col);
        // UNIFIED FLOOR: no ETH vault — route the fee floor-share into the token
        // buyback buffer (setVault(0)); the vault stays deployed only as a supply
        // counter for crystallize.
        hook.setVault(address(0));
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
        // The continuation vault serves ONLY the forged tranche (ids > genesisShares)
        // — the OGs have their own dividend + redemption floor and must not dilute
        // or draw this one, so the vault's floorOffset = genesisShares.
        address vlt = factory.deployVault(col, address(this), genesisShares);
        generationCollection[gen] = col;
        generationVault[gen] = vlt; // kept for crystallize's supply count (holds no ETH)
        IMiFrensContinuable(col).setVault(vlt);
        IMiFrensContinuable(col).setMinter(address(hook));
        hook.setCollection(col);
        hook.setVault(address(0)); // unified floor: fee floor-share → token buyback
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
    // NOTE: NOT nonReentrant — it burns the caller's tokens then pulls the same 1:1
    // from the reserve via the (trusted) PositionManager; neither calls back into
    // arbitrary code, so there's no reentrancy vector. Dropping the guard also lets
    // the perp engine's syncGeneration migrate its inventory DURING relaunch (which
    // holds the registry's reentrancy lock) — the "stake & chill" auto-migrate.
    function claimByBurn(uint256 fromGen, uint256 amount)
        external
        returns (uint256 claimedAmount)
    {
        if (fromGen == 0 || fromGen >= currentGeneration) revert CannotClaimCurrentGen();
        // Anti-dump gate: when a vesting escrow is set, the instant direct path is
        // closed to ordinary holders — they must migrate through the escrow (which
        // drips the claim). The perp engine is exempt so its own inventory
        // migration during relaunch (via syncGeneration) is never blocked.
        if (claimGate != address(0) && msg.sender != claimGate && msg.sender != hook.perpEngine()) {
            revert VestingEnforced();
        }
        address prevToken = generationToken[fromGen];
        if (prevToken == address(0)) revert UnknownGeneration();
        if (amount == 0 || IERC20(prevToken).balanceOf(msg.sender) < amount) revert NoBalance();

        // Burn old, release the same 1:1 from the reserve (out of range → no price
        // move, no mint). A short reserve reverts, rolling the burn back with it.
        uint256 g = currentGeneration;
        claimedAmount = PoolOps.migrateOne(
            IPositionManagerOps(address(positionManager)), prevToken, msg.sender, amount,
            ReserveRef(generationReservePositionId[g], generationPoolKey[g], reserveTickLower[g], reserveTickUpper[g])
        );
        emit HolderClaimed(fromGen, msg.sender, claimedAmount);
    }

    /// @notice CAPACITY-AWARE 1:1 migration: burn up to `maxAmount` of `fromGen`
    ///         and receive exactly that much of the live token, but never more than
    ///         the reserve can actually deliver. Returns the amount migrated.
    ///
    ///  This exists for the PERP ENGINE's own inventory sync. `claimByBurn` is
    ///  strict — it burns `amount` and REVERTS if the reserve is short (audit H-03,
    ///  which is what protects ordinary holders from a silent partial fill). But
    ///  the engine migrates its whole book in one shot at every relaunch, so a
    ///  strict call would revert inside `syncGeneration`'s try/catch and leave the
    ///  engine stranded on a dead token. Sizing to capacity first gives it a partial
    ///  migration that is still exactly 1:1 on every wei it does burn.
    ///  Same gating as `claimByBurn`: the vesting escrow and the engine are exempt.
    ///  ── THE BODY MOVED TO {RedemptionExt} (EIP-170) ───────────────────────
    ///  This contract had 15 bytes of margin and the `recoverLegs` forwarder below
    ///  needs ~150. This function is the cheapest thing to move that is worth more
    ///  than its own stub: it is redemption, which is what the facet is for, and it
    ///  touches nothing but {CauldronBase} storage and {PoolOps}. Behaviour,
    ///  authority and ABI are identical - a delegatecall runs it on this registry's
    ///  storage and custody.
    function claimByBurnUpTo(uint256, uint256) external returns (uint256) {
        _forwardToExt();
    }

    // -----------------------------------------------------------------------
    // AUTO-MIGRATE -- hands-off, keeper-executed migration (opt-in)
    // -----------------------------------------------------------------------

    // NOTE: `AUTO_MIGRATE_FEE` + `autoMigrate` now live in {CauldronBase} (autoMigrate
    // is storage slot 40 — the last of the shared baseline layout).

    event AutoMigrateSet(address indexed who);
    event AutoMigrated(uint256 indexed fromGen, address indexed holder, uint256 amount);

    /// @notice Opt in to hands-off migration: a keeper migrates your balance into
    ///         each new iteration for you, so you never have to click. FREE for
    ///         frens (any MiFren holder); 0.069 ETH for everyone else (the fee
    ///         stays in the registry and seeds the next launch).
    function enableAutoMigrate() external payable {
        // Frens (any MiFren holder) opt in free; everyone else pays the fee. When
        // `mifrens` is unset (the genesis bonus is opt-in and may never be wired),
        // there is no fren tier → charge the fee for everyone. Guard the zero
        // address so we never `balanceOf` a non-contract (which reverts).
        if (mifrens == address(0) || IERC721(mifrens).balanceOf(msg.sender) == 0) {
            if (msg.value < AUTO_MIGRATE_FEE) revert Fee();
        }
        autoMigrate[msg.sender] = true;
        emit AutoMigrateSet(msg.sender);
    }

    /// @notice Revoke the hands-off migration consent (audit F-02).
    ///
    ///  `enableAutoMigrate` is an IRREVOCABLE grant without this. The flag is the
    ///  ONLY thing standing between a wallet and `autoMigrateBatch`, which calls
    ///  `CauldronToken.burn(holder, balance)` — a registry-only primitive that needs
    ///  no allowance — so an opted-in wallet's entire old-generation balance can be
    ///  burned by ANY permissionless keeper, at ANY future relaunch, at a moment the
    ///  holder did not choose. That directly contradicts the migration contract's
    ///  own stated model ("Migration is a choice, not a requirement... old tokens are
    ///  never frozen, so a holder who prefers a past iteration simply keeps it"): a
    ///  holder who decides they prefer iteration N had no way to stop the machine
    ///  from converting them into iteration N+1. Consent must be withdrawable.
    ///
    ///  Free (revoking a permission must never be gated behind a fee) and effective
    ///  immediately: `PoolOps.autoMigrateBatch` reads the flag per holder, per call.
    ///  Re-opting in costs the fee again, exactly as the first time.
    function disableAutoMigrate() external {
        autoMigrate[msg.sender] = false;
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
        // The keeper auto-migrate delivers INSTANTLY to holders, so it's a vesting
        // bypass — disabled while the escrow gate is on. Holders instead approve the
        // {MigrationVesting} escrow and a keeper calls its `vestBatch`.
        if (claimGate != address(0)) revert VestingEnforced();
        address prevToken = generationToken[fromGen];
        if (prevToken == address(0)) revert UnknownGeneration();
        uint256 g = currentGeneration;
        PoolOps.autoMigrateBatch(
            IPositionManagerOps(address(positionManager)), prevToken, fromGen, holders,
            ReserveRef(generationReservePositionId[g], generationPoolKey[g], reserveTickLower[g], reserveTickUpper[g])
        );
    }

    // NOTE: the old `burnUnclaimed` is obsolete in the reserve-LP model — a dead
    // generation's un-migrated supply lives in its LP positions, which relaunch
    // removes + burns wholesale (see _removeLiquidity), so nothing lingers in a
    // wallet to sweep.

    // -----------------------------------------------------------------------
    // GENESIS RECYCLE-REDEMPTION -- delegatecall forwarders → {RedemptionExt}
    // -----------------------------------------------------------------------
    //
    // The OG-redemption ops (redeemOgFren / buyTreasuryOgFren / donateToReserve /
    // materializeLegacyReserve) live in the {RedemptionExt} facet — extracted to
    // reclaim EIP-170 headroom for the progressive-seed wiring. The registry keeps
    // THIN forwarders that DELEGATECALL the facet with the original calldata: the
    // facet's code runs in THIS registry's context (its storage, its custody, and
    // it is the msg.sender the PositionManager / MiFrens see), so custody +
    // accounting semantics are byte-for-byte what they were in the monolith.
    //
    // ⚠️ Reentrancy: the facet functions keep their own `nonReentrant`, which runs
    //    against the registry's ReentrancyGuard slot (shared via CauldronBase).
    //    The forwarders therefore must NOT be `nonReentrant` — a guard here would
    //    double-lock and revert every redemption. See CauldronBase + RedemptionExt.

    /// @notice RECYCLE a genesis (OG) MiFren for its LIVE floor share of whatever
    ///         token the machine is running. OG-only; NFT moves to treasury (not
    ///         burned) to be resold at 2× via {buyTreasuryOgFren}. See RedemptionExt.
    function redeemOgFren(uint256) external returns (uint256) {
        _forwardToExt();
    }

    /// @notice BUY a treasury-held (recycled) genesis fren for 2× the live floor,
    ///         paid in the current token → added to the reserve (floor ratchets up).
    function buyTreasuryOgFren(uint256) external returns (uint256) {
        _forwardToExt();
    }

    /// @notice Permissionlessly GROW the genesis floor: donate current token into
    ///         the reserve (caller must approve first). See RedemptionExt.
    function donateToReserve(uint256) external {
        _forwardToExt();
    }

    /// @notice Permissionless: deposit the hook's held live-buyback tokens into the
    ///         shared reserve LP + credit the collection ledger. See RedemptionExt.
    function materializeLegacyReserve() external returns (uint256) {
        _forwardToExt();
    }

    //  ── THERE IS NO CATCH-ALL FALLBACK, SO FACET CALLS NEED A STUB ─────────
    //  I moved these three to {RedemptionExt} for EIP-170 headroom on the
    //  assumption that "the fallback delegates unknown selectors". It does not:
    //  this contract declares `receive()` and no `fallback()`, and every
    //  forwarded function above is an EXPLICIT stub. Without one, the call dies
    //  as "unrecognized function selector ... which has no fallback function" —
    //  which is exactly how F04 caught it, and would otherwise have shipped as a
    //  view the frontend calls on every treasury poll.
    //
    //  Stubs are cheap (a selector and a jump); the BODIES are what did not fit.

    /// @notice Whether the genesis redemption floor is claimable at spot right now,
    ///         and the current per-fren floor. See RedemptionExt.
    function floorClaimableNow() external returns (bool, uint256) {
        _forwardToExtView();
    }

    /// @notice How many rotated legs a generation holds beyond its primary pool.
    function legCount(uint256) external returns (uint256) {
        _forwardToExtView();
    }

    /// @notice Read one leg: quote, position id, and the pool it sits in.
    function legAt(uint256, uint256) external returns (address, uint256, PoolKey memory) {
        _forwardToExtView();
    }

    /// @dev View-side forwarder.
    ///
    ///  Solidity refuses `delegatecall` inside a `view` body, in assembly too —
    ///  so the stubs above are NOT `view`. They are `nonpayable` reads, which an
    ///  eth_call serves exactly as before: `registry.floorClaimableNow()` from
    ///  ethers/viem/cast is a call, not a transaction, and the node discards any
    ///  state change. The only cost is that a SOLIDITY caller must not expect a
    ///  `view` in an interface, which is why every internal reader uses
    ///  `floorPerFren()` (genuinely view, on CauldronBase) instead.
    function _forwardToExtView() private {
        _forwardToExt();
    }

    /// @dev Forward the FULL calldata (selector + args) to the RedemptionExt facet
    ///      via DELEGATECALL — the facet executes on this registry's storage +
    ///      custody — bubbling its return data / revert verbatim. `redemptionExt`
    ///      is set once at deploy and frozen; a zero target is rejected because a
    ///      delegatecall to an empty account returns SUCCESS with no data (which
    ///      would make an unset facet silently no-op instead of reverting).
    function _forwardToExt() private {
        address ext = redemptionExt;
        if (ext == address(0)) revert NotConfigured();
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), ext, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // -----------------------------------------------------------------------
    // LEGACY FLOOR -- volume collections keep their fee value forever
    // -----------------------------------------------------------------------

    event CollectionRecycled(uint256 indexed gen, uint256 indexed tokenId, address indexed holder, uint256 payout);
    event CollectionBought(uint256 indexed gen, uint256 indexed tokenId, address indexed buyer, uint256 paid);

    /// @notice Wire the legacy-floor cap table (one-time, owner/deployer). Zero
    ///         keeps the legacy floor OFF (collections behave exactly as before).
    function setCollectionLedger(address ledger) external onlyOwner {
        collectionLedger = ICollectionLedger(ledger);
    }

    /// @notice The hook reports a live buyback: record the bought tokens against the
    ///         CURRENT collection's pending legacy entitlement (folded in at death).
    ///         Hook-only; no-op if the ledger isn't wired.
    ///
    ///  ITERATION #2 is special — it CONTINUES the MiFrens collection, so OGs
    ///  (1..genesisShares) and forged frens (>genesisShares) share it. To keep the
    ///  OGs senior, the buyback is SPLIT so both floors rise at the SAME per-fren
    ///  rate (∝ fren count): the forged share → the ledger, the OG share → the
    ///  genesis reserve (via genesisPending, folded at the next relaunch). Because
    ///  the OG floor starts higher (the 20% seed + recycle ratchets), it stays >=
    ///  the forged floor forever. Any other iteration → all to the collection ledger.
    /// @dev At relaunch, flush the hook's un-materialized live-buyback tokens for the
    ///      DYING gen: credit its ledger with the amount (value carries as a NUMBER —
    ///      the new reserve is sized below to cover the grown totalEntitled in the new
    ///      token) and BURN the swept dead-gen tokens along with the LP recovery.
    ///      Keeps a collection's last buybacks in its floor even if no keeper called
    ///      materializeLegacyReserve before death.
    function _flushLegacyAtRelaunch(uint256 oldGen, address oldToken) private {
        ReserveRef memory empty; // unused on the burn path (toReserve = false)
        (, uint256 og) = PoolOps.materializeLegacy(
            IPositionManagerOps(address(positionManager)), address(hook), address(this),
            address(collectionLedger), mifrens, genesisShares, oldGen, generationCollection[oldGen],
            oldToken, empty, false
        );
        genesisPending += og;
    }

    /// @notice RECYCLE a dead collection's NFT for its live-token floor. Pays the
    ///         floor from the shared reserve and moves the NFT to the treasury (the
    ///         registry) to be resold at 2× — NOT burned. Mirrors the genesis
    ///         recycle, but the floor is this collection's ledger entitlement.
    function recycleCollectionNFT(uint256 gen, uint256 tokenId)
        external nonReentrant returns (uint256 amount)
    {
        if (_redeemBlocked()) revert RedemptionPaused();
        address col = generationCollection[gen];
        //  The OG tranche may not draw the FORGED tranche's floor; the guard
        //  lives in {PoolOps.recycleCollection}, which has the EIP-170 room and
        //  sits next to the ledger accounting it protects.
        if (address(collectionLedger) == address(0) || col == address(0)) revert BadConfig();
        uint256 g = currentGeneration; // pay in the LIVE token, from the shared reserve
        amount = PoolOps.recycleCollection(
            IPositionManagerOps(address(positionManager)),
            address(collectionLedger), col, gen, tokenId, msg.sender,
            ReserveRef(generationReservePositionId[g], generationPoolKey[g], reserveTickLower[g], reserveTickUpper[g])
        );
        emit CollectionRecycled(gen, tokenId, msg.sender, amount);
    }

    /// @notice BUY a treasury-held (recycled) collection NFT for 2× its floor, paid
    ///         in the live token → added to the reserve → the collection's floor
    ///         ratchets up for every remaining NFT.
    function buyCollectionNFT(uint256 gen, uint256 tokenId)
        external nonReentrant returns (uint256 paid)
    {
        address col = generationCollection[gen];
        if (address(collectionLedger) == address(0) || col == address(0)) revert BadConfig();
        uint256 g = currentGeneration;
        paid = PoolOps.buyCollection(
            IPositionManagerOps(address(positionManager)),
            address(collectionLedger), col, generationToken[g], gen, tokenId, msg.sender,
            ReserveRef(generationReservePositionId[g], generationPoolKey[g], reserveTickLower[g], reserveTickUpper[g])
        );
        emit CollectionBought(gen, tokenId, msg.sender, paid);
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

        // ACTIVE position. For a PROGRESSIVE gen this is 0 (the seeder owns the N
        // mini-positions instead) — skip the pm call so it never touches token id 0.
        uint256 activeId = generationPositionId[gen];
        if (activeId != 0) {
            (ethRecovered, tokensRecovered) = PoolOps.removeAll(pm, activeId, key, deadToken);
        }

        uint256 rid = generationReservePositionId[gen];
        if (rid != 0) {
            (uint256 e2, uint256 t2) = PoolOps.removeAll(pm, rid, key, deadToken);
            ethRecovered += e2;
            tokensRecovered += t2;
        }

        // PROGRESSIVE TEARDOWN: unwind the seeder's N mini-positions (whatever mix
        // of ETH + token they hold after trading) + any un-streamed ledger-A funds,
        // back to this registry, so a streamed generation is recovered in full at
        // relaunch with nothing stranded. The seeder only ever holds ledger A (the
        // 69× redemption reserve is a separate pool position it can't touch). Safe to
        // skip when the seeder is unset or idle (e.g. an atomic generation).
        address _seeder = seeder;
        if (_seeder != address(0) && ISeeder(_seeder).seeding()) {
            (uint256 e3, uint256 t3) = ISeeder(_seeder).withdrawAll(address(this));
            ethRecovered += e3;
            tokensRecovered += t3;
        }

        //  ROTATED LEGS. A generation that rotated holds liquidity in pools the
        //  three recoveries above know nothing about: the primary, the reserve
        //  and the seeder's bands are all this function ever unwound, and a leg
        //  opened by `RedemptionExt.rotateSlice` is none of them. Half a treasury
        //  voted into a stable would have stayed in that pool through the
        //  rebirth, funding nothing.
        //
        //  Delegatecalled into the facet because the loop does not fit here —
        //  this contract has ~380 bytes of EIP-170 margin against the facet's
        //  ~14KB. Failure is swallowed for the same reason the facet swallows a
        //  single bad leg: recovery is worth attempting, and a rebirth that
        //  cannot happen is worse than one that recovers less than everything.
        address ext = redemptionExt;
        if (ext != address(0)) {
            //  Selector computed by the compiler, never written by hand. My
            //  first attempt hardcoded 0x9b0f6ef7 for this; the real one is
            //  0x03ebe66e, and a wrong selector here fails SILENTLY — the
            //  delegatecall returns false, the `if (ok)` skips, and every leg
            //  stays stranded exactly as before with nothing to show for it.
            (bool ok, bytes memory ret) =
                ext.delegatecall(abi.encodeWithSelector(RECOVER_LEGS, gen));
            if (ok && ret.length >= 64) {
                (uint256 e4, uint256 t4) = abi.decode(ret, (uint256, uint256));
                ethRecovered += e4;
                tokensRecovered += t4;
            }
        }
    }

    // -----------------------------------------------------------------------
    // Internal: Deploy the generation token
    // -----------------------------------------------------------------------

    /**
     * @dev Deploy a CauldronToken. Uses plain CREATE, NOT CREATE2 (audit A-01):
     *      a CREATE2 address keyed on the generation number is fully predictable
     *      before the deploy, so anyone could squat it and permanently brick
     *      `relaunch()`. See {PoolOps.deployToken}.
     */
    function _deployToken(
        string memory name,
        string memory symbol,
        uint256 gen,
        address want
    ) private returns (address token, address quoteUsed) {
        // Delegated to PoolOps so the 3.2 KB CauldronToken creation blob lives
        // there, not in this registry (EIP-170). Delegatecall keeps
        // address(this) = registry, so the registry is the deployer + token owner
        // — and, for a mined address, the CREATE2 deployer nobody else can be.
        //
        // The token is mined to sort ABOVE the quote so "quote = currency0" holds
        // for every pool. Whatever quote comes back is what was actually
        // achievable, so recording it here keeps generationQuote from ever
        // claiming a pair the pool was not built for.
        (token, quoteUsed) = PoolOps.deployTokenAbove(name, symbol, gen, TOTAL_SUPPLY, want);
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
    // NOTE: the old silent-seed `_createPoolAndSeed` was removed — BOTH genesis and
    // relaunch now use `_createPoolAndSeedWithBuy` (the green candle), so iteration #1
    // launches with a real first-block market buy like every rebirth. PoolOps still
    // exposes `createAndSeed` for reference / external callers.

    /**
     * @dev RELAUNCH seed variant: the migration reserve is funded by a real
     *      first-block market BUY (green candle) instead of a silent single-sided
     *      seed. See `PoolOps.createAndSeedWithBuy`. We arm `_seedBuyUnlocked` so
     *      the PoolManager's re-entry into `unlockCallback` (which drives the buy)
     *      is accepted for exactly this window and nothing else.
     */
    function _createPoolAndSeedWithBuy(
        address token,
        uint256 activeTokens,
        uint256 ethAmount,
        uint256 reserveTokens,
        uint256 gen
    ) private returns (PoolId poolId) {
        // Per-iteration ceiling: use the configured `next` value (default = 69×).
        // `_seedBuyUnlocked` is armed by the caller (`_seedGeneration`) for both
        // seed branches — see the note there.
        SeedResult memory r = PoolOps.createAndSeedWithBuy(
            poolManager, IPositionManagerOps(address(positionManager)), address(hook),
            token, activeTokens, ethAmount, reserveTokens,
            TICK_SPACING, POOL_FEE, nextReserveCeilingOffset,
            generationQuote[gen]
        );
        poolId = _recordSeed(r, gen);
    }

    /**
     * @dev Seed a generation's pool. Dispatches between two paths:
     *   - PROGRESSIVE (opt-in: `seeder != 0 && nextSeedWindow > 0`): place the
     *     reserve (ledger B) out-of-range in full, then hand the ACTIVE tranche
     *     (ledger A: ETH + tokens) to the persistent {CauldronSeeder}, which streams
     *     it into the pool over `nextSeedWindow`. No green-candle buy — the reserve
     *     is placed silently single-sided (the anti-snipe comes from the thin
     *     streamed book, not a candle). `activePositionId` is 0 (the seeder owns N
     *     mini-positions, torn down at relaunch via {ISeeder.withdrawAll}).
     *   - ATOMIC (default): the green-candle path, unchanged.
     * Delegatecalled PoolOps runs in the registry's context, so its token transfer
     * to the seeder + the seeder's `onlyRegistry` both resolve to this registry.
     */
    function _seedGeneration(
        address token,
        uint256 activeTokens,
        uint256 ethAmount,
        uint256 reserveTokens,
        uint256 gen
    ) private returns (PoolId poolId) {
        //  A non-native generation is handled INSIDE
        //  `PoolOps.createAndSeedProgressive`, which already receives the quote —
        //  the check lives there because this contract has single-digit bytes of
        //  EIP-170 margin. See that function for why it must degrade, not revert.
        // ARM THE BUY FOR BOTH BRANCHES. The progressive path now also drives a
        // green candle (PoolOps folds the reserve into the base tranche and buys it
        // out), so it re-enters `unlockCallback` exactly as the atomic path does.
        // Hoisting the flag here rather than adding a second pair of writes inside
        // the branch keeps this contract's bytecode flat — it has ~60 bytes of
        // EIP-170 margin, so `_createPoolAndSeedWithBuy` drops its own arming and
        // relies on this one.
        _seedBuyUnlocked = true;
        if (seeder != address(0) && nextSeedWindow > 0) {
            SeedResult memory r = PoolOps.createAndSeedProgressive(
                poolManager, IPositionManagerOps(address(positionManager)), address(hook),
                token, activeTokens, ethAmount, reserveTokens,
                TICK_SPACING, POOL_FEE, nextReserveCeilingOffset,
                SeedParams({seeder: seeder, gen: gen, window: nextSeedWindow}),
                generationQuote[gen]
            );
            poolId = _recordSeed(r, gen);
        } else {
            poolId = _createPoolAndSeedWithBuy(token, activeTokens, ethAmount, reserveTokens, gen);
        }
        _seedBuyUnlocked = false;
    }

    /// @dev Persist a freshly-seeded pool's positions/ticks under `gen`, and push the
    ///      LIVE key to the hook so its legacy buyback can only ever spend into THIS
    ///      pool (audit C-01b) — never into the key of whatever swap triggered it.
    function _recordSeed(SeedResult memory r, uint256 gen) private returns (PoolId poolId) {
        poolId = r.poolId;
        generationPoolId[gen] = r.poolId;
        generationPoolKey[gen] = r.key;
        generationPositionId[gen] = r.activePositionId;
        generationReservePositionId[gen] = r.reservePositionId;
        reserveTickLower[gen] = r.reserveTickLower;
        reserveTickUpper[gen] = r.reserveTickUpper;
        hook.setLiveKey(r.key);
    }

    /**
     * @notice PoolManager unlock hook — accepted ONLY while a relaunch buy is
     *         armed (`_seedBuyUnlocked`) and only from the PoolManager itself. The
     *         swap encoding lives in the linked `PoolOps` library (delegatecalled,
     *         so it runs in this registry's context: it settles the registry's ETH
     *         and receives the bought token).
     */
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        if (!_seedBuyUnlocked) revert NotPoolManager();
        return PoolOps.executeBuy(data);
    }

    // -----------------------------------------------------------------------
    // View Helpers
    // -----------------------------------------------------------------------

    //  `hasClaimed(uint256,address)` REMOVED. It read {CauldronBase.claimed},
    //  which has no writer anywhere in the tree, so it answered false for every
    //  holder of every generation — permanently, and silently. Nothing on-chain
    //  gates on it and nothing off-chain calls it (grepped src/, indexer/, api/,
    //  scripts/: the only `hasClaimed` hit is an unrelated field in the presale
    //  ABI). An integrator or a future claim button that trusted it would have
    //  shown every holder as never having claimed. Removing it makes that call
    //  fail loud instead of lying; the slot stays reserved, see CauldronBase.

    // NOTE: `floorClaimableNow` moved to {RedemptionExt} to reclaim EIP-170
    // bytecode for the rotation-leg recovery. The ABI is UNCHANGED: the fallback
    // delegatecalls any unknown selector to the facet, so `registry.
    // floorClaimableNow()` still answers exactly as before. It reads only
    // CauldronBase state, which the facet shares.

    // NOTE: `getCreatureForGeneration` moved fully into the linked PoolOps library
    // (`PoolOps.creatureFor`) to save registry EIP-170 bytecode — summon calls it
    // directly, tests call the library. Relaunches (gen 2+) name from the BrewSpec.
    // NOTE: `predictTokenAddress` (a frontend-convenience CREATE2 preview) was
    // removed to reclaim EIP-170 headroom — it had zero on-chain/frontend callers.
    // Token addresses are now non-deterministic by design (audit A-01); read the
    // live address from `currentToken()` / the CauldronSummoned|Reborn events.
}
