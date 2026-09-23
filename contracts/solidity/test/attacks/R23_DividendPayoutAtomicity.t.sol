// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {DividendBasketTest} from "../DividendBasket.t.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract R23MovesThenFails is ERC20 {
    bool public fail;
    constructor() ERC20("Payout boundary", "PAY") { _mint(msg.sender, 100); }
    function setFail(bool value) external { fail = value; }
    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        return !fail;
    }
}

contract R23DividendPayoutAtomicity is DividendBasketTest {
    function test_R23_FailedLegRollsBackTokenMovementBeforeBanking() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);
        R23MovesThenFails asset = new R23MovesThenFails();
        asset.approve(address(div), 100);
        div.fundToken(address(asset), 100);
        div.fundToken(address(usdg), 1000e6);
        asset.setFail(true);
        vm.prank(alice); div.claimTokens(1);
        assertEq(usdg.balanceOf(alice), 1000e6);
        assertEq(asset.balanceOf(alice), 0, "false leg must roll back transfer");
        assertEq(asset.balanceOf(address(div)), 100);
        assertEq(div.owedAsset(alice, address(asset)), 100);
        assertEq(div.accountedOf(address(asset)), 100);
        asset.setFail(false);
        vm.prank(alice); div.withdrawOwedToken(address(asset));
        assertEq(asset.balanceOf(alice), 100);
        assertEq(div.owedAsset(alice, address(asset)), 0);
        assertEq(div.accountedOf(address(asset)), 0);
        vm.prank(alice); div.withdrawOwedToken(address(asset));
        assertEq(asset.balanceOf(alice), 100, "cannot pay twice");
    }

    function test_R23_PayoutHelperRejectsExternalCaller() public {
        usdg.mint(address(div), 100);
        vm.expectRevert(MiFrensDividend.NotOwner.selector);
        vm.prank(alice);
        div.pushTokenIsolated(address(usdg), alice, 100);
        assertEq(usdg.balanceOf(address(div)), 100);
        assertEq(usdg.balanceOf(alice), 0);
    }
}
