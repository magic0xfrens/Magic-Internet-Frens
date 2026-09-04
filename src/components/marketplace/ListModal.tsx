import { useState, useEffect, useRef, useCallback } from "react";
import type { ApprovalStatus } from "@/hooks/useMarketplace";

type ListState = "idle" | "listing" | "sent";

interface ListModalProps {
  open: boolean;
  tokenId: bigint | null;
  approvalStatus: ApprovalStatus;
  onClose: () => void;
  onCheckApproval: () => Promise<void>;
  onApprove: () => Promise<void>;
  onConfirm: (tokenId: bigint, priceSats: bigint) => Promise<void>;
}

export default function ListModal({
  open,
  tokenId,
  approvalStatus,
  onClose,
  onCheckApproval,
  onApprove,
  onConfirm,
}: ListModalProps) {
  const [priceBTC, setPriceBTC] = useState("");
  const [listState, setListState] = useState<ListState>("idle");
  const modalRef = useRef<HTMLDivElement>(null);

  // Stable ref to avoid re-triggering effect when callback identity changes
  const checkRef = useRef(onCheckApproval);
  checkRef.current = onCheckApproval;

  // Check approval when modal opens
  useEffect(() => {
    if (open) {
      setPriceBTC("");
      setListState("idle");
      checkRef.current();
    }
  }, [open]);

  // ESC to close
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape" && listState !== "listing" && approvalStatus !== "approving" && approvalStatus !== "waiting_confirm") {
        onClose();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [open, listState, approvalStatus, onClose]);

  // Focus trap
  useEffect(() => {
    if (!open) return;
    const modal = modalRef.current;
    if (!modal) return;
    requestAnimationFrame(() => {
      const first = modal.querySelector<HTMLElement>("input, button:not([disabled])");
      first?.focus();
    });
  }, [open, approvalStatus]);

  const handleApprove = useCallback(async () => {
    await onApprove();
  }, [onApprove]);

  const handleSubmit = useCallback(async () => {
    if (!tokenId || listState !== "idle") return;
    const btcVal = parseFloat(priceBTC);
    if (isNaN(btcVal) || btcVal <= 0) return;

    const sats = BigInt(Math.round(btcVal * 1e8));
    setListState("listing");
    try {
      await onConfirm(tokenId, sats);
      setListState("sent");
    } catch {
      setListState("idle");
    }
  }, [tokenId, priceBTC, listState, onConfirm]);

  if (!open || !tokenId) return null;

  const btcVal = parseFloat(priceBTC);
  const isValid = !isNaN(btcVal) && btcVal > 0;
  const isApproved = approvalStatus === "approved";
  const isProcessingApproval = approvalStatus === "approving" || approvalStatus === "waiting_confirm";
  const canClose = listState !== "listing" && !isProcessingApproval;

  return (
    <div className="lm__overlay" onClick={canClose ? onClose : undefined}>
      <div
        className="lm__modal"
        ref={modalRef}
        role="dialog"
        aria-modal="true"
        onClick={(e) => e.stopPropagation()}
      >
        {canClose && (
          <button className="lm__close" onClick={onClose} aria-label="Close">&times;</button>
        )}

        <div className="lm__body">
          <h2 className="lm__title">LIST FOR SALE</h2>
          <p className="lm__subtitle">MiFren #{tokenId.toString()}</p>

          {/* Listing TX Sent — waiting for confirmation */}
          {listState === "sent" ? (
            <div className="lm__sent">
              <div className="lm__spinner" />
              <span className="lm__sent-title">LISTING TX SENT</span>
              <span className="lm__sent-grass">Touch sum grass fren, TX needs 10min+ to confirm</span>
              <span className="lm__sent-sub">Your listing will appear on the marketplace once confirmed</span>
              <button className="lm__cta lm__cta--close" onClick={onClose}>CLOSE</button>
            </div>
          ) : (
            <>
              {/* Step 1: Approval */}
              {!isApproved && (
                <div className="lm__step">
                  <div className="lm__step-header">
                    <span className="lm__step-num">1</span>
                    <span className="lm__step-label">APPROVE MARKETPLACE</span>
                  </div>

                  {(approvalStatus === "unknown" || approvalStatus === "checking") && (
                    <div className="lm__status">
                      <span className="lm__spinner" />
                      <span className="lm__status-text">Checking approval status...</span>
                    </div>
                  )}

                  {approvalStatus === "not_approved" && (
                    <>
                      <p className="lm__hint">
                        One-time approval to let the marketplace transfer your Frens.
                      </p>
                      <button className="lm__cta lm__cta--approve" onClick={handleApprove}>
                        APPROVE COLLECTION
                      </button>
                    </>
                  )}

                  {approvalStatus === "approving" && (
                    <div className="lm__status">
                      <span className="lm__spinner" />
                      <span className="lm__status-text">Sending approval TX...</span>
                    </div>
                  )}

                  {approvalStatus === "waiting_confirm" && (
                    <div className="lm__status lm__status--waiting">
                      <span className="lm__spinner" />
                      <span className="lm__status-text">Waiting for confirmation...</span>
                      <span className="lm__grass-banner">Touch sum grass fren, TX confirming</span>
                      <span className="lm__status-sub">Modal will update automatically</span>
                    </div>
                  )}
                </div>
              )}

              {/* Step 2: Set price & list (only when approved) */}
              {isApproved && (
                <>
                  <div className="lm__approved-badge">COLLECTION APPROVED</div>

                  <div className="lm__field">
                    <label className="lm__label">PRICE (ETH)</label>
                    <input
                      type="number"
                      step="0.0001"
                      min="0"
                      className="lm__input"
                      placeholder="0.01"
                      value={priceBTC}
                      onChange={(e) => setPriceBTC(e.target.value)}
                      disabled={listState === "listing"}
                    />
                    {isValid && (
                      <span className="lm__sats">{btcVal} ETH</span>
                    )}
                  </div>

                  <button
                    className="lm__cta"
                    onClick={handleSubmit}
                    disabled={!isValid || listState === "listing"}
                  >
                    {listState === "listing" ? "LISTING..." : "LIST FOR SALE"}
                  </button>
                </>
              )}
            </>
          )}
        </div>
      </div>

      <style>{listModalStyles}</style>
    </div>
  );
}

const listModalStyles = `
  .lm__overlay {
    position: fixed;
    inset: 0;
    z-index: 10000;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(42, 31, 84, 0.5);
    backdrop-filter: blur(12px);
    animation: lm-fadein 0.25s ease;
  }

  @keyframes lm-fadein {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .lm__modal {
    position: relative;
    background: #FBF7F0;
    border: 1px solid rgba(42,31,84,0.12);
    border-radius: 12px;
    max-width: 400px;
    width: 92%;
    overflow: hidden;
    box-shadow: 0 2px 8px rgba(42,31,84,0.08);
    animation: lm-pop 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
  }

  @keyframes lm-pop {
    from { opacity: 0; transform: scale(0.88) translateY(24px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .lm__close {
    position: absolute;
    top: 14px;
    right: 18px;
    background: none;
    border: none;
    color: #8A7BAA;
    font-size: 22px;
    cursor: pointer;
    z-index: 2;
    line-height: 1;
    transition: color 0.15s ease;
  }
  .lm__close:hover { color: #2A1F54; }

  .lm__body {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 36px 28px 28px;
    text-align: center;
  }

  .lm__title {
    font-family: "Fredoka", sans-serif;
    font-size: 13px;
    color: #d5fd51;
    margin-bottom: 8px;
  }

  .lm__subtitle {
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    color: #2A1F54;
    margin-bottom: 24px;
  }

  /* Step layout */
  .lm__step {
    width: 100%;
    margin-bottom: 20px;
  }

  .lm__step-header {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 14px;
  }

  .lm__step-num {
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(42,31,84,0.12);
    color: #7C5CFC;
    font-family: "DM Sans", sans-serif;
    font-size: 12px;
    font-weight: 700;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .lm__step-label {
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.08em;
    color: #2A1F54;
  }

  .lm__hint {
    font-size: 12px;
    color: #8A7BAA;
    margin-bottom: 14px;
    line-height: 1.5;
  }

  /* Status with spinner */
  .lm__status {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 18px 0;
  }

  .lm__status--waiting {
    padding: 24px 0;
  }

  .lm__spinner {
    width: 28px;
    height: 28px;
    border: 3px solid rgba(42,31,84,0.12);
    border-top-color: #7C5CFC;
    border-radius: 50%;
    animation: lm-spin 0.8s linear infinite;
  }

  @keyframes lm-spin {
    to { transform: rotate(360deg); }
  }

  .lm__status-text {
    font-family: "DM Sans", sans-serif;
    font-size: 12px;
    color: #2A1F54;
  }

  .lm__status-text--dim {
    color: #8A7BAA;
  }

  .lm__status-sub {
    font-size: 11px;
    color: #8A7BAA;
  }

  /* Approved badge */
  .lm__approved-badge {
    font-family: "DM Sans", sans-serif;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.12em;
    color: #3ddc84;
    border: 1px solid rgba(52, 211, 153, 0.3);
    border-radius: 12px;
    padding: 6px 14px;
    margin-bottom: 20px;
    background: rgba(52, 211, 153, 0.06);
  }

  /* Price field */
  .lm__field {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-bottom: 20px;
  }

  .lm__label {
    font-size: 10px;
    font-weight: 500;
    letter-spacing: 0.12em;
    color: #8A7BAA;
    text-align: left;
  }

  .lm__input {
    width: 100%;
    padding: 12px 14px;
    background: #F5F0E8;
    border: 1px solid rgba(42,31,84,0.12);
    border-radius: 12px;
    color: #2A1F54;
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    outline: none;
    box-sizing: border-box;
    transition: border-color 0.15s ease;
  }

  .lm__input:focus {
    border-color: #7C5CFC;
  }

  .lm__input::placeholder {
    color: #B8ADCC;
  }

  .lm__sats {
    font-size: 11px;
    color: #8A7BAA;
    text-align: right;
  }

  /* Sent / Waiting state */
  .lm__sent {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 12px 0;
  }

  .lm__sent-title {
    font-family: "Fredoka", sans-serif;
    font-size: 11px;
    color: #3ddc84;
  }

  .lm__sent-grass {
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    font-weight: 700;
    color: #d5fd51;
    margin-top: 12px;
    padding: 14px 20px;
    background: rgba(247, 147, 26, 0.06);
    border: 1px solid rgba(247, 147, 26, 0.2);
    border-radius: 12px;
    text-align: center;
    width: 100%;
    box-sizing: border-box;
  }

  .lm__sent-sub {
    font-size: 11px;
    color: #8A7BAA;
  }

  .lm__grass-banner {
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    font-weight: 700;
    color: #d5fd51;
    padding: 14px 20px;
    background: rgba(247, 147, 26, 0.06);
    border: 1px solid rgba(247, 147, 26, 0.2);
    border-radius: 12px;
    text-align: center;
    width: 100%;
    box-sizing: border-box;
  }

  /* CTA buttons */
  .lm__cta {
    width: 100%;
    padding: 14px 32px;
    background: #d5fd51;
    color: #FBF7F0;
    border: none;
    border-radius: 12px;
    font-family: "DM Sans", sans-serif;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.1em;
    cursor: pointer;
    transition: opacity 0.15s ease;
  }

  .lm__cta--approve {
    background: #7C5CFC;
    color: #FBF7F0;
  }

  .lm__cta--close {
    background: rgba(42,31,84,0.12);
    color: #2A1F54;
    margin-top: 16px;
  }

  .lm__cta:hover:not(:disabled) {
    opacity: 0.9;
  }

  .lm__cta:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .lm__cta:focus-visible {
    outline: 2px solid #7C5CFC;
    outline-offset: 3px;
  }

  @media (prefers-reduced-motion: reduce) {
    .lm__overlay, .lm__modal, .lm__spinner { animation: none !important; }
  }
`;
