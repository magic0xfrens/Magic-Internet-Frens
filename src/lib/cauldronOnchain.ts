import { parseAbiItem, type Address, type PublicClient } from "viem";
import { CAULDRON, CAULDRON_INDEXER, REGISTRY_ABI, COLLECTION_ABI } from "@/config/cauldron";

/**
 * On-chain NFT ownership loader — the indexer-independent source of truth.
 *
 * The Ponder indexer can be stale (points at an old round) or down; this reads
 * ownership straight from chain so "your NFTs" always reflect reality. It:
 *   1. enumerates every collection the launchpad has ever minted — the genesis
 *      MiFrens + each iteration's creature collection (generationCollection 1…N),
 *   2. scans Transfer(to=you) logs for each (chunked to respect public-RPC block
 *      caps), then
 *   3. confirms current ownership via ownerOf (drops anything sold/transferred),
 *      reading rarity + revealed where the collection exposes them.
 */

const ZERO = "0x0000000000000000000000000000000000000000";
const TRANSFER = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
);
const ERC721_OWNER = [
  { type: "function", name: "ownerOf", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
] as const;

export interface OnchainNft {
  collection: Address;
  tokenId: number;
  rarity: number;
  revealed: boolean;
  isGenesis: boolean;
  gen: number;
}

/** An NFT row served by the Ponder indexer (adds the liquidatoor flag). */
export interface IndexerNft extends OnchainNft {
  isLiquidatoor: boolean;
}

/**
 * NFTs owned by a wallet — served STRAIGHT from the Ponder indexer, with NO
 * on-chain reads (no getLogs, no fallback). Ownership, rarity, revealed and the
 * liquidatoor flag all come from `/nfts/:owner`; `/collections` supplies the
 * generation + genesis mapping. The caller resolves each token's art from its
 * tokenURI separately.
 *
 * Throws on a missing/unreachable indexer (the callers surface a retry) — this
 * is deliberate: these views are indexer-only by design, so a silent on-chain
 * fallback would defeat the point.
 */
export async function fetchNftsFromIndexer(
  owner: Address,
  opts: { includeGenesis?: boolean } = {},
): Promise<IndexerNft[]> {
  const { includeGenesis = true } = opts;
  // `includeGenesis` is a pure client-side filter, so every caller can share one
  // network round-trip: coalesce the UNFILTERED rows per owner, then filter.
  // The vault mounts the creature grid, the badge grid and the rail's counter
  // together — three identical /collections + /nfts pairs before this.
  const rows = await fetchAllNftsFromIndexer(owner);
  return includeGenesis ? rows : rows.filter((n) => !n.isGenesis);
}

/** In-flight dedupe for the raw (unfiltered) indexer rows, keyed by owner. */
const allNftsInFlight = new Map<string, Promise<IndexerNft[]>>();

function fetchAllNftsFromIndexer(owner: Address): Promise<IndexerNft[]> {
  const key = owner.toLowerCase();
  const pending = allNftsInFlight.get(key);
  if (pending) return pending;
  const req = loadAllNftsFromIndexer(owner).finally(() => allNftsInFlight.delete(key));
  allNftsInFlight.set(key, req);
  return req;
}

async function loadAllNftsFromIndexer(owner: Address): Promise<IndexerNft[]> {
  const base = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : null;
  if (!base) throw new Error("no-indexer");

  // collection → { gen, isGenesis } — one call. The genesis MiFrens (presale)
  // has generation=null; every brew's creature collection carries its gen.
  const colRes = await fetch(`${base}/collections`, { signal: AbortSignal.timeout(8000) });
  if (!colRes.ok) throw new Error("indexer-unreachable");
  const colData = (await colRes.json()) as {
    collections?: { address: string; generation: number | null; isPresale: boolean }[];
  };
  const colMap = new Map<string, { gen: number; isGenesis: boolean }>();
  for (const c of colData.collections ?? []) {
    colMap.set(c.address.toLowerCase(), {
      gen: c.generation ?? 0,
      isGenesis: c.isPresale || c.generation == null,
    });
  }
  // Belt-and-suspenders: the known genesis collection is always genesis even if
  // /collections hasn't caught up yet.
  colMap.set(CAULDRON.mifrens.toLowerCase(), { gen: 0, isGenesis: true });

  const res = await fetch(`${base}/nfts/${owner.toLowerCase()}?limit=2000`, {
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) throw new Error("indexer-unreachable");
  const data = (await res.json()) as {
    nfts?: { collection: string; tokenId: number; rarity: number; revealed: boolean; isLiquidatoor?: boolean }[];
  };

  const rows: IndexerNft[] = (data.nfts ?? [])
    .map((n) => {
      const meta = colMap.get(n.collection.toLowerCase()) ?? { gen: 0, isGenesis: false };
      return {
        collection: n.collection as Address,
        tokenId: n.tokenId,
        rarity: n.rarity,
        revealed: n.revealed,
        isLiquidatoor: Boolean(n.isLiquidatoor),
        isGenesis: meta.isGenesis,
        gen: meta.gen,
      };
    });

  return rows.sort((a, b) => b.gen - a.gen || b.rarity - a.rarity || b.tokenId - a.tokenId);
}

/** Every collection the current launchpad has minted: genesis + each iteration. */
export async function launchpadCollections(pc: PublicClient): Promise<{ address: Address; gen: number; isGenesis: boolean }[]> {
  const reg = { address: CAULDRON.registry, abi: REGISTRY_ABI } as const;
  const out: { address: Address; gen: number; isGenesis: boolean }[] = [
    { address: CAULDRON.mifrens, gen: 0, isGenesis: true },
  ];
  let gen = 0;
  try {
    gen = Number(await pc.readContract({ ...reg, functionName: "currentGeneration" }) as bigint);
  } catch { /* not summoned yet */ }
  const seen = new Set<string>([CAULDRON.mifrens.toLowerCase()]);
  for (let g = 1; g <= gen; g++) {
    try {
      const c = await pc.readContract({ ...reg, functionName: "generationCollection", args: [BigInt(g)] }) as Address;
      if (c && c !== ZERO && !seen.has(c.toLowerCase())) {
        seen.add(c.toLowerCase());
        out.push({ address: c, gen: g, isGenesis: false });
      }
    } catch { /* skip */ }
  }
  return out;
}

/** tokenIds a wallet received in a collection (chunked getLogs, public-RPC safe). */
async function incomingTokenIds(pc: PublicClient, collection: Address, owner: Address, fromBlock: bigint, toBlock: bigint): Promise<bigint[] > {
  const ids = new Set<bigint>();
  const STEP = 9000n; // stay under public-RPC getLogs range caps
  for (let start = fromBlock; start <= toBlock; start += STEP + 1n) {
    const end = start + STEP > toBlock ? toBlock : start + STEP;
    try {
      const logs = await pc.getLogs({
        address: collection,
        event: TRANSFER,
        args: { to: owner },
        fromBlock: start,
        toBlock: end,
      });
      for (const l of logs) {
        const id = (l.args as { tokenId?: bigint }).tokenId;
        if (id != null) ids.add(id);
      }
    } catch { /* skip this window */ }
  }
  return [...ids];
}

/** All NFTs the wallet CURRENTLY owns across the launchpad, on-chain + fast.
 *  `includeGenesis:false` skips the huge genesis collection (the creatures view
 *  doesn't need it, and a whale who minted 1000+ genesis would be slow). Uses
 *  multicall so ownership/rarity for all tokens resolves in one round-trip. */
export async function fetchOwnedNftsOnchain(
  pc: PublicClient,
  owner: Address,
  opts: { includeGenesis?: boolean } = {},
): Promise<OnchainNft[]> {
  const { includeGenesis = true } = opts;
  const all = await launchpadCollections(pc);
  const collections = includeGenesis ? all : all.filter((c) => !c.isGenesis);
  const latest = await pc.getBlockNumber();
  const out: OnchainNft[] = [];

  await Promise.all(collections.map(async ({ address, isGenesis, gen }) => {
    const candidates = await incomingTokenIds(pc, address, owner, CAULDRON.deployBlock, latest);
    if (candidates.length === 0) return;

    // Batch ownerOf + rarity + revealed for every candidate in ONE multicall.
    const owners = await pc.multicall({
      allowFailure: true,
      contracts: candidates.map((id) => ({ address, abi: ERC721_OWNER, functionName: "ownerOf", args: [id] })),
    });
    const mine = candidates.filter((_, i) =>
      owners[i].status === "success" && (owners[i].result as string).toLowerCase() === owner.toLowerCase());
    if (mine.length === 0) return;

    const [rarities, reveals] = await Promise.all([
      pc.multicall({ allowFailure: true, contracts: mine.map((id) => ({ address, abi: COLLECTION_ABI, functionName: "rarityOf", args: [id] })) }),
      pc.multicall({ allowFailure: true, contracts: mine.map((id) => ({ address, abi: COLLECTION_ABI, functionName: "revealed", args: [id] })) }),
    ]);
    mine.forEach((id, i) => {
      out.push({
        collection: address,
        tokenId: Number(id),
        rarity: rarities[i].status === "success" ? Number(rarities[i].result) : 0,
        revealed: reveals[i].status === "success" ? Boolean(reveals[i].result) : true,
        isGenesis, gen,
      });
    });
  }));

  return out.sort((a, b) => b.gen - a.gen || b.rarity - a.rarity || b.tokenId - a.tokenId);
}

/**
 * Owned NFTs, indexer-PREFERRED with an on-chain fallback + freshness guard.
 *
 * Ponder is the fast path (one HTTP call). But a redeployed launchpad reuses
 * gen #1 with DIFFERENT collections, so a stale indexer would return old/empty
 * data. We validate the indexer against the live collection set: we only trust
 * indexer rows whose collection belongs to THIS deploy, and if the indexer
 * yields nothing for the live collections we fall back to the on-chain scan
 * (which is authoritative). `includeGenesis:false` skips the big genesis set.
 */
export async function fetchForgedNfts(
  pc: PublicClient,
  owner: Address,
  opts: { includeGenesis?: boolean } = {},
): Promise<OnchainNft[]> {
  const { includeGenesis = false } = opts;
  const base = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : null;

  if (base) {
    try {
      // Live collections for THIS deploy → the freshness whitelist.
      const live = await launchpadCollections(pc);
      const liveMap = new Map(
        live.filter((c) => includeGenesis || !c.isGenesis).map((c) => [c.address.toLowerCase(), c]),
      );

      const res = await fetch(`${base}/nfts/${owner.toLowerCase()}?limit=2000`, { signal: AbortSignal.timeout(6000) });
      if (res.ok) {
        const data = (await res.json()) as { nfts?: { collection: string; tokenId: number; rarity: number; revealed: boolean }[] };
        const rows = (data.nfts ?? []).flatMap((n) => {
          const c = liveMap.get(n.collection.toLowerCase());
          if (!c) return []; // stale / different-deploy collection → ignore
          return [{ collection: c.address, tokenId: n.tokenId, rarity: n.rarity, revealed: n.revealed, isGenesis: c.isGenesis, gen: c.gen }];
        });
        // Trust the indexer only if it actually returned live rows; an empty
        // result may just mean "not yet synced" → verify on-chain instead.
        if (rows.length > 0) {
          return rows.sort((a, b) => b.gen - a.gen || b.rarity - a.rarity || b.tokenId - a.tokenId);
        }
      }
    } catch { /* indexer down → on-chain below */ }
  }

  // Fallback: authoritative on-chain scan.
  return fetchOwnedNftsOnchain(pc, owner, { includeGenesis });
}
