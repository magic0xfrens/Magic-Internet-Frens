// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {YBase} from "./YBase.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  S-02 — THE LIVE QUOTE ROTATION SURFACE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  Entry points under test: `CauldronRegistry.rotateSlice` (:235) and
 *  `rotateSliceFrom` (:259). BOTH are plain `external` with NO modifier and
 *  forward via `_forwardToExt()` (:1404) into
 *  `RedemptionExt.rotateSliceFrom` (:266), which is `public`, ungated, and
 *  documents itself as "PERMISSIONLESS, WITHIN WHAT THE GUILD APPROVED"
 *  (:281-286).
 *
 *  Four properties, each stated as the thing the protocol NEEDS, so a failing
 *  assertion IS the finding:
 *
 *   S02-01  a permissionless caller cannot choose BOTH the venue and the price
 *           floor of a treasury swap;
 *   S02-02  a generation that completed a rotation can still be reborn;
 *   S02-03  a generation is re-denominated only when its liquidity actually
 *           moved (RedemptionExt.sol:406-410 states exactly this as intent);
 *   S02-04  linking a rotated pair never makes a pool its own volume sibling.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract S02_RotationSurface is YBase {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;

    /// @dev The CURATED venue: deep, hookless, 3000/60 — exactly F-10's.
    PoolKey internal honest;
    /// @dev The ATTACKER's venue: same pair, different fee tier -> different
    ///      PoolId -> not on `rotator.allowedVenue`.
    PoolKey internal evil;

    int24 internal constant EVIL_SPACING = 10;
    uint24 internal constant EVIL_FEE = 500;

    uint256 internal evilEthIn;
    uint256 internal evilUsdgIn;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        // MAINNET timings (testnet = false), same construction F-10 uses.
        governor = new TreasuryGovernor(
            IVotes721(address(new SVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));
    }

    // =======================================================================
    //  S02-01 — a random EOA picks the venue AND the price floor
    // =======================================================================

    /**
     * @notice PROPERTY: a rotation must refuse a venue the treasury never
     *         curated.
     *
     *  WHY THE CODE BELIEVES IT HOLDS. `QuoteRotator.rotateStep` (:295) refuses
     *  any venue absent from `allowedVenue`, and {allowedVenue}'s header
     *  (:139-178) argues at length that a shape check is not enough, because
     *  "a keeper routing to a pool they seeded earns that 0.1% AND the entire
     *  spread, by returning exactly `minOut` and keeping the difference as
     *  inventory in their own pool". `swapOnce` is exempted on ONE stated
     *  ground, at :292-294:
     *
     *     "`swapOnce` is deliberately not gated this way — it is owner-only, so
     *      the caller choosing the venue is the same party that curates the
     *      list."
     *
     *  WHY IT DOES NOT. `swapOnce` is not owner-only: it is `onlyRegistry`
     *  (:337; the {onlyRegistry} modifier at :121 exists precisely because
     *  `onlyOwner` made rotations unrunnable). Its ONLY caller is
     *  `RedemptionExt.rotateSliceFrom` :352, which is permissionless and passes
     *  BOTH `route` and `minOut` through verbatim from its own caller's
     *  calldata. So the party choosing the venue is any EOA and the party
     *  curating the list is the treasury — the separation the exemption assumed
     *  away. `minOut`, which the rotator's header calls "the whole price
     *  protection", is picked by the attacker.
     */
    function test_INVARIANT_S02_01_RotationRefusesAnUncuratedVenue() public {
        vm.skip(!active);

        _seedHonestVenue();
        _approveEnvelope(address(usdg), governor.MAX_ENVELOPE_BPS());
        _openEvilVenue();
        _mintEvilLiquidity();

        assertTrue(rotator.isVenueAllowed(honest), "the treasury curated the deep venue");
        assertFalse(rotator.isVenueAllowed(evil), "the attacker's pool is NOT curated");

        vm.prank(attacker);
        vm.expectRevert(); // QuoteRotator.NoRoute
        registry.rotateSlice(2500, 0, evil);
    }

    /// @notice POSITIVE PoC, and the price tag. Same slice, priced twice: once
    ///         through the curated venue, once through the attacker's. The
    ///         second run ends with the attacker's own LP holding the treasury's
    ///         ETH.
    function test_S02_01_PoC_UncuratedVenueDrainsTheSlice() public {
        vm.skip(!active);

        _seedHonestVenue();
        _approveEnvelope(address(usdg), governor.MAX_ENVELOPE_BPS());
        _openEvilVenue();

        //  Price the honest fill, then rewind so both runs start byte-identical.
        uint256 snap = vm.snapshotState();
        vm.prank(attacker);
        (uint256 honestOut,) = registry.rotateSlice(2500, 0, honest);
        vm.revertToState(snap);

        uint256 liq = _mintEvilLiquidity();

        //  ── INVERTED BY THE R-01 FIX ────────────────────────────────────────
        //  This used to succeed and asserted the damage: the treasury filled at
        //  99.80 USDG where the curated venue paid 44,325.89 (under 1%), and the
        //  attacker withdrew 5.01 ETH against 0.01 ETH in. The venue allowlist
        //  now covers `swapOnce` — the path `rotateSliceFrom` actually takes —
        //  so an uncurated pool is refused before any liquidity moves.
        //
        //  `NoRoute()` is the rotator's error, bubbled through the registry's
        //  delegatecall to the facet verbatim.
        vm.prank(attacker);
        vm.expectRevert(bytes4(keccak256("NoRoute()")));
        registry.rotateSlice(2500, 0, evil);

        //  Nothing moved: the attacker's pool still holds exactly what it seeded,
        //  so there was no fill to skim.
        (uint256 backEth, uint256 backUsdg) = _burnEvilLiquidity(liq);
        console2.log("fill via CURATED venue  (usdg, 6dp):", honestOut);
        console2.log("attacker deposited  wei:", evilEthIn);
        console2.log("attacker withdrew   wei:", backEth);
        console2.log("attacker withdrew  usdg:", backUsdg);

        assertLe(backEth, evilEthIn, "the attacker cannot profit - no treasury flow reached its pool");
        assertLe(backUsdg, evilUsdgIn, "and no treasury USDG either");
        //  And the CURATED route still works, so the guard blocks the attack
        //  rather than the feature.
        vm.prank(attacker);
        (uint256 stillWorks,) = registry.rotateSlice(2500, 0, honest);
        assertGt(stillWorks, 0, "a curated venue still rotates");
        //  Sentinel: no branch above may skip the assertions (audit rule).
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S02-02 — a completed rotation vs the rebirth
    // =======================================================================

    /**
     * @notice PROPERTY: a generation that completed a live rotation can still be
     *         reborn.
     *
     *  MECHANISM. `rotateSliceFrom` writes `generationQuote[gen]`
     *  (RedemptionExt.sol:413) when the envelope is spent. NOTHING writes
     *  `generationPoolKey[gen]` / `generationPositionId[gen]` /
     *  `generationPoolId[gen]` — the only writes in the tree are
     *  CauldronRegistry.sol:1692-1694, inside `_seedGeneration`. After a
     *  completed rotation the recorded DENOMINATION is USDG while the recorded
     *  PRIMARY POOL is still the ETH pool holding the un-rotated remainder
     *  (`MAX_ENVELOPE_BPS` = 30_000 leaves 0.75^12 ~ 3.2% behind, and every
     *  smaller envelope leaves far more).
     *
     *  `_removeLiquidity` (:1506-1515) then unwinds that primary with
     *  `generationPoolKey[gen]` and adds the NATIVE WEI it recovers to
     *  `ethRecovered`. `RedemptionExt.recoverLegs` adds the USDG legs to the
     *  same accumulator behind `matchQuote = generationQuote[gen]` (:622) —
     *  which now reads USDG, so BOTH denominations land in one number.
     *  `relaunch` hands it to `PoolOps.seedFunding` as an amount "denominated in
     *  `specQuote`'s OWN units" (:918-925) with `oldQuote = USDG`. Because
     *  `oldQuote != address(0)` and `recovered > 0`, the native branch
     *  (PoolOps.sol:1040) is unreachable and branch 3 (:1044) returns
     *  `(USDG, nativeWei + usdgUnits)`. USDG is 6-decimal, so one wei of ETH
     *  remainder reads as one micro-dollar: a 0.5 ETH remainder reads as 500
     *  BILLION raw USDG units the registry does not hold.
     */
    function test_INVARIANT_S02_02_ARotatedGenerationCanStillBeReborn() public {
        vm.skip(!active);

        _seedHonestVenue();
        _approveEnvelope(address(usdg), governor.MAX_ENVELOPE_BPS());
        _rotateUntilSpent();

        assertEq(registry.generationQuote(1), address(usdg), "the rotation completed");

        //  The primary POOL slots did not follow the quote.
        (Currency c0,,,,) = registry.generationPoolKey(1);
        console2.log("generationQuote(1)     :", registry.generationQuote(1));
        console2.log("generationPoolKey.cur0 :", Currency.unwrap(c0));
        assertEq(Currency.unwrap(c0), address(0), "the recorded primary pool is still the ETH pool");

        console2.log("registry USDG actually held (6dp):", usdg.balanceOf(address(registry)));
        console2.log("ETH still in the primary pool (wei):", _ethLeftInPrimary());

        //  Kill it, then try to be reborn.
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        assertTrue(hook.isDead(registry.generationPoolId(1)), "the generation is dead");

        try registry.relaunch() {
            console2.log("relaunch OK; gen-2 quote:", registry.generationQuote(2));
        } catch (bytes memory err) {
            console2.log("relaunch REVERTED:", vm.toString(err));
            assertTrue(false, "relaunch must survive a completed rotation");
        }
    }

    // =======================================================================
    //  S02-03 — an exhausted envelope is not a completed rotation
    // =======================================================================

    /**
     * @notice PROPERTY, quoting the code itself (RedemptionExt.sol:406-410):
     *
     *     "A partial rotation that simply stops therefore leaves the quote
     *      alone, which is correct — 30% moved does not redenominate a
     *      generation."
     *
     *  The flip is gated on `allowance() == address(0)` (:411-412), and
     *  `TreasuryGovernor.allowance` (:511-516) returns zero as soon as
     *  `movedBps >= maxTotalBps`. So the guard means "the ENVELOPE is spent",
     *  not "the LIQUIDITY moved". A guild that deliberately votes a partial
     *  mandate and executes exactly it re-denominates the whole generation —
     *  and re-points the perp engine with it (:447-448) — onto the pool that
     *  holds the MINORITY of its liquidity.
     */
    function test_INVARIANT_S02_03_APartialEnvelopeDoesNotRedenominate() public {
        vm.skip(!active);

        _seedHonestVenue();
        //  A deliberately partial mandate: "move at most 25% of the LP".
        _approveEnvelope(address(usdg), 2500);

        uint256 primaryId = registry.generationPositionId(1);
        uint256 before = IPositionManagerOps(posm).getPositionLiquidity(primaryId);

        vm.prank(attacker);
        registry.rotateSlice(2500, 0, honest);

        uint256 left = IPositionManagerOps(posm).getPositionLiquidity(primaryId);
        console2.log("primary liquidity before:", before);
        console2.log("primary liquidity after :", left);
        console2.log("share of the pair never moved (bps):", (left * 10_000) / before);

        assertGe(left * 4, before * 3, "at least 75% of the pair never moved");
        assertEq(
            registry.generationQuote(1), address(0),
            "a 25%-only rotation must not re-denominate the generation"
        );
    }

    /// @notice POSITIVE PoC for the same defect plus the consequence that gives
    ///         it teeth: once the quote flips, the 3-arg `rotateSlice` is DEAD
    ///         for the rest of the generation. `fromLeg == 0` reads
    ///         `generationQuote` (now USDG) alongside `generationPositionId`
    ///         (still the ETH pool), so `PoolOps.removePartial` measures the ETH
    ///         pool's payout as a USDG balance delta of ZERO
    ///         (PoolOps.sol:915-919) and RedemptionExt.sol:347 reverts
    ///         `BadConfig`.
    function test_S02_03_PoC_FlipStrandsThePrimaryAndKillsRotateSlice() public {
        vm.skip(!active);

        _seedHonestVenue();
        _approveEnvelope(address(usdg), 2500);

        vm.prank(attacker);
        registry.rotateSlice(2500, 0, honest);
        //  INVERTED BY THE R-04 FIX. This asserted the defect — that a fully-spent
        //  25% mandate redenominated the whole generation. Completion is now judged
        //  by whether the guild authorised moving the WHOLE position
        //  ({TreasuryGovernor.migrationMandateSpent}), so a partial mandate leaves
        //  the denomination where the liquidity still mostly is.
        assertEq(
            registry.generationQuote(1), address(0),
            "a 25% mandate must NOT redenominate the generation"
        );

        //  ── R-05 REGRESSION: A SPENT ENVELOPE MUST RELEASE GOVERNANCE ──────
        //  The mandate above is now exhausted (one 2500-bps slice against a
        //  2500-bps budget). Pre-fix `envelope.active` stayed TRUE until the
        //  envelope EXPIRED — 30 days on mainnet defaults — because only the
        //  guardian's `cancel` ever cleared it, while `propose` refuses whenever
        //  `envelope.active && now < expiry` (TreasuryGovernor.sol:322/397/409).
        //  So a mandate spent in its first hour locked the guild out of even
        //  FILING a correction. Reaching this line at all used to revert
        //  `ProposalActive()`; only the COOLDOWN should gate the next mandate.
        //
        //  Deliberately does NOT warp past ENVELOPE_LIFETIME — waiting out the
        //  expiry is the very workaround the fix removes the need for.
        _warp(governor.COOLDOWN() + 1);
        _approveEnvelope(address(usdg), 2500);

        (address dest,) = governor.allowance();
        assertEq(dest, address(usdg), "a spent envelope must not block the next mandate");
        //  Sentinel: no branch above may skip the assertions (audit rule - a
        //  Foundry test that asserts nothing still reports PASS).
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  S02-04 — rotating BACK makes the primary its own volume sibling
    // =======================================================================

    /**
     * @notice PROPERTY: `CauldronHook.linkVolume` must never register a pool as
     *         its own volume sibling, because `isDead` (:1539-1547) sums the
     *         primary's 24h volume and then EVERY sibling's.
     *
     *  REACHED BY THE DESIGN'S OWN ROUND TRIP. `PoolOps.openOrAddPair`'s header
     *  (:815-819) and `RedemptionExt` :498-501 both promise "the guild can move
     *  into USDG and later move back into ETH without a different code path".
     *  Moving back is `rotateSliceFrom(leg, ...)` with `toQuote` = the LAUNCH
     *  quote; `openOrAddPair` then TOPS UP the primary pool and returns
     *  `generationPoolId[gen]` itself, which RedemptionExt.sol:372 hands to
     *  `linkVolume(primary, primary)`.
     */
    function test_INVARIANT_S02_04_APoolIsNeverItsOwnVolumeSibling() public {
        vm.skip(!active);

        //  Short timings only, so both legs fit in one test. On mainnet this is
        //  two ordinary votes a COOLDOWN apart; the mechanism is identical.
        //  ENVELOPE_LIFETIME is 2h here, not 30 days, because of a SEPARATE defect
        //  this test ran into: nothing clears `envelope.active` when an envelope is
        //  EXHAUSTED (it is written true at TreasuryGovernor.sol:397 and false only
        //  by the guardian's `cancel`, :409), while `propose` refuses while
        //  `envelope.active && block.timestamp < envelope.expiry` (:322). So a
        //  fully-spent envelope locks out all new treasury proposals until it
        //  EXPIRES — 30 days on mainnet defaults. A short lifetime is the only way
        //  to reach leg 2 at all; on mainnet this round trip is two votes 30 days
        //  apart, and the mechanism under test is identical.
        governor = new TreasuryGovernor(
            IVotes721(address(new SVotes())), address(registry), address(this),
            1 hours, 2 hours, 1 hours, 1 hours, true
        );
        registry.setRotationWiring(address(rotator), address(governor));

        _seedHonestVenue();

        //  Leg 1: ETH -> USDG.
        //
        //  This step originally asserted `generationQuote(1) == address(0)`, on the
        //  strength of RedemptionExt.sol:407-410 ("30% moved does not redenominate a
        //  generation"). That comment is WRONG and S02-03 proves it: completion is
        //  judged by envelope EXHAUSTION, not by liquidity moved, so a fully-spent
        //  2400-bps envelope flips the quote with ~76% of the LP still in ETH.
        //  The precondition is corrected to the measured reality; the round trip
        //  this test is about is unaffected either way, and is in fact made MORE
        //  reachable by the flip.
        _approveEnvelope(address(usdg), 2400);
        vm.prank(attacker);
        registry.rotateSlice(2400, 0, honest);
        console2.log("generationQuote(1) after leg 1:", registry.generationQuote(1));

        //  Real volume, then a threshold that makes the generation DEAD on it.
        _buy(1 ether, address(this));
        PoolId pid = registry.generationPoolId(1);
        uint256 vol = hook.getVolume24h(pid);
        console2.log("24h volume on the primary:", vol);
        require(vol > 0, "no volume recorded");
        hook.setDeathThreshold(vol + (vol / 2), address(0), 0, 0, 0);
        assertTrue(hook.isDead(pid), "dead on its real volume");

        //  Leg 2: the USDG leg back into ETH. Warp past BOTH the cooldown and the
        //  spent envelope's expiry — see the note in the governor construction.
        _warp(governor.ENVELOPE_LIFETIME() + governor.COOLDOWN() + 1);
        _approveEnvelope(address(0), 2400);
        assertTrue(hook.isDead(pid), "still dead just before the round trip");

        //  ── BOTH HALVES OF THE FIX, ASSERTED TOGETHER ──────────────────────
        //  Pre-fix this call reverted `NoRotationApproved()`: `allowance()` names
        //  a native destination as `address(0)`, and `rotateSliceFrom` read that
        //  same value as "nothing approved" (R-03). Rotation was ONE-WAY — a
        //  treasury that moved into an ERC20 could never come home, which is also
        //  why the self-sibling below had never been reachable.
        //
        //  Now that it IS reachable, it is the thing this test was always about:
        //  the destination pair for a rotation back to the launch quote IS the
        //  primary pair, so `rotateSliceFrom` hands `linkVolume` the same PoolId
        //  twice. Without a guard `isDead` would sum that pool's 24h volume with
        //  its own and hold a dead generation open forever — `relaunch` gates on
        //  `isDead`, so it is a permanent brick.
        (address dest,) = governor.allowance();
        assertEq(dest, address(0), "the envelope names native ether");

        vm.prank(attacker);
        registry.rotateSliceFrom(1, 2400, 0, honest);

        console2.log("24h volume AFTER the round trip:", hook.getVolume24h(pid));
        assertTrue(
            hook.isDead(pid),
            "rotating back to the launch quote must not resurrect a dead generation"
        );
        //  Sentinel: no branch above may skip the assertions (audit rule - a
        //  Foundry test that asserts nothing still reports PASS).
        assertTrue(true, "reached");
    }

    // =======================================================================
    //  Helpers
    // =======================================================================

    /// @dev The deep, curated ETH/USDG venue — identical to F-10's.
    function _seedHonestVenue() internal {
        uint256 venueUsdg = 400_000e6;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 40 ether, venueUsdg, 60, 3000
        );
        honest = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        rotator.setVenue(honest, true);
    }

    /// @dev The attacker's pool: SAME pair, different fee tier -> different
    ///      PoolId -> not curated. Initialized at the curated venue's LIVE price
    ///      so nothing about it looks wrong from the outside.
    function _openEvilVenue() internal {
        evil = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: EVIL_FEE, tickSpacing: EVIL_SPACING, hooks: IHooks(address(0))
        });
        (uint160 fair,,,) = pm.getSlot0(honest.toId());
        pm.initialize(evil, fair);
    }

    /// @dev Seed the attacker's pool with a THIN full-range position. Full range
    ///      matters: `QuoteRotator._swap` settles the WHOLE `size` (:531), so a
    ///      venue that cannot absorb it reverts the unlock instead of filling.
    function _mintEvilLiquidity() internal returns (uint256 liq) {
        liq = 1e12;
        usdg.mint(address(this), 1_000_000e6);
        uint256 e0 = address(this).balance;
        uint256 u0 = usdg.balanceOf(address(this));
        _evilLiq(int256(liq));
        evilEthIn = e0 - address(this).balance;
        evilUsdgIn = u0 - usdg.balanceOf(address(this));
    }

    function _burnEvilLiquidity(uint256 liq) internal returns (uint256 eth, uint256 dollars) {
        uint256 e0 = address(this).balance;
        uint256 u0 = usdg.balanceOf(address(this));
        _evilLiq(-int256(liq));
        eth = address(this).balance - e0;
        dollars = usdg.balanceOf(address(this)) - u0;
    }

    function _evilLiq(int256 delta) private {
        int24 lo = (TickMath.MIN_TICK / EVIL_SPACING) * EVIL_SPACING;
        int24 hi = (TickMath.MAX_TICK / EVIL_SPACING) * EVIL_SPACING;
        pm.unlock(abi.encode(OP_LIQ, abi.encode(YLiq(lo, hi, delta)), evil));
    }

    function _approveEnvelope(address quote, uint16 bps) internal {
        uint256 id = governor.propose(quote, bps);
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
        (address dest,) = governor.allowance();
        require(dest == quote, "envelope not installed");
    }

    function _rotateUntilSpent() internal {
        for (uint256 i; i < 24; ++i) {
            (address open,) = governor.allowance();
            if (open == address(0)) break;
            vm.prank(attacker);
            try registry.rotateSlice(2500, 0, honest) {} catch { break; }
        }
    }

    function _ethLeftInPrimary() internal view returns (uint256) {
        return address(pm).balance;
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
