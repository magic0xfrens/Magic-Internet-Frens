import { useState, useCallback, useEffect } from "react";
import { Link, useLocation } from "react-router-dom";
import { useWallet } from "@/hooks/useWallet";
import PresaleModal from "@/components/presale/PresaleModal";
import { NAV_ITEMS, prefetchRoute, truncateAddress } from "./navItems";

/**
 * The landing-page navigation. App routes render `AppSidebar` instead, so this
 * bar no longer needs the old dark-glass variant — the rail owns that surface.
 */
export function AppHeader() {
  const location = useLocation();
  const { isConnected, walletAddress, disconnect } = useWallet();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [showPresale, setShowPresale] = useState(false);
  const [scrolled, setScrolled] = useState(false);

  const isHome = location.pathname === "/" || location.pathname === "";

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

  // The bar floats transparent over the hero, then fades in a glass fill once
  // it is over real content — otherwise nav text competes with the page.
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 80);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const isActive = (path: string) => {
    if (path === "/" && location.pathname === "/") return true;
    if (path !== "/" && location.pathname.startsWith(path)) return true;
    return false;
  };

  return (
    <header
      className={`hdr${isHome ? " hdr--home" : ""}${scrolled ? " hdr--scrolled" : ""}`}
    >
      <div className="hdr__inner">
        <Link to="/" className="hdr__logo" onClick={closeMobile}>
          <img
            src="/mifrens-logo.svg"
            alt=""
            className="hdr__logo-img"
          />
          MiFrens
        </Link>

        <nav className="hdr__nav" aria-label="Main">
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.path}
              to={item.path}
              className={`hdr__link${isActive(item.path) ? " hdr__link--active" : ""}`}
              aria-current={isActive(item.path) ? "page" : undefined}
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
              <button className="hdr__disconnect" onClick={() => disconnect()}>
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
            aria-expanded={mobileOpen}
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
          z-index: var(--z-sticky);
          width: 100%;
          /* Transparent glass — the page background shows through on every tab.
             A light blur + hairline keeps nav text legible over any content. */
          background: rgba(245, 240, 232, 0.45);
          backdrop-filter: blur(16px) saturate(1.1);
          -webkit-backdrop-filter: blur(16px) saturate(1.1);
          border-bottom: 1px solid rgba(42, 31, 84, 0.06);
        }

        /* Home: an inset floating bar rather than an edge-to-edge strip, so the
           hero reads as art the nav sits on top of. */
        .hdr--home {
          position: fixed;
          top: 16px;
          left: 16px;
          right: 16px;
          width: auto;
          border-radius: var(--r-md);
          background: transparent;
          backdrop-filter: none;
          -webkit-backdrop-filter: none;
          border-bottom: none;
          transition: background 0.25s ease, backdrop-filter 0.25s ease,
                      box-shadow 0.25s ease;
        }

        /* Past the hero the bar earns a fill so links stay readable. The 0.86
           alpha is not arbitrary: over the cream page below, anything lighter
           drops the 70%-white nav links under 4.5:1. */
        .hdr--home.hdr--scrolled {
          background: rgba(23, 17, 47, 0.86);
          backdrop-filter: blur(18px) saturate(1.15);
          -webkit-backdrop-filter: blur(18px) saturate(1.15);
          box-shadow: 0 10px 34px rgba(14, 10, 26, 0.28);
        }

        .hdr__inner {
          max-width: 1100px;
          margin: 0 auto;
          padding: 0 24px;
          height: var(--hdr-h);
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
          color: var(--ink);
          text-decoration: none;
          letter-spacing: 0.02em;
          white-space: nowrap;
        }

        .hdr--home .hdr__logo {
          color: #FFFFFF;
          text-shadow: 0 1px 8px rgba(0,0,0,0.3);
        }

        .hdr__logo:focus-visible { outline: 2px solid var(--lime); outline-offset: 4px; }

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
          color: var(--ink);
        }

        .hdr--home .hdr__link:hover {
          color: var(--lime);
        }

        .hdr__link:focus-visible {
          outline: 2px solid var(--lime);
          outline-offset: 3px;
          border-radius: var(--r-xs);
        }

        .hdr__link--active {
          color: var(--ink);
          text-decoration: underline;
          text-underline-offset: 4px;
          text-decoration-color: var(--lime);
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
          background: var(--lime);
          color: var(--ink);
          border: none;
          border-radius: var(--r-sm);
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
          outline: 2px solid var(--lime);
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
          border-radius: var(--r-sm);
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
          border-radius: var(--r-sm);
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
          color: var(--red);
          border-color: var(--red);
        }

        .hdr__disconnect:focus-visible {
          outline: 2px solid var(--lime);
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
          background: var(--ink);
          border-radius: 1px;
          transition: transform 0.2s ease, opacity 0.2s ease;
        }

        .hdr--home .hdr__burger span {
          background: #FFFFFF;
        }

        .hdr__burger:focus-visible { outline: 2px solid var(--lime); outline-offset: 3px; }

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
          border-radius: 0 0 var(--r-md) var(--r-md);
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
          color: var(--ink);
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

          /* The drawer needs an opaque bar behind it on mobile. */
          .hdr--home {
            background: rgba(23, 17, 47, 0.88);
            backdrop-filter: blur(18px) saturate(1.15);
            -webkit-backdrop-filter: blur(18px) saturate(1.15);
          }
        }

        @media (prefers-reduced-motion: reduce) {
          .hdr--home { transition: none; }
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
