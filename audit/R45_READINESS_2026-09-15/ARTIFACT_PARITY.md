# P2.5 Artifact & Wiring Parity — Round 45 Deploy Readiness

Compares round-44's ON-CHAIN Sepolia deployment (chainId 11155111) against the
currently-checked-out `contracts/solidity` source, using `indexer/deployments/round.json`
as the manifest. RPC = "the Alchemy endpoint" (never written literally above).

## A. Bytecode parity table (17 mapped contracts + 2 external)

| key | address | contractName | chain bytes | source bytes | delta | selectors missing on chain | verdict |
|---|---|---|---|---|---|---|---|
| registry | 0x3dc6...c10325 | CauldronRegistry | 24492 | 24661 | -169 | none | MATCH (metadata-only delta) |
| hook | 0xc6dc...d510cc | CauldronHook | 24530 | 23309 | +1221 | none | source shrank since deploy (older/bigger on chain) — not a missing-selector bug, but chain code predates recent hook edits |
| governor | 0xf0b1...036b3 | CauldronGovernor | 9302 | 9510 | -208 | none | MATCH (metadata-only) |
| dividend | 0x3d67...07cda | MiFrensDividend | 8050 | 8219 | -169 | none | MATCH |
| presale | 0xfd48...b92ba | MiFrensGenesis | 20470 | 20639 | -169 | none | MATCH |
| gachaRouter | 0x4658...82fda | CauldronGachaRouter | 8580 | 8983 | -403 | **df70b5a4 playChurn(uint256,uint256,uint256,uint256)** | **STALE ARTIFACT — the known r43/r44 bug is STILL LIVE on the currently-manifested address** |
| timelock | 0x987b...66b831 | TimelockController (OZ) | 5375 | 168 | +5207 | n/a | contractName mismatch — `forge inspect` resolved an unrelated/ambiguous OZ artifact (submodule `lib/openzeppelin-contracts` shows modified in git status); comparison invalid, not evidence of a bug |
| collectionLedger | 0x7377...80d9e80 | CollectionLedger | 1972 | 2141 | -169 | none | MATCH |
| perpEngine | 0xaD0b...a43C6 | PerpEngine | 24460 | 24416 | +44 | none | MATCH (chain code is 44 bytes larger, within immutable/metadata noise) |
| perpVault | 0x343b...27575b | PerpVault | 8002 | 9429 | -1427 | epochAcc(), stakerEpoch(address), totalTokYieldPulled(), yieldEpoch() | **source has evolved past deploy** — these 4 getters exist in source but not on chain; not app-called (not in `functionName` grep) so no user-facing break, but is a genuine staleness signal |
| factory | 0x88d3...abd3 | CauldronFactory | 18741 | 20028 | -1287 | none found by selector scan | source grew (likely refactor since deploy); needs a size re-check before r45 relies on any new factory selector |
| collection | 0xf850...d1a2c4 | (unresolved) | — | — | — | — | **NOT IN BROADCAST at all** (see B) — this is BY DESIGN per `apply-deployment.mjs`: the value is carried from a prior round's manifest because summon-time collections have no top-level CREATE to name |
| treasuryGovernor | 0x7da2...9e97f86 | TreasuryGovernor | 6653 | 6815 | -162 | none | MATCH (metadata-only) |
| quoteOracle | 0x9b79...4831e | QuoteOracle | 3821 | 3990 | -169 | none | MATCH |
| seeder | 0xc28b...ac2028 | VenueSeeder (assumed) | 15260 | 5365 | +9895 | not scanned (mapping unverified) | **address IS in run-latest.json but as a `null`-contractName CREATE** — my assumed contractName is unverified; +9895 delta is not trustworthy evidence of a bug, just a wrong comparison |
| nativeZap | 0x8059...566f41 | NativeQuoteZap | 2326 | 2495 | -169 | none | MATCH |
| poolManager | 0xE03A...203543 | — | — | — | — | — | EXTERNAL (Uniswap v4, expected) |
| positionManager | 0x429b...5c09b4 | — | — | — | — | — | EXTERNAL (Uniswap v4, expected) |

The recurring **exactly -169** delta across 7 unrelated contracts (registry, governor≈-208 close,
dividend, presale, collectionLedger, quoteOracle, nativeZap, treasuryGovernor≈-162) is a
metadata/CBOR-hash artifact of `forge inspect` vs. the on-chain deploy build, not a functional gap —
none of these lost a selector under the full methodIdentifiers scan.

**Real, actionable deltas: gachaRouter (-403, missing playChurn — matches the known live incident) and
perpVault (-1427, 4 missing getters not called by the app).** hook (+1221) and factory (-1287) need
attention before r45 because their sign shows the SOURCE and the DEPLOYED CODE have diverged since
round 44 in both directions — nobody has re-verified whether new hook/factory selectors the frontend
might start calling are actually on chain.

## B. Selector parity (STEP 1)

`scripts/verify-selectors.mjs` output (exactly 1 finding):
```
FAIL gachaRouter 0x465819232bd80d89423f5b8ee5b958c61bc82fda: 0xdf70b5a4 playChurn(uint256,uint256,uint256,uint256) ABSENT from deployed code
1 missing selector(s) — the app will revert with EMPTY data on those calls
```
Confirmed independently by grepping the raw runtime hex for the 4-byte selector on both the
gachaRouter (missing) and perpVault (4 selectors missing, listed above) — no other manifest
contract lost a source selector.

App-called `functionName` values total 112 call sites across ~80 distinct names (full list captured
in scratch). REQUIRED in `verify-selectors.mjs` covers only 5 manifest keys (gachaRouter, registry,
governor, perpEngine, dividend) and, within those, only a small allow-list of signatures. Names the
app calls that are NOT covered by REQUIRED (with the manifest key the call site's surrounding code
implies) include: `buyCollectionNFT`, `recycleCollectionNFT`, `redeemOgFren`, `floorPerFren`,
`floorPerNFT`, `soldOut`, `minted`, `revealed`/`reveal`/`revealBatch`, `render`, `renderer`,
`royaltyInfo`, `tokenURI` → **presale/collection**; `claimLiquidatorBadges`, `badgesOwed`,
`missStreak`, `oddsForPlay`, `rarityOf`, `castMany` → **gachaRouter/collectionLedger**; `depositEth`,
`depositToken`, `withdrawEth`, `withdrawOwed`, `withdrawOwedToken`, `claimPendingEth`,
`claimPendingToken`, `claimTokYield`, `claimTokens`, `owed`, `owedAsset`, `pendingToken`, `sweep`,
`vault` → **perpVault/perpEngine**; `rotateSliceFrom`, `legAt`, `legCount`, `envelope`,
`lastEnvelopeAt`, `isVenueAllowed`, `proposalCount`, `getProposal`(covered), `execute`,
`generationCollection`, `generationPoolKey`, `generationPositionId`, `generationToken` →
**quoteRotator/treasuryGovernor/registry**; `igniteCauldron`, `relaunch`, `extsload`, `zap` →
**hook/registry/nativeZap**; `claimByBurn`, `redeem`, `progress`, `finalized`, `closed`, `opened` →
**presale/collectionLedger**. Standard ERC20/721 names (`balanceOf`, `approve`, `allowance`, `mint`,
`symbol`, `decimals`, `ownerOf`, `safeTransferFrom`, `transferFrom`) are correctly out of scope for a
custom-selector check. **The gap is real: REQUIRED only guards ~10% of what the app actually calls;
the script would not have caught a second `playChurn`-shaped bug on any of these other ~60 functions.**

## C. Manifest ↔ broadcast freshness (STEP 2)

All 17 non-external manifest addresses trace to a CREATE in `DeployLaunchpad.s.sol` or
`DeployPerp.s.sol` run-latest.json **except**:
- `collection` (0xf850df1ae54c45433579b09909d1d6cb26d1a2c4) — **absent from every run-*.json in
  both broadcast trees.** `scripts/apply-deployment.mjs` (~line 310) explains why: it deliberately
  carries this value forward from the previous round's manifest with the comment "the summon, so no
  broadcast can name it." This is a documented design choice, not an accidental staleness bug — but
  it means bytecode/ABI parity for `collection` **cannot be verified from broadcast at all** and must
  be checked purely on-chain against whatever contract type it actually is.
- `seeder` (0xc28ba531213e9f0074f70e778aa35eb0f2ac2028) — present in DeployLaunchpad run-latest.json
  but as a `CREATE` transaction with `contractName: null`; apply-deployment.mjs has the same
  previous-round carry-forward fallback for this key. My PerpVault-style delta comparison against
  "VenueSeeder" (+9895 bytes) is **not trustworthy** since the contractName was never confirmed.

Both `DeployLaunchpad` (timestamp 1789305265390) and `DeployPerp` (timestamp 1789305576800) run-latest
files are from the same deploy session (~5 min apart), and their first receipt block numbers
(11696106 and 11696128) sit just after manifest `blocks.deploy`/`blocks.perp` = 11696096 — consistent,
not stale. `perpEngine`'s manifest value is mixed-case (`0xaD0b8d2A2556E59f40389171149D65Aaf14a43C6`)
but matches the lowercase broadcast address case-insensitively — no mismatch, just a checksum-casing
inconsistency worth normalizing.

**Freshness verdict: 15/17 keys are cleanly traceable to the live broadcast; 2 keys (`collection`,
`seeder`) are intentionally-carried-forward and unverifiable from broadcast by design — this design
itself is a latent risk if a future round's "no CREATE for this key" assumption stops holding.**

## D. ABI parity (STEP 4)

All indexer ABI files (`indexer/abis/*.ts`) are hand-written JS object literals (unquoted keys,
comments), not strict JSON — `JSON.parse` on the bracket-stripped content fails for every file
(`RegistryAbi.ts`, `GachaGovAbi.ts`, `DividendAbi.ts`, `PerpEngineAbi.ts`, `CollectionAbi.ts`,
`SeederAbi.ts`, `TreasuryGovAbi.ts`, `FloorAbi.ts`). Per the brief's fallback instruction, `/tmp/r45-parity/abidiff.mjs`
fell back to name-grepping; all event names it extracted exist as plausibly-named events (spot check:
`GenerationSynced`, `SliceRotated`, `SpellCast`, `TicketWon`, `CollectionDeployed`, etc.) but **this
fallback cannot check tuple-component counts or `indexed` flags** — exactly the class of bug the
brief calls out (the `votes` 1.149e48 incident). **This is a genuine parity gap**: no automated
check currently verifies event-field-count parity between these hand-written indexer ABIs and the
compiler ABI. Recommend a follow-up phase with a real TS/AST parser (e.g. `ts-morph`) before r45 ships,
specifically for `GachaGovAbi.ts` (Voted/Proposed) and `TreasuryGovAbi.ts` (SliceRotated/LegOpened),
since those carry the most tuple-like multi-field events.

## E. Wiring (STEP 5)

- `syncedToken()` — no such function exists anywhere in the reviewed contracts (grep found nothing);
  the brief's assumed getter name does not exist. Used `currentToken()` instead.
- `registry.currentToken()` = `0xFDC755Bf7B978345641b90833F82aBDF7CC11419`
- `registry.currentGeneration()` = `1`
- `registry.generationQuote(1)` = `0x0000...0000` (native ETH quote for gen 1 — expected value, not an error)
- `registry.generationPoolId(1)` = `0x84e8d98d71683d4098c50afe87c9ec97977a263b41fd0bb944bd3c5ac2ad6d9d` — **matches manifest `poolIds[0]` exactly**
- `blocksVolumeLink()` lives on `PerpEngine`, not `CauldronRegistry`/`CauldronHook` as the brief assumed; `PerpEngine.blocksVolumeLink()` = `false` (expected)
- `PerpEngine.markSource` is declared `internal` (PerpEngine.sol:614) — **no public getter exists**, so "non-zero" cannot be confirmed from outside; `PerpEngine.currentToken()` reverted on this address (needs investigation — inconsistent with registry.currentToken() succeeding)

## F. CHURN1 baseline failure (STEP 6)

`test_CHURN1_playWorksButChurnReverts` hardcodes the **live r44-deployed** gachaRouter address
(`0x465819232bD80d89423F5b8eE5B958C61bC82FDa`) and a real Sepolia EOA — it is not a fresh deploy. Ran
against the fork: `play` succeeds (`play opened crystals: 24`), then the raw `playChurn` call
reverts with `EvmError: Revert` (empty-data). This is **classification (a)**: the deliberate
live-incident PoC, expected to fail until round 45 deploys a router whose on-chain bytecode actually
contains `playChurn` — confirmed still true today since the manifest's gachaRouter is unchanged r44
code (Section A).

## G. Deploy-pipeline hygiene (STEP 7)

- Compiles under `FOUNDRY_PROFILE=cauldron` in every deploy path (`deploy-testnet.sh`, `go-testnet.sh`,
  `auto-deploy.sh`, `deploy-arc.sh`) — same profile the tests run under; no profile mismatch found.
- `auto-deploy.sh` runs `forge build --sizes` and gates on a clean tree (dies with "the tree has
  regressions" unless `--skip-suite`) before broadcasting — **a clean build is forced**, but `forge
  build` (not `forge clean && forge build`) is used, so a stale `out/` artifact from a prior partial
  build is possible if `--force` is never passed; none of the four deploy scripts pass `--force` or
  call `forge clean`.
- **No deploy script invokes `verify-selectors.mjs` after broadcast** — this is the direct mechanism
  by which the round-43/44 `playChurn` gap shipped silently and remains unfixed today; there is no
  automated post-deploy gate that would have caught it.
- `foundry.toml` `[profile.cauldron].skip` (lines 57-90 as reviewed) does cover
  `lib/**/test/**`, `lib/**/mocks/**`, etc. but **does not explicitly list
  `lib/v4-periphery/lib/permit2/script`** — matches the brief's warning: a clean build of the tree
  currently fails on that path (confirmed: `forge inspect` runs in this session emitted
  `error="...draft-EIP712.sol": No such file or directory` from a nested v4-periphery/permit2 path),
  and only a stale `out/` cache is masking this in day-to-day `forge inspect`/`forge test` runs.
- `apply-deployment.mjs` has an **exact-name match with a silent fallback to the previous round's
  manifest value** for at least two keys (`seeder`, `collection`) when no broadcast CREATE can be
  matched — by design, but silent, and confirmed above to currently apply to real round-44 addresses.

## H. Will round 45 ship the source just reviewed?

| Mechanism | Currently guarded? |
|---|---|
| Stale `out/` cache (no forced `forge clean`) | **NOT guarded** — `auto-deploy.sh` runs `forge build --sizes` but never `forge clean` or `--force` |
| Wrong compile profile | Guarded — all scripts pin `FOUNDRY_PROFILE=cauldron` |
| Silent address fallback to a previous round (`apply-deployment.mjs`) | **NOT guarded** — documented but silent; two keys (`seeder`, `collection`) always take this path by design, and it is indistinguishable in the manifest from an accidental miss |
| No post-deploy selector check | **NOT guarded** — `verify-selectors.mjs` exists but nothing in the deploy pipeline calls it after broadcast; this is exactly how `playChurn` shipped broken in r43 and r44 and is still broken today |
| Missing permit2/script skip entry masked by stale cache | **NOT guarded** — will surface as a hard build failure the first time someone runs a genuinely clean build |


---

## P2.5 verifier verdicts

Independent re-execution. Full evidence in `ARTIFACT_PARITY_VERIFY.md`.

### 17-row verdict column

MATCH = on-chain code is its own source as of deploy. EXPECTED-DRIFT = source changed after r44,
must be redeployed by r45. STALE-AT-DEPLOY = on-chain code did not match its own source at deploy
time (the bug class).

| key | attributed contract | verdict |
|---|---|---|
| registry | CauldronRegistry | MATCH |
| hook | CauldronHook | EXPECTED-DRIFT |
| governor | CauldronGovernor | MATCH |
| dividend | MiFrensDividend | MATCH |
| presale | MiFrensGenesis | MATCH |
| gachaRouter | CauldronGachaRouter | **STALE-AT-DEPLOY** — `df70b5a4 playChurn` absent on chain, present in source |
| timelock | OZ TimelockController (`getMinDelay()`=180) | attributed; bytecode NOT VERIFIED (dirty OZ submodule) |
| collectionLedger | CollectionLedger | MATCH |
| perpEngine | PerpEngine | EXPECTED-DRIFT — **downgraded from the draft's MATCH**: slot 85 of the deployed engine reads `1e18`, a uint, where current source puts `address markSource`, so the deployed layout is not this source |
| perpVault | PerpVault | EXPECTED-DRIFT — 4 getters absent on chain; declared at `src/config/perp.ts:165-168` but called by nothing |
| factory | CauldronFactory | EXPECTED-DRIFT |
| collection | **CauldronCollection** ("Gnomeland"), confirmed by `registry.generationCollection(1)` | MATCH |
| treasuryGovernor | TreasuryGovernor | MATCH |
| quoteOracle | QuoteOracle | MATCH |
| seeder | **CauldronSeeder**, not VenueSeeder — confirmed by `registry.seeder()` and `seeder.registry()` | MATCH (≈ −197 B, metadata band; the draft's +9895 B was a comparison against the wrong contract) |
| nativeZap | NativeQuoteZap | MATCH |
| **quoteRotator** (0x410e…a6653) | — | **NOT VERIFIED — this manifest key is missing from the draft's table entirely** |
| poolManager / positionManager | Uniswap v4 | EXTERNAL |

### ABI-parity summary

Section D's premise is refuted: the ABI files are ordinary TypeScript modules and Node 24 loads them
directly, so the check the draft deferred has now been run. **25 ABI exports (all 15 in
`indexer/abis/` and all 10 contract ABIs in `src/config/`), 199 function/event entries, compared
recursively against `forge inspect … abi` including tuple-component counts, output counts and event
`indexed` flags: ZERO substantive mismatches.** The `votes`-decoded-as-1.149e48 class of bug is not
present. Two app-ABI entries have no compiler counterpart and both are benign: the 9-argument
`propose` overload in `GOVERNOR_ABI` (a documented old-governor fallback selected by argument count,
`src/hooks/useCauldronMachine.ts:391-403`) and `pending(uint256)` in the entirely dead `LEDGER_ABI`
(`src/config/cauldron.ts:242`, zero other references). Three apparent "missing event" hits were
mis-mapping on my side and resolve cleanly against `CauldronSeeder.sol:212/215/218`,
`RedemptionExt.sol:628/630/655` and `CauldronCollection.sol:120`. Not covered: inline ABI literals
in `src/hooks/**` and `src/components/**` — NOT VERIFIED.

### Pipeline (state of the pre-fix tree)

(i) no `forge clean`/`--force` — CONFIRMED, only `auto-deploy.sh:77 forge build --sizes`;
(ii) no post-deploy selector check — CONFIRMED, `verify-selectors` appears in no deploy script;
(iii) seeder/collection fallback — DOWNGRADED: `apply-deployment.mjs` resolves both from the chain
(`:296` registry `seeder()` selector `0x684931ed`, `:309` collection) and only falls back to the
previous round inside the `catch`/zero branches (`:299/:301/:326/:328/:330`) — a silent *failure*
mode, not a silent default; (iv) permit2 skip entry — CONFIRMED absent early in this run (two live
`draft-EIP712.sol` / `src/Permit2.sol not found` build errors observed) and **FIXED-DURING-RUN**:
`"lib/v4-periphery/lib/permit2/script/**"` is now in the cauldron `skip` list.
CHURN1_LiveRevert: classification **(a) expected live-incident PoC** — `play` succeeded
(`play opened crystals: 24`, so the control `assertGt` at `:33` did execute), the raw
`playChurn` call at `:36` against `ROUTER = 0x465819232bD80d89423F5b8eE5B958C61bC82FDa` (= manifest
`gachaRouter`) reverted with empty data; note `:27 if (… FORK_RPC …) return;` makes this test pass
vacuously whenever the fork env is unset.

**Will the round-45 deploy ship the source we just reviewed, as the pipeline stands today? No — with
no forced clean build before broadcast and no post-deploy selector check, the exact mechanism that
put a `playChurn`-less router on chain for two rounds is still unguarded, so r45 can silently ship a
stale artifact again.**
