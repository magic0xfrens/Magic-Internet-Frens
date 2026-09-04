// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";

/**
 * @title ReserveLib
 * @notice Pure math for the "all supply in the LP" migration/genesis reserve.
 *
 *  THE MODEL. To avoid a whale-look wallet holding the un-migrated supply, the
 *  reserve is parked as a SINGLE-SIDED token position OUT OF RANGE, so 100% of
 *  supply reads as liquidity yet only ever leaves 1:1 against a burn/claim.
 *
 *  ORIENTATION (the footgun). In every Cauldron pool ETH is `currency0` and the
 *  brew token is `currency1`, so the pool price is `token1/token0` = TOKENS per
 *  ETH. A position holds pure `token1` only when the current price is ABOVE its
 *  range (currentTick > tickUpper). When the TOKEN appreciates, tokens-per-ETH
 *  FALLS, so the pool price/tick FALLS. Therefore the reserve must sit BELOW the
 *  launch tick: it is pure token while `currentTick > reserveTickUpper`, and only
 *  begins converting to ETH if the token pumps ~69x down into the range. Placing
 *  it above the launch tick would make it pure ETH (wrong) or sell instantly.
 */
library ReserveLib {
    /// @dev Align a tick DOWN to the nearest multiple of `spacing` (toward -inf).
    function _alignDown(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 r = tick / spacing;
        if (tick < 0 && (tick % spacing != 0)) r -= 1;
        return r * spacing;
    }

    /// @dev Align a tick UP to the nearest multiple of `spacing` (toward +inf).
    function _alignUp(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 r = tick / spacing;
        if (tick > 0 && (tick % spacing != 0)) r += 1;
        return r * spacing;
    }

    /**
     * @notice The [tickLower, tickUpper] for the single-sided token reserve,
     *         placed BELOW the launch tick by `offset` (≈ the appreciation
     *         ceiling). The band spans from the aligned floor up to
     *         `launchTick - offset`, so every reserve token is priced at ≥ that
     *         ceiling and stays pure token1 until the pool trades into it.
     * @param launchTick the pool's tick right after initialize()
     * @param spacing    the pool tick spacing (200)
     * @param offset     ticks below launch = the ceiling (≈ ln(69)/ln(1.0001) → 42400)
     */
    function reserveTicks(int24 launchTick, int24 spacing, int24 offset)
        internal
        pure
        returns (int24 tickLower, int24 tickUpper)
    {
        tickUpper = _alignDown(launchTick - offset, spacing);
        // Floor at the lowest USABLE aligned tick (>= MIN_TICK): align UP so we
        // never place a tick below MIN_TICK (which reverts InvalidTick). The band
        // spans from here up to the ceiling ("infinite" token price side).
        tickLower = _alignUp(TickMath.MIN_TICK, spacing);
        // Degenerate-safety: if the launch tick is so low the ceiling underflows
        // past the floor, collapse to a one-space band just above the floor so the
        // position is still valid (pure token1) rather than reverting.
        if (tickUpper <= tickLower) {
            tickUpper = tickLower + spacing;
        }
    }

    /**
     * @notice Liquidity units `L` that represent EXACTLY `amount1` of token when
     *         the range is fully below the current price (pure token1). Rounds
     *         DOWN (via V4's LiquidityAmounts), so removing this `L` can never
     *         pull more than `amount1` and never pulls any ETH. Used both to SIZE
     *         the reserve at seed time and to remove the exact N for a claim.
     */
    function liquidityForTokenOut(int24 tickLower, int24 tickUpper, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        liquidity = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount1
        );
    }
}
