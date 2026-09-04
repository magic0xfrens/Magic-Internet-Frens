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
        toFloor = (vault != address(0) && floorBps > 0) ? (rem * floorBps) / BPS : 0;
        toRelaunch = rem - toFloor; // remainder — guarantees the sum == feeAmount
    }
}
