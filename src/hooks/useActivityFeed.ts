import { useCallback, useMemo, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";
import type { LiveSwap } from "@/hooks/useLiveSwaps";

/**
 * Activity history: INDEXED for what already happened, LIVE for what just did.
 *
 * The same split the chart uses. The websocket alone only knows what it has
 * personally witnessed, so a refresh emptied the drawer and opening the page
 * mid-session showed nothing — the indexer is what makes the history durable.
 * The socket is what makes it immediate.
 *
 * Live entries win on collision. They arrive first, and once Ponder indexes the
 * same transaction the two describe one event; keying on the tx hash means the
 * handover replaces rather than duplicates.
 */
export function useActivityFeed(generation: number, live: LiveSwap[]): LiveSwap[] {
  const [indexed, setIndexed] = useState<LiveSwap[]>([]);

  const load = useCallback(async () => {
    const base = CAULDRON_INDEXER;
    if (!base || !generation) return;
    try {
      const res = await fetch(`${base}/recent/${generation}?limit=60`, {
        signal: AbortSignal.timeout(7000),
      });
      if (!res.ok) return;
      const d = (await res.json()) as {
        swaps?: Array<{ price: number; amountEth: number; isBuy: boolean; t: number; tx?: string }>;
      };
      const rows = (d.swaps ?? [])
        .filter((r) => r.t > 0 && Number.isFinite(r.amountEth))
        .map((r, i): LiveSwap => ({
          // Negative ids so they can never collide with the live counter.
          id: -(i + 1),
          key: r.tx ?? `idx:${r.t}:${i}`,
          kind: r.isBuy ? "buy" : "sell",
          isBuy: r.isBuy,
          // The indexer reports ETH as a float; the feed formats from wei.
          quoteWei: BigInt(Math.round(r.amountEth * 1e18)),
          tokenWei: 0n,
          price: r.price,
          // `t` is seconds on-chain; everything downstream works in ms.
          ts: r.t * 1000,
          txHash: r.tx ?? "",
        }));
      setIndexed(rows);
    } catch {
      // Keep whatever we have — a blip should not empty the drawer.
    }
  }, [generation]);

  // Slow on purpose: the websocket already delivers anything new within a
  // block. This only has to cover a refresh and repair a missed socket frame.
  usePoll(load, 30_000, !!generation);

  return useMemo(() => {
    const byTx = new Map<string, LiveSwap>();
    // Indexed first so a live entry for the same tx overwrites it.
    for (const e of indexed) if (e.key) byTx.set(e.key.toLowerCase(), e);
    for (const e of live) {
      const k = (e.txHash || e.key).toLowerCase();
      // A tx can emit several DIFFERENT events (a gacha spin is one tx with a
      // commit and many resolutions), so the key includes the kind — otherwise
      // merging by tx alone would silently drop all but one of them.
      byTx.set(`${k}:${e.kind}`, e);
      byTx.delete(k);
    }
    return [...byTx.values()].sort((a, b) => b.ts - a.ts).slice(0, 80);
  }, [indexed, live]);
}
