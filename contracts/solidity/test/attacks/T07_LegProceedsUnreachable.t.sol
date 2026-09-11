// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

/**
 * T07 — FOREIGN LEG PROCEEDS ARE BOOKED WITH NO REACHABLE WAY OUT.
 *
 * `RedemptionExt.recoverLegs` unwinds every rotated leg of a dying generation.
 * A leg whose quote does not match the generation's quote cannot be counted
 * toward the rebirth's funding, so its proceeds are BOOKED instead:
 *
 *     } else if (q > 0) {
 *         legProceeds[l.quote] += q;              // RedemptionExt.sol:707
 *         emit LegProceedsBooked(gen, l.quote, q);
 *     }
 *
 * The facet ships exactly one way to move that balance out —
 * `sweepLegProceeds(address,address)` (RedemptionExt.sol:758, `onlyOwner`) —
 * and one way to read it, `legProceedsOf(address)` (RedemptionExt.sol:721).
 *
 * NEITHER HAS A DISPATCHER STUB, and `CauldronRegistry` has no `fallback`. The
 * facet is only ever reached through explicit forwarders, so both are dead: the
 * booked asset cannot be swept and the booking cannot even be read on-chain.
 *
 * This is the FOURTH instance of the defect class {F20_FacetReachability}
 * documents — and F20 itself enumerates only three selectors, so these two were
 * never classified either way. Found by diffing the facet's ABI against the
 * dispatcher's, rather than by reading the reachability test.
 *
 * IMPACT (Medium, not High): the assets sit in the registry's own custody and
 * are not lost to an attacker. `CauldronRegistry.emergencySweep` (:448) can
 * still move an arbitrary ERC20 out — but it is `onlyEmergency timelocked`
 * break-glass that sweeps the registry's ENTIRE balance of that token to the
 * emergency admin, not the owner-directed, amount-exact, policy-chosen transfer
 * `sweepLegProceeds` was written to be. The `legProceeds` ledger is also never
 * cleared by that route, so the accounting stays permanently stale.
 *
 * METHOD is {F20_FacetReachability}'s: `vm.etch` the registry's runtime code at
 * a blank address and call each selector raw. A ROUTED selector reaches
 * `_forwardToExt` and reverts `NotConfigured()` (4 bytes) on the zero facet
 * pointer; an UNROUTED one dies in dispatch with EMPTY return data. Return-data
 * length is an exact discriminator, with no fork and no wiring.
 *
 * Written to FAIL while the defect is present: it is the regression guard.
 */
contract T07_LegProceedsUnreachable is Test {
    address internal reg;

    bytes4 internal constant NOT_CONFIGURED = bytes4(keccak256("NotConfigured()"));

    function setUp() public {
        reg = makeAddr("registry");
        vm.etch(reg, vm.getDeployedCode("CauldronRegistry.sol:CauldronRegistry"));
    }

    /// @dev true = the selector is routable on the registry.
    function _routable(bytes memory callData) internal returns (bool) {
        (bool ok, bytes memory ret) = reg.call(callData);
        if (ok) return true;
        if (ret.length == 0) return false; // no stub, no fallback
        assertEq(bytes4(ret), NOT_CONFIGURED, "routed calls fail on the zero facet pointer");
        return true;
    }

    /// @notice The only exit for booked foreign leg proceeds must be reachable.
    function test_T07_SweepLegProceedsIsReachable() public {
        bool reached;
        bool routable = _routable(
            abi.encodeWithSignature("sweepLegProceeds(address,address)", address(1), address(2))
        );
        reached = true;
        assertTrue(
            routable,
            "sweepLegProceeds must be forwarded: it is the ONLY way to move booked leg proceeds"
        );
        assertTrue(reached, "test did not reach its assertion");
    }

    /// @notice `legProceedsOf` is knowingly left UNROUTED, and this pins that
    ///         decision so it is a choice rather than a second accident.
    ///
    ///         The registry has ~21 bytes of EIP-170 headroom after stubbing
    ///         `sweepLegProceeds`; a second stub does not fit. Of the two, the
    ///         one that MOVES the asset had to win — a read-only gap is
    ///         recoverable (the balance is observable from the
    ///         `LegProceedsBooked` / `LegProceedsSwept` events, and the facet
    ///         runs on the registry's own storage so the slot can be read
    ///         directly), whereas a stuck asset is not.
    ///
    ///         Flip this to `assertTrue` if headroom is ever reclaimed.
    function test_T07_LegProceedsOfIsKnowinglyUnrouted() public {
        bool reached;
        bool routable = _routable(abi.encodeWithSignature("legProceedsOf(address)", address(1)));
        reached = true;
        assertFalse(routable, "legProceedsOf became routable: update this pin and the comment");
        assertTrue(reached, "test did not reach its assertion");
    }

    /// @notice Control: the facet really does implement both, so this is a
    ///         dispatcher gap and not a missing feature. Proven against the
    ///         facet's own runtime code, where the same selectors DO dispatch
    ///         (they reach the body and revert on the blank storage / guard,
    ///         which is a non-empty revert — never the empty dispatch failure).
    function test_T07_ControlFacetImplementsBoth() public {
        bool reached;
        address ext = makeAddr("ext");
        vm.etch(ext, vm.getDeployedCode("RedemptionExt.sol:RedemptionExt"));

        (bool okSweep, bytes memory retSweep) =
            ext.call(abi.encodeWithSignature("sweepLegProceeds(address,address)", address(1), address(2)));
        (bool okView, bytes memory retView) =
            ext.call(abi.encodeWithSignature("legProceedsOf(address)", address(1)));

        reached = true;
        assertTrue(
            okSweep || retSweep.length > 0,
            "facet must dispatch sweepLegProceeds (empty revert = no such function)"
        );
        assertTrue(
            okView || retView.length > 0,
            "facet must dispatch legProceedsOf (empty revert = no such function)"
        );
        assertTrue(reached, "control did not reach its assertions");
    }
}
