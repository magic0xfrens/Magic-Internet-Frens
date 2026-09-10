// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

/**
 * F-20 — FACET REACHABILITY (dispatcher conformance).
 *
 * `CauldronRegistry` keeps its OG-redemption and rotation ops in the
 * {RedemptionExt} facet and reaches them through EXPLICIT thin forwarders that
 * DELEGATECALL the facet (`_forwardToExt`, CauldronRegistry.sol:1368). The
 * registry declares a payable `receive()` (CauldronRegistry.sol:508) and NO
 * `fallback()`, so a facet function without a stub is UNREACHABLE — the call
 * dies as "unrecognized function selector ... which has no fallback function",
 * which is not a named protocol error and so is not diagnosable from the revert.
 *
 * This is a recurring defect class in this tree. It has now appeared three times:
 *   1. `setRotationWiring` — forwarder present, facet body missing
 *      (recorded at RedemptionExt.sol:215-227).
 *   2. `floorClaimableNow` / `legCount` / `legAt` — facet bodies present,
 *      forwarders missing. Caught by F04 and fixed at CauldronRegistry.sol:1344.
 *   3. `rotateSliceFrom` — facet body present, forwarder still missing. Asserted
 *      below.
 *
 * METHOD. `vm.etch` the registry's runtime code at a fresh address and call each
 * selector raw. The two outcomes are distinguishable with no fork and no wiring:
 *
 *   • ROUTED   — dispatch finds the stub, runs `_forwardToExt`, and reverts
 *                `NotConfigured()` because `redemptionExt` is zero in the etched
 *                (blank) storage. Revert data is the 4-byte error selector.
 *   • UNROUTED — dispatch finds nothing and there is no fallback, so the EVM
 *                reverts with EMPTY return data.
 *
 * Return-data length is therefore an exact discriminator for routability.
 */
contract F20_FacetReachability is Test {
    address internal reg;

    /// @dev `NotConfigured()` — the error `_forwardToExt` raises on a zero facet
    ///      pointer (CauldronRegistry.sol:1370). Its presence proves dispatch
    ///      reached the stub.
    bytes4 internal constant NOT_CONFIGURED = bytes4(keccak256("NotConfigured()"));

    function setUp() public {
        reg = makeAddr("registry");
        vm.etch(reg, vm.getDeployedCode("CauldronRegistry.sol:CauldronRegistry"));
    }

    /// @dev true = the selector is routable on the registry.
    function _routable(bytes memory callData) internal returns (bool) {
        (bool ok, bytes memory ret) = reg.call(callData);
        if (ok) return true; // dispatched and returned
        if (ret.length == 0) return false; // no stub, no fallback
        // Reached a stub and bubbled a real error.
        assertEq(bytes4(ret), NOT_CONFIGURED, "routed calls fail on the zero facet pointer");
        return true;
    }

    /// @dev A rotation route tuple (`PoolKey`), shaped for the rotate selectors.
    function _key() internal pure returns (address, address, uint24, int24, address) {
        return (address(0), address(0), uint24(0), int24(0), address(0));
    }

    // ── CONTROL ──────────────────────────────────────────────────────────────

    /// @notice The forwarders that exist really do route, so a `false` below is
    ///         a statement about the registry and not about this harness.
    function test_F20_KnownForwardersRoute() public {
        (address c0, address c1, uint24 f, int24 t, address h) = _key();
        assertTrue(_routable(abi.encodeWithSignature("redeemOgFren(uint256)", 1)), "Registry:1309");
        assertTrue(_routable(abi.encodeWithSignature("buyTreasuryOgFren(uint256)", 1)), "Registry:1315");
        assertTrue(_routable(abi.encodeWithSignature("donateToReserve(uint256)", 1)), "Registry:1321");
        assertTrue(_routable(abi.encodeWithSignature("materializeLegacyReserve()")), "Registry:1327");
        assertTrue(_routable(abi.encodeWithSignature("setRotationWiring(address,address)", address(1), address(2))), "Registry:242");
        assertTrue(
            _routable(abi.encodeWithSignature(
                "rotateSlice(uint16,uint256,(address,address,uint24,int24,address))",
                uint16(100), uint256(0), c0, c1, f, t, h
            )),
            "Registry:235"
        );
    }

    /// @notice The three views fixed after F04 caught them now route.
    ///         Regression guard: they must never silently un-route again.
    function test_F20_ViewsFixedAfterF04StillRoute() public {
        assertTrue(_routable(abi.encodeWithSignature("floorClaimableNow()")), "Registry:1344");
        assertTrue(_routable(abi.encodeWithSignature("legCount(uint256)", 1)), "Registry:1349");
        assertTrue(_routable(abi.encodeWithSignature("legAt(uint256,uint256)", 1, 0)), "Registry:1354");
    }

    // ── THE OPEN DEFECT ──────────────────────────────────────────────────────

    /// @notice `rotateSliceFrom` (RedemptionExt.sol:266) is the multi-leg
    ///         rotation entrypoint. It has NO registry forwarder, so it is
    ///         unreachable from every caller.
    ///
    ///  IMPACT. It is the ONLY write the shipped treasury UI issues for a
    ///  rotation — `src/hooks/useTreasuryRotation.ts:290` calls
    ///  `functionName: "rotateSliceFrom"` at `CAULDRON.registry` for EVERY
    ///  slice, including the default `fromLeg = 0`. So the rotate button reverts
    ///  on every press, whichever leg is chosen.
    ///
    ///  Only the 3-arg `rotateSlice` routes, and it hard-codes `fromLeg = 0`
    ///  (RedemptionExt.sol:260). Rotating OUT of an already-rotated leg — the
    ///  merging and rebalancing that RedemptionExt.sol:307-318 calls the entire
    ///  reason `fromLeg` exists — has no reachable path at all.
    ///
    ///  This test is written to FAIL while the defect is present. It is the
    ///  regression guard for the fix.
    function test_F20_RotateSliceFromIsReachable() public {
        (address c0, address c1, uint24 f, int24 t, address h) = _key();
        assertTrue(
            _routable(abi.encodeWithSignature(
                "rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))",
                uint8(1), uint16(100), uint256(0), c0, c1, f, t, h
            )),
            "rotateSliceFrom must be forwarded: the treasury UI calls it for every slice"
        );
    }

    /// @notice `completeRotation` (RedemptionExt.sol:477) is also unrouted, but
    ///         unlike `rotateSliceFrom` that is CORRECT: it is superseded dead
    ///         code. `rotateSlice` performs removal, swap and redeploy in one
    ///         call, so the begin/complete pair it belonged to has no caller —
    ///         `useTreasuryRotation.ts:12-20` reaches the same conclusion.
    ///         Pinned here so the classification is asserted, not assumed; the
    ///         cleanup is to DELETE the function, which flips this test.
    function test_F20_CompleteRotationIsUnroutedDeadCode() public {
        assertFalse(
            _routable(abi.encodeWithSignature("completeRotation(address,uint256,uint256)", address(0), 0, 0)),
            "completeRotation is dead code pending deletion"
        );
    }

    /// @notice `recoverLegs` (RedemptionExt.sol:571) is unrouted BY DESIGN — the
    ///         registry invokes it internally by explicit selector during
    ///         relaunch (CauldronRegistry.sol:1490 via the `RECOVER_LEGS`
    ///         constant at :60), and it must not be externally callable.
    ///         Asserted so a future "fix all the unrouted selectors" pass does
    ///         not wrongly expose it.
    function test_F20_RecoverLegsIsIntentionallyInternal() public {
        assertFalse(
            _routable(abi.encodeWithSignature("recoverLegs(uint256)", 1)),
            "recoverLegs must stay internal-only"
        );
    }
}
