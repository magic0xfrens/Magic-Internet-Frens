// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/// Minimal IVotes surface the governor actually consumes.
contract ZVotes {
    mapping(address => uint256) public power;

    function setPower(address who, uint256 p) external {
        power[who] = p;
    }

    function getVotes(address a) external view returns (uint256) {
        return power[a];
    }

    function getPastVotes(address a, uint256) external view returns (uint256) {
        return power[a];
    }

    function delegates(address a) external pure returns (address) {
        return a;
    }
}

/**
 * FINDING Z-03 (High) — `relaunch()` performs an UNBOUNDED O(n) scan over every
 * proposal ever submitted, and proposing is permissionless for the holder of a
 * single MiFren. Proposal spam therefore raises the gas cost of every rebirth
 * without limit until `relaunch()` cannot fit in a block — permanently halting the
 * "eternal machine". It compounds with Z-07: `registry.setGovernor` is `onlyOwner`
 * and registry ownership is burned into the presale contract at deploy, so a
 * spammed governor can never be replaced.
 *
 * Scan sites, all inside ONE `relaunch()` call:
 *   CauldronRegistry.relaunch:597  governor.hasProposals() -> _bestUnconsumed -> _recomputeLeader
 *   CauldronRegistry.relaunch:660  governor.winner()       -> _bestUnconsumed -> _recomputeLeader
 *   CauldronRegistry.relaunch:674  governor.markConsumed() -> _recomputeLeader
 *
 * `markConsumed` recomputes whenever the consumed id is the cached leader — which
 * is ALWAYS true on the relaunch path, because relaunch consumes exactly the id
 * that `winner()` (i.e. `_bestUnconsumed()`) just returned.
 *
 * STATUS: FIXED. `_recomputeLeader` now scans at most `MAX_LEADER_SCAN` (64) of the
 * most recent proposals, making relaunch gas O(1) in the proposal count. The
 * cached-leader fast path is untouched, so an established winner still wins however
 * much spam follows it. The suite below is the regression.
 *
 * HARNESS NOTE: this profile compiles with `via_ir`, whose optimiser treats the
 * NUMBER and TIMESTAMP opcodes as loop-invariant and common-subexpression-eliminates
 * them. `vm.roll(block.number + 1)` written twice in one function therefore rolls to
 * the SAME target twice. All clocks below are held in storage for that reason.
 */
contract Z03_GovernorSpamRelaunchDoS is Test {
    CauldronGovernor internal gov;
    ZVotes internal votes;
    address internal constant ATTACKER = address(0xBAD);
    address internal constant WHALE = address(0xB16);
    address internal constant REGISTRY = address(0x9E9);

    uint256 internal _bn; // storage-backed clocks (see harness note)
    uint256 internal _ts;

    function setUp() public {
        votes = new ZVotes();
        gov = new CauldronGovernor(address(votes));
        gov.setRegistry(REGISTRY);
        votes.setPower(ATTACKER, 1); // ONE NFT is the entire cost of entry
        votes.setPower(WHALE, 1_000_000);
        _bn = block.number;
        _ts = block.timestamp;
    }

    function _advanceBlock() internal {
        _bn += 1;
        vm.roll(_bn);
    }

    function _closeVoting() internal {
        _ts += gov.VOTING_PERIOD() + 1;
        vm.warp(_ts);
    }

    function _spam(uint256 n) internal {
        vm.startPrank(ATTACKER);
        for (uint256 i = 0; i < n; ++i) {
            gov.propose("x", "x", MetadataMode.BaseURI, "u", address(0), "", "", 0, 0, address(0));
        }
        vm.stopPrank();
    }

    /// REGRESSION: spam no longer inflates the per-relaunch scan.
    function test_FIXED_RelaunchScanIsBoundedUnderSpam() public {
        uint256 gasBase = _measureConsumeScan();
        _spam(200);
        uint256 gas200 = _measureConsumeScan();
        _spam(600); // 800 spam proposals total
        uint256 gas800 = _measureConsumeScan();

        emit log_named_uint("relaunch scan gas @   1 proposal ", gasBase);
        emit log_named_uint("relaunch scan gas @ 201 proposals", gas200);
        emit log_named_uint("relaunch scan gas @ 801 proposals", gas800);

        // 600 extra spam proposals must cost the rebirth NOTHING: both measurements
        // sit past the 64-proposal scan bound, so the cost is flat.
        assertEq(gas800, gas200, "FIXED: scan cost is flat past the bound");
        assertLt(gas800, 250_000, "FIXED: one scan stays far inside a block");
        emit log_named_uint("MAX_LEADER_SCAN bound (proposals)", 64);
    }

    /// REGRESSION: an attacker can still defeat the leader CACHE by keeping a
    /// still-open proposal in the leader slot, but the fallback rescan is now bounded.
    function test_FIXED_ForcedRescanStaysBounded() public {
        vm.prank(ATTACKER);
        uint256 winId = gov.propose("Real", "REAL", MetadataMode.BaseURI, "ipfs://x", address(0), "", "", 1000, 0, address(0));
        _advanceBlock();
        vm.prank(ATTACKER);
        gov.vote(winId);
        _closeVoting();

        _spam(400);

        uint256 g0 = gasleft();
        gov.hasProposals();
        uint256 cached = g0 - gasleft();

        // A whale outvotes the cache with a brand-new, still-OPEN proposal.
        vm.prank(WHALE);
        uint256 fresh = gov.propose("Grief", "GRF", MetadataMode.BaseURI, "u", address(0), "", "", 0, 0, address(0));
        _advanceBlock();
        vm.prank(WHALE);
        gov.vote(fresh); // `_leaderId` now points at an OPEN proposal

        g0 = gasleft();
        gov.hasProposals();
        uint256 uncached = g0 - gasleft();

        emit log_named_uint("hasProposals gas, cache HIT ", cached);
        emit log_named_uint("hasProposals gas, cache MISS", uncached);
        // The cache is still defeatable, but the fallback scan is now BOUNDED, so
        // defeating it costs the attacker effort and buys them no unbounded gas growth.
        assertLt(uncached, 250_000, "FIXED: even a forced rescan stays bounded");
    }

    /// Sanity (UNCHANGED, and recorded as accepted): proposing remains open to anyone
    /// holding one unit of voting power, with no cooldown, deposit or per-address cap.
    /// That is deliberate; the bounded scan is what removes its DoS leverage.
    function test_INFO_ProposingIsStillPermissionless() public {
        uint256 before = gov.proposalCount();
        _spam(50);
        assertEq(gov.proposalCount(), before + 50, "one NFT, fifty proposals, no cooldown");
    }

    /// @dev Measure exactly what `relaunch()` pays at its `markConsumed` site: the
    ///      consumed id is the CACHED LEADER (relaunch always consumes `winner()`),
    ///      so `_recomputeLeader` runs.
    function _measureConsumeScan() internal returns (uint256 used) {
        uint256 snap = vm.snapshotState();
        vm.prank(WHALE);
        uint256 id = gov.propose("W", "W", MetadataMode.BaseURI, "u", address(0), "", "", 0, 0, address(0));
        _advanceBlock();
        vm.prank(WHALE);
        gov.vote(id); // whale power makes this the leader
        _closeVoting();
        assertEq(_winnerId(), id, "measured proposal is the winner relaunch would consume");

        vm.prank(REGISTRY);
        uint256 g0 = gasleft();
        gov.markConsumed(id);
        used = g0 - gasleft();
        vm.revertToState(snap);
        _bn = block.number;
        _ts = block.timestamp;
    }

    function _winnerId() internal view returns (uint256 id) {
        (id,) = gov.winner();
    }
}
