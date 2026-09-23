// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LocalLifecycleBoot} from "./LocalLifecycleAdapters.t.sol";

/// Local dependency-failure injection, not a claim that an attacker can replace
/// the configured engine. Protect the hook boundary when its bounded call fails.
contract PreSweepFailureClosedTest is LocalLifecycleBoot {
    bytes4 constant SWEEP = bytes4(keccak256("sweepLiquidations(address,int256,bool,uint160)"));

    function setUp() public {
        _boot(60 ether, 0);
        _bootPerp(40 ether, 400_000_000 ether);
        address owner = address(0xA001);
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        perp.openShort{value: 0.01 ether}(2, 0, 0, 0.01 ether);
        assertEq(perp.openCount(), 1);
    }

    function buyThroughHook() external {
        require(msg.sender == address(this), "self only");
        _buy(1 ether, attacker);
    }

    function _assertRefused() internal {
        uint160 priceBefore = _sqrtP();
        uint256 plvBefore = perp.plv();
        (bool filled,) = address(this).call(abi.encodeCall(this.buyThroughHook, ()));
        assertFalse(filled, "pre-trade sweep failure must not authorize a swap");
        assertEq(_sqrtP(), priceBefore, "refusal must roll back price");
        assertEq(perp.plv(), plvBefore, "refusal must preserve backing");
        assertEq(perp.openCount(), 1, "refusal must preserve book");
    }

    function test_revertedPreTradeSweepMustRefuseSwap() public {
        vm.mockCallRevert(address(perp), abi.encodePacked(SWEEP), abi.encodeWithSignature("InjectedSweepFailure()"));
        _assertRefused();
    }

    function test_emptyPreTradeSweepResponseMustRefuseSwap() public {
        vm.mockCall(address(perp), abi.encodePacked(SWEEP), bytes(""));
        _assertRefused();
    }

    function test_realEngineControlFills() public {
        uint160 beforePrice = _sqrtP();
        _buy(1 ether, attacker);
        assertTrue(_sqrtP() != beforePrice, "control must execute a price-moving trade");
    }
}
