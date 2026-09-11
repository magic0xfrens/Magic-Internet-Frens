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
