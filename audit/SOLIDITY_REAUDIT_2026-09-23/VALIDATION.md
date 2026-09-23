# Final validation requirements

> FINAL (2026-09-23): see "Final validation" and "Local chain lane" sections at the end. The matrix immediately below is the earlier Codex checkpoint, kept for provenance.

This matrix reconciles SCOPE.md and the active objective. A passing selected
suite proves its assertions only. Historical runs remain in logs; a terminal
exit0 with no selected tests is not a runtime pass. PROGRESS.md is authoritative
for source traversal; no file is currently signed off.

| Requirement | Current evidence | Missing for final acceptance |
|---|---|---|
| Frozen complete scope | BASELINE.json, snapshot/, COMPILER_GRAPH.json | Recheck frozen hash integrity at final reporting; retain dependency dirty-state provenance. |
| Every file/body traversed | 66 unique worksheet mappings, remediation/TRAVERSAL_INVENTORY_CHECK.json | Current declaration-level authority/assets/callback/invariant/consumer annotations; new candidate declarations included. |
| Every cross-contract lifecycle | Individual worksheets and local integration logs | Close each explicit GAP; launch/rotation/relaunch/successor, adverse callbacks, multi-asset reserves and accounting cannot be inferred from isolated tests. |
| Confirmed Critical/High/Medium remediated | FINDINGS.md, LEDGER.md, ten Medium candidate patches and High badge admission patch | Full final suites, current-source second-pass reviews, unresolved leads disposition and artifact freshness. No Critical confirmed here; absence is not proof of safety. |
| Regression execution | Numerous bounded logs with exact command, exit, skips | Full current candidate profile run, classify all failing/skipped/no-op tests, excluded-profile coverage. Historical characterization failures must remain visible. |
| Invariants and sequences | Targeted conservation/cascade/reward logs and worksheets | Complete assertion-to-invariant mapping and unresolved sequences across generation/asset transitions. Test counts do not close this gate. |
| Local integration | Real V4/PositionManager/Permit2 lanes, explicit mocks/inventory limitations | Remaining required scenarios and compatibility; no fork/deployed-state parity claim. |
| ABI/selectors/storage | Ten remediation surface verifiers; registry/facet recursive storage check | Fresh compiler graph for latest scripts/helpers, VenueSeeder surface, all affected consumers and explicit accepted ABI/storage changes. |
| Deployment limits | Source-matched prior remediation sizes; registry and linked libraries have tight margin | Recheck every deployable candidate runtime/initcode with correct compiler/link settings. Script/test harness size is not production size. |
| Deployment path | Serial preflight12 pass, helper recovery, actual hook constructor2 pass | Complete local script/factory/wiring/summon path, required profiles, dependency provenance and supported optional configs. No broadcast authorized. |
| Consumers | Individual review notes including vault zero-rounded debt UI gap | Current ABI/static-view/address wiring compatibility and documented recovery UI/runbook limitations. |
| Report artifacts | FINDINGS.md, COVERAGE.md, PROGRESS.md, this VALIDATION.md | FINAL_REPORT.md with precise source identities, unresolved issues, old-finding reconciliation, and defensible per-file sign-off evidence. |

Known profile limitation: render profile previously failed compiling transient
hook syntax; explicit renderer imports under cauldron execute some tests but do
not establish that the required render build succeeds. Offline Foundry avoids
observed macOS proxy-client panic; it does not turn unavailable forks into tests.
Use --threads1 for environment-mutating tests. Preserve no-push/no-broadcast rule.

## Candidate artifact checkpoint

`check_candidate_artifacts.py` / remediation/CANDIDATE_ARTIFACT_INVENTORY.json
and CANDIDATE_ARTIFACT_REVIEW.md now record whole-input freshness and lengths.
179 artifacts,171 whole-input matches,8 stale outputs;62/66 scoped files have a
matching artifact. Missing four renderer-related standalone outputs remain a
gate. Deployable registry runtime margin is8 bytes. Constructor-argument sizes,
link addresses, full deployment and current semantic verification are not proved
by these measurements. Full local profile session44592 still running at this
checkpoint; collect terminal log before recording aggregate results.

Renderer artifact gap closed by renderer-standalone-artifacts: explicit four
paths, FOUNDRY_SKIP=[], separate output/cache, solc0.8.30 at cauldron settings.
Current whole-input artifact coverage66/66, prior inventory preserved. Broad
render profile failure remains unresolved; explicit build is not its success.

## Full local suite terminal result

candidate-cauldron-full-local finished exit1 in290.54s. Forge reports356 suites:
1079 passing executions,45 failures,276 skips (1400 total). This is not1079
independent properties; inherited repetitions and silent early-return fixtures
need accounting. Exact failure inventory: remediation/FULL_LOCAL_FAILURE_TRIAGE.json.

-39 failures explicitly require an unavailable fork. No fork assertions passed.
-2 OgFloorRatchet failures: MockOgCollection lacked totalMinted required by the
 new badge admission check. Added ogSupply+1 art ceiling, retaining original
 `og tranche` rejection assertions. og-floor-admission-fixture rerun:13pass,
 zero fail/skip. Historical full-run failures remain recorded, not overwritten.
-3 expected unresolved Low properties: art buffer overflow, treasury tie order,
 stale guardian cancellation target. FINDINGS.md records them.
-1 conditional GachaLib mint-failure/pity lead; production reachability remains
 under investigation. No production severity asserted from synthetic counters.

No full-suite process remains live. No claim that unavailable forks, remaining
failed assertions, excluded profiles, or no-op tests satisfy final validation.

---

# Final validation (continuation 2026-09-23, Claude Opus 5.5)

All commands via `run.py --worktree` (profile cauldron) unless stated; logs in
logs/<label>.{json,log}. Nothing below is counted from a skipped or early-returning test.

## Fix verification batches

| Label | Command selection | Exit | Result |
|---|---|---|---|
| genesis-paid-mint-failure (Codex, pre-fix) | R23GenesisMintFailure | 1 | pity 1 -> 0 on rejected mint (FS-gacha-01 reproduced) |
| gacha-pity-fix | 17 gacha/queue/churn/badge suites | 0 | 32 pass, 0 fail, 17 skip (fork-only F02/Y03/Z05, not counted) |
| registry-perp-leads (pre-fix) | R23RelaunchGasSkip, R23SuccessorLegHandoff, R23CascadeMixedLeverage | 1 | relaunch: 5 stranded completions at 6.0-8.0M; successor: leg stranded; cascade: 256 fuzz pass |
| relaunch-successor-fix | 16 suites incl. relaunch/rotation/registry neighbours | 0 | 46 pass, 0 fail, 0 skip; 0 stranded completions (36 ok caps, min 8.5M); leg handed to successor; ladder 24 fills / 21 with kills |

## Final full local suite

`final-cauldron-full-local`: `env FORK_RPC= forge test --offline --threads 1 -vv`,
exit 1, 360 suites in 327.87s: **1100 passed, 42 failed, 276 skipped** (1418).
Triage: remediation/FINAL_FULL_LOCAL_TRIAGE.json.

- 39 failures: fork harness explicitly refuses to run without FORK_RPC (unavailable-fork).
- 1 failure: R23RenderBuffer dense upload — documented Low FS-artbuffer-01, unfixed by policy.
- 2 failures: R23TreasuryTargeting tie order and stale cancel — documented Lows FS-treasury-L01/L02, unfixed by policy.
- 0 new failures versus the candidate run; 3 resolved (R23GachaFailedMint, two OgFloorRatchet fixture tests).
- 276 skips: fork-gated tests (`vm.skip(!active)` / early-gated fixtures) — not passes. See "Local chain lane".

## Artifacts, sizes, surfaces, mechanical gates

- check_candidate_artifacts.py: 66/66 first-party files have whole-input source-matched
  artifacts (prior inventory kept as CANDIDATE_ARTIFACT_INVENTORY_PRE_CONTINUATION.json).
  All deployable runtimes <= 24,576; tightest: CauldronRegistry 24,553 (23 headroom,
  previously 8), PoolOps 24,465, CauldronHook 24,401, PerpEngine 24,207. Only forge
  script contracts exceed EIP-170 (never deployed).
- surface_recheck.py (58 contracts in changed files vs frozen compiler graph): only
  intended deltas — CollectionLedger +event EntitlementReleased; MiFrensDividend
  +pushTokenIsolated; PerpVault +1 appended private slot (_settledTokYield, slot 24);
  RedemptionExt +event LegHandedOff. Storage layouts compared (14): identical for
  CauldronHook, CauldronRegistry, CauldronVault, CollectionLedger, MiFrensDividend,
  MigrationVesting, PerpEngine, QuoteOracle, RedemptionExt, VenueSeeder and three
  script contracts; PerpVault differs only by the appended slot. Libraries
  (GachaLib, PoolOps, SurtaxLib) hold no storage.
- final_gates.py (remediation/FINAL_GATES.json): snapshot 4,304/4,304 intact;
  16 first-party files changed (all claimed in LEDGER.md), 0 removed, 46 test files
  added; frontend selector list 43/43 present in fresh artifacts; `git diff --check`
  exit 0; secret scan: 28 hits, all vendored forge-std StdChains public default RPC
  URLs echoed in logs/baseline-build.log, 0 keyed URLs or keys in first-party
  contracts/tests/scripts/frontend/indexer/api.
- contracts/abis/Cauldron*.abi.json are human-readable string ABIs (not compared
  structurally); the frontend/indexer inline ABIs were checked through the selector list.

## Remaining gates (not satisfiable here)

Target-chain pinned fork lane and deployed-bytecode/manifest parity (no approved
RPC); independent reviewer; off-chain resilience drills. See FINAL_REPORT.md.

## Local chain lane (FORK_RPC = local anvil) and production-script rehearsal

Details: rehearsal/README.md and rehearsal/*.log.

`final-full-localchain`: whole suite with FORK_RPC=http://127.0.0.1:8546 and the
rehearsal's V4 addresses, exit 1: **361 suites, 1448 passed, 12 failed, 1 skipped**
(1461). Triage remediation/FINAL_LOCALCHAIN_TRIAGE.json:
- 8 require real Sepolia state (QuoteOracleFork x2 real Chainlink feeds,
  RotatorSwapFork x5 real pools, CHURN1_LiveRevert live r44 router).
- 3 documented Lows (FS-artbuffer-01, FS-treasury-L01/L02).
- 1 superseded premise: CauldronSummon legacy-buyback asserted crystallize never
  reduces entitlement; trace (logs/localchain-legacy-buyback-trace.*) shows
  totalMinted 0, outstanding 0, EntitlementReleased(1, 3.39e24) — the intended
  FS-ledger-01 release. Assertion tightened to: exactly zero when no art exists,
  never reduced otherwise. `localchain-summon-ledger-premise`: 16/16 pass.
- 1 skip: BadgeDump utility (vm.skip by design).
The 276 local skips and 39 fork refusals of the FORK_RPC-empty run are therefore
now executed; only the 8 Sepolia-state tests remain unexecutable here. This is a
local chain, not target-chain parity.

`final2-full-localchain` (after the ten Low fixes, commit 6961bb4; same chain and
addresses), exit 1: **367 suites, 1459 passed, 8 failed, 1 skipped** (1468). The 8
failures are exactly the Sepolia-state set above (QuoteOracleFork x2,
RotatorSwapFork x5, CHURN1_LiveRevert x1); the three Low-fix failures and the
superseded premise are gone, and the six new R23 suites pass.

Production scripts DeployV4Core, DeployLaunchpad and DeployPerp executed
successfully on the local chain; the lifecycle (presale, ignition, trade, gacha,
perps open/close, governance, death, relaunch with open book, Genesis
continuation) completed. FS-relaunch-01 fix confirmed on deployed bytecode: low
gas reverts Panic(0x11); dapp-style estimated gas relaunches and drains the book.

## Final tree gates and Sepolia r47 (after the Low fixes)

Regenerated on the final tree (`6961bb4`, out/ force-built by the r47 deploy):
CANDIDATE_ARTIFACT_INVENTORY 66/66 files with source-matched artifacts;
FINAL_GATES snapshot 4,304/4,304 intact, frontend selectors 43/43, `git diff
--check` exit 0, secret scan 28 hits (all public forge-std RPC constants echoed
in build logs, 0 first-party); FINAL_SURFACE_RECHECK only intended deltas (see
FINAL_REPORT §7). Renderer artifacts rebuilt by the explicit-path recipe into
remediation/renderer-artifacts.

r47 (R47_DEPLOYMENT.md): 93 script transactions, 0 failed; 32/32 deployed
runtimes byte-identical to the artifacts (verify_deployed_bytecode.py);
manifest round 47 OK; `npm run build` exit 0 against it.
