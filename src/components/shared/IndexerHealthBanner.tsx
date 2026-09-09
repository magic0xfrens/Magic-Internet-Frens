import { useIndexerHealth } from "@/hooks/useIndexerHealth";

/**
 * A single, app-wide "this data may not be true" banner.
 *
 * ── Why this is global and not per-hook (audit A-3) ────────────────────────
 * Nineteen modules read the indexer — dividends, perp positions, the vault,
 * collection floors, candles, the trade tape, presale state — and exactly ONE
 * of them consulted the health signal. The rest do not error when the indexer
 * has diverged; they return empty, and the page renders a confident, wrong,
 * empty answer. That is how a sold-out presale displayed 0 / 1111.
 *
 * {useIndexerHealth} already says as much in its own header: the problem
 * "cannot be fixed hook by hook — several of them genuinely cannot fall back
 * (you cannot rebuild an hour of candles from one RPC call)", so the page has to
 * say when its data is untrustworthy. That was the right conclusion; the banner
 * was just mounted inside one route, so every other page kept rendering wrong
 * numbers silently. Hoisting it to the shell is what makes the design match its
 * stated intent.
 *
 * Deliberately additive: route-level guards that give better, more specific
 * advice — PerpPanel's "verify on the explorer before trading" — stay where they
 * are. This is the floor, not a replacement.
 */
export function IndexerHealthBanner() {
  const health = useIndexerHealth();
  if (!health.degraded) return null;

  return (
    <>
      {/* Carried with the component rather than left in TheCauldron's style
          block, so the banner is styled on every route it can now appear on. */}
      <style>{`
    .tc-health { position: fixed; left: 50%; transform: translateX(-50%); bottom: 16px; z-index: 80; display: flex; align-items: center; gap: 8px; padding: 7px 14px; border-radius: 999px; font-size: 11px; background: rgba(20,14,8,0.94); border: 1px solid rgba(246,200,106,0.3); color: #f6d9a0; backdrop-filter: blur(12px); box-shadow: 0 6px 22px rgba(0,0,0,0.5); }
    .tc-health.is-down { border-color: rgba(255,86,96,0.35); color: #ffc9cd; background: rgba(28,10,12,0.94); }
    .tc-health__dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; animation: tcHealthPulse 1.4s ease-in-out infinite; }
    .tc-health b { font-weight: 500; opacity: 0.6; }
    @keyframes tcHealthPulse { 0%,100% { opacity: 1; } 50% { opacity: 0.25; } }
      `}</style>
      <div className={`tc-health is-${health.state}`} role="status" aria-live="polite">
        <span className="tc-health__dot" />
        <span className="tc-mono">
          {health.state === "down" ? "indexer unreachable" : health.reason}
          {" · "}
          <b>live prices still on-chain</b>
        </span>
      </div>
    </>
  );
}
