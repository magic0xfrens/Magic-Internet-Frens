// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ZAuditBase} from "./ZAuditBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

/**
 * FINDING Z-01 (High) — the hook's ETH fee is skipped entirely for EXACT-OUTPUT
 * SELLS, and the swapper still accrues full crystal credit.
 *
 * CauldronHook._afterSwap:
 *     bool exactInput      = params.amountSpecified < 0;
 *     bool unspecifiedIsEth = exactInput ? (!params.zeroForOne) : (params.zeroForOne);
 *     if (!unspecifiedIsEth) return (BaseHook.afterSwap.selector, 0);
 *
 * The four swap quadrants resolve as:
 *   exact-in  buy  (amt<0, z4o=1) -> unspecifiedIsEth=false -> charged in _beforeSwap  OK
 *   exact-in  sell (amt<0, z4o=0) -> unspecifiedIsEth=true  -> charged in _afterSwap   OK
 *   exact-out buy  (amt>0, z4o=1) -> unspecifiedIsEth=true  -> charged in _afterSwap   OK
 *   exact-out sell (amt>0, z4o=0) -> unspecifiedIsEth=FALSE -> early return            <-- and
 *                                    _beforeSwap already skipped it (`!exactInput`)
 *
 * So the ONE quadrant nobody charged was the exact-output sell — reachable by any
 * direct PoolManager caller and a standard aggregator route.
 *
 * STATUS: FIXED. `_beforeSwap` now rejects the quadrant outright
 * (`ExactOutSellUnsupported`), because V4's afterSwap return delta applies to the
 * UNSPECIFIED currency — which is the TOKEN here — so an ETH fee physically cannot be
 * taken on that leg, and the hook is ETH-fee-only by design. Exact-INPUT sells are the
 * economically equivalent route and are unaffected.
 *
 * The tests below are the regression suite: they drive the original exploit and assert
 * it is now blocked, with the three legitimate quadrants still charged.
 */
contract Z01_ExactOutSellFeeBypass is ZAuditBase {
    address internal token;
    PoolId internal pid;

    function setUp() public {
        _bootstrap(1 ether);
        if (!active) return;
        (token, pid) = registry.summon{value: 5 ether}();
        // Clear the launch surtax so the measured fee is the flat 3% base tax only.
        vm.roll(block.number + hook.snipeWindowBlocks() + 1);
    }

    /// REGRESSION: the exploit route is now refused instead of served fee-free.
    function test_FIXED_ExactOutputSell_IsRejected() public {
        if (!active) return;

        // Acquire inventory with a normal (taxed) buy.
        uint256 bought = _buyExactIn(1 ether);
        assertGt(bought, 0, "acquired inventory");

        // --- control: an EXACT-INPUT sell pays the fee ---
        uint256 sellSize = bought / 8;
        uint256 bankedBefore = hook.relaunchETH();
        uint256 ethOutTaxed = _sellExactIn(sellSize);
        uint256 feeTaxed = hook.relaunchETH() - bankedBefore;
        assertGt(feeTaxed, 0, "control: exact-input sell IS taxed");
        assertGt(ethOutTaxed, 0, "control: received ETH");

        // --- exploit: the SAME economic trade routed as exact-OUTPUT is refused ---
        bankedBefore = hook.relaunchETH();
        vm.expectRevert(); // CauldronHook.ExactOutSellUnsupported
        this.sellExactOutExternal(ethOutTaxed);
        assertEq(hook.relaunchETH(), bankedBefore, "no state moved on the rejected route");

        emit log_named_uint("fee paid, exact-input sell (wei)", feeTaxed);
        emit log_named_uint("tokens spent, exact-input      ", sellSize);
    }

    /// REGRESSION: the un-taxed quadrant also used to mint free crystal (NFT) credit,
    /// because the credit accrual in `_afterSwap` runs BEFORE the fee branch returns.
    /// The whole route is now rejected, so no credit can be farmed through it.
    function test_FIXED_ExactOutputSell_MintsNoFreeCredit() public {
        if (!active) return;
        _buyExactIn(1 ether);

        uint256 creditBefore = hook.creditOf(address(this));
        uint256 lifeBefore = hook.lifetimeVolumeOf(address(this));

        vm.expectRevert(); // CauldronHook.ExactOutSellUnsupported
        this.sellExactOutExternal(0.05 ether);

        assertEq(hook.creditOf(address(this)), creditBefore, "no free crystal credit");
        assertEq(hook.lifetimeVolumeOf(address(this)), lifeBefore, "no free lifetime volume");
    }

    /// The three other quadrants ARE charged — this pins the bug to exactly one
    /// branch and proves the finding is not a harness artefact.
    function test_SAFE_OtherThreeQuadrantsAreCharged() public {
        if (!active) return;

        uint256 b0 = hook.relaunchETH();
        _buyExactIn(0.5 ether);
        assertGt(hook.relaunchETH() - b0, 0, "exact-in buy charged");

        uint256 have = IERC20(token).balanceOf(address(this));
        b0 = hook.relaunchETH();
        _buyExactOut(have / 100); // exact-output BUY
        assertGt(hook.relaunchETH() - b0, 0, "exact-out buy charged");

        b0 = hook.relaunchETH();
        _sellExactIn(IERC20(token).balanceOf(address(this)) / 20);
        assertGt(hook.relaunchETH() - b0, 0, "exact-in sell charged");
    }
}
