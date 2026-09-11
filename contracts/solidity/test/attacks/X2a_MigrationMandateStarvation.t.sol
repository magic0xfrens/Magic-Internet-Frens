// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/// @dev Minimal ERC721Votes stand-in. Every account holds 10 votes; total supply
///      is 100, so QUORUM_BPS (10%) needs exactly 10 FOR-votes.
contract X2aVotes {
    function getVotes(address) external pure returns (uint256) { return 10; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 10; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 100; }
}

/**
 * X2a — REGRESSION. A voted MIGRATION mandate could be spent to zero without ever
 *       migrating; now a full-position envelope refuses to pay for anything but
 *       the migration it was voted for.
 *
 * TreasuryGovernor.consume (TreasuryGovernor.sol:697) debits ONE budget:
 *      e.movedBps += bps;                          // every slice
 *      if (fromPrimary) e.movedPrimaryBps += bps;  // only primary slices
 *      if (e.movedBps >= e.maxTotalBps) e.active = false;
 * while migrationMandateSpent (TreasuryGovernor.sol:683) requires
 *      e.maxTotalBps >= 10_000 && e.movedPrimaryBps >= e.maxTotalBps
 * and RedemptionExt.rotateSliceFrom (RedemptionExt.sol:505) is the ONLY writer of
 * generationQuote for a live generation, gated on that flag.
 *
 * `fromPrimary` is `fromLeg == 0`, and `fromLeg` is an argument of the
 * PERMISSIONLESS RedemptionExt.rotateSliceFrom. So anyone could route the guild's
 * whole migration budget through a secondary leg: movedBps reaches maxTotalBps,
 * the envelope deactivates, and movedPrimaryBps never can.
 *
 * REACHABILITY (the verifier's narrowed precondition, asserted below): a secondary
 * leg in a DIFFERENT quote must already exist, because `_recordLeg` upserts by
 * quote (RedemptionExt.sol:676) and `fromQuote == toQuote` reverts BadConfig
 * (RedemptionExt.sol:358). So a generation's FIRST migration cannot be starved and
 * every migration after one is a candidate.
 *
 * FIX: TreasuryGovernor.consume refuses `fromPrimary == false` while the envelope is
 * a full-position migration mandate (`maxTotalBps >= BPS_ONE`). Partial envelopes —
 * every envelope that is not a migration — still fund leg-to-leg rebalancing.
 *
 * This test drives TreasuryGovernor directly as the registry (the only caller
 * `consume` accepts), which is exactly the call RedemptionExt.sol:437 makes.
 */
contract X2a_MigrationMandateStarvation is Test {
    TreasuryGovernor internal gov;
    X2aVotes internal votes;

    // TreasuryGovernor reads `IRegistryQuotes(registry).allowedQuote` — this
    // contract IS the registry, so the allowlist lives here.
    function allowedQuote(address) external pure returns (bool) { return true; }

    address internal constant USDG = address(0xDDDD);

    function setUp() public {
        votes = new X2aVotes();
        // zeros => mainnet defaults: 3d vote, 30d envelope, 7d cooldown, 3d window.
        gov = new TreasuryGovernor(IVotes721(address(votes)), address(this), address(this), 0, 0, 0, 0, false);
        vm.warp(100 days);
        vm.roll(1000);
    }

    /// @dev File + pass + install a FULL-POSITION migration envelope (10_000 bps).
    function _installFullMigrationEnvelope() internal returns (uint256 id) {
        id = gov.propose(USDG, 10_000);
        gov.vote(id, true);
        vm.warp(block.timestamp + 3 days + 1);
        gov.execute(id);
    }

    /// @dev Try to spend the envelope out of a SECONDARY leg (fromPrimary = false).
    ///      Returns false when the governor refuses.
    function _trySecondaryLegSlice(uint16 bps) internal returns (bool ok) {
        try gov.consume(bps, false) { ok = true; } catch { ok = false; }
    }

    /// @dev Spend the whole envelope out of the PRIMARY position — the honest path.
    function _spendFromPrimary() internal {
        for (uint256 i; i < 4; ++i) gov.consume(2500, true);
    }

    /// @dev Can the guild file a replacement right now?
    function _canReproposeNow() internal returns (bool) {
        try gov.propose(USDG, 10_000) returns (uint256) { return true; } catch { return false; }
    }

    /// @dev Is any further slice authorised under the envelope?
    function _remaining() internal view returns (uint16 left) {
        (, left) = gov.allowance();
    }

    // ── POSITIVE CONTROL: the property that is supposed to hold ──────────────

    function test_X2a_control_primarySlicesCompleteTheMigration() public {
        _installFullMigrationEnvelope();
        _spendFromPrimary();
        bool spent = gov.migrationMandateSpent();
        uint16 left = _remaining();
        assertTrue(spent, "a full mandate consumed out of the primary MUST declare the migration done");
        assertEq(left, 0, "and the envelope is exhausted");
    }

    // ── THE ATTACK ───────────────────────────────────────────────────────────

    function test_X2a_legSlicesCannotStarveTheMigrationMandate() public {
        _installFullMigrationEnvelope();

        // THE ATTACK: spend the guild's migration budget out of a secondary leg.
        bool first  = _trySecondaryLegSlice(2500);
        bool second = _trySecondaryLegSlice(2500);

        assertFalse(first,  "FIXED: a full migration mandate refuses a secondary-leg slice");
        assertFalse(second, "FIXED: and refuses every retry");

        // Nothing was taken out of the envelope, so the migration is still fundable.
        assertEq(_remaining(), 10_000, "the whole envelope survives the attempt");
        assertFalse(gov.migrationMandateSpent(), "and is not yet spent");

        // ...and the honest path still completes it, under the very same envelope.
        _spendFromPrimary();
        assertTrue(gov.migrationMandateSpent(), "the primary path still migrates the generation");
        assertEq(_remaining(), 0, "and exhausts the envelope");
        emit log_string("X2a: full mandate is exclusive to the primary position");
    }

    /// @dev The fix must not kill rebalancing. A PARTIAL envelope — anything a guild
    ///      votes that is not a whole-position migration — still pays for leg-to-leg
    ///      slices, which is what `fromLeg` exists for.
    function test_X2a_partialEnvelopeStillFundsLegRebalancing() public {
        uint256 id = gov.propose(USDG, 2_500);      // a quarter, not a migration
        gov.vote(id, true);
        vm.warp(block.timestamp + 3 days + 1);
        gov.execute(id);

        assertTrue(_trySecondaryLegSlice(1_000), "a partial envelope funds a secondary leg");
        assertEq(_remaining(), 1_500, "and is debited for it");
        assertFalse(gov.migrationMandateSpent(), "a partial envelope never declares a migration");
    }
}
