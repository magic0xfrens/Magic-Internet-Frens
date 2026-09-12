# perp cluster — function graph notes

Generated from the working tree at `contracts/solidity`; re-derived 2026-09-12 after the fix wave, so every line number below points at the CURRENT file.

| file | lines | nodes |
|---|---:|---:|
| `cauldron/PerpEngine.sol` | 2041 | 105 (PerpEngine 93 + 4 interfaces declared inside: IPerpRegistry 8, IMarkSource 1, IPerpVaultStake 2, IPerpHook 2) |
| `cauldron/PerpVault.sol` | 478 | 35 (PerpVault 23 + IPerpEngineVault 11 + IVaultRegistry 1) |
| `cauldron/PerpSwapLib.sol` | 280 | 11 |
| `cauldron/PerpMarkSource.sol` | 203 | 7 |
| `cauldron/PerpStakerOracle.sol` | 32 | 4 (PerpStakerOracle 2 + IPerpShares 2) |

Total 163 nodes. Companion machine-checked data: `audit/graph/perp.json`.

Extraction only — no severity judgement anywhere below. Where a comment claims something the code does not do, both are recorded side by side in section H.

---

## A. Value inventory

Denomination key: **Q** = the engine's `quote` (PerpEngine.sol:184); `address(0)` means native ether, otherwise the ERC20 at that address. **T** = the generation token (`registry.currentToken()`, read at PerpEngine.sol:535). **S** = share units. **idx** = a 1e18-scaled index, not an amount.

### PerpEngine

**`plv`** (PerpEngine.sol:319) — free lendable capital, **Q**.
- `-` PerpEngine.sol:874 long open moves `borrow` out to `longOiEth`
- `+` PerpEngine.sol:1293 long settle repays at most the principal
- `+` PerpEngine.sol:1333 funding paid in by the crowded side
- `-` PerpEngine.sol:1340 funding paid out to the underweight side (after insurance, saturating)
- `+` PerpEngine.sol:1514 long-attributed fee yield
- `+` PerpEngine.sol:1644 insurance replenishment after long bad debt
- `-` PerpEngine.sol:1655 short bad-debt absorption (saturating at 0)
- `+` PerpEngine.sol:1758 owner donation (`fundPlv`, no shares minted)
- `+` PerpEngine.sol:1818 ERC20 perp-fee credit from the hook
- `+` PerpEngine.sol:1841 native perp-fee credit, buy side
- `+` PerpEngine.sol:1818 vault deposit or hook asset fee (shared body `_pullIntoPlv`)
- `-` PerpEngine.sol:1863 vault withdrawal
- read-only bounds: PerpEngine.sol:862, PerpEngine.sol:1218 (zeroed by the rotation sweep at PerpEngine.sol:1219), PerpEngine.sol:1339, PerpEngine.sol:1862

**`plvToken`** (PerpEngine.sol:320) — free short inventory, **T**.
- `-` PerpEngine.sol:910 short open lends inventory out
- `+` PerpEngine.sol:1306 short settle returns the borrowed size IN FULL
- `+` PerpEngine.sol:1766 owner donation
- `+` PerpEngine.sol:1880 vault deposit
- `-` PerpEngine.sol:1886 vault withdrawal
- `=` PerpEngine.sol:1138 **replaced wholesale** by the engine's real balance of the new token during a sync

**`insuranceEth`** (PerpEngine.sol:223) — bad-debt buffer, **Q**.
- `-` PerpEngine.sol:1337 funding credit drawn from the buffer first
- `+` PerpEngine.sol:1519 insurance carve of every routed fee
- `-` PerpEngine.sol:1644 cover paid into `plv` after long bad debt
- `-` PerpEngine.sol:1653 cover consumed by short bad debt
- `+` PerpEngine.sol:1772 permissionless top-up
- `-` PerpEngine.sol:2016 owner skim of the surplus

**`tokYieldEth`** (PerpEngine.sol:326) — segregated short-side reward pot, **Q** on the way out, credited with native value on one path (see F).
- `+` PerpEngine.sol:1516 short-attributed fee yield
- `+` PerpEngine.sol:1843 native perp-fee credit, sell side
- `-` PerpEngine.sol:1875 attributed claim paid through the vault

**`tokYieldCumulative`** (PerpEngine.sol:329) — monotonic marker, same units, never decremented.
- `+` PerpEngine.sol:1517, `+` PerpEngine.sol:1844

**`longOiEth`** (PerpEngine.sol:384) — capital lent to open longs, **Q**.
- `+` PerpEngine.sol:874, `-` PerpEngine.sol:1289, `= 0` PerpEngine.sol:1140 (sync)

**`shortOiToken`** (PerpEngine.sol:385) — inventory lent to open shorts, **T**.
- `+` PerpEngine.sol:910, `-` PerpEngine.sol:1301, `= 0` PerpEngine.sol:1139 (sync)

**`payoutOwed[addr]`** (PerpEngine.sol:356) — undeliverable settlement credit, **Q**.
- `+` PerpEngine.sol:1544 (inside `unchecked`, together with the aggregate `payoutOwedTotal` on the same line), `= 0` PerpEngine.sol:1635 (self-claim) or PerpEngine.sol:1616 (owner/permissionless retire)

**`badgesOwed[addr]`** (PerpEngine.sol:351) — a COUNT of NFTs, not value.
- `+` PerpEngine.sol:1722 (inside `unchecked`), `-` PerpEngine.sol:1738

**`positions[id]`** (PerpEngine.sol:345) — `collateral` and `principal` are **Q**, `size` is **T**, `entryFunding` is **idx**.
- created PerpEngine.sol:1480, deleted PerpEngine.sol:1282 (before any swap)

**`fundingIndex`** (PerpEngine.sol:332) — signed **idx**, `+=` PerpEngine.sol:808 only.

**`liqEthThisBlock`** (PerpEngine.sol:302) — per-timestamp liquidated notional, **Q**. `= 0` at PerpEngine.sol:939 / PerpEngine.sol:1044 when `liqBlock` (PerpEngine.sol:939) differs; `+=` PerpEngine.sol:942 / PerpEngine.sol:1047.

### PerpVault

**`ethShares`** (PerpVault.sol:105) / **`ethShareOf`** (PerpVault.sol:106) — **S**. `+` PerpVault.sol:227 / PerpVault.sol:228; `-` PerpVault.sol:277 / PerpVault.sol:276.

**`pendingEth`** (PerpVault.sol:107) / **`pendingEthOf`** (PerpVault.sol:108) — queued nominal claims, **Q**. `+` PerpVault.sol:279 / PerpVault.sol:280; written down `-` PerpVault.sol:318 (both); `-` PerpVault.sol:332 / PerpVault.sol:331 on payment.

**`tokShares`** (PerpVault.sol:111) / **`tokShareOf`** (PerpVault.sol:112) — **S**. `+` PerpVault.sol:382 / PerpVault.sol:383; `-` PerpVault.sol:417 / PerpVault.sol:416.

**`pendingTok`** (PerpVault.sol:113) / **`pendingTokOf`** (PerpVault.sol:114) — queued nominal claims, **T**. `+` PerpVault.sol:420 / PerpVault.sol:421; written down PerpVault.sol:433; paid PerpVault.sol:439 / PerpVault.sol:438.

**`accEthPerTokShare`** (PerpVault.sol:121) — **idx**, `+=` PerpVault.sol:356 only.
**`lastTokYieldCum`** (PerpVault.sol:122) — watermark, `=` PerpVault.sol:354 only, ALWAYS advanced even at zero shares (PerpVault.sol:355).
**`tokRewardDebt`** (PerpVault.sol:123) — **idx** baseline, `=` PerpVault.sol:369 only.
**`tokRewardOwed`** (PerpVault.sol:124) — banked reward, **Q**. `+` PerpVault.sol:364, `= 0` PerpVault.sol:398.

`PerpMarkSource`, `PerpStakerOracle` and `PerpSwapLib` hold no value and no balances of their own (`PerpSwapLib` moves the ENGINE's value under delegatecall — see D).

---

## B. Balance vs counter

The engine never compares any counter to its own balance. There is exactly one reconciliation in the cluster:

- **`plvToken` is re-derived from a real balance** at PerpEngine.sol:1124-1138, using `IERC20(newTok).balanceOf(address(this))`. Every other counter is carried forward from arithmetic alone.

Where counter and balance can diverge:

1. **Bare `receive()`** (PerpEngine.sol:2040) accepts native value that no counter records. Pool settlement needs it; a direct send is untracked.
2. **`_creditPerp`** (PerpEngine.sol:1839) credits `msg.value` — native wei — into `plv` (PerpEngine.sol:1841) or `tokYieldEth` (PerpEngine.sol:1843), and now REFUSES unless the book is native (PerpEngine.sol:1833), so native wei can no longer inflate an ERC20-denominated counter. The non-native equivalent is `creditPerpFeeAsset` (PerpEngine.sol:1806), which pulls the asset and credits the ETH side for both trade directions (PerpEngine.sol:1818).
3. **Unchecked ERC20 pulls.** `fundPlvToken` (PerpEngine.sol:1765) and `fundTokenFromVault` (PerpEngine.sol:1879) call `transferFrom` without inspecting the return value, then credit `plvToken` (PerpEngine.sol:1766 / PerpEngine.sol:1880). Contrast `_pullQuote` (PerpEngine.sol:206), `_safeTransfer` (PerpEngine.sol:1744) and `PerpVault._pull` (PerpVault.sol:253), which all decode it.
4. **Short settlement spends before it books.** `_buyExactOut` (PerpEngine.sol:1305) spends real balance for the buy-back; `_absorbPlvLoss` (PerpEngine.sol:1311) then reduces the counters to match. Between those two lines the counters overstate the balance.
5. **Failed pushes become debt without releasing a counter.** `_payOut` (PerpEngine.sol:1544) converts an undeliverable payment into `payoutOwed`; the value stays in the contract backing a new claim.
6. **Quote adoption now redenominates instead of refusing.** The guard tests two things only: `payoutOwedTotal != 0` (PerpEngine.sol:1207) and the outgoing vault's `hasStakers()` (PerpEngine.sol:1208). It then SWEEPS `plv + tokYieldEth + insuranceEth` (PerpEngine.sol:1218) to the treasury in the OLD asset and zeroes all three (PerpEngine.sol:1219), drops `markSource` (PerpEngine.sol:1241) and re-reads the quote's decimals into `quoteUnit` (PerpEngine.sol:1243). `plvToken` is NOT part of the sweep — it is token-denominated. The sweep's push result is discarded (PerpEngine.sol:1228).
7. **Vault claims vs vault backing.** `assetsEth()` (PerpVault.sol:185) subtracts `pendingEth` from `engine.totalEth()`, so live shares and queued claims partition the same pot. But the haircut at PerpVault.sol:317 compares the WHOLE `engine.totalEth()` against `pendingEth` alone — live-share backing is in the numerator and not in the denominator. The token side does the same at PerpVault.sol:432.
8. **`totalEth()` counts lent capital.** PerpEngine.sol:517 returns `plv + longOiEth`, so the vault prices shares against capital that is not in the contract; only `freeEth()` (PerpEngine.sol:519) is instantly payable, which is why `withdrawEth` splits at PerpVault.sol:270.

Counters that must cover one another (the solvency table) are in the cluster extras below.

---

## C. Authority map

| gate | held by | guarded surface | rotatable? |
|---|---|---|---|
| `onlyOwner` (OZ `Ownable`, constructed at PerpEngine.sol:478) | engine owner | `setFees` PerpEngine.sol:1891, `setRisk` PerpEngine.sol:1895, `setTiers` PerpEngine.sol:1932, `setRouting` PerpEngine.sol:1946, `setGuards` PerpEngine.sol:1956, `setVault` PerpEngine.sol:1977, `setVaultSplit` PerpEngine.sol:1983, `setVaultLimits` PerpEngine.sol:1989, `setMinCollateral` PerpEngine.sol:1994, `skimInsurance` PerpEngine.sol:2010, `fundPlv` PerpEngine.sol:1756, `fundPlvToken` PerpEngine.sol:1764 | transfer only — `renounceOwnership` is overridden to revert (PerpEngine.sol:453), so the row above cannot be orphaned; `transferOwnership` is unmodified, and re-pointing `markSource` (PerpEngine.sol:1953) stays owner-only |
| `onlyVault` (PerpEngine.sol:510) | whatever address `vault` holds | `fundFromVault` PerpEngine.sol:1855, `withdrawPlvTo` PerpEngine.sol:1861, `withdrawTokYieldTo` PerpEngine.sol:1873, `fundTokenFromVault` PerpEngine.sol:1878, `withdrawPlvTokenTo` PerpEngine.sol:1884 | yes, by the owner at PerpEngine.sol:1979, behind the incumbent's own `hasStakers()` answer (PerpEngine.sol:1978). While `vault` is zero the whole surface is unreachable |
| `msg.sender != hookAddr` (PerpEngine.sol:956, PerpEngine.sol:1807, PerpEngine.sol:1823) | the hook | `sweepLiquidations`, `creditPerpFee`, `creditPerpFeeToken`, `creditPerpFeeAsset` | **no** — `hookAddr` is immutable (PerpEngine.sol:96, set at PerpEngine.sol:479). A replaced hook dead-ends keeperless liquidation and perp-fee credit permanently |
| `msg.sender != address(poolManager)` (PerpEngine.sol:1394) | the v4 pool manager | `unlockCallback` | no — immutable |
| `msg.sender != address(this)` (PerpEngine.sol:965) | the engine itself | `selfSweep` | n/a |
| `p.trader != msg.sender` (PerpEngine.sol:925) | the position owner | `close` | per-position |
| `onlyOwner` (PerpMarkSource.sol:115, PerpMarkSource.sol:126, PerpMarkSource.sol:147) | mark-source owner | `setPrimary`, `addPool`, `removePool` | transfer only — `renounceOwnership` reverts (PerpMarkSource.sol:99); the engine can also detach the source at PerpEngine.sol:1953 or drop it itself on a quote flip (PerpEngine.sol:1241) |
| none | — | **every** `PerpVault` entrypoint | `PerpVault` has no owner, no admin and no upgrade path; `engine` and `registry` are immutable (PerpVault.sol:66-67), so a vault is bound to one engine for life |
| none | — | `PerpStakerOracle.isInstant` PerpStakerOracle.sol:29 | `perpVault` is immutable (PerpStakerOracle.sol:22); replacement happens at the consumer |

Permissionless entrypoints that move value or state: `poke` PerpEngine.sol:631, `openLong` PerpEngine.sol:851, `openShort` PerpEngine.sol:888, `liquidate` PerpEngine.sol:930, `forceCloseDead` PerpEngine.sol:1057, `forceCloseAllDead` PerpEngine.sol:1072, `syncGeneration` PerpEngine.sol:1098, `claimPayout` PerpEngine.sol:1632, `claimLiquidatorBadges` PerpEngine.sol:1730, `fundInsurance` PerpEngine.sol:1770, `receive` PerpEngine.sol:2040, `retirePayout` PerpEngine.sol:1612 (owner-only while `quote` agrees with the generation's quote, permissionless while it diverges — the branch is at PerpEngine.sol:1615), and the whole of `PerpVault`.

Trust the engine extends without a gate: `registry` is consulted unconditionally and un-caught at PerpEngine.sol:1461 (inside the death test that every open and every force-close passes through), while the hook's own `isDead` at PerpEngine.sol:1462 IS wrapped in try/catch.

---

## D. External calls, value, and CEI ordering

| site | callee | value moved | trust | ordering |
|---|---|---|---|---|
| PerpEngine.sol:206 -> PerpSwapLib.sol:124 | `token.call(transferFrom)` (delegatecalled) | pulls **Q** in | untrusted | `_pullQuote`; in `openLong`/`openShort` it runs BEFORE every guard (PerpEngine.sol:855, PerpEngine.sol:892); return value decoded at PerpSwapLib.sol:127, engine reverts at PerpEngine.sol:206 |
| PerpEngine.sol:216 | `to.call{value}` | sends **Q** out, all gas | untrusted | after effects (PerpEngine.sol:1637, PerpEngine.sol:1869, PerpEngine.sol:2017); reverts on failure |
| PerpEngine.sol:219 -> PerpEngine.sol:1744 -> PerpSwapLib.sol:132 | `token.call(transfer)` (delegatecalled) | sends **Q**/**T** out | untrusted | same; the library REPORTS and `_safeTransfer` reverts on a false return (PerpEngine.sol:1744) |
| PerpEngine.sol:489, PerpEngine.sol:540, PerpEngine.sol:624 | `poolManager.getSlot0` | none (view) | trusted | — |
| PerpEngine.sol:615 | `markSource` raw `staticcall` | none (view) | untrusted, owner-set | result accepted only if the call succeeded and returned exactly 32 bytes (PerpEngine.sol:619) |
| PerpEngine.sol:763 | `poolManager.getLiquidity` | none (view) | trusted | — |
| PerpEngine.sol:1118 | `PerpSwapLib.migrateInventory` (delegatecall) → PerpSwapLib.sol:255 `registry.call` | burns the engine's dead **T**, receives live **T** | trusted registry, low-level and best-effort | before the `plvToken` re-derivation at PerpEngine.sol:1138 |
| PerpEngine.sol:1124 | `IERC20(newTok).balanceOf` | none (view) | untrusted (new generation token) | — |
| PerpEngine.sol:1380 | `poolManager.unlock` | re-enters this contract at PerpEngine.sol:1393 | trusted | — |
| PerpEngine.sol:1414 | `PerpSwapLib.swapLeg` (delegatecall) | see the four rows below | trusted lib, untrusted currencies | called from `_settle` AFTER the position is deleted (PerpEngine.sol:1282) |
| PerpSwapLib.sol:186 | `poolManager.swap` | none directly; creates deltas | trusted | price limit is the extreme tick (PerpSwapLib.sol:176) — no slippage bound inside the library |
| PerpSwapLib.sol:214 | `poolManager.settle{value}` | sends native out of the ENGINE | trusted | pay leg |
| PerpSwapLib.sol:216 / :111 / :115 | `sync`, `c.call(transfer)`, `settle` | sends ERC20 out of the ENGINE | untrusted token | return decoded at PerpSwapLib.sol:224 |
| PerpSwapLib.sol:200 / :95 | `poolManager.take` | receives into the ENGINE | trusted | after the pay leg |
| PerpEngine.sol:1435 | `registry.lastSummonAt` | none | trusted, **not** caught | gates every open |
| PerpEngine.sol:1461 | `registry.generationQuote` + `currentGeneration` | none | trusted, **not** caught | gates every open and every force-close |
| PerpEngine.sol:1462 | `hook.isDead` | none | trusted, try/catch → false | — |
| PerpEngine.sol:1466 | `mifrens.balanceOf` | none | trusted, immutable | inside fee computation |
| PerpEngine.sol:1565 | `to.call{value, gas:30_000}` | sends native **Q** | untrusted | `_tryPush(capped=true)`; credit-on-failure at PerpEngine.sol:1544 |
| PerpEngine.sol:1566 | `to.call{value}` | sends native **Q**, **all** remaining gas | untrusted | `_tryPush(capped=false)`, reached only from `retirePayout` (PerpEngine.sol:1623) |
| PerpEngine.sol:1568 -> PerpSwapLib.sol:132 | `token.call(transfer)` | sends ERC20 **Q**, **all** remaining gas | untrusted | reporting push; credit-on-failure at PerpEngine.sol:1544 |
| PerpEngine.sol:1720 / PerpEngine.sol:1733 | `hook.collection` | none | trusted, typed, un-caught | — |
| PerpSwapLib.sol:74 / PerpSwapLib.sol:79 | `col.call{gas: fwd}` (delegatecalled from PerpEngine.sol:1720) | none | untrusted, hook-chosen | failure falls back to `badgesOwed` |
| PerpEngine.sol:1741 | `col.mintLiquidator` typed | none | untrusted, hook-chosen | AFTER `badgesOwed` is decremented (PerpEngine.sol:1738) |
| PerpEngine.sol:1765 / PerpEngine.sol:1879 | `token.transferFrom` | pulls **T** in | untrusted, **return not checked** | before the counter increment |
| PerpEngine.sol:1978 | `vault.hasStakers` | none | typed, un-caught | the incumbent answers the question that permits its own replacement |
| PerpVault.sol:240 | `engine.staticcall("quote()")` | none | trusted, deliberately raw so a missing function degrades to native (PerpVault.sol:243) | — |
| PerpVault.sol:250 / PerpVault.sol:257 | `token.call(transferFrom/approve)` | pulls **Q**/**T** in, grants allowance | untrusted | `_pull` decodes the return (PerpVault.sol:253); `_approve` checks only the success flag (PerpVault.sol:258) |
| PerpVault.sol:229 | `engine.fundFromVault{value}` | sends **Q** to the engine | trusted | AFTER shares are minted (PerpVault.sol:227) |
| PerpVault.sol:282 / PerpVault.sol:333 | `engine.withdrawPlvTo` | pays the caller | trusted | AFTER shares burned and queue earmarked (PerpVault.sol:276-280, PerpVault.sol:331) |
| PerpVault.sol:388 | `engine.fundTokenFromVault` | sends **T** to the engine | trusted | after share mint and baseline rebase |
| PerpVault.sol:399 | `engine.withdrawTokYieldTo` | pays the caller | trusted | AFTER `tokRewardOwed` zeroed (PerpVault.sol:398) |
| PerpVault.sol:423 / PerpVault.sol:440 | `engine.withdrawPlvTokenTo` | pays the caller **T** | trusted | after effects |
| PerpStakerOracle.sol:30 | `perpVault.ethShareOf` / `tokShareOf` | none | typed, un-caught | — |

Reentrancy shape worth recording plainly: `sweepLiquidations` (PerpEngine.sol:955) carries neither `nonReentrant` nor `notNested`, and `_settle` performs its pool swap at PerpEngine.sol:1290 / PerpEngine.sol:1305. A settlement swap therefore reaches the hook's afterSwap, which calls back into `sweepLiquidations`; nesting beyond that is stopped by `_liqReentry` (PerpEngine.sol:981), and while a sweep is live `notNested` (PerpEngine.sol:506) locks every user entrypoint.

---

## E. Loops

| site | bound | who can grow the bound |
|---|---|---|
| PerpEngine.sol:734 | binary search over the ring — at most log2 of `OBS_CARDINALITY` = 5 iterations | nobody; PerpEngine.sol:263 is a constant |
| PerpEngine.sol:770 | `tierDepthWei.length` | the owner, via `setTiers` (PerpEngine.sol:1933); the arrays are replaced wholesale with no length ceiling. Runs inside `maxLeverage`, which every open calls (PerpEngine.sol:1439) |
| PerpEngine.sol:1000 | `SWEEP_SCAN` = 12 checks, `MAX_LIQ_PER_SWAP` = 8 kills, plus a hard break below `SWEEP_KILL_RESERVE` gas (PerpEngine.sol:1016) | nobody — the break degrades instead of reverting |
| PerpEngine.sol:1082 | `FORCE_CLOSE_MAX` = 96 (PerpEngine.sol:164) | anyone, by opening positions — but only up to `MAX_OPEN_POSITIONS` = 64 (PerpEngine.sol:1477), which is a constant and strictly below the loop bound |
| PerpEngine.sol:1741 | caller-supplied `n`, clamped down to `badgesOwed` (PerpEngine.sol:1732) | liquidations grow the owed count (PerpEngine.sol:1722); the caller chooses how much to process |
| PerpMarkSource.sol:137 | `pools.length` < `MAX_POOLS` = 4 | the owner, up to the cap |
| PerpMarkSource.sol:150 | same | same |
| PerpMarkSource.sol:188 | same — and this one runs inside every swap, through `_writeObs` → `_currentTick` (PerpEngine.sol:686) | the owner, up to the cap |

`PerpVault` contains no loops at all — every path is O(1) in the number of stakers.

---

## F. Denomination and units

- **Amount conversion is price-based; THRESHOLD conversion is decimals-based.** Every token/quote amount conversion still goes through the pool's Q96 sqrt price — `_quoteAt` (PerpEngine.sol:783) and `_ethToToken` (PerpEngine.sol:1496), both now delegating to `PerpSwapLib` (PerpSwapLib.sol:91, PerpSwapLib.sol:96) — so no decimal correction is needed there. Separately, `PerpSwapLib.unitOf` (PerpSwapLib.sol:37) DOES staticcall `decimals()` once at quote adoption (PerpEngine.sol:1243) and stores `quoteUnit` (PerpEngine.sol:554); `_q` (PerpEngine.sol:568) then rescales the four absolute wei-written thresholds: the tier depths (PerpEngine.sol:771), `minCollateral` (PerpEngine.sol:860, PerpEngine.sol:897), `insuranceFloor` on open (PerpEngine.sol:868, PerpEngine.sol:906) and the skim floor (PerpEngine.sol:2013).
- `quote` (PerpEngine.sol:184) is the single denomination switch, written only at PerpEngine.sol:1245, alongside `quoteUnit` (PerpEngine.sol:1243). `_quoteIsNative` (PerpEngine.sol:187) branches every transport.
- The `*Eth` identifiers are vestigial labels for "quote units" — the contract says so at PerpEngine.sol:391-411, and the vault repeats it at PerpVault.sol:69-90.
- Mixed-unit sums that are internally consistent: `totalEth` (PerpEngine.sol:517) adds two **Q** counters; `totalTokenAssets` (PerpEngine.sol:521) adds two **T** counters; `skimInsurance` (PerpEngine.sol:2012) converts the **T** side to **Q** with `_quoteEth` before adding.
- Native/ERC20 crossing points: `creditPerpFee` (PerpEngine.sol:1780) and `creditPerpFeeToken` (PerpEngine.sol:1785) are `payable` and their shared body credits `msg.value` (PerpEngine.sol:1839) without a native check; `creditPerpFeeAsset` (PerpEngine.sol:1810) is the ERC20 twin and refuses any asset other than the live `quote`, and credits `plv` for BOTH trade directions (its own note at PerpEngine.sol:1794-1804 records the missing side split).
- Fixed-point scales: `BPS` = 10_000 (PerpEngine.sol:102); `Q96` (PerpEngine.sol:103); the funding index is 1e18-scaled (PerpEngine.sol:806, consumed at PerpEngine.sol:823); the badge's entry/liq prices are 1e18-scaled quote-per-token (PerpEngine.sol:1692-1693); the vault's reward accumulator uses `ACC` = 1e18 (PerpVault.sol:120) and its virtual share offset is `OFFSET` = 1e6 (PerpVault.sol:64), so one asset unit mints ~1e6 shares.
- Width truncations: collateral is stored as `uint128` (PerpEngine.sol:1480); badge stats clamp to `uint96`/`uint128` rather than reverting (PerpEngine.sol:1698-1704); the observation ring packs `uint32` timestamps and an `int56` cumulative (PerpEngine.sol:269); the mark source's answer is cast `int24(v)` with no range check (PerpEngine.sol:622).
- Tick comparability is enforced, not assumed: `addPool` rejects any pool whose two currencies differ from the primary's in either slot (PerpMarkSource.sol:129-132), which is what keeps a cross-quote normalisation oracle off the liquidation path.

---

## G. `unchecked` blocks and rounding direction

| site | what is unchecked | effect |
|---|---|---|
| PerpEngine.sol:672 | the whole `_writeObs` body: `nowTs - lastObsTs` (PerpEngine.sol:673), the `int56` integration (PerpEngine.sol:676), `nowTs - lastRingTs` (PerpEngine.sol:680), the ring index mask (PerpEngine.sol:682) | uint32 epoch wrap yields the modulo-2^32 delta instead of a panic |
| PerpEngine.sol:711 | `nowTs - twapWindow` | a target before the epoch wraps rather than panicking |
| PerpEngine.sol:729 | `nowTs - oldest.ts` | same |
| PerpEngine.sol:744 | the tail extrapolation and span (PerpEngine.sol:745-746) | same |
| PerpEngine.sol:772 | `++i` in the tier loop | gas only |
| PerpEngine.sol:1085 | `iters++` in the drain loop | gas only |
| PerpEngine.sol:1544 | `payoutOwed[to] += amount; payoutOwedTotal += amount` | an overflow would wrap the credit and the aggregate together |
| PerpSwapLib.sol:73, PerpSwapLib.sol:78 | `gasleft() - 120_000` | guarded by the 200k tests at PerpSwapLib.sol:71 and PerpSwapLib.sol:77 (the engine's own 300k check is at PerpEngine.sol:1719) |
| PerpEngine.sol:1722 | `badgesOwed[to] += 1` | gas only in practice |
| PerpEngine.sol:1741 | `++i` in the mint loop | gas only |

Rounding — every division in the cluster is integer and there is no rounding-up helper anywhere:

- Fee, penalty, keeper and cap arithmetic `(x * bps) / BPS` floors: PerpEngine.sol:1465, PerpEngine.sol:1345, PerpEngine.sol:1347, PerpEngine.sol:1363, PerpEngine.sol:867, PerpEngine.sol:872, PerpEngine.sol:940, PerpEngine.sol:1272, PerpEngine.sol:1471, PerpEngine.sol:2012. Caps therefore bind slightly EARLIER than the nominal ratio and fees are slightly smaller.
- `_quoteAt` (PerpEngine.sol:783) and `_ethToToken` (PerpEngine.sol:1496) use `FullMath.mulDiv` inside `PerpSwapLib` (PerpSwapLib.sol:92, PerpSwapLib.sol:97), which floors. A floored mark value makes a long marginally more likely to be underwater at PerpEngine.sol:1272 and a short marginally less likely at PerpEngine.sol:1277.
- Signed divisions truncate toward ZERO, not toward minus infinity: the funding step (PerpEngine.sol:806), the per-position funding delta (PerpEngine.sol:823), the TWAP tick (PerpEngine.sol:749) and the weighted tick (PerpMarkSource.sol:201). For a negative tick this biases the mark upward by up to one tick.
- Vault share math floors in the vault's favour on BOTH sides: shares minted (PerpVault.sol:225, PerpVault.sol:380) and assets owed (PerpVault.sol:268, PerpVault.sol:411) both use `mulDiv`; the `+ OFFSET` / `+ 1` terms (PerpVault.sol:64) are the inflation guard. `_haircut` (PerpVault.sol:309) floors toward the vault by design. The reward accumulator (PerpVault.sol:356) and its per-user settle (PerpVault.sol:363, PerpVault.sol:369) also floor, so dust accrues to the pot.

---

## H. Comment-vs-code observations

1. Comment at PerpEngine.sol:257-259 says a full ring takes `CARDINALITY x OBS_INTERVAL`, quotes that as ~68 minutes, and assumes 30-second minimum spacing; code declares `OBS_CARDINALITY` = 32 at PerpEngine.sol:263 and `OBS_INTERVAL` = 15 seconds at PerpEngine.sol:267 — 8 minutes.
2. Comment at PerpEngine.sol:1067 says `forceCloseAllDead` is "bounded to 64 per call"; code bounds the loop by `FORCE_CLOSE_MAX` at PerpEngine.sol:1082, declared as 96 at PerpEngine.sol:164.
3. Comment at PerpEngine.sol:1317 says the settlement tail was "extracted to {PerpOps}"; the code computes it inline from PerpEngine.sol:1329 and no such library exists in the tree.
4. Comment at PerpEngine.sol:1539-1540 says the payout forwards "bounded gas so a recipient cannot consume the settlement's budget"; in `_tryPush` only the native branch bounds it (PerpEngine.sol:1565), the ERC20 branch (PerpEngine.sol:1568 -> PerpSwapLib.sol:132) forwards everything. The doc block at PerpEngine.sol:1553 now states the cap as applying to the NATIVE forward specifically.
5. `@notice` at PerpEngine.sol:1963-1964 says a wired vault may only be re-pointed "while the PLV is EMPTY (plv/plvToken/tokYieldEth all 0)"; the code at PerpEngine.sol:1978 instead asks the outgoing vault `hasStakers()`. The later note at PerpEngine.sol:1967-1976 explains the replacement, but the `@notice` above it still states the old rule.
6. Comment at PerpEngine.sol:964 documents `selfSweep` as called by the engine on itself; the guard at PerpEngine.sol:965 tests `address(this)` but reverts with `OnlyHook`.
7. Comment at PerpEngine.sol:500 refers to "the hook-driven `liquidateInSwap`"; no such function exists in the cluster — the hook-driven entry is `sweepLiquidations` (PerpEngine.sol:955).
8. Comment at PerpEngine.sol:1008 attributes the discarded sweep result to `CauldronHook.sol:912`; that line is a comment inside the native fee-path branch, and the `sweepLiquidations` call site is CauldronHook.sol:950 (the bounded-gas call at CauldronHook.sol:949). The same comment cites `minCollateral` at ":131"; PerpEngine.sol:132 is `warmup` and `minCollateral` is declared at PerpEngine.sol:145.
9. Comment at PerpEngine.sol:1442-1443 says `quote` is "adopted only in {syncGeneration} (:1027), which refuses while `openCount != 0` (:987)"; the adoption is at PerpEngine.sol:1245 inside the function that starts at PerpEngine.sol:1098, and the `openCount` refusals are at PerpEngine.sol:1110 and PerpEngine.sol:1163.
10. Comment at PerpEngine.sol:124 points at "`markSource` at :462"; PerpEngine.sol:462 is inside an event declaration block and `markSource` is declared at PerpEngine.sol:550.
11. Header comment at PerpEngine.sol:87 says the open fee is "6.9%-of-collateral"; `_takeFee` (PerpEngine.sol:1465) computes it on the amount SENT and collateral is the remainder (PerpEngine.sol:1467), so the fee is 6.9% of gross, not of collateral.
12. Header comment at PerpMarkSource.sol:17-18 says the engine reads `slot0` of the one pool "built from `registry.generationQuote(gen)`"; `_key` (PerpEngine.sol:534) builds it from the engine's own CACHED `quote` slot, whose only writer is PerpEngine.sol:1245.
13. Comment at PerpVault.sol:154 describes `assetsEth` as "the engine's ETH PLV minus queued exits"; the code at PerpVault.sol:186 uses `engine.totalEth()`, which is `plv + longOiEth` (PerpEngine.sol:517), i.e. it includes capital lent out to open longs.
14. The doc-block heading of `retirePayout` says "Timelock-only." (PerpEngine.sol:1573); the code calls `_checkOwner()` only while the engine's `quote` agrees with the generation's (PerpEngine.sol:1615) and is otherwise open to anyone. A later paragraph of the same block (PerpEngine.sol:1597-1607) documents the permissionless branch.
15. `PerpVault`'s invariant note says the engine "refuses to adopt a new quote while {hasQuoteStake} is true" (PerpVault.sol:88, repeated at PerpVault.sol:101); the engine's guard calls the broader `hasStakers()` (PerpEngine.sol:1208) and never calls `hasQuoteStake()`. The implementation (PerpVault.sol:179) and its interface declaration (PerpEngine.sol:48) have no production caller — only tests.
16. The comment above `skimInsurance` says `insuranceFloor` "defaults to 0 and is never set by the deploy script" (PerpEngine.sol:2003), while the comment inside `syncGeneration` says the deploy script arms `INSURANCE_FLOOR_WEI = 0.05 ether` (PerpEngine.sol:1193). The code reads only the stored value (PerpEngine.sol:2013).
17. In-comment line pointers inside `syncGeneration` are stale: the note cites `_pushQuote` at ":1553" (PerpEngine.sol:1166) and `_safeTransfer` at ":1473" (PerpEngine.sol:1171), while those functions are declared at PerpEngine.sol:213 and PerpEngine.sol:1743.
18. The comment above `_quoteAt` says the body lives in `PerpSwapLib` for EIP-170 headroom (PerpEngine.sol:779-782) and it does (PerpEngine.sol:784) — which is why the function is now `view` rather than `pure`; the `@dev` line above it still describes the arithmetic as if it were local.
19. The section header at PerpVault.sol:477 announces "internal ERC20 helpers" and is the last line before the closing brace; the helpers it names are defined far earlier, at PerpVault.sol:249 and PerpVault.sol:256.

---

## Cluster extra 1 — solvency accounting

Every quantity that must cover another, with the lines that maintain it.

**(S1) `plv` must cover what longs may borrow.** Enforced per open at PerpEngine.sol:862 (`borrow > plv` reverts) and again as a share of the whole book at PerpEngine.sol:867 (`longOiEth + borrow <= totalEth() * maxUtilBps / BPS`, only while a vault is wired). Repaid at PerpEngine.sol:1293, capped at the principal so a shortfall never credits more than the loan.

**(S2) `plvToken` must cover what shorts may borrow.** Enforced at PerpEngine.sol:902 and PerpEngine.sol:905. Restored IN FULL at PerpEngine.sol:1306, because the buy-back at PerpEngine.sol:1305 is exact-output — this is the mechanism that makes token principal structurally protected, and the vault's header states it at PerpVault.sol:37-41.

**(S3) Per-side open interest must stay inside pool depth.** `longOiEth + borrow <= activeEthDepth() * maxOiBps / BPS` at PerpEngine.sol:872; the token-side mirror at PerpEngine.sol:908 converts depth into token units first. Single-position notional is separately capped at PerpEngine.sol:1471.

**(S4) A position's mark value must cover its debt plus the maintenance buffer.** Long: PerpEngine.sol:1272. Short: PerpEngine.sol:1277, where backing is `collateral + principal` (PerpEngine.sol:1275). Violation is exactly the liquidation trigger.

**(S5) `insuranceEth` covers bad debt before LP principal does.** Long shortfall: PerpEngine.sol:1643-1644 (insurance → `plv`). Short overspend: PerpEngine.sol:1652-1655 (insurance first, then `plv` saturating at zero). Funding credit: PerpEngine.sol:1336-1340 (insurance first, then `plv`, never overdrawing either).

**(S6) Funding paid in must cover funding paid out.** The payer is capped by its OWN residual at PerpEngine.sol:1332, so it can pay less than it owes; the receiver draws the difference from insurance and then `plv` at PerpEngine.sol:1336-1340. Per-position magnitude is bounded to `maxFundingBps` of collateral at PerpEngine.sol:824, and the global rate is bounded at PerpEngine.sol:1917.

**(S7) The liquidation penalty must fit inside the residual.** PerpEngine.sol:1346 clamps it, then PerpEngine.sol:1347-1348 carves the keeper cut out of the clamped figure, so neither can drive `residual` negative.

**(S8) `insuranceEth` must stay above the risk floor before any skim.** PerpEngine.sol:2012-2015: protection is the greater of the configured `insuranceFloor` and `maintenanceBps` of live two-sided open interest, valued at SPOT.

**(S9) Vault shares plus queued claims must not exceed the engine's book.** `assetsEth()`/`assetsTok()` subtract the queue (PerpVault.sol:187, PerpVault.sol:192), saturating at zero; when backing falls below the queue, `_haircut` (PerpVault.sol:308-309) writes every claimant down pro rata and persists it (PerpVault.sol:318, PerpVault.sol:433).

**(S10) Instant payment must not exceed free capital.** PerpVault.sol:270 and PerpVault.sol:413 cap payment at `engine.freeEth()`/`freeToken()`; the engine re-checks at PerpEngine.sol:1862 and PerpEngine.sol:1885 and reverts `PlvInsufficient` otherwise.

**(S11) The token-side reward pot must cover attributed claims.** PerpEngine.sol:1874 bounds every payment by `tokYieldEth`; the vault only ever asks for a figure it has already settled into `tokRewardOwed` (PerpVault.sol:364). Yield accrued at zero shares is never attributed (PerpVault.sol:355), so the pot is always at least the sum of attributed claims.

**(S13) A quote adoption must not leave an old-asset claim payable in the new asset.** `payoutOwedTotal` (PerpEngine.sol:371) is the enumerable-mapping substitute: `_payOut` raises it with every credit (PerpEngine.sol:1544), `claimPayout` (PerpEngine.sol:1636) and `retirePayout` (PerpEngine.sol:1617) lower it, and the adoption refuses while it is non-zero (PerpEngine.sol:1207). `retirePayout` (PerpEngine.sol:1612) is the escape hatch that keeps that guard satisfiable, pushing at FULL gas (PerpEngine.sol:1623) and retiring the claim either way.

**(S14) Token inventory that does not migrate must stay on the books.** `syncGeneration` re-points `plvToken` to the engine's real balance (PerpEngine.sol:1138) but first books the difference against the old token at `strandedToken` (PerpEngine.sol:1135) and emits `TokenInventoryStranded` (PerpEngine.sol:1136); the library also emits `InventoryMigrationShortfall` with the raw revert reason (PerpSwapLib.sol:274). Neither reverts — a reverting sync is the brick shape.

**(S12) The book must be drainable in one call.** `MAX_OPEN_POSITIONS` = 64 (PerpEngine.sol:1477) is a constant and is strictly below `FORCE_CLOSE_MAX` = 96 (PerpEngine.sol:1082); `_payOut` never reverts (PerpEngine.sol:1544), so no single position can block the drain. This is what makes `openCount == 0` reachable, which `syncGeneration` demands at PerpEngine.sol:1110.

---

## Cluster extra 2 — the liquidation path, end to end

**Entry, three ways.**
- `liquidate(id)` PerpEngine.sol:930 — any caller, `nonReentrant` + `notNested`, reverts `Healthy` or `LiqCapped` on refusal.
- `sweepLiquidations(liquidator)` PerpEngine.sol:955 — hook-only, from afterSwap on every trade on any interface, `inLocked = true`, no reentrancy modifier.
- `selfSweep(liquidator)` PerpEngine.sol:964 — engine-only, reached from `_sweepAfterOpen` (PerpEngine.sol:974) with a gas reserve and a swallowing catch.

**1. Oracle and funding.** `_pokeFunding` (PerpEngine.sol:933 / PerpEngine.sol:992) runs first. It calls `_writeObs` (PerpEngine.sol:793), which integrates the elapsed interval at `lastTick`, appends to the ring if `OBS_INTERVAL` has passed, and always refreshes `lastTick` from `_currentTick` (PerpEngine.sol:686). Then it accrues `fundingIndex` (PerpEngine.sol:808) from the mark-valued imbalance.

**2. Selection.** The sweep reads a rotating window of `_openIds` starting at `sweepCursor` (PerpEngine.sol:997), at most `SWEEP_SCAN` checks and `MAX_LIQ_PER_SWAP` kills, breaking below `SWEEP_KILL_RESERVE` gas (PerpEngine.sol:1016). After a kill the cursor does NOT advance, because the swap-and-pop put a new id in the same slot (PerpEngine.sol:1024).

**3. Health test.** `_quoteMark(p.size)` (PerpEngine.sol:935 / PerpEngine.sol:1040) is computed ONCE and reused both for the test and as the throttle notional. `_underwaterVal` (PerpEngine.sol:1269) applies the long or short form.

**4. Throttle.** Reset when the timestamp changed (PerpEngine.sol:939 / PerpEngine.sol:1044), cap = `activeEthDepth() * maxLiqBps / BPS` (PerpEngine.sol:940 / PerpEngine.sol:1045), and the cap is skipped entirely when it computes to zero. The keeper path reverts `LiqCapped`; the sweep path silently returns (PerpEngine.sol:1046).

**5. Settlement — `_settle(id, p, 0, MODE_LIQUIDATION, keeper)`.**
- effects first: delete (PerpEngine.sol:1282), remove from the set (PerpEngine.sol:1283), `openCount--` (PerpEngine.sol:1284);
- long: `longOiEth -= principal` (PerpEngine.sol:1289), sell the held token (PerpEngine.sol:1290), repay at most the principal into `plv` (PerpEngine.sol:1293), top up from insurance (PerpEngine.sol:1298), `residual = proceeds - repay` (PerpEngine.sol:1299) — which is 0 whenever the position was underwater;
- short: `shortOiToken -= size` (PerpEngine.sol:1301), exact-output buy-back (PerpEngine.sol:1305), inventory restored (PerpEngine.sol:1306), overspend absorbed (PerpEngine.sol:1311), `residual = backing - cost` (PerpEngine.sol:1312);
- `minOut` is NOT enforced, because `ownerSlippage` is false outside `MODE_NORMAL` (PerpEngine.sol:1286);
- funding transfer (PerpEngine.sol:1329-1342);
- penalty = `liqPenaltyBps` of collateral, clamped to residual (PerpEngine.sol:1345-1346); keeper cut = `keeperBps` of the penalty (PerpEngine.sol:1347); the rest is routed as a fee, side-attributed by `p.isLong` (PerpEngine.sol:1349);
- keeper paid through the non-reverting `_payOut` (PerpEngine.sol:1350), `Liquidated` emitted (PerpEngine.sol:1351);
- trophy: `_killStats` (PerpEngine.sol:1360) snapshots entry/liq prices, `_awardBadge` (PerpEngine.sol:1708) checks 300k gas (PerpEngine.sol:1719) and delegatecalls `PerpSwapLib.tryMintBadge` (PerpSwapLib.sol:70), which tries the stats mint then the plain mint under its own 200k floor (PerpSwapLib.sol:71) and falls back to `badgesOwed` (PerpEngine.sol:1722). The `hook.collection()` read itself (PerpEngine.sol:1720) is un-caught and outside the best-effort boundary;
- trader paid the remaining residual (PerpEngine.sol:1366) and `Closed` emitted (PerpEngine.sol:1367).

**6. Swap execution.** Every leg goes through `_run` (PerpEngine.sol:1380): in-lock during a sweep, a fresh `unlock` otherwise. `_swapBody` (PerpEngine.sol:1401) derives leg orientation from `syncedToken` and delegates to `PerpSwapLib.swapLeg`, which settles the pay leg and takes the receive leg with NO internal slippage bound.

**7. Claims afterwards.** Every settlement push goes through `_payOut` (PerpEngine.sol:1541) -> `_tryPush` (PerpEngine.sol:1563), which reports instead of reverting; whatever it could not deliver is claimable at `claimPayout` (PerpEngine.sol:1632) or retirable at `retirePayout` (PerpEngine.sol:1612). Unminted trophies at `claimLiquidatorBadges` (PerpEngine.sol:1730).

**Death variant.** `forceCloseDead` (PerpEngine.sol:1057) and `forceCloseAllDead` (PerpEngine.sol:1072) run the same `_settle` with `MODE_DEATH`: no penalty, no badge, and the caller takes `keeperBps` of the residual (PerpEngine.sol:1363). Both require `_isDead()` (PerpEngine.sol:1460).

---

## Cluster extra 3 — mark and price sources, with fallback order

**A. The tick — `_currentTick` (PerpEngine.sol:607).** Every sample in the system starts here.
1. `markSource` if non-zero — hand-rolled `staticcall` (PerpEngine.sol:615), accepted only when the call succeeded AND `returndatasize() == 32` (PerpEngine.sol:619);
2. otherwise `poolManager.getSlot0(_key().toId())` (PerpEngine.sol:624).
A source that reverts, self-destructs, is unset or returns the wrong width degrades silently to (2).

**B. Inside the mark source — `PerpMarkSource.weightedTick` (PerpMarkSource.sol:173).**
1. not armed → tick `0` (PerpMarkSource.sol:174) — note this is a *valid-looking* answer to the engine, not a failure;
2. no sibling pools → the primary's tick (PerpMarkSource.sol:180);
3. siblings present but no in-range liquidity anywhere → the primary's tick (PerpMarkSource.sol:200);
4. otherwise `sum(tick_i * L_i) / sum(L_i)` (PerpMarkSource.sol:186-201), skipping any pool with zero in-range depth (PerpMarkSource.sol:191). The primary's tick is always in the sum, weighted by its own liquidity, even when that is zero.

**C. The liquidation mark — `markSqrtPriceX96` (PerpEngine.sol:754).**
1. `twapTick()` (PerpEngine.sol:707) if it returns ok;
2. otherwise SPOT via `_sqrtP()` (PerpEngine.sol:756); the tick-to-price step itself is `PerpSwapLib.sqrtPriceAtTick` (PerpSwapLib.sol:52), which reverts on an out-of-range tick rather than falling back.

**D. Inside the TWAP — `twapTick` (PerpEngine.sol:707).**
1. `now <= MIN_TWAP` → not ok (PerpEngine.sol:709);
2. ring empty → not ok (PerpEngine.sol:722);
3. oldest entry newer than the target → use the oldest, but only if it spans `MIN_TWAP`, else not ok (PerpEngine.sol:729);
4. otherwise binary-search the newest entry at or before the target (PerpEngine.sol:734-740);
5. zero span → not ok (PerpEngine.sol:748).
The un-recorded tail is always extrapolated at `lastTick` (PerpEngine.sol:745), which `_writeObs` refreshes unconditionally (PerpEngine.sol:686).

**E. Spot — `_sqrtP` (PerpEngine.sol:540).** A direct `slot0` read of the single pool `_key()` names. No fallback: an uninitialised pool returns 0, which `activeEthDepth` special-cases (PerpEngine.sol:762) and `_ethToToken` does not.

**Which decision uses which:**

| decision | source |
|---|---|
| liquidation trigger (PerpEngine.sol:1272, PerpEngine.sol:1277) | MARK (C) |
| per-timestamp liquidation throttle notional (PerpEngine.sol:940, PerpEngine.sol:1045) | MARK (C) |
| funding imbalance sizing (PerpEngine.sol:801) | MARK (C) |
| badge liq price (PerpEngine.sol:1693) | MARK (C) |
| UI health (PerpEngine.sol:2035) | MARK (C) |
| short borrow sizing (PerpEngine.sol:901) | SPOT (E) |
| open-interest cap in token units (PerpEngine.sol:908) | SPOT (E) |
| depth for leverage tiers, notional and OI caps (PerpEngine.sol:759) | SPOT (E) |
| insurance risk floor (PerpEngine.sol:2012) | SPOT (E) |
| actual execution price of every leg | the pool itself, unbounded inside PerpSwapLib (PerpSwapLib.sol:176) |
| pool identity for all of the above | the CACHED `quote` (PerpEngine.sol:534), not `registry.generationQuote` |

**F. Two warm-ups gate opens, none gate liquidations.** `_guardOpen` (PerpEngine.sol:1428) takes the LATER of `registry.lastSummonAt() + warmup` (PerpEngine.sol:1435) and `ringArmedAt + twapWindow` (PerpEngine.sol:1436). `ringArmedAt` is stamped only where the ring is wiped (PerpEngine.sol:1148) and not in the constructor, so after a sync no position can be opened until the ring genuinely spans the window again — but closes, liquidations and the in-swap sweep never pass through this guard and still price off the post-wipe mark, whose fallback trusts as little as `MIN_TWAP` (PerpEngine.sol:268).

**G. A quote flip drops the mark source.** `syncGeneration` zeroes `markSource` (PerpEngine.sol:1241) when the quote changes, so `_currentTick` falls back to the engine's own `_key()` pool (PerpEngine.sol:624) rather than a source still armed on the old pair; the death test cannot catch that case because by that line `quote` and `generationQuote` agree (PerpEngine.sol:1461).

There is no external price oracle on any path in this cluster; `PerpMarkSource.addPool` (PerpMarkSource.sol:129-132) exists precisely to keep one off the liquidation path.

---

## I. Function inventory

One line per skeleton node: `file:line` — signature — authority — value effect.


### IPerpRegistry (declared in PerpEngine.sol)

- `PerpEngine.sol:23` — `function currentToken() external view returns (address)` — **anyone (declaration only; the engine calls it on the immutable `registry`)** — NONE
- `PerpEngine.sol:27` — `function generationQuote(uint256 gen) external view returns (address)` — **anyone (declaration only; the engine calls it on the immutable `registry`)** — NONE
- `PerpEngine.sol:28` — `function currentGeneration() external view returns (uint256)` — **anyone (declaration only; the engine calls it on the immutable `registry`)** — NONE
- `PerpEngine.sol:29` — `function lastSummonAt() external view returns (uint256)` — **anyone (declaration only; the engine calls it on the immutable `registry`)** — NONE
- `PerpEngine.sol:30` — `function generationPoolId(uint256) external view returns (PoolId)` — **anyone (declaration only)** — NONE
- `PerpEngine.sol:31` — `function generationToken(uint256) external view returns (address)` — **anyone (declaration only)** — NONE
- `PerpEngine.sol:32` — `function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256)` — **anyone (declaration only)** — NONE
- `PerpEngine.sol:33` — `function claimByBurnUpTo(uint256 fromGen, uint256 maxAmount) external returns (uint256)` — **anyone (declaration only)** — NONE

### IMarkSource (declared in PerpEngine.sol)

- `PerpEngine.sol:41` — `function weightedTick() external view returns (int24)` — **anyone (declaration only; only its 4-byte selector is used)** — NONE

### IPerpVaultStake (declared in PerpEngine.sol)

- `PerpEngine.sol:46` — `function hasStakers() external view returns (bool)` — **anyone (declaration only; the engine calls it on `vault`)** — NONE
- `PerpEngine.sol:48` — `function hasQuoteStake() external view returns (bool)` — **anyone (declaration only)** — NONE

### IPerpHook (declared in PerpEngine.sol)

- `PerpEngine.sol:52` — `function isDead(PoolId id) external view returns (bool)` — **anyone (declaration only; the engine calls it on the immutable `hookAddr`)** — NONE
- `PerpEngine.sol:54` — `function collection() external view returns (address)` — **anyone (declaration only; the engine calls it on the immutable `hookAddr`)** — NONE

### PerpEngine

- `PerpEngine.sol:187` — `function _quoteIsNative() internal view returns (bool)` — **internal (callers: _pullQuote, _pushQuote, _payOut)** — NONE
- `PerpEngine.sol:195` — `function _pullQuote(address from, uint256 amount) internal` — **internal (callers: openLong, openShort, fundPlv, fundInsurance, _pullIntoPlv)** — asserts the native value (line 197) already arrived with the call; on an ERC20 book it refuses any value (line 199) and pulls amount from from through tryTransferFrom (line 206)
- `PerpEngine.sol:213` — `function _pushQuote(address to, uint256 amount) internal` — **internal (callers: _sendEth, claimPayout)** — sends native to to (line 216); ERC20 transfer of the quote to to via _safeTransfer (line 219)
- `PerpEngine.sol:453` — `function renounceOwnership() public pure override` — **anyone, but it always reverts** — NONE
- `PerpEngine.sol:475` — `constructor( IPoolManager _poolManager, address _hook, address _registry, address _mifrens, address _dividend,...` — **deployer** — NONE
- `PerpEngine.sol:505` — `modifier notNested()` — **internal (applied to: openLong, openShort, close, liquidate, forceCloseDead, forceCloseAllDead, syncGeneration, fundPlv, fundPlvToken, withdrawPlvTo, withdrawTokYieldTo, withdrawPlvTokenTo)** — NONE
- `PerpEngine.sol:509` — `modifier onlyVault()` — **internal (applied to: fundFromVault, withdrawPlvTo, withdrawTokYieldTo, fundTokenFromVault, withdrawPlvTokenTo)** — NONE
- `PerpEngine.sol:517` — `function totalEth() public view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:519` — `function freeEth() external view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:521` — `function totalTokenAssets() public view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:523` — `function freeToken() external view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:533` — `function _key() internal view returns (PoolKey memory)` — **internal (callers: _sqrtP, _currentTick, activeEthDepth, _swapBody, _isDead)** — NONE
- `PerpEngine.sol:540` — `function _sqrtP() internal view returns (uint160 s)` — **internal (callers: markSqrtPriceX96, _quoteEth, activeEthDepth, _ethToToken)** — NONE
- `PerpEngine.sol:568` — `function _q(uint256 wei18) internal view returns (uint256)` — **internal (callers: maxLeverage, openLong, openShort, skimInsurance)** — NONE
- `PerpEngine.sol:607` — `function _currentTick() internal view returns (int24 t)` — **internal (callers: constructor, _writeObs, syncGeneration)** — NONE
- `PerpEngine.sol:631` — `function poke() external` — **anyone** — NONE
- `PerpEngine.sol:670` — `function _writeObs() internal` — **internal (callers: _pokeFunding)** — NONE
- `PerpEngine.sol:707` — `function twapTick() public view returns (int24 tick, bool ok)` — **anyone** — NONE
- `PerpEngine.sol:754` — `function markSqrtPriceX96() public view returns (uint160)` — **anyone (view)** — NONE
- `PerpEngine.sol:759` — `function activeEthDepth() public view returns (uint256)` — **anyone (view)** — NONE
- `PerpEngine.sol:766` — `function maxLeverage() public view returns (uint8 lev)` — **anyone (view)** — NONE
- `PerpEngine.sol:783` — `function _quoteAt(uint256 size, uint256 sp) internal view returns (uint256)` — **internal (callers: _quoteEth, _quoteMark)** — NONE
- `PerpEngine.sol:787` — `function _quoteEth(uint256 size) internal view returns (uint256)` — **internal (callers: skimInsurance)** — NONE
- `PerpEngine.sol:789` — `function _quoteMark(uint256 size) internal view returns (uint256)` — **internal (callers: _pokeFunding, liquidate, _tryLiquidate, _underwater, _killStats, positionHealth)** — NONE
- `PerpEngine.sol:792` — `function _pokeFunding() internal` — **internal (callers: poke, openLong, openShort, close, liquidate, _doSweep, forceCloseDead, forceCloseAllDead)** — NONE
- `PerpEngine.sol:817` — `function _fundingDelta(Position memory p) internal view returns (int256)` — **internal (callers: fundingDelta, _settle)** — NONE
- `PerpEngine.sol:830` — `function fundingDelta(uint256 id) external view returns (int256)` — **anyone** — NONE
- `PerpEngine.sol:851` — `function openLong(uint8 leverage, uint256 minTokenOut, uint256 liqHint, uint256 amount) public payable nonReen...` — **anyone (the open conditions are enforced in _guardOpen)** — takes the collateral in through _pullQuote (line 855) — native value or an ERC20 pull — and pays the open fee out through _takeFee (line 859)
- `PerpEngine.sol:888` — `function openShort(uint8 leverage, uint256 minEthOut, uint256 liqHint, uint256 amount) public payable nonReent...` — **anyone (the open conditions are enforced in _guardOpen)** — takes collateral in through _pullQuote (line 892) and holds the sale proceeds (line 911) as backing for the token debt
- `PerpEngine.sol:923` — `function close(uint256 id, uint256 minOut) external nonReentrant notNested` — **the position's trader** — pays out through _settle (line 927)
- `PerpEngine.sol:930` — `function liquidate(uint256 id) external nonReentrant notNested` — **anyone (subject to the position being underwater at the mark)** — pays the keeper and trader through _settle (line 943)
- `PerpEngine.sol:955` — `function sweepLiquidations(address liquidator) external` — **hook** — pays keepers and traders through _doSweep (line 957)
- `PerpEngine.sol:964` — `function selfSweep(address liquidator) external` — **the engine itself** — pays keepers and traders through _doSweep (line 966)
- `PerpEngine.sol:970` — `function _sweepAfterOpen(address liquidator) internal` — **internal (callers: openLong, openShort)** — NONE
- `PerpEngine.sol:980` — `function _doSweep(address liquidator, bool inLocked) internal` — **internal (callers: sweepLiquidations, selfSweep)** — pays keepers and traders through _tryLiquidate (line 1021)
- `PerpEngine.sol:1035` — `function _tryLiquidate(uint256 id, address liquidator) internal` — **internal (callers: _doSweep)** — pays the keeper and trader through _settle (line 1048)
- `PerpEngine.sol:1057` — `function forceCloseDead(uint256 id) external nonReentrant notNested` — **anyone (once the generation is dead)** — pays the keeper and trader through _settle (line 1062)
- `PerpEngine.sol:1072` — `function forceCloseAllDead() external nonReentrant notNested` — **anyone (once the generation is dead); driven by the hook at relaunch** — pays the keeper and every trader through _settle (line 1084)
- `PerpEngine.sol:1098` — `function syncGeneration() external nonReentrant notNested` — **anyone (permissionless re-arm)** — on a quote flip it sweeps the summed plv, tokYieldEth and insuranceEth (line 1218) to the treasury through _tryPush (line 1228), in the OLD asset, before quote (line 1245) is reassigned
- `PerpEngine.sol:1253` — `function isLiquidatable(uint256 id) external view returns (bool)` — **anyone** — NONE
- `PerpEngine.sol:1260` — `function _underwater(Position memory p) internal view returns (bool)` — **internal (callers: isLiquidatable, positionHealth)** — NONE
- `PerpEngine.sol:1269` — `function _underwaterVal(Position memory p, uint256 val) internal view returns (bool)` — **internal (callers: liquidate, _tryLiquidate, _underwater)** — NONE
- `PerpEngine.sol:1281` — `function _settle(uint256 id, Position memory p, uint256 minOut, uint8 mode, address keeper) internal` — **internal (callers: close, liquidate, _tryLiquidate, forceCloseDead, forceCloseAllDead)** — pays the keeper through _payOut (line 1350) and the trader through _payOut (line 1366)
- `PerpEngine.sol:1377` — `function _run(SwapReq memory r) internal returns (bytes memory)` — **internal (callers: _swapExactIn, _buyExactOut)** — NONE
- `PerpEngine.sol:1384` — `function _swapExactIn(bool buy, uint256 amount) internal returns (uint256 out)` — **internal (callers: openLong, openShort, _settle)** — NONE
- `PerpEngine.sol:1389` — `function _buyExactOut(uint256 tokenOut) internal returns (uint256 ethSpent)` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1393` — `function unlockCallback(bytes calldata raw) external returns (bytes memory)` — **pool manager** — settles pool legs through _swapBody (line 1395)
- `PerpEngine.sol:1401` — `function _swapBody(SwapReq memory r) internal returns (bytes memory)` — **internal (callers: _run, unlockCallback)** — settles both currency legs through swapLeg (line 1414)
- `PerpEngine.sol:1428` — `function _guardOpen(uint8 leverage) internal view` — **internal (callers: openLong, openShort)** — NONE
- `PerpEngine.sol:1460` — `function _isDead() internal view returns (bool)` — **internal (callers: forceCloseDead, forceCloseAllDead, _guardOpen)** — NONE
- `PerpEngine.sol:1464` — `function _takeFee(uint256 sent, bool longSide) internal returns (uint256 collateral)` — **internal (callers: openLong, openShort)** — routes the fee out through _routeFee (line 1468)
- `PerpEngine.sol:1470` — `function _checkNotional(uint256 notionalEth) internal view` — **internal (callers: openLong, openShort)** — NONE
- `PerpEngine.sol:1473` — `function _book(address trader, bool isLong, uint256 collateral, uint256 size, uint256 principal, uint8 leverag...` — **internal (callers: openLong, openShort)** — NONE
- `PerpEngine.sol:1486` — `function _removeOpen(uint256 id) internal` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1496` — `function _ethToToken(uint256 eth) internal view returns (uint256)` — **internal (callers: openShort)** — NONE
- `PerpEngine.sol:1500` — `function _routeFee(uint256 amount, bool longSide) internal` — **internal (callers: _takeFee, _settle)** — pays the dividend and treasury through _payOut (line 1525)
- `PerpEngine.sol:1529` — `function _sendEth(address to, uint256 amount) internal` — **internal (callers: withdrawPlvTo, withdrawTokYieldTo, skimInsurance)** — sends the quote to to through _pushQuote (line 1529)
- `PerpEngine.sol:1541` — `function _payOut(address to, uint256 amount) internal` — **internal (callers: _settle, _routeFee)** — pushes amount (line 1543) of the quote to to through _tryPush, and books an IOU when that fails
- `PerpEngine.sol:1563` — `function _tryPush(address to, uint256 amount, bool capped) private returns (bool ok)` — **private (callers: syncGeneration, _payOut, retirePayout)** — sends native to to (line 1565) with a 30k budget when capped, or with all remaining gas at to (line 1566); on an ERC20 book transfers the quote via tryTransfer (line 1568)
- `PerpEngine.sol:1612` — `function retirePayout(address to) external` — **owner while the engine's quote matches the generation's; ANYONE while it diverges** — pushes the retired amount (line 1623) to to at FULL gas; the value is lost to the engine as residue if that push fails
- `PerpEngine.sol:1632` — `function claimPayout() external nonReentrant returns (uint256 amount)` — **anyone (clears only the caller's own credit)** — pays amount (line 1637) of the quote to the caller through the REVERTING push
- `PerpEngine.sol:1642` — `function _replenishPlv(uint256 shortfall) internal` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1651` — `function _absorbPlvLoss(uint256 loss) internal` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1687` — `function _killStats(Position memory p, uint256 bounty) internal view returns (LiqStats memory st)` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1708` — `function _awardBadge(uint256 id, address to, LiqStats memory st) internal` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1730` — `function claimLiquidatorBadges(uint256 n) external nonReentrant` — **anyone (burns only the caller's own credit)** — NONE
- `PerpEngine.sol:1743` — `function _safeTransfer(address token, address to, uint256 amount) private` — **private (callers: _pushQuote, withdrawPlvTokenTo)** — transfers amount (line 1744) of token out of the engine, reverting if the token reports failure
- `PerpEngine.sol:1756` — `function fundPlv(uint256 amount) external payable onlyOwner notNested` — **owner** — receives the quote through _pullQuote (line 1757)
- `PerpEngine.sol:1764` — `function fundPlvToken(uint256 amount) external onlyOwner notNested` — **owner** — ERC20 transferFrom of the generation token from the owner (line 1765)
- `PerpEngine.sol:1770` — `function fundInsurance(uint256 amount) external payable` — **anyone** — receives the quote through _pullQuote (line 1771)
- `PerpEngine.sol:1780` — `function creditPerpFee() external payable` — **hook** — receives native payable (line 1780)
- `PerpEngine.sol:1785` — `function creditPerpFeeToken() external payable` — **hook** — receives native payable (line 1785)
- `PerpEngine.sol:1806` — `function creditPerpFeeAsset(address asset, uint256 amount) external` — **hook only** — pulls amount (line 1811) of the quote from the hook into the ETH-side PLV
- `PerpEngine.sol:1816` — `function _pullIntoPlv(uint256 amount) private` — **private (callers: creditPerpFeeAsset, fundFromVault)** — receives the quote through _pullQuote (line 1817) and banks it as ETH-side PLV
- `PerpEngine.sol:1822` — `function _creditPerp(bool ethSide) private` — **hook only** — banks the incoming native value (line 1839) into the ETH-side PLV or the token-side reward pot
- `PerpEngine.sol:1855` — `function fundFromVault(uint256 amount) external payable onlyVault` — **vault only** — receives a depositor's stake through the shared _pullIntoPlv (line 1856)
- `PerpEngine.sol:1861` — `function withdrawPlvTo(uint256 amount, address to) external onlyVault notNested nonReentrant` — **vault only** — pays amount (line 1863) of the quote to to through the shared vault tail
- `PerpEngine.sol:1868` — `function _vaultPaid(uint256 amount, address to) private` — **private (callers: withdrawPlvTo, withdrawTokYieldTo)** — sends amount (line 1869) of the quote to to and emits the withdrawal event
- `PerpEngine.sol:1873` — `function withdrawTokYieldTo(uint256 amount, address to) external onlyVault notNested nonReentrant` — **vault only** — pays amount (line 1875) of the quote out of the segregated token-side pot
- `PerpEngine.sol:1878` — `function fundTokenFromVault(uint256 amount) external onlyVault` — **vault** — ERC20 transferFrom of the generation token from the vault (line 1879)
- `PerpEngine.sol:1884` — `function withdrawPlvTokenTo(uint256 amount, address to) external onlyVault notNested nonReentrant` — **vault** — ERC20 transfer of the generation token to to via _safeTransfer (line 1887)
- `PerpEngine.sol:1891` — `function setFees(uint256 _openBps, uint256 _ogDiscBps, uint256 _liqBps, uint256 _divShareBps, uint256 _keeperB...` — **owner** — NONE
- `PerpEngine.sol:1895` — `function setRisk(uint256 _warmup, uint256 _ceiling, uint256 _maintBps, uint256 _maxNotBps, uint256 _maxOiBps, ...` — **owner** — NONE
- `PerpEngine.sol:1932` — `function setTiers(uint256[] calldata depths, uint8[] calldata levs) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1946` — `function setRouting(address _dividend, address _treasury, address _nftBeneficiary, address _markSource) extern...` — **owner** — NONE
- `PerpEngine.sol:1956` — `function setGuards(uint32 _twapWindow, uint256 _maxLiqBps, uint256 _maxFundingBps) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1977` — `function setVault(address _vault) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1983` — `function setVaultSplit(uint256 _yieldBps, uint256 _insBps) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1989` — `function setVaultLimits(uint256 _maxUtilBps, uint256 _insuranceFloor) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1994` — `function setMinCollateral(uint256 _minCollateral) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:2010` — `function skimInsurance(uint256 amount, address to) external onlyOwner` — **owner** — sends amount (line 2017) of the quote to to through the REVERTING push
- `PerpEngine.sol:2029` — `function positionHealth(uint256 id) external view returns ( bool isLong, uint256 markValueEth, uint256 debtOrB...` — **anyone** — NONE
- `PerpEngine.sol:2040` — `receive() external payable` — **anyone** — receives native via receive (line 2040)

### PerpMarkSource

- `PerpMarkSource.sol:99` — `function renounceOwnership() public pure override` — **anyone, but it always reverts** — NONE
- `PerpMarkSource.sol:108` — `constructor(IPoolManager _poolManager, address _owner) Ownable(_owner)` — **deployer** — NONE
- `PerpMarkSource.sol:115` — `function setPrimary(PoolKey calldata key) external onlyOwner` — **owner** — NONE
- `PerpMarkSource.sol:126` — `function addPool(PoolKey calldata key) external onlyOwner` — **owner** — NONE
- `PerpMarkSource.sol:147` — `function removePool(PoolKey calldata key) external onlyOwner` — **owner** — NONE
- `PerpMarkSource.sol:161` — `function poolCount() external view returns (uint256)` — **anyone** — NONE
- `PerpMarkSource.sol:173` — `function weightedTick() external view returns (int24 tick)` — **anyone** — NONE

### IPerpShares (declared in PerpStakerOracle.sol)

- `PerpStakerOracle.sol:8` — `function ethShareOf(address who) external view returns (uint256)` — **anyone (declaration only; the oracle calls it on the immutable `perpVault`)** — NONE
- `PerpStakerOracle.sol:9` — `function tokShareOf(address who) external view returns (uint256)` — **anyone (declaration only; the oracle calls it on the immutable `perpVault`)** — NONE

### PerpStakerOracle

- `PerpStakerOracle.sol:24` — `constructor(address _perpVault)` — **deployer** — NONE
- `PerpStakerOracle.sol:29` — `function isInstant(address who) external view returns (bool)` — **anyone** — NONE

### PerpSwapLib

- `PerpSwapLib.sol:37` — `function unitOf(address q) external view returns (uint256)` — **engine (linked library; the only caller is PerpEngine.syncGeneration)** — NONE
- `PerpSwapLib.sol:52` — `function sqrtPriceAtTick(int24 t) external pure returns (uint160)` — **engine (linked library; the only caller is PerpEngine.markSqrtPriceX96)** — NONE
- `PerpSwapLib.sol:70` — `function tryMintBadge(address col, address to, LiqStats memory st) external returns (bool ok)` — **engine (linked library; the only caller is PerpEngine._awardBadge)** — NONE
- `PerpSwapLib.sol:91` — `function quoteAt(uint256 size, uint256 sp) external pure returns (uint256)` — **engine (linked library; the only caller is PerpEngine._quoteAt)** — NONE
- `PerpSwapLib.sol:96` — `function ethToToken(uint256 eth, uint256 sp) external pure returns (uint256)` — **engine (linked library; the only caller is PerpEngine._ethToToken)** — NONE
- `PerpSwapLib.sol:102` — `function ethDepth(uint128 L, uint160 sp) external pure returns (uint256)` — **engine (linked library; the only caller is PerpEngine.activeEthDepth)** — NONE
- `PerpSwapLib.sol:123` — `function tryTransferFrom(address token, address from, uint256 amount) external returns (bool)` — **engine (linked library; the only caller is PerpEngine._pullQuote)** — pulls amount (line 125) of token from from into the delegatecalling engine
- `PerpSwapLib.sol:131` — `function tryTransfer(address token, address to, uint256 amount) external returns (bool)` — **engine (linked library; callers are PerpEngine._tryPush and PerpEngine._safeTransfer)** — sends amount (line 133) of token from the delegatecalling engine to to
- `PerpSwapLib.sol:162` — `function swapLeg( IPoolManager poolManager, PoolKey memory key, Req memory r, bool quoteIsCurrency0, bytes mem...` — **engine (linked library; the only caller is PerpEngine._swapBody)** — settles the pay leg through _settle (line 199) and receives the other leg through take (line 200)
- `PerpSwapLib.sol:211` — `function _settle(IPoolManager poolManager, Currency c, uint256 amount) private` — **internal (callers: swapLeg)** — sends native to the pool manager via settle (line 214); ERC20 transfer of the currency to the pool manager via transfer (line 222)
- `PerpSwapLib.sol:249` — `function migrateInventory(address registry, address oldToken, uint256 fromGen) external returns (uint256 migra...` — **engine (linked library; the only caller is PerpEngine.syncGeneration)** — burns the engine's dead-generation balance through the registry and receives the live token 1:1

### IPerpEngineVault (declared in PerpVault.sol)

- `PerpVault.sol:9` — `function fundFromVault(uint256 amount) external payable` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:10` — `function quote() external view returns (address)` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:11` — `function withdrawPlvTo(uint256 amount, address to) external` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:12` — `function fundTokenFromVault(uint256 amount) external` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:13` — `function withdrawPlvTokenTo(uint256 amount, address to) external` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:14` — `function totalEth() external view returns (uint256)` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:15` — `function freeEth() external view returns (uint256)` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:16` — `function totalTokenAssets() external view returns (uint256)` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:17` — `function freeToken() external view returns (uint256)` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:19` — `function tokYieldCumulative() external view returns (uint256)` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE
- `PerpVault.sol:20` — `function withdrawTokYieldTo(uint256 amount, address to) external` — **anyone (declaration only; the vault calls it on the immutable `engine`)** — NONE

### IVaultRegistry (declared in PerpVault.sol)

- `PerpVault.sol:24` — `function currentToken() external view returns (address)` — **anyone (declaration only; the vault calls it on the immutable `registry`)** — NONE

### PerpVault

- `PerpVault.sol:143` — `constructor(address _engine, address _registry)` — **deployer** — NONE
- `PerpVault.sol:167` — `function hasStakers() external view returns (bool)` — **anyone** — NONE
- `PerpVault.sol:179` — `function hasQuoteStake() external view returns (bool)` — **anyone (view)** — NONE
- `PerpVault.sol:185` — `function assetsEth() public view returns (uint256)` — **anyone** — NONE
- `PerpVault.sol:190` — `function assetsTok() public view returns (uint256)` — **anyone** — NONE
- `PerpVault.sol:210` — `function deposit(uint256 amount) public payable nonReentrant returns (uint256 shares)` — **anyone** — receives native asserted against value (line 218); pulls the ERC20 quote through _pull (line 221); forwards it to the engine at fundFromVault (line 229)
- `PerpVault.sol:235` — `function depositEth() external payable returns (uint256)` — **anyone** — receives native and forwards the whole msg value (line 236)
- `PerpVault.sol:239` — `function _engineQuote() private view returns (address)` — **private (callers: deposit)** — NONE
- `PerpVault.sol:249` — `function _pull(address token, address from, uint256 amount) private` — **private (callers: deposit, depositToken)** — ERC20 pull of the depositor's balance into this vault by transferFrom (line 251)
- `PerpVault.sol:256` — `function _approve(address token, address spender, uint256 amount) private` — **private (callers: deposit, depositToken)** — grants the engine an ERC20 approve allowance over this vault's balance (line 257)
- `PerpVault.sol:263` — `function withdrawEth(uint256 shares) external nonReentrant returns (uint256 paid, uint256 queued)` — **anyone (redeems only the caller's own shares)** — pays the caller out of the engine at withdrawPlvTo (line 282)
- `PerpVault.sol:303` — `function _haircut(uint256 owed, uint256 backing, uint256 claims) private pure returns (uint256)` — **private (callers: claimPendingEth, claimPendingToken)** — NONE
- `PerpVault.sol:313` — `function claimPendingEth() external nonReentrant returns (uint256 paid)` — **anyone (pays only the caller's own queued exit)** — pays paid (line 333) of the quote to the caller by pulling it out of the engine's free PLV
- `PerpVault.sol:350` — `function _syncTokYield() internal` — **internal (callers: depositToken, claimTokYield, withdrawToken)** — NONE
- `PerpVault.sol:360` — `function _settleTok(address user) internal` — **internal (callers: depositToken, claimTokYield, withdrawToken)** — NONE
- `PerpVault.sol:368` — `function _resetTokDebt(address user) internal` — **internal (callers: depositToken, claimTokYield, withdrawToken)** — NONE
- `PerpVault.sol:376` — `function depositToken(uint256 amount) external nonReentrant returns (uint256 shares)` — **anyone** — pulls the generation token from the depositor at _pull (line 386) and hands it to the engine at fundTokenFromVault (line 388)
- `PerpVault.sol:394` — `function claimTokYield() external nonReentrant returns (uint256 paid)` — **anyone (claims only the caller's own accrued reward)** — pays the caller out of the engine's segregated pot at withdrawTokYieldTo (line 399)
- `PerpVault.sol:405` — `function withdrawToken(uint256 shares) external nonReentrant returns (uint256 paid, uint256 queued)` — **anyone (redeems only the caller's own shares)** — pays the caller token out of the engine at withdrawPlvTokenTo (line 423)
- `PerpVault.sol:428` — `function claimPendingToken() external nonReentrant returns (uint256 paid)` — **anyone (claims only the caller's own queued exit)** — pays the caller token out of the engine at withdrawPlvTokenTo (line 440)
- `PerpVault.sol:448` — `function ethPosition(address user) external view returns (uint256 redeemable, uint256 instant, uint256 pending)` — **anyone** — NONE
- `PerpVault.sol:456` — `function tokenPosition(address user) external view returns (uint256 redeemable, uint256 instant, uint256 pendi...` — **anyone** — NONE
- `PerpVault.sol:465` — `function pendingTokYield(address user) external view returns (uint256)` — **anyone** — NONE
