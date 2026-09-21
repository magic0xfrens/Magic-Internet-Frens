# Verification checkpoint — 2026-09-18

This is an interim evidence record, not a completed audit or deployment attestation.

## Current focused remediation rerun (2026-09-19)

The current checkout passed **59/59** tests with the production `cauldron`
profile across `DeployLaunchpadSafetyTest`, `PerpPartialCloseLocalTest`,
`PerpVaultRepeatedWriteoffTest`, `PerpRebookAccountingTest`,
`QuoteRotationLocalIntegrationTest`, `QuoteRotatorTest`,
`RotationLifecycleLocalTest`, `UnifiedVaultDonationTest`, and
`X2c_OracleFloorFailsSafe`. This is a focused local remediation/control lane,
not fork or deployed-bytecode parity evidence.

The follow-on local lifecycle lane passed **18/18** tests: D04 rebook
funding/penalty, cascade projection/loss, exact-output preemption, gas-budget
behavior, 24/64-position pre-sweeps with deferred badges, and NativeQuoteZap
custody/fee-bearing fuzz checks. These use local production V4 fixtures and do
not attest to live deployment parity.

An additional local generation-sync/quote-rotation lane
(`K3c_RotationStrandsPerpEngine`) passed **5/5**. It proves the permissionless
sync refusal for a quote-side staker, the owner/timelock override, owner-only
authorization, warmup control, and successful adoption when the vault is empty.
The separate hostile-vault relaunch suite was attempted but produced 3 skipped
fork-gated tests; it receives no coverage credit.

The local `K3a_StaleQueueEatsDeposit` model lane passed **2/2** (fresh deposits
cannot be consumed by a stale queue in the solvent control; the attack model
reproduces the documented queue-seniority behavior). It is model-vault
evidence, not full production-engine integration. `S08_InSwapGasStarvation`
remains 5 fork-gated skips and receives no credit.

Additional local lanes historically passed **6/6**, but this is NOT six
security-control successes. `T9bDividendConservation` contains two conservation
controls and one successful vulnerability reproduction: its cast-spell test
asserts two shares for one NFT, a surviving phantom share after transfer, and
only half of a later deposit claimable. `T9eLegacyBuybackSandwich` contains the
three reference-seeding/honest-buyback/adverse-tick controls. See
`REVIEW_DIVIDEND_CALLBACK.md` and NFT-02 for the callback trust boundary.
These are local harnesses; no live deployment or fork parity is claimed.

The current off-chain rerun also passed **19 Node tests, 2 API tests, 7
indexer tests, and 5 swap-gas tests**. The npm command emitted only an npm
CLI warning for the extra `--runInBand` argument; all configured suites exited
successfully.

An attempted read-only rerun of the 35 previously failing fork-dependent
contracts with the configured Sepolia RPC did not execute any test: Foundry
exited 134 while constructing its macOS system proxy client
(`system-configuration` NULL object). This is an infrastructure/toolchain
failure, not a security pass or a production-code failure; the fork lane stays
open and the earlier bounded 12/12 fork result remains the only credited fork
evidence.

## Latest continuation

- Current isolated production-profile focused run: **29 passed / 0 failed / 0
  skipped**. It includes pre-trade membership snapshot/final revalidation,
  24/64-position books, exact-output and rotated-cursor cases, gas rollback,
  cascade projection/loss, partial-close minimum, and 257 rebook fuzz cases.
  The command was run with `FOUNDRY_PROFILE=cauldron forge test --offline
  --threads 1 --match-contract 'PreSweepLargeBookLocalTest|LocalCascadeProjectionTest|LocalCascadeLossTest|LocalExactOutputPreemptionTest|PerpPartialCloseMinimumTest|PerpPartialCloseLocalTest|PerpRebookAccountingTest' -vv`.
- Claim-later badge regression: **1 passed / 0 failed / 0 skipped**. A 24-position
  pre-trade sweep left 24 claimable keeper badges, minted none inline, and a
  bounded claim minted all 24 with intentionally absent liquidation stats.
  Keeper-credit preservation is asserted by one-for-one badge entitlement; a
  full economic payment comparison remains a follow-up acceptance check.
- The isolated production compile completed successfully with Solc 0.8.26 and
  0.8.30. It emitted existing low-level-call and initcode warnings; no size
  acceptance claim is made from those warnings alone.
- Fresh compiled runtime-bytecode measurements from that same source are:
  PerpEngine 23,244 bytes (1,292 bytes below EIP-170), CauldronHook 23,763
  (773 below), CauldronRegistry 24,493 (43 below), PoolOps 24,174 (362 below),
  RedemptionExt 13,745, and QuoteRotator 8,532. Registry/PoolOps headroom is
  tight and must be rechecked after any additional production edit.

- Actual Sepolia fork: `LIQ02_PreemptiveProjection` **5 passed / 0 failed / 0
  skipped**, with public `FORK_RPC` plus manifest PoolManager/PositionManager.
  Original assertions executed; this is fresh local protocol code on forked
  manager state, not deployed-protocol parity. See `ARTIFACT_AND_DEPLOYMENT_PARITY.md`.
- Current bounded fork lane with `FORK_RPC`, PoolManager, and PositionManager:
  **12 passed / 0 failed / 0 skipped** across D04, LIQ03, LIQ04 exact-in/out and
  cascade, LIQ05 cascade loss, R1B padded-book traversal, and M4A/M4B relaunch
  controls. R1B's padded-book assertion now observes the victim closed rather
  than left insolvent. This is forked local production code, not deployed
  source/bytecode parity.
- A subsequent isolated `V2A_VoteFarm` fork probe crashed Foundry before test
  execution in `system-configuration` while constructing its HTTP client
  (`Attempted to create a NULL object`, exit 134). This is an RPC/toolchain
  infrastructure failure, not a pass or a vulnerability result; the prior
  offline failure remains a fork-prerequisite gap.
- Root independently reran swap-gas helper tests: **5/5 passed**. `npm test` now
  includes the focused `test:swap-gas` lane instead of leaving it opt-in.

- Historical PERP-04 attempt: **16 passed / 3 failed / 0 skipped** across six
  suites, caused by a transient source overlap. It is superseded by the current
  59-test remediation lane and 18-test lifecycle lane at the top of this file;
  no retest is pending for that historical result. Source hash, precise gas
  ladder and traversal limitations remain in `REVIEW_PRESWEEP_COMPLETENESS.md`.
  Command: `FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-contract 'PreSweepLargeBookLocalTest|LocalCascadeProjectionTest|LocalCascadeLossTest|LocalExactOutputPreemptionTest|PerpPartialCloseMinimumTest|PerpRebookAccountingTest' -vv`.
- Historical frontend type-check failure after overlapping manifest edits is
  superseded: the current `npm run type-check` rerun exits 0 and is recorded at
  the top of this file.

- PERP-03 post-patch focused run: **22 passed / 0 failed / 0 skipped** across six
  suites, including partial minimum rollback/zero-floor opt-in, partial funding,
  rebook fuzz (256 cases), cascade and exact-output controls. Command:
  `FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-contract 'PerpPartialCloseMinimumTest|PerpPartialCloseLocalTest|PerpRebookAccountingTest|LocalCascadeProjectionTest|LocalExactOutputPreemptionTest|LocalCascadeLossTest' -vv`.
- NFT-01 / zap / local liquidation-edge run: **22 passed / 1 failed / 0 skipped**.
  NFT-01's eight tests plus six legacy controls passed; zap's four passed including
  fuzz. The failure is the unchanged gas multiplier assertion (GAS-01, Low), not
  a suppressed result. See `LOCAL_LIFECYCLE_RESULTS.md`.

- Full serial offline rerun: 758 passed / 36 failed, exit 1. Predates NFT-01 and
  the new liquidation-edge adapters. Exact additional failure is retained in
  `OFFLINE_RERUN.md`; no skip or silent-return coverage is credited.
- CORE-01 feed-boundary cases: 9 passed plus 3 run-entry rejection controls.
- PERP-02 write-off suite: 4 passed, including the focused fuzz campaign; see
  `LOCAL_LIFECYCLE_RESULTS.md` for the replay count and fixture limits.
- Root `npm test`: 19 Node + 2 API + 7 indexer tests passed.
- Root `npm run type-check` and indexer `./node_modules/.bin/tsc --noEmit`:
  both exit 0 after the market-consumer fix.
- NFT-01 pre-patch: 2 failed / 1 passed in `UnifiedVaultDonationTest`.
  The failure is a missing expected rejection, not a dependency/setup error.

The older sections below preserve prior runs and their narrower source checkpoints.

## Executed local checks

- Buyback decimal regression/control: 2 passed after patch; neighboring X1a/X4a/X1e suites: 9 passed.
- Rebook accounting harness: 2 unit tests and 1 fuzz test (256 cases) passed. Harness-level arithmetic evidence is not by itself production reachability evidence.
- Production V4 PoolManager/PerpEngine partial-close test: passed. Hook and registry are test fixtures; no fork is claimed.
- Actual launch script preflight entry point: 3 passed (mainnet mock quote, codeless native feed, stale native feed rejected before signer/config loading or broadcast).
- Real V4 rotation controls: 3 passed (fresh oracle small trade, fresh oracle adverse trade rejection, unauthorized callback rejection).
- Missing-oracle rotation regression: failed before ROT-01 patch with `next call did not revert as expected`, establishing the bypass at the production rotator boundary.

The last combined pre-ROT-01-patch command returned 7 passed / 1 failed / 0 skipped across 3 suites:

```sh
FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 \
  --match-contract 'QuoteRotationLocalIntegrationTest|DeployLaunchpadSafetyTest|PerpPartialCloseLocalTest' \
  --match-test 'test_(partialClose|runRejects|controlFresh|unsetOracle|strangerCannot)' -vv
```

Focused post-ROT-01-patch rerun completed successfully: **43 passed, 0 failed, 0 skipped**, across six suites. The fuzz test ran 256 cases. Compiler versions in this run were 0.8.26 and 0.8.30, selected by the existing project configuration; existing compiler warnings remain. `git diff --check` also passed.

```sh
FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 \
  --match-contract 'QuoteRotationLocalIntegrationTest|DeployLaunchpadSafetyTest|PerpPartialCloseLocalTest|PerpRebookAccountingTest|X2c_OracleFloorFailsSafe|QuoteRotatorTest' -vv
```

Suite counts: deployment 3; local perp integration (including inherited XL1 cases) 7; real V4 rotation 4; rotator unit suite 23; X2c 3; isolated rebook 3.

Full serial offline rerun after ROT-02 completed: 276 suites, 1,046 tests, 735 passed / 35 failed / 276 skipped, exit 1. Exact failing tests are retained in `OFFLINE_RERUN.md`. This is not a full-scope green gate. Missing fork prerequisites and silent-return passes remain coverage gaps.

## Current full offline suite

After the PERP-03/PERP-04 changes, the fresh full production-profile run
completed with **803 succeeded / 35 failed** (exit 1). Fork-gated tests were not
available because `FORK_RPC` was unset. The local lifecycle adapters, including
LIQ02/03/04/05, D04, relaunch controls, vault-donation controls, and the new
claim-later badge regression passed. The failed set remains open: most failures
are explicit fork prerequisites, while `V2A_VoteFarm` and several direct
fork-dependent liquidation tests require separate diagnosis. No failed test is
counted as fixed or silently skipped.

## ROT-02 local lifecycle verification

Before the consolidation patch, both round-trip assertions failed: duplicate launch-quote position and failure to consume the next primary migration allowance. After the patch both passed. The fixture was then strengthened to create ten mock genesis NFTs and a real, nonzero redemption reserve. All four tests passed (0 failed, 0 skipped):

- migration out and back consolidates the launch active position;
- the next migration recognizes the returned treasury as primary;
- two complete round trips preserve the reserve position id, liquidity, pool key and advertised floor, followed by a successful OG redemption; and
- an impossible output minimum rolls back source/destination liquidity, balances, denomination and mandate, followed by a successful retry.

Command: `FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-path test/audit_full_scope/RotationLifecycleLocal.t.sol -vv`.

The fixture uses real local V4, PositionManager, canonical Permit2, registry/facet, hook, governor and rotator. Fixed votes, mock OG NFTs/quote and explicit 1:1 oracle pegs are fixture assumptions. Legacy already-duplicated state and deployment parity are not covered by these four tests.

Current artifact runtime bytes: Registry 24,492 (84 spare); PoolOps 24,173 (403 spare); Hook 23,762 (814 spare); PerpEngine 23,243 (1,333 spare); RedemptionExt 13,744 (10,832 spare); QuoteRotator 8,531 (16,045 spare). `git diff --check` passed. These measurements are current local artifacts, not deployed bytecode attestations.

## Compiler-backed node map

`compiler_graph.mjs` regenerated AST/type information directly from current source using installed 0.8.30 and 0.8.26 compilers, without bytecode generation or network. It recorded 1,038 declarations, 3,227 call expressions, 14 explicit assembly/delegatecall sites and 163 contract/interface/library surfaces. Every nonnegative compiler declaration reference resolved. Builtins, dynamic calls, constructors, event/error calls and ordinary calls are distinguished by their retained compiler types/target kinds; totals must not be presented as 3,227 externally callable functions or reviewed vulnerabilities.

`COMPILER_GRAPH.json` retains source hashes, compiler binary/input hashes, exact referenced declarations, ABI/selectors and storage layouts. Compiler selections from mixed-version artifacts are explicitly noted. This map replaces regex guesses as static dispatch evidence; it does not prove runtime target identity, full property coverage or source-to-deployment parity.

## Important limitations

- No deployed contract was changed. Remediations remain local and uncommitted.
- No complete source-to-deployment attestation, full liquidation matrix, legacy-position recovery rehearsal, or final invariant campaign has completed.
- Fork-dependent tests without an actual fork do not count as verified coverage, including silent-return passes.
- Deploy-script tests set process-global environment and must be run serially (`--threads 1`).
- Function inventories and semantic graph work are not substitutes for security review; global reconciliation after code changes remains pending.
