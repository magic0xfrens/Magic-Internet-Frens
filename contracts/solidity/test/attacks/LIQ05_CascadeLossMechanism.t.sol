// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";

/**
 * LIQ-05 — WHERE does the 39.58 mETH of LIQ-04.D actually leave the vault, and
 * is it charged BEFORE the trade (the pre-sweep) or AFTER it (the legacy sweep)?
 *
 *  (1) The LIQ-04.D PoC reports "BadDebt booked (wei) 0" and concludes the loss
 *      "lands via settlement, not `_absorbPlvLoss`". That is a decoding bug in
 *      the PoC: `event BadDebt(uint256 shortfall, uint256 covered)`
 *      (PerpEngine.sol:507) and the PoC decodes the SECOND field, `covered`,
 *      which is zero whenever `insuranceEth` is zero. Seed the buffer and the
 *      events appear, summing to the exact vault drain.
 *
 *  (2) The attribution matters for the proposed fix. Refreshing `_projSqrtP`
 *      between kills can only move a kill from the AFTER-swap sweep into the
 *      BEFORE-swap sweep. Bad debt already booked INSIDE the pre-sweep is
 *      cascade-settlement impact that a fresher projection cannot touch. This
 *      test splits the two by log order: the user's own swap is the only
 *      PoolManager `Swap` whose `sender` is this test contract; every settlement
 *      swap is sent by the PerpEngine.
 */
contract LIQ05_CascadeLossMechanism is YBase {
    bytes32 constant BAD_DEBT = keccak256("BadDebt(uint256,uint256)");
    bytes32 constant SWAP =
        keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");

    function setUp() public {
        _boot(3 ether, 24);
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 5_000 ether);
    }

    function _openShorts(uint256 n) internal returns (uint256 opened) {
        for (uint256 i; i < n; ++i) {
            vm.prank(victim);
            perp.openShort{value: 0.05 ether}(2, 0, 0, 0.05 ether);
        }
        opened = perp.openCount();
    }

    /// @return nBd    number of BadDebt events
    /// @return total  sum of their SHORTFALL field (the first one)
    /// @return pre    shortfall booked before the user's own swap (the pre-sweep)
    /// @return post   shortfall booked after it (the legacy afterSwap sweep)
    function _split(Vm.Log[] memory logs)
        internal
        view
        returns (uint256 nBd, uint256 total, uint256 pre, uint256 post)
    {
        uint256 mainSwapIdx = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics[0] == SWAP && logs[i].topics.length > 2
                    && address(uint160(uint256(logs[i].topics[2]))) == address(this)
            ) {
                mainSwapIdx = i;
            }
        }
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == BAD_DEBT) {
                (uint256 shortfall,) = abi.decode(logs[i].data, (uint256, uint256));
                nBd++;
                total += shortfall;
                if (i < mainSwapIdx) pre += shortfall;
                else post += shortfall;
            }
        }
    }

    function test_LIQ05_FIXED_CascadeBooksNoBadDebtAtAll() public {
        uint256 opened = _openShorts(8);
        // Seed insurance so the BadDebt events carry a non-zero `covered` field
        // and PLV principal itself is shielded — isolating the measurement.
        perp.fundInsurance{value: 1 ether}(1 ether);

        uint256 plvBefore = perp.plv();
        uint256 insBefore = perp.insuranceEth();

        vm.recordLogs();
        _buy(0.8 ether, address(this));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 nBd, uint256 total, uint256 pre, uint256 post) = _split(logs);

        uint256 plvAfter = perp.plv();
        uint256 insAfter = perp.insuranceEth();
        uint256 drained = insBefore - insAfter;

        console2.log("opened / remaining", opened, perp.openCount());
        console2.log("plv before / after", plvBefore, plvAfter);
        console2.log("insurance drained (wei)", drained);
        console2.log("BadDebt events / total shortfall (wei)", nBd, total);
        console2.log("shortfall booked in the PRE-swap sweep (wei)", pre);
        console2.log("shortfall booked in the AFTER-swap sweep (wei)", post);

        assertGt(opened, 1, "control: a cascade needs more than one position");
        assertEq(perp.openCount(), 0, "control: the whole book was closed");
        //  ZERO now. This test was written to explain WHERE the cascade's drain was
        //  booked (`_absorbPlvLoss`; the original PoC decoded `covered` instead of
        //  `shortfall`, which reads 0 while insurance is empty). Per-kill
        //  re-projection plus the 1500 bps margin removed the drain itself, so
        //  there is no bad debt left to attribute.
        assertEq(nBd, 0, "no BadDebt may be booked at all now");
        assertEq(total, 0, "no shortfall");
        assertEq(drained, 0, "and nothing drained from the vault");
        assertEq(plvAfter, plvBefore, "with a buffer in front of it, LP principal is untouched");
        // THE LOAD-BEARING ATTRIBUTION. Measured: every wei of the residual is
        // booked in the AFTER-swap sweep and NONE inside the pre-sweep, i.e. the
        // pre-sweep's own cascade settled without loss and the residual is
        // entirely positions the projection failed to TRIP. That is the one
        // shape the proposed fix (refresh `_projSqrtP` between kills) can move.
        assertEq(pre, 0, "the pre-sweep's own cascade booked no bad debt");
        assertEq(post, 0, "and neither did the post-trade sweep: nothing slipped through");
    }
}
