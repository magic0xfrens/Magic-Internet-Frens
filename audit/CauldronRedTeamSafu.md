# The Cauldron — Red-Team / SAFU Review

**Date:** 2026-09-10 → 2026-09-11
**Branch:** `fix/b05-b07-relaunch-totality`
**Scope:** working tree (not HEAD), `contracts/solidity/**` outside `lib/`
**Method:** adversarial threat modelling with executable proof. Every finding below
is either a Foundry test that fails on current code, or a measured run whose output
is pasted verbatim.

> **Tree-stability caveat, stated up front.** A second Claude session
> (`magic-internet-frens-77`) was editing this same working tree throughout this
> pass — `cauldron/CauldronGachaRouter.sol`, `cauldron/CauldronBase.sol`,
> `cauldron/RedemptionExt.sol` and `test/attacks/Q02_GachaOddsUnitMismatch.t.sol`
> changed underneath the audit, under a parallel "functional audit R-04/R-05"
> workstream. Every result here was measured against the tree as it stood at the
> moment of the run. Re-run before acting.

---

## 1. Verdict

**Do not deploy.** Not because the core machine is unsound — the launch, fee,
dividend, floor and relaunch paths took sustained fire and held — but because the
newest subsystem, **live quote rotation**, is not safe to expose in its current
form. Three things stand between this and yes:

1. **The rotation venue is attacker-chosen and the slippage bound is
   attacker-supplied.** A permissionless `rotateSlice` swapped a slice at
   **0.225% of fair value** in a measured run; the attacker turned 0.01 ETH into
   5.01 ETH. This is a live drain, not a theoretical one.
2. **A completed rotation permanently bricks `relaunch()`.** Verified:
   `TRANSFER_FROM_FAILED`. The protocol's central promise — relaunches forever,
   permissionlessly — is destroyed by using its own headline feature, with no
   attacker involved.
3. **Rotation is one-way and self-correction is impossible.** `address(0)` means
   both "native ether" and "no envelope approved", so a treasury that rotates into
   an ERC20 can never rotate back; and a spent envelope locks out new proposals
   until it expires (30 days). The guild cannot vote its way out of 1 or 2.

**Track A (value extraction):** one Critical, live and cheap.
**Track B (liveness/griefing):** one Critical, one High, two Mediums.
**Rotation surface specifically:** not deployable. Every finding above lives here.

Everything outside rotation that was attacked — perp solvency interlocks, the
relaunch gas brick, the B-05 non-native relaunch clamp, the delegatecall facet
layout — **held**, and several held against deliberate, targeted attempts to break
them (§5).

---

## 2. Measured baselines

Prior audit prompts quote stale numbers. These were measured this pass.

| Metric | Measured |
|---|---|
| Suite **with** fork env | 99 suites, **456 tests, 0 failed, 0 skipped** |
| Suite **without** fork env | 118 passed, **62 skipped (34%)** |
| External/public declarations | 463 (non-test, non-deploy, non-lib) |
| Genuinely permissionless state-changing entrypoints | **71** |
| `CauldronRegistry` | 24,521 B runtime — **55 B** margin |
| `CauldronHook` | 24,508 B runtime — **68 B** margin |
| `RedemptionExt` | 13,399 B — 11,177 margin |
| `QuoteRotator` | 7,692 B — 16,884 margin |

**The fork gate hides exactly the high-risk surface.** Without `FORK_RPC`, these
skip entirely: `F10_QuoteRotationTotality`, `F11_FloorsAndRedemption`,
`Z02_PerpStaleMark`, `Z06_GovernanceLockout`, `Y03_RelaunchGasBrick`,
`PoC_PerpGriefStuckEngine`, `PoC_PoisonProposalBricksRelaunch`,
`B16_FeatureReachability`, `F02_L2Semantics`. A bare `forge test` prints green
while testing none of the rotation, perp or relaunch properties. **Always report
the skip count beside the pass count.**

**Final state after this pass.** The full suite was re-run with the fork env at the
end of the review. The **only** failing tests in the entire repository are the four
invariants added by this audit, each documenting a confirmed defect:

| Failing invariant | Finding |
|---|---|
| `S02…test_INVARIANT_S02_01_RotationRefusesAnUncuratedVenue` | R-01 |
| `S02…test_INVARIANT_S02_02_ARotatedGenerationCanStillBeReborn` | R-02 |
| `S02…test_INVARIANT_S02_03_APartialEnvelopeDoesNotRedenominate` | R-04 |
| `S04…test_invariant_winnerCostIsIndependentOfThirdPartySpam` | R-06 |

**No pre-existing test was weakened, modified or broken.** Four new PoCs pass
(`S02_01_PoC_UncuratedVenueDrainsTheSlice`,
`S02_04_APoolIsNeverItsOwnVolumeSibling`,
`S02_03_PoC_FlipStrandsThePrimaryAndKillsRotateSlice`,
plus the two `S04` measurement PoCs).

Environment required for a meaningful run:

```
export FOUNDRY_PROFILE=cauldron
export FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
forge test --threads 2      # public RPC 429s are infrastructure, not regressions
```

---

## 3. Findings

### R-01 · CRITICAL · Track A — permissionless rotation drains the treasury through an attacker-built venue

**Location:** `cauldron/QuoteRotator.sol` `_routeMatches`; `cauldron/RedemptionExt.sol`
`rotateSlice` / `rotateSliceFrom`.
**PoC:** `test/attacks/S02_RotationSurface.t.sol::test_S02_01_PoC_UncuratedVenueDrainsTheSlice`
(PASSES — drain succeeds) and `::test_INVARIANT_S02_01_RotationRefusesAnUncuratedVenue`
(FAILS — "next call did not revert as expected").
**Confidence: VERIFIED.**

Measured:

```
fill via CURATED venue  (usdg, 6dp): 44,325,886,405   ->  44,325.89 USDG
fill via ATTACKER venue (usdg, 6dp):        99,800,275   ->       99.80 USDG
attacker deposited wei: 10,000,000,000,000,000   (0.01 ETH)
attacker withdrew  wei:  5,009,999,999,998,440   (5.01 ETH)
```

**99.775% of the slice destroyed; attacker net +5.0 ETH.**

Mechanism. Once a governance envelope is live, `rotateSlice` is permissionless and
the **caller supplies both the venue and the slippage floor**. The only venue check is:

```solidity
// QuoteRotator._routeMatches
return (c0 == from && c1 == to) || (c0 == to && c1 == from);
```

A v4 `PoolKey` is `(currency0, currency1, fee, tickSpacing, hooks)`. This validates
two of five fields — the currency *pair* — and ignores `fee`, `tickSpacing` and
`hooks`. Any attacker-deployed ETH/USDG pool at any price therefore qualifies.
With `minOut = 0` the rotation dumps treasury liquidity into it. Repeatable until
the envelope is exhausted.

`RedemptionExt` argues the caller "chooses only the timing — and `minOut` bounds
what timing can cost." **That reasoning is circular**: `minOut` is supplied by the
same untrusted caller, so it bounds nothing. *A guard parameterised by the attacker
is not a guard.*

This is prior finding **B-12 ("rotator venue unvalidated")** — the earlier fix
validated the pair but not the pool identity.

**Cost to attacker:** one pool deployment + minimal seed liquidity (0.01 ETH + 100
USDG in the PoC). **Value out:** bounded only by envelope size and `MAX_SLICE_BPS`.

---

### R-02 · CRITICAL · Track B — a completed quote rotation permanently bricks `relaunch()`

**Location:** `CauldronRegistry.sol:1558`, `:922`; `cauldron/RedemptionExt.sol:413`,
`:632`; `cauldron/PoolOps.sol` `seedFunding` branch 3.
**PoC:** `test/attacks/S02_RotationSurface.t.sol::test_INVARIANT_S02_02_ARotatedGenerationCanStillBeReborn`
(FAILS).
**Confidence: VERIFIED.**

Measured:

```
generationQuote(1)     : 0xa0Cb...7598   (USDG - rotation completed)
generationPoolKey.cur0 : 0x0000...0000   (primary pool is STILL the ETH pool)
registry USDG actually held (6dp): 0
relaunch REVERTED: 0x08c379a0...5452414e534645525f46524f4d5f4641494c4544
                                  -> "TRANSFER_FROM_FAILED"
```

**No attacker, no privileged key.** The guild votes a rotation through the real
`TreasuryGovernor`, anyone drives `rotateSlice` to completion, the generation dies
naturally, and `relaunch()` reverts. Every retry reverts identically.

Mechanism:

1. Rotation flips `generationQuote[gen] = toQuote` (`RedemptionExt.sol:413`) but
   **never updates the recorded primary `generationPoolKey`** — proved by the log.
2. `_removeLiquidity` recovers native wei from that still-ETH primary pool, then:
   ```solidity
   // CauldronRegistry.sol:1558
   ethRecovered += e4;   // e4 = recoverLegs' quoteOut, in USDG 6-decimal raw units
   ```
   Post-rotation the legs *match* `generationQuote`, so `recoverLegs` takes the
   `quoteOut += q` branch (`RedemptionExt.sol:632`) — **18-decimal wei and
   6-decimal USDG summed into one integer.**
3. The mixed magnitude is passed with `oldQuote = USDG` (`:922`). `seedFunding`
   skips branch 1 (B-05 clamps `specQuote` native) and branch 2
   (`oldQuote != 0 && recovered > 0`), landing on **branch 3**, which returns
   `(USDG, mixed)` — an ETH-magnitude number requested as raw USDG.
4. The registry cannot pay it → `TRANSFER_FROM_FAILED`.

This is **B-05 WALL-1 resurrected through a door the B-05 fix never covered.** That
fix clamped the *proposal's* quote to native; it never clamped
`generationQuote[oldGen]` becoming non-native via *rotation*.

The concurrent R-04 `legProceeds` work addresses the *non-matching* leg case. The
brick is in the **matching** case and survives it — this was measured on a tree
that already contains that change.

**Recovery:** `emergencySweep` / `migrateToSuccessor` only — both `onlyEmergency`
**and** timelocked. There is no permissionless path back.

---

### R-03 · HIGH · Track B — rotation is one-way; the guild cannot correct itself

**Location:** `cauldron/TreasuryGovernor.sol` `allowance()`;
`cauldron/RedemptionExt.sol` `rotateSliceFrom`.
**PoC:** `test/attacks/S02_RotationSurface.t.sol::test_INVARIANT_S02_04_APoolIsNeverItsOwnVolumeSibling`
(PASSES, asserting the defect via `vm.expectRevert(NoRotationApproved())`).
**Confidence: VERIFIED.**

`allowance()` returns `e.quote`, and a rotation back to ether has
`e.quote == address(0)`. But the consumer reads that same value as "nothing
approved":

```solidity
(address toQuote, uint16 remaining) = ITreasuryGovernor(gov).allowance();
if (toQuote == address(0)) revert NoRotationApproved();
```

**The sentinel for "no envelope" is identical to the protocol's own default quote.**

The guild can pass *and execute* a vote to return to ether — `setAllowedQuote`
keeps native permanently allowed (`NativeQuoteRequired`), `_requirePriceable`
short-circuits on `address(0)` — so the envelope installs cleanly, and then every
slice reverts. Once a treasury rotates into an ERC20 quote **it can never come
back**, which is what makes R-02 uncorrectable by governance.

---

### R-04 · HIGH · Track B — a *partial* envelope re-denominates the entire generation

**Location:** `cauldron/RedemptionExt.sol:410-413`; `cauldron/TreasuryGovernor.sol:511-516`.
**PoC:** `test/attacks/S02_RotationSurface.t.sol::test_INVARIANT_S02_03_APartialEnvelopeDoesNotRedenominate`
(FAILS).
**Confidence: VERIFIED.**

A 2500-bps mandate, fully executed, flips the generation to USDG while **75%+ of
the LP verifiably stays in ETH** — the test's `assertGe(left * 4, before * 3)`
passes; the redenomination assertion fails.

```solidity
(address stillRotating,) = ITreasuryGovernor(gov).allowance();
if (stillRotating == address(0)) { generationQuote[gen] = toQuote; ... }
```

`allowance()` returns `address(0)` when `movedBps >= maxTotalBps` — envelope
**exhausted** — which the code treats as *rotation complete*. But `maxTotalBps` is
how much the guild **voted to move**, not 100% of the LP.

The comment at `:407-410` asserts the opposite — *"30% moved does not redenominate
a generation"* — which holds only when an envelope stops **early**, not when a
**small** envelope is fully spent. Completion is being measured against budget
consumption rather than against liquidity actually moved.

**Consequences:** (a) re-points the perp engine onto the thin minority pool —
precisely the *"cheap one to push while the deep sibling sets the price"* hazard
`CauldronHook.sol:1500-1508` describes, now reachable through ordinary governance
instead of being interlocked; (b) arms R-02 with only a 25% mandate.

---

### R-05 · MEDIUM · Track B — a spent envelope locks out treasury governance until expiry

**Location:** `cauldron/TreasuryGovernor.sol:322`, `:397`, `:409`.
**Confidence: VERIFIED** (observed as `ProposalActive()` blocking leg 2 of the S02-04
round trip; confirmed by reading every write to `envelope.active`).

`envelope.active` is set `true` at `:397` and set `false` in exactly one place —
`cancel`, at `:409`, which is **guardian-only**. Nothing clears it when the envelope
is exhausted. Meanwhile:

```solidity
// propose, :322
if (envelope.active && block.timestamp < envelope.expiry) revert ProposalActive();
```

So once an envelope is installed, **no new treasury proposal can be filed until it
expires** — `MAINNET_LIFETIME = 30 days` — even if it was fully spent in the first
hour. After R-01 drains a slice or R-04 mis-denominates a generation, the guild
cannot even *file* a corrective proposal for up to 30 days. Guardian `cancel` is the
only escape, and it is privileged.

---

### R-06 · MEDIUM (L1) / HIGH (L2) · Track B — treasury governance wedged by proposal spam

**Location:** `cauldron/TreasuryGovernor.sol:356-359`, `:379`, `:448-493`.
**PoC:** `test/attacks/S04_GovernanceScanDoS.t.sol` — invariant
`test_invariant_winnerCostIsIndependentOfThirdPartySpam` FAILS; two positive PoCs PASS.
**Confidence: VERIFIED.**

Measured:

| | |
|---|---|
| `winner()` — honest world | **6,399 gas** |
| `winner()` — +400 junk proposals | **363,611 gas** (57×) |
| Marginal cost per junk proposal | **888 gas** |
| `propose()` cost to attacker | **78,977 gas** |
| Proposals to exceed a 30M block | **33,783** |
| **Total attacker gas to wedge** | **~2.67 billion** |

`execute` gates on `id != winner()` (`:379`), so `winner()` sits on the only path
that installs an envelope. The enabling defect is that the leader cache is a
**permanent high-water mark** — `_leadVotes` is written in exactly one place
(`:356-359`, under `p.forVotes > _leadVotes`) and **never reset**, by `execute`,
`cancel` or anything else. Once any proposal draws V votes, every later proposal
passing quorum with fewer than V can never become the hint, `_leadId` keeps pointing
at something executed/cancelled/stale, and **every** `winner()` call falls through
to the full scan.

The scan is bounded by **time**, not position (`:483-492`) — a deliberate and
correct fix for this repo's own B-10. But bounding *age* does not bound *how many*
were filed inside that window, and `propose` gates on nothing but
`PROPOSAL_THRESHOLD = 5` MiFrens. The contract already says so at `:430-432`:
*"COOLDOWN and the `envelope.active` check gate ENVELOPES, not proposals, so one
holder can file indefinitely."*

Correctness is **not** broken — `winner()` still elects the right proposal
(asserted). This is purely cost/liveness: the mandate expires unexecuted inside its
3-day window because nobody can afford to read it. At mainnet 10 gwei the wedge
costs ~27 ETH and must be re-bought as spam ages out; `foundry.toml` configures
`base` and `bnb`, where the same attack costs well under 0.1 ETH and is sustainable
indefinitely.

---

### R-07 · HIGH (operator footgun, not attacker-reachable) — the documented workaround permanently strands the perp engine

**Location:** `CauldronHook.sol:1514-1515` (the advice), `:1517-1518` (the skipped
interlock), `:1929` (the gate), `:1539-1540` (`isDead` on an untracked pool);
`cauldron/PerpEngine.sol:450`, `:987`, `:1027`, `:1216`.
**Confidence: DERIVED** (mechanism verified line-by-line; see §6 for why the
subagent's PoC does not substantiate it).

`PerpEngine._key()` builds its PoolKey from PerpEngine's **own cached `quote` slot**
(`:450`) but reads `registry.currentToken()` **live** (`:451`). The token side
follows a relaunch automatically; the quote side moves only in `syncGeneration`
(`:1027`), which refuses while `openCount != 0` (`:987`).

If the two ever diverge, the trap closes permanently: `_key()` hashes to a pool that
was never initialised → `CauldronHook.isDead` returns **false** for any untracked
pool (`:1539-1540`) → `forceCloseDead` / `forceCloseAllDead` both revert `NotDead()`
→ `openCount` never drops → `syncGeneration` reverts forever. `_swapBody` builds its
swap from the same stale `_key()`, so even the trader's own `close()` (`:816`, which
does *not* gate on `_isDead`) cannot settle. `linkVolume` stays blocked too (`:1518`).

**Reachability is operator-only.** `setPerpEngine` requires `registry || owner()`
(`:1929`). But the hook's own comment recommends the fatal step:

> *"Close the positions (or unset the engine) before diversifying the quote."*

Taking the second half removes **both** guards at once — `linkVolume` skips its
`PerpsOpen` check when `perpEngine == address(0)` (`:1517`), and `rotateSlice` skips
its in-call re-point for the same reason. The rotation then completes over a full
book, and re-wiring the engine restores a machine whose `quote` no reachable call
can move. **The guidance in the code leads the operator into the trap.**

---

## 4. Leads (believed real, not demonstrated)

- **L-1 — `rotateSlice` dies for the rest of a generation after redenomination.**
  With `generationQuote` flipped (R-04) but `generationPositionId` still the ETH
  pool, `fromLeg == 0` should measure the ETH pool's payout as a *USDG* balance
  delta of zero. A PoC was blocked by R-05's proposal lockout. **HYPOTHESIS.**
- **L-2 — in-swap gas-reserve starvation.** The hot path fires liquidation, gacha,
  legacy-buy and seeder pokes under hard gas reserves in `CauldronHook`. Not
  attacked this pass (agent lost to rate limits). Constants unverified — measure
  before trusting any number.
- **L-3 — `PerpVault` share-price manipulation.** Eight permissionless entrypoints
  (`deposit`/`depositEth`/`withdrawEth`/`claimPendingEth`/`depositToken`/
  `withdrawToken`/`claimTokYield`/`claimPendingToken`). First-depositor/donation
  inflation and queued-exit seniority were **not** examined.
- **L-4 — `QuoteRotator.arbStep`** is permissionless with an owner-tunable
  `maxArbNotionalUsd` (default $25k/call) and `arbKeeperBps = 1000`. Repeated calls
  as an ungoverned treasury re-allocation were not tested.

---

## 5. Proven safe (attacked, held)

- **Relaunch does not change the quote under a surviving perp book.** `seedFunding`'s
  "never strand `recovered`" rule holds: branch 1 needs `recovered == 0 || oldQuote
  == wantQuote`, branch 2 needs `recovered == 0 || oldQuote == address(0)`, branch 3
  returns `oldQuote`. Attacked directly as R-07 Route A. **REFUTED.**
- **A live rotation cannot diverge the perp engine.** The uncommitted `RedemptionExt`
  change genuinely works: `linkVolume` earlier in the same call proves
  `openCount == 0`, and the engine is re-pointed in the same transaction. Attacked
  as R-07 Route B, including the `notNested` nesting angle. **REFUTED.**
- **A pool can never become its own volume sibling.** `CauldronHook.linkVolume` does
  lack a `primary != secondary` check, but `generationPoolId[gen]` is always the ETH
  primary, so self-linking would require a rotation back to native — which R-03
  makes impossible. A `USDG→xNVDA→USDG` trip links leg pools, never the primary.
  **REFUTED — do not re-raise.**
- **The delegatecall facet cannot corrupt registry state.** `CauldronRegistry` and
  `RedemptionExt` storage layouts are byte-identical through slot 53 (both inherit
  `CauldronBase`), verified with `forge inspect … storageLayout`. Live round-38
  registry storage confirms the real layout (slot 49 `quoteRotator`, slot 50
  `treasuryGovernor`), and both are correctly wired on-chain.
  *Note: source comments are off by one — `CauldronBase.sol:332` calls
  `generationQuote` "slot 49" when it is slot 48.*
- **Relaunch survives a maximally-spammed perp book under a constrained gas budget**
  (`Y03`, re-run green with the fork).
- **The registry forwarder surface is genuinely gated.** Registry forwarders look
  ungated but inherit the facet's gate through `_forwardToExt()`;
  `setRotationWiring` is `onlyOwner` on the facet.

---

## 6. Confidence, and what this review did *not* establish

Four hunting subagents were lost to rate limits before validating their own output.
Their artefacts were re-run and adjudicated rather than trusted:

- **`S01_PerpQuoteDeadlock.t.sol` reported 9/9 PASS. The Route C assertions never
  executed.** Each sat behind
  `if (!runner.tryRelaunch(...)) { console2.log(...); return; }`, and the logged
  reality was `REBIRTH REVERTED — the machine cannot advance at all`. In Foundry a
  test passes if it does not revert, so an early return yields a green test with zero
  assertions. R-07 is therefore tagged DERIVED, not VERIFIED — the mechanism is
  verified line-by-line, but the PoC does not yet prove it end to end.
- `S02`'s S02-04 asserted a precondition that R-04 disproves (its author trusted the
  `:407-410` comment). Corrected to measured reality, after which it settled both
  R-03 and the self-sibling refutation.
- Two `S02` results were adjudicated as test-rig artefacts, not findings, and fixed:
  `ProposalActive()` (→ became R-05) and a 30-day envelope lifetime.

**Blind spots — not reached this pass:** the in-swap hot path and gas reserves
(L-2), `PerpVault` solvency (L-3), `arbStep` (L-4), the NFT/gacha/dividend cluster,
the oracle's decimal conversions under a live rotation, and the entire off-chain
surface (serverless routes, indexer trust, frontend signing). The function graph was
rebuilt only for `perp` and `rotation`; `hook`, `registry`, `nft` and `governance`
extraction died with their agents and the stale 2026-09-09 copies are archived at
`audit/graph/stale-2026-09-09/`.

---

## 7. Priced residual — the honest version of "100% safu"

No audit proves a contract safe. What this pass establishes:

**If rotation ships as-is:** the treasury is drainable by any address the moment a
rotation envelope is live (R-01), and the protocol stops relaunching forever the
first time a rotation completes (R-02), with no governance path back (R-03, R-05).
That is not a priced residual; it is a blocker.

**If rotation is disabled at launch** — no `setRotationWiring`, or no envelope ever
approved — then R-01 through R-05 are all unreachable, because every one of them
requires a live envelope. The remaining exposure is:

- **R-06** (governance spam) — treasury-rotation liveness only; the core relaunch
  loop runs on `CauldronGovernor`, which carries its own scan and runner-up
  mechanism and is untouched by this finding.
- **R-07** — an operator footgun, avoidable by never unsetting the perp engine, and
  worth fixing in the comment as much as in the code.
- The four leads in §4, none of which were attacked.

That is a defensible launch posture: **ship the eternal machine, hold the rotation
feature back** until R-01…R-05 are fixed and re-tested. It is also the honest
framing — the machine's core promise survived everything thrown at it this pass; the
feature bolted onto it did not.

---

## 8. Recommended fix order

1. **R-01** — curate the venue (allowlist full `PoolKey` hashes, or pin
   `fee`/`tickSpacing`/`hooks`), and derive `minOut` from the oracle inside the
   contract instead of accepting it from the caller. *Never let the attacker supply
   the guard.*
2. **R-02** — stop mixing denominations at `CauldronRegistry.sol:1558`; make
   `seedFunding` branch 3 payable, or clamp a rotated generation back to native at
   relaunch exactly as B-05 clamps proposals.
3. **R-03** — stop using `address(0)` as the "no envelope" sentinel; use the
   existing `active` flag or a distinct sentinel. Grep for other `== address(0)`
   sentinels on quote-typed values.
4. **R-04** — judge completion by liquidity actually moved (or the absence of a
   remaining old-quote position), not by envelope exhaustion.
5. **R-05** — clear `envelope.active` when `movedBps >= maxTotalBps`.
6. **R-06** — reset `_leadVotes`/`_leadId` when the cached leader stops being
   executable, so the O(1) path survives ordinary use.
7. **R-07** — delete "or unset the engine" from `CauldronHook.sol:1515`, and make
   `_isDead` fail closed (treat an untracked pool as dead, or as an explicit error)
   so the deadlock cannot close even if divergence occurs.

Note the EIP-170 ceiling: `CauldronRegistry` has **55 bytes** and `CauldronHook`
**68 bytes** of margin. Any fix that must live in either belongs in `RedemptionExt`
(11,177 B free), `QuoteRotator` (16,884 B free) or a library.
