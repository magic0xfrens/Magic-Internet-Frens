# OFF-CHAIN LIVENESS — chain 4663 (P5b)

**Question:** when chain 4663 misbehaves, what breaks in our read layer, how would we know, and how do we recover?

**Short answer:** the read layer's reorg tolerance is **30 blocks ≈ 3 seconds** against a chain whose
rewrite window is **~9,650 blocks ≈ 16 minutes**, the setting is **not configurable**, and **nobody is
paged when it breaks**. No reorg-induced double-action is reachable (that class is closed by design,
§L-6). Two keepers carry Sepolia-derived constants that are wrong by 2–3 orders of magnitude on a
100 ms chain (§L-4, §L-5). Chain facts are taken from `CHAIN_PROFILE.md` and not re-derived.

Every claim below is tagged **VERIFIED** (read or ran it), **DERIVED** (reasoned), or **UNKNOWN**.

---

## 1. Failure-mode table

| # | What breaks | How we detect it | How we recover | How long |
|---|---|---|---|---|
| L-1a | Reorg **deeper than 30 blocks (~3 s)** → Ponder throws `Encountered unrecoverable reorg beyond finalized block N`, retries ~14× over ~8.5 min, then `onFatalError` → `process.exit(1)` | **Nothing detects it.** `/health` still 200s until the process dies; then the whole API is connection-refused and a *user* sees the banner | Railway `ON_FAILURE` restarts; if the fork persists it burns all 10 retries and stays **down permanently** → manual redeploy | Down until a human notices. **Unbounded** |
| L-1b | Reorg **between 30 blocks and the real ~9,650-block window** → the rolled-back rows were already *finalized* in Postgres and the reorg tables pruned. Indexer serves history that no longer exists | **Nothing detects it.** `/freshness` returns `ok: true` — it checks pool + generation, never block height | No surgical repair exists. Bump `schema` in `round.json` → full clean reindex | = reindex time (§4). **Silent until then** |
| L-2 | Ponder crash for *any* reason (rate limit, 520, fatal fetch) | Only `src/hooks/useIndexerHealth.ts:38` — i.e. **a user's browser**. Zero external monitors in the tree | Railway restarts, ≤10 times | Minutes if transient; unbounded if the cap is exhausted |
| L-3 | Indexer **stalls** (realtime wedged, HTTP server alive) | **Nothing.** `/freshness` has no lag/height field; the watchdog only fires on `poolMismatch \|\| missedLaunch` | Restart the service | Unbounded |
| L-4 | Gacha crystals age past the **25.6 s** blockhash window on a quiet pool → re-anchor, then deterministic fallback | Player-visible bad outcome | Raise keeper resolve cadence (one-line) | Pre-launch fix |
| L-5 | Seed keeper signs every `poke()` with **chainId 11155111** → rejected by 4663, swallowed as `poke skipped` | Log line only | Fix the hardcoded `chain: sepolia` | Pre-launch fix |
| L-7 | Primary RPC 429/520 | Transport rolls over to publicnode automatically | Automatic | Seconds. **Handled** |
| L-7b | Primary RPC returns **200 with a stale tip or a fork** | **Nothing.** `fallback` rolls over on *error*, never on *wrong answer* | See runbook §4 | See §4 |

---

## 2. Findings

### L-1 (CRITICAL) — reorg depth is off by 322×, and it cannot be configured

**VERIFIED.** `indexer/node_modules/ponder/dist/esm/utils/finality.js:9-36` is a `switch` on `chain?.id`
covering mainnet/testnets (65), Polygon (200), Arbitrum One/Nova (240), and then:

```js
default:
    // Assume a 2-second block time, e.g. OP stack chains.
    finalityBlockCount = 30;
```

4663 is not in the switch. `matchedChain` is a **viem** chain looked up by id
(`build/config.js:115`) and viem has no chain for 4663, so `chain?.id` is `undefined` → **default 30**.
`build/config.js:109-117` computes `finalityBlockCount` unconditionally from that function; **no field in
`ponder.config.ts` overrides it** — our config sets `id`, `rpc`, `pollingInterval`, `maxRequestsPerSecond`
and nothing else, and there is no knob to set.

**VERIFIED.** Ponder never asks the node what is finalized. `build/config.js:141-145` takes
`latest` and fetches `Math.max(latest - chain.finalityBlockCount, 0)`. So on 4663 (~100 ms blocks) Ponder
declares a block **final ~3 seconds after it sees it**, while the chain itself puts `finalized` ~9,648
blocks / ~16 minutes back. **Off by ~322×.**

Two distinct consequences, and the second is worse than the first:

- **Crash (L-1a).** `sync-realtime/index.js:497-505`: if the common ancestor is not in the in-memory
  `unfinalizedBlocks` window, it throws
  `Encountered unrecoverable '<chain>' reorg beyond finalized block N`. That propagates to the retry
  ladder `ERROR_TIMEOUT = [1,2,5,10,30,60,60,60,60,60,60,60,60,60]` (`sync-realtime/index.js:11-13`) —
  14 attempts, ~8.5 minutes — then `args.onFatalError(error)` (`:751-757`), wired to
  `exit({ reason: "Received fatal error", code: 1 })` (`bin/commands/start.js:144-146`). Process dies.
- **Silent bad data (L-1b).** A reorg *shallower* than 30 blocks is reverted correctly
  (`bin/utils/run.js:342-355` → `database.revert`). A reorg **between 30 and ~9,650 blocks** hits rows
  that Ponder already finalized: `run.js:358-365` → `database.finalize()`, which deletes the reorg
  journals (`database/index.js:789-828`). Those writes are **unrevertable**. The indexer then serves a
  chain history that does not exist, and reports itself healthy.

> On a single-sequencer Nitro chain, deep reorgs are **rare**, not routine — there are no competing
> proposers. But any sequencer restart or rollback lasting longer than **three seconds** exceeds the
> tolerance. The window is so small that "rare event" and "certain to exceed the limit when it happens"
> are both true. (DERIVED.)

### L-2 (HIGH) — nobody is paged; a crash is found by a user

**VERIFIED, and the previous round's finding stands verbatim.**

- `indexer/railway.json:4-9`: `"healthcheckPath": "/health"`, `"restartPolicyType": "ON_FAILURE"`,
  `"restartPolicyMaxRetries": 10`.
- `/health` is Ponder's built-in **liveness** endpoint — always 200 once the server is up. Our own code
  says so and deliberately refuses to shadow it: `indexer/src/api/index.ts:1384-1387` ("intentionally NOT
  mounted at `/health` … Overriding it … DEADLOCKED promotion"). **A 200 on `/health` means the process
  is alive, nothing more.**
- The real beacon is `/freshness` (`indexer/src/api/index.ts:1389-1392`, 200/503).
- **Nothing in the tree polls it except the browser.** `src/hooks/useIndexerHealth.ts:38` fetches
  `${base}/freshness` on a 25 s `usePoll`. Repo-wide grep for `sentry|pagerduty|betteruptime|uptimerobot|healthchecks.io|discord…webhook|slack…webhook`: **zero hits outside vendored `node_modules`**.
  `.github/workflows/` contains **only** `deploy.yml`.

**Who finds out, plainly:** the first user to load the site and read the degraded banner. There is no
path from that banner to anyone's phone. A crash that exhausts Railway's 10 restarts is an outage of
**unbounded length**.

**VERIFIED.** The in-process watchdog (`indexer/src/api/index.ts:1398-1412`) exits after ~9 min of
sustained divergence — but `diverged = poolMismatch || missedLaunch` only. A reorg-corrupted DB on the
**right** pool and the **right** generation is not divergence, so the watchdog never fires.

**VERIFIED gap.** The `/freshness` body (`indexer/src/api/index.ts:1360-1366`) is
`{ok, chainGen, indexedGen, curPoolId, indexedPools, chainOpenPositions, dbOpenPositions, reasons,
divergingForMs, behind, warmingUp}` — **no block height, no timestamp, no lag**. An indexer stuck 40
minutes behind the tip on the correct pool reports `ok: true`.

### L-3 — the schema-bump negative result still applies, now for two reasons

Bumping `schema` in `indexer/deployments/round.json` (consumed at `indexer/start.mjs:16-21`) forces a
clean reindex, which **does** repair L-1b's Postgres damage. It still does **not** fix bad data being
served live from an RPC, because (a) it touches nothing the frontend reads straight from chain — quotes,
balances, position state, all of `src/hooks/*`; and (b) the reindex re-reads history **from the same two
RPCs**, so if the provider is the thing serving a dead fork you reindex the same wrong data. Confirmed
still true. (DERIVED from the code paths above.)

### L-4 (HIGH) — the gacha reveal window is 25.6 s on 4663; the keeper resolves every 64 s

**VERIFIED.** `contracts/solidity/cauldron/GachaLib.sol:96` — "`blockhash` returns zero past 256 blocks.
That is an EVM constant, not a …". Seeds are protected by `_pinSeeds` (`GachaLib.sol:147-155`), reachable
**only** from the resolve path (`GachaLib.sol:272`), pinning `PIN_SPAN = 4` batches per pass
(`GachaLib.sol:130`). Past expiry the batch re-anchors, and a second expiry reaches the
"deterministic-fallback hazard" (`GachaLib.sol:201-206`).

Resolution is driven by two things: in-swap, `CauldronHook.sol:2533` `_resolveTickets(NATIVE_RESOLVE_MAX)`
with `NATIVE_RESOLVE_MAX = 6` (`CauldronHook.sol:190`); and the permissionless keeper.

**`scripts/keeper.sh:160-163` runs `resolve` every 8th sweep with `sleep 8` — ~64 s — and justifies it
inline:**

```sh
#  Every ~64s. The commit blockhash survives 256 blocks (~51 min on Sepolia),
#  so this is an order of magnitude inside the window that forfeits a draw.
[ $((n % 8)) -eq 0 ] && resolve
```

On 4663, **256 × ~100 ms = 25.6 seconds**. The cadence is **2.5× outside** the window, not an order of
magnitude inside it. On a pool quiet enough that no swap triggers the in-swap path, every committed
crystal ages out before the keeper reaches it. The comment's own reasoning inverts on this chain.

Fix is one line (`% 8` → `% 1`, and `sleep 8` → block-time-aware). **Not edited** — outside the files I
was authorised to touch.

### L-5 (MEDIUM) — the only autonomous tx sender is hardcoded to Sepolia

**VERIFIED.** `indexer/seed-keeper.mjs:37` imports `sepolia`; `:89-90`:

```js
const pub = createPublicClient({ chain: sepolia, transport: http(rpc) });
const wallet = createWalletClient({ account, chain: sepolia, transport: http(rpc) });
```

A local account (`privateKeyToAccount`, `:88`) signs with `chain.id`, so on 4663 every `poke()` is signed
with **chainId 11155111** and rejected by the node. The rejection is swallowed at `:135-138` and logged
as `[keeper] poke skipped: …`. The launch-liquidity keeper is **silently inert on 4663** — precisely the
round-35 failure it was written to prevent (`seed-keeper.mjs:10-14`). Not a reorg problem; a launch-day
problem. (Chain-mismatch behaviour is DERIVED from viem's local-account signing; the hardcode is VERIFIED.)

### L-6 (GOOD) — no reorg-induced double action is reachable

This was the highest-severity item in scope. **I could not construct one, and the reason is structural.**

Every off-chain actor that sends a transaction is **level-triggered** — it compares a desired state to
freshly-read on-chain state — never **edge-triggered** on an observed event. Complete inventory
(repo-wide grep for `writeContract|sendTransaction|sendRawTransaction|privateKeyToAccount`, plus the
shell scripts that `cast send`, which that grep misses):

- **`indexer/seed-keeper.mjs:106-121`** re-reads `placedWad` / `primePending` every tick and sends only
  when `target > placed`, where `target` is a pure function of elapsed time. If a poke is reorged out,
  `placedWad` rolls back with it and the next tick re-derives the same deficit and re-pokes. That is
  *correct*, not a double action. The file argues this itself (`:18-22`: "its target is a pure function
  of elapsed time … cannot be accelerated, over-deployed or front-run").
- **`scripts/keeper.sh:98-121`** re-reads `nextId()`, `positions(id)` and `isLiquidatable(id)` every
  sweep, and on-chain `liquidate()` re-checks solvency. A liquidation prepared against a fork block
  simply reverts on the canonical chain — the script already logs that case ("healthy at TWAP mark").
- **`resolve` / `materialize` / `royalty_sweep`** (`keeper.sh:69, 91, 145-152`) are permissionless and
  idempotent; they no-op or revert when there is nothing to do.
- **Nothing consumes indexer events or logs to decide whether to send**, and **nothing stores "I already
  did this" off-chain.** The `contracts/scripts/*` hits are manual ops/deploy scripts, not keepers.

**DERIVED, and worth writing into the runbook:** the safety property is *"read the chain, don't remember
what you did."* It is the reason a 16-minute rewrite window is survivable for our keepers. A future
keeper that caches "already liquidated #7" off-chain, or that reacts to a Ponder event instead of a fresh
`eth_call`, would break it. `seed-keeper.mjs:129` uses `waitForTransactionReceipt` with the default **1
confirmation**, which on 4663 means essentially nothing — but because the actor is level-triggered, the
only consequence is a log line that later becomes untrue.

### L-7 — frontend transport: sufficient for 429/520, structurally insufficient for a lying RPC

**VERIFIED.** `src/config/chains.ts:219-222`:

```ts
[targetChain.id]: fallback(
  TARGET_RPCS.map((u) => http(u, { batch: { wait: 24 }, retryCount: 2, retryDelay: 250 })),
  { rank: false, retryCount: 1, retryDelay: 300 },
),
```

`TARGET_RPCS` (`:88-96`) = `VITE_RPC_URL` (comma-splittable) + `BACKUP_RPCS[4663] =
["https://robinhood-rpc.publicnode.com"]`, de-duplicated.

**VERIFIED live** (one read-only request per endpoint): both `rpc.mainnet.chain.robinhood.com` and
`robinhood-rpc.publicnode.com` return `eth_chainId = 0x1237` (**4663**) and both send
`access-control-allow-origin: *`. The backup is genuinely browser-usable — worth checking, because
`chains.ts:139-141` records that many public nodes block cross-origin fetch, which would have made the
new fallback decorative.

- **Sufficient for** a 429 or a 520 on the primary: 2 retries at the transport, then roll to publicnode.
  `batch: { wait: 24 }` also collapses request count, which is the actual 429 driver.
- **Not sufficient for a stale tip or a fork.** viem's `fallback` rolls over on **error**, never on
  **wrong answer**. A primary returning HTTP 200 with a 40-minute-old block is the happy path as far as
  the transport is concerned, and `rank: false` removes the latency-based escape too. With exactly two
  endpoints there is no majority to take: two nodes that disagree give you a coin flip, not a
  resolution. **This is the structural reason the old runbook's core step does not port to 4663.**
- `RPC_URL` throws rather than guessing when the chain is unknown and the env is blank
  (`chains.ts:70-79`), and 4663 has a correct built-in default (`chains.ts:63`), so a blank Vercel var
  degrades to the verified mainnet RPC rather than to another chain's.

**UNKNOWN:** whether the deployed Vercel env actually has `VITE_RPC_URL` populated. `.env.example:48-51`
declares it empty; I did not open `.env.vercel-backup` / `.vercel` (they may carry secrets) and cannot
query the Vercel project from here. Flagging rather than guessing. The blast radius is small because the
built-in default is correct — but the *intended* primary may not be the one in use.

### L-8 (INFO) — dead host clean; manifest still points at Sepolia

**VERIFIED.** `grep -rn "rpc.chain.robinhood.com"` excluding the `mainnet.` / `testnet.` forms hits only
warning comments (`src/config/chains.ts:60`, `indexer/ponder.config.ts:118`,
`indexer/src/api/index.ts:142`) and docs/audit prose that themselves state it does not exist. **It is a
default nowhere.** Matches `ARTIFACT_PARITY.md:200`.

**VERIFIED.** `indexer/deployments/round.json` currently pins `chainId: 11155111`, `round: 44`,
`schema: "cauldron_r44d"`, `blocks.indexer: 11696096`. `indexer/ponder.config.ts:23` derives `chainId`
from that manifest and `:131` keys the RPC default off it, so the indexer **as committed indexes Sepolia
and declares Sepolia**. Presumably the deploy agent's item, but the read layer is not "4663-ready" until
it flips.

---

## 3. The 4663 recovery runbook (replaces the Sepolia one)

The old runbook's core step — *"find the provider whose block N+1 parent-hashes to N"* — assumed several
independent providers. **On 4663 there are two, both downstream of one Robinhood-run sequencer, and no
free archive. That step does not port.** The replacement authority is not quorum, it is **time**:
`blockTag: "finalized"` lags ~16 minutes but cannot be rewritten.

### Step 0 — before trusting any endpoint
`eth_chainId` must equal `0x1237` (4663). Lookalike RPC hosts, fake explorers and phishing sites exist
around this chain. `rpc.chain.robinhood.com` (no `mainnet.`) **does not exist**; `arrowrpc` serves HTML;
`ordofi` prunes ~40 minutes of history. Use only the two endpoints in `CHAIN_PROFILE.md §8`.

### Step 1 — detect
Today the only detector is a human looking at the site. **Until §5.1 ships, assume detection latency is
hours.** Once you are looking:
- `curl -s <indexerUrl>/freshness` — **not** `/health`. `/health` returning 200 means the process is
  alive; it says nothing about data. Connection-refused means Ponder exited.
- `/freshness` returning `ok:true` does **not** currently rule out a stalled or fork-following indexer
  (no lag field — see §5.4). Cross-check by hand: compare the newest row the API serves against
  `eth_blockNumber`.
- Check the Railway restart count. **If it has burned its 10 retries the service will not come back on
  its own** and needs a manual redeploy.

### Step 2 — is it a reorg, or is a provider lying?
1. Ask **both** endpoints for the hash at a height **at or below `finalized`** (tip − ~9,650). If they
   agree, that history is settled and is truth. Anything above `finalized` is provisional **by
   definition** and disagreement there is not evidence of a fault.
2. Self-verify a single endpoint's chain: fetch block N and N+1 from the *same* endpoint and check
   `N+1.parentHash == N.hash`. This catches lag and skew. It does **not** catch a coherent fork — a node
   that believes an orphan is canonical serves a self-consistent chain.
3. Two endpoints cannot break a tie. If they disagree **below** `finalized`, one is lying or badly
   pruned: prefer `rpc.mainnet.chain.robinhood.com` (the operator's own) and treat the other as suspect.
4. **If it is above `finalized`, the correct action is to wait ~16 minutes and re-ask.** The question
   answers itself, and no amount of provider-shopping answers it sooner.

### Step 3 — recover the indexer
- **Crash-looping on `unrecoverable reorg`:** the in-memory window can never catch up. Bump `schema` in
  `indexer/deployments/round.json` and redeploy (`indexer/start.mjs:16-21` reads it) → clean reindex.
- **Serving finalized rows from a dead fork (L-1b):** there is **no surgical repair** — Ponder pruned the
  reorg journals. Same fix: bump `schema`, redeploy.
- **Stalled but not crashed:** restart the service.
- Remember §L-3: a schema bump repairs Postgres only. Anything the frontend reads straight from RPC is
  unaffected by it.

### Step 4 — what we reindex from, and how long it takes
Reindex reads from `round.json` `blocks.indexer` to the tip. **This is the part that needs a budget
decision, not a procedure.**

- **There is no free archive on 4663.** A reindex is only possible while the primary still retains the
  range. Whether `rpc.mainnet.chain.robinhood.com` prunes, and at what depth, is **UNKNOWN** — not
  measured in `CHAIN_PROFILE.md`. **Measure it before launch** (one `eth_getBlockByNumber` at a
  deliberately old height). If it prunes, historical recovery is **impossible** at any speed.
- **Arithmetic (DERIVED):** at ~100 ms blocks, one day of chain is ~864,000 blocks. Even at a generous
  2,000 blocks/s of filtered `eth_getLogs`, one day of history is ~7 minutes of sync and one week is
  ~50 minutes — and it is all served by one endpoint at `maxRequestsPerSecond` defaulting to `12 × 1`
  (`indexer/ponder.config.ts:170-173`). Recovery time grows linearly with round age.

**The honest answer, stated plainly: we cannot recover quickly without a paid archive endpoint.** Two
mitigations are available today, and they are not substitutes for each other:
1. Keep `blocks.indexer` at the round's own deploy block and keep rounds short, so a forced reindex is
   minutes rather than hours. (Free. Bounds the damage.)
2. Buy an archive/dedicated endpoint. (Costs money. Removes the class.)

---

## 4. What must be true before launch

1. **Alerting must exist.** One external poller hitting `/freshness` and reaching a phone. This is the
   single highest-value item in this report: it converts every entry in §1 from *unbounded* to
   *minutes*. Nothing in the tree does this today.
2. **A decision on reorg depth.** Ponder's 30 blocks ≈ 3 s versus the chain's ~16 min rewrite window, and
   it is **not configurable** (§L-1). Pick one, knowingly: (a) accept it and rely on schema-bump
   reindex as the repair; (b) pin `blocks.indexer` recent so that repair is cheap; (c) patch
   `getFinalityBlockCount` in a vendored Ponder; (d) pay for an endpoint. Doing nothing is choosing (a)
   without the reindex plan.
3. **An archive endpoint — or an explicit, written acceptance that deep recovery is not available.**
   First measure whether the primary prunes (§3 step 4).
4. **A lag field in `/freshness`.** `ok: true` on a 40-minute-stale indexer is the failure mode most
   likely to be believed. Add indexed-tip height + chain-tip height; the browser hook
   (`src/hooks/useIndexerHealth.ts`) and any monitor both get it for free.
5. **`indexer/seed-keeper.mjs:89-90`** — drop the hardcoded `chain: sepolia`; the launch keeper cannot
   send a transaction on 4663 today (§L-5).
6. **`scripts/keeper.sh:160-163`** — resolve every sweep, not every 8th; the gacha window is 25.6 s on
   this chain, not 51 minutes (§L-4).
7. **`indexer/deployments/round.json`** must move off `chainId: 11155111` (§L-8).

---

## 5. The single most likely way the read layer goes down on day one

**Not a reorg.** It is the mundane path: the primary RPC rate-limits or blips during launch traffic,
Ponder's realtime loop exhausts its retry ladder and calls `onFatalError`
(`sync-realtime/index.js:763-780` → `bin/commands/start.js:144`), the process exits, and Railway restarts
it. Individually that is a ninety-second blip. **The outage is not the crash — it is that nobody is
watching it.** If the condition persists past ten restarts the service stays down permanently, and the
first person to know is a user staring at an empty trade panel. The deep-reorg path (§L-1) is the same
shape with a worse tail: it can also leave *wrong* data behind, reported as healthy.

**What would prevent it:** one external monitor on `/freshness` wired to a phone. That, plus a recent
`blocks.indexer` so the forced reindex is minutes rather than hours. Everything else on the list is a
refinement of those two.

---

*P5b, 2026-09-16. Read-only local inspection plus two read-only `eth_chainId` probes against the public
endpoints. No load tests, no deployments, no changes to any file other than this report.*
