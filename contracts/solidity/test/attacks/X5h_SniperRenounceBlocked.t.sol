// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchSniper} from "../../cauldron/LaunchSniper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract X5hToken {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
}

/// @notice X5h — REGRESSION: `renounceOwnership` would seal `sweep()`, the only
///         exit for value this contract holds.
///
///  LaunchSniper is `Ownable` and its entire owner surface is `launch()` (payable)
///  and `sweep(address)`. The contract takes ETH during a launch, holds the bought
///  token between the buy and the forward, and has an open `receive()` for the
///  gacha router's refund — and `sweep` is the ONLY way any of that leaves. OZ's
///  live `renounceOwnership()` therefore stranded every token and every wei the
///  contract ever held, permanently. Same load-bearing shape fixE hit on the gacha
///  router. Fixed with the MigrationVesting guard (20d6de2): a pure revert.
contract X5hSniperRenounceBlocked is Test {
    LaunchSniper sniper;
    X5hToken tok;
    address owner = address(this);
    address newOwner = address(0xB0B);
    address stranger = address(0xBADBAD);

    function setUp() public {
        sniper = new LaunchSniper(owner);
        tok = new X5hToken();
        vm.deal(address(this), 100 ether);
    }

    // ---- helpers ----------------------------------------------------------

    /// @dev Fund the sniper the way a real launch does: ETH via `receive()` and
    ///      tokens sitting in it between the buy and the forward.
    function _fundLikeALaunch() internal {
        (bool ok, ) = address(sniper).call{value: 5 ether}("");
        assertTrue(ok, "sniper accepts ETH");
        tok.mint(address(sniper), 1_000e18);
    }

    function _trySweep(address who, address asset) internal returns (bool ok) {
        vm.prank(who);
        try sniper.sweep(asset) { return true; } catch { return false; }
    }

    // ---- the guard --------------------------------------------------------

    function test_Fixed_RenounceRevertsAndOwnerSurvives() public {
        assertEq(sniper.owner(), owner, "owner set from the constructor");

        vm.expectRevert(LaunchSniper.OwnershipCannotBeRenounced.selector);
        sniper.renounceOwnership();
        assertEq(sniper.owner(), owner, "owner unchanged after the refused renounce");

        // a stranger gets the same refusal, not an access-control error - the
        // function is dead for everyone, not merely gated
        vm.prank(stranger);
        vm.expectRevert(LaunchSniper.OwnershipCannotBeRenounced.selector);
        sniper.renounceOwnership();
        assertEq(sniper.owner(), owner, "still owned");
    }

    function test_Fixed_TransferOwnershipStillWorks() public {
        sniper.transferOwnership(newOwner);
        assertEq(sniper.owner(), newOwner, "ownership is still transferable");

        // the guard travels with the contract, not the owner
        vm.prank(newOwner);
        vm.expectRevert(LaunchSniper.OwnershipCannotBeRenounced.selector);
        sniper.renounceOwnership();
        assertEq(sniper.owner(), newOwner, "new owner cannot renounce either");

        // and the old owner is genuinely out
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        sniper.transferOwnership(stranger);
    }

    function test_Fixed_SweepStillRescuesEthAndTokensAfterTheRefusedRenounce() public {
        _fundLikeALaunch();
        assertEq(address(sniper).balance, 5 ether, "sniper holds ETH");
        assertEq(tok.balanceOf(address(sniper)), 1_000e18, "sniper holds tokens");

        vm.expectRevert(LaunchSniper.OwnershipCannotBeRenounced.selector);
        sniper.renounceOwnership();

        // the exit is still open - this is the whole point of the guard
        uint256 ethBefore = owner.balance;
        assertTrue(_trySweep(owner, address(0)), "ETH sweep still works");
        assertEq(address(sniper).balance, 0, "ETH recovered");
        assertEq(owner.balance - ethBefore, 5 ether, "owner got it");

        assertTrue(_trySweep(owner, address(tok)), "token sweep still works");
        assertEq(tok.balanceOf(address(sniper)), 0, "tokens recovered");
        assertEq(tok.balanceOf(owner), 1_000e18, "owner got them");

        // still owner-only
        assertFalse(_trySweep(stranger, address(0)), "sweep is still onlyOwner");
    }

    receive() external payable {}
}
