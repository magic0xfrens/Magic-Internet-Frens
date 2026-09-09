import { WagmiProvider } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RainbowKitProvider } from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";
import { HashRouter } from "react-router-dom";
import { Toaster } from "react-hot-toast";
import { AppRoutes } from "./routes";
import { AppLayout } from "@/components/layout/AppLayout";
import { wagmiConfig } from "@/config/chains";
import { ErrorBoundary } from "@/components/shared/ErrorBoundary";
import { WagmiClientGate } from "@/components/shared/WagmiClientGate";
import { IndexerHealthBanner } from "@/components/shared/IndexerHealthBanner";

const queryClient = new QueryClient();

export function App() {
  return (
    <ErrorBoundary>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <WagmiClientGate>
        <RainbowKitProvider>
          <HashRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
            <AppLayout>
              <AppRoutes />
            </AppLayout>
            {/* App-wide staleness signal. Most of the page reads the indexer
                with no chain fallback, so when it diverges the honest thing is
                to say so on EVERY route, not just the one that happened to
                check. See {IndexerHealthBanner} (audit A-3). */}
            <IndexerHealthBanner />
            <Toaster
              position="bottom-right"
              toastOptions={{
                style: {
                  background: "#FBF7F0",
                  color: "#2A1F54",
                  border: "1px solid rgba(42,31,84,0.12)",
                  borderRadius: "var(--r-md)",
                  fontFamily: '"DM Sans", sans-serif',
                  fontSize: "13px",
                },
              }}
            />
          </HashRouter>
        </RainbowKitProvider>
        </WagmiClientGate>
      </QueryClientProvider>
    </WagmiProvider>
    </ErrorBoundary>
  );
}
