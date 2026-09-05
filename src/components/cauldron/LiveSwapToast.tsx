import { useEffect, useMemo, useRef, useState } from "react";
import { formatEther } from "viem";
import type { LiveSwap } from "@/hooks/useLiveSwaps";

/**
 * The live trade feed — swaps painted the instant their block is seen.
 *
 * The page is otherwise indexer-driven, so a trade only surfaces on the next
 * poll, after Ponder has indexed the block. That gap is what makes a busy pool
 * feel dead. This is the optimistic half: the websocket paints immediately, the
 * indexer's authoritative numbers land in the tape and candles a beat later.
 *
 * It NEVER writes to either. If the two disagreed, the indexer is right and this
 * has already faded.
 *
 * Positioned bottom-LEFT on purpose. Bottom-right sat on top of the stat cards,
 * and a feed that covers the numbers it is reporting on is worse than no feed.
 */
export function LiveSwapToast({ swaps, symbol, glyph }: {
  swaps: LiveSwap[];
  symbol: string;
  glyph: string;
}) {
  // Which ids are still visible. Each toast ages out on its own timer, so a
  // burst does not reset the clock on the ones already showing.
  const [live, setLive] = useState<number[]>([]);
  const seen = useRef<Set<number>>(new Set());

  useEffect(() => {
    const fresh = swaps.filter((s) => !seen.current.has(s.id));
    if (fresh.length === 0) return;

    const timers: ReturnType<typeof setTimeout>[] = [];
    for (const s of fresh) {
      seen.current.add(s.id);
      setLive((l) => [s.id, ...l].slice(0, 6));
      // Staggered dismissal keeps a burst readable instead of clearing it all
      // at once — the feed drains rather than blinking out.
      timers.push(setTimeout(() => {
        setLive((l) => l.filter((id) => id !== s.id));
      }, 6000));
    }
    return () => timers.forEach(clearTimeout);
  }, [swaps]);

  const shown = useMemo(
    () => live.map((id) => swaps.find((s) => s.id === id)).filter(Boolean) as LiveSwap[],
    [live, swaps],
  );

  if (shown.length === 0) return null;

  return (
    <div className="tc-feed" aria-live="polite">
      {shown.map((s, i) => {
        const q = Number(formatEther(s.quoteWei));
        const tok = Number(formatEther(s.tokenWei));
        return (
          <div
            key={s.id}
            className={`tc-feed__row ${s.isBuy ? "is-buy" : "is-sell"}`}
            // Older entries recede rather than being cut off, so the stack reads
            // as depth instead of a wall of equal-weight boxes.
            style={{ opacity: Math.max(0.35, 1 - i * 0.16) }}
          >
            <span className="tc-feed__pulse" />
            <span className="tc-feed__side">{s.isBuy ? "BUY" : "SELL"}</span>
            <span className="tc-feed__amt tc-mono">
              {q < 0.0001 ? "<0.0001" : q.toFixed(4)}
              <em>{glyph || symbol}</em>
            </span>
            {tok > 0 && (
              <span className="tc-feed__tok tc-mono">
                {tok >= 1e6 ? `${(tok / 1e6).toFixed(2)}M` : tok >= 1e3 ? `${(tok / 1e3).toFixed(1)}K` : tok.toFixed(0)}
              </span>
            )}
          </div>
        );
      })}
    </div>
  );
}
