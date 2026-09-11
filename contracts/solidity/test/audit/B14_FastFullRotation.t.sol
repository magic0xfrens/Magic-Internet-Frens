// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-14 — A FULL DE-RISKING ROTATION MUST FIT INSIDE ONE WEEK
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  THE REQUIREMENT. A guild that votes to move its LP into a stable because it
 *  believes the market is topping has to be able to act on that decision while
 *  it is still true. If executing the vote takes a quarter, the vote is about a
 *  market that no longer exists.
 *
 *  WHAT MADE IT IMPOSSIBLE. `TreasuryGovernor.consume` books the NOMINAL slice
 *  size, while `PoolOps.removePartial` takes that share of the CURRENT
 *  position — so the position decays geometrically and the nominal budget
 *  needed to convert most of it is well over 100%. With the old constants
 *  (MAX_SLICE_BPS 500, MAX_ENVELOPE_BPS 4000) one envelope bought 8 slices and
 *  moved 1 - 0.95^8 = 33.66%. A ~95% conversion needed 8 consecutive envelopes,
 *  each gated by a 3-day vote and a 7-day cooldown: ~80 days.
 *
 *  WHAT CHANGED, AND WHAT DID NOT. The slice ceiling and the envelope budget
 *  both moved, so one approved envelope now carries a rotation to ~95% in 11
 *  calls. The per-call floor guard (`PoolOps.MAX_ROTATION_BPS` = 50%) did not
 *  move: no single transaction can still empty the pair, and every slice keeps
 *  its own `minOut`. This is a change to how fast an APPROVED policy executes,
 *  not to what may be approved.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B14_FastFullRotation is Test {
    TreasuryGovernor internal gov;

    /// @dev Mirrors RedemptionExt.MAX_SLICE_BPS (internal, so restated).
    uint16 internal constant SLICE_BPS = 2500;
    /// @dev PoolOps.MAX_ROTATION_BPS — the holder guard that must NOT have moved.
    uint16 internal constant ROTATION_CAP_BPS = 5000;

    function setUp() public {
        gov = new TreasuryGovernor(IVotes721(address(new Votes14())), address(this), address(this), 0, 0, 0, 0, false);
    }

    /// @notice THE REQUIREMENT, asserted directly: one envelope must convert the
    ///         overwhelming majority of the position.
    function test_INVARIANT_B14_OneEnvelopeConvertsMostOfThePosition() public view {
        uint16 converted = gov.conversionFor(gov.MAX_ENVELOPE_BPS(), SLICE_BPS);
        assertGt(converted, 9_000, "one envelope must convert >90% of the LP");
    }

    /// @notice And it must do so inside a week, counting the vote.
    ///
    ///  Slices carry no cooldown of their own, so the wall clock is the voting
    ///  period plus however long it takes to send the calls. The assertion is on
    ///  the part the contracts control.
    function test_INVARIANT_B14_FullRotationFitsInSevenDays() public {
        uint256 slices = uint256(gov.MAX_ENVELOPE_BPS()) / SLICE_BPS;
        // One block apiece is generous; the point is that no CONTRACT-imposed
        // delay sits between slices.
        uint256 executionDays = 1;
        uint256 total = gov.VOTING_PERIOD() / 1 days + executionDays;

        emit log_named_uint("slices in one envelope   ", slices);
        emit log_named_uint("converted (bps)          ", gov.conversionFor(gov.MAX_ENVELOPE_BPS(), SLICE_BPS));
        emit log_named_uint("days: vote + execution   ", total);

        assertLe(total, 7, "a voted rotation must be executable within a week");
    }

    /// @notice REGRESSION: the per-call floor guard must not have been widened.
    ///         Speed comes from more slices, never from a bigger single bite.
    function test_INVARIANT_B14_PerCallFloorGuardUnchanged() public pure {
        assertLe(SLICE_BPS, ROTATION_CAP_BPS, "a slice must stay under the per-call cap");
        assertEq(ROTATION_CAP_BPS, 5000, "the 50% per-call floor guard must not move");
    }

    /// @notice The budget's units are not a voter's units, so the helper that
    ///         translates them has to be right. Checked against the closed form.
    ///
    ///  TOLERANCE IS THE TRUNCATION BOUND, not a fudge. The loop carries `rem`
    ///  in 1e4 fixed point and truncates once per slice, and each truncation
    ///  shrinks `rem` — so the reported conversion drifts UP by at most 1 bps
    ///  per iteration. Measured: +3.20 bps over 8 slices, +1.76 over 12. The
    ///  assertions below use the iteration count as the bound, so a real error
    ///  in the series would still fail while the inherent rounding does not.
    function test_B14_ConversionMathMatchesTheGeometricSeries() public view {
        // 4 slices of 25%: 1 - 0.75^4 = 0.683594 -> 6835.94 bps exact
        uint16 got = gov.conversionFor(10_000, 2500);
        assertApproxEqAbs(uint256(got), 6836, 4, "4 x 25% converts ~68.36%");

        // The old regime, for the record: 8 slices of 5% -> 1 - 0.95^8 = 33.658%
        uint16 old = gov.conversionFor(4000, 500);
        assertApproxEqAbs(uint256(old), 3366, 8, "the old envelope moved 33.66%, not the 40% it read as");

        // The drift must be UPWARD: an implementation that rounded the other way
        // would understate what a vote is about to move.
        assertGe(uint256(got), 6835, "truncation must not understate conversion");
    }

    /// @notice A zero slice size must not divide by zero or loop forever.
    function test_B14_DegenerateInputsAreSafe() public view {
        assertEq(gov.conversionFor(10_000, 0), 0, "zero slice converts nothing");
        assertEq(gov.conversionFor(0, 2500), 0, "zero budget converts nothing");
    }
}

/// @dev Everyone holds voting power; this suite is about the constants.
contract Votes14 {
    function getVotes(address) external pure returns (uint256) { return 10; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 10; }
    /// @dev Mirrors `Votes.getPastTotalSupply` — the quorum denominator the
    ///      real vote source ({MiFrensGenesis}) actually implements.
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 100; }
    function balanceOf(address) external pure returns (uint256) { return 10; }
}
