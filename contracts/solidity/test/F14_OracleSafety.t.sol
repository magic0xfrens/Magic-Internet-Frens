// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {QuoteOracle} from "../cauldron/QuoteOracle.sol";

/// @dev A Chainlink aggregator we can break on demand.
contract MockFeed {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public dec;
    bool public boom;

    constructor(int256 a, uint8 d) { answer = a; updatedAt = block.timestamp; dec = d; }
    function set(int256 a, uint256 u) external { answer = a; updatedAt = u; }
    function setBoom(bool b) external { boom = b; }
    function decimals() external view returns (uint8) { if (boom) revert("dead"); return dec; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (boom) revert("dead");
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract Tok { function decimals() external pure returns (uint8) { return 6; } }

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  F-14 — A BROKEN ORACLE MUST NOT MOVE MONEY
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  This factor scales recorded VOLUME, and volume mints NFTs that earn a
 *  perpetual dividend. So a wrong answer is not a display bug — it issues the
 *  collection against trades that never happened.
 *
 *  Every failure mode must resolve to 0, which callers read as CANNOT JUDGE and
 *  the hook handles by recording nothing (audit V-1). "Record a fiction" and
 *  "record zero volume" are both wrong; refusing to answer is the only safe
 *  third option.
 *
 *  The four ways a feed fails, and the fourth is the one with teeth:
 *    1. STALE      — answers, but the answer is old.
 *    2. DEAD       — does not answer at all (retired, migrated, no code).
 *    3. NONSENSE   — answers <= 0, or dates itself in the future.
 *    4. FRESH AND  — answers promptly with a number that is simply wrong.
 *       WRONG        Nothing above catches it. Only a sanity band does.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract F14_OracleSafetyTest is Test {
    QuoteOracle internal oracle;
    MockFeed internal ethFeed;
    Tok internal usdg;

    function setUp() public {
        vm.warp(1_800_000_000);
        oracle = new QuoteOracle(address(this));
        ethFeed = new MockFeed(2400e8, 8);              // $2,400 / ETH
        usdg = new Tok();
        oracle.setFeed(address(0), address(ethFeed), 4 hours, 18);
    }

    // ── the peg ─────────────────────────────────────────────────────────────

    /// @notice A PEGGED stable prices at $1 with no feed, so it cannot go stale.
    ///         This is the live outage that motivated it: Sepolia's USDC/USD feed
    ///         drifted 23.7h against a 12h heartbeat, the oracle correctly said
    ///         "cannot judge", and a USDG generation recorded NO volume at all.
    function test_F14_PeggedStableNeedsNoFeed() public {
        oracle.setPegged(address(usdg), 0);   // 0 = read decimals from the token
        uint256 f = oracle.usdPerRawUnit(address(usdg));

        // usdVolume = raw * factor / 1e18. One whole 6-dec token must be $1.
        assertEq((1e6 * f) / 1e18, 1e18, "one USDG must price at exactly $1");

        // A month later it still answers — there is nothing to go stale.
        vm.warp(block.timestamp + 30 days);
        assertEq(oracle.usdPerRawUnit(address(usdg)), f, "a peg cannot go stale");
    }

    /// @notice The peg is decimal-correct, not just correct at 6.
    function test_F14_PegHandlesAnyDecimals() public {
        oracle.setPegged(address(0xDA1), 18);
        uint256 f18 = oracle.usdPerRawUnit(address(0xDA1));
        assertEq((1e18 * f18) / 1e18, 1e18, "one 18-dec token must price at $1");
    }

    // ── the four failure modes ──────────────────────────────────────────────

    /// @notice STALE.
    function test_F14_StaleFeedRefusesToAnswer() public {
        assertGt(oracle.usdPerRawUnit(address(0)), 0, "fresh feed answers");
        vm.warp(block.timestamp + 5 hours);   // heartbeat is 4h
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "a stale feed must not be believed");
    }

    /// @notice DEAD — reverts rather than returning anything.
    function test_F14_DeadFeedDoesNotBubbleUp() public {
        ethFeed.setBoom(true);
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "a reverting feed must resolve to 0");
    }

    /// @notice NONSENSE — non-positive, or dated in the future.
    function test_F14_NonsenseAnswersRefused() public {
        ethFeed.set(0, block.timestamp);
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "zero price is not a price");
        ethFeed.set(-1, block.timestamp);
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "negative price is not a price");
        ethFeed.set(2400e8, block.timestamp + 1 days);
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "a future timestamp is not trustworthy");
    }

    /// @notice FRESH AND WRONG — the one with teeth, and the only one a band
    ///         catches. Without bounds this answer is believed completely.
    function test_F14_AMispricedFeedCannotInflateVolume() public {
        // No bounds yet: a 4000x answer sails through every other check.
        ethFeed.set(10_000_000e8, block.timestamp);
        assertGt(oracle.usdPerRawUnit(address(0)), 0, "unbounded, the lie is believed");

        oracle.setBounds(address(0), uint128(100e18), uint128(100_000e18));
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "$10m/ETH must be refused");

        // And the other direction — a feed reporting near-zero would deflate
        // volume until the brew read as dead.
        ethFeed.set(1e8, block.timestamp);
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "$1/ETH must be refused");

        // A real price still passes.
        ethFeed.set(2400e8, block.timestamp);
        assertGt(oracle.usdPerRawUnit(address(0)), 0, "a sane price must still answer");
    }

    /// @notice Bounds are optional per side, so one can be set without the other.
    function test_F14_OpenEndedBounds() public {
        oracle.setBounds(address(0), uint128(100e18), 0);   // floor only
        ethFeed.set(10_000_000e8, block.timestamp);
        assertGt(oracle.usdPerRawUnit(address(0)), 0, "no ceiling means no ceiling");
        ethFeed.set(1e8, block.timestamp);
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "the floor still binds");
    }

    // ── authority ───────────────────────────────────────────────────────────

    /// @notice Pricing is owner-only. Choosing which assets exist and choosing
    ///         how they are priced are the same decision, and neither is votable.
    function test_F14_OnlyOwnerMayPrice() public {
        vm.startPrank(address(0xBAD));
        vm.expectRevert(QuoteOracle.NotOwner.selector);
        oracle.setPegged(address(usdg), 6);
        vm.expectRevert(QuoteOracle.NotOwner.selector);
        oracle.setBounds(address(0), 1, 2);
        vm.stopPrank();
    }

    /// @notice An inverted band is refused rather than silently rejecting every
    ///         answer, which would look exactly like a dead feed.
    function test_F14_InvertedBandRefused() public {
        vm.expectRevert(QuoteOracle.BadConfig.selector);
        oracle.setBounds(address(0), uint128(100e18), uint128(10e18));
    }

    /// @notice Re-pointing a pegged asset at a real feed clears the peg, so the
    ///         two configurations can never both be live.
    function test_F14_SettingAFeedClearsThePeg() public {
        oracle.setPegged(address(usdg), 6);
        assertGt(oracle.usdPerRawUnit(address(usdg)), 0, "pegged answers");

        MockFeed f = new MockFeed(1e8, 8);
        oracle.setFeed(address(usdg), address(f), 12 hours, 6);
        vm.warp(block.timestamp + 13 hours);   // now stale
        assertEq(oracle.usdPerRawUnit(address(usdg)), 0, "the peg must not survive a setFeed");
    }
}
