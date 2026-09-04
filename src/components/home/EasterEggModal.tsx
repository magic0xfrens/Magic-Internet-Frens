import { useEffect, useState, useCallback, useRef } from "react";

type EggPhase = "riddle" | "incantation" | "success" | "fail";

interface EasterEggModalProps {
  open: boolean;
  onClose: () => void;
}

// Answer: hidden as data-rune attribute on the manifesto section
const ANSWER = "f7e7";
const MAX_ATTEMPTS = 3;

const TWITTER_INTENT =
  "https://x.com/intent/tweet?text=I%20found%20the%20hidden%20egg%20at%20mifrens.xyz%20and%20cracked%20the%20wizard%27s%20riddle%20%F0%9F%A5%9A%E2%9C%A8%0A%0A%40magic0xfrens";

function EasterEggModal({ open, onClose }: EasterEggModalProps) {
  const [phase, setPhase] = useState<EggPhase>("riddle");
  const [guess, setGuess] = useState("");
  const [attempts, setAttempts] = useState(0);
  const [shake, setShake] = useState(false);
  const modalRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Reset on open
  useEffect(() => {
    if (open) {
      setPhase("riddle");
      setGuess("");
      setAttempts(0);
      setShake(false);
    }
  }, [open]);

  // Focus input when entering incantation phase
  useEffect(() => {
    if (phase === "incantation") {
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [phase]);

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [open, onClose]);

  // Focus trap
  useEffect(() => {
    if (!open) return;
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
        'button:not([disabled]), input:not([disabled])',
      );
      first?.focus();
    });

    modal.addEventListener("keydown", handler);
    return () => modal.removeEventListener("keydown", handler);
  }, [open, phase]);

  const handleSubmit = useCallback(() => {
    const normalized = guess.trim().toLowerCase();
    if (normalized === ANSWER) {
      setPhase("success");
    } else {
      const next = attempts + 1;
      setAttempts(next);
      if (next >= MAX_ATTEMPTS) {
        setPhase("fail");
      } else {
        setShake(true);
        setGuess("");
        setTimeout(() => setShake(false), 500);
      }
    }
  }, [guess, attempts]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter" && guess.trim().length > 0) handleSubmit();
    },
    [handleSubmit, guess],
  );

  const handleClaimX = useCallback(() => {
    window.open(TWITTER_INTENT, "_blank", "noopener,noreferrer");
  }, []);

  if (!open) return null;

  return (
    <div className="ee__overlay" onClick={onClose}>
      <div
        className="ee__modal"
        ref={modalRef}
        role="dialog"
        aria-modal="true"
        onClick={(e) => e.stopPropagation()}
      >
        <button className="ee__close" onClick={onClose} aria-label="Close">
          &times;
        </button>

        {/* RIDDLE PHASE */}
        {phase === "riddle" && (
          <div className="ee__body">
            <div className="ee__sigil">&#x1F9D9;</div>
            <h2 className="ee__title">THE WIZARD&apos;S TRIAL</h2>
            <p className="ee__riddle">
              &ldquo;The answer hides not in what the eye can see, but in
              the bones beneath the wizard&apos;s manifesto.&rdquo;
            </p>
            <p className="ee__riddle">
              &ldquo;Only those who peer beyond the surface &mdash; into the
              very source &mdash; shall find the four runes inscribed there.
              Speak them, and the ancient magic shall recognize thee.&rdquo;
            </p>
            <div className="ee__hint-box">
              <span className="ee__hint-label">DIFFICULTY</span>
              <span className="ee__hint-value">ARCHMAGE</span>
            </div>
            <button className="ee__cta" onClick={() => setPhase("incantation")}>
              I KNOW THE ANSWER
            </button>
          </div>
        )}

        {/* INCANTATION (INPUT) PHASE */}
        {phase === "incantation" && (
          <div className="ee__body">
            <h2 className="ee__title">SPEAK THE RUNES</h2>
            <p className="ee__subtitle">
              Enter the four hex runes. {MAX_ATTEMPTS - attempts} attempt{MAX_ATTEMPTS - attempts !== 1 ? "s" : ""} remaining.
            </p>
            <div className={`ee__input-wrap${shake ? " ee__input-wrap--shake" : ""}`}>
              <span className="ee__input-prefix">0x</span>
              <input
                ref={inputRef}
                className="ee__input"
                type="text"
                maxLength={4}
                spellCheck={false}
                autoComplete="off"
                autoCapitalize="off"
                placeholder="?????"
                value={guess}
                onChange={(e) => setGuess(e.target.value.replace(/[^0-9a-fA-F]/g, "").slice(0, 4))}
                onKeyDown={handleKeyDown}
              />
            </div>
            {attempts > 0 && (
              <p className="ee__attempt-hint">
                The stone remains silent. Look deeper, fren.
              </p>
            )}
            <button
              className="ee__cta"
              onClick={handleSubmit}
              disabled={guess.trim().length === 0}
            >
              SUBMIT INCANTATION
            </button>
            <button
              className="ee__cta ee__cta--ghost"
              onClick={() => { setPhase("riddle"); setGuess(""); setAttempts(0); }}
            >
              READ RIDDLE AGAIN
            </button>
          </div>
        )}

        {/* SUCCESS PHASE */}
        {phase === "success" && (
          <div className="ee__body">
            <div className="ee__sigil ee__sigil--glow">&#x2728;</div>
            <h2 className="ee__title ee__title--success">THE CODE HAS BEEN CRACKED</h2>
            <p className="ee__answer-reveal">
              <span className="ee__hex">0xf7e7</span>
            </p>
            <p className="ee__subtitle">
              Yuo read the bones of the manifesto, fren. The ancient magic
              recognizes thee. The riddle has already been solved by a bery gud
              wizard, but the runes remember all who find them.
            </p>
            <button className="ee__cta ee__cta--claim" onClick={handleClaimX}>
              SHARE ON X
            </button>
          </div>
        )}

        {/* FAIL PHASE */}
        {phase === "fail" && (
          <div className="ee__body">
            <div className="ee__sigil">&#x1F480;</div>
            <h2 className="ee__title ee__title--fail">THE STONE IS SILENT</h2>
            <p className="ee__subtitle">
              Your incantations have been spent. The ancient magic does not
              recognize thee&hellip; yet. Study the old scriptures and return, fren.
            </p>
            <button
              className="ee__cta"
              onClick={() => { setPhase("riddle"); setGuess(""); setAttempts(0); }}
            >
              START OVER
            </button>
          </div>
        )}
      </div>

      <style>{easterEggStyles}</style>
    </div>
  );
}

export default EasterEggModal;

/* ═══════════════════════════════════════════════════════════
 * Styles — Easter Egg Modal
 * ═══════════════════════════════════════════════════════════ */

const easterEggStyles = `
  .ee__overlay {
    position: fixed;
    inset: 0;
    z-index: 9999;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(42,31,84,0.55);
    backdrop-filter: blur(12px);
    animation: ee-fadein 0.25s ease;
  }

  @keyframes ee-fadein {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .ee__modal {
    position: relative;
    background: #FBF7F0;
    border: 1px solid rgba(42,31,84,0.12);
    border-radius: var(--r-sm);
    max-width: 420px;
    width: 92%;
    overflow: hidden;
    animation: ee-pop 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
  }

  @keyframes ee-pop {
    from { opacity: 0; transform: scale(0.88) translateY(24px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .ee__close {
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
  .ee__close:hover { color: #2A1F54; }
  .ee__close:focus-visible { outline: 2px solid #7C5CFC; outline-offset: 2px; }

  .ee__body {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 40px 32px 36px;
    text-align: center;
  }

  .ee__sigil {
    font-size: 44px;
    margin-bottom: 16px;
    animation: ee-float 2.5s ease-in-out infinite;
  }

  .ee__sigil--glow {
    filter: drop-shadow(0 0 12px rgba(247, 147, 26, 0.6));
  }

  @keyframes ee-float {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-6px); }
  }

  .ee__title {
    font-family: "Fredoka", sans-serif;
    font-size: 14px;
    font-weight: 400;
    color: #d5fd51;
    text-shadow: 0 0 24px rgba(247, 147, 26, 0.25);
    margin-bottom: 12px;
    letter-spacing: 0.08em;
  }

  .ee__title--success {
    color: #3ddc84;
    text-shadow: 0 0 24px rgba(0, 204, 102, 0.3);
  }

  .ee__title--fail {
    color: #ff4d6d;
    text-shadow: 0 0 24px rgba(255, 68, 102, 0.25);
  }

  .ee__riddle {
    font-family: "DM Sans", sans-serif;
    font-size: 13px;
    line-height: 1.8;
    color: #8A7BAA;
    font-style: italic;
    max-width: 330px;
    margin-bottom: 12px;
  }

  .ee__subtitle {
    font-size: 12px;
    line-height: 1.7;
    color: #8A7BAA;
    max-width: 300px;
    margin-bottom: 20px;
  }

  /* Difficulty badge */
  .ee__hint-box {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 8px 0 24px;
    padding: 6px 14px;
    border: 1px solid rgba(42,31,84,0.08);
    border-radius: var(--r-sm);
  }

  .ee__hint-label {
    font-family: "DM Sans", sans-serif;
    font-size: 9px;
    font-weight: 500;
    letter-spacing: 0.12em;
    color: rgba(42,31,84,0.3);
  }

  .ee__hint-value {
    font-family: "DM Sans", sans-serif;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.1em;
    color: #ff4d6d;
  }

  /* Hex input */
  .ee__input-wrap {
    display: flex;
    align-items: center;
    gap: 0;
    margin-bottom: 12px;
    border: 2px solid rgba(42,31,84,0.12);
    border-radius: var(--r-sm);
    padding: 0 16px;
    background: rgba(42,31,84,0.03);
    transition: border-color 0.2s ease;
  }

  .ee__input-wrap:focus-within {
    border-color: #d5fd51;
  }

  .ee__input-wrap--shake {
    animation: ee-shake 0.4s ease;
    border-color: #ff4d6d;
  }

  @keyframes ee-shake {
    0%, 100% { transform: translateX(0); }
    20% { transform: translateX(-8px); }
    40% { transform: translateX(8px); }
    60% { transform: translateX(-4px); }
    80% { transform: translateX(4px); }
  }

  .ee__input-prefix {
    font-family: "DM Mono", "Fira Code", monospace;
    font-size: 22px;
    font-weight: 500;
    color: rgba(42,31,84,0.25);
    user-select: none;
  }

  .ee__input {
    flex: 1;
    border: none;
    background: transparent;
    font-family: "DM Mono", "Fira Code", monospace;
    font-size: 28px;
    font-weight: 600;
    letter-spacing: 0.2em;
    color: #2A1F54;
    padding: 14px 0 14px 4px;
    outline: none;
    width: 120px;
    text-transform: lowercase;
  }

  .ee__input::placeholder {
    color: rgba(42,31,84,0.12);
    letter-spacing: 0.3em;
  }

  .ee__attempt-hint {
    font-family: "DM Sans", sans-serif;
    font-size: 11px;
    color: #ff4d6d;
    margin-bottom: 12px;
    font-style: italic;
  }

  /* Answer reveal */
  .ee__answer-reveal {
    margin-bottom: 16px;
  }

  .ee__hex {
    font-family: "DM Mono", "Fira Code", monospace;
    font-size: 32px;
    font-weight: 700;
    color: #d5fd51;
    letter-spacing: 0.15em;
    text-shadow: 0 0 20px rgba(247, 147, 26, 0.3);
  }

  /* CTA */
  .ee__cta {
    padding: 14px 32px;
    background: #d5fd51;
    color: #F5F0E8;
    border: none;
    border-radius: var(--r-sm);
    font-family: "DM Sans", sans-serif;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.1em;
    cursor: pointer;
    transition: opacity 0.15s ease, box-shadow 0.15s ease;
    text-transform: uppercase;
    width: 100%;
  }

  .ee__cta:hover {
    opacity: 0.9;
    box-shadow: 0 0 28px rgba(247, 147, 26, 0.35);
  }

  .ee__cta:focus-visible {
    outline: 2px solid #7C5CFC;
    outline-offset: 3px;
  }

  .ee__cta:disabled {
    opacity: 0.4;
    cursor: not-allowed;
    box-shadow: none;
  }

  .ee__cta--ghost {
    background: transparent;
    color: #8A7BAA;
    border: 1px solid rgba(42,31,84,0.08);
    margin-top: 8px;
  }

  .ee__cta--ghost:hover {
    color: #2A1F54;
    border-color: rgba(42,31,84,0.12);
    box-shadow: none;
  }

  .ee__cta--claim {
    background: #1DA1F2;
  }

  .ee__cta--claim:hover {
    box-shadow: 0 0 28px rgba(29, 161, 242, 0.35);
  }

  @media (prefers-reduced-motion: reduce) {
    .ee__overlay,
    .ee__modal,
    .ee__sigil,
    .ee__input-wrap--shake {
      animation: none !important;
    }
  }

  @media (max-width: 500px) {
    .ee__body {
      padding: 32px 20px 28px;
    }
    .ee__input {
      font-size: 24px;
    }
    .ee__cta {
      padding: 12px 24px;
    }
  }
`;
