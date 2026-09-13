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

## Root-cause bisect for the seeder regressions

Commit: `40b9608a6283c4aa51616900a1413c50ddb98b05` — "fix(pool): full range always — an exhaustible band is not a book"
Date: Sat Sep 12 20:06:48 2026 +0100
Files touched: `contracts/solidity/cauldron/PoolOps.sol` only (33 insertions/2 deletions) — no test files updated.

Full message:
```
`SEED_BASE_WAD` 15% -> 100%. The whole of ledger A is now laid as a two-sided
full-range base at summon, and the streamed campaign is not started when there
is nothing left to stream.

PoolOps' own comment already said this: "Perps belong on ATOMIC (full-range,
spot-straddling) generations — progressive is the launch-only anti-snipe
mechanic. A huge sell that walks past the bands teleporting toward the 69x
reserve is accepted BY DESIGN for spot trading." r42 ran perps on a progressive
generation, which is the combination that note warns against, and the 15% base
was far too thin to keep the book continuous.

Measured on r42: a 1 ETH buy into a 0.55 ETH pool moved price 39x. Constant
product caps that at ~8x — the extra came from walking past the last band into
empty space. Everything after followed from the gap: a 0.05 ETH short blew out
to -4.4 ETH; its notional then exceeded pool depth so `LiqCapped` made it
unliquidatable at ANY setting (verified by setting maxLiqBps to 100% on chain);
and the close path could not buy back 83M tokens the pool did not hold. The
owner's 1 ETH vault stake came back as 0.6 — stakers ate the bad debt.

A single-sided band is exhaustible by definition, so anything load-bearing for
perps, liquidations, the NFT floor and treasury rotation cannot sit on one. The
cost is capital efficiency (a full-range spread is thinner per tick); that is
the right trade here. Anti-snipe is unaffected — the surtax and LaunchSniper are
the real defences and both are untouched.

The streaming machinery is intact: lower the constant to bring it back.
```

Value before → after: `SEED_BASE_WAD = 0.15e18` → `SEED_BASE_WAD = 1e18` (PoolOps.sol line ~168).

`ProgressiveSeed.t.sol` results:
- At parent (`40b9608^`, 0.15e18): 6 passed, 0 failed, 0 skipped.
- At the commit itself (`40b9608`, 1e18): 1 passed, 5 failed, 0 skipped — `test_Base_GivesSpotDepth_FromSummon_OnFork`, `test_InSwap_AutoStreams_OnFork`, `test_InSwap_ToggleOff_PermissionlessStillWorks_OnFork`, `test_PartialStream_Death_FullRecovery_OnFork`, `test_Summon_Stream_Teardown_Relaunch_OnFork` all fail (streaming/floor assertions expect a partial 15% base, get the full 100% base instead). `test_WindowZero_IsAtomicGreenCandle_OnFork` still passes.
- At HEAD: could not run — unrelated pre-existing compile error (`RoyaltyRouter` constructor arg-count mismatch in `test/attacks/X1e_RoyaltyRouterRevertsOnErc20Quote.t.sol` and `test/attacks/Z9_ScopeProbe.t.sol`) blocks the whole build; out of scope for this bisect.

This is an intentional design change (only source touched, deliberate constant rename note "lower the constant to bring it back"), but the progressive-seed test suite was never updated to match the new full-range-always behavior, so it fails at and after this commit by design-vs-test mismatch, not by a code defect.
