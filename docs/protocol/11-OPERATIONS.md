# 11 — Operations

Running the off-chain half: environment, the keeper loops, the operator
scripts, and how to tell whether it is working.

Nothing in this document prints a secret. Where a secret exists it is named by
variable only.

---

## 1. Environment variables

Every variable below was read from the code that consumes it. `.env.example`
states that **all of them are optional for a read-only local run**: contract
addresses come from the committed manifest and the frontend falls back to the
manifest's indexer URL.

### 1.1 Frontend (Vite, baked at build time)

| Variable | Purpose | Read at |
|---|---|---|
| `VITE_NETWORK` | `testnet` (Sepolia) or `mainnet`; one flip retargets config, wallet switching, explorer links and copy | `src/config/chains.ts:85-90` |
| `VITE_SEPOLIA_RPC_URL` | Comma-separated Sepolia RPCs, tried first in a viem `fallback` chain; rotating several free keys multiplies the effective limit | `src/config/chains.ts:63-71` |
| `VITE_WALLETCONNECT_PROJECT_ID` | WalletConnect Cloud id; without it only injected wallets are offered and the connector is not constructed at all | `src/config/chains.ts:43-49` |
| `VITE_ROBINHOOD_CHAIN_ID` | Mainnet chain id override; anything not a positive integer falls back to 4663 | `src/config/chains.ts:19-20` |
| `VITE_ROBINHOOD_RPC_URL` | Mainnet RPC | `src/config/chains.ts:22-23` |
| `VITE_ROBINHOOD_EXPLORER` | Mainnet block explorer | `src/config/chains.ts:25-26` |
| `VITE_X_CLIENT_ID` | X OAuth client id, also read server-side by the token proxy | `api/x-token.ts:65` |

`VITE_CAULDRON_INDEXER` is documented in `.env.example` but **the code does not
read it**: `src/config/cauldron.ts:39-46` takes `round.indexerUrl` from the
manifest and explicitly states there is no env override. Treat the
`.env.example` entry as stale.

### 1.2 Indexer (Ponder / Railway)

| Variable | Purpose | Read at |
|---|---|---|
| `DATABASE_URL` | Postgres connection; unset falls back to in-memory SQLite | `indexer/ponder.config.ts:45-47` |
| `PONDER_RPC_URL` | Comma-separated sync RPCs. **Not a free Alchemy key** — its 10-block `eth_getLogs` cap crashes Ponder's sync | `indexer/ponder.config.ts:58-77` |
| `POLLING_INTERVAL_MS` | Block poll cadence; default 4000 on Sepolia, 1000 on chain 4663 | `indexer/ponder.config.ts:86-88` |
| `PONDER_MAX_RPS` | Per-endpoint request cap; default `12 × endpoints` | `indexer/ponder.config.ts:91-94` |
| `STRICT_POOL_FILTER` | `true` restores the pool-id Swap filter, and the per-relaunch manual edit with it | `indexer/ponder.config.ts:128` |
| `API_RPC_URL` | Dedicated RPC pool for the API's own chain reads | `api/cauldron/liquidatoor.ts:29`, `.env.example` |
| `CORS_ORIGIN` | Indexer CORS origin, default `*` | `indexer/src/api/index.ts:11` |
| `MAX_GRAPHQL_BYTES` | GraphQL body cap, default 8000 | `indexer/src/api/index.ts:52` |
| `HEALTH_WATCHDOG` | `0` disables the self-restart watchdog | `indexer/src/api/index.ts:995` |
| `SEED_KEEPER_PK` | **Secret.** Hot key for the launch poke keeper; unset leaves it inert | `indexer/seed-keeper.mjs:30` |
| `SEED_KEEPER_INTERVAL` | Seconds between pokes, default 20 | `indexer/seed-keeper.mjs:32` |

The Postgres schema name is **not** an env var. It comes from `round.json`'s
`schema` field via `indexer/start.mjs:14`; `railway.json` must not pass
`--schema` (`indexer/start.mjs:1-6`).

### 1.3 Serverless routes (Vercel)

| Variable | Purpose | Read at |
|---|---|---|
| `DATABASE_URL` | Neon, shared with the indexer's tables plus `cauldron_brand` and `fren_corrections` | `api/brand.ts:97`, `api/fren-teach.ts:20` |
| `GROQ_API_KEY` | **Secret.** Preferred LLM provider | `api/fren-ask.ts:28` |
| `GROQ_MODEL` | Model name, default `llama-3.3-70b-versatile` | `api/fren-ask.ts:29` |
| `GEMINI_API_KEY` | **Secret.** Fallback LLM provider | `api/fren-ask.ts:30` |
| `GEMINI_MODEL` | Comma-separated model chain | `api/fren-ask.ts:34-37` |
| `CAULDRON_DOCS_ORIGIN` | Pins where `/llms-full.txt` is fetched from; unset uses the platform host | `api/fren-ask.ts:71-85` |
| `FREN_ADMIN_SECRET` | **Secret.** Gates the correction writer; unset disables teaching | `api/fren-teach.ts:21` |
| `BRAND_SIGNERS` | Addresses allowed to sign a branding update; **unset disables the write path entirely** | `api/brand.ts:40-43` |
| `BRAND_ALLOWED_ORIGINS` | Origins allowed to POST `/api/brand` | `api/brand.ts:48-51` |
| `BRAND_MAX_ROWS` | Row cap, default 256 | `api/brand.ts:56` |
| `X_REDIRECT_URIS` | Exact redirect URIs the token proxy will exchange | `api/x-token.ts:16-17` |
| `X_CLIENT_SECRET` | **Secret.** X app client secret | `api/x-token.ts:66` |
| `LIQUIDATOOR_COLLECTIONS` | Extra collections the badge route may read | `api/cauldron/liquidatoor.ts:191` |
| `VERCEL_PROJECT_PRODUCTION_URL`, `VERCEL_URL` | Platform-injected; the docs-fetch origin of last resort | `api/fren-ask.ts:81` |

### 1.4 Operator scripts and deploys

| Variable | Purpose | Read at |
|---|---|---|
| `KEYSTORE_ACCOUNT` | Foundry keystore account name — **the preferred signer** | `scripts/lib/signer.sh:24-28` |
| `KEYSTORE_PASSWORD_FILE` | Path to the keystore password file (`chmod 600`) | `scripts/lib/signer.sh:25-27` |
| `PRIVATE_KEY` | **Secret.** Raw-key fallback; announced on every run because it does reach argv | `scripts/lib/signer.sh:30-34` |
| `SEPOLIA_RPC` | RPC for the keeper and market maker, from `contracts/solidity/.env.sepolia` | `scripts/keeper.sh:32` |
| `RPC_URL` | RPC for the recovery scripts | `scripts/recover-live.sh:27` |
| `DEPLOYER` | Deployer address the recovery forwards to | `scripts/recover-live.sh:28` |
| `PERP_ENGINE`, `CAULDRON_REGISTRY` | Optional overrides; must **agree** with the manifest or the keeper exits | `scripts/keeper.sh:39-48` |
| `OLD_REGISTRY`, `GEN`, `POSM` | Which superseded round to reclaim | `scripts/reclaim-old-lp.sh:33-35,43` |
| `TARGET` | Presale mint target, default `GENESIS_SUPPLY - 1` | `scripts/mint-presale.sh:41` |
| Deploy-time vars | `POOL_MANAGER`, `POSITION_MANAGER`, `TESTNET_GOV`, `GOV_*`, `EMERGENCY_DELAY`, `PRESALE_*`, `GENESIS_BONUS_BPS`, `PRIME_BUY_ETH`, `SEED_WINDOW`, `BADGE_ART`, `MINT_OUT_TARGET_USD`, `HEARTBEAT_*`, `VENUE_*` | see 12-DEPLOYMENT |

### 1.5 Signing policy

`scripts/lib/signer.sh` is the one place a signer is resolved. Its header is the
correction of a false comment: seven scripts passed `--private-key
"$PRIVATE_KEY"` while `keeper.sh`'s header claimed it "uses `$PRIVATE_KEY` by
name only" — naming a variable does not stop the shell expanding it into the
child's argv (`scripts/lib/signer.sh:4-9`). Commit `b8ec2b9` fixed it.

- With `KEYSTORE_ACCOUNT` **and** `KEYSTORE_PASSWORD_FILE`, only an account name
  and a file path reach argv (`:24-28`).
- With a raw `PRIVATE_KEY`, the script prints a warning to stderr saying the key
  will appear in the host's process table, then uses it (`:30-34`). The header
  records that `cast` has no env-var route for a raw key (checked against cast
  1.4.4), so this is an honest statement rather than a fixable gap.
- With neither, it fails (`:36-37`).

Two scripts still bypass this. `scripts/arm-old-emergency.sh:13,21` uses
`--account deployer --from $DEP` with an interactive prompt, and
`scripts/recover-old-lp.sh:33-34` reads a keystore password with `read -rsp`.
Neither puts a key in argv.

---

## 2. The keeper loops

There are two, and they do different jobs.

### 2.1 The perp keeper — `scripts/keeper.sh`

Liquidates underwater perp positions and sweeps buffered legacy buybacks.

```
./scripts/keeper.sh          # one sweep
./scripts/keeper.sh watch    # sweep every ~8s
```

Order of operations (`scripts/keeper.sh:29-52`):

1. **Config loads first.** `contracts/solidity/.env.sepolia` must exist or the
   script refuses to run on defaults. The header records why: `PERP` and
   `REGISTRY` used to be bound *above* the `source`, so hardcoded defaults —
   both pointing at a dead round — won even when the env file named different
   addresses. The keeper then swept a nonexistent engine and reported "0 open"
   forever (`:23-28`). Fixed in commit `d517e62`.
2. **Addresses come from the manifest.** `PERP_ENGINE` / `CAULDRON_REGISTRY` may
   only *agree* with `indexer/deployments/round.json`; a mismatch exits 1
   (`:34-48`).
3. The signer is resolved through `scripts/lib/signer.sh` (`:50-52`).

Each sweep walks `id = 1 .. nextId()-1`, skips positions whose trader is zero,
calls `isLiquidatable(uint256)` and sends `liquidate(uint256)` on a true
(`:64-85`). Every eighth sweep in watch mode also calls
`materializeLegacyReserve()` on the registry, which is permissionless and a
no-op when nothing is pending (`:55-62,90`).

Cost: one `eth_call` per position per sweep, plus gas for each liquidation.
Reward: the keeper share of the liquidation penalty goes to the signer.

**Scaling note:** the sweep is O(nextId) per pass with two RPC calls per open
position, so it will get slower as the engine accumulates ids. That is a
property of the script, not a defect.

### 2.2 The launch poke keeper — `indexer/seed-keeper.mjs`

Calls `CauldronSeeder.poke()` across the launch window so the liquidity stream
and the tranched prime buy advance without waiting for an outside buyer.

It runs **inside the indexer process**, started by `indexer/start.mjs:25`, so it
ships with an already-wired deploy rather than needing a second Railway service
(`indexer/seed-keeper.mjs:24-27`). It is **inert unless `SEED_KEEPER_PK` is
set**, so no hot key is present by default (`:25-27`).

Why it exists: the seeder streams on `poke()` or on the hook's in-swap
`pokeInSwap()`, so a launch with no trades never streams. Round 35 closed its
900 s window with `placedWad == seedFloorWad` and 76.5 % of the launch liquidity
still in the seeder (`:8-12`).

Safety: `poke()` is permissionless and its target is a pure function of elapsed
time, so it cannot be accelerated or front-run into doing something different;
the worst a broken keeper does is waste its own gas (`:18-22`). It mirrors
`SeedLib.deployedTargetWad` client-side so it only sends a transaction when the
poke would actually move something (`:55-60`).

### 2.3 The market maker — `scripts/marketmaker.sh`

A testnet volume and chart-pattern bot. It buys and sells through the gacha
router to move the candles so leverage trading can be tested against real price
action (`scripts/marketmaker.sh:3-11`). Patterns include `uptrend`,
`downtrend`, `pump`, `dump`, `chop`, `accumulate`, `distribute`,
`head-shoulders`, `double-top`, `double-bottom`, `bull-div`, `rally`, `crash`,
`loop <pattern>` and `auto` (chaos).

Signing goes through `scripts/lib/signer.sh:39-40`.

**This script is not current — do not rely on it as written.**

1. Its default addresses are a dead round. `GACHA`, `TOKEN` and `PERP` default
   to `0x13D8b354…`, `0x125F6F98…`, `0x26ae199E…`
   (`scripts/marketmaker.sh:30-33`) — the round-20 addresses in
   `deployments/sepolia.json`, not the manifest's round-38 addresses. `POOL_ID`
   at `:51` is likewise pinned to that round's pool. The header comment says
   "config (round-19)". Unlike `keeper.sh`, it does **not** cross-check the
   manifest.
2. **It calls a function the router does not have.** Line 63 sends
   `play(uint256,uint256,uint256,uint256)` — four arguments. The router
   implements only the five-argument
   `play(uint256,uint256,uint256,uint256,uint256)`
   (`contracts/solidity/cauldron/CauldronGachaRouter.sol:233`), which is also
   what the frontend encodes (`src/config/cauldron.ts:314-325`). The four-arg
   form encodes a selector the contract does not implement, so every buy
   reverts — and line 64 swallows the failure as "likely RPC hiccup".

Fixing it means pointing `GACHA`/`TOKEN`/`PERP`/`POOL_ID` at the manifest the
way `keeper.sh:36-48` does, and adding the fifth argument.

---

## 3. Deployment and manifest scripts

| Script | What it does | Current? |
|---|---|---|
| `scripts/go-testnet.sh` | The whole bring-up: arm the old deployment, deploy, mint out, finalize, fold addresses into the manifest | yes — see 12-DEPLOYMENT |
| `scripts/deploy-testnet.sh` | Sets every testnet-only env value in one block, then runs `DeployLaunchpad.s.sol --broadcast` | yes |
| `scripts/mint-presale.sh` | Mints `GENESIS_SUPPLY - 1` in batches of 250, deliberately stopping one short so ignition is a human act | yes; reads the presale from the manifest (`:25`) |
| `scripts/apply-deployment.mjs` | Reads Foundry broadcast artifacts and writes addresses into `indexer/deployments/round.json` | yes |
| `scripts/verify-manifest.mjs` | Prebuild guard: fails the build on a malformed manifest or a reintroduced second address source | yes |
| `scripts/sync-deploy.mjs` | Older propagation script driven by `deployments/sepolia.json` | **stale** — see §6 |
| `scripts/deploy-round.mjs` | Referenced by `indexer/ponder.config.ts:16` and `src/config/cauldron.ts:8` as the way to ship a round | **unverified** — not read; `apply-deployment.mjs` is what `go-testnet.sh:111` actually runs |

`apply-deployment.mjs` reads **CREATE and CREATE2** records from
`contracts/solidity/broadcast/{DeployLaunchpad,DeployRotationStack,DeployPerp}.s.sol/<chain>/run-latest.json`
and picks by `contractName` (`:36-71`). Two failure modes are recorded in the
file: filtering to CREATE alone made the CREATE2-mined hook invisible
(`:40-44`), and taking "the first CREATE2" once pointed `hook` at `FeeRouteLib`,
an address with real code that answers no hook call (`:79-90`). Run it with
`--dry` to preview.

`verify-manifest.mjs` runs on prebuild and enforces: an integer `chainId`; a
`schema` matching `^[a-z0-9_]+$` because it becomes a Postgres schema name; an
absolute `indexerUrl`; twelve required contract addresses; **no duplicated
address** across contract keys; and positive integer `blocks.{deploy,perp,indexer}`
(`:24-70`).

---

## 4. Recovery scripts

All four exist to get ETH out of a superseded or current round. They differ in
how much they assume.

### `scripts/recover-live.sh` — **current, use this one**

Recovers the **current** round's liquidity so a fresh deploy can go over the
top. Registry address comes from the manifest (`:33`); the timelock, generation
and emergency delay are read off the chain (`:36-38`).

Sequence (`:74-100`): arm the break-glass through the timelock if
`emergencyReadyAt() == 0`; wait out the delay; `emergencyWithdrawLP(gen)`; then
forward the timelock's whole balance to `DEPLOYER`. Every timelock action is a
`schedule` → `sleep(getMinDelay + 12)` → `execute` pair (`:63-72`).

It says out loud that this **kills the current round** — pulling the liquidity
leaves whatever was bought with no market (`:18-20`). It also documents what
comes back: `emergencyWithdrawLP` calls `_removeLiquidity`, which unwinds the
registry's positions and, while the seeder still reports `seeding`, calls
`ISeeder.withdrawAll`, so streamed bands and un-streamed ledger A return too
(`:12-16`). It stops before the forward if nothing was recovered (`:97`).

It was generalised from a `recover-round35.sh` that hardcoded a registry and
timelock, because "pointing a break-glass at a stale registry is exactly the
kind of mistake that is easiest to make and hardest to notice" (`:5-10`).

### `scripts/reclaim-old-lp.sh` — **current, and the most careful**

Recovers value from a **superseded** round. It names three places value hides:
the generation's reserve position NFT; on a progressive generation, the seeder's
core bands (where `generationPositionId == 0`, so anyone looking only at
position NFTs concludes the round is empty); and loose ETH/token on the seeder
and registry (`:5-12`).

It runs `emergencyWithdrawLP`, `rescueSeeder` and `emergencySweep`, all
idempotent (`:13-17`). **Dry run by default** — nothing is broadcast without
`--execute` (`:19-22`). `OLD_REGISTRY` defaults to a specific address
(`:34`); pass your own.

### `scripts/recover-old-lp.sh` — **superseded, keep for reference only**

Hardcodes one deployment: `TL=0x06705E8c…`, `REG=0x3FD7649F…`,
`DEP=0xc94400e9…` (`:15-19`). It waits for the old registry's *immutable* 48 h
break-glass, then schedules `emergencyWithdrawLP(1)` with a 180 s timelock delay
and forwards the balance (`:36-58`). Generation `1` is hardcoded, the amount
"~6.8882 ETH" is in the header (`:3`), and there is no manifest check.
`recover-live.sh` does the same job against whatever is actually live.

Note the timelock address `0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3` is still
the manifest's `timelock` (`indexer/deployments/round.json:21`) but `REG` is
not the manifest's registry — so running this today would arm and drain a
registry that is not the live one.

### `scripts/arm-old-emergency.sh` — **superseded**

The arming half of the above, against the same two hardcoded addresses
(`:4-5`). It schedules `armEmergency()` (selector `0x06e7b8db`, `:8`) through
the timelock with a 180 s delay, executes, and prints the resulting
`emergencyReadyAt` (`:10-25`). `go-testnet.sh:61-76` inlines exactly this step,
so the script is redundant with the bring-up flow.

**Arming is not a withdrawal.** It moves nothing by itself and forces redemption
open — the intended holder protection — while starting the immutable delay
(`scripts/go-testnet.sh:61-64`).

---

## 5. Is it healthy?

Check these in order. Each has a cheap, unambiguous answer.

1. **Manifest is well-formed.** `node scripts/verify-manifest.mjs` exits 0. This
   runs on prebuild anyway.
2. **Indexer liveness.** `GET <indexerUrl>/health` returns 200. This is Ponder's
   own endpoint and says only "the process is up".
3. **Indexer freshness.** `GET <indexerUrl>/freshness` returns **200** with
   `ok: true`. A 503 means sustained divergence. During a fresh backfill expect
   `warmingUp: true` with a 200 — that is correct, not a fault
   (`indexer/src/api/index.ts:960-964`).
4. **It is indexing the right pool.** In the `/freshness` body, `curPoolId`
   appears in `indexedPools`. If it does not, the site will render an
   empty-but-confident page and the banner will say "indexing a different pool"
   (`src/hooks/useIndexerHealth.ts:56-58`).
5. **Generations agree.** `indexedGen === chainGen` in the same body.
6. **The app shows no health banner.** `IndexerHealthBanner` is hidden only when
   `degraded` is false (`src/components/shared/IndexerHealthBanner.tsx:27`).
7. **Perp reads resolve.** `GET /perp-heatmap/1` and `GET /perp-vault` return
   populated objects rather than nulls.
8. **Serverless routes answer.** `GET /api/cauldron/unrevealed` returns the
   sealed-crystal JSON (no dependencies, so a failure here is a platform
   problem). `GET /api/brand?gen=<round>` returns 200.
9. **The LLM route degrades rather than errors.** `POST /api/fren-ask` returns
   200 with `source: "groq" | "gemini"`; `source: "fallback"` with
   `reason: "no_api_key"` means no provider key is configured
   (`api/fren-ask.ts:207-210`).
10. **The keeper sees the live engine.** `./scripts/keeper.sh` prints a non-zero
    `swept N open` while positions exist. "engine unreachable" means the RPC or
    the address is wrong (`scripts/keeper.sh:66`).

---

## 6. When it is not healthy

| Symptom | Likely cause | Action |
|---|---|---|
| Site renders empty panels, no error | Indexer diverged or points at the wrong pool | Check `/freshness`. If `poolMismatch`, the manifest's pool set is stale — redeploy the indexer after `apply-deployment.mjs` |
| `/freshness` 503, `warmingUp: false` | Sustained divergence | The in-process watchdog will exit(1) after ~3 grace periods and Railway restarts it (`indexer/src/api/index.ts:995-1012`). If it loops, the deployment is misconfigured, not merely behind |
| Indexer crash-loops during sync | A free Alchemy key in `PONDER_RPC_URL` — 10-block `eth_getLogs` cap vs Ponder's larger chunks | Switch to publicnode or a paid tier (`indexer/ponder.config.ts:52-57`) |
| Indexer serves a previous round's data | A `--schema` in `railway.json` or a stale env var overriding the manifest | Remove it; the schema comes from `round.json` only (`indexer/start.mjs:1-6`) |
| Deploy will not promote on Railway | Something overrode `/health` with a divergence check | `/health` must stay Ponder's liveness path (`indexer/src/api/index.ts:985-989`) |
| Every mint reverts `WrongPrice` | A hardcoded price disagreeing with the contract | The UI already re-reads `PRICE()` per mint (`src/hooks/useMiFrensPresale.ts:206-219`); check the contract, not the UI |
| Keeper reports "0 open" forever | Wrong engine address | The script now exits on a manifest mismatch (`scripts/keeper.sh:45-48`); if it runs but finds nothing, the engine really is idle |
| Market-maker buys all "fail" | The four-arg `play` selector (§2.3) | Do not trust this script until it is fixed |
| Launch window closes with liquidity still in the seeder | No trades and no poke keeper | Set `SEED_KEEPER_PK` before the launch, or call `poke()` manually — it is permissionless |
| `/api/fren-ask` always returns `fallback` | No provider key, or the docs origin is unreachable | Set `GROQ_API_KEY` or `GEMINI_API_KEY`; check `CAULDRON_DOCS_ORIGIN` resolves and serves `text/*` |
| `/api/brand` POST returns 503 `branding_disabled` | `BRAND_SIGNERS` unset — the route fails closed by design | Set it; do not work around it |
| `/api/x-token` returns 503 | `X_REDIRECT_URIS` unset | Set the exact registered redirect URIs |
| Need the ETH back out of a round | — | Current round: `scripts/recover-live.sh`. Superseded round: `scripts/reclaim-old-lp.sh` (dry run first) |

Two standing recommendations recorded in the code rather than invented here:
the in-memory rate limiters are per warm instance and real protection belongs in
the WAF (`api/fren-ask.ts:135-138`), and the GraphQL byte cap is a bound on the
honest majority plus a speed bump on the rest
(`indexer/src/api/index.ts:64-67`).

---

## Verification

- `git rev-parse --short HEAD` → `20d6de2`
- Disagreements found:
  1. `.env.example` documents `VITE_CAULDRON_INDEXER`, but
     `src/config/cauldron.ts:39-46` reads the indexer URL from the manifest and
     states there is deliberately no env override. The `.env.example` entry is
     stale.
  2. `scripts/marketmaker.sh:63` calls a four-argument `play(...)`; the router
     implements only the five-argument form
     (`contracts/solidity/cauldron/CauldronGachaRouter.sol:233`).
  3. `scripts/marketmaker.sh:30-33,51` hardcodes round-20 addresses and a
     round-20 pool id with no manifest cross-check, unlike `scripts/keeper.sh`.
  4. `scripts/recover-old-lp.sh:18` and `scripts/arm-old-emergency.sh:5` target
     registry `0x3FD7649F…`, which is not the manifest's registry.
- Not verified: `scripts/deploy-round.mjs` and `scripts/sync-deploy.mjs` were
  not read; both are referenced by comments as the way to ship a round, while
  `go-testnet.sh:111` runs `apply-deployment.mjs`.
