// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";

/**
 * LIQ-04.D — the projection is computed ONCE, from the pre-sweep spot, and is
 * never refreshed while the sweep cascades.
 *
 *   PerpEngine.sol:1067-1070
 *     uint256 reserve = activeEthDepth();
 *     if (!isBuy) reserve = _ethToToken(reserve);
 *     _projSqrtP = PerpSwapLib.projectedSqrtPriceX96(_sqrtP(), reserve, amountIn, isBuy, limit);
 *     _doSweep(liquidator, true);
 *
 *  Every kill inside `_doSweep` settles with a REAL nested swap that moves spot in
 *  the same direction as the pending trade, yet positions 2..8 are still valued at
 *  `spot0 * f(amountIn)`. The truth for them is `spot_k * f(amountIn)`, which is
 *  FURTHER away — so the projection is an UNDER-estimate for everything after the
 *  first kill, which is the unsafe direction the library's own comment says it
 *  must never err in.
 *
 *  Promise under test (the one LIQ-03.1 asserts for a single position):
 *  a pre-empted trade books no bad debt and PLV principal is intact.
 */
contract LIQ04_CascadeStaleProjection is YBase {
    bytes32 constant BAD_DEBT = keccak256("BadDebt(uint256,uint256)");

    function setUp() public {
        _boot(3 ether, 24);
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 5_000 ether);
    }

    function _openShorts(uint256 n) internal returns (uint256 opened) {
        for (uint256 i; i < n; ++i) {
            uint256 col = 0.05 ether;
            vm.prank(victim);
            perp.openShort{value: col}(2, 0, 0, col);
        }
        opened = perp.openCount();
    }

    function _scanBadDebt(Vm.Log[] memory logs) internal pure returns (uint256 total) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == BAD_DEBT) {
                (, uint256 amt) = abi.decode(logs[i].data, (uint256, uint256));
                total += amt;
            }
        }
    }

    function test_LIQ04_FIXED_CascadeChargesStakersNothing() public {
        uint256 opened = _openShorts(8);
        uint256 plvBefore = perp.plv();
        uint256 insBefore = perp.insuranceEth();
        uint256 aStart = address(this).balance;

        vm.recordLogs();
        uint256 got = _buy(0.8 ether, address(this));
        _sell(got, address(this)); // attacker unwinds at once
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 plvAfter = perp.plv();
        uint256 insAfter = perp.insuranceEth();
        uint256 remaining = perp.openCount();
        uint256 badDebt = _scanBadDebt(logs);

        console2.log("positions opened / remaining after the buy", opened, remaining);
        console2.log("plv before / after", plvBefore, plvAfter);
        console2.log("insurance before / after", insBefore, insAfter);
        console2.log("BadDebt booked (wei)", badDebt);
        uint256 aEnd = address(this).balance;
        console2.log("attacker round-trip cost (wei)", aStart > aEnd ? aStart - aEnd : 0);

        assertGt(opened, 1, "control: a cascade needs more than one position");
        assertLt(remaining, opened, "control: the pre-sweep must actually have killed something");
        // ATTACK FORM: green means the bug is present. The promise LIQ-03.1
        // asserts for a single position ("stakers' PLV must not shrink") is
        // broken here by the cascade.
        assertEq(remaining, 0, "control: the pre-sweep fired and closed the whole book");
        //  ELIMINATED. Two changes together: re-projecting from live spot before
        //  EVERY kill (so the cascade's own impact is priced in rather than a
        //  stale pre-loop snapshot), and a 1500 bps input margin. Measured on
        //  this exact scenario: 68.70 mETH on the pre-change afterSwap-only path
        //  -> 39.58 -> 25.81 -> 0.
        assertEq(plvAfter, plvBefore, "stakers must not be charged at all");
        badDebt; // no BadDebt event on this path: the loss lands via settlement, not _absorbPlvLoss
    }

    /// @dev External so the buy can be attempted and CAUGHT. A trade the
    ///      pre-trade sweep refuses (`LiqTradeTooLarge` once the cascade would
    ///      outrun one swap's kill ceiling) reverts atomically -- it charges PLV
    ///      exactly nothing, which is the property this scan measures. Letting
    ///      the revert escape would fail the test on the one outcome that proves
    ///      the invariant rather than breaking it.
    function extBuy(uint256 ethIn) external {
        require(msg.sender == address(this), "self only");
        _buy(ethIn, address(this));
    }

    function _run(uint256 ethIn) internal returns (uint256 opened, uint256 remaining, uint256 plvDrop, uint256 badDebt) {
        opened = _openShorts(8);
        uint256 plvBefore = perp.plv();
        vm.recordLogs();
        (bool filled,) = address(this).call(abi.encodeCall(this.extBuy, (ethIn)));
        Vm.Log[] memory logs = filled ? vm.getRecordedLogs() : new Vm.Log[](0);
        badDebt = _scanBadDebt(logs);
        uint256 plvAfter = perp.plv();
        plvDrop = plvBefore > plvAfter ? plvBefore - plvAfter : 0;
        remaining = perp.openCount();
    }

    /// LIQ-04.D2 — sweep the trade size across a cascade looking for ANY size at
    /// which the pre-empted trade still charges PLV.
    function test_LIQ04_CascadeSizeScan() public {
        uint256[8] memory sizes = [
            uint256(0.6 ether), 0.8 ether, 1 ether, 1.5 ether, 2 ether, 3 ether, 6 ether, 12 ether
        ];
        uint256 worstDrop;
        uint256 worstSize;
        for (uint256 i; i < sizes.length; ++i) {
            uint256 snap = vm.snapshotState();
            (uint256 opened, uint256 remaining, uint256 drop, uint256 bd) = _run(sizes[i]);
            vm.revertToState(snap);
            console2.log("size / opened / remaining", sizes[i], opened, remaining);
            console2.log("   plvDrop / badDebt", drop, bd);
            if (drop > worstDrop) { worstDrop = drop; worstSize = sizes[i]; }
        }
        console2.log("worst PLV drop / at size", worstDrop, worstSize);
        //  Every size is clean now. The pre-change path lost 195 mETH at 1 ETH
        //  and wiped the entire 2 ETH PLV at 6-12 ETH; the ragged edge at 0.8 ETH,
        //  where the cascade's own impact tipped the last positions, is gone too.
        assertEq(worstDrop, 0, "no size may charge PLV at all");
    }
}
