# Implementation plan — preserve perp backing across a quote rotation (D-2)

Date: 2026-09-22. Status: **IMPLEMENTED**, tests green, sizes measured.
Companion to `QUOTE_AGNOSTIC_PERPS_SCOPE.md`.

## OUTCOME — what actually shipped, and how it differs from the plan below

Four things changed during implementation. Each was forced by something the
plan had wrong, and each is recorded here rather than quietly folded in.

**1. The registry cannot host a new entry point.** `CauldronRegistry` dispatches
to the facet through explicit per-selector stubs and has **8 bytes** of EIP-170
headroom — so `convertPerpBacking` could not exist as planned in §1. The
conversion is instead driven from the **vault**, permissionlessly, and the
existing `rotateSliceFrom` flip merely *arms* it and takes one best-effort shot.

**2. The vault therefore needed its own authority on the rotator.**
`QuoteRotator` gained a `converter` slot (owner-set) accepted by `swapOnce` and
`withdraw`. It grants no new discretion: the venue allowlist and the oracle
floor both still bind. Rotator had 16,074 B free.

**3. Asking the vault must never be able to revert the adoption.** The first
version called `IPerpVaultStake(vault).consumeRequote()` directly. A vault
deployed *before* this feature has no such selector, so the typed call reverted
`syncGeneration` **wholesale** — caught by `X3a_QuoteRotationRedenominates`,
whose mock vault has no fallback. That is the brick shape this codebase has
closed four times. It now goes through `PerpSwapLib.tryConsumeRequote` — a
low-level call in a linked library where "no answer" means `false`, which is the
same lesson `PerpVault._engineQuote` already records against `quote()`. As a
DELEGATECALLed library it also costs the engine a call site instead of a branch.

**4. Two guards the plan missed**, both found by re-auditing the written code:

- **`BookOpen`** — `totalEth() = plv + longOiEth`, and only `plv` is converted.
  `longOiEth` is principal lent to open longs, still in the old quote.
  Converting one and not the other makes every share price a 6-decimal number
  minus an 18-decimal one. The book must be empty.
- **`AlreadyRequoted`** — `from` stays the OLD quote until the engine adopts, so
  a second call would convert an already-converted pot and mislabel it.

Also: the engine pays the rotator **directly** (`withdrawPlvTo(spent, rot)`)
rather than routing the old asset through the vault, so the vault never
custodies a second asset. It keeps a `receive()` restricted to the engine and
the rotator, for the case where a rotation goes back to a native quote.

### Measured sizes (`FOUNDRY_PROFILE=cauldron forge build --sizes`)

| contract | before | after | delta | free |
|---|---:|---:|---:|---:|
| PerpEngine | 24,338 | 24,490 | **+152** | **86** |
| PerpVault | 11,613 | 13,461 | +1,848 | 11,115 |
| RedemptionExt | 13,916 | 15,826 | +1,910 | 8,750 |
| QuoteRotator | 8,502 | 8,731 | +229 | 15,845 |
| PerpSwapLib | 8,978 | 9,143 | +165 | 15,433 |
| CauldronRegistry | 24,568 | 24,568 | 0 | 8 |
| CauldronHook | 23,978 | 23,978 | 0 | 598 |

The engine stayed under its 238-byte budget. Nothing else moved.

### Tests

`test/functional/F12_RequoteBacking.t.sol` — **8 passing**, values logged so the
arithmetic is visible rather than merely asserted:

- T1 — 4 ETH → 12,000 USDG, split 9,000 / 3,000: the 75/25 proportion survives
- T2 — a 3.5 ETH queued claim becomes exactly 10,500 USDG; **no epoch bump**,
  so the unit change was not read as a total loss
- T3 / T3b — a fill under the floor reverts wholesale, leaves `plv` in the old
  asset, and the permissionless retry then succeeds
- T4 — `consumeRequote` is engine-only and one-shot
- T5 — `armRequote` is registry-only; no divergence ⇒ inert
- T6 — refuses while a long is open, then succeeds once flat
- T7 — cannot convert twice before adoption

Full suite on this tree: **848 passing, 38 failing** — every remaining failure
is a fork/env gate (`FORK_RPC` unset, or `call to non-contract address 0x0` from
an unset env address), none touching this change. `X3a_QuoteRotationRedenominates`
regressed and is now fixed (see §3 above).

### Deploy wiring — REQUIRED, or the feature silently does nothing

`DeployPerp.s.sol` now calls `rotator.setConverter(vault)` when `QUOTE_ROTATOR`
is exported. **Without it the write-off path is still what runs** —
`requoteQuoteSide` reverts `NotOwner` inside `swapOnce`. Nothing bricks; the
backing simply does not survive the rotation, which is the whole point. On
mainnet the rotator's owner is the treasury/timelock, so this is a governance
call in the rotation runbook, not a deploy step.

---


## 0. Verified facts this plan rests on

Every one of these was read, not assumed. Where a comment disagreed with code,
the code wins (that is how the R-1 correction was earned).

| # | Fact | Evidence |
|---|------|----------|
| V1 | `RedemptionExt` is a **delegatecall facet of `CauldronRegistry`** — inside it, `address(this) == registry` | `CauldronBase.sol:21-22,126-130`; `CauldronRegistry.sol:186-187` |
| V2 | `QuoteRotator.swapOnce(route, from, to, amountIn, minOut)` is `onlyRegistry` and is the existing curated-venue swap primitive | `QuoteRotator.sol:335-341`; used at `RedemptionExt.sol:458` |
| V3 | Engine↔vault money API: `fundFromVault(uint256) payable onlyVault`, `withdrawPlvTo(uint256,address) onlyVault` | `PerpEngine.sol:2902,2908` |
| V4 | `totalEth() = plv + longOiEth`, and `syncGeneration` sets `longOiEth = 0`; adoption requires `openCount == 0`, so **at adoption `totalEth() == plv`** | `PerpEngine.sol:616,1597,1542` |
| V5 | Vault share value is derived, not stored: `assetsEth() = engine.totalEth() - pendingEth()`. The vault holds no ETH of its own | `PerpVault.sol:268-272` |
| V6 | `pendingEth() = ethQueueUnits * ethQueueIndex / QSCALE` — an **absolute** old-asset figure | `PerpVault.sol:418-420` |
| V7 | `_syncEthQueue` haircuts the queue when `backing < ethBackingMark`, and **retires the entire queue** when the new index rounds to 0 | `PerpVault.sol:488-512` |
| V8 | `PerpVault.deposit` is **already quote-agnostic** — it reads `_engineQuote()` and pulls ERC20 via `_pull`/`_approve` when non-native | `PerpVault.sol:296-334` |
| V9 | `PerpSwapLib` has `external` functions ⇒ it is a **linked library, DELEGATECALLed**; additions there cost the engine only call-site bytes | `forge build --sizes` lists `PerpSwapLib` at 8,978 B |

### V5+V6 together are the whole correctness argument

Because share value is *derived* from `engine.totalEth()`, **live shares
redenominate for free**. A holder of 10% of `ethShares` owns 10% of the pot
before and after; only the pot's unit changes. That is exactly the intent.

What does **not** redenominate for free is the exit queue. `pendingEth()` is an
absolute old-asset number. If `plv` flips from ~1e21 wei to ~1e9 USDG raw while
`ethQueueIndex` stays put, then:

- `assetsEth()` saturates to **0** (V5 subtracts a wei-sized `pendingEth` from a
  USDG-sized `totalEth`) → **every live share is instantly worth nothing**, and
- `_syncEthQueue` sees `backing (1e9) << mark (1e21)` → haircuts to `newIdx == 0`
  → **retires the whole queue** (V7).

So the conversion is not optional bookkeeping. Converting `plv` *without*
rescaling `ethQueueIndex` and re-marking `ethBackingMark` in the same transaction
destroys both live shares and queued exits. **These three writes are atomic or
the change is worse than the write-off it replaces.**

## 1. Design

Division of labour, forced by the byte budget (PerpEngine: **238 B free**):

- **`RedemptionExt`** (10,660 B free) — *drives*. It is the registry (V1), so it
  alone may call `swapOnce` (V2). It already holds the curated `route`.
- **`PerpVault`** (12,963 B free) — *accounts*. Owns every unit-bearing write.
- **`PerpEngine`** (238 B free) — *minimal*. One call swapped for another, one
  branch. Budget: **≤ 180 B**, measured before and after.

### Sequence (one transaction, driven from RedemptionExt)

```
convertPerpBacking(route, minOut)                     [registry context]
 1. from = engine.quote();  to = generationQuote[gen]
    require(to != from)                               // only at a real divergence
    require(engine.openCount() == 0)                  // book already settled
 2. amt = vault.releaseForRequote()                   // vault → engine.withdrawPlvTo(plv, registry)
 3. out = rotator.swapOnce(route, from, to, amt, minOut)
    rotator.withdraw(to, address(this), out)
 4. vault.creditRequote{value:…}(out, amt, to)        // vault → engine.fundFromVault(out)
                                                      // vault rescales index + re-marks + arms flag
 5. engine.syncGeneration()                           // adopts; consumes flag; SKIPS the plv sweep
```

Steps 2–4 leave the vault's invariants intact at every intermediate point
because nothing else can interleave — single transaction, `nonReentrant`.

### Why `swapOnce` and not a new swap

It is the same primitive, same curated venue, same floor discipline the
mandate-completing slice itself uses. Reusing it means the conversion **cannot
be routed through an uncurated pool** and cannot be executed at a
caller-chosen floor — the two properties `QuoteRotator.sol:290-299` exists to
enforce. A bespoke swap would have to re-earn both.

### What converts, what does not

| Counter | Unit | Treatment | Why |
|---|---|---|---|
| `plv` (engine) | old quote | **CONVERT** | staker principal — the whole point |
| `ethQueueIndex` (vault) | old quote / QSCALE | **RESCALE** at the realized rate | V6/V7 — or the queue is retired |
| `ethBackingMark` (vault) | old quote | **RE-MARK** post-credit | V7 — or the flip reads as a total loss |
| `ethShares` (vault) | dimensionless | untouched | V5 — proportions are unit-free |
| `insuranceEth` (engine) | old quote | **sweep to treasury** (unchanged) | keeps the documented "opens pause until `fundInsurance` re-funds in the new asset" behaviour |
| `tokYieldEth` (engine) | old quote | **written off** (unchanged) | see below |
| `plvToken` (engine) | generation token | untouched | a quote rotation does not redenominate it |

**`tokYieldEth` stays a write-off — deliberate.** Converting it would require
rescaling `accEthPerTokShare`, `epochAcc` **and every `tokRewardDebt[user]`**
(`PerpVault.sol:152,179,662`) — an unbounded per-user mapping, not rescalable in
O(1). The existing forfeit-line machinery (`:626,633`) already handles the
write-off correctly and emits `TokYieldWrittenOff` by name. It is accrued
*reward*, not principal; token principal (`plvToken`) is untouched either way.
Documented as a known limitation rather than silently half-done.

### Fail-safe rule

If `swapOnce` cannot clear `minOut`, the whole call reverts. The engine keeps
`plv` **in the old asset**, stays parked and diverged, and `convertPerpBacking`
is permissionless so anyone retries at a better time or on a deeper venue. The
pool rotation is already done and is *not* rolled back. A thin venue therefore
delays engine adoption; it never strands principal and never forces a write-off.

## 2. Changes, file by file

### 2.1 `PerpVault.sol` (+~700 B est.)

```solidity
bool    public requotePending;   // armed by creditRequote, consumed by the engine
address public requotedTo;       // for events/inspection

/// Vault pulls its own quote-side principal out so the registry can swap it.
function releaseForRequote() external nonReentrant returns (uint256 amt) {
    _onlyRegistry();                 // engine.registry()
    _requireDiverged();              // engine.quote() != generation quote
    _syncEthQueue();                 // recognise losses in OLD units FIRST
    amt = engine.freeEth();          // == plv; == totalEth() at adoption (V4)
    if (amt == 0) revert ZeroAmount();
    engine.withdrawPlvTo(amt, msg.sender);
}

/// Registry hands back the proceeds; the vault re-denominates itself.
function creditRequote(uint256 got, uint256 spent, address to)
    external payable nonReentrant
{
    _onlyRegistry();
    if (got == 0 || spent == 0) revert ZeroAmount();
    if (to != address(0)) { _pull(to, msg.sender, got); _approve(to, address(engine), got); }
    else if (msg.value != got) revert ZeroAmount();
    engine.fundFromVault{value: to == address(0) ? got : 0}(got);

    // THE QUEUE MUST MOVE AT THE SAME REALIZED RATE (V6/V7).
    if (ethQueueUnits != 0) {
        uint256 ni = FullMath.mulDiv(ethQueueIndex, got, spent);
        //  Never let a DENOMINATION change round the queue to zero: that path
        //  (_syncEthQueue :504) retires every claim and bumps the epoch, which
        //  is a total loss triggered by a unit change rather than by a loss.
        ethQueueIndex = ni == 0 ? 1 : ni;
    }
    _markEth();                      // re-mark in the NEW unit, post-credit
    requotePending = true;
    requotedTo = to;
    emit QuoteSideConverted(_engineQuote(), to, spent, got, ethQueueIndex);
}

/// One call that answers AND clears — so the engine spends one selector, not two.
function consumeRequote() external returns (bool ok) {
    if (msg.sender != address(engine)) revert NotEngine();
    ok = requotePending;
    if (ok) requotePending = false;
}
```

Ordering inside `creditRequote` is load-bearing: `fundFromVault` **before**
`_markEth()`, so the mark records post-credit backing; and the index rescale
before `_markEth()` for the same reason.

### 2.2 `RedemptionExt.sol` (+~450 B est.)

New permissionless `convertPerpBacking(PoolKey calldata route, uint256 minOut)`
implementing the 5-step sequence. Guards:

- `to != from` — only at a genuine divergence
- `engine.openCount() == 0` — the book must already be settled
- venue curation and floor come from `swapOnce`, not from this function
- best-effort `syncGeneration()` at the end (`try/catch`), matching the
  established pattern at `:693` — a failed adoption leaves a retryable state,
  it must not roll back a completed swap

### 2.3 `PerpEngine.sol` (target ≤ 180 B)

Inside the existing `if (newQuote != quote)` block, wrap veto + `plv` sweep:

```solidity
bool conv = vault != address(0) && IPerpVaultStake(vault).consumeRequote();
if (!conv && msg.sender != owner() && vault != address(0)
    && IPerpVaultStake(vault).hasQuoteStake()) revert VaultStaked();

uint256 writtenOff = tokYieldEth;
emit TokYieldWrittenOff(quote, writtenOff);
uint256 sweep = writtenOff + insuranceEth + (conv ? 0 : plv);
if (!conv) plv = 0;                 // converted plv is ALREADY the new asset
tokYieldEth = 0; insuranceEth = 0;
if (sweep != 0 && treasury != address(0)) _tryPush(treasury, sweep, true);
```

The veto still runs on the unconverted path — nothing is relaxed for anyone who
has not actually moved the money. On the converted path the veto is *satisfied*,
not bypassed: staker value has been moved into the new asset, which is the
precise condition the veto existed to protect.

`_tryPush` pays in `quote`, which is still the **old** quote at this line, and
the swept counters (`insuranceEth`, `tokYieldEth`) are old-asset — consistent.
The engine holds both assets at this instant (old-asset insurance dust, new-asset
`plv`), which is correct and transient.

## 3. Test plan

New `test/functional/F12_RequoteBacking.t.sol`:

| # | Assertion |
|---|---|
| T1 | ETH→USDG with live stakers: `ethShares` unchanged, `assetsEth()` ≈ `out`, share **proportions** preserved to 1 wei |
| T2 | A queued exit straddling the flip is paid the **same fraction** of the pot after as before (this is the V6/V7 regression) |
| T3 | `unabsorbedEth == 0` across the whole sequence |
| T4 | `swapOnce` below `minOut` ⇒ whole call reverts, `plv` still old-asset, engine still parked, **retry succeeds** |
| T5 | Round trip ETH→USDG→ETH; a staker who never touched the vault can withdraw a sane ETH amount at the end |
| T6 | Unconverted path unchanged: no `creditRequote` ⇒ old sweep-to-treasury behaviour byte-for-byte |
| T7 | `consumeRequote` is one-shot — a second `syncGeneration` cannot reuse the flag |
| T8 | `releaseForRequote` / `creditRequote` revert for a non-registry caller |

Plus: re-run `RotationRoundTrip.t.sol` and the existing rotation attack suite
(`S0x_RotationPerpHostage`, `T02_PerpAfterRotation`, `X8c_RotationOrphansEveryLeg`,
`K3c_RotationStrandsPerpEngine`, `F10_QuoteRotationTotality`) — these encode the
prior fixes and must not regress.

**PoC discipline** (prior lesson): run with `-vv` and confirm assertion counts —
an early `return` makes a Foundry PoC pass vacuously.

## 4. Byte budget — hard gate

Measure `FOUNDRY_PROFILE=cauldron forge build --sizes` before and after.
**PerpEngine must stay under 24,576.** Baseline 24,338 (238 free). If the engine
delta exceeds 238 B, the change does not ship as written; the fallback is to move
the `conv` branch behind a `PerpSwapLib` external (V9), which costs the engine a
call site instead of a branch.

## 5. Deliberately NOT in this change

- **D-1** (force-close settling against the drained pool). Real, separate, needs
  engine headroom. Tracked in the scope doc.
- **D-3** (mark source re-arm) — an ops runbook item.
- `tokYieldEth` conversion — see §1, unbounded per-user rescale.
- Testnet venue re-seed — needed before any *live* retest, but it is a deploy
  parameter (`VENUE_ETH`, open-band width), not a contract change.
