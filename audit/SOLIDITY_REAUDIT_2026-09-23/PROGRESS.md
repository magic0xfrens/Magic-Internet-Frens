# Solidity audit progress

Checkpoint: 2026-09-23. This is a review tracker, not a security certification.
The complete frozen file inventory is `BASELINE.json:first_party_solidity`;
the declaration inventory is `COMPILER_GRAPH.json`. Scope is not narrowed to
files with passing tests. New candidate declarations also require review.

## Progress bars

- Frozen first-party inventory: **66/66 files inventoried**.
- Baseline declaration inventory: **1,093 declarations mapped mechanically**.
- Full source-body traversal documented: **66/66 files** (100%, source reading only).
- Full-scope final verification: **66/66 files signed off (local scope, with limitations)** — see SIGNOFF_CHECKLIST.md.
- Confirmed Medium findings: **10 patched with targeted regression evidence**;
  final full-scope validation remains pending.
- High finding: badge redemption consumed art-only backing in a funded local
  reproduction. Patch has 22 targeted/neighboring passing checks, one additional earned-badge
  integration pass subsequently expanded to paid art acquisition, and passing
  ABI/storage/size evidence; full-scope validation remains pending.

There is no defensible overall completion percentage or finish-time estimate yet.
Test totals, static graph resolution, and reading a function are not semantic
verification. Inherited/repeated tests must not inflate progress.

## Documented full source traversals

Each row still requires resolution of its worksheet gaps and applicable
cross-contract/final validation. These are not completed-contract checkmarks.

| File | Review evidence |
|---|---|
| CauldronHook.sol | HOOK_REVIEW.md |
| QuoteOracle.sol | QUOTE_ORACLE_REVIEW.md |
| QuoteRotator.sol | QUOTE_ROTATOR_REVIEW.md |
| NativeQuoteZap.sol | NATIVE_ZAP_REVIEW.md |
| MigrationVesting.sol | VESTING_REVIEW.md |
| PerpStakerOracle.sol | VESTING_REVIEW.md |
| ReserveLib.sol | RESERVE_SEED_MATH_REVIEW.md |
| SeedLib.sol | RESERVE_SEED_MATH_REVIEW.md |
| CauldronSeeder.sol | SEEDER_REVIEW.md |
| CauldronToken.sol | TOKEN_FACTORY_REVIEW.md |
| CauldronFactory.sol | TOKEN_FACTORY_REVIEW.md |
| RoyaltyRouter.sol | ROYALTY_ROUTER_REVIEW.md |
| MiFrensDividend.sol | DIVIDEND_REVIEW.md |
| CauldronVault.sol | VAULT_REVIEW.md |
| CollectionLedger.sol | COLLECTION_LEDGER_REVIEW.md |
| LegacyBuyLib.sol | LEGACY_BUY_REVIEW.md |
| DefaultFeeRouter.sol | FEE_ROUTING_REVIEW.md |
| FeeRouteLib.sol | FEE_ROUTING_REVIEW.md |
| MintCurvePolicy.sol | POLICY_MATH_REVIEW.md |
| SurtaxLib.sol | POLICY_MATH_REVIEW.md |
| TreasuryGovernor.sol | TREASURY_REVIEW.md |
| GachaLib.sol | GACHA_LIB_REVIEW.md |
| CauldronGachaRouter.sol | GACHA_ROUTER_REVIEW.md |
| CauldronCollection.sol | COLLECTION_REVIEW.md |
| PerpVault.sol | PERP_VAULT_REVIEW.md |
| PerpMarkSource.sol | PERP_MARK_REVIEW.md |
| PerpSwapLib.sol | PERP_SWAP_REVIEW.md |
| PerpEngine.sol | PERP_ENGINE_REVIEW.md |
| IPolicies.sol | INTERFACE_REVIEW.md |
| IDeathChecker.sol | INTERFACE_REVIEW.md |
| ILiquidatorMintable.sol | INTERFACE_REVIEW.md |
| ICauldron.sol | INTERFACE_REVIEW.md |
| vendor/BaseHook.sol | HOOK_BASE_REVIEW.md |
| vendor/HookMiner.sol | HOOK_BASE_REVIEW.md |
| CauldronBase.sol | REGISTRY_BASE_REVIEW.md |
| CauldronGovernor.sol | GOVERNOR_REVIEW.md |
| LaunchSniper.sol | LAUNCH_SNIPER_REVIEW.md |
| CauldronArtAdapter.sol | ART_STORAGE_REVIEW.md |
| render/SSTORE2.sol | ART_STORAGE_REVIEW.md |
| render/TraitStorage.sol | ART_STORAGE_REVIEW.md |
| render/FrenRenderer.sol | ART_STORAGE_REVIEW.md |
| render/LiquidatoorRenderer.sol | BADGE_RENDERER_REVIEW.md |
| deploy/DeployLaunchSniper.s.sol | DEPLOY_HELPERS_REVIEW.md |
| deploy/DeployMigrationVesting.s.sol | DEPLOY_HELPERS_REVIEW.md |
| deploy/DeployQuoteAssets.s.sol | DEPLOY_HELPERS_REVIEW.md |
| deploy/DeployV4Core.s.sol | DEPLOY_HELPERS_REVIEW.md |
| deploy/FixFactoryWiring.s.sol | DEPLOY_HELPERS_REVIEW.md |
| ISeeder.sol | REMAINING_INTERFACES_MOCKS_REVIEW.md |
| ICreatorToken.sol | REMAINING_INTERFACES_MOCKS_REVIEW.md |
| interfaces/INFTContract.sol | REMAINING_INTERFACES_MOCKS_REVIEW.md |
| MockAggregator.sol | REMAINING_INTERFACES_MOCKS_REVIEW.md |
| MockQuoteToken.sol | REMAINING_INTERFACES_MOCKS_REVIEW.md |
| deploy/DeployPerp.s.sol | DEPLOY_PERP_ART_PROBE_REVIEW.md |
| deploy/DeployRenderer.s.sol | DEPLOY_PERP_ART_PROBE_REVIEW.md |
| deploy/BadgeArtLib.sol | DEPLOY_PERP_ART_PROBE_REVIEW.md |
| deploy/SnipeBuy.s.sol | DEPLOY_PERP_ART_PROBE_REVIEW.md |
| deploy/SellVolume.s.sol | VENUE_VOLUME_REVIEW.md |
| deploy/SwapVolume.s.sol | VENUE_VOLUME_REVIEW.md |
| deploy/TopUpVenue.s.sol | VENUE_VOLUME_REVIEW.md |
| deploy/DeployRotationStack.s.sol | VENUE_VOLUME_REVIEW.md |
| deploy/DeployCauldron.s.sol | DEPLOY_CAULDRON_REVIEW.md |
| MiFrensGenesis.sol | GENESIS_REVIEW.md |
| deploy/DeployLaunchpad.s.sol | LAUNCHPAD_REVIEW.md |
| RedemptionExt.sol | REDEMPTION_FACET_REVIEW.md |
| PoolOps.sol | POOL_OPS_REVIEW.md |
| CauldronRegistry.sol | REGISTRY_REVIEW.md |

Every other baseline file remains partial or not reviewed; selected integration
tests do not promote it to fully traversed. Cluster inventories and outstanding
semantic annotations are in COVERAGE.md and graph/skeleton/.

## Completion gates

- [x] Capture frozen baseline inputs and dependency/source hashes.
- [x] Build baseline and extract compiler-resolved declaration/call inventory.
- [ ] Reconcile all current-tree changes against the frozen baseline.
- [ ] Document every first-party function, modifier, constructor and entry point.
- [ ] Complete access-control, external-call and state/accounting analysis.
- [ ] Verify perp solvency, partial closes, liquidation ordering and gas bounds.
- [ ] Verify rotation, requoting, reserve redemption and successor transitions.
- [ ] Verify hook fees, NFT/dividend/gacha, governance and deployment lifecycles.
- [ ] Reconcile historical findings against current reproducible behavior.
- [ ] Fix and verify all confirmed Critical/High/Medium findings.
- [ ] Complete applicable regression, invariant, fork and integration validation.
- [ ] Complete consumer/deployment parity and independent remediation checks.
- [ ] Publish final findings, remaining Low/Info, explicit gaps and source hashes.

## Evidence and freshness rules

Use LEDGER.md and FINDINGS.md for individual findings, logs/ for executed
commands/results, and remediation/ for candidate compiler/surface checks.
Historical log entries describing a running session are checkpoint history,
not evidence that a process is currently running. No test job was active when
this tracker was created.

A file is finally verified only after its functions and lifecycle obligations
are documented, required evidence passes, and remaining limitations are stated.
Subsequent source/dependency changes invalidate affected verification until
reconciled. No push or deployment is authorized by this tracker.

## Latest continuation checkpoint

- Reconciled the completed `badge-floor-fix`: 21 passes, no failures/skips.
- `badge-legacy-and-earned-yield`: legacy badge rejection and both art payouts
  pass; earned-yield replacement-guard property fails on a mock-engine fixture.
  The mixed batch is **not green**. No real-engine reward-loss proof yet.
- PoolOps runtime 24,465 bytes (111 bytes headroom); CauldronVault 2,495 bytes.
  Current source hashes match the passing compiler surface checks.
- No additional full-file traversal or final sign-off claimed this continuation.
- Next: real-engine earned-yield replacement/control reproduction, complete
  PerpVault queue/rotation review, and earned-badge lifecycle integration.

Production-engine continuation: PerpVault full source traversal documented,
24/66 read and 0/66 signed off. `perp-replacement-earned-yield` passed one
mechanism/recovery test, zero skips: old earned claim is disabled by owner vault
replacement and recovers if the empty replacement permits restoration.
FS-perpvault-01 is confirmed Medium, unpatched; final verification remains open.

Latest remediation checkpoint supersedes the preceding unpatched status:
FS-perpvault-01 patched with targeted evidence (25 distinct tests in 32
executions, plus 2 scale tests). New private storage slot explicitly checked;
ABI/selectors unchanged. PerpMarkSource traversal adds one file: 25/66, 0/66
final sign-off. Its 3 boundary and 11 existing tests pass, with mock-manager
limitations. No test process remains active.

Latest checkpoint: **31/66** source traversals, **0/66** final sign-offs.
PerpSwapLib/PerpEngine plus four shared-interface/schema worksheets added.
FS-perpmark-01 is a ninth confirmed Medium: malformed owner-configured tick
blocks ordinary buys through production beforeSwap (without public poke).
Candidate is patched with passing source surface checks; runtime regressions
remain in progress as `perp-mark-range-fix`, session 70859, confirmed live.
Eight earlier Medium patches retain their prior targeted-evidence status;
none is promoted to final sign-off. Mark-boundary acceptance and four-user
reward-debt sequence tests are prepared but not yet executed. See LEDGER.md.

Latest terminal checkpoint: **35/66** source traversals, **0/66** final sign-offs.
FS-perpmark-01 now has targeted verification: four funded/local regressions,
five tick acceptance boundaries, plus 15 neighboring local tests all pass.
The four-user vault conservation test passed 256 sequences of 64 actions.
No test job remains active. Source-matched versioned engine artifacts fit at
24,207 bytes; stale unversioned PerpEngine.json must not be used for deployment.
Registry/base/facet recursive storage parity passes across all 61 entries.
Full validation, deployed parity, consumer gaps and remaining source review open.

Latest terminal checkpoint: **36/66** traversed, **0/66** final sign-offs.
LaunchSniper worksheet and four passing local regressions added. Governor
bounded-bench eviction and fresh-proposal recovery characterized in one passing
test; stronger invariant failure retained, not misclassified as permanent freeze.
No production edits in this continuation; no test jobs remain active.

Latest checkpoint: **40/66** source traversals, **0/66** final sign-offs.
Four art/storage worksheets added; five adapter regressions pass. Dedicated
FrenRenderer tests were excluded by profile and are not counted as passed.
Local asset buffer bound <=118,476/200,000 bytes; arbitrary-upload memory-safety
lead remains open. Governor settled-bench flooding characterization passes.
No test process active; production code unchanged in this continuation.


Latest terminal checkpoint: **41/66** traversed, **0/66** final sign-offs.
LiquidatoorRenderer full source worksheet added, ten local tests pass.
Five real-blob FrenRenderer tests now actually execute and pass via explicit
import under cauldron profile. Standalone render profile compile failure is
retained. Dense valid owner upload reproduces renderer panic: Low
FS-artbuffer-01, unpatched, failing property retained. No production edits;
no test process active. Full validation and all prior gaps remain open.

Latest checkpoint: **51/66** source traversals, **0/66** final sign-offs.
Five deployment helpers, three interfaces and two testnet mocks documented.
Two Low source-confirmed script workflow defects recorded; runtime reproductions
remain pending. No new runtime passes claimed and no scripts broadcast.

Latest terminal checkpoint: **55/66** traversed, **0/66** final sign-offs.
Four more deployment/art/probe files documented. Factory operation identity and
original-calldata recovery verified by one passing local test with actual
TimelockController/factories and stub registry target. No script broadcast.
Remaining script leads include zero upload batch and supplied mark ownership
handoff; no stronger severity asserted without impact verification. No live jobs.

Latest checkpoint: **59/66** traversed, **0/66** signed off.
Volume/rotation/venue files fully read, including deployed VenueSeeder helper.
Open leads: repeated seed overwrites only stored positionId; band tick formula
appears about tenfold wider than documented. Funded/runtime tests remain needed;
no production edits, broadcasts or new runtime passes in this continuation.

Latest checkpoint: **60/66** traversed, **0/66** final sign-offs.
Funded real-manager reproduction confirms Medium FS-venueseed-01: repeated seed
orphans prior LP NFT. Both seed entrypoints now reject a live stored position;
postpatch recover/reseed regression is RUNNING, session57962 / venue-reseed-guard.
No pass claimed until terminal evidence. Nine earlier Medium patches retain
prior targeted verification; new tenth Medium candidate pending verification.
DeployCauldron traversal identifies obsolete hook permission flags (beforeSwap
bits missing); source worksheet records pending reproduction/remediation.
No broadcasts; git diff --check passes.

Latest terminal checkpoint: **61/66** traversed, **0/66** final sign-offs.
Genesis source traversal complete. genesis-lifecycle-regressions: 48 test
executions across11 suites pass, zero failures/skips; inherited/repeated tests
are not 48 distinct security properties. Includes refunds, discount mint, caps,
cancelled ignition, genesis-only voting and three-asset dividend transfer paths.
Venue guard test passes both rejection paths plus recover/reseed/recover. Tenth
Medium now patched with targeted verification; full-scope validation remains.
No test jobs active, no broadcasts. Five large source files remain for traversal:
DeployLaunchpad, CauldronRegistry, CauldronHook, PoolOps and RedemptionExt.

Latest checkpoint: **62/66** traversed, **0/66** signed off.
Full Launchpad review found optional band mode intentionally double-seeded the
same helper. Guard alone would break this supported flow; candidate now uses
separate recoverable full-range/band helpers and logs both. Compatibility and
preflight tests RUNNING session49871 / launchpad-venue-compatibility.
Prior venue guard pass is not sufficient evidence for changed launchpad flow.
No broadcasts. Remaining four files: hook, registry, PoolOps, RedemptionExt.

Latest terminal checkpoint: **63/66** traversed, **0/66** final sign-offs.
RedemptionExt traversal and registry dispatcher boundary review documented.
launchpad-venue-compatibility finished6 passes/7 failures: venue two-helper
lifecycle passes, environment-mutating preflight tests raced. Fresh serial
launchpad-preflight-serial rerun passes all12 preflight tests, no skips. Retain
failed batch; use --threads1 for these shared-process environment tests during
final checks. No complete broadcast/script deployment success claimed.
No running jobs. Remaining traversal: CauldronHook, CauldronRegistry, PoolOps.

Latest checkpoint: **64/66** traversed, **0/66** signed off.
Complete PoolOps source traversal documents all linked-library functions and
host assumptions. Dust legacy sweep and small burn/zero payout remain open
leads, not new confirmed findings. No new tests/production edits this turn.
Remaining traversal: CauldronHook and CauldronRegistry. Full validation open.

Latest checkpoint: **65/66** complete source-body traversals, **0/66** sign-offs.
Registry full executable pass documented plus critical narrative inspected.
New unclassified leads: non-native emergency withdrawal denomination, incomplete
rotated-leg successor handoff, freshly flushed OG legacy share delayed by pending
fold order. None is counted as a confirmed finding without runtime impact proof.
No tests/production edits this continuation. CauldronHook traversal remains;
all semantic/final lifecycle gates remain open, regardless of reading count.

Latest checkpoint: **66/66** complete source-body traversals, **0/66** final sign-offs.
Hook worksheet documents normal beforeSwap liquidation without public poke,
configuration boundaries and outstanding semantic/lifecycle gates. All frozen
files now have traversal evidence; this does not establish security completion.
Next: reproduce deployment permission mismatch and continue unresolved lifecycle
leads and full final validation. No sign-offs inferred from coverage.

Latest terminal checkpoint: **66/66** traversed, **0/66** final sign-offs.
Inventory cross-check maps all66 frozen files to unique existing worksheets;
remediation/TRAVERSAL_INVENTORY_CHECK.json is coverage evidence only.
Low FS-deployhook-01 reproduced and patched. Two actual-constructor tests pass
with --offline; original network-client crash retained. Full script/factory/
summon validation remains open. No live tests, pushes, broadcasts or deployments.

Latest terminal checkpoint: **66/66** traversed, **0/66** final sign-offs.
Earned badge from ordinary swap liquidation cannot redeem art backing: one
integration pass, no public poke. Art issuance remains fixture setup; full
lifecycle/gates remain open. Funded rotation emergency recovery: one pass shows
foreign quote retained in registry and recoverable via separately armed sweep;
non-native LAUNCH quote mismatch not yet reproduced. Initial zero-selected-test
run and three badge fixture failures retained, not counted as passes. No live
jobs or production edits this continuation. git diff --check passes.

Latest checkpoint: **66/66** traversed, **0/66** final sign-offs.
Expanded earned-art-and-badge-native passes with real paid swap credit, native
commit/resolve and swap liquidation; no mint-role impersonation or public poke.
Pity/odds/blockhash and external inventory are explicit fixture assumptions.
VALIDATION.md now maps final requirements to evidence and missing gates;
COVERAGE.md reconciled to all66 traversal worksheets without closing nodes.
Full local cauldron suite RUNNING: candidate-cauldron-full-local, session44592,
--offline --threads1, FORK_RPC empty. Fork omissions will not count as passes.
No full-suite result yet. No production source edits this continuation.

Latest checkpoint: **66/66** traversed, **0/66** final sign-offs.
Current artifact inventory checks all recorded compiler input hashes, not just
the main source.179 artifacts found:171 matching,8 stale.62/66 files have at
least one matching artifact; four renderer/deploy-renderer standalone artifacts
remain absent. Registry runtime24568(headroom8), hook24401(175), PoolOps24465(111),
engine24207(369), VenueSeeder5294(19282). Initcode excludes constructor args;
link/deployment/profile validation remains open. See remediation artifact JSON
and review. Full suite session44592 remains live at direct poll; no final totals
claimed. Fork-required failures observed are separate from protocol verdicts.

Latest checkpoint: **66/66** traversed, **0/66** final sign-offs.
Whole-input-matching artifact coverage now **66/66** after isolated explicit-path
renderer build (renderer-standalone-artifacts exit0, solc0.8.30, cauldron settings).
Separate artifact/cache directories preserve running suite inputs. Original62/66
inventory retained. Constructor args/linking, broad render profile, deployment
and semantic gates remain open. Full suite44592 still live; no aggregate pass.

Latest terminal checkpoint: **66/66** traversed, **0/66** final sign-offs.
Full local suite44592 finished exit1:1079pass/45fail/276skip across356 suites.
Failure triage:39 unavailable-fork,2 outdated OG collection mocks,3 documented
Low properties,1 conditional gacha failed-mint lead. Mock updated to expose
art ceiling; original assertions retained; targeted13-test suite passes.
No production edits. No live jobs. Next gacha reachability check must include
Genesis deployer-set validator, not only registry-deployed brew collections.
Final all-lifecycle/profile/consumer/deployment/semantic gates remain open.

Final-stage tracking clarified at user request: SIGNOFF_CHECKLIST.md and JSON
now enumerate all66 files, current source hashes, their specific next verification
and pending final conclusion. This adds no sign-offs and does not substitute
checklist creation for closing the listed security and compatibility work.
Active next priority: real Genesis continuation validator-rejected gacha mint.

## Final checkpoint (continuation 2026-09-23, Claude Opus 5.5)

**66/66 traversed, 66/66 signed off at local scope with limitations.** Resolved
the Genesis failed-mint lead (FS-gacha-01, Medium, fixed), confirmed and fixed
FS-relaunch-01 (High) and FS-successor-01 (Medium), dispositioned every remaining
worksheet lead (FINDINGS.md table), ran the final full local suite, the whole
suite against a local anvil chain, a production-script deployment and lifecycle
rehearsal, artifact/size/surface/selector/secret gates, and wrote
SIGNOFF_CHECKLIST.md and FINAL_REPORT.md. Completion gates above that require a
target-chain RPC, an independent reviewer or off-chain drills remain open and
are listed as launch blockers in FINAL_REPORT.md.
