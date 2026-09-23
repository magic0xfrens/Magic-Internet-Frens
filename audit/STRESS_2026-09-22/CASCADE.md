# Cascade-liquidation stress test — Cauldron r45, Sepolia (11155111)

Harness: `scripts/stress/cascade.mjs`. Evidence of record: **`cascade-actions.jsonl`**
(128 append-only records across runs `preflight`, `live-A`, `live-B`, `live-C`,
`live-D-restore`). Every number below is in that file with a tx hash or a revert string.
Addresses read from `indexer/deployments/round.json`; funder key read from
`contracts/solidity/.env` at runtime and written nowhere.

Totals: **41 actions, 40 ok, 1 revert (predicted)**, 25,202,817 gas used, 16 snapshots,
16 positions, 7 findings.

---

## Headline

| question | answer |
|---|---|
| **Did `unabsorbedEth` move?** | **No. `0` at every one of the 16 snapshots**, including either side of the cascade trade and after all 16 closes. Set of all observed values: `{0}`. No bad debt at any point. |
| **Did the unstaking queue engage?** | **Yes.** `withdrawEth(all shares)` paid `0.110761751452008714` and queued `0.225474912141690591`. `claimPendingEth` later paid the queued amount in full. |
| **Gas dose-response** | 1M **refused** `LiqGasStarved`; 4M / 8M / 16M **fill**. The cliff is between 1M and 4M. |

### Gas dose-response (scenario 2)

Same call (`gachaRouter.play(0, 81930578652677456897308517, 0, 0, 0)`), four gas limits.
An `eth_call` honours `gas`, so each refusal was obtained for free and still yields the
hook's real error once v4's wrapper is peeled.

| gas supplied | outcome | error (unwrapped) |
|---:|---|---|
| 1,000,000 | **REFUSED** | `LiqGasStarved` — unwrapped from `WrappedError(target=0x0112…D0cC, hookFn=0x575e24b4)` |
| 4,000,000 | FILLS | — |
| 8,000,000 | FILLS | — |
| 16,000,000 | FILLS | — |

Sent at 4M (the lowest that simulated clean): tx
`0xab79f57b55b96edb0d748469c16c9fed40df31eb82dddc96841a473c31b9952e`, **gas used
1,730,238**.

**Finding worth the owner's attention.** At the moment of that dose-response the book held
**zero liquidatable positions** — `isLiquidatable` read `false` for all 16 ids immediately
before. The 1M refusal therefore fired on a *completely healthy* book. `LiqGasStarved` is
gated on the gas the trader supplied being enough to *guarantee* a worst-case sweep, not on
there being anything to sweep. That is the conservative choice and it is almost certainly
deliberate, but it means **a 1M-gas swap is unconditionally refused on this pool** — the
frontend's pinned 8M is not a comfort margin, it is load-bearing. Anyone integrating with a
lower pin gets a hard revert on a quiet market.

Reported selector `0x575e24b4` is the *hook function* field of the v4 wrapper, not an error
selector. Unwrapped, the error is `LiqGasStarved`.

---

## Why the previous run produced nothing

Confirmed against the source, and it is the more serious half of the problem.

`rec()` at `stress-market.mjs:167` is correct and all 13 call sites work. `RESULTS` is a
single module-level array. The bug is the **writer**, at `:796` — `writeReport()` runs once
at the end of `main()` and `fs.writeFileSync`s `results.json` and `run-report.md` wholesale.
Every phase body is gated on `PHASES.has(...)` (`:453, :486, :513, :534, :572, :596, :653,
:714`). A later invocation with a narrow `--phases` pushes only a few records and then
**truncates the previous full run's file**. The on-disk `results: 0` with 2 wallets and an
empty summary table is the signature of last-invocation-wins, not of a failed run: the 92
actions were probably real, and the harness deleted its own proof.

Additionally, the `FATAL` handler at `:791` calls `printTable()` (stdout only) and never
`writeReport` — so any crash or rate-limit also loses everything.

`cascade.mjs` fixes both: one `fs.appendFileSync` per record the instant the tx resolves
(`put()`), every line tagged with its `run`, and nothing in the file ever truncates the
JSONL. A resumed run rebuilds the cluster by replaying `kind:"position"` records out of the
log, so the log is real state, not just a report.

---

## Scenario 1 — the cluster

**PLV was the binding constraint, exactly as briefed — not depth, and not `maxOiBps`.**
Params read live, not assumed:

| param | value |
|---|---|
| `minCollateral` | 0.003 ETH |
| `maxLeverage()` | **2** (not 3 — `maxLeverageCeiling` is 3 but the live read is 2) |
| `maxNotionalBps` | 500 → cap 0.1424 ETH notional/position |
| `maxLiqBps` | 2000 |
| `MAX_OPEN_POSITIONS` | 64 |
| `maxFundingBps` | 5000 |

At `maxLeverage = 2`, borrow == collateral. `_utilGate` caps `longOiEth` at 80% of
`totalEth`, and `totalEth` was only 0.3243 ETH, so the whole book could lend ~0.26 ETH.
Sized to 72% utilisation: **16 longs × 0.014595734861580178 ETH** collateral
(0.014092182008855662 net of the open fee). Depth (2.85 ETH) and `maxOiBps` never came close
to binding. 16 is the honest number; 100 was never reachable.

All 16 opened, ids **#10–#25**, tx hashes in the log. `isLiquidatable` was **`false` at open
for all 16**.

They are a **ladder, not a point.** Each `openLong` buys token, so each successive position
entered higher: #10 received 4.610e24 tokens for its notional, #25 only 3.527e24 — a **30.7%
entry spread** across the cluster. Clustering them at one price is not possible through this
entrypoint, because the act of opening moves the mark.

State after: `plv` 0.3243 → **0.110761751452008714**, `longOiEth` 0 → 0.225474912141690592,
`openCount` 16, `activeEthDepth` 2.848 → 3.286, `unabsorbedEth` **0**.

## Scenario 2 — one trade that condemns many

Sold the funder's entire token balance (81,930,578,652,677,456,897,308,517 units) in one
swap. Before/after, from the `pre-cascade` and `post-cascade` snapshots:

| metric | before | after |
|---|---|---|
| `openCount` | 16 | **16** |
| ids died | — | **none** |
| `liquidatorMinted` | 2 | 2 |
| `badgesOwed(funder)` | 0 | 0 |
| `plv` | 0 | 0 |
| `insuranceEth` | 0.061622039595892328 | 0.061622039595892328 |
| **`unabsorbedEth`** | **0** | **0** |
| `activeEthDepth` | 3.285703113962770811 | 2.749764775524473715 |
| `cumulativeVolume` | 4.295959740513546252 | 4.831898078951843348 |

**The trade condemned nobody, and the reason is structural, not a harness failure.** Against
a CPMM the final token reserve after "buy B ETH of token, then dump everything" is
independent of B — a round trip is price-neutral. The only genuine downward force available
was the funder's **pre-existing** 8.19e25 token bag, and dumping all of it moved spot about
**−30%**. At `maxLeverage = 2` a position starts with 50% equity, so −30% leaves ~20% equity
on the *worst* position (#25, the highest entry) and ~9% of drawdown on #10. Nothing crossed
maintenance.

The honest conclusion: **with 2× max leverage and a 0.32 ETH PLV book, a single trader
cannot buy enough ammunition from this pool to cascade it.** To condemn the ladder you would
need to inflate spot *before* opening the cluster and dump afterwards — i.e. the attacker
must pre-position, which costs real fees and is visible. That is a defensive result, not a
gap in the test, but it does mean **the ≥30-kill `LiqTradeTooLarge` path was not exercised
live** and remains covered only by the unit tests.

## Scenario 3 — the unstaking queue (the one the last run could not reach)

It engaged, and the construction was cheaper than expected because a preflight read showed
**the funder already owns 100% of the vault's ETH shares** (`ethShareOf(funder) ==
ethShares`). Since `totalEth = plv + longOiEth` is conserved by an open, *any* `longOiEth > 0`
puts `freeEth` below a full-share withdrawal. No large new stake was needed.

`withdrawEth(319714166689763742773920 shares)` — tx
`0x3fb3e53fe8c29a73b07a487eb7e29cc6d5e632ca8e83a70c7f1be9a7b811c25f`, gas 113,754:

| field | value |
|---|---|
| `freeEth` at withdrawal | 0.110761751452008714 |
| withdrawal worth | 0.336236663593699306 |
| paid | 0.110761751452008714 |
| **queued** | **0.225474912141690591** |
| `pendingEthOf(funder)` | 0.225474912141690591 |
| `pendingEth` | 0.225474912141690591 |
| `ethQueueUnits` | 225474912141690591 |
| `ethBackingMark` | 0.225474912141690592 (re-baselined, delta 0) |

That left **`plv = 0` and `freeEth = 0`** — the queue was 100% unfunded, with the entire
claim backed only by ETH lent into the 16 open positions. Two consequences, both recorded:

- `openLong` at `plv = 0` reverted **`PlvInsufficient`** — predicted, therefore a **pass**.
  The liquidity brake holds: you cannot open into a drained book.
- `claimPendingEth` could pay nothing until positions closed. Each close returned exactly
  0.014093747806856645 to `plv`, monotonically, 16 times — the ledger is exact. After the
  last close `plv` was 0.225499377735455947 and `claimPendingEth` (tx
  `0x1d21b29cbff80f2af5e4740704109ff93e7aa20d914914d84deaa5f24bf311e9`, gas 73,015) paid the
  queue out **in full**, leaving `pendingEth = 0`, `ethQueueUnits = 0`.

The queue is reachable, correct, and self-clearing. Its liveness depends entirely on
positions closing — which is the design.

## Scenario 4 — fee accrual

Deltas, not adjectives, across the whole run (`t0` → final):

| metric | t0 | final | delta |
|---|---|---|---|
| `cumulativeVolume` | 3.858538410958666492 | 5.145060018523973244 | **+1.286521607565306752** |
| `insuranceEth` | 0.060816355031533112 | 0.061622039595892328 | **+0.000805684564359216** |
| `plv` | 0.304349663590670634 | 0.304349663590670634 | 0 (restored — see below) |
| `tokYieldEth` | — | — | no such getter on this deployment |

Fees grew. **But the growth is entirely attributable to the 16 perp opens.** `insuranceEth`
was 0.061622039595892328 before the cascade sell and *identical* after it: a 0.536 ETH swap
through the pool added **zero** to insurance. Insurance on this deployment accrues from perp
open fees, not from swap volume. Worth confirming that is intended before launch — it means
the insurance buffer does not grow with trading, only with leverage demand.

## Scenario 5 — no bad debt

`unabsorbedEth` was `0` at all 16 snapshots, across 16 opens, a 0.536 ETH adverse swap, a
fully-unfunded withdrawal queue and 16 closes. It never moved. Nothing to report as a
headline finding.

---

## The two open audit questions, settled on-chain

### 1. `ethBackingMark` vs `totalEth`: **stale from deployment, not diverging**

Directly tested with a `deposit`, as suggested:

| point | `ethBackingMark` − `totalEth` |
|---|---|
| before any activity | **−0.000010753398231431** |
| immediately after `depositEth(0.02)` | **0** |
| after 16 opens (no vault action) | −0.011887000003028672 |
| immediately after `withdrawEth` | **0** |
| after the restore deposit | **0** |

`_markEth` re-baselines on both `deposit` and `withdrawEth`, and it did so to the wei every
time. The −0.0000107 at t0 was a **stale watermark left over from deployment** — the last
vault action predated some fee accrual, and nothing had touched the vault since. The
−0.011887 mid-run is the same mechanism working correctly: open fees accrued to `plv`
between vault actions and the mark had not yet been refreshed. **No divergence. Close it.**

### 2. Pre-emptive (projected-price) liquidation: **not confirmed, not refuted**

`isLiquidatable(id)` read **`false` at spot for all 16 ids** immediately before the cascade
swap — and the sweep then killed **none** of them. The test that would have distinguished
projected-price liquidation from spot-price liquidation requires the sweep to kill a
position reading `false`, and no position died. **This question remains open**; it needs
either a deeper crash than a single trader can fund here, or a fork test.

---

## Reconciliation

Funder `0xc94400e90bb652afa02740bff50824e14069c133`.

| item | ETH |
|---|---|
| balance at start (`live-A`) | 9.693827516903786474 |
| balance at end (`live-D-restore`) | 10.071355831854315426 |
| **net** | **+0.377528314950528952** |
| gross deployed (stake 0.02 + collateral 0.2535 + restore 0.3043) | 0.577856955782188126 |
| gas used, all 41 actions | 25,202,817 |
| stranded in vault | 0 (shares 12,438,905,056 wei-units ≈ 1.2e-8 ETH rounding dust) |
| stranded in positions | 0 (`openCount` = 0) |
| residual token | 0 |
| unrecovered | **0** |
| budget | ≤ 2.5 ETH — **never approached**; peak at risk 0.578 ETH |

The funder is **up** 0.3775 ETH. That is not profit from the protocol: it is the funder's
**pre-existing 8.19e25 token bag sold into the pool as cascade ammunition and never bought
back**. No stress wallets were derived, so there was nothing to sweep — every action was
funder-signed.

## State left on the deployment

- **`plv` restored to `0.304349663590670634`** — byte-identical to t0. The queue test drained
  the vault's ETH side to zero (which made `openLong` revert `PlvInsufficient`, a functional
  outage), so that side effect was reversed with `depositEth(0.304325197996905278)`, recorded
  as run `live-D-restore`. `openCount` 0, `pendingEth` 0, `unabsorbedEth` 0.
- **`activeEthDepth` is 2.436602835952343812, down from 2.848281784407891051 (−14.4%).** This
  was *not* reversed. It is the price consequence of selling the funder's token bag in and
  not buying it back — a market position, not a broken invariant. Buying back ~0.41 ETH of
  token restores both the depth and the token balance, if the owner wants the pre-test mark.
- `isDead` stayed **false** throughout; `cumulativeVolume` rose, so the 24h death check was
  never at risk.
- **No contract was changed.**

## Not exercised

- `LiqTradeTooLarge` / the ≥30-kill path — unreachable live for the reason in scenario 2.
- Projected-price liquidation — see above.
- Short-side cascade (`openShort`), `forceCloseDead`, funding-driven liquidation over time.
