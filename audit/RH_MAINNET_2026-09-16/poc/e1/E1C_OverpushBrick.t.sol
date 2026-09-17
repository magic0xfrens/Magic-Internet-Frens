// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PerpEngineForkTest} from "../PerpEngine.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * E1C — lead L4. A large enough spot push makes the band-less buy-back's cost
 * exceed the engine's ETH balance, so PoolManager.settle{value:...} reverts and
 * liquidate() reverts whole. Question: is the short then PERMANENTLY unclosable
 * (Critical brick), or does it recover once spot is restored (transient DoS)?
 */
contract E1C_OverpushBrick is PerpEngineForkTest {
    function _rawSell(uint256 tokenIn) internal returns (uint256 ethOut) {
        ethOut = abi.decode(pm.unlock(abi.encode(uint8(1), tokenIn)), (uint256));
    }

    struct R {
        bool liqRevertedUnderPush;
        bool closedAfterRestore;
    }

    function _run() internal returns (R memory r) {
        uint8 lev = perp.maxLeverage();
        uint256 capNotional = (perp.activeEthDepth() * 500) / 10_000;
        uint256 coll = (capNotional / lev) * 9 / 10;

        vm.deal(trader, coll + 1 ether);
        vm.prank(trader);
        uint256 id = perp.openShort{value: coll}(lev, 0, 0, coll);

        // Push spot up hard enough that the buy-back cost exceeds engine ETH.
        vm.deal(address(this), 500 ether);
        uint256 tokStart = IERC20Minimal(token).balanceOf(address(this));
        _buyToken(300 ether);
        uint256 tokBought = IERC20Minimal(token).balanceOf(address(this)) - tokStart;

        // liquidate() should revert (settle underfunded) at the inflated spot.
        try perp.liquidate(id) { r.liqRevertedUnderPush = false; }
        catch { r.liqRevertedUnderPush = true; }

        // Restore spot by dumping the tokens we bought.
        if (tokBought > 0) _rawSell(tokBought);

        // Recovery path: the owner closes their own short after spot is restored.
        vm.prank(trader);
        try perp.close(id, 0) {} catch {}
        (address t2,,,,,,,) = perp.positions(id);
        r.closedAfterRestore = (t2 == address(0));
    }

    function test_overpush_brick_is_transient_not_permanent() public {
        vm.skip(!active);
        R memory r = _run();
        emit log_named_string("liquidate reverted under push", r.liqRevertedUnderPush ? "yes" : "no");
        emit log_named_string("position closed after restore", r.closedAfterRestore ? "yes" : "no");
        // If both hold: the over-push is a transient DoS, recoverable by restoring
        // spot then closing/liquidating. If close FAILS after restore, that is a
        // permanent brick and this assertion fails loudly.
        assertTrue(r.closedAfterRestore, "position recoverable after spot restore");
    }
}
