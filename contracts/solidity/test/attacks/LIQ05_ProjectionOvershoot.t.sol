// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";

/**
 * LIQ-05 — measure the ACTUAL over-projection of
 * `PerpSwapLib.projectedSqrtPriceX96` against the price the same trade really
 * leaves behind, to check the LIQ-04.B claim that "SLACK_BPS = 500 on the sqrt
 * ratio" is "~10% on price".
 *
 *  The slack is applied to `amountIn`, not to the ratio:
 *      inflated = amountIn * 1.05
 *      ratio    = 1 + inflated / reserveIn
 *  so the sqrt-price overshoot is 0.05 * (dE/E) / (1 + dE/E), i.e. it SHRINKS
 *  with trade size relative to depth — it is nowhere near a flat 10% on price.
 *
 *  Method: read spot, compute the projection for `ethIn`, then execute the same
 *  buy on the un-pre-swept EXACT-OUTPUT route (so no liquidation perturbs the
 *  measurement) and read spot again. Report both overshoots in bps.
 */
contract LIQ05_ProjectionOvershoot is YBase {
    function setUp() public {
        _boot(3 ether, 24);
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 5_000 ether);
    }

    function _buyExactOut(uint256 tokenOut) internal returns (uint256 ethSpent) {
        bytes memory r =
            pm.unlock(abi.encode(OP_SWAP, abi.encode(YSwap(true, int256(tokenOut), address(this), address(this))), _key()));
        (int128 a0,) = abi.decode(r, (int128, int128));
        ethSpent = uint256(uint128(-a0));
    }

    /// @return projBps  how far the PROJECTED sqrt price sits past spot, in bps
    /// @return realBps  how far the REAL post-trade sqrt price sits past spot, in bps
    function _measure(uint256 ethIn) internal returns (uint256 projBps, uint256 realBps) {
        uint160 s0 = _sqrtP();
        uint160 proj = PerpSwapLib.projectedSqrtPriceX96(s0, perp.activeEthDepth(), 0, -int256(ethIn), true, 0);

        uint256 snap = vm.snapshotState();
        uint256 tokenOut = _buy(ethIn, address(this));
        vm.revertToState(snap);
        _buyExactOut(tokenOut);
        uint160 s1 = _sqrtP();
        vm.revertToState(snap);

        // A buy with the quote at currency0 makes sqrtP FALL (token per quote).
        projBps = s0 > proj ? ((uint256(s0) - uint256(proj)) * 10_000) / uint256(s0) : 0;
        realBps = s0 > s1 ? ((uint256(s0) - uint256(s1)) * 10_000) / uint256(s0) : 0;
    }

    function test_LIQ05_ProjectionOvershootIsSmallAndSizeScaled() public {
        uint256[6] memory sizes =
            [uint256(0.05 ether), 0.1 ether, 0.2 ether, 0.5 ether, 1 ether, 2 ether];
        uint256 worstOvershootBps;
        uint256 measured;
        for (uint256 i; i < sizes.length; ++i) {
            (uint256 projBps, uint256 realBps) = _measure(sizes[i]);
            measured++;
            uint256 over = projBps > realBps ? projBps - realBps : 0;
            console2.log("ethIn / projected sqrtP move bps / real sqrtP move bps", sizes[i], projBps, realBps);
            console2.log("   OVERSHOOT (sqrtP bps) / ~price bps", over, over * 2);
            if (over > worstOvershootBps) worstOvershootBps = over;
        }
        console2.log("MEASURED SIZES", measured);
        console2.log("worst sqrtP overshoot (bps) / ~price overshoot (bps)", worstOvershootBps, worstOvershootBps * 2);

        assertEq(measured, sizes.length, "every size was measured");
        // The LIQ-04.B claim is "~10% on price" = 1000 bps of price = ~500 bps of sqrtP.
        assertLt(worstOvershootBps, 500, "sqrtP overshoot is well under the 500bps the finding assumes");
    }

    /// @notice DECISIVE CONTROL for LIQ-04.B. The hunter's PoC calls the 0.5 ETH
    ///         kill "premature" because `isLiquidatable` is false right after the
    ///         un-pre-swept trade. But that test is TWAP-marked and the TWAP has
    ///         not moved yet in the same block. Let the mark catch up to the price
    ///         the trade actually created (warp past `twapWindow`, poking) and ask
    ///         again: if the short IS liquidatable at the sustained post-trade
    ///         price, the pre-emptive close was CORRECT, not premature.
    function test_LIQ05_TheTradeReallyDoesSinkTheShort() public {
        uint256 col = 0.05 ether;
        vm.prank(victim);
        uint256 id = perp.openShort{value: col}(2, 0, 0, col);
        assertFalse(perp.isLiquidatable(id), "control: healthy at open");

        // Same 0.5 ETH buy, routed exact-OUTPUT so NO pre-sweep fires.
        uint256 snap = vm.snapshotState();
        uint256 tokenOut = _buy(0.5 ether, address(this));
        vm.revertToState(snap);
        _buyExactOut(tokenOut);

        (address t0,,,,,,,) = perp.positions(id);
        bool aliveSameBlock = t0 != address(0);
        bool liqSameBlock = aliveSameBlock ? perp.isLiquidatable(id) : true;

        // Let the TWAP mark converge on the new price (window is 5 minutes).
        for (uint256 i; i < 12; ++i) {
            _warp(60);
            vm.roll(block.number + 1);
            perp.poke();
        }
        (address t1,,,,,,,) = perp.positions(id);
        bool aliveAfterWarp = t1 != address(0);
        bool liqAfterWarp = aliveAfterWarp ? perp.isLiquidatable(id) : true;

        console2.log("same block: alive / isLiquidatable", aliveSameBlock, liqSameBlock);
        console2.log("after TWAP catches up: alive / isLiquidatable", aliveAfterWarp, liqAfterWarp);

        assertTrue(liqAfterWarp, "the 0.5 ETH buy DOES push the short past maintenance once the mark catches up");
    }
}
