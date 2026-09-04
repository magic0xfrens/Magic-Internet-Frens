import { useEffect, useRef, useState, useCallback, type CSSProperties } from "react";
import { createPortal } from "react-dom";
import { isAddress, formatUnits } from "viem";
import { usePublicClient, useWriteContract } from "wagmi";
import toast from "react-hot-toast";
import type { OwnedNFT } from "@/hooks/useUserNFTs";
import { resolveTraits } from "@/data/traitResolver";
import FrenSprite from "@/components/shared/FrenSprite";
import { CLASS_COLORS, type FrenClass, isGenesisFren } from "@/data/frens";
import { useWallet } from "@/hooks/useWallet";
import { useCollectionFloor } from "@/hooks/useCollectionFloor";
import { CAULDRON } from "@/config/cauldron";

// Minimal ERC-721 transfer ABI (the genesis MiFrens are a standard ERC-721).
const ERC721_TRANSFER_ABI = [
  { type: "function", name: "safeTransferFrom", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "address" }, { type: "uint256" }], outputs: [] },
] as const;

// Registry: the live OG redemption floor + the single-fren recycle.
const REGISTRY_FLOOR_ABI = [
  { type: "function", name: "floorPerFren", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "currentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "redeemOgFren", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
] as const;

const fmtAmt = (n: number) =>
  n >= 1e6 ? `${(n / 1e6).toFixed(2)}M` : n >= 1e3 ? `${(n / 1e3).toFixed(1)}K` : n.toLocaleString("en-US", { maximumFractionDigits: 0 });

interface FrenDetailModalProps {
  nft: OwnedNFT | null;
  onClose: () => void;
  onListForSale?: (tokenId: bigint) => void;
}

export default function FrenDetailModal({ nft, onClose, onListForSale }: FrenDetailModalProps) {
  const { walletAddress } = useWallet();
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const { writeContractAsync } = useWriteContract();
  const modalRef = useRef<HTMLDivElement>(null);

  const [transferAddr, setTransferAddr] = useState("");
  const [transferring, setTransferring] = useState(false);
  const [showTransferInput, setShowTransferInput] = useState(false);
  const [recycling, setRecycling] = useState(false);
  const [floor, setFloor] = useState<{ gnome: number; ticker: string } | null>(null);
  const cf = useCollectionFloor(); // live collection floor (building from buybacks)
  // Genesis MiFrens are a standard ERC-721 — always transferable (no lock).
  const locked = false as boolean | null;
  const nftAddress = CAULDRON.mifrens;

  // Read the LIVE OG redemption floor (GNOME per fren) when a genesis fren opens.
  useEffect(() => {
    if (!nft || !pc || !isGenesisFren(nft.tokenId)) { setFloor(null); return; }
    let alive = true;
    (async () => {
      try {
        const reg = { address: CAULDRON.registry, abi: REGISTRY_FLOOR_ABI } as const;
        const [f, tok] = await Promise.all([
          pc.readContract({ ...reg, functionName: "floorPerFren" }) as Promise<bigint>,
          pc.readContract({ ...reg, functionName: "currentToken" }) as Promise<`0x${string}`>,
        ]);
        const sym = await pc.readContract({ address: tok, abi: [{ type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] }] as const, functionName: "symbol" }).catch(() => "GNOME") as string;
        if (alive) setFloor({ gnome: Number(formatUnits(f, 18)), ticker: sym || "GNOME" });
      } catch { if (alive) setFloor(null); }
    })();
    return () => { alive = false; };
  }, [nft, pc]);

  // ESC to close
  useEffect(() => {
    if (!nft) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !transferring) onClose();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [nft, transferring, onClose]);

  // Focus trap
  useEffect(() => {
    if (!nft) return;
    const modal = modalRef.current;
    if (!modal) return;

    const handler = (e: KeyboardEvent) => {
      if (e.key !== "Tab") return;
      const focusable = modal.querySelectorAll<HTMLElement>(
        'button:not([disabled]), a[href], input:not([disabled]), [tabindex]:not([tabindex="-1"])',
      );
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault();
          last.focus();
        }
      } else {
        if (document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };

    requestAnimationFrame(() => {
      const first = modal.querySelector<HTMLElement>(
        'button:not([disabled]), a[href], input:not([disabled])',
      );
      first?.focus();
    });

    modal.addEventListener("keydown", handler);
    return () => modal.removeEventListener("keydown", handler);
  }, [nft]);

  const handleTransfer = useCallback(async () => {
    if (!nft || !transferAddr || !walletAddress || !pc) return;

    if (!isAddress(transferAddr)) {
      toast.error("Invalid recipient address");
      return;
    }

    setTransferring(true);
    try {
      const hash = await writeContractAsync({
        address: nftAddress, abi: ERC721_TRANSFER_ABI, functionName: "safeTransferFrom",
        args: [walletAddress as `0x${string}`, transferAddr as `0x${string}`, nft.tokenId],
      });
      toast.success("Transfer submitted — awaiting confirmation…");
      const r = await pc.waitForTransactionReceipt({ hash, timeout: 90_000 });
      if (r.status === "reverted") throw new Error("transfer reverted");

      toast.success(`Transferred Fren #${nft.tokenId} to ${transferAddr.slice(0, 8)}...`);
      setShowTransferInput(false);
      setTransferAddr("");
      onClose();
    } catch (err) {
      const msg = err instanceof Error ? (err as { shortMessage?: string }).shortMessage ?? err.message : String(err);
      toast.error(`Transfer failed: ${msg}`);
    } finally {
      setTransferring(false);
    }
  }, [nft, transferAddr, walletAddress, pc, writeContractAsync, nftAddress, onClose]);

  const handleRecycle = useCallback(async () => {
    if (!nft || !pc) return;
    setRecycling(true);
    const t = toast.loading(`Recycling Fren #${nft.tokenId} for the floor…`);
    try {
      const hash = await writeContractAsync({
        address: CAULDRON.registry, abi: REGISTRY_FLOOR_ABI, functionName: "redeemOgFren", args: [nft.tokenId],
      });
      const r = await pc.waitForTransactionReceipt({ hash, timeout: 90_000 });
      if (r.status === "reverted") throw new Error("recycle reverted");
      toast.success(`Recycled #${nft.tokenId} — floor paid to your wallet ✓`, { id: t });
      onClose();
    } catch (err) {
      const msg = err instanceof Error ? (err as { shortMessage?: string }).shortMessage ?? err.message : String(err);
      toast.error(`Recycle failed: ${msg}`, { id: t });
    } finally {
      setRecycling(false);
    }
  }, [nft, pc, writeContractAsync, onClose]);

  if (!nft) return null;

  const traits = resolveTraits(nft.classIdx, nft.bodyIdx, nft.faceIdx, nft.itemIdx);
  const classColor = CLASS_COLORS[traits.className as FrenClass] ?? "#8A7BAA";
  const genesis = isGenesisFren(nft.tokenId);

  return createPortal(
    <div className="fd__overlay" onClick={!transferring ? onClose : undefined}>
      <div className="fd__modal" ref={modalRef} role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
        <button className="fd__close" onClick={onClose} aria-label="Close">
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round"><path d="M1 1l12 12M13 1L1 13" /></svg>
        </button>

        <div className="fd__body">
          <div className="fd__cols">
            {/* ── identity column ── */}
            <aside className="fd__idcol">
              <div className={`fd__art${genesis ? " fd__art--genesis" : ""}`}>
                {nft.imageUri ? (
                  <img src={nft.imageUri} alt={`MiFren #${nft.tokenId}`} className="fd__img" style={{ imageRendering: "pixelated" } as CSSProperties} />
                ) : nft.bodyFile ? (
                  <FrenSprite bodyFile={nft.bodyFile} faceFile={nft.faceFile} itemFile={nft.itemFile}
                    bodyIdx={nft.bodyIdx} faceIdx={nft.faceIdx} itemIdx={nft.itemIdx} className="fd__img" alt={`MiFren #${nft.tokenId}`} />
                ) : (
                  <div className="fd__img-ph">#{nft.tokenId.toString()}</div>
                )}
              </div>

              <h2 className="fd__name">MiFren <span className="fd__hash">#{nft.tokenId.toString()}</span></h2>
              <div className="fd__chips">
                {genesis && <span className="fd__chip fd__chip--genesis" title="Genesis Founder — earns from every iteration">◆ Genesis</span>}
                <span className="fd__chip fd__chip--class" style={{ color: classColor, borderColor: `${classColor}66` }}>{traits.className}</span>
              </div>

              {genesis && (
                <div className="fd__hero">
                  <span className="fd__hero-k">Redemption Floor</span>
                  <span className="fd__hero-v">{floor ? `${fmtAmt(floor.gnome)}` : "…"}<em>${floor?.ticker ?? "GNOME"}</em></span>
                  <span className="fd__hero-sub">per fren · redeemable now</span>
                </div>
              )}
            </aside>

            {/* ── ledger column ── */}
            <section className="fd__detailcol">
              <dl className="fd__ledger">
                {genesis && (
                  <div className="fd__row fd__row--gold">
                    <dt>Edition</dt><dd>Genesis Founder · 1 of 1111</dd>
                  </div>
                )}
                <div className="fd__row"><dt>Body</dt><dd>{traits.bodyLabel}</dd></div>
                <div className="fd__row"><dt>Face</dt><dd>{traits.faceLabel}</dd></div>
                <div className="fd__row"><dt>Item</dt><dd>{traits.itemLabel}</dd></div>
                {locked !== null && (
                  <div className="fd__row"><dt>Status</dt><dd className={locked ? "fd__locked" : undefined}>{locked ? "Locked" : "Unlocked"}</dd></div>
                )}
              </dl>

              {genesis && (
                <div className="fd__collfloor">
                  <span className="fd__cf-k">Collection Floor</span>
                  <span className="fd__cf-v">{cf.loading ? "…" : `${fmtAmt(Number(cf.fmt ? cf.fmt(cf.livePending) : Number(cf.livePending) / 1e18))} $${cf.ticker || floor?.ticker || "GNOME"}`}</span>
                  <span className="fd__cf-sub">building from fees ↑</span>
                </div>
              )}
            </section>
          </div>

          {/* ── actions ── */}
          <div className="fd__foot">
            {genesis && !showTransferInput && (
              <>
                <button className="fd__btn fd__btn--recycle" onClick={handleRecycle} disabled={recycling || !floor}
                  title="Recycle this fren for the live floor — it goes to the treasury (not burned), resold at 2×; the floor only ratchets up">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M7 19H4.8a2 2 0 0 1-1.7-3l3.4-6M17 5h2.2a2 2 0 0 1 1.7 3l-2 3.4M12 22l-3-3 3-3M12 2l3 3-3 3M5 12l-2.5 1.5M19 12l2.5-1.5"/></svg>
                  {recycling ? "Recycling…" : floor ? `Recycle for ${fmtAmt(floor.gnome)} $${floor.ticker}` : "Recycle"}
                </button>
                <p className="fd__note">Pays you the live floor from the reserve. It <b>only rises</b> — buybacks + re-enchant fees grow it.</p>
              </>
            )}

            {showTransferInput ? (
              <div className="fd__xfer">
                <input type="text" className="fd__xfer-input" placeholder="Recipient address…" value={transferAddr}
                  onChange={(e) => setTransferAddr(e.target.value)} disabled={transferring} />
                <div className="fd__foot-row">
                  <button className="fd__btn fd__btn--send" onClick={handleTransfer} disabled={transferring || !transferAddr}>{transferring ? "Sending…" : "Confirm"}</button>
                  <button className="fd__btn fd__btn--ghost" onClick={() => { setShowTransferInput(false); setTransferAddr(""); }} disabled={transferring}>Cancel</button>
                </div>
              </div>
            ) : (
              <div className="fd__foot-row">
                <button className="fd__btn fd__btn--transfer" onClick={() => setShowTransferInput(true)}>Transfer</button>
                <button className="fd__btn fd__btn--list" disabled={!onListForSale}
                  onClick={() => { if (nft && onListForSale) { onListForSale(nft.tokenId); onClose(); } }}>List for Sale</button>
              </div>
            )}
          </div>
        </div>

        <style>{fdStyles}</style>
      </div>
    </div>,
    document.body,
  );
}

const fdStyles = `
  .fd__overlay {
    position: fixed; inset: 0; z-index: 9999;
    display: flex; align-items: center; justify-content: center; padding: 24px; overflow-y: auto;
    background: rgba(6,4,12,0.78); backdrop-filter: blur(20px);
    animation: fd-in 0.28s ease;
  }
  @keyframes fd-in { from { opacity: 0; } to { opacity: 1; } }

  .fd__modal {
    position: relative;
    width: 100%; max-width: 660px;
    background:
      radial-gradient(130% 90% at 50% -20%, rgba(213,253,81,0.07), transparent 50%),
      linear-gradient(165deg, #171128 0%, #0f0b1e 60%, #0b0817 100%);
    border: 1px solid rgba(213,253,81,0.14);
    border-radius: var(--r-md);
    box-shadow: 0 40px 100px rgba(0,0,0,0.65), inset 0 1px 0 rgba(255,255,255,0.05);
    overflow: hidden;
    animation: fd-rise 0.45s cubic-bezier(0.22,1,0.36,1);
  }
  @keyframes fd-rise { from { opacity: 0; transform: translateY(18px) scale(0.985); } to { opacity: 1; transform: none; } }
  /* hairline gold accent along the top */
  .fd__modal::before { content: ""; position: absolute; top: 0; left: 22px; right: 22px; height: 1px;
    background: linear-gradient(90deg, transparent, rgba(246,200,106,0.5), transparent); }

  .fd__close {
    position: absolute; top: 15px; right: 15px; width: 30px; height: 30px; z-index: 3;
    display: grid; place-items: center; border-radius: 50%;
    background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.08); color: #8f83b8;
    cursor: pointer; transition: all 0.18s ease;
  }
  .fd__close:hover { background: rgba(255,77,109,0.2); border-color: rgba(255,77,109,0.4); color: #ffd9dc; }
  .fd__close:focus-visible { outline: 2px solid #d5fd51; outline-offset: 2px; }

  .fd__body { padding: 26px; }
  .fd__cols { display: grid; grid-template-columns: 190px 1fr; gap: 26px; align-items: start; }

  /* identity column */
  .fd__idcol { display: flex; flex-direction: column; align-items: center; text-align: center; }
  .fd__art {
    position: relative; width: 100%; aspect-ratio: 1; border-radius: var(--r-md); overflow: hidden;
    border: 1px solid rgba(255,255,255,0.09); background: rgba(255,255,255,0.02);
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.06), 0 14px 34px rgba(0,0,0,0.4);
  }
  .fd__art--genesis { border-color: rgba(213,253,81,0.45); box-shadow: inset 0 0 22px rgba(213,253,81,0.12), 0 0 24px rgba(213,253,81,0.14), 0 14px 34px rgba(0,0,0,0.4); }
  .fd__img { width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; display: block; }
  .fd__img-ph { width: 100%; height: 100%; display: grid; place-items: center; font-family: "Fredoka", sans-serif; font-size: 30px; color: rgba(245,240,232,0.14); }

  .fd__name { margin: 16px 0 0; font-family: "Cinzel Decorative", serif; font-size: 19px; font-weight: 700; color: #F5F0E8; letter-spacing: 0.01em; line-height: 1.15; }
  .fd__hash { color: #8f83b8; font-weight: 400; }
  .fd__chips { display: flex; flex-wrap: wrap; gap: 6px; justify-content: center; margin-top: 10px; }
  .fd__chip { font-family: "DM Mono", monospace; font-size: 9px; font-weight: 600; letter-spacing: 0.1em; text-transform: uppercase; padding: 4px 9px; border-radius: var(--r-chip); }
  .fd__chip--genesis { color: #17112f; background: linear-gradient(90deg, #d5fd51, #f6c86a); box-shadow: 0 2px 10px rgba(213,253,81,0.3); }
  .fd__chip--class { background: transparent; border: 1px solid; }

  .fd__hero { margin-top: 18px; padding-top: 16px; width: 100%; border-top: 1px solid rgba(255,255,255,0.07); display: flex; flex-direction: column; gap: 3px; }
  .fd__hero-k { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.16em; text-transform: uppercase; color: #7a6fa0; }
  .fd__hero-v { font-family: "Fredoka", sans-serif; font-size: 25px; font-weight: 700; color: #d5fd51; line-height: 1; display: flex; align-items: baseline; gap: 6px; justify-content: center; }
  .fd__hero-v em { font-style: normal; font-size: 12px; font-weight: 600; color: #a9e04a; }
  .fd__hero-sub { font-family: "DM Sans", sans-serif; font-size: 10px; color: #6b6390; }

  /* ledger column */
  .fd__detailcol { display: flex; flex-direction: column; }
  .fd__ledger {
    margin: 0; border: 1px solid rgba(255,255,255,0.07); border-radius: var(--r-sm);
    background: rgba(255,255,255,0.02); overflow: hidden; box-shadow: inset 0 1px 0 rgba(255,255,255,0.03);
  }
  .fd__row { display: flex; align-items: center; justify-content: space-between; padding: 11px 15px; border-bottom: 1px solid rgba(255,255,255,0.045); }
  .fd__row:last-child { border-bottom: none; }
  .fd__row dt { font-family: "DM Mono", monospace; font-size: 9.5px; font-weight: 500; letter-spacing: 0.13em; text-transform: uppercase; color: #7a6fa0; margin: 0; }
  .fd__row dd { margin: 0; font-family: "DM Sans", sans-serif; font-size: 13px; font-weight: 600; color: #F5F0E8; text-align: right; }
  .fd__row--gold dd { background: linear-gradient(90deg, #d5fd51, #f6c86a); -webkit-background-clip: text; background-clip: text; -webkit-text-fill-color: transparent; font-weight: 700; }
  .fd__locked { color: #f6c86a !important; }

  .fd__collfloor { margin-top: 12px; padding: 12px 15px; border-radius: var(--r-sm); background: rgba(246,200,106,0.05); border: 1px solid rgba(246,200,106,0.14); display: flex; flex-direction: column; gap: 3px; }
  .fd__cf-k { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: #b79a5e; }
  .fd__cf-v { font-family: "Fredoka", sans-serif; font-size: 16px; font-weight: 700; color: #f6c86a; line-height: 1.05; }
  .fd__cf-sub { font-family: "DM Sans", sans-serif; font-size: 10px; color: #6b6390; }

  /* footer actions */
  .fd__foot { margin-top: 20px; }
  .fd__foot-row { display: flex; gap: 10px; }
  .fd__foot-row .fd__btn { flex: 1; }
  .fd__btn {
    display: flex; align-items: center; justify-content: center; gap: 8px;
    padding: 12px 20px; border: none; border-radius: var(--r-sm); cursor: pointer;
    font-family: "DM Sans", sans-serif; font-size: 13px; font-weight: 700; letter-spacing: 0.01em;
    transition: transform 0.15s ease, box-shadow 0.15s ease, background 0.15s ease, border-color 0.15s ease;
  }
  .fd__btn:focus-visible { outline: 2px solid #d5fd51; outline-offset: 2px; }
  .fd__btn:disabled { opacity: 0.45; cursor: not-allowed; }

  .fd__btn--recycle {
    width: 100%; padding: 14px 20px; color: #0b0817; letter-spacing: 0.02em;
    background: linear-gradient(95deg, #d5fd51, #8dfca0);
    box-shadow: 0 6px 26px rgba(213,253,81,0.34);
  }
  .fd__btn--recycle:hover:not(:disabled) { transform: translateY(-1px); box-shadow: 0 10px 32px rgba(213,253,81,0.5); }
  .fd__note { margin: 9px 2px 16px; font-family: "DM Sans", sans-serif; font-size: 10.5px; line-height: 1.5; color: #8f83b8; text-align: center; }
  .fd__note b { color: #d5fd51; }

  .fd__btn--transfer { color: #F5F0E8; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.11); }
  .fd__btn--transfer:hover:not(:disabled) { background: rgba(255,255,255,0.09); border-color: rgba(213,253,81,0.3); }
  .fd__btn--list { color: #f6c86a; background: transparent; border: 1px solid rgba(246,200,106,0.35); }
  .fd__btn--list:hover:not(:disabled) { border-color: #f6c86a; background: rgba(246,200,106,0.07); }
  .fd__btn--send { color: #0b0817; background: #d5fd51; }
  .fd__btn--ghost { color: #8f83b8; background: transparent; border: 1px solid rgba(255,255,255,0.1); }
  .fd__btn--ghost:hover:not(:disabled) { color: #F5F0E8; border-color: rgba(255,255,255,0.2); }

  .fd__xfer { display: flex; flex-direction: column; gap: 10px; }
  .fd__xfer-input {
    width: 100%; padding: 12px 15px; box-sizing: border-box; border-radius: var(--r-sm); outline: none;
    background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.1); color: #F5F0E8;
    font-family: "DM Mono", monospace; font-size: 12px; transition: border-color 0.2s, box-shadow 0.2s;
  }
  .fd__xfer-input:focus { border-color: #d5fd51; box-shadow: 0 0 0 3px rgba(213,253,81,0.1); }
  .fd__xfer-input::placeholder { color: #6b6390; }

  @media (prefers-reduced-motion: reduce) { .fd__overlay, .fd__modal { animation: none !important; } }
  @media (max-width: 560px) {
    .fd__body { padding: 22px; }
    .fd__cols { grid-template-columns: 1fr; gap: 20px; }
    .fd__idcol { max-width: 220px; margin: 0 auto; }
    .fd__modal { max-width: 420px; }
  }
`;
