// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";

contract R23SeederOwnerView {
    address public owner;
    constructor(address who) { owner = who; }
}
contract R23RejectPrimeRefund {
    receive() external payable { revert("reject"); }
}
contract R23SeederPrimeRefund is Test {
    CauldronSeeder seeder;
    address constant OWNER = address(0x1234);
    address constant TREASURY = address(0x5678);
    function setUp() public {
        // No pool calls occur in these pre-campaign funding/refund tests.
        seeder = new CauldronSeeder(address(new R23SeederOwnerView(OWNER)), address(0), address(0));
        vm.deal(address(this), 3 ether);
        seeder.fundPrime{value: 1 ether}(TREASURY);
    }
    function test_R23_FailedRefundPreservesBudgetThenOwnerCanRecover() public {
        R23RejectPrimeRefund rejector = new R23RejectPrimeRefund();
        vm.expectRevert(bytes("eth"));
        seeder.refundPrime(address(rejector));
        assertEq(address(seeder).balance, 1 ether);
        assertEq(seeder.primeBudget(), 1 ether);
        assertEq(seeder.primeTo(), TREASURY);
        vm.prank(OWNER);
        seeder.refundPrime(TREASURY);
        assertEq(TREASURY.balance, 1 ether);
        assertEq(address(seeder).balance, 0);
        assertEq(seeder.primeBudget(), 0);
        assertEq(seeder.primeSpent(), 0);
        assertEq(seeder.primeTo(), address(0));
    }
    function test_R23_StrangerCannotRefundOrRetarget() public {
        vm.expectRevert(CauldronSeeder.OnlyRegistry.selector);
        vm.prank(address(0xBAD));
        seeder.refundPrime(address(0xBAD));
        vm.expectRevert(CauldronSeeder.OnlyRegistry.selector);
        vm.prank(address(0xBAD));
        seeder.fundPrime(address(0xBAD));
        assertEq(seeder.primeBudget(), 1 ether);
        assertEq(seeder.primeTo(), TREASURY);
        assertEq(address(seeder).balance, 1 ether);
    }
    function test_R23_AdminCannotRetargetOutstandingBudgetWithoutRefund() public {
        vm.expectRevert(CauldronSeeder.BadConfig.selector);
        seeder.fundPrime(OWNER);
        assertEq(seeder.primeTo(), TREASURY);
        seeder.refundPrime(TREASURY);
        seeder.fundPrime{value: 1 ether}(OWNER);
        assertEq(seeder.primeTo(), OWNER);
        assertEq(seeder.primeBudget(), 1 ether);
        assertEq(address(seeder).balance, 1 ether);
    }
}
