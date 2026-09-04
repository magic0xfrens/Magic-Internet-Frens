import { db } from "ponder:api";
import schema from "ponder:schema";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { graphql, eq, desc, and } from "ponder";

const app = new Hono();
app.use("*", cors({ origin: process.env.CORS_ORIGIN ?? "*" }));
app.use("/graphql", graphql({ db, schema }));
app.use("/", graphql({ db, schema }));

/* ── charting ──────────────────────────────────────────────────────────── */
app.get("/candles/:generation", async (c) => {
  const gen = Number(c.req.param("generation"));
  const limit = Math.min(Number(c.req.query("limit") ?? 120), 500);
  const pools = await db.select().from(schema.pool).where(eq(schema.pool.generation, gen)).limit(1);
  const p = pools[0];
  if (!p) return c.json({ pool: null, candles: [], last: 0 });
  const rows = await db.select().from(schema.candle).where(eq(schema.candle.poolId, p.id)).orderBy(desc(schema.candle.bucketStart)).limit(limit);
  const candles = rows.reverse().map((r) => ({ t: r.bucketStart, o: r.open, h: r.high, l: r.low, c: r.close, v: r.volumeEth }));
  return c.json({ pool: { id: p.id, generation: p.generation, token: p.token, name: p.name, symbol: p.symbol, dead: p.dead }, candles, last: p.lastPrice, volumeEth: p.volumeEth, swapCount: p.swapCount });
});
app.get("/recent/:generation", async (c) => {
  const gen = Number(c.req.param("generation"));
  const limit = Math.min(Number(c.req.query("limit") ?? 150), 300);
  const pools = await db.select().from(schema.pool).where(eq(schema.pool.generation, gen)).limit(1);
  const p = pools[0];
  if (!p) return c.json({ swaps: [] });
  const rows = await db.select().from(schema.swap).where(eq(schema.swap.poolId, p.id)).orderBy(desc(schema.swap.timestamp)).limit(limit);
  return c.json({ swaps: rows.map((r) => ({ price: r.price, amountEth: r.amountEth, isBuy: r.isBuy, t: Number(r.timestamp), tx: r.txHash })) });
});

/* ── collections + NFTs + holders ──────────────────────────────────────── */
app.get("/collections", async (c) => {
  const rows = await db.select().from(schema.collection);
  return c.json({ collections: rows.map((r) => ({
    address: r.id, generation: r.generation, name: r.name, symbol: r.symbol,
    totalMinted: r.totalMinted, isPresale: r.isPresale,
    createdAt: r.createdAt ? Number(r.createdAt) : null,
  })) });
});
// NFTs owned by a wallet (across all collections) — the "my frens" view.
app.get("/nfts/:owner", async (c) => {
  const owner = c.req.param("owner").toLowerCase() as `0x${string}`;
  const limit = Math.min(Number(c.req.query("limit") ?? 500), 2000);
  const rows = await db.select().from(schema.nft).where(eq(schema.nft.owner, owner)).limit(limit);
  return c.json({ nfts: rows.map((r) => ({ collection: r.collection, tokenId: r.tokenId, rarity: r.rarity, revealed: r.revealed })) });
});
// NFTs in a collection.
app.get("/collection/:address/nfts", async (c) => {
  const addr = c.req.param("address").toLowerCase() as `0x${string}`;
  const limit = Math.min(Number(c.req.query("limit") ?? 200), 2000);
  const rows = await db.select().from(schema.nft).where(eq(schema.nft.collection, addr)).orderBy(desc(schema.nft.tokenId)).limit(limit);
  return c.json({ nfts: rows.map((r) => ({ tokenId: r.tokenId, owner: r.owner, rarity: r.rarity, revealed: r.revealed })) });
});

/* ── gacha player stats ────────────────────────────────────────────────── */
app.get("/gacha/:player", async (c) => {
  const p = c.req.param("player").toLowerCase() as `0x${string}`;
  const rows = await db.select().from(schema.gachaPlayer).where(eq(schema.gachaPlayer.id, p)).limit(1);
  const g = rows[0];
  return c.json(g ? { wins: g.wins, misses: g.misses, committed: g.committed } : { wins: 0, misses: 0, committed: 0 });
});

/* ── dividend + "cast the spell" enchant ───────────────────────────────── */
app.get("/dividend", async (c) => {
  const rows = await db.select().from(schema.dividendStat).where(eq(schema.dividendStat.id, "dividend")).limit(1);
  const s = rows[0];
  const active = await db.select().from(schema.enchant).where(eq(schema.enchant.active, true));
  return c.json({
    totalDeposited: (s?.totalDeposited ?? 0n).toString(),
    totalClaimed: (s?.totalClaimed ?? 0n).toString(),
    treasuryFunded: (s?.treasuryFunded ?? 0n).toString(),
    activeShares: active.length,
  });
});
// Which of a wallet's genesis frens are currently enchanted (spell cast).
app.get("/enchants/:owner", async (c) => {
  const owner = c.req.param("owner").toLowerCase() as `0x${string}`;
  const rows = await db.select().from(schema.enchant).where(and(eq(schema.enchant.fren, owner), eq(schema.enchant.active, true)));
  return c.json({ tokenIds: rows.map((r) => r.id) });
});

/* ── per-iteration migration + burn (deflation) ────────────────────────── */
app.get("/iterations", async (c) => {
  const rows = await db.select().from(schema.iteration).orderBy(desc(schema.iteration.id));
  let totalBurned = 0n;
  for (const r of rows) totalBurned += r.burned;
  return c.json({
    iterations: rows.map((r) => ({
      generation: r.id, token: r.token, symbol: r.symbol,
      migratedOut: r.migratedOut.toString(), burned: r.burned.toString(),
    })),
    totalBurned: totalBurned.toString(),
    supplyPerGen: "777000000000000000000000000", // fixed 777M * 1e18 per iteration
  });
});

/* ── governance ────────────────────────────────────────────────────────── */
app.get("/proposals", async (c) => {
  const rows = await db.select().from(schema.proposal).orderBy(desc(schema.proposal.votes));
  return c.json({ proposals: rows.map((r) => ({ id: r.id, name: r.name, symbol: r.symbol, proposer: r.proposer, votes: r.votes.toString(), consumed: r.consumed })) });
});

export default app;
