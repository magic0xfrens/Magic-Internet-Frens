import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { formatEther } from "viem";
import type { LiveSwap, EventKind } from "@/hooks/useLiveSwaps";

/**
 * The Cauldron's grimoire — the full run of on-chain activity, on demand.
 *
 * Rows lead with what ACTUALLY happened ("Bought", "Sold", "Fren forged") and
 * carry the fren-speak underneath as flavour. An earlier version showed only the
 * flavour, which was charming and unreadable: "gib tendies · 0.25 Ξ" does not
 * tell you a purchase occurred.
 *
 * Clicking a row expands it in place rather than jumping straight to Etherscan.
 * A link that leaves the page is the wrong default for a glance — most of the
 * time the question is "what was that?", not "show me the raw transaction".
 */
const SPELL: Record<EventKind, { icon: string; verb: string; flavour: string; tone: string }> = {
  "buy":          { icon: "🐸", verb: "Bought",          flavour: "gib tendies",     tone: "good" },
  "sell":         { icon: "📉", verb: "Sold",            flavour: "paper hands",     tone: "bad" },
  "gacha-commit": { icon: "🔮", verb: "Crystals cast",   flavour: "the wheel spins", tone: "magic" },
  "gacha-win":    { icon: "✨", verb: "Fren forged",     flavour: "a wizard appears", tone: "magic" },
  "gacha-miss":   { icon: "💨", verb: "Spell fizzled",   flavour: "no fren this time", tone: "neutral" },
  "perp-open":    { icon: "⚔️", verb: "Leverage opened", flavour: "brave or foolish", tone: "good" },
  "perp-close":   { icon: "🛡️", verb: "Position closed", flavour: "lives to trade on", tone: "neutral" },
  "liquidation":  { icon: "💀", verb: "Liquidated",      flavour: "REKT",            tone: "bad" },
  "badge":        { icon: "🏆", verb: "Liquidatoor badge", flavour: "spoils of war", tone: "magic" },
};

const short = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");

function ago(ts: number, now: number): string {
  const s = Math.max(0, Math.round((now - ts) / 1000));
  if (s < 5) return "now";
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  return `${Math.floor(s / 3600)}h`;
}

export function ActivityDrawer({ events, glyph, ticker }: {
  events: LiveSwap[];
  glyph: string;
  ticker: string;
}) {
  const [open, setOpen] = useState(false);
  const [expanded, setExpanded] = useState<number | null>(null);
  const [now, setNow] = useState(Date.now());

  // Only tick the clock while open — a re-render per second behind a closed
  // panel is pure waste.
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
        {!open && events.length > 0 && (
          <span className="tc-grim__tab-count">{events.length > 99 ? "99+" : events.length}</span>
        )}
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
            const amount = q > 0
              ? `${q < 0.0001 ? "<0.0001" : q.toFixed(4)} ${glyph}`
              : undefined;
            const isOpen = expanded === e.id;

            return (
              <div key={e.id} className={`tc-grim__item ${isOpen ? "is-expanded" : ""}`}>
                <button
                  className={`tc-grim__row is-${s.tone}`}
                  onClick={() => setExpanded(isOpen ? null : e.id)}
                  aria-expanded={isOpen}
                >
                  <span className="tc-grim__rune">{s.icon}</span>
                  <span className="tc-grim__body">
                    <span className="tc-grim__verb">
                      {s.verb}
                      {isTrade && <em> ${ticker}</em>}
                    </span>
                    <span className="tc-grim__flavour">{s.flavour}</span>
                  </span>
                  <span className="tc-grim__right">
                    {amount && <span className="tc-grim__amt tc-mono">{amount}</span>}
                    <span className="tc-grim__ago tc-mono">{ago(e.ts, now)}</span>
                  </span>
                  <span className="tc-grim__chev">{isOpen ? "▴" : "▾"}</span>
                </button>

                {isOpen && (
                  <div className="tc-grim__detail">
                    {isTrade && e.price > 0 && (
                      <Row k="Price" v={`${(e.price * 1e9).toFixed(3)} gwei`} />
                    )}
                    {isTrade && e.tokenWei > 0n && (
                      <Row k={`${ticker} moved`} v={fmtToken(Number(formatEther(e.tokenWei)))} />
                    )}
                    {amount && <Row k={e.kind === "buy" ? "Paid" : "Received"} v={amount} />}
                    {e.detail && !isTrade && <Row k="Detail" v={e.detail} />}
                    {e.who && <Row k="Wallet" v={short(e.who)} mono />}
                    <Row k="When" v={new Date(e.ts).toLocaleTimeString()} mono />
                    {e.txHash && (
                      <a
                        className="tc-grim__tx"
                        href={`https://sepolia.etherscan.io/tx/${e.txHash}`}
                        target="_blank"
                        rel="noreferrer"
                      >
                        View transaction ↗
                      </a>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </aside>
    </>,
    document.body,
  );
}

function Row({ k, v, mono }: { k: string; v: string; mono?: boolean }) {
  return (
    <div className="tc-grim__kv">
      <span>{k}</span>
      <span className={mono ? "tc-mono" : ""}>{v}</span>
    </div>
  );
}

function fmtToken(n: number): string {
  if (n >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return n.toFixed(0);
}
