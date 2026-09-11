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
 * T02 — THE HALF-CHANGED TREASURY
 * ═══════════════════════════════════════════════════════════════════════════
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

    /// @notice A. A "MIGRATE THE WHOLE POSITION" MANDATE REDENOMINATES THE
    /// GENERATION WITH A THIRD OF IT STILL IN THE OLD ASSET.
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

    /// @notice B. AND THAT THIRD CAN NEVER BE ROTATED AGAIN.
    ///
    /// `fromLeg == 0` reads `fromQuote = generationQuote[gen]` (now USDG) but
    /// `srcKey = generationPoolKey[gen]` (still the ETH pair). `removePartial`
    /// then burns ETH liquidity and looks for the proceeds in the USDG balance.
    function test_T02_POC_PrimaryLegIsUnrotatableAfterTheFlip() public {
        vm.skip(!active);

        _approve(address(usdg), 10_000);
        for (uint256 i; i < 20; ++i) {
            (, uint16 left) = governor.allowance();
            if (left == 0) break;
            registry.rotateSlice(2500, 0, _venueKey());
        }
        assertEq(registry.generationQuote(1), address(usdg), "flipped");

        // The stored pair is UNCHANGED — this is the whole defect.
        (Currency c0,,,,) = registry.generationPoolKey(1);
        assertEq(Currency.unwrap(c0), address(0), "generationPoolKey[1] still names ETH as the quote");
        assertTrue(
            Currency.unwrap(c0) != registry.generationQuote(1),
            "generationQuote and generationPoolKey now disagree"
        );

        // The guild votes to bring the stranded third home. Native is an
        // allowed quote (CauldronRegistry.sol:173) and `_requirePriceable`
        // exempts it (TreasuryGovernor.sol:749), so the vote passes and
        // executes cleanly.
        _warp(governor.COOLDOWN() + 1);
        _approve(address(0), 10_000);
        (address dest, uint16 rem) = governor.allowance();
        assertEq(dest, address(0), "the envelope really does target native ether");
        assertGt(rem, 0, "and it is live");

        // Every slice of it reverts. The 31.6% is unreachable for the rest of
        // the generation's life.
        vm.expectRevert();
        registry.rotateSliceFrom(0, 2500, 0, _venueKey());

        console2.log("envelope remaining bps     :", rem);
        console2.log("rotateSliceFrom(0,...) reverted; the ETH leg cannot be moved");

        bool reached = true;
        assertTrue(reached, "T02 primary-unrotatable reached its assertions");
    }
}

contract SVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
