import { useCallback, useRef, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/** One step of the launch, as it lands. */
export interface SeedFeedItem {
  id: string;
  /** started | base | poked | prime | complete | funded */
  kind: string;
  generation: number;
  /** Stream progress before/after this poke, 0..1. */
  from: number;
  to: number;
  /** Prime-buy tranche size, ETH. */
  ethInEth: number;
  tokenOut: string;
  tick: number | null;
  ts: number;
  block: number;
  txHash: string;
}

export interface SeedProgress {
  /** Fraction of the stream budget actually placed, 0..1. */
  placed: number;
  /** Where the schedule says it SHOULD be by now, 0..1. */
  target: number;
  active: boolean;
  complete: boolean;
  /** The two-sided full-range base is down (perps have spot depth). */
  basePlaced: boolean;
  /** Pokes so far this campaign. */
  pokes: number;
  /** Seconds until the window closes, or 0. */
  remaining: number;
  /** Treasury prime buy, in ETH. */
  primeBudgetEth: number;
  primeSpentEth: number;
  /** Newest first. */
  feed: SeedFeedItem[];
  /** Items that arrived since the previous poll — what to announce. */
  fresh: SeedFeedItem[];
}

const EMPTY: SeedProgress = {
  placed: 0, target: 0, active: false, complete: false, basePlaced: false,
  pokes: 0, remaining: 0, primeBudgetEth: 0, primeSpentEth: 0, feed: [], fresh: [],
};

/**
 * Live progress of the progressive liquidity seed, READ FROM PONDER.
 *
 * A generation does not launch with all its depth at once: the seeder streams it
 * in over a window. Nothing on the page showed that, so a fresh brew looked thin
 * and broken rather than filling.
 *
 * `placed` and `target` are deliberately separate. The stream only advances when
 * someone POKES it — either the keeper, or a swap through the hook's in-swap
 * nudge — so on a quiet pool the schedule runs ahead of what is actually
 * deployed. Showing one number would hide that the pool is waiting on flow,
 * which is the single most useful thing to know while staring at a new launch.
 *
 * THIS READS THE INDEXER, NOT THE CHAIN. It used to issue six `readContract`
 * calls against the seeder every 8 seconds from every open tab, which is exactly
 * the pattern that earns public-RPC 429s — and the 429 arrives as an empty
 * progress bar, i.e. it looks like the launch stalled. One cached `/seeding`
 * request serves the same data plus the event tape the notifications need.
 */
export function useSeedProgress(): SeedProgress {
  const [s, setS] = useState<SeedProgress>(EMPTY);
  // Ids already announced. Kept in a ref so re-renders never re-fire a toast,
  // and seeded on the FIRST response so opening the page mid-launch does not
  // replay the whole backlog as notifications.
  const seen = useRef<Set<string> | null>(null);

  const load = useCallback(async () => {
    if (!INDEXER) return;
    try {
      const res = await fetch(`${INDEXER}/seeding`, { signal: AbortSignal.timeout(10000) });
      if (!res.ok) return;
      const d = await res.json();
      const feed: SeedFeedItem[] = Array.isArray(d.feed) ? d.feed : [];

      let fresh: SeedFeedItem[] = [];
      if (seen.current === null) {
        seen.current = new Set(feed.map((f) => f.id)); // first load: catch up silently
      } else {
        fresh = feed.filter((f) => !seen.current!.has(f.id));
        for (const f of fresh) seen.current.add(f.id);
      }

      setS({
        placed: Number(d.placed) || 0,
        target: Number(d.target) || 0,
        active: !!d.active,
        complete: !!d.complete,
        basePlaced: !!d.basePlaced,
        pokes: Number(d.pokes) || 0,
        remaining: Number(d.remaining) || 0,
        primeBudgetEth: Number(d.prime?.budgetEth) || 0,
        primeSpentEth: Number(d.prime?.spentEth) || 0,
        feed,
        // Oldest first, so a burst announces in the order it happened.
        fresh: fresh.slice().reverse(),
      });
    } catch {
      // A deployment without a seeder (atomic launch) simply has no progress.
    }
  }, []);

  // 6s: pokes land on the keeper's cadence (~20s) and on swaps, so this is
  // comfortably ahead of the data without hammering a cached endpoint.
  usePoll(load, 6_000);
  return s;
}

/** Human sentence for a seeding step — used by the live notifications. */
export function seedFeedMessage(f: SeedFeedItem): string | null {
  switch (f.kind) {
    case "started":
      return "Cauldron ignited — liquidity is streaming in";
    case "base":
      return "Base liquidity placed — perps are live";
    case "poked": {
      const pct = Math.round(f.to * 100);
      const add = Math.round((f.to - f.from) * 100);
      return add > 0 ? `Liquidity +${add}% → ${pct}% deployed` : null;
    }
    case "prime":
      return `Treasury bought ${f.ethInEth.toFixed(4)} Ξ of the brew`;
    case "complete":
      return "Seeding complete — full depth deployed";
    default:
      return null;
  }
}
