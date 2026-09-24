// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YNoFrens} from "../attacks/YBase.sol";
import {F14Base} from "./F14_RotationTotality.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 *  F-14c — D-1, FIXED: A REAL BOOK IS CARRIED ACROSS THE FLIP, NOT FORCE-SOLD
 *  INTO THE POOL THE ROTATION JUST DRAINED.
 *
 *  BEFORE (measured on this fork, block 11,763,300, pre-fix): the flip parked
 *  the engine and made the book force-closeable against the OLD pool, which the
 *  rotation had emptied of ~97% of its liquidity. With the largest long and short
 *  the engine would sell (0.5 ETH at 2x each), both SOLVENT at the flip:
 *    - the long was force-sold into that depth: payout 0, all 0.4655 ETH of
 *      collateral gone, plus a 0.4336 ETH shortfall the insurance fund covered;
 *    - the short then bought back into the price the long had crushed: payout
 *      1.246 ETH (+0.78) — a forced wealth transfer between solvent traders,
 *      ordered by whoever called the permissionless `forceCloseDead` first.
 *
 *  AFTER: {PerpEngine.requoteBook} carries the book. Both positions stay open
 *  through the flip; each owner closes on the deep NEW pool, in USDG. Against a
 *  CONTROL (the same closes with no rotation, via snapshot), measured:
 *    - long  992.7 USDG vs 1,016.5 control (-2.3%): the new pool is priced at
 *      the venue the rotation walked, ~4% under the oracle it was restated at;
 *    - short 1,247.5 USDG vs 1,464 control (-14.8%): its backing (~3x its
 *      collateral) was MONEY and took the swap's ~5.2% slippage, as designed —
 *      slippage stays with what was swapped, never with the stakers.
 */
contract F14c_D1ForceCloseAfterDrain is F14Base {
    PerpVault internal vault;
    address internal alice = address(0xA11CE);
    address internal longer = address(0x1011);
    address internal shorter = address(0x5401);
    address internal keeper = address(0x6EE9);

    uint256 internal longCol;
    uint256 internal shortCol;

    function setUp() public {
        _boot(20 ether, 24);
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        require(active, "F14c_D1ForceCloseAfterDrain: fork not active - PoC proved nothing");
        _bootRotation();
        hook.setDeathThreshold(0, address(oracle), 50e18, 0.05e18, 1200e18);
        perp = new PerpEngine(
            pm, address(hook), address(registry),
            address(new YNoFrens()), address(0xD1D1), address(0x7E7E), address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.setRouting(address(0xD1D1), address(0x7E7E), address(0x7E7E), address(0), address(oracle));
        vault = new PerpVault(address(perp), address(registry));
        perp.setVault(address(vault));
        deal(token, address(this), 50_000_000 ether, true);
        IERC20Minimal(token).approve(address(perp), 50_000_000 ether);
        perp.fundPlvToken(50_000_000 ether);
        perp.fundInsurance{value: 1 ether}(1 ether);
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.depositEth{value: 20 ether}();
        _warp(25 hours);
        vm.roll(block.number + 40);
        perp.poke();
    }

    /// The largest position of each side the engine sells, by halving.
    function _openMax() internal {
        vm.deal(longer, 100 ether);
        vm.deal(shorter, 100 ether);
        uint256 c = 8 ether;
        for (uint256 i; i < 12 && longCol == 0; ++i) {
            vm.prank(longer, longer);
            try perp.openLong{value: c}(2, 0, 0, c) { longCol = c; } catch { c /= 2; }
        }
        c = 8 ether;
        for (uint256 i; i < 12 && shortCol == 0; ++i) {
            vm.prank(shorter, shorter);
            try perp.openShort{value: c}(2, 0, 0, c) { shortCol = c; } catch { c /= 2; }
        }
    }

    function test_F14c_D1_FIXED_TheBookIsCarried_NotForceSold() public {
        _approveEnvelopeTo(address(usdg));
        _openMax();
        perp.poke();
        uint256 aliceBefore = _alice();
        //  CONTROL: what closing the same two positions pays with NO rotation, on
        //  the full pool, right now — so what the rotation itself costs can be
        //  told apart from what closing a max-size position always costs.
        (uint256 longBase, uint256 shortBase) = _closeBoth();
        console2.log("D1 control long  paid (wei)", longBase);
        console2.log("D1 control short paid (wei)", shortBase);
        console2.log("D1 long collateral (wei) ", longCol);
        console2.log("D1 short collateral (wei)", shortCol);
        console2.log("D1 staker value before   ", aliceBefore);
        assertEq(perp.openCount(), 2, "a real book is open across the flip");
        assertGt(longCol + shortCol, 0.1 ether, "and it is not dust");

        uint256 slices = _rotateUntilSpent(0);
        console2.log("D1 slices                ", slices);
        assertEq(registry.generationQuote(1), address(usdg), "the rotation completed");

        //  THE FIX: nothing was force-closed. Both positions ride the flip.
        assertEq(perp.quote(), address(usdg), "the engine adopted USDG in the flipping slice");
        assertEq(perp.openCount(), 2, "FIXED D-1: both positions are still open");
        assertFalse(perp.isLiquidatable(1) || perp.isLiquidatable(2), "and both are still solvent");
        uint256 insAfterFlip = perp.insuranceEth();
        console2.log("D1 staker value after flip (usdg)", _alice());

        //  Their owners close them on the DEEP new pool, when they choose.
        vm.roll(vm.getBlockNumber() + 200); // past the new leg's launch surtax
        _warp(perp.twapWindow() + 1);
        perp.poke();
        vm.prank(longer, longer);
        perp.close(1, 0);
        vm.prank(shorter, shorter);
        perp.close(2, 0);
        uint256 longPaid = usdg.balanceOf(longer);
        uint256 shortPaid = usdg.balanceOf(shorter);
        console2.log("D1 long  paid (usdg)", longPaid);
        console2.log("D1 short paid (usdg)", shortPaid);

        //  Against the CONTROL, in oracle USDG. Pre-fix the long got 0 and the
        //  short 2.68x its collateral — a transfer of ~100% of the long's stake.
        //  What remains is the rotation's own price effect: its slices price the
        //  new pool at the venue's walked rate (~4% under the oracle both
        //  positions were restated at), which a 2x long loses and a 2x short gains.
        uint256 longCtl = longBase * 3000e6 / 1 ether;
        uint256 shortCtl = shortBase * 3000e6 / 1 ether;
        console2.log("D1 rotation cost to long  (bps)", longCtl > longPaid ? (longCtl - longPaid) * 10_000 / longCtl : 0);
        console2.log("D1 rotation gain to short (bps)", shortPaid > shortCtl ? (shortPaid - shortCtl) * 10_000 / shortCtl : 0);
        assertGe(longPaid, longCtl * 75 / 100, "FIXED D-1: the long keeps >= 75% of what closing pays anyway (was 0)");
        assertLe(shortPaid, shortCtl * 125 / 100, "FIXED D-1: the short gains <= 25% over closing anyway (was 2.7x collateral)");
        //  Insurance may pay FUNDING owed to a trader (by design); what D-1 drew was
        //  a 0.4336 ETH shortfall — 43% of the fund. Bounded at 0.1%.
        assertLe(insAfterFlip - perp.insuranceEth(), insAfterFlip / 1000, "insurance paid at most funding dust");
        assertEq(perp.unabsorbedEth(), 0, "no bad debt");
    }

    /// Close both at today's price on the untouched pool, report, and roll back.
    function _closeBoth() internal returns (uint256 longPaid, uint256 shortPaid) {
        uint256 snap = vm.snapshotState();
        uint256 lb = longer.balance;
        uint256 sb = shorter.balance;
        vm.prank(longer, longer);
        perp.close(1, 0);
        vm.prank(shorter, shorter);
        perp.close(2, 0);
        longPaid = longer.balance - lb;
        shortPaid = shorter.balance - sb;
        vm.revertToState(snap);
    }

    function _alice() internal view returns (uint256 v) {
        (v,,) = vault.ethPosition(alice);
    }
}
