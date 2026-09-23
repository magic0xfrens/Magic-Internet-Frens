// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RotationLifecycleLocalTest} from "../audit_full_scope/RotationLifecycleLocal.t.sol";
import {IPositionManagerOps} from "../../cauldron/PoolOps.sol";

/// Actual registry/facet and funded V4 positions; no target storage writes.
contract R23EmergencyRotationRecovery is RotationLifecycleLocalTest {
    function test_rotatedQuoteRequiresSeparateEmergencySweep() public {
        _approveRotation(address(usd));
        (, uint256 foreign) = _move(0);
        assertGt(IPositionManagerOps(posm).getPositionLiquidity(foreign), 0);
        uint256 adminQuote = usd.balanceOf(address(this));
        uint256 registryQuote = usd.balanceOf(address(registry));
        uint256 adminNative = address(this).balance;
        registry.armEmergency();
        registry.emergencyWithdrawLP(gen);
        assertGt(address(this).balance, adminNative, "native launch quote returned");
        assertEq(IPositionManagerOps(posm).getPositionLiquidity(foreign), 0, "foreign LP unwound");
        assertEq(usd.balanceOf(address(this)), adminQuote, "foreign quote not included in admin payout");
        uint256 remaining = usd.balanceOf(address(registry));
        assertGt(remaining, registryQuote, "foreign recovery remains in registry custody");
        registry.armEmergency();
        registry.emergencySweep(address(usd));
        assertEq(usd.balanceOf(address(registry)), 0);
        assertEq(usd.balanceOf(address(this)), adminQuote + remaining, "separate action recovers all quote");
    }
}
