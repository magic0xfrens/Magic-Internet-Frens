# Function graph — cluster `hook`

Generated from the current `contracts/solidity` tree on 2026-09-18. Machine source: [`hook.json`](./hook.json).

Validated coverage: **146/146 nodes, 0 failures** with a fresh compiler cache.

## Files

| file | lines |
|---|---:|
| `CauldronHook.sol` | 2643 |
| `vendor/BaseHook.sol` | 217 |
| `vendor/HookMiner.sol` | 58 |
| `cauldron/FeeRouteLib.sol` | 264 |
| `cauldron/DefaultFeeRouter.sol` | 50 |
| `cauldron/ReserveLib.sol` | 108 |
| `cauldron/RoyaltyRouter.sol` | 140 |
| `cauldron/LegacyBuyLib.sol` | 340 |
| `cauldron/SurtaxLib.sol` | 129 |

## Node inventory and semantic annotations

### IRegistryQuotes (declared in CauldronHook.sol)

#### L34 `allowedQuote`

- Declaration: `function allowedQuote(address quote) external view returns (bool)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only. Dispatched once per pool adoption at `allowedQuote` (CauldronHook.sol:660), against the address in `registry` (CauldronHook.sol:660) — the one caller `_afterInitialize` (CauldronHook.sol:637) has already required the initializer to BE the registry, so the callee is trusted by construction. Its single bool decides `quoteIsCurrency0` (CauldronHook.sol:663) for the pool's whole life; only currency0 is tested, currency1 is inferred.

### IQuoteOracle (declared in CauldronHook.sol)

#### L44 `cachedUsdPerRawUnit`

- Declaration: `function cachedUsdPerRawUnit(address quote) external returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only, and never used as an interface call: the hook builds the selector by hand at `cachedUsdPerRawUnit` (CauldronHook.sol:761) and fires a raw `call` (CauldronHook.sol:760) so a reverting oracle cannot take the swap down. The target is `quoteOracle` (CauldronHook.sol:758), set only through `setDeathThreshold` (CauldronHook.sol:1961). It is non-view by design, so this is a state-changing call inside afterSwap and the oracle is a re-entrancy-capable trusted component.

### IPerpOpenCount (declared in CauldronHook.sol)

#### L51 `openCount`

- Declaration: `function openCount() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only. The current pool-link path queries `blocksVolumeLink` (CauldronHook.sol:1726), while this legacy `openCount` declaration has no hook dispatch site (DERIVED).

#### L54 `blocksVolumeLink`

- Declaration: `function blocksVolumeLink() external view returns (bool)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration used by the registry-only pool-link path through `blocksVolumeLink` (CauldronHook.sol:1726); the configured engine address supplies the answer.

### IPerpEngineLiq (declared in CauldronHook.sol)

#### L58 `liquidateInSwap`

- Declaration: `function liquidateInSwap(uint256 id, address liquidator) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only, and unused by the hook: `liquidateInSwap` (CauldronHook.sol:58) has no dispatch site in this cluster (DERIVED). The current swap path enters the shared helper at `_liqSweep` (CauldronHook.sol:1024).

#### L59 `liquidateManyInSwap`

- Declaration: `function liquidateManyInSwap(uint256[] calldata ids, address liquidator) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only, and DEAD: `liquidateManyInSwap` (CauldronHook.sol:59) has no dispatch site anywhere in the hook (DERIVED).

#### L60 `sweepLiquidations`

- Declaration: `function sweepLiquidations(address liquidator, int256 amountSpecified, bool isBuy, uint160 limit) external returns (bool complete)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration dispatched as `sweepLiquidations` (CauldronHook.sol:805) to the configured perp engine with the swap shape and price limit.

#### L65 `openCount`

- Declaration: `function openCount() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration queried as `openCount` (CauldronHook.sol:852) only on the low-gas pre-trade branch.

### ICollectionLiquidator (declared in CauldronHook.sol)

#### L70 `setLiquidatorMinter`

- Declaration: `function setLiquidatorMinter(address minter) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only. One dispatch site, `setLiquidatorMinter` (CauldronHook.sol:2206), inside a try/catch in `_wireLiquidator` (CauldronHook.sol:2204); a collection that does not grant the hook this right simply no-ops, so a summon or relaunch cannot brick on it.

### ILegacyNote (declared in CauldronHook.sol)

#### L76 `noteLegacyBuy`

- Declaration: `function noteLegacyBuy(uint256 tokensBought) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only, and DEAD: `noteLegacyBuy` (CauldronHook.sol:76) has no dispatch site in the hook (DERIVED). The buyback's accounting is deferred to the counter written at `legacyOwedToReserve` (CauldronHook.sol:1206) and settled later by the registry's sweep through `sweepLegacyReserve` (CauldronHook.sol:1264).
- Observation: comment at `registry` (CauldronHook.sol:73) says this is the registry entry that records a legacy buyback against the live collection's pending entitlement; code never calls `noteLegacyBuy` (CauldronHook.sol:76) and instead accrues `legacyOwedToReserve` (CauldronHook.sol:1206) for a later registry-pulled sweep

### IPerpForceClose (declared in CauldronHook.sol)

#### L81 `forceCloseAllDead`

- Declaration: `function forceCloseAllDead() external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only. One dispatch site: `forceCloseAllDead` (CauldronHook.sol:1989), inside the registry-gated `forceClosePerps` (CauldronHook.sol:1984) and wrapped in try/catch, with the transient relaunch flag set around it so the engine's settlement swaps pay no fee.

#### L82 `openCount`

- Declaration: `function openCount() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only. One dispatch site: `openCount` (CauldronHook.sol:2015), immediately after the try/catch. It is NOT guarded, and a non-zero result reverts `PerpsOpen` (CauldronHook.sol:2015) — so the engine's answer here can abort the registry's whole relaunch transaction.

### IPerpFeeCredit (declared in CauldronHook.sol)

#### L88 `creditPerpFee`

- Declaration: `function creditPerpFee() external payable`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only; used as a SELECTOR. `creditPerpFee` (CauldronHook.sol:1387) is chosen for the BUY side and handed to `routePerp` (CauldronHook.sol:1385), which calls it with value through the library's native branch. Reached only when the swapper is the perp engine, per the branch at `perpEngine` (CauldronHook.sol:1618).

#### L89 `creditPerpFeeToken`

- Declaration: `function creditPerpFeeToken() external payable`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only; used as a SELECTOR. `creditPerpFeeToken` (CauldronHook.sol:1387) is the SELL-side counterpart passed to `routePerp` (CauldronHook.sol:1385). Same gate as its buy-side twin: only a swap whose sender is `perpEngine` (CauldronHook.sol:1618) routes here.

#### L92 `creditPerpFeeAsset`

- Declaration: `function creditPerpFeeAsset(address asset, uint256 amount) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only; used as a SELECTOR for the non-native pull path. `creditPerpFeeAsset` (CauldronHook.sol:1388) is passed to `routePerp` (CauldronHook.sol:1385) and invoked by the library only after it has approved the engine, so the engine pulls rather than receives.

### ISeederInSwap (declared in CauldronHook.sol)

#### L99 `pokeInSwap`

- Declaration: `function pokeInSwap() external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only; used as a SELECTOR. `pokeInSwap` (CauldronHook.sol:1159) is encoded into a gas-capped low-level call on `seeder` (CauldronHook.sol:1155) from `_maybePoke` (CauldronHook.sol:1154), with the result ignored. Fires on every swap on a tracked pool before any fee is taken, provided a seeder is wired and enough gas remains.

### CauldronHook

#### L424 `outstandingCrystals`

- Declaration: `function outstandingCrystals() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `9c252ea470576fd04571ccd0f0c22f9c6401aabc`
- Authority: anyone
- Gate: `UNGATED`
- Reads: gacha (line 424)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: External view preserving the former public getter while the counter now lives at `gacha` (CauldronHook.sol:424).

#### L572 `constructor`

- Declaration: `constructor( IPoolManager _poolManager, uint256 _deathThreshold, address _nftContract, address _treasury, address _owner ) BaseHook(_poolManager) Ownable(_owner)`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `866740523afe62e35b19c64314ed9ad688c9431c`
- Authority: deployer
- Gate: `UNGATED`
- Reads: -
- Writes: deathThreshold (line 579);nftContract (line 580);treasury (line 581)
- Value: NONE
- Edges: BaseHook.validateHookAddress (BaseHook.sol:19), TRUSTED, in-cluster
- Reachability: Runs once at CREATE2 deployment. Ownership is passed in explicitly at `Ownable` (CauldronHook.sol:578) because the hook is deployed through a factory, so the constructor's sender is not the intended owner. The base initialiser reaches `validateHookAddress` (BaseHook.sol:19), which reverts unless the mined address carries exactly the permission bits of `getHookPermissions` (CauldronHook.sol:588). Note that `registry` (CauldronHook.sol:2117) is NOT set here: the hook is inert until the owner wires it, and `registry` (CauldronHook.sol:646) compares against a zero registry until then.
- Observation: comment at `stability` (CauldronHook.sol:256) says the treasury slot is a dead slot read by nothing and kept only for layout stability; code at `treasury` (CauldronHook.sol:581) still writes it from a constructor parameter

#### L588 `getHookPermissions`

- Declaration: `function getHookPermissions() public pure override returns (Hooks.Permissions memory)`
- Kind/visibility/mutability: `function` / `public` / `pure`
- Body SHA-1: `106d16749ed8afd42e230af8ad24446220e8b931`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure; no state. Read on-chain during construction by `getHookPermissions` (BaseHook.sol:32) so the v4 address-flag validation can compare it against the deployed address, and off-chain by deploy tooling that mines the salt. The enabled bits are `afterInitialize` (CauldronHook.sol:596), `beforeSwap` (CauldronHook.sol:601), `afterSwap` (CauldronHook.sol:602), `beforeSwapReturnDelta` (CauldronHook.sol:605) and `afterSwapReturnDelta` (CauldronHook.sol:606); every liquidity and donate bit is false.
- Observation: comment at `afterSwapReturnDelta` (CauldronHook.sol:124) says the hook's permissions are afterInitialize, afterSwap and afterSwapReturnDelta; code additionally enables `beforeSwap` (CauldronHook.sol:601) and `beforeSwapReturnDelta` (CauldronHook.sol:605), which is what lets the buy-leg fee be skimmed before the swap

#### L637 `_afterInitialize`

- Declaration: `function _afterInitialize( address sender, PoolKey calldata key, uint160, int24 ) internal override returns (bytes4)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `fd2c8f03db651daee790c501e325dfbfc93638b3`
- Authority: poolManager (and, inside it, only the registry may be the initializer)
- Gate: `require(sender == registry); (CauldronHook.sol:646)`
- Reads: registry (line 646);registry (line 660)
- Writes: quoteIsCurrency0 (line 663);trackedPools (line 664);_lastUpdateTs (line 665);poolInitBlock (line 666)
- Value: NONE
- Edges: IRegistryQuotes.allowedQuote (CauldronHook.sol:660), UNTRUSTED, out-of-cluster
- Reachability: Anyone may initialize a v4 pool naming this hook, so the external entry `afterInitialize` (BaseHook.sol:49) is publicly reachable through the pool manager; the adoption gate is the bare `require` (CauldronHook.sol:646), which reverts (no reason string) unless the initializer is the registry. A revert here makes the initialize itself fail, which is what stops anyone squatting a future generation's computable PoolKey. Once past the gate it asks the registry which side is the quote with a single `allowedQuote` (CauldronHook.sol:660) call on currency0 ONLY — currency1 is inferred, never checked — and freezes that answer in `quoteIsCurrency0` (CauldronHook.sol:663) for the pool's lifetime. It also stamps `poolInitBlock` (CauldronHook.sol:666) with the block number, which is the anchor for the anti-sniper decay.

#### L757 `_toUsd`

- Declaration: `function _toUsd(address quote, uint256 raw) internal returns (uint256)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `1ea29ada68f7f2680b2a47e258bbee611b8b3764`
- Authority: internal (callers: CauldronHook._afterSwap)
- Gate: `UNGATED`
- Reads: quoteOracle (line 758)
- Writes: -
- Value: NONE
- Edges: o.call (CauldronHook.sol:760), UNTRUSTED, out-of-cluster
- Reachability: Reached once per tracked swap from `_toUsd` (CauldronHook.sol:914). With no oracle wired it is the identity at `raw` (CauldronHook.sol:759), so volume stays in raw quote units. Otherwise it makes a low-level `call` (CauldronHook.sol:760) — not a staticcall, so the oracle can write and can re-enter the hook mid-swap — and any failure, short return or zero factor collapses to 0 at `f` (CauldronHook.sol:765), which the caller treats as `cannot judge` and records nothing. The multiply-then-divide at `raw` (CauldronHook.sol:765) rounds DOWN and can revert on overflow for an enormous raw amount, which would revert the swap.
- Observation: comment at `oracles` (CauldronHook.sol:109) says the 24h volume is fully computed inside afterSwap with no oracles; code at `quoteOracle` (CauldronHook.sol:758) makes a state-changing external oracle call from inside that same callback whenever the slot is wired

#### L799 `_liqSweep`

- Declaration: `function _liqSweep(address sender, int256 amountSpecified, bool isBuy, uint160 limit) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `7184b034a63fa817b1a7269797daaefa7719bddb`
- Authority: internal (callers: CauldronHook._beforeSwap and CauldronHook._afterSwap)
- Gate: `UNGATED`
- Reads: perpEngine (line 800);LIQ_GAS_RESERVE (line 801, constant);LIQ_GAS_MIN (line 801, constant)
- Writes: -
- Value: NONE
- Edges: perpEngine.call (CauldronHook.sol:804), UNTRUSTED, out-of-cluster;perpEngine.staticcall (CauldronHook.sol:852), UNTRUSTED, out-of-cluster
- Reachability: Private shared sweep. The pre-swap caller passes the signed swap amount at `amountSpecified` (CauldronHook.sol:1346); the post-swap caller passes zero at `_liqSweep` (CauldronHook.sol:1024). It skips self-recursion and a zero engine at `perpEngine` (CauldronHook.sol:800). With enough gas it forwards all gas above the selected reserve at `call` (CauldronHook.sol:804); an incomplete pre-trade pass reverts at `LiqGasStarved` (CauldronHook.sol:821). Below the floor, only a successfully decoded non-zero `openCount` causes the same revert at `LiqGasStarved` (CauldronHook.sol:853); a reverting or malformed engine is treated as an empty book.

#### L857 `_afterSwap`

- Declaration: `function _afterSwap( address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData ) internal override returns (bytes4, int128)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `15f63b9e7e04202cf9cbd1dfbb47fd82e08d1652`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:167)`
- Reads: trackedPools (line 870);quoteIsCurrency0 (line 873);collection (line 936);creditUntaggedSwaps (line 955);registry (line 960);buyWeightBps (line 967);sellWeightBps (line 967);BPS (line 967, constant);nftCredit (line 971);creditEpoch (line 971);lifetimeVolumeOf (line 974);totalLifetimeVolume (line 977);quest (line 985);GACHA_GAS_MIN (line 1036, constant);GACHA_GAS_RESERVE (line 1037, constant)
- Writes: cumulativeVolume (line 917);nftCredit (line 973);lifetimeVolumeOf (line 976);totalLifetimeVolume (line 979)
- Value: NONE directly; the returned `fee` (CauldronHook.sol:1074) is the positive unspecified-leg delta collected by the pool manager, after `_takeEthFee` has accounted it.
- Edges: CauldronHook._maybeLegacyBuyback (CauldronHook.sol:877), TRUSTED, in-cluster;CauldronHook._maybePoke (CauldronHook.sol:879), TRUSTED, in-cluster;CauldronHook._toUsd (CauldronHook.sol:914), TRUSTED, in-cluster;CauldronHook._recordVolume (CauldronHook.sol:916), TRUSTED, in-cluster;quest.call (CauldronHook.sol:986), UNTRUSTED, out-of-cluster;CauldronHook._liqSweep (CauldronHook.sol:1024), TRUSTED, in-cluster;address(this).call (CauldronHook.sol:1037), TRUSTED, in-cluster;CauldronHook._isExemptPlayer (CauldronHook.sol:1062), TRUSTED, in-cluster;CauldronHook._takeEthFee (CauldronHook.sol:1072), TRUSTED, in-cluster;CauldronHook._maybeLegacyBuyback (CauldronHook.sol:1073), TRUSTED, in-cluster
- Reachability: Reached through pool-manager-gated `afterSwap` (BaseHook.sol:161). Self-buy/relaunch flags and the adoption check short-circuit at `trackedPools` (CauldronHook.sol:870). Quote volume from `delta` (CauldronHook.sol:890) is normalized once; a zero conversion writes no volume or credit. Credit is restricted to the current live currency1 at `_liveKey` (CauldronHook.sol:937), attributed from hookData or `tx.origin` at `player` (CauldronHook.sol:953), and all three accumulators saturate. The post-trade liquidation sweep is best-effort through `_liqSweep` (CauldronHook.sol:1024). Native untagged gacha is a gas-bounded, result-ignored self-call at `call` (CauldronHook.sol:1037). Only a sell whose unspecified leg is the quote reaches `_takeEthFee` (CauldronHook.sol:1072); buys were charged before the swap.

#### L1087 `_maybeLegacyBuyback`

- Declaration: `function _maybeLegacyBuyback(PoolId id, PoolKey calldata key) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `e0220c618a6f3ff646cdcef51d10618c7ad1d294`
- Authority: internal (callers: CauldronHook._afterSwap)
- Gate: `UNGATED`
- Reads: legacyBuffer (line 1088);_liveKey (line 1089);legacyBufferAsset (line 1115);legacyRegistry (line 1115);legacyThreshold (line 1124);quoteIsCurrency0 (line 1135);LEGACY_GAS_MIN (line 1141, constant);LEGACY_GAS_RESERVE (line 1142, constant)
- Writes: legacyBuffer (line 1117)
- Value: NONE here; the gas-capped self `call` (line 1142) is what spends the buffer, and the drain branch only moves the figure between counters at `_creditFor` (line 1121)
- Edges: CauldronHook._creditFor (CauldronHook.sol:1121), TRUSTED, in-cluster;address(this).call (CauldronHook.sol:1142), TRUSTED, in-cluster
- Reachability: Private; called twice per afterSwap, at `_maybeLegacyBuyback` (CauldronHook.sol:877) before anything else and again at `_maybeLegacyBuyback` (CauldronHook.sol:1073) after the sell-leg fee, so either leg can trigger. FIRST, A DRAIN, NOT A RETURN: a buffer whose denomination does not match the live pool's currency0 OR that exists while the buyback is unwired is zeroed at `legacyBuffer` (CauldronHook.sol:1117) and moved into the reserve for the asset it actually is at `_creditFor` (CauldronHook.sol:1121), which is checked BEFORE the threshold test at `legacyThreshold` (CauldronHook.sol:1124), so a sub-threshold or stranded balance still leaves. The wiring test is now part of that same condition at `legacyRegistry` (CauldronHook.sol:1115) instead of an early return ahead of it. Three more conditions then gate the spend: a quote at currency0 per `quoteIsCurrency0` (CauldronHook.sol:1135), a wired live pair at `live` (CauldronHook.sol:1137) and the triggering id equal to the live key's id at `live` (CauldronHook.sol:1138). The caller's own key is explicitly discarded at `key` (CauldronHook.sol:1139), so an attacker cannot steer the spend into a book they price; the spend itself is a gas-capped self-call whose result is discarded at `call` (CauldronHook.sol:1142).

#### L1154 `_maybePoke`

- Declaration: `function _maybePoke() private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `ebd2e4fef9e4a995423a4a18980ade981cf50173`
- Authority: internal (callers: CauldronHook._afterSwap)
- Gate: `UNGATED`
- Reads: seeder (line 1155);SEED_POKE_GAS_MIN (line 1158, constant);SEED_POKE_GAS_RESERVE (line 1159, constant)
- Writes: -
- Value: NONE
- Edges: s.call (CauldronHook.sol:1159), UNTRUSTED, out-of-cluster
- Reachability: Private; one call site, `_maybePoke` (CauldronHook.sol:879), near the top of afterSwap and BEFORE the adoption-dependent work below it — but after the tracked-pool early return at `trackedPools` (CauldronHook.sol:870), so an unadopted pool never reaches it. No-ops when `seeder` (CauldronHook.sol:1155) is unset. The call is gas-capped and its result discarded, so a broken seeder can waste gas but cannot revert the swap.

#### L1170 `legacyBuyStep`

- Declaration: `function legacyBuyStep(PoolKey calldata key) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `84eed309b82734d8f8e9a401f73895cc80695dc7`
- Authority: hook itself (self-call only)
- Gate: `if (msg.sender != address(this)) revert OnlySelf(); (CauldronHook.sol:1171)`
- Reads: legacyBuffer (line 1172);legacyThreshold (line 1173);legacyBufferAsset (line 1189);relaunchETH (line 1195);relaunchAsset (line 1195)
- Writes: legacyBuffer (line 1174);legacyBuffer (line 1200);legacyOwedToReserve (line 1206)
- Value: spends native or the ERC20 quote out of the hook through the delegatecalled `buyStep` (line 1195)
- Edges: LegacyBuyLib.buyStep (CauldronHook.sol:1195), TRUSTED, delegatecall
- Reachability: External but self-only: the sole reachable caller is the gas-capped self `call` (CauldronHook.sol:1142) inside `_maybeLegacyBuyback` (CauldronHook.sol:1087), which already re-checks the threshold. A SECOND DENOMINATION GATE lives here: the spender reverts `BadParam` when the key it was handed does not match the buffer's asset at `legacyBufferAsset` (CauldronHook.sol:1189), which rolls back the `legacyBuffer` (CauldronHook.sol:1174) zeroing; the revert is contained because the only call site ignores the result. The reserve counter for the same asset is passed to the library as `encumbered` at `relaunchETH` (CauldronHook.sol:1195), so the buy clamps to the free balance instead of moving reserve-backed value. The unspent remainder is credited back at `legacyBuffer` (CauldronHook.sol:1200). The transient re-entry flag is raised around the nested swap at `_inSelfBuy` (CauldronHook.sol:1181) so the hook's own before/afterSwap charge nothing, and cleared at `_inSelfBuy` (CauldronHook.sol:1196) but NOT in a try/catch, so a reverting library call unwinds the whole self-call rather than leaving the flag set. The bought tokens stay on the hook and are only counted, at `legacyOwedToReserve` (CauldronHook.sol:1206).

#### L1216 `fundLegacyBuffer`

- Declaration: `function fundLegacyBuffer() external payable`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `c7fb00fe63a9bf1a54531cc4bcfa1b9e88d80f2f`
- Authority: anyone
- Gate: `UNGATED`
- Reads: _liveKey (line 1243);legacyBuffer (line 1244);legacyBufferAsset (line 1244)
- Writes: relaunchETH (line 1245);legacyBufferAsset (line 1248);legacyBuffer (line 1249)
- Value: receives native; it is credited to `legacyBuffer` (line 1249) when the live generation is ether-quoted and the buffer is not already holding another asset, otherwise to `relaunchETH` (line 1245)
- Edges: -
- Reachability: Permissionless and payable. The intended caller is RoyaltyRouter, which forwards secondary royalties at `call` (RoyaltyRouter.sol:91), but any address can donate. A zero-value call returns at `msg` (CauldronHook.sol:1242); value that cannot enter the native buffer is rerouted into `relaunchETH` (CauldronHook.sol:1245), so this path does not revert a marketplace sale.

#### L1264 `sweepLegacyReserve`

- Declaration: `function sweepLegacyReserve(address token, address to) external returns (uint256 amt)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `1cd98f158a5eb7e059f7d317eb177bbb6eb3ee60`
- Authority: legacyRegistry
- Gate: `if (msg.sender != legacyRegistry) revert OnlySelf(); (CauldronHook.sol:1265)`
- Reads: legacyOwedToReserve (line 1266)
- Writes: legacyOwedToReserve (line 1269)
- Value: transfers `token` to the caller-supplied recipient through the delegatecalled `send` (line 1279)
- Edges: IERC20.balanceOf (CauldronHook.sol:1267), UNTRUSTED, out-of-cluster;FeeRouteLib.send (CauldronHook.sol:1279), TRUSTED, delegatecall
- Reachability: Gated on `legacyRegistry` (CauldronHook.sol:1265) - the same slot the fee split uses as an on/off switch, settable by owner OR registry through `setLegacyBuyback` (CauldronHook.sol:2059). Both `token` (CauldronHook.sol:1264) and the destination are caller-supplied, so the caller chooses which ERC20 is read and where it lands; the debit is clamped to the live balance at `amt` (CauldronHook.sol:1268) so it can only ever equal what the transfer attempts. THE TRANSFER IS NOW CHECKED AND THE DEBIT UNDONE ON FAILURE: the move goes through `send` (CauldronHook.sol:1279), which verifies the ERC20 boolean, and a false answer reverts `SendFailed` (CauldronHook.sol:1279), rolling back the `legacyOwedToReserve` (CauldronHook.sol:1269) debit so the next sweep can still claim it. Unlike the buyback self-call, this entrypoint is called directly by the registry, so the revert propagates to that caller.

#### L1289 `_beforeSwap`

- Declaration: `function _beforeSwap( address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData ) internal override returns (bytes4, BeforeSwapDelta, uint24)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `a045332057af73a07efe71b4d44a0dcf56668ff7`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:146)`
- Reads: trackedPools (line 1299);quoteIsCurrency0 (line 1301)
- Writes: -
- Value: NONE directly; `toBeforeSwapDelta` (CauldronHook.sol:1365) returns a positive specified-currency delta equal to the input fee.
- Edges: CauldronHook._liqSweep (CauldronHook.sol:1346), TRUSTED, in-cluster;CauldronHook._isExemptPlayer (CauldronHook.sol:1351), TRUSTED, in-cluster;CauldronHook._takeEthFee (CauldronHook.sol:1359), TRUSTED, in-cluster
- Reachability: Entered through pool-manager-gated `beforeSwap` (BaseHook.sol:144). Self-buy/relaunch and untracked pools return zero delta at `trackedPools` (CauldronHook.sol:1299). Exact-output sells remain refused at `ExactOutSellUnsupported` (CauldronHook.sol:1345). Every other swap shape first invokes the pre-trade `_liqSweep` (CauldronHook.sol:1346); only exact-input buys continue to fee collection, with exemptions checked at `_isExemptPlayer` (CauldronHook.sol:1351).

#### L1380 `_routePerpFee`

- Declaration: `function _routePerpFee(uint256 amount, bool isBuy) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `9132b998f156875fc5825f6a4a79b9c33197045e`
- Authority: internal (callers: CauldronHook._takeEthFee)
- Gate: `UNGATED`
- Reads: BPS (line 1381, constant);guild (line 1386);perpEngine (line 1386)
- Writes: -
- Value: no direct transfer; the guild and staker shares leave through the delegatecalled `routePerp` (line 1385)
- Edges: FeeRouteLib.routePerp (CauldronHook.sol:1385), TRUSTED, delegatecall;CauldronHook._creditReserve (CauldronHook.sol:1385), TRUSTED, in-cluster
- Reachability: Private; one call site, `_routePerpFee` (CauldronHook.sol:1618), taken only when the swapper IS the configured perp engine. The 30/70 split is a hard-coded literal at `toGuild` (CauldronHook.sol:1381) — not a tunable bps slot — and the remainder is computed by subtraction at `toStakers` (CauldronHook.sol:1382) so the two always sum exactly. Which staker side is credited is decided by the caller's isBuy flag at `isBuy` (CauldronHook.sol:1387). Whatever the library could not deliver comes back as a number and is booked to the reserve in the same expression.

#### L1397 `_creditReserve`

- Declaration: `function _creditReserve(uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `b4cd68c849881d40a6055fa01bcbc6a2aa567126`
- Authority: internal (callers: CauldronHook._routePerpFee, CauldronHook._routeEthFee)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: CauldronHook._creditFor (CauldronHook.sol:1397), TRUSTED, in-cluster
- Reachability: Private one-liner; two call sites, `_creditReserve` (CauldronHook.sol:1385) and `_creditReserve` (CauldronHook.sol:1549). It no longer does the branching itself: it forwards the transient fee asset to `_creditFor` (CauldronHook.sol:1397), which is the single place that decides whether a residual joins the native wei counter or the per-asset mapping.

#### L1401 `_creditFor`

- Declaration: `function _creditFor(address a, uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `9065e1222d93ec3bef04b92a5784a8f9b4690138`
- Authority: internal (callers: CauldronHook._creditReserve, CauldronHook._maybeLegacyBuyback)
- Gate: `UNGATED`
- Reads: relaunchETH (line 1403);relaunchAsset (line 1404)
- Writes: relaunchETH (line 1403);relaunchAsset (line 1404)
- Value: NONE; it only moves a figure between the two reserve counters
- Edges: -
- Reachability: New private helper, reached from `_creditFor` (CauldronHook.sol:1397) for a residual in the CURRENT fee asset and from `_creditFor` (CauldronHook.sol:1121) for a buffer stranded in some OTHER asset after a rotation or an unwiring. The caller names the denomination explicitly at `a` (CauldronHook.sol:1403), which is what lets the stale-buffer drain credit the asset the buffer really holds rather than whatever the current fee happens to be. A zero amount returns at `amount` (CauldronHook.sol:1402). Both destinations have exits (`releaseRelaunchETH` and `releaseRelaunchAsset` on this contract).

#### L1407 `_routeEthFee`

- Declaration: `function _routeEthFee(uint256 feeAmount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `00d4abc021bb1657f7d5c1742253b338baa0e00b`
- Authority: internal (callers: CauldronHook._takeEthFee)
- Gate: `UNGATED`
- Reads: activeProposer (line 1445);proposerBps (line 1446);BPS (line 1447, constant);proposerOwed (line 1449);feeRouter (line 1464);guild (line 1466);vault (line 1466);guildBps (line 1466);floorBps (line 1466);guild (line 1475);guildBps (line 1475);floorBps (line 1477);_liveKey (line 1507);legacyRegistry (line 1508);legacyBps (line 1508);legacyBuffer (line 1509);legacyBufferAsset (line 1509);vault (line 1528);legacyRegistry (line 1532)
- Writes: proposerOwed (line 1449);legacyBufferAsset (line 1516);legacyBuffer (line 1517);legacyBufferAsset (line 1534);legacyBuffer (line 1535)
- Value: no direct transfer; the guild and floor shares leave through the delegatecalled `routeSplit` (line 1550) and everything undelivered is booked by `_creditReserve` (line 1549)
- Edges: IFeeRouter.route (CauldronHook.sol:1466), UNTRUSTED, out-of-cluster;CauldronHook._creditReserve (CauldronHook.sol:1549), TRUSTED, in-cluster;FeeRouteLib.routeSplit (CauldronHook.sol:1550), TRUSTED, delegatecall
- Reachability: Private; reached from `_routeEthFee` (CauldronHook.sol:1619) for the base fee of an ordinary swap and from `_routeEthFee` (CauldronHook.sol:1627) for a surtax the guild refused. Order of operations: the proposer slice is carved off the top but ONLY for a native fee at `prop` (CauldronHook.sol:1445), accrued pull-style so the swap path stays call-free; then an optional pluggable router is asked for the split inside try/catch at `route` (CauldronHook.sol:1466) and its answer discarded unless the three parts sum exactly to the fee at `feeAmount` (CauldronHook.sol:1467); then the legacy carve, taken from the floor share first, gated on the fee asset matching the live pool's currency0 at `_feeAsset` (CauldronHook.sol:1507) AND on the buffer being empty or already in that same asset at `legacyBufferAsset` (CauldronHook.sol:1509), with the denomination stamped alongside the figure at `legacyBufferAsset` (CauldronHook.sol:1516); then two floor fall-backs at `vault` (CauldronHook.sol:1528) and `_feeAsset` (CauldronHook.sol:1538) that redirect a floor share the vault cannot hold. Nothing reverts: every undeliverable share ends in the reserve at `_creditReserve` (CauldronHook.sol:1549).
- Observation: code at `_feeAsset` (CauldronHook.sol:1532) folds a no-vault floor share into the buffer only when the fee asset is native, while the carve above it at `_feeAsset` (CauldronHook.sol:1507) compares the fee asset to the live key's currency0; the two buffer entries therefore apply different denomination rules once a generation is quoted in an ERC20, and only the second one also stamps `legacyBufferAsset` (CauldronHook.sol:1534) (DERIVED)

#### L1560 `snipeSurtaxBps`

- Declaration: `function snipeSurtaxBps(PoolId id) public view returns (uint256)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `6179fce6e06b026ec4ec0d366e13a1e9c1036efa`
- Authority: anyone
- Gate: `UNGATED`
- Reads: surtaxPolicy (line 1567);poolInitBlock (line 1567);snipeMaxBps (line 1567);snipeWindowBlocks (line 1567);MAX_SNIPE_BPS (line 1567, constant)
- Writes: -
- Value: NONE
- Edges: SurtaxLib.surtaxBps (CauldronHook.sol:1566), TRUSTED, out-of-cluster
- Reachability: Public view, so anyone can read it, and it is also on the fee hot path from `snipeSurtaxBps` (CauldronHook.sol:1594). THE WHOLE CURVE MOVED OUT: this function now only reads the inputs and hands them to the linked library at `SurtaxLib` (CauldronHook.sol:1566), a separately-deployed library whose function is `view`. The policy preference, the try/catch that stops a reverting module bricking the fee path, the fallback curve and both clamps are on the library side - the module's answer is clamped to the hard cap at `hardCap` (SurtaxLib.sol:47) and a revert falls through to `defaultSurtaxBps` (SurtaxLib.sol:50). The jitter no longer reads live pool state: the seed is the previous blockhash, the pool id, the block number and `prevrandao` at `prevrandao` (SurtaxLib.sol:121), all per-BLOCK rather than per-call, and it is ADDED to the linear decay at `total` (SurtaxLib.sol:125). `_takeEthFee` clamps the combined rate afterwards at `totalBps` (CauldronHook.sol:1595).
- Observation: comment at `prevrandao` (CauldronHook.sol:1557) says the jitter means there is no cleanly-predictable cheap block to schedule an entry into; the library that now computes it states the opposite at `snipeSurtaxBps` (SurtaxLib.sol:70) - because the getter is public view, a sniper can read the block's draw and retry in the next block - and the floor the code does guarantee is the deterministic decay at `total` (SurtaxLib.sol:125)

#### L1579 `_takeEthFee`

- Declaration: `function _takeEthFee( PoolId id, PoolKey calldata key, address sender, bytes calldata hookData, uint256 ethAmount, bool isBuy ) private returns (uint256 total)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `fc0bb10ab9b4827ee189a3f308dc70f5fece6f5c`
- Authority: internal (callers: CauldronHook._beforeSwap, CauldronHook._afterSwap)
- Gate: `UNGATED`
- Reads: MAX_TOTAL_FEE_BPS (line 1595, constant);BPS (line 1596, constant);quoteIsCurrency0 (line 1611);perpEngine (line 1618);guild (line 1626)
- Writes: -
- Value: pulls `total` (line 1613) of the quote currency out of the pool manager into this hook
- Edges: CauldronHook._taxedPlayer (CauldronHook.sol:1592), TRUSTED, in-cluster;CauldronHook._getHolderTaxRate (CauldronHook.sol:1592), TRUSTED, in-cluster;CauldronHook.snipeSurtaxBps (CauldronHook.sol:1594), TRUSTED, in-cluster;IPoolManager.take (CauldronHook.sol:1613), TRUSTED, out-of-cluster;CauldronHook._routePerpFee (CauldronHook.sol:1618), TRUSTED, in-cluster;CauldronHook._routeEthFee (CauldronHook.sol:1619), TRUSTED, in-cluster;FeeRouteLib.routeSplit (CauldronHook.sol:1626), TRUSTED, delegatecall;CauldronHook._routeEthFee (CauldronHook.sol:1627), TRUSTED, in-cluster
- Reachability: Private; the two call sites are the buy leg at `_takeEthFee` (CauldronHook.sol:1359) and the sell leg at `_takeEthFee` (CauldronHook.sol:1072), so its authority is exactly the pool manager's. The taxed identity is resolved once at `_taxedPlayer` (CauldronHook.sol:1592) so a routed trade is charged the trader's tier rather than the router's. The combined rate is clamped at `MAX_TOTAL_FEE_BPS` (CauldronHook.sol:1595) so a swap always keeps at least one percent. The actual custody move is the pool-manager `take` (CauldronHook.sol:1613) — an in-swap call to core that credits this contract — and it happens BEFORE any routing, with the transient fee-asset field written first at `_feeAsset` (CauldronHook.sol:1612) so every downstream send knows the denomination. Surtax is offered to the guild first and only falls into the normal split if the guild is unset or refused at `guild` (CauldronHook.sol:1626).

#### L1634 `setSnipeParams`

- Declaration: `function setSnipeParams(uint256 windowBlocks, uint256 maxBps) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `0a1966d0c4593857179e255048811bf736461d5e`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:1634)`
- Reads: MAX_SNIPE_BPS (line 1635, constant)
- Writes: snipeWindowBlocks (line 1636);snipeMaxBps (line 1637)
- Value: NONE
- Edges: -
- Reachability: Owner-only. The peak is bounded by `MAX_SNIPE_BPS` (CauldronHook.sol:1635) but the WINDOW is not bounded at all at `snipeWindowBlocks` (CauldronHook.sol:1636), so an arbitrarily long surtax window can be set; the per-swap clamp in `MAX_TOTAL_FEE_BPS` (CauldronHook.sol:1595) is what keeps a trade executable.

#### L1644 `_recordVolume`

- Declaration: `function _recordVolume(PoolId id, uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `7a149563b0ed3bb9b20c34d465c14b04ecd98e17`
- Authority: internal (caller: CauldronHook._afterSwap)
- Gate: `UNGATED`
- Reads: _lastUpdateTs (line 1645);SECONDS_PER_HOUR (line 1653, constant);_lastBucketIndex (line 1655);HOURS_PER_DAY (line 1657, constant);_volumeBuckets (line 1668)
- Writes: _volumeBuckets (line 1659);_volumeBuckets (line 1663);_volumeBuckets (line 1669);_lastBucketIndex (line 1671);_lastUpdateTs (line 1672)
- Value: NONE
- Edges: CauldronHook._getCurrentBucket (CauldronHook.sol:1654), TRUSTED, in-cluster
- Reachability: Private and called only for non-zero normalized volume at `_recordVolume` (CauldronHook.sol:916). Absolute-hour `steps` (CauldronHook.sol:1653) distinguishes the same ring index a day later from the same current hour. A full clear is fixed at 24 iterations; the partial clear is bounded because `steps` is less than `HOURS_PER_DAY` (CauldronHook.sol:1657). The bucket add saturates at `type` (CauldronHook.sol:1670).

#### L1677 `getVolume24h`

- Declaration: `function getVolume24h(PoolId id) public view returns (uint256 total)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `f113302ae2f03cce4c1fd26895064bc6e87743ad`
- Authority: anyone
- Gate: `UNGATED`
- Reads: SECONDS_PER_HOUR (line 1682, constant);_lastUpdateTs (line 1682);HOURS_PER_DAY (line 1683, constant);_lastBucketIndex (line 1684);_volumeBuckets (line 1685)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Public view. An absolute-hour `gap` (CauldronHook.sol:1682) returns zero after a full day and causes the fixed ring scan to skip buckets that have expired but have not yet been lazily cleared. The loop at `HOURS_PER_DAY` (CauldronHook.sol:1689) has at most 24 iterations, and its uint128 sum cannot overflow uint256.

#### L1724 `linkVolume`

- Declaration: `function linkVolume(PoolId primary, PoolId secondary) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `71fd47c0f640bff569e417a48738e91dc73cb8b4`
- Authority: registry
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1725)`
- Reads: registry (line 1725);perpEngine (line 1726);_volumeSiblings (line 1738)
- Writes: -
- Value: NONE
- Edges: IPerpOpenCount.blocksVolumeLink (CauldronHook.sol:1726), UNTRUSTED, out-of-cluster;CauldronHook._addSibling (CauldronHook.sol:1763), TRUSTED, in-cluster;CauldronHook._addSibling (CauldronHook.sol:1764), TRUSTED, in-cluster;CauldronHook._addSibling (CauldronHook.sol:1766), TRUSTED, in-cluster;CauldronHook._addSibling (CauldronHook.sol:1767), TRUSTED, in-cluster
- Reachability: Registry-only. A configured engine may veto through `blocksVolumeLink` (CauldronHook.sol:1726); that external call is not caught. Self-linking returns at `primary` (CauldronHook.sol:1737). Existing siblings are connected bidirectionally with the new pool at `_addSibling` (CauldronHook.sol:1763), and the primary/new pair is also linked both ways, making every member's aggregate symmetric. `_addSibling` performs deduplication and enforces the per-node cap.
- Observation: There remains no unlink path: each distinct destination permanently consumes sibling capacity, as documented beside `MAX_SIBLINGS` (CauldronHook.sol:1784).

#### L1773 `_addSibling`

- Declaration: `function _addSibling(PoolId a, PoolId b) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `f8d62f8eb26857a7710a4cf484c2a703ba07bab7`
- Authority: internal (caller: CauldronHook.linkVolume)
- Gate: `UNGATED`
- Reads: _volumeSiblings (line 1774);MAX_SIBLINGS (line 1778, constant)
- Writes: _volumeSiblings (line 1774)
- Value: NONE
- Edges: -
- Reachability: Private helper reached only from the `_addSibling` calls in linkVolume (CauldronHook.sol:1763). It scans at most the capped sibling list, returns on a duplicate at `unwrap` (CauldronHook.sol:1776), rejects a distinct overflow at `MAX_SIBLINGS` (CauldronHook.sol:1778), then appends `b` (CauldronHook.sol:1779).

#### L1791 `isDead`

- Declaration: `function isDead(PoolId id) external view returns (bool)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `93951bf9ed9e2686b153ea7fbba2fb075a9ef85b`
- Authority: anyone
- Gate: `UNGATED`
- Reads: trackedPools (line 1792);_volumeSiblings (line 1798);deathChecker (line 1800);deathThreshold (line 1804);deathThreshold (line 1807);deathThreshold (line 1810)
- Writes: -
- Value: NONE
- Edges: CauldronHook.getVolume24h (CauldronHook.sol:1797), TRUSTED, in-cluster;CauldronHook.getVolume24h (CauldronHook.sol:1799), TRUSTED, in-cluster;IDeathChecker.isDead (CauldronHook.sol:1804), UNTRUSTED, out-of-cluster
- Reachability: External view, permissionless, and it is the gate the registry's relaunch depends on. An untracked pool is never dead at `trackedPools` (CauldronHook.sol:1792). Volume is summed across the primary and every sibling, so the loop at `sib` (CauldronHook.sol:1799) costs one full 24-bucket sum per sibling and is bounded only by the sibling cap. A pluggable checker is consulted inside try/catch at `checker` (CauldronHook.sol:1804) and a revert falls back to the built-in comparison, so a broken module cannot brick relaunch — but a WORKING hostile module can return either answer.

#### L1813 `_getCurrentBucket`

- Declaration: `function _getCurrentBucket() private view returns (uint256)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `044d34cc77755ead04ed76359bd9c19afd3c0706`
- Authority: internal (callers: CauldronHook._recordVolume)
- Gate: `UNGATED`
- Reads: SECONDS_PER_HOUR (line 1814, constant);HOURS_PER_DAY (line 1814, constant)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Private view, one call site at `_getCurrentBucket` (CauldronHook.sol:1654). Pure wall-clock arithmetic on the block timestamp, which is what makes the window mean the same thing on a chain whose block numbers track a parent chain.

#### L1821 `_getHolderTaxRate`

- Declaration: `function _getHolderTaxRate(address holder) private view returns (uint256)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `0e0e016aca6fa06a152fc7170a8bdfcb7f1ff794`
- Authority: internal (caller: CauldronHook._takeEthFee)
- Gate: `UNGATED`
- Reads: nftContract (line 1822);defaultTaxBps (line 1822);nftContract (line 1824);MAX_TAX_BPS (line 1828, constant);defaultTaxBps (line 1830)
- Writes: -
- Value: NONE
- Edges: INFTContract.getHolderTaxRate (CauldronHook.sol:1824), UNTRUSTED, out-of-cluster
- Reachability: Private fee lookup. With no NFT contract it returns `defaultTaxBps` (CauldronHook.sol:1822). Otherwise the external view call is caught; a successful tier rate is clamped at `MAX_TAX_BPS` (CauldronHook.sol:1828), and a revert falls back to the default.

#### L1836 `setDefaultTaxBps`

- Declaration: `function setDefaultTaxBps(uint256 _bps) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `fd93667f14d2060ac614e532fd2e41b107dc3bc9`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:1836)`
- Reads: MAX_TAX_BPS (line 1837, constant)
- Writes: defaultTaxBps (line 1838)
- Value: NONE
- Edges: -
- Reachability: Owner-only, bounded by `MAX_TAX_BPS` (CauldronHook.sol:1837) at ten percent. Only affects swaps where `nftContract` (CauldronHook.sol:1822) is unset or reverting.

#### L1851 `releaseRelaunchETH`

- Declaration: `function releaseRelaunchETH() external returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `fe26d6100bc9403da86008ed5c08d47308628cbe`
- Authority: registry
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1852)`
- Reads: registry (line 1852);relaunchETH (line 1854)
- Writes: relaunchETH (line 1857)
- Value: sends native to `registry` (line 1859)
- Edges: registry.call (CauldronHook.sol:1859), UNTRUSTED, out-of-cluster
- Reachability: Registry-only, and the counter is zeroed BEFORE the send at `relaunchETH` (CauldronHook.sol:1857), so it is checks-effects-interactions. A zero balance reverts `NoETHToRelease` (CauldronHook.sol:1855) rather than returning zero, and a failed send reverts `SendFailed` (CauldronHook.sol:1860) — which rolls the zeroing back, so the counter and the balance cannot silently diverge here. The counter is authoritative: nothing compares it against `address(this).balance`, so ether paid out elsewhere reduces the backing without reducing the number.

#### L1879 `releaseRelaunchAsset`

- Declaration: `function releaseRelaunchAsset(address asset) external returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `db5a9021d453ee0388d1e6c19b0e0134d4f85d70`
- Authority: registry
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1880)`
- Reads: registry (line 1880);relaunchAsset (line 1882)
- Writes: relaunchAsset (line 1885)
- Value: ERC20 transfer of `asset` to `registry` (line 1886)
- Edges: FeeRouteLib.send (CauldronHook.sol:1886), TRUSTED, delegatecall
- Reachability: Registry-only, per-asset counterpart to the native release. The mapping entry is zeroed before the move at `relaunchAsset` (CauldronHook.sol:1885) and the library's boolean IS checked at `send` (CauldronHook.sol:1886), so a token that returns false rather than reverting cannot zero the counter while the tokens stay put. The gas cap passed is zero, i.e. unbounded, which matters only for the native branch the caller cannot reach here.

#### L1913 `renounceOwnership`

- Declaration: `function renounceOwnership() public view override onlyOwner`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `05b5a97cde9034b25da9601e40bee80c6e76a89d`
- Authority: owner only, and it reverts for the owner too
- Gate: `public view override onlyOwner (CauldronHook.sol:1913)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Overrides OpenZeppelin's live `renounceOwnership` and always reverts at `RenounceDisabled` (CauldronHook.sol:1914), so ownership on this contract is transferable but not renounceable; `transferOwnership` remains the route to the governance timelock. This contract inherits Ownable directly rather than through CauldronBase, so the base contract's own guard never covered this selector (DERIVED). Because the `onlyOwner` modifier still runs first (CauldronHook.sol:1913), a non-owner caller gets Ownable's unauthorized error and only the owner reaches `RenounceDisabled` (CauldronHook.sol:1914) - the two callers are distinguishable by revert data (DERIVED). Declared `view` while reverting, which is legal and keeps the selector non-payable and gas-free to probe (DERIVED).

#### L1961 `setDeathThreshold`

- Declaration: `function setDeathThreshold( uint256 _threshold, address _oracle, uint256 _volumePerNFT, uint256 _nftPriceStep, uint256 _oddsFullVolume ) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `8026927a68f5b1a02e573cfcfcfbbc500cf066c3`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:1967)`
- Reads: -
- Writes: deathThreshold (line 1968);quoteOracle (line 1971);volumePerNFT (line 1972);nftPriceStep (line 1973);oddsFullVolumeWei (line 1974)
- Value: NONE
- Edges: -
- Reachability: Owner-only, and the only way to wire `quoteOracle` (CauldronHook.sol:1971). Wiring an oracle re-denominates every volume-derived number, so the setter forces the curve to be restated in the same call and rejects a zero base or zero full-play size at `BadParam` (CauldronHook.sol:1970). A zero oracle argument leaves the oracle and the curve untouched while still moving `deathThreshold` (CauldronHook.sol:1968) — and there is no way to UNSET an oracle once set, because address(0) is the leave-alone sentinel.

#### L1984 `forceClosePerps`

- Declaration: `function forceClosePerps() external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `d57ed2210a6be28a72263c3d51845454e3e00414`
- Authority: registry
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1985)`
- Reads: registry (line 1985);perpEngine (line 1986)
- Writes: -
- Value: NONE
- Edges: IPerpForceClose.forceCloseAllDead (CauldronHook.sol:1989), UNTRUSTED, out-of-cluster;IPerpForceClose.openCount (CauldronHook.sol:2015), UNTRUSTED, out-of-cluster
- Reachability: Registry-only, called once per rebirth. It raises the transient relaunch flag at `_inRelaunchClose` (CauldronHook.sol:1988) so the engine's settlement swaps skip fee and buyback, force-closes inside try/catch, then lowers it at `_inRelaunchClose` (CauldronHook.sol:1990). The flag is transient, so it clears at end of transaction even if the close reverts. The final survivor check at `openCount` (CauldronHook.sol:2015) is NOT guarded and reverts `PerpsOpen` (CauldronHook.sol:2015) on any leftover, which deliberately unwinds the caller's whole relaunch rather than stranding positions.

#### L2046 `setLiveKey`

- Declaration: `function setLiveKey(PoolKey calldata k) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `02986dde19d55de0d40cbd71c92b64aea88dad91`
- Authority: registry
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2047)`
- Reads: registry (line 2047)
- Writes: _liveKey (line 2048)
- Value: NONE
- Edges: -
- Reachability: Registry-only, pushed at every summon and relaunch. It is a plain storage write with NO validation of the key at `_liveKey` (CauldronHook.sol:2048) — not the currencies, not the fee, not the hook field — so the registry alone decides which pool the buyback spends into and which currency1 the credit gate at `_liveKey` (CauldronHook.sol:937) compares against.

#### L2052 `liveKey`

- Declaration: `function liveKey() external view returns (PoolKey memory)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `03474adb2d83decd6dbe095dbbe8787d142f8f3c`
- Authority: anyone
- Gate: `UNGATED`
- Reads: _liveKey (line 2053)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: External view returning the whole struct; the canonical pool for integrators. Same data the internal paths read at `_liveKey` (CauldronHook.sol:1089).

#### L2059 `setLegacyBuyback`

- Declaration: `function setLegacyBuyback(address registry_, uint256 bps, uint256 threshold) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `890425b88ceec2707f89c4796b3042017d6e77df`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2060)`
- Reads: registry (line 2060);BPS (line 2061, constant)
- Writes: legacyRegistry (line 2062);legacyBps (line 2063);legacyThreshold (line 2064)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2060), TRUSTED, out-of-cluster
- Reachability: Two holders: the registry and the owner. `legacyRegistry` (CauldronHook.sol:2062) is unvalidated and doubles as the authority for `sweepLegacyReserve` (CauldronHook.sol:1264), so setting it grants that withdrawal right to an arbitrary address. The share is bounded by `BPS` (CauldronHook.sol:2061) at 100 percent of the post-guild fee, and a zero threshold argument leaves the existing threshold alone at `legacyThreshold` (CauldronHook.sol:2064).

#### L2073 `setDeathChecker`

- Declaration: `function setDeathChecker(address _checker) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `99849e0603cb1ed7102e2d1fab4494d8fd43940f`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2074)`
- Reads: registry (line 2074)
- Writes: deathChecker (line 2075)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2074), TRUSTED, out-of-cluster
- Reachability: Owner or registry. Unvalidated: any address, including one that is not a contract, can be written to `deathChecker` (CauldronHook.sol:2075); the consumer wraps it in try/catch at `checker` (CauldronHook.sol:1804) so a bad module degrades to the built-in rule.

#### L2083 `setPolicies`

- Declaration: `function setPolicies(address _surtax, address _odds, address _curve) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `31da35d431557c1c027ea715b31571a5154eb9b4`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2084)`
- Reads: registry (line 2084)
- Writes: surtaxPolicy (line 2085);oddsPolicy (line 2086);curvePolicy (line 2087)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2084), TRUSTED, out-of-cluster
- Reachability: Owner or registry; all three modules are written unconditionally, so passing address(0) for one CLEARS it rather than leaving it alone. Each consumer clamps and falls back: the surtax at `MAX_SNIPE_BPS` (CauldronHook.sol:1567), which the hook passes to the linked library where it is applied at `hardCap` (SurtaxLib.sol:47), the odds at `ODDS_HARD_CAP_BPS` (CauldronHook.sol:2369), the curve at `c` (CauldronHook.sol:2320) which only rejects a zero price.

#### L2095 `setFeeRouter`

- Declaration: `function setFeeRouter(address _router) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `1375c52e78664b778b3e218452ea8061fb729559`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2096)`
- Reads: registry (line 2096)
- Writes: feeRouter (line 2097)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2096), TRUSTED, out-of-cluster
- Reachability: Owner or registry. The router only returns amounts — the hook keeps custody and does the sends itself at `routeSplit` (CauldronHook.sol:1550) — and a result that does not sum exactly to the fee is discarded at `feeAmount` (CauldronHook.sol:1467). It is still a call made mid-swap into an admin-chosen address, so it is a re-entrancy surface into the fee path.

#### L2101 `setNftContract`

- Declaration: `function setNftContract(address _nft) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `4f42c2d4c6dc609e442b09d6f4e27e2bd3da9240`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2101)`
- Reads: -
- Writes: nftContract (line 2102)
- Value: NONE
- Edges: -
- Reachability: Owner-only, unvalidated. It selects the contract every swap asks for a tax tier at `INFTContract` (CauldronHook.sol:1824), so it directly controls what every trader pays, bounded only by the combined clamp at `MAX_TOTAL_FEE_BPS` (CauldronHook.sol:1595).

#### L2114 `setRegistry`

- Declaration: `function setRegistry(address _registry) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `9089e77a581624638f4dade071c0543f47a8023a`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2114)`
- Reads: registry (line 2115)
- Writes: registry (line 2117)
- Value: NONE
- Edges: -
- Reachability: Owner-only and ONE-SHOT: a second call reverts `RegistryAlreadySet` (CauldronHook.sol:2115) and zero is rejected at `ZeroAddress` (CauldronHook.sol:2116). This is what stops the owner re-pointing the reserve's payee; the only way past it is the delayed override pair.

#### L2130 `proposeRegistryOverride`

- Declaration: `function proposeRegistryOverride(address _registry) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `af9fd298c244c81077709a2e5deefb714187490c`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2130)`
- Reads: -
- Writes: pendingRegistry (line 2132);registrySwapReadyAt (line 2133)
- Value: NONE
- Edges: -
- Reachability: Owner-only step one of the controller swap. It arms `pendingRegistry` (CauldronHook.sol:2132) and stamps a deadline of now plus the constant at `REGISTRY_SWAP_DELAY` (CauldronHook.sol:2133); the delay is a constant, so the owner cannot shorten their own notice period. Re-proposing simply overwrites both and restarts the clock.

#### L2139 `cancelRegistryOverride`

- Declaration: `function cancelRegistryOverride() external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `2846168a2dd569eaef3aaa62d0ba826e30f46656`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2139)`
- Reads: -
- Writes: pendingRegistry (line 2140);registrySwapReadyAt (line 2141)
- Value: NONE
- Edges: -
- Reachability: Owner-only abort of an armed swap; no delay, because it can only ever cancel. It emits the proposal event with zero values at `RegistryOverrideProposed` (CauldronHook.sol:2142), which an indexer must interpret as a cancellation rather than a proposal.

#### L2150 `executeRegistryOverride`

- Declaration: `function executeRegistryOverride() external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `95f08dad8b4716913f9c5572d0c742aa04299902`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2150)`
- Reads: pendingRegistry (line 2151);registrySwapReadyAt (line 2153);relaunchETH (line 2154);relaunchETH (line 2155);registry (line 2157)
- Writes: relaunchETH (line 2156);registry (line 2161);pendingRegistry (line 2162);registrySwapReadyAt (line 2163)
- Value: sends native to the OUTGOING `registry` (line 2157)
- Edges: registry.call (CauldronHook.sol:2157), UNTRUSTED, out-of-cluster
- Reachability: Owner-only step two, refused before the deadline at `registrySwapReadyAt` (CauldronHook.sol:2153) — reusing the RegistryAlreadySet error for a timing condition. The whole native reserve is flushed to the OUTGOING registry first, zeroed before the send at `relaunchETH` (CauldronHook.sol:2156), and a failed send reverts the entire swap at `SendFailed` (CauldronHook.sol:2158). The per-asset reserves in `relaunchAsset` (CauldronHook.sol:1885) are NOT flushed, so a non-native reserve survives the controller change and can then only be pulled by the NEW registry.

#### L2182 `setCollection`

- Declaration: `function setCollection(address _collection) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `479be36b30a7574c4523f36d6f951ace1713cbe7`
- Authority: registry
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2183)`
- Reads: registry (line 2183)
- Writes: collection (line 2184);mintBaseline (line 2187);creditEpoch (line 2190)
- Value: NONE
- Edges: ICauldronCollection.totalMinted (CauldronHook.sol:2189), UNTRUSTED, out-of-cluster;CauldronHook._wireLiquidator (CauldronHook.sol:2193), TRUSTED, in-cluster
- Reachability: Registry-only, once per summon or relaunch. The external `totalMinted` (CauldronHook.sol:2189) read is NOT guarded, so a collection that reverts there blocks the whole wiring. Bumping `creditEpoch` (CauldronHook.sol:2190) namespaces credit so the previous generation's balances cannot mint the new collection, and the baseline anchors the rising curve at position zero even for a continued collection.

#### L2204 `_wireLiquidator`

- Declaration: `function _wireLiquidator(address _collection) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `7e837fe8724c6684b475bc7b4d75203b8775d0bc`
- Authority: internal (callers: CauldronHook.setCollection, CauldronHook.setPerpEngine)
- Gate: `UNGATED`
- Reads: perpEngine (line 2205);perpEngine (line 2206)
- Writes: -
- Value: NONE
- Edges: ICollectionLiquidator.setLiquidatorMinter (CauldronHook.sol:2206), UNTRUSTED, out-of-cluster
- Reachability: Private; reached from `_wireLiquidator` (CauldronHook.sol:2193) and `_wireLiquidator` (CauldronHook.sol:2238). Best-effort: the try/catch at `ICollectionLiquidator` (CauldronHook.sol:2206) means a collection that does not grant the hook this right cannot brick a summon, and equally means a silent failure to wire badges.

#### L2210 `setVault`

- Declaration: `function setVault(address _vault) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `83c7a231e6ddeac23212ee3d5c9afcb6c39f6adb`
- Authority: registry
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2211)`
- Reads: registry (line 2211)
- Writes: vault (line 2212)
- Value: NONE
- Edges: -
- Reachability: Registry-only, unvalidated. `vault` (CauldronHook.sol:2212) is a payee: the native floor share is sent there at `routeSplit` (CauldronHook.sol:1550), and clearing it to zero reroutes that share to the legacy buffer or the reserve at `vault` (CauldronHook.sol:1528).

#### L2216 `setQuest`

- Declaration: `function setQuest(address _quest) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `1ebb3bee0ac4d15e8c948dd9d87e8603fc30726b`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2217)`
- Reads: registry (line 2217)
- Writes: quest (line 2218)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2217), TRUSTED, out-of-cluster
- Reachability: Owner or registry, unvalidated. The quest contract is called mid-swap with ignored result at `quest` (CauldronHook.sol:986), but with NO gas cap — unlike the seeder and perp calls — so a hostile quest can burn the swapper's remaining gas.

#### L2225 `setSeeder`

- Declaration: `function setSeeder(address _seeder) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `e3bd6520f43e523ca3479dbf473754b347b6c655`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2226)`
- Reads: registry (line 2226)
- Writes: seeder (line 2227)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2226), TRUSTED, out-of-cluster
- Reachability: Owner or registry, unvalidated. Setting it turns on the in-swap poke at `s` (CauldronHook.sol:1159); clearing it to zero turns the in-swap nudge off at `s` (CauldronHook.sol:1156) without disabling the seeder's own permissionless path.

#### L2233 `setPerpEngine`

- Declaration: `function setPerpEngine(address _engine) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `b504fa9c89328b2f41bc69fb675114d618d5f12c`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2234)`
- Reads: registry (line 2234);collection (line 2238)
- Writes: perpEngine (line 2235)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2234), TRUSTED, out-of-cluster;CauldronHook._wireLiquidator (CauldronHook.sol:2238), TRUSTED, in-cluster
- Reachability: Owner or registry, unvalidated. This slot controls the post-trade sweep through `_liqSweep` (CauldronHook.sol:1024), fee routing at `perpEngine` (CauldronHook.sol:1618), the pool-link interlock at `perpEngine` (CauldronHook.sol:1726), and relaunch force-close at `perpEngine` (CauldronHook.sol:1986). Zero disables all four.

#### L2242 `setFloorBps`

- Declaration: `function setFloorBps(uint256 _bps) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `fc232776fc681d78c9b489dc2a7d20dff9e1a381`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2242)`
- Reads: BPS (line 2243, constant)
- Writes: floorBps (line 2244)
- Value: NONE
- Edges: -
- Reachability: Owner-only, bounded at 100 percent by `BPS` (CauldronHook.sol:2243). It splits the post-guild fee between the floor vault and the relaunch reserve at `floorBps` (CauldronHook.sol:1477).

#### L2249 `setGuild`

- Declaration: `function setGuild(address _guild) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `f8b7e84c4e3be133e0b4b82802c41c5a7ca3fe61`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2250)`
- Reads: registry (line 2250);guildBps (line 2252)
- Writes: guild (line 2251)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2250), TRUSTED, out-of-cluster
- Reachability: Owner or registry, unvalidated. `guild` (CauldronHook.sol:2251) is the recipient of the off-the-top tribute at `guild` (CauldronHook.sol:1475) AND of 100 percent of every anti-sniper surtax at `guild` (CauldronHook.sol:1626), so this one slot can redirect the single largest fee stream at launch.

#### L2261 `setGuildBps`

- Declaration: `function setGuildBps(uint256 _bps) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `84286d3fa3fbe0d7d4d34ed19e5654e822d523a9`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2261)`
- Reads: -
- Writes: guildBps (line 2263)
- Value: NONE
- Edges: -
- Reachability: Owner-only. The cap is the hard-coded deployed default at `BadParam` (CauldronHook.sol:2262), so the share can be lowered and restored but never raised above it.

#### L2269 `setActiveProposer`

- Declaration: `function setActiveProposer(address who) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `66103e31c8064f05a2be7615093520dc787a1a5f`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2270)`
- Reads: registry (line 2270)
- Writes: activeProposer (line 2271)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2270), TRUSTED, out-of-cluster
- Reachability: Owner or registry, unvalidated. The named address accrues a pull-only balance at `proposerOwed` (CauldronHook.sol:1449) on every NATIVE fee; address(0) disables the slice for that iteration at `prop` (CauldronHook.sol:1446).

#### L2276 `setProposerBps`

- Declaration: `function setProposerBps(uint256 _bps) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `b50a27df364278711c8d34e01d58ac4bfc40ea43`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2276)`
- Reads: MAX_PROPOSER_BPS (line 2277, constant)
- Writes: proposerBps (line 2278)
- Value: NONE
- Edges: -
- Reachability: Owner-only, capped at `MAX_PROPOSER_BPS` (CauldronHook.sol:2277) so the slice can never cannibalise the floor or the guild.

#### L2284 `claimProposerFees`

- Declaration: `function claimProposerFees() external nonReentrant returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `52a9c2c49b45f01a5f011052f0719a507019dc5b`
- Authority: anyone (each caller can only claim their own accrued balance)
- Gate: `UNGATED`
- Reads: proposerOwed (line 2285)
- Writes: proposerOwed (line 2287)
- Value: sends native to the caller via `call` (line 2288)
- Edges: msg.sender.call (CauldronHook.sol:2288), UNTRUSTED, out-of-cluster
- Reachability: Permissionless pull. Guarded by `nonReentrant` (CauldronHook.sol:2284) and written checks-effects-interactions: the balance is zeroed at `proposerOwed` (CauldronHook.sol:2287) before the value-bearing call. An empty balance reverts `NoETHToRelease` (CauldronHook.sol:2286). The ether paid out is the hook's raw balance, which is the same balance backing `relaunchETH` (CauldronHook.sol:1854) and `legacyBuffer` (CauldronHook.sol:1172) — none of those counters is reconciled against the balance.

#### L2294 `setNftCurve`

- Declaration: `function setNftCurve(uint256 _base, uint256 _step) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `377fecd9ad6b8b4837e91fe11dae640824a1f43c`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2294)`
- Reads: -
- Writes: volumePerNFT (line 2296);nftPriceStep (line 2297)
- Value: NONE
- Edges: -
- Reachability: Owner-only; the only bound is a non-zero base at `BadParam` (CauldronHook.sol:2295). It restates the crystal ladder that `volumePerNFT` (CauldronHook.sol:2323) prices against, in whatever unit the volume ledger currently uses.

#### L2300 `setCreditUntaggedSwaps`

- Declaration: `function setCreditUntaggedSwaps(bool on) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `63dbbabea1d007da4be91cb892411cb727aec55a`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2300)`
- Reads: -
- Writes: creditUntaggedSwaps (line 2300)
- Value: NONE
- Edges: -
- Reachability: Owner-only single-slot toggle. When off, an untagged direct swap credits nobody at `creditUntaggedSwaps` (CauldronHook.sol:955) and therefore also skips the in-swap gacha, since that path only arms for an untagged buyer.

#### L2307 `setNftCurveFrom`

- Declaration: `function setNftCurveFrom(uint256 _base) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `57127bd15715f6fb87538435488e911dd67192df`
- Authority: registry
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:2308)`
- Reads: registry (line 2308)
- Writes: volumePerNFT (line 2310);nftPriceStep (line 2311)
- Value: NONE
- Edges: -
- Reachability: Registry-only, called from a winning proposal's parameters. A zero argument is a no-op at `_base` (CauldronHook.sol:2309) rather than an error, and it forces a FLAT ladder by zeroing the step at `nftPriceStep` (CauldronHook.sol:2311), which is how a mint-out volume target is made exact.

#### L2315 `nftPriceAt`

- Declaration: `function nftPriceAt(uint256 k) public view returns (uint256)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `2e99dff880c7158f1f0d9c24e5ad9d63bce63e47`
- Authority: anyone
- Gate: `UNGATED`
- Reads: curvePolicy (line 2316);volumePerNFT (line 2318);nftPriceStep (line 2318);volumePerNFT (line 2323);nftPriceStep (line 2323)
- Writes: -
- Value: NONE
- Edges: ICurvePolicy.priceAt (CauldronHook.sol:2318), UNTRUSTED, out-of-cluster
- Reachability: Public view, and on the commit path from `nftPriceAt` (CauldronHook.sol:2462) — once per crystal, so up to 30 external calls per commit when a curve policy is wired. A policy result of zero is rejected at `c` (CauldronHook.sol:2320) because a free crystal would mint without bound, but there is no UPPER bound on what a policy may charge.

#### L2327 `creditOf`

- Declaration: `function creditOf(address player) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `33532772442a520955d1acdffc340d57e3c6020c`
- Authority: anyone
- Gate: `UNGATED`
- Reads: nftCredit (line 2328);creditEpoch (line 2328)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: External view of the current epoch's balance only; credit from a previous generation still sits in `nftCredit` (CauldronHook.sol:971) under an older epoch key and is unreadable through this getter.

#### L2335 `_curvePos`

- Declaration: `function _curvePos() internal view returns (uint256)`
- Kind/visibility/mutability: `function` / `internal` / `view`
- Body SHA-1: `9fdb6f241e5413cec54be64fa99c85adea579a98`
- Authority: internal (callers: CauldronHook.crystalsReady, CauldronHook.costOfNextCrystals, CauldronHook.progress)
- Gate: `UNGATED`
- Reads: collection (line 2336);outstandingOf (line 2337);collection (line 2337);mintBaseline (line 2337)
- Writes: -
- Value: NONE
- Edges: ICauldronCollection.totalMinted (CauldronHook.sol:2336), UNTRUSTED, out-of-cluster
- Reachability: Internal view; three callers, all views, each of which has already checked that a collection is set. The subtraction of `mintBaseline` (CauldronHook.sol:2337) is unguarded, so it underflows and reverts if the collection's minted count ever drops below the baseline recorded at wiring time.

#### L2341 `crystalsReady`

- Declaration: `function crystalsReady(address player) public view returns (uint256 ready)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `99751b79841e39eb81f9e603c492ab49f85057f3`
- Authority: anyone
- Gate: `UNGATED`
- Reads: collection (line 2342);nftCredit (line 2344);creditEpoch (line 2344);MAX_MINTS_PER_CALL (line 2346, constant)
- Writes: -
- Value: NONE
- Edges: CauldronHook._curvePos (CauldronHook.sol:2343), TRUSTED, in-cluster;CauldronHook.nftPriceAt (CauldronHook.sol:2347), TRUSTED, in-cluster
- Reachability: Public view for the UI. The loop is bounded by the constant at `MAX_MINTS_PER_CALL` (CauldronHook.sol:2346), so it reports at most 30 even when the player can afford more, and each iteration may make an external policy call through `nftPriceAt` (CauldronHook.sol:2347).

#### L2355 `costOfNextCrystals`

- Declaration: `function costOfNextCrystals(uint256 count) public view returns (uint256 cost)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `a2b558025358024beffd6978b6b149dd5ecd6664`
- Authority: anyone
- Gate: `UNGATED`
- Reads: collection (line 2356)
- Writes: -
- Value: NONE
- Edges: CauldronHook._curvePos (CauldronHook.sol:2357), TRUSTED, in-cluster;CauldronHook.nftPriceAt (CauldronHook.sol:2358), TRUSTED, in-cluster
- Reachability: Public view. The loop bound is the CALLER-SUPPLIED `count` (CauldronHook.sol:2358) with no cap, so an off-chain caller can ask for an unbounded amount of work; it is a view, so the cost falls on the node answering the query, not on a transaction.

#### L2364 `oddsForPlay`

- Declaration: `function oddsForPlay(uint256 playWei) public view returns (uint256 bps)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `76fae8d852d0101095abccde420f836ff6a99bb0`
- Authority: anyone
- Gate: `UNGATED`
- Reads: oddsPolicy (line 2365);maxOddsBps (line 2367);oddsFullVolumeWei (line 2367);ODDS_HARD_CAP_BPS (line 2369, constant);oddsFullVolumeWei (line 2372);maxOddsBps (line 2372);maxOddsBps (line 2373);oddsFullVolumeWei (line 2373)
- Writes: -
- Value: NONE
- Edges: IOddsPolicy.oddsBps (CauldronHook.sol:2367), UNTRUSTED, out-of-cluster
- Reachability: Public view, also called once per commit at `oddsForPlay` (CauldronHook.sol:2479) and cast to uint16 there. A zero full-play size short-circuits to the maximum at `oddsFullVolumeWei` (CauldronHook.sol:2372). The linear scale rounds DOWN at `bps` (CauldronHook.sol:2373), so a play below one ten-thousandth of the full size rolls zero odds, and any policy answer is clamped to the hard cap.

#### L2378 `outstandingTickets`

- Declaration: `function outstandingTickets() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `9c252ea470576fd04571ccd0f0c22f9c6401aabc`
- Authority: anyone
- Gate: `UNGATED`
- Reads: gacha (line 2379)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: External view alias over the same global `gacha` counter (CauldronHook.sol:2379) exposed by outstandingCrystals.

#### L2383 `mintedOut`

- Declaration: `function mintedOut() external view returns (bool)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `8d5bf8c5d8b0bc3f89384e448eb9abeacb3603db`
- Authority: anyone
- Gate: `UNGATED`
- Reads: collection (line 2384);collection (line 2385);collection (line 2386)
- Writes: -
- Value: NONE
- Edges: ICauldronCollection.totalMinted (CauldronHook.sol:2385), UNTRUSTED, out-of-cluster;ICauldronCollection.maxSupply (CauldronHook.sol:2386), UNTRUSTED, out-of-cluster
- Reachability: External view; two external calls, neither guarded, so a reverting collection makes this revert rather than report. It ignores the reserved crystals counted at `outstandingOf` (CauldronHook.sol:2450), so it can report not-minted-out while every remaining slot is already spoken for.

#### L2393 `progress`

- Declaration: `function progress(address player) external view returns (uint256 inCurrent, uint256 threshold, uint256 ready)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `47c154c922ed6ba57d4cf51d208f91dfc35bcd92`
- Authority: anyone
- Gate: `UNGATED`
- Reads: collection (line 2398);nftCredit (line 2400);creditEpoch (line 2400);MAX_MINTS_PER_CALL (line 2402, constant)
- Writes: -
- Value: NONE
- Edges: CauldronHook.nftPriceAt (CauldronHook.sol:2398), TRUSTED, in-cluster;CauldronHook._curvePos (CauldronHook.sol:2399), TRUSTED, in-cluster;CauldronHook.nftPriceAt (CauldronHook.sol:2403), TRUSTED, in-cluster;CauldronHook.nftPriceAt (CauldronHook.sol:2408), TRUSTED, in-cluster
- Reachability: External view for the UI; duplicates the loop in `crystalsReady` (CauldronHook.sol:2341) and additionally prices the next unaffordable crystal at `threshold` (CauldronHook.sol:2408). Same 30-iteration bound.

#### L2420 `commitCrystals`

- Declaration: `function commitCrystals(address player, uint256 maxCount, uint256 playWei) external nonReentrant returns (uint256 n)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `c853d965bd3f9229a2e300e57deb785402e56d2f`
- Authority: opener (an address flagged in isOpener)
- Gate: `if (!isOpener[msg.sender]) revert NotOpener(); (CauldronHook.sol:2425)`
- Reads: isOpener (line 2425)
- Writes: -
- Value: NONE
- Edges: CauldronHook._commitCrystals (CauldronHook.sol:2434), TRUSTED, in-cluster
- Reachability: Only an allow-listed opener may call it, which is what keeps the play size honest — `playWei` (CauldronHook.sol:2420) is supplied by the caller and feeds the odds directly, so an unrestricted caller could claim any play size. Guarded by `nonReentrant` (CauldronHook.sol:2422), which shares one guard with the resolve path and the in-swap gacha. The player is also caller-supplied, so an opener can commit on anyone's behalf and spend THAT player's credit.

#### L2440 `_commitCrystals`

- Declaration: `function _commitCrystals(address player, uint256 maxCount, uint256 playWei) internal returns (uint256 n)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `a12307ddca62cc0ebf52c41b6df122755616f5eb`
- Authority: internal (callers: CauldronHook.commitCrystals and CauldronHook.nativeGachaStep)
- Gate: `UNGATED`
- Reads: collection (line 2444);outstandingOf (line 2450);mintBaseline (line 2457);creditEpoch (line 2458);nftCredit (line 2459);MAX_MINTS_PER_CALL (line 2461, constant)
- Writes: nftCredit (line 2473);committedOf (line 2474);pendingOf (line 2475);gacha (line 2476);outstandingOf (line 2477);batches (line 2480)
- Value: NONE
- Edges: ICauldronCollection.totalMinted (CauldronHook.sol:2446), UNTRUSTED, out-of-cluster;ICauldronCollection.maxSupply (CauldronHook.sol:2447), UNTRUSTED, out-of-cluster;CauldronHook.nftPriceAt (CauldronHook.sol:2462), TRUSTED, in-cluster;CauldronHook.oddsForPlay (CauldronHook.sol:2479), TRUSTED, in-cluster
- Reachability: Shared commit body. Remaining supply is conservatively reduced by all `outstandingOf` (CauldronHook.sol:2450), and zero room returns without reverting. Curve position includes reserved crystals at `startPos` (CauldronHook.sol:2457). The affordability loop is bounded by caller max, remaining room, and `MAX_MINTS_PER_CALL` (CauldronHook.sol:2461). Credit and five reservation counters are updated before appending the batch; `n` is also clamped to uint16 at `type` (CauldronHook.sol:2471).

#### L2500 `resolveTickets`

- Declaration: `function resolveTickets(uint256 maxCount) public nonReentrant returns (uint256 processed, uint256 won)`
- Kind/visibility/mutability: `function` / `public` / `nonpayable`
- Body SHA-1: `b36cf57fdfc86db1eb9c88161b8da02d4a63ba38`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: CauldronHook._resolveTickets (CauldronHook.sol:2505), TRUSTED, in-cluster
- Reachability: Permissionless keeper entrypoint, guarded by `nonReentrant` (CauldronHook.sol:2502). The gacha router calls it right after committing, and anyone may call it at any time; the caller chooses `maxCount` (CauldronHook.sol:2500), which is the loop bound.

#### L2512 `_resolveTickets`

- Declaration: `function _resolveTickets(uint256 maxCount) internal returns (uint256 processed, uint256 won)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `2943c6a5a259c010f4cc35a1f18aa18b2e213b51`
- Authority: internal (callers: CauldronHook.resolveTickets and CauldronHook.nativeGachaStep)
- Gate: `UNGATED`
- Reads: batches (line 2520);missStreak (line 2520);pendingOf (line 2520);outstandingOf (line 2520);opened (line 2520);gacha (line 2520);pityThreshold (line 2520)
- Writes: batches (line 2520);missStreak (line 2520);pendingOf (line 2520);outstandingOf (line 2520);opened (line 2520);gacha (line 2520)
- Value: NONE
- Edges: GachaLib.resolveTickets (CauldronHook.sol:2519), TRUSTED, library
- Reachability: Internal wrapper reached by permissionless resolve through `_resolveTickets` (CauldronHook.sol:2505) and the self-only native step. It delegatecalls linked `GachaLib.resolveTickets` (CauldronHook.sol:2519), passing every mutable collection as a storage reference, including both scalar counters grouped in `gacha` (CauldronHook.sol:2520).

#### L2530 `nativeGachaStep`

- Declaration: `function nativeGachaStep(address player, uint256 playWei) external nonReentrant`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `2a17c527f6141940fb3f76eec4a41d37fa32b2b8`
- Authority: hook itself (self-call only)
- Gate: `if (msg.sender != address(this)) revert OnlySelf(); (CauldronHook.sol:2531)`
- Reads: NATIVE_COMMIT_MAX (line 2532, constant);NATIVE_RESOLVE_MAX (line 2533, constant)
- Writes: -
- Value: NONE
- Edges: CauldronHook._commitCrystals (CauldronHook.sol:2532), TRUSTED, in-cluster;CauldronHook._resolveTickets (CauldronHook.sol:2533), TRUSTED, in-cluster
- Reachability: External but self-only; the sole reachable caller is the gas-capped self `call` (CauldronHook.sol:1037) at the tail of afterSwap, whose result is discarded. `nonReentrant` (CauldronHook.sol:2530) shares the guard with the commit and resolve entrypoints, so a mint callback cannot re-enter either. The play size passed in is the weighted volume computed in afterSwap, i.e. already in the ledger's unit rather than raw ether.

#### L2539 `setOpener`

- Declaration: `function setOpener(address who, bool allowed) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `d29775ce6337baf3f83602014c5ccd75e2d5dd83`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2540)`
- Reads: registry (line 2540)
- Writes: isOpener (line 2541)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2540), TRUSTED, out-of-cluster
- Reachability: Owner or registry. An opener gets three powers at once: it may commit crystals for any player at `isOpener` (CauldronHook.sol:2425), its hookData tag is believed for tax tiering at `isOpener` (CauldronHook.sol:2572), and its tag is believed for fee exemption at `isOpener` (CauldronHook.sol:2564).

#### L2549 `setTaxExempt`

- Declaration: `function setTaxExempt(address who, bool exempt) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `b697d2426d55f6e2cb0fdc77c1a3204874ec7905`
- Authority: owner or registry
- Gate: `if (msg.sender != registry && msg.sender != owner()) revert OnlyRegistry(); (CauldronHook.sol:2550)`
- Reads: registry (line 2550)
- Writes: taxExempt (line 2551)
- Value: NONE
- Edges: Ownable.owner (CauldronHook.sol:2550), TRUSTED, out-of-cluster
- Reachability: Owner or registry. Exemption alone is not enough to dodge the fee: the swap must ALSO arrive from a trusted opener, per the conjunction at `isOpener` (CauldronHook.sol:2564), so a direct swapper cannot self-tag as exempt.

#### L2563 `_isExemptPlayer`

- Declaration: `function _isExemptPlayer(address sender, bytes calldata hookData) private view returns (bool)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `d6c969a3bf450e40d43d3f85f1a99c2c85c21331`
- Authority: internal (callers: CauldronHook._beforeSwap, CauldronHook._afterSwap)
- Gate: `UNGATED`
- Reads: taxExempt (line 2564);isOpener (line 2564)
- Writes: -
- Value: NONE
- Edges: CauldronHook._taxedPlayer (CauldronHook.sol:2564), TRUSTED, in-cluster
- Reachability: Private view on both fee legs, at `_isExemptPlayer` (CauldronHook.sol:1351) and `_isExemptPlayer` (CauldronHook.sol:1062). Exemption requires BOTH a flagged player and a trusted sender, so the hookData tag is only honoured from an opener.

#### L2571 `_taxedPlayer`

- Declaration: `function _taxedPlayer(address sender, bytes calldata hookData) private view returns (address)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `e3a216dde5c4d928a22f65f7539d1d647d1aeba4`
- Authority: internal (callers: CauldronHook._isExemptPlayer, CauldronHook._takeEthFee)
- Gate: `UNGATED`
- Reads: isOpener (line 2572)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Private view; the identity resolver used for both tiering at `_taxedPlayer` (CauldronHook.sol:1592) and exemption at `_taxedPlayer` (CauldronHook.sol:2564). A non-opener sender is always taxed as itself; an opener may name any player, and a zero decode falls back to the sender at `p` (CauldronHook.sol:2574).

#### L2579 `setOddsParams`

- Declaration: `function setOddsParams(uint256 fullVolumeWei, uint256 pity) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `b93ec7f7514e5c4778a2c94d8f80afe0e5941b4d`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2579)`
- Reads: -
- Writes: oddsFullVolumeWei (line 2580);pityThreshold (line 2581)
- Value: NONE
- Edges: -
- Reachability: Owner-only and unbounded on both arguments: `oddsFullVolumeWei` (CauldronHook.sol:2580) may be zero, making every play use maximum odds at `oddsFullVolumeWei` (CauldronHook.sol:2372), while a zero `pityThreshold` is passed into library resolution through `pityThreshold` (CauldronHook.sol:2520) and forces each non-sold-out ticket to win (DERIVED).

#### L2586 `setMaxOdds`

- Declaration: `function setMaxOdds(uint256 bps) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `5858fc64b27780a9387f80e956120eff5b091555`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2586)`
- Reads: ODDS_HARD_CAP_BPS (line 2587, constant)
- Writes: maxOddsBps (line 2588)
- Value: NONE
- Edges: -
- Reachability: Owner-only, capped at `ODDS_HARD_CAP_BPS` (CauldronHook.sol:2587) so bet size alone can never guarantee a creature; only the pity counter can.

#### L2592 `setWeights`

- Declaration: `function setWeights(uint256 buyBps, uint256 sellBps) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `1d8fc4a9ffc3841509306786befb1ded34460643`
- Authority: owner
- Gate: `external onlyOwner (CauldronHook.sol:2592)`
- Reads: MAX_WEIGHT_BPS (line 2593, constant)
- Writes: buyWeightBps (line 2594);sellWeightBps (line 2595)
- Value: NONE
- Edges: -
- Reachability: Owner-only, each side capped at `MAX_WEIGHT_BPS` (CauldronHook.sol:2593). These multiply the recorded volume into crystal credit at `buyWeightBps` (CauldronHook.sol:967), so raising them accelerates mint-out for every trader at once.

#### L2641 `receive`

- Declaration: `receive() external payable`
- Kind/visibility/mutability: `receive` / `-` / `payable`
- Body SHA-1: `da39a3ee5e6b4b0d3255bfef95601890afd80709`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: receives native via `receive` (line 2641)
- Edges: -
- Reachability: Empty payable fallback-style receiver. It records NOTHING, deliberately: ether arriving here — including the pool manager's payouts and any stray transfer — must not be counted into `legacyBuffer` (CauldronHook.sol:1249), which is why donations have their own entrypoint. Anything sent here silently increases the raw balance behind the counters without increasing any of them.

### DefaultFeeRouter

#### L21 `route`

- Declaration: `function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256 floorBps) external pure returns (uint256 toGuild, uint256 toFloor, uint256 toRelaunch)`
- Kind/visibility/mutability: `function` / `external` / `pure`
- Body SHA-1: `9f95f60701b954d087755b5767778029c1e42bf5`
- Authority: anyone
- Gate: `UNGATED`
- Reads: BPS (line 26, constant);BPS (line 46, constant)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: External pure split. `toGuild` (DefaultFeeRouter.sol:26) is guild-gated; floor share deliberately ignores the vault address at `toFloor` (DefaultFeeRouter.sol:46) so a zero-vault unified-floor deployment still receives buy-pressure allocation. `toRelaunch` (DefaultFeeRouter.sol:47) takes the exact remainder.

### FeeRouteLib

#### L48 `routeSplit`

- Declaration: `function routeSplit( address asset, address guild, address vault, uint256 toGuild, uint256 toFloor ) external returns (uint256 leftover)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `93b99711c1c96271284a127fb017d49288ecf486`
- Authority: internal to the hook via delegatecall (callers: CauldronHook._routeEthFee, CauldronHook._takeEthFee); the deployed library address is callable by anyone but holds no state and no funds
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: no direct transfer; value leaves through `_fundGuild` (FeeRouteLib.sol:64) and `_move` (FeeRouteLib.sol:68)
- Edges: FeeRouteLib._fundGuild (FeeRouteLib.sol:64), TRUSTED, library;FeeRouteLib._move (FeeRouteLib.sol:68), TRUSTED, library
- Reachability: Declared `external` (FeeRouteLib.sol:54) in a library, so it is delegatecalled and runs in the hook's context: the ether sent is the hook's and the tokens moved are the hook's. Three call sites, all inside the swap: `routeSplit` (CauldronHook.sol:1550) for the ordinary fee split, `routeSplit` (CauldronHook.sol:1626) for the anti-sniper surtax, and nothing else. Both call sites reach it only after the hook has already taken the fee, so the authority is whatever reached `_takeEthFee` (CauldronHook.sol:1579) — the pool manager driving before/afterSwap. Nothing here reverts: a guild or vault that refuses is reported by returning the undelivered amount as `leftover` (FeeRouteLib.sol:65), which the caller books into the reserve.

#### L79 `routePerp`

- Declaration: `function routePerp( address asset, address guild, address engine, uint256 toGuild, uint256 toStakers, bytes4 nativeSel, bytes4 assetSel ) external returns (uint256 leftover)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `34dbe093cf458114c81f48e99f28264b4d5d2d07`
- Authority: internal to the hook via delegatecall (caller: CauldronHook._routePerpFee); the deployed library address is callable by anyone but holds no state and no funds
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: no direct transfer; value leaves through `_fundGuild` (FeeRouteLib.sol:97) and `_deliver` (FeeRouteLib.sol:100)
- Edges: FeeRouteLib._fundGuild (FeeRouteLib.sol:97), TRUSTED, library;FeeRouteLib._deliver (FeeRouteLib.sol:100), TRUSTED, library
- Reachability: Delegatecalled from the single site `routePerp` (CauldronHook.sol:1385), which is reached only when the swapper is the perp engine — the branch at `perpEngine` (CauldronHook.sol:1618). The guild share goes through the accounted path and the staker share through `_deliver` (FeeRouteLib.sol:100), which picks the native selector or the ERC20 pull selector the caller passed in. Neither failure reverts: both undelivered shares accumulate into `leftover` (FeeRouteLib.sol:101) and the hook credits them to the reserve.

#### L105 `_move`

- Declaration: `function _move(address asset, address to, uint256 amount) private returns (bool ok)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `d5ece5e62d8ff8ac4ccea24bc1352c33a74da1cb`
- Authority: internal (caller: FeeRouteLib.routeSplit)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: sends native to `to` (line 117), or asks `asset` (line 118) to transfer the ERC20 amount to the encoded recipient
- Edges: to.call (FeeRouteLib.sol:117), UNTRUSTED, out-of-cluster;asset.call (FeeRouteLib.sol:118), UNTRUSTED, out-of-cluster
- Reachability: Private delivery helper. It rejects a codeless destination at `code` (FeeRouteLib.sol:116) before either branch, preventing a successful native transfer to a mistyped EOA from being reported as floor funding. Native and token failures return false; ERC20 empty returns are accepted and bool returns decoded.

#### L139 `_fundGuild`

- Declaration: `function _fundGuild(address asset, address guild, uint256 amount) private returns (bool ok)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `5de5667680ae42062538dc85c8d25ad4d5302ba1`
- Authority: internal (callers: FeeRouteLib.routeSplit, FeeRouteLib.routePerp)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: sends native to the guild at `guild` (line 157); ERC20 approve of `asset` (line 158) then a pull by `guild` (line 160)
- Edges: guild.call (FeeRouteLib.sol:157), UNTRUSTED, out-of-cluster;asset.call (FeeRouteLib.sol:158), UNTRUSTED, out-of-cluster;guild.call (FeeRouteLib.sol:160), UNTRUSTED, out-of-cluster;asset.call (FeeRouteLib.sol:162), UNTRUSTED, out-of-cluster
- Reachability: Private; reached from `_fundGuild` (FeeRouteLib.sol:64) and `_fundGuild` (FeeRouteLib.sol:97). A CODELESS RECIPIENT IS REFUSED BEFORE EITHER BRANCH: the guard at `guild` (FeeRouteLib.sol:156) returns false without moving anything, which covers the native leg as well as the ERC20 one - the earlier form guarded only the token path, and on the native path a `call{value:}` to a codeless address succeeds, so the ether left and the caller was told the guild was funded. On false the caller books the share to the relaunch reserve at `leftover` (FeeRouteLib.sol:65). Native uses the guild's bare receive at `guild` (FeeRouteLib.sol:157); an ERC20 is approved and then pulled by `fundToken` (FeeRouteLib.sol:160) so the dividend can account for it. The approval is only cleared when the pull reports failure at `ok` (FeeRouteLib.sol:162); a pull that succeeds but consumes less than the approved amount leaves the remainder standing. Every call's result is captured rather than bubbled, so this can never revert the swap that produced the fee.

#### L165 `_deliver`

- Declaration: `function _deliver(address asset, address to, uint256 amount, bytes4 nativeSel, bytes4 assetSel) private returns (bool ok)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `59766d939df8997aac38924905bbfdc24a3dcd46`
- Authority: internal (callers: FeeRouteLib.routePerp)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: sends native to the engine at `to` (line 181); ERC20 approve of `asset` (line 184) then a pull by `to` (line 186)
- Edges: to.call (FeeRouteLib.sol:181), UNTRUSTED, out-of-cluster;asset.call (FeeRouteLib.sol:184), UNTRUSTED, out-of-cluster;to.call (FeeRouteLib.sol:186), UNTRUSTED, out-of-cluster;asset.call (FeeRouteLib.sol:189), UNTRUSTED, out-of-cluster
- Reachability: Private; the only call site is `_deliver` (FeeRouteLib.sol:100). A CODELESS RECIPIENT IS REFUSED BEFORE EITHER BRANCH at `to` (FeeRouteLib.sol:179), so no value moves and the caller rolls the staker share into the relaunch reserve at `leftover` (FeeRouteLib.sol:101); on the native leg that is the difference between ether sitting at a codeless address and ether staying in the hook. The selectors are supplied by the caller, so the target entrypoint is chosen at the hook: `nativeSel` (FeeRouteLib.sol:181) for a value-bearing call and `assetSel` (FeeRouteLib.sol:186) for the pull. The dangling-approval cleanup at `approve` (FeeRouteLib.sol:189) runs only on failure. Results are captured, never bubbled.

#### L201 `send`

- Declaration: `function send(address asset, address to, uint256 amount, uint256 gasCap) external returns (bool ok)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `26d5aab1ab25087c67073dd781d0a3d6c705c4ae`
- Authority: internal to the hook via delegatecall (caller: CauldronHook.releaseRelaunchAsset); the deployed library address is callable by anyone but holds no state and no funds
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: sends native to `to` (line 207); sends native with a gas cap to `to` (line 208); ERC20 transfer encoded against `asset` (line 214)
- Edges: to.call (FeeRouteLib.sol:207), UNTRUSTED, out-of-cluster;to.call (FeeRouteLib.sol:208), UNTRUSTED, out-of-cluster;asset.call (FeeRouteLib.sol:214), UNTRUSTED, out-of-cluster
- Reachability: The single in-tree call site is `send` (CauldronHook.sol:1886) inside the registry-gated non-native release, which passes `gasCap` (FeeRouteLib.sol:201) as 0, i.e. the unbounded native branch. A zero amount reports success without moving anything at `amount` (FeeRouteLib.sol:205). The ERC20 branch checks the return payload at `abi` (FeeRouteLib.sol:217), which is what lets the caller keep its counter intact when a token returns false.

#### L231 `deliver`

- Declaration: `function deliver( address asset, address to, uint256 amount, bytes4 nativeSelector, bytes4 selector ) external returns (bool ok)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `7041da4ce53c58ee730a578ff19e31184213ec87`
- Authority: internal to the hook via delegatecall; NO caller anywhere in the source tree
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: sends native to `to` (line 251); ERC20 approve of `asset` (line 254) then a pull by `to` (line 258)
- Edges: to.call (FeeRouteLib.sol:251), UNTRUSTED, out-of-cluster;asset.call (FeeRouteLib.sol:254), UNTRUSTED, out-of-cluster;to.call (FeeRouteLib.sol:258), UNTRUSTED, out-of-cluster;asset.call (FeeRouteLib.sol:261), UNTRUSTED, out-of-cluster
- Reachability: Unreachable from the protocol: `deliver` (FeeRouteLib.sol:231) has no call site in any non-test source file (DERIVED) - the perp fee path uses the private `_deliver` (FeeRouteLib.sol:165) instead, and this external twin is dead weight that still occupies a selector in the deployed library. It now carries the same codeless-recipient refusal as the private twin at `to` (FeeRouteLib.sol:249), ahead of both branches, plus the zero-amount short circuit at `amount` (FeeRouteLib.sol:238).

### LegacyBuyLib

#### L132 `buyStep`

- Declaration: `function buyStep(IPoolManager poolManager, PoolKey calldata key, uint256 amt, uint256 encumbered) external returns (uint256 spent, uint256 got)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `be8f060ecce8efd54c11e7a1f89172eb4774acb4`
- Authority: anyone at the linked library address; in protocol delegatecalled only from CauldronHook.legacyBuyStep
- Gate: `UNGATED`
- Reads: SLIP_SQRT_BPS (line 207, constant);MIN_SQRT_LIMIT (line 209, constant)
- Writes: -
- Value: sends native to `poolManager` (LegacyBuyLib.sol:266), or transfers ERC20 quote to it at `call` (LegacyBuyLib.sol:275), then takes bought currency1 to this delegated context at `take` (LegacyBuyLib.sol:280)
- Edges: IERC20.balanceOf (LegacyBuyLib.sol:145), UNTRUSTED, out-of-cluster;IPoolManager.getSlot0 (LegacyBuyLib.sol:157), TRUSTED, out-of-cluster;LegacyBuyLib._syncRef (LegacyBuyLib.sol:203), TRUSTED, in-cluster;TickMath.getSqrtPriceAtTick (LegacyBuyLib.sol:206), TRUSTED, library;IPoolManager.swap (LegacyBuyLib.sol:212), TRUSTED, out-of-cluster;FullMath.mulDiv (LegacyBuyLib.sol:262), TRUSTED, library;IPoolManager.settle (LegacyBuyLib.sol:266), TRUSTED, out-of-cluster;IPoolManager.sync (LegacyBuyLib.sol:268), TRUSTED, out-of-cluster;q.call (LegacyBuyLib.sol:275), UNTRUSTED, out-of-cluster;IPoolManager.settle (LegacyBuyLib.sol:277), TRUSTED, out-of-cluster;IPoolManager.take (LegacyBuyLib.sol:280), TRUSTED, out-of-cluster
- Reachability: The hook delegatecalls this linked library, so balances and the namespaced reference belong to the hook. Spend is clamped to unencumbered balance at `free` (LegacyBuyLib.sol:146). `_syncRef` (LegacyBuyLib.sol:203) seeds without spending and thereafter moves at most the per-block tick bound. The sqrt limit uses the larger of spot and reference at `lim` (LegacyBuyLib.sol:207); an unreachable limit returns zero before opening deltas. It settles the realized debit at `spent` (LegacyBuyLib.sol:227), rejects zero output, enforces a FullMath-derived minimum at `Slipped` (LegacyBuyLib.sol:263), checks ERC20 return data, and takes output only after settlement.

#### L309 `_syncRef`

- Declaration: `function _syncRef(PoolId pid, int24 tick) private returns (int24 ref, bool seeded)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `a7f05445a569314fe746124687954eb3042a5778`
- Authority: internal (caller: LegacyBuyLib.buyStep)
- Gate: `UNGATED`
- Reads: REF_SLOT (line 310, constant);MAX_TICK_DEV (line 324, constant)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Private price-reference synchronizer reached at `_syncRef` (LegacyBuyLib.sol:203). It reads and writes a keccak-namespaced slot in the delegating hook with `sload` (LegacyBuyLib.sol:312) and `sstore` (LegacyBuyLib.sol:337), rather than a declared library storage variable. A virgin reference is marked with `VIRGIN_BIT` (LegacyBuyLib.sol:321); later blocks clamp tick movement to `MAX_TICK_DEV` (LegacyBuyLib.sol:324), while same-block calls report whether the reference was born in that block.

### ReserveLib

#### L27 `_alignDown`

- Declaration: `function _alignDown(int24 tick, int24 spacing) internal pure returns (int24)`
- Kind/visibility/mutability: `function` / `internal` / `pure`
- Body SHA-1: `ac747d34e207c10ff4944b28b6683f31982f0cb3`
- Authority: internal (callers: ReserveLib.reserveTicks)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure helper, inlined into every importer. In-tree the only call site is `_alignDown` (ReserveLib.sol:55) inside `reserveTicks` (ReserveLib.sol:50); the library itself is imported by PoolOps, outside this cluster (DERIVED). Integer division truncates toward zero, so the negative branch subtracts one to floor toward minus infinity.

#### L34 `_alignUp`

- Declaration: `function _alignUp(int24 tick, int24 spacing) internal pure returns (int24)`
- Kind/visibility/mutability: `function` / `internal` / `pure`
- Body SHA-1: `ca49e30bc6609d49673a4e86ff9cf497373ff5d5`
- Authority: internal (callers: ReserveLib.reserveTicks)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure helper, reached from `_alignUp` (ReserveLib.sol:59) inside `reserveTicks` (ReserveLib.sol:50). Mirrors the down-alignment: the positive branch adds one so the result rounds toward plus infinity.

#### L50 `reserveTicks`

- Declaration: `function reserveTicks(int24 launchTick, int24 spacing, int24 offset) internal pure returns (int24 tickLower, int24 tickUpper)`
- Kind/visibility/mutability: `function` / `internal` / `pure`
- Body SHA-1: `1299c1bb4c6e17c423528f04cd9afc8446ba29a8`
- Authority: internal (callers: out-of-cluster PoolOps)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: ReserveLib._alignDown (ReserveLib.sol:55), TRUSTED, library;ReserveLib._alignUp (ReserveLib.sol:59), TRUSTED, library
- Reachability: Pure tick math with no state and no external calls. Nothing in this cluster calls `reserveTicks` (ReserveLib.sol:50); the callers are in PoolOps and RedemptionExt, outside the cluster (DERIVED). `tickUpper` (ReserveLib.sol:55) is the launch tick less the ceiling offset aligned down, `tickLower` (ReserveLib.sol:59) is the minimum usable aligned tick, and a degenerate ordering collapses to a one-spacing band at `tickUpper` (ReserveLib.sol:64).

#### L75 `liquidityForTokenOut`

- Declaration: `function liquidityForTokenOut(int24 tickLower, int24 tickUpper, uint256 amount1) internal pure returns (uint128 liquidity)`
- Kind/visibility/mutability: `function` / `internal` / `pure`
- Body SHA-1: `821db9d67db8b4419d8ed4be54f108c0307839a9`
- Authority: internal (callers: out-of-cluster PoolOps)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure. No caller inside this cluster (DERIVED). It forwards to the v4-periphery helper at `LiquidityAmounts` (ReserveLib.sol:80) with the two tick prices from `TickMath` (ReserveLib.sol:81) and `TickMath` (ReserveLib.sol:82); those symbols live under lib/ and so are not edges the graph can resolve. Rounding is whatever `getLiquidityForAmount1` (ReserveLib.sol:80) does, which the doc comment states is DOWN.

#### L96 `tokenOutForLiquidity`

- Declaration: `function tokenOutForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity) internal pure returns (uint256 amount1)`
- Kind/visibility/mutability: `function` / `internal` / `pure`
- Body SHA-1: `ca6b8a228e26a48ac11ef6f3dd32a730c72eb016`
- Authority: internal (callers: out-of-cluster PoolOps)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure inverse of the sizing helper; no in-cluster caller (DERIVED). Zero liquidity short-circuits at `liquidity` (ReserveLib.sol:101); otherwise it reads two tick prices via `TickMath` (ReserveLib.sol:102) and `TickMath` (ReserveLib.sol:103) and divides by the Q96 scale with `FullMath` (ReserveLib.sol:105), which truncates (rounds down).

### ILegacyBuffer (declared in RoyaltyRouter.sol)

#### L5 `fundLegacyBuffer`

- Declaration: `function fundLegacyBuffer() external payable`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration only. Both in-cluster dispatches use `fundLegacyBuffer` (RoyaltyRouter.sol:91) or `fundLegacyBuffer` (RoyaltyRouter.sol:108) against immutable `hook` (RoyaltyRouter.sol:91); the implementation is `fundLegacyBuffer` (CauldronHook.sol:1216).

### IAdoptable (declared in RoyaltyRouter.sol)

#### L9 `adopt`

- Declaration: `function adopt(address asset) external returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: interface declaration (no body in this cluster)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declaration used as the advisory booking callback from `adopt` (RoyaltyRouter.sol:122) after ERC20 delivery.

### RoyaltyRouter

#### L77 `constructor`

- Declaration: `constructor(address _hook, address _erc20Sink)`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `2d3f499dcd12b85154e1a1736e2df00c120b8a79`
- Authority: deployer
- Gate: `UNGATED`
- Reads: -
- Writes: hook (line 79, immutable);erc20Sink (line 80, immutable)
- Value: NONE
- Edges: -
- Reachability: Constructor rejects a zero `hook` (RoyaltyRouter.sol:78), freezes it, and freezes `erc20Sink` (RoyaltyRouter.sol:80) to the supplied receiver or the hook fallback. Neither destination can later be redirected.

#### L83 `receive`

- Declaration: `receive() external payable`
- Kind/visibility/mutability: `receive` / `-` / `payable`
- Body SHA-1: `d1b2c59e210e973197505455d6fda2f6d0d0fcf6`
- Authority: anyone sending native currency
- Gate: `UNGATED`
- Reads: FORWARD_GAS_FLOOR (line 90, constant);hook (line 91, immutable)
- Writes: -
- Value: receives native; best-effort sends `msg.value` to `hook` (line 91)
- Edges: hook.call (RoyaltyRouter.sol:91), UNTRUSTED, out-of-cluster
- Reachability: Plain-payable royalty path. Zero-value and stipend-limited calls return at `msg` (RoyaltyRouter.sol:84) and `FORWARD_GAS_FLOOR` (RoyaltyRouter.sol:90), retaining funds for sweep. With enough gas it attempts the immutable hook through `call` (RoyaltyRouter.sol:91) and deliberately ignores failure so a royalty receiver cannot revert the marketplace sale.

#### L101 `sweep`

- Declaration: `function sweep(address asset) external returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `cf4d0248d6f96a90e874bce7c7ab31701b589366`
- Authority: anyone
- Gate: `UNGATED`
- Reads: hook (line 108, immutable);erc20Sink (line 113, immutable)
- Writes: -
- Value: sends held native to `hook` (line 108), or all held `asset` through `_safeTransfer` (line 116) to the immutable-derived recipient
- Edges: ILegacyBuffer.fundLegacyBuffer (RoyaltyRouter.sol:108), TRUSTED, in-cluster;RoyaltyRouter._balanceOf (RoyaltyRouter.sol:114), TRUSTED, in-cluster;RoyaltyRouter._safeTransfer (RoyaltyRouter.sol:116), TRUSTED, in-cluster;IAdoptable.adopt (RoyaltyRouter.sol:122), TRUSTED, in-cluster
- Reachability: Permissionless recovery with no caller-chosen destination. Native sweep sends the full balance to immutable `hook` (RoyaltyRouter.sol:108) and bubbles failure. ERC20 sweep measures the full balance, transfers to immutable `erc20Sink` (RoyaltyRouter.sol:113), then makes a caught advisory `adopt` call (RoyaltyRouter.sol:122); callback failure cannot undo delivery.

#### L126 `_balanceOf`

- Declaration: `function _balanceOf(address asset) private view returns (uint256)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `d7bd0fd8a46ed4d6b17b98b9e164e237241062ce`
- Authority: internal (caller: RoyaltyRouter.sweep)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: asset.staticcall (RoyaltyRouter.sol:128), UNTRUSTED, out-of-cluster
- Reachability: Private balance probe. It invokes caller-selected `asset` through `staticcall` (RoyaltyRouter.sol:128) and requires both success and a full word before decoding, so malformed tokens fail the sweep without moving value.

#### L134 `_safeTransfer`

- Declaration: `function _safeTransfer(address asset, address to, uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `cc71f51e9ceff1b596bce8dc12f5bb13f54c1ea6`
- Authority: internal (caller: RoyaltyRouter.sweep)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: ERC20 transfer of `asset` to immutable-derived `to` (line 136)
- Edges: asset.call (RoyaltyRouter.sol:136), UNTRUSTED, out-of-cluster
- Reachability: Private ERC20 push. The low-level `call` (RoyaltyRouter.sol:136) accepts an empty return or true and otherwise reverts, so sweep cannot emit success without a conforming delivery signal.

### SurtaxLib

#### L33 `surtaxBps`

- Declaration: `function surtaxBps( address pol, PoolId id, uint256 start, uint256 maxBps, uint256 window, uint256 hardCap ) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `120feff94a21d9cfa193a260ea2905531963bf0b`
- Authority: anyone at the linked library address; hook calls it as its fallback surtax policy wrapper
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: ISurtaxPolicy.surtaxBps (SurtaxLib.sol:46), UNTRUSTED, out-of-cluster;SurtaxLib.defaultSurtaxBps (SurtaxLib.sol:50), TRUSTED, in-cluster
- Reachability: External view wrapper. A non-zero caller-supplied policy is queried in try/catch at `surtaxBps` (SurtaxLib.sol:46), and its result is clamped to `hardCap` (SurtaxLib.sol:47). Zero or revert falls through to the built-in curve at `defaultSurtaxBps` (SurtaxLib.sol:50).

#### L54 `defaultSurtaxBps`

- Declaration: `function defaultSurtaxBps(PoolId id, uint256 maxBps, uint256 window, uint256 start) public view returns (uint256)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `af549726b0b5e087d88ce26b3dbe253247c5efc8`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Public view built-in curve. Disabled or unknown inputs return zero at `start` (SurtaxLib.sol:59), elapsed windows return zero, deterministic decay floors division at `decayed` (SurtaxLib.sol:65), and block-derived jitter is added then clamped at `maxBps` (SurtaxLib.sol:126). The caller can observe current-block output before trading; the guaranteed component is the deterministic decay, not unpredictability after inclusion (DERIVED).

### BaseHook

#### L18 `constructor`

- Declaration: `constructor(IPoolManager _manager) ImmutableState(_manager)`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `750ec9cba9df6eee8b38312f49541e4d00115962`
- Authority: deployer
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook.validateHookAddress (BaseHook.sol:19), TRUSTED, in-cluster
- Reachability: Runs once, as part of CauldronHook's construction (`BaseHook` (CauldronHook.sol:578) is its base initialiser). It stores the manager in the v4-periphery `ImmutableState` (BaseHook.sol:18) base and then calls `validateHookAddress` (BaseHook.sol:19), which reverts unless the deployed address' low bits match the permission struct — this is what forces the salt mining.

#### L25 `getHookPermissions`

- Declaration: `function getHookPermissions() public pure virtual returns (Hooks.Permissions memory)`
- Kind/visibility/mutability: `function` / `public` / `pure`
- Body SHA-1: `-`
- Authority: anyone (abstract declaration; the implementation is CauldronHook.getHookPermissions)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Abstract with no body at `getHookPermissions` (BaseHook.sol:25); the deployed contract's version is `getHookPermissions` (CauldronHook.sol:588). Read on-chain only by `getHookPermissions` (BaseHook.sol:32) during construction, and off-chain by deployment tooling.

#### L31 `validateHookAddress`

- Declaration: `function validateHookAddress(BaseHook _this) internal pure virtual`
- Kind/visibility/mutability: `function` / `internal` / `pure`
- Body SHA-1: `aab15c3c4f2b6265c0a1e2171ee4973082cceae9`
- Authority: internal (callers: BaseHook constructor)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook.getHookPermissions (BaseHook.sol:32), TRUSTED, in-cluster
- Reachability: Reached once, from `validateHookAddress` (BaseHook.sol:19). It hands the permission struct to the v4-core `Hooks` (BaseHook.sol:32) validator, which lives under lib/ and is therefore not a resolvable edge. It is `virtual` (BaseHook.sol:31) so a test harness can override it and etch a hook at an arbitrary address; CauldronHook does not override it.

#### L36 `beforeInitialize`

- Declaration: `function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96) external onlyPoolManager returns (bytes4)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `0334cf310c69f91830231b3e6f800ed2d2b16852`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:38)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._beforeInitialize (BaseHook.sol:41), TRUSTED, in-cluster
- Reachability: The v4 pool manager is the only permitted caller — the `onlyPoolManager` (BaseHook.sol:38) modifier comes from the periphery `ImmutableState` base. It forwards to `_beforeInitialize` (BaseHook.sol:41), which CauldronHook does NOT override, so any call reverts `HookNotImplemented`; the permission bit for it is false at `beforeInitialize` (CauldronHook.sol:595), so the manager never calls it.

#### L44 `_beforeInitialize`

- Declaration: `function _beforeInitialize(address, PoolKey calldata, uint160) internal virtual returns (bytes4)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.beforeInitialize)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body: `revert` (BaseHook.sol:45) unconditionally. Reached only from `_beforeInitialize` (BaseHook.sol:41), and unreachable in practice because the matching permission bit is false at `beforeInitialize` (CauldronHook.sol:595).

#### L49 `afterInitialize`

- Declaration: `function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) external onlyPoolManager returns (bytes4)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `a328b88409a6897cf4f2f03c6fafc485d066ce67`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:51)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._afterInitialize (BaseHook.sol:54), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:51). This one IS enabled: `afterInitialize` (CauldronHook.sol:596) is true, so every initialize of a pool naming this hook lands here and is forwarded to the override `_afterInitialize` (CauldronHook.sol:637), which reverts unless the initializer is the registry.

#### L57 `_afterInitialize`

- Declaration: `function _afterInitialize(address, PoolKey calldata, uint160, int24) internal virtual returns (bytes4)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.afterInitialize)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:58). It is shadowed by the override `_afterInitialize` (CauldronHook.sol:637), so the default is never executed in the deployed hook.

#### L62 `beforeAddLiquidity`

- Declaration: `function beforeAddLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData ) external onlyPoolManager returns (bytes4)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `ff0a7aaa7a818dd031e536b15894fe643278cd2e`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:67)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._beforeAddLiquidity (BaseHook.sol:68), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:67). Dead in this deployment: `beforeAddLiquidity` (CauldronHook.sol:597) is false, so the manager never dispatches here, and the forwarded `_beforeAddLiquidity` (BaseHook.sol:68) is not overridden.

#### L71 `_beforeAddLiquidity`

- Declaration: `function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) internal virtual returns (bytes4)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.beforeAddLiquidity)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:76); not overridden by CauldronHook and gated off by the permission bit `beforeAddLiquidity` (CauldronHook.sol:597).

#### L80 `beforeRemoveLiquidity`

- Declaration: `function beforeRemoveLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData ) external onlyPoolManager returns (bytes4)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `edbb8326ef5735222667c90c17afc91261f5142f`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:85)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._beforeRemoveLiquidity (BaseHook.sol:86), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:85). Dead: `beforeRemoveLiquidity` (CauldronHook.sol:599) is false and `_beforeRemoveLiquidity` (BaseHook.sol:86) is not overridden.

#### L89 `_beforeRemoveLiquidity`

- Declaration: `function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) internal virtual returns (bytes4)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.beforeRemoveLiquidity)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:94); gated off by `beforeRemoveLiquidity` (CauldronHook.sol:599).

#### L98 `afterAddLiquidity`

- Declaration: `function afterAddLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData ) external onlyPoolManager returns (bytes4, BalanceDelta)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `579a58516f5fc01469b31345c298105e1dcdcd8f`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:105)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._afterAddLiquidity (BaseHook.sol:106), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:105). Dead: `afterAddLiquidity` (CauldronHook.sol:598) is false and the return-delta bit `afterAddLiquidityReturnDelta` (CauldronHook.sol:607) is false too; `_afterAddLiquidity` (BaseHook.sol:106) is not overridden.

#### L109 `_afterAddLiquidity`

- Declaration: `function _afterAddLiquidity( address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata ) internal virtual returns (bytes4, BalanceDelta)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.afterAddLiquidity)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:117); gated off by `afterAddLiquidity` (CauldronHook.sol:598).

#### L121 `afterRemoveLiquidity`

- Declaration: `function afterRemoveLiquidity( address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData ) external onlyPoolManager returns (bytes4, BalanceDelta)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `ff9104ccfafc9b24f2a5f03e926243a46a3555e0`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:128)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._afterRemoveLiquidity (BaseHook.sol:129), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:128). Dead: `afterRemoveLiquidity` (CauldronHook.sol:600) is false, as is `afterRemoveLiquidityReturnDelta` (CauldronHook.sol:608).

#### L132 `_afterRemoveLiquidity`

- Declaration: `function _afterRemoveLiquidity( address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata ) internal virtual returns (bytes4, BalanceDelta)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.afterRemoveLiquidity)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:140); gated off by `afterRemoveLiquidity` (CauldronHook.sol:600).

#### L144 `beforeSwap`

- Declaration: `function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `a43e1924ec9db2cfcd7060115f37cedadcd90385`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:146)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._beforeSwap (BaseHook.sol:149), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:146). ENABLED: `beforeSwap` (CauldronHook.sol:601) is true and `beforeSwapReturnDelta` (CauldronHook.sol:605) is true, so this is the entry for every swap on an adopted pool and the returned BeforeSwapDelta is honoured. Forwards to the override `_beforeSwap` (CauldronHook.sol:1289).

#### L152 `_beforeSwap`

- Declaration: `function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata) internal virtual returns (bytes4, BeforeSwapDelta, uint24)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.beforeSwap)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:157); shadowed by the override `_beforeSwap` (CauldronHook.sol:1289), so it never runs in the deployed hook.

#### L161 `afterSwap`

- Declaration: `function afterSwap( address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData ) external onlyPoolManager returns (bytes4, int128)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `ac48feff2035ceddc93ef21b017b4b630c51fa29`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:167)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._afterSwap (BaseHook.sol:168), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:167). ENABLED: `afterSwap` (CauldronHook.sol:602) and `afterSwapReturnDelta` (CauldronHook.sol:606) are both true, so the int128 this returns is taken out of the swapper's unspecified leg. Forwards to the override `_afterSwap` (CauldronHook.sol:857).

#### L171 `_afterSwap`

- Declaration: `function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata) internal virtual returns (bytes4, int128)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.afterSwap)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:176); shadowed by the override `_afterSwap` (CauldronHook.sol:857).

#### L180 `beforeDonate`

- Declaration: `function beforeDonate( address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData ) external onlyPoolManager returns (bytes4)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `c52b8e843534422653d4a49fec4d2137a3d842cc`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:186)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._beforeDonate (BaseHook.sol:187), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:186). Dead: `beforeDonate` (CauldronHook.sol:603) is false and `_beforeDonate` (BaseHook.sol:187) is not overridden.

#### L190 `_beforeDonate`

- Declaration: `function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) internal virtual returns (bytes4)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.beforeDonate)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:195); gated off by `beforeDonate` (CauldronHook.sol:603).

#### L199 `afterDonate`

- Declaration: `function afterDonate( address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData ) external onlyPoolManager returns (bytes4)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `bf85b76dee803fab7362a7cb689b1cf66de8c9f6`
- Authority: poolManager
- Gate: `onlyPoolManager (BaseHook.sol:205)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: BaseHook._afterDonate (BaseHook.sol:206), TRUSTED, in-cluster
- Reachability: Pool-manager only via `onlyPoolManager` (BaseHook.sol:205). Dead: `afterDonate` (CauldronHook.sol:604) is false and `_afterDonate` (BaseHook.sol:206) is not overridden.

#### L209 `_afterDonate`

- Declaration: `function _afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) internal virtual returns (bytes4)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `d2b720c4c859999a72ad2a07e9724a7746f91d73`
- Authority: internal (callers: BaseHook.afterDonate)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Default body reverts at `revert` (BaseHook.sol:214); gated off by `afterDonate` (CauldronHook.sol:604).

### HookMiner

#### L23 `find`

- Declaration: `function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs) internal view returns (address, bytes32)`
- Kind/visibility/mutability: `function` / `internal` / `view`
- Body SHA-1: `4b58a8d5471623bab2113e95062d0604c89cf530`
- Authority: internal (callers: deploy scripts and test harnesses, none in this cluster)
- Gate: `UNGATED`
- Reads: FLAG_MASK (line 28, constant);MAX_LOOP (line 32, constant)
- Writes: -
- Value: NONE
- Edges: HookMiner.computeAddress (HookMiner.sol:33), TRUSTED, in-cluster
- Reachability: `find` (HookMiner.sol:23) is a library `internal` function, so it is inlined into whatever unit imports it. No contract in this cluster calls it; the only importers in the tree are deploy scripts and test harnesses (DERIVED). It brute-forces a CREATE2 salt whose address carries the hook-flag bits masked by `FLAG_MASK` (HookMiner.sol:28) and has no deployed code, giving up after `MAX_LOOP` (HookMiner.sol:32) iterations with a revert string.

#### L48 `computeAddress`

- Declaration: `function computeAddress(address deployer, uint256 salt, bytes memory creationCodeWithArgs) internal pure returns (address hookAddress)`
- Kind/visibility/mutability: `function` / `internal` / `pure`
- Body SHA-1: `a98ee6c4b4be399155ff915121e97d452e71110d`
- Authority: internal (callers: HookMiner.find)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure CREATE2 address derivation, called once per loop iteration from `computeAddress` (HookMiner.sol:33). No storage, no external calls: a single `keccak256` (HookMiner.sol:54) over the 0xFF / deployer / salt / init-code-hash preimage.

