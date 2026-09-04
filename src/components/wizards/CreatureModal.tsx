import { useCallback, useEffect, useState } from "react";
import { formatEther, type Address } from "viem";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { CAULDRON, COLLECTION_ABI, VAULT_ABI } from "@/config/cauldron";
import { nftTokenUrl, NETWORK_SHORT } from "@/config/chains";
import FrenSprite from "@/components/shared/FrenSprite";
import { frenFromSeed } from "@/data/frens";

const RARITY = ["Common", "Rare", "Epic", "Ultra", "Legendary"];
const RARITY_COL = ["#8f83b8", "#5ac8fa", "#c07cff", "#f5c542", "#d5fd51"];

const ipfs = (u?: string) => (u && u.startsWith("ipfs://") ? u.replace("ipfs://", "https://ipfs.io/ipfs/") : u);
async function resolveArt(uri: string): Promise<{ image?: string; name?: string }> {
  try {
    if (uri.startsWith("data:application/json;base64,")) { const j = JSON.parse(atob(uri.slice(29))); return { image: ipfs(j.image), name: j.name }; }
    if (uri.startsWith("data:application/json,")) { const j = JSON.parse(decodeURIComponent(uri.slice(22))); return { image: ipfs(j.image), name: j.name }; }
    if (uri.startsWith("http") || uri.startsWith("ipfs")) { const m = await fetch(ipfs(uri) as string, { signal: AbortSignal.timeout(6000) }).then((r) => r.json()); return { image: ipfs(m.image), name: m.name }; }
  } catch { /* ignore */ }
  return {};
}

export interface CreatureRef {
  collection: Address;
  tokenId: number;
  rarity: number;
  revealed: boolean;
  image?: string;
  name?: string;
}

interface Props {
  creature: CreatureRef;
  onClose: () => void;
  /** Called after a reveal/burn so the parent list can refresh. */
  onChanged?: () => void;
}

/**
 * CreatureModal — inspect one forged crystal/creature and act on it:
 *   • REVEAL a sealed crystal → cracks it open to the creature inside.
 *   • BURN for floor ETH → redeem the vault's equal share, burning the NFT.
 */
export default function CreatureModal({ creature, onClose, onChanged }: Props) {
  const { address } = useAccount();
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const { writeContractAsync } = useWriteContract();

  const [revealed, setRevealed] = useState(creature.revealed);
  const [image, setImage] = useState(creature.image);
  const [name, setName] = useState(creature.name);
  const [rarity, setRarity] = useState(creature.rarity);
  const [floorWei, setFloorWei] = useState<bigint>(0n);
  const [vaultClosed, setVaultClosed] = useState(false);
  const [busy, setBusy] = useState<null | "reveal" | "burn">(null);
  const [err, setErr] = useState("");
  const [done, setDone] = useState(false);

  const tid = BigInt(creature.tokenId);

  // Load the floor quote (vault) once.
  useEffect(() => {
    if (!pc) return;
    let alive = true;
    (async () => {
      try {
        const vault = await pc.readContract({ address: creature.collection, abi: COLLECTION_ABI, functionName: "vault" }) as Address;
        if (!vault || vault === "0x0000000000000000000000000000000000000000") return;
        const [floor, closed] = await Promise.all([
          pc.readContract({ address: vault, abi: VAULT_ABI, functionName: "floorPerNFT" }) as Promise<bigint>,
          pc.readContract({ address: vault, abi: VAULT_ABI, functionName: "closed" }).catch(() => false) as Promise<boolean>,
        ]);
        if (alive) { setFloorWei(floor); setVaultClosed(closed); }
      } catch { /* no vault */ }
    })();
    return () => { alive = false; };
  }, [pc, creature.collection]);

  const refreshArt = useCallback(async () => {
    if (!pc) return;
    try {
      const uri = await pc.readContract({ address: creature.collection, abi: COLLECTION_ABI, functionName: "tokenURI", args: [tid] }) as string;
      const art = await resolveArt(uri);
      setImage(art.image); setName(art.name);
      // rarityOf returns uint8, which viem decodes to a number - not a bigint.
      try { setRarity(Number(await pc.readContract({ address: creature.collection, abi: COLLECTION_ABI, functionName: "rarityOf", args: [tid] }) as number)); } catch { /* none */ }
    } catch { /* ignore */ }
  }, [pc, creature.collection, tid]);

  const doReveal = async () => {
    setErr(""); if (!pc) return;
    setBusy("reveal");
    try {
      const hash = await writeContractAsync({ address: creature.collection, abi: COLLECTION_ABI, functionName: "reveal", args: [tid] });
      const r = await pc.waitForTransactionReceipt({ hash, timeout: 90_000 });
      if (r.status === "reverted") throw new Error("Reveal reverted on-chain");
      setRevealed(true);
      await refreshArt();
      onChanged?.();
    } catch (e: unknown) {
      const m = e as { shortMessage?: string; message?: string };
      setErr(m?.shortMessage || m?.message || "Reveal failed");
    } finally { setBusy(null); }
  };

  const doBurn = async () => {
    setErr(""); if (!pc) return;
    setBusy("burn");
    try {
      const vault = await pc.readContract({ address: creature.collection, abi: COLLECTION_ABI, functionName: "vault" }) as Address;
      const hash = await writeContractAsync({ address: vault, abi: VAULT_ABI, functionName: "redeem", args: [tid] });
      const r = await pc.waitForTransactionReceipt({ hash, timeout: 90_000 });
      if (r.status === "reverted") throw new Error("Burn reverted — the vault may be closed (brew died).");
      setDone(true);
      onChanged?.();
    } catch (e: unknown) {
      const m = e as { shortMessage?: string; message?: string };
      setErr(m?.shortMessage || m?.message || "Burn failed");
    } finally { setBusy(null); }
  };

  const floorEth = Number(formatEther(floorWei));
  const rcol = RARITY_COL[rarity] ?? RARITY_COL[0];
  const osUrl = nftTokenUrl(creature.collection, creature.tokenId);

  return (
    <div className="cm-overlay" onClick={onClose}>
      <style>{css(rcol)}</style>
      <div className="cm" onClick={(e) => e.stopPropagation()}>
        <button className="cm-x" onClick={onClose} aria-label="Close">✕</button>

        {done ? (
          <div className="cm-done">
            <div className="cm-done-emoji">🔥</div>
            <h3>Burned for {floorEth.toFixed(5)} Ξ</h3>
            <p>Crystal #{creature.tokenId} redeemed its floor share. The ETH is in your wallet.</p>
            <button className="cm-btn cm-btn--ghost" onClick={onClose}>Close</button>
          </div>
        ) : (
          <>
            <div className="cm-art">
              {revealed && !image ? (
                // Renderer art missing → deterministic pixel fren from the tokenId.
                (() => { const f = frenFromSeed(creature.tokenId); return (
                  <FrenSprite bodyFile={f.bodyFile} faceFile={f.faceFile} itemFile={f.itemFile}
                    bodyIdx={f.bodyIdx} faceIdx={f.faceIdx} itemIdx={f.itemIdx} alt={name || `#${creature.tokenId}`} />
                ); })()
              ) : (
                <img src={revealed ? (image || "/crystal.png") : "/crystal.png"} alt={name || `#${creature.tokenId}`} />
              )}
              {!revealed && <span className="cm-sealed">SEALED</span>}
            </div>

            <div className="cm-body">
              <div className="cm-eyebrow" style={{ color: rcol }}>
                {revealed ? (RARITY[rarity] ?? "Common") : "Unrevealed crystal"}
              </div>
              <h3 className="cm-name">{revealed ? (name || `Creature #${creature.tokenId}`) : `Sealed Crystal #${creature.tokenId}`}</h3>
              <p className="cm-sub">
                {revealed
                  ? "This creature was forged from trading volume — fully on-chain art."
                  : "A crystal summoned from the brew. Open it to reveal the creature inside, or burn it for its floor share."}
              </p>

              {!revealed && (
                <button className="cm-btn cm-btn--reveal" onClick={doReveal} disabled={!!busy}>
                  {busy === "reveal" ? "Opening…" : "✦ Open crystal — reveal creature"}
                </button>
              )}

              <button className="cm-btn cm-btn--burn" onClick={doBurn} disabled={!!busy || vaultClosed || floorWei === 0n}>
                {busy === "burn" ? "Burning…"
                  : vaultClosed ? "Vault closed (brew died)"
                  : floorWei === 0n ? "No floor to redeem"
                  : `🔥 Burn for floor · ${floorEth.toFixed(5)} Ξ`}
              </button>

              <a className="cm-os" href={osUrl} target="_blank" rel="noopener">View on {NETWORK_SHORT === "Robinhood" ? "Explorer" : "OpenSea"} ↗</a>

              {err && <div className="cm-err">{err}</div>}
              <p className="cm-note">Burning is permanent — it destroys the NFT and pays out its equal share of the floor vault.</p>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

const css = (rcol: string) => `
  .cm-overlay { position: fixed; inset: 0; z-index: 200; display: grid; place-items: center; padding: 20px;
    background: rgba(8,6,15,0.78); backdrop-filter: blur(6px); animation: cm-fade 0.2s ease; }
  .cm { position: relative; width: 100%; max-width: 720px; display: grid; grid-template-columns: 1fr 1fr; gap: 0;
    background: linear-gradient(160deg, #1b1436, #120c22); border: 1px solid rgba(255,255,255,0.08);
    border-radius: var(--r-md); overflow: hidden; box-shadow: 0 30px 90px rgba(0,0,0,0.6); animation: cm-pop 0.25s cubic-bezier(.2,1.3,.4,1); }
  .cm-x { position: absolute; top: 12px; right: 12px; z-index: 3; width: 30px; height: 30px; border-radius: 50%;
    border: 1px solid rgba(255,255,255,0.1); background: rgba(8,6,15,0.6); color: #b8adcc; cursor: pointer; font-size: 13px; }
  .cm-x:hover { color: #f5f0e8; border-color: rgba(255,255,255,0.25); }
  .cm-art { position: relative; display: grid; place-items: center; padding: 24px; background: radial-gradient(120% 100% at 50% 30%, ${rcol}18, transparent 65%); }
  .cm-art img { width: 100%; max-width: 260px; aspect-ratio: 1; object-fit: contain; image-rendering: pixelated;
    border-radius: var(--r-sm); filter: drop-shadow(0 8px 30px rgba(0,0,0,0.5)); }
  .cm-sealed { position: absolute; top: 20px; left: 20px; font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.14em;
    color: #8f83b8; border: 1px solid rgba(255,255,255,0.12); border-radius: var(--r-chip); padding: 3px 9px; background: rgba(8,6,15,0.5); }
  .cm-body { padding: 26px 26px 22px; display: flex; flex-direction: column; }
  .cm-eyebrow { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.14em; text-transform: uppercase; }
  .cm-name { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 21px; color: #f5f0e8; margin: 5px 0 8px; }
  .cm-sub { font-family: "DM Sans", sans-serif; font-size: 12.5px; color: #b8adcc; line-height: 1.55; margin: 0 0 18px; }
  .cm-btn { width: 100%; padding: 12px; border-radius: var(--r-sm); font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 14px;
    cursor: pointer; border: 1px solid transparent; transition: all 0.15s; margin-bottom: 9px; }
  .cm-btn:disabled { opacity: 0.5; cursor: default; }
  .cm-btn--reveal { background: ${rcol}1c; border-color: ${rcol}; color: ${rcol}; }
  .cm-btn--reveal:hover:not(:disabled) { background: ${rcol}33; box-shadow: 0 0 22px ${rcol}44; }
  .cm-btn--burn { background: rgba(255,77,109,0.12); border-color: #ff4d6d; color: #ff4d6d; }
  .cm-btn--burn:hover:not(:disabled) { background: rgba(255,77,109,0.24); }
  .cm-btn--ghost { background: rgba(255,255,255,0.05); border-color: rgba(255,255,255,0.12); color: #f5f0e8; }
  .cm-os { display: block; text-align: center; font-family: "DM Mono", monospace; font-size: 11px; color: #2081e2; text-decoration: none; margin: 4px 0 2px; }
  .cm-os:hover { color: #4a9ff5; }
  .cm-err { margin-top: 8px; font-family: "DM Sans", sans-serif; font-size: 11px; color: #ff4d6d; text-align: center; line-height: 1.4; }
  .cm-note { font-family: "DM Mono", monospace; font-size: 8.5px; color: #8f83b8; opacity: 0.65; margin-top: auto; padding-top: 12px; line-height: 1.5; text-align: center; }
  .cm-done { grid-column: 1 / -1; padding: 44px 30px; text-align: center; }
  .cm-done-emoji { font-size: 44px; margin-bottom: 8px; }
  .cm-done h3 { font-family: "Cinzel Decorative", serif; color: #d5fd51; font-size: 22px; margin: 0 0 8px; }
  .cm-done p { font-family: "DM Sans", sans-serif; color: #b8adcc; font-size: 13px; margin: 0 auto 20px; max-width: 340px; line-height: 1.5; }
  @media (max-width: 560px) { .cm { grid-template-columns: 1fr; max-width: 380px; } }
  @keyframes cm-fade { from { opacity: 0; } to { opacity: 1; } }
  @keyframes cm-pop { from { opacity: 0; transform: scale(0.94) translateY(10px); } to { opacity: 1; transform: none; } }
`;
