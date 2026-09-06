import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
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
 * Top-right of the PAGE, released one at a time. A block can carry a dozen
 * events — the gacha router alone fires a commit, a swap and several ticket
 * resolutions — and dumping them together reads as one thing happening instead
 * of a busy cauldron.
 *
 * RENDERED THROUGH A PORTAL, which is not incidental. `position: fixed` is
 * resolved against the nearest ancestor with a transform, filter or
 * backdrop-filter — and `.tc-card` has one. Mounted inline it was therefore
 * pinned to the chart card's top-right rather than the viewport's, which is
 * exactly the bug it looked like. A portal to document.body escapes every such
 * ancestor by construction.
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
  "revealed":     { icon: "🧙", label: "fren revealed", tone: "magic" },
};

const short = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");

/** One card: either a single event, or several of the same kind merged. */
interface Entry {
  id: number;
  kind: EventKind;
  count: number;
  quoteWei: bigint;
  who?: string;
  detail?: string;
}

export function SpellFeed({ events, glyph }: { events: LiveSwap[]; glyph: string }) {
  const [visible, setVisible] = useState<Entry[]>([]);
  const pending = useRef<LiveSwap[]>([]);
  const seen = useRef<Set<number>>(new Set());
  const flushAt = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const fresh = [...events].reverse().filter((e) => !seen.current.has(e.id));
    if (fresh.length === 0) return;
    for (const e of fresh) seen.current.add(e.id);
    pending.current.push(...fresh);

    //  COALESCE, don't stream.
    //
    //  One gacha spin emits a commit, a swap and a dozen ticket resolutions in a
    //  SINGLE block. Announcing each separately produced a wall of near-identical
    //  cards flashing past too fast to read — technically accurate and useless.
    //
    //  So a short window is collected and same-kind events are merged into one
    //  card with a count: "7× fren forged" instead of seven cards. Bursts read as
    //  one event because that is what they are, and a genuinely isolated trade
    //  still shows on its own.
    if (flushAt.current) return;
    flushAt.current = setTimeout(() => {
      flushAt.current = null;
      const batch = pending.current;
      pending.current = [];
      if (batch.length === 0) return;

      const groups = new Map<EventKind, LiveSwap[]>();
      for (const e of batch) {
        const g = groups.get(e.kind) ?? [];
        g.push(e);
        groups.set(e.kind, g);
      }

      const merged: Entry[] = [...groups.entries()].map(([kind, list]) => {
        const head = list[list.length - 1];
        // Buys and sells sum their size; the total is the interesting number.
        const totalWei = list.reduce((a, e) => a + e.quoteWei, 0n);
        return {
          id: head.id,
          kind,
          count: list.length,
          quoteWei: totalWei,
          who: list.length === 1 ? head.who : undefined,
          detail: list.length === 1 ? head.detail : undefined,
        };
      });

      setVisible((v) => [...merged.reverse(), ...v].slice(0, 3));
      for (const m of merged) {
        setTimeout(() => setVisible((v) => v.filter((x) => x.id !== m.id)), 10000);
      }
    }, 900); // long enough to catch a block's worth, short enough to feel live
  }, [events]);

  if (visible.length === 0) return null;
  if (typeof document === "undefined") return null;

  return createPortal(
    <div className="tc-spell" aria-live="polite">
      {visible.map((e, i) => {
        const s = SPELL[e.kind] ?? SPELL["gacha-miss"];
        const q = Number(formatEther(e.quoteWei));
        const isTrade = e.kind === "buy" || e.kind === "sell";
        const amount = isTrade
          ? `${q < 0.0001 ? "<0.0001" : q.toFixed(4)} ${glyph}`
          : e.detail;
        return (
          <div
            key={e.id}
            className={`tc-spell__row is-${s.tone}`}
            style={{ opacity: Math.max(0.4, 1 - i * 0.18) }}
          >
            <span className="tc-spell__rune">{s.icon}</span>
            <span className="tc-spell__body">
              <span className="tc-spell__label">
                {/* A count only appears when there IS one — a lone trade should
                    not read as "1x". */}
                {e.count > 1 && <b className="tc-spell__x">{e.count}×</b>}
                {s.label}
              </span>
              {amount && <span className="tc-spell__amt tc-mono">{amount}</span>}
            </span>
            {e.who && <span className="tc-spell__who tc-mono">{short(e.who)}</span>}
          </div>
        );
      })}
    </div>,
    document.body,
  );
}
