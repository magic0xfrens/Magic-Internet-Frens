// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

contract K2bVotes is IVotes721 {
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

/**
 * K2b — a PASSED treasury mandate is erased AFTER its vote has closed by
 *        proposals whose own voting is still OPEN.
 *
 * TreasuryGovernor._benchRecord (TreasuryGovernor.sol:525-541) ranks bench
 * entries purely on `forVotes` and only excludes `_dead` entries. A proposal
 * whose voting window is still OPEN is neither dead nor executable, yet it
 * counts at full weight and can evict a proposal that has already PASSED and is
 * inside its EXECUTION_WINDOW. {winner} (:707-712) then finds nothing executable
 * on the bench, {execute} gates on `id != winner()` (:566), and the guild's
 * mandate goes stale three days later with no way to run it.
 *
 * The attacker never casts an AGAINST vote and never has to act while the vote
 * is open: they act only after the guild believes the mandate is secured. One
 * wallet's voting power is reused across all eight filings, because `hasVoted`
 * is per-proposal.
 */
contract K2b_MandateErasedAfterVoteCloses is Test {
    K2bVotes votes;
    mapping(address => bool) public allowedQuote;
    TreasuryGovernor gov;

    address constant USDG = address(0x115D);
    address constant XNVDA = address(0x8B0A);
    address constant GUILD = address(0x6111D);
    address constant ATTACKER = address(0xBAD);
    address constant GUARDIAN = address(0x6A2D);

    uint256 constant SUPPLY = 1000;   // quorum = 10% = 100
    uint256 constant GUILD_POWER = 300;
    uint256 constant ATTACK_POWER = 301; // GUILD_POWER + 1

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.roll(1000);
        votes = new K2bVotes();
        allowedQuote[USDG] = true;
        allowedQuote[XNVDA] = true;
        votes.setSupply(SUPPLY);
        gov = new TreasuryGovernor(votes, address(this), GUARDIAN, 0, 0, 0, 0, false);
        votes.set(GUILD, GUILD_POWER);
        votes.set(ATTACKER, ATTACK_POWER);
    }

    function _fileAndVote(address who, uint256 power, address quote, uint16 cap)
        internal
        returns (uint256 id)
    {
        votes.setPast(vm.getBlockNumber() - 1, who, power);
        vm.prank(who);
        id = gov.propose(quote, cap);
        vm.prank(who);
        gov.vote(id, true);
    }

    /// @dev viaIR sinks `block.timestamp` reads past `vm.warp` in this profile,
    ///      so time is always read through the cheatcode, never the opcode.
    function _warpBy(uint256 d) internal returns (uint256 t) {
        t = vm.getBlockTimestamp() + d;
        vm.warp(t);
    }

    function _executeSucceeds(uint256 id) internal returns (bool ok) {
        try gov.execute(id) { ok = true; } catch { ok = false; }
    }

    // ---------------------------------------------------------------
    // POSITIVE: the honest path works end to end.
    // ---------------------------------------------------------------
    function test_K2b_positive_passedMandateExecutes() public {
        uint256 good = _fileAndVote(GUILD, GUILD_POWER, USDG, 10_000);
        (, , uint64 goodEnd, , , , , , ) = gov.proposals(good);
        uint256 t = _warpBy(3 days + 1);

        uint256 w = gov.winner();
        bool ok = _executeSucceeds(good);
        (address q, uint16 rem) = gov.allowance();

        assertGt(t, uint256(goodEnd), "the warp really cleared the voting window");
        assertEq(w, good, "the guild's proposal is the winner");
        assertTrue(ok, "a passed mandate executes");
        assertEq(q, USDG, "envelope points at the voted asset");
        assertEq(rem, 10_000, "full budget installed");
    }

    // ---------------------------------------------------------------
    // ATTACK: eight still-open filings erase it after the vote closed.
    // ---------------------------------------------------------------
    function test_K2b_openProposalsEvictAPassedMandate() public {
        uint256 good = _fileAndVote(GUILD, GUILD_POWER, USDG, 10_000);
        (, , uint64 goodEnd, , , , , , ) = gov.proposals(good);
        uint256 t1 = _warpBy(3 days + 1);

        // Sanity: right now the mandate is the winner and would execute.
        uint256 winnerBefore = gov.winner();
        bool passingBefore = gov.passing(good);

        // ATTACK, one transaction's worth of calls, entirely after the close.
        // BENCH_SLOTS is 8; the same 301 votes are reused on every filing.
        uint256[] memory junk = new uint256[](8);
        for (uint256 i; i < 8; ++i) {
            junk[i] = _fileAndVote(ATTACKER, ATTACK_POWER, XNVDA, 10_000);
        }

        uint256 winnerAfter = gov.winner();
        bool stillPassing = gov.passing(good);
        bool canExecute = _executeSucceeds(good);

        // ...and three days later the guild's mandate is permanently stale,
        // while the attacker's own envelope is now installable.
        (, , uint64 junkEnd, , , , , , ) = gov.proposals(junk[0]);
        vm.warp(uint256(junkEnd) + 1);
        bool secondWarpTookEffect = vm.getBlockTimestamp() == uint256(junkEnd) + 1;
        bool attackerCanExecute = _executeSucceeds(junk[0]);
        (address q, uint16 rem) = gov.allowance();

        assertGt(t1, uint256(goodEnd), "the guild's vote really did close before the attack");
        assertTrue(secondWarpTookEffect, "the second warp actually moved the clock");
        assertEq(winnerBefore, good, "before the attack the guild's mandate wins");
        assertTrue(passingBefore, "it passed quorum");
        assertTrue(stillPassing, "it STILL passes: the votes were never contested");
        assertEq(winnerAfter, good, "FIXED: eight open filings cannot unseat a settled, passed mandate");
        assertTrue(canExecute, "FIXED: the passed mandate still executes");
        assertFalse(attackerCanExecute, "FIXED: the attacker's envelope does not install over it");
        assertEq(q, USDG, "FIXED: the treasury points at the asset the guild voted for");
        assertEq(rem, 10_000, "FIXED: with the whole budget the guild voted");
    }

    // The attacker never voted AGAINST anything, so this is not ordinary
    // opposition: it lands entirely after the window in which the guild could
    // have answered it.
    function test_K2b_attackerCastNoAgainstVotes() public {
        uint256 good = _fileAndVote(GUILD, GUILD_POWER, USDG, 10_000);
        (, , uint64 goodEnd, , , , , , ) = gov.proposals(good);
        uint256 t = _warpBy(3 days + 1);
        for (uint256 i; i < 8; ++i) {
            _fileAndVote(ATTACKER, ATTACK_POWER, XNVDA, 10_000);
        }
        (, , , , uint256 forVotes, uint256 againstVotes, , , ) = gov.proposals(good);

        assertGt(t, uint256(goodEnd), "the guild's vote really did close");
        assertEq(forVotes, GUILD_POWER, "the mandate's FOR count is untouched");
        assertEq(againstVotes, 0, "no AGAINST vote was ever cast against it");
        assertEq(gov.winner(), good, "FIXED: and it is still the winner, so it can still be executed");
    }
}
