import { useRef, useEffect, useCallback } from "react";
import { useMiFrensPresale } from "@/hooks/useMiFrensPresale";
import { MOTOSWAP_URL } from "@/constants/contracts";
import { PHOENIX_METADATA, PHOENIX_CONFIG } from "@/constants/phoenix";
import potionImg from "@/assets/images/potion-cropped.svg";

/* ═══════════════════════════════════════════
   Creature data (Generation 1)
   ═══════════════════════════════════════════ */

const creature = PHOENIX_METADATA[0];

/* ═══════════════════════════════════════════
   Deterministic mock price data
   ═══════════════════════════════════════════ */

function createRng(seed: number) {
  let s = seed;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return s / 2147483647;
  };
}

function generatePriceData(): { price: number; vol: number }[] {
  const rand = createRng(777);
  const points: { price: number; vol: number }[] = [];
  let price = 0.00012; // starting price in BTC

  for (let i = 0; i < 96; i++) {
    // 96 points = 4 days of 1h candles
    const drift = (rand() - 0.48) * 0.08;
    price = Math.max(0.00003, price * (1 + drift));
    // Create a price pump then pullback pattern
    if (i > 10 && i < 30) price *= 1.012;
    if (i > 55 && i < 70) price *= 1.008;
    if (i > 70 && i < 80) price *= 0.994;
    points.push({
      price,
      vol: 0.001 + rand() * 0.008,
    });
  }

  return points;
}

const PRICE_DATA = generatePriceData();

/* ═══════════════════════════════════════════
   Component
   ═══════════════════════════════════════════ */

export default function Token() {
  const presale = useMiFrensPresale();
  const totalMinted = presale.minted ?? 0;
  const maxSupply = presale.maxSupply;
  const progress = maxSupply > 0 ? (totalMinted / maxSupply) * 100 : 0;
  const isUnlocked = presale.soldOut;
  const loading = presale.minted === undefined;

  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  /* ── Mock live stats ── */
  const volume24h = 0.042;
  const healthPct = (volume24h / PHOENIX_CONFIG.DEATH_THRESHOLD_BTC) * 100;
  const healthColor = healthPct < 150 ? "#ff4444" : healthPct < 300 ? "#d5fd51" : "#3ddc84";
  const healthLabel = healthPct < 150 ? "CRITICAL" : healthPct < 300 ? "MODERATE" : "HEALTHY";

  const lastPrice = PRICE_DATA[PRICE_DATA.length - 1].price;
  const firstPrice = PRICE_DATA[0].price;
  const priceChange = ((lastPrice - firstPrice) / firstPrice) * 100;
  const isUp = priceChange >= 0;

  /* ── Draw price chart ── */
  const drawChart = useCallback((canvas: HTMLCanvasElement) => {
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const { width: w, height: totalH } = canvas.getBoundingClientRect();
    canvas.width = w * dpr;
    canvas.height = totalH * dpr;
    ctx.scale(dpr, dpr);

    const chartH = totalH * 0.72;
    const volH = totalH * 0.18;
    const volTop = chartH + totalH * 0.04;
    const pad = { top: 16, right: 60, bottom: 4, left: 12 };

    // Background
    ctx.fillStyle = "#FBF7F0";
    ctx.fillRect(0, 0, w, totalH);

    // Grid lines
    const prices = PRICE_DATA.map((d) => d.price);
    const minP = Math.min(...prices) * 0.95;
    const maxP = Math.max(...prices) * 1.05;
    const chartW = w - pad.left - pad.right;
    const chartInnerH = chartH - pad.top - pad.bottom;

    const toX = (i: number) => pad.left + (i / (PRICE_DATA.length - 1)) * chartW;
    const toY = (p: number) => pad.top + (1 - (p - minP) / (maxP - minP)) * chartInnerH;

    // Horizontal grid + price labels
    const gridSteps = 5;
    ctx.strokeStyle = "rgba(42,31,84,0.06)";
    ctx.lineWidth = 0.5;
    ctx.font = '9px "DM Sans", sans-serif';
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";

    for (let i = 0; i <= gridSteps; i++) {
      const p = minP + (i / gridSteps) * (maxP - minP);
      const y = toY(p);
      ctx.beginPath();
      ctx.moveTo(pad.left, y);
      ctx.lineTo(w - pad.right + 8, y);
      ctx.stroke();

      ctx.fillStyle = "#8A7BAA";
      ctx.fillText((p * 100000).toFixed(1), w - pad.right + 12, y);
    }

    // Y-axis label
    ctx.save();
    ctx.fillStyle = "rgba(42,31,84,0.2)";
    ctx.font = '8px "DM Sans", sans-serif';
    ctx.textAlign = "right";
    ctx.fillText("gwei", w - pad.right + 12, pad.top - 6);
    ctx.restore();

    // Gradient fill under the line
    const gradient = ctx.createLinearGradient(0, pad.top, 0, chartH);
    const lineColor = isUp ? "#3ddc84" : "#ff4444";
    gradient.addColorStop(0, isUp ? "rgba(0, 204, 102, 0.18)" : "rgba(255, 68, 68, 0.18)");
    gradient.addColorStop(1, "rgba(245, 240, 232, 0)");

    ctx.beginPath();
    ctx.moveTo(toX(0), chartH);
    for (let i = 0; i < PRICE_DATA.length; i++) {
      ctx.lineTo(toX(i), toY(PRICE_DATA[i].price));
    }
    ctx.lineTo(toX(PRICE_DATA.length - 1), chartH);
    ctx.closePath();
    ctx.fillStyle = gradient;
    ctx.fill();

    // Price line
    ctx.beginPath();
    for (let i = 0; i < PRICE_DATA.length; i++) {
      const x = toX(i);
      const y = toY(PRICE_DATA[i].price);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.strokeStyle = lineColor;
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // Current price dot
    const lastX = toX(PRICE_DATA.length - 1);
    const lastY = toY(lastPrice);
    ctx.beginPath();
    ctx.arc(lastX, lastY, 3, 0, Math.PI * 2);
    ctx.fillStyle = lineColor;
    ctx.fill();
    // Glow ring
    ctx.beginPath();
    ctx.arc(lastX, lastY, 6, 0, Math.PI * 2);
    ctx.strokeStyle = lineColor;
    ctx.lineWidth = 0.5;
    ctx.globalAlpha = 0.4;
    ctx.stroke();
    ctx.globalAlpha = 1;

    // Dashed horizontal line at current price
    ctx.setLineDash([3, 3]);
    ctx.beginPath();
    ctx.moveTo(lastX + 8, lastY);
    ctx.lineTo(w - pad.right + 8, lastY);
    ctx.strokeStyle = lineColor;
    ctx.lineWidth = 0.5;
    ctx.globalAlpha = 0.6;
    ctx.stroke();
    ctx.globalAlpha = 1;
    ctx.setLineDash([]);

    // Price tag at right edge
    ctx.fillStyle = lineColor;
    const tagW = 48;
    const tagH = 16;
    ctx.fillRect(w - pad.right + 10, lastY - tagH / 2, tagW, tagH);
    ctx.fillStyle = "#F5F0E8";
    ctx.font = 'bold 8px "DM Sans", sans-serif';
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText((lastPrice * 100000).toFixed(1), w - pad.right + 10 + tagW / 2, lastY);

    // Volume bars
    const maxVol = Math.max(...PRICE_DATA.map((d) => d.vol));
    const barW = Math.max(1, chartW / PRICE_DATA.length - 1);

    for (let i = 0; i < PRICE_DATA.length; i++) {
      const x = toX(i) - barW / 2;
      const barH = (PRICE_DATA[i].vol / maxVol) * volH;
      const priceUp = i > 0 ? PRICE_DATA[i].price >= PRICE_DATA[i - 1].price : true;

      ctx.fillStyle = priceUp ? "rgba(0, 204, 102, 0.35)" : "rgba(255, 68, 68, 0.3)";
      ctx.fillRect(x, volTop + volH - barH, barW, barH);
    }

    // Volume label
    ctx.fillStyle = "rgba(42,31,84,0.2)";
    ctx.font = '8px "DM Sans", sans-serif';
    ctx.textAlign = "left";
    ctx.fillText("VOL", pad.left, volTop - 2);
  }, [isUp, lastPrice]);

  /* ── Resize observer + redraw ── */
  useEffect(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container) return;

    const draw = () => drawChart(canvas);
    draw();

    const ro = new ResizeObserver(() => draw());
    ro.observe(container);
    return () => ro.disconnect();
  }, [drawChart]);

  /* ── Distribution data ── */
  const distribution = [
    { pct: 21, label: "FREN HOLDERS", desc: "Airdrop to 777 MiFrens holders", color: "#d5fd51" },
    { pct: 72, label: "LIQUIDITY POOL", desc: "Seeded on MotoSwap DEX", color: "#7C5CFC" },
    { pct: 7, label: "COMMUNITY", desc: "OTC deals & initiatives", color: "#8A7BAA" },
  ];

  /* ══════════════════════ RENDER ══════════════════════ */

  return (
    <div className="tkn">
      {/* ─── 1. HEADER ─── */}
      <div className="tkn__header">
        <div className="tkn__header-top">
          <div className="tkn__header-left">
            <span className="tkn__tag">FIRST SUMMONING</span>
            <div className="tkn__name-row">
              <img src={potionImg} alt="" className="tkn__potion" />
              <h1 className="tkn__creature-name">{creature.name.toUpperCase()}</h1>
            </div>
            <span className="tkn__ticker">${creature.symbol}</span>
          </div>
          <div className="tkn__header-right">
            <span className="tkn__gen-badge">GENERATION {creature.gen}</span>
            <span className={`tkn__status-badge ${isUnlocked ? "tkn__status-badge--live" : ""}`}>
              <span className="tkn__status-dot" />
              {isUnlocked ? "ALIVE" : "PENDING"}
            </span>
          </div>
        </div>

        <div className="tkn__progress-section">
          <div className="tkn__progress-header">
            <span className="tkn__progress-label">MINT PROGRESS</span>
            <span className="tkn__progress-val">
              {loading ? "\u2014" : totalMinted} / {maxSupply}
            </span>
          </div>
          <div className="tkn__progress-track">
            <div className="tkn__progress-fill" style={{ width: `${Math.max(progress, 0.3)}%` }} />
          </div>
        </div>
      </div>

      {/* ─── 2. PRICE CHART ─── */}
      <div className="tkn__chart">
        <div className="tkn__chart-header">
          <span className="tkn__chart-pair">${creature.symbol} / ETH</span>
          <span className="tkn__chart-price-info">
            <span className="tkn__chart-last">{(lastPrice * 100000).toFixed(1)} gwei</span>
            <span className={`tkn__chart-change ${isUp ? "tkn__chart-change--up" : "tkn__chart-change--down"}`}>
              {isUp ? "+" : ""}{priceChange.toFixed(1)}%
            </span>
          </span>
          <span className={`tkn__chart-live ${isUnlocked ? "tkn__chart-live--on" : ""}`}>
            {isUnlocked ? "LIVE" : "DEMO"}
          </span>
        </div>

        <div className="tkn__chart-body" ref={containerRef}>
          <canvas ref={canvasRef} className="tkn__chart-canvas" />
          {!isUnlocked && (
            <div className="tkn__chart-overlay">DEMO &mdash; LIVE AFTER SUMMONING</div>
          )}
        </div>

        <div className="tkn__chart-footer">
          <div className="tkn__chart-tf">
            {["1H", "4H", "1D", "1W"].map((tf, i) => (
              <span key={tf} className={`tkn__tf${i === 1 ? " tkn__tf--active" : ""}`}>{tf}</span>
            ))}
          </div>
          <a href={MOTOSWAP_URL} target="_blank" rel="noopener noreferrer" className="tkn__trade-btn">
            TRADE ON MOTOSWAP
          </a>
        </div>
      </div>

      {/* ─── CREATURE HEALTH ─── */}
      <div className="tkn__health">
        <div className="tkn__health-row">
          <span className="tkn__health-label">CREATURE HEALTH</span>
          <span className="tkn__health-status" style={{ color: healthColor }}>
            {healthLabel}
          </span>
        </div>
        <div className="tkn__health-track">
          <div
            className={`tkn__health-fill${healthPct < 150 ? " tkn__health-fill--pulse" : ""}`}
            style={{ width: `${Math.min(healthPct / 5, 100)}%`, background: healthColor }}
          />
        </div>
        <div className="tkn__health-meta">
          <span>24H VOLUME: {volume24h} ETH</span>
          <span>DEATH AT: {PHOENIX_CONFIG.DEATH_THRESHOLD_BTC} ETH</span>
        </div>
      </div>

      {/* ─── 3. STATS GRID ─── */}
      <div className="tkn__stats">
        {[
          { val: `${volume24h}`, label: "24H VOLUME" },
          { val: "--", label: "MKT CAP" },
          { val: "--", label: "HOLDERS" },
          { val: "LOCKED", label: "LIQUIDITY" },
        ].map((s) => (
          <div key={s.label} className="tkn__stat">
            <span className="tkn__stat-val">{s.val}</span>
            <span className="tkn__stat-label">{s.label}</span>
          </div>
        ))}
      </div>

      {/* ─── 4. DISTRIBUTION ─── */}
      <div className="tkn__dist">
        <h2 className="tkn__section-title">TOKEN DISTRIBUTION</h2>

        <div className="tkn__dist-bar">
          {distribution.map((d) => (
            <div
              key={d.label}
              className="tkn__dist-seg"
              style={{ width: `${d.pct}%`, background: d.color }}
            >
              {d.pct}%
            </div>
          ))}
        </div>

        <div className="tkn__dist-grid">
          {distribution.map((d) => (
            <div key={d.label} className="tkn__dist-item">
              <span className="tkn__dist-pct" style={{ color: d.color }}>
                {d.pct}%
              </span>
              <span className="tkn__dist-name">{d.label}</span>
              <span className="tkn__dist-desc">{d.desc}</span>
            </div>
          ))}
        </div>
      </div>

      {/* ─── 5. TOKEN DETAILS ─── */}
      <div className="tkn__details">
        <h2 className="tkn__section-title">TOKEN DETAILS</h2>
        <div className="tkn__table">
          {[
            { k: "NAME", v: `${creature.name.toUpperCase()} (${creature.symbol})` },
            { k: "GENERATION", v: `${creature.gen}` },
            { k: "NETWORK", v: "ROBINHOOD" },
            { k: "DECIMALS", v: "18" },
            { k: "TOTAL SUPPLY", v: `${PHOENIX_CONFIG.INITIAL_LIQUIDITY_TOKENS}` },
            { k: "DEATH THRESHOLD", v: `${PHOENIX_CONFIG.DEATH_THRESHOLD_BTC} ETH / 24H` },
            { k: "DEPLOY CONDITION", v: `SUMMONED AFTER ${maxSupply} FRENS ARE MINTED` },
            { k: "CONTRACT", v: isUnlocked ? "0x..." : "NOT DEPLOYED", dim: !isUnlocked },
          ].map((r) => (
            <div key={r.k} className="tkn__row">
              <span className="tkn__row-key">{r.k}</span>
              <span className={`tkn__row-val${r.dim ? " tkn__row-val--dim" : ""}`}>{r.v}</span>
            </div>
          ))}
          <div className="tkn__row">
            <span className="tkn__row-key">DEX</span>
            <a href={MOTOSWAP_URL} target="_blank" rel="noopener noreferrer" className="tkn__row-val tkn__row-link">
              MOTOSWAP
            </a>
          </div>
        </div>
      </div>

      {/* ─── 6. LORE ─── */}
      <div className="tkn__utility">
        <h2 className="tkn__section-title">LORE</h2>
        <div className="tkn__lore-text">
          <p>
            In the beginning there was only the chain — an immutable ledger stretching
            back to the genesis block. But deep within its cryptographic marrow, something
            stirred. A spark of magic, inscribed in Tapscript, waiting to be summoned.
          </p>
          <p>
            The Magic Internet Frens are the first iteration — 777 beings conjured
            fully on-chain on Robinhood. Wizards, Kings, Knights, Gnomes,
            Apprentices, and Peasants, each with their own traits etched permanently
            into the base chain. No bridges. No sidechains. No escape hatches.
          </p>
          <p>
            When the last fren is minted, the Cauldron ignites. The first iteration token launches,
            and the protocol awakens. Every fren holder becomes a keeper of the flame —
            bound to the network by code, governed by consensus, united by magic.
          </p>
          <p>
            But the flame does not burn forever. If the daily volume falls below the death
            threshold, the creature perishes — and from its ashes, something new is born.
            A second generation rises, transformed, carrying the memory of what came before
            but reshaped by the chain itself. Death is not the end. It is transmutation.
          </p>
          <p>
            This is not a promise of what comes next. This is the proof that it already began.
          </p>
        </div>
      </div>

      {/* ═══════════════════════════════════════
          STYLES — light wizard palette
          ═══════════════════════════════════════ */}
      <style>{`
        .tkn {
          max-width: 820px;
          margin: 0 auto;
          padding: 48px 24px 80px;
        }

        /* ── 1. Header ── */
        .tkn__header {
          margin-bottom: 40px;
          padding: 36px;
          background: #FBF7F0;
          border: 1px solid rgba(42,31,84,0.08);
          border-radius: var(--r-md);
          box-shadow: 0 2px 12px rgba(42,31,84,0.06);
        }

        .tkn__header-top {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          margin-bottom: 32px;
        }

        .tkn__header-left {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        .tkn__tag {
          font-size: 10px;
          font-weight: 600;
          letter-spacing: 0.18em;
          color: #B8ADCC;
        }

        .tkn__name-row {
          display: flex;
          align-items: center;
          gap: 14px;
        }

        .tkn__potion {
          width: 48px;
          height: 48px;
          image-rendering: pixelated;
          filter: drop-shadow(0 0 10px rgba(77, 182, 172, 0.5));
          animation: potion-bob 3s ease-in-out infinite;
        }

        @keyframes potion-bob {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-3px); }
        }

        .tkn__creature-name {
          font-family: "Cinzel Decorative", serif;
          font-size: 24px;
          font-weight: 400;
          color: ${creature.color};
          text-shadow: 0 0 20px ${creature.color}33;
          margin: 0;
        }

        .tkn__ticker {
          font-family: "DM Sans", sans-serif;
          font-size: 13px;
          font-weight: 600;
          color: #8A7BAA;
          letter-spacing: 0.06em;
        }

        .tkn__header-right {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 10px;
        }

        .tkn__gen-badge {
          font-family: "DM Sans", sans-serif;
          font-size: 10px;
          font-weight: 600;
          letter-spacing: 0.15em;
          color: #8A7BAA;
          padding: 5px 12px;
          border: 1px solid rgba(42,31,84,0.10);
          background: #F5F0E8;
          border-radius: var(--r-md);
        }

        .tkn__status-badge {
          display: flex;
          align-items: center;
          gap: 6px;
          font-family: "DM Sans", sans-serif;
          font-size: 11px;
          font-weight: 700;
          letter-spacing: 0.1em;
          color: #8A7BAA;
        }

        .tkn__status-badge--live {
          color: #3ddc84;
        }

        .tkn__status-dot {
          width: 6px;
          height: 6px;
          border-radius: 50%;
          background: #8A7BAA;
          animation: dot-blink 2s ease-in-out infinite;
        }

        .tkn__status-badge--live .tkn__status-dot {
          background: #3ddc84;
          box-shadow: 0 0 6px #3ddc84;
        }

        @keyframes dot-blink {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.3; }
        }

        /* Progress bar */
        .tkn__progress-section {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }

        .tkn__progress-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .tkn__progress-label {
          font-size: 10px;
          font-weight: 500;
          letter-spacing: 0.12em;
          color: #8A7BAA;
        }

        .tkn__progress-val {
          font-family: "DM Sans", sans-serif;
          font-size: 13px;
          font-weight: 600;
          color: #2A1F54;
        }

        .tkn__progress-track {
          width: 100%;
          height: 5px;
          background: rgba(42,31,84,0.08);
          overflow: hidden;
          border-radius: var(--r-sm);
        }

        .tkn__progress-fill {
          height: 100%;
          background: linear-gradient(90deg, #d5fd51, #E8850F);
          transition: width 0.6s ease;
          border-radius: var(--r-sm);
        }

        /* ── 2. Price Chart ── */
        .tkn__chart {
          background: #FBF7F0;
          border: 1px solid rgba(42,31,84,0.08);
          margin-bottom: 0;
          overflow: hidden;
          border-radius: var(--r-md) var(--r-md) 0 0;
          box-shadow: 0 2px 12px rgba(42,31,84,0.06);
        }

        .tkn__chart-header {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 12px 20px;
          border-bottom: 1px solid rgba(42,31,84,0.06);
          background: linear-gradient(135deg, #F5F0E8 0%, #EDE8DD 100%);
        }

        .tkn__chart-pair {
          font-family: "Fredoka", sans-serif;
          font-size: 13px;
          font-weight: 500;
          color: #2A1F54;
        }

        .tkn__chart-price-info {
          display: flex;
          align-items: center;
          gap: 8px;
          margin-left: auto;
        }

        .tkn__chart-last {
          font-family: "DM Sans", sans-serif;
          font-size: 12px;
          font-weight: 700;
          color: #2A1F54;
        }

        .tkn__chart-change {
          font-family: "DM Sans", sans-serif;
          font-size: 10px;
          font-weight: 700;
          letter-spacing: 0.05em;
          padding: 2px 8px;
          border-radius: var(--r-md);
        }

        .tkn__chart-change--up { color: #3ddc84; background: rgba(0, 204, 102, 0.08); }
        .tkn__chart-change--down { color: #ff4444; background: rgba(255, 68, 68, 0.08); }

        .tkn__chart-live {
          font-family: "DM Sans", sans-serif;
          font-size: 10px;
          font-weight: 600;
          letter-spacing: 0.1em;
          color: #B8ADCC;
          margin-left: 12px;
        }

        .tkn__chart-live--on {
          color: #3ddc84;
        }

        .tkn__chart-body {
          position: relative;
          height: 320px;
        }

        .tkn__chart-canvas {
          display: block;
          width: 100%;
          height: 100%;
        }

        .tkn__chart-overlay {
          position: absolute;
          inset: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: "Fredoka", sans-serif;
          font-size: 13px;
          font-weight: 400;
          letter-spacing: 0.12em;
          color: #2A1F5466;
          background: rgba(251,247,240,0.15);
          pointer-events: none;
          z-index: 5;
        }

        .tkn__chart-footer {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 12px 20px;
          border-top: 1px solid rgba(42,31,84,0.06);
        }

        .tkn__chart-tf {
          display: flex;
          gap: 3px;
        }

        .tkn__tf {
          font-family: "DM Sans", sans-serif;
          font-size: 10px;
          font-weight: 600;
          letter-spacing: 0.05em;
          color: #B8ADCC;
          padding: 5px 12px;
          cursor: pointer;
          transition: all 0.15s ease;
          border-radius: var(--r-md);
        }

        .tkn__tf:hover {
          color: #2A1F54;
          background: rgba(42,31,84,0.04);
        }

        .tkn__tf--active {
          color: #d5fd51;
          background: rgba(247, 147, 26, 0.08);
        }

        .tkn__trade-btn {
          display: inline-block;
          padding: 10px 24px;
          background: #d5fd51;
          color: #FBF7F0;
          font-family: "Fredoka", sans-serif;
          font-size: 13px;
          font-weight: 500;
          letter-spacing: 0.04em;
          text-decoration: none;
          transition: all 0.2s ease;
          border-radius: var(--r-md);
        }

        .tkn__trade-btn:hover {
          transform: translateY(-1px);
          box-shadow: 0 4px 16px rgba(247, 147, 26, 0.25);
        }

        /* ── Health bar ── */
        .tkn__health {
          padding: 22px 28px;
          background: #FBF7F0;
          border: 1px solid rgba(42,31,84,0.08);
          border-top: none;
          margin-bottom: 40px;
          border-radius: 0 0 var(--r-md) var(--r-md);
          box-shadow: 0 2px 12px rgba(42,31,84,0.06);
        }

        .tkn__health-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 10px;
        }

        .tkn__health-label {
          font-size: 10px;
          font-weight: 500;
          letter-spacing: 0.12em;
          color: #8A7BAA;
        }

        .tkn__health-status {
          font-family: "Fredoka", sans-serif;
          font-size: 12px;
          font-weight: 500;
          letter-spacing: 0.06em;
        }

        .tkn__health-track {
          width: 100%;
          height: 6px;
          background: rgba(42,31,84,0.08);
          overflow: hidden;
          margin-bottom: 10px;
          border-radius: var(--r-sm);
        }

        .tkn__health-fill {
          height: 100%;
          transition: width 0.6s ease;
          border-radius: var(--r-sm);
        }

        .tkn__health-fill--pulse {
          animation: health-pulse 1.2s ease-in-out infinite;
        }

        @keyframes health-pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }

        .tkn__health-meta {
          display: flex;
          justify-content: space-between;
          font-family: "DM Sans", sans-serif;
          font-size: 10px;
          font-weight: 500;
          letter-spacing: 0.06em;
          color: #B8ADCC;
        }

        /* ── 3. Stats grid ── */
        .tkn__stats {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 16px;
          margin-bottom: 40px;
        }

        .tkn__stat {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 12px;
          padding: 32px 16px;
          background: #FBF7F0;
          border: 1px solid rgba(42,31,84,0.08);
          border-radius: var(--r-md);
          box-shadow: 0 2px 12px rgba(42,31,84,0.04);
          transition: all 0.2s ease;
        }

        .tkn__stat:hover {
          transform: translateY(-2px);
          box-shadow: 0 6px 20px rgba(42,31,84,0.08);
        }

        .tkn__stat-val {
          font-family: "Fredoka", sans-serif;
          font-size: 18px;
          color: #d5fd51;
        }

        .tkn__stat-label {
          font-size: 10px;
          font-weight: 500;
          letter-spacing: 0.12em;
          color: #B8ADCC;
          text-align: center;
        }

        /* ── 4. Distribution ── */
        .tkn__dist {
          margin-bottom: 40px;
        }

        .tkn__section-title {
          font-size: 14px;
          font-weight: 600;
          letter-spacing: 0.08em;
          color: #8a7baa;
          margin-bottom: 24px;
          padding-bottom: 14px;
          border-bottom: 1px solid rgba(42,31,84,0.08);
          font-family: "Cinzel", serif;
        }

        .tkn__dist-bar {
          display: flex;
          height: 36px;
          gap: 3px;
          margin-bottom: 16px;
          border-radius: var(--r-sm);
          overflow: hidden;
        }

        .tkn__dist-seg {
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: "Fredoka", sans-serif;
          font-size: 12px;
          font-weight: 500;
          color: #FBF7F0;
        }

        .tkn__dist-grid {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 16px;
        }

        .tkn__dist-item {
          display: flex;
          flex-direction: column;
          gap: 8px;
          padding: 24px 20px;
          background: #FBF7F0;
          border: 1px solid rgba(42,31,84,0.08);
          border-radius: var(--r-md);
          box-shadow: 0 2px 12px rgba(42,31,84,0.04);
        }

        .tkn__dist-pct {
          font-family: "Fredoka", sans-serif;
          font-size: 22px;
          font-weight: 500;
        }

        .tkn__dist-name {
          font-size: 11px;
          font-weight: 600;
          letter-spacing: 0.12em;
          color: #2A1F54;
        }

        .tkn__dist-desc {
          font-size: 12px;
          line-height: 1.6;
          color: #8A7BAA;
        }

        /* ── 5. Token details ── */
        .tkn__details {
          margin-bottom: 40px;
        }

        .tkn__table {
          display: flex;
          flex-direction: column;
          background: #FBF7F0;
          border: 1px solid rgba(42,31,84,0.08);
          border-radius: var(--r-md);
          padding: 8px 24px;
          box-shadow: 0 2px 12px rgba(42,31,84,0.04);
        }

        .tkn__row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 16px 0;
          border-bottom: 1px solid rgba(42,31,84,0.05);
        }

        .tkn__row:last-child {
          border-bottom: none;
        }

        .tkn__row-key {
          font-size: 11px;
          font-weight: 500;
          letter-spacing: 0.1em;
          color: #B8ADCC;
        }

        .tkn__row-val {
          font-family: "DM Sans", sans-serif;
          font-size: 13px;
          font-weight: 600;
          color: #2A1F54;
        }

        .tkn__row-val--dim {
          color: #8A7BAA;
        }

        .tkn__row-link {
          color: #d5fd51;
          text-decoration: none;
          transition: opacity 0.15s ease;
          font-weight: 600;
        }

        .tkn__row-link:hover {
          opacity: 0.75;
        }

        /* ── 6. Lore ── */
        .tkn__lore-text {
          padding: 36px 40px;
          background: #FBF7F0;
          border: 1px solid rgba(42,31,84,0.08);
          border-radius: var(--r-md);
          box-shadow: 0 2px 12px rgba(42,31,84,0.04);
          position: relative;
          overflow: hidden;
        }

        .tkn__lore-text::before {
          content: "";
          position: absolute;
          top: 0;
          left: 0;
          width: 4px;
          height: 100%;
          background: linear-gradient(180deg, #d5fd51 0%, #7C5CFC 50%, #d5fd51 100%);
          border-radius: 4px 0 0 4px;
        }

        .tkn__lore-text p {
          font-family: "DM Sans", sans-serif;
          font-size: 14px;
          line-height: 1.9;
          color: #8a7baa;
          margin: 0 0 20px;
        }

        .tkn__lore-text p:first-child::first-letter {
          font-family: "Cinzel Decorative", serif;
          font-size: 36px;
          float: left;
          line-height: 1;
          margin-right: 8px;
          margin-top: 2px;
          color: #d5fd51;
        }

        .tkn__lore-text p:last-child {
          margin-bottom: 0;
          color: #d5fd51;
          font-weight: 600;
          font-style: italic;
          letter-spacing: 0.02em;
        }

        /* ── Legacy utility grid ── */
        .tkn__util-grid {
          display: grid;
          grid-template-columns: repeat(2, 1fr);
          gap: 16px;
        }

        .tkn__util-item {
          padding: 28px;
          background: #FBF7F0;
          border: 1px solid rgba(42,31,84,0.08);
          border-radius: var(--r-md);
          box-shadow: 0 2px 12px rgba(42,31,84,0.04);
        }

        .tkn__util-num {
          font-family: "Fredoka", sans-serif;
          font-size: 12px;
          font-weight: 500;
          color: #d5fd51;
          letter-spacing: 0.05em;
          display: block;
          margin-bottom: 12px;
        }

        .tkn__util-title {
          font-size: 14px;
          font-weight: 600;
          letter-spacing: 0.06em;
          color: #2A1F54;
          margin-bottom: 8px;
        }

        .tkn__util-desc {
          font-size: 12px;
          color: #8A7BAA;
          line-height: 1.6;
        }

        /* ═══════ RESPONSIVE ═══════ */
        @media (max-width: 768px) {
          .tkn__header-top {
            flex-direction: column;
            gap: 16px;
          }

          .tkn__header-right {
            align-items: flex-start;
            flex-direction: row;
            gap: 12px;
          }

          .tkn__creature-name {
            font-size: 18px;
          }

          .tkn__stats {
            grid-template-columns: repeat(2, 1fr);
          }

          .tkn__dist-grid {
            grid-template-columns: 1fr;
            gap: 12px;
          }

          .tkn__chart-body {
            height: 260px;
          }

          .tkn__chart-price-info {
            gap: 4px;
          }

          .tkn__lore-text {
            padding: 28px 28px 28px 32px;
          }
        }

        @media (max-width: 500px) {
          .tkn {
            padding: 32px 16px 64px;
          }

          .tkn__header {
            padding: 24px;
          }

          .tkn__creature-name {
            font-size: 16px;
          }

          .tkn__stats {
            grid-template-columns: 1fr 1fr;
            gap: 10px;
          }

          .tkn__stat {
            padding: 24px 12px;
          }

          .tkn__stat-val {
            font-size: 15px;
          }

          .tkn__util-grid {
            grid-template-columns: 1fr;
          }

          .tkn__chart-body {
            height: 220px;
          }

          .tkn__chart-last {
            display: none;
          }

          .tkn__health-meta {
            flex-direction: column;
            gap: 4px;
          }

          .tkn__table {
            padding: 4px 16px;
          }

          .tkn__lore-text {
            padding: 24px 20px 24px 28px;
          }
        }
      `}</style>
    </div>
  );
}
