import { useEffect, useRef, useState } from "react";
import { formatEther } from "viem";
import type { LiveSwap } from "@/hooks/useLiveSwaps";

/**
 * The live trade feed — swaps painted the instant their block is seen.
 *
 * RELEASED ONE AT A TIME, deliberately. A block can carry a dozen swaps (the
 * gacha router alone fires a buy and a sell together), and dumping them into the
 * DOM at once reads as a single event rather than a busy market. A short stagger
 * turns the same data into a stream, which is what it actually is.
 *
 * This is the optimistic half of the pair: the socket paints immediately, the
 * indexer's authoritative numbers land in the tape and candles a beat later. It
 * never writes to either — if they disagreed, the indexer is right and this has
 * already faded.
 */
export function LiveSwapToast({ swaps, symbol, glyph }: {
  swaps: LiveSwap[];
  symbol: string;
  glyph: string;
}) {
  const [visible, setVisible] = useState<LiveSwap[]>([]);
  const queued = useRef<LiveSwap[]>([]);
  const seen = useRef<Set<number>>(new Set());
  const draining = useRef(false);

  useEffect(() => {
    // Oldest first, so a burst plays in the order it happened.
    const fresh = [...swaps].reverse().filter((s) => !seen.current.has(s.id));
    if (fresh.length === 0) return;
    for (const s of fresh) seen.current.add(s.id);
    queued.current.push(...fresh);

    if (draining.current) return;
    draining.current = true;

    const pop = () => {
      const next = queued.current.shift();
      if (!next) { draining.current = false; return; }

      setVisible((v) => [next, ...v].slice(0, 6));
      // Each entry ages out on its OWN timer, so a burst drains steadily
      // instead of the whole stack blinking out together.
      setTimeout(() => setVisible((v) => v.filter((x) => x.id !== next.id)), 6500);

      // Faster when a backlog is waiting: a busy block should feel busy, not
      // like a slow queue.
      setTimeout(pop, queued.current.length > 3 ? 140 : 260);
    };
    pop();
  }, [swaps]);

  if (visible.length === 0) return null;

  return (
    <div className="tc-feed" aria-live="polite">
      {visible.map((s, i) => {
        const q = Number(formatEther(s.quoteWei));
        const tok = Number(formatEther(s.tokenWei));
        return (
          <div
            key={s.id}
            className={`tc-feed__row ${s.isBuy ? "is-buy" : "is-sell"}`}
            // Older rows recede so the stack reads as depth rather than a wall
            // of equal-weight boxes.
            style={{ opacity: Math.max(0.3, 1 - i * 0.15) }}
          >
            <span className="tc-feed__glyph">{s.isBuy ? "▲" : "▼"}</span>
            <span className="tc-feed__side">{s.isBuy ? "BUY" : "SELL"}</span>
            <span className="tc-feed__amt tc-mono">
              {q < 0.0001 ? "<0.0001" : q.toFixed(4)}
              <em>{glyph || symbol}</em>
            </span>
            {tok > 0 && (
              <span className="tc-feed__tok tc-mono">
                {tok >= 1e6 ? `${(tok / 1e6).toFixed(1)}M` : tok >= 1e3 ? `${(tok / 1e3).toFixed(1)}K` : tok.toFixed(0)}
              </span>
            )}
          </div>
        );
      })}
    </div>
  );
}
