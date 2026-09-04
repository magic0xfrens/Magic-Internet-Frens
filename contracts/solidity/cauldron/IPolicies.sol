// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/src/types/PoolId.sol";

/**
 * Pluggable POLICY modules for the CauldronHook.
 *
 *  Each is a pure/view rule that returns a NUMBER — never custodies or moves
 *  funds. The hook keeps a built-in default for each and delegates to the module
 *  only when one is set (owner/registry-gated, timelocked on mainnet). A reverting
 *  module always falls back to the built-in rule, so it can never brick a swap or
 *  a relaunch. This is how launch/economic RULES are upgraded WITHOUT an
 *  upgradeable proxy on the money contracts — the fund flows stay immutable, only
 *  the policy math is swappable.
 */

/// @notice Anti-sniper launch surtax (bps) for a pool at the current block.
interface ISurtaxPolicy {
    /// @param id           the pool.
    /// @param initBlock    the block the pool was initialized (launch anchor).
    /// @param maxBps       hook's configured peak surtax.
    /// @param windowBlocks hook's configured surtax window length.
    /// @return bps         surtax in basis points (0..maxBps), charged ON TOP of base.
    function surtaxBps(PoolId id, uint256 initBlock, uint256 maxBps, uint256 windowBlocks)
        external
        view
        returns (uint256 bps);
}

/// @notice Gacha win-probability (bps) for a play of a given ETH size.
interface IOddsPolicy {
    /// @param playWei          ETH notional of the play.
    /// @param maxBps           hook's configured max odds from bet size.
    /// @param fullVolumeWei    play size at which odds reach maxBps.
    /// @return bps             win chance in basis points (0..maxBps).
    function oddsBps(uint256 playWei, uint256 maxBps, uint256 fullVolumeWei)
        external
        view
        returns (uint256 bps);
}

/// @notice Volume-credit cost of the NFT at 0-indexed curve position k.
interface ICurvePolicy {
    /// @param k        curve position (0 = first mint of the brew).
    /// @param base     hook's configured base cost (volumePerNFT).
    /// @param step     hook's configured per-position step (nftPriceStep).
    /// @return cost    credit cost to forge the k-th NFT.
    function priceAt(uint256 k, uint256 base, uint256 step)
        external
        view
        returns (uint256 cost);
}

/// @notice ETH fee-split STRUCTURE. Returns how a collected ETH fee divides across
///         the sinks; the HOOK does the actual sends (custody stays immutable in
///         the hook → this can be swapped WITHOUT ever exposing a fund-flow rug
///         surface). The three amounts MUST sum to exactly `feeAmount`; the hook
///         verifies this and falls back to its built-in split on any mismatch or
///         revert, so a bad router can never brick a swap or misroute funds.
interface IFeeRouter {
    /// @param feeAmount  total ETH fee to divide.
    /// @param guild      genesis-dividend sink (0 = none).
    /// @param vault      active brew's floor vault (0 = none).
    /// @param guildBps   hook's configured guild share.
    /// @param floorBps   hook's configured floor share (of the post-guild remainder).
    /// @return toGuild     ETH to the genesis dividend.
    /// @return toFloor     ETH to the floor vault.
    /// @return toRelaunch  ETH kept as the relaunch reserve.
    function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256 floorBps)
        external
        view
        returns (uint256 toGuild, uint256 toFloor, uint256 toRelaunch);
}
