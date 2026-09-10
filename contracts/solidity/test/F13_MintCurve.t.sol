// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MintCurvePolicy} from "../cauldron/MintCurvePolicy.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  F-13 — THE MINT LADDER, AND WHY IT CANNOT DILUTE THE FLOOR
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  THE PROPERTY THAT MATTERS. Forging an NFT must add more to the collection
 *  floor than the claim it creates, or every mint dilutes the holders before it.
 *  Written out, with `r` the share of volume that reaches the floor:
 *
 *      floorPerNFT(n) = r * SUM(cost[0..n-1]) / n
 *      minting n adds   r * cost[n]
 *      rises  <=>  cost[n] > mean(cost[0..n-1])
 *
 *  `r` cancels, and so does the token price and the quote asset — so this is a
 *  statement about the CURVE alone, provable without an oracle, and it holds for
 *  any strictly increasing ladder. These tests assert it directly rather than
 *  asserting the algebra, by simulating the floor the way the ledger builds it.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract F13_MintCurveTest is Test {
    MintCurvePolicy internal curve;

    uint256 constant SUPPLY = 3333;
    uint256 constant BASE   = 50e18;        // $50 to forge the first fren
    //  0.383748e18. Written the long way and grouped in threes: the first cut of
    //  this was one zero short, which the calibration test caught as an $350k
    //  mint-out instead of $2M — exactly the job that test exists to do.
    uint256 constant SPREAD = 383_748_000_000_000_000;
    uint256 constant KNEE   = 300;

    function setUp() public {
        curve = new MintCurvePolicy(BASE, SPREAD, KNEE, SUPPLY);
    }

    /// @notice THE INVARIANT, simulated exactly as the ledger accrues it: the
    ///         floor per NFT must strictly rise on every single mint.
    function test_F13_FloorPerNftStrictlyRises() public view {
        uint256 entitled;   // proportional to r * SUM(cost); r cancels, so drop it
        uint256 prevFloor;
        for (uint256 n; n < SUPPLY; ++n) {
            uint256 cost = curve.priceAt(n, 0, 0);
            uint256 floorAfter = (entitled + cost) / (n + 1);
            if (n > 0) {
                assertGt(floorAfter, prevFloor, "a mint must never dilute the floor");
            }
            entitled += cost;
            prevFloor = floorAfter;
        }
    }

    /// @notice And the reason it holds: the ladder is strictly increasing.
    function test_F13_LadderIsStrictlyIncreasing() public view {
        uint256 prev;
        for (uint256 k; k < SUPPLY; ++k) {
            uint256 c = curve.priceAt(k, 0, 0);
            if (k > 0) assertGt(c, prev, "cost must rise at every position");
            prev = c;
        }
    }

    /// @notice THE SHAPE. Fast early, then decelerating — the price keeps going
    ///         up but the rate it goes up AT comes down.
    function test_F13_AcceleratesThenDecelerates() public {
        // Step sizes at three points on the ladder.
        uint256 early = curve.priceAt(11, 0, 0) - curve.priceAt(10, 0, 0);
        uint256 mid   = curve.priceAt(801, 0, 0) - curve.priceAt(800, 0, 0);
        uint256 late  = curve.priceAt(3001, 0, 0) - curve.priceAt(3000, 0, 0);

        emit log_named_uint("step at #11   (wei)", early);
        emit log_named_uint("step at #801  (wei)", mid);
        emit log_named_uint("step at #3001 (wei)", late);

        // Rising early: each mint costs meaningfully more than the last.
        assertGt(mid, early, "the ladder must steepen through the knee");
        // Then flattening: the step stops growing the way it did.
        assertLt(late - mid, mid - early, "the rate of increase must decay");
        // But never turns down.
        assertGt(late, 0, "the ladder never stops rising");
    }

    /// @notice CALIBRATION. The whole collection costs what it was tuned to cost,
    ///         checked against the contract's own sum rather than a spreadsheet.
    function test_F13_MintOutCostMatchesTheTarget() public {
        uint256 total = curve.totalToMintOut();
        emit log_named_uint("mint-out total (usd 1e18)", total / 1e18);
        // 2% tolerance: `spread` is an integer, so the sum lands near the target
        // rather than exactly on it.
        assertApproxEqRel(total, 2_000_000e18, 0.02e18, "mint-out must cost ~$2M of volume");
    }

    /// @notice The first fren is cheap and the last is not — the span a collector
    ///         actually experiences.
    function test_F13_SpanIsWide() public {
        uint256 first = curve.priceAt(0, 0, 0);
        uint256 last  = curve.priceAt(SUPPLY - 1, 0, 0);
        emit log_named_uint("first fren (usd)", first / 1e18);
        emit log_named_uint("last  fren (usd)", last / 1e18);
        assertEq(first, BASE, "the first fren costs the base");
        assertGt(last, first * 20, "the last fren must cost far more than the first");
    }

    /// @notice Degenerate config is refused rather than silently disabling the
    ///         curve — the hook's own `c > 0` guard would otherwise fall back to
    ///         the linear default with no signal that the policy was ignored.
    function test_F13_BadConfigReverts() public {
        vm.expectRevert(MintCurvePolicy.BadParam.selector);
        new MintCurvePolicy(0, SPREAD, KNEE, SUPPLY);
        vm.expectRevert(MintCurvePolicy.BadParam.selector);
        new MintCurvePolicy(BASE, SPREAD, 0, SUPPLY);   // k=0 would divide by zero
        vm.expectRevert(MintCurvePolicy.BadParam.selector);
        new MintCurvePolicy(BASE, SPREAD, KNEE, 0);
    }

    /// @notice The constructor REFUSES a flat ladder, so the diluting shape
    ///         cannot be deployed by a calibration that under-shot its target.
    function test_F13_FlatLadderIsRefused() public {
        vm.expectRevert(MintCurvePolicy.BadParam.selector);
        new MintCurvePolicy(BASE, 0, KNEE, SUPPLY);
    }

    /// @notice CALIBRATION IS SELF-SCALING. `base` is a fraction of the mean, so
    ///         any mint-out target is reachable and the SHAPE is unchanged —
    ///         fixing `base` independently is what made a $20k target clamp flat.
    function test_F13_AnyTargetIsReachableAndKeepsItsShape() public {
        uint256 n = 3333;
        uint256[3] memory targets = [uint256(5_000e18), 200_000e18, 2_000_000e18];
        for (uint256 i; i < targets.length; ++i) {
            uint256 target = targets[i];
            uint256 b = (target / n) * 800 / 10_000;      // the deploy's formula
            uint256 sum;
            for (uint256 k; k < n; ++k) sum += (k * k * 1e18) / (k + KNEE);
            uint256 sp = ((target - n * b) * 1e18) / sum;

            MintCurvePolicy c = new MintCurvePolicy(b, sp, KNEE, n);
            assertApproxEqRel(c.totalToMintOut(), target, 0.01e18, "target must be hit");
            uint256 span = c.priceAt(n - 1, 0, 0) / c.priceAt(0, 0, 0);
            assertGe(span, 20, "shape must survive rescaling");
            assertLe(span, 32, "shape must survive rescaling");
        }
    }

    /// @notice A FLAT ladder is what the invariant actually rules out. Asserted so
    ///         the test above cannot pass vacuously.
    function test_F13_AFlatLadderWouldDiluteTheFloor() public pure {
        uint256 entitled;
        uint256 prevFloor;
        bool everDiluted;
        for (uint256 n; n < 50; ++n) {
            uint256 cost = 50e18;                     // flat
            uint256 floorAfter = (entitled + cost) / (n + 1);
            if (n > 0 && floorAfter <= prevFloor) everDiluted = true;
            entitled += cost;
            prevFloor = floorAfter;
        }
        assertTrue(everDiluted, "a flat ladder must fail the property the curve passes");
    }
}
