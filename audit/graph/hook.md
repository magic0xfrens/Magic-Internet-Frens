# Function graph — `hook`

Current source-derived semantic map: **148 nodes** across **9 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `CauldronHook.sol` | 2795 |
| `vendor/BaseHook.sol` | 216 |
| `vendor/HookMiner.sol` | 57 |
| `cauldron/FeeRouteLib.sol` | 279 |
| `cauldron/DefaultFeeRouter.sol` | 49 |
| `cauldron/ReserveLib.sol` | 107 |
| `cauldron/RoyaltyRouter.sol` | 139 |
| `cauldron/LegacyBuyLib.sol` | 339 |
| `cauldron/SurtaxLib.sol` | 136 |


## `IRegistryQuotes (declared in CauldronHook.sol)`

### `allowedQuote/function` — CauldronHook.sol:34

- Signature: `function allowedQuote(address quote) external view returns (bool)`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only. Dispatched once per pool adoption at `allowedQuote` (CauldronHook.sol:693), against the address in `registry` (CauldronHook.sol:693) — the one caller `_afterInitialize` (CauldronHook.sol:670) has already required the initializer to BE the registry, so the callee is trusted by construction. Its single bool decides `quoteIsCurrency0` (CauldronHook.sol:696) for the pool's whole life; only currency0 is tested, currency1 is inferred.
- Edges: none
- Observations: none


## `IQuoteOracle (declared in CauldronHook.sol)`

### `cachedUsdPerRawUnit/function` — CauldronHook.sol:44

- Signature: `function cachedUsdPerRawUnit(address quote) external returns (uint256)`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only, and never used as an interface call: the hook builds the selector by hand at `cachedUsdPerRawUnit` (CauldronHook.sol:794) and fires a raw `call` (CauldronHook.sol:793) so a reverting oracle cannot take the swap down. The target is `quoteOracle` (CauldronHook.sol:791), set only through `setDeathThreshold` (CauldronHook.sol:2050). It is non-view by design, so this is a state-changing call inside afterSwap and the oracle is a re-entrancy-capable trusted component.
- Edges: none
- Observations: none


## `IPerpOpenCount (declared in CauldronHook.sol)`

### `openCount/function` — CauldronHook.sol:51

- Signature: `function openCount() external view returns (uint256)`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only. The current pool-link path queries `blocksVolumeLink` (CauldronHook.sol:1815), while this legacy `openCount` declaration has no hook dispatch site (DERIVED).
- Edges: none
- Observations: none

### `blocksVolumeLink/function` — CauldronHook.sol:54

- Signature: `function blocksVolumeLink() external view returns (bool)`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration used by the registry-only pool-link path through `blocksVolumeLink` (CauldronHook.sol:1815); the configured engine address supplies the answer.
- Edges: none
- Observations: none


## `IPerpEngineLiq (declared in CauldronHook.sol)`

### `liquidateInSwap/function` — CauldronHook.sol:58

- Signature: `function liquidateInSwap(uint256 id, address liquidator) external`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only, and unused by the hook: `liquidateInSwap` (CauldronHook.sol:58) has no dispatch site in this cluster (DERIVED). The current swap path enters the shared helper at `_liqSweep` (CauldronHook.sol:1092).
- Edges: none
- Observations: none

### `liquidateManyInSwap/function` — CauldronHook.sol:59

- Signature: `function liquidateManyInSwap(uint256[] calldata ids, address liquidator) external`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only, and DEAD: `liquidateManyInSwap` (CauldronHook.sol:59) has no dispatch site anywhere in the hook (DERIVED).
- Edges: none
- Observations: none

### `sweepLiquidations/function` — CauldronHook.sol:60

- Signature: `function sweepLiquidations(address liquidator, int256 amountSpecified, bool isBuy, uint160 limit) external returns (uint8 status)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: the hook calls it with all gas above the reserve from `_liqSweep` (`sweepLiquidations` CauldronHook.sol:838) and reads a status word back, 0 clean, 1 out of gas, 2 more work than one swap can do.
- Edges: none
- Observations: none

### `openCount/function` — CauldronHook.sol:65

- Signature: `function openCount() external view returns (uint256)`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration queried as `openCount` (CauldronHook.sol:920) only on the low-gas pre-trade branch.
- Edges: none
- Observations: none


## `ICollectionLiquidator (declared in CauldronHook.sol)`

### `setLiquidatorMinter/function` — CauldronHook.sol:70

- Signature: `function setLiquidatorMinter(address minter) external`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only. One dispatch site, `setLiquidatorMinter` (CauldronHook.sol:2344), inside a try/catch in `_wireLiquidator` (CauldronHook.sol:2342); a collection that does not grant the hook this right simply no-ops, so a summon or relaunch cannot brick on it.
- Edges: none
- Observations: none


## `ILegacyNote (declared in CauldronHook.sol)`

### `noteLegacyBuy/function` — CauldronHook.sol:76

- Signature: `function noteLegacyBuy(uint256 tokensBought) external`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only, and DEAD: `noteLegacyBuy` (CauldronHook.sol:76) has no dispatch site in the hook (DERIVED). The buyback's accounting is deferred to the counter written at `legacyOwedToReserve` (CauldronHook.sol:1278) and settled later by the registry's sweep through `sweepLegacyReserve` (CauldronHook.sol:1336).
- Edges: none
- Observations: comment at `registry` (CauldronHook.sol:73) says this is the registry entry that records a legacy buyback against the live collection's pending entitlement; code never calls `noteLegacyBuy` (CauldronHook.sol:76) and instead accrues `legacyOwedToReserve` (CauldronHook.sol:1278) for a later registry-pulled sweep


## `IPerpForceClose (declared in CauldronHook.sol)`

### `forceCloseAllDead/function` — CauldronHook.sol:81

- Signature: `function forceCloseAllDead() external`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only. One dispatch site: `forceCloseAllDead` (CauldronHook.sol:2078), inside the registry-gated `forceClosePerps` (CauldronHook.sol:2073) and wrapped in try/catch, with the transient relaunch flag set around it so the engine's settlement swaps pay no fee.
- Edges: none
- Observations: none

### `openCount/function` — CauldronHook.sol:82

- Signature: `function openCount() external view returns (uint256)`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only. One dispatch site: `openCount` (CauldronHook.sol:2104), immediately after the try/catch. It is NOT guarded, and a non-zero result reverts `PerpsOpen` (CauldronHook.sol:2104) — so the engine's answer here can abort the registry's whole relaunch transaction.
- Edges: none
- Observations: none


## `IPerpFeeCredit (declared in CauldronHook.sol)`

### `creditPerpFee/function` — CauldronHook.sol:88

- Signature: `function creditPerpFee() external payable`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; used as a SELECTOR. `creditPerpFee` (CauldronHook.sol:1459) is chosen for the BUY side and handed to `routePerp` (CauldronHook.sol:1457), which calls it with value through the library's native branch. Reached only when the swapper is the perp engine, per the branch at `perpEngine` (CauldronHook.sol:1707).
- Edges: none
- Observations: none

### `creditPerpFeeToken/function` — CauldronHook.sol:89

- Signature: `function creditPerpFeeToken() external payable`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; used as a SELECTOR. `creditPerpFeeToken` (CauldronHook.sol:1459) is the SELL-side counterpart passed to `routePerp` (CauldronHook.sol:1457). Same gate as its buy-side twin: only a swap whose sender is `perpEngine` (CauldronHook.sol:1707) routes here.
- Edges: none
- Observations: none

### `creditPerpFeeAsset/function` — CauldronHook.sol:92

- Signature: `function creditPerpFeeAsset(address asset, uint256 amount) external`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; used as a SELECTOR for the non-native pull path. `creditPerpFeeAsset` (CauldronHook.sol:1460) is passed to `routePerp` (CauldronHook.sol:1457) and invoked by the library only after it has approved the engine, so the engine pulls rather than receives.
- Edges: none
- Observations: none


## `ISeederInSwap (declared in CauldronHook.sol)`

### `pokeInSwap/function` — CauldronHook.sol:99

- Signature: `function pokeInSwap() external`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; used as a SELECTOR. `pokeInSwap` (CauldronHook.sol:1229) is encoded into a gas-capped low-level call on `seeder` (CauldronHook.sol:1225) from `_maybePoke` (CauldronHook.sol:1224), with the result ignored. Fires on every swap on a tracked pool before any fee is taken, provided a seeder is wired and enough gas remains.
- Edges: none
- Observations: none


## `CauldronHook`

### `setSweepFailOpen/function` — CauldronHook.sol:186

- Signature: `function setSweepFailOpen(bool on) external onlyOwner`
- Authority: owner
- Gate evidence: `function setSweepFailOpen(bool on) external onlyOwner { (CauldronHook.sol:186)`
- Reads: none
- Writes: `sweepFailOpen (line 187)`
- Value: NONE
- Reachability: Owner-only escape hatch. While set, a pre-trade liquidation sweep that could not run at all no longer reverts the swap (`sweepFailOpen` CauldronHook.sol:884), trading liquidation safety for a live market while a broken engine is repointed; an engine that ran and reported unfinished work still reverts either way.
- Edges: none
- Observations: none

### `outstandingCrystals/function` — CauldronHook.sol:457

- Signature: `function outstandingCrystals() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `gacha (line 457)`
- Writes: none
- Value: NONE
- Reachability: External view preserving the former public getter while the counter now lives at `gacha` (CauldronHook.sol:457).
- Edges: none
- Observations: none

### `constructor/constructor` — CauldronHook.sol:605

- Signature: `constructor( IPoolManager _poolManager, uint256 _deathThreshold, address _nftContract, address _treasury, address _owner ) BaseHook(_poolManager) Ownable(_owner)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `deathThreshold (line 612)`; `nftContract (line 613)`; `treasury (line 614)`
- Value: NONE
- Reachability: Runs once at CREATE2 deployment. Ownership is passed in explicitly at `Ownable` (CauldronHook.sol:611) because the hook is deployed through a factory, so the constructor's sender is not the intended owner. The base initialiser reaches `validateHookAddress` (BaseHook.sol:19), which reverts unless the mined address carries exactly the permission bits of `getHookPermissions` (CauldronHook.sol:621). Note that `registry` (CauldronHook.sol:2255) is NOT set here: the hook is inert until the owner wires it, and `registry` (CauldronHook.sol:679) compares against a zero registry until then.
- Edges: `BaseHook.validateHookAddress (BaseHook.sol:19), TRUSTED, in-cluster`
- Observations: comment at `stability` (CauldronHook.sol:289) says the treasury slot is a dead slot read by nothing and kept only for layout stability; code at `treasury` (CauldronHook.sol:614) still writes it from a constructor parameter

### `getHookPermissions/function` — CauldronHook.sol:621

- Signature: `function getHookPermissions() public pure override returns (Hooks.Permissions memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure; no state. Read on-chain during construction by `getHookPermissions` (BaseHook.sol:32) so the v4 address-flag validation can compare it against the deployed address, and off-chain by deploy tooling that mines the salt. The enabled bits are `afterInitialize` (CauldronHook.sol:629), `beforeSwap` (CauldronHook.sol:634), `afterSwap` (CauldronHook.sol:635), `beforeSwapReturnDelta` (CauldronHook.sol:638) and `afterSwapReturnDelta` (CauldronHook.sol:639); every liquidity and donate bit is false.
- Edges: none
- Observations: comment at `afterSwapReturnDelta` (CauldronHook.sol:124) says the hook's permissions are afterInitialize, afterSwap and afterSwapReturnDelta; code additionally enables `beforeSwap` (CauldronHook.sol:634) and `beforeSwapReturnDelta` (CauldronHook.sol:638), which is what lets the buy-leg fee be skimmed before the swap

### `_afterInitialize/function` — CauldronHook.sol:670

- Signature: `function _afterInitialize( address sender, PoolKey calldata key, uint160, int24 ) internal override returns (bytes4)`
- Authority: poolManager (and, inside it, only the registry may be the initializer)
- Gate evidence: `require(sender == registry); (CauldronHook.sol:679)`
- Reads: `registry (line 679)`; `registry (line 693)`
- Writes: `quoteIsCurrency0 (line 696)`; `trackedPools (line 697)`; `_lastUpdateTs (line 698)`; `poolInitBlock (line 699)`
- Value: NONE
- Reachability: Anyone may initialize a v4 pool naming this hook, so the external entry `afterInitialize` (BaseHook.sol:49) is publicly reachable through the pool manager; the adoption gate is the bare `require` (CauldronHook.sol:679), which reverts (no reason string) unless the initializer is the registry. A revert here makes the initialize itself fail, which is what stops anyone squatting a future generation's computable PoolKey. Once past the gate it asks the registry which side is the quote with a single `allowedQuote` (CauldronHook.sol:693) call on currency0 ONLY — currency1 is inferred, never checked — and freezes that answer in `quoteIsCurrency0` (CauldronHook.sol:696) for the pool's lifetime. It also stamps `poolInitBlock` (CauldronHook.sol:699) with the block number, which is the anchor for the anti-sniper decay.
- Edges: `IRegistryQuotes.allowedQuote (CauldronHook.sol:693), UNTRUSTED, out-of-cluster`
- Observations: none

### `_toUsd/function` — CauldronHook.sol:790

- Signature: `function _toUsd(address quote, uint256 raw) internal returns (uint256)`
- Authority: internal (callers: CauldronHook._afterSwap)
- Gate evidence: `UNGATED`
- Reads: `quoteOracle (line 791)`
- Writes: none
- Value: NONE
- Reachability: Reached once per tracked swap from `_toUsd` (CauldronHook.sol:982). With no oracle wired it is the identity at `raw` (CauldronHook.sol:792), so volume stays in raw quote units. Otherwise it makes a low-level `call` (CauldronHook.sol:793) — not a staticcall, so the oracle can write and can re-enter the hook mid-swap — and any failure, short return or zero factor collapses to 0 at `f` (CauldronHook.sol:798), which the caller treats as `cannot judge` and records nothing. The multiply-then-divide at `raw` (CauldronHook.sol:798) rounds DOWN and can revert on overflow for an enormous raw amount, which would revert the swap.
- Edges: `IQuoteOracle.cachedUsdPerRawUnit (CauldronHook.sol:794), UNTRUSTED, out-of-cluster`
- Observations: comment at `oracles` (CauldronHook.sol:109) says the 24h volume is fully computed inside afterSwap with no oracles; code at `quoteOracle` (CauldronHook.sol:791) makes a state-changing external oracle call from inside that same callback whenever the slot is wired

### `_liqSweep/function` — CauldronHook.sol:832

- Signature: `function _liqSweep(address sender, int256 amountSpecified, bool isBuy, uint160 limit) private`
- Authority: internal (callers: CauldronHook._beforeSwap and CauldronHook._afterSwap)
- Gate evidence: `UNGATED`
- Reads: `perpEngine (line 833)`; `LIQ_GAS_RESERVE (line 834, constant)`; `LIQ_GAS_MIN (line 834, constant)`; `sweepFailOpen (line 884)`; `MAX_LIQ_PER_SWAP_VIEW (line 887, constant)`
- Writes: none
- Value: NONE
- Reachability: Private shared sweep; the pre-swap caller passes the signed swap amount and the post-swap caller passes zero. It skips self-recursion and a zero engine (`perpEngine` CauldronHook.sol:833). With enough gas it forwards all gas above the selected reserve (`sweepLiquidations` CauldronHook.sol:838). On the pre-trade call the engine's answer decides the swap: a sweep that could not run or returned a short reply reverts unless the owner's fail-open switch is on (`LiqSweepUnavailable` CauldronHook.sol:884); status 2 reverts as a trade too large for one swap (`LiqTradeTooLarge` CauldronHook.sol:887); any other nonzero status reverts for more gas (`LiqGasStarved` CauldronHook.sol:888). Below the gas floor, only a successfully decoded nonzero open count reverts the pre-trade call (`LiqGasStarved` CauldronHook.sol:921); a reverting or malformed engine is treated as an empty book there. The post-trade call never reverts.
- Edges: `IPerpEngineLiq.sweepLiquidations (CauldronHook.sol:838), UNTRUSTED, out-of-cluster`; `IPerpEngineLiq.openCount (CauldronHook.sol:920), UNTRUSTED, out-of-cluster`
- Observations: none

### `_afterSwap/function` — CauldronHook.sol:925

- Signature: `function _afterSwap( address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData ) internal override returns (bytes4, int128)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:167)`
- Reads: `trackedPools (line 938)`; `quoteIsCurrency0 (line 941)`; `collection (line 1004)`; `creditUntaggedSwaps (line 1023)`; `registry (line 1028)`; `buyWeightBps (line 1035)`; `sellWeightBps (line 1035)`; `BPS (line 1035, constant)`; `nftCredit (line 1039)`; `creditEpoch (line 1039)`; `lifetimeVolumeOf (line 1042)`; `totalLifetimeVolume (line 1045)`; `quest (line 1053)`; `GACHA_GAS_MIN (line 1104, constant)`; `GACHA_GAS_RESERVE (line 1105, constant)`
- Writes: `cumulativeVolume (line 985)`; `nftCredit (line 1041)`; `lifetimeVolumeOf (line 1044)`; `totalLifetimeVolume (line 1047)`
- Value: NONE directly; the returned `fee` (CauldronHook.sol:1142) is the positive unspecified-leg delta collected by the pool manager, after `_takeEthFee` has accounted it.
- Reachability: Reached through pool-manager-gated `afterSwap` (BaseHook.sol:161). Self-buy/relaunch flags and the adoption check short-circuit at `trackedPools` (CauldronHook.sol:938). Quote volume from `delta` (CauldronHook.sol:958) is normalized once; a zero conversion writes no volume or credit. Credit is restricted to the current live currency1 at `_liveKey` (CauldronHook.sol:1005), attributed from hookData or `tx.origin` at `player` (CauldronHook.sol:1021), and all three accumulators saturate. The post-trade liquidation sweep is best-effort through `_liqSweep` (CauldronHook.sol:1092). Native untagged gacha is a gas-bounded, result-ignored self-call at `call` (CauldronHook.sol:1105). Only a sell whose unspecified leg is the quote reaches `_takeEthFee` (CauldronHook.sol:1140); buys were charged before the swap.
- Edges: `CauldronHook._maybeLegacyBuyback (CauldronHook.sol:945), TRUSTED, in-cluster`; `CauldronHook._maybePoke (CauldronHook.sol:947), TRUSTED, in-cluster`; `CauldronHook._toUsd (CauldronHook.sol:982), TRUSTED, in-cluster`; `CauldronHook._recordVolume (CauldronHook.sol:984), TRUSTED, in-cluster`; `CauldronHook._liqSweep (CauldronHook.sol:1092), TRUSTED, in-cluster`; `CauldronHook.nativeGachaStep (CauldronHook.sol:1106), TRUSTED, in-cluster`; `CauldronHook._isExemptPlayer (CauldronHook.sol:1130), TRUSTED, in-cluster`; `CauldronHook._takeEthFee (CauldronHook.sol:1140), TRUSTED, in-cluster`; `CauldronHook._maybeLegacyBuyback (CauldronHook.sol:1141), TRUSTED, in-cluster`
- Observations: none

### `_maybeLegacyBuyback/function` — CauldronHook.sol:1155

- Signature: `function _maybeLegacyBuyback(PoolId id, PoolKey calldata key) private`
- Authority: internal (callers: CauldronHook._afterSwap)
- Gate evidence: `UNGATED`
- Reads: `legacyBuffer (line 1156)`; `_liveKey (line 1157)`; `legacyBufferAsset (line 1183)`; `legacyRegistry (line 1183)`; `legacyThresholdRaw (line 1192)`; `legacyThreshold (line 1193)`; `quoteIsCurrency0 (line 1205)`; `LEGACY_GAS_MIN (line 1211, constant)`; `LEGACY_GAS_RESERVE (line 1212, constant)`
- Writes: `legacyBuffer (line 1185)`
- Value: NONE here; the gas-capped self-call to `legacyBuyStep` (line 1213) is what spends the buffer, and the drain branch only moves the figure between counters at `_creditFor` (line 1189)
- Reachability: Private; called from afterSwap on either leg. FIRST, A DRAIN, NOT A RETURN: a buffer whose denomination does not match the live pool's currency0, or that exists while the buyback is unwired (`legacyRegistry` CauldronHook.sol:1183), is zeroed (`legacyBuffer` CauldronHook.sol:1185) and moved into the reserve for the asset it actually is (`_creditFor` CauldronHook.sol:1189) before any threshold test, so a stranded balance still leaves. The trigger is the threshold cached in the live quote's raw units (`legacyThresholdRaw` CauldronHook.sol:1192), falling back to the native-denominated threshold only when no cache exists (`legacyThreshold` CauldronHook.sol:1193). Three more conditions gate the spend: a quote at currency0 (`quoteIsCurrency0` CauldronHook.sol:1205), a wired live pair and the triggering id equal to the live key's id (`live` CauldronHook.sol:1208). The caller's own key is discarded (`key` CauldronHook.sol:1209), so an attacker cannot steer the spend into a book they price; the spend is a gas-capped self-call whose result is ignored (`legacyBuyStep` CauldronHook.sol:1213).
- Edges: `CauldronHook._creditFor (CauldronHook.sol:1189), TRUSTED, in-cluster`; `CauldronHook.legacyBuyStep (CauldronHook.sol:1213), TRUSTED, in-cluster`
- Observations: none

### `_maybePoke/function` — CauldronHook.sol:1224

- Signature: `function _maybePoke() private`
- Authority: internal (callers: CauldronHook._afterSwap)
- Gate evidence: `UNGATED`
- Reads: `seeder (line 1225)`; `SEED_POKE_GAS_MIN (line 1228, constant)`; `SEED_POKE_GAS_RESERVE (line 1229, constant)`
- Writes: none
- Value: NONE
- Reachability: Private; one call site, `_maybePoke` (CauldronHook.sol:947), near the top of afterSwap and BEFORE the adoption-dependent work below it — but after the tracked-pool early return at `trackedPools` (CauldronHook.sol:938), so an unadopted pool never reaches it. No-ops when `seeder` (CauldronHook.sol:1225) is unset. The call is gas-capped and its result discarded, so a broken seeder can waste gas but cannot revert the swap.
- Edges: `ISeederInSwap.pokeInSwap (CauldronHook.sol:1229), UNTRUSTED, out-of-cluster`
- Observations: none

### `legacyBuyStep/function` — CauldronHook.sol:1240

- Signature: `function legacyBuyStep(PoolKey calldata key) external`
- Authority: hook itself (self-call only)
- Gate evidence: `if (msg.sender != address(this)) revert OnlySelf(); (CauldronHook.sol:1241)`
- Reads: `legacyBuffer (line 1242)`; `legacyThresholdRaw (line 1243)`; `legacyThreshold (line 1244)`; `legacyBufferAsset (line 1261)`; `relaunchETH (line 1267)`; `relaunchAsset (line 1267)`
- Writes: `legacyBuffer (line 1246)`; `legacyBuffer (line 1272)`; `legacyOwedToReserve (line 1278)`
- Value: spends native or the ERC20 quote out of the hook through the delegatecalled `buyStep` (line 1267)
- Reachability: External but self-only: the sole reachable caller is the gas-capped self-call inside `_maybeLegacyBuyback` (CauldronHook.sol:1155). It re-checks the same raw-unit trigger (`legacyThresholdRaw` CauldronHook.sol:1243). A SECOND DENOMINATION GATE lives here: the spender reverts `BadParam` when the key it was handed does not match the buffer's asset (`legacyBufferAsset` CauldronHook.sol:1261), which rolls back the zeroing (`legacyBuffer` CauldronHook.sol:1246); the revert is contained because the only call site ignores the result. The reserve counter for the same asset is passed to the library as encumbered (`relaunchETH` CauldronHook.sol:1267), so the buy clamps to the free balance instead of moving reserve-backed value. The unspent remainder is credited back (`legacyBuffer` CauldronHook.sol:1272). The transient re-entry flag is raised around the nested swap (`_inSelfBuy` CauldronHook.sol:1253) so the hook's own before/afterSwap charge nothing. The bought tokens stay on the hook and are only counted (`legacyOwedToReserve` CauldronHook.sol:1278).
- Edges: `LegacyBuyLib.buyStep (CauldronHook.sol:1267), TRUSTED, delegatecall`
- Observations: none

### `fundLegacyBuffer/function` — CauldronHook.sol:1288

- Signature: `function fundLegacyBuffer() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_liveKey (line 1315)`; `legacyBuffer (line 1316)`; `legacyBufferAsset (line 1316)`
- Writes: `relaunchETH (line 1317)`; `legacyBufferAsset (line 1320)`; `legacyBuffer (line 1321)`
- Value: receives native; it is credited to `legacyBuffer` (line 1321) when the live generation is ether-quoted and the buffer is not already holding another asset, otherwise to `relaunchETH` (line 1317)
- Reachability: Permissionless and payable. The intended caller is RoyaltyRouter, which forwards secondary royalties at `call` (RoyaltyRouter.sol:91), but any address can donate. A zero-value call returns at `msg` (CauldronHook.sol:1314); value that cannot enter the native buffer is rerouted into `relaunchETH` (CauldronHook.sol:1317), so this path does not revert a marketplace sale.
- Edges: none
- Observations: none

### `sweepLegacyReserve/function` — CauldronHook.sol:1336

- Signature: `function sweepLegacyReserve(address token, address to) external returns (uint256 amt)`
- Authority: legacyRegistry
- Gate evidence: `if (msg.sender != legacyRegistry) revert OnlySelf(); (CauldronHook.sol:1337)`
- Reads: `legacyOwedToReserve (line 1338)`
- Writes: `legacyOwedToReserve (line 1341)`
- Value: transfers `token` to the caller-supplied recipient through the delegatecalled `send` (line 1351)
- Reachability: Gated on `legacyRegistry` (CauldronHook.sol:1337) - the same slot the fee split uses as an on/off switch, settable by owner OR registry through `setLegacyBuyback` (CauldronHook.sol:2149). Both `token` (CauldronHook.sol:1336) and the destination are caller-supplied, so the caller chooses which ERC20 is read and where it lands; the debit is clamped to the live balance at `amt` (CauldronHook.sol:1340) so it can only ever equal what the transfer attempts. THE TRANSFER IS NOW CHECKED AND THE DEBIT UNDONE ON FAILURE: the move goes through `send` (CauldronHook.sol:1351), which verifies the ERC20 boolean, and a false answer reverts `SendFailed` (CauldronHook.sol:1351), rolling back the `legacyOwedToReserve` (CauldronHook.sol:1341) debit so the next sweep can still claim it. Unlike the buyback self-call, this entrypoint is called directly by the registry, so the revert propagates to that caller.
- Edges: `IERC20.balanceOf (CauldronHook.sol:1339), UNTRUSTED, out-of-cluster`; `FeeRouteLib.send (CauldronHook.sol:1351), TRUSTED, delegatecall`
- Observations: none

### `_beforeSwap/function` — CauldronHook.sol:1361

- Signature: `function _beforeSwap( address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData ) internal override returns (bytes4, BeforeSwapDelta, uint24)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:146)`
- Reads: `trackedPools (line 1371)`; `quoteIsCurrency0 (line 1373)`
- Writes: none
- Value: NONE directly; `toBeforeSwapDelta` (CauldronHook.sol:1437) returns a positive specified-currency delta equal to the input fee.
- Reachability: Entered through pool-manager-gated `beforeSwap` (BaseHook.sol:144). Self-buy/relaunch and untracked pools return zero delta at `trackedPools` (CauldronHook.sol:1371). Exact-output sells remain refused at `ExactOutSellUnsupported` (CauldronHook.sol:1417). Every other swap shape first invokes the pre-trade `_liqSweep` (CauldronHook.sol:1418); only exact-input buys continue to fee collection, with exemptions checked at `_isExemptPlayer` (CauldronHook.sol:1423).
- Edges: `CauldronHook._liqSweep (CauldronHook.sol:1418), TRUSTED, in-cluster`; `CauldronHook._isExemptPlayer (CauldronHook.sol:1423), TRUSTED, in-cluster`; `CauldronHook._takeEthFee (CauldronHook.sol:1431), TRUSTED, in-cluster`
- Observations: none

### `_routePerpFee/function` — CauldronHook.sol:1452

- Signature: `function _routePerpFee(uint256 amount, bool isBuy) private`
- Authority: internal (callers: CauldronHook._takeEthFee)
- Gate evidence: `UNGATED`
- Reads: `BPS (line 1453, constant)`; `guild (line 1458)`; `perpEngine (line 1458)`
- Writes: none
- Value: no direct transfer; the guild and staker shares leave through the delegatecalled `routePerp` (line 1457)
- Reachability: Private; one call site, `_routePerpFee` (CauldronHook.sol:1707), taken only when the swapper IS the configured perp engine. The 30/70 split is a hard-coded literal at `toGuild` (CauldronHook.sol:1453) — not a tunable bps slot — and the remainder is computed by subtraction at `toStakers` (CauldronHook.sol:1454) so the two always sum exactly. Which staker side is credited is decided by the caller's isBuy flag at `isBuy` (CauldronHook.sol:1459). Whatever the library could not deliver comes back as a number and is booked to the reserve in the same expression.
- Edges: `FeeRouteLib.routePerp (CauldronHook.sol:1457), TRUSTED, delegatecall`; `CauldronHook._creditReserve (CauldronHook.sol:1457), TRUSTED, in-cluster`
- Observations: none

### `_creditReserve/function` — CauldronHook.sol:1469

- Signature: `function _creditReserve(uint256 amount) private`
- Authority: internal (callers: CauldronHook._routePerpFee, CauldronHook._routeEthFee)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Private one-liner; two call sites, `_creditReserve` (CauldronHook.sol:1457) and `_creditReserve` (CauldronHook.sol:1638). It no longer does the branching itself: it forwards the transient fee asset to `_creditFor` (CauldronHook.sol:1469), which is the single place that decides whether a residual joins the native wei counter or the per-asset mapping.
- Edges: `CauldronHook._creditFor (CauldronHook.sol:1469), TRUSTED, in-cluster`
- Observations: none

### `_creditFor/function` — CauldronHook.sol:1473

- Signature: `function _creditFor(address a, uint256 amount) private`
- Authority: internal (callers: CauldronHook._creditReserve, CauldronHook._maybeLegacyBuyback)
- Gate evidence: `UNGATED`
- Reads: `relaunchETH (line 1475)`; `relaunchAsset (line 1476)`
- Writes: `relaunchETH (line 1475)`; `relaunchAsset (line 1476)`
- Value: NONE; it only moves a figure between the two reserve counters
- Reachability: New private helper, reached from `_creditFor` (CauldronHook.sol:1469) for a residual in the CURRENT fee asset and from `_creditFor` (CauldronHook.sol:1189) for a buffer stranded in some OTHER asset after a rotation or an unwiring. The caller names the denomination explicitly at `a` (CauldronHook.sol:1475), which is what lets the stale-buffer drain credit the asset the buffer really holds rather than whatever the current fee happens to be. A zero amount returns at `amount` (CauldronHook.sol:1474). Both destinations have exits (`releaseRelaunchETH` and `releaseRelaunchAsset` on this contract).
- Edges: none
- Observations: none

### `_routeEthFee/function` — CauldronHook.sol:1479

- Signature: `function _routeEthFee(uint256 feeAmount) private`
- Authority: internal (callers: CauldronHook._takeEthFee)
- Gate evidence: `UNGATED`
- Reads: `activeProposer (line 1517)`; `proposerBps (line 1518)`; `BPS (line 1519, constant)`; `proposerOwed (line 1521)`; `feeRouter (line 1536)`; `guild (line 1538)`; `vault (line 1538)`; `guildBps (line 1538)`; `floorBps (line 1538)`; `guild (line 1560)`; `guildBps (line 1560)`; `floorBps (line 1562)`; `_liveKey (line 1592)`; `legacyRegistry (line 1593)`; `legacyBps (line 1593)`; `legacyBuffer (line 1594)`; `legacyBufferAsset (line 1594)`; `vault (line 1613)`; `legacyRegistry (line 1621)`
- Writes: `proposerOwed (line 1521)`; `legacyBufferAsset (line 1601)`; `legacyBuffer (line 1602)`; `legacyBufferAsset (line 1623)`; `legacyBuffer (line 1624)`
- Value: no direct transfer; the guild and floor shares leave through the delegatecalled `routeSplit` (line 1639) and everything undelivered is booked by `_creditReserve` (line 1638)
- Reachability: Private; reached for the base fee of an ordinary swap and for a surtax the guild refused. Order of operations: the proposer slice is carved off the top only for a native fee (`prop` CauldronHook.sol:1517), accrued pull-style so the swap path stays call-free. Then an optional router is asked for the split by a bounded STATICCALL that must return three full words (`routed` CauldronHook.sol:1544), so the router cannot write state or re-enter the fee path; its answer is used only if the parts are each within the fee and sum exactly to it (`routed` CauldronHook.sol:1551), otherwise the built-in split applies. Then the legacy carve, taken from the floor share first, gated on the fee asset matching the live pool's currency0 (`_feeAsset` CauldronHook.sol:1592) and on the buffer being empty or already in that asset (`legacyBufferAsset` CauldronHook.sol:1594), with the denomination stamped alongside the figure (`legacyBufferAsset` CauldronHook.sol:1601). With no vault the floor share joins the buffer under the same match rule (`legacyBufferAsset` CauldronHook.sol:1623) or folds into relaunch. Nothing reverts: every undeliverable share ends in the reserve (`_creditReserve` CauldronHook.sol:1638).
- Edges: `IFeeRouter.route (CauldronHook.sol:1538), UNTRUSTED, out-of-cluster`; `CauldronHook._creditReserve (CauldronHook.sol:1638), TRUSTED, in-cluster`; `FeeRouteLib.routeSplit (CauldronHook.sol:1639), TRUSTED, delegatecall`
- Observations: none

### `snipeSurtaxBps/function` — CauldronHook.sol:1649

- Signature: `function snipeSurtaxBps(PoolId id) public view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `surtaxPolicy (line 1656)`; `poolInitBlock (line 1656)`; `snipeMaxBps (line 1656)`; `snipeWindowBlocks (line 1656)`; `MAX_SNIPE_BPS (line 1656, constant)`
- Writes: none
- Value: NONE
- Reachability: Public view, also on the fee hot path. It reads the inputs and hands them to the linked view library (`SurtaxLib` CauldronHook.sol:1655). The policy preference, the bounded one-word STATICCALL that stops a reverting or malformed module bricking the fee path, the fallback curve and both clamps are on the library side: the module's answer is clamped to the hard cap (`hardCap` SurtaxLib.sol:56) and an invalid reply falls through to the built-in curve (`defaultSurtaxBps` SurtaxLib.sol:58). The jitter is per block, seeded from the previous blockhash, pool id, block number and `prevrandao` (SurtaxLib.sol:129), and added to the linear decay (`total` SurtaxLib.sol:133).
- Edges: `SurtaxLib.surtaxBps (CauldronHook.sol:1655), TRUSTED, out-of-cluster`
- Observations: comment at `prevrandao` (CauldronHook.sol:1646) says the jitter means there is no cleanly-predictable cheap block to schedule an entry into; the library that computes it states the opposite at `snipeSurtaxBps` (SurtaxLib.sol:78) - because the getter is public view, a sniper can read the block's draw and retry in the next block - and the floor the code does guarantee is the deterministic decay at `total` (SurtaxLib.sol:133)

### `_takeEthFee/function` — CauldronHook.sol:1668

- Signature: `function _takeEthFee( PoolId id, PoolKey calldata key, address sender, bytes calldata hookData, uint256 ethAmount, bool isBuy ) private returns (uint256 total)`
- Authority: internal (callers: CauldronHook._beforeSwap, CauldronHook._afterSwap)
- Gate evidence: `UNGATED`
- Reads: `MAX_TOTAL_FEE_BPS (line 1684, constant)`; `BPS (line 1685, constant)`; `quoteIsCurrency0 (line 1700)`; `perpEngine (line 1707)`; `guild (line 1715)`
- Writes: none
- Value: pulls `total` (line 1702) of the quote currency out of the pool manager into this hook
- Reachability: Private; the two call sites are the buy leg at `_takeEthFee` (CauldronHook.sol:1431) and the sell leg at `_takeEthFee` (CauldronHook.sol:1140), so its authority is exactly the pool manager's. The taxed identity is resolved once at `_taxedPlayer` (CauldronHook.sol:1681) so a routed trade is charged the trader's tier rather than the router's. The combined rate is clamped at `MAX_TOTAL_FEE_BPS` (CauldronHook.sol:1684) so a swap always keeps at least one percent. The actual custody move is the pool-manager `take` (CauldronHook.sol:1702) — an in-swap call to core that credits this contract — and it happens BEFORE any routing, with the transient fee-asset field written first at `_feeAsset` (CauldronHook.sol:1701) so every downstream send knows the denomination. Surtax is offered to the guild first and only falls into the normal split if the guild is unset or refused at `guild` (CauldronHook.sol:1715).
- Edges: `CauldronHook._taxedPlayer (CauldronHook.sol:1681), TRUSTED, in-cluster`; `CauldronHook._getHolderTaxRate (CauldronHook.sol:1681), TRUSTED, in-cluster`; `CauldronHook.snipeSurtaxBps (CauldronHook.sol:1683), TRUSTED, in-cluster`; `IPoolManager.take (CauldronHook.sol:1702), TRUSTED, out-of-cluster`; `CauldronHook._routePerpFee (CauldronHook.sol:1707), TRUSTED, in-cluster`; `CauldronHook._routeEthFee (CauldronHook.sol:1708), TRUSTED, in-cluster`; `FeeRouteLib.routeSplit (CauldronHook.sol:1715), TRUSTED, delegatecall`; `CauldronHook._routeEthFee (CauldronHook.sol:1716), TRUSTED, in-cluster`
- Observations: none

### `setSnipeParams/function` — CauldronHook.sol:1723

- Signature: `function setSnipeParams(uint256 windowBlocks, uint256 maxBps) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:1723)`
- Reads: `MAX_SNIPE_BPS (line 1724, constant)`
- Writes: `snipeWindowBlocks (line 1725)`; `snipeMaxBps (line 1726)`
- Value: NONE
- Reachability: Owner-only. The peak is bounded by `MAX_SNIPE_BPS` (CauldronHook.sol:1724) but the WINDOW is not bounded at all at `snipeWindowBlocks` (CauldronHook.sol:1725), so an arbitrarily long surtax window can be set; the per-swap clamp in `MAX_TOTAL_FEE_BPS` (CauldronHook.sol:1684) is what keeps a trade executable.
- Edges: none
- Observations: none

### `_recordVolume/function` — CauldronHook.sol:1733

- Signature: `function _recordVolume(PoolId id, uint256 amount) private`
- Authority: internal (caller: CauldronHook._afterSwap)
- Gate evidence: `UNGATED`
- Reads: `_lastUpdateTs (line 1734)`; `SECONDS_PER_HOUR (line 1742, constant)`; `_lastBucketIndex (line 1744)`; `HOURS_PER_DAY (line 1746, constant)`; `_volumeBuckets (line 1757)`
- Writes: `_volumeBuckets (line 1748)`; `_volumeBuckets (line 1752)`; `_volumeBuckets (line 1758)`; `_lastBucketIndex (line 1760)`; `_lastUpdateTs (line 1761)`
- Value: NONE
- Reachability: Private and called only for non-zero normalized volume at `_recordVolume` (CauldronHook.sol:984). Absolute-hour `steps` (CauldronHook.sol:1742) distinguishes the same ring index a day later from the same current hour. A full clear is fixed at 24 iterations; the partial clear is bounded because `steps` is less than `HOURS_PER_DAY` (CauldronHook.sol:1746). The bucket add saturates at `type` (CauldronHook.sol:1759).
- Edges: `CauldronHook._getCurrentBucket (CauldronHook.sol:1743), TRUSTED, in-cluster`
- Observations: none

### `getVolume24h/function` — CauldronHook.sol:1766

- Signature: `function getVolume24h(PoolId id) public view returns (uint256 total)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `SECONDS_PER_HOUR (line 1771, constant)`; `_lastUpdateTs (line 1771)`; `HOURS_PER_DAY (line 1772, constant)`; `_lastBucketIndex (line 1773)`; `_volumeBuckets (line 1774)`
- Writes: none
- Value: NONE
- Reachability: Public view. An absolute-hour `gap` (CauldronHook.sol:1771) returns zero after a full day and causes the fixed ring scan to skip buckets that have expired but have not yet been lazily cleared. The loop at `HOURS_PER_DAY` (CauldronHook.sol:1778) has at most 24 iterations, and its uint128 sum cannot overflow uint256.
- Edges: none
- Observations: none

### `linkVolume/function` — CauldronHook.sol:1813

- Signature: `function linkVolume(PoolId primary, PoolId secondary) external`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1814)`
- Reads: `registry (line 1814)`; `perpEngine (line 1815)`; `_volumeSiblings (line 1827)`
- Writes: none
- Value: NONE
- Reachability: Registry-only. A configured engine may veto through `blocksVolumeLink` (CauldronHook.sol:1815); that external call is not caught. Self-linking returns at `primary` (CauldronHook.sol:1826). Existing siblings are connected bidirectionally with the new pool at `_addSibling` (CauldronHook.sol:1852), and the primary/new pair is also linked both ways, making every member's aggregate symmetric. `_addSibling` performs deduplication and enforces the per-node cap.
- Edges: `IPerpOpenCount.blocksVolumeLink (CauldronHook.sol:1815), UNTRUSTED, out-of-cluster`; `CauldronHook._addSibling (CauldronHook.sol:1852), TRUSTED, in-cluster`; `CauldronHook._addSibling (CauldronHook.sol:1853), TRUSTED, in-cluster`; `CauldronHook._addSibling (CauldronHook.sol:1855), TRUSTED, in-cluster`; `CauldronHook._addSibling (CauldronHook.sol:1856), TRUSTED, in-cluster`
- Observations: There remains no unlink path: each distinct destination permanently consumes sibling capacity, as documented beside `MAX_SIBLINGS` (CauldronHook.sol:1873).

### `_addSibling/function` — CauldronHook.sol:1862

- Signature: `function _addSibling(PoolId a, PoolId b) private`
- Authority: internal (caller: CauldronHook.linkVolume)
- Gate evidence: `UNGATED`
- Reads: `_volumeSiblings (line 1863)`; `MAX_SIBLINGS (line 1867, constant)`
- Writes: `_volumeSiblings (line 1863)`
- Value: NONE
- Reachability: Private helper reached only from the `_addSibling` calls in linkVolume (CauldronHook.sol:1852). It scans at most the capped sibling list, returns on a duplicate at `unwrap` (CauldronHook.sol:1865), rejects a distinct overflow at `MAX_SIBLINGS` (CauldronHook.sol:1867), then appends `b` (CauldronHook.sol:1868).
- Edges: none
- Observations: none

### `isDead/function` — CauldronHook.sol:1880

- Signature: `function isDead(PoolId id) external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `trackedPools (line 1881)`; `_volumeSiblings (line 1887)`; `deathChecker (line 1889)`; `deathThreshold (line 1893)`; `deathThreshold (line 1896)`; `deathThreshold (line 1899)`
- Writes: none
- Value: NONE
- Reachability: External view, permissionless, and it is the gate the registry's relaunch depends on. An untracked pool is never dead at `trackedPools` (CauldronHook.sol:1881). Volume is summed across the primary and every sibling, so the loop at `sib` (CauldronHook.sol:1888) costs one full 24-bucket sum per sibling and is bounded only by the sibling cap. A pluggable checker is consulted inside try/catch at `checker` (CauldronHook.sol:1893) and a revert falls back to the built-in comparison, so a broken module cannot brick relaunch — but a WORKING hostile module can return either answer.
- Edges: `CauldronHook.getVolume24h (CauldronHook.sol:1886), TRUSTED, in-cluster`; `CauldronHook.getVolume24h (CauldronHook.sol:1888), TRUSTED, in-cluster`; `IDeathChecker.isDead (CauldronHook.sol:1893), UNTRUSTED, out-of-cluster`
- Observations: none

### `_getCurrentBucket/function` — CauldronHook.sol:1902

- Signature: `function _getCurrentBucket() private view returns (uint256)`
- Authority: internal (callers: CauldronHook._recordVolume)
- Gate evidence: `UNGATED`
- Reads: `SECONDS_PER_HOUR (line 1903, constant)`; `HOURS_PER_DAY (line 1903, constant)`
- Writes: none
- Value: NONE
- Reachability: Private view, one call site at `_getCurrentBucket` (CauldronHook.sol:1743). Pure wall-clock arithmetic on the block timestamp, which is what makes the window mean the same thing on a chain whose block numbers track a parent chain.
- Edges: none
- Observations: none

### `_getHolderTaxRate/function` — CauldronHook.sol:1910

- Signature: `function _getHolderTaxRate(address holder) private view returns (uint256)`
- Authority: internal (caller: CauldronHook._takeEthFee)
- Gate evidence: `UNGATED`
- Reads: `nftContract (line 1911)`; `defaultTaxBps (line 1911)`; `nftContract (line 1913)`; `MAX_TAX_BPS (line 1917, constant)`; `defaultTaxBps (line 1919)`
- Writes: none
- Value: NONE
- Reachability: Private fee lookup. With no NFT contract it returns `defaultTaxBps` (CauldronHook.sol:1911). Otherwise the external view call is caught; a successful tier rate is clamped at `MAX_TAX_BPS` (CauldronHook.sol:1917), and a revert falls back to the default.
- Edges: `INFTContract.getHolderTaxRate (CauldronHook.sol:1913), UNTRUSTED, out-of-cluster`
- Observations: none

### `setDefaultTaxBps/function` — CauldronHook.sol:1925

- Signature: `function setDefaultTaxBps(uint256 _bps) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:1925)`
- Reads: `MAX_TAX_BPS (line 1926, constant)`
- Writes: `defaultTaxBps (line 1927)`
- Value: NONE
- Reachability: Owner-only, bounded by `MAX_TAX_BPS` (CauldronHook.sol:1926) at ten percent. Only affects swaps where `nftContract` (CauldronHook.sol:1911) is unset or reverting.
- Edges: none
- Observations: none

### `releaseRelaunchETH/function` — CauldronHook.sol:1940

- Signature: `function releaseRelaunchETH() external returns (uint256 amount)`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1941)`
- Reads: `registry (line 1941)`; `relaunchETH (line 1943)`
- Writes: `relaunchETH (line 1946)`
- Value: sends native to `registry` (line 1948)
- Reachability: Registry-only, and the counter is zeroed BEFORE the send at `relaunchETH` (CauldronHook.sol:1946), so it is checks-effects-interactions. A zero balance reverts `NoETHToRelease` (CauldronHook.sol:1944) rather than returning zero, and a failed send reverts `SendFailed` (CauldronHook.sol:1949) — which rolls the zeroing back, so the counter and the balance cannot silently diverge here. The counter is authoritative: nothing compares it against `address(this).balance`, so ether paid out elsewhere reduces the backing without reducing the number.
- Edges: none
- Observations: none

### `releaseRelaunchAsset/function` — CauldronHook.sol:1968

- Signature: `function releaseRelaunchAsset(address asset) external returns (uint256 amount)`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1969)`
- Reads: `registry (line 1969)`; `relaunchAsset (line 1971)`
- Writes: `relaunchAsset (line 1974)`
- Value: ERC20 transfer of `asset` to `registry` (line 1975)
- Reachability: Registry-only, per-asset counterpart to the native release. The mapping entry is zeroed before the move at `relaunchAsset` (CauldronHook.sol:1974) and the library's boolean IS checked at `send` (CauldronHook.sol:1975), so a token that returns false rather than reverting cannot zero the counter while the tokens stay put. The gas cap passed is zero, i.e. unbounded, which matters only for the native branch the caller cannot reach here.
- Edges: `FeeRouteLib.send (CauldronHook.sol:1975), TRUSTED, delegatecall`
- Observations: none

### `renounceOwnership/function` — CauldronHook.sol:2002

- Signature: `function renounceOwnership() public view override onlyOwner`
- Authority: owner only, and it reverts for the owner too
- Gate evidence: `public view override onlyOwner (CauldronHook.sol:2002)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Overrides OpenZeppelin's live `renounceOwnership` and always reverts at `RenounceDisabled` (CauldronHook.sol:2003), so ownership on this contract is transferable but not renounceable; `transferOwnership` remains the route to the governance timelock. This contract inherits Ownable directly rather than through CauldronBase, so the base contract's own guard never covered this selector (DERIVED). Because the `onlyOwner` modifier still runs first (CauldronHook.sol:2002), a non-owner caller gets Ownable's unauthorized error and only the owner reaches `RenounceDisabled` (CauldronHook.sol:2003) - the two callers are distinguishable by revert data (DERIVED). Declared `view` while reverting, which is legal and keeps the selector non-payable and gas-free to probe (DERIVED).
- Edges: none
- Observations: none

### `setDeathThreshold/function` — CauldronHook.sol:2050

- Signature: `function setDeathThreshold( uint256 _threshold, address _oracle, uint256 _volumePerNFT, uint256 _nftPriceStep, uint256 _oddsFullVolume ) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2056)`
- Reads: none
- Writes: `deathThreshold (line 2057)`; `quoteOracle (line 2060)`; `volumePerNFT (line 2061)`; `nftPriceStep (line 2062)`; `oddsFullVolumeWei (line 2063)`
- Value: NONE
- Reachability: Owner-only, and the only way to wire `quoteOracle` (CauldronHook.sol:2060). Wiring an oracle re-denominates every volume-derived number, so the setter forces the curve to be restated in the same call and rejects a zero base or zero full-play size at `BadParam` (CauldronHook.sol:2059). A zero oracle argument leaves the oracle and the curve untouched while still moving `deathThreshold` (CauldronHook.sol:2057) — and there is no way to UNSET an oracle once set, because address(0) is the leave-alone sentinel.
- Edges: none
- Observations: none

### `forceClosePerps/function` — CauldronHook.sol:2073

- Signature: `function forceClosePerps() external`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2074)`
- Reads: `registry (line 2074)`; `perpEngine (line 2075)`
- Writes: none
- Value: NONE
- Reachability: Registry-only, called once per rebirth. It raises the transient relaunch flag at `_inRelaunchClose` (CauldronHook.sol:2077) so the engine's settlement swaps skip fee and buyback, force-closes inside try/catch, then lowers it at `_inRelaunchClose` (CauldronHook.sol:2079). The flag is transient, so it clears at end of transaction even if the close reverts. The final survivor check at `openCount` (CauldronHook.sol:2104) is NOT guarded and reverts `PerpsOpen` (CauldronHook.sol:2104) on any leftover, which deliberately unwinds the caller's whole relaunch rather than stranding positions.
- Edges: `IPerpForceClose.forceCloseAllDead (CauldronHook.sol:2078), UNTRUSTED, out-of-cluster`; `IPerpForceClose.openCount (CauldronHook.sol:2104), UNTRUSTED, out-of-cluster`
- Observations: none

### `setLiveKey/function` — CauldronHook.sol:2135

- Signature: `function setLiveKey(PoolKey calldata k) external`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2136)`
- Reads: `registry (line 2136)`
- Writes: `_liveKey (line 2137)`
- Value: NONE
- Reachability: Registry-only, pushed at every summon, relaunch and quote change. A plain storage write with no validation of the key (`_liveKey` CauldronHook.sol:2137), so the registry alone decides which pool the buyback spends into. It then re-caches the buyback trigger in the new currency0's raw units (`_cacheLegacyThreshold` CauldronHook.sol:2138).
- Edges: `CauldronHook._cacheLegacyThreshold (CauldronHook.sol:2138), TRUSTED, in-cluster`
- Observations: none

### `liveKey/function` — CauldronHook.sol:2142

- Signature: `function liveKey() external view returns (PoolKey memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_liveKey (line 2143)`
- Writes: none
- Value: NONE
- Reachability: External view returning the whole struct; the canonical pool for integrators. Same data the internal paths read at `_liveKey` (CauldronHook.sol:1157).
- Edges: none
- Observations: none

### `setLegacyBuyback/function` — CauldronHook.sol:2149

- Signature: `function setLegacyBuyback(address registry_, uint256 bps, uint256 threshold) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2150)`
- Reads: `registry (line 2150)`; `BPS (line 2151, constant)`; `_liveKey (line 2155)`
- Writes: `legacyRegistry (line 2152)`; `legacyBps (line 2153)`; `legacyThreshold (line 2154)`
- Value: NONE
- Reachability: Two holders: the registry and the owner. `legacyRegistry` (CauldronHook.sol:2152) is unvalidated and doubles as the authority for `sweepLegacyReserve`, so setting it grants that withdrawal right to an arbitrary address. The share is bounded by `BPS` (CauldronHook.sol:2151) at 100 percent of the post-guild fee, a zero threshold leaves the existing one alone (`legacyThreshold` CauldronHook.sol:2154), and the raw-unit trigger is re-cached for the live quote (`_cacheLegacyThreshold` CauldronHook.sol:2155).
- Edges: `Ownable.owner (CauldronHook.sol:2150), TRUSTED, out-of-cluster`; `CauldronHook._cacheLegacyThreshold (CauldronHook.sol:2155), TRUSTED, in-cluster`
- Observations: none

### `_cacheLegacyThreshold/function` — CauldronHook.sol:2163

- Signature: `function _cacheLegacyThreshold(address quote) private`
- Authority: internal (callers: setLiveKey, setLegacyBuyback)
- Gate evidence: `UNGATED`
- Reads: `quoteOracle (line 2169)`; `legacyThreshold (line 2171)`; `legacyThreshold (line 2192)`
- Writes: `legacyThresholdRaw (line 2174)`; `legacyThresholdRaw (line 2182)`; `legacyThresholdRaw (line 2187)`; `legacyThresholdRaw (line 2195)`; `legacyThresholdRaw (line 2197)`; `legacyThresholdRaw (line 2200)`
- Value: NONE
- Reachability: Restates the native-denominated buyback threshold in the live quote's raw units. With an oracle and a priceable quote it converts by dollar value (`legacyThresholdRaw` CauldronHook.sol:2174); otherwise by decimals alone, read with a bounded call. An unreadable or absurd decimals value sets the trigger to 1 raw unit (`legacyThresholdRaw` CauldronHook.sol:2182), so the buffer still drains rather than sitting forever; a conversion that rounds to zero is lifted to 1 and an overflow saturates (`legacyThresholdRaw` CauldronHook.sol:2200).
- Edges: `CauldronHook._toUsd (CauldronHook.sol:2170), TRUSTED, in-cluster`; `IERC20.decimals (CauldronHook.sol:2180), UNTRUSTED, out-of-cluster`
- Observations: none

### `setDeathChecker/function` — CauldronHook.sol:2211

- Signature: `function setDeathChecker(address _checker) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2212)`
- Reads: `registry (line 2212)`
- Writes: `deathChecker (line 2213)`
- Value: NONE
- Reachability: Owner or registry. Unvalidated: any address, including one that is not a contract, can be written to `deathChecker` (CauldronHook.sol:2213); the consumer wraps it in try/catch at `checker` (CauldronHook.sol:1893) so a bad module degrades to the built-in rule.
- Edges: `Ownable.owner (CauldronHook.sol:2212), TRUSTED, out-of-cluster`
- Observations: none

### `setPolicies/function` — CauldronHook.sol:2221

- Signature: `function setPolicies(address _surtax, address _odds, address _curve) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2222)`
- Reads: `registry (line 2222)`
- Writes: `surtaxPolicy (line 2223)`; `oddsPolicy (line 2224)`; `curvePolicy (line 2225)`
- Value: NONE
- Reachability: Owner or registry; all three modules are written unconditionally, so passing address(0) for one CLEARS it rather than leaving it alone. Each consumer bounds and falls back: the surtax is clamped in the linked library (`hardCap` SurtaxLib.sol:56), the odds at `ODDS_HARD_CAP_BPS` (CauldronHook.sol:2516), and the curve price is used only when the bounded call returned a full nonzero word (`valid` CauldronHook.sol:2468), with no upper bound on what a curve policy may charge.
- Edges: `Ownable.owner (CauldronHook.sol:2222), TRUSTED, out-of-cluster`
- Observations: none

### `setFeeRouter/function` — CauldronHook.sol:2233

- Signature: `function setFeeRouter(address _router) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2234)`
- Reads: `registry (line 2234)`
- Writes: `feeRouter (line 2235)`
- Value: NONE
- Reachability: Owner or registry. The router only returns amounts: the hook keeps custody and does the sends itself (`routeSplit` CauldronHook.sol:1639). It is queried by STATICCALL, so it cannot write state or re-enter mid-swap, and an answer that is short or does not split the fee exactly is ignored (`routed` CauldronHook.sol:1551).
- Edges: `Ownable.owner (CauldronHook.sol:2234), TRUSTED, out-of-cluster`
- Observations: none

### `setNftContract/function` — CauldronHook.sol:2239

- Signature: `function setNftContract(address _nft) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2239)`
- Reads: none
- Writes: `nftContract (line 2240)`
- Value: NONE
- Reachability: Owner-only, unvalidated. It selects the contract every swap asks for a tax tier at `INFTContract` (CauldronHook.sol:1913), so it directly controls what every trader pays, bounded only by the combined clamp at `MAX_TOTAL_FEE_BPS` (CauldronHook.sol:1684).
- Edges: none
- Observations: none

### `setRegistry/function` — CauldronHook.sol:2252

- Signature: `function setRegistry(address _registry) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2252)`
- Reads: `registry (line 2253)`
- Writes: `registry (line 2255)`
- Value: NONE
- Reachability: Owner-only and ONE-SHOT: a second call reverts `RegistryAlreadySet` (CauldronHook.sol:2253) and zero is rejected at `ZeroAddress` (CauldronHook.sol:2254). This is what stops the owner re-pointing the reserve's payee; the only way past it is the delayed override pair.
- Edges: none
- Observations: none

### `proposeRegistryOverride/function` — CauldronHook.sol:2268

- Signature: `function proposeRegistryOverride(address _registry) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2268)`
- Reads: none
- Writes: `pendingRegistry (line 2270)`; `registrySwapReadyAt (line 2271)`
- Value: NONE
- Reachability: Owner-only step one of the controller swap. It arms `pendingRegistry` (CauldronHook.sol:2270) and stamps a deadline of now plus the constant at `REGISTRY_SWAP_DELAY` (CauldronHook.sol:2271); the delay is a constant, so the owner cannot shorten their own notice period. Re-proposing simply overwrites both and restarts the clock.
- Edges: none
- Observations: none

### `cancelRegistryOverride/function` — CauldronHook.sol:2277

- Signature: `function cancelRegistryOverride() external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2277)`
- Reads: none
- Writes: `pendingRegistry (line 2278)`; `registrySwapReadyAt (line 2279)`
- Value: NONE
- Reachability: Owner-only abort of an armed swap; no delay, because it can only ever cancel. It emits the proposal event with zero values at `RegistryOverrideProposed` (CauldronHook.sol:2280), which an indexer must interpret as a cancellation rather than a proposal.
- Edges: none
- Observations: none

### `executeRegistryOverride/function` — CauldronHook.sol:2288

- Signature: `function executeRegistryOverride() external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2288)`
- Reads: `pendingRegistry (line 2289)`; `registrySwapReadyAt (line 2291)`; `relaunchETH (line 2292)`; `relaunchETH (line 2293)`; `registry (line 2295)`
- Writes: `relaunchETH (line 2294)`; `registry (line 2299)`; `pendingRegistry (line 2300)`; `registrySwapReadyAt (line 2301)`
- Value: sends native to the OUTGOING `registry` (line 2295)
- Reachability: Owner-only step two, refused before the deadline at `registrySwapReadyAt` (CauldronHook.sol:2291) — reusing the RegistryAlreadySet error for a timing condition. The whole native reserve is flushed to the OUTGOING registry first, zeroed before the send at `relaunchETH` (CauldronHook.sol:2294), and a failed send reverts the entire swap at `SendFailed` (CauldronHook.sol:2296). The per-asset reserves in `relaunchAsset` (CauldronHook.sol:1974) are NOT flushed, so a non-native reserve survives the controller change and can then only be pulled by the NEW registry.
- Edges: none
- Observations: none

### `setCollection/function` — CauldronHook.sol:2320

- Signature: `function setCollection(address _collection) external`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2321)`
- Reads: `registry (line 2321)`
- Writes: `collection (line 2322)`; `mintBaseline (line 2325)`; `creditEpoch (line 2328)`
- Value: NONE
- Reachability: Registry-only, once per summon or relaunch. The external `totalMinted` (CauldronHook.sol:2327) read is NOT guarded, so a collection that reverts there blocks the whole wiring. Bumping `creditEpoch` (CauldronHook.sol:2328) namespaces credit so the previous generation's balances cannot mint the new collection, and the baseline anchors the rising curve at position zero even for a continued collection.
- Edges: `ICauldronCollection.totalMinted (CauldronHook.sol:2327), UNTRUSTED, out-of-cluster`; `CauldronHook._wireLiquidator (CauldronHook.sol:2331), TRUSTED, in-cluster`
- Observations: none

### `_wireLiquidator/function` — CauldronHook.sol:2342

- Signature: `function _wireLiquidator(address _collection) private`
- Authority: internal (callers: CauldronHook.setCollection, CauldronHook.setPerpEngine)
- Gate evidence: `UNGATED`
- Reads: `perpEngine (line 2343)`; `perpEngine (line 2344)`
- Writes: none
- Value: NONE
- Reachability: Private; reached from `_wireLiquidator` (CauldronHook.sol:2331) and `_wireLiquidator` (CauldronHook.sol:2376). Best-effort: the try/catch at `ICollectionLiquidator` (CauldronHook.sol:2344) means a collection that does not grant the hook this right cannot brick a summon, and equally means a silent failure to wire badges.
- Edges: `ICollectionLiquidator.setLiquidatorMinter (CauldronHook.sol:2344), UNTRUSTED, out-of-cluster`
- Observations: none

### `setVault/function` — CauldronHook.sol:2348

- Signature: `function setVault(address _vault) external`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2349)`
- Reads: `registry (line 2349)`
- Writes: `vault (line 2350)`
- Value: NONE
- Reachability: Registry-only, unvalidated. `vault` (CauldronHook.sol:2350) is a payee: the native floor share is sent there at `routeSplit` (CauldronHook.sol:1639), and clearing it to zero reroutes that share to the legacy buffer or the reserve at `vault` (CauldronHook.sol:1613).
- Edges: none
- Observations: none

### `setQuest/function` — CauldronHook.sol:2354

- Signature: `function setQuest(address _quest) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2355)`
- Reads: `registry (line 2355)`
- Writes: `quest (line 2356)`
- Value: NONE
- Reachability: Owner or registry, unvalidated. The quest contract is called mid-swap with ignored result at `quest` (CauldronHook.sol:1054), but with NO gas cap — unlike the seeder and perp calls — so a hostile quest can burn the swapper's remaining gas.
- Edges: `Ownable.owner (CauldronHook.sol:2355), TRUSTED, out-of-cluster`
- Observations: none

### `setSeeder/function` — CauldronHook.sol:2363

- Signature: `function setSeeder(address _seeder) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2364)`
- Reads: `registry (line 2364)`
- Writes: `seeder (line 2365)`
- Value: NONE
- Reachability: Owner or registry, unvalidated. Setting it turns on the in-swap poke at `s` (CauldronHook.sol:1229); clearing it to zero turns the in-swap nudge off at `s` (CauldronHook.sol:1226) without disabling the seeder's own permissionless path.
- Edges: `Ownable.owner (CauldronHook.sol:2364), TRUSTED, out-of-cluster`
- Observations: none

### `setPerpEngine/function` — CauldronHook.sol:2371

- Signature: `function setPerpEngine(address _engine) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2372)`
- Reads: `registry (line 2372)`; `collection (line 2376)`
- Writes: `perpEngine (line 2373)`
- Value: NONE
- Reachability: Owner or registry, unvalidated. This slot controls the post-trade sweep through `_liqSweep` (CauldronHook.sol:1092), fee routing at `perpEngine` (CauldronHook.sol:1707), the pool-link interlock at `perpEngine` (CauldronHook.sol:1815), and relaunch force-close at `perpEngine` (CauldronHook.sol:2075). Zero disables all four.
- Edges: `Ownable.owner (CauldronHook.sol:2372), TRUSTED, out-of-cluster`; `CauldronHook._wireLiquidator (CauldronHook.sol:2376), TRUSTED, in-cluster`
- Observations: none

### `setFloorBps/function` — CauldronHook.sol:2380

- Signature: `function setFloorBps(uint256 _bps) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2380)`
- Reads: `BPS (line 2381, constant)`
- Writes: `floorBps (line 2382)`
- Value: NONE
- Reachability: Owner-only, bounded at 100 percent by `BPS` (CauldronHook.sol:2381). It splits the post-guild fee between the floor vault and the relaunch reserve at `floorBps` (CauldronHook.sol:1562).
- Edges: none
- Observations: none

### `setGuild/function` — CauldronHook.sol:2387

- Signature: `function setGuild(address _guild) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2388)`
- Reads: `registry (line 2388)`; `guildBps (line 2390)`
- Writes: `guild (line 2389)`
- Value: NONE
- Reachability: Owner or registry, unvalidated. `guild` (CauldronHook.sol:2389) is the recipient of the off-the-top tribute at `guild` (CauldronHook.sol:1560) AND of 100 percent of every anti-sniper surtax at `guild` (CauldronHook.sol:1715), so this one slot can redirect the single largest fee stream at launch.
- Edges: `Ownable.owner (CauldronHook.sol:2388), TRUSTED, out-of-cluster`
- Observations: none

### `setGuildBps/function` — CauldronHook.sol:2399

- Signature: `function setGuildBps(uint256 _bps) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2399)`
- Reads: none
- Writes: `guildBps (line 2401)`
- Value: NONE
- Reachability: Owner-only. The cap is the hard-coded deployed default at `BadParam` (CauldronHook.sol:2400), so the share can be lowered and restored but never raised above it.
- Edges: none
- Observations: none

### `setActiveProposer/function` — CauldronHook.sol:2407

- Signature: `function setActiveProposer(address who) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2408)`
- Reads: `registry (line 2408)`
- Writes: `activeProposer (line 2409)`
- Value: NONE
- Reachability: Owner or registry, unvalidated. The named address accrues a pull-only balance at `proposerOwed` (CauldronHook.sol:1521) on every NATIVE fee; address(0) disables the slice for that iteration at `prop` (CauldronHook.sol:1518).
- Edges: `Ownable.owner (CauldronHook.sol:2408), TRUSTED, out-of-cluster`
- Observations: none

### `setProposerBps/function` — CauldronHook.sol:2414

- Signature: `function setProposerBps(uint256 _bps) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2414)`
- Reads: `MAX_PROPOSER_BPS (line 2415, constant)`
- Writes: `proposerBps (line 2416)`
- Value: NONE
- Reachability: Owner-only, capped at `MAX_PROPOSER_BPS` (CauldronHook.sol:2415) so the slice can never cannibalise the floor or the guild.
- Edges: none
- Observations: none

### `claimProposerFees/function` — CauldronHook.sol:2422

- Signature: `function claimProposerFees() external nonReentrant returns (uint256 amount)`
- Authority: anyone (each caller can only claim their own accrued balance)
- Gate evidence: `UNGATED`
- Reads: `proposerOwed (line 2423)`
- Writes: `proposerOwed (line 2425)`
- Value: sends native to the caller via `call` (line 2426)
- Reachability: Permissionless pull. Guarded by `nonReentrant` (CauldronHook.sol:2422) and written checks-effects-interactions: the balance is zeroed at `proposerOwed` (CauldronHook.sol:2425) before the value-bearing call. An empty balance reverts `NoETHToRelease` (CauldronHook.sol:2424). The ether paid out is the hook's raw balance, which is the same balance backing `relaunchETH` (CauldronHook.sol:1943) and `legacyBuffer` (CauldronHook.sol:1242) — none of those counters is reconciled against the balance.
- Edges: none
- Observations: none

### `setNftCurve/function` — CauldronHook.sol:2432

- Signature: `function setNftCurve(uint256 _base, uint256 _step) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2432)`
- Reads: none
- Writes: `volumePerNFT (line 2434)`; `nftPriceStep (line 2435)`
- Value: NONE
- Reachability: Owner-only; the only bound is a non-zero base at `BadParam` (CauldronHook.sol:2433). It restates the crystal ladder that `volumePerNFT` (CauldronHook.sol:2470) prices against, in whatever unit the volume ledger currently uses.
- Edges: none
- Observations: none

### `setCreditUntaggedSwaps/function` — CauldronHook.sol:2438

- Signature: `function setCreditUntaggedSwaps(bool on) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2438)`
- Reads: none
- Writes: `creditUntaggedSwaps (line 2438)`
- Value: NONE
- Reachability: Owner-only single-slot toggle. When off, an untagged direct swap credits nobody at `creditUntaggedSwaps` (CauldronHook.sol:1023) and therefore also skips the in-swap gacha, since that path only arms for an untagged buyer.
- Edges: none
- Observations: none

### `setNftCurveFrom/function` — CauldronHook.sol:2445

- Signature: `function setNftCurveFrom(uint256 _base) external`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2446)`
- Reads: `registry (line 2446)`
- Writes: `volumePerNFT (line 2448)`; `nftPriceStep (line 2449)`
- Value: NONE
- Reachability: Registry-only, called from a winning proposal's parameters. A zero argument is a no-op at `_base` (CauldronHook.sol:2447) rather than an error, and it forces a FLAT ladder by zeroing the step at `nftPriceStep` (CauldronHook.sol:2449), which is how a mint-out volume target is made exact.
- Edges: none
- Observations: none

### `nftPriceAt/function` — CauldronHook.sol:2453

- Signature: `function nftPriceAt(uint256 k) public view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `curvePolicy (line 2454)`; `volumePerNFT (line 2459)`; `nftPriceStep (line 2459)`; `volumePerNFT (line 2470)`; `nftPriceStep (line 2470)`
- Writes: none
- Value: NONE
- Reachability: Public view, and on the commit path once per crystal. A wired curve policy is asked by a bounded one-word STATICCALL (`valid` CauldronHook.sol:2464); its price is used only if the reply is a full word and nonzero (`c` CauldronHook.sol:2468), because a free crystal would mint without bound, and a reverting, short or zero answer falls back to the linear curve (`nftPriceStep` CauldronHook.sol:2470). There is no upper bound on what a policy may charge.
- Edges: `ICurvePolicy.priceAt (CauldronHook.sol:2459), UNTRUSTED, out-of-cluster`
- Observations: none

### `creditOf/function` — CauldronHook.sol:2474

- Signature: `function creditOf(address player) external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `nftCredit (line 2475)`; `creditEpoch (line 2475)`
- Writes: none
- Value: NONE
- Reachability: External view of the current epoch's balance only; credit from a previous generation still sits in `nftCredit` (CauldronHook.sol:1039) under an older epoch key and is unreadable through this getter.
- Edges: none
- Observations: none

### `_curvePos/function` — CauldronHook.sol:2482

- Signature: `function _curvePos() internal view returns (uint256)`
- Authority: internal (callers: CauldronHook.crystalsReady, CauldronHook.costOfNextCrystals, CauldronHook.progress)
- Gate evidence: `UNGATED`
- Reads: `collection (line 2483)`; `outstandingOf (line 2484)`; `collection (line 2484)`; `mintBaseline (line 2484)`
- Writes: none
- Value: NONE
- Reachability: Internal view; three callers, all views, each of which has already checked that a collection is set. The subtraction of `mintBaseline` (CauldronHook.sol:2484) is unguarded, so it underflows and reverts if the collection's minted count ever drops below the baseline recorded at wiring time.
- Edges: `ICauldronCollection.totalMinted (CauldronHook.sol:2483), UNTRUSTED, out-of-cluster`
- Observations: none

### `crystalsReady/function` — CauldronHook.sol:2488

- Signature: `function crystalsReady(address player) public view returns (uint256 ready)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `collection (line 2489)`; `nftCredit (line 2491)`; `creditEpoch (line 2491)`; `MAX_MINTS_PER_CALL (line 2493, constant)`
- Writes: none
- Value: NONE
- Reachability: Public view for the UI. The loop is bounded by the constant at `MAX_MINTS_PER_CALL` (CauldronHook.sol:2493), so it reports at most 30 even when the player can afford more, and each iteration may make an external policy call through `nftPriceAt` (CauldronHook.sol:2494).
- Edges: `CauldronHook._curvePos (CauldronHook.sol:2490), TRUSTED, in-cluster`; `CauldronHook.nftPriceAt (CauldronHook.sol:2494), TRUSTED, in-cluster`
- Observations: none

### `costOfNextCrystals/function` — CauldronHook.sol:2502

- Signature: `function costOfNextCrystals(uint256 count) public view returns (uint256 cost)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `collection (line 2503)`
- Writes: none
- Value: NONE
- Reachability: Public view. The loop bound is the CALLER-SUPPLIED `count` (CauldronHook.sol:2505) with no cap, so an off-chain caller can ask for an unbounded amount of work; it is a view, so the cost falls on the node answering the query, not on a transaction.
- Edges: `CauldronHook._curvePos (CauldronHook.sol:2504), TRUSTED, in-cluster`; `CauldronHook.nftPriceAt (CauldronHook.sol:2505), TRUSTED, in-cluster`
- Observations: none

### `oddsForPlay/function` — CauldronHook.sol:2511

- Signature: `function oddsForPlay(uint256 playWei) public view returns (uint256 bps)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `oddsPolicy (line 2512)`; `maxOddsBps (line 2514)`; `oddsFullVolumeWei (line 2514)`; `ODDS_HARD_CAP_BPS (line 2516, constant)`; `oddsFullVolumeWei (line 2519)`; `maxOddsBps (line 2519)`; `maxOddsBps (line 2520)`; `oddsFullVolumeWei (line 2520)`
- Writes: none
- Value: NONE
- Reachability: Public view, also called once per commit at `oddsForPlay` (CauldronHook.sol:2626) and cast to uint16 there. A zero full-play size short-circuits to the maximum at `oddsFullVolumeWei` (CauldronHook.sol:2519). The linear scale rounds DOWN at `bps` (CauldronHook.sol:2520), so a play below one ten-thousandth of the full size rolls zero odds, and any policy answer is clamped to the hard cap.
- Edges: `IOddsPolicy.oddsBps (CauldronHook.sol:2514), UNTRUSTED, out-of-cluster`
- Observations: none

### `outstandingTickets/function` — CauldronHook.sol:2525

- Signature: `function outstandingTickets() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `gacha (line 2526)`
- Writes: none
- Value: NONE
- Reachability: External view alias over the same global `gacha` counter (CauldronHook.sol:2526) exposed by outstandingCrystals.
- Edges: none
- Observations: none

### `mintedOut/function` — CauldronHook.sol:2530

- Signature: `function mintedOut() external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `collection (line 2531)`; `collection (line 2532)`; `collection (line 2533)`
- Writes: none
- Value: NONE
- Reachability: External view; two external calls, neither guarded, so a reverting collection makes this revert rather than report. It ignores the reserved crystals counted at `outstandingOf` (CauldronHook.sol:2597), so it can report not-minted-out while every remaining slot is already spoken for.
- Edges: `ICauldronCollection.totalMinted (CauldronHook.sol:2532), UNTRUSTED, out-of-cluster`; `ICauldronCollection.maxSupply (CauldronHook.sol:2533), UNTRUSTED, out-of-cluster`
- Observations: none

### `progress/function` — CauldronHook.sol:2540

- Signature: `function progress(address player) external view returns (uint256 inCurrent, uint256 threshold, uint256 ready)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `collection (line 2545)`; `nftCredit (line 2547)`; `creditEpoch (line 2547)`; `MAX_MINTS_PER_CALL (line 2549, constant)`
- Writes: none
- Value: NONE
- Reachability: External view for the UI; duplicates the loop in `crystalsReady` (CauldronHook.sol:2488) and additionally prices the next unaffordable crystal at `threshold` (CauldronHook.sol:2555). Same 30-iteration bound.
- Edges: `CauldronHook.nftPriceAt (CauldronHook.sol:2545), TRUSTED, in-cluster`; `CauldronHook._curvePos (CauldronHook.sol:2546), TRUSTED, in-cluster`; `CauldronHook.nftPriceAt (CauldronHook.sol:2550), TRUSTED, in-cluster`; `CauldronHook.nftPriceAt (CauldronHook.sol:2555), TRUSTED, in-cluster`
- Observations: none

### `commitCrystals/function` — CauldronHook.sol:2567

- Signature: `function commitCrystals(address player, uint256 maxCount, uint256 playWei) external nonReentrant returns (uint256 n)`
- Authority: opener (an address flagged in isOpener)
- Gate evidence: `if (!isOpener[msg.sender]) revert NotOpener(); (CauldronHook.sol:2572)`
- Reads: `isOpener (line 2572)`
- Writes: none
- Value: NONE
- Reachability: Only an allow-listed opener may call it, which is what keeps the play size honest — `playWei` (CauldronHook.sol:2567) is supplied by the caller and feeds the odds directly, so an unrestricted caller could claim any play size. Guarded by `nonReentrant` (CauldronHook.sol:2569), which shares one guard with the resolve path and the in-swap gacha. The player is also caller-supplied, so an opener can commit on anyone's behalf and spend THAT player's credit.
- Edges: `CauldronHook._commitCrystals (CauldronHook.sol:2581), TRUSTED, in-cluster`
- Observations: none

### `_commitCrystals/function` — CauldronHook.sol:2587

- Signature: `function _commitCrystals(address player, uint256 maxCount, uint256 playWei) internal returns (uint256 n)`
- Authority: internal (callers: CauldronHook.commitCrystals and CauldronHook.nativeGachaStep)
- Gate evidence: `UNGATED`
- Reads: `collection (line 2591)`; `outstandingOf (line 2597)`; `mintBaseline (line 2604)`; `creditEpoch (line 2605)`; `nftCredit (line 2606)`; `MAX_MINTS_PER_CALL (line 2608, constant)`
- Writes: `nftCredit (line 2620)`; `committedOf (line 2621)`; `pendingOf (line 2622)`; `gacha (line 2623)`; `outstandingOf (line 2624)`; `batches (line 2627)`
- Value: NONE
- Reachability: Shared commit body. Remaining supply is conservatively reduced by all `outstandingOf` (CauldronHook.sol:2597), and zero room returns without reverting. Curve position includes reserved crystals at `startPos` (CauldronHook.sol:2604). The affordability loop is bounded by caller max, remaining room, and `MAX_MINTS_PER_CALL` (CauldronHook.sol:2608). Credit and five reservation counters are updated before appending the batch; `n` is also clamped to uint16 at `type` (CauldronHook.sol:2618).
- Edges: `ICauldronCollection.totalMinted (CauldronHook.sol:2593), UNTRUSTED, out-of-cluster`; `ICauldronCollection.maxSupply (CauldronHook.sol:2594), UNTRUSTED, out-of-cluster`; `CauldronHook.nftPriceAt (CauldronHook.sol:2609), TRUSTED, in-cluster`; `CauldronHook.oddsForPlay (CauldronHook.sol:2626), TRUSTED, in-cluster`
- Observations: none

### `resolveTickets/function` — CauldronHook.sol:2647

- Signature: `function resolveTickets(uint256 maxCount) public nonReentrant returns (uint256 processed, uint256 won)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Permissionless keeper entrypoint, guarded by `nonReentrant` (CauldronHook.sol:2649). The gacha router calls it right after committing, and anyone may call it at any time; the caller chooses `maxCount` (CauldronHook.sol:2647), which is the loop bound.
- Edges: `CauldronHook._resolveTickets (CauldronHook.sol:2652), TRUSTED, in-cluster`
- Observations: none

### `_resolveTickets/function` — CauldronHook.sol:2659

- Signature: `function _resolveTickets(uint256 maxCount) internal returns (uint256 processed, uint256 won)`
- Authority: internal (callers: CauldronHook.resolveTickets and CauldronHook.nativeGachaStep)
- Gate evidence: `UNGATED`
- Reads: `batches (line 2667)`; `missStreak (line 2667)`; `pendingOf (line 2667)`; `outstandingOf (line 2667)`; `opened (line 2667)`; `gacha (line 2667)`; `pityThreshold (line 2667)`
- Writes: `batches (line 2667)`; `missStreak (line 2667)`; `pendingOf (line 2667)`; `outstandingOf (line 2667)`; `opened (line 2667)`; `gacha (line 2667)`
- Value: NONE
- Reachability: Internal wrapper reached by permissionless resolve through `_resolveTickets` (CauldronHook.sol:2652) and the self-only native step. It delegatecalls linked `GachaLib.resolveTickets` (CauldronHook.sol:2666), passing every mutable collection as a storage reference, including both scalar counters grouped in `gacha` (CauldronHook.sol:2667).
- Edges: `GachaLib.resolveTickets (CauldronHook.sol:2666), TRUSTED, library`
- Observations: none

### `nativeGachaStep/function` — CauldronHook.sol:2677

- Signature: `function nativeGachaStep(address player, uint256 playWei) external nonReentrant`
- Authority: hook itself (self-call only)
- Gate evidence: `if (msg.sender != address(this)) revert OnlySelf(); (CauldronHook.sol:2678)`
- Reads: `NATIVE_COMMIT_MAX (line 2679, constant)`; `NATIVE_RESOLVE_MAX (line 2680, constant)`
- Writes: none
- Value: NONE
- Reachability: External but self-only; the sole reachable caller is the gas-capped self `call` (CauldronHook.sol:1105) at the tail of afterSwap, whose result is discarded. `nonReentrant` (CauldronHook.sol:2677) shares the guard with the commit and resolve entrypoints, so a mint callback cannot re-enter either. The play size passed in is the weighted volume computed in afterSwap, i.e. already in the ledger's unit rather than raw ether.
- Edges: `CauldronHook._commitCrystals (CauldronHook.sol:2679), TRUSTED, in-cluster`; `CauldronHook._resolveTickets (CauldronHook.sol:2680), TRUSTED, in-cluster`
- Observations: none

### `setOpener/function` — CauldronHook.sol:2686

- Signature: `function setOpener(address who, bool allowed) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2687)`
- Reads: `registry (line 2687)`
- Writes: `isOpener (line 2688)`
- Value: NONE
- Reachability: Owner or registry. An opener gets three powers at once: it may commit crystals for any player at `isOpener` (CauldronHook.sol:2572), its hookData tag is believed for tax tiering at `isOpener` (CauldronHook.sol:2719), and its tag is believed for fee exemption at `isOpener` (CauldronHook.sol:2711).
- Edges: `Ownable.owner (CauldronHook.sol:2687), TRUSTED, out-of-cluster`
- Observations: none

### `setTaxExempt/function` — CauldronHook.sol:2696

- Signature: `function setTaxExempt(address who, bool exempt) external`
- Authority: owner or registry
- Gate evidence: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2697)`
- Reads: `registry (line 2697)`
- Writes: `taxExempt (line 2698)`
- Value: NONE
- Reachability: Owner or registry. Exemption alone is not enough to dodge the fee: the swap must ALSO arrive from a trusted opener, per the conjunction at `isOpener` (CauldronHook.sol:2711), so a direct swapper cannot self-tag as exempt.
- Edges: `Ownable.owner (CauldronHook.sol:2697), TRUSTED, out-of-cluster`
- Observations: none

### `_isExemptPlayer/function` — CauldronHook.sol:2710

- Signature: `function _isExemptPlayer(address sender, bytes calldata hookData) private view returns (bool)`
- Authority: internal (callers: CauldronHook._beforeSwap, CauldronHook._afterSwap)
- Gate evidence: `UNGATED`
- Reads: `taxExempt (line 2711)`; `isOpener (line 2711)`
- Writes: none
- Value: NONE
- Reachability: Private view on both fee legs, at `_isExemptPlayer` (CauldronHook.sol:1423) and `_isExemptPlayer` (CauldronHook.sol:1130). Exemption requires BOTH a flagged player and a trusted sender, so the hookData tag is only honoured from an opener.
- Edges: `CauldronHook._taxedPlayer (CauldronHook.sol:2711), TRUSTED, in-cluster`
- Observations: none

### `_taxedPlayer/function` — CauldronHook.sol:2718

- Signature: `function _taxedPlayer(address sender, bytes calldata hookData) private view returns (address)`
- Authority: internal (callers: CauldronHook._isExemptPlayer, CauldronHook._takeEthFee)
- Gate evidence: `UNGATED`
- Reads: `isOpener (line 2719)`
- Writes: none
- Value: NONE
- Reachability: Private view; the identity resolver used for both tiering at `_taxedPlayer` (CauldronHook.sol:1681) and exemption at `_taxedPlayer` (CauldronHook.sol:2711). A non-opener sender is always taxed as itself; an opener may name any player, and a zero decode falls back to the sender at `p` (CauldronHook.sol:2721).
- Edges: none
- Observations: none

### `setOddsParams/function` — CauldronHook.sol:2726

- Signature: `function setOddsParams(uint256 fullVolumeWei, uint256 pity) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2726)`
- Reads: none
- Writes: `oddsFullVolumeWei (line 2727)`; `pityThreshold (line 2728)`
- Value: NONE
- Reachability: Owner-only and unbounded on both arguments: `oddsFullVolumeWei` (CauldronHook.sol:2727) may be zero, making every play use maximum odds at `oddsFullVolumeWei` (CauldronHook.sol:2519), while a zero `pityThreshold` is passed into library resolution through `pityThreshold` (CauldronHook.sol:2667) and forces each non-sold-out ticket to win (DERIVED).
- Edges: none
- Observations: none

### `setMaxOdds/function` — CauldronHook.sol:2733

- Signature: `function setMaxOdds(uint256 bps) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2733)`
- Reads: `ODDS_HARD_CAP_BPS (line 2734, constant)`
- Writes: `maxOddsBps (line 2735)`
- Value: NONE
- Reachability: Owner-only, capped at `ODDS_HARD_CAP_BPS` (CauldronHook.sol:2734) so bet size alone can never guarantee a creature; only the pity counter can.
- Edges: none
- Observations: none

### `setWeights/function` — CauldronHook.sol:2739

- Signature: `function setWeights(uint256 buyBps, uint256 sellBps) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronHook.sol:2739)`
- Reads: `MAX_WEIGHT_BPS (line 2740, constant)`
- Writes: `buyWeightBps (line 2741)`; `sellWeightBps (line 2742)`
- Value: NONE
- Reachability: Owner-only, each side capped at `MAX_WEIGHT_BPS` (CauldronHook.sol:2740). These multiply the recorded volume into crystal credit at `buyWeightBps` (CauldronHook.sol:1035), so raising them accelerates mint-out for every trader at once.
- Edges: none
- Observations: none

### `receive/receive` — CauldronHook.sol:2794

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native via `receive` (line 2794)
- Reachability: Empty payable fallback-style receiver. It records NOTHING, deliberately: ether arriving here — including the pool manager's payouts and any stray transfer — must not be counted into `legacyBuffer` (CauldronHook.sol:1321), which is why donations have their own entrypoint. Anything sent here silently increases the raw balance behind the counters without increasing any of them.
- Edges: none
- Observations: none


## `DefaultFeeRouter`

### `route/function` — DefaultFeeRouter.sol:21

- Signature: `function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256 floorBps) external pure returns (uint256 toGuild, uint256 toFloor, uint256 toRelaunch)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `BPS (line 26, constant)`; `BPS (line 46, constant)`
- Writes: none
- Value: NONE
- Reachability: External pure split. `toGuild` (DefaultFeeRouter.sol:26) is guild-gated; floor share deliberately ignores the vault address at `toFloor` (DefaultFeeRouter.sol:46) so a zero-vault unified-floor deployment still receives buy-pressure allocation. `toRelaunch` (DefaultFeeRouter.sol:47) takes the exact remainder.
- Edges: none
- Observations: none


## `FeeRouteLib`

### `routeSplit/function` — FeeRouteLib.sol:48

- Signature: `function routeSplit( address asset, address guild, address vault, uint256 toGuild, uint256 toFloor ) external returns (uint256 leftover)`
- Authority: internal to the hook via delegatecall (callers: CauldronHook._routeEthFee, CauldronHook._takeEthFee); the deployed library address is callable by anyone but holds no state and no funds
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: no direct transfer; value leaves through `_fundGuild` (FeeRouteLib.sol:64) and `_move` (FeeRouteLib.sol:68)
- Reachability: Declared `external` (FeeRouteLib.sol:54) in a library, so it is delegatecalled and runs in the hook's context: the ether sent is the hook's and the tokens moved are the hook's. Three call sites, all inside the swap: `routeSplit` (CauldronHook.sol:1639) for the ordinary fee split, `routeSplit` (CauldronHook.sol:1715) for the anti-sniper surtax, and nothing else. Both call sites reach it only after the hook has already taken the fee, so the authority is whatever reached `_takeEthFee` (CauldronHook.sol:1668) — the pool manager driving before/afterSwap. Nothing here reverts: a guild or vault that refuses is reported by returning the undelivered amount as `leftover` (FeeRouteLib.sol:65), which the caller books into the reserve.
- Edges: `FeeRouteLib._fundGuild (FeeRouteLib.sol:64), TRUSTED, library`; `FeeRouteLib._move (FeeRouteLib.sol:68), TRUSTED, library`
- Observations: none

### `routePerp/function` — FeeRouteLib.sol:79

- Signature: `function routePerp( address asset, address guild, address engine, uint256 toGuild, uint256 toStakers, bytes4 nativeSel, bytes4 assetSel ) external returns (uint256 leftover)`
- Authority: internal to the hook via delegatecall (caller: CauldronHook._routePerpFee); the deployed library address is callable by anyone but holds no state and no funds
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: no direct transfer; value leaves through `_fundGuild` (FeeRouteLib.sol:97) and `_deliver` (FeeRouteLib.sol:100)
- Reachability: Delegatecalled from the single site `routePerp` (CauldronHook.sol:1457), which is reached only when the swapper is the perp engine — the branch at `perpEngine` (CauldronHook.sol:1707). The guild share goes through the accounted path and the staker share through `_deliver` (FeeRouteLib.sol:100), which picks the native selector or the ERC20 pull selector the caller passed in. Neither failure reverts: both undelivered shares accumulate into `leftover` (FeeRouteLib.sol:101) and the hook credits them to the reserve.
- Edges: `FeeRouteLib._fundGuild (FeeRouteLib.sol:97), TRUSTED, library`; `FeeRouteLib._deliver (FeeRouteLib.sol:100), TRUSTED, library`
- Observations: none

### `_move/function` — FeeRouteLib.sol:105

- Signature: `function _move(address asset, address to, uint256 amount) private returns (bool ok)`
- Authority: internal (caller: FeeRouteLib.routeSplit)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native to `to` (line 117), or asks `asset` (line 118) to transfer the ERC20 amount to the encoded recipient
- Reachability: Private delivery helper. It rejects a codeless destination at `code` (FeeRouteLib.sol:116) before either branch, preventing a successful native transfer to a mistyped EOA from being reported as floor funding. Native and token failures return false; ERC20 empty returns are accepted and bool returns decoded.
- Edges: `IERC20.transfer (FeeRouteLib.sol:119), UNTRUSTED, out-of-cluster`
- Observations: none

### `_fundGuild/function` — FeeRouteLib.sol:139

- Signature: `function _fundGuild(address asset, address guild, uint256 amount) private returns (bool ok)`
- Authority: internal (callers: FeeRouteLib.routeSplit, FeeRouteLib.routePerp)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native to the guild at `guild` (line 157); ERC20 approve of `asset` (line 158) then a pull by `guild` (line 160)
- Reachability: Private; reached from `_fundGuild` (FeeRouteLib.sol:64) and `_fundGuild` (FeeRouteLib.sol:97). A CODELESS RECIPIENT IS REFUSED BEFORE EITHER BRANCH: the guard at `guild` (FeeRouteLib.sol:156) returns false without moving anything, which covers the native leg as well as the ERC20 one - the earlier form guarded only the token path, and on the native path a `call{value:}` to a codeless address succeeds, so the ether left and the caller was told the guild was funded. On false the caller books the share to the relaunch reserve at `leftover` (FeeRouteLib.sol:65). Native uses the guild's bare receive at `guild` (FeeRouteLib.sol:157); an ERC20 is approved and then pulled by `fundToken` (FeeRouteLib.sol:160) so the dividend can account for it. The approval is only cleared when the pull reports failure at `ok` (FeeRouteLib.sol:162); a pull that succeeds but consumes less than the approved amount leaves the remainder standing. Every call's result is captured rather than bubbled, so this can never revert the swap that produced the fee.
- Edges: `IERC20.approve (FeeRouteLib.sol:158), UNTRUSTED, out-of-cluster`; `MiFrensDividend.fundToken (FeeRouteLib.sol:160), UNTRUSTED, out-of-cluster`; `IERC20.approve (FeeRouteLib.sol:162), UNTRUSTED, out-of-cluster`
- Observations: none

### `_deliver/function` — FeeRouteLib.sol:165

- Signature: `function _deliver(address asset, address to, uint256 amount, bytes4 nativeSel, bytes4 assetSel) private returns (bool ok)`
- Authority: internal (callers: FeeRouteLib.routePerp)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native to the engine at `to` (line 181); ERC20 approve of `asset` (line 184) then a pull by `to` (line 186)
- Reachability: Private; the only call site is `_deliver` (FeeRouteLib.sol:100). A CODELESS RECIPIENT IS REFUSED BEFORE EITHER BRANCH at `to` (FeeRouteLib.sol:179), so no value moves and the caller rolls the staker share into the relaunch reserve at `leftover` (FeeRouteLib.sol:101); on the native leg that is the difference between ether sitting at a codeless address and ether staying in the hook. The selectors are supplied by the caller, so the target entrypoint is chosen at the hook: `nativeSel` (FeeRouteLib.sol:181) for a value-bearing call and `assetSel` (FeeRouteLib.sol:186) for the pull. The dangling-approval cleanup at `approve` (FeeRouteLib.sol:189) runs only on failure. Results are captured, never bubbled.
- Edges: `IERC20.approve (FeeRouteLib.sol:184), UNTRUSTED, out-of-cluster`; `IERC20.approve (FeeRouteLib.sol:189), UNTRUSTED, out-of-cluster`
- Observations: none

### `send/function` — FeeRouteLib.sol:201

- Signature: `function send(address asset, address to, uint256 amount, uint256 gasCap) external returns (bool ok)`
- Authority: internal to the hook via delegatecall (caller: CauldronHook.releaseRelaunchAsset); the deployed library address is callable by anyone but holds no state and no funds
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native to `to` (line 207); sends native with a gas cap to `to` (line 208); ERC20 transfer encoded against `asset` (line 214)
- Reachability: The single in-tree call site is `send` (CauldronHook.sol:1975) inside the registry-gated non-native release, which passes `gasCap` (FeeRouteLib.sol:201) as 0, i.e. the unbounded native branch. A zero amount reports success without moving anything at `amount` (FeeRouteLib.sol:205). The ERC20 branch checks the return payload at `abi` (FeeRouteLib.sol:217), which is what lets the caller keep its counter intact when a token returns false.
- Edges: `IERC20.transfer (FeeRouteLib.sol:215), UNTRUSTED, out-of-cluster`
- Observations: none

### `deliver/function` — FeeRouteLib.sol:231

- Signature: `function deliver( address asset, address to, uint256 amount, bytes4 nativeSelector, bytes4 selector ) external returns (bool ok)`
- Authority: internal to the hook via delegatecall; NO caller anywhere in the source tree
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native to `to` (line 251); ERC20 approve of `asset` (line 254) then a pull by `to` (line 258)
- Reachability: Unreachable from the protocol: `deliver` (FeeRouteLib.sol:231) has no call site in any non-test source file (DERIVED); the perp fee path uses the private `_deliver` (FeeRouteLib.sol:165). It refuses codeless recipients (`to` FeeRouteLib.sol:249) and short-circuits zero amounts (`amount` FeeRouteLib.sol:238). After the recipient's pull the approval is reset to zero unconditionally (`approve` FeeRouteLib.sol:277), so a pull that took less than the full amount leaves no standing allowance.
- Edges: `IERC20.approve (FeeRouteLib.sol:255), UNTRUSTED, out-of-cluster`; `IERC20.approve (FeeRouteLib.sol:277), UNTRUSTED, out-of-cluster`
- Observations: none


## `LegacyBuyLib`

### `buyStep/function` — LegacyBuyLib.sol:132

- Signature: `function buyStep(IPoolManager poolManager, PoolKey calldata key, uint256 amt, uint256 encumbered) external returns (uint256 spent, uint256 got)`
- Authority: anyone at the linked library address; in protocol delegatecalled only from CauldronHook.legacyBuyStep
- Gate evidence: `UNGATED`
- Reads: `SLIP_SQRT_BPS (line 207, constant)`; `MIN_SQRT_LIMIT (line 209, constant)`
- Writes: none
- Value: sends native to `poolManager` (LegacyBuyLib.sol:266), or transfers ERC20 quote to it at `call` (LegacyBuyLib.sol:275), then takes bought currency1 to this delegated context at `take` (LegacyBuyLib.sol:280)
- Reachability: The hook delegatecalls this linked library, so balances and the namespaced reference belong to the hook. Spend is clamped to unencumbered balance at `free` (LegacyBuyLib.sol:146). `_syncRef` (LegacyBuyLib.sol:203) seeds without spending and thereafter moves at most the per-block tick bound. The sqrt limit uses the larger of spot and reference at `lim` (LegacyBuyLib.sol:207); an unreachable limit returns zero before opening deltas. It settles the realized debit at `spent` (LegacyBuyLib.sol:227), rejects zero output, enforces a FullMath-derived minimum at `Slipped` (LegacyBuyLib.sol:263), checks ERC20 return data, and takes output only after settlement.
- Edges: `IERC20.balanceOf (LegacyBuyLib.sol:145), UNTRUSTED, out-of-cluster`; `StateLibrary.getSlot0 (LegacyBuyLib.sol:157), TRUSTED, out-of-cluster`; `LegacyBuyLib._syncRef (LegacyBuyLib.sol:203), TRUSTED, in-cluster`; `TickMath.getSqrtPriceAtTick (LegacyBuyLib.sol:206), TRUSTED, library`; `IPoolManager.swap (LegacyBuyLib.sol:212), TRUSTED, out-of-cluster`; `FullMath.mulDiv (LegacyBuyLib.sol:262), TRUSTED, library`; `IPoolManager.settle (LegacyBuyLib.sol:266), TRUSTED, out-of-cluster`; `IPoolManager.sync (LegacyBuyLib.sol:268), TRUSTED, out-of-cluster`; `IERC20.transfer (LegacyBuyLib.sol:275), UNTRUSTED, out-of-cluster`; `IPoolManager.settle (LegacyBuyLib.sol:277), TRUSTED, out-of-cluster`; `IPoolManager.take (LegacyBuyLib.sol:280), TRUSTED, out-of-cluster`
- Observations: none

### `_syncRef/function` — LegacyBuyLib.sol:309

- Signature: `function _syncRef(PoolId pid, int24 tick) private returns (int24 ref, bool seeded)`
- Authority: internal (caller: LegacyBuyLib.buyStep)
- Gate evidence: `UNGATED`
- Reads: `REF_SLOT (line 310, constant)`; `MAX_TICK_DEV (line 324, constant)`
- Writes: none
- Value: NONE
- Reachability: Private price-reference synchronizer reached at `_syncRef` (LegacyBuyLib.sol:203). It reads and writes a keccak-namespaced slot in the delegating hook with `sload` (LegacyBuyLib.sol:312) and `sstore` (LegacyBuyLib.sol:337), rather than a declared library storage variable. A virgin reference is marked with `VIRGIN_BIT` (LegacyBuyLib.sol:321); later blocks clamp tick movement to `MAX_TICK_DEV` (LegacyBuyLib.sol:324), while same-block calls report whether the reference was born in that block.
- Edges: none
- Observations: none


## `ReserveLib`

### `_alignDown/function` — ReserveLib.sol:27

- Signature: `function _alignDown(int24 tick, int24 spacing) internal pure returns (int24)`
- Authority: internal (callers: ReserveLib.reserveTicks)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure helper, inlined into every importer. In-tree the only call site is `_alignDown` (ReserveLib.sol:55) inside `reserveTicks` (ReserveLib.sol:50); the library itself is imported by PoolOps, outside this cluster (DERIVED). Integer division truncates toward zero, so the negative branch subtracts one to floor toward minus infinity.
- Edges: none
- Observations: none

### `_alignUp/function` — ReserveLib.sol:34

- Signature: `function _alignUp(int24 tick, int24 spacing) internal pure returns (int24)`
- Authority: internal (callers: ReserveLib.reserveTicks)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure helper, reached from `_alignUp` (ReserveLib.sol:59) inside `reserveTicks` (ReserveLib.sol:50). Mirrors the down-alignment: the positive branch adds one so the result rounds toward plus infinity.
- Edges: none
- Observations: none

### `reserveTicks/function` — ReserveLib.sol:50

- Signature: `function reserveTicks(int24 launchTick, int24 spacing, int24 offset) internal pure returns (int24 tickLower, int24 tickUpper)`
- Authority: internal (callers: out-of-cluster PoolOps)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure tick math with no state and no external calls. Nothing in this cluster calls `reserveTicks` (ReserveLib.sol:50); the callers are in PoolOps and RedemptionExt, outside the cluster (DERIVED). `tickUpper` (ReserveLib.sol:55) is the launch tick less the ceiling offset aligned down, `tickLower` (ReserveLib.sol:59) is the minimum usable aligned tick, and a degenerate ordering collapses to a one-spacing band at `tickUpper` (ReserveLib.sol:64).
- Edges: `ReserveLib._alignDown (ReserveLib.sol:55), TRUSTED, library`; `ReserveLib._alignUp (ReserveLib.sol:59), TRUSTED, library`
- Observations: none

### `liquidityForTokenOut/function` — ReserveLib.sol:75

- Signature: `function liquidityForTokenOut(int24 tickLower, int24 tickUpper, uint256 amount1) internal pure returns (uint128 liquidity)`
- Authority: internal (callers: out-of-cluster PoolOps)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure. No caller inside this cluster (DERIVED). It forwards to the v4-periphery helper at `LiquidityAmounts` (ReserveLib.sol:80) with the two tick prices from `TickMath` (ReserveLib.sol:81) and `TickMath` (ReserveLib.sol:82); those symbols live under lib/ and so are not edges the graph can resolve. Rounding is whatever `getLiquidityForAmount1` (ReserveLib.sol:80) does, which the doc comment states is DOWN.
- Edges: none
- Observations: none

### `tokenOutForLiquidity/function` — ReserveLib.sol:96

- Signature: `function tokenOutForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity) internal pure returns (uint256 amount1)`
- Authority: internal (callers: out-of-cluster PoolOps)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure inverse of the sizing helper; no in-cluster caller (DERIVED). Zero liquidity short-circuits at `liquidity` (ReserveLib.sol:101); otherwise it reads two tick prices via `TickMath` (ReserveLib.sol:102) and `TickMath` (ReserveLib.sol:103) and divides by the Q96 scale with `FullMath` (ReserveLib.sol:105), which truncates (rounds down).
- Edges: none
- Observations: none


## `ILegacyBuffer (declared in RoyaltyRouter.sol)`

### `fundLegacyBuffer/function` — RoyaltyRouter.sol:5

- Signature: `function fundLegacyBuffer() external payable`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only. Both in-cluster dispatches use `fundLegacyBuffer` (RoyaltyRouter.sol:91) or `fundLegacyBuffer` (RoyaltyRouter.sol:108) against immutable `hook` (RoyaltyRouter.sol:91); the implementation is `fundLegacyBuffer` (CauldronHook.sol:1288).
- Edges: none
- Observations: none


## `IAdoptable (declared in RoyaltyRouter.sol)`

### `adopt/function` — RoyaltyRouter.sol:9

- Signature: `function adopt(address asset) external returns (uint256)`
- Authority: interface declaration (no body in this cluster)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration used as the advisory booking callback from `adopt` (RoyaltyRouter.sol:122) after ERC20 delivery.
- Edges: none
- Observations: none


## `RoyaltyRouter`

### `constructor/constructor` — RoyaltyRouter.sol:77

- Signature: `constructor(address _hook, address _erc20Sink)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `hook (line 79, immutable)`; `erc20Sink (line 80, immutable)`
- Value: NONE
- Reachability: Constructor rejects a zero `hook` (RoyaltyRouter.sol:78), freezes it, and freezes `erc20Sink` (RoyaltyRouter.sol:80) to the supplied receiver or the hook fallback. Neither destination can later be redirected.
- Edges: none
- Observations: none

### `receive/receive` — RoyaltyRouter.sol:83

- Signature: `receive() external payable`
- Authority: anyone sending native currency
- Gate evidence: `UNGATED`
- Reads: `FORWARD_GAS_FLOOR (line 90, constant)`; `hook (line 91, immutable)`
- Writes: none
- Value: receives native; best-effort sends `msg.value` to `hook` (line 91)
- Reachability: Plain-payable royalty path. Zero-value and stipend-limited calls return at `msg` (RoyaltyRouter.sol:84) and `FORWARD_GAS_FLOOR` (RoyaltyRouter.sol:90), retaining funds for sweep. With enough gas it attempts the immutable hook through `call` (RoyaltyRouter.sol:91) and deliberately ignores failure so a royalty receiver cannot revert the marketplace sale.
- Edges: `ILegacyBuffer.fundLegacyBuffer (RoyaltyRouter.sol:91), UNTRUSTED, out-of-cluster`
- Observations: none

### `sweep/function` — RoyaltyRouter.sol:101

- Signature: `function sweep(address asset) external returns (uint256 amount)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `hook (line 108, immutable)`; `erc20Sink (line 113, immutable)`
- Writes: none
- Value: sends held native to `hook` (line 108), or all held `asset` through `_safeTransfer` (line 116) to the immutable-derived recipient
- Reachability: Permissionless recovery with no caller-chosen destination. Native sweep sends the full balance to immutable `hook` (RoyaltyRouter.sol:108) and bubbles failure. ERC20 sweep measures the full balance, transfers to immutable `erc20Sink` (RoyaltyRouter.sol:113), then makes a caught advisory `adopt` call (RoyaltyRouter.sol:122); callback failure cannot undo delivery.
- Edges: `ILegacyBuffer.fundLegacyBuffer (RoyaltyRouter.sol:108), TRUSTED, in-cluster`; `RoyaltyRouter._balanceOf (RoyaltyRouter.sol:114), TRUSTED, in-cluster`; `RoyaltyRouter._safeTransfer (RoyaltyRouter.sol:116), TRUSTED, in-cluster`; `IAdoptable.adopt (RoyaltyRouter.sol:122), TRUSTED, in-cluster`
- Observations: none

### `_balanceOf/function` — RoyaltyRouter.sol:126

- Signature: `function _balanceOf(address asset) private view returns (uint256)`
- Authority: internal (caller: RoyaltyRouter.sweep)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Private balance probe. It invokes caller-selected `asset` through `staticcall` (RoyaltyRouter.sol:128) and requires both success and a full word before decoding, so malformed tokens fail the sweep without moving value.
- Edges: `IERC20.balanceOf (RoyaltyRouter.sol:128), UNTRUSTED, out-of-cluster`
- Observations: none

### `_safeTransfer/function` — RoyaltyRouter.sol:134

- Signature: `function _safeTransfer(address asset, address to, uint256 amount) private`
- Authority: internal (caller: RoyaltyRouter.sweep)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: ERC20 transfer of `asset` to immutable-derived `to` (line 136)
- Reachability: Private ERC20 push. The low-level `call` (RoyaltyRouter.sol:136) accepts an empty return or true and otherwise reverts, so sweep cannot emit success without a conforming delivery signal.
- Edges: `IERC20.transfer (RoyaltyRouter.sol:136), UNTRUSTED, out-of-cluster`
- Observations: none


## `SurtaxLib`

### `surtaxBps/function` — SurtaxLib.sol:33

- Signature: `function surtaxBps( address pol, PoolId id, uint256 start, uint256 maxBps, uint256 window, uint256 hardCap ) external view returns (uint256)`
- Authority: anyone at the linked library address; hook calls it as its fallback surtax policy wrapper
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: External view wrapper. A nonzero caller-supplied policy is queried by a bounded one-word STATICCALL (`valid` SurtaxLib.sol:53); a full reply is clamped to `hardCap` (SurtaxLib.sol:56). A zero policy, a revert or a short reply falls through to the built-in curve (`defaultSurtaxBps` SurtaxLib.sol:58).
- Edges: `ISurtaxPolicy.surtaxBps (SurtaxLib.sol:46), UNTRUSTED, out-of-cluster`; `SurtaxLib.defaultSurtaxBps (SurtaxLib.sol:58), TRUSTED, in-cluster`
- Observations: none

### `defaultSurtaxBps/function` — SurtaxLib.sol:62

- Signature: `function defaultSurtaxBps(PoolId id, uint256 maxBps, uint256 window, uint256 start) public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Public view built-in curve. Disabled or unknown inputs return zero at `start` (SurtaxLib.sol:67), elapsed windows return zero, deterministic decay floors division at `decayed` (SurtaxLib.sol:73), and block-derived jitter is added then clamped at `maxBps` (SurtaxLib.sol:134). The caller can observe current-block output before trading; the guaranteed component is the deterministic decay, not unpredictability after inclusion (DERIVED).
- Edges: none
- Observations: none


## `BaseHook`

### `constructor/constructor` — BaseHook.sol:18

- Signature: `constructor(IPoolManager _manager) ImmutableState(_manager)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Runs once, as part of CauldronHook's construction (`BaseHook` (CauldronHook.sol:611) is its base initialiser). It stores the manager in the v4-periphery `ImmutableState` (BaseHook.sol:18) base and then calls `validateHookAddress` (BaseHook.sol:19), which reverts unless the deployed address' low bits match the permission struct — this is what forces the salt mining.
- Edges: `BaseHook.validateHookAddress (BaseHook.sol:19), TRUSTED, in-cluster`
- Observations: none

### `getHookPermissions/function` — BaseHook.sol:25

- Signature: `function getHookPermissions() public pure virtual returns (Hooks.Permissions memory)`
- Authority: anyone (abstract declaration; the implementation is CauldronHook.getHookPermissions)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Abstract with no body at `getHookPermissions` (BaseHook.sol:25); the deployed contract's version is `getHookPermissions` (CauldronHook.sol:621). Read on-chain only by `getHookPermissions` (BaseHook.sol:32) during construction, and off-chain by deployment tooling.
- Edges: none
- Observations: none

### `validateHookAddress/function` — BaseHook.sol:31

- Signature: `function validateHookAddress(BaseHook _this) internal pure virtual`
- Authority: internal (callers: BaseHook constructor)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Reached once, from `validateHookAddress` (BaseHook.sol:19). It hands the permission struct to the v4-core `Hooks` (BaseHook.sol:32) validator, which lives under lib/ and is therefore not a resolvable edge. It is `virtual` (BaseHook.sol:31) so a test harness can override it and etch a hook at an arbitrary address; CauldronHook does not override it.
- Edges: `BaseHook.getHookPermissions (BaseHook.sol:32), TRUSTED, in-cluster`
- Observations: none

### `beforeInitialize/function` — BaseHook.sol:36

- Signature: `function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96) external onlyPoolManager returns (bytes4)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:38)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: The v4 pool manager is the only permitted caller — the `onlyPoolManager` (BaseHook.sol:38) modifier comes from the periphery `ImmutableState` base. It forwards to `_beforeInitialize` (BaseHook.sol:41), which CauldronHook does NOT override, so any call reverts `HookNotImplemented`; the permission bit for it is false at `beforeInitialize` (CauldronHook.sol:628), so the manager never calls it.
- Edges: `BaseHook._beforeInitialize (BaseHook.sol:41), TRUSTED, in-cluster`
- Observations: none

### `_beforeInitialize/function` — BaseHook.sol:44

- Signature: `function _beforeInitialize(address, PoolKey calldata, uint160) internal virtual returns (bytes4)`
- Authority: internal (callers: BaseHook.beforeInitialize)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body: `revert` (BaseHook.sol:45) unconditionally. Reached only from `_beforeInitialize` (BaseHook.sol:41), and unreachable in practice because the matching permission bit is false at `beforeInitialize` (CauldronHook.sol:628).
- Edges: none
- Observations: none

### `afterInitialize/function` — BaseHook.sol:49

- Signature: `function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) external onlyPoolManager returns (bytes4)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:51)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:51). This one IS enabled: `afterInitialize` (CauldronHook.sol:629) is true, so every initialize of a pool naming this hook lands here and is forwarded to the override `_afterInitialize` (CauldronHook.sol:670), which reverts unless the initializer is the registry.
- Edges: `BaseHook._afterInitialize (BaseHook.sol:54), TRUSTED, in-cluster`
- Observations: none

### `_afterInitialize/function` — BaseHook.sol:57

- Signature: `function _afterInitialize(address, PoolKey calldata, uint160, int24) internal virtual returns (bytes4)`
- Authority: internal (callers: BaseHook.afterInitialize)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:58). It is shadowed by the override `_afterInitialize` (CauldronHook.sol:670), so the default is never executed in the deployed hook.
- Edges: none
- Observations: none

### `beforeAddLiquidity/function` — BaseHook.sol:62

- Signature: `function beforeAddLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData ) external onlyPoolManager returns (bytes4)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:67)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:67). Dead in this deployment: `beforeAddLiquidity` (CauldronHook.sol:630) is false, so the manager never dispatches here, and the forwarded `_beforeAddLiquidity` (BaseHook.sol:68) is not overridden.
- Edges: `BaseHook._beforeAddLiquidity (BaseHook.sol:68), TRUSTED, in-cluster`
- Observations: none

### `_beforeAddLiquidity/function` — BaseHook.sol:71

- Signature: `function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) internal virtual returns (bytes4)`
- Authority: internal (callers: BaseHook.beforeAddLiquidity)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:76); not overridden by CauldronHook and gated off by the permission bit `beforeAddLiquidity` (CauldronHook.sol:630).
- Edges: none
- Observations: none

### `beforeRemoveLiquidity/function` — BaseHook.sol:80

- Signature: `function beforeRemoveLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData ) external onlyPoolManager returns (bytes4)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:85)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:85). Dead: `beforeRemoveLiquidity` (CauldronHook.sol:632) is false and `_beforeRemoveLiquidity` (BaseHook.sol:86) is not overridden.
- Edges: `BaseHook._beforeRemoveLiquidity (BaseHook.sol:86), TRUSTED, in-cluster`
- Observations: none

### `_beforeRemoveLiquidity/function` — BaseHook.sol:89

- Signature: `function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) internal virtual returns (bytes4)`
- Authority: internal (callers: BaseHook.beforeRemoveLiquidity)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:94); gated off by `beforeRemoveLiquidity` (CauldronHook.sol:632).
- Edges: none
- Observations: none

### `afterAddLiquidity/function` — BaseHook.sol:98

- Signature: `function afterAddLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData ) external onlyPoolManager returns (bytes4, BalanceDelta)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:105)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:105). Dead: `afterAddLiquidity` (CauldronHook.sol:631) is false and the return-delta bit `afterAddLiquidityReturnDelta` (CauldronHook.sol:640) is false too; `_afterAddLiquidity` (BaseHook.sol:106) is not overridden.
- Edges: `BaseHook._afterAddLiquidity (BaseHook.sol:106), TRUSTED, in-cluster`
- Observations: none

### `_afterAddLiquidity/function` — BaseHook.sol:109

- Signature: `function _afterAddLiquidity( address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata ) internal virtual returns (bytes4, BalanceDelta)`
- Authority: internal (callers: BaseHook.afterAddLiquidity)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:117); gated off by `afterAddLiquidity` (CauldronHook.sol:631).
- Edges: none
- Observations: none

### `afterRemoveLiquidity/function` — BaseHook.sol:121

- Signature: `function afterRemoveLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData ) external onlyPoolManager returns (bytes4, BalanceDelta)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:128)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:128). Dead: `afterRemoveLiquidity` (CauldronHook.sol:633) is false, as is `afterRemoveLiquidityReturnDelta` (CauldronHook.sol:641).
- Edges: `BaseHook._afterRemoveLiquidity (BaseHook.sol:129), TRUSTED, in-cluster`
- Observations: none

### `_afterRemoveLiquidity/function` — BaseHook.sol:132

- Signature: `function _afterRemoveLiquidity( address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata ) internal virtual returns (bytes4, BalanceDelta)`
- Authority: internal (callers: BaseHook.afterRemoveLiquidity)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:140); gated off by `afterRemoveLiquidity` (CauldronHook.sol:633).
- Edges: none
- Observations: none

### `beforeSwap/function` — BaseHook.sol:144

- Signature: `function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:146)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:146). ENABLED: `beforeSwap` (CauldronHook.sol:634) is true and `beforeSwapReturnDelta` (CauldronHook.sol:638) is true, so this is the entry for every swap on an adopted pool and the returned BeforeSwapDelta is honoured. Forwards to the override `_beforeSwap` (CauldronHook.sol:1361).
- Edges: `BaseHook._beforeSwap (BaseHook.sol:149), TRUSTED, in-cluster`
- Observations: none

### `_beforeSwap/function` — BaseHook.sol:152

- Signature: `function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata) internal virtual returns (bytes4, BeforeSwapDelta, uint24)`
- Authority: internal (callers: BaseHook.beforeSwap)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:157); shadowed by the override `_beforeSwap` (CauldronHook.sol:1361), so it never runs in the deployed hook.
- Edges: none
- Observations: none

### `afterSwap/function` — BaseHook.sol:161

- Signature: `function afterSwap( address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData ) external onlyPoolManager returns (bytes4, int128)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:167)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:167). ENABLED: `afterSwap` (CauldronHook.sol:635) and `afterSwapReturnDelta` (CauldronHook.sol:639) are both true, so the int128 this returns is taken out of the swapper's unspecified leg. Forwards to the override `_afterSwap` (CauldronHook.sol:925).
- Edges: `BaseHook._afterSwap (BaseHook.sol:168), TRUSTED, in-cluster`
- Observations: none

### `_afterSwap/function` — BaseHook.sol:171

- Signature: `function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata) internal virtual returns (bytes4, int128)`
- Authority: internal (callers: BaseHook.afterSwap)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:176); shadowed by the override `_afterSwap` (CauldronHook.sol:925).
- Edges: none
- Observations: none

### `beforeDonate/function` — BaseHook.sol:180

- Signature: `function beforeDonate( address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData ) external onlyPoolManager returns (bytes4)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:186)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:186). Dead: `beforeDonate` (CauldronHook.sol:636) is false and `_beforeDonate` (BaseHook.sol:187) is not overridden.
- Edges: `BaseHook._beforeDonate (BaseHook.sol:187), TRUSTED, in-cluster`
- Observations: none

### `_beforeDonate/function` — BaseHook.sol:190

- Signature: `function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) internal virtual returns (bytes4)`
- Authority: internal (callers: BaseHook.beforeDonate)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:195); gated off by `beforeDonate` (CauldronHook.sol:636).
- Edges: none
- Observations: none

### `afterDonate/function` — BaseHook.sol:199

- Signature: `function afterDonate( address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData ) external onlyPoolManager returns (bytes4)`
- Authority: poolManager
- Gate evidence: `onlyPoolManager (BaseHook.sol:205)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:205). Dead: `afterDonate` (CauldronHook.sol:637) is false and `_afterDonate` (BaseHook.sol:206) is not overridden.
- Edges: `BaseHook._afterDonate (BaseHook.sol:206), TRUSTED, in-cluster`
- Observations: none

### `_afterDonate/function` — BaseHook.sol:209

- Signature: `function _afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) internal virtual returns (bytes4)`
- Authority: internal (callers: BaseHook.afterDonate)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Default body reverts at `revert` (BaseHook.sol:214); gated off by `afterDonate` (CauldronHook.sol:637).
- Edges: none
- Observations: none


## `HookMiner`

### `find/function` — HookMiner.sol:23

- Signature: `function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs) internal view returns (address, bytes32)`
- Authority: internal (callers: deploy scripts and test harnesses, none in this cluster)
- Gate evidence: `UNGATED`
- Reads: `FLAG_MASK (line 28, constant)`; `MAX_LOOP (line 32, constant)`
- Writes: none
- Value: NONE
- Reachability: `find` (HookMiner.sol:23) is a library `internal` function, so it is inlined into whatever unit imports it. No contract in this cluster calls it; the only importers in the tree are deploy scripts and test harnesses (DERIVED). It brute-forces a CREATE2 salt whose address carries the hook-flag bits masked by `FLAG_MASK` (HookMiner.sol:28) and has no deployed code, giving up after `MAX_LOOP` (HookMiner.sol:32) iterations with a revert string.
- Edges: `HookMiner.computeAddress (HookMiner.sol:33), TRUSTED, in-cluster`
- Observations: none

### `computeAddress/function` — HookMiner.sol:48

- Signature: `function computeAddress(address deployer, uint256 salt, bytes memory creationCodeWithArgs) internal pure returns (address hookAddress)`
- Authority: internal (callers: HookMiner.find)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure CREATE2 address derivation, called once per loop iteration from `computeAddress` (HookMiner.sol:33). No storage, no external calls: a single `keccak256` (HookMiner.sol:54) over the 0xFF / deployer / salt / init-code-hash preimage.
- Edges: none
- Observations: none
