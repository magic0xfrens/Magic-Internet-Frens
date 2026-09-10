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
  reserves: { hookReserve: number; floorVault: number };
  nextLaunch: number;
}

const EMPTY: Liquidity = {
  generation: 0, pool: 0, assets: [], totalUsd: null,
  reserves: { hookReserve: 0, floorVault: 0 }, nextLaunch: 0,
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
      if (d && typeof d.pool === "number") setV({ ...EMPTY, ...d });
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
  const R = 52, C = 2 * Math.PI * R, GAP = assets.length > 1 ? 3 : 0;
  let offset = 0;

  return (
    <div className="ld">
      <div className="ld__ring">
        <svg viewBox="0 0 128 128" role="img" aria-label="Liquidity composition">
          <circle className="ld__track" cx="64" cy="64" r={R} />
          {assets.map((a, i) => {
            const len = Math.max(0, a.share) * C;
            const dash = Math.max(0, len - GAP);
            const el = (
              <circle
                key={a.address || a.symbol}
                className="ld__arc"
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
        <div className="ld__centre">
          <span className="ld__value">{fmt(liq.pool)}</span>
          <span className="ld__unit">{assets.length === 1 ? assets[0].symbol : "in LP"}</span>
          {liq.totalUsd != null && (
            <span className="ld__usd">${fmt(liq.totalUsd, 0)}</span>
          )}
        </div>
      </div>

      <div className="ld__side">
        <span className="ld__label">REAL LIQUIDITY · QUOTE SIDE</span>
        <ul className="ld__legend">
          {assets.map((a, i) => (
            <li key={a.address || a.symbol}>
              <i style={{ background: hueFor(a.symbol, i) }} />
              <b>{a.symbol}</b>
              <em>{fmt(a.amount)}</em>
              <span>{Math.round(a.share * 100)}%</span>
            </li>
          ))}
        </ul>
        <div className="ld__reserves">
          <span title="Hook fee reserve — seeds the next iteration, not tradeable depth">
            fee reserve <em>{fmt(liq.reserves.hookReserve)}</em>
          </span>
          <span title="Collection floor vault — backs redemptions, not tradeable depth">
            floor vault <em>{fmt(liq.reserves.floorVault)}</em>
          </span>
        </div>
      </div>

      <style>{`
        .ld { display: flex; align-items: center; gap: 18px; padding: 4px 2px; }
        .ld__ring { position: relative; flex: 0 0 128px; width: 128px; height: 128px; }
        .ld__ring svg { width: 100%; height: 100%; transform: rotate(-90deg); }
        .ld__track { fill: none; stroke: rgba(245,240,232,.07); stroke-width: 11; }
        .ld__arc {
          fill: none; stroke-width: 11; stroke-linecap: butt;
          filter: drop-shadow(0 0 6px currentColor);
          animation: ld-sweep .9s cubic-bezier(.16,1,.3,1) both;
          transition: stroke-dasharray .7s cubic-bezier(.16,1,.3,1);
        }
        @keyframes ld-sweep { from { opacity: 0; stroke-width: 3; } }

        .ld__centre {
          position: absolute; inset: 0; display: flex; flex-direction: column;
          align-items: center; justify-content: center; gap: 1px; pointer-events: none;
        }
        .ld__value { font: 600 21px/1 "DM Mono", ui-monospace, monospace; color: #f5f0e8; }
        .ld__unit  { font: 400 9px/1 "DM Mono", ui-monospace, monospace; color: #8f83b8;
                     text-transform: uppercase; letter-spacing: .14em; }
        .ld__usd   { font: 400 10px/1 "DM Mono", ui-monospace, monospace; color: #3ddc84; margin-top: 3px; }

        .ld__side { display: flex; flex-direction: column; gap: 8px; min-width: 0; flex: 1; }
        .ld__label { font: 400 9px/1 "DM Mono", ui-monospace, monospace; color: #8f83b8;
                     text-transform: uppercase; letter-spacing: .14em; }

        .ld__legend { list-style: none; margin: 0; padding: 0; display: flex;
                      flex-direction: column; gap: 5px; }
        .ld__legend li { display: flex; align-items: center; gap: 8px;
                         font: 400 11.5px/1 "DM Sans", sans-serif; color: #b8adcc; }
        .ld__legend i { width: 8px; height: 8px; border-radius: 2px; flex: 0 0 8px;
                        box-shadow: 0 0 8px currentColor; }
        .ld__legend b { color: #f5f0e8; font-weight: 600; min-width: 42px; }
        .ld__legend em { font-style: normal; font-family: "DM Mono", ui-monospace, monospace;
                         color: #b8adcc; }
        .ld__legend span { margin-left: auto; font-family: "DM Mono", ui-monospace, monospace;
                           color: #8f83b8; font-size: 10.5px; }

        .ld__reserves { display: flex; flex-direction: column; gap: 3px; margin-top: 3px;
                        padding-top: 8px; border-top: 1px solid rgba(245,240,232,.08); }
        .ld__reserves span { display: flex; justify-content: space-between;
                             font: 400 10px/1.3 "DM Mono", ui-monospace, monospace; color: #8f83b8; }
        .ld__reserves em { font-style: normal; color: #b8adcc; }

        @media (max-width: 560px) {
          .ld { flex-direction: column; align-items: stretch; gap: 12px; }
          .ld__ring { align-self: center; }
        }
        @media (prefers-reduced-motion: reduce) {
          .ld__arc { animation: none; transition: none; }
        }
      `}</style>
    </div>
  );
}
