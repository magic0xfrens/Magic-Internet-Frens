import { Component, type ErrorInfo, type ReactNode } from "react";

interface Props {
  children: ReactNode;
}
interface State {
  error: Error | null;
}

/**
 * App-wide safety net. If any render/provider error escapes (a bad wallet
 * config, a failed lazy chunk on a cold cache, a runtime throw), show a friendly
 * reload card instead of a blank screen.
 */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // Surface it for debugging; a monitoring hook could go here.
    console.error("App crashed:", error, info);
  }

  render() {
    if (!this.state.error) return this.props.children;
    const isChunk = /chunk|dynamically imported module|Failed to fetch/i.test(this.state.error.message);
    return (
      <div style={wrap}>
        <div style={card}>
          <div style={{ fontSize: 34, marginBottom: 6 }}>🧙‍♂️</div>
          <h1 style={h1}>The spell fizzled</h1>
          <p style={p}>
            {isChunk
              ? "A fresh version just shipped. Reload to grab it."
              : "Something went wrong loading the page."}
          </p>
          <button style={btn} onClick={() => { location.reload(); }}>↻ Reload</button>
        </div>
      </div>
    );
  }
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
