import { useCallback, useState } from "react";
import { usePoll } from "@/hooks/usePoll";
import { CAULDRON_INDEXER } from "@/config/cauldron";

export interface Candle { t: number; o: number; h: number; l: number; c: number; v: number }

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * OHLC candles for a generation, straight from Ponder (/candles/:gen) — no
 * browser RPC. Returns the candle series (ETH per token) for a candlestick chart.
 */
export function useCandles(generation = 1, enabled = true, intervalMs = 12000): { candles: Candle[]; last: number } {
  const [state, setState] = useState<{ candles: Candle[]; last: number }>({ candles: [], last: 0 });

  const load = useCallback(async () => {
      try {
        const res = await fetch(`${INDEXER}/candles/${generation}?limit=120`, { signal: AbortSignal.timeout(6000) });
        if (!res.ok) return;
        const d = await res.json() as { candles?: Candle[]; last?: number };
        const candles = (d.candles ?? []).filter((k) => k.c > 0 && Number.isFinite(k.c));
        setState({ candles, last: d.last ?? (candles.at(-1)?.c ?? 0) });
      } catch { /* keep last */ }
  }, [generation]);

  usePoll(load, intervalMs, enabled && !!INDEXER);

  return state;
}
