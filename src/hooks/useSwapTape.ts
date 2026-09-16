import { useCallback, useEffect, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";

export interface Trade { price: number; amountEth: number; isBuy: boolean; t: number; o: number }

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * The raw per-trade tape for a generation, from Ponder (/recent/:gen) — no
 * browser RPC. Sorted ASCending by time so the chart can bucket it into candles
 * at any timeframe (tick / 1m / 5m / 15m / 1h / 4h) client-side.
 *
 * This is the ONE price source for the app: the brew line, the trading chart and
 * the header all derive from it, so they cannot disagree about what the price
 * did.
 *
 * Pass `refreshKey` (e.g. a confirmed tx hash) to pull immediately instead of
 * waiting out the poll. A receipt only means the swap is mined — the indexer
 * still has to see that block — so the refresh is retried briefly rather than
 * fired once, otherwise a single early fetch returns the pre-swap tape and the
 * chart looks unchanged until the next interval.
 */
/** Stable identity so an unresolved tape does not re-render every consumer. */
const EMPTY_TRADES: Trade[] = [];

export function useSwapTape(
  generation = 1,
  enabled = true,
  intervalMs = 5000,
  refreshKey?: string | null,
): Trade[] {
  //  KEYED BY THE GENERATION IT WAS READ FOR. This tape is the app's live price
  //  source: TheCauldron:510 takes its last row as `livePerpPrice`, which becomes
  //  SwapWidget's `spotPrice` and therefore the SIGNED slippage floor. `usePoll`'s
  //  effect deps are [intervalMs, enabled] only, and `enabled` does not change on
  //  a relaunch — so an unkeyed array kept serving the PREVIOUS generation's last
  //  trade, i.e. a different token's price, for a whole poll period. Returning
  //  nothing for a generation we have not read makes TheCauldron fall back to the
  //  machine's own `m.spotPrice`, which is generation-correct.
  const [state, setState] = useState<{ gen: number; rows: Trade[] }>({ gen: 0, rows: [] });

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
        setState({ gen: generation, rows });
      } catch { /* keep last */ }
    }
  }, [generation]);

  //  Invalidate, then re-read, the moment the generation changes — `usePoll`
  //  alone never restarts on a `load` change when `enabled` is already true.
  useEffect(() => {
    setState((s) => (s.gen === generation ? s : { gen: 0, rows: [] }));
    void load();
  }, [load, generation]);

  usePoll(load, intervalMs, enabled && !!INDEXER);

  // Chase a freshly-confirmed transaction: the indexer trails the chain by a
  // block or two, so poll a few times over ~4s rather than once.
  useEffect(() => {
    if (!refreshKey || !enabled || !INDEXER) return;
    let n = 0;
    const id = setInterval(() => {
      void load();
      if (++n >= 5) clearInterval(id);
    }, 800);
    return () => clearInterval(id);
  }, [refreshKey, enabled, load]);

  return state.gen === generation ? state.rows : EMPTY_TRADES;
}
