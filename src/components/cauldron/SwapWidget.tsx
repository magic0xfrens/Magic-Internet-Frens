import { useEffect, useMemo, useRef, useState } from "react";
import { formatEther, parseEther, type Address } from "viem";
import { useAccount, useReadContract } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { useCauldronSwap } from "@/hooks/useCauldronSwap";
import { usePerpLiqHint } from "@/hooks/usePerpLiqHint";
import { NATIVE_QUOTE, isNativeQuote } from "@/config/quotes";
import { useLiquidatoorWatch } from "@/hooks/useLiquidatoorWatch";
import LiquidatoorModal from "@/components/cauldron/LiquidatoorModal";
import { CAULDRON, ERC20_SWAP_ABI, TRADE_FEE_BPS } from "@/config/cauldron";
import { explorerTxUrl } from "@/config/chains";

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
  /** The asset this generation's pool is priced in. A completed rotation flips
   *  it (address(0) = native ETH), and the buy leg must follow: the router
   *  reverts `ErcQuoteTakesNoValue` if a native-shaped buy is sent to an
   *  ERC20-quoted generation. */
  quote?: Address;
  quoteSymbol?: string;
  quoteDecimals?: number;
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
 * Adjustable, because a fixed tolerance chosen silently on the user's behalf is
 * the other half of the same mistake — but tucked behind the gear in the header,
 * because a control most traders touch once does not deserve a permanent row.
 *
 *  ── WHY THE PRESETS MOVED OFF 0.5/1/3 ─────────────────────────────────────
 *  The estimate these floors are derived from now subtracts the protocol fee
 *  ({TRADE_FEE_BPS}) — see the note there for the reverts that omission caused —
 *  so the tolerance is once again covering only what a tolerance should: price
 *  impact and whatever the price does between quote and mine. 3% is the default
 *  because this pool is thin enough that a 0.05Ξ buy walks ~1.9% of impact on its
 *  own; 1% is kept for when it deepens, and 10% for a deliberate ape. Anything
 *  else goes in the box.
 */
const SLIP_PRESETS = [1, 3, 10] as const;
const DEFAULT_SLIP_PCT = 3;
const MAX_SLIP_PCT = 50;
/**  A tolerance the trader chose should survive a page load — the alternative is
 *   re-picking it on every visit, which is how people end up leaving it wherever
 *   it landed. */
const SLIP_KEY = "mifrens.swap.slipPct";

function loadSlip(): number {
  try {
    const v = Number(localStorage.getItem(SLIP_KEY));
    return Number.isFinite(v) && v > 0 && v <= MAX_SLIP_PCT ? v : DEFAULT_SLIP_PCT;
  } catch { return DEFAULT_SLIP_PCT; }
}

/** What survives the hook's skim on the ETH side of a swap. */
const netOfFee = (x: number) => x * (1 - TRADE_FEE_BPS / 10_000);

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
export default function SwapWidget({
  ticker, token, spotPrice, priceUsd, ethUsd, col, onBought,
  quote = NATIVE_QUOTE, quoteSymbol = "ETH", quoteDecimals = 18,
}: SwapWidgetProps) {
  //  The buy leg is denominated in the GENERATION'S quote, which is ETH for
  //  every generation until a rotation completes. `qNative` drives both the
  //  transaction shape and every label that used to hardcode ether.
  const qNative = isNativeQuote(quote);
  const qGlyph = qNative ? "Ξ" : quoteSymbol;


  const [mode, setMode] = useState<"buy" | "sell">("buy");
  const [buyAmt, setBuyAmt] = useState<string>("0.05");
  const [sellAmt, setSellAmt] = useState<string>("");
  const [err, setErr] = useState<string>("");
  const [faucetBusy, setFaucetBusy] = useState(false);


  const [slipPct, setSlipPct] = useState<number>(loadSlip);
  const [slipOpen, setSlipOpen] = useState(false);
  const slipRef = useRef<HTMLDivElement>(null);
  const { address, isConnected } = useAccount();

  //  ── THE TESTNET FAUCET ────────────────────────────────────────────────
  //  A rotation can redenominate the generation into an asset NOBODY HOLDS.
  //  On Sepolia the quote is a MockQuoteToken whose `mint` is deliberately
  //  public ("Anyone may mint. Testnet only"), so the honest fix for a tester
  //  staring at a buy button they cannot use is to offer the mint — not to
  //  explain in a docs page why trading stopped.
  //
  //  Chain-gated, not build-gated: this must never render against mainnet,
  //  where the quote is a real asset and `mint` does not exist.
  const isTestnet = CAULDRON.chainId === 11155111;
  const { data: quoteBal, refetch: refetchQuoteBal } = useReadContract({
    address: qNative ? undefined : (quote as Address),
    abi: ERC20_SWAP_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: CAULDRON.chainId,
    query: { enabled: !qNative && !!address },
  });
  const needsFaucet = !qNative && isTestnet && (quoteBal ?? 0n) === 0n;
  const { openConnectModal } = useConnectModal();
  const { buy, sell, approveToken, isPending, confirming, confirmed, failed, failReason, reset, txHash , mintTestQuote } = useCauldronSwap();
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
  //  NET OF THE PROTOCOL FEE. The hook skims {TRADE_FEE_BPS} off the ETH side of
  //  every swap — off the INPUT on a buy (`beforeSwap`), off the OUTPUT on a sell
  //  (`afterSwap`) — so on both legs the trader receives the fee-adjusted amount.
  //  Quoting raw mid price here is what pushed `minOut` above every achievable
  //  fill; see {TRADE_FEE_BPS} for the reverts it caused.
  //  Price impact is NOT modelled — that is what the tolerance is for.
  const estTokensOut = useMemo(() => (spotPrice > 0 ? netOfFee(eth) / spotPrice : 0), [eth, spotPrice]);
  const estEthOut = useMemo(() => netOfFee(tokensIn * spotPrice), [tokensIn, spotPrice]);
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
  //  ── THE SPOT PRICE IS IN ETH, AND THE PAY SIDE MAY NOT BE ────────────
  //  `spotPrice` is ETH per token. On an ERC20-quoted generation the buy side is
  //  USDG, so `netOfFee(amount) / spotPrice` overstates the expected output by
  //  the whole ETH/quote ratio (~2,533x) and `minOut` lands far above anything
  //  the pool can fill. The swap then EXECUTES and fails the floor afterwards,
  //  which burns the gas and reports nothing useful.
  //
  //  Refusing is the honest outcome until the quote-denominated price is wired
  //  through: this panel already refuses to sign an unpriceable market, and a
  //  price in the wrong UNIT is not a price. Selling is unaffected — it is
  //  denominated in the token either way.
  const priceable = spotPrice > 0 && (qNative || mode === "sell");

  const needsApproval = mode === "sell" && tokensIn > 0 &&
    (allowanceWei == null || (allowanceWei as bigint) < (() => { try { return parseEther((tokensIn).toFixed(18)); } catch { return 0n; } })());

  useEffect(() => {
    try { localStorage.setItem(SLIP_KEY, String(slipPct)); } catch { /* private mode */ }
  }, [slipPct]);

  //  Dismiss the tolerance popover the way every popover should dismiss: a click
  //  anywhere else, or Escape. Without this it can be left hanging over the CTA.
  useEffect(() => {
    if (!slipOpen) return;
    const onDown = (e: MouseEvent) => {
      if (slipRef.current && !slipRef.current.contains(e.target as Node)) setSlipOpen(false);
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setSlipOpen(false); };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => { document.removeEventListener("mousedown", onDown); document.removeEventListener("keydown", onKey); };
  }, [slipOpen]);

  /*  A FAILED TRADE HAS TO SAY SO. Nothing here read the outcome of the wait, so
      the three ways a submitted buy can end badly all ended in silence: a REVERT
      showed "Done ✓" (the hook treated a mined receipt as a success), a dropped
      or replaced transaction dumped the button back to "Buy" with no message,
      and a stalled RPC left it reading "Buying..." forever. The hook now names
      all three; this puts the name on screen, next to the one thing the trader
      can act on — the transaction itself. */
  useEffect(() => {
    if (failed && failReason) setErr(failReason);
  }, [failed, failReason]);

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
        if (eth <= 0) { setErr(`Enter a ${qGlyph} amount`); return; }
        if (!priceable) { setErr("No price for this market yet — refusing to trade at any price"); return; }
        if (minOut <= 0n) { setErr("Could not compute a slippage floor — refusing to sign"); return; }
        await buy(eth, minOut, 0, liqHint, quote, quoteDecimals);
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
    : failed ? (mode === "buy" ? `Retry buy` : `Retry sell`)
    : mode === "buy" ? `Buy $${ticker}`
    : needsApproval ? `Approve $${ticker}`
    : `Sell $${ticker}`;

  return (
    <aside className="sw">
      <style>{`
        .sw { position: sticky; top: 12px; border-radius: var(--r-sm); padding: 11px 12px 12px; background: rgba(23, 18, 42, 0.28); border: 1px solid rgba(255,255,255,0.05); }
        .sw__toggle { display: flex; gap: 3px; padding: 3px; border-radius: var(--r-sm); background: rgba(8,6,15,0.5); margin-bottom: 8px; }
        .sw__toggle button {
          flex: 1; padding: 5px 0; border-radius: var(--r-sm); border: none; cursor: pointer;
          font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px;
          background: none; color: ${C.mute}; transition: all 0.15s ease;
        }
        .sw__toggle button.on--buy { background: ${col}1c; color: ${col}; }
        .sw__toggle button.on--sell { background: ${C.red}1c; color: ${C.red}; }
        .sw__head { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 7px; }
        .sw__head-r { display: flex; align-items: center; gap: 7px; }
        .sw__title { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: ${C.mute}; }
        .sw__spot { font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; }
        .sw__field { background: rgba(8,6,15,0.45); border: 1px solid rgba(255,255,255,0.05); border-radius: var(--r-sm); padding: 8px 11px; }
        .sw__field-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 3px; }
        .sw__lbl { font-family: "DM Mono", monospace; font-size: 8.5px; letter-spacing: 0.14em; text-transform: uppercase; color: ${C.mute}; }
        .sw__sub { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; }
        .sw__row { display: flex; align-items: center; gap: 8px; }
        /*  TRADE SETTINGS — a gear that states its own value, and a glass panel
            that borrows the card language above it (blur + hairline + deep
            shadow) so it reads as part of the widget rather than a browser
            popup pasted on top. */
        .sw__gear-wrap { position: relative; display: flex; }
        .sw__gear {
          display: inline-flex; align-items: center; gap: 4px; padding: 2.5px 6px 2.5px 5px;
          border-radius: var(--r-chip); border: 1px solid rgba(255,255,255,0.09);
          background: rgba(8,6,15,0.5); color: ${C.mute}; cursor: pointer;
          font-family: "DM Mono", monospace; font-size: 9.5px; line-height: 1;
          transition: color 0.15s ease, border-color 0.15s ease, background 0.15s ease;
        }
        .sw__gear:hover { color: ${C.cream}; border-color: rgba(255,255,255,0.2); }
        .sw__gear svg { transition: transform 0.35s cubic-bezier(0.34,1.3,0.64,1); }
        .sw__gear:hover svg { transform: rotate(60deg); }
        .sw__gear--on { color: ${side}; border-color: ${side}88; background: ${side}14; }
        .sw__gear--on svg { transform: rotate(60deg); }
        .sw__gear-v { letter-spacing: 0.02em; }
        .sw__pop {
          position: absolute; top: calc(100% + 7px); right: -2px; z-index: 40; width: 218px;
          padding: 11px 12px 10px; border-radius: var(--r-sm);
          background: rgba(19,14,36,0.93); border: 1px solid rgba(255,255,255,0.1);
          box-shadow: 0 18px 44px rgba(8,6,15,0.66); backdrop-filter: blur(16px);
          animation: sw-pop 0.16s cubic-bezier(0.34,1.2,0.64,1) both;
        }
        /*  The caret is two stacked pseudo-elements: the border colour first, the
            panel fill 1px below it, so the notch keeps the hairline outline. */
        .sw__pop::before, .sw__pop::after {
          content: ""; position: absolute; right: 12px; width: 9px; height: 9px;
          transform: rotate(45deg);
        }
        .sw__pop::before { top: -5.5px; background: rgba(255,255,255,0.1); }
        .sw__pop::after { top: -4.5px; background: rgba(19,14,36,0.93); }
        @keyframes sw-pop { from { opacity: 0; transform: translateY(-5px) scale(0.97); } to { opacity: 1; transform: none; } }
        .sw__pop-l { font-family: "DM Mono", monospace; font-size: 8.5px; letter-spacing: 0.16em; text-transform: uppercase; color: ${C.mute}; margin-bottom: 7px; }
        .sw__pop-opts { display: flex; align-items: center; gap: 4px; }
        .sw__slip-chip { flex: 1; padding: 4px 0; border-radius: var(--r-sm); border: 1px solid rgba(255,255,255,0.08); background: rgba(8,6,15,0.5); color: ${C.mute}; font-family: "DM Mono", monospace; font-size: 10px; cursor: pointer; transition: all 0.15s ease; }
        .sw__slip-chip:hover { border-color: ${side}66; color: ${C.cream}; }
        .sw__slip-chip--on { color: ${C.void}; background: ${side}; border-color: ${side}; }
        .sw__slip-input { width: 36px; padding: 4px 5px; border-radius: var(--r-sm); border: 1px solid rgba(255,255,255,0.08); background: rgba(8,6,15,0.5); color: #fff; font-family: "DM Mono", monospace; font-size: 10px; text-align: right; outline: none; }
        .sw__slip-input:focus { border-color: ${side}88; }
        .sw__slip-pct { font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; }
        .sw__pop-row { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; margin-top: 10px; padding-top: 9px; border-top: 1px solid rgba(255,255,255,0.07); font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; }
        .sw__pop-row b { color: ${C.cream}; font-weight: 500; font-size: 10px; }
        .sw__pop-note { font-family: "DM Sans", sans-serif; font-size: 9px; line-height: 1.45; color: ${C.mute}; opacity: 0.72; margin: 7px 0 0; }
        .sw__min { margin: 0 2px 7px; font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; opacity: 0.75; text-align: right; }
        .sw__min-warn { color: ${C.red}; opacity: 1; }
        .sw__input { flex: 1; min-width: 0; background: none; border: none; outline: none; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 19px; color: ${C.cream}; letter-spacing: -0.01em; }
        .sw__input::placeholder { color: rgba(143,131,184,0.45); }
        .sw__coin { display: inline-flex; align-items: center; gap: 5px; padding: 3px 8px; border-radius: var(--r-chip); background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.07); font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 11px; color: ${C.cream}; white-space: nowrap; }
        .sw__coin-dot { width: 13px; height: 13px; border-radius: 50%; display: grid; place-items: center; font-size: 8px; }
        .sw__faucet { width: 100%; margin-top: 7px; padding: 6px 8px; border-radius: var(--r-sm);
          background: rgba(240,180,41,0.07); border: 1px solid rgba(240,180,41,0.28);
          font-family: "DM Mono", monospace; font-size: 9.5px; color: #f0b429; cursor: pointer;
          transition: all 0.15s ease; }
        .sw__faucet:hover:not(:disabled) { background: rgba(240,180,41,0.13); }
        .sw__faucet:disabled { opacity: 0.5; cursor: default; }
        .sw__chips { display: flex; gap: 5px; margin: 6px 0 5px; }
        .sw__chip { flex: 1; padding: 4px 0; border-radius: var(--r-sm); background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; cursor: pointer; transition: all 0.15s ease; }
        .sw__chip:hover { border-color: ${side}55; color: ${C.cream}; }
        .sw__chip--on { background: ${side}1a; border-color: ${side}88; color: ${side}; }
        .sw__out { display: flex; justify-content: space-between; align-items: baseline; padding: 2px 2px 0; margin-top: 2px; }
        .sw__out-l { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; }
        .sw__out-v { font-family: "DM Mono", monospace; font-size: 12px; color: ${C.cream}; }
        .sw__gacha { font-family: "DM Sans", sans-serif; font-size: 9.5px; line-height: 1.35; color: ${C.mute}; margin: 6px 2px 7px; opacity: 0.85; }
        .sw__gacha b { color: ${col}; font-weight: 600; }
        .sw__cta { width: 100%; padding: 8px; border-radius: var(--r-sm); border: 1px solid ${side}66; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 13px; letter-spacing: 0.02em; color: ${side}; background: ${side}14; cursor: pointer; transition: background 0.15s ease, border-color 0.15s ease; }
        .sw__cta:hover:not(:disabled) { background: ${side}26; border-color: ${side}; }
        .sw__cta:disabled { opacity: 0.5; cursor: default; }
        .sw__cta--busy { background: transparent; }
        .sw__err { margin: 8px 2px 0; font-family: "DM Sans", sans-serif; font-size: 10px; color: ${C.red}; line-height: 1.45; }
        .sw__err-a, .sw__pending a { color: ${C.cream}; text-decoration: underline; text-decoration-color: rgba(255,255,255,0.3); text-underline-offset: 2px; white-space: nowrap; }
        .sw__err-a:hover, .sw__pending a:hover { text-decoration-color: currentColor; }
        .sw__pending { margin: 7px 2px 0; font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; text-align: center; }
        .sw__foot { margin-top: 6px; font-family: "DM Mono", monospace; font-size: 8px; color: ${C.mute}; text-align: center; opacity: 0.5; }
        @keyframes sw-spin { to { transform: rotate(360deg); } }
        /*  SHORT VIEWPORTS — the reactor is meant to land whole, above the fold.
            This blurb is the only thing in the widget that is pure prose, and the
            crystal rail immediately to its right makes the same promise at full
            volume with the artwork to match. It is the one element here whose
            removal costs nothing, so it is the one that goes when the fold is
            tight, rather than squeezing the price, the floor or the button. */
        @media (max-height: 880px) { .sw__gacha { display: none; } }
        /*  COMPACT TIER — a laptop with a tall browser chrome leaves ~700px of
            page, and this widget is the one column child with no viewport-scaled
            dimension of its own (a number field cannot be clamped the way a chart
            or an illustration can). So below the tier it sheds its footnote and
            tightens its rhythm by a couple of pixels a row, which is invisible
            next to the alternative: the Buy button under the fold. */
        @media (max-height: 780px) {
          .sw { padding: 9px 11px 10px; }
          .sw__foot { display: none; }
          .sw__toggle { margin-bottom: 6px; }
          .sw__toggle button { padding: 4px 0; }
          .sw__field { padding: 6px 11px; }
          .sw__input { font-size: 17px; }
          .sw__chips { margin: 5px 0 4px; }
          .sw__min { margin-bottom: 5px; }
        }
      `}</style>

      {/* buy / sell toggle */}
      <div className="sw__toggle">
        <button className={mode === "buy" ? "on--buy" : ""} onClick={() => { setMode("buy"); setErr(""); }}>Buy</button>
        <button className={mode === "sell" ? "on--sell" : ""} onClick={() => { setMode("sell"); setErr(""); }}>Sell</button>
      </div>

      <div className="sw__head">
        <span className="sw__title">{mode === "buy" ? "Buy" : "Sell"} ${ticker}</span>
        <div className="sw__head-r">
          <span className="sw__spot">{priceUsd > 0 ? `$${priceUsd < 0.01 ? priceUsd.toPrecision(2) : priceUsd.toFixed(4)}` : "—"}</span>
          {/*  THE TOLERANCE, AND THE NUMBER IT PRODUCES — behind the gear. It is
               not hidden: the current setting is printed ON the trigger, so a
               trader can never be unaware of the floor they are about to sign,
               and one click opens the presets + the minimum received. */}
          <div className="sw__gear-wrap" ref={slipRef}>
            <button
              className={`sw__gear ${slipOpen ? "sw__gear--on" : ""}`}
              aria-label={`Max slippage ${slipPct}% — open trade settings`}
              aria-expanded={slipOpen}
              onClick={() => setSlipOpen((o) => !o)}
            >
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="3.2" />
                <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
              </svg>
              <span className="sw__gear-v">{slipPct}%</span>
            </button>

            {slipOpen && (
              <div className="sw__pop" role="dialog" aria-label="Trade settings">
                <div className="sw__pop-l">Max slippage</div>
                <div className="sw__pop-opts">
                  {SLIP_PRESETS.map((sp) => (
                    <button key={sp} className={`sw__slip-chip ${slipPct === sp ? "sw__slip-chip--on" : ""}`}
                      onClick={() => setSlipPct(sp)}>{sp}%</button>
                  ))}
                  <input className="sw__slip-input" inputMode="decimal" value={slipPct}
                    aria-label="Max slippage percent"
                    onChange={(e) => setSlipPct(Math.min(MAX_SLIP_PCT, Number(e.target.value.replace(/[^0-9.]/g, "")) || 0))} />
                  <span className="sw__slip-pct">%</span>
                </div>
                <div className="sw__pop-row">
                  <span>minimum received</span>
                  <b>
                    {!priceable
                      ? "will not sign"
                      : mode === "buy"
                        ? `${compact(Number(formatEther(minOut)))} $${ticker}`
                        : `${Number(formatEther(minOut)).toFixed(6)} Ξ`}
                  </b>
                </div>
                <p className="sw__pop-note">
                  The estimate is already net of the {TRADE_FEE_BPS / 100}% protocol fee.
                  This covers price impact — a thin pool walks several percent on one buy.
                </p>
              </div>
            )}
          </div>
        </div>
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
              <span className="sw__coin"><span className="sw__coin-dot" style={{ background: qNative ? "#627EEA" : "#2775CA", color: "#fff" }}>{qNative ? "Ξ" : qGlyph.slice(0, 1)}</span>{qNative ? "ETH" : quoteSymbol}</span>
            </div>
            {needsFaucet && (
              <button
                className="sw__faucet"
                disabled={faucetBusy}
                onClick={async () => {
                  setFaucetBusy(true);
                  try {
                    await mintTestQuote(quote as Address, quoteDecimals);
                    await refetchQuoteBal();
                  } catch (e) { setErr((e as Error).message.slice(0, 110)); }
                  finally { setFaucetBusy(false); }
                }}
              >
                {faucetBusy ? "Minting…" : `You hold no ${quoteSymbol} — mint 10,000 test ${quoteSymbol}`}
              </button>
            )}
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

      {/*  The floor stays ON SCREEN even with its control tucked behind the gear
           — a widget that shows an estimate while quietly signing a floor the
           trader never saw is the bug this whole control exists to close. */}
      <div className="sw__min">
        {!priceable
          ? <span className="sw__min-warn">
              {!qNative && mode === "buy"
                ? `price is quoted in ETH, pool takes ${quoteSymbol} · will not sign`
                : "unpriceable · will not sign"}
            </span>
          : <>min {mode === "buy"
              ? `${compact(Number(formatEther(minOut)))} $${ticker}`
              : `${Number(formatEther(minOut)).toFixed(6)} Ξ`} · {slipPct}% slip</>}
      </div>

      <button className={`sw__cta ${busy ? "sw__cta--busy" : ""}`} onClick={onAction}
        disabled={busy || (isConnected && (mode === "buy" ? eth <= 0 : tokensIn <= 0 && !needsApproval))}>
        {busy && <span style={{ display: "inline-block", animation: "sw-spin 1s linear infinite", marginRight: 6 }}>⏳</span>}
        {btnLabel}
      </button>

      {err && (
        <div className="sw__err">
          {err}
          {txHash && (
            <> <a className="sw__err-a" href={explorerTxUrl(txHash)} target="_blank" rel="noreferrer">view transaction ↗</a></>
          )}
        </div>
      )}
      {/*  Something to DO while the chain thinks. A spinner with no handle on the
           transaction is the state a stuck confirmation used to trap you in. */}
      {confirming && txHash && !err && (
        <div className="sw__pending">
          <a href={explorerTxUrl(txHash)} target="_blank" rel="noreferrer">track it on the explorer ↗</a>
        </div>
      )}
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
