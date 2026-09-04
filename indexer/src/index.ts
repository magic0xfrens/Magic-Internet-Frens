import { ponder } from "ponder:registry";
import { pool, candle, swap, collection, nft, holder, gachaPlayer, proposal, vote, enchant, dividendStat, iteration } from "ponder:schema";

const CANDLE_SECONDS = Number(process.env.CANDLE_SECONDS ?? 30);
const Q96 = 2 ** 96;
const ZERO = "0x0000000000000000000000000000000000000000";
const PRESALE = (process.env.PRESALE_ADDRESS ?? "0x66ab0548468c3c32742a015a2796155b1ea7133d").toLowerCase();

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
ponder.on("PoolManager:Swap", async ({ event, context }) => {
  const poolId = event.args.id as `0x${string}`;
  const p = await context.db.find(pool, { id: poolId });
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
