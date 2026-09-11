// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

contract X2iVotes {
    mapping(address => uint256) public w;
    function set(address a, uint256 n) external { w[a] = n; }
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return w[a]; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 100; }
}

/**
 * X2i — REGRESSION. `execute` (TreasuryGovernor.sol:478-511) enforced neither of
 *       the two gates `propose` does (`:387-388`): no `envelope.active` test and
 *       no COOLDOWN test. `:488 if (id != winner()) revert DidNotPass();` does not
 *       cover it, because proposals COMPETE rather than queue — two can pass in the
 *       same window, and executing the leader makes the loser the leader (the
 *       winner is now `executed`, so `_executable` drops it).
 *
 * So: execute A, an envelope installs and `lastEnvelopeAt` is stamped; then execute
 * B in the very next transaction and the live envelope is OVERWRITTEN, with
 * `movedBps` and `movedPrimaryBps` reset to zero. Two full envelopes' worth of the
 * treasury moves inside one cooldown - the budget COOLDOWN exists to bound - and
 * the guild voted for one of those as an ALTERNATIVE to the other.
 */
contract X2i_EnvelopeExecuteGate is Test {
    TreasuryGovernor internal gov;
    X2iVotes internal votes;

    address internal aliceV = address(0xA11CE);
    address internal bobV   = address(0xB0B);

    function allowedQuote(address) external pure returns (bool) { return true; }
    address internal constant USDG = address(0xDDDD);
    address internal constant DAI  = address(0xDA17);

    function setUp() public {
        votes = new X2iVotes();
        gov = new TreasuryGovernor(IVotes721(address(votes)), address(this), address(this), 0, 0, 0, 0, false);
        vm.warp(100 days);
        vm.roll(1000);
    }

    /// @dev Two proposals filed before any envelope exists; both pass quorum, A by
    ///      more. This is the ordinary competitive case `propose` is built for.
    function _twoPassingProposals() internal returns (uint256 a, uint256 b) {
        a = gov.propose(USDG, 2_500);
        b = gov.propose(DAI, 2_500);
        votes.set(aliceV, 30); vm.prank(aliceV); gov.vote(a, true);
        votes.set(bobV, 20);   vm.prank(bobV);   gov.vote(b, true);
        vm.warp(block.timestamp + 3 days + 1);
    }

    // ── CONTROL: the leader installs normally ────────────────────────────────

    function test_X2i_control_theLeaderInstallsItsEnvelope() public {
        (uint256 a,) = _twoPassingProposals();
        gov.execute(a);
        (address dest, uint16 left) = gov.allowance();
        assertEq(dest, USDG, "A's envelope is live");
        assertEq(left, 2_500, "with A's full budget");
    }

    // ── THE FINDING ──────────────────────────────────────────────────────────

    function test_X2i_theLoserCannotOverwriteTheLiveEnvelope() public {
        (uint256 a, uint256 b) = _twoPassingProposals();
        gov.execute(a);

        // With A executed, B is now the leader - so `id != winner()` lets it past.
        assertEq(gov.winner(), b, "precondition: the loser is now the leader");

        vm.expectRevert(TreasuryGovernor.ProposalActive.selector);
        gov.execute(b);

        (address dest, uint16 left) = gov.allowance();
        assertEq(dest, USDG, "FIXED: A's envelope is untouched");
        assertEq(left, 2_500, "FIXED: and its budget was not reset by a second mandate");
    }

    /// @dev And once the envelope is gone, COOLDOWN still applies - `execute` must
    ///      not become the way around the limit `propose` enforces.
    function test_X2i_cooldownAppliesToExecuteToo() public {
        (uint256 a, uint256 b) = _twoPassingProposals();
        gov.execute(a);
        gov.cancel(a);                       // guardian stops it; `active` clears
        assertEq(gov.winner(), b, "B is still executable on its own terms");

        vm.expectRevert(TreasuryGovernor.CooldownActive.selector);
        gov.execute(b);
    }
}
