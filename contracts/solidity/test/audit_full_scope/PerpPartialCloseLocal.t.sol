// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {XL1_LiqTwapAndDepthCap} from "../attacks/XL1_LiqTwapAndDepthCap.t.sol";
import {Vm} from "forge-std/Vm.sol";

/// Real local V4 PoolManager + production PerpEngine, using the existing XL1
/// callback fixture. No fork or forced writes into engine storage.
contract PerpPartialCloseLocalTest is XL1_LiqTwapAndDepthCap {
    function test_partialCloseKeepsFundingAndBacking() public {
        uint256 id = _openShort();
        (,, uint128 initialCollateral, uint256 initialSize, uint256 initialPrincipal,,,) = perp.positions(id);
        assertGt(initialCollateral, 0);
        _skip(15);
        vm.recordLogs();
        _buy(1.2 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawPartial;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(perp) && logs[i].topics.length > 0
                && logs[i].topics[0] == keccak256("PartiallyClosed(uint256,uint256,uint256,uint256)")) {
                sawPartial = true;
            }
        }
        assertTrue(sawPartial, "real swap must reach partial settlement");
        (,, uint128 collateral, uint256 size, uint256 principal,,,) = perp.positions(id);
        assertGt(size, 0);
        assertLe(size, initialSize);
        assertGt(collateral, 0, "partial close retains its funding basis");
        assertLe(uint256(collateral) + principal, uint256(initialCollateral) + initialPrincipal);
        _rest(40);
        _skip(1 days);
        uint256 nowAt = vm.getBlockTimestamp();
        assertGt(nowAt, 1_800_000_000 + 1 days);
        perp.poke();
        assertGt(perp.fundingDelta(id), 0, "crowded short must still owe funding");
        assertEq(perp.openCount(), 1);
    }
}
