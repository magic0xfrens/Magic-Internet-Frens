# `perp` function graph — current-tree semantic refresh

Status: DERIVED static graph annotations. Solidity was not modified and no exploit claim is made here.

- Current skeleton: **216 nodes** across **5 files**.
- Reused after source-line remap: **0** unchanged bodies.
- Re-read and regenerated from current bodies: **155 changed**, **61 added**.
- Removed obsolete nodes: **8**.

- Carried nodes regenerated after current-line citation checks: **0**.

Each row is keyed by the immutable skeleton. `R/W/E` is the count of direct storage reads, writes, and resolved call edges recorded in the machine graph; it is not transitive coverage.

## `cauldron/PerpEngine.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 23 | `IPerpRegistry (declared in PerpEngine.sol)` | `currentToken` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 27 | `IPerpRegistry (declared in PerpEngine.sol)` | `generationQuote` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 28 | `IPerpRegistry (declared in PerpEngine.sol)` | `currentGeneration` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 29 | `IPerpRegistry (declared in PerpEngine.sol)` | `lastSummonAt` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 30 | `IPerpRegistry (declared in PerpEngine.sol)` | `generationPoolId` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 31 | `IPerpRegistry (declared in PerpEngine.sol)` | `generationToken` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 32 | `IPerpRegistry (declared in PerpEngine.sol)` | `claimByBurn` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 33 | `IPerpRegistry (declared in PerpEngine.sol)` | `claimByBurnUpTo` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 41 | `IMarkSource (declared in PerpEngine.sol)` | `weightedTick` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 46 | `IPerpVaultStake (declared in PerpEngine.sol)` | `hasStakers` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 48 | `IPerpVaultStake (declared in PerpEngine.sol)` | `hasQuoteStake` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 52 | `IPerpHook (declared in PerpEngine.sol)` | `isDead` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 54 | `IPerpHook (declared in PerpEngine.sol)` | `collection` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 224 | `PerpEngine` | `_quoteIsNative` | `internal` | internal; reachable only through Solidity callers | 1/0/0 |
| 232 | `PerpEngine` | `_pullQuote` | `internal` | internal; reachable only through Solidity callers | 1/0/2 |
| 250 | `PerpEngine` | `_pushQuote` | `internal` | internal; reachable only through Solidity callers | 1/0/3 |
| 499 | `PerpEngine` | `renounceOwnership` | `public` | anyone | 0/0/1 |
| 539 | `PerpEngine` | `constructor` | `constructor` | deployer (constructor executes once) | 1/16/3 |
| 577 | `PerpEngine` | `notNested` | `modifier` | internal; reachable only through Solidity callers | 0/0/2 |
| 578 | `PerpEngine` | `onlyVault` | `modifier` | internal; reachable only through Solidity callers | 0/0/2 |
| 579 | `PerpEngine` | `_notNested` | `internal` | internal; reachable only through Solidity callers | 2/0/1 |
| 580 | `PerpEngine` | `_onlyVault` | `internal` | internal; reachable only through Solidity callers | 1/0/1 |
| 585 | `PerpEngine` | `totalEth` | `public` | anyone | 2/0/0 |
| 587 | `PerpEngine` | `freeEth` | `external` | anyone | 1/0/0 |
| 589 | `PerpEngine` | `totalTokenAssets` | `public` | anyone | 2/0/0 |
| 591 | `PerpEngine` | `freeToken` | `external` | anyone | 1/0/0 |
| 602 | `PerpEngine` | `_tok` | `internal` | internal; reachable only through Solidity callers | 1/0/3 |
| 603 | `PerpEngine` | `_gq` | `internal` | internal; reachable only through Solidity callers | 1/0/3 |
| 606 | `PerpEngine` | `_bal` | `internal` | internal; reachable only through Solidity callers | 0/0/2 |
| 607 | `PerpEngine` | `_liq` | `internal` | internal; reachable only through Solidity callers | 1/0/3 |
| 608 | `PerpEngine` | `_col` | `internal` | internal; reachable only through Solidity callers | 1/0/2 |
| 609 | `PerpEngine` | `_gen` | `internal` | internal; reachable only through Solidity callers | 1/0/3 |
| 611 | `PerpEngine` | `_key` | `internal` | internal; reachable only through Solidity callers | 4/0/3 |
| 618 | `PerpEngine` | `_pid` | `internal` | internal; reachable only through Solidity callers | 0/0/3 |
| 620 | `PerpEngine` | `_slot0` | `internal` | internal; reachable only through Solidity callers | 1/0/3 |
| 621 | `PerpEngine` | `_sqrtP` | `internal` | internal; reachable only through Solidity callers | 0/0/3 |
| 673 | `PerpEngine` | `_q` | `internal` | internal; reachable only through Solidity callers | 1/0/2 |
| 711 | `PerpEngine` | `_currentTick` | `internal` | internal; reachable only through Solidity callers | 2/0/4 |
| 735 | `PerpEngine` | `poke` | `external` | anyone | 0/0/2 |
| 774 | `PerpEngine` | `_writeObs` | `internal` | internal; reachable only through Solidity callers | 2/0/3 |
| 799 | `PerpEngine` | `twapTick` | `public` | anyone | 2/0/3 |
| 856 | `PerpEngine` | `blocksVolumeLink` | `external` | anyone | 1/1/3 |
| 862 | `PerpEngine` | `markSqrtPriceX96` | `public` | anyone | 0/0/5 |
| 867 | `PerpEngine` | `activeEthDepth` | `public` | anyone | 0/0/5 |
| 873 | `PerpEngine` | `maxLeverage` | `public` | anyone | 2/0/4 |
| 892 | `PerpEngine` | `_quoteAt` | `internal` | internal; reachable only through Solidity callers | 0/0/3 |
| 896 | `PerpEngine` | `_quoteEth` | `internal` | internal; reachable only through Solidity callers | 0/0/4 |
| 898 | `PerpEngine` | `_quoteMark` | `internal` | internal; reachable only through Solidity callers | 0/0/4 |
| 901 | `PerpEngine` | `_pokeFunding` | `internal` | internal; reachable only through Solidity callers | 4/2/3 |
| 926 | `PerpEngine` | `_fundingDelta` | `internal` | internal; reachable only through Solidity callers | 3/0/2 |
| 956 | `PerpEngine` | `_pos` | `internal` | internal; reachable only through Solidity callers | 1/0/2 |
| 959 | `PerpEngine` | `fundingDelta` | `external` | anyone | 0/0/4 |
| 980 | `PerpEngine` | `openLong` | `public` | anyone | 3/2/10 |
| 1011 | `PerpEngine` | `openShort` | `public` | anyone | 3/2/12 |
| 1040 | `PerpEngine` | `close` | `external` | caller restricted by explicit msg.sender check | 1/0/4 |
| 1047 | `PerpEngine` | `liquidate` | `external` | anyone | 1/0/6 |
| 1100 | `PerpEngine` | `sweepLiquidations` | `external` | caller restricted by explicit msg.sender check | 1/0/1 |
| 1112 | `PerpEngine` | `_project` | `internal` | internal; reachable only through Solidity callers | 0/0/6 |
| 1124 | `PerpEngine` | `selfSweep` | `external` | caller restricted by explicit msg.sender check | 0/0/2 |
| 1131 | `PerpEngine` | `_sweepAfterOpen` | `internal` | internal; reachable only through Solidity callers | 1/0/2 |
| 1147 | `PerpEngine` | `_doSweep` | `internal` | internal; reachable only through Solidity callers | 3/3/3 |
| 1242 | `PerpEngine` | `_tryLiquidate` | `internal` | internal; reachable only through Solidity callers | 1/0/5 |
| 1261 | `PerpEngine` | `_deadPrep` | `private` | private; reachable only through Solidity callers | 0/0/3 |
| 1268 | `PerpEngine` | `_open` | `private` | private; reachable only through Solidity callers | 0/0/3 |
| 1273 | `PerpEngine` | `forceCloseDead` | `external` | anyone | 1/0/4 |
| 1286 | `PerpEngine` | `forceCloseAllDead` | `external` | anyone | 4/0/4 |
| 1311 | `PerpEngine` | `syncGeneration` | `external` | caller restricted by explicit msg.sender check | 5/19/10 |
| 1546 | `PerpEngine` | `isLiquidatable` | `external` | anyone | 0/0/4 |
| 1553 | `PerpEngine` | `_underwater` | `internal` | internal; reachable only through Solidity callers | 0/0/3 |
| 1599 | `PerpEngine` | `_liqTest` | `internal` | internal; reachable only through Solidity callers | 0/0/8 |
| 1656 | `PerpEngine` | `_insolventVal` | `internal` | internal; reachable only through Solidity callers | 0/0/2 |
| 1682 | `PerpEngine` | `_throttle` | `internal` | internal; reachable only through Solidity callers | 2/2/3 |
| 1695 | `PerpEngine` | `_underwaterVal` | `internal` | internal; reachable only through Solidity callers | 2/0/2 |
| 1709 | `PerpEngine` | `_ownerFloor` | `private` | private; reachable only through Solidity callers | 0/0/1 |
| 1713 | `PerpEngine` | `_settle` | `internal` | internal; reachable only through Solidity callers | 8/7/21 |
| 1914 | `PerpEngine` | `_run` | `internal` | internal; reachable only through Solidity callers | 2/0/4 |
| 1923 | `PerpEngine` | `_swapExactIn` | `internal` | internal; reachable only through Solidity callers | 0/0/1 |
| 1953 | `PerpEngine` | `_buyUpTo` | `internal` | internal; reachable only through Solidity callers | 2/0/4 |
| 1966 | `PerpEngine` | `unlockCallback` | `external` | caller restricted by explicit msg.sender check | 1/0/3 |
| 1975 | `PerpEngine` | `_swapBody` | `internal` | internal; reachable only through Solidity callers | 3/0/4 |
| 2005 | `PerpEngine` | `_openPrologue` | `internal` | internal; reachable only through Solidity callers | 0/0/4 |
| 2012 | `PerpEngine` | `_guardOpen` | `internal` | internal; reachable only through Solidity callers | 4/0/4 |
| 2069 | `PerpEngine` | `_isDead` | `internal` | internal; reachable only through Solidity callers | 3/0/8 |
| 2086 | `PerpEngine` | `_takeFee` | `internal` | internal; reachable only through Solidity callers | 4/0/4 |
| 2092 | `PerpEngine` | `_checkNotional` | `internal` | internal; reachable only through Solidity callers | 2/0/2 |
| 2095 | `PerpEngine` | `_book` | `internal` | internal; reachable only through Solidity callers | 3/1/1 |
| 2112 | `PerpEngine` | `_addOpen` | `internal` | internal; reachable only through Solidity callers | 0/4/1 |
| 2132 | `PerpEngine` | `_rebook` | `internal` | internal; reachable only through Solidity callers | 0/0/2 |
| 2147 | `PerpEngine` | `_insuranceNeed` | `internal` | internal; reachable only through Solidity callers | 5/0/4 |
| 2153 | `PerpEngine` | `_utilGate` | `private` | private; reachable only through Solidity callers | 3/1/2 |
| 2185 | `PerpEngine` | `_removeOpen` | `internal` | internal; reachable only through Solidity callers | 0/2/1 |
| 2195 | `PerpEngine` | `_ethToToken` | `internal` | internal; reachable only through Solidity callers | 0/0/4 |
| 2199 | `PerpEngine` | `_routeFee` | `internal` | internal; reachable only through Solidity callers | 7/4/3 |
| 2228 | `PerpEngine` | `_sendEth` | `internal` | internal; reachable only through Solidity callers | 0/0/2 |
| 2240 | `PerpEngine` | `_payOut` | `internal` | internal; reachable only through Solidity callers | 0/2/2 |
| 2262 | `PerpEngine` | `_tryPush` | `private` | private; reachable only through Solidity callers | 2/0/6 |
| 2322 | `PerpEngine` | `retirePayout` | `external` | anyone | 0/3/5 |
| 2357 | `PerpEngine` | `claimPayout` | `external` | anyone | 0/2/3 |
| 2369 | `PerpEngine` | `_bd` | `private` | private; reachable only through Solidity callers | 0/0/1 |
| 2379 | `PerpEngine` | `_writeOffTok` | `private` | private; reachable only through Solidity callers | 0/2/1 |
| 2385 | `PerpEngine` | `_vf` | `private` | private; reachable only through Solidity callers | 0/0/1 |
| 2386 | `PerpEngine` | `_vw` | `private` | private; reachable only through Solidity callers | 0/0/1 |
| 2390 | `PerpEngine` | `_replenishPlv` | `internal` | internal; reachable only through Solidity callers | 0/2/2 |
| 2399 | `PerpEngine` | `_absorbPlvLoss` | `internal` | internal; reachable only through Solidity callers | 0/2/2 |
| 2451 | `PerpEngine` | `_killStats` | `internal` | internal; reachable only through Solidity callers | 0/0/1 |
| 2472 | `PerpEngine` | `_awardBadge` | `internal` | internal; reachable only through Solidity callers | 0/1/3 |
| 2494 | `PerpEngine` | `claimLiquidatorBadges` | `external` | anyone | 0/1/2 |
| 2507 | `PerpEngine` | `_safeTransfer` | `private` | private; reachable only through Solidity callers | 0/0/2 |
| 2520 | `PerpEngine` | `fundPlv` | `external` | owner via onlyOwner | 0/1/2 |
| 2528 | `PerpEngine` | `fundPlvToken` | `external` | owner via onlyOwner | 0/0/2 |
| 2533 | `PerpEngine` | `_pullTokenIn` | `private` | private; reachable only through Solidity callers | 0/1/2 |
| 2539 | `PerpEngine` | `fundInsurance` | `external` | anyone | 0/1/2 |
| 2549 | `PerpEngine` | `creditPerpFee` | `external` | anyone | 0/0/2 |
| 2554 | `PerpEngine` | `creditPerpFeeToken` | `external` | anyone | 0/0/2 |
| 2575 | `PerpEngine` | `creditPerpFeeAsset` | `external` | caller restricted by explicit msg.sender check | 2/0/2 |
| 2585 | `PerpEngine` | `_pullIntoPlv` | `private` | private; reachable only through Solidity callers | 0/1/3 |
| 2591 | `PerpEngine` | `_creditPerp` | `private` | private; reachable only through Solidity callers | 1/3/3 |
| 2624 | `PerpEngine` | `fundFromVault` | `external` | configured vault via onlyVault | 0/0/2 |
| 2630 | `PerpEngine` | `withdrawPlvTo` | `external` | configured vault via onlyVault | 0/1/2 |
| 2637 | `PerpEngine` | `_vaultPaid` | `private` | private; reachable only through Solidity callers | 0/0/3 |
| 2642 | `PerpEngine` | `withdrawTokYieldTo` | `external` | configured vault via onlyVault | 0/1/2 |
| 2647 | `PerpEngine` | `fundTokenFromVault` | `external` | configured vault via onlyVault | 0/0/2 |
| 2652 | `PerpEngine` | `withdrawPlvTokenTo` | `external` | configured vault via onlyVault | 0/1/4 |
| 2659 | `PerpEngine` | `setFees` | `external` | owner via onlyOwner | 1/5/1 |
| 2663 | `PerpEngine` | `setRisk` | `external` | owner via onlyOwner | 2/6/1 |
| 2700 | `PerpEngine` | `setTiers` | `external` | owner via onlyOwner | 0/1/1 |
| 2722 | `PerpEngine` | `setRouting` | `external` | owner via onlyOwner | 0/4/0 |
| 2741 | `PerpEngine` | `setVaultSplit` | `external` | owner via onlyOwner | 1/2/1 |
| 2746 | `PerpEngine` | `setGuards` | `external` | owner via onlyOwner | 2/3/1 |
| 2780 | `PerpEngine` | `setVault` | `external` | owner via onlyOwner | 0/1/1 |
| 2786 | `PerpEngine` | `setVaultLimits` | `external` | owner via onlyOwner | 1/2/1 |
| 2791 | `PerpEngine` | `setMinCollateral` | `external` | owner via onlyOwner | 0/1/1 |
| 2807 | `PerpEngine` | `skimInsurance` | `external` | owner via onlyOwner | 0/1/3 |
| 2823 | `PerpEngine` | `positionHealth` | `external` | anyone | 0/0/3 |
| 2834 | `PerpEngine` | `receive` | `receive` | anyone | 0/0/0 |

## `cauldron/PerpMarkSource.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 99 | `PerpMarkSource` | `renounceOwnership` | `public` | anyone | 0/0/1 |
| 108 | `PerpMarkSource` | `constructor` | `constructor` | deployer (constructor executes once) | 1/1/0 |
| 115 | `PerpMarkSource` | `setPrimary` | `external` | owner via onlyOwner | 0/3/1 |
| 126 | `PerpMarkSource` | `addPool` | `external` | owner via onlyOwner | 3/1/1 |
| 147 | `PerpMarkSource` | `removePool` | `external` | owner via onlyOwner | 0/1/1 |
| 161 | `PerpMarkSource` | `poolCount` | `external` | anyone | 1/0/2 |
| 173 | `PerpMarkSource` | `weightedTick` | `external` | anyone | 4/0/2 |

## `cauldron/PerpStakerOracle.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 8 | `IPerpShares (declared in PerpStakerOracle.sol)` | `ethShareOf` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 9 | `IPerpShares (declared in PerpStakerOracle.sol)` | `tokShareOf` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 24 | `PerpStakerOracle` | `constructor` | `constructor` | deployer (constructor executes once) | 0/1/0 |
| 29 | `PerpStakerOracle` | `isInstant` | `external` | anyone | 1/0/4 |

## `cauldron/PerpSwapLib.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 71 | `PerpSwapLib` | `unitOf` | `external` | anyone | 0/0/3 |
| 75 | `PerpSwapLib` | `_unitOf` | `private` | private; reachable only through Solidity callers | 0/0/4 |
| 108 | `PerpSwapLib` | `quoteFactor` | `external` | anyone | 0/0/6 |
| 123 | `PerpSwapLib` | `_usdPerRawUnit` | `private` | private; reachable only through Solidity callers | 0/0/4 |
| 175 | `PerpSwapLib` | `projectedSqrtPriceX96` | `external` | anyone | 1/0/3 |
| 282 | `PerpSwapLib` | `twapTick` | `external` | anyone | 3/0/1 |
| 338 | `PerpSwapLib` | `writeObs` | `external` | anyone | 1/0/0 |
| 367 | `PerpSwapLib` | `sqrtPriceAtTick` | `external` | anyone | 0/0/2 |
| 385 | `PerpSwapLib` | `tryMintBadge` | `external` | anyone | 0/0/4 |
| 406 | `PerpSwapLib` | `quoteAt` | `external` | anyone | 1/0/3 |
| 411 | `PerpSwapLib` | `ethToToken` | `external` | anyone | 1/0/3 |
| 417 | `PerpSwapLib` | `ethDepth` | `external` | anyone | 2/0/4 |
| 438 | `PerpSwapLib` | `tryTransferFrom` | `external` | anyone | 0/0/3 |
| 446 | `PerpSwapLib` | `tryTransfer` | `external` | anyone | 0/0/3 |
| 480 | `PerpSwapLib` | `swapLeg` | `external` | anyone | 2/0/6 |
| 537 | `PerpSwapLib` | `_settle` | `private` | private; reachable only through Solidity callers | 0/0/4 |
| 575 | `PerpSwapLib` | `migrateInventory` | `external` | anyone | 0/0/2 |
| 624 | `PerpSwapLib` | `spendLimit` | `external` | anyone | 0/0/1 |
| 670 | `PerpSwapLib` | `bandLimit` | `external` | anyone | 0/0/1 |
| 692 | `PerpSwapLib` | `closeLimit` | `external` | anyone | 0/0/1 |
| 701 | `PerpSwapLib` | `_band` | `private` | private; reachable only through Solidity callers | 2/0/2 |
| 714 | `PerpSwapLib` | `_spend` | `private` | private; reachable only through Solidity callers | 3/0/3 |

## `cauldron/PerpVault.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 9 | `IPerpEngineVault (declared in PerpVault.sol)` | `fundFromVault` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 10 | `IPerpEngineVault (declared in PerpVault.sol)` | `quote` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 11 | `IPerpEngineVault (declared in PerpVault.sol)` | `withdrawPlvTo` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 12 | `IPerpEngineVault (declared in PerpVault.sol)` | `fundTokenFromVault` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 13 | `IPerpEngineVault (declared in PerpVault.sol)` | `withdrawPlvTokenTo` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 14 | `IPerpEngineVault (declared in PerpVault.sol)` | `totalEth` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 15 | `IPerpEngineVault (declared in PerpVault.sol)` | `freeEth` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 16 | `IPerpEngineVault (declared in PerpVault.sol)` | `totalTokenAssets` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 17 | `IPerpEngineVault (declared in PerpVault.sol)` | `freeToken` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 19 | `IPerpEngineVault (declared in PerpVault.sol)` | `tokYieldCumulative` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 22 | `IPerpEngineVault (declared in PerpVault.sol)` | `tokYieldEth` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 23 | `IPerpEngineVault (declared in PerpVault.sol)` | `withdrawTokYieldTo` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 27 | `IVaultRegistry (declared in PerpVault.sol)` | `currentToken` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 210 | `PerpVault` | `constructor` | `constructor` | deployer (constructor executes once) | 1/2/0 |
| 236 | `PerpVault` | `hasStakers` | `external` | anyone | 2/0/2 |
| 259 | `PerpVault` | `hasQuoteStake` | `external` | anyone | 1/0/2 |
| 265 | `PerpVault` | `assetsEth` | `public` | anyone | 2/0/4 |
| 271 | `PerpVault` | `assetsTok` | `public` | anyone | 2/0/4 |
| 292 | `PerpVault` | `deposit` | `public` | anyone | 3/2/10 |
| 333 | `PerpVault` | `depositEth` | `external` | anyone | 0/0/3 |
| 337 | `PerpVault` | `_engineQuote` | `private` | private; reachable only through Solidity callers | 1/0/3 |
| 347 | `PerpVault` | `_pull` | `private` | private; reachable only through Solidity callers | 0/0/3 |
| 354 | `PerpVault` | `_approve` | `private` | private; reachable only through Solidity callers | 0/0/3 |
| 361 | `PerpVault` | `withdrawEth` | `external` | anyone | 2/2/7 |
| 398 | `PerpVault` | `_haircut` | `private` | private; reachable only through Solidity callers | 0/0/1 |
| 410 | `PerpVault` | `pendingEth` | `public` | anyone | 2/0/3 |
| 414 | `PerpVault` | `pendingEthOf` | `public` | anyone | 2/0/3 |
| 420 | `PerpVault` | `_queueEth` | `private` | private; reachable only through Solidity callers | 1/0/2 |
| 429 | `PerpVault` | `_dropEthUnits` | `private` | private; reachable only through Solidity callers | 0/0/1 |
| 455 | `PerpVault` | `_syncEthQueue` | `private` | private; reachable only through Solidity callers | 2/0/4 |
| 493 | `PerpVault` | `settlePendingEth` | `external` | anyone | 1/0/5 |
| 505 | `PerpVault` | `claimPendingEth` | `external` | caller restricted by explicit msg.sender check | 3/0/10 |
| 547 | `PerpVault` | `_syncTokYield` | `internal` | internal; reachable only through Solidity callers | 3/2/6 |
| 599 | `PerpVault` | `_settleTok` | `internal` | internal; reachable only through Solidity callers | 3/2/3 |
| 615 | `PerpVault` | `_resetTokDebt` | `internal` | internal; reachable only through Solidity callers | 3/1/2 |
| 623 | `PerpVault` | `depositToken` | `external` | anyone | 4/2/13 |
| 651 | `PerpVault` | `claimTokYield` | `external` | anyone | 1/1/6 |
| 663 | `PerpVault` | `withdrawToken` | `external` | anyone | 2/2/10 |
| 683 | `PerpVault` | `pendingTok` | `public` | anyone | 2/0/3 |
| 687 | `PerpVault` | `pendingTokOf` | `public` | anyone | 2/0/3 |
| 693 | `PerpVault` | `_queueTok` | `private` | private; reachable only through Solidity callers | 1/0/2 |
| 701 | `PerpVault` | `_dropTokUnits` | `private` | private; reachable only through Solidity callers | 0/0/1 |
| 710 | `PerpVault` | `_syncTokQueue` | `private` | private; reachable only through Solidity callers | 2/0/4 |
| 730 | `PerpVault` | `settlePendingToken` | `external` | anyone | 1/0/5 |
| 745 | `PerpVault` | `claimPendingToken` | `external` | caller restricted by explicit msg.sender check | 3/0/10 |
| 770 | `PerpVault` | `ethPosition` | `external` | anyone | 5/0/6 |
| 778 | `PerpVault` | `tokenPosition` | `external` | anyone | 5/0/6 |
| 787 | `PerpVault` | `pendingTokYield` | `external` | anyone | 8/0/9 |

## Interpretation limits

- `reads` and `writes` enumerate direct references visible in the node body. Modifier and transitive callee effects remain on their own nodes.
- Interface declarations describe the caller-side assumption; their implementation authority and effects live in the implementing cluster.
- Public state-variable getters are compiler method identifiers and remain outside the declaration-node skeleton; the validator reports them separately.
- Test/assertion links are not fields in the legacy graph schema and remain a separate full-scope coverage task.
