// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

contract M4Votes is IVotes721 {
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

contract M4Registry {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * @notice A MANDATE NOBODY CAN EXECUTE MUST NOT WEDGE GOVERNANCE.
 *
 *  `propose` (TreasuryGovernor.sol:437) and `execute` (:617) both refuse while
 *  `envelope.active && now < envelope.expiry`. Correct for a rotation in
 *  progress; wrong for one that CANNOT progress. If the timelock de-lists the
 *  destination after the vote — or its route dies, or the source leg does —
 *  every `rotateSliceFrom` reverts, nothing advances, and the guild cannot even
 *  FILE a correction until ENVELOPE_LIFETIME elapses (30 days on mainnet
 *  defaults). The only escape was the guardian-only `cancel` (:643), which makes
 *  governance liveness depend on a privileged party being present and willing.
 *
 *  The fix is {TreasuryGovernor.stalled}: an envelope that has moved ZERO bps
 *  and is past its COOLDOWN stops blocking. This test proves BOTH halves — the
 *  stuck envelope clears with no privileged call, and a healthy one that has
 *  moved even one basis point cannot be cleared by anybody.
 */
contract M4E_StalledMandate is Test {
    TreasuryGovernor gov;
    M4Votes votes;
    M4Registry reg;

    address constant USDG = address(0x115D);
    address constant XNVDA = address(0x8B0A);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant GRIEFER = address(0x6217);
    address constant GUARDIAN = address(0x6A2D);

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.roll(1000);
        votes = new M4Votes();
        reg = new M4Registry();
        reg.set(USDG, true);
        reg.set(XNVDA, true);
        votes.setSupply(1000);
        gov = new TreasuryGovernor(votes, address(reg), GUARDIAN, 0, 0, 0, 0, false);
        votes.set(ALICE, 10);
        votes.set(BOB, 10);
        votes.set(GRIEFER, 10);
    }

    function _snapshot(uint256 id) internal view returns (uint256) {
        (,,, uint256 snap,,,,,) = gov.proposals(id);
        return snap;
    }

    function _installEnvelope(address quote, uint16 bps) internal returns (uint256 id) {
        vm.prank(ALICE);
        id = gov.propose(quote, bps);
        votes.setPast(_snapshot(id), ALICE, 200); // > 10% of 1000 supply
        vm.prank(ALICE);
        gov.vote(id, true);
        _warpTo(vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1);
        gov.execute(id);
    }

    function _warpTo(uint256 t) internal {
        vm.warp(t);
        assertEq(vm.getBlockTimestamp(), t, "warp must land");
    }

    function _envelope()
        internal
        view
        returns (address quote, uint16 maxTotalBps, uint16 movedBps, uint64 expiry, bool active, uint16 movedPrimaryBps)
    {
        return gov.envelope();
    }

    // ------------------------------------------------------------------
    // HALF ONE: the wedge clears, permissionlessly.
    // ------------------------------------------------------------------
    function test_unexecutable_mandate_does_not_wedge_propose() public {
        uint256 installedAt = vm.getBlockTimestamp();
        _installEnvelope(USDG, 3000);
        installedAt = vm.getBlockTimestamp();

        (address q,, uint16 moved, uint64 expiry, bool active,) = _envelope();
        assertEq(q, USDG, "envelope installed against USDG");
        assertTrue(active, "envelope is live");
        assertEq(moved, uint16(0), "nothing moved yet");

        //  THE MANDATE BECOMES UNEXECUTABLE: the timelock de-lists the
        //  destination after the vote. `RedemptionExt.rotateSliceFrom` checks
        //  `allowedQuote[toQuote]` before liquidity moves, so from here every
        //  slice reverts and `movedBps` can never leave zero.
        reg.set(USDG, false);

        //  A YOUNG ENVELOPE IS NOT STALLED. Being unexecutable is not enough —
        //  the guild has not been given its cooldown to act on it yet.
        assertFalse(gov.stalled(), "an envelope inside its cooldown is never stalled");
        vm.prank(BOB);
        vm.expectRevert(TreasuryGovernor.ProposalActive.selector);
        gov.propose(XNVDA, 2000);

        //  ONE SECOND BEFORE THE COOLDOWN ELAPSES: still blocked.
        _warpTo(installedAt + gov.COOLDOWN() - 1);
        assertFalse(gov.stalled(), "not stalled one second early");
        vm.prank(BOB);
        vm.expectRevert(TreasuryGovernor.ProposalActive.selector);
        gov.propose(XNVDA, 2000);

        //  AT THE COOLDOWN: the stuck mandate stops silencing the guild, and no
        //  guardian, owner or other privileged party was involved.
        _warpTo(installedAt + gov.COOLDOWN());
        assertTrue(gov.stalled(), "a zero-progress envelope past its cooldown is stalled");
        assertTrue(vm.getBlockTimestamp() < expiry, "and this is still well inside the envelope's life");

        vm.prank(BOB);
        uint256 fix_ = gov.propose(XNVDA, 2000);
        assertTrue(fix_ != 0, "the correction can be FILED");

        //  AND EXECUTED — `execute` carries the same gate, so relaxing only
        //  `propose` would have left the correction stuck one step later.
        votes.setPast(_snapshot(fix_), BOB, 200);
        vm.prank(BOB);
        gov.vote(fix_, true);
        _warpTo(vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1);
        gov.execute(fix_);

        (address q2,,,, bool active2,) = _envelope();
        assertEq(q2, XNVDA, "the replacement mandate is now the live envelope");
        assertTrue(active2, "and it is live");
        assertFalse(gov.stalled(), "a freshly installed envelope is not stalled");
    }

    // ------------------------------------------------------------------
    // HALF TWO: a healthy envelope cannot be cleared by a stranger.
    // ------------------------------------------------------------------
    function test_griefer_cannot_supersede_an_advancing_mandate() public {
        _installEnvelope(USDG, 3000);
        uint256 installedAt = vm.getBlockTimestamp();
        (,,,, bool active,) = _envelope();
        assertTrue(active, "envelope is live");

        //  ONE SLICE LANDS. `rotateSliceFrom` is permissionless, so this is a
        //  move any member of the guild can make with a single transaction —
        //  and it immunises the mandate for the rest of its life.
        vm.prank(address(reg));
        gov.consume(1, false);
        (,, uint16 moved,,,) = _envelope();
        assertEq(moved, uint16(1), "one basis point moved");

        //  PAST THE COOLDOWN, AND FOR THE WHOLE REST OF THE ENVELOPE'S LIFE, a
        //  griefer still cannot file over it.
        _warpTo(installedAt + gov.COOLDOWN() + 1);
        assertFalse(gov.stalled(), "an envelope that moved is never stalled");
        vm.prank(GRIEFER);
        vm.expectRevert(TreasuryGovernor.ProposalActive.selector);
        gov.propose(XNVDA, 2000);

        (,,, uint64 expiry,,) = _envelope();
        _warpTo(uint256(expiry) - 1);
        assertFalse(gov.stalled(), "still not stalled one second before expiry");
        vm.prank(GRIEFER);
        vm.expectRevert(TreasuryGovernor.ProposalActive.selector);
        gov.propose(XNVDA, 2000);

        //  Expiry is what releases it, exactly as before this change.
        _warpTo(uint256(expiry));
        vm.prank(GRIEFER);
        uint256 id = gov.propose(XNVDA, 2000);
        assertTrue(id != 0, "an EXPIRED envelope releases governance, as it always did");
    }

    // ------------------------------------------------------------------
    // The guardian backstop is still there; it was not replaced.
    // ------------------------------------------------------------------
    function test_guardian_cancel_still_clears_immediately() public {
        uint256 id = _installEnvelope(USDG, 3000);
        assertFalse(gov.stalled(), "not stalled yet");
        vm.prank(GUARDIAN);
        gov.cancel(id);
        (,,,, bool active,) = _envelope();
        assertFalse(active, "guardian cleared the envelope with no waiting");
        assertFalse(gov.stalled(), "an inactive envelope is not 'stalled', it is gone");
    }
}
