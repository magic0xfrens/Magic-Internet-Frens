# Off-chain liveness under chain misbehaviour (P5b)

Round-45 deploy-readiness review, 2026-09-15. Assembled by the orchestrator from hunter 5's
evidence (`hunt/H5_offchain_frontend.md` §6) and verifier 5's verdicts (`verify/V5_offchain_frontend.md`).
Every claim carries its source tag. The premise of this phase: the chain misbehaves in ways that are
NORMAL, not adversarial — depth-1 reorgs, providers briefly disagreeing, an endpoint serving an orphaned
block by number, 429s, 520s, a node lagging the tip. A routine Sepolia reorg took the entire read layer
down for ~25 minutes and no phase of the previous brief looked at this.

## 1. The incident this phase exists for

Sepolia reorged at block 11704817. The canonical LOGS were served correctly, while
`eth_getBlockByNumber` on some providers still returned the ORPHANED block for minutes afterwards.
Ponder treats a log/block hash disagreement as FATAL. The process died, restarted into the same
condition, and crash-looped. Provider behaviour during the event (VERIFIED, from the incident):

| provider | served during the reorg |
|---|---|
| tenderly gateway | the canonical block — the only one that was right |
| publicnode, 1rpc | the losing sibling |
| ankr, blastapi | neither |

## 2. What kills the indexer, and what it does next

- **Fatal class** (DERIVED, `indexer/ponder.config.ts:87-104`): a log whose `blockHash` disagrees with
  the block fetched for that height. Ponder treats it as unrecoverable.
- **Restart policy** (VERIFIED): `railway.json` — `ON_FAILURE`, max **10** retries, healthcheck `/health`.
  `/health` is Ponder's own liveness and returns 200 once the server is up, so it does NOT detect
  divergence. The divergence beacon is deliberately at `/freshness`
  (`indexer/src/api/index.ts:1280-1288`), because a 503 on the healthcheck route once deadlocked deploy
  promotion. After 10 failed restarts the service stays down until a human intervenes.
- **Crash loop**: yes, while the RPC list round-robins. **Fixed during this run** — see §5.
- **Self-heal**: an in-process watchdog (`indexer/src/api/index.ts:1291-1307`) calls `exit(1)` after
  roughly 9 minutes of sustained divergence, but only if the process was ever healthy. That gate is
  in-memory, so a container that boots straight INTO divergence never self-restarts and reports `ok`
  forever (finding R5E, CONFIRMED Medium). **Fixed during this run.**
- **Alerting**: none exists in the tree. `/freshness` is the only external signal, and nothing polls it
  except the browser and `scripts/deploy-round.mjs:76-91`. This remains an open gap.

## 3. What still works when the indexer is dark

Confirmed by reading the hooks (DERIVED). Everything on `useReadContract` keeps working, because it
reads the chain directly:

- swap widget balances and allowance; `progress` / `missStreak` / `oddsForPlay`
  (`CrystalCauldronGame.tsx:141-167`)
- perp position reads; presale price and supply (`useMiFrensPresale`)
- machine state (`useCauldronMachine`); floor reads
- **every write path** — the app can still transact with the indexer down

Dead without the indexer: candles, trade tape, activity feed, perp heatmap, collection floors,
proposals, iterations, gacha lifetime stats, seeding progress. `useIndexerHealth` shows a degraded
banner for `down` / `stale` / `syncing`, except in the boot-into-divergence case above.

## 4. Frontend RPC behaviour

VERIFIED from source, `src/config/chains.ts:141-145`: the Sepolia transport is a viem `fallback` over
`VITE_SEPOLIA_RPC_URL` (comma-split at `:92-93`) prepended to four public nodes, with per-endpoint
`retryCount: 2`. `sepolia.rpcUrls` is also overridden (`:107-113`) so chain-default paths cannot escape
the list. viem rolls over on error and 429.

- **Is it populated in production?** NOT VERIFIABLE from the repository. Nothing in `vercel.json`, no
  `.env.production`; `.env.vercel-backup` defines `VITE_CAULDRON_INDEXER` and `VITE_X_CLIENT_ID` but not
  `VITE_SEPOLIA_RPC_URL`. **Action for the operator: check that variable in the Vercel dashboard before
  the round-45 deploy.** Without it the app runs on public nodes only.
- **Can a rollover spoof `minOut`?** No (VERIFIED). The `spotPrice` that feeds `minOut` comes from the
  indexer, not from these nodes (`SwapWidget.tsx:215-217`). A provider rollover changes balance,
  allowance and `priceWeiLive` reads, where a lagging node causes a revert rather than a bad price.
- **Arc**: `targetChain` gets a single `http(RPC_URL)` with **no fallback**. One endpoint, no rollover.

## 5. Keeper and operator scripts

VERIFIED from source. `scripts/keeper.sh` requires `contracts/solidity/.env.sepolia` (`:31`) and resolves
the signer through `scripts/lib/signer.sh`; a keystore is preferred and the raw `PRIVATE_KEY` fallback
announces itself, so with `KEYSTORE_ACCOUNT` set no key appears in argv or `ps`. Addresses are
cross-checked against the manifest case-insensitively and the script exits on drift (`:45-48`).

**Reorg safety: no double action.** Keeper actions are idempotent checks re-derived from chain state
(`isLiquidatable` then `liquidate`), sends are sequential and each waits on `cast send`, so a
reorged-out liquidation is simply re-detected on the next sweep. `indexer/seed-keeper.mjs` holds
`SEED_KEEPER_PK` from the environment, uses only the FIRST `PONDER_RPC_URL` entry (`:81-84`), guards
overlap with an `inFlight` latch (`:93-97`), simulates before sending, waits for the receipt with a
120 s timeout, and wraps everything in try/catch so it cannot take the indexer down. A reorged-out
`poke` is re-derived from `placedWad` on the next tick.

Weaknesses: every `cast send` was silenced with `>/dev/null 2>&1` (R5G, Low — addressed this run), and
the sweep is an O(nextId) scan that grows with position count (logged, not fixed).

Note: `scripts/market-round.mjs`, named in the review brief, **does not exist**. The market-move helper
is `scripts/marketmaker.sh`.

## 6. RECOVERY RUNBOOK — the indexer is 502ing or the app says "indexer unreachable"

1. **Confirm what is actually broken.** `curl -s <indexerUrl>/freshness` and compare against
   `/health`. `/health` returning 200 means the server is up, not that data is good. `/freshness` is the
   divergence and lag beacon. If `/freshness` reports behind-but-moving, it is syncing: wait.
2. **Identify the honest provider.** Take the block height the indexer died on. For each candidate
   endpoint, fetch block `N` and block `N+1` and check that `N+1`'s `parentHash` equals `N`'s hash. A
   provider that fails this is serving an orphan. During the 11704817 event only the tenderly gateway
   passed.
3. **Pin it.** Set `PONDER_RPC_URL` on the Railway service to that ONE provider, then `railway up`.
   Do not set a comma-separated list while recovering: the point is to stop two providers disagreeing.
4. **A clean schema bump alone does NOT help.** `indexer/start.mjs:14-19` only chooses the Postgres
   schema; the bad data arrives live from the RPC. Re-indexing into a fresh schema from a provider that
   serves an orphan reproduces the same fault. This was tried during the incident and is a useful
   negative result. Bump the schema only if you also pinned a good provider.
5. **If the service is fully stopped**, check whether the 10-retry cap in `railway.json` was exhausted;
   it will not restart itself after that.
6. **Tell users nothing is lost.** Every write path and all on-chain reads keep working with the
   indexer down (§3). The outage is a read-layer outage, not a protocol outage.

## 7. Findings, severity-tagged

| id | severity | status | what |
|---|---|---|---|
| R5C | Medium (downgraded from High) | FIXED this run | `ponder.config.ts:107-121` defaulted to a 5-provider round-robin — the exact configuration its own comment at `:101-105` blames for the fatal crash-loop. `start.mjs` never set `PONDER_RPC_URL`, so the default was live. Now a single pinned provider by default, with ordered failover for a list. |
| R5E | Medium | FIXED this run | `indexer/src/api/index.ts:1260` — `everHealthy` gating let a container that boots into divergence report `ok` forever and never self-restart. |
| R5F | Low | FIXED this run | `GET /candles/abc` returned HTTP 500 leaking `/app/node_modules/pg-pool/index.js:45:11`, unauthenticated. |
| R5G | Low | partly fixed | `scripts/keeper.sh:59,:71` silenced every `cast send` failure. The O(nextId) sweep at `:63` is logged, not fixed. |
| — | Low | OPEN | No alerting on `/freshness`. Nothing polls it; an outage is discovered by a user. |
| — | Low | OPEN | `railway.json` 10-retry cap means a sustained fault ends in a stopped service needing manual recovery. Left deliberately unchanged: more retries do not help a crash loop whose cause is the RPC. |
| — | — | NOT VERIFIABLE | Whether `VITE_SEPOLIA_RPC_URL` is populated in the Vercel production environment, and whether `PONDER_RPC_URL` is pinned on Railway. Both must be checked in the hosting dashboards before the round-45 deploy. |
