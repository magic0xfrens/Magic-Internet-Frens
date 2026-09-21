# Current-tree regression recheck — 2026-09-21

Observed HEAD: `6ec1f8e0816c508a9c2f532b212cebd9ca0230ae`.
223 compiler-input hashes checked: PerpEngine.sol and QuoteRotator.sol differ
from the compiler graph snapshot. It must be regenerated before strict matching.
No commit, push or deployment performed in this continuation.

## Executed before this pass's production edit

From `contracts/solidity`, offline, one thread, cauldron profile:

- `--match-contract PerpVaultEngineWriteoffTest -vv`: exit 0, 4 passed,
  0 failed/skipped, including 256 fuzz cases. These results revalidate the
  narrow production engine/vault boundary on the observed tree.
- `--match-contract 'PerpPartialCloseMinimumTest|PreSweepLargeBookLocalTest|PerpRebookAccountingTest' -vv`:
  exit 1, **11 passed / 8 failed / 0 skipped**. Partial-close suite 7/1;
  pre-sweep suite 1/7; rebook suite 3/0 including 257 fuzz cases.

The nonzero-minimum partial-close test fails because the current branch rebooks
and returns without `_ownerFloor(ownerSlippage, 0, minOut)`. Restored that
narrow guard with two explanatory comment lines; three-line source delta only.
The zero-minimum behavior and liquidation/death policy are not intentionally
changed. Post-edit focused run was started; record its outcome before closure.

The seven pre-sweep failures cover 24/64-position books, exact-output buying,
rotated cursor, gas-ladder executability, Sepolia transaction gas cap and
claim-later badges. The four-position control passes. Current source uses
cap/check-only behavior and does NOT contain the historical full traversal /
badge-defer patch. Failures mostly demonstrate refusal/liveness and policy
mismatch; do not claim they reproduce the older successful-swap insolvency.
PERP-04 acceptance is reopened. Do not overwrite newer cap logic with a stale
snapshot: reconcile current invariants and user-approved badge policy first.

## Cap/check-only liveness reconciliation

Current `_doSweep` keeps eight settlements, then scans in check-only mode and
returns incomplete when another position trips projected liquidation. The test
fixture's `_openBook` explicitly asserts EVERY position is not liquidatable
before the trigger trade. Therefore the comment's proposed permissionless
`liquidate` escape is not available for those healthy positions at that state.
Trade refusal is atomic and does not advance liquidation progress. This explains
the demonstrated large-trade liveness failure without claiming a successful
unsafe trade or permanent inability to execute smaller trades.

The latest design must preserve fail-closed safety, post-trade bounded behavior,
and owner-approved pre-trade claim-later badges while supporting the bounded
book under the tested budget. Review stable membership traversal (swap-pop and
rotated cursor), re-projection after each settlement, and final survivor
revalidation before applying any replacement. Do not merely raise the cap or
weaken the large-book test's executability assertion.

The partial-close post-edit build remains active in verified session `82377`:
0.8.26 completed, 0.8.30 compilation still running at the last poll. No restart
was attempted; no passing result credited. Process-list inspection was denied
by the sandbox, but the original session remains a valid live handle.

## Recovered implementation comparison

The replacement snapshot is still present at
`/private/tmp/mifrens-audit-20260919-final/contracts/solidity/cauldron/PerpEngine.sol`.
Inspected its complete `_doSweep` body and badge entrypoint against current
source; it is a reference for a narrow delta, NOT a file to copy over the owner
tree. Its pre-trade path snapshots membership, scans all captured IDs, then
rechecks survivors at the final projected price. Any additional settlement
restarts that check, requires strictly reduced position size, and consumes one
of at most the original book length retry credits. Gas failure returns incomplete.
Post/open sweeps retain the existing eight-kill bound.

Important integration difference: the snapshot calls `_awardBadge` with the
position/bounty and computes `_killStats` only for immediate minting. Current
source computes `_killStats` BEFORE `_awardBadge`. Merely changing the current
mint condition would defer the NFT but retain the statistics computation cost.
Any restored deferred-badge optimization must account for that call-site
difference while preserving keeper-payment math and attribution events.
No sweep or badge code has been changed during the active minimum-guard build.

## ROT-01 source regression identified

Current `QuoteRotator.swapOnce` at line 390 again uses
`if (floor == 0 && quoteOracle != address(0)) revert NotPriceable();`.
The previous unconditional zero-floor guard is absent. Its accompanying
comment explicitly preserves no-oracle operation based on caller `minOut`,
despite the permissionless forwarding path. Reopened ROT-01 as OPEN based on
this current source and the previously reproduced mechanism, not a claimed
fresh exploit execution. The local V4 regression
`QuoteRotationLocalIntegrationTest.test_unsetOracleMustNotRemovePermissionlessPriceFloor`
remains available for the next run. The older X2c comments still endorse the
exception; do not confuse that historical expectation with the audit invariant.
Rotator production code was not edited while session 82377 was compiling.

## Partial-close post-edit result

Session 82377 completed, exit 0: **8 passed / 0 failed / 0 skipped** in
PerpPartialCloseMinimumTest. The nonzero minimum now rejects, explicit zero
minimum still permits partial progress, and the six inherited local liquidation
controls pass. Solidity 0.8.30 compilation took 376.68s; do not confuse build
time with test execution. This verifies the restored narrow guard, not the
still-open pre-sweep traversal or full-scope acceptance.

Next command started with `--match-contract QuoteRotationLocalIntegrationTest`
(same offline cauldron profile / one thread) in session 69037. Foundry began
recompiling 81 files with 0.8.30 plus five with 0.8.26; no result yet. Do not
restart this live handle or treat the fresh oracle regression as executed until
its terminal test output is available.

Concurrent-edit correction: after the completed partial-close run, another edit
inserted an equivalent guard at the start of the same branch. `git diff` showed
both that four-line insertion and this continuation's three-line insertion.
Removed ONLY this continuation's duplicate, preserving the other guard and its
comments. The latest engine source therefore differs from the completed build;
8/8 is historical patch evidence, not a source-hash attestation of the newest
file. Source edits during the active rotator build also require freshness checks
before attributing its result. No other editor's delta was removed.

The earlier all-fixed report is not valid for this checkout. No test assertions
were weakened, no failures relabeled as skipped, and no full-scope completion
claimed. QuoteRotator's changed source also requires targeted revalidation.
