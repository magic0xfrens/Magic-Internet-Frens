# H3 — Perps (PerpEngine / PerpVault / PerpSwapLib / PerpMarkSource / PerpStakerOracle)

Blind adversarial review. Tree: `/tmp/blind-final-h3/contracts/solidity`.
PoCs: `test/attacks/X3{a,b,c,d}_*.t.sol` — 5 tests, all passing, no fork required.

---

## 1. Model from code

**Denomination.** One switch: `quote` (`PerpEngine.sol:183`), `address(0)` = native.
`_quoteIsNative()` (:186) branches `_pullQuote` (:194), `_pushQuote` (:213), `_payOut` (:1388).
Every `*Eth` counter — `plv` (:304), `insuranceEth` (:223), `tokYieldEth` (:311), `longOiEth` (:354),
`payoutOwed` (:341), and the vault's `pendingEth` (:96) — is denominated in `quote`, **not** in ether.
`quote` has exactly one writer: `PerpEngine.sol:1099`, inside `syncGeneration`.

**Entrypoints / gates.**
Permissionless: `poke` :558, `openLong` :777, `openShort` :814, `liquidate` :856, `forceCloseDead` :983,
`forceCloseAllDead` :998, **`syncGeneration` :1024**, `claimPayout` :1410, `claimLiquidatorBadges` :1523,
`fundInsurance` :1564, `receive` :1813, and all of `PerpVault` (no owner, no admin).
Hook-only (`hookAddr` immutable :95): `sweepLiquidations` :881, `creditPerpFee` :1574,
`creditPerpFeeToken` :1579, `creditPerpFeeAsset` :1604.
Vault-only (:458): `fundFromVault` :1633, `withdrawPlvTo` :1641, `withdrawTokYieldTo` :1647,
`fundTokenFromVault` :1652, `withdrawPlvTokenTo` :1658.
Owner: fee/risk/tier/routing/guard setters, `setVault` :1751 (gated on `vault.hasStakers()`),
`fundPlv` :1550, `skimInsurance` :1784.

**Asset flows.** IN: vault deposits → `fundFromVault`→`plv`; hook fees → `_creditPerp`/`creditPerpFeeAsset`;
trader collateral → `_pullQuote`. OUT: `_pushQuote`/`_payOut` (trader, keeper, dividend, treasury),
`withdrawPlvTo`/`withdrawTokYieldTo`/`withdrawPlvTokenTo` (vault), pool legs through
`PerpSwapLib.swapLeg` (no internal slippage bound — limit is the tick extreme, `PerpSwapLib.sol:66`).

**Cross-subsystem.** `registry.generationQuote/currentGeneration/currentToken/lastSummonAt` — read
un-caught on every open (:1283, :1307). `hook.isDead` try/caught; `hook.collection` for badges.
`_key()` (:482) is built from the engine's **cached** `quote`, so a registry rotation diverges the
engine from the live pool until `syncGeneration` runs; `_isDead()` (:1306) reads that divergence as
death, which makes `forceCloseAllDead` permissionless and drives `openCount` to 0 — the precondition
`syncGeneration` needs. The whole rotation-follow chain is therefore permissionless.

---

## 2. Findings

```
id: X3a   severity: Critical   confidence: VERIFIED
subsystem: cauldron/PerpEngine.sol:1098-1099
  1098:  if (newQuote != quote && plv != 0) revert VaultStaked();
  1099:  quote = newQuote;
title: A permissionless syncGeneration re-denominates every native-quote counter except `plv`, so a
       stale wei counter pays out real new-quote tokens and the engine's ether is permanently locked.
precondition: a treasury quote rotation (a first-class feature this very function was extended to
  follow) plus `plv == 0`. `insuranceEth` (:223), `tokYieldEth` (:311) and `payoutOwed` (:341) are
  all quote-denominated and are NOT tested at :1098. Reaching it needs nobody's permission: quote
  divergence makes `_isDead()` true (:1307), `forceCloseAllDead` (:998) is permissionless and drives
  `openCount` to 0, then anyone calls `syncGeneration`.
sequence:
  1. hook credits short-side perp fees: creditPerpFeeToken{value: 1 ether}  -> tokYieldEth = 1e18 wei
  2. anyone: fundInsurance{value: 0.5 ether}(0.5 ether)                     -> insuranceEth = 5e17 wei
  3. treasury rotates registry.generationQuote(gen) to an ERC20
  4. attacker (any EOA): syncGeneration()   -> passes, because plv == 0; quote := the ERC20
  5. hook credits honest LP yield in the new quote: creditPerpFeeAsset(USDG, 1000e18) -> plv = 1000e18
  6. vault: withdrawTokYieldTo(1 ether, x)  -> _safeTransfer sends 1e18 UNITS OF USDG
attacker_cost: one syncGeneration call (~58k gas). No capital.
damage: `plv` still claims 1000e18 while the engine holds 999e18 — insolvent, and the gap grows with
  every stale-counter claim (tokYieldEth + insuranceEth + payoutOwed). The 1.5 ETH the engine actually
  holds is permanently unreachable: `_pushQuote` (:213) and `_payOut` (:1388) now take the ERC20
  branch for every counter, and `receive()` (:1813) books nothing. Permanent.
poc: test/attacks/X3a_QuoteRotationRedenominates.t.sol   needs_fork: no
```

```
id: X3c   severity: Critical   confidence: VERIFIED
subsystem: cauldron/PerpVault.sol:285-286, 294-296  (gate: PerpEngine.sol:1098)
  285:  if (claims == 0 || backing >= claims) return owed;
  286:  return FullMath.mulDiv(owed, backing, claims);
  294:  uint256 capped = _haircut(owed, engine.totalEth(), pendingEth);
  295:  if (capped < owed) { pendingEth -= (owed - capped); pendingEthOf[msg.sender] = capped; owed = capped; }
  296:  if (owed == 0) revert ZeroAmount();
title: A queued vault exit keeps its full wei-denominated nominal across a quote rotation and then
       claims that same NUMBER of units of the new asset — taking 100% of the next depositor's stake.
precondition: `pendingEth != 0` while `plv == 0` (the ordinary aftermath of a utilisation-capped exit
  followed by long bad debt), then a rotation. `PerpEngine.setVault` (:1751) already asks the right
  question — `vault.hasStakers()` (PerpVault.sol:158), which counts `pendingEth | pendingTok` — but
  `syncGeneration` :1098 asks only `plv != 0`. The vault's own header asserts the opposite guarantee:
  PerpVault.sol:86-90 "ONE ASSET AT A TIME ... syncGeneration refuses to adopt a new quote while
  plv != 0, so the asset cannot change underneath a staker ... a queue left against zero backing is
  written down to zero by {_haircut} before then." A queue can NEVER be written down to zero: line
  295 writes the zero and line 296 immediately reverts, rolling the write back. Measured.
sequence:
  1. alice: vault.depositEth{value: 10 ether}                   (plv = 10e18)
  2. a long borrows 8 ETH                                        (plv = 2e18, longOiEth = 8e18)
  3. alice: vault.withdrawEth(all)      -> paid 2e18, QUEUED 8e18, plv = 0, pendingEth = 8e18
  4. the long settles at a total loss                            (totalEth() = 0)
  5. alice: claimPendingEth() -> REVERTS; pendingEthOf[alice] is still 8e18 (not written down)
  6. anyone: syncGeneration()  -> plv == 0, so quote := USDG (6 decimals)
  7. bob deposits 1000 USDG (his shares are worth 0 on arrival)
  8. alice: claimPendingEth() -> _haircut(8e18, 1000e6, 8e18) = 1000e6 -> alice takes ALL 1000 USDG
attacker_cost: gas only; alice is an ordinary LP who simply did not claim.
damage: 100% of the honest depositor's capital, in a different asset, for an 8-ETH-denominated claim
  (125x the unit count a same-denomination claim would take — the control test bounds it to 8e18).
poc: test/attacks/X3c_StaleQueueSurvivesRotation.t.sol   needs_fork: no
```

```
id: X3d   severity: High   confidence: VERIFIED
subsystem: cauldron/PerpEngine.sol:1056-1061, :656, :268, :1283
  1056:  delete observations;
  1058:  obsIndex = 1;
  1061:  lastTick = _currentTick();
   656:  unchecked { if (nowTs - oldest.ts < MIN_TWAP) return (0, false); }
   268:  uint32 internal constant MIN_TWAP = 1 seconds;
  1283:  if (block.timestamp < registry.lastSummonAt() + warmup) revert NotWarm();
title: A permissionless syncGeneration wipes the TWAP ring without re-arming the warmup gate, so for
       a full `twapWindow` afterwards the liquidation mark is whatever a ~10-second price push says.
precondition: a quote rotation (mid-generation, so `lastSummonAt + warmup` is long expired and
  `_guardOpen` lets positions open immediately). `twapTick` reports `ok = true` on as little as
  MIN_TWAP = 1 SECOND of history (:656), and `markSqrtPriceX96` (:681) then feeds it to
  `_underwaterVal` (:1126/:1131), the per-timestamp liquidation throttle (:866/:971) and funding (:727).
  `setRisk` enforces only `warmup >= MIN_TWAP` (:1674), i.e. >= 1 second — the stated protection
  ("no position can open before the TWAP oracle has enough history", :1670-1673) is vacuous.
sequence:
  1. warm engine, ring holds 10 min of history; push the pool to tick 60000 and hold it 10 s
     -> twapTick() = 1929   (3.2% of the push — the TWAP resists; this is the positive control)
  2. treasury rotates the quote; ANY EOA calls syncGeneration()  -> ring deleted, one seed entry
  3. same 10 s push at tick 60000
     -> twapTick() = 54545, ok = true   (90.9% of the push — 28x the control)
attacker_cost: two swaps + holding the pool off-price for ~10 s, inside the 5-minute window after a
  rotation. No role.
damage: for one `twapWindow` every liquidation trigger, liquidation throttle and funding accrual is
  attacker-set: solvent positions are liquidatable (keeper cut + badge + settlement slippage) and
  insolvent ones are shielded, charging the loss to `plv`.
poc: test/attacks/X3d_RingResetCollapsesTwap.t.sol   needs_fork: no
```

```
id: X3b   severity: High   confidence: VERIFIED
subsystem: cauldron/PerpEngine.sol:1617-1622
  1617:  uint256 amount = msg.value;
  1618:  if (ethSide) {
  1619:      plv += amount;
  1621:      tokYieldEth += amount;
title: `_creditPerp` is the only native ingress with no `_quoteIsNative()` test, so on an ERC20 book
       it inflates `plv`/`tokYieldEth` with wei the engine can never pay out.
precondition: hook role (the protocol's own contract) + `quote != address(0)`. Reachable whenever the
  hook's TRANSIENT `_feeAsset` (CauldronHook.sol:697, written from the live pool key at :1459)
  disagrees with the engine's cached `quote` — e.g. a relaunch clamps the live pool to native while
  the engine still caches the previous generation's ERC20 quote, in the window before anyone calls
  `syncGeneration`. `FeeRouteLib._deliver` (FeeRouteLib.sol:141-142) picks the native selector purely
  from `asset == address(0)`, never asking the engine what it is denominated in.
sequence (measured, all on the same ERC20-quoted engine):
  1. fundPlv{value: 1 ether}(1 ether)        -> REVERTS  (_pullQuote :198 rejects value)
  2. fundInsurance{value: 1 ether}(1 ether)  -> REVERTS  (same)
  3. creditPerpFeeAsset(otherToken, 1e18)    -> REVERTS  (:1606 asset != quote)
  4. creditPerpFee{value: 1 ether}()         -> SUCCEEDS, plv        += 1e18
  5. creditPerpFeeToken{value: 1 ether}()    -> SUCCEEDS, tokYieldEth += 1e18
attacker_cost: none beyond the fee itself.
damage: `plv` claims 1e18 units of an ERC20 the engine received zero of (asserted), so the vault
  prices shares against phantom assets and the first real redemption reverts or drains another
  staker; 2 ETH sits in the contract with no counter that can ever pay it out.
poc: test/attacks/X3b_NativeCreditIntoErc20Plv.t.sol   needs_fork: no
```

---

## 3. Refutations — surfaces attacked that held

1. **`_haircut` pro-rata is self-consistent among queued claimants.** Worked the algebra and checked
   it in X3c's control: paying claimant A `owed·B/C` reduces backing and claims by the same ratio, so
   B's later claim gets the identical fraction. Order does not profit. No finding.
2. **The vault's inflation guard.** `OFFSET = 1e6` (PerpVault.sol:64) with `+1` on both share-math
   divisions (:202/:245) — a donation attack needs ~1e6x the victim's deposit. Not broken.
3. **Native value on the guarded ingresses.** `fundPlv`, `fundInsurance`, `fundFromVault` all route
   through `_pullQuote`, which rejects `msg.value != 0` on an ERC20 book; `creditPerpFeeAsset` rejects
   any asset that is not the live `quote`. All three asserted FALSE in X3b — they hold. `_creditPerp`
   is the single exception, which is what makes X3b a finding rather than a class.
4. **Same-transaction mark steering.** Attacked the obvious shape: push spot, then `poke()`, then
   `liquidate()` in one tx. `_writeObs` (:600-604) integrates the elapsed interval at the PREVIOUS
   `lastTick` and advances `lastObsTs` to now, so `twapTick`'s tail term
   `lastTick·(nowTs - lastObsTs)` (:672) is exactly zero for a push made inside the reading
   transaction. The push earns weight only for wall-clock time it is actually held. Held.
5. **A warm TWAP ring genuinely resists.** X3d's positive control: 10 s at tick 60000 against a warm
   300 s window moves the mark to 1929 (3.2%). The design works — it is the ring RESET that breaks it.
6. **`PerpMarkSource.addPool` orientation check.** `PerpMarkSource.sol:113-117` rejects any sibling
   whose two currencies differ from the primary's in either slot, and `weightedTick` skips zero-depth
   pools (:176) and falls back to the primary (:159/:165/:185). Could not get a cross-pair oracle onto
   the liquidation path.
7. **`forceCloseAllDead` drainability.** `MAX_OPEN_POSITIONS` = 64 is strictly below
   `FORCE_CLOSE_MAX` = 96 (:1008) and `_payOut` (:1405) credits instead of reverting, so no single
   position can block the drain. The `openCount == 0` precondition is genuinely reachable.

---

## 4. Leads (HYPOTHESIS — next step named)

- **Liquidation settlement has no slippage bound at all.** `ownerSlippage = mode == MODE_NORMAL`
  (`PerpEngine.sol:1140`), so a liquidation passes `minOut = 0`, and `PerpSwapLib` sets the price
  limit to the tick extreme (`PerpSwapLib.sol:66`). An in-swap sweep (`sweepLiquidations` :881, called
  from the swapper's own afterSwap) therefore executes the forced sale at whatever spot the triggering
  swap just created. Next step: fork PoC — one tx that crashes spot, lets the sweep dump a genuinely
  underwater long into the crash, then buys the dumped inventory back; measure the `plv` loss against
  the attacker's round-trip cost and the `maxLiqBps` throttle (:866).
- **Absolute thresholds do not survive a 6-decimal quote.** `minCollateral = 0.003 ether`
  (:144) and `tierDepthWei = [25 ether, 100 ether, 300 ether]` (:431) are raw quote-unit constants.
  After a permissionless rotation to a 6-decimal quote they mean 3e15 and 2.5e19 units: every
  `openLong`/`openShort` reverts `DustPosition` (:787/:823) and `maxLeverage()` (:696) pins to tier 0.
  Owner-recoverable via `setMinCollateral`/`setTiers`, so liveness-only. Next step: assert
  `DustPosition` on a 6-decimal book in a fork test and time how long the engine is dead.
- **Unchecked `transferFrom` on the token side.** `fundPlvToken` (:1559) and `fundTokenFromVault`
  (:1653) credit `plvToken` without decoding the return, unlike `_pullQuote` (:204), `_safeTransfer`
  (:1538) and `PerpVault._pull` (:230). A generation token that returns false instead of reverting
  would credit inventory that never arrived. Next step: confirm `CauldronToken.transfer*` always
  reverts; if any future generation token can return false, this is a direct `plvToken` inflation.
- **`setTiers` has no length ceiling** (:1706) and the tier loop (:700) runs inside `maxLeverage()`,
  which every open calls. Owner-only, so griefing-by-owner; next step: measure the array length at
  which `openLong` exceeds a block's gas.
