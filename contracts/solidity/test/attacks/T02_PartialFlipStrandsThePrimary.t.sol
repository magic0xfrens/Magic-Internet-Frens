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
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

interface IPosLiq {
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128);
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * T02 — THE HALF-CHANGED TREASURY  (REGRESSION; both halves resolved)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * WHY THIS FILE WAS IN THE DEPLOY GATE'S BASELINE-FAILURE LIST, and it should not
 * have been: its vote mock implemented `totalSupply` where
 * `TreasuryGovernor._passed` needs `getPastTotalSupply`, so every `execute` here
 * died on an unrecognized selector and BOTH tests failed before reaching a single
 * assertion. A broken harness is indistinguishable from a real regression when the
 * gate compares by name. Mock widened; see `SVotes` at the bottom.
 *
 * OF THE TWO CLAIMS BELOW, ONE IS ACCEPTED BEHAVIOUR AND ONE WAS A REAL BUG:
 *   A. the ~31.6% tail is REAL and DELIBERATE — see {RedemptionExt.rotateSliceFrom}
 *      ("this deliberately does NOT try to make the flip a full-drain test ...
 *      demanding a drained position would make completion unreachable and the whole
 *      feature dead"). Asserted here as the accepted, bounded property it is.
 *   B. the tail being UNROTATABLE was the bug, and it is fixed: `fromLeg == 0` now
 *      resolves its quote from `generationPoolKey.currency0` — the pair's own quote
 *      — instead of from `generationQuote`. That is what makes A a limitation
 *      rather than a loss.
 *
 * `RedemptionExt.rotateSliceFrom` flips the generation's denomination when
 * the governor says the migration mandate is spent (:468-469):
 *
 *     if (ITreasuryGovernor(gov).migrationMandateSpent()) {
 *         generationQuote[gen] = toQuote;
 *
 * and `migrationMandateSpent` (TreasuryGovernor.sol:656-659) is
 *
 *     return e.maxTotalBps >= BPS_ONE && e.movedBps >= e.maxTotalBps;
 *
 * `movedBps` is a LINEAR SUM of slice sizes (`consume`, :668-684) while each
 * slice removes `sliceBps` of *current* liquidity — a COMPOUNDING quantity.
 * The two units are not the same, and the file says so itself:
 *
 *     "HONEST ABOUT THE UNIT: slices are a share of CURRENT liquidity, so
 *      budget bps compound rather than sum to a clean fraction ... a small
 *      tail can remain in the old pair."
 *
 * At the exact threshold the test uses — `maxTotalBps == 10_000`, the SMALLEST
 * mandate that counts as "the guild authorised moving the WHOLE position" —
 * the tail is 0.75^4 = 31.6%, not "small".
 *
 * And then `generationQuote[gen]` is the ONLY thing that moves.
 * `generationPoolKey[gen]` and `generationPositionId[gen]` (CauldronBase.sol:188,
 * :190) still describe the ORIGINAL pair, and nothing rewrites them. So
 * `fromLeg == 0` (:337-340) now reads a quote from one generation-scoped slot
 * and a position from another that no longer agrees with it, hands both to
 * `PoolOps.removePartial`, and that function MEASURES the recovered quote with
 * `_balance(quote)` (PoolOps.sol:920) while SETTLING `key.currency0/currency1`.
 * The measurement and the settlement are for different assets.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract T02_PartialFlipStrandsThePrimary is YBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(
            IVotes721(address(new SVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));

        uint256 venueUsdg = 400_000e6;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 40 ether, venueUsdg, 60, 3000
        );
        rotator.setVenue(_venueKey(), true);
    }

    function _venueKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
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
        return IPosLiq(posm).getPositionLiquidity(registry.generationPositionId(1));
    }

    // -----------------------------------------------------------------------

    /// @notice A. ACCEPTED PROPERTY. A "migrate the whole position" mandate
    /// redenominates the generation and leaves a BOUNDED tail in the old asset,
    /// because slices are a share of CURRENT liquidity and therefore compound
    /// rather than sum. 0.75^4 = 31.6%. This is documented and deliberate; the
    /// alternative (demanding a drained pair) makes completion unreachable.
    /// What makes it survivable is test B: the tail stays addressable.
    function test_T02_POC_FullMandateFlipsWithAThirdLeftBehind() public {
        vm.skip(!active);

        uint128 liq0 = _primaryLiquidity();
        assertGt(liq0, 0, "precondition: the primary pair holds the treasury");
        assertEq(registry.generationQuote(1), address(0), "precondition: ETH-denominated");

        // The SMALLEST mandate `migrationMandateSpent` accepts as "the whole
        // position": 10,000 bps. A guild reading the UI sees "100%".
        _approve(address(usdg), 10_000);

        uint256 slices;
        for (uint256 i; i < 20; ++i) {
            (, uint16 left) = governor.allowance();
            if (left == 0) break;
            registry.rotateSlice(2500, 0, _venueKey());
            slices++;
        }

        uint128 liq1 = _primaryLiquidity();
        uint256 remainingPct = (uint256(liq1) * 10_000) / uint256(liq0);

        console2.log("slices executed            :", slices);
        console2.log("primary liquidity BEFORE   :", uint256(liq0));
        console2.log("primary liquidity AFTER    :", uint256(liq1));
        console2.log("still in the OLD asset, bps:", remainingPct);
        console2.log("generationQuote[1]         :", registry.generationQuote(1));

        assertEq(slices, 4, "a 10,000-bps envelope buys exactly four 2,500-bps slices");
        assertEq(registry.generationQuote(1), address(usdg), "the generation is now USDG-denominated");

        // 0.75^4 = 0.31640625 of the original liquidity is STILL in the ETH pair.
        assertApproxEqRel(remainingPct, 3164, 0.02e18, "~31.6% never moved");
        assertGt(remainingPct, 3000, "nearly a third of the treasury is in the asset the guild left");

        bool reached = true;
        assertTrue(reached, "T02 partial-flip reached its assertions");
    }

    /// @notice B. REGRESSION — AND THAT THIRD IS STILL ADDRESSABLE.
    ///
    /// The bug: `fromLeg == 0` read `fromQuote = generationQuote[gen]` (flipped to
    /// USDG) while `srcKey = generationPoolKey[gen]` still named the ETH pair, so
    /// `removePartial` burned ETH liquidity and looked for the proceeds in the USDG
    /// balance — `quoteOut == 0`, revert `BadConfig`, residual frozen for the life
    /// of the generation.
    ///
    /// THE OLD ASSERTION COULD NOT SEE THE FIX. It was a bare `vm.expectRevert()`
    /// over a call whose ONLY defect was WHICH error it raised, and it pointed the
    /// envelope at native ether — the primary pair's own quote — so it would keep
    /// passing on a correctly refused self-rotation long after the freeze was gone.
    /// Both directions are now asserted separately and by selector.
    function test_T02_POC_PrimaryLegIsUnrotatableAfterTheFlip() public {
        vm.skip(!active);

        _approve(address(usdg), 10_000);
        for (uint256 i; i < 20; ++i) {
            (, uint16 left) = governor.allowance();
            if (left == 0) break;
            registry.rotateSlice(2500, 0, _venueKey());
        }
        assertEq(registry.generationQuote(1), address(usdg), "flipped");

        // The two slots still disagree, and they MUST: the 69x redemption reserve is
        // held under `generationPoolKey`, so the primary cannot be re-pointed. That
        // divergence is the precondition the fix had to survive, not remove.
        (Currency c0,,,,) = registry.generationPoolKey(1);
        assertEq(Currency.unwrap(c0), address(0), "generationPoolKey[1] still names ETH as the quote");
        assertTrue(
            Currency.unwrap(c0) != registry.generationQuote(1),
            "generationQuote and generationPoolKey disagree - the shape that used to freeze the primary"
        );

        uint128 liqBefore = _primaryLiquidity();
        assertGt(liqBefore, 0, "the stranded third is still sitting in the ETH pair");

        // The guild votes to finish the job: drain the ETH residual into USDG.
        _warp(governor.COOLDOWN() + 1);
        _approve(address(usdg), 10_000);
        (address dest, uint16 rem) = governor.allowance();
        assertEq(dest, address(usdg), "the envelope targets the destination");
        assertGt(rem, 0, "and it is live");

        // ── THE FIX ─────────────────────────────────────────────────────────
        // This is the exact call that used to revert BadConfig() = 0x07cc321c.
        (uint256 moved,) = registry.rotateSliceFrom(0, 2500, 0, _venueKey());
        assertGt(moved, 0, "FIXED: the primary residual rotates, and real value moves");
        assertLt(_primaryLiquidity(), liqBefore, "FIXED: the ETH pair actually shrank");

        // ── AND THE GUARD IT MUST NOT HAVE DISABLED ─────────────────────────
        // Leg 1 is already USDG, so rotating it into USDG is a self-rotation and is
        // still refused by name. The fix resolves the primary's REAL quote; it does
        // not make every slice succeed.
        vm.expectRevert(bytes4(keccak256("BadConfig()")));
        registry.rotateSliceFrom(1, 2500, 0, _venueKey());

        console2.log("primary liquidity before   :", uint256(liqBefore));
        console2.log("primary liquidity after    :", uint256(_primaryLiquidity()));
        console2.log("quote moved out of the ETH residual:", moved);
    }
}

contract SVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
    /// @dev HARNESS GAP, not a protocol finding, and the reason this whole file sat
    ///      in the deploy gate's baseline-failure list. `TreasuryGovernor._passed`
    ///      reads `getPastTotalSupply` for its quorum denominator — that IS the real
    ///      vote source's API (`MiFrensGenesis` implements it). This mock had only
    ///      `totalSupply`, so every `execute` here died on an unrecognized selector
    ///      and both tests failed before reaching an assertion. Same one-line gap as
    ///      `FVotes` in T02_StaleFloorSandwich.
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
}
