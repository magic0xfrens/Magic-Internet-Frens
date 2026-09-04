import { useState } from "react";
import { formatEther } from "viem";
import toast from "react-hot-toast";
import { useCollectionFloor } from "@/hooks/useCollectionFloor";
import { useCandles } from "@/hooks/useCandles";
import { useEthUsd } from "@/hooks/useEthUsd";

/** USD from a wei token amount × USD-per-token. "" when we have no price yet. */
function usdOf(wei: bigint, priceUsd: number): string {
  if (!(priceUsd > 0) || wei <= 0n) return "";
  const v = Number(formatEther(wei)) * priceUsd;
  if (!(v > 0)) return "";
  return v < 0.01 ? `≈ $${v.toPrecision(2)}` : `≈ $${v.toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
}

/**
 * CollectionFloorPanel — the COLLECTION LEGACY FLOOR (r28). Leads with the
 * per-NFT floor (what one NFT is redeemable for right now), backed by the pool
 * total and a progress bar to the next in-hook buyback, then any past (dead)
 * collection's floor with recycle / buy-from-treasury actions. Self-hides
 * pre-summon and sources its own USD price, so it can render anywhere.
 *
 * Renders on /mi-frens (the vault's "Floors" view) — it used to sit on the
 * Cauldron ABOVE the tab switch, which meant it appeared on three unrelated
 * views, and its actions are about NFTs you hold rather than the brew.
 */
export default function CollectionFloorPanel() {
  const cf = useCollectionFloor();
  // Sources its own USD price (last indexed trade x ETH/USD) so the panel can
  // live anywhere — it moved off the Cauldron, which used to hand it down.
  const { last } = useCandles(cf.currentGen, cf.currentGen > 0);
  const ethUsd = useEthUsd();
  const priceUsd = last > 0 && ethUsd > 0 ? last * ethUsd : 0;
  const [genInput, setGenInput] = useState("");
  const [idInput, setIdInput] = useState("");

  if (!cf.loading && cf.currentGen === 0) return null;
  const ticker = cf.ticker || "the live token";
  const liveUsd = usdOf(cf.livePending, priceUsd);
  const perNftUsd = usdOf(cf.liveFloorPerNFT, priceUsd);
  const redeemable = cf.liveFloorPerNFT > 0n;

  const onRecycle = async () => {
    const gen = Number(genInput), id = idInput.trim();
    if (!gen || !id) return toast.error("Enter a generation + tokenId");
    const t = toast.loading(`Recycling #${id}…`);
    try {
      await cf.recycle(gen, BigInt(id));
      toast.success(`Recycled #${id} → received $${cf.ticker} ✓`, { id: t });
      setIdInput("");
    } catch (e) {
      toast.error(short((e as Error)?.message ?? "Recycle failed"), { id: t });
    }
  };

  const onBuy = async () => {
    const gen = Number(genInput), id = idInput.trim();
    if (!gen || !id) return toast.error("Enter a generation + tokenId");
    const t = toast.loading(`Buying #${id} @ 2× floor…`);
    try {
      await cf.buyTreasury(gen, BigInt(id));
      toast.success(`Bought #${id} — floor ratcheted up ✓`, { id: t });
      setIdInput("");
    } catch (e) {
      toast.error(short((e as Error)?.message ?? "Buy failed"), { id: t });
    }
  };

  return (
    <div className="cfp">
      <div className="cfp__head">
        <span className="cfp__spark" aria-hidden>◆</span>
        <div>
          <div className="cfp__title">Collection Legacy Floor</div>
          <div className="cfp__sub">
            Every collection keeps the value its <b>own volume + royalties</b> earn — forever. Trading fees
            market-buy <span className="cfp__mono">${ticker}</span> to back the live collection's floor; at death
            it <b>crystallizes</b> into a per-NFT floor that <b>moons with the machine</b>.
          </div>
        </div>
      </div>

      {/* LIVE collection. The HERO number is the per-NFT floor — what one NFT is
          actually worth. The pooled total is context for it, not the headline:
          "579,832 $GNOME" told a holder nothing about their own position. */}
      <div className="cfp__live">
        {redeemable ? (
          <>
            <div className="cfp__hero">
              <span className="cfp__k">Floor per NFT · redeemable now</span>
              <span className="cfp__hero-v">
                {cf.fmt(cf.liveFloorPerNFT)} <em>${ticker}</em>
                {perNftUsd && <span className="cfp__hero-usd">{perNftUsd}</span>}
              </span>
            </div>
            <div className="cfp__backed">
              backed by {cf.fmt(cf.livePending)} ${ticker}
              {liveUsd && <span className="cfp__usd">{liveUsd}</span>}
              {cf.liveOutstanding > 0 && <> across {cf.liveOutstanding.toLocaleString()} NFTs</>}
            </div>
          </>
        ) : (
          /* Nothing redeemable yet — the first buyback has not landed, so the
             pool total IS the story until there is a per-NFT number to show. */
          <div className="cfp__hero">
            <span className="cfp__k">Floor building</span>
            <span className="cfp__hero-v">
              {cf.fmt(cf.livePending)} <em>${ticker}</em>
              {liveUsd && <span className="cfp__hero-usd">{liveUsd}</span>}
            </span>
          </div>
        )}
        <div className="cfp__bar" title={`${cf.bufferPct.toFixed(0)}% to the next buyback`}>
          <div className="cfp__barfill" style={{ width: `${cf.bufferPct}%` }} />
        </div>
        <div className="cfp__barlabel">
          {cf.bufferPct.toFixed(0)}% to the next auto-buyback · {cf.legacyBps / 100}% of every fee funds the floor
        </div>
      </div>

      {/* PAST collections — redeemable floors */}
      {cf.past.length > 0 && (
        <div className="cfp__past">
          <div className="cfp__pasthead">Past collections — redeemable floors</div>
          {cf.past.map((p) => (
            <div key={p.gen} className="cfp__pastrow">
              <span className="cfp__mono">Iteration #{p.gen}</span>
              <span className="cfp__k">{p.outstanding.toLocaleString()} left</span>
              <span className="cfp__v">{cf.fmt(p.floorPerNFT)} ${ticker}/NFT ↑{usdOf(p.floorPerNFT, priceUsd) && <span className="cfp__usd">{usdOf(p.floorPerNFT, priceUsd)}</span>}</span>
            </div>
          ))}
          <div className="cfp__actions">
            <input className="cfp__in" placeholder="gen" value={genInput} onChange={(e) => setGenInput(e.target.value)} inputMode="numeric" />
            <input className="cfp__in cfp__in--wide" placeholder="tokenId" value={idInput} onChange={(e) => setIdInput(e.target.value)} inputMode="numeric" />
            <button className="cfp__btn" onClick={onRecycle} disabled={cf.busy}>Recycle</button>
            <button className="cfp__btn cfp__btn--ghost" onClick={onBuy} disabled={cf.busy}>Buy @2×</button>
          </div>
          <div className="cfp__note">Recycle burns your claim to the floor (NFT → treasury); anyone can buy it back for 2× — which raises the floor for every remaining holder.</div>
        </div>
      )}

      <style>{css}</style>
    </div>
  );
}

function short(m: string) { return m.length > 90 ? m.slice(0, 90) + "…" : m; }

const css = `
  .cfp { margin: 0 0 22px; padding: 18px 20px; border-radius: var(--r-md);
    background: radial-gradient(140% 130% at 100% 0%, rgba(213,253,81,0.10), transparent 55%), linear-gradient(160deg, #1b1630, #14102a);
    border: 1px solid rgba(213,253,81,0.22); box-shadow: 0 8px 30px rgba(12,10,26,0.3); }
  .cfp__head { display: flex; gap: 12px; align-items: flex-start; margin-bottom: 14px; }
  .cfp__spark { flex: 0 0 auto; width: 36px; height: 36px; display: grid; place-items: center; border-radius: var(--r-sm);
    font-size: 16px; color: #14102a; background: linear-gradient(90deg, #d5fd51, #8fe36a); box-shadow: 0 0 18px rgba(213,253,81,0.4); }
  .cfp__title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 16px; color: #f5f0e8; }
  .cfp__sub { margin-top: 3px; font-family: "DM Sans", sans-serif; font-size: 12.5px; line-height: 1.5; color: #b8adcc; max-width: 64ch; }
  .cfp__mono { font-family: "DM Mono", monospace; color: #f5f0e8; }
  .cfp__live { padding: 13px 14px; border-radius: var(--r-sm); background: rgba(14,10,26,0.5); border: 1px solid rgba(255,255,255,0.05); }
  .cfp__liverow { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 9px; }
  /* The per-NFT floor is the headline, so it gets headline weight. */
  .cfp__hero { display: flex; flex-direction: column; gap: 4px; margin-bottom: 10px; }
  .cfp__hero-v { font-family: "DM Sans", sans-serif; font-weight: 700; font-size: 26px; line-height: 1.05; color: #d5fd51; }
  .cfp__hero-v em { font-style: normal; font-weight: 500; font-size: 15px; color: #b8adcc; }
  .cfp__hero-usd { margin-left: 9px; font-family: "DM Mono", monospace; font-weight: 500; font-size: 12px; color: #8f83b8; }
  .cfp__backed { margin-bottom: 10px; font-family: "DM Sans", sans-serif; font-size: 11.5px; color: #8f83b8; }
  .cfp__backed .cfp__usd { margin-left: 5px; }
  .cfp__k { font-family: "DM Mono", monospace; font-size: 10.5px; letter-spacing: 0.06em; text-transform: uppercase; color: #8f83b8; }
  .cfp__v { font-family: "DM Sans", sans-serif; font-weight: 800; font-size: 15px; color: #f5f0e8; }
  .cfp__v--hl { color: #d5fd51; }
  .cfp__usd { margin-left: 7px; font-family: "DM Mono", monospace; font-weight: 500; font-size: 11px; color: #8f83b8; }
  .cfp__redeem { display: flex; justify-content: space-between; align-items: baseline; margin-top: 10px; padding-top: 10px; border-top: 1px dashed rgba(213,253,81,0.18); }
  .cfp__bar { height: 8px; border-radius: var(--r-chip); background: rgba(255,255,255,0.06); overflow: hidden; }
  .cfp__barfill { height: 100%; border-radius: var(--r-chip); background: linear-gradient(90deg, #d5fd51, #8fe36a); transition: width .4s ease; }
  .cfp__barlabel { margin-top: 7px; font-family: "DM Mono", monospace; font-size: 10.5px; color: #8f83b8; }
  .cfp__past { margin-top: 14px; }
  .cfp__pasthead { font-family: "DM Mono", monospace; font-size: 10.5px; letter-spacing: 0.06em; text-transform: uppercase; color: #8f83b8; margin-bottom: 8px; }
  .cfp__pastrow { display: grid; grid-template-columns: 1fr auto auto; gap: 10px; align-items: baseline; padding: 8px 0; border-top: 1px solid rgba(255,255,255,0.05); }
  .cfp__actions { display: flex; gap: 8px; margin-top: 12px; flex-wrap: wrap; }
  .cfp__in { width: 68px; padding: 9px 10px; border-radius: var(--r-sm); border: 1px solid rgba(255,255,255,0.1);
    background: rgba(14,10,26,0.6); color: #f5f0e8; font: 600 12px "DM Mono", monospace; }
  .cfp__in--wide { width: 110px; }
  .cfp__btn { padding: 9px 16px; border-radius: var(--r-sm); cursor: pointer; border: none;
    font: 800 12px "DM Sans", sans-serif; color: #14102a; background: linear-gradient(90deg, #d5fd51, #8fe36a); }
  .cfp__btn--ghost { background: transparent; color: #d5fd51; border: 1px solid rgba(213,253,81,0.4); }
  .cfp__btn:disabled { opacity: 0.5; cursor: default; }
  .cfp__note { margin-top: 9px; font-family: "DM Sans", sans-serif; font-size: 11px; color: #8f83b8; line-height: 1.5; }
  @media (max-width: 620px) { .cfp__pastrow { grid-template-columns: 1fr; gap: 3px; } }
`;
