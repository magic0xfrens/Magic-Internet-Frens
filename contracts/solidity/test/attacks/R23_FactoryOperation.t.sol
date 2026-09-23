// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
contract R23FactoryTarget {
    address public factory;
    address immutable admin;
    constructor(address a) { admin = a; }
    function setFactory(address f) external { require(msg.sender == admin); factory = f; }
}
contract R23FactoryOperation is Test {
    function test_rerunFactoryIsNotScheduledButOriginalRemainsExecutable() public {
        address[] memory roles = new address[](1); roles[0] = address(this);
        TimelockController lock = new TimelockController(60, roles, roles, address(this));
        R23FactoryTarget target = new R23FactoryTarget(address(lock));
        CauldronFactory first = new CauldronFactory();
        bytes memory scheduled = abi.encodeCall(target.setFactory, (address(first)));
        lock.schedule(address(target), 0, scheduled, bytes32(0), bytes32(0), 60);
        bytes32 originalId = lock.hashOperation(address(target), 0, scheduled, bytes32(0), bytes32(0));
        vm.warp(lock.getTimestamp(originalId) + 1);
        CauldronFactory second = new CauldronFactory();
        bytes memory rerun = abi.encodeCall(target.setFactory, (address(second)));
        assertTrue(lock.isOperationReady(originalId));
        assertFalse(lock.isOperationReady(lock.hashOperation(address(target), 0, rerun, bytes32(0), bytes32(0))));
        vm.expectRevert();
        lock.execute(address(target), 0, rerun, bytes32(0), bytes32(0));
        lock.execute(address(target), 0, scheduled, bytes32(0), bytes32(0));
        assertEq(target.factory(), address(first));
    }
}
