# H1 — Core pool (CauldronHook / CauldronRegistry / CauldronBase / PoolOps / SurtaxLib / NativeQuoteZap)

Branch `redteam/2026-09-11`. Worked from a decontaminated copy at
`/tmp/blind-final-h1/contracts/solidity` (line numbers match the real tree 1:1).

## 1. Model from code

**Adoption.** `CauldronHook._afterInitialize` (CauldronHook.sol:625) is the only
gate that matters: `require(sender == registry)` (:633). Everything else in the
hook keys off `trackedPools[id]` and `quoteIsCurrency0[id]`, both written only
there. `quoteIsCurrency0 = IRegistryQuotes(registry).allowedQuote(currency0)`
(:648); the quote is always currency0 in practice because
`PoolOps.deployTokenAbove` (PoolOps.sol:748) mines the token above
`QUOTE_WATERMARK = 0xf000…` (PoolOps.sol:713) and `setAllowedQuote`
(CauldronRegistry.sol:314) refuses any quote at/above that watermark and refuses
to de-list native (`allowedQuote[address(0)] = true`, CauldronRegistry.sol:181,
and `NativeQuoteRequired` at :315).

**Swap path.** `_beforeSwap` (:1221) charges exact-input buys, refuses the
exact-output sell quadrant (`ExactOutSellUnsupported`, :1255). `_afterSwap`
(:782) in order: `_maybeLegacyBuyback` (:1019) → `_maybePoke` (:1086) → volume
(`_toUsd` :745 → `_recordVolume` :1553) → crystal credit (gated on
`key.currency1 == _liveKey.currency1`, :863) → perp `sweepLiquidations` on
`tx.origin` (:950) → native gacha self-call (:967) → `_takeEthFee` (:1488) →
`_maybeLegacyBuyback` again. Every side-effect call is gas-capped and
result-ignored; all four `MIN > RESERVE` (:160–:365), so no `gasleft()`
underflow.

**Assets in/out.** In: `poolManager.take(feeCur, address(this), total)` (:1517)
and `fundLegacyBuffer()` (:1148, permissionless payable). Out: guild/vault via
`FeeRouteLib.routeSplit` (delegatecall), `legacyBuyStep` (:1102, self-only) into
`_liveKey` only, `claimProposerFees` (:2146, native), `releaseRelaunchETH`
(:1713) / `releaseRelaunchAsset` (:1741), both registry-gated.
`_creditFor` (:1310) denominates the residual.

**Death → relaunch.** `isDead` (:1656) sums `getVolume24h(id)` plus up to
`MAX_SIBLINGS = 9` linked siblings (`linkVolume`, :1624, registry-only).
`CauldronRegistry.relaunch()` (:821) gates on `hook.isDead(oldPoolId)` (:832),
`minLifetime` (:836), `governor.hasProposals()` (:840); consumes at
`governor.markConsumed(winId)` (:1031); everything to the right of that line
(`_seedGeneration` :1131, `_deployCollection` :1138, `setNftCurveFrom` :1144)
must be total or the machine bricks.

**Cross-subsystem.** hook→registry (`allowedQuote`), registry→hook
(`setLiveKey`/`setCollection`/`setActiveProposer`/`setNftCurveFrom`/
`forceClosePerps`), hook→PerpEngine (in-swap sweep), hook→CauldronSeeder
(`pokeInSwap`), registry→RedemptionExt (delegatecall via `_forwardToExt`,
CauldronRegistry.sol:1505).

## 2. Findings

```
id: K1a   severity: High   confidence: VERIFIED
subsystem: CauldronHook volume/death detector
file:line: CauldronHook.sol:1558-1571 and CauldronHook.sol:1584
  1558:  if (block.timestamp > lastTs + SECONDS_PER_DAY) {
  1559:      for (uint256 i = 0; i < HOURS_PER_DAY; i++) {
  1560:          _volumeBuckets[id][i] = 0;
  1561:      }
  1562:  } else if (currentBucket != lastBucket) {
  ...
  1583:  function getVolume24h(PoolId id) public view returns (uint256 total) {
  1584:      if (block.timestamp > _lastUpdateTs[id] + SECONDS_PER_DAY) return 0;
title: One wei of trading per day, timed into the same hour-of-day bucket,
       keeps arbitrarily old volume inside the "24h" window forever, so
       `isDead()` never returns true and `relaunch()` reverts `TokenStillAlive`
       for as long as the attacker keeps pinging.
precondition: A tracked (registry-created) pool. Nothing else. Directly
       reachable on the live primary pool of any generation.
sequence:
  1. attacker (anyone) swaps >= `deathThreshold` of quote through the pool once,
     at timestamp T. `_recordVolume` writes bucket b = (T/3600)%24 and sets
     `_lastUpdateTs = T`.
  2. at T + 86400 exactly (any timestamp in [T+86400-s, T+86400], where s is T's
     offset within its hour, i.e. a window up to ~1h wide) the attacker swaps
     1 wei. `block.timestamp > lastTs + SECONDS_PER_DAY` is FALSE (86400 is not
     > 86400) and `currentBucket == lastBucket`, so NEITHER clearing branch runs.
     Bucket b keeps its full value and `_lastUpdateTs` advances a whole day.
  3. repeat step 2 once per day, forever.
  4. `CauldronRegistry.relaunch()` (:832) `if (!hook.isDead(oldPoolId)) revert
     TokenStillAlive();` — reverts on every call, from every caller.
attacker_cost: one swap of `deathThreshold` size once (fee = taxRate bps of it),
       then 1 wei + ~60-80k gas per day. At 1 gwei that is far under $0.01/day.
damage: the eternal machine's core promise ("permissionless relaunch once the
       pool is dead") is suspended indefinitely at negligible cost; every holder
       of the dying iteration is stranded in a dead token with no migration
       path. Zero profit to the attacker except that the incumbent
       `activeProposer` keeps earning `proposerBps` of every fee (:1352) and the
       incumbent LP keeps its position. Not permanent in the strict sense — it
       lapses if the attacker stops paying — hence High rather than Critical.
poc: contracts/solidity/test/attacks/K1a_StaleVolumeKeepsAlive.t.sol
needs_fork: no
```

Measured output of the PoC (`forge test --match-path 'test/attacks/K1*' -vv`):

```
Ran 1 test for test/attacks/K1a_StaleVolumeKeepsAlive.t.sol:K1a_StaleVolumeKeepsAlive
[PASS] test_K1a_staleBucketBlocksRelaunchForever() (gas: 701243)
Logs:
  elapsed_seconds: 2592000
  volume24h_reported: 10000000000000000030
```

i.e. after 30 days and 30 wei of trading, `getVolume24h` still reports the
original 10 ETH swap, and `isDead()` is false. The **positive liveness control
is in the same test** and asserted first: a second pool (`fee = 500`) that takes
the identical 10 ETH swap and is then left alone reports `isDead() == true`
after 86,401 s (`assertTrue(controlDead, ...)`). So the window does expire when
nobody games it; it is the same-bucket ping that defeats it.

The PoC drives production bytecode: the test contract is the PoolManager
(`_deployOffchain(address(this))`), calls `hook.afterInitialize(address(registry),
key, …)` to pass the real adoption gate at CauldronHook.sol:633, then calls
`hook.afterSwap(...)` with an exact-input zeroForOne buy — which records volume
and then early-returns at :983 (`unspecifiedIsCurrency0 != q0`) before any
`take`, so no pool liquidity is faked. No `return;` and no `vm.skip` appear
anywhere in the file (`grep -n "return;\|vm.skip"` → no match, exit 1); all
conditional logic is in two internal helpers returning into locals.

Two corollaries worth stating separately, both DERIVED:
* **No attacker is required for the correctness half.** Even under honest
  trading, `getVolume24h` counts volume up to 47h59m old whenever the last swap
  of a day lands in a late bucket. `deathThreshold` therefore does not mean what
  it says, in the safe-for-incumbents direction.
* The same staleness is inherited by `isDead`'s sibling sum (:1660-1662), so one
  gamed sibling pool holds the whole generation open.

## 3. Refutations (attacked hard, held)

1. **PoolKey / token-address squatting before `relaunch()`.** v4's `initialize`
   never touches the currency contracts, so a stranger *can* name an
   as-yet-undeployed token in a PoolKey. The hook closes it: `_afterInitialize`
   (:625) has `require(sender == registry)` at :633 and the hook carries
   `AFTER_INITIALIZE_FLAG`, so a foreign initialize reverts rather than going
   untracked. Changing the `hooks` field to dodge the gate changes the PoolId, so
   the registry's key stays free. `PoolOps.deployTokenAbove` (:748) CREATE2s from
   `address(this)` — the registry, because PoolOps is delegatecalled — with
   `salt = keccak256(abi.encode(gen, i))` and an initHash over
   `(name, symbol, gen, registry, supply)`; no third party can occupy it, and
   distinct generations/proposals give distinct addresses. `PoolOps.openOrAddPair`
   (:900) correctly re-throws `PoolInitRefused` instead of swallowing the hook's
   refusal as "already open" (:943-949). Attacked; held.

2. **A poisoned `BrewSpec` bricking relaunch past `markConsumed`.** The one
   unclamped-looking field is the collection metadata:
   `CauldronCollection`'s constructor reverts `BadConfig()` when
   `mode == MetadataMode.Renderer && (renderer == 0 || renderer.code.length == 0)`
   (CauldronCollection.sol:222-226), and `CauldronRegistry._deployCollection`
   (:1188) only defaults the *BaseURI* case, never the renderer. That would be a
   permanent brick (revert to the right of `markConsumed` at :1031). It is closed
   *upstream*: `CauldronGovernor._propose` validates both modes at proposal time
   (`revert BadRenderer()` when `renderer == 0 || renderer.code.length == 0`).
   Post-Cancun (EIP-6780) a contract with code cannot be removed, so the check
   cannot be stale. The other post-`markConsumed` calls are total:
   `hook.setActiveProposer` (:2131, no input validation),
   `hook.setNftCurveFrom` (:2169, `if (_base == 0) return;`),
   `_perpHousekeep(true)` (try/catch, :1160). `nftSupply` is clamped at :963.
   Held — but see Lead L4, the registry-side clamp is missing as defence in depth.

3. **`_curvePos()` underflow bricking the gacha.** `minted + outstandingOf[col]
   - mintBaseline` (:2197-2200) is checked arithmetic and `mintBaseline` is
   pinned to `totalMinted()` at `setCollection` (:2049). A burn would underflow
   it and brick `_commitCrystals`. Both collections' counters are monotone:
   `CauldronCollection.totalMinted` is only `++totalMinted` at :210 and
   `burnFromVault` (:429) does not decrement it; `MiFrensGenesis.minted` (:139)
   is only incremented (:282, :478) and `burnFromVault` (:579) does not touch it.
   Held.

4. **Gas-bomb / OOG of the parent swap through the four in-swap side calls.**
   `LIQ_GAS_MIN 400k > LIQ_GAS_RESERVE 180k`, `GACHA_GAS_MIN 500k > 200k`,
   `LEGACY_GAS_MIN 300k > 220k`, `SEED_POKE_GAS_MIN 750k > 350k`
   (CauldronHook.sol:160-365), so `gasleft() - RESERVE` can never underflow under
   0.8.x checked arithmetic, and the 63/64 rule preserves the reserve. Held.

5. **Legacy-buyback denomination drain.** `_maybeLegacyBuyback` (:1019) drains a
   mismatched buffer to `_creditFor(legacyBufferAsset, stale)` *before* the
   threshold test (:1048-1055); `legacyBuyStep` re-asserts
   `legacyBufferAsset == key.currency0` (:1124) and passes the encumbering
   counter into `LegacyBuyLib.buyStep`, which clamps to `bal - encumbered`
   (LegacyBuyLib.sol:145-147). `proposerOwed` is carved out of `feeAmount`
   (:1356-1359) before `relaunchETH` is credited, so it is never inside the
   clamped "free" balance in a way that can overspend. Held.

6. **Surtax manipulability inside the swap.** `SurtaxLib.defaultSurtaxBps`
   (SurtaxLib.sol:53) seeds only on `blockhash(block.number-1)`,
   `PoolId`, `block.number`, `prevrandao` — nothing the swapper can move inside
   its own transaction — and `total >= decayed` holds for every input. The
   block-shopping weakness is documented and bounded by the decay. Held.

## 4. Leads (HYPOTHESIS — exact next step given)

* **L1 — native buffer on a rotated generation.** `_routeEthFee`'s no-vault
  branch (CauldronHook.sol:1436-1443) buffers a *native* fee whenever
  `_feeAsset == address(0)`, without checking that `_liveKey.currency0` is also
  native — unlike the primary carve at :1417, which does check. On a generation
  rotated to USDG with `vault == address(0)`, a native fee from a sibling pool
  therefore sets `legacyBufferAsset = address(0)` while the live pool is
  ERC20-quoted. `_maybeLegacyBuyback` then drains it to `relaunchETH` on the next
  swap, so nothing strands — but the buffer is unusable for its purpose for the
  generation's whole life, and `fundLegacyBuffer` royalties follow the same path.
  *Next step:* fork test — set `_liveKey` to a USDG key via `registry`, clear
  `vault`, drive a native-quote sibling swap, assert `legacyBufferAsset == 0`
  while `_liveKey.currency0 == USDG`, then measure how much royalty value never
  reaches the collection floor over N swaps.

* **L2 — `_getHolderTaxRate` is uncapped on the NFT path.** :1686-1693 returns
  whatever `INFTContract(nftContract).getHolderTaxRate(holder)` says, with no
  floor and no cap; `setDefaultTaxBps` caps at `MAX_TAX_BPS = 1000` but this path
  does not. A tier contract returning 0 makes `_takeEthFee` return 0 (:1506) —
  free wash trading, hence free crystal credit and a free mint-out of the whole
  collection. No implementation of `getHolderTaxRate` exists anywhere in the tree
  (grepped `CauldronHook.sol`, `CauldronToken.sol`, `cauldron/`), and
  `setNftContract` is `onlyOwner` (:1963), so it is latent. *Next step:* write a
  tier stub returning 0, `setNftContract` it, and count NFTs minted per ETH of
  round-trip volume against the honest baseline.

* **L3 — `linkVolume` reverts at the cap.** :1645 `if (sib.length >=
  MAX_SIBLINGS) revert OnlyRegistry();`. The caller is
  `RedemptionExt.rotateSliceFrom`, so the 10th distinct destination quote makes
  the whole rotation revert rather than degrading. H2's subsystem; flagged here
  because the revert lives in my file. *Next step:* drive 10 rotations to
  distinct allowlisted quotes on a fork and confirm the 10th `rotateSlice`
  reverts whole.

* **L4 — no registry-side clamp on `spec.mode`/`spec.renderer`.** The comment at
  CauldronRegistry.sol:958-963 explicitly justifies clamping `nftSupply` at the
  registry so it "survives a governor swap". `mode`/`renderer`/`baseURI` get no
  such treatment, and `_deployCollection` (:1188) only defaults the BaseURI case.
  A governor replaced via `setGovernor` (:585, onlyOwner) that omits the
  `BadRenderer` check re-opens Refutation 2 as a permanent brick. *Next step:*
  deploy a minimal `ICauldronGovernor` stub with no renderer validation, wire it,
  win a `mode = Renderer, renderer = address(0)` proposal, call `relaunch()`
  twice, and assert the second call reverts identically.
