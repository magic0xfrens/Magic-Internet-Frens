// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ZAuditBase, ZMockMiFrens} from "./ZAuditBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

/**
 * FINDING Z-02 (High) — the liquidation TWAP oracle is not sampled while the book
 * is empty, so the first position opened after a quiet period is marked against a
 * price from BEFORE the quiet period and is born instantly liquidatable.
 *
 * PerpEngine._doSweep (the ONLY thing an ordinary swap calls):
 *     if (_liqReentry) return;
 *     uint256 len = _openIds.length;
 *     if (len == 0) return;        // <-- returns BEFORE _pokeFunding()
 *     _pokeFunding();              // <-- the only keeperless oracle write
 *
 * With zero open positions no swap ever reaches `_pokeFunding`, so `lastTick`
 * stays frozen at whatever it was when the book last emptied. `_writeObs` then
 * integrates the ENTIRE elapsed interval at that frozen tick
 * (`tickCumulative += lastTick * dt`), and `twapTick()` extrapolates the same
 * frozen tick over the whole lookback — so `markSqrtPriceX96()` returns the OLD
 * price no matter how far spot has moved.
 *
 * This is the same class of bug the contract documents as fixed for the
 * intra-transaction case (the `_writeObs` "always refresh lastTick" comment); the
 * inter-period case is still open because the oracle simply is not sampled.
 *
 * Impact: the opener paid the 6.9% liquidation penalty on a position that was fully
 * collateralised at spot. The mirror case (mark stale-favourable) left a genuinely
 * insolvent position un-liquidatable until the mark converged — bad debt charged to
 * the ETH PLV.
 *
 * STATUS: FIXED. `_pokeFunding()` now runs BEFORE the empty-book early return, so
 * every served swap samples the oracle whether or not anything is open. The suite
 * below is the regression: it replays the exploit and asserts the mark now tracks
 * spot and the position survives, and keeps the keeper-poke control for contrast.
 */
contract Z02_PerpStaleMark is ZAuditBase {
    PerpEngine internal engine;
    ZMockMiFrens internal frens;
    address internal token;
    PoolId internal pid;

    address internal constant DIVIDEND = address(0xD11D);
    address internal constant TREASURY = address(0x77E5);

    function setUp() public {
        _bootstrap(1 ether);
        if (!active) return;

        (token, pid) = registry.summon{value: 20 ether}();

        frens = new ZMockMiFrens();
        engine = new PerpEngine(pm, address(hook), address(registry), address(frens), DIVIDEND, TREASURY, address(this));
        hook.setPerpEngine(address(engine));
        engine.fundPlv{value: 5 ether}();
        // warmup 60s (>= MIN_TWAP); everything else at defaults.
        engine.setRisk(60, 3, 1500, 500, 3000, 100);
        // Keep the pool "alive" for the whole test so opens are never gated on death.
        hook.setDeathThreshold(0);

        vm.roll(block.number + hook.snipeWindowBlocks() + 1);
        vm.warp(block.timestamp + 120); // clear the open warmup
    }

    /// REGRESSION: with an empty book the oracle is still sampled by the swap itself,
    /// so a ~2x spot move is reflected in the mark with no keeper involved.
    function test_FIXED_MarkTracksSpotWithAnEmptyBook() public {
        if (!active) return;

        uint160 markBefore = engine.markSqrtPriceX96();
        uint160 spotBefore = _spotSqrt(pid);
        assertApproxEqRel(uint256(markBefore), uint256(spotBefore), 0.01e18, "mark starts at spot");

        // A large organic buy. No perp position is open, so afterSwap's sweep
        // returns before _pokeFunding and the oracle is NEVER written.
        _buyExactIn(8 ether);

        // Time passes with no perp activity (the "keeperless" claim).
        vm.roll(block.number + 300);
        vm.warp(block.timestamp + 1 hours);

        uint160 markAfter = engine.markSqrtPriceX96();
        uint160 spotAfter = _spotSqrt(pid);

        emit log_named_uint("spot sqrtP before", spotBefore);
        emit log_named_uint("spot sqrtP after ", spotAfter);
        emit log_named_uint("MARK sqrtP after ", markAfter);

        assertLt(spotAfter, spotBefore, "spot moved (token appreciated)");
        // The mark now FOLLOWS spot: the swap's own sweep sampled the oracle, so the
        // quiet hour was integrated at the tick that was genuinely in force.
        assertApproxEqRel(uint256(markAfter), uint256(spotAfter), 0.01e18, "FIXED: mark tracks spot");
        assertLt(uint256(markAfter), uint256(markBefore), "FIXED: mark is no longer frozen");
    }

    /// REGRESSION: a fully-collateralised long opened after the same quiet period used
    /// to be liquidated inside its OWN opening transaction. It now survives.
    function test_FIXED_PositionSurvivesOpenAfterQuietPeriod() public {
        if (!active) return;

        _buyExactIn(8 ether);
        vm.roll(block.number + 300);
        vm.warp(block.timestamp + 1 hours);

        uint256 id = engine.openLong{value: 0.1 ether}(2, 0, 0);
        (address trader,,,,,,,) = engine.positions(id);

        assertEq(trader, address(this), "FIXED: position survives its own open tx");
        assertEq(engine.openCount(), 1, "FIXED: book holds the position");
        assertFalse(engine.isLiquidatable(id), "FIXED: healthy at a correctly-sampled mark");
    }

    /// CONTROL / ROOT CAUSE. Identical scenario, except the permissionless
    /// `poke()` keeps the oracle fresh. The position now survives — proving the
    /// defect is precisely the missing oracle write on the empty-book path and
    /// that the design is not in fact keeperless.
    function test_SAFE_WithKeeperPoke_PositionSurvives() public {
        if (!active) return;

        _buyExactIn(8 ether);
        // A keeper samples the oracle across the quiet window.
        // NOTE (harness): `vm.roll` re-snaps `block.timestamp` to the forked block's
        // own timestamp, so it MUST NOT be interleaved with `vm.warp` when elapsed
        // time is what is under test. Only time matters here, so we warp alone.
        uint256 t = block.timestamp;
        for (uint256 i = 0; i < 24; ++i) {
            t += 150;
            vm.warp(t);
            engine.poke();
        }

        uint256 id = engine.openLong{value: 0.1 ether}(2, 0, 0);
        (address trader,,,,,,,) = engine.positions(id);

        assertEq(trader, address(this), "control: position survives when the mark is fresh");
        assertEq(engine.openCount(), 1, "control: book holds the position");
        assertFalse(engine.isLiquidatable(id), "control: healthy at a fresh mark");
    }
}
