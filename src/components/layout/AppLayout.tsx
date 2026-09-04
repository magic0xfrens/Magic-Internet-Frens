import { useEffect, type FC, type ReactNode } from "react";
import { useLocation } from "react-router-dom";
import { AppHeader } from "./AppHeader";
import { AppSidebar } from "./AppSidebar";
import { isAppRoute } from "./navItems";

interface AppLayoutProps {
  children: ReactNode;
}

/**
 * Two shells, one design language.
 *
 * The landing page keeps its floating top bar. Everything under the app routes
 * renders the left rail instead — same wordmark, same link type, same lime
 * accent — so navigation is one persistent surface rather than a header that
 * changes personality between marketing and product.
 */
export const AppLayout: FC<AppLayoutProps> = ({ children }) => {
  const location = useLocation();
  const isApp = isAppRoute(location.pathname);

  // App routes paint near-black; the rail and the page both sit on it, so the
  // body has to be dark too or a light strip shows through at the scroll ends.
  useEffect(() => {
    document.body.style.background = isApp ? "#0E0A1A" : "";
    return () => {
      document.body.style.background = "";
    };
  }, [isApp]);

  return (
    <div className={`app-layout${isApp ? " app-layout--app" : ""}`}>
      <a href="#main-content" className="skip-nav">
        Skip to main content
      </a>

      {isApp ? (
        <div className="shell">
          {/* Film grain spans rail + content so the texture doesn't stop at the
              rail edge the way it did when it lived inside the Cauldron page. */}
          <div className="shell__grain" aria-hidden />
          <AppSidebar />
          <main id="main-content" className="shell__main">
            {children}
          </main>
        </div>
      ) : (
        <>
          <AppHeader />
          <main id="main-content" className="app-main">
            {children}
          </main>
        </>
      )}

      <style>{`
        .skip-nav {
          position: absolute;
          top: -100%;
          left: 16px;
          z-index: var(--z-toast);
          padding: 8px 16px;
          background: var(--lime);
          color: var(--void);
          font-family: "DM Sans", sans-serif;
          font-size: 12px;
          font-weight: 600;
          text-decoration: none;
          letter-spacing: 0.08em;
          border-radius: var(--r-sm);
        }

        .skip-nav:focus { top: 8px; }

        .app-layout { min-height: 100vh; }

        .app-main { min-height: calc(100vh - var(--hdr-h)); }

        .shell {
          position: relative;
          display: flex;
          align-items: flex-start;
          min-height: 100vh;
          background: var(--void);
        }

        .shell__grain {
          position: fixed;
          inset: 0;
          z-index: var(--z-raised);
          pointer-events: none;
          opacity: 0.05;
          background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
        }

        .shell__main {
          flex: 1 1 auto;
          min-width: 0;
          padding: 0 28px;
        }

        @media (max-width: 960px) {
          /* The rail becomes a fixed drawer, so the shell is a single column
             under the mobile top bar. */
          .shell { display: block; }
          .shell__main { padding: 0 16px; }
        }
      `}</style>
    </div>
  );
};
