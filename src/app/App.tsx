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

const queryClient = new QueryClient();

export function App() {
  return (
    <ErrorBoundary>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          <HashRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
            <AppLayout>
              <AppRoutes />
            </AppLayout>
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
      </QueryClientProvider>
    </WagmiProvider>
    </ErrorBoundary>
  );
}
