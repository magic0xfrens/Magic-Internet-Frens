# E1 — Flashloan adversary report

Target: `/tmp/rh-blind-h2` (copy of `contracts/solidity`). Fork: Sepolia v4
(`POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`). All fork PoCs
compiled with `FOUNDRY_OPTIMIZER_RUNS` overridden (see F-ICE) — findings below are
about **logic** (a price reachable / a budget spent), which the workaround does
not affect.

---

## (1) Findings

```
id: E1A   severity: High   confidence: VERIFIED (real engine, real v4 pool, no mocks)
subsystem: cauldron/PerpEngine.sol
  :1042 function liquidate(uint256 id) external ...            // permissionless
  :1046   (bool trip, bool insolvent, uint256 notional) = _liqTest(p);
  :1580-1582  uint160 pj = _projSqrtP; uint160 sp = pj != 0 ? pj : _sqrtP();
              if (sp != 0) insolvent = _insolventVal(p, _quoteAt(p.size, sp));
              // OFF the in-swap sweep _projSqrtP==0 -> sp = LIVE SPOT
  :1658-1660  uint160 band = mode == MODE_DEATH ? bandLimit(...) : 0;  // NO band on LIQUIDATION
  :1696       _buyUpTo(p.size, backing + insuranceEth + plv, band); // budget includes ALL plv
  :1703       if (cost > backing) _absorbPlvLoss(cost - backing);   // overspend hits insurance then plv
title: Anyone can force-liquidate a HEALTHY short by pushing spot in one tx; the
  band-less buy-back then overspends the vault (plv) at that inflated live spot,
  socializing the loss onto stakers and destroying the victim's position.
precondition: any open short exists (permissionless to create). Attacker needs
  transient ETH to move spot on the (single-digit-ETH launch) pool. No role.
sequence:
  1. victim: openShort{value:0.02e18}(2,...)  -> healthy (liquidate reverts Healthy()).
  2. attacker: buy token with borrowed ETH (front-run) -> spot up.
  3. attacker: liquidate(id) -> _liqTest uses LIVE SPOT (_projSqrtP==0) -> short is
     "insolvent" at the pushed spot -> MODE_LIQUIDATION, band=0, budget incl. all plv
     -> forced market buy of p.size at the inflated price -> _absorbPlvLoss drains plv.
  4. attacker: sell the token back (back-run).
capital: push size only; FLASHLOANABLE yes (v4 PoolManager unlock(), 21,218 ETH
  fee-free atomic on target chain). Available today.
attacker_cost: gas + sandwich slippage. MEASURED at 0.02-ETH short / 1-ETH push:
  attacker net -0.0147 ETH (pure swapper is fee-negative at dust scale).
damage: MEASURED plv 5.000 -> 4.9692 ETH = 0.0307 ETH drained from stakers to close
  a position whose entire collateral was 0.02 ETH (~1.5x the collateral, socialized);
  PLUS the victim loses their position + liq penalty. Scales with the short's size
  and the push; at low-tens-of-ETH TVL a whale-sized victim short drains proportionally.
poc: audit/RH_MAINNET_2026-09-16/poc/e1/E1A_LiqBuyBackSandwich.t.sol  needs_fork: yes
```

Why HIGH not Critical: the *staker drain* and *victim destruction* are VERIFIED and
permissionless, but the drained ETH lands in the pool; capturing it as **net
attacker profit** requires the attacker to be the pool LP (so the forced inflated
buy is bought back fee-free on LP withdrawal) rather than a pure swapper. As a pure
swapper the hook's ~3% fee on both sandwich legs makes it fee-negative at the scale
tested. The LP-capture extraction is **DERIVED** (not built): it assumes the
attacker holds a dominant share of pool liquidity so the engine's `cost` ETH accrues
to their LP position — realistic on a fresh single-digit-ETH launch pool. The
griefing/liveness damage alone (destroy any short + socialize a >collateral loss for
gas) already voids the "attacker is a loss-maker" defense per the brief.

The code's own defense comment (`:1569-1573`) claims using the *projected* post-trade
price stops "an atomic crash-and-restore [farming] a liquidation." That guard only
applies to the in-swap sweep path where `_projSqrtP != 0`. The **permissionless
external `liquidate()` still judges insolvency at raw live spot**, so the exact class
the guard exists for is open on the entrypoint anyone can call.

```
id: F-ICE  severity: Low (build integrity)  confidence: VERIFIED
subsystem: cauldron/PerpEngine.sol (+ test harness under the cauldron profile)
title: solc 0.8.30 ICE "Assembly exception ... Tag too large for reserved space"
  when a test contract inheriting the PerpEngine fork harness is compiled under the
  project `cauldron` profile (via_ir=true, optimizer_runs=1).
repro: FOUNDRY_PROFILE=cauldron forge test --match-path test/attacks/E1A*.t.sol
  -> "Internal compiler error ... CompilerStack.cpp(1476) ... Tag too large for
  reserved space." Overriding FOUNDRY_OPTIMIZER_RUNS (0 or 50) compiles cleanly and
  the run is green. The ICE is optimizer-runs-sensitive and flaky.
note: not an attack, but a source unit that crashes the project's own compiler
  profile is worth resolving before a mainnet build; it also means any gas figure
  under the override is not production gas.
```

---

## (2) Re-priced

- **L1 (band-less short buy-back) — RE-RAISE, and the trigger is cheaper than H2
  thought.** H2 framed the trigger as a *sustained 5-min TWAP push*. In fact the
  permissionless `liquidate()` insolvency test falls back to **live spot**
  (`_projSqrtP==0` off the sweep, PerpEngine.sol:1581), so **no TWAP hold is
  needed** — a single-tx spot push suffices (E1A, VERIFIED). `twapWindow` default
  = 5 min (`:281`), `MIN_TWAP = 1 s` (`:311`); on ~100 ms blocks a 5-min TWAP spans
  ~3000 blocks and is NOT flashloanable, but the live-spot external path makes that
  irrelevant.
- **Same-block TWAP mark manipulation — ACCEPT-STILL-HOLDS.** Not needed for E1A;
  did not re-attack it.
- **Large-push variant reverts (partial refutation of a stronger brick claim):** at
  a 200-ETH push the forced buy-back's `cost` (~5.2 ETH) exceeds the engine's ETH
  balance and `PoolManager.settle{value:...}` reverts, so `liquidate()` reverts
  whole — i.e. the budget bound at `:1696` is NOT tight to the engine's balance
  despite the `:1826` comment ("by construction <= the engine's own balance"). This
  bricks that *specific* over-push, but the attacker simply pushes less (E1A uses
  1 ETH and succeeds), so it caps the per-tx drain rather than preventing it. Lead
  L4 below.

---

## (3) Refutations

- **Pure-swapper extraction at dust scale FAILS.** E1A measured the attacker net at
  **-0.0147 ETH** (fee-negative) for a 0.02-ETH short and a 1-ETH push. The failed
  profit assertion is why E1A asserts on the *plv drain* (VERIFIED) and the
  *victim destruction*, not on attacker PnL. Extraction needs the LP-capture variant
  (DERIVED, L3).

---

## (4) Leads

- **L3 (extraction, next step):** repeat E1A with the attacker minting a dominant v4
  LP position (PositionManager) before the sandwich, then `decreaseLiquidity` after,
  and assert attacker ETH strictly increases. Expectation: the engine's `cost` ETH
  (incl. the plv overspend) accrues to the attacker's LP share fee-free. If positive,
  E1A becomes a Critical extraction.
- **L4 (brick, next step):** find the push size where the forced buy-back's `cost`
  first exceeds the engine's native balance so `liquidate()` reverts (settle
  underfunded), then check whether an *honestly* insolvent short at that spot is
  permanently unliquidatable via `liquidate()` while the in-swap sweep is gas-gated —
  a possible liveness brick of the loss-clearing promise.
- **L2 (`_utilGate` pin) — untested.** `maxUtilBps=8000` (`:272`), `_utilGate` at
  `:2021`. Whale pins 80% util to force 80% of any LP withdrawal to queue. Per-block
  hold cost on a 100 ms chain not yet quantified.
```

---

## (5) L3 / L4 follow-up — E1A is CRITICAL (net extraction), L4 is a transient DoS

**L3 — the pure-swapper net crosses POSITIVE at the protocol's own max short size.
E1A upgrades from High to CRITICAL, and no LP position is required.**

The dust-scale −0.0147 ETH in E1A was an artifact of a 0.02-ETH short. The
per-position notional is capped at `maxNotionalBps = 500` = 5% of pool depth
(PerpEngine.sol:172, enforced in `_checkNotional` :1961 — which reverts
`BadLeverage()`, why the first larger-short attempts failed). Sizing the short at
90% of that cap and re-running as a **pure swapper** (front-run buy, `liquidate()`,
back-run sell — all atomic, borrowed capital):

| push | short coll | plv drained | attacker NET (pure swapper) |
|------|-----------|-------------|------------------------------|
| 1 ETH | 0.045 ETH | 0.0719 ETH | **+0.0435 ETH** |
| 3 ETH | 0.045 ETH | 0.4400 ETH | **+0.2720 ETH** |

VERIFIED (real engine + real v4 pool, no mocks) —
`poc/e1/E1B_LiqDrainScale.t.sol`, both tests PASS with `healthyPre=true` and
`cleared=true` asserted. Crossover is BELOW the 0.045-ETH cap size, so at every
legitimately-openable short size at/above ~5%-of-depth notional the attack is net
profitable **without owning any LP** — the earlier "LP-capture required" caveat is
withdrawn. Capital is the flashloanable v4 unlock() push, repaid in the same tx.
Damage per liquidation is bounded by ~5% of pool depth (the notional cap), but the
attacker can repeat across up to `MAX_OPEN_POSITIONS = 64` shorts and every honest
short on the book is a free target. **Severity: Critical** (permissionless atomic
extraction from staker capital; force-liquidates healthy positions).

Note the drain (0.44 ETH) exceeds the attacker's take (0.272 ETH) at push 3 — the
difference leaks to the pool LP and fees, so an attacker who ALSO holds the LP nets
strictly more (unbuilt, still DERIVED, but no longer needed to reach Critical).

**L4 — over-push settle-revert is a TRANSIENT DoS, NOT a permanent brick.**
`poc/e1/E1C_OverpushBrick.t.sol` (PASS): a 300-ETH push makes the buy-back `cost`
exceed the engine's ETH balance, so `PoolManager.settle{value:...}` reverts and
`liquidate()` reverts whole (`liquidate reverted under push: yes`). But after the
attacker's push is undone and spot is restored, the owner's `close(id,0)` succeeds
(`position closed after restore: yes`). So the position is recoverable by restoring
spot; the brick is not permanent. Severity: Low/Medium transient griefing — an
attacker can only block liquidation of a target while actively holding spot pushed
(capital-bound, not flashloan-atomic since it must persist), and anyone can restore
spot and proceed. The revert is a value-logic revert (`settle{value}` > balance),
independent of the optimizer; it reproduced at `FOUNDRY_OPTIMIZER_RUNS={0,50}`. It
could NOT be checked at the shipping `optimizer_runs=1` because that triggers the
F-ICE compiler crash — but since the cause is a balance comparison, not gas, it
transfers.
