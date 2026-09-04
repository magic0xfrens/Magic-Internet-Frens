import { ponder } from "ponder:registry";
import { pool, candle, swap, collection, nft, holder, gachaPlayer, proposal, vote, enchant, dividendStat, iteration, perpPosition, perpStat, liquidator, genesisFloor, floorEvent, collectionFloor, collectionFloorEvent, proposerEarning } from "ponder:schema";
import { RegistryGenReadAbi } from "../abis/PerpEngineAbi";
import round from "../deployments/round.json";

const CANDLE_SECONDS = Number(process.env.CANDLE_SECONDS ?? 30);
const Q96 = 2 ** 96;
const ZERO = "0x0000000000000000000000000000000000000000";
// FROM THE MANIFEST, NOT env and NOT hardcoded.
//
// These were previously literals with a "bump per round" comment. The reason for
// avoiding env was right — a stale Railway/`.env` REGISTRY_ADDRESS silently
// overrides and pins the indexer to a dead round, which is what once served r29
// data as r31 — but hardcoding traded that for a manual step, and a manual step
// eventually gets missed. `ponder.config.ts` already reads the same manifest, so
// the two halves of the indexer could disagree with each other.
//
// `deployments/round.json` lives INSIDE `indexer/` precisely so `railway up`
// ships it, so importing it has none of the env-drift problem and removes the
// per-round edit entirely.
const PRESALE = round.contracts.presale as `0x${string}`;
const REGISTRY_ADDR = round.contracts.registry as `0x${string}`;
// Maintenance-margin fraction — mirrors PerpEngine.maintenanceBps (1500 = 15%).
// Override with PERP_MAINTENANCE_BPS if the deployer retunes it.
const PERP_M = Number(process.env.PERP_MAINTENANCE_BPS ?? 1500) / 1e4;

function ethPerToken(sqrtPriceX96: bigint): number {
  const s = Number(sqrtPriceX96) / Q96;
  const tokenPerEth = s * s;
  return tokenPerEth > 0 ? 1 / tokenPerEth : 0;
}
const lc = (a: string) => a.toLowerCase() as `0x${string}`;
const nftId = (col: string, id: bigint) => `${lc(col)}-${id}`;
const holderId = (col: string, addr: string) => `${lc(col)}-${lc(addr)}`;

/* ── registry: pools + collections ─────────────────────────────────────── */
async function registerPool(ctx: any, poolId: `0x${string}`, gen: number, token: `0x${string}`, name: string, symbol: string, ts: bigint, block: bigint) {
  const clean = name.replace(/\s*by Magic Internet Frens\s*$/i, "").trim();
  await ctx.db.insert(pool).values({
    id: poolId, generation: gen, token: lc(token), name: clean, symbol,
    createdAt: ts, createdBlock: block, dead: false, lastPrice: 0, swapCount: 0, volumeEth: 0, updatedAt: ts,
  }).onConflictDoNothing();
  await ctx.db.insert(iteration).values({ id: gen, token: lc(token), symbol, createdAt: ts })
    .onConflictDoUpdate(() => ({ token: lc(token), symbol }));
}
ponder.on("CauldronRegistry:CauldronSummoned", async ({ event, context }) => {
  await registerPool(context, event.args.poolId as `0x${string}`, Number(event.args.generation), event.args.token as `0x${string}`, event.args.name, event.args.symbol, event.block.timestamp, event.block.number);
});
ponder.on("CauldronRegistry:CauldronReborn", async ({ event, context }) => {
  await registerPool(context, event.args.poolId as `0x${string}`, Number(event.args.generation), event.args.token as `0x${string}`, event.args.name, event.args.symbol, event.block.timestamp, event.block.number);
});
ponder.on("CauldronRegistry:CauldronDied", async () => { /* death flag is read live; history is the point */ });

ponder.on("RegistryColl:CollectionDeployed", async ({ event, context }) => {
  const addr = lc(event.args.collection as string);
  await context.db.insert(collection).values({
    id: addr, generation: Number(event.args.generation),
    name: null, symbol: null, totalMinted: 0, isPresale: addr === PRESALE, createdAt: event.block.timestamp,
  }).onConflictDoUpdate(() => ({ generation: Number(event.args.generation) }));
});

/* ── NFT mints + transfers (shared by Presale + every Collection) ──────── */
async function onMint(ctx: any, colAddr: string, to: string, tokenId: bigint, rarity: number, ts: bigint, tx: string, isPresale: boolean) {
  const id = nftId(colAddr, tokenId);
  await ctx.db.insert(nft).values({
    id, collection: lc(colAddr), tokenId: Number(tokenId), owner: lc(to),
    rarity, revealed: isPresale, mintedAt: ts, mintTx: lc(tx),
  }).onConflictDoUpdate(() => ({ owner: lc(to), rarity }));
  // collection rollup
  const c = await ctx.db.find(collection, { id: lc(colAddr) });
  await ctx.db.insert(collection).values({ id: lc(colAddr), totalMinted: 1, isPresale, createdAt: ts })
    .onConflictDoUpdate((cur: any) => ({ totalMinted: (cur.totalMinted ?? 0) + 1 }));
  void c;
}
// Flag a token as a Liquidatoor badge (OnChain Collectible). The Transfer from
// the mint already created the row; here we mark it isLiquidatoor + revealed.
// Badges are NOT counted in the collection's art rollup (separate id range).
async function onLiquidatoor(ctx: any, colAddr: string, tokenId: bigint, ts: bigint, tx: string) {
  await ctx.db.insert(nft).values({
    id: nftId(colAddr, tokenId), collection: lc(colAddr), tokenId: Number(tokenId),
    owner: ZERO as `0x${string}`, rarity: 0, revealed: true, isLiquidatoor: true,
    mintedAt: ts, mintTx: lc(tx),
  }).onConflictDoUpdate(() => ({ isLiquidatoor: true, revealed: true }));
}
async function onTransfer(ctx: any, colAddr: string, from: string, to: string, tokenId: bigint) {
  // ownership
  if (to !== ZERO) {
    await ctx.db.insert(nft).values({ id: nftId(colAddr, tokenId), collection: lc(colAddr), tokenId: Number(tokenId), owner: lc(to), rarity: 0, revealed: false })
      .onConflictDoUpdate(() => ({ owner: lc(to) }));
  }
  // holder balances
  if (from !== ZERO) {
    await ctx.db.insert(holder).values({ id: holderId(colAddr, from), collection: lc(colAddr), address: lc(from), balance: 0 })
      .onConflictDoUpdate((cur: any) => ({ balance: Math.max(0, (cur.balance ?? 0) - 1) }));
  }
  if (to !== ZERO) {
    await ctx.db.insert(holder).values({ id: holderId(colAddr, to), collection: lc(colAddr), address: lc(to), balance: 1 })
      .onConflictDoUpdate((cur: any) => ({ balance: (cur.balance ?? 0) + 1 }));
  }
}

ponder.on("Presale:Transfer", async ({ event, context }) => {
  await onTransfer(context, PRESALE, (event.args.from as string).toLowerCase(), (event.args.to as string).toLowerCase(), event.args.tokenId as bigint);
});
ponder.on("Presale:VolumeMinted", async ({ event, context }) => {
  await onMint(context, PRESALE, event.args.to as string, event.args.tokenId as bigint, Number(event.args.rarity), event.block.timestamp, event.transaction.hash, false);
});
ponder.on("Presale:Revealed", async ({ event, context }) => {
  await context.db.insert(nft).values({ id: nftId(PRESALE, event.args.tokenId as bigint), collection: lc(PRESALE), tokenId: Number(event.args.tokenId), owner: ZERO as `0x${string}`, rarity: Number(event.args.rarity), revealed: true })
    .onConflictDoUpdate(() => ({ revealed: true, rarity: Number(event.args.rarity) }));
});
ponder.on("Presale:LiquidatoorMinted", async ({ event, context }) => {
  await onLiquidatoor(context, PRESALE, event.args.tokenId as bigint, event.block.timestamp, event.transaction.hash);
});

ponder.on("Collection:Transfer", async ({ event, context }) => {
  await onTransfer(context, event.log.address, (event.args.from as string).toLowerCase(), (event.args.to as string).toLowerCase(), event.args.tokenId as bigint);
});
ponder.on("Collection:Minted", async ({ event, context }) => {
  await onMint(context, event.log.address, event.args.to as string, event.args.tokenId as bigint, Number(event.args.rarity), event.block.timestamp, event.transaction.hash, false);
});
ponder.on("Collection:Revealed", async ({ event, context }) => {
  await context.db.insert(nft).values({ id: nftId(event.log.address, event.args.tokenId as bigint), collection: lc(event.log.address), tokenId: Number(event.args.tokenId), owner: ZERO as `0x${string}`, rarity: Number(event.args.rarity), revealed: true })
    .onConflictDoUpdate(() => ({ revealed: true, rarity: Number(event.args.rarity) }));
});
ponder.on("Collection:LiquidatoorMinted", async ({ event, context }) => {
  await onLiquidatoor(context, event.log.address, event.args.tokenId as bigint, event.block.timestamp, event.transaction.hash);
});

/* ── gacha player stats ────────────────────────────────────────────────── */
ponder.on("Hook:TicketWon", async ({ event, context }) => {
  const p = lc(event.args.player as string);
  await context.db.insert(gachaPlayer).values({ id: p, wins: 1, misses: 0, committed: 0, updatedAt: event.block.timestamp })
    .onConflictDoUpdate((cur: any) => ({ wins: (cur.wins ?? 0) + 1, updatedAt: event.block.timestamp }));
});
ponder.on("Hook:TicketLost", async ({ event, context }) => {
  const p = lc(event.args.player as string);
  await context.db.insert(gachaPlayer).values({ id: p, wins: 0, misses: 1, committed: 0, updatedAt: event.block.timestamp })
    .onConflictDoUpdate((cur: any) => ({ misses: (cur.misses ?? 0) + 1, updatedAt: event.block.timestamp }));
});
ponder.on("Hook:CrystalsCommitted", async ({ event, context }) => {
  const p = lc(event.args.player as string);
  const n = Number(event.args.count);
  await context.db.insert(gachaPlayer).values({ id: p, wins: 0, misses: 0, committed: n, updatedAt: event.block.timestamp })
    .onConflictDoUpdate((cur: any) => ({ committed: (cur.committed ?? 0) + n, updatedAt: event.block.timestamp }));
});

/* ── governance ────────────────────────────────────────────────────────── */
ponder.on("Governor:Proposed", async ({ event, context }) => {
  await context.db.insert(proposal).values({
    id: Number(event.args.proposalId), name: event.args.name, symbol: event.args.symbol,
    proposer: lc(event.args.proposer as string), votes: 0n, consumed: false, createdAt: event.block.timestamp,
  }).onConflictDoNothing();
});
ponder.on("Governor:Voted", async ({ event, context }) => {
  const pid = Number(event.args.proposalId);
  await context.db.insert(vote).values({ id: `${pid}-${lc(event.args.voter as string)}`, proposalId: pid, voter: lc(event.args.voter as string), weight: event.args.weight as bigint }).onConflictDoNothing();
  await context.db.insert(proposal).values({ id: pid, name: "", symbol: "", proposer: ZERO as `0x${string}`, votes: event.args.totalVotes as bigint, consumed: false, createdAt: event.block.timestamp })
    .onConflictDoUpdate(() => ({ votes: event.args.totalVotes as bigint }));
});

/* ── dividend: "cast the spell" enchant + fee totals ───────────────────── */
const DIV = "dividend";
async function bumpDiv(ctx: any, field: "totalDeposited" | "totalClaimed" | "treasuryFunded", amount: bigint) {
  await ctx.db.insert(dividendStat).values({ id: DIV, [field]: amount })
    .onConflictDoUpdate((cur: any) => ({ [field]: (cur[field] ?? 0n) + amount }));
}
async function bumpIter(ctx: any, gen: number, field: "migratedOut" | "burned", amount: bigint) {
  await ctx.db.insert(iteration).values({ id: gen, [field]: amount })
    .onConflictDoUpdate((cur: any) => ({ [field]: (cur[field] ?? 0n) + amount }));
}

ponder.on("Dividend:SpellCast", async ({ event, context }) => {
  await context.db.insert(enchant).values({ id: Number(event.args.tokenId), fren: lc(event.args.fren as string), active: true, updatedAt: event.block.timestamp })
    .onConflictDoUpdate(() => ({ fren: lc(event.args.fren as string), active: true, updatedAt: event.block.timestamp }));
});
ponder.on("Dividend:SpellBroken", async ({ event, context }) => {
  await context.db.insert(enchant).values({ id: Number(event.args.tokenId), fren: null, active: false, updatedAt: event.block.timestamp })
    .onConflictDoUpdate(() => ({ active: false, updatedAt: event.block.timestamp }));
});
ponder.on("Dividend:Deposited", async ({ event, context }) => { await bumpDiv(context, "totalDeposited", event.args.amount as bigint); });
ponder.on("Dividend:Claimed", async ({ event, context }) => { await bumpDiv(context, "totalClaimed", event.args.amount as bigint); });
ponder.on("Dividend:TreasuryFunded", async ({ event, context }) => { await bumpDiv(context, "treasuryFunded", event.args.amount as bigint); });

/* ── migration + burn (per-iteration deflation) ────────────────────────── */
ponder.on("CauldronRegistry:HolderClaimed", async ({ event, context }) => { await bumpIter(context, Number(event.args.generation), "migratedOut", event.args.amount as bigint); });
ponder.on("CauldronRegistry:AutoMigrated", async ({ event, context }) => { await bumpIter(context, Number(event.args.fromGen), "migratedOut", event.args.amount as bigint); });
ponder.on("CauldronRegistry:UnclaimedBurned", async ({ event, context }) => { await bumpIter(context, Number(event.args.gen), "burned", event.args.amount as bigint); });

/* ── price candles + raw swaps (charting) ──────────────────────────────── */
// Lazy pool register: the genesis green-candle + prime-buy swaps fire INSIDE the
// summon tx, emitted BEFORE the CauldronSummoned event, so the pool row doesn't
// exist yet when this Swap runs. Read the live current gen/token from the registry
// and register it inline so the first green candle isn't dropped. Only ever hits
// once (the first block); afterwards the pool row exists.
const REG_LAZY_ABI = [
  { type: "function", name: "currentGeneration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "currentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "getCreatureForGeneration", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "string" }, { type: "string" }] },
] as const;
async function ensurePool(ctx: any, poolId: `0x${string}`, ts: bigint, block: bigint) {
  try {
    const [gen, token, creature] = await Promise.all([
      ctx.client.readContract({ address: REGISTRY_ADDR, abi: REG_LAZY_ABI, functionName: "currentGeneration" }),
      ctx.client.readContract({ address: REGISTRY_ADDR, abi: REG_LAZY_ABI, functionName: "currentToken" }),
      ctx.client.readContract({ address: REGISTRY_ADDR, abi: REG_LAZY_ABI, functionName: "getCreatureForGeneration", args: [1n] }).catch(() => ["Gnomeland", "GNOME"]),
    ]);
    await registerPool(ctx, poolId, Number(gen), token as `0x${string}`, (creature as string[])[0], (creature as string[])[1], ts, block);
    return await ctx.db.find(pool, { id: poolId });
  } catch { return null; }
}

ponder.on("PoolManager:Swap", async ({ event, context }) => {
  const poolId = event.args.id as `0x${string}`;
  let p = await context.db.find(pool, { id: poolId });
  if (!p) p = await ensurePool(context, poolId, event.block.timestamp, event.block.number);
  if (!p) return;
  const price = ethPerToken(event.args.sqrtPriceX96 as bigint);
  if (!(price > 0) || !Number.isFinite(price)) return;
  const amount0 = event.args.amount0 as bigint;
  const amountEth = Math.abs(Number(amount0)) / 1e18;
  const isBuy = amount0 < 0n;
  const ts = Number(event.block.timestamp);
  const bucketStart = Math.floor(ts / CANDLE_SECONDS) * CANDLE_SECONDS;
  const candleId = `${poolId}-${bucketStart}`;

  await context.db.insert(swap).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`, poolId, generation: p.generation,
    sender: lc(event.args.sender as string), price, amountEth, isBuy,
    timestamp: event.block.timestamp, block: event.block.number, txHash: event.transaction.hash,
    // strict execution order for correct tick-chart sequencing (many swaps/block)
    orderKey: event.block.number * 1_000_000n + BigInt(event.log.logIndex),
  }).onConflictDoNothing();

  const existing = await context.db.find(candle, { id: candleId });
  if (existing) {
    await context.db.update(candle, { id: candleId }).set({
      high: Math.max(existing.high, price), low: Math.min(existing.low, price), close: price,
      volumeEth: existing.volumeEth + amountEth, swapCount: existing.swapCount + 1,
    });
  } else {
    await context.db.insert(candle).values({
      id: candleId, poolId, generation: p.generation, bucketStart,
      open: price, high: price, low: price, close: price, volumeEth: amountEth, swapCount: 1,
    });
  }
  await context.db.update(pool, { id: poolId }).set({ lastPrice: price, swapCount: p.swapCount + 1, volumeEth: p.volumeEth + amountEth, updatedAt: event.block.timestamp });
});

/* ── perps: positions + liquidation heatmap source ─────────────────────── */
// Liquidation level from entry price + leverage + maintenance margin (matches
// PerpEngine._underwater): a long liquidates as price falls, a short as it rises.
function liqPriceOf(entry: number, lev: number, isLong: boolean): number {
  if (lev <= 0) return entry;
  return isLong
    ? entry * ((lev - 1) * (1 + PERP_M)) / lev   // long: down
    : entry * ((lev + 1) * (1 - PERP_M)) / lev;  // short: up
}
async function bumpStat(ctx: any, gen: number, ts: bigint, patch: (s: any) => any) {
  const cur = await ctx.db.find(perpStat, { id: gen });
  const base = cur ?? { id: gen, longOiEth: 0, shortOiEth: 0, openPositions: 0, totalOpened: 0, totalLiquidated: 0, updatedAt: ts };
  const next = patch({ ...base });
  next.updatedAt = ts;
  if (cur) await ctx.db.update(perpStat, { id: gen }).set(next);
  else await ctx.db.insert(perpStat).values(next);
}

{
  ponder.on("PerpEngine:Opened", async ({ event, context }) => {
    const isLong = event.args.isLong as boolean;
    const lev = Number(event.args.leverage);
    const collateralEth = Number(event.args.collateral) / 1e18;
    const sizeTok = Number(event.args.size) / 1e18;
    const notionalEth = collateralEth * lev;
    // avg execution price (mid-way through your own impact) — fallback only.
    const avgExec = sizeTok > 0 ? notionalEth / sizeTok : 0;

    let gen = 1;
    try {
      gen = Number(await context.client.readContract({
        address: REGISTRY_ADDR, abi: RegistryGenReadAbi, functionName: "currentGeneration",
      }));
    } catch { /* fall back to gen 1 */ }

    // Stored entry = avg execution (fallback). The API overrides this with the
    // POST-OPEN spot (the open's own swap price, looked up by openTx) so PnL only
    // counts moves AFTER your impact — see /perp-positions + /perp-heatmap.
    const entryPrice = avgExec;
    const liqPrice = liqPriceOf(entryPrice, lev, isLong);

    await context.db.insert(perpPosition).values({
      id: `${gen}-${event.args.id}`,
      positionId: event.args.id as bigint,
      generation: gen,
      poolId: null,
      trader: lc(event.args.trader as string),
      isLong, leverage: lev,
      collateralEth, notionalEth, entryPrice, liqPrice,
      status: "open", pnlEth: null,
      openedAt: event.block.timestamp, closedAt: null,
      openTx: event.transaction.hash,
    }).onConflictDoNothing();

    await bumpStat(context, gen, event.block.timestamp, (s) => {
      if (isLong) s.longOiEth += notionalEth; else s.shortOiEth += notionalEth;
      s.openPositions += 1; s.totalOpened += 1; return s;
    });
  });

  // Liquidated is emitted BEFORE Closed in the same tx — mark status, then Closed
  // does the OI/count bookkeeping for every close path (normal or liquidation).
  ponder.on("PerpEngine:Liquidated", async ({ event, context }) => {
    for (const g of await candidateGens(context, event.args.id as bigint)) {
      const pos = await context.db.find(perpPosition, { id: `${g}-${event.args.id}` });
      if (!pos || pos.status !== "open") continue;
      await context.db.update(perpPosition, { id: `${g}-${event.args.id}` }).set({ status: "liquidated" });
      await bumpStat(context, g, event.block.timestamp, (s) => { s.totalLiquidated += 1; return s; });
      break;
    }
  });

  // Badge provenance + liquidator leaderboard. Emitted in the same tx as
  // Liquidated (right after), so the position row already exists — stamp who
  // rekt it + the badge id, and bump the liquidator's kill/badge tally.
  ponder.on("PerpEngine:LiquidatoorAwarded", async ({ event, context }) => {
    const to = lc(event.args.to as string);
    const badgeId = event.args.badgeId as bigint;
    for (const g of await candidateGens(context, event.args.id as bigint)) {
      const pos = await context.db.find(perpPosition, { id: `${g}-${event.args.id}` });
      if (!pos) continue;
      await context.db.update(perpPosition, { id: `${g}-${event.args.id}` })
        .set({ liquidatedBy: to as `0x${string}`, badgeId });
      break;
    }
    await context.db.insert(liquidator)
      .values({ id: to as `0x${string}`, kills: 1, badges: badgeId > 0n ? 1 : 0, lastAt: event.block.timestamp })
      .onConflictDoUpdate((cur: any) => ({
        kills: (cur.kills ?? 0) + 1,
        badges: (cur.badges ?? 0) + (badgeId > 0n ? 1 : 0),
        lastAt: event.block.timestamp,
      }));
  });

  ponder.on("PerpEngine:Closed", async ({ event, context }) => {
    for (const g of await candidateGens(context, event.args.id as bigint)) {
      const pos = await context.db.find(perpPosition, { id: `${g}-${event.args.id}` });
      if (!pos || pos.closedAt) continue;
      const payout = Number(event.args.payout) / 1e18;
      const pnl = Number(event.args.pnl) / 1e18;
      await context.db.update(perpPosition, { id: `${g}-${event.args.id}` }).set({
        status: pos.status === "liquidated" ? "liquidated" : "closed",
        closedAt: event.block.timestamp, pnlEth: pnl,
      });
      await bumpStat(context, g, event.block.timestamp, (s) => {
        if (pos.isLong) s.longOiEth = Math.max(0, s.longOiEth - pos.notionalEth);
        else s.shortOiEth = Math.max(0, s.shortOiEth - pos.notionalEth);
        s.openPositions = Math.max(0, s.openPositions - 1); return s;
      });
      void payout; break;
    }
  });
}

// A position id is unique per engine but our rows are keyed `${gen}-${id}`. The
// engine's nextId is global (never resets across gens), so the id is unique and
// only one gen row will match — probe the few recent gens to find it.
async function candidateGens(context: any, _id: bigint): Promise<number[]> {
  let gen = 1;
  try {
    gen = Number(await context.client.readContract({
      address: REGISTRY_ADDR, abi: RegistryGenReadAbi, functionName: "currentGeneration",
    }));
  } catch { /* default */ }
  const gens: number[] = [];
  for (let g = gen; g >= 1 && g >= gen - 3; g--) gens.push(g);
  return gens;
}

/* ══════════════════════════════════════════════════════════════════════════
 * r30 · REDEMPTION FLOOR (genesis recycle-ratchet) + LEGACY COLLECTION FLOOR
 * ════════════════════════════════════════════════════════════════════════ */

const evId = (tx: string, logIndex: number) => `${lc(tx)}-${logIndex}`;

// Read the live current generation (FloorGrew carries no gen). Falls back to 1.
async function currentGen(context: any): Promise<number> {
  try {
    return Number(await context.client.readContract({
      address: REGISTRY_ADDR, abi: RegistryGenReadAbi, functionName: "currentGeneration",
    }));
  } catch { return 1; }
}

async function bumpGenesisFloor(ctx: any, gen: number, patch: (cur: any) => any, ts: bigint) {
  await ctx.db.insert(genesisFloor).values({ id: gen, updatedAt: ts, ...patch({}) })
    .onConflictDoUpdate((cur: any) => ({ ...patch(cur), updatedAt: ts }));
}

// RECYCLE a genesis fren for the live floor (paid from the reserve; NFT → treasury).
ponder.on("RegistryFloor:FrenRedeemed", async ({ event, context }) => {
  const gen = Number(event.args.generation);
  const amt = event.args.amount as bigint;
  await context.db.insert(floorEvent).values({
    id: evId(event.transaction.hash, event.log.logIndex), kind: "redeem", generation: gen,
    tokenId: event.args.mifrenTokenId as bigint, actor: lc(event.args.holder as string),
    amount: amt, floorAfter: null, ts: event.block.timestamp, block: event.block.number,
  }).onConflictDoNothing();
  await bumpGenesisFloor(context, gen, (c) => ({
    redeemedCount: (c.redeemedCount ?? 0) + 1,
    totalRedeemed: (c.totalRedeemed ?? 0n) + amt,
  }), event.block.timestamp);
});

// BUY a treasury fren for 2x floor (payment added to the reserve → floor grows).
ponder.on("RegistryFloor:FrenBought", async ({ event, context }) => {
  const gen = Number(event.args.generation);
  const paid = event.args.paid as bigint;
  await context.db.insert(floorEvent).values({
    id: evId(event.transaction.hash, event.log.logIndex), kind: "buy", generation: gen,
    tokenId: event.args.mifrenTokenId as bigint, actor: lc(event.args.buyer as string),
    amount: paid, floorAfter: null, ts: event.block.timestamp, block: event.block.number,
  }).onConflictDoNothing();
  await bumpGenesisFloor(context, gen, (c) => ({
    boughtCount: (c.boughtCount ?? 0) + 1,
  }), event.block.timestamp);
});

// The floor RATCHET — reserve grew, new floor-per-fren. Not gen-tagged in the
// event, so attribute to the current (highest-known) iteration.
ponder.on("RegistryFloor:FloorGrew", async ({ event, context }) => {
  const gen = Number(await currentGen(context));
  const added = event.args.addedToReserve as bigint;
  const newReserve = event.args.newReserve as bigint;
  const floorPer = event.args.newFloorPerFren as bigint;
  await context.db.insert(floorEvent).values({
    id: evId(event.transaction.hash, event.log.logIndex), kind: "grow", generation: gen,
    tokenId: null, actor: null, amount: added, floorAfter: floorPer,
    ts: event.block.timestamp, block: event.block.number,
  }).onConflictDoNothing();
  await bumpGenesisFloor(context, gen, (c) => ({
    reserveOutstanding: newReserve,
    floorPerFren: floorPer,
    totalGrown: (c.totalGrown ?? 0n) + added,
  }), event.block.timestamp);
});

// LEGACY collection floor: a dead collection's NFT recycled for its floor.
ponder.on("RegistryFloor:CollectionRecycled", async ({ event, context }) => {
  const gen = Number(event.args.gen);
  const payout = event.args.payout as bigint;
  await context.db.insert(collectionFloorEvent).values({
    id: evId(event.transaction.hash, event.log.logIndex), kind: "recycle", generation: gen,
    tokenId: event.args.tokenId as bigint, actor: lc(event.args.holder as string),
    amount: payout, ts: event.block.timestamp, block: event.block.number,
  }).onConflictDoNothing();
  await context.db.insert(collectionFloor).values({
    id: gen, recycledCount: 1, totalPaidOut: payout, updatedAt: event.block.timestamp,
  }).onConflictDoUpdate((c: any) => ({
    recycledCount: (c.recycledCount ?? 0) + 1,
    totalPaidOut: (c.totalPaidOut ?? 0n) + payout,
    updatedAt: event.block.timestamp,
  }));
});

// LEGACY collection floor: a recycled NFT bought back for 2x (grows the floor).
ponder.on("RegistryFloor:CollectionBought", async ({ event, context }) => {
  const gen = Number(event.args.gen);
  const paid = event.args.paid as bigint;
  await context.db.insert(collectionFloorEvent).values({
    id: evId(event.transaction.hash, event.log.logIndex), kind: "buy", generation: gen,
    tokenId: event.args.tokenId as bigint, actor: lc(event.args.buyer as string),
    amount: paid, ts: event.block.timestamp, block: event.block.number,
  }).onConflictDoNothing();
  await context.db.insert(collectionFloor).values({
    id: gen, boughtCount: 1, totalPaidIn: paid, updatedAt: event.block.timestamp,
  }).onConflictDoUpdate((c: any) => ({
    boughtCount: (c.boughtCount ?? 0) + 1,
    totalPaidIn: (c.totalPaidIn ?? 0n) + paid,
    updatedAt: event.block.timestamp,
  }));
});

// PROPOSER flywheel — a slice of the fee accrued to the iteration's proposer.
ponder.on("HookFloor:ProposerFunded", async ({ event, context }) => {
  const amt = event.args.amount as bigint;
  if (amt === 0n) return; // 0 = a claim marker (pull), not an accrual
  await context.db.insert(proposerEarning).values({
    id: lc(event.args.proposer as string), totalEarned: amt, payoutCount: 1, updatedAt: event.block.timestamp,
  }).onConflictDoUpdate((c: any) => ({
    totalEarned: (c.totalEarned ?? 0n) + amt,
    payoutCount: (c.payoutCount ?? 0) + 1,
    updatedAt: event.block.timestamp,
  }));
});
