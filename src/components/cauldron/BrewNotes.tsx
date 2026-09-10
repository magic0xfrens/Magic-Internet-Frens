import { useCallback, useRef, useState } from "react";
import { createPortal } from "react-dom";

/**
 * BREW NOTES — the Cauldron's running commentary.
 *
 *  ── WHY THIS REPLACED THE OLD TOAST ────────────────────────────────────────
 *  The previous notice was a single fixed div at `z-index: 50`. Two things were
 *  wrong with it, and they compounded at exactly the wrong moment.
 *
 *  1. IT LOST THE STACKING FIGHT. The presale modal's overlay sits at
 *     `z-index: 10000`. Ignition hands you from that modal to the chart, so the
 *     seeding notices fired while the overlay was still up — and rendered
 *     underneath a full-screen backdrop-blurred sheet. Invisible by
 *     construction, on the one screen they exist for.
 *  2. IT HELD ONE MESSAGE. Seeding arrives in bursts: the campaign starts, the
 *     base lands, a tranche buys, the stream steps. Each new line overwrote the
 *     last within a frame, so a burst of five events read as one flicker.
 *
 *  ── THE AESTHETIC ──────────────────────────────────────────────────────────
 *  These are instrument readouts from a working apparatus, not app toasts. Dark
 *  glass over the void, a single hairline in the signal's own colour, mono
 *  numerals, and a reaction glyph that pulses while its stage is live. Cards
 *  surface from the bottom and stack upward — older ones recede in scale and
 *  opacity, so depth does the ordering rather than a timestamp.
 */

export type BrewKind = "liquidity" | "treasury" | "ignite" | "done" | "ok" | "err";

export interface BrewNote {
  id: number;
  kind: BrewKind;
  title: string;
  /** Small mono caption under the title — a number, a stage, a ticker. */
  sub?: string;
  /** 0..1 — renders the fill rail. Omit for a plain note. */
  progress?: number;
}

const GLYPH: Record<BrewKind, string> = {
  liquidity: "◈",
  treasury: "◆",
  ignite: "✧",
  done: "✦",
  ok: "●",
  err: "▲",
};

const HUE: Record<BrewKind, string> = {
  liquidity: "#d5fd51", // lime — the hero accent, used for depth arriving
  treasury: "#f5c542",  // gold — the treasury spending its own coin
  ignite: "#7c5cfc",    // violet — the summon itself
  done: "#3ddc84",      // green — a stage closing out
  ok: "#3ddc84",
  err: "#ff4d6d",
};

/** How long each kind stays up. Failures linger; progress steps do not. */
const TTL: Record<BrewKind, number> = {
  liquidity: 5200, treasury: 6000, ignite: 7000, done: 7000, ok: 5200, err: 9000,
};

const MAX_VISIBLE = 4;

let nextNoteId = 1;

/**
 * The queue. Kept outside the render tree so a burst of events in one tick does
 * not fight React's batching — each push is its own entry with its own timer.
 */
export function useBrewNotes() {
  const [notes, setNotes] = useState<BrewNote[]>([]);
  const timers = useRef<number[]>([]);

  const push = useCallback((kind: BrewKind, title: string, sub?: string, progress?: number) => {
    const id = nextNoteId++;
    setNotes((prev) => {
      const next = [...prev, { id, kind, title, sub, progress }];
      // Trim from the FRONT: the oldest is the one that has had its time.
      return next.length > MAX_VISIBLE ? next.slice(next.length - MAX_VISIBLE) : next;
    });
    const t = window.setTimeout(() => {
      setNotes((prev) => prev.filter((n) => n.id !== id));
    }, TTL[kind]);
    timers.current.push(t);
  }, []);

  const clear = useCallback(() => {
    timers.current.forEach(window.clearTimeout);
    timers.current = [];
    setNotes([]);
  }, []);

  return { notes, push, clear };
}

export default function BrewNotes({ notes }: { notes: BrewNote[] }) {
  if (typeof document === "undefined") return null;

  return createPortal(
    <>
      <div className="bn" role="status" aria-live="polite">
        {notes.map((n, i) => {
          // Depth: the newest card is front-most and full size; each older one
          // steps back. `i` counts from the oldest, so invert it.
          const back = notes.length - 1 - i;
          return (
            <div
              key={n.id}
              className={`bn__card bn__card--${n.kind}`}
              style={{
                // Custom props so the CSS can tint every layer from one value.
                ["--hue" as string]: HUE[n.kind],
                ["--back" as string]: String(back),
                zIndex: 100 - back,
              }}
            >
              <span className="bn__ember" aria-hidden />
              <span className="bn__glyph" aria-hidden>{GLYPH[n.kind]}</span>
              <span className="bn__body">
                <span className="bn__title">{n.title}</span>
                {n.sub && <span className="bn__sub">{n.sub}</span>}
              </span>
              {n.progress != null && (
                <span className="bn__rail" aria-hidden>
                  <span
                    className="bn__fill"
                    style={{ width: `${Math.max(0, Math.min(1, n.progress)) * 100}%` }}
                  />
                </span>
              )}
            </div>
          );
        })}
      </div>

      <style>{`
        .bn {
          position: fixed; right: 22px; bottom: 22px;
          display: flex; flex-direction: column; align-items: flex-end; gap: 9px;
          /* ABOVE THE MODAL (10000). The old notice sat at 50 and spent the whole
             ignition hand-off underneath the presale overlay. */
          z-index: 10001;
          pointer-events: none;
          max-width: min(92vw, 344px);
        }

        .bn__card {
          position: relative; display: flex; align-items: center; gap: 11px;
          width: 100%; padding: 11px 14px 11px 13px;
          border-radius: 12px; overflow: hidden;
          background:
            /* faint grain, so the glass has tooth instead of reading flat */
            radial-gradient(circle at 12% 18%, rgba(255,255,255,.045) 0 1px, transparent 1px) 0 0/7px 7px,
            linear-gradient(180deg, rgba(30,22,58,.96), rgba(14,10,26,.97));
          border: 1px solid color-mix(in srgb, var(--hue) 26%, transparent);
          box-shadow:
            0 14px 40px rgba(0,0,0,.62),
            0 0 0 1px rgba(255,255,255,.02) inset,
            0 0 22px -12px var(--hue);
          backdrop-filter: blur(14px) saturate(1.2);
          /* Older cards recede rather than merely dimming — depth reads as order. */
          transform-origin: 100% 100%;
          transform: scale(calc(1 - var(--back) * 0.035));
          opacity: calc(1 - var(--back) * 0.2);
          animation: bn-in .42s cubic-bezier(.16,1,.3,1) both;
        }

        /* The signal's colour, as a lit edge down the left. */
        .bn__ember {
          position: absolute; left: 0; top: 9px; bottom: 9px; width: 2px;
          border-radius: 0 2px 2px 0;
          background: var(--hue);
          box-shadow: 0 0 10px var(--hue), 0 0 22px -4px var(--hue);
        }

        .bn__glyph {
          flex: 0 0 24px; width: 24px; height: 24px;
          display: grid; place-items: center;
          font-size: 12px; line-height: 1; color: var(--hue);
          border-radius: 50%;
          background: radial-gradient(circle, color-mix(in srgb, var(--hue) 22%, transparent) 0%, transparent 72%);
          text-shadow: 0 0 9px color-mix(in srgb, var(--hue) 70%, transparent);
        }
        /* Only a live stage pulses; a closed one sits still. */
        .bn__card--liquidity .bn__glyph,
        .bn__card--treasury .bn__glyph,
        .bn__card--ignite .bn__glyph { animation: bn-pulse 2.1s ease-in-out infinite; }

        .bn__body { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
        .bn__title {
          font: 600 12.5px/1.3 "DM Sans", sans-serif; color: #f5f0e8;
          letter-spacing: .005em;
        }
        .bn__sub {
          font: 400 9.5px/1.3 "DM Mono", ui-monospace, monospace;
          color: #8f83b8; text-transform: uppercase; letter-spacing: .1em;
        }

        .bn__rail {
          position: absolute; left: 0; right: 0; bottom: 0; height: 2px;
          background: rgba(255,255,255,.05);
        }
        .bn__fill {
          display: block; height: 100%;
          background: linear-gradient(90deg,
            color-mix(in srgb, var(--hue) 40%, transparent), var(--hue));
          box-shadow: 0 0 10px var(--hue);
          transition: width .6s cubic-bezier(.16,1,.3,1);
        }

        @keyframes bn-in {
          from { opacity: 0; transform: translate3d(18px, 10px, 0) scale(.95); }
        }
        @keyframes bn-pulse {
          0%, 100% { opacity: .78; transform: scale(1); }
          50%      { opacity: 1;   transform: scale(1.11); }
        }

        @media (max-width: 560px) {
          .bn { left: 12px; right: 12px; bottom: 12px; max-width: none; align-items: stretch; }
        }
        @media (prefers-reduced-motion: reduce) {
          .bn__card { animation: none; }
          .bn__glyph { animation: none !important; }
          .bn__fill { transition: none; }
        }
      `}</style>
    </>,
    document.body,
  );
}
