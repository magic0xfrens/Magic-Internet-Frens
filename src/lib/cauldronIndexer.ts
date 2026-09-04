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

/**
 * In-flight request dedupe. Several independent consumers ask for the same
 * wallet's NFTs on the same render pass — the vault grid, the dividend panel
 * and the rail's profile card all mount together — and each would otherwise
 * fire its own copy of this request. Keyed by owner, cleared as soon as the
 * request settles, so this is a coalescer and not a cache: the next mount
 * still gets fresh data.
 */
const ownedNftsInFlight = new Map<string, Promise<IndexedNft[] | null>>();

/** All NFTs a wallet owns, across every Cauldron collection. */
export function fetchOwnedNfts(owner: Address): Promise<IndexedNft[] | null> {
  const key = owner.toLowerCase();
  const pending = ownedNftsInFlight.get(key);
  if (pending) return pending;

  const req = (async (): Promise<IndexedNft[] | null> => {
    const base = indexerBase();
    if (!base) return null;
    try {
      const res = await fetch(`${base}/nfts/${key}?limit=2000`, {
        signal: AbortSignal.timeout(6000),
      });
      if (!res.ok) return null;
      const data = (await res.json()) as { nfts?: IndexedNft[] };
      return data.nfts ?? [];
    } catch {
      return null;
    }
  })().finally(() => ownedNftsInFlight.delete(key));

  ownedNftsInFlight.set(key, req);
  return req;
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
