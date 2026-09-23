// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {ReauditLocalManagers} from "../audit_reaudit/RotationTotalityLocal.t.sol";
import {R23SurtaxResponse} from "./R23_PolicyBoundaries.t.sol";

contract R23SurtaxHookFallback is ReauditLocalManagers {
    function _check(uint256 mode) internal {
        _boot(20 ether, 0);
        hook.setPolicies(address(new R23SurtaxResponse(mode)), address(0), address(0));
        vm.roll(block.number + 40);
        assertGt(_buy(0.01 ether, victim), 0, "faulty surtax policy must use built-in fallback");
    }
    function test_revertingPolicyPreservesFundedSwap() public { _check(0); }
    function test_emptyPolicyPreservesFundedSwap() public { _check(1); }
}
