# Live Audit Status

Last updated: 2026-09-19

## Current continuation (supersedes historical status below)

PERP-03 restored guard passes its focused suite: 8/8, zero failed/skipped,
session 82377 exit 0. ROT-01 focused local V4 run is compiling in session 69037;
no outcome credited yet. PERP-04 remains open. Details in
`CURRENT_TREE_REGRESSION_RECHECK.md`.

ROT-01 reopened: current source restores the no-oracle zero-floor exception.
Fresh local V4 reproduction is pending completion of existing build 82377;
source evidence and historical reproduction are distinguished in
`CURRENT_TREE_REGRESSION_RECHECK.md`. Do not rely on older FIXED labels.

Current-tree regressions: engine/vault 4/4 pass; partial-close/pre-sweep/rebook
combined 11 pass / 8 fail / zero skipped. Reopened PERP-04; restored the narrow
PERP-03 zero-output minimum guard, pending post-edit verification. Compiler
snapshot is stale for engine and rotator. Read
`CURRENT_TREE_REGRESSION_RECHECK.md` before relying on older fixed/pass claims.

Observed HEAD changed to `6ec1f8e0816c508a9c2f532b212cebd9ca0230ae`; no commit
or push performed by this continuation. Prior test results need freshness checks
against this tree. Reviewed quote transfer helpers, removed two spurious edges
and corrected linked-library delegatecall classification. See
`REVIEW_QUOTE_TRANSFER_BOUNDARY.md` for exact behavior and token-policy gaps.

Strict compiler join now disallows legacy name/getter fallback. Current result:
565 pinned declarations + 66 typed address operations + 1,092 unresolved =
1,723 edges; zero malformed, exit 1. The old 460 count mixed evidence strengths
and is superseded for acceptance. Internal-call notation is matched via exact
compiler target identity. 20/20 tooling tests pass. See
`GRAPH_DEPENDENCY_IDENTITY.md`; security/property coverage remains incomplete.

Compiler-match freshness now checks all 223 compiler input sources, including
dependencies. A changed import invalidates matches even if the caller is
unchanged; regression passes in the 18/18 tooling suite. Correction: the 106
new declaration classifications include imports, not exclusively first-party
targets. Exact totals and remaining legacy resolver limits are documented in
`GRAPH_DEPENDENCY_IDENTITY.md`.

Latest compiler join: 106 exact first-party declaration matches (runtime
implementation unverified), 66 typed address operations, 460 unresolved,
zero malformed; exit 1. Target and caller hashes are required. 18/18 tooling
tests pass. This supersedes the 566 structural-gap count, not the security
property ledger. Details: `GRAPH_DEPENDENCY_IDENTITY.md`.

Compiler-backed join now matches 66 address operations using current source
hashes, exact caller/signature/location/expression and receiver types. They are
reported separately as runtime-target-unverified, not resolved callees. With
explicit compiler/source arguments: 566 unresolved, zero malformed, exit 1;
without them: 632. Tooling tests pass 17/17. Property coverage is not advanced
by structural matching. See `GRAPH_DEPENDENCY_IDENTITY.md` for command/limits.

Compiler inventory regenerated with explicit receiver types/declarations:
3,230 calls, 1,533 member calls; 90 address operations versus 14 same-named
methods on other types. Current source hashes all match. This supplies exact
evidence for the next graph join step, but does not itself close prose edges or
property coverage. See `GRAPH_DEPENDENCY_IDENTITY.md`.

Graph follow-up: removed unconditional resolution for low-level-looking names
and their missing-source exemption. 16/16 tooling tests pass. Join now reports
632 unresolved, zero malformed (supersedes 537); genuine low-level operations
need compiler receiver/type evidence, not a name-based exemption. Details in
`GRAPH_DEPENDENCY_IDENTITY.md`. No Solidity production changes.

2026-09-21 graph integrity correction: dependency resolution now requires the
method on the named dependency, not a global method-name match. 15/15 tooling
tests pass. Current join fails correctly with 537 unresolved edges, zero
malformed, superseding 343. See `GRAPH_DEPENDENCY_IDENTITY.md`; old cluster
zero-failure reports are historical, not proof under the tightened rules.

Latest: 4/4 engine/vault tests pass, including 256 fuzz cases and a real
ETH-rejecting staker. Failed nonzero payout rolls back accounting; another
staker can claim independently, and the rejecting staker can retry after
accepting payments. Native-ETH case only; no global audit closure claimed.

2026-09-21: engine/vault suite now passes 3/3 (256 fuzz cases included).
Added zero/duplicate reward-claim rejection: reverted synchronization cannot
persist an epoch or watermark, and later valid claims still succeed. This does
not cover a nonzero payment rejected by a hostile receiver. See the latest
section of `REVIEW_ENGINE_VAULT_INTEGRATION.md`.

Latest engine/vault continuation: 2/2 tests passed, including 256 fuzz cases
varying rewards and reversing claim order. Pending previews agree with actual
payouts after repeated write-offs; remaining pot and token principal are checked.
Details: `REVIEW_ENGINE_VAULT_INTEGRATION.md`. No production code changes.

2026-09-20: production PerpEngine + PerpVault repeated-writeoff integration
passed 1/1, including actual syncGeneration write-offs, treasury transfers,
late-sync watermark and 1/9 ETH payouts with 10,000 token principal retained.
See `REVIEW_ENGINE_VAULT_INTEGRATION.md`. Registry/pool remain fixtures; real
governance/V4 rotation coverage is not claimed. No production patch this pass.

Latest concrete progress: added and executed `LegacyThresholdAcceptanceTest`,
now 10/10 passed after a hostile metadata reproduction (200k setter fails
atomically, 2M succeeds). Recorded conditional Low HOOK-02, left unfixed, and
added explicit cache-function evidence without claiming full node acceptance.
The original run below remains historical:
9/9 passed (seven new metadata/cache tests plus two inherited buyback cases;
512 fuzz cases). Source-matched hook artifact is 23,762 bytes with the cache
at slot 69. Older committed layout cache is stale around Gacha state and must
not establish baseline parity. See `REVIEW_HOOK_THRESHOLD_ACCEPTANCE.md` for
exact evidence and remaining gates. No production mutation or live operation.

The old `/private/tmp/mifrens-audit-20260918.CgUEVV` worktree is absent.
Current main remains `f1023234f5221b5db4562f51d3d40a1712546fc7`, with the cap
and partial-close-minimum guards present in its existing dirty source.
Engine SHA-256 before the continuation delta was
`d46ce7023be627c2468607d91e37ac6e100a7a47c46fbcc011cb71d6777ac577`; current
post-delta SHA-256 is
`0e3ea4d442881fb527c8d3d22415732455b28af206c752cb682955463b440583`.
A replacement isolated snapshot is being prepared; no root production source
is overwritten, and no push/deployment is performed by this continuation.

Before workspace loss, the snapshot/final-check trial failed the local cascade
test (0 pass / 1 fail): later settlements invalidated an earlier healthy check.
A bounded revalidation trial and owner-approved claim-later badges were then
verified in the replacement snapshot; the initial test compile error was fixed
by removing an invalid reference to internal fee fields.

The full audit remains incomplete. New results and recoverable patch artifacts
will be retained in the repository, not only in temporary storage.

**Fresh focused remediation rerun (2026-09-19):** the current checkout passed
**59/59** tests across the deployment, perp, vault, rotation, oracle-floor, and
unified-vault suites. This is current-source local evidence for the associated
remediations and controls; fork, graph-coverage, and deployed-parity gates
remain open.

The follow-on local lifecycle lane passed **18/18**: D04 rebook funding/penalty,
cascade projection/loss, exact-output preemption, gas-budget behavior, the
24/64-position pre-sweep and deferred-badge cases, and NativeQuoteZap custody
and fee-bearing fuzz checks. These runs exercise local production V4 fixtures,
not a live deployment.

The generation-sync/quote-rotation lane `K3c_RotationStrandsPerpEngine` also
passed **5/5** locally, covering quote-side stake vetoes, timelock override,
authorization, warmup, and empty-vault adoption. Hostile-vault relaunch tests
remain fork-gated and were not credited.

The stale-queue model lane `K3a_StaleQueueEatsDeposit` passed **2/2**; this is
model-vault evidence only. The S08 in-swap gas suite remained fork-gated and was
not credited.

Correction: the historical **6/6** combined T9b/T9e result comprises five
security controls and one successful vulnerability reproduction, NOT a passing
reentrancy defense. T9b explicitly demonstrates phantom dividend shares under
a malicious wired registry. Restored as Low NFT-02 (historical Z-13), left
unfixed per scope; see `REVIEW_DIVIDEND_CALLBACK.md` for evidence and limits.

The governance graph validator was re-run after refreshing compiler artifacts and
current citations: **48/48 nodes, 0 failures**. The renderer/art cluster now
validates **61/61 nodes, 0 failures** using its dedicated `render` profile. The
seed cluster also validates **69/69 nodes, 0 failures** after refreshing its
storage/selector artifacts. The pool validator's dependency
allowlist was also refreshed for current linked libraries, reducing its reported
failures from 48 to 43 without masking its stale citation failures. Remaining cluster validators
still report stale semantic citations or unresolved dependency aliases and are
kept open in the graph gate.

The NFT cluster's current validator run covers all **167/167 nodes** and now
reports 305 stale citation/semantic failures after refreshing its storage and
dependency artifacts; none are treated as resolved security evidence.

The hook cluster covers **146/146 nodes** and currently reports 597 stale
semantic/citation failures after refreshing its storage artifact. These are
graph reconciliation gaps, not findings being silently downgraded.

The hardened cross-cluster joiner now reports **343 unresolved edges and zero
malformed edges** (down from 374 after adding only verified dependency types to
the allowlist). Instance aliases and stale prose-generated targets remain open.

The ledger's thirteen provisional `FIXED` labels previously conflated local
patch/test evidence with completed acceptance. Its status-basis correction now
requires `PATCHED-UNVERIFIED` interpretation wherever finding-specific gates
remain open. HOOK-01, ROT-02, PERP-02 and NFT-01 explicitly retain such gates.
The rest require individual reconciliation, not a blanket closure claim.

**Verified continuation result (isolated snapshot, then applied as the exact
source delta here):** bounded pre-trade membership snapshot plus final
revalidation passed 29/29 focused tests (0 failed, 0 skipped), including the
four-position control, 24/64-position books, exact-output buy, rotated cursor,
gas ladder, cascade projection/loss, partial-close minimum, and 257 rebook fuzz
cases. The separate claim-later badge regression passed 1/1: 24 positions
settled, 24 keeper credits remained claimable, no inline pre-trade mints occurred,
and claimed badges intentionally had zero liquidation stats. This is local
production-code evidence; the full suite, fork lane, and size acceptance remain
open.

The current-source graph was regenerated after these edits: 66 files, 1,038
declarations, 3,227 calls, 14 sensitive sites, 163 surfaces, and zero unresolved
compiler references/selectors. The conservative coverage ledger reports 2,305
entries, 2,278 evidence gaps, and 260 stale semantic annotations; strict cluster
validation still exits nonzero and `coverage.py --check` exits 1, so these remain
explicit audit gates rather than hidden skips.

After removing the isolated snapshot from the repository tree, `npm test`
passed 19 Node tests, 2 API tests, 7 indexer tests, and 5 swap-gas tests;
`npm run type-check` passed. These are current off-chain results, not a full
production build or deployment-parity attestation.

The fresh full offline Foundry run ended **803 succeeded / 35 failed** (exit 1).
Fork prerequisites were unset; the failures are retained as open coverage or
triage items, including `V2A_VoteFarm`. Local adapters for the reviewed
liquidation/rebook paths passed.

Graph tooling unit tests pass **14/14** when run from `audit/graph`. An initial
repository-root module invocation failed due to Python's import path; the
corrected command and result are recorded here, with no audit coverage credited
to the failed invocation.

**Audit continuation moved to an approved isolated worktree:**
`/private/tmp/mifrens-audit-20260918.CgUEVV` at detached base
`f1023234f5221b5db4562f51d3d40a1712546fc7`. Subsequent fixes/results belong there,
not to this concurrently edited main checkout. The retained audit changes and
dependency snapshot were copied explicitly; no reset, merge, commit or push was
performed by this turn. Consult that worktree's report folder for new progress.

**12:02 UTC conflict checkpoint:** another process advanced HEAD and replaced
overlapping engine source during verification, removing the tested PERP-03 and
PERP-04 remedies. They are OPEN again. See `CONCURRENT_EDIT_CHECKPOINT.md` for
executed results and exact pending remedies. Source ownership/stability must be
resolved before final certification; earlier green runs are historical evidence.

**Incomplete; not a release approval.** Work resumed at the user's request. The persistent-goal tool reported `blocked` at this continuation's start, contrary to the previous ACTIVE label here. Do not interpret that old label as evidence of ongoing background execution. No push or deployment is authorized by this audit continuation.

## Completion gate

The review is not complete until every confirmed Critical, High, and Medium issue is:

1. reproduced or otherwise supported by direct executable/source evidence;
2. fixed in production code;
3. pinned by a regression test;
4. checked against affected invariants and lifecycle paths;
5. compiled under the production profile and rechecked for EIP-170 size; and
6. included in the final report with residual risk.

Low and Informational issues may remain only when the final report records their impact, rationale, and recommended disposition.

## Current state

| Workstream | State | Evidence |
|---|---|---|
| Scope/toolchain baseline | Complete | `BASELINE.md`, `TREE_BASELINE.md` |
| First-party Solidity declaration inventory | Current-source enumeration complete | 66 files, 10 clusters, 1,038 declarations after current engine changes; `FUNCTION_GRAPH.md` |
| Graph semantic refresh | Reconciliation required after edits | 260 stale semantic annotations and 2,278 evidence gaps; strict semantic-edge resolution remains nonzero |
| Direct Solidity review | In progress | Hook/NFT, perp/rotation, and registry/pool/governance/seed/art/deploy lanes |
| Candidate reproduction | In progress | Buyback decimal mismatch and missing rotation oracle reproduced; real local V4 partial-close regression passes after patch |
| Production remediations | Local patches; final acceptance pending | PERP-03/PERP-04 focused regressions and claim-later badge regression pass; all remain uncommitted and size/consumer gates remain. |
| Full regression/fuzz/invariant rerun | Offline rerun completed; not a green full-scope gate | 803 passed, 35 failed. Fork prerequisites remain gaps; see `OFFLINE_RERUN.md`. |
| Off-chain checks | Focused checks pass | 19 Node + 2 API + 7 indexer + 5 swap-gas tests; type-check passes. |
| Fork/on-chain parity | Limited read-only observations; not full attestation | Bounded fork lane 12/12 passes; deployed bytecode/source parity remains open. |
| Final audit report | Evidence handoff created; certification pending | `FINAL_REPORT.md` separates fixed findings, low/open items, and residual graph/fork/deployment gaps |

The latest coverage ledger inventories 2,305 entries: source declarations, sensitive assembly/delegatecall sites, and compiler selectors are separate entry classes, not unique functions audited. Twenty-seven entries now have current-source evidence mappings for the remediation lanes; 2,278 remain gaps. Prior reports/tests still need mapping. Fresh direct compiler extraction has 1,038 declarations, 3,227 call expressions, 14 sensitive sites, 163 surfaces and zero unresolved references/selectors or scope issues. None of these structural counts establishes full security coverage. Tooling regressions passed 14/14.

Current integration work: ROT-02's four local lifecycle regressions pass, including repeated rotations, nonzero-reserve preservation followed by redemption, and swap-failure rollback. Registry and facet storage layouts match exactly (60 entries). Deployment-feed checks pass (9 edge cases plus 3 entry-point controls). The repeated-write-off vault suite passes four tests including fuzzing. NFT-01 donation/forced-ETH behavior was reproduced and its fail-closed guard now passes 8 new regressions plus 6 legacy controls. New local liquidation-edge adapters preserve existing assertions.

## Current confirmed evidence

The buyback decimal regression and 18-decimal control pass after a local patch. Three deployment preflight rejection tests pass. The perp rebook accounting tests pass, including 256 fuzz cases, and a production PoolManager/PerpEngine partial-close integration test preserves backing and subsequent funding.

A real local V4 rotation test failed before the newest patch: with no oracle configured, a large-price-impact trade proceeded despite the expected `NotPriceable` rejection. The fresh-oracle control rejected the same trade. The patch now requires an independent nonzero floor even when the oracle is unset. The focused post-patch run completed with 43 passed, 0 failed, 0 skipped across six suites, including 256 fuzz cases. Final acceptance and full regression remain outstanding.

These are local source changes, not deployed fixes or a completed audit. See `VERIFICATION.md` for test scope and limitations.

## User-visible deliverables

- `PROMPT.md` — revised full-scope review specification.
- `BASELINE.md` — builds, tests, toolchain, and size headroom.
- `TREE_BASELINE.md` — scope counts and graph coverage.
- `STATUS.md` — this live checkpoint.
- `REVIEW_*.md` — direct source-review evidence as each lane completes.
- `FINDINGS.md` — normalized severity ledger and remediation state.
- `FINAL_REPORT.md` — final evidence-backed handoff after the completion gate passes.
