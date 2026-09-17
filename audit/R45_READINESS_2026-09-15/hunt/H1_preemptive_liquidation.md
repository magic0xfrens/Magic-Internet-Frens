# H1 — Pre-emptive liquidation (CauldronHook beforeSwap/afterSwap → PerpEngine → PerpSwapLib)

Tree: `/tmp/r45-blind-h1/contracts/solidity` (line numbers identical to the real tree).
Run: `FOUNDRY_PROFILE=cauldron forge test --match-path 'test/attacks/R1*.t.sol' -vv --skip 'lib/v4-periphery/lib/permit2/script/**'`
Ground truth: 3 suites, 2 passed (the two positive controls), 3 failed (the three attack assertions). Fork-gated: every PoC asserts `ran == true` first, so a silent skip cannot produce a green run.

---

## 1. MODEL FROM CODE

**Entrypoints and gates.**
- `CauldronHook._beforeSwap` — v4 `PoolManager` only. Gates: `_inSelfBuy || _inRelaunchClose` early-out (`CauldronHook.sol:1241`); adoption gate `if (!trackedPools[id]) return` (`:1244`); `if (!exactInput && !inputIsQuote) revert ExactOutSellUnsupported()` (`:1290`). Then **ungated** `_liqSweep(sender, params.amountSpecified, inputIsQuote, params.sqrtPriceLimitX96)` (`:1291`). `inputIsQuote = params.zeroForOne == q0` (`:1268`).
- `CauldronHook._afterSwap` — same two gates (`:813`,`:815`); post-trade `_liqSweep(sender, 0, false, 0)` (`:969`).
- `CauldronHook._liqSweep` (`:791`) — private; gated only on `perpEngine != 0 && sender != perpEngine`, and on **gasleft()**: `reserve = amountSpecified != 0 ? LIQ_GAS_RESERVE + LIQ_GAS_MIN : LIQ_GAS_RESERVE` then `if (g > reserve + LIQ_GAS_MIN)`. Result discarded (low-level `.call`).
- `PerpEngine.sweepLiquidations(liquidator, spec, isBuy, limit)` (`:1050`) — `if (msg.sender != hookAddr) revert OnlyHook()`.
- `PerpEngine.selfSweep` (`:1085`) — `msg.sender == address(this)`.
- `PerpEngine.liquidate(id)` (`:1037`) — permissionless; `_liqTest` + `_throttle`.
- `PerpEngine.openLong/openShort` (`:964`,`:998`) — permissionless; `minCollateral = 0.003 ether` (`:182`), `MAX_OPEN_POSITIONS = 64` (`:198`), OI/util caps.

**Sweep body** `_doSweep` (`:1106`): `_liqReentry` guard → `_pokeFunding()` → rotating window `while (scanned < SWEEP_SCAN(12) && scanned < len && kills < MAX_LIQ_PER_SWAP(8))` (`:1126`), `if (gasleft() < SWEEP_KILL_RESERVE(420_000)) break` (`:1142`), `if (spec != 0) _projSqrtP = _project(spec, isBuy, limit)` (`:1155`), `_tryLiquidate` (`:1156`), cursor advances only on a non-kill (`:1159`), `_projSqrtP = 0` (`:1165`).

**Trigger** `_liqTest` (`:1530`): TWAP mark with `maintenanceBps`, OR zero-buffer insolvency at `sp = _projSqrtP != 0 ? _projSqrtP : _sqrtP()` (`:1556-1558`). Insolvent positions are **exempt** from `_throttle` (`:1594`).

**Projection** `PerpEngine._project` (`:1072`) feeds `PerpSwapLib.projectedSqrtPriceX96` (`:175`) with `_sqrtP()` and `activeEthDepth()` of **the engine's own `_pid()`** (`:596-604`, `:850`) — not the swapped pool's.

**Asset flows.** In: trader collateral (quote) on open; attacker swap input. Out: settlement proceeds to trader; `liqPenaltyBps = 690` of collateral (`:155`) split, `keeperBps = 145` (`:168`) to `liquidator` = `tx.origin` (`CauldronHook.sol:797`); shortfalls to `insuranceEth` then `_absorbPlvLoss` → PLV stakers (`:1679`).

**Cross-subsystem.** Hook fee/volume/death/gacha/legacy-buyback share the same `beforeSwap`/`afterSwap` gas budget; `PerpVault` holds the PLV that absorbs shortfalls; `CauldronRegistry` owns `trackedPools` adoption (`CauldronHook.sol:656`, `require(sender == registry)`).

---

## 2. FINDINGS

```
id: R1C   severity: Critical   confidence: VERIFIED
subsystem: CauldronHook pre/post swap liquidation sweep
file:line: contracts/solidity/CauldronHook.sol:161,172,791-799
    uint256 internal constant LIQ_GAS_RESERVE = 180_000;
    uint256 internal constant LIQ_GAS_MIN = 400_000;   // don't bother firing under this
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
title: Any swapper turns the entire liquidation engine off for their own trade — pre-trade AND post-trade sweep — by capping the transaction's gas, and walks a full-size price crash straight through the book.
precondition: None beyond an open position and a live pool. The swapper chooses their own gas limit; no role, no state, no spend. The hook's own note (CauldronHook.sol:165) puts the bare swap at ~103,857 gas against a 980,000-gas floor for the pre-sweep and 580,000 for the post-sweep.
sequence:
  1. victim (any address) opens a 2x long with 1 ETH: PerpEngine.openLong{value: 1 ether}(2, 0, 0, 1 ether). principal = 0.931 ETH.
  2. attacker acquires ~45 ETH-equivalent of the iteration token.
  3. attacker calls PoolManager.unlock{gas: 500_000}(...) wrapping an exact-input sell of that token.
     At beforeSwap gasleft() < 980_000 -> pre-emptive sweep skipped.
     At afterSwap  gasleft() <  580_000 -> post-trade sweep skipped.
  4. The swap SUCCEEDS (measured swapOk == true at gasCap 500_000).
attacker_cost: strictly LESS than a normal swap — a 500k gas limit is cheaper than the ~1.5M an unrestricted hook swap consumes. Zero protocol fee delta, zero extra ETH.
damage: measured badDebtGapWei = 307,979,144,626,939,095 (0.308 ETH) on a single 1-ETH-collateral 2x long, on a 60 ETH pool. The position is left OPEN and insolvent at the realized post-trade price. Staker loss is DEFERRED, not realized in-tx: the shortfall becomes insuranceEth/PLV loss only when the position is finally settled (PerpEngine.sol:1679 _absorbPlvLoss). Whether a later normal-gas swap recovers it depends on price path — see Lead L3. Scales linearly with position size and with the number of positions the trade bankrupts; every position on the losing side is missed by the same single capped transaction.
poc: test/attacks/R1C_GasFloorBypass.t.sol   needs_fork: yes
  attack  test_R1C_gas_capped_swap_skips_both_sweeps          FAILS ("I1 BROKEN: gas-capped swap left an insolvent position open"), assertion observed under -vv
  control test_R1C_positive_uncapped_gas_preempts             PASSES (same trade at full gas: victim is pre-empted, survivedPos == false)
```

```
id: R1B   severity: High   confidence: VERIFIED
subsystem: PerpEngine rotating-window sweep
file:line: contracts/solidity/cauldron/PerpEngine.sol:186,198,419,1126
    uint256 internal constant MAX_LIQ_PER_SWAP = 8;
    uint256 public constant MAX_OPEN_POSITIONS = 64;
    uint256 internal constant SWEEP_SCAN = 12;      // positions checked per swap
        while (scanned < SWEEP_SCAN && scanned < len && kills < MAX_LIQ_PER_SWAP) {
  and contracts/solidity/cauldron/PerpEngine.sol:182
    uint256 public minCollateral = 0.003 ether;
title: Pad the book with cheap positions the crash cannot liquidate, rotate sweepCursor with dust swaps, and a chosen position sits outside BOTH 12-slot windows of the killing swap — neither pre-empted nor cleaned up.
precondition: A book with more than 24 open positions. Anyone can create them: minCollateral is 0.003 ether (PerpEngine.sol:182) and MAX_OPEN_POSITIONS is 64 (:198), so 40 padding positions is entirely permissionless. The padding must be on the side the crash does NOT hurt (the PoC uses SHORTS against a down-move) so the sweep never kills them — a killed pad swap-pops the tail into the scanned slot (PerpEngine.sol:2032-2035) and would drag the victim back into the window.
sequence:
  1. attacker opens 40 shorts of 0.01 ETH each: PerpEngine.openShort{value: 0.01 ether}(2, 0, 0, 0.01 ether).  (0.40 ETH of collateral, recoverable by closing)
  2. victim opens a 2x long with 1 ETH (principal 0.931 ETH) — lands at the tail of _openIds.
  3. attacker issues dust sells (0.02 ETH-equivalent each) until the victim's index is >= 24 slots ahead of sweepCursor, i.e. outside the pre-sweep window [c, c+12) and the post-sweep window [c+12, c+24). PoC measured: 2 rotations sufficed ("windowSafe true rotations 2").
  4. attacker sells ~45 ETH-equivalent of token in one ordinary, full-gas swap.
attacker_cost: 0.40 ETH of padding collateral (returned on close, less open fees) + ~42 transactions of gas. Effective cost is the open-fee drag on 0.40 ETH plus gas, well under 0.05 ETH.
damage: measured badDebtGapWei = 315,255,392,517,555,254 (0.315 ETH) left OPEN and insolvent after the swap that bankrupted it. DEFERRED staker loss, same mechanism as R1C. The padding is also a standing griefing asset: 63 padding positions would additionally exhaust MAX_OPEN_POSITIONS and block all opens.
poc: test/attacks/R1B_SweepWindowStarvation.t.sol   needs_fork: yes
  attack  test_R1B_padded_book_strands_an_insolvent_position  FAILS ("I1 BROKEN: insolvent position still open after the swap that bankrupted it"), assertion observed under -vv
  control test_R1B_positive_short_book_is_preempted           PASSES (same 45 ETH crash on a 1-position book: victim pre-empted)
```

```
id: R1A   severity: Medium   confidence: VERIFIED
subsystem: PerpSwapLib projection slack -> PerpEngine zero-buffer insolvency trigger
file:line: contracts/solidity/cauldron/PerpSwapLib.sol:63,212,218-236
    uint256 internal constant SLACK_BPS = 1500;
        uint256 slackBps = SLACK_BPS;
        uint256 inflated = amountIn + FullMath.mulDiv(amountIn, slackBps, 10_000);
        if (inflated > reserveIn) inflated = reserveIn;
        uint256 ratio = 1e18 + FullMath.mulDivRoundingUp(inflated, 1e18, reserveIn);
  and contracts/solidity/cauldron/PerpEngine.sol:1556-1558
            uint160 pj = _projSqrtP;
            uint160 sp = pj != 0 ? pj : _sqrtP();
            if (sp != 0) insolvent = _insolventVal(p, _quoteAt(p.size, sp));
title: Because the projection inflates the pending input by 15% and then feeds a ZERO-buffer insolvency test, there is a band of trade sizes that force-closes a position which is still solvent at the price the trade actually leaves behind — a free kill with a keeper bounty attached.
precondition: One open leveraged position and a pool the attacker can move. No role, no special state. The attacker sizes their own trade to land the victim inside the slack band; the band is wider the closer the victim is to its threshold, so a victim near maintenance can be killed by an arbitrarily small trade.
sequence:
  1. victim opens a 2x long with 1 ETH (principal = 0.931 ETH). Pre-attack: perp.isLiquidatable(vid) == false (asserted, healthyBefore == true).
  2. attacker sells 22.25 ETH-equivalent of the token in one exact-input swap.
  3. beforeSwap -> _liqSweep -> sweepLiquidations -> _project -> _projSqrtP (15%-inflated) -> _liqTest reports insolvent -> _throttle exempts insolvent (PerpEngine.sol:1594) -> _settle(MODE_LIQUIDATION, liquidator = tx.origin).
  4. Realized post-trade valuation of the victim's size, measured with the protocol's own PerpSwapLib.quoteAt: 962,809,494,402,837,712 wei vs principal 931,000,000,000,000,000 wei — 3.4% ABOVE its debt, i.e. SOLVENT. (This figure is measured AFTER the liquidation's own settlement sell pushed price further down, so the counterfactual is more solvent still; the number is conservative.)
attacker_cost: the round-trip cost of a 22.25 ETH-equivalent sell on a 60 ETH pool — LP fee both legs plus the hook's ETH fee on the buy-back. Materially cheaper for a victim already near its threshold.
damage: the victim pays liqPenaltyBps = 690 (6.9% of collateral, PerpEngine.sol:155) and loses a solvent position; keeperBps = 145 of the penalty goes to the attacker as tx.origin, plus a Liquidatoor badge. Loss is REALIZED in the attacking transaction (the settlement executes in-tx). Per-victim bounded by collateral, so Medium rather than High — but it is the direct negation of invariant I2 ("no free kills") and it is permissionless and repeatable against every marginal position in the book.
poc: test/attacks/R1A_FreeKillSlack.t.sol   needs_fork: yes
  attack test_R1A_free_kill_inside_the_projection_slack  FAILS ("FREE KILL: liquidated while solvent at the realized price"), assertion observed under -vv; logs foundSellEthEq 22250000000000000000, realizedVal 962809494402837712, threshold 931000000000000000
  The same test asserts healthyBefore == true and diedInSwap == true before reaching the failing assertion, so the three-step claim (healthy -> killed -> solvent at realized) is all executed.
```

---

## 3. REFUTATIONS

**R-1. Huge-nominal swap with a limit at spot ("project a move the trade never makes"). HELD. DERIVED.**
`PerpSwapLib.sol:264-266`:
```
        if (limit != 0) {
            if (up ? (limit > sqrtP && out > limit) : (limit < sqrtP && out < limit)) out = limit;
        }
```
`up = isBuy ? !quoteIsCurrency0 : quoteIsCurrency0` (`:250`) with `quoteIsCurrency0 = true` (`:211`). I checked all four quadrants against v4's own limit semantics: a `zeroForOne` buy has `limit < sqrtP` and takes the `!up` branch; a `oneForZero` sell has `limit > sqrtP` and takes the `up` branch. In both, a projection that would overshoot the limit is pulled back to it, so the "huge amountSpecified + limit at spot" griefing shape cannot project past where the trade can physically go. YBase already carries the primitive for this shape (`_buyWithLimit`, `test/attacks/YBase.sol:235-241`, commented "huge nominal, limit at spot, so almost nothing fills"). I read the clamp in all four quadrants but did not execute a new PoC against it — DERIVED, not VERIFIED.

**R-2. Exact-output as the unprojected quadrant. HELD. DERIVED.**
`PerpSwapLib.sol:196-203` converts a positive (exact-output) `amountSpecified` into the input it will cost, `FullMath.mulDivRoundingUp(reserveIn, dOut, reserveOut - dOut)`, clamping to `reserveIn` when `dOut >= reserveOut`. `CauldronHook.sol:1291` passes v4's signed amount through unchanged, so exact-output buys ARE projected, and exact-output sells are refused outright at `:1290` for an unrelated fee reason. I worked the arithmetic for `dOut = reserveOut/2` (projection ratio 2 in sqrtP, i.e. 4x in price — exactly the constant-product answer) and for small `dOut`; the closed form is correct, not a bypass. Routability (I3) is preserved: exact-output single swaps are served, not reverted.

**R-3. Window starvation using LONG padding. REFUTED BY EXECUTION. VERIFIED.**
My first R1B built the padding out of 2x **longs**. It failed: the victim died even though it started outside both windows ("windowSafe true rotations 2" yet "survived false"). Cause, read after the failure: a kill does not advance the cursor and `_removeOpen` swap-pops the LAST id into the freed slot (`PerpEngine.sol:2032-2035`), so liquidating the padding actively drags the tail — the victim — into the scan window. The attack only works with padding the crash cannot kill. That is a genuine (undocumented) defensive property of the swap-pop, and it is why R1B's final form uses shorts. Worth keeping: any future change from swap-pop to ordered removal would widen R1B.

**R-4. `quoteIsCurrency0 = true` hardcoded in the library while `PerpEngine._key()` handles both orderings. HELD. DERIVED.**
`PerpSwapLib.sol:204-211` asserts the orientation is an invariant; `PerpEngine.sol:596-602` builds the key with `(q < t ? (q,t) : (t,q))` and its comment explicitly says an ERC20 quote "may land either side"; `CauldronHook.sol:1265-1268` also contemplates "an ERC20 quote at currency1". If `q0` could ever be false the projection would move the price the WRONG WAY and liquidate the opposite book. It cannot: `cauldron/PoolOps.sol:912` enforces it at deploy —
```
        require(token > quote, "order"); // the watermark invariant, asserted
```
so every protocol-created pool has the quote at currency0 and `inputIsQuote == zeroForOne`. Not exploitable; it is a latent coupling, not a live bug.

**R-5. `activeEthDepth()` manipulated to zero. HELD. DERIVED.**
`PerpEngine.sol:850-855` returns 0 when `_sqrtP() == 0`; `PerpSwapLib.sol:215` returns the CURRENT price unchanged when `sqrtP == 0 || reserveIn == 0 || amountIn == 0`, so an attacker who pushes price out of every LP range degrades the sweep to "liquidate only what is already underwater at spot" rather than to a fabricated projection. Fails safe.

**R-6. Reentrancy into the engine mid-sweep. HELD. DERIVED.**
`_doSweep` opens with `if (_liqReentry) return;` and sets `_liqReentry`/`_inLocked` around the whole loop (`PerpEngine.sol:1107,1121-1122,1163-1164`), `sweepLiquidations` is `hookAddr`-only (`:1051`), `selfSweep` is self-only (`:1086`), and `_liqSweep` early-returns when `sender == perpEngine` (`CauldronHook.sol:792`). I found no path that re-enters `_doSweep` from inside a settlement. Not tested with a hostile token — see Lead L4.

---

## 4. LEADS (HYPOTHESIS)

**L1 — Cross-pool projection contamination (highest-value open lead).** `CauldronHook.sol:1291` forwards the *swapped* pool's `params.amountSpecified`, `inputIsQuote` and `params.sqrtPriceLimitX96` into `sweepLiquidations`, but `PerpEngine._project` (`:1072-1077`) projects on the **engine's own** pool via `_sqrtP()`/`activeEthDepth()` of `_pid()` (`:596-604`). The only gate on the forwarding path is `trackedPools[id]` (`:1244`), which is true for every pool the registry adopted, including the rotation-destination siblings linked at `CauldronHook.sol:1683-1714`. A `sqrtPriceLimitX96` that is a tight, honest limit for sibling pool B is an arbitrary number relative to pool A's `sqrtP`, so R-1's clamp does not bind: for a buy the clamp needs `limit < sqrtP_A`, and a sibling with a different decimal/price scale routinely sits on the wrong side of that. A cheap partial-fill swap on the sibling would then project a full 4x move on the perp pool and mass-kill one side. **Next step:** in a YBase-derived test, drive a quote rotation to create a second tracked+linked pool, then fire an exact-input buy on the sibling with a huge nominal and a limit one tick below the *sibling's* spot; assert the perp book's positions die while the perp pool's own `sqrtP` is unchanged.

**L2 — Pre-sweep settlement pushes spot past the user's own price limit (routability / I3).** The pre-sweep's settlement swaps execute *before* the user's trade and move spot in the same direction as the user's trade. If they cross the user's `sqrtPriceLimitX96`, the user's own `PoolManager.swap` reverts with `PriceLimitAlreadyExceeded`, rolling the kills back too — so the condition is not self-clearing and every tight-slippage router buy in that state reverts. **Next step:** park one liquidatable short, then call `YBase._buyWithLimit` with a limit ~0.5% from spot and assert the revert; then assert that a wide-limit buy succeeds, proving the pool is selectively unroutable.

**L3 — Is the R1B/R1C staker loss recovered or realized?** Both leave an insolvent position OPEN; whether the eventual settlement charges `insuranceEth`/PLV depends on the price path between the attacking swap and the next full-gas sweep. I did not measure `perp.plv()`/`perp.insuranceEth()` before and after a full sequence. **Next step:** extend R1C with a second, normal-gas swap after the capped crash and assert `insuranceEth + plv` strictly decreases; that converts DEFERRED to REALIZED and would raise R1B to match R1C.

**L4 — Tick-boundary liquidity vs constant-product projection.** `PerpSwapLib.projectedSqrtPriceX96` models the pool as constant product on `activeEthDepth()` = `ethDepth(getLiquidity(id), sqrtP)` (`PerpEngine.sol:850-855`), which is the virtual reserve of the **currently active tick range only**. Within the range the model is exact; once the trade crosses out of the range the real move can exceed the projection (under-protection, the PLV-losing direction), and with liquidity concentrated in a thin band around spot and depth parked further out the projection can also overshoot (free-kill direction, R1A but larger). **Next step:** `_modifyLiquidity` a narrow band around spot plus a wide band outside it, then repeat R1A's minimum-kill search and measure how far the realized price diverges from the projected one in each configuration.

**L5 — 63 permanent dust positions.** `MAX_OPEN_POSITIONS = 64` (`PerpEngine.sol:198`) enforced at `_book` (`:1943`), `minCollateral = 0.003 ether` (`:182`). Filling 63 slots costs ~0.19 ETH and would refuse every other open. Recovery depends on whether the padding is ever liquidatable (a 1x long has zero principal, so `_underwaterVal`/`_insolventVal` can never trip it) and on `forceCloseAllDead` only being reachable once the token is dead. **Next step:** check whether `_guardOpen` (`:1856`) admits `leverage == 1`; if it does, assert that 63 such positions make a 64th open revert `OiCapped()` indefinitely and that neither `liquidate` nor the sweep can clear them while the token is alive.

**L6 — `SWEEP_KILL_RESERVE = 420_000` vs a measured kill.** `PerpEngine.sol:1142` breaks the loop below 420k, and the hook forwards `g - 580_000`. I did not measure the actual cost of one `_settle(MODE_LIQUIDATION)` iteration, so I cannot say whether the reserve is generous or whether the loop banks fewer kills than the constant implies. **Next step:** instrument `_tryLiquidate` with `gasleft()` deltas in a local build and compare against 420,000.
