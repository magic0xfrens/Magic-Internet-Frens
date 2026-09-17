# H2 — Perp solvency and the PLV waterfall (round-45 blind)

Tree: `/tmp/r45-blind-h2/contracts/solidity`. PoCs: `test/attacks/R2*.t.sol` + shared mock `test/attacks/R2Mock.sol`.
Run: `FOUNDRY_PROFILE=cauldron forge test --match-path 'test/attacks/R2*.t.sol' -vv --skip 'lib/v4-periphery/lib/permit2/script/**'` → **4 passed, 0 failed, 0 skipped** (no fork needed; every assertion line is proved to have executed by the `console2` values printed above it).

---

## 1. MODEL FROM CODE

Two contracts, one balance sheet, two denominations.

**PerpEngine counters** (`PerpEngine.sol:580-586`): `totalEth() = plv + longOiEth`, `freeEth() = plv`, `totalTokenAssets() = plvToken + shortOiToken`, `freeToken() = plvToken`. Plus `insuranceEth:260`, `tokYieldEth`, `payoutOwedTotal`.

**Value in.** `fundFromVault:2463` onlyVault; `fundTokenFromVault:2486` onlyVault (`transferFrom(registry.currentToken())`); `fundPlv:2364` / `fundPlvToken:2372` onlyOwner; `fundInsurance:2378` **permissionless**; `creditPerpFee:2388` / `…Token:2393` → `_creditPerp` gated `if (msg.sender != hookAddr) revert OnlyHook();`; trader collateral via `openLong:964` / `openShort:998`.

**Value out.** `withdrawPlvTo:2469` / `withdrawTokYieldTo:2481` / `withdrawPlvTokenTo:2492` all onlyVault+notNested+nonReentrant and hard-capped by the counter; settlement residual/penalty/keeper via `_payOut`/`_pushQuote:~1553`; `skimInsurance:2647` onlyOwner, capped at `_insuranceNeed()`; `claimPayout:2201` / `retirePayout:2166`.

**Waterfall.** Long shortfall → `_replenishPlv:2234` (insurance → plv). Short overspend → `_absorbPlvLoss:2243` (`insuranceEth` first, then `plv` saturating). Negative funding credit → insurance then plv (`:1719-1726`). Short buy-back may spend `backing + insuranceEth + plv` (`:1672`) — the whole ETH LP base backstops one short.

**Gates.** `_utilGate:1997` = per-side utilization ≤ `maxUtilBps` (8000, `:272`) **and** `insuranceEth ≥ _insuranceNeed():1991` = `max(_q(insuranceFloor), maintenanceBps(1500)·(longOiEth+_quoteEth(shortOiToken))/BPS)`.

**Mark.** `_currentTick:693` → `markSource.weightedTick()` (owner-armed, fail-soft staticcall) else pool slot0 → `writeObs` ring (`PerpSwapLib.sol:338`) → `twapTick` (`PerpSwapLib.sol:282`) → `markSqrtPriceX96:845`, which **falls back to spot** when `ok == false`. `MIN_TWAP = 1 seconds` (`PerpSwapLib.sol:39`); opens are additionally ring-warmup-gated at `_guardOpen:1864`, liquidations are not.

**PerpVault** prices shares off the engine counters net of its own exit queues: `assetsEth():236 = totalEth − pendingEth`, `assetsTok():240 = totalTokenAssets − pendingTok`. Entrypoints `deposit:259` / `depositEth:298` / `withdrawEth:326` / `claimPendingEth:376` / `depositToken:507` / `withdrawToken:537` / `claimPendingToken:560` / `claimTokYield:525` — all permissionless. `hasStakers:205` gates `PerpEngine.setVault:2620`; `hasQuoteStake:228` gates `syncGeneration:1242`.

---

## 2. FINDINGS

---

### id: R2B   severity: Critical   confidence: VERIFIED

**subsystem:** PerpVault token-side exit queue
**file:line:** `contracts/solidity/cauldron/PerpVault.sol:560-572`

```solidity
560:    function claimPendingToken() external nonReentrant returns (uint256 paid) {
562:        if (owed == 0) revert ZeroAmount();
564:        uint256 capped = _haircut(owed, engine.totalTokenAssets(), pendingTok);
565:        if (capped < owed) { pendingTok -= (owed - capped); pendingTokOf[msg.sender] = capped; owed = capped; }
566:        if (owed == 0) revert ZeroAmount();
569:        if (paid == 0) revert ZeroAmount();
```

against the ETH side, which was patched and the token side was not:

```solidity
390:        if (owed == 0) { emit ClaimEth(msg.sender, 0); return 0; }
403:        if (paid == 0) { emit ClaimEth(msg.sender, 0); return 0; }
```

and the missing deposit guard — `deposit` has it (`:274`), `depositToken` (`:507-509`) does not:

```solidity
274:        if (pendingEth > engine.totalEth()) revert QueueInsolvent();
...
507:    function depositToken(uint256 amount) external nonReentrant returns (uint256 shares) {
508:        if (amount == 0) revert ZeroAmount();
509:        address tok = registry.currentToken();
```

**title:** Once token backing falls below the token exit queue, `pendingTok` can never be reduced — `hasStakers()` latches true and `PerpEngine.setVault` is bricked forever — and, because `depositToken` lacks the ETH side's insolvency guard, the stale queue takes 100% of the next token staker's principal.

**precondition:** `pendingTok > totalTokenAssets()`. Two reachable routes, both ordinary operation:
1. `_writeOffTok(id, unbought, false)` (`PerpEngine.sol:2225`: `shortOiToken -= amount`) on a `MODE_DEATH` short the pool cannot supply inside the band (`:1694`).
2. **Relaunch.** `syncGeneration:1310` does `plvToken = newInv` where `newInv` is the engine's balance of the *new* token after the **best-effort** `PerpSwapLib.migrateInventory`. That library's own comment records this failing in production: *"when the registry's `claimByBurnUpTo` body moved to {RedemptionExt}, a registry without that facet wired answered `NotConfigured()` here, this returned 0, and the engine's whole token side went to zero silently."* Any queued token exit outstanding across that relaunch is instantly insolvent. Note `syncGeneration` is gated on `hasQuoteStake()` (ETH only) by design (`PerpVault.sol:228` note), so a standing `pendingTok` does **not** block the relaunch that strands it.

**sequence:**
1. token staker deposits 100e18; the engine lends the inventory to shorts (`freeToken()==0` — the normal utilised state).
2. staker calls `withdrawToken(all)` → 100e18 queued (`pendingTok=100e18`, `tokShares=0`).
3. a death settle / failed migration drops `totalTokenAssets()` to 50e18 → `claimPendingToken()` writes the haircut on `:565` then **reverts on `:569`** (`freeToken()==0`), rolling it back.
4. remaining 50e18 written off → `totalTokenAssets()==0` → `capped==0` → **reverts on `:566`**, rolling back again. `pendingTok` is still 100e18 with zero backing, permanently.
5. `vault.hasStakers()` is `true` forever → `PerpEngine.setVault(newVault)` reverts `BadParam` (`PerpEngine.sol:2620-2622`) for the life of the engine. The engine's own note calls this "the ONLY lever for replacing a broken vault on a live engine".
6. a fresh staker deposits 100e18 of the live token: `assetsTok()` is 0, so he mints `1e26` shares whose `tokenPosition.redeemable` is **0**.
7. the stale queuer calls `claimPendingToken()` and receives **100e18 — the newcomer's entire principal**.

**attacker_cost:** gas only (~250k for steps 1-2 and 7). Steps 3-4 are protocol events, not attacker spend. No capital at risk beyond a deposit he was going to make anyway.
**damage:** (a) permanent brick of `setVault` — a Critical by the report's own definition; (b) 100% of every subsequent token staker's deposit, uncapped and repeatable (measured 100e18 of 100e18 in the PoC).
**poc:** `test/attacks/R2B_TokenQueueLatch.t.sol` — `[PASS]`, logs
`TOKEN-side pendingTok after the same: 100000000000000000000`, `hasStakers(): true`, `victim redeemable token: 0`, `stale queue claimed from victim principal: 100000000000000000000`, against the ETH-side positive control `ETH-side pendingEth after a total wipe-out: 0`.
**needs_fork:** no

---

### id: R2C   severity: High   confidence: VERIFIED

**subsystem:** PerpVault ETH-side deposit guard
**file:line:** `contracts/solidity/cauldron/PerpVault.sol:274` and `:376-379`

```solidity
274:        if (pendingEth > engine.totalEth()) revert QueueInsolvent();
...
376:    function claimPendingEth() external nonReentrant returns (uint256 paid) {
377:        uint256 owed = pendingEthOf[msg.sender];
378:        if (owed == 0) revert ZeroAmount();
```

**title:** A single queued claimant whose claim has already been written down to dust can shut the ETH side of the vault to every future depositor forever, for the price of the dust, simply by never calling `claimPendingEth`.

**precondition:** `pendingEth > engine.totalEth()` — i.e. bad debt has exceeded the live share base. `pendingEth` is decremented **only** inside `claimPendingEth`, and only against `pendingEthOf[msg.sender]`. Grepped: there is no `claimFor`, no owner override, no expiry, no admin drain of `pendingEth` anywhere in the file. The guard's own comment claims the release is permissionless ("`claimPendingEth` banks the haircut permissionlessly … No privilege, no timelock, no stuck vault") — it is permissionless only for the *one address that benefits from withholding it*.

**sequence:**
1. `holdout` deposits 10 ETH (sole LP); the book borrows it all.
2. `holdout` calls `withdrawEth(all)` → 10 ETH queued (costs nothing, `freeEth()==0`).
3. bad debt reduces `engine.totalEth()` to 0.001 ETH (`_absorbPlvLoss`, `PerpEngine.sol:2243`, saturating).
4. `holdout` does nothing. Simulated-and-rolled-back, his claim is worth **0.001 ETH**.
5. every `deposit` / `depositEth` reverts `QueueInsolvent` — measured in the PoC.
6. positive control: he claims → `pendingEth` drains → the side reopens. His call is the only key.

**attacker_cost:** 0.001 ETH forgone + ~290k gas total. Because the haircut already wrote his claim down to the residual backing, *the cost of the grief equals the entire post-loss backing, which is by construction near zero in exactly the state the attack needs.*
**damage:** permanent — the perp's community-PLV can never be recapitalised by new stakers after a wipeout, which is the one moment it must be. Bounded only by `insuranceEth`/`fundPlv` (owner) as an alternative capital route; the *community* promise is dead.
**poc:** `test/attacks/R2C_DepositLatch.t.sol` — `[PASS]`, logs `pendingEth while held : 10000000000000000000`, `engine.totalEth() : 1000000000000000`, `cost to the holdout of refusing (wei): 1000000000000000`.
**needs_fork:** no

---

### id: R2A   severity: High   confidence: VERIFIED

**subsystem:** PerpVault exit-queue seniority
**file:line:** `contracts/solidity/cauldron/PerpVault.sol:234-237` and `:366-373`

```solidity
234:    function assetsEth() public view returns (uint256) {
235:        uint256 t = engine.totalEth();
236:        return t > pendingEth ? t - pendingEth : 0;
...
370:    {
371:        if (claims == 0 || backing >= claims) return owed;
372:        return FullMath.mulDiv(owed, backing, claims);
```

**title:** A queued exit is fully senior to live shares until the live share base is wiped out entirely, so racing into the queue the block before a loss shifts 100% of that loss onto the LPs who stayed — the "bank run with a protocol-enforced starting gun" the `_haircut` note claims to have removed.

**precondition:** none beyond being an LP and seeing a loss coming. Loss visibility is a public view: `PerpEngine.isLiquidatable(id):1477`. Queueing is free when `freeEth()` is low, which is the normal state under the 80% utilization cap (`maxUtilBps = 8_000`, `PerpEngine.sol:272`).

`_haircut` only bites when `backing < pendingEth`. `assetsEth()` subtracts the *whole* queue nominal before the live share price is computed, so live shares absorb the loss first, in full, down to zero — pro-rata across claimants only applies *inside* the queue, never between the queue and the stakers.

**sequence:** (both LPs equal at 5 ETH; 4 ETH loss)
1. `lpA`, `lpB` each `depositEth{value: 5 ether}`; `totalEth()==10e18`.
2. the book borrows 10 ETH; `freeEth()==0`.
3. `lpA` calls `withdrawEth(allShares)` → `paid==0`, `queued==5e18` **at the pre-loss price**. Cost: gas.
4. 4 ETH of bad debt lands; `totalEth()==6e18`.
5. positions close, liquidity returns.
6. `lpA.claimPendingEth()` → **5.000 ETH** (no haircut: `backing 6e18 ≥ claims 5e18`).
7. `lpB.withdrawEth(allShares)` → **1.000 ETH**.

Pro-rata would be 3/3. Measured 5/1: `lpA` recovered 100%, `lpB` 20%.

**attacker_cost:** one `withdrawEth` (~90k gas). No capital, no holding cost, no price risk.
**damage:** the full bad debt transferred to passive LPs — 4 ETH of 4 ETH in the PoC. Generalises: the first LP to queue converts an at-risk position into a risk-free senior claim, which makes queueing every LP's dominant strategy and re-creates the run.
**poc:** `test/attacks/R2A_QueueSeniority.t.sol` — `[PASS]`, logs `lpA (queued first) recovered wei: 5000000000000000000`, `lpB (stayed staked) recovered wei: 1000000000000000000`, `total loss wei: 4000000000000000000`. Solvency positive-control `aOut + bOut <= 10 ether` also asserted and held (no value invented — this is pure loss-shifting).
**needs_fork:** no

---

### id: R2D   severity: Medium   confidence: DERIVED

**subsystem:** `_utilGate` risk-scaled insurance pause
**file:line:** `contracts/solidity/cauldron/PerpEngine.sol:1991-2026`

```solidity
1991:    function _insuranceNeed() internal view returns (uint256) {
1992:        uint256 riskMin = ((longOiEth + _quoteEth(shortOiToken)) * maintenanceBps) / BPS;
1993:        uint256 floorQ = _q(insuranceFloor);
1994:        return floorQ > riskMin ? floorQ : riskMin;
1995:    }
1997:    function _utilGate(uint256 used, uint256 total) private view {
...
2025:        if (need > 0 && insuranceEth < need) revert InsurancePaused();
```

with the constants `maintenanceBps = 1_500` (`:171`), `openFeeBps = 690` (`:149`), `insuranceBps = 1_000` (`:265`), and `borrow = collateral * (leverage - 1)` (`:974`), `fee = (sent * openFeeBps) / BPS` (`:1931`).

**title:** One held position pushes `_insuranceNeed()` above `insuranceEth` and pauses **all** opens for everyone, at ~8:1 in the griefer's favour.

**arithmetic (DERIVED, not run):** a griefer sends `S` at leverage `L`. Insurance gains `S·0.069·0.10 = 0.0069·S`. `longOiEth` gains `0.931·S·(L−1)`, so `riskMin` gains `0.1397·S·(L−1)`. At `L = 5`: `+0.559·S` of requirement against `+0.0069·S` of buffer — an 81× deficit per open. His own open passes because the gate is evaluated **before** the OI update (the comment at `:2019-2024` states this as accepted lag). Every subsequent open by anyone reverts `InsurancePaused`.

Recovery is permissionless — `fundInsurance:2378` takes anyone's money — but the defender must donate `0.552·S` of ETH that `skimInsurance:2647` then refuses to return while the position is open, whereas the griefer's non-refundable outlay is the `0.069·S` open fee (of which he gets a share back as an LP). Ratio ≈ 8:1. He un-griefs at will by closing.

**precondition:** any wired vault (`vault != address(0)`, `:1998`) and an insurance buffer that has not been over-funded. The code's own measured baseline — *"insurance 0.0608 ETH against a 0.1493 ETH max notional"* — puts the OI ceiling at `0.0608 / 0.15 = 0.405 ETH`, i.e. the engine self-pauses at well under half an ETH of open interest on the r44 numbers.

**attacker_cost:** `0.069·S` + funding per block; collateral refundable on close.
**damage:** no funds lost; `close`/`liquidate` are ungated so liveness (g) holds. Pure denial of the permissionless-leverage promise, plus a bootstrapping problem: supporting 10 ETH of OI needs 1.5 ETH of insurance, which organic open fees would take ~217 ETH of cumulative collateral to accrue.
**poc:** not written (needs the live-pool fork harness). **Next step:** in `YBase`, seed a pool, `setVault`, `fundInsurance(0.06 ether)`, `openLong(5, …, 0.15 ether)` from attacker, then assert a second account's `openLong` reverts `InsurancePaused()` and that clearing it costs `_insuranceNeed() − insuranceEth` via `fundInsurance`.
**needs_fork:** yes

---

## 3. REFUTATIONS

**PoC: `test/attacks/R2E_RefutationEthDeposit.t.sol` — `[PASS]`.**

1. **"Dilute a fresh ETH depositor behind a large standing queue."** Hit with a 100 ETH queue against an *empty* live share base (`ethShares == 0`) and a fresh 10 ETH deposit — the worst shape I could build short of insolvency. Held exactly: redeemable `10000000000000000000` for a 10e18 deposit. `assetsEth()` (`:236`) nets `pendingEth` symmetrically on the mint (`:290`) and the redeem (`:344`), so the queue's seniority does not leak into the newcomer's price. This is precisely why R2B is a bug in `depositToken`'s **missing** `QueueInsolvent` guard and not in `assetsTok` — the arithmetic is right on both sides; only the ETH side refuses the insolvent case.

2. **First-depositor / donation inflation on the ETH share base.** Refuted structurally, by grep of every `plv +=` writer reachable from outside: `fundFromVault:2463` (onlyVault), `fundPlv:2364` (onlyOwner), `_creditPerp` (`if (msg.sender != hookAddr) revert OnlyHook();`), and settlement internals. `fundInsurance:2378` is the one permissionless value-in path and it credits `insuranceEth`, not `plv`. Asserted in the PoC with the only route a stranger actually has — a raw 50 ETH `call{value:}` to the engine — which moved the victim's redeemable by **0 wei**. `OFFSET = 1e6` (`:67`) plus the `+1` denominators make the residual rounding edge uninteresting.

3. **The `_absorbPlvLoss` / `_replenishPlv` / funding waterfall ordering.** Read all four sites (`:1679`, `:1662`, `:1719-1726`, `:2234-2251`). Insurance is consumed before `plv` on every one, `plv` is saturating so no path can underflow-brick a liquidation, and I could not construct a double-take: the long leg books the shortfall by *under-crediting* `plv` and then replenishes from insurance, while the short leg *over-spends* raw ETH and then debits — opposite signs, no overlap. DERIVED, not run; I found no way in.

---

## 4. LEADS (HYPOTHESIS)

**L1 — `MIN_TWAP = 1 seconds` makes the mark a 1-second average after any ring reset.** `PerpSwapLib.sol:39`, and the fallback at `:306` `if (nowTs - oldest.ts < MIN_TWAP) return (0, false);`. `syncGeneration:1298-1303` does `delete observations; ring.obsIndex = 1;`. `_guardOpen:1864` adds a `ringArmedAt + twapWindow` warmup for **opens** — but `markSqrtPriceX96:845` falls back to raw `_sqrtP()` when `ok == false`, and **liquidation** has no equivalent warmup gate. *Next step:* on the fork, relaunch with a position still liquidatable, then call `liquidate` two seconds into the new ring and assert the mark used was spot.

**L2 — the queue survives a generation change in the wrong denomination.** `pendingTok` / `pendingTokOf` are raw token amounts of generation N; `syncGeneration:1310` re-points `plvToken` at generation N+1's token and `withdrawPlvTokenTo:2492` transfers `registry.currentToken()`. A 100-unit gen-N queued claim therefore draws 100 units of the *new* token at a 1:1 nominal. *Next step:* extend R2B with a `MockRegistry.set(newToken)` between the queue and the claim and price the two tokens differently.

**L3 — cross-side value transfer on a short buy-back.** `PerpEngine.sol:1672` lets a single short's forced buy-back spend `backing + insuranceEth + plv`, and `:1674` credits the purchased tokens to `plvToken`. `shortOiToken -= bought` keeps `totalTokenAssets()` flat so the *counters* balance, but ETH-side principal is what paid for inventory the token side now holds free and clear. *Next step:* construct a max-notional short against a thin pool on the fork, measure `plv` before/after against `plvToken`, and check whether the token side's share price rises by the ETH side's loss.

**L4 — `_currentTick:693` truncates the mark source's answer unchecked.** `v := mload(0x00)` then `int24(v)` with no range check; only `returndatasize() == 0x20` is enforced. Owner-armed today, so Low — but it means any future permissionless mark source is a free tick oracle. *Next step:* confirm `setRouting` is the sole writer of `markSource` and that it validates the target.
