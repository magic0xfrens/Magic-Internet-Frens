# Deploy the Cauldron indexer on Railway (~€5/mo)

The indexer is the single source of truth for all frontend data: charting
(candles/swaps), collections, NFT mints + rarity, holders, gacha stats, and
governance. Host it on Railway with a Postgres addon.

## Steps
1. **New Railway project** → "Deploy from GitHub repo" → point at this repo,
   set the **root directory** to `indexer/`.
2. **Add a Postgres** (Railway → New → Database → PostgreSQL). Railway injects
   `DATABASE_URL` into the service automatically.
3. **Set service env vars** (Variables tab). Only these — chain id, addresses,
   start blocks and the schema all come from `deployments/round.json`, NOT from
   env. Setting `DATABASE_SCHEMA` / `*_ADDRESS` / `START_BLOCK` here does
   nothing; nothing reads them.
   - `PONDER_RPC_URL=<your Sepolia RPC>` (a paid RPC is recommended; comma-separate for a pool)
   - `CORS_ORIGIN=https://your-frontend-domain` (or `*`)
   - optional: `POLLING_INTERVAL_MS`, `PONDER_MAX_RPS`, `STRICT_POOL_FILTER`
4. **Deploy.** Railway runs `node start.mjs` (see railway.json), which reads
   `deployments/round.json` and execs `ponder start --schema <round.json schema>`,
   then exposes a public URL.
5. **Point the frontend** at it: set `VITE_CAULDRON_INDEXER=https://<railway-url>`
   in the MiFrens app's Vercel env. The frontend then reads candles/NFTs/
   collections/gacha/proposals from the indexer.

## Endpoints
- `GET /candles/:gen` · `GET /recent/:gen` — charting
- `GET /collections` — every collection + totalMinted
- `GET /nfts/:owner` — a wallet's NFTs (across all collections)
- `GET /collection/:address/nfts` — a collection's NFTs
- `GET /gacha/:player` — wins / misses / committed
- `GET /proposals` — governance
- `GET /graphql` — everything, typed

On each redeploy of the contracts, edit `deployments/round.json` only —
addresses, `blocks`, and `schema`.

**Bump `schema` whenever `ponder.config.ts`, `ponder.schema.ts` or `src/` changed
since the last bump.** Ponder fingerprints those three inputs into a `build_id`
and refuses to attach to a schema written by a different one:

> NonRetryableError: Schema 'X' was previously used by a different Ponder app.

That error is fatal and non-retryable, so the container crash-loops until
Railway's `restartPolicyMaxRetries` (10) is spent and the service stays down.
Same code + same `schema` = resume (crash recovery, no wipe); new `schema` =
clean reindex. Old schemas linger in Postgres — once the new one is serving,
reclaim the space with `DROP SCHEMA "cauldron_r44d" CASCADE;`.
