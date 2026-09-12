import { useCallback, useState } from "react";
import type { Address } from "viem";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { NATIVE_QUOTE, quoteMeta, type QuoteAsset } from "@/config/quotes";
import { usePoll } from "@/hooks/usePoll";

/**
 * WHAT THE LP IS ACTUALLY DENOMINATED IN, and in what proportion.
 *
 * A generation used to be one pool against native ETH, so "the basis" was a
 * constant and nothing needed to display it. It is now a per-generation choice
 * (`registry.generationQuote`), and a guild can hold the treasury across several
 * assets and rotate between them ({QuoteRotator}). Neither fact was visible
 * anywhere in the app.
 *
 * ── READ FROM PONDER, NOT FROM THE BROWSER ────────────────────────────────
 * Everything here comes from ONE cached call to the indexer's `/treasury`,
 * which does the chain reads server-side against a rotated multi-node pool.
 *
 * The first version of this hook read the chain directly: one `balanceOf` per
 * quote plus an oracle call each, per open tab, every 30 seconds. That is the
 * shape the rest of this app deliberately avoids — the cost multiplies by
 * viewers, it competes with Ponder's own sync for the same public nodes, and it
 * earns an HTTP 429 exactly when the app is busiest. `usePerpVault` states the
 * rule plainly: reads come from Ponder so the browser stays RPC-free.
 *
 * ── ON REFUSING TO DRAW A BAR ─────────────────────────────────────────────
 * A share is a USD comparison, and USD needs a price. When an asset is held but
 * cannot be priced the endpoint returns `usd: null`, and this reports `share:
 * null` rather than guessing. A bar that silently treats 10,000 USDG (6dp) as
 * 10,000 ETH (18dp) would render ETH as 99.99% of a treasury it is a minority
 * of — the exact failure `QuoteRotator` was redesigned to avoid. A wrong bar is
 * worse than a missing one, because it looks like data.
 */

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

export interface QuoteHolding {
  asset: QuoteAsset;
  /** Raw balance, in the asset's own units. */
  raw: bigint;
  /** Human IDLE amount in the asset's own units — what is NOT deployed. */
  amount: number;
  /** Raw quote-side amount this asset has deployed in the generation's live
   *  positions, in the asset's own units. */
  lpRaw: bigint;
  /** Human deployed amount. For a healthy treasury this is essentially all of
   *  it: `rotateSlice` redeploys in the same transaction it removes in. */
  lpAmount: number;
  /** Idle + deployed. The figure `usd` is derived from. */
  totalAmount: number;
  /** USD value, or null when no usable price exists for this asset. */
  usd: number | null;
  /** Share of the priced total, 0..1 — null when this asset is unpriced. */
  share: number | null;
  /** Raw Uniswap L units this quote currently backs across the generation's live
   *  positions. This is where the value actually IS: `rotateSlice` removes,
   *  swaps and redeploys in one transaction, so a working treasury holds almost
   *  nothing idle. Not comparable BETWEEN quotes without a price, so it is shown
   *  as presence ("in LP") rather than folded into `share`. */
  liquidity: bigint;
  /** True when this is the asset the live generation is priced in. */
  isBasis: boolean;
}

export interface LpComposition {
  /** The quote the live generation's pool is denominated in. */
  basis: QuoteAsset;
  holdings: QuoteHolding[];
  /** Sum of the USD values that could be priced. */
  totalUsd: number;
  /** True when at least one HELD asset had no usable price, so the shares
   *  describe only part of the treasury and the UI must say so. */
  partial: boolean;
  loading: boolean;
  /** USD(1e18) per RAW unit, keyed by lowercased quote address — the same
   *  factors `QuoteRotator._oracleFloor` prices slices with, so a native<->quote
   *  rate derived from these agrees with the contract by construction. */
  prices: Record<string, bigint>;
  /** True when the endpoint could not be read. An empty treasury and an
   *  unreachable indexer render identically otherwise, and they mean opposite
   *  things: one says the guild holds nothing, the other says we do not know. */
  failed: boolean;
}

/** The `/treasury` payload. `raw` is a string because JSON has no bigint. */
interface TreasuryRow {
  address: string;
  raw: string;
  amount: number;
  usd: number | null;
  share: number | null;
  liquidity?: string;
  lpRaw?: string;
  lpAmount?: number;
  totalAmount?: number;
  isBasis: boolean;
}

const EMPTY: LpComposition = {
  basis: quoteMeta(NATIVE_QUOTE),
  holdings: [],
  totalUsd: 0,
  partial: false,
  loading: true,
  failed: false,
  prices: {},
};

/**
 * @param generation the live generation — used only to re-fetch across a rebirth;
 *                   the endpoint resolves the basis itself from the indexed tables
 */
export function useLpComposition(generation: number): LpComposition {
  const [state, setState] = useState<LpComposition>(EMPTY);

  const load = useCallback(async () => {
    if (!INDEXER) {
      // No indexer configured: report "nothing to show" rather than falling back
      // to browser RPC, which is the thing this hook exists to not do.
      setState((s) => ({ ...s, loading: false, failed: true }));
      return;
    }
    try {
      const r = await fetch(`${INDEXER}/treasury`);
      if (!r.ok) throw new Error(String(r.status));
      const j = (await r.json()) as {
        basis: string; holdings: TreasuryRow[]; totalUsd: number; partial: boolean;
        prices?: Record<string, string>;
      };
      setState({
        basis: quoteMeta(j.basis as Address),
        holdings: (j.holdings ?? []).map((h) => ({
          asset: quoteMeta(h.address as Address),
          raw: BigInt(h.raw ?? "0"),
          amount: h.amount ?? 0,
          lpRaw: BigInt(h.lpRaw ?? "0"),
          lpAmount: h.lpAmount ?? 0,
          //  Fall back to the idle amount when the endpoint predates the LP
          //  valuation, so an older indexer degrades to the previous behaviour
          //  instead of reporting every holding as zero.
          totalAmount: h.totalAmount ?? h.amount ?? 0,
          usd: h.usd,
          share: h.share,
          liquidity: BigInt(h.liquidity ?? "0"),
          isBasis: h.isBasis,
        })),
        totalUsd: j.totalUsd ?? 0,
        partial: !!j.partial,
        loading: false,
        failed: false,
        prices: Object.fromEntries(
          Object.entries((j.prices ?? {}) as Record<string, string>)
            .map(([k, v]) => [k.toLowerCase(), BigInt(v)]),
        ),
      });
    } catch {
      // Keep the last good composition; only clear the spinner. A blank panel on
      // one failed poll is worse than a slightly stale one.
      setState((s) => ({ ...s, loading: false, failed: true }));
    }
  }, []);

  // The endpoint caches for 30s server-side, so polling faster than that only
  // costs the browser a round-trip and returns the identical payload.
  usePoll(load, 30_000, !!generation);

  return state;
}
