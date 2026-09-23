# MiFrens / Cauldron Solidity re-audit — final report

Date: 2026-09-23. Scope: SCOPE.md (66 first-party Solidity files and their
deployment/ABI/call/event consumers). Baseline `31b753546c0e39efb7ae3c28efe9ee4d7fa67df5`
(frozen snapshot, 4,304 hashed inputs); review tree at HEAD `20640d0` plus the
uncommitted audit patches and tests listed in §4 and FINAL_GATES.json.
Review lineage: Codex (inventory, traversal, 11 fixes) until credit exhaustion,
then Claude Opus 5.5 (remaining leads, 3 fixes, final gates, sign-off) on the
same tree. Nothing was committed, pushed, broadcast to a public network or deployed.

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

**Live deployment warning.** Fixes are source-only. The deployed Sepolia r46
contracts still contain FS-relaunch-01: a relaunch landing at <= 8M gas in the
housekeeping step completes and permanently strands every open perp position,
and the dapp's default gas estimate lands in that band. Until redeployed:
relaunch only with an explicit gas limit well above 8.5M (e.g. 15-20M), and
prefer an empty perp book at relaunch, because any outsider can still submit a
low-gas relaunch first. Do not run migrateToSuccessor while rotated legs exist
(FS-successor-01).

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
| Low | 11 | 1 fixed (deploy script), 10 documented, unfixed per scope |
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

Open Low (documented, unfixed): FS-treasury-L01, FS-treasury-L02, FS-artbuffer-01,
FS-deployfactory-01, FS-deployvesting-01, FS-registry-L01, FS-registry-L02,
FS-hook-L01, FS-venueband-L01, FS-router-L01. Informational: FS-deployperp-I01,
FS-deployrender-I01, FS-rotation-I01, R23-L1 cascade exit wording, governor bench
eviction, vault cumulative deposits; plus stale-documentation notes per worksheet.

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
- Gaps (apply across files): no per-node machine-readable semantic graph (§6.2
  of the brief); target-chain fork lane and deployed parity not run; single
  review lineage; off-chain resilience drills not run; dedicated `render`
  profile does not compile (explicit-path renderer build under cauldron settings
  does). DeployV4Core, DeployLaunchpad and DeployPerp were rehearsed on a local
  chain (rehearsal/README.md); the remaining helper/probe scripts are verified by
  source review and targeted tests only.

## 7. Source / artifact / manifest / on-chain parity

- Artifacts: 66/66 first-party files have whole-input source-matched artifacts
  (CANDIDATE_ARTIFACT_INVENTORY.json).
- Surface recheck against the frozen compiler graph (FINAL_SURFACE_RECHECK.json,
  58 contracts): only intended changes — CollectionLedger +EntitlementReleased,
  MiFrensDividend +pushTokenIsolated (self-only), PerpVault one appended private
  slot (slot 24), RedemptionExt +LegHandedOff. Registry/facet storage identical,
  preserving delegatecall parity.
- Frontend selector parity (scripts/verify-selectors.mjs list) against local
  artifacts: 43/43 present.
- Local rehearsal: bytecode deployed by the production scripts has the audited
  runtime lengths (registry 24,553, hook 24,401, facet 16,334, Genesis 22,858)
  and all wiring reads back correctly, including internal pointers by slot.
- Live deployments (Sepolia r46) and manifests: NOT verified (no RPC). They
  predate every fix in this report.

## 8. Off-chain resilience

Not executed in this Solidity sign-off. Consumer notes found during review:
dapp relaunch uses default gas estimation (safe only with the fix — the
estimate on the fixed registry was 8,378,972 and drained the book);
default DeployPerp leaves opens paused until insurance is funded and shorts
unavailable until token PLV is deposited (intended guards, operator runbook item);
StakePanel hides the zero-display reward claim that FS-perpvault-01's dust
clearing needs (direct contract call works); indexer does not consume
EntitlementReleased or LegHandedOff (optional).

## 9. Test / build / size results

See VALIDATION.md for exact commands, exits and triage.

| Run | Result |
|---|---|
| Candidate full local (before this continuation) | 1079 pass / 45 fail / 276 skip |
| **Final full local** (final tree, FORK_RPC empty) | **1100 pass / 42 fail / 276 skip**; fails = 39 need a fork + 3 documented Low properties; 0 new; 3 resolved |
| Targeted fix batches this continuation | gacha-pity-fix 32/0; relaunch-successor-fix 46/0 |
| **Full suite on a local chain** (FORK_RPC = local anvil with V4 core) | **1448 pass / 12 fail / 1 skip**; fails = 8 need real Sepolia state + 3 documented Lows + 1 superseded premise (FS-ledger-01, assertion tightened; suite then 16/16) |
| Production-script rehearsal (local chain) | DeployV4Core, DeployLaunchpad, DeployPerp succeed; presale → ignition → trade → gacha → perps → governance → relaunch with open book → Genesis continuation all succeed; low-gas relaunch reverts Panic(0x11), estimated-gas relaunch drains the book |

Runtime sizes (headroom to 24,576): CauldronRegistry 24,553 (23; was 8 before
this continuation), PoolOps 24,465 (111), CauldronHook 24,401 (175), PerpEngine
24,207 (369), MiFrensGenesis 22,858 (1,718); all others larger margins.
Initcode (without constructor args) all below 49,152.

## 10. Residual risk, assumptions and launch blockers

Assumptions: owner/timelock/emergency roles are honest and competent; configured
dependencies (policies, routers, oracles, death checker, mark source, quote
tokens, venues) are curated; blockhash-based gacha randomness is acceptable.

Launch blockers (minimum evidence still required):
1. Run the fork-dependent suites against a pinned fork of the TARGET chain with
   an approved RPC (8 tests here need real Sepolia feeds/pools/router); classify
   every failure.
2. Repeat the local rehearsal (rehearsal/README.md) on a fork of the target chain
   with the real oracle feeds, then scripts/verify-manifest.mjs and
   scripts/verify-selectors.mjs against its output; link GachaLib and other
   libraries at their new addresses.
3. Independent second review of FS-relaunch-01, FS-successor-01 and FS-gacha-01
   fixes (same-lineage verification only so far).
4. Decide on the documented Lows (notably FS-registry-L01 break-glass for ERC20
   generations and FS-artbuffer-01 before any dense art upload) and the
   StakePanel dust-claim consumer path.
5. Treat registry size as a hard constraint (23 bytes headroom).
