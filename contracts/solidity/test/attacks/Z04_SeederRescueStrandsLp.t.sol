// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ZAuditBase, ZMockGovernor} from "./ZAuditBase.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
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

    /// REGRESSION: the break-glass returns the loose funds but keeps the recovery path
    /// armed, so the already-placed book is no longer orphaned.
    function test_FIXED_RescueLeavesTheRecoveryPathOpen() public {
        if (!active) return;

        assertTrue(seeder.seeding(), "campaign live");
        (uint256 liqBefore, uint256 n) = _seederLiquidity();
        assertGt(n, 0, "seeder tracks ranges");
        assertGt(liqBefore, 0, "seeder has REAL liquidity in the pool");
        emit log_named_uint("seeder ranges", n);
        emit log_named_uint("seeder liquidity before rescue", liqBefore);

        // Governance pulls the documented break-glass (emergencyAdmin = this, delay 0).
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.rescueSeeder();

        // The campaign stays ARMED, which is what keeps `withdrawAll` reachable from
        // `_removeLiquidity` / `migrateToSuccessor`.
        assertTrue(seeder.seeding(), "FIXED: rescue does not orphan the campaign");
        (uint256 liqAfter,) = _seederLiquidity();
        assertEq(liqAfter, liqBefore, "rescue still only moves LOOSE funds (by design)");

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
        if (!active) return;

        (uint256 liqBefore,) = _seederLiquidity();
        assertGt(liqBefore, 0, "book funded");
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.rescueSeeder();

        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(pid), "gen-1 dead");

        uint256 n = seeder.rangeCount();
        int24[] memory los = new int24[](n);
        int24[] memory his = new int24[](n);
        for (uint256 i = 0; i < n; ++i) {
            (los[i], his[i]) = seeder.ranges(i);
        }

        registry.relaunch(); // no longer reverts NoLiquidityToSeed
        assertEq(registry.currentGeneration(), 2, "FIXED: rebirth succeeds after a rescue");

        uint256 leftover;
        for (uint256 i = 0; i < n; ++i) {
            (uint128 liq,,) = pm.getPositionInfo(pid, address(seeder), los[i], his[i], bytes32(0));
            leftover += liq;
        }
        assertEq(leftover, 0, "FIXED: the whole gen-1 book was unwound, nothing stranded");
        emit log_named_uint("liquidity recovered (was stranded)", liqBefore);
    }

    /// REGRESSION (secondary): `startSeed` now resets `ranges`, so a rebirth's campaign
    /// starts from a clean per-campaign range set instead of inheriting the dead pool's.
    function test_FIXED_RangesResetPerCampaign() public {
        if (!active) return;

        vm.roll(block.number + hook.snipeWindowBlocks() + 1);
        _buyExactIn(2 ether); // fee accrues to hook.relaunchETH so relaunch can proceed

        uint256 rangesGen1 = seeder.rangeCount();
        assertGt(rangesGen1, 0, "gen-1 tracked ranges");
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.rescueSeeder();

        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();

        // gen-2's campaign lays its own base + first bands only.
        assertLt(seeder.rangeCount(), rangesGen1 + 3, "FIXED: gen-1 ranges did not leak forward");
        emit log_named_uint("gen-1 ranges", rangesGen1);
        emit log_named_uint("range count after gen-2 startSeed", seeder.rangeCount());
    }

    /// CONTROL: without the rescue, the normal relaunch teardown DOES unwind the
    /// seeder's book — proving the loss is caused by `rescue`, not by the design.
    function test_SAFE_NormalRelaunchRecoversTheBook() public {
        if (!active) return;

        uint256 n = seeder.rangeCount();
        int24[] memory los = new int24[](n);
        int24[] memory his = new int24[](n);
        uint256 liqBefore;
        for (uint256 i = 0; i < n; ++i) {
            (los[i], his[i]) = seeder.ranges(i);
            (uint128 liq,,) = pm.getPositionInfo(pid, address(seeder), los[i], his[i], bytes32(0));
            liqBefore += liq;
        }
        assertGt(liqBefore, 0, "book funded");

        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();

        uint256 leftover;
        for (uint256 i = 0; i < n; ++i) {
            (uint128 liq,,) = pm.getPositionInfo(pid, address(seeder), los[i], his[i], bytes32(0));
            leftover += liq;
        }
        assertEq(leftover, 0, "control: gen-1's exact ranges were fully unwound");
    }
}
