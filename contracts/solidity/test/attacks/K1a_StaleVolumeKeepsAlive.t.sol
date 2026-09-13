// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FinalAuditBase} from "../final/FinalAuditBase.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/**
 * K1a — REGRESSION. The 24h volume window must really be a 24h window.
 *
 *  `CauldronHook._recordVolume` only zeroes the buckets it STEPS OVER, and
 *  `getVolume24h` only zeroes everything when
 *  `block.timestamp > _lastUpdateTs[id] + SECONDS_PER_DAY`. A dust swap landing
 *  in the SAME hour-of-day bucket exactly <= 86400s after the previous one
 *  advances `_lastUpdateTs` while stepping over ZERO buckets — so an ancient
 *  bucket's volume is never cleared and keeps counting toward `isDead`.
 *
 *  This test drives the PRODUCTION hook bytecode with the test contract standing
 *  in as the PoolManager (BaseHook's `onlyPoolManager`), so every line executed
 *  is the real one.
 */
contract K1a_StaleVolumeKeepsAlive is FinalAuditBase {
    using PoolIdLibrary for PoolKey;

    PoolKey internal key;
    PoolId internal pid;

    address internal constant TOKEN = address(0xf00000000000000000000000000000000000BeEF);

    function setUp() public {
        // The TEST is the PoolManager, so it can invoke the hook callbacks
        // exactly as v4 would.
        _deployOffchain(address(this));

        key = PoolKey({
            currency0: Currency.wrap(address(0)), // native quote
            currency1: Currency.wrap(TOKEN),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        pid = key.toId();

        // Adopt the pool the way the registry does.
        hook.afterInitialize(address(registry), key, uint160(1 << 96), int24(0));
    }

    /// @dev One exact-input BUY of `quoteIn` wei. Quote is currency0 and the swap
    ///      is zeroForOne + exactInput, so `_afterSwap` records volume and then
    ///      early-returns before any fee take (unspecified leg is currency1).
    function _swapOn(PoolKey memory k, uint256 quoteIn) internal {
        SwapParams memory p = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(quoteIn),
            sqrtPriceLimitX96: 0
        });
        BalanceDelta d = toBalanceDelta(-int128(int256(quoteIn)), int128(int256(quoteIn)));
        hook.afterSwap(address(0xBEEF), k, p, d, "");
    }

    /// @dev Positive control on a SEPARATE pool (no snapshots): with no trading
    ///      at all, the window really does expire and the generation dies.
    function _controlDiesAfterOneDay() internal returns (bool dead) {
        PoolKey memory k2 = key;
        k2.fee = 100;
        PoolId p2 = k2.toId();
        hook.afterInitialize(address(registry), k2, uint160(1 << 96), int24(0));
        SwapParams memory p = SwapParams({
            zeroForOne: true, amountSpecified: -int256(10 ether), sqrtPriceLimitX96: 0
        });
        BalanceDelta d = toBalanceDelta(-int128(int256(10 ether)), int128(int256(10 ether)));
        hook.afterSwap(address(0xBEEF), k2, p, d, "");
        bool aliveNow = !hook.isDead(p2);
        require(aliveNow, "control: should be alive right after a 10 ETH swap");
        uint256 tc = vm.getBlockTimestamp();
        vm.warp(tc + 86_401);
        dead = hook.isDead(p2);
        vm.warp(tc);
    }

    /// @dev The attack: one real swap, then a dust ping once per day placed so
    ///      that the hour-of-day bucket index is UNCHANGED (`stride` of 86400
    ///      or 86399 seconds), which used to step over ZERO buckets and keep
    ///      the ancient volume alive forever.
    function _attackKeepsAlive(PoolKey memory k, uint256 days_, uint256 stride)
        internal
        returns (bool aliveAfter, uint256 volAfter, uint256 elapsed)
    {
        PoolId p = k.toId();
        // `vm.getBlockTimestamp()`, not `block.timestamp`: solc/viaIR sinks the
        // TIMESTAMP opcode to its use site, which reads it AFTER the warps.
        uint256 t0 = vm.getBlockTimestamp();
        uint256 t = t0;
        _swapOn(k, 10 ether);
        require(!hook.isDead(p), "rig: alive right after the 10 ETH swap");
        for (uint256 i = 0; i < days_; ++i) {
            t += stride;
            vm.warp(t);
            _swapOn(k, 1); // one wei of "volume"
        }
        elapsed = t - t0;
        volAfter = hook.getVolume24h(p);
        aliveAfter = !hook.isDead(p);
    }

    function _pool(uint24 fee) internal returns (PoolKey memory k) {
        k = key;
        k.fee = fee;
        hook.afterInitialize(address(registry), k, uint160(1 << 96), int24(0));
    }

    /// @dev The three cadences, all driven from the SAME starting second so the
    ///      only variable is the stride / the second-of-hour budget.
    function test_K1a_staleBucketBlocksRelaunchForever() public {
        // Second 1800 of an hour, so the bucket maths is easy to follow.
        uint256 base = 1_800_000_000 - (1_800_000_000 % 3600) + 1800;
        vm.warp(base);

        assertEq(hook.deathThreshold(), 1 ether, "rig: threshold");

        // 0. The window genuinely expires when nobody trades.
        assertTrue(_controlDiesAfterOneDay(), "control: dead after 24h of silence");

        // 1. Stride of EXACTLY 86400s: same bucket, delta == SECONDS_PER_DAY.
        vm.warp(base);
        PoolKey memory kA = _pool(3001);
        (bool aliveA, uint256 volA, uint256 elapsedA) = _attackKeepsAlive(kA, 30, 86_400);
        emit log_named_uint("A_elapsed_seconds", elapsedA);
        emit log_named_uint("A_volume24h_reported", volA);
        assertEq(elapsedA, 30 * 86_400, "A: 30 days elapsed");
        assertLt(volA, 1 ether, "A: 30-day-old volume must NOT be counted");
        assertTrue(!aliveA, "A: isDead() must be true after 30 days of dust");

        // 2. Stride of 86399s: still the same bucket index (second-of-hour just
        //    walks backwards by one), so the old same-bucket skip applied here
        //    too. 1800 seconds of budget, 30 days, never exhausted.
        vm.warp(base);
        PoolKey memory kB = _pool(500);
        (bool aliveB, uint256 volB,) = _attackKeepsAlive(kB, 30, 86_399);
        emit log_named_uint("B_volume24h_reported", volB);
        assertLt(volB, 1 ether, "B: 86399s cadence must not pin stale volume");
        assertTrue(!aliveB, "B: isDead() must be true after 30 days of dust");

        // 3. Same 86399s stride but starting at second 20 of the hour, so the
        //    budget runs out mid-run and the ring crosses the 23-step branch.
        vm.warp(base - 1780); // second 20 of the hour
        PoolKey memory kC = _pool(10_000);
        (bool aliveC, uint256 volC,) = _attackKeepsAlive(kC, 30, 86_399);
        emit log_named_uint("C_volume24h_reported", volC);
        assertLt(volC, 1 ether, "C: drifting cadence must not pin stale volume");
        assertTrue(!aliveC, "C: isDead() must be true after 30 days of dust");

        // 4. NOT over-corrected: real volume inside the window still counts and
        //    still holds the generation open.
        _swapOn(kC, 10 ether);
        assertGe(hook.getVolume24h(kC.toId()), 10 ether, "live volume must count");
        assertTrue(!hook.isDead(kC.toId()), "a pool that just traded 10 ETH is alive");
    }
}
