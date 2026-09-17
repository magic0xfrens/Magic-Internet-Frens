# FINAL BLIND REVIEW — 2026-09-13

Third blind red-team of the Cauldron protocol, run against the working tree 173 commits after
the 09-11 run (which itself was two remediations after the 09-08 one). Orchestrator + 6 blind
hunters + 6 blind verifiers + reconciliation against every prior artifact + 5 fixer groups + a
blind neighbourhood re-hunt of the day's own fixes + a 3-agent coherence pass. Every finding
below carries a `file:line` an agent read, a PoC that ran with `-vv`, and a verifier verdict.
Branch `redteam/2026-09-13`; snapshot `a19550e`; nothing pushed.

---

## 1. Verdict

**Not to mainnet today. Deploy r45 to testnet and run one more short blind pass on the diff —
then yes.**

Two Criticals were reported and both were downgraded by execution: the "engine stranded forever"
is healed by the dust staker's own withdrawal or the next relaunch, and the "dead seeder" is a
documented design choice. What was real: **eight Highs**, every one with a passing PoC, every one
now fixed with an inverted regression test — a dust swap a day that suspended permissionless
relaunch indefinitely (an off-by-one that turned out to be two bugs), eight junk filings that erase
a passed mandate after voting closes in *both* governors, a partial envelope spendable from any
leg, one wei of stake that parks the perp engine, a rotation over an open book that force-closes
solvent positions at zero slippage, and a frontend that spent a user's *entire* quote balance on an
ERC20-quoted buy while pricing 6-decimal quotes 4e8× off.

Answering the real question — *is anything hidden still there*: **yes, and it was hidden where the
method predicted.** 14 of the 28 verified findings live in or follow from code a prior remediation
wrote; 4 prior fixes had never actually held. Today's fixes then produced **three more bugs of
their own**, found by the blind re-hunt and closed in the same session. The pattern is stable
across three runs: freshly patched code is the richest hunting ground. That is why the deploy
answer is "after one more pass on the diff", not "now".

---

## 2. Value & authority map — merged from the six blind models

Built by the hunters from code before any prior document was opened. Cited lines are the blind
tree's, identical to the real tree at snapshot `a19550e`.

**Adoption and orientation.** `CauldronHook._afterInitialize` (`CauldronHook.sol:625`) is the
only gate that matters: `require(sender == registry)` (`:633`); everything else keys off
`trackedPools[id]` and `quoteIsCurrency0[id]`, written only there. The quote is always currency0
in practice: `PoolOps.deployTokenAbove` (`PoolOps.sol:748`) mines the token above
`QUOTE_WATERMARK` (`:713`) and `setAllowedQuote` (`CauldronRegistry.sol:314`) refuses any quote
at or above it and refuses to de-list native.

**Swap path.** `_beforeSwap` (`:1221`) charges exact-input buys and refuses the exact-output sell
quadrant. `_afterSwap` (`:782`) in order: legacy buyback → seeder poke → volume (`_toUsd :745` →
`_recordVolume :1553`) → crystal credit → perp `sweepLiquidations(tx.origin)` (`:950`) → gacha
self-call → `_takeEthFee` (`:1488`) → legacy buyback again. Every side-effect call is gas-capped
and result-ignored; all four `MIN > RESERVE`, so no `gasleft()` underflow.

**Native value in/out.** In: `poolManager.take` (`:1517`), permissionless `fundLegacyBuffer`
(`:1148`), trader collateral (`PerpEngine._pullQuote`), vault deposits, `fundInsurance`, genesis
`mint`, `CauldronVault.receive` (counts only registry/minter deposits into `accountedDeposits`).
Out: `FeeRouteLib.routeSplit` (delegatecall; checks `to.code.length` before every native send and
never reverts), `legacyBuyStep` (self-only, `_liveKey` only), `claimProposerFees`,
`releaseRelaunchETH/Asset` (registry-gated), perp `_payOut`/`_pushQuote`, vault withdrawals.

**Death → relaunch.** `isDead` (`:1656`) sums `getVolume24h` plus up to `MAX_SIBLINGS = 9`
linked siblings (`linkVolume :1624`, registry-only). `CauldronRegistry.relaunch()` (`:821`) gates
on `hook.isDead` (`:832`), `minLifetime` (`:836`), `governor.hasProposals()` (`:840`), consumes at
`markConsumed` (`:1031`); everything right of that line must be total or the machine bricks.

**Governance.** `TreasuryGovernor.propose` needs 5 MiFrens, an allowlisted priceable quote, no
live envelope, cooldown; `vote` snapshots at `block.number-1`; `execute` is permissionless and
requires `id == winner()`, where `winner()` is an O(1) hint validated by `_executable` plus an
8-slot bench keyed on FOR votes. `CauldronGovernor.propose` has no threshold. `allowance()` /
`consume(bps, fromPrimary)` are registry-only writes.

**Rotation.** `RedemptionExt` is a delegatecall facet reached through `CauldronRegistry` stubs
(`:246/:270/:280/:296/:306`, `_forwardToExt :1505`). `rotateSliceFrom(fromLeg, sliceBps, minOut,
route)` is **permissionless**: it removes a slice from the named leg, swaps through
`QuoteRotator.swapOnce` (venue allowlist by `PoolId`, floor from the uncached oracle,
`NotPriceable` when unpriceable, fill ≥ `max(minOut, floor)`), unwinds and re-mints the
destination leg, `linkVolume`s it, then `consume(sliceBps, fromLeg == 0)` and — only on a spent
migration mandate — flips `generationQuote` and best-effort `syncGeneration`.

**Perps.** One engine serves every generation. Permissionless: `openLong/openShort`
(`_guardOpen`), `close`, `liquidate` (`_liqTest` + `_throttle`), `forceCloseDead/AllDead`
(`_isDead()` only, MODE_DEATH), `syncGeneration`, `retirePayout` (owner, or anyone once `quote`
diverged). `hookAddr`-only: `sweepLiquidations`, `creditPerpFee*`. `onlyVault`: `fundFromVault`,
`withdrawPlvTo`, `withdrawTokYieldTo`. `onlyOwner` (timelock): `setRouting`, `setVault`, fees,
risk, tiers. `quote` is a *cache* assigned only in `syncGeneration`; `registry.generationQuote` is
truth; `_isDead()` = quote divergence OR `hook.isDead(primaryPoolId)`. `PerpVault` prices both
sides off engine counters (`totalEth() - pendingEth`; a MasterChef accumulator paying short-side
yield from `tokYieldEth`).

**Token / NFT.** `CauldronToken` mints once to the registry; `burn` is `onlyRegistry` and both
reachable callers bind `from`. `CauldronCollection.mint` is `minter`-only (the hook), capped; the
reveal re-anchors once then commits tier 0. Gacha (`play/playLiq/playChurn/openReady`) pulls the
generation quote (native XOR ERC20) and seeds outcomes from `blockhash(commitBlock)`
(`CauldronHook.sol:2388-2406`). Volume-collection royalties go to a per-brew `RoyaltyRouter`
(`CauldronFactory.sol:81-82`) forwarding into `fundLegacyBuffer`.

**Genesis / seed / deploy.** `MiFrensGenesis.mint` caps on `balanceOf`; `cancelPresale` is
deployer-only and irreversible with refunds; `igniteCauldron` forwards the balance to
`registry.summon`. `summon` (`owner() || igniter`, one-shot) deploys the token and dispatches
PROGRESSIVE only when `seeder != 0 && nextSeedWindow > 0`; with `SEED_BASE_WAD = 1e18`
(`PoolOps.sol:168`, deliberate since `40b9608`) the campaign never starts and the whole base is
laid full-range at summon. `CauldronSeeder.startSeed` is onlyRegistry; `fundPrime` is
deployer/registry-owner; `withdrawAll`/`rescue` onlyRegistry. `DeployLaunchpad.s.sol` wires
hook→registry, openers, `setIgniter(presale)` then `transferOwnership(timelock)`.

**Off-chain.** Six Vercel routes; only `fren-teach` is authenticated (shared secret,
`timingSafeEqual`); `x-token` is PKCE with an allowlisted redirect; rate limits key on `x-real-ip`
then the rightmost XFF hop. Frontend writes go through `CauldronGachaRouter.play/playChurn`,
`useTreasuryRotation.rotateSlice` (minOut from an on-chain `quoteSlice()` re-read), `usePerpEngine`.
Both swap floors derive from `spotPrice`, which the indexer computed as a raw sqrtPrice ratio.
53 indexer subscriptions all resolve to declared events.

---

## 3. Findings (severity after verification; fix commits on `redteam/2026-09-13`)

### High

| id | location | mechanism | precondition | impact | PoC | conf. | fix | regression |
|---|---|---|---|---|---|---|---|---|
| K1a | `CauldronHook.sol:1558,:1584` (`>` vs `>=`) and the mod-24 bucket ring | one dust swap a day at delta ≤ 86400 in the same hour-bucket keeps 30-day-old volume in `getVolume24h`; `isDead()` never flips; `relaunch` reverts `TokenStillAlive` | none; no minimum swap size (`:840`) | permissionless relaunch suspended for ~70k gas/day; only escape is the timelocked `setDeathChecker` | `K1a_StaleVolumeKeepsAlive` | VERIFIED | `146a08f` — ring measures absolute elapsed hours; the 86399 cadence was a **second** bug the briefed one-char fix would not have closed | same file, 3 cadences × 30 days, reports 1 wei |
| T2a | `TreasuryGovernor.sol:775,:855` via `CauldronRegistry.sol:270-274` → `RedemptionExt.sol:280,:514` | partial envelopes meter on the shared `movedBps`; one permissionless `rotateSliceFrom(fromLeg=1, 2500, …)` spends the whole voted budget from a secondary leg; `COOLDOWN` locks the guild 7 days, repeatably | a secondary leg in another quote exists | governance lockout; no value stolen (venue- and oracle-floored) | `K2a_PartialEnvelopeStarve` | VERIFIED | `5b2f2b5` — every envelope meters and deactivates on `movedPrimaryBps` | `test_K2a_*` (3) |
| T2b | `TreasuryGovernor.sol:525-541,:696-712` | `_benchRecord` admits OPEN proposals at full weight; 8 filings after the vote closed evict a PASSED mandate; `execute` (`:566`) has no by-id path; the comment at `:713-728` describes a scan that is not in the code | 5 MiFrens + power > mandate FOR; no deposit/fee/cooldown | mandate erased after the window; attacker's envelope installs (owner-allowlisted quote only) | `K2b_MandateErasedAfterVoteCloses` | VERIFIED (mutation-tested) | `5b2f2b5` — lexicographic eviction: unprotected-before-executable, then fewer votes; comment corrected | `test_K2b_*` (2) |
| T2c | `CauldronGovernor.sol:689-706,:812-826,:731-733` → `CauldronRegistry.sol:841` | same root cause; `hasProposals()` goes false with a settled mandate; `vote` demotes `_leaderId`→`_runnerId` then overwrites; `:652 VotingClosed` means the evicted brew can never be re-benched | power > the guild brew's total; `propose` has no threshold | **permanent hijack of the rebirth**, gated on out-voting | `K2c_RelaunchStalledByOpenBrews` | VERIFIED | `c660538` | `test_K2c_*` |
| T3c | `PerpEngine.sol:1337` (`VaultStaked` on `hasQuoteStake()`), `RedemptionExt.sol:582,:617`, `_isDead :1797`, `setVault :2435` | 1 wei of quote-side stake vetoes `syncGeneration`; the facet swallows it; engine parks dead; `setVault(0)` vetoed by the same dust; `DeployPerp.s.sol:235` creates the staker | any rotation | engine parked for a generation; every open position `forceCloseDead`-able by a stranger — downgraded from Critical: the staker's own `withdrawEth` or the next relaunch heals it; NOT owner/timelock/registry | `K3c_RotationStrandsPerpEngine` | VERIFIED | `7b805e2` — timelock (`owner()`) override always adopts; the `setVault` veto is **kept on purpose** (relaxing it reopens an ETH-principal hole a prior fix closed) | `K3c` 5/5 incl. `test_FIXED_theOverrideIsOwnerOnly` |
| T3d | `PerpEngine.sol:844` `blocksVolumeLink`, `CauldronHook.sol:1626`, `RedemptionExt.sol:606,:1278`, `forceCloseDead :1162` | with a mark source armed (the deployed state) the interlock is off; the quote flips over an open book; `PositionsOpen` swallowed; solvent positions force-closed at literal `minOut 0` with a keeper cut | rotation with open positions | value extraction by keepers on solvent positions | none at hunt → `K3d_DeathBandProtectsForcedClose` (6/6) written at fix | DERIVED→VERIFIED | `7b805e2` + `7007326` — `MODE_DEATH` fills only inside ±10% of the engine's own TWAP by capping the sqrt-price limit (`PerpSwapLib.bandLimit/closeLimit`); the remainder rebooks or is written off, so LIQ-02's "always clearable" still holds (XL1 5/5); a double-band bug in the first cut was caught and fixed in the same commit | `K3d`, `XL1` |
| T6A | `src/hooks/useCauldronSwap.ts:181,215` → `CauldronGachaRouter.sol:278` | ERC20-quoted `buy()` passes the wallet's ENTIRE quote balance as `quoteIn` with a floor sized for the typed amount; `_pullQuote` takes it all; nothing refunded | ERC20-quoted generation (live on xNVDA) | 400× overspend measured | `/tmp/blind-h6/poc_a_full_balance.mjs` | VERIFIED | `6504a11` — typed amount in quote decimals, bounded approval, floor scaled to actual zap delivery | `scripts/test-quote-units.mjs` pins the 400× factor |
| T6B | `indexer/src/index.ts:27-31,292,321`, `SwapWidget.tsx:186-199` | `lastPrice` is a raw ratio with no decimals term; 6-dec quotes are 4e8× off; every ERC20-quoted buy signs an unreachable floor and reverts AFTER the zap (two signatures) already spent the user's ETH; mcap/charts wrong | 6-dec quote | stranded zap output + gas per attempt; USDG buys impossible | `poc_b_quote_units.mjs` | VERIFIED | `fe94a40` — indexer records `lastPriceRaw` + decimals-normalised `lastPrice`, `quoteDecimals`; schema `cauldron_r44c` | same script (1e12 factor) |

### Medium

| id | location | mechanism | fix |
|---|---|---|---|
| T3a | `PerpVault.sol:196,238,325` | after a loss leaves `pendingEth > totalEth`, a stale queued exit takes 100% of a fresh deposit (downgraded: the state is a public read) | `7b805e2` `deposit` reverts `QueueInsolvent()`; the latch this created (Jb) fixed in `58e1a55` |
| T3b | `PerpEngine.sol:1359`, `:2296` | rotation zeroes `tokYieldEth` not `tokYieldCumulative`; all-or-nothing `claimTokYield` reverts forever | `561f0f7` epoch tag in PerpVault (zero engine bytes; storage append-only); boundary bug (Ja) fixed in `899efc4` |
| T3e | `PerpMarkSource.sol:173`, `PerpEngine.sol:666-684,:1384` | `weightedTick()` fails OPEN (tick 0 = 1:1) unarmed; no sanity check; source not cleared on relaunch | `7b805e2` reverts `NotArmed`; cleared on every sync — which re-armed the hostage (Jc), resolved in `581ab37` |
| K4a | `RoyaltyRouter.sol:35-46`, `CauldronFactory.sol:81-82` | receive-only ERC-2981 receiver: WETH/USDC royalties stranded forever (downgraded from High: no transfer validator, so it is voluntary third-party royalty) | `0503a09` constructor `(hook, erc20Sink)`, permissionless `sweep(address)` to the genesis dividend + `adopt`; `receive()` never reverts a sale (K4d) |
| K4c | `CauldronGachaRouter.sol:369,:470,:496,:518` | `playChurn` has no `minOut`; legs at MIN/MAX sqrt; caller sandwiched for ~8000× measured | `0c80fe9` `playChurn(quoteIn, loops, minTokenOut, openMax)` — ABI change, frontend updated |
| K5b (residual) | `CauldronSeeder.sol:338-339,:632,:842`; `DeployLaunchpad.s.sol:536-541` | seeder dead BY DESIGN (`PoolOps.sol:157-167`), but `fundPrime` accepts ETH with both exits closed; script tells the operator to "Send 2-3Ξ" (downgraded from Critical) | `ca2b76e` `refundPrime(address)` for the funding principal while no campaign ever started; script text corrected |
| K5c | `CauldronSeeder.sol:838-842`, `_teardown :662` | `rescue()` and `withdrawAll` call `IERC20(address(0)).balanceOf` pre-campaign and revert — the teardown could never return the prime budget | `ca2b76e`, `0123c3b` |
| H1-L3 | `CauldronHook.sol:773,:1644` → `RedemptionExt.sol:473` | `MAX_SIBLINGS = 9`; at 9 even re-linking a KNOWN quote reverted (PoC `K1b` contradicted the verifier's note); a 10th distinct quote still reverts and no unlink exists | `858d8ae` re-link fixed byte-free; **accepted residual**: `unlinkVolume` needs 278 B vs 41 free — rides the hook split |

### Low

T3f `_rebook` zeroes collateral so the remainder pays no funding/penalty (released: changes documented
loss seniority) · K4b uncapped ticket re-anchor (downgraded: one unprivileged `resolveTickets` or any
swap's auto-resolve defeats it; no fix) · K4d stipend payer reverted the sale (fixed `0503a09`) · K5e
per-wallet cap on `balanceOf` (released: fresh EOAs sweep identically; a counter breaks a regression) ·
H1-L2 `_getHolderTaxRate` uncapped, dormant (`nftContract == 0`; clamped 17 B in `858d8ae`) · T6C
floors from an unauthenticated indexer number (mitigated by T6B) · T6D seed-keeper hardcodes sepolia
(in-swap poke is the primary) · T6E brand DDL per request (fixed `d8ed3af`).

### Refuted by verifiers (not to re-raise with the same argument)

K5f deployer cancel (documented safety valve with refunds) · T6F `?chain=` (filtered by
`isDeployChain`) · K5b-as-Critical (design, not bug) · T3c-as-Critical (self-healing by the staker) ·
Jd (see §4) · plus 3 downgrades above.

### Suite

SUITE-1 — 26 tests failed at P0, all `[PASS]` at the 09-11 baseline: `40b9608` deliberately set
`SEED_BASE_WAD 0.15e18 → 1e18` and no fixture was updated; every one opened with `vm.skip(!fork)`,
so CI stayed green while the launch suite was dead. Repaired without a single skip or loosened
assertion (`6b3b854`, `980272c`, `a4ebab3`, `5403847`); the anti-snipe property was relocated to
`snipeSurtaxBps`; one parameter was genuinely obsolete (named in `a4ebab3`); 7 of 8 perp fixtures
were killing their own victim inside the crash dump's afterSwap sweep because of LIQ-01's spot
trigger. The "0.17 ETH stranded in the seeder" a rewrite surfaced was the fork's own balance at the
CREATE address, verified with `cast balance`, not ours.

---

## 4. Neighbourhood re-hunt of today's changes (blind, one round)

| id | sev | where | what today's fix did wrong | fix |
|---|---|---|---|---|
| Ja | High | `PerpVault._syncTokYield` (`:421-453`) | the epoch split-fold was guarded by `cut > last`, false whenever the vault was synced at rotation time (the common case): `epochAcc` stamped above the post-rotation accrual, all new yield forfeited and stranded | `899efc4` — `cut` clamped into `[last, cum]`, split is the only shape; `Ja` 2/2, K3b 3/3 |
| Jb | Medium | `PerpVault.sol:274,:381,:393` | the `QueueInsolvent` guard latched: `claimPendingEth` reverted `ZeroAmount` when `freeEth == 0`, rolling back the haircut it had just written | `58e1a55` — banks the write-down and returns 0 |
| Jc | High | `PerpEngine.sol:1454,:874` | clearing `markSource` on every sync re-armed `blocksVolumeLink()` after each relaunch: one ~0.0007 ETH dust position held treasury rotation hostage until the timelock re-armed — the hostage "armed at birth" was meant to remove | `581ab37` — the interlock releases whenever the engine has its own usable TWAP, because the death band now prices any rotation-time forced close off that TWAP; re-arming after relaunch is a quality choice, not a liveness gate |
| Jd | — | `TreasuryGovernor.sol:817,:913` | claimed a secondary-only envelope never deactivates and locks `propose` | **refuted by execution** (`fbedeef`): the envelope is live because its primary budget is still spendable; the proposed fix would have reinstated T2a verbatim |

Six changed shapes held under attack: the absolute-hour volume ring, band direction and the
tighter-of-two limits, the reverting `weightedTick`, `RoyaltyRouter.sweep/adopt`, both bench
comparators, every `playChurn` caller.

---

## 5. Leads — believed real, not demonstrated

- `claimPendingToken` carries the byte-identical `paid == 0 → revert ZeroAmount` rollback as Jb; it
  cannot latch a deposit guard (there is none on the token side) but it is the same shape (fixPERP).
- A native buffer stranded on a rotated no-vault generation (H1-L1); no registry-side clamp on
  `spec.mode`/`spec.renderer` after a governor swap (H1-L4).
- Native-ETH `NotPriceable` on the way back to ether; a de-priced leg that can no longer be
  rotated; `cancel` on a phantom id; `arbStep`'s capital claim; a dead `_settled` (H2).
- Adopt-timing windfall; `_curvePos` underflow on collection re-set; `setTransferValidator` as a
  collection-wide brick (H4).
- Proposal-string link phishing in the governor UI; whether Vercel forwards a client `x-real-ip`;
  creature-route RPC amplification; a frozen `prev.spotPrice` (H6).
- Full lists with next steps: `hunt/H*.md` §4, `REHUNT.md` §4.

---

## 6. Proven safe — attacked hard, held

PoolKey/CREATE2 squat (`_afterInitialize:633`, `PoolInitRefused`) · poisoned `BrewSpec` past
`markConsumed` (`BadRenderer`) · `_curvePos` underflow · all four in-swap gas reserves · legacy-buffer
denomination and `proposerOwed` · in-tx surtax steering · rotator venue + oracle floor on
`swapOnce`/`arbStep` (`QuoteRotator.sol:359/:390/:393`, verifier-agreed) · sub-quorum bench
displacement · `consume` uint16 overflow · `_recoverLegs` loop bound (owner-allowlist-bounded,
verifier-agreed) · leg-proceeds double booking · `redeemOgFren` underflow · renounce dead-ends ·
cumulative-rewind underflow · share inflation · `retirePayout` escrow burn · `_absorbPlvLoss`
underflow · the relaunch token-denomination window · `adopt` double-pay · ledger redeem/buyback
round-trip · `CauldronToken.burn` without allowance · MintCurvePolicy calibration bound ·
FeeRouteLib codeless-recipient checks on every live native leg (`:116/:156/:180/:249`; the unguarded
`send :207` has zero call sites, verifier-agreed) · churn hookData · vault donation entitlement
(`accountedDeposits`, verifier-agreed) · ignite-after-cancel · sniper selector · badge dilution ·
vesting grant flooding · igniter wiring order · `dist/` secret scan · all 53 indexer subscriptions ·
x-token PKCE/state/allowlist · fren-ask SSRF + prompt-injection pinning · fren-teach auth and
rightmost-XFF keying (verifier-agreed) · liquidatoor `?col=` allowlist · "sells revert"
(`PoolOps.sol:269`) · the six re-hunt shapes above.

---

## 7. Coverage gaps

- 26 launch/perp tests were dead behind `vm.skip(!fork)` for a day and CI was green (fixed; the
  gate now requires the skip count not to grow).
- T3d and Jc were DERIVED at the hunt; both now have non-fork PoCs (`K3d`, `Jc`) written at fix
  time — a PoC-less High is a gap until it is not.
- `ProgressiveSeed.t.sol` and its siblings now prove the full-range design; the dormant streaming
  machinery has no live test and none is possible without lowering `SEED_BASE_WAD`.
- 30 prior OPEN / UNCHECKED / LEAD / DESIGN-DECISION items were **not re-tested** this run
  (`RECONCILIATION.md`, "not re-tested"); notably O-9 and the `via_ir` test-integrity item.
- The function graph is stale for 65 added / 10 removed / 78 changed / 14 moved nodes
  (`audit/graph/CHANGES_SINCE_2026-09-11.md`); re-extraction needs the second brief's roster.
- Three coherence Lows left undone by budget: `LegOpened` indexer handler, presale `refund()`
  button, `EnvelopeConsumed` over-reporting.

---

## 8. Decontamination

First pass removed 759 finding-ID tags from comments; `wc -l` per file identical; every
non-test contract byte-identical between real and blind trees. Second pass added three-letter tags
(LIQ-/LEG-) and string literals in `test/` only, found and fixed three bugs in its own stripper, and
discovered `test/audit/` (21 PoC files) had been silently *excluded* rather than quarantined by an
unanchored `rsync --exclude audit` — corrected (`d9107a9`). Final residual: **one** hit,
`deploy/DeployLaunchpad.s.sol:195` `"… (audit F-19)"` in a `require` string, left in place.
Leaks that cannot be removed by a stripper and are recorded honestly: review-shaped prose
("MEASURED DEAD END, DO NOT RETRY"), fix-encoding identifiers (`reanchored`, `accountedDeposits`,
`MIN_SEED_UNITS`, `priceRef`, `_syncRef`, `_bench`, `failedReads`), and the orchestrator's own
memory, which names prior findings (hunters and verifiers were told to ignore it; the orchestrator
never hunted). Full detail: `DECONTAMINATION.md`.

---

## 9. Reconciliation (P3) against 112 prior rows

| bucket | n | items |
|---|---|---|
| new | 2 | K5c, T6D |
| still-open | 5 | H1-L2/DOC-1, T3a/O-2, K4d/Z-14, K5e/Z-12, T6C/A-3 |
| fix-induced (prior runs) | 10 | T2c←`b3a9026`, T3d←`20df254`, T3b←`efaed64`, T3e←`1eff1d2`, T3f←`03469bb`, K5b+SUITE-1←`40b9608`, T6A←`62614e2`/`41cda01`, T6B←`3a5a156`, T6E←`b502cac` |
| **prior-fix FAILED** | 4 | T2a←X2a/C-3/R-04 `89aa06d` (partials still on the shared meter); T2b←X2d/B-10 `b3a9026` (landed only in CauldronGovernor); T3c←F-01 `efaed64` (veto moved sides); K4a←X1e `8fa52c6` (native path only) |
| reconfirmed-safe | 3 | K5d/Z-17, K5f/X5a, T6F |
| dropped | 0 | T2a and T2b answered prior refutations with new evidence |
| missed-by-prior | 4 | K1a, H1-L3, K4c, K4b |
| **fix-induced (today)** | 3 | Ja, Jb, Jc |

Verifier discards: 3 refuted, 8 downgraded, 0 not-verified. All 10 hunt PoCs were already in
the real tree; none needed copying.

---

## 10. Fixes and space

62 commits on `redteam/2026-09-13` from snapshot `a19550e` to this report (fix and test commits
plus audit artifacts and gate rounds; see `git log`), one per finding except where the owner's blanket `71396b6 "push"` at 16:59 swept four fixers' in-flight
work into one commit (flagged in the ledger, not rewritten). No `refactor(size):` commit was
needed: every byte was found inside the contract being fixed. Measured under viaIR and logged as
do-not-retry: `_openPrep` fold +210 B, `maxLev`→PerpSwapLib +94, `this.markSqrtPriceX96()` +62,
`_band` inlined twice +1,191 (hoisting it to one call site −921); `unlinkVolume` in the hook +278.

| contract | P0 | final | free |
|---|---|---|---|
| CauldronHook | 24,530 | 24,535 | 41 |
| CauldronRegistry | 24,492 | 24,492 (untouched) | 84 |
| PerpEngine | 24,460 | 24,509 | 67 |
| PoolOps | 24,006 | 24,006 (untouched) | 570 |
| PerpVault | 8,002 | 9,260 | |
| PerpSwapLib | 6,310 | 6,783 | |
| TreasuryGovernor | 6,653 | 6,646 | |
| CauldronGovernor | 9,302 | 9,341 | |
| CauldronSeeder | 15,260 | 15,453 | 9,123 |
| RoyaltyRouter | 293 | 1,295 | |
| CauldronGachaRouter | 8,580 | 8,814 | |

ABI / schema changes (all in the ledger): `RoyaltyRouter(hook, erc20Sink)` + `sweep(address)`;
`playChurn(quoteIn, loops, minTokenOut, openMax)`; `CauldronSeeder.refundPrime(address)` +
`PrimeRefunded`; PerpVault `QueueInsolvent()`, `yieldEpoch()/stakerEpoch()/epochAcc()/
totalTokYieldPulled()`, `TokYieldForfeited`; PerpMarkSource `NotArmed()`; indexer schema
`cauldron_r44b → r44d` (`pool.quoteDecimals/lastPriceRaw`, `dividend_asset`, `perp_position.
sizeRemaining/writtenOff`) — **a clean reindex is required**. Every contract touched needs a
redeploy (r45).

Suite (fork env, `--threads 2`): P0 **211 suites / 858 passed / 26 failed / 1 skipped** → first
gate **228 / 912 / 13 / 1** (all 26 P0 failures repaired; 13 NEW, every one a prior-run PoC or
regression whose asserted behaviour today's fixes changed — 9 inverted, 6 fixture repairs, 0
contract changes, 0 loosened assertions; `cf6ad0f`, `33bd29b`, `7da1cdb`, `88eecb1`) → final
re-run **228 / 884 / 6 / 1**, where the 6 are `vm.createSelectFork` timeouts in `setUp()` against
the public Sepolia RPC; re-run once by contract, **42/42 pass** — effective **0 failing, 1
skipped**. The skip count did not grow. `npm run type-check`, `npm run build`, `npm test`
(13/13): green. Details and the failure lists: `GATE.md`.

---

## 11. Coherence

`FUNCTIONAL_COHERENCE.md`: 1 High / 10 Medium / 15 Low; none can lose a user's funds. The
contracts are now the most coherent layer; the frontend and indexer lagged three generations of
ABI (an ERC20 dividend basket the UI could not show or claim, undecoded perp events and errors, a
native-only churn path, rarities rendered one tier low), and the docs described the launch
mechanism switched off in `40b9608`. All Highs and Mediums fixed (`fc0bb01`, `9280861`,
`86fbeb6`, `066bf18`). The incentive that breaks first is operational: re-arming the mark source
and calling the royalty sweep now have a keeper and a button, but did not before today.

---

## 12. Blind spots — what this run could not reach or run

- Fork tests ran on the public Sepolia RPC; Arc was not forked or tested at all.
- The owner committed to the branch during the run (`0d2c39c` Arc trading + timelock arming,
  `71396b6`); those hunks were inside the re-hunt's diff range but had no dedicated hunter.
- **`54e2775` "fix(perp): opens gate on a RISK-SCALED insurance floor, not a static one"** edited
  `PerpEngine.sol` (24,509 → 24,499 B) after the re-hunt ran, with no ledger row and no hunter on
  it. It changes the open gate. It is the one contract change on this branch nobody attacked.
- One round of re-hunt only, by design. It found three bugs in the day's fixes; the fixes to
  those three have had no blind pass.
- Design decisions not made for you: the `setVault` dust veto is kept (timelock override is the
  exit); the 10th-sibling-quote residual rides the hook split; the streaming seeder stays dormant.
- 30 prior items not re-tested; graph not re-extracted; three coherence Lows open.
- Blinding was comment-level, not total (§8).

---

## Final line

**Would I deploy this to mainnet today? No — not because of what is open, but because of what the
last three days proved about fresh fixes. Deploy r45 to Sepolia + Arc with the r44d reindex, run
one short blind pass on `a19550e..HEAD`, and if that pass comes back empty, yes.**
