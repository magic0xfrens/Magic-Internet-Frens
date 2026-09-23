// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";

contract R23BoundaryFeed {
    uint8 public mode;
    int256 public answer = 3000e8;
    function setMode(uint8 m) external { mode = m; }
    function setAnswer(int256 a) external { answer = a; }
    function decimals() external view returns (uint8) {
        if (mode == 2) assembly { return(0, 0) }
        return 8;
    }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (mode == 1) assembly { return(0, 0) }
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}

/// Tests the documented unusable-feed return contract, not live feed behaviour.
/// A configurable synthetic feed models an external dependency failing after setup.
contract R23OracleFailureBoundaries is Test {
    QuoteOracle internal oracle;
    R23BoundaryFeed internal feed;
    function setUp() public {
        vm.warp(1_800_000_000);
        assertEq(vm.getBlockTimestamp(), 1_800_000_000);
        oracle = new QuoteOracle(address(this));
        feed = new R23BoundaryFeed();
        oracle.setFeed(address(0), address(feed), 3600, 18);
        oracle.setBounds(address(0), 100e18, 100_000e18);
        assertEq(oracle.usdPerRawUnit(address(0)), 3000e18);
    }
    function test_R23_MalformedRoundMustReturnUnpriceable() public {
        feed.setMode(1);
        assertEq(oracle.usdPerRawUnit(address(0)), 0);
    }
    function test_R23_MalformedDecimalsMustReturnUnpriceable() public {
        feed.setMode(2);
        assertEq(oracle.usdPerRawUnit(address(0)), 0);
    }
    function test_R23_ExtremeAnswerMustRespectRefusalContract() public {
        feed.setAnswer(type(int256).max);
        assertEq(oracle.usdPerRawUnit(address(0)), 0);
    }
    function test_R23_MalformedFeedMustRetainUsableCache() public {
        uint256 good = oracle.cachedUsdPerRawUnit(address(0));
        feed.setMode(1);
        uint256 later = vm.getBlockTimestamp() + oracle.TTL() + 1;
        vm.warp(later);
        assertEq(vm.getBlockTimestamp(), later);
        assertEq(oracle.cachedUsdPerRawUnit(address(0)), good);
    }
    function test_R23_CodeLessFeedMustReturnUnpriceable() public {
        oracle.setFeed(address(0), address(0xC0DE), 3600, 18);
        assertEq(address(0xC0DE).code.length, 0);
        assertEq(oracle.usdPerRawUnit(address(0)), 0);
    }
}
