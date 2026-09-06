// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../cauldron/TreasuryGovernor.sol";

/// @dev MiFren voting power with a settable history, so a test can move votes
///      AFTER a snapshot and prove the snapshot is what counts.
contract MockVotes is IVotes721 {
    mapping(address => uint256) public now_;
    mapping(uint256 => mapping(address => uint256)) public past;
    uint256 public supply;

    function set(address a, uint256 v) external { now_[a] = v; }
    function setPast(uint256 blk, address a, uint256 v) external { past[blk][a] = v; }
    function setSupply(uint256 v) external { supply = v; }
    function getVotes(address a) external view returns (uint256) { return now_[a]; }
    function getPastVotes(address a, uint256 blk) external view returns (uint256) { return past[blk][a]; }
    function totalSupply() external view returns (uint256) { return supply; }
}

contract RegistryStub {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * @dev The treasury vote.
 *
 *  These tests are mostly about what a vote must NOT allow. The interesting
 *  failures in DAO governance are not "the maths is wrong" — they are "someone
 *  found a way to make the process not run at all", or "someone executed
 *  something the guild did not choose".
 */
contract TreasuryGovernorTest is Test {
    TreasuryGovernor gov;
    MockVotes votes;
    RegistryStub reg;

    address constant USDG = address(0x115D);
    address constant XNVDA = address(0x8B0A);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant SQUATTER = address(0x5A77);
    address constant GUARDIAN = address(0x6A2D);

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.roll(1000);
        votes = new MockVotes();
        reg = new RegistryStub();
        reg.set(USDG, true);
        reg.set(XNVDA, true);
        votes.setSupply(1000);
        gov = new TreasuryGovernor(votes, address(reg), GUARDIAN);

        // Everyone clears the proposal threshold.
        votes.set(ALICE, 100);
        votes.set(BOB, 100);
        votes.set(SQUATTER, 5);
    }

    function _propose(address who, address quote, uint16 bps) internal returns (uint256 id) {
        vm.prank(who);
        id = gov.propose(quote, bps);
    }

    function _voteWith(uint256 id, address who, uint256 weight, bool support) internal {
        votes.setPast(gov_snapshot(id), who, weight);
        vm.prank(who);
        gov.vote(id, support);
    }

    function gov_snapshot(uint256 id) internal view returns (uint256) {
        (,,, uint256 snap,,,,,) = gov.proposals(id);
        return snap;
    }

    // ── conflict resolution ─────────────────────────────────────────────────

    /// TWO GENUINE PROPOSALS FOR DIFFERENT ASSETS must resolve by vote, not by
    /// who filed first. This is the whole reason proposals run concurrently.
    function test_CompetingProposalsResolveByVote() public {
        uint256 a = _propose(ALICE, USDG, 3000);
        uint256 b = _propose(BOB, XNVDA, 2000);

        _voteWith(a, ALICE, 120, true);
        _voteWith(b, BOB, 300, true);

        vm.warp(block.timestamp + 3 days + 1);
        assertEq(gov.winner(), b, "the more-supported proposal wins");

        gov.execute(b);
        (address q,,,, bool active) = gov.envelope();
        assertEq(q, XNVDA, "the winner's asset is what gets installed");
        assertTrue(active);
    }

    /// THE ATTACK THE OLD DESIGN ALLOWED. One-proposal-at-a-time reads as a
    /// safety property and is actually a veto: anyone at the threshold could
    /// file junk forever and block the treasury for the price of gas.
    function test_SquatterCannotBlockGovernance() public {
        _propose(SQUATTER, USDG, 100); // junk, never voted for

        // A real proposal is filed anyway — no queue to wait behind.
        uint256 real = _propose(ALICE, XNVDA, 3000);
        _voteWith(real, ALICE, 200, true);

        vm.warp(block.timestamp + 3 days + 1);
        assertEq(gov.winner(), real, "junk loses; it does not block");
        gov.execute(real);
    }

    /// A passing proposal that is NOT the leader must not be installable — or
    /// several passing at once turns the vote into a race to execute.
    function test_LoserCannotExecuteEvenIfItPassed() public {
        uint256 a = _propose(ALICE, USDG, 3000);
        uint256 b = _propose(BOB, XNVDA, 2000);
        _voteWith(a, ALICE, 150, true);  // passes quorum
        _voteWith(b, BOB, 400, true);    // passes by more

        vm.warp(block.timestamp + 3 days + 1);
        vm.expectRevert(TreasuryGovernor.DidNotPass.selector);
        gov.execute(a);
    }

    // ── what a vote may not do ──────────────────────────────────────────────

    /// Buying MiFrens after reading a proposal must not buy influence over it.
    function test_VotingPowerIsSnapshotted() public {
        uint256 id = _propose(ALICE, USDG, 3000);
        // BOB acquires a huge stake AFTER the snapshot block.
        votes.set(BOB, 10_000);
        vm.roll(block.number + 10);

        vm.prank(BOB);
        vm.expectRevert(TreasuryGovernor.NoVotingPower.selector);
        gov.vote(id, true);
    }

    /// A handful of holders at 4am must not move the treasury.
    function test_QuorumIsRequired() public {
        uint256 id = _propose(ALICE, USDG, 3000);
        _voteWith(id, ALICE, 50, true); // 5% of 1000 supply, quorum is 10%

        vm.warp(block.timestamp + 3 days + 1);
        assertEq(gov.winner(), 0, "below quorum is not a winner");
        vm.expectRevert(TreasuryGovernor.DidNotPass.selector);
        gov.execute(id);
    }

    /// However the vote goes, no envelope may exceed the hard ceiling.
    function test_EnvelopeCeilingIsNotVotable() public {
        vm.prank(ALICE);
        vm.expectRevert(TreasuryGovernor.BadParam.selector);
        gov.propose(USDG, 4001); // MAX_ENVELOPE_BPS is 4000
    }

    /// A vote can only choose among assets the timelock already vetted. This is
    /// the guardrail that removes a category rather than limiting damage.
    function test_CannotProposeAnUnvettedAsset() public {
        vm.prank(ALICE);
        vm.expectRevert(TreasuryGovernor.QuoteNotAllowed.selector);
        gov.propose(address(0xDEAD), 1000);
    }

    function test_BelowThresholdCannotPropose() public {
        votes.set(address(0xFEE), 4); // threshold is 5
        vm.prank(address(0xFEE));
        vm.expectRevert(TreasuryGovernor.BelowProposalThreshold.selector);
        gov.propose(USDG, 1000);
    }

    function test_CannotVoteTwice() public {
        uint256 id = _propose(ALICE, USDG, 3000);
        _voteWith(id, ALICE, 200, true);
        vm.prank(ALICE);
        vm.expectRevert(TreasuryGovernor.AlreadyVoted.selector);
        gov.vote(id, true);
    }

    // ── time ────────────────────────────────────────────────────────────────

    /// A winner nobody executed must go stale rather than installing months
    /// later into a market nobody voted about.
    function test_StaleWinnerCannotBeExecuted() public {
        uint256 id = _propose(ALICE, USDG, 3000);
        _voteWith(id, ALICE, 200, true);

        vm.warp(block.timestamp + 3 days + 3 days + 2); // past the execution window
        assertEq(gov.winner(), 0, "a stale winner is no longer a winner");
        vm.expectRevert(TreasuryGovernor.DidNotPass.selector);
        gov.execute(id);
    }

    /// Only one rotation may be live, so a second cannot be installed on top.
    function test_OneEnvelopeAtATime() public {
        uint256 a = _propose(ALICE, USDG, 3000);
        _voteWith(a, ALICE, 200, true);
        vm.warp(block.timestamp + 3 days + 1);
        gov.execute(a);

        vm.prank(BOB);
        vm.expectRevert(TreasuryGovernor.ProposalActive.selector);
        gov.propose(XNVDA, 1000);
    }

    // ── emergency ───────────────────────────────────────────────────────────

    /// A malicious proposal can pass legitimately; the guardian is the answer,
    /// and it can only ever STOP a rotation.
    function test_GuardianCanCancelAPassedProposal() public {
        uint256 id = _propose(ALICE, USDG, 3000);
        _voteWith(id, ALICE, 200, true);
        vm.warp(block.timestamp + 3 days + 1);
        gov.execute(id);

        vm.prank(GUARDIAN);
        gov.cancel(id);
        (,,,, bool active) = gov.envelope();
        assertFalse(active, "the guardian stops a live rotation");

        (address q,) = gov.allowance();
        assertEq(q, address(0), "and nothing is executable after");
    }

    function test_StrangerCannotCancel() public {
        uint256 id = _propose(ALICE, USDG, 3000);
        vm.prank(address(0xBAD));
        vm.expectRevert(TreasuryGovernor.NotGuardian.selector);
        gov.cancel(id);
    }

    /// Only the registry may report movement, since it is the contract that
    /// actually moves the liquidity.
    function test_OnlyRegistryConsumesEnvelope() public {
        uint256 id = _propose(ALICE, USDG, 3000);
        _voteWith(id, ALICE, 200, true);
        vm.warp(block.timestamp + 3 days + 1);
        gov.execute(id);

        vm.prank(address(0xBAD));
        vm.expectRevert(TreasuryGovernor.NotGuardian.selector);
        gov.consume(100);

        vm.prank(address(reg));
        gov.consume(500);
        (, uint16 left) = gov.allowance();
        assertEq(left, 2500, "3000 - 500 remains");
    }

    /// An exhausted envelope stops authorising rotation.
    function test_ExhaustedEnvelopeAuthorisesNothing() public {
        uint256 id = _propose(ALICE, USDG, 1000);
        _voteWith(id, ALICE, 200, true);
        vm.warp(block.timestamp + 3 days + 1);
        gov.execute(id);

        vm.prank(address(reg));
        gov.consume(1000);
        (address q, uint16 left) = gov.allowance();
        assertEq(q, address(0), "spent envelope authorises nothing");
        assertEq(left, 0);
    }
}
