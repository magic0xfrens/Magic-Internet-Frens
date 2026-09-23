// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Q07_WeightedMark} from "./Q07_WeightedMark.t.sol";
import {PerpMarkSource} from "../../cauldron/PerpMarkSource.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

contract R23MarkBoundaries is Q07_WeightedMark {
    function testFuzz_weightedTickStaysBetweenConstituents(
        int24 rawA, int24 rawB, uint128 weightA, uint128 weightB
    ) public {
        int24 a = int24(bound(int256(rawA), -887272, 887272));
        int24 b = int24(bound(int256(rawB), -887272, 887272));
        weightA = uint128(bound(uint256(weightA), 1, type(uint128).max));
        weightB = uint128(bound(uint256(weightB), 1, type(uint128).max));
        _setPool(primaryKey, a, weightA);
        _setPool(siblingKey, b, weightB);
        mark.setPrimary(primaryKey);
        mark.addPool(siblingKey);
        int256 result = mark.weightedTick();
        assertGe(result, a < b ? int256(a) : int256(b));
        assertLe(result, a > b ? int256(a) : int256(b));
        if (a == b) assertEq(result, a);
    }

    function test_removePreservesOtherSiblingAndPrimaryResetClearsAll() public {
        mark.setPrimary(primaryKey);
        mark.addPool(siblingKey);
        PoolKey memory other = siblingKey;
        other.fee = 500;
        _setPool(primaryKey, -100, 0);
        _setPool(siblingKey, 999, 10);
        _setPool(other, -123, 10);
        mark.addPool(other);
        mark.removePool(siblingKey);
        assertEq(mark.poolCount(), 1);
        assertEq(mark.weightedTick(), -123);
        vm.expectRevert(PerpMarkSource.NotFound.selector);
        mark.removePool(siblingKey);
        vm.expectRevert(PerpMarkSource.AlreadyAdded.selector);
        mark.addPool(other);
        mark.setPrimary(primaryKey);
        assertEq(mark.poolCount(), 0);
        assertEq(mark.weightedTick(), -100);
    }

    function test_transferredOwnerAloneCanConfigureAndCannotRenounce() public {
        address owner = address(0xA11CE);
        mark.transferOwnership(owner);
        vm.expectRevert(); mark.setPrimary(primaryKey);
        vm.prank(owner); mark.setPrimary(primaryKey);
        vm.expectRevert(); mark.removePool(siblingKey);
        vm.prank(owner); mark.addPool(siblingKey);
        vm.prank(owner); mark.removePool(siblingKey);
        vm.expectRevert(PerpMarkSource.OwnershipCannotBeRenounced.selector);
        vm.prank(owner); mark.renounceOwnership();
        assertEq(mark.owner(), owner);
    }
}
