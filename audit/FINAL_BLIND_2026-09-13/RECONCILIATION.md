# RECONCILIATION — FINAL_BLIND_2026-09-13 (P3)

Every post-P2 verified item of this run, sorted against `PRIOR_INDEX.md` (112 netted prior rows).
Attribution is from `git blame`/`git show` on the cited line, not from prose. Blame was taken at
`61f3fba` for the four off-chain files that this run's own fixOFF commits (`6504a11`, `fe94a40`,
`d8ed3af`) have since rewritten.

**Headline regularity, again.** 10 of 28 rows are *fix-induced* and 4 are *prior-fix-FAILED*: 14 of
this run's 28 items live in, or are the direct consequence of, code a previous remediation wrote.
That is the same dominant pattern the 09-11 run recorded, and it is now the single best predictor of
where the next finding will be.

## The table

| id | severity (post-P2) | bucket | prior id(s) | evidence (commit / prior status / one sentence) |
|---|---|---|---|---|
| K1a | HIGH | missed-by-prior | PS-core (PROVEN-SAFE), REHUNT-lead (LEAD) | `CauldronHook.sol:1558,:1584` blame `c3dc671` (2026-09-04) — original code, never touched by a fix; prior H1 proved the volume path's *loops* bounded and left the day-bucket comparison and the absence of any volume-independent death trigger unexecuted. |
| H1-L3 | MEDIUM (derived) | missed-by-prior | prior-run `hunt/H1_core_pool.md:173` | `CauldronHook.sol:773,:1644` blame `3c9b453` (feature, not a fix); the prior hunter read `MAX_SIBLINGS` at `:1579` as a *safety bound* and wrote it up as such, never asking what the 10th distinct sibling does (reverts the whole rotation via `RedemptionExt.sol:473`, and there is no unlink). |
| H1-L2 | LOW (dormant) | still-open | DOC-1 (OPEN) | `CauldronHook.sol:1686` blame `d8461b3` (Init); DOC-1 "holder tax tiers unimplemented" is OPEN and this is the same uncapped `_getHolderTaxRate`; dormant only because `nftContract == address(0)` on the deployed path. |
| T2a | HIGH | prior-fix-FAILED | X2a / C-3 / R-04 — FIXED `1b558b8` + `89aa06d` | `TreasuryGovernor.sol:775,:855` blame `89aa06d` *("the migration budget is now the one thing a side-pool slice can't spend")*: the fix made metering read `movedPrimaryBps` **only when `e.maxTotalBps >= BPS_ONE`**, so a *partial* envelope still meters on the shared `movedBps` and one slice from a secondary leg burns the whole voted budget plus a 7-day COOLDOWN. Not dropped against RH-R3 — this run's PoC (`K2a`) supplies the case RH-R3's argument does not cover. |
| T2b | HIGH | prior-fix-FAILED | X2d / B-10 / O-6 — `**` FIXED `b3a9026`; X2h FIXED `e377594` | `b3a9026` ("64 junk filings could erase a mandate") landed in `CauldronGovernor.sol:695,:820` **only** — `TreasuryGovernor.winner()` at `:696-712` is still the `dd570c7` `_leadId` hint + 8-slot bench, and its own comment at `:713-728` describes a walking-backwards scan that is not in the code; 8 open filings after the vote closes evict a PASSED mandate. Not dropped against RH-R1 — the attacker here pays real voting power, which is exactly the cost RH-R1 assumed nobody would pay. |
| T2c | HIGH | fix-induced | X2d / B-10 (`b3a9026`), RH-L6 (LEAD) | `CauldronGovernor.sol:695` (`_benchRecord` admits open proposals) and `:820` (`_recomputeLeader` skips them) are both `b3a9026`; the fix's two halves disagree, so a bench full of open brews makes `hasProposals()` false and `CauldronRegistry.sol:841 NoProposal` permanent — the LEAD RH-L6 predicted the capacity problem, not this asymmetry. |
| T3c | HIGH (from Critical) | prior-fix-FAILED | F-01 — `**` FIXED `efaed64`; F-06 (OPEN) | `PerpEngine.sol:1337` blame `efaed64` *("one dust token deposit could kill the perp engine for a whole gen")*: the fix removed the **token-side** dust veto and installed a **quote-side** one (`hasQuoteStake()` → `VaultStaked`), which `DeployPerp.s.sol:235`'s own staker trips permanently; it also turned F-06's "dead code" into the live revert. The veto was moved, not removed. |
| T3d | HIGH (derived) | fix-induced | README §"Open findings" one-sided `_volumeSiblings` HIGH (OPEN, PoC `S0x_RotationPerpHostage.t.sol`) | `PerpEngine.sol:844` (`blocksVolumeLink`) and `CauldronHook.sol:1626` both blame `20df254` ("weighted-mark interlock") — the mark-armed interlock shipped to release the rotation hostage now lets `linkVolume` through over an **open** book, falsifying `RedemptionExt.sol:606`'s "the book is provably empty". |
| T3a | MEDIUM (downgraded) | still-open | O-2 — DESIGN-DECISION (owner: stays as-is) | `PerpVault.sol:196,:325` blame `c3dc671` (original, untouched by any fix); filed with the new impact the index demands: after a prior insolvency (`pendingEth > totalEth`, a public read) a stale queued exit takes **100%** of a fresh deposit, so this is the accepted design decision plus a griefable trigger, not a re-file. |
| T3b | MEDIUM | fix-induced | F-05 — FIXED `efaed64` | `PerpEngine.sol:1359` blame `efaed64`: the rotation write-off that fix added zeroes `tokYieldEth` but not `tokYieldCumulative`, and the all-or-nothing check at `:2296` (`c3dc671`, unchanged) then reverts `claimTokYield` forever for every pre-rotation token staker. |
| T3e | MEDIUM (derived) | fix-induced | T02-1 / flat-lead-4 — FIXED `1eff1d2` | `PerpEngine.sol:1384` (`markSource = address(0)`) blame `1eff1d2` ("a rotated quote is now something the engine can actually follow") — the clear was added on the **rotation** branch only, never on relaunch, and `PerpMarkSource.weightedTick():173` returns `0` unarmed while `_currentTick` (`:666-684`) accepts any answer. |
| T3f | LOW (derived) | fix-induced | LIQ-02 — FIXED `03469bb` | `PerpEngine.sol:1860` blame `03469bb` ("a short bigger than the pool's token side could never be closed"): the `_rebook` that fix introduced zeroes collateral, which funding (`:917`) and the penalty (`:1617`) are computed from, and contradicts its own comment at `:1849`. |
| K4a | MEDIUM (downgraded) | prior-fix-FAILED | X1e — `**` FIXED `8fa52c6` (already flagged fix-induced by `f9c775f`) | `git show --stat 8fa52c6` edited `RoyaltyRouter.sol` (+16) and rewrote its header to promise "the forward cannot fail" — but the fix only made the **native** forward denomination-aware; the contract is still `receive()`-only (`:35-46`) with no ERC20 ingress, egress or rescue, while `CauldronFactory.sol:81-82` keeps naming it every collection's ERC-2981 receiver, so ERC20-settled marketplace royalties are stranded rather than reverted. |
| K4c | MEDIUM (derived) | missed-by-prior | X4b + twin — FIXED `04607bf` + `381b2a1` | `CauldronGachaRouter.sol:369` blame `1e98bb4` (snapshot, no fix); prior work audited `_churn` for *refund confiscation* and closed that, and nobody then asked why `playChurn` has no `minOut` while sibling `play` at `:234` has two — the legs swap at MIN/MAX sqrt (`:470`, `:496`). |
| K4b | LOW (downgraded) | missed-by-prior | Z-08 / prior-M — `**` FIXED `545cd29` + `d552abc`; PS-core (PROVEN-SAFE) | `CauldronHook.sol:2391` blame `c3dc671`: the expired-seed re-anchor grind was fixed in `MiFrensGenesis.sol:532-537` only and never shape-swept into the hook's ticket re-anchor, which PS-core had declared "gacha reveal not grindable"; largely self-defeating (any `resolveTickets`, plus auto-resolve at `:966-972`), hence LOW. |
| K4d | LOW (derived) | still-open | Z-14 (OPEN) | `RoyaltyRouter.sol:44-46` blame `c3dc671`; Z-14 filed the same `receive()` as a gas problem and is still OPEN — this run states it as the unmetered forward into `fundLegacyBuffer` that lets a 2300-gas payer revert the sale. |
| K5b | MEDIUM (from Critical) | fix-induced | LIQ-01 `9d5cd46` / LIQ-02 `03469bb` remediation → `40b9608` | `git show 40b9608 -- PoolOps.sol`: `- SEED_BASE_WAD = 0.15e18` → `+ = 1e18` ("full range always — an exhaustible band is not a book"), whose own comment recounts the LiqCapped/83M-token incident; the whole of ledger A is now the base, `:402-405` returns before `startSeed`, and the progressive seeder is dead by design — what survives is `fundPrime` (`CauldronSeeder.sol:338-339`) still accepting ETH with both native egresses closed while `DeployLaunchpad.s.sol:536-541` instructs "Send 2-3Ξ". |
| K5c | MEDIUM | new | — | `CauldronSeeder.sol:838-842` blame `c3dc671`; no prior row covers `rescue()` reverting pre-campaign on `IERC20(address(0)).balanceOf` (the prior `Z04_SeederRescueStrandsLp.t.sol` PoC attacks a different rescue defect, LP stranding). |
| K5d | INFORMATIONAL | reconfirmed-safe | Z-17 — FIXED `9f04d9f` | Attacked the `poke()` sandwich again; bounded by exactly `9f04d9f`'s guards — ratcheted reference `:471-477`, `MAX_TICK_DEV :392`, `PRIME_SLIP_BPS :420-422` — and unreachable anyway while the seeder is dead. |
| K5e | LOW | still-open | Z-12 (OPEN) | `MiFrensGenesis.sol:268` blame `d8461b3`; Z-12 "MAX_PER_WALLET is a balance check" is OPEN and unchanged. |
| K5f | REFUTED by V5 | reconfirmed-safe | X5a — FIXED `038e4d7` | Cancel/ignite attacked again; `:286-295` + `:612-621` make cancel a documented safety valve with refunds — `038e4d7`'s `cancelled` check holds. |
| SUITE-1 | coverage (26 P0 failures) | fix-induced | `40b9608` (+ TEST-INTEGRITY, UNCHECKED) | Same commit as K5b: `SEED_BASE_WAD 0.15e18 → 1e18` was never propagated to the tests, so 26 tests fail on positive-control preconditions (`seeding()` false, `deployedWad()` 0) and its perp-fixture consequences; all currently open with `vm.skip` on the fork gate, so CI is green over a design change. This is a *coverage* row, not a vulnerability. |
| T6A | HIGH | fix-induced | (X7a/G1 area, different mechanism) | `useCauldronSwap.ts:181` blame `62614e2` ("ether is always the input, whatever the generation trades") and `:215` blame `41cda01` ("a completed rotation switched buying off entirely") — the ETH-zap added during the 09-11 fix window passes the caller's **whole quote balance** as `quoteIn`, and `CauldronGachaRouter.sol:278` pulls all of it; 400× overspend, live on xNVDA. |
| T6B | HIGH | fix-induced | X7a / G1 — FIXED `3a5a156` | `SwapWidget.tsx:188-196` blame `3a5a156` ("every buy and every sell signed a zero floor"): the real `minOut` that fix started signing is derived from an indexer `lastPrice` with no decimals term (`indexer/src/index.ts:27-31,292,321`, original `d8461b3`), so on a 6-decimal quote it is unreachable and every ERC20-quoted buy reverts — after the separate zap signature (`:189-190` then `:210`) has already spent the ETH. |
| T6C | LOW (downgraded) | still-open | A-3 (UNCHECKED) | `useCauldronMachine.ts:261` blame `35bf670` (2026-09-04, pre-audit); A-3 "indexer freshness gate wired on 1 of 19 consumers" was never re-tested and this is one of the 18 — floors read from an indexer HTTP number with banner-only health. |
| T6D | LOW (downgraded) | new | — | `indexer/seed-keeper.mjs` blame `99aae4b` (feature commit that created the file); no prior row covers the hardcoded `sepolia`, and `pokeInSwap` makes the keeper a fallback only. |
| T6E | LOW | fix-induced | X6d / F2 — FIXED `b502cac` | `api/brand.ts:104` blame `b502cac` ("a stranger could rewrite the live site's PFP and banner"): the fix authenticated the *write* path and left the unauthenticated GET running DDL per request, cache-bypassable with any junk query param. |
| T6F | REFUTED by V6 | reconfirmed-safe | — (no prior row) | `?chain=` is filtered by `isDeployChain` (`deployments.ts:43-45`); the chain-agnostic frontend work introduced no untrusted chain selection. |

### Bucket counts

| bucket | n | ids |
|---|---|---|
| new | 2 | K5c, T6D |
| still-open | 5 | H1-L2, T3a, K4d, K5e, T6C |
| fix-induced | 10 | T2c, T3d, T3b, T3e, T3f, K5b, SUITE-1, T6A, T6B, T6E |
| prior-fix-FAILED | 4 | T2a, T2b, T3c, K4a |
| reconfirmed-safe | 3 | K5d, K5f, T6F |
| dropped | 0 | — (see below) |
| missed-by-prior | 4 | K1a, H1-L3, K4c, K4b |
| **total** | **28** | |

**Nothing was dropped.** The two candidates both had the prior refutation answered with new
evidence, so per the rules they are bucketed normally: T2a vs **RH-R3** (RH-R3's `allowance()`
argument holds only for `maxTotalBps >= BPS_ONE`; `K2a` is the partial envelope) and T2b vs
**RH-R1** (RH-R1 assumed dust; `K2b`'s filer spends real voting power).

### Reconfirmed-safe — this run's refutations mapped to prior rows

Attacked hard and found closed, i.e. the prior fix or the prior PROVEN-SAFE verdict holds:
C-1 PoolKey/CREATE2 squat (`_afterInitialize:633 PoolInitRefused`) · X1b/O-4 surtax in-tx
manipulability (`69dc15d`) · X1a/X4a legacy-buffer denomination + proposerOwed (`f9c775f`) ·
R-01 + PS-gov rotator venue **and** floor on `swapOnce`/`arbStep` (`QuoteRotator.sol:359,:390,:393`) ·
RH-R3 `uint16 consume` overflow · M-1/X2b + X2n `_recoverLegs` loop bound and leg-proceeds booking
(`8237167`, `e6237a3`) · RH-R1 sub-quorum bench displacement · X3a/X3c cumulative-rewind underflow
and the relaunch token-denomination window (fixB) · F-02 `retirePayout` escrow burn (`efaed64`) ·
O-3 `_absorbPlvLoss` underflow (`1eff1d2` + `6459b85`) · X4c/X4c-2/X4e/F-04 `FeeRouteLib`
codeless-recipient checks (`02f4e8a`, `ddd7284`, `a3773fc`, `064b29e`; the unguarded `send` at `:207`
has zero call sites) · Z-09/T-2 `MintCurvePolicy` calibration bound (`f96d42f` + `a59a675`) ·
X4b churn `hookData` shape · Z-02 vault donation entitlement (`6f2ba20`, `accountedDeposits`) ·
X5a ignite-after-cancel (`038e4d7`) · X5b sniper selector (`79a3fed`) · X5f/X5g vesting grant
flooding (`20d6de2`) · X6c/A-1 fren-ask SSRF + prompt-injection pinning (`3c7d009`) · **A-6**
fren-teach auth including rightmost-XFF (`api/fren-teach.ts:60-64,84-88`) · X6h/X6i/X6j x-token
PKCE/state/allowlist and the liquidatoor `?col=` allowlist (`b8ec2b9`, `fec94bf`, `b9e4583`) ·
X6g indexer subscriptions (53 match declared events, `7890490`).

## Prior OPEN / UNCHECKED / DESIGN-DECISION / LEAD items this run did NOT re-test

No hunter executed these. They carry forward untested; nothing below should be read as coverage.

**OPEN** — DOC-2 (ETH floor vault never funded) *not re-tested* · DOC-3 (bits understated) *not
re-tested* · ACCESS-LOW-02 / INFO-03 / REENT-INFO-01 *not re-tested* · Z-03 / Z-04 / Z-05
(`CollectionLedger` under-credit, unchecked `_approve`, burned NFTs in the floor) *not re-tested* ·
Z-15 (factory `transferOwnership`) *not re-tested* · Z-13 / flat-lead-5 (`_castSpell` mutates after
two external calls) *not re-tested* · Z-06 / Z-07 / Z-16 (rounding dust, `creatureFor(0)`, no token
residual) *not re-tested*.
Two OPEN rows were touched incidentally, not audited: **REG-1** — T2a used the ungated facet stub at
`CauldronRegistry.sol:270-274` as its attack door, which re-confirms the root cause exists but is not
a re-test of the class; **F-06** — T3c shows `hasQuoteStake` is no longer dead code (`efaed64` wired
it into a revert), but the lost `observations` getter half *was not re-tested*.

**UNCHECKED** — **O-9** (live collection floor divides a forged-only pot by an OG-inclusive count,
`PoolOps.sol:1382`) *not re-tested*, still the highest-value untested prior item · **TEST-INTEGRITY**
(nine `vm.warp` helpers CSE'd under `via_ir`; `test_FullLifecycle_ToRound3_OnFork`) *not re-tested* —
that test appears in `BASELINE_FAILURES.md` as a P0 failure, but the CSE/one-generation question was
never audited · **A-2** (unbounded public GraphQL, no byte cap) *not re-tested* · **A-5** (immutable
`emergencyAdmin`) *not re-tested*. A-3 is carried as still-open via T6C; A-6 was re-tested and held.

**DESIGN-DECISION** — X1h (jitter block-shoppable; H1 refuted only *in-tx* manipulability) *not
re-tested* · O-3 (`plvToken` assigned, not adjusted) *not re-tested* — T3b is the neighbouring
`tokYield` counter, not this one. O-2 was re-tested (T3a).

**LEAD** — prior-M / RH-L2 (`legacyThreshold` scalar vs per-asset 6-decimal buffer) *not re-tested*
(H1 refuted buffer *denomination* generally, not the threshold) · REHUNT-lead (anti-sniper window in
BLOCKS vs volume window in SECONDS) *not re-tested* — K1a is a different defect in the same window ·
FS-L3 / FS-L4 (`setPolicies` overwrites all three slots; `quoteOracle` never unsettable) *not
re-tested* · flat-lead-3 (hook volume collapses with no oracle wired) *not re-tested* · RH-L5
(`NotPriceable` may make "rotate home to ether" unreachable) *not re-tested* · flat-lead-1
(sequencer-restart grace as a scheduled window) *not re-tested* · RH-L1 / RH-L4 (`_pullQuote` accepts
empty returndata; `claimPendingEth` banks a zero) *not re-tested* · FS-L1 (`castSpell` may be
unusable for a whole generation) *not re-tested* · FS-L2 / FS-L5 (`setDividend` re-settable to zero;
320k gas floor per move) *not re-tested* · RH-L3 (`vaultSwept` native wei stranded on a non-native
rebirth) *not re-tested*. RH-L6 (9th mandate invisible to the 8-slot bench) and flat-lead-6
(`_leadVotes` poisoning) **were** exercised — see T2c and T2b.

## Verifier discards (P2)

- **Refuted: 3** — K5f (cancel is a documented safety valve with refunds), T6F (`?chain=` filtered by
  `isDeployChain`), and the **K5b-as-Critical** framing (the progressive seeder is dead *by design*
  per `40b9608`, not by a bug; only the `fundPrime` trap survives, at MEDIUM).
- **Downgraded: 8** — T3c (Critical→HIGH), T3a, K4a, K4b, K5b, K5d (→INFORMATIONAL), plus T6C and
  T6D (→LOW).

## PoC presence in the real tree

All ten surviving PoCs were already present under `contracts/solidity/test/attacks/` (untracked
before this commit); **none had to be copied** from `/tmp/blind-final-h<N>/`.

| PoC | bytes |
|---|---|
| `K1a_StaleVolumeKeepsAlive.t.sol` | 5650 |
| `K2a_PartialEnvelopeStarve.t.sol` | 6808 |
| `K2b_MandateErasedAfterVoteCloses.t.sol` | 7729 |
| `K2c_RelaunchStalledByOpenBrews.t.sol` | 5346 |
| `K3a_StaleQueueEatsDeposit.t.sol` | 5721 |
| `K3b_TokYieldLockout.t.sol` | 7350 |
| `K3c_RotationStrandsPerpEngine.t.sol` | 9393 |
| `K4a_RoyaltyErc20Strand.t.sol` | 5193 |
| `K4b_GachaReanchorGrind.t.sol` | 5209 |
| `K5b_ProgressiveSeederUnreachable.t.sol` | 8699 |

Not run in this phase, by instruction. T3d, T3e, T3f, K4c, K4d, K5c, K5e and H1-L2/H1-L3 are derived
findings with no PoC; T6A/T6B/T6C/T6D/T6E are off-chain and were verified by reading, not by Foundry.
