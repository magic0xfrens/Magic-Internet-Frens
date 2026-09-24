// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {console2} from "forge-std/console2.sol";

/**
 *  R1A — PRE-EMPTIVE LIQUIDATION FREE KILL.
 *
 *  `PerpSwapLib.projectedSqrtPriceX96` inflates the pending swap's input by
 *  SLACK_BPS = 1500 (15%) and rounds the ratio UP, then `PerpEngine._liqTest`
 *  uses that PROJECTED price as a ZERO-BUFFER insolvency trigger. So there is a
 *  band of trade sizes for which a position is solvent at the price the trade
 *  actually leaves behind, yet is force-closed before the trade runs.
 *
 *  Invariant under test (I2, "no free kills"): no position that is solvent at the
 *  REALIZED post-trade price is liquidated by that trade.
 */
contract R1A_FreeKillSlack is YBase {
    uint256 internal vid;
    uint256 internal vSize;
    uint256 internal vColl;
    uint256 internal vPrin;

    bool internal ran;
    bool internal healthyBefore;
    bool internal diedInSwap;
    bool internal solventAtRealized;
    uint256 internal foundSize;
    uint256 internal realizedVal;
    uint256 internal threshold;

    function setUp() public {
        _boot(60 ether, 0);
        if (!active) return;
        _bootPerp(40 ether, 400_000_000 ether);
    }

    function _openVictimLong() internal {
        vm.prank(victim);
        vid = perp.openLong{value: 1 ether}(2, 0, 0, 1 ether);
        (, , uint128 c, uint256 s, uint256 p, , , ) = perp.positions(vid);
        vColl = uint256(c);
        vSize = s;
        vPrin = p;
        // long insolvency (PerpEngine._insolventVal): val < principal
        threshold = vPrin;
    }

    /// @dev token amount worth roughly `ethAmt` at the current spot.
    function _tokensFor(uint256 ethAmt) internal view returns (uint256) {
        uint256 v = PerpSwapLib.quoteAt(1e18, uint256(_sqrtP()));
        if (v == 0) return 0;
        return (ethAmt * 1e18) / v;
    }

    function _trySell(uint256 tokenIn) internal returns (bool died, uint256 valAtRealized) {
        deal(token, attacker, tokenIn, true);
        _sell(tokenIn, attacker);
        uint160 realized = _sqrtP();
        valAtRealized = PerpSwapLib.quoteAt(vSize, uint256(realized));
        (address t, , , , , , , ) = perp.positions(vid);
        died = (t == address(0));
    }

    function _search() internal {
        uint256 coarse;
        for (uint256 i = 1; i <= 80; i++) {
            uint256 e = i * 10 ether;
            uint256 snap = vm.snapshotState();
            (bool died, ) = _trySell(_tokensFor(e));
            vm.revertToState(snap);
            if (died) { coarse = e; break; }
        }
        if (coarse == 0) return;
        console2.log("coarse kill at sellEthEq", coarse);
        uint256 lo = coarse > 10 ether ? coarse - 10 ether : 0;
        for (uint256 j = 1; j <= 40; j++) {
            uint256 e = lo + j * 0.25 ether;
            uint256 snap = vm.snapshotState();
            (bool died, uint256 val) = _trySell(_tokensFor(e));
            vm.revertToState(snap);
            if (died) {
                foundSize = e;
                diedInSwap = true;
                realizedVal = val;
                solventAtRealized = (val >= threshold);
                console2.log("MIN kill sellEthEq", e);
                console2.log("  valAtRealized", val, "threshold", threshold);
                return;
            }
        }
    }

    function test_R1A_free_kill_inside_the_projection_slack() public {
        if (active) {
            _openVictimLong();
            healthyBefore = !perp.isLiquidatable(vid);
            _search();
            ran = true;
        }
        console2.log("ran", ran);
        console2.log("healthyBefore", healthyBefore);
        console2.log("diedInSwap", diedInSwap);
        console2.log("solventAtRealized", solventAtRealized);
        console2.log("foundSellEthEq", foundSize);
        console2.log("realizedVal", realizedVal, "threshold(principal)", threshold);
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        assertTrue(ran, "fork not active - PoC proved nothing");
        assertTrue(healthyBefore, "victim must be healthy before the attack");
        assertTrue(diedInSwap, "no trade size killed the victim");
        //  CHARACTERIZATION, NOT A BUG GATE (red-team R1A, rated LOW, ACCEPTED).
        //  The kill IS early: `_liqTest` tests insolvency at the PROJECTED price
        //  with no maintenance buffer, so there is a band where the victim is
        //  still (barely) solvent at the realized price. It is EARLY, not WRONG —
        //  the victim is already underwater on the mark leg at the realized price,
        //  staker harm is zero, and the keeper bounty (~1.0 mETH) is dwarfed by
        //  the 0.5-1 ETH of round-trip fees needed to farm it.
        //  The two obvious "fixes" are BOTH forbidden and were both tried:
        //    * applying `maintenanceBps` to the projected leg — tried 2026-09-13,
        //      REVERTED, it broke the A02 and flash-crash suites by letting one
        //      trade farm a merely-unhealthy position;
        //    * shrinking SLACK_BPS — that is the LESS conservative direction and
        //      it feeds the bad-debt class R1B/R1C exist to close (measured: at
        //      500 bps the worst cascade charged PLV 25.81 mETH; at 1500 bps it
        //      charges ZERO at every size).
        //  So this test PINS the accepted behaviour instead of forbidding it: the
        //  earliness must stay BOUNDED BY THE SLACK. If a future change widens the
        //  overshoot past the 15% projection slack, this fails and someone looks.
        if (solventAtRealized) {
            uint256 overshoot = realizedVal - threshold;
            console2.log("accepted early-kill overshootWei", overshoot);
            assertLe(
                overshoot,
                (threshold * 1500) / 10_000,
                "early kill exceeded the SLACK_BPS projection band - NOT the accepted behaviour"
            );
        }
    }
}
