// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "../attacks/YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  F-10 — DENOMINATION TOTALITY: does the protocol follow a LIVE quote change?
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  INTENT (design, spine iii). A live rotation moves the LP from ETH into
 *  asset X. From that moment the pool trades X, and every downstream reader —
 *  fee routing, reserve credit, dividends, floors, and above all the perp
 *  engine's collateral/mark/funding/liquidation — must reference the asset the
 *  pool ACTUALLY trades now, not the one the generation launched with.
 *
 *  WHAT THIS TEST ESTABLISHES, mechanically:
 *
 *   1. `generationQuote[gen]` is written in exactly ONE place in the entire
 *      tree — `CauldronRegistry.sol:917`, inside `relaunch()`. Grep-verified.
 *      `RedemptionExt.rotateSlice` READS it (:278) to learn what it is moving
 *      FROM, and never writes it.
 *
 *   2. `PerpEngine.quote` — the field `_key()` (:449) builds the mark pool from
 *      — is assigned in exactly one place, `syncGeneration` (:1017).
 *
 *   3. `syncGeneration` is gated on the GENERATION CHANGING:
 *          if (gen == syncedGeneration) revert AlreadySynced();   // :977
 *      A rotation does not change the generation.
 *
 *  Together: after a live rotation there is NO call, privileged or otherwise,
 *  that can re-point the perp engine at the new quote for the rest of that
 *  generation. It marks, funds and liquidates against the pre-rotation pool —
 *  the one the rotation has been draining — until the next relaunch.
 *
 *  WHAT LIMITS IT. `CauldronHook.linkVolume` refuses while positions are open
 *  (:1473, `PerpsOpen`), and `rotateSlice` calls it (:316), so a rotation cannot
 *  re-denominate liquidity out from under LIVE positions. The exposure is to
 *  positions opened AFTER the rotation, against a pool holding the remnant.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract F10_QuoteRotationTotality is YBase {
    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        _bootPerp(10 ether, 50_000_000 ether);

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(IVotes721(address(new FVotes())), address(registry), address(this), 0, 0, 0, 0, false);
        registry.setRotationWiring(address(rotator), address(governor));
    }

    /// @notice THE HEADLINE TRANSITION (journey 4). Run a COMPLETE live
    ///         rotation ETH -> USDG and assert the generation's denomination and
    ///         the perp engine both follow it.
    ///
    ///  Pre-fix this was unreachable in two independent ways: `rotateSlice`
    ///  never wrote `generationQuote` (only `relaunch` did, Registry:917), and
    ///  `syncGeneration` refused without a generation change (:977) — so the
    ///  engine kept marking against the pool the rotation was draining, forever.
    function test_INVARIANT_F10_PerpQuoteFollowsALiveRotation() public {
        vm.skip(!active);

        assertEq(perp.quote(), address(0), "engine starts on ETH");
        assertEq(registry.generationQuote(1), address(0), "generation starts on ETH");

        PoolKey memory route = _seedVenue();

        // Approve the rotation the way governance would.
        uint256 id = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
        (address dest,) = governor.allowance();
        assertEq(dest, address(usdg), "envelope approved USDG");

        // Rotate until the envelope is spent. `minOut = 0` because this test is
        // about denomination plumbing, not execution quality — B-12 covers the
        // venue allowlist that bounds the latter.
        uint256 slices;
        for (uint256 i; i < 20; ++i) {
            (address open,) = governor.allowance();
            if (open == address(0)) break;
            try registry.rotateSlice(2500, 0, route) { slices++; }
            catch (bytes memory err) {
                if (slices == 0) console2.log("first slice reverted:", vm.toString(err));
                break;
            }
        }
        assertGt(slices, 0, "no slice executed - the rotation never ran");
        console2.log("slices executed:", slices);

        (address remaining,) = governor.allowance();
        assertEq(remaining, address(0), "envelope should be spent after a full rotation");

        //  1. THE GENERATION'S DENOMINATION FOLLOWED THE LIQUIDITY.
        assertEq(
            registry.generationQuote(1), address(usdg),
            "generationQuote must follow a completed rotation"
        );

        //  2. AND THE PERP ENGINE ALREADY FOLLOWED IT — with NO keeper call.
        //
        //  This assertion used to call `perp.syncGeneration()` first, because
        //  adopting the new quote was a separate, permissionless step someone had
        //  to remember to take. That left a window: between the final slice and
        //  whoever called sync, `PerpEngine.quote` still pointed at the drained
        //  pool, and `_guardOpen` (PerpEngine.sol:1210-1214) checks warmup, death
        //  and leverage but NOT quote freshness — so a trader could open in that
        //  window and pin the engine there, since `syncGeneration` then reverts
        //  `PositionsOpen()` (:987) and `forceClose*` both require a DEAD
        //  generation (:937, :950).
        //
        //  `rotateSlice` now re-points the engine in the same transaction that
        //  flips the quote (RedemptionExt.sol, at the `stillRotating` branch).
        //  That is safe precisely there and nowhere else: reaching it required
        //  `linkVolume` to succeed earlier in the same call, and that reverts
        //  `PerpsOpen()` unless `openCount == 0` (CauldronHook.sol:1518).
        //
        //  Asserted BEFORE any sync call, so this proves the engine followed on
        //  its own rather than proving a keeper can fix it after the fact.
        //  ── AMENDED, AND STRENGTHENED, BY R-08 ──────────────────────────────
        //  Adoption is the RIGHT outcome but it is not unconditional, and the
        //  condition is not cosmetic. `PerpEngine.plv` is a bare COUNTER of the
        //  quote asset and every payout leaves through `_pushQuote`, which pays in
        //  whatever `quote` names TODAY. So adopting a new quote while the LP
        //  vault holds value silently re-denominates staked capital: measured,
        //  an ETH staker's `withdrawEth` reverted `BadParam()` inside
        //  `_safeTransfer` with their ether sitting in the engine and no call able
        //  to reach it, and the next honest depositor in the NEW asset could be
        //  redeemed against by the stale ETH-side shares. {syncGeneration} now
        //  refuses while `plv != 0`.
        //
        //  The property this test exists to protect is NOT "the slot changed" —
        //  it is "the engine never prices, or sells leverage against, a pool the
        //  liquidity has left". Both branches are asserted, so the end is pinned
        //  however the means resolves:
        //
        //    plv == 0  -> the engine ADOPTS, exactly as before (no keeper call).
        //    plv != 0  -> the engine PARKS: {_isDead} reads the divergence as
        //                 death, so `_guardOpen` refuses new leverage (closing
        //                 the pin-the-engine window this test was written for)
        //                 and the book is force-closeable by anyone.
        if (perp.plv() == 0) {
            assertEq(
                perp.quote(), address(usdg),
                "the perp engine must mark against the asset the pool now trades"
            );
        } else {
            assertEq(perp.quote(), address(0), "a funded engine keeps the asset it can pay in");
            //  It must be INERT while diverged, or this branch would be a hole.
            address late = address(0xF10DEF);
            vm.deal(late, 1 ether);
            vm.prank(late, late);
            vm.expectRevert(PerpEngine.TokenDead.selector);
            perp.openLong{value: 0.004 ether}(1, 0, 0, 0.004 ether);
            console2.log("engine PARKED (plv funded), new leverage refused:", perp.plv());
        }

        //  3. AND A REDUNDANT SYNC IS A NO-OP, not a correction. `AlreadySynced`
        //     here is the positive signal that step 2 was not luck: there is
        //     nothing left for a keeper to adopt. On the parked branch the
        //     equivalent signal is `VaultStaked` — the refusal is deliberate and
        //     named, not an incidental failure, and it LIFTS once the vault is
        //     drained, which is asserted below rather than assumed.
        if (perp.plv() == 0) {
            vm.expectRevert(PerpEngine.AlreadySynced.selector);
            perp.syncGeneration();
        } else {
            vm.expectRevert(PerpEngine.VaultStaked.selector);
            perp.syncGeneration();

            //  THE PARK IS TEMPORARY, WHICH IS WHAT MAKES IT ACCEPTABLE: the
            //  refusal lifts the moment the quote-side capital is drained, and the
            //  engine then adopts on an ordinary permissionless call — no
            //  privileged key and no relaunch. This rig has no PerpVault wired
            //  (`_bootPerp` seeds `plv` straight from the owner), so the
            //  drain-then-adopt leg is proved where a real vault exists:
            //  S06_PerpVaultSolvency::test_S06_POC_QuoteRotationDrainsTheNewQuoteStakers.
            console2.log("engine parked pending a drain; plv:", perp.plv());
        }
    }

    /// @dev Stand up the ETH/USDG venue the rotation swaps through, and curate
    ///      it. The allowlist fails closed, so an uncurated venue reverts
    ///      `NoRoute` however deep it is.
    function _seedVenue() internal returns (PoolKey memory route) {
        uint256 venueUsdg = 400_000e6;
        usdg.mint(address(this), venueUsdg);
        // token = USDG (sorts above native), quote = ETH, hookless.
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

    /// @notice DOCUMENTS THE MITIGATION so the finding is not overstated: a
    ///         rotation cannot re-denominate liquidity under LIVE positions,
    ///         because `linkVolume` refuses while any position is open.
    function test_F10_RotationIsBlockedWhilePositionsAreOpen() public {
        vm.skip(!active);

        perp.setRisk(24 hours, 3, 4_000, 10_000, 10_000, 100);
        uint256 col = (perp.activeEthDepth() * 8 / 100) / 2;
        if (col < perp.minCollateral()) col = perp.minCollateral();
        vm.prank(trader);
        perp.openLong{value: col}(2, 0, 0, col);
        assertGt(perp.openCount(), 0, "a position is open");

        uint256 id = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);

        PoolKey memory route = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        rotator.setVenue(route, true);

        // The interlock is what keeps live positions safe. If this ever stops
        // reverting while positions are open, the finding above becomes far
        // worse: live collateral would be re-denominated underneath traders.
        vm.expectRevert();
        registry.rotateSlice(2500, 0, route);
    }
}

contract FVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    /// @dev Mirrors `Votes.getPastTotalSupply` — the quorum denominator the
    ///      real vote source ({MiFrensGenesis}) actually implements.
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
