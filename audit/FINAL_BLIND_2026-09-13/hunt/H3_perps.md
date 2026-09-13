# H3 — Perps subsystem (PerpEngine / PerpVault / PerpSwapLib / PerpMarkSource / PerpStakerOracle)

Branch `redteam/2026-09-11`. Work done in a decontaminated copy at
`/tmp/blind-final-h3/contracts/solidity`; line numbers match the real tree 1:1.
PoCs live at `contracts/solidity/test/attacks/K3{a,b,c}_*.t.sol`. All 7 tests pass:

```
forge test --match-path 'test/attacks/K3*' -vv   # 8 passed, 0 failed
```

---

## 1. Model from code

**PerpEngine** (2492 lines, one engine per protocol, serves every generation).
Entrypoints and gates:

- Permissionless: `openLong` / `openShort` (`_guardOpen`: summon warmup, ring warmup,
  `_isDead`, leverage tier), `close(id,minOut)` (trader-only), `liquidate(id)`
  (`_liqTest` + `_throttle`), `forceCloseDead` / `forceCloseAllDead` (`_isDead()` only,
  MODE_DEATH, `minOut = 0`, keeper cut), `syncGeneration`, `poke`, `fundInsurance`,
  `claimPayout`, `claimLiquidatorBadges`, `retirePayout` (owner, or anyone once
  `quote` has diverged).
- `hookAddr`-only: `sweepLiquidations`, `creditPerpFee`, `creditPerpFeeToken`,
  `creditPerpFeeAsset`. Self-only: `selfSweep`.
- `onlyVault`: `fundFromVault`, `fundTokenFromVault`, `withdrawPlvTo`,
  `withdrawPlvTokenTo`, `withdrawTokYieldTo`.
- `onlyOwner` (timelock): `setFees`, `setRisk`, `setTiers`, `setVaultSplit`,
  `setGuards`, `setRouting`, `setVault`, `setVaultLimits`, `setMinCollateral`,
  `skimInsurance`, `fundPlv`, `fundPlvToken`.

Counters: `plv` (quote-side LP), `longOiEth`, `plvToken` / `shortOiToken` (token side),
`insuranceEth`, `tokYieldEth` (segregated short-side reward pot) with the monotone
marker `tokYieldCumulative`, `payoutOwed`/`payoutOwedTotal`, `strandedToken`.
Value in: trader collateral (`_pullQuote`), vault deposits, hook fee credits,
`fundInsurance`. Value out: `_payOut`/`_pushQuote` (settlement residual, keeper cut,
dividend, treasury), vault withdrawals.

**PerpVault** two sides, both priced off engine counters: quote side
(`ethShares`/`pendingEth`, assets = `engine.totalEth() - pendingEth`) and token side
(`tokShares`/`pendingTok`, plus a MasterChef accumulator paying quote-denominated
short-side yield out of `tokYieldEth`).

Cross-subsystem: `quote` is a *cache* assigned only in `syncGeneration`;
`registry.generationQuote(gen)` is truth. `_isDead()` = quote divergence OR
`hook.isDead(primaryPoolId)`. `RedemptionExt.rotateSliceFrom` flips
`generationQuote` and then calls `syncGeneration` best-effort.
`CauldronHook.afterSwap` calls `sweepLiquidations(tx.origin)` with a gas cap.
`_currentTick` optionally delegates to `PerpMarkSource.weightedTick()`.

---

## 2. Findings

```
id: T3c   severity: Critical   confidence: VERIFIED
subsystem: PerpEngine / PerpVault / rotation
file:line: cauldron/PerpEngine.sol:1337
    if (vault != address(0) && IPerpVaultStake(vault).hasQuoteStake()) revert VaultStaked();
file:line: cauldron/PerpEngine.sol:1797
    if (quote != registry.generationQuote(gen)) return true;      // _isDead
file:line: cauldron/PerpEngine.sol:1748
    if (_isDead()) revert TokenDead(); // no leverage into a death
file:line: cauldron/PerpEngine.sol:2435
    if (vault != address(0) && IPerpVaultStake(vault).hasStakers()) revert BadParam();  // setVault
file:line: cauldron/RedemptionExt.sol:582
    generationQuote[gen] = toQuote;
file:line: cauldron/RedemptionExt.sol:617
    if (eng != address(0)) { try IPerpSync(eng).syncGeneration() {} catch {} }
file:line: cauldron/PerpVault.sol:190
    function hasQuoteStake() external view returns (bool) { return (ethShares | pendingEth) != 0; }
title: One wei of PerpVault quote-side stake permanently strands the whole perp
       engine the moment a governance-approved quote rotation completes — no new
       position can ever be opened again for that generation, and neither the
       timelock nor anyone else can break the deadlock.
precondition: A live quote rotation reaches its final slice (a normal, voted
       governance action) while ANY address holds quote-side vault shares. The
       deploy script itself creates one: deploy/DeployPerp.s.sol:235 seeds the PLV
       through `IPerpVaultDeposit(address(vault)).depositEth{value: seed}()`, which
       mints `ethShares` to the deployer and never burns them. A stranger can
       create another for 1 wei (`deposit` mints `amount*(ethShares+1e6)/(assetsEth()+1)`
       shares, PerpVault.sol:238, so 1 wei is enough).
sequence:
  1. vandal -> PerpVault.deposit{value: 1 wei}(1 wei)                 [cost: 1 wei]
  2. governance -> RedemptionExt.rotateSliceFrom(...) final slice.
     :582 sets generationQuote[gen] = USDG; :617 calls syncGeneration inside
     try/catch. syncGeneration reaches :1337, sees hasQuoteStake() == true and
     reverts VaultStaked(). The catch swallows it; the rotation reports success.
  3. `PerpEngine.quote` is still the OLD asset. `_isDead()` (:1797) now returns
     true unconditionally, because it compares the cache with generationQuote.
  4. anyone -> openLong / openShort  => reverts TokenDead() forever.
  5. timelock -> setVault(0) to unwire the vault => reverts BadParam() (:2435,
     hasStakers() is true). The recovery lever is itself vetoed.
  6. Only the vandal's own withdrawEth clears hasQuoteStake and lets a
     permissionless syncGeneration finally adopt the quote.
attacker_cost: 1 wei + ~90k gas. Zero if the operator's own PLV seed is the staker
       — then the strand happens on the first rotation with nobody attacking.
damage: The perp engine is switched OFF for the remainder of the generation
       (no opens, at any leverage, for any user). Every open position is
       simultaneously reclassified as DEAD, so `forceCloseDead`/`forceCloseAllDead`
       become callable by any stranger against SOLVENT positions with `minOut = 0`
       and a keeperBps (1.45%) cut of each trader's residual — the exact harm
       PerpEngine.sol:1785 records as a previously-fixed bug, re-entered through
       the quote-divergence branch. Recovery requires UNANIMOUS voluntary exit of
       every quote-side staker; a single holdout is a permanent veto until the
       next relaunch re-clamps the quote to native.
poc: contracts/solidity/test/attacks/K3c_RotationStrandsPerpEngine.t.sol   needs_fork: no
     - test_positive_engineAliveWhileQuoteAgrees      (positive liveness control)
     - test_positive_rotationAdoptedWhenVaultIsEmpty  (positive: rotation IS followed
       when nobody is staked — proves the guard, not the plumbing, is the cause)
     - test_attack_oneWeiOfStakeStrandsThePerpEngine  (the attack)
     - test_control_warmupIsClearedSoNotWarmCannotMasquerade (anti-vacuity: proves
       the `openLong` probe reaches the death gate rather than dying at NotWarm;
       time is read via `vm.getBlockTimestamp()` and the warp is asserted, because
       under this profile's viaIR build a `block.timestamp` read can be sunk past
       `vm.warp`)
```

```
id: T3a   severity: High   confidence: VERIFIED
subsystem: PerpVault — exit queue vs. deposit pricing
file:line: cauldron/PerpVault.sol:196
    function assetsEth() public view returns (uint256) {
        uint256 t = engine.totalEth();
        return t > pendingEth ? t - pendingEth : 0;          // <- SATURATES
    }
file:line: cauldron/PerpVault.sol:238
    shares = FullMath.mulDiv(amount, ethShares + OFFSET, assetsEth() + 1);
file:line: cauldron/PerpVault.sol:325
    uint256 capped = _haircut(owed, engine.totalEth(), pendingEth);   // LAZY write-down
title: A queued exit whose backing was wiped is only written down lazily, at claim
       time — so any deposit made before the claimant calls `claimPendingEth`
       is transferred to them 1:1 and the depositor's shares are worth zero the
       instant they mint.
precondition: The engine has taken bad debt while an exit sits in the queue
       (`pendingEth > totalEth()`). Reachable through the ordinary short
       buy-back overspend path (`_absorbPlvLoss`, PerpEngine.sol:2057) or a long
       whose proceeds fall short (`_replenishPlv`, :2048). The queued LP simply
       does not call `claimPendingEth`; calling it is what would write their
       claim down to zero.
sequence:
  1. alice -> depositEth(10 ETH); engine lends it to longs (100% utilised).
  2. alice -> withdrawEth(all): paid 0, queued 10 ETH. Shares burned;
     pendingEth = 10e18.
  3. Bad debt: totalEth() -> 0. Alice's nominal claim is still 10 ETH because
     _haircut has not run.
  4. bob -> depositEth(10 ETH). `deposit` has NO solvency gate. assetsEth() is
     0 (saturated), so bob mints 1e25 shares whose redeemable value is ~0.
  5. alice -> claimPendingEth(). backing (= totalEth() = 10 ETH, i.e. bob's
     money) >= claims (10 ETH), so _haircut does nothing and alice is paid
     10 ETH in full.
attacker_cost: 0 beyond the gas of step 5; alice's own principal was already lost.
damage: 100% of every deposit made into the vault while a stale underwater queue
       entry stands. Measured in the PoC: bob pays 10 ETH, bob's redeemable
       value < 1 gwei, alice receives 10.000 ETH.
poc: contracts/solidity/test/attacks/K3a_StaleQueueEatsDeposit.t.sol   needs_fork: no
     - test_positive_solventVault_queueAndDepositBothWhole  (control: solvent vault,
       both parties whole)
     - test_attack_staleQueueTakes100PctOfAFreshDeposit
```

```
id: T3b   severity: Medium   confidence: VERIFIED
subsystem: PerpVault token-side yield accumulator vs. the rotation write-off
file:line: cauldron/PerpEngine.sol:1359
    uint256 writtenOff = tokYieldEth;
    emit TokYieldWrittenOff(quote, writtenOff);
    uint256 sweep = plv + writtenOff + insuranceEth;
    plv = 0; tokYieldEth = 0; insuranceEth = 0;              // cumulative NOT rewound
file:line: cauldron/PerpEngine.sol:1897 / :2266
    tokYieldCumulative += toVault;     // monotone, the only two writes
file:line: cauldron/PerpEngine.sol:2296
    if (amount > tokYieldEth) revert PlvInsufficient();
file:line: cauldron/PerpVault.sol:405
    function claimTokYield() external nonReentrant returns (uint256 paid) {
        _syncTokYield(); _settleTok(msg.sender); _resetTokDebt(msg.sender);
        paid = tokRewardOwed[msg.sender];                    // ALL or nothing
        ...
        engine.withdrawTokYieldTo(paid, msg.sender);
title: A quote rotation zeroes the token-side reward pot but leaves the cumulative
       marker the vault derives entitlements from, so every staker who held shares
       across the rotation carries a permanently oversized `tokRewardOwed` and can
       never claim ANY short-side yield again — including the yield they earn after
       the rotation. There is no partial-claim path; the call reverts wholesale.
precondition: One completed quote rotation while token-side shares exist. The
       engine's own comment (PerpEngine.sol:1350-1358) frames the pot sweep as a
       "bounded, announced, one-time loss of accrued REWARD"; it is not bounded to
       the accrued amount, it poisons all future accrual for those stakers.
sequence:
  1. alice -> depositToken(1000). Short-side fees accrue 5 ETH
     (tokYieldEth = 5, tokYieldCumulative = 5).
  2. syncGeneration rotation branch: tokYieldEth = 0; cumulative stays 5.
  3. New fees accrue 1 ETH (pot 1, cumulative 6).
  4. alice -> claimTokYield(): owed = 6 > pot -> PlvInsufficient, reverts. Repeat
     forever: her owed only ever grows, and any other staker draining the pot
     makes it strictly worse.
  5. bob, who deposited AFTER the rotation, claims normally.
attacker_cost: none — this fires on the protocol's own governance action; a
       co-staker can also deliberately front-run to drain the pot first.
damage: all pre- and post-rotation short-side yield of every pre-rotation token
       staker, permanently unclaimable. Token PRINCIPAL is unaffected (asserted
       in the PoC), which is why this is Medium and not High.
poc: contracts/solidity/test/attacks/K3b_TokYieldLockout.t.sol   needs_fork: no
     - test_positive_tokStakerClaimsShortSideYield  (control)
     - test_attack_rotationPermanentlyLocksTokStakerOutOfFutureYield
     The mock engine mirrors PerpEngine.sol:1896-1897, :1359-1362 and :2295-2297
     line for line; the vault under test is the real PerpVault.
```

```
id: T3d   severity: High   confidence: DERIVED
subsystem: rotation interlock vs. the weighted mark
file:line: cauldron/PerpEngine.sol:844
    function blocksVolumeLink() external view returns (bool) {
        return openCount != 0 && markSource == address(0);
    }
file:line: CauldronHook.sol:1626
    if (perpEngine != address(0) && IPerpOpenCount(perpEngine).blocksVolumeLink()) {
        revert PerpsOpen();
    }
file:line: cauldron/RedemptionExt.sol:606 (the safety argument, verbatim)
    //  Doing it HERE is safe and needs no new guard: reaching this line
    //  required `linkVolume` to succeed earlier in this same call
    //  (:372), and that reverts `PerpsOpen()` unless `openCount == 0`
    //  (CauldronHook.sol:1518). So the book is provably empty right now,
title: With a `markSource` armed — the state the whole PerpMarkSource feature exists
       to reach — `blocksVolumeLink()` returns false regardless of `openCount`, so
       the rotation's "the book is provably empty right now" is false. The quote
       flips over an OPEN book, `syncGeneration` reverts `PositionsOpen()` inside
       the try/catch, and every solvent open position immediately becomes
       `forceCloseDead`-able by a stranger.
precondition: governance has armed `markSource` via `setRouting`
       (deploy/DeployPerp.s.sol:206-228 supports it behind `DEPLOY_MARK_SOURCE`),
       and a rotation's final slice lands with `openCount != 0`.
sequence:
  1. Any traders hold open positions.
  2. Rotation final slice: linkVolume passes (blocksVolumeLink false),
     generationQuote flips, syncGeneration reverts PositionsOpen, swallowed.
  3. `_isDead()` is now true for every position.
  4. attacker, one tx: swap to crash the (rotation-drained) primary pool, then
     `forceCloseDead(id)` for each long — `_settle(id, p, 0, MODE_DEATH, msg.sender)`
     (PerpEngine.sol:1168) runs with `ownerSlippage == false`, so the engine dumps
     `p.size` token at the crashed price with NO minOut — then buy the token back.
  5. attacker collects keeperBps (1.45%, PerpEngine.sol:1635) of each residual on
     top of the sandwich.
attacker_cost: pool round-trip fees + gas.
damage: each trader's equity is realised at an attacker-chosen price with zero
       slippage protection; the shortfall below principal lands on `insuranceEth`
       then `plv` via `_replenishPlv`. Plus the T3c strand for the rest of the
       generation.
poc: none — needs a live v4 pool + hook + governor fixture (fork). This is the
     highest-value item I could not execute inside budget.   needs_fork: yes
```

```
id: T3e   severity: Medium   confidence: DERIVED
subsystem: PerpMarkSource
file:line: cauldron/PerpMarkSource.sol:173
    function weightedTick() external view returns (int24 tick) {
        if (!armed) return 0;
file:line: cauldron/PerpEngine.sol:667-686 (_currentTick)
    ok := and(ok, eq(returndatasize(), 0x20))
    ...
    if (ok) return int24(v);
title: `weightedTick()` fails OPEN, not soft: an unarmed source answers a
       well-formed `int24(0)` — tick 0, i.e. price exactly 1:1 — and the engine's
       fail-soft branch accepts it because the staticcall succeeded with a full
       word. The primary-pool fallback is never reached.
precondition: `setRouting` wires a PerpMarkSource whose `setPrimary` has not run.
       `armed` is only set inside `setPrimary` (:118); the constructor leaves it
       false. Same shape, worse consequence, on a relaunch: `setPrimary` is
       `onlyOwner` (timelock) while relaunch is permissionless, and
       `syncGeneration` clears `markSource` on a QUOTE ROTATION (:1384) but NOT on
       a generation change — so between a relaunch and the timelock's re-arm the
       mark reads the OLD generation's dead, drainable pool. `setPrimary` also
       performs no pair/orientation check against the engine's own `_key()`
       (`addPool` checks against `primary`, :133-138, but nothing checks `primary`),
       so an inverted key silently inverts the whole mark.
attacker_cost: pushing a dead pool's tick costs dust.
damage: `_quoteMark` -> `_underwaterVal` -> liquidation for the entire book runs
       off a 1:1 (or foreign-pool) price. Solvent positions liquidatable, insolvent
       ones unliquidatable.
poc: none (operational precondition; stated as DERIVED)   needs_fork: yes
```

```
id: T3f   severity: Low   confidence: DERIVED
subsystem: partial short close
file:line: cauldron/PerpEngine.sol:1858
    function _rebook(uint256 id, Position memory p, uint256 newSize, uint256 newBacking) internal {
        p.size = newSize;
        p.collateral = 0;
        p.principal = newBacking;
file:line: cauldron/PerpEngine.sol:915
    uint256 notional = uint256(p.collateral) * p.leverage;
    int256 raw = (signed * int256(notional)) / 1e18;
    int256 cap = int256((uint256(p.collateral) * maxFundingBps) / BPS);
file:line: cauldron/PerpEngine.sol:1617
    uint256 penalty = (uint256(p.collateral) * liqPenaltyBps) / BPS;
title: Zeroing `collateral` on a partial close makes the remainder pay exactly zero
       funding for the rest of its life (notional and cap are both
       `collateral`-derived) and yields zero liquidation penalty and zero keeper
       reward on its final close — while the remainder is, by construction, the
       piece most likely to be insolvent.
precondition: a short whose buy-back cannot complete inside
       `backing + insuranceEth + plv` (thin pool relative to the debt).
damage: no direct theft; the crowded-side funding transfer leaks, and keepers have
       no economic reason to finish a remainder. Also: `_doSweep`'s cursor logic
       (:1132) treats a partial close as "no kill" and advances the cursor, but the
       id was swap-popped and re-pushed to the tail, so one open position is skipped
       per partial close in the rotating scan.
poc: none   needs_fork: yes
```

---

## 3. Refutations — surfaces I attacked hard that held

1. **`PerpVault._syncTokYield` underflow on a cumulative rewind.**
   `uint256 delta = cum - lastTokYieldCum;` (PerpVault.sol:369) is checked
   arithmetic with no `unchecked`. If the engine ever *decreased*
   `tokYieldCumulative`, `_syncTokYield` would panic and take `depositToken`,
   `withdrawToken` and `claimTokYield` down permanently. I grepped every write:
   PerpEngine.sol:1897 and :2266 are the only two and both are `+=`. The rotation
   write-off (:1362) zeroes `tokYieldEth` and deliberately leaves the marker alone.
   **Holds** — and that same choice is what produces T3b, so the two are the two
   halves of one design decision.

2. **First-depositor / donation share inflation on either vault side.**
   `OFFSET = 1e6` (PerpVault.sol:63) with `mulDiv(amount, shares + OFFSET, assets + 1)`.
   I attacked it with a 1-wei seed plus a large direct PLV donation in the K3a
   fixture's precursor; the victim's redeemable value stayed within a wei of their
   deposit. **Holds.**

3. **`retirePayout` as a burn-someone-else's-escrow primitive.**
   PerpEngine.sol:2029 gates the unprivileged branch on the push actually
   succeeding (`if (!_tryPush(to, amount, false) && !priv) revert EthSend();`), and
   the effects at :2019-2020 land before it, so a failed push rolls the whole
   retirement back and the claim survives. **Holds.**

4. **`_absorbPlvLoss` / `_replenishPlv` underflow.**
   Both saturate (`plv = plv > rest ? plv - rest : 0`, :2062; `cover = min(...)`,
   :2050), so an extreme gap degrades rather than bricking the settlement.
   **Holds.**

5. **`fundTokenFromVault` / `withdrawPlvTokenTo` reading `registry.currentToken()`
   while `plvToken` is denominated in `syncedToken`.** I chased the window between
   a relaunch flipping `currentToken()` and `syncGeneration` re-pointing
   `plvToken`. `CauldronRegistry.sol:1163` calls `syncGeneration` in the same
   transaction as the relaunch, and `PerpSwapLib.migrateInventory` (:311-338) is
   fully non-reverting by construction (low-level `call`, shortfall emitted rather
   than thrown), so the sync does not fail on the migration leg and the window is
   atomic. **Holds** on the paths I could reach.

---

## 4. Leads (HYPOTHESIS — exact next step for each)

- **L1 — the spot leg of `_liqTest` as an in-swap extraction.**
  PerpEngine.sol:1451-1454 adds a zero-buffer SPOT insolvency trigger that is
  exempt from `_throttle` (:1503). An attacker who pushes spot up past a short's
  entire equity in one swap gets `liquidate` (or the afterSwap sweep) to force the
  engine to buy the token back at the price they just made — the engine's forced
  buy is their exit liquidity — plus the keeper cut. The file argues the impact
  must be paid into the same pool the settlement unwinds against; that is true but
  not obviously sufficient once the attacker is also the LP on the other side.
  *Next step:* fork fixture, seed a concentrated position, measure attacker P&L
  across (push, liquidate, unwind) as a function of pool depth vs. victim equity.

- **L2 — `_buyUpTo` budget includes the whole `plv`.** PerpEngine.sol:1533
  `_buyUpTo(p.size, backing + insuranceEth + plv)`. A single bad short can spend
  every wei of LP principal on one buy-back before `_absorbPlvLoss` socialises it.
  *Next step:* check whether a cap at `backing + insuranceEth + maxUtilBps·plv`
  changes any existing test, and quantify the worst single-position drain.

- **L3 — `PerpStakerOracle` (32 lines) is entirely unexercised by my pass.**
  `isInstant(address)` (:29) is the only logic; I did not find a production
  consumer. *Next step:* `grep -rn "PerpStakerOracle\|isInstant"` across the tree
  including the frontend/indexer; if it has no consumer it is dead code on a
  security-relevant name.

- **L4 — `_doSweep` cursor skipping.** See T3f's second paragraph. *Next step:*
  a unit test that parks N liquidatable positions and asserts every id is reached
  within N swaps, with one partial close in the middle.

- **L5 — `syncGeneration` reverts if `registry.currentToken()` has no code**
  (`IERC20(newTok).balanceOf(address(this))`, PerpEngine.sol:1232, unguarded).
  Everything else on that function's path is best-effort. *Next step:* determine
  whether any legitimate registry state (pre-first-summon, mid-relaunch) can make
  `currentToken()` a codeless address.
