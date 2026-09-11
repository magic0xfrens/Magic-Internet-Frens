# perp cluster — function graph notes

Generated from the decontaminated tree at `/tmp/blind-final/contracts/solidity`; line numbers are identical to the repo by construction.

| file | lines | nodes |
|---|---:|---:|
| `cauldron/PerpEngine.sol` | 1814 | 99 (PerpEngine 87 + 4 interfaces declared inside: IPerpRegistry 8, IMarkSource 1, IPerpVaultStake 1, IPerpHook 2) |
| `cauldron/PerpVault.sol` | 447 | 34 (PerpVault 22 + IPerpEngineVault 11 + IVaultRegistry 1) |
| `cauldron/PerpSwapLib.sol` | 142 | 3 |
| `cauldron/PerpMarkSource.sol` | 188 | 6 |
| `cauldron/PerpStakerOracle.sol` | 32 | 4 (PerpStakerOracle 2 + IPerpShares 2) |

Total 146 nodes. Companion machine-checked data: `audit/graph/perp.json`.

Extraction only — no severity judgement anywhere below. Where a comment claims something the code does not do, both are recorded side by side in section H.

---

## A. Value inventory

Denomination key: **Q** = the engine's `quote` (PerpEngine.sol:183); `address(0)` means native ether, otherwise the ERC20 at that address. **T** = the generation token (`registry.currentToken()`, read at PerpEngine.sol:484). **S** = share units. **idx** = a 1e18-scaled index, not an amount.

### PerpEngine

**`plv`** (PerpEngine.sol:304) — free lendable capital, **Q**.
- `-` PerpEngine.sol:800 long open moves `borrow` out to `longOiEth`
- `+` PerpEngine.sol:1147 long settle repays at most the principal
- `+` PerpEngine.sol:1187 funding paid in by the crowded side
- `-` PerpEngine.sol:1194 funding paid out to the underweight side (after insurance, saturating)
- `+` PerpEngine.sol:1361 long-attributed fee yield
- `+` PerpEngine.sol:1421 insurance replenishment after long bad debt
- `-` PerpEngine.sol:1432 short bad-debt absorption (saturating at 0)
- `+` PerpEngine.sol:1552 owner donation (`fundPlv`, no shares minted)
- `+` PerpEngine.sol:1606 ERC20 perp-fee credit from the hook
- `+` PerpEngine.sol:1619 native perp-fee credit, buy side
- `+` PerpEngine.sol:1635 vault deposit
- `-` PerpEngine.sol:1643 vault withdrawal
- read-only bounds: PerpEngine.sol:788, PerpEngine.sol:1098, PerpEngine.sol:1193, PerpEngine.sol:1642

**`plvToken`** (PerpEngine.sol:305) — free short inventory, **T**.
- `-` PerpEngine.sol:836 short open lends inventory out
- `+` PerpEngine.sol:1160 short settle returns the borrowed size IN FULL
- `+` PerpEngine.sol:1560 owner donation
- `+` PerpEngine.sol:1654 vault deposit
- `-` PerpEngine.sol:1660 vault withdrawal
- `=` PerpEngine.sol:1051 **replaced wholesale** by the engine's real balance of the new token during a sync

**`insuranceEth`** (PerpEngine.sol:223) — bad-debt buffer, **Q**.
- `-` PerpEngine.sol:1191 funding credit drawn from the buffer first
- `+` PerpEngine.sol:1366 insurance carve of every routed fee
- `-` PerpEngine.sol:1421 cover paid into `plv` after long bad debt
- `-` PerpEngine.sol:1430 cover consumed by short bad debt
- `+` PerpEngine.sol:1566 permissionless top-up
- `-` PerpEngine.sol:1789 owner skim of the surplus

**`tokYieldEth`** (PerpEngine.sol:311) — segregated short-side reward pot, **Q** on the way out, credited with native value on one path (see F).
- `+` PerpEngine.sol:1363 short-attributed fee yield
- `+` PerpEngine.sol:1621 native perp-fee credit, sell side
- `-` PerpEngine.sol:1649 attributed claim paid through the vault

**`tokYieldCumulative`** (PerpEngine.sol:314) — monotonic marker, same units, never decremented.
- `+` PerpEngine.sol:1364, `+` PerpEngine.sol:1622

**`longOiEth`** (PerpEngine.sol:354) — capital lent to open longs, **Q**.
- `+` PerpEngine.sol:800, `-` PerpEngine.sol:1143, `= 0` PerpEngine.sol:1053 (sync)

**`shortOiToken`** (PerpEngine.sol:355) — inventory lent to open shorts, **T**.
- `+` PerpEngine.sol:836, `-` PerpEngine.sol:1155, `= 0` PerpEngine.sol:1052 (sync)

**`payoutOwed[addr]`** (PerpEngine.sol:341) — undeliverable settlement credit, **Q**.
- `+` PerpEngine.sol:1405 (inside `unchecked`), `= 0` PerpEngine.sol:1413

**`badgesOwed[addr]`** (PerpEngine.sol:336) — a COUNT of NFTs, not value.
- `+` PerpEngine.sol:1515 (inside `unchecked`), `-` PerpEngine.sol:1531

**`positions[id]`** (PerpEngine.sol:330) — `collateral` and `principal` are **Q**, `size` is **T**, `entryFunding` is **idx**.
- created PerpEngine.sol:1326, deleted PerpEngine.sol:1136 (before any swap)

**`fundingIndex`** (PerpEngine.sol:317) — signed **idx**, `+=` PerpEngine.sol:734 only.

**`liqEthThisBlock`** (PerpEngine.sol:287) — per-timestamp liquidated notional, **Q**. `= 0` at PerpEngine.sol:865 / PerpEngine.sol:970 when `liqBlock` (PerpEngine.sol:865) differs; `+=` PerpEngine.sol:868 / PerpEngine.sol:973.

### PerpVault

**`ethShares`** (PerpVault.sol:94) / **`ethShareOf`** (PerpVault.sol:95) — **S**. `+` PerpVault.sol:204 / PerpVault.sol:205; `-` PerpVault.sol:254 / PerpVault.sol:253.

**`pendingEth`** (PerpVault.sol:96) / **`pendingEthOf`** (PerpVault.sol:97) — queued nominal claims, **Q**. `+` PerpVault.sol:256 / PerpVault.sol:257; written down `-` PerpVault.sol:295 (both); `-` PerpVault.sol:301 / PerpVault.sol:300 on payment.

**`tokShares`** (PerpVault.sol:100) / **`tokShareOf`** (PerpVault.sol:101) — **S**. `+` PerpVault.sol:351 / PerpVault.sol:352; `-` PerpVault.sol:386 / PerpVault.sol:385.

**`pendingTok`** (PerpVault.sol:102) / **`pendingTokOf`** (PerpVault.sol:103) — queued nominal claims, **T**. `+` PerpVault.sol:389 / PerpVault.sol:390; written down PerpVault.sol:402; paid PerpVault.sol:408 / PerpVault.sol:407.

**`accEthPerTokShare`** (PerpVault.sol:110) — **idx**, `+=` PerpVault.sol:325 only.
**`lastTokYieldCum`** (PerpVault.sol:111) — watermark, `=` PerpVault.sol:323 only, ALWAYS advanced even at zero shares (PerpVault.sol:324).
**`tokRewardDebt`** (PerpVault.sol:112) — **idx** baseline, `=` PerpVault.sol:338 only.
**`tokRewardOwed`** (PerpVault.sol:113) — banked reward, **Q**. `+` PerpVault.sol:333, `= 0` PerpVault.sol:367.

`PerpMarkSource`, `PerpStakerOracle` and `PerpSwapLib` hold no value and no balances of their own (`PerpSwapLib` moves the ENGINE's value under delegatecall — see D).

---

## B. Balance vs counter

The engine never compares any counter to its own balance. There is exactly one reconciliation in the cluster:

- **`plvToken` is re-derived from a real balance** at PerpEngine.sol:1050-1051, using `IERC20(newTok).balanceOf(address(this))`. Every other counter is carried forward from arithmetic alone.

Where counter and balance can diverge:

1. **Bare `receive()`** (PerpEngine.sol:1813) accepts native value that no counter records. Pool settlement needs it; a direct send is untracked.
2. **`_creditPerp`** (PerpEngine.sol:1617) credits `msg.value` — native wei — into `plv` (PerpEngine.sol:1619) or `tokYieldEth` (PerpEngine.sol:1621) with no `_quoteIsNative()` test. Those counters are paid out through `_pushQuote` (PerpEngine.sol:213) in whatever `quote` names.
3. **Unchecked ERC20 pulls.** `fundPlvToken` (PerpEngine.sol:1559) and `fundTokenFromVault` (PerpEngine.sol:1653) call `transferFrom` without inspecting the return value, then credit `plvToken` (PerpEngine.sol:1560 / PerpEngine.sol:1654). Contrast `_pullQuote` (PerpEngine.sol:206), `_safeTransfer` (PerpEngine.sol:1538) and `PerpVault._pull` (PerpVault.sol:230), which all decode it.
4. **Short settlement spends before it books.** `_buyExactOut` (PerpEngine.sol:1159) spends real balance for the buy-back; `_absorbPlvLoss` (PerpEngine.sol:1165) then reduces the counters to match. Between those two lines the counters overstate the balance.
5. **Failed pushes become debt without releasing a counter.** `_payOut` (PerpEngine.sol:1405) converts an undeliverable payment into `payoutOwed`; the value stays in the contract backing a new claim.
6. **Quote adoption tests one counter only.** The refusal at PerpEngine.sol:1098 checks `plv != 0`. `plvToken`, `tokYieldEth`, `insuranceEth` and the vault's `pendingEth` (PerpVault.sol:96) are not tested at that point.
7. **Vault claims vs vault backing.** `assetsEth()` (PerpVault.sol:162) subtracts `pendingEth` from `engine.totalEth()`, so live shares and queued claims partition the same pot. But the haircut at PerpVault.sol:294 compares the WHOLE `engine.totalEth()` against `pendingEth` alone — live-share backing is in the numerator and not in the denominator. The token side does the same at PerpVault.sol:401.
8. **`totalEth()` counts lent capital.** PerpEngine.sol:466 returns `plv + longOiEth`, so the vault prices shares against capital that is not in the contract; only `freeEth()` (PerpEngine.sol:468) is instantly payable, which is why `withdrawEth` splits at PerpVault.sol:247.

Counters that must cover one another (the solvency table) are in the cluster extras below.

---

## C. Authority map

| gate | held by | guarded surface | rotatable? |
|---|---|---|---|
| `onlyOwner` (OZ `Ownable`, constructed at PerpEngine.sol:427) | engine owner | `setFees` PerpEngine.sol:1665, `setRisk` PerpEngine.sol:1669, `setTiers` PerpEngine.sol:1706, `setRouting` PerpEngine.sol:1720, `setGuards` PerpEngine.sol:1730, `setVault` PerpEngine.sol:1751, `setVaultSplit` PerpEngine.sol:1757, `setVaultLimits` PerpEngine.sol:1763, `setMinCollateral` PerpEngine.sol:1768, `skimInsurance` PerpEngine.sol:1784, `fundPlv` PerpEngine.sol:1550, `fundPlvToken` PerpEngine.sol:1558 | yes — `transferOwnership`/`renounceOwnership` are in the compiled ABI; renouncing dead-ends every row above, including the only path that can re-point `markSource` (PerpEngine.sol:1727) |
| `onlyVault` (PerpEngine.sol:459) | whatever address `vault` holds | `fundFromVault` PerpEngine.sol:1633, `withdrawPlvTo` PerpEngine.sol:1641, `withdrawTokYieldTo` PerpEngine.sol:1647, `fundTokenFromVault` PerpEngine.sol:1652, `withdrawPlvTokenTo` PerpEngine.sol:1658 | yes, by the owner at PerpEngine.sol:1753, behind the incumbent's own `hasStakers()` answer (PerpEngine.sol:1752). While `vault` is zero the whole surface is unreachable |
| `msg.sender != hookAddr` (PerpEngine.sol:882, PerpEngine.sol:1601, PerpEngine.sol:1611) | the hook | `sweepLiquidations`, `creditPerpFee`, `creditPerpFeeToken`, `creditPerpFeeAsset` | **no** — `hookAddr` is immutable (PerpEngine.sol:95, set at PerpEngine.sol:428). A replaced hook dead-ends keeperless liquidation and perp-fee credit permanently |
| `msg.sender != address(poolManager)` (PerpEngine.sol:1248) | the v4 pool manager | `unlockCallback` | no — immutable |
| `msg.sender != address(this)` (PerpEngine.sol:891) | the engine itself | `selfSweep` | n/a |
| `p.trader != msg.sender` (PerpEngine.sol:851) | the position owner | `close` | per-position |
| `onlyOwner` (PerpMarkSource.sol:100, PerpMarkSource.sol:111, PerpMarkSource.sol:132) | mark-source owner | `setPrimary`, `addPool`, `removePool` | yes, and renounceable — after renouncing, the pool set is frozen and the engine can still be detached at PerpEngine.sol:1727 |
| none | — | **every** `PerpVault` entrypoint | `PerpVault` has no owner, no admin and no upgrade path; `engine` and `registry` are immutable (PerpVault.sol:66-67), so a vault is bound to one engine for life |
| none | — | `PerpStakerOracle.isInstant` PerpStakerOracle.sol:29 | `perpVault` is immutable (PerpStakerOracle.sol:22); replacement happens at the consumer |

Permissionless entrypoints that move value or state: `poke` PerpEngine.sol:558, `openLong` PerpEngine.sol:777, `openShort` PerpEngine.sol:814, `liquidate` PerpEngine.sol:856, `forceCloseDead` PerpEngine.sol:983, `forceCloseAllDead` PerpEngine.sol:998, `syncGeneration` PerpEngine.sol:1024, `claimPayout` PerpEngine.sol:1410, `claimLiquidatorBadges` PerpEngine.sol:1523, `fundInsurance` PerpEngine.sol:1564, `receive` PerpEngine.sol:1813, and the whole of `PerpVault`.

Trust the engine extends without a gate: `registry` is consulted unconditionally and un-caught at PerpEngine.sol:1307 (inside the death test that every open and every force-close passes through), while the hook's own `isDead` at PerpEngine.sol:1308 IS wrapped in try/catch.

---

## D. External calls, value, and CEI ordering

| site | callee | value moved | trust | ordering |
|---|---|---|---|---|
| PerpEngine.sol:203 | `quote.call(transferFrom)` | pulls **Q** in | untrusted | first statement of `_pullQuote`; in `openLong`/`openShort` it runs BEFORE every guard (PerpEngine.sol:781, PerpEngine.sol:818) |
| PerpEngine.sol:216 | `to.call{value}` | sends **Q** out, all gas | untrusted | after effects (PerpEngine.sol:1413, PerpEngine.sol:1643, PerpEngine.sol:1649, PerpEngine.sol:1789); reverts on failure |
| PerpEngine.sol:219 → PerpEngine.sol:1537 | `token.call(transfer)` | sends **Q**/**T** out | untrusted | same; reverts on a false return (PerpEngine.sol:1538) |
| PerpEngine.sol:438, PerpEngine.sol:489, PerpEngine.sol:551 | `poolManager.getSlot0` | none (view) | trusted | — |
| PerpEngine.sol:542 | `markSource` raw `staticcall` | none (view) | untrusted, owner-set | result accepted only if the call succeeded and returned exactly 32 bytes (PerpEngine.sol:546) |
| PerpEngine.sol:690 | `poolManager.getLiquidity` | none (view) | trusted | — |
| PerpEngine.sol:1044 | `PerpSwapLib.migrateInventory` (delegatecall) → PerpSwapLib.sol:134 `registry.call` | burns the engine's dead **T**, receives live **T** | trusted registry, low-level and best-effort | before the `plvToken` re-derivation at PerpEngine.sol:1051 |
| PerpEngine.sol:1050 | `IERC20(newTok).balanceOf` | none (view) | untrusted (new generation token) | — |
| PerpEngine.sol:1234 | `poolManager.unlock` | re-enters this contract at PerpEngine.sol:1247 | trusted | — |
| PerpEngine.sol:1268 | `PerpSwapLib.swapLeg` (delegatecall) | see the four rows below | trusted lib, untrusted currencies | called from `_settle` AFTER the position is deleted (PerpEngine.sol:1136) |
| PerpSwapLib.sol:76 | `poolManager.swap` | none directly; creates deltas | trusted | price limit is the extreme tick (PerpSwapLib.sol:66) — no slippage bound inside the library |
| PerpSwapLib.sol:104 | `poolManager.settle{value}` | sends native out of the ENGINE | trusted | pay leg |
| PerpSwapLib.sol:106 / :111 / :115 | `sync`, `c.call(transfer)`, `settle` | sends ERC20 out of the ENGINE | untrusted token | return decoded at PerpSwapLib.sol:114 |
| PerpSwapLib.sol:90 / :95 | `poolManager.take` | receives into the ENGINE | trusted | after the pay leg |
| PerpEngine.sol:1283 | `registry.lastSummonAt` | none | trusted, **not** caught | gates every open |
| PerpEngine.sol:1307 | `registry.generationQuote` + `currentGeneration` | none | trusted, **not** caught | gates every open and every force-close |
| PerpEngine.sol:1308 | `hook.isDead` | none | trusted, try/catch → false | — |
| PerpEngine.sol:1312 | `mifrens.balanceOf` | none | trusted, immutable | inside fee computation |
| PerpEngine.sol:1392 | `to.call{value, gas:30_000}` | sends native **Q** | untrusted | credit-on-failure (PerpEngine.sol:1405) |
| PerpEngine.sol:1400 | `quote.call(transfer)` | sends ERC20 **Q**, **all** remaining gas | untrusted | credit-on-failure |
| PerpEngine.sol:1493 / PerpEngine.sol:1526 | `hook.collection` | none | trusted, typed, un-caught | — |
| PerpEngine.sol:1497 / PerpEngine.sol:1508 | `col.call{gas: fwd}` | none | untrusted, hook-chosen | failure falls back to `badgesOwed` |
| PerpEngine.sol:1534 | `col.mintLiquidator` typed | none | untrusted, hook-chosen | AFTER `badgesOwed` is decremented (PerpEngine.sol:1531) |
| PerpEngine.sol:1559 / PerpEngine.sol:1653 | `token.transferFrom` | pulls **T** in | untrusted, **return not checked** | before the counter increment |
| PerpEngine.sol:1752 | `vault.hasStakers` | none | typed, un-caught | the incumbent answers the question that permits its own replacement |
| PerpVault.sol:217 | `engine.staticcall("quote()")` | none | trusted, deliberately raw so a missing function degrades to native (PerpVault.sol:220) | — |
| PerpVault.sol:227 / PerpVault.sol:234 | `token.call(transferFrom/approve)` | pulls **Q**/**T** in, grants allowance | untrusted | `_pull` decodes the return (PerpVault.sol:230); `_approve` checks only the success flag (PerpVault.sol:235) |
| PerpVault.sol:206 | `engine.fundFromVault{value}` | sends **Q** to the engine | trusted | AFTER shares are minted (PerpVault.sol:204) |
| PerpVault.sol:259 / PerpVault.sol:302 | `engine.withdrawPlvTo` | pays the caller | trusted | AFTER shares burned and queue earmarked (PerpVault.sol:253-257, PerpVault.sol:300) |
| PerpVault.sol:357 | `engine.fundTokenFromVault` | sends **T** to the engine | trusted | after share mint and baseline rebase |
| PerpVault.sol:368 | `engine.withdrawTokYieldTo` | pays the caller | trusted | AFTER `tokRewardOwed` zeroed (PerpVault.sol:367) |
| PerpVault.sol:392 / PerpVault.sol:409 | `engine.withdrawPlvTokenTo` | pays the caller **T** | trusted | after effects |
| PerpStakerOracle.sol:30 | `perpVault.ethShareOf` / `tokShareOf` | none | typed, un-caught | — |

Reentrancy shape worth recording plainly: `sweepLiquidations` (PerpEngine.sol:881) carries neither `nonReentrant` nor `notNested`, and `_settle` performs its pool swap at PerpEngine.sol:1144 / PerpEngine.sol:1159. A settlement swap therefore reaches the hook's afterSwap, which calls back into `sweepLiquidations`; nesting beyond that is stopped by `_liqReentry` (PerpEngine.sol:907), and while a sweep is live `notNested` (PerpEngine.sol:455) locks every user entrypoint.

---

## E. Loops

| site | bound | who can grow the bound |
|---|---|---|
| PerpEngine.sol:661 | binary search over the ring — at most log2 of `OBS_CARDINALITY` = 5 iterations | nobody; PerpEngine.sol:263 is a constant |
| PerpEngine.sol:700 | `tierDepthWei.length` | the owner, via `setTiers` (PerpEngine.sol:1707); the arrays are replaced wholesale with no length ceiling. Runs inside `maxLeverage`, which every open calls (PerpEngine.sol:1285) |
| PerpEngine.sol:926 | `SWEEP_SCAN` = 12 checks, `MAX_LIQ_PER_SWAP` = 8 kills, plus a hard break below `SWEEP_KILL_RESERVE` gas (PerpEngine.sol:942) | nobody — the break degrades instead of reverting |
| PerpEngine.sol:1008 | `FORCE_CLOSE_MAX` = 96 (PerpEngine.sol:163) | anyone, by opening positions — but only up to `MAX_OPEN_POSITIONS` = 64 (PerpEngine.sol:1323), which is a constant and strictly below the loop bound |
| PerpEngine.sol:1534 | caller-supplied `n`, clamped down to `badgesOwed` (PerpEngine.sol:1525) | liquidations grow the owed count (PerpEngine.sol:1515); the caller chooses how much to process |
| PerpMarkSource.sol:122 | `pools.length` < `MAX_POOLS` = 4 | the owner, up to the cap |
| PerpMarkSource.sol:135 | same | same |
| PerpMarkSource.sol:173 | same — and this one runs inside every swap, through `_writeObs` → `_currentTick` (PerpEngine.sol:613) | the owner, up to the cap |

`PerpVault` contains no loops at all — every path is O(1) in the number of stakers.

---

## F. Denomination and units

- **No `decimals()` call exists anywhere in the cluster.** Every token/quote conversion goes through the pool's Q96 sqrt price: `_quoteAt` (PerpEngine.sol:710) and `_ethToToken` (PerpEngine.sol:1344). The sqrt price already encodes the decimal ratio, so a 6-decimal quote needs no correction and none is present.
- `quote` (PerpEngine.sol:183) is the single denomination switch, written only at PerpEngine.sol:1099. `_quoteIsNative` (PerpEngine.sol:186) branches every transport.
- The `*Eth` identifiers are vestigial labels for "quote units" — the contract says so at PerpEngine.sol:361-381, and the vault repeats it at PerpVault.sol:69-90.
- Mixed-unit sums that are internally consistent: `totalEth` (PerpEngine.sol:466) adds two **Q** counters; `totalTokenAssets` (PerpEngine.sol:470) adds two **T** counters; `skimInsurance` (PerpEngine.sol:1786) converts the **T** side to **Q** with `_quoteEth` before adding.
- Native/ERC20 crossing points: `creditPerpFee` (PerpEngine.sol:1574) and `creditPerpFeeToken` (PerpEngine.sol:1579) are `payable` and their shared body credits `msg.value` (PerpEngine.sol:1617) without a native check; `creditPerpFeeAsset` (PerpEngine.sol:1604) is the ERC20 twin and refuses any asset other than the live `quote`, and credits `plv` for BOTH trade directions (its own note at PerpEngine.sol:1588-1598 records the missing side split).
- Fixed-point scales: `BPS` = 10_000 (PerpEngine.sol:101); `Q96` (PerpEngine.sol:102); the funding index is 1e18-scaled (PerpEngine.sol:732, consumed at PerpEngine.sol:749); the badge's entry/liq prices are 1e18-scaled quote-per-token (PerpEngine.sol:1469-1470); the vault's reward accumulator uses `ACC` = 1e18 (PerpVault.sol:109) and its virtual share offset is `OFFSET` = 1e6 (PerpVault.sol:64), so one asset unit mints ~1e6 shares.
- Width truncations: collateral is stored as `uint128` (PerpEngine.sol:1326); badge stats clamp to `uint96`/`uint128` rather than reverting (PerpEngine.sol:1475-1481); the observation ring packs `uint32` timestamps and an `int56` cumulative (PerpEngine.sol:269); the mark source's answer is cast `int24(v)` with no range check (PerpEngine.sol:549).
- Tick comparability is enforced, not assumed: `addPool` rejects any pool whose two currencies differ from the primary's in either slot (PerpMarkSource.sol:114-117), which is what keeps a cross-quote normalisation oracle off the liquidation path.

---

## G. `unchecked` blocks and rounding direction

| site | what is unchecked | effect |
|---|---|---|
| PerpEngine.sol:599 | the whole `_writeObs` body: `nowTs - lastObsTs` (PerpEngine.sol:600), the `int56` integration (PerpEngine.sol:603), `nowTs - lastRingTs` (PerpEngine.sol:607), the ring index mask (PerpEngine.sol:609) | uint32 epoch wrap yields the modulo-2^32 delta instead of a panic |
| PerpEngine.sol:638 | `nowTs - twapWindow` | a target before the epoch wraps rather than panicking |
| PerpEngine.sol:656 | `nowTs - oldest.ts` | same |
| PerpEngine.sol:671 | the tail extrapolation and span (PerpEngine.sol:672-673) | same |
| PerpEngine.sol:702 | `++i` in the tier loop | gas only |
| PerpEngine.sol:1011 | `iters++` in the drain loop | gas only |
| PerpEngine.sol:1405 | `payoutOwed[to] += amount` | an overflow would wrap the credit |
| PerpEngine.sol:1496, PerpEngine.sol:1507 | `gasleft() - 120_000` | guarded above by the 300k/200k tests on the preceding lines |
| PerpEngine.sol:1515 | `badgesOwed[to] += 1` | gas only in practice |
| PerpEngine.sol:1534 | `++i` in the mint loop | gas only |

Rounding — every division in the cluster is integer and there is no rounding-up helper anywhere:

- Fee, penalty, keeper and cap arithmetic `(x * bps) / BPS` floors: PerpEngine.sol:1311, PerpEngine.sol:1199, PerpEngine.sol:1201, PerpEngine.sol:1217, PerpEngine.sol:793, PerpEngine.sol:798, PerpEngine.sol:866, PerpEngine.sol:1126, PerpEngine.sol:1317, PerpEngine.sol:1786. Caps therefore bind slightly EARLIER than the nominal ratio and fees are slightly smaller.
- `_quoteAt` (PerpEngine.sol:710) and `_ethToToken` (PerpEngine.sol:1344) use `FullMath.mulDiv`, which floors. A floored mark value makes a long marginally more likely to be underwater at PerpEngine.sol:1126 and a short marginally less likely at PerpEngine.sol:1131.
- Signed divisions truncate toward ZERO, not toward minus infinity: the funding step (PerpEngine.sol:732), the per-position funding delta (PerpEngine.sol:749), the TWAP tick (PerpEngine.sol:676) and the weighted tick (PerpMarkSource.sol:186). For a negative tick this biases the mark upward by up to one tick.
- Vault share math floors in the vault's favour on BOTH sides: shares minted (PerpVault.sol:202, PerpVault.sol:349) and assets owed (PerpVault.sol:245, PerpVault.sol:380) both use `mulDiv`; the `+ OFFSET` / `+ 1` terms (PerpVault.sol:64) are the inflation guard. `_haircut` (PerpVault.sol:286) floors toward the vault by design. The reward accumulator (PerpVault.sol:325) and its per-user settle (PerpVault.sol:332, PerpVault.sol:338) also floor, so dust accrues to the pot.

---

## H. Comment-vs-code observations

1. Comment at PerpEngine.sol:257-259 says a full ring takes `CARDINALITY x OBS_INTERVAL`, quotes that as ~68 minutes, and assumes 30-second minimum spacing; code declares `OBS_CARDINALITY` = 32 at PerpEngine.sol:263 and `OBS_INTERVAL` = 15 seconds at PerpEngine.sol:267 — 8 minutes.
2. Comment at PerpEngine.sol:993 says `forceCloseAllDead` is "bounded to 64 per call"; code bounds the loop by `FORCE_CLOSE_MAX` at PerpEngine.sol:1008, declared as 96 at PerpEngine.sol:163.
3. Comment at PerpEngine.sol:1171 says the settlement tail was "extracted to {PerpOps}"; the code computes it inline from PerpEngine.sol:1183 and no such library exists in the tree.
4. Comment at PerpEngine.sol:1387 says the payout forwards "bounded gas so a recipient cannot consume the settlement's budget"; only the native branch bounds it (PerpEngine.sol:1392), the ERC20 branch at PerpEngine.sol:1400 forwards everything.
5. `@notice` at PerpEngine.sol:1737-1738 says a wired vault may only be re-pointed "while the PLV is EMPTY (plv/plvToken/tokYieldEth all 0)"; the code at PerpEngine.sol:1752 instead asks the outgoing vault `hasStakers()`. The later note at PerpEngine.sol:1741-1750 explains the replacement, but the `@notice` above it still states the old rule.
6. Comment at PerpEngine.sol:890 documents `selfSweep` as called by the engine on itself; the guard at PerpEngine.sol:891 tests `address(this)` but reverts with `OnlyHook`.
7. Comment at PerpEngine.sol:449 refers to "the hook-driven `liquidateInSwap`"; no such function exists in the cluster — the hook-driven entry is `sweepLiquidations` (PerpEngine.sol:881).
8. Comment at PerpEngine.sol:934 attributes the discarded sweep result to `CauldronHook.sol:912`; line 912 of that file is inside the gacha block, and the `sweepLiquidations` call site is CauldronHook.sol:949. The same comment cites `minCollateral` at ":131"; PerpEngine.sol:131 is `warmup` and `minCollateral` is declared at PerpEngine.sol:144.
9. Comment at PerpEngine.sol:1288-1289 says `quote` is "adopted only in {syncGeneration} (:1027), which refuses while `openCount != 0` (:987)"; the adoption is at PerpEngine.sol:1099 inside the function that starts at PerpEngine.sol:1024, and the `openCount` refusals are at PerpEngine.sol:1036 and PerpEngine.sol:1075.
10. Comment at PerpEngine.sol:123 points at "`markSource` at :462"; PerpEngine.sol:462 is blank and `markSource` is declared at PerpEngine.sol:499.
11. Header comment at PerpEngine.sol:86 says the open fee is "6.9%-of-collateral"; `_takeFee` (PerpEngine.sol:1311) computes it on the amount SENT and collateral is the remainder (PerpEngine.sol:1313), so the fee is 6.9% of gross, not of collateral.
12. Header comment at PerpMarkSource.sol:17-18 says the engine reads `slot0` of the one pool "built from `registry.generationQuote(gen)`"; `_key` (PerpEngine.sol:483) builds it from the engine's own CACHED `quote` slot, whose only writer is PerpEngine.sol:1099.
13. Comment at PerpVault.sol:143 describes `assetsEth` as "the engine's ETH PLV minus queued exits"; the code at PerpVault.sol:163 uses `engine.totalEth()`, which is `plv + longOiEth` (PerpEngine.sol:466), i.e. it includes capital lent out to open longs.
14. The section header at PerpVault.sol:446 announces "internal ERC20 helpers" and is the last line before the closing brace; the helpers it names are defined far earlier, at PerpVault.sol:226 and PerpVault.sol:233.

---

## Cluster extra 1 — solvency accounting

Every quantity that must cover another, with the lines that maintain it.

**(S1) `plv` must cover what longs may borrow.** Enforced per open at PerpEngine.sol:788 (`borrow > plv` reverts) and again as a share of the whole book at PerpEngine.sol:793 (`longOiEth + borrow <= totalEth() * maxUtilBps / BPS`, only while a vault is wired). Repaid at PerpEngine.sol:1147, capped at the principal so a shortfall never credits more than the loan.

**(S2) `plvToken` must cover what shorts may borrow.** Enforced at PerpEngine.sol:828 and PerpEngine.sol:831. Restored IN FULL at PerpEngine.sol:1160, because the buy-back at PerpEngine.sol:1159 is exact-output — this is the mechanism that makes token principal structurally protected, and the vault's header states it at PerpVault.sol:37-41.

**(S3) Per-side open interest must stay inside pool depth.** `longOiEth + borrow <= activeEthDepth() * maxOiBps / BPS` at PerpEngine.sol:798; the token-side mirror at PerpEngine.sol:834 converts depth into token units first. Single-position notional is separately capped at PerpEngine.sol:1317.

**(S4) A position's mark value must cover its debt plus the maintenance buffer.** Long: PerpEngine.sol:1126. Short: PerpEngine.sol:1131, where backing is `collateral + principal` (PerpEngine.sol:1129). Violation is exactly the liquidation trigger.

**(S5) `insuranceEth` covers bad debt before LP principal does.** Long shortfall: PerpEngine.sol:1420-1421 (insurance → `plv`). Short overspend: PerpEngine.sol:1429-1432 (insurance first, then `plv` saturating at zero). Funding credit: PerpEngine.sol:1190-1194 (insurance first, then `plv`, never overdrawing either).

**(S6) Funding paid in must cover funding paid out.** The payer is capped by its OWN residual at PerpEngine.sol:1186, so it can pay less than it owes; the receiver draws the difference from insurance and then `plv` at PerpEngine.sol:1190-1194. Per-position magnitude is bounded to `maxFundingBps` of collateral at PerpEngine.sol:750, and the global rate is bounded at PerpEngine.sol:1691.

**(S7) The liquidation penalty must fit inside the residual.** PerpEngine.sol:1200 clamps it, then PerpEngine.sol:1201-1202 carves the keeper cut out of the clamped figure, so neither can drive `residual` negative.

**(S8) `insuranceEth` must stay above the risk floor before any skim.** PerpEngine.sol:1786-1788: protection is the greater of the configured `insuranceFloor` and `maintenanceBps` of live two-sided open interest, valued at SPOT.

**(S9) Vault shares plus queued claims must not exceed the engine's book.** `assetsEth()`/`assetsTok()` subtract the queue (PerpVault.sol:164, PerpVault.sol:169), saturating at zero; when backing falls below the queue, `_haircut` (PerpVault.sol:285-286) writes every claimant down pro rata and persists it (PerpVault.sol:295, PerpVault.sol:402).

**(S10) Instant payment must not exceed free capital.** PerpVault.sol:247 and PerpVault.sol:382 cap payment at `engine.freeEth()`/`freeToken()`; the engine re-checks at PerpEngine.sol:1642 and PerpEngine.sol:1659 and reverts `PlvInsufficient` otherwise.

**(S11) The token-side reward pot must cover attributed claims.** PerpEngine.sol:1648 bounds every payment by `tokYieldEth`; the vault only ever asks for a figure it has already settled into `tokRewardOwed` (PerpVault.sol:333). Yield accrued at zero shares is never attributed (PerpVault.sol:324), so the pot is always at least the sum of attributed claims.

**(S12) The book must be drainable in one call.** `MAX_OPEN_POSITIONS` = 64 (PerpEngine.sol:1323) is a constant and is strictly below `FORCE_CLOSE_MAX` = 96 (PerpEngine.sol:1008); `_payOut` never reverts (PerpEngine.sol:1405), so no single position can block the drain. This is what makes `openCount == 0` reachable, which `syncGeneration` demands at PerpEngine.sol:1036.

---

## Cluster extra 2 — the liquidation path, end to end

**Entry, three ways.**
- `liquidate(id)` PerpEngine.sol:856 — any caller, `nonReentrant` + `notNested`, reverts `Healthy` or `LiqCapped` on refusal.
- `sweepLiquidations(liquidator)` PerpEngine.sol:881 — hook-only, from afterSwap on every trade on any interface, `inLocked = true`, no reentrancy modifier.
- `selfSweep(liquidator)` PerpEngine.sol:890 — engine-only, reached from `_sweepAfterOpen` (PerpEngine.sol:900) with a gas reserve and a swallowing catch.

**1. Oracle and funding.** `_pokeFunding` (PerpEngine.sol:859 / PerpEngine.sol:918) runs first. It calls `_writeObs` (PerpEngine.sol:719), which integrates the elapsed interval at `lastTick`, appends to the ring if `OBS_INTERVAL` has passed, and always refreshes `lastTick` from `_currentTick` (PerpEngine.sol:613). Then it accrues `fundingIndex` (PerpEngine.sol:734) from the mark-valued imbalance.

**2. Selection.** The sweep reads a rotating window of `_openIds` starting at `sweepCursor` (PerpEngine.sol:923), at most `SWEEP_SCAN` checks and `MAX_LIQ_PER_SWAP` kills, breaking below `SWEEP_KILL_RESERVE` gas (PerpEngine.sol:942). After a kill the cursor does NOT advance, because the swap-and-pop put a new id in the same slot (PerpEngine.sol:950).

**3. Health test.** `_quoteMark(p.size)` (PerpEngine.sol:861 / PerpEngine.sol:966) is computed ONCE and reused both for the test and as the throttle notional. `_underwaterVal` (PerpEngine.sol:1123) applies the long or short form.

**4. Throttle.** Reset when the timestamp changed (PerpEngine.sol:865 / PerpEngine.sol:970), cap = `activeEthDepth() * maxLiqBps / BPS` (PerpEngine.sol:866 / PerpEngine.sol:971), and the cap is skipped entirely when it computes to zero. The keeper path reverts `LiqCapped`; the sweep path silently returns (PerpEngine.sol:972).

**5. Settlement — `_settle(id, p, 0, MODE_LIQUIDATION, keeper)`.**
- effects first: delete (PerpEngine.sol:1136), remove from the set (PerpEngine.sol:1137), `openCount--` (PerpEngine.sol:1138);
- long: `longOiEth -= principal` (PerpEngine.sol:1143), sell the held token (PerpEngine.sol:1144), repay at most the principal into `plv` (PerpEngine.sol:1147), top up from insurance (PerpEngine.sol:1152), `residual = proceeds - repay` (PerpEngine.sol:1153) — which is 0 whenever the position was underwater;
- short: `shortOiToken -= size` (PerpEngine.sol:1155), exact-output buy-back (PerpEngine.sol:1159), inventory restored (PerpEngine.sol:1160), overspend absorbed (PerpEngine.sol:1165), `residual = backing - cost` (PerpEngine.sol:1166);
- `minOut` is NOT enforced, because `ownerSlippage` is false outside `MODE_NORMAL` (PerpEngine.sol:1140);
- funding transfer (PerpEngine.sol:1183-1196);
- penalty = `liqPenaltyBps` of collateral, clamped to residual (PerpEngine.sol:1199-1200); keeper cut = `keeperBps` of the penalty (PerpEngine.sol:1201); the rest is routed as a fee, side-attributed by `p.isLong` (PerpEngine.sol:1203);
- keeper paid through the non-reverting `_payOut` (PerpEngine.sol:1204), `Liquidated` emitted (PerpEngine.sol:1205);
- trophy: `_killStats` (PerpEngine.sol:1214) snapshots entry/liq prices, `_awardBadge` (PerpEngine.sol:1485) tries a stats mint, then a plain mint, then credits `badgesOwed`;
- trader paid the remaining residual (PerpEngine.sol:1220) and `Closed` emitted (PerpEngine.sol:1221).

**6. Swap execution.** Every leg goes through `_run` (PerpEngine.sol:1234): in-lock during a sweep, a fresh `unlock` otherwise. `_swapBody` (PerpEngine.sol:1255) derives leg orientation from `syncedToken` and delegates to `PerpSwapLib.swapLeg`, which settles the pay leg and takes the receive leg with NO internal slippage bound.

**7. Claims afterwards.** Anything `_payOut` could not deliver is claimable at `claimPayout` (PerpEngine.sol:1410); unminted trophies at `claimLiquidatorBadges` (PerpEngine.sol:1523).

**Death variant.** `forceCloseDead` (PerpEngine.sol:983) and `forceCloseAllDead` (PerpEngine.sol:998) run the same `_settle` with `MODE_DEATH`: no penalty, no badge, and the caller takes `keeperBps` of the residual (PerpEngine.sol:1217). Both require `_isDead()` (PerpEngine.sol:1306).

---

## Cluster extra 3 — mark and price sources, with fallback order

**A. The tick — `_currentTick` (PerpEngine.sol:534).** Every sample in the system starts here.
1. `markSource` if non-zero — hand-rolled `staticcall` (PerpEngine.sol:542), accepted only when the call succeeded AND `returndatasize() == 32` (PerpEngine.sol:546);
2. otherwise `poolManager.getSlot0(_key().toId())` (PerpEngine.sol:551).
A source that reverts, self-destructs, is unset or returns the wrong width degrades silently to (2).

**B. Inside the mark source — `PerpMarkSource.weightedTick` (PerpMarkSource.sol:158).**
1. not armed → tick `0` (PerpMarkSource.sol:159) — note this is a *valid-looking* answer to the engine, not a failure;
2. no sibling pools → the primary's tick (PerpMarkSource.sol:165);
3. siblings present but no in-range liquidity anywhere → the primary's tick (PerpMarkSource.sol:185);
4. otherwise `sum(tick_i * L_i) / sum(L_i)` (PerpMarkSource.sol:171-186), skipping any pool with zero in-range depth (PerpMarkSource.sol:176). The primary's tick is always in the sum, weighted by its own liquidity, even when that is zero.

**C. The liquidation mark — `markSqrtPriceX96` (PerpEngine.sol:681).**
1. `twapTick()` (PerpEngine.sol:634) if it returns ok;
2. otherwise SPOT via `_sqrtP()` (PerpEngine.sol:683).

**D. Inside the TWAP — `twapTick` (PerpEngine.sol:634).**
1. `now <= MIN_TWAP` → not ok (PerpEngine.sol:636);
2. ring empty → not ok (PerpEngine.sol:649);
3. oldest entry newer than the target → use the oldest, but only if it spans `MIN_TWAP`, else not ok (PerpEngine.sol:656);
4. otherwise binary-search the newest entry at or before the target (PerpEngine.sol:661-667);
5. zero span → not ok (PerpEngine.sol:675).
The un-recorded tail is always extrapolated at `lastTick` (PerpEngine.sol:672), which `_writeObs` refreshes unconditionally (PerpEngine.sol:613).

**E. Spot — `_sqrtP` (PerpEngine.sol:489).** A direct `slot0` read of the single pool `_key()` names. No fallback: an uninitialised pool returns 0, which `activeEthDepth` special-cases (PerpEngine.sol:689) and `_ethToToken` does not.

**Which decision uses which:**

| decision | source |
|---|---|
| liquidation trigger (PerpEngine.sol:1126, PerpEngine.sol:1131) | MARK (C) |
| per-timestamp liquidation throttle notional (PerpEngine.sol:866, PerpEngine.sol:971) | MARK (C) |
| funding imbalance sizing (PerpEngine.sol:727) | MARK (C) |
| badge liq price (PerpEngine.sol:1470) | MARK (C) |
| UI health (PerpEngine.sol:1808) | MARK (C) |
| short borrow sizing (PerpEngine.sol:827) | SPOT (E) |
| open-interest cap in token units (PerpEngine.sol:834) | SPOT (E) |
| depth for leverage tiers, notional and OI caps (PerpEngine.sol:686) | SPOT (E) |
| insurance risk floor (PerpEngine.sol:1786) | SPOT (E) |
| actual execution price of every leg | the pool itself, unbounded inside PerpSwapLib (PerpSwapLib.sol:66) |
| pool identity for all of the above | the CACHED `quote` (PerpEngine.sol:483), not `registry.generationQuote` |

There is no external price oracle on any path in this cluster; `PerpMarkSource.addPool` (PerpMarkSource.sol:114-117) exists precisely to keep one off the liquidation path.

---

## I. Function inventory

One line per skeleton node: `file:line` — signature — authority — value effect.


### IPerpRegistry (declared in PerpEngine.sol)

- `PerpEngine.sol:24` — `function currentToken() external view returns (address)` — **anyone (declaration only; the engine calls it on the immutable `registry`)** — NONE
- `PerpEngine.sol:28` — `function generationQuote(uint256 gen) external view returns (address)` — **anyone (declaration only; the engine calls it on the immutable `registry`)** — NONE
- `PerpEngine.sol:29` — `function currentGeneration() external view returns (uint256)` — **anyone (declaration only; the engine calls it on the immutable `registry`)** — NONE
- `PerpEngine.sol:30` — `function lastSummonAt() external view returns (uint256)` — **anyone (declaration only; the engine calls it on the immutable `registry`)** — NONE
- `PerpEngine.sol:31` — `function generationPoolId(uint256) external view returns (PoolId)` — **anyone (declaration only)** — NONE
- `PerpEngine.sol:32` — `function generationToken(uint256) external view returns (address)` — **anyone (declaration only)** — NONE
- `PerpEngine.sol:33` — `function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256)` — **anyone (declaration only)** — NONE
- `PerpEngine.sol:34` — `function claimByBurnUpTo(uint256 fromGen, uint256 maxAmount) external returns (uint256)` — **anyone (declaration only)** — NONE

### IMarkSource (declared in PerpEngine.sol)

- `PerpEngine.sol:42` — `function weightedTick() external view returns (int24)` — **anyone (declaration only; only its 4-byte selector is used)** — NONE

### IPerpVaultStake (declared in PerpEngine.sol)

- `PerpEngine.sol:47` — `function hasStakers() external view returns (bool)` — **anyone (declaration only; the engine calls it on `vault`)** — NONE

### IPerpHook (declared in PerpEngine.sol)

- `PerpEngine.sol:51` — `function isDead(PoolId id) external view returns (bool)` — **anyone (declaration only; the engine calls it on the immutable `hookAddr`)** — NONE
- `PerpEngine.sol:53` — `function collection() external view returns (address)` — **anyone (declaration only; the engine calls it on the immutable `hookAddr`)** — NONE

### PerpEngine

- `PerpEngine.sol:186` — `function _quoteIsNative() internal view returns (bool)` — **internal (callers: _pullQuote, _pushQuote, _payOut)** — NONE
- `PerpEngine.sol:194` — `function _pullQuote(address from, uint256 amount) internal` — **internal (callers: openLong, openShort, fundPlv, fundInsurance, creditPerpFeeAsset, fundFromVault)** — receives native asserted against value (line 196); ERC20 pull of the quote by transferFrom (line 204)
- `PerpEngine.sol:213` — `function _pushQuote(address to, uint256 amount) internal` — **internal (callers: _sendEth, claimPayout)** — sends native to to (line 216); ERC20 transfer of the quote to to via _safeTransfer (line 219)
- `PerpEngine.sol:424` — `constructor( IPoolManager _poolManager, address _hook, address _registry, address _mifrens, address _dividend, addres...` — **deployer** — NONE
- `PerpEngine.sol:454` — `modifier notNested()` — **internal (applied to: openLong, openShort, close, liquidate, forceCloseDead, forceCloseAllDead, syncGeneration, fundPlv, fundPlvToken, withdrawPlvTo, withdrawTokYieldTo, withdrawPlvTokenTo)** — NONE
- `PerpEngine.sol:458` — `modifier onlyVault()` — **internal (applied to: fundFromVault, withdrawPlvTo, withdrawTokYieldTo, fundTokenFromVault, withdrawPlvTokenTo)** — NONE
- `PerpEngine.sol:466` — `function totalEth() public view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:468` — `function freeEth() external view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:470` — `function totalTokenAssets() public view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:472` — `function freeToken() external view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:482` — `function _key() internal view returns (PoolKey memory)` — **internal (callers: _sqrtP, _currentTick, activeEthDepth, _swapBody, _isDead)** — NONE
- `PerpEngine.sol:489` — `function _sqrtP() internal view returns (uint160 s)` — **internal (callers: markSqrtPriceX96, _quoteEth, activeEthDepth, _ethToToken)** — NONE
- `PerpEngine.sol:534` — `function _currentTick() internal view returns (int24 t)` — **internal (callers: constructor, _writeObs, syncGeneration)** — NONE
- `PerpEngine.sol:558` — `function poke() external` — **anyone** — NONE
- `PerpEngine.sol:597` — `function _writeObs() internal` — **internal (callers: _pokeFunding)** — NONE
- `PerpEngine.sol:634` — `function twapTick() public view returns (int24 tick, bool ok)` — **anyone** — NONE
- `PerpEngine.sol:681` — `function markSqrtPriceX96() public view returns (uint160)` — **anyone** — NONE
- `PerpEngine.sol:686` — `function activeEthDepth() public view returns (uint256)` — **anyone** — NONE
- `PerpEngine.sol:696` — `function maxLeverage() public view returns (uint8 lev)` — **anyone** — NONE
- `PerpEngine.sol:709` — `function _quoteAt(uint256 size, uint256 sp) internal pure returns (uint256)` — **internal (callers: _quoteEth, _quoteMark)** — NONE
- `PerpEngine.sol:713` — `function _quoteEth(uint256 size) internal view returns (uint256)` — **internal (callers: skimInsurance)** — NONE
- `PerpEngine.sol:715` — `function _quoteMark(uint256 size) internal view returns (uint256)` — **internal (callers: _pokeFunding, liquidate, _tryLiquidate, _underwater, _killStats, positionHealth)** — NONE
- `PerpEngine.sol:718` — `function _pokeFunding() internal` — **internal (callers: poke, openLong, openShort, close, liquidate, _doSweep, forceCloseDead, forceCloseAllDead)** — NONE
- `PerpEngine.sol:743` — `function _fundingDelta(Position memory p) internal view returns (int256)` — **internal (callers: fundingDelta, _settle)** — NONE
- `PerpEngine.sol:756` — `function fundingDelta(uint256 id) external view returns (int256)` — **anyone** — NONE
- `PerpEngine.sol:777` — `function openLong(uint8 leverage, uint256 minTokenOut, uint256 liqHint, uint256 amount) public payable nonReentrant n...` — **anyone** — receives the quote through _pullQuote (line 781); pays the pool and takes token through _swapExactIn (line 801)
- `PerpEngine.sol:814` — `function openShort(uint8 leverage, uint256 minEthOut, uint256 liqHint, uint256 amount) public payable nonReentrant no...` — **anyone** — receives the quote through _pullQuote (line 818); sells borrowed token for quote through _swapExactIn (line 837)
- `PerpEngine.sol:849` — `function close(uint256 id, uint256 minOut) external nonReentrant notNested` — **the position's trader** — pays out through _settle (line 853)
- `PerpEngine.sol:856` — `function liquidate(uint256 id) external nonReentrant notNested` — **anyone (subject to the position being underwater at the mark)** — pays the keeper and trader through _settle (line 869)
- `PerpEngine.sol:881` — `function sweepLiquidations(address liquidator) external` — **hook** — pays keepers and traders through _doSweep (line 883)
- `PerpEngine.sol:890` — `function selfSweep(address liquidator) external` — **the engine itself** — pays keepers and traders through _doSweep (line 892)
- `PerpEngine.sol:896` — `function _sweepAfterOpen(address liquidator) internal` — **internal (callers: openLong, openShort)** — NONE
- `PerpEngine.sol:906` — `function _doSweep(address liquidator, bool inLocked) internal` — **internal (callers: sweepLiquidations, selfSweep)** — pays keepers and traders through _tryLiquidate (line 947)
- `PerpEngine.sol:961` — `function _tryLiquidate(uint256 id, address liquidator) internal` — **internal (callers: _doSweep)** — pays the keeper and trader through _settle (line 974)
- `PerpEngine.sol:983` — `function forceCloseDead(uint256 id) external nonReentrant notNested` — **anyone (once the generation is dead)** — pays the keeper and trader through _settle (line 988)
- `PerpEngine.sol:998` — `function forceCloseAllDead() external nonReentrant notNested` — **anyone (once the generation is dead); driven by the hook at relaunch** — pays the keeper and every trader through _settle (line 1010)
- `PerpEngine.sol:1024` — `function syncGeneration() external nonReentrant notNested` — **anyone (permissionless); also driven by the registry and the redemption extension** — NONE
- `PerpEngine.sol:1107` — `function isLiquidatable(uint256 id) external view returns (bool)` — **anyone** — NONE
- `PerpEngine.sol:1114` — `function _underwater(Position memory p) internal view returns (bool)` — **internal (callers: isLiquidatable, positionHealth)** — NONE
- `PerpEngine.sol:1123` — `function _underwaterVal(Position memory p, uint256 val) internal view returns (bool)` — **internal (callers: liquidate, _tryLiquidate, _underwater)** — NONE
- `PerpEngine.sol:1135` — `function _settle(uint256 id, Position memory p, uint256 minOut, uint8 mode, address keeper) internal` — **internal (callers: close, liquidate, _tryLiquidate, forceCloseDead, forceCloseAllDead)** — pays the keeper through _payOut (line 1204) and the trader through _payOut (line 1220)
- `PerpEngine.sol:1231` — `function _run(SwapReq memory r) internal returns (bytes memory)` — **internal (callers: _swapExactIn, _buyExactOut)** — NONE
- `PerpEngine.sol:1238` — `function _swapExactIn(bool buy, uint256 amount) internal returns (uint256 out)` — **internal (callers: openLong, openShort, _settle)** — NONE
- `PerpEngine.sol:1243` — `function _buyExactOut(uint256 tokenOut) internal returns (uint256 ethSpent)` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1247` — `function unlockCallback(bytes calldata raw) external returns (bytes memory)` — **pool manager** — settles pool legs through _swapBody (line 1249)
- `PerpEngine.sol:1255` — `function _swapBody(SwapReq memory r) internal returns (bytes memory)` — **internal (callers: _run, unlockCallback)** — settles both currency legs through swapLeg (line 1268)
- `PerpEngine.sol:1282` — `function _guardOpen(uint8 leverage) internal view` — **internal (callers: openLong, openShort)** — NONE
- `PerpEngine.sol:1306` — `function _isDead() internal view returns (bool)` — **internal (callers: forceCloseDead, forceCloseAllDead, _guardOpen)** — NONE
- `PerpEngine.sol:1310` — `function _takeFee(uint256 sent, bool longSide) internal returns (uint256 collateral)` — **internal (callers: openLong, openShort)** — routes the fee out through _routeFee (line 1314)
- `PerpEngine.sol:1316` — `function _checkNotional(uint256 notionalEth) internal view` — **internal (callers: openLong, openShort)** — NONE
- `PerpEngine.sol:1319` — `function _book(address trader, bool isLong, uint256 collateral, uint256 size, uint256 principal, uint8 leverage) inte...` — **internal (callers: openLong, openShort)** — NONE
- `PerpEngine.sol:1332` — `function _removeOpen(uint256 id) internal` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1342` — `function _ethToToken(uint256 eth) internal view returns (uint256)` — **internal (callers: openShort)** — NONE
- `PerpEngine.sol:1347` — `function _routeFee(uint256 amount, bool longSide) internal` — **internal (callers: _takeFee, _settle)** — pays the dividend and treasury through _payOut (line 1372)
- `PerpEngine.sol:1376` — `function _sendEth(address to, uint256 amount) internal` — **internal (callers: withdrawPlvTo, withdrawTokYieldTo, skimInsurance)** — sends the quote to to through _pushQuote (line 1376)
- `PerpEngine.sol:1388` — `function _payOut(address to, uint256 amount) internal` — **internal (callers: _settle, _routeFee)** — sends native to to (line 1392); ERC20 transfer of the quote to to (line 1401)
- `PerpEngine.sol:1410` — `function claimPayout() external nonReentrant returns (uint256 amount)` — **anyone (pays only the caller's own credit)** — sends the quote to the caller through _pushQuote (line 1414)
- `PerpEngine.sol:1419` — `function _replenishPlv(uint256 shortfall) internal` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1428` — `function _absorbPlvLoss(uint256 loss) internal` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1464` — `function _killStats(Position memory p, uint256 bounty) internal view returns (LiqStats memory st)` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1485` — `function _awardBadge(uint256 id, address to, LiqStats memory st) internal` — **internal (callers: _settle)** — NONE
- `PerpEngine.sol:1523` — `function claimLiquidatorBadges(uint256 n) external nonReentrant` — **anyone (burns only the caller's own credit)** — NONE
- `PerpEngine.sol:1536` — `function _safeTransfer(address token, address to, uint256 amount) private` — **internal (callers: _pushQuote, withdrawPlvTokenTo)** — ERC20 transfer of token to to (line 1537)
- `PerpEngine.sol:1550` — `function fundPlv(uint256 amount) external payable onlyOwner notNested` — **owner** — receives the quote through _pullQuote (line 1551)
- `PerpEngine.sol:1558` — `function fundPlvToken(uint256 amount) external onlyOwner notNested` — **owner** — ERC20 transferFrom of the generation token from the owner (line 1559)
- `PerpEngine.sol:1564` — `function fundInsurance(uint256 amount) external payable` — **anyone** — receives the quote through _pullQuote (line 1565)
- `PerpEngine.sol:1574` — `function creditPerpFee() external payable` — **hook** — receives native payable (line 1574)
- `PerpEngine.sol:1579` — `function creditPerpFeeToken() external payable` — **hook** — receives native payable (line 1579)
- `PerpEngine.sol:1600` — `function creditPerpFeeAsset(address asset, uint256 amount) external` — **hook** — receives the quote through _pullQuote (line 1605)
- `PerpEngine.sol:1610` — `function _creditPerp(bool ethSide) private` — **hook (private; callers: creditPerpFee, creditPerpFeeToken)** — receives native msg.value (line 1617)
- `PerpEngine.sol:1633` — `function fundFromVault(uint256 amount) external payable onlyVault` — **vault** — receives the quote through _pullQuote (line 1634)
- `PerpEngine.sol:1641` — `function withdrawPlvTo(uint256 amount, address to) external onlyVault notNested nonReentrant` — **vault** — sends the quote to to through _sendEth (line 1643)
- `PerpEngine.sol:1647` — `function withdrawTokYieldTo(uint256 amount, address to) external onlyVault notNested nonReentrant` — **vault** — sends the quote to to through _sendEth (line 1649)
- `PerpEngine.sol:1652` — `function fundTokenFromVault(uint256 amount) external onlyVault` — **vault** — ERC20 transferFrom of the generation token from the vault (line 1653)
- `PerpEngine.sol:1658` — `function withdrawPlvTokenTo(uint256 amount, address to) external onlyVault notNested nonReentrant` — **vault** — ERC20 transfer of the generation token to to via _safeTransfer (line 1661)
- `PerpEngine.sol:1665` — `function setFees(uint256 _openBps, uint256 _ogDiscBps, uint256 _liqBps, uint256 _divShareBps, uint256 _keeperBps) ext...` — **owner** — NONE
- `PerpEngine.sol:1669` — `function setRisk(uint256 _warmup, uint256 _ceiling, uint256 _maintBps, uint256 _maxNotBps, uint256 _maxOiBps, uint256...` — **owner** — NONE
- `PerpEngine.sol:1706` — `function setTiers(uint256[] calldata depths, uint8[] calldata levs) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1720` — `function setRouting(address _dividend, address _treasury, address _nftBeneficiary, address _markSource) external only...` — **owner** — NONE
- `PerpEngine.sol:1730` — `function setGuards(uint32 _twapWindow, uint256 _maxLiqBps, uint256 _maxFundingBps) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1751` — `function setVault(address _vault) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1757` — `function setVaultSplit(uint256 _yieldBps, uint256 _insBps) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1763` — `function setVaultLimits(uint256 _maxUtilBps, uint256 _insuranceFloor) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1768` — `function setMinCollateral(uint256 _minCollateral) external onlyOwner` — **owner** — NONE
- `PerpEngine.sol:1784` — `function skimInsurance(uint256 amount, address to) external onlyOwner` — **owner** — sends the quote to to through _sendEth (line 1790)
- `PerpEngine.sol:1802` — `function positionHealth(uint256 id) external view returns ( bool isLong, uint256 markValueEth, uint256 debtOrBackingE...` — **anyone** — NONE
- `PerpEngine.sol:1813` — `receive() external payable` — **anyone** — receives native via receive (line 1813)

### PerpMarkSource

- `PerpMarkSource.sol:93` — `constructor(IPoolManager _poolManager, address _owner) Ownable(_owner)` — **deployer** — NONE
- `PerpMarkSource.sol:100` — `function setPrimary(PoolKey calldata key) external onlyOwner` — **owner** — NONE
- `PerpMarkSource.sol:111` — `function addPool(PoolKey calldata key) external onlyOwner` — **owner** — NONE
- `PerpMarkSource.sol:132` — `function removePool(PoolKey calldata key) external onlyOwner` — **owner** — NONE
- `PerpMarkSource.sol:146` — `function poolCount() external view returns (uint256)` — **anyone** — NONE
- `PerpMarkSource.sol:158` — `function weightedTick() external view returns (int24 tick)` — **anyone** — NONE

### IPerpShares (declared in PerpStakerOracle.sol)

- `PerpStakerOracle.sol:8` — `function ethShareOf(address who) external view returns (uint256)` — **anyone (declaration only; the oracle calls it on the immutable `perpVault`)** — NONE
- `PerpStakerOracle.sol:9` — `function tokShareOf(address who) external view returns (uint256)` — **anyone (declaration only; the oracle calls it on the immutable `perpVault`)** — NONE

### PerpStakerOracle

- `PerpStakerOracle.sol:24` — `constructor(address _perpVault)` — **deployer** — NONE
- `PerpStakerOracle.sol:29` — `function isInstant(address who) external view returns (bool)` — **anyone** — NONE

### PerpSwapLib

- `PerpSwapLib.sol:52` — `function swapLeg( IPoolManager poolManager, PoolKey memory key, Req memory r, bool quoteIsCurrency0, bytes memory hoo...` — **engine (linked library; the only caller is PerpEngine._swapBody)** — settles the pay leg through _settle (line 89) and receives the other leg through take (line 90)
- `PerpSwapLib.sol:101` — `function _settle(IPoolManager poolManager, Currency c, uint256 amount) private` — **internal (callers: swapLeg)** — sends native to the pool manager via settle (line 104); ERC20 transfer of the currency to the pool manager via transfer (line 112)
- `PerpSwapLib.sol:128` — `function migrateInventory(address registry, address oldToken, uint256 fromGen) external returns (uint256 migratedIn)` — **engine (linked library; the only caller is PerpEngine.syncGeneration)** — burns the engine's dead-generation token balance and receives the live token inside the registry call (line 134)

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

- `PerpVault.sol:132` — `constructor(address _engine, address _registry)` — **deployer** — NONE
- `PerpVault.sol:156` — `function hasStakers() external view returns (bool)` — **anyone** — NONE
- `PerpVault.sol:162` — `function assetsEth() public view returns (uint256)` — **anyone** — NONE
- `PerpVault.sol:167` — `function assetsTok() public view returns (uint256)` — **anyone** — NONE
- `PerpVault.sol:187` — `function deposit(uint256 amount) public payable nonReentrant returns (uint256 shares)` — **anyone** — receives native asserted against value (line 195); pulls the ERC20 quote through _pull (line 198); forwards it to the engine at fundFromVault (line 206)
- `PerpVault.sol:212` — `function depositEth() external payable returns (uint256)` — **anyone** — receives native and forwards the whole msg value (line 213)
- `PerpVault.sol:216` — `function _engineQuote() private view returns (address)` — **private (callers: deposit)** — NONE
- `PerpVault.sol:226` — `function _pull(address token, address from, uint256 amount) private` — **private (callers: deposit, depositToken)** — ERC20 pull of the depositor's balance into this vault by transferFrom (line 228)
- `PerpVault.sol:233` — `function _approve(address token, address spender, uint256 amount) private` — **private (callers: deposit, depositToken)** — grants the engine an ERC20 approve allowance over this vault's balance (line 234)
- `PerpVault.sol:240` — `function withdrawEth(uint256 shares) external nonReentrant returns (uint256 paid, uint256 queued)` — **anyone (redeems only the caller's own shares)** — pays the caller out of the engine at withdrawPlvTo (line 259)
- `PerpVault.sol:280` — `function _haircut(uint256 owed, uint256 backing, uint256 claims) private pure returns (uint256)` — **private (callers: claimPendingEth, claimPendingToken)** — NONE
- `PerpVault.sol:290` — `function claimPendingEth() external nonReentrant returns (uint256 paid)` — **anyone (claims only the caller's own queued exit)** — pays the caller out of the engine at withdrawPlvTo (line 302)
- `PerpVault.sol:319` — `function _syncTokYield() internal` — **internal (callers: depositToken, claimTokYield, withdrawToken)** — NONE
- `PerpVault.sol:329` — `function _settleTok(address user) internal` — **internal (callers: depositToken, claimTokYield, withdrawToken)** — NONE
- `PerpVault.sol:337` — `function _resetTokDebt(address user) internal` — **internal (callers: depositToken, claimTokYield, withdrawToken)** — NONE
- `PerpVault.sol:345` — `function depositToken(uint256 amount) external nonReentrant returns (uint256 shares)` — **anyone** — pulls the generation token from the depositor at _pull (line 355) and hands it to the engine at fundTokenFromVault (line 357)
- `PerpVault.sol:363` — `function claimTokYield() external nonReentrant returns (uint256 paid)` — **anyone (claims only the caller's own accrued reward)** — pays the caller out of the engine's segregated pot at withdrawTokYieldTo (line 368)
- `PerpVault.sol:374` — `function withdrawToken(uint256 shares) external nonReentrant returns (uint256 paid, uint256 queued)` — **anyone (redeems only the caller's own shares)** — pays the caller token out of the engine at withdrawPlvTokenTo (line 392)
- `PerpVault.sol:397` — `function claimPendingToken() external nonReentrant returns (uint256 paid)` — **anyone (claims only the caller's own queued exit)** — pays the caller token out of the engine at withdrawPlvTokenTo (line 409)
- `PerpVault.sol:417` — `function ethPosition(address user) external view returns (uint256 redeemable, uint256 instant, uint256 pending)` — **anyone** — NONE
- `PerpVault.sol:425` — `function tokenPosition(address user) external view returns (uint256 redeemable, uint256 instant, uint256 pending)` — **anyone** — NONE
- `PerpVault.sol:434` — `function pendingTokYield(address user) external view returns (uint256)` — **anyone** — NONE
