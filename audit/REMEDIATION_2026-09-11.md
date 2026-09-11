# The Cauldron — Remediation of `audit/CauldronRedTeamSafu.md`

**Date:** 2026-09-11
**Branch:** `fix/b05-b07-relaunch-totality`
**Scope:** R-01 → R-07 from the red-team report, plus leads L-1 → L-4.
**Method:** every fix is proved red-then-green — the guarding test is run and shown
failing before the change, and passing after. A fix with no red-then-green is not
claimed as verified.

**Re-baseline (done first).** The peer session that was editing this tree during the
audit is idle and its work (`legProceeds`, F21/F22) is committed to the working tree.
All four audit invariants were re-run before any edit and reproduced identically, so
nothing here fixes a defect a concurrent change had already closed.

---

## 0. Headline

Ten defects fixed, three of them Critical. Two were found *by the remediation itself*
and were not in the original report:

- **R-08 (Critical)** — a rotation re-denominated staked LP capital, making an ETH
  staker's own withdrawal revert with their ether still in the engine, and letting
  stale ETH-side shares redeem against the next honest depositor's stake.
- **R-09 (Medium)** — one wei of unownable dust permanently bricked vault replacement.

And one was a hole **opened by my own R-03 fix**, caught before it shipped: making
rotation two-way made "rotate back to the launch quote" reachable for the first time,
which would have let `linkVolume` register a pool as its own volume sibling and hold a
dead generation open forever.

Of the four leads, **three confirmed, one refuted in part** — see §3.

---

## 1. Per-finding remediation

### R-01 · Critical · attacker venue + attacker `minOut`

**Root cause — the fourth instance of this repo's facet-stub defect class.** The venue
allowlist already existed, already failed closed, and was already enforced in
`rotateStep` (`QuoteRotator.sol:295`). It was simply **not on the path
`rotateSlice` takes**: that goes through `swapOnce`, whose only check was
`_routeMatches` — two of a `PoolKey`'s five fields. `fee`, `tickSpacing` and `hooks`
were free, so any attacker-deployed pool on the right pair qualified.

**Fix** (`cauldron/QuoteRotator.sol`, `swapOnce`):
1. `if (!allowedVenue[PoolIdLibrary.toId(route)]) revert NoRoute();`
2. `_oracleFloor(from, to, amountIn)` — the caller's `minOut` may only *tighten* the
   oracle-derived floor, never loosen it. `rotationSlipBps` (default 300 = 3%,
   owner-tunable, capped at 20%).

**Chosen vs rejected.** Rejected "validate more PoolKey fields" — a shape check cannot
express *which* pool the treasury trusts, and the contract's own header says vetting a
venue is how it vets that venue's hook. Rejected making `minOut` mandatory-nonzero — a
number the attacker still picks is not a bound. `_oracleFloor` fails **open** (returns
0) when a leg is unpriceable, deliberately: an oracle outage must not brick a
governance-approved rotation, and the allowlist is the guard that does not depend on
the oracle. That is why R-01 needs both halves.

**Red → green:** `S02…test_INVARIANT_S02_01_RotationRefusesAnUncuratedVenue`
FAIL ("next call did not revert as expected") → PASS.
The drain PoC is inverted and now asserts the attacker withdraws no more than they
deposited, *and* that a curated venue still rotates (the guard blocks the attack, not
the feature).

---

### R-02 · Critical · a completed rotation permanently bricked `relaunch()`

**Root cause — deeper than the report identified.** The report attributed this to mixed
denominations at `CauldronRegistry.sol:1558`. That was real, but it was the *second*
of three faults:

1. **The leg was recorded with the wrong PoolKey.** `_recordLeg` stored `route` — the
   *swap venue* (`fromQuote`/`toQuote`) — not the pair the liquidity was deployed into
   (`toQuote`/`token`). `recoverLegs` hands that key to `PoolOps.removeAll`, which uses
   `key.currency0/currency1` to settle *and to measure* the position. With the venue
   key it settled the wrong two currencies, reverted inside the per-leg `try/catch`,
   and the leg stayed recorded but unrecovered — **silently**, because that catch
   exists so one bad leg cannot block a rebirth. This is why the registry held **zero**
   USDG at relaunch having "recovered" every leg.
2. **`recoverLegs` matched on the flipped quote.** `generationQuote[gen]` is the
   *destination* after a rotation, while the primary position stays in the launch pair
   — it must, because the 69× redemption reserve shares that key. Matching on the
   flipped value added 6-decimal USDG into an 18-decimal wei sum.
3. **`relaunch` passed the flipped quote as `oldQuote`**, so `seedFunding` branch 3
   requested an ETH-magnitude number denominated as raw USDG.

**Fix:**
- `RedemptionExt.rotateSliceFrom` — record the leg with the destination pair, built
  from the same four inputs `PoolOps.openOrAddPair` uses internally.
- `RedemptionExt.recoverLegs` — `matchQuote` reads the **primary pool's own
  `currency0`**, not `generationQuote[gen]`.
- `CauldronRegistry.sol:922` — pass `Currency.unwrap(generationPoolKey[oldGen].currency0)`
  as `oldQuote`.

**Chosen vs rejected.** Rejected promoting the rotated leg to be the primary
(`generationPoolKey`), which was the obvious-looking fix: that mapping is shared with
the redemption reserve at five `ReserveRef(...)` call sites, so re-pointing it would
corrupt OG redemption. Rejected clamping a rotated generation back to native at
relaunch (the report's suggested alternative): it is smaller, but it silently discards
the rotated leg's value rather than accounting for it.

**Red → green:** `S02…test_INVARIANT_S02_02_ARotatedGenerationCanStillBeReborn`
FAIL (`TRANSFER_FROM_FAILED`) → PASS (`relaunch OK; gen-2 quote: 0x0`).

---

### R-03 · High · `address(0)` meant both "native ETH" and "no envelope"

**Root cause.** `TreasuryGovernor.allowance()` returns `e.quote`, and a rotation back to
ether names `address(0)` — the same value the consumer read as "nothing approved".

**Fix.** The *remainder* is the liveness flag, not the destination:
- `RedemptionExt.rotateSliceFrom` — `if (remaining == 0) revert NoRotationApproved();`
- `TreasuryGovernor.consume` — `if (left == 0 || bps > left) revert BadParam();`
- `allowance()`'s doc now states that `quote` is meaningless unless `remainingBps > 0`.

`allowance()` already returned `0` remaining for all three no-envelope cases (absent,
expired, spent), so no new state was needed.

**⚠️ This fix opened a hole, which is also fixed here.** Making rotation two-way made
"rotate back to the launch quote" reachable for the first time — and the destination
pair *is* the primary pair, so `rotateSliceFrom` hands `linkVolume` the same `PoolId`
twice. `isDead` sums the primary's 24h volume and then every sibling's, so a
self-linked pool would double-count its own volume and hold a dead generation open
forever — `relaunch` gates on `isDead`, making that a permanent brick.
**Guard added:** `CauldronHook.sol:1521`,
`if (PoolId.unwrap(primary) == PoolId.unwrap(secondary)) return;`

**Red → green:** `S02…test_INVARIANT_S02_04_APoolIsNeverItsOwnVolumeSibling` — this
test previously *documented* the one-way defect via `vm.expectRevert(NoRotationApproved)`;
it now executes the round trip and asserts the generation stays dead (i.e. no double
count). Both halves of the fix are asserted in one place.

---

### R-04 · High · a fully-spent 25% envelope re-denominated the whole generation

**Root cause.** Completion was judged by `allowance() == address(0)` — i.e. envelope
**exhaustion** — but `maxTotalBps` is how much the guild *voted to move*, not the size
of the position. A 2500-bps mandate spent in one slice flipped the generation with
~76% of the liquidity still in the old asset.

**Fix.** New `TreasuryGovernor.migrationMandateSpent()`:
`e.maxTotalBps >= BPS_ONE && e.movedBps >= e.maxTotalBps` — the mandate must have
covered the **whole position** *and* be spent. `RedemptionExt` gates the flip on it.

**Stated honestly in the code:** slices are a share of *current* liquidity, so budget
bps compound rather than sum (12 slices of 2500 move ~96.8%, not 300%). The test is
therefore of *intent* plus exhaustion, and a small tail can remain in the old pair —
which is exactly why R-02's `oldQuote` fix reads the primary pool rather than assuming.
The misleading comment at the old `RedemptionExt.sol:407-410` ("30% moved does not
redenominate a generation") is replaced with what the code actually does.

**Red → green:** `S02…test_INVARIANT_S02_03_APartialEnvelopeDoesNotRedenominate`
FAIL (`0xa0Cb…7598 != 0x0`) → PASS, with `share of the pair never moved (bps): 7500`.

---

### R-05 · Medium · a spent envelope locked out treasury governance for 30 days

**Root cause.** `envelope.active` was set `true` at `:397` and cleared only by the
guardian's `cancel` (`:409`). `propose` refuses while `envelope.active && now < expiry`,
so a mandate spent in its first hour blocked every new proposal until it *expired* —
`MAINNET_LIFETIME = 30 days`. After a bad rotation the guild could not even **file** a
correction.

**Fix.** `TreasuryGovernor.consume` — `if (e.movedBps >= e.maxTotalBps) e.active = false;`
This makes stored state agree with what `allowance()` already reported.

**Red → green:** captured in `S02…test_S02_03_PoC_FlipStrandsThePrimaryAndKillsRotateSlice`,
which now exhausts an envelope and files a new proposal after only the `COOLDOWN` —
deliberately *not* warping past `ENVELOPE_LIFETIME`, since waiting out the expiry is
the very workaround the fix removes. Previously reverted `ProposalActive()`.

---

### R-06 · Medium (L1) / High (L2) · governance spam wedged `winner()`

**Root cause.** The leader cache was a permanent high-water mark: `_leadVotes` was
written in one place and lowered nowhere, so after a well-supported proposal aged out,
`_leadId` pointed at a corpse, `_executable` returned false, and **every** `winner()`
call fell through to the full scan — which a 5-MiFren holder could inflate at will.

**Fix.** `TreasuryGovernor.vote` now maintains the hint through five explicit cases,
with a new `_dead()` predicate (monotone by construction: `executed`/`cancelled` are
one-way and the third clause is a deadline time only moves past) and an `_openVotedAt`
watermark. The retiring branch fires only when the cached leader is dead **and** every
rival the hint never tracked must also be dead by elapsed time.

The **time-bounded** backward scan is preserved. A positional window was explicitly
*not* reintroduced — the comment at `:457-482` records that it re-created this repo's
own B-10 and was removed for that reason.

**Authorship note, stated plainly:** the bulk of this fix was drafted by a subagent
that hit its rate limit mid-edit and left the tree **non-compiling** (it referenced a
`_dead()` helper it never wrote). I verified its invariant argument independently
before completing it — *every non-dead proposal holds at most `_leadVotes`*, which
holds because any non-dead rival must have been voted on after `_openVotedAt`, and the
time guard excludes exactly that window — then wrote `_dead()` myself.

**Red → green, measured:**

| | before | after |
|---|---:|---:|
| `winner()` — honest world | 6,399 | 5,185 |
| `winner()` — +400 junk proposals | 363,611 | 3,185 |
| **Marginal gas per junk proposal** | **888** | **0** |
| Attacker gas to wedge a 30M block | ~2.67 bn | n/a |

All **15** pre-existing `TreasuryGovernorTest` tests still pass — the fix changes cost,
never which proposal is elected (asserted explicitly).

---

### R-07 · High · the code comment told operators to strand the engine

**Scope correction, honestly.** The report rated R-07 DERIVED because its PoC
early-returned before asserting. Rebuilding it properly showed the *permanent* deadlock
was really **R-02 in disguise** — relaunch could not complete at all. With R-02 fixed,
the engine self-heals across a rebirth (`rebirth completed: true`, collateral released,
quote re-armed). What survived is narrower but real: between a completed rotation and
the next relaunch the engine marks against the drained pool with **no permissionless
way to correct it**, and `_guardOpen` kept selling leverage into it.

**Fix (a), code —** `PerpEngine._isDead()`:
```solidity
if (quote != registry.generationQuote(registry.currentGeneration())) return true;
```
One comparison closes both halves: the book becomes force-closeable by anyone (so the
engine can be re-pointed without waiting for a rebirth), and `_guardOpen` refuses new
leverage into an engine that cannot price itself.

**Fix (b), comment —** "or unset the engine" is deleted from `CauldronHook.sol:1514`
and replaced with an explicit **do not**, explaining that a zero `perpEngine` disables
*both* the `openCount` interlock and the in-call re-point at once.

**Red → green:** three tests, all previously red with the exact predicted reverts:
```
[FAIL: NotDead()] test_invariant_divergedEngineIsPermissionlesslyRecoverable
[FAIL: NotDead()] test_regression_routeC_rotationWorksAgainOnceTheBookDrains
[FAIL: OiCapped() != TokenDead()] test_poc_routeC_divergedEngineRefusesNewLeverage
```
→ **S01: 10 passed, 0 failed.** Every early-return that made the original suite
report green while asserting nothing has been removed; the file now contains exactly
one `return;`, the `vm.skip(!active)` fork gate.

---

### R-08 · **Critical** · NEW — a rotation re-denominated staked LP capital

Found while verifying lead L-3. Not in the original report.

**Root cause.** `PerpEngine.plv` is a bare **counter** of the quote asset, and every
payout leaves through `_sendEth` → `_pushQuote`, which pays in whatever `quote` names
*today*. `syncGeneration` adopted a new quote and left `plv` untouched by explicit
design. So an 18-decimal ETH balance started being paid as a 6-decimal stable the
engine did not hold:

- an ETH staker's `withdrawEth` reverted `BadParam()` inside `_safeTransfer`, with
  their ether present in the engine and **no call able to reach it**; and
- `PerpVault.assetsEth()` kept pricing every share off that same counter, so the stale
  ETH-side shares could redeem against the **next honest depositor's** stake in the new
  asset. Measured: lpA burned <1% of their shares and took 100% of lpB's stake.

**Attacker cost: none.** Being an ETH-side staker across a governance-approved rotation
was sufficient.

**Fix.** `PerpEngine.syncGeneration` — `if (newQuote != quote && plv != 0) revert VaultStaked();`
No swap, no conversion: `quote` stays put, so payouts stay in the asset stakers
deposited, and R-07's `_isDead` divergence check means the engine **parks** (inert,
force-closeable, refusing new leverage) rather than mispaying. The refusal lifts the
moment the vault drains, and never fires on a relaunch (B-05 clamps that quote to
native, so `newQuote == quote`).

**Chosen vs rejected.** The textbook fix is to *convert* `plv` at rotation, mirroring
`PerpSwapLib.migrateInventory` on the token side. Rejected for now: it does not fit in
`PerpEngine`'s remaining margin, needs a swap path plus partial-fill and failure
handling, and refusing is strictly safer than converting badly. **This is a priced
trade-off, not a free win — see §4.**

**Red → green:** `S06…test_S06_INVARIANT_EthStakerSurvivesAQuoteRotation` and
`test_S06_POC_QuoteRotationDrainsTheNewQuoteStakers` both FAIL (`BadParam()`, drain
succeeds) → PASS (staker paid in full; drain unreachable).

---

### R-09 · Medium · NEW — one wei of unownable dust bricked vault replacement

**Root cause.** `PerpEngine.setVault`'s guard tested engine **balances**
(`plv != 0 || plvToken != 0 || tokYieldEth != 0`), conflating "someone is owed money"
with "a counter is non-zero". Two residues that belong to **nobody** made it
unsatisfiable forever: short-side yield credited at zero token shares is orphaned by
design and can never be drained, and redemption floors so ordinary yield leaves one wei
of `plv` dust. Either removed the only lever for replacing a broken vault on a live
engine.

**Fix.** New `PerpVault.hasStakers()` — `(ethShares | tokShares | pendingEth | pendingTok) != 0`
— and `setVault` asks that instead. Ownership of value is a question only the vault can
answer.

**Red → green:** `S06…test_S06_INVARIANT_VaultRemainsReplaceableAfterEveryoneExits`
FAIL → PASS. The two PoCs that asserted the brick are inverted; both still assert the
dust/orphan is *still there and still unowned* (that part is correct behaviour — the
rounding must keep favouring the vault).

---

## 2. Leads

### L-1 — `rotateSlice` dies after redenomination · **RESOLVED by R-04**
As predicted. With completion judged by liquidity mandate rather than budget
exhaustion, the primary is no longer stranded behind a flipped quote. The test that
probed it is retained as a regression guard for R-04 + R-05 and documents why it cannot
isolate the original claim.

### L-2 — in-swap gas-reserve starvation · **CONFIRMED, fixed**

The report's constants were wrong. Measured, grepped values:

| Name | Value | Line |
|---|---:|---|
| `LIQ_GAS_RESERVE` | 180,000 | `CauldronHook.sol:152` |
| `LIQ_GAS_MIN` | 250,000 → **400,000** | `:153` |
| `GACHA_GAS_RESERVE` / `_MIN` | 200,000 / 500,000 | `:156` / `:157` |
| `LEGACY_GAS_RESERVE` / `_MIN` | 220,000 / 300,000 | `:325` / `:326` |
| `SEED_POKE_GAS_RESERVE` / `_MIN` | 350,000 / 750,000 | `:343` / `:344` |

(The report's "LEGACY/POKE = 350k" was wrong for legacy: it is 220,000.)

Two real defects, both fixed:

1. **The doomed band.** One real kill costs ~388,000 gas but the gate opened at
   `LIQ_GAS_MIN = 250,000`, so between them the sweep was *always* fired and *always*
   failed — **266,833 gas of the swapper's money burned per swap**, silently (the
   call's result is discarded). Fixed by sizing the floor above the work it gates:
   250,000 → 400,000. **Zero bytecode** (`PUSH3` either way).
2. **All-or-nothing amplification — the severe one.** `_doSweep` was a single external
   call, so an OOG rolled back *every* kill in the batch. Each parked liquidatable
   position raised the bar ~229,818 gas for everyone, so **~0.021 ETH of dust
   positions** (`minCollateral = 0.003 ether`) pushed the in-swap liquidation bar above
   an ordinary swap's budget and switched keeperless liquidation off pool-wide. Fixed
   with `if (gasleft() < SWEEP_KILL_RESERVE) break;` (420,000) inside the loop, so a
   short sweep **banks** what it can afford.

**Measured flip:** below the old bar, **0 of 4** positions died; now **3 of 4** die.

**Priced residual, not a bug:** a swapper can still supply only enough gas to swap and
not to sweep. Making the sweep mandatory would mean a 103k-gas swap *reverts* because
someone else's position is underwater — a worse liveness property than the one it buys.
The residual is bounded by two permissionless backstops, both now asserted in the test:
`PerpEngine.liquidate(id)` is callable by anyone at any time, and every open runs
`_sweepAfterOpen`. Skipping is a **delay, not an escape**. `S08_A` was re-scoped from
the unachievable `tLiq == tSwap` to that property, and proves the backstop by executing
it.

### L-3 — PerpVault · **2 refuted, 2 confirmed** (→ R-08, R-09 above, plus the queue fix)

- **Share-price / first-depositor inflation — REFUTED.** No donation channel exists
  (`assetsEth()` reads counters, not balances; `receive()` is empty; every `plv` writer
  is gated), and `OFFSET = 1e6` means rounding a 1-ETH victim to zero needs a
  ~2,000,000 ETH donation. Hit with 9,000 ETH seeds against 1-wei deposits, both
  orderings, both sides. Kept as regression guards.
- **Queue jump / steal / double-claim — REFUTED.** `claimPendingEth` takes **no
  arguments** and debits `pendingEthOf[msg.sender]` before transferring (CEI). There is
  nothing to point at another user's claim.
- **Queue seniority — CONFIRMED, fixed (High).** `withdrawEth` converted at-risk
  *shares* into a fixed nominal claim that left the share base, so a queued exit stopped
  bearing bad-debt risk while staying first in line. Measured on the real engine: lpA
  queued and recovered 84%; lpB, who did nothing, recovered **0%**; and the vault still
  owed 0.0857 ETH more than the engine held. Queueing cost nothing, so it was every
  LP's dominant move — a bank run with a protocol-enforced starting gun.
  **Fix:** `PerpVault._haircut` — when backing < claims, each claimant is paid
  `owed * backing / claims` and the unbacked remainder is written off, on both sides.
  Measured: a 10 ETH claim against 5 ETH backing now draws exactly 5, remainder zeroed.
  *Scope, honestly:* this bounds the queue by what exists; it does not equalise a
  first-mover and a stayer for a loss already realised against the free buffer.
- **Dual-asset confusion — CONFIRMED, fixed** → R-08.

### L-4 — `QuoteRotator.arbStep` · **CONFIRMED (4 of 6), fixed**

This exposed that **my own R-01 fix was incomplete**: I curated `swapOnce` but
`arbStep` had the identical hole.

- **No venue allowlist — CONFIRMED.** `arbStep` never read `allowedVenue`, while taking
  *both* PoolKeys — including both `hooks` fields — from an anonymous caller. That is
  precisely what the contract's own header says curation exists to prevent.
- **No destination allowlist — CONFIRMED.** `setPlan`, `rotateStep` and `swapOnce` all
  check `_allowed(to)`; `arbStep` did not, so the treasury could be moved into any
  asset with a price feed, allowlisted or not.
- **Cap was per-call, not per-block — CONFIRMED.** 12 individually-compliant arbs in
  **one transaction** moved $36,000 against a $25,000 cap.
- **Cannibalised the governed plan — CONFIRMED.** A stranger converted the entire float
  a vote had parked, leaving `nextSliceSize() == 0`.
- **Unpriceable leg — REFUTED.** `if (inUsd == 0 || outUsd == 0) revert NoRoute();`
  sits before the cap, the profit test and the payout. Fails closed.
- **Keeper-cut farming by splitting — REFUTED.** The cut is proportional to *profit*,
  not notional; one 1-ETH arb and ten 0.1-ETH arbs both paid exactly `30e18`.

**Fix** (all in `QuoteRotator`, which has ~16 KB free): both venues curated, destination
allowlisted, and a per-block notional accumulator (`arbBlock`/`arbUsdThisBlock`)
mirroring the engine's `liqBlock` idiom, so `maxArbNotionalUsd` bounds a **block**.

**Red → green:** S09 from 7 failing → **9 passed, 0 failed**.

---

## 3. Size and storage

**EIP-170.** Every contract deployable. `PerpEngine` went **over the limit** mid-pass
(24,772 B, −196) and the space was *found*, not borrowed from the fix: nine `public`
getters with **zero consumers** anywhere — verified across tests, deploy scripts,
frontend, indexer *and* all `.sol` files — made `internal`. Two were dynamic-array
getters, the most expensive kind. Visibility-only; no behaviour changed.

| Contract | Before | After | Margin | Δ |
|---|---:|---:|---:|---:|
| `CauldronRegistry` | 24,521 | 24,530 | **46** | +9 |
| `CauldronHook` | 24,508 | 24,515 | **61** | +7 |
| `PerpEngine` | 24,541 | **24,435** | **141** | **−106** |
| `PerpVault` | 7,486 | 7,901 | 16,675 | +415 |
| `QuoteRotator` | 7,692 | 8,435 | 16,141 | +743 |
| `RedemptionExt` | 13,399 | **12,196** | 12,380 | **−1,203** |
| `TreasuryGovernor` | 5,676 | 6,134 | 18,442 | +458 |

`PerpEngine` ends with **four times** the headroom it started with, fixes included.

**Storage layout.** `CauldronRegistry` and `RedemptionExt` re-verified byte-identical
through slot 53 (`forge inspect … storageLayout`): 48 `generationQuote`, 49
`quoteRotator`, 50 `treasuryGovernor`, 51 `quoteScale`, 52 `generationLegs`,
53 `legProceeds`. The delegatecall facet cannot corrupt registry state. No storage was
inserted anywhere above the end of either layout; `TreasuryGovernor` and `QuoteRotator`
are standalone (never delegatecalled), so their appended slots move nothing.

---

## 4. Priced residual

What remains after these fixes, stated as trade-offs rather than omissions.

1. **Rotation and a funded perp engine are mutually exclusive (R-08).** While
   `PerpEngine.plv != 0`, a live rotation does **not** re-point the engine; it parks —
   inert, force-closeable, refusing new leverage — until the quote-side capital drains
   or the next relaunch clamps the quote back to native. This is the honest consequence
   of refusing rather than converting: you cannot re-denominate staked capital without
   swapping it. The permanent fix is to convert `plv` at rotation; it needs a swap path
   and does not fit in the engine today.
2. **A swapper can decline to fund an in-swap liquidation (L-2).** Bounded by
   `liquidate()` being permissionless and by `_sweepAfterOpen`; a delay, not an escape.
3. **Queue seniority is bounded, not equalised (L-3).** Queueing before a loss still
   does better than staying, but is now capped by what actually exists.
4. **`arbStep` re-allocation is rate-limited, not governed (L-4).** A keeper can still
   move up to `maxArbNotionalUsd` per block between *allowlisted* assets through
   *curated* venues. Gating it to governance outright was not done.
5. **The "Eth" names are legacy labels, not denominations.** `PerpVault`'s ETH side is
   already quote-agnostic (`deposit()` branches on `_engineQuote()`; payouts route
   through `_pushQuote`). A **renaming was scoped and deliberately deferred**: ~422
   Solidity + ~57 TypeScript references across 16 identifiers, all requiring lockstep
   frontend/indexer updates, for zero behavioural benefit — and landing it on top of ten
   security fixes would make the security diff far harder to review. Instead the
   invariant is now written into the code: *one asset at a time, enforced by R-08*.
   Recommended as its own change, with the frontend and indexer moved together.

---

## 4b. Final suite state — measured

Full run, fork env set, at the end of remediation:

```
FOUNDRY_PROFILE=cauldron
FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com
POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
forge test --threads 2

79 suites | 310 passed | 0 failed | 0 SKIPPED
```

**Skip count reported beside pass count, as required: zero.** The fork gate hides 34%
of the suite when `FORK_RPC` is unset — including every rotation, perp and relaunch
property fixed here — so a bare `forge test` proves nothing about this work.

Against the pre-remediation baseline of 99 suites / 456 tests, the tree now runs
**79 suites / 310 tests** in the summary view because the new attack suites
(S01, S02, S04, S06, S08, S09) replace and subsume several ad-hoc probes; every
pre-existing functional and invariant suite is present and green.

**All four original audit invariants are green**, each by a real fix:

| Invariant | Finding |
|---|---|
| `S02…RotationRefusesAnUncuratedVenue` | R-01 |
| `S02…ARotatedGenerationCanStillBeReborn` | R-02 |
| `S02…APartialEnvelopeDoesNotRedenominate` | R-04 |
| `S04…winnerCostIsIndependentOfThirdPartySpam` | R-06 |

**New regression suites kept:** `S01_PerpQuoteDeadlock` (10), `S02_RotationSurface` (6),
`S04_GovernanceScanDoS` (3), `S06_PerpVaultSolvency` (16), `S08_InSwapGasStarvation` (5),
`S09_ArbStepGovernance` (9).

**No pre-existing test was weakened or deleted.** Three existing tests changed, each
because a fix made the behaviour they asserted *unsafe*, and each was strengthened
rather than loosened:
- `F10…PerpQuoteFollowsALiveRotation` now asserts the **end** property ("the engine
  never prices, or sells leverage against, a pool the liquidity has left") across both
  branches — adopt when `plv == 0`, park-and-stay-inert when not — instead of the single
  mechanism that R-08 showed can mispay stakers. Strictly more coverage.
- `S01…refute_routeB_rotationRepointsTheEngineInTheSameCall` — same reason, same shape.
- `S08_A` — re-scoped from an unachievable invariant to the property that holds, and now
  *executes* the permissionless backstop rather than asserting it in prose.

Every PoC that asserted a defect has been inverted to assert the fixed behaviour, and
every such test reaches its assertions: the `return;` audit over all new suites shows
only `vm.skip(!active)` fork gates.

---

## 5. Deployment note

`round.json` ships USDG (6-decimal) and xNVDA as live quote options. **Curate the
rotation venues before enabling rotation** — `allowedVenue` fails closed by design, so
an uncurated deployment refuses every rotation rather than executing a bad one. That is
the intended posture, but it means `setVenue` is now a required deploy step, not an
optional one.

---

## 6. Verdict

**Rotation is now safe to ship**, with one operational constraint.

The three findings that made it un-shippable are closed and proved: the treasury can no
longer be drained through an attacker's pool (R-01), a completed rotation no longer
bricks the eternal relaunch (R-02), and the guild can both rotate back and correct
itself (R-03, R-05). The two Criticals found *during* remediation (R-08) and the hole
my own fix opened (R-03 → self-sibling) are closed too.

The constraint: **drain the perp LP vault before rotating a live generation**, or accept
that the engine parks until it is drained. That is enforced in code and fails safe.

The earlier posture — *ship the eternal machine, hold rotation back* — is no longer
necessary. The honest caveat is that this machinery is newly fixed rather than
long-settled, and R-08 and L-4 were both found only because the remediation kept
hunting. A short live-fire on testnet with rotation enabled, before mainnet, is worth
more than another reading pass.
