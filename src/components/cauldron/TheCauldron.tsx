import { useMemo, useState, useEffect, useCallback } from "react";
import { createPortal } from "react-dom";
import { useSearchParams } from "react-router-dom";
import { useAppStore } from "@/store/useAppStore";
import FrenSprite from "@/components/shared/FrenSprite";
import PresaleModal from "@/components/presale/PresaleModal";
import SwapWidget from "@/components/cauldron/SwapWidget";
import CrystalCauldronGame from "@/components/cauldron/CrystalCauldronGame";
import PerpPanel from "@/components/cauldron/PerpPanel";
import StakePanel from "@/components/cauldron/StakePanel";
import TradingChart from "@/components/cauldron/TradingChart";
import { formatEther } from "viem";
import { useCauldronMachine, type Proposal, type Phase, type MigratableBalance } from "@/hooks/useCauldronMachine";
import { useGenesisBonus } from "@/hooks/useGenesisBonus";
import { usePerpHeatmap } from "@/hooks/usePerpHeatmap";
import { useSwapTape } from "@/hooks/useSwapTape";
import { useAllowedQuotes, useCurrentQuote } from "@/hooks/useAllowedQuotes";
import { TreasuryRotation } from "@/components/cauldron/TreasuryRotation";
import { useSeedProgress } from "@/hooks/useSeedProgress";
import { useLiveSwaps } from "@/hooks/useLiveSwaps";
import { SpellFeed } from "@/components/cauldron/SpellFeed";
import { ActivityDrawer } from "@/components/cauldron/ActivityDrawer";
import { useIndexerHealth } from "@/hooks/useIndexerHealth";
import { NATIVE_QUOTE, quoteMeta, isNativeQuote } from "@/config/quotes";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { nftCollectionUrl, NETWORK_LABEL, NETWORK_SHORT } from "@/config/chains";
import { useMiFrensPresale } from "@/hooks/useMiFrensPresale";
import { PRESALE } from "@/config/presale";
import { BODIES, FACES, GNOME_FACES, ELF_FACES, ITEMS, CLASS_ORDER, type FrenClass, type TraitLayer } from "@/data/frens";

const FRENS_PATH = "/frens/";

/** The console's views. Mirrors the sub-items in `layout/navItems.ts`. */
const TAB_KEYS = ["reactor", "leverage", "stake", "governance", "lineage"] as const;
type TabKey = (typeof TAB_KEYS)[number];

/* ═══════════════════════════════════════════════════════════════
 * THE CAULDRON — a living, autonomous on-chain machine, on life support.
 *
 * "Life-Support Grimoire": the current iteration is a breathing reactor
 * core whose glow tracks its vitality (lime alive → amber dying → red
 * dead). An EKG line plots the real V4 price; when volume dies the pulse
 * flatlines and the RELAUNCH ritual ignites. Everything is live chain data.
 * ═══════════════════════════════════════════════════════════════ */

/* ── palette ─────────────────────────────────────────────────────── */
// ── Refined Arcane palette (tokenized) ──────────────────────────────
//  Ink ramp for structure · lime as the SHARP hero accent (not fills) ·
//  violet as the secondary accent · one red / one gold / one green.
const C = {
  void: "#0E0A1A",                    // deepest ink (purple undertone)
  panel: "rgba(28, 20, 54, 0.60)",    // glass panel
  edge: "rgba(213, 253, 81, 0.14)",   // lime hairline
  lime: "#d5fd51",                    // HERO accent
  violet: "#7c5cfc",                  // SECONDARY accent
  amber: "#f5c542",                   // gold — one warm signal (dying/rare)
  red: "#ff4d6d",                     // one red — sell / death / error
  green: "#3ddc84",                   // one green — success / live
  cream: "#f5f0e8",                   // paper / primary text on dark
  mute: "#8f83b8",                    // muted text (single mid-lavender)
  dim: "#b8adcc",                     // dim text step
};

function phaseColor(phase: Phase): string {
  return phase === "dead" ? C.red : phase === "dying" ? C.amber : C.lime;
}

/** Turn a viem/wallet error into a short, human sentence so a failed vote /
 *  relaunch / propose never fails silently (the old `catch {}` hid the reason). */
function friendlyErr(e: unknown): string {
  const raw = (() => {
    const err = e as { shortMessage?: string; details?: string; message?: string };
    return err?.shortMessage || err?.details || err?.message || String(e);
  })();
  const s = raw.toLowerCase();
  if (s.includes("user rejected") || s.includes("user denied") || s.includes("rejected the request")) return "Transaction rejected in your wallet.";
  if (s.includes("novotingpower")) return "This wallet holds no MiFrens — you need a MiFren to vote or propose.";
  if (s.includes("alreadyvoted")) return "This wallet has already voted on that proposal.";
  if (s.includes("snapshotnotready")) return "Voting opens one block after a proposal is created — try again in a few seconds.";
  if (s.includes("noproposal") || s.includes("noproposals")) return "No proposal has any votes yet — vote for one first, then relaunch.";
  if (s.includes("alreadyconsumed")) return "That proposal has already been summoned.";
  if (s.includes("tokenisdead")) return "That iteration's token is frozen (it died) — its balance can be migrated, not transferred.";
  if (s.includes("timelock")) return "The emergency timelock is still counting down.";
  if (s.includes("insufficient funds")) return "Not enough ETH for gas.";
  if (s.includes("chain") && s.includes("switch")) return `Switch your wallet to ${NETWORK_LABEL} and try again.`;
  return raw.length > 140 ? raw.slice(0, 140) + "…" : raw;
}

/* ── fren avatars (proposer faces) ───────────────────────────────── */
function facesFor(cls: FrenClass) {
  return cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
}
function frenFromSeed(seed: number, forceClass?: FrenClass) {
  const cls = forceClass ?? CLASS_ORDER[seed % CLASS_ORDER.length];
  const bodies = BODIES[cls]; const items = ITEMS[cls]; const faces = facesFor(cls);
  const bodyIdx = (seed * 7 + 3) % bodies.length;
  const faceIdx = (seed * 13 + 5) % faces.length;
  const itemIdx = (seed * 5 + 2) % items.length;
  return { bodyFile: bodies[bodyIdx].file, faceFile: faces[faceIdx].file, itemFile: items[itemIdx].file, bodyIdx, faceIdx, itemIdx };
}
function addrSeed(a?: string) {
  if (!a) return 7;
  let h = 0; for (let i = 2; i < a.length; i++) h = (h * 31 + a.charCodeAt(i)) >>> 0;
  return h;
}
function FrenFace({ seed, size = 40, ring }: { seed: number; size?: number; ring?: string }) {
  const f = useMemo(() => frenFromSeed(seed), [seed]);
  return (
    <div className="tc-face" style={{ width: size, height: size, borderRadius: size > 60 ? "var(--r-md)" : "50%", boxShadow: `0 0 0 2px ${ring ?? "rgba(255,255,255,0.12)"}` }}>
      <div className="tc-face__zoom">
        <FrenSprite bodyFile={f.bodyFile} faceFile={f.faceFile} itemFile={f.itemFile} bodyIdx={f.bodyIdx} faceIdx={f.faceIdx} itemIdx={f.itemIdx} alt="" />
      </div>
    </div>
  );
}

/* ── icons ───────────────────────────────────────────────────────── */
const I = {
  bolt: (p: { size?: number }) => <svg width={p.size ?? 14} height={p.size ?? 14} viewBox="0 0 24 24" fill="currentColor"><path d="M13 2L3 14h7l-1 8 10-12h-7z" /></svg>,
  vote: (p: { size?: number }) => <svg width={p.size ?? 15} height={p.size ?? 15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 11l3 3L22 4" /><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" /></svg>,
  skull: (p: { size?: number }) => <svg width={p.size ?? 14} height={p.size ?? 14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a9 9 0 0 0-5 16v3h10v-3a9 9 0 0 0-5-16z" /><circle cx="9" cy="12" r="1.4" fill="currentColor" /><circle cx="15" cy="12" r="1.4" fill="currentColor" /></svg>,
  globe: (p: { size?: number }) => <svg width={p.size ?? 12} height={p.size ?? 12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c2.5 2.5 3.5 6 3.5 9s-1 6.5-3.5 9c-2.5-2.5-3.5-6-3.5-9s1-6.5 3.5-9z" /></svg>,
  x: (p: { size?: number }) => <svg width={p.size ?? 12} height={p.size ?? 12} viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" /></svg>,
  opensea: (p: { size?: number }) => <svg width={p.size ?? 13} height={p.size ?? 13} viewBox="0 0 24 24" fill="currentColor"><path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0ZM5.92 12.4l.05-.08 3.12-4.88a.107.107 0 0 1 .188.013c.52 1.17.973 2.624.76 3.53-.09.37-.334.874-.61 1.34-.036.067-.075.132-.116.196a.108.108 0 0 1-.09.048H6.013a.108.108 0 0 1-.093-.165zm13.91 1.2a.11.11 0 0 1-.062.1c-.267.115-1.174.549-1.552 1.075-.964 1.343-1.7 3.264-3.35 3.264H8.196a3.457 3.457 0 0 1-3.446-3.464v-.152a.109.109 0 0 1 .108-.108h3.48a.11.11 0 0 1 .11.11c0 .373.11.663.318.89.209.229.51.375.888.375h1.723v-1.345h-1.7a.11.11 0 0 1-.09-.172l.065-.094c.174-.246.42-.628.665-1.062.166-.293.328-.607.457-.923.026-.055.047-.113.07-.17.036-.099.073-.193.099-.287.026-.08.047-.163.068-.24.052-.223.074-.469.074-.723 0-.1-.004-.205-.013-.306-.005-.11-.019-.22-.033-.331a5.13 5.13 0 0 0-.048-.297 6.86 6.86 0 0 0-.096-.445l-.014-.06c-.03-.108-.056-.21-.09-.317a11.31 11.31 0 0 0-.36-1.001c-.045-.127-.096-.248-.15-.367-.077-.19-.156-.36-.229-.522a4.75 4.75 0 0 0-.1-.204l-.117-.235c-.028-.055-.06-.107-.082-.157l-.236-.436c-.033-.06.02-.132.086-.113l1.317.357h.01l.174.048.19.055.07.019v-.783c0-.379.303-.686.679-.686a.68.68 0 0 1 .476.194.664.664 0 0 1 .2.492v1.162l.141.04c.01.004.021.009.03.016.033.024.08.06.14.106.048.036.098.08.156.128.116.093.254.213.401.34.288.269.612.585.921.936.087.099.171.198.259.302.086.106.177.21.256.314.105.14.216.284.315.435.045.07.098.142.14.211.123.183.23.373.331.563.043.086.087.18.125.272.114.256.204.516.261.777.017.056.03.114.043.171v.008c.02.076.026.158.033.242a2.51 2.51 0 0 1-.014.526c-.023.148-.06.29-.104.428a3.85 3.85 0 0 1-.15.398c-.115.266-.25.535-.411.783-.052.093-.114.19-.176.284-.067.099-.138.193-.199.284-.084.116-.172.238-.263.347-.081.11-.164.218-.257.316-.128.153-.25.298-.379.435-.075.088-.156.178-.242.26-.075.075-.152.148-.227.219-.126.126-.234.224-.323.305l-.209.19a.11.11 0 0 1-.072.028h-1.048v1.345h1.318c.294 0 .574-.104.799-.294.077-.068.417-.362.82-.807a.098.098 0 0 1 .046-.03l3.643-1.052a.109.109 0 0 1 .139.104z" /></svg>,
};

function short(a?: string) {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "—";
}
function fmt(n: number, dp = 2) {
  if (!Number.isFinite(n)) return "0";
  if (n === 0) return "0";
  if (n < 0.0001) return n.toExponential(2);
  return n.toLocaleString(undefined, { maximumFractionDigits: dp });
}
/** Countdown "1h 04m" / "4m 12s" / "48s" from seconds remaining. */
function fmtCountdown(secs: number): string {
  const s = Math.max(0, Math.floor(secs));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  if (h > 0) return `${h}h ${String(m).padStart(2, "0")}m`;
  if (m > 0) return `${m}m ${String(sec).padStart(2, "0")}s`;
  return `${sec}s`;
}
/** Price in USD (falls back to ETH if the feed is unavailable). */
function usdPrice(priceUsd: number, priceEth: number): string {
  if (priceUsd > 0) {
    if (priceUsd < 0.01) return `$${priceUsd.toPrecision(3)}`;
    return `$${priceUsd.toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
  }
  return priceEth > 0 ? `${(priceEth * 1e9).toFixed(2)} gwei` : "—";
}
/** Compact USD for market cap: $1.2M, $940K, $3.1B. */
function usdCompact(v: number): string {
  if (v >= 1e9) return `$${(v / 1e9).toFixed(2)}B`;
  if (v >= 1e6) return `$${(v / 1e6).toFixed(2)}M`;
  if (v >= 1e3) return `$${(v / 1e3).toFixed(1)}K`;
  return `$${v.toFixed(0)}`;
}

/* ═══════════════════════ EKG price chart + liquidation heatmap ═══════════ */
const BUY_C = "rgb(70,230,124)";
const SELL_C = "rgb(255,86,96)";
const LIQ_LONG = "#ff5470";  // long liquidation walls (below price)
const LIQ_SHORT = "#d5fd51"; // short liquidation walls (above price)
const HEAT_ROWS = 26;

type LiqPos = { isLong: boolean; liqPrice: number; notionalEth: number };

function EKG({ series, color, dead, liq }: { series: number[]; color: string; dead: boolean; liq?: LiqPos[] }) {
  const W = 640, H = 180, pad = 8;

  // Y-domain: the series range, expanded to REVEAL the liquidation walls (that's
  // the whole point). Walls sit ~25–45% from spot, so we include any wall within
  // a wide band around the current price (bounded so a crazy outlier can't squash
  // the line). The price line compresses a little — the walls become visible.
  const domain = useMemo(() => {
    if (series.length < 2) return null;
    let lo = Math.min(...series), hi = Math.max(...series);
    const cur = series[series.length - 1] || hi;
    const bLo = cur * 0.35, bHi = cur * 1.9; // include walls within this band of spot
    for (const p of liq ?? []) {
      if (p.liqPrice >= bLo && p.liqPrice <= bHi) { lo = Math.min(lo, p.liqPrice); hi = Math.max(hi, p.liqPrice); }
    }
    const span = hi - lo || hi * 0.1 || 1;
    return { lo: lo - span * 0.06, hi: hi + span * 0.06, span: span * 1.12 };
  }, [series, liq]);

  const yOf = (v: number) => domain ? H - pad - ((v - domain.lo) / domain.span) * (H - pad * 2) : H / 2;

  const path = useMemo(() => {
    if (!domain || series.length < 2) return "";
    const dx = (W - pad * 2) / (series.length - 1);
    return series.map((v, i) => `${i === 0 ? "M" : "L"}${(pad + i * dx).toFixed(1)},${yOf(v).toFixed(1)}`).join(" ");
  }, [series, domain]);

  // Bucket open positions into price rows → liquidation density per side.
  const rows = useMemo(() => {
    if (!domain || !liq || liq.length === 0) return [];
    const bins: { long: number; short: number }[] = Array.from({ length: HEAT_ROWS }, () => ({ long: 0, short: 0 }));
    for (const p of liq) {
      if (p.liqPrice < domain.lo || p.liqPrice > domain.hi) continue;
      const frac = (p.liqPrice - domain.lo) / domain.span;
      const idx = Math.min(HEAT_ROWS - 1, Math.max(0, Math.floor(frac * HEAT_ROWS)));
      if (p.isLong) bins[idx].long += p.notionalEth; else bins[idx].short += p.notionalEth;
    }
    const max = Math.max(1e-9, ...bins.map((b) => b.long + b.short));
    const rh = (H - pad * 2) / HEAT_ROWS;
    return bins.map((b, i) => {
      const total = b.long + b.short;
      if (total <= 0) return null;
      const y = H - pad - (i + 1) * rh;
      const isLong = b.long >= b.short;
      return { y, rh, intensity: total / max, isLong, total };
    }).filter(Boolean) as { y: number; rh: number; intensity: number; isLong: boolean; total: number }[];
  }, [liq, domain]);

  const last = series.length ? series[series.length - 1] : 0;
  const hasHeat = rows.length > 0;


  return (
    <div className="tc-ekg">
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="tc-ekg__svg">
        <defs>
          <linearGradient id="ekgfill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity="0.28" />
            <stop offset="100%" stopColor={color} stopOpacity="0" />
          </linearGradient>
          <filter id="ekgglow"><feGaussianBlur stdDeviation="2.4" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
        </defs>
        {[0.25, 0.5, 0.75].map((g) => <line key={g} x1="0" x2={W} y1={H * g} y2={H * g} stroke="rgba(255,255,255,0.05)" strokeWidth="1" />)}

        {/* liquidation heatmap: full-width bands (the walls the market hunts) +
            a right-anchored density histogram sized by stacked notional. */}
        {rows.map((r, i) => {
          const c = r.isLong ? LIQ_LONG : LIQ_SHORT;
          const barW = (W - pad * 2) * (0.12 + 0.33 * r.intensity);
          return (
            <g key={i}>
              <rect x="0" y={r.y} width={W} height={r.rh + 0.6} fill={c} opacity={0.05 + 0.22 * r.intensity} />
              <rect x={W - pad - barW} y={r.y + r.rh * 0.18} width={barW} height={r.rh * 0.64} rx="1" fill={c} opacity={0.35 + 0.5 * r.intensity} />
            </g>
          );
        })}

        {path && (
          <>
            <path d={`${path} L${W - pad},${H} L${pad},${H} Z`} fill="url(#ekgfill)" />
            <path d={path} fill="none" stroke={color} strokeWidth="2.2" filter="url(#ekgglow)" className={dead ? "" : "tc-ekg__line"} strokeLinecap="round" strokeLinejoin="round" />

          </>
        )}
      </svg>
      <div className="tc-ekg__last" style={{ color }}>
        {last > 0 ? `${(last * 1e9).toFixed(2)} gwei` : "—"}
      </div>
      {hasHeat && (
        <div className="tc-ekg__legend">
          <span><i style={{ background: LIQ_SHORT }} />short liqs</span>
          <span><i style={{ background: LIQ_LONG }} />long liqs</span>
        </div>
      )}
      {series.length < 2 && <div className="tc-ekg__empty">awaiting first swaps…</div>}
    </div>
  );
}

/* ═══════════════════════ brew profile (Twitter-style) ═══════════════════════ */
type Brand = { banner: string; logo: string; website?: string; x?: string; accent?: string };
const BREW_BRAND: Record<string, Brand> = {
  GNOME: { banner: "/brews/gnome-banner.jpg", logo: "/brews/gnomeland-pfp.png", website: "gnomeland.quest", x: "Gnome0xLand", accent: "#d5fd51" },
  // future iterations add their branding here (or fall back to the generic card)
};
// Branding for PROPOSALS (by ticker) — logo + fren banner so a branded next brew
// stands out + gets a full brew-profile modal. MIF = the MiFrens flagship.
const PROPOSAL_BRAND: Record<string, { logo: string; banner: string; accent: string; logoBg: string }> = {
  MIF: { logo: "/mifrens-logo.svg", banner: "/mifrens-frens-banner.png", accent: "#d5fd51", logoBg: "#2A1F54" },
};

function BrewProfile({ name, ticker, gen, genNum, phase, col, collection }: { name: string; ticker: string; gen: string; genNum: number; phase: Phase; col: string; collection?: string }) {
  const fallback = BREW_BRAND[ticker?.toUpperCase?.() ?? ""];
  const [uploaded, setUploaded] = useState<{ logo?: string; banner?: string }>({});
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);

  // Load any uploaded PFP/banner for this iteration (survives reindex).
  useEffect(() => {
    let alive = true;
    fetch(`/api/brand?gen=${genNum}`).then((r) => r.ok ? r.json() : null).then((d) => {
      if (alive && d) setUploaded({ logo: d.logo || undefined, banner: d.banner || undefined });
    }).catch(() => {});
    return () => { alive = false; };
  }, [genNum]);

  const logo = uploaded.logo || fallback?.logo;
  const banner = uploaded.banner || fallback?.banner;
  const liveDot = phase === "dead" ? C.red : phase === "dying" ? C.amber : C.lime;

  const pickFile = (which: "logo" | "banner") => {
    const inp = document.createElement("input");
    inp.type = "file"; inp.accept = "image/*";
    inp.onchange = () => {
      const f = inp.files?.[0]; if (!f) return;
      const rd = new FileReader();
      rd.onload = () => setUploaded((u) => ({ ...u, [which]: rd.result as string }));
      rd.readAsDataURL(f);
    };
    inp.click();
  };
  const save = async () => {
    setSaving(true);
    try {
      await fetch("/api/brand", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ gen: genNum, logo: uploaded.logo, banner: uploaded.banner }) });
      setEditing(false);
    } catch { /* ignore */ } finally { setSaving(false); }
  };

  return (
    <div className="tc-profile">
      <div className="tc-profile__banner" style={banner ? { backgroundImage: `url(${banner})` } : { background: `linear-gradient(120deg, ${col}22, #1b1436)` }}>
        <span className="tc-profile__gen" style={{ color: liveDot, borderColor: `${liveDot}55` }}>
          <span className="tc-profile__dot" style={{ background: liveDot, boxShadow: `0 0 8px ${liveDot}` }} /> ITER {gen} · {phase.toUpperCase()}
        </span>
        <button className="tc-profile__edit" onClick={() => setEditing((e) => !e)} title="Upload PFP + banner">✎</button>
      </div>
      {editing && (
        <div className="tc-profile__editbar">
          <button onClick={() => pickFile("logo")}>Upload PFP</button>
          <button onClick={() => pickFile("banner")}>Upload banner</button>
          <button className="tc-profile__save" onClick={save} disabled={saving}>{saving ? "Saving…" : "Save"}</button>
        </div>
      )}
      <div className="tc-profile__logo" style={{ boxShadow: `0 0 0 3px #171226, 0 0 22px ${col}55` }}>
        {logo ? <img src={logo} alt={name} /> : <span className="tc-profile__initial" style={{ color: col }}>{(ticker || "?")[0]}</span>}
      </div>
      <div className="tc-profile__body">
        <h2 className="tc-profile__name">{name || "…"}</h2>
        <div className="tc-profile__handle">
          <span className="tc-profile__tick tc-mono" style={{ color: col }}>${ticker || "…"}</span>
          <span className="tc-profile__by">· by Magic Internet Frens</span>
        </div>
        {(fallback?.website || fallback?.x || collection) && (
          <div className="tc-profile__links">
            {fallback?.website && (
              <a className="tc-profile__link" href={`https://${fallback.website}`} target="_blank" rel="noopener">
                <I.globe size={13} /> {fallback.website}
              </a>
            )}
            {fallback?.x && (
              <a className="tc-profile__link" href={`https://x.com/${fallback.x}`} target="_blank" rel="noopener">
                <I.x size={12} /> @{fallback.x}
              </a>
            )}
            {collection && (
              <a className="tc-profile__link tc-profile__link--os" href={nftCollectionUrl(collection)} target="_blank" rel="noopener" title={`View the collection on ${NETWORK_SHORT === "Robinhood" ? "the explorer" : "OpenSea"}`}>
                <I.opensea size={14} /> {NETWORK_SHORT === "Robinhood" ? "Explorer" : "OpenSea"}
              </a>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

/* ═══════════════════════ reactor core (legacy, unused) ═══════════════════════ */
function Core({ vitality, phase, ticker }: { vitality: number; phase: Phase; ticker: string }) {
  const col = phaseColor(phase);
  const intensity = phase === "dead" ? 0.12 : 0.25 + (vitality / 100) * 0.6;
  return (
    <div className="tc-core" style={{ ["--cc" as string]: col, ["--ci" as string]: intensity }}>
      <div className={`tc-core__halo ${phase === "dead" ? "" : "tc-core__halo--pulse"}`} />
      <div className="tc-core__ring tc-core__ring--a" />
      <div className="tc-core__ring tc-core__ring--b" />
      <div className={`tc-core__orb ${phase === "dead" ? "tc-core__orb--cold" : "tc-core__orb--live"}`}>
        <span className="tc-core__tick">${ticker || "…"}</span>
      </div>
    </div>
  );
}

/* ═══════════════════════ main ═══════════════════════ */
export default function TheCauldron() {
  const m = useCauldronMachine();
  // Websocket ping on every swap in our pool: a trade made on ANY machine
  // refreshes the chart and tape the moment its block is seen, instead of
  // waiting out the poll interval. The polls stay as the fallback.
  const live_ = useLiveSwaps();
  // Says out loud when the data behind the page is not trustworthy, rather than
  // letting an empty indexer render as a confident, wrong, empty page.
  const health = useIndexerHealth();
  const presale = useMiFrensPresale();
  // Live perp positions → liquidation heatmap + OHLC candles (all from Ponder).
  const heat = usePerpHeatmap(m.summoned && m.phase !== "dead", m.gen);
  // m.txHash advances on every confirmed action, so the tape re-pulls right
  // after a swap instead of waiting out its interval.
  // The websocket nonce is passed as the refresh key, so a swap made ANYWHERE —
  // another browser, a bot, a raw Uniswap trade — refetches the tape the moment
  // the block is seen, instead of waiting out the poll interval. The 5s poll
  // stays as the fallback for when the socket is down.
  const tradeTape = useSwapTape(
    m.gen,
    m.summoned,
    5000,
    m.confirmed ? m.txHash : `ws:${live_.nonce}`,
  );
  // What THIS brew is priced in. Fixed at summon, so it is read once per
  // generation rather than polled hard.
  const liveQuoteAddr = useCurrentQuote(m.gen);
  // Progressive launch: depth streams in over a window rather than landing at
  // once, so the page shows it filling instead of just looking thin.
  const seed = useSeedProgress();
  const liveQuote = quoteMeta(liveQuoteAddr);
  const perpsAvailable = isNativeQuote(liveQuoteAddr);
  // The freshest spot = the latest trade on the Ponder tape (updates every ~5s,
  // same source as the chart). Falls back to the machine's spot until the tape
  // loads. Used for live perp PnL so it tracks the chart, not a slower feed.
  const livePerpPrice = tradeTape.length ? tradeTape[tradeTape.length - 1].price : m.spotPrice;

  // The brew EKG plots the SAME tape the trading chart does. Deriving both from
  // one source is what keeps them consistent; the tape is already fetched above
  // for the chart, so this costs no extra request.
  const ekgSeries = useMemo(() => {
    const base = tradeTape.length >= 2 ? tradeTape.map((t) => t.price) : m.priceSeries;

    //  LIVE TAIL, HANDED OVER BY TIMESTAMP.
    //
    //  The indexer builds the tape, so a fresh trade only reaches the chart once
    //  Ponder has indexed its block. Each swap already carries its post-trade
    //  sqrtPriceX96 on the wire, so the price it left behind is known the instant
    //  the block is seen — this covers that gap and nothing more.
    //
    //  The handoff is the part that has to be right. An earlier version appended
    //  the last few live prices and only dropped one that exactly equalled the
    //  tape's final point, so once the indexer caught up the SAME trades were
    //  drawn twice — the chart kicked and doubled back. Comparing timestamps
    //  instead means a live point disappears the moment the indexed tape covers
    //  its block, which is a clean handover rather than a guess.
    const newestIndexed = tradeTape.length > 0
      ? Math.max(...tradeTape.map((t) => t.t)) * 1000
      : 0;

    const live = live_.recent
      .filter((sw) => (sw.kind === "buy" || sw.kind === "sell") && sw.price > 0)
      // Only what the tape has NOT reached yet. A small lag allowance absorbs
      // block-time vs wall-clock skew without letting a real trade slip through.
      .filter((sw) => newestIndexed === 0 || sw.ts > newestIndexed + 4000)
      .sort((a, b) => a.ts - b.ts)
      .map((sw) => sw.price);

    if (live.length === 0) return base;
    return [...base, ...live.slice(-4)];
  }, [tradeTape, m.priceSeries, live_.recent]);
  // The view lives in the URL (`?v=…`) rather than local state: the left rail
  // owns the tab strip now, and Leverage / Governance become shareable links.
  const [searchParams, setSearchParams] = useSearchParams();
  const rawTab = searchParams.get("v");
  const parsedTab: TabKey = (TAB_KEYS as readonly string[]).includes(rawTab ?? "")
    ? (rawTab as TabKey)
    : "reactor";
  // Leverage renders nothing before a generation is live, so a deep link to it
  // on an unsummoned machine lands on the brew instead of an empty page.
  const needsBrew = parsedTab === "leverage" || parsedTab === "stake";
  const tab: TabKey = needsBrew && !m.summoned && !m.loading ? "reactor" : parsedTab;
  const setTab = useCallback(
    (next: TabKey) => setSearchParams({ v: next }, { replace: true }),
    [setSearchParams],
  );
  const [showPresale, setShowPresale] = useState(false);
  const [autoMint, setAutoMint] = useState(false);
  const [mintQty, setMintQty] = useState(1);
  const [justSummoned, setJustSummoned] = useState(false);
  const [busyVote, setBusyVote] = useState<number | null>(null);
  const [openProposal, setOpenProposal] = useState<Proposal | null>(null);
  const [busyRelaunch, setBusyRelaunch] = useState(false);
  const [showPropose, setShowPropose] = useState(false);
  const [busyPropose, setBusyPropose] = useState(false);
  const [flash, setFlash] = useState<{ kind: "ok" | "err"; msg: string } | null>(null);
  const notify = useCallback((kind: "ok" | "err", msg: string) => {
    setFlash({ kind, msg });
    window.clearTimeout((notify as unknown as { _t?: number })._t);
    (notify as unknown as { _t?: number })._t = window.setTimeout(() => setFlash(null), 6500);
  }, []);

  // Publish the live counters the left rail shows next to its sub-items. The
  // rail sits outside this component, so it reads them from the store rather
  // than re-querying the chain.
  const setCauldronNav = useAppStore((s) => s.setCauldronNav);
  useEffect(() => {
    setCauldronNav({
      summoned: m.summoned,
      perps: heat.openCount || 0,
      proposals: m.proposals.length,
      gen: m.summoned ? m.gen : 0,
    });
  }, [heat.openCount, m.proposals.length, m.summoned, m.gen, setCauldronNav]);

  // Deflation: total supply burned across all iterations (from the indexer).
  // Each generation mints a fixed 777M; burns (unclaimed pools + LP recovery)
  // only ever shrink it — so this is the machine's lifetime burn %.
  const [burn, setBurn] = useState<{ tokens: number; pct: number } | null>(null);
  useEffect(() => {
    const base = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "/api";
    let alive = true;
    const load = async () => {
      try {
        const r = await fetch(`${base}/iterations`, { signal: AbortSignal.timeout(6000) });
        if (!r.ok) return;
        const d = await r.json() as { iterations?: unknown[]; totalBurned?: string; supplyPerGen?: string };
        const gens = Math.max(1, (d.iterations?.length ?? 1));
        const burned = Number(d.totalBurned ?? "0") / 1e18;
        const supply = (Number(d.supplyPerGen ?? "0") / 1e18) * gens;
        if (alive) setBurn({ tokens: burned, pct: supply > 0 ? (burned / supply) * 100 : 0 });
      } catch { /* indexer down → hide the stat */ }
    };
    load();
    const id = setInterval(load, 30_000);
    return () => { alive = false; clearInterval(id); };
  }, []);

  const col = phaseColor(m.phase);
  const genLabel = m.summoned ? `#${String(m.gen).padStart(2, "0")}` : "—";
  const totalVotes = m.proposals.reduce((a, p) => a + p.votes, 0) || 1;

  const onVote = async (id: number) => {
    setBusyVote(id);
    try {
      const hash = await m.voteFor(id);      // submitted
      notify("ok", "Vote submitted — confirming on-chain…");
      await m.waitForReceipt(hash);           // mined
      await m.refresh();                      // pull the new tally
      notify("ok", "Vote counted ✓");
    } catch (e) {
      notify("err", friendlyErr(e));
    } finally { setBusyVote(null); }
  };
  const [busyClaim, setBusyClaim] = useState<number | null>(null);
  const onClaimPrev = async (gen: number, amount: bigint, symbol: string) => {
    setBusyClaim(gen);
    try {
      const hash = await m.claimPrev(gen, amount);
      notify("ok", `Migrating $${symbol} → $${m.ticker}…`);
      await m.waitForReceipt(hash);
      await m.refresh();
      notify("ok", `Migrated to $${m.ticker} ✓`);
    } catch (e) {
      notify("err", friendlyErr(e));
    } finally { setBusyClaim(null); }
  };
  const onRelaunch = async () => {
    setBusyRelaunch(true);
    try {
      const hash = await m.relaunch();
      notify("ok", "Relaunch ritual submitted — summoning…");
      await m.waitForReceipt(hash);
      setJustSummoned(true);
      await m.refresh();
      notify("ok", "The Cauldron has relaunched ✓");
    } catch (e) {
      notify("err", friendlyErr(e));
    } finally { setBusyRelaunch(false); }
  };
  // After a summon, poll fast until the new iteration shows up on-chain, then
  // clear the "materializing" state → graceful reveal instead of a stale page.
  useEffect(() => {
    if (m.summoned && justSummoned) setJustSummoned(false);
  }, [m.summoned, justSummoned]);
  // Safety: never let the "Summoning…" screen stick. A real summon confirms in
  // well under a minute; clear the flag after 60s so a stale/aborted flow can't
  // pin the page on the summoning state.
  useEffect(() => {
    if (!justSummoned) return;
    const id = setTimeout(() => setJustSummoned(false), 60_000);
    return () => clearTimeout(id);
  }, [justSummoned]);
  useEffect(() => {
    if (!justSummoned || m.summoned) return;
    const id = setInterval(() => m.refresh(), 2500);
    return () => clearInterval(id);
  }, [justSummoned, m.summoned, m.refresh]);

  const onPropose = async (p: {
    name: string; symbol: string; nftSupply: number; mintOutEth: number;
    renderer?: string; baseURI?: string; website?: string; socials?: string;
  }) => {
    setBusyPropose(true);
    try {
      const hash = await m.propose(p);
      notify("ok", "Proposal submitted — confirming…");
      await m.waitForReceipt(hash);
      setShowPropose(false);
      await m.refresh();
      notify("ok", "Proposal is live ✓");
    } catch (e) {
      notify("err", friendlyErr(e));
    } finally { setBusyPropose(false); }
  };

  return (
    <div className="tc">
      {/* Page-level, not inside the trade tab: a liquidation or a forged fren
          should still announce while you are reading governance. Portals to
          document.body, so no card's backdrop-filter can capture its
          position:fixed. */}
      <SpellFeed events={live_.recent} glyph={liveQuote.glyph || liveQuote.symbol} />
      <ActivityDrawer events={live_.recent} glyph={liveQuote.glyph || liveQuote.symbol} />
      {health.degraded && (
        <div className={`tc-health is-${health.state}`} role="status">
          <span className="tc-health__dot" />
          <span className="tc-mono">
            {health.state === "down" ? "indexer unreachable" : health.reason}
            {" · "}
            <b>live prices still on-chain</b>
          </span>
        </div>
      )}
      <div className="tc-embers" aria-hidden>
        {Array.from({ length: 14 }).map((_, i) => <span key={i} className="tc-ember" style={{ left: `${(i * 7 + 4) % 100}%`, animationDelay: `${(i * 0.9) % 8}s`, animationDuration: `${7 + (i % 5)}s` }} />)}
      </div>

      {flash && (
        <div className="tc-toast" role="status" style={{
          borderColor: flash.kind === "ok" ? C.green : C.red,
          color: flash.kind === "ok" ? C.green : C.red,
        }}>
          <span className="tc-toast__dot" style={{ background: flash.kind === "ok" ? C.green : C.red }} />
          {flash.msg}
        </div>
      )}

      {/* ── masthead ── */}
      <header className="tc-top">
        <div>
          <h1 className="tc-wordmark">The Cauldron</h1>
          <p className="tc-sub">Eternal · autonomous · never halted</p>
        </div>
        <div className="tc-stats">
          <Stat label="Status" value={m.loading ? "syncing" : m.summoned ? m.phase : "genesis"} color={col} />
          <Stat label="Iteration" value={genLabel} />
          <Stat label="24h Volume" value={m.summoned ? `${fmt(m.vol24hEth, 3)} Ξ` : "—"} />
          <Stat label="Floor Vault" value={m.summoned ? `${fmt(m.vaultEth, 3)} Ξ` : "—"} color={C.lime} />
          {burn && burn.tokens > 0 && (
            <Stat label="Supply Burned" value={`${burn.pct < 0.01 ? "<0.01" : fmt(burn.pct, 2)}%`} color={C.amber} />
          )}
        </div>
      </header>

      {/* ── OG genesis token airdrop (self-hides when nothing is due) ── */}
      {m.summoned && <GenesisBonusPanel notify={notify} />}

      {/* ── migrate previous-iteration balances (only when you hold dead tokens) ── */}
      {m.summoned && m.migratable.length > 0 && (
        <MigratePanel
          items={m.migratable}
          currentTicker={m.ticker}
          busyGen={busyClaim}
          onClaim={onClaimPrev}
        />
      )}

      {/* The tab strip lives in the left rail — see `layout/AppSidebar`. */}

      <div className="tc-main">
        {/* ══ REACTOR ══ */}
        {tab === "reactor" && (
          <>
            {(m.loading || (justSummoned && !m.summoned)) ? (
              <SummoningState summoning={justSummoned && !m.summoned} />
            ) : !m.summoned ? (
              <PresalePanel
                minted={presale.minted ?? m.presaleMinted}
                goal={m.presaleGoal}
                onOpen={() => { setAutoMint(false); setShowPresale(true); }}
                onMintNow={(qty) => { setMintQty(qty); setAutoMint(true); setShowPresale(true); }}
                soldOut={!!presale.soldOut}
                presale={presale}
              />
            ) : (
              <div className="tc-reactor">
                {/* left: brew profile (Twitter-style) + vitality */}
                <section className="tc-card tc-core-card">
                  <BrewProfile name={m.name} ticker={m.ticker} gen={genLabel} genNum={m.gen} phase={m.phase} col={col} collection={m.collection} />

                  <div className="tc-vital">
                    <div className="tc-vital__row">
                      <span className="tc-mono tc-dim">VITALITY</span>
                      <span className="tc-mono" style={{ color: col }}>{Math.round(m.vitality)}%</span>
                    </div>
                    <div className="tc-vital__track">
                      <div className={`tc-vital__fill ${m.phase === "dead" ? "" : "tc-vital__fill--beat"}`} style={{ width: `${Math.max(m.vitality, 3)}%`, background: col, boxShadow: `0 0 18px ${col}` }} />
                    </div>
                    <p className="tc-vital__note">
                      {m.phase === "live" && "The brew is thriving. Every swap forges an NFT and lifts the floor."}
                      {m.phase === "dying" && `Volume below the death floor (${fmt(m.deathThresholdEth, 0)} Ξ/24h). The brew is fading…`}
                      {m.phase === "dead" && "The brew has died. Perform the relaunch ritual to summon the winning proposal."}
                    </p>
                  </div>

                  {m.phase === "dead" ? (
                    <RelaunchPanel
                      proposals={m.proposals}
                      relaunchAt={m.relaunchAt}
                      busy={busyRelaunch}
                      col={col}
                      onRelaunch={onRelaunch}
                      onPropose={() => setTab("governance")}
                    />
                  ) : (
                    <div className="tc-reserve" title="LP liquidity + hook fee reserve + floor vault — all of it seeds the next iteration's pool on relaunch">
                      <span className="tc-mono tc-dim">AVAILABLE FOR NEXT LAUNCH</span>
                      <span className="tc-reserve__eth">{fmt(m.availableEth, 4)} <em>Ξ</em></span>
                    </div>
                  )}
                </section>

                {/* middle: chart + telemetry, with the Buy/Sell swap BELOW it */}
                <div className="tc-chart-col">
                  <section className="tc-card tc-chart-card">
                    <div className="tc-chart-head">
                      <div>
                        <div className="tc-card__eyebrow" style={{ color: col }}>${m.ticker} / {liveQuote.symbol} · V4 pool</div>
                        {/* Shown while streaming AND once finished. Hiding it on
                            completion meant a fast launch — two swaps was enough
                            here — displayed nothing at all, so there was no way
                            to tell "not started" from "already fully deployed". */}
                        {(seed.active || seed.complete) && (
                          <div className="tc-seed" title="Liquidity is streamed in as swaps poke the seeder">
                            <div className="tc-seed__row">
                              <span className="tc-mono tc-dim">
                                {seed.complete
                                  ? `Liquidity fully deployed · 100%`
                                  : `Liquidity deploying · ${(seed.placed * 100).toFixed(0)}%`}
                              </span>
                              <span className="tc-mono tc-dim">
                                {seed.ranges} band{seed.ranges === 1 ? "" : "s"}
                                {seed.remaining > 0 && ` · ${Math.ceil(seed.remaining / 60)}m left`}
                              </span>
                            </div>
                            <div className="tc-seed__track">
                              {/* Two bars: what the SCHEDULE expects (ghost) and what is
                                  actually placed (solid). They diverge on a quiet pool,
                                  because slivers only land when a swap pokes the seeder —
                                  which is the most useful thing to see on a new launch. */}
                              <div className="tc-seed__target" style={{ width: `${seed.target * 100}%` }} />
                              <div className="tc-seed__fill" style={{ width: `${seed.placed * 100}%`, background: col }} />
                            </div>
                            {!seed.complete && seed.target - seed.placed > 0.05 && (
                              <div className="tc-mono tc-seed__hint">
                                waiting on a swap to place the next sliver
                              </div>
                            )}
                          </div>
                        )}
                        <div className="tc-spot">{usdPrice(m.priceUsd, m.spotPrice)} <span className="tc-dim tc-mono">/ token</span></div>
                      </div>
                      <div className="tc-chart-mcap">
                        <span className="tc-mono tc-dim">MARKET CAP</span>
                        <span className="tc-chart-mcap__v">{m.mcapUsd > 0 ? usdCompact(m.mcapUsd) : (m.mcap > 0 ? `${fmt(m.mcap, 2)} Ξ` : "—")}</span>
                        <span className="tc-mono tc-dim" style={{ fontSize: 10 }}>{m.fdv > 0 ? `${fmt(m.fdv, 2)} Ξ FDV` : ""}</span>
                      </div>
                    </div>
                    {/* The Brew keeps a clean, simple price line — OI + the
                        liquidation heatmap live on the Leverage tab's chart. */}
                    {/* ONE price source for the whole page. The brew line and the
                        trading chart both read the indexer's per-trade tape, so
                        they can never disagree about what the price did — which
                        they previously could, because this line had its own
                        fetch-and-fallback path that updated on a slower cycle.
                        Falls back to the machine's series only when the tape has
                        not loaded yet. */}
                    <EKG series={ekgSeries} color={col} dead={m.phase === "dead"} />
                    <div className="tc-tele">
                      <Tele label="NFTs forged" value={`${m.nftMinted}${m.nftMax ? ` / ${m.nftMax}` : ""}`} />
                      <Tele label="24h Volume" value={`${fmt(m.vol24hEth, 3)} Ξ`} />
                      <Tele label="Floor / vault" value={`${fmt(m.vaultEth, 3)} Ξ`} accent />
                      <Tele label="Death floor" value={`${fmt(m.deathThresholdEth, 0)} Ξ`} />
                    </div>
                  </section>
                  {/* Buy/Sell swap — directly below the chart. Shown even when
                      "dead": a young pool reads dead at 0 volume, and a buy revives it. */}
                  {m.token && (
                    <SwapWidget
                      ticker={m.ticker}
                      token={m.token}
                      spotPrice={m.spotPrice}
                      priceUsd={m.priceUsd}
                      ethUsd={m.ethUsd}
                      col={col}
                      onBought={m.refresh}
                    />
                  )}
                </div>

                {/* right rail: the crystal gacha game */}
                {m.token && (
                  <div className="tc-rail">
                    <CrystalCauldronGame
                      ticker={m.ticker}
                      token={m.token}
                      collection={m.collection}
                      spotPrice={m.spotPrice}
                      ethUsd={m.ethUsd}
                      col={col}
                      nftMinted={m.nftMinted}
                      nftMax={m.nftMax}
                      onBought={m.refresh}
                    />
                  </div>
                )}
              </div>
            )}
          </>
        )}

        {/* ══ LEVERAGE (perps) ══ */}
        {tab === "leverage" && m.summoned && (
          <section className="tc-card" style={{ padding: 18 }}>
            <div className="tc-card__eyebrow" style={{ color: col, marginBottom: 4 }}>
              Leverage · hook-native perps on ${m.ticker}
            </div>
            <p style={{ fontFamily: '"DM Sans", sans-serif', fontSize: 12, color: C.mute, margin: "0 0 16px", maxWidth: 620, lineHeight: 1.5 }}>
              Long or short the brew with real price impact — every position moves the chart, and the liquidation walls light up the heatmap below. Overcollateralized, TWAP-marked, no external oracle.
            </p>

            {/* The ENGINE refuses a non-ETH generation (PerpEngine.QuoteNotSupported),
                so say why here rather than letting an open fail at signing. Its
                collateral, funding and insurance buffer are still ETH-denominated. */}
            {!perpsAvailable && (
              <div className="tc-perp-gate">
                <div className="tc-mono" style={{ color: "#f6c86a", marginBottom: 6 }}>
                  ⚠ Leverage is ETH-only for now
                </div>
                <p style={{ margin: 0, fontFamily: '"DM Sans", sans-serif', fontSize: 12, lineHeight: 1.55, color: C.mute }}>
                  This brew is priced in <b>{liveQuote.symbol}</b>. Spot trading, the
                  gacha and the collection floor all work normally — but the perp
                  engine denominates collateral and its insurance buffer in ETH, so
                  it declines this pair rather than mis-pricing your position.
                </p>
              </div>
            )}

            {/* live chart WITH the liquidation heatmap — trade against your walls */}
            <div className="tc-perp-chart">
              <div className="tc-chart-head">
                <div>
                  <div className="tc-card__eyebrow" style={{ color: col }}>${m.ticker} · liquidation heatmap</div>
                  <div className="tc-spot">{usdPrice(m.priceUsd, m.spotPrice)} <span className="tc-dim tc-mono">/ token</span></div>
                </div>
                <div className="tc-chart-mcap">
                  <span className="tc-mono tc-dim">OPEN INTEREST</span>
                  <span className="tc-chart-mcap__v">{heat.openCount || 0} pos</span>
                  <span className="tc-mono tc-dim" style={{ fontSize: 10 }}>
                    {heat.live ? `${fmt(heat.longOiEth, 2)}Ξ L · ${fmt(heat.shortOiEth, 2)}Ξ S` : `offline: ${heat.reason ?? "…"}`}
                  </span>
                </div>
              </div>
              <TradingChart trades={tradeTape} liq={[...heat.positions, ...heat.history]} mark={heat.markPrice} />
              {heat.openCount === 0 && (
                <p className="tc-perp-hint">
                  No liquidation walls yet — open a position and its liquidation price appears here as a
                  <span style={{ color: C.red }}> red (long)</span> or <span style={{ color: col }}>lime (short)</span> band.
                </p>
              )}
            </div>

            <PerpPanel
              ticker={m.ticker}
              spotPrice={livePerpPrice}
              priceUsd={livePerpPrice > 0 ? livePerpPrice * (m.ethUsd ?? 0) : m.priceUsd}
              ethUsd={m.ethUsd ?? 0}
              col={col}
              warm={m.summoned}
              generation={m.gen}
              onTraded={m.refresh}
            />

            <p className="tc-perp-hint" style={{ marginTop: 18 }}>
              The leverage you trade against is funded by the community vault —
              <button className="tc-linkbtn" onClick={() => setTab("stake")}>stake into it</button>
              to earn 30% of every perp fee.
            </p>
          </section>
        )}

        {/* ══ STAKE — the community liquidity vault that funds the perps ══ */}
        {tab === "stake" && m.summoned && (
          <section className="tc-card" style={{ padding: 18 }}>
            <div className="tc-card__eyebrow" style={{ color: col, marginBottom: 4 }}>
              Community vault · fund the leverage, earn the fees
            </div>
            <p style={{ fontFamily: '"DM Sans", sans-serif', fontSize: 12, color: C.mute, margin: "0 0 16px", maxWidth: 620, lineHeight: 1.5 }}>
              Stake ETH or ${m.ticker} into the perp liquidity vault that fronts every trader’s leverage — and earn 30% of all perp fees as your share price grows. This is the community-funded sink that powers the whole engine.
            </p>
            <StakePanel ticker={m.ticker} token={m.token} spotPrice={livePerpPrice} ethUsd={m.ethUsd ?? 0} col={col} />
          </section>
        )}

        {/* ══ GOVERNANCE ══ */}
        {tab === "governance" && (
          <>
          <TreasuryRotation gen={m.gen} col={col} />
          <section className="tc-card tc-gov">
            <div className="tc-gov__head">
              <div>
                <div className="tc-card__eyebrow" style={{ color: C.lime }}>Fren governance · the guild decides the next brew</div>
                <h2 className="tc-gov__title">Proposals</h2>
              </div>
              {m.holdsMiFren ? (
                <button className="tc-btn tc-btn--propose" onClick={() => setShowPropose((v) => !v)}>
                  {showPropose ? "✕ Cancel" : "＋ Propose the next brew"}
                </button>
              ) : (
                <span className="tc-gov__gate tc-mono">Hold a MiFren to propose</span>
              )}
            </div>
            <p className="tc-gov__desc">When the current brew dies, the top proposal is summoned as the next iteration. Every MiFren is one vote — and only MiFren holders can propose.</p>

            {showPropose && m.holdsMiFren && (
              <ProposeForm busy={busyPropose} col={col} onSubmit={onPropose} />
            )}

            {m.proposals.length === 0 ? (
              <div className="tc-empty">No live proposals yet. {m.holdsMiFren ? "Propose the next brew above." : "The frens haven't proposed the next brew yet."}</div>
            ) : (
              <div className="tc-props">
                {m.proposals.map((p, i) => (
                  <ProposalRow key={p.id} p={p} share={(p.votes / totalVotes) * 100} leader={i === 0} busy={busyVote === p.id} onVote={() => onVote(p.id)} onOpen={() => setOpenProposal(p)} />
                ))}
              </div>
            )}
          </section>
          </>
        )}

        {/* ══ LINEAGE ══ */}
        {tab === "lineage" && (
          <section className="tc-card tc-gov">
            <div className="tc-card__eyebrow" style={{ color: C.lime }}>Generation lineage</div>
            <h2 className="tc-gov__title">The eternal chain</h2>
            <p className="tc-gov__desc">Every iteration the machine has ever summoned. It has never halted.</p>
            {!m.summoned ? (
              <div className="tc-empty">No brews yet. Finish the genesis and summon iteration #1.</div>
            ) : (
              <div className="tc-lineage">
                {Array.from({ length: m.gen }).map((_, i) => {
                  const g = m.gen - i;
                  const isCurrent = g === m.gen;
                  return (
                    <div key={g} className={`tc-lin ${isCurrent ? "tc-lin--live" : ""}`}>
                      <div className="tc-lin__gen" style={{ color: isCurrent ? col : C.mute }}>#{String(g).padStart(2, "0")}</div>
                      <div className="tc-lin__body">
                        <div className="tc-lin__name">{isCurrent ? m.name : `Iteration ${g}`}</div>
                        <div className="tc-lin__meta tc-mono tc-dim">{isCurrent ? `$${m.ticker} · ${m.phase}` : "retired → LP burned"}</div>
                      </div>
                      {isCurrent && <span className="tc-lin__dot" style={{ background: col, boxShadow: `0 0 10px ${col}` }} />}
                    </div>
                  );
                })}
              </div>
            )}
          </section>
        )}
      </div>

      <PresaleModal
        isOpen={showPresale}
        onClose={() => { setShowPresale(false); setAutoMint(false); m.refresh(); }}
        autoMint={autoMint}
        initialAmount={mintQty}
        onSummoned={() => { setJustSummoned(true); m.refresh(); }}
      />
      {openProposal && (
        <ProposalModal
          p={openProposal}
          leader={m.proposals[0]?.id === openProposal.id}
          busy={busyVote === openProposal.id}
          onVote={() => onVote(openProposal.id)}
          onClose={() => setOpenProposal(null)}
        />
      )}
      <Styles />
    </div>
  );
}

/* ── sub-components ─────────────────────────────────────────────── */
function Stat({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="tc-stat">
      <span className="tc-stat__l tc-mono">{label}</span>
      <span className="tc-stat__v tc-mono" style={{ color: color ?? C.cream }}>{value}</span>
    </div>
  );
}
function SummoningState({ summoning }: { summoning: boolean }) {
  return (
    <div className="tc-summoning">
      <div className="tc-summoning__portal">
        <span className="tc-summoning__ring" />
        <span className="tc-summoning__ring tc-summoning__ring--2" />
        <span className="tc-summoning__ring tc-summoning__ring--3" />
        <span className="tc-summoning__core">⚗</span>
      </div>
      <h3 className="tc-summoning__t">{summoning ? "Summoning iteration #1" : "Loading the Cauldron"}<span className="tc-summoning__dots"><i>.</i><i>.</i><i>.</i></span></h3>
      <p className="tc-summoning__s">
        {summoning
          ? "Seeding the liquidity pool and inscribing the first brew on-chain — this takes a few seconds."
          : "Reading the live brew from the indexer."}
      </p>
    </div>
  );
}
function Tele({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div className="tc-teleitem">
      <span className="tc-mono tc-dim">{label}</span>
      <span className="tc-teleitem__v" style={{ color: accent ? C.lime : C.cream }}>{value}</span>
    </div>
  );
}
/** Graceful migration prompt: when the connected wallet still holds tokens from
 *  a past (dead) iteration, offer to burn them 1:1 into the live brew. Only the
 *  holder can migrate their own dead tokens — 1 old = 1 new, nothing lost. */
function MigratePanel({ items, currentTicker, busyGen, onClaim }: {
  items: MigratableBalance[];
  currentTicker: string;
  busyGen: number | null;
  onClaim: (gen: number, amount: bigint, symbol: string) => void;
}) {
  const fmtAmt = (b: bigint) => {
    const n = Number(formatEther(b));
    return n >= 1000 ? n.toLocaleString(undefined, { maximumFractionDigits: 0 })
      : n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  };
  return (
    <div className="tc-migrate" role="region" aria-label="Migrate previous iteration tokens">
      <div className="tc-migrate__head">
        <span className="tc-migrate__spark" aria-hidden><I.bolt /></span>
        <div>
          <div className="tc-migrate__title">Carry your balance forward</div>
          <div className="tc-migrate__sub">
            You hold tokens from {items.length === 1 ? "a past brew" : `${items.length} past brews`}.
            Migrate them <b>1:1</b> into the live <span className="tc-mono">${currentTicker}</span> — old tokens are burned, no value lost.
          </div>
        </div>
      </div>
      <div className="tc-migrate__rows">
        {items.map((it) => {
          const busy = busyGen === it.gen;
          return (
            <div key={it.gen} className="tc-migrate__row">
              <div className="tc-migrate__from">
                <span className="tc-migrate__gen tc-mono">#{String(it.gen).padStart(2, "0")}</span>
                <span className="tc-migrate__bal">{fmtAmt(it.balance)}</span>
                <span className="tc-mono tc-migrate__sym">${it.symbol}</span>
              </div>
              <span className="tc-migrate__arrow" aria-hidden>→</span>
              <span className="tc-migrate__to tc-mono">${currentTicker}</span>
              <button
                className="tc-btn tc-btn--migrate"
                onClick={() => onClaim(it.gen, it.balance, it.symbol)}
                disabled={busy}
              >
                {busy ? "Migrating…" : "Migrate"}
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
/** The GENESIS REDEMPTION FLOOR (v2, ratcheting): recycle a genesis MiFren for the
 *  LIVE floor of the current token — the NFT goes to the treasury (not burned) to
 *  be resold at 2× floor, which grows the reserve so the floor only RISES. Ties the
 *  NFT floor to the live marketcap; non-dilutive. Self-hides for non-holders. */
function GenesisBonusPanel({ notify }: { notify: (k: "ok" | "err", m: string) => void }) {
  const gb = useGenesisBonus();
  const [open, setOpen] = useState(false);
  if (gb.unclaimedIds.length === 0) return null;

  const fmtG = (b: bigint) => Number(formatEther(b)).toLocaleString(undefined, { maximumFractionDigits: 0 });
  const remaining = gb.unclaimedIds.length; // every owned genesis fren is recyclable
  const thisBatch = Math.min(remaining, gb.claimBatch);
  const more = remaining > gb.claimBatch;
  const ticker = gb.currentTicker || "the live token";

  const onClaim = async () => {
    const ok = window.confirm(
      `Recycle ${thisBatch} genesis fren${thisBatch > 1 ? "s" : ""} for ${fmtG(gb.sharePerFren * BigInt(thisBatch))} $${gb.currentTicker}?\n\n` +
      `The NFT${thisBatch > 1 ? "s move" : " moves"} to the treasury (NOT burned) to be resold at 2× floor. ` +
      `You get the live token now and give up ${thisBatch > 1 ? "their" : "its"} vote + dividend on exit.`,
    );
    if (!ok) return;
    try {
      await gb.claimAndMigrate(); // recycles via redeemFren (NFT → treasury)
      notify("ok", `Recycled ${thisBatch} fren${thisBatch > 1 ? "s" : ""} → received $${gb.currentTicker} ✓`);
    } catch (e) { notify("err", friendlyErr(e)); }
  };

  // Collapsed by default → a slim notification pill that doesn't eat vertical
  // space (so the gacha + chart + swap fit without scrolling). Click to expand.
  if (!open) {
    return (
      <button className="tc-gpill" onClick={() => setOpen(true)} aria-label="Open genesis redemption floor">
        <span className="tc-gpill__spark" aria-hidden><I.bolt /></span>
        <span className="tc-gpill__txt">
          <b>Genesis Floor</b> · {fmtG(gb.sharePerFren)} ${ticker}/fren ↑
          <span className="tc-gpill__sub"> — {remaining.toLocaleString()} fren{remaining === 1 ? "" : "s"} recyclable</span>
        </span>
        <span className="tc-gpill__chev">›</span>
      </button>
    );
  }

  return (
    <div className="tc-migrate tc-genesis" role="region" aria-label="Genesis redemption floor">
      <button className="tc-gclose" onClick={() => setOpen(false)} aria-label="Minimize">×</button>
      <div className="tc-migrate__head">
        <span className="tc-migrate__spark" aria-hidden><I.bolt /></span>
        <div>
          <div className="tc-migrate__title">Genesis Redemption Floor ↑</div>
          <div className="tc-migrate__sub">
            Recycle a genesis MiFren for <span className="tc-mono">{fmtG(gb.sharePerFren)} ${ticker}</span> from
            the reserve — the NFT goes to the treasury (not burned), resold at 2× floor. The floor
            {" "}<b>RATCHETS UP</b>: buybacks + re-enchant fees grow the reserve, so it only rises and tracks
            {" "}<span className="tc-mono">${ticker}</span>'s marketcap.
          </div>
        </div>
      </div>
      <div className="tc-genesis__stats">
        <div className="tc-genesis__stat"><span className="tc-genesis__k tc-mono">MiFrens held</span><span className="tc-genesis__v">{gb.mifrenCount.toLocaleString()}</span></div>
        <div className="tc-genesis__stat"><span className="tc-genesis__k tc-mono">Floor / fren</span><span className="tc-genesis__v">{fmtG(gb.sharePerFren)} ${ticker}</span></div>
        <div className="tc-genesis__stat"><span className="tc-genesis__k tc-mono">Your total floor</span><span className="tc-genesis__v tc-genesis__v--hl">{fmtG(gb.claimableGnome)} ${ticker}</span></div>
      </div>
      <div className="tc-genesis__foot">
        <button className="tc-btn tc-btn--migrate" onClick={onClaim} disabled={gb.busy}>
          {gb.busy
            ? (gb.progress ? `Recycling ${gb.progress.done + 1}/${gb.progress.total}…` : "Recycling…")
            : `Recycle & Redeem ${more ? `${thisBatch} of ${remaining}` : remaining}`}
        </button>
        {more && <span className="tc-genesis__note tc-mono">recycles {gb.claimBatch} at a time — repeat for the rest</span>}
      </div>
    </div>
  );
}
function RelaunchPanel({ proposals, relaunchAt, busy, col, onRelaunch, onPropose }: {
  proposals: Proposal[]; relaunchAt: number; busy: boolean; col: string; onRelaunch: () => void; onPropose: () => void;
}) {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(id);
  }, []);
  const winner = proposals[0];
  // A proposal is only summonable once it has at least one vote — the governor
  // ignores 0-vote proposals when picking a winner (relaunch would revert).
  const hasProposal = !!winner;
  const hasWinner = !!winner && winner.votes > 0;
  const graceLeft = Math.max(0, relaunchAt - now);
  const tooYoung = graceLeft > 0;
  const canRelaunch = hasWinner && !tooYoung;

  const label = busy ? "Summoning…"
    : !hasProposal ? "Propose the next brew"
    : !hasWinner ? "Vote a proposal to unlock relaunch"
    : tooYoung ? `Relaunch in ${fmtCountdown(graceLeft)}`
    : `Summon $${winner.ticker}`;

  return (
    <div className="tc-relaunch">
      {hasWinner ? (
        <div className="tc-relaunch__next">
          <FrenFace seed={addrSeed(winner.proposer)} size={34} ring={col} />
          <div className="tc-relaunch__meta">
            <span className="tc-mono tc-dim">NEXT BREW · WINNING PROPOSAL</span>
            <span className="tc-relaunch__brew">{winner.name} <em>${winner.ticker}</em></span>
          </div>
          <span className="tc-relaunch__votes tc-mono" style={{ color: col }}>{winner.votes} ▲</span>
        </div>
      ) : hasProposal ? (
        <div className="tc-relaunch__none">
          Proposals are in — but none have votes yet. <b>Cast a vote</b> in the Governance tab to crown a
          winner, then the Cauldron can relaunch.
        </div>
      ) : (
        <div className="tc-relaunch__none">
          No proposal yet — the guild must <b>propose &amp; vote</b> the next brew before the Cauldron can relaunch.
        </div>
      )}

      <button
        className="tc-btn tc-btn--ritual"
        onClick={canRelaunch ? onRelaunch : onPropose}
        disabled={busy || (hasWinner && tooYoung)}
      >
        <I.bolt /> {label}
      </button>

      {tooYoung && hasWinner && (
        <p className="tc-relaunch__hint">
          Fresh brews are protected — a token must survive a grace period so it has a fair chance to
          trade before anyone can relaunch it.
        </p>
      )}
    </div>
  );
}
function ProposeForm({ busy, onSubmit }: {
  busy: boolean; col: string;
  onSubmit: (p: { name: string; symbol: string; nftSupply: number; mintOutEth: number; renderer?: string; baseURI?: string; website?: string; socials?: string; quote?: string }) => void;
}) {
  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [supply, setSupply] = useState("3333");
  const [mintOut, setMintOut] = useState("50");
  const [artMode, setArtMode] = useState<"renderer" | "uri">("uri");
  const [renderer, setRenderer] = useState("");
  const [baseURI, setBaseURI] = useState("");
  const [website, setWebsite] = useState("");
  const [socials, setSocials] = useState("");
  // What the brew is PRICED IN. Native ETH is the default and is always
  // available — the registry allows it at construction and refuses to remove it.
  const [quote, setQuote] = useState<string>(NATIVE_QUOTE);
  const { quotes, loading: quotesLoading } = useAllowedQuotes();
  const quoteInfo = quoteMeta(quote as `0x${string}`);

  const nSupply = Math.max(0, Math.floor(Number(supply) || 0));
  const nMintOut = Math.max(0, Number(mintOut) || 0);
  const perNft = nSupply > 0 ? nMintOut / nSupply : 0;
  const rendererOk = artMode === "uri" || /^0x[0-9a-fA-F]{40}$/.test(renderer.trim());
  const valid = name.trim() && symbol.trim() && nSupply > 0 && nMintOut > 0 && rendererOk;

  return (
    <div className="tc-propose">
      <div className="tc-propose__grid">
        <label className="tc-propose__field">
          <span className="tc-mono tc-dim">Name</span>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Frog Nation" maxLength={32} />
        </label>
        <label className="tc-propose__field">
          <span className="tc-mono tc-dim">Ticker</span>
          <input value={symbol} onChange={(e) => setSymbol(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ""))} placeholder="FROG" maxLength={10} />
        </label>
        <label className="tc-propose__field">
          <span className="tc-mono tc-dim"># NFTs (volume-forged)</span>
          <input value={supply} onChange={(e) => setSupply(e.target.value.replace(/[^0-9]/g, ""))} inputMode="numeric" placeholder="3333" />
        </label>
        <label className="tc-propose__field">
          <span className="tc-mono tc-dim">Volume to mint out ({quoteInfo.glyph || quoteInfo.symbol})</span>
          <input value={mintOut} onChange={(e) => setMintOut(e.target.value.replace(/[^0-9.]/g, ""))} inputMode="decimal" placeholder="50" />
        </label>
      </div>

      {/* PAIR — what the brew is priced in. Only quotes the treasury has
          approved on-chain appear here, so a proposal can never be rejected for
          naming an unvetted pair after the whole form is filled in. */}
      <div className="tc-propose__pair">
        <div className="tc-propose__pair-head">
          <span className="tc-mono tc-dim">Trading pair</span>
          {quotes.length === 1 && !quotesLoading && (
            <span className="tc-mono tc-dim tc-propose__pair-note">only ETH is approved right now</span>
          )}
        </div>
        <div className="tc-propose__seg tc-propose__seg--pair">
          {quotes.map((q) => (
            <button
              key={q.address}
              type="button"
              className={quote.toLowerCase() === q.address.toLowerCase() ? "on" : ""}
              onClick={() => setQuote(q.address)}
              title={q.blurb}
            >
              ${symbol || "TOKEN"} / {q.symbol}
            </button>
          ))}
        </div>
        <p className="tc-propose__pair-blurb">{quoteInfo.blurb}</p>
        {!isNativeQuote(quote as `0x${string}`) && (
          <p className="tc-propose__pair-warn">
            Perps stay ETH-only for now — a {quoteInfo.symbol}-paired brew trades spot
            and forges NFTs, but leverage is disabled until the engine is
            re-denominated.
          </p>
        )}
      </div>

      {/* art source */}
      <div className="tc-propose__art">
        <div className="tc-propose__seg">
          <button className={artMode === "uri" ? "on" : ""} onClick={() => setArtMode("uri")} type="button">Metadata URL</button>
          <button className={artMode === "renderer" ? "on" : ""} onClick={() => setArtMode("renderer")} type="button">On-chain renderer</button>
        </div>
        {artMode === "uri" ? (
          <label className="tc-propose__field">
            <span className="tc-mono tc-dim">Base URI (tokenURI = baseURI + id)</span>
            <input value={baseURI} onChange={(e) => setBaseURI(e.target.value)} placeholder="https://frognation.xyz/api/meta/ (blank = default)" />
          </label>
        ) : (
          <label className="tc-propose__field">
            <span className="tc-mono tc-dim">Renderer contract address</span>
            <input value={renderer} onChange={(e) => setRenderer(e.target.value)} placeholder="0x… (on-chain tokenURI)" />
            {!rendererOk && renderer.length > 0 && <span className="tc-propose__err">Enter a valid 0x address</span>}
          </label>
        )}
      </div>

      <div className="tc-propose__grid">
        <label className="tc-propose__field">
          <span className="tc-mono tc-dim">Website (optional)</span>
          <input value={website} onChange={(e) => setWebsite(e.target.value)} placeholder="frognation.xyz" />
        </label>
        <label className="tc-propose__field">
          <span className="tc-mono tc-dim">X / socials (optional)</span>
          <input value={socials} onChange={(e) => setSocials(e.target.value)} placeholder="@frognation" />
        </label>
      </div>

      <div className="tc-propose__summary tc-mono">
        {nSupply > 0 && nMintOut > 0
          ? `≈ ${perNft.toFixed(perNft < 0.01 ? 5 : 3)} Ξ of volume forges each NFT · ${nSupply.toLocaleString()} total`
          : "set collection size + mint-out volume"}
      </div>

      <button
        className="tc-btn tc-btn--ritual"
        disabled={!valid || busy}
        onClick={() => onSubmit({
          name: name.trim(), symbol: symbol.trim(), nftSupply: nSupply, mintOutEth: nMintOut,
          renderer: artMode === "renderer" ? renderer.trim() : undefined,
          baseURI: artMode === "uri" ? baseURI.trim() : undefined,
          website: website.trim(), socials: socials.trim(),
          quote,
        })}
      >
        <I.bolt /> {busy ? "Proposing…" : `Propose $${symbol || "TICKER"}`}
      </button>
      <p className="tc-propose__note">The top-voted proposal is summoned as the next iteration when the current brew dies. Its NFTs are forged from trading volume via the crystal gacha.</p>
    </div>
  );
}
function ProposalRow({ p, share, leader, busy, onVote, onOpen }: { p: Proposal; share: number; leader: boolean; busy: boolean; onVote: () => void; onOpen: () => void }) {
  const brand = PROPOSAL_BRAND[p.ticker?.toUpperCase?.() ?? ""];
  return (
    <div className={`tc-prop ${leader ? "tc-prop--lead" : ""} ${brand ? "tc-prop--branded" : ""} tc-prop--click`} onClick={onOpen} role="button" tabIndex={0}>
      {brand
        ? <img className="tc-prop__logo" src={brand.logo} alt={p.name} style={{ borderColor: leader ? C.lime : `${brand.accent}66`, background: brand.logoBg }} />
        : <FrenFace seed={addrSeed(p.proposer)} size={46} ring={leader ? C.lime : "rgba(255,255,255,0.12)"} />}
      <div className="tc-prop__body">
        <div className="tc-prop__head">
          <span className="tc-prop__name">{p.name}</span>
          <span className="tc-prop__tick tc-mono">${p.ticker}</span>
          {leader && <span className="tc-prop__lead-badge">LEADING</span>}
        </div>
        <div className="tc-prop__theme">{p.theme}</div>
        <div className="tc-prop__spec tc-mono">
          <span>◆ {p.nftSupply.toLocaleString()} NFTs</span>
          <span>⚗ {fmt(p.mintOutEth, 1)} Ξ to mint out</span>
          <span>{p.metaMode === "renderer" ? "on-chain art" : "URI art"}</span>
        </div>
        <div className="tc-prop__foot">
          <span className="tc-mono tc-dim">by {short(p.proposer)}</span>
          {p.website && <a className="tc-prop__link" href={`https://${p.website.replace(/^https?:\/\//, "")}`} target="_blank" rel="noopener" onClick={(e) => e.stopPropagation()}><I.globe /> {p.website}</a>}
          {p.socials && <a className="tc-prop__link" href={`https://x.com/${p.socials.replace(/^@|https?:\/\/x\.com\//, "")}`} target="_blank" rel="noopener" onClick={(e) => e.stopPropagation()}><I.x /></a>}
          <span className="tc-prop__more">view details →</span>
        </div>
        <div className="tc-prop__votetrack"><div className="tc-prop__votefill" style={{ width: `${Math.max(share, 3)}%` }} /></div>
      </div>
      <div className="tc-prop__vote" onClick={(e) => e.stopPropagation()}>
        <span className="tc-prop__votes tc-mono">{p.votes.toLocaleString()}</span>
        <span className="tc-mono tc-dim">votes</span>
        <button className="tc-btn tc-btn--vote" onClick={onVote} disabled={busy}><I.vote size={13} /> {busy ? "…" : "Vote"}</button>
      </div>
    </div>
  );
}

/* ── Proposal detail modal — a brew-twitter-style card (banner + logo + $ticker
   + all the launch details) so a proposal reads like the live brew profile. ── */
function ProposalModal({ p, leader, busy, onVote, onClose }: { p: Proposal; leader: boolean; busy: boolean; onVote: () => void; onClose: () => void }) {
  const brand = PROPOSAL_BRAND[p.ticker?.toUpperCase?.() ?? ""];
  const accent = brand?.accent ?? C.lime;
  const site = p.website?.replace(/^https?:\/\//, "");
  const x = p.socials?.replace(/^@|https?:\/\/x\.com\//, "");
  return createPortal(
    <div className="tc-pm__scrim" onClick={onClose}>
      <div className="tc-pm" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <button className="tc-pm__x" onClick={onClose} aria-label="Close">✕</button>
        {/* banner */}
        <div className="tc-pm__banner" style={brand ? { backgroundImage: `url(${brand.banner})` } : { background: `linear-gradient(120deg, ${accent}22, #1b1436)` }}>
          <span className="tc-pm__gen" style={{ color: accent, borderColor: `${accent}55` }}>
            <span className="tc-pm__dot" style={{ background: accent, boxShadow: `0 0 8px ${accent}` }} /> PROPOSAL · {leader ? "LEADING" : "PENDING"}
          </span>
        </div>
        {/* logo */}
        <div className="tc-pm__logo" style={{ background: brand?.logoBg ?? "#171226", boxShadow: `0 0 0 3px #171226, 0 0 22px ${accent}55` }}>
          {brand ? <img src={brand.logo} alt={p.name} /> : <FrenFace seed={addrSeed(p.proposer)} size={80} ring="transparent" />}
        </div>
        <div className="tc-pm__body">
          <h2 className="tc-pm__name">{p.name}</h2>
          <div className="tc-pm__handle">
            <span className="tc-pm__tick tc-mono" style={{ color: accent }}>${p.ticker}</span>
            <span className="tc-pm__by">· by Magic Internet Frens</span>
          </div>
          <p className="tc-pm__theme">The next eternal token proposed by the guild — a fully on-chain ${p.ticker} launch with a {p.nftSupply.toLocaleString()}-fren collection, forged live from trading volume.</p>
          <div className="tc-pm__links">
            {site && <a className="tc-pm__link" href={`https://${site}`} target="_blank" rel="noopener"><I.globe size={13} /> {site}</a>}
            {x && <a className="tc-pm__link" href={`https://x.com/${x}`} target="_blank" rel="noopener"><I.x size={12} /> @{x}</a>}
          </div>

          {/* launch spec grid */}
          <div className="tc-pm__grid">
            <div className="tc-pm__stat"><div className="k">NFT collection</div><div className="v">{p.nftSupply > 0 ? p.nftSupply.toLocaleString() : "—"} <span>frens</span></div></div>
            <div className="tc-pm__stat"><div className="k">Volume to mint out</div><div className="v">{p.mintOutEth > 0 ? fmt(p.mintOutEth, 1) : "—"} <span>Ξ</span></div></div>
            <div className="tc-pm__stat"><div className="k">Art source</div><div className="v" style={{ fontSize: 15 }}>{p.metaMode === "renderer" ? "On-chain renderer" : "Hosted URI"}</div></div>
            <div className="tc-pm__stat">
              <div className="k">Proposed by</div>
              <div className="v tc-pm__proposer">
                <FrenFace seed={addrSeed(p.proposer)} size={26} ring={`${accent}66`} />
                <span style={{ fontSize: 15 }}>{short(p.proposer)}</span>
              </div>
            </div>
          </div>

          <div className="tc-pm__votes">
            <span className="tc-mono tc-dim">{p.votes.toLocaleString()} votes</span>
            <button className="tc-btn tc-btn--ritual" style={{ borderColor: accent, color: accent, background: `${accent}18` }} onClick={onVote} disabled={busy}>
              <I.vote size={14} /> {busy ? "Voting…" : `Vote for $${p.ticker}`}
            </button>
          </div>
          <p className="tc-pm__note">Winning proposals summon as the next iteration when the current brew dies. Genesis MiFrens vote (1 fren = 1 vote).</p>
        </div>
      </div>
    </div>,
    document.body,
  );
}
const RARE_CLASSES: FrenClass[] = ["Knight", "Gnome", "Wizard", "Elf", "King"];
function comboFor(cls: FrenClass) {
  const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
  return {
    face: faces[Math.floor(Math.random() * faces.length)],
    body: BODIES[cls][Math.floor(Math.random() * BODIES[cls].length)],
    item: ITEMS[cls][Math.floor(Math.random() * ITEMS[cls].length)],
  };
}

function PresalePanel({
  minted, goal, onOpen, onMintNow, soldOut, presale,
}: {
  minted: number; goal: number; onOpen: () => void; onMintNow: (qty: number) => void; soldOut: boolean;
  presale: ReturnType<typeof useMiFrensPresale>;
}) {
  const pct = Math.min(100, (minted / goal) * 100);
  const [amount, setAmount] = useState(1);
  const [agreed, setAgreed] = useState(false);

  // Cycling 3-fren cluster (Gnome · Wizard · Elf) — same feel as the modal.
  const [cluster, setCluster] = useState(() => RARE_CLASSES.map(comboFor));
  useEffect(() => {
    const id = setInterval(() => setCluster(RARE_CLASSES.map(comboFor)), 220);
    return () => clearInterval(id);
  }, []);

  // Full moving frens background marquee.
  const marquee = useMemo(() => {
    const primes = [7, 11, 13, 17, 19]; const offs = [0, 5, 3, 9, 6];
    const rows: { body: TraitLayer; face: TraitLayer; item: TraitLayer }[][] = [];
    for (let r = 0; r < 5; r++) {
      const row: { body: TraitLayer; face: TraitLayer; item: TraitLayer }[] = [];
      for (let i = 0; i < 14; i++) {
        const seed = r * 14 + i;
        const cls = CLASS_ORDER[(seed * primes[r % 5]) % CLASS_ORDER.length];
        const bodies = BODIES[cls]; const items = ITEMS[cls];
        const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
        row.push({
          body: bodies[(seed * primes[(r + 1) % 5] + offs[r]) % bodies.length],
          face: faces[(seed * primes[(r + 2) % 5] + offs[(r + 1) % 5]) % faces.length],
          item: items[(seed * primes[(r + 3) % 5] + offs[(r + 2) % 5]) % items.length],
        });
      }
      rows.push(row);
    }
    return rows;
  }, []);

  const priceEth = (amount * PRESALE.priceEth).toFixed(4);
  const minting = presale.isPending || presale.confirming;
  // REAL genesis airdrop: per-fren token gift + the iteration-#1 ticker (from
  // Ponder). Falls back to a sensible default if the read hasn't landed yet.
  const airTicker = presale.airdropTicker || "GNOME";
  const airPerFren = presale.airdropPerFren || 0;
  const airStr = airPerFren > 0 ? fmt(airPerFren, 0) : "—";

  // Route through the modal so the full crystal-orb → reveal animation plays.
  const doMint = () => {
    if (!agreed) return;
    onMintNow(amount);
  };

  return (
    <section className="tc-card tc-presale">
      {/* moving frens background */}
      <div className="tc-ps-bg" aria-hidden>
        {marquee.map((row, ri) => (
          <div key={ri} className="tc-ps-row">
            {[...row, ...row].map((f, fi) => (
              <div key={fi} className="tc-ps-fren">
                <img src={`${FRENS_PATH}${f.face.file}`} alt="" />
                <img src={`${FRENS_PATH}${f.body.file}`} alt="" />
                <img src={`${FRENS_PATH}${f.item.file}`} alt="" />
              </div>
            ))}
          </div>
        ))}
      </div>

      <div className="tc-ps-inner">
        <div className="tc-card__eyebrow" style={{ color: C.lime }}>Step 1 · genesis {soldOut ? "· sold out" : "· open"}</div>
        <h2 className="tc-brewname">Mint the founding guild</h2>
        <p className="tc-ps-sub">A rare-class MiFren + {airStr} ${airTicker}. Every MiFren is one vote and earns a slice of every brew's fees — forever.</p>

        <div className="tc-ps-grid">
          {/* LEFT — visual */}
          <div className="tc-ps-visual">
            <div className="tc-ps-cluster">
              {cluster.map((f, i) => (
                <div key={i} className={`tc-ps-hero tc-ps-hero--${["xl", "l", "c", "r", "xr"][i]}`}>
                  <img src={`${FRENS_PATH}${f.face.file}`} alt="" />
                  <img src={`${FRENS_PATH}${f.body.file}`} alt="" />
                  <img src={`${FRENS_PATH}${f.item.file}`} alt="" />
                </div>
              ))}
            </div>
            <div className="tc-ps-benefits">
              <span className="tc-ps-benefit"><I.bolt size={11} /> Rare Only</span>
              <span className="tc-ps-benefit">ERC-721</span>
              <span className="tc-ps-benefit">{airStr} ${airTicker}</span>
            </div>
            <div className="tc-ps-art">
              <span className="tc-ps-art__tag">YOU'RE BUYING ART</span>
              <p className="tc-ps-art__text">
                Your MiFren is a fully on-chain pixel-art NFT. The {airStr} ${airTicker} airdrop is a <strong>gift, not a promise</strong> — at launch it's worth <strong>~75% less than you paid</strong> (most of the raise seeds a deep pool, not the airdrop). You're here for the <strong>art</strong> (and the guild).
              </p>
            </div>
          </div>

          {/* RIGHT — mint action (always in view, no scroll) */}
          <div className="tc-ps-action">
            <div className="tc-ps-prog">
              <div className="tc-ps-progrow"><span className="tc-mono tc-dim">MINTED</span><span className="tc-mono">{minted} / {goal} · {Math.round(pct)}%</span></div>
              <div className="tc-presale__track"><div className="tc-presale__fill" style={{ width: `${Math.max(pct, 2)}%` }} /></div>
            </div>

            <div className="tc-ps-qtyrow">
              <div className="tc-ps-stepper">
                <button onClick={() => setAmount((a) => Math.max(1, a - 1))}>−</button>
                <span>{amount}</span>
                <button onClick={() => setAmount((a) => Math.min(50, a + 1))}>+</button>
              </div>
              <div className="tc-ps-price">
                <span className="tc-ps-price__eth">{priceEth} <em>ETH</em></span>
                <span className="tc-mono tc-dim">{airPerFren > 0 ? fmt(amount * airPerFren, 0) : "—"} ${airTicker} airdrop</span>
              </div>
            </div>

            <label className="tc-ps-terms">
              <input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} />
              <span>I'm buying art. The token is a bonus with no promised value. Experimental DeFi. Not a US person.</span>
            </label>

            {soldOut ? (
              <button className="tc-btn tc-btn--ritual" onClick={onOpen}><I.bolt /> Summon iteration #1 · Gnomeland</button>
            ) : (
              <button className="tc-btn tc-btn--ritual" onClick={doMint} disabled={!agreed}>
                <I.bolt /> Mint {amount} {amount === 1 ? "Fren" : "Frens"} · {priceEth} ETH
              </button>
            )}
            <button className="tc-ps-adv" onClick={onOpen}>full genesis mint flow →</button>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ── styles ─────────────────────────────────────────────────────── */
function Styles() {
  return (
    <style>{`
    /* The shell owns the horizontal gutter now (it has to clear the rail), so
       the page only sets its own vertical rhythm and atmosphere. */
    .tc { position: relative; min-height: 100vh; padding: 0 0 100px; overflow: visible;
      background:
        radial-gradient(1100px 620px at 50% -8%, rgba(213,253,81,0.06), transparent 60%),
        radial-gradient(900px 700px at 80% 20%, rgba(124,92,252,0.10), transparent 55%),
        ${C.void};
      color: ${C.cream}; font-family: "DM Sans", sans-serif; }
    .tc-mono { font-family: "DM Mono", ui-monospace, monospace; }
    .tc-dim { color: ${C.mute}; }
    .tc * { box-sizing: border-box; }

    /* Atmosphere. The film grain now lives on the shell (.shell__grain) so it
       spans the rail too; only the embers are page-local. */
    .tc-embers { position: fixed; inset: 0; pointer-events: none; z-index: 1; overflow: hidden; }
    .tc-ember { position: absolute; bottom: -10px; width: 3px; height: 3px; border-radius: var(--r-full);
      background: ${C.lime}; opacity: 0; filter: blur(0.5px);
      animation-name: tc-rise; animation-iteration-count: infinite; animation-timing-function: ease-out; }
    @keyframes tc-rise { 0% { transform: translateY(0) scale(1); opacity: 0; } 12% { opacity: 0.7; } 100% { transform: translateY(-70vh) scale(0.3); opacity: 0; } }

    .tc > *:not(.tc-embers) { position: relative; z-index: 2; max-width: 1240px; margin-left: auto; margin-right: auto; }

    /* action toast (vote / relaunch / propose feedback) */
    .tc-toast { position: fixed; left: 50%; bottom: 28px; transform: translateX(-50%);
      z-index: 50; display: flex; align-items: center; gap: 10px;
      padding: 12px 18px; border-radius: var(--r-sm); border: 1px solid;
      background: rgba(14, 10, 26, 0.92); backdrop-filter: blur(10px);
      font: 500 13.5px/1.35 'DM Sans', sans-serif; letter-spacing: 0.01em;
      box-shadow: 0 12px 40px rgba(0,0,0,0.5); max-width: min(92vw, 460px);
      animation: tc-toast-in 0.28s cubic-bezier(0.2,0.9,0.3,1); }
    .tc-toast__dot { width: 8px; height: 8px; border-radius: 50%; flex: 0 0 auto;
      box-shadow: 0 0 10px currentColor; }
    @keyframes tc-toast-in { from { opacity: 0; transform: translate(-50%, 12px); } to { opacity: 1; transform: translate(-50%, 0); } }

    /* migrate previous-iteration balances forward */
    /* collapsed genesis-airdrop pill — slim, unobtrusive */
    .tc-gpill { display: flex; align-items: center; gap: 10px; width: 100%; margin: 0 0 14px; padding: 9px 14px; border-radius: var(--r-sm); cursor: pointer; text-align: left;
      border: 1px solid ${C.lime}44; background: linear-gradient(100deg, rgba(213,253,81,0.10), rgba(213,253,81,0.02)); transition: all .15s ease; }
    .tc-gpill:hover { border-color: ${C.lime}88; background: linear-gradient(100deg, rgba(213,253,81,0.16), rgba(213,253,81,0.04)); }
    .tc-gpill__spark { display: grid; place-items: center; width: 24px; height: 24px; border-radius: var(--r-sm); background: ${C.lime}1e; color: ${C.lime}; flex-shrink: 0; }
    .tc-gpill__txt { font-family: "DM Sans", sans-serif; font-size: 12.5px; color: ${C.cream}; flex: 1; min-width: 0; }
    .tc-gpill__txt b { color: ${C.lime}; font-weight: 700; }
    .tc-gpill__sub { color: ${C.mute}; }
    .tc-gpill__chev { color: ${C.lime}; font-size: 18px; font-weight: 700; opacity: 0.7; }
    .tc-gclose { position: absolute; top: 10px; right: 12px; background: none; border: none; color: ${C.mute}; font-size: 18px; cursor: pointer; line-height: 1; opacity: 0.7; }
    .tc-gclose:hover { opacity: 1; color: ${C.cream}; }
    .tc-migrate { position: relative; margin: 0 0 22px; padding: 16px 18px; border-radius: var(--r-md);
      border: 1px solid ${C.edge};
      background:
        radial-gradient(120% 140% at 0% 0%, rgba(213,253,81,0.10), transparent 55%),
        ${C.panel};
      backdrop-filter: blur(8px);
      animation: tc-toast-in 0.4s cubic-bezier(0.2,0.9,0.3,1); }
    .tc-migrate__head { display: flex; gap: 12px; align-items: flex-start; margin-bottom: 12px; }
    .tc-migrate__spark { flex: 0 0 auto; width: 34px; height: 34px; border-radius: var(--r-sm);
      display: grid; place-items: center; color: ${C.void};
      background: ${C.lime}; box-shadow: 0 0 18px rgba(213,253,81,0.4); }
    .tc-migrate__spark svg { width: 18px; height: 18px; }
    .tc-migrate__title { font: 700 15px/1.2 'Cinzel Decorative', serif; color: ${C.cream}; letter-spacing: 0.01em; }
    .tc-migrate__sub { margin-top: 3px; font: 400 12.5px/1.45 'DM Sans', sans-serif; color: ${C.dim}; max-width: 62ch; }
    .tc-migrate__sub b { color: ${C.lime}; font-weight: 700; }
    .tc-migrate__sub .tc-mono { color: ${C.cream}; }
    .tc-migrate__rows { display: flex; flex-direction: column; gap: 8px; }
    .tc-migrate__row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
      padding: 10px 12px; border-radius: var(--r-sm);
      background: rgba(14,10,26,0.5); border: 1px solid rgba(255,255,255,0.05); }
    .tc-migrate__from { display: flex; align-items: baseline; gap: 8px; min-width: 0; }
    .tc-migrate__gen { font-size: 11px; color: ${C.mute}; padding: 2px 6px; border-radius: var(--r-chip);
      background: rgba(124,92,252,0.14); border: 1px solid rgba(124,92,252,0.25); }
    .tc-migrate__bal { font: 700 16px/1 'DM Sans', sans-serif; color: ${C.cream}; }
    .tc-migrate__sym { font-size: 12px; color: ${C.dim}; }
    .tc-migrate__arrow { color: ${C.lime}; font-size: 16px; opacity: 0.8; }
    .tc-migrate__to { font-size: 13px; color: ${C.lime}; font-weight: 700; }
    .tc-btn--migrate { margin-left: auto; padding: 8px 18px; border-radius: var(--r-sm);
      background: ${C.lime}; color: ${C.void}; border: none; font: 700 12.5px/1 'DM Sans', sans-serif;
      cursor: pointer; transition: filter 0.18s, transform 0.18s; }
    .tc-btn--migrate:hover:not(:disabled) { filter: brightness(1.08); }
    .tc-btn--migrate:disabled { opacity: 0.55; cursor: default; }
    @media (max-width: 560px) { .tc-migrate__row { gap: 8px; } .tc-btn--migrate { margin-left: 0; width: 100%; } }

    /* genesis airdrop panel */
    .tc-genesis__stats { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 12px; }
    .tc-genesis__stat { flex: 1 1 120px; padding: 10px 12px; border-radius: var(--r-sm);
      background: rgba(14,10,26,0.5); border: 1px solid rgba(255,255,255,0.05);
      display: flex; flex-direction: column; gap: 3px; }
    .tc-genesis__k { font-size: 10.5px; letter-spacing: 0.06em; text-transform: uppercase; color: ${C.mute}; }
    .tc-genesis__v { font: 700 17px/1 'DM Sans', sans-serif; color: ${C.cream}; }
    .tc-genesis__v--hl { color: ${C.lime}; }
    .tc-genesis__foot { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
    .tc-genesis__foot .tc-btn--migrate { margin-left: 0; }
    .tc-genesis__note { font-size: 11px; color: ${C.mute}; }
    .tc-genesis__stranded { padding: 11px 13px; border-radius: var(--r-sm); font: 400 12.5px/1.5 'DM Sans', sans-serif;
      color: ${C.dim}; background: rgba(245,197,66,0.08); border: 1px solid rgba(245,197,66,0.28); }
    .tc-genesis__stranded b { color: ${C.amber}; }
    .tc-genesis__stranded .tc-mono { color: ${C.cream}; }

    /* Masthead — a page title now, not a second nav. The rail carries identity,
       so the wordmark shrinks and the stats collapse to one aligned strip. */
    .tc-top { display: flex; justify-content: space-between; align-items: center; gap: 20px 32px; flex-wrap: wrap;
      padding: 22px 0 16px; margin-bottom: 18px; border-bottom: 1px solid rgba(255,255,255,0.06); }
    .tc-wordmark { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 28px; line-height: 1.05; margin: 0; letter-spacing: 0.01em;
      background: linear-gradient(180deg, ${C.cream}, #b9aee0); -webkit-background-clip: text; background-clip: text; -webkit-text-fill-color: transparent; }
    .tc-sub { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.22em; text-transform: uppercase; color: ${C.mute}; margin: 6px 0 0; }
    .tc-stats { display: flex; align-items: center; gap: 22px; flex-wrap: wrap; }
    .tc-stat { display: flex; flex-direction: column; gap: 3px; }
    .tc-stat__l { font-size: 9px; letter-spacing: 0.18em; text-transform: uppercase; color: ${C.mute}; }
    .tc-stat__v { font-size: 14px; font-weight: 500; text-transform: capitalize; }

    /* cards */
    .tc-card { background: ${C.panel}; border: 1px solid rgba(255,255,255,0.07); border-radius: var(--r-md); padding: 26px; backdrop-filter: blur(14px);
      box-shadow: 0 24px 60px rgba(8,6,15,0.5); }
    .tc-card__eyebrow { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.18em; text-transform: uppercase; margin-bottom: 16px; }

    .tc-reactor { display: grid; grid-template-columns: 0.8fr 1.2fr 300px; gap: 18px; align-items: start; }
    .tc-rail { display: flex; flex-direction: column; gap: 14px; }
    .tc-chart-col { display: flex; flex-direction: column; gap: 14px; min-width: 0; }
    @media (max-width: 1180px) { .tc-reactor { grid-template-columns: 1fr 1fr; } }
    @media (max-width: 760px) { .tc-reactor { grid-template-columns: 1fr; } .tc-top { align-items: flex-start; } }

    /* core */
    .tc-core-card { display: flex; flex-direction: column; }

    /* brew profile — Twitter-style banner + avatar */
    .tc-profile { margin: -26px -26px 6px; }
    .tc-profile__banner {
      position: relative; height: 128px; border-radius: var(--r-md) var(--r-md) 0 0;
      background-size: cover; background-position: center;
    }
    .tc-profile__banner::after { content: ""; position: absolute; inset: 0; border-radius: var(--r-md) var(--r-md) 0 0; background: linear-gradient(180deg, rgba(8,6,15,0) 40%, rgba(23,18,38,0.9) 100%); }
    .tc-profile__gen {
      position: absolute; top: 12px; right: 12px; z-index: 2;
      display: inline-flex; align-items: center; gap: 6px;
      font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.1em;
      padding: 5px 10px; border-radius: var(--r-md); border: 1px solid;
      background: rgba(8,6,15,0.6); backdrop-filter: blur(6px);
    }
    .tc-profile__dot { width: 7px; height: 7px; border-radius: 50%; }
    .tc-profile__edit { position: absolute; top: 12px; left: 12px; z-index: 3; width: 28px; height: 28px; border-radius: 50%; border: 1px solid rgba(255,255,255,0.2); background: rgba(8,6,15,0.6); backdrop-filter: blur(6px); color: ${C.cream}; cursor: pointer; font-size: 13px; opacity: 0; transition: opacity .2s; }
    .tc-profile:hover .tc-profile__edit { opacity: 1; }
    .tc-profile__editbar { display: flex; gap: 8px; padding: 10px 22px 0; flex-wrap: wrap; }
    .tc-profile__editbar button { font-family: "DM Mono", monospace; font-size: 11px; padding: 7px 12px; border-radius: var(--r-sm); border: 1px solid rgba(213,253,81,0.25); background: rgba(213,253,81,0.06); color: ${C.lime}; cursor: pointer; }
    .tc-profile__editbar .tc-profile__save { background: ${C.lime}; color: #0c0918; border: none; font-weight: 700; }
    .tc-profile__logo {
      position: relative; z-index: 3; width: 84px; height: 84px; margin: -42px 0 0 22px;
      border-radius: 50%; overflow: hidden; background: #171226; display: grid; place-items: center;
    }
    .tc-profile__logo img { width: 100%; height: 100%; object-fit: cover; }
    .tc-profile__initial { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 34px; }
    .tc-profile__body { padding: 10px 26px 4px; }
    .tc-profile__name { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 24px; margin: 4px 0 2px; color: ${C.cream}; }
    .tc-profile__handle { display: flex; align-items: baseline; gap: 7px; flex-wrap: wrap; margin-bottom: 10px; }
    .tc-profile__tick { font-size: 13px; font-weight: 600; }
    .tc-profile__by { font-family: "DM Mono", monospace; font-size: 11px; color: ${C.mute}; }
    .tc-profile__links { display: flex; gap: 16px; flex-wrap: wrap; }
    .tc-profile__link { display: inline-flex; align-items: center; gap: 5px; font-family: "DM Mono", monospace; font-size: 12px; color: ${C.mute}; text-decoration: none; transition: color .2s; }
    .tc-profile__link:hover { color: ${C.lime}; }
    .tc-profile__link--os { color: #2081e2; }
    .tc-profile__link--os:hover { color: #4a9ff5; }
    .tc-core { position: relative; width: 220px; height: 220px; margin: 6px 0 10px; display: grid; place-items: center; }
    .tc-core__halo { position: absolute; inset: 0; border-radius: 50%;
      background: radial-gradient(circle, color-mix(in srgb, var(--cc) 60%, transparent) 0%, transparent 62%); opacity: var(--ci); }
    .tc-core__halo--pulse { animation: tc-breathe 3.4s ease-in-out infinite; }
    @keyframes tc-breathe { 0%,100% { transform: scale(1); opacity: calc(var(--ci) * 0.7); } 50% { transform: scale(1.14); opacity: var(--ci); } }
    .tc-core__ring { position: absolute; border-radius: 50%; border: 1px solid color-mix(in srgb, var(--cc) 40%, transparent); }
    .tc-core__ring--a { width: 200px; height: 200px; animation: tc-spin 14s linear infinite; border-style: dashed; opacity: 0.5; }
    .tc-core__ring--b { width: 156px; height: 156px; animation: tc-spin 9s linear infinite reverse; opacity: 0.35; }
    @keyframes tc-spin { to { transform: rotate(360deg); } }
    .tc-core__orb { position: relative; width: 118px; height: 118px; border-radius: 50%; display: grid; place-items: center;
      background: radial-gradient(circle at 38% 32%, color-mix(in srgb, var(--cc) 85%, white 10%), color-mix(in srgb, var(--cc) 40%, #140f26) 70%, #0c0918 100%);
      box-shadow: 0 0 40px color-mix(in srgb, var(--cc) 55%, transparent), inset 0 0 30px rgba(0,0,0,0.5); }
    .tc-core__orb--live { animation: tc-throb 2.6s ease-in-out infinite; }
    @keyframes tc-throb { 0%,100% { transform: scale(1); } 50% { transform: scale(1.05); } }
    .tc-core__orb--cold { filter: grayscale(0.5) brightness(0.7); }
    .tc-core__tick { font-family: "DM Mono", monospace; font-weight: 700; font-size: 15px; color: #0c0918; text-shadow: 0 1px 2px color-mix(in srgb, var(--cc) 40%, transparent); }

    .tc-brewname { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 26px; margin: 4px 0 2px; color: ${C.cream}; }
    .tc-brewby { font-family: "DM Mono", monospace; font-size: 11px; color: ${C.mute}; margin: 0 0 18px; letter-spacing: 0.06em; }

    .tc-vital { width: 100%; margin-bottom: 18px; }
    .tc-vital__row { display: flex; justify-content: space-between; font-size: 11px; letter-spacing: 0.12em; margin-bottom: 7px; }
    .tc-vital__track { height: 9px; border-radius: var(--r-md); background: rgba(255,255,255,0.06); overflow: hidden; }
    .tc-vital__fill { height: 100%; border-radius: var(--r-md); transition: width .6s ease; }
    .tc-vital__fill--beat { animation: tc-beat 1.4s ease-in-out infinite; }
    @keyframes tc-beat { 0%,100% { filter: brightness(1); } 50% { filter: brightness(1.35); } }
    .tc-vital__note { font-size: 12.5px; line-height: 1.5; color: rgba(231,225,245,0.6); margin: 12px 0 0; }

    .tc-reserve { width: 100%; display: flex; flex-direction: column; align-items: center; gap: 3px; padding: 14px; border-radius: var(--r-sm); background: rgba(213,253,81,0.05); border: 1px solid rgba(213,253,81,0.12); }
    .tc-reserve__eth { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 22px; color: ${C.lime}; }
    .tc-reserve__eth em { font-style: normal; font-size: 13px; opacity: 0.7; }

    /* chart */
    .tc-chart-head { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 8px; }
    .tc-spot { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 26px; color: ${C.cream}; }
    .tc-spot .tc-dim { font-size: 12px; font-weight: 400; }
    .tc-chart-mcap { text-align: right; display: flex; flex-direction: column; gap: 3px; }
    .tc-chart-mcap__v { font-family: "DM Mono", monospace; font-size: 15px; color: ${C.cream}; }

    .tc-ekg { position: relative; height: 180px; margin: 4px 0 16px; border-radius: var(--r-sm); overflow: hidden; background: rgba(8,6,15,0.4); border: 1px solid rgba(255,255,255,0.05); }
    .tc-ekg__svg { width: 100%; height: 100%; display: block; }
    .tc-ekg__line { stroke-dasharray: 1400; stroke-dashoffset: 1400; animation: tc-draw 2.2s ease forwards; }
    @keyframes tc-draw { to { stroke-dashoffset: 0; } }
    .tc-ekg__last { position: absolute; top: 10px; right: 12px; font-family: "DM Mono", monospace; font-size: 12px; font-weight: 700; }
    .tc-ekg__empty { position: absolute; inset: 0; display: grid; place-items: center; font-family: "DM Mono", monospace; font-size: 12px; color: ${C.mute}; }
    .tc-ekg__legend { position: absolute; bottom: 8px; left: 12px; display: flex; gap: 12px; font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.04em; color: ${C.mute}; text-transform: uppercase; pointer-events: none; }
    .tc-ekg__legend span { display: inline-flex; align-items: center; gap: 4px; }
    .tc-ekg__legend i { width: 8px; height: 8px; border-radius: 2px; display: inline-block; }

    .tc-oi { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-top: 2px; }
    .tc-oi__pill { font-family: "DM Mono", monospace; font-size: 10px; font-weight: 700; letter-spacing: 0.03em; padding: 3px 8px; border-radius: var(--r-chip); }
    .tc-oi__pill--long { color: #ff5470; background: rgba(255, 84, 112, 0.12); border: 1px solid rgba(255, 84, 112, 0.28); }
    .tc-oi__pill--short { color: ${C.lime}; background: rgba(213, 253, 81, 0.1); border: 1px solid rgba(213, 253, 81, 0.28); }
    .tc-oi__meta { font-size: 10px; }

    .tc-perp-chart { background: rgba(8,6,15,0.35); border: 1px solid rgba(255,255,255,0.06); border-radius: var(--r-sm); padding: 14px; margin-bottom: 16px; }
    .tc-perp-hint { margin: 8px 2px 0; font-family: "DM Sans", sans-serif; font-size: 10.5px; line-height: 1.5; color: ${C.mute}; opacity: 0.85; text-align: center; }
    /* Inline text link that switches view — staking moved to its own tab, so
       Leverage points at it rather than stacking the vault underneath. */
    .tc-linkbtn { margin: 0 3px; padding: 0; background: none; border: none; cursor: pointer;
      font: inherit; color: ${C.lime}; text-decoration: underline; text-underline-offset: 2px; }
    .tc-linkbtn:hover { filter: brightness(1.15); }
    .tc-linkbtn:focus-visible { outline: 2px solid ${C.lime}; outline-offset: 2px; border-radius: var(--r-xs); }

    .tc-tele { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; align-items: stretch; }
    @media (max-width: 560px) { .tc-tele { grid-template-columns: repeat(2, 1fr); } }
    .tc-teleitem { display: flex; flex-direction: column; gap: 4px; padding: 12px; border-radius: var(--r-sm); background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.05); }
    .tc-teleitem .tc-dim { font-size: 9px; letter-spacing: 0.12em; text-transform: uppercase; }
    .tc-teleitem__v { font-family: "DM Mono", monospace; font-size: 15px; font-weight: 500; white-space: nowrap; }

    /* buttons */
    .tc-btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px; font-family: "DM Mono", monospace; font-size: 12px; font-weight: 700; letter-spacing: 0.05em; border-radius: var(--r-sm); padding: 13px 20px; cursor: pointer; border: none; transition: transform .15s, box-shadow .15s, opacity .2s; }
    .tc-btn:disabled { opacity: 0.55; cursor: not-allowed; }
    .tc-btn--ritual { width: 100%; background: linear-gradient(180deg, ${C.lime}, #a9cc2f); color: #0c0918; box-shadow: 0 6px 0 #7f9a22, 0 0 30px rgba(213,253,81,0.25); text-transform: uppercase; }
    .tc-btn--ritual:hover:not(:disabled) { transform: translateY(-1px); box-shadow: 0 7px 0 #7f9a22, 0 0 40px rgba(213,253,81,0.35); }
    .tc-btn--vote { background: rgba(213,253,81,0.12); color: ${C.lime}; padding: 9px 15px; box-shadow: none; }
    .tc-btn--vote:hover:not(:disabled) { background: rgba(213,253,81,0.2); }

    /* relaunch panel */
    .tc-relaunch { display: flex; flex-direction: column; gap: 11px; }
    .tc-relaunch__next { display: flex; align-items: center; gap: 11px; padding: 11px 13px; border-radius: var(--r-sm); background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08); }
    .tc-relaunch__meta { display: flex; flex-direction: column; gap: 3px; min-width: 0; flex: 1; }
    .tc-relaunch__meta .tc-dim { font-size: 8.5px; letter-spacing: 0.14em; }
    .tc-relaunch__brew { font-family: "Cinzel Decorative", "Cinzel", serif; font-size: 15px; font-weight: 700; color: ${C.cream}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .tc-relaunch__brew em { font-family: "DM Mono", monospace; font-style: normal; font-size: 12px; color: ${C.lime}; margin-left: 4px; }
    .tc-relaunch__votes { font-size: 13px; font-weight: 700; white-space: nowrap; }
    .tc-relaunch__none { padding: 12px 14px; border-radius: var(--r-sm); background: rgba(255,84,112,0.06); border: 1px solid rgba(255,84,112,0.18); font-family: "DM Sans", sans-serif; font-size: 12px; line-height: 1.5; color: ${C.mute}; }
    .tc-relaunch__none b { color: ${C.cream}; font-weight: 600; }
    .tc-relaunch__hint { margin: 0; font-family: "DM Sans", sans-serif; font-size: 10.5px; line-height: 1.5; color: ${C.mute}; text-align: center; }

    /* governance */
    .tc-gov__head { display: flex; align-items: flex-start; justify-content: space-between; gap: 14px; flex-wrap: wrap; }
    .tc-gov__title { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 26px; margin: 0 0 6px; }
    .tc-gov__desc { font-size: 13px; color: rgba(231,225,245,0.6); margin: 0 0 20px; max-width: 620px; line-height: 1.55; }
    .tc-gov__gate { font-size: 11px; color: ${C.mute}; padding: 8px 12px; border: 1px dashed rgba(255,255,255,0.14); border-radius: var(--r-sm); white-space: nowrap; }
    .tc-btn--propose { background: rgba(213,253,81,0.12); color: ${C.lime}; padding: 9px 15px; box-shadow: none; white-space: nowrap; }
    .tc-btn--propose:hover:not(:disabled) { background: rgba(213,253,81,0.2); }
    .tc-propose { margin: 0 0 22px; padding: 16px; border-radius: var(--r-md); background: rgba(213,253,81,0.04); border: 1px solid rgba(213,253,81,0.16); }
    .tc-propose__grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 14px; }
    @media (max-width: 620px) { .tc-propose__grid { grid-template-columns: 1fr; } }
    .tc-propose__field { display: flex; flex-direction: column; gap: 5px; }
    .tc-propose__field span { font-size: 8.5px; letter-spacing: 0.14em; text-transform: uppercase; }
    .tc-propose__field input {
      background: rgba(8,6,15,0.5); border: 1px solid rgba(255,255,255,0.1); border-radius: var(--r-sm);
      padding: 9px 11px; color: ${C.cream}; font-family: "DM Sans", sans-serif; font-size: 14px; outline: none;
      transition: border-color 0.15s ease;
    }
    .tc-propose__field input:focus { border-color: ${C.lime}; }
    .tc-propose__field input::placeholder { color: rgba(143,131,184,0.5); }
    .tc-propose__note { margin: 10px 2px 0; font-family: "DM Sans", sans-serif; font-size: 11px; color: ${C.mute}; text-align: center; }
    .tc-propose__art { margin-bottom: 14px; }
    .tc-propose__seg { display: inline-flex; gap: 4px; padding: 3px; border-radius: var(--r-sm); background: rgba(8,6,15,0.4); margin-bottom: 10px; }
    .tc-propose__seg button { font-family: "DM Mono", monospace; font-size: 11px; color: ${C.mute}; background: none; border: none; padding: 6px 12px; border-radius: var(--r-sm); cursor: pointer; transition: all 0.15s ease; }
    .tc-propose__seg button.on { background: rgba(213,253,81,0.16); color: ${C.lime}; }
    /* PAIR selector — set apart from the art toggle because it is the one
       choice on this form that cannot be changed after the brew launches. */
    .tc-propose__pair { margin: 14px 0 4px; padding: 12px 14px; border-radius: var(--r-sm); background: rgba(8,6,15,0.28); border: 1px solid rgba(255,255,255,0.05); }
    .tc-propose__pair-head { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; margin-bottom: 8px; }
    .tc-propose__pair-note { font-size: 10px; opacity: 0.7; }
    .tc-propose__seg--pair { margin-bottom: 8px; flex-wrap: wrap; }
    .tc-propose__seg--pair button { font-size: 12px; letter-spacing: 0.02em; }
    .tc-propose__pair-blurb { margin: 0; font-family: "DM Sans", sans-serif; font-size: 11px; line-height: 1.5; color: ${C.mute}; }
    /* TREASURY ROTATION — set apart from the proposal card because it moves
       real liquidity rather than casting a vote. */
    /* THE SPELLBOOK — every on-chain action, announced from the websocket as it
       lands. Top-right: out of the way of the chart and the stat cards, which is
       where earlier attempts kept landing. */
    .tc-spell { position: fixed; top: 76px; right: 20px; display: flex; flex-direction: column; gap: 7px; z-index: 70; pointer-events: none; width: 232px; }
    .tc-spell__row {
      display: flex; align-items: center; gap: 9px;
      padding: 9px 12px;
      border-radius: 13px;
      background: linear-gradient(135deg, rgba(30,22,58,0.94), rgba(14,11,26,0.94));
      border: 1px solid rgba(168,140,255,0.16);
      box-shadow: 0 8px 26px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.05);
      backdrop-filter: blur(16px) saturate(1.25);
      animation: tcSpellIn 0.5s cubic-bezier(0.16,1,0.3,1);
      transition: opacity 0.55s ease;
      position: relative; overflow: hidden;
    }
    /* A thin rune-light down the left edge, tinted by what happened. */
    .tc-spell__row::before { content: ""; position: absolute; left: 0; top: 0; bottom: 0; width: 2px; }
    .tc-spell__row.is-good::before  { background: linear-gradient(180deg, rgb(70,230,124), rgba(70,230,124,0.25)); box-shadow: 0 0 10px rgba(70,230,124,0.55); }
    .tc-spell__row.is-bad::before   { background: linear-gradient(180deg, rgb(255,86,96), rgba(255,86,96,0.25)); box-shadow: 0 0 10px rgba(255,86,96,0.55); }
    .tc-spell__row.is-magic::before { background: linear-gradient(180deg, rgb(196,142,255), rgba(196,142,255,0.25)); box-shadow: 0 0 10px rgba(196,142,255,0.55); }
    .tc-spell__row.is-neutral::before { background: linear-gradient(180deg, rgba(255,255,255,0.35), rgba(255,255,255,0.08)); }
    .tc-spell__rune { font-size: 16px; line-height: 1; filter: drop-shadow(0 0 6px rgba(196,142,255,0.5)); }
    .tc-spell__body { display: flex; flex-direction: column; gap: 1px; min-width: 0; flex: 1; }
    .tc-spell__label { font-family: "Cinzel", serif; font-size: 11.5px; letter-spacing: 0.02em; color: #efe7ff; }
    .is-good .tc-spell__label  { color: rgb(150,245,180); }
    .is-bad .tc-spell__label   { color: rgb(255,140,148); }
    .is-magic .tc-spell__label { color: rgb(214,178,255); }
    .tc-spell__amt { font-size: 10.5px; opacity: 0.72; }
    .tc-spell__x { font-family: "DM Mono", monospace; font-size: 10px; font-weight: 600; margin-right: 5px; padding: 1px 5px; border-radius: 5px; background: rgba(255,255,255,0.09); }
    .tc-spell__who { font-size: 9px; opacity: 0.34; align-self: flex-start; padding-top: 2px; }
    @keyframes tcSpellIn { from { opacity: 0; transform: translateX(26px) scale(0.94); } to { opacity: 1; transform: none; } }
    @media (max-width: 860px) { .tc-spell { display: none; } }

    /* INDEXER HEALTH. Most of the page reads from Ponder with no chain
       fallback, so when it is behind the UI renders empty rather than wrong-
       looking. This makes that state visible instead of silent. */
    .tc-health { position: fixed; left: 50%; transform: translateX(-50%); bottom: 16px; z-index: 80; display: flex; align-items: center; gap: 8px; padding: 7px 14px; border-radius: 999px; font-size: 11px; background: rgba(20,14,8,0.94); border: 1px solid rgba(246,200,106,0.3); color: #f6d9a0; backdrop-filter: blur(12px); box-shadow: 0 6px 22px rgba(0,0,0,0.5); }
    .tc-health.is-down { border-color: rgba(255,86,96,0.35); color: #ffc9cd; background: rgba(28,10,12,0.94); }
    .tc-health__dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; animation: tcHealthPulse 1.4s ease-in-out infinite; }
    .tc-health b { font-weight: 500; opacity: 0.6; }
    @keyframes tcHealthPulse { 0%,100% { opacity: 1; } 50% { opacity: 0.25; } }

    /* THE GRIMOIRE — the full activity run, on demand. The toasts announce and
       leave; this is where you look when something scrolled past. */
    .tc-grim__tab {
      position: fixed; right: 0; top: 50%; transform: translateY(-50%);
      z-index: 75; display: flex; flex-direction: column; align-items: center; gap: 7px;
      padding: 15px 8px; border: 1px solid rgba(168,140,255,0.2); border-right: none;
      border-radius: 12px 0 0 12px; cursor: pointer;
      background: linear-gradient(135deg, rgba(30,22,58,0.95), rgba(14,11,26,0.95));
      backdrop-filter: blur(14px); color: #cbb6ff; font-family: "DM Mono", monospace;
      transition: right 0.42s cubic-bezier(0.16,1,0.3,1), color 0.2s, border-color 0.2s;
    }
    .tc-grim__tab:hover { color: #efe7ff; border-color: rgba(168,140,255,0.45); }
    .tc-grim__tab.is-open { right: 320px; }
    .tc-grim__tab-text { writing-mode: vertical-rl; font-size: 9px; letter-spacing: 0.24em; }
    .tc-grim__tab-icon { font-size: 14px; line-height: 1; opacity: 0.7; }
    .tc-grim__tab-count { font-size: 9px; padding: 2px 5px; border-radius: 6px; background: rgba(196,142,255,0.22); color: #d9c4ff; }

    .tc-grim {
      position: fixed; top: 0; right: 0; bottom: 0; width: 320px; z-index: 74;
      display: flex; flex-direction: column;
      background: linear-gradient(180deg, rgba(22,16,42,0.97), rgba(11,9,20,0.98));
      border-left: 1px solid rgba(168,140,255,0.16);
      backdrop-filter: blur(20px) saturate(1.2);
      box-shadow: -18px 0 50px rgba(0,0,0,0.55);
      transform: translateX(100%);
      transition: transform 0.42s cubic-bezier(0.16,1,0.3,1);
    }
    .tc-grim.is-open { transform: none; }
    .tc-grim__head { display: flex; align-items: flex-start; justify-content: space-between; padding: 20px 18px 14px; border-bottom: 1px solid rgba(255,255,255,0.06); }
    .tc-grim__eyebrow { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.22em; text-transform: uppercase; color: rgba(196,142,255,0.75); margin-bottom: 5px; }
    .tc-grim__title { font-family: "Cinzel", serif; font-size: 17px; margin: 0; color: #f2ecff; }
    .tc-grim__close { background: none; border: none; color: rgba(255,255,255,0.34); font-size: 14px; cursor: pointer; padding: 2px 4px; }
    .tc-grim__close:hover { color: #fff; }

    .tc-grim__list { flex: 1; overflow-y: auto; padding: 8px 10px 20px; scrollbar-width: thin; }
    .tc-grim__list::-webkit-scrollbar { width: 5px; }
    .tc-grim__list::-webkit-scrollbar-thumb { background: rgba(168,140,255,0.22); border-radius: 3px; }
    .tc-grim__row { display: flex; align-items: center; gap: 10px; padding: 9px 10px; border-radius: 10px; text-decoration: none; color: inherit; border-left: 2px solid transparent; transition: background 0.18s; }
    .tc-grim__row:hover { background: rgba(255,255,255,0.045); }
    .tc-grim__row.is-good  { border-left-color: rgba(70,230,124,0.75); }
    .tc-grim__row.is-bad   { border-left-color: rgba(255,86,96,0.75); }
    .tc-grim__row.is-magic { border-left-color: rgba(196,142,255,0.75); }
    .tc-grim__row.is-neutral { border-left-color: rgba(255,255,255,0.18); }
    .tc-grim__rune { font-size: 14px; }
    .tc-grim__body { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
    .tc-grim__label { font-family: "Cinzel", serif; font-size: 11.5px; color: #ece4ff; }
    .is-good .tc-grim__label  { color: rgb(150,245,180); }
    .is-bad .tc-grim__label   { color: rgb(255,140,148); }
    .is-magic .tc-grim__label { color: rgb(214,178,255); }
    .tc-grim__meta { font-size: 9px; opacity: 0.32; }
    .tc-grim__right { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; }
    .tc-grim__amt { font-size: 10.5px; opacity: 0.8; }
    .tc-grim__ago { font-size: 9px; opacity: 0.3; }
    .tc-grim__empty { padding: 40px 18px; text-align: center; font-family: "DM Sans", sans-serif; font-size: 12px; color: rgba(255,255,255,0.42); display: flex; flex-direction: column; gap: 8px; }
    .tc-grim__empty span { font-size: 10.5px; opacity: 0.55; line-height: 1.5; }
    @media (max-width: 860px) { .tc-grim { width: 84vw; } .tc-grim__tab.is-open { right: 84vw; } }

    /* PROGRESSIVE SEED — depth streams in, so show it filling. */
    .tc-seed { margin-top: 10px; }
    .tc-seed__row { display: flex; justify-content: space-between; gap: 10px; font-size: 10px; margin-bottom: 5px; }
    .tc-seed__track { position: relative; height: 5px; border-radius: 3px; background: rgba(255,255,255,0.06); overflow: hidden; }
    .tc-seed__target { position: absolute; inset: 0 auto 0 0; background: rgba(255,255,255,0.14); transition: width 0.6s ease; }
    .tc-seed__fill { position: absolute; inset: 0 auto 0 0; border-radius: 3px; transition: width 0.6s ease; }
    .tc-seed__hint { font-size: 9.5px; opacity: 0.55; margin-top: 4px; }
    .tc-rot { background: rgba(8,6,15,0.42); border: 1px solid rgba(255,255,255,0.06); border-radius: var(--r-md); padding: 20px 22px; margin-bottom: 18px; }
    .tc-rot__head { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
    .tc-rot__title { font-family: "Cinzel", serif; font-size: 20px; margin: 4px 0 0; color: #f4f1ff; }
    .tc-rot__lead { font-family: "DM Sans", sans-serif; font-size: 12.5px; line-height: 1.6; color: ${C.mute}; margin: 10px 0 16px; max-width: 640px; }
    .tc-rot__targets { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 14px; }
    .tc-rot__targets button { font-family: "DM Mono", monospace; font-size: 12px; color: ${C.mute}; background: rgba(8,6,15,0.5); border: 1px solid rgba(255,255,255,0.07); padding: 7px 13px; border-radius: var(--r-sm); cursor: pointer; transition: all 0.15s ease; }
    .tc-rot__targets button:hover { color: #f4f1ff; border-color: rgba(255,255,255,0.16); }
    .tc-rot__targets button.on { background: rgba(213,253,81,0.16); color: ${C.lime}; border-color: rgba(213,253,81,0.3); }
    .tc-rot__grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 10px; margin-bottom: 14px; }
    .tc-rot__grid label { display: flex; flex-direction: column; gap: 5px; }
    .tc-rot__grid input { background: rgba(8,6,15,0.6); border: 1px solid rgba(255,255,255,0.08); border-radius: var(--r-sm); padding: 9px 11px; color: #f4f1ff; font-family: "DM Mono", monospace; font-size: 13px; }
    .tc-rot__steps { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 12px; }
    .tc-rot__steps .tc-btn { font-size: 12px; padding: 9px 14px; }
    .tc-rot__note { font-family: "DM Sans", sans-serif; font-size: 11px; line-height: 1.55; color: ${C.mute}; opacity: 0.85; margin: 0; }
    .tc-rot__log { list-style: none; padding: 10px 12px; margin: 12px 0 0; background: rgba(0,0,0,0.28); border-radius: var(--r-sm); font-size: 11px; color: ${C.mute}; }
    .tc-rot__log li { padding: 2px 0; }
    .tc-perp-gate { margin-bottom: 16px; padding: 14px 16px; border-radius: var(--r-sm); background: rgba(246,200,106,0.07); border: 1px solid rgba(246,200,106,0.22); }
    .tc-propose__pair-warn { margin: 8px 0 0; font-family: "DM Sans", sans-serif; font-size: 11px; line-height: 1.5; color: #f6c86a; opacity: 0.92; }
    .tc-propose__err { font-family: "DM Sans", sans-serif; font-size: 10px; color: ${C.red}; margin-top: 3px; }
    .tc-propose__summary { text-align: center; font-size: 11px; color: ${C.lime}; margin: 12px 0 4px; padding: 8px; border-radius: var(--r-sm); background: rgba(213,253,81,0.06); }
    .tc-prop__spec { display: flex; gap: 14px; flex-wrap: wrap; font-size: 10px; color: ${C.mute}; margin: 5px 0 2px; }
    .tc-prop__spec span { white-space: nowrap; }
    .tc-props { display: flex; flex-direction: column; gap: 12px; }
    .tc-prop { position: relative; display: flex; gap: 16px; align-items: center; padding: 16px; border-radius: var(--r-md); background: rgba(255,255,255,0.02); border: 1px solid rgba(255,255,255,0.06); transition: border-color .2s, transform .2s; }
    .tc-prop:hover { border-color: rgba(213,253,81,0.2); transform: translateY(-1px); }
    .tc-prop--lead { border-color: rgba(213,253,81,0.3); background: rgba(213,253,81,0.04); }
    /* clickable proposal row + branded logo chip */
    .tc-prop--click { cursor: pointer; }
    .tc-prop__logo { width: 46px; height: 46px; border-radius: var(--r-sm); object-fit: contain; padding: 5px; border: 2px solid; box-shadow: 0 4px 14px rgba(0,0,0,0.5); }
    .tc-prop__more { font-family: "DM Mono", monospace; font-size: 10px; color: ${C.lime}; opacity: 0.7; margin-left: auto; }
    .tc-prop:hover .tc-prop__more { opacity: 1; }

    /* proposal detail modal (brew-twitter style) */
    .tc-pm__scrim { position: fixed; inset: 0; z-index: 9999; background: rgba(6,5,11,0.86); backdrop-filter: blur(7px); display: grid; place-items: center; padding: 20px; animation: tc-pm-fade .2s ease; }
    @keyframes tc-pm-fade { from { opacity: 0; } to { opacity: 1; } }
    .tc-pm { position: relative; width: 460px; max-width: 94vw; max-height: 92vh; overflow-y: auto; border-radius: var(--r-md); background: linear-gradient(180deg, #171226, #0E0A1A); border: 1px solid rgba(255,255,255,0.08); box-shadow: 0 40px 90px -30px rgba(0,0,0,0.9); scrollbar-width: none; -ms-overflow-style: none; }
    .tc-pm::-webkit-scrollbar { display: none; }
    .tc-pm__proposer { display: flex; align-items: center; gap: 8px; }
    .tc-pm__x { position: absolute; top: 12px; right: 12px; z-index: 3; width: 30px; height: 30px; border-radius: var(--r-sm); border: none; background: rgba(8,6,15,0.6); color: ${C.cream}; font-size: 14px; cursor: pointer; }
    .tc-pm__x:hover { background: rgba(8,6,15,0.9); }
    .tc-pm__banner { position: relative; height: 150px; background-size: cover; background-position: center; border-radius: var(--r-md) var(--r-md) 0 0; }
    .tc-pm__banner::after { content: ""; position: absolute; inset: 0; background: linear-gradient(180deg, rgba(23,18,38,0.1), #171226); border-radius: var(--r-md) var(--r-md) 0 0; }
    .tc-pm__gen { position: absolute; top: 12px; left: 14px; z-index: 2; display: inline-flex; align-items: center; gap: 6px; font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.08em; padding: 4px 10px; border-radius: var(--r-chip); background: rgba(8,6,15,0.6); border: 1px solid; }
    .tc-pm__dot { width: 6px; height: 6px; border-radius: 50%; }
    .tc-pm__logo { position: relative; z-index: 2; width: 92px; height: 92px; margin: -46px 0 0 22px; border-radius: var(--r-md); display: grid; place-items: center; overflow: hidden; }
    .tc-pm__logo img { width: 100%; height: 100%; object-fit: contain; padding: 12px; }
    .tc-pm__body { padding: 12px 22px 22px; }
    .tc-pm__name { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 30px; color: ${C.cream}; margin: 6px 0 2px; letter-spacing: 0.01em; }
    .tc-pm__handle { display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; }
    .tc-pm__tick { font-size: 16px; font-weight: 700; }
    .tc-pm__by { font-family: "DM Mono", monospace; font-size: 12px; color: ${C.mute}; }
    .tc-pm__theme { font-family: "DM Sans", sans-serif; font-size: 13px; color: #b8adcc; line-height: 1.5; margin: 10px 0 0; }
    .tc-pm__links { display: flex; gap: 14px; margin-top: 12px; flex-wrap: wrap; }
    .tc-pm__link { display: inline-flex; align-items: center; gap: 6px; font-family: "DM Mono", monospace; font-size: 12px; color: #a99fd0; text-decoration: none; }
    .tc-pm__link:hover { color: ${C.cream}; }
    .tc-pm__grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin: 18px 0; }
    .tc-pm__stat { background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); border-radius: var(--r-sm); padding: 12px 13px; }
    .tc-pm__stat .k { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.1em; text-transform: uppercase; color: ${C.mute}; margin-bottom: 5px; }
    .tc-pm__stat .v { font-family: "Fredoka", sans-serif; font-weight: 700; font-size: 20px; color: ${C.cream}; }
    .tc-pm__stat .v span { font-size: 12px; font-weight: 500; color: ${C.mute}; }
    .tc-pm__votes { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-top: 4px; }
    .tc-pm__note { font-family: "DM Sans", sans-serif; font-size: 11px; color: ${C.mute}; opacity: 0.8; line-height: 1.5; margin-top: 14px; }
    .tc-prop__body { flex: 1; min-width: 0; }
    .tc-prop__head { display: flex; align-items: center; gap: 10px; margin-bottom: 4px; flex-wrap: wrap; }
    .tc-prop__name { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 16px; }
    .tc-prop__tick { font-size: 12px; color: ${C.lime}; }
    .tc-prop__lead-badge { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.1em; color: #0c0918; background: ${C.lime}; padding: 2px 8px; border-radius: var(--r-md); }
    .tc-prop__theme { font-size: 12.5px; color: rgba(231,225,245,0.55); margin-bottom: 8px; line-height: 1.4; }
    .tc-prop__foot { display: flex; align-items: center; gap: 14px; margin-bottom: 9px; flex-wrap: wrap; }
    .tc-prop__link { display: inline-flex; align-items: center; gap: 4px; font-family: "DM Mono", monospace; font-size: 11px; color: ${C.mute}; text-decoration: none; }
    .tc-prop__link:hover { color: ${C.lime}; }
    .tc-prop__votetrack { height: 5px; border-radius: var(--r-md); background: rgba(255,255,255,0.06); overflow: hidden; }
    .tc-prop__votefill { height: 100%; background: ${C.lime}; border-radius: var(--r-md); box-shadow: 0 0 10px ${C.lime}; transition: width .6s ease; }
    .tc-prop__vote { display: flex; flex-direction: column; align-items: center; gap: 3px; flex-shrink: 0; }
    .tc-prop__votes { font-size: 20px; font-weight: 700; color: ${C.cream}; }

    /* lineage */
    .tc-lineage { display: flex; flex-direction: column; gap: 10px; }
    .tc-lin { display: flex; align-items: center; gap: 16px; padding: 15px 18px; border-radius: var(--r-sm); background: rgba(255,255,255,0.02); border: 1px solid rgba(255,255,255,0.06); }
    .tc-lin--live { border-color: rgba(213,253,81,0.25); background: rgba(213,253,81,0.03); }
    .tc-lin__gen { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 20px; min-width: 48px; }
    .tc-lin__name { font-weight: 600; font-size: 15px; }
    .tc-lin__meta { font-size: 11px; text-transform: capitalize; }
    .tc-lin__body { flex: 1; }
    .tc-lin__dot { width: 9px; height: 9px; border-radius: 50%; }

    /* presale — the rich founding-guild mint */
    /* summoning / syncing state — graceful post-summon transition */
    .tc-summoning { max-width: 460px; margin: 40px auto; text-align: center; padding: 30px 24px; }
    .tc-summoning__portal { position: relative; width: 130px; height: 130px; margin: 0 auto 22px; display: grid; place-items: center; }
    .tc-summoning__ring { position: absolute; inset: 0; border-radius: 50%; border: 2px solid rgba(213,253,81,0.12); border-top-color: ${C.lime}; animation: tc-summon-spin 1.5s linear infinite; }
    .tc-summoning__ring--2 { inset: 15px; animation-duration: 1.1s; animation-direction: reverse; border-top-color: #a9cc2f; }
    .tc-summoning__ring--3 { inset: 30px; animation-duration: 0.8s; }
    .tc-summoning__core { position: relative; z-index: 1; font-size: 40px; animation: tc-summon-pulse 1.6s ease-in-out infinite; }
    @keyframes tc-summon-spin { to { transform: rotate(360deg); } }
    @keyframes tc-summon-pulse { 0%,100% { transform: scale(1); opacity: 0.85; } 50% { transform: scale(1.12); opacity: 1; } }
    .tc-summoning__t { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 22px; color: ${C.cream}; margin: 0 0 8px; }
    .tc-summoning__s { font-family: "DM Sans", sans-serif; font-size: 13px; color: ${C.mute}; line-height: 1.55; margin: 0; }
    .tc-summoning__dots i { display: inline-block; animation: tc-summon-blink 1.2s infinite both; color: ${C.lime}; }
    .tc-summoning__dots i:nth-child(2) { animation-delay: 0.2s; } .tc-summoning__dots i:nth-child(3) { animation-delay: 0.4s; }
    @keyframes tc-summon-blink { 0%,80%,100% { opacity: 0.2; } 40% { opacity: 1; } }

    .tc-presale { max-width: 860px; margin: 0 auto; position: relative; overflow: hidden; padding: 0; }
    .tc-ps-bg { position: absolute; inset: 0; overflow: hidden; pointer-events: none; opacity: 0.06; }
    .tc-ps-row { display: flex; gap: 6px; width: max-content; margin-bottom: 6px; animation: ps-marq 40s linear infinite; }
    .tc-ps-row:nth-child(2n) { animation-direction: reverse; animation-duration: 35s; }
    .tc-ps-row:nth-child(3) { animation-duration: 46s; } .tc-ps-row:nth-child(5) { animation-duration: 50s; animation-direction: reverse; }
    @keyframes ps-marq { to { transform: translateX(-50%); } }
    .tc-ps-fren { width: 60px; height: 60px; position: relative; flex-shrink: 0; image-rendering: pixelated; }
    .tc-ps-fren img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; }
    .tc-ps-inner { position: relative; z-index: 2; padding: 24px 26px; }

    .tc-ps-sub { font-size: 13px; color: rgba(231,225,245,0.62); line-height: 1.55; margin: 0 0 14px; max-width: 640px; }
    /* two columns: visual (left) + mint action (right, always in view) */
    .tc-ps-grid { display: grid; grid-template-columns: 1fr 320px; gap: 22px; align-items: start; }
    .tc-ps-visual { min-width: 0; }
    .tc-ps-action {
      display: flex; flex-direction: column; gap: 13px;
      padding: 16px; border-radius: var(--r-md);
      background: rgba(8,6,15,0.35); border: 1px solid rgba(213,253,81,0.18);
    }
    @media (max-width: 860px) {
      .tc-ps-grid { grid-template-columns: 1fr; }
      .tc-ps-action { order: -1; } /* mint controls first on mobile — no scroll */
    }
    /* 5 fanned rare frens, larger, pushed DOWN so their feet crop at the base. */
    .tc-ps-cluster { position: relative; width: 100%; height: 244px; margin: -14px auto 22px; overflow: hidden; }
    .tc-ps-hero { position: absolute; image-rendering: pixelated; }
    .tc-ps-hero img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; }
    /* bottom is NEGATIVE → feet dip below the crop line */
    .tc-ps-hero--xl { width: 178px; height: 178px; left: -4%;  bottom: -36px; z-index: 1; filter: drop-shadow(0 6px 16px rgba(0,0,0,0.4)); }
    .tc-ps-hero--xr { width: 178px; height: 178px; right: -4%; bottom: -36px; z-index: 1; filter: drop-shadow(0 6px 16px rgba(0,0,0,0.4)); }
    .tc-ps-hero--l  { width: 200px; height: 200px; left: 8%;   bottom: -46px; z-index: 2; filter: drop-shadow(0 6px 16px rgba(0,0,0,0.45)); }
    .tc-ps-hero--r  { width: 200px; height: 200px; right: 8%;  bottom: -46px; z-index: 2; filter: drop-shadow(0 6px 16px rgba(0,0,0,0.45)); }
    .tc-ps-hero--c  { width: 236px; height: 236px; left: 50%; transform: translateX(-50%); bottom: -54px; z-index: 3; filter: drop-shadow(0 0 30px rgba(213,253,81,0.3)) drop-shadow(0 8px 18px rgba(0,0,0,0.55)); }
    @media (max-width: 640px) {
      .tc-ps-hero--xl, .tc-ps-hero--xr { display: none; }
      .tc-ps-hero--l { width: 158px; height: 158px; left: 2%; }
      .tc-ps-hero--r { width: 158px; height: 158px; right: 2%; }
      .tc-ps-hero--c { width: 188px; height: 188px; }
    }
    .tc-ps-benefits { display: flex; justify-content: center; gap: 8px; position: relative; z-index: 4; margin-bottom: 20px; }
    .tc-ps-benefit { display: inline-flex; align-items: center; gap: 5px; font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.06em; text-transform: uppercase; color: ${C.lime}; background: rgba(213,253,81,0.08); border: 1px solid rgba(213,253,81,0.18); padding: 5px 11px; border-radius: var(--r-md); }

    .tc-ps-prog { margin-bottom: 18px; }
    .tc-ps-progrow { display: flex; justify-content: space-between; font-size: 11px; margin-bottom: 7px; }
    .tc-presale__track { height: 9px; border-radius: var(--r-md); background: rgba(255,255,255,0.06); overflow: hidden; }
    .tc-presale__fill { height: 100%; background: linear-gradient(90deg, ${C.lime}, #a9cc2f); border-radius: var(--r-md); box-shadow: 0 0 16px rgba(213,253,81,0.4); transition: width .6s ease; }

    .tc-ps-qtyrow { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 16px; }
    .tc-ps-stepper { display: flex; align-items: center; gap: 6px; }
    .tc-ps-stepper button { width: 40px; height: 40px; border-radius: var(--r-sm); border: 1px solid rgba(213,253,81,0.3); background: rgba(213,253,81,0.06); color: ${C.lime}; font-size: 20px; font-family: "DM Mono", monospace; cursor: pointer; transition: background .2s; }
    .tc-ps-stepper button:hover { background: rgba(213,253,81,0.16); }
    .tc-ps-stepper span { min-width: 44px; text-align: center; font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 24px; color: ${C.cream}; }
    .tc-ps-price { text-align: right; display: flex; flex-direction: column; gap: 2px; }
    .tc-ps-price__eth { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 22px; color: ${C.cream}; }
    .tc-ps-price__eth em { font-style: normal; font-size: 12px; color: ${C.mute}; }

    .tc-ps-art { padding: 13px 14px; background: rgba(213,253,81,0.06); border: 1px solid rgba(213,253,81,0.18); border-left: 3px solid ${C.lime}; border-radius: var(--r-sm); margin-bottom: 14px; }
    .tc-ps-art__tag { display: inline-block; font-family: "DM Mono", monospace; font-size: 9px; font-weight: 700; letter-spacing: 0.12em; color: #0c0918; background: ${C.lime}; padding: 3px 8px; border-radius: var(--r-chip); margin-bottom: 8px; }
    .tc-ps-art__text { margin: 0; font-size: 12px; line-height: 1.5; color: rgba(231,225,245,0.72); }
    .tc-ps-art__text strong { color: ${C.amber}; }
    .tc-ps-terms { display: flex; align-items: flex-start; gap: 10px; padding: 12px; background: rgba(255,255,255,0.03); border-radius: var(--r-sm); cursor: pointer; margin-bottom: 16px; }
    .tc-ps-terms input { width: 16px; height: 16px; margin-top: 1px; flex-shrink: 0; accent-color: ${C.lime}; cursor: pointer; }
    .tc-ps-terms span { font-size: 11px; line-height: 1.5; color: rgba(231,225,245,0.55); }
    .tc-ps-adv { display: block; width: 100%; margin-top: 12px; background: none; border: none; color: ${C.mute}; font-family: "DM Mono", monospace; font-size: 11px; cursor: pointer; transition: color .2s; }
    .tc-ps-adv:hover { color: ${C.lime}; }

    .tc-empty { text-align: center; padding: 40px; font-family: "DM Mono", monospace; font-size: 13px; color: ${C.mute}; border: 1px dashed rgba(255,255,255,0.1); border-radius: var(--r-sm); }

    /* fren face */
    .tc-face { overflow: hidden; position: relative; background: #171226; flex-shrink: 0; }
    .tc-face__zoom { width: 100%; height: 100%; }
    .tc-face__zoom > div { width: 100% !important; height: 100% !important; transform: scale(2.35); transform-origin: 50% 47%; }

    @media (prefers-reduced-motion: reduce) {
      .tc-core__halo--pulse, .tc-core__orb--live, .tc-core__ring--a, .tc-core__ring--b, .tc-vital__fill--beat, .tc-ekg__line, .tc-ember { animation: none !important; }
    }
    `}</style>
  );
}
