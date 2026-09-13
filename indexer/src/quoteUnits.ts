/**
 * QUOTE UNITS — indexer copy of `src/lib/quoteUnits.ts`.
 *
 * Ponder builds from `indexer/` alone (that is the directory `railway up`
 * ships), so it cannot import across the tree. Keep the two in step; the shared
 * unit test `scripts/test-quote-units.mjs` imports BOTH files and asserts they
 * agree, so a drift fails the test rather than silently mispricing a chart.
 */

/** Token side of every cauldron pool. Fixed by `CauldronToken`. */
export const TOKEN_DECIMALS = 18;

/**
 * RAW currency0/currency1 ratio → human quote-per-token.
 *
 * `sqrtPriceX96` prices RAW units against RAW units. A cauldron pool is always
 * `currency0 = quote, currency1 = token` (`PoolOps.sol:269-274`), the token is
 * always 18 decimals, and the quote is not — round.json ships USDG at 6. Without
 * this term a USDG pool recorded `2.5e-18` where the truth is `0.0000025`
 * USDG/token, 4e8x off, which made every ERC20-quoted buy sign an unreachable
 * floor and mispriced every chart, mcap and FDV. Native ETH is 18 decimals, so
 * the factor is exactly 1 and the ETH path is unchanged.
 */
export function normaliseQuotePerToken(
  rawRatio: number,
  quoteDecimals: number,
  tokenDecimals: number = TOKEN_DECIMALS,
): number {
  if (!Number.isFinite(rawRatio) || rawRatio <= 0) return 0;
  return rawRatio * 10 ** (tokenDecimals - quoteDecimals);
}

/** RAW amount of the quote side of a swap → human units of that quote. */
export function rawToQuoteAmount(raw: bigint, quoteDecimals: number): number {
  const neg = raw < 0n;
  const abs = neg ? -raw : raw;
  const v = Number(abs) / 10 ** quoteDecimals;
  return neg ? -v : v;
}
