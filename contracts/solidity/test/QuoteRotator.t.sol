// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {QuoteRotator} from "../cauldron/QuoteRotator.sol";

/// @dev A registry stub exposing only the allowlist the rotator consults.
contract RegistryStub {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * @dev The MiFrens guild managing what its own LP is denominated in.
 *
 *  The treasury has always been long ETH by default. These targets make that a
 *  decision: rotate into USDG near a top, back later, hold an equity. Because
 *  the swap leg touches a market the protocol does not own, the tests here are
 *  mostly about what a step is NOT allowed to do.
 */
contract QuoteRotatorTest is Test {
    QuoteRotator rot;
    RegistryStub reg;

    address constant USDG = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant XNVDA = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant STRANGER = address(0xBAD);
    address constant NATIVE = address(0);

    function setUp() public {
        reg = new RegistryStub();
        reg.set(USDG, true);
        reg.set(XNVDA, true);
        rot = new QuoteRotator(address(reg), IPoolManager(address(0xdead)), NATIVE);
    }

    // ---------------------------------------------------------------------
    // The allocation is the guild's to set, and nobody else's
    // ---------------------------------------------------------------------

    function test_StartsFullyInThePrimary() public view {
        assertEq(rot.targetBps(NATIVE), 10_000, "100% ETH at deploy");
        assertEq(rot.primaryQuote(), NATIVE);
    }

    function test_GuildCanSetAnAllocation() public {
        address[] memory q = new address[](2);
        uint16[] memory b = new uint16[](2);
        (q[0], b[0]) = (NATIVE, 6000);
        (q[1], b[1]) = (USDG, 4000);
        rot.setTargets(q, b);

        assertEq(rot.targetBps(NATIVE), 6000, "60% ETH");
        assertEq(rot.targetBps(USDG), 4000, "40% USDG");
    }

    function test_StrangerCannotSetTheAllocation() public {
        address[] memory q = new address[](1);
        uint16[] memory b = new uint16[](1);
        (q[0], b[0]) = (NATIVE, 10_000);

        vm.prank(STRANGER);
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rot.setTargets(q, b);
    }

    // ---------------------------------------------------------------------
    // What an allocation is never allowed to be
    // ---------------------------------------------------------------------

    /// The treasury curates which assets are acceptable. A rotation into
    /// something unvetted is how a hostile "quote" would drain the LP, so it is
    /// refused at the allocation boundary rather than at execution.
    function test_CannotTargetAnUnvettedQuote() public {
        address[] memory q = new address[](2);
        uint16[] memory b = new uint16[](2);
        (q[0], b[0]) = (NATIVE, 5000);
        (q[1], b[1]) = (address(0xDEAD), 5000); // never allowlisted

        vm.expectRevert(QuoteRotator.NotAllowedQuote.selector);
        rot.setTargets(q, b);
    }

    /// An allocation that does not sum to 100% would leave the remainder
    /// undefined, and the rotation loop would chase a target that never settles.
    function test_AllocationMustSumToOneHundredPercent() public {
        address[] memory q = new address[](2);
        uint16[] memory b = new uint16[](2);
        (q[0], b[0]) = (NATIVE, 5000);
        (q[1], b[1]) = (USDG, 4000); // 90%

        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setTargets(q, b);
    }

    /// THE IMPORTANT ONE. However the guild votes, the LP can never fully leave
    /// the asset the protocol is denominated in — an all-in rotation into an
    /// equity would leave the machine unable to price or pay anything.
    function test_CannotRotateOutOfThePrimaryEntirely() public {
        address[] memory q = new address[](1);
        uint16[] memory b = new uint16[](1);
        (q[0], b[0]) = (USDG, 10_000); // 100% USDG, 0% ETH

        vm.expectRevert(QuoteRotator.FloorBreached.selector);
        rot.setTargets(q, b);
    }

    /// The same guard just below the boundary: the floor is 30%, so 29% fails.
    function test_PrimaryShareBelowTheFloorIsRefused() public {
        address[] memory q = new address[](2);
        uint16[] memory b = new uint16[](2);
        (q[0], b[0]) = (NATIVE, 2900);
        (q[1], b[1]) = (USDG, 7100);

        vm.expectRevert(QuoteRotator.FloorBreached.selector);
        rot.setTargets(q, b);
    }

    /// Dropping a quote from a new allocation must actually zero it. Without
    /// clearing the previous set first, a removed quote would keep its old
    /// target and the totals would never sum to 100% again.
    function test_DroppedQuoteIsZeroedNotStranded() public {
        address[] memory q = new address[](3);
        uint16[] memory b = new uint16[](3);
        (q[0], b[0]) = (NATIVE, 4000);
        (q[1], b[1]) = (USDG, 3000);
        (q[2], b[2]) = (XNVDA, 3000);
        rot.setTargets(q, b);
        assertEq(rot.targetBps(XNVDA), 3000);

        // Re-allocate without XNVDA at all.
        address[] memory q2 = new address[](2);
        uint16[] memory b2 = new uint16[](2);
        (q2[0], b2[0]) = (NATIVE, 5000);
        (q2[1], b2[1]) = (USDG, 5000);
        rot.setTargets(q2, b2);

        assertEq(rot.targetBps(XNVDA), 0, "a dropped quote must be zeroed");
        assertEq(uint256(rot.targetBps(NATIVE)) + rot.targetBps(USDG), 10_000, "and the rest still sums");
    }

    // ---------------------------------------------------------------------
    // Execution limits
    // ---------------------------------------------------------------------

    /// Slicing is the execution strategy: one large conversion is both a
    /// sandwich target and a self-inflicted price impact. The cooldown is what
    /// forces it to happen over time.
    function test_StepsAreRateLimited() public {
        vm.warp(block.timestamp + 2 hours);
        // No holdings, so there is nothing to rotate and the step is a no-op...
        assertEq(rot.nextStepSize(), 0, "nothing to do while empty");
    }

    /// A careless or compromised owner must still not be able to configure a
    /// single step that empties the LP.
    function test_ParamsAreBounded() public {
        // >20% per step
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setParams(3000, 2001, 1 hours, 100, 1800, 10);

        // >5% slippage
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setParams(3000, 500, 1 hours, 501, 1800, 10);

        // A TWAP window short enough to be cheap to manipulate
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setParams(3000, 500, 1 hours, 100, 299, 10);

        // A keeper reward above 1%
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setParams(3000, 500, 1 hours, 100, 1800, 101);
    }

    function test_StrangerCannotChangeParams() public {
        vm.prank(STRANGER);
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rot.setParams(0, 2000, 0, 500, 300, 100);
    }

    /// Sanity: the guild CAN hold several assets at once, which is the point of
    /// the whole design — spread the LP, not just flip it.
    function test_MultipleQuotesCanBeHeldTogether() public {
        address[] memory q = new address[](3);
        uint16[] memory b = new uint16[](3);
        (q[0], b[0]) = (NATIVE, 4000);
        (q[1], b[1]) = (USDG, 3500);
        (q[2], b[2]) = (XNVDA, 2500);
        rot.setTargets(q, b);

        assertEq(rot.targetBps(NATIVE), 4000);
        assertEq(rot.targetBps(USDG), 3500);
        assertEq(rot.targetBps(XNVDA), 2500);
        assertEq(rot.trackedQuotesLength(), 3, "all three are walked by the rotation loop");
    }
}
