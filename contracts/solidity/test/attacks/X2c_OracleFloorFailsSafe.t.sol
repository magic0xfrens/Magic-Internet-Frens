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
 * X2c — REGRESSION. An unpriceable or dead feed used to delete the rotation floor
 *       instead of stopping the rotation.
 *
 * `QuoteRotator._oracleFloor` (QuoteRotator.sol:420) returns 0 for "cannot value
 * this", and `swapOnce` then enforced `max(minOut, floor)` — so 0 meant NO FLOOR,
 * on the one path (`RedemptionExt.rotateSliceFrom`) that is PERMISSIONLESS and
 * whose `minOut` comes from the caller. The frontend signs a flat 1-unit minimum,
 * so in that state the only surviving guard was the venue allowlist.
 *
 * NOT THE TIMESTAMP. The first-stated mechanism — `QuoteOracle.cachedUsdPerRawUnit`
 * re-stamping `c.at` on a failed refresh — was REFUTED by execution: applying that
 * fix flipped the timestamp assertion and the stale price survived, because the real
 * line is `if (fresh > 0) c.factor = fresh; return c.factor;` (QuoteOracle.sol:308).
 * And the naive repair (zero the factor) is strictly worse: it makes `_oracleFloor`
 * return 0, which is the no-floor case this test is about. The cache is LEFT ALONE —
 * for volume accounting a stale price genuinely beats a zero, which would read as
 * "no trading" and push a live generation toward death.
 *
 * FIX, in two halves:
 *   1. `_oracleFloor` values both legs through `usdPerRawUnit` (uncached), so a dead
 *      feed reports 0 rather than the factor frozen at the moment it died.
 *   2. `swapOnce` reverts `NotPriceable` when an oracle IS wired and returns no
 *      floor, BEFORE touching the pool. A deployment with no oracle at all is
 *      unchanged — nothing there can invent a price.
 */
contract X2c_OracleFloorFailsSafe is Test {
    QuoteRotator internal rotator;
    QuoteOracle  internal oracle;
    MockAggregator internal ethFeed;
    MockAggregator internal qFeed;

    /// The destination quote. Sorts above native, so it is `currency1`.
    address internal constant Q = address(0xEEEE);

    /// This test IS the registry (so `swapOnce`'s `onlyRegistry` passes) AND the
    /// rotator's owner, so it can curate the venue.
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
        rotator.setVenue(_route(), true);
    }

    function _route() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(Q),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    /// @dev The rotation a permissionless caller signs: 1 ETH in, `minOut` of Q,
    ///      through the curated venue. Returns the revert selector (0 on success).
    function _rotate(uint256 minOut) internal returns (bytes4 sel) {
        PoolKey memory r = _route();
        try rotator.swapOnce(r, address(0), Q, 1 ether, minOut) returns (uint256) {
            return bytes4(0);
        } catch (bytes memory err) {
            if (err.length >= 4) {
                assembly { sel := mload(add(err, 32)) }
            }
        }
    }

    /// @dev How a retired aggregator breaks: it still answers, `updatedAt` stops.
    function _killFeed() internal { qFeed.setStale(true); }

    // ── CONTROL: a healthy oracle does NOT refuse ────────────────────────────

    function test_X2c_control_healthyFeedClearsTheFloorCheck() public {
        bytes4 sel = _rotate(0);
        assertTrue(oracle.priceable(Q), "precondition: the destination is priceable");
        assertTrue(
            sel != QuoteRotator.NotPriceable.selector,
            "a priceable pair is never refused for want of a floor"
        );
    }

    // ── THE FINDING: a dead feed must STOP the rotation, not unguard it ──────

    function test_X2c_deadFeedRefusesThePermissionlessRotation() public {
        // Prime the cache while the feed is healthy — this is the state in which the
        // cached factor is a lie waiting to be used.
        oracle.cachedUsdPerRawUnit(Q);
        _killFeed();
        vm.warp(block.timestamp + 365 days);

        (uint256 cachedFactor,,) = oracle.cache(Q);
        assertGt(cachedFactor, 0, "the cache still holds the pre-death factor...");
        assertFalse(oracle.priceable(Q), "...while the asset genuinely cannot be valued");

        // minOut = 0 is what a caller supplies to disarm the guard; minOut = 1 is what
        // the frontend actually signs. Both must be refused, not merely bounded.
        assertEq(_rotate(0), QuoteRotator.NotPriceable.selector, "FIXED: refused, not unguarded");
        assertEq(_rotate(1), QuoteRotator.NotPriceable.selector, "FIXED: the UI's 1-unit minimum too");
        emit log_named_uint("X2c frozen cache factor still on record", cachedFactor);
    }

    /// @dev An UNWIRED oracle is a different statement from an oracle that declines.
    ///      That deployment is bounded by `minOut` by design and must keep working.
    function test_X2c_noOracleWiredIsUnchanged() public {
        rotator.setArbParams(address(0), 1000, 5e18);
        assertTrue(
            _rotate(0) != QuoteRotator.NotPriceable.selector,
            "no oracle wired: the floor cannot exist and is not demanded"
        );
    }
}
