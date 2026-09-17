// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";

/**
 * LIQ-04.A — the pre-emptive sweep is bypassable by routing the identical
 * economic buy as EXACT OUTPUT.
 *
 *  CauldronHook._beforeSwap gates the pre-sweep on `if (exactInput)`, so an
 *  exact-output BUY (amountSpecified > 0, input is the quote) — a first-class,
 *  fully-served quadrant that still pays its fee in `_afterSwap` — reaches the
 *  PoolManager with no projection and no pre-emption. The short is carried
 *  through the trade and closed AFTER it, into the price the trade just made:
 *  exactly the bad-debt path pre-emption exists to remove.
 *
 *  The test runs the SAME trade twice from the SAME snapshot, once per route,
 *  and compares. Every branch lives in a helper returning values; the top-level
 *  test body is straight-line and ends in assertions.
 */
contract LIQ04_ExactOutBypass is YBase {
    bytes32 constant BAD_DEBT = keccak256("BadDebt(uint256,uint256)");
    bytes32 constant LIQUIDATED = keccak256("Liquidated(uint256,address,uint256)");

    struct Outcome {
        bool positionSurvivedBeforeSwap; // liquidation happened, but only post-trade
        bool badDebt;
        uint256 badDebtWei;
        uint256 plvBefore;
        uint256 plvAfter;
        uint256 ethIn;
        uint256 tokenOut;
    }

    function setUp() public {
        _boot(3 ether, 24);
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 3_000 ether);
    }

    function _openHealthyShort() internal returns (uint256 id) {
        uint256 col = 0.05 ether;
        id = perp.openShort{value: col}(2, 0, 0, col);
    }

    /// @dev Exact-OUTPUT buy: amountSpecified > 0 with zeroForOne (quote in).

    function _scanBadDebt(Vm.Log[] memory logs) internal pure returns (bool found, uint256 wei_) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == BAD_DEBT) {
                found = true;
                (, uint256 amt) = abi.decode(logs[i].data, (uint256, uint256));
                wei_ += amt;
            }
        }
    }

    function _routeExactIn(uint256 ethIn) internal returns (Outcome memory o) {
        uint256 id = _openHealthyShort();
        o.plvBefore = perp.plv();
        vm.recordLogs();
        o.tokenOut = _buy(ethIn, address(this));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (o.badDebt, o.badDebtWei) = _scanBadDebt(logs);
        o.plvAfter = perp.plv();
        o.ethIn = ethIn;
        (address t, , , , , , , ) = perp.positions(id);
        o.positionSurvivedBeforeSwap = t != address(0);
    }

    function _routeExactOut(uint256 tokenOut) internal returns (Outcome memory o) {
        uint256 id = _openHealthyShort();
        o.plvBefore = perp.plv();
        vm.recordLogs();
        o.ethIn = _buyExactOut(tokenOut, address(this));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (o.badDebt, o.badDebtWei) = _scanBadDebt(logs);
        o.plvAfter = perp.plv();
        o.tokenOut = tokenOut;
        (address t, , , , , , , ) = perp.positions(id);
        o.positionSurvivedBeforeSwap = t != address(0);
    }

    /**
     * FIXED (LIQ04-A): exact-output buys are PROJECTED, not refused.
     *
     *  Refusing them would have been unroutable — `SWAP_EXACT_OUT_SINGLE` from
     *  the Universal Router, and any aggregator quoting exact-out, would revert
     *  against this pool — and it also bricked the protocol's own relaunch green
     *  candle and short buy-back, which are exact-output buys by design. So the
     *  signed `amountSpecified` crosses to the engine instead and the projection
     *  derives the input from the output: dIn = rIn*dOut/(rOut-dOut).
     *
     *  Both routes must now behave identically: the short is pre-empted and
     *  stakers are untouched.
     */
    function test_LIQ04_FIXED_exactOutputBuyIsProjectedToo() public {
        uint256 snap = vm.snapshotState();
        Outcome memory inRoute = _routeExactIn(1 ether);
        vm.revertToState(snap);
        Outcome memory outRoute = _routeExactOut(inRoute.tokenOut);

        console2.log("exact-IN  ethIn/tokenOut", inRoute.ethIn, inRoute.tokenOut);
        console2.log("exact-IN  plv before/after", inRoute.plvBefore, inRoute.plvAfter);
        console2.log("exact-OUT ethIn/tokenOut", outRoute.ethIn, outRoute.tokenOut);
        console2.log("exact-OUT plv before/after", outRoute.plvBefore, outRoute.plvAfter);

        assertEq(outRoute.tokenOut, inRoute.tokenOut, "control: same tokens acquired");
        assertFalse(inRoute.badDebt, "control: exact-input route books no bad debt");
        assertGe(inRoute.plvAfter, inRoute.plvBefore, "control: exact-input route does not shrink PLV");

        //  THE FIX: the exact-output route is no longer the unprojected quadrant.
        assertFalse(outRoute.positionSurvivedBeforeSwap, "the short must be pre-empted on the exact-output route");
        assertFalse(outRoute.badDebt, "exact-output route must not book bad debt");
        assertGe(outRoute.plvAfter, outRoute.plvBefore, "exact-output route must not charge stakers");
    }
}
