// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SurtaxLib} from "../../cauldron/SurtaxLib.sol";

/**
 * X8b — the anti-sniper surtax's jitter is BLOCK-SHOPPABLE.
 *
 * SurtaxLib.sol:83-89 seeds the jitter with
 *   keccak256(blockhash(block.number - 1), poolId, block.number, block.prevrandao)
 * and claims the previous blockhash is "known to everyone during block N, but not
 * to a sniper choosing which block to submit into".
 *
 * Every one of those four operands is fixed BEFORE block N is built:
 * blockhash(N-1) seals with block N-1, poolId is static, N is the next number,
 * and `prevrandao` is the constant 1 on Arbitrum/Orbit (the library's own
 * comment says so). So the surtax for the next block is computable at the head
 * and the sniper submits only into blocks where the jitter is small.
 */
contract X8bSurtaxJitterBlockShoppable is Test {
    PoolId constant ID = PoolId.wrap(bytes32(uint256(0xA11CE)));
    uint256 constant MAX_BPS = 1_000;
    uint256 constant WINDOW  = 200;

    /// The value an observer at the HEAD of block n-1 computes for block n, from
    /// prior-block data only. Mirrors SurtaxLib.defaultSurtaxBps arithmetic.
    function _predict(bytes32 prevHash, uint256 n, bytes32 rand, uint256 start)
        internal pure returns (uint256)
    {
        uint256 elapsed = n - start;
        if (elapsed >= WINDOW) return 0;
        uint256 remaining = WINDOW - elapsed;
        uint256 decayed = (MAX_BPS * remaining) / WINDOW;
        uint256 rnd = uint256(keccak256(abi.encodePacked(prevHash, PoolId.unwrap(ID), n, rand))) % (MAX_BPS + 1);
        uint256 total = decayed + (rnd * remaining) / WINDOW;
        return total > MAX_BPS ? MAX_BPS : total;
    }

    function _scan(uint256 start, uint256 first, uint256 count)
        internal
        returns (uint256 mismatches, uint256 lo, uint256 hi, uint256 loBlock)
    {
        lo = type(uint256).max;
        for (uint256 i; i < count; ++i) {
            uint256 n = first + i;
            vm.roll(n);
            // prior-block data only: sealed before block n was built
            uint256 predicted = _predict(blockhash(n - 1), n, bytes32(uint256(1)), start);
            uint256 live = SurtaxLib.defaultSurtaxBps(ID, MAX_BPS, WINDOW, start);
            if (predicted != live) ++mismatches;
            if (live < lo) { lo = live; loBlock = n; }
            if (live > hi) hi = live;
        }
    }

    function test_TheSurtaxForTheNextBlockIsKnownBeforeSubmittingIntoIt() public {
        // Emulate Arbitrum/Orbit, where `prevrandao` is the constant 1.
        vm.prevrandao(bytes32(uint256(1)));

        uint256 start = 1_000;          // the block the pool was initialised at
        uint256 first = 1_010;          // 64 candidate blocks, all inside the window
        (uint256 mismatches, uint256 lo, uint256 hi, uint256 loBlock) = _scan(start, first, 64);

        // The deterministic floor the design publishes: decay with zero jitter,
        // measured at the cheapest block the sniper picked.
        uint256 remaining = WINDOW - (loBlock - start);
        uint256 decayedAtLo = (MAX_BPS * remaining) / WINDOW;

        emit log_named_uint("blocks scanned", 64);
        emit log_named_uint("cheapest surtax bps", lo);
        emit log_named_uint("dearest surtax bps", hi);
        emit log_named_uint("published decay at the cheapest block", decayedAtLo);

        assertEq(mismatches, 0, "every block's surtax was predicted from prior-block data alone");
        assertLt(lo, hi, "the surtax varies across candidate blocks, so there is a cheap one to pick");
        assertLt(lo, (hi * 9) / 10, "and the cheapest is materially below the dearest");
        assertGe(lo, decayedAtLo, "jitter only ever adds, so the decay is the floor the sniper reaches");
    }
}
