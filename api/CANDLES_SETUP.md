# Cauldron price chart — serverless + Neon (free, scales to 1000+ viewers)

The Cauldron page's live price chart is served by **`/api/candles`** — a Vercel
serverless function backed by a free **Neon Postgres**. It never recomputes
history: it incrementally indexes only *new* swaps since the pool's last block,
and the response is CDN-cached so a thousand viewers collapse to ~1 origin hit
per cache window.

```
[Vercel edge cache] ← s-maxage=15, stale-while-revalidate=60
        │  (serves ~all traffic)
[/api/candles?gen=N] ──incrementally indexes new swaps──▶ [Neon Postgres]
        │  (SELECT candles)                                 pool / candle tables
        └──▶ { pool, candles:[{t,o,h,l,c,v}], last }
[Cauldron chart] fetches /api/candles?gen=N   (getLogs fallback if the API is down)
```

## Setup (one-time, ~3 min, all free tiers)

1. **Create a Neon database** → https://neon.tech (free tier). Copy the
   connection string (`postgres://…`).
2. **Add Vercel env vars** (Project → Settings → Environment Variables):
   - `DATABASE_URL` = the Neon connection string (required for persistence)
   - `SEPOLIA_RPC` = your Sepolia RPC (optional; defaults to publicnode)
   - `REGISTRY_ADDRESS` = `0x51056e25be0b07e398c21535be6caa84d42f9a33`
   - `POOL_MANAGER_ADDRESS` = `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`
   - `START_BLOCK` = `11520000`
   - `CANDLE_SECONDS` = `300` (5-minute candles)
3. **Deploy.** The function auto-creates its tables on first call. Done.

The schema (auto-created): `cauldron_pool(gen, pool_id, last_price, last_block…)`
and `cauldron_candle(pool_id, bucket, o,h,l,c,v,n)`.

## Local dev
`vite` doesn't run Vercel functions, so locally the chart uses the **on-chain
getLogs fallback** automatically (no setup). To exercise the real function
locally, run `vercel dev` with `DATABASE_URL` set. Without `DATABASE_URL` the
function still returns a chart via a bounded direct on-chain read (no persistence).

## Why this scales
- **CDN cache** absorbs virtually all reads (`s-maxage`+`stale-while-revalidate`).
- **Incremental indexing** keeps each getLogs tiny (only new blocks), so it never
  hits public-RPC range limits.
- **Idempotent upserts** (`ON CONFLICT`) make concurrent revalidations safe.

## Alternative: full Ponder indexer
A complete Ponder indexer also lives in `indexer/` (OHLC candles, GraphQL, live
tape). To use it instead, host it on any always-on Node service + Postgres and
set `VITE_CAULDRON_INDEXER=<its url>` — the frontend will prefer it over
`/api/candles`. The serverless route is the zero-infra default.
