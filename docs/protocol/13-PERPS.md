# Cauldron — Perpetuals

What this document covers: what the perp system does for a trader and for a
depositor, the full open/close/liquidate paths with every gate in the order the
code applies them, where the price comes from and what happens when it is not
available, which quantity has to cover which, how funding and fees accrue and in
what asset, and what a quote rotation does to an open position and to a queued
vault exit.

The engine is quote-agnostic. Every identifier ending in `Eth` — `longOiEth`,
`activeEthDepth`, `buyEth`, `tokYieldEth` — means **"in the generation's quote
units"**, not ether. The names predate multi-quote and are kept because they are
public ABI (`cauldron/PerpEngine.sol:378-398`, `cauldron/PerpVault.sol:69-92`).
This document says *quote units* where the code says `Eth`.

Related: [`06-HOOK.md`](06-HOOK.md) for the swap callbacks that drive the
liquidation sweep, [`14-QUOTE-ROTATION.md`](14-QUOTE-ROTATION.md) for the
rotation this engine has to follow, [`04-GOVERNANCE.md`](04-GOVERNANCE.md) for
the vote that authorises it.

---

## 1. What it is

Leverage on the live iteration token, executed as **real pool swaps**. There is
no synthetic mark-to-market ledger: opening a long buys the token in the pool and
moves the chart; closing a short buys it back and moves it the other way
(`PerpEngine.sol:58-90`).

- **Long** — borrow quote from the vault, buy token, hold it. `principal` is the
  borrowed quote; `size` is the token held (`:821`).
- **Short** — borrow *token* from the vault's inventory, sell it, hold the
  proceeds. `principal` is the proceeds; `size` is the token owed (`:858`).

The counterparty is a community vault (`PerpVault`), not the protocol. Traders
borrow from depositors; depositors earn the fees and bear the bad-debt tail.

One engine serves every generation. It re-arms on relaunch via `syncGeneration`
(`:1041`), which is permissionless.

---

## 2. Opening a position

`openLong(uint8 leverage, uint256 minTokenOut, uint256 liqHint, uint256 amount)`
— `PerpEngine.sol:794`.
`openShort(uint8 leverage, uint256 minEthOut, uint256 liqHint, uint256 amount)`
— `:831`.

`liqHint` is vestigial. Pass `0`; the post-open sweep is hint-free (`:822`).

`amount` is the collateral **before** the open fee, stated explicitly so a
non-native quote can be pulled by `transferFrom`. On a native book it must equal
`msg.value`; on an ERC-20 book `msg.value` must be zero and the engine must
already be approved (`_pullQuote`, `:196-210`). The `transferFrom` return value
is checked, so a token that returns `false` cannot mint free collateral (`:208`).

### Every gate, in order

| # | Check | Reverts | Cite |
|---|---|---|---|
| 1 | `amount != 0` | `ZeroValue` | `:797` / `:834` |
| 2 | Native: `msg.value == amount`. ERC-20: `msg.value == 0` and a checked `transferFrom` | `BadParam` | `:196-210` |
| 3 | `block.timestamp >= registry.lastSummonAt() + warmup` (24 h) | `NotWarm` | `:1301` |
| 4 | `block.timestamp >= ringArmedAt + twapWindow` — the observation ring must genuinely span the TWAP window since it was last wiped | `NotWarm` | `:1308` |
| 5 | `!_isDead()` — hook says dead, **or** the engine's cached `quote` disagrees with `registry.generationQuote(currentGeneration)` | `TokenDead` | `:1309`, `:1331-1334` |
| 6 | `1 <= leverage <= maxLeverage()` | `BadLeverage` | `:1310` |
| 7 | `collateral = amount − fee >= minCollateral` (0.003 quote units) | `DustPosition` | `:803` / `:840` |
| 8 | Long: `borrow = collateral × (leverage − 1) <= plv`. Short: `tokenToSell <= plvToken` | `PlvInsufficient` | `:805` / `:845` |
| 9 | *Vault wired only:* side OI + new borrow `<= totalAssets × maxUtilBps / BPS` (80%) | `UtilCapped` | `:810` / `:848` |
| 10 | *Vault wired only:* `insuranceFloor == 0 || insuranceEth >= insuranceFloor` | `InsurancePaused` | `:811` / `:849` |
| 11 | Notional `<= activeEthDepth() × maxNotionalBps / BPS` (5% of depth) | `BadLeverage` | `:814`, `:1341-1343` |
| 12 | Side OI `<= depth × maxOiBps / BPS` (30%); the short side converts depth to token units at **spot** first | `OiCapped` | `:815` / `:851` |
| 13 | Swap output `>= minTokenOut` / `minEthOut` | `Slippage` | `:819` / `:855` |
| 14 | `openCount < MAX_OPEN_POSITIONS` (64) | `OiCapped` | `:1348` |

Gate 14 is structural, not economic. `MAX_OPEN_POSITIONS` (64) is deliberately a
constant and strictly below `FORCE_CLOSE_MAX` (96), so one
`forceCloseAllDead` call always drains the entire book (`:151-165`). If the book
could outgrow the drain, positions would survive a rebirth, `syncGeneration`
would revert `PositionsOpen` forever, and the whole token inventory would be
stranded in a dead token.

After booking, the open fires a best-effort liquidation sweep on itself
(`_sweepAfterOpen`, `:913-918`): it skips entirely below 250k gas, forwards
`gasleft − 120_000`, and wraps the call in `try/catch` so a cascade can never
revert the trader's own open.

### Leverage

`maxLeverage()` (`:713-722`) walks a tier table against `activeEthDepth()`, then
clamps to `maxLeverageCeiling`.

| Depth (quote units, at spot) | Tier leverage |
|---|---|
| below 25 | 2 |
| ≥ 25 | 3 |
| ≥ 100 | 4 |
| ≥ 300 | 5 |

Seeded in the constructor (`:448-449`), replaceable by `setTiers` (`:1751`).
**The tier table's top of 5 is unreachable at deploy:** `maxLeverageCeiling`
defaults to 3 (`:134`), and the clamp is applied last (`:721`). Raising it needs
`setRisk` (`:1714`), which bounds the ceiling to 10.

`activeEthDepth()` (`:703-711`) is a closed-form figure derived from the live
pool's liquidity and `sqrtPrice`, in **quote raw units**. It returns 0 for an
uninitialised pool or zero liquidity, which makes gates 11 and 12 pass trivially
(`cap > 0` is not required there) while `maxLeverage()` falls to the first tier.

---

## 3. Closing

`close(uint256 id, uint256 minOut)` — `:866`. Caller must be `p.trader`
(`:868`). `minOut` is enforced **only** on this path: `ownerSlippage` is
`mode == MODE_NORMAL` (`:1158`), so a liquidation and a death force-close both
execute with no slippage bound at all.

| Mode | Entry | Penalty | Keeper reward | Slippage bound |
|---|---|---|---|---|
| `MODE_NORMAL` (0) | `close` (`:866`) | none | none | `minOut` (`:1163`, `:1185`) |
| `MODE_LIQUIDATION` (1) | `liquidate` (`:873`), `sweepLiquidations` (`:898`), `selfSweep` (`:907`) | `liqPenaltyBps` of collateral, clamped to residual (`:1217-1218`) | `keeperBps` of the penalty (`:1219`) | none |
| `MODE_DEATH` (2) | `forceCloseDead` (`:1000`), `forceCloseAllDead` (`:1015`) | none | `keeperBps` of the residual (`:1235`) | none |

`_settle` (`:1153-1240`) is one body for all three. Effects first: the position is
deleted, swap-popped out of the enumerable open set and `openCount` decremented
(`:1154-1156`) before any swap or payout.

- **Long** — `longOiEth -= principal`; sell `size` token; repay `min(proceeds,
  principal)` into `plv`; residual is whatever is left (`:1160-1171`). A
  liquidated long almost always leaves `residual == 0`, because `repay =
  proceeds`.
- **Short** — `shortOiToken -= size`; buy back **exactly** `size` token
  (exact-output); return it to `plvToken` in full; residual is
  `backing − cost` where `backing = collateral + principal` (`:1172-1186`). The
  exact-output buy-back is what makes token-side principal structurally
  protected: the inventory always comes back whole, and any overspend lands on
  the quote side.

---

## 4. The vault — who supplies the capital and who bears the loss

`cauldron/PerpVault.sol`. Two independent sides, one asset each.

| | Quote side (`ethShares`) | Token side (`tokShares`) |
|---|---|---|
| Deposits | `deposit(amount)` `:187`, native convenience `depositEth()` `:212` | `depositToken(amount)` `:345` |
| Backs | longs | shorts |
| Principal risk | **bears the bad-debt tail** (after insurance) | structurally protected — buy-backs are exact-output |
| Yield | accrues inside the engine's `plv`, so share price rises (`:44-47`) | a segregated quote-asset pot, `tokYieldEth`, claimed via `claimTokYield` `:363` |
| Redeem | `withdrawEth(shares)` `:240` | `withdrawToken(shares)` `:374` |
| Queue | `pendingEth` / `claimPendingEth` `:290` | `pendingTok` / `claimPendingToken` `:397` |

Shares are priced with a `1e6` virtual offset (`OFFSET`, `:64`), so a
first-depositor inflation attack would have to donate ~1e6× a victim's deposit.
Pricing happens *before* the funds reach the engine (`:201-202`).

**Withdrawals under utilisation.** You are paid instantly up to the engine's free
balance (`engine.freeEth()` = `plv`); the remainder becomes a fixed nominal claim
and leaves the share base (`:245-258`). A queued claim stops earning yield and
stops bearing risk from that moment.

**A queued exit is a claim, not a guarantee.** `_haircut` (`:280-287`) writes
every claimant down pro rata when backing is below total claims:
`owed × backing / claims`, rounded down. The write-down is persisted on claim
(`:295`, `:402`), so it is not recomputed away.

### 4.1 Queued exits are SENIOR to live shares — a deliberate choice

Read this before supplying capital, because it determines who absorbs a loss.

The haircut only bites when total backing falls below the **queue itself**. Any loss
that leaves the vault above its queued total is therefore borne **entirely by the
shares still outstanding**. Worked example:

| | |
|---|---|
| Vault | 10 ETH backing (2 free, 8 lent), Alice and Bob hold half each |
| Alice exits | owed 5, paid 2 in cash, **3 becomes a queued claim**, her shares burn |
| Perps then lose 4 | backing falls to 6 |
| Alice collects | **3 in full** — the haircut needs backing below 3, and 6 is above it |
| Bob holds | 6 − 3 = **3 ETH**, against shares that were worth 5 |

Alice bore none of the loss; Bob bore all of it, though both were in the vault when
the risk was taken.

**Why it is built this way.** A queued claim gives up yield the moment it is queued
(`:245-258`), so it gives up risk at the same moment — a withdrawal in flight, symmetric
in both directions. The alternative is to denominate the queue in shares so it keeps
bearing loss until paid, which removes the asymmetry but makes your exit amount
uncertain until it settles.

**What it costs you.** Exiting first is rewarded, so if losses are expected the
individually rational move is to queue immediately. This is accepted on the grounds
that vault losses are a tail case rather than routine: liquidation is in-swap and
near-immediate, and the vault's income is trader fees. The residual loss cases are a
gap through the liquidation price, a close into a book too thin to absorb it, and a
mark that was wrong at the moment it mattered — which is what the insurance buffer
exists to absorb.

*Decision recorded 2026-09-12 by the protocol owner: keep seniority, document it. This
is a design choice, not an unfixed defect.*

**Token-side yield.** A MasterChef accumulator (`accEthPerTokShare`, 1e18-scaled,
`:110`) folds deltas of `engine.tokYieldCumulative()` (`:319-326`). Yield that
accrued while `tokShares == 0` is **orphaned on purpose**: the watermark advances
anyway and emits `UnattributedYield` (`:324`), so it can never be back-paid to
whoever deposits first. That ETH stays in the engine's segregated pot and has no
claimant.

`hasStakers()` (`:156`) — `ethShares | tokShares | pendingEth | pendingTok`
— is the test `PerpEngine.setVault` uses before allowing the vault to be
re-pointed (`PerpEngine.sol:1797`). It asks who is *owed*, not what is *held*,
because one wei of rounding dust used to latch the old guard permanently.

---

## 5. Every price source, with its fallback order

There is **no external price oracle anywhere on the liquidation path.** That is
deliberate: `PerpMarkSource.addPool` refuses a pool whose currency pair differs
from the primary's precisely to keep one off it (`PerpMarkSource.sol:111-127`,
rationale at `:40-54`).

**A. The tick — `_currentTick()` (`PerpEngine.sol:551-569`).** Every sample in
the system starts here.

1. `markSource` if non-zero: a hand-rolled `staticcall` of `weightedTick()`,
   accepted only when the call succeeded **and** `returndatasize() == 32`
   (`:557-566`).
2. Otherwise `poolManager.getSlot0(_key().toId())` (`:568`).

A mark source that reverts, self-destructs, is unset, or returns the wrong width
degrades silently to (2). Wiring one can never be worse than not wiring one —
with one exception, below.

**B. Inside the mark source — `PerpMarkSource.weightedTick()`
(`PerpMarkSource.sol:158-187`).**

1. `!armed` → returns **tick 0** (`:159`).
2. no sibling pools → the primary's tick (`:165`).
3. siblings present but no in-range liquidity anywhere → the primary's tick
   (`:185`).
4. otherwise `Σ(tickᵢ × Lᵢ) / Σ(Lᵢ)`, skipping pools with zero in-range depth
   (`:170-186`).

Branch 1 is the sharp edge. Tick 0 is a *valid-looking* 32-byte answer, so
`_currentTick` accepts it (`PerpEngine.sol:563-566`) and the mark reads as a 1:1
price. An unarmed mark source wired into a live engine is therefore worse than no
mark source. `setPrimary` must be called before `setRouting` points the engine at
it (`PerpMarkSource.sol:100`).

**C. The liquidation mark — `markSqrtPriceX96()` (`PerpEngine.sol:698-701`).**

1. `twapTick()` if it returns `ok`.
2. Otherwise **spot**, `_sqrtP()`.

**D. Inside the TWAP — `twapTick()` (`:651-695`).**

1. `block.timestamp <= MIN_TWAP` → not ok (`:653`).
2. ring empty → not ok (`:666`).
3. oldest entry newer than `now − twapWindow` → use the oldest, but only if it
   still spans `MIN_TWAP`; otherwise not ok (`:670-674`).
4. otherwise binary-search the newest observation at or before the target — about
   5 SLOADs rather than a 32-slot scan (`:676-684`).
5. zero span → not ok (`:692`).

The un-recorded tail is always extrapolated at `lastTick`, which `_writeObs`
refreshes **unconditionally** (`:630`). An earlier version bailed out when
`dt < OBS_INTERVAL` and left `lastTick` stale, which let one atomic
crash-then-restore round trip poison the mark for a whole window (`:577-598`).
Ring *appends* stay throttled on their own clock, `lastRingTs` (`:624`), so the
ring cannot be flooded to evict history.

Every timestamp delta in `_writeObs` and `twapTick` is `unchecked` so the
`uint32` epoch rollover in 2106 yields the modulo-2³² difference rather than a
panic (`:599-613`). A panic there would be permanent: `_pokeFunding` is on every
mutating entrypoint, including `forceCloseAllDead`.

**E. Spot — `_sqrtP()` (`:506`).** A direct `slot0` read of the single pool
`_key()` names. No fallback.

**`_key()` (`:499-505`) is built from the engine's own cached `quote` slot**, not
from `registry.generationQuote(gen)`. Currencies are sorted by address, because
an ERC-20 quote can land on either side of a CREATE-deployed token.

### Which decision reads which

| Decision | Source | Cite |
|---|---|---|
| Liquidation trigger (both sides) | MARK (C) | `:1141-1151` |
| Per-timestamp liquidation throttle notional | MARK (C) | `:878`, `:983` |
| Funding imbalance sizing | MARK (C) | `:744` |
| Badge liquidation price | MARK (C) | `:1495` |
| `positionHealth` (UI) | MARK (C) | `:1853` |
| Short borrow sizing (`_ethToToken`) | SPOT (E) | `:844`, `:1367` |
| OI cap converted to token units | SPOT (E) | `:851` |
| Depth for leverage tiers, notional and OI caps | SPOT (E) | `:703-711` |
| Insurance risk floor | SPOT (E) | `:1831` |
| Actual execution price of every leg | the pool, with **no** internal slippage bound | `PerpSwapLib.sol:76-96` |

---

## 6. The liquidation path, end to end

**Three entries.**

| Entry | Caller | Guards | Refusal |
|---|---|---|---|
| `liquidate(id)` `:873` | anyone | `nonReentrant`, `notNested` | reverts `Healthy` / `LiqCapped` |
| `sweepLiquidations(liquidator)` `:898` | the hook only (`:899`) | `_liqReentry`, `_inLocked` | silent no-op |
| `selfSweep(liquidator)` `:907` | the engine on itself (`:908`) | same | silent no-op |

The hook fires the sweep from `afterSwap` on **every** trade, on any interface,
crediting the swapper as keeper — and only when it can afford to:
`gasleft > LIQ_GAS_RESERVE (180k) + LIQ_GAS_MIN (400k)`, forwarding
`gasleft − 180k` and discarding the result (`CauldronHook.sol:157`, `:168`,
`:946-951`).

**1. Oracle and funding, always first.** `_pokeFunding()` (`:735`) runs *before*
the empty-book early return (`:935-937`). If it ran after, no swap would write an
observation while the book was empty, `lastTick` would freeze, and the first
position opened after a quiet period would be born liquidatable.

**2. Selection.** A rotating window over `_openIds` from `sweepCursor`: at most
`SWEEP_SCAN` (12) checks and `MAX_LIQ_PER_SWAP` (8) kills, and it **breaks** when
`gasleft < SWEEP_KILL_RESERVE` (420k) rather than attempting one more kill
(`:943-969`). Breaking early is load-bearing: the hook discards the result, so an
out-of-gas inside the sweep reverts *every* kill in it silently. Parked
liquidatable dust used to raise the gas bar for everyone until keeperless
liquidation switched off pool-wide (`:944-958`). After a kill the cursor does not
advance, because the swap-and-pop put a new id in that slot (`:965-967`).

**3. Health test.** `_quoteMark(p.size)` is computed **once** and reused for both
the underwater test and the throttle notional (`:981-983`).

| Side | Underwater when | Cite |
|---|---|---|
| Long | `markValue < principal + principal × maintenanceBps / BPS` | `:1144` |
| Short | `markValue + backing × maintenanceBps / BPS > backing`, where `backing = collateral + principal` | `:1147-1149` |

**4. Throttle.** Keyed on `block.timestamp`, **not** `block.number` — on
Arbitrum/Orbit `block.number` is the L1 number and would let the cap span dozens
of L2 blocks (`:304-311`). `cap = activeEthDepth() × maxLiqBps / BPS`; the cap is
**skipped entirely when it computes to zero** (`:884`, `:989`). The keeper path
reverts `LiqCapped`; the sweep path silently skips.

**5. Settlement.** As §3, then in order: funding transfer (`:1201-1214`), penalty
clamped to residual and keeper cut carved from the clamped figure
(`:1217-1222`), the rest routed as a fee side-attributed by `p.isLong` (`:1221`),
the `Liquidated` event, the trophy, and finally the trader's residual
(`:1223-1239`).

**6. Payouts never revert.** `_payOut` (`:1413-1431`) forwards 30k gas on the
native path and checks the ERC-20 return value; on any failure it credits
`payoutOwed[to]` and emits `PayoutOwed`. Without this, one hostile trader could
make their own position unsettleable, `forceCloseAllDead` would revert wholesale,
`openCount` would never reach 0, and `syncGeneration` would revert
`PositionsOpen` forever. Credits are withdrawn via `claimPayout()` (`:1435`).

**7. The trophy.** `_awardBadge` (`:1510-1542`) attempts a synchronous mint only
above 300k gas remaining and only when the collection has code (`:1517-1519`); it
tries `mintLiquidatorWithStats` then falls back to `mintLiquidator`, and credits
`badgesOwed` on any failure. The code check matters: a low-level call to a
code-less address returns `true`, which used to report a mint that never
happened. `claimLiquidatorBadges(n)` (`:1548`) reverts `BadParam` when no
collection is wired, so the credit is not burned for nothing (`:1552-1555`).

**Death variant.** `forceCloseDead(id)` (`:1000`) and `forceCloseAllDead()`
(`:1015`) run the same `_settle` with `MODE_DEATH`: no penalty, no badge, caller
takes `keeperBps` of the residual. Both require `_isDead()`. The registry drives
`forceCloseAllDead` once during relaunch, while the old pool is still alive so
settlement swaps can execute (`CauldronRegistry.sol:812-819`), then re-arms the
engine after the rebirth (`:1100-1103`). Both are `try/catch`-wrapped so they can
never brick a rebirth (`:1112-1115`).

---

## 7. Solvency accounting — which quantity must cover which

| # | Invariant | Maintained at |
|---|---|---|
| S1 | `plv` covers what longs may borrow | per open `:805`; as a share of the book `:810`; repaid capped at principal `:1164-1165` |
| S2 | `plvToken` covers what shorts may borrow | `:845`, `:848`; restored **in full** by the exact-output buy-back `:1177-1178` |
| S3 | Per-side OI stays inside pool depth | `:815` (quote side), `:851` (token side, depth converted at spot); single-position notional `:1341-1343` |
| S4 | A position's mark value covers debt + maintenance buffer | `:1141-1151` — violation *is* the liquidation trigger |
| S5 | `insuranceEth` absorbs bad debt before LP principal | long shortfall `:1444-1448`; short overspend `:1453-1459` (saturating at zero so an extreme gap cannot underflow); funding credit `:1206-1213` |
| S6 | Funding paid in covers funding paid out | payer capped by its own residual `:1204`; receiver draws insurance first, then `plv`, never overdrawing `:1207-1212`; per-position magnitude capped `:767-769`; global rate bounded `:1735-1736` |
| S7 | The liquidation penalty fits inside the residual | clamped `:1218`, keeper cut carved from the clamped figure `:1219` |
| S8 | Insurance stays above a risk floor before any skim | `:1829-1834`: protection is `max(insuranceFloor, (longOiEth + shortOiToken@spot) × maintenanceBps / BPS)` |
| S9 | Vault shares + queued claims do not exceed the engine's book | `assetsEth`/`assetsTok` subtract the queue, saturating at zero (`PerpVault.sol:162-170`); `_haircut` writes claimants down pro rata (`:280-287`) |
| S10 | Instant payment never exceeds free capital | vault caps at `freeEth`/`freeToken` (`PerpVault.sol:247`, `:382`); the engine re-checks and reverts `PlvInsufficient` (`PerpEngine.sol:1681`, `:1704`) |
| S11 | The token-side pot covers attributed claims | bounded by `tokYieldEth` (`:1693`); yield at zero shares is never attributed (`PerpVault.sol:324`) |
| S12 | The book is drainable in one call | `MAX_OPEN_POSITIONS` (64) < `FORCE_CLOSE_MAX` (96), both constants (`:162`, `:165`); `_payOut` never reverts (`:1413`) |

S6 is the one worth reading twice: funding is **not** a closed transfer. An
underwater position — and every liquidated long, where `residual == 0` — pays
less than it owes, while the receiving side still draws in full. The difference
comes out of insurance first and LP principal second (`:1192-1200`).

---

## 8. Funding and fees — amounts, and in which asset

Everything below is denominated in the generation's **quote**, whatever that is.
Transport differs, accounting does not: native arrives as `msg.value` and leaves
by `call{value:}`; an ERC-20 arrives by `transferFrom` and leaves by `transfer`
(`:175-223`).

### The open fee

`_takeFee(sent, longSide)` (`:1335-1340`): `fee = sent × openFeeBps / BPS`,
halved to `fee × (BPS − ogDiscountBps) / BPS` if the caller holds **any** MiFren
(`mifrens.balanceOf(msg.sender) > 0`). `collateral = sent − fee`.

> **Doc/code disagreement.** The contract header calls this a
> "6.9%-of-collateral open fee" (`:88`). It is 6.9% of the amount **sent**;
> collateral is what remains after it.

### Where a routed fee goes — `_routeFee(amount, longSide)` (`:1372-1400`)

With a vault wired, the split is carved in two stages:

| Leg | Share of the routed fee | Lands in | Cite |
|---|---|---|---|
| LP yield | `vaultYieldBps` = 30% | `plv` if `longSide`, else `tokYieldEth` + `tokYieldCumulative` | `:1378`, `:1385-1390` |
| Insurance | `insuranceBps` = 10% | `insuranceEth` | `:1379`, `:1391` |
| Genesis dividend | `divShareBps` = 60% **of the remaining 60%** → 36% of the original | `dividend` | `:1395` |
| Treasury | the rest → 24% of the original | `treasury` | `:1396` |

> **Doc/code disagreement.** The header states the split is "60% OG-dividend /
> 40% treasury" (`:89`). That holds only with **no vault wired** (`:1377`). With
> the default vault split it is 36% / 24%, after 30% LP yield and 10% insurance.

### Funding

A global index, `fundingIndex`, scaled 1e18 and **signed**: positive means longs
pay (`:333-334`).

```
shortValue = shortOiToken valued at the MARK              (:744)
total      = longOiEth + shortValue
imbalance  = longOiEth − shortValue                       (:748)
step       = imbalance × fundingRateBpsPerDay × dt × 1e18
             ─────────────────────────────────────────────  (:749-750)
                    total × BPS × 1 days
fundingIndex += step
```

Per position, at close (`_fundingDelta`, `:760-771`):

```
signed   = isLong ? (index − entryFunding) : −(index − entryFunding)
notional = collateral × leverage        (pinned at OPEN, price-independent)
raw      = signed × notional / 1e18
clamped to ±(collateral × maxFundingBps / BPS)
```

Notional is pinned to entry so funding cannot be gamed by moving spot before
close. The clamp means funding can never be weaponised to drain the vault or wipe
a position. Settlement is a real transfer through the PLV, not an accrual: the
payer's contribution is capped by its own residual and the receiver draws
insurance first (`:1201-1214`).

`poke()` (`:575`) is open to anyone, so the mark and the funding index stay
current even with no trading.

### Perp-swap trading fees

Perp swaps pay the hook's ordinary swap fee, but it is routed differently: 30% to
the genesis dividend, 70% to the side-attributed stakers
(`CauldronHook.sol:1261-1271`). Direction decides the side — a buy credits the
quote stakers, a sell the token stakers.

| Book | Entrypoint | Credits | Cite |
|---|---|---|---|
| Native, buy | `creditPerpFee()` | `plv` | `:1599`, `:1659-1660` |
| Native, sell | `creditPerpFeeToken()` | `tokYieldEth` + `tokYieldCumulative` | `:1604`, `:1661-1663` |
| ERC-20, either | `creditPerpFeeAsset(asset, amount)` (hook approves, engine pulls) | **`plv` for both sides** | `:1625-1631` |

Two guards matter here. `_creditPerp` refuses on a non-native book (`:1652`), so
native wei can never inflate an ERC-20-denominated counter — reachable, because
the hook's `_feeAsset` and `generationQuote` diverge mid-rotation.
`creditPerpFeeAsset` refuses any asset that is not the engine's own `quote`
(`:1629`).

**Known behavioural gap, stated in the code (`:1612-1623`):** on an ERC-20 book
the sell side credits `plv` rather than `tokYieldEth`, so a non-native
generation's token stakers do not receive their sell-side share. It is a
redistribution between two staker classes, not a loss — the fee is fully pulled
and accounted, and solvency is unaffected. Fixing it needs a second asset
entrypoint the engine has no EIP-170 headroom for.

---

## 9. Death, relaunch, and what a quote rotation does

### `_isDead()` — two conditions, not one

```solidity
if (quote != registry.generationQuote(registry.currentGeneration())) return true;
try IPerpHook(hookAddr).isDead(_key().toId()) returns (bool d) { return d; } catch { return false; }
```
`:1331-1334`

A key the engine can no longer trade counts as death. That makes the book
force-closeable by anyone and stops `_guardOpen` selling new leverage into an
engine that cannot price itself. A hook that reverts reads as **alive**.

### `syncGeneration()` — the only writer of `quote`

`:1041-1122`, permissionless.

| Step | Cite |
|---|---|
| Refuse when neither the generation nor the quote has changed (`AlreadySynced`) | `:1052` |
| Refuse while `openCount != 0` (`PositionsOpen`) | `:1053` |
| Migrate leftover dead-token inventory 1:1 via `registry.claimByBurnUpTo` — best-effort, capacity-aware | `:1060-1062`, `PerpSwapLib.sol:128-138` |
| Re-arm `plvToken` to the engine's real balance of the new token; zero `shortOiToken` and `longOiEth` | `:1066-1070` |
| Wipe the observation ring; set `ringArmedAt = now` | `:1073-1080` |
| **Refuse a quote change while `plv != 0` (`VaultStaked`)** | `:1116` |
| Adopt the quote; record the generation and token | `:1117-1120` |

`claimByBurnUpTo(fromGen, maxAmount)` is vesting-gated: when `claimGate` is set,
only the gate itself and `hook.perpEngine()` may call it
(`RedemptionExt.sol:657-659`). That exemption is what lets the engine migrate its
own inventory. Its body now lives on `RedemptionExt` (`:653`) and the registry
keeps a forwarder (`CauldronRegistry.sol:1288-1289`); the selector `0x1db616fa`
is unchanged, so the engine's hand-encoded call still resolves
(`PerpSwapLib.sol:134-135`).

The `VaultStaked` refusal is the whole protection for staked capital. `plv` is a
bare counter and `_pushQuote` pays in whatever `quote` says *today*, so adopting
a new quote would re-denominate every staked unit without moving any of it — and
the vault would go on pricing shares off the same counter (`:1094-1111`). Refusing
costs nothing: the engine **parks**. `_isDead` reads the divergence as death, the
book force-closes, new leverage stops, and once the vault has drained anyone can
call `syncGeneration` again.

### Queued vault exits across a rotation

A queued exit is a nominal claim in the asset that was staked. When the engine
parks and the vault drains, `engine.totalEth()` reaches zero, and `_haircut`
writes the whole queue down to zero before the new quote is ever adopted
(`PerpVault.sol:88-90`, `:280-287`). No queued claim is ever paid in the wrong
asset — but a claim left unclaimed against zero backing is worth nothing.

### The live-rotation window

When a rotation's migration mandate is spent, `RedemptionExt.rotateSliceFrom`
flips `generationQuote[gen]` and calls `syncGeneration()` on the engine
**in the same transaction**, best-effort (`RedemptionExt.sol:526-562`). That is
safe without a new guard: reaching that line required `linkVolume` to succeed
earlier in the same call, and `linkVolume` reverts `PerpsOpen` unless
`openCount == 0` (`CauldronHook.sol:1596-1600`). The book is provably empty, and
no user can interleave an open inside one transaction.

If the engine is unset, both guards vanish at once. Do not "just unset the
engine" to work around the interlock (`CauldronHook.sol:1587-1595`).

See [`14-QUOTE-ROTATION.md`](14-QUOTE-ROTATION.md) §9 for the full denomination
table.

---

## 10. Every parameter, with units

Owner-settable unless marked. Defaults are the values at construction.

| Parameter | Default | Units | Bound | Setter | Cite |
|---|---|---|---|---|---|
| `openFeeBps` | 690 | bps of the amount sent | ≤ 2000 | `setFees` | `:120`, `:1711` |
| `ogDiscountBps` | 5,000 | bps off the open fee for MiFren holders | ≤ 10,000 | `setFees` | `:121`, `:1711` |
| `liqPenaltyBps` | 690 | bps of collateral | ≤ 2000 | `setFees` | `:126`, `:1711` |
| `divShareBps` | 6,000 | bps of the post-carve fee → dividend | ≤ 10,000 | `setFees` | `:127`, `:1711` |
| `keeperBps` | 145 | bps of the penalty (liq) or the residual (death) | ≤ 10,000 | `setFees` | `:132`, `:1711` |
| `warmup` | 24 hours | seconds since `lastSummonAt` | ≥ `MIN_TWAP` | `setRisk` | `:133`, `:1719` |
| `maxLeverageCeiling` | 3 | integer multiple | 1…10 | `setRisk` | `:134`, `:1735` |
| `maintenanceBps` | 1,500 | bps of debt (long) or backing (short) | ≤ 5000 | `setRisk` | `:135`, `:1735` |
| `maxNotionalBps` | 500 | bps of `activeEthDepth()` | ≤ 10,000 | `setRisk` | `:136`, `:1735` |
| `maxOiBps` | 3,000 | bps of `activeEthDepth()`, per side | ≤ 10,000 | `setRisk` | `:141`, `:1736` |
| `fundingRateBpsPerDay` | 100 | bps of notional per day at 100% imbalance | ≤ 10,000 | `setRisk` | `:243`, `:1736` |
| `minCollateral` | 0.003 | quote raw units (wei-scale) | ≤ 1e18 | `setMinCollateral` | `:146`, `:1814` |
| `twapWindow` | 5 minutes | seconds | `MIN_TWAP`…2 hours | `setGuards` | `:246`, `:1776` |
| `maxLiqBps` | 2,000 | bps of depth, per timestamp | ≤ 10,000 | `setGuards` | `:248`, `:1776` |
| `maxFundingBps` | 5,000 | bps of collateral, per position | ≤ 10,000 | `setGuards` | `:249`, `:1776` |
| `vaultYieldBps` | 3,000 | bps of a routed fee → LP yield | sum with `insuranceBps` ≤ 10,000 | `setVaultSplit` | `:229`, `:1803` |
| `insuranceBps` | 1,000 | bps of a routed fee → insurance | same | `setVaultSplit` | `:230`, `:1803` |
| `maxUtilBps` | 8,000 | bps of vault assets lendable, per side | ≤ 10,000 | `setVaultLimits` | `:237`, `:1809` |
| `insuranceFloor` | 0 | quote raw units; 0 = breaker off | none | `setVaultLimits` | `:240`, `:1810` |
| `tierDepthWei` | [25, 100, 300] | quote raw units (1e18 scale) | `levs.length == depths.length + 1` | `setTiers` | `:448`, `:1752` |
| `tierLeverage` | [2, 3, 4, 5] | integer multiples | same | `setTiers` | `:449`, `:1752` |
| `dividend`, `treasury`, `nftBeneficiary`, `markSource` | constructor / 0 | addresses | none | `setRouting` | `:1765-1773` |
| `vault` | 0 | address | re-pointable only while `!hasStakers()` | `setVault` | `:1796-1799` |

Constants (not settable at all):

| Constant | Value | Units | Cite |
|---|---|---|---|
| `BPS` | 10,000 | — | `:103` |
| `POOL_FEE` | 0 | pips | `:101` |
| `TICK_SPACING` | 200 | ticks | `:102` |
| `MODE_NORMAL` / `MODE_LIQUIDATION` / `MODE_DEATH` | 0 / 1 / 2 | — | `:107-109` |
| `MAX_OPEN_POSITIONS` | 64 | positions | `:162` |
| `FORCE_CLOSE_MAX` | 96 | positions per call | `:165` |
| `MAX_LIQ_PER_SWAP` | 8 | kills per swap | `:150` |
| `SWEEP_SCAN` | 12 | positions checked per swap | `:365` |
| `SWEEP_KILL_RESERVE` | 420,000 | gas | `:370` |
| `OBS_CARDINALITY` | 32 | ring slots | `:265` |
| `OBS_INTERVAL` | 15 | seconds between ring appends | `:269` |
| `MIN_TWAP` | 1 | seconds — shortest span trusted | `:270` |
| `MAX_POOLS` (mark source) | 4 | sibling pools | `PerpMarkSource.sol:81` |
| `OFFSET` (vault) | 1e6 | virtual-share multiplier | `PerpVault.sol:64` |
| `ACC` (vault) | 1e18 | reward-accumulator scale | `PerpVault.sol:109` |
| `LIQ_GAS_RESERVE` / `LIQ_GAS_MIN` (hook) | 180,000 / 400,000 | gas | `CauldronHook.sol:157`, `:168` |

---

## 11. What can go wrong, and what protects you

**Execution has no slippage bound except your own.** Every settlement leg swaps
against the live pool with the price limit pinned wide open
(`PerpSwapLib.sol:66`). `minOut` is enforced only on `close` (`:1163`, `:1185`).
A liquidation and a death force-close execute at whatever the pool gives. What
bounds the damage is the per-position notional cap (5% of depth) and the
per-timestamp liquidation cap (20% of depth) — not a price bound.

**The mark is time-averaged; execution is not.** A flash move cannot trigger a
liquidation (the TWAP averages it away), but once a liquidation *is* triggered
the swap fills at spot. The two are deliberately different.

**The throttle is skipped when depth reads zero.** `cap = depth × maxLiqBps /
BPS`, and `cap > 0` gates the check (`:884`, `:989`). A pool with no in-range
liquidity has no per-block liquidation bound.

**An unarmed mark source reports tick 0 as a real answer.**
`PerpMarkSource.weightedTick` returns 0 when `armed` is false
(`PerpMarkSource.sol:159`), and `_currentTick` cannot distinguish that from a
genuine tick of 0 (`PerpEngine.sol:563-566`). Call `setPrimary` before pointing
the engine at a mark source.

**Bad debt lands on quote-side depositors.** Insurance absorbs first, then LP
principal, saturating at zero so an extreme gap cannot brick a liquidation
(`:1453-1459`). Token-side principal is structurally protected — the buy-back is
exact-output — but token-side *yield* is a quote-asset pot with the exposures of
that asset.

**Queueing a withdrawal does not jump the queue.** `_haircut` shares any
shortfall pro rata (`PerpVault.sol:280-287`). Measured before that fix: an LP who
queued recovered 84% and one who did nothing recovered 0%.

**Short-side yield accrued at zero token shares has no claimant.** It stays in
`tokYieldEth` and is never back-paid (`PerpVault.sol:319-326`). Governance can
redirect it; nothing else can.

**Residual limitations at this commit, stated plainly:**

1. **Only `plv` gates a quote change.** `syncGeneration` refuses a new quote while
   `plv != 0` (`:1116`) and nothing else. `insuranceEth`, `tokYieldEth` and
   `payoutOwed` are quote-denominated counters that are **not** checked, and all
   three are paid out through `_pushQuote` in whatever `quote` says at claim time
   (`:1401`, `:1439`, `:1694`, `:1835`). A non-zero balance in any of them
   surviving a rotation is either paid in the wrong asset or unpayable. *A fix
   broadening this guard, plus a `PerpVault.hasQuoteStake()` implementation, was
   uncommitted in the working tree while this document was written; it is not part
   of the commit documented here.*
2. **`IPerpVaultStake.hasQuoteStake()` is declared and never called.** It is
   declared at `PerpEngine.sol:49` and there is no call site in the engine and no
   implementation on `PerpVault` at this commit. Treat it as unwired.
3. **ERC-20 books do not split perp trading fees by side** (`:1612-1623`). See §8.
4. **`maxLeverageCeiling` (3) makes the top tier unreachable** at deploy (`:134`,
   `:721`). Deliberate, but the tier table reads as though 5× is available.
5. **The 24 h `warmup` is measured from `lastSummonAt`**, which a mid-generation
   rotation does not move (`:1301`). The second arm, `ringArmedAt + twapWindow`
   (`:1308`), is what actually covers a rotation. Together they mean opens are
   blocked for `twapWindow` (5 minutes) after any re-sync, not 24 hours.

---

## Verification

- **Commit documented against:** `880220a` — the most recent commit touching
  `cauldron/PerpEngine.sol`, `cauldron/PerpVault.sol`,
  `cauldron/PerpMarkSource.sol` and `cauldron/PerpSwapLib.sol`. Every citation was
  read with `git show 880220a:contracts/solidity/<path>`, not from the working
  tree. A sample was re-verified after writing.
- **The working tree had diverged when this was written.** `git diff 880220a --
  contracts/solidity/cauldron/` reported +246/−16 lines across six files,
  including `PerpEngine.sol` (+52), `PerpVault.sol` (+39) and
  `PerpMarkSource.sol` (+15). Those edits are **not** reflected here and they
  shift line numbers. Re-check any citation against `880220a`.
  [`04-GOVERNANCE.md`](04-GOVERNANCE.md) names the same commit but its
  `TreasuryGovernor.sol` line numbers are from the working tree (e.g. it cites
  `setQuoteOracle` at `:933-936`; at `880220a` it is `:842-846`). Where the two
  documents disagree on a line number for a file under active edit, they are
  describing different trees.

### Documentation debt — where a comment or a prior doc disagrees with the code

1. **`cauldron/PerpEngine.sol:88`** — "6.9%-of-collateral open fee". The fee is
   6.9% of the amount **sent** (`_takeFee`, `:1336`); collateral is the remainder.
2. **`cauldron/PerpEngine.sol:89`** — "split 60% OG-dividend / 40% treasury". True
   only with no vault wired. With the default split it is 36% / 24% of the routed
   fee, after 30% LP yield and 10% insurance (`_routeFee`, `:1377-1396`).
3. **`cauldron/CauldronHook.sol:1569`** — "`PerpEngine._key()` is built from
   `generationQuote[gen]`". It is built from the engine's **own cached `quote`
   slot** (`PerpEngine.sol:499-500`). The distinction is the entire reason
   `syncGeneration` has to be re-driven after a rotation.
4. **`cauldron/CauldronHook.sol:1580-1585`** — "The real fix is a
   liquidity-weighted mark across the generation's pools, which is a larger change
   than this interlock. Until it lands, the two features are mutually exclusive."
   The weighted mark **has** landed: `PerpMarkSource.weightedTick`
   (`PerpMarkSource.sol:158`), wired through `setRouting`
   (`PerpEngine.sol:1765`). The `PerpsOpen` interlock is still enforced
   (`CauldronHook.sol:1598`), so the behaviour is correct — the comment's
   rationale is stale.
5. **`cauldron/PerpEngine.sol:49`** — `IPerpVaultStake.hasQuoteStake()` is
   declared with no call site in the engine and no implementation on `PerpVault`
   at this commit.
6. **`audit/graph/perp.md`** — mechanically correct on behaviour and used as a
   cross-check for §§5–7, but its line numbers predate `b108507` and `880220a` and
   no longer resolve. Every figure quoted from it here was re-derived from source.

### Not verified here

- The gas figures quoted in the engine's own comments (≈388k per in-swap kill,
  ~450k per short settlement, ~78k per badge mint, ~30k per Chainlink read) are
  the code's measurements, not re-measured in this pass.
- The claim that `block.number` reports the parent chain's number on Arbitrum
  Nitro / Orbit is taken from `PerpEngine.sol:304-311`; it is not independently
  confirmed here.
- `PerpStakerOracle` appears in the perp cluster's function graph but has no call
  site in any file read for this document. Its role is **unverified**.
