// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";

/// @dev Minimal vote source; this test never votes.
contract X2jVotes {
    function getVotes(address) external pure returns (uint256) { return 1; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1; }
}

/**
 * X2j — REGRESSION. `Ownable.renounceOwnership()` was live and unguarded on
 *       CauldronGovernor, whose owner is the only caller of `setRegistry` and
 *       `setBrewFee`. One transaction could dead-end both permanently: the
 *       governor could never be re-pointed at a new registry, and the brew fee
 *       would be frozen wherever it stood, with no recovery and no redeploy that
 *       keeps the stockpiled mandates.
 *
 * `CauldronBase.sol:417` already blocks this for its inheritors — the governor is
 * not one, so it carried the hole. Same fix shape fixer D used on MigrationVesting.
 */
contract X2j_GovernorRenounceBlocked is Test {
    CauldronGovernor internal gov;

    function setUp() public {
        gov = new CauldronGovernor(address(new X2jVotes()), 0);
    }

    function test_X2j_ownerCannotRenounceIntoADeadEnd() public {
        address before = gov.owner();
        assertEq(before, address(this), "precondition: this test owns the governor");

        vm.expectRevert(CauldronGovernor.OwnershipCannotBeRenounced.selector);
        gov.renounceOwnership();

        assertEq(gov.owner(), before, "FIXED: the owner slot is unchanged");

        // ...and the two controls it would have dead-ended still work.
        gov.setRegistry(address(0xBEEF));
        assertEq(gov.registry(), address(0xBEEF), "setRegistry still reachable");
    }

    /// @dev Handing the seat on is still available — that is the honest way to say
    ///      "nobody should hold this", and it is what the fix leaves open.
    function test_X2j_transferOwnershipIsUntouched() public {
        gov.transferOwnership(address(0xDEAD));
        assertEq(gov.owner(), address(0xDEAD), "transferOwnership still works");
    }
}
