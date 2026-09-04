// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../cauldron/MiFrensGenesis.sol";

/// Cancel/refund safety valve for a stalled genesis presale. No fork needed.
contract GenesisCancelRefundTest is Test {
    MiFrensGenesis g;
    address dev = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant PRICE = 0.0222 ether;

    function setUp() public {
        // supply 1111, cap 2222, price 0.0222, maxWallet 50
        g = new MiFrensGenesis("MiFrens", "MIFREN", 1111, 2222, PRICE, 50, "u/");
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_Refund_ReturnsExactEth() public {
        vm.prank(alice); g.mint{value: PRICE * 3}(3);
        vm.prank(bob);   g.mint{value: PRICE * 2}(2);
        assertEq(g.paid(alice), PRICE * 3);
        assertEq(g.paid(bob), PRICE * 2);

        // deployer cancels the stalled sale
        g.cancelPresale();
        assertTrue(g.cancelled());

        // minting is now blocked
        vm.prank(alice);
        vm.expectRevert(MiFrensGenesis.AlreadyCancelled.selector);
        g.mint{value: PRICE}(1);

        // each minter reclaims exactly what they paid
        uint256 aBefore = alice.balance;
        vm.prank(alice); uint256 got = g.refund();
        assertEq(got, PRICE * 3, "alice full refund");
        assertEq(alice.balance - aBefore, PRICE * 3);
        assertEq(g.paid(alice), 0, "paid zeroed");

        // no double refund
        vm.prank(alice);
        vm.expectRevert(MiFrensGenesis.NothingToRefund.selector);
        g.refund();

        // contract retains only bob's outstanding refund
        assertEq(address(g).balance, PRICE * 2, "only bob left");
    }

    function test_Cancel_OnlyDeployer() public {
        vm.prank(alice);
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        g.cancelPresale();
    }

    function test_Refund_RequiresCancel() public {
        vm.prank(alice); g.mint{value: PRICE}(1);
        vm.prank(alice);
        vm.expectRevert(MiFrensGenesis.NotCancelled.selector);
        g.refund();
    }

    receive() external payable {}
}
