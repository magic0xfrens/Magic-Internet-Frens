# H2 — Perp solvency & the PLV waterfall

## (1) Model from code
**PerpVault** (cauldron/PerpVault.sol). Two independent sides, one denomination each (engine `quote`).
Entrypoints & gates:
- `deposit`/`depositEth` (permissionless, payable): guard `pendingEth() > engine.totalEth()` → `QueueInsolvent`; mints `shares = amount·(ethShares+OFFSET)/(assetsEth()+1)`; forwards to `engine.fundFromVault`.
- `withdrawEth(shares)` (permissionless): `owed = shares·(assetsEth()+1)/(ethShares+OFFSET)`; pays `min(owed,freeEth)` instantly, **queues the remainder** via `_queueEth` (units at live index). Does NOT call `_syncEthQueue`.
- `settlePendingEth(user)` / `claimPendingEth()` (permissionless): call `_syncEthQueue()` which haircuts the index **only when `pendingEth() > engine.totalEth()`** (`:466` early-return `backing >= claims`).
- Token side mirrors ETH; `claimTokYield` pays from segregated `tokYieldEth` pot; `_syncTokYield` epoch-forfeits on rotation write-off.
Asset flows: ETH in via `fundFromVault`→`plv`; out via `withdrawPlvTo` (≤`plv`). `totalEth()=plv+longOiEth`, `freeEth()=plv`.
Loss waterfall (engine): short overspend → `_absorbPlvLoss` (insurance then plv); long bad debt → `plv += repay(<principal)`, `longOiEth -= principal` ⇒ `totalEth` falls; funding shortfalls → insurance then plv.
Cross-dep: `assetsEth() = totalEth() − pendingEth()` saturating at 0 — **the exit queue's nominal is subtracted before live shares are priced.**

## (2) Findings

```
id: T2A   severity: Medium   confidence: DERIVED (real PerpVault; bad-debt trigger simulated)
subsystem: cauldron/PerpVault.sol
  :361 withdrawEth → _queueEth (queued exit becomes a fixed senior nominal)
  :265 assetsEth(): return t > p ? t - p : 0;   // live shares priced NET of the queue
  :460-466 _syncEthQueue: if (claims != 0 && backing >= claims) return;  // haircut ONLY when queue itself underwater
title: A PLV staker who withdraws-to-queue just before a loss dodges it entirely; staying stakers eat 100% of a partial loss, defeating the code's own "loss shared in proportion, not by reaction speed" claim (:394-400).
precondition: utilization high enough that freeEth < owed so the exit QUEUES (guaranteed reachable: maxUtilBps=8000 lets 80% of totalEth be lent, so any withdrawal >20% of side queues). A subsequent bad-debt loss whose size keeps queue nominal <= remaining backing.
sequence:
  1. lpA, lpB each deposit 5 ETH (plv=10).
  2. Traders borrow 8 ETH (longOiEth=8, freeEth=2) — permissionless opens.
  3. lpA.withdrawEth(all): 2 paid instant, 3 QUEUED at nominal (senior claim, no longer bears risk).
  4. A 3 ETH long bad-debt loss lands (totalEth 10→7). _syncEthQueue: claims 3 <= backing 7 → NO haircut.
  5. lentEth returns; lpA.claimPendingEth() → full 3. lpB redeems → 2 (assetsEth = 7−3 wound down to 2).
  Result: lpA recovers 5/5 (0% loss); lpB recovers 2/5 (100% of the 3 ETH loss). Pro-rata would cost each 1.5.
capital: gas only. FLASHLOANABLE: n/a (loss-avoidance, not extraction). No external drain.
attacker_cost: ~1 withdraw + 1 claim of gas; forgone yield while queued.  damage: redistributes an arbitrary partial loss from fast LPs onto passive LPs; at $738M-scale PLV this is unbounded transfer between LP cohorts. Defeats the stated pro-rata invariant.
poc: audit/RH_MAINNET_2026-09-16/poc/h2/M2a_QueueSeniorityDodge.t.sol  needs_fork: no
```
Invariant (plain words): the ERC4626-style share design and the queue's own comment promise a loss is shared **in proportion** across all staker value. Actually, the exit queue is fully senior to live shares: it only takes a haircut when the queue *by itself* exceeds total backing, so for any smaller loss the queue eats 0 and live stakers eat everything. Who *should* eat it: all staker value pro-rata. Who *does*: only stakers who did not queue.
**Mock seam a verifier must attack:** `LossEngine.injectLoss` shrinks `totalEth` via the lent leg. Faithfulness argument: the real engine's long-loss path (PerpEngine.sol:1682 `plv += repay` with `repay = min(proceeds,principal) < principal`, plus `longOiEth -= principal`) lowers `totalEth()` in exactly this shape while leaving `freeEth`/queue nominal untouched. The vault haircut logic — where the bug lives — is the **real** PerpVault. Upgrade to VERIFIED by opening a real losing long against the live engine while a vault exit is queued.

## (3) Refutations
- **ETH queue units×index accounting is sound (VERIFIED by construction + M2a control test).** I attacked: (a) same-block deposit/queue/settle/claim dilution — a new queuer after a haircut books `units = amount·QSCALE/index`, so their nominal is exactly `amount`, no dilution of existing units; (b) partial-claim rounding — `du = floor(paid·QSCALE/index)` favours the claimant by <1 wei/claim, not amplifiable; (c) insolvency (vault owing > backing) — `assetsEth()` saturates at 0 and `_syncEthQueue` floors the index so `pendingEth() <= totalEth()` post-sync; the R2C-class permissionless spam that moved 9.88/10 ETH is closed (write-down is global on one index, order-independent). No theft found in the restructure.
- **Same-block TWAP mark manipulation refuted.** `writeObs` integrates the OLD `lastTick` over `dt` then refreshes; a same-block push contributes `lastTick·0` to the tail (PerpSwapLib.twapTick `cumNow = tickCumulative + lastTick·(nowTs−lastObsTs)`), so a flash move is not the mark. twapWindow=5min default; the MIN_TWAP=1s fallback only binds near a ring wipe, guarded by `ringArmedAt+twapWindow` warmup (PerpEngine.sol:1888).

## (4) Leads
- **L1 — MODE_LIQUIDATION short buy-back has NO mark band.** PerpEngine.sol:1658 `band = mode==MODE_DEATH ? bandLimit(...) : 0`; `_buyUpTo(p.size, backing + insuranceEth + plv, band=0)` (:1696) can push spot arbitrarily up to a budget that includes **all of plv**. An honestly-TWAP-underwater short liquidated in a thinned pool drains staker plv at inflated spot. Next step: fork-PoC a short + sustained 5-min TWAP push (cost the per-block hold at ~100ms blocks vs recapture via owning pool LP) to test self-liquidation profit. Not yet costed → HYPOTHESIS.
- **L2 — `_utilGate` pins withdrawals to 20% instant.** A whale opening longs to 80% util forces 80% of any large LP withdrawal to queue (freeEth=plv≥20% totalEth). Cheap per-block on this chain; bounded liveness degradation, likely within design. Next: quantify funding cost/block to hold the pin.
```
```
