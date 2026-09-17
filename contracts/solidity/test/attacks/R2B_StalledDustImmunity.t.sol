// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/// @dev Minimal ERC721Votes surface the governor actually calls. Real contract
///      under test is {TreasuryGovernor}; this only supplies voting weight.
contract R2Votes {
    mapping(address => uint256) public votesOf;
    uint256 public total;

    function set(address who, uint256 v) external {
        total = total - votesOf[who] + v;
        votesOf[who] = v;
    }

    function getVotes(address a) external view returns (uint256) { return votesOf[a]; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return votesOf[a]; }
    function getPastTotalSupply(uint256) external view returns (uint256) { return total; }
}

/// @dev Registry stand-in: the governor only ever asks `allowedQuote`.
contract R2Registry {
    mapping(address => bool) public ok;
    function allow(address q) external { ok[q] = true; }
    function allowedQuote(address q) external view returns (bool) { return ok[q]; }
}

/**
 * @notice R2B — ONE DUST SLICE OUT OF A LEG NOBODY VOTED ABOUT PERMANENTLY
 *         DISARMS THE `stalled()` ESCAPE HATCH.
 *
 *  `TreasuryGovernor.stalled()` (:926-933) requires BOTH `movedBps == 0` and
 *  `movedPrimaryBps == 0`. `consume(bps, fromPrimary=false)` — the booking a
 *  secondary-leg slice makes, which by this contract's own design "cannot be
 *  what declares the migration done" and "cannot spend the budget the guild
 *  voted for the migration" (:946-958, :821-823) — nevertheless sets
 *  `movedBps != 0`.
 *
 *  So a stranger's 1-bps rebalance of a side pool re-installs the 30-day
 *  governance wedge that `696899b` was written to remove.
 */
contract R2B_StalledDustImmunity is Test {
    R2Votes internal votes;
    R2Registry internal reg;
    TreasuryGovernor internal gov;

    address internal guild = address(0x6111D);
    address internal attacker = address(0xBAD);
    address internal USDC = address(0xC0FFEE);
    address internal DAI = address(0xDEAD01);

    uint64 internal constant LIFETIME = 30 days;
    uint64 internal constant COOLDOWN = 7 days;

    function setUp() public {
        votes = new R2Votes();
        reg = new R2Registry();
        reg.allow(USDC);
        reg.allow(DAI);
        // mainnet-shaped timing, testnet=false so the real floors apply
        gov = new TreasuryGovernor(
            IVotes721(address(votes)), address(reg), address(0xFEED),
            3 days, LIFETIME, COOLDOWN, 3 days, false
        );
        votes.set(guild, 1000);
        votes.set(attacker, 10);
        vm.warp(1_000_000);
        vm.roll(1_000);
    }

    // ── helpers (all conditionals live here; the test bodies only assert) ────

    /// @dev Install a live envelope toward `quote`, returning the timestamp it
    ///      was installed at.
    function _installEnvelope(address quote) internal returns (uint64 at) {
        vm.prank(guild);
        uint256 id = gov.propose(quote, 10_000);
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(guild);
        gov.vote(id, true);
        vm.warp(vm.getBlockTimestamp() + 3 days + 1);
        gov.execute(id);
        at = gov.lastEnvelopeAt();
    }

    /// @dev Try to open a fresh proposal; return true when it lands.
    function _canPropose(address quote) internal returns (bool) {
        uint256 snap = vm.snapshotState();
        vm.prank(guild);
        try gov.propose(quote, 10_000) returns (uint256) {
            vm.revertToState(snap);
            return true;
        } catch {
            vm.revertToState(snap);
            return false;
        }
    }

    // ── 1. POSITIVE LIVENESS: a mandate nobody can execute stops blocking ────

    function test_R2B_positive_zeroProgressEnvelopeStopsBlockingAtCooldown() public {
        uint64 at = _installEnvelope(USDC);
        assertTrue(gov.stalled() == false, "fresh envelope must not read stalled");
        assertFalse(_canPropose(DAI), "cooldown must block immediately after install");

        // one second before the boundary
        vm.warp(uint256(at) + COOLDOWN - 1);
        assertEq(vm.getBlockTimestamp(), uint256(at) + COOLDOWN - 1, "warp #1 landed");
        bool stalledBefore = gov.stalled();
        bool proposeBefore = _canPropose(DAI);

        // exactly at the boundary
        vm.warp(uint256(at) + COOLDOWN);
        assertEq(vm.getBlockTimestamp(), uint256(at) + COOLDOWN, "warp #2 landed");
        bool stalledAt = gov.stalled();
        bool proposeAt = _canPropose(DAI);

        assertFalse(stalledBefore, "not stalled one second early");
        assertFalse(proposeBefore, "and propose is blocked one second early");
        assertTrue(stalledAt, "stalled exactly at lastEnvelopeAt + COOLDOWN");
        assertTrue(proposeAt, "and the guild can file the correction");
    }

    // ── 2. THE ATTACK: a 1-bps SECONDARY slice kills the escape hatch ────────

    function test_R2B_attack_oneDustSecondarySliceReinstatesTheWedge() public {
        uint64 at = _installEnvelope(USDC);

        // The attacker's slice comes out of a leg the mandate is NOT about.
        // This is exactly what RedemptionExt.sol:548 books for `fromLeg` != the
        // position holding the current denomination.
        vm.prank(address(reg));
        gov.consume(1, false);

        (, uint16 leftAfter) = gov.allowance();
        bool mandateSpent = gov.migrationMandateSpent();

        // Past the cooldown: the honest escape would now be open.
        vm.warp(uint256(at) + COOLDOWN + 1);
        assertEq(vm.getBlockTimestamp(), uint256(at) + COOLDOWN + 1, "warp #1 landed");
        bool stalledAtCooldown = gov.stalled();
        bool proposeAtCooldown = _canPropose(DAI);

        // ... and stays shut for the whole envelope lifetime.
        vm.warp(uint256(at) + LIFETIME - 1);
        assertEq(vm.getBlockTimestamp(), uint256(at) + LIFETIME - 1, "warp #2 landed");
        bool stalledLate = gov.stalled();
        bool proposeLate = _canPropose(DAI);

        // Only expiry reopens it.
        vm.warp(uint256(at) + LIFETIME + 1);
        assertEq(vm.getBlockTimestamp(), uint256(at) + LIFETIME + 1, "warp #3 landed");
        bool proposeAfterExpiry = _canPropose(DAI);

        console2.log("remaining bps after the dust slice", leftAfter);
        console2.log("migrationMandateSpent", mandateSpent);

        // The dust slice took NOTHING out of the voted position:
        assertEq(leftAfter, 10_000, "primary budget untouched - the slice was not the migration");
        assertFalse(mandateSpent, "and it did not advance the migration one bit");

        // Yet it disarmed the escape hatch for the envelope's whole life:
        assertFalse(stalledAtCooldown, "1 bps of a side pool makes stalled() false at cooldown");
        assertFalse(proposeAtCooldown, "so the guild cannot file the correction");
        assertFalse(stalledLate, "still false 30 days in");
        assertFalse(proposeLate, "governance wedged for ENVELOPE_LIFETIME");
        assertTrue(proposeAfterExpiry, "only expiry reopens it");
    }

    // ── 3. A ZERO-BPS BOOKING DOES NOT IMMUNISE (boundary check) ────────────

    function test_R2B_zeroBpsBookingDoesNotImmunise() public {
        uint64 at = _installEnvelope(USDC);
        vm.prank(address(reg));
        gov.consume(0, false);
        vm.warp(uint256(at) + COOLDOWN);
        assertEq(vm.getBlockTimestamp(), uint256(at) + COOLDOWN, "warp landed");
        assertTrue(gov.stalled(), "movedBps still 0 after a 0-bps booking");
        assertTrue(_canPropose(DAI), "escape hatch still open");
    }
}
