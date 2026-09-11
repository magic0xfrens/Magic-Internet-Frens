# Cauldron function graph

Generated 2026-09-11 at commit `1e98bb4` (branch snapshot of the working tree) from the decontaminated source tree `/tmp/blind-final/contracts/solidity` (comment tags stripped; line numbers and body hashes identical to `contracts/solidity` by construction; see `audit/FINAL_BLIND_2026-09-11/DECONTAMINATION.md`).

Extraction only: no severity judgment, no exploit narrative. Every node comes from `skeleton.py`; every number below comes from `validate.py`, `join.py`, or `CROSSCHECK.md`.

## Schema

Skeleton fields (mechanical, never edited by hand): `contract`, `file`, `line`, `kind` (function | constructor | receive | fallback | modifier), `name`, `signature` (declaration text up to `{` or `;`), `visibility`, `mutability`, `modifiers[]`, `body_lines`, `body_sha1` (sha1 of the body with comments removed and whitespace collapsed; empty for `;` bodies). Interfaces declared inside another file are named `"IName (declared in File.sol)"`.

Semantic fields (filled by extractors, machine-checked by the validator):

| field | meaning | check |
|---|---|---|
| `authority` | who can reach it: anyone, a role, `internal (callers: …)`, deployer | non-empty |
| `authority_gate_quote` | the exact gating line as `<quote> (File.sol:N)` or `UNGATED` | substring of line N±1 |
| `reads[]`, `writes[]` | storage only, as `name (line N)` / `(line N, immutable)` / `(line N, constant)` | name in `forge inspect storageLayout` ∪ immutables ∪ constants; identifier on line N |
| `value` | `NONE` / receives native / sends native to X / ERC20 transfer of T to X, each with `(line N)` | identifier on line N |
| `edges[]` | `Callee.fn (File.sol:N), TRUSTED|UNTRUSTED, in-cluster|out-of-cluster|delegatecall|library` | `fn` declared in-repo or under lib/, `fn` on line N |
| `reachability` | prose: how a caller gets here, which gate, what state; every claim cites `` `id` File.sol:N `` or is tagged DERIVED | identifier on the cited line |
| `observations[]` | comment-vs-code mismatches only, both sides cited | identifiers on cited lines |

TRUSTED = the callee's code is in this repo or a pinned lib; UNTRUSTED = an address a user or admin can point anywhere.

## Cluster map

| cluster | files |
|---|---|
| hook | `CauldronHook.sol`, `vendor/BaseHook.sol`, `vendor/HookMiner.sol`, `cauldron/FeeRouteLib.sol`, `cauldron/DefaultFeeRouter.sol`, `cauldron/ReserveLib.sol`, `cauldron/RoyaltyRouter.sol`, `cauldron/LegacyBuyLib.sol` |
| registry | `CauldronRegistry.sol`, `CauldronToken.sol`, `cauldron/IPolicies.sol`, `cauldron/IDeathChecker.sol`, `cauldron/ILiquidatorMintable.sol`, `cauldron/ICauldron.sol` |
| pool | `cauldron/CauldronBase.sol`, `cauldron/PoolOps.sol` |
| perp | `cauldron/PerpEngine.sol`, `cauldron/PerpVault.sol`, `cauldron/PerpSwapLib.sol`, `cauldron/PerpMarkSource.sol`, `cauldron/PerpStakerOracle.sol` |
| rotation | `cauldron/QuoteRotator.sol`, `cauldron/QuoteOracle.sol`, `cauldron/RedemptionExt.sol`, `cauldron/CauldronVault.sol`, `cauldron/MockAggregator.sol`, `cauldron/MockQuoteToken.sol` |
| governance | `cauldron/CauldronGovernor.sol`, `cauldron/TreasuryGovernor.sol` |
| nft | `cauldron/MiFrensGenesis.sol`, `cauldron/CauldronCollection.sol`, `cauldron/CollectionLedger.sol`, `cauldron/CauldronGachaRouter.sol`, `cauldron/MiFrensDividend.sol`, `cauldron/MintCurvePolicy.sol`, `cauldron/CauldronFactory.sol`, `cauldron/ICreatorToken.sol`, `interfaces/INFTContract.sol` |
| seed | `cauldron/CauldronSeeder.sol`, `cauldron/SeedLib.sol`, `cauldron/ISeeder.sol`, `cauldron/MigrationVesting.sol`, `cauldron/LaunchSniper.sol` |

## How to re-run

```
cd contracts/solidity && export FOUNDRY_PROFILE=cauldron && forge build
python3 audit/graph/skeleton.py <src_root> audit/graph            # rebuild skeleton/<cluster>.json
python3 audit/graph/diff.py audit/graph/skeleton/<c>.json audit/graph/<c>.json   # ADDED / REMOVED / CHANGED / MOVED nodes
# re-extract only the CHANGED/ADDED nodes with a chunk file, then:
python3 audit/graph/merge.py audit/graph <c> <chunk.json>
python3 audit/graph/validate.py <src_root> audit/graph <c> [--partial]
python3 audit/graph/join.py audit/graph
python3 audit/graph/make_readme.py audit/graph <src_root> <validate_log_dir>
```

## Coverage per contract (from validate.py)

| cluster | contract | skeleton nodes | graph nodes | with reachability | with edges | DERIVED | validator |
|---|---|---|---|---|---|---|---|
| hook | IRegistryQuotes (declared in CauldronHook.sol) | 1 | 1 | 1 | 0 | 0 | |
| hook | IQuoteOracle (declared in CauldronHook.sol) | 1 | 1 | 1 | 0 | 0 | |
| hook | IPerpOpenCount (declared in CauldronHook.sol) | 1 | 1 | 1 | 0 | 0 | |
| hook | IPerpEngineLiq (declared in CauldronHook.sol) | 3 | 3 | 3 | 0 | 2 | |
| hook | ICollectionLiquidator (declared in CauldronHoo | 1 | 1 | 1 | 0 | 0 | |
| hook | ILegacyNote (declared in CauldronHook.sol) | 1 | 1 | 1 | 0 | 1 | |
| hook | IPerpForceClose (declared in CauldronHook.sol) | 2 | 2 | 2 | 0 | 0 | |
| hook | IPerpFeeCredit (declared in CauldronHook.sol) | 3 | 3 | 3 | 0 | 0 | |
| hook | ISeederInSwap (declared in CauldronHook.sol) | 1 | 1 | 1 | 0 | 0 | |
| hook | CauldronHook | 77 | 77 | 77 | 48 | 0 | |
| hook | DefaultFeeRouter | 1 | 1 | 1 | 0 | 0 | |
| hook | FeeRouteLib | 7 | 7 | 7 | 7 | 1 | |
| hook | LegacyBuyLib | 1 | 1 | 1 | 1 | 0 | |
| hook | ReserveLib | 5 | 5 | 5 | 1 | 4 | |
| hook | ILegacyBuffer (declared in RoyaltyRouter.sol) | 1 | 1 | 1 | 0 | 0 | |
| hook | RoyaltyRouter | 2 | 2 | 2 | 1 | 1 | |
| hook | BaseHook | 23 | 23 | 23 | 12 | 0 | |
| hook | HookMiner | 2 | 2 | 2 | 1 | 1 | |
| registry | CauldronRegistry | 68 | 68 | 68 | 41 | 31 | |
| registry | CauldronToken | 3 | 3 | 3 | 0 | 2 | |
| registry | ICollectionRenderer (declared in ICauldron.sol | 1 | 1 | 1 | 0 | 1 | |
| registry | LaunchLib (declared in ICauldron.sol) | 1 | 1 | 1 | 0 | 1 | |
| registry | ICauldronGovernor (declared in ICauldron.sol) | 3 | 3 | 3 | 0 | 1 | |
| registry | ICauldronCollection (declared in ICauldron.sol | 3 | 3 | 3 | 0 | 2 | |
| registry | IDeathChecker | 1 | 1 | 1 | 0 | 0 | |
| registry | ILiquidatorMintable | 3 | 3 | 3 | 0 | 1 | |
| registry | ISurtaxPolicy (declared in IPolicies.sol) | 1 | 1 | 1 | 0 | 1 | |
| registry | IOddsPolicy (declared in IPolicies.sol) | 1 | 1 | 1 | 0 | 1 | |
| registry | ICurvePolicy (declared in IPolicies.sol) | 1 | 1 | 1 | 0 | 0 | |
| registry | IFeeRouter (declared in IPolicies.sol) | 1 | 1 | 1 | 0 | 0 | |
| pool | ICauldronFactory (declared in CauldronBase.sol | 2 | 2 | 2 | 0 | 0 | |
| pool | IMiFrensContinuable (declared in CauldronBase. | 5 | 5 | 5 | 0 | 2 | |
| pool | IVaultClose (declared in CauldronBase.sol) | 1 | 1 | 1 | 0 | 1 | |
| pool | IPerpSync (declared in CauldronBase.sol) | 2 | 2 | 2 | 0 | 1 | |
| pool | ICollectionLedger (declared in CauldronBase.so | 1 | 1 | 1 | 0 | 0 | |
| pool | IPositionManager (declared in CauldronBase.sol | 3 | 3 | 3 | 0 | 3 | |
| pool | CauldronBase | 4 | 4 | 4 | 0 | 0 | |
| pool | IPositionManagerOps (declared in PoolOps.sol) | 3 | 3 | 3 | 0 | 1 | |
| pool | ILedgerOps (declared in PoolOps.sol) | 7 | 7 | 7 | 0 | 1 | |
| pool | IColMinted (declared in PoolOps.sol) | 1 | 1 | 1 | 0 | 0 | |
| pool | IVaultRedeemedOps (declared in PoolOps.sol) | 2 | 2 | 2 | 0 | 1 | |
| pool | IHookReserves (declared in PoolOps.sol) | 2 | 2 | 2 | 0 | 0 | |
| pool | IVaultCloseOps (declared in PoolOps.sol) | 1 | 1 | 1 | 0 | 0 | |
| pool | ICollectionOps (declared in PoolOps.sol) | 2 | 2 | 2 | 0 | 0 | |
| pool | ILegacyHookOps (declared in PoolOps.sol) | 2 | 2 | 2 | 0 | 0 | |
| pool | ICauldronBurn (declared in PoolOps.sol) | 1 | 1 | 1 | 0 | 0 | |
| pool | IAutoFlag (declared in PoolOps.sol) | 1 | 1 | 1 | 0 | 0 | |
| pool | IPermit2Ops (declared in PoolOps.sol) | 1 | 1 | 1 | 0 | 0 | |
| pool | PoolOps | 30 | 30 | 30 | 28 | 3 | |
| perp | IPerpRegistry (declared in PerpEngine.sol) | 8 | 8 | 8 | 0 | 4 | |
| perp | IMarkSource (declared in PerpEngine.sol) | 1 | 1 | 1 | 0 | 0 | |
| perp | IPerpVaultStake (declared in PerpEngine.sol) | 1 | 1 | 1 | 0 | 1 | |
| perp | IPerpHook (declared in PerpEngine.sol) | 2 | 2 | 2 | 0 | 1 | |
| perp | PerpEngine | 87 | 87 | 87 | 62 | 33 | |
| perp | PerpMarkSource | 6 | 6 | 6 | 0 | 4 | |
| perp | IPerpShares (declared in PerpStakerOracle.sol) | 2 | 2 | 2 | 0 | 1 | |
| perp | PerpStakerOracle | 2 | 2 | 2 | 1 | 2 | |
| perp | PerpSwapLib | 3 | 3 | 3 | 3 | 0 | |
| perp | IPerpEngineVault (declared in PerpVault.sol) | 11 | 11 | 11 | 0 | 1 | |
| perp | IVaultRegistry (declared in PerpVault.sol) | 1 | 1 | 1 | 0 | 1 | |
| perp | PerpVault | 22 | 22 | 22 | 17 | 7 | |
| rotation | IBurnableCollection (declared in CauldronVault | 3 | 3 | 3 | 0 | 3 | |
| rotation | CauldronVault | 6 | 6 | 6 | 4 | 0 | |
| rotation | MockAggregator | 7 | 7 | 7 | 0 | 0 | |
| rotation | MockQuoteToken | 3 | 3 | 3 | 1 | 0 | |
| rotation | IAggregatorV3 (declared in QuoteOracle.sol) | 2 | 2 | 2 | 0 | 0 | |
| rotation | IERC20Decimals (declared in QuoteOracle.sol) | 1 | 1 | 1 | 0 | 0 | |
| rotation | QuoteOracle | 11 | 11 | 11 | 6 | 1 | |
| rotation | QuoteRotator | 29 | 29 | 29 | 18 | 0 | |
| rotation | ITreasuryGovernor (declared in RedemptionExt.s | 3 | 3 | 3 | 0 | 0 | |
| rotation | IQuoteRotator (declared in RedemptionExt.sol) | 2 | 2 | 2 | 0 | 0 | |
| rotation | IHookVolume (declared in RedemptionExt.sol) | 1 | 1 | 1 | 0 | 0 | |
| rotation | RedemptionExt | 16 | 16 | 16 | 11 | 2 | |
| governance | IRegistryQuotes (declared in CauldronGovernor. | 1 | 1 | 1 | 0 | 0 | |
| governance | CauldronGovernor | 11 | 11 | 11 | 7 | 3 | |
| governance | IVotes721 (declared in TreasuryGovernor.sol) | 3 | 3 | 3 | 0 | 2 | |
| governance | IRegistryQuotes (declared in TreasuryGovernor. | 1 | 1 | 1 | 0 | 0 | |
| governance | IQuotePrice (declared in TreasuryGovernor.sol) | 1 | 1 | 1 | 0 | 1 | |
| governance | TreasuryGovernor | 18 | 18 | 18 | 9 | 18 | |
| nft | CauldronCollection | 26 | 26 | 26 | 8 | 1 | |
| nft | CauldronFactory | 4 | 4 | 4 | 1 | 2 | |
| nft | ICauldronHookGacha (declared in CauldronGachaR | 5 | 5 | 5 | 0 | 0 | |
| nft | IRegistryCurrent (declared in CauldronGachaRou | 3 | 3 | 3 | 0 | 0 | |
| nft | IQuoteOracleView (declared in CauldronGachaRou | 1 | 1 | 1 | 0 | 0 | |
| nft | CauldronGachaRouter | 23 | 23 | 23 | 18 | 7 | |
| nft | CollectionLedger | 8 | 8 | 8 | 3 | 3 | |
| nft | ITransferValidator (declared in ICreatorToken. | 1 | 1 | 1 | 0 | 0 | |
| nft | ICreatorToken | 3 | 3 | 3 | 0 | 0 | |
| nft | IMiFrensShares (declared in MiFrensDividend.so | 4 | 4 | 4 | 0 | 0 | |
| nft | IReserveRegistry (declared in MiFrensDividend. | 3 | 3 | 3 | 0 | 1 | |
| nft | MiFrensDividend | 22 | 22 | 22 | 18 | 4 | |
| nft | IRegistrySummon (declared in MiFrensGenesis.so | 2 | 2 | 2 | 0 | 1 | |
| nft | IMiFrensDividendHook (declared in MiFrensGenes | 1 | 1 | 1 | 0 | 0 | |
| nft | MiFrensGenesis | 42 | 42 | 42 | 13 | 8 | |
| nft | MintCurvePolicy | 3 | 3 | 3 | 0 | 0 | |
| nft | INFTContract | 2 | 2 | 2 | 0 | 2 | |
| seed | IRegistryOwner (declared in CauldronSeeder.sol | 1 | 1 | 1 | 0 | 1 | |
| seed | CauldronSeeder | 23 | 23 | 23 | 14 | 7 | |
| seed | ISeeder | 6 | 6 | 6 | 0 | 1 | |
| seed | IMiFrensGenesisFinalize (declared in LaunchSni | 2 | 2 | 2 | 0 | 0 | |
| seed | IRegistryCurrent (declared in LaunchSniper.sol | 1 | 1 | 1 | 0 | 1 | |
| seed | IGachaPlay (declared in LaunchSniper.sol) | 1 | 1 | 1 | 0 | 1 | |
| seed | LaunchSniper | 4 | 4 | 4 | 2 | 1 | |
| seed | IVestingRegistry (declared in MigrationVesting | 3 | 3 | 3 | 0 | 2 | |
| seed | IStakerOracle (declared in MigrationVesting.so | 1 | 1 | 1 | 0 | 1 | |
| seed | MigrationVesting | 15 | 15 | 15 | 9 | 1 | |
| seed | SeedLib | 7 | 7 | 7 | 3 | 5 | |

| cluster | validator result |
|---|---|
| hook | `COVERAGE hook: 133/133 nodes, 0 failures` |
| registry | `COVERAGE registry: 87/87 nodes, 0 failures` |
| pool | `COVERAGE pool: 71/71 nodes, 0 failures` |
| perp | `COVERAGE perp: 146/146 nodes, 0 failures` |
| rotation | `COVERAGE rotation: 84/84 nodes, 0 failures` |
| governance | `COVERAGE governance: 35/35 nodes, 0 failures` |
| nft | `COVERAGE nft: 153/153 nodes, 0 failures` |
| seed | `COVERAGE seed: 64/64 nodes, 0 failures` |

## Per-cluster totals (from the graph JSON)

| cluster | nodes | external/public | authority = anyone | UNGATED | edges | UNTRUSTED edges | DERIVED tags | observations |
|---|---|---|---|---|---|---|---|---|
| hook | 133 | 87 | 21 | 81 | 130 | 47 | 10 | 15 |
| registry | 87 | 68 | 31 | 35 | 108 | 4 | 41 | 15 |
| pool | 71 | 61 | 45 | 39 | 119 | 20 | 13 | 6 |
| perp | 146 | 93 | 65 | 107 | 196 | 13 | 55 | 7 |
| rotation | 84 | 60 | 38 | 53 | 96 | 15 | 6 | 14 |
| governance | 35 | 26 | 16 | 25 | 25 | 3 | 24 | 10 |
| nft | 153 | 116 | 42 | 85 | 121 | 33 | 29 | 10 |
| seed | 64 | 38 | 25 | 41 | 96 | 24 | 21 | 12 |

Total nodes: 773.

## Cross-cluster edge join (from join.py)

| cluster | edges | in-cluster | out-of-cluster | resolved to node | resolved to lib/low-level | unresolved | malformed |
|---|---|---|---|---|---|---|---|
| hook | 130 | 54 | 76 | 43 | 33 | 0 | 0 |
| registry | 108 | 29 | 79 | 67 | 12 | 0 | 0 |
| pool | 119 | 31 | 88 | 59 | 29 | 0 | 0 |
| perp | 196 | 134 | 62 | 43 | 19 | 0 | 0 |
| rotation | 96 | 47 | 49 | 21 | 28 | 0 | 0 |
| governance | 25 | 14 | 11 | 10 | 1 | 0 | 0 |
| nft | 121 | 84 | 37 | 16 | 21 | 0 | 0 |
| seed | 96 | 42 | 54 | 14 | 40 | 0 | 0 |

Unresolved edges (0):

## Cross-check (from CROSSCHECK.md)

# Graph cross-check

Independent re-derivation of a sample of filled nodes against the Solidity source at
`/tmp/blind-final/contracts/solidity` (line numbers identical to the repo).
For every sampled node the full body was read first and authority / gate / storage writes /
edges were derived before the graph's own values were opened. No graph file was edited.

## Summary

| cluster | sampled | matched | mismatched |
|---|---|---|---|
| hook | 6 | 6 | 0 |
| registry | 6 | 6 | 0 |
| pool | 6 | 4 | 2 |
| perp | 6 | 6 | 0 |
| rotation | 6 | 6 | 0 |
| governance | 6 | 6 | 0 |
| nft | 6 | 3 | 3 |
| seed | 6 | 6 | 0 |

Clusters with two or more mismatches (send the affected contract back to a fresh extractor):
**pool** (`cauldron/PoolOps.sol`) and **nft** (`cauldron/CauldronGachaRouter.sol`,
`cauldron/CauldronFactory.sol`).

## Sample list

| cluster | four state-changing external/public | internal/private writer | modifier or constructor |
|---|---|---|---|
| hook | `FeeRouteLib.deliver` (ungated), `CauldronHook.forceClosePerps`, `CauldronHook.releaseRelaunchAsset` (delegatecall), `CauldronHook.claimProposerFees` (ungated) | `CauldronHook._routeEthFee` | `CauldronHook` constructor |
| registry | `CauldronRegistry.relaunch` (ungated), `CauldronRegistry.rotateSlice` (delegatecall), `CauldronRegistry.emergencySweep`, `CauldronRegistry.donateToReserve` (ungated) | `CauldronRegistry._recordSeed` | modifier `timelocked` |
| pool | `PoolOps.createAndSeed` (ungated), `PoolOps.executeBuy`, `PoolOps.removePartial`, `PoolOps.addToReserve` (ungated) | none exist in this cluster — substituted `PoolOps.claimFromReserve` | `CauldronBase` constructor |
| perp | `PerpEngine.openLong` (ungated), `PerpEngine.liquidate`, `PerpVault.withdrawToken`, `PerpEngine.syncGeneration` (ungated) | `PerpEngine._routeFee` | modifier `onlyVault` |
| rotation | `RedemptionExt.rotateSliceFrom` (ungated), `QuoteRotator.swapOnce`, `QuoteRotator.unlockCallback`, `CauldronVault.redeem` | `RedemptionExt._pullGrow` | modifier `onlyRegistry` |
| governance | `TreasuryGovernor.execute` (ungated), `TreasuryGovernor.propose`, `TreasuryGovernor.vote`, `CauldronGovernor.markConsumed` | none exist in this cluster — substituted `TreasuryGovernor.consume` | `TreasuryGovernor` constructor |
| nft | `CauldronGachaRouter.playChurn` (ungated), `CauldronGachaRouter.unlockCallback`, `MiFrensDividend.claimTokens`, `CauldronFactory.deployBrew` (ungated) | `MiFrensDividend._castSpell` | modifier `nonReentrant` |
| seed | `CauldronSeeder.poke` (ungated), `CauldronSeeder.unlockCallback`, `LaunchSniper.launch`, `MigrationVesting.vestBatch` (ungated) | `CauldronSeeder._teardown` | modifier `onlyRegistry` |

## Mismatches (step 2)

`cluster | node | field | extractor value | my value | cite`

- `pool | PoolOps.claimFromReserve | edge trust label | "IERC20.balanceOf (PoolOps.sol:1163), TRUSTED" and "IERC20.balanceOf (PoolOps.sol:1175), TRUSTED" | UNTRUSTED | PoolOps.sol:1163`
  The address called is `Currency.unwrap(key.currency1)` out of the caller's own `key` argument, and
  the node's own authority text reads "anyone directly at the linked library address". The
  structurally identical call in the same file, `IERC20(token).balanceOf(address(this))`
  (PoolOps.sol:921), is labelled UNTRUSTED, so the file disagrees with itself.
- `pool | PoolOps.addToReserve | edge trust label | "IERC20.balanceOf (PoolOps.sol:1201), TRUSTED" and "IERC20.balanceOf (PoolOps.sol:1214), TRUSTED" | UNTRUSTED | PoolOps.sol:1201`
  Same shape: `address token = Currency.unwrap(key.currency1);` (PoolOps.sol:1199) comes from the
  caller's `key`.
- `nft | CauldronGachaRouter.playChurn | edges | 6 edges, none for the unlock | a seventh edge for poolManager.unlock | CauldronGachaRouter.sol:379`
  The body's central out-call, `bytes memory ret = poolManager.unlock(` (CauldronGachaRouter.sol:379),
  has no edge; only the internal helpers and the two hook calls are recorded.
- `nft | CauldronGachaRouter.unlockCallback | edges | 7 edges, none for either swap | two more edges for poolManager.swap | CauldronGachaRouter.sol:422, CauldronGachaRouter.sol:436`
  Both `BalanceDelta delta = poolManager.swap(` sites are missing. The analogous node
  `QuoteRotator.unlockCallback` does carry "IPoolManager.swap (QuoteRotator.sol:620)".
- `nft | CauldronFactory.deployBrew | edges | 3 edges, all setters | six, adding the three deployments | CauldronFactory.sol:71, CauldronFactory.sol:75, CauldronFactory.sol:81`
  `new CauldronCollection(` (CauldronFactory.sol:71), `new CauldronVault(address(col), c.registry, 0);`
  (CauldronFactory.sol:75) and `new RoyaltyRouter(c.hook);` (CauldronFactory.sol:81) each run another
  contract's constructor and are what make this factory the collection's deployer — the privilege the
  very next line, `col.setVault(address(v));` (CauldronFactory.sol:76), relies on.

Everything else in the sample re-derived identically: authority, the exact gate line, the full
storage-write set, and every edge with its trust label.

### Checks that could have gone the other way but did not

- `CauldronHook.forceClosePerps` carries `writes: []` although its body assigns at
  CauldronHook.sol:1764 and CauldronHook.sol:1766. Correct: the variable is declared
  `bool private transient _inRelaunchClose;` (CauldronHook.sol:340) — transient, not storage.
- `CauldronHook._routeEthFee` omits `_feeAsset` from its reads for the same reason:
  `address internal transient _feeAsset;` (CauldronHook.sol:697).
- `PerpVault.withdrawToken` omits `FullMath.mulDiv` (PerpVault.sol:380); those helpers are
  `internal pure`, so there is no call to record.
- Every gate quote that points into a different file was opened and matched:
  CauldronRegistry.sol:1759 (`NotPoolManager`), RedemptionExt.sol:317 (`NoRotationApproved`),
  RedemptionExt.sol:79 (`RedemptionPaused`), CauldronSeeder.sol:342 (`OnlyPoolManager`).
- `TreasuryGovernor` constructor writes are tagged immutable where the declarations say so
  (TreasuryGovernor.sol:131, TreasuryGovernor.sol:223), and `guardian (line 324)` — the one real
  storage slot — is not tagged.

### Conventions that differ between clusters (not counted as mismatches)

- Writes performed by a modifier are attributed to the *function* in registry
  (`emergencyReadyAt (line 391)` on `emergencySweep`, which reaches it through `timelocked`) but only
  to the *modifier* node in nft (`_locked` on `nonReentrant`, absent from `playChurn`).
- A protocol address that an admin sets is TRUSTED in registry, rotation and perp
  (`ICauldronGovernor.winner (CauldronRegistry.sol:849)`, `CauldronHook.perpEngine
  (RedemptionExt.sol:539)`) and UNTRUSTED in hook and nft (`IPerpForceClose.forceCloseAllDead
  (CauldronHook.sol:1765)`, `ICauldronHookGacha.commitCrystals (CauldronGachaRouter.sol:387)`).
- For a delegatecall forwarder the gate is quoted from the facet
  (`CauldronRegistry.rotateSlice` cites RedemptionExt.sol:317) while the facet's own node
  `RedemptionExt.rotateSliceFrom` reads UNGATED. Both statements are true of the code; they just
  answer different questions.

## Missing external calls (step 3)

Scanned `hook`, `perp`, `nft` and `registry` for `.transfer(`, `.transferFrom(`, `safeTransfer`,
`.call{`, `.call(`, `latestRoundData`, `unlock(`, `modifyLiquidity`, `settle(`, `take(` outside
comments, mapped each hit to its node through `body_lines`, and checked for an edge at that line.
13 genuine misses. (Three further hits — PerpEngine.sol:1536, CauldronGachaRouter.sol:535,
CauldronGachaRouter.sol:541 — are the `_safeTransfer` / `_safeTransferFrom` declaration lines; their
real call sites at PerpEngine.sol:1537, CauldronGachaRouter.sol:537 and CauldronGachaRouter.sol:543
all do carry edges.)

`cluster | node | missing edge text I would write`

- `hook | CauldronHook._takeEthFee | "IPoolManager.take (CauldronHook.sol:1460), TRUSTED, out-of-cluster"`
- `hook | LegacyBuyLib.buyStep | "IPoolManager.settle (LegacyBuyLib.sol:93), TRUSTED, out-of-cluster"`
- `hook | LegacyBuyLib.buyStep | "IPoolManager.take (LegacyBuyLib.sol:97), TRUSTED, out-of-cluster"`
- `perp | PerpSwapLib.swapLeg | "IPoolManager.take (PerpSwapLib.sol:90), TRUSTED, out-of-cluster"`
- `perp | PerpSwapLib.swapLeg | "IPoolManager.take (PerpSwapLib.sol:95), TRUSTED, out-of-cluster"`
- `perp | PerpSwapLib._settle | "IPoolManager.settle (PerpSwapLib.sol:115), TRUSTED, out-of-cluster"`
- `nft | CauldronGachaRouter._play | "IPoolManager.unlock (CauldronGachaRouter.sol:301), TRUSTED, out-of-cluster"`
- `nft | CauldronGachaRouter.playChurn | "IPoolManager.unlock (CauldronGachaRouter.sol:379), TRUSTED, out-of-cluster"`
- `nft | CauldronGachaRouter._settle | "IPoolManager.settle (CauldronGachaRouter.sol:511), TRUSTED, out-of-cluster"`
- `nft | CauldronGachaRouter._take | "IPoolManager.take (CauldronGachaRouter.sol:516), TRUSTED, out-of-cluster"`
- `nft | MiFrensDividend._collectEnchantFee | "IERC20.transferFrom (MiFrensDividend.sol:455), UNTRUSTED, out-of-cluster"`
- `registry | CauldronRegistry.migrateToSuccessor | "IERC721.transferFrom (CauldronRegistry.sol:524), TRUSTED, out-of-cluster"`
- `registry | CauldronRegistry.migrateToSuccessor | "IERC721.transferFrom (CauldronRegistry.sol:525), TRUSTED, out-of-cluster"`

Plus, from the sample rather than the scan (the scan's pattern list has no `.swap(` or `new `):
the two `poolManager.swap` sites in `CauldronGachaRouter.unlockCallback`
(CauldronGachaRouter.sol:422, CauldronGachaRouter.sol:436) and the three deployments in
`CauldronFactory.deployBrew` (CauldronFactory.sol:71, CauldronFactory.sol:75,
CauldronFactory.sol:81), all listed above as step-2 mismatches.

DERIVED: in `cauldron/CauldronGachaRouter.sol` the pattern is total — not one of the six direct
`poolManager` calls in that contract has an edge, while every internal helper call does. That looks
like a single systematic omission rather than six independent slips.

## join.py

`python3 audit/graph/join.py audit/graph`

| cluster | edges | in-cluster | out-of-cluster | resolved to node | resolved to lib/low-level | unresolved | malformed |
|---|---|---|---|---|---|---|---|
| hook | 124 | 54 | 70 | 43 | 27 | 0 | 0 |
| registry | 106 | 29 | 77 | 67 | 10 | 0 | 0 |
| pool | 119 | 31 | 88 | 59 | 29 | 0 | 0 |
| perp | 190 | 134 | 56 | 43 | 13 | 0 | 0 |
| rotation | 96 | 47 | 49 | 21 | 28 | 0 | 0 |
| governance | 25 | 14 | 11 | 10 | 1 | 0 | 0 |
| nft | 110 | 84 | 26 | 16 | 10 | 0 | 0 |
| seed | 96 | 42 | 54 | 14 | 40 | 0 | 0 |

Unresolved edges (0):

Nothing unresolved and nothing malformed. Note that this only proves every edge that was written
resolves to something — it cannot see the 13 calls above, which were never written down.

## Residual: what the validator cannot catch

The validator proves shape: every node exists in the skeleton, every cited line contains the named identifier, every gate quote is a real substring, every callee resolves, every storage name is in the compiled layout, every external selector matches the compiler. It does not prove that a `reachability` sentence is true, that an `authority` is complete (a gate hidden in a callee), or that a TRUSTED/UNTRUSTED label is right. Claims that could not be tied to a line carry the tag DERIVED; the per-cluster DERIVED counts above are the size of that residual. The cross-check section samples exactly those fields and re-derives them independently; its mismatch counts are the measured error rate.

Conventions that differ between extractors (found by the cross-check, kept as-is, read the field with this in mind): writes performed inside a modifier are attributed to the calling function in the registry cluster but to the modifier node in the nft cluster; an admin-settable protocol address (router, oracle, venue) is labelled TRUSTED in registry/rotation/perp and UNTRUSTED in hook/nft. The fix-up pass after the cross-check made PoolOps, CauldronGachaRouter, and CauldronFactory consistent with the rule "UNTRUSTED = an address a user or admin can point elsewhere".

Also outside the validator: public state-variable getters are part of the external surface but have no declaration node (the validator lists them as INFO per contract); contract creations (`new X`) are recorded in `value`/`reachability`, not as edges; and Yul functions inside `assembly` blocks are not nodes.
