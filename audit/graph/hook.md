# Function graph — cluster `hook`

Source tree: `contracts/solidity` in the repository working tree. Re-extracted 2026-09-12 after the fix wave: line numbers, node set and semantics are current as of that tree.

| file | lines | nodes |
|---|---:|---:|
| `CauldronHook.sol` | 2546 | 92 |
| `vendor/BaseHook.sol` | 217 | 23 |
| `vendor/HookMiner.sol` | 58 | 2 |
| `cauldron/FeeRouteLib.sol` | 253 | 7 |
| `cauldron/DefaultFeeRouter.sol` | 32 | 1 |
| `cauldron/ReserveLib.sol` | 108 | 5 |
| `cauldron/RoyaltyRouter.sol` | 48 | 3 |
| `cauldron/LegacyBuyLib.sol` | 155 | 1 |

The anti-sniper curve now lives in a NINTH file, `cauldron/SurtaxLib.sol` (128 lines), reached by the hook at CauldronHook.sol:1472. It is not in this cluster's file list, so it carries no nodes here; its behaviour is recorded on `snipeSurtaxBps` (CauldronHook.sol:1466).

134 skeleton nodes, all filled. Machine-checked by `audit/graph/validate.py` at 0 failures.

> Edge note: this tree's `lib/` is a symlink, so the validator's library-symbol grep returns nothing and calls into v4-core / v4-periphery / OpenZeppelin (`poolManager.take`, `poolManager.swap`, `settle`, `sync`, `getSlot0`, `toId`, `amount0`, `amount1`, `toBeforeSwapDelta`, `TickMath`, `LiquidityAmounts`, `FullMath`) cannot be emitted as resolvable `edges[]` entries. Every one of them is recorded in prose on the owning node and enumerated in sections D and J below.

## A. Value inventory

Every storage field that holds or counts value, its denomination, and every line that moves it.

| field | denomination | increases | decreases |
|---|---|---|---|
| `relaunchETH` (CauldronHook.sol:286) | native wei only | CauldronHook.sol:1309 | CauldronHook.sol:1716, CauldronHook.sol:2015 |
| `relaunchAsset` (CauldronHook.sol:2524) | base units of the mapped ERC20 | CauldronHook.sol:1310 | CauldronHook.sol:1744 |
| `legacyBuffer` (CauldronHook.sol:318) | raw units of whatever `legacyBufferAsset` names; every write now stamps that field alongside the figure | CauldronHook.sol:1129, CauldronHook.sol:1178, CauldronHook.sol:1423, CauldronHook.sol:1441 | CauldronHook.sol:1046 (drained to the reserve), CauldronHook.sol:1103 |
| `legacyBufferAsset` (CauldronHook.sol:2542) | the address that denominates `legacyBuffer`; `address(0)` means native | CauldronHook.sol:1177, CauldronHook.sol:1422, CauldronHook.sol:1440 | never cleared independently of the buffer |
| `legacyOwedToReserve` (CauldronHook.sol:332) | units of the iteration token bought | CauldronHook.sol:1135 | CauldronHook.sol:1198 |
| `proposerOwed` (CauldronHook.sol:497) | native wei; credited only when the fee asset is native (CauldronHook.sol:1351) | CauldronHook.sol:1355 | CauldronHook.sol:2146 |
| `nftCredit` (CauldronHook.sol:367) | weighted volume credit, in whatever unit the volume ledger currently uses | CauldronHook.sol:895 (saturating) | CauldronHook.sol:2332 |
| `_volumeBuckets` (CauldronHook.sol:273) | uint128 of quote-raw or USD-at-1e18 volume | CauldronHook.sol:1572 (saturating at CauldronHook.sol:1573) | CauldronHook.sol:1557, CauldronHook.sol:1566 (wipes to zero) |
| `cumulativeVolume` (CauldronHook.sol:420) | same unit as the buckets | CauldronHook.sol:839 | never |
| `lifetimeVolumeOf` (CauldronHook.sol:417) | weighted volume | CauldronHook.sol:898 (saturating) | never |
| `totalLifetimeVolume` (CauldronHook.sol:418) | weighted volume | CauldronHook.sol:901 (saturating) | never |
| `outstandingCrystals` (CauldronHook.sol:409) | crystal count, global | CauldronHook.sol:2335 | CauldronHook.sol:2407 |
| `outstandingOf` (CauldronHook.sol:410) | crystal count, per collection | CauldronHook.sol:2336 | CauldronHook.sol:2408 |
| `pendingOf` (CauldronHook.sol:413) | crystal count, per player | CauldronHook.sol:2334 | CauldronHook.sol:2406 |
| `committedOf` (CauldronHook.sol:412) | crystal count, per player | CauldronHook.sol:2333 | never |
| `opened` (CauldronHook.sol:411) | creature count, per player | CauldronHook.sol:2411 | never |
| `missStreak` (CauldronHook.sol:414) | consecutive misses | CauldronHook.sol:2416 | CauldronHook.sol:2410 (reset to 0) |
| `batches` (CauldronHook.sol:407) | ticket batches | CauldronHook.sol:2339 (append only) | never; only `batchCursor` (CauldronHook.sol:2424) advances |

Value the hook holds that NO counter tracks: anything arriving through the bare `receive` (CauldronHook.sol:2544), which records nothing by design, and the ether/quote the pool manager credits at `take` (CauldronHook.sol:1519) between the take and the routing that disposes of it.

## B. Balance vs counter

- Three native counters are paid out of ONE undivided balance and none of them is ever compared against `address(this).balance`: `relaunchETH` at CauldronHook.sol:1718 and CauldronHook.sol:2016, `proposerOwed` at CauldronHook.sol:2147, and `legacyBuffer` spent as value through the delegatecalled settle at LegacyBuyLib.sol:138. A shortfall in one shows up as a failed send in whichever path runs first.
- `legacyOwedToReserve` IS reconciled: the sweep reads the live token balance at CauldronHook.sol:1196, clamps at CauldronHook.sol:1197 and debits only what moved at CauldronHook.sol:1198, so the counter cannot outrun the balance. The ERC20 return value IS now checked: the move goes through `FeeRouteLib.send` at CauldronHook.sol:1208 and a false answer reverts `SendFailed`, which rolls the debit back.
- `relaunchAsset` is the mirror image: the send's boolean IS required at CauldronHook.sol:1745, but the amount is never clamped to the live balance, so a token balance reduced elsewhere is not reflected in the counter.
- Known divergence points on the fee path: `_fundGuild` approves at FeeRouteLib.sol:147 and then calls `fundToken` at FeeRouteLib.sol:149; a pull that reports success but transfers less leaves tokens on the hook belonging to no counter, and the allowance is only cleared on the failure branch at FeeRouteLib.sol:151. `_deliver` has the same shape at FeeRouteLib.sol:173 and FeeRouteLib.sol:178.
- Crystal counters: pricing reads only the per-collection `outstandingOf` at CauldronHook.sol:2196 and CauldronHook.sol:2309, while `outstandingCrystals` at CauldronHook.sol:2238 is the global figure the public getter exposes. Resolution decrements both, keyed by the BATCH's stored collection at CauldronHook.sol:2394 rather than the live `collection` set at CauldronHook.sol:2043, so the two drift apart across a relaunch.
- `mintedOut` (CauldronHook.sol:2242) compares minted against maxSupply and ignores the reserved crystals counted at CauldronHook.sol:2309, so it can report not-minted-out while every remaining slot is already spoken for.

## C. Authority map

| gate | holder | rotatable? | where |
|---|---|---|---|
| `onlyOwner` | Ownable owner, set explicitly in the constructor (CauldronHook.sol:563) | yes — Ownable `transferOwnership`, and `renounceOwnership` is overridden to revert `RenounceDisabled` (CauldronHook.sol:1773), so the keys can be handed on but not dropped | CauldronHook.sol:1540, 1695, 1820, 1960, 1973, 1989, 1998, 2009, 2101, 2120, 2135, 2153, 2159, 2482, 2489, 2495 |
| `msg.sender != registry` | `registry` (CauldronHook.sol:256) | ONE-SHOT at CauldronHook.sol:1976; thereafter only through the announced pair CauldronHook.sol:1989 → CauldronHook.sol:2009 after `REGISTRY_SWAP_DELAY` (CauldronHook.sol:263) | CauldronHook.sol:1622, 1711, 1739, 1844, 1906, 2042, 2070, 2167 |
| `msg.sender != registry && msg.sender != owner()` | either | follows both of the above | CauldronHook.sol:1919, 1933, 1943, 1955, 2076, 2085, 2093, 2109, 2129, 2443, 2453 |
| adoption gate `require(sender == registry)` | `registry` | same slot as above; before it is set, NO pool can be adopted | CauldronHook.sol:631 |
| `msg.sender != legacyRegistry` | `legacyRegistry` (CauldronHook.sol:313) | freely, no delay, by owner OR registry at CauldronHook.sol:1921 | CauldronHook.sol:1194 |
| `!isOpener[msg.sender]` | any address flagged at CauldronHook.sol:2444 | freely, by owner or registry | CauldronHook.sol:2284 |
| `msg.sender != address(this)` | the hook itself | not rotatable | CauldronHook.sol:1100, CauldronHook.sol:2434 |
| `onlyPoolManager` | the v4 PoolManager, immutable from the periphery base | NOT rotatable (constructor-fixed at CauldronHook.sol:563) | BaseHook.sol:38, 51, 67, 85, 105, 128, 146, 167, 186, 205 |
| `nonReentrant` (not an authority gate) | — | — | CauldronHook.sol:2143, 2281, 2361, 2433 |

Ungated external surface: `fundLegacyBuffer` (CauldronHook.sol:1145), `claimProposerFees` (CauldronHook.sol:2143, self-balance only), `resolveTickets` (CauldronHook.sol:2359), `receive` (CauldronHook.sol:2544), and every view. `RoyaltyRouter.receive` (RoyaltyRouter.sol:44) is ungated and its `hook` target is immutable (RoyaltyRouter.sol:37). Every library entrypoint (FeeRouteLib.sol:48, 79, 190, 220; LegacyBuyLib.sol:73; SurtaxLib.sol:33) is ungated on its own account — the gate always sits on the hook side of the delegatecall.

Owner-or-registry slots that are written with NO validation, each of which redirects value or changes what traders pay: `legacyRegistry` (CauldronHook.sol:1921), `deathChecker` (CauldronHook.sol:1934), the three policies (CauldronHook.sol:1944-1863), `feeRouter` (CauldronHook.sol:1956), `nftContract` (CauldronHook.sol:1961), `collection` (CauldronHook.sol:2043), `vault` (CauldronHook.sol:2071), `quest` (CauldronHook.sol:2077), `seeder` (CauldronHook.sol:2086), `perpEngine` (CauldronHook.sol:2094), `guild` (CauldronHook.sol:2110), `activeProposer` (CauldronHook.sol:2130), `_liveKey` (CauldronHook.sol:1907), `quoteOracle` (CauldronHook.sol:1830).

## D. External calls, value and CEI ordering

| site | callee | value | gas | result | ordering |
|---|---|---|---|---|---|
| CauldronHook.sol:745 | `quoteOracle` raw `call` | none | unbounded | checked (CauldronHook.sol:748) | read-only for the hook; runs mid-swap, non-static so it can re-enter |
| CauldronHook.sol:908 | `quest` | none | UNBOUNDED — no cap, unlike the sibling best-effort calls | ignored | effects (CauldronHook.sol:895-900) first |
| CauldronHook.sol:949 | `perpEngine` sweep | none | `gasleft - LIQ_GAS_RESERVE`, floor `LIQ_GAS_MIN` (CauldronHook.sol:948) | ignored | after all volume/credit effects |
| CauldronHook.sol:966 | self → `nativeGachaStep` | none | `gg - GACHA_GAS_RESERVE`, floor `GACHA_GAS_MIN` (CauldronHook.sol:965) | ignored | after credit effects, before the fee take |
| CauldronHook.sol:1071 | self → `legacyBuyStep` | none | `gl - LEGACY_GAS_RESERVE`, floor `LEGACY_GAS_MIN` (CauldronHook.sol:1070) | ignored | fires twice per afterSwap (CauldronHook.sol:799, CauldronHook.sol:1002) |
| CauldronHook.sol:1088 | `seeder` poke | none | `g - SEED_POKE_GAS_RESERVE`, floor `SEED_POKE_GAS_MIN` (CauldronHook.sol:1087) | ignored | before any accounting |
| CauldronHook.sol:1124 | `LegacyBuyLib.buyStep` (delegatecall) | spends native or the quote, clamped to the balance above the reserve counter passed in at CauldronHook.sol:1124 | unbounded | reverts bubble (contained: the only caller is the result-ignored self-call) | buffer zeroed at CauldronHook.sol:1103 BEFORE; denomination re-checked at CauldronHook.sol:1118; credit at CauldronHook.sol:1135 AFTER |
| CauldronHook.sol:1196 / 1118 | `IERC20.balanceOf` / `transfer` | ERC20 out | unbounded | `transfer` return NOT checked | debit at CauldronHook.sol:1198 precedes the transfer |
| CauldronHook.sol:1372 | `IFeeRouter.route` | none | unbounded | try/catch, and discarded unless the parts sum exactly (CauldronHook.sol:1373) | before every send |
| CauldronHook.sol:1291 | `FeeRouteLib.routePerp` (delegatecall) | sends native or approves + is pulled | unbounded | returns undelivered amount | reserve credited AFTER, same expression |
| CauldronHook.sol:1456 | `FeeRouteLib.routeSplit` (delegatecall) | sends native or approves + is pulled | unbounded | returns undelivered amount | reserve credited AFTER at CauldronHook.sol:1455 |
| CauldronHook.sol:1532 | `FeeRouteLib.routeSplit` (delegatecall), surtax | sends native or approves + is pulled | unbounded | non-zero leftover re-routes at CauldronHook.sol:1533 | after the take at CauldronHook.sol:1519 |
| LegacyBuyLib.sol:97 | `poolManager.getSlot0` | none | unbounded | used for the buy's own sqrt-price bound at LegacyBuyLib.sol:98 | the fee path no longer reads live pool state at all: the surtax jitter's tick input was removed when the curve moved to SurtaxLib.sol:119 |
| CauldronHook.sol:1519 | `poolManager.take` | PULLS the fee into the hook | unbounded | reverts bubble | fee asset recorded at CauldronHook.sol:1518 first; routing after |
| CauldronHook.sol:1623 | `IPerpOpenCount.openCount` | none | unbounded | UNGUARDED — a revert blocks linking | before any write |
| CauldronHook.sol:1666 | `IDeathChecker.isDead` | none | unbounded | try/catch → built-in rule | view |
| CauldronHook.sol:1686 | `INFTContract.getHolderTaxRate` | none | UNBOUNDED, on every fee | try/catch → default bps | before the take |
| CauldronHook.sol:1718 | `registry.call{value}` | native out, whole reserve | unbounded | required (CauldronHook.sol:1719) | counter zeroed at CauldronHook.sol:1716 first — CEI clean |
| CauldronHook.sol:1745 | `FeeRouteLib.send` (delegatecall) | ERC20 out | gasCap 0 = unbounded | required (CauldronHook.sol:1745) | counter zeroed at CauldronHook.sol:1744 first — CEI clean |
| CauldronHook.sol:1848 / 1791 | `IPerpForceClose.forceCloseAllDead` / `openCount` | none | unbounded | first try/catch, second UNGUARDED and reverting | transient flag raised/lowered around the first |
| CauldronHook.sol:2016 | `registry.call{value}` | native out, whole reserve | unbounded | required (CauldronHook.sol:2017) | counter zeroed at CauldronHook.sol:2015 first — CEI clean |
| CauldronHook.sol:2048 | `ICauldronCollection.totalMinted` | none | unbounded | UNGUARDED | before the epoch bump |
| CauldronHook.sol:2065 | `ICollectionLiquidator.setLiquidatorMinter` | none | unbounded | try/catch | last |
| CauldronHook.sol:2147 | `msg.sender.call{value}` | native out | unbounded | required (CauldronHook.sol:2148) | balance zeroed at CauldronHook.sol:2146 first + `nonReentrant` — CEI clean |
| CauldronHook.sol:2177 | `ICurvePolicy.priceAt` | none | unbounded, ONCE PER CRYSTAL | try/catch, zero rejected | view |
| CauldronHook.sol:2195 / 2161 / 2162 / 2222 / 2223 / 2313 / 2314 | `totalMinted` / `maxSupply` | none | unbounded | UNGUARDED | reads |
| CauldronHook.sol:2226 | `IOddsPolicy.oddsBps` | none | unbounded | try/catch, clamped | view |
| CauldronHook.sol:2412 | `ICauldronCollection.mint` | none | unbounded | reverts bubble | three counters decremented at CauldronHook.sol:2406-2325 and `opened` at CauldronHook.sol:2411 BEFORE the mint |
| LegacyBuyLib.sol:100 / 89 / 91 / 92 / 93 / 97 | `poolManager.swap` / `settle{value}` / `sync` / `IERC20.transfer` / `settle` / `take` | settles the realised debit `spent` (LegacyBuyLib.sol:115) | unbounded | reverts bubble | nested under the parent swap's unlock |
| RoyaltyRouter.sol:45 | `ILegacyBuffer.fundLegacyBuffer{value}` | forwards the whole `msg.value` | unbounded | UNGUARDED — a failure reverts the royalty payment | only statement |
| FeeRouteLib.sol:106 / 129 / 142 / 168 / 169 / 201 | native `call{value}` | native out | unbounded except FeeRouteLib.sol:197 | captured, never bubbled | caller books the leftover |
| FeeRouteLib.sol:107 / 130 / 132 / 134 / 145 / 147 / 150 / 175 / 204 / 208 / 211 | ERC20 `transfer` / `approve` / pull | ERC20 out | unbounded | captured; `transfer` return decoded at FeeRouteLib.sol:110 and FeeRouteLib.sol:206 | approve-then-pull; allowance cleared only on failure |

## E. Loops

| loop | bound | who grows the bound |
|---|---|---|
| CauldronHook.sol:1556 (full bucket wipe) | `HOURS_PER_DAY` = 24 (CauldronHook.sol:195) | nobody — constant |
| CauldronHook.sol:1565 (partial bucket wipe) | `steps`, clamped to 24 at CauldronHook.sol:1563 | nobody |
| CauldronHook.sol:1586 (24h sum) | 24, fixed array length | nobody |
| CauldronHook.sol:1643 (sibling duplicate scan) | `MAX_SIBLINGS` = 9 (CauldronHook.sol:770) | the registry, one push per call at CauldronHook.sol:1646 |
| CauldronHook.sol:1661 (death sum over siblings) | same 9; EACH iteration is a full 24-bucket sum | the registry, via CauldronHook.sol:1621 |
| CauldronHook.sol:2205 (`crystalsReady`) | `MAX_MINTS_PER_CALL` = 30 (CauldronHook.sol:389); each iteration may make an external policy call | nobody |
| CauldronHook.sol:2217 (`costOfNextCrystals`) | UNBOUNDED — the caller's `count` | any caller; it is a view, so the cost lands on the querying node |
| CauldronHook.sol:2261 (`progress`) | 30, as above | nobody |
| CauldronHook.sol:2320 (commit affordability) | min(caller's maxCount, 30) | nobody; the native path passes `NATIVE_COMMIT_MAX` = 4 (CauldronHook.sol:173) |
| CauldronHook.sol:2377 (resolve, outer over batches) | caller's `maxCount`; the batch array itself grows without bound at CauldronHook.sol:2339 | every committer; the cursor only moves forward at CauldronHook.sol:2424 |
| CauldronHook.sol:2401 (resolve, inner over a batch) | caller's `maxCount` and `Batch.count` (uint16) | the committer, capped at 30 per commit |
| HookMiner.sol:32 (salt search) | `MAX_LOOP` = 160_444 (HookMiner.sol:14) | nobody — constant; view-only |

## F. Denomination and units

- The fee is taken on whichever side the pool recorded as the quote: the currency is chosen at CauldronHook.sol:1517 from stored `quoteIsCurrency0`, stamped into the transient fee-asset field at CauldronHook.sol:1518, and pulled at CauldronHook.sol:1519. Every downstream send reads that transient field.
- `_creditFor` (CauldronHook.sol:1307) is the single denomination switch for residuals: native goes to CauldronHook.sol:1309, anything else to CauldronHook.sol:1310. `_creditReserve` (CauldronHook.sol:1303) is now just the wrapper that supplies the CURRENT fee asset; the stale-buffer drain at CauldronHook.sol:1050 supplies `legacyBufferAsset` instead, which is how a buffer left over from a rotated quote reaches the right counter.
- The proposer slice is NATIVE-ONLY by construction at CauldronHook.sol:1351 and is paid out as raw wei at CauldronHook.sol:2147.
- The legacy-buffer carve matches the fee asset against the live pool's currency0 at CauldronHook.sol:1413, but the no-vault floor fold immediately below tests native-only at CauldronHook.sol:1438; the two rules differ once a generation is quoted in an ERC20.
- The floor vault only receives a NATIVE share: a non-native floor share is folded into the per-asset reserve at CauldronHook.sol:1444-1350.
- Volume units: raw quote units when no oracle is wired (CauldronHook.sol:744), otherwise USD at 1e18 via the multiply-then-divide at CauldronHook.sol:750. A zero factor means `cannot judge` and nothing is recorded (CauldronHook.sol:837).
- There is NO `decimals()` read anywhere in this cluster. The entire scale conversion is whatever `cachedUsdPerRawUnit` (CauldronHook.sol:746) returns, so a 6-decimal and an 18-decimal quote are distinguished only by the oracle's factor.
- Wiring the oracle forcibly restates the volume-denominated constants in the same call: `deathThreshold` (CauldronHook.sol:1827), `volumePerNFT` (CauldronHook.sol:1831), `nftPriceStep` (CauldronHook.sol:1832), `oddsFullVolumeWei` (CauldronHook.sol:1833). `buyWeightBps`/`sellWeightBps` (CauldronHook.sol:889) are ratios and unit-free.
- Bps denominator `BPS` = 10_000 (CauldronHook.sol:149), used at CauldronHook.sol:889, 1287, 1353, 1381, 1383, 1416, 1502, 1508 and in DefaultFeeRouter.sol:26 / DefaultFeeRouter.sol:28. The gacha roll uses a separate literal 10_000 modulus at CauldronHook.sol:2402; the odds ratio divides by `oddsFullVolumeWei` at CauldronHook.sol:2232.
- Narrowing casts: bucket to uint128 with explicit saturation at CauldronHook.sol:1573; odds and count to uint16 at CauldronHook.sol:2338 and CauldronHook.sol:2344 with a guard at CauldronHook.sol:2330; resolved to uint16 at CauldronHook.sol:2421; block number to uint48 at CauldronHook.sol:2342 and CauldronHook.sol:2389; fee to int128 at CauldronHook.sol:1003 and int256→int128 at CauldronHook.sol:1271.
- ReserveLib is tick/liquidity math in v4 units only; its orientation assumption (quote at currency0, token at currency1) is stated at ReserveLib.sol:17 and used at ReserveLib.sol:55.

## G. `unchecked` blocks and rounding direction

| block | what it covers | why it cannot wrap, or what happens if it does |
|---|---|---|
| CauldronHook.sol:892-901 | three credit adds | explicit SATURATION, not wrapping: each add compares against its input at CauldronHook.sol:895, CauldronHook.sol:898, CauldronHook.sol:901 and pins to `type(uint256).max` |
| CauldronHook.sol:1129 | `legacyBuffer += amt - spent` | guarded by `spent < amt` on the same line |
| CauldronHook.sol:1583-1528 | 24-bucket sum | 24 × 2^128 cannot overflow uint256; the bound is the fixed array length |
| CauldronHook.sol:2217 | `++i` only | loop counter |
| CauldronHook.sol:2324 | `n++` | bounded by 30 |
| CauldronHook.sol:2413 | `minted++`, `won++` | local counters bounded by the batch |
| CauldronHook.sol:2419 | `r++`, `processed++` | bounded by `maxCount` and `Batch.count` |
| CauldronHook.sol:2422 | `bi++` | bounded by `batches.length` |

Rounding: every bps split is FLOOR division (CauldronHook.sol:889, 1287, 1353, 1381, 1383, 1416, 1502, 1508, 2232; DefaultFeeRouter.sol:26, DefaultFeeRouter.sol:28), and in every case the complement is taken by SUBTRACTION so the parts sum exactly — CauldronHook.sol:1288, CauldronHook.sol:1382, CauldronHook.sol:1384, CauldronHook.sol:1509, DefaultFeeRouter.sol:29. `_toUsd` multiplies before dividing by 1e18 and rounds DOWN at CauldronHook.sol:750. ReserveLib rounds DOWN in both directions (ReserveLib.sol:80 and the `mulDiv` at ReserveLib.sol:105), and its tick alignment rounds toward minus infinity at ReserveLib.sol:29 and toward plus infinity at ReserveLib.sol:36. Dust from a floor division is never lost: it lands in the subtraction complement, which is always the relaunch reserve or the staker share.

## H. Comment-vs-code observations

1. **ILegacyNote (declared in CauldronHook.sol) L66** — comment at `registry` (CauldronHook.sol:64) says this is the registry entry that records a legacy buyback against the live collection's pending entitlement; code never calls `noteLegacyBuy` (CauldronHook.sol:67) and instead accrues `legacyOwedToReserve` (CauldronHook.sol:1135) for a later registry-pulled sweep
2. **CauldronHook L556** — comment at `stability` (CauldronHook.sol:240) says the treasury slot is a dead slot read by nothing and kept only for layout stability; code at `treasury` (CauldronHook.sol:566) still writes it from a constructor parameter
3. **CauldronHook L572** — comment at `afterSwapReturnDelta` (CauldronHook.sol:115) says the hook's permissions are afterInitialize, afterSwap and afterSwapReturnDelta; code additionally enables `beforeSwap` (CauldronHook.sol:586) and `beforeSwapReturnDelta` (CauldronHook.sol:590), which is what lets the buy-leg fee be skimmed before the swap
4. **CauldronHook L741** — comment at `oracles` (CauldronHook.sol:100) says the 24h volume is fully computed inside afterSwap with no oracles; code at `quoteOracle` (CauldronHook.sol:743) makes a state-changing external oracle call from inside that same callback whenever the slot is wired
5. **CauldronHook L778** — comment at `liqHint` (CauldronHook.sol:924) says the swap must carry a liquidation hint in hookData and the engine is fired at the hinted position; code at `sweepLiquidations` (CauldronHook.sol:950) passes no hint at all and calls a bounded rotating sweep instead
6. **CauldronHook L778** — comment at `liquidateInSwap` (CauldronHook.sol:930) names `liquidateInSwap` as the function whose gas is being reserved; code at `perpEngine` (CauldronHook.sol:949) calls `sweepLiquidations` (CauldronHook.sol:950)
7. **CauldronHook L778** — comment at `GACHA_GAS_RESERVE` (CauldronHook.sol:959) says the native gacha self-call keeps a reserve for fee collection and the return; code at `gg` (CauldronHook.sol:965) compares remaining gas against the MIN constant but subtracts the RESERVE constant at `GACHA_GAS_RESERVE` (CauldronHook.sol:966), so the two constants are not compared against each other the way the sibling perp gate does at `LIQ_GAS_RESERVE` (CauldronHook.sol:948)
8. **CauldronHook L1128** — comment at `unspecifiedIsEth` (CauldronHook.sol:1235) says the afterSwap side early-returns because its `unspecifiedIsEth` test is false; code names that variable `unspecifiedIsCurrency0` (CauldronHook.sol:986) and compares it against the recorded quote side rather than against ether
9. **CauldronHook L1128** — comment at `deltas` (CauldronHook.sol:104) says the hook collects its tiered fees via afterSwap return deltas; code charges the buy leg here instead, returning a BeforeSwapDelta built at `toBeforeSwapDelta` (CauldronHook.sol:1271)
10. **CauldronHook L1313** — code at `_feeAsset` (CauldronHook.sol:1438) folds a no-vault floor share into the buffer only when the fee asset is native, while the carve above it at `_feeAsset` (CauldronHook.sol:1413) compares the fee asset to the live key's currency0; the two buffer entries therefore apply different denomination rules once a generation is quoted in an ERC20, and only the second one also stamps `legacyBufferAsset` (CauldronHook.sol:1440) (DERIVED)
11. **CauldronHook L1220** — comment at `feeRouter` (CauldronHook.sol:694) points the reader at a line number for the re-entrant fee router; code has `feeRouter` (CauldronHook.sol:1370) as the actual read site, and the cited line is a comment
12. **CauldronHook L1562** — comment at `treasury` (CauldronHook.sol:1639) says seven pools is already a wide treasury and the cap is headroom above that; code sets `MAX_SIBLINGS` (CauldronHook.sol:770) to nine
13. **LegacyBuyLib L73** — the sqrt-price bound is a fraction of the LIVE price read in the same call at `getSlot0` (LegacyBuyLib.sol:97), so it bounds only the move this buy itself causes and not the price the buy starts from (DERIVED); the comment at `SLIP_SQRT_BPS` (LegacyBuyLib.sol:47) describes the constant as ~0.8998 of the price while it is applied to the sqrt price at `lim` (LegacyBuyLib.sol:98)
14. **CauldronHook L1466** — comment at `prevrandao` (CauldronHook.sol:1463) says the jitter means there is no cleanly-predictable cheap block to schedule an entry into; the library that now computes it states the opposite at `snipeSurtaxBps` (SurtaxLib.sol:70) — because the getter is public view, a sniper can read the block's draw and retry in the next block — and the floor the code does guarantee is the deterministic decay at `total` (SurtaxLib.sol:125)
15. **RoyaltyRouter L44** — comment at `relaunchETH` (RoyaltyRouter.sol:30) now states that a payment the buffer cannot take is rerouted rather than refused and that this contract's balance returns to zero in the same call; code at `fundLegacyBuffer` (RoyaltyRouter.sol:45) forwards the whole `msg.value` unguarded and the callee has no revert path left, at `msg` (CauldronHook.sol:1171) and `relaunchETH` (CauldronHook.sol:1174), so the earlier contradiction is gone; what remains is that the forward is still unguarded, so any future revert inside the hook would revert the royalty payment with it (DERIVED)

## I. Function inventory

| contract | line | function | authority | value effect |
|---|---:|---|---|---|
| IRegistryQuotes (declared in CauldronHook.sol) | 33 | `function allowedQuote(address quote) external view returns (bool)` | interface declaration (no body in this cluster) | NONE |
| IQuoteOracle (declared in CauldronHook.sol) | 43 | `function cachedUsdPerRawUnit(address quote) external returns (uint256)` | interface declaration (no body in this cluster) | NONE |
| IPerpOpenCount (declared in CauldronHook.sol) | 50 | `function openCount() external view returns (uint256)` | interface declaration (no body in this cluster) | NONE |
| IPerpEngineLiq (declared in CauldronHook.sol) | 54 | `function liquidateInSwap(uint256 id, address liquidator) external` | interface declaration (no body in this cluster) | NONE |
| IPerpEngineLiq (declared in CauldronHook.sol) | 55 | `function liquidateManyInSwap(uint256[] calldata ids, address liquidator) external` | interface declaration (no body in this cluster) | NONE |
| IPerpEngineLiq (declared in CauldronHook.sol) | 56 | `function sweepLiquidations(address liquidator) external` | interface declaration (no body in this cluster) | NONE |
| ICollectionLiquidator (declared in CauldronHook.sol) | 61 | `function setLiquidatorMinter(address minter) external` | interface declaration (no body in this cluster) | NONE |
| ILegacyNote (declared in CauldronHook.sol) | 67 | `function noteLegacyBuy(uint256 tokensBought) external` | interface declaration (no body in this cluster) | NONE |
| IPerpForceClose (declared in CauldronHook.sol) | 72 | `function forceCloseAllDead() external` | interface declaration (no body in this cluster) | NONE |
| IPerpForceClose (declared in CauldronHook.sol) | 73 | `function openCount() external view returns (uint256)` | interface declaration (no body in this cluster) | NONE |
| IPerpFeeCredit (declared in CauldronHook.sol) | 79 | `function creditPerpFee() external payable` | interface declaration (no body in this cluster) | NONE |
| IPerpFeeCredit (declared in CauldronHook.sol) | 80 | `function creditPerpFeeToken() external payable` | interface declaration (no body in this cluster) | NONE |
| IPerpFeeCredit (declared in CauldronHook.sol) | 83 | `function creditPerpFeeAsset(address asset, uint256 amount) external` | interface declaration (no body in this cluster) | NONE |
| ISeederInSwap (declared in CauldronHook.sol) | 90 | `function pokeInSwap() external` | interface declaration (no body in this cluster) | NONE |
| CauldronHook | 557 | `constructor( IPoolManager _poolManager, uint256 _deathThreshold, address _nftContract, ad...` | deployer | NONE |
| CauldronHook | 573 | `function getHookPermissions() public pure override returns (Hooks.Permissions memory)` | anyone | NONE |
| CauldronHook | 622 | `function _afterInitialize( address sender, PoolKey calldata key, uint160, int24 ) interna...` | poolManager (and, inside it, only the registry may be the initializer) | NONE |
| CauldronHook | 742 | `function _toUsd(address quote, uint256 raw) internal returns (uint256)` | internal (callers: CauldronHook._afterSwap) | NONE |
| CauldronHook | 779 | `function _afterSwap( address sender, PoolKey calldata key, SwapParams calldata params, Ba...` | poolManager | NONE directly; it returns a positive int128 fee at `fee` (line 1003) which the pool manager takes out of th... |
| CauldronHook | 1016 | `function _maybeLegacyBuyback(PoolId id, PoolKey calldata key) private` | internal (callers: CauldronHook._afterSwap) | NONE here; the gas-capped self `call` (line 1071) is what spends the buffer, and the drain branch only move... |
| CauldronHook | 1083 | `function _maybePoke() private` | internal (callers: CauldronHook._afterSwap) | NONE |
| CauldronHook | 1099 | `function legacyBuyStep(PoolKey calldata key) external` | hook itself (self-call only) | spends native or the ERC20 quote out of the hook through the delegatecalled `buyStep` (line 1124) |
| CauldronHook | 1145 | `function fundLegacyBuffer() external payable` | anyone | receives native; it is credited to `legacyBuffer` (line 1178) when the live generation is ether-quoted and ... |
| CauldronHook | 1193 | `function sweepLegacyReserve(address token, address to) external returns (uint256 amt)` | legacyRegistry | transfers `token` to the caller-supplied recipient through the delegatecalled `send` (line 1208) |
| CauldronHook | 1218 | `function _beforeSwap( address sender, PoolKey calldata key, SwapParams calldata params, b...` | poolManager | NONE directly; the returned BeforeSwapDelta at `toBeforeSwapDelta` (line 1271) makes the manager credit the... |
| CauldronHook | 1286 | `function _routePerpFee(uint256 amount, bool isBuy) private` | internal (callers: CauldronHook._takeEthFee) | no direct transfer; the guild and staker shares leave through the delegatecalled `routePerp` (line 1291) |
| CauldronHook | 1303 | `function _creditReserve(uint256 amount) private` | internal (callers: CauldronHook._routePerpFee, CauldronHook._routeEthFe... | NONE |
| CauldronHook | 1307 | `function _creditFor(address a, uint256 amount) private` | internal (callers: CauldronHook._creditReserve, CauldronHook._maybeLega... | NONE; it only moves a figure between the two reserve counters |
| CauldronHook | 1313 | `function _routeEthFee(uint256 feeAmount) private` | internal (callers: CauldronHook._takeEthFee) | no direct transfer; the guild and floor shares leave through the delegatecalled `routeSplit` (line 1456) an... |
| CauldronHook | 1466 | `function snipeSurtaxBps(PoolId id) public view returns (uint256)` | anyone | NONE |
| CauldronHook | 1485 | `function _takeEthFee( PoolId id, PoolKey calldata key, address sender, bytes calldata hoo...` | internal (callers: CauldronHook._beforeSwap, CauldronHook._afterSwap) | pulls `total` (line 1519) of the quote currency out of the pool manager into this hook |
| CauldronHook | 1540 | `function setSnipeParams(uint256 windowBlocks, uint256 maxBps) external onlyOwner` | owner | NONE |
| CauldronHook | 1550 | `function _recordVolume(PoolId id, uint256 amount) private` | internal (callers: CauldronHook._afterSwap) | NONE |
| CauldronHook | 1580 | `function getVolume24h(PoolId id) public view returns (uint256 total)` | anyone | NONE |
| CauldronHook | 1621 | `function linkVolume(PoolId primary, PoolId secondary) external` | registry | NONE |
| CauldronHook | 1653 | `function isDead(PoolId id) external view returns (bool)` | anyone | NONE |
| CauldronHook | 1675 | `function _getCurrentBucket() private view returns (uint256)` | internal (callers: CauldronHook._recordVolume) | NONE |
| CauldronHook | 1683 | `function _getHolderTaxRate(address holder) private view returns (uint256)` | internal (callers: CauldronHook._takeEthFee) | NONE |
| CauldronHook | 1695 | `function setDefaultTaxBps(uint256 _bps) external onlyOwner` | owner | NONE |
| CauldronHook | 1710 | `function releaseRelaunchETH() external returns (uint256 amount)` | registry | sends native to `registry` (line 1718) |
| CauldronHook | 1738 | `function releaseRelaunchAsset(address asset) external returns (uint256 amount)` | registry | ERC20 transfer of `asset` to `registry` (line 1745) |
| CauldronHook | 1772 | `function renounceOwnership() public view override onlyOwner` | owner only, and it reverts for the owner too | NONE |
| CauldronHook | 1820 | `function setDeathThreshold( uint256 _threshold, address _oracle, uint256 _volumePerNFT, u...` | owner | NONE |
| CauldronHook | 1843 | `function forceClosePerps() external` | registry | NONE |
| CauldronHook | 1905 | `function setLiveKey(PoolKey calldata k) external` | registry | NONE |
| CauldronHook | 1911 | `function liveKey() external view returns (PoolKey memory)` | anyone | NONE |
| CauldronHook | 1918 | `function setLegacyBuyback(address registry_, uint256 bps, uint256 threshold) external` | owner or registry | NONE |
| CauldronHook | 1932 | `function setDeathChecker(address _checker) external` | owner or registry | NONE |
| CauldronHook | 1942 | `function setPolicies(address _surtax, address _odds, address _curve) external` | owner or registry | NONE |
| CauldronHook | 1954 | `function setFeeRouter(address _router) external` | owner or registry | NONE |
| CauldronHook | 1960 | `function setNftContract(address _nft) external onlyOwner` | owner | NONE |
| CauldronHook | 1973 | `function setRegistry(address _registry) external onlyOwner` | owner | NONE |
| CauldronHook | 1989 | `function proposeRegistryOverride(address _registry) external onlyOwner` | owner | NONE |
| CauldronHook | 1998 | `function cancelRegistryOverride() external onlyOwner` | owner | NONE |
| CauldronHook | 2009 | `function executeRegistryOverride() external onlyOwner` | owner | sends native to the OUTGOING `registry` (line 2016) |
| CauldronHook | 2041 | `function setCollection(address _collection) external` | registry | NONE |
| CauldronHook | 2063 | `function _wireLiquidator(address _collection) private` | internal (callers: CauldronHook.setCollection, CauldronHook.setPerpEngi... | NONE |
| CauldronHook | 2069 | `function setVault(address _vault) external` | registry | NONE |
| CauldronHook | 2075 | `function setQuest(address _quest) external` | owner or registry | NONE |
| CauldronHook | 2084 | `function setSeeder(address _seeder) external` | owner or registry | NONE |
| CauldronHook | 2092 | `function setPerpEngine(address _engine) external` | owner or registry | NONE |
| CauldronHook | 2101 | `function setFloorBps(uint256 _bps) external onlyOwner` | owner | NONE |
| CauldronHook | 2108 | `function setGuild(address _guild) external` | owner or registry | NONE |
| CauldronHook | 2120 | `function setGuildBps(uint256 _bps) external onlyOwner` | owner | NONE |
| CauldronHook | 2128 | `function setActiveProposer(address who) external` | owner or registry | NONE |
| CauldronHook | 2135 | `function setProposerBps(uint256 _bps) external onlyOwner` | owner | NONE |
| CauldronHook | 2143 | `function claimProposerFees() external nonReentrant returns (uint256 amount)` | anyone (each caller can only claim their own accrued balance) | sends native to the caller via `call` (line 2147) |
| CauldronHook | 2153 | `function setNftCurve(uint256 _base, uint256 _step) external onlyOwner` | owner | NONE |
| CauldronHook | 2159 | `function setCreditUntaggedSwaps(bool on) external onlyOwner` | owner | NONE |
| CauldronHook | 2166 | `function setNftCurveFrom(uint256 _base) external` | registry | NONE |
| CauldronHook | 2174 | `function nftPriceAt(uint256 k) public view returns (uint256)` | anyone | NONE |
| CauldronHook | 2186 | `function creditOf(address player) external view returns (uint256)` | anyone | NONE |
| CauldronHook | 2194 | `function _curvePos() internal view returns (uint256)` | internal (callers: CauldronHook.crystalsReady, CauldronHook.costOfNextC... | NONE |
| CauldronHook | 2200 | `function crystalsReady(address player) public view returns (uint256 ready)` | anyone | NONE |
| CauldronHook | 2214 | `function costOfNextCrystals(uint256 count) public view returns (uint256 cost)` | anyone | NONE |
| CauldronHook | 2223 | `function oddsForPlay(uint256 playWei) public view returns (uint256 bps)` | anyone | NONE |
| CauldronHook | 2237 | `function outstandingTickets() external view returns (uint256)` | anyone | NONE |
| CauldronHook | 2242 | `function mintedOut() external view returns (bool)` | anyone | NONE |
| CauldronHook | 2252 | `function progress(address player) external view returns (uint256 inCurrent, uint256 thres...` | anyone | NONE |
| CauldronHook | 2279 | `function commitCrystals(address player, uint256 maxCount, uint256 playWei) external nonRe...` | opener (an address flagged in isOpener) | NONE |
| CauldronHook | 2299 | `function _commitCrystals(address player, uint256 maxCount, uint256 playWei) internal retu...` | internal (callers: CauldronHook.commitCrystals, CauldronHook.nativeGach... | NONE |
| CauldronHook | 2359 | `function resolveTickets(uint256 maxCount) public nonReentrant returns (uint256 processed,...` | anyone | NONE |
| CauldronHook | 2371 | `function _resolveTickets(uint256 maxCount) internal returns (uint256 processed, uint256 w...` | internal (callers: CauldronHook.resolveTickets, CauldronHook.nativeGach... | NONE |
| CauldronHook | 2433 | `function nativeGachaStep(address player, uint256 playWei) external nonReentrant` | hook itself (self-call only) | NONE |
| CauldronHook | 2442 | `function setOpener(address who, bool allowed) external` | owner or registry | NONE |
| CauldronHook | 2452 | `function setTaxExempt(address who, bool exempt) external` | owner or registry | NONE |
| CauldronHook | 2466 | `function _isExemptPlayer(address sender, bytes calldata hookData) private view returns (b...` | internal (callers: CauldronHook._beforeSwap, CauldronHook._afterSwap) | NONE |
| CauldronHook | 2474 | `function _taxedPlayer(address sender, bytes calldata hookData) private view returns (addr...` | internal (callers: CauldronHook._isExemptPlayer, CauldronHook._takeEthF... | NONE |
| CauldronHook | 2482 | `function setOddsParams(uint256 fullVolumeWei, uint256 pity) external onlyOwner` | owner | NONE |
| CauldronHook | 2489 | `function setMaxOdds(uint256 bps) external onlyOwner` | owner | NONE |
| CauldronHook | 2495 | `function setWeights(uint256 buyBps, uint256 sellBps) external onlyOwner` | owner | NONE |
| CauldronHook | 2544 | `receive() external payable` | anyone | receives native via `receive` (line 2544) |
| DefaultFeeRouter | 21 | `function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256...` | anyone | NONE |
| FeeRouteLib | 48 | `function routeSplit( address asset, address guild, address vault, uint256 toGuild, uint25...` | internal to the hook via delegatecall (callers: CauldronHook._routeEthF... | no direct transfer; value leaves through `_fundGuild` (FeeRouteLib.sol:64) and `_move` (FeeRouteLib.sol:68) |
| FeeRouteLib | 79 | `function routePerp( address asset, address guild, address engine, uint256 toGuild, uint25...` | internal to the hook via delegatecall (caller: CauldronHook._routePerpF... | no direct transfer; value leaves through `_fundGuild` (FeeRouteLib.sol:97) and `_deliver` (FeeRouteLib.sol:... |
| FeeRouteLib | 105 | `function _move(address asset, address to, uint256 amount) private returns (bool ok)` | internal (callers: FeeRouteLib.routeSplit) | sends native to the recipient `to` (line 106); ERC20 transfer encoded against `asset` (line 107) |
| FeeRouteLib | 128 | `function _fundGuild(address asset, address guild, uint256 amount) private returns (bool o...` | internal (callers: FeeRouteLib.routeSplit, FeeRouteLib.routePerp) | sends native to the guild at `guild` (line 146); ERC20 approve of `asset` (line 147) then a pull by `guild`... |
| FeeRouteLib | 154 | `function _deliver(address asset, address to, uint256 amount, bytes4 nativeSel, bytes4 ass...` | internal (callers: FeeRouteLib.routePerp) | sends native to the engine at `to` (line 170); ERC20 approve of `asset` (line 173) then a pull by `to` (lin... |
| FeeRouteLib | 190 | `function send(address asset, address to, uint256 amount, uint256 gasCap) external returns...` | internal to the hook via delegatecall (caller: CauldronHook.releaseRela... | sends native to `to` (line 196); sends native with a gas cap to `to` (line 197); ERC20 transfer encoded aga... |
| FeeRouteLib | 220 | `function deliver( address asset, address to, uint256 amount, bytes4 nativeSelector, bytes...` | internal to the hook via delegatecall; NO caller anywhere in the source... | sends native to `to` (line 240); ERC20 approve of `asset` (line 243) then a pull by `to` (line 247) |
| LegacyBuyLib | 73 | `function buyStep(IPoolManager poolManager, PoolKey calldata key, uint256 amt, uint256 enc...` | anyone in principle (a linked library address with no state and no fund... | sends native to `poolManager` (LegacyBuyLib.sol:138); or transfers the ERC20 quote to the pool manager at `... |
| ReserveLib | 27 | `function _alignDown(int24 tick, int24 spacing) internal pure returns (int24)` | internal (callers: ReserveLib.reserveTicks) | NONE |
| ReserveLib | 34 | `function _alignUp(int24 tick, int24 spacing) internal pure returns (int24)` | internal (callers: ReserveLib.reserveTicks) | NONE |
| ReserveLib | 50 | `function reserveTicks(int24 launchTick, int24 spacing, int24 offset) internal pure return...` | internal (callers: out-of-cluster PoolOps) | NONE |
| ReserveLib | 75 | `function liquidityForTokenOut(int24 tickLower, int24 tickUpper, uint256 amount1) internal...` | internal (callers: out-of-cluster PoolOps) | NONE |
| ReserveLib | 96 | `function tokenOutForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity) intern...` | internal (callers: out-of-cluster PoolOps) | NONE |
| ILegacyBuffer (declared in RoyaltyRouter.sol) | 5 | `function fundLegacyBuffer() external payable` | interface declaration (no body in this cluster) | NONE |
| RoyaltyRouter | 39 | `constructor(address _hook)` | deployer | NONE |
| RoyaltyRouter | 44 | `receive() external payable` | anyone (any address that sends ether here) | receives native, gated on `value` (line 45); sends native to `hook` (line 45) |
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

- `_afterSwap` is handed the manager's computed `BalanceDelta` at CauldronHook.sol:783. It reads the quote leg TWICE: CauldronHook.sol:812 for the volume figure and CauldronHook.sol:996 for the sell-leg fee base. Which side is read is decided by the STORED `quoteIsCurrency0` (CauldronHook.sol:795), not by inspecting the key — so the adoption-time answer governs every later swap.
  Derived from CauldronHook.sol:812: the USD/raw conversion (CauldronHook.sol:836), the bucket write (CauldronHook.sol:1572), `cumulativeVolume` (CauldronHook.sol:839), the weighted credit (CauldronHook.sol:889) and therefore `nftCredit`, `lifetimeVolumeOf`, `totalLifetimeVolume`, and the in-swap gacha play size (CauldronHook.sol:916).
  Derived from CauldronHook.sol:996: `ethAmount` and hence the whole sell-leg fee (CauldronHook.sol:1001).
- The surtax curve no longer reads pool state at all, and no longer lives in this cluster: `snipeSurtaxBps` (CauldronHook.sol:1466) reads its inputs and calls the linked library at CauldronHook.sol:1472. The jitter seed is the previous blockhash, the pool id, the block number and `prevrandao` at SurtaxLib.sol:121 — per-BLOCK, not per-call — added to the linear decay at SurtaxLib.sol:125. The old `getSlot0` tick input, which a probe swap in the same transaction could steer, is gone. This still runs on the fee path of EVERY swap via CauldronHook.sol:1500.
- `_takeEthFee` performs the only state-changing manager call on the ordinary path: `poolManager.take(feeCur, address(this), total)` at CauldronHook.sol:1519, which is what actually moves the fee into the hook.
- `_beforeSwap` reads NO pool state. Everything it decides comes from `params` (CauldronHook.sol:1231, CauldronHook.sol:1251) and from storage (CauldronHook.sol:1228, CauldronHook.sol:1230).
- The nested buyback, running under the parent swap's unlock, reads and writes live pool state directly: `poolManager.swap` at LegacyBuyLib.sol:100, the realised debit at LegacyBuyLib.sol:115, `settle{value}` at LegacyBuyLib.sol:138, `sync` at LegacyBuyLib.sol:140, `settle` at LegacyBuyLib.sol:149, the credit amount at LegacyBuyLib.sol:132 and `take` at LegacyBuyLib.sol:152. It also reads the live sqrt price at LegacyBuyLib.sol:97 to bound its own price move at LegacyBuyLib.sol:105.
- Not read anywhere in the cluster: pool liquidity, tick bitmap, fee growth, or any TWAP. The only price-sensitive input left is the sqrt price the nested buyback reads at LegacyBuyLib.sol:97, and it is used only as that buy's own limit.

### J2. Hook permission bits

Declared once, in `getHookPermissions` (CauldronHook.sol:573), and enforced against the deployed address by `validateHookAddress` (BaseHook.sol:31) during construction.

| bit | value | line |
|---|---|---:|
| `beforeInitialize` | false | CauldronHook.sol:580 |
| `afterInitialize` | TRUE | CauldronHook.sol:581 |
| `beforeAddLiquidity` | false | CauldronHook.sol:582 |
| `afterAddLiquidity` | false | CauldronHook.sol:583 |
| `beforeRemoveLiquidity` | false | CauldronHook.sol:584 |
| `afterRemoveLiquidity` | false | CauldronHook.sol:585 |
| `beforeSwap` | TRUE | CauldronHook.sol:586 |
| `afterSwap` | TRUE | CauldronHook.sol:587 |
| `beforeDonate` | false | CauldronHook.sol:588 |
| `afterDonate` | false | CauldronHook.sol:589 |
| `beforeSwapReturnDelta` | TRUE | CauldronHook.sol:590 |
| `afterSwapReturnDelta` | TRUE | CauldronHook.sol:591 |
| `afterAddLiquidityReturnDelta` | false | CauldronHook.sol:592 |
| `afterRemoveLiquidityReturnDelta` | false | CauldronHook.sol:593 |

The five enabled bits are exactly the ones with live bodies: CauldronHook.sol:622, CauldronHook.sol:1218 and CauldronHook.sol:779. The nine disabled bits correspond to BaseHook defaults that revert `HookNotImplemented` (BaseHook.sol:45, 58, 76, 94, 117, 140, 157, 176, 195, 214) — note CauldronHook overrides three of those, so only the liquidity and donate defaults remain reachable-in-principle, and their permission bits are false.

### J3. Every BalanceDelta / BeforeSwapDelta construction

| site | construction | meaning |
|---|---|---|
| CauldronHook.sol:1225 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | self-buy or relaunch-close: charge nothing |
| CauldronHook.sol:1228 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | pool not adopted |
| CauldronHook.sol:1254 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | not an exact-input buy |
| CauldronHook.sol:1258 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | exempt player |
| CauldronHook.sol:1267 | `BeforeSwapDeltaLibrary.ZERO_DELTA` | computed fee rounded to zero |
| CauldronHook.sol:1271 | `toBeforeSwapDelta(int128(int256(fee)), 0)` | POSITIVE specified delta = the hook consumed `fee` of the input; unspecified leg untouched |
| CauldronHook.sol:788, 792, 988, 993 | afterSwap returns literal `0` | no return delta taken |
| CauldronHook.sol:1003 | afterSwap returns `int128(uint128(fee))` | positive = the hook takes `fee` out of the unspecified (quote) leg |
| CauldronHook.sol:783 | `BalanceDelta delta` parameter | consumed, not constructed; read at CauldronHook.sol:812 and CauldronHook.sol:996 |
| LegacyBuyLib.sol:100 | `BalanceDelta d = poolManager.swap(...)` | the nested buy's realised delta; read at LegacyBuyLib.sol:115 and LegacyBuyLib.sol:132 |
| BaseHook.sol:105, 116, 128, 139 | `BalanceDelta` returns on the four liquidity callbacks | declared only; all unimplemented and all permission-disabled |

