# Full offline regression checkpoint

Command: `FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --summary`.

## Current 2026-09-19 run

Command: `FOUNDRY_PROFILE=cauldron forge test --offline --threads 1`.

The fresh production-profile run compiled 84 Solidity files with 0.8.30 and 5
with 0.8.26, then completed with **803 succeeded / 35 failed** (exit 1).
Failures were retained by Foundry and are not suppressed. The majority require
`FORK_RPC`/PoolManager/PositionManager state and therefore cannot be certified
in this offline invocation; local adapters for those lifecycle paths passed.
`V2A_VoteFarm` failed in its inactive fork setup before reaching its assertions,
so it is a coverage prerequisite issue, not evidence of a production exploit.
The bounded fork lane is recorded in `VERIFICATION.md` (12/12 passed).

## Second rerun (latest completed full run)

Observed exit 1: **758 passed, 36 failed**. Includes the deployment-feed edge cases,
PerpVault repeated-write-off correction and local lifecycle adapters. Predates
`UnifiedVaultDonation.t.sol` and its remediation. The same 35 original failures
listed below remain, plus this executed local failure:

```text
Encountered 1 failing test in test/audit_full_scope/LocalLifecycleAdapters.t.sol:LocalD04RebookTest
[FAIL: control: the band-refused buy-back must rebook the position] test_D04_RebookedPositionStillOwesFundingAndPenalty() (gas: 124354918)
Encountered a total of 36 failing tests, 758 tests succeeded
```

The local D04 trace closes the position during hook preemption before reaching
the intended partial-rebook path; see `LOCAL_LIFECYCLE_RESULTS.md`. This is not a
passing regression or proof that partial close is safe. The separate narrower
production-engine partial-close regression passes with fixture hook dependencies.

## First rerun (historical)

Observed exit 1. 276 suites; 735 passed, 35 failed, 276 skipped (1046 total).

This run includes the first five production patches and the four ROT-02 lifecycle regressions. It predates the new QuotePreflightEdges and PerpVaultRepeatedWriteoff tests and any subsequent fixes. Compared with the baseline, HOOK-01's decimal regression no longer fails. No full-scope green result is claimed.

Explicit no-fork prerequisite failures are infrastructure/coverage gaps. Generic EvmError failures in YBase-derived suites require trace confirmation; source inspection shows YBase._boot returns before initialization when FORK_RPC is missing, but that fact alone is not a passing security test. Tests that silently return because active is false are not credited as executed coverage.

The run also executed local invariants at 256 runs × 500 calls (128,000 calls each), including consent, legacy sweep, and ledger invariants. These do not cover skipped fork-dependent system invariants.

## Exact failing-test output

```text
Failing tests:
Encountered 1 failing test in test/attacks/D04_RebookErasesFundingAndPenalty.t.sol:D04_RebookErasesFundingAndPenalty
[FAIL: fork must be live for this regression] test_D04_RebookedPositionStillOwesFundingAndPenalty() (gas: 6868)

Encountered 2 failing tests in test/attacks/E1B_LiqDrainScale.t.sol:E1B_LiqDrainScale
[FAIL: fork must be live for this regression] test_scale_push_1eth() (gas: 6376)
[FAIL: fork must be live for this regression] test_scale_push_3eth() (gas: 6420)

Encountered 1 failing test in test/attacks/K5b_ProgressiveSeederUnreachable.t.sol:K5b_ProgressiveSeederUnreachable
[FAIL: FORK_RPC/POOL_MANAGER/POSITION_MANAGER must be exported] test_K5b_ProgressiveSeedNeverStarts_AndPrimeFundingIsLocked() (gas: 2478)

Encountered 5 failing tests in test/attacks/LIQ02_PreemptiveProjection.t.sol:LIQ02_PreemptiveProjection
[FAIL: EvmError: Revert] test_LIQ02_BuyProjectionIsAnUpperBoundOnTheRealMove() (gas: 5342)
[FAIL: EvmError: Revert] test_LIQ02_DegenerateInputsFallBackToSpot() (gas: 5240)
[FAIL: EvmError: Revert] test_LIQ02_ExactOutputProjectionIsAlsoABound() (gas: 5302)
[FAIL: EvmError: Revert] test_LIQ02_SellProjectionIsABoundOnTheRealMove() (gas: 5484)
[FAIL: EvmError: Revert] test_LIQ02_TheSafetyMarginIsApplied() (gas: 5347)

Encountered 1 failing test in test/attacks/LIQ03_PreemptiveLiquidation.t.sol:LIQ03_PreemptiveLiquidation
[FAIL: EvmError: Revert] setUp() (gas: 0)

Encountered 1 failing test in test/attacks/LIQ04_CascadeStaleProjection.t.sol:LIQ04_CascadeStaleProjection
[FAIL: EvmError: Revert] setUp() (gas: 0)

Encountered 1 failing test in test/attacks/LIQ04_ExactOutBypass.t.sol:LIQ04_ExactOutBypass
[FAIL: EvmError: Revert] setUp() (gas: 0)

Encountered 1 failing test in test/attacks/LIQ04_GasStarve.t.sol:LIQ04_GasStarve
[FAIL: EvmError: Revert] setUp() (gas: 0)

Encountered 1 failing test in test/attacks/LIQ04_PrematureKill.t.sol:LIQ04_PrematureKill
[FAIL: EvmError: Revert] setUp() (gas: 0)

Encountered 1 failing test in test/attacks/LIQ05_CascadeLossMechanism.t.sol:LIQ05_CascadeLossMechanism
[FAIL: EvmError: Revert] setUp() (gas: 0)

Encountered 1 failing test in test/attacks/LIQ05_PrematureKillEconomics.t.sol:LIQ05_PrematureKillEconomics
[FAIL: EvmError: Revert] setUp() (gas: 0)

Encountered 1 failing test in test/attacks/LIQ05_ProjectionOvershoot.t.sol:LIQ05_ProjectionOvershoot
[FAIL: EvmError: Revert] setUp() (gas: 0)

Encountered 1 failing test in test/attacks/M1a_LiqGasBand.t.sol:M1a_LiqGasBand
[FAIL: fork must be live for this regression] test_gate_affords_only_one_kill_strands_the_rest() (gas: 6904)

Encountered 1 failing test in test/attacks/M3B_ExpiredCrystalForfeit.t.sol:M3B_ExpiredCrystalForfeit
[FAIL: fork inactive: FORK_RPC unset] test_M3B_two_missed_windows_destroy_a_paid_crystal() (gas: 20371)

Encountered 1 failing test in test/attacks/M4A_RelaunchSeam.t.sol:M4A_RelaunchSeam
[FAIL: fork harness must be live] test_relaunch_liveness_positive_control() (gas: 5686)

Encountered 1 failing test in test/attacks/M4B_RelaunchWhale.t.sol:M4B_RelaunchWhale
[FAIL: fork harness must be live] test_whale_cannot_break_relaunch_or_exit() (gas: 5840)

Encountered 1 failing test in test/attacks/M4C_QuoteComeHome.t.sol:M4C_QuoteComeHome
[FAIL: fork harness must be live] test_launch_quote_can_never_be_restored() (gas: 5642)

Encountered 1 failing test in test/attacks/R1A_FreeKillSlack.t.sol:R1A_FreeKillSlack
[FAIL: fork not active - PoC proved nothing] test_R1A_free_kill_inside_the_projection_slack() (gas: 21032)

Encountered 2 failing tests in test/attacks/R1B_SweepWindowStarvation.t.sol:R1B_SweepWindowStarvation
[FAIL: fork not active - PoC proved nothing] test_R1B_padded_book_strands_an_insolvent_position() (gas: 14878)
[FAIL: fork not active] test_R1B_positive_short_book_is_preempted() (gas: 13413)

Encountered 2 failing tests in test/attacks/R1C_GasFloorBypass.t.sol:R1C_GasFloorBypass
[FAIL: fork not active - PoC proved nothing] test_R1C_gas_capped_swap_skips_both_sweeps() (gas: 18156)
[FAIL: fork not active] test_R1C_positive_uncapped_gas_preempts() (gas: 11206)

Encountered 1 failing test in test/attacks/R2D_RotationPrimaryDerivation.t.sol:R2D_RotationPrimaryDerivation
[FAIL: fork harness must be live] test_R2D_roundTripMisclassifiesThePositionHoldingTheTreasury() (gas: 5819)

Encountered 1 failing test in test/attacks/RH2A_BookPadGasFloor.t.sol:RH2A_BookPadGasFloor
[FAIL: fork harness did not boot (FORK_RPC unset?)] test_RH2A_bookPadding_raises_the_gas_floor_of_every_swap() (gas: 9167)

Encountered 1 failing test in test/attacks/S0x_ForceCloseGasWedge.t.sol:S0xForceCloseGasWedge
[FAIL: vm.envString: environment variable "FORK_RPC" not found] setUp() (gas: 0)

Encountered 4 failing tests in test/attacks/S0x_RotationPerpHostage.t.sol:S0x_RotationPerpHostage
[FAIL: fork harness must be live (FORK_RPC)] test_S0x_DustPerpPositionHoldsTheApprovedRotationHostage() (gas: 5572)
[FAIL: fork harness must be live (FORK_RPC)] test_S0x_FIXED_WeightedMarkLetsTheApprovedRotationProceed() (gas: 5749)
[FAIL: fork harness must be live (FORK_RPC)] test_S0x_LIVENESS_RotationCompletesWithAnEmptyPerpBook() (gas: 5661)
[FAIL: fork harness must be live (FORK_RPC)] test_S0x_RotatedLegDeathReadIsOneSided() (gas: 5793)

Encountered 1 failing test in test/attacks/V2A_VoteFarm.t.sol:V2A_VoteFarm
[FAIL: EvmError: Revert] test_V2A_selfLiquidationFarmsVotes() (gas: 5854)

Encountered a total of 35 failing tests, 735 tests succeeded

Tip: Run `forge test --rerun` to retry only the 35 failed tests
```

Next: reproduce suitable scenarios with explicitly local production V4 managers, preserving the original test assertions. Local-manager runs must not be described as fork or deployment parity.
