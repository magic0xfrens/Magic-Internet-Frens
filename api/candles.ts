import type { VercelRequest, VercelResponse } from "@vercel/node";
import { neon } from "@neondatabase/serverless";
import { createPublicClient, http, parseAbiItem, type Address } from "viem";
import { sepolia } from "viem/chains";

/**
 * /api/candles?gen=N  — live OHLC price candles for a Cauldron generation.
 *
 * SCALE MODEL (built for 1000+ concurrent viewers):
 *   1. Candles live in Neon Postgres — we NEVER recompute history. Each call
 *      only INCREMENTALLY indexes new swaps since the pool's last indexed block.
 *   2. The response is CDN-cached (s-maxage + stale-while-revalidate), so a
 *      thousand viewers collapse to ~1 origin hit per cache window; everyone
 *      else is served instantly from Vercel's edge.
 *   3. A short time-lock bounds indexing work under a cache-miss stampede.
 *
 * Without DATABASE_URL it degrades gracefully to a DB-less on-chain read
 * (bounded getLogs) so local dev still returns a chart.
 */

const CHAIN = sepolia;
const RPC = process.env.SEPOLIA_RPC || process.env.PONDER_RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com";
const REGISTRY = (process.env.REGISTRY_ADDRESS || "0xf311cFdb3D185Cd5e862ca09E84051109c723802") as Address;
const POOL_MANAGER = (process.env.POOL_MANAGER_ADDRESS || "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543") as Address;
const START_BLOCK = BigInt(process.env.START_BLOCK || "11590480");
const CANDLE_SECONDS = Number(process.env.CANDLE_SECONDS || "300");
const MAX_LOG_RANGE = 9000n;      // stay under public-RPC getLogs caps
const INDEX_MIN_INTERVAL = 12;    // seconds between incremental indexes per pool

const SWAP = parseAbiItem(
  "event Swap(bytes32 indexed id, address indexed sender, int128 amount0, int128 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick, uint24 fee)",
);
const REGISTRY_ABI = [
  { type: "function", name: "generationPoolId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "generationToken", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "currentGeneration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const TOKEN_ABI = [
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
] as const;

const client = createPublicClient({ chain: CHAIN, transport: http(RPC) });
const Q96 = 2 ** 96;
const nowSec = () => Math.floor(Date.now() / 1000);

/** ETH per token from a V4 sqrtPriceX96 (currency0 = ETH, currency1 = token). */
function ethPerToken(sqrtPriceX96: bigint): number {
  const s = Number(sqrtPriceX96) / Q96;
  const tokenPerEth = s * s;
  return tokenPerEth > 0 ? 1 / tokenPerEth : 0;
}

type Row = { o: number; h: number; l: number; c: number; v: number };

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const gen = Number((req.query.gen as string) ?? "1");
  const limit = Math.min(Number((req.query.limit as string) ?? "120"), 500);
  if (!Number.isFinite(gen) || gen < 1) return res.status(400).json({ error: "bad gen" });

  try {
    // Serve everyone from the CDN; revalidate quietly in the background.
    res.setHeader("Cache-Control", "public, s-maxage=15, stale-while-revalidate=60");

    const dbUrl = process.env.DATABASE_URL;
    if (!dbUrl) {
      // Local / no-DB: bounded on-chain read, no persistence.
      const out = await directRead(gen);
      return res.status(200).json(out);
    }

    const sql = neon(dbUrl);
    await ensureSchema(sql);

    // Resolve (and cache) the pool for this generation.
    let pool = (await sql`SELECT * FROM cauldron_pool WHERE gen = ${gen}`)[0] as
      | { gen: number; pool_id: string; token: string; name: string; symbol: string; last_price: number; last_block: string; indexed_at: number }
      | undefined;

    if (!pool) {
      const poolId = (await client.readContract({ address: REGISTRY, abi: REGISTRY_ABI, functionName: "generationPoolId", args: [BigInt(gen)] })) as string;
      if (!poolId || /^0x0+$/.test(poolId)) return res.status(200).json({ pool: null, candles: [], last: 0 });
      const token = (await client.readContract({ address: REGISTRY, abi: REGISTRY_ABI, functionName: "generationToken", args: [BigInt(gen)] })) as Address;
      const [name, symbol] = await Promise.all([
        client.readContract({ address: token, abi: TOKEN_ABI, functionName: "name" }).catch(() => "Iteration") as Promise<string>,
        client.readContract({ address: token, abi: TOKEN_ABI, functionName: "symbol" }).catch(() => "TKN") as Promise<string>,
      ]);
      const cleanName = name.replace(/\s*by Magic Internet Frens\s*$/i, "").trim();
      await sql`INSERT INTO cauldron_pool (gen, pool_id, token, name, symbol, last_price, last_block, indexed_at)
                VALUES (${gen}, ${poolId}, ${token.toLowerCase()}, ${cleanName}, ${symbol}, 0, ${START_BLOCK.toString()}, 0)
                ON CONFLICT (gen) DO NOTHING`;
      pool = (await sql`SELECT * FROM cauldron_pool WHERE gen = ${gen}`)[0] as typeof pool;
    }
    if (!pool) return res.status(200).json({ pool: null, candles: [], last: 0 });

    // Incremental index — only when stale (bounds work under a stampede).
    if (nowSec() - Number(pool.indexed_at) >= INDEX_MIN_INTERVAL) {
      await indexNew(sql, pool.gen, pool.pool_id as `0x${string}`, BigInt(pool.last_block));
      pool = (await sql`SELECT * FROM cauldron_pool WHERE gen = ${gen}`)[0] as typeof pool;
    }

    const rows = (await sql`
      SELECT bucket, o, h, l, c, v FROM cauldron_candle
      WHERE pool_id = ${pool!.pool_id} ORDER BY bucket DESC LIMIT ${limit}
    `) as { bucket: number; o: number; h: number; l: number; c: number; v: number }[];
    const candles = rows.reverse().map((r) => ({ t: r.bucket, o: r.o, h: r.h, l: r.l, c: r.c, v: r.v }));

    return res.status(200).json({
      pool: { gen: pool!.gen, id: pool!.pool_id, token: pool!.token, name: pool!.name, symbol: pool!.symbol },
      candles,
      last: pool!.last_price,
    });
  } catch (e) {
    return res.status(200).json({ pool: null, candles: [], last: 0, error: (e as Error).message });
  }
}

async function ensureSchema(sql: ReturnType<typeof neon>) {
  await sql`CREATE TABLE IF NOT EXISTS cauldron_pool (
    gen INT PRIMARY KEY, pool_id TEXT NOT NULL, token TEXT, name TEXT, symbol TEXT,
    last_price DOUBLE PRECISION DEFAULT 0, last_block BIGINT DEFAULT 0, indexed_at BIGINT DEFAULT 0
  )`;
  await sql`CREATE TABLE IF NOT EXISTS cauldron_candle (
    pool_id TEXT NOT NULL, bucket INT NOT NULL,
    o DOUBLE PRECISION, h DOUBLE PRECISION, l DOUBLE PRECISION, c DOUBLE PRECISION,
    v DOUBLE PRECISION DEFAULT 0, n INT DEFAULT 0,
    PRIMARY KEY (pool_id, bucket)
  )`;
}

/** Index swaps from `fromBlock`+1 to head, chunked; upsert OHLC candles. */
async function indexNew(sql: ReturnType<typeof neon>, gen: number, poolId: `0x${string}`, lastBlock: bigint) {
  const head = await client.getBlockNumber();
  let from = lastBlock > 0n ? lastBlock + 1n : START_BLOCK;
  if (from > head) { await sql`UPDATE cauldron_pool SET indexed_at = ${nowSec()} WHERE gen = ${gen}`; return; }

  // Anchor block→timestamp with the head block (Sepolia ~12s blocks).
  const headBlock = await client.getBlock({ blockNumber: head });
  const headTs = Number(headBlock.timestamp);
  const tsOf = (bn: bigint) => headTs - Number(head - bn) * 12;

  let lastPrice = 0;
  const buckets = new Map<number, Row>();

  while (from <= head) {
    const to = from + MAX_LOG_RANGE - 1n > head ? head : from + MAX_LOG_RANGE - 1n;
    const logs = await client.getLogs({ address: POOL_MANAGER, event: SWAP, args: { id: poolId }, fromBlock: from, toBlock: to });
    for (const l of logs) {
      const sp = l.args.sqrtPriceX96 as bigint | undefined;
      if (!sp) continue;
      const price = ethPerToken(sp);
      if (!(price > 0) || !Number.isFinite(price)) continue;
      const amt0 = l.args.amount0 as bigint;
      const amtEth = Math.abs(Number(amt0)) / 1e18;
      const bucket = Math.floor(tsOf(l.blockNumber!) / CANDLE_SECONDS) * CANDLE_SECONDS;
      const cur = buckets.get(bucket);
      if (cur) { cur.h = Math.max(cur.h, price); cur.l = Math.min(cur.l, price); cur.c = price; cur.v += amtEth; }
      else buckets.set(bucket, { o: price, h: price, l: price, c: price, v: amtEth });
      lastPrice = price;
    }
    from = to + 1n;
  }

  // Upsert accumulated buckets (merge with any existing candle in that bucket).
  for (const [bucket, r] of buckets) {
    await sql`
      INSERT INTO cauldron_candle (pool_id, bucket, o, h, l, c, v, n)
      VALUES (${poolId}, ${bucket}, ${r.o}, ${r.h}, ${r.l}, ${r.c}, ${r.v}, 1)
      ON CONFLICT (pool_id, bucket) DO UPDATE SET
        h = GREATEST(cauldron_candle.h, EXCLUDED.h),
        l = LEAST(cauldron_candle.l, EXCLUDED.l),
        c = EXCLUDED.c,
        v = cauldron_candle.v + EXCLUDED.v,
        n = cauldron_candle.n + 1
    `;
  }

  await sql`UPDATE cauldron_pool SET last_block = ${head.toString()}, indexed_at = ${nowSec()},
            last_price = ${lastPrice > 0 ? lastPrice : (await sql`SELECT last_price FROM cauldron_pool WHERE gen = ${gen}`)[0]?.last_price ?? 0}
            WHERE gen = ${gen}`;
}

/** DB-less fallback: bounded on-chain read (local dev). */
async function directRead(gen: number) {
  const poolId = (await client.readContract({ address: REGISTRY, abi: REGISTRY_ABI, functionName: "generationPoolId", args: [BigInt(gen)] })) as `0x${string}`;
  if (!poolId || /^0x0+$/.test(poolId)) return { pool: null, candles: [], last: 0 };
  const head = await client.getBlockNumber();
  const from = head > 45000n ? head - 45000n : 0n;
  const prices: number[] = [];
  let cur = from;
  while (cur <= head) {
    const to = cur + MAX_LOG_RANGE - 1n > head ? head : cur + MAX_LOG_RANGE - 1n;
    const logs = await client.getLogs({ address: POOL_MANAGER, event: SWAP, args: { id: poolId }, fromBlock: cur, toBlock: to });
    for (const l of logs) {
      const sp = l.args.sqrtPriceX96 as bigint | undefined;
      if (sp) { const p = ethPerToken(sp); if (p > 0 && Number.isFinite(p)) prices.push(p); }
    }
    cur = to + 1n;
  }
  const candles = prices.map((p, i) => ({ t: i, o: p, h: p, l: p, c: p, v: 0 }));
  return { pool: { gen, id: poolId }, candles, last: prices.length ? prices[prices.length - 1] : 0 };
}
