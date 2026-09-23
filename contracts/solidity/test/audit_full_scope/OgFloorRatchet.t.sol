// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {CauldronBase} from "../../cauldron/CauldronBase.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {PoolOps, ReserveRef, IPositionManagerOps} from "../../cauldron/PoolOps.sol";

/**
 * @notice Fork-free probe over the SHARED base layout, same trick as
 *         {FacetLayoutInvariant}: plant known values in base slots and read the
 *         floor back, both locally and through the facet's own code.
 */
contract FloorProbe is CauldronBase {
    address public ext;

    function setExt(address e) external { ext = e; }

    function poke(uint256 shares, uint256 outstanding_, uint256 held) external {
        genesisShares = shares;
        genesisReserveOutstanding = outstanding_;
        treasuryHeldOg = held;
        summoned = true;
    }

    function reserve() external view returns (uint256) { return genesisReserveOutstanding; }

    /// @dev Exactly the bookkeeping `redeemOgFren` performs, minus the LP leg:
    ///      debit the floor, move the fren into the treasury.
    function simulateRedeem() external returns (uint256 paidOut) {
        paidOut = floorPerFren();
        if (genesisReserveOutstanding >= paidOut) genesisReserveOutstanding -= paidOut;
        treasuryHeldOg += 1;
    }

    /// @dev Exactly the bookkeeping `buyTreasuryOgFren` performs: price at 2x while
    ///      the fren is still the treasury's, then return it to the active set.
    function simulateResale() external returns (uint256 paidIn) {
        paidIn = 2 * floorPerFren();
        if (treasuryHeldOg > 0) treasuryHeldOg -= 1;
        genesisReserveOutstanding += paidIn;
    }

    /// @dev The OLD divisor, kept so a test can state the bug that was fixed.
    function legacyFloor() external view returns (uint256) {
        return genesisShares == 0 ? 0 : genesisReserveOutstanding / genesisShares;
    }

    function facetFloorPerFren() external returns (uint256) {
        (bool ok, bytes memory ret) =
            ext.delegatecall(abi.encodeWithSelector(CauldronBase.floorPerFren.selector));
        require(ok, "delegatecall failed");
        return abi.decode(ret, (uint256));
    }
}

/// @notice Minimal collection that answers only what `PoolOps.buyCollection`
///         consults before its OG guard: who owns the id, the art-id ceiling,
///         and where the OG tranche ends. Include one forged art id.
contract MockOgCollection {
    address public treasury;
    uint256 public GENESIS_SUPPLY;

    constructor(address treasury_, uint256 ogSupply) {
        treasury = treasury_;
        GENESIS_SUPPLY = ogSupply;
    }

    function ownerOf(uint256) external view returns (address) { return treasury; }
    function totalMinted() external view returns (uint256) { return GENESIS_SUPPLY + 1; }
}

/**
 * @title OgFloorRatchet
 * @notice Regression cover for the OG (genesis) redemption floor.
 *
 *  Three defects, all in how the floor accrues rather than in who may touch it:
 *
 *   R-1  `floorPerFren()` divided by `genesisShares`, a divisor that NEVER drops
 *        because a redeemed fren moves to the treasury instead of being burned.
 *        A redeemer withdrew `R/N` while the divisor stayed `N`, so every OG who
 *        stayed lost a factor of `(1 - 1/N)` and a run of redemptions with no
 *        matching resales decayed the floor as `F*(1 - 1/N)^k`.
 *
 *   R-2  the 2x resale was then priced off that already-lowered floor, so a full
 *        redeem->resale cycle returned only `F*(1 - 2/N)`: it repaired the damage
 *        the redemption caused rather than ratcheting above the starting point.
 *
 *   R-3  `PoolOps.buyCollection` guarded the treasury door with nothing but "the
 *        treasury owns it". `recycleCollection` blocks an OG from drawing the
 *        FORGED floor on the way in; nothing blocked an OG from being sold out
 *        the forged door on the way back, for 2x the forged floor (<= the OG
 *        floor by construction) with the payment credited to the forged ledger.
 *
 *  Run: FOUNDRY_PROFILE=cauldron forge test --match-contract OgFloorRatchet
 *  (No fork required.)
 */
contract OgFloorRatchetTest is Test {
    FloorProbe probe;
    RedemptionExt ext;

    uint256 constant N = 1000;      // genesis shares
    uint256 constant R0 = 1000e18;  // reserve backing

    function setUp() public {
        ext = new RedemptionExt();
        probe = new FloorProbe();
        probe.setExt(address(ext));
        probe.poke(N, R0, 0);
    }

    // ── R-1 ────────────────────────────────────────────────────────────────

    /// @notice A redemption must not move the floor for anyone who stays.
    ///         `(R - F)/(A - 1) == R/A` exactly, because `F == R/A`.
    function test_R1_RedemptionIsFloorNeutral() public {
        uint256 before = probe.floorPerFren();
        assertEq(before, R0 / N, "baseline floor");

        uint256 paid = probe.simulateRedeem();
        assertEq(paid, before, "redeemer is paid the floor");
        assertEq(probe.floorPerFren(), before, "floor must not move for the stayers");
    }

    /// @notice The decay the old divisor produced, stated so it cannot come back:
    ///         under the OLD formula the same redemption strictly LOWERS the floor.
    function test_R1_OldDivisorWouldHaveDiluted() public {
        uint256 before = probe.floorPerFren();
        probe.simulateRedeem();

        assertLt(probe.legacyFloor(), before, "old divisor: the stayers were diluted");
        assertEq(probe.floorPerFren(), before, "new divisor: they are not");
    }

    /// @notice Repeated redemptions with NO resales still cannot decay the floor.
    ///         This is the `F*(1 - 1/N)^k` run, and it must now be flat.
    function test_R1_ManyRedemptionsNoResalesStayFlat() public {
        uint256 before = probe.floorPerFren();
        for (uint256 i = 0; i < 50; i++) probe.simulateRedeem();

        assertEq(probe.floorPerFren(), before, "50 redemptions, floor unchanged");
        assertLt(probe.legacyFloor(), before, "the old formula would have decayed");
    }

    // ── R-2 ────────────────────────────────────────────────────────────────

    /// @notice A full redeem -> 2x resale cycle must leave the floor STRICTLY
    ///         higher than it started, and the reserve up by a full `F`.
    function test_R2_FullCycleRatchetsUp() public {
        uint256 f0 = probe.floorPerFren();
        uint256 r0 = probe.reserve();

        uint256 out = probe.simulateRedeem();
        uint256 paidIn = probe.simulateResale();

        assertEq(paidIn, 2 * f0, "resale is priced at 2x the (unmoved) floor");
        assertEq(probe.reserve(), r0 - out + paidIn, "reserve accounting");
        assertEq(probe.reserve(), r0 + f0, "net +F over the cycle");
        assertGt(probe.floorPerFren(), f0, "the floor ratchets, it does not merely recover");
    }

    /// @notice Many cycles compound upward and never retrace.
    function test_R2_CyclesCompoundMonotonically() public {
        uint256 last = probe.floorPerFren();
        for (uint256 i = 0; i < 20; i++) {
            probe.simulateRedeem();
            probe.simulateResale();
            uint256 now_ = probe.floorPerFren();
            assertGt(now_, last, "each completed cycle must raise the floor");
            last = now_;
        }
    }

    /// @notice The divisor is restored by the resale, so the active count returns
    ///         to where it started and the treasury holds nothing.
    function test_R2_ResaleRestoresTheDivisor() public {
        probe.simulateRedeem();
        assertEq(probe.treasuryHeldOg(), 1, "fren is parked in the treasury");
        probe.simulateResale();
        assertEq(probe.treasuryHeldOg(), 0, "and returned to the active set");
    }

    // ── divisor edges ──────────────────────────────────────────────────────

    /// @notice With EVERY fren in the treasury there is no active claimant to
    ///         divide by. The floor must fall back to the full count rather than
    ///         divide by zero — otherwise `buyTreasuryOgFren` quotes 2x0 and
    ///         reverts, and no fren could ever leave the treasury again.
    function test_AllInTreasuryFallsBackInsteadOfDividingByZero() public {
        probe.poke(N, R0, N);
        assertEq(probe.floorPerFren(), R0 / N, "fallback to the full divisor");
        assertGt(probe.floorPerFren(), 0, "resale must still be priceable");
    }

    /// @notice A `treasuryHeldOg` that somehow exceeds `genesisShares` must clamp,
    ///         not underflow the subtraction.
    function test_OverCountedTreasuryClamps() public {
        probe.poke(N, R0, N + 500);
        assertEq(probe.floorPerFren(), R0 / N, "clamped, not reverted");
    }

    function test_ZeroSharesIsStillZero() public {
        probe.poke(0, R0, 0);
        assertEq(probe.floorPerFren(), 0, "no shares -> no floor");
    }

    /// @notice The new slot must be visible to the FACET through delegatecall —
    ///         the property the whole EIP-170 split rests on. If `treasuryHeldOg`
    ///         had been inserted anywhere but the end, this reads a shifted slot.
    function test_FacetSeesTheSameDivisor() public {
        probe.poke(N, R0, 400);
        assertEq(probe.floorPerFren(), R0 / (N - 400), "local view");
        assertEq(probe.facetFloorPerFren(), probe.floorPerFren(), "facet agrees slot-for-slot");
    }

    // ── R-3 ────────────────────────────────────────────────────────────────

    /// @notice An OG id may not be bought out of the treasury through the FORGED
    ///         door. The guard sits before any ledger or position-manager work, so
    ///         a bare mock collection is enough to reach it.
    function test_R3_OgIdCannotBeBoughtThroughTheCollectionDoor() public {
        MockOgCollection col = new MockOgCollection(address(this), 100);
        ReserveRef memory r;

        vm.expectRevert(bytes("og tranche"));
        PoolOps.buyCollection(
            IPositionManagerOps(address(0)), address(0), address(col),
            address(0), 1, 42, address(this), r
        );
    }

    /// @notice The boundary id is still OG, and still refused.
    function test_R3_BoundaryIdIsOg() public {
        MockOgCollection col = new MockOgCollection(address(this), 100);
        ReserveRef memory r;

        vm.expectRevert(bytes("og tranche"));
        PoolOps.buyCollection(
            IPositionManagerOps(address(0)), address(0), address(col),
            address(0), 1, 100, address(this), r
        );
    }

    /// @notice The guard must be SCOPED to the OG tranche: a forged id gets past
    ///         it (and fails later, on the ledger work this mock cannot serve).
    ///         Without this, "og tranche" could be blocking everything.
    function test_R3_ForgedIdIsNotBlockedByTheOgGuard() public {
        MockOgCollection col = new MockOgCollection(address(this), 100);
        ReserveRef memory r;

        try PoolOps.buyCollection(
            IPositionManagerOps(address(0)), address(0), address(col),
            address(0), 1, 101, address(this), r
        ) {
            revert("a bare mock cannot have satisfied the ledger");
        } catch Error(string memory reason) {
            assertFalse(
                keccak256(bytes(reason)) == keccak256(bytes("og tranche")),
                "forged ids must pass the OG guard"
            );
        } catch {
            // Any non-string revert is also fine: it means we got past the guard
            // and died in the ledger/pm calls, which is the point.
        }
    }
}
