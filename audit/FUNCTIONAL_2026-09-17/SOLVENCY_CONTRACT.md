# Solvency contract — the invariants a perp/sweep change must not break

Written for the session scaling the position book (`MAX_LIQ_PER_SWAP` 8 → ~30,
kill-count → gas-bound refusal, tick-indexed book). Every line below is grounded
in code I read at `6cfb38c`, with the `file:line` to check it against. **Treat it
as claims to verify, not facts to quote** — that rule is why three findings in
this review were retracted.

This is not a review of your design, which I think is right. It is the set of
properties that were expensive to establish and are cheap to lose.

---

## 1. Bad debt: the owner's explicit requirement

> **No bad debt is shed onto stakers who stayed.**

Absorption is a two-tier waterfall, `PerpEngine._absorbPlvLoss` (`:2569-2575`):

```solidity
uint256 fromIns = loss < insuranceEth ? loss : insuranceEth;
insuranceEth -= fromIns;
uint256 rest = loss - fromIns;
if (rest > 0) plv = plv > rest ? plv - rest : 0;   // socialized LP loss
_bd(loss, fromIns);
```

**The saturation on `:2573` is where silent bad debt lives.** When `rest > plv`,
the excess is not absorbed anywhere — it is *dropped*. `plv` floors at 0 and the
shortfall never becomes a number anyone can read. `_bd(loss, fromIns)` is the
only record that the loss was larger than what was taken.

### What to hold invariant
- **I1 — Conservation.** Every wei of loss is either taken from `insuranceEth`,
  taken from `plv`, or **explicitly recorded as unabsorbed**. Never silently
  clamped. If your change can increase per-swap loss (30 kills instead of 8 is
  exactly that), the saturating branch gets reached more often, not less.
- **I2 — No reallocation by reaction speed.** A staker who queued an exit before
  a loss must not escape a loss a staying staker eats. `PerpVault._syncEthQueue`
  (`:455-470`) haircuts the queue when `backing < claims` and retires it entirely
  when nothing can pay. **Known open (R2A/T2A): the haircut only fires when the
  queue exceeds total backing — for any smaller loss, queued stakers eat 0% and
  stayers eat 100%.** Do not make that worse; a wider kill loop realises more
  losses per swap, which is precisely the regime where it bites.
- **I3 — Order independence.** Two liquidations in one sweep must produce the
  same end state in either order. The units×index queue exists because a per-user
  nominal write-down was neither idempotent nor order-independent — measured, 80
  calls moved **9.878 of 10 ETH** from a victim to the caller, for gas
  (`PerpVault.sol:112-120`). **A tick-indexed book changes sweep ORDER from
  cursor-rotation to price-proximity. That is an order change over a code path
  whose order-dependence was a Critical.** Assert it directly.

---

## 2. What the sweep must never do

- **N1 — Never certify an unscanned tail as safe.** The whole point of
  `98a97ec`. `complete = false` must be set on *any* early exit that leaves a
  condemned position unexamined. It is currently assigned in exactly two places:
  the gas break (`:1242`) and the cap branch (`:1280`). **If you delete the cap
  branch, make sure the gas break carries the whole burden** — there must be no
  third way out of that loop.
- **N2 — Refusal must be atomic.** A refused pre-trade sweep rolls back kills,
  book state, price, PLV, payer balance and keeper payout. The hook fires the
  sweep with a bounded-gas call and **discards the result**
  (`CauldronHook.sol:912`), so an OOG inside is not a partial sweep — the whole
  call reverts. Keep it that way; a partially-applied sweep is the worst
  available outcome.
- **N3 — A liquidation must never revert on the trophy.** Badge minting is
  deliberately best-effort with a `badgesOwed` fallback
  (`PerpEngine.sol:2581-2587`). Your wider kill loop **will** push more badges
  into deferral — that is expected and fine. What is not fine is a badge path
  that can revert the settlement.
- **N4 — Solvency judgement must not become cheaper than correctness.** The
  tick index replaces `_liqTest` per position with a bucket lookup. `_liqTest`
  reads live state; a bucket reads a cached tick. **Any position whose backing
  changed since bucketing has a stale tick.** See §4.

---

## 3. Guard tests — these encode Criticals, not preferences

Run all six before each commit. If one goes red, stop: each is the only thing
standing between a fixed Critical and its return.

| test | what it proves | the number |
|---|---|---|
| `E1B_LiqDrainScale` | a flashloaned spot push cannot drain PLV via a forced liquidation (**E1A**) | `drain wei: 0`, attacker net **−0.0591 / −0.1773 ETH** |
| `XL1_LiqTwapAndDepthCap` | large/insolvent positions stay closeable; nested sweep is a no-op | 6/6 |
| `D04_RebookErasesFundingAndPenalty` | funding, liquidation penalty and keeper cut survive a partial close | — |
| `H1B_SweepCapCertifiesUnscanned` | the crash swap reverts leaving **0 stranded** | 0 |
| `H1C_PreExistingBacklogWedge` | a spot-insolvent backlog drains **18 → 0** with **zero keeper calls** | 18 → 0 |
| `test_ownerPartialCloseMustRespectNonzeroMinimum` | a partial close honours the signed `minOut` | PASS |

**You may change `H1B`/`H1C` if you split `LiqGasStarved()`** — they assert on
that selector. Change what they *match*, never what they *prove*.

---

## 4. The tick index: the three things I would test first

Your offset-and-shift plan holds — funding applies through a **global** index per
side, so drift preserves relative order within a side. Two caveats plus the one
that worries me:

- **T1 — Two offsets, not one.** Longs and shorts drift in opposite directions.
- **T2 — Per-position mutations break the global-offset invariant.** Anything
  that changes one position's `collateral` or `principal` moves *that* position's
  liquidation tick independently. **`_rebook` is the live one**: since
  `712c2b1`/`dbf3cbd` it preserves `collateral` and adjusts `principal`, and a
  partial close changes `size`. Every such path must re-bucket. The invariant to
  test: *after any single-position mutation, that position's bucket equals a
  freshly computed tick.*
- **T3 — A stale bucket is a solvency failure, not a performance bug.** If a
  position's real liquidation tick is inside the crossed range but its bucket
  says otherwise, the sweep skips it and **certifies a tail it never scanned** —
  N1, through a new door. I would write that test before writing the index:
  mutate a position, do not re-bucket, and assert the sweep still catches it (it
  must fail), then make it pass.

---

## 5. Gas: two reserves that were never load-bearing together

At a count cap of 8 the engine could not approach either bound. At ~30 it will.

```
PerpEngine.SWEEP_KILL_RESERVE = 420_000     // sweep keeps this to finish
CauldronHook.LIQ_GAS_RESERVE  = 180_000     // hook keeps this for afterSwap
CauldronHook.LIQ_GAS_MIN      = 400_000     // hook won't fire below this
```

`CauldronHook:801-803` gates on `g > reserve + LIQ_GAS_MIN`; `:1009` forwards
`gasleft − LIQ_GAS_RESERVE`. **So the sweep's budget is set by the hook's
arithmetic, and `:1242` measures against a ceiling it does not control.**

Measured unit cost: **~440k marginal per in-swap kill** (543,602 with sweep vs
103,857 bare, `CauldronHook.sol:170-177`). 30 × 440k ≈ 13.2M + overhead, against
EIP-7825's 16,777,216 cap. **That is tight, not comfortable.**

- **G1** — assert a max-kill sweep cannot starve the `afterSwap` completion path.
  That failure is an OOG in the parent swap, not a clean refusal.
- **G2** — `test_maximumBookTradeMustFitSepoliaTransactionGasCap` asks for ~28M
  inside 16.7M: impossible at **any** cap, including none. Fixing it is right;
  make it assert the arithmetic rather than lowering the number until it passes.

---

## 6. Non-perp exploit vectors that a book change can reach

- **V1 — `tx.origin` keeper credit.** `_doSweep` credits the swapper
  (`PerpEngine.sol:1069` via `_sweepAfterOpen:1099`). Governance badges mint per
  kill. **More kills per swap = more badges per transaction.** Badge voting weight
  was suppressed at source, and the quorum denominator was checked to agree —
  **re-verify that still holds** once a single swap can mint ~30.
- **V2 — Dust positions as a griefing lever.** `minCollateral ≈ 0.003 ether`,
  `MAX_OPEN_POSITIONS = 64`. Raising the kill ceiling changes the economics of
  book-padding in both directions: cheaper to clear, but a larger scan to grief.
  Re-price it.
- **V3 — The mark band on `_settle`.** Every settlement that can spend staker
  money is banded (`55ba6fe`). A position too large to buy back inside the band
  is left **intact**, not part-sold. **If your index or wider loop assumes a
  liquidation always reduces or clears a position, that assumption is false.**
- **V4 — Reentrancy through the settlement swap.** `_settle` swaps in-place while
  `_doSweep` is on the stack; the PoolManager re-enters the hook and
  `sweepLiquidations` is re-entered at **measured depth 2**. It is a no-op via
  `_liqReentry` (`:1152`), and `notNested` (`:579`) hard-reverts external
  entrypoints. **A wider loop means more re-entries per swap.** `XL1`'s
  `NestedSweepIsANoOp` is the canary.

---

## 7. Method, because it cost this review four days

1. **Verify in `git worktree add` at the commit you mean to characterise.** Three
   findings here — a rotation Critical, a round-trip inversion, a `QUOTE_ORACLE`
   escape hatch — were confident conclusions drawn from a dirty shared tree. All
   retracted.
2. **Two independent readings agreeing is not execution.** The inversion had two
   sessions agreeing on the code and both wrong about reachability.
3. **A red PoC can mean the bug is dead.** `S06` asserts `pending > backing` —
   it fails because the vault is **solvent by 0.115 ETH**. It was carried as an
   open Critical across three reviews.
4. **Trace the value, not the symbol.** I called `QUOTE_ORACLE` an escape hatch
   because the name looked right; it never reached the rotator.
5. **The regression signature is diffuse.** A gas-budget break surfaced as
   `InvalidHeartbeat(0) != FeedUnusable(...)` and a bare `WrappedError`. **Run
   all five canaries**, not just the ones whose names match your change.
6. Keyed archive RPC only; never add an `audit_full_scope` skip.

---

# Addendum — "no bad debt" as shipped, and the one twin still open

Owner directive: *no bad debt allowed.* Two halves landed; one sibling remains.

## The property, stated honestly

**"Bad debt cannot exist" is not achievable.** Pre-swap liquidation bounds
*trade-induced* insolvency; it cannot eliminate insolvency, for four measured
reasons:

1. **Insolvency arises with no trade at all.** `H1C` drives 18 positions
   underwater with funding accrual plus a `maintenanceBps` change and **zero
   swaps**. No swap means no pre-swap hook.
2. **Closing is itself a price-moving swap.** `XL1` asserts a position larger
   than pool depth stays liquidatable — at that size the buy-back costs more
   than its backing by construction.
3. **The mark band deliberately refuses a bad close** (`55ba6fe`), leaving an
   oversized position **intact** rather than settling it at a price the
   liquidator made. Correct, and it means a shortfall can sit open.
4. **Liquidation is itself price-moving, so the solvent set is not fixed while
   you liquidate.** Kill #9 can condemn a position kill #1 left healthy.
   Measured by session `2c`: **2 positions insolvent at spot after a *successful*
   45-ETH buy** on a 24-position book.

**The achievable property, and the one now enforced: bad debt is never silently
created, and never silently reallocated.**

## Half 1 — never silently created (`PerpEngine`, session `2c`)

`_absorbPlvLoss`'s `plv = plv > rest ? plv - rest : 0` clamp dropped any loss
exceeding insurance + PLV. `_bd` only emitted an event; no state recorded it.
Now the remainder accumulates in a `public`, monotonic `unabsorbedEth` with
`BadDebtUnabsorbed` carrying the running total. **The waterfall is unchanged** —
insurance, then PLV.

**Trap, flagged and not live today** (grep: written and emitted, never read):
`unabsorbedEth` is monotonic and never decremented, so any future
`require(unabsorbedEth == 0)` is a **permanent brick on first bad debt**, even
after full recovery. It means *"this once happened"*, never *"this is
outstanding"*. Never gate on it.

## Half 2 — never silently reallocated (`PerpVault`, this session)

**R2A was live.** `_syncEthQueue:461` early-returned on `backing >= claims`, so a
loss *smaller than the queue* was not haircut at all. Measured: 5 ETH loss on a
20 ETH book → queued LP kept **10/10** (0% of the loss), stayer kept **5/10**
(100%).

Fixed in `6634f2a`: a new `ethBackingMark` slot records backing as of the last
vault action; `_syncEthQueue` scales `ethQueueIndex` by `backing/mark` on any
fall in `engine.totalEth()` the vault did not cause; `_markEth()` re-baselines
after every transfer. **One global index write — no per-user write-down**, which
is what made 80 calls move 9.878 of 10 ETH. Same loss now splits **7.5 / 7.5**.

Insurance-vs-PLV ordering untouched. ABI addition only (`ethBackingMark()`).

**Verified in a clean worktree at `6634f2a`: 60/60, 0 failed** — `test_R2A_*`
green, `E1B` `drain wei: 0` on both scales, `XL1`/`D04`/`H1B`/`H1C` green.
(The fixer's own runs were in the shared dirty tree and it said so; this re-run
is why that caveat is now discharged.)

## Still open — the token twin

`_syncTokQueue:762` carries the **identical** early-return the ETH fix replaced:

```solidity
if (claims != 0 && backing >= claims) return;
```

So the token-denominated exit queue has the same seniority hole: a token loss
smaller than the token queue falls entirely on stakers who stayed. The exposure
differs — token principal is structurally more protected than ETH — but the
defect is the same shape and the fix is the same shape (`tokBackingMark`
mirroring `ethBackingMark`).

**Not fixed, deliberately: it is an owner call**, because it is a second
economic surface rather than a repeat of an approved one. If the answer is
"treat both sides identically", it is a mechanical port of `6634f2a`.

## Also noted, not defects
- `assetsEth()` reads stale between vault calls; every money path syncs first,
  so pricing is never stale at the point it is used.

---

# Addendum 2 — F-3, and what "the refusal is over-scoped" actually means

Two findings were raised against the liquidation throttle during R46. **One was
never real; the other is real but lives in a different function and is
deliberately left open.** Both are recorded because the failure modes are
instructive in opposite directions.

## F-3 as originally written: NOT A DEFECT — the fix already existed

The finding recommended gating the per-block throttle on the `insolvent` flag so
a merely-underwater position could not be used as a per-block DoS lever at
~100 ms blocks. `PerpEngine._throttle` (`:1899-1905`) already does exactly that:

```solidity
if (!insolvent && cap > 0 && liqEthThisBlock + notional > cap) return false;
```

**An insolvent position is never throttled**, so the positions that actually
threaten PLV cannot be capped out of a block. Provenance, checked rather than
assumed: `git log -S 'if (!insolvent && cap > 0'` returns a single commit,
`9d5cd46` ("a whale's single swap could leave a short unliquidatable with
unbounded bad debt"), which **pre-dates R46 entirely**.

So this is the S06 shape again — **a finding written recommending a fix that was
already in the tree.** Third instance this review (S06 carried red across three
reviews for asserting an attack succeeds; the rotation Critical read off a dirty
worktree; this). The common cause is asserting a mechanism's behaviour without
executing or grepping it first.

## The real residual: `_condemnedByThisTrade` refuses on `trip`, not `insolvent`

`PerpEngine.sol:1443-1452`:

```solidity
function _condemnedByThisTrade(Position memory p) private returns (bool) {
    (bool trip,,) = _liqTest(p);     // <-- TRIP, and `insolvent` is discarded
    if (!trip) return false;
    ...
    return !spotTrip;                // already condemned => backlog, not us
}
```

`_liqTest` returns `(trip, insolvent, notional)` (`:1816-1819`). The two are
different states:
- **`trip`** = `_underwaterVal` — the maintenance margin is breached. The
  position still has collateral. **Closing it costs stakers nothing.**
- **`insolvent`** = `_insolventVal` — backing is exhausted. **This is the state
  that reaches `_absorbPlvLoss` and charges PLV.**

Because the refusal keys on `trip`, a trade is turned away for an
**underwater-but-solvent** position the sweep could not close — one that
threatens no staker capital. The refusal is therefore **over-scoped relative to
what it exists to protect**.

### Why it is left open rather than fixed

Loosening a solvency gate from `trip` to `insolvent` is a **permissive change**,
and permissive changes to this exact surface have been wrong twice in this
review. Refusing on `trip` is the conservative direction and it is what `H1B` and
`H1C` pin.

What makes it tolerable rather than merely cautious: `!spotTrip` means a position
**already** condemned at spot is treated as pre-existing backlog, not blamed on
the trade. So the refusal only ever fires on damage *this* trade would cause —
never on a backlog the trader did not create.

**Status: open, deliberately conservative, with a named residual.** Not "fixed",
not "a DoS". Changing it needs a measurement of how often a merely-underwater
position actually blocks a trade at realistic sizes, which nobody has taken.

## Coverage gap, named rather than papered over

The fill-clean-after-a-large-cascade branch has **never been exercised above dust
size**. Per P30, the OI cap binds first: **16 positions at 0.05 ETH collateral on
a 10 ETH engine** (`maxOiBps = 3000` refuses the 17th), 40 at 0.02 ETH, and only
at 0.005 ETH does the book reach `MAX_OPEN_POSITIONS = 64`.

So the branch may be **genuinely unreachable at realistic position sizes**. No
test was manufactured for it: a test contorted into reaching a branch is worth
less than an honest note that the branch was never reached. If it is ever built,
the right shape is a book sized just under the refusal boundary.

**Consequence for the count caps, which is the decision-relevant part:**
`MAX_LIQ_PER_SWAP` and `MAX_OPEN_POSITIONS = 64` are **dust-only ceilings**. With
meaningful positions the binding constraint is economic (`maxOiBps`), not
numeric — so raising either buys nothing until `maxOiBps` moves, and `maxOiBps`
is the parameter that keeps a cascade small relative to the pool that must
absorb it.
