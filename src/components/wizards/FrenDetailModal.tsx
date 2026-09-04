import { useEffect, useRef, useState, useCallback, type CSSProperties } from "react";
import { createPortal } from "react-dom";
import { isAddress } from "viem";
import { usePublicClient, useWriteContract } from "wagmi";
import toast from "react-hot-toast";
import type { OwnedNFT } from "@/hooks/useUserNFTs";
import { resolveTraits } from "@/data/traitResolver";
import FrenSprite from "@/components/shared/FrenSprite";
import { CLASS_COLORS, type FrenClass, isGenesisFren } from "@/data/frens";
import { useWallet } from "@/hooks/useWallet";
import { CAULDRON } from "@/config/cauldron";

// Minimal ERC-721 transfer ABI (the genesis MiFrens are a standard ERC-721).
const ERC721_TRANSFER_ABI = [
  { type: "function", name: "safeTransferFrom", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "address" }, { type: "uint256" }], outputs: [] },
] as const;

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
  // Genesis MiFrens are a standard ERC-721 — always transferable (no lock).
  const locked = false as boolean | null;
  const nftAddress = CAULDRON.mifrens;

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

  if (!nft) return null;

  const traits = resolveTraits(nft.classIdx, nft.bodyIdx, nft.faceIdx, nft.itemIdx);
  const classColor = CLASS_COLORS[traits.className as FrenClass] ?? "#8A7BAA";
  const genesis = isGenesisFren(nft.tokenId);

  return createPortal(
    <div className="fd__overlay" onClick={!transferring ? onClose : undefined}>
      <div
        className="fd__modal"
        ref={modalRef}
        role="dialog"
        aria-modal="true"
        onClick={(e) => e.stopPropagation()}
      >
        <button className="fd__close" onClick={onClose} aria-label="Close">
          &times;
        </button>

        <div className="fd__body">
          {/* Image */}
          <div className="fd__image-wrap">
            {nft.imageUri ? (
              <img
                src={nft.imageUri}
                alt={`MiFren #${nft.tokenId}`}
                className="fd__image"
                style={{ imageRendering: "pixelated" } as CSSProperties}
              />
            ) : nft.bodyFile ? (
              <FrenSprite
                bodyFile={nft.bodyFile}
                faceFile={nft.faceFile}
                itemFile={nft.itemFile}
                bodyIdx={nft.bodyIdx}
                faceIdx={nft.faceIdx}
                itemIdx={nft.itemIdx}
                className="fd__image"
                alt={`MiFren #${nft.tokenId}`}
              />
            ) : (
              <div className="fd__image-placeholder">
                #{nft.tokenId.toString()}
              </div>
            )}
            <div className="fd__image-glow" style={{ background: genesis
              ? "radial-gradient(circle, rgba(213,253,81,0.28) 0%, rgba(255,214,107,0.12) 45%, transparent 72%)"
              : `radial-gradient(circle, ${classColor}15 0%, transparent 70%)` }} />
            {genesis && <div className="fd__genesis-ring" />}
          </div>

          {/* Header */}
          <div className="fd__header">
            <span className="fd__token-id">MiFren #{nft.tokenId.toString()}</span>
            {genesis && <span className="fd__genesis-badge" title="Genesis Founder — earns a share of every iteration's fees">◆ GENESIS</span>}
            <span className="fd__class-badge" style={{ borderColor: classColor, color: classColor }}>
              {traits.className}
            </span>
          </div>

          {/* Trait table */}
          <div className="fd__traits">
            {genesis && (
              <div className="fd__trait-row fd__trait-row--genesis">
                <span className="fd__trait-label">EDITION</span>
                <span className="fd__trait-value">Genesis Founder · 1 of {1111}</span>
              </div>
            )}
            <div className="fd__trait-row">
              <span className="fd__trait-label">BODY</span>
              <span className="fd__trait-value">{traits.bodyLabel}</span>
            </div>
            <div className="fd__trait-row">
              <span className="fd__trait-label">FACE</span>
              <span className="fd__trait-value">{traits.faceLabel}</span>
            </div>
            <div className="fd__trait-row">
              <span className="fd__trait-label">ITEM</span>
              <span className="fd__trait-value">{traits.itemLabel}</span>
            </div>
            {locked !== null && (
              <div className="fd__trait-row">
                <span className="fd__trait-label">STATUS</span>
                <span className={`fd__trait-value${locked ? " fd__trait-value--locked" : ""}`}>
                  {locked ? "Locked (in Cauldron)" : "Unlocked"}
                </span>
              </div>
            )}
          </div>

          {/* Actions */}
          <div className="fd__actions">
            {showTransferInput ? (
              <div className="fd__transfer-form">
                <input
                  type="text"
                  className="fd__transfer-input"
                  placeholder="Recipient address..."
                  value={transferAddr}
                  onChange={(e) => setTransferAddr(e.target.value)}
                  disabled={transferring}
                />
                <div className="fd__transfer-btns">
                  <button
                    className="fd__btn fd__btn--transfer"
                    onClick={handleTransfer}
                    disabled={transferring || !transferAddr || locked === true}
                  >
                    {transferring ? "SENDING..." : "CONFIRM TRANSFER"}
                  </button>
                  <button
                    className="fd__btn fd__btn--ghost"
                    onClick={() => {
                      setShowTransferInput(false);
                      setTransferAddr("");
                    }}
                    disabled={transferring}
                  >
                    CANCEL
                  </button>
                </div>
              </div>
            ) : (
              <>
                <button
                  className="fd__btn fd__btn--transfer"
                  onClick={() => setShowTransferInput(true)}
                  disabled={locked === true}
                >
                  TRANSFER
                </button>
                <button
                  className="fd__btn fd__btn--list"
                  disabled={locked === true || !onListForSale}
                  onClick={() => {
                    if (nft && onListForSale) {
                      onListForSale(nft.tokenId);
                      onClose();
                    }
                  }}
                >
                  LIST FOR SALE
                </button>
              </>
            )}
            {locked && (
              <p className="fd__lock-notice">
                This fren is locked in a Cauldron position. Unlock it first to transfer or list.
              </p>
            )}
          </div>
        </div>
      </div>

      <style>{fdStyles}</style>
    </div>,
    document.body,
  );
}

const fdStyles = `
  .fd__overlay {
    position: fixed;
    inset: 0;
    z-index: 9999;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
    overflow-y: auto;
    background: rgba(14,10,26,0.6);
    backdrop-filter: blur(16px);
    animation: fd-fadein 0.25s ease;
  }

  @keyframes fd-fadein {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .fd__modal {
    position: relative;
    background: #FBF7F0;
    border: 1px solid rgba(42,31,84,0.08);
    border-radius: 24px;
    max-width: 420px;
    width: 92%;
    overflow: hidden;
    box-shadow: 0 24px 64px rgba(42,31,84,0.18);
    animation: fd-pop 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
  }

  @keyframes fd-pop {
    from { opacity: 0; transform: scale(0.88) translateY(24px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .fd__close {
    position: absolute;
    top: 16px;
    right: 18px;
    width: 32px;
    height: 32px;
    background: rgba(42,31,84,0.04);
    border: none;
    border-radius: 50%;
    color: #8A7BAA;
    font-size: 18px;
    cursor: pointer;
    z-index: 2;
    line-height: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.15s ease;
  }
  .fd__close:hover { background: rgba(42,31,84,0.08); color: #2A1F54; }
  .fd__close:focus-visible { outline: 2px solid #7C5CFC; outline-offset: 2px; }

  .fd__body {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 36px 32px 32px;
  }

  /* Image */
  .fd__image-wrap {
    position: relative;
    width: 200px;
    height: 200px;
    margin-bottom: 24px;
    background: linear-gradient(145deg, #F5F0E8 0%, #EDE8DD 100%);
    border-radius: 20px;
    padding: 16px;
    box-sizing: border-box;
  }

  .fd__image {
    width: 100%;
    height: 100%;
    object-fit: contain;
    image-rendering: pixelated;
  }

  .fd__image-placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 32px;
    font-weight: 700;
    color: rgba(42,31,84,0.10);
    font-family: "Fredoka", sans-serif;
  }

  .fd__image-glow {
    position: absolute;
    inset: -24px;
    border-radius: 50%;
    z-index: -1;
  }

  /* Header */
  .fd__header {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 20px;
  }

  .fd__token-id {
    font-family: "Cinzel", serif;
    font-size: 18px;
    font-weight: 600;
    color: #2A1F54;
  }

  .fd__class-badge {
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.05em;
    padding: 4px 10px;
    border: 1px solid;
    border-radius: 20px;
    text-transform: uppercase;
  }

  /* Genesis Founder marks */
  .fd__genesis-badge {
    font-family: "DM Mono", monospace;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.1em;
    padding: 4px 10px;
    border-radius: 20px;
    color: #2A1F54;
    background: linear-gradient(90deg, #d5fd51, #ffd66b);
    box-shadow: 0 2px 10px rgba(213,253,81,0.4);
  }
  .fd__genesis-ring {
    position: absolute;
    inset: 8px;
    border-radius: 18px;
    pointer-events: none;
    border: 1.5px solid rgba(213,253,81,0.5);
    box-shadow: inset 0 0 24px rgba(213,253,81,0.18), 0 0 20px rgba(213,253,81,0.25);
    animation: fd-genesis-pulse 3s ease-in-out infinite;
  }
  @keyframes fd-genesis-pulse { 0%,100% { opacity: 0.55; } 50% { opacity: 1; } }
  .fd__trait-row--genesis .fd__trait-value {
    font-weight: 700;
    background: linear-gradient(90deg, #7a9a00, #b98900);
    -webkit-background-clip: text; background-clip: text; -webkit-text-fill-color: transparent;
  }
  @media (prefers-reduced-motion: reduce) { .fd__genesis-ring { animation: none; } }

  /* Trait table */
  .fd__traits {
    width: 100%;
    border: 1px solid rgba(42,31,84,0.06);
    border-radius: 16px;
    background: #F5F0E8;
    margin-bottom: 24px;
    overflow: hidden;
  }

  .fd__trait-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 20px;
    border-bottom: 1px solid rgba(42,31,84,0.05);
  }

  .fd__trait-row:last-child {
    border-bottom: none;
  }

  .fd__trait-label {
    font-size: 10px;
    font-weight: 500;
    letter-spacing: 0.12em;
    color: #B8ADCC;
  }

  .fd__trait-value {
    font-family: "DM Sans", sans-serif;
    font-size: 13px;
    font-weight: 600;
    color: #2A1F54;
  }

  .fd__trait-value--locked {
    color: #d5fd51;
  }

  /* Actions */
  .fd__actions {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .fd__btn {
    padding: 14px 24px;
    font-family: "Fredoka", sans-serif;
    font-size: 13px;
    font-weight: 500;
    letter-spacing: 0.04em;
    border-radius: 14px;
    cursor: pointer;
    text-align: center;
    text-decoration: none;
    transition: all 0.2s ease;
    display: block;
    width: 100%;
    box-sizing: border-box;
  }

  .fd__btn:focus-visible {
    outline: 2px solid #7C5CFC;
    outline-offset: 3px;
  }

  .fd__btn--transfer {
    background: #d5fd51;
    color: #FBF7F0;
    border: none;
  }

  .fd__btn--transfer:hover:not(:disabled) {
    transform: translateY(-1px);
    box-shadow: 0 4px 20px rgba(247, 147, 26, 0.3);
  }

  .fd__btn--transfer:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .fd__btn--list {
    background: transparent;
    color: #7C5CFC;
    border: 1.5px solid rgba(124, 92, 252, 0.25);
  }

  .fd__btn--list:hover:not(:disabled) {
    border-color: #7C5CFC;
    background: rgba(124, 92, 252, 0.04);
    transform: translateY(-1px);
    box-shadow: 0 4px 20px rgba(124, 92, 252, 0.12);
  }

  .fd__btn--list:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .fd__btn--ghost {
    background: transparent;
    color: #8A7BAA;
    border: 1px solid rgba(42,31,84,0.08);
  }

  .fd__btn--ghost:hover:not(:disabled) {
    color: #2A1F54;
    border-color: rgba(42,31,84,0.15);
    background: rgba(42,31,84,0.02);
  }

  /* Transfer form */
  .fd__transfer-form {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .fd__transfer-input {
    width: 100%;
    padding: 12px 16px;
    background: #F5F0E8;
    border: 1.5px solid rgba(42,31,84,0.08);
    border-radius: 14px;
    color: #2A1F54;
    font-family: "DM Sans", sans-serif;
    font-size: 13px;
    outline: none;
    box-sizing: border-box;
    transition: border-color 0.2s ease, box-shadow 0.2s ease;
  }

  .fd__transfer-input:focus {
    border-color: #7C5CFC;
    box-shadow: 0 0 0 3px rgba(124, 92, 252, 0.08);
  }

  .fd__transfer-input::placeholder {
    color: #B8ADCC;
  }

  .fd__transfer-input:disabled {
    opacity: 0.5;
  }

  .fd__transfer-btns {
    display: flex;
    gap: 10px;
  }

  .fd__transfer-btns .fd__btn {
    flex: 1;
  }

  .fd__lock-notice {
    font-size: 12px;
    color: #d5fd51;
    text-align: center;
    margin-top: 4px;
    line-height: 1.5;
  }

  @media (prefers-reduced-motion: reduce) {
    .fd__overlay,
    .fd__modal {
      animation: none !important;
    }
  }

  @media (max-width: 500px) {
    .fd__body {
      padding: 28px 20px 24px;
    }
    .fd__image-wrap {
      width: 160px;
      height: 160px;
    }
    .fd__modal {
      border-radius: 20px;
    }
  }
`;
