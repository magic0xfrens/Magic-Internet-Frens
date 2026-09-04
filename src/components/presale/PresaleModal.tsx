import { useState, useEffect, useCallback, useMemo, useRef } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { useAccount } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { useMiFrensPresale } from "@/hooks/useMiFrensPresale";
import FrenSprite from "@/components/shared/FrenSprite";
import { frenTraitsForToken } from "@/data/frenAssign";
import { resolveSprites, traitSummary } from "@/data/traitResolver";

const CLASS_NAMES: Record<number, string> = {
  0: "Wizard", 1: "King", 2: "Knight", 3: "Apprentice", 4: "Peasant", 5: "Gnome", 6: "Elf",
};
const spriteFor = (tokenId: number) => {
  const t = frenTraitsForToken(tokenId);
  return { ...t, ...resolveSprites(t.classIdx, t.bodyIdx, t.faceIdx, t.itemIdx) };
};

/** The ERC-721 Transfer(0x0 → owner) tokenId from the mint receipt = the fren we
 *  minted. topics[3] holds the indexed tokenId. Returns the FIRST mint's id. */
function mintedIdFromReceipt(receipt: unknown): number | null {
  try {
    const logs = (receipt as { logs?: { topics?: string[] }[] })?.logs ?? [];
    const TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
    for (const l of logs) {
      const t = l.topics ?? [];
      // Transfer(from,to,tokenId): from == 0x0 (mint), tokenId in topics[3].
      if (t[0]?.toLowerCase() === TRANSFER && t.length === 4 && BigInt(t[1] ?? "0x0") === 0n) {
        return Number(BigInt(t[3] as string));
      }
    }
  } catch { /* ignore */ }
  return null;
}

interface PresaleModalProps {
  isOpen: boolean;
  onClose: () => void;
  /** Fire the mint immediately on open (Cauldron inline "Mint"). */
  autoMint?: boolean;
  initialAmount?: number;
  /** Fires when the summon (finalize) confirms. */
  onSummoned?: () => void;
}

/**
 * PresaleModal — a clean, one-step ETH mint for the founding-guild MiFrens.
 * Replaces the old multi-chain (ETH/BTC/BNB) flow: connect → pick quantity →
 * mint. When the tranche sells out, anyone can ignite iteration #1 (finalize).
 */
export default function PresaleModal({ isOpen, onClose, autoMint = false, initialAmount = 1, onSummoned }: PresaleModalProps) {
  const { isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const p = useMiFrensPresale();
  const [amount, setAmount] = useState(initialAmount);
  const [autoFired, setAutoFired] = useState(false);
  const [preview, setPreview] = useState(0);

  const remaining = p.minted != null ? Math.max(0, p.maxSupply - p.minted) : undefined;
  const maxMint = Math.max(1, Math.min(remaining ?? 10, 10));
  const busy = p.isPending || p.confirming;
  const total = (p.priceEth * amount).toLocaleString(undefined, { maximumFractionDigits: 6 });

  // The actual minted fren (parsed from the receipt once the tx confirms).
  const mintedId = useMemo(() => (p.confirmed ? mintedIdFromReceipt(p.receipt) : null), [p.confirmed, p.receipt]);

  // While the tx is in flight, cycle FAST through random frens (slot machine);
  // idle cycles slowly as a preview. Stops once we know the minted fren.
  useEffect(() => {
    if (!isOpen || mintedId != null) return;
    const speed = busy ? 90 : 2000;
    const id = setInterval(() => setPreview((n) => n + 1), speed);
    return () => clearInterval(id);
  }, [isOpen, busy, mintedId]);

  // Sprite shown in the art window: the real fren once revealed, else the cycle.
  const shownSprite = useMemo(() => {
    if (mintedId != null) return spriteFor(mintedId);
    return spriteFor(((preview * 137 + 7) % 1111) + 1);
  }, [mintedId, preview]);

  const doMint = useCallback(() => { p.mint(amount).catch(() => {}); }, [p, amount]);

  // Reset when reopened; clamp amount to what's mintable.
  useEffect(() => {
    if (isOpen) { setAmount(Math.min(initialAmount, maxMint)); setAutoFired(false); p.reset(); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen]);

  // Auto-mint (Cauldron inline button).
  useEffect(() => {
    if (isOpen && autoMint && !autoFired && isConnected && !busy && !p.confirmed) {
      setAutoFired(true); doMint();
    }
  }, [isOpen, autoMint, autoFired, isConnected, busy, p.confirmed, doMint]);

  // Notify parent ONLY on the finalize TRANSITION (false→true), i.e. a genuine
  // fresh summon this session — never while `finalized` is already true (which it
  // stays forever on-chain). Firing on every render (onSummoned is an inline
  // callback whose identity changes each render) caused an infinite setState loop
  // that flooded the indexer (net::ERR_INSUFFICIENT_RESOURCES / max update depth).
  const wasFinalized = useRef(p.finalized);
  useEffect(() => {
    if (p.finalized && !wasFinalized.current) onSummoned?.();
    wasFinalized.current = p.finalized;
  }, [p.finalized, onSummoned]);

  if (!isOpen) return null;

  const soldOut = p.soldOut;

  return createPortal(
    <div className="pm__overlay" onClick={busy ? undefined : onClose}>
      <div className="pm__modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <button className="pm__close" onClick={onClose} disabled={busy} aria-label="Close"><X size={18} /></button>

        <div className="pm__eyebrow">{soldOut && !p.confirmed ? "Iteration #1 · GnomeLand" : "The Founding Guild"}</div>
        <h2 className="pm__title">
          {p.confirmed ? "Your MiFren" : busy ? "Summoning…" : soldOut ? "Ignite the Cauldron" : "Mint a MiFren"}
        </h2>

        {/* sold-out → GnomeLand brand; else preview / slot-machine / reveal */}
        {soldOut && !p.confirmed ? (
          <div className="pm__art">
            <div className="pm__art-brand"><img src="/brews/gnomeland-pfp.png" alt="GnomeLand" /></div>
          </div>
        ) : (
        <div className={`pm__art${busy ? " pm__art--spin" : ""}${mintedId != null ? " pm__art--reveal" : ""}`}>
          <div className="pm__art-inner">
            <FrenSprite {...shownSprite} alt={mintedId != null ? `MiFren #${mintedId}` : "MiFren"} />
          </div>
          {busy && <div className="pm__art-scan" aria-hidden />}
          {mintedId != null && <div className="pm__art-burst" aria-hidden />}
        </div>
        )}

        {p.confirmed ? (
          <div className="pm__done">
            <div className="pm__reveal-name">
              <span className="pm__reveal-id">#{mintedId ?? "—"}</span>
              {mintedId != null && <span className="pm__reveal-class">{CLASS_NAMES[spriteFor(mintedId).classIdx]}</span>}
            </div>
            {mintedId != null && (
              <p className="pm__reveal-traits">
                {traitSummary(spriteFor(mintedId).classIdx, spriteFor(mintedId).bodyIdx, spriteFor(mintedId).faceIdx, spriteFor(mintedId).itemIdx)}
              </p>
            )}
            <p className="pm__done-sub">A genesis founder is yours — it earns from every iteration's fees. Cast the spell to start.</p>
            {/* If THIS mint completed the sellout, celebrate the mint-out AND
                offer the summon right here (don't hide it behind a re-open). */}
            {soldOut && (
              <div className="pm__mintout">
                <p className="pm__done-title">🎉 Genesis is minted out!</p>
                <p className="pm__done-sub">All {p.maxSupply.toLocaleString()} founding MiFrens are claimed. Ignite iteration&nbsp;#1 — <b style={{ color: "#f5f0e8" }}>GnomeLand</b> — to seed the eternal Cauldron.</p>
              </div>
            )}
            <div className="pm__done-actions">
              {soldOut && !p.finalized && (
                <button className="pm__btn pm__btn--primary" disabled={p.finalizing} onClick={() => p.finalize().catch(() => {})}>
                  {p.finalizing ? "Igniting…" : "⚡ Summon iteration #1"}
                </button>
              )}
              {soldOut && p.finalized ? (
                <a href="#/cauldrons" className="pm__btn pm__btn--primary" onClick={onClose}>Enter the Cauldron</a>
              ) : (
                <a href="#/mi-frens" className={`pm__btn ${soldOut ? "pm__btn--ghost" : "pm__btn--primary"}`} onClick={onClose}>View my frens</a>
              )}
            </div>
          </div>
        ) : busy ? (
          <div className="pm__done">
            <p className="pm__done-sub pm__spinning">
              {p.isPending ? "Confirm in your wallet…" : "Reading the runes — your fren is materializing…"}
            </p>
          </div>
        ) : soldOut ? (
          <div className="pm__done">
            <p className="pm__done-title">Genesis is minted out</p>
            <p className="pm__done-sub">All {p.maxSupply.toLocaleString()} founding MiFrens are claimed. Ignite iteration&nbsp;#1 — <b style={{ color: "#f5f0e8" }}>GnomeLand</b> — to seed the eternal Cauldron.</p>
            {!p.finalized ? (
              <button className="pm__btn pm__btn--primary" disabled={p.finalizing} onClick={() => p.finalize().catch(() => {})}>
                {p.finalizing ? "Igniting…" : "Ignite the Cauldron"}
              </button>
            ) : (
              <a href="#/cauldrons" className="pm__btn pm__btn--primary" onClick={onClose}>Enter the Cauldron</a>
            )}
          </div>
        ) : (
          <>
            <div className="pm__meta">
              <span>{p.priceEth} Ξ each</span>
              {remaining != null && <span>{remaining.toLocaleString()} of {p.maxSupply.toLocaleString()} left</span>}
            </div>

            <div className="pm__qty">
              <button className="pm__step" onClick={() => setAmount((a) => Math.max(1, a - 1))} disabled={amount <= 1 || busy}>–</button>
              <span className="pm__qty-val">{amount}</span>
              <button className="pm__step" onClick={() => setAmount((a) => Math.min(maxMint, a + 1))} disabled={amount >= maxMint || busy}>+</button>
              <span className="pm__total">= {total} Ξ</span>
            </div>

            {!isConnected ? (
              <button className="pm__btn pm__btn--primary" onClick={() => openConnectModal?.()}>Connect Wallet</button>
            ) : (
              <button className="pm__btn pm__btn--primary" onClick={doMint} disabled={busy}>
                {p.isPending ? "Confirm in wallet…" : p.confirming ? "Minting…" : `Mint ${amount} · ${total} Ξ`}
              </button>
            )}
            <p className="pm__fine">Each MiFren is a genesis founder — a permanent share of every iteration's swap fees.</p>
          </>
        )}
      </div>
      <style>{css}</style>
    </div>,
    document.body,
  );
}

const css = `
  .pm__overlay { position: fixed; inset: 0; z-index: 10000; display: flex; align-items: center; justify-content: center;
    padding: 24px; overflow-y: auto; background: rgba(14,10,26,0.66); backdrop-filter: blur(16px); animation: pm-fade .25s ease; }
  @keyframes pm-fade { from { opacity: 0; } to { opacity: 1; } }
  .pm__modal { position: relative; width: 100%; max-width: 400px; border-radius: var(--r-md); padding: 30px 28px 26px;
    background: radial-gradient(140% 120% at 50% 0%, rgba(124,92,252,0.14), transparent 55%), linear-gradient(165deg, #221a45, #17112f);
    border: 1px solid rgba(213,253,81,0.2); box-shadow: 0 30px 90px rgba(0,0,0,0.6); text-align: center;
    animation: pm-pop .3s cubic-bezier(.2,.9,.3,1); }
  @keyframes pm-pop { from { opacity: 0; transform: translateY(14px) scale(.97); } to { opacity: 1; transform: none; } }
  .pm__close { position: absolute; top: 14px; right: 14px; width: 32px; height: 32px; display: grid; place-items: center;
    border-radius: var(--r-sm); cursor: pointer; color: #8f83b8; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.08); transition: all .18s; }
  .pm__close:hover:not(:disabled) { color: #f5f0e8; background: rgba(255,255,255,0.1); }
  .pm__eyebrow { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.2em; text-transform: uppercase; color: #7c5cfc; }
  .pm__title { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 27px; color: #f5f0e8; margin: 6px 0 18px; }
  .pm__art { position: relative; display: grid; place-items: center; margin-bottom: 18px; }
  .pm__art-inner { position: relative; width: 158px; border-radius: var(--r-md); overflow: hidden;
    border: 1px solid rgba(213,253,81,0.25); box-shadow: 0 10px 30px rgba(0,0,0,0.4); }
  .pm__art-brand { width: 132px; height: 132px; border-radius: var(--r-md); overflow: hidden;
    box-shadow: 0 0 40px rgba(74,144,226,0.45), 0 10px 30px rgba(0,0,0,0.5); animation: pm-pop .4s cubic-bezier(.2,1.3,.4,1); }
  .pm__art-brand img { width: 100%; height: 100%; object-fit: cover; display: block; }
  /* fast slot-machine cycle: motion blur + jitter while the tx is in flight */
  .pm__art--spin .pm__art-inner { animation: pm-jitter 0.09s steps(2) infinite; filter: blur(0.6px) saturate(1.1); border-color: rgba(213,253,81,0.5); box-shadow: 0 0 28px rgba(213,253,81,0.35); }
  @keyframes pm-jitter { 0% { transform: translateY(-1px) scale(1.01); } 100% { transform: translateY(1px) scale(0.99); } }
  /* reveal: pop + settle when the real fren lands */
  .pm__art--reveal .pm__art-inner { animation: pm-reveal 0.6s cubic-bezier(.2,1.3,.4,1); border-color: #d5fd51; box-shadow: 0 0 40px rgba(213,253,81,0.55); }
  @keyframes pm-reveal { 0% { transform: scale(0.5) rotate(-8deg); opacity: 0; } 60% { transform: scale(1.12) rotate(3deg); } 100% { transform: scale(1) rotate(0); opacity: 1; } }
  /* sweeping scan line while spinning */
  .pm__art-scan { position: absolute; inset: 0; pointer-events: none; border-radius: var(--r-md); overflow: hidden;
    background: linear-gradient(180deg, transparent 40%, rgba(213,253,81,0.25) 50%, transparent 60%); background-size: 100% 300%;
    animation: pm-scan 0.6s linear infinite; }
  @keyframes pm-scan { 0% { background-position: 0 -100%; } 100% { background-position: 0 200%; } }
  /* burst rings on reveal */
  .pm__art-burst { position: absolute; inset: -10px; pointer-events: none; border-radius: var(--r-md);
    box-shadow: 0 0 0 2px rgba(213,253,81,0.6); animation: pm-burst 0.7s ease-out forwards; }
  @keyframes pm-burst { 0% { transform: scale(0.7); opacity: 0.9; } 100% { transform: scale(1.4); opacity: 0; } }
  .pm__spinning { color: #d5fd51 !important; animation: pm-pulse 1.4s ease-in-out infinite; }
  @keyframes pm-pulse { 0%,100% { opacity: 0.55; } 50% { opacity: 1; } }
  .pm__reveal-name { display: flex; align-items: center; justify-content: center; gap: 10px; margin-bottom: 4px; }
  .pm__reveal-id { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 26px; color: #f5f0e8; }
  .pm__reveal-class { font: 700 10px/1 "DM Mono", monospace; letter-spacing: 0.08em; text-transform: uppercase; color: #17112f;
    background: linear-gradient(90deg, #d5fd51, #f5c542); padding: 5px 10px; border-radius: var(--r-md); }
  .pm__reveal-traits { font-size: 12px; color: #b8adcc; margin-bottom: 8px; }
  .pm__meta { display: flex; align-items: center; justify-content: space-between; font: 600 12px/1 "DM Mono", monospace; color: #b8adcc; margin-bottom: 14px; }
  .pm__qty { display: flex; align-items: center; justify-content: center; gap: 12px; margin-bottom: 18px; }
  .pm__step { width: 38px; height: 38px; border-radius: var(--r-sm); font-size: 20px; font-weight: 700; cursor: pointer;
    color: #f5f0e8; background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12); transition: all .15s; }
  .pm__step:hover:not(:disabled) { border-color: #d5fd51; color: #d5fd51; }
  .pm__step:disabled { opacity: 0.35; cursor: default; }
  .pm__qty-val { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 24px; color: #f5f0e8; min-width: 34px; }
  .pm__total { font-family: "DM Mono", monospace; font-size: 13px; color: #8f83b8; margin-left: 6px; }
  .pm__btn { display: block; width: 100%; padding: 15px; border-radius: var(--r-sm); cursor: pointer; text-decoration: none; text-align: center;
    font: 800 15px/1 "DM Sans", sans-serif; letter-spacing: 0.01em; border: none; transition: transform .15s, box-shadow .15s, opacity .2s; }
  .pm__btn--primary { color: #17112f; background: #d5fd51; box-shadow: 0 6px 0 #a9cc2f; }
  .pm__btn--primary:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 8px 0 #a9cc2f; }
  .pm__btn--ghost { color: #d5fd51; background: rgba(213,253,81,0.06); border: 1px solid rgba(213,253,81,0.32); box-shadow: none; }
  .pm__btn--ghost:hover { background: rgba(213,253,81,0.12); }
  .pm__btn:disabled { opacity: 0.6; cursor: default; box-shadow: 0 6px 0 #6f8420; }
  .pm__done-actions { display: flex; flex-direction: column; gap: 8px; width: 100%; }
  .pm__mintout { display: flex; flex-direction: column; align-items: center; gap: 6px; margin: 6px 0 10px; padding: 12px; border-radius: var(--r-sm); width: 100%;
    background: radial-gradient(120% 120% at 50% 0%, rgba(213,253,81,0.10), transparent 70%); border: 1px solid rgba(213,253,81,0.22); }
  .pm__fine { font-size: 11.5px; color: #8f83b8; line-height: 1.5; margin-top: 12px; }
  .pm__done { display: flex; flex-direction: column; align-items: center; gap: 8px; }
  .pm__done-check { font-size: 34px; color: #d5fd51; text-shadow: 0 0 20px rgba(213,253,81,0.5); }
  .pm__done-title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 19px; color: #f5f0e8; }
  .pm__done-sub { font-size: 13px; color: #b8adcc; line-height: 1.55; margin-bottom: 8px; }
  @media (prefers-reduced-motion: reduce) {
    .pm__art--spin .pm__art-inner, .pm__art--reveal .pm__art-inner, .pm__art-scan, .pm__art-burst, .pm__spinning { animation: none !important; filter: none !important; }
  }
`;
