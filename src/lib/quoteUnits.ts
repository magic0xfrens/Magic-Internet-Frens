/**
 * QUOTE UNITS — the decimals arithmetic that two separate bugs were missing.
 *
 * A generation's pool is `currency0 = quote, currency1 = token` by construction
 * (`PoolOps.sol:269-274` — "the token is deployed to sort above it"), and the
 * token is always 18 decimals. The QUOTE is not: round.json ships USDG at 6 and
 * xNVDA at 18. Everything below is pure so it can be unit-tested without a
 * chain; `scripts/test-quote-units.mjs` asserts the 6- and 18-decimal cases.
 *
 * The indexer keeps its own copy at `indexer/src/quoteUnits.ts` — Ponder builds
 * from `indexer/` alone and cannot reach across the tree into `src/`.
 */

/** Token side of every cauldron pool. Fixed by `CauldronToken`. */
export const TOKEN_DECIMALS = 18;

/**
 * RAW currency0/currency1 ratio → human quote-per-token.
 *
 * `sqrtPriceX96` prices RAW units against RAW units, so a 6-decimal quote makes
 * the raw ratio 10^12 too small. Without this term a USDG-quoted pool reported
 * `2.5e-18` where the true price is `0.0000025` USDG/token — 4e8x off — which
 * made every buy sign an unreachable floor and mispriced every chart, mcap and
 * FDV. Native ETH is 18 decimals, so the factor is exactly 1 and the ETH path
 * is bit-for-bit unchanged.
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

/**
 * HOW MUCH QUOTE THE BUY MAY SPEND, in the quote's own decimals.
 *
 * The buy hook used to hand the router the wallet's ENTIRE quote balance while
 * the slippage floor was sized for the amount the user typed. `_pullQuote`
 * (`CauldronGachaRouter.sol:278`) `transferFrom`s the whole thing and the
 * exact-input swap at the extreme tick consumes all of it with no refund, so a
 * wallet holding 10,000 USDG spent 10,000 to buy 25 USDG worth — a measured
 * 400x overspend.
 *
 * The typed amount is `expected` (the oracle's conversion of the typed ETH into
 * quote units). When a zap was needed, `delivered` is what the swap ACTUALLY
 * produced; spending more than that would revert in `transferFrom`, and
 * spending the pre-zap estimate is the same class of guess. So: the typed
 * amount, never more than what arrived, never more than the wallet holds.
 */
export function quoteInForTypedAmount(
  expected: bigint,
  delivered: bigint | null,
  walletBalance: bigint,
): bigint {
  let spend = expected;
  if (delivered !== null && delivered < spend) spend = delivered;
  if (walletBalance < spend) spend = walletBalance;
  return spend > 0n ? spend : 0n;
}

/**
 * Re-scale a slippage floor that was computed for `reference` input down to the
 * `spend` actually being signed. Proportional, so the per-unit floor the user
 * chose is preserved exactly and never raised.
 */
export function scaleFloor(minOut: bigint, spend: bigint, reference: bigint): bigint {
  if (reference <= 0n || spend >= reference) return minOut;
  return (minOut * spend) / reference;
}
