import { useEffect, useMemo, useState } from "react";
import { formatEther, parseEther, type Address } from "viem";
import { useAccount, useReadContract } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { useCauldronSwap } from "@/hooks/useCauldronSwap";
import { CAULDRON, ERC20_SWAP_ABI } from "@/config/cauldron";

interface SwapWidgetProps {
  ticker: string;
  /** The iteration token address (needed to sell — balance/allowance/approve). */
  token?: Address;
  /** ETH per token (spot). */
  spotPrice: number;
  /** USD per token. */
  priceUsd: number;
  /** USD per ETH. */
  ethUsd: number;
  /** Accent colour for the current phase. */
  col: string;
  /** Called after a trade confirms so the parent can refresh telemetry. */
  onBought?: () => void;
}

const BUY_QUICK = [0.01, 0.05, 0.1, 0.25];
const SELL_PCTS = [25, 50, 100];

function compact(n: number): string {
  if (!Number.isFinite(n) || n <= 0) return "0";
  if (n >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(2)}K`;
  return n.toFixed(n >= 1 ? 2 : 4);
}

/**
 * SwapWidget — buy OR sell the current iteration's token through the Cauldron
 * router. A BUY also credits volume + rolls the crystal gacha (chance to forge a
 * creature NFT). A SELL swaps the token back to ETH (needs a one-time approval).
 */
export default function SwapWidget({ ticker, token, spotPrice, priceUsd, ethUsd, col, onBought }: SwapWidgetProps) {
  const [mode, setMode] = useState<"buy" | "sell">("buy");
  const [buyAmt, setBuyAmt] = useState<string>("0.05");
  const [sellAmt, setSellAmt] = useState<string>("");
  const [err, setErr] = useState<string>("");
  const { address, isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const { buy, sell, approveToken, isPending, confirming, confirmed, reset } = useCauldronSwap();

  const side = mode === "buy" ? col : C.red;

  // Sell-side reads: token balance + router allowance.
  const { data: balanceWei, refetch: refetchBal } = useReadContract({
    address: token, abi: ERC20_SWAP_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, chainId: CAULDRON.chainId,
    query: { enabled: !!token && !!address },
  });
  const { data: allowanceWei, refetch: refetchAllow } = useReadContract({
    address: token, abi: ERC20_SWAP_ABI, functionName: "allowance",
    args: address ? [address, CAULDRON.gachaRouter] : undefined, chainId: CAULDRON.chainId,
    query: { enabled: !!token && !!address },
  });

  const balance = balanceWei != null ? Number(formatEther(balanceWei as bigint)) : 0;
  const eth = parseFloat(buyAmt) || 0;
  const tokensIn = parseFloat(sellAmt) || 0;
  const estTokensOut = useMemo(() => (spotPrice > 0 ? eth / spotPrice : 0), [eth, spotPrice]);
  const estEthOut = useMemo(() => tokensIn * spotPrice, [tokensIn, spotPrice]);
  const needsApproval = mode === "sell" && tokensIn > 0 &&
    (allowanceWei == null || (allowanceWei as bigint) < (() => { try { return parseEther((tokensIn).toFixed(18)); } catch { return 0n; } })());

  useEffect(() => {
    if (confirmed) {
      onBought?.();
      refetchBal();
      refetchAllow();
      const t = setTimeout(() => reset(), 4000);
      return () => clearTimeout(t);
    }
  }, [confirmed, onBought, reset, refetchBal, refetchAllow]);

  const onAction = async () => {
    setErr("");
    if (!isConnected) { openConnectModal?.(); return; }
    try {
      if (mode === "buy") {
        if (eth <= 0) { setErr("Enter an ETH amount"); return; }
        await buy(eth, 0n, 0);
      } else {
        if (!token) { setErr("No token yet"); return; }
        if (tokensIn <= 0) { setErr(`Enter a $${ticker} amount`); return; }
        if (needsApproval) { await approveToken(token); return; } // approve first
        await sell(tokensIn, 0n, 0);
      }
    } catch (e: unknown) {
      const m = e as { shortMessage?: string; message?: string };
      setErr(m?.shortMessage || m?.message || "Swap failed");
    }
  };

  const busy = isPending || confirming;
  const btnLabel = !isConnected
    ? "Connect wallet"
    : isPending ? "Confirm in wallet…"
    : confirming ? (mode === "buy" ? "Buying…" : needsApproval ? "Approving…" : "Selling…")
    : confirmed ? "Done ✓"
    : mode === "buy" ? `Buy $${ticker}`
    : needsApproval ? `Approve $${ticker}`
    : `Sell $${ticker}`;

  return (
    <aside className="sw">
      <style>{`
        .sw { position: sticky; top: 16px; border-radius: 14px; padding: 13px; background: rgba(23, 18, 42, 0.28); border: 1px solid rgba(255,255,255,0.05); }
        .sw__toggle { display: flex; gap: 3px; padding: 3px; border-radius: 10px; background: rgba(8,6,15,0.5); margin-bottom: 11px; }
        .sw__toggle button {
          flex: 1; padding: 6px 0; border-radius: 7px; border: none; cursor: pointer;
          font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px;
          background: none; color: ${C.mute}; transition: all 0.15s ease;
        }
        .sw__toggle button.on--buy { background: ${col}1c; color: ${col}; }
        .sw__toggle button.on--sell { background: ${C.red}1c; color: ${C.red}; }
        .sw__head { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 9px; }
        .sw__title { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: ${C.mute}; }
        .sw__spot { font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; }
        .sw__field { background: rgba(8,6,15,0.45); border: 1px solid rgba(255,255,255,0.05); border-radius: 10px; padding: 9px 11px; }
        .sw__field-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 3px; }
        .sw__lbl { font-family: "DM Mono", monospace; font-size: 8.5px; letter-spacing: 0.14em; text-transform: uppercase; color: ${C.mute}; }
        .sw__sub { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; }
        .sw__row { display: flex; align-items: center; gap: 8px; }
        .sw__input { flex: 1; min-width: 0; background: none; border: none; outline: none; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 20px; color: ${C.cream}; letter-spacing: -0.01em; }
        .sw__input::placeholder { color: rgba(143,131,184,0.45); }
        .sw__coin { display: inline-flex; align-items: center; gap: 5px; padding: 3px 8px; border-radius: 999px; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.07); font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 11px; color: ${C.cream}; white-space: nowrap; }
        .sw__coin-dot { width: 13px; height: 13px; border-radius: 50%; display: grid; place-items: center; font-size: 8px; }
        .sw__chips { display: flex; gap: 5px; margin: 7px 0; }
        .sw__chip { flex: 1; padding: 4px 0; border-radius: 7px; background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; cursor: pointer; transition: all 0.15s ease; }
        .sw__chip:hover { border-color: ${side}55; color: ${C.cream}; }
        .sw__chip--on { background: ${side}1a; border-color: ${side}88; color: ${side}; }
        .sw__out { display: flex; justify-content: space-between; align-items: baseline; padding: 2px 2px 0; margin-top: 2px; }
        .sw__out-l { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; }
        .sw__out-v { font-family: "DM Mono", monospace; font-size: 12px; color: ${C.cream}; }
        .sw__gacha { font-family: "DM Sans", sans-serif; font-size: 9.5px; line-height: 1.4; color: ${C.mute}; margin: 8px 2px 10px; opacity: 0.85; }
        .sw__gacha b { color: ${col}; font-weight: 600; }
        .sw__cta { width: 100%; padding: 9px; border-radius: 10px; border: 1px solid ${side}66; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 13px; letter-spacing: 0.02em; color: ${side}; background: ${side}14; cursor: pointer; transition: background 0.15s ease, border-color 0.15s ease; }
        .sw__cta:hover:not(:disabled) { background: ${side}26; border-color: ${side}; }
        .sw__cta:disabled { opacity: 0.5; cursor: default; }
        .sw__cta--busy { background: transparent; }
        .sw__err { margin: 8px 2px 0; font-family: "DM Sans", sans-serif; font-size: 10px; color: ${C.red}; line-height: 1.4; }
        .sw__foot { margin-top: 8px; font-family: "DM Mono", monospace; font-size: 8px; color: ${C.mute}; text-align: center; opacity: 0.55; }
        @keyframes sw-spin { to { transform: rotate(360deg); } }
      `}</style>

      {/* buy / sell toggle */}
      <div className="sw__toggle">
        <button className={mode === "buy" ? "on--buy" : ""} onClick={() => { setMode("buy"); setErr(""); }}>Buy</button>
        <button className={mode === "sell" ? "on--sell" : ""} onClick={() => { setMode("sell"); setErr(""); }}>Sell</button>
      </div>

      <div className="sw__head">
        <span className="sw__title">{mode === "buy" ? "Buy" : "Sell"} ${ticker}</span>
        <span className="sw__spot">{priceUsd > 0 ? `$${priceUsd < 0.01 ? priceUsd.toPrecision(2) : priceUsd.toFixed(4)}` : "—"}</span>
      </div>

      {mode === "buy" ? (
        <>
          <div className="sw__field">
            <div className="sw__field-top">
              <span className="sw__lbl">You pay</span>
              <span className="sw__sub">{eth * ethUsd > 0 ? `≈ $${(eth * ethUsd).toFixed(2)}` : ""}</span>
            </div>
            <div className="sw__row">
              <input className="sw__input" inputMode="decimal" placeholder="0.0" value={buyAmt} onChange={(e) => setBuyAmt(e.target.value.replace(/[^0-9.]/g, ""))} />
              <span className="sw__coin"><span className="sw__coin-dot" style={{ background: "#627EEA", color: "#fff" }}>Ξ</span>ETH</span>
            </div>
          </div>
          <div className="sw__chips">
            {BUY_QUICK.map((q) => (
              <button key={q} className={`sw__chip ${eth === q ? "sw__chip--on" : ""}`} onClick={() => setBuyAmt(String(q))}>{q}</button>
            ))}
          </div>
          <div className="sw__out">
            <span className="sw__out-l">≈ receive</span>
            <span className="sw__out-v">{compact(estTokensOut)} ${ticker}</span>
          </div>
          <p className="sw__gacha">Every buy rolls the <b>crystal gacha</b> — a chance to forge a creature NFT &amp; keep the brew alive.</p>
        </>
      ) : (
        <>
          <div className="sw__field">
            <div className="sw__field-top">
              <span className="sw__lbl">You sell</span>
              <span className="sw__sub">balance {compact(balance)}</span>
            </div>
            <div className="sw__row">
              <input className="sw__input" inputMode="decimal" placeholder="0.0" value={sellAmt} onChange={(e) => setSellAmt(e.target.value.replace(/[^0-9.]/g, ""))} />
              <span className="sw__coin"><span className="sw__coin-dot" style={{ background: col, color: C.void }}>◆</span>${ticker}</span>
            </div>
          </div>
          <div className="sw__chips">
            {SELL_PCTS.map((p) => (
              <button key={p} className="sw__chip" onClick={() => setSellAmt(String(+(balance * p / 100).toFixed(6)))}>{p === 100 ? "MAX" : `${p}%`}</button>
            ))}
          </div>
          <div className="sw__out">
            <span className="sw__out-l">≈ receive</span>
            <span className="sw__out-v">{estEthOut > 0 ? `${estEthOut.toFixed(estEthOut < 0.001 ? 6 : 4)} Ξ` : "0 Ξ"}</span>
          </div>
          <p className="sw__gacha">Selling swaps ${ticker} back to ETH. A one-time approval is needed first.</p>
        </>
      )}

      <button className={`sw__cta ${busy ? "sw__cta--busy" : ""}`} onClick={onAction} disabled={busy}>
        {busy && <span style={{ display: "inline-block", animation: "sw-spin 1s linear infinite", marginRight: 6 }}>⏳</span>}
        {btnLabel}
      </button>

      {err && <div className="sw__err">{err}</div>}
      <div className="sw__foot">via Cauldron V4 hook · 3% fee → floor + genesis</div>
    </aside>
  );
}

// Local palette mirror (keeps the widget self-contained).
const C = {
  void: "#08060f",
  lime: "#d5fd51",
  red: "#ff4d6d",
  cream: "#F5F0E8",
  mute: "#8f83b8",
};
