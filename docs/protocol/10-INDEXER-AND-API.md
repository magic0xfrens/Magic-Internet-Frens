# 10 — Indexer and API

Two separate services sit off-chain.

1. **The Ponder indexer** (`indexer/`) ingests contract events into Postgres and
   serves the app's entire read layer over HTTP. Deployed to Railway.
2. **Vercel serverless routes** (`api/`) serve NFT metadata, per-round branding
   and two LLM-backed endpoints. They share the site's domain.

---

## 1. The indexer

### 1.1 What it ingests

Ponder is configured from the shared manifest, never from environment variables
(`indexer/ponder.config.ts:12-17`). A `CHAIN_ID` env var is deliberately absent
so the indexer cannot point at a different network than the manifest it serves
addresses for (`:19-22`).

| Registered contract | Address source | ABI |
|---|---|---|
| `CauldronRegistry` | `contracts.registry` | `abis/RegistryAbi.ts` |
| `RegistryColl` | same address | `abis/GachaGovAbi.ts` |
| `RegistryFloor` | same address | `abis/FloorAbi.ts` |
| `HookFloor` | `contracts.hook` | `abis/FloorAbi.ts` |
| `PoolManager` | `contracts.poolManager` | `abis/PoolManagerAbi.ts` |
| `Governor` | `contracts.governor` | `abis/GachaGovAbi.ts` |
| `Seeder` | `contracts.seeder`, else `0x0` | `abis/SeederAbi.ts` |
| `Hook` | `contracts.hook` | `abis/GachaGovAbi.ts` |
| `Dividend` | `contracts.dividend` | `abis/DividendAbi.ts` |
| `PerpEngine` | `contracts.perpEngine` | `abis/PerpEngineAbi.ts` |
| `Presale` | `contracts.presale` | `abis/CollectionAbi.ts` |
| `Collection` | **factory pattern** on `CollectionDeployed` | `abis/CollectionAbi.ts` |

(`indexer/ponder.config.ts:98-157`.) All start at `blocks.indexer`
(`:23`). Per-iteration collections are discovered automatically from the
registry's `CollectionDeployed(uint256,address,uint8)` event, so one handler set
covers every future brew (`:148-157`).

Two registrations are defensive rather than live. The seeder falls back to the
zero address on a manifest that predates it and then yields no logs
(`:38-42`); the perp engine is described the same way (`:140-142`).

**The PoolManager is not filtered to a pool id.** The filter was removed because
a pool id is derived from the generation's token address, the token is
redeployed at every relaunch, and the manifest is baked into the container at
build time — so the id was always one deploy stale and the indexer filtered
Swaps to the *previous* generation's dead pool (`:106-127`). Measured before
removal: 88 Swap logs per 2000 Sepolia blocks across every V4 pool.
`STRICT_POOL_FILTER=true` restores the old behaviour and the manual step with
it (`:128-131`).

Event handlers are registered in `indexer/src/index.ts` — 42 of them, covering
the registry lifecycle (`:67-73`), collections and transfers (`:75-150`), the
gacha (`:152-168`), governance (`:170-192`), the dividend (`:194-204`),
migration (`:207-208`), swaps (`:271`), the perp engine (`:327-402`), the
redemption and collection floors (`:458-540`), the proposer flywheel (`:542`)
and the launch seeder (`:580-628`).

### 1.2 Schema

`indexer/ponder.schema.ts` defines 19 tables.

| Table | Purpose | Line |
|---|---|---|
| `pool` | one row per pool, with `quote` and `isPrimary` | `:4` |
| `candle` | OHLC buckets | `:29` |
| `swap` | every swap, ordered by `orderKey = block*1e6 + logIndex` | `:42` |
| `collection` | one per deployed collection | `:61` |
| `nft` | one per token, with `isLiquidatoor` | `:71` |
| `holder` | balance per (collection, address) | `:88` |
| `gacha_player` | wins / misses / committed | `:96` |
| `proposal`, `vote` | brew governance | `:105`, `:115` |
| `enchant` | per genesis tokenId, spell state | `:124` |
| `dividend_stat` | singleton lifetime fee flows | `:132` |
| `perp_position` | one per opened position, with a computed `liqPrice` | `:144` |
| `liquidator` | kill + badge leaderboard | `:171` |
| `perp_stat` | per generation open interest | `:181` |
| `iteration` | per-generation migration totals | `:192` |
| `genesis_floor`, `floor_event` | redemption floor state and log | `:207`, `:219` |
| `collection_floor`, `collection_floor_event` | legacy floor | `:234`, `:243` |
| `proposer_earning` | proposer flywheel | `:255` |
| `seed_event`, `seed_state` | launch seeding tape and live singleton | `:267`, `:285` |

`swap.orderKey` exists because several swaps can share one block — a
liquidation fires multiple buy-backs atomically — and ordering by timestamp
scrambles the candle close (`:53-57`).

**`iteration.burned` is always 0.** No contract emits `UnclaimedBurned`, so
nothing writes it. The column is kept so the API field does not vanish under a
live UI, and the schema says in so many words that it must not be presented as
live data (`indexer/ponder.schema.ts:197-200`). Commit `7890490` removed the
dead handler.

### 1.3 The HTTP API

Hono app, mounted by Ponder. `CORS_ORIGIN` defaults to `*`
(`indexer/src/api/index.ts:11`). Every GET without its own `Cache-Control` gets
`public, max-age=5, s-maxage=5, stale-while-revalidate=30` (`:25-31`).

GraphQL is mounted at both `/graphql` and `/` (`:115-116`). Both are guarded by
a body cap, `MAX_GRAPHQL_BYTES` (default 8000, `:52`): a missing
`Content-Length` is a 411, a declared oversize is a 413, and the real body is
then measured by reading a **clone** of the request stream with an early abort
so the check itself cannot be turned into memory exhaustion (`:69-112`). The
comment records that the cap was originally registered only on `/graphql`, so
`POST /` reached the same unbounded resolver.

All read routes are `GET` and **unauthenticated**. There is no rate limiting in
the app; the code says real limiting belongs in the WAF.

| Route | Params | Serves |
|---|---|---|
| `/presale` | — | mint progress (`:374`) |
| `/treasury` | — | treasury balances, 30 s cache (`:422`) |
| `/floor` | — | genesis redemption floor, 4 s cache (`:533`) |
| `/collection-floors` | — | legacy floors, live chain reads, 5 s cache (`:591`) |
| `/cauldron` | — | live generation summary (`:664`) |
| `/candles/:generation` | `?limit` ≤ 500, default 120 | OHLC (`:713`) |
| `/recent/:generation` | `?limit` ≤ 5000, default 150 | trade tape (`:723`) |
| `/perp-heatmap/:generation` | — | engine stats + liquidation buckets (`:822`) |
| `/perp-positions/:trader` | — | a wallet's open positions (`:882`) |
| `/perp-rekt/:trader` | — | liquidation history (`:896`) |
| `/freshness` | — | divergence beacon, 200 or 503 (`:989`) |
| `/perp-vault` | — | vault totals, 5 s cache (`:1033`) |
| `/perp-vault/:user` | — | a user's vault position (`:1034`) |
| `/perp-liquidators` | `?limit` ≤ 200, default 50 | leaderboard (`:1059`) |
| `/perp-kills/:wallet` | — | a wallet's kills (`:1070`) |
| `/collections` | — | every indexed collection (`:1085`) |
| `/nfts/:owner` | `?limit` ≤ 2000, default 500 | a wallet's NFTs (`:1094`) |
| `/collection/:address/nfts` | `?limit` ≤ 2000, default 200 | a collection's NFTs (`:1101`) |
| `/gacha/:player` | — | player gacha stats (`:1109`) |
| `/liquidity` | — | real LP depth, 8 s cache (`:1136`) |
| `/seeding` | `?limit` default 25 | seed state + tape (`:1230`) |
| `/dividend` | — | lifetime dividend totals (`:1284`) |
| `/enchants/:owner` | — | spell state per token (`:1296`) |
| `/iterations` | — | per-generation rows (`:1303`) |
| `/proposals` | — | brew proposals by votes (`:1356`) |
| `/floor/history` | `?gen`, `?limit` ≤ 500 | floor event log (`:1379`) |
| `/proposers` | — | proposer flywheel leaderboard (`:1406`) |

Several routes do live chain reads server-side with the API's own RPC pool so
the browser never touches RPC (`:118-120`, and e.g. `/perp-vault` at
`:56-73`). `API_RPC_URL` is a pool kept separate from the Ponder sync pool so a
backfill cannot starve it (`.env.example`, "Dedicated pool for the API's own
chain reads").

**Duplicate route.** `/collection-floors` is registered twice — at
`indexer/src/api/index.ts:591` (live chain reads, cached) and again at `:1394`
(a plain table dump). Hono matches in registration order, so `:591` answers
every request and the handler at `:1394` is unreachable. The two return
different shapes (`{floors, events}` vs the cached object), so this is worth
resolving rather than leaving.

### 1.4 Health and freshness

Two different endpoints, deliberately.

- **`/health`** is Ponder's built-in liveness path and is **not** overridden.
  The comment at `indexer/src/api/index.ts:985-989` records why: overriding it
  with the divergence check, which can 503 during a fresh backfill, deadlocked
  Railway's deploy promotion.
- **`/freshness`** is the deeper beacon. It returns `{ok, chainGen, indexedGen,
  curPoolId, indexedPools, chainOpenPositions, dbOpenPositions, reasons:
  {poolMismatch, missedLaunch, missedOpens}, divergingForMs, warmingUp}` with a
  200 or a 503 (`:966-972,989-992`).

Two guards keep it honest. `ok` is only false once the service has been healthy
at least once (`everHealthy`) **and** the divergence has outlived the grace
period — a fresh backfill legitimately has `dbOpen < chainOpen` for its whole
duration (`:960-964`). Any exception reports `ok: true, warmingUp: true` rather
than a 500, so a startup blip never blocks a deploy (`:974-981`).

An in-process **watchdog** polls the same evaluation every 30 s and
`process.exit(1)`s after roughly three grace periods of sustained divergence, so
Railway's `ON_FAILURE` policy restarts into a fresh sync. It arms only after the
service has been healthy once, and `HEALTH_WATCHDOG=0` disables it
(`:995-1012`).

The frontend consumes `/freshness` in `src/hooks/useIndexerHealth.ts:38` — see
09-FRONTEND §3.3.

### 1.5 Process shape

`npm start` runs `node start.mjs` (`indexer/package.json:7`), which reads the
schema name out of the manifest, validates it against `^[a-z0-9_]+$`, starts the
seed keeper in the same process, and then execs `npx ponder start --schema
<schema>` (`indexer/start.mjs:11-31`). Hardcoding `--schema` in `railway.json`
is called out as having silently pinned the indexer to a dead schema in past
rounds (`:1-6`). Bumping `schema` in `round.json` forces a clean reindex;
leaving it forces a resume.

---

## 2. Serverless API routes

Six routes under `api/`. `vercel.json` rewrites `/api/(.*)` to the functions and
everything else to `index.html`; the security headers it sets (`X-Frame-Options:
DENY`, a `frame-ancestors 'none'` CSP, `nosniff`, `no-referrer`) apply to the
HTML routes, not to `/api/*`.

### 2.1 Summary

| Route | Methods | Auth | Rate limit | Operator cost when called |
|---|---|---|---|---|
| `/api/brand` | GET, POST, OPTIONS | GET: **none**. POST: EIP-191 signature from `BRAND_SIGNERS` + Origin allowlist | none | a Neon query per GET; a bounded row write per POST |
| `/api/fren-ask` | POST | **none** | 10 req / 30 s per IP, in-memory | **an LLM call** (Groq or Gemini) + a docs fetch + a Neon query |
| `/api/fren-teach` | GET, POST, DELETE | shared secret header `x-fren-admin` vs `FREN_ADMIN_SECRET` | 5 *failed* attempts / 60 s per IP | a Neon query |
| `/api/x-token` | POST | **none** — `redirect_uri` allowlist only | 10 req / 60 s per IP | two upstream X API calls on the operator's `X_CLIENT_SECRET` |
| `/api/cauldron/liquidatoor` | any (no method check) | **none** | none | one `eth_call` per uncached badge |
| `/api/cauldron/unrevealed` | any | **none** | none | none — a static JSON body |

All four in-memory limiters are per warm serverless instance, not global. Each
file says so (`api/fren-ask.ts:135-138`, `api/fren-teach.ts:43-45`).

### 2.2 `/api/brand`

Per-iteration PFP, banner and website for the profile card, stored in its own
Neon table (`cauldron_brand`) rather than in Ponder, which resets on reindex
(`api/brand.ts:8-11`).

- `GET ?gen=N` → `{logo, banner, website}`, all null when `DATABASE_URL` is
  unset (`:99-112`). `Access-Control-Allow-Origin: *`, cached
  `s-maxage=30` (`:100,108`).
- `POST {gen, logo, banner, website, ts, sig}` → `{ok:true}`.

The write is gated five ways, in this order (`:116-181`):

1. A request carrying an `Origin` not in `BRAND_ALLOWED_ORIGINS` is refused 403.
   A request with **no** `Origin` header — curl, a server — skips this check;
   the signature is what actually authorises (`:117-120`).
2. No `BRAND_SIGNERS` configured → 503. The route **fails closed** (`:121-123`).
3. `gen` must be an integer in `[0, round + 16]` (`:57-59,66-68`).
4. `ts` must be within 10 minutes (`SIG_TTL_MS`, `:54,135-137`) and `sig` must
   match `^0x[0-9a-f]{130}$` (`:138-140`).
5. `recoverMessageAddress` over a message that commits to `gen`, the **sha256 of
   each image**, the website and `ts` (`:70-85,156-164`), then membership in
   `BRAND_SIGNERS` (`:165`).

After that, `updated_at` must strictly increase (409 otherwise) and new rows are
capped at `BRAND_MAX_ROWS`, default 256, with a 507 (`:171-181`).

The header records what this replaced: the POST destructured only `{gen, logo,
banner, website}` and never read `sig`, so any stranger could rewrite the live
site's branding, with `Access-Control-Allow-Origin: *` on the write
(`:16-21`). Fixed in commit `b502cac`. **This is the doc-comment-describing-a-
check-that-did-not-exist case; the check exists now.**

Images are capped at 3,500,000 characters each (~2.5 MB as a data URL, `:149-154`).

### 2.3 `/api/fren-ask` — LLM-backed

`POST {question, history?}` → `{answer, source}` where `source` is `groq`,
`gemini` or `fallback` (`api/fren-ask.ts:379-443`). `maxDuration` is 30 s
(`:26`).

**No authentication.** The only guard is the per-IP limiter: 10 requests per
30 s window, 429 with `Retry-After: 30` (`:139-140,190-194`). This matters
because each call costs an LLM invocation. The bucket key is chosen carefully —
`x-real-ip` first, otherwise the **rightmost** `x-forwarded-for` hop, never the
leftmost, because a client sets its own headers and proxies append rather than
replace, so the leftmost value is attacker-chosen and rotating it per request
defeats the limiter with one extra header (`:143-166`). Commit `fec94bf`
brought this route in line with `fren-teach`, which already did it.

Untrusted input is handled in three places:

1. **The question** is coerced to a string, truncated to 800 characters and
   trimmed; `history` is truncated to the last 6 turns and each turn to 1200
   characters (`:196-199`, `:268`, `:291`).
2. **The docs** are fetched from a pinned origin. `CAULDRON_DOCS_ORIGIN` when
   set, otherwise the platform-set `VERCEL_PROJECT_PRODUCTION_URL` /
   `VERCEL_URL`. **No request header participates**, the fetch uses
   `redirect: "error"`, requires a `text/*` content type, times out at 8 s and
   truncates at 200,000 characters (`:71-103`). The header records that this
   previously built the URL from `x-forwarded-host`, which Vercel does not
   strip — one extra header redirected the fetch to any server the caller named
   and its bytes became the "source of truth" block of the system prompt
   (`:56-69`). Fixed in commit `3c7d009`.
3. **Prompt-injection framing.** The docs block is wrapped in BEGIN/END markers
   and the system prompt instructs the model to treat everything between them as
   untrusted data to quote and never as instructions, naming role changes,
   prompt disclosure and redirection to another site/contract/wallet as
   directives to ignore (`:214-226`).

Owner-saved corrections from Neon are injected as an "AUTHORITATIVE CORRECTIONS"
block, ranked by word overlap against the question, top 10 of the most recent 40
(`:105-133,227-230`). **Corrections are trusted content** — they are written
only through the admin-gated `/api/fren-teach`.

With no `GROQ_API_KEY` and no `GEMINI_API_KEY` the route returns
`{answer:null, source:"fallback"}` and the widget uses its offline knowledge
base (`:207-210`). Any exception degrades the same way (`:240-246`). Groq is
tried first; Gemini walks a model chain and falls through on 429 or 404
(`:232-239`, `:308-331`).

### 2.4 `/api/fren-teach` — the write side of the LLM memory

`POST {question, answer}` saves a correction; `GET` lists up to 200; `DELETE
{id}` removes one. All require the `x-fren-admin` header
(`api/fren-teach.ts:85-89`).

The secret comparison hashes both sides to sha256 first and then uses
`timingSafeEqual`, because `===` leaks length and first-difference position
through timing while `timingSafeEqual` throws on a length mismatch — which would
leak the length by itself (`:23-35`).

Failed attempts are throttled at 5 per 60 s per IP with the same rightmost-hop
IP derivation (`:47-83,111-121`). The header is explicit that this is an
unauthenticated brute-force surface in front of a write path that feeds the
Guide's system prompt (`:37-46`).

With `FREN_ADMIN_SECRET` unset the route is 503 and `authed()` returns false, so
teaching is disabled (`:86,107-110`). Inputs are truncated to 800 / 4000
characters (`:150-151`).

### 2.5 `/api/x-token` — X OAuth 2.0 PKCE proxy

`POST {code, code_verifier, redirect_uri}` → `{access_token, user}`. It exists
because X's token endpoint blocks browser CORS (`api/x-token.ts:4-5`).

**No caller authentication.** Two guards stand in for it:

- `redirect_uri` must be exactly in `X_REDIRECT_URIS`; an empty allowlist is a
  503 rather than a pass (`:16-17,58-63`).
- 10 requests per 60 s per IP, same rightmost-hop derivation (`:19-42,48-51`).

It then calls `https://api.x.com/2/oauth2/token` with HTTP Basic
`VITE_X_CLIENT_ID:X_CLIENT_SECRET`, and on success `GET /2/users/me`
(`:73-99`). The cost of a call is therefore two upstream requests billed against
the operator's X app. The header states the pre-fix position plainly: the route
took any `redirect_uri` and forwarded it, unthrottled, with the client
credentials attached (`:7-12`). Fixed in commit `fec94bf`.

### 2.6 `/api/cauldron/liquidatoor`

Renders a Liquidatoor badge's metadata and a self-contained SVG data URI, with
the facts read from chain state rather than invented
(`api/cauldron/liquidatoor.ts:5-22`).

- Input: `?id=<tokenId>` (or the last path segment), stripped to digits
  (`:178-180`); `?col=<collection>`.
- `?col=` is checked against an allowlist built from
  `deployment.contracts.collection` plus `LIQUIDATOOR_COLLECTIONS`; an unknown
  address is a 400 (`:189-197`). Before commit `b9e4583` any address at all was
  accepted, so the route would read `liqStats` off a contract the caller
  deployed and render its answer as a badge (`:184-188`).
- One `eth_call` to `liqStats(uint256)` through a viem `fallback` of
  `API_RPC_URL` or three public Sepolia nodes (`:29-37,79-94`). Only ids at or
  above `LIQUIDATOR_ID_BASE = 1_000_000n` are read (`:27,202`).
- A resolved badge is cached `s-maxage=31536000, immutable`; an unresolved one
  for 30 s, so a badge minted seconds ago is not pinned to "unavailable"
  (`:204-212`).
- Text interpolated into the SVG is escaped for `&`, `<`, `>` (`:101-102`).
- `Access-Control-Allow-Origin: *`, no method check (`:175`).

**Doc/code disagreement.** The comment at `:182-183` says the collection
"Defaults to the genesis collection", and the allowlist at `:190-191` is built
from `deployment.contracts.collection` — but the fallback actually used when
`?col=` is absent or malformed is `deployment.contracts.presale` (`:198-200`).
On the current manifest those are two different addresses:
`collection = 0x09be0DFc…` and `presale = 0x9589089c…`
(`indexer/deployments/round.json:19,27`). So a caller can never *name* the
presale collection (it is not on the allowlist), yet it is the default that is
read. This should be reconciled.

### 2.7 `/api/cauldron/unrevealed`

A static JSON body for every sealed crystal across every iteration — the URI is
a constant in `CauldronCollection`, not per token
(`api/cauldron/unrevealed.ts:4-13`). No inputs, no chain reads,
`Access-Control-Allow-Origin: *`, cached `s-maxage=86400,
stale-while-revalidate=604800` (`:16-17`). Cheapest route in the tree.

---

## Verification

- `git rev-parse --short HEAD` → `20d6de2`
- Disagreements found:
  1. `/collection-floors` is registered twice in `indexer/src/api/index.ts`
     (`:591`, `:1394`) with different response shapes; the second is
     unreachable.
  2. `api/cauldron/liquidatoor.ts` comments say the default collection is the
     genesis collection, but the code defaults to `contracts.presale` while the
     allowlist is built from `contracts.collection`.
  3. `iteration.burned` is documented in the schema as permanently 0 and must
     not be rendered as live data (`indexer/ponder.schema.ts:197-200`).
- Not verified: the exact JSON field names returned by routes other than
  `/freshness`, `/perp-vault`, `/collection-floors` and `/proposers` — those
  handler bodies were not read in full.
