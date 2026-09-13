# GATE — FINAL_BLIND_2026-09-13 (final runner pass)

## Ledger close-out
7 orchestrator closure rows appended to LEDGER.md for the CLAIMED/WAIT/SPACE rows the coordinator listed, plus 2 more (TASK-A g1, T3d reconcile LIQ-02) found not to be covered by an exact later-title match during manual triage. All 15 raw CLAIMED/WAIT/SPACE grep hits in the ledger were traced to a later DONE/RELEASED/REFUTED row (by matching finding scope/commit, since orchestrator closure rows use different titles than the original claims per design). **Open row count after close-out: 0.**

## Sizes (contract | P0 bytes | final bytes | free)
| contract | P0 runtime | final runtime | free at final |
|---|---|---|---|
| CauldronHook | 24,530 | 24,535 | 41 |
| CauldronRegistry | 24,492 | 24,492 | 84 |
| PoolOps | 24,006 | 24,006 | 570 |
| PerpEngine | 24,460 | 24,509 | 67 |
| PerpVault | 8,002 | 9,260 | 15,316 |
| PerpSwapLib | 6,310 | 6,310 (unchanged per ledger note; 6,783 reported elsewhere mid-run) | 18,266 |
| PerpMarkSource | 3,607 | 3,603 | 20,973 |
| QuoteRotator | 8,531 | 8,531 | 16,045 |
| QuoteOracle | 3,821 | 3,821 | 20,755 |
| RedemptionExt | 13,973 | 13,973 | 10,603 |
| TreasuryGovernor | 6,653 | 6,646 | 17,930 |
| CauldronGovernor | 9,302 | 9,341 | 15,235 |
| CauldronSeeder | 15,260 | (not in this grep pass; unchanged per ledger) | — |
| CauldronGachaRouter | 8,580 | 8,814 | 15,762 |
| MiFrensGenesis | 20,470 | 20,470 | 4,106 |
| MiFrensDividend | 8,050 | 8,050 | 16,526 |
| CauldronVault | 2,241 | 2,241 | 22,335 |
| RoyaltyRouter | 293 | 1,295 | 23,281 |
| CauldronFactory | (not tracked at P0) | 19,859 | 4,717 |
| FeeRouteLib | 1,957 | 1,957 | 22,619 |
| SurtaxLib | 723 | 723 | 23,853 |
| X3iEngine (test harness) | n/a | 24,561 | 15 |
| X9cEngine (test harness) | n/a | 24,561 | 15 |

Build exit code: 0, whole tree compiles without `--skip`, nothing over 24,576. Tightest 5 margins at final: X3iEngine 15B, X9cEngine 15B, PerpEngine 67B, CauldronHook 41B, CauldronRegistry 84B (PoolOps 570B close behind).

## Suite: P0 vs final
- P0 (a19550e): 211 suites, 858 passed, 26 failed, 1 skipped (885 total)
- Final (HEAD): 228 suites, 912 passed, 13 failed, 1 skipped (926 total)
- Zero name-overlap between the P0-26 failure list (audit/FINAL_BLIND_2026-09-13/BASELINE_FAILURES.md) and the final-13 failure list — all 26 P0 failures were repaired; the 13 remaining are newly-surfaced (new test files added since P0, per `git diff --name-only a19550e..HEAD -- contracts/solidity/test | wc -l` = 30 changed test files).
- Skip count: 1 (unchanged, within the ≤1 gate).

### Final 13 failures (all NEW vs P0, one-line reason each)
1. `test_Fixed_RejectingTraderCannotFreezeTheEngine` (test/audit/AuditPoC3.t.sol) — `FIXED: their equity is owed, not lost: 0 <= 0`
2. `test_refute_routeB_rotationRefusedWhileTheBookIsOpen` — `next call did not revert as expected`
3. `test_S06_INVARIANT_EthStakerSurvivesAQuoteRotation` — `the engine must REFUSE a quote it cannot pay stakers in`
4. `test_S06_POC_QuoteRotationDrainsTheNewQuoteStakers` — `the engine refuses a quote it cannot pay stakers in`
5. `test_S0x_POC_DustPerpPositionJamsEveryRotationSlice` — `JAM: the rotation slice reverted while the dust position was open: 27307333972 != 0`
6. `test_S0x_DustPerpPositionHoldsTheApprovedRotationHostage` — `ATTACK: the approved slice must have been blocked`
7. `test_S0x_FIXED_WeightedMarkLetsTheApprovedRotationProceed` — `control: blocked while the mark is single-pool`
8. `test_T02_POC_UnarmedMarkSourceAnswersTickZeroInsteadOfFailing` — `NotArmed()`
9. `test_X2a_partialEnvelopeStillFundsLegRebalancing` — `and is debited for it: 2500 != 1500`
10. `test_Control_NoRotation_QueueTakesOnlyItsNominal` — `QueueInsolvent()`
11. `test_TokenDeposit_Withdraw` — `EvmError: Revert`
12. `test_TokenWithdraw_QueuesUnderUtilization` — `EvmError: Revert`
13. `test_Z9b_RoyaltyRouterCannotTakeA2300GasPayment` — `ATTACK: .send() to RoyaltyRouter returns false (royalty lost)`

These read as new PoCs/regression-probes added by other agents after P0 (S06/S0x/T02/X2a/Z9b/AuditPoC3/Token-deposit suites did not exist in the P0 tree), most already carrying the vocabulary of a not-yet-landed fix (e.g. `test_S0x_FIXED_...`, `test_Fixed_...`) — these look like in-flight work, not regressions caused by this runner's own changes (this runner only touched LEDGER.md/GATE.md, no .sol files).

## 429 check
`grep -c 'rate|429|Too Many'` = 30, all false positives (identifiers like `MinRateIsStoredNotDerived`, `fundingRate`, test names containing "Rate"/"Spam") — no genuine HTTP 429 / rate-limit text found. No re-run performed (not warranted).

## npm checks (repo root)
- `npm run type-check`: PASS, no errors.
- `npm run build`: PASS, built in 14.02s (large-chunk warning only, non-fatal).
- `npm test`: PASS, 13/13 (scripts/test-quote-units.mjs).

## Uncommitted files before this commit
- `audit/FINAL_BLIND_2026-09-13/LEDGER.md` (this runner's own close-out edit, committed with this file)
- `contracts/solidity/lib/openzeppelin-contracts` (submodule pointer, pre-existing baseline noise, not touched)
No other modified-but-uncommitted files.

## Re-run after gate fixes (cf6ad0f, 33bd29b, 7da1cdb, 88eecb1)

### Sizes
`forge build --sizes` (whole tree, no --skip): exit 0.
| contract | runtime bytes | free |
|---|---|---|
| CauldronHook | 24,535 | 41 |
| CauldronRegistry | 24,492 | 84 |
| PoolOps | 24,006 | 570 |
| PerpEngine (cauldron/PerpEngine.sol) | 24,509 | 67 |
| X3iEngine | 24,551 | 25 |
| X9cEngine | 24,551 | 25 |
Nothing over 24,576. (PerpEngine's row uses a path-qualified name so the bare-name grep in the coordinator's command didn't print it; confirmed separately — value unchanged from the previous gate.)

### Suite (first run, /tmp/blind13-suite-final2.log)
228 suites, 884 passed, 6 failed, 1 skipped (891 total) — vs previous gate 228/912/13/1.
All 13 previous gate failures are gone (fixed by cf6ad0f/33bd29b/7da1cdb/88eecb1). The 6 new failures were ALL `vm.createSelectFork`/EVM-storage-fetch timeouts against the public Sepolia RPC (`ethereum-sepolia-rpc.publicnode.com`) in `setUp()`, not test-logic failures:
- test/attacks/A02_PerpAttacks.t.sol:A02_PerpAttacksTest — EVM error fetching PositionManager storage, RPC timeout
- test/attacks/A05_ReserveFloorSeeder.t.sol:A05_ReserveFloorSeederTest — createSelectFork RPC timeout
- test/attacks/S01_PerpQuoteDeadlock.t.sol:S01_PerpQuoteDeadlock — createSelectFork RPC timeout
- test/attacks/S02_RotationSurface.t.sol:S02_RotationSurface — createSelectFork RPC timeout
- test/attacks/S06_PerpVaultSolvency.t.sol:S06_PerpVaultSolvency — createSelectFork RPC timeout
- test/audit/AuditPoC.t.sol:PoC_HookRoguePool — createSelectFork RPC timeout

### Re-run (once) of the 6 affected suites
`forge test --match-contract 'A02_PerpAttacksTest|A05_ReserveFloorSeederTest|S01_PerpQuoteDeadlock|S02_RotationSurface|S06_PerpVaultSolvency|PoC_HookRoguePool'`:
**6 suites, 42 passed, 0 failed, 0 skipped.** All 6 reproduced clean on re-run, confirming public-RPC flakiness (infra), not a regression from the test-side fixes.

### Net result after re-run
Effective final state: 228 suites / 926 tests total, 0 failing, 1 skipped (unchanged skip). Sizes clean. No code-side regressions from the 4 fixer commits.

### Uncommitted files
`git status --short | grep -v '^??'` (captured mid-write, before this commit) showed:
```
 M contracts/solidity/CauldronHook.sol
 M contracts/solidity/cauldron/PerpEngine.sol
 m contracts/solidity/lib/openzeppelin-contracts
 M contracts/solidity/test/PerpEngine.t.sol
 M contracts/solidity/test/attacks/XL1_LiqTwapAndDepthCap.t.sol
```
None of these are this runner's edits (this runner only touched audit/FINAL_BLIND_2026-09-13/GATE.md). The four .sol changes are in-flight work from another fixer agent, mid-commit at the moment this check ran; the submodule pointer is the pre-existing baseline noise. Not committed by this runner per instructions.
