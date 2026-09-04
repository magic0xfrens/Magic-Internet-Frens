import { useCallback, useEffect, useState } from "react";
import { parseAbiItem, type Address } from "viem";
import {
  useAccount,
  usePublicClient,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { CAULDRON, DIVIDEND_ABI } from "@/config/cauldron";
import { fetchOwnedGenesis, fetchEnchanted } from "@/lib/cauldronIndexer";

const TRANSFER = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)"
);

type PC = NonNullable<ReturnType<typeof usePublicClient>>;

/** Chunked multicall reading a bool-returning dividend view for many ids. Failed
 *  reads default to false. One request per 250-id chunk (never N loose calls). */
async function multicallBool(pc: PC, fn: "isEnchanted", ids: bigint[]): Promise<boolean[]> {
  const CHUNK = 250; const out: boolean[] = [];
  for (let i = 0; i < ids.length; i += CHUNK) {
    const slice = ids.slice(i, i + CHUNK);
    try {
      const res = await pc.multicall({
        contracts: slice.map((id) => ({ address: CAULDRON.dividend, abi: DIVIDEND_ABI, functionName: fn, args: [id] })),
        allowFailure: true,
      });
      for (const r of res) out.push(r.status === "success" ? Boolean(r.result) : false);
    } catch { for (let k = 0; k < slice.length; k++) out.push(false); }
  }
  return out;
}

/** Chunked multicall reading a uint-returning dividend view for many ids. */
async function multicallBigint(pc: PC, fn: "pending", ids: bigint[]): Promise<bigint[]> {
  const CHUNK = 250; const out: bigint[] = [];
  for (let i = 0; i < ids.length; i += CHUNK) {
    const slice = ids.slice(i, i + CHUNK);
    try {
      const res = await pc.multicall({
        contracts: slice.map((id) => ({ address: CAULDRON.dividend, abi: DIVIDEND_ABI, functionName: fn, args: [id] })),
        allowFailure: true,
      });
      for (const r of res) out.push(r.status === "success" ? (r.result as bigint) : 0n);
    } catch { for (let k = 0; k < slice.length; k++) out.push(0n); }
  }
  return out;
}

// eth_getLogs is capped at ~1000 blocks/response on most public RPCs
// (thirdweb rejects wider ranges), so scan in ≤1000-block windows.
const LOG_CHUNK = 1000n;

/**
 * Fallback ownership scan when the indexer is unavailable: reconstruct the
 * wallet's current genesis MiFrens from Transfer logs (in − out), chunked so
 * rate-limited RPCs don't reject the range.
 */
async function genesisFromLogs(
  publicClient: NonNullable<ReturnType<typeof usePublicClient>>,
  address: Address,
): Promise<bigint[]> {
  const head = await publicClient.getBlockNumber();
  const scan = async (dir: "to" | "from") => {
    const out: { tokenId: bigint; blockNumber: bigint; logIndex: number }[] = [];
    for (let from = CAULDRON.deployBlock; from <= head; from += LOG_CHUNK) {
      const to = from + LOG_CHUNK - 1n > head ? head : from + LOG_CHUNK - 1n;
      const logs = await publicClient.getLogs({
        address: CAULDRON.mifrens,
        event: TRANSFER,
        args: dir === "to" ? { to: address } : { from: address },
        fromBlock: from,
        toBlock: to,
      });
      for (const l of logs)
        out.push({ tokenId: l.args.tokenId as bigint, blockNumber: l.blockNumber!, logIndex: l.logIndex! });
    }
    return out;
  };
  const [incoming, outgoing] = await Promise.all([scan("to"), scan("from")]);

  // Net balance per tokenId: +1 received, -1 sent (in chronological order).
  const owned = new Set<bigint>();
  const events = [
    ...incoming.map((l) => ({ id: l.tokenId, inbound: true, bn: l.blockNumber, li: l.logIndex })),
    ...outgoing.map((l) => ({ id: l.tokenId, inbound: false, bn: l.blockNumber, li: l.logIndex })),
  ].sort((a, b) => (a.bn === b.bn ? a.li - b.li : Number(a.bn - b.bn)));
  for (const e of events) {
    if (e.inbound) owned.add(e.id);
    else owned.delete(e.id);
  }
  return [...owned]
    .filter((id) => id >= 1n && id <= BigInt(CAULDRON.genesisSupply))
    .sort((a, b) => Number(a - b));
}

/** The genesis MiFren tokenIds an address owns right now — indexer first, then a
 *  bounded on-chain Transfer scan. Shared by the ETH dividend and the genesis
 *  token bonus so ownership is derived one way. */
export async function ownedGenesisIds(
  publicClient: NonNullable<ReturnType<typeof usePublicClient>>,
  address: Address,
): Promise<bigint[]> {
  const fromIndexer = await fetchOwnedGenesis(address);
  if (fromIndexer !== null) return fromIndexer;
  return genesisFromLogs(publicClient, address);
}

export interface DividendState {
  /** Genesis MiFren tokenIds (<= genesisSupply) the wallet currently owns. */
  ownedGenesis: bigint[];
  /** Per-token pending ETH (wei), aligned with ownedGenesis. */
  perToken: bigint[];
  /** Per-token "spell cast" status, aligned with ownedGenesis. */
  enchanted: boolean[];
  /** Total claimable ETH across all owned genesis MiFrens (wei). */
  totalPending: bigint;
  /** ETH settled to this wallet when a fren left the active set (pull). */
  owed: bigint;
  loading: boolean;
  error?: string;
}

/**
 * useMiFrensDividend — how much ETH the wallet's GENESIS MiFrens can claim from
 * the MiFrensDividend (a slice of every iteration's swap fees + sniper surtax).
 *
 * The presale collection isn't Enumerable, so ownership comes from the Ponder
 * indexer (`/nfts/:owner`, which tracks Transfers server-side). When the indexer
 * is unset/unreachable we fall back to a bounded on-chain Transfer scan (chunked
 * ≤1000 blocks so rate-limited RPCs don't reject the request). We keep only
 * genesis ids (1..genesisSupply), then read `pending(id)` for each. Claiming
 * uses claimMany.
 */
export function useMiFrensDividend() {
  const { address, chainId } = useAccount();
  const publicClient = usePublicClient({ chainId: CAULDRON.chainId });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: confirming, isSuccess: confirmed } =
    useWaitForTransactionReceipt({ hash: txHash, chainId: CAULDRON.chainId });

  const [state, setState] = useState<DividendState>({
    ownedGenesis: [],
    perToken: [],
    enchanted: [],
    totalPending: 0n,
    owed: 0n,
    loading: false,
  });

  const load = useCallback(async () => {
    if (!address || !publicClient) {
      setState({ ownedGenesis: [], perToken: [], enchanted: [], totalPending: 0n, owed: 0n, loading: false });
      return;
    }
    setState((s) => ({ ...s, loading: true, error: undefined }));
    try {
      // 1) Ownership from the indexer (scales; no getLogs). null → fall back.
      let genesis = await fetchOwnedGenesis(address);

      // 2) Fallback: bounded on-chain Transfer scan when the indexer is down.
      if (genesis === null) {
        genesis = await genesisFromLogs(publicClient, address);
      }

      // A fren only accrues fees once ENCHANTED, so we don't need to read
      // pending() for all (potentially 1111) owned frens — that call storm was
      // hammering the RPC. Get the enchanted set from the indexer (Ponder) and
      // only read pending() for those; everything else is 0 by definition.
      const enchantedFromIndexer = await fetchEnchanted(address);
      const enchantedSet = new Set<string>();
      if (enchantedFromIndexer !== null) {
        for (const id of enchantedFromIndexer) enchantedSet.add(id.toString());
      } else {
        // Indexer down → fall back to on-chain isEnchanted, but MULTICALLED and
        // chunked so it stays one request per chunk (never 1111 loose calls).
        const flags = await multicallBool(publicClient, "isEnchanted", genesis);
        genesis.forEach((id, i) => { if (flags[i]) enchantedSet.add(id.toString()); });
      }

      const enchanted = genesis.map((id) => enchantedSet.has(id.toString()));
      const enchantedIds = genesis.filter((id) => enchantedSet.has(id.toString()));

      // pending() only for the enchanted frens (usually a handful, often 0).
      const pendingByEnchanted = enchantedIds.length
        ? await multicallBigint(publicClient, "pending", enchantedIds)
        : [];
      const pendingMap = new Map<string, bigint>();
      enchantedIds.forEach((id, i) => pendingMap.set(id.toString(), pendingByEnchanted[i] ?? 0n));
      const perToken = genesis.map((id) => pendingMap.get(id.toString()) ?? 0n);
      const totalPending = perToken.reduce((a, b) => a + b, 0n);

      const owed = await (publicClient.readContract({
        address: CAULDRON.dividend, abi: DIVIDEND_ABI, functionName: "owed", args: [address],
      }).catch(() => 0n) as Promise<bigint>);

      setState({ ownedGenesis: genesis, perToken, enchanted, totalPending, owed, loading: false });
    } catch (e: unknown) {
      setState((s) => ({ ...s, loading: false, error: (e as Error)?.message ?? "load failed" }));
    }
  }, [address, publicClient]);

  useEffect(() => {
    load();
  }, [load]);

  // Refresh once a claim confirms.
  useEffect(() => {
    if (confirmed) load();
  }, [confirmed, load]);

  /** Claim all owned genesis MiFrens' accrued ETH in one tx. */
  const claimAll = useCallback(async (): Promise<`0x${string}`> => {
    if (!address) throw new Error("Connect a wallet first");
    if (state.ownedGenesis.length === 0) throw new Error("No genesis MiFrens to claim");
    if (chainId !== CAULDRON.chainId) {
      await switchChainAsync({ chainId: CAULDRON.chainId });
    }
    return writeContractAsync({
      address: CAULDRON.dividend,
      abi: DIVIDEND_ABI,
      functionName: "claimMany",
      args: [state.ownedGenesis],
    });
  }, [address, chainId, state.ownedGenesis, switchChainAsync, writeContractAsync]);

  const unenchantedIds = state.ownedGenesis.filter((_, i) => !state.enchanted[i]);

  /** Cast the spell on every owned fren that isn't enchanted yet (one tx). */
  const castAll = useCallback(async (): Promise<`0x${string}`> => {
    if (!address) throw new Error("Connect a wallet first");
    const ids = state.ownedGenesis.filter((_, i) => !state.enchanted[i]);
    if (ids.length === 0) throw new Error("Your frens are all enchanted");
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
    return writeContractAsync({ address: CAULDRON.dividend, abi: DIVIDEND_ABI, functionName: "castMany", args: [ids] });
  }, [address, chainId, state.ownedGenesis, state.enchanted, switchChainAsync, writeContractAsync]);

  /** Withdraw ETH settled to you when a fren left the active set (transfers). */
  const withdrawOwed = useCallback(async (): Promise<`0x${string}`> => {
    if (!address) throw new Error("Connect a wallet first");
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
    return writeContractAsync({ address: CAULDRON.dividend, abi: DIVIDEND_ABI, functionName: "withdrawOwed" });
  }, [address, chainId, switchChainAsync, writeContractAsync]);

  return {
    ...state,
    unenchantedIds,
    claimAll,
    castAll,
    withdrawOwed,
    refresh: load,
    txHash,
    isPending,   // wallet signing
    confirming,  // waiting for confirmation
    confirmed,
    reset,
  };
}
