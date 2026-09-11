// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-17 — TreasuryGovernor.winner() scanned every proposal ever filed
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `execute` gates on `id != winner()` (TreasuryGovernor.sol:273), so `winner()`
 *  sits on the ONLY path that installs a rotation envelope. It looped
 *  `i = 1; i <= proposalCount` — unbounded in the all-time proposal count.
 *
 *  `propose` requires {PROPOSAL_THRESHOLD} MiFrens and nothing else. {COOLDOWN}
 *  and the `envelope.active` check gate ENVELOPES, not proposals — so a single
 *  holder can file indefinitely, and each filing permanently lengthens the scan
 *  until `execute` cannot fit in a block. At that point no rotation can ever be
 *  installed again.
 *
 *  This is the same shape as the project's own Z-03 (rated High and fixed in
 *  `CauldronGovernor` with `MAX_LEADER_SCAN = 64`); the treasury side never got
 *  the fix.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B17_TreasuryScanBound is Test {
    TreasuryGovernor internal gov;
    RegStub internal reg;
    address constant USDG = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        reg = new RegStub();
        reg.allow(USDG);
        gov = new TreasuryGovernor(IVotes721(address(new V17())), address(reg), address(this), 0, 0, 0, 0, false);
    }

    /// @notice INVARIANT: spam must not make a LEGITIMATELY VOTED proposal
    ///         expensive to execute.
    ///
    ///  That is the property worth defending, and it is narrower than "winner()
    ///  is always cheap". An earlier version of this test filed hundreds of
    ///  UNVOTED proposals and measured `winner()` — but with nothing executable
    ///  `winner()` returns 0 and `execute` reverts `DidNotPass` regardless, so
    ///  the griefer is only burning their own gas. Measuring that proved nothing.
    ///
    ///  With a real winner present, the hint from {vote} makes `winner()` O(1)
    ///  however much spam surrounds it — which is what keeps `execute` reachable.
    function test_INVARIANT_B17_AVotedWinnerStaysCheapUnderSpam() public {
        // A genuine, voted, executable proposal.
        uint256 mine = gov.propose(USDG, 2000);
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(mine, true);
        vm.warp(vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1);

        uint256 g0 = gasleft();
        assertEq(gov.winner(), mine, "wins before the spam");
        uint256 clean = g0 - gasleft();

        // Bury it under spam.
        for (uint256 i; i < 300; ++i) gov.propose(USDG, 1000);

        g0 = gasleft();
        assertEq(gov.winner(), mine, "still wins after 300 filings");
        uint256 spammed = g0 - gasleft();

        emit log_named_uint("winner() gas, clean        ", clean);
        emit log_named_uint("winner() gas, +300 spam    ", spammed);
        emit log_named_uint("proposalCount              ", gov.proposalCount());

        //  O(1): the cached hint is validated and returned without a scan.
        assertLt(spammed, clean * 2, "a voted winner must not get more expensive under spam");
        assertLt(spammed, 50_000, "and must stay trivially inside a block");
    }

    /// @notice The bound must not orphan a genuinely executable proposal: a
    ///         winner has to be executed inside EXECUTION_WINDOW of its vote
    ///         closing, so anything executable is always among the most recent.
    function test_B17_ARecentWinnerIsStillFound() public {
        for (uint256 i; i < 200; ++i) gov.propose(USDG, 1000);

        uint256 id = gov.propose(USDG, 2000);
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(id, true);
        vm.warp(vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1);

        assertEq(gov.winner(), id, "a freshly voted proposal must still win after 200 filings");
    }
}

contract RegStub {
    mapping(address => bool) public allowedQuote;
    function allow(address q) external { allowedQuote[q] = true; }
}

/// @dev Above the proposal threshold and the quorum, so this suite measures the
///      scan rather than the politics.
contract V17 {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    /// @dev Mirrors `Votes.getPastTotalSupply` — the quorum denominator the
    ///      real vote source ({MiFrensGenesis}) actually implements.
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
