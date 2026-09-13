// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

contract K2Votes is IVotes721 {
    mapping(address => uint256) public now_;
    mapping(uint256 => mapping(address => uint256)) public past;
    uint256 public supply;

    function set(address a, uint256 v) external { now_[a] = v; }
    function setPast(uint256 blk, address a, uint256 v) external { past[blk][a] = v; }
    function setSupply(uint256 v) external { supply = v; }
    function getVotes(address a) external view returns (uint256) { return now_[a]; }
    function getPastVotes(address a, uint256 blk) external view returns (uint256) { return past[blk][a]; }
    function getPastTotalSupply(uint256) external view returns (uint256) { return supply; }
}

contract K2Registry {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * K2a — a PARTIAL treasury envelope can be spent to zero by a permissionless
 *        slice taken out of a SECONDARY leg, nullifying the mandate the guild
 *        voted for and locking governance out for COOLDOWN.
 *
 * TreasuryGovernor.allowance() meters a MIGRATION mandate (maxTotalBps >= 10_000)
 * against `movedPrimaryBps`, so a stranger rotating a side leg cannot eat it.
 * A PARTIAL mandate (maxTotalBps < 10_000) is deliberately left on the SHARED
 * `movedBps` counter — TreasuryGovernor.sol:775-778 — so the identical attack
 * still lands on every partial envelope.
 *
 * The registry-side caller is RedemptionExt.rotateSliceFrom, which is
 * permissionless and books `consume(sliceBps, fromLeg == 0)`
 * (RedemptionExt.sol:514) — `false` for any leg the caller names.
 *
 * All conditional logic is in helpers; the top-level tests are straight-line
 * assertions.
 */
contract K2a_PartialEnvelopeStarve is Test {
    K2Votes votes;
    mapping(address => bool) public allowedQuote;
    TreasuryGovernor gov;

    address constant USDG = address(0x115D);
    address constant ALICE = address(0xA11CE);
    address constant GUARDIAN = address(0x6A2D);
    address constant REGISTRY_CALLER = address(0xEE9);

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.roll(1000);
        votes = new K2Votes();
        allowedQuote[USDG] = true;
        votes.setSupply(1000);
        // Mainnet timing: 3d vote, 30d lifetime, 7d cooldown, 3d exec window.
        gov = new TreasuryGovernor(votes, address(this), GUARDIAN, 0, 0, 0, 0, false);
        votes.set(ALICE, 200);
    }

    /// @dev Install an envelope of `capBps` through a real, quorum-passing vote.
    function _installEnvelope(uint16 capBps) internal returns (uint256 id) {
        votes.setPast(vm.getBlockNumber() - 1, ALICE, 200); // 20% of 1000 supply, quorum is 10%
        vm.prank(ALICE);
        id = gov.propose(USDG, capBps);
        vm.prank(ALICE);
        gov.vote(id, true);
        _warpBy(3 days + 1);
        gov.execute(id);
    }

    /// @dev viaIR sinks `block.timestamp` reads past `vm.warp` in this profile,
    ///      so time is always read through the cheatcode, never the opcode.
    function _warpBy(uint256 d) internal {
        vm.warp(vm.getBlockTimestamp() + d);
    }

    function _remaining() internal view returns (uint16 r) {
        (, r) = gov.allowance();
    }

    function _proposeReverts() internal returns (bool reverted) {
        votes.setPast(vm.getBlockNumber() - 1, ALICE, 200);
        vm.prank(ALICE);
        try gov.propose(USDG, 2500) returns (uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
    }

    // ---------------------------------------------------------------
    // POSITIVE CONTROL: a MIGRATION mandate survives the same attack.
    // ---------------------------------------------------------------
    function test_K2a_control_migrationEnvelopeSurvivesSecondaryDrain() public {
        _installEnvelope(10_000);
        uint16 before_ = _remaining();

        // Four permissionless max-size slices out of a secondary leg.
        for (uint256 i; i < 4; ++i) {
            _consumeSecondary(2500);
        }

        uint16 after_ = _remaining();
        (, , , , bool active, ) = gov.envelope();

        assertEq(before_, 10_000, "migration envelope should open at full budget");
        assertEq(after_, 10_000, "migration budget must be untouched by secondary slices");
        assertTrue(active, "migration envelope must stay live");
    }

    // ---------------------------------------------------------------
    // REGRESSION (was the T2a attack): a PARTIAL mandate now survives a
    // secondary slice exactly the way a migration mandate does.
    // ---------------------------------------------------------------
    function test_K2a_partialEnvelopeNulledBySingleSecondarySlice() public {
        _installEnvelope(2500); // guild voted "move at most 25% into USDG"
        uint16 before_ = _remaining();

        // One permissionless rotateSliceFrom(fromLeg=1, sliceBps=2500, ...) —
        // MAX_SLICE_BPS is exactly 2500, so ONE call was enough to null it.
        _consumeSecondary(2500);

        uint16 after_ = _remaining();
        (, , , , bool active, ) = gov.envelope();
        bool migrationDone = gov.migrationMandateSpent();

        assertEq(before_, 2500, "envelope opens at the voted budget");
        assertEq(after_, 2500, "FIXED: the voted budget is untouched by a secondary slice");
        assertTrue(active, "FIXED: the envelope stays live; the primary never moved");
        assertFalse(migrationDone, "no migration happened; a partial mandate never migrates");

        // And the mandate can still do the thing the guild voted for: spend its
        // whole budget out of the PRIMARY position.
        gov.consume(2500, true);
        (, , , , bool activeAfterPrimary, ) = gov.envelope();
        assertEq(_remaining(), 0, "FIXED: the primary slice is what spends the budget");
        assertFalse(activeAfterPrimary, "FIXED: and what retires the envelope");
    }

    // The 7-day COOLDOWN lockout the attack bought no longer exists: there is
    // nothing for a stranger to spend, so there is nothing to lock out.
    function test_K2a_lockoutLastsFullCooldown() public {
        _installEnvelope(2500);
        _consumeSecondary(2500);

        uint256 tBefore = vm.getBlockTimestamp();
        _warpBy(7 days + 1);
        bool warpTookEffect = vm.getBlockTimestamp() == tBefore + 7 days + 1;

        assertTrue(warpTookEffect, "the 7-day warp actually moved the clock");
        assertEq(_remaining(), 2500, "FIXED: a full cooldown later the budget is still the guild's");
        // A second secondary slice is refused outright: leg-to-leg rebalancing
        // is still capped by the voted total, it just cannot spend the primary's.
        vm.expectRevert();
        gov.consume(1, false);
        // The primary spend the guild voted for still goes through.
        gov.consume(2500, true);
        assertEq(_remaining(), 0, "FIXED: the mandate executes against the primary after the cooldown");
    }

    /// @dev The registry is `address(this)` here, standing in for the delegatecall
    ///      frame RedemptionExt.rotateSliceFrom runs in. `fromPrimary = false` is
    ///      exactly what that function passes for any `fromLeg != 0`.
    function _consumeSecondary(uint16 bps) internal {
        gov.consume(bps, false);
    }
}
