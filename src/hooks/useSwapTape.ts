import { useCallback, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";

export interface Trade { price: number; amountEth: number; isBuy: boolean; t: number; o: number }

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * The raw per-trade tape for a generation, from Ponder (/recent/:gen) — no
 * browser RPC. Sorted ASCending by time so the chart can bucket it into candles
 * at any timeframe (tick / 1m / 5m / 15m / 1h / 4h) client-side.
 */
export function useSwapTape(generation = 1, enabled = true, intervalMs = 5000): Trade[] {
  const [trades, setTrades] = useState<Trade[]>([]);

  const load = useCallback(async () => {
    if (!INDEXER) return;
    {
      try {
        const res = await fetch(`${INDEXER}/recent/${generation}?limit=5000`, { signal: AbortSignal.timeout(8000) });
        if (!res.ok) return;
        const d = await res.json() as { swaps?: Array<{ price: number; amountEth: number; isBuy: boolean; t: number; o?: number }> };
        const rows = (d.swaps ?? [])
          .filter((s) => s.price > 0 && Number.isFinite(s.price) && s.t > 0)
          .map((s, i) => ({ price: s.price, amountEth: s.amountEth, isBuy: s.isBuy, t: s.t, o: s.o ?? i }))
          // Sort by EXECUTION order (o = block*1e6+logIndex), NOT timestamp —
          // same-block liquidation buy-backs share `t`, and a t-sort leaves them
          // reversed → the candle closes on the wrong sub-swap (phantom red bar).
          .sort((a, b) => a.o - b.o);
        setTrades(rows);
      } catch { /* keep last */ }
    }
  }, [generation]);

  usePoll(load, intervalMs, enabled && !!INDEXER);

  return trades;
}
