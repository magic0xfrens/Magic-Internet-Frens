import toast from "react-hot-toast";
import { formatEther } from "viem";
import { useGenesisBonus } from "@/hooks/useGenesisBonus";

/**
 * GenesisClaimPanel — the OG airdrop for founding MiFren buyers. Every genesis
 * MiFren is owed a fixed share of iteration #1's token (per-tokenId, follows the
 * NFT on resale). Lives on the MiFrens page so buyers claim right beside their
 * frens. Self-hides when nothing is due.
 */
export default function GenesisClaimPanel() {
  const gb = useGenesisBonus();
  // Not a genesis holder → nothing to show. (Only hide when we actually know the
  // wallet holds no genesis frens, not merely while loading.)
  if (!gb.loading && gb.mifrenCount === 0 && gb.ownedGenesis.length === 0) return null;

  const fmtG = (b: bigint) => Number(formatEther(b)).toLocaleString(undefined, { maximumFractionDigits: 0 });
  const remaining = gb.unclaimedIds.length;
  const batch = Math.min(remaining, gb.claimBatch);
  const more = remaining > gb.claimBatch;
  const claimedCount = gb.ownedGenesis.length - remaining;

  // All frens claimed → show a clear "done" confirmation instead of vanishing,
  // so the holder knows they're finished (not that the panel failed to load).
  if (!gb.loading && gb.ownedGenesis.length > 0 && remaining === 0) {
    return (
      <div className="gcp gcp--done">
        <span className="gcp__spark" aria-hidden>✓</span>
        <div>
          <div className="gcp__title">Genesis airdrop claimed</div>
          <div className="gcp__sub">
            All {gb.ownedGenesis.length.toLocaleString()} of your founding MiFrens have claimed their
            {" "}<span className="gcp__mono">${gb.genesisTicker}</span>. Nothing left to claim.
          </div>
        </div>
        <style>{css}</style>
      </div>
    );
  }

  // Still loading and we don't yet know the split → show a light skeleton row.
  if (gb.loading && gb.unclaimedIds.length === 0) {
    return (
      <div className="gcp gcp--load">
        <span className="gcp__spark gcp__spark--spin" aria-hidden>✦</span>
        <div className="gcp__sub">Checking your genesis airdrop…</div>
        <style>{css}</style>
      </div>
    );
  }

  const onClaim = async () => {
    const t = toast.loading("Claiming your genesis airdrop…");
    try {
      await gb.claimAndMigrate();
      toast.success(
        gb.needsMigrate
          ? `Claimed $${gb.genesisTicker} → migrated to $${gb.currentTicker} ✓`
          : `Genesis $${gb.genesisTicker} claimed ✓`,
        { id: t },
      );
    } catch (e) {
      const msg = (e as { shortMessage?: string; message?: string })?.shortMessage
        ?? (e as Error)?.message ?? "Claim failed";
      toast.error(msg.length > 90 ? msg.slice(0, 90) + "…" : msg, { id: t });
    }
  };

  return (
    <div className="gcp">
      <div className="gcp__head">
        <span className="gcp__spark" aria-hidden>✦</span>
        <div>
          <div className="gcp__title">OG Genesis Airdrop</div>
          <div className="gcp__sub">
            Your founding MiFrens are owed iteration-1 <span className="gcp__mono">${gb.genesisTicker}</span> —
            {" "}{fmtG(gb.sharePerFren)} each, one claim per NFT.
            {gb.needsMigrate && <> Claimed tokens migrate 1:1 into the live <span className="gcp__mono">${gb.currentTicker}</span>.</>}
          </div>
        </div>
      </div>

      <div className="gcp__stats">
        <div className="gcp__stat"><span className="gcp__k">Claimed</span><span className="gcp__v">{claimedCount.toLocaleString()} / {gb.ownedGenesis.length.toLocaleString()}</span></div>
        <div className="gcp__stat"><span className="gcp__k">Unclaimed</span><span className="gcp__v">{remaining.toLocaleString()}</span></div>
        <div className="gcp__stat"><span className="gcp__k">Claimable</span><span className="gcp__v gcp__v--hl">{fmtG(gb.claimableGnome)} ${gb.genesisTicker}</span></div>
      </div>

      <div className="gcp__foot">
        <button className="gcp__btn" onClick={onClaim} disabled={gb.busy}>
          {gb.busy
            ? (gb.progress ? `Claiming ${gb.progress.done + 1}/${gb.progress.total}…` : "Claiming…")
            : `Claim ${more ? `${batch} of ${remaining}` : remaining}${gb.needsMigrate ? " + Migrate" : ""}`}
        </button>
        {more && <span className="gcp__note">claims run {gb.claimBatch} at a time — repeat for the rest</span>}
      </div>

      <style>{css}</style>
    </div>
  );
}

const css = `
  .gcp { margin: 0 0 22px; padding: 18px 20px; border-radius: 18px;
    background: radial-gradient(140% 130% at 0% 0%, rgba(245,197,66,0.12), transparent 55%), linear-gradient(160deg, #241b2e, #17112f);
    border: 1px solid rgba(245,197,66,0.3); box-shadow: 0 8px 30px rgba(12,10,26,0.28); }
  .gcp__head { display: flex; gap: 12px; align-items: flex-start; margin-bottom: 14px; }
  .gcp__spark { flex: 0 0 auto; width: 36px; height: 36px; display: grid; place-items: center; border-radius: 10px;
    font-size: 18px; color: #17112f; background: linear-gradient(90deg, #f5c542, #d5fd51); box-shadow: 0 0 18px rgba(245,197,66,0.45); }
  .gcp__title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 16px; color: #f5f0e8; }
  .gcp__sub { margin-top: 3px; font-family: "DM Sans", sans-serif; font-size: 12.5px; line-height: 1.5; color: #b8adcc; max-width: 62ch; }
  .gcp__mono { font-family: "DM Mono", monospace; color: #f5f0e8; }
  .gcp__stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 14px; }
  .gcp__stat { padding: 11px 13px; border-radius: 11px; display: flex; flex-direction: column; gap: 4px;
    background: rgba(14,10,26,0.5); border: 1px solid rgba(255,255,255,0.05); }
  .gcp__k { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.08em; text-transform: uppercase; color: #8f83b8; }
  .gcp__v { font-family: "DM Sans", sans-serif; font-weight: 800; font-size: 17px; color: #f5f0e8; }
  .gcp__v--hl { color: #f5c542; }
  .gcp__foot { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
  .gcp__btn { padding: 13px 24px; border-radius: 12px; cursor: pointer; border: none;
    font: 800 13.5px/1 "DM Sans", sans-serif; color: #17112f; background: linear-gradient(90deg, #f5c542, #d5fd51);
    box-shadow: 0 5px 0 #b8901f; transition: transform .15s, box-shadow .15s, opacity .2s; }
  .gcp__btn:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 7px 0 #b8901f; }
  .gcp__btn:disabled { opacity: 0.6; cursor: default; box-shadow: 0 5px 0 #7a5f14; }
  .gcp__note { font-family: "DM Mono", monospace; font-size: 11px; color: #8f83b8; }
  .gcp--done, .gcp--load { display: flex; align-items: center; gap: 13px; border-color: rgba(61,220,132,0.28);
    background: radial-gradient(140% 130% at 0% 0%, rgba(61,220,132,0.1), transparent 55%), linear-gradient(160deg, #1a2420, #17112f); }
  .gcp--done .gcp__spark { background: linear-gradient(90deg, #3ddc84, #d5fd51); box-shadow: 0 0 18px rgba(61,220,132,0.4); }
  .gcp--load { border-color: rgba(255,255,255,0.08); background: rgba(28,20,54,0.5); }
  .gcp--load .gcp__spark { background: rgba(255,255,255,0.06); box-shadow: none; }
  .gcp__spark--spin { animation: gcp-spin 1.1s linear infinite; }
  @keyframes gcp-spin { to { transform: rotate(360deg); } }
  @media (max-width: 620px) { .gcp__stats { grid-template-columns: 1fr; } }
`;
