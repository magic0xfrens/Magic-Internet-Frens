// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

interface IRouter {
    function playChurn(uint256 quoteIn, uint256 loops, uint256 minTokenOut, uint256 openMax)
        external payable returns (uint256);
    function play(uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax)
        external payable returns (uint256);
}

/// Was: reproduced the live r44 `playChurn` revert. Rounds 43 and 44 shipped a
/// router built from a stale `out/` with no `playChurn` in its dispatcher
/// (selector 0xdf70b5a4), so every spin died at ~537 gas with empty data. The
/// fix was a deploy-pipeline one (forced clean builds + selector parity), and
/// r45 carries the selector — but this test stayed pinned to the r44 router and
/// so kept failing on every fork run long after the fix shipped, reading as a
/// live regression it no longer was.
///
/// Now a POSITIVE check against the router in `indexer/deployments/round.json`
/// (round 45). If a future round ships without the selector, this fails.
contract CHURN1_LiveRevert is Test {
    /// round 45 `contracts.gachaRouter` (indexer/deployments/round.json)
    address constant ROUTER = 0x16df9e45a93DaC058AFf3c5b1415926ECD0A15b4;
    address constant USER = 0xC94400e90bB652AFA02740bFf50824E14069c133;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        require(bytes(rpc).length != 0, "CHURN1_LiveRevert: fork not active - PoC proved nothing");
        vm.createSelectFork(rpc);
    }

    function test_CHURN1_liveRouterPlaysAndChurns() public {
        vm.deal(USER, 10 ether);

        vm.prank(USER);
        uint256 opened = IRouter(ROUTER).play{value: 0.01 ether}(0, 0, 0, 0, 0);
        console2.log("play opened crystals:", opened);
        assertGt(opened, 0, "control: play works on the live router");

        vm.prank(USER);
        IRouter(ROUTER).playChurn{value: 0.01 ether}(0, 1, 0, 0);
        assertGt(ROUTER.code.length, 0, "the live router exists");
    }
}
