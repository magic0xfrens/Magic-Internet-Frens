# Function graph — `deploy`

Current source-derived semantic map: **71 nodes** across **14 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `deploy/DeployCauldron.s.sol` | 125 |
| `deploy/DeployLaunchSniper.s.sol` | 62 |
| `deploy/DeployLaunchpad.s.sol` | 1031 |
| `deploy/DeployMigrationVesting.s.sol` | 121 |
| `deploy/DeployPerp.s.sol` | 267 |
| `deploy/DeployQuoteAssets.s.sol` | 66 |
| `deploy/DeployRenderer.s.sol` | 91 |
| `deploy/DeployRotationStack.s.sol` | 446 |
| `deploy/DeployV4Core.s.sol` | 95 |
| `deploy/FixFactoryWiring.s.sol` | 73 |
| `deploy/SellVolume.s.sol` | 58 |
| `deploy/SnipeBuy.s.sol` | 111 |
| `deploy/SwapVolume.s.sol` | 83 |
| `deploy/TopUpVenue.s.sol` | 126 |


## `DeployCauldron (declared in DeployCauldron.s.sol)`

### `_hookFlags/function` — DeployCauldron.s.sol:45

- Signature: `function _hookFlags() internal pure returns (uint160)`
- Authority: internal (callers: run)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure: the hook permission bits the CREATE2 salt is mined for, the full set the hook declares including the before-swap delta bits (`BEFORE_SWAP_RETURNS_DELTA_FLAG` DeployCauldron.s.sol:50), so the mined address matches what the pool manager validates.
- Edges: none
- Observations: none

### `run/function` — DeployCauldron.s.sol:55

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority is whichever key the operator configures
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: Broadcasts the genesis summon with GENESIS_ETH of native from the configured key (`summon` DeployCauldron.s.sol:120).
- Reachability: Minimal local stack: mines the hook salt for the declared flags (`_hookFlags` DeployCauldron.s.sol:65), deploys hook, registry with an instant emergency delay and the redemption facet, wires them, and summons generation 1. The hook address is checked against the mined one (`hookAddr` DeployCauldron.s.sol:93).
- Edges: `DeployCauldron._hookFlags (DeployCauldron.s.sol:65), TRUSTED, in-cluster`; `HookMiner.find (DeployCauldron.s.sol:75), TRUSTED, out-of-cluster`; `CauldronRegistry.setRedemptionExt (DeployCauldron.s.sol:107), TRUSTED, out-of-cluster`; `CauldronHook.setRegistry (DeployCauldron.s.sol:111), TRUSTED, out-of-cluster`; `CauldronHook.setOpener (DeployCauldron.s.sol:116), TRUSTED, out-of-cluster`; `CauldronHook.setTaxExempt (DeployCauldron.s.sol:117), TRUSTED, out-of-cluster`; `CauldronRegistry.summon (DeployCauldron.s.sol:120), TRUSTED, out-of-cluster`
- Observations: none


## `IHookExempt (declared in DeployLaunchSniper.s.sol)`

### `setTaxExempt/function` — DeployLaunchSniper.s.sol:8

- Signature: `function setTaxExempt(address who, bool exempt) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setTaxExempt` is declared at DeployLaunchSniper.s.sol:8; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `isOpener/function` — DeployLaunchSniper.s.sol:9

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

### `setFinalizer/function` — DeployLaunchSniper.s.sol:13

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

### `run/function` — DeployLaunchSniper.s.sol:28

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployLaunchSniper.s.sol:28; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `IHookExempt.isOpener (DeployLaunchSniper.s.sol:44), UNTRUSTED, out-of-cluster`; `IHookExempt.setTaxExempt (DeployLaunchSniper.s.sol:52), UNTRUSTED, out-of-cluster`; `IPresaleFinalizer.setFinalizer (DeployLaunchSniper.s.sol:55), UNTRUSTED, out-of-cluster`; `LaunchSniper.launch (DeployLaunchSniper.s.sol:60), UNTRUSTED, out-of-cluster`
- Observations: none


## `IOwnable (declared in DeployLaunchpad.s.sol)`

### `transferOwnership/function` — DeployLaunchpad.s.sol:36

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

### `run/function` — DeployLaunchpad.s.sol:114

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority is whichever key the operator configures
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Production launch script. With DEPLOY_QUOTES it validates the whole quote stack before the first broadcast (`_preflightQuoteStack` DeployLaunchpad.s.sol:121), so a bad feed cannot leave a half-deployed stack. Presale price defaults to 0.1111 ether and is overridable (`PRESALE_PRICE` DeployLaunchpad.s.sol:142); an optional frenlist root and setter are applied at the end (`setDiscountRoot` DeployLaunchpad.s.sol:677). A nonzero emergency delay is mandatory (`emergencyDelay` DeployLaunchpad.s.sol:223). When the script deploys its own oracle, a separately supplied oracle is refused so one protocol is never priced by two oracles (`quoteOracle` DeployLaunchpad.s.sol:314).
- Edges: `DeployLaunchpad._preflightQuoteStack (DeployLaunchpad.s.sol:121), TRUSTED, in-cluster`; `CauldronRegistry.setRedemptionExt (DeployLaunchpad.s.sol:232), TRUSTED, out-of-cluster`; `CauldronHook.setRegistry (DeployLaunchpad.s.sol:278), TRUSTED, out-of-cluster`; `DeployLaunchpad._deployQuoteOracle (DeployLaunchpad.s.sol:314), TRUSTED, in-cluster`; `MiFrensDividend.setRegistry (DeployLaunchpad.s.sol:408), TRUSTED, out-of-cluster`; `DeployLaunchpad._deployRotationStack (DeployLaunchpad.s.sol:591), TRUSTED, in-cluster`; `MiFrensGenesis.setRegistry (DeployLaunchpad.s.sol:669), TRUSTED, out-of-cluster`; `MiFrensGenesis.setDiscountRoot (DeployLaunchpad.s.sol:677), TRUSTED, out-of-cluster`; `MiFrensGenesis.setDiscountSetter (DeployLaunchpad.s.sol:678), TRUSTED, out-of-cluster`
- Observations: none

### `_preflightQuoteStack/function` — DeployLaunchpad.s.sol:738

- Signature: `function _preflightQuoteStack() internal view returns (bool enabled)`
- Authority: internal (callers: run)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pre-broadcast gate for DEPLOY_QUOTES: mock quotes are Sepolia-only (`MockQuotesSepoliaOnly` DeployLaunchpad.s.sol:741), and every feed the run will configure must be usable now with the same heartbeat and bounds the oracle will get (`_requireUsableFeed` DeployLaunchpad.s.sol:744).
- Edges: `DeployLaunchpad._requireUsableFeed (DeployLaunchpad.s.sol:744), TRUSTED, in-cluster`; `DeployLaunchpad._requireUsableFeed (DeployLaunchpad.s.sol:752), TRUSTED, in-cluster`
- Observations: none

### `_requireUsableFeed/function` — DeployLaunchpad.s.sol:764

- Signature: `function _requireUsableFeed( address feed, uint256 heartbeatRaw, uint256 minUsd, uint256 maxUsd ) internal view`
- Authority: internal (callers: _preflightQuoteStack)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Mirrors the oracle's acceptance rules off-chain: heartbeat must fit uint32 (`InvalidHeartbeat` DeployLaunchpad.s.sol:768), the feed must have code, return a full round (`ret` DeployLaunchpad.s.sol:776) with a positive, fresh, non-future answer, and decimals; the scaled per-whole price must be nonzero, representable and inside the bounds (`perWhole` DeployLaunchpad.s.sol:798).
- Edges: none
- Observations: none

### `_deployQuoteOracle/function` — DeployLaunchpad.s.sol:807

- Signature: `function _deployQuoteOracle(address deployer) internal returns (QuoteOracle oracle)`
- Authority: internal (callers: run)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Deploys the one QuoteOracle the protocol uses, before the registry wiring that needs it. Native is pegged or fed from the configured feed with bounds (`setBounds` DeployLaunchpad.s.sol:845); a fed native price must read nonzero in the same broadcast (`usdPerRawUnit` DeployLaunchpad.s.sol:850).
- Edges: `QuoteOracle.setPegged (DeployLaunchpad.s.sol:840), TRUSTED, out-of-cluster`; `QuoteOracle.setFeed (DeployLaunchpad.s.sol:844), TRUSTED, out-of-cluster`; `QuoteOracle.setBounds (DeployLaunchpad.s.sol:845), TRUSTED, out-of-cluster`; `QuoteOracle.usdPerRawUnit (DeployLaunchpad.s.sol:850), TRUSTED, out-of-cluster`
- Observations: none

### `_deployRotationStack/function` — DeployLaunchpad.s.sol:865

- Signature: `function _deployRotationStack( CauldronRegistry registry, QuoteRotator rotator, address poolManager, address positionManager, QuoteOracle oracle ) internal`
- Authority: internal (callers: run)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: Seeds the ETH/USDG rotation venue with VENUE_ETH of native plus freshly minted mock USDG (`seed` DeployLaunchpad.s.sol:987), and optionally a concentrated band (`seedBand` DeployLaunchpad.s.sol:996).
- Reachability: Takes the already-deployed oracle instead of creating its own. Places mock USDG below the quote-address watermark (`usdg` DeployLaunchpad.s.sol:882), prices it pegged or by feed (`setPegged` DeployLaunchpad.s.sol:899), allowlists it, sizes the USDG leg of the venue from the oracle unless given (`venueUsdg` DeployLaunchpad.s.sol:953), seeds the venue and curates exactly that pool in the rotator (`setVenue` DeployLaunchpad.s.sol:1004).
- Edges: `QuoteOracle.setPegged (DeployLaunchpad.s.sol:899), TRUSTED, out-of-cluster`; `QuoteOracle.setFeed (DeployLaunchpad.s.sol:903), TRUSTED, out-of-cluster`; `QuoteRotator.setArbParams (DeployLaunchpad.s.sol:906), TRUSTED, out-of-cluster`; `QuoteRotator.setRotationSlipBps (DeployLaunchpad.s.sol:919), TRUSTED, out-of-cluster`; `CauldronRegistry.setAllowedQuote (DeployLaunchpad.s.sol:922), TRUSTED, out-of-cluster`; `QuoteOracle.usdPerRawUnit (DeployLaunchpad.s.sol:946), TRUSTED, out-of-cluster`; `MockQuoteToken.mint (DeployLaunchpad.s.sol:986), TRUSTED, out-of-cluster`; `VenueSeeder.seed (DeployLaunchpad.s.sol:987), TRUSTED, out-of-cluster`; `VenueSeeder.seedBand (DeployLaunchpad.s.sol:996), TRUSTED, out-of-cluster`; `QuoteRotator.setVenue (DeployLaunchpad.s.sol:1004), TRUSTED, out-of-cluster`
- Observations: none


## `IRegistryGate (declared in DeployMigrationVesting.s.sol)`

### `emergencyAdmin/function` — DeployMigrationVesting.s.sol:9

- Signature: `function emergencyAdmin() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `emergencyAdmin` is declared at DeployMigrationVesting.s.sol:9; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `emergencyDelay/function` — DeployMigrationVesting.s.sol:10

- Signature: `function emergencyDelay() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `emergencyDelay` is declared at DeployMigrationVesting.s.sol:10; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `emergencyReadyAt/function` — DeployMigrationVesting.s.sol:11

- Signature: `function emergencyReadyAt() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: the script reads when the registry's emergency arm matures before trying to set the claim gate (`emergencyReadyAt` DeployMigrationVesting.s.sol:95).
- Edges: none
- Observations: none

### `claimGate/function` — DeployMigrationVesting.s.sol:12

- Signature: `function claimGate() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `claimGate` is declared at DeployMigrationVesting.s.sol:12; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `setClaimGate/function` — DeployMigrationVesting.s.sol:13

- Signature: `function setClaimGate(address gate) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setClaimGate` is declared at DeployMigrationVesting.s.sol:13; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IHookPerp (declared in DeployMigrationVesting.s.sol)`

### `perpEngine/function` — DeployMigrationVesting.s.sol:15

- Signature: `function perpEngine() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `perpEngine` is declared at DeployMigrationVesting.s.sol:15; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IEngineVault (declared in DeployMigrationVesting.s.sol)`

### `vault/function` — DeployMigrationVesting.s.sol:16

- Signature: `function vault() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `vault` is declared at DeployMigrationVesting.s.sol:16; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `DeployMigrationVesting (declared in DeployMigrationVesting.s.sol)`

### `run/function` — DeployMigrationVesting.s.sol:55

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority is whichever key the operator configures
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Deploys the staker oracle and the vesting contract. With ENFORCE it sets the registry claim gate only when the broadcaster is the emergency admin and an emergency arm has matured (`matured` DeployMigrationVesting.s.sol:97), because setting the gate consumes the arm; otherwise it prints the arm, wait and set steps instead of reverting mid-broadcast.
- Edges: `IHookPerp.perpEngine (DeployMigrationVesting.s.sol:69), TRUSTED, in-cluster`; `IEngineVault.vault (DeployMigrationVesting.s.sol:71), TRUSTED, in-cluster`; `IRegistryGate.emergencyAdmin (DeployMigrationVesting.s.sol:94), TRUSTED, in-cluster`; `IRegistryGate.emergencyReadyAt (DeployMigrationVesting.s.sol:95), TRUSTED, in-cluster`; `IRegistryGate.setClaimGate (DeployMigrationVesting.s.sol:98), TRUSTED, in-cluster`
- Observations: none


## `IHookWire (declared in DeployPerp.s.sol)`

### `setPerpEngine/function` — DeployPerp.s.sol:14

- Signature: `function setPerpEngine(address engine) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setPerpEngine` is declared at DeployPerp.s.sol:14; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `collection/function` — DeployPerp.s.sol:15

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

### `liquidatorMinter/function` — DeployPerp.s.sol:18

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

### `depositEth/function` — DeployPerp.s.sol:21

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

### `transferOwnership/function` — DeployPerp.s.sol:24

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

### `currentGeneration/function` — DeployPerp.s.sol:27

- Signature: `function currentGeneration() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `currentGeneration` is declared at DeployPerp.s.sol:27; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `generationPoolKey/function` — DeployPerp.s.sol:28

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

### `run/function` — DeployPerp.s.sol:65

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployPerp.s.sol:65; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `IHookWire.collection (DeployPerp.s.sol:92), UNTRUSTED, out-of-cluster`; `IHookWire.setPerpEngine (DeployPerp.s.sol:94), UNTRUSTED, out-of-cluster`; `PerpEngine.setVault (DeployPerp.s.sol:100), UNTRUSTED, out-of-cluster`; `PerpEngine.setVaultLimits (DeployPerp.s.sol:105), UNTRUSTED, out-of-cluster`; `PerpEngine.setRisk (DeployPerp.s.sol:119), UNTRUSTED, out-of-cluster`; `PerpEngine.fundInsurance (DeployPerp.s.sol:132), UNTRUSTED, out-of-cluster`; `PerpEngine.setGuards (DeployPerp.s.sol:158), UNTRUSTED, out-of-cluster`; `PerpEngine.setRouting (DeployPerp.s.sol:178), UNTRUSTED, out-of-cluster`; `PerpEngine.blocksVolumeLink (DeployPerp.s.sol:187), TRUSTED, out-of-cluster`; `IRegistryGen.currentGeneration (DeployPerp.s.sol:208), UNTRUSTED, out-of-cluster`; `IRegistryGen.generationPoolKey (DeployPerp.s.sol:210), UNTRUSTED, out-of-cluster`; `PerpMarkSource.setPrimary (DeployPerp.s.sol:216), UNTRUSTED, out-of-cluster`; `PerpEngine.setRouting (DeployPerp.s.sol:228), UNTRUSTED, out-of-cluster`; `IPerpVaultDeposit.depositEth (DeployPerp.s.sol:235), UNTRUSTED, out-of-cluster`; `IHookWire.setPerpEngine (DeployPerp.s.sol:246), UNTRUSTED, out-of-cluster`; `IOwnable.transferOwnership (DeployPerp.s.sol:247), UNTRUSTED, out-of-cluster`; `IOwnable.transferOwnership (DeployPerp.s.sol:248), UNTRUSTED, out-of-cluster`; `IOwnable.transferOwnership (DeployPerp.s.sol:254), UNTRUSTED, out-of-cluster`; `IHookWire.collection (DeployPerp.s.sol:261), UNTRUSTED, out-of-cluster`; `ICollLiq.liquidatorMinter (DeployPerp.s.sol:264), UNTRUSTED, out-of-cluster`
- Observations: none


## `IRegistryQuoteAdmin (declared in DeployQuoteAssets.s.sol)`

### `setAllowedQuote/function` — DeployQuoteAssets.s.sol:10

- Signature: `function setAllowedQuote(address quote, bool allowed, uint256 scale) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setAllowedQuote` is declared at DeployQuoteAssets.s.sol:10; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `allowedQuote/function` — DeployQuoteAssets.s.sol:11

- Signature: `function allowedQuote(address quote) external view returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `allowedQuote` is declared at DeployQuoteAssets.s.sol:11; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `owner/function` — DeployQuoteAssets.s.sol:12

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

### `run/function` — DeployQuoteAssets.s.sol:29

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployQuoteAssets.s.sol:29; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `IRegistryQuoteAdmin.owner (DeployQuoteAssets.s.sol:45), UNTRUSTED, out-of-cluster`; `IRegistryQuoteAdmin.setAllowedQuote (DeployQuoteAssets.s.sol:47), UNTRUSTED, out-of-cluster`; `IRegistryQuoteAdmin.setAllowedQuote (DeployQuoteAssets.s.sol:48), UNTRUSTED, out-of-cluster`
- Observations: none


## `IPegRenderer (declared in DeployRenderer.s.sol)`

### `setRenderer/function` — DeployRenderer.s.sol:9

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

### `run/function` — DeployRenderer.s.sol:38

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at DeployRenderer.s.sol:38; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `TraitStorage.storeTraits (DeployRenderer.s.sol:73), UNTRUSTED, out-of-cluster`; `IPegRenderer.setRenderer (DeployRenderer.s.sol:79), UNTRUSTED, out-of-cluster`; `TraitStorage.freeze (DeployRenderer.s.sol:85), UNTRUSTED, out-of-cluster`
- Observations: none


## `IPermit2Approve (declared in DeployRotationStack.s.sol)`

### `approve/function` — DeployRotationStack.s.sol:26

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

### `setAllowedQuote/function` — DeployRotationStack.s.sol:30

- Signature: `function setAllowedQuote(address quote, bool allowed, uint256 scale) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setAllowedQuote` is declared at DeployRotationStack.s.sol:30; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `allowedQuote/function` — DeployRotationStack.s.sol:31

- Signature: `function allowedQuote(address quote) external view returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `allowedQuote` is declared at DeployRotationStack.s.sol:31; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `setRotationWiring/function` — DeployRotationStack.s.sol:32

- Signature: `function setRotationWiring(address rotator, address governor) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setRotationWiring` is declared at DeployRotationStack.s.sol:32; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `owner/function` — DeployRotationStack.s.sol:33

- Signature: `function owner() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `owner` is declared at DeployRotationStack.s.sol:33; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `mifrens/function` — DeployRotationStack.s.sol:34

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

### `run/function` — DeployRotationStack.s.sol:111

- Signature: `function run() external`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `address me = pk != 0 ? vm.addr(pk) : msg.sender; (DeployRotationStack.s.sol:118)`
- Reads: none
- Writes: none
- Value: transfers token or native value through `transfer` (DeployRotationStack.s.sol:211)
- Reachability: `run` is declared at DeployRotationStack.s.sol:111; caller satisfying the in-body msg.sender check.
- Edges: `IRegistryAdmin.owner (DeployRotationStack.s.sol:126), UNTRUSTED, out-of-cluster`; `IRegistryAdmin.mifrens (DeployRotationStack.s.sol:127), UNTRUSTED, out-of-cluster`; `QuoteRotator.setArbParams (DeployRotationStack.s.sol:182), UNTRUSTED, out-of-cluster`; `QuoteOracle.setFeed (DeployRotationStack.s.sol:189), UNTRUSTED, out-of-cluster`; `QuoteOracle.setFeed (DeployRotationStack.s.sol:190), UNTRUSTED, out-of-cluster`; `QuoteOracle.transferOwnership (DeployRotationStack.s.sol:195), UNTRUSTED, out-of-cluster`; `MockQuoteToken.mint (DeployRotationStack.s.sol:201), UNTRUSTED, out-of-cluster`; `VenueSeeder.seed (DeployRotationStack.s.sol:212), UNTRUSTED, out-of-cluster`; `QuoteRotator.setVenue (DeployRotationStack.s.sol:219), UNTRUSTED, out-of-cluster`; `IRegistryAdmin.setAllowedQuote (DeployRotationStack.s.sol:223), UNTRUSTED, out-of-cluster`; `IRegistryAdmin.setRotationWiring (DeployRotationStack.s.sol:227), UNTRUSTED, out-of-cluster`
- Observations: none


## `VenueSeeder (declared in DeployRotationStack.s.sol)`

### `constructor/constructor` — DeployRotationStack.s.sol:269

- Signature: `constructor()`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `constructor` is declared at DeployRotationStack.s.sol:269; deployer.
- Edges: none
- Observations: none

### `seed/function` — DeployRotationStack.s.sol:271

- Signature: `function seed( IPoolManager poolManager, IPositionManagerOps posm, address usdg, uint256 ethAmount, uint256 usdgAmount, int24 spacing, uint24 fee ) external payable returns (uint256)`
- Authority: the seeder's deployer
- Gate evidence: `require(msg.sender == deployer, "only deployer"); (DeployRotationStack.s.sol:280)`
- Reads: `deployer (line 280, immutable)`; `positionId (line 281)`
- Writes: `positionId (line 283)`
- Value: Mints a full-range ETH/USDG position with the attached native and the seeder's USDG (`openOrAddPair` DeployRotationStack.s.sol:283).
- Reachability: Deployer-only. Refuses while a previous position is still held (`positionId` DeployRotationStack.s.sol:281) so a re-seed cannot orphan it; recover first.
- Edges: `PoolOps.openOrAddPair (DeployRotationStack.s.sol:283), TRUSTED, library`
- Observations: none

### `seedBand/function` — DeployRotationStack.s.sol:330

- Signature: `function seedBand( IPoolManager poolManager, IPositionManagerOps posm, address usdg, uint256 ethAmount, uint256 usdgAmount, int24 spacing, uint24 fee, uint16 bandBps ) external payable returns (uint256)`
- Authority: the seeder's deployer
- Gate evidence: `require(msg.sender == deployer, "only deployer"); (DeployRotationStack.s.sol:340)`
- Reads: `deployer (line 340, immutable)`; `positionId (line 341)`
- Writes: `positionId (line 395)`
- Value: Mints a concentrated ETH/USDG band with the attached native and the seeder's USDG through the position manager (`modifyLiquidities` DeployRotationStack.s.sol:396).
- Reachability: Deployer-only; refuses while a position is held (`positionId` DeployRotationStack.s.sol:341). Needs an initialized pool, converts the half-width from bps of price to ticks as roughly one tick per bp (`delta` DeployRotationStack.s.sol:364), keeps the band straddling the current tick and nonzero-liquidity, then mints it to the seeder.
- Edges: `StateLibrary.getSlot0 (DeployRotationStack.s.sol:355), TRUSTED, library`; `LiquidityAmounts.getLiquidityForAmounts (DeployRotationStack.s.sol:373), TRUSTED, library`; `IERC20.approve (DeployRotationStack.s.sol:388), TRUSTED, out-of-cluster`; `IPositionManagerOps.nextTokenId (DeployRotationStack.s.sol:395), TRUSTED, out-of-cluster`; `IPositionManagerOps.modifyLiquidities (DeployRotationStack.s.sol:396), TRUSTED, out-of-cluster`
- Observations: none

### `recover/function` — DeployRotationStack.s.sol:423

- Signature: `function recover(IPositionManagerOps posm, PoolKey memory key, address usdg) external returns (uint256 ethOut, uint256 usdgOut)`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `require(msg.sender == deployer, "only deployer"); (DeployRotationStack.s.sol:427)`
- Reads: none
- Writes: none
- Value: transfers token or native value through `transfer` (DeployRotationStack.s.sol:437)
- Reachability: `recover` is declared at DeployRotationStack.s.sol:423; caller satisfying the in-body msg.sender check.
- Edges: `PoolOps.removeAll (DeployRotationStack.s.sol:429), TRUSTED, out-of-cluster`; `MockQuoteToken.balanceOf (DeployRotationStack.s.sol:436), UNTRUSTED, out-of-cluster`
- Observations: none

### `receive/receive` — DeployRotationStack.s.sol:445

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `receive` is declared at DeployRotationStack.s.sol:445; anyone.
- Edges: none
- Observations: none


## `DeployV4Core (declared in DeployV4Core.s.sol)`

### `run/function` — DeployV4Core.s.sol:55

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

### `setFactory/function` — FixFactoryWiring.s.sol:8

- Signature: `function setFactory(address f) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setFactory` is declared at FixFactoryWiring.s.sol:8; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `owner/function` — FixFactoryWiring.s.sol:9

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

### `schedule/function` — FixFactoryWiring.s.sol:13

- Signature: `function schedule(address target, uint256 value, bytes calldata data, bytes32 pred, bytes32 salt, uint256 delay) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `schedule` is declared at FixFactoryWiring.s.sol:13; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `execute/function` — FixFactoryWiring.s.sol:14

- Signature: `function execute(address target, uint256 value, bytes calldata data, bytes32 pred, bytes32 salt) external payable`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `execute` is declared at FixFactoryWiring.s.sol:14; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `getMinDelay/function` — FixFactoryWiring.s.sol:15

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

### `run/function` — FixFactoryWiring.s.sol:33

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority is whichever key the operator configures
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Two-phase timelocked factory repoint. The schedule run deploys and wires a new factory and schedules the registry call (`schedule` FixFactoryWiring.s.sol:66); the execute run reuses that factory from FACTORY (`factory` FixFactoryWiring.s.sol:50) so the executed calldata matches the scheduled operation instead of naming a second, fresh factory.
- Edges: `CauldronFactory.setLiquidatorRenderer (FixFactoryWiring.s.sol:53), TRUSTED, out-of-cluster`; `ITimelock.getMinDelay (FixFactoryWiring.s.sol:58), TRUSTED, in-cluster`; `ITimelock.execute (FixFactoryWiring.s.sol:63), TRUSTED, in-cluster`; `ITimelock.schedule (FixFactoryWiring.s.sol:66), TRUSTED, in-cluster`
- Observations: none


## `IERC20Min (declared in SellVolume.s.sol)`

### `approve/function` — SellVolume.s.sol:14

- Signature: `function approve(address, uint256) external returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `approve` is declared at SellVolume.s.sol:14; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `balanceOf/function` — SellVolume.s.sol:15

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

### `run/function` — SellVolume.s.sol:24

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at SellVolume.s.sol:24; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `IERC20Min.approve (SellVolume.s.sol:42), UNTRUSTED, out-of-cluster`
- Observations: none


## `ISeederView (declared in SnipeBuy.s.sol)`

### `deployedWad/function` — SnipeBuy.s.sol:16

- Signature: `function deployedWad() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `deployedWad` is declared at SnipeBuy.s.sol:16; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `seeding/function` — SnipeBuy.s.sol:17

- Signature: `function seeding() external view returns (bool)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `seeding` is declared at SnipeBuy.s.sol:17; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `isComplete/function` — SnipeBuy.s.sol:18

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

### `balanceOf/function` — SnipeBuy.s.sol:20

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

### `run/function` — SnipeBuy.s.sol:50

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at SnipeBuy.s.sol:50; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `ISeederView.deployedWad (SnipeBuy.s.sol:72), UNTRUSTED, out-of-cluster`; `ISeederView.isComplete (SnipeBuy.s.sol:73), UNTRUSTED, out-of-cluster`; `ISeederView.seeding (SnipeBuy.s.sol:74), UNTRUSTED, out-of-cluster`; `ISeederView.isComplete (SnipeBuy.s.sol:74), UNTRUSTED, out-of-cluster`; `IERC20View.balanceOf (SnipeBuy.s.sol:81), UNTRUSTED, out-of-cluster`; `IERC20View.balanceOf (SnipeBuy.s.sol:94), UNTRUSTED, out-of-cluster`
- Observations: none

### `_u/function` — SnipeBuy.s.sol:110

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

### `crystalsReady/function` — SwapVolume.s.sol:18

- Signature: `function crystalsReady(address player) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `crystalsReady` is declared at SwapVolume.s.sol:18; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `getVolume24h/function` — SwapVolume.s.sol:19

- Signature: `function getVolume24h(bytes32 id) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `getVolume24h` is declared at SwapVolume.s.sol:19; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `nftCredit/function` — SwapVolume.s.sol:20

- Signature: `function nftCredit(uint256 epoch, address player) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `nftCredit` is declared at SwapVolume.s.sol:20; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `creditEpoch/function` — SwapVolume.s.sol:21

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

### `totalMinted/function` — SwapVolume.s.sol:24

- Signature: `function totalMinted() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `totalMinted` is declared at SwapVolume.s.sol:24; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `balanceOf/function` — SwapVolume.s.sol:25

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

### `run/function` — SwapVolume.s.sol:35

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at SwapVolume.s.sol:35; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `IHookView.crystalsReady (SwapVolume.s.sol:77), UNTRUSTED, out-of-cluster`; `ICollView.totalMinted (SwapVolume.s.sol:80), UNTRUSTED, out-of-cluster`; `ICollView.balanceOf (SwapVolume.s.sol:81), UNTRUSTED, out-of-cluster`
- Observations: none


## `TopUpVenue (declared in TopUpVenue.s.sol)`

### `run/function` — TopUpVenue.s.sol:55

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at TopUpVenue.s.sol:55; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `MockQuoteToken.mint (TopUpVenue.s.sol:73), UNTRUSTED, out-of-cluster`; `VenueSeeder.seed (TopUpVenue.s.sol:74), UNTRUSTED, out-of-cluster`; `QuoteRotator.setRotationSlipBps (TopUpVenue.s.sol:83), UNTRUSTED, out-of-cluster`
- Observations: none


## `RecoverVenue (declared in TopUpVenue.s.sol)`

### `run/function` — TopUpVenue.s.sol:102

- Signature: `function run() external`
- Authority: off-chain script invoker; broadcast authority comes from configured key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `run` is declared at TopUpVenue.s.sol:102; off-chain script invoker; broadcast authority comes from configured key.
- Edges: `VenueSeeder.recover (TopUpVenue.s.sol:120), UNTRUSTED, out-of-cluster`
- Observations: none
