// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployLaunchpad} from "../../deploy/DeployLaunchpad.s.sol";

contract QuotePreflightHarness is DeployLaunchpad {
    function preflight() external view returns (bool) { return _preflightQuoteStack(); }
}

contract QuotePreflightFeed {
    uint8 public immutable decimals;
    int256 internal immutable answer;
    uint256 internal immutable updatedAt;
    constructor(uint8 d, int256 a, uint256 t) { decimals = d; answer = a; updatedAt = t; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

/// Preflight-only harness never reads a signer, broadcasts, or deploys a stack.
contract QuotePreflightEdgesTest is Test {
    QuotePreflightHarness internal script;
    function setUp() public {
        vm.chainId(11155111);
        vm.warp(1 days);
        script = new QuotePreflightHarness();
    }
    // Foundry snapshots EVM state, not process environment changes between tests.
    modifier freshEnvironment() {
        vm.setEnv("DEPLOY_QUOTES", "true");
        vm.setEnv("NATIVE_PEGGED_USD", "false");
        vm.setEnv("PEG_STABLES", "true");
        vm.setEnv("HEARTBEAT_ETH", "3600");
        vm.setEnv("HEARTBEAT_USDC", "3600");
        vm.setEnv("ETH_MIN_USD", "100000000000000000000");
        vm.setEnv("ETH_MAX_USD", "100000000000000000000000");
        _;
    }
    function _feed(uint8 d, int256 answer, uint256 timestamp) internal returns (address feed) {
        feed = address(new QuotePreflightFeed(d, answer, timestamp));
        vm.setEnv("FEED_ETH_USD", vm.toString(feed));
    }
    function _unusable(address feed) internal {
        vm.expectRevert(abi.encodeWithSelector(DeployLaunchpad.FeedUnusable.selector, feed));
        script.preflight();
    }
    function test_disabledStackDoesNotRequireSepoliaOrFeeds() public freshEnvironment {
        vm.chainId(1);
        vm.setEnv("DEPLOY_QUOTES", "false");
        assertFalse(script.preflight());
    }
    function test_explicitSepoliaPegsNeedNoFeed() public freshEnvironment {
        vm.setEnv("NATIVE_PEGGED_USD", "true");
        assertTrue(script.preflight());
    }
    function test_freshNativeAndStableFeedsAreAccepted() public freshEnvironment {
        _feed(8, 2000e8, vm.getBlockTimestamp());
        address stable = address(new QuotePreflightFeed(6, 1e6, vm.getBlockTimestamp()));
        vm.setEnv("PEG_STABLES", "false");
        vm.setEnv("FEED_USDC_USD", vm.toString(stable));
        assertTrue(script.preflight());
    }
    function test_futureTimestampRejected() public freshEnvironment {
        _unusable(_feed(8, 2000e8, vm.getBlockTimestamp() + 1));
    }
    function test_nonpositiveAnswerRejected() public freshEnvironment {
        _unusable(_feed(8, 0, vm.getBlockTimestamp()));
        _unusable(_feed(8, -1, vm.getBlockTimestamp()));
    }
    function test_invalidHeartbeatRejected() public freshEnvironment {
        _feed(8, 2000e8, vm.getBlockTimestamp());
        vm.setEnv("HEARTBEAT_ETH", "0");
        vm.expectRevert(abi.encodeWithSelector(DeployLaunchpad.InvalidHeartbeat.selector, 0));
        script.preflight();
        vm.setEnv("HEARTBEAT_ETH", "4294967296");
        vm.expectRevert(abi.encodeWithSelector(DeployLaunchpad.InvalidHeartbeat.selector, uint256(1) << 32));
        script.preflight();
    }
    function test_boundsAndDecimalScalingEnforced() public freshEnvironment {
        _unusable(_feed(8, 99e8, vm.getBlockTimestamp()));
        _unusable(_feed(8, 100001e8, vm.getBlockTimestamp()));
        _feed(20, 2000e20, vm.getBlockTimestamp());
        assertTrue(script.preflight());
    }
    function test_decimalOverflowRejected() public freshEnvironment {
        _unusable(_feed(0, type(int256).max, vm.getBlockTimestamp()));
        _unusable(_feed(255, 1, vm.getBlockTimestamp()));
    }
    function test_stableFeedRoundedToZeroIsRejected() public freshEnvironment {
        vm.setEnv("NATIVE_PEGGED_USD", "true");
        vm.setEnv("PEG_STABLES", "false");
        address stable = address(new QuotePreflightFeed(20, 1, vm.getBlockTimestamp()));
        vm.setEnv("FEED_USDC_USD", vm.toString(stable));
        _unusable(stable);
    }
}
