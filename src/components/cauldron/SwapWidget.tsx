import { useEffect, useMemo, useState } from "react";
import { formatEther, parseEther, type Address } from "viem";
import { useAccount, useReadContract } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { useCauldronSwap } from "@/hooks/useCauldronSwap";
import { usePerpLiqHint } from "@/hooks/usePerpLiqHint";
import { useLiquidatoorWatch } from "@/hooks/useLiquidatoorWatch";
import LiquidatoorModal from "@/components/cauldron/LiquidatoorModal";
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

/**
 * SLIPPAGE — the floor every trade signs.
 *
 * Both legs used to pass `minOut = 0n` (`buy(eth, 0n, …)` and
 * `sell(tokensIn, 0n, …)`), which tells the router "fill me at ANY price". The
 * router takes a floor on both sides (`play(quoteIn, tokenIn, minTokenOut,
 * minQuoteOut, openMax)`) and the hook forwards one — only the widget never
 * supplied it. A sandwich could take the entire trade and the transaction would
 * still succeed, on the path every ordinary user trades through.
 *
 * 1% by default, adjustable, because a fixed tolerance chosen silently on the
 * user's behalf is the other half of the same mistake.
 */
const SLIP_PRESETS = [0.5, 1, 3] as const;
const DEFAULT_SLIP_PCT = 1;
const MAX_SLIP_PCT = 50;

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
  const [slipPct, setSlipPct] = useState<number>(DEFAULT_SLIP_PCT);
  const { address, isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const { buy, sell, approveToken, isPending, confirming, confirmed, reset, txHash } = useCauldronSwap();
  // The most-at-risk perp position to tag onto this swap: if our trade tips it
  // past the mark, the hook auto-liquidates it and mints us a Liquidatoor badge.
  // A buy threatens shorts, a sell threatens longs. 0n keeps the cheaper path.
  const liqHint = usePerpLiqHint(mode);
  // Pop "Congrats Liquidatoor!" if this spot trade rekt someone + badged us.
  const { hit: liqHit, ack: ackLiq } = useLiquidatoorWatch(txHash);

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
  //  The floor that will actually be signed, in the unit the router compares
  //  against: token wei on a buy, ETH wei on a sell. Derived from the SAME
  //  estimate shown above it, so the number on screen and the number in the
  //  calldata cannot drift apart.
  const slipBps = BigInt(Math.min(MAX_SLIP_PCT * 100, Math.max(0, Math.round(slipPct * 100))));
  const minOutFor = (expected: number): bigint => {
    if (!Number.isFinite(expected) || expected <= 0) return 0n;
    try { return (parseEther(expected.toFixed(18)) * (10_000n - slipBps)) / 10_000n; }
    catch { return 0n; }
  };
  const expectedOut = mode === "buy" ? estTokensOut : estEthOut;
  const minOut = minOutFor(expectedOut);
  //  No mark, no floor — and a floor of 0 is exactly the bug. Refuse instead.
  const priceable = spotPrice > 0;

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
        if (!priceable) { setErr("No price for this market yet — refusing to trade at any price"); return; }
        if (minOut <= 0n) { setErr("Could not compute a slippage floor — refusing to sign"); return; }
        await buy(eth, minOut, 0, liqHint);
      } else {
        if (!token) { setErr("No token yet"); return; }
        if (tokensIn <= 0) { setErr(`Enter a $${ticker} amount`); return; }
        if (needsApproval) { await approveToken(token); return; } // approve first
        if (!priceable) { setErr("No price for this market yet — refusing to trade at any price"); return; }
        if (minOut <= 0n) { setErr("Could not compute a slippage floor — refusing to sign"); return; }
        // Pass the exact on-chain balance so a "MAX" that rounds a hair high
        // (float precision on big balances) is clamped instead of reverting.
        await sell(tokensIn, minOut, 0, liqHint, balanceWei as bigint | undefined);
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
        .sw { position: sticky; top: 16px; border-radius: var(--r-sm); padding: 13px; background: rgba(23, 18, 42, 0.28); border: 1px solid rgba(255,255,255,0.05); }
        .sw__toggle { display: flex; gap: 3px; padding: 3px; border-radius: var(--r-sm); background: rgba(8,6,15,0.5); margin-bottom: 11px; }
        .sw__toggle button {
          flex: 1; padding: 6px 0; border-radius: var(--r-sm); border: none; cursor: pointer;
          font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px;
          background: none; color: ${C.mute}; transition: all 0.15s ease;
        }
        .sw__toggle button.on--buy { background: ${col}1c; color: ${col}; }
        .sw__toggle button.on--sell { background: ${C.red}1c; color: ${C.red}; }
        .sw__head { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 9px; }
        .sw__title { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: ${C.mute}; }
        .sw__spot { font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; }
        .sw__field { background: rgba(8,6,15,0.45); border: 1px solid rgba(255,255,255,0.05); border-radius: var(--r-sm); padding: 9px 11px; }
        .sw__field-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 3px; }
        .sw__lbl { font-family: "DM Mono", monospace; font-size: 8.5px; letter-spacing: 0.14em; text-transform: uppercase; color: ${C.mute}; }
        .sw__sub { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; }
        .sw__row { display: flex; align-items: center; gap: 8px; }
        .sw__slip { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin: 9px 0 6px; }
        .sw__slip-l { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.08em; text-transform: uppercase; color: ${C.mute}; }
        .sw__slip-opts { display: flex; align-items: center; gap: 4px; }
        .sw__slip-chip { padding: 3px 7px; border-radius: var(--r-sm); border: 1px solid rgba(255,255,255,0.08); background: rgba(8,6,15,0.5); color: ${C.mute}; font-family: "DM Mono", monospace; font-size: 10px; cursor: pointer; }
        .sw__slip-chip--on { color: ${C.void}; background: ${side}; border-color: ${side}; }
        .sw__slip-input { width: 34px; padding: 3px 4px; border-radius: var(--r-sm); border: 1px solid rgba(255,255,255,0.08); background: rgba(8,6,15,0.5); color: #fff; font-family: "DM Mono", monospace; font-size: 10px; text-align: right; }
        .sw__slip-pct { font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; }
        .sw__out--min .sw__out-v { color: ${C.mute}; }
        .sw__input { flex: 1; min-width: 0; background: none; border: none; outline: none; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 20px; color: ${C.cream}; letter-spacing: -0.01em; }
        .sw__input::placeholder { color: rgba(143,131,184,0.45); }
        .sw__coin { display: inline-flex; align-items: center; gap: 5px; padding: 3px 8px; border-radius: var(--r-chip); background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.07); font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 11px; color: ${C.cream}; white-space: nowrap; }
        .sw__coin-dot { width: 13px; height: 13px; border-radius: 50%; display: grid; place-items: center; font-size: 8px; }
        .sw__chips { display: flex; gap: 5px; margin: 7px 0; }
        .sw__chip { flex: 1; padding: 4px 0; border-radius: var(--r-sm); background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; cursor: pointer; transition: all 0.15s ease; }
        .sw__chip:hover { border-color: ${side}55; color: ${C.cream}; }
        .sw__chip--on { background: ${side}1a; border-color: ${side}88; color: ${side}; }
        .sw__out { display: flex; justify-content: space-between; align-items: baseline; padding: 2px 2px 0; margin-top: 2px; }
        .sw__out-l { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; }
        .sw__out-v { font-family: "DM Mono", monospace; font-size: 12px; color: ${C.cream}; }
        .sw__gacha { font-family: "DM Sans", sans-serif; font-size: 9.5px; line-height: 1.4; color: ${C.mute}; margin: 8px 2px 10px; opacity: 0.85; }
        .sw__gacha b { color: ${col}; font-weight: 600; }
        .sw__cta { width: 100%; padding: 9px; border-radius: var(--r-sm); border: 1px solid ${side}66; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 13px; letter-spacing: 0.02em; color: ${side}; background: ${side}14; cursor: pointer; transition: background 0.15s ease, border-color 0.15s ease; }
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

      {/*  THE SLIPPAGE CONTROL AND THE NUMBER IT PRODUCES. A tolerance the user
           cannot see or change is not protection, and a widget that shows an
           estimate while signing a floor of zero is actively misleading. */}
      <div className="sw__slip">
        <span className="sw__slip-l">Max slippage</span>
        <div className="sw__slip-opts">
          {SLIP_PRESETS.map((sp) => (
            <button key={sp} className={`sw__slip-chip ${slipPct === sp ? "sw__slip-chip--on" : ""}`}
              onClick={() => setSlipPct(sp)}>{sp}%</button>
          ))}
          <input className="sw__slip-input" inputMode="decimal" value={slipPct}
            aria-label="Max slippage percent"
            onChange={(e) => setSlipPct(Math.min(MAX_SLIP_PCT, Number(e.target.value.replace(/[^0-9.]/g, "")) || 0))} />
          <span className="sw__slip-pct">%</span>
        </div>
      </div>
      <div className="sw__out sw__out--min">
        <span className="sw__out-l">minimum received</span>
        <span className="sw__out-v">
          {!priceable
            ? "unpriceable — will not sign"
            : mode === "buy"
              ? `${compact(Number(formatEther(minOut)))} $${ticker}`
              : `${Number(formatEther(minOut)).toFixed(6)} \u039e`}
        </span>
      </div>

      <button className={`sw__cta ${busy ? "sw__cta--busy" : ""}`} onClick={onAction}
        disabled={busy || (isConnected && (mode === "buy" ? eth <= 0 : tokensIn <= 0 && !needsApproval))}>
        {busy && <span style={{ display: "inline-block", animation: "sw-spin 1s linear infinite", marginRight: 6 }}>⏳</span>}
        {btnLabel}
      </button>

      {err && <div className="sw__err">{err}</div>}
      <div className="sw__foot">via Cauldron V4 hook · 3% fee → floor + genesis</div>

      {liqHit && <LiquidatoorModal hit={liqHit} onClose={ackLiq} />}
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
