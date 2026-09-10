// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-10 — SPAM ERASES A VOTED MANDATE FROM THE LEADER SCAN  (Medium)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `CauldronGovernor._recomputeLeader` is bounded to the newest
 *  {MAX_LEADER_SCAN} = 64 proposals (:370, `first = n - MAX_LEADER_SCAN + 1`).
 *  The bound is deliberate and correct — it is what keeps rebirth gas O(1) in the
 *  proposal count, and Z03_GovernorSpamRelaunchDoS asserts exactly that.
 *
 *  What Z03 asserts is that the scan stays CHEAP. It never asserts that the scan
 *  still FINDS anything. The window selects on proposal id, not on whether anyone
 *  voted, so a settled mandate the guild has already voted for can be pushed out
 *  of it by proposals authored afterwards — and `propose()` is permissionless for
 *  the holder of one MiFren, with no cooldown, no deposit and no per-address cap.
 *
 *  The cached-leader fast path in {_bestUnconsumed} hides this for the CURRENT
 *  leader. It does not protect the mandate queued behind it, because
 *  {markConsumed} rebuilds the cache from the scan the moment the leader is
 *  consumed — which is precisely what a normal rebirth does.
 *
 *  MEASURED: two voted mandates queued, then 64 spam proposals costing
 *  15,596,982 gas in total — one block, cents on an L2. The instant a normal
 *  rebirth consumed the first mandate, the second became unreachable:
 *  `hasProposals()` returned false, so `CauldronRegistry.relaunch()` reverted
 *  `NoProposal()` (:734) and the machine could not be reborn until the guild
 *  authored a replacement and waited out the full 3-day {VOTING_PERIOD} again.
 *  Repeatable at every generation boundary, indefinitely.
 *
 *  No value is extracted, and the revert is on the SAFE side of `markConsumed`,
 *  so this is a griefing vector rather than a permanent brick — but the protocol
 *  is frozen while it holds: the pool is dead, and holders cannot migrate.
 *
 *  FIXED by carrying the runner-up forward explicitly instead of rescanning on
 *  consumption. Spam cannot occupy either slot, because both require votes.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B10_ScanWindowErasure is Test {
    CauldronGovernor internal gov;

    function setUp() public {
        gov = new CauldronGovernor(address(new VS10()));
        gov.setRegistry(address(this)); // this test stands in for the registry
    }

    function _propose() internal returns (uint256 id) {
        id = gov.propose(
            "B", "X", MetadataMode.BaseURI, "ipfs://b/", address(0), "w", "s", 1000, 0, address(0)
        );
    }

    function _settle() internal {
        // `via_ir` CSEs repeated TIMESTAMP reads — use the cheatcode getter.
        vm.warp(vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1);
    }

    /// @notice THE FINDING. The guild queues two brews and votes both. A normal
    ///         rebirth consumes the first. The second must survive 64 proposals
    ///         authored in between.
    function test_INVARIANT_B10_QueuedMandateSurvivesSpam() public {
        uint256 h1 = _propose();
        uint256 h2 = _propose();
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(h2); // 1 vote -> leader
        gov.vote(h1); // ties at 1 -> tie keeps the earlier leader, h1 is runner-up
        _settle();

        uint256 g0 = gasleft();
        for (uint256 i; i < 64; ++i) _propose();
        emit log_named_uint("attacker spam gas (64 proposals)", g0 - gasleft());

        (uint256 winId,) = gov.winner();
        gov.markConsumed(winId);

        assertTrue(gov.hasProposals(), "the guild's other voted mandate must survive the spam");
        (uint256 next,) = gov.winner();
        assertEq(next, h1, "and it must be the one they actually voted for");
    }

    /// @notice The promotion must not resurrect a CONSUMED proposal: consuming
    ///         both mandates in turn has to leave the machine with nothing, not
    ///         with a stale pointer to an already-launched brew.
    function test_FIXED_B10_PromotionNeverResurrectsAConsumedProposal() public {
        uint256 h1 = _propose();
        uint256 h2 = _propose();
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(h2);
        gov.vote(h1);
        _settle();

        gov.markConsumed(h2);
        gov.markConsumed(h1);

        assertFalse(gov.hasProposals(), "both mandates spent: nothing left to launch");
    }

    /// @notice The leader gaining further votes must not become its own runner-up
    ///         — that would let one proposal be launched twice in a row.
    function test_FIXED_B10_LeaderCannotBecomeItsOwnRunnerUp() public {
        uint256 h1 = _propose();
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(h1);
        vm.prank(address(0xB0B));
        gov.vote(h1); // same proposal, more votes
        _settle();

        gov.markConsumed(h1);
        assertFalse(gov.hasProposals(), "a consumed leader cannot be promoted back over itself");
    }

    /// @notice Consuming the RUNNER-UP out of band must not leave a consumed id
    ///         sitting in the promotable slot.
    function test_FIXED_B10_ConsumingTheRunnerUpClearsTheSlot() public {
        uint256 h1 = _propose();
        uint256 h2 = _propose();
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(h2); // leader
        gov.vote(h1); // runner-up
        _settle();

        gov.markConsumed(h1); // consume the runner-up first
        gov.markConsumed(h2); // now consume the leader

        assertFalse(gov.hasProposals(), "no consumed proposal may be promoted");
    }

    /// @notice Governance still works normally: more votes wins, and the displaced
    ///         leader becomes the runner-up rather than being lost.
    function test_FIXED_B10_MoreVotesStillWins() public {
        uint256 h1 = _propose();
        uint256 h2 = _propose();
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(h1);                       // h1 = 1 vote, leader
        vm.prank(address(0xB0B)); gov.vote(h2);
        vm.prank(address(0xC0C)); gov.vote(h2); // h2 = 2 votes, takes the lead
        _settle();

        (uint256 winId,) = gov.winner();
        assertEq(winId, h2, "the proposal with more votes wins");

        gov.markConsumed(h2);
        (uint256 next,) = gov.winner();
        assertEq(next, h1, "and the displaced leader is still queued behind it");
    }
}

/// @dev Everyone holds one vote, so `propose`/`vote` reach the logic under test.
contract VS10 {
    function getVotes(address) external pure returns (uint256) { return 1; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1; }
}
