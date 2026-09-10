// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-11 — A REVERTING FEED BYPASSED THE ORACLE'S FAIL-SAFE  (Medium)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `QuoteOracle` states its failure policy explicitly (:40-44): death is
 *  irreversible and relaunch is permissionless, so "when a price is unusable
 *  this returns 0, and callers must treat 0 as 'cannot judge' rather than 'no
 *  volume'. Failing toward ALIVE is the only safe direction when the wrong
 *  answer cannot be undone."
 *
 *  It then enumerates three unusable conditions (:49-55): no feed, stale, and
 *  sequencer down. All three are cases where the feed ANSWERS and the answer is
 *  no good. A feed can also fail by NOT ANSWERING — a retired or migrated
 *  aggregator, an access-controlled one, a proxy pointing at a removed
 *  implementation, or an address with no code (a high-level call to a codeless
 *  address reverts on the extcodesize check).
 *
 *  That fourth case did not return 0. It threw, through `usdPerRawUnit` and out
 *  of `cachedUsdPerRawUnit` — which calls it via `this.`, so the revert
 *  propagates — and so never reached the line that keeps the last good factor.
 *
 *  The consequence is an asymmetry between two forms of the SAME real-world
 *  condition. `CauldronHook._toUsd` (:677-682) wraps the oracle in a raw `call`
 *  and returns 0 on failure, so a reverting feed does not take swaps down. But
 *  `CauldronHook:769` then reads `if (absVolume > 0)`, so the swap records ZERO
 *  volume — and `isDead` (:1512) judges `vol < deathThreshold`. A feed that
 *  broke by reverting pushed a live generation toward relaunch; the identical
 *  feed going stale did not, because the cache covered it.
 *
 *  Two further revert paths were found while confirming this, both from checked
 *  arithmetic on attacker-irrelevant but operator-plausible input: a feed
 *  reporting `updatedAt` in the future underflowed `block.timestamp - updatedAt`,
 *  and the sequencer feed reporting a future `startedAt` underflowed
 *  `block.timestamp - startedAt`.
 *
 *  LATENT AT THE CURRENT LIVE CONFIG: `indexer/deployments/round.json` carries
 *  `deathThresholdEth: 0`, and `vol < 0` is never true, so nothing dies today.
 *  This is rated against the configuration the design intends, not the one
 *  currently shipped.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B11_OracleRevertBypassesCache is Test {
    QuoteOracle internal oracle;
    RevertableFeed internal feed;
    address internal constant NATIVE = address(0);

    function setUp() public {
        oracle = new QuoteOracle(address(this));
        feed = new RevertableFeed(8, 3000e8);
        oracle.setFeed(NATIVE, address(feed), 1 hours, 18);
    }

    /// @notice CONTROL: a STALE feed degrades gracefully — the cache keeps the
    ///         last good value. This is the documented purpose of the cache and
    ///         it always worked.
    function test_B11a_StaleFeedKeepsTheCachedValue() public {
        uint256 good = oracle.cachedUsdPerRawUnit(NATIVE);
        assertGt(good, 0, "a live feed prices");

        feed.setUpdatedAt(1); // stale
        vm.warp(vm.getBlockTimestamp() + oracle.TTL() + 1);

        assertEq(oracle.cachedUsdPerRawUnit(NATIVE), good, "stale: last good value retained");
    }

    /// @notice INVARIANT: the same lapse, but the aggregator reverts instead of
    ///         answering stale. The cached value must protect us identically.
    ///         Pre-fix this reverted with "feed: down".
    function test_INVARIANT_B11_RevertingFeedKeepsTheCachedValue() public {
        uint256 good = oracle.cachedUsdPerRawUnit(NATIVE);
        assertGt(good, 0, "a live feed prices");

        feed.setReverting(true);
        vm.warp(vm.getBlockTimestamp() + oracle.TTL() + 1);

        assertEq(
            oracle.cachedUsdPerRawUnit(NATIVE), good,
            "reverting: last good value must be retained, same as stale"
        );
    }

    /// @notice The uncached view must also degrade rather than throw, so
    ///         `priceable()` can answer for a broken feed instead of reverting.
    function test_INVARIANT_B11_ViewsDegradeRatherThanThrow() public {
        feed.setReverting(true);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "a reverting feed reads as unusable");
        assertFalse(oracle.priceable(NATIVE), "and reports itself unpriceable");
    }

    /// @notice A feed with a skewed clock must be refused, not underflow the
    ///         staleness subtraction. `block.timestamp - updatedAt` is checked
    ///         arithmetic under ^0.8.26.
    function test_INVARIANT_B11_FutureTimestampIsRefusedNotReverted() public {
        feed.setUpdatedAt(block.timestamp + 1 days);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "a future updatedAt is unusable, not fatal");
    }

    /// @notice The sequencer uptime feed is a feed like any other: if it refuses
    ///         to answer, that is "cannot confirm healthy", not a revert.
    function test_INVARIANT_B11_RevertingSequencerFeedIsRefusedNotReverted() public {
        RevertableFeed seq = new RevertableFeed(0, 0); // 0 = sequencer up
        oracle.setSequencer(address(seq), 3600);
        vm.warp(vm.getBlockTimestamp() + 2 hours); // past the grace period
        // Warping past the grace period also ages the PRICE feed past its 1h
        // heartbeat; refresh it so this test isolates the sequencer path.
        feed.setUpdatedAt(vm.getBlockTimestamp());

        assertGt(oracle.usdPerRawUnit(NATIVE), 0, "healthy sequencer prices normally");

        seq.setReverting(true);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "a reverting uptime feed is unusable, not fatal");
    }

    /// @notice A sequencer feed reporting a future startedAt must not underflow.
    function test_INVARIANT_B11_FutureSequencerStartIsRefused() public {
        RevertableFeed seq = new RevertableFeed(0, 0);
        seq.setStarted(block.timestamp + 1 days);
        oracle.setSequencer(address(seq), 3600);

        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "a future startedAt is unusable, not fatal");
    }
}

/// @dev A Chainlink-shaped feed that can be made to stop answering, mirroring a
///      retired, migrated or access-controlled aggregator.
contract RevertableFeed {
    uint8 public decimals;
    int256 public answer;
    uint256 public updatedAt;
    uint256 public startedAt;
    bool public reverting;

    constructor(uint8 d, int256 a) {
        decimals = d; answer = a; updatedAt = block.timestamp; startedAt = block.timestamp;
    }
    function setUpdatedAt(uint256 t) external { updatedAt = t; }
    function setStarted(uint256 t) external { startedAt = t; }
    function setReverting(bool r) external { reverting = r; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        require(!reverting, "feed: down");
        return (1, answer, startedAt, updatedAt, 1);
    }
}
