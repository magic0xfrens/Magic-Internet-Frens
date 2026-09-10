# CauldronHook cluster — mechanical extraction

Scope: `CauldronHook.sol` (2319 lines), `cauldron/FeeRouteLib.sol` (213 lines),
`cauldron/DefaultFeeRouter.sol` (31 lines), `cauldron/ReserveLib.sol` (107 lines),
`cauldron/RoyaltyRouter.sol` (35 lines), and the 9 interfaces declared inside
CauldronHook.sol. Every file read in full. Line numbers verified against the
working tree at `/tmp/blind-tree/contracts/solidity`.

This is extraction only. No severity judgment, no exploit narrative. Where a
comment claims something the code's behavior doesn't obviously match, both are
recorded side by side as a factual observation.

Two peripheral facts, established once here and referenced by short name
below:
- **`out-of-cluster, delegatecall`** = `cauldron/LegacyBuyLib.sol`, a linked
  library (external functions ⇒ Solidity deploys it separately and reaches it
  by `delegatecall`, per its own header comment). It is not one of the five
  cluster files but `CauldronHook.legacyBuyStep` calls into it directly, so
  its `poolManager` calls execute in the hook's own storage/ETH context.
- **`vendor/BaseHook.sol`** = the hook's abstract base (not in the cluster).
  Its external `afterInitialize`/`beforeSwap`/`afterSwap` wrappers are gated
  `onlyPoolManager` and dispatch to the `_afterInitialize`/`_beforeSwap`/
  `_afterSwap` internal overrides that live in CauldronHook.sol. Quoted where
  it establishes AUTHORITY for those three functions.

---

## (A) THE FEE RESERVE — full +/- inventory

Five storage fields accrue value across calls. Two adjacent names —
`floorBps` (vault share) and `guildBps` (dividend share) — are **not**
reserves: they are computed and sent immediately inside `_routeEthFee` via
`FeeRouteLib.routeSplit`/`_fundGuild`/`_move` (CauldronHook.sol:1272-1274,
FeeRouteLib.sol:48-71,105-111,128-135); the hook holds no accruing counter for
either. This is stated as a mechanical fact from reading `_routeEthFee` and
`FeeRouteLib.routeSplit`, not inferred.

### 1. `relaunchETH` — `uint256 public relaunchETH;` (CauldronHook.sol:255)
**Denomination: native wei.** Comment at 251-254: "STRICTLY NATIVE WEI.
Everything that spends this sends it with `.call{value:}`". Confirmed by the
only two payout sites, both `.call{value: amount}` (1558, 1808).

- INCREASE, line 1149: `if (a == address(0)) relaunchETH += amount;` — inside
  `_creditReserve(uint256 amount)`, called from `_routePerpFee` (1134, wraps
  `FeeRouteLib.routePerp`'s undelivered leftover) and from `_routeEthFee`
  (1272-1274, wraps `wantRelaunch + FeeRouteLib.routeSplit(...)`'s leftover).
  Guard on the increase itself: `if (amount == 0) return;` (1147).
- DECREASE, line 1556: `relaunchETH = 0;` — inside `releaseRelaunchETH()`.
  Guard: `if (amount == 0) revert NoETHToRelease();` (1554). Authority gate:
  `if (msg.sender != registry) revert OnlyRegistry();` (1551). No floor check
  against `address(this).balance` anywhere in this function — the send is
  `(bool ok,) = registry.call{value: amount}("")` (1558) and `if (!ok) revert
  SendFailed();` (1559) reverts the whole call (and thus the zeroing at 1556)
  if the hook doesn't actually hold `amount` wei.
- DECREASE, line 1807: `relaunchETH = 0;` — inside `executeRegistryOverride()`,
  guarded by `if (relaunchETH > 0)` (1805). Authority: `onlyOwner` (1801) plus
  a time gate `if (block.timestamp < registrySwapReadyAt) revert
  RegistryAlreadySet();` (1804, reusing that error name for a timing check,
  not an already-set check — factual, not a judgment). Same
  `.call{value:}`/`revert SendFailed()` pattern (1808-1809), sent to
  `registry` — the OUTGOING address, read before `registry = next;` executes
  two lines later (1812).

No other read/write of `relaunchETH` exists in the file (grep-verified,
CauldronHook.sol:255,461,568,708,1149,1173,1553,1556,1763,1777,1805-1807,2305
— the rest are comments).

### 2. `relaunchAsset` — `mapping(address => uint256) public relaunchAsset;` (CauldronHook.sol:2316)
**Denomination: per-key ERC20 units**, keyed by the asset address that was
actually collected. Declared at the very end of the contract under an
"APPEND-ONLY STORAGE" banner (2293-2298) that says new slots must never be
inserted mid-layout because a test pins `legacyOwedToReserve` to a literal
slot.

- INCREASE, line 1150: `else relaunchAsset[a] += amount;` — same
  `_creditReserve` helper as above, `a = _feeAsset` (1148). Reached only when
  `_feeAsset != address(0)`, i.e. the fee was collected in a non-native quote.
- DECREASE, line 1584: `relaunchAsset[asset] = 0;` — inside
  `releaseRelaunchAsset(address asset)`. Guard: `if (amount == 0) revert
  NoETHToRelease();` (1582, same error as the native path, reused for a
  non-ETH asset). Authority: `if (msg.sender != registry) revert
  OnlyRegistry();` (1579). Payout: `if (!FeeRouteLib.send(asset, registry,
  amount, 0)) revert SendFailed();` (1585) — `FeeRouteLib.send` checks the
  ERC20 `transfer` return value (FeeRouteLib.sol:175-178) before reporting
  success. No `balanceOf` check anywhere in `releaseRelaunchAsset` itself —
  see Section B.

### 3. `proposerOwed` — `mapping(address => uint256) public proposerOwed;` (CauldronHook.sol:463)
**Denomination: native wei only, by construction.** `_routeEthFee` computes
`address prop = _feeAsset == address(0) ? activeProposer : address(0);`
(1191) — the non-native branch is routed to `address(0)` and the very next
`if (prop != address(0) && proposerBps > 0)` (1192) skips the whole carve, so
this mapping is only ever written when `_feeAsset == address(0)`.

- INCREASE, line 1195: `proposerOwed[prop] += wantProp;` — inside
  `_routeEthFee`, `wantProp = (feeAmount * proposerBps) / BPS` (1193), guarded
  `if (wantProp > 0)` (1194).
- DECREASE, line 1938: `proposerOwed[msg.sender] = 0;` — inside
  `claimProposerFees()`. Guard: `if (amount == 0) revert
  NoETHToRelease();` (1937). Authority: UNGATED — `nonReentrant` only
  (1935); any caller may zero `proposerOwed[msg.sender]`, i.e. only their own
  entry. Payout `(bool ok,) = msg.sender.call{value: amount}("");` (1939),
  `if (!ok) revert SendFailed();` (1940). No balance floor check in this
  function either.

### 4. `legacyBuffer` — `uint256 public legacyBuffer;` (CauldronHook.sol:287)
**Denomination: native wei only.** Three separate comments assert this
("NATIVE ONLY", 1231, 1257-1258); mechanically confirmed because every credit
site is gated `_feeAsset == address(0)` except the direct ETH donation path,
and the only spend path (`legacyBuyStep`) settles via
`poolManager.settle{value:}` (LegacyBuyLib.sol:69).

- INCREASE, line 1030: `legacyBuffer += msg.value;` — inside
  `fundLegacyBuffer() external payable`. Authority: UNGATED (permissionless
  donation entry point; `RoyaltyRouter.receive()` at RoyaltyRouter.sol:33
  calls this).
- INCREASE, line 1013: `if (spent < amt) { unchecked { legacyBuffer += amt -
  spent; } }` — inside `legacyBuyStep`, refunding the unspent remainder of a
  buyback swap. `unchecked` block; safe by construction since `spent <= amt`
  is the guarding `if`.
- INCREASE, line 1244: `legacyBuffer += fromFloor + fromRelaunch;` — inside
  `_routeEthFee`'s legacy-bps carve, gated `_feeAsset == address(0) &&
  legacyRegistry != address(0) && legacyBps > 0` (1237).
- INCREASE, line 1259: `if (_feeAsset == address(0) && legacyRegistry !=
  address(0)) legacyBuffer += wantFloor;` — inside `_routeEthFee`'s
  no-vault fallback (reached when `vault == address(0)`, 1255).
- DECREASE, line 1000: `legacyBuffer = 0;` — inside `legacyBuyStep`. Guard:
  `if (amt < legacyThreshold) return;` (999) — a threshold gate, not a
  balance check. Authority: `if (msg.sender != address(this)) revert
  OnlySelf();` (997) — self-call only, reached from `_maybeLegacyBuyback`'s
  gas-capped self-call (968-970). The zeroed amount is spent via
  `LegacyBuyLib.buyStep` (1008, delegatecall) which itself settles only the
  swap's *realized* debit (`spent`, LegacyBuyLib.sol:68-69), not the full
  `amt` — the unspent difference is refunded at line 1013 above, so
  `legacyBuffer` is never left permanently short by a partial fill.

### 5. `legacyOwedToReserve` — `uint256 public legacyOwedToReserve;` (CauldronHook.sol:301)
**Denomination: the LIVE iteration TOKEN** (an ERC20 — `_liveKey.currency1`),
not ETH. Established at the only increase site: `got =
uint256(uint128(d.amount1()))` is the token leg bought by the swap
(LegacyBuyLib.sol:71), credited at CauldronHook.sol:1019.

- INCREASE, line 1019: `legacyOwedToReserve += got;` — inside
  `legacyBuyStep`, self-only (see above).
- DECREASE, line 1050: `legacyOwedToReserve = owed - amt;` — inside
  `sweepLegacyReserve(address token, address to)`. Guard/floor, line 1049:
  `amt = owed > bal ? bal : owed;` where `bal =
  IERC20(token).balanceOf(address(this))` (1048) — **this is the one reserve
  in the cluster whose decrease is explicitly clamped to an on-chain
  balance**, contrast Section B. Authority: `if (msg.sender != legacyRegistry)
  revert OnlySelf();` (1046, reusing the self-call error name for a
  registry-address check — factual, not a judgment). Payout: `if (amt > 0)
  IERC20(token).transfer(to, amt);` (1051) — return value of `transfer` is
  **not** checked (no `require`/`if` on it), unlike every `FeeRouteLib` send
  path. `token` is a caller-supplied parameter; nothing in this function
  cross-checks it against `_liveKey.currency1` or against whichever asset
  `legacyBuyStep` most recently bought.

---

## (B) BALANCE vs COUNTER

All five reserves above are tracked by **storage counter**, not by live
balance, with one exception:

| Reserve | Tracked by | Balance ever consulted? |
|---|---|---|
| `relaunchETH` | `uint256` counter | No — `address(this).balance` does not appear anywhere in CauldronHook.sol (grep-verified: the only two `.balance` occurrences in the whole file are `IERC20(...).balanceOf(...)` at 1048, and a *comment* at 1263 describing a **different** contract, `CauldronVault`'s own balance check). |
| `relaunchAsset[asset]` | `mapping` counter | No — `releaseRelaunchAsset` reads only `relaunchAsset[asset]` (1581), never `IERC20(asset).balanceOf(address(this))`. |
| `proposerOwed[addr]` | `mapping` counter | No — `claimProposerFees` reads only `proposerOwed[msg.sender]` (1936). |
| `legacyBuffer` | `uint256` counter | No explicit `.balance` check in `legacyBuyStep`; the spend is bounded indirectly because `LegacyBuyLib.buyStep`'s `poolManager.settle{value: spent}()` (LegacyBuyLib.sol:69) would fail if the hook lacked `spent` wei — an EVM-level backstop, not an application-level balance read. |
| `legacyOwedToReserve` | `uint256` counter | **Yes** — `sweepLegacyReserve` explicitly clamps to `IERC20(token).balanceOf(address(this))` (CauldronHook.sol:1048-1049) before decrementing. |

No function in the cluster reads `address(this).balance` at all. The only
`balanceOf` call in CauldronHook.sol is line 1048.

---

## (C) IN-SWAP READS OF LIVE POOL STATE

Exhaustive grep for `getSlot0`, `sqrtPriceX96`, `.tick`, `getLiquidity`,
`slot0` across the cluster.

1. **`(, int24 tick,,) = poolManager.getSlot0(id);`** — CauldronHook.sol:1329,
   inside `_defaultSurtaxBps(PoolId id)` (internal view). Reached via
   `snipeSurtaxBps(id)` (1283-1292) ⇐ `_takeEthFee` (1360) ⇐ **both**
   `_beforeSwap` (1108, buy leg) and `_afterSwap` (933, sell leg). This is
   the only live PoolManager state read in the whole cluster. In the
   `_beforeSwap` call this reads the pool's pre-this-swap tick; in the
   `_afterSwap` call it reads the post-this-swap tick (the core swap has
   already applied its deltas by the time `afterSwap` fires, per V4's
   ordering). The tick feeds a `keccak256(...)` jitter (1330-1332) folded into
   the anti-sniper surtax.

No other `poolManager.get*` call exists in CauldronHook.sol. `FeeRouteLib.sol`,
`DefaultFeeRouter.sol`, `ReserveLib.sol`, `RoyaltyRouter.sol` contain none —
`ReserveLib.sol` never touches `poolManager` at all (its inputs are a
`launchTick` parameter, not a live read).

Two adjacent items, listed for exhaustiveness though they are not
external/live reads:

- **`delta.amount0()` / `delta.amount1()`** — CauldronHook.sol:744, 928,
  inside `_afterSwap`. `delta` is the `BalanceDelta` **parameter** the
  PoolManager passes into the `afterSwap` callback (already-computed result
  of the swap that just executed) — not a call the hook makes, and not
  independently re-queryable.
- Out-of-cluster, delegatecall: `poolManager.swap(key, SwapParams{...}, "")`
  — LegacyBuyLib.sol:53, inside `buyStep`, reached from
  `CauldronHook.legacyBuyStep` (1008) ⇐ `_maybeLegacyBuyback`'s gas-capped
  self-call (968-970) ⇐ `_afterSwap` (731, 934). This is a **nested swap**
  executed from inside the outer swap's `afterSwap` callback; it re-enters
  the hook's own `_beforeSwap`/`_afterSwap` (guarded to early-return by
  `_inSelfBuy`, set true/false around it at CauldronHook.sol:1007/1009).

`IERC20(token).balanceOf(address(this))` (CauldronHook.sol:1048) reads the
hook's own token balance, not pool state, and is not reached from
beforeSwap/afterSwap — `sweepLegacyReserve` has no caller inside the swap
path (grep-verified: its only caller anywhere is external, gated
`legacyRegistry`).

---

## (D) HOOK MECHANICS

### Permission bits — `getHookPermissions()`, CauldronHook.sol:536-558 (public pure override)
```
beforeInitialize: false,           afterInitialize: true,
beforeAddLiquidity: false,         afterAddLiquidity: false,
beforeRemoveLiquidity: false,      afterRemoveLiquidity: false,
beforeSwap: true,                  afterSwap: true,
beforeDonate: false,               afterDonate: false,
beforeSwapReturnDelta: true,       afterSwapReturnDelta: true,
afterAddLiquidityReturnDelta: false, afterRemoveLiquidityReturnDelta: false
```
Five `true` bits: `afterInitialize`, `beforeSwap`, `afterSwap`,
`beforeSwapReturnDelta`, `afterSwapReturnDelta`. All others `false`.

Each of the three enabled callbacks is only reachable through
`vendor/BaseHook.sol`'s external wrapper, gated `onlyPoolManager`:
`afterInitialize` (BaseHook.sol:49-55), `beforeSwap` (144-150), `afterSwap`
(161-169) — each wrapper calls the matching `_afterInitialize`/`_beforeSwap`/
`_afterSwap` internal override in CauldronHook.sol.

### BeforeSwapDelta constructions/returns (CauldronHook.sol, inside `_beforeSwap`)
- `BeforeSwapDeltaLibrary.ZERO_DELTA` — lines 1068, 1071, 1097, 1101, 1110
  (five early-return paths: self-buy/relaunch-close, untracked pool,
  not-exact-input-buy quadrant, fee-exempt player, zero computed fee).
- `toBeforeSwapDelta(int128(int256(fee)), 0)` — line 1114. Sign convention
  per the function's own comment (1104-1106): "The positive specified delta
  tells the PoolManager the hook consumed `fee` of the input, so only
  (amountIn - fee) is swapped." Second argument (unspecified-side delta) is
  always `0` here.

### afterSwap int128 return (inside `_afterSwap`)
- `(BaseHook.afterSwap.selector, 0)` — lines 720, 724, 920, 924 (no fee:
  self-buy/relaunch-close, untracked pool, wrong leg, computed-fee-is-zero /
  unreached since `_takeEthFee` returning 0 still returns fee var at 935 —
  see function table for `_afterSwap`).
- `(BaseHook.afterSwap.selector, int128(uint128(fee)))` — line 935. Header
  comment (101-103): "the hook collects tiered fees via afterSwap return
  deltas." Positive value = amount the hook takes from the swap's unspecified
  (output) leg.

### BalanceDelta
Never constructed inside CauldronHook.sol — only ever read as the `delta`
parameter of `_afterSwap` (line 715) via `.amount0()`/`.amount1()` (744, 928).
Out-of-cluster: `BalanceDelta d = poolManager.swap(...)` is constructed
(returned by the core, not by hook code) at LegacyBuyLib.sol:53, then read via
`.amount0()`/`.amount1()` at LegacyBuyLib.sol:68, 71.

### `poolManager.take` / `.settle` / `.sync` / `.donate`
- `poolManager.take(feeCur, address(this), total);` — CauldronHook.sol:1379,
  inside `_takeEthFee`, reached from both `_beforeSwap` and `_afterSwap`.
  `feeCur` is whichever `Currency` the adoption gate recorded as the quote
  (`quoteIsCurrency0[id] ? key.currency0 : key.currency1`, 1377).
- `poolManager.settle{value: spent}();` — LegacyBuyLib.sol:69 (out-of-cluster,
  delegatecall). `spent` is the swap's *realized* debit, explicitly not the
  requested `amt` (comment at LegacyBuyLib.sol:63-67 explains over-settling
  would leave a positive delta that reverts the parent swap).
- `poolManager.take(key.currency1, address(this), got);` —
  LegacyBuyLib.sol:72 (out-of-cluster, delegatecall).
- No `.sync(` and no `.donate(` call anywhere in the cluster or in
  LegacyBuyLib.sol (grep-verified).
- No `poolManager.unlock(` call in the cluster — the hook never initiates its
  own top-level unlock; it only runs inside callbacks the PoolManager already
  invoked, plus the nested `poolManager.swap(...)` inside LegacyBuyLib, which
  itself re-enters the already-unlocked PoolManager rather than calling
  `unlock` again (V4's swap does not require a fresh unlock from inside an
  active one — stated as observed call shape, not independently verified
  against v4-core's unlock-reentrancy rules here).

---

## (E) GAS-CAPPED CALLS AND TRY/CATCH

### `call{gas: ...}` (4, all in CauldronHook.sol, all self- or config-target, all result-ignored)
1. Line 881: `perpEngine.call{gas: g - LIQ_GAS_RESERVE}(abi.encodeWithSelector(IPerpEngineLiq.sweepLiquidations.selector, tx.origin))` — inside `_afterSwap`. Target: `perpEngine` (registry/owner-set). On failure: return value unchecked, swap continues.
2. Line 898: `address(this).call{gas: gg - GACHA_GAS_RESERVE}(abi.encodeWithSelector(this.nativeGachaStep.selector, gachaPlayer, gachaWei))` — inside `_afterSwap`. Target: self. On failure: unchecked.
3. Line 968: `address(this).call{gas: gl - LEGACY_GAS_RESERVE}(abi.encodeWithSelector(this.legacyBuyStep.selector, live))` — inside `_maybeLegacyBuyback`. Target: self. On failure: unchecked.
4. Line 985: `s.call{gas: g - SEED_POKE_GAS_RESERVE}(abi.encodeWithSelector(ISeederInSwap.pokeInSwap.selector))` — inside `_maybePoke`. Target: `seeder` (registry/owner-set). On failure: unchecked.

Each is preceded by a `gasleft()` capture and a minimum-gas guard (`LIQ_GAS_MIN`, `GACHA_GAS_MIN`, `LEGACY_GAS_MIN`, `SEED_POKE_GAS_MIN` respectively) so the call is skipped entirely rather than attempted, below that floor.

`FeeRouteLib.send(address asset, address to, uint256 amount, uint256 gasCap)` (FeeRouteLib.sol:162-179) has a conditional gas-capped branch — `to.call{value: amount, gas: gasCap}("")` (169) — reached only when `gasCap != 0`. The cluster's one call site, `releaseRelaunchAsset` (CauldronHook.sol:1585), passes `0`, so that branch is not exercised from within this cluster.

### try/catch (8, all in CauldronHook.sol)
1. Lines 1212-1214, in `_routeEthFee`: `try fr.route(feeAmount, guild, vault, guildBps, floorBps) returns (uint256 g, uint256 f, uint256 r) { if (g + f + r == feeAmount) {...routed = true;} } catch { /* fall through to built-in */ }` — target `feeRouter`. Falls back to the built-in split on revert OR on a sum mismatch.
2. Lines 1286-1289, in `snipeSurtaxBps`: `try pol.surtaxBps(...) returns (uint256 b) { return b > MAX_SNIPE_BPS ? MAX_SNIPE_BPS : b; } catch {...}` — target `surtaxPolicy`. Falls back to `_defaultSurtaxBps(id)`.
3. Lines 1506-1510, in `isDead`: `try checker.isDead(id, vol, deathThreshold) returns (bool dead) { return dead; } catch { return vol < deathThreshold; }` — target `deathChecker`.
4. Lines 1526-1530, in `_getHolderTaxRate`: `try INFTContract(nftContract).getHolderTaxRate(holder) returns (uint256 rate) { return rate; } catch { return defaultTaxBps; }` — target `nftContract`.
5. Line 1664, in `forceClosePerps`: `try IPerpForceClose(eng).forceCloseAllDead() {} catch {}` — target `perpEngine`; both branches empty (result and failure both fully swallowed).
6. Line 1857, in `_wireLiquidator`: `try ICollectionLiquidator(_collection).setLiquidatorMinter(perpEngine) {} catch {}` — target `_collection`; both branches empty.
7. Lines 1969-1972, in `nftPriceAt`: `try pol.priceAt(k, volumePerNFT, nftPriceStep) returns (uint256 c) { if (c > 0) return c; } catch { /* fall through */ }` — target `curvePolicy`. Falls back to `volumePerNFT + k * nftPriceStep` on revert OR `c == 0`.
8. Lines 2018-2021, in `oddsForPlay`: `try pol.oddsBps(playWei, maxOddsBps, oddsFullVolumeWei) returns (uint256 b) { return b > ODDS_HARD_CAP_BPS ? ODDS_HARD_CAP_BPS : b; } catch { /* fall through */ }` — target `oddsPolicy`.

All eight targets (`feeRouter`, `surtaxPolicy`, `deathChecker`, `nftContract`, `perpEngine`, `_collection`/`collection`, `curvePolicy`, `oddsPolicy`) are owner/registry-set addresses — none is derived from swap-time attacker input.

---

## Storage layout (declaration order, CauldronHook.sol)

Constants (`constant`, not real storage slots) are marked *(const)*. Two
`transient` booleans are marked *(transient)*. Everything else is ordinary
persistent storage.

```
188  uint256 public deathThreshold
196  IDeathChecker public deathChecker
203  ISurtaxPolicy public surtaxPolicy
204  IOddsPolicy public oddsPolicy
205  ICurvePolicy public curvePolicy
211  IFeeRouter public feeRouter
216  uint256 internal defaultTaxBps = 300
219  address internal nftContract
222  address public treasury                       -- see note below
225  address public registry
228  address public pendingRegistry
229  uint256 internal registrySwapReadyAt
242  mapping(PoolId => uint128[24]) private _volumeBuckets
244  mapping(PoolId => uint256) private _lastBucketIndex
245  mapping(PoolId => uint256) private _lastUpdateTs
246  mapping(PoolId => bool) public trackedPools
255  uint256 public relaunchETH                     -- RESERVE (A.1)
267  address public collection
276  address public perpEngine
282  address public legacyRegistry
285  uint256 internal legacyBps
287  uint256 public legacyBuffer                    -- RESERVE (A.4)
289  uint256 internal legacyThreshold = 0.02 ether
294  PoolKey internal _liveKey
301  uint256 public legacyOwedToReserve              -- RESERVE (A.5)
305  bool private transient _inSelfBuy
310  bool private transient _inRelaunchClose
325  address public seeder
336  mapping(uint256 => mapping(address => uint256)) public nftCredit
337  uint256 public creditEpoch
343  uint256 public volumePerNFT = 0.02 ether
344  uint256 public nftPriceStep = 0.00002 ether
352  uint256 internal mintBaseline
373  Batch[] public batches
374  uint256 internal batchCursor
375  uint256 public outstandingCrystals
376  mapping(address => uint256) internal outstandingOf
377  mapping(address => uint256) public opened
378  mapping(address => uint256) public committedOf
379  mapping(address => uint256) public pendingOf
380  mapping(address => uint256) public missStreak
383  mapping(address => uint256) public lifetimeVolumeOf
384  uint256 public totalLifetimeVolume
386  uint256 public cumulativeVolume
389  uint256 public buyWeightBps = 15_000
390  uint256 public sellWeightBps = 5_000
396  bool public creditUntaggedSwaps = true
401  uint256 public oddsFullVolumeWei = 0.5 ether
402  uint256 public maxOddsBps = 9_000
404  uint256 internal pityThreshold = 8
408  mapping(address => bool) public isOpener
415  mapping(address => bool) public taxExempt
419  address public vault
424  uint256 public floorBps = 10_000
429  address public quest
435  address public guild
443  uint256 public guildBps = 1500
449  address public activeProposer
457  uint256 public proposerBps = 50
463  mapping(address => uint256) public proposerOwed -- RESERVE (A.3)
468  mapping(PoolId => uint256) public poolInitBlock
473  uint256 public snipeWindowBlocks = 30
479  uint256 public snipeMaxBps = 9_600
622  mapping(PoolId => bool) internal quoteIsCurrency0
630  address internal _feeAsset                      -- NOT `transient`, see note
635  address internal quoteOracle
697  mapping(PoolId => PoolId[]) private _volumeSiblings
2316 mapping(address => uint256) public relaunchAsset -- RESERVE (A.2), appended at file end
```

**Note on `treasury` (line 222):** written in the constructor (529) and by
`setTreasury` (1757); grep across the whole file finds no other read of
`treasury` — no fee split, payout, or comparison references it. Recorded as
observed; UNSURE what (if anything) elsewhere in the wider (out-of-cluster)
codebase reads this getter.

**Note on `_feeAsset` (line 630):** the doc-comment immediately above it
(626) calls it "A transient field rather than a parameter threaded through
every helper" — informal usage. The declaration itself, `address internal
_feeAsset;`, does **not** carry Solidity's `transient` storage keyword,
unlike `_inSelfBuy` (305) and `_inRelaunchClose` (310) which explicitly do.
Mechanically, `_feeAsset` is ordinary persistent storage: it is set at line
1378 on every fee take and otherwise keeps whatever value the previous fee
take left in it.

---

## Interfaces declared inside CauldronHook.sol (lines 31-89)

| Interface | Function(s) | Line |
|---|---|---|
| `IRegistryQuotes` | `allowedQuote(address) view returns (bool)` | 32 |
| `IQuoteOracle` | `cachedUsdPerRawUnit(address) returns (uint256)` (non-view) | 42 |
| `IPerpOpenCount` | `openCount() view returns (uint256)` | 49 |
| `IPerpEngineLiq` | `liquidateInSwap(uint256,address)`; `liquidateManyInSwap(uint256[],address)`; `sweepLiquidations(address)` | 53-55 |
| `ICollectionLiquidator` | `setLiquidatorMinter(address)` | 60 |
| `ILegacyNote` | `noteLegacyBuy(uint256)` | 66 |
| `IPerpForceClose` | `forceCloseAllDead()` | 71 |
| `IPerpFeeCredit` | `creditPerpFee() payable`; `creditPerpFeeToken() payable`; `creditPerpFeeAsset(address,uint256)` | 77-81 |
| `ISeederInSwap` | `pokeInSwap()` | 88 |

`ILegacyNote.noteLegacyBuy` is declared but grep across the entire file (and
the whole repo) finds no call site and no implementer named
`noteLegacyBuy` anywhere else — UNSURE whether this interface is vestigial or
intended for a caller outside this cluster; recorded as observed, not
resolved.

---

## Function table

Full per-function detail (signature, visibility, mutability, modifiers,
authority + exact gate quote, reads, writes, value, edges with trust tags,
reachability, line) is in `/tmp/graph/hook.json`. Summary below; JSON is the
source of truth for exact wording.

**CauldronHook.sol — 78 functions/records** (constructor; `getHookPermissions`;
3 hook callbacks — `_afterInitialize`, `_beforeSwap`, `_afterSwap`; 2
in-swap dispatch helpers — `_maybeLegacyBuyback`, `_maybePoke`; fee pipeline —
`_toUsd`, `_routePerpFee`, `_creditReserve`, `_routeEthFee`, `snipeSurtaxBps`,
`_defaultSurtaxBps`, `_takeEthFee`; legacy buyback —
`legacyBuyStep`, `fundLegacyBuffer`, `sweepLegacyReserve`; volume —
`_recordVolume`, `getVolume24h`, `_getCurrentBucket`, `linkVolume`, `isDead`;
tax — `_getHolderTaxRate`, `_isExemptPlayer`, `_taxedPlayer`; relaunch —
`releaseRelaunchETH`, `releaseRelaunchAsset`; 33 admin setters/getters
(`setSnipeParams` … `setWeights`, `setLiveKey`/`liveKey`,
`proposeRegistryOverride`/`cancelRegistryOverride`/`executeRegistryOverride`,
etc.); gacha — `nftPriceAt`, `creditOf`, `_curvePos`, `crystalsReady`,
`costOfNextCrystals`, `oddsForPlay`, `outstandingTickets`, `mintedOut`,
`progress`, `commitCrystals`/`_commitCrystals`,
`resolveTickets`/`_resolveTickets`, `nativeGachaStep`; `claimProposerFees`;
`_wireLiquidator`; `receive`).

**FeeRouteLib.sol — 7 functions**: `routeSplit`, `routePerp` (external,
entry points), `_move`, `_fundGuild`, `_deliver` (private helpers), `send`,
`deliver` (external, general-purpose send/deliver used by the hook's
relaunch-asset release path).

**DefaultFeeRouter.sol — 1 function**: `route` (external pure — a drop-in
`IFeeRouter` reference implementation; not imported/hardcoded into
CauldronHook.sol, only reachable if `setFeeRouter` is pointed at a deployed
copy of it).

**ReserveLib.sol — 5 functions**: `_alignDown`, `_alignUp`, `reserveTicks`,
`liquidityForTokenOut`, `tokenOutForLiquidity` — all `internal pure`, no
storage, no value. Not called from anywhere in CauldronHook.sol (grep-verified
repo-wide: its callers are `cauldron/SeedLib.sol`, `cauldron/PoolOps.sol`,
`cauldron/RedemptionExt.sol`, all out-of-cluster). Its "reserve" is a
single-sided out-of-range LP tick-math concept for the migration/genesis
token reserve — a different meaning of "reserve" from Section A's fee
counters; noted to avoid conflating the two.

**RoyaltyRouter.sol — 2 functions**: `constructor` (sets immutable `hook`),
`receive() external payable` (forwards `msg.value` into
`ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}()` — i.e. into
Reserve A.4 above). Only referenced from CauldronHook.sol in a comment
(line 1024); the actual link is the matching `fundLegacyBuffer()` selector,
not a direct import.

Total function records: **93** (78 + 7 + 1 + 5 + 2), machine-verified against `/tmp/graph/hook.json`.
