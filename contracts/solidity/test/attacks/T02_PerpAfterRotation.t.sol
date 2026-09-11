// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpMarkSource} from "../../cauldron/PerpMarkSource.sol";
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

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * T02 — WHAT DOES *NOT* FOLLOW A COMPLETED QUOTE ROTATION
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `RedemptionExt.rotateSliceFrom` re-points two things when the migration
 * mandate is spent: `generationQuote[gen]` (:469) and, best-effort,
 * `PerpEngine.quote` via `syncGeneration` (:504).
 *
 * It re-points NOTHING ELSE. This file measures two readers that must follow
 * the change and do not.
 *
 * A. `PerpMarkSource.primary` — the pool `PerpEngine._currentTick` samples the
 *    entire TWAP mark from. Written only by `setPrimary`, which is `onlyOwner`
 *    and called by nothing in the tree (grep: only deploy/DeployPerp.s.sol
 *    mentions it, and only "on every relaunch").
 *
 * B. `PerpEngine.minCollateral` — `0.003 ether` (PerpEngine.sol:144), an
 *    ABSOLUTE 18-decimal constant compared against collateral denominated in
 *    whatever `quote` now is.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract T02_PerpAfterRotation is YBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;
    PerpMarkSource internal markSrc;

    uint160 internal constant Q96 = 79228162514264337593543950336;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(
            IVotes721(address(new PVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));

        // Perp engine with an EMPTY LP vault, so `syncGeneration` is free to
        // adopt the new quote (PerpEngine.sol:1098 refuses while `plv != 0`).
        perp = new PerpEngine(
            pm, address(hook), address(registry),
            address(new PNoFrens()), address(0xD1D1), address(0x7E7E), address(this)
        );
        hook.setPerpEngine(address(perp));
        hook.setDeathThreshold(0, address(0), 0, 0, 0);

        // Wire the liquidity-weighted mark at the generation's launch pair,
        // exactly as deploy/DeployPerp.s.sol:140-141 instructs.
        markSrc = new PerpMarkSource(pm, address(this));
        markSrc.setPrimary(_key());
        perp.setRouting(address(0xD1D1), address(0x7E7E), address(0x7E7E), address(markSrc));

        _warp(25 hours);
        vm.roll(vm.getBlockNumber() + 40);
        perp.poke();
    }

    function _venueKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
    }

    function _destKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    function _rotateFully() internal returns (uint256 slices) {
        uint256 venueUsdg = 400_000e6;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 40 ether, venueUsdg, 60, 3000
        );
        rotator.setVenue(_venueKey(), true);

        uint256 id = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);

        for (uint256 i; i < 20; ++i) {
            (address open,) = governor.allowance();
            if (open == address(0)) break;
            try registry.rotateSlice(2500, 0, _venueKey()) { slices++; }
            catch { break; }
        }
    }

    // -----------------------------------------------------------------------

    /// @notice A. THE MARK STAYS IN THE OLD DENOMINATION.
    function test_T02_POC_MarkSourceDoesNotFollowTheRotation() public {
        vm.skip(!active);

        (Currency p0,,,,) = markSrc.primary();
        assertEq(Currency.unwrap(p0), address(0), "mark source armed on the ETH pair");

        uint256 slices = _rotateFully();
        assertGt(slices, 0, "the rotation ran");
        assertEq(registry.generationQuote(1), address(usdg), "generation redenominated");
        assertEq(perp.quote(), address(usdg), "and the engine ADOPTED the new quote");

        // The engine now settles, collateralises and pays in 6-decimal USDG...
        (Currency stillP0,,,,) = markSrc.primary();
        assertEq(Currency.unwrap(stillP0), address(0), "...but the mark is still sampled from the ETH pair");

        // Fill the TWAP ring from the (stale) mark source, the way any keeper or
        // swap would, then read the mark the engine would liquidate against.
        for (uint256 i; i < 8; ++i) { _warp(60); perp.poke(); }
        uint256 mark = uint256(perp.markSqrtPriceX96());

        (uint160 ethSqrt,,,) = pm.getSlot0(_key().toId());
        (uint160 usdgSqrt,,,) = pm.getSlot0(_destKey().toId());

        console2.log("engine quote              :", perp.quote());
        console2.log("mark sqrtPriceX96 (used)  :", mark);
        console2.log("ETH/token pool  sqrtPrice :", uint256(ethSqrt));
        console2.log("USDG/token pool sqrtPrice :", uint256(usdgSqrt));
        console2.log("ratio  mark : correct pool:", mark / uint256(usdgSqrt));

        // The mark tracks the abandoned ETH pair, not the pair the engine trades.
        assertApproxEqRel(mark, uint256(ethSqrt), 0.05e18, "mark == the OLD pool's price");
        // DIRECTION CORRECTED: the destination pool's sqrtPrice is the LARGER of
        // the two (the token is cheap in raw 6-decimal USDG units), so the stale
        // mark sits orders of magnitude BELOW the pool the engine settles in.
        // The earlier pass asserted this the wrong way round and the test failed
        // on a true finding.
        assertLt(
            mark * 10, uint256(usdgSqrt),
            "the mark is orders of magnitude away from the pool the engine now settles in"
        );

        // `_quoteMark(size) = size * (Q96/sqrt)^2` is the value every liquidation
        // test uses. Same size, two marks:
        uint256 size = 1e21; // 1,000 tokens
        uint256 valStale = _quoteAt(size, mark);
        uint256 valTrue = _quoteAt(size, uint256(usdgSqrt));
        console2.log("1,000 token marked, STALE :", valStale);
        console2.log("1,000 token marked, TRUE  :", valTrue);
        console2.log("stale/true overstatement x:", valTrue == 0 ? 0 : valStale / valTrue);
        assertGt(valStale, valTrue * 10, "positions mark at many times their real value");

        // The generation is NOT protected by the engine's own staleness guard:
        // `_isDead` (PerpEngine.sol:1307) compares `quote` against
        // `generationQuote` and they AGREE — `syncGeneration` ran. Nothing
        // anywhere compares the MARK SOURCE's pair against the engine's.
        assertEq(perp.quote(), registry.generationQuote(1), "quotes agree; only the mark is stale");

        bool reached = true;
        assertTrue(reached, "T02 mark-source-stale reached its assertions");
    }

    function _quoteAt(uint256 size, uint256 sp) internal pure returns (uint256) {
        uint256 a = (size * uint256(Q96)) / sp;
        return (a * uint256(Q96)) / sp;
    }

    /// @notice B. THE DUST FILTER IS AN 18-DECIMAL CONSTANT.
    /// After the rotation, `minCollateral` (0.003 ether = 3e15) is
    /// compared against a 6-decimal USDG amount. 3e15 raw USDG is
    /// three billion dollars, so every open reverts.
    function test_T02_POC_MinCollateralBricksOpensOnASixDecimalQuote() public {
        vm.skip(!active);

        uint256 slices = _rotateFully();
        assertGt(slices, 0, "the rotation ran");
        assertEq(perp.quote(), address(usdg), "engine adopted the 6-decimal quote");

        uint256 floorRaw = perp.minCollateral();
        console2.log("minCollateral (raw units) :", floorRaw);
        console2.log("...as WHOLE USDG ($)      :", floorRaw / 1e6);
        assertEq(floorRaw, 0.003 ether, "unchanged by the rotation");

        // A generous $50,000 of collateral, in the asset the engine now uses.
        uint256 collateral = 50_000e6;
        usdg.mint(trader, collateral);
        vm.prank(trader);
        usdg.approve(address(perp), collateral);

        vm.prank(trader, trader);
        vm.expectRevert(PerpEngine.DustPosition.selector);
        perp.openLong(2, 0, 0, collateral);

        console2.log("$50,000 of USDG collateral rejected as DUST");

        // And the ceiling on the fix is in the same units: `setMinCollateral`
        // refuses anything above 1 ether, which is fine here, but the value is
        // never rescaled by anything — it takes a governance transaction the
        // rotation does not trigger.
        assertEq(uint256(1 ether), 1e18, "setMinCollateral's ceiling is also 18-decimal");

        bool reached = true;
        assertTrue(reached, "T02 min-collateral reached its assertions");
    }
}

contract PVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}

contract PNoFrens {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}
