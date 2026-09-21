// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {F2A_LegacyThresholdDecimals} from "../attacks/F2A_LegacyThresholdDecimals.t.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @dev Local hostile dependency: exceptional halt consumes forwarded call gas.
contract ExhaustingDecimals {
    fallback() external {
        assembly { invalid() }
    }
}

/// @dev Production hook/registry; inherited PoolManager is a stub. These tests
/// establish metadata arithmetic/cache behavior, not real-pool execution.
contract LegacyThresholdAcceptanceTest is F2A_LegacyThresholdDecimals {
    address constant METADATA = address(0xDEC1);

    // Compiler layout: appended internal cache, slot 69. Read-only observation;
    // no production getter or storage mutation is introduced for this test.
    function _raw() internal view returns (uint256) {
        return uint256(vm.load(address(hook), bytes32(uint256(69))));
    }

    function _decimals(uint256 value) internal {
        vm.mockCall(METADATA, abi.encodeWithSignature("decimals()"), abi.encode(value));
        vm.prank(address(registry));
        hook.setLiveKey(_key(METADATA));
    }

    function test_CacheTracksNativeSixEighteenAndNativeAgain() public {
        vm.prank(address(registry));
        hook.setLiveKey(_key(address(0)));
        assertEq(_raw(), DECLARED_THRESHOLD);
        vm.prank(address(registry));
        hook.setLiveKey(_key(address(usdg)));
        assertEq(_raw(), 20_000);
        vm.prank(address(registry));
        hook.setLiveKey(_key(address(dai)));
        assertEq(_raw(), DECLARED_THRESHOLD);
        vm.prank(address(registry));
        hook.setLiveKey(_key(address(0)));
        assertEq(_raw(), DECLARED_THRESHOLD);
    }

    function test_ConfigChangeRefreshesCacheAndZeroPreservesThreshold() public {
        _decimals(6);
        hook.setLegacyBuyback(address(registry), 10_000, 3 ether);
        assertEq(_raw(), 3e6);
        hook.setLegacyBuyback(address(registry), 10_000, 0);
        assertEq(_raw(), 3e6);
    }

    function test_RevertingMetadataFallsBackToOne() public {
        vm.mockCallRevert(METADATA, abi.encodeWithSignature("decimals()"), hex"deadbeef");
        vm.prank(address(registry));
        hook.setLiveKey(_key(METADATA));
        assertEq(_raw(), 1);
    }

    function testFuzz_ShortMetadataFallsBackToOne(uint8 length) public {
        length = uint8(bound(length, 0, 31));
        vm.mockCall(METADATA, abi.encodeWithSignature("decimals()"), new bytes(length));
        vm.prank(address(registry));
        hook.setLiveKey(_key(METADATA));
        assertEq(_raw(), 1);
    }

    function testFuzz_UnsupportedMetadataFallsBackToOne(uint256 decimals) public {
        decimals = bound(decimals, 78, type(uint256).max);
        _decimals(decimals);
        assertEq(_raw(), 1);
    }

    function test_SubRawUnitThresholdClampsToOne() public {
        _decimals(0);
        assertEq(_raw(), 1);
        _decimals(6);
        hook.setLegacyBuyback(address(registry), 10_000, 1);
        assertEq(_raw(), 1);
    }

    function test_HighDecimalsScaleAndOverflowSaturates() public {
        _decimals(24);
        assertEq(_raw(), DECLARED_THRESHOLD * 1e6);
        _decimals(77);
        assertEq(_raw(), DECLARED_THRESHOLD * 1e59);
        hook.setLegacyBuyback(address(registry), 10_000, type(uint256).max);
        assertEq(_raw(), type(uint256).max);
        _decimals(18);
        assertEq(_raw(), type(uint256).max);
    }

    /// @dev Reproduction, NOT a passing liveness guarantee. Governance-selected
    /// metadata can exhaust a realistically bounded setter call. Atomicity holds.
    function test_ExhaustingMetadataReproducesBoundedSetterFailureAtomically() public {
        vm.prank(address(registry));
        hook.setLiveKey(_key(address(0)));
        ExhaustingDecimals hostile = new ExhaustingDecimals();
        bytes memory data = abi.encodeWithSelector(hook.setLiveKey.selector, _key(address(hostile)));
        vm.prank(address(registry));
        (bool ok,) = address(hook).call{gas: 200_000}(data);
        assertFalse(ok, "reproduction: metadata exhausts the bounded setter");
        assertEq(Currency.unwrap(hook.liveKey().currency0), address(0), "live key rolls back");
        assertEq(_raw(), DECLARED_THRESHOLD, "threshold rolls back");

        // Failure is gas-dependent, not proof of a permanent protocol freeze.
        vm.prank(address(registry));
        (ok,) = address(hook).call{gas: 2_000_000}(data);
        assertTrue(ok, "EIP-150 reserve can fund fallback with a higher cap");
        assertEq(Currency.unwrap(hook.liveKey().currency0), address(hostile));
        assertEq(_raw(), 1);
    }
}
