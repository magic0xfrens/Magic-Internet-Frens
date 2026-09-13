# Cauldron — Quote rotation

What this document covers: why a generation can trade against more than one
asset, exactly what changes when the treasury rotates from one to another, the
rotation state machine and every gate on it, the envelope that authorises it, the
oracle and what fails safe versus what fails open, who supplies `minOut` and what
floors it, how rotated legs are recorded and recovered, and — for every stored
quantity that can outlive a rotation — whether it is converted, refused, or
carried.

[`04-GOVERNANCE.md`](04-GOVERNANCE.md) covers the vote itself: `TreasuryGovernor`
proposal lifecycle, quorum, the guardian seat, and what governance cannot do.
This document starts where the envelope exists and describes what spends it.
[`13-PERPS.md`](13-PERPS.md) §9 covers the perp engine's side of the same event.

`completeRotation` and a `RotationCompleted` event appear in older material.
Both were deleted; `rotateSliceFrom` does the whole job in one atomic call
(`cauldron/RedemptionExt.sol:608-620`). Do not look for them.

---

## 1. Why more than one quote asset

A generation launches against one asset — native ether by default
(`CauldronRegistry.sol:712`). Its LP, its perp book and its volume accounting are
all denominated in that asset.

Holding one asset is a position, whether or not anyone voted for it. Rotation
lets the MiFrens guild change it: sell ether into a stable near a top, come back
later, hold a tokenised equity. A rotation is a **flow, not an allocation** —
"convert 25% of this leg", not "hold 40% USDG" — which is what lets it work
without valuing two assets against each other (`QuoteRotator.sol:21-41`).

### What changes when a rotation completes

| | Before | After |
|---|---|---|
| Where the LP sits | one pair, `token/launchQuote` | two or more pairs; the launch pair keeps a residual |
| `generationQuote[gen]` | the launch asset | the destination — but **only** when a whole-position mandate is spent (`RedemptionExt.sol:526-527`) |
| `generationPoolKey[gen]` | the launch pair | **unchanged**, always — the 69× redemption reserve shares that key |
| Volume accounting | one pool | the sibling is linked, so the generation does not read as dying (`RedemptionExt.sol:418`) |
| The perp engine | marks the launch pair | re-pointed in the same transaction, best-effort (`RedemptionExt.sol:561-562`) |
| Fees | taken on the launch quote | taken on whichever side of the traded pool is the quote (`CauldronHook.sol:1492-1493`) |

---

## 2. Two machines, one word

"Rotation" names two separate mechanisms that never touch each other.

| | **Live rotation** | **Scheduled plan** |
|---|---|---|
| Lives in | `RedemptionExt` (running on the registry's storage) | `QuoteRotator` (its own storage) |
| Moves | LP liquidity: remove → swap → redeploy, atomically | idle balances sitting in the rotator |
| Authorised by | a `TreasuryGovernor` envelope | the rotator's owner (the treasury) |
| Entry | `rotateSliceFrom` (permissionless) | `rotateStep` (permissionless) |
| Price floor | oracle-derived, `max(callerMinOut, oracleFloor)` | `plan.minRate`, set at vote time |
| Used by | the guild's approved migrations | operational conversion of loose assets |

They share only the `QuoteRotator` contract and its venue allowlist. The live
path (`rotateSliceFrom` → `swapOnce`) never reads `plan`; `rotateStep` never
consults the governor.

`QuoteRotator` has **two authorities**, and this is load-bearing
(`QuoteRotator.sol:105-133`). `swapOnce` and `withdraw` are the registry's;
`setVenue`, `setPlan`, `setKeeperBps`, `setArbParams` and
`setRotationSlipBps` are the owner's. A single owner slot could only ever be one
or the other — with `owner = registry` the whole configuration surface became
unreachable, and with `owner = treasury` every live rotation reverted `NotOwner`
on its first swap. Neither is a working deployment, which is why a live rotation
had never actually run.

---

## 3. The rotation state machine

### Machine 1 — the live rotation (registry storage, driven by `RedemptionExt`)

```
                  setRotationWiring(rotator, governor)        RedemptionExt.sol:260
   UNWIRED ─────────────────────────────────────────────▶ WIRED
      │            onlyOwner; zero on either is refused (:261)
      │
      │  rotateSliceFrom while quoteRotator == 0  →  revert RotationNotWired (:293)
      │  rotateSliceFrom while treasuryGovernor == 0 → revert RotationNotWired (:302)
      ▼
   WIRED ──── TreasuryGovernor.execute(id) ───────────────▶ ARMED
      │         one live envelope at a time (TreasuryGovernor.sol:478-511)
      │
      │  rotateSliceFrom while allowance().remaining == 0
      │      →  revert NoRotationApproved (:317)
      ▼
   ARMED ──── rotateSliceFrom(fromLeg, sliceBps, minOut, route) ──▶ SPLIT
      │         removes  (:385)  →  swaps  (:398)  →  pulls back (:399)
      │         →  redeploys (:404) → links volume (:418)
      │         →  records the leg (:445) → consumes envelope (:459)
      │
      │  repeatable while the envelope has budget and has not expired
      ▼
   SPLIT ──── fromLeg == 0 && migrationMandateSpent() ─────▶ REDENOMINATED
      │         generationQuote[gen] = toQuote            (:526-527)
      │         perp engine re-pointed, best-effort       (:561-562)
      │         emit GenerationRequoted                    (:564)
      ▼
   REDENOMINATED ── relaunch: _removeLiquidity delegatecalls
                    recoverLegsAtTeardown ────────────────▶ single position again
                    (CauldronRegistry.sol:1605-1619)
```

There is **no pause, no abort and no pending state**. A guild that changes its
mind simply stops calling, or the guardian cancels the proposal
(`TreasuryGovernor.sol:516-521`).

Two gates sit outside this machine and can stop it from the side:

- `linkVolume` reverts `PerpsOpen` unless the perp book is empty
  (`CauldronHook.sol:1596-1600`). A slice therefore cannot execute at all while
  any perp position is open.
- The envelope's own liveness is `allowance().remainingBps`
  (`TreasuryGovernor.sol:652-677`).

### Machine 2 — the scheduled plan (`QuoteRotator.plan`, one slot)

| State | Test | Entered by | Gate |
|---|---|---|---|
| NONE | `plan.totalIn == 0` | deployment; `cancelPlan` deleting the struct (`:248-251`) | `onlyOwner` |
| ARMED | `totalIn != 0`, `lastStepAt == 0` | `setPlan` writes the whole struct (`:231-241`) | `onlyOwner` (`:223`) |
| RUNNING | `lastStepAt != 0`, `doneIn < totalIn` | `rotateStep` stamps `lastStepAt` and adds to `doneIn` (`:304-305`) | **ungated**; the venue must be curated (`:299`) |
| COOLING | `block.timestamp < lastStepAt + interval` | the same stamp (`:270`) | — |
| FINISHED | `doneIn >= totalIn` | accumulation at `:305` | — |

`lastStepAt == 0` means the **first** slice is due immediately; `interval` spaces
subsequent slices rather than delaying the start (`:266-270`).

`setPlan` is the only writer of `from`, `to`, `totalIn`, `sliceIn`, `minRate` and
`interval`, and it may be called from any state — overwriting a live plan resets
`doneIn` and `gotOut` to zero in the same literal (`:235-236`).

A third, smaller machine sits beside them: the per-block arb throttle,
`arbBlock` / `arbUsdThisBlock` (`:480-481`), reset on a new `block.number` and
accumulated per call (`:581-586`). It is active only while
`maxArbNotionalUsd != 0`.

---

## 4. One slice, step by step

`rotateSliceFrom(uint8 fromLeg, uint16 sliceBps, uint256 minOut, PoolKey route)`
— `RedemptionExt.sol:280`, reached through the registry's forwarder
(`CauldronRegistry.sol:264-268`). `rotateSlice(sliceBps, minOut, route)` is the
3-argument form and hard-codes `fromLeg = 0` (`RedemptionExt.sol:269-275`).

**Permissionless, within what the guild approved.** The destination and the
ceiling come from the vote; the caller chooses the timing, the source leg, the
venue, and a `minOut` that may only *tighten* the oracle floor
(`:295-300`, `QuoteRotator.sol:361-368`).

### Every gate, in order

| # | Check | Reverts | Cite |
|---|---|---|---|
| 1 | `quoteRotator != 0` | `RotationNotWired` | `:293` |
| 2 | `treasuryGovernor != 0` | `RotationNotWired` | `:302` |
| 3 | `allowance().remainingBps != 0` — **the remainder is the liveness flag, not the destination** | `NoRotationApproved` | `:317` |
| 4 | `sliceBps <= remaining` | `BadConfig` | `:318` |
| 5 | `allowedQuote[toQuote]` — re-checked at the last moment before liquidity moves | `NotConfigured` | `:322` |
| 6 | `0 < sliceBps <= MAX_SLICE_BPS` (2500 = 25%) | `BadConfig` | `:326`, `:598` |
| 7 | `fromQuote != toQuote` — a leg cannot rotate into itself | `BadConfig` | `:381` |
| 8 | `PoolOps.removePartial`: `0 < bps <= MAX_ROTATION_BPS` (5000 = 50% of live liquidity) | `require("bps")` | `PoolOps.sol:913`, `:941` |
| 9 | Both sides came back non-zero | `BadConfig` | `:393` |
| 10 | `QuoteRotator.swapOnce`: destination allowlisted, route trades the pair, **route is a curated venue** | `NotAllowedQuote` / `NoRoute` | `QuoteRotator.sol:343-359` |
| 11 | Oracle floor computed **before** the swap; `floor == 0 && quoteOracle != 0` refuses | `NotPriceable` | `QuoteRotator.sol:372-390` |
| 12 | `out >= max(minOut, floor)` | `SlippageTooHigh` | `QuoteRotator.sol:393` |
| 13 | `linkVolume` — registry-only, and reverts while any perp position is open | `PerpsOpen` | `CauldronHook.sol:1596-1600` |
| 14 | `consume(sliceBps, fromLeg == 0)` — booked **after** the move succeeds | `BadParam` | `:459`, `TreasuryGovernor.sol:726-771` |

Step 3 deserves its own note. `address(0)` is both "native ether" and "no
envelope", so testing the *destination* for zero made rotation one-way: a
treasury that moved into an ERC-20 could pass a vote to come home and watch every
slice revert. `allowance` reports zero remaining for absent, expired **and** spent
envelopes alike, so the remainder answers the liveness question without
overloading an address (`:308-317`, `TreasuryGovernor.sol:644-651`).

Which leg the slice comes out of:

- `fromLeg == 0` — the primary. Its quote is read from
  `generationPoolKey[gen].currency0`, **not** from `generationQuote[gen]`
  (`:371`). The two diverge the moment a migration completes, and reading the
  flipped value asked `removePartial` to measure the destination asset out of the
  launch pair — it settled the wrong currency, returned 0, and reverted. Measured:
  after a completed ETH→USDG migration the ~32% residual still in the ETH pair
  could never be rotated again for the life of the generation (`:349-370`).
- `fromLeg >= 1` — `generationLegs[gen][fromLeg − 1]` (`:373-376`). This is what
  makes rebalancing and merging expressible; merging is just rotating one leg
  entirely into another leg's pair.

### What one slice does, in order

1. `PoolOps.removePartial` takes `sliceBps` of the **current** liquidity from the
   chosen pair. `DECREASE_LIQUIDITY` + `TAKE_PAIR`, with no `BURN_POSITION`, so
   the position survives and the original pair keeps trading
   (`PoolOps.sol:905-936`).
2. The quote side goes to the rotator and is swapped: `swapOnce`. The **token
   side never leaves the registry** — it is the same asset in either pair
   (`:395-399`).
3. `PoolOps.openOrAddPair` redeploys into the destination pair, opening it on the
   first slice and topping up the same position on every later one (`:404-414`).
4. `linkVolume` counts the new pool toward the generation, or splitting liquidity
   would read as the generation dying (`:418`).
5. `_recordLeg` upserts the leg **by quote** (`:445-456`, `:692-700`).
6. `consume` books the spend (`:459`).
7. If this was a primary slice and the migration mandate is now spent, the
   generation's quote flips and the perp engine is re-synced (`:526-562`).

Because each slice takes a share of what **remains**, the position decays
geometrically: 11 slices of 25% convert about 95%, and an exactly-10,000-bps
budget converges on ~68% moved (`:519-525`, `TreasuryGovernor.sol:230-256`).
A residual tail in the old pair is normal and is handled explicitly at relaunch,
not assumed away.

---

## 5. The envelope lifecycle

One envelope at a time (`TreasuryGovernor.sol:119-129`, `:140`). See
[`04-GOVERNANCE.md`](04-GOVERNANCE.md) §3 for proposing and voting; this is what
happens to it afterwards.

| Stage | What happens | Cite |
|---|---|---|
| **Created** | `execute(id)` writes `Envelope{quote, maxTotalBps, movedBps: 0, expiry: now + ENVELOPE_LIFETIME, active: true, movedPrimaryBps: 0}` and stamps `lastEnvelopeAt` | `TreasuryGovernor.sol:500-510` |
| **Validated at creation** | leader-only (`id != winner()` reverts), inside `EXECUTION_WINDOW`, destination still allowlisted, destination still priceable | `:488-498` |
| **Read** | `allowance()` returns `(quote, remainingBps)`; zero remainder for absent, expired **and** spent | `:652-677` |
| **Metered** | a **whole-position** mandate (`maxTotalBps >= 10000`) meters against `movedPrimaryBps`; anything smaller meters against the shared `movedBps` | `:674` |
| **Spent** | `consume(bps, fromPrimary)`, registry-only; primary slices bounded by `left`, secondary slices bounded by the shared total | `:726-757` |
| **Completed** | `migrationMandateSpent()` = `maxTotalBps >= 10000 && movedPrimaryBps >= maxTotalBps` | `:710-713` |
| **Deactivated** | on exhaustion of whichever counter `allowance` reports — so a spent envelope stops blocking new proposals | `:769` |
| **Aborted** | guardian `cancel(id)`; clears `active` if that proposal's envelope is live | `:516-521` |
| **Expired** | `block.timestamp >= expiry` makes `allowance` report zero | `:654` |

Two accounting rules carry most of the weight here.

**`movedBps` counts every slice; `movedPrimaryBps` counts only slices out of the
generation's own position.** `rotateSliceFrom` lets a permissionless caller pick
the source leg, so without the split a stranger could spend a voted 10,000-bps
migration mandate 25 bps at a time out of a 0.1% dust leg — redenominating the
generation with the primary pair bit-for-bit untouched, and then freezing every
later primary slice because `generationPoolKey` and `generationQuote` disagreed
(`RedemptionExt.sol:500-518`, `TreasuryGovernor.sol:699-709`).

**Exhaustion is not completion.** `maxTotalBps` is the size of the *mandate*, not
the size of the *pair*. A fully-spent 2500-bps mandate leaves ~76% of the pair in
the old asset, and flipping the denomination on that pointed the perp engine at
the minority pool — the thin-pool mark this protocol already treats as dangerous
(`RedemptionExt.sol:479-498`, `TreasuryGovernor.sol:681-697`).

`MAX_ENVELOPE_BPS` is 30,000 (`:257`). That is a **spend budget**, not a fraction
of the LP; `conversionFor(spendBps, sliceBps)` (`:266-275`) converts it into the
share of the position it actually moves, because "30,000" is not 300% of
anything.

---

## 6. The oracle — what fails safe, what fails open

`cauldron/QuoteOracle.sol`. Its job is to turn a raw amount of any quote asset
into US dollars, so that volume, death detection and rotation floors mean the
same thing in every pool.

`usdPerRawUnit(quote)` returns the USD value of **one raw unit**, scaled 1e18.
Raw unit, not whole token, so a caller multiplies and divides once and handles no
decimals itself (`:190-201`). **Zero means "cannot judge", never "worth
nothing"** — and every caller is obliged to treat it that way.

### Every condition that produces zero

| Condition | Cite |
|---|---|
| Pegged asset — returns `1e18 × 1e18 / 10^decimals` and consults no feed at all | `:207` |
| No aggregator configured | `:208` |
| Sequencer feed says down, is inside the grace period, has `startedAt == 0` or in the future, or reverts | `:209`, `:320-342` |
| `latestRoundData()` reverts (retired, migrated, access-controlled, or code-less) | `:231-238` |
| `answer <= 0` | `:239` |
| `updatedAt == 0` or in the future | `:245` |
| `block.timestamp − updatedAt > heartbeat` | `:246` |
| `decimals()` reverts | `:249-253` |
| Normalised price outside `[minUsd, maxUsd]` when either bound is set | `:267-268` |

The revert branch is not a detail. A stale feed degraded to 0; a *reverting* feed
used to throw straight through the cache, so the same real-world condition
produced opposite outcomes — one kept a generation alive, the other pushed it
toward a permissionless, irreversible relaunch (`:211-228`).

A pegged asset is priced at exactly $1 and has none of these failure modes
(`:70-88`). The trade is stated: a depeg is not tracked, which mis-measures
*volume* by the depeg and cannot make the protocol insolvent. The alternative was
live on Sepolia — a USDC/USD feed drifted 23.7 h against a 12 h heartbeat and a
USDG generation would have recorded no volume at all.

### Which caller is safe and which is open

| Caller | Reads | On "cannot price" | Direction |
|---|---|---|---|
| `CauldronHook._toUsd` → volume, death | `cachedUsdPerRawUnit` | keeps the **last good** factor (`:305-312`) | **fails open** — deliberately: a zero would read as "no trading" and push a live generation toward death, which is irreversible |
| `QuoteRotator._oracleFloor` → `swapOnce` | `_usdLive` — **uncached** (`:601-614`) | returns 0, and `swapOnce` reverts `NotPriceable` when an oracle is wired (`:390`) | **fails closed** |
| `QuoteRotator.arbStep` | `_usd` — **cached** (`:616-625`) | reverts `NoRoute` if either leg is 0 (`:570`) | fails closed on *unpriceable*, but **will act on a price up to `TTL` old** |
| `TreasuryGovernor._requirePriceable` (propose **and** execute) | `usdPerRawUnit` — uncached (`:837`) | reverts `QuoteNotPriceable` | **fails closed** |

The floor must not use the cache, and that is the whole point: a price frozen at
whatever it was when the feed died is precisely what an attacker would want the
floor computed from. The naive repair — zeroing a stale cache entry — does not
make the floor safe, it deletes it (`QuoteRotator.sol:429-438`, `:373-389`).

Two exemptions in `_requirePriceable`, both to avoid trading a value bug for a
deadlock: **native is exempt** (`:834`), because refusing it would strand a
treasury with nowhere to rotate back to; and an **unset oracle is exempt**
(`:836`), because such a deployment measures volume in raw quote units
throughout, which is self-consistent.

| Oracle parameter | Default | Units | Cite |
|---|---|---|---|
| `Feed.heartbeat` | per feed, non-zero required | seconds | `QuoteOracle.sol:65`, `:135` |
| `Feed.quoteDecimals` | read from the token when 0 is passed | decimals of the **token**, not the feed | `:66-69`, `:137-139` |
| `Feed.pegged` | false | flag | `:88`, `:153-160` |
| `Feed.minUsd` / `maxUsd` | 0 / 0 (disabled) | whole USD, 1e18 | `:92-93`, `:175-180` |
| `gracePeriod` | 3600 | seconds since the sequencer came back | `:104`, `:182` |
| `TTL` | 15 minutes | seconds a cached factor stays good | `:284` |

---

## 7. Slice mechanics — who supplies `minOut`, and what floors it

Three spending paths exist on `QuoteRotator`, and all three now require a curated
venue.

| Path | Caller | Size from | Floor from | Venue check |
|---|---|---|---|---|
| `rotateStep(route)` `:284` | anyone | `nextSliceSize()` — the plan (`:263-275`) | `size × plan.minRate / 1e18` (`:310`) | `:299` |
| `swapOnce(route, from, to, amountIn, minOut)` `:335` | **registry only** (`:341`) | the caller's `amountIn`, itself bounded by the envelope and `MAX_SLICE_BPS` upstream | `max(minOut, oracleFloor)` (`:393`) | `:359` |
| `arbStep(cheap, dear, amountIn)` `:533` | anyone | the caller's `amountIn`, bounded per **block** by `maxArbNotionalUsd` (`:581-586`) | profit in USD must exceed `minArbProfitUsd` (`:590`) | both keys, `:553` |

**`minOut` alone was never a bound.** `rotateSliceFrom` is permissionless and
took `minOut` from whoever called it, so a caller supplying 0 disarmed the only
price guard — and the frontend signs a flat 1-unit minimum, which in practice is
no guard at all. The oracle floor is now computed inside `swapOnce`, **before**
the swap, and the caller may only demand *more* than it (`:361-393`).

The floor itself (`_oracleFloor`, `:425-445`):

```
inUsd     = usdLive(from, amountIn)            0 → refuse
perUnitTo = usdLive(to, 1e18)                  0 → refuse
fair      = inUsd × 1e18 / perUnitTo
floor     = fair × (10000 − rotationSlipBps) / 10000
```

Decimals-agnostic by construction: both legs go through USD first, and the
per-raw-unit price carries the scale.

**The venue allowlist is the guard that does not depend on the oracle.** Keyed by
`PoolId`, so `fee`, `tickSpacing` and `hooks` are all pinned by the hash — listing
a pair does not list every pool on that pair (`:183-194`). Pool creation is
permissionless in v4, so a pair-shape check alone admitted any pool, including
one the caller had just created. Measured, before the fix: the same slice filled
44,325.89 USDG through the curated venue and 99.80 USDG through an attacker's —
99.775% of the treasury's money (`:345-359`). It **fails closed**: an unset
allowlist rotates nothing, because a paused treasury operation is better than a
realised loss. Deployment must call `setVenue` before `setPlan` is useful.

Vetting a venue vets its hook. Listing a hooked pool grants that hook execution
inside the rotator's own `unlock` (`:180-182`).

| Rotation parameter | Default | Units | Bound | Cite |
|---|---|---|---|---|
| `MAX_SLICE_BPS` | 2,500 | bps of the source leg, per call | constant | `RedemptionExt.sol:598` |
| `MAX_ROTATION_BPS` | 5,000 | bps of live position liquidity, per call | constant | `PoolOps.sol:941` |
| `PRIMARY_DRAINED_DUST` | 1,000 | raw liquidity units | constant | `RedemptionExt.sol:258` |
| `MAX_ENVELOPE_BPS` | 30,000 | bps of spend budget per envelope | constant | `TreasuryGovernor.sol:257` |
| `QUORUM_BPS` | 1,000 | bps of total MiFren supply at the snapshot | constant | `TreasuryGovernor.sol:277` |
| `PROPOSAL_THRESHOLD` | 5 | MiFrens | constant | `TreasuryGovernor.sol:280` |
| `VOTING_PERIOD` | 3 days | seconds | immutable; ≥ 1 day unless testnet | `TreasuryGovernor.sol:223`, `:334` |
| `ENVELOPE_LIFETIME` | 30 days | seconds | immutable; ≥ `EXECUTION_WINDOW` | `:224`, `:341` |
| `COOLDOWN` | 7 days | seconds between envelopes | immutable; ≥ 1 day unless testnet | `:225`, `:335` |
| `EXECUTION_WINDOW` | 3 days | seconds after a vote closes | immutable; ≥ 1 day unless testnet | `:229`, `:336` |
| `rotationSlipBps` | 300 | bps below the oracle's valuation | ≤ 2000 | `QuoteRotator.sol:400`, `:405` |
| `keeperBps` | 10 | bps of what a `rotateStep` slice produced | ≤ 100 | `QuoteRotator.sol:89`, `:254` |
| `arbKeeperBps` | 1,000 | bps of arb **profit** | ≤ 2000 | `QuoteRotator.sol:456`, `:486` |
| `minArbProfitUsd` | 5e18 | USD, 1e18 | none | `QuoteRotator.sol:461` |
| `maxArbNotionalUsd` | 25,000e18 | USD, 1e18, **per block** | 0 = unbounded | `QuoteRotator.sol:474`, `:581-586` |
| `plan.minRate` | none | destination raw units per 1e18 source raw units | non-zero required | `QuoteRotator.sol:74-76`, `:226` |
| `plan.interval` | none | seconds between slices | none | `QuoteRotator.sol:77` |
| `QUOTE_WATERMARK` | see `PoolOps` | address ceiling — every allowlisted quote must sort below every token | `CauldronRegistry.sol:320` |

---

## 8. Legs — recording, recovery, and foreign proceeds

A **leg** is a rotated LP position beyond the generation's primary pair:
`TreasuryLeg{quote, positionId, key}` in `generationLegs[gen]`
(`CauldronBase.sol:448`, `:460`).

**Recorded by quote, upserted not appended** (`RedemptionExt.sol:692-700`).
`openOrAddPair` tops up the same position on every later slice into the same
pair, so appending would record the same id N times and unwind it N times at
teardown.

**The leg is recorded with its own pair, not with the venue.** An earlier version
stored `route` — the pool the *quote side was swapped through* (e.g. ETH/USDG) —
rather than the pair the liquidity was actually deployed into (toQuote/token).
`recoverLegs` hands that key straight to `PoolOps.removeAll`, which uses it both
to settle the position and to *measure* what came back; with the venue key it
settled the wrong two currencies, reverted inside the per-leg `try/catch`, and
the leg stayed recorded but unrecovered — silently. Measured: after a completed
rotation the registry held zero of the destination asset at relaunch, having
"recovered" every leg (`:431-444`).

### Reading them

| Function | Reached via | Cite |
|---|---|---|
| `legCount(gen)` | facet | `:677` |
| `legAt(gen, i)` → `(quote, positionId, key)` | facet | `:682-689` |
| `legProceedsOf(asset)` | facet | `:810` |

### Recovering them

| Entry | Gate | Who can call it | Cite |
|---|---|---|---|
| `recoverLegs(gen)` | `gen != 0 && gen < currentGeneration` — **past generations only** | anyone, through the registry forwarder | `:732-735`, `CauldronRegistry.sol:290` |
| `recoverLegsAtTeardown(gen)` | none on the generation | **nobody externally** — there is no registry stub and the registry has no fallback; the relaunch path reaches it by `delegatecall` | `:748-750`, `CauldronRegistry.sol:1605-1619` |

**`recoverLegs` now has a way in, and the gate is on the public side.** The retry
was documented and unreachable: the registry had no stub, the registry has no
catch-all fallback, so `registry.recoverLegs(gen)` died as an unrecognised
selector — and calling the deployed facet directly ran against the facet's own
empty storage and returned `(0, 0)`. The forwarder added in `8237167` costs 15
bytes the registry did not have, which is what the preceding size refactor paid
for (`CauldronRegistry.sol:276-290`).

The gate is the reason the two entries are separate functions. Unwinding a
**live** generation's legs is not a rescue, it is an attack: it pulls rotated
liquidity out of its pools, parks it idle in the registry, drops the linked
sibling volume and can make a healthy generation read as dying
(`:725-731`). The teardown entry needs no such gate because it runs on the
generation being dismantled, at a point where that generation is still
`currentGeneration`. **Do not add a forwarder for `recoverLegsAtTeardown`** — the
absence of one is its access control (`:742-747`).

`_recoverLegs` (`:752-806`) walks the array backwards, and:

- is **best-effort per leg** — a `try/catch` around `removeAll`, so one pool that
  cannot be unwound does not block a rebirth and strand every other leg. A failed
  leg stays recorded, which is exactly what makes the retry meaningful;
- is **idempotent** — legs are swap-popped as they are taken, so a second call
  recovers nothing rather than reverting;
- aggregates the **token** side unconditionally, because every leg holds the same
  dying generation's token (`:792`);
- matches the quote side against
  `generationPoolKey[gen].currency0`, **not** `generationQuote[gen]` (`:783`).

That last line is one denomination per sum. `quoteOut` is returned to
`CauldronRegistry._removeLiquidity`, added to `ethRecovered` and passed to
`PoolOps.seedFunding` as an amount measured in the primary pair's own asset. A
completed rotation flips `generationQuote` while the primary position stays on
the launch pair — so matching on the flipped value added 6-decimal USDG to
18-decimal wei in one integer, and the mixed magnitude was then requested as raw
USDG at seeding: `TRANSFER_FROM_FAILED`, and a machine that could never be reborn
(`:768-782`, `CauldronRegistry.sol:958-972`).

**Foreign proceeds are booked, not counted.** A leg in any other asset is still
fully recovered — the position is unwound and the proceeds land in the registry —
but they go to `legProceeds[asset]` with a `LegProceedsBooked` event
(`:795-797`). They cannot be redeployed automatically: `recoverLegs` runs inside
`_removeLiquidity`, which is tearing down every pool the dying generation had, and
the new generation's quote is not chosen until `seedFunding` ninety lines later.
There is no LP in existence that can accept a foreign asset at that instant, and
converting would need a swap — and therefore a price — on the one path that must
never be why the machine cannot be reborn (`:814-830`).

`sweepLegProceeds(asset, to)` (`:847-857`) moves them, owner-gated because the
destination is a policy choice. It clears the booking **before** the transfer.
Both it and `legProceedsOf` shipped without registry stubs and were dead until
forwarders were added (`CauldronRegistry.sol:292-300`).

---

## 9. Denomination — every quantity that can outlive a rotation

The rule the tree enforces: **one denomination per sum**. A name that lies has
cost this protocol at least three real bugs (`PerpVault.sol:80-84`).

| Stored quantity | Where | Across a rotation | Cite |
|---|---|---|---|
| `generationQuote[gen]` | registry | **Converted** — flipped to the destination, and only when a *primary* slice spends a *whole-position* mandate | `RedemptionExt.sol:526-527` |
| `generationPoolKey[gen]`, `generationPositionId[gen]` | registry | **Carried** — always stay on the launch pair; the 69× redemption reserve is held under the same key | `:349-368`, `:783` |
| `generationReservePositionId[gen]`, `reserveTickLower/Upper[gen]` | registry | **Carried** — read with `generationPoolKey[gen]` on every redemption | `:669-672` |
| `generationLegs[gen][i].quote` | registry | **Carried**, one asset per leg; upserted by quote so a pair is never recorded twice | `:692-700` |
| `legProceeds[asset]` | registry | **Carried per asset** — never summed across assets, never folded into `ethRecovered` | `:793-798` |
| `ethRecovered` at relaunch | registry | **Refused** if it would mix — matched on the primary pair's own `currency0` | `:783`, `CauldronRegistry.sol:966-972` |
| `quoteScale[quote]` | registry | **Carried** — set once at allowlist time, identity (1e18) for native | `CauldronRegistry.sol:322-323` |
| `envelope.movedBps`, `movedPrimaryBps` | governor | **Carried** — bps of a source leg; dimensionless, so no conversion exists or is needed | `TreasuryGovernor.sol:122-128`, `:722` |
| `PerpEngine.quote` | engine | **Converted** by `syncGeneration` — and **refused** while `plv != 0` (`VaultStaked`) | `PerpEngine.sol:1116-1117` |
| `PerpEngine.plv`, `longOiEth`, `collateral`, `principal` | engine | **Carried** as bare counters; the refusal above is what keeps them meaning one asset | `PerpEngine.sol:378-398`, `:1094-1111` |
| `PerpEngine.insuranceEth`, `tokYieldEth`, `payoutOwed[]` | engine | **Carried, and NOT covered by the refusal** — see §10 | `PerpEngine.sol:225`, `:328`, `:358` |
| `PerpVault.ethShares`, `pendingEth` | vault | **Carried** — legacy names for "the engine's current quote"; one asset at a time, and a queue left against zero backing is written to zero by `_haircut` | `PerpVault.sol:69-92`, `:280-287` |
| `QuoteRotator.plan.doneIn`, `gotOut` | rotator | **Carried** in the plan's own `from`/`to` units; `gotOut` records what actually arrived, never what was expected | `QuoteRotator.sol:71-73`, `:313-314` |
| `QuoteRotator.arbUsdThisBlock` | rotator | **Converted** to USD, which is the only common unit across two different assets | `QuoteRotator.sol:565-586` |
| `CauldronHook._feeAsset` | hook | **Converted** per swap — transient, written from the pool's quote side before any routing | `CauldronHook.sol:1492-1493` |
| `CauldronHook.legacyBuffer` / `legacyBufferAsset` | hook | **Refused** — buffers any quote but never mixes two | `CauldronHook.sol:1388-1397` |

Rotation direction, stated: **native `address(0)` is a legitimate destination.**
The `remaining == 0` liveness test is what made rotating *back* to ether possible
(`RedemptionExt.sol:308-317`), and `linkVolume` had to learn that a pool is not
its own sibling for the same reason — the destination pair of a rotation home is
the primary pair itself (`CauldronHook.sol:1601-1609`).

---

## 10. What can go wrong, and what protects you

**A rotation cannot execute while a perp position is open.** `linkVolume` reverts
`PerpsOpen` (`CauldronHook.sol:1598`). That is the interlock, and it is also the
proof that lets the quote flip re-sync the engine safely in the same transaction.
Do **not** work around it by unsetting `perpEngine` — a zero there disables both
guards at once (`CauldronHook.sol:1587-1595`).

**The floor is only as good as the oracle, and the venue list is the guard that
does not need one.** With an oracle wired, `swapOnce` refuses an unpriceable
rotation outright (`QuoteRotator.sol:390`). With **no** oracle wired, `_oracleFloor`
returns 0 and the caller's `minOut` stands alone — which on a permissionless path
means the venue allowlist is the only protection left. Both halves are required
(`:419-424`).

**`arbStep` is permissionless and judges profit off a cached price.** It uses
`_usd` (cached, up to `TTL` = 15 minutes old, `:616-625`) rather than the live
read the rotation floor uses. What bounds it: both venues must be curated
(`:553`), the destination must be allowlisted (`:560`), profit must exceed
`minArbProfitUsd`, and spend is capped per **block** at `maxArbNotionalUsd`
(`:581-586`). It was per *call* until recently, which measured as 12
individually-compliant arbs in one transaction moving $36,000 against a $25,000
cap.

**An arb shifts allocation, not just captures spread.** Buying in the ETH pool
and selling in the USDG pool leaves less ETH, more USDG and the same token — it
does not return to the starting asset (`:507-516`). The per-block cap is what
stops repeated arbs re-allocating the treasury behind governance's back.

**A slice is bounded three ways and none of them is a price.** `MAX_SLICE_BPS`
(25% of the source leg), `MAX_ROTATION_BPS` (50% of live position liquidity), and
the envelope's remaining budget. Price protection is separate: the oracle floor
plus the caller's `minOut`.

**Residual limitations, stated plainly:**

1. **The tail never moves.** Slices take a share of what remains, so a
   fully-spent 10,000-bps mandate converges on ~68% converted and an exactly-95%
   conversion needs ~27,500 bps of budget (`TreasuryGovernor.sol:232-248`). The
   flip is an **intent-plus-exhaustion** test, not a drained-position test —
   demanding a drained position would make completion unreachable and the feature
   dead (`RedemptionExt.sol:519-525`). A residual stays in the launch pair until
   relaunch.
2. **`generationQuote` and `generationPoolKey` are permanently allowed to
   disagree**, by design, because the redemption reserve lives under the launch
   key. Every consumer must know which one it wants. Three separate Criticals in
   this codebase were the same mistake in different places
   (`RedemptionExt.sol:349-370`, `:768-782`, `CauldronRegistry.sol:958-965`).
3. **Only `plv` gates the perp engine's quote adoption.** `insuranceEth`,
   `tokYieldEth` and `payoutOwed` are quote-denominated counters that
   `syncGeneration` does not check (`PerpEngine.sol:1116`), and all three pay out
   through `_pushQuote` in whatever `quote` says at claim time. See
   [`13-PERPS.md`](13-PERPS.md) §11. *A broader guard was uncommitted in the
   working tree while this was written and is not part of the commit documented
   here.*
4. **Foreign leg proceeds need a manual sweep.** They are booked correctly and
   nothing is lost, but `sweepLegProceeds` is owner-gated and the preferred
   destination — paying them to genesis holders as a dividend — is not wired,
   because `MiFrensDividend.fundToken` is `funder`-gated to the hook and the
   registry cannot call it (`RedemptionExt.sol:832-841`).
5. **An unset venue allowlist silently rotates nothing.** That is the safe
   direction, but on a fresh deployment it presents as a governance problem
   (`NoRoute`) rather than a configuration one (`QuoteRotator.sol:175-178`).
6. **`setPlan` can be called from any state** and resets `doneIn`/`gotOut` to zero
   (`QuoteRotator.sol:235-236`). A plan overwritten mid-flight loses its own
   record of what it already converted; the converted assets themselves are
   unaffected and remain withdrawable.

---

## Verification

- **Commit documented against:** `880220a` — the most recent commit touching the
  rotation files. Every citation was read with
  `git show 880220a:contracts/solidity/<path>`, not from the working tree. A
  sample was re-verified after writing.
- **The working tree had diverged when this was written.** `git diff 880220a --
  contracts/solidity/cauldron/` reported +246/−16 lines across six files,
  including `TreasuryGovernor.sol` (+113). Those edits are **not** reflected here
  and they shift line numbers. Re-check any citation against `880220a`.
  [`04-GOVERNANCE.md`](04-GOVERNANCE.md) names the same commit but its
  `TreasuryGovernor.sol` line numbers are from the working tree; where the two
  documents disagree on a line number for that file, they describe different
  trees.

### Documentation debt — where a comment or a prior doc disagrees with the code

1. **`audit/graph/rotation.md`** was used as a structural cross-check for §3 and
   §5 and is behaviourally accurate, but **every line number in it is stale** — it
   predates `1b558b8`, `26c2722`, `89aa06d`, `c2e3afa`, `8237167`, `f337813` and
   `880220a`. Example: it cites `allowance` at `TreasuryGovernor.sol:643`; at this
   commit it is `:652`. Everything quoted from it here was re-derived from source.
2. **`audit/graph/rotation.md` §"Machine 2"** states the registry's
   `setRotationWiring` stub "is ungated (CauldronRegistry.sol:272)". That remains
   true in shape — the stub forwards and the facet applies `onlyOwner`
   (`RedemptionExt.sol:260`) — but a reader should not take it as an unguarded
   entrypoint.
3. **`cauldron/TreasuryGovernor.sol:545-565`** documents a positional
   `MAX_WINNER_SCAN` bound at length and then states it was removed. The surviving
   block records a rejected design, not the code; the scan is bounded by **time**
   (`winner`, `:602-611`).
4. **`cauldron/TreasuryGovernor.sol:840-841`** calls `setQuoteOracle`
   "Timelock-set". The gate is `msg.sender != guardian` (`:843`).
5. **`cauldron/QuoteRotator.sol:296-298`** says `swapOnce` "is deliberately not
   gated this way — it is owner-only". `swapOnce` is `onlyRegistry` (`:341`), not
   `onlyOwner`; the venue allowlist **is** enforced on it (`:359`). The comment
   predates both changes.
6. **`cauldron/QuoteRotator.sol:638-640`** cites `RedemptionExt:297` for the
   `withdraw` call site; at this commit it is `:399`. Intra-tree line references
   throughout these files have drifted and should be treated as prose, not
   citations.
7. **`cauldron/RedemptionExt.sol:605-606`** still declares
   `event QuoteRotatorSet` and `event RotationBegun`. Neither is emitted anywhere
   in the file.

### Not verified here

- The measured figures quoted inside the comments (44,325.89 vs 99.80 USDG on the
  venue drain; 12 arbs moving $36,000 against a $25,000 cap; 6,421 vs 363,633 gas
  on the `winner` scan; the 23.7 h Sepolia USDC feed drift) are the code's own
  measurements and were not re-measured in this pass.
- `PoolOps.openOrAddPair`, `PoolOps.removeAll` and `PoolOps.seedFunding` were read
  only at their call sites and for `MAX_ROTATION_BPS` / `removePartial`. Their
  internals are **unverified** here.
- Whether any deployment has actually called `QuoteRotator.setVenue` is not
  checked by this document. The allowlist fails closed, so an unconfigured
  deployment cannot rotate at all.
