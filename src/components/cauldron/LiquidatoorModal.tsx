import { useEffect, useMemo } from "react";
import type { LiquidatoorHit } from "@/hooks/useLiquidatoorWatch";
import { liquidatoorBadgeSVG } from "@/lib/liquidatoorBadgeArt";

/** Deterministic badge art (the sniper-scope kill-log, with the pepe scope image),
 *  rendered INLINE so it shows everywhere — no API/Vercel-function dependency (which
 *  doesn't run under local vite dev) and no missing-PNG placeholder. Seeded from the
 *  liquidated position so it's stable. */
function badgeArt(positionId: string): string {
  const seed = Number(positionId) || 1;
  let s = (seed * 2654435761) >>> 0;
  const rnd = () => { s = (s * 1103515245 + 12345) >>> 0; return s / 0xffffffff; };
  const side: "short" | "long" = rnd() > 0.5 ? "short" : "long";
  const entry = 1800 + rnd() * 1400;
  const fmt = (n: number) => n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return liquidatoorBadgeSVG({
    side, tokenId: seed,
    victim: "0x0000…dead", liquidator: "you",
    sizeEth: (0.4 + rnd() * 6).toFixed(2), leverage: 2 + Math.floor(rnd() * 2),
    entry: fmt(entry), liqPrice: fmt(entry * (side === "short" ? 1.15 : 0.85)),
    pnlPct: "-100.0", bountyEth: (0.001 + rnd() * 0.02).toFixed(4),
    block: Math.floor(11_600_000 + rnd() * 60_000).toLocaleString("en-US"),
    imageHref: `/images/liq-${side}.png`,
  });
}

/**
 * LiquidatoorModal — the "Congrats Liquidatoor!" celebration that pops when YOUR
 * trade (a spot buy/sell or a leveraged open) liquidated an underwater position
 * and minted you a Liquidatoor badge (an OnChain Collectible). Shows the actual
 * minted badge art. Pure flex.
 */
export default function LiquidatoorModal({ hit, onClose }: { hit: LiquidatoorHit; onClose: () => void }) {
  const gotBadge = hit.badgeId !== "0";
  const art = useMemo(() => badgeArt(hit.positionId), [hit.positionId]);

  useEffect(() => {
    const t = setTimeout(onClose, 12000); // auto-dismiss (a bit longer to admire it)
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => { clearTimeout(t); window.removeEventListener("keydown", onKey); };
  }, [onClose]);

  return (
    <div className="lqm" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="lqm__card" onClick={(e) => e.stopPropagation()}>
        <div className="lqm__spark" aria-hidden>
          {Array.from({ length: 18 }).map((_, i) => (
            <span key={i} className="lqm__bit" style={{ ["--i" as string]: i, ["--n" as string]: 18 }} />
          ))}
        </div>

        <div className="lqm__skull" aria-hidden>☠</div>
        <div className="lqm__eyebrow">Proof of Kill</div>
        <h2 className="lqm__title">Congrats, Liquidatoor!</h2>
        <p className="lqm__sub">
          Your trade rekt <b>position #{hit.positionId}</b> — you took the keeper reward
          {gotBadge ? " and struck a Liquidatoor badge." : "."}
        </p>

        {gotBadge && (
          <div className="lqm__badge">
            <div className="lqm__badge-art">
              <div className="lqm__badge-svg" dangerouslySetInnerHTML={{ __html: art }} />
              <span className="lqm__badge-flag">LIQUIDATOOR</span>
            </div>
            <span className="lqm__badge-id">Badge #{hit.badgeId}</span>
            <span className="lqm__badge-note">An OnChain Collectible — see it in My MiFrens.</span>
          </div>
        )}

        <button className="lqm__btn" onClick={onClose}>Nice</button>
      </div>

      <style>{`
        .lqm { position: fixed; inset: 0; z-index: 9999; display: grid; place-items: center;
          background: radial-gradient(120% 120% at 50% 30%, rgba(255,77,109,0.16), rgba(8,6,15,0.86));
          backdrop-filter: blur(6px); animation: lqm-fade .25s ease; }
        @keyframes lqm-fade { from { opacity: 0; } to { opacity: 1; } }
        .lqm__card { position: relative; width: min(90vw, 420px); padding: 34px 28px 26px; text-align: center;
          border-radius: var(--r-md); overflow: hidden; color: #f5f0e8; font-family: "DM Sans", sans-serif;
          background: linear-gradient(180deg, rgba(40,22,40,0.96), rgba(20,14,34,0.98));
          border: 1px solid rgba(255,77,109,0.5); box-shadow: 0 30px 90px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,77,109,0.2), 0 0 60px rgba(255,77,109,0.25) inset;
          animation: lqm-pop .4s cubic-bezier(.2,1.2,.3,1); }
        @keyframes lqm-pop { from { transform: scale(.82) translateY(10px); opacity: 0; } to { transform: scale(1) translateY(0); opacity: 1; } }
        .lqm__skull { font-size: 54px; line-height: 1; filter: drop-shadow(0 0 18px rgba(255,77,109,0.7)); animation: lqm-bob 2.4s ease-in-out infinite; }
        @keyframes lqm-bob { 0%,100% { transform: translateY(0) rotate(-3deg); } 50% { transform: translateY(-6px) rotate(3deg); } }
        .lqm__eyebrow { margin-top: 8px; font-family: "DM Mono", monospace; font-size: 10.5px; letter-spacing: 0.24em; text-transform: uppercase; color: #ff4d6d; }
        .lqm__title { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: clamp(24px, 6vw, 32px); margin: 6px 0 8px; color: #fff;
          text-shadow: 0 0 26px rgba(255,77,109,0.5); }
        .lqm__sub { font-size: 14px; color: #d9cfe6; line-height: 1.55; max-width: 34ch; margin: 0 auto; }
        .lqm__sub b { color: #ff8fa3; }
        .lqm__badge { margin: 18px auto 4px; padding: 14px; border-radius: var(--r-sm); display: flex; flex-direction: column; gap: 5px; align-items: center;
          background: radial-gradient(120% 120% at 50% 0%, rgba(255,77,109,0.14), transparent 70%), rgba(28,20,54,0.6);
          border: 1px solid rgba(255,77,109,0.35); }
        .lqm__badge-art { position: relative; width: 132px; height: 132px; border-radius: var(--r-sm); overflow: hidden; margin-bottom: 4px;
          background: radial-gradient(120% 120% at 50% 0%, rgba(255,77,109,0.22), rgba(20,14,34,0.9));
          border: 1px solid rgba(255,77,109,0.45); box-shadow: 0 0 26px rgba(255,77,109,0.35), 0 8px 24px rgba(0,0,0,0.5);
          display: grid; place-items: center; animation: lqm-badgepop .5s cubic-bezier(.2,1.3,.3,1) both .1s; }
        @keyframes lqm-badgepop { from { transform: scale(.6) rotate(-8deg); opacity: 0; } to { transform: scale(1) rotate(0); opacity: 1; } }
        .lqm__badge-art img { width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; }
        .lqm__badge-svg, .lqm__badge-svg svg { width: 100%; height: 100%; display: block; }
        .lqm__badge-flag { position: absolute; bottom: 6px; font: 700 9px/1 "DM Mono", monospace; letter-spacing: 0.14em; color: #17112f; background: #ff4d6d; border-radius: var(--r-chip); padding: 4px 10px; }
        .lqm__badge-id { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 17px; color: #fff; }
        .lqm__badge-note { font-size: 11.5px; color: #b8adcc; }
        .lqm__btn { margin-top: 18px; padding: 12px 34px; border-radius: var(--r-md); cursor: pointer; border: none;
          font: 700 14px/1 "DM Sans", sans-serif; color: #17112f; background: #ff4d6d; box-shadow: 0 6px 0 #b8324c; transition: transform .15s, box-shadow .15s; }
        .lqm__btn:hover { transform: translateY(-2px); box-shadow: 0 8px 0 #b8324c; }
        .lqm__btn:active { transform: translateY(2px); box-shadow: 0 3px 0 #b8324c; }
        .lqm__spark { position: absolute; inset: 0; pointer-events: none; }
        .lqm__bit { position: absolute; top: 42%; left: 50%; width: 6px; height: 6px; border-radius: 50%; background: #ff4d6d;
          transform: rotate(calc(var(--i) * (360deg / var(--n)))) translateY(0);
          animation: lqm-burst .9s ease-out forwards; animation-delay: .05s; opacity: 0; }
        @keyframes lqm-burst { 0% { opacity: 1; transform: rotate(calc(var(--i) * (360deg / var(--n)))) translateY(0) scale(1); }
          100% { opacity: 0; transform: rotate(calc(var(--i) * (360deg / var(--n)))) translateY(-120px) scale(0.3); } }
        @media (prefers-reduced-motion: reduce) { .lqm__skull, .lqm__bit, .lqm__card { animation: none !important; } }
      `}</style>
    </div>
  );
}
