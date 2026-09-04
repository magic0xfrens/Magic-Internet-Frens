import toast from "react-hot-toast";
import { formatEther } from "viem";
import { useGenesisBonus } from "@/hooks/useGenesisBonus";

/**
 * GenesisRedeemPanel — the GENESIS REDEMPTION FLOOR. A genesis MiFren is a
 * perpetual redemption ticket for the eternal machine: BURN it to receive a fixed
 * share of WHATEVER token is live right now, released from the reserve. The NFT's
 * floor therefore tracks the live iteration's marketcap. One-way and non-dilutive
 * — the tokens were never circulating and the fren is destroyed. Lives on the
 * MiFrens page beside the collection. Self-hides for non-holders.
 */
export default function GenesisClaimPanel() {
  const gb = useGenesisBonus();
  // Not a genesis holder → nothing to redeem.
  if (!gb.loading && gb.mifrenCount === 0 && gb.ownedGenesis.length === 0) return null;

  const fmtG = (b: bigint) => Number(formatEther(b)).toLocaleString(undefined, { maximumFractionDigits: 0 });
  const redeemable = gb.unclaimedIds.length; // every owned genesis fren is redeemable
  const batch = Math.min(redeemable, gb.claimBatch);
  const more = redeemable > gb.claimBatch;
  const ticker = gb.currentTicker || "the live token";

  // Still loading and we don't yet know the frens → light skeleton row.
  if (gb.loading && gb.ownedGenesis.length === 0) {
    return (
      <div className="gcp gcp--load">
        <span className="gcp__spark gcp__spark--spin" aria-hidden>✦</span>
        <div className="gcp__sub">Reading your genesis redemption floor…</div>
        <style>{css}</style>
      </div>
    );
  }

  const onRedeem = async () => {
    if (redeemable === 0) return;
    const ok = window.confirm(
      `Recycle ${batch} genesis fren${batch > 1 ? "s" : ""} for ${fmtG(gb.sharePerFren * BigInt(batch))} $${gb.currentTicker}?\n\n` +
      `The NFT${batch > 1 ? "s move" : " moves"} to the treasury (NOT burned) to be resold at 2× floor, and you ` +
      `receive the live token now. You give up ${batch > 1 ? "their" : "its"} vote + dividend when ${batch > 1 ? "they" : "it"} ` +
      `leave${batch > 1 ? "" : "s"} your wallet.`,
    );
    if (!ok) return;
    const t = toast.loading(`Recycling ${batch} fren${batch > 1 ? "s" : ""}…`);
    try {
      await gb.claimAndMigrate(); // recycles via redeemFren (NFT → treasury)
      toast.success(`Recycled ${batch} fren${batch > 1 ? "s" : ""} → received $${gb.currentTicker} ✓`, { id: t });
    } catch (e) {
      const msg = (e as { shortMessage?: string; message?: string })?.shortMessage
        ?? (e as Error)?.message ?? "Recycle failed";
      toast.error(msg.length > 90 ? msg.slice(0, 90) + "…" : msg, { id: t });
    }
  };

  return (
    <div className="gcp">
      <div className="gcp__head">
        <span className="gcp__spark" aria-hidden>✦</span>
        <div>
          <div className="gcp__title">Genesis Redemption Floor</div>
          <div className="gcp__sub">
            Each genesis MiFren can be recycled for <span className="gcp__mono">{fmtG(gb.sharePerFren)} ${ticker}</span>
            {" "}from the reserve — the NFT goes to the treasury (not burned) to be resold at 2× floor.
            The floor <strong className="gcp__warn">RATCHETS UP</strong>: buybacks + re-enchant fees grow the
            reserve, so it only rises over time and tracks <span className="gcp__mono">${ticker}</span>'s marketcap.
          </div>
        </div>
      </div>

      <div className="gcp__stats">
        <div className="gcp__stat"><span className="gcp__k">Your Frens</span><span className="gcp__v">{gb.ownedGenesis.length.toLocaleString()}</span></div>
        <div className="gcp__stat"><span className="gcp__k">Per Fren</span><span className="gcp__v">{fmtG(gb.sharePerFren)} ${ticker}</span></div>
        <div className="gcp__stat"><span className="gcp__k">Total Redeemable</span><span className="gcp__v gcp__v--hl">{fmtG(gb.claimableGnome)} ${ticker}</span></div>
      </div>

      <div className="gcp__foot">
        <button className="gcp__btn" onClick={onRedeem} disabled={gb.busy || redeemable === 0}>
          {gb.busy
            ? (gb.progress ? `Recycling ${gb.progress.done + 1}/${gb.progress.total}…` : "Recycling…")
            : `Recycle & Redeem ${more ? `${batch} of ${redeemable}` : redeemable}`}
        </button>
        {more && <span className="gcp__note">redeems {gb.claimBatch} at a time — repeat for the rest</span>}
      </div>

      <style>{css}</style>
    </div>
  );
}

const css = `
  .gcp { margin: 0 0 22px; padding: 18px 20px; border-radius: var(--r-md);
    background: radial-gradient(140% 130% at 0% 0%, rgba(245,197,66,0.12), transparent 55%), linear-gradient(160deg, #241b2e, #17112f);
    border: 1px solid rgba(245,197,66,0.3); box-shadow: 0 8px 30px rgba(12,10,26,0.28); }
  .gcp__head { display: flex; gap: 12px; align-items: flex-start; margin-bottom: 14px; }
  .gcp__spark { flex: 0 0 auto; width: 36px; height: 36px; display: grid; place-items: center; border-radius: var(--r-sm);
    font-size: 18px; color: #17112f; background: linear-gradient(90deg, #f5c542, #d5fd51); box-shadow: 0 0 18px rgba(245,197,66,0.45); }
  .gcp__title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 16px; color: #f5f0e8; }
  .gcp__sub { margin-top: 3px; font-family: "DM Sans", sans-serif; font-size: 12.5px; line-height: 1.5; color: #b8adcc; max-width: 62ch; }
  .gcp__mono { font-family: "DM Mono", monospace; color: #f5f0e8; }
  .gcp__warn { color: #f5c542; font-weight: 700; }
  .gcp__stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 14px; }
  .gcp__stat { padding: 11px 13px; border-radius: var(--r-sm); display: flex; flex-direction: column; gap: 4px;
    background: rgba(14,10,26,0.5); border: 1px solid rgba(255,255,255,0.05); }
  .gcp__k { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.08em; text-transform: uppercase; color: #8f83b8; }
  .gcp__v { font-family: "DM Sans", sans-serif; font-weight: 800; font-size: 17px; color: #f5f0e8; }
  .gcp__v--hl { color: #f5c542; }
  .gcp__foot { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
  .gcp__btn { padding: 13px 24px; border-radius: var(--r-sm); cursor: pointer; border: none;
    font: 800 13.5px/1 "DM Sans", sans-serif; color: #17112f; background: linear-gradient(90deg, #f5c542, #d5fd51);
    box-shadow: 0 5px 0 #b8901f; transition: transform .15s, box-shadow .15s, opacity .2s; }
  .gcp__btn:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 7px 0 #b8901f; }
  .gcp__btn:disabled { opacity: 0.6; cursor: default; box-shadow: 0 5px 0 #7a5f14; }
  .gcp__note { font-family: "DM Mono", monospace; font-size: 11px; color: #8f83b8; }
  .gcp--load { display: flex; align-items: center; gap: 13px; border-color: rgba(255,255,255,0.08); background: rgba(28,20,54,0.5); }
  .gcp--load .gcp__spark { background: rgba(255,255,255,0.06); box-shadow: none; }
  .gcp__spark--spin { animation: gcp-spin 1.1s linear infinite; }
  @keyframes gcp-spin { to { transform: rotate(360deg); } }
  @media (max-width: 620px) { .gcp__stats { grid-template-columns: 1fr; } }
`;
