import { useCallback, useEffect, useState } from "react";
import { type Address } from "viem";
import {
  useAccount,
  usePublicClient,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { CAULDRON, REGISTRY_ABI, TOKEN_ABI, MIFRENS_ERC721_ABI } from "@/config/cauldron";
import { ownedGenesisIds } from "./useMiFrensDividend";

const ZERO = "0x0000000000000000000000000000000000000000" as Address;

/** Read genesisClaimed(id) for many ids reliably via multicall, chunked so the
 *  aggregate call never hits a gas/size limit. Falls back to per-id reads only
 *  if multicall is unavailable. A failed read is treated as UNKNOWN → we keep it
 *  claimed-safe (true) so we never re-attempt a claim that already happened. */
async function multicallClaimed(
  pc: NonNullable<ReturnType<typeof usePublicClient>>,
  reg: { address: Address; abi: typeof REGISTRY_ABI },
  ids: bigint[],
): Promise<boolean[]> {
  const CHUNK = 250;
  const out: boolean[] = [];
  for (let i = 0; i < ids.length; i += CHUNK) {
    const slice = ids.slice(i, i + CHUNK);
    try {
      const res = await pc.multicall({
        contracts: slice.map((id) => ({ ...reg, functionName: "genesisClaimed", args: [id] })),
        allowFailure: true,
      });
      for (const r of res) out.push(r.status === "success" ? Boolean(r.result) : true);
    } catch {
      // Multicall unsupported → conservative fallback (treat as claimed so we
      // don't spam reverting re-claims; a later successful load corrects it).
      for (let k = 0; k < slice.length; k++) out.push(true);
    }
  }
  return out;
}

/** How many genesis MiFrens we'll claim per click. Each `claimGenesis` is its own
 *  tx (the contract has no batch), so we cap the wallet-popup burst and let the
 *  user repeat for the rest. Normal holders (a few NFTs) clear it in one go. */
const CLAIM_BATCH = 12;

export interface GenesisBonusState {
  loading: boolean;
  mifrenCount: number;        // total MiFrens the wallet holds (balanceOf)
  ownedGenesis: bigint[];     // genesis tokenIds (1..genesisSupply) owned now
  unclaimedIds: bigint[];     // of those, the ones not yet genesis-claimed
  sharePerFren: bigint;       // GNOME airdrop per MiFren (wei)
  claimableGnome: bigint;     // unclaimed.length * share
  gnomeBalance: bigint;       // wallet's current gen-1 (GNOME) balance
  needsMigrate: boolean;      // true once a relaunch happened (gen1 ≠ current)
  genesisTokenDead: boolean;  // gen-1 token is frozen → claimGenesis reverts on THIS deploy
  currentTicker: string;      // live iteration ticker (migrate target)
  genesisTicker: string;      // gen-1 ticker (usually GNOME)
  error?: string;
}

const EMPTY: GenesisBonusState = {
  loading: false, mifrenCount: 0, ownedGenesis: [], unclaimedIds: [],
  sharePerFren: 0n, claimableGnome: 0n, gnomeBalance: 0n,
  needsMigrate: false, genesisTokenDead: false, currentTicker: "", genesisTicker: "GNOME",
};

/**
 * useGenesisBonus — the OG MiFren token airdrop. Every genesis MiFren can claim a
 * fixed share of iteration #1's token (GNOME) exactly once, keyed PER tokenId
 * (`genesisClaimed[id]`) and gated by live ownership — so the claim right follows
 * the NFT across sales (buy an unclaimed MiFren on OpenSea → you can claim it;
 * an already-claimed one can never be claimed again). If a relaunch has happened,
 * the claimed GNOME is a past-iteration token, so we offer to migrate it 1:1 into
 * the live brew in the same flow.
 */
export function useGenesisBonus() {
  const { address, chainId } = useAccount();
  const publicClient = usePublicClient({ chainId: CAULDRON.chainId });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();

  const [s, setS] = useState<GenesisBonusState>(EMPTY);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);

  const load = useCallback(async () => {
    if (!address || !publicClient) { setS(EMPTY); return; }
    setS((p) => ({ ...p, loading: true, error: undefined }));
    try {
      const reg = { address: CAULDRON.registry, abi: REGISTRY_ABI } as const;
      const [share, curGenBn, currentToken, genesisToken, mifrenBal] = await Promise.all([
        publicClient.readContract({ ...reg, functionName: "genesisSharePerFren" }) as Promise<bigint>,
        publicClient.readContract({ ...reg, functionName: "currentGeneration" }) as Promise<bigint>,
        publicClient.readContract({ ...reg, functionName: "currentToken" }) as Promise<Address>,
        publicClient.readContract({ ...reg, functionName: "generationToken", args: [1n] }) as Promise<Address>,
        publicClient.readContract({ address: CAULDRON.mifrens, abi: MIFRENS_ERC721_ABI, functionName: "balanceOf", args: [address] }) as Promise<bigint>,
      ]);

      const owned = await ownedGenesisIds(publicClient, address);
      // Read genesisClaimed for every owned id via MULTICALL, chunked. A naive
      // 1111-way Promise.all of individual RPC reads gets rate-limited on public
      // nodes, and errored reads defaulting to "unclaimed" made already-claimed
      // frens reappear — so a repeat claim kept hitting the same ids. Multicall is
      // one request per chunk and returns reliable results.
      const claimedFlags = await multicallClaimed(publicClient, reg, owned);
      const unclaimedIds = owned.filter((_, i) => !claimedFlags[i]);

      const needsMigrate = genesisToken !== ZERO && currentToken !== ZERO
        && genesisToken.toLowerCase() !== currentToken.toLowerCase();

      const [currentTicker, genesisTicker, gnomeBalance, genesisAlive] = await Promise.all([
        publicClient.readContract({ address: currentToken, abi: TOKEN_ABI, functionName: "symbol" }).catch(() => "") as Promise<string>,
        genesisToken !== ZERO
          ? publicClient.readContract({ address: genesisToken, abi: TOKEN_ABI, functionName: "symbol" }).catch(() => "GNOME") as Promise<string>
          : Promise.resolve("GNOME"),
        genesisToken !== ZERO
          ? publicClient.readContract({ address: genesisToken, abi: TOKEN_ABI, functionName: "balanceOf", args: [address] }).catch(() => 0n) as Promise<bigint>
          : Promise.resolve(0n),
        genesisToken !== ZERO
          ? publicClient.readContract({ address: genesisToken, abi: TOKEN_ABI, functionName: "isAlive" }).catch(() => true) as Promise<boolean>
          : Promise.resolve(true),
      ]);

      setS({
        loading: false,
        mifrenCount: Number(mifrenBal),
        ownedGenesis: owned,
        unclaimedIds,
        sharePerFren: share,
        claimableGnome: share * BigInt(unclaimedIds.length),
        gnomeBalance,
        needsMigrate,
        genesisTokenDead: !genesisAlive,
        currentTicker,
        genesisTicker,
      });
    } catch (e: unknown) {
      setS((p) => ({ ...p, loading: false, error: (e as Error)?.message ?? "load failed" }));
    }
  }, [address, publicClient]);

  useEffect(() => { load(); }, [load]);

  /** Claim up to CLAIM_BATCH unclaimed genesis MiFrens, then (if a relaunch has
   *  happened) migrate the wallet's whole GNOME balance into the live brew. */
  const claimAndMigrate = useCallback(async () => {
    if (!address) throw new Error("Connect a wallet first");
    if (!publicClient) throw new Error("No RPC client");
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });

    const batch = s.unclaimedIds.slice(0, CLAIM_BATCH);
    setBusy(true);
    try {
      // 1) Claim each owned-but-unclaimed genesis MiFren (per-tokenId, no batch).
      //    After each confirms, OPTIMISTICALLY drop that id from state so the
      //    Unclaimed/Claimable stats tick down live and the next batch never
      //    re-targets an already-claimed fren.
      for (let i = 0; i < batch.length; i++) {
        setProgress({ done: i, total: batch.length });
        const id = batch[i];
        const hash = await writeContractAsync({
          address: CAULDRON.registry, abi: REGISTRY_ABI,
          functionName: "claimGenesis", args: [id],
        });
        await publicClient.waitForTransactionReceipt({ hash, timeout: 90_000 });
        setS((prev) => {
          const unclaimedIds = prev.unclaimedIds.filter((x) => x !== id);
          return { ...prev, unclaimedIds, claimableGnome: prev.sharePerFren * BigInt(unclaimedIds.length) };
        });
      }
      setProgress(null);

      // 2) Migrate the resulting GNOME into the current iteration, 1:1.
      if (s.needsMigrate) {
        const bal = await publicClient.readContract({
          address: await publicClient.readContract({ address: CAULDRON.registry, abi: REGISTRY_ABI, functionName: "generationToken", args: [1n] }) as Address,
          abi: TOKEN_ABI, functionName: "balanceOf", args: [address],
        }) as bigint;
        if (bal > 0n) {
          const hash = await writeContractAsync({
            address: CAULDRON.registry, abi: REGISTRY_ABI,
            functionName: "claimByBurn", args: [1n, bal],
          });
          await publicClient.waitForTransactionReceipt({ hash, timeout: 90_000 });
        }
      }
      await load();
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }, [address, publicClient, chainId, s.unclaimedIds, s.needsMigrate, switchChainAsync, writeContractAsync, load]);

  return { ...s, busy, progress, claimBatch: CLAIM_BATCH, claimAndMigrate, refresh: load };
}
