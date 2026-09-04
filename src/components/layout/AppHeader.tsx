import { useState, useCallback, useEffect } from "react";
import { Link, useLocation } from "react-router-dom";
import { useWallet } from "@/hooks/useWallet";
import PresaleModal from "@/components/presale/PresaleModal";

const NAV_ITEMS = [
  { label: "HOME", path: "/" },
  { label: "MI FRENS", path: "/mi-frens" },
  { label: "THE CAULDRON", path: "/cauldrons" },
];

/**
 * Route chunk prefetchers — fired on nav hover/focus so the lazy chunk is
 * already in cache by the time the user clicks (navigation feels instant).
 * Vite dedupes the dynamic import, so calling it early just warms the cache.
 */
const PREFETCH: Record<string, () => Promise<unknown>> = {
  "/": () => import("@/components/preview/HomePreview"),
  "/mi-frens": () => import("@/components/wizards/MyWizards"),
  "/cauldrons": () => import("@/components/cauldron/TheCauldron"),
  "/token": () => import("@/components/token/Token"),
};
const prefetched = new Set<string>();
function prefetchRoute(path: string) {
  if (prefetched.has(path)) return;
  prefetched.add(path);
  PREFETCH[path]?.().catch(() => prefetched.delete(path));
}

function truncateAddress(addr: string): string {
  if (!addr || addr.length < 12) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export function AppHeader() {
  const location = useLocation();
  const { isConnected, walletAddress, disconnect } =
    useWallet();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [showPresale, setShowPresale] = useState(false);

  const isHome = location.pathname === "/" || location.pathname === "";
  // Dark-themed routes (Cauldron console + MiFrens vault) get the transparent
  // dark-glass bar so it blends into their near-black background instead of the
  // default cream bar.
  const isDark = location.pathname.startsWith("/cauldrons")
    || location.pathname.startsWith("/mi-frens");

  const toggleMobile = useCallback(() => {
    setMobileOpen((prev) => !prev);
  }, []);

  const closeMobile = useCallback(() => {
    setMobileOpen(false);
  }, []);

  useEffect(() => {
    if (mobileOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => { document.body.style.overflow = ""; };
  }, [mobileOpen]);

  // Dark routes paint the page background near-black. The header is a transparent
  // glass bar, so the body must be dark BEHIND it too — otherwise the sticky bar
  // sits over the light app-root and reads as a flat gray strip.
  useEffect(() => {
    document.body.style.background = isDark ? "#0E0A1A" : "";
    return () => { document.body.style.background = ""; };
  }, [isDark]);

  const isActive = (path: string) => {
    if (path === "/" && location.pathname === "/") return true;
    if (path !== "/" && location.pathname.startsWith(path)) return true;
    return false;
  };

  return (
    <header className={`hdr${isHome ? " hdr--home" : ""}${isDark ? " hdr--dark" : ""}`}>
      <div className="hdr__inner">
        <Link to="/" className="hdr__logo" onClick={closeMobile}>
          <img
            src="/mifrens-logo.svg"
            alt="MiFrens"
            className="hdr__logo-img"
          />
          MiFrens
        </Link>

        <nav className="hdr__nav">
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.path}
              to={item.path}
              className={`hdr__link${isActive(item.path) ? " hdr__link--active" : ""}`}
              onMouseEnter={() => prefetchRoute(item.path)}
              onFocus={() => prefetchRoute(item.path)}
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="hdr__actions">
          {isConnected && (
            <div className="hdr__wallet">
              <span className="hdr__addr">
                {truncateAddress(walletAddress ?? "")}
              </span>
              <button className="hdr__disconnect" onClick={disconnect}>
                DISCONNECT
              </button>
            </div>
          )}
          {/* JOIN PRESALE is always available — connected or not — so every
              entry point (header, home, cauldron) opens the same modal. */}
          <button className="hdr__connect" onClick={() => setShowPresale(true)}>
            JOIN GENESIS
          </button>

          <button
            className={`hdr__burger${mobileOpen ? " hdr__burger--open" : ""}`}
            onClick={toggleMobile}
            aria-label="Toggle menu"
          >
            <span />
            <span />
          </button>
        </div>
      </div>

      {mobileOpen && (
        <div className="hdr__drawer">
          <nav className="hdr__drawer-nav">
            {NAV_ITEMS.map((item) => (
              <Link
                key={item.path}
                to={item.path}
                className={`hdr__drawer-link${
                  isActive(item.path) ? " hdr__drawer-link--active" : ""
                }`}
                onClick={closeMobile}
                onTouchStart={() => prefetchRoute(item.path)}
              >
                {item.label}
              </Link>
            ))}
          </nav>

          {isConnected && (
            <div className="hdr__drawer-wallet">
              <span className="hdr__addr">
                {truncateAddress(walletAddress ?? "")}
              </span>
              <button
                className="hdr__disconnect"
                onClick={() => {
                  disconnect();
                  closeMobile();
                }}
              >
                DISCONNECT
              </button>
            </div>
          )}
          {/* Same presale entry in the mobile drawer, always available. */}
          <button
            className="hdr__connect"
            onClick={() => {
              setShowPresale(true);
              closeMobile();
            }}
          >
            JOIN GENESIS
          </button>
        </div>
      )}

      <style>{`
        .hdr {
          position: sticky;
          top: 0;
          z-index: 100;
          width: 100%;
          /* Transparent glass — the page background shows through on every tab.
             A light blur + hairline keeps nav text legible over any content. */
          background: rgba(245, 240, 232, 0.45);
          backdrop-filter: blur(16px) saturate(1.1);
          -webkit-backdrop-filter: blur(16px) saturate(1.1);
          border-bottom: 1px solid rgba(42, 31, 84, 0.06);
        }

        .hdr--home {
          position: absolute;
          background: transparent;
          backdrop-filter: none;
          -webkit-backdrop-filter: none;
          border-bottom: none;
        }

        /* Dark routes (Cauldron, MiFrens) — transparent dark glass so the
           near-black page background shows through the bar. */
        .hdr--dark {
          background: rgba(14, 10, 26, 0.4);
          border-bottom: 1px solid rgba(213, 253, 81, 0.12);
        }
        .hdr--dark .hdr__logo { color: #F5F0E8; }
        .hdr--dark .hdr__link { color: rgba(231, 225, 245, 0.62); }
        .hdr--dark .hdr__link:hover { color: #d5fd51; }
        .hdr--dark .hdr__link--active {
          color: #F5F0E8;
          text-decoration-color: #d5fd51;
        }
        .hdr--dark .hdr__addr { color: #E7E1F5; }

        .hdr__inner {
          max-width: 1100px;
          margin: 0 auto;
          padding: 0 24px;
          height: 56px;
          display: flex;
          align-items: center;
          justify-content: space-between;
        }

        .hdr__logo {
          display: flex;
          align-items: center;
          gap: 10px;
          font-family: "Cinzel Decorative", serif;
          font-size: 18px;
          font-weight: 700;
          color: #2A1F54;
          text-decoration: none;
          letter-spacing: 0.02em;
          white-space: nowrap;
        }

        .hdr--home .hdr__logo {
          color: #FFFFFF;
          text-shadow: 0 1px 8px rgba(0,0,0,0.3);
        }

        .hdr__logo-img {
          width: 36px;
          height: 36px;
          object-fit: contain;
        }

        .hdr__nav {
          display: flex;
          align-items: center;
          gap: 0;
        }

        .hdr__link {
          padding: 8px 18px;
          font-family: "Cinzel", serif;
          font-size: 13px;
          font-weight: 600;
          letter-spacing: 0.1em;
          color: #8A7BAA;
          text-decoration: none;
          text-transform: uppercase;
          transition: color 0.2s ease;
        }

        .hdr--home .hdr__link {
          color: rgba(255, 255, 255, 0.7);
        }

        .hdr__link:hover {
          color: #2A1F54;
        }

        .hdr--home .hdr__link:hover {
          color: #d5fd51;
        }

        .hdr__link:focus-visible {
          outline: 2px solid #7C5CFC;
          outline-offset: 3px;
        }

        .hdr__link--active {
          color: #2A1F54;
          text-decoration: underline;
          text-underline-offset: 4px;
          text-decoration-color: #d5fd51;
        }

        .hdr--home .hdr__link--active {
          color: #FFFFFF;
        }

        .hdr__actions {
          display: flex;
          align-items: center;
          gap: 12px;
        }

        .hdr__connect {
          padding: 8px 22px;
          background: #d5fd51;
          color: #2A1F54;
          border: none;
          border-radius: 24px;
          font-family: "Fredoka", sans-serif;
          font-size: 13px;
          font-weight: 700;
          letter-spacing: 0.06em;
          cursor: pointer;
          transition: transform 0.2s ease, box-shadow 0.2s ease;
        }

        .hdr__connect:hover {
          transform: translateY(-1px);
          box-shadow: 0 4px 14px rgba(213, 253, 81, 0.45);
        }

        .hdr__connect:focus-visible {
          outline: 2px solid #7C5CFC;
          outline-offset: 3px;
        }

        .hdr__wallet {
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .hdr__addr {
          padding: 6px 14px;
          background: rgba(42, 31, 84, 0.06);
          border: 1px solid rgba(42, 31, 84, 0.12);
          border-radius: 20px;
          font-size: 12px;
          font-weight: 500;
          color: #8a7baa;
          font-family: "DM Sans", sans-serif;
        }

        .hdr--home .hdr__addr {
          background: rgba(255, 255, 255, 0.15);
          border-color: rgba(255, 255, 255, 0.2);
          color: rgba(255, 255, 255, 0.8);
        }

        .hdr__disconnect {
          padding: 6px 14px;
          background: transparent;
          border: 1px solid rgba(42, 31, 84, 0.12);
          border-radius: 20px;
          color: #8A7BAA;
          font-family: "DM Sans", sans-serif;
          font-size: 11px;
          font-weight: 500;
          letter-spacing: 0.08em;
          cursor: pointer;
          transition: color 0.2s ease, border-color 0.2s ease;
        }

        .hdr--home .hdr__disconnect {
          border-color: rgba(255, 255, 255, 0.2);
          color: rgba(255, 255, 255, 0.7);
        }

        .hdr__disconnect:hover {
          color: #ff4d6d;
          border-color: #ff4d6d;
        }

        .hdr__disconnect:focus-visible {
          outline: 2px solid #7C5CFC;
          outline-offset: 3px;
        }

        .hdr__burger {
          display: none;
          flex-direction: column;
          justify-content: center;
          gap: 6px;
          width: 28px;
          height: 28px;
          border: none;
          background: transparent;
          cursor: pointer;
          padding: 4px;
        }

        .hdr__burger span {
          display: block;
          width: 100%;
          height: 2px;
          background: #2A1F54;
          border-radius: 1px;
          transition: transform 0.2s ease, opacity 0.2s ease;
        }

        .hdr--home .hdr__burger span {
          background: #FFFFFF;
        }

        .hdr__burger--open span:first-child {
          transform: translateY(4px) rotate(45deg);
        }

        .hdr__burger--open span:last-child {
          transform: translateY(-4px) rotate(-45deg);
        }

        .hdr__drawer {
          display: none;
          flex-direction: column;
          gap: 16px;
          padding: 20px 24px;
          border-top: 1px solid rgba(42, 31, 84, 0.08);
          background: #FBF7F0;
        }

        .hdr__drawer-nav {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }

        .hdr__drawer-link {
          padding: 12px 0;
          font-family: "Cinzel", serif;
          font-size: 14px;
          font-weight: 600;
          letter-spacing: 0.1em;
          color: #8A7BAA;
          text-decoration: none;
          text-transform: uppercase;
          border-bottom: 1px solid rgba(42, 31, 84, 0.06);
          transition: color 0.2s ease;
        }

        .hdr__drawer-link:hover,
        .hdr__drawer-link--active {
          color: #d5fd51;
        }

        .hdr__drawer-wallet {
          display: flex;
          align-items: center;
          gap: 10px;
        }

        @media (max-width: 768px) {
          .hdr__nav {
            display: none;
          }

          .hdr__actions > .hdr__wallet,
          .hdr__actions > .hdr__connect {
            display: none;
          }

          .hdr__burger {
            display: flex;
          }

          .hdr__drawer {
            display: flex;
          }

          .hdr__logo {
            font-size: 15px;
          }
        }
      `}</style>

      {/* Presale Modal */}
      <PresaleModal
        isOpen={showPresale}
        onClose={() => setShowPresale(false)}
      />
    </header>
  );
}
