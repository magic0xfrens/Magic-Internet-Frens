import type { Address } from "viem";

/**
 * Quote assets — what an iteration's token is PRICED IN.
 *
 * Historically every brew paired against native ETH. A brew can now pair against
 * a stablecoin or a tokenized equity instead, chosen by governance from a set
 * the treasury curates on-chain (`registry.allowedQuote`).
 *
 * THE CHAIN IS THE SOURCE OF TRUTH. This file only supplies presentation —
 * symbol, decimals, an icon — for addresses the chain has already approved. It
 * can never widen what is selectable: {useAllowedQuotes} filters the list
 * through `allowedQuote()`, so an entry here that governance has not approved
 * simply does not appear, and an approved address missing from here still
 * appears (rendered by its short address).
 */
export interface QuoteAsset {
  /** `address(0)` = native ETH. */
  address: Address;
  symbol: string;
  name: string;
  /** Decimals matter for display, not for pool maths: `_sqrtPrice` takes raw
   *  amounts. Getting this wrong misprices the UI by orders of magnitude. */
  decimals: number;
  /** Shown next to a price, e.g. "Ξ" or "$". */
  glyph: string;
  /** One line on why a brew might choose this pair. */
  blurb: string;
}

export const NATIVE_QUOTE: Address = "0x0000000000000000000000000000000000000000";

/**
 * Presentation for quotes we know about. ETH is first and always present: it is
 * allowed at construction and the registry refuses to remove it, so every brew
 * can always launch against it.
 */
export const KNOWN_QUOTES: QuoteAsset[] = [
  {
    address: NATIVE_QUOTE,
    symbol: "ETH",
    name: "Ether",
    decimals: 18,
    glyph: "Ξ",
    blurb: "The default. Deepest liquidity, and the only pair perps support today.",
  },
];

/** Presentation for `quote`, falling back to a shortened address for anything
 *  approved on-chain that this file does not know about yet. */
export function quoteMeta(quote?: Address | null): QuoteAsset {
  const a = (quote ?? NATIVE_QUOTE).toLowerCase();
  const hit = KNOWN_QUOTES.find((q) => q.address.toLowerCase() === a);
  if (hit) return hit;
  return {
    address: (quote ?? NATIVE_QUOTE) as Address,
    symbol: `${(quote ?? "").slice(0, 6)}…${(quote ?? "").slice(-4)}`,
    name: "Unlisted quote",
    decimals: 18,
    glyph: "",
    blurb: "Approved on-chain, but not yet described in the app.",
  };
}

/** True when the brew is quoted in native ETH — the only case perps serve. */
export const isNativeQuote = (quote?: Address | null) =>
  !quote || quote.toLowerCase() === NATIVE_QUOTE;

/** Format an amount of the quote for display. Reads the quote's own decimals
 *  rather than assuming 18: USDG is 6, and assuming 18 would be off by 10^12. */
export function formatQuote(
  raw: bigint,
  quote?: Address | null,
  dp = 4,
): string {
  const meta = quoteMeta(quote);
  const v = Number(raw) / 10 ** meta.decimals;
  return `${v.toFixed(dp)}${meta.glyph ? ` ${meta.glyph}` : ` ${meta.symbol}`}`;
}
