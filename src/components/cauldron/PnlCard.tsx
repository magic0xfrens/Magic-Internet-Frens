import { useMemo, useRef, useState } from "react";
import { useAccount } from "wagmi";
import { toPng } from "html-to-image";
import FrenSprite from "@/components/shared/FrenSprite";
import { BODIES, FACES, GNOME_FACES, ELF_FACES, ITEMS, CLASS_ORDER, type FrenClass } from "@/data/frens";

export type CardKind = "win" | "loss" | "rip";
export interface CardData {
  pnlEth: number;
  roiPct: number;
  kind: CardKind;
  leverage: number;
  isLong: boolean;
  entryPrice?: number; // ETH per token at open — enables the entry/mark columns
}

interface PnlCardProps extends CardData {
  ticker: string;
  col: string;
  spotPrice: number;
  priceUsd: number;
  onClose: () => void;
}

// deterministic wizard fren from the wallet — "your" trader avatar
function facesFor(cls: FrenClass) { return cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES; }
function frenFromSeed(seed: number) {
  const cls = CLASS_ORDER[seed % CLASS_ORDER.length];
  const bodies = BODIES[cls], items = ITEMS[cls], faces = facesFor(cls);
  const bodyIdx = (seed * 7 + 3) % bodies.length;
  const faceIdx = (seed * 13 + 5) % faces.length;
  const itemIdx = (seed * 5 + 2) % items.length;
  return { bodyFile: bodies[bodyIdx].file, faceFile: faces[faceIdx].file, itemFile: items[itemIdx].file, bodyIdx, faceIdx, itemIdx, cls };
}
function addrSeed(a?: string) {
  if (!a) return 42;
  let h = 0; for (let i = 2; i < a.length; i++) h = (h * 31 + a.charCodeAt(i)) >>> 0;
  return h;
}
function fmtUsd(v: number) {
  if (!(v > 0)) return "—";
  if (v < 0.01) return `$${v.toPrecision(3)}`;
  return `$${v.toLocaleString(undefined, { maximumFractionDigits: v < 1 ? 4 : 2 })}`;
}

const GREEN = "#31d996", RED = "#ff5470", CREAM = "#EDEAF5", MUTE = "#8c85a8", INK = "#07060c";

/**
 * PnlCard — a shareable trading PnL card in the clean, Hyperliquid-style mould:
 * concentric ring backdrop, oversized hero ROI, entry/mark price columns, and the
 * trader's own pixel fren as the mascot. Three moods: WIN (green), LOSS (red),
 * RIP (liquidated — skull, "REKT BY THE CAULDRON"). Download as PNG or share to X.
 */
export default function PnlCard({ ticker, col, spotPrice, priceUsd, pnlEth, roiPct, kind, leverage, isLong, entryPrice, onClose }: PnlCardProps) {
  const { address } = useAccount();
  const cardRef = useRef<HTMLDivElement>(null);
  const [saving, setSaving] = useState(false);
  const fren = useMemo(() => frenFromSeed(addrSeed(address)), [address]);

  const rip = kind === "rip";
  const up = !rip && pnlEth >= 0;
  const accent = rip ? RED : up ? GREEN : RED;
  const glow = rip ? "rgba(255,84,112,0.22)" : up ? "rgba(49,217,150,0.22)" : "rgba(255,84,112,0.20)";
  const sign = pnlEth >= 0 ? "+" : "";
  const verdict = rip ? "Liquidated" : up ? "Realized profit" : "Realized loss";

  // entry & mark in USD — derived from the ETH-per-token ratio so we only need entryPrice
  const markUsd = priceUsd;
  const entryUsd = entryPrice && spotPrice > 0 ? priceUsd * (entryPrice / spotPrice) : 0;

  const download = async () => {
    if (!cardRef.current) return;
    setSaving(true);
    try {
      const dataUrl = await toPng(cardRef.current, { pixelRatio: 2, cacheBust: true, backgroundColor: INK });
      const a = document.createElement("a");
      a.download = `mifrens-pnl-${kind}-${Date.now()}.png`;
      a.href = dataUrl; a.click();
    } catch { /* toPng can fail on cross-origin imgs; the fren art is same-origin */ }
    finally { setSaving(false); }
  };
  const shareX = () => {
    const txt = rip
      ? `Got liquidated ${leverage}× on $${ticker} in The Cauldron ⚰️ ${roiPct.toFixed(0)}%. wagmi anyway 🧙‍♂️`
      : `${sign}${roiPct.toFixed(0)}% ${isLong ? "long" : "short"} ${leverage}× on $${ticker} via The Cauldron's hook-native perps 🧙‍♂️⚡`;
    const url = `https://x.com/intent/post?text=${encodeURIComponent(txt + "\n\nmifrens.xyz")}`;
    window.open(url, "_blank", "noopener");
  };

  return (
    <div className="pc-scrim" onClick={onClose}>
      <style>{`
        .pc-scrim { position: fixed; inset: 0; z-index: 9999; background: rgba(6,5,11,0.86); backdrop-filter: blur(7px); display: grid; place-items: center; padding: 20px; animation: pc-fade .2s ease; }
        @keyframes pc-fade { from { opacity: 0; } to { opacity: 1; } }
        .pc-wrap { display: flex; flex-direction: column; align-items: center; gap: 16px; }
        .pc-card { position: relative; width: 480px; max-width: 92vw; aspect-ratio: 1.5; border-radius: var(--r-sm); overflow: hidden;
          background:
            repeating-radial-gradient(circle at 82% 44%, rgba(255,255,255,0.028) 0 1px, transparent 1px 26px),
            radial-gradient(120% 120% at 82% 44%, ${glow}, transparent 52%),
            linear-gradient(155deg, #0d0b16 0%, ${INK} 70%);
          border: 1px solid rgba(255,255,255,0.07);
          box-shadow: 0 30px 80px -28px rgba(0,0,0,0.9), 0 0 0 1px rgba(255,255,255,0.02) inset;
          font-family: "DM Sans", system-ui, sans-serif; color: ${CREAM}; }
        .pc-inner { position: relative; height: 100%; padding: 26px 26px 22px; display: flex; flex-direction: column; }

        .pc-fren { position: absolute; right: 14px; top: 50%; transform: translateY(-46%); width: 208px; height: 208px; border-radius: var(--r-sm); overflow: hidden; image-rendering: pixelated; opacity: 0.98;
          -webkit-mask-image: radial-gradient(120% 120% at 50% 50%, #000 62%, transparent 92%);
          mask-image: radial-gradient(120% 120% at 50% 50%, #000 62%, transparent 92%); }
        .pc-fren-zoom { position: absolute; width: 168%; height: 168%; left: 50%; top: 30%; transform: translate(-50%,-14%) ${isLong ? "" : "scaleX(-1)"}; }
        /* red card: rekt wizard, NOT in a box — anchored to the card's bottom,
           black background dropped so it blends into the card. */
        .pc-rekt { position: absolute; right: -8px; bottom: 0; height: 86%; width: auto; max-width: 54%;
          object-fit: contain; object-position: bottom right; mix-blend-mode: screen;
          pointer-events: none; opacity: 0.98; }

        .pc-brand { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 15px; letter-spacing: -0.01em; color: ${CREAM}; }
        .pc-mark { width: 18px; height: 18px; border-radius: var(--r-chip); background: linear-gradient(135deg, ${col}, #f6c86a); box-shadow: 0 0 12px ${col}66; }
        .pc-brand span { color: ${MUTE}; font-weight: 500; }

        .pc-pairrow { display: flex; align-items: center; gap: 8px; margin-top: 20px; }
        .pc-pair { font-family: "DM Mono", monospace; font-size: 14px; font-weight: 500; letter-spacing: 0.02em; color: ${CREAM}; }
        .pc-pill { font-family: "DM Mono", monospace; font-size: 10px; font-weight: 500; letter-spacing: 0.06em; padding: 3px 8px; border-radius: var(--r-chip); text-transform: uppercase;
          color: ${isLong ? GREEN : RED}; background: ${(isLong ? GREEN : RED)}1e; border: 1px solid ${(isLong ? GREEN : RED)}3a; }

        .pc-hero { margin-top: auto; }
        .pc-verdict { font-size: 12px; font-weight: 500; letter-spacing: 0.01em; color: ${MUTE}; margin-bottom: 2px; }
        .pc-roi { font-weight: 800; font-size: 62px; line-height: 0.98; letter-spacing: -0.035em; color: ${accent}; text-shadow: 0 0 30px ${glow}; }
        .pc-pnl { margin-top: 6px; font-family: "DM Mono", monospace; font-size: 15px; font-weight: 500; color: ${accent}; letter-spacing: 0.01em; }

        .pc-prices { display: flex; gap: 34px; margin-top: 18px; padding-top: 16px; border-top: 1px solid rgba(255,255,255,0.07); }
        .pc-col .k { font-size: 11px; color: ${MUTE}; letter-spacing: 0.01em; margin-bottom: 3px; }
        .pc-col .v { font-family: "DM Mono", monospace; font-size: 14px; font-weight: 500; color: ${CREAM}; }

        .pc-site { position: absolute; right: 26px; bottom: 22px; font-family: "DM Mono", monospace; font-size: 11px; letter-spacing: 0.02em; color: ${MUTE}; }

        .pc-actions { display: flex; gap: 8px; }
        .pc-btn { padding: 9px 16px; border-radius: var(--r-sm); font-family: "DM Sans", sans-serif; font-weight: 600; font-size: 13px; cursor: pointer; border: 1px solid; transition: all .15s ease; }
        .pc-btn--dl { color: ${CREAM}; border-color: rgba(255,255,255,0.16); background: rgba(255,255,255,0.05); }
        .pc-btn--dl:hover { background: rgba(255,255,255,0.11); }
        .pc-btn--x { color: ${INK}; border-color: transparent; background: ${CREAM}; }
        .pc-btn--x:hover { background: #fff; }
        .pc-btn--close { color: ${MUTE}; border-color: transparent; background: transparent; }
      `}</style>

      <div className="pc-wrap" onClick={(e) => e.stopPropagation()}>
        <div className="pc-card" ref={cardRef}>
          <div className="pc-inner">
            {up ? (
              // win card: the comfy money-wizard — free-standing (no square),
              // bottom-anchored to the card, black bg dropped via screen blend.
              <img className="pc-rekt" src="/win-wizard.png" alt="" />
            ) : (
              // red card: the angry rekt wizard — same treatment.
              <img className="pc-rekt" src="/rekt-wizard.png" alt="" />
            )}

            <div className="pc-brand"><span className="pc-mark" />The Cauldron <span>· perps</span></div>

            <div className="pc-pairrow">
              <span className="pc-pair">${ticker}-PERP</span>
              <span className="pc-pill">{isLong ? "LONG" : "SHORT"} {leverage}×</span>
            </div>

            <div className="pc-hero">
              <div className="pc-verdict">{verdict}</div>
              <div className="pc-roi">{sign}{roiPct.toFixed(1)}%</div>
              <div className="pc-pnl">{sign}{pnlEth.toFixed(4)} Ξ</div>
            </div>

            <div className="pc-prices">
              <div className="pc-col"><div className="k">Entry Price</div><div className="v">{fmtUsd(entryUsd)}</div></div>
              <div className="pc-col"><div className="k">Mark Price</div><div className="v">{fmtUsd(markUsd)}</div></div>
            </div>

            <div className="pc-site">mifrens.xyz</div>
          </div>
        </div>

        <div className="pc-actions">
          <button className="pc-btn pc-btn--dl" onClick={download} disabled={saving}>{saving ? "Saving…" : "⬇ Save image"}</button>
          <button className="pc-btn pc-btn--x" onClick={shareX}>Share on 𝕏</button>
          <button className="pc-btn pc-btn--close" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
}
