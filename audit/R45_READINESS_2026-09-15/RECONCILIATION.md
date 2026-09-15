# Reconciliation (P3) — this run against the three prior passes

Round-45 deploy-readiness review, 2026-09-15. Written by the orchestrator AFTER the blind hunt and the
verification phase closed, by opening the prior audit output for the first time in this run:
`audit/FINAL_BLIND_2026-09-13/`, `audit/FINAL_BLIND_2026-09-11/`, `audit/REMEDIATION_2026-09-11.md`.

Buckets per the brief: **new / still-open**, **fix-induced**, **re-confirmed safe**, **missed by us**.
The rule applied throughout: a rediscovery of something marked FIXED means the fix is broken, and is
treated as new. A rediscovery of something REFUTED with the SAME argument is dropped unless the
verifier addressed the refutation.

## Headline

Two of this run's three most important findings land directly on what the last remediation changed, and
a third is a finding the last run wrote down, deferred, and reasoned about incorrectly. That is the
pattern the brief predicted, and it held for the fourth time running: **freshly written, carefully
reviewed code is the best hunting ground on this repo.**

## Bucket 1 — FIX-INDUCED

### R1C (High) — the gas-floor bypass is a direct consequence of the L-2 remediation
On 2026-09-11, finding **L-2** correctly identified a real defect: one liquidation kill costs ~388,000
gas while the sweep gate opened at `LIQ_GAS_MIN = 250,000`, so the sweep was *always* fired and *always*
failed, silently burning 266,833 gas of the swapper's money per swap. The fix raised the floor to sit
above the work it gates: **250,000 → 400,000** (`REMEDIATION_2026-09-11.md` §L-2), plus an in-loop
`if (gasleft() < SWEEP_KILL_RESERVE) break;` so a short sweep banks what it can afford.

That fix is correct on its own terms. It also widened the band this run attacks: with
`LIQ_GAS_RESERVE = 180_000` and `LIQ_GAS_MIN = 400_000`, the pre-trade sweep now requires
`gasleft() > 980_000` against a ~104k bare swap. Raising the floor made the silent-skip window larger,
and nobody asked the inverse question — *what if the caller simply supplies less gas than the floor?*
The prior run came close: `FINAL_BLIND_2026-09-13/hunt/H1_core_pool.md:171` records the relationship
`LIQ_GAS_MIN 400k > LIQ_GAS_RESERVE 180k` as an observation, without turning it into an attack.

**Classification: fix-induced, new, CONFIRMED High.** Verified realized loss 0.30798 ETH per attack,
attacker cost negative, repeatable per block.

### R1A (Low) — the projected-price trigger is the shape the LIQ04-D fix chose
The same remediation changed `SLACK_BPS` 500 → 1500 and made the trigger *insolvency at the projected
price*, explicitly NOT maintenance-at-projected, because maintenance-at-projected broke the A02 and
flash-crash suites (one trade could farm a merely-unhealthy position). R1A is the residual cost of that
deliberate choice: a zero-buffer projected leg can close a position that is solvent at the realized
price. **Accepted with rationale, LOW, not fixed** — the alternatives were tried and reverted, and
shrinking `SLACK_BPS` is the less-conservative direction that feeds the R1B/R1C bad-debt class.

**Important:** the prior run REFUTED a similar-sounding claim (LIQ04-B: "slack is on the INPUT, 12–190
bps against a 1500 bps buffer; the short really was sunk; the attacker is a 9× loss-maker"). Verifier 1
ruled this run's PoC **NEW EVIDENCE**, not the same claim: it is a LONG rather than a sunk short, the
error is ~330 bps of PRICE rather than 12–190 bps of input, and `maintenanceBps` is demonstrably not
applied to the projected leg. The severity still falls to Low, but for a *different* reason than the old
refutation gave — the victim is already underwater on the mark leg, so the kill is early rather than
wrong. The old refutation's argument does not survive; its conclusion does.

## Bucket 2 — REDISCOVERY OF A "FIXED" ITEM: the fix is incomplete

### R2C (High) — Jb was fixed for the wrong half of the problem
Prior finding **Jb** (`FINAL_BLIND_2026-09-13`, Medium, VERIFIED) is the same guard at
`PerpVault.sol:274`. Its fix, commit `58e1a55`, stopped `claimPendingEth` reverting `ZeroAmount` and
rolling back the haircut it had just written, so the write-down now banks and returns 0.

That closed the *revert* path. It did not close the *latch*: `pendingEth` shrinks only inside
`claimPendingEth`, which is keyed on `msg.sender` (`PerpVault.sol:381,:405`). Nobody but the queued
holder can trigger the banking, and the holder has no obligation to. The prior run's own comment claims
the release "banks the haircut permissionlessly" — **that property is false as written**, and this run
demonstrates deposits staying shut to everyone else as a result. Verifier 2 corrected two of the
hunter's claims in the process (the holdout must lose ~10 ETH first, not 0.001 ETH; existing stakers can
still withdraw, so it is a deposit denial-of-service, not a fund lock).

**Classification: new — the fix is incomplete. CONFIRMED High.**

### R2B (High) — the token twin is the item the last run saw and deferred
`FINAL_BLIND_2026-09-13/LEDGER.md:108` records it verbatim, as an explicit deferral:

> "OBSERVATION, not changed: `claimPendingToken` (PerpVault.sol, token side) carries the byte-identical
> `if (paid == 0) revert ZeroAmount()` rollback. It cannot latch a deposit guard because `depositToken`
> has none, so it is the H-2 shape rather than Jb — but somebody should decide whether the token queue
> deserves the same treatment."

This run answers that question: **yes, and the reasoning for deferring was wrong.** The absence of a
guard on `depositToken` is not what makes the token side safe — it is the second half of the defect. With
no `QueueInsolvent` guard, the next token staker's entire principal is paid out to the stale queue
(measured: 100e18 of 100e18). So the token side has both the latch AND an unguarded deposit.

**Classification: known-and-deferred, now demonstrated. CONFIRMED High.**

### R3A (High) — K4b was downgraded on an argument this run's PoC defeats
Prior finding **K4b** was classified "missed-by-prior" and **downgraded to LOW** on the reasoning that
the grind is "largely self-defeating (any unprivileged `resolveTickets`, plus auto-resolve at
`:966-972`)". The related fix `545cd29` + `d552abc` closed the same shape in `MiFrensGenesis.sol:532-537`
only, and — as `RECONCILIATION.md:31` of that run says — was "never shape-swept into the hook's ticket
re-anchor".

This run's hunter and an independent verifier both put it at **HIGH**, with a PoC measuring 20 free
re-anchors on a single batch. The gacha path governs mint-or-nothing rather than cosmetic rarity, which
is why the same shape is worth more here than in the reveal path it was fixed in. The two sibling paths
(`CauldronCollection.sol:253`, `MiFrensGenesis.sol:559`) cap it at one and their comments name this exact
attack; the gacha path has no `reanchored` map at all.

**Classification: rediscovery of a downgraded item, re-raised with evidence. CONFIRMED High, being fixed.**
We disagree with the prior severity and say so explicitly rather than silently re-rating it.

## Bucket 3 — NEW / STILL-OPEN

| id | severity | why it is new |
|---|---|---|
| R1B | Medium | The persistent `sweepCursor` over a 12-slot window was never attacked with padding + dust sells. The prior run touched `MAX_LIQ_PER_SWAP` only to derive frontend gas. |
| R4A | Medium | `seedFunding` branch 1 pulling before testing the threshold. The 2026-09-11 sweep looked at branch 1's *return value* (`FINAL_AUDIT_FULLSWEEP.md:255,:299`) and at `_sqrtPrice` representability (Z-01, fixed `3cf1053`), never at the reserve the short branch consumes on its way out. |
| R5A | High | Frontend: the crystal spin is blind to the quote asset. Prior runs touched this component for rendering only (`FINAL_BLIND_2026-09-11/LEDGER.md:155,163`). |
| R5B | High | Frontend: `parseEther` on a 6-decimal quote, then a silent clamp to the whole balance. |
| R5C / R5E | Medium | Indexer liveness under a reorg. No prior phase covered this; it is why P5b exists. |
| C-1 | Critical (round) | The deployed router lacks `playChurn`. Structurally invisible to every prior phase, all of which assumed deployed bytecode equals source. |

## Bucket 4 — RE-CONFIRMED SAFE (attacked hard, held)

- **Supply conservation and exactly-once gacha resolution** — `R3C_SupplyConservation.t.sol` asserts
  committed == resolved, no stuck crystals, queue drained, cap never exceeded. R3A mints *within* the cap.
- **Relaunch liveness** — hunter 4 attacked it from every reachable state (mid-rotation, post-rotation,
  non-ETH quote, partially spent envelope, squatted next-generation pool, linked sibling, hostile
  recipient) and it held; the full gen1→gen2→gen3 lifecycle with perps passes on the Sepolia fork.
- **The sibling cap** — binds exactly where documented, atomically, one-way (`R4B_SiblingCap.t.sol`,
  four real assertions).
- **PoolKey squat, orientation inversion, cross-denomination teardown, stale-feed premature death,
  proposal-string OOG, treasury bench flooding** — eight refutations from hunter 4.
- **ABI parity** — 199 function and event entries across 25 ABI exports compared recursively including
  tuple component counts and event `indexed` flags: zero substantive mismatches. The class that once
  shipped `votes` as 1.149e48 is not present.
- **Projection inputs** — six refutations from hunter 1: price-limit clamping in all four quadrants,
  exact-output closed form, long-side padding starvation, `quoteIsCurrency0` orientation
  (`PoolOps.sol:912`), zero-depth failing safe, and sweep reentrancy guards.
- **Off-chain** — nine refutations from hunter 5: bundle secrets, Vite dynamic env, `x-forwarded-for`
  rate-limit bypass on all three routes, LLM prompt injection, OAuth redirect, address sourcing and
  case handling, indexer query surface, and a clean type-check.

## Bucket 5 — MISSED BY US (found by a prior pass, not independently rediscovered here)

Honest accounting. This run was deliberately narrowed to the delta and the deploy seam, so most of the
static surface was not re-swept; these are not failures of the hunt so much as consequences of the
narrowing, but they are listed because a report that hides them is marketing.

- The whole 2026-09-09 and 2026-09-11 finding sets (B-01 through B-13, Q-01, the relaunch/rotation brick
  family) were not re-derived. Prior PoCs for them live in `test/attacks/` and still pass.
- `Jc` (mark pointer not surviving a sync) was not independently rediscovered, though hunter 4's lead L5
  is in the same neighbourhood.
- `SIB1-D` (`linkVolume` O(n²), 487k gas at the 9th sibling, accepted) was not re-measured.
- The `S06` bad-debt-shedding failure is a known pre-existing open item, unchanged by this run.

## Coverage gap discovered during reconciliation

`test/attacks/CHURN1_LiveRevert.t.sol:27` contains `if (… FORK_RPC …) return;` in its top-level test, so
**it passes vacuously when the fork environment is absent** — the precise vacuity pattern this brief's
prime directive forbids, in an existing kept test. It is currently a genuine failure (the live r44 router
really does lack `playChurn`), but without the fork env it would report green while asserting nothing.
Logged as a test-quality finding.

## Evidence that the blinding actually worked

Not an assertion — a check. The quarantine removed 139 answer-key PoCs from the hunters' trees, and two of
them were the prior runs' own proofs of the very mechanisms this run re-found:

| quarantined PoC | prior verdict | rediscovered blind by | this run's verdict |
|---|---|---|---|
| `K4b_GachaReanchorGrind.t.sol` | LOW, "largely self-defeating" | hunter 3, which never saw it | HIGH, with 20 measured free re-rolls |
| `Jb_QueueInsolventDepositLock.t.sol` | Medium, fixed at `58e1a55` | hunter 2, which never saw it | HIGH, fix shown incomplete |

Hunter 3's tree contained only its own R3 files (verified: `ls` shows R3A–R3D and the shared base, no K4b).
So the re-raise of the gacha grind is an independent rediscovery at a higher severity, not a re-read of the
prior conclusion — which is exactly what a blind pass is for. The same holds for the vault queue.

The counter-consideration, recorded honestly: both hunters could still see that the surrounding code had
been patched (comments and identifiers such as `reanchored` survive comment-stripping), so they knew *where*
someone had been before, just not *what* they concluded. That is the residual documented in
`DECONTAMINATION.md` §5, and it plausibly drew attention to these files. It does not change the fact that
the severity judgement was re-derived from measurement rather than inherited.

## CORRECTION to Bucket 1, made after the final suite run — R1C was NOT new

The full-suite re-run failed two pre-existing tests in `test/attacks/S08_InSwapGasStarvation.t.sol`, and
their names gave the game away: `test_S08_B_PoC_SwapperChosenGasSilentlySkipsTheSweep`. The 2026-09-11
remediation had already found this exact mechanism, written a PoC for it, and — this is the part that
matters — **explicitly considered the remedy this run implemented and rejected it**
(`REMEDIATION_2026-09-11.md:349-357`):

> "**Priced residual, not a bug:** a swapper can still supply only enough gas to swap and not to sweep.
> Making the sweep mandatory would mean a 103k-gas swap *reverts* because someone else's position is
> underwater — a worse liveness property than the one it buys. The residual is bounded by two
> permissionless backstops … `PerpEngine.liquidate(id)` is callable by anyone at any time, and every open
> runs `_sweepAfterOpen`. Skipping is a **delay, not an escape**."

So R1C belongs in **Bucket 2 (found before, downgraded on an argument this run defeats)**, not Bucket 3.
My earlier "nobody asked the inverse question" was wrong: they asked it, answered it, and priced it as a
residual. The honest statement of this run's contribution is narrower and sharper:

**What was actually new.** Verifier 1 established by execution that the staker loss is REALIZED in the
attacking transaction, not deferred: the position sits at zero equity (`val < principal`,
`PerpEngine.sol:1568`) the instant the trade lands, and both backstops — a later sweep and a permissionless
`liquidate` — close it at the *same depressed price*. The backstops therefore bound WHEN the position
closes, not WHAT the stakers lose. That is precisely what defeats "a delay, not an escape", and it is the
whole reason pre-emptive liquidation exists: to close before the trade moves the price, not after.

**We overrode a deliberate prior decision, and that deserves to be stated plainly.** The prior objection
was a real one and is not fully dissolved: a swap CAN now revert because someone else's position is
underwater. What makes the trade-off acceptable is the `openCount() != 0` gate — with no open perp
positions there is no floor at all, so the liveness cost is confined to pools that actually carry the risk
the sweep protects against. Routability was verified by name (`LIQ04_ExactOutBypass`, `LifecycleE2E`'s
relaunch green candle), and every app path pins 8,000,000 gas against the ~1.05M floor.

**If the owner disagrees with that trade-off, this is the decision to revisit** — the mechanism is a
one-line gate in `_liqSweep`, and reverting to the prior "priced residual" stance means accepting ~0.31 ETH
of realized staker loss per attack, repeatable per block at negative attacker cost.

Consequence for the two S08 tests: they encode the pre-fix behaviour and now fail. They are being INVERTED
onto the post-fix behaviour, not deleted — the same treatment K4b received. An existing test that must
change to accommodate a fix is itself a finding, and this is it, recorded here.

### Owner decision, 2026-09-15: the trade-off is ACCEPTED

Asked directly whether to keep the gate or revert to the prior "priced residual" stance, the owner
confirmed: **protect the stakers, keep the fix.** The staker-first policy in the standing constraints is
the tie-breaker, and it outranks the earlier liveness objection. This is no longer an open decision, and
a future pass should not re-litigate it without new evidence about the liveness cost in practice.
