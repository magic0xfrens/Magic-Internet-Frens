# CHANGES SINCE 2026-09-18 -- graph refresh for the 2026-09-23 re-audit fixes

Skeleton regenerated from `contracts/solidity` after the re-audit fixes (the High/Medium
remediation and the ten Lows). The committed graphs were carried onto it with `rebase.py`:
unchanged bodies keep their fields with citations remapped through a line diff; every ADDED and
CHANGED node below was re-read from source and re-annotated by hand, and neighbouring nodes whose
prose cited a moved line were corrected.

The validator had been hardened (typed callees only; per-type dependency methods) without the
graph being brought along, so this refresh also:

- regenerates `cache/libfns.json` per dependency type (`libfns.py`); the old flat list failed closed;
- rewrites low-level `x.call`/`x.staticcall` edges to the selector they encode (`I.f`), and drops
  edges with no callee function (native sends, raw forwarding), which stay described in `value`;
- drops edges that were extraction artefacts (`X.returns`), types receiver variables, and brings
  the generated edge/read/write counts in stub prose back in line with the fields;
- rebuilds `storageLayout`/`methodIdentifiers` caches for every changed contract.

Result: `validate.py` reports 0 failures on all ten clusters, and `join.py` resolves every edge.

Residual, stated plainly: 479 of 1102 nodes still carry generated stub reachability prose
("DERIVED from the current body: ...", "Internal body declared at ..."). Their mechanical
fields, edges and citations are current and validated, but the prose is a summary, not a
hand-written reading of the body. The last column counts them per cluster.

## Per-cluster summary

| cluster | nodes (new/old) | added | removed | changed | moved | stub prose |
|---|---|---|---|---|---|---|
| hook | 148/146 | 3 | 1 | 9 | 0 | 0 |
| registry | 89/89 | 1 | 1 | 2 | 0 | 2 |
| pool | 78/77 | 1 | 0 | 3 | 4 | 5 |
| perp | 261/216 | 47 | 2 | 15 | 0 | 191 |
| rotation | 103/93 | 10 | 0 | 14 | 6 | 79 |
| governance | 48/48 | 0 | 0 | 4 | 0 | 16 |
| nft | 173/167 | 6 | 0 | 7 | 3 | 0 |
| seed | 69/69 | 0 | 0 | 1 | 0 | 68 |
| art | 62/61 | 1 | 0 | 2 | 0 | 59 |
| deploy | 71/66 | 6 | 1 | 6 | 4 | 59 |

## hook

ADDED (3): CauldronHook.setSweepFailOpen, CauldronHook._cacheLegacyThreshold, IPerpEngineLiq (declared in CauldronHook.sol).sweepLiquidations

REMOVED (1): IPerpEngineLiq (declared in CauldronHook.sol).sweepLiquidations

CHANGED (9): CauldronHook._liqSweep, CauldronHook._maybeLegacyBuyback, CauldronHook.legacyBuyStep, CauldronHook._routeEthFee, CauldronHook.setLiveKey, CauldronHook.setLegacyBuyback, CauldronHook.nftPriceAt, FeeRouteLib.deliver, SurtaxLib.surtaxBps

## registry

ADDED (1): CauldronRegistry.emergencyWithdrawLP

REMOVED (1): CauldronRegistry.emergencyWithdrawLP

CHANGED (2): CauldronRegistry.relaunch, CauldronRegistry._perpHousekeep

## pool

ADDED (1): IPerpBook (declared in CauldronBase.sol).requoteBook

CHANGED (3): CauldronBase.floorPerFren, PoolOps.recycleCollection, PoolOps.buyCollection

## perp

ADDED (47): IRequoteEngine (declared in PerpSwapLib.sol).quote, IRequoteEngine (declared in PerpSwapLib.sol).vault, IRequoteEngine (declared in PerpSwapLib.sol).registry, IRequoteEngine (declared in PerpSwapLib.sol).syncedGeneration, IRequoteEngine (declared in PerpSwapLib.sol).payoutOwedTotal, IRequoteEngine (declared in PerpSwapLib.sol).owner, IRequoteEngine (declared in PerpSwapLib.sol).treasury, IRequoteEngine (declared in PerpSwapLib.sol).poke, IRequoteRegistry (declared in PerpSwapLib.sol).currentGeneration, IRequoteRegistry (declared in PerpSwapLib.sol).generationQuote, IRequoteRotator (declared in PerpSwapLib.sol).quoteOracle, IRequoteRotator (declared in PerpSwapLib.sol).venueFor, IRequoteRotator (declared in PerpSwapLib.sol).swapOnce, IRequoteRotator (declared in PerpSwapLib.sol).withdraw, IVaultQuoteStake (declared in PerpSwapLib.sol).hasQuoteStake, PerpEngine.sweepLiquidations, PerpEngine._doSweep, PerpEngine._condemnedByThisTrade, PerpEngine._bookSlots, PerpEngine.requoteBook, PerpSwapLib._quoteFactor, PerpSwapLib._requoteBook, PerpSwapLib._factors, PerpSwapLib._restatePots, PerpSwapLib.syncQuoteChangeAt, PerpSwapLib._carryEmpty, PerpSwapLib._ldAddr, PerpSwapLib.requoteBookAt, PerpSwapLib._posAt, PerpSwapLib._idsAt, PerpSwapLib._obsAt, PerpSwapLib._ringAt, PerpSwapLib._slot, PerpSwapLib._ld, PerpSwapLib._st, PerpSwapLib._stAddr, PerpSwapLib._factorStrict, PerpSwapLib._shortBacking, PerpSwapLib._convert, PerpSwapLib._held, PerpSwapLib._restatePositions, PerpSwapLib._shiftRing, PerpSwapLib._vaultHook, PerpVault._markEth, PerpVault.beforeBookRequote, PerpVault.afterBookRequote, PerpVault._toYieldUnit

REMOVED (2): PerpEngine.sweepLiquidations, PerpEngine._doSweep

CHANGED (15): PerpEngine._currentTick, PerpEngine.syncGeneration, PerpEngine._settle, PerpEngine._rebook, PerpEngine._absorbPlvLoss, PerpSwapLib.quoteFactor, PerpVault.hasStakers, PerpVault.deposit, PerpVault.withdrawEth, PerpVault._syncEthQueue, PerpVault.claimPendingEth, PerpVault._syncTokYield, PerpVault._settleTok, PerpVault.claimTokYield, PerpVault.pendingTokYield

## rotation

ADDED (10): CauldronVault._legacyFloorActive, ILegacyFloorHook (declared in CauldronVault.sol).vault, QuoteOracle._readRound, QuoteOracle._readWords, QuoteRotator._liveEngine, QuoteRotator._pairKey, QuoteRotator.venueFor, RedemptionExt._handedOff, RedemptionExt._handOffLegs, RedemptionExt.emergencyWithdrawLP

CHANGED (14): CauldronVault.floorPerNFT, CauldronVault.redeem, QuoteOracle.usdPerRawUnit, QuoteOracle._sequencerOk, QuoteRotator.onlyRegistry, QuoteRotator.setVenue, QuoteRotator.swapOnce, QuoteRotator.withdraw, RedemptionExt.redeemOgFren, RedemptionExt.buyTreasuryOgFren, RedemptionExt.materializeLegacyReserve, RedemptionExt.rotateSliceFrom, RedemptionExt._recordLeg, RedemptionExt.recoverLegs

## governance

CHANGED (4): TreasuryGovernor.vote, TreasuryGovernor.execute, TreasuryGovernor.cancel, TreasuryGovernor.winner

## nft

ADDED (6): MiFrensDividend.pushTokenIsolated, MiFrensGenesis.mintDiscounted, MiFrensGenesis.setDiscountRoot, MiFrensGenesis.setDiscountSetter, MiFrensGenesis._mintGenesis, MiFrensGenesis.remainingGenesisAllowance

CHANGED (7): CauldronGachaRouter._playInCurveUnits, CollectionLedger.crystallize, GachaLib.resolveTickets, MiFrensDividend.<unnamed>, MiFrensDividend._tryPush, MiFrensGenesis.<unnamed>, MiFrensGenesis.mint

## seed

CHANGED (1): MigrationVesting._isInstant

## art

ADDED (1): FrenRenderer._ensure

CHANGED (2): FrenRenderer._append, FrenRenderer._appendUint

## deploy

ADDED (6): DeployCauldron (declared in DeployCauldron.s.sol)._hookFlags, DeployLaunchpad (declared in DeployLaunchpad.s.sol)._preflightQuoteStack, DeployLaunchpad (declared in DeployLaunchpad.s.sol)._requireUsableFeed, DeployLaunchpad (declared in DeployLaunchpad.s.sol)._deployQuoteOracle, DeployLaunchpad (declared in DeployLaunchpad.s.sol)._deployRotationStack, IRegistryGate (declared in DeployMigrationVesting.s.sol).emergencyReadyAt

REMOVED (1): DeployLaunchpad (declared in DeployLaunchpad.s.sol)._deployRotationStack

CHANGED (6): DeployCauldron (declared in DeployCauldron.s.sol).run, DeployLaunchpad (declared in DeployLaunchpad.s.sol).run, DeployMigrationVesting (declared in DeployMigrationVesting.s.sol).run, FixFactoryWiring (declared in FixFactoryWiring.s.sol).run, VenueSeeder (declared in DeployRotationStack.s.sol).seed, VenueSeeder (declared in DeployRotationStack.s.sol).seedBand
