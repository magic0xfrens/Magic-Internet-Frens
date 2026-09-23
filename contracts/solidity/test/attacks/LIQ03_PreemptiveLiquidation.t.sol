// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";

/**
 * LIQ-03 — PRE-EMPTIVE liquidation: the hook closes a position BEFORE the trade
 * that would sink it, at the pre-trade price, so the loss never exists.
 *
 *  Before this, the only sweep ran in `afterSwap`: a large buy carried a short
 *  from healthy to insolvent INSIDE the trade, and the sweep then closed it into
 *  the price that trade had just created — bad debt, socialised onto PLV stakers
 *  by `_absorbPlvLoss`. Now `beforeSwap` projects where the pending swap will
 *  leave the price (conservatively — LIQ-02) and closes anything that projection
 *  puts past maintenance, while it is still solvent.
 *
 *  Three properties, each a separate test because each can fail on its own:
 *    1. it fires, and it fires BEFORE the user's swap executes;
 *    2. it cannot be used to grief — a huge nominal with a limit at spot fills
 *       nothing and must liquidate nothing;
 *    3. property 2 is not just pre-emption being off — the same nominal with a
 *       real limit DOES liquidate.
 */
contract LIQ03_PreemptiveLiquidation is YBase {
    bytes32 constant LIQUIDATED = keccak256("Liquidated(uint256,address,uint256)");
    bytes32 constant BAD_DEBT = keccak256("BadDebt(uint256,uint256)");
    bytes32 constant SWAP = keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");

    function setUp() public {
        _boot(3 ether, 24);
        require(active, "LIQ03_PreemptiveLiquidation: fork not active - PoC proved nothing");
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 3_000 ether);
    }

    /// A 2x short sized under the notional cap, healthy at the TWAP mark.
    function _openHealthyShort() internal returns (uint256 id) {
        uint256 col = 0.05 ether;
        id = perp.openShort{value: col}(2, 0, 0, col);
        assertFalse(perp.isLiquidatable(id), "short must start healthy");
    }

    function _lastIndexOf(Vm.Log[] memory logs, bytes32 topic) internal pure returns (int256 idx) {
        idx = -1;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == topic) idx = int256(i);
    }
    function _firstIndexOf(Vm.Log[] memory logs, bytes32 topic) internal pure returns (int256 idx) {
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == topic) return int256(i);
        return -1;
    }

    /**
     * LIQ-03.1 — the short is closed before the buy that would have sunk it,
     * and no bad debt is booked.
     */
    function test_LIQ03_ShortIsClosedBeforeTheBuyThatWouldSinkIt() public {
        uint256 id = _openHealthyShort();
        (, , uint128 collateral, uint256 size, uint256 principal, , , ) = perp.positions(id);
        uint256 backing = uint256(collateral) + principal;
        uint256 plvBefore = perp.plv();

        vm.recordLogs();
        _buy(1 ether, address(this));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        //  (a) It fired: the position is gone.
        (address trader, , , , , , , ) = perp.positions(id);
        assertEq(trader, address(0), "position should have been liquidated");

        //  (b) It fired BEFORE the user's swap: the Liquidated log precedes the
        //      LAST Swap log, which is the user's own (the sweep's settlement swap
        //      is an earlier, nested one).
        int256 liq = _firstIndexOf(logs, LIQUIDATED);
        int256 userSwap = _lastIndexOf(logs, SWAP);
        assertGt(liq, -1, "no Liquidated event");
        assertLt(liq, userSwap, "liquidation must precede the user's swap, not follow it");

        //  (c) The trade WOULD have made it insolvent — so this was not a free
        //      kill of a healthy position. Value the short's obligation at the
        //      price the trade actually left behind.
        uint256 valueAtPost = PerpSwapLib.quoteAt(size, _sqrtP());
        assertGt(valueAtPost, backing, "control: the buy really would have sunk this short");

        //  (d) And the loss never existed: no BadDebt, PLV principal intact.
        assertEq(_firstIndexOf(logs, BAD_DEBT), -1, "BadDebt was booked");
        assertGe(perp.plv(), plvBefore, "stakers' PLV must not shrink");
        console2.log("backing / value-if-not-preempted", backing, valueAtPost);
    }

    /**
     * LIQ-03.2 — a huge nominal with a limit at spot cannot be used to liquidate.
     *
     *  Without the limit clamp, `amountSpecified = 1000 ETH` would project a
     *  4x move and trip every short for the price of a dust fill. The PoolManager
     *  will not move price past the limit, so neither may the projection.
     */
    function test_LIQ03_TightLimitCannotGriefLiquidations() public {
        uint256 id = _openHealthyShort();
        uint256 openBefore = perp.openCount();

        uint160 limit = _sqrtP() - 1; // one wei below spot: fills essentially nothing
        uint256 got = _buyWithLimit(1_000 ether, limit, attacker);

        assertLt(got, 1e15, "the griefing swap should barely fill");
        (address trader, , , , , , , ) = perp.positions(id);
        assertEq(trader, address(this), "a tight-limit swap must not liquidate a healthy short");
        assertEq(perp.openCount(), openBefore, "open count unchanged");
    }

    /**
     * LIQ-03.3 — control for 03.2: the same nominal with a REAL limit liquidates.
     *  Proves the previous test passed because of the clamp, not because
     *  pre-emption was silently inert.
     */
    function test_LIQ03_ControlRealFillDoesLiquidate() public {
        uint256 id = _openHealthyShort();
        _buyWithLimit(1_000 ether, MIN_LIMIT, attacker);
        (address trader, , , , , , , ) = perp.positions(id);
        assertEq(trader, address(0), "a real fill of that size must liquidate the short");
    }
}
