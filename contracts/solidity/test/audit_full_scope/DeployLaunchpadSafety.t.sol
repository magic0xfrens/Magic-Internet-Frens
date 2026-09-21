// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployLaunchpad} from "../../deploy/DeployLaunchpad.s.sol";

contract StaleLaunchpadFeed {
    function latestRoundData()
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, 2_000e8, 1, 1, 1);
    }
}

contract DeployLaunchpadSafetyTest is Test {
    DeployLaunchpad internal script;

    function setUp() public {
        script = new DeployLaunchpad();
    }

    function test_runRejectsMockQuotesOnMainnetBeforeReadingSignerOrDeploymentEnv() public {
        vm.chainId(1);
        vm.setEnv("DEPLOY_QUOTES", "true");

        vm.expectRevert(abi.encodeWithSelector(DeployLaunchpad.MockQuotesSepoliaOnly.selector, 1));
        script.run();
    }

    function test_runRejectsCodelessNativeFeedBeforeReadingSignerOrDeploymentEnv() public {
        address codeless = address(0xFEE1);
        vm.chainId(11155111);
        vm.setEnv("DEPLOY_QUOTES", "true");
        vm.setEnv("NATIVE_PEGGED_USD", "false");
        vm.setEnv("FEED_ETH_USD", vm.toString(codeless));

        vm.expectRevert(abi.encodeWithSelector(DeployLaunchpad.FeedHasNoCode.selector, codeless));
        script.run();
    }

    function test_runRejectsStaleNativeFeedBeforeReadingSignerOrDeploymentEnv() public {
        StaleLaunchpadFeed stale = new StaleLaunchpadFeed();
        vm.chainId(11155111);
        vm.warp(1 days);
        vm.setEnv("DEPLOY_QUOTES", "true");
        vm.setEnv("NATIVE_PEGGED_USD", "false");
        vm.setEnv("FEED_ETH_USD", vm.toString(address(stale)));
        vm.setEnv("HEARTBEAT_ETH", "3600");

        vm.expectRevert(
            abi.encodeWithSelector(DeployLaunchpad.FeedUnusable.selector, address(stale))
        );
        script.run();
    }
}
