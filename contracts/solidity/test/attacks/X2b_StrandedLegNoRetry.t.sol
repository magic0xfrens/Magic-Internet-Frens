// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

/**
 * X2b — a rotated treasury leg that fails to unwind during relaunch can NEVER be
 *       retried, despite the code promising exactly that.
 *
 * RedemptionExt.recoverLegs (RedemptionExt.sol:699) swallows a per-leg failure:
 *      } catch {
 *          // Left in place on purpose — see the note above.
 *      }
 * and its header (RedemptionExt.sol:690, :697) promises
 *      "safe to call directly afterwards for a generation whose rebirth predates this"
 *      "A failed leg stays recorded, so it can be retried once whatever broke is fixed."
 *
 * Neither is true:
 *   • CauldronRegistry has NO stub for `recoverLegs(uint256)` and NO fallback
 *     (CauldronRegistry.sol:1408). The only caller is the compiler-built selector
 *     at CauldronRegistry.sol:1607, inside the private `_removeLiquidity(gen)`,
 *     which relaunch runs exactly ONCE per generation.
 *   • Calling the FACET directly does not revert — it runs against the facet's own
 *     (permanently empty) storage and returns (0,0). The operator's "retry"
 *     reports SUCCESS and recovers nothing.
 *
 * Method mirrors test/functional/F20: etch runtime code, call the raw selector,
 * and use return-data length as the routability discriminator.
 */
contract X2b_StrandedLegNoRetry is Test {
    address internal reg;
    address internal ext;

    /// @dev `NotConfigured()` — what a routed forwarder raises on a zero facet ptr.
    bytes4 internal constant NOT_CONFIGURED = bytes4(keccak256("NotConfigured()"));

    function setUp() public {
        reg = makeAddr("registry");
        vm.etch(reg, vm.getDeployedCode("CauldronRegistry.sol:CauldronRegistry"));
        ext = makeAddr("facet");
        vm.etch(ext, vm.getDeployedCode("RedemptionExt.sol:RedemptionExt"));
    }

    /// @dev true = the registry dispatches this selector at all.
    function _routable(bytes memory cd) internal returns (bool) {
        (bool ok, bytes memory ret) = reg.call(cd);
        if (ok) return true;
        if (ret.length == 0) return false;            // no stub, no fallback
        assertEq(bytes4(ret), NOT_CONFIGURED, "a routed call fails on the zero facet pointer");
        return true;
    }

    /// @dev Call `recoverLegs(gen)` straight on the facet. Returns (succeeded, quoteOut, tokenOut).
    function _facetDirect(uint256 gen) internal returns (bool ok, uint256 q, uint256 t) {
        bytes memory ret;
        (ok, ret) = ext.call(abi.encodeWithSignature("recoverLegs(uint256)", gen));
        if (ok && ret.length >= 64) (q, t) = abi.decode(ret, (uint256, uint256));
    }

    // ── CONTROL: the harness can tell routed from unrouted ───────────────────

    function test_X2b_control_neighbouringLegSelectorsAreRouted() public {
        assertTrue(_routable(abi.encodeWithSignature("legCount(uint256)", 1)), "Registry:1423");
        assertTrue(_routable(abi.encodeWithSignature("legAt(uint256,uint256)", 1, 0)), "Registry:1428");
        assertTrue(
            _routable(abi.encodeWithSignature("sweepLegProceeds(address,address)", address(1), address(2))),
            "Registry:282"
        );
    }

    // ── THE FINDING ──────────────────────────────────────────────────────────

    function test_X2b_recoverLegsRetryIsReachableAndGated() public {
        bool viaRegistry = _routable(abi.encodeWithSignature("recoverLegs(uint256)", 1));
        (bool facetOk,,) = _facetDirect(1);

        assertTrue(viaRegistry, "FIXED: registry.recoverLegs(gen) now routes to the facet");
        // (`legProceedsOf` stays deliberately unrouted - see T07_LegProceedsUnreachable,
        //  which asserts that as an accepted property. `sweepLegProceeds` is the
        //  routed half and moves the value.)

        // The facet-direct call no longer reports a silent success against its own
        // empty storage: `currentGeneration` is 0 there, so the past-generations
        // gate refuses instead of returning (0, 0) and looking like a retry that ran.
        assertFalse(facetOk, "FIXED: the facet-direct call refuses rather than no-opping");
    }

    /// @dev The ungated teardown entry must stay unreachable from outside. Its access
    ///      control IS the absence of a forwarder, so this is the test that enforces
    ///      it — adding a stub for it would be a privilege escalation, not a fix.
    function test_X2b_teardownEntryHasNoForwarderOnPurpose() public {
        assertFalse(
            _routable(abi.encodeWithSignature("recoverLegsAtTeardown(uint256)", 1)),
            "recoverLegsAtTeardown is reachable ONLY by the registry's internal delegatecall"
        );
    }

    /// @dev And the dead two-step rotation entry is gone from the facet entirely.
    function test_X2b_completeRotationIsRemoved() public {
        (bool ok, bytes memory ret) = ext.call(
            abi.encodeWithSignature("completeRotation(address,uint256,uint256)", address(1), 1, 1)
        );
        assertFalse(ok, "completeRotation no longer exists on the facet");
        assertEq(ret.length, 0, "and there is no fallback to catch it");
    }
}
