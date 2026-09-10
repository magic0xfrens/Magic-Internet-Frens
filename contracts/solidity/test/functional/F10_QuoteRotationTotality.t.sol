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

        //  2. AND THE PERP ENGINE CAN NOW ADOPT IT. Pre-fix this reverted
        //     `AlreadySynced` because the generation number had not changed.
        perp.syncGeneration();
        assertEq(
            perp.quote(), address(usdg),
            "the perp engine must mark against the asset the pool now trades"
        );
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
    function totalSupply() external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
