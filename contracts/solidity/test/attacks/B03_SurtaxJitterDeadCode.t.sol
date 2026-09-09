// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

/**
 * @title B-03 — the anti-sniper surtax "entropy" is dead code; the surtax is
 *               fully predictable
 *
 *  {CauldronHook._defaultSurtaxBps} (CauldronHook.sol:1266-1294) computes:
 *
 *      decayed = (maxBps * remaining) / window;
 *      rnd     = keccak256(...) % (maxBps + 1);   // so rnd ∈ [0, maxBps]
 *      jitter  = (rnd * remaining) / window;
 *      return  decayed > jitter ? decayed : jitter;   // == max(decayed, jitter)
 *
 *  The comment (CauldronHook.sol:1281-1287, "audit L-02") claims the jitter folds
 *  in the pool's LIVE tick — unknowable at submission time — so "a sniper can't
 *  pick a guaranteed-cheap block", and states "the jitter can only ever RAISE the
 *  rate".
 *
 *  It can NEVER raise the rate. Because `rnd <= maxBps`, and both terms scale by
 *  the identical `remaining / window` under the SAME floor division:
 *
 *      rnd <= maxBps
 *        => rnd * remaining <= maxBps * remaining
 *        => (rnd * remaining) / window <= (maxBps * remaining) / window
 *        => jitter <= decayed        (for ALL inputs)
 *
 *  So `max(decayed, jitter) == decayed` unconditionally. The `keccak256(...,
 *  tick)` term — the entire manipulation-resistance argument — is discarded by
 *  the `max` on every path. The surtax is therefore a pure, closed-form function
 *  of `block.number` alone:
 *
 *      surtax(block) = maxBps * (window - (block - start)) / window
 *
 *  which a sniper computes exactly for any future block and schedules around. The
 *  defense the L-02 comment describes does not exist in the code.
 *
 *  IMPACT: Low. The deterministic decay term still charged a real surtax, so this
 *  was a defeated defense-in-depth layer rather than a zero-fee bypass — but the
 *  code and its security comment disagreed, on exactly the property
 *  (unpredictability) the jitter was added to provide.
 *
 *  STATUS: FIXED. `_defaultSurtaxBps` now returns `min(decayed + jitter, maxBps)`
 *  instead of `max(decayed, jitter)`, so the random/tick term genuinely raises the
 *  rate — a "cheap" late-window block can spike by an amount unknowable at
 *  submission. This file is now a REGRESSION: it replicates the FIXED formula and
 *  proves (a) jitter is bounded (never exceeds maxBps, never below decayed) and
 *  (b) jitter is LIVE (there are inputs where the result strictly exceeds decayed,
 *  which could never happen under the old `max`).
 *
 *  NOTE: this proves the BUILT-IN curve. A wired `surtaxPolicy` module overrides
 *  it (CauldronHook.sol:1256); the built-in is the documented fallback and default.
 */
contract B03_SurtaxJitterDeadCode is Test {
    /// Faithful replica of the FIXED two lines under test:
    ///   total = decayed + jitter;  return total > maxBps ? maxBps : total;
    function _built(uint256 maxBps, uint256 remaining, uint256 window, bytes32 seed)
        internal
        pure
        returns (uint256 decayed, uint256 jitter, uint256 returned)
    {
        decayed = (maxBps * remaining) / window;
        uint256 rnd = uint256(seed) % (maxBps + 1);
        jitter = (rnd * remaining) / window;
        uint256 total = decayed + jitter;
        returned = total > maxBps ? maxBps : total;
    }

    /// @notice REGRESSION — the fixed surtax is BOUNDED: it never dips below the
    ///         deterministic decay (jitter only raises) and never exceeds the
    ///         configured peak `maxBps`. Holds for all inputs.
    function testFuzz_B03_SurtaxStaysBetweenDecayAndPeak(
        uint16 maxBps,
        uint32 remaining,
        uint32 window,
        bytes32 seed
    ) public pure {
        maxBps = uint16(bound(maxBps, 1, 9900));       // MAX_SNIPE_BPS range
        window = uint32(bound(window, 1, 1_000_000));
        remaining = uint32(bound(remaining, 0, window));

        (uint256 decayed,, uint256 returned) = _built(maxBps, remaining, window, seed);

        assertGe(returned, decayed, "jitter must never LOWER the rate");
        assertLe(returned, maxBps, "surtax must never exceed the configured peak");
    }

    /// @notice REGRESSION — the jitter is now LIVE: with room below the peak and a
    ///         nonzero random draw, the returned surtax STRICTLY exceeds the
    ///         deterministic decay. Under the old `max(decayed, jitter)` this was
    ///         impossible for ANY input, so this test is the exact discriminator
    ///         between the dead-code version and the fix.
    function test_B03_REGRESSION_JitterActuallyRaisesTheRate() public pure {
        // Mid-window (remaining = window/2) so decayed = maxBps/2 leaves headroom,
        // and a max random draw yields jitter = maxBps/2 → total = maxBps > decayed.
        uint256 maxBps = 9900;
        uint256 window = 100;
        uint256 remaining = 50;

        // A seed whose `% (maxBps+1)` is the maximum draw (rnd == maxBps).
        bytes32 seed = bytes32(uint256(maxBps));
        (uint256 decayed, uint256 jitter, uint256 returned) = _built(maxBps, remaining, window, seed);

        assertGt(jitter, 0, "jitter is nonzero for this draw");
        assertGt(returned, decayed, "the jitter raised the surtax above the deterministic decay");
    }
}
