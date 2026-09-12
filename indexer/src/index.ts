import { ponder } from "ponder:registry";
import { pool, candle, swap, collection, nft, holder, gachaPlayer, proposal, vote, enchant, dividendStat, iteration, perpPosition, perpStat, liquidator, genesisFloor, floorEvent, collectionFloor, collectionFloorEvent, proposerEarning, seedEvent, seedState, rotationProposal, rotationVote, rotationSlice } from "ponder:schema";
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
async function registerPool(ctx: any, poolId: `0x${string}`, gen: number, token: `0x${string}`, name: string, symbol: string, ts: bigint, block: bigint, authoritative = true) {
  const clean = name.replace(/\s*by Magic Internet Frens\s*$/i, "").trim();
  //  WHAT IS THIS POOL PRICED IN? Read once, at registration. The quote is
  //  fixed for a generation's whole life (`generationQuote[gen]` is written at
  //  rebirth and never revised), so there is nothing to keep in sync. A
  //  registry that predates the multi-quote work has no such function; treat
  //  that as native, which is what those generations actually are.
  let quote = ZERO as `0x${string}`;
  try {
    quote = lc(await ctx.client.readContract({
      abi: RegistryGenReadAbi, address: REGISTRY_ADDR,
      functionName: "generationQuote", args: [BigInt(gen)],
    }) as string);
  } catch { /* pre-quote registry, or an RPC blip: native is the right answer */ }
  await ctx.db.insert(pool).values({
    id: poolId, generation: gen, token: lc(token), name: clean, symbol,
    createdAt: ts, createdBlock: block, dead: false, lastPrice: 0, swapCount: 0, volumeEth: 0, updatedAt: ts,
    quote, isPrimary: true,
    //  A lazily-registered row (see `ensurePool`) is a GUESS about the name:
    //  the swaps inside a summon/rebirth transaction are emitted BEFORE the
    //  CauldronSummoned/Reborn event that carries the real one. With
    //  `onConflictDoNothing` on every path, that guess won - a relaunched
    //  generation kept gen 1's creature name forever while pointing at the new
    //  token. So the event path, which is authoritative, corrects it.
  }).onConflictDoUpdate((row: any) => (authoritative
    ? { generation: gen, token: lc(token), name: clean, symbol, quote }
    : {}));
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
//  The live generation's collection, subscribed by ADDRESS as well as through the
//  factory. Same handlers, same tables — the factory did not index the current
//  collection, so a wallet holding crystals on chain read as empty in the UI.
ponder.on("LiveCollection:Transfer", async ({ event, context }) => {
  await onTransfer(context, event.log.address, (event.args.from as string).toLowerCase(), (event.args.to as string).toLowerCase(), event.args.tokenId as bigint);
});
ponder.on("LiveCollection:Minted", async ({ event, context }) => {
  await onMint(context, event.log.address, event.args.to as string, event.args.tokenId as bigint, Number(event.args.rarity), event.block.timestamp, event.transaction.hash, false);
});
ponder.on("LiveCollection:Revealed", async ({ event, context }) => {
  await context.db.insert(nft).values({ id: nftId(event.log.address, event.args.tokenId as bigint), collection: lc(event.log.address), tokenId: Number(event.args.tokenId), owner: ZERO as `0x${string}`, rarity: Number(event.args.rarity), revealed: true })
    .onConflictDoUpdate(() => ({ revealed: true, rarity: Number(event.args.rarity) }));
});
ponder.on("LiveCollection:LiquidatoorMinted", async ({ event, context }) => {
  await onLiquidatoor(context, event.log.address, event.args.tokenId as bigint, event.block.timestamp, event.transaction.hash);
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
//  NO `UnclaimedBurned` SUBSCRIPTION. The event exists in no contract in the
//  tree (38 of the other 39 indexer filters match a real event exactly), so the
//  filter never fired and `iteration.burned` sat at 0 forever while the API
//  served it as an indexed statistic. A filter on a non-existent topic is not a
//  future-proofing measure, it is a number that lies quietly.

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
  { type: "function", name: "generationPoolId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bytes32" }] },
] as const;

//  Pool ids proven NOT to be ours. Without the topic filter every v4 swap on the
//  chain reaches this handler, and re-asking the registry about the same foreign
//  pool on every one of its trades would be a pointless RPC per log.
const foreignPools = new Set<string>();
async function ensurePool(ctx: any, poolId: `0x${string}`, ts: bigint, block: bigint) {
  if (foreignPools.has(poolId)) return null;
  try {
    //  TIMING, BECAUSE IT IS LOAD-BEARING. The green-candle swap is emitted
    //  INSIDE the summon/rebirth transaction, BEFORE `generationPoolId[gen]` is
    //  written (the registry records the seed after PoolOps returns). A
    //  mid-transaction read would therefore see 0x0 and reject our own first
    //  candle. It does not: Ponder pins `ctx.client` reads to
    //  `event.block.number` (indexing/client.js), i.e. END of block, and the
    //  whole summon is one transaction inside that block - so the mapping is
    //  populated by the time this resolves.
    //
    //  PROVE IT IS OURS FIRST. This used to register whatever pool id it was
    //  handed, which was safe only because the Ponder-level topic filter meant
    //  nothing else could arrive. That filter is gone (it pinned the indexer to
    //  a pool id that changes at every relaunch), so the check has to be here:
    //  ask the registry for the LIVE generation's pool id and compare. Anything
    //  else is somebody else's v4 pool and must not become our chart.
    const gen = await ctx.client.readContract({
      address: REGISTRY_ADDR, abi: REG_LAZY_ABI, functionName: "currentGeneration",
    });
    const ours = await ctx.client.readContract({
      address: REGISTRY_ADDR, abi: REG_LAZY_ABI, functionName: "generationPoolId", args: [gen],
    });
    if (String(ours).toLowerCase() !== poolId.toLowerCase()) {
      foreignPools.add(poolId);
      return null;
    }
    const [token, creature] = await Promise.all([
      ctx.client.readContract({ address: REGISTRY_ADDR, abi: REG_LAZY_ABI, functionName: "currentToken" }),
      ctx.client.readContract({ address: REGISTRY_ADDR, abi: REG_LAZY_ABI, functionName: "getCreatureForGeneration", args: [gen] }).catch(() => ["Gnomeland", "GNOME"]),
    ]);
    //  Provisional: the real name arrives moments later on CauldronSummoned /
    //  CauldronReborn, which overwrites this (see registerPool).
    await registerPool(ctx, poolId, Number(gen), token as `0x${string}`, (creature as string[])[0], (creature as string[])[1], ts, block, false);
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


/* ══════════════════════ LAUNCH SEEDING FEED ══════════════════════════════
 * Progressive stream + tranched prime buy, indexed so the frontend can show the
 * launch filling in real time instead of polling the seeder over public RPC.
 *
 * `seedState` is a singleton keyed "live" — upserted rather than inserted so a
 * replay is idempotent, and so a poke that arrives before SeedStarted (possible
 * only on a partial reindex) still creates the row instead of throwing. */
const SEED_ID = "live";

async function bumpSeed(context: any, patch: Record<string, unknown>, ts: bigint) {
  await context.db
    .insert(seedState)
    .values({ id: SEED_ID, updatedAt: ts, ...patch })
    .onConflictDoUpdate(() => ({ updatedAt: ts, ...patch }));
}

async function logSeed(context: any, event: any, kind: string, gen: number, extra: Record<string, unknown> = {}) {
  await context.db.insert(seedEvent).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    kind, generation: gen,
    ts: event.block.timestamp, block: event.block.number, txHash: event.transaction.hash,
    ...extra,
  }).onConflictDoNothing();
}

ponder.on("Seeder:SeedStarted", async ({ event, context }) => {
  const gen = Number(event.args.gen);
  await logSeed(context, event, "started", gen);
  await bumpSeed(context, {
    generation: gen,
    ethTotal: event.args.ethTotal as bigint,
    tokenTotal: event.args.tokenTotal as bigint,
    window: BigInt(event.args.window as bigint),
    startTs: event.block.timestamp,
    // A fresh campaign resets progress: `withdrawAll` clears the contract's
    // counters too, so carrying the previous generation's numbers forward would
    // render a brand-new launch as already finished.
    placedWad: 0n, basePlaced: false, complete: false,
    primeSpent: 0n, primeTokenOut: 0n, pokes: 0,
  }, event.block.timestamp);
});

ponder.on("Seeder:BasePlaced", async ({ event, context }) => {
  const gen = Number(event.args.gen);
  await logSeed(context, event, "base", gen);
  await bumpSeed(context, { basePlaced: true }, event.block.timestamp);
});

ponder.on("Seeder:Poked", async ({ event, context }) => {
  const to = event.args.toWad as bigint;
  const cur = await context.db.find(seedState, { id: SEED_ID });
  await logSeed(context, event, "poked", cur?.generation ?? 0, {
    fromWad: event.args.fromWad as bigint,
    toWad: to,
    tick: Number(event.args.tick),
  });
  await bumpSeed(context, { placedWad: to, pokes: (cur?.pokes ?? 0) + 1 }, event.block.timestamp);
});

ponder.on("Seeder:SeedComplete", async ({ event, context }) => {
  const gen = Number(event.args.gen);
  await logSeed(context, event, "complete", gen);
  await bumpSeed(context, { complete: true, placedWad: 10n ** 18n }, event.block.timestamp);
});

ponder.on("Seeder:PrimeFunded", async ({ event, context }) => {
  const cur = await context.db.find(seedState, { id: SEED_ID });
  await logSeed(context, event, "funded", cur?.generation ?? 0, {
    budget: event.args.budget as bigint,
  });
  await bumpSeed(context, { primeBudget: event.args.budget as bigint }, event.block.timestamp);
});

ponder.on("Seeder:PrimeBought", async ({ event, context }) => {
  const gen = Number(event.args.gen);
  const cur = await context.db.find(seedState, { id: SEED_ID });
  await logSeed(context, event, "prime", gen, {
    ethIn: event.args.ethIn as bigint,
    tokenOut: event.args.tokenOut as bigint,
    spent: event.args.spent as bigint,
    budget: event.args.budget as bigint,
  });
  await bumpSeed(context, {
    primeSpent: event.args.spent as bigint,
    primeBudget: event.args.budget as bigint,
    primeTokenOut: (cur?.primeTokenOut ?? 0n) + (event.args.tokenOut as bigint),
  }, event.block.timestamp);
});

// ── TREASURY ROTATION GOVERNANCE ────────────────────────────────────────────
// The vote that changes what the LP is denominated in, and the slices it
// authorises. Previously indexed nowhere, so the frontend could file a proposal
// and then had nothing to render: no tally, no AGAINST side, no executed
// rotation. Every signature here was verified against a live Sepolia log.

ponder.on("TreasuryGov:Proposed", async ({ event, context }) => {
  await context.db.insert(rotationProposal).values({
    id: event.args.id.toString(),
    proposer: event.args.proposer,
    quote: event.args.quote,
    maxTotalBps: Number(event.args.maxTotalBps),
    createdTs: event.block.timestamp,
    createdBlock: event.block.number,
    updatedTs: event.block.timestamp,
    txHash: event.transaction.hash,
  }).onConflictDoNothing();
});

ponder.on("TreasuryGov:Voted", async ({ event, context }) => {
  const pid = event.args.id.toString();
  const support = event.args.support;
  const weight = event.args.weight;

  //  THE BALLOT IS KEYED BY (proposal, voter), NOT BY TX.
  //  `TreasuryGovernor.vote` reverts `AlreadyVoted` on a second ballot, so one
  //  voter contributes exactly once. Keying by txHash would let a re-org replay
  //  inflate a tally the contract itself refuses to inflate.
  await context.db.insert(rotationVote).values({
    id: `${pid}-${event.args.voter.toLowerCase()}`,
    proposalId: pid,
    voter: event.args.voter,
    support,
    weight,
    ts: event.block.timestamp,
    block: event.block.number,
    txHash: event.transaction.hash,
  }).onConflictDoNothing();

  await context.db.update(rotationProposal, { id: pid }).set((row) => ({
    forVotes: row.forVotes + (support ? weight : 0n),
    againstVotes: row.againstVotes + (support ? 0n : weight),
    voters: row.voters + 1,
    updatedTs: event.block.timestamp,
  }));
});

ponder.on("TreasuryGov:Executed", async ({ event, context }) => {
  await context.db.update(rotationProposal, { id: event.args.id.toString() }).set({
    executed: true,
    expiry: event.args.expiry,
    updatedTs: event.block.timestamp,
  });
});

ponder.on("TreasuryGov:Cancelled", async ({ event, context }) => {
  await context.db.update(rotationProposal, { id: event.args.id.toString() }).set({
    cancelled: true,
    updatedTs: event.block.timestamp,
  });
});

ponder.on("RotationExec:SliceRotated", async ({ event, context }) => {
  //  quoteIn is denominated in `from` and quoteOut in `to`. Those can be 18 and
  //  6 decimals respectively, so they are stored raw and converted per-asset by
  //  the API — subtracting or ratioing them here would be the exact
  //  decimals confusion QuoteRotator was redesigned to avoid.
  await context.db.insert(rotationSlice).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    generation: Number(event.args.gen),
    fromQuote: event.args.from,
    toQuote: event.args.to,
    quoteIn: event.args.quoteIn,
    quoteOut: event.args.quoteOut,
    sliceBps: Number(event.args.sliceBps),
    ts: event.block.timestamp,
    block: event.block.number,
    txHash: event.transaction.hash,
  }).onConflictDoNothing();
});
