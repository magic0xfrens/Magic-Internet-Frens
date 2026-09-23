// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReauditLocalManagers} from "../audit_reaudit/RotationTotalityLocal.t.sol";

contract R23InvalidFeeRouter {
    uint256 immutable mode;
    constructor(uint256 m) { mode = m; }
    function route(uint256, address, address, uint256, uint256)
        external view returns (uint256, uint256, uint256)
    {
        if (mode == 0) revert("dependency unavailable");
        if (mode == 1) { assembly ("memory-safe") { return(0, 0) } }
        return (type(uint256).max, 1, 0);
    }
}

contract R23FeeRouterFallback is ReauditLocalManagers {
    function _check(uint256 mode) internal {
        _boot(20 ether, 0);
        hook.setFeeRouter(address(new R23InvalidFeeRouter(mode)));
        vm.roll(block.number + 40);
        assertGt(_buy(0.01 ether, victim), 0, "invalid router should fall back to built-in split");
    }
    function test_revertingRouterFallsBack() public { _check(0); }
    function test_emptyRouterFallsBack() public { _check(1); }
    function test_overflowingRouterFallsBack() public { _check(2); }
}
