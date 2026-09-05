import { useEffect, useState } from "react";
import { formatEther } from "viem";
import type { LiveSwap } from "@/hooks/useLiveSwaps";

/**
 * A swap notification that appears the instant the block is seen.
 *
 * The page is otherwise entirely indexer-driven, so a trade only surfaces on the
 * next poll — after Ponder has indexed the block. That gap is what makes the
 * chart feel dead even while the pool is busy.
 *
 * This is the OPTIMISTIC half of the pair: the websocket paints a toast
 * immediately from the raw log, and the indexer's authoritative numbers land in
 * the tape and candles a moment later. It never writes to either — if the two
 * ever disagreed, the indexer is right and the toast has already faded.
 */
export function LiveSwapToast({ swap, symbol, glyph }: {
  swap: LiveSwap | null;
  symbol: string;
  glyph: string;
}) {
  const [shown, setShown] = useState<LiveSwap[]>([]);

  useEffect(() => {
    if (!swap) return;
    setShown((s) => [swap, ...s].slice(0, 3));
    // Toasts are ambient, not a log — they say "something just happened" and
    // then get out of the way. The tape below is the durable record.
    const t = setTimeout(() => {
      setShown((s) => s.filter((x) => x.id !== swap.id));
    }, 5200);
    return () => clearTimeout(t);
  }, [swap]);

  if (shown.length === 0) return null;

  return (
    <div className="tc-toasts" aria-live="polite">
      {shown.map((s) => {
        const size = Number(formatEther(s.quoteWei));
        return (
          <div key={s.id} className={`tc-toast ${s.isBuy ? "buy" : "sell"}`}>
            <span className="tc-toast__dot" />
            <span className="tc-mono">
              {s.isBuy ? "BUY" : "SELL"}{" "}
              {size < 0.0001 ? "<0.0001" : size.toFixed(4)} {glyph || symbol}
            </span>
            <span className="tc-mono tc-toast__live">live</span>
          </div>
        );
      })}
    </div>
  );
}
