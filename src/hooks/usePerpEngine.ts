import { useCallback, useEffect, useRef, useState } from "react";
import { parseEther } from "viem";
import { useAccount, useSwitchChain, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { PERP, PERP_ABI, PERP_LIVE, PERP_SLIPPAGE_BPS } from "@/config/perp";
import { CAULDRON_INDEXER } from "@/config/cauldron";

export interface PerpStats {
  live: boolean;
  longOiEth: number;
  shortOiEth: number;
  plvEth: number;
  plvToken: number;
  depthEth: number;
  maxLev: number;
  fundingIdx: number;   // signed; >0 longs pay, <0 shorts pay
  dead: boolean;
  openFeeBps: number;
  ogDiscountBps: number;
  maxNotionalBps: number; // per-position notional cap (× depth) — mirrors the engine
  stale: boolean;         // indexer diverged from chain → positions/OI unreliable
}

export interface PerpPosition {
  id: bigint;
  isLong: boolean;
  leverage: number;
  collateralEth: number;
  notionalEth: number;  // entry notional (collateral × leverage)
  entryPrice: number;   // ETH per token at open
  openedAt: number;
}

const EMPTY_STATS: PerpStats = {
  live: false, longOiEth: 0, shortOiEth: 0, plvEth: 0, plvToken: 0,
  depthEth: 0, maxLev: 0, fundingIdx: 0, dead: false, openFeeBps: 690, ogDiscountBps: 5000,
  maxNotionalBps: 500, stale: false,
};
// Live the moment the engine is deployed; the indexer reads enrich the numbers.
const INITIAL_STATS: PerpStats = { ...EMPTY_STATS, live: PERP_LIVE, maxLev: 3 };
/** Gas headroom for a hinted open that may also liquidate a position (extra
 *  nested swaps + badge mint the wallet can't foresee at estimate time). */
const LIQ_OPEN_GAS = 3_000_000n;
const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/** `expected × (1 - slippage)`, in the engine's own units. */
function floorFrom(expected: number): bigint {
  if (!Number.isFinite(expected) || expected <= 0) return 0n;
  return (parseEther(expected.toFixed(18)) * BigInt(10_000 - PERP_SLIPPAGE_BPS)) / 10_000n;
}

/**
 * usePerpEngine — the trading brain for the perp panel. ALL READS COME FROM
 * PONDER (the indexer): engine stats via /perp-heatmap/:gen (which reads live
 * chain state server-side with rotated keys), and the wallet's positions via
 * /perp-positions/:trader. The browser makes NO read RPC calls. Only the write
 * actions (openLong/openShort/close) + the receipt watch touch the wallet/chain.
 */
export function usePerpEngine(generation = 1) {
  const { address, chainId } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  // NO RPC READS. writeContractAsync submits the tx (the wallet signs it — that's
  // the only chain interaction). Confirmation, positions, stats — ALL from PONDER.
  const { writeContractAsync, data: txHash, isPending, reset, error: writeError } = useWriteContract();
  const [pendingAction, setPendingAction] = useState<"open" | "close" | null>(null);
  const txError = writeError ? (writeError as { shortMessage?: string; message?: string }) : null;
  // ONE receipt read for the user's own tx — so a tx that was sent but REVERTED
  // on-chain (e.g. open blocked by a guard) surfaces an error instead of silently
  // timing out. This is the only RPC read; everything else stays Ponder-only.
  const { data: receipt, isError: receiptError } = useWaitForTransactionReceipt({ hash: txHash, chainId: PERP.chainId });

  const [stats, setStats] = useState<PerpStats>(INITIAL_STATS);
  const [positions, setPositions] = useState<PerpPosition[]>([]);
  const [loading, setLoading] = useState(false);

  // ── PONDER-ONLY confirmation ──
  // An open lands when a NEW position appears in your list; a close when one
  // leaves. Baseline the count when an action starts; Ponder polls fast (below),
  // so this resolves in ~2-3s after the indexer sees the tx — no RPC receipt.
  const positionsRef = useRef<PerpPosition[]>([]);
  positionsRef.current = positions;
  const baselineCountRef = useRef(0);
  const [ponderConfirmed, setPonderConfirmed] = useState(false);
  useEffect(() => {
    if (!pendingAction) return;
    const n = positions.length, base = baselineCountRef.current;
    if ((pendingAction === "open" && n > base) || (pendingAction === "close" && n < base)) {
      setPonderConfirmed(true); setPendingAction(null);
    }
  }, [positions, pendingAction]);
  // Wallet-rejection / safety: drop the busy state on a write error, a reverted
  // receipt, or after ~20s if the indexer somehow never reflects it.
  const reverted = receipt?.status === "reverted";
  useEffect(() => {
    if (txError || reverted) { setPendingAction(null); return; }
    if (!pendingAction) return;
    const t = setTimeout(() => setPendingAction(null), 20000);
    return () => clearTimeout(t);
  }, [pendingAction, txHash, txError, reverted]);

  const confirmed = ponderConfirmed;
  const receiptFailed = !!receiptError;
  const confirming = !!pendingAction && !ponderConfirmed;
  const openingBusy = confirming && pendingAction === "open";
  const closingBusy = confirming && pendingAction === "close";

  // ── engine stats FROM PONDER (/perp-heatmap serves live depth/vault/OI) ──
  useEffect(() => {
    if (!PERP_LIVE || !INDEXER) { setStats(INITIAL_STATS); return; }
    let alive = true;
    const load = async () => {
      try {
        const res = await fetch(`${INDEXER}/perp-heatmap/${generation}`, { signal: AbortSignal.timeout(12000) });
        if (!res.ok) return;
        const d = await res.json() as Partial<PerpStats> & { openCount?: number; stale?: boolean };
        if (!alive) return;
        setStats({
          live: true,
          longOiEth: d.longOiEth ?? 0, shortOiEth: d.shortOiEth ?? 0,
          plvEth: d.plvEth ?? 0, plvToken: d.plvToken ?? 0, depthEth: d.depthEth ?? 0,
          maxLev: d.maxLev || 3, fundingIdx: d.fundingIdx ?? 0, dead: !!d.dead,
          openFeeBps: d.openFeeBps ?? 690, ogDiscountBps: d.ogDiscountBps ?? 5000,
          maxNotionalBps: d.maxNotionalBps ?? 500, stale: !!d.stale,
        });
      } catch { /* keep last */ }
    };
    load();
    // Pause while the tab is backgrounded, refresh on return: an idle tab
    // should cost nothing. Mirrors usePoll.
    let t: ReturnType<typeof setInterval> | null = setInterval(load, 4000);
    const onVis = () => {
      if (document.hidden) { if (t) { clearInterval(t); t = null; } }
      else if (!t) { load(); t = setInterval(load, 4000); }
    };
    document.addEventListener("visibilitychange", onVis);
    return () => {
      alive = false;
      if (t) clearInterval(t);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [generation, confirmed]);

  // ── the wallet's open positions FROM PONDER (/perp-positions/:trader) ──
  // Polls FAST — 1.2s while an action is pending (so the button + list update
  // ~instantly on confirm), 3s at rest.
  useEffect(() => {
    if (!PERP_LIVE || !address || !INDEXER) { setPositions([]); return; }
    let alive = true;
    const load = async () => {
      setLoading(true);
      try {
        const res = await fetch(`${INDEXER}/perp-positions/${address}`, { signal: AbortSignal.timeout(12000) });
        if (!res.ok) return;
        const d = await res.json() as { positions?: Array<{ id: string; isLong: boolean; leverage: number; collateralEth: number; notionalEth: number; entryPrice: number; openedAt: number }> };
        if (!alive) return;
        setPositions((d.positions ?? []).map((p) => ({
          id: BigInt(p.id), isLong: p.isLong, leverage: p.leverage,
          collateralEth: p.collateralEth, notionalEth: p.notionalEth,
          entryPrice: p.entryPrice, openedAt: p.openedAt,
        })).sort((a, b) => b.openedAt - a.openedAt));
      } catch { /* keep last */ }
      finally { if (alive) setLoading(false); }
    };
    load();
    const t = setInterval(load, pendingAction ? 1200 : 3000);
    return () => { alive = false; clearInterval(t); };
  }, [address, generation, confirmed, pendingAction]);

  // ── actions (wallet writes — the only chain interaction from the browser) ──
  // Each action RESETS the prior tx state first, so a previous close/open never
  // bleeds into the next (which was leaving the button stuck on "Opening…").
  const ensureChain = useCallback(async () => {
    reset();
    if (chainId !== PERP.chainId) await switchChainAsync({ chainId: PERP.chainId });
  }, [chainId, switchChainAsync, reset]);

  // Baseline the position count + arm the pending action so the Ponder-based
  // confirmation can detect the change (new position for open / gone for close).
  const beginAction = useCallback((kind: "open" | "close") => {
    baselineCountRef.current = positionsRef.current.length;
    setPonderConfirmed(false);
    setPendingAction(kind);
  }, []);

  // `liqHint` (optional): a position to liquidate on open — if it's underwater at
  // the mark, YOUR open rekts it and mints you a Liquidatoor badge. 0n = none
  // (uses the plain 2-arg open); a stale/healthy hint is a silent no-op on-chain.
  // Always the 3-arg form (liqHint = 0n when none) — the engine's canonical
  // opener. A stale/healthy/zero hint is a silent no-op on-chain, so passing 0n
  // is safe and keeps ONE ABI shape (the 2-arg openShort no longer exists).
  //  `spotPrice` is ETH PER TOKEN, the same number the panel prices the ticket
  //  with. The engine buys `collateral × leverage` worth of ETH into tokens
  //  (`PerpEngine.sol:800-818`) and reverts `Slippage()` when the swap returns
  //  less than `minTokenOut`, so the floor is expressed in TOKENS. Computing it
  //  with the FULL open fee (ignoring any OG discount) understates the expected
  //  size, which errs toward filling rather than reverting.
  //
  //  The 4th argument is the collateral amount; on a native book it must equal
  //  the ETH sent.
  const openLong = useCallback(async (collateralEth: number, leverage: number, liqHint: bigint = 0n, spotPrice = 0) => {
    if (!address) throw new Error("Connect a wallet first");
    if (!(spotPrice > 0)) throw new Error("No price for this market yet — refusing to open at any price");
    await ensureChain();
    beginAction("open");
    const value = parseEther(collateralEth.toFixed(18));
    const notionalEth = collateralEth * (1 - stats.openFeeBps / 10_000) * leverage;
    const minTokenOut = floorFrom(notionalEth / spotPrice);
    return writeContractAsync({
      address: PERP.engine, abi: PERP_ABI, functionName: "openLong",
      args: [leverage, minTokenOut, liqHint, value], value, ...(liqHint > 0n ? { gas: LIQ_OPEN_GAS } : {}),
    });
  }, [address, ensureChain, beginAction, writeContractAsync, stats.openFeeBps]);

  //  A short sells the borrowed token side for ETH, so ITS floor is in ETH and
  //  tracks the notional rather than a token count.
  const openShort = useCallback(async (collateralEth: number, leverage: number, liqHint: bigint = 0n, spotPrice = 0) => {
    if (!address) throw new Error("Connect a wallet first");
    if (!(spotPrice > 0)) throw new Error("No price for this market yet — refusing to open at any price");
    await ensureChain();
    beginAction("open");
    const value = parseEther(collateralEth.toFixed(18));
    const minEthOut = floorFrom(collateralEth * (1 - stats.openFeeBps / 10_000) * leverage);
    return writeContractAsync({
      address: PERP.engine, abi: PERP_ABI, functionName: "openShort",
      args: [leverage, minEthOut, liqHint, value], value, ...(liqHint > 0n ? { gas: LIQ_OPEN_GAS } : {}),
    });
  }, [address, ensureChain, beginAction, writeContractAsync, stats.openFeeBps]);

  //  `expectedOutEth` is what `_settle` compares `minOut` against — the gross
  //  sale proceeds for a long (`PerpEngine.sol:1179-1180`) and the trader's ETH
  //  residual for a short (`:1202`). Only the trader's own close enforces it
  //  (`ownerSlippage`, :1175), which is precisely this call.
  //
  //  0 means "fill at any price" and was what every close signed. It is kept
  //  ONLY as the unpriceable fallback: with no mark, refusing to close would
  //  trap the position, which is worse than the status quo — so the panel
  //  passes 0 only when it genuinely has no price.
  const closePosition = useCallback(async (id: bigint, expectedOutEth = 0) => {
    await ensureChain();
    setPendingAction("close");
    return writeContractAsync({
      address: PERP.engine, abi: PERP_ABI, functionName: "close",
      args: [id, floorFrom(expectedOutEth)],
    });
  }, [ensureChain, writeContractAsync]);

  /** Close EVERY open position — sends one tx per position (wallet signs each). */
  const closeAll = useCallback(async (expectedOutEth?: (p: PerpPosition) => number) => {
    if (positions.length === 0) return;
    if (chainId !== PERP.chainId) await switchChainAsync({ chainId: PERP.chainId });
    setPendingAction("close");
    for (const p of positions) {
      try {
        await writeContractAsync({
          address: PERP.engine, abi: PERP_ABI, functionName: "close",
          args: [p.id, floorFrom(expectedOutEth ? expectedOutEth(p) : 0)],
        });
      } catch { /* user rejected one → keep going with the rest */ }
    }
  }, [positions, chainId, switchChainAsync, writeContractAsync]);

  return {
    live: PERP_LIVE, stats, positions, loading,
    openLong, openShort, closePosition, closeAll,
    pendingAction, openingBusy, closingBusy,
    txHash, isPending, confirming, confirmed, reverted, receiptFailed, txError, reset,
  };
}
