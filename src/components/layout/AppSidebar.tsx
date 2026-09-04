import { useEffect, useState } from "react";
import { Link, useLocation, useSearchParams } from "react-router-dom";
import { useAppStore } from "@/store/useAppStore";
import PresaleModal from "@/components/presale/PresaleModal";
import WalletProfileCard from "./WalletProfileCard";
import { NAV_ITEMS, prefetchRoute, type BadgeKey, type NavItem } from "./navItems";

const MOBILE_BREAKPOINT = 960;

/**
 * The app console's left rail — the single navigation surface on every route
 * under `/cauldrons`, `/mi-frens`, `/docs`. Built from the landing header's
 * type and colour (Cinzel Decorative wordmark, Cinzel uppercase links, lime
 * active marker) so crossing from the marketing page into the app reads as the
 * same product rather than a different site.
 *
 * Under 960px it collapses to a top bar plus a slide-in drawer, driven by the
 * `sidebarOpen` flag that already lives in the app store.
 */
export function AppSidebar() {
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const open = useAppStore((s) => s.sidebarOpen);
  const setOpen = useAppStore((s) => s.setSidebarOpen);
  const cauldronNav = useAppStore((s) => s.cauldronNav);
  const mifrensNav = useAppStore((s) => s.mifrensNav);
  const [showPresale, setShowPresale] = useState(false);

  const activeView = searchParams.get("v") ?? "reactor";

  const isActive = (path: string) =>
    path === "/" ? location.pathname === "/" : location.pathname.startsWith(path);

  // Route changes close the mobile drawer; it should never survive navigation.
  useEffect(() => {
    setOpen(false);
  }, [location.pathname, location.search, setOpen]);

  // Lock body scroll behind the drawer, but only while it is actually overlaying
  // content — on desktop the rail is in normal flow and must not lock anything.
  // Widening past the breakpoint with the drawer open closes it, otherwise the
  // lock would survive into a layout that has no drawer to dismiss.
  useEffect(() => {
    if (!open) return;
    const mq = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT}px)`);
    if (!mq.matches) return;

    document.body.style.overflow = "hidden";
    const onChange = (e: MediaQueryListEvent) => {
      if (!e.matches) setOpen(false);
    };
    mq.addEventListener("change", onChange);
    return () => {
      mq.removeEventListener("change", onChange);
      document.body.style.overflow = "";
    };
  }, [open, setOpen]);

  const badgeCount = (key?: BadgeKey): number => {
    switch (key) {
      case "perps": return cauldronNav.perps;
      case "proposals": return cauldronNav.proposals;
      case "gen": return cauldronNav.gen;
      case "frens": return mifrensNav.frens;
      case "collectibles": return mifrensNav.collectibles;
      default: return 0;
    }
  };

  const logo = (
    <Link to="/" className="rail__logo" onClick={() => setOpen(false)}>
      <img src="/mifrens-logo.svg" alt="" className="rail__logo-img" />
      MiFrens
    </Link>
  );

  const renderItem = (item: NavItem) => {
    const active = isActive(item.path);
    return (
      <div key={item.path} className="rail__group">
        <Link
          to={item.path}
          className={`rail__link${active ? " rail__link--active" : ""}`}
          aria-current={active ? "page" : undefined}
          onMouseEnter={() => prefetchRoute(item.path)}
          onFocus={() => prefetchRoute(item.path)}
        >
          {item.label}
        </Link>

        {/* Sub-items only exist while their section is open, so the rail stays
            short and the current context is always the deepest thing visible. */}
        {active && item.children && (
          <div className="rail__sub">
            {item.children.map((sub) => {
              if (sub.needsSummoned && !cauldronNav.summoned) return null;
              const n = badgeCount(sub.badge);
              const on = activeView === sub.view;
              return (
                <Link
                  key={sub.view}
                  to={`${item.path}?v=${sub.view}`}
                  className={`rail__sublink${on ? " rail__sublink--active" : ""}${
                    sub.hot && n > 0 ? " rail__sublink--hot" : ""
                  }`}
                  aria-current={on ? "true" : undefined}
                >
                  {sub.label}
                  {n > 0 && <span className="rail__badge">{n}</span>}
                </Link>
              );
            })}
          </div>
        )}
      </div>
    );
  };

  return (
    <>
      {/* Mobile-only top bar. Mirrors the landing header's lockup exactly. */}
      <div className="rail-bar">
        {logo}
        <button
          className={`rail-bar__burger${open ? " rail-bar__burger--open" : ""}`}
          onClick={() => setOpen(!open)}
          aria-label="Toggle menu"
          aria-expanded={open}
          aria-controls="app-rail"
        >
          <span />
          <span />
        </button>
      </div>

      {open && <div className="rail__scrim" onClick={() => setOpen(false)} aria-hidden />}

      <aside id="app-rail" className={`rail${open ? " rail--open" : ""}`}>
        <div className="rail__head">{logo}</div>

        <nav className="rail__nav" aria-label="Main">
          {NAV_ITEMS.map(renderItem)}
        </nav>

        <div className="rail__foot">
          <button className="rail__cta" onClick={() => setShowPresale(true)}>
            JOIN GENESIS
          </button>
          <WalletProfileCard />
        </div>
      </aside>

      <PresaleModal isOpen={showPresale} onClose={() => setShowPresale(false)} />

      <style>{`
        .rail {
          position: sticky;
          top: 0;
          z-index: var(--z-rail);
          flex: 0 0 var(--rail-w);
          width: var(--rail-w);
          height: 100vh;
          display: flex;
          flex-direction: column;
          padding: 18px 14px 16px;
          background: rgba(14, 10, 26, 0.72);
          backdrop-filter: blur(20px) saturate(1.1);
          -webkit-backdrop-filter: blur(20px) saturate(1.1);
          border-right: 1px solid rgba(213, 253, 81, 0.10);
        }

        .rail__head { padding: 0 8px 20px; }

        /* Identical lockup to the landing header — same face, size and spacing. */
        .rail__logo {
          display: flex;
          align-items: center;
          gap: 10px;
          font-family: "Cinzel Decorative", serif;
          font-size: 18px;
          font-weight: 700;
          letter-spacing: 0.02em;
          color: var(--cream);
          text-decoration: none;
          white-space: nowrap;
        }
        .rail__logo-img { width: 36px; height: 36px; object-fit: contain; }
        .rail__logo:focus-visible { outline: 2px solid var(--lime); outline-offset: 4px; }

        .rail__nav { display: flex; flex-direction: column; gap: 2px; overflow-y: auto; }
        .rail__group { display: flex; flex-direction: column; }

        /* Landing's link type: Cinzel uppercase, wide tracking. */
        .rail__link {
          padding: 9px 14px;
          border-left: 2px solid transparent;
          font-family: "Cinzel", serif;
          font-size: 13px;
          font-weight: 600;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: rgba(231, 225, 245, 0.62);
          text-decoration: none;
          transition: color 0.18s ease, border-color 0.18s ease;
        }
        .rail__link:hover { color: var(--cream); }
        .rail__link--active { color: var(--cream); border-left-color: var(--lime); }
        .rail__link:focus-visible { outline: 2px solid var(--lime); outline-offset: -2px; }

        /* A spine dropped from the active item's lime marker — the sub-items
           read as children of the open section, not as peers. */
        .rail__sub {
          display: flex;
          flex-direction: column;
          gap: 1px;
          margin: 2px 0 8px 15px;
          border-left: 1px solid rgba(255, 255, 255, 0.07);
        }
        .rail__sublink {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 8px;
          padding: 6px 12px;
          border-radius: var(--r-sm);
          font: 500 12.5px/1.2 "DM Sans", sans-serif;
          color: var(--mute);
          text-decoration: none;
          transition: color 0.15s ease, background 0.15s ease;
        }
        .rail__sublink:hover { color: var(--cream); background: rgba(255, 255, 255, 0.04); }
        .rail__sublink--active { color: var(--lime); background: rgba(213, 253, 81, 0.08); }
        .rail__sublink--hot:not(.rail__sublink--active) { color: var(--lime); }
        .rail__sublink:focus-visible { outline: 2px solid var(--lime); outline-offset: -2px; }

        .rail__badge {
          padding: 1px 6px;
          border-radius: var(--r-chip);
          background: rgba(213, 253, 81, 0.14);
          color: var(--lime);
          font: 600 10px/1.5 "DM Mono", ui-monospace, monospace;
        }

        .rail__foot { margin-top: auto; padding-top: 16px; display: flex; flex-direction: column; gap: 10px; }

        .rail__cta {
          padding: 10px 16px;
          border: none;
          border-radius: var(--r-sm);
          background: var(--lime);
          color: var(--void);
          font-family: "Fredoka", sans-serif;
          font-size: 12.5px;
          font-weight: 700;
          letter-spacing: 0.06em;
          cursor: pointer;
          transition: filter 0.2s ease, box-shadow 0.2s ease;
        }
        .rail__cta:hover { filter: brightness(1.06); box-shadow: 0 4px 16px rgba(213, 253, 81, 0.35); }
        .rail__cta:focus-visible { outline: 2px solid var(--lime); outline-offset: 3px; }

        /* ── mobile: top bar + drawer ── */
        .rail-bar { display: none; }
        .rail__scrim { display: none; }

        @media (max-width: ${MOBILE_BREAKPOINT}px) {
          .rail-bar {
            position: sticky;
            top: 0;
            z-index: var(--z-sticky);
            display: flex;
            align-items: center;
            justify-content: space-between;
            height: var(--hdr-h);
            padding: 0 20px;
            background: rgba(14, 10, 26, 0.82);
            backdrop-filter: blur(16px) saturate(1.1);
            -webkit-backdrop-filter: blur(16px) saturate(1.1);
            border-bottom: 1px solid rgba(213, 253, 81, 0.10);
          }
          .rail-bar .rail__logo { font-size: 15px; }
          .rail-bar .rail__logo-img { width: 28px; height: 28px; }

          .rail-bar__burger {
            display: flex;
            flex-direction: column;
            justify-content: center;
            gap: 6px;
            width: 28px;
            height: 28px;
            padding: 4px;
            border: none;
            background: transparent;
            cursor: pointer;
          }
          .rail-bar__burger span {
            display: block;
            width: 100%;
            height: 2px;
            border-radius: 1px;
            background: var(--cream);
            transition: transform 0.2s ease;
          }
          .rail-bar__burger--open span:first-child { transform: translateY(4px) rotate(45deg); }
          .rail-bar__burger--open span:last-child { transform: translateY(-4px) rotate(-45deg); }
          .rail-bar__burger:focus-visible { outline: 2px solid var(--lime); outline-offset: 3px; }

          .rail__scrim {
            display: block;
            position: fixed;
            inset: 0;
            z-index: var(--z-overlay);
            background: rgba(6, 4, 12, 0.6);
            backdrop-filter: blur(2px);
          }

          .rail {
            position: fixed;
            top: 0;
            left: 0;
            bottom: 0;
            height: 100dvh;
            z-index: var(--z-modal);
            transform: translateX(-100%);
            /* visibility (not just transform) so a closed drawer is out of the
               tab order and hidden from screen readers, instead of an
               invisible off-screen menu you can still tab into. */
            visibility: hidden;
            transition: transform 0.24s cubic-bezier(0.2, 0.9, 0.3, 1),
                        visibility 0.24s;
            border-right: 1px solid rgba(213, 253, 81, 0.16);
            background: rgba(14, 10, 26, 0.97);
          }
          .rail--open { transform: none; visibility: visible; }
          .rail__head { display: none; }
          .rail__nav { padding-top: 8px; }
        }

        @media (prefers-reduced-motion: reduce) {
          .rail { transition: none; }
        }
      `}</style>
    </>
  );
}

export default AppSidebar;
