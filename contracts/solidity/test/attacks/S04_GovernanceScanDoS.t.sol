// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/// @dev Mirrors test/TreasuryGovernor.t.sol's MockVotes so this suite stands
///      alone without touching that file.
contract SVotes is IVotes721 {
    mapping(address => uint256) public now_;
    mapping(uint256 => mapping(address => uint256)) public past;
    uint256 public supply;

    function set(address a, uint256 v) external { now_[a] = v; }
    function setPast(uint256 blk, address a, uint256 v) external { past[blk][a] = v; }
    function setSupply(uint256 v) external { supply = v; }
    function getVotes(address a) external view returns (uint256) { return now_[a]; }
    function getPastVotes(address a, uint256 blk) external view returns (uint256) { return past[blk][a]; }
    /// @dev Mirrors `Votes.getPastTotalSupply`, which is what the REAL vote
    ///      source ({MiFrensGenesis}, an `ERC721Votes` that is deliberately not
    ///      `ERC721Enumerable`) actually implements. The earlier `totalSupply()`
    ///      stub here existed on no production contract, so this mock asserted a
    ///      quorum path that reverted on every real deployment.
    function getPastTotalSupply(uint256) external view returns (uint256) { return supply; }
}

contract SRegistryStub {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  S-04 — TREASURY GOVERNANCE WEDGED BY PROPOSAL SPAM   [Track B — liveness]
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  {TreasuryGovernor.execute} gates on `id != winner()` (TreasuryGovernor.sol:379),
 *  so `winner()` sits on the ONLY path that installs a rotation envelope. It has
 *  two modes:
 *
 *    FAST PATH  — `if (hint != 0 && _executable(proposals[hint])) return hint;`
 *                 (:452-453), O(1).
 *    SCAN       — a backwards walk `for (uint256 i = n; i >= 1; --i)` that
 *                 `break`s only at the first proposal too old to execute (:483-492).
 *
 *  The scan is bounded by TIME, not position — deliberately, because a positional
 *  window reintroduced this repo's own B-10 (see the comment at :457-482). But
 *  "bounded by time" bounds only the AGE of the proposals walked, never HOW MANY
 *  were filed inside that window, and `propose` gates on nothing but
 *  PROPOSAL_THRESHOLD = 5 MiFrens (:301). The contract says so itself at :430-432:
 *  "COOLDOWN and the `envelope.active` check gate ENVELOPES, not proposals, so one
 *  holder can file indefinitely."
 *
 *  What makes that reachable is the leader cache. `_leadVotes` is written in
 *  exactly ONE place — `vote()`, :356-359, under `p.forVotes > _leadVotes` — and
 *  is NEVER reset: not by `execute`, not by `cancel`, nowhere (4 references in the
 *  whole file). So it is a permanent high-water mark. Once any proposal has drawn
 *  V votes, every later proposal that passes quorum with fewer than V can never
 *  become the hint, and `_leadId` keeps pointing at a proposal that is executed,
 *  cancelled or stale. `_executable` then returns false and EVERY `winner()` call
 *  falls through to the full scan.
 *
 *  Net: after the first well-supported vote, a holder of 5 MiFrens can file junk
 *  and make `execute` cost O(proposals filed in the last 6 days) — until it no
 *  longer fits in a block, at which point no rotation can be installed at all and
 *  the guild's mandate expires unexecuted inside its 3-day window.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract S04_GovernanceScanDoS is Test {
    TreasuryGovernor gov;
    SVotes votes;
    SRegistryStub reg;

    address constant USDG = address(0x115D);
    address constant XNVDA = address(0x8B0A);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant SQUATTER = address(0x5A77);
    address constant GUARDIAN = address(0x6A2D);

    /// Mainnet block gas limit, the ceiling `execute` must fit under.
    uint256 constant BLOCK_GAS_LIMIT = 30_000_000;

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.roll(1000);
        votes = new SVotes();
        reg = new SRegistryStub();
        reg.set(USDG, true);
        reg.set(XNVDA, true);
        votes.setSupply(1000);
        gov = new TreasuryGovernor(votes, address(reg), GUARDIAN, 0, 0, 0, 0, false);

        votes.set(ALICE, 100);
        votes.set(BOB, 100);
        votes.set(SQUATTER, 5); // exactly PROPOSAL_THRESHOLD
    }

    function _propose(address who, address quote, uint16 bps) internal returns (uint256 id) {
        vm.prank(who);
        id = gov.propose(quote, bps);
    }

    function _snapshot(uint256 id) internal view returns (uint256) {
        (,,, uint256 snap,,,,,) = gov.proposals(id);
        return snap;
    }

    function _voteWith(uint256 id, address who, uint256 weight, bool support) internal {
        votes.setPast(_snapshot(id), who, weight);
        vm.prank(who);
        gov.vote(id, support);
    }

    /// @dev Poison the leader cache the way ordinary use does: one well-supported
    ///      proposal sets `_leadVotes` high, then ages out of its execution window.
    ///      `_leadId` still points at it, and it is no longer `_executable`.
    function _poisonLeaderCache() internal {
        uint256 big = _propose(ALICE, USDG, 3000);
        _voteWith(big, ALICE, 500, true); // _leadVotes = 500, _leadId = big
        // 3d voting + 3d execution window + 1 => `big` is stale, never executed.
        vm.warp(block.timestamp + 6 days + 1);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  1. THE CACHE RETIRES A DEAD LEADER
    // ───────────────────────────────────────────────────────────────────────

    /// @notice RENAMED BY THE FIX (was `test_poc_leadCacheIsAPermanentHighWaterMark`).
    ///         `_leadVotes` used to be written in one place and lowered nowhere, so
    ///         after a 500-vote proposal aged out, a later 150-vote mandate could
    ///         never become the hint and every `winner()` paid for a full scan.
    ///
    ///         The mechanism is now the opposite, and both halves are asserted: a
    ///         vote on the live mandate RETIRES the dead hint (so the O(1) path is
    ///         available), and the elected proposal is unchanged (the fix is about
    ///         cost, and must not touch which proposal the guild gets).
    function test_poc_leadCacheRetiresADeadLeader() public {
        _poisonLeaderCache();

        uint256 real = _propose(BOB, XNVDA, 3000);
        _voteWith(real, BOB, 150, true); // passes quorum (10% of 1000 = 100) but 150 < 500
        vm.warp(block.timestamp + 3 days + 1);

        assertEq(gov.winner(), real, "the right proposal is still elected");

        //  The hint is what makes that cheap. A full scan over this tiny set would
        //  also return `real`, so assert the COST that distinguishes them: reading
        //  the winner must now be O(1)-cheap even though a bigger, dead proposal
        //  came before it.
        uint256 before = gasleft();
        gov.winner();
        uint256 used = before - gasleft();
        console2.log("winner() gas after the dead leader retired:", used);
        assertLt(used, 10_000, "the dead hint was retired - winner() is back on its fast path");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  2. THE COST — measured, then extrapolated to the block ceiling
    // ───────────────────────────────────────────────────────────────────────

    /// @notice Measures the MARGINAL gas each junk proposal adds to `winner()`.
    ///
    ///  INVERTED BY THE FIX. Pre-fix this asserted the defect — `assertGt(gasAt200,
    ///  gasAt0, "spam must make winner() more expensive")` — and measured 888 gas
    ///  per junk proposal, ~33,783 proposals (~2.67 billion gas) to push `execute`
    ///  past a 30M block. It now asserts the property that replaced it: the
    ///  marginal cost is ZERO, because the restored hint keeps `winner()` on its
    ///  O(1) path no matter how much junk is filed behind it.
    ///
    ///  MEASURED BETWEEN TWO SPAM LEVELS, not against a spam-free baseline. Filing
    ///  proposals warms `proposalCount` and the hint slots, so a 0-spam run pays
    ///  cold-SLOAD prices (2100 vs 100 gas) that a spammed run does not — post-fix
    ///  the spammed call is actually CHEAPER, which is storage warmth, not
    ///  algorithmic improvement. Differencing two spammed runs cancels that out and
    ///  isolates the only thing in question: does cost GROW with the list?
    function test_poc_measureSpamCostPerProposal() public {
        _poisonLeaderCache();
        uint256 real = _propose(BOB, XNVDA, 3000);
        _voteWith(real, BOB, 150, true);
        uint256 gasAt200 = _winnerGasAfterSpam(200);

        setUp();
        _poisonLeaderCache();
        real = _propose(BOB, XNVDA, 3000);
        _voteWith(real, BOB, 150, true);
        uint256 gasAt400 = _winnerGasAfterSpam(400);

        console2.log("winner() gas, 200 junk     :", gasAt200);
        console2.log("winner() gas, 400 junk     :", gasAt400);

        uint256 growth = gasAt400 > gasAt200 ? gasAt400 - gasAt200 : 0;
        uint256 perProposal = growth / 200;
        console2.log("growth over +200 proposals :", growth);
        console2.log("marginal gas per proposal  :", perProposal);

        assertEq(perProposal, 0, "FIXED: junk must add no marginal cost to winner()");
        //  Sentinel: the assertion above is unconditional, but make a skipped
        //  body impossible to mistake for a pass (audit rule).
        assertTrue(true, "reached");
    }

    /// @dev Files `n` junk proposals, then returns the gas `winner()` consumes.
    function _winnerGasAfterSpam(uint256 n) internal returns (uint256 used) {
        for (uint256 i; i < n; ++i) {
            vm.prank(SQUATTER);
            gov.propose(USDG, 100);
        }
        vm.warp(block.timestamp + 3 days + 1);
        uint256 before = gasleft();
        gov.winner();
        used = before - gasleft();
    }

    function _proposeGas() internal returns (uint256 used) {
        uint256 before = gasleft();
        vm.prank(SQUATTER);
        gov.propose(USDG, 100);
        used = before - gasleft();
    }

    // ───────────────────────────────────────────────────────────────────────
    //  3. THE LIVENESS INVARIANT
    // ───────────────────────────────────────────────────────────────────────

    /// @notice LIVENESS INVARIANT — the property that actually breaks: the cost of
    ///         reading the guild's mandate must not be inflatable by a third party.
    ///         `execute` gates on `id != winner()` (:379), so whoever can raise the
    ///         cost of `winner()` can raise the cost of executing the guild's vote,
    ///         and past a block limit can prevent it outright.
    ///
    ///         Stated as gas independence rather than a fixed ceiling on purpose:
    ///         a threshold test only fails once the attacker buys enough spam, which
    ///         says more about the constant chosen than about the contract. The
    ///         defect is the DEPENDENCE itself.
    ///
    ///         Pre-fix this FAILED at "363611 != 6399" — 400 junk proposals made
    ///         reading the mandate 57x more expensive. It passes now because a
    ///         vote on the live mandate retires the dead hint and restores the O(1)
    ///         path (TreasuryGovernor {vote} case (4)).
    ///
    ///         `assertLe`, not `assertEq`: filing proposals WARMS `proposalCount`
    ///         and the hint slots, so the spammed run pays 100-gas warm SLOADs
    ///         where the honest run pays 2100-gas cold ones and comes out cheaper.
    ///         Demanding exact equality would fail on storage warmth while the
    ///         actual property — cost must not GROW with the list — holds. The
    ///         companion test measures marginal growth directly, between two
    ///         equally-warm runs, and asserts it is zero.
    function test_invariant_winnerCostIsIndependentOfThirdPartySpam() public {
        // Baseline: the honest world — one stale leader, one live mandate.
        _poisonLeaderCache();
        uint256 real = _propose(BOB, XNVDA, 3000);
        _voteWith(real, BOB, 150, true);
        uint256 clean = _winnerGasAfterSpam(0);

        // Identical world, except a squatter also filed junk into the same window.
        setUp();
        _poisonLeaderCache();
        real = _propose(BOB, XNVDA, 3000);
        _voteWith(real, BOB, 150, true);
        uint256 spammed = _winnerGasAfterSpam(400);

        console2.log("winner() gas, honest world :", clean);
        console2.log("winner() gas, 400 junk     :", spammed);

        assertLe(
            spammed,
            clean,
            "LIVENESS: a third party must not be able to inflate the cost of reading the mandate"
        );
        //  And the mandate must still be the one the guild chose - a cheap
        //  `winner()` that returns the wrong proposal would be no fix at all.
        assertEq(gov.winner(), real, "the guild's mandate is still the winner");
    }
}
