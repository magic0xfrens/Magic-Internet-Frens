// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {T9cSeederRangeCapMisSide} from "./T9c_SeederRangeCapMisSide.t.sol";
import {SeedLib} from "../../cauldron/SeedLib.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract R23SeederRangeTracking is T9cSeederRangeCapMisSide {
    using StateLibrary for IPoolManager;

    function _assertTrackedIfFunded(int24 lo, int24 hi) internal view {
        (uint128 liq,,) = pm.getPositionInfo(pid, address(seeder), lo, hi, bytes32(0));
        bool tracked;
        for (uint256 j; j < seeder.rangeCount(); ++j) {
            (int24 a, int24 b) = seeder.ranges(j);
            if (a == lo && b == hi) tracked = true;
        }
        assertTrue(liq == 0 || tracked, "funded position must remain tracked");
    }

    function test_R23_RangeCapDivergentSpotKeepsNewPositionsTracked() public {
        (uint256 count,) = _fillRangeCap(80);
        assertEq(count, 64);
        int24[12] memory lows;
        int24[12] memory highs;
        for (uint256 i; i < 6; ++i) {
            int24 target = i % 2 == 0 ? _startTick + 10_000 : _startTick - 25_000;
            _swapTo(target);
            uint256 later = vm.getBlockTimestamp() + 25;
            vm.warp(later);
            assertEq(vm.getBlockTimestamp(), later);
            vm.roll(vm.getBlockNumber() + 1);
            uint256 beforePlaced = seeder.deployedWad();
            seeder.poke();
            assertGt(seeder.deployedWad(), beforePlaced, "each poke advances a real step");
            (, int24 tick,,) = pm.getSlot0(pid);
            (int24 ref,) = seeder.priceRef();
            (lows[2*i], highs[2*i]) = SeedLib.askBand(0, 1, ref < tick ? ref : tick, SPACING, 400);
            (lows[2*i+1], highs[2*i+1]) = SeedLib.bidBand(0, 1, ref > tick ? ref : tick, SPACING, 400);
            (uint128 askLiq,,) = pm.getPositionInfo(pid, address(seeder), lows[2*i], highs[2*i], bytes32(0));
            (uint128 bidLiq,,) = pm.getPositionInfo(pid, address(seeder), lows[2*i+1], highs[2*i+1], bytes32(0));
            assertGt(uint256(askLiq) + uint256(bidLiq), 0, "requested bands really funded");
            for (uint256 j; j <= 2*i+1; ++j) _assertTrackedIfFunded(lows[j], highs[j]);
            assertEq(seeder.rangeCount(), 64);
        }
        seeder.withdrawAll(address(this));
        for (uint256 j; j < 12; ++j) {
            (uint128 liq,,) = pm.getPositionInfo(pid, address(seeder), lows[j], highs[j], bytes32(0));
            assertEq(liq, 0, "teardown removes sampled positions");
        }
        assertEq(seeder.rangeCount(), 0);
    }
}
