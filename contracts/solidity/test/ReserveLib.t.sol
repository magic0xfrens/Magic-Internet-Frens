// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ReserveLib} from "../cauldron/ReserveLib.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * Pure-math tests for the migration/genesis reserve. These validate the ONE
 * thing most likely to be silently wrong — the tick ORIENTATION (ETH=currency0,
 * so token appreciation moves the pool price DOWN) — plus the exact-N claim
 * round-trip. No fork needed: this is deterministic AMM geometry.
 */
contract ReserveLibTest is Test {
    int24 constant SPACING = 200;
    int24 constant OFFSET = 42400; // ≈ 69x

    /// The reserve range must sit strictly BELOW the launch tick, so at launch
    /// (currentTick == launchTick) the position is out of range on the token1
    /// side (currentTick > tickUpper) → pure token, zero ETH.
    function test_ReserveIsBelowLaunch() public pure {
        int24 launchTick = 227000; // a representative high launch tick
        (int24 lo, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, OFFSET);
        assertLt(hi, launchTick, "reserve upper must be below launch tick");
        assertLt(lo, hi, "lower < upper");
        // Ceiling is ~offset below launch (aligned).
        assertApproxEqAbs(int256(launchTick - hi), int256(OFFSET), uint256(uint24(SPACING)), "ceiling ~= offset");
        // Ticks are spacing-aligned.
        assertEq(hi % SPACING, 0, "upper aligned");
        assertEq(lo % SPACING, 0, "lower aligned");
    }

    /// The ceiling really is ~69x: price at reserveTickUpper is ~1/69 of launch
    /// price (tokens-per-ETH falls 69x ⇔ each token worth 69x more ETH).
    function test_Ceiling_Is_69x() public pure {
        int24 launchTick = 180000;
        (, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, OFFSET);
        uint160 pLaunch = TickMath.getSqrtPriceAtTick(launchTick);
        uint160 pCeil = TickMath.getSqrtPriceAtTick(hi);
        // price ratio = (sqrtLaunch/sqrtCeil)^2 ; token value multiple = that ratio.
        uint256 ratioX = (uint256(pLaunch) * 1e6) / uint256(pCeil); // sqrt-price ratio *1e6
        uint256 mult = (ratioX * ratioX) / 1e12; // square → price multiple
        assertApproxEqAbs(mult, 69, 3, "token appreciation ceiling ~= 69x");
    }

    /// Removing `liquidityForTokenOut(N)` from the out-of-range reserve yields
    /// EXACTLY (≤, rounded down) N token and ZERO ETH — the core claim invariant.
    function test_ExactTokenOut_ZeroEth() public pure {
        int24 launchTick = 200000;
        (int24 lo, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, OFFSET);

        uint256 N = 12_345_678e18;
        uint128 L = ReserveLib.liquidityForTokenOut(lo, hi, N);
        assertGt(L, 0, "nonzero liquidity");

        uint160 sLo = TickMath.getSqrtPriceAtTick(lo);
        uint160 sHi = TickMath.getSqrtPriceAtTick(hi);

        // The position is fully BELOW the current price (out of range on the
        // token1 side), so a removal returns pure token1 = getAmount1Delta over
        // [sLo,sHi], and token0 (ETH) is ZERO by geometry — the current price
        // never enters the range, so no token0 is owed. (The fork test asserts
        // the zero-ETH against the live PoolManager.)
        uint256 tokenOut = SqrtPriceMath.getAmount1Delta(sLo, sHi, L, false);

        // Rounded down, so tokenOut <= N and within liquidity granularity of N.
        assertLe(tokenOut, N, "never over-withdraws");
        assertApproxEqRel(tokenOut, N, 1e12, "approx exact N (rounding dust only)"); // within 1e-6
    }

    /// Sizing the whole reserve and then claiming a slice conserves: the sum of
    /// claim liquidities never exceeds the seeded reserve liquidity.
    function test_Claims_NeverExceedReserve() public pure {
        int24 launchTick = 210000;
        (int24 lo, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, OFFSET);

        uint256 total = 700_000_000e18;
        uint128 Ltotal = ReserveLib.liquidityForTokenOut(lo, hi, total);

        uint256 c1 = 100_000_000e18;
        uint256 c2 = 250_000_000e18;
        uint128 L1 = ReserveLib.liquidityForTokenOut(lo, hi, c1);
        uint128 L2 = ReserveLib.liquidityForTokenOut(lo, hi, c2);
        assertLe(uint256(L1) + uint256(L2), Ltotal, "partial claims fit within reserve");
    }

    /// Degenerate guard: an absurdly low launch tick can't produce an invalid
    /// (inverted/zero-width) reserve band.
    function test_DegenerateLaunchTick() public pure {
        int24 launchTick = TickMath.MIN_TICK + 1000;
        (int24 lo, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, OFFSET);
        assertLt(lo, hi, "band stays valid even at extreme low launch tick");
    }
}
