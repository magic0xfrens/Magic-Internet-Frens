// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/// @dev B-20 probe: does the MAX_WINNER_SCAN bound I added in pass 6 let spam
///      orphan a legitimately voted, still-executable proposal? That is the B-10
///      shape — a POSITIONAL window over a permissionless-to-grow list.
contract B20_SelfCheck is Test {
    TreasuryGovernor internal gov;
    RegStub internal reg;
    address constant USDG = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        reg = new RegStub();
        reg.allow(USDG);
        gov = new TreasuryGovernor(IVotes721(address(new V20())), address(reg), address(this));
    }

    function test_B20_VotedWinnerSurvivesSpamInsideTheExecutionWindow() public {
        // A genuine, passing proposal.
        uint256 mine = gov.propose(USDG, 2000);
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(mine, true);
        vm.warp(vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1);

        assertEq(gov.winner(), mine, "it wins before the spam");

        // Attacker files 64 proposals INSIDE the 3-day execution window. No
        // cooldown gates this; 5 MiFrens is the only cost.
        for (uint256 i; i < 64; ++i) gov.propose(USDG, 1000);

        assertEq(
            gov.winner(), mine,
            "a voted, still-executable winner must survive spam filed after it"
        );
    }
}

contract RegStub {
    mapping(address => bool) public allowedQuote;
    function allow(address q) external { allowedQuote[q] = true; }
}
contract V20 {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
