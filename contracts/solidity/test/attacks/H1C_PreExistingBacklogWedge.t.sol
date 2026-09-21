// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";

interface IPerpH1C {
    function openCount() external view returns (uint256);
    function nextId() external view returns (uint256);
    function isLiquidatable(uint256 id) external view returns (bool);
    function maintenanceBps() external view returns (uint256);
    function warmup() external view returns (uint256);
    function maxNotionalBps() external view returns (uint256);
    function fundingRateBpsPerDay() external view returns (uint256);
    function setRisk(uint256 w, uint256 c, uint256 m, uint256 n, uint256 o, uint256 f) external;
}

/**
 * H1C — the keeperless property, versus a PRE-EXISTING liquidation backlog.
 *
 * 98a97ec made a PRE-trade sweep report `complete == false` whenever it hit the
 * MAX_LIQ_PER_SWAP kill cap and found ANOTHER position the trade condemns. That
 * closed real bad debt. But it does not distinguish two very different states:
 *
 *   (a) THIS TRADE would condemn a 9th position  -> refusing the trade is the
 *       whole point; the trade is what creates the loss.
 *   (b) MORE THAN 8 positions are ALREADY underwater at live spot, before any
 *       trade  -> refusing does not rescue them. The revert also rolls back the
 *       8 kills the sweep just made, so no swap can ever chip the backlog down.
 *       Every swap reverts, forever, and only the external `liquidate()` can
 *       exit the state. On a protocol whose whole design is that liquidation
 *       happens INSIDE the swap with no keeper, that is a regression.
 *
 * This test builds (b) by NON-SWAP drift — an owner `setRisk` raising
 * `maintenanceBps`, the cheap and fully in-protocol way to move many positions
 * underwater without a single trade — and then measures whether the pool can
 * still trade and still heal itself.
 *
 * PRE-refinement this test FAILS: every swap reverts and the book never heals.
 * POST-refinement it passes: swaps fill again and the in-swap sweeps grind the
 * backlog to zero with ZERO keeper calls.
 */
contract H1C_PreExistingBacklogWedge is YBase {
    uint256 internal opened;
    bool internal ran;

    uint256 internal constant N_LONGS = 18;

    function doBuy(uint256 ethIn) external {
        require(msg.sender == address(this), "self");
        _buy(ethIn, attacker);
    }

    function _openLongs() internal {
        vm.deal(attacker, 10_000 ether);
        for (uint256 i = 0; i < N_LONGS; i++) {
            vm.prank(attacker);
            (bool ok,) = address(perp).call{value: 0.012 ether, gas: 4_000_000}(
                abi.encodeWithSignature(
                    "openLong(uint8,uint256,uint256,uint256)", uint8(3), uint256(0), uint256(0), uint256(0.012 ether)
                )
            );
            if (!ok) break;
            opened++;
            _warp(180);
            vm.roll(block.number + 1);
            perp.poke();
        }
    }

    function _liqOpen() internal view returns (uint256 n) {
        uint256 last = IPerpH1C(address(perp)).nextId();
        for (uint256 id = 1; id < last; id++) {
            if (IPerpH1C(address(perp)).isLiquidatable(id)) n++;
        }
    }

    /// Non-swap drift: governance tightens the maintenance margin. No trade.
    function _driftUnderwater() internal {
        // `maxLeverageCeiling` (3) and `maxOiBps` (3_000) are internal; these are
        // their declared defaults (PerpEngine.sol:170, :177), re-passed unchanged.
        // The ONLY parameter that moves is `maintenanceBps`: 1_500 -> 5_000.
        IPerpH1C p = IPerpH1C(address(perp));
        assertEq(p.maintenanceBps(), 1_500, "unexpected starting maintenanceBps");
        // Tighten maintenance AND open the funding rate to its bound, then let
        // time pass. `poke()` is not a swap; nothing here trades.
        p.setRisk(p.warmup(), 3, 5_000, p.maxNotionalBps(), 3_000, 10_000);
        assertEq(p.maintenanceBps(), 5_000, "setRisk did not take");
        for (uint256 d = 0; d < 45; d++) {
            _warp(1 days);
            vm.roll(block.number + 1);
            perp.poke();
        }
    }

    function test_H1C_aPreExistingBacklogMustNotFreezeTheSwapPath() public {
        _boot(60 ether, 0);
        if (!active) return;
        ran = true;

        _bootPerp(60 ether, 4_000_000 ether);
        _openLongs();
        assertGt(opened, 8, "could not build a book larger than MAX_LIQ_PER_SWAP");

        _warp(2 hours);
        vm.roll(block.number + 10);
        perp.poke();
        console2.log("open before drift      :", IPerpH1C(address(perp)).openCount());
        console2.log("liquidatable before    :", _liqOpen());

        // THE DRIFT — no swap of any kind.
        _driftUnderwater();
        uint256 backlog = _liqOpen();
        console2.log("liquidatable after drift:", backlog);
        assertGt(backlog, 8, "drift did not produce a backlog larger than the kill cap");

        // Can the pool still trade? A BUY, which moves the price in the direction
        // that HELPS every one of these longs, and is therefore never the cause
        // of anyone's insolvency.
        uint256 fills;
        for (uint256 i = 0; i < 12; i++) {
            (bool ok,) = address(this).call{gas: 28_000_000}(abi.encodeWithSelector(this.doBuy.selector, uint256(0.2 ether)));
            if (ok) fills++;
            vm.roll(block.number + 1);
            _warp(13);
            perp.poke();
        }
        uint256 left = _liqOpen();
        console2.log("buys that filled       :", fills);
        console2.log("liquidatable left      :", left);
        console2.log("open after             :", IPerpH1C(address(perp)).openCount());

        // THE PROPERTY, in two halves.
        // 1. The pool is not frozen by a backlog no trade created.
        assertGt(fills, 0, "WEDGED: every swap reverts on a pre-existing backlog");
        // 2. And it heals ITSELF, in-swap, with no external keeper called at all.
        assertEq(left, 0, "the in-swap sweeps could not clear the backlog without a keeper");
    }
}
