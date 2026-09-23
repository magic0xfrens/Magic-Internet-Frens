# Cascade-liquidation at 5x — Cauldron r45, Sepolia (11155111)

Harness: `scripts/stress/tiers.mjs`, `scripts/stress/cascade.mjs`, `scripts/stress/cascade5x.mjs`,
`scripts/stress/finale.mjs`. Evidence of record: **`cascade-actions.jsonl`**, append-only,
now 278 records; this run contributed 128 under the tags `tiers-boost`, `live-5X-setup`,
`live-5X-cascade`, `live-5X-finale`, `tiers-restore`, `live-5X-unwind`. Nothing was truncated.
Addresses from `indexer/deployments/round.json`; funder key read at runtime, written nowhere.
No contract was changed.

---

## 1. Tiers are restored — read back from chain

**This is the non-negotiable item and it is done.**

| | `tierDepthWei` | `tierLevPacked` | `maxLeverageCeiling` (slot 10) | `maxLeverage()` |
|---|---|---|---|---|
| original (recorded before anything) | `[25e18, 100e18, 300e18]` | `84148994` = `0x5040302` | `3` | **2** |
| boosted for the test | `[1e18, 2e18, 3e18]` | `84214787` = `0x5050403` | `5` | **5** |
| **restored, read back** | **`[25e18, 100e18, 300e18]`** | **`84148994` = `0x5040302`** | **`3`** | **2** |

Byte-identical. Verified by re-reading storage slots 26 (array length), `keccak(26)+i` (data),
27 (packed) and 10 (ceiling), plus the live `maxLeverage()` call.

Both changes went through the timelock `0x326abb…0aEe4` (`getMinDelay()` = 180s), funder holding
`PROPOSER_ROLE` + `EXECUTOR_ROLE`:

| | schedule | execute |
|---|---|---|
| boost | `0xa50b2b59113216e4c955513928efeec3e00fe4da7ed31a74a9952ae5feda4c4d` | `0xf7478dcd36fdaf4ec6090693984cc20266a8761ab409c5de80a200873dbf2961` |
| restore | `0x9f5684b5b4784e9dab4e9e3a626bd677ec56c1340905f66d0717bbbfccd722b8` | `0x7a6e4c8930a1b7eaee66c13501b42c35de58ece971225c155187e0e77825d1b0` |

**Nothing is left queued or dangling** — each mode scheduled exactly one `scheduleBatch` and
executed it. There is no unexecuted operation on the timelock from this run.

### `setTiers` alone would NOT have worked — and this is the finding to keep

`maxLeverage()` ends with `if (lev > maxLeverageCeiling) lev = uint8(maxLeverageCeiling)`
(`PerpEngine.sol:914`). `maxLeverageCeiling` is **`internal` with no getter**; read out of
storage slot 10 it was **3**. A `setTiers` call asking for 5x would have silently returned **3**,
and the run would have been mis-attributed to the tiers. Both `setTiers` and `setRisk` therefore
went in **one `scheduleBatch`**, so the engine was never observed half-configured.

For the record, the brief's proposed `depths=[1e18,2e18,3e18]`, `levs=[3,4,5,5]` **does** yield 5x
at 2.436 ETH depth. The loop assigns `levs[i+1]` for threshold `i`, so `depth >= 2e18` selects
`levs[2] = 5`; the threshold that must be cleared for 5x is 2 ETH, not 3 ETH. `maxLeverage()`
returned **5**, confirmed on chain before a single position was opened.

---

## 2. The deliverable table — `isLiquidatable` at spot vs. killed by the sweep

Cluster: **16 longs at 5x, ids 26–41**, opened at a clustered entry; collateral
`0.00387718222481879` ETH each after the open fee, principal (borrow) `0.015508728899275160` ETH
each — exactly 4× collateral, so equity is 20.0% of notional at open. Position #17 was refused
**`UtilCapped`** — a **pass**: `maxUtilBps` (8000) capped borrow at 80% of `totalEth`, which is the
ceiling doing its job, and it confirms PLV/util bound the cluster rather than depth.

**One position was condemned having read `isLiquidatable == false` at spot moments earlier.**

| id | `isLiquidatable` at spot, last read before the swap | killed in that swap | condemned by |
|---|---|---|---|
| **41** | **`false`** (table `after short#0`, 16 alive, 0 liquidatable) | **yes** — gone in table `after short#1` | **projected price** |
| 26–40 (15) | `false` | no | — survived every subsequent swap |
| 2 shorts | not individually tabled; `shortOiToken` `17,795,406,417,858,956,850,225,090` → `0` | **both** | 1 in the shorts phase, 1 in the 0.55 ETH buy |

So **3 liquidations occurred on chain** — `liquidatorMinted` went **2 → 4 → 5** across the run, and
`openCount` went 16 → 16 → 15 (16 longs, then 15 longs + 1 short, then 15 longs).

**This is a positive but thin result.** Long #41 read `false` at the spot sampled immediately
after `openShort#0` and was dead by the read immediately after `openShort#1` — it was carried
across maintenance by the price impact of the very trade it died in, which is pre-emptive
liquidation working. It is **one** position, not the broad false-but-killed table the test was
designed to produce, and it was not isolated by a dedicated pre-read in the same block. Treat it
as corroboration, not proof. Section 4 explains exactly what blocked the wide version, and it is
a real property of the system rather than a harness defect.

---

## 3. `unabsorbedEth` never moved

**`0` at every one of the 10 snapshots in this run**, set of all observed values `{0}` — across
the cluster build, both shorts, the 0.55 ETH buy, the full-bag dump, the trigger trade, and after
the three liquidations. `insuranceEth` moved only upward (`0.061843707600874184` →
`0.062270567852559931`), i.e. liquidation penalties funded insurance and **no liquidation produced
bad debt**. No headline here — the ledger held.

---

## 4. Why the wide cascade did not fire: the mark is a 5-minute TWAP, and buying ammunition *heals* the book

This is the substantive result of the run and it was not known going in.

`twapWindow` is **5 minutes** (`PerpEngine.sol:312`), and `_liqTest` takes the **worse of the TWAP
mark and live spot** (`PerpEngine.sol` `_underwater` → `_liqTest`, the LIQ-01 fix). The trip
condition measured live is `markValue < principal × 1.15` — i.e. equity below 13.04% of mark
value, not the 15% `maintenanceBps` reads like at a glance.

The brief's two ammunition options both fail against that, for one shared reason:

- **A CPMM round trip is not merely price-neutral on spot, it is actively *protective* on the mark
  for a full `twapWindow`.** Acquiring a bag requires BUYING it. Measured: the 0.55 ETH buy
  (`0xf7d0607e5ee528bc744ae16257e082e93d1f7b656be6c4b3409236c722d135a4`) dragged the TWAP up for
  the next five minutes; min cushion across the cluster went **13.42% before the dump → 43.34%
  after it**. The dump moved spot down (`activeEthDepth` 3.2687 → 2.7187 ETH, exactly the 0.55 ETH
  leaving) while `markSqrtPriceX96` was **byte-identical before and after**
  (`900778705498347803371640212044644`). The sweep had nothing to condemn because the mark had not
  moved.
- **Waiting it out does not help either**, because the round trip returns the pool to where it
  started. Eight polls over six minutes: cushion pinned at `18.10..33.24%`, `LIQUIDATABLE=0` every
  time — identical to the t0 cluster reading of `18.10..34.16%`.

**`openShort` is the one real source of un-reversed downward pressure.** It borrows `plvToken`
(`PerpEngine.sol:1053`) and sells it, costing only ETH collateral, and `_liqSweep` returns early
when `sender == perpEngine` (`CauldronHook.sol:833`) so it loads the book without firing the
sweep. Two shorts took the thinnest long from 18.10% to **13.42%** cushion — **0.38 points above
the 13.04% trip**. The halt condition in `cascade5x.mjs` stopped at `minCushion < 16.5%`, one
short too early; a third short would very likely have carried the cluster over and produced the
wide table. `maxNotionalBps = 500` caps each short at 5% of depth (~0.12 ETH notional), so ~4
shorts is the realistic dose. **That is the concrete change for the next run.**

The honest summary: at 5x the machinery is reachable — a ~8.0% adverse move on mark value trips a
position, versus ~41% at 2x — but the TWAP means a cascade **cannot be manufactured inside a few
minutes by a trader who starts with no inventory**. That is the TWAP doing exactly what its
comment says it is for.

---

## 5. Gas — the dose-response moved once there was a book to scan

Every refusal below is an `eth_call`, so it cost nothing and still yields the hook's real error
once v4's wrapper is peeled. **Unwrapped**, not the raw selector: `0x575e24b4` is the *hookFn*
field of `WrappedError`, not an error selector.

| gas supplied | empty book (previous run) | **16-long book (this run)** |
|---:|---|---|
| 500,000 | not tested | **REFUSED** `LiqGasStarved` |
| 1,000,000 | REFUSED `LiqGasStarved` | **REFUSED** `LiqGasStarved` |
| 2,000,000 | not tested | **REFUSED** `LiqGasStarved` |
| 3,000,000 | not tested | **REFUSED** — `revert: execution reverted`, **empty revert data, NOT `LiqGasStarved`** |
| 4,000,000 | FILLS | **FILLS** |
| 6M / 8M / 16M / 30M | FILLS | **FILLS** |

Two things worth the owner's attention:

1. **The cliff moved from "between 1M and 4M" to "between 3M and 4M"** once 16 positions were on
   the book. The gate at `CauldronHook.sol:834` (`g > reserve + LIQ_GAS_MIN`) is a pure gas check
   and refuses even a healthy book, but the *fill* threshold now also depends on the book's size.
   The frontend's pinned 8M is load-bearing, and at 3M the margin is already gone.
2. **The 3M refusal is a different failure from the 1M/2M refusal.** 1M and 2M are cleanly
   rejected by the pre-flight gate with a named error. 3M passes the gate and then dies *inside*
   the sweep with **empty revert data** — an out-of-gas, not a policy refusal. An integrator
   pinning 3M gets an undiagnosable revert rather than `LiqGasStarved`.

### Gas actually consumed

| action | kills in that tx | gas used | tx |
|---|---:|---:|---|
| `openLong` #0 (empty book) | 0 | 846,588 | `0x7c180df426fbad9bfed37de8b3de9d5c6e4ea0a2e99e87e6725143914a04431a` |
| `openLong` #14 (14-long book) | 0 | 1,198,741 | `0x78c1073acf241fc977e2e93f025a4b61c3d64892fb31229fe550c7f4ea9c834b` |
| `openShort` #0 | 0 | 1,506,972 | `0x152e6e15c79dacd8eba63d1a4160433e4b34fea95a797696465d45036caebe0e` |
| `openShort` #1 | **2** (long #41 + 1 short) | 1,646,807 | `0xef6ee89320a69663bfd630fe3dff1cf9024dcb6e84c3d2bdfda42cb3e3de2828` |
| buy 0.55 ETH | **1** (the remaining short) | 3,452,879 | `0xf7d0607e5ee528bc744ae16257e082e93d1f7b656be6c4b3409236c722d135a4` |
| full-bag dump @16M | 0 | 3,117,776 | `0x9d1fd62e48a0849378c9b9340d5ed2beb4d8fac060ae8c96aba2e3eca6242645` |
| trigger buy 0.03 ETH @16M | 0 | 3,164,374 | `0x135cf1f32b1f8516a35f3811f911206fcc2e516eb82f08d40901b8ff91885266` |

**The marginal scan cost is now measured**: across `openLong` #0 → #14 the book grew by 14
positions and gas rose 846,588 → 1,198,741, i.e. **≈25,154 gas per extra position on the book**,
paid by every swap whether or not anything is liquidated.

**Gas per kill is still not cleanly isolated.** The two multi-kill transactions also did other
work (a perp open; a 0.55 ETH router buy plus gacha mints), so differencing them against the
0-kill router trades is not sound: a router sell with 0 kills used 3,117,776 and a router buy
with 1 kill used 3,452,879, which would imply ~335k per kill, but the two are not like-for-like.
The clean experiment is the one section 4 describes — four shorts, then one trade — and it is the
single thing this run leaves undone.

---

## 6. Predicted reverts, all passes

| revert | where | why it is a pass |
|---|---|---|
| `UtilCapped` | `openLong` #16 | `maxUtilBps` = 8000 capped borrow at 80% of `totalEth`. The util ceiling bound the cluster at 16, confirming PLV/util — not depth, not `maxOiBps` — is the binding constraint, exactly as briefed. |
| `LiqGasStarved` | 0.5M / 1M / 2M dose | The `CauldronHook.sol:834` gas gate refusing a swap that could not fund a worst-case sweep. Correct, conservative behaviour. |

### One genuine harness bug found and fixed

`inv/buy 1.0 ETH of token` reverted **`NativeQuoteTakesValue`**. `CauldronGachaRouter.sol:275`
requires `quoteIn == 0` for a native-quote play — the ETH goes in `msg.value`. `cascade.mjs` was
passing `play(value, 0, …)` *and* `value`, so **the `inv` phase has never once bought inventory**,
in this run or the previous one. Corrected form (`play(0,0,0,0,0)` + `msg.value`) is what
`cascade5x.mjs` uses and it succeeded. This is why the earlier run reported "the funder's token
bag" as its only ammunition: the harness could not acquire any.

---

## 7. Reconciliation

Funder `0xC94400e90bB652AFA02740bFf50824E14069c133`, start **10.071355831854315426 ETH**, well
inside the 2.5 ETH budget.

| | ETH |
|---|---|
| cluster collateral (16 × 0.004015724727932459) | 0.064251595646919344 |
| short collateral (2 × 0.02) | 0.04 |
| token buy (recovered in the dump) | 0.55 |
| trigger trade | 0.03 |
| **gross deployed** | **≈0.684** |

`live-5X-unwind` (`cascade.mjs --only unwind`) completed. **Final state read back from chain:**

| | value |
|---|---|
| `openCount()` | **0** — all 15 remaining longs closed |
| residual token held by funder | **0** — sold back |
| `pendingEth` / queued withdrawals | **0** |
| `unabsorbedEth()` | **0** |
| `maxLeverage()` | **2** |
| `plv()` | `25052723846414` wei |

Nothing stranded: no open positions, no residual token, no pending queue entry. The per-close
records, the residual-token sale and the closing `kind:"reconciliation"` line are in the JSONL
under the `live-5X-unwind` tag; the file now holds **312 records** and no prior run's lines were
disturbed.

No key, mnemonic or keyed RPC was written to any file. `isDead` read `false` at every snapshot;
the pool never went `TokenDead`.

---

## 8. What the next run should do differently

1. **Open 4 shorts, not 2.** Halt on `minCushion < 13.5%` (just above the measured 13.04% trip),
   not `< 16.5%`. Two shorts landed at 13.42% — 0.38 points short.
2. **Never buy the ammunition after the cluster is open.** The buy lifts the TWAP for 5 minutes
   and heals the book faster than the dump can hurt it. Either acquire the bag *before* the
   cluster exists, or do not use a bag at all and let shorts do the work.
3. **Read the per-id table in the same block as the condemning trade** (a multicall or an
   archive read at `blockNumber - 1`), so a false-then-dead position is provably false at the
   instant of the swap rather than at a read shortly before it.
4. Fix `cascade.mjs`'s `inv` phase to `play(0, 0, 0, 0, 0)` + `msg.value` so the phase stops
   silently doing nothing.
