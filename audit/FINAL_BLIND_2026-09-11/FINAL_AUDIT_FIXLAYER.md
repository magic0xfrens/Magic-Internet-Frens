# Smart Contract Security Audit Report — THE FIX LAYER
Magic Internet Frens / Cauldron

## Executive Summary

**Project:** Cauldron (Magic Internet Frens)
**Auditor:** Claude Opus 5 (solidity-auditor skill), final pre-redeploy pass
**Date:** 2026-09-12
**Scope commit range:** `6459b85..HEAD` on `redteam/2026-09-11` — the **thirteen contract commits that landed after the last audited tree** (`ddd7284`, `699af92`, `c3f5229`, `f42ca1a`, `c886f90`, `e6237a3`, `6f7ef41`, `1eff1d2`, `2dd5169`, `1ab6226`, `e17b6aa`)
**Solidity:** ^0.8.26 (checked arithmetic; no overflow findings raised outside `unchecked`)

### Overview

Every commit in scope is a *fix for a prior audit finding*, i.e. code written under
time pressure against a known hole. The review therefore hunted the failure modes
that class of change invites: a revert turned into a continuation (or the reverse),
a guard whose satisfiability depends on a third party, unit-vs-value confusion in
newly-scaled thresholds, and authority splits that open a permissionless window.

The two heaviest commits — `1eff1d2` and `2dd5169`, the perp quote-rotation sweep
and the `retirePayout` split authority — account for both of the top findings. The
oracle two-timestamp model (`c886f90`), the `legProceeds` retry booking (`e6237a3`),
the governor snapshot (`6f7ef41`), the vesting checked transfer (`f42ca1a`) and the
`sweepLegacyReserve` revert (`699af92`) are **clean** as far as I could drive them;
the detail of how hard I looked is in §Clean.

### Risk Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 1 |
| Medium   | 2 |
| Low      | 2 |
| Info     | 1 |

### Key Findings

- **F-01 (High)** — one dust token-side vault share permanently vetoes the perp
  engine's quote adoption *and* its vault replacement. This is the X8-01
  "permanent freeze" shape re-opened through the token side, with no governance
  escape, at negligible attacker cost.
- **F-02 (Medium)** — `retirePayout` became permissionless while the quote
  diverges and still ignores a failed push, so anyone can permanently destroy a
  third party's escrowed payout during the window in which that recipient happens
  to be unable to receive.
- **F-03 (Medium)** — the new `_q()`/`quoteUnit` scaling converts *units*, not
  *value*: on a 6-decimal quote the dust filter, the insurance circuit breaker and
  the leverage tiers all lose ~12 orders of magnitude of economic meaning and
  effectively switch off.

---

## Scope

| Contract | Lines | Change in scope |
|----------|-------|-----------------|
| `cauldron/PerpEngine.sol` | 2041 | rotation sweep, `strandedToken`, `_q()` scaling, `retirePayout` split authority, `_tryPush` |
| `cauldron/PerpSwapLib.sol` | 280 | `unitOf`, `tryTransfer*`, `migrateInventory` |
| `cauldron/QuoteOracle.sol` | 374 | `at`/`triedAt` two-timestamp cache |
| `cauldron/QuoteRotator.sol` | 790 | `_usd` deleted, `arbStep` pre-flight `NotPriceable` |
| `cauldron/RedemptionExt.sol` | 900 | `_bookLegProceeds` on the retry path |
| `cauldron/TreasuryGovernor.sol` | 949 | `snapshot: block.number - 1` |
| `cauldron/FeeRouteLib.sol` | 252 | codeless-guild check moved before the branch |
| `cauldron/MigrationVesting.sol` | 375 | checked `transfer`, `TransferFailed` |
| `CauldronHook.sol` | 2545 | `_maybeLegacyBuyback` drain, `sweepLegacyReserve` revert |
| `deploy/DeployLaunchpad.s.sol` | — | guardian-gated call, mock quote watermark |

Read as source at HEAD, not as diffs alone. `c3f5229` (surtax) is comment-only and
was confirmed as such.

---

## Findings

### F-01 — HIGH — One dust token-side vault share permanently bricks the perp engine's quote adoption and its vault replacement

**Location:** `contracts/solidity/cauldron/PerpEngine.sol:1208` (`syncGeneration`),
`contracts/solidity/cauldron/PerpEngine.sol:1978` (`setVault`),
`contracts/solidity/cauldron/PerpVault.sol:167-169` (`hasStakers`)
**Tag:** DERIVED (traced concretely; no Foundry PoC — the claim is two literal lines)

**Description.** `1eff1d2` replaced the unsatisfiable `plv | tokYieldEth |
insuranceEth | payoutOwedTotal == 0` guard (red-team X8-01) with an ownership
question. The question it asks is the wrong one:

```solidity
// PerpEngine.sol:1207-1208
if (payoutOwedTotal != 0) revert VaultStaked();
if (vault != address(0) && IPerpVaultStake(vault).hasStakers()) revert VaultStaked();
```

and `hasStakers()` covers **both** sides of the vault:

```solidity
// PerpVault.sol:168
return (ethShares | tokShares | pendingEth | pendingTok) != 0;
```

The vault's own header documents the opposite contract, and documents *why*:

```
// PerpVault.sol:174-178
//  {PerpEngine.syncGeneration} asks this before adopting a NEW quote. The
//  token side is deliberately excluded: `tokShares`/`pendingTok` are counts
//  of the generation's TOKEN, which a quote rotation does not redenominate,
//  and blocking on them would make rotation unrunnable for no safety gain.
```

`hasQuoteStake()` (`PerpVault.sol:179`) exists, is declared in the engine's own
interface (`PerpEngine.sol:48`), and **has zero callers** — verified by grep across
`cauldron/`, `*.sol` and `test/`.

A token-side stake is not residue and not orphaned, so `hasStakers()` correctly
reports `true` for it — and there is no way to make it false without the staker's
cooperation. `setVault` (`:1978`) is gated on the *same* predicate, so governance
cannot even unwire the vault to escape. `withdrawToken` is the only lever and it is
`msg.sender`-keyed.

**Impact.** While the guard holds, `quote` stays on the old asset while
`registry.generationQuote(gen)` names the new one, and `_isDead()` (`:1460-1461`)
reads that divergence as death. Consequences, all for the remainder of the
generation:

- `_guardOpen` (`:1438`) reverts `TokenDead()` — **no new leverage, at all**;
- the entire book is permissionlessly force-closeable and stays closed;
- the engine cannot be re-pointed at the new pair, so perps are off until the next
  relaunch;
- `setVault` is also vetoed, so a *buggy* vault cannot be replaced either — the
  exact lever R-09 was filed to restore.

Governance cannot rotate back out of it on the shipped path: `address(0)` means
both "native" and "no envelope", so a treasury that has rotated away from ether
cannot rotate back (prior finding *rotation-is-one-way*).

**Exploit sequence.**
1. A quote rotation is scheduled/announced (governance action, publicly visible).
2. Attacker buys a small amount of the generation token and calls
   `PerpVault.depositToken(amount)` with just enough to mint ≥ 1 share
   (`PerpVault.sol:380`, `OFFSET = 1e6`, so `amount ≈ assetsTok()/1e6` suffices).
3. Attacker never withdraws. `tokShares != 0` forever.
4. The rotation completes. Every subsequent `syncGeneration()` call — it is
   permissionless, so honest keepers will try — reverts `VaultStaked()`.
5. `_isDead()` is now permanently true. Perps are dead for the generation, and
   `setVault` is dead with them.

No attacker is even required: the deploy script itself stakes
(`deploy/DeployPerp.s.sol:154` deposits `PLV_SEED_ETH`), and any ordinary token-side
LP reaches the same state by doing nothing wrong.

**Recommended fix.** Ask the question the vault's own header says is being asked,
and park — rather than zero — the one quote-denominated counter the token side owns:

```solidity
// PerpEngine.sol — new storage (next to strandedToken)
/// @notice Token-side yield accrued in a quote the engine has since left, keyed
///         by that asset. Claimable by the vault; never paid in the NEW quote.
mapping(address => uint256) public parkedTokYield;

// PerpEngine.sol:1207 — replace the two guards
if (payoutOwedTotal != 0) revert VaultStaked();
// The TOKEN side is not redenominated by a quote rotation, so it must not veto
// the adoption (PerpVault.sol:174-178). Only quote-denominated stake may.
if (vault != address(0) && IPerpVaultStake(vault).hasQuoteStake()) revert VaultStaked();

// PerpEngine.sol:1218-1219 — do not confiscate token-side yield
address oldQuote = quote;
if (tokYieldEth != 0) {
    parkedTokYield[oldQuote] += tokYieldEth;   // still owed, still in the OLD asset
    tokYieldEth = 0;                           // but never payable in the NEW one
}
uint256 sweep = plv + insuranceEth;
plv = 0; insuranceEth = 0;
```

plus a vault-only drain for the parked pot, denominated explicitly:

```solidity
function withdrawParkedTokYield(address asset, uint256 amount, address to)
    external onlyVault notNested nonReentrant
{
    uint256 owed = parkedTokYield[asset];
    if (amount > owed) revert PlvInsufficient();
    parkedTokYield[asset] = owed - amount;
    if (asset == address(0)) { (bool ok,) = to.call{value: amount}(""); if (!ok) revert EthSend(); }
    else _safeTransfer(asset, to, amount);
}
```

If EIP-170 cannot afford the parked-pot path, the minimum acceptable change is the
`hasQuoteStake()` swap plus an explicit, logged write-off of `tokYieldEth` — a
bounded, one-time loss of accrued short-side reward is strictly preferable to a
permanent, attacker-triggerable shutdown of the whole engine. Also delete the
stale premise in `test/attacks/X3c_StaleQueueSurvivesRotation.t.sol:58`.

---

### F-02 — MEDIUM — Permissionless `retirePayout` lets anyone permanently destroy a third party's escrowed payout

**Location:** `contracts/solidity/cauldron/PerpEngine.sol:1612-1623`
**Tag:** DERIVED

**Description.** `2dd5169` split `retirePayout`'s authority: owner-only when the
quote has converged, **permissionless while it has not**.

```solidity
// PerpEngine.sol:1612-1623
function retirePayout(address to) external {
    uint256 amount = payoutOwed[to];
    if (amount == 0) revert ZeroValue();
    if (quote == registry.generationQuote(registry.currentGeneration())) _checkOwner();
    payoutOwed[to] = 0;                     // effects before interaction
    payoutOwedTotal -= amount;
    _tryPush(to, amount, false); // retired either way — never re-arm the counter
}
```

`_tryPush`'s return is **discarded**. The claim is destroyed whether or not the
value moved. Combined with the permissionless branch, that is a
**burn-someone-else's-escrow primitive** available to any address for as long as
the engine is diverged — and by F-01 that window can last the whole generation.

The recipient's own `claimPayout()` (`:1632`) is *strictly safer*: it routes through
`_pushQuote`, which reverts on failure, so a transiently-unpayable recipient keeps
its claim. `retirePayout` is the only path that can lose it.

Divergence is not attacker-created (it follows a governance rotation), which is
what keeps this out of High. But the recipient's *transient* inability to receive
very much is attacker-observable and attacker-timed.

**Impact.** Permanent loss of an individual trader's, keeper's or fee sink's
escrowed settlement proceeds, chosen and timed by an unprivileged third party. The
wei stays in the engine as residue owned by nobody. The `dividend` sink is the
largest routine occupant of `payoutOwed` — its `receive()` writes 3+ slots
(`MiFrensDividend.sol` receive: `totalDeposited`, `accPerShare`, `residual`, a log)
and so routinely overruns the 30k budget `_payOut` forwards — so the amounts here
are not dust.

**Exploit sequence (ERC20-quoted book, the realistic case).**
1. Governance rotates the generation quote; `syncGeneration()` has not yet adopted
   it (or cannot, per F-01). `quote != generationQuote` → permissionless branch.
2. Victim `V` is owed `payoutOwed[V]` in the old ERC20 quote and is currently
   unable to receive it — blacklisted by that token, or a contract paused for an
   upgrade. `PerpSwapLib.tryTransfer` returns `false` for `V`.
3. Attacker calls `retirePayout(V)`. `payoutOwed[V]` → 0, `payoutOwedTotal`
   decremented, `_tryPush` returns `false` and is ignored.
4. `V` is delisted / unpaused an hour later. `claimPayout()` reverts
   `ZeroValue()`. The funds are unrecoverable at any privilege level.

**Recommended fix.** Keep the liveness promise for recipients that *can* be paid;
keep the write-off privileged.

```solidity
function retirePayout(address to) external {
    uint256 amount = payoutOwed[to];
    if (amount == 0) revert ZeroValue();
    bool converged = quote == registry.generationQuote(registry.currentGeneration());
    if (converged) _checkOwner();
    payoutOwed[to] = 0;                     // effects before interaction
    payoutOwedTotal -= amount;
    //  A PERMISSIONLESS CALLER MAY UNBLOCK A ROTATION, NOT BURN A CLAIM. The
    //  full-gas retry is the whole point of this entry, so a recipient that can
    //  be paid is paid and the counter is freed either way. One that refuses at
    //  full gas is a WRITE-OFF, and only the owner may take that decision.
    if (!_tryPush(to, amount, false) && !converged) revert EthSend();
}
```

This is a deliberate, documented narrowing of
`S01_PerpQuoteDeadlock.test_invariant_divergedEngineIsPermissionlesslyRecoverable`:
permissionless recovery still works for every recipient that is payable, which is
every case the invariant was written for; a recipient that reverts at full gas now
needs the timelock. Update that test's comment accordingly rather than leaving the
contradiction in place.

---

### F-03 — MEDIUM — `_q()` rescales UNITS, not VALUE: three safety thresholds silently switch off on a 6-decimal quote

**Location:** `contracts/solidity/cauldron/PerpEngine.sol:568-571` (`_q`),
`:1243` (`quoteUnit = PerpSwapLib.unitOf(newQuote)`), consumers at `:771`
(`maxLeverage` tiers), `:860`/`:897` (`minCollateral` dust filter), `:868`/`:906`
(`insuranceFloor` circuit breaker), `:2013` (`skimInsurance` protected floor)
**Tag:** DERIVED

**Description.** `1eff1d2` correctly identified that an absolute wei constant
compared against a quote-denominated amount is a denomination bug, and fixed the
*dimension*:

```solidity
// PerpEngine.sol:568-571
function _q(uint256 wei18) internal view returns (uint256) {
    uint256 u = quoteUnit;
    return u == 1e18 ? wei18 : (wei18 * u) / 1e18;
}
```

But the constants being rescaled are **value** statements, not unit statements.
`tierDepthWei = [25 ether, 100 ether, 300 ether]` (`:482`) means "≈ $80k / $320k /
$1M of pool depth". `_q` turns that into `[25e6, 100e6, 300e6]` raw units of a
6-decimal quote — i.e. **$25 / $100 / $300**. Likewise `minCollateral = 0.003 ether`
(≈ $10) becomes `3000` = $0.003, and `insuranceFloor = 0.05 ether`
(`deploy/DeployPerp.s.sol:95`, ≈ $160) becomes `50000` = $0.05.

`PerpSwapLib.unitOf` (`PerpSwapLib.sol:37-44`) is correctly defensive about the
untrusted `decimals()` — reverting, absent, short-returning and `> 36` answers all
fall back to `1e18`, so **that** half of the brief's question 4 is clean. `d == 0`
is accepted and yields `u = 1`, which drives every threshold above to exactly `0`.

**Impact.** On any non-ETH-quoted generation with `decimals() < 18`:

- **leverage tiering is bypassed.** `depth >= _q(tierDepthWei[i])` is true for the
  top tier at essentially any liquidity, so `maxLeverage()` returns
  `maxLeverageCeiling` in a paper-thin pool. That defeats the stated design ("leverage
  auto-capped by active-ETH depth", `:69-70`) and raises per-position bad-debt risk
  precisely where slippage is worst.
- **the dust filter is off** (`_q(minCollateral) ≈ 0`). The contract's own comment
  at `:141-144` explains what that costs: position spam bloating the liquidation
  set and griefing the batch auto-liquidator. `MAX_OPEN_POSITIONS = 64` caps the
  blast radius, but 64 dust positions is exactly the L-2 gas-bar attack.
- **the insurance circuit breaker is off** (`insuranceEth < _q(insuranceFloor)` is
  effectively never true), and `skimInsurance`'s protected floor collapses to
  `riskMin` alone — reversing audit M-05.
- With `decimals() == 0` all three are *exactly* zero, not merely small.

Not a direct theft, and governance can retune every one of them
(`setTiers`, `setMinCollateral`, `setVaultLimits`) — hence Medium, not High. But
they are silently wrong from the instant of adoption, with no event and no revert.

**Recommended fix.** Rescale by **value**, using the oracle the protocol already
runs, and fail closed to the previous (native) behaviour rather than to zero:

```solidity
/// @dev Re-express an 18-decimal wei-written VALUE threshold in the live quote's
///      own units, at the quote's USD price. `_q` scaled the UNITS only, which
///      turned "25 ETH of depth" into "25 USDC of depth".
function _q(uint256 wei18) internal view returns (uint256) {
    uint256 u = quoteUnit;
    if (u == 1e18 && quote == address(0)) return wei18;
    // usdPerRawUnit is 1e18-scaled USD per RAW unit; both legs staticcall-guarded
    // and 0 on any failure, in which case we keep the unscaled figure (fails
    // CLOSED — the threshold stays at least as strict as the native one).
    uint256 pNative = _usdPerRawUnit(address(0));
    uint256 pQuote  = _usdPerRawUnit(quote);
    if (pNative == 0 || pQuote == 0) return wei18;
    return FullMath.mulDiv(wei18, pNative, pQuote);
}
```

If EIP-170 cannot afford an oracle read here (plausible — the engine has
single-digit bytes spare), the acceptable alternative is to make the thresholds
**explicitly re-armed at adoption** instead of derived: revert the adoption unless
governance has pre-registered a `quoteThresholds[newQuote]` tuple
(`minCollateral`, `insuranceFloor`, `tierDepthWei`) for the incoming asset. Deriving
them from `decimals()` alone cannot be made correct, because `decimals()` carries
no price.

---

### F-04 — LOW — The codeless-recipient guard `ddd7284` moved is still missing on the sibling floor leg

**Location:** `contracts/solidity/cauldron/FeeRouteLib.sol:68` (`routeSplit`),
`:105-111` (`_move`)
**Tag:** DERIVED

**Description.** `ddd7284`'s whole thesis is that on the **native** branch
`to.call{value: amount}("")` to a codeless address *succeeds and the ether really
leaves*, so reporting `true` makes the caller skip its `leftover` reserve fallback
and the money is gone with a success signal on it. That reasoning was applied to
`_fundGuild` (`:145`) and `_deliver` (`:168`). The floor leg was not:

```solidity
// FeeRouteLib.sol:67-70
if (toFloor > 0) {
    if (vault != address(0) && _move(asset, vault, toFloor)) emit FloorFunded(vault, toFloor);
    else leftover += toFloor;
}

// FeeRouteLib.sol:105-111
function _move(address asset, address to, uint256 amount) private returns (bool ok) {
    if (asset == address(0)) { (ok, ) = to.call{value: amount}(""); return ok; }
    ...
}
```

`_move` has no `to.code.length` check on either branch. `vault` is timelock-set —
exactly the same trust level and the same "misconfigured recipient" precondition
that `ddd7284` accepted as in-scope for the guild.

**Impact.** A non-zero but codeless `vault` (operator typo, or a not-yet-deployed
CREATE address) sends the floor share of **every** fee this hook routes to a
codeless address, permanently, while emitting `FloorFunded` and suppressing the
`leftover` → relaunch-reserve fallback that would have given the value an exit.

**Recommended fix.** One line, matching its two siblings:

```solidity
function _move(address asset, address to, uint256 amount) private returns (bool ok) {
    //  A CODELESS RECIPIENT IS NOT A SUCCESSFUL DELIVERY — the native branch
    //  SUCCEEDS and the ether really leaves (red-team X4c). Checked before the
    //  branch, as in {_fundGuild} and {_deliver}.
    if (to.code.length == 0) return false;
    if (asset == address(0)) { (ok, ) = to.call{value: amount}(""); return ok; }
    ...
}
```

---

### F-05 — LOW — A quote rotation books the entire live token inventory as "stranded" while simultaneously keeping it

**Location:** `contracts/solidity/cauldron/PerpEngine.sol:1117-1138`
**Tag:** DERIVED

**Description.** On a **quote rotation**, `gen == syncedGeneration`, so the
migration guard at `:1117` (`fromGen < gen`) is false and `migrateInventory` never
runs — `migratedIn` stays `0`. Nothing was migrated because nothing *needed* to be:
`newTok == syncedToken`. But the shortfall bookkeeping added by `1eff1d2` does not
know that:

```solidity
// PerpEngine.sol:1133-1138
uint256 unmigrated = plvToken > migratedIn ? plvToken - migratedIn : 0;
if (unmigrated != 0) {
    strandedToken[syncedToken] += unmigrated;
    emit TokenInventoryStranded(syncedToken, unmigrated, migratedIn);
}
plvToken = newInv;
```

So the whole live `plvToken` is booked to `strandedToken[syncedToken]` and announced
as stranded, while `plvToken` is immediately re-set to the same real balance on the
very next line. The books now claim the engine holds the inventory twice.

**Impact.** No fund impact today: `strandedToken` has **no reader anywhere** —
verified by grep across `cauldron/`, `*.sol`, `test/`, `deploy/`, `script/` (the
only two hits are the declaration at `:360` and the write at `:1135`). The harm is
a false `TokenInventoryStranded` event to operators and indexers on every rotation,
and a mapping that becomes a live double-count the moment anyone writes a recovery
path against it — which is precisely what it was added for.

**Recommended fix.** Only book a shortfall on a path that actually attempted a
migration:

```solidity
uint256 migratedIn;
bool migrated;
if (fromGen != 0 && fromGen < gen && syncedToken != address(0)) {
    migratedIn = PerpSwapLib.migrateInventory(address(registry), syncedToken, fromGen);
    migrated = true;
}
...
//  ONLY A GENERATION CHANGE CAN STRAND INVENTORY. A quote rotation keeps the
//  same token, so `migratedIn == 0` here means "nothing to migrate", not
//  "migration failed" — booking it would double-count the live inventory.
uint256 unmigrated = migrated && plvToken > migratedIn ? plvToken - migratedIn : 0;
```

---

### F-06 — INFORMATIONAL — `hasQuoteStake` is dead code and three comments document a contract the code does not honour

**Location:** `contracts/solidity/cauldron/PerpVault.sol:86-90`, `:101`, `:174-178`;
`contracts/solidity/cauldron/PerpEngine.sol:48`;
`contracts/solidity/test/attacks/X3c_StaleQueueSurvivesRotation.t.sol:16,58`

`PerpVault.hasQuoteStake()` has no production caller. Three separate comment blocks
state that `PerpEngine.syncGeneration` calls it; it calls `hasStakers()`
(`PerpEngine.sol:1208`). `X3c_StaleQueueSurvivesRotation` asserts the documented
premise (`require(!IQuoteStake(vaultAddr).hasQuoteStake(), "VaultStaked")`), so the
regression test for the H-2 stale-queue fix is now testing a predicate the engine
does not consult. Resolve alongside F-01 in whichever direction is chosen, and
delete the unreachable function if `hasStakers()` is kept.

---

## Clean — and how hard I looked

Per the brief's seven hunt categories:

1. **Reverts flipped to continuations and back.** `fundLegacyBuffer`
   (`CauldronHook.sol:1145`) never reverts and credits `relaunchETH`, which has a
   real exit via `releaseRelaunchETH` — `_creditFor` (`:1307`) confirmed. Its only
   caller is `RoyaltyRouter`, whose `receive()` forwards unconditionally, so the
   liveness argument holds. `claimPendingEth` returning `0`
   (`PerpVault.sol:327`) is reachable only when `_haircut` writes the claim to zero;
   the only state that zeroes backing is `plv == 0`, and `pendingEth != 0` blocks
   the rotation that would cause it (given `hasStakers`, F-01's *stricter* side).
   `migrateInventory` (`PerpSwapLib.sol:249`) emits rather than reverting, correctly
   — it runs inside relaunch's `try/catch`. The **new** revert,
   `sweepLegacyReserve` → `SendFailed` (`CauldronHook.sol:1208`), sits on the
   relaunch path (`CauldronRegistry.sol:1043` → `_flushLegacyAtRelaunch` →
   `PoolOps.materializeLegacy:1357`) with no `try/catch`, i.e. it is structurally a
   B-05-class wall — but it can only fire when `FeeRouteLib.send` returns `false`
   for the *dying generation's own* `CauldronToken`, which is protocol-minted,
   standard, and returns `true`. `gasCap = 0` means *no* cap (`FeeRouteLib.sol:196`),
   not a zero-gas call. Not raised; flagged here because the next person who makes
   a generation token non-standard turns it into a Critical.
2. **The perp sweep at the quote flip.** Traced. `hasStakers()` genuinely blocks the
   flip while any staker capital is present (that is F-01's other edge). No payout
   path can claim swept value: `plv`/`insuranceEth`/`tokYieldEth` are zeroed in the
   same statement, `openCount == 0` is required, and `_tryPush(treasury, sweep,
   true)` deliberately avoids `_payOut` so no old-asset figure survives to be paid
   in new-asset units. A failed push strands the value as inert residue, not a
   double credit. The engine cannot end with a live book and zero backing:
   `openCount == 0` is a precondition, and post-flip `plv == 0` makes any
   `leverage > 1` open revert `PlvInsufficient`. The 30k cap on the treasury push
   is survivable for the shipped sinks (an EOA, or `CauldronRegistry.sol:572`'s
   empty `receive()`).
3. **`retirePayout` transition.** See F-02. Divergence itself is **not**
   attacker-forcible — it requires `registry.generationQuote(gen)` to move, i.e. a
   completed governance rotation — and a payout that was about to be claimed is not
   stealable: `_tryPush` sends to `to` and only to `to`, chosen before any external
   code runs, and the effects land before the interaction so a reentrant call finds
   `payoutOwed[to] == 0`. The finding is the *discarded return value*, not the
   authority split.
4. **Decimals scaling.** See F-03. `unitOf`'s handling of the untrusted
   `decimals()` — reverting, missing, short-returning, `> 36` — is correct and
   fails to `1e18`. A token that *changes* its decimals is not re-read until the
   next adoption, which is the right cadence given `quoteUnit` is adopted with
   `quote`.
5. **The oracle's two-timestamp model.** Clean. `triedAt` cannot be pinned by a
   caller: the early return at `QuoteOracle.sol:337` fires *before* `triedAt` is
   written, so repeat calls never extend the throttle, and `triedAt` advances only
   on a genuine attempt. `usdPerRawUnit` returns `0` on every failure path
   (`:245-246`, `:249-252`, `:267-268`) and never reverts, so the
   `this.usdPerRawUnit(...)` self-call cannot bubble out of the cached reader. No
   consumer anywhere reads `cache(q).at` as "we looked recently" — grepped: the only
   cached-reader consumer is `CauldronHook._toUsd:742` (fail-open, volume/death,
   which *wants* the retained factor), and every value-moving reader in
   `QuoteRotator` now goes through `_usdLive` (`:439`, `:441`, `:574`, `:585`,
   `:586`) with the cached `_usd` deleted. Fail-open and fail-closed each get what
   they need.
6. **`legProceeds` booking on the retry path only.** Clean. The teardown entry
   reaches `_recoverLegs` through a *separate selector*
   (`CauldronRegistry.sol:65` `recoverLegsAtTeardown(uint256)`, delegatecalled from
   `_removeLiquidity` with no dispatcher stub), so it cannot be driven through
   `_bookLegProceeds`. Double recovery is impossible: `_recoverLegs` swap-pops each
   leg on success (`RedemptionExt.sol:834-835`), so a second `recoverLegs(gen)`
   finds an empty array. The sink is correct for both assets — `quoteOut` is keyed
   by `generationPoolKey[gen].currency0`, which is exactly the asset
   `_recoverLegs` aggregates into it (`:818`, `:828`).
7. **`block.number - 1` snapshot.** Clean, including on Orbit. Reads and
   checkpoint writes share one clock, and because `block.number` on an Orbit chain
   is the L1 number shared across many L2 blocks, `block.number - 1` excludes the
   *entire* current L1 window — strictly stronger than intended, never weaker. OZ's
   `_getVotes` precondition (`timepoint < clock()`) holds. `getPastTotalSupply` at
   `:887` uses the same snapshot, so quorum and power cannot disagree.

Also reviewed and clean: `MigrationVesting.claim`'s checked transfer
(`MigrationVesting.sol:286`) — `grt.released` is written before the transfer, so
reverting is what makes the rollback correct, and the token is always a
protocol-minted `CauldronToken` chosen by the registry, so no caller-supplied token
can grief a holder's other grants; `_maybeLegacyBuyback`'s folded wiring check
(`CauldronHook.sol:1014`, `:1044`) — the drain destination has an exit, and the
"unwired" and "wrong denomination" cases now share one meaning and one exit as
claimed.

Not re-raised (checked and refuted): `FeeRouteLib._fundGuild`'s allowance is
cleared on failure (`:151`) and fully consumed on success by
`MiFrensDividend.fundToken`'s pull, so no standing approval outlives the call.

---

## Redeploy verdict

**Nothing here forces a redeploy before launch. One finding forces a redeploy before
the first quote rotation.**

The reasoning, per finding:

| Finding | Contract | Reachable on the live Sepolia deployment? | Verdict |
|---|---|---|---|
| F-01 High | `PerpEngine` (immutable) | Only once `registry.generationQuote(gen)` moves — i.e. only after a **completed quote rotation**. Gen-1 is native and relaunch clamps the quote to native (B-05), so no rotation → unreachable. | **Redeploy `PerpEngine` before enabling quote rotation.** Not blocking an ETH-quoted launch. |
| F-02 Medium | `PerpEngine` | Same gate — the permissionless branch requires `quote != generationQuote`. | Ships with the F-01 redeploy. |
| F-03 Medium | `PerpEngine` | Requires a non-native generation quote, which today only arises via rotation. | Ships with the F-01 redeploy. Interim mitigation: retune `setTiers` / `setMinCollateral` / `setVaultLimits` in the same timelock batch as any rotation. |
| F-04 Low | `FeeRouteLib` (a **linked** library, address baked into `CauldronHook` bytecode) | Requires a misconfigured, codeless floor vault. | **Wait.** Fixing it changes the library address, which changes the hook's bytecode, which means a full hook/mine/redeploy of everything. Not worth it alone; fold into the next full redeploy. Operationally, verify `vault.code.length != 0` before any `setFeeRouter`/vault re-point. |
| F-05 Low | `PerpEngine` | Reachable on any rotation; no fund impact (dead mapping). | Ships with the F-01 redeploy. |
| F-06 Info | comments + one test | n/a | Fix in-tree now, no deploy. |

**Practical recommendation.** `PerpEngine` is independently redeployable — it is
wired by `hook.setPerpEngine(...)` and `PerpVault(engine, registry)` — so F-01/F-02/
F-03/F-05 can ship as one new engine + vault pair without touching the hook, the
registry or the mined hook address. Do that **before** the first `rotateSlice`
campaign, not before launch. If a quote rotation is already scheduled, F-01 is
launch-blocking for the perp subsystem, because a single dust `depositToken` by any
observer turns the rotation into a permanent perp shutdown with no governance
escape.

---

## Recommendations

1. Ship F-01 and F-02 together — they are the two halves of the same
   "guard/recovery must not depend on a third party" principle, and F-01 makes
   F-02's window unbounded.
2. Add a regression test per finding, and fix
   `X3c_StaleQueueSurvivesRotation.t.sol` so it asserts the predicate the engine
   actually consults.
3. Treat every remaining `wei`-written constant in a quote-agnostic contract as
   F-03-shaped until proven otherwise: the bug class is "a value expressed in a
   unit", and `_q` is a unit converter.
4. Before any rotation, snapshot `PerpVault.tokShares` / `pendingTok` — a non-zero
   value is, today, a hard veto on the engine following the rotation.
