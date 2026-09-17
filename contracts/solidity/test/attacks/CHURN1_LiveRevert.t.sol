// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

interface IRouter {
    function playChurn(uint256 quoteIn, uint256 loops, uint256 minTokenOut, uint256 openMax)
        external payable returns (uint256);
    function play(uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax)
        external payable returns (uint256);
}

/// Reproduces the live r44 `playChurn` revert against a Sepolia fork so the
/// trace shows WHICH inner call fails. `play` on the same router succeeds, so
/// this isolates the churn leg.
contract CHURN1_LiveRevert is Test {
    address constant ROUTER = 0x465819232bD80d89423F5b8eE5B958C61bC82FDa;
    address constant USER = 0xC94400e90bB652AFA02740bFf50824E14069c133;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
    }

    function test_CHURN1_playWorksButChurnReverts() public {
        if (bytes(vm.envOr("FORK_RPC", string(""))).length == 0) return;
        vm.deal(USER, 10 ether);

        vm.prank(USER);
        uint256 opened = IRouter(ROUTER).play{value: 0.01 ether}(0, 0, 0, 0, 0);
        console2.log("play opened crystals:", opened);
        assertGt(opened, 0, "control: play works on this router");

        vm.prank(USER);
        IRouter(ROUTER).playChurn{value: 0.01 ether}(0, 1, 0, 0);
    }
}
