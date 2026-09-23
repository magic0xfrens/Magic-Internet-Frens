// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {RotationLifecycleLocalTest} from "../audit_full_scope/RotationLifecycleLocal.t.sol";
import {IPositionManagerOps} from "../../cauldron/PoolOps.sol";

interface IR23OwnerOf {
    function ownerOf(uint256 id) external view returns (address);
}

/// V2 controller stand-in: accepts the handed-off native balance.
contract R23Successor {
    receive() external payable {}
}

/// Actual registry/facet, real local V4 managers, a funded native launch and a
/// voted ERC20 rotation leg. The emergency admin performs the documented handoff.
/// No target storage writes, no impersonated registry or manager callbacks.
contract R23SuccessorLegHandoff is RotationLifecycleLocalTest {
    function test_successorHandoffMustNotStrandRotatedLeg() public {
        _approveRotation(address(usd));
        (, uint256 leg) = _move(0);
        IPositionManagerOps pmo = IPositionManagerOps(posm);
        uint128 legLiquidity = pmo.getPositionLiquidity(leg);
        assertGt(legLiquidity, 0, "rotation leg funded");
        assertEq(registry.legCount(gen), 1);

        // Control: a live generation that has NOT been handed off stays untouchable.
        vm.expectRevert(bytes4(keccak256("CannotClaimCurrentGen()")));
        registry.recoverLegs(gen);

        R23Successor successor = new R23Successor();
        registry.setSuccessor(address(successor));
        registry.armEmergency();
        registry.migrateToSuccessor();

        uint256 active = registry.generationPositionId(gen);
        assertEq(IR23OwnerOf(posm).ownerOf(active), address(successor), "live active NFT handed off");
        assertEq(IR23OwnerOf(posm).ownerOf(leg), address(registry), "migrateToSuccessor alone leaves the leg");

        // Anyone may complete the handoff; the destination is the recorded successor.
        vm.prank(address(0xBEEF));
        (bool ok, bytes memory err) = address(registry).call(abi.encodeWithSignature("recoverLegs(uint256)", gen));
        console2.log("recoverLegs(current gen) after handoff ok", ok);
        if (!ok) console2.logBytes(err);

        address legOwner = IR23OwnerOf(posm).ownerOf(leg);
        uint128 after_ = pmo.getPositionLiquidity(leg);
        console2.log("leg owned by successor", legOwner == address(successor));
        console2.log("leg liquidity after handoff", uint256(after_));
        assertTrue(legOwner == address(successor) || after_ == 0, "handoff must not strand the rotated treasury leg");
        assertEq(legOwner, address(successor), "leg follows the primary to the successor");
        assertEq(after_, legLiquidity, "ownership moves; liquidity is not unwound");
        assertEq(registry.legCount(gen), 0, "leg no longer tracked by the old registry");

        // Idempotent afterwards: nothing left to move, no revert.
        registry.recoverLegs(gen);
        assertEq(IR23OwnerOf(posm).ownerOf(leg), address(successor));
    }
}
