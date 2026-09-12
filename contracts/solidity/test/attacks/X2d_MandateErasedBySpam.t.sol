// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MetadataMode, BrewSpec} from "../../cauldron/ICauldron.sol";

/// @dev 1 NFT = 1 vote, with a per-address weight the test sets.
contract X2dVotes {
    mapping(address => uint256) public w;
    function set(address a, uint256 n) external { w[a] = n; }
    function getVotes(address a) external view returns (uint256) { return w[a] == 0 ? 1 : w[a]; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return w[a] == 0 ? 1 : w[a]; }
}

/**
 * X2d — REGRESSION. A settled, voted, unconsumed brew mandate WAS erased by 64
 *       later spam filings, so `relaunch()` reverted `NoProposals` and the eternal
 *       machine stalled until the guild re-voted (3 days), repeatably.
 *
 * CauldronGovernor._recomputeLeader (CauldronGovernor.sol:478-489) is a POSITIONAL
 * window over a list anyone holding ONE MiFren may grow without cooldown:
 *      uint256 first = n > MAX_LEADER_SCAN ? n - MAX_LEADER_SCAN + 1 : 1;
 *      for (uint256 i = first; i <= n; i++) { ... }
 * with MAX_LEADER_SCAN = 64 (CauldronGovernor.sol:474).
 *
 * The mitigation is a ONE-DEEP runner-up slot (CauldronGovernor.sol:178-179,
 * promoted at :412-416) — "spam can never reach it". It is one deep: a third
 * proposal overtaking the leader overwrites `_runnerId` with the DISPLACED leader
 * (CauldronGovernor.sol:356-359) and the previous runner-up is forgotten. Once two
 * consumptions drain the slot, `markConsumed` falls back to the positional scan
 * (CauldronGovernor.sol:419) and the forgotten mandate must be inside the newest 64.
 *
 * The sibling governor removed exactly this shape ("a window over a list anyone may
 * grow is a window anyone may flood ... The guild's mandate was erased by spam that
 * cost gas", TreasuryGovernor.sol:573-580) and replaced it with a TIME bound. A time
 * bound is not available here — a brew mandate is STOCKPILED against the next death,
 * which may be months away — so the scan stopped being over the proposal list at all.
 *
 * FIX: {CauldronGovernor._bench}, a fixed 8-slot leaderboard entered by VOTES rather
 * than by position. A proposal nobody voted for never enters it, so filings alone
 * cannot displace anything, and `_recomputeLeader` scans those 8 slots instead of a
 * window over `proposalCount` — still O(1) rebirth gas.
 */
contract X2d_MandateErasedBySpam is Test {
    CauldronGovernor internal gov;
    X2dVotes internal votes;

    address internal alice = address(0xA11CE);
    address internal bob   = address(0xB0B);
    address internal carol = address(0xCAC0);
    address internal mallory = address(0x4A110);

    function setUp() public {
        votes = new X2dVotes();
        gov = new CauldronGovernor(address(votes), 0);
        gov.setRegistry(address(this));   // this test IS the registry
        vm.warp(1_000_000);
        vm.roll(100);
    }

    function _file(address who, string memory nm) internal returns (uint256 id) {
        vm.prank(who);
        id = gov.propose(nm, "SYM", MetadataMode.BaseURI, "ipfs://x/", address(0), "", "", 0, 0, address(0));
        vm.roll(block.number + 1);        // snapshot must be in the past to vote
    }

    function _voteWith(address who, uint256 weight, uint256 id) internal {
        votes.set(who, weight);
        vm.prank(who);
        gov.vote(id);
    }

    /// @dev A(100) leads, B(90) is runner-up, then C(150) overtakes and the
    ///      runner slot is overwritten with the displaced leader A — B is dropped.
    function _buildForgottenMandate() internal returns (uint256 a, uint256 b, uint256 c) {
        a = _file(alice, "Alpha");
        _voteWith(alice, 100, a);
        b = _file(bob, "Beta");
        _voteWith(bob, 90, b);
        c = _file(carol, "Gamma");
        _voteWith(carol, 150, c);
        vm.warp(block.timestamp + 3 days + 1);   // every window closes
    }

    /// @dev Mallory floods `n` proposals with one MiFren and no cooldown.
    function _flood(uint256 n) internal returns (uint256 gasUsed) {
        votes.set(mallory, 1);
        uint256 g0 = gasleft();
        for (uint256 i; i < n; ++i) {
            vm.prank(mallory);
            gov.propose("s", "s", MetadataMode.BaseURI, "i", address(0), "", "", 0, 0, address(0));
        }
        gasUsed = g0 - gasleft();
    }

    /// @dev Drain the runner slot: consume C (promotes A), then consume A (falls
    ///      through to the positional scan at CauldronGovernor.sol:419).
    function _consumeTwice(uint256 c, uint256 a) internal {
        gov.markConsumed(c);
        gov.markConsumed(a);
    }

    /// @dev Does the governor still see the guild's surviving mandate?
    function _winnerId() internal view returns (uint256 id) {
        try gov.winner() returns (uint256 w, BrewSpec memory) { id = w; }
        catch { id = 0; }
    }

    // ── POSITIVE CONTROL: without spam, the forgotten mandate is recovered ────

    function test_X2d_control_scanRecoversTheForgottenMandate() public {
        (uint256 a, uint256 b, uint256 c) = _buildForgottenMandate();
        _consumeTwice(c, a);
        uint256 w = _winnerId();
        bool has = gov.hasProposals();
        assertEq(w, b, "the rescan finds B, the guild's surviving 90-vote mandate");
        assertTrue(has, "relaunch can proceed");
    }

    // ── THE ATTACK ───────────────────────────────────────────────────────────

    function test_X2d_spamCannotEraseTheVotedMandate() public {
        (uint256 a, uint256 b, uint256 c) = _buildForgottenMandate();

        uint256 floodGas = _flood(64);       // 64 junk filings, one MiFren, no cooldown
        _consumeTwice(c, a);

        uint256 w = _winnerId();
        bool has = gov.hasProposals();

        assertGt(b, 0, "B exists and was never consumed");
        assertEq(w, b, "FIXED: the guild's surviving 90-vote mandate is still the winner");
        assertTrue(has, "FIXED: relaunch() still has something to summon");
        emit log_named_uint("X2d flood gas for 64 filings", floodGas);
        emit log_named_uint("X2d surviving mandate id", b);
    }

    /// @dev And a flood an order of magnitude larger changes nothing, because the
    ///      bench is not a window over the proposal list.
    function test_X2d_biggerFloodStillCannotReachTheBench() public {
        (uint256 a, uint256 b, uint256 c) = _buildForgottenMandate();
        _flood(200);
        _consumeTwice(c, a);
        assertEq(_winnerId(), b, "200 junk filings still cannot displace a voted mandate");
        assertTrue(gov.hasProposals(), "relaunch stays available");
    }
}
