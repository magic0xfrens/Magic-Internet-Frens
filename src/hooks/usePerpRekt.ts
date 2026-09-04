import { useEffect, useRef, useState } from "react";
import { useAccount } from "wagmi";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { PERP_LIVE } from "@/config/perp";

export interface RektEvent {
  id: string;
  isLong: boolean;
  leverage: number;
  collateralEth: number;
  pnlEth: number;
  closedAt: number;
}

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * Watches the connected wallet's LIQUIDATIONS via Ponder (/perp-rekt/:trader) and
 * surfaces a NEW one (that happened while you're watching) exactly once — so the
 * UI can pop a "RIP" PnL card the moment you get liquidated on-screen. Positions
 * liquidated before this session are baselined out (no spam on load).
 */
export function usePerpRekt(enabled: boolean, intervalMs = 6000): { latest: RektEvent | null; ack: () => void } {
  const { address } = useAccount();
  const [latest, setLatest] = useState<RektEvent | null>(null);
  const seen = useRef<Set<string>>(new Set());
  const baselined = useRef(false);

  useEffect(() => { seen.current = new Set(); baselined.current = false; setLatest(null); }, [address]);

  useEffect(() => {
    if (!enabled || !PERP_LIVE || !address || !INDEXER) return;
    let alive = true;
    const load = async () => {
      try {
        const res = await fetch(`${INDEXER}/perp-rekt/${address}`, { signal: AbortSignal.timeout(6000) });
        if (!res.ok) return;
        const d = await res.json() as { rekt?: RektEvent[] };
        if (!alive) return;
        const rekt = d.rekt ?? [];
        // First fetch = baseline (mark all existing as seen, don't pop old ones).
        if (!baselined.current) {
          for (const r of rekt) seen.current.add(r.id);
          baselined.current = true;
          return;
        }
        // Newest unseen liquidation → pop it.
        for (const r of rekt) {
          if (!seen.current.has(r.id)) {
            seen.current.add(r.id);
            setLatest(r);
            break;
          }
        }
      } catch { /* keep polling */ }
    };
    load();
    // Pause while the tab is backgrounded, refresh on return: an idle tab
    // should cost nothing. Mirrors usePoll.
    let t: ReturnType<typeof setInterval> | null = setInterval(load, intervalMs);
    const onVis = () => {
      if (document.hidden) { if (t) { clearInterval(t); t = null; } }
      else if (!t) { load(); t = setInterval(load, intervalMs); }
    };
    document.addEventListener("visibilitychange", onVis);
    return () => {
      alive = false;
      if (t) clearInterval(t);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [enabled, address, intervalMs]);

  return { latest, ack: () => setLatest(null) };
}
