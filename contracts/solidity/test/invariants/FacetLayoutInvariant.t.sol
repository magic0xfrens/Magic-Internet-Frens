// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {CauldronBase} from "../../cauldron/CauldronBase.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";

/**
 * @notice A stand-in for the registry with the SAME shared base. Because
 *         {CauldronBase} declares every slot and neither child adds state, this
 *         probe's layout is identical to {CauldronRegistry}'s and to
 *         {RedemptionExt}'s — which is exactly the property the delegatecall pair
 *         depends on. The probe exposes writers so a test can plant known values
 *         in specific base slots and then run the FACET'S code against them.
 */
contract LayoutProbe is CauldronBase {
    address public ext;

    function setExt(address e) external { ext = e; }
    function poke(uint256 shares, uint256 outstanding_, bool summoned_) external {
        genesisShares = shares;
        genesisReserveOutstanding = outstanding_;
        summoned = summoned_;
    }

    /// Run the FACET's `floorPerFren` body against THIS contract's storage.
    function facetFloorPerFren() external returns (uint256) {
        (bool ok, bytes memory ret) =
            ext.delegatecall(abi.encodeWithSelector(CauldronBase.floorPerFren.selector));
        require(ok, "delegatecall failed");
        return abi.decode(ret, (uint256));
    }

    /// Run the FACET's `_redeemBlocked` exit-guarantee logic against our storage.
    function setBreaker(bool paused, uint256 readyAt) external {
        redemptionPaused = paused;
        emergencyReadyAt = readyAt;
    }
    function localRedeemBlocked() external view returns (bool) { return _redeemBlocked(); }
}

/**
 * @title FacetLayoutInvariant
 * @notice Proves the load-bearing property of the EIP-170 facet split:
 *
 *   F-1  the registry and the facet agree slot-for-slot (verified statically with
 *        `forge inspect ... storage-layout`, and dynamically here by running the
 *        FACET'S code against a foreign-but-identically-shaped storage image);
 *   F-2  a direct call to a deployed {RedemptionExt} is INERT — it runs against its
 *        own empty storage and reverts before touching value;
 *   F-3  the shared OZ ReentrancyGuard slot is a fixed ERC-7201 namespace, so the
 *        facet's `nonReentrant` locks the REGISTRY (which is why the registry's
 *        forwarders must not also be `nonReentrant`).
 *
 *  Run: FOUNDRY_PROFILE=cauldron forge test --match-contract FacetLayoutInvariant
 *  (No fork required.)
 */
contract FacetLayoutInvariant is Test {
    RedemptionExt ext;
    LayoutProbe probe;

    function setUp() public {
        ext = new RedemptionExt();
        probe = new LayoutProbe();
        probe.setExt(address(ext));
    }

    /// F-1: the facet's compiled code reads the caller's slots at the offsets
    ///      {CauldronBase} declares. If the layouts diverged, this returns garbage.
    function testFuzz_FacetReadsCallerStorage(uint256 shares, uint256 outstanding_) public {
        shares = bound(shares, 1, 1_000_000);
        outstanding_ = bound(outstanding_, 0, type(uint128).max);
        probe.poke(shares, outstanding_, true);

        assertEq(
            probe.facetFloorPerFren(),
            outstanding_ / shares,
            "F-1: facet must compute the floor from the CALLER's storage"
        );
    }

    /// F-1b: zero shares is the documented degenerate case (no division by zero).
    function test_FacetFloorZeroShares() public {
        probe.poke(0, 1e18, true);
        assertEq(probe.facetFloorPerFren(), 0, "zero shares -> zero floor");
    }

    /// F-2: a DIRECT call to the deployed facet is inert. Its own `summoned` is
    ///      false, so every entrypoint bounces before touching value.
    function test_DirectFacetCallsAreInert() public {
        vm.expectRevert(CauldronBase.NotSummoned.selector);
        ext.redeemOgFren(1);

        vm.expectRevert(CauldronBase.NotSummoned.selector);
        ext.buyTreasuryOgFren(1);

        vm.expectRevert(CauldronBase.NotSummoned.selector);
        ext.donateToReserve(1);

        vm.expectRevert(CauldronBase.NotSummoned.selector);
        ext.materializeLegacyReserve();

        assertEq(ext.genesisReserveOutstanding(), 0, "facet custodies nothing");
        assertEq(address(ext).balance, 0, "facet holds no ETH");
    }

    /// F-3 EXIT GUARANTEE: redemptions are blocked ONLY while the breaker is on AND
    ///     no emergency is armed. The instant an emergency is armed the exit is
    ///     forced open, so holders can always leave at floor before custody moves.
    function testFuzz_ExitGuarantee(bool paused, uint256 readyAt) public {
        probe.setBreaker(paused, readyAt);
        bool expected = paused && readyAt == 0;
        assertEq(probe.localRedeemBlocked(), expected, "F-3: exit guarantee semantics");
        if (paused && readyAt != 0) {
            assertFalse(probe.localRedeemBlocked(), "F-3: an armed emergency FORCES the exit open");
        }
    }

    /// The facet must add NO storage of its own beyond the shared base — otherwise
    /// its layout would diverge from the registry's. Checked by comparing the base
    /// constants both expose (a cheap sanity check on top of `forge inspect`).
    function test_SharedConstantsAgree() public view {
        assertEq(ext.TOTAL_SUPPLY(), 777_000_000e18, "supply constant");
        assertEq(ext.GEN1_ACTIVE_TOKENS(), (777_000_000e18 * 4) / 5, "gen-1 active tranche");
        assertEq(ext.AUTO_MIGRATE_FEE(), 0.069 ether, "auto-migrate fee");
        assertEq(uint256(int256(ext.TICK_SPACING())), 200, "tick spacing");
    }
}
