# V1 — pre-emptive liquidation sweep (R1A / R1B / R1C)

Tree: /tmp/r45-blind-h1/contracts/solidity. All three PoCs re-run with `-vv`; all three
attack assertions executed (their `console2.log` lines and the assertion messages appear
in the traces). No `return;` or `vm.skip` in any top-level `test_*` body — the only
`return;` hits are inside the internal helpers `_search` / `_rotateUntilSafe`, which set
their result fields before returning, and each top-level test asserts `ran`/`ranA`
before its invariant. No PoC depends on `vm.warp`/`vm.roll`, so the viaIR timestamp
gotcha does not apply.

---

## R1C — gas-capped swap skips both sweeps — **CONFIRMED, HIGH**

### Quoted code (VERIFIED by read)

contracts/solidity/CauldronHook.sol:161
```solidity
uint256 internal constant LIQ_GAS_RESERVE = 180_000;
```
contracts/solidity/CauldronHook.sol:172
```solidity
uint256 internal constant LIQ_GAS_MIN = 400_000;   // don't bother firing under this
```
contracts/solidity/CauldronHook.sol:791-799
```solidity
function _liqSweep(address sender, int256 amountSpecified, bool isBuy, uint160 limit) private {
    if (perpEngine == address(0) || sender == perpEngine) return;
    uint256 reserve = amountSpecified != 0 ? LIQ_GAS_RESERVE + LIQ_GAS_MIN : LIQ_GAS_RESERVE;
    uint256 g = gasleft();
    if (g > reserve + LIQ_GAS_MIN) {
        perpEngine.call{gas: g - reserve}(
            abi.encodeWithSelector(IPerpEngineLiq.sweepLiquidations.selector, tx.origin, amountSpecified, isBuy, limit)
        );
    }
}
```
The hook's own note at CauldronHook.sol:165 supplies the cost baseline: "minimum swap gas
for the sweep to actually kill a position was 543_602, against 103_857 for the bare swap".
Pre-trade call site: CauldronHook.sol:1291 (`amountSpecified != 0` → threshold 980_000).
Post-trade call site: CauldronHook.sol:969 (`int256(0)` → threshold 580_000).

### Execution (VERIFIED)
`test_R1C_gas_capped_swap_skips_both_sweeps` FAILS at the first cap tried:
```
gasCap 500000 swapOk true
   survived true insolvent true
badDebtGapWei 307979144626939095
```
`swapOk true` is the `(ok,) = address(pm).call{gas: cap}(unlock...)` return — the swap
SUCCEEDED under the cap, it did not revert. The positive control
`test_R1C_positive_uncapped_gas_preempts` PASSES with `survivedPos false`, i.e. the same
trade at ordinary gas does kill the victim pre-emptively. That control is the
one-line-difference experiment the brief asks for: the only delta between the failing and
passing test is the gas cap, so the mechanism claim is isolated.

The PoC's insolvency metric matches the engine's own: PerpEngine.sol:1568
```solidity
return p.isLong ? val < p.principal : val > uint256(p.collateral) + p.principal;
```
and the PoC computes `val = quoteAt(vSize, _sqrtP()) ; ins = val < vPrin`. Same formula.

### Counter-arguments tried
(i) **Realized or deferred?** DERIVED: **REALIZED.** The cursor persists
(`sweepCursor = cursor`, PerpEngine.sol:1162) and `liquidate(uint256)` is permissionless
(PerpEngine.sol:1037), so the victim *will* be reached by the next ordinary swap or by any
keeper. But the whole point of the pre-emptive leg is to close BEFORE the trade lands; once
the trade has landed the price is already down and the later liquidation recovers only
`val`, which is 0.30798 ETH short of `principal`. The hole is created by the capped swap and
no later action can shrink it. Deferred liquidation would be the finding if the position
were merely *unhealthy*; it is *insolvent* (zero equity, `val < principal`), and the code's
own comment at PerpEngine.sol:1514-1516 states the case: "past zero equity every further
block is bad debt the vault eats, and waiting cannot make it smaller." So severity does not
drop on this axis.
(ii) **Attacker profit?** The gas cap is not a cost — it is a *saving*; the attacker pays
less gas than an honest swapper. Direct profit comes from two shapes: an attacker holding
the opposite side of the victim's trade, and (more cheaply) a trader capping gas on their
OWN swaps so their own insolvent position is never pre-empted. Pure-grief framing does not
rescue this because the grief is free.
(iii) **Another gas floor / keeper path?** `SWEEP_KILL_RESERVE = 420_000`
(PerpEngine.sol:424, used at :1142) is a floor *inside* the sweep and is never reached when
the hook skips the call entirely. `liquidate()` (:1037) is permissionless but cannot run
inside someone else's tx before their swap, so it cannot substitute for pre-emption.
(iv) **Counterparty needed?** No. The attacker in the PoC is an ordinary seller with no
relationship to the victim.

### Price
Attacker cost: nothing above an ordinary swap (500_000 gas cap; the bare swap is ~104k).
Staker/insurance loss: 0.30798 ETH per 1-ETH-collateral victim, per attack. Repeatable once
per victim per block, bounded only by the number of open insolvent-able positions.

**Verdict: CONFIRMED, HIGH** — the caller chooses whether the liquidation engine runs at
all, at negative cost, and each bypass crystallizes bad debt on insurance/PLV.

---

## R1B — 12-slot sweep window over a 64-slot book — **CONFIRMED, MEDIUM (downgraded from HIGH)**

### Quoted code (VERIFIED by read)
contracts/solidity/cauldron/PerpEngine.sol:419 `uint256 internal constant SWEEP_SCAN = 12;`
:186 `uint256 internal constant MAX_LIQ_PER_SWAP = 8;`
:198 `uint256 public constant MAX_OPEN_POSITIONS = 64;`
:182 `uint256 public minCollateral = 0.003 ether;`
:1126-1162 (the scan loop):
```solidity
uint256 cursor = sweepCursor;
...
while (scanned < SWEEP_SCAN && scanned < len && kills < MAX_LIQ_PER_SWAP) {
    if (gasleft() < SWEEP_KILL_RESERVE) break;
    ...
    if (_openIds.length < n) { kills++; } else { cursor++; }
    scanned++;
}
sweepCursor = cursor;
```

### How the cursor advances, and what `_rotateUntilSafe` exploits (VERIFIED)
`sweepCursor` is **persisted** across swaps (:1123 read, :1162 write) and advances by one
slot per *non-killing* check. So one swap covers 12 slots pre-trade and the next 12
post-trade — a deterministic, publicly readable 24-slot window on a ring of `_openIds`.
The PoC reads `sweepCursor` directly from storage slot 80 and `_openIds.length` from slot
78, then issues 0.02-ETH dust sells until the victim's index satisfies `rel >= 24`. It took
**2 rotations**. The padding is 40 **shorts** at 0.01 ETH — chosen because a crash makes a
short profitable, so the sweep never kills them and never swap-pops the tail into the
window, keeping the ring geometry stable.

### Execution (VERIFIED)
```
windowSafe true rotations 2
survived true insolvent true
  valAtRealized 615744607482444746 principal 931000000000000000
badDebtGapWei 315255392517555254
```
Control `test_R1B_positive_short_book_is_preempted` PASSES with `survivedBare false` — the
identical 45-ETH crash on an unpadded book does pre-empt the victim. Again a clean
one-variable experiment: only the padding + rotation differ.

### Counter-arguments tried
- **Cursor rotates → reachable later.** True, and it means the *liquidation* is deferred.
  But as in R1C the *loss* is REALIZED: `val` is 0.6157 ETH against 0.931 ETH of principal
  the instant the crash lands, and a later sweep at that same depressed price still leaves
  0.31526 ETH for insurance/PLV.
- **Does the padding cost anything?** 40 x 0.01 ETH = 0.40 ETH of collateral, in SHORT
  positions that are *profitable* in the very crash the attacker then causes, and closable
  at will. Net cost is plausibly negative; the only sunk cost is open fees plus two 0.02-ETH
  dust sells. Cheap, but not free and not instantaneous — this is what separates it from
  R1C.
- **Does `MAX_OPEN_POSITIONS = 64` cap the grief?** It caps the ring at 64, which is more
  than the 24-slot double window, so the window can always be evaded; but it also caps how
  many victims can be parked, and the attacker's 40 pads consume 40 of the 64 global slots,
  which is itself loud and self-limiting (and blocks the attacker's own future victims from
  opening — `OiCapped()` at :1943).
- **Ordinary liquidation outside swaps?** Unaffected: `liquidate(uint256)` at :1037 takes an
  explicit id and does not use the window at all. So a keeper closes the position after the
  fact; only the *pre-emption* is starved.

**Verdict: CONFIRMED but DOWNGRADED to MEDIUM** — same realized-bad-debt outcome as R1C
(0.31526 ETH), but it costs 0.40 ETH of capital to set up, consumes 40 of 64 global position
slots, and requires reading engine storage and timing two rotating sells. R1C achieves the
same result for free, which is why R1C is the one that should drive any fix.

---

## R1A — free kill inside the projection slack — **CONFIRMED as a mechanism, DOWNGRADED to LOW; ruling: NEW EVIDENCE**

### Quoted code (VERIFIED by read)
contracts/solidity/cauldron/PerpSwapLib.sol:63 `uint256 internal constant SLACK_BPS = 1500;`
:212 `uint256 slackBps = SLACK_BPS;`
:218 `uint256 inflated = amountIn + FullMath.mulDiv(amountIn, slackBps, 10_000);`
PerpEngine.sol:1552-1561 (the zero-buffer projected leg):
```solidity
//  INSOLVENCY, never maintenance. Only the TWAP is allowed a
//  maintenance buffer, ...
uint160 pj = _projSqrtP;
uint160 sp = pj != 0 ? pj : _sqrtP();
if (sp != 0) insolvent = _insolventVal(p, _quoteAt(p.size, sp));
```

### Execution (VERIFIED)
```
MIN kill sellEthEq 22250000000000000000
  valAtRealized 962809494402837712 threshold 931000000000000000
healthyBefore true  diedInSwap true  solventAtRealized true
```

### (a) Is the victim really solvent at the realized price? YES (DERIVED from the trace)
The PoC values the position with `PerpSwapLib.quoteAt(vSize, _sqrtP())` and compares to
`p.principal` — byte-for-byte the engine's own long test at PerpEngine.sol:1568
(`val < p.principal`). Crucially `_sqrtP()` is sampled AFTER the kill, so it already
includes the liquidation's own settlement sell pushing price further down; the
counterfactual price with the victim left open would be *higher* and the victim *more*
solvent. So the measurement is conservative against the finding and it still shows
0.96281 > 0.931.

### (b) The slack's effect in PRICE bps, and the buffer that is not there
For the kill to fire, the projected value must be < 0.931 while the realized value is
0.96281 — the projection understates the position's value by at least
(0.96281-0.931)/0.96281 = **330 bps of price**, an order of magnitude above the "12-190 bps"
the prior refutation assumed. And the 1500 bps `maintenanceBps` (PerpEngine.sol:171) is NOT
available to absorb it: the projected leg is explicitly zero-buffer (PerpEngine.sol:1552-1557
quoted above); the maintenance buffer lives only on `_underwaterVal` (:1608). The prior
refutation's arithmetic compared an input-side slack against a buffer that this code path
deliberately does not apply.

### (c) Who profits, and at what cost
Liquidator payout: PerpEngine.sol:1728-1730
```solidity
uint256 penalty = (uint256(p.collateral) * liqPenaltyBps) / BPS;
uint256 toKeeper = (penalty * keeperBps) / BPS;
```
with `liqPenaltyBps = 690` (:155) and `keeperBps = 145` (:168): on 1 ETH of collateral the
attacker (credited as `tx.origin` at CauldronHook.sol:797) earns
1 ETH x 6.9% x 1.45% = **1.0 mETH**. To earn it they must push 22.25 ETH of sell through a
~60 ETH pool and, to avoid eating the price move, buy it back — two legs of hook + LP fees
on 22.25 ETH, i.e. order 0.5-1 ETH. That is a **500-1000x loss-maker**, strictly worse for
the attacker than the 9x the prior pass measured. The attacker does NOT receive the victim's
collateral; the penalty accrues to the protocol/PLV. Stakers are net beneficiaries of this
direction of error.

### (d) Would the ordinary path have killed it anyway?
Yes, on the mark leg, as soon as the TWAP converges. PerpEngine.sol:1608:
```solidity
return val < p.principal + (p.principal * maintenanceBps) / BPS;
```
0.96281 < 0.931 x 1.15 = 1.0707, so the victim is *underwater on the mark* at the realized
price and dies by the ordinary path within one TWAP window if the price persists. The free
kill is therefore **early, not wrong**, unless the attacker atomically restores the price —
which is exactly the 500-1000x-loss trade above. The victim's forfeited residual equity is
bounded by 0.96281 - 0.931 = **31.8 mETH**, i.e. 3.2% of its 1 ETH collateral, and the
6.9% penalty exceeds that residual anyway.

### Ruling: NEW EVIDENCE
The prior refutation is defeated on mechanism: this is a LONG (not the sunk short), it is
solvent at the realized price by the engine's own formula, the error is 330 bps of price not
12-190, and the maintenance buffer it invoked does not apply to the projected leg. The
finding also directly falsifies the library's own claim at PerpSwapLib.sol:196-198 — "the
over-liquidation scan STILL finds no trade size that survives the real trade yet dies to the
projection" — which is now false at 22.25 ETH.

But the severity conclusion is unchanged and lower than the hunter's: bounded harm
(<= 3.2% of collateral, to a trader who is already 96.8% wiped by a legitimate price move),
no staker harm, and a 500-1000x negative-EV attack.

**Verdict: CONFIRMED as a mechanism, DOWNGRADED to LOW / informational.** The actionable
part is the comment at PerpSwapLib.sol:196-198, which now asserts something the tree can
disprove.

### Remedy note (HYPOTHESIS, not an instruction)
Do NOT respond by shrinking SLACK_BPS: that moves the projection in the *less* conservative
direction and hands the R1C/R1B bad-debt class more room, violating STAKER-FIRST. If
anything is done it belongs on the accounting side (e.g. crediting a projection-killed
position its realized-price residual rather than the projected one), which touches neither
`beforeSwap` gating nor exact-output routability, so ROUTABILITY by the Universal Router and
aggregator exact-output quoting is unaffected. Unverified.

---

## Summary
| # | Verdict | Severity | Loss | Attacker cost |
|---|---|---|---|---|
| R1C | CONFIRMED | HIGH | 0.30798 ETH realized bad debt | negative (saves gas) |
| R1B | CONFIRMED (downgraded) | MEDIUM | 0.31526 ETH realized bad debt | ~0.40 ETH capital + 40/64 slots, recoverable |
| R1A | CONFIRMED mechanism (downgraded) | LOW | <= 31.8 mETH of trader residual, no staker loss | 0.5-1 ETH for a 1.0 mETH bounty |

Discards (findings not independently verified within budget): 0.
