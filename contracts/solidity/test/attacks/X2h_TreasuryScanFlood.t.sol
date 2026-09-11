// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/// @dev `getVotes` is the PROPOSAL threshold (everyone may file); `getPastVotes` is
///      the per-address ballot weight the test sets. Total supply 100, so
///      QUORUM_BPS (10%) needs 10 FOR-votes.
contract X2hVotes {
    mapping(address => uint256) public w;
    function set(address a, uint256 n) external { w[a] = n; }
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return w[a]; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 100; }
}

/**
 * X2h — REGRESSION. `winner()`'s fallback scan could be inflated without bound by
 *       a stranger, and the O(1) hint that was supposed to make that irrelevant
 *       could be pinned on a corpse for the price of one vote every six days.
 *
 * TWO HALVES THAT FEED EACH OTHER.
 *
 *  1. `_leadVotes` (TreasuryGovernor.sol:164) is lowered in exactly ONE branch —
 *     case (4) in `vote` — which needs
 *         block.timestamp > _openVotedAt + VOTING_PERIOD + EXECUTION_WINDOW
 *     and case (5) rewrites `_openVotedAt` on ANY FOR-vote for a live proposal the
 *     hint does not track. So one junk filing plus one FOR-vote every six days
 *     keeps case (4) permanently unreachable: `_leadId` stays pointed at a dead
 *     proposal and EVERY `winner()` call falls through to the scan.
 *
 *  2. The scan (`:593 for (uint256 i = n; i >= 1; --i)`) is bounded by TIME, not
 *     position — but the window is six days wide and `propose` has no per-proposal
 *     cooldown, so during the only window in which an envelope can be installed a
 *     stranger can fill it. `execute` gates on `id != winner()`, so an over-budget
 *     scan is an un-installable mandate.
 *
 * FIX: the fallback walks {TreasuryGovernor._bench}, eight slots entered by
 * FOR-VOTES rather than by position or recency — the same shape the sibling brew
 * governor got for the same reason. The pinnable hint is left alone on purpose:
 * with an O(8) fallback, pinning it costs eight cold reads instead of one.
 */
contract X2h_TreasuryScanFlood is Test {
    TreasuryGovernor internal gov;
    X2hVotes internal votes;

    address internal alice   = address(0xA11CE);
    address internal guild   = address(0x6111D);
    address internal mallory = address(0x4A110);

    function allowedQuote(address) external pure returns (bool) { return true; }
    address internal constant USDG = address(0xDDDD);

    function setUp() public {
        votes = new X2hVotes();
        gov = new TreasuryGovernor(IVotes721(address(votes)), address(this), address(this), 0, 0, 0, 0, false);
        vm.warp(100 days);
        vm.roll(1000);
    }

    function _file(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = gov.propose(USDG, 2_500);
    }

    function _voteFor(address who, uint256 weight, uint256 id) internal {
        votes.set(who, weight);
        vm.prank(who);
        gov.vote(id, true);
    }

    /// @dev via_ir CSEs repeated TIMESTAMP reads, so warps go through storage.
    uint256 internal clock;
    function _warpTo(uint256 t) internal { clock = t; vm.warp(clock); }

    /// @dev Pin `_leadId` on a proposal that is already dead, by keeping
    ///      `_openVotedAt` fresh with one junk FOR-vote every five days.
    function _pinTheHintOnACorpse() internal returns (uint256 corpse) {
        uint256 t0 = block.timestamp;
        corpse = _file(alice);
        _voteFor(alice, 10, corpse);                    // hint = corpse, _leadVotes = 10

        // t+2d: corpse still alive -> case (5) dates `_openVotedAt`.
        _warpTo(t0 + 2 days);
        _voteFor(mallory, 1, _file(mallory));

        // From here the corpse is dead, but case (4) needs six clear days with no
        // case (5) write. One junk vote every five days denies it, forever.
        for (uint256 k = 1; k <= 4; ++k) {
            _warpTo(t0 + 2 days + k * 5 days);
            votes.set(mallory, 1);
            uint256 j = _file(mallory);
            vm.prank(mallory);
            gov.vote(j, true);
        }
    }

    /// @dev Gas for one external `winner()` call, and what it returned.
    function _winner() internal returns (uint256 gasUsed, uint256 id) {
        uint256 g0 = gasleft();
        id = gov.winner();
        gasUsed = g0 - gasleft();
    }

    // ── CONTROL: with the hint pinned and NO flood, the guild's mandate wins ──

    function test_X2h_control_pinnedHintStillResolvesToTheGuildsMandate() public {
        uint256 corpse = _pinTheHintOnACorpse();
        uint256 g = _file(guild);
        _voteFor(guild, 10, g);
        _warpTo(block.timestamp + 3 days + 1);

        (uint256 gasUsed, uint256 w) = _winner();
        assertEq(w, g, "the fallback finds the guild's mandate, not the pinned corpse");
        assertTrue(w != corpse, "and the pinned hint is NOT what wins");
        emit log_named_uint("X2h winner() gas, no flood", gasUsed);
    }

    // ── THE FINDING: a flood inside the window must not price out `execute` ──

    function test_X2h_floodCannotInflateTheWinnerScan() public {
        _pinTheHintOnACorpse();

        uint256 g = _file(guild);
        _voteFor(guild, 10, g);

        // 300 junk filings inside the same six-day window, one MiFren, no cooldown.
        votes.set(mallory, 1);
        uint256 floodGas = gasleft();
        for (uint256 i; i < 300; ++i) { vm.prank(mallory); gov.propose(USDG, 2_500); }
        floodGas -= gasleft();

        _warpTo(block.timestamp + 3 days + 1);
        (uint256 gasUsed, uint256 w) = _winner();

        assertEq(w, g, "FIXED: the guild's mandate still wins under a 300-proposal flood");
        assertLt(gasUsed, 60_000, "FIXED: the scan is O(BENCH_SLOTS), not O(proposals in the window)");

        // And the mandate is actually installable, which is the property that was lost.
        gov.execute(g);
        (address dest,) = gov.allowance();
        assertEq(dest, USDG, "the envelope installs");
        emit log_named_uint("X2h flood gas for 300 filings", floodGas);
        emit log_named_uint("X2h winner() gas after the flood", gasUsed);
    }
}
