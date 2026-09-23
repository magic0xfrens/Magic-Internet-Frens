// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YNoFrens} from "./YBase.sol";
import {F14Base} from "../functional/F14_RotationTotality.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  RQ-1 — ADVERSARIAL PASS ON THE CARRIED BOOK (PerpEngine.requoteBook)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  Each test is an ATTACK, executed on the pinned fork. A test named `_HOLDS`
 *  asserts the defence; one named `_MEASURED` pins a residual that is bounded
 *  but real, so a change to it is a deliberate edit, not a silent drift.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract RQ1_CarriedBookAdversarial is F14Base {
    PerpVault internal vault;
    address internal alice = address(0xA11CE);

    function setUp() public {
        _boot(20 ether, 24);
        require(active, "RQ1_CarriedBookAdversarial: fork not active - PoC proved nothing");
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
        vault.depositEth{value: 10 ether}();
        _warp(25 hours);
        vm.roll(block.number + 40);
        perp.poke();
    }

    function _flipToUsdg() internal returns (uint256 slices) {
        _approveEnvelopeTo(address(usdg));
        slices = _rotateUntilSpent(0);
    }

    // ── A1: an owed payout to a contract that refuses ether blocks the flip ────

    /**
     *  `requoteBook` refuses while `payoutOwedTotal != 0` — owed payouts live in
     *  a per-address mapping no loop can re-express. An attacker contract whose
     *  `receive` reverts turns its own close into an owed payout and so holds the
     *  mandate-completing slice hostage. Remedy: the owner's `retirePayout`
     *  write-off (a timelock call). MEASURED: cost to the attacker, and that the
     *  remedy restores liveness.
     */
    function test_A1_MEASURED_RefusingRecipientDelaysTheFlip() public {
        _approveEnvelopeTo(address(usdg));
        RQRefuser r = new RQRefuser(perp);
        vm.deal(address(r), 1 ether);
        uint256 col = perp.minCollateral() * 2;
        uint256 before = address(r).balance;
        uint256 id = r.openLong(col);
        r.setRefuse(true);
        r.close(id);
        uint256 owed = perp.payoutOwed(address(r));
        console2.log("A1 attacker spent (wei)       ", before - address(r).balance);
        console2.log("A1 payout left owed (wei)     ", owed);
        assertGt(owed, 0, "the refusing close left a payout owed");

        uint256 slices = _rotateUntilSpent(0);
        console2.log("A1 slices before the block    ", slices);
        assertEq(registry.generationQuote(1), address(0), "MEASURED: the flip is held while the payout is owed");
        assertEq(perp.quote(), address(0), "and nothing was converted");

        //  The owner writes it off (the attacker forfeits it) and the flip lands.
        perp.retirePayout(address(r));
        _rotateUntilSpent(0);
        assertEq(registry.generationQuote(1), address(usdg), "the owner remedy restores the flip");
        assertEq(perp.quote(), address(usdg), "and the book is carried");
    }

    // ── A2: sandwich the conversion at the flip ────────────────────────────────

    /**
     *  The flipping slice swaps the engine's money through the venue at whatever
     *  price the venue shows — floored by the rotator's oracle band. Anyone may
     *  call `rotateSlice`, so an attacker can push the venue, trigger the flip,
     *  and unwind, atomically. MEASURED at the rotator's DEFAULT 3% band (the
     *  harnesses widen it to 20%).
     */
    function test_A2_MEASURED_SandwichTheFlipAtTheDefaultFloor() public {
        _approveEnvelopeTo(address(usdg));
        for (uint256 i; i < 11; ++i) registry.rotateSlice(2500, 0, route);
        (, uint16 left) = tgov.allowance();
        assertGt(left, 0, "one slice left: the flip");
        //  Arbitrage between slices, which a real venue has and this one does not:
        //  bring the venue back to the oracle before the flip.
        _arbVenueToOracle();
        rotator.setRotationSlipBps(300);                 // the deployed default band
        uint256 pot = perp.plv() + perp.insuranceEth();

        uint256 snap = vm.snapshotState();
        registry.rotateSlice(2500, 0, route);
        uint256 honest = usdg.balanceOf(address(perp));
        vm.revertToState(snap);
        console2.log("A2 engine pot converted (wei) ", pot);
        console2.log("A2 honest flip -> engine usdg ", honest);

        uint256 worst = honest;
        uint256 bestProfit;
        uint256[4] memory push = [uint256(2 ether), 4 ether, 6 ether, 9 ether];
        for (uint256 i; i < push.length; ++i) {
            (bool landed, uint256 engineGot, uint256 profit) = _sandwich(push[i]);
            console2.log("A2 push (wei)", push[i], landed ? "landed" : "REFUSED by the band");
            if (!landed) continue;
            console2.log("   engine usdg / attacker profit (wei)", engineGot, profit);
            if (engineGot < worst) worst = engineGot;
            if (profit > bestProfit) bestProfit = profit;
        }
        console2.log("A2 worst engine outcome (bps of honest)", worst * 10_000 / honest);
        console2.log("A2 best attacker profit (wei)          ", bestProfit);
        //  The band is what bounds it: the engine can never be filled below it.
        assertGe(worst, honest * 96 / 100, "HOLDS: the oracle band caps the sandwich (~3% of the pot)");
    }

    /// Dump `ethIn` into the venue, fire the flip, buy the ETH back; rolled back.
    function _sandwich(uint256 ethIn) internal returns (bool landed, uint256 engineGot, uint256 profit) {
        uint256 snap = vm.snapshotState();
        vm.deal(address(legTrader), 1_000 ether);
        uint256 ethBefore = address(legTrader).balance;
        uint256 usdgIn = legTrader.swap(route, true, ethIn);
        try registry.rotateSlice(2500, 0, route) { landed = true; } catch {}
        if (landed) {
            legTrader.swap(route, false, usdgIn);
            engineGot = usdg.balanceOf(address(perp));
            uint256 ethAfter = address(legTrader).balance;
            profit = ethAfter > ethBefore ? ethAfter - ethBefore : 0;
        }
        vm.revertToState(snap);
    }

    /// Buy ETH on the venue with USDG until its spot is back at the oracle's 3000.
    function _arbVenueToOracle() internal {
        vm.deal(address(legTrader), 1_000 ether);
        for (uint256 i; i < 60 && _venueUsdgPerEth() < 2997e6; ++i) {
            usdg.mint(address(legTrader), 5_000e6);
            legTrader.swap(route, false, 5_000e6);
        }
        console2.log("A2 venue after arbitrage (usdg/eth)", _venueUsdgPerEth());
    }

    // ── A3: can a trader position across the flip for a free profit? ──────────

    /**
     *  Longs are restated at the ORACLE rate; shorts' backing moves at the
     *  REALIZED rate; the new pool opens at the venue the rotation walked. An
     *  attacker holding one of each across the flip — a delta-neutral pair —
     *  must not come out ahead of closing both before it.
     */
    function test_A3_HOLDS_NoFreeLunchAcrossTheFlip() public {
        _approveEnvelopeTo(address(usdg));
        vm.deal(attacker, 10 ether);
        uint256 col = 0.2 ether;
        vm.startPrank(attacker, attacker);
        uint256 l = perp.openLong{value: col}(2, 0, 0, col);
        uint256 sh = perp.openShort{value: col}(2, 0, 0, col);
        vm.stopPrank();

        uint256 snap = vm.snapshotState();
        uint256 b = attacker.balance;
        vm.startPrank(attacker, attacker);
        perp.close(l, 0);
        perp.close(sh, 0);
        vm.stopPrank();
        uint256 controlUsd = (attacker.balance - b) * 3000e6 / 1 ether;
        vm.revertToState(snap);

        _rotateUntilSpent(0);
        vm.roll(vm.getBlockNumber() + 200);
        _warp(perp.twapWindow() + 1);
        perp.poke();
        vm.startPrank(attacker, attacker);
        perp.close(l, 0);
        perp.close(sh, 0);
        vm.stopPrank();
        uint256 carried = usdg.balanceOf(attacker);
        console2.log("A3 pair closed before the flip (usdg at oracle)", controlUsd);
        console2.log("A3 pair carried across the flip (usdg)        ", carried);
        assertLe(carried, controlUsd, "HOLDS: carrying a hedged pair across the flip is not profitable");
    }

    // ── A4: the library cannot be driven directly ──────────────────────────────

    function test_A4_HOLDS_LibraryRefusesADirectCall() public {
        (bool ok,) = address(PerpSwapLib).call(
            abi.encodeWithSelector(PerpSwapLib.requoteBookAt.selector, address(rotator), uint256(1), uint256(2))
        );
        assertFalse(ok, "HOLDS: a non-delegate call into the library reverts");
        vm.prank(attacker);
        vm.expectRevert();
        perp.requoteBook(address(rotator));
    }

    // ── A5: gas of the flip with a FULL book ───────────────────────────────────

    function test_A5_MEASURED_FlipGasWithAFullBook() public {
        _approveEnvelopeTo(address(usdg));
        uint256 cap = perp.MAX_OPEN_POSITIONS();
        uint256 col = perp.minCollateral() * 2;
        for (uint256 i; i < cap; ++i) {
            address t = address(uint160(0xB0B000 + i));
            vm.deal(t, 1 ether);
            vm.prank(t, t);
            if (i % 2 == 0) perp.openLong{value: col}(2, 0, 0, col);
            else perp.openShort{value: col}(2, 0, 0, col);
        }
        assertEq(perp.openCount(), cap, "a full book");
        for (uint256 i; i < 11; ++i) registry.rotateSlice(2500, 0, route);
        uint256 g = gasleft();
        registry.rotateSlice(2500, 0, route);
        uint256 used = g - gasleft();
        console2.log("A5 flipping slice gas, 64-position book", used);
        assertEq(perp.quote(), address(usdg), "the full book was carried");
        assertEq(perp.openCount(), cap, "every position survived");
        assertLt(used, 15_000_000, "MEASURED: well inside a 30M block");
    }

    // ── A6: relaunch after a rotation, with stakers ────────────────────────────

    /**
     *  Relaunch forces the new generation back to NATIVE. After a rotation the
     *  engine is on USDG, so `syncGeneration` (called in a try by the registry)
     *  meets a quote change with stakers present.
     */
    function test_A6_RelaunchAfterARotation_EngineFollows() public {
        _flipToUsdg();
        assertEq(perp.quote(), address(usdg), "rotated");
        uint256 aliceUsdg = _alice();
        //  Kill the generation and relaunch it.
        hook.setDeathThreshold(type(uint128).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days);
        registry.relaunch();
        console2.log("A6 engine synced gen", perp.syncedGeneration(), "registry gen", registry.currentGeneration());
        console2.log("A6 engine quote", perp.quote());
        console2.log("A6 alice value before / after", aliceUsdg, _alice());
        assertEq(perp.syncedGeneration(), registry.currentGeneration(), "the engine followed the relaunch");
        assertEq(perp.quote(), registry.generationQuote(registry.currentGeneration()), "onto the new quote");
        assertGt(_alice(), 0, "and alice's stake was carried, not written off");
    }

    function _alice() internal view returns (uint256 v) {
        (v,,) = vault.ethPosition(alice);
    }
}

/// A trading contract whose `receive` can be switched to refuse ether.
contract RQRefuser {
    PerpEngine internal immutable perp;
    bool public refuse;

    constructor(PerpEngine p) { perp = p; }
    function setRefuse(bool r) external { refuse = r; }
    function openLong(uint256 col) external returns (uint256) {
        return perp.openLong{value: col}(2, 0, 0, col);
    }
    function close(uint256 id) external { perp.close(id, 0); }
    receive() external payable { require(!refuse, "refuse"); }
}
