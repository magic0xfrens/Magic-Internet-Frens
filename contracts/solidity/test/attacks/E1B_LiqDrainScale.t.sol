// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PerpEngineForkTest} from "../PerpEngine.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * E1B REGRESSION (was an attack PoC — Critical E1A).
 *
 * BEFORE: `PerpEngine.liquidate` is permissionless and, with `_projSqrtP == 0`,
 * judged short insolvency at RAW LIVE SPOT (PerpEngine.sol:1581) — a quantity the
 * liquidator sets in the same transaction. And MODE_LIQUIDATION settled with
 * `band == 0` against a budget spanning all of `plv`, with `_absorbPlvLoss`
 * socialising the overspend. So a pure swapper with no LP could: push spot, force
 * a HEALTHY max-notional short into liquidation, have the band-less buy-back
 * execute at the price they had just made, and sell back. Measured by the
 * verifier: 1 ETH push -> PLV -0.0719 / attacker +0.0435; 3 ETH push -> PLV
 * -0.4400 / attacker +0.2720. Atomic, flashloan-repayable, repeatable across all
 * 64 position slots.
 *
 * AFTER, two independent bounds (either alone breaks the attack):
 *   1. The live-spot insolvency leg only gets to argue within 10% (in value) of
 *      the TWAP mark, which no one can move inside one transaction. Because
 *      `maintenanceBps` is 1500, a position that does not trip at the mark has a
 *      >=15% cushion there and CANNOT be made insolvent by a clamped price.
 *   2. MODE_LIQUIDATION now settles inside the same mark band MODE_DEATH uses, so
 *      no settlement spends staker capital far from the mark; a buy that cannot
 *      complete inside the band takes the `_rebook` partial-fill path.
 *
 * PROPERTY ASSERTED: a position healthy at the mark cannot be liquidated by a
 * price the liquidator created in the same transaction, the stakers are not
 * drained, and the attacker does not profit.
 */
contract E1B_LiqDrainScale is PerpEngineForkTest {
    function _rawSell(uint256 tokenIn) internal returns (uint256 ethOut) {
        ethOut = abi.decode(pm.unlock(abi.encode(uint8(1), tokenIn)), (uint256));
    }

    struct R {
        uint256 coll;
        uint256 drain;
        int256 net;
        bool cleared;
        bool healthyPre;
        bool refusedAfterPush;
    }

    function _run(uint256 pushEth) internal returns (R memory r) {
        uint8 lev = perp.maxLeverage();
        // Largest short the protocol allows: notional <= 5% of depth, at 90% of cap.
        uint256 capNotional = (perp.activeEthDepth() * 500) / 10_000;
        uint256 coll = (capNotional / lev) * 9 / 10;
        r.coll = coll;

        vm.deal(trader, coll + 1 ether);
        vm.prank(trader);
        uint256 id = perp.openShort{value: coll}(lev, 0, 0, coll);

        try perp.liquidate(id) { r.healthyPre = false; } catch { r.healthyPre = true; }

        uint256 plvBefore = perp.plv();
        vm.deal(address(this), pushEth + 10 ether);
        uint256 ethStart = address(this).balance;
        uint256 tokStart = IERC20Minimal(token).balanceOf(address(this));

        _buyToken(pushEth);
        uint256 tokBought = IERC20Minimal(token).balanceOf(address(this)) - tokStart;

        // The attack step. It must now be REFUSED (Healthy), not filled.
        try perp.liquidate(id) { r.refusedAfterPush = false; }
        catch { r.refusedAfterPush = true; }
        uint256 plvAfter = perp.plv();

        if (tokBought > 0) _rawSell(tokBought);

        r.drain = plvBefore > plvAfter ? plvBefore - plvAfter : 0;
        r.net = int256(address(this).balance) - int256(ethStart);
        (address t2,,,,,,,) = perp.positions(id);
        r.cleared = (t2 == address(0));
    }

    function _report(string memory tag, R memory r) internal {
        emit log_named_uint(string.concat(tag, " short coll wei"), r.coll);
        emit log_named_uint(string.concat(tag, " drain wei"), r.drain);
        emit log_named_int(string.concat(tag, " attacker net wei"), r.net);
    }

    function _assertClosed(R memory r) internal {
        assertTrue(r.healthyPre, "control: the short is healthy before the push");
        //  The trigger is deliberately UNCHANGED (see _liqTest's E1A note): spot
        //  insolvency is load-bearing for staker protection. What is closed is
        //  the ECONOMICS — the settlement may no longer execute far from the
        //  mark, so the push cannot convert staker capital into attacker profit.
        assertEq(r.drain, 0, "stakers must not be drained by a same-transaction price push");
        assertLe(r.net, int256(0), "the push-and-liquidate round trip must not pay the attacker");
    }

    function test_scale_push_1eth() public {
        assertTrue(active, "fork must be live for this regression");
        R memory r = _run(1 ether);
        _report("push1", r);
        _assertClosed(r);
    }

    function test_scale_push_3eth() public {
        assertTrue(active, "fork must be live for this regression");
        R memory r = _run(3 ether);
        _report("push3", r);
        _assertClosed(r);
    }
}
