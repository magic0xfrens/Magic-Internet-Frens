// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

contract R23BenchVotes {
    function getVotes(address voter) external pure returns (uint256) { return uint160(voter); }
    function getPastVotes(address voter, uint256) external pure returns (uint256) { return uint160(voter); }
}

contract R23GovernorBench is Test {
    function test_openFloodDisplacesOnlyOneOfEightSettledBenchEntries() public {
        CauldronGovernor governor = new CauldronGovernor(address(new R23BenchVotes()), 60);
        governor.setRegistry(address(this));
        for (uint256 i = 1; i <= 8; ++i) {
            vm.prank(address(uint160(i)));
            governor.propose("Brew", "BRW", MetadataMode.BaseURI,
                "ipfs://brew/", address(0), "", "", 0, 0, address(0));
        }
        vm.roll(governor.getProposal(8).snapshot + 1);
        for (uint256 i = 1; i <= 8; ++i) {
            vm.prank(address(uint160(i))); governor.vote(i);
        }
        vm.warp(governor.getProposal(8).votingEndsAt + 1);
        for (uint256 i = 9; i <= 16; ++i) {
            vm.prank(address(uint160(i)));
            governor.propose("Open", "NEW", MetadataMode.BaseURI,
                "ipfs://new/", address(0), "", "", 0, 0, address(0));
        }
        vm.roll(governor.getProposal(16).snapshot + 1);
        for (uint256 i = 9; i <= 16; ++i) {
            vm.prank(address(uint160(i))); governor.vote(i);
        }
        for (uint256 i = 8; i >= 2; --i) {
            (uint256 selected,) = governor.winner();
            assertEq(selected, i, "open flood must preserve seven settled entries");
            governor.markConsumed(selected);
        }
        assertFalse(governor.hasProposals());
        assertFalse(governor.getProposal(1).consumed);
        vm.warp(governor.getProposal(16).votingEndsAt + 1);
        (uint256 winner,) = governor.winner();
        assertEq(winner, 16);
    }

    function test_evictedProposalIsUndiscoverableButFreshMandateRecovers() public {
        CauldronGovernor governor = new CauldronGovernor(address(new R23BenchVotes()), 60);
        governor.setRegistry(address(this));
        for (uint256 i = 1; i <= 9; ++i) {
            vm.prank(address(uint160(i)));
            uint256 id = governor.propose("Brew", "BRW", MetadataMode.BaseURI,
                "ipfs://brew/", address(0), "", "", 0, 0, address(0));
            assertEq(id, i);
        }
        vm.roll(block.number + 1);
        for (uint256 i = 1; i <= 9; ++i) {
            vm.prank(address(uint160(i))); governor.vote(i);
        }
        vm.warp(block.timestamp + 61);
        for (uint256 i = 9; i >= 2; --i) {
            (uint256 winner,) = governor.winner();
            assertEq(winner, i);
            governor.markConsumed(winner);
        }
        CauldronGovernor.Proposal memory remaining = governor.getProposal(1);
        assertFalse(remaining.consumed);
        assertEq(remaining.votes, 1);
        assertFalse(governor.hasProposals(), "evicted mandate is absent from bounded selection");
        vm.expectRevert(CauldronGovernor.NoProposals.selector);
        governor.winner();
        vm.prank(address(1));
        uint256 fresh = governor.propose("Fresh", "NEW", MetadataMode.BaseURI,
            "ipfs://fresh/", address(0), "", "", 0, 0, address(0));
        vm.roll(governor.getProposal(fresh).snapshot + 1);
        vm.prank(address(1)); governor.vote(fresh);
        assertFalse(governor.hasProposals(), "fresh mandate must finish voting");
        vm.warp(governor.getProposal(fresh).votingEndsAt + 1);
        (uint256 recovered,) = governor.winner();
        assertEq(recovered, fresh);
        assertTrue(governor.hasProposals());
    }
}
