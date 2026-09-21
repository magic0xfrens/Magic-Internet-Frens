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
