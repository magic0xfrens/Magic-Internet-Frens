// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {XL1_LiqTwapAndDepthCap} from "./XL1_LiqTwapAndDepthCap.t.sol";
import {R23MalformedMark} from "./R23_MarkMalformed.t.sol";

contract R23MarkMalformedLocal is XL1_LiqTwapAndDepthCap {
    function _closeWithSource(bool fails) internal {
        uint256 id = _openShort();
        assertEq(perp.openCount(), 1);
        perp.setRouting(address(0xD1), address(0x7777), address(0x7777),
            address(new R23MalformedMark(887273, fails)), address(0));
        perp.poke();
        _rest(40);
        vm.prank(trader);
        perp.close(id, 0);
        assertEq(perp.openCount(), 0, "funded position must remain closeable");
    }
    function test_localMalformedMarkCannotBlockClose() public { _closeWithSource(false); }
    function test_localRevertingMarkStillAllowsClose() public { _closeWithSource(true); }
}
