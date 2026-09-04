// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/**
 * @title SeedLib
 * @notice Pure math for the PROGRESSIVE (streamed) launch seed. Two parts:
 *
 *  1. SCHEDULE — how much of the active tranche should be deployed by `now`,
 *     streaming linearly from a starting `seedFloor` fraction up to 100% over a
 *     configurable `window` (see LAUNCH_LADDER_DESIGN.md). The Seeder deploys the
 *     DELTA between the target and what's already placed on each poke — continuous,
 *     so there's no discrete "add LP" tx to front-run.
 *
 *  2. BAND GEOMETRY — where the single-sided liquidity sits. We build the two-sided
 *     book from single-sided orders (no leftover-ratio problem):
 *       • ASK bands = single-sided TOKEN (currency1), what buyers buy.
 *       • BID bands = single-sided ETH   (currency0), what sellers sell into.
 *
 *  ORIENTATION (the footgun — matches ReserveLib). ETH is currency0, the brew
 *  token is currency1, so pool price = token1/token0 = TOKENS per ETH. When the
 *  TOKEN appreciates, tokens-per-ETH FALLS → the pool tick FALLS. Therefore:
 *       • ASK (token) bands sit BELOW the launch tick — pure token1 while
 *         currentTick >= tickUpper; consumed as buyers push the tick DOWN.
 *       • BID (ETH) bands sit ABOVE the launch tick — pure token0/ETH while
 *         currentTick < tickLower; consumed as sellers push the tick UP.
 *  So a token-price CEILING (P_max, e.g. 5–10×) is a tick offset BELOW launch, and
 *  a token-price FLOOR (e.g. −80%) is a tick offset ABOVE launch. Both offsets are
 *  passed as POSITIVE tick distances; the frontend computes them from multipliers
 *  via ln(mult)/ln(1.0001).
 *
 *  Aggregate at rest (zero net flow) the ask bands below + bid bands above ≡ one
 *  concentrated two-sided position centred at the launch tick = the old atomic LP.
 */
library SeedLib {
    uint256 internal constant WAD = 1e18;

    // ── tick alignment (same convention as ReserveLib) ──────────────────────
    function _alignDown(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 r = tick / spacing;
        if (tick < 0 && (tick % spacing != 0)) r -= 1;
        return r * spacing;
    }
    function _alignUp(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 r = tick / spacing;
        if (tick > 0 && (tick % spacing != 0)) r += 1;
        return r * spacing;
    }

    // ── 1. SCHEDULE ─────────────────────────────────────────────────────────
    /**
     * @notice Fraction (WAD, 1e18 = 100%) of the active tranche that SHOULD be
     *         deployed by `nowTs`. Linear from `seedFloorWad` at `startTs` to 100%
     *         at `startTs + window`. Clamped: `< start` → seedFloor, `>= start+window`
     *         → 100%. `window == 0` → always 100% (degenerate/atomic).
     */
    function deployedTargetWad(uint64 startTs, uint64 window, uint256 nowTs, uint256 seedFloorWad)
        internal
        pure
        returns (uint256 wad)
    {
        if (seedFloorWad > WAD) seedFloorWad = WAD;
        if (window == 0 || nowTs >= uint256(startTs) + window) return WAD;
        if (nowTs <= startTs) return seedFloorWad;
        uint256 elapsed = nowTs - startTs;
        // seedFloor + (1 - seedFloor) * elapsed/window
        return seedFloorWad + ((WAD - seedFloorWad) * elapsed) / window;
    }

    // ── 2. BAND GEOMETRY ────────────────────────────────────────────────────
    /**
     * @notice The i-th single-sided TOKEN (ask) band, BELOW the launch tick.
     *         The ask region [L - ceilingOffset, L] is tiled into `n` equal-width
     *         bands; band 0 is the hottest (adjacent to launch, first bought).
     * @param i            band index, 0..n-1 (0 = closest to launch)
     * @param n            total ask bands (>= 1)
     * @param launchTick   pool tick right after initialize()
     * @param spacing      pool tick spacing
     * @param ceilingOffset positive ticks below launch = the price ceiling (P_max)
     * @return lower the band's lower tick
     * @return upper the band's upper tick (pure token1 while currentTick >= upper)
     */
    function askBand(uint256 i, uint256 n, int24 launchTick, int24 spacing, int24 ceilingOffset)
        internal
        pure
        returns (int24 lower, int24 upper)
    {
        int24 L = _alignDown(launchTick, spacing);
        int24 w = _bandWidth(ceilingOffset, n, spacing);
        // band i sits [L - (i+1)w, L - i*w]; band 0's upper == L (pure token since
        // currentTick(launch) >= L).
        upper = L - int24(int256(i)) * w;
        lower = upper - w;
        // clamp the deepest band's floor to the usable range
        int24 floorTick = _alignUp(TickMath.MIN_TICK, spacing);
        if (lower < floorTick) lower = floorTick;
        if (upper <= lower) upper = lower + spacing;
    }

    /**
     * @notice The j-th single-sided ETH (bid) band, ABOVE the launch tick.
     *         The bid region [L+spacing, L+spacing + floorOffset] is tiled into `m`
     *         equal-width bands; band 0 is the hottest (adjacent to launch, first
     *         sold into). Starts one spacing above launch so the band is pure ETH
     *         (currentTick < tickLower) at seed — the one-spacing seam at launch is
     *         where the marginal "P0" trade sits.
     * @return lower the band's lower tick (pure token0/ETH while currentTick < lower)
     * @return upper the band's upper tick
     */
    function bidBand(uint256 j, uint256 m, int24 launchTick, int24 spacing, int24 floorOffset)
        internal
        pure
        returns (int24 lower, int24 upper)
    {
        int24 L = _alignDown(launchTick, spacing) + spacing; // strictly above launch
        int24 w = _bandWidth(floorOffset, m, spacing);
        lower = L + int24(int256(j)) * w;
        upper = lower + w;
        // clamp the highest band's ceiling to the usable range
        int24 capTick = _alignDown(TickMath.MAX_TICK, spacing);
        if (upper > capTick) upper = capTick;
        if (upper <= lower) lower = upper - spacing;
    }

    /// @dev Equal band width for tiling `offset` ticks into `n` bands, aligned to
    ///      `spacing` and never below one spacing.
    function _bandWidth(int24 offset, uint256 n, int24 spacing) internal pure returns (int24 w) {
        if (n == 0) n = 1;
        w = _alignDown(offset / int24(int256(n)), spacing);
        if (w < spacing) w = spacing;
    }

    /**
     * @notice Per-band allocation weight (WAD) that tapers MORE liquidity toward the
     *         launch tick (band 0) and less into the tails — a linear descending
     *         profile. Sum over i=0..n-1 == 1e18 (bar integer dust). Band 0 gets
     *         weight ∝ n, the last band ∝ 1.
     */
    function taperWeightWad(uint256 i, uint256 n) internal pure returns (uint256 wad) {
        if (n == 0) return 0;
        // w_i = 2 (n - i) / (n (n+1))
        uint256 denom = n * (n + 1);
        return (2 * (n - i) * WAD) / denom;
    }
}
