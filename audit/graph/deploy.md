# Function graph — `deploy`

Current source-derived semantic map: **66 nodes** across **14 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `deploy/DeployCauldron.s.sol` | 120 |
| `deploy/DeployLaunchSniper.s.sol` | 63 |
| `deploy/DeployLaunchpad.s.sol` | 831 |
| `deploy/DeployMigrationVesting.s.sol` | 111 |
| `deploy/DeployPerp.s.sol` | 268 |
| `deploy/DeployQuoteAssets.s.sol` | 67 |
| `deploy/DeployRenderer.s.sol` | 92 |
| `deploy/DeployRotationStack.s.sol` | 443 |
| `deploy/DeployV4Core.s.sol` | 96 |
| `deploy/FixFactoryWiring.s.sol` | 63 |
| `deploy/SellVolume.s.sol` | 59 |
| `deploy/SnipeBuy.s.sol` | 112 |
| `deploy/SwapVolume.s.sol` | 84 |
| `deploy/TopUpVenue.s.sol` | 127 |

## `DeployCauldron (declared in DeployCauldron.s.sol)`

### `run` — DeployCauldron.s.sol:45

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployCauldron.s.sol:45; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `CauldronHook.getHookPermissions (DeployCauldron.s.sol:54), TRUSTED, out-of-cluster`; `HookMiner.find (DeployCauldron.s.sol:69), TRUSTED, out-of-cluster`; `registry.setRedemptionExt (DeployCauldron.s.sol:101), UNTRUSTED, out-of-cluster`; `hook.setRegistry (DeployCauldron.s.sol:105), UNTRUSTED, out-of-cluster`; `hook.setOpener (DeployCauldron.s.sol:110), UNTRUSTED, out-of-cluster`; `hook.setTaxExempt (DeployCauldron.s.sol:111), UNTRUSTED, out-of-cluster`; `registry.summon (DeployCauldron.s.sol:114), UNTRUSTED, out-of-cluster`
- Observations: none


## `IHookExempt (declared in DeployLaunchSniper.s.sol)`

### `setTaxExempt` — DeployLaunchSniper.s.sol:8

- Signature: `function setTaxExempt(address who, bool exempt) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setTaxExempt` is declared at DeployLaunchSniper.s.sol:8; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `isOpener` — DeployLaunchSniper.s.sol:9

- Signature: `function isOpener(address who) external view returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `isOpener` is declared at DeployLaunchSniper.s.sol:9; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IPresaleFinalizer (declared in DeployLaunchSniper.s.sol)`

### `setFinalizer` — DeployLaunchSniper.s.sol:13

- Signature: `function setFinalizer(address who) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setFinalizer` is declared at DeployLaunchSniper.s.sol:13; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `DeployLaunchSniper (declared in DeployLaunchSniper.s.sol)`

### `run` — DeployLaunchSniper.s.sol:28

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployLaunchSniper.s.sol:28; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `hook.setOpener (DeployLaunchSniper.s.sol:38), UNTRUSTED, out-of-cluster`; `external.isOpener (DeployLaunchSniper.s.sol:44), UNTRUSTED, out-of-cluster`; `hook.setOpener (DeployLaunchSniper.s.sol:45), UNTRUSTED, out-of-cluster`; `external.setTaxExempt (DeployLaunchSniper.s.sol:52), UNTRUSTED, out-of-cluster`; `external.setFinalizer (DeployLaunchSniper.s.sol:55), UNTRUSTED, out-of-cluster`; `sniper.launch (DeployLaunchSniper.s.sol:60), UNTRUSTED, out-of-cluster`
- Observations: none


## `IOwnable (declared in DeployLaunchpad.s.sol)`

### `transferOwnership` — DeployLaunchpad.s.sol:36

- Signature: `function transferOwnership(address newOwner) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `transferOwnership` is declared at DeployLaunchpad.s.sol:36; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `DeployLaunchpad (declared in DeployLaunchpad.s.sol)`

### `run` — DeployLaunchpad.s.sol:98

- Signature: `function run() external`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `address deployer = pk != 0 ? vm.addr(pk) : msg.sender; (DeployLaunchpad.s.sol:108)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployLaunchpad.s.sol:98; caller satisfying the in-body msg.sender check.
- Edges: `HookMiner.find (DeployLaunchpad.s.sol:161), TRUSTED, out-of-cluster`; `timelock.schedule (DeployLaunchpad.s.sol:170), UNTRUSTED, out-of-cluster`; `registry.setRedemptionExt (DeployLaunchpad.s.sol:204), UNTRUSTED, out-of-cluster`; `BadgeArtLib.upload (DeployLaunchpad.s.sol:241), TRUSTED, library`; `hook.setRegistry (DeployLaunchpad.s.sol:250), UNTRUSTED, out-of-cluster`; `hook.setGuild (DeployLaunchpad.s.sol:251), UNTRUSTED, out-of-cluster`; `hook.setOpener (DeployLaunchpad.s.sol:252), UNTRUSTED, out-of-cluster`; `gacha.setOracle (DeployLaunchpad.s.sol:262), UNTRUSTED, out-of-cluster`; `hook.setDeathThreshold (DeployLaunchpad.s.sol:286), UNTRUSTED, out-of-cluster`; `hook.setPolicies (DeployLaunchpad.s.sol:329), UNTRUSTED, out-of-cluster`; `curve.totalToMintOut (DeployLaunchpad.s.sol:332), UNTRUSTED, out-of-cluster`; `curve.priceAt (DeployLaunchpad.s.sol:334), UNTRUSTED, out-of-cluster`; `hook.setOpener (DeployLaunchpad.s.sol:343), UNTRUSTED, out-of-cluster`; `hook.setTaxExempt (DeployLaunchpad.s.sol:344), UNTRUSTED, out-of-cluster`; `registry.setRoyalty (DeployLaunchpad.s.sol:346), UNTRUSTED, out-of-cluster`; `presale.setRoyalty (DeployLaunchpad.s.sol:347), UNTRUSTED, out-of-cluster`; `presale.setDividend (DeployLaunchpad.s.sol:350), UNTRUSTED, out-of-cluster`; `dividend.setRegistry (DeployLaunchpad.s.sol:354), UNTRUSTED, out-of-cluster`; `dividend.setFunder (DeployLaunchpad.s.sol:359), UNTRUSTED, out-of-cluster`; `registry.setFactory (DeployLaunchpad.s.sol:360), UNTRUSTED, out-of-cluster`; `registry.setGovernor (DeployLaunchpad.s.sol:361), UNTRUSTED, out-of-cluster`; `registry.setSeeder (DeployLaunchpad.s.sol:372), UNTRUSTED, out-of-cluster`; `registry.setSeedWindow (DeployLaunchpad.s.sol:373), UNTRUSTED, out-of-cluster`; `hook.setOpener (DeployLaunchpad.s.sol:380), UNTRUSTED, out-of-cluster`; `hook.setTaxExempt (DeployLaunchpad.s.sol:381), UNTRUSTED, out-of-cluster`; `hook.setSnipeParams (DeployLaunchpad.s.sol:393), UNTRUSTED, out-of-cluster`; `seeder.refundPrime (DeployLaunchpad.s.sol:405), UNTRUSTED, out-of-cluster`; `registry.fundPrimeBuy (DeployLaunchpad.s.sol:410), UNTRUSTED, out-of-cluster`; `seeder.fundPrime (DeployLaunchpad.s.sol:413), UNTRUSTED, out-of-cluster`; `registry.setCollectionLedger (DeployLaunchpad.s.sol:426), UNTRUSTED, out-of-cluster`; `hook.setLegacyBuyback (DeployLaunchpad.s.sol:427), UNTRUSTED, out-of-cluster`; `registry.setGenesisMetadata (DeployLaunchpad.s.sol:433), UNTRUSTED, out-of-cluster`; `registry.setGenesisMetadata (DeployLaunchpad.s.sol:435), UNTRUSTED, out-of-cluster`; `presale.setLiquidatorRenderer (DeployLaunchpad.s.sol:441), UNTRUSTED, out-of-cluster`; `factory.setLiquidatorRenderer (DeployLaunchpad.s.sol:449), UNTRUSTED, out-of-cluster`; `treasuryGov.setQuoteOracle (DeployLaunchpad.s.sol:514), UNTRUSTED, out-of-cluster`; `treasuryGov.setQuoteOracle (DeployLaunchpad.s.sol:517), UNTRUSTED, out-of-cluster`; `registry.setRotationWiring (DeployLaunchpad.s.sol:520), UNTRUSTED, out-of-cluster`; `registry.setGenesisBonus (DeployLaunchpad.s.sol:537), UNTRUSTED, out-of-cluster`; `registry.setAirdropReserve (DeployLaunchpad.s.sol:545), UNTRUSTED, out-of-cluster`; `registry.fundPrimeBuy (DeployLaunchpad.s.sol:554), UNTRUSTED, out-of-cluster`; `governor.setRegistry (DeployLaunchpad.s.sol:561), UNTRUSTED, out-of-cluster`; `presale.setRegistry (DeployLaunchpad.s.sol:562), UNTRUSTED, out-of-cluster`; `registry.setIgniter (DeployLaunchpad.s.sol:582), UNTRUSTED, out-of-cluster`; `external.transferOwnership (DeployLaunchpad.s.sol:583), UNTRUSTED, out-of-cluster`
- Observations: none

### `_deployRotationStack` — DeployLaunchpad.s.sol:637

- Signature: `function _deployRotationStack( CauldronRegistry registry, QuoteRotator rotator, address poolManager, address positionManager, address deployer ) internal`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_deployRotationStack` is declared at DeployLaunchpad.s.sol:637; internal (callers are paths that reference this function).
- Edges: `oracle.setPegged (DeployLaunchpad.s.sol:691), UNTRUSTED, out-of-cluster`; `oracle.setFeed (DeployLaunchpad.s.sol:693), UNTRUSTED, out-of-cluster`; `oracle.setBounds (DeployLaunchpad.s.sol:694), UNTRUSTED, out-of-cluster`; `oracle.setPegged (DeployLaunchpad.s.sol:713), UNTRUSTED, out-of-cluster`; `oracle.setFeed (DeployLaunchpad.s.sol:715), UNTRUSTED, out-of-cluster`; `rotator.setArbParams (DeployLaunchpad.s.sol:717), UNTRUSTED, out-of-cluster`; `rotator.setRotationSlipBps (DeployLaunchpad.s.sol:730), UNTRUSTED, out-of-cluster`; `registry.setAllowedQuote (DeployLaunchpad.s.sol:733), UNTRUSTED, out-of-cluster`; `oracle.usdPerRawUnit (DeployLaunchpad.s.sol:757), UNTRUSTED, out-of-cluster`; `oracle.usdPerRawUnit (DeployLaunchpad.s.sol:758), UNTRUSTED, out-of-cluster`; `usdg.mint (DeployLaunchpad.s.sol:773), UNTRUSTED, out-of-cluster`; `vs.seed (DeployLaunchpad.s.sol:791), UNTRUSTED, out-of-cluster`; `vs.seedBand (DeployLaunchpad.s.sol:796), UNTRUSTED, out-of-cluster`; `rotator.setVenue (DeployLaunchpad.s.sol:803), UNTRUSTED, out-of-cluster`; `hook.commitCrystals (DeployLaunchpad.s.sol:821), UNTRUSTED, out-of-cluster`
- Observations: none


## `IRegistryGate (declared in DeployMigrationVesting.s.sol)`

### `emergencyAdmin` — DeployMigrationVesting.s.sol:9

- Signature: `function emergencyAdmin() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `emergencyAdmin` is declared at DeployMigrationVesting.s.sol:9; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `emergencyDelay` — DeployMigrationVesting.s.sol:10

- Signature: `function emergencyDelay() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `emergencyDelay` is declared at DeployMigrationVesting.s.sol:10; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `claimGate` — DeployMigrationVesting.s.sol:11

- Signature: `function claimGate() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `claimGate` is declared at DeployMigrationVesting.s.sol:11; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `setClaimGate` — DeployMigrationVesting.s.sol:12

- Signature: `function setClaimGate(address gate) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setClaimGate` is declared at DeployMigrationVesting.s.sol:12; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IHookPerp (declared in DeployMigrationVesting.s.sol)`

### `perpEngine` — DeployMigrationVesting.s.sol:14

- Signature: `function perpEngine() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `perpEngine` is declared at DeployMigrationVesting.s.sol:14; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IEngineVault (declared in DeployMigrationVesting.s.sol)`

### `vault` — DeployMigrationVesting.s.sol:15

- Signature: `function vault() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `vault` is declared at DeployMigrationVesting.s.sol:15; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `DeployMigrationVesting (declared in DeployMigrationVesting.s.sol)`

### `run` — DeployMigrationVesting.s.sol:54

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployMigrationVesting.s.sol:54; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `external.vault (DeployMigrationVesting.s.sol:64), UNTRUSTED, out-of-cluster`; `external.perpEngine (DeployMigrationVesting.s.sol:68), UNTRUSTED, out-of-cluster`; `external.vault (DeployMigrationVesting.s.sol:70), UNTRUSTED, out-of-cluster`; `external.emergencyAdmin (DeployMigrationVesting.s.sol:89), UNTRUSTED, out-of-cluster`; `external.setClaimGate (DeployMigrationVesting.s.sol:91), UNTRUSTED, out-of-cluster`; `external.claimGate (DeployMigrationVesting.s.sol:107), UNTRUSTED, out-of-cluster`
- Observations: none


## `IHookWire (declared in DeployPerp.s.sol)`

### `setPerpEngine` — DeployPerp.s.sol:14

- Signature: `function setPerpEngine(address engine) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setPerpEngine` is declared at DeployPerp.s.sol:14; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `collection` — DeployPerp.s.sol:15

- Signature: `function collection() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `collection` is declared at DeployPerp.s.sol:15; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `ICollLiq (declared in DeployPerp.s.sol)`

### `liquidatorMinter` — DeployPerp.s.sol:18

- Signature: `function liquidatorMinter() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `liquidatorMinter` is declared at DeployPerp.s.sol:18; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IPerpVaultDeposit (declared in DeployPerp.s.sol)`

### `depositEth` — DeployPerp.s.sol:21

- Signature: `function depositEth() external payable returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `depositEth` is declared at DeployPerp.s.sol:21; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IOwnable (declared in DeployPerp.s.sol)`

### `transferOwnership` — DeployPerp.s.sol:24

- Signature: `function transferOwnership(address newOwner) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `transferOwnership` is declared at DeployPerp.s.sol:24; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IRegistryGen (declared in DeployPerp.s.sol)`

### `currentGeneration` — DeployPerp.s.sol:27

- Signature: `function currentGeneration() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `currentGeneration` is declared at DeployPerp.s.sol:27; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `generationPoolKey` — DeployPerp.s.sol:28

- Signature: `function generationPoolKey(uint256 gen) external view returns (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `generationPoolKey` is declared at DeployPerp.s.sol:28; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `DeployPerp (declared in DeployPerp.s.sol)`

### `run` — DeployPerp.s.sol:65

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployPerp.s.sol:65; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `hook.collection (DeployPerp.s.sol:92), UNTRUSTED, out-of-cluster`; `external.setPerpEngine (DeployPerp.s.sol:94), UNTRUSTED, out-of-cluster`; `engine.setVault (DeployPerp.s.sol:100), UNTRUSTED, out-of-cluster`; `engine.setVaultLimits (DeployPerp.s.sol:105), UNTRUSTED, out-of-cluster`; `engine.setRisk (DeployPerp.s.sol:119), UNTRUSTED, out-of-cluster`; `engine.fundInsurance (DeployPerp.s.sol:132), UNTRUSTED, out-of-cluster`; `engine.setGuards (DeployPerp.s.sol:158), UNTRUSTED, out-of-cluster`; `engine.setRouting (DeployPerp.s.sol:178), UNTRUSTED, out-of-cluster`; `markSource.addPool (DeployPerp.s.sol:179), UNTRUSTED, out-of-cluster`; `PerpEngine.blocksVolumeLink (DeployPerp.s.sol:187), TRUSTED, out-of-cluster`; `external.currentGeneration (DeployPerp.s.sol:208), UNTRUSTED, out-of-cluster`; `external.generationPoolKey (DeployPerp.s.sol:210), UNTRUSTED, out-of-cluster`; `ms.setPrimary (DeployPerp.s.sol:216), UNTRUSTED, out-of-cluster`; `engine.setRouting (DeployPerp.s.sol:228), UNTRUSTED, out-of-cluster`; `external.depositEth (DeployPerp.s.sol:235), UNTRUSTED, out-of-cluster`; `external.setPerpEngine (DeployPerp.s.sol:246), UNTRUSTED, out-of-cluster`; `external.transferOwnership (DeployPerp.s.sol:247), UNTRUSTED, out-of-cluster`; `external.transferOwnership (DeployPerp.s.sol:248), UNTRUSTED, out-of-cluster`; `external.transferOwnership (DeployPerp.s.sol:254), UNTRUSTED, out-of-cluster`; `external.collection (DeployPerp.s.sol:261), UNTRUSTED, out-of-cluster`; `external.liquidatorMinter (DeployPerp.s.sol:264), UNTRUSTED, out-of-cluster`
- Observations: none


## `IRegistryQuoteAdmin (declared in DeployQuoteAssets.s.sol)`

### `setAllowedQuote` — DeployQuoteAssets.s.sol:10

- Signature: `function setAllowedQuote(address quote, bool allowed, uint256 scale) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setAllowedQuote` is declared at DeployQuoteAssets.s.sol:10; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `allowedQuote` — DeployQuoteAssets.s.sol:11

- Signature: `function allowedQuote(address quote) external view returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `allowedQuote` is declared at DeployQuoteAssets.s.sol:11; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `owner` — DeployQuoteAssets.s.sol:12

- Signature: `function owner() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `owner` is declared at DeployQuoteAssets.s.sol:12; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `DeployQuoteAssets (declared in DeployQuoteAssets.s.sol)`

### `run` — DeployQuoteAssets.s.sol:29

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployQuoteAssets.s.sol:29; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `reg.owner (DeployQuoteAssets.s.sol:45), UNTRUSTED, out-of-cluster`; `reg.setAllowedQuote (DeployQuoteAssets.s.sol:47), UNTRUSTED, out-of-cluster`; `reg.setAllowedQuote (DeployQuoteAssets.s.sol:48), UNTRUSTED, out-of-cluster`
- Observations: none


## `IPegRenderer (declared in DeployRenderer.s.sol)`

### `setRenderer` — DeployRenderer.s.sol:9

- Signature: `function setRenderer(address) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setRenderer` is declared at DeployRenderer.s.sol:9; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `DeployRenderer (declared in DeployRenderer.s.sol)`

### `run` — DeployRenderer.s.sol:38

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployRenderer.s.sol:38; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `store.storeTraits (DeployRenderer.s.sol:73), UNTRUSTED, out-of-cluster`; `external.setRenderer (DeployRenderer.s.sol:79), UNTRUSTED, out-of-cluster`; `store.freeze (DeployRenderer.s.sol:85), UNTRUSTED, out-of-cluster`
- Observations: none


## `IPermit2Approve (declared in DeployRotationStack.s.sol)`

### `approve` — DeployRotationStack.s.sol:26

- Signature: `function approve(address token, address spender, uint160 amount, uint48 expiration) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `approve` is declared at DeployRotationStack.s.sol:26; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IRegistryAdmin (declared in DeployRotationStack.s.sol)`

### `setAllowedQuote` — DeployRotationStack.s.sol:30

- Signature: `function setAllowedQuote(address quote, bool allowed, uint256 scale) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setAllowedQuote` is declared at DeployRotationStack.s.sol:30; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `allowedQuote` — DeployRotationStack.s.sol:31

- Signature: `function allowedQuote(address quote) external view returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `allowedQuote` is declared at DeployRotationStack.s.sol:31; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `setRotationWiring` — DeployRotationStack.s.sol:32

- Signature: `function setRotationWiring(address rotator, address governor) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setRotationWiring` is declared at DeployRotationStack.s.sol:32; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `owner` — DeployRotationStack.s.sol:33

- Signature: `function owner() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `owner` is declared at DeployRotationStack.s.sol:33; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `mifrens` — DeployRotationStack.s.sol:34

- Signature: `function mifrens() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `mifrens` is declared at DeployRotationStack.s.sol:34; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `DeployRotationStack (declared in DeployRotationStack.s.sol)`

### `run` — DeployRotationStack.s.sol:111

- Signature: `function run() external`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `address me = pk != 0 ? vm.addr(pk) : msg.sender; (DeployRotationStack.s.sol:118)`
- Reads: none
- Writes: none
- Value: transfers token or native value through `transfer` (DeployRotationStack.s.sol:211)
- Reachability: `run` is declared at DeployRotationStack.s.sol:111; caller satisfying the in-body msg.sender check.
- Edges: `reg.owner (DeployRotationStack.s.sol:126), UNTRUSTED, out-of-cluster`; `reg.mifrens (DeployRotationStack.s.sol:127), UNTRUSTED, out-of-cluster`; `rotator.setArbParams (DeployRotationStack.s.sol:182), UNTRUSTED, out-of-cluster`; `oracle.setFeed (DeployRotationStack.s.sol:189), UNTRUSTED, out-of-cluster`; `oracle.setFeed (DeployRotationStack.s.sol:190), UNTRUSTED, out-of-cluster`; `oracle.transferOwnership (DeployRotationStack.s.sol:195), UNTRUSTED, out-of-cluster`; `usdg.mint (DeployRotationStack.s.sol:201), UNTRUSTED, out-of-cluster`; `usdg.transfer (DeployRotationStack.s.sol:211), UNTRUSTED, out-of-cluster`; `seeder.seed (DeployRotationStack.s.sol:212), UNTRUSTED, out-of-cluster`; `rotator.setVenue (DeployRotationStack.s.sol:219), UNTRUSTED, out-of-cluster`; `reg.setAllowedQuote (DeployRotationStack.s.sol:223), UNTRUSTED, out-of-cluster`; `reg.setRotationWiring (DeployRotationStack.s.sol:227), UNTRUSTED, out-of-cluster`
- Observations: none


## `VenueSeeder (declared in DeployRotationStack.s.sol)`

### `constructor` — DeployRotationStack.s.sol:269

- Signature: `constructor()`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `constructor` is declared at DeployRotationStack.s.sol:269; deployer.
- Edges: none
- Observations: none

### `seed` — DeployRotationStack.s.sol:271

- Signature: `function seed( IPoolManager poolManager, IPositionManagerOps posm, address usdg, uint256 ethAmount, uint256 usdgAmount, int24 spacing, uint24 fee ) external payable returns (uint256)`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `require(msg.sender == deployer, "only deployer"); (DeployRotationStack.s.sol:280)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `seed` is declared at DeployRotationStack.s.sol:271; caller satisfying the in-body msg.sender check.
- Edges: `PoolOps.openOrAddPair (DeployRotationStack.s.sol:282), TRUSTED, out-of-cluster`
- Observations: none

### `seedBand` — DeployRotationStack.s.sol:329

- Signature: `function seedBand( IPoolManager poolManager, IPositionManagerOps posm, address usdg, uint256 ethAmount, uint256 usdgAmount, int24 spacing, uint24 fee, uint16 bandBps ) external payable returns (uint256)`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `require(msg.sender == deployer, "only deployer"); (DeployRotationStack.s.sol:339)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `seedBand` is declared at DeployRotationStack.s.sol:329; caller satisfying the in-body msg.sender check.
- Edges: `external.approve (DeployRotationStack.s.sol:384), UNTRUSTED, out-of-cluster`; `external.approve (DeployRotationStack.s.sol:385), UNTRUSTED, out-of-cluster`; `posm.nextTokenId (DeployRotationStack.s.sol:391), UNTRUSTED, out-of-cluster`; `posm.modifyLiquidities (DeployRotationStack.s.sol:392), UNTRUSTED, out-of-cluster`
- Observations: none

### `recover` — DeployRotationStack.s.sol:419

- Signature: `function recover(IPositionManagerOps posm, PoolKey memory key, address usdg) external returns (uint256 ethOut, uint256 usdgOut)`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `require(msg.sender == deployer, "only deployer"); (DeployRotationStack.s.sol:423)`
- Reads: none
- Writes: none
- Value: transfers token or native value through `transfer` (DeployRotationStack.s.sol:433)
- Reachability: `recover` is declared at DeployRotationStack.s.sol:419; caller satisfying the in-body msg.sender check.
- Edges: `PoolOps.removeAll (DeployRotationStack.s.sol:425), TRUSTED, out-of-cluster`; `external.balanceOf (DeployRotationStack.s.sol:432), UNTRUSTED, out-of-cluster`; `external.transfer (DeployRotationStack.s.sol:433), UNTRUSTED, out-of-cluster`; `deployer.call (DeployRotationStack.s.sol:436), UNTRUSTED, out-of-cluster`
- Observations: none

### `receive` — DeployRotationStack.s.sol:441

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `receive` is declared at DeployRotationStack.s.sol:441; anyone.
- Edges: none
- Observations: none


## `DeployV4Core (declared in DeployV4Core.s.sol)`

### `run` — DeployV4Core.s.sol:55

- Signature: `function run() external`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `address deployer = pk != 0 ? vm.addr(pk) : msg.sender; (DeployV4Core.s.sol:57)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployV4Core.s.sol:55; caller satisfying the in-body msg.sender check.
- Edges: none
- Observations: none


## `IRegistryFactoryAdmin (declared in FixFactoryWiring.s.sol)`

### `setFactory` — FixFactoryWiring.s.sol:8

- Signature: `function setFactory(address f) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setFactory` is declared at FixFactoryWiring.s.sol:8; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `owner` — FixFactoryWiring.s.sol:9

- Signature: `function owner() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `owner` is declared at FixFactoryWiring.s.sol:9; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `ITimelock (declared in FixFactoryWiring.s.sol)`

### `schedule` — FixFactoryWiring.s.sol:13

- Signature: `function schedule(address target, uint256 value, bytes calldata data, bytes32 pred, bytes32 salt, uint256 delay) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `schedule` is declared at FixFactoryWiring.s.sol:13; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `execute` — FixFactoryWiring.s.sol:14

- Signature: `function execute(address target, uint256 value, bytes calldata data, bytes32 pred, bytes32 salt) external payable`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `execute` is declared at FixFactoryWiring.s.sol:14; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `getMinDelay` — FixFactoryWiring.s.sol:15

- Signature: `function getMinDelay() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `getMinDelay` is declared at FixFactoryWiring.s.sol:15; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `FixFactoryWiring (declared in FixFactoryWiring.s.sol)`

### `run` — FixFactoryWiring.s.sol:33

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at FixFactoryWiring.s.sol:33; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `factory.setLiquidatorRenderer (FixFactoryWiring.s.sol:43), UNTRUSTED, out-of-cluster`; `external.getMinDelay (FixFactoryWiring.s.sol:46), UNTRUSTED, out-of-cluster`; `external.execute (FixFactoryWiring.s.sol:51), UNTRUSTED, out-of-cluster`; `external.schedule (FixFactoryWiring.s.sol:54), UNTRUSTED, out-of-cluster`
- Observations: none


## `IERC20Min (declared in SellVolume.s.sol)`

### `approve` — SellVolume.s.sol:14

- Signature: `function approve(address, uint256) external returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `approve` is declared at SellVolume.s.sol:14; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `balanceOf` — SellVolume.s.sol:15

- Signature: `function balanceOf(address) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `balanceOf` is declared at SellVolume.s.sol:15; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `SellVolume (declared in SellVolume.s.sol)`

### `run` — SellVolume.s.sol:24

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at SellVolume.s.sol:24; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `external.approve (SellVolume.s.sol:42), UNTRUSTED, out-of-cluster`; `router.swap (SellVolume.s.sol:53), UNTRUSTED, out-of-cluster`
- Observations: none


## `ISeederView (declared in SnipeBuy.s.sol)`

### `deployedWad` — SnipeBuy.s.sol:16

- Signature: `function deployedWad() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `deployedWad` is declared at SnipeBuy.s.sol:16; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `seeding` — SnipeBuy.s.sol:17

- Signature: `function seeding() external view returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `seeding` is declared at SnipeBuy.s.sol:17; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `isComplete` — SnipeBuy.s.sol:18

- Signature: `function isComplete() external view returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `isComplete` is declared at SnipeBuy.s.sol:18; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IERC20View (declared in SnipeBuy.s.sol)`

### `balanceOf` — SnipeBuy.s.sol:20

- Signature: `function balanceOf(address) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `balanceOf` is declared at SnipeBuy.s.sol:20; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `SnipeBuy (declared in SnipeBuy.s.sol)`

### `run` — SnipeBuy.s.sol:50

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at SnipeBuy.s.sol:50; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `external.deployedWad (SnipeBuy.s.sol:72), UNTRUSTED, out-of-cluster`; `external.isComplete (SnipeBuy.s.sol:73), UNTRUSTED, out-of-cluster`; `external.seeding (SnipeBuy.s.sol:74), UNTRUSTED, out-of-cluster`; `external.isComplete (SnipeBuy.s.sol:74), UNTRUSTED, out-of-cluster`; `external.balanceOf (SnipeBuy.s.sol:81), UNTRUSTED, out-of-cluster`; `router.swap (SnipeBuy.s.sol:91), UNTRUSTED, out-of-cluster`; `external.balanceOf (SnipeBuy.s.sol:94), UNTRUSTED, out-of-cluster`
- Observations: none

### `_u` — SnipeBuy.s.sol:110

- Signature: `function _u(int24 v) private pure returns (int256)`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_u` is declared at SnipeBuy.s.sol:110; internal (callers are paths that reference this function).
- Edges: none
- Observations: none


## `IHookView (declared in SwapVolume.s.sol)`

### `crystalsReady` — SwapVolume.s.sol:18

- Signature: `function crystalsReady(address player) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `crystalsReady` is declared at SwapVolume.s.sol:18; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `getVolume24h` — SwapVolume.s.sol:19

- Signature: `function getVolume24h(bytes32 id) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `getVolume24h` is declared at SwapVolume.s.sol:19; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `nftCredit` — SwapVolume.s.sol:20

- Signature: `function nftCredit(uint256 epoch, address player) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `nftCredit` is declared at SwapVolume.s.sol:20; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `creditEpoch` — SwapVolume.s.sol:21

- Signature: `function creditEpoch() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `creditEpoch` is declared at SwapVolume.s.sol:21; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `ICollView (declared in SwapVolume.s.sol)`

### `totalMinted` — SwapVolume.s.sol:24

- Signature: `function totalMinted() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `totalMinted` is declared at SwapVolume.s.sol:24; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `balanceOf` — SwapVolume.s.sol:25

- Signature: `function balanceOf(address) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `balanceOf` is declared at SwapVolume.s.sol:25; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `SwapVolume (declared in SwapVolume.s.sol)`

### `run` — SwapVolume.s.sol:35

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at SwapVolume.s.sol:35; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `router.swap (SwapVolume.s.sol:66), UNTRUSTED, out-of-cluster`; `hv.crystalsReady (SwapVolume.s.sol:77), UNTRUSTED, out-of-cluster`; `external.totalMinted (SwapVolume.s.sol:80), UNTRUSTED, out-of-cluster`; `external.balanceOf (SwapVolume.s.sol:81), UNTRUSTED, out-of-cluster`
- Observations: none


## `TopUpVenue (declared in TopUpVenue.s.sol)`

### `run` — TopUpVenue.s.sol:55

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at TopUpVenue.s.sol:55; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `external.mint (TopUpVenue.s.sol:73), UNTRUSTED, out-of-cluster`; `vs.seed (TopUpVenue.s.sol:74), UNTRUSTED, out-of-cluster`; `external.setRotationSlipBps (TopUpVenue.s.sol:83), UNTRUSTED, out-of-cluster`
- Observations: none


## `RecoverVenue (declared in TopUpVenue.s.sol)`

### `run` — TopUpVenue.s.sol:102

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at TopUpVenue.s.sol:102; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `external.recover (TopUpVenue.s.sol:120), UNTRUSTED, out-of-cluster`
- Observations: none
