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
import { fetchBrewIdentity, fetchCollectionBalance, fetchGenesisFloor } from "@/lib/cauldronIndexer";

const ZERO = "0x0000000000000000000000000000000000000000" as Address;

/** How many genesis MiFrens we'll redeem per click. `redeemFrensMany` burns them
 *  all in ONE reserve removal, so a whole wallet clears in a single tx — but we
 *  still cap the array size so the calldata/gas stays modest and the wallet popup
 *  is snappy. A holder of many frens just repeats for the rest. */
const CLAIM_BATCH = 30;

export interface GenesisBonusState {
  loading: boolean;
  mifrenCount: number;        // total MiFrens the wallet holds (balanceOf)
  ownedGenesis: bigint[];     // genesis tokenIds (1..genesisSupply) owned now
  unclaimedIds: bigint[];     // REDEEMABLE ids — every owned genesis fren (burning is the guard)
  sharePerFren: bigint;       // live-token you receive per burned fren (wei)
  claimableGnome: bigint;     // total redeemable current-token = ownedGenesis * share
  gnomeBalance: bigint;       // wallet's current (live) token balance
  needsMigrate: boolean;      // always false — redeem pays the LIVE token directly
  genesisTokenDead: boolean;  // unused in the redemption model (kept for compat)
  currentTicker: string;      // live iteration ticker (what a redeem pays out)
  genesisTicker: string;      // alias of currentTicker (redeem → current token)
  /** Where `sharePerFren` came from. "none" = NOBODY could answer, so the figure
   *  below is not a floor of 0 — it is a floor we do not know. Panels must say
   *  so rather than print "0". */
  floorSource: "indexer" | "chain" | "none";
  error?: string;
}

const EMPTY: GenesisBonusState = {
  loading: false, mifrenCount: 0, ownedGenesis: [], unclaimedIds: [],
  sharePerFren: 0n, claimableGnome: 0n, gnomeBalance: 0n,
  needsMigrate: false, genesisTokenDead: false, currentTicker: "", genesisTicker: "",
  floorSource: "none",
};

/**
 * useGenesisBonus — the GENESIS REDEMPTION FLOOR (round-26+). A genesis MiFren is
 * a perpetual redemption ticket for the eternal machine: BURN it to receive
 * `genesisSharePerFren` of WHATEVER token is live right now (GNOME today, the next
 * summon tomorrow), released from the out-of-range reserve. This ties the genesis
 * NFT floor to the live iteration's marketcap (floor = share × current price) and
 * is non-dilutive — the tokens were never circulating and the NFT is destroyed.
 *
 * Unlike the old one-time airdrop, there is no `genesisClaimed` flag: EVERY owned
 * genesis fren is redeemable, and redeeming pays the CURRENT token directly (no
 * separate migrate step). Redemption is one-way — you give up the fren's vote,
 * dividend, and art for the token.
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

      //  ── INDEXER FIRST, CHAIN AS THE FLOOR UNDER IT ────────────────────────
      //  The floor, the live token and its ticker are DISPLAY facts: redeeming
      //  calls `redeemOgFren(tokenId)`, which carries no amount and no minimum,
      //  so nothing here can shape a transaction the user signs. The indexer's
      //  /floor is itself a server-side chain read cached 4s (not an event
      //  rollup), and the floor only ratchets UP — so the worst a stale answer
      //  can do is under-state what a redemption pays.
      //
      //  Both are tried in ONE round-trip. If EITHER cannot answer we fall back
      //  to the chain for that part specifically, and `floorSource` records
      //  which source won so the panel can say "floor unavailable" instead of
      //  printing a confident zero.
      const [idxFloor, brew] = await Promise.all([fetchGenesisFloor(), fetchBrewIdentity()]);

      let floorSource: GenesisBonusState["floorSource"] = "indexer";
      let share = idxFloor?.floorPerFrenWei ?? null;
      let currentToken: Address | null = brew?.token ?? null;
      let currentTicker = brew?.ticker ?? "";

      if (share === null) {
        floorSource = "chain";
        share = await (publicClient.readContract({ ...reg, functionName: "floorPerFren" })
          .catch(() => null) as Promise<bigint | null>);
        if (share === null) floorSource = "none";
      }
      if (currentToken === null) {
        currentToken = await (publicClient.readContract({ ...reg, functionName: "currentToken" })
          .catch(() => null) as Promise<Address | null>);
      }
      const liveToken = currentToken && currentToken !== ZERO ? currentToken : null;
      if (!currentTicker && liveToken) {
        currentTicker = await (publicClient.readContract({ address: liveToken, abi: TOKEN_ABI, functionName: "symbol" })
          .catch(() => "") as Promise<string>);
      }

      // In the redemption model EVERY owned genesis fren is redeemable (the burn is
      // the double-spend guard), so there is no per-id claimed lookup to do.
      const owned = await ownedGenesisIds(publicClient, address);

      //  HOW MANY FRENS ARE HELD — from the indexer's ownership table, which is
      //  the same request `ownedGenesisIds` just made (deduped in flight, so this
      //  costs nothing). `null` means the indexer could not answer, and ONLY then
      //  do we spend an RPC read on balanceOf: a 0 from a down indexer would hide
      //  the whole panel, which is the exact bug this codebase already shipped
      //  once as "0 sealed" on a wallet holding four crystals.
      let mifrenCount = await fetchCollectionBalance(address, CAULDRON.mifrens);
      if (mifrenCount === null) {
        const bal = await (publicClient.readContract({
          address: CAULDRON.mifrens, abi: MIFRENS_ERC721_ABI, functionName: "balanceOf", args: [address],
        }).catch(() => null) as Promise<bigint | null>);
        mifrenCount = bal === null ? owned.length : Number(bal);
      }

      //  The wallet's ERC20 balance of the live token. NOT INDEXED — there is no
      //  token-balance table in ponder.schema.ts — so this stays a chain read.
      const tokenBalance = liveToken
        ? await (publicClient.readContract({ address: liveToken, abi: TOKEN_ABI, functionName: "balanceOf", args: [address] })
            .catch(() => 0n) as Promise<bigint>)
        : 0n;

      setS({
        loading: false,
        mifrenCount,
        ownedGenesis: owned,
        unclaimedIds: owned,                 // all owned genesis frens are redeemable
        sharePerFren: share ?? 0n,
        claimableGnome: (share ?? 0n) * BigInt(owned.length),
        gnomeBalance: tokenBalance,
        needsMigrate: false,
        genesisTokenDead: false,
        currentTicker,
        genesisTicker: currentTicker,        // redeem pays the CURRENT token
        floorSource,
      });
    } catch (e: unknown) {
      setS((p) => ({ ...p, loading: false, error: (e as Error)?.message ?? "load failed" }));
    }
  }, [address, publicClient]);

  useEffect(() => { load(); }, [load]);

  /** RECYCLE up to CLAIM_BATCH genesis MiFrens: each `redeemFren` pays the LIVE
   *  floor of the current token from the reserve and moves the NFT to the TREASURY
   *  (not burned) to be resold at 2× floor. The fren stops earning the instant it
   *  moves. Loops single redeems (no batch fn) with optimistic per-tx updates.
   *  Kept named `claimAndMigrate` so the existing panels keep working. */
  const claimAndMigrate = useCallback(async () => {
    if (!address) throw new Error("Connect a wallet first");
    if (!publicClient) throw new Error("No RPC client");
    if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });

    const batch = s.unclaimedIds.slice(0, CLAIM_BATCH);
    if (batch.length === 0) return;
    setBusy(true);
    try {
      for (let i = 0; i < batch.length; i++) {
        setProgress({ done: i, total: batch.length });
        const id = batch[i];
        const hash = await writeContractAsync({
          address: CAULDRON.registry, abi: REGISTRY_ABI,
          functionName: "redeemOgFren", args: [id],
        });
        await publicClient.waitForTransactionReceipt({ hash, timeout: 120_000 });
        // The fren recycled to the treasury — drop it from state so the next tx
        // never re-targets it and the stats tick down live.
        setS((prev) => {
          const remaining = prev.unclaimedIds.filter((x) => x !== id);
          return {
            ...prev,
            ownedGenesis: prev.ownedGenesis.filter((x) => x !== id),
            unclaimedIds: remaining,
            mifrenCount: Math.max(0, prev.mifrenCount - 1),
            claimableGnome: prev.sharePerFren * BigInt(remaining.length),
          };
        });
      }
      setProgress(null);
      await load();
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }, [address, publicClient, chainId, s.unclaimedIds, switchChainAsync, writeContractAsync, load]);

  return { ...s, busy, progress, claimBatch: CLAIM_BATCH, claimAndMigrate, redeem: claimAndMigrate, refresh: load };
}
