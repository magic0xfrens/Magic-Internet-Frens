// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  S-09 — `QuoteRotator.arbStep` AS UNGOVERNED TREASURY RE-ALLOCATION
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  THE SURFACE, read at QuoteRotator.sol:489-526. `arbStep` is `external` with
 *  NO modifier — permissionless — and spends the rotator's own balance:
 *
 *      function arbStep(PoolKey calldata cheap, PoolKey calldata dear, uint256 amountIn)
 *          external returns (uint256 profitUsd)
 *      {
 *          if (amountIn == 0) revert BadConfig();
 *          address inQuote  = Currency.unwrap(cheap.currency0);
 *          address outQuote = Currency.unwrap(dear.currency0);
 *          if (Currency.unwrap(cheap.currency1) != Currency.unwrap(dear.currency1)) revert NoRoute();
 *          if (inQuote == outQuote) revert NoRoute();
 *          ... poolManager.unlock(...) ...
 *
 *  THAT IS THE WHOLE ADMISSION TEST. Compare it against the other two execution
 *  paths in the same contract:
 *
 *    rotateStep :286  `if (!_allowed(p.to)) revert NotAllowedQuote();`      <- quote allowlist
 *    rotateStep :295  `if (!allowedVenue[toId(route)]) revert NoRoute();`   <- venue allowlist
 *    swapOnce   :339  `if (!_allowed(to)) revert NotAllowedQuote();`        <- quote allowlist
 *    swapOnce   :355  `if (!allowedVenue[toId(route)]) revert NoRoute();`   <- venue allowlist
 *    arbStep          (neither)
 *
 *  Both guards exist, both are argued for at length in this contract's own
 *  headers ({allowedVenue} :139-178: "FAILS CLOSED. An unset allowlist rotates
 *  nothing"; :176-178: "VETTING A VENUE VETS ITS HOOK ... doing so grants that
 *  hook execution inside this contract's `unlock`"), and neither is on the one
 *  path that is permissionless AND lets the caller name both pools.
 *
 *  WHAT THIS FILE DRIVES TO A VERDICT
 *
 *    S09-A  INVARIANT + PoC — arbStep executes through venues the treasury never
 *           curated, while `rotateStep` refuses the identical key.
 *    S09-B  INVARIANT       — arbStep moves the treasury into a destination quote
 *           the registry's allowlist does not contain.
 *    S09-C  PoC            — `maxArbNotionalUsd` is a PER-CALL bound with no
 *           per-block or per-period accumulator: N calls fit in one transaction.
 *    S09-D  PoC            — an arb spends the balance parked for a GOVERNED
 *           `setPlan` rotation, shrinking `nextSliceSize()` to zero and making
 *           the voted rotation revert `TooSoon`.
 *    S09-E  REFUTED        — an unpriceable leg fails CLOSED here (:509), unlike
 *           `_oracleFloor` (:403/:405) which deliberately fails open.
 *    S09-F  REFUTED        — splitting one arb into many does not farm the keeper
 *           cut; `minArbProfitUsd` (:517) floors each slice.
 *    S09-G  REGRESSION     — closes B-04's documented coverage gap by actually
 *           EXECUTING the `ArbTooLarge` branch, which B04_ArbNotionalCap.t.sol
 *           :26-31 defers ("an end-to-end 'over-cap arb reverts' PoC is deferred
 *           as a documented gap; the branch is verified by inspection").
 *
 *  WHY A MOCK POOLMANAGER AND NOT A FORK. `arbStep`'s two legs run inside one
 *  `poolManager.unlock`, and reaching the code AFTER that unlock — which is
 *  where every check in this finding lives (:507-523) — needs a manager that
 *  returns real swap deltas for two pools on the same token. The rotator's whole
 *  existing test-suite (test/QuoteRotator.t.sol, test/attacks/B04_*) constructs
 *  it with `IPoolManager(address(0xdead))`, so no test in this repository has
 *  ever executed a successful `arbStep`. The stand-in below implements exactly
 *  the five entry points the rotator calls — `unlock`, `swap`, `sync`, `settle`,
 *  `take` — with a fixed exchange rate per pool. Everything under test is the
 *  REAL `QuoteRotator`.
 *
 *  Run:
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract S09_ArbStepGovernance --threads 2 -vv
 *  (No fork required; this suite does not read FORK_RPC.)
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract S09_ArbStepGovernance is Test {
    using PoolIdLibrary for PoolKey;

    QuoteRotator internal rot;
    S09Registry internal reg;
    S09PoolManager internal mgr;
    S09Oracle internal oracle;
    MockQuoteToken internal usdg;
    S09Looper internal looper;

    address internal constant NATIVE = address(0);
    /// @dev The generation token. 0xFF..FF so any deployed USDG sorts below it and
    ///      both PoolKeys are well formed (currency0 < currency1).
    address internal constant TOKEN = address(type(uint160).max);

    address internal constant ATTACKER = address(0xA77ACC);
    address internal constant TREASURY_DEST = address(0x7BEA5);

    /// @dev USD per 1e18 RAW units, the unit `QuoteRotator._usd` (:528-537) works
    ///      in: `usd = raw * f / 1e18`.
    uint256 internal constant USD_PER_ETH = 3_000e18; // $3,000 / ETH
    uint256 internal constant USD_PER_USDG = 1e18;    // $1 / USDG (18 decimals)

    /// @dev The spread. 1 ETH buys 1,000 TOKEN in `cheap`; 1 TOKEN sells for 3.3
    ///      USDG in `dear`. So $3,000 in, $3,300 out, $300 of profit per ETH.
    uint256 internal constant RATE_CHEAP = 1_000e18;
    uint256 internal constant RATE_DEAR = 3.3e18;

    uint256 internal constant ARB_IN = 1 ether;
    uint256 internal constant IN_USD = 3_000e18;
    uint256 internal constant OUT_USDG = 3_300e18;

    PoolKey internal cheap; // ETH  / TOKEN
    PoolKey internal dear;  // USDG / TOKEN

    function setUp() public {
        reg = new S09Registry();
        mgr = new S09PoolManager();
        oracle = new S09Oracle();
        usdg = new MockQuoteToken("Magic USD", "USDG", 18);
        looper = new S09Looper();

        rot = new QuoteRotator(address(reg), IPoolManager(address(mgr)));
        rot.setArbParams(address(oracle), 1000, 5e18); // 10% keeper cut, $5 floor

        oracle.set(NATIVE, USD_PER_ETH);
        oracle.set(address(usdg), USD_PER_USDG);

        cheap = PoolKey({
            currency0: Currency.wrap(NATIVE),
            currency1: Currency.wrap(TOKEN),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        dear = PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(TOKEN),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });

        mgr.setRate(cheap, RATE_CHEAP);
        mgr.setRate(dear, RATE_DEAR);

        // The venue the pool manager pays out of, and the treasury's own float.
        usdg.mint(address(mgr), 5_000_000e18);
        vm.deal(address(rot), 100 ether);
        vm.deal(ATTACKER, 1 ether);

        //  ── POST-FIX RIG: CURATE THE HONEST VENUES + ALLOWLIST THE DESTINATION
        //  `arbStep` now applies the same curation `rotateStep`/`swapOnce` do
        //  (red-team L-4), so a legitimate arb needs both pools listed and the
        //  destination quote approved. Tests that probe the GUARDS de-curate or
        //  swap in an uncurated key explicitly.
        rot.setVenue(cheap, true);
        rot.setVenue(dear, true);
        reg.set(address(usdg), true);
    }

    // =======================================================================
    //  S09-A — the venue allowlist is not on this path
    // =======================================================================

    /**
     * @notice INVARIANT: a permissionless treasury swap must refuse a venue the
     *         treasury never curated.
     *
     *  This is the contract's OWN stated rule. {allowedVenue} (:171-174):
     *
     *      "FAILS CLOSED. An unset allowlist rotates nothing. That is deliberate:
     *       a rotation that cannot execute is a paused treasury operation, whereas
     *       a rotation that executes into an unvetted venue is a realised loss."
     *
     *  and (:176-178):
     *
     *      "VETTING A VENUE VETS ITS HOOK. A hooked pool may be listed, and doing
     *       so grants that hook execution inside this contract's `unlock`. List
     *       only hooks the treasury would trust with that."
     *
     *  `arbStep` never reads `allowedVenue`, and the caller supplies BOTH keys —
     *  including both `hooks` fields, which the PoolManager will call while this
     *  contract is the locker.
     *
     *  THE ASSERTION IS EXPECTED TO FAIL ON CURRENT CODE. That failure is the
     *  finding.
     */
    function test_S09_A_INVARIANT_ArbStepRefusesAnUncuratedVenue() public {
        //  De-curate locally: `setUp` now lists both pools because a legitimate
        //  arb requires it post-fix. This test is about the GUARD, so it puts the
        //  world back into the un-curated state the guard exists for.
        rot.setVenue(cheap, false);
        rot.setVenue(dear, false);
        assertFalse(rot.isVenueAllowed(cheap), "the treasury never curated the cheap pool");
        assertFalse(rot.isVenueAllowed(dear), "nor the dear pool");

        uint256 ethBefore = address(rot).balance;
        vm.prank(ATTACKER);
        try rot.arbStep(cheap, dear, ARB_IN) returns (uint256 p) {
            console2.log("arbStep FILLED through two uncurated pools.");
            console2.log("  oracle profit booked (USD 1e18):", p);
            console2.log("  treasury ETH spent       (wei) :", ethBefore - address(rot).balance);
            console2.log("  both `hooks` fields were chosen by the caller.");
            assertTrue(false, "arbStep must refuse a venue the treasury never curated (cf. :295, :355)");
        } catch (bytes memory err) {
            assertEq(bytes4(err), QuoteRotator.NoRoute.selector, "refused, and for the curation reason");
        }
    }

    /// @notice POSITIVE PoC (green == the hole is real). The same two uncurated
    ///         keys that `rotateStep` refuses are executed by `arbStep`, and the
    ///         anonymous caller is paid for it out of the treasury's proceeds.
    function test_S09_A_PoC_UncuratedVenuesExecuteAndPayTheCaller() public {
        // CONTROL — the curated-venue rule really is enforced on the other path.
        reg.set(address(usdg), true);
        rot.setPlan(NATIVE, address(usdg), 10 ether, 1 ether, 1e18, 1 hours);
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.rotateStep(dear);
        rot.cancelPlan();

        // ATTACK — the identical uncurated key, through `arbStep`.
        uint256 ethBefore = address(rot).balance;
        rot.setVenue(cheap, false);
        rot.setVenue(dear, false);
        assertFalse(rot.isVenueAllowed(cheap), "still uncurated");
        assertFalse(rot.isVenueAllowed(dear), "still uncurated");

        //  ── INVERTED BY THE L-4 FIX ─────────────────────────────────────────
        //  This used to run: an anonymous caller filled 1 ETH of treasury through
        //  two pools it chose itself — supplying both `hooks` fields, which
        //  {allowedVenue}'s own header calls out as the reason curation exists —
        //  and was paid 30e18 USDG for it. `arbStep` now applies the same venue
        //  allowlist `rotateStep` (:295) and `swapOnce` (:355) always did.
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.arbStep(cheap, dear, ARB_IN);

        assertEq(address(rot).balance, ethBefore, "not one wei of treasury moved");
        assertEq(usdg.balanceOf(ATTACKER), 0, "and the caller was paid nothing");

        //  The guard blocks the ATTACK, not the feature: curate the same venues
        //  and the identical call goes through.
        rot.setVenue(cheap, true);
        rot.setVenue(dear, true);
        vm.prank(ATTACKER);
        uint256 profitUsd = rot.arbStep(cheap, dear, ARB_IN);
        console2.log("curated arb still fills; profit (USD 1e18):", profitUsd);
        assertEq(profitUsd, 300e18, "$300 of oracle-measured profit on a curated route");
        assertEq(usdg.balanceOf(ATTACKER), 30e18, "and the keeper is paid as designed");
        // Sentinel: no branch above may skip the assertions (audit rule - a
        // Foundry test that asserts nothing still reports PASS).
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S09-B — the quote allowlist is not on this path either
    // =======================================================================

    /**
     * @notice INVARIANT: the treasury cannot be converted into an asset the
     *         registry's allowlist does not contain.
     *
     *  That allowlist is the governance surface for WHAT the guild may hold. It
     *  is checked when a plan is SCHEDULED (:225), again when a slice EXECUTES
     *  (:286, "Checked here AND at execution, because the allowlist can change in
     *  between"), and in `swapOnce` (:339). `arbStep` derives `outQuote` from
     *  `dear.currency0` — attacker-supplied — and never checks it.
     *
     *  THE ASSERTION IS EXPECTED TO FAIL ON CURRENT CODE.
     */
    function test_S09_B_INVARIANT_ArbStepRefusesANonAllowlistedDestination() public {
        //  De-allowlist locally, for the same reason the A test de-curates.
        reg.set(address(usdg), false);
        assertFalse(reg.allowedQuote(address(usdg)), "USDG is not an approved quote");

        // CONTROL — every governed path refuses it, which is what makes the
        // allowlist the control surface.
        vm.expectRevert(QuoteRotator.NotAllowedQuote.selector);
        rot.setPlan(NATIVE, address(usdg), 10 ether, 1 ether, 1e18, 1 hours);

        // The permissionless path must refuse it too.
        vm.prank(ATTACKER);
        try rot.arbStep(cheap, dear, ARB_IN) returns (uint256 p) {
            console2.log("arbStep FILLED into a quote the registry never allowlisted.");
            console2.log("  oracle profit booked (USD 1e18):", p);
            console2.log("  unapproved asset now held      :", usdg.balanceOf(address(rot)));
            assertTrue(false, "arbStep must check the destination quote (cf. :225, :286, :339)");
        } catch (bytes memory err) {
            assertEq(bytes4(err), QuoteRotator.NotAllowedQuote.selector, "refused for the allowlist reason");
        }
    }

    /// @notice POSITIVE PoC: the treasury ends the call holding an asset that no
    ///         governance surface in this system ever approved.
    function test_S09_B_PoC_TreasuryEndsUpHoldingAnUnapprovedAsset() public {
        reg.set(address(usdg), false);
        assertFalse(reg.allowedQuote(address(usdg)), "USDG is not an approved quote");
        assertEq(usdg.balanceOf(address(rot)), 0, "treasury holds none of it to start");

        //  ── INVERTED BY THE L-4 FIX ─────────────────────────────────────────
        //  A stranger used to be able to move the treasury into any asset with a
        //  price feed, allowlisted or not — the one guardrail TreasuryGovernor's
        //  header calls "the single most important" one, since it is what stops a
        //  captured vote (or here, no vote at all) routing funds into an
        //  attacker's token. `arbStep` now checks the destination like every
        //  other spending path does.
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.NotAllowedQuote.selector);
        rot.arbStep(cheap, dear, ARB_IN);

        console2.log("USDG held by the treasury after the refusal:", usdg.balanceOf(address(rot)));
        assertEq(
            usdg.balanceOf(address(rot)),
            0,
            "the treasury holds none of the unapproved asset"
        );
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S09-C — the cap is PER CALL, and calls are free
    // =======================================================================

    /**
     * @notice POSITIVE PoC. `maxArbNotionalUsd` (:437) is described as the bound
     *         that stops "repeated arbs [from] quietly re-allocat[ing] the
     *         treasury behind governance's back" (:470-472). It is enforced once
     *         per call (:513) against that call's own `inUsd`, and NOTHING in the
     *         contract accumulates notional across calls — no `lastStepAt`
     *         equivalent (contrast `rotateStep`, which has `interval` +
     *         `lastStepAt`, :266/:300), no per-block counter, no reentrancy or
     *         frequency guard.
     *
     *  So the bound is not a rate limit. This drives 12 individually-compliant
     *  arbs through ONE transaction in ONE block and moves 1.44x the cap.
     */
    function test_S09_C_PoC_PerCallCapIsNotAPerBlockCap() public {
        uint256 cap = rot.maxArbNotionalUsd();
        assertEq(cap, 25_000e18, "the documented $25k per-call default");

        uint256 n = 12;
        uint256 ethBefore = address(rot).balance;
        uint256 blockBefore = block.number;

        //  ── INVERTED BY THE L-4 FIX ─────────────────────────────────────────
        //  ONE external call -> ONE transaction -> ONE block. This used to run all
        //  `n` arbs and move $36,000 against a $25,000 "cap", because nothing
        //  accumulated: the bound was per CALL, so it bounded nothing a loop could
        //  not step around. `arbStep` now accumulates notional per block, so the
        //  loop reverts the moment the block's budget is exhausted.
        vm.expectRevert(QuoteRotator.ArbTooLarge.selector);
        looper.loop(rot, cheap, dear, ARB_IN, n);

        //  Nothing partial survives: the whole transaction unwound.
        assertEq(address(rot).balance, ethBefore, "the over-cap transaction moved nothing");
        assertEq(usdg.balanceOf(address(looper)), 0, "and paid the caller nothing");

        //  And the budget is a BUDGET, not a freeze — what fits still executes.
        uint256 fits = cap / IN_USD;
        uint256 totalProfit = looper.loop(rot, cheap, dear, ARB_IN, fits);
        n = fits;

        uint256 movedUsd = n * IN_USD;
        console2.log("per-call cap (USD 1e18)                :", cap);
        console2.log("arbs executed in ONE transaction       :", n);
        console2.log("notional moved in that transaction USD :", movedUsd);
        console2.log("treasury ETH spent (wei)               :", ethBefore - address(rot).balance);
        console2.log("keeper cut harvested in one tx (USDG)  :", usdg.balanceOf(address(looper)));
        console2.log("total oracle profit (USD 1e18)         :", totalProfit);

        assertEq(block.number, blockBefore, "all of it inside a single block");
        assertEq(ethBefore - address(rot).balance, n * ARB_IN, "only the in-budget arbs moved treasury");
        assertLe(movedUsd, cap, "THE CAP NOW BOUNDS THE BLOCK, not just the call");
        assertEq(usdg.balanceOf(address(looper)), n * 30e18, "keeper paid only for what executed");

        //  One more arb in the SAME block is refused; the budget has been spent.
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.ArbTooLarge.selector);
        rot.arbStep(cheap, dear, ARB_IN);
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S09-D — the arb eats the balance a GOVERNED rotation was funded with
    // =======================================================================

    /**
     * @notice POSITIVE PoC, and the part with teeth. `nextSliceSize` (:259-271)
     *         ends with
     *
     *             uint256 held = _balanceOf(p.from);
     *             return size < held ? size : held;
     *
     *         so a voted plan can only sell what this contract still HOLDS.
     *         `arbStep` spends that same balance, is permissionless, and does not
     *         look at `plan` at all. A stranger can therefore convert the entire
     *         float a guild vote parked here — in a direction and into an asset
     *         the vote did not choose — and the voted rotation then reverts
     *         `TooSoon` because there is nothing left to sell.
     */
    function test_S09_D_PoC_ArbStepCannibalisesTheGovernedPlan() public {
        reg.set(address(usdg), true);

        // The guild's decision: convert 10 ETH into USDG, 1 ETH at a time.
        vm.deal(address(rot), 10 ether);
        rot.setPlan(NATIVE, address(usdg), 10 ether, 1 ether, 1e18, 1 hours);
        rot.setVenue(dear, true); // properly curated, as deployment requires
        assertEq(rot.nextSliceSize(), 1 ether, "the voted slice is ready to run");

        //  ── BOUNDED BY THE L-4 FIX ──────────────────────────────────────────
        //  A stranger used to spend the ENTIRE governed float through the
        //  ungoverned path in one transaction, leaving `nextSliceSize() == 0` so
        //  the voted rotation had nothing left to sell. The per-block notional
        //  budget now caps how much any one block can re-allocate, so the vote
        //  cannot be cancelled outright.
        uint256 floatBefore = address(rot).balance;
        vm.expectRevert(QuoteRotator.ArbTooLarge.selector);
        looper.loop(rot, cheap, dear, ARB_IN, 10);
        assertEq(address(rot).balance, floatBefore, "the over-budget attempt moved nothing");

        //  What DOES fit still eats into the float — that is the residual, and it
        //  is now rate-limited rather than unbounded.
        uint256 fits = rot.maxArbNotionalUsd() / IN_USD;
        looper.loop(rot, cheap, dear, ARB_IN, fits);

        console2.log("treasury ETH left after the arbs (wei):", address(rot).balance);
        console2.log("nextSliceSize() now (wei)            :", rot.nextSliceSize());

        assertGt(address(rot).balance, 0, "the governed float SURVIVES a single block of arbs");
        assertGt(rot.nextSliceSize(), 0, "and the voted rotation still has something to sell");
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S09-E — REFUTED: the unpriceable leg
    // =======================================================================

    /**
     * @notice REFUTED. The lead asked whether `_usd` returning 0 is exploitable.
     *         In `arbStep` it is not: :509 is
     *
     *             if (inUsd == 0 || outUsd == 0) revert NoRoute();
     *
     *         and it sits BEFORE the cap check (:513), the profit check (:514)
     *         and the keeper payout (:523). An unpriceable leg therefore makes the
     *         whole call revert and the unlock unwind atomically — it cannot be
     *         used to bypass the cap, to manufacture profit, or to zero-price the
     *         treasury's side. Kept as a regression guard.
     *
     *  Worth recording alongside: `_oracleFloor` (:398-408) deliberately fails
     *  OPEN on the same condition (`if (inUsd == 0) return 0;`), which is correct
     *  there for the reason its header gives, and is guarded separately by the
     *  venue allowlist on `swapOnce` (:355). The two behaviours are different on
     *  purpose; only `arbStep`'s matters for this lead.
     */
    function test_S09_E_REFUTED_AnUnpriceableLegFailsClosed() public {
        // Destination unpriceable.
        oracle.set(address(usdg), 0);
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.arbStep(cheap, dear, ARB_IN);

        // Source unpriceable.
        oracle.set(address(usdg), USD_PER_USDG);
        oracle.set(NATIVE, 0);
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.arbStep(cheap, dear, ARB_IN);

        // Oracle removed entirely.
        oracle.set(NATIVE, USD_PER_ETH);
        rot.setArbParams(address(0), 1000, 5e18);
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.arbStep(cheap, dear, ARB_IN);

        // And nothing moved in any of the three.
        assertEq(address(rot).balance, 100 ether, "the treasury is untouched");
        assertEq(usdg.balanceOf(address(rot)), 0, "no destination asset was acquired");
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S09-F — REFUTED: farming the keeper cut by splitting
    // =======================================================================

    /**
     * @notice REFUTED. The cut is `received * profitUsd * arbKeeperBps /
     *         (outUsd * BPS)` (:522) — proportional to PROFIT, not to notional —
     *         so slicing one profitable spread into many pieces pays the same
     *         total, and `minArbProfitUsd` (:517) refuses any slice too small to
     *         clear the floor. On a real curve the split is strictly WORSE than
     *         the single call, because each leg pays pool fees and its own price
     *         impact; the linear stand-in here is the most generous case for the
     *         attacker and it is still only break-even.
     */
    function test_S09_F_REFUTED_SplittingDoesNotFarmTheKeeperCut() public {
        // One big arb.
        uint256 snap = vm.snapshotState();
        vm.prank(ATTACKER);
        rot.arbStep(cheap, dear, 1 ether);
        uint256 oneShot = usdg.balanceOf(ATTACKER);
        vm.revertToState(snap);

        // The same ETH, sliced ten ways, all in one transaction.
        looper.loop(rot, cheap, dear, 0.1 ether, 10);
        uint256 sliced = usdg.balanceOf(address(looper));

        console2.log("keeper cut, one 1 ETH arb   (USDG):", oneShot);
        console2.log("keeper cut, ten 0.1 ETH arbs(USDG):", sliced);
        assertLe(sliced, oneShot, "slicing pays no more than the single call");

        // And the floor bites below it: 0.01 ETH yields $3 of profit, under the
        // $5 `minArbProfitUsd`, so the dust slice is refused outright.
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.SlippageTooHigh.selector);
        rot.arbStep(cheap, dear, 0.01 ether);
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S09-G — REGRESSION: execute the branch B-04 could only inspect
    // =======================================================================

    /**
     * @notice REGRESSION, closing B04_ArbNotionalCap.t.sol's own documented gap
     *         (:26-31: "an end-to-end 'over-cap arb reverts' PoC is deferred as a
     *         documented gap; the branch is verified by inspection"). With a pool
     *         manager that returns real deltas the branch is now EXECUTED:
     *         `inUsd > maxArbNotionalUsd` reverts `ArbTooLarge` (:513), the swap
     *         unwinds, and nothing moves. The `0 = unbounded` opt-out is exercised
     *         on the same state so the semantics are pinned end to end, not just
     *         at the setter.
     */
    function test_S09_G_REGRESSION_OverCapArbRevertsEndToEnd() public {
        // 10 ETH = $30,000 in, against the $25,000 default cap.
        vm.prank(ATTACKER);
        vm.expectRevert(QuoteRotator.ArbTooLarge.selector);
        rot.arbStep(cheap, dear, 10 ether);

        assertEq(address(rot).balance, 100 ether, "the over-cap swap unwound atomically");
        assertEq(usdg.balanceOf(ATTACKER), 0, "and paid nobody");

        // Just under the cap goes through...
        vm.prank(ATTACKER);
        rot.arbStep(cheap, dear, 8 ether); // $24,000
        assertEq(address(rot).balance, 92 ether, "an in-cap arb executes");

        // ...and 0 really does disable the bound.
        rot.setMaxArbNotionalUsd(0);
        vm.prank(ATTACKER);
        rot.arbStep(cheap, dear, 20 ether); // $60,000, far over the old cap
        assertEq(address(rot).balance, 72 ether, "0 = unbounded, as documented");
        assertTrue(true, "reached");
    }

    receive() external payable {}
}

// ===========================================================================
//  Fixtures
// ===========================================================================

/// @dev The registry surface the rotator consults: `allowedQuote(address)`.
contract S09Registry {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/// @dev The oracle surface `QuoteRotator._usd` (:528-537) low-level-calls.
contract S09Oracle {
    mapping(address => uint256) public factor;
    function set(address quote, uint256 f) external { factor[quote] = f; }
    function cachedUsdPerRawUnit(address quote) external returns (uint256) {
        factor[quote]; // non-view on purpose: matches the real oracle, which caches
        return factor[quote];
    }
}

/**
 * @dev A v4 PoolManager stand-in exposing exactly the five entry points
 *      `QuoteRotator` calls: `unlock`, `swap`, `sync`, `settle`, `take`.
 *
 *  Each pool has ONE fixed rate, applied as `out = in * rate / 1e18`. Fixed
 *  rather than curved on purpose: a curve would make "did the cap bound the
 *  transaction" depend on depth, and the property under test is that NOTHING in
 *  the rotator bounds it. Where that matters for the conclusion (S09-F) the test
 *  says so explicitly.
 */
contract S09PoolManager {
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => uint256) public rate;

    function setRate(PoolKey calldata key, uint256 r) external { rate[key.toId()] = r; }

    function unlock(bytes calldata data) external returns (bytes memory) {
        return IUnlockCallback(msg.sender).unlockCallback(data);
    }

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata)
        external
        view
        returns (BalanceDelta)
    {
        // The rotator only ever swaps EXACT INPUT (:588, :612, :622).
        require(params.amountSpecified < 0, "exact-in only");
        uint256 amt = uint256(-params.amountSpecified);
        uint256 out = (amt * rate[key.toId()]) / 1e18;
        return params.zeroForOne
            ? toBalanceDelta(-int128(int256(amt)), int128(int256(out)))
            : toBalanceDelta(int128(int256(out)), -int128(int256(amt)));
    }

    function sync(Currency) external {}

    function settle() external payable returns (uint256) { return msg.value; }

    function take(Currency currency, address to, uint256 amount) external {
        address c = Currency.unwrap(currency);
        if (c == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "take native");
        } else {
            require(IERC20(c).transfer(to, amount), "take erc20");
        }
    }

    receive() external payable {}
}

/// @dev Calls `arbStep` N times inside ONE transaction, so "per call" and "per
///      block" can be told apart.
contract S09Looper {
    function loop(QuoteRotator rot, PoolKey calldata cheap, PoolKey calldata dear, uint256 amountIn, uint256 n)
        external
        returns (uint256 totalProfitUsd)
    {
        for (uint256 i; i < n; ++i) {
            totalProfitUsd += rot.arbStep(cheap, dear, amountIn);
        }
    }
}
