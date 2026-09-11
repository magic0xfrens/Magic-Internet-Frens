// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {ISurtaxPolicy} from "./IPolicies.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

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
    using StateLibrary for IPoolManager;

    /**
     * @notice The decaying anti-sniper surtax for `id`, in bps.
     * @param start  The block `id` was initialised at (0 = unknown → no surtax).
     * @param maxBps The configured peak. 0 disables the surtax.
     * @param window How many blocks the surtax decays across. 0 disables it.
     */
    function defaultSurtaxBps(
        IPoolManager poolManager,
        PoolId id,
        uint256 maxBps,
        uint256 window,
        uint256 start
    ) external view returns (uint256) {
        if (maxBps == 0 || window == 0 || start == 0) return 0;
        uint256 elapsed = block.number - start;
        if (elapsed >= window) return 0;

        uint256 remaining = window - elapsed;
        // Deterministic decay: high at launch, fading to 0 across the window.
        uint256 decayed = (maxBps * remaining) / window;
        // Per-block jitter, also fading with the window, so late-window blocks can
        // still randomly spike — a sniper can't pick a guaranteed-cheap block.
        //
        // ENTROPY (audit L-02). `prevrandao` is useless here: it is a constant (1)
        // on Arbitrum/Orbit. The previous blockhash varies per block but is KNOWN to
        // everyone during block N, so a sniper submitting into N could compute the
        // exact surtax and skip expensive blocks. We therefore also fold in the
        // pool's LIVE tick, which moves with the very trade being priced and is not
        // knowable at submission time.
        //
        // JITTER MUST *ADD*, NOT `max` (red-team B-03). The previous form returned
        // `max(decayed, jitter)`, but `rnd ∈ [0, maxBps]` and both terms carry the
        // identical `remaining/window` factor under the same floor division, so
        // `jitter <= decayed` for ALL inputs and the `max` was ALWAYS `decayed` —
        // the tick term was dead code and the surtax was fully predictable from the
        // block number alone, defeating the entire point of this branch. Adding the
        // jitter on TOP of the decay makes it genuinely raise the rate (as the
        // comment always claimed), so a "cheap" late-window block can still spike by
        // an amount unknowable at submission. Clamped to `maxBps` so the surtax can
        // never exceed its configured peak; `snipeSurtaxBps` clamps again to
        // MAX_SNIPE_BPS, and `_takeEthFee` clamps the COMBINED rate so a trade always
        // leaves >=1% to execute.
        (, int24 tick,,) = poolManager.getSlot0(id);
        uint256 rnd = uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), PoolId.unwrap(id), block.number, tick))
        ) % (maxBps + 1);
        uint256 jitter = (rnd * remaining) / window;
        uint256 total = decayed + jitter;
        return total > maxBps ? maxBps : total;
    }
}
