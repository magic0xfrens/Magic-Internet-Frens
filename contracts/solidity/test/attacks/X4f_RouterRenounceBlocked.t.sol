// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";

contract X4fToken {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }
}

/**
 * X4f REGRESSION — `Ownable.renounceOwnership()` was live and unguarded on
 *       CauldronGachaRouter. Every owner-gated function on this router is a
 *       recovery or a repair — {rescueETH} and {rescueToken} are the only exits
 *       for value stranded in it — so renouncing sealed the stranded value in
 *       forever. Same class fixD closed on MigrationVesting (20d6de2).
 */
contract X4f_RouterRenounceBlocked is Test {
    CauldronGachaRouter internal router;
    X4fToken internal usdg;

    address internal constant OWNER = address(0xB0B);
    address internal constant STRANGER = address(0x5747);

    function setUp() public {
        usdg = new X4fToken();
        router = new CauldronGachaRouter(
            IPoolManager(address(0xBEEF)), address(0xDEAD), address(0xFEED), OWNER
        );
    }

    function test_renounceOwnership_reverts_and_the_rescue_paths_survive() public {
        assertEq(router.owner(), OWNER, "owner is set at construction");

        // The owner cannot renounce into a dead end.
        vm.prank(OWNER);
        vm.expectRevert(CauldronGachaRouter.OwnershipCannotBeRenounced.selector);
        router.renounceOwnership();
        assertEq(router.owner(), OWNER, "owner unchanged after the blocked renounce");

        // Neither can a stranger (Ownable's own gate, still intact).
        vm.prank(STRANGER);
        vm.expectRevert();
        router.renounceOwnership();
        assertEq(router.owner(), OWNER, "owner unchanged after a stranger tries");

        // The exits for stranded value still work afterwards.
        usdg.mint(address(router), 500e6);
        vm.prank(OWNER);
        router.rescueToken(address(usdg), address(this), 500e6);
        assertEq(usdg.balanceOf(address(this)), 500e6, "rescueToken still works");
        assertEq(usdg.balanceOf(address(router)), 0, "no ERC20 left stranded");

        vm.deal(address(router), 1 ether);
        uint256 before = address(this).balance;
        vm.prank(OWNER);
        router.rescueETH(address(this), 1 ether);
        assertEq(address(this).balance, before + 1 ether, "rescueETH still works");
        assertEq(address(router).balance, 0, "no ETH left stranded");

        emit log_named_address("owner after a blocked renounce", router.owner());
    }

    /// Ownership can still be HANDED OVER — blocking renounce must not freeze
    /// the owner in place, only stop it becoming nobody.
    function test_ownership_can_still_be_transferred() public {
        vm.prank(OWNER);
        router.transferOwnership(STRANGER);
        assertEq(router.owner(), STRANGER, "transferOwnership is unaffected");

        vm.prank(STRANGER);
        vm.expectRevert(CauldronGachaRouter.OwnershipCannotBeRenounced.selector);
        router.renounceOwnership();
        assertEq(router.owner(), STRANGER, "the new owner cannot renounce either");
    }

    receive() external payable {}
}
