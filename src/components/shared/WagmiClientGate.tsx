import { useEffect, useRef, useState, type ReactNode } from "react";
import { usePublicClient } from "wagmi";
import { wagmiConfig, ACTIVE_CHAIN_ID } from "@/config/chains";

/**
 * Keeps RainbowKit from mounting without a viem client.
 *
 * `usePublicClient()` is typed `Client | undefined` for a reason: wagmi's
 * `getClient` wraps `config.getClient()` in a bare try/catch and returns
 * `undefined` on ANY throw — an unresolvable `state.chainId`, a transport that
 * fails to construct, storage the browser refuses to read. RainbowKit 2.2.11
 * then does `getTransactionProvider(provider)` → `` `${provider.uid}.…` ``
 * inside the `TransactionStoreProvider` useState initializer with no guard, so
 * that `undefined` becomes "Cannot read properties of undefined (reading 'uid')"
 * and the whole app white-screens — on that one user's machine only, which makes
 * it look like a phantom.
 *
 * So: if the client is missing, try once to heal the most likely cause (a store
 * chainId that no longer resolves) by pinning state back to the active chain.
 * If that doesn't take, show a reset card instead of crashing. Delete this gate
 * when RainbowKit ships a null-check upstream.
 */
export function WagmiClientGate({ children }: { children: ReactNode }) {
  const client = usePublicClient();
  const healAttempted = useRef(false);
  const [gaveUp, setGaveUp] = useState(false);

  useEffect(() => {
    if (client || healAttempted.current) return;
    healAttempted.current = true;
    try {
      wagmiConfig.setState((s) => ({ ...s, chainId: ACTIVE_CHAIN_ID }));
    } catch {
      /* fall through to the reset card */
    }
    // If the re-pin worked, `client` is defined on the next render and this
    // never fires. If it didn't, the config is broken beyond a chain swap.
    const t = setTimeout(() => setGaveUp(true), 0);
    return () => clearTimeout(t);
  }, [client]);

  if (client) return <>{children}</>;
  if (!gaveUp) return null; // one frame while the re-pin lands
  return <ResetCard />;
}

/** Nukes wagmi's persisted store and reloads — clears a poisoned connection. */
function ResetCard() {
  const reset = () => {
    try {
      for (const key of Object.keys(localStorage)) {
        if (key.startsWith("wagmi.") || key.startsWith("rk-")) localStorage.removeItem(key);
      }
    } catch {
      /* storage blocked — the reload alone may still help */
    }
    location.reload();
  };

  return (
    <div style={wrap}>
      <div style={card}>
        <div style={{ fontSize: 34, marginBottom: 6 }}>🧙‍♂️</div>
        <h1 style={h1}>Your wallet session got tangled</h1>
        <p style={p}>
          The saved connection points at a network this build no longer serves.
          Clearing it puts everything back.
        </p>
        <button style={btn} onClick={reset}>
          ↻ Reset wallet connection
        </button>
      </div>
    </div>
  );
}

const wrap: React.CSSProperties = {
  minHeight: "100vh", display: "grid", placeItems: "center",
  background: "#0E0A1A", padding: 20,
  fontFamily: '"DM Sans", system-ui, sans-serif',
};
const card: React.CSSProperties = {
  textAlign: "center", maxWidth: 380, padding: "34px 28px", borderRadius: "var(--r-md)",
  background: "linear-gradient(160deg,#1b1436,#120c22)",
  border: "1px solid rgba(213,253,81,0.2)", boxShadow: "0 24px 70px rgba(0,0,0,0.5)",
};
const h1: React.CSSProperties = {
  fontFamily: '"Cinzel Decorative", serif', fontSize: 22, color: "#f5f0e8", margin: "0 0 8px",
};
const p: React.CSSProperties = { fontSize: 13.5, color: "#b8adcc", margin: "0 0 20px", lineHeight: 1.5 };
const btn: React.CSSProperties = {
  padding: "10px 22px", borderRadius: "var(--r-sm)", border: "1px solid #d5fd51",
  background: "rgba(213,253,81,0.14)", color: "#d5fd51", fontWeight: 600,
  fontFamily: '"Fredoka", sans-serif', fontSize: 14, cursor: "pointer",
};
