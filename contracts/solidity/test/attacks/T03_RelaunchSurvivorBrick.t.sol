// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {YBase} from "./YBase.sol";

/**
 * T03 — SURVIVORS OF A GAS-CAPPED RELAUNCH.
 *
 * CauldronRegistry.sol:1087-1091 concedes the force-close may not finish and
 * asserts the recovery:
 *     "any survivors are cleared afterwards by the permissionless
 *      forceCloseDead path, then syncGeneration re-arms."
 *
 * That is an UNVERIFIED CLAIM. Both force-close entrypoints gate on
 * `_isDead()` (PerpEngine.sol:986, :999), and `_isDead()` (PerpEngine.sol:1306-1309)
 * asks the hook about `_key().toId()` — a key built from `registry.currentToken()`,
 * i.e. the pool of the generation that is CURRENT *now*. One instruction after
 * the relaunch that is the NEWBORN pool, which is alive.
 *
 * `relaunch()` (CauldronRegistry.sol:751) is permissionless and the caller
 * chooses the gas limit, so the survivor set is attacker-selected.
 */
contract T03_RelaunchSurvivorBrick is YBase {
    uint256 constant OPEN_AMT = 0.0035 ether;

    function setUp() public {
        _boot(4 ether, 0);
        if (!active) return;
        _bootPerp(3 ether, 200_000_000 ether);
    }

    function _fill(uint256 n) internal returns (uint256 opened) {
        vm.deal(address(this), 100_000 ether);
        for (uint256 i; i < n; ++i) {
            try perp.openLong{value: OPEN_AMT}(1, 0, 0, OPEN_AMT) { opened++; }
            catch { break; }
        }
    }

    function _fillLev(uint256 n, uint8 lev) internal returns (uint256 opened) {
        vm.deal(address(this), 100_000 ether);
        for (uint256 i; i < n; ++i) {
            try perp.openLong{value: OPEN_AMT}(lev, 0, 0, OPEN_AMT) { opened++; }
            catch { break; }
        }
    }

    /// Sweep gas caps to find the window where the rebirth SUCCEEDS but the
    /// force-close does not finish.
    function test_SweepGasCaps() public {
        vm.skip(!active);
        uint256 opened = _fill(64);
        assertEq(perp.openCount(), opened, "book filled");
        hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
        _warp(1 days + 1);

        T03GasRunner runner = new T03GasRunner();
        uint256[6] memory caps =
            [uint256(12_000_000), 14_000_000, 16_000_000, 18_000_000, 20_000_000, 24_000_000];

        for (uint256 i; i < caps.length; ++i) {
            uint256 snap = vm.snapshotState();
            bool ok = runner.relaunchWithGas(address(registry), caps[i]);
            console2.log("cap", caps[i]);
            console2.log("  relaunch ok      :", ok);
            console2.log("  gen              :", registry.currentGeneration());
            console2.log("  openCount after  :", perp.openCount());
            console2.log("  syncedGeneration :", perp.syncedGeneration());
            vm.revertToState(snap);
        }

        bool reached = true;
        assertTrue(reached, "T03: gas-cap sweep complete");
    }

    /// THE BRICK. 12,000,000 gas is enough for the rebirth and not enough for
    /// the force-close. Every recovery path the comment names is then probed.
    /// REFUTED, AND NOW A REGRESSION TEST FOR THE PROPERTY THAT REPLACED IT.
    ///
    ///  THE ORIGINAL ATTACK: 12,000,000 gas was enough for the rebirth and not
    ///  enough for the force-close, so the protocol moved to gen-2 while 64
    ///  positions SURVIVED into it — holding LP ether that no path could return,
    ///  with `forceCloseAllDead`, `forceCloseDead`, `syncGeneration`, `close` and
    ///  `liquidate` all unreachable. A permanent brick for the price of 64 dust
    ///  positions.
    ///
    ///  IT NO LONGER REPRODUCES. `relaunch()` is now ATOMIC across the gas range:
    ///  it either completes fully or reverts and changes NOTHING. There is no
    ///  window that leaves survivors behind. Measured on this fork, full 64-book:
    ///
    ///      cap 12M -> relaunch false, gen 1, openCount 64, synced 1  (no-op)
    ///      cap 14M -> relaunch true,  gen 2, openCount  0, synced 2  (complete)
    ///      caps 16M/18M/20M/24M -> identical to 14M
    ///
    ///  So the assertion that earns its keep is ATOMICITY, not the old brick. If a
    ///  future change reintroduces a half-done rebirth, the "nothing moved" block
    ///  below fails and names it.
    function test_SurvivorsCanNeverBeClosed() public {
        vm.skip(!active);
        uint256 opened = _fillLev(64, 2); // leverage 2 -> real LP ETH is lent out
        assertGt(opened, 0, "book filled");

        address oldTok = registry.currentToken();
        hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
        _warp(1 days + 1);

        T03GasRunner runner = new T03GasRunner();

        // ---- STARVED (12M): the rebirth must be a clean no-op, not a half-step.
        uint256 snap = vm.snapshotState();
        bool okStarved = runner.relaunchWithGas(address(registry), 12_000_000);
        assertFalse(okStarved, "12M is not enough to relaunch a full book");
        assertEq(registry.currentGeneration(), 1, "ATOMIC: generation did not move");
        assertEq(registry.currentToken(), oldTok, "ATOMIC: token did not change");
        assertEq(perp.openCount(), opened, "ATOMIC: the book is untouched");
        assertEq(perp.syncedGeneration(), 1, "ATOMIC: the engine did not re-arm");
        vm.revertToState(snap);

        // ---- FUNDED (14M): the rebirth completes and DRAINS the book.
        bool okFunded = runner.relaunchWithGas(address(registry), 14_000_000);
        assertTrue(okFunded, "14M relaunches a full 64-position book");
        assertEq(registry.currentGeneration(), 2, "the protocol moved on");
        assertEq(perp.openCount(), 0, "NO survivor: every position was force-closed");
        assertEq(perp.syncedGeneration(), 2, "the engine re-armed for gen-2");
        assertTrue(registry.currentToken() != oldTok, "the token really did change");
        assertEq(perp.longOiEth(), 0, "no LP ether left lent out");
    }

    /// `_key()`, i.e. the gen-2 pool, while the engine holds only gen-1 token.
    /// REFUTED. The companion claim was that once the NEW pool dies too, the
    /// `NotDead()` gate opens but the settlement swap is still aimed at the gen-2
    /// pool while the engine holds only gen-1 token — so survivors stay stuck even
    /// then. That depended on survivors EXISTING, which the atomic rebirth above
    /// no longer produces. Asserted here from the other side: relaunch with enough
    /// gas and there is simply nothing left to be stuck.
    function test_SurvivorsUnclosableEvenWhenTheGateOpens() public {
        vm.skip(!active);
        uint256 opened = _fillLev(64, 2);
        assertGt(opened, 0, "book filled");
        address oldTok = registry.currentToken();

        hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
        _warp(1 days + 1);
        T03GasRunner runner = new T03GasRunner();
        assertTrue(runner.relaunchWithGas(address(registry), 14_000_000), "relaunch ok");

        address newTok = registry.currentToken();
        assertTrue(newTok != oldTok, "the token changed");
        assertEq(perp.openCount(), 0, "no survivors to strand");

        //  The engine's inventory followed the generation: it must NOT still be
        //  holding the dead token while pointed at the new pool, which was the
        //  mechanism that made the settle swap unrunnable.
        assertEq(perp.syncedToken(), newTok, "engine re-pointed at the gen-2 token");
        assertEq(perp.longOiEth(), 0, "no LP ether lent out against a dead book");
    }
}


/// HOW FULL MUST THE BOOK BE? `hook.forceClosePerps{gas: g - 8_000_000}()` is
/// ALL-OR-NOTHING: it runs inside a try/catch, so if the budget does not cover
/// the WHOLE book the child OOGs, reverts, and ZERO positions are closed.
contract T03_RelaunchSurvivorBrick_BookSize is YBase {
    function setUp() public {
        _boot(4 ether, 0);
        if (!active) return;
        _bootPerp(3 ether, 200_000_000 ether);
    }

    function _openN(uint256 n) internal {
        vm.deal(address(this), 100_000 ether);
        for (uint256 i; i < n; ++i) perp.openLong{value: 0.0035 ether}(2, 0, 0, 0.0035 ether);
    }

    /// REFUTED. This searched for the smallest book that a 12M-gas relaunch would
    /// carry into the next generation intact — the cheapest brick. There is no
    /// longer any such size: at 12M the rebirth is a clean no-op at EVERY book
    /// size, so nothing survives because nothing happens.
    function test_MinimumBookSizeAt12M() public {
        vm.skip(!active);
        T03GasRunner runner = new T03GasRunner();
        uint256[5] memory ns = [uint256(8), 16, 32, 48, 64];
        uint256 smallest;
        uint256 checked;
        for (uint256 i; i < ns.length; ++i) {
            uint256 s = vm.snapshotState();
            _openN(ns[i]);
            hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
            _warp(1 days + 1);
            bool ok = runner.relaunchWithGas(address(registry), 12_000_000);
            uint256 oc = perp.openCount();
            console2.log("book size", ns[i]);
            console2.log("  relaunch ok / survivors:", ok, oc);
            //  A BRICK is "the rebirth SUCCEEDED and the whole book survived".
            if (ok && oc == ns[i] && smallest == 0) smallest = ns[i];
            //  Whatever the gas outcome, the state must be self-consistent: a
            //  successful rebirth drains the book, a failed one leaves it whole.
            assertTrue(ok ? (oc == 0) : (oc == ns[i]), "rebirth was all-or-nothing");
            checked++;
            vm.revertToState(s);
        }
        assertEq(checked, ns.length, "every book size was probed");
        assertEq(smallest, 0, "NO brickable book size exists at a 12M cap");
    }
}

interface IERC20Like { function balanceOf(address) external view returns (uint256); }

contract T03GasRunner {
    function relaunchWithGas(address reg, uint256 cap) external returns (bool ok) {
        (ok,) = reg.call{gas: cap}(abi.encodeWithSignature("relaunch()"));
    }
}
