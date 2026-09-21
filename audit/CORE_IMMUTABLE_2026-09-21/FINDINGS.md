# Core Immutable Tier — Security Audit

**Date:** 2026-09-21 · **Auditor:** independent pass (solidity-auditor)
**Scope:** the contracts that cannot be replaced or patched
**Method:** OWASP SC Top-10 2025 frame, executed against source rather than a checklist sweep

---

## 1. Pin

```
HEAD                         a709ba7
git status --porcelain       NOT CLEAN  (see below)
Solidity                     ^0.8.26   (overflow-safe by default)
Profile                      FOUNDRY_PROFILE=cauldron  (via_ir, optimizer_runs=1)
```

**The tree was dirty, so this audit reads committed code via `git show HEAD:<file>`,
not the working copy.** Uncommitted at audit time, owned by other concurrent sessions:

```
 M contracts/solidity/CauldronHook.sol                        <- see FINDING-1
 M contracts/solidity/lib/openzeppelin-contracts              (submodule pin)
 M contracts/solidity/test/attacks/Jb_QueueInsolventDepositLock.t.sol
 M contracts/solidity/test/attacks/K3a_StaleQueueEatsDeposit.t.sol
 M contracts/solidity/test/attacks/R2C_DepositLatch.t.sol
 M contracts/solidity/test/attacks/T03_VaultQueueSeniority.t.sol
 M contracts/solidity/test/attacks/X3c_StaleQueueSurvivesRotation.t.sol
 ?? contracts/solidity/test/audit_full_scope/PreSweepFailureClosed.t.sol
```

### Measured suite — and why the number is not usable

```
298 suites · 1157 passed · 8 failed · 1 skipped   (378s wall, 4026s CPU)
```

**Five of the eight failing test files are themselves uncommitted.** The failures are
being produced by another session's in-flight edits to the tests, not by the protocol:

| Failing test | File committed? |
| --- | --- |
| `Jb_QueueInsolventDepositLock` | **no — modified** |
| `K3a_StaleQueueEatsDeposit` | **no — modified** |
| `R2C_DepositLatch` | **no — modified** |
| `T03_VaultQueueSeniority` | **no — modified** |
| `X3c_StaleQueueSurvivesRotation` | **no — modified** |
| `LIQ05_PrematureKillEconomics` | **no — modified** |
| `S08_InSwapGasStarvation` | **yes, clean** — see FINDING-1 |
| `CHURN1_LiveRevert` | yes, clean — unattributed |

**No suite number measured on this tree describes the committed protocol**, in either
direction. This is the fourth time this month that a dirty shared tree has produced a
misleading result (`git log --oneline --grep=RETRACT`). An earlier note of mine quoting
"44 tests currently red" was measured the same way and was equally uninterpretable;
treat it as withdrawn.

### Measured EIP-170 headroom — why the severity bar is different here

```
CauldronRegistry   24,492 / 24,576 B    84 bytes free
CauldronHook       23,774 / 24,576 B   802 bytes free
PerpEngine         23,243 / 24,576 B  1,333 bytes free
MiFrensGenesis     21,831 / 24,576 B  2,745 bytes free
```

There is no proxy anywhere in this system. A finding in `CauldronRegistry` **cannot be
fixed by adding a check** — 84 bytes will not hold a `require`. Remediation is a full
redeploy plus migrating custody of two live v4 position NFTs. Gas and style findings
are therefore omitted as noise; the bar applied was *"can a user reach a state the
machine cannot leave."*

---

## 2. Findings

### FINDING-1 — HIGH (liveness, unpatchable tier) — **RESOLVED 2026-09-22, never shipped**

**An uncommitted change to `CauldronHook._liqSweep` converts a result-ignored
side-effect into an unconditional revert, which can brick every swap on the pool.**

Location: `CauldronHook.sol:834` (committed) vs the working-tree edit.

Committed:

```solidity
if (amountSpecified != 0 && swept && out.length >= 32) {
    uint256 status = abi.decode(out, (uint256));
    if (status == 2) revert LiqTradeTooLarge(MAX_LIQ_PER_SWAP_VIEW);
    if (status != 0) revert LiqGasStarved();
}
```

Working tree:

```solidity
if (amountSpecified != 0) {
    // A failed bounded call or missing status is not a solvency
    // certificate. Only post-trade cleanup may fail best-effort.
    if (!swept || out.length < 32) revert LiqGasStarved();
    ...
}
```

The stated rationale is correct on its own terms: a reverted sweep is not evidence the
book is solvent. But the two branches differ **only** when `swept == false` (the bounded
call itself reverted) or the engine returned no status. In those cases the committed
hook proceeds and the edit reverts the user's swap.

**Impact.** `_liqSweep` is documented three lines above as *"Gas-bounded and
result-ignored: it can never revert or starve the swap it rides on."* That property is
what stops an optional side-effect from bricking the pool. The edit removes it for the
pre-trade sweep. Any condition that makes `PerpEngine.sweepLiquidations` revert
unconditionally — an engine bug, a mid-rotation state mismatch, a repoint to a bad
address, an engine that panics rather than returns — now reverts **every exact-input
swap on the pool**, for everyone, permanently. The hook cannot be patched and its
address encodes the `PoolKey`, so the remedy would be abandoning the pool.

**The two failure modes are not comparable in kind, and that is what decides it.**
Under committed code the downside is bad debt that is *bounded, recorded and absorbed*:
`PerpEngine.unabsorbedEth` (committed, `PerpEngine.sol:2616`) makes the event permanently
readable, and the waterfall that eats it is an accepted owner decision. Under the edit
the downside is **unbounded loss of the market itself**, in the one contract with no
patch path. Trading a bounded, instrumented, accepted risk for an unbounded unpatchable
one is the wrong direction even though the fail-closed instinct is right in isolation.
(Independently reached by `magic-internet-frens-68` on review; stated here because it is
the strongest form of the argument.)

**Evidence it is already biting.** `S08_InSwapGasStarvation::test_S08_E` is a **clean,
committed** test that fails on this tree, and it asserts by name exactly the property the
edit removes:

```solidity
assertTrue(okBelow, "the swap still fills below the bar");
assertGt(deadBelow, 0, "DEGRADES, NOT ALL-OR-NOTHING: a short sweep still banks kills");
```

The committed design is *degrade gracefully*; the edit is *all-or-nothing*. One of the
two has to give, and that is a design decision for the owner, not a silent one.

> **Correction (2026-09-22).** An earlier revision of this section also cited
> `LIQ05_PrematureKillEconomics` as committed evidence. It is **modified in the working
> tree**, so it is not independent evidence and may be the same author's in-flight edit.
> Caught by `magic-internet-frens-68` and verified. Dropping it narrows the claim to one
> test — and strengthens it, because the surviving one is the one that asserts the exact
> property at issue.

**This is not a defect in committed code.** It is flagged because it is in flight toward
a contract that can never be fixed, and because the failing committed tests make the
conflict concrete. Recommendation: keep the fail-closed intent but scope it to the case
the rationale actually describes — a sweep that *ran* and *reported* it could not finish
(`swept == true`, `status != 0`), which the committed code already handles — and leave a
sweep that could not run at all as result-ignored, so a broken engine degrades the
liquidation guarantee instead of bricking the market. If fail-closed on `!swept` is
genuinely wanted, S08_E must be updated deliberately and the owner should accept the
liveness trade explicitly, as was done for the `LiqGasStarved` gas-floor decision.

**Not fixed by me.** It was another session's uncommitted work; editing it would have
repeated the data-loss incident already recorded this week. Raised with the owning
session instead.

> **Resolution (2026-09-22).** `magic-internet-frens-2c` reverted the fail-closed
> variant; the guard line is byte-identical to committed again, so this never reached
> a commit and never reached a deploy. They went further than a revert and pinned the
> reasoning in-place as a comment — naming the asymmetry, and citing `S08` by name —
> so the next reader has to argue with the reason rather than re-derive the same
> fail-closed instinct. That instinct is correct in isolation, which is precisely why
> it would otherwise keep returning. **Verified by diff, not taken on report.**

---

### FINDING-2 — INFORMATIONAL — latent, unreachable today

**`FeeRouteLib.send` omits the codeless-recipient guard its two siblings carry.**

`FeeRouteLib.sol:201`. `_move` and `deliver` both open with
`if (to.code.length == 0) return false;` — the fix for red-team X4c/X4e, where
`.call{value:}` to an address with no code returns `true` and the ether is gone with a
success signal. `send` has no such guard on its native branch.

Both committed call sites (`CauldronHook.sol:1302` `sweepLegacyReserve`, `:1909`
`releaseRelaunchAsset`) pass a real ERC-20, so the native branch is unreachable today
and the ERC-20 branch checks its return value correctly.

**Deliberately not "fixed".** The asymmetry is defensible: `_move` and `deliver` address
protocol contracts by construction, whereas `send` documents a `gasCap` for *"a recipient
the protocol does not control"* — i.e. possibly an EOA, for which a code-length check
would be wrong. Recorded so a future call site does not assume the guard is there. In an
unpatchable library that assumption would be unrecoverable.

---

### FINDING-3 — INFORMATIONAL — **FIXED in `072dbd7`**

**`FeeRouteLib.deliver` clears its allowance only on failure.** `FeeRouteLib.sol:255`.
The comment says *"Leave no standing allowance behind"*, but the reset runs under
`if (!ok)`. A recipient that succeeds while pulling less than `amount` leaves a standing
allowance against the hook.

Not exploitable as wired: the only pull entrypoint, `MiFrensDividend.fundToken`
(`:273-289`), pulls exactly `amount`. Recorded because the library is unpatchable and the
comment overstates what the code does.

**Resolution.** The revoke is now unconditional. Fixed despite being unreachable because
of *where* it lives: a linked library's address is baked into `CauldronHook` at link
time, so it cannot be repointed after deploy and a future call site cannot be handed the
guard later. Cost is one warm zero-over-zero SSTORE on the happy path.

Pinned by `test/audit/CI1_DeliverLeavesNoAllowance.t.sol`, **verified non-vacuous rather
than assumed**: against the pre-fix library `test_CI1_partialPullLeavesNoStandingAllowance`
fails with exactly 40 ether still approved, and passes after. Three controls (full pull,
reverting pull, codeless recipient) hold in both directions, so the X4e guard is pinned
alongside it.

Verified in a throwaway worktree at `HEAD` carrying only the two changed files — the
shared tree does not currently compile (another session has `PerpEngine`/`PoolOps`/
`CauldronBase` mid-edit; the build dies on stack-too-deep), so a result measured there
would have described their work rather than this change.

---

## 3. Negative results — attacked and held

Each of these was probed directly against committed source; every one already carries an
explicit prior-audit lineage in-code, which is why it held.

| Surface | Result |
| --- | --- |
| **SC-01 Access control** — `CauldronToken.burn(from,·)` takes no allowance | Only call site burns `address(this)` (`CauldronRegistry.sol:865`). The keeper path is opt-in **and revocable** (`disableAutoMigrate`, audit F-02). Holds. |
| **SC-01** — `MiFrensGenesis.custodyTransfer` moves NFTs with no approval | Registry-gated; all four call sites pass `msg.sender`/`caller` or `address(this)` as `from`, and OZ `_transfer` independently enforces `from == owner`. Defence in depth. Holds. |
| **SC-02 Logic** — migration atomicity | `migrateOne` burns then reverts if the reserve is short (audit H-03); `autoMigrateBatch` sizes capacity per holder and skips rather than reverting (audit F-08). No partial migration. Holds. |
| **SC-02** — reserve ceiling arithmetic | `ReserveLib.reserveTicks` aligns to usable ticks and collapses degenerately rather than reverting; `launchTick - offset` cannot overflow `int24` at v4 tick bounds. Holds. |
| **SC-03 Reentrancy** | Facet forwarders deliberately omit `nonReentrant` because the facet re-enters the registry's shared guard slot via `CauldronBase` — double-locking would revert every redemption. Correct as documented. |
| **SC-04 Flash loans / governance** | `_getVotingUnits` returns `genesisBalanceOf`, not `balanceOf` — forged frens and Liquidatoor badges cannot be delegated into phantom votes. Holds. |
| **SC-06 Oracle** | Surtax entropy is per-**block** (`blockhash(n-1)` + `prevrandao`), never per-call; the live tick was removed after red-team X1b measured a same-tx probe worth ~3198 bps. Jitter *adds* to the decay after B-03 found `max()` made it dead code. Floor property `total >= decayed` holds. |
| **SC-07 Unchecked calls** | `sweepLegacyReserve` routes through `FeeRouteLib.send` and reverts on `false`, rolling back the counter debit (red-team X1f). Holds for false-returning tokens (USDT-style). |
| **SC-08 Overflow** | All 13 `unchecked` blocks in scope reviewed. Every one is a loop counter, an explicitly saturated add (`nc < c ? type(uint256).max : nc`), or carries a bound proof (24 × 2^128 ≪ 2^256). `b.resolved = uint16(r)` is bounded by `b.count`, itself `uint16`. Holds. |
| **SC-09 DoS** | Gacha queue: a reverting mint is caught and recorded as a loss so the FIFO drains (GACHA1-b). Batch loops are caller-funded and caller-sized. Holds. |

---

## 4. Reachability notes

- Registry forwarders (`redeemOgFren`, `buyTreasuryOgFren`, `donateToReserve`,
  `materializeLegacyReserve`) look ungated at the registry; they inherit the facet's gate
  through `_forwardToExt()`. Confirmed — not permissionless.
- `SurtaxLib.defaultSurtaxBps` is `public` on a linked library, so it is callable directly
  on the library address. It is `view` and stateless. No impact.
- `FeeRouteLib.send` / `deliver` are `external` on a linked library and therefore callable
  directly at the library address, where `address(this)` is the library — which holds no
  funds and no allowances. No drain path.

## 5. Out-of-scope notes

- `PerpVault` exit-queue semantics are being actively reworked across five uncommitted
  test files and six recent commits (`6634f2a`, `beedf49`, `8bcfe78`, `58e1a55`). Tier 1,
  not audited here; it is the noisiest area in the repo and deserves its own pass once
  the tree settles.
- `CauldronRegistry` at 84 free bytes cannot absorb any future fix. Independent of any
  finding above, that is a standing operational risk worth a deliberate decision.

---

## 6. Conclusion

**No Critical, High or Medium defect was found in committed code in the immutable tier.**
One informational hardening (FINDING-3) was fixed in `072dbd7` with a non-vacuous
regression test; FINDING-2 was deliberately left alone with its reasoning recorded.
That is the expected outcome for a codebase carrying five prior audits and 185
proof-of-concept exploit suites, and the in-code audit lineage on every path probed here
(X1b, X1f, X4c, X4e, H-03, F-02, F-08, B-03, GACHA1-b, I-07, D-1, R1C, H1) is consistent
with it. Checklist-shaped findings on this tier are exhausted.

The one item worth acting on was **FINDING-1**, and it was in a working tree rather than
in the protocol: an in-flight change traded the hook's "an optional step can never revert
a user's swap" guarantee for a solvency guarantee, in a contract that can never be
patched, while a committed test disagreed with it by name. **It was reverted before it
reached a commit, and the reasoning is now pinned in the source.**

**Every finding from this pass is closed.** FINDING-1 reverted by its owner; FINDING-3
fixed in `072dbd7` with a non-vacuous regression test; FINDING-2 deliberately left alone
with its reasoning recorded so it is not "fixed" later by someone reading it as an
oversight.

**What this pass does NOT establish.** No audit proves the absence of bugs, and this one
is narrower than most: it deliberately excluded everything behind a setter, and it could
not measure the test suite against committed code, because the shared tree did not
compile throughout. A clean-tree suite run is still owed, and is the single most useful
next step — the most recent trustworthy number predates several in-flight changes to
`PerpVault`, `PerpEngine`, `PoolOps`, `CauldronBase` and `RedemptionExt`.
