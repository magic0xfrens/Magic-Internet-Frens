// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {CauldronTokenSupplyTest} from "../CauldronTokenSupply.t.sol";
import {CauldronToken} from "../../CauldronToken.sol";

contract R23TokenAuthority is CauldronTokenSupplyTest {
    function test_R23_MintSelectorActuallyRevertsWithoutChangingSupply() public {
        uint256 supply = token.totalSupply();
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1 ether));
        assertFalse(ok, "no external mint dispatch");
        assertEq(token.totalSupply(), supply);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_R23_AllowanceDoesNotGrantBurnAuthority() public {
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.expectRevert(CauldronToken.NotRegistry.selector);
        vm.prank(bob);
        token.burn(alice, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(bob);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether, "ordinary approved transfer still works");
        assertEq(token.totalSupply(), SUPPLY);
    }
}
