// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SeedLib} from "../cauldron/SeedLib.sol";

/// Pure-math unit tests for the progressive-seed library: schedule + band
/// geometry (ask below launch / bid above launch, per the ETH=currency0 ordering).
contract SeedLibTest is Test {
    int24 constant SPACING = 200;
    int24 constant LAUNCH = 12_000; // arbitrary aligned-ish launch tick
    int24 constant CEIL = 16_000;   // ask ceiling offset (~5×)
    int24 constant FLOOR = 16_000;  // bid floor offset (~−80%)

    // ── SCHEDULE ────────────────────────────────────────────────────────────
    function test_Schedule_FloorAtStart() public pure {
        uint256 w = SeedLib.deployedTargetWad(1000, 3600, 1000, 0.1e18);
        assertEq(w, 0.1e18, "at start = seed floor");
    }

    function test_Schedule_BeforeStartClampsToFloor() public pure {
        uint256 w = SeedLib.deployedTargetWad(1000, 3600, 500, 0.1e18);
        assertEq(w, 0.1e18, "before start = floor");
    }

    function test_Schedule_FullAtWindowEnd() public pure {
        uint256 w = SeedLib.deployedTargetWad(1000, 3600, 1000 + 3600, 0.1e18);
        assertEq(w, 1e18, "at window end = 100%");
    }

    function test_Schedule_ClampsAfterWindow() public pure {
        uint256 w = SeedLib.deployedTargetWad(1000, 3600, 1_000_000, 0.1e18);
        assertEq(w, 1e18, "after window = 100%");
    }

    function test_Schedule_LinearHalfway() public pure {
        uint256 w = SeedLib.deployedTargetWad(1000, 3600, 1000 + 1800, 0.1e18);
        // 0.1 + 0.9 * 0.5 = 0.55
        assertApproxEqAbs(w, 0.55e18, 1e6, "halfway = floor + half of remainder");
    }

    function test_Schedule_MonotonicNonDecreasing() public pure {
        uint256 prev = 0;
        for (uint256 t = 900; t <= 1000 + 3600 + 100; t += 137) {
            uint256 w = SeedLib.deployedTargetWad(1000, 3600, t, 0.1e18);
            assertGe(w, prev, "monotonic non-decreasing");
            assertLe(w, 1e18, "never exceeds 100%");
            prev = w;
        }
    }

    function test_Schedule_ZeroWindowIsAtomic() public pure {
        assertEq(SeedLib.deployedTargetWad(1000, 0, 1000, 0.1e18), 1e18, "window 0 = instant 100%");
    }

    // ── ASK BANDS (token, below launch) ─────────────────────────────────────
    function test_AskBands_AllBelowLaunch_AndAligned() public pure {
        uint256 n = 3;
        int24 L = SeedLib._alignDown(LAUNCH, SPACING);
        for (uint256 i = 0; i < n; i++) {
            (int24 lo, int24 hi) = SeedLib.askBand(i, n, LAUNCH, SPACING, CEIL);
            assertLt(lo, hi, "lower < upper");
            assertLe(hi, L, "ask band upper <= launch (pure token1 at seed)");
            assertEq(lo % SPACING, 0, "lower aligned");
            assertEq(hi % SPACING, 0, "upper aligned");
        }
    }

    function test_AskBands_Band0IsHottest_AndContiguous() public pure {
        uint256 n = 4;
        int24 L = SeedLib._alignDown(LAUNCH, SPACING);
        (, int24 hi0) = SeedLib.askBand(0, n, LAUNCH, SPACING, CEIL);
        assertEq(hi0, L, "band 0 upper == launch (adjacent, hottest)");
        // contiguous: band i's lower == band i+1's upper
        for (uint256 i = 0; i + 1 < n; i++) {
            (int24 loI, ) = SeedLib.askBand(i, n, LAUNCH, SPACING, CEIL);
            (, int24 hiNext) = SeedLib.askBand(i + 1, n, LAUNCH, SPACING, CEIL);
            assertEq(loI, hiNext, "ask bands contiguous (no gap/overlap)");
        }
    }

    // ── BID BANDS (ETH, above launch) ───────────────────────────────────────
    function test_BidBands_AllAboveLaunch_AndAligned() public pure {
        uint256 m = 3;
        int24 L = SeedLib._alignDown(LAUNCH, SPACING);
        for (uint256 j = 0; j < m; j++) {
            (int24 lo, int24 hi) = SeedLib.bidBand(j, m, LAUNCH, SPACING, FLOOR);
            assertLt(lo, hi, "lower < upper");
            assertGt(lo, L, "bid band lower > launch (pure ETH at seed)");
            assertEq(lo % SPACING, 0, "lower aligned");
            assertEq(hi % SPACING, 0, "upper aligned");
        }
    }

    function test_BidBands_Band0Adjacent_AndContiguous() public pure {
        uint256 m = 4;
        int24 L = SeedLib._alignDown(LAUNCH, SPACING);
        (int24 lo0, ) = SeedLib.bidBand(0, m, LAUNCH, SPACING, FLOOR);
        assertEq(lo0, L + SPACING, "bid band 0 starts one spacing above launch");
        for (uint256 j = 0; j + 1 < m; j++) {
            (, int24 hiJ) = SeedLib.bidBand(j, m, LAUNCH, SPACING, FLOOR);
            (int24 loNext, ) = SeedLib.bidBand(j + 1, m, LAUNCH, SPACING, FLOOR);
            assertEq(hiJ, loNext, "bid bands contiguous");
        }
    }

    // ask and bid must never overlap (they straddle the launch seam)
    function test_AskBid_NoOverlapAtSeam() public pure {
        (, int24 askHi) = SeedLib.askBand(0, 3, LAUNCH, SPACING, CEIL);
        (int24 bidLo, ) = SeedLib.bidBand(0, 3, LAUNCH, SPACING, FLOOR);
        assertLe(askHi, bidLo, "ask top <= bid bottom (disjoint across launch)");
    }

    function test_SingleBand_Works() public pure {
        (int24 aLo, int24 aHi) = SeedLib.askBand(0, 1, LAUNCH, SPACING, CEIL);
        (int24 bLo, int24 bHi) = SeedLib.bidBand(0, 1, LAUNCH, SPACING, FLOOR);
        assertLt(aLo, aHi);
        assertLt(bLo, bHi);
    }

    // ── TAPER WEIGHTS ───────────────────────────────────────────────────────
    function test_Taper_SumsToWad_AndDescends() public pure {
        for (uint256 n = 1; n <= 8; n++) {
            uint256 sum;
            uint256 prev = type(uint256).max;
            for (uint256 i = 0; i < n; i++) {
                uint256 wgt = SeedLib.taperWeightWad(i, n);
                assertLe(wgt, prev, "weights descend (most near launch)");
                prev = wgt;
                sum += wgt;
            }
            // integer division dust: within n wei of 1e18
            assertApproxEqAbs(sum, 1e18, n, "weights sum to ~1e18");
        }
    }

    function test_Taper_Band0HeaviestForN() public pure {
        assertGt(SeedLib.taperWeightWad(0, 5), SeedLib.taperWeightWad(4, 5), "band0 > last");
    }

    // ── FUZZ: geometry invariants hold across launch ticks / offsets / counts ─
    function testFuzz_BandsValid(int24 launch, uint8 nRaw, uint8 mRaw, int24 ceil, int24 fl) public pure {
        launch = int24(bound(launch, -400_000, 400_000));
        uint256 n = uint256(bound(nRaw, 1, 8));
        uint256 m = uint256(bound(mRaw, 1, 8));
        ceil = int24(bound(ceil, 2000, 120_000));
        fl = int24(bound(fl, 2000, 120_000));

        int24 L = SeedLib._alignDown(launch, SPACING);
        for (uint256 i = 0; i < n; i++) {
            (int24 lo, int24 hi) = SeedLib.askBand(i, n, launch, SPACING, ceil);
            assertLt(lo, hi, "ask lo<hi");
            assertLe(hi, L, "ask <= launch");
        }
        for (uint256 j = 0; j < m; j++) {
            (int24 lo, int24 hi) = SeedLib.bidBand(j, m, launch, SPACING, fl);
            assertLt(lo, hi, "bid lo<hi");
            assertGt(lo, L, "bid > launch");
        }
    }
}
