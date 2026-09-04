import { useEffect } from "react";
import { createPortal } from "react-dom";

interface Props {
  open: boolean;
  onClose: () => void;
  /** Called when the reader clicks the "spread the magic" seal (shares to X). */
  onSpread?: () => void;
}

/**
 * ManifrenstoModal — the MANIFRENSTO rendered as an aged medieval parchment
 * scroll: warm vellum, burnt edges, illuminated drop-cap, and a wax seal CTA.
 * Explains the novel concept (the eternal, self-funding Cauldron) in-character.
 */
export default function ManifrenstoModal({ open, onClose, onSpread }: Props) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => { window.removeEventListener("keydown", onKey); document.body.style.overflow = ""; };
  }, [open, onClose]);

  if (!open) return null;

  return createPortal(
    <div className="mf-overlay" onClick={onClose}>
      <style>{css}</style>
      <div className="mf-scroll" onClick={(e) => e.stopPropagation()} role="dialog" aria-label="The Magic Manifrensto">
        <button className="mf-x" onClick={onClose} aria-label="Close">✕</button>

        <div className="mf-parchment">
          <div className="mf-edge mf-edge--top" aria-hidden />
          <div className="mf-body">
            <div className="mf-crest" aria-hidden>✦</div>
            <h2 className="mf-title">The Magic Manifrensto</h2>
            <div className="mf-rule" aria-hidden />

            <p className="mf-verse">
              <span className="mf-dropcap">C</span>ountless moons have passed, and the art of wizardry
              hath faded from the minds of many. The chain grew cold. The magic was forgotten.
            </p>
            <p className="mf-verse">
              Yet a spark remains. We, the Frens, do gather to rekindle it — not with promises of riches,
              but with a machine of pure and honest sorcery. Behold <em>the Cauldron</em>: an eternal engine
              that funds itself from its own trade, answers to no master, and can never be stopped.
            </p>
            <p className="mf-verse">
              Each token it summons lives, breathes, and is traded. When its fire dims and volume fades,
              it dies — and from its ashes the guild votes a new one into being. So the cycle turns,
              forever, with no hand upon the treasury and no bridge to burn.
            </p>
            <p className="mf-verse">
              The <strong>1111 genesis Frens</strong> are the founding guild, earning a share of every
              brew's fees for as long as the chain shall run. The other <strong>1111</strong> are forged
              from the heat of trade itself — crystals summoned from raw volume, cracked open to reveal
              the creature sealed within.
            </p>
            <p className="mf-verse mf-verse--vow">
              This is our vow: to build the Fren Village, on-chain and unbroken. To keep the magic wild,
              the code trustless, and the frens forever. <span className="mf-gm">gm. wagmi.</span>
            </p>

            <div className="mf-sign">— sealed by the guild of Magic Internet Frens</div>

            <button className="mf-seal" onClick={() => onSpread?.()}>
              <span className="mf-seal-wax">✦</span>
              Spread the Magic
            </button>
          </div>
          <div className="mf-edge mf-edge--bottom" aria-hidden />
        </div>
      </div>
    </div>,
    document.body,
  );
}

const css = `
  .mf-overlay {
    position: fixed; inset: 0; z-index: 300; display: grid; place-items: center; padding: 24px;
    background: rgba(14, 10, 26, 0.82); backdrop-filter: blur(5px);
    animation: mf-fade 0.25s ease;
  }
  .mf-scroll {
    position: relative; width: 100%; max-width: 640px; max-height: 88vh; overflow: visible;
    animation: mf-unfurl 0.4s cubic-bezier(.2,1,.3,1);
  }
  .mf-x {
    position: absolute; top: -14px; right: -14px; z-index: 3; width: 34px; height: 34px; border-radius: 50%;
    border: 2px solid #6b4f2a; background: #2A1F54; color: #f6c86a; cursor: pointer; font-size: 14px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.4);
  }
  .mf-x:hover { background: #3a2b6e; }

  .mf-parchment {
    position: relative; border-radius: 4px; overflow: hidden;
    background:
      radial-gradient(120% 90% at 50% 0%, rgba(120, 82, 34, 0.10), transparent 55%),
      radial-gradient(80% 60% at 85% 100%, rgba(120, 82, 34, 0.14), transparent 55%),
      linear-gradient(175deg, #f3e3c0 0%, #ecd9ad 45%, #e6cf9c 100%);
    box-shadow:
      inset 0 0 60px rgba(120, 82, 34, 0.28),
      inset 0 0 140px rgba(90, 60, 20, 0.12),
      0 30px 80px rgba(0,0,0,0.55);
    border: 1px solid #cdb488;
  }
  /* torn/burnt roller edges top & bottom */
  .mf-edge { height: 22px; background:
      repeating-linear-gradient(90deg, #d8c290 0 8px, #cbb47f 8px 16px);
    box-shadow: inset 0 0 20px rgba(90,60,20,0.35); }
  .mf-edge--top { border-bottom: 1px solid rgba(120,82,34,0.3); }
  .mf-edge--bottom { border-top: 1px solid rgba(120,82,34,0.3); }

  .mf-body {
    padding: 30px clamp(24px, 5vw, 52px) 34px;
    max-height: calc(88vh - 44px); overflow-y: auto;
    color: #3a2a12;
    font-family: "Cinzel", "Cinzel Decorative", Georgia, serif;
  }
  .mf-body::-webkit-scrollbar { width: 8px; }
  .mf-body::-webkit-scrollbar-thumb { background: rgba(120,82,34,0.4); border-radius: 4px; }

  .mf-crest { text-align: center; font-size: 22px; color: #9a6b2c; margin-bottom: 4px; }
  .mf-title {
    text-align: center; font-family: "Cinzel Decorative", serif; font-weight: 900;
    font-size: clamp(24px, 5vw, 36px); color: #4a2f10; margin: 0 0 12px;
    letter-spacing: 0.02em; text-shadow: 0 1px 0 rgba(255,255,255,0.35);
  }
  .mf-rule {
    height: 2px; margin: 0 auto 22px; max-width: 220px;
    background: linear-gradient(90deg, transparent, #9a6b2c, transparent);
  }

  .mf-verse {
    font-size: 15.5px; line-height: 1.75; margin: 0 0 16px; text-align: justify;
    font-family: Georgia, "Times New Roman", serif; color: #43310f;
  }
  .mf-verse em { font-style: italic; color: #6b3f10; }
  .mf-verse strong { color: #5a3a0e; }
  .mf-dropcap {
    float: left; font-family: "Cinzel Decorative", serif; font-weight: 900;
    font-size: 58px; line-height: 0.8; padding: 4px 10px 0 0; color: #8a4b12;
    text-shadow: 0 2px 0 rgba(255,255,255,0.4);
  }
  .mf-verse--vow { font-style: italic; color: #5a3a0e; }
  .mf-gm { font-family: "Cinzel Decorative", serif; font-weight: 700; color: #7a4a12; }

  .mf-sign {
    text-align: right; font-family: "Cinzel Decorative", serif; font-style: italic;
    font-size: 13px; color: #6b4f2a; margin: 18px 0 24px; opacity: 0.85;
  }

  .mf-seal {
    display: flex; align-items: center; gap: 10px; margin: 0 auto; padding: 12px 26px;
    border: none; border-radius: 30px; cursor: pointer;
    background: linear-gradient(180deg, #8f2b2b, #6e1f1f); color: #f3e3c0;
    font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 14px; letter-spacing: 0.03em;
    box-shadow: 0 6px 18px rgba(110, 31, 31, 0.5), inset 0 1px 0 rgba(255,255,255,0.15);
    transition: transform 0.15s ease, box-shadow 0.15s ease;
  }
  .mf-seal:hover { transform: translateY(-2px); box-shadow: 0 10px 24px rgba(110, 31, 31, 0.6), inset 0 1px 0 rgba(255,255,255,0.2); }
  .mf-seal-wax {
    width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center;
    background: radial-gradient(circle at 35% 30%, #c14b4b, #7e2222); color: #f3e3c0; font-size: 11px;
    box-shadow: inset 0 0 4px rgba(0,0,0,0.4);
  }

  @keyframes mf-fade { from { opacity: 0; } to { opacity: 1; } }
  @keyframes mf-unfurl { from { opacity: 0; transform: scale(0.94) translateY(14px); } to { opacity: 1; transform: none; } }
  @media (prefers-reduced-motion: reduce) { .mf-scroll { animation: none; } }
`;
