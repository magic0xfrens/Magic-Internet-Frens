// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {LocalLifecycleBoot} from "../audit_full_scope/LocalLifecycleAdapters.t.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";

contract R23LifecycleFeed {
    uint8 public mode;
    function setMode(uint8 m) external { mode = m; }
    function decimals() external pure returns (uint8) { return 8; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (mode == 1) revert("dependency unavailable");
        if (mode == 2) assembly { return(0, 0) }
        return (1, 3000e8, block.timestamp, block.timestamp, 1);
    }
}

/// Local production hook/registry/managers; configured synthetic oracle feed.
/// Inherited fixture documents additional ambient manager inventory.
contract R23OracleHookLifecycle is LocalLifecycleBoot {
    QuoteOracle internal oracle;
    R23LifecycleFeed internal feed;
    function setUp() public {
        _boot(20 ether, 0);
        oracle = new QuoteOracle(address(this));
        feed = new R23LifecycleFeed();
        oracle.setFeed(address(0), address(feed), 3600, 18);
        hook.setDeathThreshold(1e18, address(oracle), 50e18, 0.05e18, 1200e18);
        assertGt(_buy(0.1 ether, attacker), 0, "healthy funded swap");
        assertGt(hook.getVolume24h(registry.generationPoolId(1)), 1e18);
        assertFalse(hook.isDead(registry.generationPoolId(1)));
        (uint256 cached,,) = oracle.cache(address(0));
        assertEq(cached, 3000e18, "real swap warms cache");
    }
    function _ageAndTrade(uint8 mode) internal {
        feed.setMode(mode);
        uint256 later = vm.getBlockTimestamp() + 25 hours;
        vm.warp(later);
        assertEq(vm.getBlockTimestamp(), later);
        vm.roll(vm.getBlockNumber() + 200);
        assertEq(hook.getVolume24h(registry.generationPoolId(1)), 0, "old volume aged out");
        assertGt(_buy(0.1 ether, attacker), 0, "trade still executes");
    }
    function test_R23_ControlOrdinaryRevertKeepsActiveGenerationAlive() public {
        _ageAndTrade(1);
        assertGt(hook.getVolume24h(registry.generationPoolId(1)), 1e18);
        assertFalse(hook.isDead(registry.generationPoolId(1)));
    }
    function test_R23_MalformedFeedMustAlsoKeepActiveGenerationAlive() public {
        _ageAndTrade(2);
        assertGt(hook.getVolume24h(registry.generationPoolId(1)), 1e18,
            "malformed response must not bypass cached volume price");
        assertFalse(hook.isDead(registry.generationPoolId(1)));
    }
}
