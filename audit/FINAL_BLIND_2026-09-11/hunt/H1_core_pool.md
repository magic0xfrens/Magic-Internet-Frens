# H1 — Core pool (CauldronHook / CauldronRegistry / CauldronBase / PoolOps)

Tree: `/tmp/blind-final-h1/contracts/solidity`. PoCs: `test/attacks/X1a_*.t.sol`, `test/attacks/X1b_*.t.sol`
(3 tests, all passing, no fork, no `return;` / `vm.skip` anywhere in the files).

## 1. Model from code

**Adoption.** `CauldronHook._afterInitialize` (CauldronHook.sol:621) is the only way a pool enters the
hook's world: `require(sender == registry)` (:630) then `quoteIsCurrency0[id]` (:647) /
`trackedPools[id] = true` (:648). Every value path in the swap callbacks is gated on `trackedPools`
(:791, :1138). The registry reaches `initialize` only through `PoolOps` under delegatecall, so
`sender` is the registry.

**Swap-side flows.** `_beforeSwap` (:1128) charges exact-input buys; `_afterSwap` (:778) charges the
sell leg; both funnel into `_takeEthFee` (:1426), which `poolManager.take`s on the quote side (:1460)
and records the collected asset in the transient `_feeAsset` (:697, :1459). `_routeEthFee` (:1211)
splits it: proposer carve (native only, :1258) → `IFeeRouter` or built-in guild/floor/relaunch split
→ legacy-buyback carve (:1317) → `FeeRouteLib.routeSplit` sends, leftovers to `_creditReserve` (:1214)
which books `relaunchETH` or `relaunchAsset[asset]`. Perp-sourced fees divert through `_routePerpFee`
(:1195). Out: `releaseRelaunchETH` (:1651) / `releaseRelaunchAsset` (:1679), registry-only;
`claimProposerFees` (:2060), native; `sweepLegacyReserve` (:1112), `legacyRegistry`-only.

**Side effects inside afterSwap**, each gas-bounded and result-ignored: `_maybeLegacyBuyback` (:1015)
→ self-call `legacyBuyStep` (:1063) → `LegacyBuyLib.buyStep`; `_maybePoke` (:1048) → seeder;
`perpEngine.sweepLiquidations(tx.origin)` (:967); `nativeGachaStep` (:2350, self-only).

**Rebirth.** `relaunch()` (CauldronRegistry.sol:767) — permissionless, state-gated on
`hook.isDead` / `minLifetime` / `governor.hasProposals` — retires, force-closes perps, `_removeLiquidity`
(primary + reserve + seeder + rotated legs via a `RECOVER_LEGS` delegatecall, :1607), mines the token,
`PoolOps.seedFunding` (PoolOps.sol:1000) decides the newborn's quote from what is actually held,
`markConsumed` (:977) is the point of no return, then `_seedGeneration` → `_recordSeed` (:1740) →
`hook.setLiveKey`. Facet calls reach `RedemptionExt` through explicit stubs + `_forwardToExt` (:1451),
a full-calldata delegatecall over the shared `CauldronBase` layout.

## 2. Findings

```
id: X1a   severity: High   confidence: VERIFIED
subsystem: CauldronHook fee/buyback accounting
file:line:
  CauldronHook.sol:1096-1098
      function fundLegacyBuffer() external payable {
          legacyBuffer += msg.value;
      }
  CauldronHook.sol:1065-1067
      uint256 amt = legacyBuffer;
      if (amt < legacyThreshold) return;
      legacyBuffer = 0;
  cauldron/LegacyBuyLib.sol:87-94
      address q = Currency.unwrap(key.currency0);
      if (q == address(0)) {
          poolManager.settle{value: spent}();
      } else {
          poolManager.sync(key.currency0);
          IERC20(q).transfer(address(poolManager), spent);
title: A stranger converts native wei into raw units of the live pool's ERC20 quote by
  donating to `fundLegacyBuffer`, and the hook then spends its whole ERC20 relaunch
  reserve buying the iteration token, repeatedly, while the donated ether is locked
  forever.
precondition: the LIVE generation's pool is quoted in an ERC20 (`_liveKey.currency0 != 0`),
  the legacy buyback is armed (`setLegacyBuyback` with a non-zero registry — set by both
  deploy scripts), and the hook holds any balance of that quote (it always does: every
  tracked pool charges a quote-side fee that `_creditReserve` books into
  `relaunchAsset[quote]`, CauldronHook.sol:1214-1218). `legacyBuffer` carries NO
  denomination tag and is never reset at a relaunch, so the same mismatch also arises
  with no attacker at all whenever a generation launches against a different quote than
  the one whose fees are sitting in the buffer. A second, attacker-free entry is
  CauldronHook.sol:1340 — `if (_feeAsset == address(0) && legacyRegistry != address(0))
  legacyBuffer += wantFloor;` — which books NATIVE wei into the buffer with no live-key
  match, unlike the guarded carve twelve lines above it (:1317).
sequence:
  1. attacker (EOA) → hook.fundLegacyBuffer{value: 0.05 ether}()   // > legacyThreshold 0.02e18
  2. anyone → a swap on the live pool. `_afterSwap` (:799) calls `_maybeLegacyBuyback`,
     which self-calls `legacyBuyStep(_liveKey)`.
  3. `LegacyBuyLib.buyStep` swaps exact-input `amt = 5e16` with `sqrtPriceLimitX96 =
     MIN_SQRT_LIMIT` (no slippage bound at all) and settles what the pool absorbed in
     `key.currency0` — the ERC20 — out of the hook's own balance.
  4. `if (spent < amt) legacyBuffer += amt - spent;` leaves the buffer armed, so step 2
     repeats on every subsequent swap until the hook's quote balance is zero.
attacker_cost: 0.05 ETH (donated, and unrecoverable by anyone) + ~60k gas.
damage: measured in the PoC — 5e16 raw quote units demanded against a 5,000 USDG (6-dec)
  reserve; the entire reserve left the hook in one swap; the hook's ETH balance did not
  move; 4.9999995e16 stayed in the buffer, re-arming the drain. Where the hook's quote
  balance is smaller than the pool can absorb, the settle transfer reverts instead and the
  collection-floor buyback is permanently dead (the buffer can only shrink through the
  very call that reverts), and every future `legacyBps` carve is locked with it.
poc: test/attacks/X1a_LegacyBufferDenomination.t.sol   needs_fork: no
```

```
id: X1b   severity: Medium   confidence: VERIFIED
subsystem: CauldronHook anti-sniper surtax (computed inside beforeSwap)
file:line: CauldronHook.sol:1410-1416
      (, int24 tick,,) = poolManager.getSlot0(id);
      uint256 rnd = uint256(
          keccak256(abi.encodePacked(blockhash(block.number - 1), PoolId.unwrap(id), block.number, tick))
      ) % (maxBps + 1);
      uint256 jitter = (rnd * remaining) / window;
      uint256 total = decayed + jitter;
title: A sniper grinds the anti-sniper surtax down to its fully-public deterministic
  floor by setting the pool tick with a probe swap in the same transaction as the buy.
precondition: none beyond a live tracked pool inside the 30-block snipe window
  (`snipeWindowBlocks = 30`, CauldronHook.sol:506). `_defaultSurtaxBps` is reached from
  `_takeEthFee` (:1441) on the BUY leg in `_beforeSwap`, i.e. the rate is read BEFORE the
  priced swap executes, so the tick it reads is the one the attacker just set.
sequence:
  1. attacker, off-chain: `blockhash(block.number-1)`, `block.number` and `PoolId` are all
     known at submission time (the code comment at :1392 concedes this). Solve for a tick
     that minimises `rnd`.
  2. attacker → one transaction: probe swap sized to land the pool on that tick, then the
     real buy. `_beforeSwap` prices the buy at `decayed + 0`.
attacker_cost: gas for one extra tiny swap (its own fee is charged on a dust amount).
damage: measured at 10 blocks into the window — the surtax over the tick range
  [-2500, 2500] spans 6402 bps (min, tick -1526) to 9600 bps (max), against a
  deterministic decay of 6400. A probe swap is worth up to 3198 bps = 31.98% of the buy.
  The jitter term is purely additive and shares the `remaining/window` factor with
  `decayed`, so grinding always lands on `decayed` — exactly the predictability the
  jitter was added to remove. Loss is to the genesis dividend, which receives 100% of
  the surtax (`_takeEthFee`:1468-1476).
poc: test/attacks/X1b_SurtaxJitterSteerable.t.sol   needs_fork: no
```

```
id: X1c   severity: Low   confidence: DERIVED
subsystem: CauldronHook fee exemption
file:line: CauldronHook.sol:2383-2384
      function _isExemptPlayer(address sender, bytes calldata hookData) private view returns (bool) {
          return taxExempt[_taxedPlayer(sender, hookData)] && isOpener[sender];
      }
title: `setTaxExempt` alone exempts nobody — a wallet flagged exempt that swaps directly
  (or through any router that is not a registered opener) still pays the full base tax
  plus the ~99% launch surtax.
precondition: the exempt wallet's `sender` is not in `isOpener`. Two shipped deploy
  scripts do exactly this: `deploy/DeployLaunchSniper.s.sol:37`
  (`IHookExempt(hook).setTaxExempt(address(sniper), true);`, no `setOpener`) and
  `deploy/DeployLaunchpad.s.sol:504` (`hook.setTaxExempt(vm.envOr("SNIPE_WALLET", deployer),
  true);`, no `setOpener`). `DeployCauldron.s.sol:110-111` and `DeployLaunchpad.s.sol:332-333`
  DO pair both for the registry, which is why the green-candle path is unaffected.
sequence: 1. owner → hook.setTaxExempt(snipeWallet, true). 2. snipeWallet → a direct
  launch-block buy. `_taxedPlayer` returns `sender` (:2392, `!isOpener[sender]`), and the
  `&& isOpener[sender]` conjunct is false, so the buy is charged at `MAX_TOTAL_FEE_BPS`.
attacker_cost: n/a (self-inflicted config defect, not an attack).
damage: up to 99% of the deployer's one-time airdrop-funding buy. The declaration's own
  docstring (:443-447, "pay ZERO base tax + ZERO anti-sniper surtax") describes behaviour
  the code does not implement for any non-opener.
poc: none (deploy-script surface; mechanism is a two-line read)   needs_fork: no
```

## 3. Refutations

* **Next-generation PoolKey squat — HELD.** `_afterInitialize` (CauldronHook.sol:621) opens with
  `require(sender == registry)` (:630). Since the key names this hook, every `initialize` on it must
  pass that callback, so a stranger cannot pre-initialize the newborn's key. The token itself is
  plain `CREATE` (`_deployToken`, CauldronRegistry.sol:623 doc / PoolOps.deployTokenAbove), and
  `predictTokenAddress` was removed. Attacked by trying to find any other `initialize` caller:
  `PoolOps` only calls it at :222, :298, :467 and :877, all delegatecalled from the registry.
* **Green-candle credit farming — HELD.** I expected `relaunch()`'s huge reserve buy to credit
  `tx.origin` through the untagged branch at CauldronHook.sol:873-875 and mint out the newborn
  collection for free. Two independent guards stop it: `PoolOps.executeBuy` tags the swap with
  `abi.encode(address(this))` (PoolOps.sol:513) so `player == registry` is nulled at :880, and the
  credit block is additionally gated on `Currency.unwrap(key.currency1) == Currency.unwrap(_liveKey.currency1)`
  (:864) while `_liveKey` still points at the dying generation (`setLiveKey` runs later, at
  CauldronRegistry.sol:1748). Not PoC'd — refuted on the second read before building.
* **Registry forwarders inheriting the facet gate — HELD.** All ten stubs were checked against the
  facet body: `setRotationWiring` (RedemptionExt.sol:260) and `sweepLegProceeds` (:794) are
  `onlyOwner`; `rotateSlice`/`rotateSliceFrom` (:269/:280) require a wired rotator AND an unspent
  governor mandate (:293, :302, :317); `redeemOgFren` (:78), `buyTreasuryOgFren` (:115),
  `donateToReserve` (:136), `materializeLegacyReserve` (:147) are `nonReentrant` + `summoned`-gated.
  Because `_forwardToExt` is a delegatecall over the shared `CauldronBase` layout, `owner()` and the
  reentrancy slot resolve to the registry's own storage. `recoverLegs` (:699) is `public` and
  ungated, but it only unwinds the registry's own legs back into the registry.
* **`linkVolume` volume inflation / death-lock — HELD.** Registry-only (CauldronHook.sol:1563),
  self-link rejected (:1576), list capped at `MAX_SIBLINGS` (:1579), and re-linking is idempotent
  (:1581-1583). I attacked it as an unbounded `isDead` loop; all three legs are closed.
* **Stale 24h volume buckets holding a generation open forever — HELD.** `_recordVolume` zeroes the
  whole ring after a >24h gap (:1496-1499) and zeroes exactly the skipped buckets on a partial wrap
  (:1500-1508); `getVolume24h` additionally short-circuits to 0 past the window (:1522).
* **`nativeGachaStep` free-crystal mint — HELD.** `if (msg.sender != address(this)) revert OnlySelf();`
  (CauldronHook.sol:2351). Same for `legacyBuyStep` (:1064).
* **Breaking the per-generation claim guarantee by donating tokens into the dying LP — HELD
  (DERIVED, algebra not PoC'd).** With supply `S = L + H` (LP + circulating), donating `A ⊆ H`
  gives `tokensFromLP = L + A` and `newReserve = S - newActive = (H - A) + unclaimedGenesis + legacy`
  — still exactly the post-donation circulating float. The `newActive > TOTAL_SUPPLY` clamp
  (CauldronRegistry.sol:1056) is therefore reachable only by a quote-side/fee donation, which does
  not shrink the reserve below the float.

## 4. Leads

* **HYPOTHESIS — `crystallizeCollection` mixes two denominations.** `PoolOps.crystallizeCollection`
  computes `FullMath.mulDiv(swept, activeBase, totalETH)` (PoolOps.sol:1356) where `swept` is NATIVE
  ether from `CauldronVault.close()` and `totalETH` is whatever `seedFunding` returned — denominated
  in the NEWBORN's quote (PoolOps.sol:1000 returns `amount` "in ITS OWN units"). On a non-native
  rebirth the ratio is off by the price × decimals gap. *Next step:* force `seedFunding` to return a
  6-decimal quote and assert `collectionLedger.totalEntitled()` against the native-quote baseline.
* **HYPOTHESIS — this is the gating question for X1a's severity.** A non-native PRIMARY generation
  looks hard to reach: `seedFunding` branch 1 needs `recovered == 0 || oldQuote == wantQuote`
  (PoolOps.sol:1053), and `recovered` is the summed `ethFromLP` of primary + reserve + seeder +
  same-quote legs (CauldronRegistry.sol:1560-1614). *Next step:* rotate 100% of a treasury out of the
  launch pair and measure whether `_removeLiquidity` really returns exactly 0 on the launch quote. If
  it can, X1a is Critical rather than High; if it cannot, the attacker-free carry-over variant
  (CauldronHook.sol:1340) is the only live entry.
* **HYPOTHESIS — `legacyOwedToReserve` is one counter over two tokens.** `legacyBuyStep` credits it in
  the LIVE token (:1086) and `sweepLegacyReserve(token, to)` clamps to `balanceOf(token)` (:1114-1117).
  `_flushLegacyAtRelaunch` (CauldronRegistry.sol:1494) drains it with the OLD token before the new key
  is recorded, which looks correct — but a buyback that lands on the newborn before a later flush would
  be measured against the wrong balance. *Next step:* drive two relaunches with an unflushed buyback
  in between and assert the ledger credit.
* **HYPOTHESIS — the view forwarders are not views.** `floorClaimableNow` / `legCount` / `legAt`
  (CauldronRegistry.sol:1418-1430) go through `_forwardToExtView` → `_forwardToExt` (a delegatecall),
  so they are `nonpayable`. Any on-chain Solidity integrator that declares them `view` gets a
  `staticcall` that reverts. *Next step:* grep the app/indexer for a `view` declaration of these three.
* **Map check.** No contradiction found between `graph/pool.md` and source on anything I verified;
  its section F already flags the `crystallizeCollection` unit mix above, which my read confirms.
