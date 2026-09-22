# Perp system audit — 2026-09-22

Scope: `cauldron/PerpEngine.sol` (3,087 lines), `cauldron/PerpVault.sol` (878),
`cauldron/PerpSwapLib.sol` (733), `cauldron/PerpMarkSource.sol` (212), and the
liquidation-sweep surface of `CauldronHook.sol`. Solidity `^0.8.26`.

Method: OWASP Smart Contract Top 10 (2025) checklist, with emphasis on the
changes landed 2026-09-21/22 — `MAX_LIQ_PER_SWAP` 8→30, the multi-pass cascade
loop in `_doSweep`, the `unabsorbedEth` ledger, and the
`LiqTradeTooLarge`/`LiqGasStarved` split.

---

## Answer to "is the perp system correct and bug-free?"

**No, and the evidence is this audit itself.** It found **two Highs in code
written hours earlier** — one of them mine, both in a tree whose suite was green
at the time. A passing suite means "the properties someone thought to assert
still hold", not "the code is correct". Both are now closed, but the rate matters
more than the count: this subsystem has produced a defect per remediation for
seven consecutive rounds, including every round that believed it was finished.

What can be said honestly:
- The sweep's **stated** invariant ("a trade never fills while leaving a position
  it condemned open") now holds against every case I could construct.
- Bad debt is **recorded** rather than silently dropped (`unabsorbedEth`).
- Two independent attack classes were re-verified as held: nested-sweep
  reentrancy (`_liqReentry`), and `tx.origin` being attribution-only.
- **One Low remains open by choice** (F-3 below, after correction) and one
  lead is unproven.

---

## F-1 — Certify-on-silence in the cascade loop · HIGH · FIXED

`PerpEngine._doSweep`. Introduced by me in `b7a45e0`, found by this audit,
roughly two hours later.

The multi-pass cascade loop exited with `break` when a pass killed nothing, and
treated that as "the book is clean". It is not. `_tryLiquidate` is a **try**:

```solidity
if (!_throttle(insolvent, notional)) return;   // capped -> returns, no removal
_settle(id, p, 0, MODE_LIQUIDATION, liquidator);  // band may refuse -> no removal
```

Two paths return without removing the position — the per-block throttle, and
`55ba6fe`'s mark band, which deliberately leaves a position **intact** rather
than part-selling it at a bad price. So a pass could find a position the trade
condemns, fail to close it, kill nothing else, and exit reporting `SWEEP_OK`.

**Impact:** the hook certifies the trade and it fills, while a position the trade
condemned stays open and insolvent. That is precisely the N1/H1 defect the
pre-trade sweep exists to prevent, reached through a new door: not an *unscanned*
book, but a scanned one whose condemned positions could not be closed. Exhausting
`MAX_CASCADE_PASSES` while still killing had the same hole.

**Fix:** the only clean exit is a full pass that finds **nothing condemned**.
Every other exit — passes exhausted, or condemned positions that will not close —
is a refusal. A pre-existing backlog still does not freeze the pool, because
`_condemnedByThisTrade` is false for a position already underwater at spot.

**Why the tests missed it:** all of them exercise books where liquidation
*succeeds*. Nothing drove the throttle or the band to refuse mid-sweep during a
pre-trade sweep. **That coverage gap is itself the finding to carry forward.**

---

## F-2 — Fail-closed `_liqSweep` would trade bounded debt for an unpatchable brick · HIGH · REVERTED

`CauldronHook._liqSweep:834`. Found uncommitted in the working tree; flagged
independently by two other sessions, whose argument was correct.

```solidity
committed:  if (amountSpecified != 0 && swept && out.length >= 32) { ... }
variant:    if (amountSpecified != 0) {
                if (!swept || out.length < 32) revert LiqGasStarved();
```

The instinct — a failed bounded call is not a solvency certificate — is right in
isolation. But the two branches differ **only** when `swept == false` (the
bounded call could not run at all). A sweep that ran and *reported* trouble
already reverts two lines down. So the entire added surface is the liveness case.

**Impact if landed:** any condition making `sweepLiquidations` revert
unconditionally — an engine panic, a mid-rotation mismatch, a bad
`setPerpEngine` — reverts **every exact-input swap on the pool**. The hook has no
proxy and its address encodes the PoolKey, so the remedy is abandoning the pool
and its liquidity.

The asymmetry settles it: committed behaviour risks **bounded bad debt, now
recorded (`unabsorbedEth`) and absorbed by an accepted waterfall**; the variant
risks **unbounded, unpatchable loss of the market**.
`S08_InSwapGasStarvation.t.sol` asserts the removed property by name: *"DEGRADES,
NOT ALL-OR-NOTHING"*.

**Resolution:** reverted to committed behaviour, with the reasoning recorded at
the site — including that the only added surface is "could not run at all" — so
the next person with the same correct-in-isolation instinct argues with the
reason rather than rediscovering it.

**Provenance note:** I could not account for this edit in my own transcript.
It is the third provenance question in this tree (a subagent destroyed
uncommitted work; 131 lines no session could account for; this). All three are
consistent with *a shared worktree is not a safe substitute for per-session
isolation*. **Owner decision.**

---

## F-3 — Refusal is scoped to *underwater*, not *insolvent* · LOW · OPEN, deliberately conservative

**CORRECTED 2026-09-22. The original finding was wrong on its premise and is
retracted as written.**

I reported that `_throttle` needed gating on the `insolvent` flag, and that
without it a per-block DoS was available at ~100 ms blocks. **It is already
gated** — `PerpEngine.sol:1902`:

```solidity
if (!insolvent && cap > 0 && liqEthThisBlock + notional > cap) return false;
```

`git log -S 'if (!insolvent && cap > 0'` returns exactly one commit, `9d5cd46`,
and `git merge-base --is-ancestor 9d5cd46 6eaf67c` confirms it **pre-dates R46
entirely**. An insolvent position is never throttled, so the positions that
actually threaten PLV cannot be blocked, and the DoS I described cannot happen.
I recommended a fix that had been in the tree the whole time — the same failure
shape as S06 carried red across three reviews: reasoning about what the code
should do instead of checking what it does. Caught by a peer session asking
before re-fixing.

**What survives, in a different function than the original finding named.**
`_condemnedByThisTrade` (`:1443-1452`):

```solidity
(bool trip,,) = _liqTest(p);     // TRIP, not INSOLVENT
```

`_liqTest` returns `(trip, insolvent, notional)`; this discards `insolvent`.
`trip` is *underwater* (maintenance margin breached); `insolvent` is *backing
exhausted*. A merely-underwater position still has collateral and costs stakers
nothing — yet the cascade loop sets `condemnedRemains` for it and can refuse the
trade. So the refusal is broader than what threatens the vault.

**Left unchanged, deliberately.** Refusing on `trip` is the conservative
direction, it is what `H1B`/`H1C` pin, and loosening a solvency gate is exactly
the permissive change that has been wrong twice this week. The mitigating
property is real: `_condemnedByThisTrade` returns `!spotTrip`, so a position
already condemned at spot is treated as backlog and **pre-existing backlog can
never refuse a trade** — the refusal only ever fires on damage *this* trade would
cause.

Status is **open, deliberately conservative, with a named residual** — neither
"fixed" nor "a DoS".

## Verified as held

- **Nested-sweep reentrancy.** `_liqReentry` makes the inner pass return before
  `_pokeFunding`, before the book is read, and before any kill
  (`PerpEngine.sol:1152/1166/1233`); external entrypoints carry `notNested` and
  hard-revert. The asymmetry is deliberate — the sweep must never revert the
  swap it rides on.
- **`tx.origin` is attribution, never authorization.** Every use credits a
  reward or a badge; no branch gates on it. Documented as L-03, accepted.
- **Badges do not dilute the NFT floor.** `mintLiquidator` uses
  `LIQUIDATOR_ID_BASE + (++liquidatorMinted)`, a counter separate from
  `totalMinted` (`CauldronCollection.sol:210` vs `:411`), and `CauldronVault.
  outstanding()` reads `totalMinted`. So 30 badges per swap instead of 8 changes
  nothing about floor backing. They also carry no votes (`MiFrensGenesis
  ._getVotingUnits` returns `genesisBalanceOf`), so the higher rate does not
  touch quorum.
- **`unabsorbedEth` is not a brick risk.** Monotonic and never read for control
  flow; the NatSpec forbids gating on it, because `require(unabsorbedEth == 0)`
  would be permanent on the first wei of bad debt.
- **Vault `unchecked` blocks** are epoch counters (`ethQueueEpoch++`,
  `yieldEpoch++`, `tokQueueEpoch++`) — monotonic, unreachable overflow.

---

## Open leads, not findings

**L-1 — `SLACK_BPS = 1500` may be a guess against a chosen geometry.**
`_project` is exact for our own pool: `activeEthDepth()` derives from `L` and
`sqrtP` (virtual reserves), where constant-product **is** v4's single-range math,
and full-range seeding creates no interior initialized ticks. So the slack is not
paying for arithmetic error — it is paying for **blindness to other LPs' tick
placement**, since `_liq()` reads liquidity active at the *current* tick only.

A third party minting a **narrow** position straddling spot makes
`activeEthDepth` read high, so the projection says "this trade barely moves
price"; the real swap crosses out into thin full-range liquidity and moves
further, **under-condemning** positions that then become bad debt. DERIVED. The
PoC (`LIQ06`) does not yet compile. **If it reproduces it is a finding in its own
right and it re-prices R1A.**

**L-2 — cascade projection.** Modelling the cascade *before* trading (project,
find condemned set, re-project with their settlement notional) is a natural
consumer of a tick-indexed book and roughly free there, versus ~1M gas as a
second book walk today. Less urgent now that the cascade is *resolved* during the
sweep rather than merely detected.

---

## Coverage gaps worth closing

1. **No test drives the throttle or the mark band to refuse mid-sweep during a
   pre-trade sweep.** That is the exact gap F-1 lived in.
2. **`via_ir` stack errors name no file** until the whole tree is built without
   `--match-path`, so they present as "your last edit broke the tree". This cost
   two debugging cycles on a file that was not mine. Same diffuse-signature class
   as the badge-gas regression, whose casualties surfaced as
   `InvalidHeartbeat(0) != FeedUnusable(...)` and a bare `WrappedError`.
   **On this profile, a compile failure with no filename means build the whole
   tree before believing any attribution.**
3. **Suite numbers have been unreproducible for days** — a shared worktree with
   three-plus sessions editing, plus an uncommitted shared harness. Every number
   in this document describes a tree that includes other sessions' in-flight work.
