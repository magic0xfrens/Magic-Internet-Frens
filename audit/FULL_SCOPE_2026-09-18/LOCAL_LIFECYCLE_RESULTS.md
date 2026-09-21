# Additional local lifecycle evidence

These are local production-V4 integrations, not forks or deployed-state parity. Original inherited assertions are unchanged.

## Liquidation-edge and vault/zap follow-up

Command: `FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-contract 'UnifiedVaultDonationTest|^VaultTest$|Z2VaultDonationEntitlement|LocalCascadeProjectionTest|LocalExactOutputPreemptionTest|LocalLiquidationGasTest|LocalCascadeLossTest|NativeQuoteZapLocalTest' -vv`

**22 passed, 1 failed, 0 skipped** across eight suites. Eight NFT-01 cases and six
legacy controls pass. Four zap tests pass (256 fuzz cases). Three cascade tests
and one exact-output preemption test pass. The loaded fixtures actually retain
four shorts, not eight: opening later shorts already causes earlier settlement.
Do not describe this as an eight-simultaneous-position cascade.

The unchanged gas-ladder test fails its <=4x expectation: clean book succeeds at
400,000 gas, while the four-position book first succeeds at 3,000,000. Lower
loaded caps revert; all higher tested caps succeed and clear the book. No
non-monotonic failure is observed. This is a verified gas-budget/route limitation,
not demonstrated theft or a reason to remove the fail-loud safety guard. Its
severity, fixed-cap router compatibility and relationship to existing documented
tradeoffs remain under review; the assertion is not weakened or hidden.

## Earlier local lifecycle run

Command: `FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-contract 'Local(D04|LIQ02|LIQ03|M4A|M4B)|PerpVaultRepeatedWriteoffTest' -vv`

Latest result: **14 passed, 1 failed, 0 skipped** across six suites. The vault fuzz test reports 257 runs, including the replayed counterexample. Compilation: two changed test files, 30.59 seconds.

| Suite | Result / exercised property |
|---|---|
| LocalLIQ02ProjectionTest | 5 passed: exact-input buy/sell and exact-output price bounds, margin and degenerate inputs |
| LocalLIQ03LiquidationTest | 3 passed: preemptive liquidation precedes the triggering swap, no bad debt/PLV loss, tight-limit grief control, actual large-fill positive control |
| LocalM4ARelaunchTest | 1 passed: two relaunches reach generation 3 with reserve position |
| LocalM4BWhaleTest | 1 passed: 500 ETH buy, relaunch, burn migration preserves token exit within 96 raw-unit rounding |
| PerpVaultRepeatedWriteoffTest | 4 passed: two-write-off accounting/claims, healthy control, repeated 2–8 cycles, bounded rounding, zero-claim revert control, both claim orders and per-claim conservation |
| LocalD04RebookTest | Failed fixture precondition: expected partial rebook is not reached |

## D04 counterargument, not a hidden pass

The unchanged owner-authored D04 test assumes the 10 ETH buy reaches partial close. Trace shows the current full hook instead executes preemptive `sweepLiquidations`, emits `Liquidated` with penalty 0.0321195 ETH and `Closed` with trader payout 0.351496353509564877 ETH before the swap completes. The partial-close assertion therefore fails because this concrete full-hook sequence closes the position completely. This does not refute the isolated `_rebook` defect, nor replace the passing XL1-based partial-close/funding test; it means this old scenario does not prove its advertised partial-close property on current code. The owner’s original file was not altered.

## Fixture and rounding corrections

The initial local managers lacked the unrelated native inventory present in the shared fork PoolManager. Before input settlement, the hook takes the nominal buy fee; large 500/1,000 ETH test inputs ran out of manager cash. The adapter explicitly supplies 10,000 ETH ambient manager inventory, without modifying protocol reserve counters. Empty-manager large-input liveness is **not** established by these tests and remains a separate integration assumption. The original un-funded failure was traced to `PoolManager.take -> hook.receive: OutOfFunds`, not concealed as an assertion pass.

Vault fuzzing initially used a fixed 1-gwei tolerance, but virtual shares are scaled by 1e6 while reward precision is 1e18. The regression now derives the flooring tolerance from `tokShares / 1e18 + 4`. Dust rewards may produce a zero entitlement; that branch explicitly asserts `ZeroAmount` and unchanged balances/pot. No silent early return or skipped case was introduced. Aggregate claim conservation remains asserted.
