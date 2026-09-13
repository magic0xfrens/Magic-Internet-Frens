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
