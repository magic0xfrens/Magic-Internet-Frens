import { useEffect, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";

export interface Candle { t: number; o: number; h: number; l: number; c: number; v: number }

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * OHLC candles for a generation, straight from Ponder (/candles/:gen) — no
 * browser RPC. Returns the candle series (ETH per token) for a candlestick chart.
 */
export function useCandles(generation = 1, enabled = true, intervalMs = 12000): { candles: Candle[]; last: number } {
  const [state, setState] = useState<{ candles: Candle[]; last: number }>({ candles: [], last: 0 });

  useEffect(() => {
    if (!enabled || !INDEXER) { setState({ candles: [], last: 0 }); return; }
    let alive = true;
    const load = async () => {
      try {
        const res = await fetch(`${INDEXER}/candles/${generation}?limit=120`, { signal: AbortSignal.timeout(6000) });
        if (!res.ok) return;
        const d = await res.json() as { candles?: Candle[]; last?: number };
        if (!alive) return;
        const candles = (d.candles ?? []).filter((k) => k.c > 0 && Number.isFinite(k.c));
        setState({ candles, last: d.last ?? (candles.at(-1)?.c ?? 0) });
      } catch { /* keep last */ }
    };
    load();
    const t = setInterval(load, intervalMs);
    return () => { alive = false; clearInterval(t); };
  }, [generation, enabled, intervalMs]);

  return state;
}
