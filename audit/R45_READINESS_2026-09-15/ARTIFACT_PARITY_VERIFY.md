# P2.5 ARTIFACT-PARITY VERIFICATION (independent re-execution of ARTIFACT_PARITY.md)

Method: every claim below was re-run. Tags: VERIFIED (I ran it) / DERIVED (read + reasoned) /
NOT VERIFIED. RPC is referred to as "the Alchemy endpoint"; the URL appears in no file.

---

## T1 — ABI parity, done properly

### T1.0 The runner's premise is REFUTED

ARTIFACT_PARITY.md §D claims:

> "All indexer ABI files (`indexer/abis/*.ts`) are hand-written JS object literals (unquoted keys,
> comments), not strict JSON — `JSON.parse` on the bracket-stripped content fails for every file"

**REFUTED (VERIFIED).** They are ordinary TypeScript modules exporting `as const` arrays. Node
24.14.0 strips types natively; `import()`ing each file and `JSON.stringify`-ing every exported array
loaded **all 15 indexer ABI exports and all 17 `src/config` ABI exports** as real JSON. No JSON5, no
regex, no `ts-morph` needed. The runner's "genuine parity gap … recommend a follow-up phase" is
therefore not a gap in the tree, it is a gap in the runner's tooling. The check has now been done.

Harness (kept out of the repo): `/tmp/r45v/dump.mjs`, `/tmp/r45v/dump2.mjs`, `/tmp/r45v/cmp.mjs`,
resolver hook `/tmp/r45v/resolver.mjs` (maps `@/…`, adds `type: "json"` attributes, rewrites
`import.meta.env`). Compiler side: `forge inspect <C> abi --json` under `FOUNDRY_PROFILE=cauldron`.

Comparison performed per entry: match by `type` + `name` + input count (all overloads kept), then a
**recursive** compare of every input and output — solidity type string with tuple components expanded
(`(uint256,address)[]`-style), **tuple component count**, component names, and the **`indexed` flag**
on every event parameter. This is exactly the check that would have caught the production
"tuple short by two fields → votes decoded as 1.149e48" incident.

### T1.1 Result table (VERIFIED)

"substantive" = a type, tuple-component-count, output-count or `indexed`-flag difference.
Parameter-*name*-only differences do not affect ABI encoding and are listed separately.

| ABI export | compared against | entries | matched | substantive mismatches | no counterpart |
|---|---|---|---|---|---|
| indexer/abis/CollectionAbi.ts::CollectionAbi | CauldronCollection + MiFrensGenesis | 5 | 5 | **0** | 0 (see note) |
| indexer/abis/DividendAbi.ts::DividendAbi | MiFrensDividend | 8 | 8 | **0** | 0 |
| indexer/abis/FloorAbi.ts::HookFloorAbi | CauldronHook | 1 | 1 | **0** | 0 |
| indexer/abis/FloorAbi.ts::RegistryFloorAbi | CauldronRegistry | 5 | 5 | **0** | 0 |
| indexer/abis/GachaGovAbi.ts::GovernorAbi | CauldronGovernor | 3 | 3 | **0** | 0 |
| indexer/abis/GachaGovAbi.ts::HookGachaAbi | CauldronHook | 3 | 3 | **0** | 0 |
| indexer/abis/GachaGovAbi.ts::RegistryCollAbi | CauldronRegistry | 1 | 1 | **0** | 0 |
| indexer/abis/PerpEngineAbi.ts::PerpEngineAbi | PerpEngine | 8 | 8 | **0** | 0 |
| indexer/abis/PerpEngineAbi.ts::RegistryGenReadAbi | CauldronRegistry | 3 | 3 | **0** | 0 |
| indexer/abis/RegistryAbi.ts::RegistryAbi | CauldronRegistry | 5 | 5 | **0** | 0 |
| indexer/abis/SeederAbi.ts::SeederAbi | **CauldronSeeder** | 6 | 6 | **0** | 0 |
| indexer/abis/TreasuryGovAbi.ts::RotationExecAbi | **RedemptionExt** | 3 | 3 | **0** | 0 |
| indexer/abis/TreasuryGovAbi.ts::TreasuryGovAbi | TreasuryGovernor | 5 | 5 | **0** | 0 |
| src/config/presale.ts::PRESALE_ABI | MiFrensGenesis | 14 | 14 | **0** | 0 |
| src/config/perp.ts::PERP_ABI | PerpEngine | 18 | 18 | **0** | 0 |
| src/config/perp.ts::PERP_VAULT_ABI | PerpVault | 17 | 17 | **0** | 0 |
| src/config/cauldron.ts::COLLECTION_ABI | CauldronCollection | 16 | 16 | **0** | 0 |
| src/config/cauldron.ts::DIVIDEND_ABI | MiFrensDividend | 21 | 21 | **0** | 0 |
| src/config/cauldron.ts::GACHA_ROUTER_ABI | CauldronGachaRouter | 4 | 4 | **0** | 0 |
| src/config/cauldron.ts::GOVERNOR_ABI | CauldronGovernor | 8 | 7 | **0** | 1 (legacy overload) |
| src/config/cauldron.ts::HOOK_ABI | CauldronHook | 17 | 17 | **0** | 0 |
| src/config/cauldron.ts::HOOK_LEGACY_ABI | CauldronHook | 1 | 1 | **0** | 0 |
| src/config/cauldron.ts::LEDGER_ABI | CollectionLedger | 4 | 3 | **0** | 1 (dead ABI) |
| src/config/cauldron.ts::REGISTRY_ABI | CauldronRegistry | 24 | 24 | **0** | 0 |
| src/config/cauldron.ts::VAULT_ABI | CauldronVault | 3 | 3 | **0** | 0 |

**Totals: 25 ABI exports, 199 function/event entries compared, 0 substantive mismatches, 2
no-counterpart entries (both benign, below).** `PoolManagerAbi` and `Erc721TransferAbi` are
third-party (Uniswap v4 / ERC-721) and were excluded by design, as were the pure ERC-20/721 helper
ABIs (`ERC20_SWAP_ABI`, `TOKEN_ABI`, `MIFRENS_ERC721_ABI`, `POOLMANAGER_ABI`,
`POSITION_MANAGER_ABI`).

### T1.2 The three "missing" entries the first pass reported were **my own mis-mapping**, not bugs

1. `SeederAbi` — all 6 events showed as missing against `VenueSeeder` (the contract name the runner
   assumed). They are all declared in **CauldronSeeder**:
   `contracts/solidity/cauldron/CauldronSeeder.sol:212`
   `event SeedStarted(uint256 indexed gen, uint256 ethTotal, uint256 tokenTotal, uint64 window);`
   `…:215  event BasePlaced(uint256 indexed gen, uint128 fullRangeLiquidity);`
   `…:218  event PrimeBought(uint256 indexed gen, uint256 ethIn, uint256 tokenOut, uint256 spent, uint256 budget);`
   Re-compared against `CauldronSeeder`: **6/6 clean, indexed flags included.** VERIFIED.
2. `RotationExecAbi` — 3 events showed as missing against `CauldronRegistry`. They are declared in
   the registry's rotation extension, `contracts/solidity/cauldron/RedemptionExt.sol:628/630/655`
   (`LegOpened`, `GenerationRequoted`, `SliceRotated`), which emits **at the registry address**, so
   `ponder.config.ts:185` pointing `RotationExec` at `REGISTRY` is correct. Re-compared against
   `RedemptionExt`: **3/3 clean.** VERIFIED.
3. `CollectionAbi` — it is a *union* ABI used for two different contracts
   (`ponder.config.ts:207 Presale → CollectionAbi`, and `:221/:227` for factory collections).
   `Minted` resolves on `contracts/solidity/cauldron/CauldronCollection.sol:120`
   (`event Minted(address indexed to, uint256 indexed tokenId, uint8 rarity);`) and `VolumeMinted`
   resolves on `MiFrensGenesis`. Both sides clean; the union is intentional. VERIFIED.

### T1.3 The two genuine no-counterpart entries — both benign (VERIFIED)

- `src/config/cauldron.ts::GOVERNOR_ABI` carries a **9-argument** `propose(string,string,uint8,
  string,address,string,string,uint256,uint256)` that `CauldronGovernor` does not have. This is
  deliberate: `src/hooks/useCauldronMachine.ts:391-403` selects the overload by feature detection
  and documents it —
  > "viem picks the overload by argument count, so appending logo/banner to a call aimed at an older
  > governor would select a signature that does not exist there and revert with no reason string."
  The 10-arg and 12-arg overloads both exist in the compiler ABI and match exactly. **Informational**,
  not a finding: the 9-arg path is the deliberate old-governor fallback.
- `src/config/cauldron.ts::LEDGER_ABI` carries `pending(uint256)`, which lives on
  `contracts/solidity/cauldron/MiFrensDividend.sol:255`, not on `CollectionLedger`. `LEDGER_ABI` is
  **dead code**: `grep -rn "LEDGER_ABI" src/` returns exactly one hit, its own definition at
  `src/config/cauldron.ts:242`. **Medium at worst (unused).**
- False alarm checked and cleared: `src/hooks/useTreasuryRotation.ts:432` calls `propose` with two
  args, but that file defines its **own local** `GOVERNOR_ABI` at `useTreasuryRotation.ts:53`
  (the treasury governor), not the imported one. Not a mismatch.

### T1.4 Coverage limit — NOT VERIFIED

Only `indexer/abis/*.ts` and the three `src/config/*.ts` ABI modules were parsed. Inline ABI
literals also exist in at least `src/hooks/useTreasuryRotation.ts`, `useCauldronSwap.ts`,
`useCauldronMachine.ts`, `useMiFrensDividend.ts`, `useAllowedQuotes.ts`, `src/lib/cauldronOnchain.ts`,
`src/components/wizards/ForgedCreatures.tsx`, `FrenDetailModal.tsx`. **Those are NOT VERIFIED.**

---

## T3 — Router and vault re-verified

**Router — STALE-AT-DEPLOY, CONFIRMED (VERIFIED).**
- On chain: `cast code 0x465819232bD80d89423F5b8eE5B958C61bC82FDa … | grep -c df70b5a4` → **0**.
- In source: `forge inspect CauldronGachaRouter methodIdentifiers` →
  `| playChurn(uint256,uint256,uint256,uint256) | df70b5a4 |`
- Runtime size: chain 17162 hex chars vs source `deployedBytecode` 17639 → the deployed router is
  ~238 bytes smaller and is missing a whole public entry point. This is the one contract whose
  on-chain code did not match its source **at deploy time**.

**Vault — EXPECTED-DRIFT, DOWNGRADED from the runner's framing (VERIFIED).**
Four selectors absent on chain: `epochAcc()`, `stakerEpoch(address)`, `totalTokYieldPulled()`,
`yieldEpoch()`. All four **are declared** in the app ABI at `src/config/perp.ts:165-168`, but
`grep -rn "functionName: *[\"'](totalTokYieldPulled|epochAcc|yieldEpoch|stakerEpoch)[\"']" src/ indexer/`
returns **zero call sites**, and so does a plain name grep over `src/hooks/`, `src/components/` and
`indexer/src/`. Declared-but-never-called ⇒ **no user-facing break today**, but it is a live
trip-wire: the first component that starts calling one of these against the r44 vault gets an
empty-data revert. Medium.

---

## T6 — Deploy-pipeline verdicts (state as of the pre-fix tree, with fixes noted)

**(i) No clean build / `--force` before broadcast — CONFIRMED (VERIFIED).**
The only build in any deploy path is
`scripts/auto-deploy.sh:77:  forge build --sizes > /tmp/ad-sizes.log 2>&1 || {`
No `forge clean`, no `--force`, in any of `deploy-testnet.sh`, `go-testnet.sh`, `auto-deploy.sh`,
`deploy-round.mjs`. The broadcast itself is
`scripts/deploy-testnet.sh:205:  forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad \`
and `scripts/go-testnet.sh:184:  forge script deploy/DeployPerp.s.sol --tc DeployPerp \`.
A stale `out/` artifact is therefore broadcastable. **Still open at the time of writing.**

**(ii) No post-deploy selector check — CONFIRMED (VERIFIED).**
`grep -n "verify-selectors" scripts/deploy-testnet.sh scripts/go-testnet.sh scripts/auto-deploy.sh
scripts/deploy-round.mjs` returns **nothing**. The script exists but nothing in the pipeline calls
it after broadcast. This is the precise mechanism by which the `playChurn` gap shipped and survived
two rounds. **Still open at the time of writing.**

**(iii) Silent previous-round fallback for seeder/collection — PARTLY REFUTED / DOWNGRADED (VERIFIED).**
The runner says apply-deployment.mjs "deliberately carries this value forward from the previous
round's manifest." That is the *old* behaviour, described in the file as a past bug:
`scripts/apply-deployment.mjs:127-129`
> "So `collection` was carried forward across every round — round 40 shipped with round 39's
> collection while the live gen-1 collection was 0xD9c04263 (GNOME), and the frontend reads this
> field, so the UI was pointed at a dead collection."

The current code does **not** default to carry-forward. Both keys are sentinels —
`:131  collection: "__ASK_CHAIN_COLLECTION__",` and `:146  seeder: "__ASK_CHAIN_SEEDER__",` — and are
resolved **from the chain**: `:296  params: [{ to: m.contracts.registry, data: "0x684931ed" }, "latest"] })  // seeder()`
with the previous-round value used only in the `catch` / zero-address branches
(`:299`, `:301`, `:326`, `:328`, `:330`). So the correct verdict is: **not a silent default, but a
silent RPC-failure fallback** — if the registry read throws, the manifest silently keeps the old
address and looks identical to a success. Downgraded from the runner's High-ish framing to
**Medium (silent failure mode, not a silent default path)**.

**(iv) permit2/script missing from the cauldron skip list — CONFIRMED for the pre-fix tree,
FIXED-DURING-RUN (VERIFIED both states).**
Early in this run, `sed -n 55,95p contracts/solidity/foundry.toml` showed a `skip = [` list running
`lib/**/test/**`, `lib/**/src/test/**`, `lib/**/mocks/**`, `lib/**/fv/**`, `lib/**/certora/**`, …
with **no permit2 entry**, and every `forge inspect` in this session emitted
`error="…/lib/v4-periphery/lib/v4-core/lib/openzeppelin-contracts/utils/cryptography/draft-EIP712.sol":
No such file or directory`, plus the CHURN1 run printed
`error: file src/Permit2.sol not found --> lib/v4-periphery/lib/permit2/script/DeployPermit2.s.sol:6:23`.
A re-read later in the run shows the entry now present:
`"lib/v4-periphery/lib/permit2/script/**",` with the comment "permit2's own deploy scripts carry a
relative import that does not resolve". **FIXED-DURING-RUN.**

---

## T5 — CHURN1_LiveRevert

Ran once: `forge test --match-path test/attacks/CHURN1_LiveRevert.t.sol -vv` with `FORK_RPC` set to
the Alchemy endpoint, `FOUNDRY_PROFILE=cauldron`.

```
Ran 1 test for test/attacks/CHURN1_LiveRevert.t.sol:CHURN1_LiveRevert
[FAIL: EvmError: Revert] test_CHURN1_playWorksButChurnReverts() (gas: 501502)
Logs:
  play opened crystals: 24
Suite result: FAILED. 0 passed; 1 failed; 0 skipped
```

Target address, `test/attacks/CHURN1_LiveRevert.t.sol:17`:
`address constant ROUTER = 0x465819232bD80d89423F5b8eE5B958C61bC82FDa;` — identical to
`round.json contracts.gachaRouter`.

What actually failed is **not** an assertion. The control assertion at `:33`
`assertGt(opened, 0, "control: play works on this router");` **executed and passed** — proven by the
`play opened crystals: 24` log emitted at `:32`, immediately before it. The failure is the raw
external call at `:36`:
`IRouter(ROUTER).playChurn{value: 0.01 ether}(0, 1, 0, 0);` reverting with empty data, i.e. the
fallback-less dispatcher rejecting selector `df70b5a4`.

Prime-directive-4 note: `grep -n "return;"` finds two hits, `:22` (in `setUp`) and
**`:27` inside the top-level test** — `if (bytes(vm.envOr("FORK_RPC", string(""))).length == 0) return;`.
**Without `FORK_RPC` this test passes vacuously with zero assertions executed.** It did not do so
here (the fork was set and the log line proves execution reached `:32`), but the guard is a latent
green-for-nothing risk if anyone runs the suite without the fork env.

**Classification: (a) the expected live-incident PoC.** It is not a source regression — the source's
`methodIdentifiers` contains `df70b5a4` — and not infrastructure, since `play` on the same address in
the same fork succeeded. It will stay red until r45 deploys a router whose runtime contains
`playChurn`.

---

## T2 — Attribution of the three unresolved contracts (all VERIFIED)

| key | address | attributed to | evidence | verdict |
|---|---|---|---|---|
| timelock | 0x987bd1be2ede55d54d2ba272f3519e662b66b831 | OpenZeppelin `TimelockController` | `cast call … "getMinDelay()(uint256)"` → **180**; runtime 10752 hex chars = 5375 B, matching the runner's on-chain figure | attributed; **bytecode compare NOT VERIFIED** (the `lib/openzeppelin-contracts` submodule is dirty per `git status`, so `forge inspect` resolves an ambiguous artifact — the runner's 168-byte "source" figure is a wrong artifact, not a bug) |
| collection | 0xf850df1ae54c45433579b09909d1d6cb26d1a2c4 | **CauldronCollection** (live gen-1) | `registry.generationCollection(1)` → `0xF850dF1AE54C45433579b09909d1d6cB26d1a2C4` (exact manifest match); `name()` → `"Gnomeland by Magic Internet Frens"` | chain 11553 B vs `CauldronCollection` deployedBytecode ~11557 B → **MATCH** |
| seeder | 0xc28ba531213e9f0074f70e778aa35eb0f2ac2028 | **CauldronSeeder** (not `VenueSeeder`) | `registry.seeder()` → `0xc28bA531213E9F0074f70e778Aa35eB0F2ac2028` (exact manifest match); `seeder.registry()` → `0x3Dc63412e643Aa4B798bda6b59c816dAf7C10325` (the registry) | chain 15260 B vs `CauldronSeeder` deployedBytecode ~15457 B → **MATCH** (metadata band) |

**The runner's `seeder` row is REFUTED.** Its "+9895 bytes vs VenueSeeder" delta was a comparison
against the wrong contract; the correct contract is `CauldronSeeder` and the delta is ≈ −197 bytes,
inside the same metadata/CBOR band as the seven other MATCH rows.

---

## T4 — Wiring reads (all VERIFIED, re-run once with cast against the Alchemy endpoint)

| read | value | matches runner? |
|---|---|---|
| `registry.currentToken()` | `0xFDC755Bf7B978345641b90833F82aBDF7CC11419` | yes |
| `registry.currentGeneration()` | `1` | yes |
| `registry.generationQuote(1)` | `0x0000000000000000000000000000000000000000` (native ETH) | yes |
| `registry.generationPoolId(1)` | `0x84e8d98d71683d4098c50afe87c9ec97977a263b41fd0bb944bd3c5ac2ad6d9d` — equals `round.json poolIds[0]` | yes |
| `PerpEngine.blocksVolumeLink()` | `false` | yes |

### Mark source — NOT VERIFIED, and the attempt produced its own evidence

`contracts/solidity/cauldron/PerpEngine.sol:614:    address internal markSource;` — internal, no
getter, so the runner's "cannot be confirmed from outside" is correct for the ABI route.
Storage route: the compiler layout (from `out/PerpEngine.sol/PerpEngine.json`, since
`forge inspect … storageLayout --json` is polluted by the permit2/EIP-712 resolver error) puts
`markSource` at **slot 85, offset 0, 20 bytes (`t_address`), unpacked**.

`cast storage 0xaD0b8d2A2556E59f40389171149D65Aaf14a43C6 85` →
`0x0000000000000000000000000000000000000000000000000de0b6b3a7640000`

`0x0de0b6b3a7640000` = **1e18**. That is a uint-shaped value, not an address-shaped one. Conclusion:
**the r44-deployed engine's storage layout is not the current source's layout**, so slot 85 on chain
is some other variable and the r44 mark-source status **cannot be read this way — NOT VERIFIED.**
This is, incidentally, independent confirmation that the deployed `perpEngine` is *not* the source
under review (EXPECTED-DRIFT, must be redeployed), stronger evidence than the runner's "+44 bytes,
within metadata noise → MATCH", which is hereby **DOWNGRADED from MATCH to EXPECTED-DRIFT**.

---

## The 17-row verdict column

MATCH = on-chain code is the contract's source as of deploy. EXPECTED-DRIFT = source legitimately
changed after r44; must be redeployed by r45. STALE-AT-DEPLOY = on-chain code did not match its own
source at deploy time (the bug class). EXTERNAL / NOT VERIFIED as labelled.

| key | address | attributed contract | verdict |
|---|---|---|---|
| registry | 0x3dc6…c10325 | CauldronRegistry | MATCH (−169 metadata band) |
| hook | 0xc6dc…d510cc | CauldronHook | **EXPECTED-DRIFT** (chain 24530 B > source 23309 B) |
| governor | 0xf0b1…036b3 | CauldronGovernor | MATCH |
| dividend | 0x3d67…07cda | MiFrensDividend | MATCH |
| presale | 0xfd48…b92ba | MiFrensGenesis | MATCH |
| gachaRouter | 0x4658…82fda | CauldronGachaRouter | **STALE-AT-DEPLOY** (`df70b5a4 playChurn` absent on chain, present in source) |
| timelock | 0x987b…66b831 | OZ TimelockController (`getMinDelay()`=180) | attributed; bytecode **NOT VERIFIED** (dirty OZ submodule) |
| collectionLedger | 0x7377…0d9e80 | CollectionLedger | MATCH |
| perpEngine | 0xaD0b…a43C6 | PerpEngine | **EXPECTED-DRIFT** (slot-85 layout mismatch proves it) |
| perpVault | 0x343b…27575b | PerpVault | **EXPECTED-DRIFT** (4 getters absent; declared in app ABI, called by nothing) |
| factory | 0x88d3…04abd3 | CauldronFactory | **EXPECTED-DRIFT** (source grew 1287 B) |
| collection | 0xf850…d1a2c4 | **CauldronCollection** (gen-1 "Gnomeland") | MATCH |
| treasuryGovernor | 0x7da2…e97f86 | TreasuryGovernor | MATCH |
| quoteOracle | 0x9b79…4831e | QuoteOracle | MATCH |
| seeder | 0xc28b…ac2028 | **CauldronSeeder** (not VenueSeeder) | MATCH (≈ −197 B metadata band) |
| nativeZap | 0x8059…566f41 | NativeQuoteZap | MATCH |
| **quoteRotator** | 0x410e6e7ecaf3f641c4486f38542f37e213aa6653 | — | **NOT VERIFIED — the runner's table omits this manifest key entirely** |
| poolManager | 0xE03A…203543 | Uniswap v4 | EXTERNAL |
| positionManager | 0x429b…5c09b4 | Uniswap v4 | EXTERNAL |

---

## Discards (claims I could not verify, or verified as wrong)

Verified-wrong (3): the runner's "ABIs cannot be JSON-parsed / parity gap unverifiable"; the
`seeder → VenueSeeder` attribution and its +9895 B delta; `apply-deployment.mjs` "carries the value
forward by design" (it reads the chain; carry-forward is only the RPC-failure branch).
Downgraded (1): `perpEngine` MATCH → EXPECTED-DRIFT.
NOT VERIFIED (4): `quoteRotator` parity (never compared by anyone); `timelock` bytecode parity
(dirty OZ submodule); the r44 engine's mark-source value; the inline ABI literals in `src/hooks/**`
and `src/components/**`.
