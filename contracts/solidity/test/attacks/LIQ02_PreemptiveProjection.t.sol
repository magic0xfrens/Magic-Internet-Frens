// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

/**
 * LIQ-02 — the projection underpinning PRE-EMPTIVE liquidation must be a real
 * bound, not an estimate.
 *
 *  `PerpSwapLib.projectedSqrtPriceX96` exists so the hook can liquidate in
 *  `beforeSwap` — BEFORE the trade that would push a position into insolvency —
 *  instead of in `afterSwap`, which closes the position at the very price the
 *  trade just created. That is only safe if the projection errs in ONE
 *  direction:
 *
 *    over-project  -> liquidate marginally EARLY. A leveraged trader consented
 *                     to liquidation risk, so this is inside the deal.
 *    under-project -> the position survives the trade and becomes bad debt,
 *                     socialised onto PLV stakers by `_absorbPlvLoss`. Stakers
 *                     did NOT consent to underwriting traders.
 *
 *  So "close enough" is not the bar. The bar is: the projected move is never
 *  smaller than the move that actually happens. These tests execute real swaps
 *  against a real v4 pool and compare.
 */
contract LIQ02_PreemptiveProjection is YBase {
    function setUp() public {
        _boot(3 ether, 24);
    }

    /// @dev Projected post-swap price for an exact-INPUT buy of `ethIn`.
    function _project(uint256 ethIn) internal view returns (uint160) {
        uint160 sp = _sqrtP();
        uint256 depth = PerpSwapLib.ethDepth(_inRangeLiquidity(), sp);
        uint256 tokDepth = PerpSwapLib.ethToToken(depth, sp);
        return PerpSwapLib.projectedSqrtPriceX96(sp, depth, tokDepth, -int256(ethIn), true, 0);
    }

    /// @dev Projected post-swap price for an exact-OUTPUT buy of `tokenOut`.
    function _projectExactOut(uint256 tokenOut) internal view returns (uint160) {
        uint160 sp = _sqrtP();
        uint256 depth = PerpSwapLib.ethDepth(_inRangeLiquidity(), sp);
        uint256 tokDepth = PerpSwapLib.ethToToken(depth, sp);
        return PerpSwapLib.projectedSqrtPriceX96(sp, depth, tokDepth, int256(tokenOut), true, 0);
    }

    /**
     * LIQ-02.1 — a BUY never moves price further than projected.
     *
     *  With the quote as currency0 a buy makes the token dearer, which LOWERS
     *  sqrtPriceX96. Conservative therefore means the projection sits at or below
     *  the price the swap actually leaves behind.
     */
    function test_LIQ02_BuyProjectionIsAnUpperBoundOnTheRealMove() public {
        uint256[4] memory sizes = [uint256(0.01 ether), 0.05 ether, 0.25 ether, 1 ether];
        for (uint256 i; i < sizes.length; ++i) {
            uint160 before_ = _sqrtP();
            uint160 projected = _project(sizes[i]);

            _buy(sizes[i], address(this));
            uint160 actual = _sqrtP();

            assertLt(actual, before_, "a buy must lower sqrtP when quote is currency0");
            //  THE ASSERTION THAT MATTERS. Projected must be at least as far as
            //  actual, i.e. numerically <= actual on this side.
            assertLe(
                uint256(projected),
                uint256(actual),
                "projection UNDERSHOT the real move - stakers would eat the gap"
            );
            console2.log("buy wei", sizes[i]);
            console2.log("  before/projected/actual", uint256(before_), uint256(projected), uint256(actual));
        }
    }

    /**
     * LIQ-02.2 — a SELL never moves price further than projected.
     *
     *  Mirror of the above: a sell makes the token cheaper, which RAISES
     *  sqrtPriceX96 under this orientation, so conservative means projected >=
     *  actual.
     */
    function test_LIQ02_SellProjectionIsABoundOnTheRealMove() public {
        uint256 got = _buy(1 ether, address(this));
        assertGt(got, 0, "need inventory to sell");

        uint256 sellSize = got / 4;
        uint160 before_ = _sqrtP();
        uint256 depth = PerpSwapLib.ethDepth(_inRangeLiquidity(), before_);

        //  UNITS CANCEL, SO EVERYTHING CAN BE DONE IN ETH. Constant product gives
        //  `dT/T == dE_equiv/E`, because `E/T` IS the price — converting the token
        //  input to ETH at spot and dividing by the ETH reserve yields the very
        //  same ratio. That is why the projection only ever needs
        //  `activeEthDepth()`, which the engine already has, instead of a second
        //  token-denominated depth helper.
        //  Round the conversion UP for the same reason the library rounds its
        //  ratio up: understating the input understates the move, which is the
        //  unsafe direction. A caller converting token->ETH must do this too.
        uint256 ethEquiv = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(sellSize, 1 << 96, uint256(before_)), 1 << 96, uint256(before_)
        );
        uint160 projected =
            //  reserveOut is unused on the exact-INPUT branch, so 0 is honest here.
            PerpSwapLib.projectedSqrtPriceX96(before_, depth, 0, -int256(ethEquiv), false, 0);

        _sell(sellSize, address(this));
        uint160 actual = _sqrtP();

        assertGt(actual, before_, "a sell must raise sqrtP when quote is currency0");
        assertGe(
            uint256(projected),
            uint256(actual),
            "projection UNDERSHOT the real move on the sell side"
        );
        console2.log("sell tokens", sellSize);
        console2.log("  depthEth/ethEquivIn", depth, ethEquiv);
        console2.log("  before/projected/actual", uint256(before_), uint256(projected), uint256(actual));
    }

    /**
     * LIQ-02.3 — the built-in safety margin is actually applied.
     *
     *  `SLACK_BPS` is a library constant rather than an argument (EIP-170 in the
     *  engine), so nothing at the call site can forget it — but equally nothing at
     *  the call site would notice if it silently became zero. This pins it: the
     *  projection must overshoot the EXACT constant-product result, which is what
     *  makes the bound survive caller-side rounding.
     */
    function test_LIQ02_TheSafetyMarginIsApplied() public view {
        uint160 sp = _sqrtP();
        uint256 depth = PerpSwapLib.ethDepth(_inRangeLiquidity(), sp);
        uint256 ethIn = 0.25 ether;

        //  Exact constant-product move, no margin: sqrtP * E / (E + dE).
        uint256 exact = (uint256(sp) * depth) / (depth + ethIn);
        uint256 projected = PerpSwapLib.projectedSqrtPriceX96(sp, depth, 0, -int256(ethIn), true, 0);

        assertLt(projected, exact, "projection must overshoot the exact move, not merely match it");
    }

    /**
     * LIQ-02.5 — the EXACT-OUTPUT branch is a bound as well.
     *
     *  Exact-output is served rather than refused, because a hook that reverts on
     *  `SWAP_EXACT_OUT_SINGLE` is not routable by the Universal Router or any
     *  aggregator quoting exact-out. That only holds if its projection is as
     *  conservative as the exact-input one, so it is asserted the same way:
     *  against real swaps, at several sizes.
     */
    function test_LIQ02_ExactOutputProjectionIsAlsoABound() public {
        uint256[3] memory outs = [uint256(1_000_000e18), 20_000_000e18, 80_000_000e18];
        for (uint256 i; i < outs.length; ++i) {
            uint160 before_ = _sqrtP();
            uint160 projected = _projectExactOut(outs[i]);

            uint256 spent = _buyExactOut(outs[i], address(this));
            uint160 actual = _sqrtP();

            assertLt(actual, before_, "an exact-out buy must lower sqrtP when quote is currency0");
            assertLe(
                uint256(projected), uint256(actual),
                "exact-output projection UNDERSHOT the real move - stakers would eat the gap"
            );
            console2.log("exact-out tokens", outs[i]);
            console2.log("  ethSpent / projected / actual", spent, uint256(projected), uint256(actual));
        }
    }

    /**
     * LIQ-02.4 — degenerate inputs return the CURRENT price, not a fabricated one.
     *
     *  A zero reserve or zero size means we have nothing to stand behind. The
     *  contract must fall back to "only liquidate what is already underwater"
     *  rather than invent a projection, so the caller's behaviour degrades to
     *  today's afterSwap semantics instead of becoming random.
     */
    function test_LIQ02_DegenerateInputsFallBackToSpot() public view {
        uint160 sp = _sqrtP();
        assertEq(PerpSwapLib.projectedSqrtPriceX96(sp, 0, 0, -1 ether, true, 0), sp, "zero reserve");
        assertEq(PerpSwapLib.projectedSqrtPriceX96(sp, 1 ether, 0, 0, true, 0), sp, "zero amount");
        assertEq(PerpSwapLib.projectedSqrtPriceX96(0, 1 ether, 0, -1 ether, true, 0), 0, "zero price");
    }
}
