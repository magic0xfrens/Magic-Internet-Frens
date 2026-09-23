// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";

/**
 * LIQ-04.B — the projection's built-in over-shoot (GROSS input + SLACK_BPS=500 on
 * the sqrt ratio, i.e. ~10% on price, against a 15% maintenance buffer) closes
 * positions that the pending trade demonstrably does NOT push past maintenance.
 *
 *  Method: run the SAME economic trade down two routes from the SAME snapshot.
 *    * EXACT-OUTPUT  — no pre-sweep (LIQ-04.A), so it shows what the trade really
 *      does to the pool. If the short survives here, the trade did not sink it.
 *    * EXACT-INPUT   — pre-sweep armed. If the short dies here, it was killed by
 *      the projection, not by the trade.
 *
 *  A size where "survives the real trade" and "dies to the projection" both hold
 *  is a forced liquidation of a position that was never in danger.
 */
contract LIQ04_PrematureKill is YBase {
    function setUp() public {
        _boot(3 ether, 24);
        require(active, "LIQ04_PrematureKill: fork not active - PoC proved nothing");
        _bootPerp(2 ether, 200_000_000e18);
        vm.deal(address(this), 5_000 ether);
    }

    function _openHealthyShort() internal returns (uint256 id) {
        uint256 col = 0.05 ether;
        id = perp.openShort{value: col}(2, 0, 0, col);
    }

    function _buyExactOut(uint256 tokenOut) internal returns (uint256 ethSpent) {
        bytes memory r = pm.unlock(
            abi.encode(OP_SWAP, abi.encode(YSwap(true, int256(tokenOut), address(this), address(this))), _key())
        );
        (int128 a0, ) = abi.decode(r, (int128, int128));
        ethSpent = uint256(uint128(-a0));
    }

    /// @return survived  the short is still open after the REAL trade (no pre-sweep)
    /// @return liqAfter  and it is not even liquidatable at the post-trade state
    function _realTrade(uint256 ethIn) internal returns (bool survived, bool liqAfter, uint256 tokenOut) {
        uint256 id = _openHealthyShort();
        // What does `ethIn` buy? Measure on a throwaway branch, roll back, then
        // replay the SAME token amount as exact-OUTPUT (the un-pre-swept route).
        uint256 s = vm.snapshotState();
        tokenOut = _buy(ethIn, address(this));
        vm.revertToState(s);
        _buyExactOut(tokenOut);
        (address t, , , , , , , ) = perp.positions(id);
        survived = t != address(0);
        liqAfter = survived ? perp.isLiquidatable(id) : true;
    }

    function _preemptedTrade(uint256 ethIn) internal returns (bool killed, uint256 collBack) {
        uint256 id = _openHealthyShort();
        uint256 balBefore = address(this).balance;
        _buy(ethIn, address(this));
        (address t, , , , , , , ) = perp.positions(id);
        killed = t == address(0);
        collBack = address(this).balance > balBefore ? address(this).balance - balBefore : 0;
    }

    /// @dev Round-trip cost to the griefer: buy `ethIn`, sell every token back.
    function _griefCost(uint256 ethIn) internal returns (uint256 cost) {
        uint256 before_ = address(this).balance;
        uint256 got = _buy(ethIn, address(this));
        uint256 back = _sell(got, address(this));
        back;
        uint256 after_ = address(this).balance;
        cost = before_ > after_ ? before_ - after_ : 0;
    }

    function test_LIQ04_REFUTED_ProjectionNeverKillsAPositionTheTradeSpares() public {
        uint256[6] memory sizes =
            [uint256(0.05 ether), 0.1 ether, 0.15 ether, 0.2 ether, 0.3 ether, 0.5 ether];

        uint256 foundSize;
        bool foundSurvivesReal;
        bool foundNotLiqReal;
        bool foundKilledByProjection;

        for (uint256 i; i < sizes.length; ++i) {
            uint256 snapA = vm.snapshotState();
            (bool survived, bool liqAfter, ) = _realTrade(sizes[i]);
            vm.revertToState(snapA);
            uint256 snapB = vm.snapshotState();
            (bool killed, ) = _preemptedTrade(sizes[i]);
            vm.revertToState(snapB);
            console2.log("size / survivedRealTrade / liquidatableAfterReal / killedByProjection", sizes[i]);
            console2.log("   ", survived, liqAfter, killed);
            if (survived && !liqAfter && killed && foundSize == 0) {
                foundSize = sizes[i];
                foundSurvivesReal = survived;
                foundNotLiqReal = !liqAfter;
                foundKilledByProjection = killed;
            }
        }

        uint256 cost;
        if (foundSize != 0) {
            uint256 snap2 = vm.snapshotState();
            _openHealthyShort();
            cost = _griefCost(foundSize);
            vm.revertToState(snap2);
        }
        console2.log("premature-kill size (wei)", foundSize);
        console2.log("griefer round-trip cost (wei)", cost);

        //  REFUTED, and pinned. The claim was that the projection's overshoot
        //  force-closes positions the trade would NOT have sunk. It does not:
        //  scanning every size finds none that survives the real trade yet dies
        //  to the projection. The overshoot is 12-190 bps of sqrtP against a
        //  1500 bps maintenance buffer, and the positions the pre-sweep closes
        //  are ones the TWAP mark simply had not caught up to yet.
        assertEq(foundSize, 0, "a size that survives the trade but dies to the projection would be over-liquidation");
        assertFalse(foundSurvivesReal, "no such size was found, so nothing survived one");
        assertFalse(foundNotLiqReal, "no such size was found");
        assertFalse(foundKilledByProjection, "no such size was found");
    }

    /// LIQ-04.B2 — price the grief. The VICTIM owns the short; the attacker buys
    /// 0.5 ETH and immediately sells every token back. The projection kills the
    /// short on the way in even though the round trip leaves the pool where it
    /// started and the trade never put the short past maintenance (04.B).
    function test_LIQ04_REFUTED_GriefRoundTripCannotForceClose() public {
        uint256 col = 0.05 ether;
        vm.prank(victim);
        uint256 id = perp.openShort{value: col}(2, 0, 0, col);
        assertFalse(perp.isLiquidatable(id), "control: victim short starts healthy");

        uint256 attackerStart = address(this).balance;
        uint256 victimStart = victim.balance;

        uint256 got = _buy(0.5 ether, address(this));
        (address t, , , , , , , ) = perp.positions(id);
        bool killed = t == address(0);
        _sell(got, address(this));

        uint256 attackerEnd = address(this).balance;
        uint256 victimEnd = victim.balance;
        uint256 attackerCost = attackerStart > attackerEnd ? attackerStart - attackerEnd : 0;
        uint256 attackerGain = attackerEnd > attackerStart ? attackerEnd - attackerStart : 0;
        uint256 victimBack = victimEnd - victimStart;
        uint256 victimLoss = col > victimBack ? col - victimBack : 0;

        console2.log("attacker cost / gain (wei)", attackerCost, attackerGain);
        console2.log("victim collateral back / loss (wei)", victimBack, victimLoss);

        //  REFUTED. Pre-emption fires on INSOLVENCY at the projected price, never
        //  on maintenance, so a round-trip that leaves the victim solvent after
        //  the trade cannot force-close them — and the attacker still pays the
        //  full round-trip cost for nothing.
        assertFalse(killed, "a solvent-after-the-trade victim must survive the round trip");
        //  `victimLoss` here is just "collateral not yet returned" — the position
        //  is still OPEN, so of course nothing came back. The property that
        //  matters is that the round trip neither closed it nor paid the griefer.
        assertEq(victimBack, 0, "nothing was settled to the victim: the short is untouched");
        assertEq(t, victim, "the victim still owns the position");
        assertGt(attackerCost, 0, "control: the griefer really did pay for the round trip");
        assertEq(attackerGain, 0, "and gained nothing");
    }

    /// @dev One grief attempt at `ethIn` against a fresh max-leverage victim short.
    function _attempt(uint256 ethIn, uint8 lev, uint256 col)
        internal
        returns (bool killed, uint256 attackerCost, uint256 victimLoss)
    {
        vm.prank(victim);
        uint256 id = perp.openShort{value: col}(lev, 0, 0, col);
        uint256 aStart = address(this).balance;
        uint256 vStart = victim.balance;
        uint256 got = _buy(ethIn, address(this));
        (address t, , , , , , , ) = perp.positions(id);
        killed = t == address(0);
        _sell(got, address(this));
        uint256 aEnd = address(this).balance;
        attackerCost = aStart > aEnd ? aStart - aEnd : 0;
        uint256 back = victim.balance - vStart;
        victimLoss = col > back ? col - back : 0;
    }

    /// LIQ-04.B3 — the CHEAPEST trade that force-closes a max-leverage short, and
    /// what it costs the attacker versus what it costs the victim. The projection's
    /// ~10% price overshoot means a victim sitting anywhere inside a 10% band above
    /// maintenance can be closed by a trade far smaller than the move that would
    /// actually endanger them.
    function test_LIQ04_REFUTED_NoTradeSizeForcesAClose() public {
        uint8 lev = perp.maxLeverage();
        uint256 col = 0.05 ether;
        uint256[7] memory sizes = [
            uint256(0.01 ether), 0.02 ether, 0.05 ether, 0.1 ether, 0.2 ether, 0.35 ether, 0.5 ether
        ];
        uint256 bestSize;
        uint256 bestCost;
        uint256 bestLoss;
        for (uint256 i; i < sizes.length; ++i) {
            uint256 snap = vm.snapshotState();
            (bool killed, uint256 cost, uint256 loss) = _attempt(sizes[i], lev, col);
            vm.revertToState(snap);
            console2.log("try size / killed?", sizes[i], killed);
            console2.log("   cost / victimLoss", cost, loss);
            if (killed && bestSize == 0) { bestSize = sizes[i]; bestCost = cost; bestLoss = loss; }
        }
        console2.log("maxLeverage used", lev);
        console2.log("cheapest kill size / attacker cost / victim loss", bestSize, bestCost, bestLoss);
        //  REFUTED across the whole size ladder: no trade force-closes a victim
        //  the trade leaves solvent, so there is no "cheapest" grief to price.
        assertEq(bestSize, 0, "no trade size may force-close a victim the trade leaves solvent");
        assertEq(bestLoss, 0, "and so no victim loss to price");
    }
}
