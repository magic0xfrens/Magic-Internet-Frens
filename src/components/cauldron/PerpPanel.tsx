import { useEffect, useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { usePerpEngine, type PerpPosition } from "@/hooks/usePerpEngine";
import { usePerpRekt } from "@/hooks/usePerpRekt";
import { usePerpLiqHint } from "@/hooks/usePerpLiqHint";
import { usePerpHeatmap } from "@/hooks/usePerpHeatmap";
import { useLiquidatoorWatch } from "@/hooks/useLiquidatoorWatch";
import LiquidatoorModal from "@/components/cauldron/LiquidatoorModal";
import PnlCard, { type CardData } from "@/components/cauldron/PnlCard";
import { explainPerpError } from "@/config/perp";

interface PerpPanelProps {
  ticker: string;
  spotPrice: number;   // ETH per token
  priceUsd: number;    // USD per token
  ethUsd: number;      // USD per ETH
  col: string;         // phase accent
  warm: boolean;       // past the open warmup
  generation?: number; // current iteration (for the Ponder reads)
  onTraded?: () => void; // called after a position opens/closes → refresh chart
}

const MAINTENANCE = 0.15; // mirrors PerpEngine.maintenanceBps (1500)
const QUICK = [0.01, 0.05, 0.1, 0.25];

function compact(n: number): string {
  if (!Number.isFinite(n) || n === 0) return "0";
  const a = Math.abs(n);
  if (a >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (a >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (a >= 1e3) return `${(n / 1e3).toFixed(2)}K`;
  return n.toFixed(a >= 1 ? 2 : 4);
}
const gwei = (p: number) => (p > 0 ? `${(p * 1e9).toFixed(2)} gw` : "—");

/**
 * PerpPanel — the leverage trading console: open longs/shorts with real price
 * impact, watch open interest + funding, and track every open position with live
 * PnL, health, and the liquidation price. Gated to a graceful "activates on
 * deploy" state until the PerpEngine address is configured.
 */
export default function PerpPanel({ ticker, spotPrice, priceUsd, ethUsd, col, warm, generation = 1, onTraded }: PerpPanelProps) {
  const { isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const perp = usePerpEngine(generation);
  const { stats, reset: perpReset } = perp;

  const [side, setSide] = useState<"long" | "short">("long");
  const [amt, setAmt] = useState("0.05");
  const [lev, setLev] = useState(2);
  const [err, setErr] = useState("");
  const [toast, setToast] = useState<{ kind: "err" | "ok"; msg: string } | null>(null);
  const [card, setCard] = useState<CardData | null>(null);

  // auto-dismiss the toast
  useEffect(() => { if (!toast) return; const t = setTimeout(() => setToast(null), 7000); return () => clearTimeout(t); }, [toast]);
  // a close's PnL card, tied to the POSITION LEAVING the list — the reliable
  // "it actually closed" signal (Ponder), not the flaky RPC receipt watch. Pops
  // the moment the closed position disappears from your positions.
  const [closeCard, setCloseCard] = useState<{ card: CardData; id: bigint } | null>(null);

  useEffect(() => {
    if (!closeCard) return;
    const stillOpen = perp.positions.some((p) => p.id === closeCard.id);
    if (!stillOpen) {
      setCard(closeCard.card);
      setCloseCard(null);
    }
  }, [perp.positions, closeCard]);

  const onClosePosition = async (id: bigint, c: CardData) => {
    try {
      await perp.closePosition(id);       // resolves once signed + submitted
      setCloseCard({ card: c, id });       // arm — pops when the position leaves the list
    } catch (e) { setToast({ kind: "err", msg: `Close failed — ${explainPerpError(e)}` }); }
  };

  // pop a RIP card the instant a liquidation lands while you're watching
  const rekt = usePerpRekt(stats.live && !stats.dead);
  // the TWAP mark (from the heatmap) — used by the open guard to catch a
  // "born-underwater" open (spot diverged from the sticky mark).
  const heat = usePerpHeatmap(stats.live && !stats.dead, generation);
  // A long open (buy pressure) threatens SHORTS; a short open threatens LONGS —
  // so the most-at-risk position to tag is the same mapping as spot.
  const liqHint = usePerpLiqHint(side === "long" ? "buy" : "sell", generation);
  // Pop "Congrats Liquidatoor!" if this open rekt someone + badged us.
  const { hit: liqHit, ack: ackLiq } = useLiquidatoorWatch(perp.txHash);
  useEffect(() => {
    if (rekt.latest) {
      const r = rekt.latest;
      setCard({ pnlEth: r.pnlEth, roiPct: r.collateralEth > 0 ? (r.pnlEth / r.collateralEth) * 100 : -100, kind: "rip", leverage: r.leverage, isLong: r.isLong });
      rekt.ack();
    }
  }, [rekt]);

  const accent = side === "long" ? col : C.red;
  const maxLev = Math.max(1, stats.maxLev || 2);
  useEffect(() => { if (lev > maxLev) setLev(maxLev); }, [maxLev, lev]);

  // aggregate PnL across all open positions (live, from spot)
  const agg = useMemo(() => {
    let pnlEth = 0, collateralEth = 0, maxLevSeen = 1, longs = 0;
    for (const p of perp.positions) {
      pnlEth += positionPnl(p, spotPrice);
      collateralEth += p.collateralEth;
      maxLevSeen = Math.max(maxLevSeen, p.leverage);
      if (p.isLong) longs++;
    }
    return { pnlEth, collateralEth, roiPct: collateralEth > 0 ? (pnlEth / collateralEth) * 100 : 0,
      maxLev: maxLevSeen, mostlyLong: longs >= perp.positions.length - longs };
  }, [perp.positions, spotPrice]);

  const collateral = parseFloat(amt) || 0;
  const notional = collateral * lev;
  const feeBps = stats.openFeeBps || 690;
  const feeEth = (collateral * feeBps) / 1e4;
  const liqPrice = useMemo(() => {
    if (spotPrice <= 0 || lev <= 0) return 0;
    return side === "long"
      ? spotPrice * ((lev - 1) * (1 + MAINTENANCE)) / lev
      : spotPrice * ((lev + 1) * (1 - MAINTENANCE)) / lev;
  }, [spotPrice, lev, side]);
  const liqDeltaPct = spotPrice > 0 ? Math.abs((liqPrice - spotPrice) / spotPrice) * 100 : 0;

  // ── MARK-vs-SPOT open guard ──────────────────────────────────────────────
  // Opens execute at SPOT, but the engine liquidates against the 5-min TWAP mark
  // (and runs a best-effort sweep at the END of openLong/openShort). So if the
  // mark has diverged past this position's liq price, you'd be liquidated in the
  // SAME block you open — "born underwater" — and your own open even mints you a
  // Liquidatoor badge for self-rekting. A long liquidates when price ≤ liqPrice,
  // a short when price ≥ liqPrice, evaluated at the MARK. Block it before the
  // wallet. Best-effort: only when we actually have a mark (heatmap live).
  const markPrice = heat.markPrice ?? 0;
  const markDivergePct = markPrice > 0 && spotPrice > 0 ? ((markPrice - spotPrice) / spotPrice) * 100 : 0;
  const wouldLiquidateOnOpen =
    markPrice > 0 && spotPrice > 0 && liqPrice > 0 && collateral > 0 &&
    (side === "long" ? markPrice <= liqPrice : markPrice >= liqPrice);

  // funding + OI balance
  const totalOi = stats.longOiEth + stats.shortOiEth;
  const longShare = totalOi > 0 ? (stats.longOiEth / totalOi) * 100 : 50;
  const fundingSide = stats.fundingIdx >= 0 ? "Longs pay" : "Shorts pay";

  // ── client-side LIQUIDITY GUARD — mirror the engine's plv + util caps so we
  // NEVER send a doomed open (PlvInsufficient/UtilCapped) that just burns gas.
  // Long borrows ETH from plv; short borrows token inventory (value it in ETH).
  const MAX_UTIL = 0.8; // maxUtilBps = 8000
  const longCap = Math.max(0, Math.min(stats.plvEth, (stats.plvEth + stats.longOiEth) * MAX_UTIL - stats.longOiEth));
  const plvTokenEth = stats.plvToken * spotPrice;                       // inventory valued in ETH
  const shortCap = Math.max(0, Math.min(plvTokenEth, (plvTokenEth + stats.shortOiEth) * MAX_UTIL - stats.shortOiEth));
  const sideCap = side === "long" ? longCap : shortCap;                 // max borrow this side can front (ETH)
  const need = side === "long" ? collateral * (lev - 1) : collateral * lev; // this open's borrow (ETH)
  const overLiquidity = collateral > 0 && need > sideCap + 1e-9;
  // biggest collateral that still fits (liquidity), at the current leverage
  const maxCollByLiquidity = side === "long" ? (lev > 1 ? sideCap / (lev - 1) : Infinity) : sideCap / lev;

  // ── client-side NOTIONAL GUARD — mirror the engine's _checkNotional so we never
  // send an open that trips BadLeverage(): notional (collateral × lev) must stay
  // ≤ maxNotionalBps of active pool depth (a per-position slippage cap). On a thin
  // pool this is the binding limit long before the vault runs out.
  const notionalCap = stats.depthEth * ((stats.maxNotionalBps || 500) / 1e4); // ETH
  const overNotional = collateral > 0 && stats.depthEth > 0 && notional > notionalCap + 1e-9;
  const maxCollByNotional = lev > 0 && notionalCap > 0 ? notionalCap / lev : Infinity;
  // the tighter of the two ceilings is what the trader can actually open
  const maxCollateral = Math.min(maxCollByLiquidity, maxCollByNotional);
  const blocked = overLiquidity || overNotional || wouldLiquidateOnOpen;

  // React to the tx settling: success → refresh the chart + positions; revert or
  // wallet/RPC error → surface it so the button never hangs on "Opening…".
  useEffect(() => {
    if (perp.confirmed && !perp.reverted) {
      onTraded?.();
      const t = setTimeout(() => perpReset(), 4000);
      return () => clearTimeout(t);
    }
    if (perp.reverted) { setErr("Transaction reverted on-chain — nothing opened."); const t = setTimeout(() => perpReset(), 6000); return () => clearTimeout(t); }
    if (perp.receiptFailed) { setErr("Couldn't confirm the tx (RPC). Check your wallet/explorer."); }
  }, [perp.confirmed, perp.reverted, perp.receiptFailed, onTraded, perpReset]);

  // surface a write/estimation error (e.g. would-revert) even before sending.
  useEffect(() => {
    if (perp.txError) setErr(perp.txError.shortMessage || perp.txError.message || "Transaction failed");
  }, [perp.txError]);

  const canOpen = stats.live && warm && !stats.dead && collateral > 0 && !blocked;
  const onOpen = async () => {
    setErr(""); setToast(null);
    if (!isConnected) { openConnectModal?.(); return; }
    try {
      if (collateral <= 0) { setErr("Enter a collateral amount"); return; }
      // Block a doomed open BEFORE the wallet — the pool's too thin for this size
      // (would revert BadLeverage on _checkNotional). Notional is the tighter cap.
      if (overNotional) {
        const msg = maxCollByNotional >= 0.0001
          ? `Position too big for pool depth — max ~${compact(notionalCap)} Ξ notional (${((stats.maxNotionalBps || 500) / 100).toFixed(0)}% of depth). Try ~${compact(maxCollByNotional)} Ξ at ${lev}×, or lower leverage.`
          : `The pool is too thin to open a position right now — depth ${compact(stats.depthEth)} Ξ. Wait for more liquidity.`;
        setErr(msg); setToast({ kind: "err", msg }); return;
      }
      // Block a "born-underwater" open BEFORE the wallet — spot has diverged from
      // the sticky 5-min TWAP mark, so the engine would liquidate this the same
      // block it opens (and self-mint you a Liquidatoor badge for rekting yourself).
      if (wouldLiquidateOnOpen) {
        const dir = markDivergePct >= 0 ? "above" : "below";
        const msg = `Mark is ${Math.abs(markDivergePct).toFixed(1)}% ${dir} spot — a ${lev}× ${side} would be liquidated the moment it opens (opens fill at spot but are marked vs the 5-min TWAP). Wait for the mark to catch up to spot, lower leverage, or trade the other side.`;
        setErr(msg); setToast({ kind: "err", msg }); return;
      }
      // Block a doomed open BEFORE the wallet — the vault can't front this borrow.
      if (overLiquidity) {
        const msg = maxCollByLiquidity >= 0.0001
          ? `Vault can only lend ${compact(sideCap)} Ξ to ${side}s right now — max ~${compact(maxCollByLiquidity)} Ξ at ${lev}×. Lower size/leverage, or stake ETH in the vault.`
          : `The ${side} vault is fully utilized right now — no liquidity to borrow. Try the other side, or stake ${side === "long" ? "ETH" : `$${ticker}`} in the vault.`;
        setErr(msg); setToast({ kind: "err", msg }); return;
      }
      if (side === "long") await perp.openLong(collateral, lev, liqHint);
      else await perp.openShort(collateral, lev, liqHint);
    } catch (e: unknown) {
      const why = explainPerpError(e);       // decoded, human-readable reason
      setErr(why);
      setToast({ kind: "err", msg: `Trade failed — ${why}` });
    }
  };

  // Scoped to the OPEN action only — a CLOSE confirming must not make this button
  // say "Opening…" (they share one write-state).
  const busy = perp.openingBusy;
  const openLabel = `Open ${side === "long" ? "Long" : "Short"} ${lev}×`;
  const btnLabel = !isConnected ? "Connect wallet"
    : !stats.live ? "Perps offline"
    : stats.dead ? "Token is dead"
    : !warm ? "Warming up…"
    : perp.pendingAction === "open" && perp.isPending ? "Confirm in wallet…"
    : perp.openingBusy ? "Opening… (may take ~15s)"
    : perp.pendingAction === "open" && perp.confirmed ? "Opened ✓"
    : overNotional ? "Size too big for pool depth"
    : overLiquidity ? "Not enough vault liquidity"
    : openLabel;

  return (
    <div className="pp">
      <style>{`
        .pp-toast { position: fixed; left: 50%; bottom: 26px; transform: translateX(-50%); z-index: 9998; max-width: 420px; width: calc(100vw - 40px); display: flex; align-items: flex-start; gap: 10px; padding: 13px 15px; border-radius: var(--r-sm); font-family: "DM Sans", sans-serif; font-size: 13px; line-height: 1.4; box-shadow: 0 18px 50px -12px rgba(0,0,0,0.6); animation: pp-toast-in .2s ease; }
        .pp-toast--err { background: linear-gradient(160deg, #2a1420, #17101f); border: 1px solid ${C.red}66; color: ${C.cream}; }
        .pp-toast--ok { background: linear-gradient(160deg, #16261a, #10171f); border: 1px solid ${C.lime}66; color: ${C.cream}; }
        .pp-toast__ic { font-size: 15px; margin-top: 1px; }
        .pp-toast__x { margin-left: auto; cursor: pointer; opacity: 0.6; background: none; border: none; color: inherit; font-size: 15px; }
        @keyframes pp-toast-in { from { opacity: 0; transform: translate(-50%, 8px); } to { opacity: 1; transform: translate(-50%, 0); } }
        .pp { display: grid; grid-template-columns: 1fr; gap: 14px; }
        @media (min-width: 900px) { .pp { grid-template-columns: 340px 1fr; align-items: start; } }
        .pp-card { border-radius: var(--r-md); padding: 16px; background: rgba(23,18,42,0.34); border: 1px solid rgba(255,255,255,0.06); }
        .pp-eyebrow { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.16em; text-transform: uppercase; color: ${C.mute}; margin-bottom: 12px; display: flex; justify-content: space-between; align-items: center; }
        .pp-eyebrow b { color: ${col}; font-weight: 500; }
        .pp-toggle { display: flex; gap: 4px; padding: 4px; border-radius: var(--r-sm); background: rgba(8,6,15,0.55); margin-bottom: 14px; }
        .pp-toggle button { flex: 1; padding: 9px 0; border-radius: var(--r-sm); border: none; cursor: pointer; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 13px; background: none; color: ${C.mute}; transition: all 0.15s ease; }
        .pp-toggle .on--long { background: ${col}1e; color: ${col}; }
        .pp-toggle .on--short { background: ${C.red}1e; color: ${C.red}; }
        .pp-field { background: rgba(8,6,15,0.5); border: 1px solid rgba(255,255,255,0.06); border-radius: var(--r-sm); padding: 11px 13px; }
        .pp-field-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; }
        .pp-lbl { font-family: "DM Mono", monospace; font-size: 8.5px; letter-spacing: 0.14em; text-transform: uppercase; color: ${C.mute}; }
        .pp-row { display: flex; align-items: center; gap: 8px; }
        .pp-input { flex: 1; min-width: 0; background: none; border: none; outline: none; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 22px; color: ${C.cream}; }
        .pp-input::placeholder { color: rgba(143,131,184,0.4); }
        .pp-coin { display: inline-flex; align-items: center; gap: 5px; padding: 4px 9px; border-radius: var(--r-chip); background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.07); font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 11px; color: ${C.cream}; }
        .pp-chips { display: flex; gap: 5px; margin: 8px 0; }
        .pp-chip { flex: 1; padding: 5px 0; border-radius: var(--r-sm); background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; cursor: pointer; transition: all 0.15s ease; }
        .pp-chip:hover { border-color: ${accent}55; color: ${C.cream}; }
        .pp-chip--on { background: ${accent}18; border-color: ${accent}77; color: ${accent}; }
        .pp-lev { margin: 14px 0 4px; }
        .pp-lev-top { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 6px; }
        .pp-lev-v { font-family: "Fredoka", sans-serif; font-weight: 700; font-size: 20px; color: ${accent}; }
        .pp-range { width: 100%; -webkit-appearance: none; appearance: none; height: 5px; border-radius: var(--r-chip); outline: none; cursor: pointer;
          background: linear-gradient(90deg, ${accent} 0%, ${accent} var(--pct,50%), rgba(255,255,255,0.09) var(--pct,50%)); }
        .pp-range::-webkit-slider-thumb { -webkit-appearance: none; width: 17px; height: 17px; border-radius: 50%; background: ${accent}; cursor: pointer; border: 3px solid ${C.void}; box-shadow: 0 0 0 1px ${accent}88; }
        .pp-range::-moz-range-thumb { width: 14px; height: 14px; border-radius: 50%; background: ${accent}; cursor: pointer; border: 3px solid ${C.void}; }
        .pp-ticks { display: flex; justify-content: space-between; font-family: "DM Mono", monospace; font-size: 8.5px; color: ${C.mute}; margin-top: 5px; }
        .pp-summary { margin: 14px 0 12px; border-top: 1px solid rgba(255,255,255,0.06); padding-top: 12px; display: grid; gap: 7px; }
        .pp-line { display: flex; justify-content: space-between; align-items: baseline; }
        .pp-line-l { font-family: "DM Mono", monospace; font-size: 9.5px; letter-spacing: 0.04em; color: ${C.mute}; }
        .pp-line-v { font-family: "DM Mono", monospace; font-size: 11px; color: ${C.cream}; }
        .pp-line-v.warn { color: ${C.red}; }
        .pp-cta { width: 100%; padding: 12px; border-radius: var(--r-sm); border: 1px solid ${accent}66; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 14px; letter-spacing: 0.02em; color: ${accent}; background: ${accent}16; cursor: pointer; transition: all 0.15s ease; }
        .pp-cta:hover:not(:disabled) { background: ${accent}28; border-color: ${accent}; }
        .pp-cta:disabled { opacity: 0.5; cursor: default; }
        .pp-err { margin-top: 9px; font-family: "DM Sans", sans-serif; font-size: 10px; color: ${C.red}; line-height: 1.4; }
        .pp-warn { margin: 10px 0 4px; padding: 8px 10px; border: 1px solid ${C.red}55; border-radius: var(--r-sm); background: ${C.red}14; font-family: "DM Sans", sans-serif; font-size: 10px; color: ${C.red}; line-height: 1.45; }
        .pp-note { margin-top: 10px; font-family: "DM Sans", sans-serif; font-size: 9.5px; line-height: 1.45; color: ${C.mute}; opacity: 0.85; }

        .pp-oi { display: grid; gap: 9px; margin-bottom: 14px; }
        .pp-oi-bar { height: 9px; border-radius: var(--r-chip); overflow: hidden; display: flex; background: rgba(8,6,15,0.6); }
        .pp-oi-long { background: ${col}; }
        .pp-oi-short { background: ${C.red}; }
        .pp-oi-legend { display: flex; justify-content: space-between; font-family: "DM Mono", monospace; font-size: 9.5px; }
        .pp-oi-legend .l { color: ${col}; } .pp-oi-legend .s { color: ${C.red}; }
        .pp-vault { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 4px; }
        .pp-vault div { background: rgba(8,6,15,0.4); border: 1px solid rgba(255,255,255,0.05); border-radius: var(--r-sm); padding: 8px 10px; }
        .pp-vault .k { font-family: "DM Mono", monospace; font-size: 8px; letter-spacing: 0.1em; text-transform: uppercase; color: ${C.mute}; }
        .pp-vault .v { font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 14px; color: ${C.cream}; margin-top: 2px; }

        .pp-pos { display: grid; gap: 9px; }
        .pp-pos-empty { font-family: "DM Sans", sans-serif; font-size: 12px; color: ${C.mute}; text-align: center; padding: 26px 0; opacity: 0.7; }
        .pp-stale { margin-bottom: 11px; padding: 10px 12px; border-radius: var(--r-sm); background: ${C.red}14; border: 1px solid ${C.red}55; color: ${C.cream}; font-family: "DM Sans", sans-serif; font-size: 11px; line-height: 1.45; }
        .pp-agg { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 12px 13px; margin-bottom: 11px; border-radius: var(--r-sm); background: rgba(8,6,15,0.5); border: 1px solid rgba(255,255,255,0.06); flex-wrap: wrap; }
        .pp-agg__k { font-family: "DM Mono", monospace; font-size: 8.5px; letter-spacing: 0.12em; text-transform: uppercase; color: ${C.mute}; }
        .pp-agg__v { font-family: "Fredoka", sans-serif; font-weight: 700; font-size: 22px; letter-spacing: -0.01em; margin-top: 2px; }
        .pp-agg__pct { font-size: 13px; opacity: 0.85; }
        .pp-agg__sub { font-size: 9.5px; color: ${C.mute}; margin-top: 3px; }
        .pp-agg__btns { display: flex; gap: 7px; }
        .pp-agg__card { padding: 8px 12px; border-radius: var(--r-sm); border: 1px solid ${col}66; background: ${col}14; color: ${col}; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px; cursor: pointer; transition: all .15s ease; }
        .pp-agg__card:hover { background: ${col}26; }
        .pp-agg__closeall { padding: 8px 12px; border-radius: var(--r-sm); border: 1px solid ${C.red}66; background: ${C.red}14; color: ${C.red}; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px; cursor: pointer; transition: all .15s ease; }
        .pp-agg__closeall:hover:not(:disabled) { background: ${C.red}26; }
        .pp-agg__closeall:disabled { opacity: 0.5; cursor: default; }
        .pp-p { border-radius: var(--r-sm); padding: 12px 13px; background: rgba(8,6,15,0.4); border: 1px solid rgba(255,255,255,0.06); }
        .pp-p.liq { border-color: ${C.red}66; box-shadow: 0 0 0 1px ${C.red}22; }
        .pp-p-top { display: flex; align-items: center; justify-content: space-between; margin-bottom: 9px; }
        .pp-badge { font-family: "DM Mono", monospace; font-size: 10px; font-weight: 700; padding: 3px 8px; border-radius: var(--r-chip); letter-spacing: 0.04em; }
        .pp-badge.long { color: ${col}; background: ${col}18; } .pp-badge.short { color: ${C.red}; background: ${C.red}18; }
        .pp-pnl { font-family: "Fredoka", sans-serif; font-weight: 700; font-size: 15px; }
        .pp-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 7px; margin-bottom: 10px; }
        .pp-cell .k { font-family: "DM Mono", monospace; font-size: 8px; letter-spacing: 0.08em; text-transform: uppercase; color: ${C.mute}; }
        .pp-cell .v { font-family: "DM Mono", monospace; font-size: 11px; color: ${C.cream}; margin-top: 2px; }
        .pp-foot { display: flex; gap: 7px; }
        .pp-cardbtn { flex: 0 0 auto; padding: 8px 12px; border-radius: var(--r-sm); border: 1px solid; background: rgba(255,255,255,0.02); font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px; cursor: pointer; transition: all 0.15s ease; white-space: nowrap; }
        .pp-cardbtn:hover { background: rgba(255,255,255,0.06); }
        .pp-close { flex: 1; width: 100%; padding: 8px; border-radius: var(--r-sm); border: 1px solid rgba(255,255,255,0.14); background: rgba(255,255,255,0.03); color: ${C.cream}; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px; cursor: pointer; transition: all 0.15s ease; }
        .pp-close:hover:not(:disabled) { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.24); }
        .pp-close:disabled { opacity: 0.5; cursor: default; }
        .pp-liq-tag { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.red}; }
        @keyframes pp-spin { to { transform: rotate(360deg); } }
      `}</style>

      {toast && (
        <div className={`pp-toast pp-toast--${toast.kind}`} role="status">
          <span className="pp-toast__ic">{toast.kind === "err" ? "⚠️" : "✅"}</span>
          <span>{toast.msg}</span>
          <button className="pp-toast__x" onClick={() => setToast(null)} aria-label="Dismiss">×</button>
        </div>
      )}

      {/* ── open a position ── */}
      <div className="pp-card">
        <div className="pp-eyebrow"><span>Open position</span><span>max <b>{maxLev}×</b></span></div>

        <div className="pp-toggle">
          <button className={side === "long" ? "on--long" : ""} onClick={() => { setSide("long"); setErr(""); }}>Long ↑</button>
          <button className={side === "short" ? "on--short" : ""} onClick={() => { setSide("short"); setErr(""); }}>Short ↓</button>
        </div>

        <div className="pp-field">
          <div className="pp-field-top">
            <span className="pp-lbl">Collateral</span>
            <span className="pp-lbl">{collateral * ethUsd > 0 ? `≈ $${(collateral * ethUsd).toFixed(2)}` : ""}</span>
          </div>
          <div className="pp-row">
            <input className="pp-input" inputMode="decimal" placeholder="0.0" value={amt}
              onChange={(e) => setAmt(e.target.value.replace(/[^0-9.]/g, ""))} />
            <span className="pp-coin"><span style={{ color: "#627EEA" }}>Ξ</span>ETH</span>
          </div>
        </div>
        <div className="pp-chips">
          {QUICK.map((q) => (
            <button key={q} className={`pp-chip ${collateral === q ? "pp-chip--on" : ""}`} onClick={() => setAmt(String(q))}>{q}</button>
          ))}
        </div>

        <div className="pp-lev">
          <div className="pp-lev-top"><span className="pp-lbl">Leverage</span><span className="pp-lev-v">{lev}×</span></div>
          <input type="range" min={1} max={maxLev} step={1} value={lev} className="pp-range"
            style={{ ["--pct" as string]: `${((lev - 1) / Math.max(1, maxLev - 1)) * 100}%` }}
            onChange={(e) => setLev(Number(e.target.value))} />
          <div className="pp-ticks">{Array.from({ length: maxLev }, (_, i) => <span key={i}>{i + 1}×</span>)}</div>
        </div>

        <div className="pp-summary">
          <div className="pp-line"><span className="pp-line-l">Notional</span><span className={`pp-line-v ${overNotional ? "warn" : ""}`}>{notional.toFixed(4)} Ξ{stats.depthEth > 0 ? ` / ${compact(notionalCap)} max` : ""}</span></div>
          <div className="pp-line"><span className="pp-line-l">Entry price</span><span className="pp-line-v">{priceUsd > 0 ? `$${priceUsd < 0.01 ? priceUsd.toPrecision(2) : priceUsd.toFixed(4)}` : gwei(spotPrice)}</span></div>
          <div className="pp-line"><span className="pp-line-l">Est. liquidation</span><span className="pp-line-v warn">{gwei(liqPrice)} <span style={{ opacity: 0.7 }}>(−{liqDeltaPct.toFixed(0)}%)</span></span></div>
          <div className="pp-line"><span className="pp-line-l">Open fee ({(feeBps / 100).toFixed(1)}% collat.)</span><span className="pp-line-v">{feeEth.toFixed(5)} Ξ</span></div>
          <div className="pp-line"><span className="pp-line-l">Vault can lend ({side}s)</span><span className={`pp-line-v ${overLiquidity ? "warn" : ""}`}>{compact(sideCap)} Ξ{overLiquidity ? ` · max ~${compact(maxCollateral)} Ξ` : ""}</span></div>
        </div>

        {wouldLiquidateOnOpen && collateral > 0 && (
          <div className="pp-warn">
            ⚠️ Mark is {Math.abs(markDivergePct).toFixed(1)}% {markDivergePct >= 0 ? "above" : "below"} spot — a {lev}× {side} would be
            liquidated the instant it opens (fills at spot, marked vs the 5-min TWAP). Wait for the mark to catch up, lower leverage, or trade the other side.
          </div>
        )}
        <button className="pp-cta" onClick={onOpen} disabled={busy || (isConnected && !canOpen)}>
          {busy && <span style={{ display: "inline-block", animation: "pp-spin 1s linear infinite", marginRight: 6 }}>⏳</span>}
          {btnLabel}
        </button>
        {err && <div className="pp-err">{err}</div>}
        <p className="pp-note">
          Leverage executes <b>real swaps</b> — your position moves the chart. Liquidations trigger off a manipulation-resistant TWAP mark; fees fund the OG dividend + treasury.
        </p>
      </div>

      {/* ── OI, funding, vault + positions ── */}
      <div style={{ display: "grid", gap: 14 }}>
        <div className="pp-card">
          <div className="pp-eyebrow"><span>Open interest</span><span>{stats.live ? `${fundingSide} · ${(Math.abs(stats.fundingIdx) * 100).toFixed(3)}%` : "—"}</span></div>
          <div className="pp-oi">
            <div className="pp-oi-bar">
              <div className="pp-oi-long" style={{ width: `${longShare}%` }} />
              <div className="pp-oi-short" style={{ width: `${100 - longShare}%` }} />
            </div>
            <div className="pp-oi-legend">
              <span className="l">Longs {stats.longOiEth.toFixed(2)} Ξ</span>
              <span className="s">{stats.shortOiEth.toFixed(2)} Ξ Shorts</span>
            </div>
          </div>
          <div className="pp-vault">
            <div><div className="k">Depth</div><div className="v">{compact(stats.depthEth)} Ξ</div></div>
            <div><div className="k">Vault ETH</div><div className="v">{compact(stats.plvEth)} Ξ</div></div>
            <div><div className="k">Vault {ticker}</div><div className="v">{compact(stats.plvToken)}</div></div>
          </div>
        </div>

        <div className="pp-card">
          <div className="pp-eyebrow"><span>Your positions</span><span>{perp.positions.length || 0}</span></div>
          {/* Data-freshness guard: when the indexer has diverged from the chain we
              must NOT present an empty list as truth — a trader could have live
              exposure the indexer isn't showing. Warn + point them on-chain. */}
          {stats.stale && (
            <div className="pp-stale" role="status">
              ⚠ Live data is delayed — open positions may not appear here yet. Your positions are safe on-chain; verify on the explorer before trading.
            </div>
          )}
          {perp.positions.length === 0 ? (
            <div className="pp-pos-empty">{!stats.live ? "Perps activate when the engine deploys." : stats.stale ? "Positions unavailable while data is delayed." : "No open positions yet."}</div>
          ) : (
            <>
              {/* overall PnL + actions */}
              <div className="pp-agg">
                <div>
                  <div className="pp-agg__k">Total unrealized PnL</div>
                  <div className="pp-agg__v" style={{ color: agg.pnlEth >= 0 ? col : C.red }}>
                    {agg.pnlEth >= 0 ? "+" : ""}{agg.pnlEth.toFixed(4)} Ξ
                    <span className="pp-agg__pct"> ({agg.pnlEth >= 0 ? "+" : ""}{agg.roiPct.toFixed(1)}%)</span>
                  </div>
                  <div className="pp-agg__sub tc-mono">{agg.collateralEth.toFixed(4)} Ξ collateral · {perp.positions.length} open</div>
                </div>
                <div className="pp-agg__btns">
                  <button className="pp-agg__closeall" onClick={() => perp.closeAll()} disabled={perp.closingBusy}>
                    {perp.closingBusy ? "Closing…" : "Close all"}
                  </button>
                </div>
              </div>
              <div className="pp-pos">
                {perp.positions.map((p) => (
                  <PositionCard key={p.id.toString()} p={p} col={col} ticker={ticker} spotPrice={spotPrice}
                    onClose={(c) => onClosePosition(p.id, c)} busy={perp.closingBusy}
                    onCard={(c) => setCard(c)} />
                ))}
              </div>
            </>
          )}
        </div>
      </div>

      {card && (
        <PnlCard ticker={ticker} col={col} spotPrice={spotPrice} priceUsd={priceUsd}
          pnlEth={card.pnlEth} roiPct={card.roiPct} kind={card.kind} leverage={card.leverage}
          isLong={card.isLong} entryPrice={card.entryPrice} onClose={() => setCard(null)} />
      )}

      {liqHit && <LiquidatoorModal hit={liqHit} onClose={ackLiq} />}
    </div>
  );
}

/** Live PnL (ETH) for a position at the current spot. Shared by the cards + agg. */
export function positionPnl(p: PerpPosition, spotPrice: number): number {
  if (!(spotPrice > 0) || !(p.entryPrice > 0)) return 0;
  const markValueEth = p.notionalEth * (spotPrice / p.entryPrice);
  return p.isLong ? markValueEth - p.notionalEth : p.notionalEth - markValueEth;
}

function PositionCard({ p, col, spotPrice, onClose, busy, onCard }: {
  p: PerpPosition; col: string; ticker: string; spotPrice: number;
  onClose: (card: CardData) => void; busy: boolean; onCard: (c: CardData) => void;
}) {
  const priced = spotPrice > 0 && p.entryPrice > 0;
  const markValueEth = priced ? p.notionalEth * (spotPrice / p.entryPrice) : p.notionalEth;
  const pnlEth = positionPnl(p, spotPrice);
  const up = pnlEth >= 0;
  const pnlPct = p.collateralEth > 0 ? (pnlEth / p.collateralEth) * 100 : 0;
  const liqPrice = spotPrice > 0
    ? (p.isLong
      ? spotPrice * ((p.leverage - 1) * (1 + MAINTENANCE)) / p.leverage
      : spotPrice * ((p.leverage + 1) * (1 - MAINTENANCE)) / p.leverage)
    : 0;
  const liquidatable = priced && (p.isLong ? spotPrice <= liqPrice : spotPrice >= liqPrice);
  return (
    <div className={`pp-p ${liquidatable ? "liq" : ""}`}>
      <div className="pp-p-top">
        <span className={`pp-badge ${p.isLong ? "long" : "short"}`}>{p.isLong ? "LONG" : "SHORT"} {p.leverage}×</span>
        <span className="pp-pnl" style={{ color: up ? col : C.red, cursor: "pointer" }}
          title="Share PnL card"
          onClick={() => onCard({ pnlEth, roiPct: pnlPct, kind: up ? "win" : "loss", leverage: p.leverage, isLong: p.isLong, entryPrice: p.entryPrice })}>
          {up ? "+" : ""}{pnlEth.toFixed(4)} Ξ <span style={{ fontSize: 11, opacity: 0.8 }}>({up ? "+" : ""}{pnlPct.toFixed(1)}%)</span>
        </span>
      </div>
      <div className="pp-grid">
        <div className="pp-cell"><div className="k">Collateral</div><div className="v">{p.collateralEth.toFixed(4)} Ξ</div></div>
        <div className="pp-cell"><div className="k">Mark value</div><div className="v">{markValueEth.toFixed(4)} Ξ</div></div>
        <div className="pp-cell"><div className="k">Liq. price</div><div className="v">{gwei(liqPrice)}</div></div>
      </div>
      {liquidatable && <div className="pp-liq-tag" style={{ marginBottom: 8 }}>⚠ At liquidation risk</div>}
      <div className="pp-foot">
        <button className="pp-cardbtn" style={{ color: up ? col : C.red, borderColor: `${up ? col : C.red}55` }}
          title="Share this position's PnL card"
          onClick={() => onCard({ pnlEth, roiPct: pnlPct, kind: up ? "win" : "loss", leverage: p.leverage, isLong: p.isLong, entryPrice: p.entryPrice })}>
          ◆ Card
        </button>
        <button className="pp-close" disabled={busy}
          onClick={() => onClose({ pnlEth, roiPct: pnlPct, kind: up ? "win" : "loss", leverage: p.leverage, isLong: p.isLong, entryPrice: p.entryPrice })}>
          {busy ? <><span style={{ display: "inline-block", animation: "pp-spin 1s linear infinite", marginRight: 6 }}>⏳</span>Closing… (may take ~15s)</> : "Close position"}
        </button>
      </div>
    </div>
  );
}

const C = { void: "#08060f", lime: "#d5fd51", red: "#ff5470", cream: "#F5F0E8", mute: "#8f83b8" };
