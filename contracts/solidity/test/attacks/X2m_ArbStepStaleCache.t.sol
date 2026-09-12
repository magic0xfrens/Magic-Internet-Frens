// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {MockAggregator} from "../../cauldron/MockAggregator.sol";

/**
 * X2m — REGRESSION, two halves of one finding.
 *
 * ROOT CAUSE (QuoteOracle.cachedUsdPerRawUnit). `c.at = uint64(block.timestamp)`
 * ran BEFORE the `fresh > 0` test, so it advanced whether the feed answered or not.
 * Together with `if (fresh > 0) c.factor = fresh;` — which RETAINS the last good
 * factor — a dead, out-of-band or sequencer-grace feed served a price that was both
 * stale AND permanently self-certifying: the TTL early-return handed out the
 * pre-death factor for another full window, forever, and any freshness check written
 * against `c.at` passed.
 *
 * Neither half is the bug alone, which is why patching one alone was measured NOT to
 * work: it flips a timestamp assertion and leaves the stale price in service. And
 * actually ZEROING the factor is worse — `QuoteRotator._oracleFloor` then returns 0,
 * i.e. no floor at all — while retention is RIGHT for the fail-open readers, because
 * volume feeds death detection and a zero there reads as "no trading".
 *
 * CONSUMER (QuoteRotator.arbStep). Both legs were valued with the CACHED reader.
 * Those two numbers are `arbStep`'s ONLY loss guard (its legs run with no
 * `sqrtPriceLimit`), the keeper's pay basis, AND the unit of the per-block notional
 * cap. `if (inUsd == 0 || outUsd == 0) revert NoRoute();` does not help: a retained
 * factor is non-zero and arbitrarily wrong.
 *
 * FIX: the factor is still retained, but `at` now means what a reader assumes —
 * last CONFIRMED — with a separate `triedAt` keeping the retry throttled so an
 * outage costs the same gas as before. And `arbStep` values both legs with the
 * uncached reader and refuses BEFORE touching the pools.
 */
contract X2m_ArbStepStaleCache is Test {
    QuoteRotator internal rotator;
    QuoteOracle internal oracle;
    MockAggregator internal ethFeed;
    MockAggregator internal qFeed;

    address internal constant Q = address(0xEEEE);

    function allowedQuote(address) external pure returns (bool) { return true; }

    function setUp() public {
        vm.warp(1_000_000);
        rotator = new QuoteRotator(address(this), IPoolManager(address(0)));
        ethFeed = new MockAggregator("ETH/USD", 3000e8);
        qFeed   = new MockAggregator("Q/USD",   1e8);
        oracle  = new QuoteOracle(address(this));
        oracle.setFeed(address(0), address(ethFeed), 4 hours, 18);
        oracle.setFeed(Q,          address(qFeed),   4 hours, 18);
        rotator.setArbParams(address(oracle), 1000, 5e18);
        rotator.setVenue(_pool(address(0)), true);
        rotator.setVenue(_pool(Q), true);
    }

    /// @dev `currency1` is the shared generation token; `currency0` is the quote.
    function _pool(address quote) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(quote),
            currency1: Currency.wrap(address(0xF00D)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
    }

    function _arb() internal returns (bytes4 sel) {
        try rotator.arbStep(_pool(address(0)), _pool(Q), 1 ether) returns (uint256) {
            return bytes4(0);
        } catch (bytes memory err) {
            if (err.length >= 4) { assembly { sel := mload(add(err, 32)) } }
        }
    }

    function _killQFeed() internal { qFeed.setStale(true); }

    // ── HALF 1: a failed refresh must not look fresh ─────────────────────────

    function test_X2m_failedRefreshKeepsTheFactorButNotTheFreshness() public {
        uint256 primed = oracle.cachedUsdPerRawUnit(Q);
        (, uint64 goodAt0,) = oracle.cache(Q);
        assertEq(primed, 1e18, "primed at $1 per raw 1e18 unit");
        assertEq(uint256(goodAt0), block.timestamp, "and confirmed now");

        _killQFeed();
        qFeed.peg(1e6); // the real price collapses 100x while the feed is mute

        vm.warp(block.timestamp + 16 minutes);
        uint256 served = oracle.cachedUsdPerRawUnit(Q);
        (, uint64 goodAt1, uint64 triedAt1) = oracle.cache(Q);

        // FAIL-OPEN READERS ARE UNCHANGED: the factor is still served, because a
        // zero here would read as "no trading" and push a live generation to death.
        assertEq(served, primed, "the factor is still retained for volume accounting");
        // FAIL-CLOSED READERS CAN NOW REFUSE: `at` did not move.
        assertEq(uint256(goodAt1), uint256(goodAt0), "FIXED: `at` records the last CONFIRMED price");
        assertGt(block.timestamp, uint256(goodAt1) + oracle.TTL(), "FIXED: so it is provably stale");
        assertEq(uint256(triedAt1), block.timestamp, "and `triedAt` still throttles the retry");

        // A year on, the staleness is still visible rather than self-certified.
        vm.warp(block.timestamp + 365 days);
        oracle.cachedUsdPerRawUnit(Q);
        (, uint64 goodAt2,) = oracle.cache(Q);
        assertEq(uint256(goodAt2), uint256(goodAt0), "FIXED: a dead feed never re-certifies itself");
    }

    // ── HALF 2: arbStep must refuse a price it cannot prove ──────────────────

    function test_X2m_arbStepRefusesAStalePrice() public {
        oracle.cachedUsdPerRawUnit(Q);        // prime the lie
        _killQFeed();
        vm.warp(block.timestamp + 365 days);

        (uint256 factor,,) = oracle.cache(Q);
        assertGt(factor, 0, "the cache still holds the pre-death factor...");
        assertFalse(oracle.priceable(Q), "...while the asset genuinely cannot be valued");

        assertEq(_arb(), QuoteRotator.NotPriceable.selector, "FIXED: refused before any swap runs");
    }

    /// @dev CONTROL: a healthy oracle is never refused for want of a price, so the
    ///      gate closes on staleness and not on arbing itself.
    function test_X2m_control_healthyFeedsClearTheGate() public {
        assertTrue(oracle.priceable(Q) && oracle.priceable(address(0)), "both legs priceable");
        assertTrue(_arb() != QuoteRotator.NotPriceable.selector, "the price gate does not fire");
    }
}
