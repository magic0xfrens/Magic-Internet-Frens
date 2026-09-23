# Fresh audit status

**FINAL (2026-09-23, continuation by Claude Opus 5.5 after Codex credit exhaustion):
66/66 files traversed, 66/66 signed off at local scope with stated limitations.**
Verdict: do not deploy this exact tree to mainnet today; ready for a testnet
redeploy and the target-chain gates in FINAL_REPORT.md.

- Findings: 2 High + 12 Medium, all fixed with passing regressions; 11 Low (1
  fixed, 10 documented); Informational items documented. New this continuation:
  FS-relaunch-01 (High), FS-gacha-01 (Medium), FS-successor-01 (Medium), plus
  Low/Info dispositions for every remaining worksheet lead.
- Final full local suite: 1100 pass / 42 fail (39 need a fork, 3 documented
  Lows) / 276 skip. Same suite against a local anvil chain with V4 core:
  1448 pass / 12 fail (8 need real Sepolia state, 3 documented Lows, 1
  superseded premise since tightened and passing) / 1 skip.
- Production scripts DeployV4Core, DeployLaunchpad, DeployPerp rehearsed on the
  local chain with a full lifecycle incl. relaunch with an open perp book.
- Gates: snapshot 4,304/4,304 intact; 66/66 source-matched artifacts; all
  deployables within EIP-170 (registry 24,553 bytes); only intended ABI/storage
  deltas; 43/43 frontend selectors present; git diff --check clean; no project secrets.
- LIVE DEPLOYMENT WARNING: deployed Sepolia r46 predates these fixes and still
  contains FS-relaunch-01 — relaunch only with an explicit gas limit well above
  8.5M and preferably an empty perp book until redeployed.

Documents: FINAL_REPORT.md, SIGNOFF_CHECKLIST.md, FINDINGS.md, VALIDATION.md,
LEDGER.md, rehearsal/README.md, remediation/FINAL_*.json. No commit, push,
public broadcast or deployment was performed.

Historical checkpoints follow (superseded by the summary above).


Latest terminal status: full local profile run completed exit1,1079pass/45fail/
276skip.39 failures require unavailable forks;2 OG mock failures repaired and
13-test targeted suite passes;3 documented Low failures and1 conditional gacha
lead remain. No live test jobs. All66 files traversed and artifact-matched;
0final sign-offs. Prior running statements below are historical.


Active verification: `candidate-cauldron-full-local`, session44592, full
cauldron test selection --offline --threads1 with empty FORK_RPC. Running at
last poll; no aggregate result claimed. Expanded paid-art/earned-badge scenario
passes (`earned-art-and-badge-native`); earlier art fixture gap is superseded.
VALIDATION.md records still-open final gates.

Current checkpoint (supersedes all historical entries below): **66/66 source
traversals, 0/66 final sign-offs**. See PROGRESS.md for authoritative coverage
and worksheets. Ten Medium fixes and the badge-floor High fix have targeted
evidence; full-scope final validation remains incomplete. Low deployment hook
permission mismatch additionally patched with two passing local constructor
tests (deploy-hook-permission-offline). Latest continuation adds one earned-badge swap-liquidation rejection pass
(no public poke) and one funded emergency rotated-quote recovery pass. Art-draw
acquisition and non-native launch recovery remain open. No live test job at
this checkpoint.
Historical session/running/state statements below are retained provenance,
not claims about current processes or active goal status.

Newest: FS-dividend-02 malformed ERC20 payout response reproduced and isolated
payout candidate implemented in MiFrensDividend. New helper is self-call-only;
ABI addition requires explicit validation (prior unchanged-dividend-ABI report
applies ONLY to the earlier residual-only patch). Session 85028 is running
dividend-payout-isolation. Added security tests and refreshed surface checks
remain pending. Full audit incomplete; no push/deploy.

Newest checkpoint: FS-dividend-01 native residual accounting fix verified by
13 focused/neighbor passes and 256 sequence fuzz cases, with unchanged ABI,
selectors and storage; runtime 8,078 bytes. No current command remains live.
Three production files now contain audit fixes: QuoteOracle, MigrationVesting,
MiFrensDividend. These targeted results do NOT establish full-scope completion.
Remaining graph annotations, major subsystem reviews and final validation are
still required. Earlier pending-job paragraphs below are historical.

Newest seeder checkpoint: existing local seeder/math batch 20 passed; initial
range-tracking test passed. Stronger non-vacuity assertions now running in
session 16808 (`seeder-range-tracking-nonvacuous`). R23-L2 remains unconfirmed.
Current PoolOps SEED_BASE_WAD=1e18 means registry launch skips startSeed; this
limits standalone campaign tests' production-reachability claims. See
SEEDER_REVIEW.md. Full-scope audit incomplete; no push/deploy.

Newest: real local registry vesting integration passed (one test, zero
failures/skips), logs/vesting-registry-conservation.*, exit 0. Session 83446
is terminal; no test session currently live. VESTING_REVIEW.md contains the
16-function implementation worksheet and PerpStakerOracle boundary notes, with
explicit gaps. Full audit remains incomplete; earlier pending statuses below
are historical.

Latest checkpoint (supersedes historical statuses below): FS-vesting-01
implemented in MigrationVesting._isInstant. Focused/neighbor batch 29 passed
(nine inherited duplicates); post-fix invariant batch six passed, zero failures
or skips. ABI/selectors/storage unchanged; runtime 4,740 bytes. Real registry
integration initially failed an overstrict nominal 1:1 test assumption; source
permits CLAIM_DUST rounding. Corrected test preserves exact actual-receipt
conservation and explicitly checks dust bounds. Session 83446 is running
`vesting-registry-conservation`; collect it before starting another build.
Full audit remains incomplete. Current HEAD observed: 20640d02c6a678881b451faf14ee3aa345f84a4d;
committed Solidity matches original baseline, while uncommitted audit patches
now include QuoteOracle and MigrationVesting. No push/deploy performed.

Latest zap callback batch: 2 passed, no failures/skips; selected candidate total
214 passed. Production manager refused nested unlock during refund; rejecting
refund rolled back pool/custody effects. See NATIVE_ZAP_REVIEW.md. No live job.

Latest completed rotation-gate batch: 24 passed, no failures/skips, exit 0;
logs/rotation-gates-review.*. Candidate selected total: 212 passing tests across
three disjoint batches. Full QuoteRotator source traversal worksheet saved;
callback, asset-model and plan/arb interaction gaps remain. No live test command.

Latest: oracle fix validation completed. Session 11212 exited 0 (42 passing
tests); session 37311 exited 0 (146 passing neighboring tests). No live command.
FS-oracle-01 is fixed with targeted verification; full audit/final gates remain
incomplete. See FINDINGS.md and VERIFICATION.md. Earlier running-job notes below
are historical and superseded by this checkpoint.

Candidate compiler-surface check passed: unchanged QuoteOracle ABI, selectors
and structural storage layout; source hash matched. Evidence in remediation/.
Session 11212 still live at last direct poll; collect it, do not restart.
Owner-side indexer/deployments/round.json is now modified; left untouched and
requires reconciliation in the later deployment-parity review.

FS-oracle-01 candidate fix is implemented in root QuoteOracle.sol. Validation
is running in session 11212, logs/oracle-fix-regressions.*; it is NOT yet marked
fixed. Original snapshot is intact. This paragraph supersedes older no-live-job
and implementation-pending checkpoints below.

FS-oracle-01 confirmed Medium at the consumer boundary; remediation claimed in
LEDGER.md, not implemented yet. Real-hook local integration: control passes,
malformed-response case fails because new recorded volume is zero after a funded
trade. Evidence logs/oracle-hook-lifecycle.*. Selected baseline aggregate:
157 passed, 6 failed, no skips. No test command remains live.

Oracle boundary reproduction completed: **5 failures**, no passes/skips in the
new R23_OracleFailureBoundaries test. Selected fresh aggregate is now **156
passed, 5 failed**. See ORACLE_FAILURE_LEAD.md: the oracle mechanism is executed,
but consumer impact/severity remain under investigation. No production fix yet.

Latest completed batch: oracle source review and 35 additional local tests,
all passing with no skips. Selected fresh total: 156 tests passed. See
QUOTE_ORACLE_REVIEW.md for function notes, assertion limitations and consumer
gaps. No current test command is live. The goal remains incomplete.

Scope: SCOPE.md. Old audit verdicts and test totals are not imported.

- Baseline HEAD: `31b753546c0e39efb7ae3c28efe9ee4d7fa67df5`.
- Snapshot: 4,304 hashed files; 66 first-party Solidity files; 273 test/helper
  Solidity files. Count of test functions is not yet established.
- Root worktree was clean except a nested submodule pointer. OpenZeppelin's
  forge-std was at `1801b0541f4fda118a10798fd3486bb7051c5dd6`, not the recorded
  `3b20d60d14b343ee4f908cb8079495c07f5e8981`. Captured unchanged.
- BASELINE.json records individual hashes and recursive dependency commits.
- Snapshot excludes old out/cache, broadcasts, git metadata and .env files.
- Foundry: 1.4.4-nightly, commit `765b8562482bf3e0227412e26ea15abae980dee1`.
- First clean-input build: `FOUNDRY_PROFILE=cauldron forge build --offline
  --sizes --threads 1`, through run.py; passed, exit 0 in 1,115.37 seconds.
  Evidence: logs/baseline-build.json and .log.
- The cauldron profile excludes legacy Peg/presale and renderer lanes. Those
  first-party files remain in scope and need separate compilation/review.
- Function map, property coverage, findings and old-finding reconciliation:
  tokenizer inventory generated: 1,093 declaration nodes, all unreviewed;
  see COVERAGE.md. Fresh compiler extraction also reports 1,093 declarations,
  3,433 calls, 30 sensitive sites and 168 contract surfaces; unresolved compiler
  references/selectors: 0. This is mechanical resolution, not semantic coverage.
  Evidence: COMPILER_GRAPH.json.
  No production remediation applied.
- Local baseline regression lane: 108 passed, 0 failed, 0 skipped in 24 suites.
  Evidence: logs/initial-local-regressions.json and .log.
- Local requote lane: 10 passed, 0 failed, 0 skipped in two suites (F12/F12b).
  Evidence: logs/requote-local-regressions.json and .log. These use fixtures;
  assertions still require review, and passing is not a security certification.
- Added test/audit_reaudit/RotationTotalityLocal.t.sol in the root tree and as
  an identical, additive snapshot harness. No original snapshot input changed.
  This runs inherited F14/F14c assertions with actual local V4 managers/Permit2,
  replacing only fork bring-up. Characterisation assertions are not safety proofs.
- Open-book local lane finished successfully: 2 passed, 0 failed, 0 skipped;
  exit 0, 625.77 seconds including compilation. Evidence:
  logs/open-book-local-regressions.*. No remaining live test command.
  Total across the three selected fresh lanes: 120 passed, 0 failed, 0 skipped.
- Build-size constraint: registry runtime 24,568 bytes (8 bytes headroom);
  engine runtime 24,168 bytes (408 bytes headroom). Recheck after any fix.
- Rechecked all 4,304 original snapshot hashes after adding the harness:
  zero changes. Root/snapshot harness copies are identical, SHA256
  `df63bc48937d73af8481955f2ddfbcb47eb590d40f13cc3348fe60ecfe4f0230`.
- Intermediate evidence and an unconfirmed cascade-completion lead are in
  REVIEW_NOTES.md. No fresh vulnerability severity or remediation is claimed.

Fresh cascade-ordering property: R23_CascadeOrderingLocal.t.sol passed 64 fuzz
cases, exit 0, 21.83 seconds including compilation; evidence in
logs/cascade-ordering-64.*. This adds one passing test (121 selected tests total),
not 64 independently reviewed properties. The suspected cascade defect remains
unconfirmed; this bounded mixed-book check did not reproduce an unsafe outcome.

Persistent-goal control: the user replaced the old objective with this fresh
audit. The runtime subsequently reported active, but the latest observation
reports blocked; the returned state does not explain why. No live test command
remains after collection of the cascade run. Do not infer that a UI warning
stopped a command, and do not install warning-triggered resume loops.
