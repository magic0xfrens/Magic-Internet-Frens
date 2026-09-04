import { useEffect, useRef, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { PERP_LIVE } from "@/config/perp";

/** One open leveraged position with its liquidation price. */
export interface PerpPosition {
  id: string;
  isLong: boolean;
  leverage: number;
  entryPrice: number; // ETH per token
  liqPrice: number;   // ETH per token — where this position liquidates
  notionalEth: number;
  openedAt?: number;  // unix seconds the position was opened (band start on the chart)
  closedAt?: number | null; // unix seconds it closed/liquidated (band END); null = live
  status?: string;    // "open" | "closed" | "liquidated"
}

export interface PerpHeatmap {
  live: boolean;
  positions: PerpPosition[];      // live walls (open → now)
  history: PerpPosition[];        // finished walls (open → close/liquidation)
  markPrice: number | null;       // ETH per token at the TWAP mark (hint targeting)
  longOiEth: number;
  shortOiEth: number;
  plvEth: number;
  openCount: number;
  reason?: string;
}

const EMPTY: PerpHeatmap = { live: false, positions: [], history: [], markPrice: null, longOiEth: 0, shortOiEth: 0, plvEth: 0, openCount: 0 };
const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * Liquidation-heatmap feed — ALL open perp positions + liquidation prices, so the
 * chart can overlay the liquidation walls. Reads ONLY from Ponder (the indexer);
 * the browser makes no RPC calls. The indexer serves positions from its tables
 * and live depth/vault/OI via a server-side read with rotated keys.
 */
export function usePerpHeatmap(enabled: boolean, generation = 1, intervalMs = 5000): PerpHeatmap {
  const ref = useRef({ enabled, generation });
  ref.current = { enabled, generation };
  const [data, setData] = useState<PerpHeatmap>(EMPTY);

  useEffect(() => {
    let alive = true;
    const load = async () => {
      const { enabled, generation } = ref.current;
      if (!PERP_LIVE) { if (alive) setData({ ...EMPTY, reason: "PERP_LIVE=false (VITE_PERP_ENGINE)" }); return; }
      if (!enabled) { if (alive) setData({ ...EMPTY, reason: "not summoned / dead" }); return; }
      if (!INDEXER) { if (alive) setData({ ...EMPTY, reason: "no indexer (VITE_CAULDRON_INDEXER)" }); return; }
      try {
        const res = await fetch(`${INDEXER}/perp-heatmap/${generation}`, { signal: AbortSignal.timeout(12000) });
        if (!res.ok) { if (alive) setData({ ...EMPTY, reason: `indexer ${res.status}` }); return; }
        const d = await res.json() as Partial<PerpHeatmap>;
        if (!alive) return;
        const positions = Array.isArray(d.positions) ? d.positions : [];
        setData({
          live: true,
          positions,
          history: Array.isArray(d.history) ? d.history : [],
          markPrice: d.markPrice ?? null,
          longOiEth: d.longOiEth ?? 0, shortOiEth: d.shortOiEth ?? 0,
          plvEth: d.plvEth ?? 0,
          // Use the live positions array as the source of truth for the count —
          // the indexed `openCount` stat can lag/read 0 while positions exist
          // (and `??` wouldn't fall back on a literal 0).
          openCount: positions.length || (d.openCount ?? 0),
        });
      } catch (e) {
        if (alive) setData({ ...EMPTY, reason: "indexer unreachable: " + String((e as Error)?.message || e).slice(0, 60) });
      }
    };
    load();
    const t = setInterval(load, intervalMs);
    return () => { alive = false; clearInterval(t); };
  }, [intervalMs]);

  return data;
}
