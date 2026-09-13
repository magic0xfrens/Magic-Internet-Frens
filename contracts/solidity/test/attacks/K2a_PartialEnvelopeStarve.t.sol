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
    // ATTACK: a PARTIAL mandate is destroyed by ONE secondary slice.
    // ---------------------------------------------------------------
    function test_K2a_partialEnvelopeNulledBySingleSecondarySlice() public {
        _installEnvelope(2500); // guild voted "move at most 25% into USDG"
        uint16 before_ = _remaining();

        // One permissionless rotateSliceFrom(fromLeg=1, sliceBps=2500, ...) —
        // MAX_SLICE_BPS is exactly 2500, so ONE call is enough.
        _consumeSecondary(2500);

        uint16 after_ = _remaining();
        (, , , , bool active, ) = gov.envelope();
        bool migrationDone = gov.migrationMandateSpent();
        bool cannotRepropose = _proposeReverts();

        assertEq(before_, 2500, "envelope opens at the voted budget");
        assertEq(after_, 0, "ATTACK: the whole voted budget is gone");
        assertFalse(active, "ATTACK: envelope deactivated without the primary moving");
        assertFalse(migrationDone, "no migration happened; the primary pair never moved");
        assertTrue(cannotRepropose, "ATTACK: COOLDOWN locks the guild out of re-proposing");
    }

    // The cooldown is 7 days: quantify the lockout.
    function test_K2a_lockoutLastsFullCooldown() public {
        _installEnvelope(2500);
        _consumeSecondary(2500);

        bool blockedAtSixDays = _proposeReverts();
        uint256 tBefore = vm.getBlockTimestamp();
        _warpBy(7 days + 1);
        bool warpTookEffect = vm.getBlockTimestamp() == tBefore + 7 days + 1;
        bool blockedAfterCooldown = _proposeReverts();

        assertTrue(warpTookEffect, "the 7-day warp actually moved the clock");

        assertTrue(blockedAtSixDays, "still inside cooldown");
        assertFalse(blockedAfterCooldown, "cooldown eventually clears: the grief is repeatable, not permanent");
    }

    /// @dev The registry is `address(this)` here, standing in for the delegatecall
    ///      frame RedemptionExt.rotateSliceFrom runs in. `fromPrimary = false` is
    ///      exactly what that function passes for any `fromLeg != 0`.
    function _consumeSecondary(uint16 bps) internal {
        gov.consume(bps, false);
    }
}
