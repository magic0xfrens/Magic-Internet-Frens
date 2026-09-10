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
  //  The gacha router's address and the floor's fee share, both from the same
  //  response — so the roll-up never has to guess either.
  const [router, setRouter] = useState<string | null>(null);
  const [legacyBps, setLegacyBps] = useState(0);
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
        gachaRouter?: string | null;
        legacyBps?: number;
        swaps?: Array<{ price: number; amountEth: number; isBuy: boolean; t: number; tx?: string; s?: string }>;
      };
      setRouter((d.gachaRouter ?? "").toLowerCase() || null);
      setLegacyBps(Number(d.legacyBps ?? 0));
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
          sender: r.s,
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
    const merged = [...byTx.values()].sort((a, b) => b.ts - a.ts);

    //  ── COLLAPSE CRYSTAL SPINS ───────────────────────────────────────────
    //  Every roll is a real buy through the gacha router, so each one arrived as
    //  its own "Bought $TOKEN" line — nine consecutive 0.0072 Ξ rows that buried
    //  the organic trades between them. They are rolled into ONE entry carrying
    //  the spin count, the volume they generated and the share of it routed to
    //  the NFT floor, which is the thing worth reading anyway.
    //
    //  Rolled up per RUN, not globally: consecutive spins collapse, but a spin
    //  an hour later starts a new row, so the feed stays a timeline rather than
    //  a single ever-growing total.
    if (!router) return merged.slice(0, 80);
    const out: LiveSwap[] = [];
    for (const e of merged) {
      const isSpin = (e.kind === "buy" || e.kind === "sell")
        && !!e.sender && e.sender.toLowerCase() === router;
      const prev = out[out.length - 1];
      if (isSpin && prev?.kind === "gacha-volume") {
        prev.spins = (prev.spins ?? 0) + 1;
        prev.rollupWei = (prev.rollupWei ?? 0n) + e.quoteWei;
        //  The floor's cut is legacyBps of the POST-GUILD fee, but the feed does
        //  not see the guild split — so this is the fee-share of volume, which
        //  is the honest upper bound and is labelled as "to floor" not "exact".
        prev.floorWei = (prev.rollupWei * BigInt(legacyBps)) / 10_000n;
        continue;
      }
      if (isSpin) {
        out.push({
          ...e, kind: "gacha-volume", spins: 1, rollupWei: e.quoteWei,
          floorWei: (e.quoteWei * BigInt(legacyBps)) / 10_000n,
        });
        continue;
      }
      out.push(e);
    }
    return out.slice(0, 80);
  }, [indexed, live, router, legacyBps]);
}
