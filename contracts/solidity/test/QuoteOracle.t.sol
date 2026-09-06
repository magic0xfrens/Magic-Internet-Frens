// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {QuoteOracle} from "../cauldron/QuoteOracle.sol";

/// @dev A Chainlink-shaped feed a test can put into any state a real one reaches.
contract MockFeed {
    uint8 public decimals;
    int256 public answer;
    uint256 public updatedAt;
    uint256 public startedAt;

    constructor(uint8 d, int256 a) { decimals = d; answer = a; updatedAt = block.timestamp; startedAt = block.timestamp; }
    function set(int256 a, uint256 t) external { answer = a; updatedAt = t; }
    function setStarted(uint256 t) external { startedAt = t; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, startedAt, updatedAt, 1);
    }
}

contract Token6 {
    function decimals() external pure returns (uint8) { return 6; }
}

/**
 * @dev The oracle is only useful if it refuses to answer when it should.
 *
 *  A price feed that keeps returning a confident, wrong number is worse than one
 *  that returns nothing — downstream it looks like data. These tests are mostly
 *  about the refusals: no feed, stale answer, negative answer, sequencer down,
 *  sequencer only just back.
 */
contract QuoteOracleTest is Test {
    QuoteOracle oracle;
    MockFeed ethFeed;
    MockFeed usdgFeed;
    MockFeed sequencer;
    Token6 usdg;

    address constant NATIVE = address(0);

    function setUp() public {
        vm.warp(1_800_000_000); // a sane wall clock; block.timestamp = 1 breaks staleness maths
        oracle = new QuoteOracle(address(this));
        ethFeed = new MockFeed(8, 3000e8);      // $3,000 / ETH, 8dp like a real USD feed
        usdgFeed = new MockFeed(8, 1e8);        // $1.00
        usdg = new Token6();
        oracle.setFeed(NATIVE, address(ethFeed), 3600, 18);
        oracle.setFeed(address(usdg), address(usdgFeed), 86400, 6);
    }

    /// The core conversion: ETH and a 6-decimal stable must produce the SAME USD
    /// figure for the same dollar amount of volume. Quote-side they differ by
    /// 1e12, which is the bug this exists to remove.
    function test_SameDollarVolumeReadsTheSameAcrossQuotes() public view {
        uint256 ethFactor = oracle.usdPerRawUnit(NATIVE);
        uint256 usdgFactor = oracle.usdPerRawUnit(address(usdg));

        // 1 ETH of volume, in wei.
        uint256 ethUsd = (1e18 * ethFactor) / 1e18;
        // $3,000 of USDG, in 6-decimal units.
        uint256 usdgUsd = (3000e6 * usdgFactor) / 1e18;

        assertApproxEqRel(ethUsd, 3000e18, 0.01e18, "1 ETH should read as ~$3,000");
        assertApproxEqRel(usdgUsd, 3000e18, 0.01e18, "3,000 USDG should read as ~$3,000");
        assertApproxEqRel(ethUsd, usdgUsd, 0.01e18, "and the two must agree");
    }

    // ── the refusals ────────────────────────────────────────────────────────

    /// An unconfigured quote must not silently price at zero-and-usable.
    function test_NoFeedIsUnusable() public view {
        assertEq(oracle.usdPerRawUnit(address(0xDEAD)), 0, "no feed -> cannot judge");
    }

    /// THE DANGEROUS ONE. A frozen feed still answers, and its answer looks
    /// perfectly valid — which is exactly why staleness has to be checked rather
    /// than assumed.
    function test_StaleAnswerIsRefused() public {
        assertGt(oracle.usdPerRawUnit(NATIVE), 0, "fresh feed works");
        // Push time past the heartbeat without updating the feed.
        vm.warp(block.timestamp + 3601);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "a stale price must be refused");
    }

    function test_NonPositiveAnswerIsRefused() public {
        ethFeed.set(0, block.timestamp);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "zero is not a price");
        ethFeed.set(-1, block.timestamp);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "negative is not a price");
    }

    /// On an L2 the feed cannot update while the sequencer is down, so every
    /// answer is stale by definition even though it reads fine.
    function test_SequencerDownIsRefused() public {
        sequencer = new MockFeed(0, 1); // 1 = down
        oracle.setSequencer(address(sequencer), 3600);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "sequencer down -> cannot judge");
    }

    /// And just after it returns, there is a backlog of stale-priced
    /// transactions to clear — so "up" alone is not enough.
    function test_SequencerJustBackIsRefused() public {
        sequencer = new MockFeed(0, 0); // 0 = up
        sequencer.setStarted(block.timestamp); // came back this second
        oracle.setSequencer(address(sequencer), 3600);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "grace period not elapsed");

        vm.warp(block.timestamp + 3601);
        ethFeed.set(3000e8, block.timestamp); // feed catches up
        assertGt(oracle.usdPerRawUnit(NATIVE), 0, "usable once the grace period passes");
    }

    /// An L1 deployment has no sequencer, and the check must not block there.
    function test_NoSequencerFeedMeansTheCheckIsSkipped() public view {
        assertGt(oracle.usdPerRawUnit(NATIVE), 0, "L1: no sequencer to check");
    }

    // ── trust model ─────────────────────────────────────────────────────────

    /// Feeds sit beside the allowlist: choosing which assets exist and how they
    /// are priced is the same decision. A vote that could set its own feed could
    /// price anything at anything.
    function test_OnlyOwnerCanSetFeeds() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(QuoteOracle.NotOwner.selector);
        oracle.setFeed(NATIVE, address(ethFeed), 3600, 18);

        vm.prank(address(0xBAD));
        vm.expectRevert(QuoteOracle.NotOwner.selector);
        oracle.setSequencer(address(0), 0);
    }

    /// A zero heartbeat would disable staleness checking entirely.
    function test_ZeroHeartbeatIsRefused() public {
        vm.expectRevert(QuoteOracle.BadConfig.selector);
        oracle.setFeed(NATIVE, address(ethFeed), 0, 18);
    }

    /// Price moves must be reflected — the whole failure of the governance
    /// scalar was that it did not.
    function test_PriceMovesAreReflected() public {
        uint256 before = oracle.usdPerRawUnit(NATIVE);
        ethFeed.set(6000e8, block.timestamp); // ETH doubles
        uint256 after_ = oracle.usdPerRawUnit(NATIVE);
        assertApproxEqRel(after_, before * 2, 0.01e18, "a 2x in ETH must show up as 2x");
    }
}
