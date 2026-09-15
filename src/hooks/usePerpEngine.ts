import { useCallback, useEffect, useRef, useState } from "react";
import { parseEther, parseUnits, type Address } from "viem";
import { useAccount, useSwitchChain, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { readContract, waitForTransactionReceipt } from "@wagmi/core";
import { wagmiConfig } from "@/config/chains";
import { ERC20_SWAP_ABI } from "@/config/cauldron";
import { NATIVE_QUOTE, isNativeQuote } from "@/config/quotes";
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
/**
 * Gas headroom for an open, sized to fund the post-open sweep in full.
 *
 *  NOT ONLY FOR "HINTED" OPENS. `PerpEngine._sweepAfterOpen` fires on EVERY
 *  open — it forwards `gasleft() - 120_000` into a self-sweep so an open can
 *  also liquidate underwater positions. `liqHint` is legacy and does not gate
 *  that, so attaching this only when a hint was passed left the common path on
 *  the wallet's estimate, which is computed against a state where nothing may be
 *  liquidatable yet. The sweep is best-effort and swallowed, so an under-gassed
 *  open just silently liquidates nothing.
 *
 *  Same derivation as LIQ_SWAP_GAS in useCauldronSwap: MAX_LIQ_PER_SWAP (8) x
 *  SWEEP_KILL_RESERVE (420k) = 3.36M of kills, plus the engine's own 120k
 *  post-open reserve, plus the open's own swap. 5M leaves honest headroom, and
 *  EIP-1559 bills gas USED, so the unused limit costs nothing.
 */
//  An open's own swap also passes through the hook's pre-emptive sweep before
//  the engine's post-open self-sweep, so it can fund two bounded sweeps too.
const LIQ_OPEN_GAS = 8_000_000n;
const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/** `expected × (1 - slippage)`, in the engine's own units.
 *
 *  `decimals` is the OUTPUT asset's: a long's floor counts CREATURE TOKENS
 *  (always 18), a short's counts QUOTE (6 for USDG). Hard-coding 18 here made a
 *  short's floor 1e12 too large on a 6-decimal book — unfillable at any price. */
function floorFrom(expected: number, slipBps: number = PERP_SLIPPAGE_BPS, decimals = 18): bigint {
  if (!Number.isFinite(expected) || expected <= 0) return 0n;
  //  Clamp rather than trust: a caller-supplied tolerance must never widen past
  //  "any price at all", which is what a 100% floor would mean.
  const bps = Math.min(9_000, Math.max(0, Math.round(slipBps)));
  const d = Math.min(Math.max(Math.trunc(decimals), 0), 18);
  return (parseUnits(expected.toFixed(d), d) * BigInt(10_000 - bps)) / 10_000n;
}

/** The generation's quote asset, as the perp forms need to know it. */
export type PerpQuote = { address: Address; decimals: number; symbol: string };
export const NATIVE_PERP_QUOTE: PerpQuote = { address: NATIVE_QUOTE, decimals: 18, symbol: "ETH" };

/**  ── COLLATERAL TRANSPORT, BY QUOTE (audit A-1) ────────────────────────────
 *  `PerpEngine._pullQuote` (:231) takes NATIVE collateral as `msg.value` and
 *  ERC20 collateral by `transferFrom`, and reverts `BadParam()` if the wrong one
 *  is used — `msg.value != amount` on a native book, `msg.value != 0` on an
 *  ERC20 one. These forms hard-coded `parseEther` + a native `value`, so on a
 *  6-decimal USDG generation EVERY open reverted. Returns the raw amount to send
 *  and the value to attach, approving the engine first when the quote is ERC20.
 */
async function prepareCollateral(
  owner: Address,
  q: PerpQuote,
  typed: number,
  approve: (token: Address, amount: bigint) => Promise<`0x${string}`>,
): Promise<{ raw: bigint; value: bigint }> {
  const d = Math.min(Math.max(Math.trunc(q.decimals), 0), 18);
  const raw = parseUnits(typed.toFixed(d), d);
  if (raw <= 0n) throw new Error("Enter a collateral amount");
  if (isNativeQuote(q.address)) return { raw, value: raw };
  const current = (await readContract(wagmiConfig, {
    address: q.address, abi: ERC20_SWAP_ABI, functionName: "allowance",
    args: [owner, PERP.engine], chainId: PERP.chainId,
  })) as bigint;
  //  BOUNDED to this open — never maxUint256; same stance as the swap buy leg.
  if (current < raw) {
    const ah = await approve(q.address, raw);
    await waitForTransactionReceipt(wagmiConfig, { hash: ah, chainId: PERP.chainId });
  }
  return { raw, value: 0n };
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
  const openLong = useCallback(async (collateralEth: number, leverage: number, liqHint: bigint = 0n, spotPrice = 0, slipBps = PERP_SLIPPAGE_BPS, quote: PerpQuote = NATIVE_PERP_QUOTE) => {
    if (!address) throw new Error("Connect a wallet first");
    if (!(spotPrice > 0)) throw new Error("No price for this market yet — refusing to open at any price");
    await ensureChain();
    beginAction("open");
    const { raw, value } = await prepareCollateral(address, quote, collateralEth, (t, a) =>
      writeContractAsync({ address: t, abi: ERC20_SWAP_ABI, functionName: "approve", args: [PERP.engine, a] }));
    const notionalEth = collateralEth * (1 - stats.openFeeBps / 10_000) * leverage;
    //  A long BUYS the creature token, so its floor counts tokens: 18 decimals
    //  whatever the quote is. `spotPrice` is quote-per-token, so quote/price is
    //  already a token count.
    const minTokenOut = floorFrom(notionalEth / spotPrice, slipBps, 18);
    return writeContractAsync({
      address: PERP.engine, abi: PERP_ABI, functionName: "openLong",
      args: [leverage, minTokenOut, liqHint, raw], value, gas: LIQ_OPEN_GAS,
    });
  }, [address, ensureChain, beginAction, writeContractAsync, stats.openFeeBps]);

  //  A short sells the borrowed token side for ETH, so ITS floor is in ETH and
  //  tracks the notional rather than a token count.
  const openShort = useCallback(async (collateralEth: number, leverage: number, liqHint: bigint = 0n, spotPrice = 0, slipBps = PERP_SLIPPAGE_BPS, quote: PerpQuote = NATIVE_PERP_QUOTE) => {
    if (!address) throw new Error("Connect a wallet first");
    if (!(spotPrice > 0)) throw new Error("No price for this market yet — refusing to open at any price");
    await ensureChain();
    beginAction("open");
    const { raw, value } = await prepareCollateral(address, quote, collateralEth, (t, a) =>
      writeContractAsync({ address: t, abi: ERC20_SWAP_ABI, functionName: "approve", args: [PERP.engine, a] }));
    //  A short SELLS the borrowed token for quote, so its floor is in QUOTE
    //  units — 6 on USDG. This is the decimals that used to be hard-coded 18.
    const minEthOut = floorFrom(collateralEth * (1 - stats.openFeeBps / 10_000) * leverage, slipBps, quote.decimals);
    return writeContractAsync({
      address: PERP.engine, abi: PERP_ABI, functionName: "openShort",
      args: [leverage, minEthOut, liqHint, raw], value, gas: LIQ_OPEN_GAS,
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
