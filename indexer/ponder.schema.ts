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
  // strict EXECUTION order = block*1e6 + logIndex. Several swaps can share ONE
  // block (a liquidation fires multiple buy-backs atomically); ordering by
  // timestamp alone scrambles them → the tick chart's candle close comes out
  // wrong (looks like a red/sell move that never happened). Sort by this.
  orderKey: t.bigint().notNull(),
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
  // Liquidatoor badge (OnChain Collectible) vs regular art. Badge ids live in the
  // LIQUIDATOR_ID_BASE range; set true by the LiquidatoorMinted handler.
  isLiquidatoor: t.boolean().notNull().default(false),
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

/* ── perps: positions + liquidation heatmap source ─────────────────────── */
// One row per opened position. liqPrice is computed at open from the event args
// (entryPrice = notionalEth/size; liq level from leverage + maintenance margin),
// so the heatmap API can bucket OPEN positions by their liquidation price without
// any extra RPC reads. status flips to closed|liquidated on the matching event.
export const perpPosition = onchainTable("perp_position", (t) => ({
  id: t.text().primaryKey(),                 // `${generation}-${positionId}`
  positionId: t.bigint().notNull(),
  generation: t.integer().notNull(),
  poolId: t.hex(),
  trader: t.hex().notNull(),
  isLong: t.boolean().notNull(),
  leverage: t.integer().notNull(),
  collateralEth: t.doublePrecision().notNull(),  // ETH stake (net of fee)
  notionalEth: t.doublePrecision().notNull(),     // collateral × leverage (heatmap weight)
  entryPrice: t.doublePrecision().notNull(),      // ETH per token at open
  liqPrice: t.doublePrecision().notNull(),        // ETH per token liquidation level
  status: t.text().notNull().default("open"),     // open | closed | liquidated
  pnlEth: t.doublePrecision(),                     // realized on close
  liquidatedBy: t.hex(),                           // the fren who rekt it (Liquidatoor)
  badgeId: t.bigint(),                             // Liquidatoor badge minted (0/none)
  openedAt: t.bigint().notNull(),
  closedAt: t.bigint(),
  openTx: t.hex(),
}), (table) => ({
  genIdx: index().on(table.generation),
  statusIdx: index().on(table.status),
  traderIdx: index().on(table.trader),
}));

/// Liquidatoor leaderboard: per-address kill count + badges earned. Powers the
/// gamification (who's rekt the most frens).
export const liquidator = onchainTable("liquidator", (t) => ({
  id: t.hex().primaryKey(),                        // address
  kills: t.integer().notNull().default(0),         // positions liquidated
  badges: t.integer().notNull().default(0),        // Liquidatoor badges minted to them
  lastAt: t.bigint(),
}), (table) => ({
  killsIdx: index().on(table.kills),
}));

// Singleton per generation: live open interest + lifetime perp activity.
export const perpStat = onchainTable("perp_stat", (t) => ({
  id: t.integer().primaryKey(),              // generation
  longOiEth: t.doublePrecision().notNull().default(0),
  shortOiEth: t.doublePrecision().notNull().default(0),
  openPositions: t.integer().notNull().default(0),
  totalOpened: t.integer().notNull().default(0),
  totalLiquidated: t.integer().notNull().default(0),
  updatedAt: t.bigint().notNull(),
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

/* ── r30: redemption floor (genesis recycle-ratchet) ───────────────────────
 * Live state per generation: the reserve backing the floor + the current
 * floor-per-fren, kept in sync from FloorGrew / FrenRedeemed / FrenBought. */
export const genesisFloor = onchainTable("genesis_floor", (t) => ({
  id: t.integer().primaryKey(),                    // generation
  reserveOutstanding: t.bigint().notNull().default(0n), // reserve backing the floor
  floorPerFren: t.bigint().notNull().default(0n),  // latest floor-per-fren (from FloorGrew)
  redeemedCount: t.integer().notNull().default(0), // frens recycled for floor
  boughtCount: t.integer().notNull().default(0),   // treasury frens bought at 2x
  totalRedeemed: t.bigint().notNull().default(0n), // tokens paid out on redemptions
  totalGrown: t.bigint().notNull().default(0n),    // tokens added to the reserve (ratchet)
  updatedAt: t.bigint().notNull().default(0n),
}));

/* Append-only log of every floor action (redeem / buy-2x / grow) for history. */
export const floorEvent = onchainTable("floor_event", (t) => ({
  id: t.text().primaryKey(),                       // txHash-logIndex
  kind: t.text().notNull(),                        // "redeem" | "buy" | "grow"
  generation: t.integer().notNull(),
  tokenId: t.bigint(),                             // the fren (null for "grow")
  actor: t.hex(),                                  // holder / buyer
  amount: t.bigint().notNull().default(0n),        // paid out / paid in / added
  floorAfter: t.bigint(),                          // floor-per-fren after (grow only)
  ts: t.bigint().notNull(),
  block: t.bigint().notNull(),
}), (table) => ({ genIdx: index().on(table.generation), kindIdx: index().on(table.kind) }));

/* ── r30: per-collection LEGACY floor (recycle / buy-2x) ────────────────────
 * Every volume collection keeps the value its own fees accrued, forever, as a
 * token entitlement. Live state + an append-only log, keyed by generation. */
export const collectionFloor = onchainTable("collection_floor", (t) => ({
  id: t.integer().primaryKey(),                    // generation
  recycledCount: t.integer().notNull().default(0),
  boughtCount: t.integer().notNull().default(0),
  totalPaidOut: t.bigint().notNull().default(0n),  // floor paid on recycles
  totalPaidIn: t.bigint().notNull().default(0n),   // 2x buybacks (grows the floor)
  updatedAt: t.bigint().notNull().default(0n),
}));

export const collectionFloorEvent = onchainTable("collection_floor_event", (t) => ({
  id: t.text().primaryKey(),                       // txHash-logIndex
  kind: t.text().notNull(),                        // "recycle" | "buy"
  generation: t.integer().notNull(),
  tokenId: t.bigint().notNull(),
  actor: t.hex().notNull(),
  amount: t.bigint().notNull().default(0n),
  ts: t.bigint().notNull(),
  block: t.bigint().notNull(),
}), (table) => ({ genIdx: index().on(table.generation) }));

/* ── r30: proposer flywheel — fee earned by each iteration's proposer ─────── */
export const proposerEarning = onchainTable("proposer_earning", (t) => ({
  id: t.hex().primaryKey(),                        // proposer address
  totalEarned: t.bigint().notNull().default(0n),   // cumulative accrued (pull-pattern)
  payoutCount: t.integer().notNull().default(0),
  updatedAt: t.bigint().notNull().default(0n),
}));
