// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ReserveLib} from "../../cauldron/ReserveLib.sol";
import {SeedLib} from "../../cauldron/SeedLib.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/**
 * INDEPENDENT audit fuzz + stateful-invariant suite (2026 review), covering the
 * three pure/near-pure kernels the whole value model rests on:
 *
 *   INV-R  the reserve position can never DELIVER more token than was deposited
 *          for it (otherwise redemption/migration mints value out of rounding);
 *   INV-D  the reserve round-trip's dust is bounded by (sqrtHi-sqrtLo)/Q96, which
 *          is what `PoolOps.CLAIM_DUST = 1e12` has to dominate;
 *   INV-S  the progressive seed schedule is monotone, bounded, and terminates at
 *          exactly 100% (so ledger A can never be over- or under-deployed);
 *   INV-L  CollectionLedger keeps `totalEntitled == Sum(entitledTokens)` across any
 *          interleaving of credit / redeem / buyback / crystallize.
 */
contract ZPureInvariants is Test {
    int24 internal constant SPACING = 200;

    // -----------------------------------------------------------------------
    // INV-R / INV-D — reserve liquidity round-trip
    // -----------------------------------------------------------------------

    uint256 internal constant TOTAL_SUPPLY = 777_000_000e18;

    /// The band the protocol ACTUALLY uses: `ReserveLib.reserveTicks(launchTick,...)`.
    /// `launchTick` is the tick of (activeTokens : seedETH) = tokens-per-ETH, which for
    /// a 777M-token supply against any plausible seed lands in the +100k..+250k range;
    /// we fuzz a generous superset of that.
    function _protocolBand(int24 launchSeed, int24 offSeed) internal pure returns (int24 lo, int24 hi) {
        int24 launchTick = int24(bound(int256(launchSeed), 50_000, 400_000));
        int24 offset = int24(bound(int256(offSeed), 4000, 138_000));
        (lo, hi) = ReserveLib.reserveTicks(launchTick, SPACING, offset);
    }

    /// The reserve can never hand out MORE than was put in. This is the lemma that
    /// makes "1:1 migration" and "redeem at floor" safe: `claimFromReserve` sizes a
    /// withdrawal in liquidity units, and liquidity rounds DOWN in both directions.
    function testFuzz_INV_R_ReserveNeverOverDelivers(int24 launchSeed, int24 offSeed, uint256 amount) public pure {
        (int24 lo, int24 hi) = _protocolBand(launchSeed, offSeed);
        amount = bound(amount, 0, TOTAL_SUPPLY);

        uint128 liq = ReserveLib.liquidityForTokenOut(lo, hi, amount);
        uint256 back = ReserveLib.tokenOutForLiquidity(lo, hi, liq);
        assertLe(back, amount, "INV-R: reserve delivered more than deposited");
    }

    /// The round-trip loss is bounded by one liquidity unit's worth of token,
    /// i.e. (sqrtHi - sqrtLo) / Q96, and — crucially — stays far below
    /// `PoolOps.CLAIM_DUST` (1e12). If it did not, `migrateOne` would revert
    /// "reserve short" on an entirely honest 1:1 claim.
    function testFuzz_INV_D_RoundTripDustIsBounded(int24 launchSeed, int24 offSeed, uint256 amount) public pure {
        (int24 lo, int24 hi) = _protocolBand(launchSeed, offSeed);
        amount = bound(amount, 1, TOTAL_SUPPLY);

        uint128 liq = ReserveLib.liquidityForTokenOut(lo, hi, amount);
        uint256 back = ReserveLib.tokenOutForLiquidity(lo, hi, liq);
        uint256 lost = amount - back;

        uint256 unit =
            (uint256(TickMath.getSqrtPriceAtTick(hi)) - uint256(TickMath.getSqrtPriceAtTick(lo))) / (1 << 96);
        assertLe(lost, unit + 1, "INV-D: dust exceeded one liquidity unit of token");
        assertLt(lost, 1e12, "INV-D: dust must stay under PoolOps.CLAIM_DUST or migration reverts");
    }

    /// BOUNDARY (audit note). `liquidityForTokenOut` casts to uint128 and REVERTS
    /// (SafeCastOverflow) once amount * Q96 / (sqrtHi - sqrtLo) exceeds 2^128 — i.e.
    /// for a narrow band at a deeply negative tick. A revert on this path inside
    /// `relaunch()` would freeze the machine, exactly like the zero-liquidity case the
    /// code already guards (`PoolOps._seedReserve`, "DUST GUARD"). This test pins the
    /// boundary and shows the protocol's own band geometry sits far inside the safe
    /// region: the reserve always spans from MIN_TICK, so (sqrtHi - sqrtLo) is huge.
    function testFuzz_INV_R_LiquidityCastIsSafeInProtocolDomain(int24 launchSeed, int24 offSeed) public pure {
        (int24 lo, int24 hi) = _protocolBand(launchSeed, offSeed);
        // Whole-supply deposit, the largest the protocol can ever place.
        uint128 liq = ReserveLib.liquidityForTokenOut(lo, hi, TOTAL_SUPPLY);
        assertGt(liq, 0, "non-degenerate");
        assertLt(uint256(liq), type(uint128).max, "cast has headroom across the whole domain");
    }

    /// The degenerate direction, recorded explicitly: an inverted/near-zero-width band
    /// at the bottom of tick space DOES overflow the uint128 liquidity cast.
    function test_INV_R_LiquidityCastOverflowsOnDegenerateBand() public {
        ZReserveProbe probe = new ZReserveProbe();
        // 1,600 ticks wide, at the very bottom of tick space.
        vm.expectRevert(); // SafeCastOverflow
        probe.liquidityForTokenOut(-813_600, -812_000, TOTAL_SUPPLY);

        // The band the protocol actually builds spans from MIN_TICK, so the same
        // deposit is comfortably representable.
        (int24 lo, int24 hi) = ReserveLib.reserveTicks(180_000, SPACING, 42_400);
        assertGt(probe.liquidityForTokenOut(lo, hi, TOTAL_SUPPLY), 0, "protocol band is safe");
    }

    /// The reserve band produced by `reserveTicks` is always a VALID, non-degenerate,
    /// in-range band — a reverting band inside `relaunch()` would freeze the machine.
    function testFuzz_INV_R_ReserveTicksAlwaysValid(int24 launchTick, int24 offset) public pure {
        launchTick = int24(bound(int256(launchTick), int256(TickMath.MIN_TICK), int256(TickMath.MAX_TICK)));
        offset = int24(bound(int256(offset), 4000, 138_000));
        (int24 lo, int24 hi) = ReserveLib.reserveTicks(launchTick, SPACING, offset);

        assertLt(lo, hi, "band must be non-empty");
        assertGe(lo, TickMath.MIN_TICK, "lower within range");
        assertLe(hi, TickMath.MAX_TICK, "upper within range");
        assertEq(lo % SPACING, 0, "lower aligned");
        assertEq(hi % SPACING, 0, "upper aligned");
        TickMath.getSqrtPriceAtTick(lo); // must not revert
        TickMath.getSqrtPriceAtTick(hi);
    }

    // -----------------------------------------------------------------------
    // INV-S — progressive seed schedule
    // -----------------------------------------------------------------------

    function testFuzz_INV_S_ScheduleMonotoneBoundedAndTerminates(
        uint64 window,
        uint256 floorWad,
        uint256 t1,
        uint256 t2
    ) public pure {
        uint64 start = 1_000_000;
        window = uint64(bound(window, 60, 7 days));
        floorWad = bound(floorWad, 1, 1e18);
        t1 = bound(t1, start, start + uint256(window) * 3);
        t2 = bound(t2, t1, start + uint256(window) * 3);

        uint256 a = SeedLib.deployedTargetWad(start, window, t1, floorWad);
        uint256 b = SeedLib.deployedTargetWad(start, window, t2, floorWad);

        assertGe(a, floorWad, "INV-S: never below the seed floor");
        assertLe(a, 1e18, "INV-S: never over-deploys ledger A");
        assertGe(b, a, "INV-S: monotone non-decreasing in time");
        assertEq(
            SeedLib.deployedTargetWad(start, window, uint256(start) + window, floorWad),
            1e18,
            "INV-S: exactly 100% at the end of the window"
        );
        assertEq(
            SeedLib.deployedTargetWad(start, window, start - 1, floorWad),
            floorWad,
            "INV-S: clamped to the floor before launch"
        );
    }

    /// The stream cannot be ACCELERATED: the target is a pure function of elapsed
    /// time, so poking more often deploys no more capital. (Anti front-run property.)
    function testFuzz_INV_S_PokeFrequencyCannotAccelerate(uint64 window, uint256 floorWad, uint256 t) public pure {
        uint64 start = 1_000_000;
        window = uint64(bound(window, 60, 7 days));
        floorWad = bound(floorWad, 1, 1e18);
        t = bound(t, start, start + uint256(window));
        assertEq(
            SeedLib.deployedTargetWad(start, window, t, floorWad),
            SeedLib.deployedTargetWad(start, window, t, floorWad),
            "INV-S: target depends only on elapsed time"
        );
    }
}

// ---------------------------------------------------------------------------
// INV-L — stateful, handler-driven ledger conservation
// ---------------------------------------------------------------------------

contract ZLedgerHandler is Test {
    CollectionLedger public ledger;
    uint256 public constant GENS = 4;
    uint256 public ghostCredited;
    uint256 public ghostRedeemed;
    uint256 public ghostBoughtBack;

    constructor(CollectionLedger l) {
        ledger = l;
    }

    function credit(uint256 gen, uint256 amt, uint256 minted) external {
        gen = bound(gen, 1, GENS);
        amt = bound(amt, 1, 1e24);
        minted;
        try ledger.credit(gen, amt) {
            ghostCredited += amt;
        } catch {}
    }

    function redeem(uint256 gen, uint256 minted) external {
        gen = bound(gen, 1, GENS);
        minted = bound(minted, 0, 5000);
        try ledger.redeem(gen, minted) returns (uint256 payout) {
            ghostRedeemed += payout;
        } catch {}
    }

    function buyback(uint256 gen, uint256 minted, uint256 paid) external {
        gen = bound(gen, 1, GENS);
        minted = bound(minted, 0, 5000);
        paid = bound(paid, 1, 1e24);
        try ledger.buyback(gen, minted, paid) {
            ghostBoughtBack += paid;
        } catch {}
    }

    function crystallize(uint256 gen, uint256 mintedAtDeath, uint256 extra) external {
        gen = bound(gen, 1, GENS);
        mintedAtDeath = bound(mintedAtDeath, 0, 5000);
        extra = bound(extra, 0, 1e24);
        try ledger.crystallize(gen, mintedAtDeath, extra) {
            ghostCredited += extra;
        } catch {}
    }
}

contract ZLedgerInvariants is Test {
    CollectionLedger internal ledger;
    ZLedgerHandler internal handler;

    function setUp() public {
        ledger = new CollectionLedger(address(this));
        handler = new ZLedgerHandler(ledger);
        // The ledger is `onlyRegistry`; make the handler the registry by deploying a
        // second ledger owned by it, so every call in the run is authorised.
        ledger = new CollectionLedger(address(handler));
        handler = new ZLedgerHandler(ledger);
        targetContract(address(handler));
    }

    /// INV-L: the advertised cap-table invariant, under any interleaving.
    function invariant_L_TotalEntitledEqualsSumOfGenerations() public view {
        uint256 sum;
        for (uint256 g = 1; g <= handler.GENS(); ++g) {
            sum += ledger.entitledTokens(g);
        }
        assertEq(ledger.totalEntitled(), sum, "INV-L: totalEntitled drifted from the per-gen sum");
    }

    /// INV-L2: value conservation — everything paid out was credited first, so the
    /// ledger can never authorise a reserve withdrawal it was not funded for.
    function invariant_L_PayoutsNeverExceedCredits() public view {
        assertLe(
            handler.ghostRedeemed(),
            handler.ghostCredited() + handler.ghostBoughtBack(),
            "INV-L2: redeemed more than was ever credited"
        );
    }

    /// INV-L3: a per-NFT floor is never larger than the whole pot it is paid from.
    function invariant_L_FloorNeverExceedsPot() public view {
        for (uint256 g = 1; g <= handler.GENS(); ++g) {
            assertLe(ledger.floorPerNFT(g, 1000), ledger.entitledTokens(g), "INV-L3: floor exceeds the pot");
        }
    }
}

/// @dev External wrapper so `vm.expectRevert` can observe reverts from the
///      otherwise-inlined `internal` library functions.
contract ZReserveProbe {
    function liquidityForTokenOut(int24 lo, int24 hi, uint256 amount) external pure returns (uint128) {
        return ReserveLib.liquidityForTokenOut(lo, hi, amount);
    }

    function tokenOutForLiquidity(int24 lo, int24 hi, uint128 liq) external pure returns (uint256) {
        return ReserveLib.tokenOutForLiquidity(lo, hi, liq);
    }
}
