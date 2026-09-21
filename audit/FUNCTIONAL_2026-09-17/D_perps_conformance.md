# Area D — perps, vault, liquidation: functional conformance

**Tree:** branch `main` @ `9c27596`. **Profile:** `FOUNDRY_PROFILE=cauldron`.
**Spec checked against:** `audit/spec/FUNCTIONAL_SPEC.md` + `audit/spec/sections/E_D_spine_rotation_perps.md`, both dated 2026-09-10.
**Executed this pass:** `test/attacks/M1a_LiqGasBand.t.sol` (1 passed, 0 failed, 0 skipped), `test/attacks/LIQ04_GasStarve.t.sol` (0 passed, **1 failed**, 0 skipped). Logs `/tmp/m1a.log`, `/tmp/liq04.log`. No source or test was changed.
**Not re-measured by me:** contract sizes (I quote c20671a's numbers and say so).

---

## D-01 · The spec does not cover area D · SPEC-STALE (headline)

FEATURE: area D as briefed — vault staking, PLV, insurance, `fundFromVault`, `openLong`/`openShort`/`close`, `liquidate`, the in-swap sweep, funding, marks, bad debt, queued exits, badges.

INTENT: `FUNCTIONAL_SPEC.md:90` routes area D to `sections/E_D_spine_rotation_perps.md`.

ACTUAL: that file is 195 lines and is **entirely** about denomination totality, the P-1 interlock, the post-rotation quote window and facet reachability. It contains no statement about deposits, withdrawals, the exit queue, insurance, the waterfall, funding, the mark band, the sweep, gas gating or badges. The conformance matrix has exactly two area-D rows (`FUNCTIONAL_SPEC.md:321-322`: "Perp quote follows rotation", "P-1 interlock") plus one badge row (`:312`).

DELTA: for ~90% of the briefed surface there is no spec to be stale against. The question "does the spec still describe the code" has no answer for the vault or the liquidation engine, because it never described them. Everything below is therefore checked against **NatSpec + commit intent + tests**, and where those disagree with the code that is the finding.

CLASS: `MISSING` (spec), and it is the largest conformance gap in area D.

IMPACT: every prior audit of this surface has been checking code against code.

REPRO: `wc -l audit/spec/sections/E_D_spine_rotation_perps.md` → 195; read it.

---

## D-02 · `E_D_spine_rotation_perps.md` §S1/§S3 is now false · SPEC-STALE

FEATURE: spec §S3 "THE GAP — the post-rotation window (headline)" and §S1's slot table.

INTENT: §S3 classifies the stale-quote window `DEVIATES`, states the fix is **not applied**, and names an EIP-170 blocker (`E_D:127-146`).

ACTUAL, with current truth:

| Stale claim | Where | Current truth |
|---|---|---|
| "Recommended fix (**NOT yet applied**)" for the stale quote | `E_D:127` | Fixed. `FUNCTIONAL_SPEC.md:153-165` records the `rotateSlice` re-point landing in `RedemptionExt`. §S3's `CLASS: DEVIATES` (`E_D:117`) is superseded by the register in the same document set. |
| "`PerpEngine` measures **24,541 bytes, 35 bytes of runtime margin**" / "Two external calls plus a custom error will not fit" | `E_D:142-146` | Dead. c20671a reports 24,661 → **23,243 B, margin +1,333**. (Commit-claimed; I did not re-run `--sizes`.) |
| "`PerpEngine`'s 35 bytes is the single hardest constraint in the codebase and directly shaped the R-02 fix" | `FUNCTIONAL_SPEC.md:362, 369-370` | Same — no longer true. |
| "`PerpEngine.quote` … `cauldron/PerpEngine.sol:170` … the only write at `:1027`"; "`_key():450`"; "`_sqrtP():456`"; "`_guardOpen` (`:1210-1214`)"; "`syncGeneration` reverts `PositionsOpen()` (`:987`)" | `E_D:15-16, 26, 87-101` | **Every line number in §S1 and §S3 is stale.** Current: `_pid()` at `PerpEngine.sol:618`, `_sqrtP()` at `:621`, `_liqTest` at `:1599`, `_settle` at `:1713`, `_doSweep` at `:1147`, `_rebook` at `:2132`. |
| "130 Foundry suites, 661 tests" | `FUNCTIONAL_SPEC.md:27`, `:339-349` | Stale baseline; ~100 commits have landed since. Do not quote it. |

DELTA: the one thing §S3 got right — `PerpEngine._key()` reads the engine's own `quote`, not `generationQuote[gen]`, and `CauldronHook.sol`'s comment says otherwise — still holds and is independently recorded in memory. Everything sized or dated is wrong.

CLASS: `SPEC-STALE`.

IMPACT: an auditor reading §S3 believes a fixed bug is open and believes no fix can land in `PerpEngine`. The second belief is what the E1A follow-up patch is currently blocked on (see D-05).

REPRO: read `E_D:127-146` against `FUNCTIONAL_SPEC.md:153-165` and `git show c20671a`.

---

## D-03 · "liquidation closes the position inside the swap that sank it" · SPEC-STALE (comment)

FEATURE: the in-swap liquidation guarantee.

INTENT: `PerpEngine.sol:1240-1241` — "**THIS IS THE PATH THAT CLOSES A POSITION INSIDE THE SWAP THAT KILLED IT**, so it must use exactly the same trigger as {liquidate}". Same shape at `CauldronHook.sol:1630` ("the whole point of that sweep is to close a…") and in the M1a header (`M1a_LiqGasBand.t.sol:22-25`: "leaves ZERO stranded insolvent positions").

ACTUAL: since 55ba6fe the short leg's buy-back is bounded by the mark band (`PerpEngine.sol:1762-1764`, `:1818-1819`). When the pool cannot supply the debt inside the band, `PerpEngine.sol:1828-1839` rebooks the remainder and **returns**, leaving the position open. `_buyUpTo` takes the tighter of the budget limit and the band (`PerpSwapLib.closeLimit:695-698`), and `bandLimit`'s own NatSpec (`PerpSwapLib.sol:659-662`) says that when live spot is already outside the band the limit is pinned one wei away "so the swap fills ~nothing" — so `bought` can be **zero** and the position is left fully intact.

DELTA: the guarantee is now size-conditional. It holds up to the size the band absorbs and fails above it, by design (`PerpEngine.sol:1809-1817` concedes exactly this: "a position too big to clear inside the band no longer closes in ONE swap").

CLASS: `SPEC-STALE` for `PerpEngine.sol:1240` and the M1a header; `CONFORMS` for the code — the new behaviour is intentional and stated.

IMPACT: the mental model "the swap that bankrupts you also closes you" is wrong at large size, and the two loudest comments on the path still assert it.

REPRO: trace `PerpEngine.sol:1818` → `:1827` → `:1837`.

---

## D-04 · `_rebook` zeroes `collateral`, which zeroes the liquidation penalty, the keeper bounty and **all future funding** · DEVIATES (headline code finding)

FEATURE: liquidation penalty, keeper reward and funding settlement on a position that has been partially (or nominally) closed.

INTENT, stated twice in `_rebook`'s own NatSpec:
- `PerpEngine.sol:2123-2125` — "`openedAt`, `leverage` and `entryFunding` are preserved, so **funding settles in full** against the smaller position on the final close rather than being charged twice."
- `PerpEngine.sol:2127-2130` — "No liquidation penalty and no keeper cut is taken on a piece … **The keeper is paid, and the badge struck, on the piece that finally closes the position.**"

ACTUAL: `PerpEngine.sol:2132-2137`

```solidity
function _rebook(uint256 id, Position memory p, uint256 newSize, uint256 newBacking) internal {
    p.size = newSize;
    p.collateral = 0;          // :2134
    p.principal = newBacking;
    _addOpen(id, p);
}
```

`collateral` is the **basis** of all three quantities the NatSpec promises:

| Quantity | Formula | After a rebook |
|---|---|---|
| Funding notional | `uint256(p.collateral) * p.leverage` — `PerpEngine.sol:931` | `0` |
| Funding cap | `(uint256(p.collateral) * maxFundingBps) / BPS` — `:933` | `0` |
| → `_fundingDelta` | clamped to ±cap — `:934-936` | **`0` forever, both directions** |
| Liquidation penalty | `(uint256(p.collateral) * liqPenaltyBps) / BPS` — `:1875` | `0` |
| → keeper cut | `(penalty * keeperBps) / BPS` — `:1877` | `0` |
| → `_routeFee(penalty - toKeeper, …)` | `:1879` | `0` |
| Badge `bountyWei` | `_killStats` — `:2465` | `0` |
| Badge `entryPrice` | `(p.principal * 1e18) / p.size` — `:2456` | inflated: `principal` absorbed `collateral` |

Solvency is unaffected — `_underwaterVal` uses `uint256(p.collateral) + p.principal` (`:1701`), and `_rebook` preserves that sum — so the position stays liquidatable. Only the money that flows *to the protocol and the keeper* is erased.

DELTA: both NatSpec sentences are false. Funding does not settle "in full" on the final close; it settles as zero. The keeper is not paid on the final piece; the keeper is paid zero, on every piece.

**Reachability, and why this is not a corner case.** `liquidate(uint256)` is permissionless (`PerpEngine.sol:1074`, `MODE_LIQUIDATION`). Combine with D-03: when spot sits outside the mark band, `_buyUpTo` fills ≈nothing, `cost ≈ 0`, `unbought == p.size`, and `PerpEngine.sol:1837` rebooks the **whole** position with `collateral = 0, principal = backing`. So the holder of a large or underwater short can call `liquidate()` **on their own position**, once, at ordinary gas, and thereafter:
- pay no funding for the rest of the position's life, in either direction;
- pay no liquidation penalty when it is eventually closed;
- leave every subsequent liquidator with a badge and a zero bounty.

The position's economics are unchanged for the trader (backing sum is preserved) and strictly worse for the protocol, the stakers and the keepers. After 55ba6fe this is the *normal* path for any position too big for the band, so it is reached without intent as well as with it.

CLASS: `DEVIATES` — code vs its own NatSpec, twice, from one line; and an economic defect independent of the doc.

IMPACT: keeperless liquidation loses its incentive precisely on the positions that most need clearing (the large ones). Funding — the mechanism that is supposed to pull a lopsided book back — silently stops applying to any position that has ever been bitten.

REPRO: no test found asserting penalty, keeper payout or funding on a rebooked position. `PerpEngine.sol:1807` cites `test_XL1_ShortLargerThanThePoolIsStillCloseable`, which pins **closeability** only. Neither suite I ran (M1a, LIQ04_GasStarve) touches it. Minimal repro: open a short at max leverage, move spot past the band, call `liquidate(id)` once (observe `PartiallyClosed(id, ~0, ~0, size)` and `positions(id).collateral == 0`), then close normally and observe `Liquidated(id, keeper, 0)` and a zero funding transfer.

---

## D-05 · Two comments in `_settle` contradict each other about the band's shape · UNDERSPECIFIED

FEATURE: the E1A mark band — flat, or split into an unbanded own-backing tranche and a banded socialised tranche?

INTENT A, `PerpEngine.sol:1724-1741`, stated as fact about the code: "A FLAT band over that whole budget closes the drain but breaks CLOSEABILITY (XL1) … The two properties in tension are about DIFFERENT money, **so they are settled against different budgets**: * the position's OWN backing is spent UNBANDED — closeability at any size, in the swap that sank it, costs the stakers nothing; * the SOCIALISED tranche (`insuranceEth + plv`) … is spent only INSIDE the mark band."

INTENT B, `PerpEngine.sol:1809-1817`, 60 lines later, stating the opposite: "COST, ACCEPTED DELIBERATELY: a position too big to clear inside the band no longer closes in ONE swap. Splitting the budget into an UNBANDED tranche … and a BANDED one … **is not here** because the second `_buyUpTo` call site costs ~987 B and puts this contract 715 B over EIP-170."

ACTUAL: `PerpEngine.sol:1818-1819` — one call, one budget, one band:

```solidity
(uint256 cost, uint256 bought) = _buyUpTo(p.size, backing + insuranceEth + plv, band);
```

DELTA: the code implements the **flat** band. Intent B is true; Intent A is false and describes an unlanded design in the present tense, including the claim that same-swap closeability at any size is preserved — which is exactly what Intent B concedes is lost. The follow-up lives on disk unapplied at `audit/RH_MAINNET_2026-09-16/e1a-splitband-followup.patch`.

CLASS: `UNDERSPECIFIED` — the intent record self-contradicts inside one function.

IMPACT: a reader who stops at `:1741` concludes D-03 and D-04 cannot happen. The EIP-170 reason given at `:1816-1817` ("715 B over") is also stale after c20671a freed 1,418 B, so the stated blocker for landing the split band no longer applies.

REPRO: read `PerpEngine.sol:1724-1741` and `:1809-1819` together.

---

## D-06 · `LiqGasStarved` on the pre-trade path, specified as a feature · CONFORMS-UNTESTED

FEATURE: pre-trade liquidation-gas gating.

INTENT: 0f71309 — "a trade that bankrupts N positions now either liquidates all N or reverts." `PerpEngine.sol:1094-1099` for the `complete` contract.

ACTUAL. Two distinct reverts, **both pre-trade only** (`amountSpecified != 0`, the call from `_beforeSwap`):

1. **Constant floor.** `CauldronHook.sol:801-803` computes `reserve = LIQ_GAS_RESERVE + LIQ_GAS_MIN` (180k + 400k) on the pre-trade call and requires `gasleft() > reserve + LIQ_GAS_MIN`, i.e. **> 980k at the check**. Below it, `CauldronHook.sol:851-853` staticcalls `openCount()` and reverts `LiqGasStarved` only if the book is non-empty. With `openCount == 0` no floor applies at all.
2. **Completeness gate (new).** The sweep runs, and if `_doSweep` broke on `gasleft() < SWEEP_KILL_RESERVE` with book unscanned (`PerpEngine.sol:1211`) it returns `complete == false`; `CauldronHook.sol:820-822` turns that into the same `LiqGasStarved`.

The post-trade sweep (`amountSpecified == 0`, from `_afterSwap`) still degrades silently — unchanged and correct, reasoned at `CauldronHook.sol:836-839`.

**Who can hit it:** any swapper on a pool with a live perp book (`openCount > 0`), through any router. `sender == perpEngine` is exempt (`CauldronHook.sol:800`), as are the hook's own swaps (`_inSelfBuy` / `_inRelaunchClose`, `:866`).

**What gas they must supply — measured this pass** (`/tmp/liq04.log`, 3 ETH buy):

| Book | Lowest ladder rung that fills | Kills |
|---|---|---|
| no perps | 400,000 (the ladder's bottom rung) | — |
| 4 shorts open | **3,000,000** — reverts through 2,000,000 | 4 |

(The test asks for 8 shorts; the log reports `open positions in the loaded run 4`, so the util/insurance admission gate at `PerpEngine.sol:2153-2155` capped it at 4. The suite name overstates its own book.)

**What an ordinary swapper experiences:** `LiqGasStarved()` with no indication of how much more gas is needed. The revert is deterministic in gas, so `eth_estimateGas` finds the right number and a wallet that estimates succeeds; a caller with a hand-set limit, or an aggregator with a fixed per-hop cap, sees the swap fail with a custom error it cannot interpret.

DELTA (documentation): `CauldronHook.sol:846-847` states the accepted trade-off as "a swap on a pool with a live perp book that supplies under **~1.05M gas** now REVERTS instead of filling." That is the *old constant floor*. Measured with 4 bankrupt shorts the real bar is **~3M**, because the completeness gate prices all N kills. The comment understates the cost it is disclosing by roughly 3×.

CLASS: `CONFORMS-UNTESTED` for the behaviour (see D-07); `DEVIATES` for `CauldronHook.sol:846-847`.

REPRO: `forge test --match-path test/attacks/LIQ04_GasStarve.t.sol -vv`.

---

## D-07 · `test_LIQ04_PreSweepDoesNotStarveTheUsersSwap` fails — **the bound is wrong**, the implementation is not miscalibrated · DEVIATES (test)

FEATURE: the ≤4× routability bound on pre-sweep gas.

INTENT: `LIQ04_GasStarve.t.sol:87-90` — `assertLe(loadedGas, baselineGas * 4, "pre-sweep multiplies the gas a plain buy needs by more than 4x")`.

ACTUAL: `[FAIL: pre-sweep multiplies the gas a plain buy needs by more than 4x: 3000000 > 1600000]`. Evidence for the classification:

1. **The denominator is a ladder artifact, not a measurement.** `_minGasFor` returns "the lowest gas cap **of the ladder** at which the buy succeeds" (`LIQ04_GasStarve.t.sol:50`), and the ladder's first rung is `400_000` (`:56-59`). The clean buy succeeds at the first rung, so `baselineGas == 400_000` is the ladder's *resolution*, not the cost of a plain buy. The protocol's own measured figures are **103,857** for a bare swap (`CauldronHook.sol:173`) and **~1.70M** for the uncapped control swap (`CauldronHook.sol:845`). Against 1.70M, the measured 3M is **1.76×** — comfortably inside 4×. The assertion is not measuring the quantity its message describes.
2. **The premise died with 0f71309.** A constant multiple of a baseline can only bound the pre-trade cost while the pre-trade sweep is allowed to *degrade*. After 0f71309 the pre-trade contract is "all N kills or revert" by design, so the gas requirement scales with N. `MAX_LIQ_PER_SWAP` (8) is the only cap, so the honest bound is `baseline + 8 × kill_cost`, not `4 × baseline`.
3. **The implementation matches its own design arithmetic.** 4 in-swap kills at the commit's measured ~440k ≈ 1.76M forwarded; `_liqSweep` forwards `g - 580k` (`CauldronHook.sol:801, 804`); plus the user's swap and the whole `afterSwap` still to run ⇒ ~2.9-3.0M. The measured 3M is the designed cost, not a miscalibration.
4. **The rest of the same test passes and is the right shape.** `assertFalse(loadedFailAbove)` (monotonicity — a higher cap never turns a working buy into a revert) and `assertGt(kills, 0)` both held: the log shows `non-monotonic failure above minGas: base / loaded false false` and `kills seen at some cap 4`.

**VERDICT: the bound is now wrong** — wrong denominator *and* dead premise. The implementation is calibrated as intended. The residual real concern is not the 4×, it is the absolute ask (~3M) and the fact that `CauldronHook.sol:846-847` still advertises ~1.05M (D-06).

CLASS: `DEVIATES` — the test encodes a pre-0f71309 property. It should be re-pointed at monotonicity + a finite bound derived from `MAX_LIQ_PER_SWAP`, both of which it already computes.

REPRO: `/tmp/liq04.log`.

---

## D-08 · M1a, the H1 regression, passes vacuously · CONFORMS-UNTESTED

FEATURE: the 0f71309 dose-response property — "across the whole band, a trade that bankrupts N positions either REVERTS or leaves ZERO stranded insolvent positions" (`M1a_LiqGasBand.t.sol:24-25`).

ACTUAL: the suite reports `1 passed`. The log reports `caps that filled: 0`. All ten caps — `1_000_000, 1_070_000, 1_100_000, 1_200_000, 1_300_000, 1_350_000, 1_400_000, 1_500_000, 1_600_000, 1_900_000` (`:88-100`) — returned `filled: 0`. The two assertions that carry the property live inside `if (ok)` (`:107-110`) and therefore **never executed**.

DELTA: the commit's own measurement says the trade "reverts through 2.2M, fills at **2.4M**". The ladder's top rung is **1.9M**, so the ladder cannot observe a fill by construction. What still runs is the sub-gate revert control (`:78-80`) and the ample-gas control at 8M (`:81-85`) — both useful, neither the dose-response property.

CLASS: `CONFORMS-UNTESTED` for the H1 property (this is the known vacuous-pass class: an early return / an untaken branch reports green).

IMPACT: the flagship regression for the 0f71309 Critical currently proves only that a starved trade reverts and an amply-funded one works. The interesting middle is unasserted. Raising the ladder above 2.4M, or asserting `passes > 0`, restores it.

REPRO: `/tmp/m1a.log`; `M1a_LiqGasBand.t.sol:100-113`.

---

## D-09 · Badge minting per liquidation path · DEVIATES (spec claim) + CONFORMS-UNTESTED (coverage)

FEATURE: Liquidatoor badge on liquidation.

INTENT: `FUNCTIONAL_SPEC.md:312` — A5 badges `CONFORMS-UNTESTED (stats payload)`, all paths including in-swap. `PerpEngine.sol:1882-1889` — "keeper call → caller; in-swap → the swapper".

ACTUAL, traced per path:

| Path | Entry | Mode | Badge |
|---|---|---|---|
| keeper `liquidate(id)` | `PerpEngine.sol:1074` | `MODE_LIQUIDATION` | **YES** — `_awardBadge` at `:1890` |
| in-swap sweep (`sweepLiquidations` → `_tryLiquidate`) | `:1105` → `:1248` | `MODE_LIQUIDATION` | **YES** — `:1890` |
| post-open sweep (`selfSweep` → `_tryLiquidate`) | `:1126` → `:1248` | `MODE_LIQUIDATION` | **YES** — `:1890` |
| **short refused (wholly or partly) by the mark band** | `:1828-1839` | `MODE_LIQUIDATION` | **NO** — the `return` at `:1839` precedes `:1874-1890` |
| `forceCloseDead` / `forceCloseAllDead` | `:1276`, `:1297` | `MODE_DEATH` | NO — by design; keeper reward instead, `:1891-1895` |

DELTA: the band-refused path emits **no** `Liquidated`, **no** `LiquidatoorAwarded` and credits **no** `badgesOwed`. After 55ba6fe that is the normal outcome for any position too large for the band, so a liquidator who supplies the gas and moves the price can walk away with nothing recorded at all. The `MODE_DEATH` exclusion is correct (a death close is not a liquidation); the band-refused exclusion makes `FUNCTIONAL_SPEC.md:312`'s "all paths" claim false. It is at least *internally* consistent with `_rebook`'s NatSpec (`:2129`, "the badge struck … on the piece that finally closes") — though by D-04 that final piece pays a zero bounty.

**Coverage.** `test/attacks/YBase.sol:356 YMockMiFrens` implements `mint`, `setRegistry`, `setMinter`, `setVault` — and **no `mintLiquidator`**. Grepping non-`out/` sources, the only `mintLiquidator` references are `PerpEngine.sol:2480` (a comment) and `:2505` (`claimLiquidatorBadges`). `_awardBadge` is deliberately best-effort behind `PerpSwapLib.tryMintBadge` with an L-06 `col.code.length` guard (`PerpEngine.sol:2420-2425, 2483-2487`), so in **every** YBase-derived suite the mint fails and falls through to `badgesOwed` silently, emitting `LiquidatoorAwarded(id, to, 0)`. The shared attack harness therefore cannot distinguish "badge struck", "badge owed" and "badge never attempted". The A5 `CONFORMS-UNTESTED` claim rests entirely on `LiquidatoorBadge.t.sol`; no liquidation-path suite can speak to badges, and the in-swap half of the claim is **untestable in the harness as built**.

CLASS: `DEVIATES` for the spec's "all paths"; `CONFORMS-UNTESTED` for the three real paths; `MISSING` for in-swap badge coverage.

REPRO: `PerpEngine.sol:1839` vs `:1890`; `grep -n mintLiquidator test/attacks/YBase.sol` → no match.

---

## D-10 · Insurance-then-PLV waterfall after the band change · CONFORMS (ordering)

FEATURE: bad-debt waterfall — insurance buffer first, LP principal second.

ACTUAL, three sites, all insurance-first, all still correct:

| Path | Site | Order |
|---|---|---|
| long bad debt (`proceeds < principal`) | `PerpEngine.sol:1794` → `_replenishPlv` `:2390-2394` | `insuranceEth` → `plv`, uncovered part recorded via `_bd` |
| short overspend (`cost > backing`) | `:1826` → `_absorbPlvLoss` `:2399-2405` | `insuranceEth` → `plv`, saturating at 0 so an extreme gap cannot underflow |
| funding receivable | `:1864-1872` | `fromIns` from `insuranceEth` first, then `rest` from `plv`, clamped so the vault is never overdrawn |

The band change tightened this rather than breaking it: `cost` is now bounded by the band (`:1818-1819`), so the socialised charge **per bite** is bounded — that is the E1A fix working as intended.

Two edges that are not documented anywhere:

(a) `PerpEngine.sol:1837` passes `backing > cost ? backing - cost : 0`, so a bite that spends the whole backing rebooks an open position with **zero** backing and non-zero size. Its next bite's budget is `0 + insuranceEth + plv` (`:1819`) — entirely socialised money — and `cost > backing` is then true for any non-zero cost, so every subsequent bite charges `_absorbPlvLoss` in full. The band bounds each bite; nothing bounds the number of bites across blocks. `UNDERSPECIFIED` — no doc says who bears the cost of a multi-bite close.

(b) The funding tail is skipped on a piece (the `return` at `:1839`) and is permanently zero thereafter (D-04), so for any position that has ever been bitten the funding waterfall never runs at all. `DEVIATES`, per D-04.

REPRO: read `:1794`, `:1826`, `:1864-1872`, `:2390-2405`.

---

## D-11 · Queued exits · CONFORMS-UNTESTED

FEATURE: `withdrawEth`/`withdrawToken` partial payout, the exit queue, and the deposit gate.

ACTUAL: `withdrawEth` (`PerpVault.sol:361-379`) prices `owed` off `assetsEth()`, pays up to `engine.freeEth()`, queues the remainder, and follows CEI (shares burned and claim earmarked before the single external send, `:370-377`). The queue is stored as **units against one global index** (`ethQueueUnits` / `ethQueueIndex` / `ethQueueEpoch`, `:128-130`; token mirror at `:137-139`), so a write-down scales one slot and touches no per-user state (`:113-127`). `_haircut` (`:398-406`) pays `owed * backing / claims` pro-rata when backing < claims, rounding toward the vault, which is what removed the run incentive documented at `:385-397`. `deposit` refuses new money while `pendingEth() > engine.totalEth()` (`QueueInsolvent`, `:309`), and the reasoning at `:301-308` notes the write-down is bankable **permissionlessly for any queued address**, which is what unlatched the R2C holdout. `pendingEthOf` returns 0 for a stale epoch (`:414-416`), so a wiped queue reads as wiped.

DELTA: none found against the NatSpec. Against the *spec*, nothing to compare — see D-01.

CLASS: `CONFORMS-UNTESTED` (conforms to its own NatSpec; not re-verified by execution in this pass, and the written spec is silent).

---

## D-12 · c20671a behaviour-neutrality · CONFORMS (claim verified, not taken on trust)

Checked each dedup against the pre-image (`git show c20671a^:contracts/solidity/cauldron/PerpEngine.sol`):

| Dedup | Verdict |
|---|---|
| `_pid()` → `_key().toId()` (`PerpEngine.sol:618`), so `_liq()` equals the pre-image's `poolManager.getLiquidity(_key().toId())` in `_buyUpTo` | **neutral** — same key, same call |
| `_slot0()` (`:620`) returning `(s, t)` from one `getSlot0`, destructured by `_sqrtP` (`:621`) and `_currentTick` | **neutral** — same values, one read |
| `_bal` casts the `mifrens` ERC721 to `IERC20` | **neutral** — `balanceOf(address)` is selector `0x70a08231` with a `uint256` return on both interfaces, so the decode is identical |
| `_pullTokenIn` shared by `fundPlvToken` and `fundTokenFromVault` (`:2647-2649`) | **neutral** — pre-image `:2623-2626` was byte-identical (`IERC20(registry.currentToken()).transferFrom(...); plvToken += amount;`) |
| `_openPrologue` (`:2105-2110`) | **neutral** — the same four statements in the same order |
| **The one semantic rewrite:** `band` from `mode != MODE_NORMAL` (long leg discarding it via `mode == MODE_DEATH ? band : 0`) to the folded predicate `p.isLong ? mode == MODE_DEATH : mode != MODE_NORMAL`, both legs then using `band` directly (`:1762-1764`, `:1775`) | **neutral** — equal across all six (isLong × mode) combinations. The only difference is that a long in `MODE_LIQUIDATION` no longer *computes* a band it would discard; `markSqrtPriceX96()`, `_sqrtP()` and `bandLimit` are all `view`/`pure`, so nothing observable changes |

CLASS: `CONFORMS`. The claim holds. Its side effect invalidates the spec's hardest stated constraint — see D-02.

---

## Q2 answered in full · who closes the remainder, and what the user sees

**Who closes it.** Anyone, by any of four calls, all already permissionless: the next swap's pre- or post-trade sweep (`sweepLiquidations`, `PerpEngine.sol:1100`, hook-only but fired by any swap), a bare `liquidate(id)` (`:1074`), the post-open `selfSweep` (`:1126`, fired by anyone's open), or the trader's own `close` (`:1044`, `MODE_NORMAL` — **unbanded**, so the owner can always clear their own position in one shot subject to their own `minOut`). There is no keeper requirement and no deadline: the remainder sits open until one of these runs.

**What is observable.** `PartiallyClosed(uint256 indexed id, uint256 bought, uint256 cost, uint256 remaining)` (declared `PerpEngine.sol:528`, emitted `:1838`) and the public getter `positions` (`:386`). **Not** emitted: `Closed`, `Liquidated`, `LiquidatoorAwarded`. So any consumer keyed on `Closed`/`Liquidated` — the natural choice — sees nothing at all.

**Is it silent in practice?** Partly. The repo's indexer does subscribe (`indexer/src/index.ts:534-548`) and correctly treats `remaining` as the authoritative post-fill size (`:540-542`). But it scales `notionalEth` by the **size fraction** (`:546-548`), whereas the chain sets `principal = backing - cost` (`PerpEngine.sol:1837`), which is not proportional to size, and nothing in the handler reflects `collateral → 0`. So the displayed position and the chain's can disagree after a real partial fill. Worth a targeted check against the UI's position card.

**The "intact-but-liquidatable" case is the worst-specified.** When the band refuses everything, the event fires as `PartiallyClosed(id, 0, 0, p.size)` — a liquidation attempt that closed nothing, reported under a name that says something closed — and the getter's `collateral` silently becomes `0` while the position is still fully open and still liquidatable. Nothing in the ABI expresses "this position is liquidatable and the band is currently refusing it". A trader watching their own position sees their collateral field zero out with no close. `UNDERSPECIFIED`.

---

## Conformance table

| # | Feature | Class | Test |
|---|---|---|---|
| D-01 | Spec coverage of area D (vault, liquidation, funding, badges) | `MISSING` | — |
| D-02 | `E_D` §S1/§S3 line numbers, R-02 status, the 35-byte blocker | `SPEC-STALE` | — |
| D-03 | "closes inside the swap that sank it" (`PerpEngine.sol:1240`) | `SPEC-STALE` (comment) / `CONFORMS` (code) | `XL1_LiqTwapAndDepthCap.t.sol` (closeability only) |
| D-04 | Penalty / keeper bounty / funding after `_rebook` | **`DEVIATES`** | none found |
| D-05 | Split band vs flat band (`:1724-1741` vs `:1809-1819`) | `UNDERSPECIFIED` | — |
| D-06 | `LiqGasStarved`, pre-trade, as a feature | `CONFORMS-UNTESTED`; `DEVIATES` for `CauldronHook.sol:846-847` | `LIQ04_GasStarve.t.sol` (**fails**) |
| D-07 | The ≤4× routability bound | `DEVIATES` (test) — **the bound is wrong, not the implementation** | `LIQ04_GasStarve.t.sol:87-90` |
| D-08 | H1 dose-response ("all N or revert") | `CONFORMS-UNTESTED` (vacuous pass) | `M1a_LiqGasBand.t.sol` (passes, 0 caps filled) |
| D-09 | Badge on keeper / in-swap / post-open liquidation | `CONFORMS-UNTESTED` | `LiquidatoorBadge.t.sol` only |
| D-09 | Badge on the band-refused path; spec's "all paths" | `DEVIATES` | none |
| D-09 | In-swap badge coverage in the shared harness (`YBase.sol:356`) | `MISSING` | — |
| D-10 | Insurance-then-PLV ordering (3 sites) | `CONFORMS` | — |
| D-10 | Zero-backing rebook, multi-bite socialised cost | `UNDERSPECIFIED` | none |
| D-11 | Queued exits, units/index write-down, `QueueInsolvent` gate | `CONFORMS-UNTESTED` | not run this pass |
| D-12 | c20671a read dedup | `CONFORMS` (verified) | XL1+E1B+S08 per commit |
| Q2 | Observability of a reduced-but-open / intact-but-liquidatable position | `UNDERSPECIFIED` | — |

---

## Spec statements found to be FALSE

Ordered by how badly a reader is misled.

1. `E_D:142-146` — "`PerpEngine` measures **24,541 bytes, 35 bytes of runtime margin** … Two external calls plus a custom error will not fit … Landing this fix requires reclaiming bytecode from `PerpEngine` first." Also `FUNCTIONAL_SPEC.md:362` and `:369-370` ("the single hardest constraint in the codebase"). **c20671a reports 23,243 B, +1,333 margin.**
2. `E_D:127` — "### Recommended fix (**NOT yet applied** — see the size blocker)". Applied; see `FUNCTIONAL_SPEC.md:153-165`.
3. `E_D:117-125` — §S3's `CLASS: DEVIATES` / "REPRO: not yet constructed" for the post-rotation stale-quote window. Superseded by R-02 FIXED.
4. `E_D:15-16, 26, 87-101, 106-108` — every line reference in §S1 and §S3 (`PerpEngine.sol:170, 450, 456, 987, 1027, 1042-1061, 1210-1214`). All stale; current anchors in D-02.
5. `FUNCTIONAL_SPEC.md:312` — A5 badges fire on every liquidation path including in-swap. False for the band-refused path (`PerpEngine.sol:1839`).
6. `FUNCTIONAL_SPEC.md:27` and the whole test baseline at `:339-349` ("130 Foundry suites, 661 tests", "660 passed, 0 failed, 1 skipped"). Stale by ~100 commits; `LIQ04_GasStarve` fails today.
7. `FUNCTIONAL_SPEC.md:57-63, 90` — routes area D to a section that does not describe the vault, liquidation, funding or badges. Structurally false as an index.

Non-spec intent sources found false (comments and NatSpec — recorded separately because a comment is evidence of intent, not of behaviour):

8. `PerpEngine.sol:2123-2125` — "funding settles in full against the smaller position on the final close." Settles as **zero** (D-04).
9. `PerpEngine.sol:2129-2130` — "The keeper is paid … on the piece that finally closes the position." Paid **zero** (D-04).
10. `PerpEngine.sol:1724-1741` — the split band described as implemented. It is not (D-05); `:1809-1817` says so explicitly.
11. `PerpEngine.sol:1240-1241` — "THIS IS THE PATH THAT CLOSES A POSITION INSIDE THE SWAP THAT KILLED IT." Size-conditional since 55ba6fe (D-03).
12. `CauldronHook.sol:846-847` — the routability trade-off quoted as "~1.05M gas". Measured ~3M at 4 bankrupt shorts (D-06).
13. `PerpEngine.sol:1816-1817` — "puts this contract 715 B over EIP-170" as the reason the split band is absent. Stale after c20671a freed 1,418 B.
