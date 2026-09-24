// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";

/**
 * LIQ-05 — verification economics for the hunter's LIQ-04.B ("the projection's
 * ~10% overshoot force-closes a position the trade does not sink").
 *
 *  Three questions the original PoC does not answer:
 *
 *   1. BASELINE. What does the victim lose if they close the SAME short
 *      voluntarily, one block after opening, with no attacker at all? That
 *      isolates the part of the reported "12.08 mETH loss" that is the open fee
 *      plus the position's own settlement impact — costs the victim pays in any
 *      exit — from the part that is actually caused by the premature kill.
 *
 *   2. PENALTY SHARE. `liqPenaltyBps = 690` (PerpEngine.sol:155) on a 0.05 ETH
 *      collateral is 3.45 mETH. How much of the loss is the penalty?
 *
 *   3. CROSSOVER. The original PoC prices the grief from a FRESH, maximally
 *      healthy short (attacker cost 29.55 mETH > victim loss 12.08 mETH, i.e.
 *      unprofitable). The realistic case is a victim already carried toward
 *      maintenance by ordinary flow. Drift the price with the UN-PRE-SWEPT
 *      exact-output route (which fires no pre-sweep, so the drift itself cannot
 *      kill in beforeSwap), then find the SMALLEST exact-input nudge that does,
 *      and compare its cost with the victim's loss.
 */
contract LIQ05_PrematureKillEconomics is YBase {
    uint256 constant COL = 0.05 ether;

    function setUp() public {
        _boot(3 ether, 24);
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        require(active, "LIQ05_PrematureKillEconomics: fork not active - PoC proved nothing");
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 5_000 ether);
    }

    function _victimShort() internal returns (uint256 id) {
        vm.prank(victim);
        id = perp.openShort{value: COL}(2, 0, 0, COL);
    }

    function _buyExactOut(uint256 tokenOut) internal returns (uint256 ethSpent) {
        bytes memory r =
            pm.unlock(abi.encode(OP_SWAP, abi.encode(YSwap(true, int256(tokenOut), address(this), address(this))), _key()));
        (int128 a0,) = abi.decode(r, (int128, int128));
        ethSpent = uint256(uint128(-a0));
    }

    /// @dev Move the price up by `ethIn` worth WITHOUT arming the pre-sweep, by
    ///      routing it exact-output for whatever `ethIn` would have bought.
    function _driftNoPreSweep(uint256 ethIn) internal {
        uint256 s = vm.snapshotState();
        uint256 tokenOut = _buy(ethIn, address(this));
        vm.revertToState(s);
        if (tokenOut > 0) _buyExactOut(tokenOut);
    }

    // ------------------------------------------------------------------
    // 1 + 2 — what a voluntary exit costs, versus the force-closed exit
    // ------------------------------------------------------------------

    function test_LIQ05_VoluntaryExitBaselineVersusForcedClose() public {
        // (a) voluntary close, no attacker
        uint256 snap = vm.snapshotState();
        uint256 id = _victimShort();
        uint256 vStart = victim.balance;
        vm.prank(victim);
        perp.close(id, 0);
        uint256 voluntaryBack = victim.balance - vStart;
        uint256 voluntaryLoss = COL > voluntaryBack ? COL - voluntaryBack : 0;
        vm.revertToState(snap);

        // (b) the hunter's grief: 0.5 ETH buy (pre-sweep kills), then sell back
        uint256 id2 = _victimShort();
        uint256 vStart2 = victim.balance;
        uint256 aStart = address(this).balance;
        uint256 got = _buy(0.5 ether, address(this));
        (address t,,,,,,,) = perp.positions(id2);
        bool killed = t == address(0);
        _sell(got, address(this));
        uint256 forcedBack = victim.balance - vStart2;
        uint256 forcedLoss = COL > forcedBack ? COL - forcedBack : 0;
        uint256 attackerCost = aStart - address(this).balance;

        uint256 penalty = (COL * 690) / 10_000;

        console2.log("voluntary close: back / loss", voluntaryBack, voluntaryLoss);
        console2.log("forced close:    back / loss", forcedBack, forcedLoss);
        console2.log("liquidation penalty (690bps of collateral)", penalty);
        console2.log("INCREMENTAL harm of the forced close (wei)",
            forcedLoss > voluntaryLoss ? forcedLoss - voluntaryLoss : 0);
        console2.log("attacker round-trip cost (wei)", attackerCost);

        //  REFUTED: pre-emption fires on insolvency at the PROJECTED price, and a
        //  0.5 ETH buy does not bankrupt this short — so there is no forced close
        //  left to price. The voluntary baseline stays because it is what makes a
        //  liquidation's INCREMENTAL harm (the 690 bps penalty, not the whole
        //  position loss) legible if the trigger is ever revisited.
        assertFalse(killed, "a victim the trade leaves solvent must not be force-closed");
        assertGt(voluntaryLoss, 0, "control: holding the short through the move costs the victim regardless");
        assertGt(attackerCost, 0, "control: the griefer paid for the round trip");
    }

    // ------------------------------------------------------------------
    // 3 — the crossover: how close to maintenance before the nudge is cheap
    // ------------------------------------------------------------------

    struct Probe {
        uint256 drift;
        uint256 killSize;
        uint256 attackerCost;
        uint256 victimLoss;
        bool preKilled;
    }

    /// @dev After `drift` of un-pre-swept price move, find the smallest exact-input
    ///      buy that force-closes the victim, and price it.
    function _probe(uint256 drift) internal returns (Probe memory p) {
        p.drift = drift;
        uint256 id = _victimShort();
        if (drift > 0) _driftNoPreSweep(drift);
        (address t0,,,,,,,) = perp.positions(id);
        if (t0 == address(0)) { p.preKilled = true; return p; }

        (p.killSize, p.attackerCost, p.victimLoss) = _scanSizes(id);
    }

    /// @dev The size scan, in its OWN frame. Two reasons, both load-bearing:
    ///      via_ir ran `_probe` 1 slot too deep once the refusal handling was
    ///      added, and a refused buy now has to be a DATA POINT rather than a
    ///      test failure. The pre-trade sweep reverts `LiqTradeTooLarge` when a
    ///      trade condemns more than one swap can close, or condemns something
    ///      it cannot close at all -- for a crossover scan that simply means the
    ///      grief is unavailable at this size: no fill, no kill, nothing spent.
    ///      Letting the revert escape aborted the whole scan on its first
    ///      refusal and reported an unavailable attack as a broken test.
    function _scanSizes(uint256 id)
        internal
        returns (uint256 killSize, uint256 attackerCost, uint256 victimLoss)
    {
        uint256[8] memory sizes = [
            uint256(0.005 ether), 0.01 ether, 0.02 ether, 0.05 ether,
            0.1 ether, 0.2 ether, 0.35 ether, 0.5 ether
        ];
        for (uint256 i; i < sizes.length; ++i) {
            uint256 s = vm.snapshotState();
            uint256 vStart = victim.balance;
            uint256 aStart = address(this).balance;
            uint256 got = _tryBuy(sizes[i]);
            if (got == 0) { vm.revertToState(s); continue; }
            (address t,,,,,,,) = perp.positions(id);
            _sell(got, address(this));
            if (t == address(0)) {
                killSize = sizes[i];
                attackerCost = aStart > address(this).balance ? aStart - address(this).balance : 0;
                uint256 back = victim.balance - vStart;
                victimLoss = COL > back ? COL - back : 0;
                vm.revertToState(s);
                return (killSize, attackerCost, victimLoss);
            }
            vm.revertToState(s);
        }
    }

    /// @dev Self-call so a refused buy returns 0 instead of aborting the scan.
    function extBuy(uint256 ethIn) external returns (uint256) {
        require(msg.sender == address(this), "self only");
        return _buy(ethIn, address(this));
    }

    function _tryBuy(uint256 ethIn) internal returns (uint256) {
        (bool ok, bytes memory ret) = address(this).call(abi.encodeCall(this.extBuy, (ethIn)));
        return ok ? abi.decode(ret, (uint256)) : 0;
    }

    function test_LIQ05_GriefCrossoverVersusVictimHealth() public {
        uint256[5] memory drifts = [uint256(0), 0.1 ether, 0.2 ether, 0.3 ether, 0.4 ether];
        uint256 crossoverDrift = type(uint256).max;
        uint256 probed;
        for (uint256 i; i < drifts.length; ++i) {
            uint256 snap = vm.snapshotState();
            Probe memory p = _probe(drifts[i]);
            vm.revertToState(snap);
            probed++;
            console2.log("drift / preKilled / killSize", p.drift, p.preKilled, p.killSize);
            console2.log("   attackerCost / victimLoss", p.attackerCost, p.victimLoss);
            if (!p.preKilled && p.killSize > 0 && p.attackerCost < p.victimLoss
                && crossoverDrift == type(uint256).max) {
                crossoverDrift = p.drift;
            }
        }
        console2.log("PROBES RUN", probed);
        console2.log("crossover drift (max uint = never profitable in this scan)", crossoverDrift);
        assertEq(probed, drifts.length, "every drift level was probed");
    }
}
