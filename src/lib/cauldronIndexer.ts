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

/**
 * One GET, deduped while in flight, `null` on anything that is not a 2xx JSON
 * body. Every helper below is built on this so they all fail the same way — the
 * callers are written against "null means I do not know", and a helper that
 * quietly substituted a zero would break that contract for all of them.
 */
const inFlight = new Map<string, Promise<unknown>>();
function get<T>(path: string, timeoutMs = 6000): Promise<T | null> {
  const base = indexerBase();
  if (!base) return Promise.resolve(null);
  const url = `${base}${path}`;
  const pending = inFlight.get(url) as Promise<T | null> | undefined;
  if (pending) return pending;
  const req = (async (): Promise<T | null> => {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
      if (!res.ok) return null;
      return (await res.json()) as T;
    } catch {
      return null;
    }
  })().finally(() => inFlight.delete(url));
  inFlight.set(url, req);
  return req;
}

/** How far behind the chain's clock the indexer's head is, in seconds, from
 *  `/status`. Null when the indexer cannot be reached at all. Callers surface
 *  this rather than silently showing an old number as if it were current. */
export async function fetchIndexerLagSec(): Promise<number | null> {
  const d = await get<{ cauldron?: { block?: { timestamp?: number } } }>("/status", 5000);
  const ts = d?.cauldron?.block?.timestamp;
  if (!ts) return null;
  return Math.max(0, Math.floor(Date.now() / 1000) - ts);
}

/** The GENESIS REDEMPTION FLOOR, from `/floor`.
 *
 *  Served by a SERVER-SIDE CHAIN READ cached for 4s — not from the event tables —
 *  so it is not subject to indexing lag, and the floor only ever ratchets up, so
 *  a stale answer under-states what a redemption pays rather than over-stating
 *  it. Returns null when the endpoint is unreachable OR when it reports that its
 *  own `floorPerFren` read failed, because a failed read there arrives as 0. */
export interface IndexedFloor {
  floorPerFrenWei: bigint;
  floorPerFren: number;
  enchantFeeWei: bigint;
  reserveTokens: number;
  markPriceEth: number | null;
  redeemFloorEth: number | null;
}
export async function fetchGenesisFloor(): Promise<IndexedFloor | null> {
  const d = await get<{
    floorPerFrenWei?: string; floorPerFren?: number; enchantFeeWei?: string;
    reserveTokens?: number; markPriceEth?: number | null; redeemFloorEth?: number | null;
    failedReads?: string[];
  }>("/floor", 8000);
  // No wei field → an older indexer that cannot answer precisely. Treat as
  // unavailable so the caller uses the chain instead of a rounded float.
  if (!d || d.floorPerFrenWei == null) return null;
  if (d.failedReads?.includes("floorPerFren")) return null;
  try {
    return {
      floorPerFrenWei: BigInt(d.floorPerFrenWei),
      floorPerFren: d.floorPerFren ?? 0,
      enchantFeeWei: BigInt(d.enchantFeeWei ?? "0"),
      reserveTokens: d.reserveTokens ?? 0,
      markPriceEth: d.markPriceEth ?? null,
      redeemFloorEth: d.redeemFloorEth ?? null,
    };
  } catch {
    return null;
  }
}

/** Identity of the live brew (generation, token, ticker) from `/cauldron`. Null
 *  when unavailable, or when nothing has been summoned yet — a caller cannot
 *  tell those apart from a zeroed struct, so it gets neither. */
export interface BrewIdentity {
  gen: number;
  token: Address | null;
  ticker: string;
  dead: boolean;
}
export async function fetchBrewIdentity(): Promise<BrewIdentity | null> {
  const d = await get<{ summoned?: boolean; gen?: number; token?: string; ticker?: string; dead?: boolean }>(
    "/cauldron",
    8000,
  );
  if (!d || !d.summoned) return null;
  return {
    gen: d.gen ?? 0,
    token: (d.token as Address) ?? null,
    ticker: d.ticker ?? "",
    dead: !!d.dead,
  };
}

/** A wallet's lifetime gacha record from `/gacha/:player`.
 *
 *  `misses` is the LIFETIME miss count, which is NOT the hook's `missStreak`
 *  (that resets on every win) — they were 12 and 0 for the same wallet when this
 *  was written. The pity counter therefore stays an on-chain read; only the
 *  lifetime tallies come from here. */
export interface IndexedGacha {
  wins: number;
  misses: number;
  committed: number;
}
export function fetchGachaStats(player: Address): Promise<IndexedGacha | null> {
  return get<IndexedGacha>(`/gacha/${player.toLowerCase()}`, 6000);
}

/** How many tokens of one collection a wallet holds, per the indexer. Null when
 *  the indexer cannot answer — NEVER 0, which is a different claim. */
export async function fetchCollectionBalance(
  owner: Address,
  collection: Address,
): Promise<number | null> {
  const nfts = await fetchOwnedNfts(owner);
  if (nfts === null) return null;
  const col = collection.toLowerCase();
  return nfts.filter((n) => n.collection.toLowerCase() === col).length;
}

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
