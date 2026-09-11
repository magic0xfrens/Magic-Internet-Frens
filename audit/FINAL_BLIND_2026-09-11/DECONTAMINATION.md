# Decontamination — FINAL_BLIND_2026-09-11

## 1. Tree
- Source: `/Users/0x0010110/Documents/GitHub/Magic Internet Frens/contracts/solidity`
- Blind:  `/tmp/blind-final/contracts/solidity`
- rsync excluded: `audit/`, `broadcast/`, `.git`, `out/`, `cache/`, `lib/` (symlinked back), all `*.md`.
  Note: `--exclude audit/` and `--exclude broadcast/` are rsync patterns with no
  leading slash, so they match at ANY depth, not just the project root. This
  correctly dropped `contracts/solidity/audit/` (LaTeX/PDF audit-report sources
  and a `graph/` json dir — confirmed zero `.sol` files, correctly out of scope)
  but it ALSO silently dropped `contracts/solidity/test/audit/` before the
  explicit quarantine `mv` for that directory ever ran. See Deviations below.
- Symlinks: `$BLIND/lib -> $SOL/lib`; `/tmp/blind-final/compressed-traits -> $REPO/compressed-traits`;
  `/tmp/blind-final/node_modules -> $REPO/node_modules`.

## 2. Quarantined
- `test/attacks/` → `/tmp/blind-quarantine/test/attacks/` (44 files):
  A01_Create2Squat.t.sol, A02_PerpAttacks.t.sol, A05_ReserveFloorSeeder.t.sol,
  B01_StrandedPerpGuildDividend.t.sol, B02_DividendGasBudgetOverrun.t.sol,
  B03_SurtaxJitterDeadCode.t.sol, B04_ArbNotionalCap.t.sol, B05_NonEthRelaunchBrick.t.sol,
  B06_ProposerOwedDenomination.t.sol, B07_RelaunchTotality.t.sol, B08_NonEthRebirth.t.sol,
  Q01_StrandedGuildDividend.t.sol, Q02_GachaOddsUnitMismatch.t.sol, Q07_WeightedMark.t.sol,
  S01_PerpQuoteDeadlock.t.sol, S02_RotationSurface.t.sol, S04_GovernanceScanDoS.t.sol,
  S06_PerpVaultSolvency.t.sol, S08_InSwapGasStarvation.t.sol, S09_ArbStepGovernance.t.sol,
  T01_PoolKeySquatRegression.t.sol, T02_EnvelopeBurnedOnADustLeg.t.sol, T02_MarkSourceUnarmed.t.sol,
  T02_OracleCacheStaleness.t.sol, T02_PartialFlipStrandsThePrimary.t.sol, T02_PerpAfterRotation.t.sol,
  T02_RotationDestinationSquat.t.sol, T02_StaleFloorSandwich.t.sol, T03_InventoryWipe.t.sol,
  T03_RelaunchSurvivorBrick.t.sol, T03_VaultQueueSeniority.t.sol, T07_LegProceedsUnreachable.t.sol,
  T08_GovernorQuorumWiring.t.sol, Y01_ReserveCeilingBreach.t.sol, Y02_DepthManip.t.sol,
  Y03_RelaunchGasBrick.t.sol, YBase.sol, Z01_ExactOutSellFeeBypass.t.sol, Z02_PerpStaleMark.t.sol,
  Z03_GovernorSpamRelaunchDoS.t.sol, Z04_SeederRescueStrandsLp.t.sol, Z05_L2BlockClock.t.sol,
  Z06_GovernanceLockout.t.sol, ZAuditBase.sol
- `test/audit/` → `/tmp/blind-quarantine/test/audit/` (21 files):
  AuditPoC.t.sol, AuditPoC2.t.sol, AuditPoC3.t.sol, AuditPoC4.t.sol,
  AuditPoC5_DividendBasket.t.sol, AuditPoC6_QuoteReserve.t.sol, AuditPoC7_StaleOracleDeath.t.sol,
  B09_ProposalPayloadGasBrick.t.sol, B10_ScanWindowErasure.t.sol, B11_OracleRevertBypassesCache.t.sol,
  B12_RotatorVenueUnvalidated.t.sol, B13_SeedFundingDustPreference.t.sol, B14_FastFullRotation.t.sol,
  B15_RotationWiringUnreachable.t.sol, B16_FeatureReachability.t.sol, B17_TreasuryScanBound.t.sol,
  B18_StaleRecastForfeitsBasket.t.sol, B19_ProgressiveNonNative.t.sol, B20_SelfCheckScanWindow.t.sol,
  B21_GovTimingFloors.t.sol, ReserveBoundProbe.t.sol
  (This directory had to be restored by direct copy from the source tree — rsync's
  unanchored exclude had already removed it before the `mv` could act on it. End
  state is identical to what the brief specifies: absent from BLIND, present in QUAR.)
- `test/F1[0-9]_*.t.sol` (root-level, finding-tagged names) → `/tmp/blind-quarantine/test/root/` (4 files):
  F12_IgniteEconomics.t.sol, F13_MintCurve.t.sol, F14_OracleSafety.t.sol, F15_QuotePriceability.t.sol
- Kept as-is: test/final, test/functional, test/invariants, and all other root-level test/*.t.sol files.

## 3. Stripped
Pass 1 (whole blind tree, immediately after rsync+quarantine): files changed 57,
substitutions 396. Full tag frequency table:
  Z-05 14, B-05 12, F-19 11, Q-02 10, L-2 9, H-03 9, H-01 9, C-01 8, P-1 7, R-1 7,
  R-07 7, F-13 7, C-02 7, R-05 7, F-09 7, U-1 6, R-04 6, M-03 6, L-3 6, F-03 5,
  Q-01 5, A-01 5, F04 5, M-02 5, F-05 5, D-1 5, L-1 5, M-01 4, V-1 4, Z-06 4,
  R-02 4, F-02 4, D-3 4, M-06 4, R-08 4, F-10 4, L-4 4, Z-01 3, G-09 3, L-02 3,
  B-03 3, R-03 3, Z-07 3, Z-12 3, L-01 3, D-2 3, A-03 3, A-02 3, G-03 3, Q-07 3,
  H-05 3, R-01 3, I-01 2, L-03 2, B-06 2, F1 2, F-20 2, I-03 2, V1 2, Z-03 2,
  B-02 2, F13 2, H-04 2, G-02 2, V-01 2, L-06 2, F-04 2, R-09 2, M-05 2, V-02 2,
  S-04 2, P2 2, F02 2, S-1 2, F-18 2, I-6 2, F-1 2, F-2 2, F-3 2, V-2 2, V-3 2,
  V-4 2, G-10 1, G-1 1, Z-09 1, I1 1, L-04 1, I-02 1, I-07 1, M-04 1, Z-08 1,
  L-08 1, F-06 1, A-05 1, H-02 1, Z-04 1, L-07 1, Z-17 1, G-01 1, G-07 1, Q-03 1,
  G-06 1, L-05 1, Z-02 1, I-06 1, A-04 1, G-05 1, F-08 1, F-07 1, B-15 1, Y-01 1,
  P0 1, B-10 1, F12 1, F-12 1, F3 1, I-08 1, F01 1, F-01 1, F03 1, C-1 1, B-12 1,
  F-11 1, F-21 1, F-22 1, I-1 1, I-2 1, I-3 1, I-4 1, I-5 1, I-7 1, R-2 1, R-3 1,
  I-05 1, R-4 1, S-2 1, S-3 1, S-4 1

Pass 2 (after Deviation #2 below restored test/attacks/YBase.sol into the blind
tree so the kept test/functional/F10 and F11 could still compile): files changed 1,
substitutions 3 — Z-10 x1, Y-01 x1, H-1 x1. Total across both passes: 58 files
changed, 399 substitutions.

### Five before/after examples (distinct tags, `strip-log.json`)
- tag P-1 — CauldronHook.sol:47
  REAL:  `///         one while anyone is exposed (audit P-1).`
  BLIND: `/// one while anyone is exposed (audit).`
- tag R-1 — CauldronHook.sol:129
  REAL:  `///      reserve (audit R-1) under EIP-170.`
  BLIND: `/// reserve (audit) under EIP-170.`
- tag Z-01 — CauldronHook.sol:142
  REAL:  `/// @dev The one swap quadrant the hook cannot charge an ETH fee on (audit Z-01).`
  BLIND: `/// @dev The one swap quadrant the hook cannot charge an ETH fee on (audit).`
- tag L-2 — CauldronHook.sol:157
  REAL:  `//  ── SIZED FROM A MEASURED KILL, NOT A GUESS (red-team L-2) ─────────────`
  BLIND: `// ── SIZED FROM A MEASURED KILL, NOT A GUESS (red-team) ─────────────`
- tag Z-05 — CauldronHook.sol:174
  REAL:  `// ── VOLUME WINDOW CLOCK (audit Z-05 — High, L2) ─────────────────────────────`
  BLIND: `// ── VOLUME WINDOW CLOCK (audit — High, L2) ─────────────────────────────`

## 4. Verification
RESULT: PASS (re-run after Pass 2 / YBase.sol restoration; final numbers below)

Line counts: .sol files in real tree: 181; in blind tree: 113; files with
differing line counts: 0; files only in real tree (quarantined/excluded): 68
(the 44 test/attacks + 21 test/audit + 4 root F1x listed above minus YBase.sol,
which was restored, plus a couple of path variants — see DECONTAMINATION_VERIFY.md
for the itemized 68-file list).

Hyphenated finding-shaped hits in comments/prose (must be 0): 0.

Hyphenated hits inside code or string literals (residual leak, not stripped): 46.
These are all assertion-message string literals in test/invariants/*.t.sol
(tags V-1..V-4, F-1, F-3, L-1..L-4, I-1, I-3..I-7, R-1..R-4, S-1..S-4, C-01) plus
one in deploy/DeployLaunchpad.s.sol ("EMERGENCY_DELAY must be > 0 (audit F-19)").
The tool intentionally does not touch string literals used as live assertion
messages (rewriting them risks changing test semantics/behavior), only comments.

Hyphenless letter+digit tokens remaining (residual, classify each): 17 — all
false positives from SVG path-command data in render-out/art-short.txt and
render-out/art-long.txt (`M0` x6, `M86` x4, `M98` x2, `M87` x2, `M94` x2, `M88` x1
— these are SVG "moveto" path commands, e.g. `M0 0h1024v775H0z`, not finding tags).

File names carrying a letter+digit prefix (residual leak, cannot be renamed
without breaking citations): 0.

sizes identical: yes. All 469 contract rows present in both the real and blind
`forge build --sizes` tables are byte-identical (0 differ), including every one
of the 26 named protocol contracts plus PositionDescriptor. The 149 rows unique
to the real table are quarantined test/mock/stub contracts and lib name-collision
duplicates that disappear from disambiguated naming once their quarantined twin
is gone (e.g. `FVotes (test/functional/F10_QuoteRotationTotality.t.sol)` in real
becomes plain `FVotes` in blind once the same-named `test/attacks/T02_...` copy
is quarantined away) — not a decontamination defect.

## 5. Residual leak
Perfect blinding is impossible. Comments that describe history ("the old
routine never did that work", "previously this reverted") still signal prior
review; variable and function names chosen during remediation (for example
flags whose name encodes a past incident) still signal a threat; test file
names in test/final and test/functional carry numbered prefixes that hint at
prior audit structure; the sizes table shows several contracts within tens of
bytes of EIP-170, which signals that code was forced into other files; and the
orchestrator's own auto-memory names prior findings (the orchestrator does not
hunt, and hunters are instructed to ignore it). None of these could be removed
without changing line numbers or code.

Additional deviations found while building this blind tree, beyond the residual
leak above:
1. `test/functional/F10_QuoteRotationTotality.t.sol` and `F11_FloorsAndRedemption.t.sol`
   (both explicitly kept per the brief) import `../attacks/YBase.sol`, a shared
   fork-test harness that lived inside the wholesale-quarantined `test/attacks/`
   directory. A blind tree with `test/attacks/` fully removed fails to compile.
   Fix: `YBase.sol` alone was copied back into `$BLIND/test/attacks/YBase.sol`
   and run through the same `decontaminate.py strip` pass (removed tags Z-10,
   Y-01, H-1 — see Pass 2 above) rather than left quarantined-and-missing.
2. The rsync `--exclude audit/` / `--exclude broadcast/` patterns are unanchored
   and match at any tree depth (documented in section 1); `test/audit/` had to
   be restored by direct copy from the source tree into quarantine rather than
   via the brief's literal `mv $BLIND/test/audit ...`, because rsync had already
   removed it. End state matches the brief's intent exactly.
3. `lib/v4-periphery/lib/permit2/script/DeployPermit2.s.sol` (a vendored,
   unused-by-us deploy script) does `import {Permit2} from "src/Permit2.sol"`,
   an unqualified self-import that only resolves under Foundry's context-scoped
   remapping when the file's canonical path is inside the compiling project's
   root. Because `$BLIND/lib` is a symlink to a directory outside `/tmp/blind-final`
   (as the brief specifies), the file's real path escapes the blind project root
   and the import fails to resolve — on a byte-for-byte identical real tree this
   is masked only because its build cache was already warm (`out/DeployPermit2.s.sol`
   exists from a prior full build) and `forge build --sizes` reported
   "No files changed, compilation skipped" rather than recompiling from clean.
   Nothing outside `lib/` imports this file or its callers (`PosmTestSetup.sol`,
   `PermissionedPosmTestSetup.sol`, `PermissionedRoutingTestHelpers.sol` — all
   v4-periphery's own internal test helpers). Worked around with the `forge`
   CLI flag `--skip "DeployPermit2"` on both the blind `forge build --sizes`
   and the blind sanity `forge test` — no file was edited, real or blind.
