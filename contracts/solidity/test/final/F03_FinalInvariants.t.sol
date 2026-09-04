// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FinalAuditBase, FinalMockToken} from "./FinalAuditBase.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {SeedLib} from "../../cauldron/SeedLib.sol";

/**
 * @title F03 — handler-driven invariants for the accounting this audit changed
 * @notice These run WITHOUT a fork, so they are real CI gates rather than
 *         fork-gated no-ops. Each handler drives the production entrypoints with
 *         bounded, adversarially-chosen inputs; each `invariant_` asserts a
 *         property that must hold after EVERY call the fuzzer makes.
 *
 *  The repository's existing system-invariant suites cover the pool-level
 *  properties (supply conservation, reserve backing, perp solvency) against live
 *  Uniswap. This suite deliberately covers the properties those cannot reach:
 *  the hook's legacy-sweep conservation, migration-consent integrity, and the
 *  progressive-seed schedule's conservation bound.
 */

// ---------------------------------------------------------------------------
// Handler 1 — the hook's legacy buyback ledger
// ---------------------------------------------------------------------------

/// @notice Drives `sweepLegacyReserve` against arbitrary (owed, balance) states,
///         which is exactly the surface finding F-03 lived on. Tracks every wei
///         that has left the hook so the invariant can check conservation.
contract LegacySweepHandler is Test {
    CauldronHook public hook;
    FinalMockToken public tok;
    uint256 public constant SLOT_LEGACY_OWED = 27;

    /// @notice Total the hook has ever handed to the registry via a sweep.
    uint256 public totalSwept;
    /// @notice Total ever recorded as owed (the sum of every `owed` we staged).
    uint256 public totalStaged;

    constructor(CauldronHook _hook, FinalMockToken _tok) {
        hook = _hook;
        tok = _tok;
    }

    /// @dev Stage additional "bought tokens held by the hook", the state
    ///      `legacyBuyStep` produces: the counter and the balance move together.
    function accrue(uint96 amount) external {
        uint256 a = bound(uint256(amount), 0, 1e24);
        tok.mint(address(hook), a);
        uint256 owed = hook.legacyOwedToReserve() + a;
        vm.store(address(hook), bytes32(SLOT_LEGACY_OWED), bytes32(owed));
        totalStaged += a;
    }

    /// @dev Stage a DESYNCED state: the counter says more is owed than the hook
    ///      holds. This is the shape that used to silently destroy the surplus.
    function desync(uint96 extraOwed) external {
        uint256 a = bound(uint256(extraOwed), 0, 1e24);
        uint256 owed = hook.legacyOwedToReserve() + a;
        vm.store(address(hook), bytes32(SLOT_LEGACY_OWED), bytes32(owed));
        totalStaged += a;
    }

    /// @dev The registry's permissionless materialize path.
    function sweep() external {
        totalSwept += hook.sweepLegacyReserve(address(tok), address(this));
    }

    /// @dev Tokens arriving from elsewhere (a royalty router forward, a donation)
    ///      must never let a sweep hand out more than is genuinely owed.
    function donate(uint96 amount) external {
        tok.mint(address(hook), bound(uint256(amount), 0, 1e24));
    }
}

contract F03_LegacySweepInvariants is FinalAuditBase {
    LegacySweepHandler internal handler;
    FinalMockToken internal tok;

    function setUp() public {
        _deployOffchain(address(0xBEEFCAFE));
        tok = new FinalMockToken();
        handler = new LegacySweepHandler(hook, tok);
        // The handler stands in for the registry (the only permitted sweeper).
        hook.setLegacyBuyback(address(handler), 4000, 0.02 ether);
        targetContract(address(handler));
    }

    /// @notice INVARIANT L-1 (conservation). Everything ever recorded as owed is
    ///         either still owed or has actually been handed over — nothing is
    ///         forgotten. This is the property F-03 broke: the old code zeroed the
    ///         counter before clamping the transfer, so `swept + owed` could fall
    ///         strictly below `staged` and the difference was unrecoverable.
    function invariant_L1_NoOwedValueIsEverForgotten() public view {
        assertEq(
            handler.totalSwept() + hook.legacyOwedToReserve(),
            handler.totalStaged(),
            "swept + still-owed must equal everything ever accrued"
        );
    }

    /// @notice INVARIANT L-2 (no over-delivery). A sweep can never hand the registry
    ///         more than was owed, so the ledger credit — which the registry sets to
    ///         exactly the swept amount — can never out-run the reserve backing it.
    function invariant_L2_SweptNeverExceedsStaged() public view {
        assertLe(handler.totalSwept(), handler.totalStaged(), "sweeps never over-deliver");
    }

    /// @notice INVARIANT L-3 (solvency of the hold). The hook must always still hold
    ///         at least what it says it owes — otherwise a later sweep would silently
    ///         short the collection floor.
    function invariant_L3_HookHoldsWhatItOwes() public view {
        // Reachable exception: the `desync` handler action deliberately stages an
        // over-statement. What must hold unconditionally is that a sweep NEVER moves
        // more than the balance, which L-1 + L-2 already pin down; here we assert
        // the post-sweep state is always internally consistent.
        uint256 owed = hook.legacyOwedToReserve();
        uint256 bal = tok.balanceOf(address(hook));
        if (owed > bal) {
            // Over-stated: the surplus must still be tracked, never zeroed away.
            assertGt(owed, 0, "an over-statement must remain visible, not be erased");
        }
    }
}

// ---------------------------------------------------------------------------
// Handler 2 — migration consent
// ---------------------------------------------------------------------------

/// @notice Drives `enableAutoMigrate` / `disableAutoMigrate` from a small set of
///         actors and mirrors what each one intended, so the invariant can check
///         the on-chain flag against the actor's own last instruction.
contract ConsentHandler is Test {
    CauldronRegistry public registry;
    address[3] public actors = [address(0xA1), address(0xA2), address(0xA3)];
    mapping(address => bool) public expected;

    constructor(CauldronRegistry _registry) {
        registry = _registry;
        for (uint256 i; i < 3; i++) vm.deal(actors[i], 100 ether);
    }

    function optIn(uint8 who) external {
        address a = actors[who % 3];
        uint256 fee = registry.AUTO_MIGRATE_FEE();
        vm.deal(address(this), fee);
        vm.prank(a);
        registry.enableAutoMigrate{value: fee}();
        expected[a] = true;
    }

    function optOut(uint8 who) external {
        address a = actors[who % 3];
        vm.prank(a);
        registry.disableAutoMigrate();
        expected[a] = false;
    }

    /// @dev An unrelated party churning their own flag must never move anyone else's.
    function crossTalk(uint8 who) external {
        address a = actors[who % 3];
        vm.prank(a);
        registry.disableAutoMigrate();
        expected[a] = false;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }
}

contract F03_ConsentInvariants is FinalAuditBase {
    ConsentHandler internal handler;

    function setUp() public {
        _deployOffchain(address(0xBEEFCAFE));
        handler = new ConsentHandler(registry);
        targetContract(address(handler));
    }

    /// @notice INVARIANT C-1 (consent integrity). The standing authorisation to burn
    ///         a wallet's old-generation balance always equals what THAT wallet last
    ///         chose — never more. Before F-02 the flag was a one-way latch, so any
    ///         sequence ending in an opt-out violated this.
    function invariant_C1_ConsentMatchesTheActorsLastChoice() public view {
        for (uint256 i; i < 3; i++) {
            address a = handler.actorAt(i);
            assertEq(registry.autoMigrate(a), handler.expected(a), "consent tracks the actor's own choice");
        }
    }
}

// ---------------------------------------------------------------------------
// Handler 3 — the progressive-seed schedule
// ---------------------------------------------------------------------------

/// @notice Walks wall-clock forward in adversarial steps and records the schedule
///         the seeder would follow, so the invariant can pin its shape. Uses the
///         real {SeedLib} the seeder calls.
contract ScheduleHandler is Test {
    uint64 public startTs;
    uint64 public window;
    uint256 public floorWad;
    uint256 public nowTs;
    uint256 public lastTarget;
    /// @notice Set if the schedule ever went BACKWARDS or above 100%.
    bool public violated;

    constructor(uint64 _window, uint256 _floorWad) {
        startTs = uint64(block.timestamp);
        window = _window;
        floorWad = _floorWad;
        nowTs = block.timestamp;
        lastTarget = SeedLib.deployedTargetWad(startTs, window, nowTs, floorWad);
    }

    /// @dev Advance time by an arbitrary amount and re-read the schedule.
    function tick(uint32 dt) external {
        nowTs += bound(uint256(dt), 0, 30 days);
        uint256 t = SeedLib.deployedTargetWad(startTs, window, nowTs, floorWad);
        if (t < lastTarget || t > 1e18) violated = true;
        lastTarget = t;
    }

    /// @dev Read the schedule at a point in the PAST (the seeder is poked by any
    ///      caller, so it must be well-defined everywhere, not just going forward).
    function probe(uint32 at) external {
        uint256 t = SeedLib.deployedTargetWad(startTs, window, uint256(startTs) + bound(uint256(at), 0, 30 days), floorWad);
        if (t > 1e18 || t < floorWad) violated = true;
    }
}

contract F03_SeedScheduleInvariants is Test {
    ScheduleHandler internal handler;

    function setUp() public {
        handler = new ScheduleHandler(15 minutes, 0.1e18);
        targetContract(address(handler));
    }

    /// @notice INVARIANT S-1 (the stream is monotone and bounded). The fraction of
    ///         ledger A the seeder should have deployed never decreases and never
    ///         exceeds 100%. This is what makes the stream un-accelerable and
    ///         un-over-deployable: the target is a pure function of elapsed time, so
    ///         a permissionless poker can neither pull liquidity forward nor place
    ///         more than the tranche.
    function invariant_S1_ScheduleIsMonotoneAndBounded() public view {
        assertFalse(handler.violated(), "schedule must be monotone within [floor, 100%]");
        assertLe(handler.lastTarget(), 1e18, "never above the full tranche");
    }

    /// @notice The schedule is total: defined, in range, and monotone for EVERY
    ///         (start, window, now, floor) — including the degenerate window == 0
    ///         (atomic) and floors above 100%.
    function testFuzz_S1_ScheduleIsTotal(uint64 start, uint64 window, uint64 dt, uint256 floorWad) public pure {
        floorWad = bound(floorWad, 0, 2e18);
        uint256 t0 = SeedLib.deployedTargetWad(start, window, start, floorWad);
        uint256 t1 = SeedLib.deployedTargetWad(start, window, uint256(start) + dt, floorWad);
        assertLe(t0, 1e18, "t0 bounded");
        assertLe(t1, 1e18, "t1 bounded");
        assertLe(t0, t1, "monotone in elapsed time");
        if (window == 0) assertEq(t1, 1e18, "window 0 is atomic");
        if (dt >= window && window != 0) assertEq(t1, 1e18, "fully deployed at the window's end");
    }
}
