# Function graph — cluster `hook`

Source tree: `/tmp/blind-final/contracts/solidity` — generated from the decontaminated tree; line numbers identical to the repo.

| file | lines | nodes |
|---|---:|---:|
| `CauldronHook.sol` | 2445 | 91 |
| `vendor/BaseHook.sol` | 217 | 23 |
| `vendor/HookMiner.sol` | 58 | 2 |
| `cauldron/FeeRouteLib.sol` | 214 | 7 |
| `cauldron/DefaultFeeRouter.sol` | 32 | 1 |
| `cauldron/ReserveLib.sol` | 108 | 5 |
| `cauldron/RoyaltyRouter.sol` | 36 | 3 |
| `cauldron/LegacyBuyLib.sol` | 100 | 1 |

133 skeleton nodes, all filled. Machine-checked by `audit/graph/validate.py` at 0 failures.

> Edge note: this tree's `lib/` is a symlink, so the validator's library-symbol grep returns nothing and calls into v4-core / v4-periphery / OpenZeppelin (`poolManager.take`, `poolManager.swap`, `settle`, `sync`, `getSlot0`, `toId`, `amount0`, `amount1`, `toBeforeSwapDelta`, `TickMath`, `LiquidityAmounts`, `FullMath`) cannot be emitted as resolvable `edges[]` entries. Every one of them is recorded in prose on the owning node and enumerated in sections D and J below.

## A. Value inventory

Every storage field that holds or counts value, its denomination, and every line that moves it.

| field | denomination | increases | decreases |
|---|---|---|---|
| `relaunchETH` (CauldronHook.sol:285) | native wei only | CauldronHook.sol:1216 | CauldronHook.sol:1657, CauldronHook.sol:1932 |
| `relaunchAsset` (CauldronHook.sol:2441) | base units of the mapped ERC20 | CauldronHook.sol:1217 | CauldronHook.sol:1685 |
| `legacyBuffer` (CauldronHook.sol:317) | native wei on three of its four writes; the carve at CauldronHook.sol:1325 is denominated in the live pool's currency0 | CauldronHook.sol:1080, CauldronHook.sol:1097, CauldronHook.sol:1325, CauldronHook.sol:1340 | CauldronHook.sol:1067 |
| `legacyOwedToReserve` (CauldronHook.sol:331) | units of the iteration token bought | CauldronHook.sol:1086 | CauldronHook.sol:1117 |
| `proposerOwed` (CauldronHook.sol:496) | native wei; credited only when the fee asset is native (CauldronHook.sol:1258) | CauldronHook.sol:1262 | CauldronHook.sol:2063 |
| `nftCredit` (CauldronHook.sol:366) | weighted volume credit, in whatever unit the volume ledger currently uses | CauldronHook.sol:894 (saturating) | CauldronHook.sol:2249 |
| `_volumeBuckets` (CauldronHook.sol:272) | uint128 of quote-raw or USD-at-1e18 volume | CauldronHook.sol:1513 (saturating at CauldronHook.sol:1514) | CauldronHook.sol:1498, CauldronHook.sol:1507 (wipes to zero) |
| `cumulativeVolume` (CauldronHook.sol:419) | same unit as the buckets | CauldronHook.sol:838 | never |
| `lifetimeVolumeOf` (CauldronHook.sol:416) | weighted volume | CauldronHook.sol:897 (saturating) | never |
| `totalLifetimeVolume` (CauldronHook.sol:417) | weighted volume | CauldronHook.sol:900 (saturating) | never |
| `outstandingCrystals` (CauldronHook.sol:408) | crystal count, global | CauldronHook.sol:2252 | CauldronHook.sol:2324 |
| `outstandingOf` (CauldronHook.sol:409) | crystal count, per collection | CauldronHook.sol:2253 | CauldronHook.sol:2325 |
| `pendingOf` (CauldronHook.sol:412) | crystal count, per player | CauldronHook.sol:2251 | CauldronHook.sol:2323 |
| `committedOf` (CauldronHook.sol:411) | crystal count, per player | CauldronHook.sol:2250 | never |
| `opened` (CauldronHook.sol:410) | creature count, per player | CauldronHook.sol:2328 | never |
| `missStreak` (CauldronHook.sol:413) | consecutive misses | CauldronHook.sol:2333 | CauldronHook.sol:2327 (reset to 0) |
| `batches` (CauldronHook.sol:406) | ticket batches | CauldronHook.sol:2256 (append only) | never; only `batchCursor` (CauldronHook.sol:2341) advances |

Value the hook holds that NO counter tracks: anything arriving through the bare `receive` (CauldronHook.sol:2443), which records nothing by design, and the ether/quote the pool manager credits at `take` (CauldronHook.sol:1460) between the take and the routing that disposes of it.

## B. Balance vs counter

- Three native counters are paid out of ONE undivided balance and none of them is ever compared against `address(this).balance`: `relaunchETH` at CauldronHook.sol:1659 and CauldronHook.sol:1933, `proposerOwed` at CauldronHook.sol:2064, and `legacyBuffer` spent as value through the delegatecalled settle at LegacyBuyLib.sol:89. A shortfall in one shows up as a failed send in whichever path runs first.
- `legacyOwedToReserve` IS reconciled: the sweep reads the live token balance at CauldronHook.sol:1115, clamps at CauldronHook.sol:1116 and debits only what moved at CauldronHook.sol:1117, so the counter cannot outrun the balance. The ERC20 return value at CauldronHook.sol:1118 is NOT checked, so a token that returns false instead of reverting still debits.
- `relaunchAsset` is the mirror image: the send's boolean IS required at CauldronHook.sol:1686, but the amount is never clamped to the live balance, so a token balance reduced elsewhere is not reflected in the counter.
- Known divergence points on the fee path: `_fundGuild` approves at FeeRouteLib.sol:130 and then calls `fundToken` at FeeRouteLib.sol:132; a pull that reports success but transfers less leaves tokens on the hook belonging to no counter, and the allowance is only cleared on the failure branch at FeeRouteLib.sol:134. `_deliver` has the same shape at FeeRouteLib.sol:145 and FeeRouteLib.sol:150.
- Crystal counters: pricing reads only the per-collection `outstandingOf` at CauldronHook.sol:2113 and CauldronHook.sol:2226, while `outstandingCrystals` at CauldronHook.sol:2155 is the global figure the public getter exposes. Resolution decrements both, keyed by the BATCH's stored collection at CauldronHook.sol:2311 rather than the live `collection` set at CauldronHook.sol:1960, so the two drift apart across a relaunch.
- `mintedOut` (CauldronHook.sol:2159) compares minted against maxSupply and ignores the reserved crystals counted at CauldronHook.sol:2226, so it can report not-minted-out while every remaining slot is already spoken for.

## C. Authority map

| gate | holder | rotatable? | where |
|---|---|---|---|
| `onlyOwner` | Ownable owner, set explicitly in the constructor (CauldronHook.sol:562) | yes — Ownable `transferOwnership`, and `renounceOwnership` DEAD-ENDS every owner setter permanently | CauldronHook.sol:1481, 1636, 1737, 1877, 1890, 1906, 1915, 1926, 2018, 2037, 2052, 2070, 2076, 2399, 2406, 2412 |
| `msg.sender != registry` | `registry` (CauldronHook.sol:255) | ONE-SHOT at CauldronHook.sol:1893; thereafter only through the announced pair CauldronHook.sol:1906 → CauldronHook.sol:1926 after `REGISTRY_SWAP_DELAY` (CauldronHook.sol:262) | CauldronHook.sol:1563, 1652, 1680, 1761, 1823, 1959, 1987, 2084 |
| `msg.sender != registry && msg.sender != owner()` | either | follows both of the above | CauldronHook.sol:1836, 1850, 1860, 1872, 1993, 2002, 2010, 2026, 2046, 2360, 2370 |
| adoption gate `require(sender == registry)` | `registry` | same slot as above; before it is set, NO pool can be adopted | CauldronHook.sol:630 |
| `msg.sender != legacyRegistry` | `legacyRegistry` (CauldronHook.sol:312) | freely, no delay, by owner OR registry at CauldronHook.sol:1838 | CauldronHook.sol:1113 |
| `!isOpener[msg.sender]` | any address flagged at CauldronHook.sol:2361 | freely, by owner or registry | CauldronHook.sol:2201 |
| `msg.sender != address(this)` | the hook itself | not rotatable | CauldronHook.sol:1064, CauldronHook.sol:2351 |
| `onlyPoolManager` | the v4 PoolManager, immutable from the periphery base | NOT rotatable (constructor-fixed at CauldronHook.sol:562) | BaseHook.sol:38, 51, 67, 85, 105, 128, 146, 167, 186, 205 |
| `nonReentrant` (not an authority gate) | — | — | CauldronHook.sol:2060, 2198, 2278, 2350 |

Ungated external surface: `fundLegacyBuffer` (CauldronHook.sol:1096), `claimProposerFees` (CauldronHook.sol:2060, self-balance only), `resolveTickets` (CauldronHook.sol:2276), `receive` (CauldronHook.sol:2443), and every view. `RoyaltyRouter.receive` (RoyaltyRouter.sol:32) is ungated and its `hook` target is immutable (RoyaltyRouter.sol:25). Every library entrypoint (FeeRouteLib.sol:48, 79, 162, 192; LegacyBuyLib.sol:50) is ungated on its own account — the gate always sits on the hook side of the delegatecall.

Owner-or-registry slots that are written with NO validation, each of which redirects value or changes what traders pay: `legacyRegistry` (CauldronHook.sol:1838), `deathChecker` (CauldronHook.sol:1851), the three policies (CauldronHook.sol:1861-1863), `feeRouter` (CauldronHook.sol:1873), `nftContract` (CauldronHook.sol:1878), `collection` (CauldronHook.sol:1960), `vault` (CauldronHook.sol:1988), `quest` (CauldronHook.sol:1994), `seeder` (CauldronHook.sol:2003), `perpEngine` (CauldronHook.sol:2011), `guild` (CauldronHook.sol:2027), `activeProposer` (CauldronHook.sol:2047), `_liveKey` (CauldronHook.sol:1824), `quoteOracle` (CauldronHook.sol:1747).

## D. External calls, value and CEI ordering

| site | callee | value | gas | result | ordering |
|---|---|---|---|---|---|
| CauldronHook.sol:744 | `quoteOracle` raw `call` | none | unbounded | checked (CauldronHook.sol:747) | read-only for the hook; runs mid-swap, non-static so it can re-enter |
| CauldronHook.sol:907 | `quest` | none | UNBOUNDED — no cap, unlike the sibling best-effort calls | ignored | effects (CauldronHook.sol:894-900) first |
| CauldronHook.sol:948 | `perpEngine` sweep | none | `gasleft - LIQ_GAS_RESERVE`, floor `LIQ_GAS_MIN` (CauldronHook.sol:947) | ignored | after all volume/credit effects |
| CauldronHook.sol:965 | self → `nativeGachaStep` | none | `gg - GACHA_GAS_RESERVE`, floor `GACHA_GAS_MIN` (CauldronHook.sol:964) | ignored | after credit effects, before the fee take |
| CauldronHook.sol:1035 | self → `legacyBuyStep` | none | `gl - LEGACY_GAS_RESERVE`, floor `LEGACY_GAS_MIN` (CauldronHook.sol:1034) | ignored | fires twice per afterSwap (CauldronHook.sol:798, CauldronHook.sol:1001) |
| CauldronHook.sol:1052 | `seeder` poke | none | `g - SEED_POKE_GAS_RESERVE`, floor `SEED_POKE_GAS_MIN` (CauldronHook.sol:1051) | ignored | before any accounting |
| CauldronHook.sol:1075 | `LegacyBuyLib.buyStep` (delegatecall) | spends native or the quote | unbounded | reverts bubble | buffer zeroed at CauldronHook.sol:1067 BEFORE; credit at CauldronHook.sol:1086 AFTER |
| CauldronHook.sol:1115 / 1118 | `IERC20.balanceOf` / `transfer` | ERC20 out | unbounded | `transfer` return NOT checked | debit at CauldronHook.sol:1117 precedes the transfer |
| CauldronHook.sol:1279 | `IFeeRouter.route` | none | unbounded | try/catch, and discarded unless the parts sum exactly (CauldronHook.sol:1280) | before every send |
| CauldronHook.sol:1201 | `FeeRouteLib.routePerp` (delegatecall) | sends native or approves + is pulled | unbounded | returns undelivered amount | reserve credited AFTER, same expression |
| CauldronHook.sol:1354 | `FeeRouteLib.routeSplit` (delegatecall) | sends native or approves + is pulled | unbounded | returns undelivered amount | reserve credited AFTER at CauldronHook.sol:1353 |
| CauldronHook.sol:1473 | `FeeRouteLib.routeSplit` (delegatecall), surtax | sends native or approves + is pulled | unbounded | non-zero leftover re-routes at CauldronHook.sol:1474 | after the take at CauldronHook.sol:1460 |
| CauldronHook.sol:1410 | `poolManager.getSlot0` | none | unbounded | used for jitter | live pool read on the fee path |
| CauldronHook.sol:1460 | `poolManager.take` | PULLS the fee into the hook | unbounded | reverts bubble | fee asset recorded at CauldronHook.sol:1459 first; routing after |
| CauldronHook.sol:1564 | `IPerpOpenCount.openCount` | none | unbounded | UNGUARDED — a revert blocks linking | before any write |
| CauldronHook.sol:1607 | `IDeathChecker.isDead` | none | unbounded | try/catch → built-in rule | view |
| CauldronHook.sol:1627 | `INFTContract.getHolderTaxRate` | none | UNBOUNDED, on every fee | try/catch → default bps | before the take |
| CauldronHook.sol:1659 | `registry.call{value}` | native out, whole reserve | unbounded | required (CauldronHook.sol:1660) | counter zeroed at CauldronHook.sol:1657 first — CEI clean |
| CauldronHook.sol:1686 | `FeeRouteLib.send` (delegatecall) | ERC20 out | gasCap 0 = unbounded | required (CauldronHook.sol:1686) | counter zeroed at CauldronHook.sol:1685 first — CEI clean |
| CauldronHook.sol:1765 / 1791 | `IPerpForceClose.forceCloseAllDead` / `openCount` | none | unbounded | first try/catch, second UNGUARDED and reverting | transient flag raised/lowered around the first |
| CauldronHook.sol:1933 | `registry.call{value}` | native out, whole reserve | unbounded | required (CauldronHook.sol:1934) | counter zeroed at CauldronHook.sol:1932 first — CEI clean |
| CauldronHook.sol:1965 | `ICauldronCollection.totalMinted` | none | unbounded | UNGUARDED | before the epoch bump |
| CauldronHook.sol:1982 | `ICollectionLiquidator.setLiquidatorMinter` | none | unbounded | try/catch | last |
| CauldronHook.sol:2064 | `msg.sender.call{value}` | native out | unbounded | required (CauldronHook.sol:2065) | balance zeroed at CauldronHook.sol:2063 first + `nonReentrant` — CEI clean |
| CauldronHook.sol:2094 | `ICurvePolicy.priceAt` | none | unbounded, ONCE PER CRYSTAL | try/catch, zero rejected | view |
| CauldronHook.sol:2112 / 2161 / 2162 / 2222 / 2223 / 2313 / 2314 | `totalMinted` / `maxSupply` | none | unbounded | UNGUARDED | reads |
| CauldronHook.sol:2143 | `IOddsPolicy.oddsBps` | none | unbounded | try/catch, clamped | view |
| CauldronHook.sol:2329 | `ICauldronCollection.mint` | none | unbounded | reverts bubble | three counters decremented at CauldronHook.sol:2323-2325 and `opened` at CauldronHook.sol:2328 BEFORE the mint |
| LegacyBuyLib.sol:55 / 89 / 91 / 92 / 93 / 97 | `poolManager.swap` / `settle{value}` / `sync` / `IERC20.transfer` / `settle` / `take` | settles the realised debit `spent` (LegacyBuyLib.sol:70) | unbounded | reverts bubble | nested under the parent swap's unlock |
| RoyaltyRouter.sol:33 | `ILegacyBuffer.fundLegacyBuffer{value}` | forwards the whole `msg.value` | unbounded | UNGUARDED — a failure reverts the royalty payment | only statement |
| FeeRouteLib.sol:106 / 129 / 142 / 168 / 169 / 201 | native `call{value}` | native out | unbounded except FeeRouteLib.sol:169 | captured, never bubbled | caller books the leftover |
| FeeRouteLib.sol:107 / 130 / 132 / 134 / 145 / 147 / 150 / 175 / 204 / 208 / 211 | ERC20 `transfer` / `approve` / pull | ERC20 out | unbounded | captured; `transfer` return decoded at FeeRouteLib.sol:110 and FeeRouteLib.sol:178 | approve-then-pull; allowance cleared only on failure |

## E. Loops

| loop | bound | who grows the bound |
|---|---|---|
| CauldronHook.sol:1497 (full bucket wipe) | `HOURS_PER_DAY` = 24 (CauldronHook.sol:194) | nobody — constant |
| CauldronHook.sol:1506 (partial bucket wipe) | `steps`, clamped to 24 at CauldronHook.sol:1504 | nobody |
| CauldronHook.sol:1527 (24h sum) | 24, fixed array length | nobody |
| CauldronHook.sol:1584 (sibling duplicate scan) | `MAX_SIBLINGS` = 9 (CauldronHook.sol:769) | the registry, one push per call at CauldronHook.sol:1587 |
| CauldronHook.sol:1602 (death sum over siblings) | same 9; EACH iteration is a full 24-bucket sum | the registry, via CauldronHook.sol:1562 |
| CauldronHook.sol:2122 (`crystalsReady`) | `MAX_MINTS_PER_CALL` = 30 (CauldronHook.sol:388); each iteration may make an external policy call | nobody |
| CauldronHook.sol:2134 (`costOfNextCrystals`) | UNBOUNDED — the caller's `count` | any caller; it is a view, so the cost lands on the querying node |
| CauldronHook.sol:2178 (`progress`) | 30, as above | nobody |
| CauldronHook.sol:2237 (commit affordability) | min(caller's maxCount, 30) | nobody; the native path passes `NATIVE_COMMIT_MAX` = 4 (CauldronHook.sol:172) |
| CauldronHook.sol:2294 (resolve, outer over batches) | caller's `maxCount`; the batch array itself grows without bound at CauldronHook.sol:2256 | every committer; the cursor only moves forward at CauldronHook.sol:2341 |
| CauldronHook.sol:2318 (resolve, inner over a batch) | caller's `maxCount` and `Batch.count` (uint16) | the committer, capped at 30 per commit |
| HookMiner.sol:32 (salt search) | `MAX_LOOP` = 160_444 (HookMiner.sol:14) | nobody — constant; view-only |

## F. Denomination and units

- The fee is taken on whichever side the pool recorded as the quote: the currency is chosen at CauldronHook.sol:1458 from stored `quoteIsCurrency0`, stamped into the transient fee-asset field at CauldronHook.sol:1459, and pulled at CauldronHook.sol:1460. Every downstream send reads that transient field.
- `_creditReserve` (CauldronHook.sol:1213) is the single denomination switch for residuals: native goes to CauldronHook.sol:1216, anything else to CauldronHook.sol:1217.
- The proposer slice is NATIVE-ONLY by construction at CauldronHook.sol:1258 and is paid out as raw wei at CauldronHook.sol:2064.
- The legacy-buffer carve matches the fee asset against the live pool's currency0 at CauldronHook.sol:1317, but the no-vault floor fold immediately below tests native-only at CauldronHook.sol:1340; the two rules differ once a generation is quoted in an ERC20.
- The floor vault only receives a NATIVE share: a non-native floor share is folded into the per-asset reserve at CauldronHook.sol:1342-1350.
- Volume units: raw quote units when no oracle is wired (CauldronHook.sol:743), otherwise USD at 1e18 via the multiply-then-divide at CauldronHook.sol:749. A zero factor means `cannot judge` and nothing is recorded (CauldronHook.sol:836).
- There is NO `decimals()` read anywhere in this cluster. The entire scale conversion is whatever `cachedUsdPerRawUnit` (CauldronHook.sol:745) returns, so a 6-decimal and an 18-decimal quote are distinguished only by the oracle's factor.
- Wiring the oracle forcibly restates the volume-denominated constants in the same call: `deathThreshold` (CauldronHook.sol:1744), `volumePerNFT` (CauldronHook.sol:1748), `nftPriceStep` (CauldronHook.sol:1749), `oddsFullVolumeWei` (CauldronHook.sol:1750). `buyWeightBps`/`sellWeightBps` (CauldronHook.sol:888) are ratios and unit-free.
- Bps denominator `BPS` = 10_000 (CauldronHook.sol:148), used at CauldronHook.sol:888, 1197, 1260, 1288, 1290, 1319, 1443, 1449 and in DefaultFeeRouter.sol:26 / DefaultFeeRouter.sol:28. The gacha roll uses a separate literal 10_000 modulus at CauldronHook.sol:2319; the odds ratio divides by `oddsFullVolumeWei` at CauldronHook.sol:2149.
- Narrowing casts: bucket to uint128 with explicit saturation at CauldronHook.sol:1514; odds and count to uint16 at CauldronHook.sol:2255 and CauldronHook.sol:2261 with a guard at CauldronHook.sol:2247; resolved to uint16 at CauldronHook.sol:2338; block number to uint48 at CauldronHook.sol:2259 and CauldronHook.sol:2306; fee to int128 at CauldronHook.sol:1002 and int256→int128 at CauldronHook.sol:1181.
- ReserveLib is tick/liquidity math in v4 units only; its orientation assumption (quote at currency0, token at currency1) is stated at ReserveLib.sol:17 and used at ReserveLib.sol:55.

## G. `unchecked` blocks and rounding direction

| block | what it covers | why it cannot wrap, or what happens if it does |
|---|---|---|
| CauldronHook.sol:891-901 | three credit adds | explicit SATURATION, not wrapping: each add compares against its input at CauldronHook.sol:894, CauldronHook.sol:897, CauldronHook.sol:900 and pins to `type(uint256).max` |
| CauldronHook.sol:1080 | `legacyBuffer += amt - spent` | guarded by `spent < amt` on the same line |
| CauldronHook.sol:1524-1528 | 24-bucket sum | 24 × 2^128 cannot overflow uint256; the bound is the fixed array length |
| CauldronHook.sol:2134 | `++i` only | loop counter |
| CauldronHook.sol:2241 | `n++` | bounded by 30 |
| CauldronHook.sol:2330 | `minted++`, `won++` | local counters bounded by the batch |
| CauldronHook.sol:2336 | `r++`, `processed++` | bounded by `maxCount` and `Batch.count` |
| CauldronHook.sol:2339 | `bi++` | bounded by `batches.length` |

Rounding: every bps split is FLOOR division (CauldronHook.sol:888, 1197, 1260, 1288, 1290, 1319, 1443, 1449, 2149; DefaultFeeRouter.sol:26, DefaultFeeRouter.sol:28), and in every case the complement is taken by SUBTRACTION so the parts sum exactly — CauldronHook.sol:1198, CauldronHook.sol:1289, CauldronHook.sol:1291, CauldronHook.sol:1450, DefaultFeeRouter.sol:29. `_toUsd` multiplies before dividing by 1e18 and rounds DOWN at CauldronHook.sol:749. ReserveLib rounds DOWN in both directions (ReserveLib.sol:80 and the `mulDiv` at ReserveLib.sol:105), and its tick alignment rounds toward minus infinity at ReserveLib.sol:29 and toward plus infinity at ReserveLib.sol:36. Dust from a floor division is never lost: it lands in the subtraction complement, which is always the relaunch reserve or the staker share.

## H. Comment-vs-code observations

1. **ILegacyNote (declared in CauldronHook.sol) L66** — comment at `registry` (CauldronHook.sol:63) says this is the registry entry that records a legacy buyback against the live collection's pending entitlement; code never calls `noteLegacyBuy` (CauldronHook.sol:66) and instead accrues `legacyOwedToReserve` (CauldronHook.sol:1086) for a later registry-pulled sweep
2. **CauldronHook L556** — comment at `stability` (CauldronHook.sol:239) says the treasury slot is a dead slot read by nothing and kept only for layout stability; code at `treasury` (CauldronHook.sol:565) still writes it from a constructor parameter
3. **CauldronHook L572** — comment at `afterSwapReturnDelta` (CauldronHook.sol:114) says the hook's permissions are afterInitialize, afterSwap and afterSwapReturnDelta; code additionally enables `beforeSwap` (CauldronHook.sol:585) and `beforeSwapReturnDelta` (CauldronHook.sol:589), which is what lets the buy-leg fee be skimmed before the swap
4. **CauldronHook L741** — comment at `oracles` (CauldronHook.sol:99) says the 24h volume is fully computed inside afterSwap with no oracles; code at `quoteOracle` (CauldronHook.sol:742) makes a state-changing external oracle call from inside that same callback whenever the slot is wired
5. **CauldronHook L778** — comment at `liqHint` (CauldronHook.sol:923) says the swap must carry a liquidation hint in hookData and the engine is fired at the hinted position; code at `sweepLiquidations` (CauldronHook.sol:949) passes no hint at all and calls a bounded rotating sweep instead
6. **CauldronHook L778** — comment at `liquidateInSwap` (CauldronHook.sol:929) names `liquidateInSwap` as the function whose gas is being reserved; code at `perpEngine` (CauldronHook.sol:948) calls `sweepLiquidations` (CauldronHook.sol:949)
7. **CauldronHook L778** — comment at `GACHA_GAS_RESERVE` (CauldronHook.sol:958) says the native gacha self-call keeps a reserve for fee collection and the return; code at `gg` (CauldronHook.sol:964) compares remaining gas against the MIN constant but subtracts the RESERVE constant at `GACHA_GAS_RESERVE` (CauldronHook.sol:965), so the two constants are not compared against each other the way the sibling perp gate does at `LIQ_GAS_RESERVE` (CauldronHook.sol:947)
8. **CauldronHook L1128** — comment at `unspecifiedIsEth` (CauldronHook.sol:1145) says the afterSwap side early-returns because its `unspecifiedIsEth` test is false; code names that variable `unspecifiedIsCurrency0` (CauldronHook.sol:985) and compares it against the recorded quote side rather than against ether
9. **CauldronHook L1128** — comment at `deltas` (CauldronHook.sol:103) says the hook collects its tiered fees via afterSwap return deltas; code charges the buy leg here instead, returning a BeforeSwapDelta built at `toBeforeSwapDelta` (CauldronHook.sol:1181)
10. **CauldronHook L1220** — comment at `rule` (CauldronHook.sol:1338) says the no-vault floor fold uses the same native-only rule as the buyback carve above it; code at `_feeAsset` (CauldronHook.sol:1340) tests the fee asset against address(0) while the carve above tests it against `_liveKey` (CauldronHook.sol:1317), so the two rules differ once a generation is quoted in an ERC20
11. **CauldronHook L1220** — comment at `feeRouter` (CauldronHook.sol:693) points the reader at a line number for the re-entrant fee router; code has `feeRouter` (CauldronHook.sol:1277) as the actual read site, and the cited line is a comment
12. **CauldronHook L1562** — comment at `treasury` (CauldronHook.sol:1580) says seven pools is already a wide treasury and the cap is headroom above that; code sets `MAX_SIBLINGS` (CauldronHook.sol:769) to nine
13. **LegacyBuyLib L50** — comment at `settle` (LegacyBuyLib.sol:44) says this function is ETH-quote only because `settle` assumes the quote is native; code at `q` (LegacyBuyLib.sol:88) branches and takes an ERC20 sync/transfer/settle path for a non-native quote
14. **LegacyBuyLib L50** — comment at `legacyBuyStep` (CauldronHook.sol:1017) says `legacyBuyStep` settles with `settle{value:}`; code at `poolManager` (LegacyBuyLib.sol:91) settles an ERC20 quote with sync + transfer + bare settle instead
15. **RoyaltyRouter L32** — comment at `hook` (RoyaltyRouter.sol:20) says the router forwards atomically and that if the hook forward ever fails the `ETH` (RoyaltyRouter.sol:21) stays here, recoverable by re-pointing; code at `fundLegacyBuffer` (RoyaltyRouter.sol:33) makes that forward an unguarded external call, so a failing hook reverts the whole receive and nothing is retained in this contract

## I. Function inventory

| contract | line | function | authority | value effect |
|---|---:|---|---|---|
| IRegistryQuotes (declared in CauldronHook.sol) | 32 | `function allowedQuote(address quote) external view returns (bool)` | interface declaration (no body in this cluster) | NONE |
| IQuoteOracle (declared in CauldronHook.sol) | 42 | `function cachedUsdPerRawUnit(address quote) external returns (uint256)` | interface declaration (no body in this cluster) | NONE |
| IPerpOpenCount (declared in CauldronHook.sol) | 49 | `function openCount() external view returns (uint256)` | interface declaration (no body in this cluster) | NONE |
| IPerpEngineLiq (declared in CauldronHook.sol) | 53 | `function liquidateInSwap(uint256 id, address liquidator) external` | interface declaration (no body in this cluster) | NONE |
| IPerpEngineLiq (declared in CauldronHook.sol) | 54 | `function liquidateManyInSwap(uint256[] calldata ids, address liquidator) external` | interface declaration (no body in this cluster) | NONE |
| IPerpEngineLiq (declared in CauldronHook.sol) | 55 | `function sweepLiquidations(address liquidator) external` | interface declaration (no body in this cluster) | NONE |
| ICollectionLiquidator (declared in CauldronHook.sol) | 60 | `function setLiquidatorMinter(address minter) external` | interface declaration (no body in this cluster) | NONE |
| ILegacyNote (declared in CauldronHook.sol) | 66 | `function noteLegacyBuy(uint256 tokensBought) external` | interface declaration (no body in this cluster) | NONE |
| IPerpForceClose (declared in CauldronHook.sol) | 71 | `function forceCloseAllDead() external` | interface declaration (no body in this cluster) | NONE |
| IPerpForceClose (declared in CauldronHook.sol) | 72 | `function openCount() external view returns (uint256)` | interface declaration (no body in this cluster) | NONE |
| IPerpFeeCredit (declared in CauldronHook.sol) | 78 | `function creditPerpFee() external payable` | interface declaration (no body in this cluster) | NONE |
| IPerpFeeCredit (declared in CauldronHook.sol) | 79 | `function creditPerpFeeToken() external payable` | interface declaration (no body in this cluster) | NONE |
| IPerpFeeCredit (declared in CauldronHook.sol) | 82 | `function creditPerpFeeAsset(address asset, uint256 amount) external` | interface declaration (no body in this cluster) | NONE |
| ISeederInSwap (declared in CauldronHook.sol) | 89 | `function pokeInSwap() external` | interface declaration (no body in this cluster) | NONE |
| CauldronHook | 556 | `constructor( IPoolManager _poolManager, uint256 _deathThreshold, address _nftContract, ad...` | deployer | NONE |
| CauldronHook | 572 | `function getHookPermissions() public pure override returns (Hooks.Permissions memory)` | anyone | NONE |
| CauldronHook | 621 | `function _afterInitialize( address sender, PoolKey calldata key, uint160, int24 ) interna...` | poolManager (and, inside it, only the registry may be the initializer) | NONE |
| CauldronHook | 741 | `function _toUsd(address quote, uint256 raw) internal returns (uint256)` | internal (callers: CauldronHook._afterSwap) | NONE |
| CauldronHook | 778 | `function _afterSwap( address sender, PoolKey calldata key, SwapParams calldata params, Ba...` | poolManager | NONE directly; it returns a positive int128 fee at `fee` (line 1002) which the pool manager takes out of th... |
| CauldronHook | 1015 | `function _maybeLegacyBuyback(PoolId id, PoolKey calldata key) private` | internal (callers: CauldronHook._afterSwap) | NONE |
| CauldronHook | 1047 | `function _maybePoke() private` | internal (callers: CauldronHook._afterSwap) | NONE |
| CauldronHook | 1063 | `function legacyBuyStep(PoolKey calldata key) external` | hook itself (self-call only) | spends native or quote out of the hook through the delegatecalled `buyStep` (line 1075) |
| CauldronHook | 1096 | `function fundLegacyBuffer() external payable` | anyone | receives native, credited to `legacyBuffer` (line 1097) |
| CauldronHook | 1112 | `function sweepLegacyReserve(address token, address to) external returns (uint256 amt)` | legacyRegistry | ERC20 transfer of `token` to the caller-supplied recipient (line 1118) |
| CauldronHook | 1128 | `function _beforeSwap( address sender, PoolKey calldata key, SwapParams calldata params, b...` | poolManager | NONE directly; the returned BeforeSwapDelta at `toBeforeSwapDelta` (line 1181) makes the manager credit the... |
| CauldronHook | 1196 | `function _routePerpFee(uint256 amount, bool isBuy) private` | internal (callers: CauldronHook._takeEthFee) | no direct transfer; the guild and staker shares leave through the delegatecalled `routePerp` (line 1201) |
| CauldronHook | 1213 | `function _creditReserve(uint256 amount) private` | internal (callers: CauldronHook._routePerpFee, CauldronHook._routeEthFee) | NONE |
| CauldronHook | 1220 | `function _routeEthFee(uint256 feeAmount) private` | internal (callers: CauldronHook._takeEthFee) | no direct transfer; the guild and floor shares leave through the delegatecalled `routeSplit` (line 1354) an... |
| CauldronHook | 1364 | `function snipeSurtaxBps(PoolId id) public view returns (uint256)` | anyone | NONE |
| CauldronHook | 1376 | `function _defaultSurtaxBps(PoolId id) internal view returns (uint256)` | internal (callers: CauldronHook.snipeSurtaxBps) | NONE |
| CauldronHook | 1426 | `function _takeEthFee( PoolId id, PoolKey calldata key, address sender, bytes calldata hoo...` | internal (callers: CauldronHook._beforeSwap, CauldronHook._afterSwap) | pulls `total` (line 1460) of the quote currency out of the pool manager into this hook |
| CauldronHook | 1481 | `function setSnipeParams(uint256 windowBlocks, uint256 maxBps) external onlyOwner` | owner | NONE |
| CauldronHook | 1491 | `function _recordVolume(PoolId id, uint256 amount) private` | internal (callers: CauldronHook._afterSwap) | NONE |
| CauldronHook | 1521 | `function getVolume24h(PoolId id) public view returns (uint256 total)` | anyone | NONE |
| CauldronHook | 1562 | `function linkVolume(PoolId primary, PoolId secondary) external` | registry | NONE |
| CauldronHook | 1594 | `function isDead(PoolId id) external view returns (bool)` | anyone | NONE |
| CauldronHook | 1616 | `function _getCurrentBucket() private view returns (uint256)` | internal (callers: CauldronHook._recordVolume) | NONE |
| CauldronHook | 1624 | `function _getHolderTaxRate(address holder) private view returns (uint256)` | internal (callers: CauldronHook._takeEthFee) | NONE |
| CauldronHook | 1636 | `function setDefaultTaxBps(uint256 _bps) external onlyOwner` | owner | NONE |
| CauldronHook | 1651 | `function releaseRelaunchETH() external returns (uint256 amount)` | registry | sends native to `registry` (line 1659) |
| CauldronHook | 1679 | `function releaseRelaunchAsset(address asset) external returns (uint256 amount)` | registry | ERC20 transfer of `asset` to `registry` (line 1686) |
| CauldronHook | 1737 | `function setDeathThreshold( uint256 _threshold, address _oracle, uint256 _volumePerNFT, u...` | owner | NONE |
| CauldronHook | 1760 | `function forceClosePerps() external` | registry | NONE |
| CauldronHook | 1822 | `function setLiveKey(PoolKey calldata k) external` | registry | NONE |
| CauldronHook | 1828 | `function liveKey() external view returns (PoolKey memory)` | anyone | NONE |
| CauldronHook | 1835 | `function setLegacyBuyback(address registry_, uint256 bps, uint256 threshold) external` | owner or registry | NONE |
| CauldronHook | 1849 | `function setDeathChecker(address _checker) external` | owner or registry | NONE |
| CauldronHook | 1859 | `function setPolicies(address _surtax, address _odds, address _curve) external` | owner or registry | NONE |
| CauldronHook | 1871 | `function setFeeRouter(address _router) external` | owner or registry | NONE |
| CauldronHook | 1877 | `function setNftContract(address _nft) external onlyOwner` | owner | NONE |
| CauldronHook | 1890 | `function setRegistry(address _registry) external onlyOwner` | owner | NONE |
| CauldronHook | 1906 | `function proposeRegistryOverride(address _registry) external onlyOwner` | owner | NONE |
| CauldronHook | 1915 | `function cancelRegistryOverride() external onlyOwner` | owner | NONE |
| CauldronHook | 1926 | `function executeRegistryOverride() external onlyOwner` | owner | sends native to the OUTGOING `registry` (line 1933) |
| CauldronHook | 1958 | `function setCollection(address _collection) external` | registry | NONE |
| CauldronHook | 1980 | `function _wireLiquidator(address _collection) private` | internal (callers: CauldronHook.setCollection, CauldronHook.setPerpEngine) | NONE |
| CauldronHook | 1986 | `function setVault(address _vault) external` | registry | NONE |
| CauldronHook | 1992 | `function setQuest(address _quest) external` | owner or registry | NONE |
| CauldronHook | 2001 | `function setSeeder(address _seeder) external` | owner or registry | NONE |
| CauldronHook | 2009 | `function setPerpEngine(address _engine) external` | owner or registry | NONE |
| CauldronHook | 2018 | `function setFloorBps(uint256 _bps) external onlyOwner` | owner | NONE |
| CauldronHook | 2025 | `function setGuild(address _guild) external` | owner or registry | NONE |
| CauldronHook | 2037 | `function setGuildBps(uint256 _bps) external onlyOwner` | owner | NONE |
| CauldronHook | 2045 | `function setActiveProposer(address who) external` | owner or registry | NONE |
| CauldronHook | 2052 | `function setProposerBps(uint256 _bps) external onlyOwner` | owner | NONE |
| CauldronHook | 2060 | `function claimProposerFees() external nonReentrant returns (uint256 amount)` | anyone (each caller can only claim their own accrued balance) | sends native to the caller via `call` (line 2064) |
| CauldronHook | 2070 | `function setNftCurve(uint256 _base, uint256 _step) external onlyOwner` | owner | NONE |
| CauldronHook | 2076 | `function setCreditUntaggedSwaps(bool on) external onlyOwner` | owner | NONE |
| CauldronHook | 2083 | `function setNftCurveFrom(uint256 _base) external` | registry | NONE |
| CauldronHook | 2091 | `function nftPriceAt(uint256 k) public view returns (uint256)` | anyone | NONE |
| CauldronHook | 2103 | `function creditOf(address player) external view returns (uint256)` | anyone | NONE |
| CauldronHook | 2111 | `function _curvePos() internal view returns (uint256)` | internal (callers: CauldronHook.crystalsReady, CauldronHook.costOfNextC... | NONE |
| CauldronHook | 2117 | `function crystalsReady(address player) public view returns (uint256 ready)` | anyone | NONE |
| CauldronHook | 2131 | `function costOfNextCrystals(uint256 count) public view returns (uint256 cost)` | anyone | NONE |
| CauldronHook | 2140 | `function oddsForPlay(uint256 playWei) public view returns (uint256 bps)` | anyone | NONE |
| CauldronHook | 2154 | `function outstandingTickets() external view returns (uint256)` | anyone | NONE |
| CauldronHook | 2159 | `function mintedOut() external view returns (bool)` | anyone | NONE |
| CauldronHook | 2169 | `function progress(address player) external view returns (uint256 inCurrent, uint256 thres...` | anyone | NONE |
| CauldronHook | 2196 | `function commitCrystals(address player, uint256 maxCount, uint256 playWei) external nonRe...` | opener (an address flagged in isOpener) | NONE |
| CauldronHook | 2216 | `function _commitCrystals(address player, uint256 maxCount, uint256 playWei) internal retu...` | internal (callers: CauldronHook.commitCrystals, CauldronHook.nativeGach... | NONE |
| CauldronHook | 2276 | `function resolveTickets(uint256 maxCount) public nonReentrant returns (uint256 processed,...` | anyone | NONE |
| CauldronHook | 2288 | `function _resolveTickets(uint256 maxCount) internal returns (uint256 processed, uint256 won)` | internal (callers: CauldronHook.resolveTickets, CauldronHook.nativeGach... | NONE |
| CauldronHook | 2350 | `function nativeGachaStep(address player, uint256 playWei) external nonReentrant` | hook itself (self-call only) | NONE |
| CauldronHook | 2359 | `function setOpener(address who, bool allowed) external` | owner or registry | NONE |
| CauldronHook | 2369 | `function setTaxExempt(address who, bool exempt) external` | owner or registry | NONE |
| CauldronHook | 2383 | `function _isExemptPlayer(address sender, bytes calldata hookData) private view returns (b...` | internal (callers: CauldronHook._beforeSwap, CauldronHook._afterSwap) | NONE |
| CauldronHook | 2391 | `function _taxedPlayer(address sender, bytes calldata hookData) private view returns (addr...` | internal (callers: CauldronHook._isExemptPlayer, CauldronHook._takeEthFee) | NONE |
| CauldronHook | 2399 | `function setOddsParams(uint256 fullVolumeWei, uint256 pity) external onlyOwner` | owner | NONE |
| CauldronHook | 2406 | `function setMaxOdds(uint256 bps) external onlyOwner` | owner | NONE |
| CauldronHook | 2412 | `function setWeights(uint256 buyBps, uint256 sellBps) external onlyOwner` | owner | NONE |
| CauldronHook | 2443 | `receive() external payable` | anyone | receives native via `receive` (line 2443) |
| DefaultFeeRouter | 21 | `function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256...` | anyone | NONE |
| FeeRouteLib | 48 | `function routeSplit( address asset, address guild, address vault, uint256 toGuild, uint25...` | internal to the hook via delegatecall (callers: CauldronHook._routeEthF... | no direct transfer; value leaves through `_fundGuild` (FeeRouteLib.sol:64) and `_move` (FeeRouteLib.sol:68) |
| FeeRouteLib | 79 | `function routePerp( address asset, address guild, address engine, uint256 toGuild, uint25...` | internal to the hook via delegatecall (caller: CauldronHook._routePerpF... | no direct transfer; value leaves through `_fundGuild` (FeeRouteLib.sol:97) and `_deliver` (FeeRouteLib.sol:... |
| FeeRouteLib | 105 | `function _move(address asset, address to, uint256 amount) private returns (bool ok)` | internal (callers: FeeRouteLib.routeSplit) | sends native to the recipient `to` (line 106); ERC20 transfer encoded against `asset` (line 107) |
| FeeRouteLib | 128 | `function _fundGuild(address asset, address guild, uint256 amount) private returns (bool ok)` | internal (callers: FeeRouteLib.routeSplit, FeeRouteLib.routePerp) | sends native to the guild `guild` (line 129); ERC20 approve of `asset` (line 130) then a pull by `guild` (l... |
| FeeRouteLib | 137 | `function _deliver(address asset, address to, uint256 amount, bytes4 nativeSel, bytes4 ass...` | internal (callers: FeeRouteLib.routePerp) | sends native to the engine `to` (line 142); ERC20 approve of `asset` (line 145) then a pull by `to` (line 147) |
| FeeRouteLib | 162 | `function send(address asset, address to, uint256 amount, uint256 gasCap) external returns...` | internal to the hook via delegatecall (caller: CauldronHook.releaseRela... | sends native to `to` (line 168); sends native with a gas cap to `to` (line 169); ERC20 transfer encoded aga... |
| FeeRouteLib | 192 | `function deliver( address asset, address to, uint256 amount, bytes4 nativeSelector, bytes...` | internal to the hook via delegatecall; NO caller anywhere in the source... | sends native to `to` (line 201); ERC20 approve of `asset` (line 204) then a pull by `to` (line 208) |
| LegacyBuyLib | 50 | `function buyStep(IPoolManager poolManager, PoolKey calldata key, uint256 amt) external re...` | anyone in principle (a linked library address with no state and no fund... | sends native to `poolManager` (LegacyBuyLib.sol:89); ERC20 transfer of the quote to the pool manager via `t... |
| ReserveLib | 27 | `function _alignDown(int24 tick, int24 spacing) internal pure returns (int24)` | internal (callers: ReserveLib.reserveTicks) | NONE |
| ReserveLib | 34 | `function _alignUp(int24 tick, int24 spacing) internal pure returns (int24)` | internal (callers: ReserveLib.reserveTicks) | NONE |
| ReserveLib | 50 | `function reserveTicks(int24 launchTick, int24 spacing, int24 offset) internal pure return...` | internal (callers: out-of-cluster PoolOps) | NONE |
| ReserveLib | 75 | `function liquidityForTokenOut(int24 tickLower, int24 tickUpper, uint256 amount1) internal...` | internal (callers: out-of-cluster PoolOps) | NONE |
| ReserveLib | 96 | `function tokenOutForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity) intern...` | internal (callers: out-of-cluster PoolOps) | NONE |
| ILegacyBuffer (declared in RoyaltyRouter.sol) | 5 | `function fundLegacyBuffer() external payable` | interface declaration (no body in this cluster) | NONE |
| RoyaltyRouter | 27 | `constructor(address _hook)` | deployer | NONE |
| RoyaltyRouter | 32 | `receive() external payable` | anyone (any address that sends ether here) | receives native, gated on `value` (line 33); sends native to `hook` (line 33) |
| BaseHook | 18 | `constructor(IPoolManager _manager) ImmutableState(_manager)` | deployer | NONE |
| BaseHook | 25 | `function getHookPermissions() public pure virtual returns (Hooks.Permissions memory)` | anyone (abstract declaration; the implementation is CauldronHook.getHoo... | NONE |
| BaseHook | 31 | `function validateHookAddress(BaseHook _this) internal pure virtual` | internal (callers: BaseHook constructor) | NONE |
| BaseHook | 36 | `function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96) ext...` | poolManager | NONE |
| BaseHook | 44 | `function _beforeInitialize(address, PoolKey calldata, uint160) internal virtual returns (...` | internal (callers: BaseHook.beforeInitialize) | NONE |
| BaseHook | 49 | `function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int2...` | poolManager | NONE |
| BaseHook | 57 | `function _afterInitialize(address, PoolKey calldata, uint160, int24) internal virtual ret...` | internal (callers: BaseHook.afterInitialize) | NONE |
| BaseHook | 62 | `function beforeAddLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams ...` | poolManager | NONE |
| BaseHook | 71 | `function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, b...` | internal (callers: BaseHook.beforeAddLiquidity) | NONE |
| BaseHook | 80 | `function beforeRemoveLiquidity( address sender, PoolKey calldata key, ModifyLiquidityPara...` | poolManager | NONE |
| BaseHook | 89 | `function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata...` | internal (callers: BaseHook.beforeRemoveLiquidity) | NONE |
| BaseHook | 98 | `function afterAddLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams c...` | poolManager | NONE |
| BaseHook | 109 | `function _afterAddLiquidity( address, PoolKey calldata, ModifyLiquidityParams calldata, B...` | internal (callers: BaseHook.afterAddLiquidity) | NONE |
| BaseHook | 121 | `function afterRemoveLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParam...` | poolManager | NONE |
| BaseHook | 132 | `function _afterRemoveLiquidity( address, PoolKey calldata, ModifyLiquidityParams calldata...` | internal (callers: BaseHook.afterRemoveLiquidity) | NONE |
| BaseHook | 144 | `function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, byt...` | poolManager | NONE |
| BaseHook | 152 | `function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata) inte...` | internal (callers: BaseHook.beforeSwap) | NONE |
| BaseHook | 161 | `function afterSwap( address sender, PoolKey calldata key, SwapParams calldata params, Bal...` | poolManager | NONE |
| BaseHook | 171 | `function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes c...` | internal (callers: BaseHook.afterSwap) | NONE |
| BaseHook | 180 | `function beforeDonate( address sender, PoolKey calldata key, uint256 amount0, uint256 amo...` | poolManager | NONE |
| BaseHook | 190 | `function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) inter...` | internal (callers: BaseHook.beforeDonate) | NONE |
| BaseHook | 199 | `function afterDonate( address sender, PoolKey calldata key, uint256 amount0, uint256 amou...` | poolManager | NONE |
| BaseHook | 209 | `function _afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) intern...` | internal (callers: BaseHook.afterDonate) | NONE |
| HookMiner | 23 | `function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory co...` | internal (callers: deploy scripts and test harnesses, none in this clus... | NONE |
| HookMiner | 48 | `function computeAddress(address deployer, uint256 salt, bytes memory creationCodeWithArgs...` | internal (callers: HookMiner.find) | NONE |

## J. Cluster extras

### J1. In-swap reads of live pool state, and what is derived from them

- `_afterSwap` is handed the manager's computed `BalanceDelta` at CauldronHook.sol:782. It reads the quote leg TWICE: CauldronHook.sol:811 for the volume figure and CauldronHook.sol:995 for the sell-leg fee base. Which side is read is decided by the STORED `quoteIsCurrency0` (CauldronHook.sol:794), not by inspecting the key — so the adoption-time answer governs every later swap.
  Derived from CauldronHook.sol:811: the USD/raw conversion (CauldronHook.sol:835), the bucket write (CauldronHook.sol:1513), `cumulativeVolume` (CauldronHook.sol:838), the weighted credit (CauldronHook.sol:888) and therefore `nftCredit`, `lifetimeVolumeOf`, `totalLifetimeVolume`, and the in-swap gacha play size (CauldronHook.sol:915).
  Derived from CauldronHook.sol:995: `ethAmount` and hence the whole sell-leg fee (CauldronHook.sol:1000).
- `_defaultSurtaxBps` performs the cluster's only direct pool-storage read: `poolManager.getSlot0(id)` at CauldronHook.sol:1410, taking the CURRENT tick. It is folded together with `blockhash(block.number - 1)`, the pool id and the block number into the jitter at CauldronHook.sol:1411, scaled by the remaining window at CauldronHook.sol:1415 and added to the linear decay at CauldronHook.sol:1416. This runs on the fee path of EVERY swap via CauldronHook.sol:1441 → CauldronHook.sol:1372.
- `_takeEthFee` performs the only state-changing manager call on the ordinary path: `poolManager.take(feeCur, address(this), total)` at CauldronHook.sol:1460, which is what actually moves the fee into the hook.
- `_beforeSwap` reads NO pool state. Everything it decides comes from `params` (CauldronHook.sol:1141, CauldronHook.sol:1161) and from storage (CauldronHook.sol:1138, CauldronHook.sol:1140).
- The nested buyback, running under the parent swap's unlock, reads and writes live pool state directly: `poolManager.swap` at LegacyBuyLib.sol:55, the realised debit at LegacyBuyLib.sol:70, `settle{value}` at LegacyBuyLib.sol:89, `sync` at LegacyBuyLib.sol:91, `settle` at LegacyBuyLib.sol:93, the credit amount at LegacyBuyLib.sol:96 and `take` at LegacyBuyLib.sol:97.
- Not read anywhere in the cluster: pool liquidity, tick bitmap, fee growth, or any TWAP. The only price-sensitive input is the single tick at CauldronHook.sol:1410.

### J2. Hook permission bits

Declared once, in `getHookPermissions` (CauldronHook.sol:572), and enforced against the deployed address by `validateHookAddress` (BaseHook.sol:31) during construction.

| bit | value | line |
|---|---|---:|
| `beforeInitialize` | false | CauldronHook.sol:579 |
| `afterInitialize` | TRUE | CauldronHook.sol:580 |
| `beforeAddLiquidity` | false | CauldronHook.sol:581 |
| `afterAddLiquidity` | false | CauldronHook.sol:582 |
| `beforeRemoveLiquidity` | false | CauldronHook.sol:583 |
| `afterRemoveLiquidity` | false | CauldronHook.sol:584 |
| `beforeSwap` | TRUE | CauldronHook.sol:585 |
| `afterSwap` | TRUE | CauldronHook.sol:586 |
| `beforeDonate` | false | CauldronHook.sol:587 |
| `afterDonate` | false | CauldronHook.sol:588 |
| `beforeSwapReturnDelta` | TRUE | CauldronHook.sol:589 |
| `afterSwapReturnDelta` | TRUE | CauldronHook.sol:590 |
| `afterAddLiquidityReturnDelta` | false | CauldronHook.sol:591 |
| `afterRemoveLiquidityReturnDelta` | false | CauldronHook.sol:592 |

The five enabled bits are exactly the ones with live bodies: CauldronHook.sol:621, CauldronHook.sol:1128 and CauldronHook.sol:778. The nine disabled bits correspond to BaseHook defaults that revert `HookNotImplemented` (BaseHook.sol:45, 58, 76, 94, 117, 140, 157, 176, 195, 214) — note CauldronHook overrides three of those, so only the liquidity and donate defaults remain reachable-in-principle, and their permission bits are false.

### J3. Every BalanceDelta / BeforeSwapDelta construction

| site | construction | meaning |
|---|---|---|
| CauldronHook.sol:1135 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | self-buy or relaunch-close: charge nothing |
| CauldronHook.sol:1138 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | pool not adopted |
| CauldronHook.sol:1164 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | not an exact-input buy |
| CauldronHook.sol:1168 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | exempt player |
| CauldronHook.sol:1177 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | computed fee rounded to zero |
| CauldronHook.sol:1181 | `toBeforeSwapDelta(int128(int256(fee)), 0)` | POSITIVE specified delta = the hook consumed `fee` of the input; unspecified leg untouched |
| CauldronHook.sol:787, 791, 987, 992 | afterSwap returns literal `0` | no return delta taken |
| CauldronHook.sol:1002 | afterSwap returns `int128(uint128(fee))` | positive = the hook takes `fee` out of the unspecified (quote) leg |
| CauldronHook.sol:782 | `BalanceDelta delta` parameter | consumed, not constructed; read at CauldronHook.sol:811 and CauldronHook.sol:995 |
| LegacyBuyLib.sol:55 | `BalanceDelta d = poolManager.swap(...)` | the nested buy's realised delta; read at LegacyBuyLib.sol:70 and LegacyBuyLib.sol:96 |
| BaseHook.sol:105, 116, 128, 139 | `BalanceDelta` returns on the four liquidity callbacks | declared only; all unimplemented and all permission-disabled |

