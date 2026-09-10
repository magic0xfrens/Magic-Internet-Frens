import { useCallback, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

export interface LiqAsset {
  address: string;
  symbol: string;
  /** Quote-side amount, in the asset's own units. */
  amount: number;
  usd: number | null;
  share: number;
  isBasis: boolean;
}

export interface Liquidity {
  generation: number;
  /** Real depth, quote side only. */
  pool: number;
  assets: LiqAsset[];
  totalUsd: number | null;
  reserves: { hookReserve: number };
  /** Genesis redemption floor, in TOKENS per fren. The floors are not ether. */
  floorPerFren?: number;
  floorTicker?: string;
  nextLaunch: number;
}

const EMPTY: Liquidity = {
  generation: 0, pool: 0, assets: [], totalUsd: null,
  reserves: { hookReserve: 0 }, nextLaunch: 0,
};

/** Per-asset colours. Keyed by symbol so a new quote lands somewhere sensible. */
const ASSET_HUE: Record<string, string> = {
  ETH: "#7c5cfc",
  WETH: "#7c5cfc",
  USDG: "#3ddc84",
  USDC: "#3ddc84",
  xNVDA: "#f5c542",
};
const FALLBACK_HUES = ["#d5fd51", "#ff8fa3", "#5cc8fc", "#c792ff"];
const hueFor = (symbol: string, i: number) =>
  ASSET_HUE[symbol] ?? FALLBACK_HUES[i % FALLBACK_HUES.length];

export function useLiquidity(refreshKey?: string | number): Liquidity {
  const [v, setV] = useState<Liquidity>(EMPTY);
  const load = useCallback(async () => {
    if (!INDEXER) return;
    try {
      const r = await fetch(`${INDEXER}/liquidity`, { signal: AbortSignal.timeout(10000) });
      if (!r.ok) return;
      const d = await r.json();
      if (!d || typeof d.pool !== "number") return;
      //  The genesis floor comes from /floor, which already computes it. Fetched
      //  here rather than duplicated into /liquidity so there is one definition
      //  of the floor in the system.
      let floorPerFren: number | undefined;
      let floorTicker: string | undefined;
      try {
        const fr = await fetch(`${INDEXER}/floor`, { signal: AbortSignal.timeout(8000) });
        if (fr.ok) {
          const fj = await fr.json();
          floorPerFren = typeof fj.floorPerFren === "number" ? fj.floorPerFren : undefined;
          floorTicker = fj.ticker || undefined;
        }
      } catch { /* the ring is still correct without it */ }
      setV({ ...EMPTY, ...d, floorPerFren, floorTicker });
    } catch { /* keep the last good reading */ }
  }, []);
  usePoll(load, 12_000);
  return v;
}

const fmt = (n: number, d = 4) =>
  n >= 1000 ? n.toLocaleString(undefined, { maximumFractionDigits: 0 }) : n.toFixed(d);

/**
 * THE LIQUIDITY DIAL.
 *
 *  Replaces a single "available for next launch" figure, which had two problems.
 *  It understated the pool (it counted the fee reserve and the floor vault but
 *  not the LP), and a single number can say nothing about COMPOSITION — which is
 *  the whole point once the guild starts rotating its basis and the position is
 *  genuinely part ETH, part stable, part whatever it voted for.
 *
 *  ONLY THE QUOTE SIDE IS DRAWN. A pool holds two assets and one of them is the
 *  brew's own token; counting that is how a project claims a pool that is half
 *  its own paper. The ring measures what someone could actually take out.
 *
 *  Reserves sit UNDER the ring, never inside it: real value, seeds the next
 *  launch, but not depth anyone can trade against today.
 */
export default function LiquidityDial({ liq, glyph = "Ξ" }: { liq: Liquidity; glyph?: string }) {
  const assets = liq.assets.length
    ? liq.assets
    : [{ address: "", symbol: glyph, amount: liq.pool, usd: null, share: 1, isBasis: true }];

  // Geometry. One ring, drawn as arcs on a circle via stroke-dasharray, which
  // stays crisp at any size and needs no chart library for what is a few arcs.
  const R = 50, C = 2 * Math.PI * R, GAP = assets.length > 1 ? 4 : 0;
  let offset = 0;

  return (
    <div className="lqd">
      <div className="lqd__ring">
        <svg viewBox="0 0 128 128" role="img" aria-label="Liquidity composition">
          <circle className="lqd__track" cx="64" cy="64" r={R} />
          {/* Engraved tick ring — instrument texture, struck into the panel
              rather than floating on it. */}
          <circle className="lqd__ticks" cx="64" cy="64" r={R} />
          {assets.map((a, i) => {
            const len = Math.max(0, a.share) * C;
            const dash = Math.max(0, len - GAP);
            const el = (
              <circle
                key={a.address || a.symbol}
                className="lqd__arc"
                cx="64" cy="64" r={R}
                stroke={hueFor(a.symbol, i)}
                strokeDasharray={`${dash} ${C - dash}`}
                strokeDashoffset={-offset}
                style={{ animationDelay: `${i * 90}ms` }}
              />
            );
            offset += len;
            return el;
          })}
        </svg>
        <div className="lqd__centre">
          <span className="lqd__value">{fmt(liq.pool)}</span>
          <span className="lqd__unit">{assets.length === 1 ? assets[0].symbol : "in LP"}</span>
          {liq.totalUsd != null && (
            <span className="lqd__usd">${fmt(liq.totalUsd, 0)}</span>
          )}
        </div>
      </div>

      <div className="lqd__side">
        <span className="lqd__label">REAL LIQUIDITY · QUOTE SIDE</span>
        <ul className="lqd__legend">
          {assets.map((a, i) => (
            <li key={a.address || a.symbol}>
              <i style={{ background: hueFor(a.symbol, i) }} />
              <b>{a.symbol}</b>
              <em>{fmt(a.amount)}</em>
              <span>{Math.round(a.share * 100)}%</span>
            </li>
          ))}
        </ul>
        <div className="lqd__reserves">
          <span title="Swap fees held by the hook. Real ether, added to the pool at the next relaunch — but not depth anyone can trade against today.">
            fee reserve <em>{fmt(liq.reserves.hookReserve)} {glyph}</em>
          </span>
          {/*  The floors are TOKEN-denominated and deliberately not shown in
               ether. The registry deploys the collection vault with
               `hook.setVault(0)` and the comment "UNIFIED FLOOR: no ETH vault",
               so an ether figure there is always zero — printing it invited the
               reader to add a floor to the pool, which is the wrong sum. What
               actually backs redemption is the out-of-range token reserve. */}
          {liq.floorPerFren ? (
            <span title="Genesis redemption floor: the out-of-range token reserve, claimed 1:1 by burning a fren. Denominated in the brew's own token, not ether.">
              genesis floor <em>{fmt(liq.floorPerFren, 0)} {liq.floorTicker || "tok"}/fren</em>
            </span>
          ) : null}
        </div>
      </div>

      <style>{`
        /*  Wears the SAME shell as the panel it replaced (.tc-reserve): a faint
            lime wash under a lime hairline. The dial should read as part of the
            page's furniture, not a widget dropped onto it. */
        .lqd {
          width: 100%; display: flex; align-items: center; gap: 16px;
          padding: 14px; border-radius: var(--r-sm);
          background:
            radial-gradient(120% 140% at 0% 0%, rgba(213,253,81,0.07), transparent 58%),
            rgba(213,253,81,0.05);
          border: 1px solid rgba(213,253,81,0.12);
        }

        .lqd__ring { position: relative; flex: 0 0 116px; width: 116px; height: 116px; }
        .lqd__ring::before {
          /* Soft bloom under the ring — the brew glowing through the glass. */
          content: ""; position: absolute; inset: 12%;
          border-radius: 50%; background: radial-gradient(circle, rgba(213,253,81,.10), transparent 70%);
          filter: blur(6px);
        }
        .lqd__ring svg { position: relative; width: 100%; height: 100%; transform: rotate(-90deg); }

        .lqd__track { fill: none; stroke: rgba(245,240,232,.06); stroke-width: 8; }
        .lqd__ticks {
          fill: none; stroke: rgba(213,253,81,.14); stroke-width: 8;
          stroke-dasharray: 0.9 7.2;            /* fine engraved graduations */
        }
        .lqd__arc {
          fill: none; stroke-width: 8; stroke-linecap: round;
          filter: drop-shadow(0 0 5px currentColor);
          animation: ld-sweep 1.05s cubic-bezier(.16,1,.3,1) both;
          transition: stroke-dasharray .8s cubic-bezier(.16,1,.3,1),
                      stroke-dashoffset .8s cubic-bezier(.16,1,.3,1);
        }
        @keyframes ld-sweep { from { stroke-dasharray: 0 999; opacity: .25; } }

        .lqd__centre {
          position: absolute; inset: 0; display: flex; flex-direction: column;
          align-items: center; justify-content: center; gap: 1px; pointer-events: none;
        }
        /*  THE HERO NUMERAL, in the wordmark's own face. Every headline figure on
            this page is Cinzel Decorative 900 — the price, the brew name, and the
            "available for next launch" value this dial replaced. Setting it in
            mono made the dial read as a foreign component. */
        .lqd__value {
          font-family: "Cinzel Decorative", serif; font-weight: 900;
          font-size: 21px; line-height: 1; color: #d5fd51;
          text-shadow: 0 0 16px rgba(213,253,81,.35);
        }
        .lqd__unit {
          font: 400 8.5px/1 "DM Mono", ui-monospace, monospace; color: #8f83b8;
          text-transform: uppercase; letter-spacing: .16em; margin-top: 3px;
        }
        .lqd__usd { font: 400 10px/1 "DM Mono", ui-monospace, monospace; color: #3ddc84; margin-top: 2px; }

        .lqd__side { display: flex; flex-direction: column; gap: 7px; min-width: 0; flex: 1; }
        .lqd__label {
          font: 400 8.5px/1 "DM Mono", ui-monospace, monospace; color: #8f83b8;
          text-transform: uppercase; letter-spacing: .16em;
        }

        .lqd__legend { list-style: none; margin: 0; padding: 0; display: flex;
                      flex-direction: column; gap: 5px; }
        .lqd__legend li { display: flex; align-items: center; gap: 8px;
                         font: 400 11px/1 "DM Mono", ui-monospace, monospace; color: #b8adcc; }
        .lqd__legend i { width: 7px; height: 7px; border-radius: 2px; flex: 0 0 7px; }
        .lqd__legend b { color: #f5f0e8; font-weight: 500; min-width: 40px; }
        .lqd__legend em { font-style: normal; color: #b8adcc; }
        .lqd__legend span { margin-left: auto; color: #8f83b8; font-size: 10px; }

        .lqd__reserves { display: flex; flex-direction: column; gap: 3px; margin-top: 2px;
                        padding-top: 7px; border-top: 1px solid rgba(213,253,81,.10); }
        .lqd__reserves span { display: flex; justify-content: space-between; gap: 10px;
                             font: 400 9.5px/1.4 "DM Mono", ui-monospace, monospace;
                             color: #8f83b8; text-transform: uppercase; letter-spacing: .08em; }
        .lqd__reserves em { font-style: normal; color: #b8adcc; text-transform: none; letter-spacing: 0; }

        @media (max-width: 560px) {
          .lqd { flex-direction: column; gap: 14px; }
          .lqd__ring { align-self: center; }
          .lqd__side { width: 100%; }
        }
        @media (prefers-reduced-motion: reduce) {
          .lqd__arc { animation: none; transition: none; }
        }
      `}</style>
    </div>
  );
}
