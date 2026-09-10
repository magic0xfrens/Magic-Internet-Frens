import type { Address } from "viem";
import round from "../../indexer/deployments/round.json";

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
 * Presentation for the quotes this deployment allows, READ FROM THE MANIFEST.
 *
 * Hardcoding these would be the same bug that made a sold-out presale render as
 * "0 / 1111": a literal here would silently outlive the deployment it described.
 * The manifest is the single source of truth, and useAllowedQuotes still filters
 * this list through the registry's on-chain allowlist, so the chain has the
 * final say on what is selectable.
 */
export const KNOWN_QUOTES: QuoteAsset[] = (round.quoteAssets ?? []).map((q) => ({
  address: q.address as Address,
  symbol: q.symbol,
  name: q.name,
  decimals: q.decimals,
  glyph: q.glyph,
  blurb: q.blurb,
}));

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

/**
 * Per-field byte caps on a proposal's free text, MIRRORING the on-chain bounds
 * in `CauldronGovernor` (MAX_NAME_BYTES / MAX_SYMBOL_BYTES / MAX_URI_BYTES /
 * MAX_LINK_BYTES).
 *
 * The contract is the source of truth and refuses anything longer with
 * `FieldTooLong`. These exist so the form stops you at the input rather than at
 * the wallet confirmation — a revert at the end of a long proposal form is the
 * worst place to learn about a limit.
 *
 * Why the contract bounds them at all: `relaunch()` replays every one of these
 * fields on every rebirth, and an unbounded payload put the rebirth permanently
 * out of gas. Keep these in sync if the contract's constants ever change.
 *
 * NOTE: these are BYTE caps on-chain and `maxLength` counts UTF-16 code units,
 * so a multi-byte character (an emoji in a brew name) can still be refused by
 * the contract while passing the input. {proposalFieldError} is the check that
 * measures bytes properly; the maxLength is only the cheap first line.
 */
export const PROPOSAL_LIMITS = {
  name: 64,
  symbol: 16,
  uri: 256,
  link: 128,
} as const;

/** Byte length of a string as the contract will measure it (UTF-8). */
export const byteLength = (s: string) => new TextEncoder().encode(s).length;

/**
 * The reason a proposal field would be refused on-chain, or null if it is fine.
 * Checks BYTES, not characters, so an emoji-laden name is caught here rather
 * than by a reverted transaction.
 */
export function proposalFieldError(
  field: keyof typeof PROPOSAL_LIMITS,
  value: string,
): string | null {
  const max = PROPOSAL_LIMITS[field];
  const n = byteLength(value);
  return n > max ? `${n} bytes — the chain accepts at most ${max}` : null;
}
