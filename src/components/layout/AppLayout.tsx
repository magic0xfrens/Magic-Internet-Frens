import type { FC, ReactNode } from "react";
import { AppHeader } from "./AppHeader";

interface AppLayoutProps {
  children: ReactNode;
}

export const AppLayout: FC<AppLayoutProps> = ({ children }) => {
  return (
    <div className="app-layout">
      <a href="#main-content" className="skip-nav">
        Skip to main content
      </a>
      <AppHeader />
      <main id="main-content" className="app-main">{children}</main>

      <style>{`
        .skip-nav {
          position: absolute;
          top: -100%;
          left: 16px;
          z-index: 9999;
          padding: 8px 16px;
          background: #d5fd51;
          color: #FFFFFF;
          font-family: "DM Sans", sans-serif;
          font-size: 12px;
          font-weight: 600;
          text-decoration: none;
          letter-spacing: 0.08em;
          border-radius: 8px;
        }

        .skip-nav:focus {
          top: 8px;
        }

        .app-layout {
          min-height: 100vh;
        }

        .app-main {
          min-height: calc(100vh - 56px);
        }
      `}</style>
    </div>
  );
};
