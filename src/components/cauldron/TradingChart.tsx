import { useEffect, useMemo, useRef, useState } from "react";
import {
  createChart, ColorType, CrosshairMode, LineStyle,
  type IChartApi, type ISeriesApi, type UTCTimestamp, type AutoscaleInfo,
  type ISeriesPrimitive, type ISeriesPrimitivePaneView, type ISeriesPrimitivePaneRenderer,
  type SeriesAttachedParameter, type Time, type IPriceLine,
} from "lightweight-charts";
import type { Trade } from "@/hooks/useSwapTape";

/** Minimal fancy-canvas rendering scope (CSS-pixel / "media" coordinates). */
type MediaScope = { context: CanvasRenderingContext2D; mediaSize: { width: number; height: number } };
type DrawTarget = { useMediaCoordinateSpace: (f: (s: MediaScope) => void) => void };

export type LiqPos = { isLong: boolean; liqPrice: number; notionalEth: number; openedAt?: number; closedAt?: number | null; status?: string };

type Bar = { time: number; open: number; high: number; low: number; close: number; volume: number };

const TFS: { label: string; sec: number }[] = [
  { label: "TICK", sec: 0 },
  { label: "1m", sec: 60 },
  { label: "5m", sec: 300 },
  { label: "15m", sec: 900 },
  { label: "1h", sec: 3600 },
  { label: "4h", sec: 14400 },
];
const GWEI = 1e9; // display prices in gwei so the axis is readable (~377, not 3.7e-7)

/** Bucket the trade tape into OHLCV bars at `tfSec` (0 = per-trade / tick). */
function aggregate(trades: Trade[], tfSec: number): Bar[] {
  if (trades.length === 0) return [];
  if (tfSec === 0) {
    // tick: one bar per trade (open = prior close), guaranteeing unique times.
    const out: Bar[] = [];
    let prev = trades[0].price;
    let lastT = 0;
    for (const tr of trades) {
      let t = tr.t;
      if (t <= lastT) t = lastT + 1; // enforce strictly-increasing time
      lastT = t;
      const p = tr.price * GWEI, o = prev * GWEI;
      out.push({ time: t, open: o, high: Math.max(o, p), low: Math.min(o, p), close: p, volume: tr.amountEth });
      prev = tr.price;
    }
    return out;
  }
  const buckets = new Map<number, Bar>();
  for (const tr of trades) {
    const b = Math.floor(tr.t / tfSec) * tfSec;
    const p = tr.price * GWEI;
    const cur = buckets.get(b);
    if (cur) { cur.high = Math.max(cur.high, p); cur.low = Math.min(cur.low, p); cur.close = p; cur.volume += tr.amountEth; }
    else buckets.set(b, { time: b, open: p, high: p, low: p, close: p, volume: tr.amountEth });
  }
  const bars = [...buckets.values()].sort((a, b) => a.time - b.time);
  // CONNECT the candles: each bar opens at the previous bar's close. On a sparse
  // testnet pool a bucket often has one trade (open==close → a flat doji line);
  // connecting them makes every candle a real body from the prior close to this
  // bucket's trades — a proper candlestick chart, not scattered dashes.
  for (let i = 1; i < bars.length; i++) {
    const prevClose = bars[i - 1].close;
    bars[i].open = prevClose;
    bars[i].high = Math.max(bars[i].high, prevClose);
    bars[i].low = Math.min(bars[i].low, prevClose);
  }
  return bars;
}

// ── Liquidation heatmap as a NATIVE lightweight-charts Series Primitive ──────
// Drawn INSIDE the chart's pane using the chart's own coordinate converters
// (priceToCoordinate / timeToCoordinate), so levels are always pixel-perfect,
// move with BOTH axes + every timeframe, and are physically clipped to the plot
// (the pane excludes the price/time axes) — no overlay-canvas drift or bleed.
type Band = { y: number; xStart: number; xEnd: number; rgb: string; t: number; live: boolean };

// Coinglass-style liquidation heatmap: each position is a soft horizontal GLOW
// LINE — a bright ~1px core at the exact liq price fading fully transparent above
// and below — drawn from the candle it opened on to the right edge. ADDITIVE
// blending (`lighter`) means overlapping levels sum up, so clusters glow brighter
// and shift colour (many stacked longs → hot red/white), exactly like a real
// liquidation heatmap. Scales to hundreds of positions.
function drawBands(ctx: CanvasRenderingContext2D, W: number, bands: Band[]) {
  ctx.save();
  ctx.globalCompositeOperation = "lighter"; // overlaps ACCUMULATE → intensify
  for (const b of bands) {
    const y = b.y;
    const x0 = Math.max(0, Math.min(b.xStart, W - 1));
    const x1 = Math.max(x0 + 1, Math.min(b.xEnd, W)); // live → W; history → close x
    const w = x1 - x0;
    if (w <= 0) continue;
    // A SINGLE position is a soft, THIN, semi-transparent glow — never fully
    // opaque. Full brightness only emerges where many positions superimpose
    // (additive blending), exactly like the Coinglass heatmap. Closed/liquidated
    // walls (`!live`) are drawn DIMMER as a historical trace from open→close.
    const dim = b.live ? 1 : 0.5;
    const halo = 9 + 5 * b.t;            // soft halo reach (px)
    const coreHalf = 1.1;                // ~1px core → thin line
    const haloA = (0.05 + 0.06 * b.t) * dim;
    const coreA = (0.22 + 0.16 * b.t) * dim; // never opaque for one position
    // soft halo
    const g = ctx.createLinearGradient(0, y - halo, 0, y + halo);
    g.addColorStop(0.0, `rgba(${b.rgb},0)`);
    g.addColorStop(0.5, `rgba(${b.rgb},${haloA.toFixed(3)})`);
    g.addColorStop(1.0, `rgba(${b.rgb},0)`);
    ctx.fillStyle = g;
    ctx.fillRect(x0, y - halo, w, halo * 2);
    // thin, translucent core line at the exact liq level
    const cg = ctx.createLinearGradient(0, y - coreHalf * 2, 0, y + coreHalf * 2);
    cg.addColorStop(0, `rgba(${b.rgb},0)`);
    cg.addColorStop(0.5, `rgba(${b.rgb},${coreA.toFixed(3)})`);
    cg.addColorStop(1, `rgba(${b.rgb},0)`);
    ctx.fillStyle = cg;
    ctx.fillRect(x0, y - coreHalf * 2, w, coreHalf * 4);
    // a small end-cap dot where a historical wall terminated (close/liquidation)
    if (!b.live && x1 < W - 1) {
      ctx.globalCompositeOperation = "source-over";
      ctx.fillStyle = `rgba(${b.rgb},${(coreA + 0.25).toFixed(3)})`;
      ctx.beginPath(); ctx.arc(x1, y, 2, 0, Math.PI * 2); ctx.fill();
      ctx.globalCompositeOperation = "lighter";
    }
  }
  ctx.restore();
}

class LiqHeatmapPrimitive implements ISeriesPrimitive<Time> {
  private _series: ISeriesApi<"Candlestick"> | null = null;
  private _chart: IChartApi | null = null;
  private _requestUpdate?: () => void;
  private _getLiq: () => LiqPos[];
  private _getTf: () => number;
  private _getSpot: () => number;
  private _paneView: ISeriesPrimitivePaneView;

  constructor(getLiq: () => LiqPos[], getTf: () => number, getSpot: () => number) {
    this._getLiq = getLiq;
    this._getTf = getTf;
    this._getSpot = getSpot;
    const self = this;
    this._paneView = {
      zOrder: () => "top",
      renderer(): ISeriesPrimitivePaneRenderer {
        return {
          draw(target: unknown) {
            (target as DrawTarget).useMediaCoordinateSpace((scope) => {
              // Compute coordinates HERE (we have the live pane height) so we can
              // clamp off-screen walls to the top/bottom edge instead of dropping
              // them — the heatmap is always visible regardless of Y framing.
              const bands = self._computeBands(scope.mediaSize.height);
              drawBands(scope.context, scope.mediaSize.width, bands);
            });
          },
        };
      },
    };
  }

  attached(p: SeriesAttachedParameter<Time>) {
    this._chart = p.chart as IChartApi;
    this._series = p.series as ISeriesApi<"Candlestick">;
    this._requestUpdate = p.requestUpdate;
  }
  detached() { this._series = null; this._chart = null; }

  private _computeBands(paneH: number): Band[] {
    const out: Band[] = [];
    const series = this._series, chart = this._chart;
    if (!series || !chart) return out;
    const ts = chart.timeScale();
    const tf = this._getTf();
    const paneW = chart.timeScale().width();
    const spotGwei = this._getSpot(); // spotRef is already in gwei (bar close)
    const list = this._getLiq().filter((p) => p.liqPrice > 0 && Number.isFinite(p.liqPrice));
    if (!list.length) return out;
    const maxNot = Math.max(1e-9, ...list.map((p) => p.notionalEth));
    const snap = (t: number) => (tf > 0 ? Math.floor(t / tf) * tf : t);
    for (const p of list) {
      const priceGwei = p.liqPrice * GWEI;
      let y = series.priceToCoordinate(priceGwei) as number | null;
      if (y == null) {
        // Off-screen at the current Y framing → clamp to the near edge so it's
        // still visible: higher-than-spot walls pin to the top, lower to bottom.
        if (spotGwei > 0) y = priceGwei > spotGwei ? 6 : paneH - 6;
        else continue;
      }
      // START x = the candle it opened on (snapped to the timeframe bucket).
      let xStart = 0;
      if (p.openedAt && p.openedAt > 0) {
        const cx = ts.timeToCoordinate(snap(p.openedAt) as UTCTimestamp);
        if (cx != null) xStart = Math.max(0, cx as number);
      }
      // END x = the candle it closed/liquidated on (history) or the right edge
      // (live). So a wall traces from open → close instead of vanishing.
      const live = !p.closedAt || p.closedAt <= 0;
      let xEnd = paneW || 1e9;
      if (!live && p.closedAt) {
        const cxe = ts.timeToCoordinate(snap(p.closedAt) as UTCTimestamp);
        // if the close coordinate resolves, use it; else treat as reaching now
        if (cxe != null) xEnd = Math.max(xStart + 1, cxe as number);
      }
      out.push({
        y, xStart, xEnd, live,
        rgb: p.isLong ? "255,84,112" : "213,253,81",
        t: p.notionalEth / maxNot,
      });
    }
    return out;
  }

  paneViews() { return [this._paneView]; }
  requestUpdate() { this._requestUpdate?.(); }
}

/**
 * TradingChart — a TradingView-style candlestick chart (via lightweight-charts):
 * timeframe selector (tick/1m/5m/15m/1h/4h), draggable + zoomable X/Y axes,
 * volume, crosshair, and a NATIVE liquidation-level heatmap primitive (red = long
 * liqs, lime = short liqs). Data is the Ponder trade tape — zero browser RPC.
 */
export default function TradingChart({ trades, liq, mark }: { trades: Trade[]; liq?: LiqPos[]; mark?: number | null }) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const candleRef = useRef<ISeriesApi<"Candlestick"> | null>(null);
  const volRef = useRef<ISeriesApi<"Histogram"> | null>(null);
  const primRef = useRef<LiqHeatmapPrimitive | null>(null);
  const markLineRef = useRef<IPriceLine | null>(null);
  const [showHeat, setShowHeat] = useState(true); // heatmap on/off toggle
  const showHeatRef = useRef(showHeat);
  showHeatRef.current = showHeat;
  const liqRef = useRef<LiqPos[]>([]);
  liqRef.current = showHeat ? (liq ?? []) : []; // hidden → primitive sees no walls
  const spotRef = useRef<number>(0); // latest price (gwei) — for the autoscale band
  const fittedTf = useRef<number>(-1);
  const [tf, setTf] = useState<number>(300); // 5m default
  const tfRef = useRef<number>(tf); // live tf for the primitive (avoids chart re-create)
  tfRef.current = tf;

  const bars = useMemo(() => aggregate(trades, tf), [trades, tf]);

  // create the chart once
  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const chart = createChart(el, {
      width: el.clientWidth, height: 340,
      layout: { background: { type: ColorType.Solid, color: "transparent" }, textColor: "#8f83b8", fontFamily: "DM Mono, monospace", fontSize: 10 },
      grid: { vertLines: { color: "rgba(255,255,255,0.04)" }, horzLines: { color: "rgba(255,255,255,0.04)" } },
      crosshair: { mode: CrosshairMode.Normal, vertLine: { color: "#8f83b8", labelBackgroundColor: "#2A1F54" }, horzLine: { color: "#8f83b8", labelBackgroundColor: "#2A1F54" } },
      rightPriceScale: { borderColor: "rgba(255,255,255,0.08)", scaleMargins: { top: 0.08, bottom: 0.12 } },
      timeScale: { borderColor: "rgba(255,255,255,0.08)", timeVisible: true, secondsVisible: false, rightOffset: 6, barSpacing: 12, minBarSpacing: 4 },
      handleScroll: true, handleScale: true,
    });
    const candle = chart.addCandlestickSeries({
      upColor: "#3ddc84", downColor: "#ff5470", borderVisible: false,
      wickUpColor: "#3ddc84", wickDownColor: "#ff5470",
      priceFormat: { type: "price", precision: 2, minMove: 0.01 },
      // Frame the price scale as a TIGHT window around spot that always includes
      // the liquidation walls, so the heatmap bands sit at their real price level
      // (not clamped to an edge) and spot stays centered — even when a few sparse
      // early ticks would otherwise blow the range out. Falls back to the default
      // range before we have a spot. Once the user drags the Y axis, lightweight-
      // charts turns autoscale off and the overlay tracks via priceToCoordinate.
      autoscaleInfoProvider: (baseImpl: () => AutoscaleInfo | null) => {
        const spot = spotRef.current;
        const walls = liqRef.current
          .map((p) => p.liqPrice * GWEI)
          .filter((wp) => wp > 0 && Number.isFinite(wp));
        // Seed the window from spot (if known) and the candle range (baseImpl),
        // then ALWAYS expand to include every liquidation wall so the bands are
        // never off-screen. This guarantees the heatmap is visible on load.
        const base = baseImpl();
        let lo = Infinity, hi = -Infinity;
        if (spot > 0) { lo = spot; hi = spot; }
        if (base?.priceRange) { lo = Math.min(lo, base.priceRange.minValue); hi = Math.max(hi, base.priceRange.maxValue); }
        // include walls within a sane band of spot (or all walls if spot unknown)
        for (const wp of walls) {
          if (spot <= 0 || (wp >= spot * 0.25 && wp <= spot * 2.5)) { lo = Math.min(lo, wp); hi = Math.max(hi, wp); }
        }
        if (!Number.isFinite(lo) || !Number.isFinite(hi) || lo >= hi) return base;
        const pad = (hi - lo) * 0.18; // breathing room so walls aren't on an edge
        return { priceRange: { minValue: lo - pad, maxValue: hi + pad } };
      },
    });
    const vol = chart.addHistogramSeries({ priceFormat: { type: "volume" }, priceScaleId: "" });
    vol.priceScale().applyOptions({ scaleMargins: { top: 0.85, bottom: 0 } });
    chartRef.current = chart; candleRef.current = candle; volRef.current = vol;

    // Native liquidation-heatmap primitive — reads the live liq list each redraw.
    const prim = new LiqHeatmapPrimitive(() => liqRef.current, () => tfRef.current, () => spotRef.current);
    candle.attachPrimitive(prim);
    primRef.current = prim;

    const ro = new ResizeObserver(() => chart.applyOptions({ width: el.clientWidth }));
    ro.observe(el);
    return () => { ro.disconnect(); chart.remove(); chartRef.current = null; candleRef.current = null; primRef.current = null; };
  }, []);

  // push data; only auto-fit when the timeframe changes (preserve pan/zoom on polls)
  useEffect(() => {
    const candle = candleRef.current, vol = volRef.current, chart = chartRef.current;
    if (!candle || !chart) return;
    candle.setData(bars.map((b) => ({ time: b.time as UTCTimestamp, open: b.open, high: b.high, low: b.low, close: b.close })));
    vol?.setData(bars.map((b) => ({ time: b.time as UTCTimestamp, value: b.volume, color: b.close >= b.open ? "rgba(61,220,132,0.35)" : "rgba(255,84,112,0.35)" })));
    spotRef.current = bars.length ? bars[bars.length - 1].close : 0; // latest price (gwei)
    if (fittedTf.current !== tf) { chart.timeScale().fitContent(); fittedTf.current = tf; }
  }, [bars, tf]);

  // When the liq set changes, ask the chart to re-render the primitive (its
  // updateAllViews reads the live list + recomputes coordinates). The primitive
  // also redraws automatically on every pan/zoom/timeframe change.
  useEffect(() => { primRef.current?.requestUpdate(); }, [liq, bars, tf, showHeat]);

  // Gold TWAP-MARK price line — a single clean horizontal line at the price the
  // engine liquidates on (the manipulation-resistant TWAP mark, which LAGS spot).
  // Drawn from the live on-chain `mark` so a trader sees why a spot wick past a liq
  // wall doesn't liquidate: the mark hasn't crossed. (Replaces the EMA line, which
  // looked wonky.)
  useEffect(() => {
    const candle = candleRef.current;
    if (!candle) return;
    if (markLineRef.current) { candle.removePriceLine(markLineRef.current); markLineRef.current = null; }
    if (mark && mark > 0 && Number.isFinite(mark)) {
      markLineRef.current = candle.createPriceLine({
        price: mark * GWEI, color: "#f6c86a", lineWidth: 2, lineStyle: LineStyle.Dashed,
        axisLabelVisible: true, title: "MARK",
      });
    }
  }, [mark]);

  return (
    <div className="tvc">
      <style>{`
        .tvc { position: relative; }
        .tvc__tfs { display: flex; gap: 4px; margin-bottom: 8px; }
        .tvc__heat { margin-left: auto; display: inline-flex; align-items: center; gap: 5px; }
        .tvc__heat-dot { width: 7px; height: 7px; border-radius: 2px; background: linear-gradient(90deg, #ff5470, #d5fd51); opacity: 0.35; transition: opacity .15s, box-shadow .15s; }
        .tvc__heat--on { color: #F5F0E8; border-color: rgba(213,253,81,0.4); }
        .tvc__heat--on .tvc__heat-dot { opacity: 1; box-shadow: 0 0 7px rgba(213,253,81,0.6); }
        .tvc__tf { padding: 4px 10px; border-radius: var(--r-sm); border: 1px solid rgba(255,255,255,0.08); background: rgba(8,6,15,0.5); color: #8f83b8; font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.04em; cursor: pointer; transition: all .15s ease; }
        .tvc__tf:hover { color: #F5F0E8; border-color: rgba(255,255,255,0.2); }
        .tvc__tf--on { background: rgba(213,253,81,0.12); border-color: rgba(213,253,81,0.5); color: #d5fd51; }
        .tvc__wrap { position: relative; width: 100%; height: 340px; }
        .tvc__chart { position: absolute; inset: 0; }
        .tvc__empty { position: absolute; inset: 34px 0 0; display: grid; place-items: center; font-family: "DM Mono", monospace; font-size: 12px; color: #8f83b8; pointer-events: none; }
        .tvc__hint { margin-top: 6px; font-family: "DM Mono", monospace; font-size: 8.5px; color: #8f83b8; opacity: 0.55; text-align: right; }
        .tvc__legend { display: inline-flex; gap: 12px; margin-left: 10px; font-size: 8.5px; }
        .tvc__legend i { width: 8px; height: 8px; border-radius: 2px; display: inline-block; margin-right: 4px; vertical-align: middle; }
      `}</style>
      <div className="tvc__tfs">
        {TFS.map((x) => (
          <button key={x.label} className={`tvc__tf ${tf === x.sec ? "tvc__tf--on" : ""}`} onClick={() => setTf(x.sec)}>{x.label}</button>
        ))}
        <button
          className={`tvc__tf tvc__heat ${showHeat ? "tvc__heat--on" : ""}`}
          onClick={() => setShowHeat((v) => !v)}
          title={showHeat ? "Hide liquidation heatmap" : "Show liquidation heatmap"}
        >
          <i className="tvc__heat-dot" /> LIQ
        </button>
      </div>
      <div className="tvc__wrap">
        <div className="tvc__chart" ref={wrapRef} />
        {bars.length === 0 && <div className="tvc__empty">awaiting first trades…</div>}
      </div>
      <div className="tvc__hint">
        drag to pan · scroll to zoom · price in gwei
        <span className="tvc__legend"><span><i style={{ background: "#d5fd51" }} />short liqs</span><span><i style={{ background: "#ff5470" }} />long liqs</span></span>
      </div>
    </div>
  );
}
