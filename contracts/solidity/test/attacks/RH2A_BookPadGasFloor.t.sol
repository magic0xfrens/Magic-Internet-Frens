// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";

/**
 * RH2A — the completeness flag turns the perp book into a pool-wide gas tax.
 *
 * `PerpEngine._doSweep` no longer caps the scan positionally; it scans the whole
 * (<=64) book and returns `complete == false` if it stops on SWEEP_KILL_RESERVE.
 * `CauldronHook._liqSweep` turns that into `revert LiqGasStarved()` on the
 * PRE-trade call. So the minimum gas ANY swap on the pool must carry scales with
 * the number of open perp positions — which is permissionless to grow.
 *
 * This test measures the minimum gas a plain buy needs with an empty book and
 * with a padded book, both against the real contracts on a fork.
 */
contract RH2A_BookPadGasFloor is YBase {
    uint256 internal minGasEmpty;
    uint256 internal minGasPadded;
    uint256 internal padded;
    bool internal ran;

    /// external so we can cap the gas forwarded to it
    function doBuy(uint256 ethIn) external {
        require(msg.sender == address(this), "self");
        _buy(ethIn, attacker);
    }

    /// @dev Smallest gas cap (to 25k) at which a 0.05 ETH buy succeeds.
    function _minGasForBuy() internal returns (uint256) {
        uint256 lo = 150_000;
        uint256 hi = 9_000_000;
        // confirm hi works at all
        if (!_tryBuy(hi)) return type(uint256).max;
        while (hi - lo > 25_000) {
            uint256 mid = (lo + hi) / 2;
            if (_tryBuy(mid)) hi = mid; else lo = mid;
        }
        return hi;
    }

    function _tryBuy(uint256 g) internal returns (bool ok) {
        uint256 snap = vm.snapshotState();
        (ok,) = address(this).call{gas: g}(abi.encodeWithSelector(this.doBuy.selector, uint256(0.05 ether)));
        vm.revertToState(snap);
    }

    function _pad(uint256 n) internal returns (uint256 made) {
        vm.deal(attacker, 10_000 ether);
        for (uint256 i = 0; i < n; i++) {
            vm.prank(attacker);
            (bool ok,) = address(perp).call{value: 0.02 ether, gas: 3_000_000}(
                abi.encodeWithSignature("openLong(uint8,uint256,uint256,uint256)", uint8(2), uint256(0), uint256(0), uint256(0.02 ether))
            );
            if (!ok) break;
            made++;
        }
    }

    function _run() internal {
        _boot(30 ether, 0);
        if (!active) return;
        _bootPerp(40 ether, 2_000_000 ether);
        ran = true;

        minGasEmpty = _minGasForBuy();
        padded = _pad(64);
        minGasPadded = _minGasForBuy();

        console2.log("open positions padded:", padded);
        console2.log("min gas, empty book :", minGasEmpty);
        console2.log("min gas, padded book:", minGasPadded);
    }

    function test_RH2A_bookPadding_raises_the_gas_floor_of_every_swap() public {
        _run();
        assertTrue(ran, "fork harness did not boot (FORK_RPC unset?)");
        assertGt(padded, 8, "attacker could not pad the book");
        assertLt(minGasEmpty, type(uint256).max, "empty-book buy never succeeded");
        assertLt(minGasPadded, type(uint256).max, "padded-book buy never succeeded at 9M");
        // The finding: the floor is not a constant, it is a function of a
        // permissionlessly growable list.
        assertGt(minGasPadded, minGasEmpty * 2, "padded book did not raise the floor");
    }
}
