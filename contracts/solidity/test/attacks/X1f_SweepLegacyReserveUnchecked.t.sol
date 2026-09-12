// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";

contract X1fPoolManagerStub { receive() external payable {} }

/// @notice A token that reports failure by RETURNING FALSE rather than reverting
///         — the USDT / tokenised-equity shape.
contract X1fFalseToken {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address, uint256) external pure returns (bool) { return false; }
}

/// @notice The same token, behaving.
contract X1fGoodToken {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
}

/**
 * @title X1f — the legacy-reserve sweep debited its counter, then transferred blind
 *
 *  `CauldronHook.sweepLegacyReserve` debits `legacyOwedToReserve` and THEN moved
 *  the tokens with a bare `IERC20.transfer`, unchecked. The registry credits the
 *  live collection's floor with exactly the `amt` this function returns, so a
 *  token that returns false instead of reverting zeroed the counter, reported a
 *  sweep that never happened, and had the ledger credit a reserve that received
 *  nothing — breaking the "a ledger credit never out-runs the reserve" property
 *  this function's own comment says it exists to preserve. And because the
 *  counter was already gone, no later sweep could recover the tokens.
 */
contract X1fSweepLegacyReserveUnchecked is Test {
    CauldronHook internal hook;

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    /// @dev Pinned by test/final/F03_FinalInvariants.t.sol:34. Asserted below
    ///      rather than trusted, so a layout change fails loudly here.
    uint256 internal constant SLOT_LEGACY_OWED = 27;
    uint256 internal constant OWED = 100e18;

    function setUp() public {
        X1fPoolManagerStub pm = new X1fPoolManagerStub();
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");

        // This test is the legacy registry, the only caller of the sweep.
        hook.setLegacyBuyback(address(this), 500, 0.02 ether);

        vm.store(address(hook), bytes32(SLOT_LEGACY_OWED), bytes32(OWED));
        assertEq(hook.legacyOwedToReserve(), OWED, "premise: SLOT_LEGACY_OWED still holds the counter");
    }

    function test_X1f_falseReturningTokenCannotZeroTheCounterWithoutMovingAnything() public {
        X1fFalseToken bad = new X1fFalseToken();
        bad.mint(address(hook), OWED);

        vm.expectRevert(CauldronHook.SendFailed.selector);
        hook.sweepLegacyReserve(address(bad), address(this));

        emit log_named_uint("counter after the refused sweep", hook.legacyOwedToReserve());
        emit log_named_uint("tokens still on the hook       ", bad.balanceOf(address(hook)));

        assertEq(hook.legacyOwedToReserve(), OWED, "the debit rolled back, so a later sweep can still claim it");
        assertEq(bad.balanceOf(address(hook)), OWED, "the tokens never moved");
        assertEq(bad.balanceOf(address(this)), 0, "and the registry was not told they had");
    }

    /// @notice The check must not break the honest path.
    function test_X1f_wellBehavedTokenStillSweepsAndDebits() public {
        X1fGoodToken good = new X1fGoodToken();
        good.mint(address(hook), OWED);

        uint256 amt = hook.sweepLegacyReserve(address(good), address(this));

        emit log_named_uint("swept", amt);
        assertEq(amt, OWED, "the whole owed amount is reported");
        assertEq(good.balanceOf(address(this)), OWED, "and really arrives");
        assertEq(hook.legacyOwedToReserve(), 0, "counter debited exactly once");
    }

    /// @notice Partial cover is unchanged (audit F-03): debit only what moved.
    function test_X1f_partialBalanceStillDebitsOnlyWhatMoved() public {
        X1fGoodToken good = new X1fGoodToken();
        good.mint(address(hook), OWED / 4);

        uint256 amt = hook.sweepLegacyReserve(address(good), address(this));

        assertEq(amt, OWED / 4, "clamped to the balance");
        assertEq(hook.legacyOwedToReserve(), OWED - OWED / 4, "remainder stays claimable");
    }

    receive() external payable {}
}
