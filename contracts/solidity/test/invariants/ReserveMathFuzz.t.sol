// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {ReserveLib} from "../../cauldron/ReserveLib.sol";
import {SeedLib} from "../../cauldron/SeedLib.sol";

/**
 * @title ReserveMathFuzz
 * @notice Pure FUZZ tests for the two libraries the whole redemption/floor promise
 *         rests on.
 *
 *  {ReserveLib} — the out-of-range band that holds 100% of the un-circulating
 *  supply. If its ticks are ever mis-oriented (band NOT strictly below the launch
 *  tick) the reserve stops being pure token1 and can be SOLD into by traders,
 *  which would destroy the migration/genesis backing. If `liquidityForTokenOut`
 *  ever rounded UP, a claim could pull more than it is owed.
 *
 *  {SeedLib} — the progressive-launch schedule and band geometry. The schedule
 *  must be monotone and capped at 100% (so a poke can never over-deploy) and the
 *  ask/bid bands must sit on the correct side of spot (so each is single-sided).
 *
 *  Run: FOUNDRY_PROFILE=cauldron forge test --match-contract ReserveMathFuzz
 *  (No fork required.)
 */
contract ReserveMathFuzz is Test {
    int24 constant SPACING = 200;

    // ── ReserveLib ─────────────────────────────────────────────────────────

    /// R-1: the reserve band is always valid, aligned and strictly ordered.
    function testFuzz_ReserveTicksAreWellFormed(int24 launchTick, int24 offset) public pure {
        launchTick = int24(bound(int256(launchTick), TickMath.MIN_TICK, TickMath.MAX_TICK));
        offset = int24(bound(int256(offset), 4000, 138_000));

        (int24 lo, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, offset);

        assertLt(lo, hi, "R-1: band must be non-empty");
        assertEq(lo % SPACING, 0, "R-1: lower aligned");
        assertEq(hi % SPACING, 0, "R-1: upper aligned");
        assertGe(int256(lo), int256(TickMath.MIN_TICK), "R-1: lower >= MIN_TICK");
        assertLe(int256(hi), int256(TickMath.MAX_TICK), "R-1: upper <= MAX_TICK");
    }

    /// R-2 ORIENTATION (the footgun): the band sits strictly BELOW the launch tick
    ///     whenever the range is not degenerate, so the position is pure token1 and
    ///     cannot be bought out of the reserve by ordinary trading.
    function testFuzz_ReserveSitsBelowLaunchTick(int24 launchTick, int24 offset) public pure {
        offset = int24(bound(int256(offset), 4000, 138_000));
        // Only meaningful where launch - offset does not underflow the usable range.
        launchTick = int24(bound(int256(launchTick), int256(TickMath.MIN_TICK) + int256(offset) + 400, TickMath.MAX_TICK));

        (, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, offset);
        assertLe(int256(hi), int256(launchTick), "R-2: reserve upper must be <= launch tick");
        assertLe(int256(hi), int256(launchTick) - int256(offset) + int256(SPACING), "R-2: at least `offset` below launch");
    }

    /// R-3 NEVER OVER-DELIVERS: the liquidity that represents `amount1` must, when
    ///     converted back, yield at most `amount1`. A round-UP here would let a
    ///     claimer pull more than they burned.
    /// @dev Domain restricted to the REACHABLE launch-tick band. A Cauldron pool
    ///      prices ~777e24 token-wei against ~1e18..1e21 ETH-wei, so its launch tick
    ///      is strongly positive (~+204,000 at genesis). Below roughly -480,000 the
    ///      reserve band becomes so narrow in sqrt-price terms that
    ///      `getLiquidityForAmount1` overflows uint128 and reverts SafeCastOverflow
    ///      (see audit finding I-05); that regime is unreachable for this token's
    ///      economics but is asserted as out-of-domain here rather than hidden.
    function testFuzz_LiquidityForTokenOutRoundsDown(int24 launchTick, uint256 amount) public pure {
        launchTick = int24(bound(int256(launchTick), -400_000, 600_000));
        // Cap at ~1.3x the protocol's entire fixed supply (777e24 wei).
        amount = bound(amount, 1e6, 1e27);
        (int24 lo, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, 42_400);

        uint128 L = ReserveLib.liquidityForTokenOut(lo, hi, amount);
        // Inverse of getLiquidityForAmount1: amount1 = L * (sqrtHi - sqrtLo) / Q96,
        // rounded DOWN — exactly what a full-range-below removal returns.
        uint256 back = FullMath.mulDiv(
            uint256(L),
            uint256(TickMath.getSqrtPriceAtTick(hi)) - uint256(TickMath.getSqrtPriceAtTick(lo)),
            0x1000000000000000000000000
        );
        assertLe(back, amount, "R-3: reserve math must round DOWN, never up");
    }

    /// R-4 MONOTONE: asking for more tokens never yields less liquidity.
    function testFuzz_LiquidityMonotoneInAmount(uint256 a, uint256 b) public pure {
        a = bound(a, 1e12, 1e27);
        b = bound(b, 1e12, 1e27);
        (uint256 lowA, uint256 highB) = a <= b ? (a, b) : (b, a);
        (int24 lo, int24 hi) = ReserveLib.reserveTicks(0, SPACING, 42_400);
        assertLe(
            ReserveLib.liquidityForTokenOut(lo, hi, lowA),
            ReserveLib.liquidityForTokenOut(lo, hi, highB),
            "R-4: liquidity must be monotone in the token amount"
        );
    }

    // ── SeedLib ────────────────────────────────────────────────────────────

    /// S-1 SCHEDULE: monotone non-decreasing in time, floored at `seedFloor`,
    ///     capped at 100%. This is what makes a poke un-accelerable: the target is
    ///     a pure function of elapsed time, so nobody can over-deploy the tranche.
    function testFuzz_ScheduleIsMonotoneAndCapped(
        uint64 start, uint64 window, uint256 t1, uint256 t2, uint256 floorWad
    ) public pure {
        start = uint64(bound(start, 1, type(uint32).max));
        window = uint64(bound(window, 1, 30 days));
        floorWad = bound(floorWad, 1, 1e18);
        t1 = bound(t1, 0, uint256(start) + uint256(window) * 3);
        t2 = bound(t2, t1, uint256(start) + uint256(window) * 3);

        uint256 w1 = SeedLib.deployedTargetWad(start, window, t1, floorWad);
        uint256 w2 = SeedLib.deployedTargetWad(start, window, t2, floorWad);

        assertLe(w1, w2, "S-1: schedule must be monotone in time");
        assertLe(w2, 1e18, "S-1: never above 100%");
        assertGe(w1, floorWad > 1e18 ? 1e18 : floorWad, "S-1: never below the seed floor");
        if (t2 >= uint256(start) + window) assertEq(w2, 1e18, "S-1: fully deployed by window end");
    }

    /// S-2 window == 0 is the degenerate/atomic case: always 100%.
    function testFuzz_ZeroWindowIsAtomic(uint64 start, uint256 t, uint256 floorWad) public pure {
        assertEq(SeedLib.deployedTargetWad(start, 0, t, bound(floorWad, 0, 1e18)), 1e18, "S-2");
    }

    /// S-3 BAND ORIENTATION: ask (token) bands are at or below the aligned launch
    ///     tick and bid (ETH) bands are strictly above it — the property that makes
    ///     each band single-sided at placement time.
    function testFuzz_BandOrientation(int24 launchTick, uint256 i, uint256 n, int24 off) public pure {
        launchTick = int24(bound(int256(launchTick), -500_000, 500_000));
        n = bound(n, 1, 16);
        i = bound(i, 0, n - 1);
        off = int24(bound(int256(off), 200, 100_000));

        (int24 aLo, int24 aHi) = SeedLib.askBand(i, n, launchTick, SPACING, off);
        (int24 bLo, int24 bHi) = SeedLib.bidBand(i, n, launchTick, SPACING, off);

        int24 L = SeedLib._alignDown(launchTick, SPACING);
        assertLt(aLo, aHi, "S-3: ask band non-empty");
        assertLt(bLo, bHi, "S-3: bid band non-empty");
        assertLe(int256(aHi), int256(L), "S-3: ask band at/below the aligned launch tick (pure token1)");
        assertGt(int256(bLo), int256(L), "S-3: bid band strictly above the launch tick (pure ETH)");
        assertGe(int256(aLo), int256(TickMath.MIN_TICK), "S-3: ask floor within range");
        assertLe(int256(bHi), int256(TickMath.MAX_TICK), "S-3: bid ceiling within range");
    }

    /// S-4 the taper weights sum to 1e18 up to integer dust, so a full sweep of the
    ///     bands never allocates more than the tranche.
    function testFuzz_TaperWeightsSumToOne(uint256 n) public pure {
        n = bound(n, 1, 64);
        uint256 sum;
        for (uint256 i; i < n; i++) sum += SeedLib.taperWeightWad(i, n);
        assertLe(sum, 1e18, "S-4: taper must never over-allocate");
        assertGe(sum + n, 1e18, "S-4: taper allocates ~everything (dust only)");
    }
}
