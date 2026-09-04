// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @dev Minimal view onto the registry's 1:1 migration primitive. `claimByBurn`
///      burns the CALLER's `fromGen` tokens and transfers the same amount of the
///      current-gen token to the CALLER from the out-of-range reserve LP. Because
///      the caller here is THIS escrow, the escrow custodies the new tokens and
///      can release them on a schedule.
interface IVestingRegistry {
    function currentGeneration() external view returns (uint256);
    function generationToken(uint256 gen) external view returns (address);
    function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256 claimedAmount);
}

/// @notice Pluggable "who claims instantly" policy. Return true for wallets that
///         have earned an unvested (instant) migration — e.g. perp PLV stakers,
///         enchanted-genesis holders. Swappable so the criteria can evolve without
///         redeploying the escrow (see {PerpStakerOracle}).
interface IStakerOracle {
    function isInstant(address who) external view returns (bool);
}

/**
 * @title MigrationVesting — anti-dump escrow for old-gen → new-gen claims
 * @author MagicFrens
 *
 *  A SELF-CONTAINED escrow that turns the registry's INSTANT 1:1 migration into a
 *  LINEAR VESTING DRIP, so an old iteration's holders cannot nuke a fresh
 *  relaunch's green candle in a single dump. It never touches the pool, never
 *  mints, and holds only the exact tokens the registry hands it — so it can ship
 *  independently of the launch machinery with zero launch risk.
 *
 *  ── Flow ──────────────────────────────────────────────────────────────────
 *   1. Holder approves this escrow to spend their DEAD-gen token, then calls
 *      {startVest}. The escrow pulls the dead tokens, calls the registry's
 *      {claimByBurn} (which burns them and hands the escrow the same amount of
 *      the LIVE token), and books a linear grant.
 *   2. {claim} releases the vested-so-far portion to the holder, pro-rata over
 *      `vestWindow` from the deposit timestamp.
 *
 *  ── Instant tier ─────────────────────────────────────────────────────────
 *   Wallets the {IStakerOracle} marks instant (default: anyone with a live perp
 *   PLV share — "stake & chill") get `window = 0`, i.e. fully claimable at once.
 *   This is the reward for committing capital across the relaunch.
 *
 *  ── Enforcement ──────────────────────────────────────────────────────────
 *   The registry's `claimByBurn` is gated to this escrow (its `claimGate`), so
 *   the instant direct path is closed and the vesting escrow is the only way for
 *   an ordinary holder to migrate — the drip can't be bypassed. (The perp engine
 *   stays exempt so its own inventory migration during relaunch is unaffected.)
 *
 *  ── Conservation / double-spend safety ──────────────────────────────────
 *   Every grant is backed 1:1 by tokens the registry actually transferred in
 *   (burning the caller's real dead-gen balance first), so nothing can be vested
 *   that wasn't destroyed on the other side — the escrow can never owe more than
 *   it holds. Each grant remembers WHICH token it holds, so a relaunch mid-vest
 *   (which makes the escrowed token itself a dead gen) never mixes balances.
 */
contract MigrationVesting is Ownable, ReentrancyGuard {
    // --- errors ---
    error BadGen();
    error ZeroAmount();
    error NoBalanceOrAllowance();
    error WindowOutOfRange();
    error NothingToClaim();

    // --- immutables ---
    IVestingRegistry public immutable registry;

    // --- config (governance-tunable) ---
    /// @notice Linear vest duration for non-instant claims. Governance-settable
    ///         within [MIN_WINDOW, MAX_WINDOW]; a fresh grant snapshots the value
    ///         live at deposit, so retuning never changes grants already booked.
    uint64 public vestWindow;
    /// @notice Policy oracle for the instant (unvested) tier. If unset, NOBODY is
    ///         instant — everyone vests (safe default).
    IStakerOracle public stakerOracle;

    uint64 public constant MIN_WINDOW = 1 hours;
    uint64 public constant MAX_WINDOW = 14 days;

    /// @notice One linear release booked at a single deposit.
    /// @dev `token` is pinned per-grant because the LIVE token at deposit becomes
    ///      a dead gen after a later relaunch — the escrow must pay back exactly
    ///      the token it received.
    struct Grant {
        address token;   // the live-at-deposit token this grant pays in
        uint256 total;   // tokens escrowed for this grant
        uint256 released; // tokens already withdrawn
        uint64 start;    // deposit timestamp (vest origin)
        uint64 window;   // vest duration; 0 = instant (fully vested at `start`)
    }

    /// @notice All open grants per beneficiary. Fully-drained grants are pruned.
    mapping(address => Grant[]) private _grants;

    // --- events ---
    event VestStarted(
        address indexed holder, uint256 indexed fromGen, uint256 burned,
        uint256 escrowed, uint64 window, address token
    );
    event Claimed(address indexed holder, uint256 amount, address token);
    event VestWindowSet(uint64 window);
    event StakerOracleSet(address oracle);

    /// @param _registry   The CauldronRegistry exposing `claimByBurn`.
    /// @param _owner       Governance (timelock) that tunes the window + oracle.
    /// @param _vestWindow  Initial linear window (e.g. 72h). Must be in range.
    /// @param _stakerOracle Optional instant-tier policy (address(0) = all vest).
    constructor(
        address _registry,
        address _owner,
        uint64 _vestWindow,
        address _stakerOracle
    ) Ownable(_owner) {
        if (_vestWindow < MIN_WINDOW || _vestWindow > MAX_WINDOW) revert WindowOutOfRange();
        registry = IVestingRegistry(_registry);
        vestWindow = _vestWindow;
        stakerOracle = IStakerOracle(_stakerOracle);
    }

    // -----------------------------------------------------------------------
    // ENTRY -- book a vesting migration
    // -----------------------------------------------------------------------

    /// @notice Migrate `amount` of your `fromGen` (dead-gen) tokens into a vesting
    ///         claim on the LIVE token. Approve this escrow for the dead token
    ///         first. Instant-tier wallets receive a `window = 0` grant (claim it
    ///         in the same tx via the auto-release below, or later via {claim}).
    /// @return escrowed The amount of LIVE token booked for you (== `amount`, 1:1).
    function startVest(uint256 fromGen, uint256 amount)
        external
        nonReentrant
        returns (uint256 escrowed)
    {
        if (amount == 0) revert ZeroAmount();
        escrowed = _pullAndVest(msg.sender, fromGen, amount);
        // Convenience: if this wallet is instant, sweep it out now so the whole
        // migration is a single tx. Non-instant grants stay to drip.
        _release(msg.sender);
    }

    /// @notice Keeper batch path (replaces the registry's instant auto-migrate when
    ///         vesting is enforced): for each holder who has APPROVED this escrow
    ///         for their `fromGen` token, pull their balance and book a grant.
    ///         Best-effort — a holder with no balance/allowance is skipped, never
    ///         reverting the batch. Grants are booked, NOT auto-claimed (the holder
    ///         or a keeper calls {claim} / {claimFor} to sweep vested instant tiers).
    function vestBatch(uint256 fromGen, address[] calldata holders) external nonReentrant {
        for (uint256 i; i < holders.length; ++i) {
            address h = holders[i];
            address dead = registry.generationToken(fromGen);
            if (dead == address(0)) revert BadGen();
            uint256 bal = IERC20(dead).balanceOf(h);
            uint256 allow = IERC20(dead).allowance(h, address(this));
            uint256 amt = bal < allow ? bal : allow;
            if (amt == 0) continue; // opted-out / empty — skip, don't revert
            _pullAndVest(h, fromGen, amt);
        }
    }

    /// @dev Pull `amount` of `holder`'s `fromGen` tokens, migrate 1:1 via the
    ///      registry, and book a grant. Pulls FROM `holder` (needs allowance) into
    ///      this escrow, then the registry burns the escrow's balance.
    function _pullAndVest(address holder, uint256 fromGen, uint256 amount)
        private
        returns (uint256 escrowed)
    {
        address dead = registry.generationToken(fromGen);
        if (dead == address(0)) revert BadGen();

        // Pull the dead-gen tokens in. The registry's claimByBurn will burn them
        // FROM this escrow and pay the live token TO this escrow.
        if (!IERC20(dead).transferFrom(holder, address(this), amount)) revert NoBalanceOrAllowance();

        uint256 g = registry.currentGeneration();
        address live = registry.generationToken(g);

        uint256 before = IERC20(live).balanceOf(address(this));
        escrowed = registry.claimByBurn(fromGen, amount);
        // Trust-but-verify the delta actually landed (defends a misreporting token).
        uint256 delta = IERC20(live).balanceOf(address(this)) - before;
        if (delta < escrowed) escrowed = delta;
        if (escrowed == 0) revert ZeroAmount();

        uint64 w = _isInstant(holder) ? 0 : vestWindow;
        _grants[holder].push(Grant({
            token: live,
            total: escrowed,
            released: 0,
            start: uint64(block.timestamp),
            window: w
        }));
        emit VestStarted(holder, fromGen, amount, escrowed, w, live);
    }

    // -----------------------------------------------------------------------
    // CLAIM -- sweep vested tokens
    // -----------------------------------------------------------------------

    /// @notice Release everything currently vested across all your grants.
    function claim() external nonReentrant {
        uint256 moved = _release(msg.sender);
        if (moved == 0) revert NothingToClaim();
    }

    /// @notice Permissionlessly release `holder`'s vested tokens TO `holder`
    ///         (keeper convenience — funds only ever go to the beneficiary).
    function claimFor(address holder) external nonReentrant {
        uint256 moved = _release(holder);
        if (moved == 0) revert NothingToClaim();
    }

    /// @dev Pay out every grant's vested-minus-released amount to `holder`,
    ///      pruning grants that become fully drained (swap-pop). Grants may hold
    ///      different tokens (post-relaunch), so payout is per-grant.
    function _release(address holder) private returns (uint256 totalMoved) {
        Grant[] storage gs = _grants[holder];
        for (uint256 i; i < gs.length; ) {
            Grant storage grt = gs[i];
            uint256 vested = _vestedOf(grt);
            uint256 due = vested - grt.released;
            if (due > 0) {
                grt.released = vested;
                totalMoved += due;
                IERC20(grt.token).transfer(holder, due);
                emit Claimed(holder, due, grt.token);
            }
            if (grt.released >= grt.total) {
                // prune: swap with last, pop (order irrelevant)
                uint256 last = gs.length - 1;
                if (i != last) gs[i] = gs[last];
                gs.pop();
            } else {
                ++i;
            }
        }
    }

    /// @dev Linear vest: 0 at start, `total` at start+window; window 0 = instant.
    function _vestedOf(Grant storage grt) private view returns (uint256) {
        if (grt.window == 0) return grt.total;
        uint256 elapsed = block.timestamp - grt.start;
        if (elapsed >= grt.window) return grt.total;
        return (grt.total * elapsed) / grt.window;
    }

    function _isInstant(address who) private view returns (bool) {
        if (address(stakerOracle) == address(0)) return false;
        // Never let a misbehaving oracle brick a migration — treat a revert as
        // "not instant" (the safe, vesting outcome).
        try stakerOracle.isInstant(who) returns (bool ok) { return ok; }
        catch { return false; }
    }

    // -----------------------------------------------------------------------
    // VIEWS
    // -----------------------------------------------------------------------

    /// @notice Total claimable across all of `holder`'s grants right now.
    function claimable(address holder) external view returns (uint256 total) {
        Grant[] storage gs = _grants[holder];
        for (uint256 i; i < gs.length; ++i) {
            total += _vestedOf(gs[i]) - gs[i].released;
        }
    }

    /// @notice Total still locked (not yet vested) across all of `holder`'s grants.
    function locked(address holder) external view returns (uint256 total) {
        Grant[] storage gs = _grants[holder];
        for (uint256 i; i < gs.length; ++i) {
            total += gs[i].total - _vestedOf(gs[i]);
        }
    }

    /// @notice Number of open grants for `holder`.
    function grantCount(address holder) external view returns (uint256) {
        return _grants[holder].length;
    }

    /// @notice Read a single open grant.
    function grantAt(address holder, uint256 i) external view returns (Grant memory) {
        return _grants[holder][i];
    }

    // -----------------------------------------------------------------------
    // GOVERNANCE
    // -----------------------------------------------------------------------

    /// @notice Tune the linear vest window for FUTURE grants (bounded). Existing
    ///         grants keep the window snapshotted at their deposit.
    function setVestWindow(uint64 _window) external onlyOwner {
        if (_window < MIN_WINDOW || _window > MAX_WINDOW) revert WindowOutOfRange();
        vestWindow = _window;
        emit VestWindowSet(_window);
    }

    /// @notice Swap the instant-tier policy oracle (address(0) = everyone vests).
    function setStakerOracle(address _oracle) external onlyOwner {
        stakerOracle = IStakerOracle(_oracle);
        emit StakerOracleSet(_oracle);
    }
}
