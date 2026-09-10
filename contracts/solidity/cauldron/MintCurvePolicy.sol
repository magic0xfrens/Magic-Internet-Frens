// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ICurvePolicy} from "./IPolicies.sol";

/**
 * @title MintCurvePolicy
 * @notice The volume ladder for forging a collection: cheap at first, expensive
 *         fast, then the rate of increase settles down.
 *
 *  ── THE SHAPE ──────────────────────────────────────────────────────────────
 *
 *      cost(k) = base + spread * k^2 / (k + knee)
 *
 *  One expression, two regimes, no exponentials or logarithms to approximate:
 *
 *    * k much smaller than `knee`:  k^2/(k+knee) ~= k^2/knee  — QUADRATIC. The
 *      first frens are nearly free and the price runs away quickly.
 *    * k much larger than `knee`:   k^2/(k+knee) ~= k - knee  — LINEAR. The
 *      cost still rises with every mint, but the rate it rises AT flattens off.
 *
 *  So the price is strictly increasing everywhere while its acceleration decays
 *  — which is the "exponential then logarithmic" feel, obtained from integer
 *  arithmetic that cannot drift or overflow at these magnitudes.
 *
 *  ── WHY THE FLOOR IS SAFE, AND WHY IT NEEDS NO ORACLE ──────────────────────
 *
 *  The concern this curve is built around: forging an NFT must add MORE to the
 *  collection floor than the claim that NFT creates, or minting dilutes the
 *  holders who came before. Writing it out, with `r` the share of volume that
 *  reaches the floor (fee rate x legacyBps):
 *
 *      floorPerNFT(n) = r * SUM(cost[0..n-1]) / n
 *      minting n adds   r * cost[n]
 *
 *      rises  <=>  r*cost[n] > r*SUM(cost[0..n-1]) / n
 *             <=>    cost[n] > mean(cost[0..n-1])
 *
 *  `r` cancels. So does the token price, and so does the quote asset. The
 *  invariant is PURELY a statement about the curve: each NFT must cost more
 *  than the average of the ones before it — which is automatic for any strictly
 *  increasing ladder, and is asserted directly in F13.
 *
 *  That is worth stating plainly because it means the guarantee does not depend
 *  on an oracle being live, on the quote being ether, or on anyone tuning a
 *  ratio. It also means the real-world margin is wider than the maths: trading
 *  that is NOT a mint still pays into the floor, and so do secondary royalties
 *  (RoyaltyRouter), and both raise the numerator without touching the count.
 *
 *  ── CALIBRATION ────────────────────────────────────────────────────────────
 *  `spread` is chosen so the whole ladder sums to the intended mint-out cost.
 *  {totalToMintOut} computes that sum on-chain, so a deployment can VERIFY its
 *  calibration rather than trusting the number that was passed in.
 *
 *  Units are whatever the hook's credit is denominated in. With the quote
 *  oracle wired that is USD at 1e18, which is what makes "it costs $2M of
 *  volume to mint out" a sentence that survives a rotation to a different quote.
 */
contract MintCurvePolicy is ICurvePolicy {
    /// @notice Cost of the very first fren, in credit units.
    uint256 public immutable base;
    /// @notice Slope factor. Calibrated so the ladder sums to the target.
    uint256 public immutable spread;
    /// @notice Position where the curve turns from quadratic to linear.
    uint256 public immutable knee;
    /// @notice Collection size the calibration was computed against.
    uint256 public immutable supply;

    error BadParam();

    constructor(uint256 _base, uint256 _spread, uint256 _knee, uint256 _supply) {
        //  `knee` must be non-zero or k=0 divides by zero; `base` must be
        //  non-zero or the hook's own guard (`c > 0`) rejects every answer and
        //  silently falls back to the linear default.
        if (_base == 0 || _knee == 0 || _supply == 0) revert BadParam();
        //  A FLAT LADDER IS THE ONE SHAPE THAT BREAKS THE GUARANTEE. With
        //  spread = 0 every fren costs the same, `cost(n) > mean(cost[0..n-1])`
        //  fails, and each mint DILUTES the floor instead of raising it — the
        //  exact counter-example F13 asserts must fail. It is refused here
        //  rather than deployed, because a calibration that under-shoots
        //  (target below supply x base) silently produces exactly this.
        if (_spread == 0) revert BadParam();
        base = _base;
        spread = _spread;
        knee = _knee;
        supply = _supply;
    }

    /// @notice Credit cost of the NFT at 0-indexed curve position `k`.
    ///
    ///  `base` and `step` from the hook are deliberately IGNORED: this policy
    ///  carries its own calibration, and silently mixing the two sets of
    ///  constants would produce a ladder neither of them describes. The hook
    ///  keeps its values as the fallback for when no policy is set.
    function priceAt(uint256 k, uint256, uint256) external view returns (uint256) {
        //  At k = supply-1 = 3332 and spread ~ 0.4e18, k*k*spread is about
        //  4.4e24 — five orders of magnitude clear of uint256. No overflow path
        //  exists for any plausible collection size.
        return base + (spread * k * k) / (k + knee);
    }

    /// @notice Total credit needed to forge the whole collection.
    ///
    ///  Sums the ladder rather than approximating it, so the calibration can be
    ///  checked against the intended figure instead of assumed. A view over a
    ///  few thousand iterations is free off-chain and is never called on a mint
    ///  path.
    function totalToMintOut() external view returns (uint256 total) {
        uint256 n = supply;
        for (uint256 k; k < n; ++k) {
            total += base + (spread * k * k) / (k + knee);
        }
    }
}
