// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MetadataMode, BrewSpec} from "../../cauldron/ICauldron.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract K2cVotes is IVotes {
    mapping(address => uint256) public v;
    function set(address a, uint256 x) external { v[a] = x; }
    function getVotes(address a) external view returns (uint256) { return v[a]; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return v[a]; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function delegates(address) external pure returns (address) { return address(0); }
    function delegate(address) external {}
    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external {}
}

/**
 * K2c — a SETTLED, voted brew mandate is pushed off the bench by proposals whose
 *        own voting is still OPEN, so `hasProposals()` goes FALSE and
 *        `CauldronRegistry.relaunch` reverts `NoProposal()`
 *        (CauldronRegistry.sol:841) for the whole of the attacker's voting
 *        period — the eternal machine cannot be reborn.
 *
 * CauldronGovernor._benchRecord (CauldronGovernor.sol:689-706) weighs an entry at
 * `q.votes` for anything that merely `exists && !consumed`; it does not care that
 * the proposal is still taking votes. _recomputeLeader (:812-826) then SKIPS
 * still-open entries (`if (block.timestamp <= p.votingEndsAt) continue;`). The two
 * disagree: an open proposal is heavy enough to evict, but not eligible to win.
 * _bestUnconsumed's cached-leader fast path does not save it, because `vote`
 * hands `_leaderId` to the heavier open proposal, which the fast path then
 * rejects for being open.
 */
contract K2c_RelaunchStalledByOpenBrews is Test {
    K2cVotes votes;
    CauldronGovernor gov;
    /// @dev Tracked explicitly: `block.number` read in this frame does not
    ///      observe a `vm.roll` issued in the same frame.
    uint256 blk;
    uint256 ts;

    address constant GUILD = address(0x6111D);
    address constant ATTACKER = address(0xBAD);

    function setUp() public {
        ts = 1_800_000_000; blk = 1000;
        vm.warp(ts);
        vm.roll(blk);
        votes = new K2cVotes();
        gov = new CauldronGovernor(address(votes), 3 days);
        votes.set(GUILD, 300);
        votes.set(ATTACKER, 301);
    }

    function _file(address who, string memory name) internal returns (uint256 id) {
        vm.prank(who);
        id = gov.propose(
            name, "BRW", MetadataMode.BaseURI, "ipfs://x/",
            address(0), "", "", 0, 0, address(0)
        );
        blk = vm.getBlockNumber() + 1;
        vm.roll(blk);
        vm.prank(who);
        gov.vote(id);
    }

    function _winnerId() internal view returns (uint256 id) {
        try gov.winner() returns (uint256 w, BrewSpec memory) {
            id = w;
        } catch {
            id = 0;
        }
    }

    // ---------------------------------------------------------------
    // POSITIVE: a settled brew mandate is available to relaunch.
    // ---------------------------------------------------------------
    function test_K2c_positive_settledMandateIsAvailable() public {
        uint256 good = _file(GUILD, "GuildBrew");
        ts = vm.getBlockTimestamp() + 3 days + 1; vm.warp(ts);
        assertEq(vm.getBlockTimestamp(), ts, "warp took effect");

        bool has = gov.hasProposals();
        uint256 w = _winnerId();

        assertTrue(has, "relaunch has a mandate to consume");
        assertEq(w, good, "and it is the guild's");
    }

    // ---------------------------------------------------------------
    // ATTACK: eight OPEN filings make relaunch() revert NoProposal().
    // ---------------------------------------------------------------
    function test_K2c_openBrewsStallRelaunch() public {
        uint256 good = _file(GUILD, "GuildBrew");
        ts = vm.getBlockTimestamp() + 3 days + 1; vm.warp(ts);
        assertEq(vm.getBlockTimestamp(), ts, "warp took effect");

        bool hasBefore = gov.hasProposals();
        uint256 winnerBefore = _winnerId();

        uint256 firstJunk;
        for (uint256 i; i < 8; ++i) {
            uint256 id = _file(ATTACKER, "Junk");
            if (i == 0) firstJunk = id;
        }

        bool hasAfter = gov.hasProposals();
        uint256 winnerAfter = _winnerId();

        // Once the attacker's own window closes, THEIR brew is what relaunch
        // installs — name, symbol, renderer, quote and supply all attacker-chosen.
        ts = vm.getBlockTimestamp() + 3 days + 1; vm.warp(ts);
        assertEq(vm.getBlockTimestamp(), ts, "warp took effect");
        uint256 winnerLater = _winnerId();

        assertTrue(hasBefore, "before: the guild's settled mandate is available");
        assertEq(winnerBefore, good, "before: it is the winner");
        assertTrue(hasAfter, "FIXED: hasProposals() still sees the settled mandate, so relaunch() runs");
        assertEq(winnerAfter, good, "FIXED: the guild's settled brew is still the winner");
        // Once the attacker's OWN window closes their brew does outrank the
        // guild's on votes (301 > 300) — that is honest governance, not the bug.
        // The bug was that relaunch() was unrunnable in the window BEFORE that,
        // when the guild's brew was the only settled mandate on file.
        assertEq(winnerLater, firstJunk, "a settled brew with more votes may win on the merits");
    }
}
