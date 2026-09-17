# V2 — perp vault solvency / queue mechanics (verification)

Tree: /tmp/r45-blind-h2/contracts/solidity. All four PoCs compiled and passed under
`forge test --match-path 'test/attacks/R2*_*.t.sol' -vv` (4 passed, 0 failed).
`grep -n "return;\|vm.skip" test/attacks/R2*.t.sol` → **no hits**; every top-level
`test_*` runs to its assertions, and each PoC logs the exact values it asserts on
(logs quoted per finding below), so no assertion was skipped. **VERIFIED**.

IMPORTANT SCOPE CAVEAT (applies to R2A/R2B/R2C): all three PoCs drive the real
`PerpVault` against `test/attacks/R2Mock.sol:MockEngine`, not the real `PerpEngine`.
The vault arithmetic they exercise is production code (**VERIFIED**); the claim that
the engine reaches the states the mock fakes is **DERIVED** from reading the engine's
loss paths, not executed.

---

## R2B — token queue latch + unguarded `depositToken` → **DOWNGRADED: HIGH** (from Critical)

The asymmetry is real and quoted from production source:

ETH side, `PerpVault.sol:391` and `:403`
```
if (owed == 0) { emit ClaimEth(msg.sender, 0); return 0; }
...
if (paid == 0) { emit ClaimEth(msg.sender, 0); return 0; }
```
Token twin, `PerpVault.sol:565-569`
```
if (capped < owed) { pendingTok -= (owed - capped); pendingTokOf[msg.sender] = capped; owed = capped; }
if (owed == 0) revert ZeroAmount();
uint256 free = engine.freeToken();
paid = owed <= free ? owed : free;
if (paid == 0) revert ZeroAmount();
```
Both reverts roll back the `:565` haircut. (4) of the brief: **the ETH twin's
behaviour really does differ — VERIFIED by quote above and by the PoC's positive
control** (`_ethControl()` → `assertEq(ethPending, 0, "ETH side banks the write-down and empties")`).

`pendingTok` is written at exactly four sites — `PerpVault.sol:552, 553` (grow) and
`:565, :571` (shrink, both inside `claimPendingToken`). (3) of the brief: **no admin
function, sweep or migration drains the token queue** — grep of `pendingTok` over the
whole vault returns only those plus views at `:206, :241, :593`. So while backing <
`pendingTok`, the queue cannot shrink and `hasStakers()` (`:206`,
`(ethShares | tokShares | pendingEth | pendingTok) != 0`) is true, which fails
`PerpEngine.sol:2621`:
```
if (vault != address(0) && IPerpVaultStake(vault).hasStakers()) revert BadParam();
```
Measured (-vv): `pendingTok` 100000000000000000000 after a total wipe-out,
`hasStakers()` true, ETH control 0.

Reachability, (2) of the brief — **DERIVED, and it needs a real bad-debt event, not a
cheap attacker action**. The only writer that shrinks token backing is
`PerpEngine.sol:2223-2226`:
```
function _writeOffTok(uint256 id, uint256 amount, bool isLong) private {
    if (amount == 0) return;
    if (isLong) plvToken += amount; else shortOiToken -= amount;
```
`totalTokenAssets() = plvToken + shortOiToken` (`PerpEngine.sol:584`). The short leg
is reached from `PerpEngine.sol:1694` `_writeOffTok(id, unbought, false);` — and the
ten lines above it (`:1681-1693`) show the write-off happens **only** in
`mode == MODE_DEATH`; every non-death shortfall takes `_rebook` and stays open. So
the precondition is a death-settled short whose buy-back the pool could not supply
in-band: an exogenous insolvency, not something an attacker mints for free. No
attacker-initiated, fresh-deploy path was found.

Two claimed consequences, judged separately:
- **setVault brick — operational, not a loss.** It is also *not* "for the engine's
  life": `depositToken` raises `plvToken`, which lifts `totalTokenAssets` back over
  `pendingTok`, and the PoC's own step 6 shows the queue then drains in full
  (`attackerClaimed == 100 ether`, `pendingTok → 0`). So the latch clears the moment
  someone deposits; it persists only while nobody does. The engine keeps trading
  either way — the source itself calls the equivalent block "a griefing nuisance and
  not the permanent freeze reported" (`PerpEngine.sol:2617-2619`).
- **The real bug is the missing guard.** `deposit` has `PerpVault.sol:274`
  `if (pendingEth > engine.totalEth()) revert QueueInsolvent();`; `depositToken`
  (`:507-527`) has no counterpart, so the victim's 100e18 mints shares redeemable for
  0 and the stale queue takes 100% of his principal. -vv: `victim redeemable token: 0`,
  `stale queue claimed from victim principal: 100000000000000000000`.

Falsifying one-line change: delete `eng.writeOffTok(50 ether);` (PoC line in step 3)
— backing stays 100e18, `_haircut` returns `owed` unchanged, the claim succeeds and
`pendingTok` drains, so `pendingAfter == 100 ether` and the victim assertions fail.
The mechanism is therefore genuinely the write-down-rollback, not an artifact.

**Verdict: CONFIRMED as a mechanism, severity DOWNGRADED to HIGH** — full principal
loss for the next token depositor is real, but it requires a prior token-side
death-settle write-off (no cheap attacker trigger), the "bricked forever" half is
self-clearing and costs no funds, and the attacker (the queued LP) must first have
eaten the same loss himself.

## R2C — `QueueInsolvent` deposit latch → **CONFIRMED, HIGH** (hunter's "cost 0.001 ETH" is wrong)

Gate quoted, `PerpVault.sol:274`:
```
if (pendingEth > engine.totalEth()) revert QueueInsolvent();
```
`pendingEth` shrinks only at `PerpVault.sol:381` and `:405`, both inside
`claimPendingEth`, both keyed on `pendingEthOf[msg.sender]` (`:377`). Grep of
`pendingEth` across the vault shows no `claimFor`, no expiry, no owner sweep —
**(the "only key is the holder" claim is VERIFIED)**. -vv: pendingEth 10e18 vs
`totalEth()` 1e15; deposit reverted while held; deposit succeeded immediately after
the holdout claimed (positive control asserted).

Corrections to the hunter's framing:
- **Not a 0.001 ETH grief.** The PoC's holdout stakes 10 ETH and loses ~all of it to
  bad debt first (`eng.absorbLentLoss`); 0.001 ETH is only the residue of his claim
  afterwards. So the state needs a prior near-total insolvency — reachable per
  `PerpEngine.sol:2243-2249` `_absorbPlvLoss` (saturating `plv = plv > rest ? plv - rest : 0`)
  and the long-settle shortfall at `PerpEngine.sol:1639/1679` — **DERIVED**, an
  exogenous event, with no attacker profit at any point.
- **Stakers can still exit.** `withdrawEth` (`PerpVault.sol:326`) carries no
  `QueueInsolvent` check, so this is a **deposit DoS, not a lock of existing funds**.
- **Two non-holder cures exist**, both of which the hunter missed: `totalEth()` rises
  with `PerpEngine.sol:2364 fundPlv` (onlyOwner) and with hook-credited perp fees
  (`_creditPerp`, `PerpEngine.sol:2430`), and either can lift backing back over
  `pendingEth`. Neither is permissionless and the owner must donate the whole
  shortfall, so the issue stands — but it is not unfixable.
- The claim being ~worthless is exactly why the holdout never returns (apathy, not
  spite, is enough), and the same `pendingEth != 0` also latches `hasStakers()` so a
  replacement vault cannot be installed either (`PerpEngine.sol:2621`).

Falsifying one-line change: replace `eng.absorbLentLoss(10 ether - 0.001 ether)` with
`eng.absorbLentLoss(1 ether)` — the queue stays solvent, `depositEth` succeeds, and
`depositRevertedWhileHeld` fails. Mechanism confirmed as insolvency-gated.

**Verdict: CONFIRMED at HIGH** — it needs a prior insolvency event (the brief's own
rubric for High), does not self-heal on the ETH side, and permanently shuts new
capital out of the vault absent owner recapitalisation.

## R2A — queue seniority → **DOWNGRADED: MEDIUM**

Mechanism VERIFIED in production source: `PerpVault.sol:236`
`return t > pendingEth ? t - pendingEth : 0;` removes the queue from the live base
first, and `_haircut` (`PerpVault.sol:371-377`) only bites `if (claims == 0 || backing >= claims) return owed;`
i.e. never until live shares are *already* wiped. -vv: racer 5.0 ETH, passive LP 1.0
ETH on a 4 ETH loss between equal 5/5 LPs. So no, the queue's own haircut never
reaches the racer before the live base is gone — **(that sub-question: VERIFIED, it
does not)**.

Why this is not High:
- It is **documented as the known residual**, not an oversight. `PerpVault.sol:360-370`
  states the problem in the protocol's own words ("a queued exit stopped bearing
  bad-debt risk while still being first in line for the money … a bank run with a
  protocol-enforced starting gun") and the remedy shipped is pro-rata *within* the
  queue only. The design intent — pro-rata across live shares too — is stated at
  `:366-369` and is not what the code does, so the gap is real, but it is a known and
  written-down asymmetry.
- **No outside attacker; it is LP-vs-LP redistribution requiring foresight.** The PoC
  simply calls `eng.absorbLentLoss` after the racer queued. For the race to be
  executable the racer must see the loss coming; `PerpEngine.isLiquidatable` is public
  and `withdrawEth` is a separate transaction, so a same-block front-run of a
  liquidation tx is plausible — **HYPOTHESIS, not demonstrated**: I did not execute a
  mempool race, and the PoC does not contain one (it hard-codes the ordering). By the
  brief's own instruction ("Show the race is executable by an outside LP watching the
  mempool, or downgrade"), it downgrades.
- Total value is conserved (`assertLe(aOut + bOut, 10 ether)` passes) — no funds leave
  the system, no protocol insolvency is created.

Falsifying one-line change: move `eng.absorbLentLoss(lossTotal)` above the
`vault.withdrawEth(aShares)` call — the racer then queues at the post-loss price, both
LPs take 3 ETH, and `assertGt(aOut - bOut, 3 ether)` fails. That confirms the effect is
purely the request-time NAV crystallisation the hunter names.

**Verdict: DOWNGRADED to MEDIUM** — mechanism CONFIRMED, but it is a documented
first-mover asymmetry between LPs with no external attacker, no value leakage, and an
unproven race.

## R2D — `_insuranceNeed` grief → **NOT VERIFIED (discard)**

Code reads as the hunter says: `PerpEngine.sol:1991-1995`
```
uint256 riskMin = ((longOiEth + _quoteEth(shortOiToken)) * maintenanceBps) / BPS;
uint256 floorQ = _q(insuranceFloor);
return floorQ > riskMin ? floorQ : riskMin;
```
gated at `PerpEngine.sol:2024-2025` `if (need > 0 && insuranceEth < need) revert InsurancePaused();`.

Blocker for a PoC: the R2 PoCs are non-fork only because they never touch the engine
— they use `MockEngine`. Exercising `_utilGate`/`openLong` needs a real `PerpEngine`
plus a live PoolManager; both available bases fork (`test/attacks/YBase.sol:101-104`
`vm.createSelectFork(rpc)`, `new PerpEngine(` at `:149`; `test/final/FinalAuditBase.sol:27`
says the same). Building a non-fork engine harness was outside budget, so no PoC.

Two counter-arguments that would likely sink it anyway (**DERIVED**):
1. `PerpEngine.sol:2378 function fundInsurance(uint256 amount) external payable` is
   **permissionless** — anyone, including the protocol, can top the buffer back over
   `need` and reopen opens. The grief is curable for exactly the shortfall.
2. The pause is the *stated intent* of the risk-scaled floor (`PerpEngine.sol:1999-2010`):
   refusing new leverage while the buffer no longer covers maintenance margin on
   existing OI. Pausing opens is the feature, not the bug; the hunter's "81x" compares
   a margin requirement to a fee stream, which are not the same quantity.

**Verdict: NOT VERIFIED — discard.**

## R2E — refutation PoC → **it does assert (but two refutations, not three)**

`test_R2E_eth_share_math_holds` ends on real assertions with no early return:
```
assertApproxEqAbs(freshRedeemable, 10 ether, 1e6, "newcomer is NOT diluted by a solvent queue");
assertEq(afterDonation, freshRedeemable, "no permissionless donation into the share base");
```
plus in-body `assertLe(vault.pendingEth(), eng.totalEth(), "solvent: the guard lets him in")`
and `assertTrue(ok, "raw send accepted by the engine's receive()")`. -vv logs
`redeemable: 10000000000000000000` before and after a 50 ETH raw donation, so both
assertion lines executed. The file documents and asserts **two** refuted attacks
(worthless-share mint against a solvent queue; donation/first-depositor inflation) —
the brief's "three" is unsupported by the file. Refutations stand as asserted;
note the donation refutation's structural half (onlyOwner/onlyVault/onlyHook writers of
`plv`) is asserted only for the raw-send route, the rest is DERIVED from
`PerpEngine.sol:2364, 2430-2431, 2463`.

---

Discards: 1 (R2D).
