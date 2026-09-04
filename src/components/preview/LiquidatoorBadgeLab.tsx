import { useMemo, useState } from "react";
import { liquidatoorBadgeSVG, sampleLiquidatoorStats } from "@/lib/liquidatoorBadgeArt";

/**
 * LiquidatoorBadgeLab — a design sandbox for the on-chain Liquidatoor trophy
 * art (route: #/badge-lab). Renders the short + long variants from the exact
 * SVG generator that will later back the Solidity tokenURI, so we can perfect
 * the look before implementing it on-chain. Re-roll to see random stats.
 */
export default function LiquidatoorBadgeLab() {
  const [seed, setSeed] = useState(0);

  const shortSvg = useMemo(
    () => liquidatoorBadgeSVG(sampleLiquidatoorStats("short", 212, "/images/liq-short.webp")),
    [seed],
  );
  const longSvg = useMemo(
    () => liquidatoorBadgeSVG(sampleLiquidatoorStats("long", 213, "/images/liq-long.webp")),
    [seed],
  );

  return (
    <div style={styles.wrap}>
      {/* make the injected fixed-size SVGs scale to their card */}
      <style>{`.badgelab-card svg { width: 100%; height: 100%; display: block; }`}</style>
      <div style={styles.head}>
        <h1 style={styles.title}>Liquidatoor Badge — Art Lab</h1>
        <p style={styles.sub}>On-chain tokenURI SVG · short (red) &amp; long (green) · terminal kill-log</p>
        <button style={styles.btn} onClick={() => setSeed((s) => s + 1)}>⟳ Re-roll stats</button>
      </div>
      <div style={styles.grid}>
        <figure style={styles.fig}>
          <div className="badgelab-card" style={styles.card} dangerouslySetInnerHTML={{ __html: shortSvg }} />
          <figcaption style={styles.cap}>SHORT liquidation</figcaption>
        </figure>
        <figure style={styles.fig}>
          <div className="badgelab-card" style={styles.card} dangerouslySetInnerHTML={{ __html: longSvg }} />
          <figcaption style={styles.cap}>LONG liquidation</figcaption>
        </figure>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  wrap: { minHeight: "100vh", background: "#0a0d12", color: "#e7ede9", padding: "48px 24px 80px", fontFamily: "'DM Mono', monospace" },
  head: { maxWidth: 1040, margin: "0 auto 32px", textAlign: "center" },
  title: { fontSize: 30, margin: "0 0 8px", letterSpacing: "-0.01em" },
  sub: { margin: "0 0 20px", opacity: 0.6, fontSize: 14 },
  btn: { background: "#1b2530", color: "#e7ede9", border: "2px solid #3ce072", borderRadius: "var(--r-sm)", padding: "10px 22px", fontFamily: "inherit", fontSize: 15, cursor: "pointer" },
  grid: { display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(340px, 1fr))", gap: 32, maxWidth: 1040, margin: "0 auto" },
  fig: { margin: 0 },
  card: { width: "100%", aspectRatio: "1 / 1", borderRadius: "var(--r-md)", overflow: "hidden", boxShadow: "0 24px 60px rgba(0,0,0,0.5)" },
  cap: { textAlign: "center", marginTop: 12, opacity: 0.7, fontSize: 13, letterSpacing: "0.1em" },
};
