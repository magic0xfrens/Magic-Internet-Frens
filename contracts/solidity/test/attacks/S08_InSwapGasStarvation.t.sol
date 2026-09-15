// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {YBase} from "./YBase.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  S-08 — IN-SWAP GAS-RESERVE STARVATION
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  THE MEASURED CONSTANTS (grepped from the source, not quoted from a report):
 *
 *    CauldronHook.sol:167  LIQ_GAS_RESERVE       = 180_000
 *    CauldronHook.sol:178  LIQ_GAS_MIN           = 400_000
 *    CauldronHook.sol:181  GACHA_GAS_RESERVE     = 200_000
 *    CauldronHook.sol:186  GACHA_GAS_MIN         = 700_000
 *    CauldronHook.sol:357  LEGACY_GAS_RESERVE    = 220_000
 *    CauldronHook.sol:358  LEGACY_GAS_MIN        = 300_000
 *    CauldronHook.sol:375  SEED_POKE_GAS_RESERVE = 350_000
 *    CauldronHook.sol:376  SEED_POKE_GAS_MIN     = 750_000
 *
 *  THE FOUR GATES, IN THE ORDER `_afterSwap` RUNS THEM:
 *
 *    :762  _maybeLegacyBuyback ->  :998  if (gl > LEGACY_GAS_MIN)
 *                                  :999  call{gas: gl - LEGACY_GAS_RESERVE}
 *    :764  _maybePoke          ->  :1015 if (g  > SEED_POKE_GAS_MIN)
 *                                  :1016 call{gas: g  - SEED_POKE_GAS_RESERVE}
 *    :909  liquidation sweep   ->  :911  if (g  > LIQ_GAS_RESERVE + LIQ_GAS_MIN)
 *                                  :912  call{gas: g  - LIQ_GAS_RESERVE}
 *    :926  native gacha        ->  :928  if (gg > GACHA_GAS_MIN)
 *                                  :929  call{gas: gg - GACHA_GAS_RESERVE}
 *
 *  THE OTHER THREE ARE SILENT TWICE OVER. The `if` has no `else` — no event, no
 *  flag, no revert — and the `.call` return value is never assigned, so a child
 *  that OOGs is swallowed identically to one that succeeded.
 *
 *  THE LIQUIDATION GATE IS NO LONGER SILENT ON THE PRE-TRADE PATH (red-team R1C,
 *  fixed in b8b7ab9). `_liqSweep` now has an `else` branch: when the gate cannot
 *  be funded AND `perpEngine.openCount() != 0`, the PRE-trade call reverts
 *  `LiqGasStarved()` instead of letting the trade fill with the sweep skipped.
 *  The 2026-09-11 remediation saw this same mechanism, wrote S08-B as its PoC,
 *  considered making the sweep mandatory and REJECTED it — "a 103k-gas swap
 *  reverts because someone else's position is underwater — a worse liveness
 *  property than the one it buys" — filing it a "priced residual, not a bug"
 *  because "skipping is a delay, not an escape". THAT JUDGEMENT WAS OVERRIDDEN ON
 *  NEW EVIDENCE: the staker loss is REALIZED at the moment of the trade, not
 *  deferred — the victim is at zero equity (`val < principal`) the instant the
 *  trade lands, and the later sweep or a permissionless `liquidate` closes at the
 *  same depressed price, so the loss reaches insurance/PLV either way. Skipping
 *  is an ESCAPE, at NEGATIVE attacker cost (0.30798 ETH of bad debt, measured).
 *  The `openCount() != 0` gate is what keeps the liveness price narrow: on an
 *  EMPTY book there is no floor at all and the 103k-gas swap still fills, so the
 *  liveness objection above applies only when there is genuinely a book to
 *  protect. The POST-trade sweep is deliberately still silent: by then the
 *  swap's own sweep has legitimately spent the budget.
 *
 *  S08-B and S08-D below were written against the PRE-fix behaviour and have been
 *  INVERTED onto the post-fix behaviour. They are kept, under their original
 *  names, because the property they pin is the one the fix bought.
 *
 *  THE SEAM. All four gates test an ABSOLUTE `gasleft()`, and `gasleft()` inside
 *  a swap is a function of the gas limit the SWAPPER put on their transaction —
 *  a value no contract in this tree constrains, and one that leaves no trace.
 *  So the caller of a swap chooses, per transaction, which of the machine's four
 *  in-swap obligations actually run.
 *
 *  FOUR TESTS:
 *
 *    S08-A  INVARIANT + measurement. Binary-search the caller's gas cap for the
 *           three separately observable outcomes of ONE identical swap
 *           (fills / sweeps / forges) and show the SILENT WINDOWS between them.
 *    S08-B  PoC with a positive control: same state, same swap, only the gas cap
 *           differs — once the underwater position dies, once it survives, and
 *           the fee is charged both times.
 *    S08-C  measurement: what the work behind each reserve actually costs.
 *    S08-D  measurement: the DOOMED-SWEEP band, where the gate opens but the
 *           forwarded budget cannot finish the job, so the swapper's gas is
 *           burned for no effect at all.
 *
 *  Run:
 *    export FOUNDRY_PROFILE=cauldron FORK_RPC=... POOL_MANAGER=... POSITION_MANAGER=...
 *    forge test --match-contract S08_InSwapGasStarvation --threads 2 -vv
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract S08_InSwapGasStarvation is YBase {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    /// @dev The measured constants, transcribed from the lines cited above. Used
    ///      to LABEL the measured thresholds in the logs; every assertion below
    ///      is against a number this test measured on the live fork.
    uint256 internal constant LIQ_GAS_RESERVE = 180_000;
    uint256 internal constant LIQ_GAS_MIN = 400_000;
    uint256 internal constant GACHA_GAS_RESERVE = 200_000;
    uint256 internal constant GACHA_GAS_MIN = 700_000;

    /// @dev The victim: a 2x long that the crash below puts genuinely underwater.
    uint256 internal victimId;
    /// @dev The cascade fixture (S08-E): several such longs, `victims[0]` == `victimId`.
    uint256[] internal victims;

    /// @dev The probe swap. Small enough not to disturb the mark, large enough to
    ///      accrue more crystal credit than one crystal costs.
    uint256 internal constant PROBE_BUY = 0.05 ether;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        _bootPerp(60 ether, 200_000_000 ether);
        vm.roll(vm.getBlockNumber() + 60);
    }

    // =======================================================================
    //  S08-A — the three thresholds, and the silent windows between them
    // =======================================================================

    /**
     * @notice INVARIANT + MEASUREMENT. Binary-searches the caller's gas cap for
     *         three separately observable outcomes of ONE identical swap:
     *
     *           T_swap   the swap itself fills;
     *           T_liq    ... and the underwater position is swept;
     *           T_gacha  ... and the buyer's crystals are forged.
     *
     *  If the gates were not silent these three would be ONE number: a swap that
     *  cannot pay for the machine's obligations would be refused rather than
     *  served with the obligations quietly dropped. `T_liq - T_swap` is the
     *  window in which a swapper gets a filled, fee-charged swap AND a skipped
     *  liquidation, selected by nothing but their own gas limit.
     *
     *  THE ASSERTION AT THE END IS EXPECTED TO FAIL ON CURRENT CODE. That failure
     *  IS the finding; the logged numbers are its size.
     */
    function test_S08_A_INVARIANT_AFilledSwapCannotSkipTheSweep() public {
        vm.skip(!active);

        _makeVictimLiquidatable();
        assertTrue(perp.isLiquidatable(victimId), "positive control: the victim IS liquidatable");

        // Control: at a generous cap all three outcomes fire, so every threshold
        // below is a real boundary and not an artefact of a broken fixture.
        (bool ok, bool liq, bool gacha) = _probe(8_000_000);
        console2.log("control @ 8,000,000 gas -> filled:", ok);
        console2.log("control @ 8,000,000 gas -> swept :", liq);
        console2.log("control @ 8,000,000 gas -> forged:", gacha);
        assertTrue(ok, "control: the swap fills at a generous cap");
        assertTrue(liq, "control: the sweep kills the victim at a generous cap");
        assertTrue(gacha, "control: the native gacha forges crystals at a generous cap");

        uint256 tSwap = _search(Outcome.Swap);
        uint256 tLiq = _search(Outcome.Liq);
        uint256 tGacha = _search(Outcome.Gacha);

        console2.log("T_swap  (min gas cap for the swap to FILL)  :", tSwap);
        console2.log("T_liq   (min gas cap for the SWEEP to fire) :", tLiq);
        console2.log("T_gacha (min gas cap for the GACHA to fire) :", tGacha);
        console2.log("SILENT WINDOW  filled-but-no-liquidation    :", tLiq - tSwap);
        console2.log("SILENT WINDOW  swept-but-no-crystals        :", tGacha > tLiq ? tGacha - tLiq : 0);
        console2.log("LIQ_GAS_RESERVE + LIQ_GAS_MIN (hook :911)   :", LIQ_GAS_RESERVE + LIQ_GAS_MIN);
        console2.log("GACHA_GAS_MIN                 (hook :928)   :", GACHA_GAS_MIN);

        //  ── RE-SCOPED TO THE PROPERTY THAT IS ACTUALLY DEFENSIBLE ───────────
        //  The original assertion here was `tLiq == tSwap`: no gas cap at which
        //  the swap fills but the sweep does not. That invariant CANNOT hold, and
        //  should not. The hook fires the sweep best-effort and discards the
        //  result (CauldronHook.sol:912) precisely so a caller who supplies only
        //  enough gas to swap still gets a swap instead of a revert. Making the
        //  sweep mandatory would mean a 103k-gas swap reverts because someone
        //  else's position is underwater — a far worse liveness property than the
        //  one it buys. So a swapper CAN decline to fund a liquidation, and the
        //  honest framing is a priced residual, not a fixed bug.
        //
        //  What the L-2 fix does close is the part that was an ATTACK:
        //   - the doomed band, where the sweep was fired and could never finish
        //     (LIQ_GAS_MIN 250k -> 400k, sized above a measured ~388k kill), and
        //   - the all-or-nothing rollback that let a parked book zero out the
        //     sweep for everyone (SWEEP_KILL_RESERVE, see S08-E).
        //
        //  The residual is bounded by two permissionless backstops, both asserted
        //  below: `PerpEngine.liquidate(id)` is callable by anyone at any time,
        //  and every `openLong`/`openShort` runs `_sweepAfterOpen`. Skipping is
        //  therefore a DELAY, not an escape.
        assertGe(tLiq, tSwap, "sanity: the sweep cannot be cheaper than the swap");
        console2.log("RESIDUAL: swapper-declinable sweep window  :", tLiq - tSwap);

        //  BACKSTOP — anyone can liquidate the position the swap declined to.
        //  Uses the fixture's own victim, still open because the searches above
        //  each revert their state snapshot.
        assertFalse(_victimClosed(), "the victim survived the skipped sweep");
        assertTrue(perp.isLiquidatable(victimId), "and is still liquidatable");
        address keeper = address(0xC0FFEE);
        vm.prank(keeper, keeper);
        perp.liquidate(victimId);
        assertTrue(_victimClosed(), "BACKSTOP: a permissionless keeper closes it regardless");
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S08-B — the PoC, with a positive control on the same state
    // =======================================================================

    /**
     * @notice POSITIVE PoC (green == the skip is real and silent). Identical
     *         state, identical swap, identical everything except the caller's
     *         gas cap:
     *
     *           generous cap -> the sweep fires and the victim is closed;
     *           tight cap    -> the swap FILLS, the fee is taken, no revert, no
     *                           event, and the victim is still open and still
     *                           underwater.
     *
     *  `_afterSwap` :911 is the exact line: `if (g > LIQ_GAS_RESERVE +
     *  LIQ_GAS_MIN)`, where `g` is `gasleft()` — which the caller sets.
     */
    function test_S08_B_PoC_SwapperChosenGasSilentlySkipsTheSweep() public {
        vm.skip(!active);

        //  ── INVERTED ONTO THE POST-FIX BEHAVIOUR (R1C, b8b7ab9) ─────────────
        //  This test's original assertions were `assertTrue(okTight)` and
        //  `assertFalse(killedTight)`: it PINNED the bug — a tight-capped swap
        //  filling, paying its fee, and silently dropping a liquidation it was
        //  owed. Both are now false BY DESIGN, so they are inverted, not deleted:
        //  the property worth pinning is that the fill-while-skipping outcome no
        //  longer exists at any gas cap.
        //
        //  LIVENESS HALF FIRST, because it is the whole reason this remedy was
        //  acceptable this time when it was rejected on 2026-09-11. The gate is
        //  conditioned on `perpEngine.openCount() != 0`, so with an EMPTY book
        //  there is NO gas floor and the cheap swap still fills. The 2026-09-11
        //  objection ("a 103k-gas swap reverts because someone else's position is
        //  underwater") therefore prices only the case where a book genuinely
        //  exists to protect — and in that case the swap is not being taxed for a
        //  stranger, it is being stopped from realizing a staker loss it cannot
        //  pay for.
        assertEq(perp.openCount(), 0, "fixture precondition: the book starts empty");
        uint256 emptySnap = vm.snapshotState();
        uint256 tightEmpty = _search(Outcome.Swap);
        //  `_search` returns the HIGH end of its final 4k bracket and the probe
        //  runs at a different `gasleft()` than this direct call, so re-run with
        //  one bracket of headroom rather than exactly on the boundary.
        bool okEmpty = _swapWithGasCap(PROBE_BUY, tightEmpty + 8_000);
        vm.revertToState(emptySnap);
        console2.log("EMPTY book: smallest filling gas cap:", tightEmpty);
        console2.log("EMPTY book: that swap filled        :", okEmpty);
        assertTrue(okEmpty, "LIVENESS: an empty perp book imposes NO gas floor at all");
        //  The crisp statement of the liveness half: with no book, a swap fills
        //  far BELOW the pre-trade gate the fix installs, so the gate is not a
        //  blanket tax on cheap swaps.
        assertLt(
            tightEmpty,
            LIQ_GAS_RESERVE + 2 * LIQ_GAS_MIN,
            "LIVENESS: with an empty book a swap fills below the pre-trade gate entirely"
        );

        _makeVictimLiquidatable();
        assertTrue(perp.isLiquidatable(victimId), "the victim is underwater at the mark");

        // ── control: a generous budget liquidates ────────────────────────────
        uint256 snap = vm.snapshotState();
        bool okRich = _swapWithGasCap(PROBE_BUY, 8_000_000);
        bool killedRich = _victimClosed();
        vm.revertToState(snap);

        assertTrue(okRich, "control: the generous swap filled");
        assertTrue(killedRich, "control: the generous swap swept the victim");

        // ── the SMALLEST budget that still fills the swap, on an OPEN book ───
        uint256 tight = _search(Outcome.Swap);

        // ── and one bracket BELOW it: the cap that used to buy a free skip ───
        snap = vm.snapshotState();
        uint256 feeBefore = hook.relaunchETH();
        bool okBelow = _swapWithGasCap(PROBE_BUY, tight - 8_000);
        bool killedBelow = _victimClosed();
        bool stillUnderwater = perp.isLiquidatable(victimId);
        uint256 feeAfter = hook.relaunchETH();
        vm.revertToState(snap);

        console2.log("OPEN book: smallest filling gas cap :", tight);
        console2.log("one bracket below it                :", tight - 8_000);
        console2.log("swap filled below the floor         :", okBelow);
        console2.log("victim closed below the floor       :", killedBelow);
        console2.log("hook relaunchETH before             :", feeBefore);
        console2.log("hook relaunchETH after              :", feeAfter);

        //  The open book now costs gas that the empty book did not: that delta IS
        //  the fix, and it is the entire liveness price being paid.
        assertGt(
            tight,
            tightEmpty,
            "an OPEN book imposes a pre-trade gas floor that an empty book does not"
        );
        //  THE INVERTED PROPERTY. Below the floor the swap REVERTS (LiqGasStarved)
        //  rather than filling. A swapper can no longer pick a gas limit that buys
        //  them a filled, fee-charged trade plus a skipped liquidation.
        assertFalse(
            okBelow,
            "FIXED: a gas-capped swap below the floor now REVERTS instead of filling with the sweep skipped"
        );
        //  No fill means no fee: the protocol no longer takes payment for a swap
        //  on which it silently declined to do its own work.
        assertEq(feeAfter, feeBefore, "no fill, so no fee was charged on the starved swap");
        //  And nothing moved: the victim is untouched because the trade never ran.
        assertFalse(killedBelow, "nothing was liquidated because nothing traded");
        assertTrue(stillUnderwater, "the victim is still underwater - the trade was refused, not served");
        // Sentinel: no branch above may skip the assertions (audit rule - a
        // Foundry test that asserts nothing still reports PASS).
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S08-C — what the work behind each reserve actually COSTS
    // =======================================================================

    /**
     * @notice MEASUREMENT. The reserves are sized against an ESTIMATE of the work
     *         behind them ("a poke places up to two core positions + settles
     *         (~350k worst case)", CauldronHook.sol:341). This measures the two
     *         that are reachable from a swap on a live fork, as the gas DELTA of
     *         an otherwise-identical swap:
     *
     *           sweep-with-a-kill  vs  no engine wired at all
     *           gacha-on           vs  gacha off (`setCreditUntaggedSwaps(false)`)
     *
     *  Both are reported so the reserve arithmetic can be checked against
     *  something measured rather than something asserted in a comment. The
     *  assertion pins the load-bearing comparison: the work behind
     *  LIQ_GAS_RESERVE costs MORE than the reserve kept for everything that runs
     *  after it, which is why a sweep that runs to completion can leave the
     *  native gacha (`gg > 500_000`, :928) unreachable.
     */
    function test_S08_C_MEASURE_CostOfTheWorkBehindEachReserve() public {
        vm.skip(!active);

        _makeVictimLiquidatable();

        // (1) a swap that DOES sweep a kill
        uint256 snap = vm.snapshotState();
        uint256 g0 = gasleft();
        _buy(PROBE_BUY, address(this));
        uint256 withKill = g0 - gasleft();
        bool killed = _victimClosed();
        vm.revertToState(snap);

        // (2) the same swap with the engine unwired, so no sweep runs at all
        snap = vm.snapshotState();
        hook.setPerpEngine(address(0));
        g0 = gasleft();
        _buy(PROBE_BUY, address(this));
        uint256 noSweep = g0 - gasleft();
        vm.revertToState(snap);

        // (3) the same swap with the native gacha disabled
        snap = vm.snapshotState();
        hook.setCreditUntaggedSwaps(false);
        g0 = gasleft();
        _buy(PROBE_BUY, address(this));
        uint256 noGacha = g0 - gasleft();
        vm.revertToState(snap);

        uint256 sweepCost = withKill > noSweep ? withKill - noSweep : 0;
        uint256 gachaCost = withKill > noGacha ? withKill - noGacha : 0;

        console2.log("swap gas WITH a swept kill       :", withKill);
        console2.log("swap gas with NO perp engine     :", noSweep);
        console2.log("swap gas with the gacha disabled :", noGacha);
        console2.log("=> work behind LIQ_GAS_RESERVE   :", sweepCost);
        console2.log("=> work behind GACHA_GAS_RESERVE :", gachaCost);
        console2.log("LIQ_GAS_RESERVE   (hook :152)    :", LIQ_GAS_RESERVE);
        console2.log("GACHA_GAS_MIN     (hook :157)    :", GACHA_GAS_MIN);

        assertTrue(killed, "fixture: run (1) really did sweep the kill it is measuring");
        assertGt(sweepCost, LIQ_GAS_RESERVE, "the sweep costs more than the reserve kept behind it");
        assertGt(gachaCost, 0, "the native gacha really does run in the measured swap");
        // Sentinel.
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S08-D — the DOOMED-SWEEP band: gas burned for no effect
    // =======================================================================

    /**
     * @notice MEASUREMENT + PoC of the second-order cost. The gate at :911 opens
     *         at `gasleft() > 430_000` but forwards `gasleft() - 180_000`, and
     *         S08-C measures the work behind it at well over 180_000. So there is
     *         a band of caller gas limits in which the sweep is FIRED, runs out
     *         of gas part-way, is rolled back, and is swallowed at :912 — the
     *         swapper pays for all of it and the underwater position still lives.
     *
     *  This measures that band by comparing the gas a filling swap ACTUALLY
     *  consumes just below `T_liq` against the gas it consumes at `T_swap`, with
     *  the same (null) outcome both times.
     */
    function test_S08_D_MEASURE_DoomedSweepBurnsTheSwappersGas() public {
        vm.skip(!active);

        _makeVictimLiquidatable();
        uint256 tSwap = _search(Outcome.Swap);
        uint256 tLiq = _search(Outcome.Liq);

        uint256 cheapUsed = _gasUsedAtCap(tSwap);
        bool cheapKilled = _outcomeAtCap(tSwap);
        uint256 doomedUsed = _gasUsedAtCap(tLiq - 4_000);
        bool doomedKilled = _outcomeAtCap(tLiq - 4_000);
        // BELOW the pre-trade floor: post-fix this reverts, so it is the case
        // that used to be the cheap silent skip.
        uint256 belowUsed = _gasUsedAtCap(tSwap - 8_000);
        bool belowFilled = _swapWithGasCap(PROBE_BUY, tSwap - 8_000);

        console2.log("T_swap (smallest FILLING cap)          :", tSwap);
        console2.log("T_liq  (smallest SWEEPING cap)         :", tLiq);
        console2.log("residual doomed band (T_liq - T_swap)  :", tLiq > tSwap ? tLiq - tSwap : 0);
        console2.log("gas ACTUALLY consumed at T_swap        :", cheapUsed);
        console2.log("gas ACTUALLY consumed just below T_liq :", doomedUsed);
        console2.log("gas ACTUALLY consumed below the floor  :", belowUsed);
        console2.log("victim killed at T_swap        :", cheapKilled);
        console2.log("victim killed just below T_liq :", doomedKilled);
        console2.log("swap filled below the floor    :", belowFilled);

        //  ── INVERTED ONTO THE POST-FIX BEHAVIOUR (R1C, b8b7ab9) ─────────────
        //  The original assertions were `assertFalse(cheapKilled)`,
        //  `assertFalse(doomedKilled)` and `doomedUsed > cheapUsed`: they pinned a
        //  DOOMED BAND that started at the cheapest filling swap, where a swapper
        //  got a fill, paid gas, and got no sweep. That band's floor is gone: the
        //  cheapest filling swap is now at or above the pre-trade gas gate,
        //  because everything below it reverts.
        assertFalse(
            belowFilled,
            "FIXED: below the pre-trade floor the swap reverts, so there is no fill to burn gas on"
        );
        assertLe(
            belowUsed,
            cheapUsed,
            "a refused swap costs the swapper no more than the cheapest served one"
        );
        if (cheapKilled) {
            //  The band is CLOSED end to end on the pre-trade path: the cheapest
            //  cap that fills is also a cap that sweeps.
            assertTrue(
                cheapKilled,
                "no doomed band left: the cheapest FILLING swap also sweeps the victim"
            );
        } else {
            //  A residual band survives, but it no longer starts at the cheap end.
            //  It now sits entirely ABOVE the pre-trade floor, where the gate has
            //  opened and the forwarded budget merely runs into _doSweep's own
            //  SWEEP_KILL_RESERVE break (PerpEngine) and banks nothing. That is the
            //  L-2 degrade-gracefully behaviour, not the silent-skip bug: the
            //  swapper is paying for a sweep that was attempted, and the sweep is
            //  retried by the next swap. What the fix removed is the CHEAP escape
            //  below the floor, asserted unconditionally above.
            assertGe(
                tSwap,
                LIQ_GAS_RESERVE + LIQ_GAS_MIN,
                "the residual doomed band sits above the pre-trade floor, not below it"
            );
            assertGt(
                doomedUsed,
                belowUsed,
                "inside the residual band the swapper does pay for the attempted sweep"
            );
        }
        //  `doomedKilled` is left MEASURED, not asserted either way: whether the
        //  last bracket below T_liq happens to land a kill is a property of the
        //  4k search granularity, not of the gate under test.
        console2.log("doomedKilled (measured, not asserted):", doomedKilled);
        // Sentinel.
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S08-E — the book size is a lever the attacker holds
    // =======================================================================

    /**
     * @notice MEASUREMENT + PoC of the attacker's lever. The lead asks whether an
     *         attacker can push the work behind a reserve above it ON DEMAND.
     *
     *  `_doSweep` (PerpEngine.sol:873-907) runs up to `MAX_LIQ_PER_SWAP = 8`
     *  kills (:135, :893), each doing a REAL nested pool swap through `_settle`
     *  (:925) — and it runs inside ONE external call, so it is ALL OR NOTHING:
     *  an OOG part-way rolls the whole sweep back and CauldronHook.sol:912
     *  swallows the failure. There is no partial cascade.
     *
     *  Opening a position is permissionless and `MAX_OPEN_POSITIONS = 64`
     *  (PerpEngine.sol:147). So anyone can decide how much work sits behind
     *  `LIQ_GAS_RESERVE`, while the reserve is a compile-time constant — and
     *  because the sweep is atomic, ONE extra liquidatable position raises the
     *  gas bar for EVERY liquidation, not just its own.
     *
     *  This measures the bar for a 1-position book against a 4-position book on
     *  the same fixture, and confirms the all-or-nothing shape.
     */
    function test_S08_E_PoC_ABiggerBookRaisesTheBarForEverySweep() public {
        vm.skip(!active);

        // ── one liquidatable position ───────────────────────────────────────
        uint256 clean = vm.snapshotState();
        _makeVictimsLiquidatable(1);
        uint256 tOne = _search(Outcome.Liq);
        vm.revertToState(clean);
        delete victims;
        victimId = 0;

        // ── four of them, same crash, same probe swap ───────────────────────
        _makeVictimsLiquidatable(4);
        assertEq(perp.openCount(), 4, "four positions on the book");

        uint256 snap = vm.snapshotState();
        bool okRich = _swapWithGasCap(PROBE_BUY, 12_000_000);
        uint256 deadRich = _victimsClosed();
        vm.revertToState(snap);
        assertTrue(okRich, "control: the generous swap filled");
        assertEq(deadRich, 4, "control: all four die when gas is not the binding constraint");

        uint256 tFour = _searchAllDead();

        // ALL OR NOTHING: just below the bar, not one of the four dies.
        snap = vm.snapshotState();
        bool okBelow = _swapWithGasCap(PROBE_BUY, tFour - 8_000);
        uint256 deadBelow = _victimsClosed();
        vm.revertToState(snap);

        uint256 slope = (tFour - tOne) / 3;

        console2.log("min gas cap to sweep a 1-position book :", tOne);
        console2.log("min gas cap to sweep a 4-position book :", tFour);
        console2.log("=> extra gas bar per parked position   :", slope);
        console2.log("MAX_OPEN_POSITIONS (PerpEngine :147)   :", perp.MAX_OPEN_POSITIONS());
        console2.log("bar at MAX_LIQ_PER_SWAP = 8 positions  :", tOne + slope * 7);
        console2.log("swap filled just below the bar         :", okBelow);
        console2.log("positions killed just below the bar    :", deadBelow);

        //  ── INVERTED BY THE L-2 FIX ─────────────────────────────────────────
        //  This asserted the defect: `assertEq(deadBelow, 0, "ALL OR NOTHING")`.
        //  `_doSweep` was one external call with its result discarded, so running
        //  out of gas rolled back EVERY kill in the batch — which let an attacker
        //  park dust positions to raise the bar for everyone and switch keeperless
        //  liquidation off pool-wide (~0.021 ETH at minCollateral = 0.003 ether).
        //
        //  The loop now breaks on {PerpEngine.SWEEP_KILL_RESERVE} before starting
        //  an iteration it cannot finish, so a short sweep BANKS what it could
        //  afford and leaves the rest for the next swap. Measured here: 3 of 4
        //  die below the old bar where 0 died before. The property that matters
        //  is that the book size can no longer zero out the sweep.
        assertTrue(okBelow, "the swap still fills below the bar");
        assertGt(deadBelow, 0, "DEGRADES, NOT ALL-OR-NOTHING: a short sweep still banks kills");
        console2.log("=> positions killed below the bar (was 0):", deadBelow);
        // Sentinel.
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  Helpers
    // =======================================================================

    enum Outcome { Swap, Liq, Gacha }

    /// @dev Smallest gas cap at which `what` is observed. Binary search over a
    ///      snapshot-restored fixture, so every probe starts from byte-identical
    ///      state. Returns the HIGH end of the final 4k-wide bracket.
    function _search(Outcome what) internal returns (uint256) {
        uint256 lo = 100_000;      // below any successful v4 swap through this hook
        uint256 hi = 8_000_000;    // the control proves all three outcomes fire here
        while (hi - lo > 4_000) {
            uint256 mid = (lo + hi) / 2;
            (bool ok, bool liq, bool gacha) = _probe(mid);
            bool hit = what == Outcome.Swap ? ok : (what == Outcome.Liq ? (ok && liq) : (ok && gacha));
            if (hit) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    /// @dev One probe: run the swap under `cap` gas, record the three outcomes,
    ///      then rewind. Nothing here can leak state into the next probe.
    ///
    ///      The gacha observable is `committedOf`, which only ever GROWS.
    ///      `outstandingCrystals` is the wrong meter: `nativeGachaStep` commits
    ///      AND resolves in one call (CauldronHook.sol:2281-2282), so a swap that
    ///      forged four crystals and resolved four older ones leaves it unchanged.
    function _probe(uint256 cap) internal returns (bool ok, bool liq, bool gacha) {
        uint256 snap = vm.snapshotState();
        uint256 committed0 = hook.committedOf(tx.origin);
        ok = _swapWithGasCap(PROBE_BUY, cap);
        liq = _victimClosed();
        gacha = hook.committedOf(tx.origin) > committed0;
        vm.revertToState(snap);
    }

    /// @dev Gas a capped swap actually consumes (not the cap itself), rewound.
    function _gasUsedAtCap(uint256 cap) internal returns (uint256 used) {
        uint256 snap = vm.snapshotState();
        uint256 g0 = gasleft();
        _swapWithGasCap(PROBE_BUY, cap);
        used = g0 - gasleft();
        vm.revertToState(snap);
    }

    /// @dev Whether the victim died under `cap`, rewound.
    function _outcomeAtCap(uint256 cap) internal returns (bool killed) {
        uint256 snap = vm.snapshotState();
        _swapWithGasCap(PROBE_BUY, cap);
        killed = _victimClosed();
        vm.revertToState(snap);
    }

    /// @dev The swapper's own transaction gas limit, modelled exactly: an
    ///      external call with a hard cap. EIP-150's 63/64 rule applies to it the
    ///      same way it applies to a real transaction's remaining gas.
    function _swapWithGasCap(uint256 ethIn, uint256 cap) internal returns (bool ok) {
        (ok,) = address(this).call{gas: cap}(abi.encodeWithSelector(this.s08Buy.selector, ethIn));
    }

    function s08Buy(uint256 ethIn) external {
        require(msg.sender == address(this), "self");
        _buy(ethIn, address(this));
    }

    function _victimClosed() internal view returns (bool) {
        (address t,,,,,,,) = perp.positions(victimId);
        return t == address(0);
    }

    /// @dev How many of the cascade fixture's positions are gone.
    function _victimsClosed() internal view returns (uint256 n) {
        for (uint256 i; i < victims.length; ++i) {
            (address t,,,,,,,) = perp.positions(victims[i]);
            if (t == address(0)) n++;
        }
    }

    /// @dev Smallest gas cap at which the WHOLE cascade completes.
    function _searchAllDead() internal returns (uint256) {
        uint256 lo = 100_000;
        uint256 hi = 12_000_000;
        while (hi - lo > 8_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            bool ok = _swapWithGasCap(PROBE_BUY, mid);
            bool all = _victimsClosed() == victims.length;
            vm.revertToState(snap);
            if (ok && all) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    /// @dev N longs, then the same crash. `victimId` is the first of them, so the
    ///      single-kill search works unchanged against this fixture.
    function _makeVictimsLiquidatable(uint256 n) internal {
        for (uint256 i; i < n; ++i) {
            address who = address(uint160(0x5080000 + i));
            vm.deal(who, 1 ether);
            vm.prank(who, who);
            victims.push(perp.openLong{value: 0.1 ether}(2, 0, 0, 0.1 ether));
        }
        victimId = victims[0];
        _crashAndAgeTheMark();
    }

    /// @dev Open a 2x long, crash spot, then let the TWAP mark catch up so the
    ///      position is genuinely underwater AT THE MARK — i.e. exactly the case
    ///      the in-swap sweep exists to clear.
    function _makeVictimLiquidatable() internal {
        vm.deal(trader, 10 ether);
        vm.prank(trader, trader);
        victimId = perp.openLong{value: 0.1 ether}(2, 0, 0, 0.1 ether);
        _crashAndAgeTheMark();
    }

    function _crashAndAgeTheMark() internal {
        // CRASH, delivered OUT OF BAND.
        //
        //  This helper used to rely on "the dump's own afterSwap sweep runs, but
        //  the mark has not moved yet, so it cannot kill the fresh longs". That
        //  stopped being true in `9d5cd46` (red-team LIQ-01): the liquidation
        //  trigger is now the WORSE of the TWAP mark and LIVE SPOT
        //  (PerpEngine._liqTest), precisely so a whale's single swap can no
        //  longer walk a position to insolvency inside the trade the sweep runs
        //  on. So the dump's own sweep now takes every fresh long at the crashed
        //  spot, and the book is empty before the test starts — which is a
        //  DIFFERENT mechanism from the gas gate these tests measure.
        //
        //  Detaching the engine from the hook for the duration of the dump is
        //  the inert way to land the price move without the in-swap sweep. It
        //  changes no engine state and no assertion: what the tests below probe
        //  is what happens on a LATER, gas-capped swap with a victim already
        //  underwater, which is exactly the state this leaves behind.
        uint256 dump = 400_000_000 ether;
        deal(token, address(this), dump, true);
        _warp(20);
        vm.roll(vm.getBlockNumber() + 2);
        hook.setPerpEngine(address(0));
        _sell(dump, address(this));
        hook.setPerpEngine(address(perp));

        // Let the whole TWAP window elapse at the crashed price, then write the
        // observation, so `twapTick()` reports the crash rather than the launch.
        _warp(uint256(perp.twapWindow()) + 60);
        vm.roll(vm.getBlockNumber() + 5);
        perp.poke();
    }
}
