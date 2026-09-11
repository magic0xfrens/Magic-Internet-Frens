// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/src/types/PoolId.sol";
import {ISurtaxPolicy} from "./IPolicies.sol";

/**
 * @title SurtaxLib
 * @notice The BUILT-IN anti-sniper surtax curve, lifted out of {CauldronHook}.
 *
 *  This is a LINKED library — one `external` function, so Solidity deploys it
 *  separately and reaches it by `staticcall` (the function is `view`). It holds
 *  no state: every input is passed in, so the hook keeps all its storage and
 *  every public getter the indexer reads exactly where it was.
 *
 *  Why it moved: {CauldronHook} sits on the EIP-170 24,576-byte ceiling. The
 *  curve is pure arithmetic over values the hook already has in hand, which
 *  makes it the cheapest thing in the contract to relocate — the call site pays
 *  four stack pushes and a return decode, against a keccak, an `abi.encodePacked`
 *  over four operands, a `getSlot0` and the whole decay/clamp chain.
 *
 *  {CauldronHook.snipeSurtaxBps} still prefers an installed {ISurtaxPolicy}
 *  module and still clamps whatever comes back to `MAX_SNIPE_BPS`; this is only
 *  the fallback it uses when no module is set or the module reverts.
 */
library SurtaxLib {
    /**
     * @notice The decaying anti-sniper surtax for `id`, in bps.
     * @param start  The block `id` was initialised at (0 = unknown → no surtax).
     * @param maxBps The configured peak. 0 disables the surtax.
     * @param window How many blocks the surtax decays across. 0 disables it.
     */
    function surtaxBps(
        address pol,
        PoolId id,
        uint256 start,
        uint256 maxBps,
        uint256 window,
        uint256 hardCap
    ) external view returns (uint256) {
        //  An installed module wins, but it may NOT brick the fee path and it may
        //  NOT exceed the hard cap: a revert falls through to the built-in curve
        //  and the result is clamped either way. Both rules moved here verbatim
        //  from the hook.
        if (pol != address(0)) {
            try ISurtaxPolicy(pol).surtaxBps(id, start, maxBps, window) returns (uint256 b) {
                return b > hardCap ? hardCap : b;
            } catch { /* fall through to the built-in curve */ }
        }
        return defaultSurtaxBps(id, maxBps, window, start);
    }

    /// @notice The built-in decaying surtax, with no policy module in the way.
    function defaultSurtaxBps(PoolId id, uint256 maxBps, uint256 window, uint256 start)
        public
        view
        returns (uint256)
    {
        if (maxBps == 0 || window == 0 || start == 0) return 0;
        uint256 elapsed = block.number - start;
        if (elapsed >= window) return 0;

        uint256 remaining = window - elapsed;
        // Deterministic decay: high at launch, fading to 0 across the window.
        uint256 decayed = (maxBps * remaining) / window;
        // Per-block jitter, also fading with the window, so late-window blocks can
        // still randomly spike — a sniper can't pick a guaranteed-cheap block.
        //
        // ENTROPY. The seed MUST NOT contain anything the caller can move inside
        // its OWN transaction (red-team X1b — Medium). It used to fold in the
        // pool's LIVE tick, read from `getSlot0` in `_beforeSwap`: a value the
        // swapper sets simply by putting a probe swap ahead of its real one in the
        // same tx. Measured 6402 vs 9600 bps in one block against a deterministic
        // decay of 6400 — a probe was worth ~3198 bps of the buy, and the OG-holder
        // dividend ate the difference. The tick is gone.
        //
        // What is left is per-BLOCK, not per-call: the previous blockhash (known to
        // everyone during block N, but not to a sniper choosing which block to
        // submit into) plus `prevrandao`. L-02 noted prevrandao is a constant on
        // Arbitrum/Orbit, so it is an addition, not a replacement — on a chain where
        // it is real it strengthens the seed, and on one where it is not the
        // blockhash term still carries it. Neither can be steered from inside the
        // transaction being priced, which is the property that was missing.
        //
        // JITTER MUST *ADD*, NOT `max` (red-team B-03). The previous form returned
        // `max(decayed, jitter)`, but `rnd ∈ [0, maxBps]` and both terms carry the
        // identical `remaining/window` factor under the same floor division, so
        // `jitter <= decayed` for ALL inputs and the `max` was ALWAYS `decayed` —
        // the jitter term was dead code and the surtax was fully predictable from the
        // block number alone, defeating the entire point of this branch. Adding the
        // jitter on TOP of the decay makes it genuinely raise the rate (as the
        // comment always claimed), so a "cheap" late-window block can still spike by
        // an amount unknowable at submission. Clamped to `maxBps` so the surtax can
        // never exceed its configured peak; `snipeSurtaxBps` clamps again to
        // MAX_SNIPE_BPS, and `_takeEthFee` clamps the COMBINED rate so a trade always
        // leaves >=1% to execute.
        uint256 rnd = uint256(
            keccak256(
                abi.encodePacked(blockhash(block.number - 1), PoolId.unwrap(id), block.number, block.prevrandao)
            )
        ) % (maxBps + 1);
        uint256 jitter = (rnd * remaining) / window;
        uint256 total = decayed + jitter;
        return total > maxBps ? maxBps : total;
    }
}
