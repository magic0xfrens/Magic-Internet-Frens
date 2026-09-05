import { useCallback, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";

export type IndexerState = "ok" | "syncing" | "stale" | "down";

export interface IndexerHealth {
  state: IndexerState;
  /** Human-readable reason, or "" when healthy. */
  reason: string;
  degraded: boolean;
}

/**
 * Is the indexer actually telling the truth right now?
 *
 * Most of the page reads from Ponder with no chain fallback — candles, the trade
 * tape, the perp heatmap, collection floors. When it restarts, backfills or
 * points at the wrong pool, those hooks do not error: they return empty, and the
 * UI renders a confident, wrong, EMPTY page. A sold-out presale showed 0 / 1111
 * that way, and a live pool read "awaiting first swaps" through real buys.
 *
 * Silent wrongness is the failure mode worth fixing, and it cannot be fixed hook
 * by hook — several of them genuinely cannot fall back (you cannot rebuild an
 * hour of candles from one RPC call). So instead the page SAYS when the data
 * behind it is not trustworthy, which covers all of them at once.
 *
 * The indexer already exposes /freshness with exactly the signals needed: the
 * generation it has indexed vs the chain's, and whether its pool set matches.
 */
export function useIndexerHealth(): IndexerHealth {
  const [h, setH] = useState<IndexerHealth>({ state: "ok", reason: "", degraded: false });

  const load = useCallback(async () => {
    const base = CAULDRON_INDEXER;
    if (!base) return;
    try {
      const res = await fetch(`${base}/freshness`, { signal: AbortSignal.timeout(7000) });
      if (!res.ok) {
        setH({ state: "down", reason: `indexer returned ${res.status}`, degraded: true });
        return;
      }
      const d = (await res.json()) as {
        ok?: boolean;
        chainGen?: number;
        indexedGen?: number;
        curPoolId?: string;
        indexedPools?: string[];
        reasons?: Record<string, boolean>;
      };

      // Pool mismatch is the one that produces a plausible EMPTY page rather
      // than an obviously broken one, so it is called out by name.
      const pools = (d.indexedPools ?? []).map((p) => p.toLowerCase());
      const cur = (d.curPoolId ?? "").toLowerCase();
      if (cur && pools.length > 0 && !pools.includes(cur)) {
        setH({ state: "stale", reason: "indexing a different pool — trades will not appear", degraded: true });
        return;
      }
      if (d.chainGen != null && d.indexedGen != null && d.indexedGen < d.chainGen) {
        setH({ state: "syncing", reason: `catching up to generation ${d.chainGen}`, degraded: true });
        return;
      }
      if (d.ok === false) {
        const why = Object.entries(d.reasons ?? {}).find(([, v]) => v)?.[0];
        setH({ state: "syncing", reason: why ? `syncing (${why})` : "syncing", degraded: true });
        return;
      }
      setH({ state: "ok", reason: "", degraded: false });
    } catch {
      setH({ state: "down", reason: "cannot reach the indexer", degraded: true });
    }
  }, []);

  // 25s: this is a health check, not a data feed. Polling it hard would add load
  // to the very service it is reporting on.
  usePoll(load, 25_000);
  return h;
}
