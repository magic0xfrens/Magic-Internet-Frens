import { useCallback, useEffect, useState } from "react";
import { usePoll } from "@/hooks/usePoll";
import { CAULDRON_INDEXER } from "@/config/cauldron";

export interface Candle { t: number; o: number; h: number; l: number; c: number; v: number }

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * OHLC candles for a generation, straight from Ponder (/candles/:gen) — no
 * browser RPC. Returns the candle series (ETH per token) for a candlestick chart.
 */
/**
 * @param refreshKey Change it to force an immediate refetch. The cauldron passes
 *   the websocket swap nonce, so a trade made on ANY machine redraws the chart
 *   the moment its block is seen instead of up to 12s later. The interval stays
 *   as the fallback for when the socket is down.
 */
export function useCandles(
  generation = 1,
  enabled = true,
  intervalMs = 12000,
  refreshKey?: string | number | null,
): { candles: Candle[]; last: number } {
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

  // Refetch the instant the key changes — the websocket sees a swap long before
  // the next interval would have fired.
  useEffect(() => {
    if (refreshKey == null || !enabled || !INDEXER) return;
    void load();
  }, [refreshKey, enabled, load]);

  return state;
}
