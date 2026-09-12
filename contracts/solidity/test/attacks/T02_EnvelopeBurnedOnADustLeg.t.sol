// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

interface IPosLiq2 {
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128);
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * T02 — A GOVERNANCE MIGRATION MANDATE CAN BE BURNED ON A DUST LEG
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `TreasuryGovernor.consume` (:668-684) books a slice against the envelope by
 * its BPS ARGUMENT ALONE:
 *
 *     if (left == 0 || bps > left) revert BadParam();
 *     e.movedBps += bps;
 *     if (e.movedBps >= e.maxTotalBps) e.active = false;
 *
 * Nothing about VALUE. Meanwhile `RedemptionExt.rotateSliceFrom` (:337-345)
 * lets the CALLER pick which leg those bps come out of:
 *
 *     if (fromLeg == 0) { fromQuote = generationQuote[gen]; ... }
 *     else { TreasuryLeg storage l = generationLegs[gen][fromLeg - 1]; ... }
 *
 * and the function is PERMISSIONLESS by design (:271-292, "Not onlyOwner").
 *
 * REGRESSION NOW. Two things changed. This file's vote mock implemented
 * `totalSupply` where `TreasuryGovernor._passed` needs `getPastTotalSupply`, so
 * every `execute` here died on an unrecognized selector and the test failed before
 * reaching an assertion — a broken harness the deploy gate could not tell apart
 * from a real regression. And the defect itself is closed: `allowance()` meters a
 * full-position mandate against `movedPrimaryBps`, so side-pool slices are still
 * allowed and still bounded by what was voted, but can no longer reach the
 * migration's budget or declare it spent.
 *
 * So `bps` is a share of WHICHEVER LEG the caller names, while the envelope
 * counts it as a share of THE TREASURY. Point every slice at the smallest leg
 * and the mandate is exhausted having moved almost nothing — but
 * `migrationMandateSpent()` still reports the migration complete, and
 * `rotateSliceFrom` (:468-469) redenominates the whole generation on it.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract T02_EnvelopeBurnedOnADustLeg is YBase {
    using PoolIdLibrary for PoolKey;

    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;   // 6-decimal stable
    MockQuoteToken internal eqty;   // 18-decimal synthetic equity

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        eqty = new MockQuoteToken("Magic Equity", "EQTY", 18);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        registry.setAllowedQuote(address(eqty), true, 1e18);

        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(
            IVotes721(address(new EVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));

        // Venue 1: ETH/USDG.
        usdg.mint(address(this), 400_000e6);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 40 ether, 400_000e6, 60, 3000
        );
        rotator.setVenue(_ethUsdg(), true);

        // Venue 2: USDG/EQTY, sorted by address as `openOrAddPair` demands.
        usdg.mint(address(this), 1_000_000e6);
        eqty.mint(address(this), 10_000e18);
        (address lo, address hi) = address(usdg) < address(eqty)
            ? (address(usdg), address(eqty))
            : (address(eqty), address(usdg));
        (uint256 loAmt, uint256 hiAmt) = lo == address(usdg)
            ? (uint256(1_000_000e6), uint256(10_000e18))
            : (uint256(10_000e18), uint256(1_000_000e6));
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0), hi, lo, loAmt, hiAmt, 60, 3000
        );
        rotator.setVenue(_usdgEqty(), true);
    }

    function _ethUsdg() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
    }

    function _usdgEqty() internal view returns (PoolKey memory) {
        (address lo, address hi) = address(usdg) < address(eqty)
            ? (address(usdg), address(eqty))
            : (address(eqty), address(usdg));
        return PoolKey({
            currency0: Currency.wrap(lo),
            currency1: Currency.wrap(hi),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
    }

    function _approve(address to, uint16 bps) internal {
        uint256 id = governor.propose(to, bps);
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
    }

    function _primaryLiquidity() internal view returns (uint128) {
        return IPosLiq2(posm).getPositionLiquidity(registry.generationPositionId(1));
    }

    // -----------------------------------------------------------------------

    function test_T02_POC_DustLegBurnsTheWholeMigrationMandate() public {
        vm.skip(!active);

        // ── 1. A DUST LEG EXISTS ────────────────────────────────────────────
        // Any earlier, modest rotation leaves one. 10 bps = 0.1% of the pair —
        // far too small a mandate to redenominate anything, and it does not:
        // `migrationMandateSpent` needs maxTotalBps >= 10_000.
        _approve(address(usdg), 10);
        registry.rotateSliceFrom(0, 10, 0, _ethUsdg());
        assertEq(registry.generationQuote(1), address(0), "still ETH-denominated, correctly");

        uint128 liqAfterDust = _primaryLiquidity();
        console2.log("primary liquidity after the dust rotation:", uint256(liqAfterDust));

        // ── 2. THE GUILD VOTES TO MIGRATE EVERYTHING INTO EQTY ──────────────
        _warp(governor.COOLDOWN() + 1);
        _approve(address(eqty), 10_000);
        (address dest, uint16 rem) = governor.allowance();
        assertEq(dest, address(eqty), "the mandate names EQTY");
        assertEq(rem, 10_000, "and covers the whole position");

        // ── 3. A STRANGER TRIES TO SPEND IT ON THE DUST LEG ─────────────────
        // `rotateSliceFrom` is permissionless. `fromLeg = 1` is the 0.1% USDG leg.
        // The slices still RUN — leg-to-leg rebalancing is authorised under an
        // envelope and rotating a leg is a legitimate move — but they now meter
        // against their OWN budget instead of the migration's.
        uint256 spent;
        for (uint256 i; i < 8; ++i) {
            vm.prank(attacker, attacker);
            try registry.rotateSliceFrom(1, 2500, 0, _usdgEqty()) { spent += 2500; }
            catch { break; }
        }

        uint128 liqEnd = _primaryLiquidity();
        (address destAfter, uint16 remAfter) = governor.allowance();

        console2.log("bps the attacker could spend:", spent);
        console2.log("primary liquidity BEFORE    :", uint256(liqAfterDust));
        console2.log("primary liquidity AFTER     :", uint256(liqEnd));
        console2.log("generationQuote[1]          :", registry.generationQuote(1));
        console2.log("migration budget remaining  :", uint256(remAfter));

        // ── 4. THE MANDATE IS UNTOUCHED ─────────────────────────────────────
        // `allowance()` meters a full-position mandate against `movedPrimaryBps` —
        // what actually left the position the guild voted to move — so nothing a
        // stranger does to a side pool reduces it. Side-pool spending is still
        // bounded by the same figure, so it cannot run forever either.
        assertEq(spent, 10_000, "side-pool rebalancing is bounded by what was voted");
        assertEq(destAfter, address(eqty), "FIXED: the mandate still names EQTY");
        assertEq(remAfter, 10_000, "FIXED: and its budget survives the attack intact");

        // ── 5. AND THE GENERATION WAS NOT REDENOMINATED ──────────────────────
        // This is what the attack was really for: flipping the denomination onto an
        // asset the treasury holds dust of, with 99.9% of the position untouched.
        assertEq(
            registry.generationQuote(1), address(0),
            "FIXED: the generation is still ETH-denominated - only a PRIMARY slice may flip it"
        );
        assertFalse(
            governor.migrationMandateSpent(),
            "FIXED: a mandate spent on side pools is not a migration"
        );
        assertEq(
            uint256(liqEnd), uint256(liqAfterDust),
            "the primary pair was never touched - which is exactly why it cannot count"
        );

        // ── 6. THE GUILD CAN STILL EXECUTE THE MIGRATION IT VOTED FOR ────────
        // The whole point: the envelope is still spendable on the thing it was for.
        // (No ETH/EQTY venue is curated in this harness, so this asserts the
        // governor's own accounting rather than driving the swap: a primary slice is
        // authorised for the full 10,000 bps.)
        assertEq(remAfter, 10_000, "a primary slice is authorised for the full mandate");

        console2.log("the dust leg can no longer extinguish a voted migration");
    }
}

contract EVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
    /// @dev HARNESS GAP, not a protocol finding. `TreasuryGovernor._passed` reads
    ///      `getPastTotalSupply` for its quorum denominator — that IS the real vote
    ///      source's API (`MiFrensGenesis` implements it). This mock had only
    ///      `totalSupply`, so every `execute` in this file died on an unrecognized
    ///      selector and both tests failed for a reason unrelated to what they
    ///      assert. Same one-line gap as T02_StaleFloorSandwich's `FVotes`.
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
