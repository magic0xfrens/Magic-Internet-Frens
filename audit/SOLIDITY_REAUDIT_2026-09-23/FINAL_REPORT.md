# MiFrens / Cauldron Solidity re-audit — final report

Date: 2026-09-23. Scope: SCOPE.md (66 first-party Solidity files and their
deployment/ABI/call/event consumers). Baseline `31b753546c0e39efb7ae3c28efe9ee4d7fa67df5`
(frozen snapshot, 4,304 hashed inputs). Review tree: `5f420af` (High/Medium
fixes, tests, sign-off), then at the owner's request `6961bb4` (the ten Lows and
the StakePanel dust claim) and `afb5642` (function graph refreshed onto the fixed
code). Review lineage: Codex (inventory, traversal, 11 fixes) until credit
exhaustion, then Claude Opus 5.5 (remaining leads, 3 fixes, final gates,
sign-off, Low fixes, graph refresh) on the same tree. After sign-off the owner
authorized: retiring r46's liquidity (R46_RETIREMENT.md) and deploying r47 to
Sepolia from the fixed tree (§7).

## Verdict

**Do not deploy this exact tree to mainnet today. It is ready for a testnet
redeploy and for the target-chain gates listed at the end.**

Every confirmed Critical/High/Medium finding is fixed and has a passing
regression; the full local suite on the final tree has no unexplained failure;
every deployable contract fits EIP-170 with source-matched artifacts; storage and
ABI changes are exactly the intended ones; the production deployment scripts ran
end to end on a local chain and the full protocol lifecycle — including a relaunch
with an open perp book — completed on the deployed bytecode. What is missing is
evidence this environment cannot produce: target-chain fork state and deployed-
bytecode/manifest parity (no approved RPC), an independent second review of the
newest fixes, and off-chain resilience drills. Minimum remaining evidence is listed in
"Launch blockers" below.

**Live deployments.** r46 (pre-fix, still containing FS-relaunch-01) had its
liquidity withdrawn through its own emergency path and is retired; nothing of
value remains in its pools. The Sepolia deployment of the fixed tree is r47 (§7).

## 1. Scope and identity

- Frozen inputs intact: 4,304/4,304 snapshot hashes match BASELINE.json.
- First-party files changed versus baseline (16): CauldronHook, CauldronRegistry,
  CauldronVault, CollectionLedger, GachaLib, MiFrensDividend, MigrationVesting,
  PerpEngine, PerpVault, PoolOps, QuoteOracle, RedemptionExt, SurtaxLib,
  DeployCauldron, DeployLaunchpad, DeployRotationStack. Current hashes:
  SIGNOFF_CHECKLIST.json. 46 test/harness files added, none removed.
- Submodules as recorded in BASELINE.json (openzeppelin-contracts dirty pointer
  and nested forge-std drift recorded, not modified).
- Toolchain: Foundry 1.4.4-nightly 765b856, solc 0.8.30 (0.8.26 for versioned
  engine/oracle artifacts), via_ir, optimizer_runs=1, Cancun.

## 2. Risk counts (verified severity / status)

| Severity | Count | Status |
|---|---:|---|
| Critical | 0 | none confirmed (absence is not proof) |
| High | 2 | both fixed and verified |
| Medium | 12 | all fixed and verified |
| Low | 11 | all fixed and verified (1 in the sign-off, 10 at the owner's request in `6961bb4`) |
| Informational | 6 tracked IDs + documentation drift | documented |

Full records: FINDINGS.md (mechanism, PoC, counterargument, fix, regression).

## 3. Value and authority model (summary)

Registry custody: LP/reserve position NFTs, rotated legs, loose quote/token
balances, genesis reserve entitlement; linked PoolOps executes in registry
context. Hook custody: fee reserves per asset, legacy buyback buffer, gacha
credit/queue state. Engine custody: PLV, insurance, trader collateral, token
inventory; vault holds staker shares and reward ledgers. Authorities: registry
owner (governance timelock), emergency admin (armed, delayed, guardian-vetoable),
hook/engine owner, Genesis deployer, governors (snapshot votes). Permissionless:
trading (with beforeSwap liquidation sweep), relaunch when dead, gacha resolve,
claims/migration, rotation steps under an approved envelope. Worksheets and
SIGNOFF_CHECKLIST.md hold per-file detail.

## 4. Findings, fixes and regressions

| ID | Sev | Mechanism (one line) | Fix location | Regression evidence |
|---|---|---|---|---|
| FS-relaunch-01 | High | Relaunch skipped the perp force-close when <= 8M gas remained and completed with the book stranded; default gas estimation lands there | CauldronRegistry._perpHousekeep | registry-perp-leads (pre) → relaunch-successor-fix: 0 stranded of 36 completed caps |
| FS-badge-floor-01 | High | Liquidation badges redeemed art-only floor backing | PoolOps recycle/buy, CauldronVault.redeem | badge-floor-fix 21, earned-art-and-badge-native |
| FS-gacha-01 | Medium | Failed art mint (deployer-set Genesis validator) erased earned pity and inflated `opened` | GachaLib.resolveTickets | genesis-paid-mint-failure (pre) → gacha-pity-fix 32/0 |
| FS-successor-01 | Medium | V2 successor handoff left rotated leg NFTs unrecoverable | RedemptionExt.recoverLegs | registry-perp-leads (pre) → relaunch-successor-fix |
| FS-surtax-01 | Medium | Malformed surtax policy reply reverted fee-bearing swaps | SurtaxLib.surtaxBps | surtax-policy-fix 7 |
| FS-feerouter-01 | Medium | Malformed/overflowing router reply bypassed fallback | CauldronHook fee split | fee-router-fix 3, acceptance 5/5 |
| FS-ledger-01 | Medium | Pre-death credit stranded at zero-claimant freeze | CollectionLedger.crystallize | ledger-release-conservation 27, registry integration |
| FS-dividend-01 | Medium | Native rounding residual re-credited repeatedly | MiFrensDividend.receive | dividend-residual-fix 13, 256-case sequence |
| FS-dividend-02 | Medium | Malformed token reply blocked whole basket payouts | MiFrensDividend payout isolation | dividend-payout-isolation 22, atomicity 2 |
| FS-vesting-01 | Medium | Malformed instant-tier policy blocked migrations | MigrationVesting._isInstant | vesting-policy-fix 29, registry integration |
| FS-oracle-01 | Medium | Malformed feed dropped recorded volume (false-death risk) | QuoteOracle reads | oracle-fix-regressions 42, neighbors 146 |
| FS-perpvault-01 | Medium | Vault replacement disabled earned reward claims | PerpVault.hasStakers accounting | perp-earned-yield-fix 32, 256x64 sequence |
| FS-perpmark-01 | Medium | Out-of-range mark tick disabled beforeSwap sweep | PerpEngine._currentTick | perp-mark-range-fix 4, neighbors 15 |
| FS-venueseed-01 | Medium | Repeated venue seeding orphaned the earlier LP NFT | VenueSeeder + DeployLaunchpad | venue-reseed-guard, launchpad-venue-compatibility |
| FS-deployhook-01 | Low | Legacy script mined an obsolete hook permission mask | DeployCauldron._hookFlags | deploy-hook-permission-offline 2 |

Lows fixed after sign-off (`6961bb4`, regressions in test/attacks/R23_LowFixes.t.sol
or the former R23 Low properties, now passing; details in FINDINGS.md):

| ID | Fix |
|---|---|
| FS-registry-L01 | emergencyWithdrawLP pays the recovered quote in the generation's own currency0; body moved into RedemptionExt behind an onlyEmergency + timelocked registry stub (EIP-170) |
| FS-registry-L02 | relaunch flushes legacy buybacks before folding genesisPending |
| FS-hook-L01 | nftPriceAt: bounded one-word policy read, malformed reply falls back |
| FS-router-L01 | _playInCurveUnits: bounded oracle read, malformed or overflowing reply falls back |
| FS-treasury-L01 | equal support breaks to the lower proposal id in vote and winner |
| FS-treasury-L02 | cancel stops only the envelope the named proposal installed |
| FS-artbuffer-01 | FrenRenderer buffer grows instead of overflowing |
| FS-venueband-L01 | seedBand width bandBps*995/1000 |
| FS-deployfactory-01 | FixFactoryWiring EXECUTE reuses the scheduled FACTORY |
| FS-deployvesting-01 | DeployMigrationVesting sets the claim gate only with a matured arm |

Informational (accepted): FS-deployperp-I01, FS-deployrender-I01, FS-rotation-I01,
R23-L1 cascade exit wording, governor bench eviction, vault cumulative deposits;
plus stale-documentation notes per worksheet.

## 5. Attacks attempted that held (selection)

- Low-gas relaunch after fix: 6.0-8.0M caps revert; no completed relaunch leaves
  positions open (R23RelaunchGasSkip).
- Mixed-leverage cascade ordering (R23-L1): 256 fuzz runs + 24-step ladder with
  21 in-sweep kill fills, no stranded victim, no insolvent survivor, no PLV loss.
- Re-entrant gacha mint cannot rewind/desync the queue (GACHA1g) — preserved
  after FS-gacha-01; rejecting validator cannot wedge the FIFO (GACHA1b).
- Earned liquidation badge cannot redeem art backing through recycle or legacy
  vault; OG IDs cannot use the collection door (OgFloorRatchet 13).
- Seeder range eviction (R23-L2) not reproduced; streaming unreachable in
  shipped launches.
- Governor bench flooding: no permanent freeze.
- Zap refund callbacks: nested zap refused; rejecting refund rolls back.
- Emergency rotation recovery: foreign quote recoverable via separate sweep.
- Pre-sweep book limits: 64-position condemnation refused atomically; kill cap
  cannot be used to bypass the pre-sweep.

## 6. Coverage and explicit gaps

- Source-body traversal: 66/66 files, documented per file (TRAVERSAL_INVENTORY_CHECK.json).
- Per-file final sign-off: see SIGNOFF_CHECKLIST.md (count and verdicts there).
- Per-node semantic graph: audit/graph refreshed onto the fixed code (`afb5642`),
  1102 nodes, validate.py 0 failures on all ten clusters, join.py resolves every
  edge. 479 unchanged nodes still carry generated stub prose (CHANGES_SINCE_2026-09-18.md).
- Gaps (apply across files): target-chain fork lane not run; single
  review lineage; off-chain resilience drills not run; dedicated `render`
  profile does not compile (explicit-path renderer build under cauldron settings
  does). DeployV4Core, DeployLaunchpad and DeployPerp were rehearsed on a local
  chain (rehearsal/README.md); the remaining helper/probe scripts are verified by
  source review and targeted tests only.

## 7. Source / artifact / manifest / on-chain parity

- Artifacts: 66/66 first-party files have whole-input source-matched artifacts
  (CANDIDATE_ARTIFACT_INVENTORY.json).
- Surface recheck against the frozen compiler graph (FINAL_SURFACE_RECHECK.json,
  regenerated on the final tree, 74 contracts): only intended changes —
  CollectionLedger +EntitlementReleased, MiFrensDividend +pushTokenIsolated
  (self-only), PerpVault one appended private slot (slot 24), RedemptionExt
  +LegHandedOff and, from the Low fix, +emergencyWithdrawLP/+EmergencyWithdraw
  (reached only through the registry stub), IRegistryGate +emergencyReadyAt
  (deploy script). Registry/facet storage identical, preserving delegatecall parity.
- Frontend selector parity (scripts/verify-selectors.mjs list) against local
  artifacts: 43/43 present.
- Local rehearsal: bytecode deployed by the production scripts has the audited
  runtime lengths (registry 24,553, hook 24,401, facet 16,334, Genesis 22,858)
  and all wiring reads back correctly, including internal pointers by slot.
- **Sepolia r47** (R47_DEPLOYMENT.md): deployed from `6961bb4` with the
  production scripts. 32/32 deployed runtimes byte-identical to the local
  artifacts (immutable and link slots masked; metadata hash included), manifest
  round 47 verified (verify-manifest.mjs; selector parity 11/11 contracts), live
  wiring read back. r46 predates the fixes and is retired (R46_RETIREMENT.md).

## 8. Off-chain resilience

Not executed in this Solidity sign-off. Consumer notes found during review:
dapp relaunch uses default gas estimation (safe only with the fix — the
estimate on the fixed registry was 8,378,972 and drained the book);
default DeployPerp leaves opens paused until insurance is funded and shorts
unavailable until token PLV is deposited (intended guards, operator runbook item);
StakePanel now offers "Clear dust reward" for a positive reward that rounds to
zero (`6961bb4`); indexer does not consume
EntitlementReleased or LegHandedOff (optional).

## 9. Test / build / size results

See VALIDATION.md for exact commands, exits and triage.

| Run | Result |
|---|---|
| Candidate full local (before this continuation) | 1079 pass / 45 fail / 276 skip |
| **Final full local** (final tree, FORK_RPC empty) | **1100 pass / 42 fail / 276 skip**; fails = 39 need a fork + 3 documented Low properties; 0 new; 3 resolved |
| Targeted fix batches this continuation | gacha-pity-fix 32/0; relaunch-successor-fix 46/0 |
| **Full suite on a local chain** (FORK_RPC = local anvil with V4 core) | **1448 pass / 12 fail / 1 skip**; fails = 8 need real Sepolia state + 3 documented Lows + 1 superseded premise (FS-ledger-01, assertion tightened; suite then 16/16) |
| **Local chain, after the Low fixes** (`6961bb4`) | **1459 pass / 8 fail / 1 skip** (367 suites); fails = exactly the 8 that need real Sepolia state |
| Production-script rehearsal (local chain) | DeployV4Core, DeployLaunchpad, DeployPerp succeed; presale → ignition → trade → gacha → perps → governance → relaunch with open book → Genesis continuation all succeed; low-gas relaunch reverts Panic(0x11), estimated-gas relaunch drains the book |

Runtime sizes on the final tree, as deployed in r47 (headroom to 24,576):
PoolOps 24,465 (111), CauldronRegistry 24,342 (234; was 23 before the
break-glass body moved into the facet), CauldronHook 24,338 (238), PerpEngine
24,207 (369), MiFrensGenesis 22,858 (1,718), RedemptionExt 17,250; all others
larger margins.
Initcode (without constructor args) all below 49,152.

## 10. Residual risk, assumptions and launch blockers

Assumptions: owner/timelock/emergency roles are honest and competent; configured
dependencies (policies, routers, oracles, death checker, mark source, quote
tokens, venues) are curated; blockhash-based gacha randomness is acceptable.

Launch blockers (minimum evidence still required):
1. Run the fork-dependent suites against a pinned fork of the TARGET chain with
   an approved RPC (8 tests here need real Sepolia feeds/pools/router); classify
   every failure.
2. Repeat the deployment on the target chain (r47 on Sepolia is the template:
   R47_DEPLOYMENT.md, with verify_deployed_bytecode.py, verify-manifest.mjs and
   verify-selectors.mjs against its output).
3. Independent second review of FS-relaunch-01, FS-successor-01 and FS-gacha-01
   fixes (same-lineage verification only so far).
4. Treat registry size as a hard constraint (234 bytes headroom after moving the
   break-glass body into the facet); PoolOps (111) likewise.
