# Mass cascade liquidation — live Sepolia, Cauldron r45

Run 2026-09-22. Engine `0x09c9E9d0d462BdbB11c15ea1dF61BB29b402a2e5`, hook `0x011251690b5472dd8cb3fae59e8fd5dfeb40d0cc`, funder/deployer `0xC94400e90bB652AFA02740bFf50824E14069c133`.
Evidence of record: `audit/STRESS_2026-09-22/cascade-actions.jsonl` (append-only; runs `mass-cascade`, `mass-killscan`, `mass-tiers-boost`, `mass-tiers-restore`, `mass-sweep`).

## The kill table

**15 positions opened, 15 killed, across two single trades. Every one of them read `isLiquidatable == false` at the last reading before the trade that killed it.**

| id | cushion % before | `isLiquidatable` at spot before | killed by the sweep | killing trade |
|---|---:|:---:|:---:|---|
| 44 | 25.12 | **false** | **yes** | trade A |
| 45 | 24.34 | **false** | **yes** | trade A |
| 46 | 23.55 | **false** | **yes** | trade A |
| 47 | 22.76 | **false** | **yes** | trade A |
| 48 | 21.96 | **false** | **yes** | trade A |
| 49 | 21.17 | **false** | **yes** | trade A |
| 50 | 20.36 | **false** | **yes** | trade A |
| 51 | 19.56 | **false** | **yes** | trade A |
| 52 | 18.75 | **false** | **yes** | trade A |
| 53 | 17.93 | **false** | **yes** | trade A |
| 54 | 17.11 | **false** | **yes** | trade A |
| 55 | 20.86 | **false** | **yes** | trade B |
| 56 | 19.92 | **false** | **yes** | trade B |
| 57 | 18.97 | **false** | **yes** | trade B |
| 58 | 18.01 | **false** | **yes** | trade B |

`cushionPct = (markValueEth − principal) / markValueEth`. All 15 positions: 5x, collateral 0.00337925 ETH after fee, principal (debt) 0.013517 ETH.

* **Trade A** — `0xc7675b45a1f9312247a06a38696518a2c705876b36d388aae2d941b6d8a37dbb`, block 11760362, `CauldronGachaRouter.play(...)` (selector `0x7fe7c4b6`), gasLimit 8,047,796, **gasUsed 4,616,901, 11 kills**. This was the owner's own out-of-band sell from the deployer, fired mid-run; it is a genuine, unrehearsed mass cascade and is counted as one.
* **Trade B** — `0x70f289700dc750970244ffb5e5a9fe6e8c71db1b400eb302556f5548758a66fd`, `play(0, bag, 0,0,0)` at 16M gas, **gasUsed 2,552,747, 4 kills**.

## Projected-price (pre-emptive) liquidation, proven live with the mark as a control

Trade B is the clean experiment, because the TWAP mark is a **held constant** across it:

```
markSqrtPriceX96 before dump = 1048485504824341532731920769298983
markSqrtPriceX96 after  dump = 1048485504824341532731920769298983   ← byte-identical
activeEthDepth   2.808199948863929515 → 2.436602835952343812        ← only spot moved
openCount 4 → 0
```

`_liqTest` (PerpEngine.sol:1816) trips on the worse of two legs: the TWAP mark **with** the 15% maintenance buffer, or spot/projected price with **zero** buffer. The mark did not move one wei, so the mark leg returned exactly what it returned before the trade — and before the trade all four read `false` at 18.01–20.86% cushion, far above the 13.04% at which the mark leg trips. The only input that changed was spot. **The four kills can only have come from the projected post-trade price in the zero-buffer leg.** That is pre-emptive liquidation executing on chain, which the E1A fix rests on and which had never been demonstrated live.

The same holds for trade A's 11, with the weaker caveat that its last reading was taken ~30 s before the trade rather than immediately before it.

## gasPerKill

| trade | kills | gasUsed | average gas/kill |
|---|---:|---:|---:|
| A | 11 | 4,616,901 | 419,718 |
| B | 4 | 2,552,747 | 638,186 |

**Marginal gas per liquidation — the number that was still unmeasured — is ~294,879**, from the two-point regression `(4,616,901 − 2,552,747) / (11 − 4)`. Implied fixed overhead of the swap itself ≈ 1.37M gas. The average overstates the marginal cost badly at small kill counts, so size gas budgets off the marginal figure.

Gas dose–response on trade B (simulated, free):

| gas supplied | outcome |
|---|---|
| 2M | **REFUSED** — `LiqGasStarved` (unwrapped from v4 `WrappedError(target=0x0112…D0cC, hookFn=0x575e24b4)`) |
| 4M / 8M / 16M | FILLS |

The hook refuses rather than silently degrading — a 4-kill cascade will not execute under ~4M gas. Open gas also climbed monotonically with book size (829,209 → 961,555 across opens 0–6) as the post-open sweep scans a growing book.

## `unabsorbedEth` did not move

**0 at every snapshot — t0, after each open, before and after both cascades, and final.** No bad debt was created by liquidating 15 positions across two trades. The liquidations were solvent and the system *gained*:

| | t0 | final | delta |
|---|---|---|---|
| `unabsorbedEth` | 0 | **0** | **0** |
| `insuranceEth` | 0.061903936045005580 | 0.062429742010568080 | **+0.000525805965562500** |
| `plv` (across the cascades) | 0.500025052723846414 | 0.506937766629214462 | **+0.006912713905368048** |
| `liquidatorMinted` | 5 | 20 | +15 (one badge per kill) |

Liquidation penalties fed insurance and PLV rather than draining them; stakers ended ahead.

## Tiers restored — verified from chain

```
[restore/after] depths=[25e18,100e18,300e18] packed=84148994 (0x5040302)
                levs=[2,3,4,5] ceiling=3 => maxLeverage()=2
```
Re-read independently after the run: `maxLeverage() = 2`, `maxLeverageCeiling` (slot 10) = 3. Boost `0xc824a4bc…`, restore `0xbe88a0d1…`, both through timelock `0x326abb80…` (180s delay, scheduleBatch → executeBatch).

## Why the previous two runs killed zero — the setup, not the protocol

1. **The dump can only fire the zero-buffer leg.** A one-block dump cannot move a 5-minute TWAP (proven above: byte-identical mark). So the maintenance-buffer arithmetic — "at 5x a long dies on a ~5% drop" — describes the *mark* leg and is unreachable by a single trade. The reachable threshold is **insolvency**: value below `principal`, a ~20% drop at 5x, i.e. the cushion must be driven below **0%**, not below 13.04%.
2. **A CPMM round trip is price-neutral.** Longs opened *before* the bag buy can never be reached by dumping that same bag — the dump lands exactly back on their entry. The longs must be opened **after** the buy, at the elevated price, so the dump carries spot back down through them. This run bought 0.7 ETH of token first (token value +65.8%), waited, then opened.
3. **Opens must be spaced.** Fired back to back, 15 opens drift spot ~16.5% above the lagging mark, past the 13.04% trip, and the later ones are liquidated by their own `_sweepAfterOpen`. At 30 s apart every open landed at 17.1% cushion with `liqAtOpen=false` and nothing self-liquidated.

## Reconciliation

Funder 10.320005883567537313 → 10.267797114926609640 ETH, **net −0.052208768640927673**. Deployed 1.2525 ETH (0.5 vault deposit, 0.7 token bag, 0.0525 collateral); vault withdrawal returned 0.506835511858943837. The 0.0525 of collateral was consumed by the liquidations, as intended. **This figure is contaminated by the owner's own sell from the same wallet mid-run**, whose proceeds landed in the funder balance; the on-chain invariants above are unaffected.

Stranded: **none** — `vaultShares 0, pendingEth 0, openPositions 0, residualToken 0`. Pool returned to its exact starting state: `activeEthDepth 2.436602835952343812` and `markSqrtPriceX96 1208390911691959174068939575761716`, both identical to t0.

## Caveat on the trade A kill count

The log scanner's first pass reported 22 kills for trade A because both `Liquidated` and `LiquidatoorAwarded` fire per liquidation and both matched the name filter. De-duplicated by position id the true count is **11** (ids 44–54), corroborated independently by `openCount` and by `liquidatorMinted` 5 → 20 across exactly 15 liquidations.
