import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useWallet } from "@/hooks/useWallet";
import { useUserNFTs } from "@/hooks/useUserNFTs";
import { frenFromSeed } from "@/data/frens";
import FrenSprite from "@/components/shared/FrenSprite";
import { explorerAddressUrl, NETWORK_SHORT } from "@/config/chains";
import { truncateAddress } from "./navItems";

/**
 * Bottom-of-rail identity card.
 *
 * Disconnected it is a single CONNECT button; connected it shows the wallet's
 * own MiFren as the avatar, the address, the ETH balance and the network, and
 * opens a menu on click. The avatar is the whole point — a holder should see
 * their fren on every screen, not just `/mi-frens`.
 */

/** Cheap deterministic hash of an address → seed for the fallback sprite. */
function addressSeed(addr: string): number {
  let h = 0;
  for (let i = 2; i < addr.length; i++) h = (h * 31 + addr.charCodeAt(i)) >>> 0;
  return h;
}

export function WalletProfileCard() {
  const navigate = useNavigate();
  const {
    isConnected,
    walletAddress,
    walletBalance,
    isCorrectNetwork,
    openConnectModal,
    disconnect,
    switchToActive,
  } = useWallet();

  const { nfts } = useUserNFTs();
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  /* The rarest owned fren represents the wallet; ties break to the lowest id so
     the avatar is stable across refetches rather than flickering between equals. */
  const avatarNft = useMemo(() => {
    const owned = nfts.filter((n) => !n.isPending && n.bodyFile);
    if (owned.length === 0) return null;
    return owned.reduce((best, n) => {
      const br = best.rarity ?? 0;
      const nr = n.rarity ?? 0;
      if (nr !== br) return nr > br ? n : best;
      return n.tokenId < best.tokenId ? n : best;
    });
  }, [nfts]);

  /* No frens yet — still render a fren, seeded off the address, so the card
     never falls back to a grey blob. */
  const fallbackFren = useMemo(
    () => (walletAddress ? frenFromSeed(addressSeed(walletAddress)) : null),
    [walletAddress],
  );

  const avatar = avatarNft ?? fallbackFren;

  // Close the menu on outside-click and Escape.
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const copyAddress = useCallback(() => {
    if (!walletAddress) return;
    navigator.clipboard?.writeText(walletAddress).then(
      () => {
        setCopied(true);
        setTimeout(() => setCopied(false), 1400);
      },
      () => {},
    );
  }, [walletAddress]);

  if (!isConnected || !walletAddress) {
    return (
      <div className="wpc">
        <button className="wpc__connect" onClick={() => openConnectModal()}>
          CONNECT
        </button>
        <style>{CSS}</style>
      </div>
    );
  }

  const balance = walletBalance ? Number(walletBalance) : null;

  return (
    <div className="wpc" ref={rootRef}>
      {open && (
        <div className="wpc__menu" role="menu">
          <button
            className="wpc__item"
            role="menuitem"
            onClick={() => {
              navigate("/mi-frens");
              setOpen(false);
            }}
          >
            My Frens
            <span className="wpc__item-chev" aria-hidden>
              ›
            </span>
          </button>
          <button className="wpc__item" role="menuitem" onClick={copyAddress}>
            {copied ? "Copied" : "Copy address"}
          </button>
          <a
            className="wpc__item"
            role="menuitem"
            href={explorerAddressUrl(walletAddress)}
            target="_blank"
            rel="noopener noreferrer"
            onClick={() => setOpen(false)}
          >
            View on explorer
            <span className="wpc__item-chev" aria-hidden>
              ↗
            </span>
          </a>
          <div className="wpc__sep" />
          <button
            className="wpc__item wpc__item--danger"
            role="menuitem"
            onClick={() => {
              disconnect();
              setOpen(false);
            }}
          >
            Disconnect
          </button>
        </div>
      )}

      <button
        className={`wpc__card${open ? " wpc__card--open" : ""}`}
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="menu"
        aria-expanded={open}
      >
        <span className="wpc__avatar">
          {avatar && (
            <FrenSprite
              bodyFile={avatar.bodyFile}
              faceFile={avatar.faceFile}
              itemFile={avatar.itemFile}
              bodyIdx={avatar.bodyIdx}
              faceIdx={avatar.faceIdx}
              itemIdx={avatar.itemIdx}
              alt={avatarNft ? `MiFren #${avatarNft.tokenId}` : "Your wallet"}
            />
          )}
        </span>
        <span className="wpc__id">
          <span className="wpc__addr">{truncateAddress(walletAddress)}</span>
          <span className="wpc__sub">
            {avatarNft ? `MiFren #${avatarNft.tokenId}` : "No frens yet"}
          </span>
        </span>
      </button>

      <div className="wpc__meta">
        <span className="wpc__bal">
          {balance === null ? "—" : balance.toFixed(3)} <em>Ξ</em>
        </span>
        {isCorrectNetwork ? (
          <span className="wpc__net">
            <span className="wpc__dot" />
            {NETWORK_SHORT}
          </span>
        ) : (
          <button className="wpc__net wpc__net--bad" onClick={() => switchToActive()}>
            <span className="wpc__dot" />
            Switch network
          </button>
        )}
      </div>

      <style>{CSS}</style>
    </div>
  );
}

const CSS = `
  .wpc { position: relative; padding: 12px; border-radius: var(--r-md);
    border: 1px solid rgba(255,255,255,0.07); background: rgba(14,10,26,0.55); }

  .wpc__connect { width: 100%; padding: 10px 14px; border: none; border-radius: var(--r-sm);
    background: var(--lime); color: var(--void); cursor: pointer;
    font: 700 12px/1 "Fredoka", sans-serif; letter-spacing: 0.08em;
    transition: filter .18s ease, box-shadow .18s ease; }
  .wpc__connect:hover { filter: brightness(1.06); box-shadow: 0 4px 16px rgba(213,253,81,0.35); }
  .wpc__connect:focus-visible { outline: 2px solid var(--lime); outline-offset: 3px; }

  .wpc__card { display: flex; align-items: center; gap: 10px; width: 100%;
    padding: 0; border: none; background: none; cursor: pointer; text-align: left; }
  .wpc__card:focus-visible { outline: 2px solid var(--lime); outline-offset: 4px;
    border-radius: var(--r-sm); }

  .wpc__avatar { flex: 0 0 auto; width: 36px; height: 36px; overflow: hidden;
    border-radius: var(--r-full); box-shadow: 0 0 0 1px rgba(213,253,81,0.28);
    transition: box-shadow .18s ease; }
  .wpc__card:hover .wpc__avatar,
  .wpc__card--open .wpc__avatar { box-shadow: 0 0 0 1px var(--lime), 0 0 14px rgba(213,253,81,0.3); }

  .wpc__id { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .wpc__addr { font: 500 12.5px/1.2 "DM Mono", ui-monospace, monospace; color: var(--cream);
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .wpc__sub { font: 400 10.5px/1.2 "DM Sans", sans-serif; color: var(--mute);
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .wpc__meta { display: flex; align-items: center; justify-content: space-between; gap: 8px;
    margin-top: 10px; padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.06); }
  .wpc__bal { font: 600 12.5px/1 "DM Sans", sans-serif; color: var(--cream); }
  .wpc__bal em { font-style: normal; color: var(--mute); font-weight: 400; }

  .wpc__net { display: inline-flex; align-items: center; gap: 5px;
    padding: 3px 7px; border-radius: var(--r-chip);
    border: 1px solid rgba(61,220,132,0.28); background: rgba(61,220,132,0.08);
    font: 500 10px/1 "DM Sans", sans-serif; letter-spacing: 0.04em; color: var(--green); }
  .wpc__net--bad { cursor: pointer; border-color: rgba(255,77,109,0.35);
    background: rgba(255,77,109,0.1); color: var(--red); }
  .wpc__net--bad:hover { background: rgba(255,77,109,0.18); }
  .wpc__net--bad:focus-visible { outline: 2px solid var(--red); outline-offset: 2px; }
  .wpc__dot { width: 5px; height: 5px; border-radius: var(--r-full);
    background: currentColor; box-shadow: 0 0 6px currentColor; }

  /* Opens upward — the card is pinned to the bottom of the rail. */
  .wpc__menu { position: absolute; left: 12px; right: 12px; bottom: calc(100% - 4px);
    z-index: var(--z-overlay); display: flex; flex-direction: column; padding: 5px;
    border-radius: var(--r-md); border: 1px solid rgba(255,255,255,0.09);
    background: rgba(20,15,38,0.97); backdrop-filter: blur(14px);
    box-shadow: 0 14px 40px rgba(0,0,0,0.55);
    animation: wpc-in .16s cubic-bezier(0.2,0.9,0.3,1); }
  @keyframes wpc-in { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }

  .wpc__item { display: flex; align-items: center; justify-content: space-between; gap: 8px;
    width: 100%; padding: 8px 10px; border: none; border-radius: var(--r-sm);
    background: none; color: var(--dim); cursor: pointer; text-align: left;
    font: 500 12.5px/1 "DM Sans", sans-serif; transition: background .15s ease, color .15s ease; }
  .wpc__item:hover { background: rgba(213,253,81,0.09); color: var(--cream); }
  .wpc__item:focus-visible { outline: 2px solid var(--lime); outline-offset: -2px; }
  .wpc__item--danger:hover { background: rgba(255,77,109,0.12); color: var(--red); }
  .wpc__item-chev { color: var(--mute); font-size: 13px; }
  .wpc__sep { height: 1px; margin: 4px 6px; background: rgba(255,255,255,0.07); }

  @media (prefers-reduced-motion: reduce) {
    .wpc__menu { animation: none; }
  }
`;

export default WalletProfileCard;
