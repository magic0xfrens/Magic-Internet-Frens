// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";

/// @dev The hook's constructor only stores the manager and validates its own
///      mined address, so a bare stub is enough to deploy the real bytecode.
contract X1dPoolManagerStub {
    receive() external payable {}
}

/**
 * @title X1d — the hook's owner could renounce into a dead end
 *
 *  {CauldronHook} inherits OpenZeppelin's {Ownable} DIRECTLY (CauldronHook.sol:117),
 *  not {CauldronBase}, so the renounce guard at CauldronBase.sol:417 never
 *  covered it and `renounceOwnership()` shipped live. The owner is the only
 *  party that can wire this contract — registry, legacy buyback, surtax policy,
 *  fee router, perp engine, seeder, every threshold — and it sits in the swap
 *  path of every trade. A renounce would freeze all of that permanently, with no
 *  recovery short of redeploying the pool at a new mined address.
 */
contract X1dHookRenounceBlocked is Test {
    CauldronHook internal hook;

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    function setUp() public {
        X1dPoolManagerStub pm = new X1dPoolManagerStub();
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");
    }

    function test_X1d_ownerCannotRenounceIntoADeadEnd() public {
        address ownerBefore = hook.owner();
        assertEq(ownerBefore, address(this), "premise: this test is the owner");

        vm.expectRevert(CauldronHook.RenounceDisabled.selector);
        hook.renounceOwnership();

        emit log_named_address("owner after the refused renounce", hook.owner());
        assertEq(hook.owner(), ownerBefore, "owner is unchanged");

        // The door that leads SOMEWHERE stays open: handing the hook to a
        // governance timelock is still a single call.
        hook.transferOwnership(address(0xBEEF));
        assertEq(hook.owner(), address(0xBEEF), "transferOwnership still works");
    }

    function test_X1d_aStrangerStillCannotRenounce() public {
        address ownerBefore = hook.owner();

        vm.prank(address(0xBAD));
        vm.expectRevert(); // onlyOwner runs first: OwnableUnauthorizedAccount
        hook.renounceOwnership();

        assertEq(hook.owner(), ownerBefore, "owner is unchanged");
    }
}
