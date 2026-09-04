import { useEffect, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { PERP_LIVE } from "@/config/perp";

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

interface HeatPos { id: string; isLong: boolean; leverage: number; entryPrice: number; liqPrice: number; notionalEth: number }

/**
 * usePerpLiqHint — picks the single MOST-AT-RISK open perp position to tag onto
 * a swap as a `liqHint`. If our buy/sell tips that position past its TWAP mark,
 * the hook auto-liquidates it inside our swap and mints US a Liquidatoor badge.
 *
 * A buy pushes price UP → threatens SHORTS (liq above spot); a sell pushes price
 * DOWN → threatens LONGS (liq below spot). We pick, on the threatened side, the
 * position whose liq price is CLOSEST to the current mark (soonest to cross). The
 * engine re-checks underwater-at-mark on-chain and no-ops a hint that isn't
 * genuinely liquidatable, so an over-eager hint never risks the trade.
 *
 * Returns 0n when nothing is close enough to matter (keeps swaps on the cheaper
 * `play` path). `side` = the trade we're about to make.
 */
export function usePerpLiqHint(side: "buy" | "sell", generation = 1): bigint {
  const [hint, setHint] = useState<bigint>(0n);

  useEffect(() => {
    if (!PERP_LIVE || !INDEXER) { setHint(0n); return; }
    let alive = true;
    const load = async () => {
      try {
        const res = await fetch(`${INDEXER}/perp-heatmap/${generation}`, { signal: AbortSignal.timeout(8000) });
        if (!res.ok) return;
        const d = await res.json() as { positions?: HeatPos[]; markPrice?: number };
        if (!alive) return;
        const positions = d.positions ?? [];
        if (positions.length === 0) { setHint(0n); return; }
        // Reference price: server mark if present, else the median entry (a coarse
        // proxy — the engine does the authoritative check regardless).
        const mark = d.markPrice && d.markPrice > 0
          ? d.markPrice
          : positions.map((p) => p.entryPrice).sort((a, b) => a - b)[Math.floor(positions.length / 2)] || 0;
        // A sell threatens LONGS (price down), a buy threatens SHORTS (price up).
        const threatened = positions.filter((p) => (side === "sell" ? p.isLong : !p.isLong) && p.liqPrice > 0);
        if (threatened.length === 0) { setHint(0n); return; }
        // Prefer a position that has ALREADY CROSSED its liq level at the mark
        // (a short liquidates when mark ≥ liqPrice; a long when mark ≤ liqPrice)
        // — that's a guaranteed on-chain liquidation. If none are crossed yet,
        // fall back to the one closest to crossing (about to be tipped by us).
        const crossed = threatened.filter((p) => (side === "sell" ? mark <= p.liqPrice : mark >= p.liqPrice));
        const pool = crossed.length > 0 ? crossed : threatened;
        const best = pool.reduce((a, b) =>
          Math.abs(b.liqPrice - mark) < Math.abs(a.liqPrice - mark) ? b : a);
        setHint(BigInt(best.id));
      } catch { /* keep last */ }
    };
    load();
    // Pause while the tab is backgrounded, refresh on return: an idle tab
    // should cost nothing. Mirrors usePoll.
    let t: ReturnType<typeof setInterval> | null = setInterval(load, 6000);
    const onVis = () => {
      if (document.hidden) { if (t) { clearInterval(t); t = null; } }
      else if (!t) { load(); t = setInterval(load, 6000); }
    };
    document.addEventListener("visibilitychange", onVis);
    return () => {
      alive = false;
      if (t) clearInterval(t);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [side, generation]);

  return hint;
}
