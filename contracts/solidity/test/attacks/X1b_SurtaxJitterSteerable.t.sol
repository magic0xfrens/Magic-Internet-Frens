// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";

/// @dev Stub PoolManager exposing a SETTABLE slot0 through `extsload`, which is
///      how {StateLibrary.getSlot0} — the call `_defaultSurtaxBps` makes — reads
///      the live tick. Everything else the hook needs here is inert.
contract X1bPoolManagerStub {
    uint160 public sqrtP = uint160(1) << 96;
    int24 public tick;

    function setTick(int24 t) external { tick = t; }

    function extsload(bytes32) external view returns (bytes32) {
        return bytes32(uint256(sqrtP) | (uint256(uint24(tick)) << 160));
    }

    function driveAfterInitialize(address hook_, address sender, PoolKey memory key) external {
        CauldronHook(payable(hook_)).afterInitialize(sender, key, sqrtP, tick);
    }

    receive() external payable {}
}

/**
 * @title X1b — the anti-sniper surtax's only entropy is the swapper's own tick
 *
 *  `CauldronHook._defaultSurtaxBps` (CauldronHook.sol:1376) derives its jitter from
 *      keccak256(blockhash(block.number - 1), id, block.number, tick)
 *  `blockhash(block.number-1)`, `id` and `block.number` are all known to a sniper
 *  at submission time (the comment at :1392 concedes this). `tick` is therefore the
 *  entire unknown — and `tick` is the pool's LIVE tick, which the sniper moves with
 *  a probe swap in the same transaction before the buy that is actually priced.
 *
 *  This test holds the block fixed and varies ONLY the tick, showing the surtax
 *  swinging across the full [decayed, maxBps] band. The minimum reachable value is
 *  the deterministic decay — i.e. the sniper can always grind the jitter away and
 *  restore exactly the predictability the jitter was added to remove.
 */
contract X1bSurtaxJitterSteerable is Test {
    using PoolIdLibrary for PoolKey;

    CauldronHook internal hook;
    CauldronRegistry internal registry;
    X1bPoolManagerStub internal pm;

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    PoolKey internal key;

    function setUp() public {
        pm = new X1bPoolManagerStub();
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");
        registry = new CauldronRegistry(address(pm), address(pm), address(hook), address(this), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0xBEEF)),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
        vm.roll(1_000_000);
        pm.driveAfterInitialize(address(hook), address(registry), key);
    }

    /// @dev Scan ticks the sniper can reach with a probe swap; return the best and
    ///      worst surtax the SAME block can be made to charge.
    function _scan(PoolId id, int24 lo, int24 hi)
        internal
        returns (uint256 minBps, uint256 maxBpsSeen, int24 bestTick)
    {
        minBps = type(uint256).max;
        for (int24 t = lo; t <= hi; t++) {
            pm.setTick(t);
            uint256 b = hook.snipeSurtaxBps(id);
            if (b < minBps) { minBps = b; bestTick = t; }
            if (b > maxBpsSeen) maxBpsSeen = b;
        }
    }

    function test_X1b_surtaxIsGrindableByTheSwappersOwnTick() public {
        PoolId id = key.toId();

        // Mid-window: 10 blocks into the default 30-block anti-sniper window.
        uint256 window = hook.snipeWindowBlocks();
        uint256 maxCfg = hook.snipeMaxBps();
        uint256 elapsed = 10;
        require(elapsed < window, "window");
        vm.roll(1_000_000 + elapsed);
        uint256 remaining = window - elapsed;
        uint256 decayed = (maxCfg * remaining) / window;

        (uint256 minBps, uint256 maxSeen, int24 bestTick) = _scan(id, int24(-2500), int24(2500));

        console2.log("window / maxBps        ", window, maxCfg);
        console2.log("deterministic decay bps", decayed);
        console2.log("min surtax over ticks  ", minBps);
        console2.log("max surtax over ticks  ", maxSeen);
        console2.log("tick that minimises it ", int256(bestTick));

        // REGRESSION: the tick is gone from the seed, so every tick the swapper
        // can reach with a probe swap in its own transaction prices identically.
        assertEq(minBps, maxSeen, "the surtax is the SAME at every reachable tick");
        assertGe(minBps, decayed, "the deterministic decay is still the floor");
        assertLe(maxSeen, maxCfg, "still clamped to the configured peak");
        console2.log("bps a probe swap saves ", maxSeen - minBps);
        assertEq(maxSeen - minBps, 0, "a probe swap buys the sniper nothing");

        // ...and the jitter is still ALIVE: it moves with per-block randomness,
        // which is unknowable when the trade is submitted and cannot be set from
        // inside the transaction.
        //
        // Probe LATE in the window. Mid-window `decayed` is 2/3 of the peak and
        // the jitter reaches the same, so `total` clamps to `maxBps` for roughly
        // half of all seeds — a run of probes can all land on the clamp and say
        // nothing about whether the jitter moved. At 25/30 elapsed the ceiling is
        // 1/3 of the peak, so the clamp cannot bite and every distinct seed shows.
        vm.roll(1_000_000 + 25);
        uint256 base = hook.snipeSurtaxBps(id);
        uint256 moved;
        for (uint256 i = 1; i <= 12; i++) {
            vm.prevrandao(bytes32(i * uint256(0x9E3779B97F4A7C15)));
            if (hook.snipeSurtaxBps(id) != base) { moved = i; break; }
        }
        console2.log("late-window surtax at the base seed ", base);
        console2.log("jitter still varies at prevrandao # ", moved);
        assertLt(base, maxCfg, "premise: late in the window the peak clamp cannot bite");
        assertGt(moved, 0, "jitter is not dead: per-block randomness still moves it");
    }
}
