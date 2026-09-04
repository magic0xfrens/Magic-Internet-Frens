import { useEffect, useMemo, useState } from "react";
import { parseEther, formatEther, type Address } from "viem";
import { useAccount } from "wagmi";
import { waitForTransactionReceipt } from "@wagmi/core";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { usePerpVault } from "@/hooks/usePerpVault";
import { explainPerpError, PERP } from "@/config/perp";
import { wagmiConfig } from "@/config/chains";

interface StakePanelProps {
  ticker: string;
  token?: Address;   // the current iteration token (for the token side)
  spotPrice: number; // ETH per token
  ethUsd: number;
  col: string;       // phase accent
}

const C = { void: "#08060f", lime: "#d5fd51", red: "#ff5470", cream: "#F5F0E8", mute: "#8f83b8" };
function compact(n: number): string {
  if (!Number.isFinite(n) || n === 0) return "0";
  const a = Math.abs(n);
  if (a >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (a >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (a >= 1e3) return `${(n / 1e3).toFixed(2)}K`;
  return n.toFixed(a >= 1 ? 3 : 4);
}

/**
 * StakePanel — the Community PLV (LP-for-perps). Stake ETH or the iteration token
 * into the vault that fronts leverage; earn a share of every perp fee (share price
 * rises as yield accrues). Withdraw any time (instant up to free liquidity, the
 * rest queued until traders close). Reads via Ponder; writes via the wallet.
 */
export default function StakePanel({ ticker, token, spotPrice, ethUsd, col }: StakePanelProps) {
  const { isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const v = usePerpVault(token);
  const [side, setSide] = useState<"eth" | "token">("eth");
  const [mode, setMode] = useState<"deposit" | "withdraw">("deposit");
  const [amt, setAmt] = useState("");
  const [toast, setToast] = useState<{ kind: "err" | "ok"; msg: string } | null>(null);
  // Auto-dismiss the toast (success clears faster than an error you may need to read).
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), toast.kind === "ok" ? 5000 : 8000);
    return () => clearTimeout(t);
  }, [toast]);

  const isEth = side === "eth";
  const pos = isEth ? v.ethPos : v.tokPos;
  const sharePrice = isEth ? v.vault.ethSharePrice : v.vault.tokSharePrice;
  const tvlEth = v.vault.assetsEth + v.vault.assetsTok * spotPrice; // token valued in ETH
  const walletTok = Number(formatEther(v.tokenBalance));

  const amount = parseFloat(amt) || 0;
  const busy = !!v.pendingAction || v.isPending;

  const notify = (e: unknown, verb: string) => setToast({ kind: "err", msg: `${verb} failed — ${explainPerpError(e)}` });

  const onAction = async () => {
    setToast(null);
    if (!isConnected) { openConnectModal?.(); return; }
    try {
      if (mode === "deposit") {
        if (amount <= 0) { setToast({ kind: "err", msg: "Enter an amount" }); return; }
        let hash: `0x${string}`;
        if (isEth) {
          hash = await v.depositEth(amount);
        } else {
          // Clamp to your EXACT on-chain balance — entering the full amount can
          // round a hair OVER the real balance → transferFrom reverts. Never over.
          let raw = parseEther(amount.toFixed(18));
          if (raw > v.tokenBalance) raw = v.tokenBalance;
          if (raw <= 0n) { setToast({ kind: "err", msg: `No $${ticker} to stake` }); return; }
          if (v.needsTokenApproval(raw)) {
            // approve THEN deposit in one flow — wait for the approval to land so
            // the deposit doesn't fail on a not-yet-mined allowance.
            setToast({ kind: "ok", msg: `Approving $${ticker}…` });
            const ah = await v.approveToken();
            await waitForTransactionReceipt(wagmiConfig, { hash: ah as `0x${string}`, chainId: PERP.chainId });
          }
          hash = await v.depositToken(raw);
        }
        // Only claim success once the tx actually CONFIRMS — a submitted tx can
        // still revert (e.g. insufficient balance), which used to show a false ✓.
        setToast({ kind: "ok", msg: "Confirming deposit…" });
        const rcpt = await waitForTransactionReceipt(wagmiConfig, { hash, chainId: PERP.chainId });
        if (rcpt.status === "reverted") { setToast({ kind: "err", msg: "Deposit reverted on-chain — nothing staked. Try a slightly smaller amount." }); return; }
        setToast({ kind: "ok", msg: "Deposited ✓" });
        return;
      } else {
        // withdraw by SHARES (using your exact raw balance) — not amount/price,
        // which mis-scaled and left dust. Full exit → all shares (→ 0 remaining);
        // partial → that fraction of your shares.
        if (pos.redeemable <= 0 || pos.shares <= 0n) { setToast({ kind: "err", msg: "Nothing staked" }); return; }
        const frac = amount > 0 ? Math.min(1, amount / pos.redeemable) : 1;
        const sharesRaw = frac >= 0.999
          ? pos.shares                                                   // withdraw ALL → no dust
          : (pos.shares * BigInt(Math.floor(frac * 1e9))) / 1_000_000_000n;
        if (isEth) await v.withdrawEthShares(sharesRaw);
        else await v.withdrawTokenShares(sharesRaw);
        // free liquidity is paid straight to your wallet; only the part traders
        // have borrowed queues (shown below to claim once they close).
        const want = frac >= 0.999 ? pos.redeemable : amount;
        const queued = Math.max(0, want - pos.instant);
        setToast({ kind: "ok", msg: queued > 0.0001
          ? `Withdrawn — free funds sent to your wallet; ${compact(queued)} ${unit} queued (claim below when traders close).`
          : `Withdrawn ✓ — funds sent straight to your wallet.` });
        return;
      }
      setToast({ kind: "ok", msg: "Deposited ✓" });
    } catch (e) { notify(e, mode === "deposit" ? "Deposit" : "Withdraw"); }
  };

  const unit = isEth ? "Ξ" : `$${ticker}`;
  const posUsd = isEth ? pos.redeemable * ethUsd : pos.redeemable * spotPrice * ethUsd;
  const btnLabel = !isConnected ? "Connect wallet"
    : busy ? "Confirming…"
    : mode === "deposit"
      ? (!isEth && v.needsTokenApproval(parseEther((amount || 0).toFixed(18))) ? `Approve $${ticker}` : `Stake ${isEth ? "ETH" : `$${ticker}`}`)
      : `Withdraw ${isEth ? "ETH" : `$${ticker}`}`;

  const apyHint = useMemo(() => {
    // share price above 1.0 = accrued yield so far (no time-series → show growth).
    const g = (sharePrice - 1) * 100;
    return g > 0.01 ? `+${g.toFixed(2)}% share growth` : "earns 30% of perp fees";
  }, [sharePrice]);

  return (
    <div className="sp">
      <style>{`
        .sp { display: grid; grid-template-columns: 1fr; gap: 14px; }
        @media (min-width: 900px) { .sp { grid-template-columns: 340px 1fr; align-items: start; } }
        .sp-card { border-radius: var(--r-md); padding: 16px; background: rgba(23,18,42,0.34); border: 1px solid rgba(255,255,255,0.06); }
        .sp-eyebrow { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.16em; text-transform: uppercase; color: ${C.mute}; margin-bottom: 12px; display: flex; justify-content: space-between; }
        .sp-eyebrow b { color: ${col}; font-weight: 500; }
        .sp-tabs { display: flex; gap: 4px; padding: 4px; border-radius: var(--r-sm); background: rgba(8,6,15,0.55); margin-bottom: 12px; }
        .sp-tabs button { flex: 1; padding: 8px 0; border-radius: var(--r-sm); border: none; cursor: pointer; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px; background: none; color: ${C.mute}; transition: all .15s; }
        .sp-tabs button.on { background: ${col}1e; color: ${col}; }
        .sp-seg { display: flex; gap: 4px; margin-bottom: 12px; }
        .sp-seg button { flex: 1; padding: 6px 0; border-radius: var(--r-sm); border: 1px solid rgba(255,255,255,0.08); background: rgba(8,6,15,0.4); color: ${C.mute}; font-family: "DM Mono", monospace; font-size: 10px; cursor: pointer; }
        .sp-seg button.on { border-color: ${col}77; color: ${col}; background: ${col}12; }
        .sp-field { background: rgba(8,6,15,0.5); border: 1px solid rgba(255,255,255,0.06); border-radius: var(--r-sm); padding: 11px 13px; }
        .sp-field-top { display: flex; justify-content: space-between; margin-bottom: 4px; }
        .sp-lbl { font-family: "DM Mono", monospace; font-size: 8.5px; letter-spacing: 0.12em; text-transform: uppercase; color: ${C.mute}; cursor: pointer; }
        .sp-row { display: flex; align-items: center; gap: 8px; }
        .sp-input { flex: 1; min-width: 0; background: none; border: none; outline: none; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 22px; color: ${C.cream}; }
        .sp-input::placeholder { color: rgba(143,131,184,0.4); }
        .sp-coin { display: inline-flex; align-items: center; gap: 5px; padding: 4px 9px; border-radius: var(--r-chip); background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.07); font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 11px; color: ${C.cream}; }
        .sp-cta { width: 100%; margin-top: 12px; padding: 12px; border-radius: var(--r-sm); border: 1px solid ${col}66; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 14px; color: ${col}; background: ${col}16; cursor: pointer; transition: all .15s; }
        .sp-cta:hover:not(:disabled) { background: ${col}28; }
        .sp-cta:disabled { opacity: 0.5; cursor: default; }
        .sp-note { margin-top: 10px; font-family: "DM Sans", sans-serif; font-size: 9.5px; line-height: 1.45; color: ${C.mute}; opacity: 0.85; }
        .sp-stats { display: grid; grid-template-columns: repeat(2, 1fr); gap: 9px; }
        .sp-stat { background: rgba(8,6,15,0.4); border: 1px solid rgba(255,255,255,0.05); border-radius: var(--r-sm); padding: 11px 12px; }
        .sp-stat .k { font-family: "DM Mono", monospace; font-size: 8px; letter-spacing: 0.1em; text-transform: uppercase; color: ${C.mute}; }
        .sp-stat .val { font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 17px; color: ${C.cream}; margin-top: 3px; }
        .sp-stat .sub { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; margin-top: 2px; }
        .sp-pos { margin-top: 12px; border-top: 1px solid rgba(255,255,255,0.06); padding-top: 12px; }
        .sp-pos-row { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 6px; }
        .sp-pos-k { font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; }
        .sp-pos-v { font-family: "DM Mono", monospace; font-size: 12px; color: ${C.cream}; }
        .sp-claim { width: 100%; margin-top: 8px; padding: 8px; border-radius: var(--r-sm); border: 1px solid ${C.lime}66; background: ${C.lime}12; color: ${C.lime}; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px; cursor: pointer; }
        .sp-toast { position: fixed; left: 50%; bottom: 26px; transform: translateX(-50%); z-index: 9998; max-width: 420px; width: calc(100vw - 40px); display: flex; gap: 10px; padding: 13px 15px; border-radius: var(--r-sm); font-family: "DM Sans", sans-serif; font-size: 13px; box-shadow: 0 18px 50px -12px rgba(0,0,0,0.6); }
        .sp-toast--err { background: linear-gradient(160deg,#2a1420,#17101f); border: 1px solid ${C.red}66; color: ${C.cream}; }
        .sp-toast--ok { background: linear-gradient(160deg,#16261a,#10171f); border: 1px solid ${C.lime}66; color: ${C.cream}; }
      `}</style>

      {toast && <div className={`sp-toast sp-toast--${toast.kind}`} role="status"><span>{toast.kind === "err" ? "⚠️" : "✅"}</span><span>{toast.msg}</span></div>}

      {/* stake form */}
      <div className="sp-card">
        <div className="sp-eyebrow"><span>Community liquidity · <b>earn perp fees</b></span></div>
        <div className="sp-tabs">
          <button className={mode === "deposit" ? "on" : ""} onClick={() => setMode("deposit")}>Stake</button>
          <button className={mode === "withdraw" ? "on" : ""} onClick={() => setMode("withdraw")}>Withdraw</button>
        </div>
        <div className="sp-seg">
          <button className={isEth ? "on" : ""} onClick={() => setSide("eth")}>ETH side</button>
          <button className={!isEth ? "on" : ""} onClick={() => setSide("token")}>${ticker} side</button>
        </div>

        <div className="sp-field">
          <div className="sp-field-top">
            <span className="sp-lbl">{mode === "deposit" ? "You stake" : "You withdraw"}</span>
            <span className="sp-lbl" onClick={() => setAmt(String(mode === "withdraw" ? pos.redeemable : (isEth ? "" : walletTok)))}>
              {mode === "withdraw" ? `staked ${compact(pos.redeemable)}` : (isEth ? "" : `bal ${compact(walletTok)}`)}
            </span>
          </div>
          <div className="sp-row">
            <input className="sp-input" inputMode="decimal" placeholder="0.0" value={amt} onChange={(e) => setAmt(e.target.value.replace(/[^0-9.]/g, ""))} />
            <span className="sp-coin">{isEth ? "Ξ ETH" : `◆ ${ticker}`}</span>
          </div>
        </div>

        <button className="sp-cta" onClick={onAction} disabled={busy}>{btnLabel}</button>
        <p className="sp-note">
          {isEth
            ? <>Staking ETH backs <b>longs</b>. You earn the <b>long-side</b> fees (open fee + funding + liquidations) — your share price rises as they accrue. Withdraw anytime: instant up to free liquidity, the rest queued until positions close.</>
            : <>Staking ${ticker} backs <b>shorts</b> — your token principal is <b>100% protected</b> (buy-backs always return it in full). On top, you earn <b>ETH from short-side</b> fees, claimable separately below.</>}
        </p>
      </div>

      {/* vault stats + your position */}
      <div className="sp-card">
        <div className="sp-eyebrow"><span>The vault</span><span>{apyHint}</span></div>
        <div className="sp-stats">
          <div className="sp-stat"><div className="k">Total value locked</div><div className="val">{compact(tvlEth)} Ξ</div><div className="sub">{ethUsd > 0 ? `$${compact(tvlEth * ethUsd)}` : ""}</div></div>
          <div className="sp-stat"><div className="k">Share price</div><div className="val">{sharePrice.toFixed(4)}</div><div className="sub">{isEth ? "ETH" : ticker} / share</div></div>
          <div className="sp-stat"><div className="k">Vault ETH</div><div className="val">{compact(v.vault.assetsEth)} Ξ</div></div>
          <div className="sp-stat"><div className="k">Vault ${ticker}</div><div className="val">{compact(v.vault.assetsTok)}</div></div>
        </div>

        <div className="sp-pos">
          <div className="sp-pos-row"><span className="sp-pos-k">Your stake ({isEth ? "ETH" : ticker})</span><span className="sp-pos-v">{compact(pos.redeemable)} {unit} {posUsd > 0 ? `· $${posUsd.toFixed(2)}` : ""}</span></div>
          <div className="sp-pos-row"><span className="sp-pos-k">Withdrawable now</span><span className="sp-pos-v">{compact(pos.instant)} {unit}</span></div>
          {pos.pending > 0 && (
            <>
              <div className="sp-pos-row"><span className="sp-pos-k">Queued (awaiting liquidity)</span><span className="sp-pos-v" style={{ color: C.mute }}>{compact(pos.pending)} {unit}</span></div>
              <button className="sp-claim" disabled={busy} onClick={async () => { try { isEth ? await v.claimEth() : await v.claimToken(); setToast({ kind: "ok", msg: "Claimed ✓" }); } catch (e) { notify(e, "Claim"); } }}>Claim queued {isEth ? "ETH" : `$${ticker}`}</button>
            </>
          )}
          {/* token stakers additionally earn ETH from short-side fees */}
          {!isEth && (
            <>
              <div className="sp-pos-row"><span className="sp-pos-k">ETH earned (short fees)</span><span className="sp-pos-v" style={{ color: C.lime }}>{compact(v.tokPos.ethReward)} Ξ {v.tokPos.ethReward * ethUsd > 0 ? `· $${(v.tokPos.ethReward * ethUsd).toFixed(2)}` : ""}</span></div>
              {v.tokPos.ethReward > 0 && (
                <button className="sp-claim" disabled={busy} onClick={async () => { try { await v.claimTokYield(); setToast({ kind: "ok", msg: "ETH reward claimed ✓" }); } catch (e) { notify(e, "Claim"); } }}>Claim {compact(v.tokPos.ethReward)} Ξ reward</button>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
