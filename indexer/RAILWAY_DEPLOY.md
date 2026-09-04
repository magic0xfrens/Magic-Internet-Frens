# Deploy the Cauldron indexer on Railway (~€5/mo)

The indexer is the single source of truth for all frontend data: charting
(candles/swaps), collections, NFT mints + rarity, holders, gacha stats, and
governance. Host it on Railway with a Postgres addon.

## Steps
1. **New Railway project** → "Deploy from GitHub repo" → point at this repo,
   set the **root directory** to `indexer/`.
2. **Add a Postgres** (Railway → New → Database → PostgreSQL). Railway injects
   `DATABASE_URL` into the service automatically.
3. **Set service env vars** (Variables tab):
   - `CHAIN_ID=11155111` (Sepolia; 4663 for Robinhood mainnet later)
   - `PONDER_RPC_URL=<your Sepolia RPC>` (a paid RPC is recommended for reliability)
   - `START_BLOCK=11523400`
   - `CANDLE_SECONDS=30`
   - `REGISTRY_ADDRESS=0x09579fbb9657322012c0c155f5af95eecca4010b`
   - `POOL_MANAGER_ADDRESS=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`
   - `PRESALE_ADDRESS=0x66ab0548468c3c32742a015a2796155b1ea7133d`
   - `HOOK_ADDRESS=0x4f44adc0cec3a48ccff17242b7ad336a707cd0cc`
   - `GOVERNOR_ADDRESS=0x999690fcb850a844715e760974e3d259cbaadf22`
   - `DATABASE_SCHEMA=cauldron_prod`
   - `CORS_ORIGIN=https://your-frontend-domain` (or `*`)
4. **Deploy.** Railway runs `npx ponder start --schema $DATABASE_SCHEMA` (see
   railway.json) and exposes a public URL.
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

On each redeploy of the contracts, update the `*_ADDRESS` + `START_BLOCK` vars
and bump `DATABASE_SCHEMA` (e.g. cauldron_prod2) to reindex cleanly.
