// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TreasuryGovernorTest} from "../TreasuryGovernor.t.sol";

contract R23TreasuryTargeting is TreasuryGovernorTest {
    function test_equalSupportMustPreferEarlierProposalAsDocumented() public {
        uint256 earlier = _propose(ALICE, USDG, 3000);
        uint256 later = _propose(BOB, XNVDA, 3000);
        _voteWith(later, BOB, 100, true);
        _voteWith(earlier, ALICE, 100, true);
        vm.warp(vm.getBlockTimestamp() + gov.VOTING_PERIOD());
        assertEq(gov.winner(), earlier, "documented lower-id tie break");
    }

    function test_cancellingOldExecutedProposalMustNotCancelNewEnvelope() public {
        uint256 oldId = _propose(ALICE, USDG, 3000);
        _voteWith(oldId, ALICE, 100, true);
        vm.warp(vm.getBlockTimestamp() + gov.VOTING_PERIOD());
        gov.execute(oldId);
        vm.prank(address(reg));
        gov.consume(3000, true);
        vm.warp(vm.getBlockTimestamp() + gov.COOLDOWN());
        uint256 newId = _propose(BOB, XNVDA, 3000);
        _voteWith(newId, BOB, 100, true);
        vm.warp(vm.getBlockTimestamp() + gov.VOTING_PERIOD());
        gov.execute(newId);
        (, uint16 beforeLeft) = gov.allowance();
        assertEq(beforeLeft, 3000);
        vm.prank(GUARDIAN);
        gov.cancel(oldId);
        (, uint16 afterLeft) = gov.allowance();
        assertEq(afterLeft, beforeLeft, "stale id must not target another envelope");
    }
}
