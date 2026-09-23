// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {ReauditLocalManagers} from "../audit_reaudit/RotationTotalityLocal.t.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract R23ChurnLocal is ReauditLocalManagers {
    function test_fundedChurnPaysOutputAndSlippageFailureRollsBack() public {
        _boot(20 ether, 0);
        CauldronGachaRouter router = new CauldronGachaRouter(pm, address(hook), address(registry), address(this));
        hook.setOpener(address(router), true);
        vm.roll(block.number + 40);
        uint256 snap = vm.snapshotState();
        uint256 beforeToken = IERC20(token).balanceOf(victim);
        uint256 beforeEth = victim.balance;
        vm.prank(victim);
        router.playChurn{value: 0.01 ether}(0, 3, 1, 1);
        uint256 received = IERC20(token).balanceOf(victim) - beforeToken;
        assertGt(received, 0);
        assertEq(address(router).balance, 0, "no native residue");
        assertEq(IERC20(token).balanceOf(address(router)), 0, "no token residue");
        assertLe(beforeEth - victim.balance, 0.01 ether);

        assertTrue(vm.revertToState(snap));
        vm.expectRevert(CauldronGachaRouter.Slippage.selector);
        vm.prank(victim);
        router.playChurn{value: 0.01 ether}(0, 3, received + 1, 1);
        assertEq(IERC20(token).balanceOf(victim), beforeToken);
        assertEq(victim.balance, beforeEth);
        assertEq(address(router).balance, 0);
        assertEq(IERC20(token).balanceOf(address(router)), 0);
    }
}
