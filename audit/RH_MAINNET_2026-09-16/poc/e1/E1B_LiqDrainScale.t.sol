// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PerpEngineForkTest} from "../PerpEngine.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * E1B — scale study for E1A (lead L3). The per-position notional is capped at
 * maxNotionalBps=500 (5% of pool depth, PerpEngine.sol:1961/_checkNotional), so a
 * single short — and thus the band-less buy-back's overspend — is bounded to a few
 * percent of depth. This sizes the short at the max allowed and measures the drain
 * and the pure-swapper net across push sizes to see if net crosses positive.
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

        perp.liquidate(id);
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

    function test_scale_push_1eth() public {
        vm.skip(!active);
        R memory r = _run(1 ether);
        _report("push1", r);
        assertTrue(r.healthyPre, "healthy pre-push");
        assertTrue(r.cleared, "force-liquidated");
        assertGt(r.drain, 0, "plv drained");
    }

    function test_scale_push_3eth() public {
        vm.skip(!active);
        R memory r = _run(3 ether);
        _report("push3", r);
        assertTrue(r.healthyPre, "healthy pre-push");
        assertTrue(r.cleared, "force-liquidated");
        assertGt(r.drain, 0, "plv drained");
    }
}
