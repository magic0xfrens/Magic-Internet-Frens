# V3 — Perps verification (blind)

Tree: `/tmp/blind-final-h3/contracts/solidity`. All five tests compile and pass unmodified:

```
Ran 4 test suites in 208.13ms: 5 tests passed, 0 failed, 0 skipped (5 total tests)
[PASS] test_QuoteRotation_RedenominatesNativeCountersAndDrainsPlv() (gas: 415175)
[PASS] test_NativeValueInflatesAnErc20DenominatedPlv()             (gas: 376659)
[PASS] test_QueuedExitInWeiClaimsTheWholeNewQuoteDeposit()         (gas: 375420)
[PASS] test_Control_NoRotation_QueueTakesOnlyItsNominal()          (gas: 238520)
[PASS] test_RotationResetsRingAndHandsTheMarkToA10SecondPush()     (gas: 1323488)
```

`grep -n "return;"` over all four PoC files returns **zero hits** — no early-return vacuity.
The only conditionals are two helper lines in X3c (`:32`, `:39`) inside a mock token's
transfer helper, not in an assertion path. Every test's final assertion block executed
(proven by the flip tests below, which fail *at* those assertions).

**Non-vacuity flip test (mandated).** Two targeted one-line source fixes were applied,
the suite re-run, then the source restored byte-identical (`diff` clean, suite green again).

| Patch | X3a | X3b | X3c | X3d |
|---|---|---|---|---|
| `plv != 0` → `(plv \|\| tokYieldEth \|\| insuranceEth) != 0` @ :1098 | **FAIL** | pass | pass | pass |
| `+ if (!_quoteIsNative()) revert BadParam();` in `_creditPerp` | — | **FAIL** | pass | pass |

That X3c and X3d keep passing under *both* engine-side fixes is itself evidence: they are
independent holes, not restatements of X3a.

---

## X3a — CONFIRMED, **DOWNGRADED Critical → High**

**Verdict:** the mechanic is exactly as claimed and the cited line is exact; the trigger is
governance-gated, not permissionless, so it lands in the High band.

The guard is at **`cauldron/PerpEngine.sol:1098`**, verbatim:

```solidity
if (newQuote != quote && plv != 0) revert VaultStaked();
quote = newQuote;
```

`plv` is the only counter tested. `tokYieldEth`, `insuranceEth` and `payoutOwed` are
untouched by the guard and are paid through `_sendEth` → `_pushQuote`, which pays in
whatever `quote` says *today*. The file's own comment above the guard concedes the
denomination hazard for `plv` ("a bare COUNTER of the quote asset … re-denominates every
staked wei without moving any of it") and then guards only that one name.

`-vv` evidence — every assertion executed:
```
assertEq(tokYieldBefore, 1 ether)         tokYieldEth is native wei
assertTrue(synced)                        permissionless syncGeneration adopted the new quote
assertEq(quoteAfter, address(newQuote))   quote flipped while 1.5 ETH was owed
assertEq(stolen, 1 ether)                 1 USDG taken against a 1-ETH-denominated counter
assertEq(engineBalAfterPull, 999 ether)   engine is now 1 USDG short of plv
assertLt(engineBalAfterPull, plvAfterPull) ENGINE IS INSOLVENT vs plv
assertEq(address(perp).balance, 1.5 ether) native trapped, no payer left
```

**Flip test:** with only the `:1098` guard widened, the test fails `BadParam()` — the sync is
refused, `quote` stays `address(0)`, and the ERC20 credit the attack depends on is rejected by
`creditPerpFeeAsset`'s `if (asset != quote || asset == address(0)) revert BadParam();`. The
guard is load-bearing and the finding is non-vacuous.

**Counter-arguments tried:**
1. *"The PoC uses a mock registry; the real one may not let `generationQuote[gen]` move for a
   live generation."* — **Failed.** `CauldronRegistry.sol:982` and `cauldron/RedemptionExt.sol:505`
   (`generationQuote[gen] = toQuote;`) both write it, and RedemptionExt's own comment at :716
   states "a completed rotation flips" this read. The mock is faithful.
2. *"`_isDead` parks the engine on divergence, so nothing mispays."* — **Failed.** That park only
   covers the window *before* the sync. After `syncGeneration` adopts the new quote there is no
   divergence left to detect, so the engine resumes and pays the stale counters in the new asset.
3. *"A settlement path re-denominates those counters elsewhere."* — **Failed.** No such path found;
   `syncGeneration` re-arms `plvToken`, `shortOiToken` and `longOiEth` only. The owner can re-seed
   via `fundPlvToken` but nothing converts a stale wei figure in `tokYieldEth`/`insuranceEth`.
4. *"The trigger is permissionless."* — **SUCCEEDED (this is the downgrade).** The hunter's
   "whole chain is permissionless" is true only of the steps *after* the rotation.
   `RedemptionExt.rotateSliceFrom` gates the write behind four checks:
   `if (rot == address(0)) revert RotationNotWired();` · `if (gov == address(0)) revert RotationNotWired();`
   · `if (remaining == 0) revert NoRotationApproved();` · `if (!allowedQuote[toQuote]) revert NotConfigured();`
   A governance-approved envelope is required. Per the rubric ("High = same but needs a role"), High.

**Why it is High at the top of its band, not Medium:** no attacker and no malice are required —
an *honest, intended* treasury rotation strands the funds, and no rescue path re-denominates the
stale counters. Recommended fix is the flip-test patch itself.

---

## X3b — CONFIRMED **High** (severity unchanged)

**Verdict:** `_creditPerp` is verifiably the only native ingress with no `_quoteIsNative()` test,
and my counter-argument that the real hook could never reach it failed.

`cauldron/PerpEngine.sol:1610` opens the function; the unguarded credit is:
```solidity
function _creditPerp(bool ethSide) private {
    if (msg.sender != hookAddr) revert OnlyHook();
    uint256 amount = msg.value;          // :1617 — no _quoteIsNative() test
    if (ethSide) { plv += amount; } else { tokYieldEth += amount; tokYieldCumulative += amount; }
```
The three siblings do gate: `fundPlv` (:1550), `fundInsurance` (:1564) and `fundFromVault` (:1633)
all route through `_pullQuote` (:194), which branches on `_quoteIsNative()` (:195); the ERC20 twin
`creditPerpFeeAsset` (:1600) rejects a mismatched asset. `_quoteIsNative()` is defined at :186.
The PoC's three control assertions (`assertFalse` × 3) all executed and held.

`-vv` evidence:
```
assertTrue(feeTookValue)          creditPerpFee accepted native wei anyway
assertEq(plvAfter - plvBefore, 1 ether)   plv inflated by 1e18 USDG-units
assertEq(usdgHeld, 0)             engine received ZERO USDG for either credit
assertEq(nativeHeld, 2 ether)     2 ETH sits untracked; no counter can pay it
assertGt(plvAfter, usdgHeld)      plv claims USDG the engine does not hold
```

**Counter-argument tried (the cheapest one): "hook-only, and the real router would never send
native on an ERC20 book, so this is dead defence-in-depth." — FAILED.**
`CauldronHook.sol:1196` `_routePerpFee` passes the hook's `_feeAsset` into
`FeeRouteLib.routePerp`, which dispatches through `_deliver`:
```solidity
if (asset == address(0)) {
    (ok, ) = to.call{value: amount}(abi.encodeWithSelector(nativeSel));   // -> creditPerpFee
```
`nativeSel` is `creditPerpFee` / `creditPerpFeeToken`. The branch is chosen by the **hook's
`_feeAsset`**, while the engine's `quote` comes from **`registry.generationQuote(gen)`** via
`syncGeneration` — two different sources. The codebase itself documents that they diverge during
a rotation (`RedemptionExt.sol:487`: the pool "names the OLD pair while `generationQuote` names
the new one"). So the exact state X3a creates also makes X3b reachable through the honest router.
Stays High (needs the hook plus the rotation window), not Critical.

---

## X3c — CONFIRMED, **DOWNGRADED Critical → High** (both sub-claims hold; this is the sharpest of the four)

**Sub-claim (a): an 8 ETH queue survives the rotation.** Confirmed, and the arithmetic makes it
unavoidable rather than incidental. `pendingEth` is **PerpVault** state (`PerpVault.sol:96`); the
guard at `PerpEngine.sol:1098` reads only engine state, so it cannot see it. Decisively:
```solidity
function totalEth() public view returns (uint256) { return plv + longOiEth; }   // PerpEngine.sol:466
function freeEth()  external view returns (uint256) { return plv; }             // PerpEngine.sol:468
```
`syncGeneration` requires `if (openCount != 0) revert PositionsOpen();`, which forces
`longOiEth == 0`. Therefore at the instant the guard is evaluated, `plv == 0` implies
`totalEth() == 0` — the vault is maximally insolvent against its queue — and that is precisely
the state in which the guard *passes*. The control test bounds the honest case to 8e18 and
passes, so the 100% take is attributable to the rotation and nothing else.

`-vv` evidence:
```
[PASS] test_QueuedExitInWeiClaimsTheWholeNewQuoteDeposit()     (gas: 375420)
[PASS] test_Control_NoRotation_QueueTakesOnlyItsNominal()      (gas: 238520)   <- control bounds it to 8e18
```

**Sub-claim (b): `PerpVault.sol:90`'s comment is wrong — `_haircut` can never write a queue to
zero.** Confirmed by reading. The comment claims:
```
//      a new quote while `plv != 0`, so the asset cannot change underneath a
//      staker: the vault must be drained first, and a queue left against zero
//      backing is written down to zero by {_haircut} before then.        <- :89-90
```
But the only caller does this:
```solidity
uint256 capped = _haircut(owed, engine.totalEth(), pendingEth);
if (capped < owed) { pendingEth -= (owed - capped); pendingEthOf[msg.sender] = capped; owed = capped; }  // :295
if (owed == 0) revert ZeroAmount();                                                                      // :296
```
With `backing == 0`, `_haircut` returns `0` for **every** caller, so line :295 writes the zeroing
and line :296 reverts the same transaction, rolling it back. The write-down can never persist.
The documented precondition for the `plv != 0` guard being safe is therefore unenforceable, and
`hasStake()` (`:157`, which *does* read `pendingEth`) is never consulted by `syncGeneration`.

**Counter-arguments tried:** (1) *"the haircut zeroes the queue first, as documented"* — **failed**,
see (b). (2) *"`plv != 0` transitively covers `pendingEth`"* — **failed**, `totalEth()` arithmetic
above shows the opposite: `plv == 0` is exactly when the queue is worst off. (3) *"the X3a fix
also fixes this"* — **failed**, X3c still passes under both flip-test patches.

**Downgrade reason:** identical to X3a — the trigger is the governance-gated rotation
(`NoRotationApproved` / `allowedQuote`), not a permissionless call. High, not Critical.
The correct guard is `vault.hasStake()`, not `plv != 0`; and `:296` should be reordered so a
zero write-down commits.

---

## X3d — CONFIRMED **High** (severity unchanged)

**Verdict:** every element of the claim checks out against source; I found a partial mitigation
that bounds the blast radius but does not remove the untrustworthy mark.

Ring reset, `cauldron/PerpEngine.sol:1055-1061` (inside `syncGeneration`):
```solidity
// Reset the TWAP oracle — old-pool ticks are meaningless for the new token.
delete observations;
tickCumulative = 0;
obsIndex = 1;
lastObsTs = uint32(block.timestamp);
lastRingTs = uint32(block.timestamp);
```
Warm-up is measured from `lastSummonAt` and is **not** re-armed here:
```solidity
if (block.timestamp < registry.lastSummonAt() + warmup) revert NotWarm();   // :1283
```
Nothing in `syncGeneration` touches `warmup` or `lastSummonAt`, so a generation summoned more
than 24 h ago is permanently past its gate the instant the ring is wiped. The trust test is only
`MIN_TWAP`:
```solidity
uint32 internal constant MIN_TWAP = 1 seconds;   // :268
unchecked { if (nowTs - oldest.ts < MIN_TWAP) return (0, false); }   // :656
```
so a 10-second span clears it and is reported `ok=true`. The hunter's `setRisk` claim is also
exact — `if (_warmup < MIN_TWAP) revert BadParam();` (`:1674`) floors warm-up at **1 second**, so
an owner cannot use `warmup` to cover the reset window either.

`-vv` evidence:
```
assertLt(armedTick, int24(3000))       control: 10s of push moves a warm 5m TWAP <5%
assertTrue(synced)                     syncGeneration is permissionless after a rotation
assertTrue(warmupLongExpired)          the 24h warmup gate is long past - opens are live
assertTrue(resetOk)                    post-reset mark is reported as TRUSTWORTHY
assertGt(resetTick, int24(45000))      10s of push now IS the liquidation mark (>75%)
assertGt(resetTick, armedTick * 15)    same push, 15x+ the effect
```
The positive control (`armedTick < 3000` on a warm ring) is what makes this non-vacuous: the same
10-second push is harmless before the reset and dominant after it.

**Counter-argument tried (partially succeeded, not enough to move the verdict):**
`syncGeneration` requires `openCount == 0`, so every pre-existing position is force-closed before
the ring is wiped. The collapsed mark therefore cannot liquidate anyone who was already open — it
only misprices positions opened *after* the sync, during the re-warm window. That bounds the
damage but does not remove it: `twapTick` actively reports `ok=true`, so the engine advertises a
mark it should be refusing, and opens are live the whole time. High is the right band; I found no
grounds to raise or lower it.

---

## Summary

| # | Hunter | Verdict | Final |
|---|---|---|---|
| X3a | Critical | CONFIRMED, DOWNGRADED | **High** — governance-gated trigger |
| X3b | High | CONFIRMED | **High** |
| X3c | Critical | CONFIRMED, DOWNGRADED | **High** — both sub-claims hold |
| X3d | High | CONFIRMED | **High** |

**Discarded: 0.** No finding was refuted. Two were downgraded on trigger permissioning only;
all four mechanics reproduced and survived every counter-argument aimed at the mechanism itself.

Root cause shared by X3a/X3b/X3c/X3d: `syncGeneration` re-denominates the book by assignment
(`quote = newQuote`) while treating `plv` as a proxy for "is anything still denominated in the old
asset". It is not a proxy for `tokYieldEth`, `insuranceEth`, `payoutOwed`, the vault's `pendingEth`,
the hook's `_feeAsset`, or the observation ring.

Source tree was restored byte-identical after the flip tests (`diff` clean, suite green).
