// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase, YNoFrens} from "../attacks/YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {MockAggregator} from "../../cauldron/MockAggregator.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

interface IPosmLiquidity {
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128);
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  F-14 — ROTATION TOTALITY: EVERY SUBSYSTEM THAT COUNTS MONEY, ACROSS
 *         ETH → USDG → ETH, AGAINST REAL UNISWAP v4
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  The question is not "does the swap execute". It is whether the ACCOUNTING
 *  follows the quote everywhere. Each subsystem's state was sorted into
 *
 *    (a) ratios / shares / other-asset counts — survive a unit change untouched
 *    (b) absolute amounts in the quote — must convert at ONE realized rate,
 *        atomically, or they silently redenominate
 *    (c) per-asset ledgers — each figure stays in the asset it was earned in,
 *        so nothing converts and nothing redenominates
 *
 *  and each gets a check below:
 *
 *    perps      (b) the WHOLE book is carried at the flip, positions open:
 *                   money it holds (plv, shorts' backing, insurance, yield pot)
 *                   swapped once at the realized rate; longs' debt restated at
 *                   the oracle rate; TWAP shifted; vault queue/yield rescaled —
 *                   one call, inside the flipping slice (F12, F12b)
 *    dividends  (c) accPerShare / accPerShareOf[asset]: ETH stays ETH, USDG
 *                   arrives through `fundToken` (Q-01/B-01 on a ROTATED quote)
 *    floor      (a) entitledTokens is in the generation TOKEN; its backing is
 *                   the out-of-range reserve LP, which no slice touches
 *    hook fees  (c) relaunchETH / relaunchAsset[q]: never cross-credited
 *    volume     (a) only because the hook restates volume in USD at 1e18 — see
 *                   F14b for what happens without the oracle
 *    gacha      (a) same oracle; the router's quote follows the flip
 *
 *  `unabsorbedEth == 0` is asserted after every phase: no step of the trip may
 *  book a loss that nobody absorbed.
 * ═══════════════════════════════════════════════════════════════════════════
 */
abstract contract F14Base is YBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    QuoteRotator internal rotator;
    TreasuryGovernor internal tgov;
    MockQuoteToken internal usdg;
    QuoteOracle internal oracle;
    F14LegTrader internal legTrader;
    PoolKey internal route;

    /// 1 ETH = 3000 USDG, and the venue is seeded AT that price and deep enough
    /// (1,000 ETH) that a conversion measures accounting, not price impact.
    uint256 internal constant ETH_USD = 3000;

    function _bootRotation() internal {
        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        oracle = new QuoteOracle(address(this));
        oracle.setFeed(address(0), address(new MockAggregator("ETH/USD", int256(ETH_USD) * 1e8)), 4 hours, 18);
        oracle.setFeed(address(usdg), address(new MockAggregator("USDG/USD", 1e8)), 4 hours, 6);
        rotator.setArbParams(address(oracle), 1000, 5e18);
        rotator.setRotationSlipBps(2000);
        tgov = new TreasuryGovernor(
            IVotes721(address(new F14Votes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(tgov));

        uint256 venueEth = 1_000 ether;
        uint256 venueUsdg = venueEth * ETH_USD / 1e12;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0), address(usdg), address(0), venueEth, venueUsdg, 60, 3000
        );
        route = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(usdg)), 3000, 60, IHooks(address(0)));
        rotator.setVenue(route, true);
        legTrader = new F14LegTrader(pm);
    }

    /// The venue's own spot, as raw USDG per 1 ETH.
    function _venueUsdgPerEth() internal view returns (uint256) {
        (uint160 sp,,,) = pm.getSlot0(route.toId());
        return FullMath.mulDiv(uint256(sp) * uint256(sp), 1e18, uint256(1) << 192);
    }

    function _legKey() internal view returns (PoolKey memory) {
        return PoolKey(
            Currency.wrap(address(usdg)), Currency.wrap(registry.currentToken()),
            registry.POOL_FEE(), registry.TICK_SPACING(), IHooks(address(hook))
        );
    }

    function _approveEnvelopeTo(address q) internal {
        uint256 id = tgov.propose(q, tgov.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        tgov.vote(id, true);
        _warp(tgov.VOTING_PERIOD() + 1);
        tgov.execute(id);
    }

    /// Slice until the envelope is spent. `fromLeg` 0 = the primary pair.
    function _rotateUntilSpent(uint8 fromLeg) internal returns (uint256 slices) {
        for (uint256 i; i < 20; ++i) {
            //  Liveness is the REMAINING BPS, never the quote: `address(0)` is a
            //  legitimate destination (native ether) on the way back (R-03).
            (, uint16 left) = tgov.allowance();
            if (left == 0) break;
            try registry.rotateSliceFrom(fromLeg, 2500, 0, route) { slices++; }
            catch (bytes memory e) { console2.logBytes(e); break; }
        }
    }

    /// Buy then sell on the USDG leg, `usdgIn` worth.
    function _tradeLeg(uint256 usdgIn) internal {
        usdg.mint(address(legTrader), usdgIn * 2);
        uint256 got = legTrader.swap(_legKey(), true, usdgIn);
        legTrader.swap(_legKey(), false, got / 2);
    }
}

contract F14_RotationTotality is F14Base {
    using PoolIdLibrary for PoolKey;
    PerpVault internal vault;
    MiFrensGenesis internal mifrens;
    MiFrensDividend internal div;
    CauldronGachaRouter internal gacha;

    address internal alice = address(0xA11CE);      // ETH staker + enchanted OG
    address internal longer = address(0x1011);
    address internal shorter = address(0x5401);
    address internal keeper = address(0x6EE9);
    address internal constant DIV_TREASURY = address(0x7EA);

    // ── snapshots, kept in storage so no phase needs many locals (via_ir) ──
    uint256 internal sAliceEth;       // alice's staked value before the trip (wei)
    uint256 internal sDivEth;         // alice's pending ETH dividend before the trip
    uint256 internal sDivUsdg;        // alice's pending USDG dividend after the USDG phase
    uint256 internal sRelaunchEth;    // hook's native relaunch reserve before the trip
    uint256 internal sRelaunchUsdg;   // hook's USDG relaunch reserve after the USDG phase
    uint128 internal sReserveLiq;     // the floor's backing: the out-of-range reserve LP
    uint256 internal sConvertedUsdg;  // the stakers' pot in USDG after the first flip
    uint256 internal sBackEth;        // ...and in ETH again after the second
    uint256 internal sCarryId;        // a USDG long carried back across the return flip
    uint256 internal sOwedToReserve;  // tokens the floor buyback had bought before the flip

    function setUp() public {
        _boot(20 ether, 24);
        require(active, "F14_RotationTotality: fork not active - PoC proved nothing");
        _bootRotation();
        //  VOLUME IN USD. Threshold 0 keeps the brew alive while the test warps
        //  through governance delays; the curve constants are the deploy's.
        hook.setDeathThreshold(0, address(oracle), 50e18, 0.05e18, 1200e18);
        _bootVaultedPerp();
        _bootGuild();
        gacha = new CauldronGachaRouter(pm, address(hook), address(registry), address(this));
        gacha.setOracle(address(oracle));
        //  The collection floor's funding: the legacy buyback, as DeployLaunchpad
        //  arms it (40% carve, 0.02 ETH trigger), on top of the no-vault floor share.
        hook.setLegacyBuyback(address(registry), 4000, 0.02 ether);
    }

    function _bootVaultedPerp() internal {
        perp = new PerpEngine(
            pm, address(hook), address(registry),
            address(new YNoFrens()), address(0xD1D1), address(0x7E7E), address(this)
        );
        hook.setPerpEngine(address(perp));
        //  The engine prices its ETH-denominated knobs (dust filter, leverage tiers,
        //  insurance floor) in the quote through `quoteUnit`, restated at every
        //  adoption from THIS oracle — as `DeployPerp` wires it from QUOTE_ORACLE.
        perp.setRouting(address(0xD1D1), address(0x7E7E), address(0x7E7E), address(0), address(oracle));
        vault = new PerpVault(address(perp), address(registry));
        perp.setVault(address(vault));
        deal(token, address(this), 50_000_000 ether, true);
        IERC20Minimal(token).approve(address(perp), 50_000_000 ether);
        perp.fundPlvToken(50_000_000 ether);    // token side: not redenominated by a rotation
        perp.fundInsurance{value: 1 ether}(1 ether); // the breaker's floor, in ETH
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.depositEth{value: 10 ether}();
        _warp(25 hours);
        vm.roll(block.number + 40);
        perp.poke();
    }

    function _bootGuild() internal {
        mifrens = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(mifrens), DIV_TREASURY);
        mifrens.setDividend(address(div));
        vm.prank(DIV_TREASURY);
        div.setFunder(address(hook));
        hook.setGuild(address(div));
        vm.prank(alice);
        mifrens.mint{value: 0.01 ether}(1);
        vm.prank(alice);
        div.castSpell(1);
    }

    function _noBadDebt(string memory phase) internal view {
        assertEq(perp.unabsorbedEth(), 0, phase);
    }

    function _aliceValue() internal view returns (uint256 v) {
        (v,,) = vault.ethPosition(alice);
    }

    // ── phase 0: an ordinary ETH-quoted generation, with an open book ─────────

    function _phaseEth() internal {
        uint256 bought = _buy(2 ether, address(this));
        _sell(bought / 2, address(this));
        sAliceEth = _aliceValue();
        sDivEth = div.pending(1);
        sRelaunchEth = hook.relaunchETH();
        sReserveLiq = IPosmLiquidity(posm).getPositionLiquidity(registry.generationReservePositionId(1));
        assertGt(sDivEth, 0, "phase 0: the guild earned ETH");
        //  (With the floor buyback armed as deployed, `floorBps` 10000 sends every
        //  non-guild fee to the floor buffer, so the relaunch reserve may take
        //  nothing from fees — recorded, and checked below never to shrink or to
        //  take another asset.)
        assertGt(sReserveLiq, 0, "phase 0: the floor has a reserve LP to back it");
        assertApproxEqRel(gacha.playInCurveUnits(1 ether), 3000e18, 1e15, "phase 0: 1 ETH of play = $3000");
        _pumpLive(3);
        sOwedToReserve = hook.legacyOwedToReserve();
        assertGt(sOwedToReserve, 0, "phase 0: the floor buyback is buying tokens with ETH fees");
    }

    /// A few buy/sell rounds on the LIVE pool, one block apart — the buyback's
    /// price reference is one block delayed, and its first run on a pool only
    /// seeds that reference.
    function _pumpLive(uint256 rounds) internal {
        for (uint256 i; i < rounds; ++i) {
            vm.roll(vm.getBlockNumber() + 1);
            if (Currency.unwrap(hook.liveKey().currency0) == address(0)) {
                uint256 got = _buy(1 ether, address(this));
                _sell(got / 2, address(this));
            } else {
                _tradeLeg(10_000e6);
            }
        }
    }

    function _openBook() internal {
        uint256 col = perp.minCollateral() * 4;
        vm.deal(longer, 1 ether);
        vm.deal(shorter, 1 ether);
        vm.prank(longer, longer);
        perp.openLong{value: col}(2, 0, 0, col);
        vm.prank(shorter, shorter);
        perp.openShort{value: col}(2, 0, 0, col);
        assertEq(perp.openCount(), 2, "an open book straddles the flip");
    }

    // ── phase 1: ETH → USDG with the book OPEN, and the book is carried ───────

    /// Money the engine physically holds in its quote: what the flip must swap.
    function _physicalPot() internal view returns (uint256 pot) {
        pot = perp.plv() + perp.insuranceEth() + perp.tokYieldEth();
        for (uint256 id = 1; id < perp.nextId(); ++id) {
            (address t, bool isLong, uint128 c,, uint256 pr,,,) = perp.positions(id);
            if (t != address(0) && !isLong) pot += uint256(c) + pr;
        }
    }

    function _phaseToUsdg() internal {
        _approveEnvelopeTo(address(usdg));
        _openBook();
        perp.poke();
        (, , uint128 lCol, uint256 lSize, uint256 lPrin, , , ) = perp.positions(1);
        (, , uint128 sCol, uint256 sSize, uint256 sPrin, , , ) = perp.positions(2);
        uint256 potEth = _physicalPot();

        uint256 slices = _rotateUntilSpent(0);
        assertGt(slices, 0, "phase 1: the rotation ran");
        assertEq(registry.generationQuote(1), address(usdg), "phase 1: the generation re-denominated");

        //  THE BOOK WAS CARRIED, not parked and force-closed (red-team D-1).
        assertEq(perp.quote(), address(usdg), "phase 1: engine adopted USDG inside the flipping slice");
        assertEq(perp.openCount(), 2, "phase 1: both positions are still open");
        assertEq(uint256(vm.load(address(perp), bytes32(uint256(86)))), 3000e6, "phase 1: quoteUnit = 3000 USDG per ETH");
        (, , uint128 lCol2, uint256 lSize2, uint256 lPrin2, , , ) = perp.positions(1);
        (, , , uint256 sSize2, , , , ) = perp.positions(2);
        assertEq(lSize2, lSize, "phase 1: the long's TOKENS are untouched");
        assertEq(sSize2, sSize, "phase 1: the short's owed tokens are untouched");
        //  The long's debt was not money — it already bought the tokens — so it
        //  is restated at the ORACLE rate, and rounds UP (it is owed to stakers).
        assertEq(lPrin2, (lPrin * 3000e6 + 1 ether - 1) / 1 ether, "phase 1: long debt restated at the oracle rate");
        assertEq(uint256(lCol2), uint256(lCol) * 3000e6 / 1 ether, "phase 1: long collateral restated at the oracle rate");

        //  The money WAS swapped, once, through the curated venue.
        uint256 got = usdg.balanceOf(address(perp));
        console2.log("F14 physical pot swapped (wei)", potEth);
        console2.log("F14 ...arrived as (usdg)      ", got);
        console2.log("F14 realized usdg per eth     ", got * 1e18 / potEth);
        assertGe(got, potEth * 3000e6 / 1 ether * 90 / 100, "phase 1: the swap cleared near the oracle");
        //  The short's backing WAS money, so it moved at exactly the realized
        //  rate — the swap's slippage stays with the money that was swapped.
        (, , uint128 sCol2, , uint256 sPrin2, , , ) = perp.positions(2);
        assertEq(uint256(sCol2), uint256(sCol) * got / potEth, "phase 1: short collateral at the realized rate");
        assertEq(sPrin2, sPrin * got / potEth, "phase 1: short proceeds at the realized rate");
        assertEq(address(perp).balance, 0, "phase 1: no ETH left behind in the engine");
        assertGe(got, _physicalPot(), "phase 1: engine solvent - every USDG figure is backed");

        //  THE BUYBACK FOLLOWS: the hook's live pool is now the USDG leg.
        assertEq(Currency.unwrap(hook.liveKey().currency0), address(usdg), "phase 1: the live key followed the flip");
        assertEq(Currency.unwrap(hook.liveKey().currency1), registry.currentToken(), "phase 1: same token");

        //  D-3: nothing to re-arm. The mark source is dropped (it weighed the OLD
        //  pair), and the engine marks the NEW pool through its carried ring —
        //  still warm, so a live book is never marked off a reset ring's spot.
        (, bool warm) = perp.twapTick();
        assertTrue(warm, "phase 1: the carried TWAP is warm on the new pool");
        assertFalse(perp.blocksVolumeLink(), "phase 1: and a further rotation is not blocked by the book");

        sConvertedUsdg = perp.totalEth();
        assertApproxEqRel(_aliceValue(), sConvertedUsdg, 1e12, "phase 1: the only staker owns the whole restated pot");
        _noBadDebt("phase 1: carrying the book booked no bad debt");
    }

    // ── phase 2: live on the USDG leg ─────────────────────────────────────────

    /// Blocks advance WITH time. The rotated leg is a NEW pool, so it carries
    /// the launch anti-snipe surtax (up to ~99%) for `snipeWindowBlocks` after
    /// its first slice; warping the clock alone makes the next swap pay it.
    function _pastLegSurtax() internal {
        vm.roll(vm.getBlockNumber() + 200);
        _warp(perp.twapWindow() + 1);
        perp.poke();
    }

    /// The two CARRIED positions close on the deep new pool and are paid in USDG.
    function _closeCarried() internal {
        (, , uint128 lCol, , , , , ) = perp.positions(1);
        (, , uint128 sCol, , , , , ) = perp.positions(2);
        uint256 insBefore = perp.insuranceEth();
        vm.prank(longer, longer);
        perp.close(1, 0);
        vm.prank(shorter, shorter);
        perp.close(2, 0);
        uint256 lPaid = usdg.balanceOf(longer);
        uint256 sPaid = usdg.balanceOf(shorter);
        console2.log("F14 carried long  paid (usdg)", lPaid, "on collateral", uint256(lCol));
        console2.log("F14 carried short paid (usdg)", sPaid, "on collateral", uint256(sCol));
        assertEq(perp.openCount(), 0, "phase 2: both carried positions closed");
        //  No forced sale, no wipe-out (pre-fix the long got 0). Measured drag,
        //  and why: the rotation's own slices price the NEW pool at the venue's
        //  walked rate (~4% under the oracle the long's debt was restated at), a
        //  2x position feels that twice; the short's backing (~3x collateral)
        //  took the ~5% swap slippage; plus the swap tax and days of funding.
        //  So: long ~86%, short ~79% of collateral — bounded here at half.
        assertGe(lPaid, uint256(lCol) / 2, "phase 2: the carried long is paid at market, in USDG");
        assertGe(sPaid, uint256(sCol) / 2, "phase 2: the carried short is paid at market, in USDG");
        //  Insurance legitimately pays FUNDING owed to a trader (`_settle` draws it
        //  first). What must not happen is a D-1 shortfall — that drew 43% of the
        //  fund. Bounded at 0.1%: funding dust, never a forced-sale gap.
        assertLe(insBefore - perp.insuranceEth(), insBefore / 1000, "phase 2: closing drew at most funding dust");
    }

    /// A perp opened and closed IN USDG: its swap fee reaches the guild through
    /// `routePerp` → `fundToken` — the exact B-01 shape, on a rotated quote.
    function _usdgPerpRoundTrip() internal {
        uint256 divBefore = div.pendingToken(1, address(usdg));
        //  No top-up needed: insurance was CONVERTED at the flip, not swept.
        assertGt(perp.insuranceEth(), 0, "phase 2: insurance arrived in USDG");
        usdg.mint(longer, 1_000e6);
        vm.startPrank(longer, longer);
        usdg.approve(address(perp), type(uint256).max);
        uint256 id = perp.openLong(2, 0, 0, 100e6);
        perp.close(id, 0);
        //  ...and one more, left OPEN to be carried back across the return flip.
        sCarryId = perp.openLong(2, 0, 0, 200e6);
        vm.stopPrank();
        assertEq(perp.openCount(), 1, "phase 2: one USDG long left open");
        assertGt(div.pendingToken(1, address(usdg)), divBefore, "phase 2: a USDG perp fee reached the guild (B-01, rotated)");
    }

    function _phaseUsdg() internal {
        //  Whatever the buffer still held in ETH at the flip is credited back to
        //  the ETH reserve bucket on the first live swap — its own asset.
        uint256 staleEth = hook.legacyBufferAsset() == address(0) ? hook.legacyBuffer() : 0;
        uint256 ethBefore = hook.relaunchETH() + staleEth;
        _pastLegSurtax();
        _closeCarried();
        _usdgPerpRoundTrip();
        _tradeLeg(30_000e6);
        uint256 owedBefore = hook.legacyOwedToReserve();
        _pumpLive(4);
        assertEq(hook.legacyBufferAsset(), address(usdg), "phase 2: the floor buffer now holds USDG");
        console2.log("F14 floor buyback tokens: before flip", sOwedToReserve, "after USDG trading", hook.legacyOwedToReserve());
        assertGt(hook.legacyOwedToReserve(), owedBefore, "phase 2: USDG fees BUY the floor's tokens on the new leg");
        sDivUsdg = div.pendingToken(1, address(usdg));
        sRelaunchUsdg = hook.relaunchAsset(address(usdg));
        assertGt(sDivUsdg, 0, "phase 2: the guild earned USDG through fundToken (Q-01/B-01 on a rotated quote)");
        assertGe(div.pending(1), sDivEth, "phase 2: ETH dividends earned before the flip are intact");
        assertEq(hook.relaunchETH(), ethBefore, "phase 2: USDG fees never inflate the ETH bucket");

        uint256 legVol = hook.getVolume24h(_legKey().toId());
        console2.log("F14 USDG-leg vol24h (USD 1e18)", legVol);
        assertGt(legVol, 10_000e18, "phase 2: USDG volume is recorded in USD, not raw 6-dec units");
        hook.setDeathThreshold(10_000e18, address(0), 0, 0, 0);
        assertFalse(hook.isDead(registry.generationPoolId(1)), "phase 2: a busy rotated generation is ALIVE");
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        assertApproxEqRel(gacha.playInCurveUnits(3000e6), 3000e18, 1e15, "phase 2: 3000 USDG of play = $3000");
        _noBadDebt("phase 2");
    }

    // ── phase 3: USDG → ETH with a USDG long open — carried back ──────────────

    function _phaseBackToEth() internal {
        _warp(tgov.COOLDOWN() + 1);
        _approveEnvelopeTo(address(0));
        (, , , uint256 cSize, uint256 cPrin, , , ) = perp.positions(sCarryId);
        uint256 potUsdg = _physicalPot();

        uint256 slices = _rotateUntilSpent(1);
        assertGt(slices, 0, "phase 3: the return rotation ran");
        assertEq(registry.generationQuote(1), address(0), "phase 3: the generation is ETH again");
        assertEq(perp.quote(), address(0), "phase 3: engine adopted ETH inside the rotation");
        assertEq(perp.openCount(), 1, "phase 3: the USDG long was carried back, still open");
        assertEq(Currency.unwrap(hook.liveKey().currency0), address(0), "phase 3: the live key came home too");
        assertEq(uint256(vm.load(address(perp), bytes32(uint256(86)))), 1e18, "phase 3: quoteUnit back to wei");
        (, , , uint256 cSize2, uint256 cPrin2, , , ) = perp.positions(sCarryId);
        assertEq(cSize2, cSize, "phase 3: its tokens untouched");
        assertEq(cPrin2, (cPrin * 1 ether + 3000e6 - 1) / 3000e6, "phase 3: its debt restated at the oracle rate");

        uint256 gotEth = address(perp).balance;
        console2.log("F14 return pot swapped (usdg)", potUsdg);
        console2.log("F14 ...arrived as (wei)      ", gotEth);
        assertGe(gotEth, potUsdg * 1 ether / 3000e6 * 97 / 100, "phase 3: converted back at >= 97% of fair");
        assertEq(usdg.balanceOf(address(perp)), 0, "phase 3: no USDG stranded in the engine");
        assertGe(gotEth, _physicalPot(), "phase 3: engine solvent in ETH");

        //  The carried long closes on the ETH pool and is paid in ETH.
        _pastLegSurtax();
        uint256 before = longer.balance;
        vm.prank(longer, longer);
        perp.close(sCarryId, 0);
        console2.log("F14 carried-back long paid (wei)", longer.balance - before);
        assertGt(longer.balance - before, 0, "phase 3: paid in ETH");
        sBackEth = perp.totalEth();
        _noBadDebt("phase 3");
    }

    function test_F14_RoundTrip_EveryLedgerSurvives() public {
        _phaseEth();
        _phaseToUsdg();
        _phaseUsdg();
        _phaseBackToEth();

        //  PERPS: alice exits in ETH with the WHOLE pot.
        //
        //  The round trip is not free, and the cost is worth naming: the stake
        //  converts at the END of each rotation, after the rotation's own slices
        //  have walked the venue, so stakers pay the price impact of the LP
        //  rotation that preceded them. Execution cost on a finite venue, bounded
        //  per leg above — not forfeiture — and it scales with rotation size /
        //  venue depth. The drag is logged below.
        uint256 shares = vault.ethShareOf(alice);
        uint256 before = alice.balance;
        vm.prank(alice);
        vault.withdrawEth(shares);
        uint256 out = alice.balance - before;
        console2.log("F14 alice staked (wei)", sAliceEth);
        console2.log("F14 alice exits  (wei)", out);
        assertApproxEqRel(out, sBackEth, 1e12, "perps: alice is paid the whole pot");
        console2.log("F14 round-trip drag (bps)", (sAliceEth - out) * 10_000 / sAliceEth);

        //  DIVIDENDS: both ledgers pay, each in its own asset.
        uint256 ethBefore = alice.balance;
        vm.prank(alice);
        div.claim(1);
        assertGe(alice.balance - ethBefore, sDivEth, "dividends: the ETH accrued before the flip is paid in ETH");
        vm.prank(alice);
        div.claimTokens(1);
        assertGe(usdg.balanceOf(alice), sDivUsdg, "dividends: the USDG accrued on the leg is paid in USDG");

        //  HOOK FEES: each bucket kept its own asset, and neither shrank.
        assertGe(hook.relaunchETH(), sRelaunchEth, "fees: the ETH reserve was never spent or redenominated");
        assertGe(hook.relaunchAsset(address(usdg)), sRelaunchUsdg, "fees: the USDG reserve is parked, accounted");

        //  FLOOR: the reserve LP that backs every entitlement never moved.
        assertEq(
            IPosmLiquidity(posm).getPositionLiquidity(registry.generationReservePositionId(1)),
            sReserveLiq,
            "floor: no slice touched the reserve LP"
        );
        _noBadDebt("end of the round trip");
    }
}

/**
 *  F-14b — WHY THE VOLUME ROW ABOVE NEEDS THE ORACLE.
 *
 *  Without `hook.quoteOracle`, `_toUsd` returns the RAW quote amount. That is
 *  consistent while every pool shares one quote and breaks at the first
 *  rotation into a quote with different decimals: the same dollar arrives on
 *  the USDG leg as 1e6 instead of ~3.3e14 wei, so the generation's 24h volume —
 *  what `isDead` compares against `deathThreshold`, and what `relaunch()` is
 *  gated on — collapses by ~3e8x the moment trading moves to the new leg.
 *
 *  `DeployLaunchpad`'s DEPLOY_QUOTES path used to ship exactly this: it wired the
 *  oracle into the rotator (so rotation ran) and nowhere else.
 */
contract F14b_RotationWithoutHookOracle is F14Base {
    using PoolIdLibrary for PoolKey;

    function setUp() public {
        _boot(20 ether, 0);
        require(active, "F14b_RotationWithoutHookOracle: fork not active - PoC proved nothing");
        _bootRotation();
        //  The shipped no-oracle default: 1 ETH of 24h volume keeps a brew alive.
        hook.setDeathThreshold(1 ether, address(0), 0, 0, 0);
    }

    function test_F14b_RawVolumeReadsABusyRotatedGenerationAsDead() public {
        _approveEnvelopeTo(address(usdg));
        assertGt(_rotateUntilSpent(0), 0, "the rotation ran");
        assertEq(registry.generationQuote(1), address(usdg), "and completed");

        _warp(25 hours);                 // only post-rotation trading counts
        vm.roll(vm.getBlockNumber() + 200); // and past the new leg's launch surtax
        _tradeLeg(30_000e6);             // ~10 ETH of real volume, 10x the threshold

        uint256 vol = hook.getVolume24h(_legKey().toId());
        bool dead = hook.isDead(registry.generationPoolId(1));
        console2.log("F14b raw leg vol24h", vol);
        console2.log("F14b threshold     ", hook.deathThreshold());
        assertLt(vol, 1e12, "CHARACTERISED: $30k of USDG volume is recorded as < 1e12 raw units");
        assertTrue(dead, "CHARACTERISED: so a generation doing 10x its threshold reads DEAD");
    }
}

// ── fixtures ────────────────────────────────────────────────────────────────

contract F14Votes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}

/// A plain trader on any pool, native or ERC20 on either side.
contract F14LegTrader {
    IPoolManager internal immutable pm;
    uint160 internal constant MIN_LIMIT = 4295128740;
    uint160 internal constant MAX_LIMIT = 1461446703485210103287273052203988822378723970342 - 1;

    constructor(IPoolManager _pm) { pm = _pm; }
    receive() external payable {}

    function swap(PoolKey calldata key, bool zeroForOne, uint256 amountIn) external returns (uint256 out) {
        out = abi.decode(pm.unlock(abi.encode(key, zeroForOne, amountIn)), (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (PoolKey memory key, bool z, uint256 amt) = abi.decode(data, (PoolKey, bool, uint256));
        BalanceDelta d = pm.swap(
            key, SwapParams({zeroForOne: z, amountSpecified: -int256(amt), sqrtPriceLimitX96: z ? MIN_LIMIT : MAX_LIMIT}), ""
        );
        _settle(key.currency0, d.amount0());
        _settle(key.currency1, d.amount1());
        int128 o = z ? d.amount1() : d.amount0();
        return abi.encode(uint256(uint128(o)));
    }

    function _settle(Currency c, int128 a) private {
        if (a < 0) {
            uint256 owe = uint256(uint128(-a));
            if (Currency.unwrap(c) == address(0)) {
                pm.settle{value: owe}();
            } else {
                pm.sync(c);
                IERC20Minimal(Currency.unwrap(c)).transfer(address(pm), owe);
                pm.settle();
            }
        } else if (a > 0) {
            pm.take(c, address(this), uint256(uint128(a)));
        }
    }
}
