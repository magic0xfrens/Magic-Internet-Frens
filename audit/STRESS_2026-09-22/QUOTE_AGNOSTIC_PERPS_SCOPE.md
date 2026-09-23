# Quote-agnostic perps across a live rotation — scope

Date: 2026-09-22. Author: audit session. Status: SCOPE, not yet implemented.

## 0. Correction to the record

I previously told the owner a perp position open across a denomination change
"can't happen — structurally impossible", citing `RedemptionExt.sol:668-685`.
That was wrong, and the comment I cited is wrong. It claims:

> reaching this line required `linkVolume` to succeed earlier in this same call
> (:372), and that reverts `PerpsOpen()` unless `openCount == 0`

`linkVolume` does not ask `openCount`. It asks `PerpEngine.blocksVolumeLink()`
(`CauldronHook.sol:1798`), which is:

```solidity
function blocksVolumeLink() external view returns (bool) {
    if (openCount == 0 || markSource != address(0)) return false;   // :887
    (, bool ok) = twapTick();
    return !ok;
}
```

An armed `markSource` short-circuits to `false` **regardless of `openCount`**.
We armed one deliberately in r44 (it closed the dust-perp rotation hostage), so
on the live deployment the stated precondition is never checked. Proven by
execution: slice `0xffc3fc5e…` completed with `openCount == 2`.

I trusted a comment over the code it described. The brief's own rule — "a
comment is evidence of intent, not of behaviour" — is the one I broke.

## 1. What already works

Rotation is **not** blocked by open perps, and the engine is not bricked by one.
The actual sequence, verified by reading each hop:

1. `rotateSliceFrom` flips `generationQuote[gen] = toQuote` (`RedemptionExt.sol:658`)
2. `try syncGeneration() {} catch {}` (`:693`) reverts `PositionsOpen()` (`PerpEngine.sol:1542`), swallowed
3. `_isDead()` now returns true on `quote != _gq(gen)` (`PerpEngine.sol:2297`)
4. Dead ⇒ `_guardOpen` refuses new leverage (`:2248`), and `forceCloseDead` /
   `forceCloseAllDead` become permissionless with a keeper cut (`:1490`, `:1503`)
5. Book drains → `openCount == 0` → permissionless `syncGeneration()` adopts

That is a deliberate **park-and-drain**, and `syncGeneration` already
redenominates properly: it resets the TWAP ring, drops the stale `markSource`,
and recomputes `quoteUnit` via `PerpSwapLib.quoteFactor` so the leverage tiers,
dust filter and insurance breaker keep their economic meaning on a 6-decimal
quote (the F-03 fix).

So "perps must work on whatever the quote asset" is **already the design**. What
follows are the three places it does not yet hold up.

## 2. Defects

### D-1 (High) — force-close settles against the pool the rotation just drained

`_settle(..., MODE_DEATH, ...)` swaps through `_key()`, built from the engine's
OLD `quote`. Longs sell via `_swapExactIn` (`PerpEngine.sol:1997`); shorts buy
back via `_buyUpTo` (`:2040`). The rotation has just removed up to 100% of that
pool's quote-side liquidity.

The band does not save it. `PerpSwapLib.bandLimit(markSqrtPriceX96(), …)`
(`:1984`) is computed off a mark that reads **the same drained pool**, so the
bound travels with the damage instead of containing it.

The short leg is where it costs money:

```solidity
if (cost > backing) _absorbPlvLoss(cost - backing);   // :2046
```

Overspend lands on stakers, and past `plv` it becomes `unabsorbedEth` — bad
debt. Severity scales with how much of the pool the rotation moved, and
**nothing sizes a rotation slice against the open perp book.**

### D-2 (High) — owner-forced adoption writes the ETH-side PLV off

`PerpEngine.sol:1676-1712`. With ETH stakers present, a non-owner cannot adopt
at all (`hasQuoteStake()` vetoes), and the owner forcing through does:

```solidity
uint256 sweep = plv + writtenOff + insuranceEth;
plv = 0; tokYieldEth = 0; insuranceEth = 0;
_tryPush(treasury, sweep, true);
```

Staker principal leaves the vault in the old asset and governance is expected to
make them whole off-chain. On a live protocol the vault never fully drains, so
in practice the only path is the write-off. **This is the "backing stays gud"
hole the owner identified.**

### D-3 (Medium) — mark source dropped, never re-armed

`markSource` is correctly dropped on every sync (it points at the old pair), but
the engine then marks off its own freshly-rotated pool until governance calls
`setRouting`. That pool is the cheapest-to-push price in the system at exactly
the moment the book is being force-closed against it. Compounds D-1.

## 3. Venue funding — answered

The ETH/USDG venue was seeded **two-sided and oracle-priced**, not one-sided.
But `DeployLaunchpad.s.sol:935`:

```solidity
uint256 openEth = bandBps == 0 ? venueEth : venueEth / 20;
```

With `VENUE_ETH=0.3 ether` (`scripts/deploy-testnet.sh:186`), only **0.015 ETH**
sits in the tradeable band; the other 95% is parked in a concentrated band away
from spot. The rotation slice was 0.2474 ETH — **16x the tradeable depth**. It
filled at 83.72% of fair and every subsequent size down to 10 bps reverted.

So R-2 is a **testnet seeding artifact**, not a protocol defect. But it exposes
the real gap: nothing bounds a rotation slice against tradeable depth, which is
the same missing check as D-1.

## 4. Fix

Binding constraint, measured under `FOUNDRY_PROFILE=cauldron`:

| contract          | runtime | free    |
|-------------------|--------:|--------:|
| PerpEngine        |  24,338 |   **238** |
| CauldronRegistry  |  24,568 |       8 |
| CauldronHook      |  23,978 |     598 |
| RedemptionExt     |  13,916 |  10,660 |
| PerpVault         |  11,613 |  12,963 |
| PerpSwapLib       |   8,978 |  15,598 |

**Nothing new lands in PerpEngine or CauldronRegistry.** All new logic goes to
PerpSwapLib / PerpVault / RedemptionExt.

### F-1 — convert the PLV instead of writing it off (closes D-2)

Replace the sweep with a swap through the rotator's own allowlisted venue, so it
inherits the existing curation and slippage discipline.

- **PerpSwapLib** gains `convertPlv(rotator, fromQuote, toQuote, amount, minOut)`
  returning proceeds in the new quote. Routes through `QuoteRotator`, so an
  uncurated venue fails closed exactly as a rotation slice does.
- **PerpVault** extends the R2A machinery — `ethBackingMark` / `_markEth()`
  already rescale the share index by `backing/mark`. A denomination change is a
  very large backing change; the index math is the same. Queued exits
  (`ethQueueUnits`, `pendingEth`) must convert **at the same realized rate**, or
  a queued wei-denominated exit pays out a USDG figure.
- **PerpEngine.syncGeneration** swaps the sweep block for a lib call and
  `plv = proceeds`. Should be byte-neutral or better — it replaces code.

`insuranceEth` converts the same way. `tokYieldEth` keeps the logged write-off
(it is an orphan by construction; see the F-01 note).

**Fail-safe rule:** if the conversion cannot clear its oracle-derived floor, do
**not** adopt. Leave the engine parked and diverged — `syncGeneration` is
permissionless, so it retries. The pool rotation itself is already done and is
not rolled back. A thin venue delays engine adoption; it never strands staker
principal and never forces a write-off.

### F-2 — do not settle the book against the drained pool (closes D-1)

Two parts:

1. **Bound the slice by the book.** `rotateSliceFrom` refuses a slice whose size
   exceeds a configured multiple of open OI, so a rotation can never outrun what
   the book needs to settle. Lives in RedemptionExt (10,660 free).
2. **Settle before the drain, not after.** Today the order is flip → drain →
   force-close. Because `_isDead()` keys on the flip, the book can only be
   force-closed *after* the pool is already damaged. Fix by having the rotation
   force-close the book in the same call, immediately after the flip and
   **before** the final slice — or, if that cannot be made atomic, require
   `openCount == 0` for the *mandate-completing* slice only (the one that flips
   the quote), which is the precondition the false comment already assumed.

Option 2b is the cheaper, more honest fix: it makes the existing comment true
instead of deleting it, and it only constrains the single flipping slice, not
ordinary rebalancing.

### F-3 — re-arm the mark (closes D-3)

`syncGeneration` cannot re-arm `markSource` itself (it does not own it). Add a
deploy/ops step that re-points `PerpMarkSource` at the new pair as part of the
rotation runbook, and have the engine emit an event on drop so the gap is
observable rather than silent.

## 5. Test plan

- `RotationRoundTrip.t.sol` extended: ETH → USDG → ETH with an open book both ways.
- New PoC asserting `unabsorbedEth == 0` across a rotation with open shorts
  (this is the D-1 regression).
- New PoC asserting vault share value is preserved across a converted rotation
  (D-2), including one queued exit straddling the flip.
- Re-seed the testnet venue with a wide open band before any live retest, or the
  harness measures the seeding artifact instead of the protocol.

## 6. Open

- Whether to bound the slice by open OI (F-2.1) *and* gate the flipping slice
  (F-2.2), or only the latter. Recommend only the latter first — measure, then
  decide.
- `_condemnedByThisTrade` over-scoping remains a separately tracked residual.
