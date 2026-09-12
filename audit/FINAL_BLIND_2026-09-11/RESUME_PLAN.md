# Resume plan — deploy the full stack to Sepolia and wire the off-chain side

Written 2026-09-11 at the end of a long session. Everything below is executable; nothing
here is a guess. Branch `redteam/2026-09-11`, ~60 fix commits, nothing pushed.

**To resume, one instruction is enough:** "follow audit/FINAL_BLIND_2026-09-11/RESUME_PLAN.md".

**The whole thing is now automated in `scripts/auto-deploy.sh`:**
```
./scripts/auto-deploy.sh --check    # run the gates, deploy nothing (safe, default)
./scripts/auto-deploy.sh --go       # gates, then deploy + wire if they pass
```
It verifies the signer derives the right address, checks the balance is sufficient, requires a clean
build with every contract under EIP-170, runs the full suite and **compares failures against the
13 known-baseline ones by name**, requires this run's 65 regression tests to be perfect, blocks if the
skip count grew, then runs `go-testnet.sh` (arm-if-needed → deploy → mint out → finalize → fold the
manifest), regenerates ABIs from compiled artifacts, type-checks and builds the frontend, and
verifies post-deploy invariants. It bridges the key from `.env.recovery` into the file the existing
scripts expect and deletes that bridge on exit, including on failure or Ctrl-C.

### DEPLOY ATTEMPT 2026-09-12 — GATE 2 REFUSED, one file to classify

`./scripts/auto-deploy.sh --go` ran. GATE 0 (signer, 12.4757 ETH) and GATE 1 (build, nothing over
EIP-170) PASSED. GATE 2 refused and deployed nothing, correctly.

Suite: 185 suites / **806 passed** / 7 failed / 1 skipped. This run's own regression set: **82/82**.
Four failures are known-baseline. **Three are NEW, all in `test/attacks/S01_PerpQuoteDeadlock.t.sol`,
and all three were `[PASS]` at baseline `1e98bb4`:**
- `test_invariant_divergedEngineIsPermissionlesslyRecoverable` — next call did not revert as expected
- `test_poc_routeC_unsetEngineStrandsTheQuoteWithAFullBook` — next call did not revert as expected
- `test_refute_routeB_rotationRepointsTheEngineInTheSameCall` — a funded engine keeps the asset it can
  pay in: `0xA4AD4f68…` != `0x0`

Cause is almost certainly `1eff1d2`, which replaced the rotation guard's "revert if counters are
non-zero" with "sweep to the treasury in the old asset, zero them, then adopt". Tests asserting the
old refusal now see success. **Do not assume that and move on:** the first one is an INVARIANT
asserting a diverged engine is recoverable **permissionlessly**, and the new sweep lives inside
`syncGeneration` while `retirePayout` is **timelock-only**. If recovery now needs the timelock where
it needed nobody, that is a genuine liveness regression and the test is right. Settle it explicitly.

Everything else is ready: the deploy is one command and fully unattended (contracts → mint out →
summon → manifest → ABIs → frontend build → Railway indexer → post-deploy verification).

**Measured 2026-09-12: GATE 0 and GATE 1 PASS** (signer verified, 12.4757 ETH, build clean, nothing
over EIP-170). **GATE 2 currently FAILS on one regression — see below.**

---

## 0. State at hand-off

| thing | state |
|---|---|
| Fixes | All 6 fixer groups COMPLETE. ~60 commits. 27 regression tests in `test/attacks/X*.t.sol`. |
| Docs | 15 files in `docs/protocol/` (01–14 + README). Frontend `/docs` page NOT yet rewritten. |
| Stranded ETH | **12.250657 ETH RECOVERED** (11 perp vaults + v7 gnome). Deployer `0xc944…c133` holds **12.4757 ETH**. |
| Signing | `.env.recovery` holds `RECOVERY_PK` for the deployer. Gitignored, mode 600. **Delete after deploy.** |
| Full suite | Was RUNNING at hand-off — its result is gate 1 below. Log: `/tmp/p4-suite.log`, sizes `/tmp/p4-sizes.log`. |
| Re-hunt | NOT run. Gate 2 below. |

Still-stranded ETH, deliberately not taken (see `STUCK_VALUE.md`):
- **6.888 ETH** r33/34 — armed, matures **~2026-09-12 20:05 UTC**. **NEVER run `scripts/arm-old-emergency.sh`** — it re-arms and adds 2 days.
- **5.547 ETH** r32 — needs arming, then 300 s. Timelock `0xBc1C27Ed…`.
- **0.919 ETH** round 38 — LIVE; taking it kills r38, so it belongs in step 3 below.
- 8.056 ETH unrecoverable (no withdraw selector compiled in).

---

## 1. GATE 1 — the suite must be clean (do not skip)

```
cd contracts/solidity
export FOUNDRY_PROFILE=cauldron FOUNDRY_DISABLE_NIGHTLY_WARNING=1
export FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
forge build --sizes            # every contract must be UNDER 24,576 runtime
forge test --threads 2         # compare against the baseline below
```

### MEASURED RESULT 2026-09-12 (~60 fix commits in)
179 suites / **782 passed** / 14 failed / **1 skipped** (baseline 152/718/13/1).
- **All 27 of this run's regression tests pass: 65/65.**
- Skip count did NOT grow. No contract over EIP-170 (CauldronHook 102 B free, CauldronRegistry 416,
  PerpEngine 67, PoolOps 729).
- 13 failures are the known baseline set. **1 is NEW and BLOCKS the deploy:**
  `test_Relaunch_AutoMigratesPerps_WithOpenPositions_OnFork` —
  `token PLV migrated 1:1 into the new token (non-zero): 0 <= 0`.
  **PROVEN a real regression, not pre-existing:** it is `[PASS] (gas: 6814317)` in the baseline log
  at `1e98bb4` and fails now. A fixer's "pre-existing" claim was checked and was wrong. Perp
  inventory migration during relaunch now moves zero, and `PerpEngine.sol:1095 plvToken = newInv`
  then silently erases the principal. A fixer was dispatched for it; if it is still open when you
  resume, it is the FIRST thing to close.

**Baseline to beat: 152 suites / 718 passed / 13 failed / 1 skipped.** The 13 were pre-existing
attack PoCs (`T02_*` ×7, `T03_*` ×3, `test_Inventory_200M`, `test_SurvivorsCanNeverBeClosed`,
`test_SurvivorsUnclosableEvenWhenTheGateOpens`, `test_MinimumBookSizeAt12M`).

Rules: **any NEW failure blocks the deploy** until explained. **A skip count above 1 also blocks it** —
a growing skip count means coverage vanished silently. Known-contested, must be confirmed
pre-existing rather than assumed: `test_Relaunch_AutoMigratesPerps_WithOpenPositions_OnFork`
(fixB proved it fails with its own changes stashed; two other groups edited the relaunch path,
so confirm against the baseline log).

## 2. GATE 2 — re-hunt today's changes (do not skip)

The single strongest finding of this review: **5 of its top findings lived in code a PRIOR
remediation wrote**, and this run then produced 2 fix-induced problems of its own (the royalty
revert that broke secondary sales, and a deployment pointer aimed at a stale record). We have
just written ~60 fixes.

Launch ONE fresh hunter, **blind to why anything changed**, given only:
`git diff --name-only e25988c..HEAD -- contracts/ src/ api/ indexer/ scripts/`
Brief it exactly like the P1 hunters (see `.claude/agents/hunter.md`), PoC prefix `X8`, and tell it
to attack the NEIGHBOURHOOD of the changes, not just the changed lines. One round only.
Anything CONFIRMED goes back to the owning fixer before deploy.

---

## 3. DEPLOY — Sepolia (chainId 11155111)

Authoritative sequence is `docs/protocol/12-DEPLOYMENT.md`, derived from the deploy scripts
themselves (not the old runbooks, which are stale). Read it first; it lists constructor args,
every wiring call, and the ordering constraints where a gap would let a stranger act first.

Signing: `set -a; . .env.recovery; set +a` then `--private-key "$RECOVERY_PK"`.
Deployer `0xc944…c133`, balance 12.4757 ETH (ample).

Order:
1. `forge script deploy/DeployLaunchpad.s.sol` — creates the OZ `TimelockController` FIRST and
   makes it the immutable emergency admin (`deploy/DeployLaunchpad.s.sol:126-133`). `TIMELOCK_DELAY`
   defaults to 180 s. Required env includes `GACHA` (added today by commit `834063c`).
2. `deploy/DeployRotationStack.s.sol`, `deploy/DeployPerp.s.sol`, `deploy/DeployQuoteAssets.s.sol`,
   `deploy/DeployMigrationVesting.s.sol` as the runbook orders them.
3. **Verify wiring before announcing anything**: `hook.isOpener(gacha)` true (the sniper script now
   requires it), emergency admin == timelock, `renounceOwnership` reverts on hook / governor /
   gacha router / vesting / perp engine / mark source / sniper.
4. **Only after the new stack is live**, recover round 38's 0.919 ETH (it kills r38, which is the
   point once its successor exists). Timelock `0x3925859C…`.

## 4. WIRE THE OFF-CHAIN SIDE

**Canonical manifest is `indexer/deployments/round.json`** — established by reading the readers,
not the comments (commit `68c9dc1`). It lives inside `indexer/` because `railway up` only uploads
that directory. Its importers: `indexer/ponder.config.ts:17`, `src/config/cauldron.ts:10`,
`src/config/perp.ts`, `src/config/quotes.ts`, `src/config/presale.ts`.

`deployments/sepolia.json` at the repo root is DEAD (round 20, marked SUPERSEDED). **Do not run
`scripts/sync-deploy.mjs`** — it writes round-20 addresses into files that now import the manifest.

1. Write the new addresses + `schema: cauldron_r<N>` into `indexer/deployments/round.json`.
2. Regenerate ABIs from compiled artifacts, never by hand:
   `forge inspect <Contract> abi` → `indexer/abis/` and `src/config/`. Drift was driven to zero
   today; keep it there.
3. `cd indexer && npm run dev` (or `railway up`) and confirm it indexes the new contracts.
4. `npm run type-check && npm run build` at the repo root; confirm no secret in the bundle.
5. Smoke-test one real user flow end to end: a spot swap must sign a NON-ZERO `minOut`
   (fixed today in `3a5a156` — it used to sign `0n` on every trade).

## 5. AFTER DEPLOY

- `rm -f .env.recovery` — the plaintext key must not outlive the deploy.
- Rewrite the frontend `/docs` page: `src/components/docs/magicfrens-llm.md` is the single source
  (also synced to `public/llms-full.txt` by `scripts/sync-llms.mjs`). Rebuild it from
  `docs/protocol/01–14`. Known-stale claims it still carries: the surtax described as
  `max(decay, jitter)` when the code ADDS them; holder tax TIERS that are implemented nowhere
  (everyone pays 300 bps); an ETH floor vault that can never pay out (`setVault(0)` on both paths).
- Write the final report `FINAL_BLIND_2026-09-11.md` in this directory from `CRITICALS.md`,
  `RECONCILIATION.md`, the `hunt/` and `verify/` reports, and the suite numbers.

---

## 6. Two open items that are DECISIONS, not bugs — ask before acting

1. **Perp vault queue seniority.** `withdrawEth` burns shares into a fixed nominal; any loss that
   leaves `totalEth() >= pendingEth` is borne 100% by live shares, contradicting the note at
   `PerpVault.sol:263-278`. Closing it is an economic redesign, not a guard. fixB verified and
   deliberately did not touch it.
2. **`plvToken = newInv`** (`PerpEngine.sol:1095`). Migration above it is best-effort, so a failed
   migration silently zeroes LP token principal. Root cause is upstream in the relaunch /
   `PerpSwapLib.migrateInventory` wiring. Has a failing fork test.

## 7. Six prior findings never re-tested this pass (blinding forbade reading old reports)

Confirmed still present in source: queue seniority (above), `plvToken` (above), treasury scan flood
(FIXED today, `e377594`), unpaginated vesting release (FIXED today, `20d6de2`). Genuinely unchecked:
gacha reveal grindability via the expired-seed re-anchor (`MiFrensGenesis.sol:532-537`); the
`via_ir` CSE test-suite integrity issue (nine `vm.warp` helpers); and four 09-08 off-chain items
(GraphQL byte cap, indexer freshness gate, immutable `emergencyAdmin`, `fren-teach` secret compare).
**Say these are untested rather than implying coverage.**
