# MiFrens full-scope audit — evidence handoff

Date: 2026-09-19  
Tree: current owner-modified working tree; no commit, push, deployment, or live
state mutation was performed.

## Executive status

2026-09-21 correction: current cross-cluster join has **537 unresolved edges**
after rejecting unsupported global dependency-method matches; 15 tooling tests
pass. Older counts and clean cluster checks below are historical. See
`GRAPH_DEPENDENCY_IDENTITY.md` for the current evidence boundary.

The confirmed High/Medium findings in `FINDINGS.md` have production-source
remediations and passing regression/control evidence. This report is an
evidence handoff with explicit residual gaps, not a claim that the protocol is
bulletproof or release-approved. The full-scope gate remains open because the
function graph still has unmapped properties, several semantic annotations are
stale, and fork/deployment parity is incomplete.

## Confirmed findings and remediation

The thirteen confirmed High/Medium findings below have recorded local patches
and focused evidence, but their provisional `FIXED` labels are not final
acceptance. See the overriding status correction in `FINDINGS.md`; outstanding
finding-specific checks mean `PATCHED-UNVERIFIED`, not fully verified closure:

- CORE-01 deployment quote/feed defaults and chain gating.
- HOOK-01 quote-decimal normalization for buyback thresholds.
- PERP-01 collateral-preserving partial rebook accounting.
- ROT-01 mandatory independent floor when the oracle is unset.
- ROT-02 round-trip treasury-position consolidation.
- PERP-02 write-off watermark accounting.
- UI-01 native-destination allowance liveness.
- UI-02 selected-source-leg route construction.
- API-01 credential-safe public RPC diagnostics.
- IDX-01 destination-pool indexing and market selection.
- NFT-01 unified-floor donation/forced-balance guard.
- PERP-03 owner partial-close minimum enforcement.
- PERP-04 pre-trade membership snapshot, bounded traversal, final revalidation,
  and gas fail-closed behavior.

The user-approved pre-trade badge trade-off is preserved: keeper credits remain
claimable, but claim-later badges intentionally omit liquidation statistics.

Low findings remain documented and unfixed: CORE-02, UI-03, GAS-01, and NFT-02
(the historical Z-13 dividend callback finding restored in this continuation).
HOOK-02 also remains unfixed: governance-selected hostile metadata can exhaust
a bounded setter call; the reproduction verifies atomic rollback and success
at a higher cap, not permanent freeze. See `REVIEW_HOOK_THRESHOLD_ACCEPTANCE.md`.

## Executed verification

- Focused remediation suites: **59 passed / 0 failed / 0 skipped**.
- Local lifecycle lane: **18 passed / 0 failed / 0 skipped**, including D04,
  cascade projection/loss, exact-output preemption, pre-sweep traversal,
  deferred badges, gas behavior, and NativeQuoteZap fuzz/custody checks.
- Generation-sync/quote-rotation lane: **5 passed / 0 failed / 0 skipped**.
  The hostile-vault relaunch suite was fork-gated and skipped, so it receives no
  coverage credit.
- The local stale-queue model lane (`K3a_StaleQueueEatsDeposit`) passed **2/2**;
  this is model-vault evidence only. The S08 in-swap gas suite remained
  fork-gated and was not credited.
- Additional local T9b/T9e lanes historically passed **6/6**, comprising five
  security controls and one vulnerability reproduction. T9b's reentrancy test
  asserts that phantom shares DO occur; it does not establish a defense.
  See NFT-02 and `REVIEW_DIVIDEND_CALLBACK.md`. These are local harnesses,
  not deployment-parity evidence.
- Bounded fork lane: **12 passed / 0 failed / 0 skipped** across D04, LIQ03,
  LIQ04, LIQ05, R1B, M4A, and M4B. This is forked local code, not deployed
  bytecode/source parity.
- Off-chain tests: **19 Node + 2 API + 7 indexer + 5 swap-gas passed**.
- `npm run type-check`: passed.
- `npm run build`: passed; only Sass/dependency deprecation and chunk-size
  warnings were emitted.
- `npm run verify:manifest`: passed.
- Indexer codegen: exit 0 with the warning `Failed to find Response internal
  state key`; indexer type-check passed.
- Graph tooling unit tests: **14/14 passed**.
- `git diff --check`: passed.

The complete offline Foundry run remains **803 passed / 35 failed**. Those
failures are retained in `OFFLINE_RERUN.md`; most require fork state. An online
rerun of the remaining fork set crashed Foundry before test execution with a
macOS `system-configuration` NULL-object panic (exit 134), so it receives no
coverage credit.

## Current node and artifact inventory

The compiler-backed graph covers 66 first-party Solidity files, 1,038
declarations, 3,227 call expressions, 14 assembly/delegatecall sites, and 163
contract/interface/library surfaces. Compiler references and selectors resolve
to zero unresolved entries. The coverage ledger contains 2,305 inventory
entries; 27 have current explicit property/test/consumer evidence and 2,278
remain GAP. There are 260 stale semantic annotations. Governance validates
48/48 governance nodes, 61/61 renderer/art nodes, and 69/69 seed nodes validate cleanly; the NFT validator covers 167/167 nodes but reports 305 stale semantic/citation failures, and the hook validator covers 146/146 nodes with 597 stale semantic/citation failures, while other cluster validators still report stale citations, dynamic
target aliases, or unresolved dependency identity. `coverage.py --check`
therefore correctly exits nonzero.

The hardened cross-cluster joiner reports **343 unresolved edges and zero
malformed edges**. Its dependency allowlist was refreshed only with verified
library types; remaining aliases and stale prose targets are not credited.

Current local runtime measurements are recorded in `BASELINE.md` and
`VERIFICATION.md`; all measured deployables remain below EIP-170, with tight
headroom in `CauldronRegistry` and `PoolOps`.

## Residual audit gaps

1. Map explicit authority, storage, asset, ordering, math, liveness, consumer,
   and exact-test evidence for the remaining 2,278 ledger entries.
2. Reconcile 260 stale semantic annotations and the nonzero strict validator
   results, including dynamic deploy-script target identity.
3. Execute the remaining fork-dependent tests once a stable compatible Foundry
   RPC transport is available; the current macOS proxy panic prevented that
   lane from running.
4. Attest source, compiler settings, runtime bytecode, selectors, manifests,
   and deployed addresses for each identified deployment. Local artifacts do
   not prove deployment parity.
5. Complete broader lifecycle properties: legacy-position recovery, full
   funding/OI conservation, hostile-token behavior, reorg/service rehearsal,
   and final invariant campaigns.
6. Reconcile any already-deployed duplicate treasury positions created before
   ROT-02; the fresh facet patch is not an upgrade or recovery plan.

## Reproduction and handoff files

- `PROMPT.md` — authorized scope and completion gates.
- `BASELINE.md` — toolchain/build/test and size evidence.
- `STATUS.md` — live continuation checkpoint.
- `FINDINGS.md` — severity/remediation ledger.
- `VERIFICATION.md` and `OFFLINE_RERUN.md` — command-level evidence and failures.
- `FUNCTION_COVERAGE.json` / `FUNCTION_GRAPH.md` — current node inventory.
- `GRAPH_VALIDATION.md` / `GRAPH_REMAINING.md` — validator results and gaps.
- `REVIEW_*.md` — subsystem review and finding evidence.

## Release decision

**No release approval.** The confirmed High/Medium defects are remediated in
the current source and regression-tested, but unresolved node evidence, fork
coverage, and deployment parity are material audit gates. Do not treat this
handoff as a complete security certification until those gaps are closed.
