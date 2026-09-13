# P0 Baseline Failure Classification (26 failures, snapshot a19550e)

Fork re-run: `/tmp/blind13-onfork-rerun.log` — all 12 OnFork failures reproduced identically
(same message, same value on both `--match-test 'OnFork'` and full-suite runs). No RPC 429s
observed; 54 other fork tests (including OnFork suites like WindowZero, QuoteOracleFork,
RotationRoundTrip, RotatorSwapFork, VolumeUnits) passed cleanly, so the fork env/RPC/round.json
addresses are not the cause — this is deterministic, not infra flake.

| test | file | bucket | reason (1 line) | classification |
|---|---|---|---|---|
| test_Fixed_A02_PoisonedMarkCannotLiquidateASolventPosition | test/attacks/A02_PerpAttacks.t.sol | attacks | `Error != expected error: NotOpen() != Healthy()` | REGRESSION-CANDIDATE |
| test_Invariant_A06_SeederFundsUnreachable | test/attacks/A05_ReserveFloorSeeder.t.sol | attacks | `campaign live` (seeder.seeding() false, precondition) | REGRESSION-CANDIDATE |
| test_Invariant_A07_ReserveBacksRedemptionFromBlockZero | test/attacks/A05_ReserveFloorSeeder.t.sol | attacks | `only 10% streamed: 0 != 100000000000000000` | REGRESSION-CANDIDATE |
| test_S08_A_INVARIANT_AFilledSwapCannotSkipTheSweep | test/attacks/S08_InSwapGasStarvation.t.sol | attacks | `positive control: the victim IS liquidatable` (precondition false) | REGRESSION-CANDIDATE |
| test_S08_B_PoC_SwapperChosenGasSilentlySkipsTheSweep | test/attacks/S08_InSwapGasStarvation.t.sol | attacks | `the victim is underwater at the mark` (precondition false) | REGRESSION-CANDIDATE |
| test_S08_C_MEASURE_CostOfTheWorkBehindEachReserve | test/attacks/S08_InSwapGasStarvation.t.sol | attacks | `the sweep costs more than the reserve kept behind it: 5912 <= 180000` | REGRESSION-CANDIDATE |
| test_S08_D_MEASURE_DoomedSweepBurnsTheSwappersGas | test/attacks/S08_InSwapGasStarvation.t.sol | attacks | `no sweep at all below the gate` | REGRESSION-CANDIDATE |
| test_S08_E_PoC_ABiggerBookRaisesTheBarForEverySweep | test/attacks/S08_InSwapGasStarvation.t.sol | attacks | `four positions on the book: 0 != 4` | REGRESSION-CANDIDATE |
| test_B19_NativeStillStreams | test/audit/B19_ProgressiveNonNative.t.sol | audit | `a native rebirth must still hand off to the seeder` (seeding() false) | REGRESSION-CANDIDATE |
| test_PerBlockLiqCap_Throttles | test/PerpEngine.t.sol | other (unit) | `next call did not revert as expected` (expectRevert LiqCapped not hit) | REGRESSION-CANDIDATE |
| test_FIXED_RangesResetPerCampaign | test/attacks/Z04_SeederRescueStrandsLp.t.sol | attacks (regression test, name FIXED_) | `gen-1 tracked ranges: 0 <= 0` | REGRESSION-CANDIDATE |
| test_FIXED_RelaunchStillRecoversAfterRescue | test/attacks/Z04_SeederRescueStrandsLp.t.sol | attacks (regression test) | `book funded: 0 <= 0` | REGRESSION-CANDIDATE |
| test_FIXED_RescueLeavesTheRecoveryPathOpen | test/attacks/Z04_SeederRescueStrandsLp.t.sol | attacks (regression test) | `campaign live` (seeder.seeding() false) | REGRESSION-CANDIDATE |
| test_SAFE_NormalRelaunchRecoversTheBook | test/attacks/Z04_SeederRescueStrandsLp.t.sol | attacks (regression test, name SAFE_) | `book funded: 0 <= 0` | REGRESSION-CANDIDATE |
| test_Progressive_PunishesEarlySnipe_OnFork | test/LaunchSnipe.t.sol | final/fork | `fully seeded: 0 != 1000000000000000000` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_FullLifecycle_ToRound3_OnFork | test/LifecycleE2E.t.sol | final/fork | `seeder armed` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_Perps_On_Progressive_ViaBase_OnFork | test/LifecycleE2E.t.sol | final/fork | `streamed` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_Base_GivesSpotDepth_FromSummon_OnFork | test/ProgressiveSeed.t.sol | final/fork | `fully streamed` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_InSwap_AutoStreams_OnFork | test/ProgressiveSeed.t.sol | final/fork | `floor at t0: 0 != 100000000000000000` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_InSwap_ToggleOff_PermissionlessStillWorks_OnFork | test/ProgressiveSeed.t.sol | final/fork | `no in-swap streaming when the hook pointer is cleared: 0 != 100000000000000000` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_PartialStream_Death_FullRecovery_OnFork | test/ProgressiveSeed.t.sol | final/fork | `streamed past the floor: 0 <= 100000000000000000` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_Summon_Stream_Teardown_Relaunch_OnFork | test/ProgressiveSeed.t.sol | final/fork | `seeder armed` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_F12_IgnitionEmitsARealSwap_OnFork | test/F12_IgniteEconomics.t.sol | final/fork | `stream armed for the remainder` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_F12_LaterTranchesMoveThePriceLess_OnFork | test/F12_IgniteEconomics.t.sol | final/fork | `a later tranche must move price less than an early one: 0 >= 0` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_F12_PrimeBuyIsTranchedAndCompletes_OnFork | test/F12_IgniteEconomics.t.sol | final/fork | `budget spent in full by completion: 0 != 200000000000000000` (reproduces on re-run) | REGRESSION-CANDIDATE |
| test_F12_UnspentPrimeIsRecovered_OnFork | test/F12_IgniteEconomics.t.sol | final/fork | `EvmError: Revert` (reproduces on re-run) | REGRESSION-CANDIDATE |

## Summary

- REGRESSION-CANDIDATE: 26
- PRIOR-POC-NO-LONGER-LANDS: 0
- FORK-INFRA: 0
- UNKNOWN: 0

## Notes

All 26 failures share one dominant symptom across otherwise-unrelated test files: values that
should reflect an armed/seeding/streaming Progressive Seeder or a triggered PerpEngine liquidation
condition come back as `0`/`false` where a nonzero/`true` positive-control value is expected
(`seeder.seeding()` false, `seeder.deployedWad()` stuck at 0, `perp.isLiquidatable()` false,
tranche spend stuck at 0). This is consistent with one shared regression in the Progressive Seeder
/ PerpEngine mark-price wiring reached by `setUp()` or a shared helper, rather than 26 independent
issues, and rather than PoCs "failing by design" (those would fail on the attack succeeding, not on
a positive-control precondition). The 12 `_OnFork` tests reproduced byte-identically on an isolated
`--match-test 'OnFork'' re-run with fresh fork state (round.json chainId 11155111 matches
POOL_MANAGER/POSITION_MANAGER Sepolia addresses used), ruling out RPC flakiness or stale-fork-state
as the cause — treated as REGRESSION-CANDIDATE rather than FORK-INFRA.
