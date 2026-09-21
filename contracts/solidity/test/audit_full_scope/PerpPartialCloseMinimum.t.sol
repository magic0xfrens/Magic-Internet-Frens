// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {XL1_LiqTwapAndDepthCap} from "../attacks/XL1_LiqTwapAndDepthCap.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";

/// Production engine + V4, fixture afterSwap hook/registry. LP withdrawal is a
/// fixture operation, not a claim that an attacker can withdraw registry LP.
contract PerpPartialCloseMinimumTest is XL1_LiqTwapAndDepthCap {
    function _thinBook() internal returns (uint256 id, uint256 initialSize) {
        id = _openShort();
        initialSize = _size(id);
        _modify(-887_200, 887_200, -int256(uint256(L0) - uint256(L0) / 1000));
        assertGt(initialSize, token.balanceOf(address(pm)), "full debt cannot be bought from the remaining book");
    }

    function test_ownerPartialCloseMustRespectNonzeroMinimum() public {
        (uint256 id, uint256 initialSize) = _thinBook();
        uint256 beforeVault = _vaultEth();
        uint256 beforeToken = token.balanceOf(address(pm));
        uint256 beforeTrader = trader.balance;
        vm.prank(trader);
        vm.expectRevert(PerpEngine.Slippage.selector);
        perp.close(id, 1);
        assertEq(_size(id), initialSize);
        assertEq(_vaultEth(), beforeVault);
        assertEq(token.balanceOf(address(pm)), beforeToken);
        assertEq(trader.balance, beforeTrader);
    }

    function test_zeroMinimumExplicitlyAllowsPartialClose() public {
        (uint256 id, uint256 initialSize) = _thinBook();
        uint256 beforeTrader = trader.balance;
        vm.prank(trader);
        perp.close(id, 0);
        assertGt(_size(id), 0, "must actually reach partial close");
        assertLt(_size(id), initialSize, "must retire some debt");
        assertEq(_traderOf(id), trader);
        assertEq(trader.balance, beforeTrader, "partial close pays no output");
    }
}
