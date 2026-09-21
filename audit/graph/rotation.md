# `rotation` function graph — current-tree semantic refresh

Status: DERIVED static graph annotations. Solidity was not modified and no exploit claim is made here.

- Current skeleton: **93 nodes** across **7 files**.
- Reused after source-line remap: **0** unchanged bodies.
- Re-read and regenerated from current bodies: **87 changed**, **6 added**.
- Removed obsolete nodes: **0**.

- Carried nodes regenerated after current-line citation checks: **0**.

Each row is keyed by the immutable skeleton. `R/W/E` is the count of direct storage reads, writes, and resolved call edges recorded in the machine graph; it is not transitive coverage.

## `cauldron/CauldronVault.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 7 | `IBurnableCollection (declared in CauldronVault.sol)` | `ownerOf` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 8 | `IBurnableCollection (declared in CauldronVault.sol)` | `totalMinted` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 9 | `IBurnableCollection (declared in CauldronVault.sol)` | `burnFromVault` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 14 | `IBurnableCollection (declared in CauldronVault.sol)` | `minter` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 60 | `CauldronVault` | `outstanding` | `public` | anyone | 3/0/3 |
| 106 | `CauldronVault` | `constructor` | `constructor` | deployer (constructor executes once) | 0/3/0 |
| 117 | `CauldronVault` | `receive` | `receive` | caller restricted by explicit msg.sender check | 1/0/1 |
| 130 | `CauldronVault` | `_minter` | `private` | private; reachable only through Solidity callers | 1/0/2 |
| 138 | `CauldronVault` | `floorPerNFT` | `public` | anyone | 0/0/3 |
| 155 | `CauldronVault` | `redeem` | `external` | caller restricted by explicit msg.sender check | 3/1/6 |
| 184 | `CauldronVault` | `close` | `external` | caller restricted by explicit msg.sender check | 1/1/3 |

## `cauldron/MockAggregator.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 54 | `MockAggregator` | `constructor` | `constructor` | deployer (constructor executes once) | 0/3/0 |
| 60 | `MockAggregator` | `onlyOwner` | `modifier` | internal; reachable only through Solidity callers | 1/0/1 |
| 65 | `MockAggregator` | `transferOwnership` | `external` | owner via onlyOwner | 0/1/1 |
| 68 | `MockAggregator` | `peg` | `external` | owner via onlyOwner | 0/2/1 |
| 76 | `MockAggregator` | `setStale` | `external` | owner via onlyOwner | 0/1/1 |
| 82 | `MockAggregator` | `setDown` | `external` | owner via onlyOwner | 0/1/1 |
| 84 | `MockAggregator` | `latestRoundData` | `external` | anyone | 4/0/0 |

## `cauldron/MockQuoteToken.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 20 | `MockQuoteToken` | `constructor` | `constructor` | deployer (constructor executes once) | 0/1/0 |
| 24 | `MockQuoteToken` | `decimals` | `public` | anyone | 1/0/2 |
| 27 | `MockQuoteToken` | `mint` | `external` | anyone | 0/0/2 |

## `cauldron/NativeQuoteZap.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 80 | `NativeQuoteZap` | `constructor` | `constructor` | deployer (constructor executes once) | 0/1/0 |
| 101 | `NativeQuoteZap` | `zap` | `external` | anyone | 1/0/4 |
| 123 | `NativeQuoteZap` | `unlockCallback` | `external` | caller restricted by explicit msg.sender check | 1/0/7 |

## `cauldron/QuoteOracle.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 5 | `IAggregatorV3 (declared in QuoteOracle.sol)` | `decimals` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 6 | `IAggregatorV3 (declared in QuoteOracle.sol)` | `latestRoundData` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 13 | `IERC20Decimals (declared in QuoteOracle.sol)` | `decimals` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 110 | `QuoteOracle` | `constructor` | `constructor` | deployer (constructor executes once) | 0/1/0 |
| 114 | `QuoteOracle` | `onlyOwner` | `modifier` | internal; reachable only through Solidity callers | 1/0/1 |
| 119 | `QuoteOracle` | `transferOwnership` | `external` | owner via onlyOwner | 0/1/1 |
| 131 | `QuoteOracle` | `setFeed` | `external` | owner via onlyOwner | 0/1/0 |
| 153 | `QuoteOracle` | `setPegged` | `external` | owner via onlyOwner | 0/1/1 |
| 175 | `QuoteOracle` | `setBounds` | `external` | owner via onlyOwner | 1/0/1 |
| 182 | `QuoteOracle` | `setSequencer` | `external` | owner via onlyOwner | 0/2/1 |
| 202 | `QuoteOracle` | `usdPerRawUnit` | `external` | anyone | 1/0/7 |
| 334 | `QuoteOracle` | `cachedUsdPerRawUnit` | `external` | anyone | 2/0/3 |
| 346 | `QuoteOracle` | `priceable` | `external` | anyone | 0/0/3 |
| 350 | `QuoteOracle` | `_sequencerOk` | `internal` | internal; reachable only through Solidity callers | 2/0/4 |

## `cauldron/QuoteRotator.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 99 | `QuoteRotator` | `constructor` | `constructor` | deployer (constructor executes once) | 0/3/0 |
| 125 | `QuoteRotator` | `onlyRegistry` | `modifier` | internal; reachable only through Solidity callers | 1/0/1 |
| 130 | `QuoteRotator` | `onlyOwner` | `modifier` | internal; reachable only through Solidity callers | 1/0/1 |
| 135 | `QuoteRotator` | `transferOwnership` | `external` | owner via onlyOwner | 0/1/1 |
| 190 | `QuoteRotator` | `setVenue` | `external` | owner via onlyOwner | 0/1/1 |
| 197 | `QuoteRotator` | `isVenueAllowed` | `external` | anyone | 1/0/2 |
| 216 | `QuoteRotator` | `setPlan` | `external` | owner via onlyOwner | 0/1/1 |
| 248 | `QuoteRotator` | `cancelPlan` | `external` | owner via onlyOwner | 0/1/1 |
| 253 | `QuoteRotator` | `setKeeperBps` | `external` | owner via onlyOwner | 0/1/1 |
| 263 | `QuoteRotator` | `nextSliceSize` | `public` | anyone | 1/0/3 |
| 284 | `QuoteRotator` | `rotateStep` | `external` | anyone | 5/0/7 |
| 335 | `QuoteRotator` | `swapOnce` | `external` | anyone | 2/0/5 |
| 405 | `QuoteRotator` | `setRotationSlipBps` | `external` | owner via onlyOwner | 0/1/1 |
| 425 | `QuoteRotator` | `_oracleFloor` | `internal` | internal; reachable only through Solidity callers | 2/0/2 |
| 485 | `QuoteRotator` | `setArbParams` | `external` | owner via onlyOwner | 1/3/1 |
| 495 | `QuoteRotator` | `setMaxArbNotionalUsd` | `external` | owner via onlyOwner | 0/1/1 |
| 533 | `QuoteRotator` | `arbStep` | `external` | anyone | 6/2/6 |
| 622 | `QuoteRotator` | `_usdLive` | `internal` | internal; reachable only through Solidity callers | 1/0/4 |
| 653 | `QuoteRotator` | `withdraw` | `external` | caller restricted by explicit msg.sender check | 2/0/2 |
| 664 | `QuoteRotator` | `_swap` | `internal` | internal; reachable only through Solidity callers | 1/0/1 |
| 673 | `QuoteRotator` | `unlockCallback` | `external` | caller restricted by explicit msg.sender check | 1/0/6 |
| 705 | `QuoteRotator` | `_arbCallback` | `internal` | internal; reachable only through Solidity callers | 1/0/6 |
| 732 | `QuoteRotator` | `_settle` | `internal` | internal; reachable only through Solidity callers | 1/0/5 |
| 742 | `QuoteRotator` | `_send` | `internal` | internal; reachable only through Solidity callers | 0/0/3 |
| 755 | `QuoteRotator` | `_safeTransfer` | `internal` | internal; reachable only through Solidity callers | 0/0/2 |
| 768 | `QuoteRotator` | `_routeMatches` | `internal` | internal; reachable only through Solidity callers | 0/0/0 |
| 778 | `QuoteRotator` | `_balanceOf` | `internal` | internal; reachable only through Solidity callers | 0/0/2 |
| 782 | `QuoteRotator` | `_allowed` | `internal` | internal; reachable only through Solidity callers | 1/0/4 |
| 789 | `QuoteRotator` | `receive` | `receive` | anyone | 0/0/0 |

## `cauldron/RedemptionExt.sol`

| line | contract | node | visibility | authority | R/W/E |
|---:|---|---|---|---|---:|
| 45 | `ITreasuryGovernor (declared in RedemptionExt.sol)` | `allowance` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 46 | `ITreasuryGovernor (declared in RedemptionExt.sol)` | `consume` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 49 | `ITreasuryGovernor (declared in RedemptionExt.sol)` | `migrationMandateSpent` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 53 | `IQuoteRotator (declared in RedemptionExt.sol)` | `swapOnce` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 55 | `IQuoteRotator (declared in RedemptionExt.sol)` | `withdraw` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 59 | `IHookVolume (declared in RedemptionExt.sol)` | `linkVolume` | `external` | declaration only; implementation authority is outside this node | 0/0/0 |
| 78 | `RedemptionExt` | `redeemOgFren` | `external` | caller restricted by explicit msg.sender check | 9/1/5 |
| 115 | `RedemptionExt` | `buyTreasuryOgFren` | `external` | anyone | 4/0/4 |
| 136 | `RedemptionExt` | `donateToReserve` | `external` | anyone | 1/0/2 |
| 147 | `RedemptionExt` | `materializeLegacyReserve` | `external` | anyone | 13/1/3 |
| 165 | `RedemptionExt` | `_pullGrow` | `private` | private; reachable only through Solidity callers | 7/1/4 |
| 260 | `RedemptionExt` | `setRotationWiring` | `external` | owner via onlyOwner | 0/3/1 |
| 269 | `RedemptionExt` | `rotateSlice` | `external` | anyone | 0/0/2 |
| 280 | `RedemptionExt` | `rotateSliceFrom` | `public` | anyone | 13/1/8 |
| 723 | `RedemptionExt` | `floorClaimableNow` | `external` | anyone | 5/0/3 |
| 742 | `RedemptionExt` | `claimByBurnUpTo` | `external` | caller restricted by explicit msg.sender check | 9/0/2 |
| 766 | `RedemptionExt` | `legCount` | `external` | anyone | 1/0/2 |
| 771 | `RedemptionExt` | `legAt` | `external` | anyone | 1/0/0 |
| 786 | `RedemptionExt` | `_legPosition` | `private` | private; reachable only through Solidity callers | 1/0/0 |
| 799 | `RedemptionExt` | `_recordLeg` | `private` | private; reachable only through Solidity callers | 1/0/1 |
| 848 | `RedemptionExt` | `recoverLegs` | `public` | anyone | 1/0/4 |
| 875 | `RedemptionExt` | `_bookLegProceeds` | `internal` | internal; reachable only through Solidity callers | 2/1/1 |
| 899 | `RedemptionExt` | `recoverLegsAtTeardown` | `external` | anyone | 0/0/3 |
| 903 | `RedemptionExt` | `_recoverLegs` | `private` | private; reachable only through Solidity callers | 4/1/4 |
| 961 | `RedemptionExt` | `legProceedsOf` | `external` | anyone | 1/0/2 |
| 998 | `RedemptionExt` | `sweepLegProceeds` | `external` | owner via onlyOwner | 0/1/3 |

## Interpretation limits

- `reads` and `writes` enumerate direct references visible in the node body. Modifier and transitive callee effects remain on their own nodes.
- Interface declarations describe the caller-side assumption; their implementation authority and effects live in the implementing cluster.
- Public state-variable getters are compiler method identifiers and remain outside the declaration-node skeleton; the validator reports them separately.
- Test/assertion links are not fields in the legacy graph schema and remain a separate full-scope coverage task.
