// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {MockAggregator} from "../../cauldron/MockAggregator.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/// @dev Registry stub for QuoteRotator._allowed.
contract T02Reg {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * T02 — QuoteOracle cache: does a REFRESH THAT FAILS make the cache stale, or
 * make it PERMANENT?
 *
 * `cachedUsdPerRawUnit` stamps `c.at = block.timestamp` on EVERY refresh
 * attempt, but only writes `c.factor` when the refresh SUCCEEDED. So an
 * indefinitely broken feed keeps re-arming the TTL against a price that was
 * last true an arbitrarily long time ago, and the public `cache()` getter
 * reports a fresh `at` for it.
 */
contract T02_OracleCacheStaleness is Test {
    QuoteOracle internal oracle;
    MockAggregator internal ethFeed;
    QuoteRotator internal rotator;
    T02Reg internal reg;
    MockQuoteToken internal usdg;

    address constant NATIVE = address(0);

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.roll(1_000);
        oracle = new QuoteOracle(address(this));
        ethFeed = new MockAggregator("ETH/USD", 3_000e8);
        oracle.setFeed(NATIVE, address(ethFeed), 1 hours, 18);

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        oracle.setPegged(address(usdg), 6);

        reg = new T02Reg();
        reg.set(address(usdg), true);
        rotator = new QuoteRotator(address(reg), IPoolManager(address(0xDEAD)));
        rotator.setArbParams(address(oracle), 1000, 5e18);
    }

    /// @notice A DEAD feed's last price is served FOREVER, and the cache's own
    /// timestamp reports it as fresh.
    function test_T02_POC_CacheNeverExpiresWhileTheFeedIsDown() public {
        uint256 good = oracle.cachedUsdPerRawUnit(NATIVE);
        assertGt(good, 0, "precondition: the feed answers");
        console2.log("factor while healthy  :", good);

        // The aggregator retires / migrates / loses access control. Every
        // subsequent fresh read resolves to 0 inside usdPerRawUnit's try/catch.
        ethFeed.setDown(true);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "fresh path is unusable");

        // One year later, with the feed down the whole time.
        for (uint256 i; i < 12; ++i) {
            vm.warp(vm.getBlockTimestamp() + 30 days);
            oracle.cachedUsdPerRawUnit(NATIVE); // whoever trades keeps re-arming it
        }

        uint256 aYearLater = oracle.cachedUsdPerRawUnit(NATIVE);
        (uint256 f, uint64 at) = oracle.cache(NATIVE);
        console2.log("factor a YEAR later   :", aYearLater);
        console2.log("cache.at (reported)   :", at);
        console2.log("block.timestamp       :", vm.getBlockTimestamp());
        console2.log("apparent cache age (s):", vm.getBlockTimestamp() - at);

        assertEq(aYearLater, good, "the year-old price is still being served");
        assertEq(f, good, "cache.factor never degraded");
        // The tell: the stored timestamp is the last ATTEMPT, not the last
        // SUCCESS, so nothing on-chain or off-chain can measure the real age.
        assertLe(
            vm.getBlockTimestamp() - at, oracle.TTL(),
            "cache.at reports the price as fresh, though it is a year old"
        );
        bool reached = true;
        assertTrue(reached, "T02 cache-never-expires reached its assertions");
    }

    /// @notice The rotation's ORACLE FLOOR — the guard that stops a caller
    /// supplying `minOut = 0` — is computed from that year-old price.
    /// `_oracleFloor` is internal; `arbStep`'s `_usd` uses the same
    /// `cachedUsdPerRawUnit` call, so the staleness is observed through
    /// the identical code path the floor uses.
    function test_T02_POC_RotationFloorIsBuiltOnTheStalePrice() public {
        // Price at the moment of the outage.
        uint256 atOutage = oracle.cachedUsdPerRawUnit(NATIVE);
        ethFeed.setDown(true);

        // Six months pass. ETH is now worth a quarter of what it was, but the
        // feed never came back, so nothing in the system knows.
        vm.warp(vm.getBlockTimestamp() + 180 days);
        uint256 servedNow = oracle.cachedUsdPerRawUnit(NATIVE);

        // What a 10 ETH slice is "worth" per the oracle the floor uses.
        uint256 valuedUsd = (10 ether * servedNow) / 1e18;
        console2.log("oracle says 10 ETH is $:", valuedUsd / 1e18);
        assertEq(servedNow, atOutage, "floor input is the pre-outage price");
        assertEq(valuedUsd / 1e18, 30_000, "the floor prices 10 ETH at the 6-month-old $3,000");

        // And the whole thing is silent: `priceable` (the view TreasuryGovernor
        // gates a rotation target on) correctly says NO, while the cached path
        // the floor actually uses says YES. The two disagree permanently.
        assertFalse(oracle.priceable(NATIVE), "priceable(): cannot price it");
        assertGt(oracle.cachedUsdPerRawUnit(NATIVE), 0, "cached(): confidently prices it");
        bool reached = true;
        assertTrue(reached, "T02 stale-floor reached its assertions");
    }

    /// @notice Control: the cache DOES work as advertised for a merely-lapsed
    /// heartbeat that later recovers. Included so the finding above is
    /// not read as "caching is wrong".
    function test_T02_CONTROL_CacheRecoversWhenTheFeedDoes() public {
        oracle.cachedUsdPerRawUnit(NATIVE);
        ethFeed.setStale(true);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        assertEq(oracle.usdPerRawUnit(NATIVE), 0, "stale");
        ethFeed.setStale(false);
        ethFeed.peg(4_000e8);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        assertEq(
            oracle.cachedUsdPerRawUnit(NATIVE), 4_000e18 * 1e18 / 1e18,
            "a recovered feed does update the cache"
        );
        bool reached = true;
        assertTrue(reached, "T02 control reached its assertions");
    }
}
