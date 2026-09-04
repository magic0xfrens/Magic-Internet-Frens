// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ZAuditBase, ZMockGovernor} from "./ZAuditBase.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

/**
 * FINDING Z-05 (High, L2) — every window in CauldronHook's death detector was
 * denominated in `block.number`, with constants hard-coded to Ethereum's ~12 s
 * cadence:
 *
 *     uint256 public constant BLOCKS_PER_HOUR = 300;     // "~12s blocks"
 *     uint256 public constant BLOCKS_PER_DAY  = 7_200;   // 300 * 24
 *
 * On Arbitrum Nitro — and therefore on every Orbit chain, including the intended
 * deployment target — `block.number` does NOT count L2 blocks; it reports the PARENT
 * chain's block number. The wall-clock meaning of those constants was a property of
 * the settlement layer rather than of the protocol:
 *
 *     parent = Ethereum L1  (~12 s)  : 7200 blocks = 24 h   (as designed)
 *     parent = Arbitrum One (~0.25 s): 7200 blocks = 30 min (48x too fast)
 *
 * On the latter a healthy, liquid token read DEAD after thirty minutes of quiet, and
 * because `relaunch()` is permissionless and its only other gate (`minLifetime`) is in
 * SECONDS, any passer-by could permanently retire a live token about an hour after
 * launch. Both constants were `constant` — no setter, no migration path — and the hook
 * had under 100 bytes of EIP-170 headroom.
 *
 * STATUS: FIXED. The volume window is now denominated in WALL-CLOCK SECONDS
 * (`SECONDS_PER_HOUR` / `SECONDS_PER_DAY`), which carries the intended meaning
 * identically on L1, on an Orbit L2 and on an Orbit L3. The owner-only `trackPool`
 * was removed to reclaim the necessary bytes (it also bypassed the `_afterInitialize`
 * adoption gate).
 *
 * These tests advance `block.number` and `block.timestamp` INDEPENDENTLY, which is
 * the only way to model the L3 cadence on an L1-like fork.
 *
 * RESIDUAL, ACCEPTED (documented in the report): the anti-snipe surtax window
 * (`snipeWindowBlocks`) and the gacha's `blockhash` commit-reveal remain block-based.
 * Both are owner-tunable or inherently block-scoped, and their failure modes are a
 * weaker launch surtax and a re-anchored ticket — not the permissionless destruction
 * of a live token. They are covered below so the residual is measured, not assumed.
 */
contract Z05_L2BlockClock is ZAuditBase {
    address internal token;
    PoolId internal pid;

    // Storage-backed clocks: `via_ir` common-subexpression-eliminates the NUMBER and
    // TIMESTAMP opcodes, so `vm.roll(block.number + x)` twice in one function rolls to
    // the same target twice. Note also that on a fork `vm.roll` re-snaps the block
    // timestamp, so rolls must never follow a warp whose elapsed time is under test.
    uint256 internal _bn;
    uint256 internal _ts;

    function setUp() public {
        _bootstrap(1 ether);
        if (!active) return;
        registry.setGovernor(address(new ZMockGovernor(address(0xBEEF))));
        (token, pid) = registry.summon{value: 10 ether}();
        _bn = block.number;
        _ts = block.timestamp;
    }

    function _roll(uint256 n) internal {
        _bn += n;
        vm.roll(_bn);
        _ts = block.timestamp; // a fork roll re-snaps the clock; re-anchor from truth
    }

    function _warp(uint256 dt) internal {
        _ts += dt;
        vm.warp(_ts);
    }

    /// REGRESSION: block-count advance alone no longer kills a healthy token. 7,201
    /// parent blocks pass — 30 minutes of wall clock at an Arbitrum-One cadence — and
    /// the token stays alive because the window is measured in seconds.
    function test_FIXED_L2_BlockAdvanceDoesNotKillAHealthyToken() public {
        if (!active) return;

        _roll(hook.snipeWindowBlocks() + 1);
        _warp(60);
        _buyExactIn(2 ether); // healthy, well above the 1 ETH death threshold
        assertFalse(hook.isDead(pid), "alive after real volume");

        uint256 volBefore = hook.getVolume24h(pid);
        assertGt(volBefore, hook.deathThreshold(), "24h volume is healthy");

        // 7,201 parent blocks == 30 minutes of wall clock on an Orbit L3.
        _roll(7201);
        _warp(30 minutes);

        assertEq(hook.getVolume24h(pid), volBefore, "FIXED: the window ignores block count");
        assertFalse(hook.isDead(pid), "FIXED: a healthy token survives 7,201 parent blocks");
    }

    /// REGRESSION: and the permissionless kill is gone with it.
    function test_FIXED_L2_HealthyTokenIsNotRelaunchable() public {
        if (!active) return;

        _roll(hook.snipeWindowBlocks() + 1);
        _warp(60);
        _buyExactIn(2 ether);

        _roll(7201); // 30 min of L3 wall-clock
        _warp(61 minutes); // clears minLifetime (1h, timestamp-based)

        address griefer = address(0xBADBAD);
        vm.prank(griefer);
        vm.expectRevert(); // TokenStillAlive()
        registry.relaunch();
        assertEq(registry.currentGeneration(), 1, "FIXED: a stranger cannot retire a live token");
    }

    /// The window still WORKS: a genuine 24 hours of silence still retires the token,
    /// on any chain, because the clock is now wall-clock.
    function test_FIXED_L2_RealDayOfSilenceStillKills() public {
        if (!active) return;

        _roll(hook.snipeWindowBlocks() + 1);
        _warp(60);
        _buyExactIn(2 ether);
        assertFalse(hook.isDead(pid), "alive");

        _warp(1 days + 1); // real time, no block advance at all
        assertEq(hook.getVolume24h(pid), 0, "window expired on wall-clock");
        assertTrue(hook.isDead(pid), "FIXED: 24h of real silence still retires the token");

        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "rebirth still works");
    }

    /// RESIDUAL (accepted): the anti-snipe surtax window is still a block count, so it
    /// is ~6 minutes on an Orbit L2 but only ~7.5 SECONDS on an Orbit L3. It is
    /// owner-tunable via `setSnipeParams`, so this is a deployment-configuration item.
    function test_RESIDUAL_L2_AntiSnipeWindowIsStillBlockBased() public {
        if (!active) return;

        uint256 atLaunch = hook.snipeSurtaxBps(pid);
        assertGt(atLaunch, 5000, "launch block is heavily surtaxed");

        uint256 window = hook.snipeWindowBlocks();
        _roll(window + 1);

        assertEq(hook.snipeSurtaxBps(pid), 0, "surtax decays on BLOCK count, not time");
        emit log_named_uint("snipe window, blocks        ", window);
        emit log_named_uint("... seconds at 12s parent   ", window * 12);
        emit log_named_uint("... seconds at 0.25s parent ", window / 4);
    }

    /// RESIDUAL (accepted): the gacha's commit-reveal seed is `blockhash(commitBlock)`,
    /// valid for only 256 blocks. On a fast parent chain that window is ~64 seconds, so
    /// batches expire routinely — and an expired batch RE-ANCHORS and `break`s, which
    /// head-of-line blocks the FIFO queue and hands its owner a fresh roll.
    function test_RESIDUAL_L2_TicketSeedExpiryReAnchorsAndStallsTheQueue() public {
        if (!active) return;

        _roll(hook.snipeWindowBlocks() + 1);
        _warp(60);
        _buyExactIn(2 ether); // earn crystal credit

        hook.setOpener(address(this), true);
        uint256 n = hook.commitCrystals(address(this), 3, 0.2 ether);
        assertGt(n, 0, "crystals committed");
        (,, uint48 commitBlock,,,) = hook.batches(0);

        // 256 parent blocks ~= 64 seconds at an Arbitrum-One cadence.
        _roll(257);

        (uint256 processed,) = hook.resolveTickets(10);
        (,, uint48 newCommitBlock,,, uint16 resolved) = hook.batches(0);

        assertEq(processed, 0, "queue stalls on the expired seed");
        assertEq(resolved, 0, "batch untouched");
        assertGt(newCommitBlock, commitBlock, "batch silently re-anchored");
        emit log_named_uint("original commitBlock", commitBlock);
        emit log_named_uint("re-anchored to      ", newCommitBlock);
    }

    /// CONTROL: inside the 256-block window the same batch resolves normally, pinning
    /// the behaviour above to seed EXPIRY rather than to the commit itself.
    function test_SAFE_TicketResolvesInsideTheSeedWindow() public {
        if (!active) return;

        _roll(hook.snipeWindowBlocks() + 1);
        _warp(60);
        _buyExactIn(2 ether);

        hook.setOpener(address(this), true);
        hook.commitCrystals(address(this), 3, 0.2 ether);
        _roll(2);

        (uint256 processed,) = hook.resolveTickets(10);
        assertGt(processed, 0, "control: resolves inside the blockhash window");
    }
}
