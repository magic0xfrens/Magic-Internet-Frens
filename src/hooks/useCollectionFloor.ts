import { useCallback, useEffect, useState } from "react";
import { formatEther, parseEther } from "viem";
import { useAccount, usePublicClient, useSwitchChain, useWriteContract } from "wagmi";
import { CAULDRON, CAULDRON_INDEXER, REGISTRY_ABI } from "@/config/cauldron";

/** endpoint float (token/ETH) → wei bigint, matching the existing bigint state
 *  shape (so consumers + fmt() are untouched). toFixed(18) dodges sci-notation. */
const toWei = (n: number): bigint => {
  if (!Number.isFinite(n) || n <= 0) return 0n;
  try { return parseEther(n.toFixed(18)); } catch { return 0n; }
};

/** A past (dead) collection's legacy floor — redeemable in the LIVE token. */
export interface PastCollectionFloor {
  gen: number;
  crystallized: boolean;
  floorPerNFT: bigint;   // live tokens redeemable per NFT (ratchets up)
  outstanding: number;   // NFTs still entitled
}

export interface CollectionFloorState {
  loading: boolean;
  ticker: string;                 // the live token
  currentGen: number;
  // LIVE collection — floor is BUILDING from the buyback AND now redeemable live.
  livePending: bigint;            // total tokens banked for the live collection
  liveFloorPerNFT: bigint;        // tokens redeemable per LIVE creature NFT right now
  liveOutstanding: number;        // entitled (redeemable) live NFTs
  buffer: bigint;                 // ETH accumulating toward the next buyback
  threshold: bigint;              // buffer size that triggers a buyback
  bufferPct: number;              // 0..100 progress to the next buyback
  legacyBps: number;              // % of the post-guild fee funding buybacks
  past: PastCollectionFloor[];    // dead collections with a redeemable floor
  error?: string;
}

const EMPTY: CollectionFloorState = {
  loading: false, ticker: "", currentGen: 0, livePending: 0n, liveFloorPerNFT: 0n,
  liveOutstanding: 0, buffer: 0n, threshold: 0n, bufferPct: 0, legacyBps: 0, past: [],
};

/**
 * useCollectionFloor — the COLLECTION LEGACY FLOOR (r28). Every volume collection
 * preserves the value its own volume + royalties accrued, forever, as a token
 * entitlement that moons with the machine. While a collection is LIVE its floor is
 * built by the in-hook buyback (fee ETH → market-buys the token → credited here);
 * at death it crystallizes into a per-NFT floor redeemable in whatever token is
 * live now. Holders recycle an NFT for its floor (NFT → treasury) or buy a
 * treasury-held one for 2× floor (which ratchets the floor up for everyone).
 */
export function useCollectionFloor() {
  const { address, chainId } = useAccount();
  const publicClient = usePublicClient({ chainId: CAULDRON.chainId });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();

  const [s, setS] = useState<CollectionFloorState>(EMPTY);
  const [busy, setBusy] = useState(false);

  // Read the floor state SERVER-SIDE via the indexer (rotated keys), like the rest
  // of the app — the browser makes NO RPC reads. The panel's old direct reads of
  // legacyBuffer/legacyThreshold silently failed on flaky public RPC → the bar
  // showed 0% while it was really building. /collection-floors computes it reliably.
  const load = useCallback(async () => {
    if (!CAULDRON_INDEXER) { setS(EMPTY); return; }
    setS((p) => ({ ...p, loading: true, error: undefined }));
    try {
      const res = await fetch(`${CAULDRON_INDEXER}/collection-floors`, { signal: AbortSignal.timeout(8000) });
      if (!res.ok) throw new Error(`floors ${res.status}`);
      const d = await res.json() as {
        currentGen?: number; ticker?: string; livePending?: number;
        liveFloorPerNFT?: number; liveOutstanding?: number; bufferEth?: number;
        thresholdEth?: number; bufferPct?: number; legacyBps?: number;
        past?: Array<{ gen: number; floorPerNFT: number; outstanding: number }>;
      };
      setS({
        loading: false,
        ticker: d.ticker ?? "",
        currentGen: d.currentGen ?? 0,
        livePending: toWei(d.livePending ?? 0),
        liveFloorPerNFT: toWei(d.liveFloorPerNFT ?? 0),
        liveOutstanding: d.liveOutstanding ?? 0,
        buffer: toWei(d.bufferEth ?? 0),
        threshold: toWei(d.thresholdEth ?? 0),
        bufferPct: d.bufferPct ?? 0,
        legacyBps: d.legacyBps ?? 0,
        // the endpoint only returns CRYSTALLIZED past collections.
        past: (d.past ?? []).map((p) => ({
          gen: p.gen, crystallized: true,
          floorPerNFT: toWei(p.floorPerNFT), outstanding: p.outstanding,
        })),
      });
    } catch (e: unknown) {
      // keep the last-good numbers; just clear the spinner.
      setS((p) => ({ ...p, loading: false, error: (e as Error)?.message ?? "load failed" }));
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const ensureChain = useCallback(async () => {
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
  }, [chainId, switchChainAsync]);

  /** Recycle a dead-collection NFT for its live-token floor (NFT → treasury). */
  const recycle = useCallback(async (gen: number, tokenId: bigint) => {
    if (!address) throw new Error("Connect a wallet first");
    if (!publicClient) throw new Error("No RPC client");
    await ensureChain();
    setBusy(true);
    try {
      const hash = await writeContractAsync({
        address: CAULDRON.registry, abi: REGISTRY_ABI,
        functionName: "recycleCollectionNFT", args: [BigInt(gen), tokenId],
      });
      await publicClient.waitForTransactionReceipt({ hash, timeout: 120_000 });
      await load();
    } finally { setBusy(false); }
  }, [address, publicClient, ensureChain, writeContractAsync, load]);

  /** Buy a treasury-held (recycled) NFT for 2× its floor → ratchets the floor up. */
  const buyTreasury = useCallback(async (gen: number, tokenId: bigint) => {
    if (!address) throw new Error("Connect a wallet first");
    if (!publicClient) throw new Error("No RPC client");
    await ensureChain();
    setBusy(true);
    try {
      const hash = await writeContractAsync({
        address: CAULDRON.registry, abi: REGISTRY_ABI,
        functionName: "buyCollectionNFT", args: [BigInt(gen), tokenId],
      });
      await publicClient.waitForTransactionReceipt({ hash, timeout: 120_000 });
      await load();
    } finally { setBusy(false); }
  }, [address, publicClient, ensureChain, writeContractAsync, load]);

  const fmt = (b: bigint) => Number(formatEther(b)).toLocaleString(undefined, { maximumFractionDigits: 0 });

  return { ...s, busy, recycle, buyTreasury, refresh: load, fmt };
}
