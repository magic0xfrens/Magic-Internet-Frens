import { useCallback, useEffect, useMemo, useState } from "react";
import { formatEther, parseEther, parseAbiItem, keccak256, encodeAbiParameters, type Address } from "viem";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import {
  CAULDRON, CAULDRON_INDEXER, REGISTRY_ABI, HOOK_ABI, GOVERNOR_ABI, COLLECTION_ABI, TOKEN_ABI, SWAP_EVENT,
  POOLMANAGER_ABI, POSITION_MANAGER, POSITION_MANAGER_ABI, MIFRENS_ERC721_ABI,
} from "@/config/cauldron";

const SWAP = parseAbiItem(SWAP_EVENT);

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
  priceSeries: [], spotPrice: 0, relaunchEth: 0, vaultEth: 0, availableEth: 0, relaunchAt: 0, proposals: [],
  migratable: [],
};

const PRESALE_MINI_ABI = [
  { type: "function", name: "minted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

type PC = NonNullable<ReturnType<typeof usePublicClient>>;

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
  const { isLoading: confirming, isSuccess: confirmed } = useWaitForTransactionReceipt({ hash: txHash });

  const [s, setS] = useState<MachineState>(EMPTY);
  const [ethUsd, setEthUsd] = useState<number>(0);

  // Live ETH/USD for price + market-cap display (Coinbase spot, CORS-friendly).
  useEffect(() => {
    let alive = true;
    const fetchUsd = async () => {
      try {
        const r = await fetch("https://api.coinbase.com/v2/prices/ETH-USD/spot", { signal: AbortSignal.timeout(5000) });
        const j = await r.json();
        const p = Number(j?.data?.amount);
        if (alive && p > 0) setEthUsd(p);
      } catch { /* keep last */ }
    };
    fetchUsd();
    const id = setInterval(fetchUsd, 60_000);
    return () => { alive = false; clearInterval(id); };
  }, []);

  const load = useCallback(async () => {
    if (!publicClient) return;
    try {
      const reg = { address: CAULDRON.registry, abi: REGISTRY_ABI } as const;
      const [summoned, genBn] = await Promise.all([
        publicClient.readContract({ ...reg, functionName: "summoned" }) as Promise<boolean>,
        publicClient.readContract({ ...reg, functionName: "currentGeneration" }) as Promise<bigint>,
      ]);
      const gen = Number(genBn);
      const proposals = await loadProposals(publicClient);

      if (!summoned || gen === 0) {
        const minted = await publicClient
          .readContract({ address: CAULDRON.mifrens, abi: PRESALE_MINI_ABI, functionName: "minted" })
          .catch(() => 0n) as bigint;
        setS({ ...EMPTY, loading: false, summoned: false, phase: "presale",
          presaleMinted: Number(minted), proposals });
        return;
      }

      // Previous-generation tokens this wallet still holds — claimable 1:1 into
      // the current brew. Only exists once there's been ≥1 relaunch (gen ≥ 2).
      const migratable = await loadMigratable(publicClient, gen, address);

      const [token, collection, vault, poolId, lastSummonAt, minLifetime] = await Promise.all([
        publicClient.readContract({ ...reg, functionName: "currentToken" }) as Promise<Address>,
        publicClient.readContract({ ...reg, functionName: "generationCollection", args: [genBn] }) as Promise<Address>,
        publicClient.readContract({ ...reg, functionName: "generationVault", args: [genBn] }) as Promise<Address>,
        publicClient.readContract({ ...reg, functionName: "generationPoolId", args: [genBn] }) as Promise<`0x${string}`>,
        publicClient.readContract({ ...reg, functionName: "lastSummonAt" }).catch(() => 0n) as Promise<bigint>,
        publicClient.readContract({ ...reg, functionName: "minLifetime" }).catch(() => 0n) as Promise<bigint>,
      ]);

      const hook = { address: CAULDRON.hook, abi: HOOK_ABI } as const;
      const col = { address: collection, abi: COLLECTION_ABI } as const;
      const [name, ticker, vol24h, isDead, deathThr, relaunchEth, nftMinted, nftMax, vaultBal] = await Promise.all([
        publicClient.readContract({ address: token, abi: TOKEN_ABI, functionName: "name" }) as Promise<string>,
        publicClient.readContract({ address: token, abi: TOKEN_ABI, functionName: "symbol" }) as Promise<string>,
        publicClient.readContract({ ...hook, functionName: "getVolume24h", args: [poolId] }) as Promise<bigint>,
        publicClient.readContract({ ...hook, functionName: "isDead", args: [poolId] }) as Promise<boolean>,
        publicClient.readContract({ ...hook, functionName: "deathThreshold" }) as Promise<bigint>,
        publicClient.readContract({ ...hook, functionName: "relaunchETH" }) as Promise<bigint>,
        publicClient.readContract({ ...col, functionName: "totalMinted" }) as Promise<bigint>,
        publicClient.readContract({ ...col, functionName: "maxSupply" }) as Promise<bigint>,
        publicClient.getBalance({ address: vault }).catch(() => 0n),
      ]);

      const vol24hEth = Number(formatEther(vol24h));
      const deathEth = Number(formatEther(deathThr));
      const vitality = Math.max(0, Math.min(100, (vol24hEth / (deathEth * 4)) * 100));
      const phase: Phase = isDead ? "dead" : vol24hEth < deathEth ? "dying" : "live";

      // ETH available to seed the NEXT iteration = LP ETH (recovered on death) +
      // hook fee reserve + floor vault (swept on death). The LP ETH is the big
      // piece — compute it from the live position + pool price.
      const relaunchEthN = Number(formatEther(relaunchEth));
      const vaultEthN = Number(formatEther(vaultBal));
      const lpEth = await lpEthOf(publicClient, poolId, genBn).catch(() => 0);
      const availableEth = lpEth + relaunchEthN + vaultEthN;

      // Render the brew IMMEDIATELY from core on-chain data — don't block on the
      // price chart (the indexer fetch can take a few seconds). This is what made
      // the page sit on "syncing" right after a summon. Keep any prior series so
      // it doesn't flash empty; the chart fills in async just below.
      setS((prev) => ({
        loading: false, summoned: true, phase, gen,
        token, collection, vault, poolId,
        name: cleanName(name), ticker,
        vol24hEth, vitality, deathThresholdEth: deathEth, isDead,
        nftMinted: Number(nftMinted), nftMax: Number(nftMax),
        presaleMinted: CAULDRON.genesisSupply, presaleGoal: CAULDRON.genesisSupply,
        priceSeries: prev.priceSeries, spotPrice: prev.spotPrice,
        relaunchEth: relaunchEthN, vaultEth: vaultEthN, availableEth,
        relaunchAt: Number(lastSummonAt + minLifetime),
        proposals, migratable,
      }));

      // Price series (indexer → candles → on-chain) loads in the background.
      loadSeries(publicClient, poolId, gen, token)
        .then(({ series, spot }) => setS((prev) => ({
          ...prev,
          priceSeries: series.length ? series : prev.priceSeries,
          spotPrice: spot || prev.spotPrice,
        })))
        .catch(() => { /* keep prior series */ });
    } catch {
      setS((prev) => ({ ...prev, loading: false }));
    }
  }, [publicClient, address]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    const id = setInterval(load, 15_000);
    return () => clearInterval(id);
  }, [load]);
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
        useRenderer ? "" : (p.baseURI || "https://magicfrens.xyz/api/cauldron/"),
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

  const mcap = useMemo(() => s.spotPrice * 777_000_000, [s.spotPrice]); // FDV in ETH
  const priceUsd = useMemo(() => s.spotPrice * ethUsd, [s.spotPrice, ethUsd]);
  const fdvUsd = useMemo(() => mcap * ethUsd, [mcap, ethUsd]);

  return { ...s, mcap, ethUsd, priceUsd, fdvUsd, relaunch, voteFor, propose, claimPrev, holdsMiFren, waitForReceipt, refresh: load, txHash, isPending, confirming, confirmed, reset };
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

/** Price series for the chart. Prefers PER-TRADE points (livelier "heartbeat"
 *  line — every buy ticks up, every sell ticks down) from the indexer's raw
 *  swaps; falls back to candle closes, then on-chain getLogs.
 *
 *  IMPORTANT: the indexer keys pools by generation number, but a *redeployed*
 *  launchpad reuses gen #1 with a DIFFERENT token. So we first validate that the
 *  indexer's pool token matches the live on-chain token — otherwise it's stale
 *  data from a previous deploy (a rising line on a pool that has 0 real volume),
 *  and we fall through to reading the current pool on-chain instead. */
async function loadSeries(
  pc: PC, poolId: `0x${string}`, gen: number, currentToken?: Address,
): Promise<{ series: number[]; spot: number }> {
  const base = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "/api";
  // 1) candles carry pool.token → use them to validate the iteration matches.
  const url = CAULDRON_INDEXER ? `${base}/candles/${gen}?limit=120` : `${base}/candles?gen=${gen}&limit=120`;
  let indexerFresh = false;
  let candleSeries: number[] = [];
  let candleSpot = 0;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
    if (res.ok) {
      const data = await res.json() as { pool?: { token?: string }; candles?: { c: number }[]; last?: number };
      const tok = data.pool?.token?.toLowerCase();
      indexerFresh = !!tok && !!currentToken && tok === currentToken.toLowerCase();
      if (indexerFresh) {
        candleSeries = (data.candles ?? []).map((k) => k.c).filter((p) => p > 0 && Number.isFinite(p));
        candleSpot = data.last && data.last > 0 ? data.last : candleSeries[candleSeries.length - 1] ?? 0;
      }
    }
  } catch { /* endpoint down → on-chain below */ }

  // 2) if the indexer is on the current iteration, prefer its per-trade tape.
  if (indexerFresh) {
    try {
      const rurl = CAULDRON_INDEXER ? `${base}/recent/${gen}?limit=150` : `${base}/recent?gen=${gen}&limit=150`;
      const rr = await fetch(rurl, { signal: AbortSignal.timeout(6000) });
      if (rr.ok) {
        const d = await rr.json() as { swaps?: { price: number }[] };
        const pts = (d.swaps ?? []).map((s) => s.price).filter((p) => p > 0 && Number.isFinite(p)).reverse();
        if (pts.length >= 2) return { series: pts, spot: pts[pts.length - 1] };
      }
    } catch { /* fall through to candles */ }
    if (candleSeries.length > 0) return { series: candleSeries, spot: candleSpot };
  }

  // 3) stale indexer (or none) → read the CURRENT pool on-chain.
  return loadSwapSeries(pc, poolId);
}

async function loadSwapSeries(pc: PC, poolId: `0x${string}`): Promise<{ series: number[]; spot: number }> {
  try {
    // Last-resort fallback (indexer down). Public RPCs cap getLogs at ~1000
    // blocks/response, so walk backward in 1000-block windows until we have
    // enough points or run out of a bounded lookback.
    const CHUNK = 1000n;
    const MAX_LOOKBACK = 40_000n; // ~ a few days on Sepolia
    const latest = await pc.getBlockNumber();
    // Never scan before the launchpad existed — the current pool can't have
    // swaps older than the deploy. This keeps the fallback to a couple of
    // getLogs calls (fast + reliable) instead of ~40 mostly-empty ones.
    const lookbackFloor = latest > MAX_LOOKBACK ? latest - MAX_LOOKBACK : 0n;
    const floor = CAULDRON.deployBlock > lookbackFloor ? CAULDRON.deployBlock : lookbackFloor;
    const logs: Awaited<ReturnType<typeof pc.getLogs>> = [];
    for (let to = latest; to >= floor; to -= CHUNK) {
      const from = to > floor + CHUNK - 1n ? to - CHUNK + 1n : floor;
      const chunk = await pc.getLogs({
        address: CAULDRON.poolManager, event: SWAP, args: { id: poolId },
        fromBlock: from, toBlock: to,
      });
      logs.unshift(...chunk);
      if (logs.length >= 120) break; // plenty for a chart line
      if (from === floor) break;
    }
    const prices = logs
      .map((l) => {
        const sp = l.args.sqrtPriceX96 as bigint | undefined;
        if (!sp) return 0;
        // token is currency1; (sqrtP/2^96)^2 = token per ETH → invert = ETH per token.
        const num = Number(sp) / 2 ** 96;
        const tokenPerEth = num * num;
        return tokenPerEth > 0 ? 1 / tokenPerEth : 0;
      })
      .filter((p) => p > 0 && Number.isFinite(p));
    const spot = prices.length ? prices[prices.length - 1] : 0;
    const series = prices.length <= 60 ? prices : sample(prices, 60);
    return { series, spot };
  } catch {
    return { series: [], spot: 0 };
  }
}

function sample(arr: number[], n: number): number[] {
  const out: number[] = [];
  const step = (arr.length - 1) / (n - 1);
  for (let i = 0; i < n; i++) out.push(arr[Math.round(i * step)]);
  return out;
}
