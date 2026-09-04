import type { Address } from "viem";
import { CAULDRON, CAULDRON_INDEXER } from "@/config/cauldron";

/**
 * Thin client for the Cauldron Ponder indexer. The indexer is the source of
 * truth for anything that would otherwise need a wide `eth_getLogs` scan
 * (ownership, collections, gacha, governance) — public RPCs cap getLogs at
 * ~1000 blocks/response, so reconstructing state client-side doesn't scale.
 *
 * Every helper returns `null` when the indexer is unset or unreachable, so
 * callers can fall back to a bounded on-chain read.
 */
export function indexerBase(): string | null {
  return CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : null;
}

export interface IndexedNft {
  collection: string;
  tokenId: number;
  rarity: number;
  revealed: boolean;
}

/** All NFTs a wallet owns, across every Cauldron collection. */
export async function fetchOwnedNfts(owner: Address): Promise<IndexedNft[] | null> {
  const base = indexerBase();
  if (!base) return null;
  try {
    const res = await fetch(`${base}/nfts/${owner.toLowerCase()}?limit=2000`, {
      signal: AbortSignal.timeout(6000),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { nfts?: IndexedNft[] };
    return data.nfts ?? [];
  } catch {
    return null;
  }
}

/**
 * Genesis MiFren tokenIds (1..genesisSupply) the wallet currently owns — the
 * only tokens that earn the dividend. Returns null when the indexer is
 * unavailable so the caller can fall back to on-chain logs.
 */
export async function fetchOwnedGenesis(owner: Address): Promise<bigint[] | null> {
  const nfts = await fetchOwnedNfts(owner);
  if (nfts === null) return null;
  const mifrens = CAULDRON.mifrens.toLowerCase();
  return nfts
    .filter(
      (n) =>
        n.collection.toLowerCase() === mifrens &&
        n.tokenId >= 1 &&
        n.tokenId <= CAULDRON.genesisSupply,
    )
    .map((n) => BigInt(n.tokenId))
    .sort((a, b) => Number(a - b));
}

/** The genesis MiFren tokenIds a wallet has ENCHANTED (cast the spell) — i.e. the
 *  only frens currently drawing fees. From the indexer's `/enchants/:owner`.
 *  Returns null when the indexer is unavailable. */
export async function fetchEnchanted(owner: Address): Promise<bigint[] | null> {
  const base = indexerBase();
  if (!base) return null;
  try {
    const res = await fetch(`${base}/enchants/${owner.toLowerCase()}`, {
      signal: AbortSignal.timeout(6000),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { tokenIds?: number[] };
    return (data.tokenIds ?? []).map((n) => BigInt(n)).sort((a, b) => Number(a - b));
  } catch {
    return null;
  }
}
