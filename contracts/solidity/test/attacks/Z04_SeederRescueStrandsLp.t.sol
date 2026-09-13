// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ZAuditBase, ZMockGovernor} from "./ZAuditBase.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * FINDING Z-04 (High) — `CauldronRegistry.rescueSeeder()` PERMANENTLY STRANDS the
 * entire active liquidity tranche of a progressive generation.
 *
 * CauldronSeeder.rescue() returns only the LOOSE balances and then sets
 * `seeding = false`; it never unwinds the core positions it has already placed and
 * never clears `ranges`:
 *
 *     function rescue(address to) external onlyRegistry lock {
 *         ... transfer loose token + ETH ...
 *         seeding = false;                 // <-- positions left in the pool
 *     }
 *
 * Every registry path to the ONLY recovery function is gated on that same flag:
 *
 *     CauldronRegistry._removeLiquidity:1168
 *         if (_seeder != address(0) && ISeeder(_seeder).seeding()) { withdrawAll }
 *     CauldronRegistry.migrateToSuccessor:352
 *         if (_seeder != address(0) && ISeeder(_seeder).seeding()) { withdrawAll }
 *
 * and `CauldronSeeder.withdrawAll` is `onlyRegistry`, so no external actor can call
 * it either. After one `rescueSeeder()` the placed liquidity is unreachable forever.
 *
 * The docstring calls this a hatch "for an ABORTED campaign", but `startSeed` places
 * the two-sided BASE and the seed-floor slice IMMEDIATELY, in the same transaction —
 * so a campaign with only loose funds never exists, and `rescue` is always
 * destructive.
 *
 * Secondary defect: `startSeed` did not `delete ranges` (only `withdrawAll` did), so
 * the NEXT generation's campaign inherited the dead generation's tick ranges.
 *
 * STATUS: FIXED. `rescue` no longer clears `seeding`, so the registry's teardown paths
 * still reach `withdrawAll` and the placed book is recovered at the next
 * relaunch/handoff; and `startSeed` now `delete ranges` for a clean per-campaign reset.
 * The suite below is the regression.
 */
contract Z04_SeederRescueStrandsLp is ZAuditBase {
    using StateLibrary for IPoolManager;

    CauldronSeeder internal seeder;
    address internal token;
    PoolId internal pid;

    function setUp() public {
        _bootstrap(1 ether);
        if (!active) return;

        seeder = new CauldronSeeder(address(registry), posm, address(pm));
        registry.setSeeder(address(seeder)); // also wires hook.setSeeder
        registry.setSeedWindow(900); // progressive: stream over 15 min
        registry.setGovernor(address(new ZMockGovernor(address(0xBEEF))));

        (token, pid) = registry.summon{value: 10 ether}();
    }

    /// Sum the seeder's live liquidity across every range it tracks.
    function _seederLiquidity() internal view returns (uint256 total, uint256 n) {
        n = seeder.rangeCount();
        for (uint256 i = 0; i < n; ++i) {
            (int24 lo, int24 hi) = seeder.ranges(i);
            (uint128 liq,,) = pm.getPositionInfo(pid, address(seeder), lo, hi, bytes32(0));
            total += liq;
        }
    }

    /// @dev Liquidity of generation `g`'s registry-owned full-range base. Since
    ///      commit 40b9608 (`SEED_BASE_WAD = 1e18`, PoolOps.sol:168) this — not a
    ///      streamed set of seeder ranges — IS the book.
    function _baseLiquidity(uint256 g) internal view returns (uint128) {
        uint256 id = registry.generationPositionId(g);
        if (id == 0) return 0;
        return IPositionManagerOps(posm).getPositionLiquidity(id);
    }

    /// REGRESSION: the break-glass returns the loose funds but keeps the recovery path
    /// armed, so the already-placed book is no longer orphaned.
    function test_FIXED_RescueLeavesTheRecoveryPathOpen() public {
        
        vm.skip(!active);

        //  ── WHAT MOVED (commit 40b9608, `SEED_BASE_WAD = 1e18`) ────────────
        //  Z-04 was that `rescue()` left the seeder's ALREADY-PLACED bands in the
        //  pool while flipping `seeding = false` — the very flag every registry
        //  recovery path was gated on. Since 40b9608 the whole of ledger A is laid
        //  as a two-sided FULL-RANGE base owned by the REGISTRY at summon and the
        //  streamed campaign never starts, so the seeder places no bands and there
        //  is nothing for `rescue` to orphan. The book this test is really about
        //  is `generationPositionId`, and it is not the seeder's to lose — which
        //  is asserted directly below rather than skipped.
        assertFalse(seeder.seeding(), "no campaign is started under a full-range base");
        (uint256 seederLiq, uint256 n) = _seederLiquidity();
        assertEq(n, 0, "the seeder tracks no ranges, so none can be orphaned");
        assertEq(seederLiq, 0, "and it holds no liquidity in the pool");

        uint128 baseBefore = _baseLiquidity(registry.currentGeneration());
        assertGt(baseBefore, 0, "the registry-owned full-range base IS the book");

        // Governance pulls the documented break-glass (emergencyAdmin = this, delay 0).
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.rescueSeeder();

        // THE PROPERTY, unchanged in substance: the break-glass cannot take the
        // book down with it.
        assertEq(
            _baseLiquidity(registry.currentGeneration()), baseBefore,
            "FIXED: rescue does not touch the registry's own base"
        );

        // Still registry-gated against outsiders.
        vm.expectRevert(); // OnlyRegistry
        seeder.withdrawAll(address(this));
    }

    /// REGRESSION (the escalation). On a progressive generation the seeder's book is
    /// the ONLY source of relaunch ETH (`generationPositionId` is 0 and the reserve is
    /// single-sided token), so orphaning it used to make `relaunch()` revert
    /// `NoLiquidityToSeed` — the machine could never be reborn. It now rebirths and
    /// recovers the book.
    function test_FIXED_RelaunchStillRecoversAfterRescue() public {
        
        vm.skip(!active);

        //  The escalation's premise ("on a progressive generation
        //  `generationPositionId` is 0, so the seeder's book is the ONLY source of
        //  relaunch ETH") is gone with 40b9608 — the base is registry-owned from
        //  summon. The property that matters survives verbatim: pulling the
        //  break-glass must not leave the machine unable to be reborn, and the
        //  dead generation's book must come back.
        uint128 liqBefore = _baseLiquidity(1);
        assertGt(liqBefore, 0, "book funded");
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.rescueSeeder();

        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(pid), "gen-1 dead");

        registry.relaunch(); // must still not revert NoLiquidityToSeed
        assertEq(registry.currentGeneration(), 2, "FIXED: rebirth succeeds after a rescue");
        assertEq(_baseLiquidity(1), 0, "FIXED: the whole gen-1 book was unwound, nothing stranded");
        assertGt(_baseLiquidity(2), 0, "and gen-2 is born with a book of its own");
        emit log_named_uint("liquidity recovered (was stranded)", liqBefore);
    }

    /// REGRESSION (secondary): `startSeed` now resets `ranges`, so a rebirth's campaign
    /// starts from a clean per-campaign range set instead of inheriting the dead pool's.
    function test_FIXED_RangesResetPerCampaign() public {
        
        vm.skip(!active);

        vm.roll(block.number + hook.snipeWindowBlocks() + 1);
        _buyExactIn(2 ether); // fee accrues to hook.relaunchETH so relaunch can proceed

        //  ── WHAT MOVED (commit 40b9608) ────────────────────────────────────
        //  This tested `startSeed` resetting `ranges`. No campaign starts under a
        //  full-range base, so `rangeCount()` is 0 in EVERY generation and the
        //  original comparison is vacuous. The property it guarded — a rebirth
        //  must start from a clean book, not inherit the dead pool's — is now
        //  carried by `generationPositionId`, so that is what is asserted.
        assertEq(seeder.rangeCount(), 0, "no streamed campaign exists to leak forward");
        uint256 posGen1 = registry.generationPositionId(1);
        assertGt(posGen1, 0, "gen-1 has a full-range base");

        registry.armEmergency(); // F-19: custody actions must be armed
        registry.rescueSeeder();

        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();

        uint256 posGen2 = registry.generationPositionId(2);
        assertGt(posGen2, 0, "gen-2 lays a base of its own");
        assertTrue(posGen2 != posGen1, "FIXED: gen-1's book did not leak forward");
        assertEq(seeder.rangeCount(), 0, "and still no campaign ranges after the rebirth");
        emit log_named_uint("gen-1 base position", posGen1);
        emit log_named_uint("gen-2 base position", posGen2);
    }

    /// CONTROL: without the rescue, the normal relaunch teardown DOES unwind the
    /// seeder's book — proving the loss is caused by `rescue`, not by the design.
    function test_SAFE_NormalRelaunchRecoversTheBook() public {
        
        vm.skip(!active);

        //  The control is the same shape against the book that exists today: the
        //  registry-owned full-range base (40b9608), not a set of seeder bands.
        uint128 liqBefore = _baseLiquidity(1);
        assertGt(liqBefore, 0, "book funded");

        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();

        assertEq(_baseLiquidity(1), 0, "control: gen-1's book was fully unwound by the normal teardown");
        assertGt(_baseLiquidity(2), 0, "and the rebirth laid a new one");
    }
}
