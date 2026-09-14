// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";

/// @dev Calls back into the test with a HARD gas cap, so the 63/64 rule and the
///      hook's own `gasleft()` guards apply exactly as they would on chain.
contract LIQ04Runner {
    function run(address t, uint256 gasCap, uint256 ethIn) external returns (bool ok) {
        (ok, ) = t.call{gas: gasCap}(abi.encodeWithSignature("doBuy(uint256)", ethIn));
    }
}

/**
 * LIQ-04.C — gas. The PRE-sweep runs inside `_beforeSwap` and is forwarded
 * `gasleft() - (LIQ_GAS_RESERVE + LIQ_GAS_MIN)` = everything above 580k. If a
 * heavy sweep (up to MAX_LIQ_PER_SWAP = 8 settlement swaps) consumes its whole
 * budget, the user's OWN swap plus the entire `_afterSwap` (volume, USD oracle,
 * credit, post-sweep, gacha, fee take) must finish inside that 580k.
 *
 * The question this answers: is there a gas limit at which the identical buy
 * SUCCEEDS with no liquidatable positions but REVERTS once positions exist —
 * i.e. the "best effort, never reverts the swap" promise broken by an attacker
 * who pre-arranges liquidatable shorts.
 */
contract LIQ04_GasStarve is YBase {
    LIQ04Runner internal runner;

    function setUp() public {
        _boot(3 ether, 24);
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 5_000 ether);
        runner = new LIQ04Runner();
    }

    function doBuy(uint256 ethIn) external {
        require(msg.sender == address(runner), "runner");
        _buy(ethIn, address(this));
    }

    function _openShorts(uint256 n) internal {
        for (uint256 i; i < n; ++i) {
            uint256 col = 0.05 ether;
            vm.prank(victim);
            perp.openShort{value: col}(2, 0, 0, col);
        }
    }

    /// @return minGas the lowest gas cap (of the ladder) at which the buy succeeds
    function _minGasFor(uint256 shorts, uint256 ethIn)
        internal
        returns (uint256 minGas, uint256 opened, bool failAbove, uint256 kills)
    {
        uint256[10] memory ladder = [
            uint256(400_000), 600_000, 800_000, 1_000_000, 1_500_000,
            2_000_000, 3_000_000, 5_000_000, 8_000_000, 15_000_000
        ];
        for (uint256 i; i < ladder.length; ++i) {
            uint256 snap = vm.snapshotState();
            if (shorts > 0) _openShorts(shorts);
            opened = perp.openCount();
            bool ok = runner.run(address(this), ladder[i], ethIn);
            uint256 left = perp.openCount();
            vm.revertToState(snap);
            console2.log("  cap / ok / openAfter", ladder[i], ok, left);
            if (ok && minGas == 0) minGas = ladder[i];
            if (!ok && minGas != 0) failAbove = true;
            if (ok && opened > left && left + kills != opened) kills = opened - left;
        }
    }

    function test_LIQ04_PreSweepDoesNotStarveTheUsersSwap() public {
        (uint256 baselineGas, , bool baseFailAbove, ) = _minGasFor(0, 3 ether);
        (uint256 loadedGas, uint256 opened, bool loadedFailAbove, uint256 kills) = _minGasFor(8, 3 ether);

        console2.log("open positions in the loaded run", opened);
        console2.log("kills seen at some cap", kills);
        console2.log("min gas: clean pool / loaded", baselineGas, loadedGas);
        console2.log("non-monotonic failure above minGas: base / loaded", baseFailAbove, loadedFailAbove);
        assertFalse(baseFailAbove, "control: clean pool never fails above its minimum");
        assertFalse(loadedFailAbove, "a higher gas cap must never turn a working buy into a revert");
        assertGt(kills, 0, "control: the loaded run must actually liquidate something");

        assertGt(baselineGas, 0, "control: the buy must succeed somewhere on the ladder with no perps");
        assertGt(loadedGas, 0, "the buy must still succeed somewhere on the ladder with 8 shorts open");
        assertLe(
            loadedGas, baselineGas * 4,
            "pre-sweep multiplies the gas a plain buy needs by more than 4x"
        );
    }
}
