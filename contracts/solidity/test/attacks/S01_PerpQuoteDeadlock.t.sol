// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {YBase, YRelaunchRunner} from "./YBase.sol";
import {BGovQuoted} from "./B05_NonEthRelaunchBrick.t.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  S-01 — THE PERP QUOTE DEADLOCK: mechanism, and how far reachability goes
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  ── THE MECHANISM (read-verified, not in doubt) ────────────────────────────
 *
 *   1. `PerpEngine._key()` (PerpEngine.sol:449-455) builds the PoolKey from its
 *      OWN `quote` storage slot (:450) and `registry.currentToken()` read LIVE
 *      (:451). The two halves have different update rules.
 *   2. `quote` is written in exactly ONE place: `syncGeneration` (:1027), which
 *      refuses while `openCount != 0` (:987, :1026).
 *   3. `CauldronHook.isDead` opens `if (!trackedPools[id]) return false;`
 *      (:1540) — an UNTRACKED pool reports NOT DEAD.
 *   4. `PerpEngine._isDead()` (:1216) asks the hook about `_key().toId()`.
 *   5. So if `quote` ever disagrees with the live generation's quote ACROSS a
 *      relaunch, `_key()` names a pair that was never initialised: `isDead`
 *      false → `forceCloseDead` (:937) and `forceCloseAllDead` (:950) both
 *      `revert NotDead()` → `openCount` never reaches 0 → `syncGeneration`
 *      reverts `PositionsOpen()` forever. A closed loop.
 *   6. VALUE LOSS: `_settle` → `_swapExactIn` → `_run`/`unlockCallback` →
 *      `_swapBody`, whose first line is `PoolKey memory key = _key();` (:1184).
 *      `close(id, minOut)` (:816) checks only `p.trader != msg.sender`, so the
 *      trader's own exit routes through the same dead key.
 *
 *  ── WHAT THIS SUITE ESTABLISHES ABOUT REACHABILITY ─────────────────────────
 *
 *  Divergence needs `PerpEngine.quote != registry.generationQuote(currentGen)`
 *  while `openCount > 0`. Three candidate routes were driven on a live fork:
 *
 *   ROUTE A — a relaunch that CHANGES the quote while positions survive.
 *     Blocked by {PoolOps.seedFunding}'s "NEVER STRAND `recovered`" rule
 *     (PoolOps.sol:1037/1043/1048). Every branch that could return an asset
 *     other than `oldQuote` is gated on `recovered == 0`, and
 *     `CauldronRegistry._removeLiquidity` (:1502) always unwinds the
 *     FULL-RANGE active position (PoolOps.sol:729-730 mines min/max ticks), so
 *     `recovered > 0` for any generation that ever held liquidity.
 *     → the quote is PRESERVED across a relaunch, and a preserved quote keeps
 *       `_key()` pointing at the pool that was just created.
 *
 *   ROUTE B — a live rotation. `RedemptionExt.rotateSlice` flips
 *     `generationQuote[gen]` and calls `syncGeneration()` in the SAME call,
 *     inside a try/catch. The swallow is safe here because nothing in that
 *     context can make the sync revert: `linkVolume` (RedemptionExt.sol:372)
 *     already proved `openCount == 0` (CauldronHook.sol:1518), the generation
 *     is unchanged so `migrateInventory` is skipped, and `notNested`
 *     (PerpEngine.sol:421) tests `_inLocked`/`_liqReentry`, which are set ONLY
 *     inside `_doSweep` and always cleared before it returns.
 *
 *   ROUTE C — the OPERATOR route, and the one that lands. `CauldronHook`'s own
 *     interlock note tells the operator how to diversify a quote while perps
 *     are open: "Close the positions (OR UNSET THE ENGINE) before diversifying
 *     the quote" (CauldronHook.sol:1514-1515). Taking the second half of that
 *     advice removes BOTH guards at once — `linkVolume` skips its `PerpsOpen`
 *     check when `perpEngine == address(0)` (:1517), and `rotateSlice` skips
 *     its in-call re-point for the same reason (RedemptionExt.sol:447-448).
 *     The rotation then completes over a book that is still full, and re-wiring
 *     the engine restores a machine whose `quote` no reachable call can move.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract S01_PerpQuoteDeadlock is YBase {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;
    YRelaunchRunner internal runner;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        _bootPerp(60 ether, 200_000_000 ether);

        // A quote that sorts BELOW PoolOps.QUOTE_WATERMARK, per B-05's rig.
        for (uint256 i; i < 32; ++i) {
            MockQuoteToken c = new MockQuoteToken("Magic USD", "USDG", 6);
            if (uint160(address(c)) < uint160(0xf000000000000000000000000000000000000000)) {
                usdg = c;
                break;
            }
        }
        require(address(usdg) != address(0), "no sub-watermark quote");
        registry.setAllowedQuote(address(usdg), true, 1e18);

        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(
            IVotes721(address(new SVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));

        runner = new YRelaunchRunner();
        vm.roll(vm.getBlockNumber() + 60);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  Rig
    // ───────────────────────────────────────────────────────────────────────

    /// @dev Stand up + curate the ETH/USDG venue the rotator swaps through.
    ///      Lifted verbatim from F-10, which is the canonical rotation rig.
    function _seedVenue() internal returns (PoolKey memory route) {
        uint256 venueUsdg = 400_000e6;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 40 ether, venueUsdg, 60, 3000
        );
        route = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        rotator.setVenue(route, true);
    }

    /// @dev Approve a full-size ETH -> USDG envelope the way the guild would.
    function _approveEnvelope() internal {
        _approveEnvelopeTo(address(usdg));
    }

    /// @dev Approve a full-size envelope to any destination, INCLUDING native
    ///      ether — which is the case R-03 was about, so it must be expressible.
    function _approveEnvelopeTo(address dest) internal {
        _warp(governor.COOLDOWN() + 1);
        uint256 id = governor.propose(dest, governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
    }

    /// @dev Rotate until the envelope is spent. Returns the slice count.
    ///
    ///  Loops on the REMAINING BPS, not on the destination address. The
    ///  destination is `address(0)` for a perfectly good rotation back to ether
    ///  (R-03), so testing it for emptiness would exit before the first slice.
    function _rotateToCompletion(PoolKey memory route) internal returns (uint256 slices) {
        for (uint256 i; i < 24; ++i) {
            (, uint16 left) = governor.allowance();
            if (left == 0) break;
            try registry.rotateSlice(2500, 0, route) { slices++; }
            catch (bytes memory err) {
                console2.log("rotateSlice reverted after slices:", slices);
                console2.logBytes(err);
                break;
            }
        }
    }

    /// @dev Fill the perp book to MAX_OPEN_POSITIONS with leverage-1 dust longs
    ///      (zero OI, so no risk cap binds) — the Y-03 book-filling primitive.
    function _fillBook(uint256 tag) internal returns (uint256 filled) {
        uint256 cap = perp.MAX_OPEN_POSITIONS();
        for (uint256 i; i < cap; i++) {
            address bot = address(uint160(tag + i));
            vm.deal(bot, 0.01 ether);
            vm.prank(bot, bot);
            perp.openLong{value: 0.004 ether}(1, 0, 0, 0.004 ether);
        }
        filled = perp.openCount();
    }

    /// @dev Total collateral still locked in the book (ETH wei, as booked).
    function _lockedCollateral() internal view returns (uint256 locked) {
        uint256 n = perp.nextId();
        for (uint256 id = 1; id < n; ++id) {
            (address t,, uint128 col,,,,,) = perp.positions(id);
            if (t != address(0)) locked += col;
        }
    }

    /// @dev First still-open position id, or 0.
    function _anyOpenId() internal view returns (uint256) {
        uint256 n = perp.nextId();
        for (uint256 id = 1; id < n; ++id) {
            (address t,,,,,,,) = perp.positions(id);
            if (t != address(0)) return id;
        }
        return 0;
    }

    /// @dev ROUTE C, up to (but not including) the relaunch: a full book, the
    ///      engine unset for the rotation exactly as CauldronHook.sol:1514-1515
    ///      advises, the rotation completed, the engine re-wired.
    function _driveRouteCDivergence(uint256 tag) internal {
        _fillBook(tag);
        assertEq(perp.openCount(), perp.MAX_OPEN_POSITIONS(), "book filled to the cap");

        PoolKey memory route = _seedVenue();
        _approveEnvelope();

        // THE DOCUMENTED WORKAROUND. `linkVolume` only checks `openCount` when an
        // engine is wired (CauldronHook.sol:1517), and `rotateSlice` only
        // re-points an engine it can see (RedemptionExt.sol:447).
        hook.setPerpEngine(address(0));

        uint256 slices = _rotateToCompletion(route);
        assertGt(slices, 0, "the rotation must actually run");
        (address remaining,) = governor.allowance();
        assertEq(remaining, address(0), "envelope spent - the rotation COMPLETED");

        // The operator puts the engine back, believing the interlock did its job.
        hook.setPerpEngine(address(perp));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  ROUTE B — REFUTATION. A live rotation cannot diverge the engine.
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice REGRESSION GUARD (Route B refuted). With the engine wired, a
    ///         completed rotation re-points `PerpEngine.quote` in the SAME
    ///         transaction that flips `generationQuote`. The try/catch around
    ///         that sync (RedemptionExt.sol:448) swallows nothing, because in
    ///         that context the sync cannot fail: `linkVolume` (:372) already
    ///         proved `openCount == 0`, the generation is unchanged so the
    ///         inventory migration is skipped, and `notNested` reads flags that
    ///         only `_doSweep` ever sets.
    function test_refute_routeB_rotationRepointsTheEngineInTheSameCall() public {
        vm.skip(!active);

        assertEq(perp.quote(), address(0), "engine starts on ETH");
        assertEq(registry.generationQuote(1), address(0), "generation starts on ETH");

        PoolKey memory route = _seedVenue();
        _approveEnvelope();
        assertGt(_rotateToCompletion(route), 0, "the rotation must actually run");

        assertEq(registry.generationQuote(1), address(usdg), "generation followed the liquidity");

        //  ── RE-AMENDED BY X8-01: THE ORIGINAL ASSERTION IS TRUE AGAIN ───────
        //  R-08 weakened this from "adopts" to "parks", because `plv` is a bare
        //  counter paid out in whatever `quote` names today and adopting would have
        //  re-denominated the 60 ETH `_bootPerp` donates into an asset the engine
        //  does not hold. Adoption no longer does that: it SWEEPS the old-asset
        //  counters to the treasury IN THE OLD ASSET (before the flip) and zeroes
        //  them, so there is nothing left to re-denominate. `_bootPerp` funds through
        //  `fundPlv`, which is documented as a SHARE-LESS PERMANENT DONATION by the
        //  owner — so the treasury is precisely where that capital belongs, and no
        //  staker exists to mispay. (Staker capital arrives via the vault, and
        //  `hasStakers()` still refuses the flip while any of it is present.)
        //
        //  So Route B is refuted in its strongest form: the engine never diverges.
        assertEq(perp.quote(), address(usdg), "the engine re-points in the SAME call");
        assertEq(perp.plv(), 0, "its old-asset PLV was swept, not re-denominated");
        assertEq(perp.insuranceEth(), 0, "and neither was the old-asset buffer");
        vm.expectRevert(PerpEngine.AlreadySynced.selector);
        perp.syncGeneration();
    }

    /// @notice REGRESSION GUARD (Route B's other half). The interlock that makes
    ///         the in-call sync sound: while ANY position is open, the rotation
    ///         cannot run at all. `CauldronHook.linkVolume` reverts `PerpsOpen`
    ///         (:1518) and `rotateSlice` calls it before it flips anything.
    function test_refute_routeB_rotationRefusedWhileTheBookIsOpen() public {
        vm.skip(!active);

        PoolKey memory route = _seedVenue();
        _approveEnvelope();

        vm.deal(trader, 1 ether);
        vm.prank(trader, trader);
        perp.openLong{value: 0.004 ether}(1, 0, 0, 0.004 ether);
        assertGt(perp.openCount(), 0, "a position is open");

        vm.expectRevert();
        registry.rotateSlice(2500, 0, route);

        assertEq(registry.generationQuote(1), address(0), "nothing was flipped");
        assertEq(perp.quote(), address(0), "engine untouched");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  ROUTE A — REFUTATION. A relaunch cannot change the quote out from under
    //  a surviving book, because `seedFunding` refuses to strand `recovered`.
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice REGRESSION GUARD (Route A refuted). Y-03's exact setup — a book
    ///         filled to the cap and a relaunch run under a gas cap that CANNOT
    ///         force-close all 64 — plus a governor naming an ALLOWLISTED
    ///         non-native quote, which is the only input that could make
    ///         `seedFunding` return something other than the dying quote.
    ///
    ///  It still returns native, because branch 1 (PoolOps.sol:1037) is gated on
    ///  `recovered == 0 || oldQuote == wantQuote` and `_removeLiquidity` recovered
    ///  the whole full-range active position. Quote preserved ⇒ `_key()` names the
    ///  pool that was just created ⇒ `isDead` is answerable ⇒ the survivors clear.
    function test_refute_routeA_relaunchPreservesTheQuoteUnderASurvivingBook() public {
        vm.skip(!active);

        _fillBook(0xD05100);
        assertEq(perp.openCount(), perp.MAX_OPEN_POSITIONS(), "book filled to the cap");

        // The one input that could flip the quote: a winning proposal naming an
        // allowlisted ERC20. (B-05's governor mock — a SWAPPED governor.)
        registry.setGovernor(address(new BGovQuoted(address(usdg))));

        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);

        assertTrue(runner.tryRelaunch(address(registry), 24_000_000), "rebirth completes");
        assertEq(registry.currentGeneration(), 2, "reborn to gen 2");
        uint256 survivors = perp.openCount();
        console2.log("survivors of the gas-capped force-close:", survivors);

        // THE GUARD: `recovered > 0`, so the newborn is seeded in the DYING
        // generation's own denomination, whatever the proposal asked for.
        assertEq(registry.generationQuote(2), address(0), "quote PRESERVED - recovered was not stranded");
        assertEq(perp.quote(), registry.generationQuote(2), "engine and generation agree");

        // And because they agree, the survivors are clearable permissionlessly.
        uint256 guard;
        while (perp.openCount() != 0 && guard < 8) {
            perp.forceCloseAllDead();
            unchecked { guard++; }
        }
        assertEq(perp.openCount(), 0, "every survivor cleared by a permissionless call");
        if (perp.syncedGeneration() != 2) perp.syncGeneration();
        assertEq(perp.syncedGeneration(), 2, "engine re-armed");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  ROUTE C — the operator route. Divergence with a full book.
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice POC (Route C, stage 1): following the hook's own advice — "unset
    ///         the engine before diversifying the quote" (CauldronHook.sol:1515)
    ///         — produces exactly the state the whole mechanism needs:
    ///         `PerpEngine.quote != registry.generationQuote(currentGen)` with
    ///         `openCount > 0`, and NO reachable call that can correct it.
    function test_poc_routeC_unsetEngineStrandsTheQuoteWithAFullBook() public {
        vm.skip(!active);

        _driveRouteCDivergence(0xD05C00);

        assertEq(registry.generationQuote(1), address(usdg), "the generation is now USDG-quoted");
        assertEq(perp.quote(), address(0), "the ENGINE is still on ETH");
        assertTrue(perp.quote() != registry.generationQuote(registry.currentGeneration()), "DIVERGED");
        assertGt(perp.openCount(), 0, "and the book is not empty");
        console2.log("locked collateral (wei):", _lockedCollateral());

        //  ── INVERTED BY THE R-07 FIX ────────────────────────────────────────
        //  Unsetting the engine still lets the divergence HAPPEN — that is the
        //  operator footgun, and the fix for it is the removed advice at
        //  CauldronHook.sol:1514 plus the guard below, not a new authority check.
        //  What changed is the consequence. This test used to assert that neither
        //  corrective call was reachable:
        //
        //      vm.expectRevert(PerpEngine.PositionsOpen.selector); syncGeneration();
        //      vm.expectRevert(PerpEngine.NotDead.selector);       forceCloseAllDead();
        //      vm.expectRevert(PerpEngine.NotDead.selector);       forceCloseDead(id);
        //
        //  {PerpEngine._isDead} now reads a diverged quote as death, so the book is
        //  force-closeable and the engine re-pointable — by anyone, immediately,
        //  without waiting for the generation to die.
        uint256 id = _anyOpenId();
        perp.forceCloseDead(id);
        (address gone,,,,,,,) = perp.positions(id);
        assertEq(gone, address(0), "a single diverged position force-closes");

        perp.forceCloseAllDead();
        assertEq(perp.openCount(), 0, "and so does the rest of the book");

        //  ── AND ADOPTION NO LONGER WAITS EITHER (X8-01) ──────────────────────
        //  This expected `VaultStaked`: the flip used to be refused while the engine
        //  held any quote-side capital. That refusal was unreachable-zero in practice
        //  — `insuranceEth` cannot be driven to zero once the deploy arms its floor —
        //  so it froze healthy engines rather than protecting them. The flip now
        //  sweeps the old-asset counters to the treasury in the OLD asset and zeroes
        //  them. This POC's thesis was "NO reachable call that can correct it"; it is
        //  now false in BOTH stages, which is the whole point.
        perp.syncGeneration();
        assertEq(
            perp.quote(), registry.generationQuote(registry.currentGeneration()),
            "a stranger re-pointed the engine: no owner, no wait"
        );
        assertEq(perp.plv(), 0, "the old-asset PLV was swept, not re-denominated");
        assertEq(_lockedCollateral(), 0, "no collateral is left locked");
        assertTrue(true, "reached");
    }

    /// @notice SCOPE, STATED HONESTLY (Route C, stage 1). While the generation
    ///         has NOT been reborn, `_key()` still names the ORIGINAL pool, which
    ///         a v4 pool being permanent means still exists — drained by the
    ///         rotation, but tradeable. So the trader's own `close` still works
    ///         and the damage at this stage is a stale mark, not lost funds.
    ///         This is the boundary the next test crosses.
    function test_poc_routeC_stage1TraderCanStillExit() public {
        vm.skip(!active);

        _driveRouteCDivergence(0xD05D00);

        uint256 id = _anyOpenId();
        (address t,, uint128 col,,,,,) = perp.positions(id);
        uint256 before = perp.openCount();

        vm.prank(t, t);
        perp.close(id, 0);

        assertEq(perp.openCount(), before - 1, "the trader's own exit still works pre-rebirth");
        console2.log("collateral that was still recoverable (wei):", col);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  THE LIVENESS INVARIANT
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice LIVENESS INVARIANT: an open position must ALWAYS be eventually
    ///         closeable, and the engine must always be re-syncable.
    ///
    ///  Drives Route C all the way through the rebirth. Once `currentToken`
    ///  advances, the diverged `quote` makes `_key()` name a pair that was never
    ///  initialised — and every exit is gone at once.
    function test_invariant_openPositionAlwaysEventuallyCloseable() public {
        vm.skip(!active);

        _driveRouteCDivergence(0xD05E00);
        uint256 lockedBefore = _lockedCollateral();

        // Kill the generation and rebirth it under Y-03's gas cap, so the
        // bounded force-close cannot drain the book.
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        bool reborn = runner.tryRelaunch(address(registry), 24_000_000);
        console2.log("rebirth completed:", reborn);
        console2.log("generation now:", registry.currentGeneration());
        console2.log("generationQuote(new):", registry.generationQuote(registry.currentGeneration()));
        console2.log("perp.quote():", perp.quote());
        console2.log("openCount:", perp.openCount());
        console2.log("locked collateral before (wei):", lockedBefore);
        console2.log("locked collateral now (wei):", _lockedCollateral());

        //  NO EARLY RETURN. A `return` here would leave the assertions below
        //  unexecuted while Foundry still reported PASS — the exact false-green
        //  that made the first version of this suite worthless. `id == 0` (nothing
        //  survived the rebirth) satisfies the liveness property outright, so it
        //  seeds `closed` rather than skipping the checks.
        uint256 id = _anyOpenId();
        bool closed = (id == 0);

        // SOME permissionless call must be able to close it.
        if (!closed) { try perp.forceCloseAllDead() { closed = perp.openCount() == 0; } catch {} }
        if (!closed) { try perp.forceCloseDead(id) { closed = true; } catch {} }
        if (!closed) { try perp.liquidate(id) { closed = true; } catch {} }
        if (!closed) {
            (address t,,,,,,,) = perp.positions(id);
            vm.prank(t, t);
            try perp.close(id, 0) { closed = true; } catch {}
        }

        assertTrue(closed, "LIVENESS: an open position must be closeable by SOMEONE");

        //  ... and the engine must end up pointing at the live generation's asset.
        //  Guarded on the QUOTE, not on `openCount`: the relaunch's own
        //  housekeeping may already have re-armed the engine, and `syncGeneration`
        //  reverts `AlreadySynced()` when there is nothing left to adopt.
        uint256 g = registry.currentGeneration();
        if (perp.quote() != registry.generationQuote(g)) perp.syncGeneration();
        assertEq(perp.quote(), registry.generationQuote(g), "engine re-synced");
    }

    /// @notice THE R-07 INVARIANT, and the one that still had teeth after R-02.
    ///
    ///  A diverged engine must be recoverable BY PERMISSIONLESS CALLS, without
    ///  waiting for a rebirth. Divergence is reached the way the hook's own
    ///  guidance invites (Route C: unset the engine, rotate, wire it back), and
    ///  from there nothing privileged should be required to put it right.
    ///
    ///  RED before the fix: `forceCloseAllDead` reverts `NotDead()` — the engine's
    ///  `_key()` names the pre-rotation pool, which is drained but very much alive
    ///  — so `openCount` never falls and `syncGeneration` reverts `PositionsOpen()`
    ///  forever. Until the generation happens to die, the engine marks, funds and
    ///  liquidates against a pool the treasury has emptied, and no one can stop it.
    ///
    ///  NOTE ON SCOPE: the PERMANENT, across-a-rebirth version of this was really
    ///  R-02 (relaunch could not complete at all), and the R-02 fix resolved it —
    ///  this test deliberately never relaunches, so it isolates what is left.
    function test_invariant_divergedEngineIsPermissionlesslyRecoverable() public {
        vm.skip(!active);

        _driveRouteCDivergence(0xD05F00);

        uint256 gen = registry.currentGeneration();
        console2.log("perp.quote()          :", perp.quote());
        console2.log("generationQuote(gen)  :", registry.generationQuote(gen));
        console2.log("openCount             :", perp.openCount());
        console2.log("locked collateral wei :", _lockedCollateral());

        assertTrue(perp.quote() != registry.generationQuote(gen), "precondition: the quote diverged");
        assertGt(perp.openCount(), 0, "precondition: the book is not empty");

        //  A stranger drains the book and re-points the engine. Every call here is
        //  permissionless; none of them is allowed to need an owner.
        perp.forceCloseAllDead();
        assertEq(perp.openCount(), 0, "LIVENESS: the book must be drainable by anyone");

        //  ── RECOVERY IS ONE PERMISSIONLESS STAGE AGAIN (X8-01) ──────────────
        //  Stage 1 (above) was the originally-broken half: the book could not be
        //  drained at all. Anyone can now do it.
        //
        //  Stage 2 used to expect `VaultStaked` — adoption was refused while the
        //  engine held quote-side capital, and the note here called that "safe and
        //  bounded". It was neither. `insuranceEth` cannot be driven to zero once
        //  `skimInsurance`'s floor is armed (DeployPerp sets 0.05 ether) and the
        //  engine simultaneously REQUIRES the buffer above that floor, so the refusal
        //  was PERMANENT: the engine stayed parked for the rest of the generation and
        //  this invariant's promise was quietly false.
        //
        //  Adoption now sweeps the old-asset counters to the treasury IN THE OLD
        //  ASSET and zeroes them, so nothing is re-denominated. `_bootPerp` donates
        //  through `fundPlv`, documented as SHARE-LESS and PERMANENT, so no staker is
        //  mispaid; staker capital comes through the vault and `hasStakers()` still
        //  refuses the flip while any of it is present.
        //
        //  NOTHING PRIVILEGED, INCLUDING THE PAYOUT BOOK. `payoutOwedTotal` is the
        //  one counter that can still refuse a flip, and {PerpEngine.retirePayout}
        //  is permissionless exactly while the engine is diverged — i.e. whenever a
        //  stranded payout is what stands between it and recovery. See
        //  X3i_PayoutVetoStrandsQuote, where a stranger clears it.
        perp.syncGeneration();
        assertEq(
            perp.quote(), registry.generationQuote(gen),
            "LIVENESS: re-pointable by ANYONE, with no wait and no owner"
        );
        assertEq(perp.plv(), 0, "old-asset PLV swept, not re-denominated");

        //  AND THE RECOVERED ENGINE WILL NOT TAKE THE OLD ASSET. It is USDG-quoted
        //  now, so this native-value open is refused by `_pullQuote` (`BadParam`)
        //  before it reaches any other gate — which is the point: recovery re-points
        //  the engine at ONE asset and it accepts only that one. `TokenDead` no
        //  longer applies precisely because the engine is healthy again.
        //
        //  The other half of "no cheap leverage off the back of a recovery" — that
        //  `syncGeneration` wipes the TWAP ring and `_guardOpen` refuses `NotWarm`
        //  until it spans `twapWindow` again — is asserted directly, on a correctly
        //  funded open, in X3d_RingResetCollapsesTwap.
        address late = address(0xDEADFEE);
        vm.deal(late, 1 ether);
        vm.prank(late, late);
        vm.expectRevert(PerpEngine.BadParam.selector);
        perp.openLong{value: 0.004 ether}(1, 0, 0, 0.004 ether);
        //  Sentinel: no branch above may skip the assertions (audit rule - a
        //  Foundry test that asserts nothing still reports PASS).
        assertTrue(true, "reached");
    }

    /// @notice The other half of the fix: a diverged engine must not keep SELLING
    ///         leverage. `_guardOpen` checks warmup, death and leverage but never
    ///         quote freshness, so pre-fix a trader could open into an engine that
    ///         marks against a drained pool — and every position opened that way
    ///         deepened the hole, since `syncGeneration` refuses while any is open.
    function test_poc_routeC_divergedEngineRefusesNewLeverage() public {
        vm.skip(!active);

        _driveRouteCDivergence(0xD05D00);
        assertTrue(
            perp.quote() != registry.generationQuote(registry.currentGeneration()),
            "precondition: the quote diverged"
        );

        //  `_driveRouteCDivergence` fills the book to MAX_OPEN_POSITIONS, so
        //  `OiCapped()` would fire before the check under test. Free one slot (the
        //  trader's own exit still works here — `_key()` names the drained-but-real
        //  pre-rotation pool) so the refusal below is about QUOTE FRESHNESS and
        //  nothing else.
        uint256 victim = _anyOpenId();
        (address owner_,,,,,,,) = perp.positions(victim);
        vm.prank(owner_, owner_);
        perp.close(victim, 0);
        assertLt(perp.openCount(), perp.MAX_OPEN_POSITIONS(), "a slot is free");

        address late = address(0xDEFEA7);
        vm.deal(late, 1 ether);
        vm.prank(late, late);
        vm.expectRevert(PerpEngine.TokenDead.selector);
        perp.openLong{value: 0.004 ether}(1, 0, 0, 0.004 ether);
        //  Sentinel: the expectRevert above is the assertion; make a skipped body
        //  impossible to mistake for a pass (audit rule).
        assertTrue(true, "reached");
    }

    /// @notice REGRESSION (R-02, proved from the perp side). A rotated generation
    ///         must still be able to die and be reborn, and the engine must come
    ///         out of that rebirth pointing at the new generation's own asset.
    ///
    ///  REWRITTEN. The previous version of this test asserted that the trader's
    ///  exit was GONE after the rebirth, and it reported PASS while asserting
    ///  NOTHING: `if (!runner.tryRelaunch(...)) { log(); return; }` sat above the
    ///  assertion and the rebirth was in fact reverting every run (that revert was
    ///  R-02). With R-02 fixed the rebirth completes, so the honest thing to
    ///  assert is the property that now holds — and to reach the assertions
    ///  unconditionally, so this can never silently pass again.
    function test_regression_routeC_rebirthClearsTheBookAndRearmsTheEngine() public {
        vm.skip(!active);

        _driveRouteCDivergence(0xD06000);
        uint256 lockedBefore = _lockedCollateral();

        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);

        bool reborn = runner.tryRelaunch(address(registry), 24_000_000);
        console2.log("rebirth completed:", reborn);
        assertTrue(reborn, "R-02: a rotated generation must still be able to be reborn");

        uint256 gen = registry.currentGeneration();
        console2.log("generation now       :", gen);
        console2.log("generationQuote(new) :", registry.generationQuote(gen));
        console2.log("perp.quote()         :", perp.quote());
        console2.log("locked collateral before (wei):", lockedBefore);
        console2.log("locked collateral now    (wei):", _lockedCollateral());

        //  Whatever survived the gas-capped force-close must still be closeable,
        //  and the engine must end up re-armed on the new generation's quote.
        while (perp.openCount() != 0) perp.forceCloseAllDead();
        if (perp.quote() != registry.generationQuote(gen)) perp.syncGeneration();

        assertEq(perp.openCount(), 0, "no position is stranded across the rebirth");
        assertEq(
            perp.quote(), registry.generationQuote(gen),
            "the engine is re-armed on the new generation's asset"
        );
        assertEq(_lockedCollateral(), 0, "and no collateral is left locked");
        assertTrue(true, "reached");
    }

    /// @notice REGRESSION: multi-pool must not stay blocked. `linkVolume` reverts
    ///         `PerpsOpen()` while `openCount > 0` (CauldronHook.sol:1518), so a
    ///         book that cannot be drained also freezes every future rotation.
    ///         Draining it permissionlessly is what unblocks both.
    ///
    ///  REWRITTEN for the same reason as the test above — the previous version
    ///  returned early twice before reaching any assertion.
    function test_regression_routeC_rotationWorksAgainOnceTheBookDrains() public {
        vm.skip(!active);

        _driveRouteCDivergence(0xD06100);
        assertGt(perp.openCount(), 0, "precondition: the book is not empty");

        //  Drain it with permissionless calls only (the R-07 fix makes a diverged
        //  engine force-closeable), then re-point the engine.
        perp.forceCloseAllDead();
        assertEq(perp.openCount(), 0, "the book drains without any privileged call");
        //  No sync here: adoption waits on a drain (R-08), and the point of this
        //  test is that an EMPTY BOOK is what unblocks `linkVolume`, not the quote.

        //  With the book empty, `linkVolume`'s interlock no longer bites and a
        //  further rotation runs. Rotating BACK to ether also exercises R-03.
        PoolKey memory route = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        _approveEnvelopeTo(address(0));
        vm.prank(attacker);
        (uint256 movedOut,) = registry.rotateSliceFrom(1, 2500, 0, route);
        assertGt(movedOut, 0, "rotation runs again once the book is empty");
        assertTrue(true, "reached");
    }
}

contract SVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    /// @dev Mirrors `Votes.getPastTotalSupply` — the quorum denominator the
    ///      real vote source ({MiFrensGenesis}) actually implements.
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
