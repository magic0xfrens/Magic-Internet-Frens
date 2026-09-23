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

## Rotator result and another concurrent revision

Session 69037 completed, exit 1: local V4 rotator suite **3 passed / 1 failed /
0 skipped**. The absent-oracle rejection failed; healthy-small-trade,
adverse-price rejection and unauthorized-callback controls passed.

Before applying the proposed guard restoration, current source changed again:
the unconditional floor guard and revised X2c absence-of-oracle assertions were
already present. The attempted patch failed its context check and applied no
changes. Preserve these existing edits. HEAD is now
`83ef97bdf3da3ed8520b1eb6f7e3b50a46b4735c`, including `505d3ef` sweep changes.
No commits or pushes were made by this continuation. Prior cap/traversal review
must be compared against this newly committed implementation before patching.

Verification started in session **40984**, offline cauldron, one thread:
`--match-contract 'QuoteRotationLocalIntegrationTest|X2c_OracleFloorFailsSafe|PerpPartialCloseMinimumTest' -vv`.
No result yet; previous failing output belongs to the prior compiled snapshot.

### Collected result: session 40984

### Fresh sweep execution: session 70027

### Hook failure-response fix: completed session 29833

Command: offline cauldron, one thread, `--match-contract
'PreSweepFailureClosedTest|PreSweepLargeBookLocalTest|LocalLIQ02ProjectionTest|LocalLIQ03LiquidationTest' -vv`.
Terminal exit 1: **18 passed / 1 failed / 0 skipped**, 532.76s compilation,
2.67s suite execution. Breakdown: failure-response 3/3, projection 5/5,
liquidation 3/3, large-book 7/8. The mixed-book rotated-cursor refusal remains;
it failed before the hook patch too. No production engine edit was made.

SHA-256 source identities collected after execution (HEAD still `83ef97b`):

- `CauldronHook.sol`: `7b9da2c831c29e46290610751d8dd8a351fe1a32cc00ab8e070673eaea924c4b`
- `cauldron/PerpEngine.sol`: `f198ce7289c30655e040767c9450344b9cd0481360ade5792c8a546ae45c0521`
- `test/audit_full_scope/PreSweepFailureClosed.t.sol`: `42c18eaa4fb6fa47eef0e081ed7595aaf331ab23b8dac43c5334b9dbcbaab27d`

Broader local acceptance now running in session **98155**, same offline profile
and one thread, `--match-path 'test/audit_full_scope/*.t.sol' -vv`. This is not
the full repository/fork lane. One additional Solidity file is compiling; no
result yet. Do not restart session 29833: it is terminal.

### Earlier sweep result details (70027)

Offline cauldron profile, one thread, `--match-contract
PreSweepLargeBookLocalTest -vv`: terminal exit 1, **7 passed / 1 failed / 0
skipped**, compilation skipped. Mixed-book rotated-cursor acceptance fails with
wrapped selector `0x017227af` and argument 30 (trade-too-large refusal), at
reachable cursor 19. No unsafe successful fill was demonstrated by this failure;
successful mixed-book traversal remains unverified. The 24-position exact-input
and exact-output cases pass with zero surviving insolvency and no PLV decrease.
Gas ladder succeeds at 12M/16M and rejects at 1M/3M/5M/8M. The 64-position tests
pass by refusing atomically, not by completing a full-book sweep. The current
badge test accepts inline minting and therefore does not establish deferral.

### Narrow guard result details (40984)

Terminal exit 0: **15 passed / 0 failed / 0 skipped**; compilation skipped.
PerpPartialCloseMinimumTest passed 8, QuoteRotationLocalIntegrationTest passed
4, and X2c_OracleFloorFailsSafe passed 3. This supports the narrow minimum-output
and oracle-floor guards; it does not close the sweep or full-scope audit.

The subsequent source review found that the survivor verification in `_doSweep`
uses the last `_projSqrtP` rather than explicitly re-projecting after the final
settlement. It also runs only when a position was removed (`kills != 0`), not
when settlement merely changed a surviving position. These are review leads,
not yet independently reproduced findings. Check the final-state projection and
partial-rebook paths before certifying pre-trade completeness.

The current 64-position acceptance test expects atomic refusal. Its arithmetic
estimate using inline badge costs is not an execution proof that a deferred-badge
implementation cannot fit. Preserve this distinction from the earlier successful
full-book acceptance requirement; the owner approved claim-later badges without
per-liquidation stats. Existing concurrently edited tests are preserved.

The earlier all-fixed report is not valid for this checkout. No test assertions
were weakened, no failures relabeled as skipped, and no full-scope completion
claimed. QuoteRotator's changed source also requires targeted revalidation.
