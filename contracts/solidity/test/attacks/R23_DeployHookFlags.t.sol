// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployCauldron} from "../../deploy/DeployCauldron.s.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract R23DeployFlagAccess is DeployCauldron {
    function flags() external pure returns (uint160) { return _hookFlags(); }
}

contract R23DeployHookFlags is Test {
    IPoolManager constant MANAGER = IPoolManager(address(0x1234));

    function _mine(uint160 flags) internal view returns (address predicted, bytes32 salt) {
        return HookMiner.find(address(this), flags, type(CauldronHook).creationCode,
            abi.encode(MANAGER, 1 ether, address(0), address(this), address(this)));
    }

    function test_originalScriptFlagsRejectActualConstructor() public {
        uint160 oldFlags = Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG
            | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
        (address predicted, bytes32 salt) = _mine(oldFlags);
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, predicted));
        new CauldronHook{salt: salt}(MANAGER, 1 ether, address(0), address(this), address(this));
    }

    function test_scriptFlagsDeployActualHookWithExplicitOwner() public {
        uint160 flags = (new R23DeployFlagAccess()).flags();
        (address predicted, bytes32 salt) = _mine(flags);
        CauldronHook hook = new CauldronHook{salt: salt}(
            MANAGER, 1 ether, address(0), address(this), address(this));
        assertEq(address(hook), predicted);
        assertEq(hook.owner(), address(this));
        assertEq(address(hook.poolManager()), address(MANAGER));
        assertEq(uint160(address(hook)) & Hooks.ALL_HOOK_MASK, flags);
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.beforeSwapReturnDelta);
    }
}
