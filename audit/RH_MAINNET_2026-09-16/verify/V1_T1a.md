# V1_T1a — blind verification of T1a ("LiqGasStarved floor is sized for ~1 kill")

Worktree `/tmp/rh-blind-h1` (= `contracts/solidity`). Fork engaged (Sepolia, PoolManager
`0xE03A...3543`). All gas numbers below are measured, not read.

## Verdicts

| Claim | Verdict |
|---|---|
| **Primary** — fixed floor lets a multi-short trade strand PLV bad debt | **CONFIRMED (High)** |
| **Secondary (hunter tagged DERIVED)** — ~70k band where the pre-trade sweep fires yet affords zero kills | **REFUTED** |
| **Secondary** — the comment at `CauldronHook.sol:829` disagrees with the code | **REFUTED** (comment is accurate) |
| **New, found while refuting** — the *post-trade* sweep is the one that is starved | **CONFIRMED (this is the actual mechanism)** |

---

## 1. Does the PoC prove what it claims? — VERIFIED

`forge test --match-path 'test/attacks/M1*.t.sol' -vv` →

```
[PASS] test_gate_affords_only_one_kill_strands_the_rest() (gas: 82077117)
  backing0             : 30000000000000000000
  open after ATK buy   : 2
  open after AMPLE buy : 0
  backing after ATK    : 25639743938647686178
  backing after AMPLE  : 30000000000000000000
  extra PLV bad debt   : 4360256061352313822
```

`grep -n "return;\|vm.skip"` on `test/attacks/M1a_LiqGasBand.t.sol` yields exactly two hits:

- line 27 `if (!active) return false;` — inside `_setup`, an internal helper returning `bool`, not an
  early exit of the test body.
- line 62 `if (!ready) { assertTrue(true, "no fork"); return; }` — the no-fork guard. **Not taken**:
  the six `emit log_named_uint` lines at 76–81 are all present in the output, and they sit *below*
  line 62. Therefore lines 83–90 (every assertion) executed. Not a vacuous pass.

No `vm.skip`. The top-level `test_*` body's only `return;` is the guard proven not taken.

## 2. Is the control fair? — VERIFIED, yes

`_run()` (M1a:47-58) is called twice and the **only** differing argument is `gasCap`
(`_run(1_350_000)` at line 71 vs `_run(8_000_000)` at line 74). Each call opens its own
`vm.snapshot()` at line 48 and `vm.revertTo(snap)` at line 57, so both start from the identical
post-`_setup` state: same 4 shorts, same `bigBuy = 40 ether`, same realization loop (lines 52-54),
same accounting `perp.plv() + perp.insuranceEth()`. The delta is attributable to gas alone.

I strengthened this independently with a monotone scan (`test/attacks/M1b_Probe.t.sol`,
**new file, PoC untouched**), which reproduces the effect as a clean dose-response — this is a far
better control than a two-point comparison:

```
cap 1.00M -> revert (used 23,882)      open 4 (unchanged)
cap 1.10M -> ok, used   554,099        open 3
cap 1.20M -> ok, used   780,029        open 2
cap 1.30M -> ok, used   880,287        open 2
cap 1.40M -> ok, used   880,287        open 2
cap 1.50M -> ok, used   880,287        open 2
cap 1.60M -> ok, used 1,087,418        open 1
cap 1.90M -> ok, used 1,393,715        open 0
```

Kills are strictly a function of the supplied gas cap. Confirmed.

## 3. The crux — why doesn't `_afterSwap` clean up? — VERIFIED

`CauldronHook.sol:1006` really does run a second sweep:

```solidity
_liqSweep(sender, int256(0), false, 0); // post-trade: catches what the trade just moved
```

but with `amountSpecified == 0` it takes the *other* branch of line 799:

```solidity
uint256 reserve = amountSpecified != 0 ? LIQ_GAS_RESERVE + LIQ_GAS_MIN : LIQ_GAS_RESERVE;
uint256 g = gasleft();
if (g > reserve + LIQ_GAS_MIN) {
    perpEngine.call{gas: g - reserve}(...)
```

so post-trade it *fires* whenever `gasleft > 580_000`, forwarding `g - 180_000`. The engine then
breaks at `PerpEngine.sol:1166`:

```solidity
if (gasleft() < SWEEP_KILL_RESERVE) break;   // SWEEP_KILL_RESERVE = 420_000 (PerpEngine.sol:429)
```

**Measured marginal cost of one in-swap kill = 439,739 gas** (`test_single_kill_marginal_cost`:
776,598 with one kill vs 336,859 on an empty book). So for `_afterSwap` to land even **one** kill it
needs `180k + 420k + ~440k ≈ 1.04M` gas still remaining *after* the user's swap has already run.

That is the defect, and it is visible directly in the scan: at caps 1.30M / 1.40M / 1.50M the
transaction consumes an **identical 880,287 gas** and leaves **two shorts open**, i.e. at the 1.50M
cap roughly **620k of supplied gas is never spent** while insolvent positions sit open. The
post-trade sweep's firing threshold (580k) is *well below* the ~1.04M it needs to kill anything, so
it enters, scans, and returns having done nothing. `MAX_LIQ_PER_SWAP = 8` (`PerpEngine.sol:186`) is
not binding at N=4, and the rotating cursor is not the cause — pure gas arithmetic is.

The hunter's framing ("afterSwap never gets a chance") is **wrong in detail but right in effect**:
afterSwap *does* get called and *does* pass its own gate; it simply cannot afford a kill. The finding
survives, on a mechanism I verified rather than accepted.

**One-line falsifier I tried:** if the mechanism were wrong, raising only the cap while holding
everything else fixed would not change `openCount`. It does, monotonically (scan above). I could not
construct a change to the PoC that makes it fail while leaving the hunter's mechanism intact.

## 4. The secondary "fires but cannot kill" band at the PRE-trade gate — REFUTED

Fine scan at 10k granularity (`test_fine_band`):

```
cap 1,000,000 .. 1,060,000 -> revert (used 23,913), open unchanged
cap 1,070,000 .. 1,110,000 -> ok, used 554,130, open 3   <-- ONE kill at the very first passing cap
cap 1,120,000              -> ok, used 612,104, open 2
```

The **first** cap that clears the gate already performs a kill. There is no region where the
pre-trade sweep fires and buys zero liquidations. The hunter's DERIVED 70k band does not exist.

Correspondingly the comment at `CauldronHook.sol:829` —

```
//  Trade-off, stated plainly: a swap on a pool with a live perp book
//  that supplies under ~1.05M gas now REVERTS instead of filling.
```

— is **accurate**: the measured tx-level revert boundary is between 1.06M and 1.07M. The "comment
disagrees with code" sub-claim is refuted; the 980k figure is `gasleft` *inside* `_liqSweep`, which
is ~80k below the tx-level cap. Not a finding.

## 5. Attacker control over forwarded gas through a routed path — DERIVED

The PoC uses a direct `address(this).call{gas: cap}`. On the target chain the swap arrives through
the Universal Router, adding frames above the hook; EIP-150's 63/64 rule means each frame passes on
at most 63/64 of what remains, so the hook sees *less* than the tx cap. That shifts the attacker's
required cap **up** by ~1.6% per frame (≈2-4% for UR → PoolManager → hook), it does not remove the
band: the attacker still sets the tx gas limit and the response is monotone and smooth over a
~600k-wide window (1.07M → 1.9M above), which is far wider than the few-percent 63/64 shrinkage.
I did not execute a Universal-Router-routed variant; tagged DERIVED, not VERIFIED.

## 6. Reachability — VERIFIED

`openShort` is a public user entrypoint (`PerpEngine.sol:1003`); the PoC's four shorts are opened by
`victim` with ordinary `openShort{value: 0.5 ether}(2, 0, 0, 0.5 ether)` calls, no role, no cheat.
An open book with several levered shorts is the protocol's *intended* steady state, and the brief's
chain facts (pending-block calldata is fully visible; the v4 PoolManager holds 21,218 ETH borrowable
fee-free) mean the attacker can both *see* the book and fund the 40 ETH buy. No contrivance.

## Severity

Held at **High**, with one honest qualification: the PoC demonstrates **protocol loss**, not
**attacker profit** — 4.36 ETH of bad debt on a 30 ETH PLV (14.5%) lands on stakers, while the
attacker's edge is a normal buy executed at negative marginal cost (they save the gas of the kills
they refuse to fund and receive the keeper rewards they forgo). It is griefing plus a systematic
staker drain, repeatable every block, not a direct extraction. That is enough for High given PLV is
the staker backing, but it should not be written up as theft.

## Policy vs calibration — kept apart

The owner's accepted trade-off is: *a swap against a pool with an open perp book must supply high gas
or revert* (`CauldronHook.sol:806-829`). **That policy is not what fails here and I am not
questioning it.** What fails is the *calibration*: the gate is a constant (`LIQ_GAS_RESERVE +
2 * LIQ_GAS_MIN`) that is independent of `openCount()` and of how many positions the incoming
`amountSpecified` will bankrupt, and the post-trade sweep's firing threshold (580k) is set ~460k
below the ~1.04M it actually needs to kill one position. The gate therefore passes trades it was
specifically introduced to refuse — it fails at the very job the policy accepted a liveness cost for.

## Constraints on a fix (HYPOTHESIS — the fixer owns the remedy)

I am deliberately not prescribing one; a previous verifier's remedy here would have broken pool
routability. Constraints any fix must respect:

- It must not raise the floor when `openCount() == 0`, or ordinary routed swaps on a quiet pool start
  reverting and the pool stops being routable by aggregators.
- Any `openCount()`-proportional floor must stay bounded — `MAX_OPEN_POSITIONS` positions must not be
  able to push the required gas past a block limit, or a large book becomes a self-inflicted DoS on
  the pool.
- The two thresholds that are currently inconsistent are the post-trade *firing* threshold
  (`LIQ_GAS_RESERVE + LIQ_GAS_MIN = 580k`) and the post-trade *per-kill* requirement
  (`LIQ_GAS_RESERVE + SWEEP_KILL_RESERVE + ~440k ≈ 1.04M`). Firing below the second number burns gas
  for nothing.
- The relevant quantity is "positions the incoming trade will bankrupt", which is not the same as
  `openCount()`; computing it in `beforeSwap` is itself gas.
- Any change must keep `_liqSweep` unable to revert on the post-trade path (`CauldronHook.sol:818-821`
  states that intent) — only the pre-trade path may revert.

## Artifacts

- PoC re-run unmodified: `/tmp/rh-blind-h1/test/attacks/M1a_LiqGasBand.t.sol`
- New verifier probe (added, nothing weakened or deleted): `/tmp/rh-blind-h1/test/attacks/M1b_Probe.t.sol`
  — `test_band_scan`, `test_single_kill_marginal_cost`, `test_fine_band`, all passing.

## Discards

**2** of 3 claims knocked down: the ~70k "fires but cannot kill" pre-trade band, and the
"comment at :829 disagrees with the code" sub-claim. The primary claim survived every attack I
could mount, including the afterSwap counter-argument, which turned out to *explain* the bug rather
than refute it.
