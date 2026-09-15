# R45 NEIGHBOURHOOD RE-HUNT — today's five edits

Tree: /tmp/r45-rehunt/contracts/solidity. PoCs: `test/attacks/NA_*.t.sol`, `test/attacks/NB_*.t.sol`.

## 1. WHAT I CHECKED

**CauldronHook.sol `_liqSweep` + `LiqGasStarved` (797-836).** Read the whole branch and the
constants it depends on (`LIQ_GAS_RESERVE = 180_000` :167, `LIQ_GAS_MIN = 400_000` :178).
Property tested: *the new revert is not merely a floor the attacker can step over* — i.e. there
must be no gas cap at which the swap LANDS (no revert) and the pre-emptive sweep nevertheless
kills nothing, because the floor (`g > 980_000`) and the gas the engine actually needs to make a
kill (`SWEEP_KILL_RESERVE = 420_000` forwarded, PerpEngine.sol:429/1166, plus one
`_pokeFunding`) are two different numbers. Method: fork PoC, full-size crash sell executed under
61 explicit transaction gas caps from 900k to 2.4M in 25k steps, checking `(landed, victim still
open, victim insolvent)` at each. Also confirmed the exact-output quadrant still reaches
`_liqSweep` before the early return (:1327-1330) and that the engine's own settlement swaps are
excluded by `sender == perpEngine` (:798).

**PerpEngine.sol `_doSweep` (1112-1190).** Read the loop and its two remaining bounds
(`scanned < len`, `len = _openIds.length <= MAX_OPEN_POSITIONS = 64` :198; `kills <
MAX_LIQ_PER_SWAP = 8` :186; `gasleft() < SWEEP_KILL_RESERVE` break :1166). Property tested:
with the positional `SWEEP_SCAN` cap gone, does the gas break really hold at the top of the
band — i.e. can a caller sit just above the hook's floor and get a scan that does no work? Tested
jointly with NA above (same 61-point gas scan).

**PerpVault.sol `settlePendingEth` / `settlePendingToken` / `claimPending*` (383-452, 611-653).**
Property tested: **idempotence and pro-rata fairness of the write-down** under a permissionless,
arbitrary-address, unlimited-frequency entrypoint. Method: non-fork PoC on the existing
`MockEngine` harness — two equal 10 ETH LPs, both queued, backing halved by bad debt; control
(one settle each) vs attack (80 settles aimed at one address).

**GachaLib.sol `resolveTickets` + `REANCHORED_SLOT` (78-88, 104-190).** Derived the slot
(`keccak256(abi.encode(bi, keccak256("cauldron.gacha.reanchored.v1")))`) and checked it cannot
alias a hook slot; checked the flag is keyed per BATCH INDEX (not per player, not global), is set
on the same line that re-stamps `commitBlock`, and is never cleared by any path (grepped
`_markReanchored` — one writer, no deleter). Checked the batch index namespace is never reused:
`batches` is only ever `push`ed (CauldronHook.sol:2462) and never deleted or reset on relaunch
(grepped `batches` across the hook and `cauldron/`), so a fresh generation's batch 0 cannot
inherit a stale "already re-anchored" flag.

**PoolOps.sol `seedFunding` / `_pullAsset` / `_pullEth` / `_peek` (1071-1250).** Checked the
peek-before-pull equality: `_peek` reads the same counter (`relaunchAsset[asset]`,
`relaunchETH`) that `releaseRelaunch*` returns in full (CauldronHook.sol:1833-1872 — `amount =
relaunchETH; relaunchETH = 0;` / `amount = relaunchAsset[asset]`), so peek == pull for a
well-behaved asset and no branch can pull-then-decline. Checked `_peek`'s failure mode: `if (ok
&& r.length >= 32)` leaves `v = 0`, which makes the branch DECLINE (no pull) — the safe side,
and `seedFunding` returning `(0,0,0)` reverts `NoLiquidityToSeed` before `markConsumed`.
Checked both siblings peek (`_pullEth` :1244 and `_pullAsset` :1225 — yes, symmetric).

## 2. FINDINGS

```
id: NB   severity: Critical   confidence: VERIFIED
subsystem: PerpVault exit queue
file:line: contracts/solidity/cauldron/PerpVault.sol:415-418
    function settlePendingEth(address user) external nonReentrant returns (uint256 stillOwed) {
        if (pendingEthOf[user] == 0) revert ZeroAmount();
        return _bankEthWriteDown(user);
    }
file:line: contracts/solidity/cauldron/PerpVault.sol:383-394
    function _bankEthWriteDown(address user) private returns (uint256 owed) {
        owed = pendingEthOf[user];
        if (owed == 0) return 0;
        uint256 capped = _haircut(owed, engine.totalEth(), pendingEth);
        if (capped < owed) {
            emit QueueWrittenDown(user, false, owed - capped);
            pendingEth -= (owed - capped);
            pendingEthOf[user] = capped;
            owed = capped;
        }
    }
file:line: contracts/solidity/cauldron/PerpVault.sol:371-377
    function _haircut(uint256 owed, uint256 backing, uint256 claims) private pure returns (uint256) {
        if (claims == 0 || backing >= claims) return owed;
        return FullMath.mulDiv(owed, backing, claims);
    }
title: Anyone can call settlePendingEth(victim) repeatedly to grind a queued LP's exit claim
       to ~1% of its pro-rata value, with the rest of the backing falling to the other queued
       claimants (the attacker included), for gas only.
precondition: The queue is insolvent (pendingEth > engine.totalEth()) with >1 queued address —
       exactly the state these two new functions were added to service, and the normal state
       after any bad-debt write-off. No role, no approval, no timing window.
sequence:
  1. attacker + victim each depositEth 10 ETH; the book lends all 20 (PLV free = 0).
  2. both withdrawEth(all shares) -> pendingEth = 20 ETH, 10 ETH each.
  3. 10 ETH of bad debt: engine.totalEth() = 10 ETH, backing is now half the queue.
  4. attacker calls vault.settlePendingEth(victim) 80 times (any caller, any address).
     Each call re-divides the victim's ALREADY-reduced nominal by a denominator that still
     carries the attacker's FULL nominal: 10 -> 5 -> 3.33 -> ... -> 0.1235 ETH.
  5. attacker calls claimPendingEth() -> paid 9.878 ETH of the 10 ETH backing.
  6. victim calls claimPendingEth() -> paid 0.1220 ETH (pro-rata share: 5 ETH).
attacker_cost: gas only. Whole attack test incl. setup and both claims measured at 1,103,148 gas
       (~1.1M gas, < 0.02 ETH at 15 gwei); the 80 settle calls are ~13.8k gas each and can be
       split across blocks. Zero ETH at risk.
damage: 4.878 ETH of a 5 ETH pro-rata entitlement moved from the victim to the other queued
       claimant (measured). Scales with the position; a pure vandal with no stake can burn the
       same value by settling every queued address except one, or all of them in rotation.
       Irreversible: the write-down is a state change with no upward path.
       The control test measured the weaker form of the same defect: ONE settle each already
       pays 4.2857 vs 5.7143 ETH purely by CALL ORDER, on two identical claims.
poc: test/attacks/NB_SettleSpamHaircut.t.sol   needs_fork: no
notes: The token twin is the same code shape and is DERIVED to carry the same defect —
       settlePendingToken PerpVault.sol:626-629 -> _bankTokWriteDown :612-623, identical
       `_haircut(owed, engine.totalTokenAssets(), pendingTok)` with the same non-idempotent
       `pendingTok -= (owed - capped)`. Not separately executed.
```

Observed under `-vv`: both assertions executed and reported (`victim paid 121951219512195110`,
`attacker paid 9878048780487804890`, `backing 10000000000000000000`). `grep -n "return;\|vm.skip"
test/attacks/N*.t.sol` — the only hits are inside the internal helper `_scan()` of NA (a search
that stops at the first hit); no top-level `test_*` contains `return;` or `vm.skip`.

## 3. REFUTATIONS

**CauldronHook `_liqSweep` / `LiqGasStarved` — HELD.** Hypothesis: the floor (980k at the hook's
frame) is below the gas the sweep needs to land a kill (420k reserve + a `_pokeFunding` write, in
a frame that only receives `g - 580_000`), so a band of gas caps exists in which the trade lands
with zero kills — reproducing the pre-fix bad debt at a slightly different cap. Attacked with
`test/attacks/NA_LiqGasBandBypass.t.sol`: a 45 ETH crash sell against an open 2x long, run under
61 distinct transaction gas caps from 900_000 to 2_400_000 in 25_000 steps, each from a fresh
state snapshot. Result: caps 900k-1,025k **revert** (`ok false`, LiqGasStarved); every cap from
1,050,000 upward lands the trade **and kills the victim** (`survived false` at all 55 landed
caps). `bandFound false`. Both NA tests PASS (`2 passed; 0 failed; 0 skipped`), including the
positive control (uncapped gas pre-empts, gas 1,697,462). The floor and the engine's
`SWEEP_KILL_RESERVE` do line up in practice: there is no landed-but-swept-nothing band at 25k
resolution.

**PerpEngine `_doSweep` unbounded scan — HELD (jointly with NA).** `scanned < len` with `len`
hard-capped at `MAX_OPEN_POSITIONS = 64` (:198, enforced at :1967 `if (openCount >=
MAX_OPEN_POSITIONS) revert OiCapped()`) plus `kills < MAX_LIQ_PER_SWAP = 8` (:186) plus the
`gasleft() < SWEEP_KILL_RESERVE` break (:1166) is a strictly stronger bound than the removed
positional cap, and the break degrades instead of reverting. The 55 landed swaps in NA all
completed with the sweep firing; no cap produced an OOG of the parent swap.

**GachaLib `REANCHORED_SLOT` — HELD.** The slot is `keccak256(abi.encode(bi, keccak256(
"cauldron.gacha.reanchored.v1")))` (:78-88) — a two-level hash in a namespace no hook declaration
can reach; it is keyed per batch index (correct granularity: per batch, not per player, not
global), set on exactly the line that re-stamps `commitBlock` (:171-175), and has exactly one
writer and no clearer. Batch indices are never recycled — `batches` is push-only
(CauldronHook.sol:2462) with no delete/reset on relaunch — so no future generation inherits a
stale flag and loses its one legitimate re-anchor. The second-expiry path sets `expired` rather
than rolling against `bh == 0` (:176-183) and still honours pity (:146-148), so every crystal
still resolves exactly once and the queue cannot wedge. DERIVED (read, not executed).

**PoolOps `_peek` / `_pullAsset` / `_pullEth` — HELD.** `_peek` reads exactly the counter the
release returns in full (CauldronHook.sol:1833-1872), so peek == pull and the pull-then-decline
strand cannot recur; a non-answering, short-returning or non-contract hook yields `v = 0`, which
makes the branch DECLINE rather than pull blind — fail-safe, and `seedFunding`'s `(0,0,0)` return
reverts before `markConsumed` so the proposal stays live. Both sibling branches peek. DERIVED.

## 4. LEADS (HYPOTHESIS — next step named)

- **L1 — token-side twin of NB.** `settlePendingToken` (PerpVault.sol:626) / `_bankTokWriteDown`
  (:612) are line-for-line the ETH shape. Next step: clone `NB_SettleSpamHaircut` onto
  `MockToken` + `lendToken`/`writeOffTok` and assert the same pro-rata invariant.
- **L2 — `_liqSweep` band at finer resolution.** NA scanned in 25_000-gas steps; a band narrower
  than one step would have been missed, and the 63/64 rule makes the hook-frame gas a coarse
  function of the cap. Next step: re-run `_scan` over 1_030_000..1_120_000 in 1_000-gas steps.
- **L3 — fee-on-transfer relaunch reserve.** `_pullAsset`'s peek equals the COUNTER, not the
  tokens that arrive; a fee-on-transfer quote makes `p >= MIN_SEED_UNITS` true on a nominal the
  registry does not hold. Next step: seed `relaunchAsset[FoT]` and run `seedFunding` against a
  2%-fee mock, asserting the registry's balance clears MIN_SEED_UNITS.
- **L4 — one legitimate re-roll survives the gacha cap.** The single re-anchor is still a free
  second draw for a player who declines a losing batch (peek at commit, let it age 256 blocks).
  Next step: measure the effective odds lift (2x at the limit) and decide if that is intended.
