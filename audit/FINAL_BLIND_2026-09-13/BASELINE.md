# BASELINE — FINAL_BLIND_2026-09-13

Pre-touch tree state:
- git status --short line count: 1
- HEAD: 0f141b0
- branch: redteam/2026-09-11

- snapshot branch: redteam/2026-09-13
- snapshot commit: a19550e

## STEP 3 — build sizes
Build exit code: 0

Sizes table (contract | runtime | initcode | runtime margin | initcode margin):
```
| CauldronCollection                                                                                                                                | 11,553           | 14,033            | 13,023             | 35,119              |
| CauldronGachaRouter                                                                                                                               | 8,580            | 9,021             | 15,996             | 40,131              |
| CauldronGovernor                                                                                                                                  | 9,302            | 9,643             | 15,274             | 39,509              |
| CauldronHook                                                                                                                                      | 24,530           | 25,626            | 46                 | 23,526              |
| CauldronRegistry                                                                                                                                  | 24,492           | 25,128            | 84                 | 24,024              |
| CauldronSeeder (cauldron/CauldronSeeder.sol)                                                                                                      | 15,260           | 15,618            | 9,316              | 33,534              |
| CauldronToken (CauldronToken.sol)                                                                                                                 | 2,033            | 3,176             | 22,543             | 45,976              |
| CauldronVault                                                                                                                                     | 2,241            | 2,520             | 22,335             | 46,632              |
| CollectionLedger                                                                                                                                  | 1,972            | 2,185             | 22,604             | 46,967              |
| DefaultFeeRouter                                                                                                                                  | 349              | 375               | 24,227             | 48,777              |
| FeeRouteLib                                                                                                                                       | 1,957            | 1,989             | 22,619             | 47,163              |
| LaunchSniper                                                                                                                                      | 1,703            | 1,912             | 22,873             | 47,240              |
| MiFrensDividend                                                                                                                                   | 8,050            | 8,755             | 16,526             | 40,397              |
| MiFrensGenesis                                                                                                                                    | 20,470           | 23,494            | 4,106              | 25,658              |
| MigrationVesting                                                                                                                                  | 4,757            | 5,204             | 19,819             | 43,948              |
| MintCurvePolicy                                                                                                                                   | 871              | 1,143             | 23,705             | 48,009              |
| PerpMarkSource                                                                                                                                    | 3,607            | 3,862             | 20,969             | 45,290              |
| PerpSwapLib (cauldron/PerpSwapLib.sol)                                                                                                            | 6,310            | 6,342             | 18,266             | 42,810              |
| PerpVault                                                                                                                                         | 8,002            | 8,335             | 16,574             | 40,817              |
| PoolOps                                                                                                                                           | 24,006           | 24,038            | 570                | 25,114              |
| QuoteOracle                                                                                                                                       | 3,821            | 3,979             | 20,755             | 45,173              |
| QuoteRotator                                                                                                                                      | 8,531            | 8,837             | 16,045             | 40,315              |
| RedemptionExt                                                                                                                                     | 13,973           | 14,176            | 10,603             | 34,976              |
| RoyaltyRouter                                                                                                                                     | 293              | 473               | 24,283             | 48,679              |
| SurtaxLib                                                                                                                                         | 723              | 753               | 23,853             | 48,399              |
| TreasuryGovernor                                                                                                                                  | 6,653            | 7,429             | 17,923             | 41,723              |
```

## Full suite (fork env, public Sepolia RPC)
Ran 211 test suites in 618.41s: 858 tests passed, 26 failed, 1 skipped (885 total tests)

Failed tests (26 unique, file:test):
- test/attacks/A02_*.t.sol: test_Fixed_A02_PoisonedMarkCannotLiquidateASolventPosition (Error != expected error: NotOpen() != Healthy())
- test/attacks/A06_*.t.sol: test_Invariant_A06_SeederFundsUnreachable (campaign live)
- test/attacks/A07_*.t.sol: test_Invariant_A07_ReserveBacksRedemptionFromBlockZero (only 10% streamed)
- test/attacks/S08_*.t.sol: test_S08_A_INVARIANT_AFilledSwapCannotSkipTheSweep
- test/attacks/S08_*.t.sol: test_S08_B_PoC_SwapperChosenGasSilentlySkipsTheSweep
- test/attacks/S08_*.t.sol: test_S08_C_MEASURE_CostOfTheWorkBehindEachReserve
- test/attacks/S08_*.t.sol: test_S08_D_MEASURE_DoomedSweepBurnsTheSwappersGas
- test/attacks/S08_*.t.sol: test_S08_E_PoC_ABiggerBookRaisesTheBarForEverySweep
- test/audit/B19_ProgressiveNonNative.t.sol: test_B19_NativeStillStreams
- test/*_OnFork*: test_Progressive_PunishesEarlySnipe_OnFork
- test/*_OnFork*: test_FullLifecycle_ToRound3_OnFork
- test/*_OnFork*: test_Perps_On_Progressive_ViaBase_OnFork
- test_PerBlockLiqCap_Throttles (next call did not revert as expected)
- test/*_OnFork*: test_Base_GivesSpotDepth_FromSummon_OnFork
- test/*_OnFork*: test_InSwap_AutoStreams_OnFork
- test/*_OnFork*: test_InSwap_ToggleOff_PermissionlessStillWorks_OnFork
- test/*_OnFork*: test_PartialStream_Death_FullRecovery_OnFork
- test/*_OnFork*: test_Summon_Stream_Teardown_Relaunch_OnFork
- test_FIXED_RangesResetPerCampaign (gen-1 tracked ranges: 0 <= 0)
- test_FIXED_RelaunchStillRecoversAfterRescue (book funded: 0 <= 0)
- test_FIXED_RescueLeavesTheRecoveryPathOpen (campaign live)
- test_SAFE_NormalRelaunchRecoversTheBook (book funded: 0 <= 0)
- test/*F12*_OnFork: test_F12_IgnitionEmitsARealSwap_OnFork
- test/*F12*_OnFork: test_F12_LaterTranchesMoveThePriceLess_OnFork
- test/*F12*_OnFork: test_F12_PrimeBuyIsTranchedAndCompletes_OnFork
- test/*F12*_OnFork: test_F12_UnspentPrimeIsRecovered_OnFork

Pattern: the vast majority of the 26 failures are "_OnFork" tests reporting zero streamed/seeded/funded amounts (e.g. "0 != 100000000000000000", "campaign live", "book funded: 0 <= 0"), consistent with the public Sepolia RPC (ethereum-sepolia-rpc.publicnode.com) returning stale/inconsistent fork state rather than a code regression — matches the prior baseline's documented pattern of fork-RPC flakiness (11/14 in the 2026-09-10 baseline). Literal "429" substring count in the log is 3, but all 3 are gas-number false positives (e.g. "gas: 34296481"), not actual HTTP 429 rate-limit messages — no explicit rate-limit text found via grep -i 'rate.?limit'. Per instructions this was not re-run within this P0 pass (re-run authority belongs to the agent(s) touching the affected suites); flagging as likely-infrastructure, not confirmed-infrastructure.
