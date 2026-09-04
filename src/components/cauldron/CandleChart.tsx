import { useMemo } from "react";
import type { Candle } from "@/hooks/useCandles";

export type LiqPos = { isLong: boolean; liqPrice: number; notionalEth: number };

const UP = "#3ddc84";        // bullish candle
const DOWN = "#ff5470";      // bearish candle
const LIQ_LONG = "#ff5470";  // long liquidation walls (below price)
const LIQ_SHORT = "#d5fd51"; // short liquidation walls (above price)
const HEAT_ROWS = 26;

/**
 * CandleChart — OHLC candlesticks (from Ponder) with the liquidation heatmap
 * overlaid: long-liq walls (red) below spot, short-liq walls (lime) above, so you
 * trade against the walls the market hunts. Pure SVG, no deps.
 */
export default function CandleChart({ candles, liq, dead }: { candles: Candle[]; liq?: LiqPos[]; dead?: boolean }) {
  const W = 640, H = 210, padT = 10, padB = 10, padR = 54, padL = 6;

  // Candle-FOCUSED domain: base the view on price action so the candles are big
  // and readable. Liquidation walls (often far from spot) are clamped to the
  // top/bottom edges below — so the chart reads as a real candlestick chart with
  // the liq heat shown at the edges, instead of squashing the candles to a line.
  const domain = useMemo(() => {
    if (candles.length < 1) return null;
    const lo0 = Math.min(...candles.map((k) => k.l));
    const hi0 = Math.max(...candles.map((k) => k.h));
    const span0 = (hi0 - lo0) || hi0 * 0.03 || 1;
    const lo = lo0 - span0 * 0.85, hi = hi0 + span0 * 0.85;
    return { lo, hi, span: hi - lo };
  }, [candles]);

  const chartW = W - padL - padR, chartH = H - padT - padB;
  const yOf = (p: number) => domain ? padT + (1 - (p - domain.lo) / domain.span) * chartH : H / 2;

  // liquidation density rows — walls are CLAMPED into the view, so a wall far
  // below spot piles into the bottom edge row (and far-above into the top),
  // reading as "heavy liquidations below/above" without squashing the candles.
  const rows = useMemo(() => {
    if (!domain || !liq || liq.length === 0) return [];
    const bins = Array.from({ length: HEAT_ROWS }, () => ({ long: 0, short: 0 }));
    for (const p of liq) {
      const clamped = Math.min(domain.hi, Math.max(domain.lo, p.liqPrice));
      const frac = (clamped - domain.lo) / domain.span;
      const idx = Math.min(HEAT_ROWS - 1, Math.max(0, Math.floor(frac * HEAT_ROWS)));
      if (p.isLong) bins[idx].long += p.notionalEth; else bins[idx].short += p.notionalEth;
    }
    const max = Math.max(1e-9, ...bins.map((b) => b.long + b.short));
    const rh = chartH / HEAT_ROWS;
    return bins.map((b, i) => {
      const total = b.long + b.short;
      if (total <= 0) return null;
      return { y: padT + (HEAT_ROWS - 1 - i) * rh, rh, intensity: total / max, isLong: b.long >= b.short };
    }).filter(Boolean) as { y: number; rh: number; intensity: number; isLong: boolean }[];
  }, [liq, domain, chartH]);

  const last = candles.at(-1)?.c ?? 0;
  const lastUp = candles.length >= 2 ? last >= candles[candles.length - 2].c : true;
  const slot = candles.length ? chartW / candles.length : chartW;
  const bodyW = Math.max(3, Math.min(22, slot * 0.66));
  const hasHeat = rows.length > 0;
  // subtle close-line so the trend reads even with few candles
  const closeLine = useMemo(() => {
    if (!domain || candles.length < 2) return "";
    return candles.map((k, i) => `${i === 0 ? "M" : "L"}${(padL + i * slot + slot / 2).toFixed(1)},${yOf(k.c).toFixed(1)}`).join(" ");
  }, [candles, domain, slot]);

  return (
    <div className="cc">
      <style>{`
        .cc { position: relative; }
        .cc svg { width: 100%; height: auto; display: block; }
        .cc__last { position: absolute; top: 8px; right: 8px; font-family: "DM Mono", monospace; font-size: 12px; font-weight: 700; }
        .cc__legend { position: absolute; bottom: 6px; left: 10px; display: flex; gap: 12px; font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.04em; color: #8f83b8; text-transform: uppercase; pointer-events: none; }
        .cc__legend span { display: inline-flex; align-items: center; gap: 4px; }
        .cc__legend i { width: 8px; height: 8px; border-radius: 2px; display: inline-block; }
        .cc__empty { position: absolute; inset: 0; display: grid; place-items: center; font-family: "DM Mono", monospace; font-size: 12px; color: #8f83b8; }
      `}</style>
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
        {/* grid */}
        {[0.25, 0.5, 0.75].map((g) => <line key={g} x1={padL} x2={W - padR} y1={padT + chartH * g} y2={padT + chartH * g} stroke="rgba(255,255,255,0.05)" />)}

        {/* liquidation heatmap: full-width bands + right-edge density bars */}
        {rows.map((r, i) => {
          const c = r.isLong ? LIQ_LONG : LIQ_SHORT;
          const barW = padR * (0.25 + 0.7 * r.intensity);
          return (
            <g key={i}>
              <rect x="0" y={r.y} width={W - padR} height={r.rh + 0.6} fill={c} opacity={0.05 + 0.2 * r.intensity} />
              <rect x={W - padR + 2} y={r.y + r.rh * 0.15} width={barW} height={r.rh * 0.7} rx="1" fill={c} opacity={0.4 + 0.5 * r.intensity} />
            </g>
          );
        })}

        {/* subtle close-line trend under the candles */}
        {closeLine && <path d={closeLine} fill="none" stroke="#ffffff" strokeWidth="0.8" opacity="0.14" />}

        {/* candlesticks */}
        {domain && candles.map((k, i) => {
          const x = padL + i * slot + slot / 2;
          const up = k.c >= k.o;
          const col = up ? UP : DOWN;
          const yO = yOf(k.o), yC = yOf(k.c);
          const bodyY = Math.min(yO, yC), bodyH = Math.max(2, Math.abs(yC - yO));
          return (
            <g key={i} opacity={dead ? 0.5 : 1}>
              <line x1={x} x2={x} y1={yOf(k.h)} y2={yOf(k.l)} stroke={col} strokeWidth="1.3" />
              <rect x={x - bodyW / 2} y={bodyY} width={bodyW} height={bodyH} fill={col} rx="1" />
            </g>
          );
        })}

        {/* last price line + tag */}
        {domain && last > 0 && (
          <>
            <line x1={padL} x2={W - padR} y1={yOf(last)} y2={yOf(last)} stroke={lastUp ? UP : DOWN} strokeWidth="0.6" strokeDasharray="3 3" opacity="0.6" />
            <rect x={W - padR} y={yOf(last) - 8} width={padR} height={16} fill={lastUp ? UP : DOWN} />
            <text x={W - padR / 2} y={yOf(last) + 3} textAnchor="middle" fontSize="8.5" fontFamily="DM Mono, monospace" fontWeight="700" fill="#08060f">{(last * 1e9).toFixed(1)}</text>
          </>
        )}
      </svg>
      <div className="cc__last" style={{ color: lastUp ? UP : DOWN }}>{last > 0 ? `${(last * 1e9).toFixed(2)} gwei` : "—"}</div>
      {hasHeat && (
        <div className="cc__legend">
          <span><i style={{ background: LIQ_SHORT }} />short liqs</span>
          <span><i style={{ background: LIQ_LONG }} />long liqs</span>
        </div>
      )}
      {candles.length < 1 && <div className="cc__empty">awaiting first swaps…</div>}
    </div>
  );
}
