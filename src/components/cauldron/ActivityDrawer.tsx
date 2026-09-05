import { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import { formatEther } from "viem";
import type { LiveSwap, EventKind } from "@/hooks/useLiveSwaps";

/**
 * The Cauldron's grimoire — the full run of on-chain activity, on demand.
 *
 * The toasts are ephemeral by design: they announce and get out of the way. That
 * leaves nowhere to look when something scrolls past, which is exactly when you
 * want to look. This is the durable counterpart — the same websocket stream,
 * kept and scrollable, rather than a second source of data.
 *
 * Portalled to document.body. `position: fixed` resolves against the nearest
 * ancestor with a transform or backdrop-filter, and the cards have one, so a
 * drawer mounted inline would be pinned inside a card instead of the viewport.
 */
const SPELL: Record<EventKind, { icon: string; label: string; tone: string }> = {
  "buy":          { icon: "🐸", label: "gib tendies",     tone: "good" },
  "sell":         { icon: "📉", label: "paper hands",     tone: "bad" },
  "gacha-commit": { icon: "🔮", label: "crystals cast",   tone: "magic" },
  "gacha-win":    { icon: "✨", label: "fren forged",     tone: "magic" },
  "gacha-miss":   { icon: "💨", label: "spell fizzled",   tone: "neutral" },
  "perp-open":    { icon: "⚔️", label: "leverage cast",   tone: "good" },
  "perp-close":   { icon: "🛡️", label: "position closed", tone: "neutral" },
  "liquidation":  { icon: "💀", label: "REKT",            tone: "bad" },
  "badge":        { icon: "🏆", label: "liquidatoor",     tone: "magic" },
};

const short = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");

function ago(ts: number, now: number): string {
  const s = Math.max(0, Math.round((now - ts) / 1000));
  if (s < 5) return "now";
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  return `${Math.floor(s / 3600)}h`;
}

export function ActivityDrawer({ events, glyph }: { events: LiveSwap[]; glyph: string }) {
  const [open, setOpen] = useState(false);
  const [now, setNow] = useState(Date.now());

  // Only tick the clock while the drawer is open — a re-render every second
  // behind a closed panel is pure waste.
  useEffect(() => {
    if (!open) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    window.addEventListener("keydown", esc);
    return () => window.removeEventListener("keydown", esc);
  }, [open]);

  const unseen = useMemo(() => events.length, [events]);

  if (typeof document === "undefined") return null;

  return createPortal(
    <>
      <button
        className={`tc-grim__tab ${open ? "is-open" : ""}`}
        onClick={() => setOpen((v) => !v)}
        aria-label="Recent activity"
      >
        <span className="tc-grim__tab-icon">{open ? "›" : "‹"}</span>
        <span className="tc-grim__tab-text">ACTIVITY</span>
        {!open && unseen > 0 && <span className="tc-grim__tab-count">{unseen > 99 ? "99+" : unseen}</span>}
      </button>

      <aside className={`tc-grim ${open ? "is-open" : ""}`} aria-hidden={!open}>
        <header className="tc-grim__head">
          <div>
            <div className="tc-grim__eyebrow">the grimoire</div>
            <h3 className="tc-grim__title">Recent activity</h3>
          </div>
          <button className="tc-grim__close" onClick={() => setOpen(false)} aria-label="Close">✕</button>
        </header>

        <div className="tc-grim__list">
          {events.length === 0 && (
            <div className="tc-grim__empty">
              nothing yet — the cauldron is quiet.
              <span>Trades, spins and liquidations appear here the moment they land.</span>
            </div>
          )}
          {events.map((e) => {
            const s = SPELL[e.kind] ?? SPELL["gacha-miss"];
            const q = Number(formatEther(e.quoteWei));
            const isTrade = e.kind === "buy" || e.kind === "sell";
            const amount = isTrade
              ? `${q < 0.0001 ? "<0.0001" : q.toFixed(4)} ${glyph}`
              : e.detail;
            return (
              <a
                key={e.id}
                className={`tc-grim__row is-${s.tone}`}
                href={e.txHash ? `https://sepolia.etherscan.io/tx/${e.txHash}` : undefined}
                target="_blank"
                rel="noreferrer"
              >
                <span className="tc-grim__rune">{s.icon}</span>
                <span className="tc-grim__body">
                  <span className="tc-grim__label">{s.label}</span>
                  <span className="tc-grim__meta tc-mono">
                    {e.who ? short(e.who) : ""}
                  </span>
                </span>
                <span className="tc-grim__right">
                  {amount && <span className="tc-grim__amt tc-mono">{amount}</span>}
                  <span className="tc-grim__ago tc-mono">{ago(e.ts, now)}</span>
                </span>
              </a>
            );
          })}
        </div>
      </aside>
    </>,
    document.body,
  );
}
