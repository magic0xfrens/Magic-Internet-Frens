# P2.5 — Artifact Parity (pre-flight, Robinhood mainnet 4663)

Scope: *will the mainnet deploy ship the source we just reviewed, and can the manifest be
filled completely?* Inspection only — **nothing in the tree was modified**. The one write
outside this file was a copy of `verify-manifest.mjs` + the template into `/tmp/mpcheck/`
so the real guard could be executed against the real template.

Tree state at review: branch `redteam/2026-09-13`, HEAD `f3d3f9e`, with
`contracts/solidity/cauldron/PerpEngine.sol` and `PerpSwapLib.sol` **uncommitted and
in flux** (a fixer is mid-work). Per the brief, transient ABI churn in
`PerpEngine`/`CauldronHook` is not counted as a defect — but a *size* overflow is not
churn, and §5 records one.

Tags: **VERIFIED** = ran it or read the exact lines · **DERIVED** = reasoned from verified
facts · **UNKNOWN** = could not determine.

---

## 1. Selector verification: wired, and complete?

### 1a. Is it wired? — **claim TRUE, VERIFIED (3/3)**

`grep -rn "verify-selectors"` across the tree (excluding `node_modules`/`.git`/`out`)
returns three live call sites, all aborting:

| Caller | Line | Abort mechanism |
|---|---|---|
| `scripts/apply-deployment.mjs` | `:212-223` | `spawnSync(process.execPath, [verify-selectors.mjs])`, then `if (gate.status !== 0) … process.exit(1)` |
| `scripts/auto-deploy.sh` | `:182` | `node "$ROOT/scripts/verify-selectors.mjs" \|\| die "selector parity FAILED …"` |
| `.github/workflows/deploy.yml` | `:70-73` | `run: node scripts/verify-selectors.mjs`, `env: RPC_URL: ${{ secrets.RPC_URL }}`; the `frontend` job `needs: [verify, contracts]` |

The last round's finding ("called by nothing", `hunt/H5_offchain_frontend.md:20` of R45) is
**closed**. `apply-deployment.mjs` is genuinely the choke point: `go-testnet.sh:241` and
`deploy-testnet.sh` both reach the manifest through it.

Caveat, VERIFIED at `apply-deployment.mjs:216-222`: the gate runs **after**
`writeFileSync(manifestPath, …)` at `:200`. On a failure the manifest has already been
rewritten; the script says so explicitly ("The manifest … was written and is NOT safe to
ship"). Correct behaviour, but the operator must `git checkout` it, not just re-run.

### 1b. The real numbers — **claim SUBSTANTIALLY TRUE, VERIFIED**

Counted by evaluating the literal out of `scripts/verify-selectors.mjs:44-88`:

```
MANIFEST KEYS: 11 | top-level entries (gate units): 43 | distinct signature strings: 45
gachaRouter:3 nativeZap:1 collection:2 vault:1 registry:10 governor:3
treasuryGovernor:3 dividend:7 perpEngine:4 perpVault:8 presale:1
```

**11 keys — exact.** **43** is the count of *gate units*; because `governor`'s `propose`
is a 3-member overload group (`:65-69`) counted once, the number of *distinct signature
strings* is **45**. The ledger's "43 signatures" is off only in that accounting.

### 1c. GAP A — the gate's default RPC is **Sepolia**. HIGH for mainnet. VERIFIED

`scripts/verify-selectors.mjs:31`

```js
const RPC = process.env.RPC_URL ?? "https://sepolia.gateway.tenderly.co";
```

Nothing on a 4663 path sets `RPC_URL`. `auto-deploy.sh` carries its endpoint in `$RPC`
(`:18`, itself a Sepolia default) and **never exports `RPC_URL`**, so even the wired call
at `:182` would hit Sepolia. On chain 4663 every manifest address returns `0x`, the loop
at `:106` prints `FAIL <key> <addr>: NO CODE` for all 11 keys and exits 1.

This fails **loudly**, not silently — the gate is not bypassed. The hazard is human: a
gate that is red for every key on a legitimate deploy is a gate an operator skips. The
mainnet step must be, verbatim:

```
RPC_URL=https://rpc.mainnet.chain.robinhood.com node scripts/verify-selectors.mjs
```

Same for `apply-deployment.mjs`, whose chain-read fallbacks default to Sepolia at
`:252-253`, `:279`, `:295`, `:314`, and whose `--chain` argument defaults to `11155111`
(`:30-31`) — the broadcast it reads is `broadcast/<script>/<chain>/run-latest.json`
(`:38`), so a mainnet run needs `--chain 4663` or it reads the wrong directory entirely.

### 1d. GAP B — four REQUIRED keys are absent from the template, so they **SKIP**. VERIFIED

`verify-selectors.mjs:104`: `if (!addr || addr.startsWith("__")) { console.log("  SKIP …"); continue; }`.

`round.robinhood.template.json` pins 12 contract keys. Of the 11 REQUIRED keys,
**`nativeZap`, `collection`, `vault`, `treasuryGovernor` are not among them** — 7 of the
43 gate units would SKIP on a template-filled-by-hand manifest, including
`zap(...)`, `reveal/revealBatch`, `redeem(uint256)` and all three treasury-governor sends.

Three of the four are recoverable **only if `apply-deployment.mjs` is run**: it writes
`nativeZap` (`:154`), `treasuryGovernor` (`:149`) and resolves `collection` from the chain
(`:132`, `:311-336`). `vault` is per-generation and is **never** written to the manifest by
any script — `redeem(uint256)` is therefore structurally ungated. That is the exact shape
of the `playChurn` defect (a function the app sends, on a contract nothing compares).

### 1e. GAP C — REQUIRED is a *send* list; the app's *read* surface is larger. VERIFIED

Enumerated the app's call surface by `functionName:` across `src/`, `indexer/src/`, `api/`
and cross-checked against `REQUIRED`. Not covered, on contracts the manifest does pin:

- **`igniteCauldron()`** — a real state-changing send, `src/hooks/useMiFrensPresale.ts:181,190`,
  ABI at `src/config/presale.ts:50`. This is *the summon*. `presale` is a REQUIRED key but
  only `mint(uint256)` is asserted on it.
- **`oddsForPlay(uint256)`** (`src/config/cauldron.ts:212`, call site
  `src/components/cauldron/CrystalCauldronGame.tsx:228`) and **`playInCurveUnits(uint256)`**
  (`src/config/cauldron.ts:493`, call site `CrystalCauldronGame.tsx:203`). Both are **new
  this run** (`9bcf5be`, the odds/quote-oracle fix) and both are on the hook/router.
- Further hook/registry reads the UI renders from: `missStreak`, `progress`, `opened`,
  `generationPoolKey`, `generationPositionId`, `allowedQuote`, `envelope`, `legAt`,
  `legCount`, `lastEnvelopeAt`, `isVenueAllowed`, `floorPerFren`, `floorPerNFT`,
  `badgesOwed`, `owed`, `owedAsset`, `pendingToken`.

A missing *read* selector produces the identical failure the gate exists to catch: a revert
with empty data and a blank panel. DERIVED: extending `REQUIRED` with the reads above
(they are cheap — the check is a substring scan of runtime bytecode, no call is made)
closes the remaining surface.

`playChurn` itself now has a second defence: `src/hooks/useCauldronSwap.ts:73-102` probes
`eth_getCode` for the selector at runtime and falls back to `play`. VERIFIED.

---

## 2. Can the manifest be filled, with no `<FILL>` surviving?

### 2a. Would the guard reject a surviving `<FILL>`? — **YES, VERIFIED BY EXECUTION**

Ran the *real* `scripts/verify-manifest.mjs` against the *real*
`indexer/deployments/round.robinhood.template.json` (both copied into `/tmp/mpcheck/`; the
repo was not touched):

```
✗ manifest check failed (15):
  · `indexerUrl` must be an absolute http(s) URL
  · contracts.registry is not a 20-byte address: <FILL from DeployLaunchpad>
  … hook, governor, dividend, presale, gachaRouter, timelock,
    collectionLedger, perpEngine, perpVault …
  · blocks.deploy / blocks.perp / blocks.indexer must be a positive integer
  · poolIds[0] is not a 32-byte pool id: <FILL: gen-1 poolId from the summon tx>
EXIT=1
```

All **12** `<FILL>` tokens are named, plus the three `0` blocks. It runs on `prebuild`
(`package.json`: `"prebuild": "node scripts/verify-manifest.mjs && node scripts/sync-llms.mjs"`)
and at `.github/workflows/deploy.yml:64`. A placeholder cannot reach a bundle.

Residual, VERIFIED: the guard does **not** validate `genesisSupply`, `deathThresholdEth`,
`legacyThresholdEth`, `legacyBps` at all — see 2b.

### 2b. Per-key provenance

| Key | Source | Status |
|---|---|---|
| `chainId` 4663 | template literal | pre-filled; cross-checked against `VITE_CHAIN_ID` at `verify-manifest.mjs:51-57` |
| `schema` | template `cauldron_rh1` | **CONFLICT** — see 2c |
| `round` | template `1` | **CONFLICT** — see 2c |
| `indexerUrl` | **no script** | **UNFILLABLE by tooling.** Produced by the Railway dashboard after the indexer service is created. Human transcription; guarded only by the URL regex |
| `blocks.deploy/perp/indexer` | `apply-deployment.mjs:221-238` — min `blockNumber` across the receipts of all three broadcasts, minus 10 | fillable, **but** it writes the *same* value to all three, whereas the template's `_note` describes three different semantics. Harmless (indexer ≤ deploy is what `verify-manifest.mjs:104-110` requires) but the note is misleading |
| `contracts.registry/governor/dividend/presale/gachaRouter/collectionLedger/timelock` | `apply-deployment.mjs:123-137`, `pick()` over `DeployLaunchpad.s.sol/4663/run-latest.json` | fillable |
| `contracts.hook` | `apply-deployment.mjs:104-108` named CREATE2, else registry read `:288-297` | fillable |
| `contracts.perpEngine/perpVault` | `apply-deployment.mjs:155-156` from `DeployPerp.s.sol` broadcast; name match tolerates the `.0.8.30` suffix (`:77-84`) | fillable |
| `contracts.poolManager` / `positionManager` | template literals `0x8366a3…0951` / `0x58daec…4fa7` | pre-filled and **VERIFIED identical** to `docs/MAINNET_LAUNCH.md:33-34` |
| `contracts.collection` | `apply-deployment.mjs:311-336`, chain read `currentGeneration()`→`generationCollection()` | fillable **only after the summon**; needs a second `apply-deployment.mjs` run |
| `contracts.seeder` | `apply-deployment.mjs:288-305`, chain read `seeder()` | fillable |
| `contracts.nativeZap / quoteRotator / treasuryGovernor / quoteOracle / factory` | `apply-deployment.mjs:138-154` | fillable; **not in the template**, so they only exist if the script runs |
| `poolIds[0]` | `apply-deployment.mjs:251-273`, `currentGeneration()` + `generationPoolId()` | fillable **only after `igniteCauldron()`**; second run required |
| `quoteAssets` | **no mainnet source** — `apply-deployment.mjs:180-212` only rewrites entries whose `symbol` is literally `"USDG"`/`"xNVDA"`, and only from a `MockQuoteToken` CREATE | **UNFILLABLE by tooling on mainnet.** There will be no `MockQuoteToken`, so `:190-198` prints its loud "quoteAssets NOT UPDATED" error — on mainnet that is a **false alarm** an operator must be told to ignore. Every real quote governance will approve must be typed in by hand |
| `genesisSupply`, `deathThresholdEth`, `legacyThresholdEth`, `legacyBps` | **no script; no guard** | **UNFILLABLE by tooling** and unchecked. They must mirror the deploy-script env (`DEATH_THRESHOLD`, `LEGACY_BPS`, `GENESIS_BONUS_BPS`, `MAINNET_LAUNCH.md:49-52`). The template ships `deathThresholdEth: 0` against a runbook that sets `DEATH_THRESHOLD=1e18` — a silent mismatch today |

### 2c. `round`/`schema` conflict — MEDIUM, VERIFIED

The template pins `round: 1`, `schema: "cauldron_rh1"`, and its `_comment` says *"Keep
`schema` a NEW value so Ponder does a clean reindex"*. But `apply-deployment.mjs:355-366`
unconditionally overwrites both whenever anything changed:

```js
m.round = prevRound + 1;
m.schema = `cauldron_r${m.round}`;
```

Running it against the filled template yields `round: 2`, `schema: "cauldron_r2"` — a name
that **collides with the Sepolia round-2 schema** if the two ever share a Postgres
instance, and which discards the `rh1` namespacing the template deliberately chose. Fix or
re-edit `schema` by hand *after* `apply-deployment.mjs`, and re-run `verify-manifest.mjs`.

---

## 3. Frontend chain config for 4663

### 3a. The `800271a` fix holds — VERIFIED

- `src/config/deployments.ts:43-45` — `DEPLOYMENTS` is `Object.fromEntries(BUNDLED.map(m => [m.chainId, m]))`. Keyed by each manifest's **own** `chainId`; the Sepolia-key shadowing is unrepresentable.
- `:49-54` — two manifests on one chain id **throws**.
- `:120-127` — `VITE_CHAIN_ID` naming a chain no bundled manifest declares **throws**.
- `:136-141` — an unrecognised `VITE_NETWORK` **throws**.
- `:142` — the final fallback is `PRIMARY_CHAIN_ID = sepoliaRound.chainId`, i.e. **whatever `round.json` itself pins**. Once `round.json` is the 4663 manifest, an *unset* `VITE_CHAIN_ID` still resolves to 4663. No hardcoded chain id remains in the resolver.
- `src/config/chains.ts:35-36` — `CHAIN_ID` derives from `SELECTED_CHAIN_ID` / `DEPLOY_CHAIN_IDS`; the old independent Arc default (5042002) is gone.
- `src/config/chains.ts:62` — `CHAIN_DEFAULTS[4663]` = `rpc.mainnet.chain.robinhood.com`, Blockscout, ETH/18, `testnet:false`. **VERIFIED correct.**
- `src/config/chains.ts:71-80` — unknown chain **and** unset `VITE_RPC_URL` **throws** rather than borrowing another chain's RPC.
- `src/config/chains.ts:87-89` — `BACKUP_RPCS[4663]` is the single CHAIN_PROFILE §8-verified `robinhood-rpc.publicnode.com`. No unverified host.
- Dead-host sweep: `grep -rn "rpc.chain.robinhood.com"` (excluding the `mainnet.`/`testnet.` forms) hits **only** warning comments (`src/config/chains.ts:60`, `indexer/ponder.config.ts:118`, `indexer/src/api/index.ts:142`, `docs/*`) and audit artifacts. It is not a default anywhere. **Clean.**

### 3b. Loud-vs-silent: what actually fails a *build*

Precise, because it matters: `chains.ts` / `deployments.ts` throws are **module-init**
throws. Vite does not evaluate them during `vite build`, so they produce a white screen at
runtime, **not** a failed build. The one genuine **build-time** chain gate is
`scripts/verify-manifest.mjs:51-57`, which runs on `prebuild`:

```
VITE_CHAIN_ID=<n> but indexer/deployments/round.json pins chainId <m> — the app would
load <m>'s addresses while telling the wallet it is on <n>
```

DERIVED consequence: **`VITE_CHAIN_ID=4663` should be set explicitly** even though it is
redundant with the manifest — it is the only value that converts a manifest/env divergence
into a red build instead of a white screen.

### 3c. Env vars for a 4663 build, and what each does if unset (VERIFIED against source)

**Vercel — frontend**

| Var | Read at | Unset ⇒ |
|---|---|---|
| `VITE_CHAIN_ID` | `deployments.ts:118` | resolves to `round.json`'s own `chainId` (4663) — correct, but the `verify-manifest` cross-check at `:51-57` is skipped. **Set it to 4663.** |
| `VITE_NETWORK` | `deployments.ts:134-141` | primary slot = `round.json` = 4663. `"mainnet"` is also fine. `"arc"` selects `round.arc.json` — **do not set** |
| `VITE_RPC_URL` | `chains.ts:72` (via the dynamic `env()` helper) | `rpc.mainnet.chain.robinhood.com` + publicnode backup. Safe |
| `VITE_CHAIN_NAME` / `_CURRENCY` / `_CURRENCY_NAME` / `_DECIMALS` / `_IS_TESTNET` | `chains.ts:69,113,114,103-107,126` | all default correctly from `CHAIN_DEFAULTS[4663]` (Robinhood Chain / ETH / Ether / 18 / `false`). Safe |
| `VITE_EXPLORER_URL` / `_NAME` | `chains.ts:81,97` | Blockscout. Safe |
| `VITE_WALLETCONNECT_PROJECT_ID` | `chains.ts:130-136` | WalletConnect connector is **silently omitted**; injected wallets only, no mobile. **Set it.** |
| `VITE_SEPOLIA_RPC_URL` | `chains.ts:150` | irrelevant on 4663 (Sepolia stays bundled as the switcher's other leg) |
| `VITE_TREASURY_ADDRESS`, `VITE_PRESALE_ADDRESS`, `VITE_MAGIC_FRENS_PEG_ADDRESS`, `VITE_MINT_PRICE_ETH`, `VITE_DEX_URL`, `VITE_X_CLIENT_ID`, `VITE_APP_TENDERLY_*` | legacy/marketing paths | cosmetic; none carry deployment identity |
| `VITE_CAULDRON_INDEXER` | **nowhere** | dead. It is in `verify-manifest.mjs:173` `BANNED_ENV` — if any code ever read it the build fails. The indexer URL is manifest-only |

**Vercel — serverless (`api/`)**

| Var | Read at | Unset ⇒ |
|---|---|---|
| `API_RPC_URL` | `api/cauldron/creature.ts:47-50`, `api/cauldron/liquidatoor.ts:29-32` | **defaults to five SEPOLIA public nodes.** See 3e |

**Railway — indexer**

| Var | Read at | Unset ⇒ |
|---|---|---|
| `PONDER_RPC_URL` | `indexer/ponder.config.ts:129-141` | **fixed**: `BY_CHAIN[4663] = ["https://rpc.mainnet.chain.robinhood.com"]`, and an unknown chain now **throws** instead of defaulting to Sepolia. Safe (a dedicated endpoint is still better) |
| `API_RPC_URL` | `indexer/src/api/index.ts:133-158` | **fixed**: `API_RPC_DEFAULTS[4663]` = mainnet RH + publicnode; unknown chain throws. Safe |
| `DATABASE_URL` | `indexer` | in-memory SQLite. **Required in production** |
| `POLLING_INTERVAL_MS` | `ponder.config.ts` | default; runbook recommends `1000` for ~0.10 s blocks |
| `DATABASE_SCHEMA`/`POOL_IDS`/`PERP_ENGINE`/… | — | **must stay unset** — `deploy-round.mjs` warns about exactly this drift class |

### 3d. H5's 31-var table is **STALE** — do not use it as-is

Checked rather than copied. `hunt/H5_offchain_frontend.md:374-392` describes the
**pre-fix** world and its line numbers no longer resolve:

- `:374` "`VITE_NETWORK` … **Neither value can reach 4663**" — false since `800271a`; the resolver now ends at the manifest's own chainId (`deployments.ts:142`).
- `:375` "`VITE_CHAIN_ID` defaults **5042002 (Arc testnet)** … ignored whenever `SELECTED_CHAIN_ID !== sepolia.id` (`chains.ts:37`)" — false; there is no Arc default left, and `chains.ts:35-36` derives from the manifest set.
- `:376-383` cite `chains.ts:45,46,47,48,54-56,63,75` — all off; the real lines are `69,72,81,97,103-107,114,126`.
- `:388` "`PONDER_RPC_URL` … **sepolia.gateway.tenderly.co** for chainId 4663" — false since `f59425e` (`ponder.config.ts:129-141`).
- `:390` `PONDER_MAX_RPS` and `:402` `X_CLIENT_SECRET`/`VITE_X_CLIENT_ID` rows remain accurate.
- `:386` `VITE_CAULDRON_INDEXER` "dead var" remains accurate.

### 3e. Residual — the **serverless** routes were never chain-keyed. MEDIUM, VERIFIED

`f59425e` chain-keyed the *indexer's* API client (`indexer/src/api/index.ts:133-158`,
with a fatal throw for an unknown chain). The two **Vercel** routes were not:

```
api/cauldron/creature.ts:47-50      const RPCS = (process.env.API_RPC_URL ?? [
api/cauldron/liquidatoor.ts:29-32     "https://ethereum-sepolia-rpc.publicnode.com", …
```

A `??` over a literal Sepolia array — no chain key, no throw. On a 4663 production build
with `API_RPC_URL` unset on Vercel, the creature-art renderer (`rarityOf`, `revealed`) and
the liquidator-badge endpoint (`liqStats`) read **Sepolia** and return empty or wrong art
silently. No funds at risk; it is a visibly-broken-feature class. Either chain-key them the
way `indexer/src/api/index.ts` now is, or set `API_RPC_URL` on Vercel *and* Railway.

### 3f. Runbook drift — `docs/MAINNET_LAUNCH.md` §3 and §5. LOW, VERIFIED

`d209241` fixed the RPC host and `docs/protocol/11-OPERATIONS.md`, but `MAINNET_LAUNCH.md`
§5 was not swept:

- `:106` tells the operator to set **`VITE_CAULDRON_INDEXER`** — dead (`BANNED_ENV`, `verify-manifest.mjs:173`), and `.env.example:17-20` says so explicitly.
- `:108` tells them to set **`VITE_ROBINHOOD_*`** — the *same document* says at `:29` that "the `VITE_ROBINHOOD_*` names this doc used to list are read by no code."
- `:105` calls `VITE_NETWORK=mainnet` "← the flip" and **never lists `VITE_CHAIN_ID=4663`**, contradicting its own `:6-8` and `:15`.
- `:95` says verify **`/health`** — `indexer/src/api/index.ts:1384` states that path is *Ponder's built-in* and ours is deliberately **`/freshness`** (`:1389`). Same error the prior round's memo flagged.
- `:100-102` (the round.json checklist) omits `positionManager`, `perpEngine`, `perpVault`, `poolIds`, `blocks.perp`, `blocks.indexer` and `quoteAssets`.

---

## 4. ABI parity — **199 → 268 entries, still zero real mismatches. VERIFIED**

Rebuilt from source (`FOUNDRY_PROFILE=cauldron forge build --sizes`; compiled clean) and
diffed every ABI the app carries against the artifacts, comparing **tuple components
recursively** and **event `indexed` flags**, not just names and arities.

*Method note:* `forge inspect` currently errors on source resolution (a missing nested
`lib/v4-periphery/lib/v4-core/lib/openzeppelin-contracts/...draft-EIP712.sol`; the OZ
submodule is dirty per `git status`), so the ABIs were read straight from the freshly built
`contracts/solidity/out/**/*.json` artifacts — the same JSON `forge inspect` prints.

```
artifacts indexed: 4195 distinct signatures
app ABI entries compared: 268      (17 consts in src/config/*.ts, 15 in indexer/abis/*.ts)
parse failures: 0
SIGNATURE MISMATCHES: 1
ORPHANS (name absent from every artifact): 0
```

The single hit is **not a defect**:

```
✗ src/config/cauldron.ts:GOVERNOR_ABI
    want  propose(string,string,uint8,string,address,string,string,uint256,uint256)
    near  propose(string,string,uint8,string,address,string,string,uint256,uint256,address)
          propose(string,string,uint8,string,address,string,string,string,string,uint256,uint256,address)
```

`CauldronGovernor` (48 ABI entries) carries the 10-arg and 12-arg forms. The 9-arg entry at
`src/config/cauldron.ts:341` is the deliberate **legacy overload for older deployed
governors** — `verify-selectors.mjs:65-69` lists all three as an "any one must be present"
group for exactly this reason, and the app picks by arity. Keeping it is correct.

Spot-confirmed the `indexed` half against the real artifacts, e.g.
`CauldronRegistry.CollectionDeployed(uint256 indexed, address, uint8)` and
`CauldronHook.CrystalsCommitted(address indexed, uint256, uint256)` — the app's declarations
match component-for-component and flag-for-flag.

**PerpEngine / CauldronHook**: no ABI mismatch is attributable to the in-flight uncommitted
work. `PerpEngineAbi` (indexer) and `PERP_ABI`/`PERP_VAULT_ABI` (frontend) all resolve
cleanly against the current artifacts. Note the artifacts carry both `PerpEngine.0.8.26`
and `PerpEngine.0.8.30` — the `pick()` suffix-tolerance at `apply-deployment.mjs:77-84`
exists for precisely this and is still needed.

The jump from the prior run's 199 to 268 is the surface this run added (the gacha odds
reads, the quote-decimals reads, the perp settle/queue entries). Parity survived it.

---

## 5. Build integrity

### 5a. Is a clean build forced before broadcast? — **Only on the Sepolia path. VERIFIED**

| Path | Build | Chain |
|---|---|---|
| `scripts/auto-deploy.sh:77-79` | `forge build --sizes --force` — comment: *"--force: a cached out/ is how r43/r44 shipped a router missing playChurn"* | **Hard-gated to Sepolia** |
| `scripts/deploy-testnet.sh:210` | `forge build --force` (no `--sizes`) | Sepolia |
| `scripts/go-testnet.sh:189` | `forge build --force` (no `--sizes`) | Sepolia |
| `docs/MAINNET_LAUNCH.md:54-55` — **the mainnet path** | bare `forge script deploy/DeployLaunchpad.s.sol --broadcast`. **No `forge clean`, no `--force`, no `--sizes`** | 4663 |

`scripts/auto-deploy.sh:64-65`:

```sh
CHAIN=$(cast chain-id --rpc-url "$RPC" 2>/dev/null)
[ "$CHAIN" = "11155111" ] || die "expected Sepolia (11155111), got '${CHAIN:-<no response>}'."
```

**The hardened deploy script cannot be used for the mainnet deploy at all.** Every guard it
carries — the forced clean build, the EIP-170 sweep, the suite/skip-count gates, the
manifest sanity check, the selector-parity call at `:182`, the post-deploy ownership
assertions — is behind that Sepolia check, and `grep -rln "4663" scripts/` returns only
`verify-manifest.mjs`. There is **no mainnet deploy script**; the runbook is a raw
`forge script`. So the exact stale-`out/` mechanism that shipped r43 and r44 broken is
**unguarded on the path mainnet will actually take**.

### 5b. The EIP-170 gate in `auto-deploy.sh` is reading the wrong column. LOW, VERIFIED

`scripts/auto-deploy.sh:81`:

```sh
OVER=$(awk -F'|' '/^\| [A-Za-z]/ {gsub(/[ ,]/,"",$4); if ($4 ~ /^-/) print $2" ("$4" B)"}' /tmp/ad-sizes.log ...)
```

With `-F'|'` the fields of a `forge build --sizes` row are
`$2=Contract, $3=Runtime Size, $4=Initcode Size, $5=Runtime Margin, $6=Initcode Margin`.
The gate tests **`$4`, the initcode *size***, which can never be negative — it is the
**margin** in `$5` that goes negative. Reproduced against this build's own log: the awk
returns nothing across 781 rows while five contracts are genuinely over.

Masked, not fatal: `forge build --sizes` itself exits non-zero on an over-limit contract, so
the `|| { … die "build failed."; }` at `:78` still aborts — but with a message that names
nothing. Change `$4` to `$5`.

### 5c. **The tree as it stands is undeployable: `PerpEngine` is 19 bytes over EIP-170.** VERIFIED

From this run's `forge build --sizes` (negative *runtime margin*, column 5):

```
PerpEngine.0.8.26   runtime 24,595   margin  -19
PerpEngine.0.8.30   runtime 24,595   margin  -19
X3iEngine           runtime 24,647   margin  -71   (test harness)
X9cEngine           runtime 24,647   margin  -71   (test harness)
Harness (K3d_…t.sol) runtime 24,884  margin -308   (test harness)
...
Error: some contracts exceed the runtime size limit (EIP-170: 24576 bytes)
```

`PerpEngine` is a **production** contract and it is over the limit. This is the uncommitted
fixer work on `cauldron/PerpEngine.sol` + `PerpSwapLib.sol` (`git status`), so it is not a
finding against reviewed source — but it **is** the current state of the tree, and a
`DeployPerp` broadcast from it would revert on `CREATE`. It must be measured back under
24,576 B and the whole pipeline re-run before any broadcast. (The three harnesses do not
matter, but they are why a naive "is the build green" check is misleading here.)

### 5d. The solc 0.8.30 ICE — could the deploy path hit it, and would it notice?

- **No ICE in this build.** `grep -i "Tag too large"` over the full log: zero hits. The `cauldron` profile compiled the entire tree including tests (781 size rows) without an internal compiler error.
- **Could the deploy path hit it?** DERIVED: **yes.** `forge build`/`forge script` under `FOUNDRY_PROFILE=cauldron` compiles the *whole* source set, `test/` included — that is exactly what produced the 781 rows above — so the fork-harness that triggered the ICE is inside the deploy path's compile set. It is not isolated to `forge test`.
- **Would the pipeline notice?** VERIFIED for the guarded paths: `auto-deploy.sh:78` (`|| die`), `deploy-testnet.sh:210` and `go-testnet.sh:189` all branch on the build's exit code. DERIVED for the mainnet path: `forge script` aborts on a compile failure by itself and nothing is broadcast — so a crash **is** noticed, but it surfaces as an opaque solc error rather than a named gate, and there is no `|| die` wrapper to say so.
- **No stale `out/` can ship on the guarded paths** (`--force`). On the mainnet path, `forge script` recompiles changed sources but reuses the cache — which is the r43/r44 mechanism.

### 5e. Read-only 4663 dry run — **NOT performed, deliberately**

`forge script --broadcast` needs `PRIVATE_KEY` and a funded deployer; a `--fork-url` dry
run of `DeployLaunchpad` still needs a signer and would mine the hook salt against live
state. Per the brief's rule 3, skipped. `contracts/solidity/.env` was never opened. No
network-mutating command was run at any point in this review; the only network the tooling
would have touched (`verify-selectors.mjs`) was not executed, because doing so against its
Sepolia default would have proved nothing about 4663.

---

## Closing answer

> **Will the mainnet deploy ship the source we just reviewed, and can the manifest be
> filled completely?**

**Not yet — on both halves.**

The *artifacts* are in good shape: ABI parity holds at 268 entries with zero real
mismatches, the selector gate is genuinely wired into all three paths it claims, the
manifest guard provably rejects every surviving `<FILL>`, and the chain-4663 frontend
Critical from earlier in this run is properly closed. What is not yet true is that the
**mainnet deploy path** inherits any of it: the hardened script refuses to run on 4663, the
gate that would catch a stale artifact defaults to querying the wrong chain, and four of
the manifest's values have no producer at all.

### Must be true before broadcast — for the runbook, verbatim

1. **`PerpEngine` is back under EIP-170.** It is currently 24,595 B / −19 B margin from the
   uncommitted `PerpEngine.sol` + `PerpSwapLib.sol` work. Re-measure with
   `FOUNDRY_PROFILE=cauldron forge build --sizes --force` and confirm no **production**
   contract shows a negative **Runtime Margin**.
2. **Deploy 4663 from a clean artifact set.** The mainnet path is a bare `forge script`
   with no `--force`. Run `cd contracts/solidity && FOUNDRY_PROFILE=cauldron forge clean`
   immediately before `DeployLaunchpad` / `DeployPerp`. (r43 and r44 shipped broken for
   want of exactly this.)
3. **Do not reach for `scripts/auto-deploy.sh`.** It hard-refuses any chain ≠ 11155111
   (`:65`). Either lift that gate to a `$EXPECT_CHAIN` variable — which brings its clean
   build, EIP-170 sweep, suite gate, manifest check and selector gate to mainnet — or
   perform each of those steps by hand. Do not assume the script ran them.
4. **Run the manifest folder against the right chain and RPC:**
   `RPC_URL=https://rpc.mainnet.chain.robinhood.com node scripts/apply-deployment.mjs --chain 4663`.
   Both flags are required; the defaults are `11155111` and a Sepolia node.
5. **Run the selector gate against the right chain:**
   `RPC_URL=https://rpc.mainnet.chain.robinhood.com node scripts/verify-selectors.mjs`.
   Without `RPC_URL` it queries Sepolia and reports NO CODE for all 11 keys. Expect a
   legitimate `SKIP vault` (never manifest-pinned) — treat any other SKIP as a hole.
6. **Ignore the `quoteAssets NOT UPDATED` error** that `apply-deployment.mjs:190-198` will
   print. It looks for a `MockQuoteToken` CREATE; mainnet has none. Fill `quoteAssets` by
   hand with every quote governance will approve, address **and decimals** — the decimals
   scale signed slippage floors.
7. **Fix `round` and `schema` after `apply-deployment.mjs` runs.** It overwrites them to
   `round: 2` / `schema: "cauldron_r2"` (`:355-366`), discarding the template's `cauldron_rh1`
   and risking a schema collision with the Sepolia deployment. Restore, then re-run
   `node scripts/verify-manifest.mjs`.
8. **Fill the four values no script produces:** `indexerUrl` (from Railway),
   `genesisSupply`, `deathThresholdEth`, `legacyThresholdEth`/`legacyBps` — the last three
   must mirror the `DEATH_THRESHOLD` / `LEGACY_BPS` / `GENESIS_BONUS_BPS` you actually
   deployed with. `verify-manifest.mjs` does **not** check them. The template ships
   `deathThresholdEth: 0` against a runbook that sets `1e18`.
9. **Run `apply-deployment.mjs` a second time after `igniteCauldron()`.** `poolIds[0]` and
   `contracts.collection` do not exist until the summon; both are chain reads, and
   `verify-manifest.mjs` will pass with an empty `poolIds` (by design, `:112-127`), so
   nothing will remind you.
10. **Set `VITE_CHAIN_ID=4663` on Vercel** even though the manifest already pins it. It is
    the only knob that turns a manifest/env divergence into a red build
    (`verify-manifest.mjs:51-57`) rather than a white screen at runtime.
11. **Set `API_RPC_URL` on Vercel** (and Railway). `api/cauldron/creature.ts:47-50` and
    `api/cauldron/liquidatoor.ts:29-32` still default to Sepolia nodes — they were missed
    when the indexer's client was chain-keyed. Better: chain-key them the way
    `indexer/src/api/index.ts:133-158` now is.
12. **Set `VITE_WALLETCONNECT_PROJECT_ID`.** Unset means injected wallets only — no mobile
    wallet can connect to the launch.
13. **Correct `docs/MAINNET_LAUNCH.md` §5 before anyone follows it.** It still instructs
    the operator to set the dead `VITE_CAULDRON_INDEXER` and `VITE_ROBINHOOD_*`, omits
    `VITE_CHAIN_ID=4663`, and §3 tells them to verify `/health` when the endpoint is
    `/freshness`. Do not hand an operator a checklist that contradicts its own preamble.

### Recommended, not blocking

- Extend `REQUIRED` in `verify-selectors.mjs` to cover `igniteCauldron()` on `presale` and
  the hook/registry **reads** the UI renders from — chiefly `oddsForPlay(uint256)` and
  `playInCurveUnits(uint256)`, both added this run. The check is a bytecode substring scan,
  so reads cost nothing to assert and fail identically when absent.
- Add `nativeZap`, `treasuryGovernor`, `quoteRotator`, `quoteOracle`, `seeder`, `collection`
  to the template as `<FILL>` so the guard demands them, instead of relying on
  `apply-deployment.mjs` having been run.
- `scripts/auto-deploy.sh:81` — change the awk field from `$4` to `$5` so the EIP-170 sweep
  can actually fire and name the offending contract.
- Regenerate `hunt/H5_offchain_frontend.md`'s 31-var table, or mark it superseded. Six of
  its rows now describe behaviour that was fixed during this run, and its `chains.ts` line
  numbers no longer resolve — it will mislead the next reader.
