import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePoll } from "@/hooks/usePoll";
import { formatEther, parseEther, keccak256, encodeAbiParameters, type Address } from "viem";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import {
  CAULDRON, CAULDRON_INDEXER, REGISTRY_ABI, HOOK_ABI, GOVERNOR_ABI, COLLECTION_ABI, TOKEN_ABI,
  POOLMANAGER_ABI, POSITION_MANAGER, POSITION_MANAGER_ABI, MIFRENS_ERC721_ABI,
} from "@/config/cauldron";
import { useEthUsd } from "./useEthUsd";


export type Phase = "presale" | "live" | "dying" | "dead";

export interface Proposal {
  id: number;
  name: string;
  ticker: string;
  theme: string;
  website?: string;
  socials?: string;
  proposer: Address;
  votes: number;
  consumed: boolean;
  metaMode: "renderer" | "uri";
  metaValue: string;
  nftSupply: number;      // collection size (volume-forged NFTs)
  mintOutEth: number;     // ≈ ETH volume to mint out the whole collection
}

export interface MachineState {
  loading: boolean;
  summoned: boolean;
  phase: Phase;
  gen: number;
  token?: Address;
  collection?: Address;
  vault?: Address;
  poolId?: `0x${string}`;
  name: string;
  ticker: string;
  vol24hEth: number;
  vitality: number;
  deathThresholdEth: number;
  isDead: boolean;
  nftMinted: number;
  nftMax: number;
  presaleMinted: number;
  presaleGoal: number;
  priceSeries: number[];
  spotPrice: number;
  reserveTokens: number; // out-of-range reserve (backs the floor) — excluded from circulating MC
  relaunchEth: number;
  vaultEth: number;
  availableEth: number; // LP ETH + hook reserve + floor vault = seeds the next launch
  relaunchAt: number;   // unix seconds when relaunch becomes allowed (grace period)
  proposals: Proposal[];
  migratable: MigratableBalance[]; // dead-gen token balances the wallet can claim 1:1
}

/** A previous-generation token the connected wallet still holds — claimable 1:1
 *  into the current brew via registry.claimByBurn(gen, amount). */
export interface MigratableBalance {
  gen: number;
  token: Address;
  symbol: string;
  balance: bigint;   // raw (18 decimals)
}

const EMPTY: MachineState = {
  loading: true, summoned: false, phase: "presale", gen: 0,
  name: "", ticker: "", vol24hEth: 0, vitality: 0,
  deathThresholdEth: CAULDRON.deathThresholdEth, isDead: false,
  nftMinted: 0, nftMax: 0, presaleMinted: 0, presaleGoal: CAULDRON.genesisSupply,
  priceSeries: [], spotPrice: 0, reserveTokens: 0, relaunchEth: 0, vaultEth: 0, availableEth: 0, relaunchAt: 0, proposals: [],
  migratable: [],
};

const PRESALE_MINI_ABI = [
  { type: "function", name: "minted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

type PC = NonNullable<ReturnType<typeof usePublicClient>>;

/** Indexer base (Ponder). The browser reads the whole cauldron from here. */
const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/** Shape of the /cauldron endpoint — the full brew state in one fetch. */
interface CauldronDto {
  summoned: boolean;
  gen: number;
  token?: string;
  collection?: string | null;
  poolId?: string;
  name?: string;
  ticker?: string;
  dead?: boolean;
  phase?: string;
  spotPrice?: number;
  volumeEth?: number;
  vol24hEth?: number;
  nftMinted?: number;
  nftMax?: number;
  deathThresholdEth?: number;
  vaultEth?: number;
  relaunchEth?: number;
  relaunchAt?: number;
  presaleMinted?: number;
}

/** One-shot brew state from the indexer's /cauldron endpoint. Returns null if
 *  the endpoint isn't available (older indexer / mid-deploy) so the caller can
 *  fall back. After a 404 we back off for 2 min (so the 15s poll doesn't log a
 *  404 every cycle) but then RETRY — so when the endpoint finishes deploying we
 *  pick up the richer values (floor/vault/24h-vol) without a manual refresh. */
let cauldron404Until = 0;
async function fetchCauldron(): Promise<CauldronDto | null> {
  if (!INDEXER || Date.now() < cauldron404Until) return null;
  try {
    const res = await fetch(`${INDEXER}/cauldron`, { signal: AbortSignal.timeout(10000) });
    if (res.status === 404) { cauldron404Until = Date.now() + 120_000; return null; }
    if (!res.ok) return null;
    return await res.json() as CauldronDto;
  } catch { return null; }
}

/** Fallback: reconstruct the brew from the ALWAYS-LIVE /collections + /candles
 *  endpoints when /cauldron isn't deployed. Zero browser RPC. Chain-only values
 *  (death floor, art cap, vault/reserve ETH) default to 0 until /cauldron ships. */
async function fetchCauldronFallback(): Promise<CauldronDto | null> {
  if (!INDEXER) return null;
  try {
    const colRes = await fetch(`${INDEXER}/collections`, { signal: AbortSignal.timeout(8000) });
    if (!colRes.ok) return null;
    const cj = await colRes.json() as { collections?: Array<{ address: string; generation: number | null; totalMinted: number; isPresale: boolean }> };
    const brews = (cj.collections ?? []).filter((c) => c.generation != null && !c.isPresale);
    if (brews.length === 0) return { summoned: false, gen: 0 };
    const top = brews.reduce((a, b) => ((b.generation ?? 0) > (a.generation ?? 0) ? b : a));
    const gen = top.generation ?? 1;

    const candRes = await fetch(`${INDEXER}/candles/${gen}?limit=1`, { signal: AbortSignal.timeout(8000) });
    const candJson = candRes.ok ? await candRes.json() as { pool?: { id: string; token: string; name: string; symbol: string; dead: boolean }; last?: number; volumeEth?: number } : {};
    const pool = candJson.pool;
    if (!pool) return { summoned: false, gen: 0 };

    return {
      summoned: true, gen,
      token: pool.token, collection: top.address, poolId: pool.id,
      name: pool.name, ticker: pool.symbol, dead: pool.dead,
      phase: pool.dead ? "dead" : "live",
      spotPrice: candJson.last ?? 0, volumeEth: candJson.volumeEth ?? 0, vol24hEth: 0,
      nftMinted: top.totalMinted, nftMax: 0,
      deathThresholdEth: 0, vaultEth: 0, relaunchEth: 0, relaunchAt: 0,
    };
  } catch { return null; }
}

/** Governance proposals from the indexer (Ponder) — no browser RPC. Fills the
 *  fields the /proposals endpoint serves; richer metadata defaults gracefully. */
async function loadProposalsIndexed(): Promise<Proposal[]> {
  if (!INDEXER) return [];
  try {
    const res = await fetch(`${INDEXER}/proposals`, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) return [];
    const d = await res.json() as { proposals?: Array<{ id: number; name: string; symbol: string; proposer: string; votes: string; consumed: boolean; website?: string | null; socials?: string | null; metaMode?: "renderer" | "uri"; metaValue?: string; nftSupply?: number; mintOutEth?: number }> };
    return (d.proposals ?? []).filter((p) => !p.consumed).map((p) => ({
      id: p.id, name: p.name, ticker: p.symbol, theme: p.name,
      proposer: p.proposer as Address, votes: Number(p.votes), consumed: p.consumed,
      website: p.website ?? undefined, socials: p.socials ?? undefined,
      metaMode: (p.metaMode ?? "uri"), metaValue: p.metaValue ?? "",
      nftSupply: p.nftSupply ?? 0, mintOutEth: p.mintOutEth ?? 0,
    }));
  } catch { return []; }
}

/**
 * useCauldronMachine — the live on-chain state of the eternal Cauldron. Reads the
 * registry / hook / governor / collection, and reconstructs a real price+volume
 * series from the current pool's V4 Swap events. Polls every 15s.
 */
export function useCauldronMachine() {
  const { address, chainId } = useAccount();
  const publicClient = usePublicClient({ chainId: CAULDRON.chainId });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: confirming, isSuccess: confirmed } = useWaitForTransactionReceipt({ hash: txHash, chainId: CAULDRON.chainId });

  // Keep publicClient in a ref so `load` can have a STABLE identity (empty deps).
  // Otherwise, if usePublicClient returns a fresh object per render, `load` churns
  // → useEffect([load]) re-fires → setS re-renders → tight fetch loop that floods
  // the browser (net::ERR_INSUFFICIENT_RESOURCES).
  const pcRef = useRef(publicClient);
  pcRef.current = publicClient;

  const [s, setS] = useState<MachineState>(EMPTY);
  // Live ETH/USD for price + market-cap display. Shared hook so the floor panel
  // and this both ride one Coinbase poll instead of two.
  const ethUsd = useEthUsd();

  const loadingRef = useRef(false);
  const load = useCallback(async () => {
    // ── PONDER-ONLY brew state ──
    // The whole cauldron comes from the indexer's /cauldron endpoint in ONE
    // fetch (indexed identity/price + a cached server-side snapshot of the few
    // chain-only values). The browser makes ZERO read RPC calls, so the page
    // paints in ~one round-trip instead of a ~25-call on-chain waterfall.
    // In-flight guard: never allow overlapping loads — a hard cap against any
    // accidental render-loop flooding the indexer (net::ERR_INSUFFICIENT_RESOURCES).
    if (loadingRef.current) return;
    loadingRef.current = true;
    try {
    if (!INDEXER) { setS((prev) => ({ ...prev, loading: false })); return; }
    try {
      // Prefer the one-shot /cauldron endpoint; if it isn't available (older
      // indexer), reconstruct the same shape from /collections + /candles, which
      // are always live. Either way the browser makes ZERO read RPC calls.
      let d = await fetchCauldron();
      if (!d) d = await fetchCauldronFallback();
      if (!d) { setS((prev) => ({ ...prev, loading: false })); return; }

      if (!d.summoned) {
        setS((prev) => ({ ...EMPTY, loading: false, summoned: false, phase: "presale",
          presaleMinted: d.presaleMinted ?? prev.presaleMinted, proposals: prev.proposals }));
        // proposals in the background (governance tab; never blocks first paint)
        loadProposalsIndexed().then((proposals) => setS((prev) => ({ ...prev, proposals }))).catch(() => {});
        return;
      }

      const vol24hEth = d.vol24hEth ?? 0;
      const deathEth = d.deathThresholdEth ?? 0;
      const vitality = deathEth > 0 ? Math.max(0, Math.min(100, (vol24hEth / (deathEth * 4)) * 100)) : 100;
      const phase = (d.phase ?? "live") as Phase;
      const availableEth = (d.relaunchEth ?? 0) + (d.vaultEth ?? 0);

      setS((prev) => ({
        loading: false, summoned: true, phase, gen: d.gen,
        token: d.token as Address, collection: (d.collection ?? "") as Address,
        vault: prev.vault, poolId: d.poolId as `0x${string}`,
        name: cleanName(d.name ?? ""), ticker: d.ticker ?? "",
        vol24hEth, vitality, deathThresholdEth: deathEth, isDead: !!d.dead,
        nftMinted: d.nftMinted ?? 0, nftMax: d.nftMax ?? 0,
        presaleMinted: CAULDRON.genesisSupply, presaleGoal: CAULDRON.genesisSupply,
        priceSeries: prev.priceSeries,
        // Take the price straight off THIS response. /cauldron already carries
        // the pool's latest indexed price, and it is the same number the chart
        // draws — so the header, market cap and FDV move the moment a swap is
        // indexed. Previously this carried `prev.spotPrice` and waited on the
        // slower background series load, which is why a confirmed buy left the
        // page unchanged while the trading chart had already updated.
        spotPrice: d.spotPrice && d.spotPrice > 0 ? d.spotPrice : prev.spotPrice,
        // Carried over, not reset: the reserve is fetched separately just below,
        // and dropping it here blanks circulating market cap on every poll.
        reserveTokens: prev.reserveTokens,
        relaunchEth: d.relaunchEth ?? 0, vaultEth: d.vaultEth ?? 0, availableEth,
        relaunchAt: d.relaunchAt ?? 0,
        proposals: prev.proposals, migratable: prev.migratable,
      }));

      // Reserve tokens (out-of-range, backs the floor) → excluded from circulating
      // MC. From /floor (Ponder), background, zero browser RPC.
      fetch(`${INDEXER}/floor`, { signal: AbortSignal.timeout(8000) })
        .then((r) => r.json())
        .then((fj: { reserveTokens?: number }) => setS((prev) => ({ ...prev, reserveTokens: fj.reserveTokens ?? prev.reserveTokens })))
        .catch(() => { /* keep prior */ });

      // The price SERIES is no longer loaded here. It used to have its own
      // fetch-with-fallback path, which made this hook a second, slower source
      // of truth for price — the header could sit on a stale number while the
      // trading chart had already moved. Both now derive from useSwapTape, and
      // spotPrice comes straight off the /cauldron response above.
      loadProposalsIndexed().then((proposals) => setS((prev) => ({ ...prev, proposals }))).catch(() => {});
      } catch {
        setS((prev) => ({ ...prev, loading: false }));
      }
    } finally {
      loadingRef.current = false;
    }
  }, []); // stable — reads publicClient via pcRef; no churn, no fetch loop

  // usePoll fires once on mount and again whenever the tab returns to the
  // foreground, so no separate initial-load effect is needed.
  usePoll(load, 15_000);
  useEffect(() => { if (confirmed) load(); }, [confirmed, load]);

  const relaunch = useCallback(async (): Promise<`0x${string}`> => {
    if (!address) throw new Error("Connect a wallet first");
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
    return writeContractAsync({ address: CAULDRON.registry, abi: REGISTRY_ABI, functionName: "relaunch" });
  }, [address, chainId, switchChainAsync, writeContractAsync]);

  /** Block until a submitted tx is mined ON THE CAULDRON CHAIN, and return the
   *  receipt so callers can verify it actually did something. Catches the
   *  "wallet was on the wrong network" trap: a call to a codeless address on the
   *  wrong chain reports success in the wallet but never lands here — waiting on
   *  the Cauldron-chain client makes that failure explicit instead of silent. */
  const waitForReceipt = useCallback(async (hash: `0x${string}`) => {
    if (!publicClient) throw new Error("No RPC client");
    const rc = await publicClient.waitForTransactionReceipt({ hash, timeout: 90_000 });
    if (rc.status !== "success") throw new Error("Transaction reverted on-chain.");
    return rc;
  }, [publicClient]);

  const voteFor = useCallback(async (proposalId: number): Promise<`0x${string}`> => {
    if (!address) throw new Error("Connect a wallet first");
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
    return writeContractAsync({ address: CAULDRON.governor, abi: GOVERNOR_ABI, functionName: "vote", args: [BigInt(proposalId)] });
  }, [address, chainId, switchChainAsync, writeContractAsync]);

  /** Migrate a dead generation's tokens into the current brew, 1:1. Burns the
   *  caller's `fromGen` tokens and mints the same amount of the current token. */
  const claimPrev = useCallback(async (fromGen: number, amount: bigint): Promise<`0x${string}`> => {
    if (!address) throw new Error("Connect a wallet first");
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
    return writeContractAsync({ address: CAULDRON.registry, abi: REGISTRY_ABI, functionName: "claimByBurn", args: [BigInt(fromGen), amount] });
  }, [address, chainId, switchChainAsync, writeContractAsync]);

  /** Propose the next brew (MiFrens holders only). The proposer specifies the
   *  collection size, its art (on-chain renderer OR baseURI), and the total
   *  ETH-volume target to mint it out (→ per-NFT curve = mintOutEth/nftSupply). */
  const propose = useCallback(async (p: {
    name: string; symbol: string; nftSupply: number; mintOutEth: number;
    renderer?: string; baseURI?: string; website?: string; socials?: string;
  }): Promise<`0x${string}`> => {
    if (!address) throw new Error("Connect a wallet first");
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
    const useRenderer = !!p.renderer && /^0x[0-9a-fA-F]{40}$/.test(p.renderer);
    const supply = BigInt(Math.max(1, Math.floor(p.nftSupply)));
    // Flat mint-out curve: per-NFT volume = total target / supply (wei).
    const perNft = supply > 0n
      ? parseEther(Math.max(0, p.mintOutEth).toFixed(18)) / supply
      : 0n;
    return writeContractAsync({
      address: CAULDRON.governor, abi: GOVERNOR_ABI, functionName: "propose",
      args: [
        p.name, p.symbol.toUpperCase(),
        useRenderer ? 1 : 0, // 1 = Renderer, 0 = BaseURI
        useRenderer ? "" : (p.baseURI || "https://mifrens.xyz/api/cauldron/"),
        (useRenderer ? p.renderer! : "0x0000000000000000000000000000000000000000") as Address,
        p.website ?? "", p.socials ?? "", supply, perNft,
      ],
    });
  }, [address, chainId, switchChainAsync, writeContractAsync]);

  // Does the connected wallet hold a MiFren? (gates proposing)
  const { data: mifrenBalance } = useReadContract({
    address: CAULDRON.mifrens, abi: MIFRENS_ERC721_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: CAULDRON.chainId,
    query: { enabled: !!address },
  });
  const holdsMiFren = (mifrenBalance ?? 0n) > 0n;

  const fdv = useMemo(() => s.spotPrice * 777_000_000, [s.spotPrice]); // fully-diluted, in ETH
  // Circulating MC = spot × supply that can actually reach the market at ~spot,
  // i.e. total minus the out-of-range reserve (locked at ~69× to back the floor).
  const circSupply = useMemo(() => Math.max(0, 777_000_000 - (s.reserveTokens || 0)), [s.reserveTokens]);
  const mcap = useMemo(() => s.spotPrice * circSupply, [s.spotPrice, circSupply]); // circulating MC in ETH
  const priceUsd = useMemo(() => s.spotPrice * ethUsd, [s.spotPrice, ethUsd]);
  const mcapUsd = useMemo(() => mcap * ethUsd, [mcap, ethUsd]);   // circulating MC in USD
  const fdvUsd = useMemo(() => fdv * ethUsd, [fdv, ethUsd]);      // fully-diluted in USD

  return { ...s, mcap, fdv, ethUsd, priceUsd, mcapUsd, fdvUsd, relaunch, voteFor, propose, claimPrev, holdsMiFren, waitForReceipt, refresh: load, txHash, isPending, confirming, confirmed, reset };
}

/* ── helpers ─────────────────────────────────────────────────────── */

function cleanName(n: string) {
  return n.replace(/\s*by Magic Internet Frens\s*$/i, "").trim();
}

/** ETH (currency0) held in the generation's full-range LP position — the amount
 *  the registry recovers on relaunch. From position liquidity L + current price:
 *  amount0 = L·2^96·(sqrtMax − sqrtP)/(sqrtP·sqrtMax). */
/** Retry a flaky RPC read a couple times before giving up (public RPCs rate-limit
 *  and can intermittently drop `extsload`/position reads — a single failure must
 *  NOT silently zero the LP that seeds the next launch). */
async function withRetry<T>(fn: () => Promise<T>, tries = 3): Promise<T> {
  let last: unknown;
  for (let i = 0; i < tries; i++) {
    try { return await fn(); }
    catch (e) { last = e; await new Promise((r) => setTimeout(r, 250 * (i + 1))); }
  }
  throw last;
}

async function lpEthOf(pc: PC, poolId: `0x${string}`, gen: bigint): Promise<number> {
  const Q96 = 1n << 96n;
  const SQRT_MAX = 1461446703485210103287273052203988822378723970342n;
  // V4 pool state lives at keccak256(abi.encode(poolId, POOLS_SLOT=6)); slot0 first.
  const stateSlot = keccak256(encodeAbiParameters(
    [{ type: "bytes32" }, { type: "uint256" }], [poolId, 6n],
  ));
  const [slot0, positionId] = await Promise.all([
    withRetry(() => pc.readContract({ address: CAULDRON.poolManager, abi: POOLMANAGER_ABI, functionName: "extsload", args: [stateSlot] }) as Promise<`0x${string}`>),
    withRetry(() => pc.readContract({ address: CAULDRON.registry, abi: REGISTRY_ABI, functionName: "generationPositionId", args: [gen] }) as Promise<bigint>),
  ]);
  const sqrtP = BigInt(slot0) & ((1n << 160n) - 1n);
  if (sqrtP === 0n || positionId === 0n) return 0;
  const L = await withRetry(() => pc.readContract({ address: POSITION_MANAGER, abi: POSITION_MANAGER_ABI, functionName: "getPositionLiquidity", args: [positionId] }) as Promise<bigint>);
  if (L === 0n) return 0;
  const amount0 = (L * Q96 * (SQRT_MAX - sqrtP)) / (sqrtP * SQRT_MAX);
  return Number(formatEther(amount0));
}

/** Scan every previous generation (1 … gen-1) for tokens the wallet still holds.
 *  These are the "dead" brews that can be migrated 1:1 into the current one. */
async function loadMigratable(pc: PC, gen: number, address?: Address): Promise<MigratableBalance[]> {
  if (!address || gen < 2) return [];
  const reg = { address: CAULDRON.registry, abi: REGISTRY_ABI } as const;
  const gens = Array.from({ length: gen - 1 }, (_, i) => i + 1); // 1 … gen-1
  const rows = await Promise.all(gens.map(async (g) => {
    try {
      const token = await pc.readContract({ ...reg, functionName: "generationToken", args: [BigInt(g)] }) as Address;
      if (!token || token === "0x0000000000000000000000000000000000000000") return null;
      const [balance, symbol] = await Promise.all([
        pc.readContract({ address: token, abi: TOKEN_ABI, functionName: "balanceOf", args: [address] }) as Promise<bigint>,
        pc.readContract({ address: token, abi: TOKEN_ABI, functionName: "symbol" }).catch(() => "???") as Promise<string>,
      ]);
      if (balance === 0n) return null;
      return { gen: g, token, symbol, balance } as MigratableBalance;
    } catch { return null; }
  }));
  return rows.filter((r): r is MigratableBalance => r !== null);
}

async function loadProposals(pc: PC): Promise<Proposal[]> {
  try {
    const count = await pc.readContract({ address: CAULDRON.governor, abi: GOVERNOR_ABI, functionName: "proposalCount" }) as bigint;
    const n = Number(count);
    if (n === 0) return [];
    const ids = Array.from({ length: n }, (_, i) => i + 1);
    const raw = await Promise.all(ids.map((id) =>
      pc.readContract({ address: CAULDRON.governor, abi: GOVERNOR_ABI, functionName: "getProposal", args: [BigInt(id)] })
        .catch(() => null)
    ));
    return raw.flatMap((p, i) => {
      const pr = p as { name: string; symbol: string; mode: number; baseURI: string; renderer: Address; website: string; socials: string; nftSupply: bigint; volumePerNFT: bigint; proposer: Address; votes: bigint; consumed: boolean; exists: boolean } | null;
      if (!pr || !pr.exists || pr.consumed) return [];
      const supply = Number(pr.nftSupply);
      return [{
        id: ids[i], name: pr.name, ticker: pr.symbol,
        theme: pr.website ? `${pr.name} — ${pr.website}` : pr.name,
        website: pr.website || undefined, socials: pr.socials || undefined,
        proposer: pr.proposer, votes: Number(pr.votes), consumed: pr.consumed,
        metaMode: pr.mode === 1 ? "renderer" : "uri",
        metaValue: pr.mode === 1 ? pr.renderer : pr.baseURI,
        nftSupply: supply,
        mintOutEth: Number(formatEther(pr.volumePerNFT)) * supply,
      } as Proposal];
    }).sort((a, b) => b.votes - a.votes);
  } catch {
    return [];
  }
}


function sample(arr: number[], n: number): number[] {
  const out: number[] = [];
  const step = (arr.length - 1) / (n - 1);
  for (let i = 0; i < n; i++) out.push(arr[Math.round(i * step)]);
  return out;
}
