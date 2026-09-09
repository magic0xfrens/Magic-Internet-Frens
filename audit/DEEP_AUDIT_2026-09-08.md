# Deep Audit — Magic Internet Frens / The Cauldron

**Commit:** `0a1830b` · **Date:** 2026-09-08 · **Scope:** protocol, indexer, API, frontend

> **STATUS: ALL FINDINGS REMEDIATED.** See [`REMEDIATION_2026-09-08.md`](REMEDIATION_2026-09-08.md)
> for what changed, why, and the verification evidence. The findings below are
> preserved as written at audit time — the analysis is the record, and the fixes
> are documented separately rather than edited over the top of it.

---

## 1. Executive summary

The Solidity core is genuinely well-built. Prior audit findings have real fixes with
real regression tests behind them, the invariant suites assert the right properties,
and the hardest thing here — a TWAP mark that resists poisoning from inside the swap
that triggers liquidation — is done carefully and correctly.

**Would I let it hold mainnet value today? For an ETH-only generation, close to yes.
For a multi-quote generation, no.** Every High finding below was introduced by the
last five commits, and they share one root cause: the multi-quote work changed what a
stored number *means* without changing the code that consumes it. The take was
generalised, the routing was generalised, the ledgers were not.

Three things stand between this and yes:

1. **`relaunchETH` is denominated in wei but credited in whatever asset the fee
   arrived in** (R-1). A non-ETH generation mints a phantom reserve and permanently
   bricks its own relaunch — the self-funding flywheel that is the entire protocol.
2. **The volume ledger silently changes units when the oracle goes stale** (V-1),
   under-counting ~1e12× and pushing a healthy generation into a permissionless,
   irreversible relaunch. This inverts the fail-safe direction `QuoteOracle`
   explicitly specifies.
3. **The dividend basket is a permissionless, bounded, append-only, no-removal list
   that a claim loops over and pushes from** (D-1/D-2). Any address can close it
   forever with eight junk tokens, or brick every holder's claim with one hostile one.

A fourth, process-level: **CI never runs `forge test`**, and 78 of the 443 "passing"
local tests pass *vacuously*.

---

## 2. Architecture

### 2.1 The lifecycle

```
 ACTOR            CALL                                  VALUE MOVED
 ─────────────────────────────────────────────────────────────────────────────
 deployer/gov  ─► CauldronRegistry.summon()             seed ETH ──► V4 pool
                    ├─► CauldronToken (CREATE2, mined)
                    ├─► PoolOps.openOrAddPair()         LP minted to registry
                    ├─► PoolManager.initialize()
                    │     └─► hook._afterInitialize()   ADOPTION GATE (C-01)
                    │           sender==registry ?      trackedPools[id]=true
                    │           allowedQuote(c0)   ?    quoteIsCurrency0[id]
                    └─► CauldronSeeder (progressive)    slices streamed in-swap

 anyone       ─► PoolManager.swap()                    ── the hot path ──
                    ├─► hook._beforeSwap()              BUY leg: fee taken on input
                    │     └─► _takeEthFee()             poolManager.take(quoteCur)
                    │           ├─► _routeEthFee()      ─► guild / floor / relaunch
                    │           └─► _routePerpFee()     ─► guild 30% / stakers 70%
                    └─► hook._afterSwap()               SELL leg: fee on output
                          ├─► _maybeLegacyBuyback()     legacyBuffer ─► market buy
                          ├─► _maybePoke()              seeder slice
                          ├─► _toUsd() ─► _recordVolume()   ⚠ V-1 lives here
                          ├─► nftCredit accrual         (tx.origin or tagged player)
                          ├─► perpEngine.sweepLiquidations(tx.origin)   ⚠ gas-bounded
                          └─► nativeGachaStep()         crystal forge

 time         ─► 24h volume buckets decay
 anyone       ─► hook.isDead(id)                        vol + siblings < threshold
 anyone       ─► CauldronRegistry.relaunch()            ── PERMISSIONLESS ──
                    ├─► _removeLiquidity(gen)           LP ──► registry
                    ├─► hook.releaseRelaunchETH()       reserve ──► registry  ⚠ R-1
                    ├─► forceCloseAllDead()             perps settled
                    ├─► deploy gen+1 token + pool
                    ├─► green-candle buy                migration reserve
                    └─► seed gen+1
 holder       ─► CauldronRegistry.claimTokens(gen)      1:1 old ──► new
```

**Points where an external actor can intervene:** pool initialization (gated),
every swap (open), `relaunch()` (open, once dead), `sweepLiquidations` (open, via any
swap), `MiFrensDividend.fundToken` (**open, and should not be** — D-1),
`materializeLegacyReserve` (open), `castSpell`/`claim` (holder-gated).

### 2.2 Value-flow map

```
                    swap fee (taken in the QUOTE asset, whichever that is)
                                       │
                    ┌──────────────────┴─────────────────┐
                    │                                    │
              base fee (taxRate)                   surtax (anti-snipe)
                    │                                    │
        ┌───────────┴──────────┐                   100% ─► guild (dividend)
        │                      │                          fallback ─► _routeEthFee
   sender==perpEngine?      organic swap
        │                      │
  30% guild / 70% stakers   guildBps off top ─► guild ─► MiFrensDividend
        │                      │                          ├─ ETH: receive()
   FeeRouteLib.routePerp       │                          └─ ERC20: fundToken() ⚠ D-1/2
        │                   floorBps of remainder ─► vault  (or ─► legacyBuffer)
   leftover ─► relaunchETH     │
       ⚠ R-1               remainder ─► relaunchETH   ⚠ R-1 (credited in wei
                                │                          regardless of asset)
                                │
                      releaseRelaunchETH() ─► registry ─► seeds gen+1
                                             (native ETH only)
```

**Where value sits, and who can move it:**

| Location | Holds | Who can move it | Authority |
|---|---|---|---|
| `hook.relaunchETH` | native ETH (+ phantom, R-1) | registry only | `releaseRelaunchETH` |
| `hook.legacyBuffer` | native ETH (+ phantom) | self-call only | `legacyBuyStep` |
| `hook` ERC20 balance | non-ETH fees | **nobody** ⚠ | no exit path exists |
| `MiFrensDividend` ETH | holder dividends | holders (pull) | `claim` / `withdrawOwed` |
| `MiFrensDividend` ERC20 | basket dividends | holders (pull) | `claimTokens` ⚠ D-2/D-3 |
| generation LP | ETH + token | registry; emergencyAdmin | `relaunch`; `emergencyWithdrawLP` |
| `PerpVault` | staker collateral | vault logic | `fundTokenFromVault` |

### 2.3 Trust and permission model

| Role | Held by | Powers | If lost | If stolen |
|---|---|---|---|---|
| `emergencyAdmin` | **immutable**, timelock/Safe | `emergencyWithdrawLP` (entire generation LP), `setRedemptionPaused`, `setEnchantFeeMult` | break-glass gone forever | **arm → wait out delay → take the whole LP.** No rotation path exists |
| registry `owner()` | timelock | seeding, wiring, ceilings | ops frozen | wide, but LP is emergencyAdmin-gated |
| hook `owner()` | deployer→timelock | `setDeathThreshold`, `setSnipeParams`, fee bps, `executeRegistryOverride` | tuning frozen | can re-point `registry` after a delay (reserve is flushed to the *outgoing* registry first — good) |
| `QuoteOracle.owner` | timelock | `setFeed`, `setSequencer` | prices freeze at last good | **can price anything at anything** → fake death/life |
| `registry` (as caller) | contract | `releaseRelaunchETH`, hook wiring | — | — |
| `CauldronGovernor` | token holders | proposals | — | spam-bounded (Z03) |
| `TreasuryGovernor` | holders | quote rotation envelopes | — | allowlist is deployer/timelock-only, so a vote picks among vetted assets — good guardrail |
| keeper scripts | EOA | `poke`, market-make | liveness degrades only | no value authority |

**The sharpest trust fact:** `emergencyAdmin` is `immutable` (`CauldronRegistry.sol:116`)
and can pull an entire generation's LP to itself (`:398-407`). The protocol's headline
claim is protocol-owned LP and no team rug; that claim rests entirely on one key that
**cannot be rotated**. Timelocked on mainnet, arming-gated even at delay 0.

### 2.4 Invariant table

| # | Invariant | Enforced by | Status |
|---|---|---|---|
| I1 | Hook ETH balance ≥ `relaunchETH + legacyBuffer` | `invariant_hookEthAccountingIsBacked`, `invariant_HOOK1_EthBooksAreSolvent` | **VIOLATED by R-1** — see §5 |
| I2 | Token supply fixed, never inflates | `invariant_SUP1_TokenIsNonMintable`, `invariant_supplyIsFixedAndNeverInflates` | enforced |
| I3 | Migration is 1:1 across generations | `testFuzz_MigrationIsOneToOne`, `invariant_migrationNeverOverDelivers` | enforced (known dust deviation documented) |
| I4 | Reserve backs its claims | `invariant_reserveBacksItsClaims`, `invariant_RES1_GenesisFloorIsBacked` | enforced |
| I5 | Reserve ceiling not breachable | `F04_ReserveCeiling`, `Y01_ReserveCeilingBreach` | enforced + self-heals |
| I6 | Reserve floor holds under seeder rescue | `A05_ReserveFloorSeeder`, `Z04` | enforced |
| I7 | Perp engine ETH solvency | `invariant_perpEngineIsSolvent`, `PERP1/2/3` | enforced |
| I8 | Ledger payouts ≤ credits | `invariant_L_PayoutsNeverExceedCredits` | enforced |
| I9 | Exit forced open while armed | `invariant_exitIsForcedOpenWhileArmed`, `testFuzz_ExitGuarantee` | enforced |
| I10 | No owed value forgotten (hook) | `invariant_L1_NoOwedValueIsEverForgotten` | enforced for ETH |
| I11 | Mark cannot be poisoned by an atomic round-trip | `Z02_PerpStaleMark`, `_writeObs` A-02 fix | enforced |
| I12 | Volume ledger has a single, stable unit | — | **UNENFORCED** → V-1 |
| I13 | Dividend basket entitlement ≤ funded, per asset | — | **UNENFORCED** → D-3 (transfer forfeits) |
| I14 | Basket asset list contains only protocol fee assets | — | **UNENFORCED** → D-1 |
| I15 | A claim path cannot be bricked by one asset | — | **UNENFORCED** → D-2 |
| I16 | Every asset the hook holds has an exit path | — | **UNENFORCED** → R-1 corollary |
| I17 | Perps mark against the pool that sets the real price | — | **UNENFORCED** → P-1 |

The five unenforced rows are exactly where the Highs are. That is not coincidence:
the enforced rows all predate the multi-quote work.

### 2.5 Four-layer data flow

```
CHAIN ──► PONDER INDEXER ──► (its own REST + GraphQL) ──► REACT UI
             │                                              │
             └── indexer/deployments/round.json ────────────┘
                 single manifest, read by BOTH
```

`round.json` lives inside `indexer/` because Railway only uploads that directory; the
frontend reaches across the tree so neither side can be updated alone. The comment is
accurate and the `verify-manifest.mjs` prebuild guard is real. This is good design.

**Where the frontend trusts the indexer:** 19 modules read it
(`useMiFrensDividend`, `usePerpEngine`, `usePerpVault`, `useCollectionFloor`,
`useCandles`, `useSwapTape`, `useUserNFTs`, …). **Only one — `TheCauldron.tsx` —
consults `useIndexerHealth`.** `cauldronOnchain.ts` has a separate on-chain fallback
for NFTs.

A stale or compromised indexer could therefore show: wrong dividend balances, wrong
perp positions and liquidation prices, a wrong floor, wrong presale state, a fabricated
activity feed — silently, in 18 of 19 places. The `/freshness` endpoint and the
in-process watchdog (`HEALTH_WATCHDOG`, exits on ~9 min sustained divergence) are
genuinely good, and are simply not wired to most consumers.

The indexer's GraphQL is served at `/graphql` **and `/`** with `cors: *` and no query
depth/complexity limit visible.

---

## 3. Findings

Severity is impact × likelihood. **Bug** = code betrays intent. **Design risk** = code
matches intent, intent is dangerous.

---

### R-1 — Non-ETH fees mint phantom `relaunchETH` and permanently brick relaunch
**High · Bug · PoC: `test/audit/AuditPoC6_QuoteReserve.t.sol` (passes on fork)**

**Location:** `CauldronHook.sol:1146-1147` (and `:1069`, `:1131`, `:1143`)

`_takeEthFee` collects on whichever side is the quote (`:1237-1239`) — correct.
`FeeRouteLib` then moves the right asset — correct. But the residual is booked into a
wei-denominated counter with no conversion and no asset check:

```solidity
relaunchETH += wantRelaunch + FeeRouteLib.routeSplit(_feeAsset, guild, vault, wantGuild, toFloor);
```

`relaunchETH` is paid out as **native ETH** — `registry.call{value: amount}` at `:1396`
and `:1549`.

**Exploit scenario (no attacker required — normal operation is sufficient):** the
treasury runs a USDG- or xNVDA-quoted generation. Every swap credits raw quote units
into `relaunchETH`. Once the phantom exceeds the hook's real ETH balance,
`releaseRelaunchETH()` fails its `require(ok)` and reverts. The counter is only zeroed
*inside* the function that reverts, so nothing self-corrects. **The generation can
never fund its successor.** Separately, the collected USDG has no exit path at all —
there is no `releaseRelaunchToken`, and `sweepLegacyReserve` (`:980`) is gated to a
different counter.

**Measured:** a single 10,000 USDG swap credited `9.9e9` wei of phantom reserve against
a hook ETH balance of 0; `releaseRelaunchETH()` reverted `"ETH transfer failed"`.

**Magnitude scales with the quote's decimals.** USDG (6dp): $1 → 1e6 phantom wei.
xNVDA (18dp, in the live manifest): 1 token → **1e18 phantom wei = one phantom ETH**.

**This is a re-opened regression.** The hook's own adoption-gate comment (`:534-539`)
names this exact failure mode, and the `currency0 != address(0)` line that prevented it
was deliberately removed when quotes were generalised (`:560-564`). The gate still
stops *foreign* pools; it no longer stops the protocol's *own* non-ETH pools.

**Fix.** Make the reserve per-asset: `mapping(address => uint256) relaunchReserve`, with
`releaseRelaunchAsset(address)` alongside the existing ETH path. The registry's seeding
logic must then choose which asset it is seeding with. Short of that, refuse to book a
residual for a non-native `_feeAsset` and route 100% of it to the guild/floor instead —
lossy but safe. **Do not ship a non-ETH generation before this lands.**

---

### V-1 — A stale oracle collapses recorded volume ~1e12× and fakes death
**High · Bug · PoC: `test/audit/AuditPoC7_StaleOracleDeath.t.sol` (passes on fork)**

**Location:** `CauldronHook.sol:628` (`_toUsd`), consumed at `:705`

`QuoteOracle` is explicit about its contract (`QuoteOracle.sol:40-44`):

> *"when a price is unusable this returns 0, and callers MUST treat 0 as 'cannot judge'
> rather than 'no volume'. Failing toward ALIVE is the only safe direction when the
> wrong answer cannot be undone."*

The consumer does the opposite:

```solidity
return f == 0 ? raw : (raw * f) / 1e18;
```

Falling back to `raw` is not "cannot judge" — it **silently changes the unit of the
volume ledger mid-stream**, and `_volumeBuckets` then holds a mixture of two
incompatible scales that `getVolume24h` sums without discrimination.

Every realistic quote under-counts on fallback: USDG (6dp, $1) by 1e12×; ETH (18dp,
$3k) by 3000×; xNVDA (18dp, $180) by 180×. **The fallback always pushes toward death.**

**Exploit scenario:** a Chainlink feed misses its heartbeat — routine, and the reason
the staleness check exists at all. Within 24 hours every bucket holds raw-scaled
figures. `isDead()` returns true for a generation trading normally. `relaunch()` is
**permissionless and irreversible**: any observer takes the free option, the LP is torn
down and rebuilt, and holders are force-migrated. Nothing reverts, and nothing looks
like a bug afterwards.

**Measured:** identical $10,000 trades recorded `1.0e20` with a live feed and `1.0e8`
with a stale one — an under-count factor of exactly **1,000,000,000,000** — after which
`isDead()` returned true against a threshold the generation had comfortably cleared.

**The test gap is precise.** `test/QuoteOracle.t.sol` proves all five refusal paths
return 0. **No test anywhere asks what the hook does with that 0.** The bug lives
exactly in the seam between two well-tested components.

**Fix.** Treat 0 as "cannot judge", as documented. Either (a) skip the volume write
entirely and leave `_lastUpdateTs` untouched so the window does not age, or (b) carry
the last-good factor forward — `QuoteOracle.cachedUsdPerRawUnit` already implements
exactly this ("A refresh that comes back unusable keeps the LAST GOOD value"). Option
(b) is strictly better and the machinery is already written; see G-1.

---

### D-1 — Anyone can permanently close the dividend basket with junk
**High · Bug · PoC: `test/audit/AuditPoC5_DividendBasket.t.sol::test_D1` (passes)**

**Location:** `MiFrensDividend.sol:198-209`

`fundToken(address asset, uint256 amount)` has **no access control and no allowlist
check**. `assets` is capped at `MAX_ASSETS = 8` (`:109`) and has **no removal path**.

**Exploit:** an attacker who is not the hook, not the owner and not a holder deploys 8
worthless tokens and funds 1 wei of each. The basket is now full. Every genuine,
treasury-approved quote asset is refused forever, so the hook's
`FeeRouteLib.deliver` to the dividend returns false permanently and the protocol's own
fee route is closed. Cost: 8 contract deployments.

The existing `test_AssetListIsBounded` asserts the bound exists but never asks **who is
allowed to consume it** — it treats the cap as a safety property when it is the attack
surface.

**Fix.** Gate `fundToken` to the hook (and/or check the registry's `allowedQuote`).
Both are one line and the contract has 18KB of headroom.

---

### D-2 — One hostile basket asset bricks every holder's token claim, forever
**High · Bug · PoC: `test/audit/AuditPoC5_DividendBasket.t.sol::test_D2` (passes)**

**Location:** `MiFrensDividend.sol:227-258`

`claimTokens` loops the entire asset list and calls `_push`, which **reverts** on
transfer failure (`:253-258`). There is no per-asset `try`/`catch` and no removal path.

**Exploit:** the attacker calls `fundToken` with a token that transfers normally, then
stops. Nothing exotic — a pausable token, a blacklisting stablecoin, or any token whose
owner turns hostile after listing behaves identically. From that moment `claimTokens`
reverts for **every holder and every asset**. In the PoC, Alice is provably owed 1,000
USDG, `pendingToken` confirms it, and she can never collect it.

**Fix.** Wrap each `_push` in `try`/`catch` and credit failures to a per-asset `owed`
mapping; add an owner-gated `removeAsset`. Effects are already written before the
interaction, so the change is contained.

---

### D-3 — Transferring an enchanted fren silently forfeits accrued ERC20 dividends
**Medium · Bug · PoC: `test/audit/AuditPoC5_DividendBasket.t.sol::test_D3` (passes)**

**Location:** `MiFrensDividend.sol:338-347`

`onMiFrenTransfer` settles the ETH ledger into `owed[cur]` and resets `debtOf`, but
**never touches `debtOfAsset`**, and there is no `owedAsset` mapping to settle into.
The next caster's `_castSpell` then resets `debtOfAsset` over the top (`:306-310`).

The leaver's basket entitlement is not paid, not credited, and not reclaimable. In the
PoC, Alice's 1 ETH survives the transfer and her 1,000 USDG is stranded in the contract
with no caller able to reach it. The ETH path was written to make a transfer lossless;
the basket path was not brought along.

**Fix.** Add `mapping(address => mapping(address => uint256)) owedAsset` and settle it
in `onMiFrenTransfer` symmetrically with the ETH path, plus a `withdrawOwedToken`.

---

### P-1 — Perps mark and liquidate against the primary pool, not the price-setting one
**Medium (today) / High (multi-pool) · Design risk · Hypothesis — no PoC**

**Location:** `PerpEngine.sol:_key()`, `_sqrtP()`, `activeEthDepth()`

`_key()` builds from the single `quote` synced from `registry.generationQuote(gen)`
(`:934`), so the engine marks, sizes and liquidates against the **primary** pool.

**I confirm the maintainer's read that this is a correctness question, but the sharpest
edge is not the one identified.** The doc frames it as `activeEthDepth()` bounding
position size against the wrong pool. That direction actually fails *safe*: if
liquidity migrates to a sibling, the primary thins, `getLiquidity` shrinks, and
positions get bounded *more* tightly.

The real problem is the **mark**. `_sqrtP()` reads `slot0` of the primary pool, and a
thin pool is precisely the cheap one to move. With liquidity concentrated in a deep
sibling, an attacker can push the primary's tick with small capital while the economic
price — the one the sibling sets — never moves. The 5-minute TWAP and the A-02
`_writeObs` fix make this expensive rather than atomic, but they defend against
*flash* manipulation, not against **sustained pressure on a pool nobody is arbitraging
because it is not where the liquidity is**. Liquidations then fire from inside
`afterSwap` against a mark that no longer reflects the market.

I have not written a PoC: it needs a two-pool generation with skewed depth, which the
current registry cannot produce without the multi-pool work landing first. **Labelled a
hypothesis, not a demonstrated bug.**

**Fix (see §4.3).** Mark against depth-weighted price across the generation's pools, or
pin the mark to the deepest pool and re-evaluate on each sync.

---

### T-1 — 78 tests pass vacuously; CI runs no Solidity tests at all
**Medium · Process**

**Locations:** all 9 `*ForkTest` suites; `test/invariants/*`; `.github/workflows/deploy.yml`

Every fork-gated suite uses `if (!active) return;`, so without `FORK_RPC` the tests
**pass rather than skip**. Locally: `443 passed, 3 skipped` — of which **78 are
no-ops** (PerpEngine 30, CauldronSummon 16, MigrationVestingGate 7, ProgressiveSeed 6,
RotatorSwapFork 6, CauldronSeeder 5, QuoteOracleFork 4, LifecycleE2E 2, LaunchSnipe 2).
Real local coverage is **365**, not 443.

Critically, **both system-invariant suites are in this set**. The invariant that R-1
violates — `address(hook).balance >= relaunchETH + legacyBuffer`, named after finding
C-01 and asserted in *two* places — is vacuous without `FORK_RPC`.

`.github/workflows/deploy.yml` runs `verify-manifest.mjs` and `npm run type-check`.
**It never invokes `forge`.** The in-code comments ("suite still compiles + passes in
CI") describe a job that does not exist.

**Fix.** Use `vm.skip(true)` so a gated test reports as skipped. Add a `forge test` job,
with `FORK_RPC` from secrets for a nightly full run.

---

### G-1 — The oracle cache is never used on the hot path
**Medium (gas) · Bug**

**Location:** `CauldronHook.sol:620-629` vs `QuoteOracle.sol:192-199`

`QuoteOracle` implements `cachedUsdPerRawUnit` with a 15-minute TTL, justified at
length: *"A Chainlink read costs ~30k gas … Paying that on every swap is roughly a 15%
tax on trading."* The hook calls the **uncached** `usdPerRawUnit` via `staticcall`,
because `_toUsd` is `view`. The only caller of the cached version is `QuoteRotator`.

So every swap on an oracle-wired generation pays the full Chainlink read, and the
documented mitigation is inert exactly where it was written to apply.

**Fix.** Make `_toUsd` non-view and call `cachedUsdPerRawUnit`. This also fixes V-1 for
free — the cache's last-good-value behaviour is the correct staleness semantics.

---

### A-1 — `/api/fren-ask` lets a caller supply its own system prompt via a header
**Low–Medium · Bug**

**Location:** `api/fren-ask.ts:55-69`

`loadDocs` builds its fetch URL from `x-forwarded-host` / `x-forwarded-proto` —
**attacker-controlled request headers** — and the response is spliced into the system
prompt as `DOCS (source of truth)`.

An attacker points the header at a host they control and serves an arbitrary system
prompt, turning the endpoint into a **free general-purpose LLM proxy billed to the
project's Groq/Gemini key**. The rate limit is in-memory per warm serverless instance
(honestly documented as best-effort at `:101-104`) and does not bound this across
instances. Not reachable against another *user* — browsers cannot set the header — so
impact is cost and quota, not victim compromise.

Secondary: `history` is fully client-supplied, so an attacker can fabricate assistant
turns to steer output. Impact is limited to brand-attributed text; the model has no
tools and no write path.

**Fix.** Pin the docs URL to a constant, or validate `host` against an allowlist.

---

### A-2 — Indexer GraphQL is public with `cors: *` and no complexity limit
**Low · Design risk**

**Location:** `indexer/src/api/index.ts:11, 32-33`

GraphQL is mounted at `/graphql` and `/` with `origin: process.env.CORS_ORIGIN ?? "*"`.
No depth or complexity limiting is visible. A nested query is a cheap way to exhaust the
indexer, which is the frontend's **entire read layer**. The watchdog would restart the
container, converting it into a restart loop rather than a fix.

---

### A-3 — 18 of 19 indexer consumers have no freshness gate
**Low · Design risk** — see §2.5. The gate exists and is good; it is applied once.

---

### A-4 — Unsanitized SVG injection sinks
**Informational**

`dangerouslySetInnerHTML` with raw SVG at `LiquidatoorBadges.tsx:249,266`,
`LiquidatoorModal.tsx:64`, `ArchiveMachine.tsx:264`, `LiquidatoorBadgeLab.tsx:33,37`.

**Currently safe** — the markup is generated client-side by `liquidatoorBadgeSVG` from
viem-decoded typed values (addresses, numbers), never from a `tokenURI` or any string
field. `Docs.tsx` correctly uses `DOMPurify`. The risk is that there is no sanitization
backstop: the first change that pipes a string field (a collection name, a trait) into
badge art becomes stored XSS. `api/cauldron/liquidatoor.ts` is well-defended by
comparison (`esc()`, digit-stripping, address regex).

---

### A-5 — `emergencyAdmin` is immutable and can take the whole LP
**Informational · Design risk (accepted, but state it plainly)**

`CauldronRegistry.sol:116` / `:398-407`. Timelocked on mainnet and arming-gated even at
delay 0 — both good. But the protocol's headline claim is protocol-owned LP with no
team rug, and that claim rests on a **single key with no rotation path**. A compromise
is unrecoverable by design: the attacker arms, waits out the delay, and takes the LP.

---

### A-6 — `fren-teach` secret comparison is non-constant-time and unthrottled
**Informational** — `api/fren-teach.ts:24`. `provided === ADMIN_SECRET` plus no rate
limit on 401s. Remote timing attacks on string compare are impractical over Vercel;
the missing throttle on an unauthenticated brute-force surface is the more real half.
SQL is correctly parameterized via `neon` tagged templates throughout.

**Secrets: clean.** `.env.local` and `.env.vercel-backup` are untracked, covered by
`.gitignore` (`.env*` + `!.env.example`), and **never appeared in git history**. No
secret reaches the client bundle — I grepped `dist/` for all of
`X_CLIENT_SECRET`/`GEMINI_API_KEY`/`GROQ_API_KEY`/`FREN_ADMIN_SECRET`/`DATABASE_URL`/`PRIVATE_KEY`
and found nothing. The only `VITE_`-exposed identifier is `VITE_X_CLIENT_ID`, which is
public by OAuth design.

---

## 4. The frontier

### 4.1 Dividend over a basket — the doc is superseded by the code, and correctly so

`TREASURY_FUND_PLAN.md` judges option 3 (one USD accumulator, settled in a chosen
asset) "almost certainly right". **The shipped code chose option 2** (per-asset
accumulators) and `MiFrensDividend.sol:93-100` argues option 3 is *wrong*:

> *"if entitlement is USD but settlement is in assets, whoever claims at a favourable
> moment takes more real value than their share, and the last claimant eats the
> difference."*

**I agree with the reversal, and the reasoning is exactly right.** To answer the two
questions as posed:

**What breaks when the oracle is stale at claim time?** Under option 3, everything.
Entitlement is a USD number; settlement needs a price to convert it. A stale price means
either the claim reverts (a liveness failure on the one path that must always work) or
it settles at a wrong price (a solvency failure). There is no third option, which is
what makes option 3 structurally unsound rather than merely inconvenient. **Option 2
needs no oracle at claim time at all** — that is its decisive advantage, and it is why
the reversal is correct.

**What is the settlement-side solvency condition?** Under option 3 it is
`Σ_holders entitlement_usd ≤ Σ_assets (balance_a × price_a)` — an inequality over
*prices*, so it can be violated with no state change at all, purely by the market
moving. A protocol cannot maintain an invariant it does not control the terms of. Under
option 2 the condition degenerates to the per-asset identity
`balance_a ≥ Σ_holders pending_a`, which is oracle-free and locally checkable. That is
the invariant worth writing (I13).

**However**, the doc's own warning about option 2 — *"strands dust in assets nobody
wants to claim"* — came true and considerably worse than predicted. It is not dust: it
is D-1, D-2 and D-3. The choice was right; the implementation shipped three bugs that
all live in the machinery option 2 requires (a list, a loop, a bound). Fix those three
and option 2 is the right long-term answer.

One further gap: `fundToken` tracks no residual, unlike the ETH `receive()` path which
carries `residual` forward. Sub-share dust is silently lost per deposit. Minor, but it
breaks the symmetry the rest of the contract maintains.

### 4.2 EIP-170 on the hook — already solved; the constraint has moved

**The doc is stale.** The `FeeRouteLib` conversion **already landed** in `710e138`,
using exactly the structural fix the library's own header describes: collapsing the
sends that always happen together into `routeSplit`/`routePerp` so the *call sites*
stop paying to encode arguments five times.

Measured at HEAD (`forge build --sizes`, `FOUNDRY_PROFILE=cauldron`, limit 24,576):

| Contract | Runtime | Margin |
|---|---|---|
| **CauldronHook** | 24,408 | **168 B** |
| **CauldronRegistry** | 24,566 | **10 B** |
| **PerpEngine** | 24,563 | **13 B** |
| PoolOps | 22,496 | 2,080 B |
| FeeRouteLib | 1,772 | 22,804 B |
| MiFrensDividend | 6,427 | 18,149 B |

So: the hook has **168 bytes, not 30**, and the proposed `_routeFee`/`_routePerpFee`
wholesale extraction is **no longer needed** — the cheaper collapsing already reached
it. I would not do the extraction now: it would cost an extra `delegatecall` (~2,600
gas) plus argument encoding on the hottest path in the protocol, to buy headroom that
is not currently the binding constraint.

**The real EIP-170 crisis has moved to `CauldronRegistry` (10 B) and `PerpEngine`
(13 B).** Both are effectively unmodifiable. This matters directly: R-1's proper fix
(a per-asset reserve with a matching release path) needs bytes in *both* the hook and
the registry, and the registry has ten. **Freeing registry bytecode is a prerequisite
for fixing R-1, not an independent cleanup.** The registry already uses a
facet/delegatecall pattern (`RedemptionExt`, `_facet` storage tests) — extending that to
the relaunch path is the natural move.

Gas cost of what already shipped: `routeSplit`/`routePerp` add one `delegatecall` per
fee route versus inline branching, ~2,600 gas plus ABI encoding, against a swap that
already costs 200k+. Under 2%. Worth it.

### 4.3 Which pool the perps trade — confirmed, with a correction

Confirmed as stated: `_key()` derives from a single `quote`, so perps mark, size and
liquidate against the primary pool. **But the failure mode is the mark, not the depth
bound** — see P-1. The depth bound fails safe (a thinning primary tightens limits); the
mark fails dangerous (a thinning primary is cheap to push while the deep sibling sets
the real price).

That distinction changes the fix. Bounding size against the *sum* of pool depths — one
of the two options the doc offers — would make things **worse**: it grants larger
positions justified by liquidity the engine cannot actually mark against. The correct
fix is the other one, and it must come first:

1. **Mark against the deepest pool**, re-evaluated at each `syncGeneration`, or better,
   a liquidity-weighted mean tick across the generation's pools.
2. **Only then** bound size against aggregate depth — and only over pools that
   participate in the mark.
3. **Cap the number of perp-eligible pools** so `_writeObs` and the liquidation sweep
   stay gas-bounded inside `afterSwap`.

### 4.4 Target architecture and migration sequence

The protocol is deployed, so ordering matters more than the end state. Each phase is
independently shippable and leaves the system correct.

**Phase 0 — stop the bleeding (before any non-ETH pool exists).**
- Fix V-1: `_toUsd` treats 0 as "cannot judge" via `cachedUsdPerRawUnit` (also fixes G-1).
- Fix D-1: gate `fundToken` to the hook / `allowedQuote`.
- Fix D-2: per-asset `try`/`catch` + `removeAsset`.
- Fix D-3: `owedAsset` + `withdrawOwedToken`.
- Fix T-1: `vm.skip(true)`; add a `forge test` CI job.
- *All four contract fixes are in `MiFrensDividend` (18KB spare) and the hook (168 B).
  None needs registry bytecode. This phase is unblocked today.*

**Phase 1 — make the reserve asset-aware (the R-1 blocker).**
- Free registry bytecode by moving the relaunch path behind the existing facet pattern.
- `mapping(address => uint256) relaunchReserve` + `releaseRelaunchAsset(address)`.
- Registry chooses the seeding asset; `legacyBuffer` gets the same treatment.
- Add invariant I16: every asset the hook holds has a non-zero exit path.
- **Gate:** no non-ETH generation may be summoned until this ships.

**Phase 2 — bounded multi-pool per generation.**
- Explicit, capped pool set per generation (the doc's "bounded pool count" guardrail).
- `isDead()` already sums siblings — extend the sibling registration path.
- Add invariant I12: the volume ledger has one unit, asserted across mixed quotes.

**Phase 3 — perp mark correctness (the P-1 blocker).**
- Liquidity-weighted mark across the generation's perp-eligible pools.
- Then aggregate depth bounding; then the pool cap.
- **Gate:** no generation runs more than one pool *with perps enabled* until this ships.

**Phase 4 — treasury operations.** `arbStep()`, governor proposal types
(diversify / consolidate / rebalance), `TreasuryGovernor` tests. The doc is right that
voting maths should not ship on inspection alone — `TreasuryGovernor.sol` is 329 lines
with one test file.

**Ordering rationale:** Phase 0 is pure bug-fixing with no new surface and no dependency
on anything. Phase 1 is the true prerequisite for the multi-quote feature and is
bytecode-blocked, so its real first task is the facet extraction. Phases 2 and 3 are
independent of each other but both depend on 1. Phase 4 depends on 2.

---

## 5. Test-coverage gap analysis

Ranked by value at risk behind the gap.

| # | Gap | Value at risk | Evidence |
|---|---|---|---|
| 1 | **No invariant suite runs without `FORK_RPC`, and none builds a non-ETH pool.** The exact invariant R-1 violates is written twice and asserted in neither the default run nor any multi-quote scenario | entire relaunch reserve; the flywheel | `CauldronSystemInvariants.t.sol:329`, `ZSystemInvariants.t.sol:59` |
| 2 | **Nothing tests the hook's consumption of an oracle `0`.** The oracle's five refusal paths are all covered; the seam is not | whole generation LP via a false death | `QuoteOracle.t.sol` vs `CauldronHook.sol:628` |
| 3 | **`fundToken` is never tested from a non-hook caller.** `test_AssetListIsBounded` funds 8 assets from the test contract and treats it as normal | all basket dividends, permanently | `DividendBasket.t.sol:118-135` |
| 4 | **No test transfers an enchanted fren while ERC20 dividends are pending.** `F09` covers the ETH path thoroughly | per-holder basket accruals | `F01_CustodyAndConsent.t.sol` |
| 5 | **No hostile-token test anywhere in the basket.** No pausable, blacklisting, fee-on-transfer or false-returning token is exercised against `claimTokens` | all basket dividends | — |
| 6 | **No multi-pool generation exists in any test**, so P-1, sibling volume summation and aggregate depth are all unexercised | perp solvency | `isDead()` sibling loop is untested |
| 7 | **Perp engine's 30 tests are entirely vacuous locally.** The sharpest code in the repo has zero default-run coverage | perp collateral | `PerpEngine.t.sol:51` |
| 8 | **`TreasuryGovernor` (329 lines) has one test file**; the doc itself flags this | quote rotation authority | `TreasuryGovernor.t.sol` |
| 9 | **No decimals-crossing fuzz.** `VolumeUnits` asserts scale for one 6-dp quote at one price; no property test across {6,8,18} dp × price range | mispriced volume, mint-out cost | `VolumeUnits.t.sol:204` |
| 10 | **No indexer/API tests at all**; no test asserts the frontend degrades correctly on stale indexer data | UI correctness | — |

**What the suite does well**, and it is worth saying: the attack suites (`A*`, `Y*`,
`Z*`) are real adversarial tests, not checkbox tests, and several are named after
findings they permanently pin (`Z02_PerpStaleMark`, `Y01_ReserveCeilingBreach`,
`F03_SweepDebitsExactlyWhatMoved`). The `test_REFUTED_*` and `test_KnownDeviation_*`
naming — tests that record what is *not* a bug and where reality deviates from the ideal
— is a discipline I rarely see and it made this audit substantially faster.

---

## 6. What I could not verify

**Ran successfully.** Full suite locally (`443 passed, 3 skipped`) and against a Sepolia
fork via `ethereum-sepolia-rpc.publicnode.com` with the runbook's `POOL_MANAGER` /
`POSITION_MANAGER` (`461 passed, 1 skipped, 0 failed`). **Both commit-message numbers
reproduce exactly.** All five of my PoCs pass.

**Could not verify:**

- **The live round-34 deployment state.** I audited the code at `0a1830b`, not the
  contracts actually at those addresses. I did not verify the deployed bytecode matches
  this commit, nor read live storage. `deathThresholdEth: 0` in the manifest implies
  death detection is currently *disabled* on the live deployment (`vol < 0` is never
  true), which would mean V-1 is not presently exploitable there — **I did not confirm
  this on-chain and it should be checked before relying on it.**
- **`vendor/BaseHook.sol` against upstream v4-core.** In scope and not done. I read it
  for hook-permission correctness but did not diff it line-by-line against the pinned
  `v4-core` revision. A vendored base hook is exactly where a subtle divergence hides.
- **The CREATE2 / hook-address-mining interaction.** `A01_Create2Squat` passes and
  `MinedTokenAddress` covers the token side, but I did not independently re-derive that
  the mined hook address's permission bits match `getHookPermissions()`.
- **P-1 has no PoC.** It needs a two-pool generation with skewed depth, which the
  current registry cannot construct. **It is a hypothesis**, argued from the code, not a
  demonstrated exploit.
- **Gas figures for §4.2 are estimated**, not measured. I measured contract *sizes*
  precisely; the ~2,600 gas `delegatecall` cost is a standard figure, not a benchmark of
  this code.
- **Frontend and indexer were surveyed, not audited.** I read the API routes in full and
  traced the trust boundaries and data flow, but did not review the 43 components or 29
  hooks individually, and ran neither `npm run test:unit` nor the Cypress suite.
- **`MagicFrensPeg.sol`, `MagicFrensPresale.sol`, `render/*`** are excluded from the
  `cauldron` profile and I did not audit them under the `render` profile.
- **No economic/simulation modelling.** `DEATH_SPIRAL_ANALYSIS.md` and
  `FLYWHEEL_ECONOMICS.md` make quantitative claims about flywheel sustainability that I
  read but did not independently model.
- **Neon/Postgres and Railway configuration** were out of reach — I could not check
  actual DB permissions, network exposure, or whether `CORS_ORIGIN` is set in
  production (the code default is `*`).

---

*Five PoCs added under `contracts/solidity/test/audit/`: `AuditPoC5_DividendBasket.t.sol`
(local, 3 tests), `AuditPoC6_QuoteReserve.t.sol` and `AuditPoC7_StaleOracleDeath.t.sol`
(fork-gated, 1 test each). All pass, and each asserts the broken behaviour so it fails
once fixed.*
