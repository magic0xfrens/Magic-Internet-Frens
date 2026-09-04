# Cauldron Indexer (Ponder)

Indexes the eternal Cauldron's price + volume from Uniswap V4 Swap events and
serves OHLC candles per generation. Powers the live chart on the MiFrens
Cauldron page.

## Run locally
```
cp .env.example .env.local
npm install
npm run dev          # PGlite (no DB needed) — API at http://localhost:42069
```

## API
- `GET /candles/:generation?limit=120` → `{ pool, candles:[{t,o,h,l,c,v}], last, volumeEth, swapCount }`
- `GET /recent/:generation?limit=30`   → latest raw swaps (live tape)
- `GET /graphql`                        → auto GraphQL over pool/candle/swap

## Frontend wiring
Set `VITE_CAULDRON_INDEXER=<indexer url>` in the MiFrens app. The chart reads
candles from the indexer and falls back to on-chain getLogs when unset/down.

## Deploy
Ponder is a long-running Node service — it CANNOT run on Vercel serverless.
Host the indexer on any always-on Node host (Ponder Cloud, Render, Fly.io,
Railway, a VPS) pointed at a Postgres (Neon / Supabase / Vercel Postgres via
DATABASE_URL). The Vercel frontend just reads the API over HTTP.
Env: CHAIN_ID, PONDER_RPC_URL, REGISTRY_ADDRESS, POOL_MANAGER_ADDRESS,
START_BLOCK, CANDLE_SECONDS, DATABASE_URL, CORS_ORIGIN.
