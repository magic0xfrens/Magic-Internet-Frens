import { onchainTable, index } from "ponder";

/* ── price / volume (charting) ─────────────────────────────────────────── */
export const pool = onchainTable("pool", (t) => ({
  id: t.hex().primaryKey(), // poolId
  generation: t.integer().notNull(),
  token: t.hex().notNull(),
  name: t.text().notNull(),
  symbol: t.text().notNull(),
  createdAt: t.bigint().notNull(),
  createdBlock: t.bigint().notNull(),
  dead: t.boolean().notNull().default(false),
  lastPrice: t.doublePrecision().notNull().default(0),
  swapCount: t.integer().notNull().default(0),
  volumeEth: t.doublePrecision().notNull().default(0),
  updatedAt: t.bigint().notNull(),
}), (table) => ({ genIdx: index().on(table.generation) }));

export const candle = onchainTable("candle", (t) => ({
  id: t.text().primaryKey(),
  poolId: t.hex().notNull(),
  generation: t.integer().notNull(),
  bucketStart: t.integer().notNull(),
  open: t.doublePrecision().notNull(),
  high: t.doublePrecision().notNull(),
  low: t.doublePrecision().notNull(),
  close: t.doublePrecision().notNull(),
  volumeEth: t.doublePrecision().notNull().default(0),
  swapCount: t.integer().notNull().default(0),
}), (table) => ({ bucketIdx: index().on(table.poolId, table.bucketStart) }));

export const swap = onchainTable("swap", (t) => ({
  id: t.text().primaryKey(),
  poolId: t.hex().notNull(),
  generation: t.integer().notNull(),
  sender: t.hex().notNull(),
  price: t.doublePrecision().notNull(),
  amountEth: t.doublePrecision().notNull(),
  isBuy: t.boolean().notNull(),
  timestamp: t.bigint().notNull(),
  block: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}), (table) => ({ poolIdx: index().on(table.poolId) }));

/* ── collections + NFTs + holders ──────────────────────────────────────── */
export const collection = onchainTable("collection", (t) => ({
  id: t.hex().primaryKey(), // collection address
  generation: t.integer(),  // null for the genesis MiFrens before iter#2
  name: t.text(),
  symbol: t.text(),
  totalMinted: t.integer().notNull().default(0),
  isPresale: t.boolean().notNull().default(false),
  createdAt: t.bigint(),
}));

export const nft = onchainTable("nft", (t) => ({
  id: t.text().primaryKey(), // `${collection}-${tokenId}`
  collection: t.hex().notNull(),
  tokenId: t.integer().notNull(),
  owner: t.hex().notNull(),
  rarity: t.integer().notNull().default(0),
  revealed: t.boolean().notNull().default(false),
  mintedAt: t.bigint(),
  mintTx: t.hex(),
}), (table) => ({
  ownerIdx: index().on(table.owner),
  colIdx: index().on(table.collection),
}));

export const holder = onchainTable("holder", (t) => ({
  id: t.text().primaryKey(), // `${collection}-${address}`
  collection: t.hex().notNull(),
  address: t.hex().notNull(),
  balance: t.integer().notNull().default(0),
}), (table) => ({ addrIdx: index().on(table.address) }));

/* ── gacha player stats ────────────────────────────────────────────────── */
export const gachaPlayer = onchainTable("gacha_player", (t) => ({
  id: t.hex().primaryKey(), // player address
  wins: t.integer().notNull().default(0),      // creatures won (opened)
  misses: t.integer().notNull().default(0),
  committed: t.integer().notNull().default(0), // crystals opened (tickets)
  updatedAt: t.bigint().notNull(),
}));

/* ── governance ────────────────────────────────────────────────────────── */
export const proposal = onchainTable("proposal", (t) => ({
  id: t.integer().primaryKey(), // proposalId
  name: t.text().notNull(),
  symbol: t.text().notNull(),
  proposer: t.hex().notNull(),
  votes: t.bigint().notNull().default(0n),
  consumed: t.boolean().notNull().default(false),
  createdAt: t.bigint().notNull(),
}));

export const vote = onchainTable("vote", (t) => ({
  id: t.text().primaryKey(), // `${proposalId}-${voter}`
  proposalId: t.integer().notNull(),
  voter: t.hex().notNull(),
  weight: t.bigint().notNull(),
}), (table) => ({ propIdx: index().on(table.proposalId) }));

/* ── dividend: "cast the spell" enchant + fee totals ───────────────────── */
// Per genesis tokenId (1..1111): whether its owner has cast the spell.
export const enchant = onchainTable("enchant", (t) => ({
  id: t.integer().primaryKey(),        // tokenId
  fren: t.hex(),                       // who cast it (enchantedBy)
  active: t.boolean().notNull().default(false),
  updatedAt: t.bigint(),
}), (table) => ({ frenIdx: index().on(table.fren) }));

// Singleton (id="dividend"): lifetime fee flows.
export const dividendStat = onchainTable("dividend_stat", (t) => ({
  id: t.text().primaryKey(),
  totalDeposited: t.bigint().notNull().default(0n),
  totalClaimed: t.bigint().notNull().default(0n),
  treasuryFunded: t.bigint().notNull().default(0n), // fees swept out when nobody cast
}));

/* ── per-iteration migration + burn (deflation) ────────────────────────── */
export const iteration = onchainTable("iteration", (t) => ({
  id: t.integer().primaryKey(),        // generation
  token: t.hex(),
  symbol: t.text(),
  migratedOut: t.bigint().notNull().default(0n), // tokens migrated FROM this gen
  burned: t.bigint().notNull().default(0n),      // unclaimed pool burned (burnUnclaimed)
  createdAt: t.bigint(),
}));
