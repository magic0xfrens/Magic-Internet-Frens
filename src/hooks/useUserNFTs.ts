import { useCallback, useEffect, useState } from "react";
import { usePublicClient } from "wagmi";
import { useWallet } from "./useWallet";
import { CAULDRON } from "@/config/cauldron";
import { fetchOwnedNfts } from "@/lib/cauldronIndexer";
import { ownedGenesisIds } from "./useMiFrensDividend";
import { useAppStore } from "@/store/useAppStore";
import { resolveSprites } from "@/data/traitResolver";
import { frenTraitsForToken } from "@/data/frenAssign";

export interface OwnedNFT {
  tokenId: bigint;
  classIdx: number;
  bodyIdx: number;
  faceIdx: number;
  itemIdx: number;
  bodyFile: string;
  faceFile: string;
  itemFile: string;
  rarity?: number;
  /** On-chain rendered image from tokenURI (data URI or URL) */
  imageUri?: string;
  isPending?: boolean;
  txHash?: string;
}

const traitsForToken = frenTraitsForToken; // collision-free, deterministic per id

/**
 * The wallet's MiFrens (Cauldron `MiFrensGenesis` collection on Sepolia). Owned
 * tokenIds come from the Ponder indexer (`/nfts/:owner`), with a bounded on-chain
 * Transfer-log fallback when the indexer is unavailable. Display traits are
 * derived deterministically from the tokenId.
 */
export function useUserNFTs() {
  const { isConnected, walletAddress } = useWallet();
  const publicClient = usePublicClient({ chainId: CAULDRON.chainId });
  const pendingMints = useAppStore((s) => s.pendingMints);
  const removePendingMintByTokenId = useAppStore((s) => s.removePendingMintByTokenId);
  const clearStalePendingMints = useAppStore((s) => s.clearStalePendingMints);

  const [nfts, setNfts] = useState<OwnedNFT[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchNFTs = useCallback(async () => {
    if (!walletAddress || !isConnected) {
      setNfts([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const owner = walletAddress as `0x${string}`;
      const mifrens = CAULDRON.mifrens.toLowerCase();

      // 1) Indexer: every owned NFT, filtered to the genesis MiFrens collection.
      const indexed = await fetchOwnedNfts(owner);
      let rows: { tokenId: number; rarity?: number }[] = [];
      if (indexed !== null) {
        rows = indexed
          .filter((n) => n.collection.toLowerCase() === mifrens)
          .map((n) => ({ tokenId: n.tokenId, rarity: n.rarity }));
      } else if (publicClient) {
        // 2) Fallback: bounded on-chain Transfer scan (genesis ids only).
        const ids = await ownedGenesisIds(publicClient, owner);
        rows = ids.map((id) => ({ tokenId: Number(id) }));
      }

      const owned: OwnedNFT[] = rows
        .sort((a, b) => a.tokenId - b.tokenId)
        .map((r) => {
          const tid = BigInt(r.tokenId);
          const t = traitsForToken(tid);
          const sprites = resolveSprites(t.classIdx, t.bodyIdx, t.faceIdx, t.itemIdx);
          return {
            tokenId: tid, ...t,
            bodyFile: sprites.bodyFile, faceFile: sprites.faceFile, itemFile: sprites.itemFile,
            rarity: r.rarity,
          };
        });

      // Reconcile pending mints now confirmed on-chain.
      const confirmed = new Set(owned.map((n) => n.tokenId.toString()));
      for (const pm of pendingMints) if (confirmed.has(pm.tokenId)) removePendingMintByTokenId(pm.tokenId);
      clearStalePendingMints();

      setNfts(owned);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error("Failed to fetch user MiFrens:", msg);
      setError(msg);
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [walletAddress, isConnected, publicClient]);

  useEffect(() => { fetchNFTs(); }, [fetchNFTs]);

  // Merge unconfirmed pending mints into the output.
  const confirmedIds = new Set(nfts.map((n) => n.tokenId.toString()));
  const pendingNfts: OwnedNFT[] = pendingMints
    .filter((pm) => !confirmedIds.has(pm.tokenId))
    .map((pm) => {
      const t = traitsForToken(BigInt(pm.tokenId));
      const sprites = resolveSprites(t.classIdx, t.bodyIdx, t.faceIdx, t.itemIdx);
      return {
        tokenId: BigInt(pm.tokenId), ...t,
        bodyFile: sprites.bodyFile, faceFile: sprites.faceFile, itemFile: sprites.itemFile,
        isPending: true, txHash: pm.txHash,
      };
    });

  const allNfts = [...pendingNfts, ...nfts];

  return {
    nfts: allNfts,
    loading,
    error,
    refresh: fetchNFTs,
    count: nfts.length,
    pendingCount: pendingNfts.length,
  };
}
