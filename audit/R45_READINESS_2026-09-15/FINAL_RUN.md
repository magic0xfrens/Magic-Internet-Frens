# Cauldron round-45 — FINAL RUN (2026-09-15)

Fork env used: Sepolia fork via the Alchemy endpoint, FOUNDRY_PROFILE=cauldron, POOL_MANAGER/POSITION_MANAGER pinned per brief.

## A. Headline numbers

| | suites | passed | skipped | failed |
|---|---|---|---|---|
| P0 baseline | 244 | 969 | 1 | 2 |
| This run | 253 | 980 | 1 | 4 |

Suite count grew (253 vs 244) because new red-team test files exist on this branch (R1A/R1B/R1C, S08, S0x, etc.) — expected growth, not a regression.

## B. Failure table

| Test | File | Classification | Result |
|---|---|---|---|
| test_CHURN1_playWorksButChurnReverts | test/attacks/CHURN1_LiveRevert.t.sol | EXPECTED-LIVE-INCIDENT | asserts against live round-44 gacha router which genuinely lacks `playChurn`; expected until round 45 deploys |
| test_S06_POC_RealEngine_QueueingBeforeBadDebtShedsAllOfItOnLpB | test/attacks/S06_PerpVaultSolvency.t.sol | KNOWN BASELINE, unchanged | `344218925886143795 <= 459182015833333191` — exact match to the P0-recorded numbers |
| test_S08_B_PoC_SwapperChosenGasSilentlySkipsTheSweep | test/attacks/S08_InSwapGasStarvation.t.sol:230 | **NEW** | `assertFalse(killedTight, "PoC: the liquidation was SKIPPED at the tight cap")` fails — sweep is silently skipped at a swapper-chosen tight gas cap |
| test_S08_D_MEASURE_DoomedSweepBurnsTheSwappersGas | test/attacks/S08_InSwapGasStarvation.t.sol:339 | **NEW** | `assertFalse(cheapKilled, "no sweep at all below the gate")` fails — no sweep occurs below the gas gate |

Re-run of test/attacks/S08_InSwapGasStarvation.t.sol alone (fork env, `-vv`): same 2 failures, same messages, deterministic — confirmed NOT an infrastructure/429 artifact. No infrastructure-signature failures were observed anywhere in the run (no 429/520/"Max retries"/"database error"/HTTP-error/RPC-timeout strings in the log), so no re-runs were needed for infra reasons.

## C. Size table (key contracts; full table is `forge build --sizes` output, 1547 lines, not reproduced here)

| Contract | P0 bytes | Now | Delta | Free margin now |
|---|---|---|---|---|
| CauldronHook | 23,140 | 23,258 | +118 | 1,318 |
| PerpEngine.0.8.26 | 24,247 | 24,215 | -32 | 361 |
| PerpEngine.0.8.30 | 24,247 | 24,215 | -32 | 361 |
| PerpVault | 9,260 | 9,858 | +598 | 14,718 |
| GachaLib | 1,466 | 1,652 | +186 | 22,924 |
| PoolOps | 24,006 | 24,173 | +167 | 403 |
| CauldronRegistry | 24,492 | 24,492 | 0 | 84 |
| PerpSwapLib (cauldron/PerpSwapLib.sol) | 8,968 (0.8.30) / 8,978 (0.8.26) | 8,968 (single consolidated line) | 0 | 15,608 |

**EIP-170 verdict: no contract is at or over 24,576 B. PASS.**

Contracts with under 500 B free margin (flagged, none over the limit):
- CauldronRegistry: 84 B free
- PerpEngine (.26/.30): 361 B free
- PoolOps: 403 B free

Contracts that changed but were NOT in the brief's expected-to-change list ("surprises"):
- None among production contracts. All other diffs in the full table are new test-only mocks/harnesses added by this round's red-team suites (e.g. `R2Mock.sol` MockToken/MockRegistry/MockEngine, `StrandHook`, `StrandUSDG`, `ReserveStub`, `R3MockCol/R3DCol/R3CapCol`, `K3d_DeathBandProtectsForcedClose.t.sol:Harness` at 24,516/60B-margin (test-only, not deployed), and minor test-harness engine variants `X9cEngine`/`X3iEngine` -32B). None of these are shipped contracts.

## D. Skip-count verdict

P0: 1 skipped. Now: 1 skipped. **Skip count did NOT grow.** Fork env was present and effective (rotation/perp/relaunch/governance suites all executed, not silently skipped).

## E. PoC hygiene sweep (R1x/R2x/R3x/R4x)

`grep -n "return;\|vm.skip"` hits, all 6 are inside `setUp()` or internal binary-search helper functions, NOT inside a top-level `test_*` function body — acceptable pattern, no vacuous-pass defects:

- test/attacks/R1A_FreeKillSlack.t.sol:36 — in `setUp()`, guards `_bootPerp` on `active` flag
- test/attacks/R1A_FreeKillSlack.t.sol:76 — in an internal coarse-search helper, guards continuing the binary search
- test/attacks/R1A_FreeKillSlack.t.sol:91 — in the fine-search helper, returns once a kill point is found (recording state first)
- test/attacks/R1C_GasFloorBypass.t.sol:48 — in `setUp()`, same `active` guard
- test/attacks/R1C_GasFloorBypass.t.sol:102 — in an internal search helper, returns after recording result
- test/attacks/R1B_SweepWindowStarvation.t.sol:40 — in `setUp()`, same `active` guard

No R2/R3/R4-prefixed files matched (none exist under those globs besides the R2Mock.sol helper contract, which is not a test file).

## F. Deviations from brief

- None. Build, full suite, and hygiene sweep all completed as specified. One extra confirmatory re-run of S08 was performed (not required by the infra-retry rule since the failure messages carry no 429/520/RPC signature) purely to confirm determinism before classifying as NEW.

## Confirmation run (post-fix)

Commits confirmed: `beedf49` (PerpVault exit queue restructured units x index), `8a98a8b` (S08 tests inverted onto post-fix behaviour), `229d98b`/`e614101` (frontend only). Fork env: Sepolia fork via the Alchemy endpoint, same POOL_MANAGER/POSITION_MANAGER pins.

### A. Headline numbers

| | suites | passed | skipped | failed |
|---|---|---|---|---|
| P0 baseline | 244 | 969 | 1 | 2 |
| Intermediate run | 253 | 980 | 1 | 4 |
| **Confirmation run** | 254 | 985 | 1 | 3 (1 infra, cleared on re-run) |

**Skip count vs P0: 1 → 1. Did NOT grow.**

### B. Failure table

| Test | File | Classification | Result |
|---|---|---|---|
| test_CHURN1_playWorksButChurnReverts | test/attacks/CHURN1_LiveRevert.t.sol | EXPECTED-LIVE-INCIDENT | still fails, asserts against live r44 router lacking `playChurn` — expected |
| test_S06_POC_RealEngine_QueueingBeforeBadDebtShedsAllOfItOnLpB | test/attacks/S06_PerpVaultSolvency.t.sol | KNOWN BASELINE, unchanged | `344218925886143795 <= 459182015833333191` — **bit-identical** to P0 and to the intermediate run, now confirmed unchanged across three independent source changes (round-45 base, PerpVault restructure, S08 fix) |
| test_T02_POC_DustLegBurnsTheWholeMigrationMandate | test/attacks/T02_EnvelopeBurnedOnADustLeg.t.sol | INFRASTRUCTURE, cleared on re-run | full-suite run hit `EVM error; database error: ... error sending request for url (the Alchemy endpoint); operation timed out`; re-run of this file alone (fork env, `-vv`) PASSED cleanly (gas 4008611) — classic transient RPC failure, not a code regression |

**S08 pass confirmation:** `test_S08_B_PoC_SwapperChosenGasSilentlySkipsTheSweep` and `test_S08_D_MEASURE_DoomedSweepBurnsTheSwappersGas` do **not** appear in this run's failing-test list — both now PASS as expected post-`8a98a8b`.

**NEW failures: none.**

### C. Size table / EIP-170

| Contract | Bytes | Free margin |
|---|---|---|
| PerpVault | 11,280 | 13,296 |
| CauldronHook | 23,258 | 1,318 |
| CauldronRegistry | 24,492 | 84 |
| PerpEngine.0.8.26 / .0.8.30 | 24,215 | 361 each |
| PoolOps | 24,173 | 403 |
| GachaLib | 1,652 | 22,924 |

PerpVault grew to 11,280 B as expected from the exit-queue restructure. **No contract is at or over 24,576 B — EIP-170 PASS.** Under-500-B-free (same three as before, unchanged by this commit set): CauldronRegistry (84 B), PerpEngine .26/.30 (361 B each), PoolOps (403 B).

### D. Hygiene re-check

`grep -rn "vm.skip\|return;" test/attacks/NB_*.t.sol test/attacks/S08_*.t.sol`:
- `test/attacks/NB_SettleSpamHaircut.t.sol` — **no hits** (clean).
- `test/attacks/S08_InSwapGasStarvation.t.sol` — one `if (!active) return;` in `setUp()` (line 114), and five `vm.skip(!active);` lines (141, 222, 339, 402, 502), each the first statement inside its own `test_S08_*` body, immediately gating on fork availability before any assertions run. These are the pre-existing, deliberate fork-availability guards named in the brief — confirmed to be the only hits in this file, and confirmed non-vacuous since this run's real fork execution produced genuine PASS/FAIL results (not universal skips) for every one of these tests.

### E. Deviations from brief

None. One extra confirmatory re-run of T02_EnvelopeBurnedOnADustLeg.t.sol was performed per the infra-retry rule (failure message matched "database error" / RPC timeout signature) and cleared.
