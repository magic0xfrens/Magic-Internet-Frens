// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFeeRouter} from "./IPolicies.sol";

/**
 * @title DefaultFeeRouter
 * @notice Reference {IFeeRouter} that reproduces the hook's BUILT-IN ETH fee split:
 *         guildBps off the top → the genesis dividend, then floorBps of the
 *         remainder → the floor vault, and whatever is left → the relaunch reserve.
 *
 *  Pure math, holds no funds, no owner, immutable. It exists so a v2 fee STRUCTURE
 *  can be A/B'd by pointing `hook.setFeeRouter` at a new router — this one is the
 *  drop-in baseline. Because the router only returns AMOUNTS (the hook does the
 *  sends), swapping it never exposes a fund-flow rug surface.
 */
contract DefaultFeeRouter is IFeeRouter {
    uint256 private constant BPS = 10_000;

    /// @inheritdoc IFeeRouter
    function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256 floorBps)
        external
        pure
        returns (uint256 toGuild, uint256 toFloor, uint256 toRelaunch)
    {
        toGuild = (guild != address(0) && guildBps > 0) ? (feeAmount * guildBps) / BPS : 0;
        uint256 rem = feeAmount - toGuild;
        //  ── NO VAULT TEST (red-team Z-11) ───────────────────────────────────
        //  `CauldronHook.sol:1383` — the built-in split this router exists to
        //  reproduce — does NOT test `vault`, because under the shipped FULL-UNIFY
        //  configuration the floor share is not an ETH transfer at all: both
        //  collection-deployment paths call `hook.setVault(address(0))`
        //  (CauldronRegistry.sol:1189, :1213) and the hook turns `wantFloor` into
        //  token BUY PRESSURE via the legacy buffer (CauldronHook.sol:1428-1450).
        //
        //  With the extra `vault != address(0)` condition this router returned
        //  `toFloor == 0` on EVERY swap of the live configuration, so the whole
        //  buy-pressure block was skipped and the collection's token floor share
        //  was silently re-routed into the relaunch reserve. The hook's own
        //  mismatch detector cannot see it: the three amounts still sum to
        //  `feeAmount`, so `routed = true` (CauldronHook.sol:1373) and the
        //  built-in split is never consulted.
        //
        //  `vault` stays in the signature — it is part of {IFeeRouter} and a v2
        //  router may legitimately want it — it just must not gate the share.
        toFloor = floorBps > 0 ? (rem * floorBps) / BPS : 0;
        toRelaunch = rem - toFloor; // remainder — guarantees the sum == feeAmount
    }
}
