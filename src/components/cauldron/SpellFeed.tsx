import { useEffect, useRef, useState } from "react";
import { formatEther } from "viem";
import type { LiveSwap, EventKind } from "@/hooks/useLiveSwaps";

/**
 * The Cauldron's live spellbook — every on-chain action, announced as it lands.
 *
 * Fed entirely by the websocket, so it fires the moment a block is seen rather
 * than waiting for the indexer. It is a NOTICEBOARD, not a ledger: entries fade,
 * and the tape and charts below remain the durable, indexed record. If the two
 * ever disagreed, the indexer is right and this has already gone.
 *
 * Top-right, released one at a time. A block can carry a dozen events — the
 * gacha router alone fires a commit, a swap and several ticket resolutions — and
 * dumping them together reads as one thing happening instead of a busy cauldron.
 */
const SPELL: Record<EventKind, { icon: string; label: string; tone: "good" | "bad" | "magic" | "neutral" }> = {
  "buy":          { icon: "🐸", label: "gib tendies",   tone: "good" },
  "sell":         { icon: "📉", label: "paper hands",   tone: "bad" },
  "gacha-commit": { icon: "🔮", label: "crystals cast", tone: "magic" },
  "gacha-win":    { icon: "✨", label: "fren forged",   tone: "magic" },
  "gacha-miss":   { icon: "💨", label: "spell fizzled", tone: "neutral" },
  "perp-open":    { icon: "⚔️", label: "leverage cast", tone: "good" },
  "perp-close":   { icon: "🛡️", label: "position closed", tone: "neutral" },
  "liquidation":  { icon: "💀", label: "REKT",          tone: "bad" },
  "badge":        { icon: "🏆", label: "liquidatoor",   tone: "magic" },
};

const short = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");

export function SpellFeed({ events, glyph }: { events: LiveSwap[]; glyph: string }) {
  const [visible, setVisible] = useState<LiveSwap[]>([]);
  const queue = useRef<LiveSwap[]>([]);
  const seen = useRef<Set<number>>(new Set());
  const draining = useRef(false);

  useEffect(() => {
    // Oldest first so a burst replays in the order it actually happened.
    const fresh = [...events].reverse().filter((e) => !seen.current.has(e.id));
    if (fresh.length === 0) return;
    for (const e of fresh) seen.current.add(e.id);
    queue.current.push(...fresh);
    if (draining.current) return;
    draining.current = true;

    const pop = () => {
      const next = queue.current.shift();
      if (!next) { draining.current = false; return; }
      setVisible((v) => [next, ...v].slice(0, 5));
      // Each ages out on its own timer, so a burst drains steadily rather than
      // the whole stack vanishing at once.
      setTimeout(() => setVisible((v) => v.filter((x) => x.id !== next.id)), 7000);
      // Tighter when a backlog is waiting: a busy block should feel busy.
      setTimeout(pop, queue.current.length > 3 ? 150 : 300);
    };
    pop();
  }, [events]);

  if (visible.length === 0) return null;

  return (
    <div className="tc-spell" aria-live="polite">
      {visible.map((e, i) => {
        const s = SPELL[e.kind] ?? SPELL["gacha-miss"];
        const q = Number(formatEther(e.quoteWei));
        const amount = e.kind === "buy" || e.kind === "sell"
          ? `${q < 0.0001 ? "<0.0001" : q.toFixed(4)} ${glyph}`
          : e.detail;
        return (
          <div
            key={e.id}
            className={`tc-spell__row is-${s.tone}`}
            // Older entries recede so the stack reads as depth, not a wall.
            style={{ opacity: Math.max(0.32, 1 - i * 0.17) }}
          >
            <span className="tc-spell__rune">{s.icon}</span>
            <span className="tc-spell__body">
              <span className="tc-spell__label">{s.label}</span>
              {amount && <span className="tc-spell__amt tc-mono">{amount}</span>}
            </span>
            {e.who && <span className="tc-spell__who tc-mono">{short(e.who)}</span>}
          </div>
        );
      })}
    </div>
  );
}
