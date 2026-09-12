# Smart Contract Security Audit Report
Magic Internet Frens — Cauldron protocol (Uniswap V4 hook)

## Executive Summary

**Project:** Magic Internet Frens / Cauldron
**Auditor:** Claude Opus 5 (solidity-auditor skill), scope-limited blind pass
**Date:** 2026-09-12
**Commit range:** `1e98bb4..HEAD` (branch `fix/b05-b07-relaunch-totality`, HEAD `6459b85`)
**Scope:** OWASP **SC-01 (Access Control)** and **SC-02 (Logic Errors)**, restricted to the
code changed in this range under `contracts/solidity`.
**Solidity Version:** `^0.8.26` (checked arithmetic; no overflow findings raised outside
`unchecked`).

### Overview

This was a final pre-deploy pass over ~40 commits touching 21 contracts. The changes are
almost entirely remediation: new guards (`renounceOwnership` disabled on 7 contracts, a
denomination gate on `fundLegacyBuffer`, a native-only gate on `_creditPerp`, a
four-counter gate on `syncGeneration`, envelope+cooldown gates on
`TreasuryGovernor.execute`), new state (`legacyBufferAsset`, `payoutOwedTotal`,
`ringArmedAt`, `hasQuoteStake`, `_bench`, `InventoryMigrationShortfall`), and one facet
relocation (`claimByBurnUpTo` → `RedemptionExt`).

I found **no Critical and no High**. The gates themselves are, with one exception,
complete and on the correct side of the delegatecall boundary. What I did find is the
predictable second-order class: **two of today's new guards can be held shut forever by a
party with no privileges**, and **one of today's newly-reachable recovery paths recovers
value into a slot with no exit**. Each is a specific, cheap, permanent condition — not a
theoretical one.

### Risk Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 3 |
| Low      | 2 |
| Info     | 3 |

### Key Findings

- **MEDIUM-01** — `payoutOwedTotal` is a *permanent, attacker-set* veto on the perp
  engine's quote adoption. One wei accrued to a contract that refuses its push blocks
  `syncGeneration`'s quote flip forever, with no admin override; the treasury rotation
  proceeds anyway (`try/catch`), so the engine is left permanently stranded on the old
  quote — the exact denomination-divergence state commit `e964d54` was written to prevent.
- **MEDIUM-02** — `fundLegacyBuffer` still accepts wei into `legacyBuffer` when the
  buyback is **disabled** (`legacyRegistry == 0`). `_maybeLegacyBuyback` returns before the
  new drain, so that wei has no reader at any privilege level. The `X1/X4a` fix closed the
  denomination case of "accepted-but-unspendable" and left the disabled-feature case open.
- **MEDIUM-03** — the newly-forwarded public `recoverLegs(gen)` retry **drops `quoteOut`**.
  A leg whose quote matches the primary's `currency0` is unwound into the registry and
  booked nowhere; `sweepLegProceeds` reads only `legProceeds`, so the recovered value is
  locked. The retry that was made reachable today recovers funds into a dead end.

---

## Scope

### Contracts in Scope (diff-only)

| Contract | Change in range | What I judged |
|----------|-----------------|---------------|
| `CauldronHook.sol` | +194 | `legacyBufferAsset`, `fundLegacyBuffer` gate, `_creditFor`, `_routeEthFee` carves, `SurtaxLib` extraction, renounce guard |
| `CauldronRegistry.sol` | +63/-... | `recoverLegs` forwarder, `claimByBurnUpTo` stub, `RECOVER_LEGS` selector change, `hasClaimed` removal |
| `cauldron/CauldronBase.sol` | +47 | renounce guard, `claimed` reserved-slot note |
| `cauldron/RedemptionExt.sol` | +153/-... | `fromQuote` primary fix, `recoverLegs`/`recoverLegsAtTeardown` split, `completeRotation` deletion, `claimByBurnUpTo` body |
| `cauldron/PerpEngine.sol` | +109 | `payoutOwedTotal`, `hasQuoteStake` guard, `ringArmedAt`, `_creditPerp` gate, `_pullIntoPlv`/`_vaultPaid` folds |
| `cauldron/PerpVault.sol` | +39 | `hasQuoteStake`, `claimPendingEth` write-down persistence |
| `cauldron/TreasuryGovernor.sol` | +172 | `_bench`, `execute` gates, `allowance`/`noteMoved` migration budget, `setGuardian` zero check |
| `cauldron/CauldronGovernor.sol` | +91 | `_bench`, renounce guard |
| `cauldron/QuoteRotator.sol` | +65 | `NotPriceable`, `_usdLive`, codeless-token check |
| `cauldron/LegacyBuyLib.sol` | +71 | `encumbered` clamp, sqrt price limit, checked transfer, `NoOutput` |
| `cauldron/PoolOps.sol` | +30 | `vaultSwept` denomination |
| `cauldron/CauldronGachaRouter.sol` | +46 | churn refund debits, `rescueToken`, renounce guard |
| `cauldron/FeeRouteLib.sol` | +35 | codeless-recipient checks |
| `cauldron/SurtaxLib.sol` | +106 (new) | jitter entropy, add-not-max |
| `cauldron/MigrationVesting.sol` | +54 | `MAX_GRANTS`/`MAX_BATCH_GRANTS`, renounce guard |
| `cauldron/PerpSwapLib.sol` | +28 | `InventoryMigrationShortfall` |
| `cauldron/LaunchSniper.sol`, `PerpMarkSource.sol`, `MiFrensGenesis.sol`, `MiFrensDividend.sol`, `RoyaltyRouter.sol` | small | renounce guards, `play` signature, cancelled-ignite gate, comment fixes |

### Out of Scope
- Everything unchanged in this range; the whole tree outside `contracts/solidity`.
- Vendored dependencies (OpenZeppelin, v4-core, v4-periphery).
- SC-03..SC-10 except where they intersect a changed gate.
- The 22 items on the coordinator's KNOWN list are excluded unless a fix is
  **incomplete** or **introduced something new** — MEDIUM-02, MEDIUM-03 and LOW-01 are of
  that kind and are stated as such.

---

## Methodology

1. `git log --oneline 1e98bb4..HEAD -- contracts/solidity` → per-commit `git show` for
   every commit in SC-01/SC-02 territory.
2. Diffs read first, then the **current** file at every cited line (a diff can mislead
   about final state — three of my candidate findings died this way, see *Refuted* below).
3. Every symbol grepped before citation: writers and readers enumerated for each new
   state variable (`payoutOwed*`, `legacyBufferAsset`, `ringArmedAt`, `_bench`,
   `hasQuoteStake`).
4. Comments treated as claims to test, not evidence. Two comment claims were tested and
   held (`recoverLegsAtTeardown`'s "no forwarder is the access control";
   `usdPerRawUnit` being a real `external view` so the `staticcall` in `_usdLive` cannot
   dead-end the rotator). One is downgraded — see LOW-01.

---

## Findings

### [MEDIUM-01] `payoutOwedTotal` gives any address a permanent, free veto on the perp engine's quote adoption

**Severity:** Medium
**Status:** Open
**File:** `contracts/solidity/cauldron/PerpEngine.sol`
**Lines:** 1154 + 1156 (guard), 1460-1478 (`_payOut`, accrual at 1477), 1482-1487 (the only clearer), 368 (declaration)
**Related:** `contracts/solidity/cauldron/RedemptionExt.sol:562` (the `try/catch` that
makes the block silent)

#### Description

Commit `e964d54` correctly widened `syncGeneration`'s rotation guard from `plv != 0` to
the whole set of quote-denominated counters:

```solidity
// PerpEngine.sol:1154
if ((plv | tokYieldEth | insuranceEth | payoutOwedTotal) != 0) revert VaultStaked();
```

`plv`, `tokYieldEth` and `insuranceEth` are all drainable by parties who *want* them
drained (LPs withdraw, the owner skims insurance). `payoutOwedTotal` is not. Its only
decrementer is:

```solidity
// PerpEngine.sol:1482
function claimPayout() external nonReentrant returns (uint256 amount) {
    amount = payoutOwed[msg.sender];      // ← msg.sender only
    ...
    payoutOwedTotal -= amount;
```

There is no `claimPayoutFor`, no owner sweep, no emergency clear — I grepped every
`payoutOwed` reference in the non-test tree: declaration (358), aggregate (368), the guard
(1154), the accrual (1477), and the three lines of `claimPayout` (1483-1486). That is the
complete set.

The accrual is *chosen by the recipient*:

```solidity
// PerpEngine.sol:1460-1478
function _payOut(address to, uint256 amount) internal {
    if (_quoteIsNative()) { (ok, ) = to.call{value: amount, gas: 30_000}(""); }
    ...
    if (!ok) { unchecked { payoutOwed[to] += amount; payoutOwedTotal += amount; } ... }
}
```

`_payOut` is reached with `to = p.trader` on every settlement (`PerpEngine.sol:1285`), and
with `to = keeper` (1269, 1283). A trader whose address is a contract with a reverting or
>30k-gas `receive()` accrues `payoutOwed` by design — that credit-instead-of-revert
behaviour is itself a deliberate anti-griefing fix (audit H-04). Combining it with the new
aggregate turns it into a different griefing primitive.

#### Impact

One wei of never-claimed `payoutOwed` makes `syncGeneration` revert `VaultStaked()` for
every future quote change, permanently. The rotation is **not** blocked in turn — both
callers wrap the sync:

```solidity
// RedemptionExt.sol:562 and CauldronRegistry.sol:1115
if (eng != address(0)) { try IPerpSync(eng).syncGeneration() {} catch {} }
```

So the treasury's quote rotation completes while the engine keeps `quote` pointed at the
old asset forever. That is the *denomination divergence* state recorded in this repo's own
notes as F-10/F-11 ("live rotation left generationQuote + perp engine permanently stale"),
re-entered through a door that commit `e964d54` opened. Downstream: the hook's
`creditPerpFeeAsset` rejects the new `_feeAsset` (`asset != quote`), `_creditPerp` now
reverts `BadParam` on the native side too (`PerpEngine.sol:1700`), so the engine stops
receiving fee revenue entirely; and marks/collateral are measured against a pool whose
quote it no longer agrees with.

Cost to the attacker: their own stuck payout (which they can reclaim at any time by
calling `claimPayout` from a different… no — `payoutOwed` is keyed on the *recipient*, so
they must un-brick their own receiver to reclaim it; the veto and the reclaim are the same
switch, and they may simply choose never to flip it). No privileges, no timing, no capital
beyond one settlement.

A second, non-adversarial instance of the same shape: `_payOut(dividend, toDiv)` and
`_payOut(treasury, toTre)` (`PerpEngine.sol:1444-1445`). `MiFrensDividend.receive()`
(`MiFrensDividend.sol:235-249`) does five SLOADs, three SSTOREs and a LOG — I measured it
by inspection at roughly 19-25k gas on the `activeShares != 0` path, i.e. *inside* the 30k
budget but not by much, and unambiguously **over** it on the `activeShares == 0` path,
which nests a further `treasury.call{value:}`. If that push ever fails, the credit lands
at `payoutOwed[dividend]`, and `MiFrensDividend` has no function that calls
`claimPayout()` — so it is unclaimable by anyone, and the veto becomes permanent with no
attacker at all.

#### Proof of Concept

```solidity
contract Veto { receive() external payable { revert(); } }

// 1. Veto opens a position on a native-quoted generation.
uint256 id = perp.open{value: 0.01 ether}(/* long, 1x */);
// 2. Anyone settles/liquidates it. PerpEngine._payOut(p.trader, residual):
//      to.call{value: residual, gas: 30_000}("")  ->  reverts
//      payoutOwed[Veto]   += residual
//      payoutOwedTotal    += residual       // now non-zero, forever
// 3. The guild passes a quote-rotation mandate and the treasury executes it:
//      RedemptionExt.rotateSliceFrom(...)   -> generationQuote[gen] = USDG
//      try perp.syncGeneration() {} catch {} -> VaultStaked(), SWALLOWED
// 4. Any later call, by anyone, for the life of the generation:
assertEq(perp.quote(), address(0));                        // still native
vm.expectRevert(PerpEngine.VaultStaked.selector);
perp.syncGeneration();                                     // forever
```

#### Recommendation

Remove the need to block on this counter at all, by recording the asset each credit
accrued in — then a stale credit is payable in its own denomination and cannot poison a
rotation:

```solidity
// storage
mapping(address => address) public payoutAsset;   // to -> asset the credit is in

function _payOut(address to, uint256 amount) internal {
    ...
    if (!ok) {
        address a = _quoteIsNative() ? address(0) : quote;
        //  One denomination per entry. A second credit in a DIFFERENT asset must
        //  not silently merge with the first.
        if (payoutOwed[to] != 0 && payoutAsset[to] != a) { _payOutSecondary(to, a, amount); return; }
        payoutAsset[to] = a;
        unchecked { payoutOwed[to] += amount; payoutOwedTotal += amount; }
        emit PayoutOwed(to, amount);
    }
}

function claimPayout() external nonReentrant returns (uint256 amount) {
    amount = payoutOwed[msg.sender];
    if (amount == 0) revert ZeroValue();
    address a = payoutAsset[msg.sender];
    payoutOwed[msg.sender] = 0;
    payoutOwedTotal -= amount;
    if (a == address(0)) _sendEth(msg.sender, amount); else _pushAsset(a, msg.sender, amount);
}

// PerpEngine.sol:1154 — payoutOwedTotal no longer belongs in the guard.
if ((plv | tokYieldEth | insuranceEth) != 0) revert VaultStaked();
```

If that is too much bytecode for this engine's 67-byte EIP-170 margin, the minimum
acceptable alternative is an escape hatch that lets the *guild*, not the recipient, retire
a stale credit — e.g. `onlyOwner sweepStalePayout(address to)` that moves
`payoutOwed[to]` into `insuranceEth` after a long deadline and zeroes
`payoutOwedTotal` accordingly. Do **not** simply drop `payoutOwedTotal` from the guard
without redenominating the credits: that restores the H-1 bug `e964d54` fixed.

The same reasoning applies, one notch weaker, to the second half of that guard
(`PerpEngine.sol:1156`): `PerpVault.hasQuoteStake()` (:179) returns `(ethShares | pendingEth) != 0`,
so a single-wei vault depositor who never withdraws also vetoes every future rotation.
That one is defensible — you genuinely must not redenominate someone's stake — but it
should be an explicit, documented product decision that the guild can be blocked by one
staker, and `PerpVault` should expose a forced-exit-to-queue the guild can drive.

---

### [MEDIUM-02] `fundLegacyBuffer` still accepts unspendable wei when the buyback is switched off

**Severity:** Medium
**Status:** Open
**File:** `contracts/solidity/CauldronHook.sol`
**Lines:** 1129, 1155-1162 (`fundLegacyBuffer`), 1017 + 1028 (the early return that precedes the drain), 1893 (`setLegacyBuyback`)

#### Description

Commit `f9c775f` (amended by `8fa52c6`) established the rule that the buyback buffer must
never hold value it cannot spend, and that such value must be *routed*, never refused:

```solidity
// CauldronHook.sol:1155
if (msg.value == 0) return;
if (Currency.unwrap(_liveKey.currency0) != address(0)
    || (legacyBuffer != 0 && legacyBufferAsset != address(0))) {
    relaunchETH += msg.value;    // routed to a counter with a real exit
    return;
}
legacyBufferAsset = address(0);
legacyBuffer += msg.value;
```

The gate tests the **denomination** and nothing else. It does not test whether the buyback
feature exists. And the drain that `_maybeLegacyBuyback` gained in the same commit sits
*behind* the feature switch:

```solidity
// CauldronHook.sol:1017
if (legacyRegistry == address(0) || legacyBuffer == 0) return;   // ← returns first
PoolKey memory live = _liveKey;
if (legacyBufferAsset != Currency.unwrap(live.currency0)) { ... drain to relaunch ... }
```

`legacyRegistry` is a mutable switch, and `0` is its documented OFF value:

```solidity
// CauldronHook.sol:1893 — "`registry_` = the Cauldron registry (0 = OFF)"
function setLegacyBuyback(address registry_, uint256 bps, uint256 threshold) external {
    if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
```

So on a **native-quoted** generation with the buyback off, `fundLegacyBuffer` takes the
wei into `legacyBuffer`, and every reader of `legacyBuffer` is unreachable:
`_maybeLegacyBuyback` returns at line 1017, `legacyBuyStep` is only called from there, and
`sweepLegacyReserve` moves *tokens*, not the buffer. I grepped all seven `legacyBuffer`
references in the hook; there is no setter and no sweep. The value is stranded at every
privilege level — which is precisely the sentence `f9c775f`'s own commit message uses to
justify itself.

Both `_routeEthFee` carves are safe here (they already require
`legacyRegistry != address(0)`, lines 1389 and 1413). `fundLegacyBuffer` is the one
ingress that does not, and it is the permissionless one: `RoyaltyRouter` forwards
unconditionally from an immutable `hook` address (`RoyaltyRouter.sol:33`), so every
EIP-2981 royalty on the collection lands here whether the buyback is wired or not.

#### Impact

Permanent loss of all NFT royalty revenue accrued while the buyback is off, on a
native-quoted generation. Two realistic triggers:

1. **A deployment that never wires it.** `setLegacyBuyback` appears exactly once in the
   deploy tree (`deploy/DeployLaunchpad.s.sol:403`) and is absent from `DeployCauldron`;
   any path that mints a collection before wiring the buyback strands every royalty paid
   in that window.
2. **Switching it off deliberately.** The owner/registry turning the feature off — the
   documented use of `registry_ = 0` — silently converts the entire standing buffer into
   dead weight. Nothing in `setLegacyBuyback` drains it first.

Not attacker-profitable (the attacker would be burning their own ether), so this is a
fund-lock rather than a theft: Medium.

#### Recommendation

Two one-line changes; either alone closes it, both together is correct.

```solidity
// CauldronHook.sol:1155 — route, don't accumulate, when there is no spender.
if (msg.value == 0) return;
if (legacyRegistry == address(0)                                   // ← ADD
    || Currency.unwrap(_liveKey.currency0) != address(0)
    || (legacyBuffer != 0 && legacyBufferAsset != address(0))) {
    relaunchETH += msg.value;
    return;
}
```

```solidity
// CauldronHook.sol:1893 — turning the feature off must not orphan the balance.
function setLegacyBuyback(address registry_, uint256 bps, uint256 threshold) external {
    if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry();
    if (bps > BPS) revert BadParam();
    if (registry_ == address(0) && legacyBuffer != 0) {
        //  The only reader of `legacyBuffer` is gated on `legacyRegistry`, so the
        //  balance must leave before the gate closes.
        uint256 stale = legacyBuffer;
        legacyBuffer = 0;
        _creditFor(legacyBufferAsset, stale);
    }
    legacyRegistry = registry_;
    ...
```

---

### [MEDIUM-03] the public `recoverLegs` retry made reachable today discards `quoteOut` into a slot with no exit

**Severity:** Medium
**Status:** Open
**File:** `contracts/solidity/cauldron/RedemptionExt.sol`
**Lines:** 732-735 (`recoverLegs`), 783-799 (`_recoverLegs` accounting), 847-858 (`sweepLegProceeds`)
**Related:** `contracts/solidity/CauldronRegistry.sol:290` (the new forwarder)

#### Description

Commit `8237167` split one function into two — an ungated teardown entry and a new
**public, permissionless** retry for a past generation — and added the registry forwarder
that makes the retry reachable for the first time:

```solidity
// RedemptionExt.sol:732
function recoverLegs(uint256 gen) public returns (uint256 quoteOut, uint256 tokenOut) {
    if (gen == 0 || gen >= currentGeneration) revert CannotClaimCurrentGen();
    return _recoverLegs(gen);
}
// CauldronRegistry.sol:290
function recoverLegs(uint256) external returns (uint256, uint256) { _forwardToExt(); }
```

The gate is correct and on the right side (the registry forwards by `delegatecall`, so the
facet body runs on registry storage; `recoverLegsAtTeardown` deliberately has no forwarder
and I confirmed the registry declares `receive()` and **no** `fallback()`, so it is
genuinely unreachable externally). The problem is the accounting, not the authority.

`_recoverLegs` splits recovered quote two ways:

```solidity
// RedemptionExt.sol:791-798
if (l.quote == matchQuote) {
    quoteOut += q;                          // returned to the caller. Nothing else.
} else if (q > 0) {
    legProceeds[l.quote] += q;              // booked, and therefore sweepable
    emit LegProceedsBooked(gen, l.quote, q);
}
```

`quoteOut` is a *return value*, not a ledger entry. At teardown that is right — the
registry adds it to `ethRecovered` and passes it to `PoolOps.seedFunding`. Through the new
public retry, nothing consumes it: the assets land in the registry's custody and the
return value is discarded. And `sweepLegProceeds` — the only exit — reads only the
mapping:

```solidity
// RedemptionExt.sol:847
function sweepLegProceeds(address asset, address to) external onlyOwner returns (uint256) {
    amount = legProceeds[asset];
    if (amount == 0) revert NoBalance();
```

So the matching-quote half of a retried recovery is permanently unreachable. The
`tokenOut` side is the dead generation's own token and is economically irrelevant; the
quote side is not.

#### Impact

The documented recovery path recovers funds into a dead end. The narrow part is
reachability: the leg's `quote` must equal the *primary pool's* `currency0`
(`matchQuote`, line 783), and legs are normally created by rotating *into* a different
asset. It becomes reachable when the guild rotates a side leg back into the launch quote —
which `rotateSliceFrom` permits, since `fromLeg > 0` with a destination key whose
`currency0` is the primary's quote is a legal merge/rebalance, and
`RedemptionExt.sol:307-318` names exactly that as the reason `fromLeg` exists. Combine
that with the per-leg `try/catch` failing once (the only reason the retry exists at all)
and the value is locked with no privileged exit.

#### Recommendation

Book it. `_recoverLegs` should not decide the disposition; the caller should, because only
the caller knows whether it is going to consume the return value.

```solidity
function recoverLegs(uint256 gen) public returns (uint256 quoteOut, uint256 tokenOut) {
    if (gen == 0 || gen >= currentGeneration) revert CannotClaimCurrentGen();
    (quoteOut, tokenOut) = _recoverLegs(gen);
    //  ── THE RETRY HAS NO SEEDING TO FEED (audit M-03) ─────────────────────
    //  At teardown `quoteOut` is added to `ethRecovered` and seeds the newborn.
    //  Here nothing consumes it, and `sweepLegProceeds` reads only `legProceeds`
    //  — so an unbooked recovery is a recovery into a slot with no exit. Book it.
    if (quoteOut > 0) {
        address a = Currency.unwrap(generationPoolKey[gen].currency0);
        legProceeds[a] += quoteOut;
        emit LegProceedsBooked(gen, a, quoteOut);
    }
}
```

`recoverLegsAtTeardown` keeps the raw return and stays as it is. Consider also asserting
in a test that after `registry.recoverLegs(pastGen)` the sum of
`legProceedsOf(asset)` over the assets touched equals the registry's balance delta —
that is the invariant this finding violates.

---

### [LOW-01] the surtax jitter can still be ground down to the published floor, because the rate is a public view and `jitter` only ever adds

**Severity:** Low
**Status:** Open
**File:** `contracts/solidity/cauldron/SurtaxLib.sol`
**Lines:** 54, 97-104
**Related:** `contracts/solidity/CauldronHook.sol:1441` (`snipeSurtaxBps` is `public view`)

#### Description

This is the *incomplete-fix* half of a KNOWN item, not a re-report. `69dc15d` removed the
live tick from the jitter seed, which correctly killed the same-transaction steer (a probe
swap ahead of the real one). What remains:

```solidity
// SurtaxLib.sol:97-104
uint256 rnd = uint256(keccak256(abi.encodePacked(
    blockhash(block.number - 1), PoolId.unwrap(id), block.number, block.prevrandao
))) % (maxBps + 1);
uint256 jitter = (rnd * remaining) / window;
uint256 total = decayed + jitter;
```

Every term is fixed for the whole of block N and knowable *before* a transaction in block
N executes: `blockhash(N-1)` is published when N-1 closes, `block.number` is N, and L-02
already records that `prevrandao` is a constant on Arbitrum/Orbit. The hook exposes the
result as `snipeSurtaxBps(PoolId)`, `public view` (`CauldronHook.sol:1441`). A sniper
therefore does not need to predict the jitter — it can *read* it and abort:

```solidity
function snipe(PoolId id, uint256 acceptBps) external {
    if (hook.snipeSurtaxBps(id) > acceptBps) revert TooExpensive();  // costs gas only
    poolManager.unlock(...);                                        // else buy
}
```

Because `jitter >= 0` and the fix changed `max(decayed, jitter)` to `decayed + jitter`,
`decayed` is now a hard *floor* on the rate rather than the whole of it. The sniper retries
until `rnd` is small: `rnd` is uniform on `[0, maxBps]`, so `P(jitter < 5% of decayed's
scale) ~= 5%` per block — roughly 20 cheap reverts on an L2 with sub-second blocks. The
"cheap block" the comment says is unknowable at submission is in fact selectable by
polling.

I am rating this Low, not Medium: the outcome is the *deterministic* `decayed` curve,
which is the protocol's own published anti-sniper schedule, so the fix has not made
anything worse and the mechanism still works against unsophisticated snipers. But the
jitter's stated purpose — "a sniper can't pick a guaranteed-cheap block" — is not
delivered, and the comment at lines 76-83 should not be relied on as if it were.

#### Recommendation

Jitter cannot be both readable-before-execution and unavoidable. Pick one:

```solidity
//  Option A (preferred, no new surface): make the ABORT expensive instead of the
//  jitter unpredictable — the anti-sniper window is short, so a per-address
//  attempt counter inside the window is enough to price retrying.
//  Option B: commit to the jitter at pool-init time over a value the sniper
//  cannot observe before its own transaction lands, e.g. fold in
//  `poolInitBlock[id]` AND the pool's cumulative swap count (hook storage the
//  sniper's own probe would have to move, making a probe self-defeating).
//  Option C: accept it, and say so — replace the "unknowable at submission"
//  comment with "the floor is `decayed`; jitter taxes only callers who do not
//  pre-check", which is what the code does.
```

Whichever is chosen, `snipeSurtaxBps`'s `public view` visibility is the load-bearing part;
if the jitter is meant to be unavoidable, that getter must not serve it.

---

### [LOW-02] `renounceOwnership`'s guard reports the wrong error to a non-owner on three contracts

**Severity:** Low
**Status:** Open
**File:** `contracts/solidity/cauldron/CauldronBase.sol:464`, `cauldron/CauldronGovernor.sol:195`, `CauldronHook.sol:1747`
**(For contrast, correct on:** `PerpEngine.sol:450`, `PerpMarkSource.sol`, `LaunchSniper.sol`, `MigrationVesting.sol` — all `public pure override` with no modifier.)

#### Description

Three of the seven renounce guards keep OpenZeppelin's modifier:

```solidity
function renounceOwnership() public view override onlyOwner { revert RenounceDisabled(); }
```

`onlyOwner` runs first, so a non-owner receives `OwnableUnauthorizedAccount(caller)` — the
error that means *"you are not allowed to do this"* — for a function nobody is allowed to
do. The four contracts fixed in the later commits dropped the modifier and are
unambiguous. The security property (no path zeroes the owner; `transferOwnership(0)`
reverts `OwnableInvalidOwner` upstream) holds in both forms; only the diagnosis differs,
and this repo has spent real effort today on exactly that distinction ("failing loud on an
unrecognized selector", `hasClaimed`).

#### Recommendation

```solidity
// CauldronBase.sol:464, CauldronGovernor.sol:195, CauldronHook.sol:1747
function renounceOwnership() public pure override { revert RenounceDisabled(); }
```

`pure` also drops the `SLOAD` of `_owner` that `onlyOwner` performs — a few bytes back on
two contracts sitting on the EIP-170 ceiling.

---

### [INFO-01] `PerpEngine.observations` lost its public getter — an ABI removal, not just a size saving

**File:** `contracts/solidity/cauldron/PerpEngine.sol:279`
`Observation[OBS_CARDINALITY] public observations` became `internal` in `539d26d` ("drop
an unread getter"). That removes `observations(uint256)` from the engine's ABI. The claim
that it is unread was not re-verified by me for the indexer and the analytics surface (I
checked the Solidity tree only, where it is indeed unread). Confirm against `indexer/` and
any external integrator before deploy; the ring is still readable from raw storage, so the
mitigation for a surprised consumer is an `eth_getStorageAt` shim, not a redeploy.

### [INFO-02] `legacyBufferAsset` is written even when nothing is buffered

**File:** `contracts/solidity/CauldronHook.sol:1397`
Inside the `_routeEthFee` carve, `legacyBufferAsset = _feeAsset` executes before
`legacyBuffer += fromFloor + fromRelaunch`, and that sum can be zero (both `wantFloor` and
`wantRelaunch` may already be exhausted). The result is a non-zero
`legacyBufferAsset` describing an empty buffer. Harmless today — every consumer
(`_maybeLegacyBuyback:1017`, `fundLegacyBuffer:1157`, the carves at 1389/1413) guards on
`legacyBuffer == 0` first — but it makes the public getter lie to an indexer, and the next
consumer added will not know to check the amount first. Move the assignment inside an
`if (fromFloor + fromRelaunch > 0)`.

### [INFO-03] `RECOVER_LEGS` selector change is a deploy-ordering dependency

**File:** `contracts/solidity/CauldronRegistry.sol:65`
`bytes4(keccak256("recoverLegs(uint256)"))` became
`bytes4(keccak256("recoverLegsAtTeardown(uint256)"))`. The registry finds this selector by
`delegatecall` into whatever `redemptionExt` points at, and a wrong selector fails
*silently* here by design (the comment at :60-64 says so). A registry from this commit
wired to a facet from before it would strand every rotated leg at teardown with no error.
Pin it: the deploy scripts should assert
`RedemptionExt(ext).recoverLegsAtTeardown.selector` exists, or `F20_FacetReachability`
should assert the constant equals the facet's function selector rather than only that
routing works. `6459b85` is the fourth instance of this exact class in the tree; a
compile-time binding (an interface call instead of a hand-rolled constant) would end it.

---

## Categories examined and found clean

Stated with the evidence, because a clean category is a result.

**Access control on every gate added today (SC-01).** I enumerated all 14
`external`/`public` functions added in the range
(`git diff … | grep -E "^\+.*function .*(external|public)"`) and checked each one's
authority:
- `renounceOwnership` × 7 — all revert unconditionally; `transferOwnership(address(0))`
  reverts `OwnableInvalidOwner` in OZ, so no path zeroes an owner. LOW-02 is cosmetic.
- `CauldronRegistry.recoverLegs(uint256)` forwarder — the real gate is on the facet
  (`gen >= currentGeneration → CannotClaimCurrentGen`), which is the correct side: the
  registry `delegatecall`s, so the facet body reads registry storage.
- `RedemptionExt.recoverLegsAtTeardown` — ungated, and its stated access control ("no
  registry stub forwards it") **holds**: I verified `CauldronRegistry` declares
  `receive()` at :572 and no `fallback()`, and no stub carries that selector. A direct call
  to the deployed facet runs on the facet's own blank storage and recovers nothing.
- `RedemptionExt.claimByBurnUpTo` — the gate moved *with* the body (facet line 658
  carry the identical `claimGate`/`perpEngine` test); the registry stub is a pure
  forwarder, so authority is unchanged. Calling the facet directly is inert for the same
  blank-storage reason (`currentGeneration == 0` → `CannotClaimCurrentGen`).
- `CauldronGachaRouter.rescueToken` — `onlyOwner`, transfers the router's *own* balance
  (`_safeTransfer`, not `transferFrom`), so it cannot reach a user's allowance; the router
  holds nothing between transactions.
- `PerpVault.hasQuoteStake` (:179) — `view`, no authority.

**The break-glass cannot be stranded.** `CauldronRegistry.emergencyAdmin` is `immutable`
(:128, set in the constructor with a `msg.sender` fallback at :171), and `onlyEmergency`
(:363) tests it directly rather than through `owner()`. Nothing in this range touches it,
`timelocked` (:372), `armEmergency` (:420), `rescueSeeder` (:339),
`setRedemptionPaused` (:453) or `emergencyWithdrawLP` (:469). The renounce guards *protect*
the owner-side levers rather than threatening the emergency side. `TreasuryGovernor`'s
guardian gained a zero check (:625) and cannot be nulled.

**The other three new state variables do not desynchronise.**
- `legacyBufferAsset` — writers: `fundLegacyBuffer:1161`, `_routeEthFee:1397` and `:1415`.
  Readers: `_maybeLegacyBuyback:1028`, `legacyBuyStep:1102`, the two carves. Every reader
  short-circuits on `legacyBuffer == 0`, so a stale asset label cannot mis-denominate a
  live balance. Fresh deploy: both zero, and native is `address(0)`, which is the correct
  initial pairing. Not a proxy, so no upgrade case. (INFO-02 is a hygiene note on this.)
- `ringArmedAt` (`PerpEngine.sol:302`) — written only in the ring reset (:1106); read only
  in `_guardOpen` (:1355). On a **fresh deploy** it is 0, so
  `block.timestamp < 0 + twapWindow` is false and the gate is open — it does not dead-end
  a new generation, which was my first hypothesis and is wrong. It correctly closes
  leverage for `twapWindow` after a rotation wipes the ring.
- `_bench` (both governors) — `_benchRecord` has the `if (b == id) return;` de-duplication
  in **both** copies (`CauldronGovernor.sol:434`, `TreasuryGovernor.sol:531`), which I
  checked in the current files after a filtered diff had hidden it; without it a single
  proposal could have colonised all eight slots. Entry is priced in votes, dead/consumed
  slots read as weight 0 and are reclaimed first, and `winner()`/`_recomputeLeader` read
  `forVotes`/`votes` live rather than a cached entry weight. `TreasuryGovernor` records
  only on `support == true`, which matches `_passed`'s requirement. Appended after the last
  prior variable in both, so no slot moves.

**`InventoryMigrationShortfall`** (`PerpSwapLib.sol:135,164`) — emit-only, no state, and
the arithmetic `oldBal - migratedIn` is guarded by `migratedIn < oldBal`. Emitting rather
than reverting is correct here: `migrateInventory` runs inside relaunch's `try/catch`
(`CauldronRegistry.sol:1115`), so a revert would re-create the B-05 armed-on-a-dead-
generation shape.

**The arithmetic called out in the brief.**
- Gacha churn: `ethBal -= inE` (`CauldronGachaRouter.sol:491`) and `tokBal -= inG` (:509)
  both debit what the pool consumed, with checked arithmetic as the guard against a pool
  over-reporting; the remainder rides into the next loop and exits via `_payQuote`. The
  new `rescueToken` gives the ERC20 side the exit the native side already had.
- `PoolOps` vault sweep: returning `0` for `vaultSwept` in branches 1 and 3 (:1078, :1088)
  and the real figure only in branch 2 (:1084) is self-consistent — branch 2 is the only
  one that folds `vaultSwept` into the `totalETH` it returns, so `crystallizeCollection`'s
  `mulDiv(swept, activeBase, totalETH)` now takes numerator and denominator from the same
  addition. I checked the branch bodies, not just the returns.
- `LegacyBuyLib` `encumbered` clamp (:82-89): `free = bal - encumbered` with
  `encumbered = relaunchETH | relaunchAsset[q]`. `amt` is derived from `legacyBuffer`
  alone, so the clamp binds only on an accounting shortfall and cannot be the thing
  standing between a buy and `proposerOwed`'s native liability. The `9486/10000` sqrt
  bound is a real price limit and the `MIN_SQRT_LIMIT` floor keeps it valid;
  `if (got == 0) revert NoOutput()` rolls back the caller's `legacyBuffer = 0`.
- `QuoteRotator` minOut floor: `NotPriceable` fails safe, and it does **not** dead-end —
  `_usdLive` `staticcall`s `usdPerRawUnit(address)`, which I confirmed exists as
  `external view` at `QuoteOracle.sol:202`, so a wired, working oracle returns a real
  factor and the rotation proceeds. Computing the floor before the swap is correct (it
  depends only on `amountIn`). The `token.code.length == 0` guard in `_safeTransfer`
  (:743) cannot catch native: both call sites (`_settle:725`, `_send:736`) branch on
  `cur == address(0)` first.
- `PerpVault.claimPendingEth`: the write-down now persists
  (`if (owed == 0) { emit ClaimEth(msg.sender, 0); return 0; }`, :327) and `pendingEth`
  stays equal to the sum of `pendingEthOf` across the haircut path, so `hasQuoteStake` is a
  faithful reading of the side.

**`TreasuryGovernor.execute`'s new gates** (:582-583) do not strand a legitimate caller:
`lastEnvelopeAt != 0` skips the first-ever execute, `envelope.active && now < expiry`
mirrors `propose` (:437-438) exactly, and a guardian `cancel` clearing `active` without
clearing `lastEnvelopeAt` is the pre-existing `propose` behaviour rather than a new asymmetry.
The `allowance`/`noteMoved` migration-budget split (:767, :844-849) does what it
claims: with `maxTotalBps >= BPS_ONE` a side-pool slice consumes `movedBps` but never
`movedPrimaryBps`, so the migration mandate is the one budget a side slice cannot spend,
and the envelope's deactivation test follows the same meter.

**`MigrationVesting`'s new caps** are the right shape: `vestBatch` is permissionless but
`_pullAndVest` takes `min(balance, allowance)` — the *whole* approved amount — so a
stranger cannot dust an array one grant at a time, and the `MAX_BATCH_GRANTS = 32`
sub-cap against `MAX_GRANTS = 64` reserves half the array for the beneficiary's own
`vest()`. The third-party path `continue`s rather than reverting, so one capped holder
cannot kill a keeper batch.

**`FeeRouteLib`'s codeless-recipient checks** (:131, :149, :219) are on the right side of
the call in all three places; the `_fundGuild` variant checks after the `call` (necessary —
the `call` is what it is judging) and an allowance granted to a codeless address is inert.

### Refuted — do not re-raise

Three candidates I developed and then killed against the current source. Recorded so the
next pass does not spend the same budget:

1. **"`CauldronGovernor._benchRecord` lacks the `b == id` de-duplication, so one proposal
   can occupy all eight slots."** False. It is at `CauldronGovernor.sol:434`. A
   comment-stripping diff filter hid it; the current file has it.
2. **"`ringArmedAt == 0` on a fresh deploy blocks every `open` until `twapWindow`
   elapses."** Backwards. `0 + twapWindow` is in 1970; the comparison is false and the gate
   is open.
3. **"`QuoteRotator`'s new `NotPriceable` makes rotation unrunnable, because `_usdLive`
   staticcalls a function that does not exist."** It exists:
   `QuoteOracle.usdPerRawUnit(address) external view`, :202.

---

## Gas Optimizations

Out of scope for this pass and not hunted. One is a free by-product of LOW-02: dropping
`onlyOwner` from the three `renounceOwnership` overrides removes an `SLOAD` and a few bytes
from two contracts that are on the EIP-170 ceiling.

---

## Recommendations

1. **Fix MEDIUM-01 before deploy.** It is the only finding an unprivileged party can
   trigger deliberately, permanently, and for the cost of one settlement, and it defeats a
   guard landed in this same range. Redenominating `payoutOwed` is the correct fix;
   an owner-gated stale-credit sweep is the minimum.
2. **Fix MEDIUM-02 and MEDIUM-03.** Both are two-to-six-line changes and both are
   "value with no exit at any privilege level" — the class this branch has spent the day
   closing. Leaving either open leaves the class open.
3. **Add the two invariant tests these findings imply**, not just regression PoCs:
   `payoutOwedTotal == Σ payoutOwed` after every settlement path, and
   `Σ legProceedsOf(asset) == registry balance delta` after `recoverLegs`.
4. **Bind the `RECOVER_LEGS` selector at compile time** (INFO-03). Four instances of the
   same facet-wiring defect class in one range is a structural signal, not four accidents.
5. **Re-check the `observations` ABI removal against the indexer** (INFO-01) before
   deploy; it is cheap to confirm and expensive to discover afterwards.
