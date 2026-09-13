// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpMarkSource} from "../../cauldron/PerpMarkSource.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * K3e — {PerpMarkSource.weightedTick} used to `return 0` when unarmed.
 *
 * Tick 0 is not "no answer"; it is a perfectly valid price of 1:1.
 * {PerpEngine._currentTick} (PerpEngine.sol:666-684) accepts ANY well-formed
 * 32-byte reply with no sanity check and marks the whole book against it, so an
 * unarmed source silently repriced every position to parity and drove
 * liquidations off a number nobody set.
 *
 * REGRESSION: it must fail CLOSED. Reverting is what makes the engine's
 * `staticcall` return `ok == false` and fall back to its OWN pool's slot0.
 */
contract K3e_UnarmedMarkTick is Test {
    PerpMarkSource src;

    function setUp() public {
        src = new PerpMarkSource(IPoolManager(address(0xBEEF)), address(this));
    }

    function test_FIXED_unarmedMarkSourceRefusesInsteadOfAnsweringParity() public {
        assertFalse(src.armed(), "positive control: the source starts unarmed");
        vm.expectRevert(PerpMarkSource.NotArmed.selector);
        src.weightedTick();
    }

    /// Positive control: the engine's own soft-fail contract is preserved — a
    /// raw staticcall to an unarmed source returns `false`, which is exactly the
    /// `ok` the engine tests before trusting the word.
    function test_FIXED_theEnginesStaticcallSeesAFailureNotATick() public {
        (bool ok, bytes memory ret) =
            address(src).staticcall(abi.encodeWithSelector(PerpMarkSource.weightedTick.selector));
        assertFalse(ok, "an unarmed source answers with a revert, so the engine falls back");
        assertEq(bytes4(ret), PerpMarkSource.NotArmed.selector, "and it says why");
    }
}
