import { useCallback, useEffect, useState } from "react";
import type { Address } from "viem";
import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from "wagmi";
import { useWallet } from "@/hooks/useWallet";
import { fetchNftsFromIndexer } from "@/lib/cauldronOnchain";
import { liquidatoorBadgeSVG, type LiquidatoorStats } from "@/lib/liquidatoorBadgeArt";
import { PERP, PERP_ABI } from "@/config/perp";
import { CAULDRON_INDEXER } from "@/config/cauldron";

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * LiquidatoorBadges — the connected wallet's LIQUIDATOOR trophies: NFTs struck
 * the moment a fren was responsible for a perp liquidation on the hook. They
 * live in the iteration collections (incl. the genesis MiFrens set) in a
 * dedicated high id range.
 *
 * The ownership LIST comes 100% from the Ponder indexer (which flags each row
 * with `isLiquidatoor`) — NO on-chain scan. Only the badge ART is read on-chain
 * from each token's tokenURI.
 */

interface Badge { collection: Address; tokenId: number; gen: number; image?: string; name?: string }

// Render the badge ART LOCALLY from the exact Lab generator (liquidatoorBadgeSVG)
// + the /public scope images — NOT from the on-chain tokenURI (which points at a
// metadata endpoint). Stats are DETERMINISTIC per tokenId (a stable, seeded roll)
// so a badge always looks the same; the liquidator is the connected wallet.
// TODO: swap the seeded stats for the REAL liquidation record from the indexer
// (LiquidatoorAwarded links positionId → badgeId; perpPosition has side/entry/liq).
function seeded(tokenId: number) {
  let s = (tokenId * 2654435761) >>> 0;
  return () => { s = (s * 1103515245 + 12345) >>> 0; return s / 0xffffffff; };
}
const short = (a?: string) => (a && a.length > 10 ? `${a.slice(0, 6)}…${a.slice(-4)}` : (a ?? "0x0000…0000"));

/** Real liquidation record for a badge (from /perp-kills), matched by badgeId. */
interface Kill { badgeId: string | null; isLong: boolean; leverage: number; entryPrice: number; liqPrice: number; notionalEth: number; victim: string; block: number; }

const fmtPx = (ethPerToken: number) => {
  // show ETH-per-token as gwei-ish so the readout isn't 1.8e-8
  const g = ethPerToken * 1e9;
  return g.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
};

function badgeStats(tokenId: number, liquidator?: string, real?: Kill): LiquidatoorStats {
  // REAL record (side/entry/liq/size are the truth) — falls back to a stable
  // seeded roll only for badges with no matched kill (e.g. pre-indexer history).
  if (real) {
    return {
      side: real.isLong ? "long" : "short", tokenId,
      victim: short(real.victim), liquidator: short(liquidator),
      sizeEth: real.notionalEth.toFixed(3),
      leverage: real.leverage || 2,
      entry: fmtPx(real.entryPrice),
      liqPrice: fmtPx(real.liqPrice),
      pnlPct: "-100.0",
      bountyEth: (real.notionalEth * 0.001).toFixed(4), // ~0.1% keeper cut
      block: (real.block || 0).toLocaleString("en-US"),
      imageHref: `/images/liq-${real.isLong ? "long" : "short"}.png`,
    };
  }
  const r = seeded(tokenId);
  const side: "short" | "long" = r() > 0.5 ? "short" : "long";
  const hex = () => Math.floor(r() * 16).toString(16);
  const entryN = 1800 + r() * 1400;
  const drop = side === "short" ? 1.05 + r() * 0.25 : 0.7 + r() * 0.25;
  const fmt = (n: number) => n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return {
    side, tokenId,
    victim: `0x${hex()}${hex()}${hex()}${hex()}…${hex()}${hex()}${hex()}${hex()}`,
    liquidator: short(liquidator),
    sizeEth: (0.4 + r() * 8).toFixed(2),
    leverage: 2 + Math.floor(r() * 2),
    entry: fmt(entryN),
    liqPrice: fmt(entryN * drop),
    pnlPct: "-100.0",
    bountyEth: (0.001 + r() * 0.05).toFixed(3),
    block: Math.floor(11_600_000 + r() * 50_000).toLocaleString("en-US"),
    imageHref: `/images/liq-${side}.png`,
  };
}

/** The badge artwork as a RAW SVG string, rendered INLINE (dangerouslySetInnerHTML)
 *  — NOT via <img src="data:...">, because an SVG loaded through <img> runs in the
 *  browser's secure-static mode which strips the nested <image> (the pepe-sniper
 *  scope art). Inline in the DOM, that same-origin /images/liq-*.png loads fine. */
function badgeArt(tokenId: number, liquidator?: string, real?: Kill): string {
  return liquidatoorBadgeSVG(badgeStats(tokenId, liquidator, real));
}

export default function LiquidatoorBadges() {
  const { isConnected, walletAddress } = useWallet();
  const [badges, setBadges] = useState<Badge[]>([]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState("");
  const [big, setBig] = useState<Badge | null>(null); // click-to-enlarge lightbox

  // PENDING badge credits — a liquidation whose swap was too gas-tight to auto-mint
  // the trophy in-swap parks it here (engine.badgesOwed); claim mints them. The
  // claim UI only appears when there's actually something to claim.
  const { data: owed, refetch: refetchOwed } = useReadContract({
    address: PERP.engine, abi: PERP_ABI, functionName: "badgesOwed",
    args: walletAddress ? [walletAddress as `0x${string}`] : undefined,
    chainId: PERP.chainId,
    query: { enabled: !!walletAddress, refetchInterval: 12_000 },
  });
  const owedN = owed ? Number(owed as bigint) : 0;
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, data: claimHash, isPending: claimPending } = useWriteContract();
  const { isLoading: claimMining, isSuccess: claimed } = useWaitForTransactionReceipt({ hash: claimHash, chainId: PERP.chainId });

  const claim = useCallback(async () => {
    if (!owedN) return;
    try {
      await switchChainAsync({ chainId: PERP.chainId }).catch(() => {});
      await writeContractAsync({
        address: PERP.engine, abi: PERP_ABI, functionName: "claimLiquidatorBadges",
        args: [BigInt(owedN)], chainId: PERP.chainId,
      });
    } catch { /* user rejected / revert — surfaced by wallet */ }
  }, [owedN, switchChainAsync, writeContractAsync]);

  const load = useCallback(async () => {
    if (!isConnected || !walletAddress) { setBadges([]); return; }
    setLoading(true); setErr("");
    const timeout = new Promise<never>((_, rej) => setTimeout(() => rej(new Error("timeout")), 25_000));
    try {
      // includeGenesis:true — iteration #2 mints badges into the genesis MiFrens
      // collection, so we include it. Ownership from the Ponder indexer only.
      const owned = await Promise.race([
        fetchNftsFromIndexer(walletAddress as `0x${string}`, { includeGenesis: true }),
        timeout,
      ]);
      const only = owned.filter((n) => n.isLiquidatoor).slice(0, 60);
      // Pull the REAL kill records so each badge tells its TRUE story (a buy that
      // rekt a short → SHORT art). The engine's event badgeId is a mint marker, not
      // the real tokenId, so we can't key by it — instead ZIP by order: each
      // liquidation mints exactly one badge in sequence, so the i-th oldest badge
      // maps to the i-th oldest kill. Falls back to a stable seeded roll if unmatched.
      const killByBadge = new Map<number, Kill>();
      if (INDEXER) {
        try {
          const r = await fetch(`${INDEXER}/perp-kills/${walletAddress}`, { signal: AbortSignal.timeout(8000) });
          const d = await r.json() as { kills?: Kill[] };
          const killsAsc = (d.kills ?? []).slice().sort((a, b) => (a.block || 0) - (b.block || 0));
          const badgesAsc = only.slice().sort((a, b) => a.tokenId - b.tokenId);
          badgesAsc.forEach((n, i) => { if (killsAsc[i]) killByBadge.set(n.tokenId, killsAsc[i]); });
        } catch { /* fall back to seeded */ }
      }
      // Render the badge ART LOCALLY (the Lab generator + /public scope images) —
      // no tokenURI fetch, so it works instantly on localhost + prod. Real side when
      // matched; liquidator = the connected wallet.
      const withArt: Badge[] = only.map((n) => ({
        collection: n.collection, tokenId: n.tokenId, gen: n.gen,
        image: badgeArt(n.tokenId, walletAddress, killByBadge.get(n.tokenId)), name: `Liquidatoor #${n.tokenId}`,
      }));
      setBadges(withArt);
    } catch (e) {
      const m = (e as Error)?.message;
      setErr(
        m === "no-indexer" ? "Indexer isn't configured — set VITE_CAULDRON_INDEXER."
        : m === "timeout" ? "Indexer was slow — tap retry."
        : "Couldn't reach the indexer — tap retry.",
      );
      setBadges([]);
    } finally {
      setLoading(false);
    }
  }, [isConnected, walletAddress]);

  useEffect(() => { load(); }, [load]);
  // after a claim confirms, the credit is 0 and a fresh badge is owned → refresh both
  useEffect(() => { if (claimed) { refetchOwed(); load(); } }, [claimed, refetchOwed, load]);

  if (!isConnected) return null;

  return (
    <div className="lqb">
      <style>{`
        .lqb { margin-top: 22px; }
        .lqb__head { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 14px; flex-wrap: wrap; gap: 8px; }
        .lqb__title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 17px; color: #f5f0e8; margin: 0; display: flex; align-items: center; gap: 10px; }
        .lqb__title span { font-family: "DM Mono", monospace; font-size: 11px; font-weight: 700; color: #17112f; background: #ff4d6d; border-radius: var(--r-chip); padding: 3px 10px; }
        .lqb__sub { font-family: "DM Sans", sans-serif; font-size: 13px; color: #8f83b8; margin: 4px 0 0; max-width: 560px; line-height: 1.5; }
        .lqb__grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 14px; }
        .lqb__card { display: block; width: 100%; border-radius: var(--r-sm); overflow: hidden; background: rgba(28,20,54,0.6);
          border: 1px solid rgba(255,77,109,0.25); transition: transform 0.2s cubic-bezier(.2,.9,.3,1), border-color 0.2s, box-shadow 0.2s; }
        .lqb__card:hover { transform: translateY(-4px); border-color: rgba(255,77,109,0.6); box-shadow: 0 12px 34px rgba(0,0,0,0.45), 0 0 0 1px rgba(255,77,109,0.2); }
        .lqb__art { position: relative; aspect-ratio: 1; width: 100%; background: radial-gradient(120% 120% at 50% 0%, rgba(255,77,109,0.12), transparent 60%), rgba(20,14,40,0.5); display: grid; place-items: center; overflow: hidden; border: none; padding: 0; cursor: zoom-in; }
        .lqb__lightbox { position: fixed; inset: 0; z-index: 9999; display: grid; place-items: center; padding: 4vh 4vw; background: rgba(8,6,15,0.86); backdrop-filter: blur(10px); animation: lqb-fade .2s ease; cursor: zoom-out; }
        @keyframes lqb-fade { from { opacity: 0; } to { opacity: 1; } }
        .lqb__lb-art { width: min(88vh, 92vw); aspect-ratio: 1; border-radius: var(--r-md); overflow: hidden; box-shadow: 0 30px 90px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,77,109,0.3); cursor: default; }
        .lqb__lb-art svg { width: 100%; height: 100%; display: block; }
        .lqb__lb-close { position: absolute; top: 3vh; right: 3vw; width: 44px; height: 44px; border-radius: 50%; border: none; background: rgba(255,255,255,0.08); color: #f5f0e8; font-size: 26px; line-height: 1; cursor: pointer; }
        .lqb__lb-close:hover { background: rgba(255,77,109,0.3); }
        .lqb__lb-cap { position: absolute; bottom: 3vh; font-family: "DM Mono", monospace; font-size: 13px; letter-spacing: 0.08em; color: #8f83b8; }
        .lqb__art img { width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; }
        .lqb__svg, .lqb__svg svg { width: 100%; height: 100%; display: block; }
        .lqb__ph { font-size: 30px; color: rgba(255,77,109,0.45); }
        .lqb__flag { position: absolute; top: 8px; left: 8px; font-family: "DM Mono", monospace; font-size: 8px; letter-spacing: 0.12em; color: #17112f; background: #ff4d6d; border-radius: var(--r-chip); padding: 2px 8px; font-weight: 700; }
        .lqb__meta { padding: 9px 11px 11px; }
        .lqb__id { font-family: "DM Sans", sans-serif; font-size: 12.5px; font-weight: 800; color: #f5f0e8; }
        .lqb__gen { font-family: "DM Mono", monospace; font-size: 10px; color: #8f83b8; margin-top: 3px; }
        .lqb__empty { padding: 22px; border-radius: var(--r-sm); background: radial-gradient(120% 120% at 50% 0%, rgba(255,77,109,0.07), transparent 60%), rgba(28,20,54,0.4); border: 1px dashed rgba(255,77,109,0.25); font-family: "DM Sans", sans-serif; font-size: 13px; color: #b8adcc; text-align: center; line-height: 1.6; }
        .lqb__empty b { color: #ff4d6d; }
        .lqb__retry { margin-top: 12px; padding: 7px 16px; border-radius: var(--r-sm); background: rgba(255,77,109,0.12); border: 1px solid #ff4d6d; color: #ff4d6d; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px; cursor: pointer; }
        .lqb__retry:hover { background: rgba(255,77,109,0.24); }
        .lqb__claim { align-self: center; padding: 9px 18px; border-radius: var(--r-sm); background: linear-gradient(90deg, #ff4d6d, #f5c542); border: none; color: #17112f; font-family: "Fredoka", sans-serif; font-weight: 700; font-size: 13px; cursor: pointer; box-shadow: 0 4px 18px rgba(255,77,109,0.4); transition: transform .15s, box-shadow .15s; }
        .lqb__claim:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 8px 26px rgba(255,77,109,0.55); }
        .lqb__claim:disabled { opacity: 0.6; cursor: default; }
      `}</style>

      <div className="lqb__head">
        <div>
          <h4 className="lqb__title">
            Liquidatoor Badges
            {badges.length > 0 && <span>{badges.length}</span>}
          </h4>
          <p className="lqb__sub">
            Trophies struck when <b style={{ color: "#ff4d6d" }}>your trade liquidated a leveraged position</b> on
            the perp engine — proof-of-kill, minted on-chain to the fren responsible.
          </p>
        </div>
        {owedN > 0 && (
          <button className="lqb__claim" onClick={claim} disabled={claimPending || claimMining}>
            {claimPending || claimMining
              ? "Claiming…"
              : `⚔ Claim ${owedN} badge${owedN > 1 ? "s" : ""}`}
          </button>
        )}
      </div>

      {loading ? (
        <div className="lqb__empty">Reading your kills from the chain…</div>
      ) : err ? (
        <div className="lqb__empty">{err}<br /><button className="lqb__retry" onClick={() => load()}>↻ Retry</button></div>
      ) : badges.length === 0 ? (
        <div className="lqb__empty">
          No badges yet. When a buy or sell tips a leveraged position past its mark, the swap that did it
          earns a <b>Liquidatoor</b> badge — trade the live token to hunt one.
        </div>
      ) : (
        <div className="lqb__grid">
          {badges.map((b) => (
            <div key={`${b.collection}-${b.tokenId}`} className="lqb__card">
              <button className="lqb__art" onClick={() => b.image && setBig(b)} title="View full size" aria-label={`Enlarge ${b.name}`}>
                {b.image
                  ? <div className="lqb__svg" dangerouslySetInnerHTML={{ __html: b.image }} />
                  : <span className="lqb__ph">☠</span>}
                <span className="lqb__flag">LIQUIDATOOR</span>
              </button>
              <div className="lqb__meta">
                <div className="lqb__id">{b.name ?? `Badge #${b.tokenId}`}</div>
                <div className="lqb__gen">Iteration {b.gen === 0 ? "MiFrens" : `#${b.gen}`}</div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* click-to-enlarge lightbox */}
      {big && (
        <div className="lqb__lightbox" onClick={() => setBig(null)} role="dialog" aria-modal="true">
          <button className="lqb__lb-close" onClick={() => setBig(null)} aria-label="Close">×</button>
          <div className="lqb__lb-art" onClick={(e) => e.stopPropagation()} dangerouslySetInnerHTML={{ __html: big.image ?? "" }} />
          <div className="lqb__lb-cap">{big.name} · Iteration {big.gen === 0 ? "MiFrens" : `#${big.gen}`}</div>
        </div>
      )}
    </div>
  );
}
