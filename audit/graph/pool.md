# Function graph — `pool`

Current source-derived semantic map: **78 nodes** across **2 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `cauldron/CauldronBase.sol` | 589 |
| `cauldron/PoolOps.sol` | 1663 |


## `ICauldronFactory (declared in CauldronBase.sol)`

### `deployBrew/function` — CauldronBase.sol:25

- Signature: `function deployBrew(Config calldata c) external returns (address collection, address vault)`
- Authority: anyone (declaration only; the implementation CauldronFactory.deployBrew carries no caller check)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration consumed through the `factory` storage slot (CauldronBase.sol:252), which the registry calls at `deployBrew` (CauldronRegistry.sol:1229) inside `_deployCollection` (CauldronRegistry.sol:1143) — reached from `summon` (CauldronRegistry.sol:681) via `_deployCollection` (CauldronRegistry.sol:794) and from `relaunch` (CauldronRegistry.sol:812) via `_deployCollection` (CauldronRegistry.sol:1143). The implementation `deployBrew` (CauldronFactory.sol:63) has no sender check, so a third party may deploy an unrelated brew from it; only the registry-held `factory` (CauldronBase.sol:252) pointer decides which deployment the protocol adopts.
- Edges: none
- Observations: none

### `deployVault/function` — CauldronBase.sol:26

- Signature: `function deployVault(address collection, address registry, uint256 floorOffset) external returns (address vault)`
- Authority: anyone (declaration only; the implementation CauldronFactory.deployVault carries no caller check)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called by the registry at `deployVault` (CauldronRegistry.sol:1267) inside `_continueMiFrens` (CauldronRegistry.sol:1262), which `relaunch` reaches at `_continueMiFrens` (CauldronRegistry.sol:1141) when the iteration continues the MiFrens collection. The implementation `deployVault` (CauldronFactory.sol:105) is ungated; the `registry` argument, not `msg.sender`, fixes who may later close the vault.
- Edges: none
- Observations: none


## `IMiFrensContinuable (declared in CauldronBase.sol)`

### `setMinter/function` — CauldronBase.sol:32

- Signature: `function setMinter(address minter) external`
- Authority: deployer or registry (gate held by the implementation)
- Gate evidence: `onlyDeployerOrRegistry (MiFrensGenesis.sol:504)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Reached from `setMinter` (CauldronRegistry.sol:1271) in `_continueMiFrens` (CauldronRegistry.sol:1262), itself called from `relaunch` at `_continueMiFrens` (CauldronRegistry.sol:1141); the registry passes the hook as the new minter. The gate sits on the collection side: `setMinter` (MiFrensGenesis.sol:512).
- Edges: none
- Observations: none

### `setVault/function` — CauldronBase.sol:33

- Signature: `function setVault(address vault) external`
- Authority: deployer or registry (gate held by the implementation)
- Gate evidence: `onlyDeployerOrRegistry (MiFrensGenesis.sol:504)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Reached from `setVault` (CauldronRegistry.sol:1247) in `_continueMiFrens` (CauldronRegistry.sol:1262) right after the vault is deployed at `deployVault` (CauldronRegistry.sol:1267). Two different implementations answer this selector: `setVault` (MiFrensGenesis.sol:517) is deployer-or-registry gated, while the per-brew `setVault` (CauldronCollection.sol:331) accepts the configurator or the deployer.
- Edges: none
- Observations: none

### `totalMinted/function` — CauldronBase.sol:34

- Signature: `function totalMinted() external view returns (uint256)`
- Authority: anyone (view on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: no call through `IMiFrensContinuable` (CauldronBase.sol:31) reaches it from the registry or the facet — DERIVED, grep for `.totalMinted()` in CauldronRegistry.sol and cauldron/RedemptionExt.sol returns no call site. The live supply reads the protocol actually makes go through the separately declared `IColMinted` (PoolOps.sol:51), called at `totalMinted` (PoolOps.sol:1467), `totalMinted` (PoolOps.sol:1467) and `totalMinted` (PoolOps.sol:1467). The implementation is `totalMinted` (MiFrensGenesis.sol:494).
- Edges: none
- Observations: none

### `custodyTransfer/function` — CauldronBase.sol:38

- Signature: `function custodyTransfer(address from, address to, uint256 tokenId) external`
- Authority: registry (gate held by the implementation)
- Gate evidence: `if (msg.sender != address(registry)) revert NotAuthorized(); (MiFrensGenesis.sol:595)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called under delegatecall from the facet at `custodyTransfer` (RedemptionExt.sol:99) when an OG fren is redeemed into the treasury, and at `custodyTransfer` (RedemptionExt.sol:137) when a treasury fren is bought back out; because the facet is delegatecalled, `address(this)` is the registry, which is what the implementation's gate `custodyTransfer` (MiFrensGenesis.sol:593) requires. The per-brew collection implements the same selector with a deployer gate at `custodyTransfer` (CauldronCollection.sol:454).
- Edges: none
- Observations: none

### `everMoved/function` — CauldronBase.sol:41

- Signature: `function everMoved(uint256 tokenId) external view returns (bool)`
- Authority: anyone (public mapping getter on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: No caller in the registry or the facet reaches this declaration — DERIVED, grep for `everMoved` across the source tree hits only the declaration, the implementation `everMoved` (MiFrensGenesis.sol:585), its writer `everMoved` (MiFrensGenesis.sol:969), a separate declaration `everMoved` (MiFrensDividend.sol:12) and its one consumer `everMoved` (MiFrensDividend.sol:473).
- Edges: none
- Observations: comment at `everMoved` (CauldronBase.sol:41) says the flag is `used to gate the paid re-enchant (original OGs are grandfathered free)`; the only code that gates on it is `everMoved` (MiFrensDividend.sol:473), which reaches it through its own interface declaration `everMoved` (MiFrensDividend.sol:12), not through this one


## `IVaultClose (declared in CauldronBase.sol)`

### `close/function` — CauldronBase.sol:45

- Signature: `function close() external returns (uint256 swept)`
- Authority: registry (gate held by the implementation)
- Gate evidence: `if (msg.sender != registry) revert NotRegistry(); (CauldronVault.sol:199)`
- Reads: none
- Writes: none
- Value: sends native to the registry from the vault at `close` (CauldronVault.sol:104)
- Reachability: This declaration has no call site: it is imported by the registry at `IVaultClose` (CauldronRegistry.sol:27) and never used — DERIVED, grep for `IVaultClose` finds only the declaration and that import. The dying vault is actually closed through the duplicate declaration `IVaultCloseOps` (PoolOps.sol:75), called inside a try/catch at `close` (PoolOps.sol:1078) from `seedFunding` (PoolOps.sol:1071).
- Edges: none
- Observations: none


## `IPerpSync (declared in CauldronBase.sol)`

### `syncGeneration/function` — CauldronBase.sol:51

- Signature: `function syncGeneration() external`
- Authority: anyone (the implementation has no sender check)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called best-effort inside a try/catch from `syncGeneration` (CauldronRegistry.sol:1165) in `_perpHousekeep` (CauldronRegistry.sol:1153), which `relaunch` runs twice — `_perpHousekeep` (CauldronRegistry.sol:852) before the old pool is drained and `_perpHousekeep` (CauldronRegistry.sol:1153) after the newborn is seeded — and from the facet at `syncGeneration` (RedemptionExt.sol:599). The implementation `syncGeneration` (PerpEngine.sol:1573) is permissionless but refuses while the book is open at `openCount` (PerpEngine.sol:1506).
- Edges: none
- Observations: none

### `openCount/function` — CauldronBase.sol:55

- Signature: `function openCount() external view returns (uint256)`
- Authority: anyone (public state-variable getter on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: No registry or facet code calls this declaration — DERIVED, grep for `openCount` finds no occurrence in CauldronRegistry.sol or cauldron/RedemptionExt.sol. The open-position count is read instead by the hook through its own declarations, at `openCount` (CauldronHook.sol:1807) and `openCount` (CauldronHook.sol:2091); the state itself is `openCount` (PerpEngine.sol:411).
- Edges: none
- Observations: comment at `relaunch` (CauldronBase.sol:54) says `relaunch` MUST see zero here before it returns; `relaunch` (CauldronRegistry.sol:812) never reads the count — its only perp step is the try/catch `syncGeneration` (CauldronRegistry.sol:1165), whose failure is swallowed, and the zero-open-positions check lives in the hook at `openCount` (CauldronHook.sol:2091)


## `IPerpBook (declared in CauldronBase.sol)`

### `requoteBook/function` — CauldronBase.sol:61

- Signature: `function requoteBook(address rotator) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: when a primary-sourced rotation spends the whole migration mandate, the facet hands the perp engine its book to carry onto the new quote through the given rotator (`requoteBook` RedemptionExt.sol:702).
- Edges: none
- Observations: none


## `ICollectionLedger (declared in CauldronBase.sol)`

### `totalEntitled/function` — CauldronBase.sol:65

- Signature: `function totalEntitled() external view returns (uint256)`
- Authority: anyone (public state-variable getter on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Reached through the `collectionLedger` storage slot (CauldronBase.sol:240), read at `totalEntitled` (CauldronRegistry.sol:1098) inside `relaunch` (CauldronRegistry.sol:812) when the newborn's reserve is sized to cover the legacy entitlement. The implementation is the public counter `totalEntitled` (CollectionLedger.sol:59). PoolOps declares the same selector again at `totalEntitled` (PoolOps.sol:48).
- Edges: none
- Observations: none


## `IPositionManager (declared in CauldronBase.sol)`

### `modifyLiquidities/function` — CauldronBase.sol:73

- Signature: `function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable`
- Authority: anyone (the external v4 PositionManager authorizes per position internally)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native at `modifyLiquidities` (line 73)
- Reachability: The registry stores the PositionManager address in `positionManager` (CauldronBase.sol:315) and writes it in its constructor at `positionManager` (CauldronRegistry.sol:174); every actual call casts that address to the duplicate declaration `IPositionManagerOps` (PoolOps.sol:31) before use — `modifyLiquidities` (PoolOps.sol:832), `modifyLiquidities` (PoolOps.sol:832), `modifyLiquidities` (PoolOps.sol:832), `modifyLiquidities` (PoolOps.sol:880), `modifyLiquidities` (PoolOps.sol:1299), `modifyLiquidities` (PoolOps.sol:1299) and `modifyLiquidities` (PoolOps.sol:1299) — so no call is made through this declaration itself (DERIVED). The registry does use the stored address directly as an ERC721 at `positionManager` (CauldronRegistry.sol:545).
- Edges: none
- Observations: none

### `nextTokenId/function` — CauldronBase.sol:74

- Signature: `function nextTokenId() external view returns (uint256)`
- Authority: anyone (view on the external v4 PositionManager)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Same shape as the sibling declaration: the calls the protocol makes are through `nextTokenId` (PoolOps.sol:827) and `nextTokenId` (PoolOps.sol:827), typed as `IPositionManagerOps` (PoolOps.sol:31); the id is read immediately before the mint so the position NFT the PositionManager is about to issue can be recorded. Nothing calls this declaration (DERIVED).
- Edges: none
- Observations: none

### `getPositionLiquidity/function` — CauldronBase.sol:75

- Signature: `function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity)`
- Authority: anyone (view on the external v4 PositionManager)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Live liquidity is read through the duplicate declaration at `getPositionLiquidity` (PoolOps.sol:985), `getPositionLiquidity` (PoolOps.sol:1284), `getPositionLiquidity` (PoolOps.sol:1284), `getPositionLiquidity` (PoolOps.sol:1284) and `getPositionLiquidity` (PoolOps.sol:1323); nothing calls this declaration (DERIVED). The interface comment at `IPositionManager` (CauldronBase.sol:72) explains the local redeclaration: the v4-periphery interface drags a lower solc pin into this unit.
- Edges: none
- Observations: none


## `CauldronBase`

### `floorPerFren/function` — CauldronBase.sol:461

- Signature: `function floorPerFren() public view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `genesisShares (line 462)`; `treasuryHeldOg (line 471)`; `genesisReserveOutstanding (line 477)`
- Writes: none
- Value: NONE
- Reachability: Public view inherited by both children of this base, so it answers on the registry and, under delegatecall, on the facet against the registry's storage. Returns 0 before summon writes `genesisShares` (line 462). The divisor is the ACTIVE OG count: frens the treasury bought back through redemption are excluded (`treasuryHeldOg` line 471), so redeeming one fren leaves the floor of every other holder unchanged; the result is the outstanding genesis reserve over that count (`genesisReserveOutstanding` line 477).
- Edges: none
- Observations: none

### `_redeemBlocked/function` — CauldronBase.sol:484

- Signature: `function _redeemBlocked() internal view returns (bool)`
- Authority: internal (callers: RedemptionExt.redeemOgFren, RedemptionExt.buyOgFren, CauldronRegistry.recycleCollectionNFT)
- Gate evidence: `UNGATED`
- Reads: `redemptionPaused (line 485)`; `emergencyReadyAt (line 485)`
- Writes: none
- Value: NONE
- Reachability: Internal guard compiled into both children. Reached on the facet at `_redeemBlocked` (RedemptionExt.sol:82) — the first statement of the OG redemption — and on the registry at `_redeemBlocked` (CauldronRegistry.sol:1577) in the collection recycle path. It blocks only while the circuit breaker is on AND no emergency is armed: `emergencyReadyAt` (line 485) being non-zero forces the exit open, which the registry comment at `_redeemBlocked` (CauldronRegistry.sol:391) restates.
- Edges: none
- Observations: none

### `constructor/constructor` — CauldronBase.sol:488

- Signature: `constructor() Ownable(msg.sender)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Abstract base constructor, run as part of whichever child is being deployed: `CauldronRegistry` (CauldronRegistry.sol:63) and the facet `RedemptionExt` (RedemptionExt.sol:63), which declares no constructor of its own. It passes `msg.sender` to the OpenZeppelin Ownable constructor at `Ownable` (line 488), so the owner slot is the deploying account; the registry constructor then writes the rest of the wiring, e.g. `positionManager` (CauldronRegistry.sol:174). The facet's own owner slot is never used at runtime because the facet only ever executes under delegatecall against the registry's storage, as its header states at `delegatecall` (RedemptionExt.sol:24).
- Edges: none
- Observations: none

### `renounceOwnership/function` — CauldronBase.sol:515

- Signature: `function renounceOwnership() public view override onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronBase.sol:515)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Overrides the inherited Ownable entry point on both children (selector renounceOwnership() is present in the compiled CauldronBase method identifiers). It is `view` and unconditionally reverts at `RenounceDisabled` (line 516), so the owner can only ever transfer ownership; the doc block explains the dead-end at `renounceOwnership` (line 515). Because the modifier runs first, a non-owner caller reverts with the Ownable error instead.
- Edges: none
- Observations: none


## `IPositionManagerOps (declared in PoolOps.sol)`

### `modifyLiquidities/function` — PoolOps.sol:32

- Signature: `function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable`
- Authority: anyone (the external v4 PositionManager authorizes each position internally)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native at `modifyLiquidities` (line 32); the only call that forwards value is `modifyLiquidities` (line 32)
- Reachability: The one PositionManager entry point every liquidity routine in this library drives, always on the address the registry stored in `positionManager` (CauldronBase.sol:315) and passed in as `pm`. Call sites: mint of the active position at `modifyLiquidities` (line 32) and `modifyLiquidities` (line 32), mint of the reserve at `modifyLiquidities` (line 32), partial withdrawal at `modifyLiquidities` (line 32), full withdrawal plus burn at `modifyLiquidities` (line 32), reserve claim at `modifyLiquidities` (line 32) and reserve top-up at `modifyLiquidities` (line 32). Because the library is delegatecalled, the PositionManager sees the registry as caller and owner of the position NFTs, as the header states at `delegatecall` (line 121).
- Edges: none
- Observations: none

### `nextTokenId/function` — PoolOps.sol:33

- Signature: `function nextTokenId() external view returns (uint256)`
- Authority: anyone (view on the external v4 PositionManager)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read immediately before each mint so the id the PositionManager is about to issue can be returned to the registry: `nextTokenId` (line 33) for the active position and `nextTokenId` (line 33) for the reserve. The value is recorded by the registry in `generationPositionId` (CauldronBase.sol:204) and `generationReservePositionId` (CauldronBase.sol:207) through `_recordSeed` (CauldronRegistry.sol:1753). It is a prediction, not a receipt: nothing re-reads the minted id after `modifyLiquidities` (line 32) returns (DERIVED).
- Edges: none
- Observations: none

### `getPositionLiquidity/function` — PoolOps.sol:34

- Signature: `function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity)`
- Authority: anyone (view on the external v4 PositionManager)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: The live-liquidity oracle for every withdrawal decision: the share taken by a rotation at `getPositionLiquidity` (line 34), the whole position at death at `getPositionLiquidity` (line 34), the cap on a reserve claim at `getPositionLiquidity` (line 34), and the migration capacity at `getPositionLiquidity` (line 34) and `getPositionLiquidity` (line 34). Zero liquidity is treated as a no-op rather than an error everywhere it is read, e.g. at `liquidity` (line 34).
- Edges: none
- Observations: none


## `ILedgerOps (declared in PoolOps.sol)`

### `redeem/function` — PoolOps.sol:42

- Signature: `function redeem(uint256 gen, uint256 mintedNow) external returns (uint256 payout)`
- Authority: registry (gate held by the implementation)
- Gate evidence: `onlyRegistry (CollectionLedger.sol:148)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called once, at `redeem` (line 42) inside `recycleCollection` (line 1576), which the registry reaches from `recycleCollectionNFT` (CauldronRegistry.sol:1574). The delegatecall makes `msg.sender` at the ledger the registry, which is what `onlyRegistry` (CollectionLedger.sol:148) demands; the returned payout is what the caller then pulls out of the reserve at `claimFromReserve` (line 1419).
- Edges: none
- Observations: none

### `buyback/function` — PoolOps.sol:43

- Signature: `function buyback(uint256 gen, uint256 mintedNow, uint256 paid) external`
- Authority: registry (gate held by the implementation)
- Gate evidence: `onlyRegistry (CollectionLedger.sol:148)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called at `buyback` (line 43) inside `buyCollection` (line 1628), reached from `buyCollectionNFT` (CauldronRegistry.sol:1595). It is credited with `added` — what the reserve position actually absorbed at `addToReserve` (line 1504) — not with the price the buyer paid at `paid` (line 43).
- Edges: none
- Observations: none

### `floorPerNFT/function` — PoolOps.sol:44

- Signature: `function floorPerNFT(uint256 gen, uint256 mintedNow) external view returns (uint256)`
- Authority: anyone (public view on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `floorPerNFT` (line 44) to price a treasury NFT at twice the collection floor, with the live mint count passed in as `mintedNow` (line 44). The implementation is the public view `floorPerNFT` (CollectionLedger.sol:100), which switches to the frozen supply once the generation has crystallized at `crystallized` (CollectionLedger.sol:91).
- Edges: none
- Observations: none

### `credit/function` — PoolOps.sol:45

- Signature: `function credit(uint256 gen, uint256 tokens) external`
- Authority: registry (gate held by the implementation)
- Gate evidence: `onlyRegistry (CollectionLedger.sol:83)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Both branches of the legacy note reach it: the forged share at `credit` (line 45) and the whole amount for a plain brew at `credit` (line 45), from `doLegacyNote` (line 1462). That runs under `materializeLegacy` (line 1493), which the registry calls at `materializeLegacy` (CauldronRegistry.sol:1562) during relaunch and the facet at `materializeLegacy` (RedemptionExt.sol:163) on the permissionless live path.
- Edges: none
- Observations: none

### `crystallize/function` — PoolOps.sol:46

- Signature: `function crystallize(uint256 gen, uint256 mintedAtDeath, uint256 extraEntitled) external`
- Authority: registry (gate held by the implementation)
- Gate evidence: `onlyRegistry (CollectionLedger.sol:148)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called once at `crystallize` (line 46), the last statement of `crystallizeCollection` (line 1518), which only `relaunch` reaches — at `crystallizeCollection` (CauldronRegistry.sol:1094). The implementation refuses a second freeze at `AlreadyCrystallized` (CollectionLedger.sol:193), and this library pre-checks the same flag at `crystallized` (line 47) so the relaunch path returns instead of reverting.
- Edges: none
- Observations: none

### `crystallized/function` — PoolOps.sol:47

- Signature: `function crystallized(uint256 gen) external view returns (bool)`
- Authority: anyone (public mapping getter on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `crystallized` (line 47) as the idempotence guard of `crystallizeCollection` (line 1518); the state is the public mapping `crystallized` (CollectionLedger.sol:55), set at `crystallized` (CollectionLedger.sol:123).
- Edges: none
- Observations: none

### `totalEntitled/function` — PoolOps.sol:48

- Signature: `function totalEntitled() external view returns (uint256)`
- Authority: anyone (public state-variable getter on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declared here but never called through this interface — DERIVED, `totalEntitled` (line 48) is the only occurrence of the name in PoolOps.sol. The registry reads the same counter through its own declaration at `totalEntitled` (CauldronRegistry.sol:1098), sizing the newborn reserve to cover `totalEntitled` (CollectionLedger.sol:59).
- Edges: none
- Observations: none


## `IColMinted (declared in PoolOps.sol)`

### `totalMinted/function` — PoolOps.sol:52

- Signature: `function totalMinted() external view returns (uint256)`
- Authority: anyone (public state-variable getter on the implementations)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Three call sites, all sizing a floor off the LIVE mint count: the forged tranche split at `totalMinted` (line 52), the recycle floor at `totalMinted` (line 52) and the buy price at `totalMinted` (line 52). Implementations are the public counters `totalMinted` (CauldronCollection.sol:67) for a brew collection and `totalMinted` (MiFrensGenesis.sol:494) for the continuation.
- Edges: none
- Observations: none


## `IVaultRedeemedOps (declared in PoolOps.sol)`

### `redeemed/function` — PoolOps.sol:55

- Signature: `function redeemed() external view returns (uint256)`
- Authority: anyone (public state-variable getter on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declared but never called in this library — DERIVED, `redeemed` (line 55) is the only live occurrence of the name in PoolOps.sol. The count it names is the public counter `redeemed` (CauldronVault.sol:48), which the vault itself folds into `outstanding` (CauldronVault.sol:64) — and that is the view this library actually calls, at `outstanding` (line 57).
- Edges: none
- Observations: none

### `outstanding/function` — PoolOps.sol:57

- Signature: `function outstanding() external view returns (uint256)`
- Authority: anyone (public view on the implementation)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `outstanding` (line 57) to freeze the entitled-NFT base when a collection crystallizes, and skipped when the generation has no vault at `vault` (line 56). The implementation subtracts redemptions and the genesis offset inside `outstanding` (CauldronVault.sol:64).
- Edges: none
- Observations: none


## `IHookReserves (declared in PoolOps.sol)`

### `releaseRelaunchETH/function` — PoolOps.sol:65

- Signature: `function releaseRelaunchETH() external returns (uint256)`
- Authority: registry (gate held by the hook)
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1813)`
- Reads: none
- Writes: none
- Value: receives native into the registry from the hook at `releaseRelaunchETH` (line 65)
- Reachability: Called inside a try/catch at `releaseRelaunchETH` (line 65) from `_pullEth` (line 1204), itself reached only from the native branch at `_pullEth` (line 1204). The hook reverts at zero with `NoETHToRelease` (CauldronHook.sol:1944), which the catch swallows, and the released ether lands in the registry because the library runs under delegatecall — the same reason the hook's sender check at `registry` (CauldronHook.sol:1814) passes.
- Edges: none
- Observations: none

### `releaseRelaunchAsset/function` — PoolOps.sol:66

- Signature: `function releaseRelaunchAsset(address asset) external returns (uint256)`
- Authority: registry (gate held by the hook)
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CauldronHook.sol:1813)`
- Reads: none
- Writes: none
- Value: ERC20 transfer of the released asset to the registry at `releaseRelaunchAsset` (line 66)
- Reachability: Called inside a try/catch at `releaseRelaunchAsset` (line 66) from `_pullAsset` (line 1160), reached from the proposal-quote branch at `_pullAsset` (line 1160) and the last-resort own-quote branch at `_pullAsset` (line 1160) of `seedFunding` (line 68). The comment at `releaseRelaunchAsset` (line 66) records that this library is the first caller the hook function has had.
- Edges: none
- Observations: none

### `relaunchETH/function` — PoolOps.sol:70

- Signature: `function relaunchETH() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `relaunchETH` is declared at PoolOps.sol:70; implementation-defined caller through this interface.
- Edges: none
- Observations: none

### `relaunchAsset/function` — PoolOps.sol:71

- Signature: `function relaunchAsset(address asset) external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `relaunchAsset` is declared at PoolOps.sol:71; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IVaultCloseOps (declared in PoolOps.sol)`

### `close/function` — PoolOps.sol:76

- Signature: `function close() external returns (uint256 swept)`
- Authority: registry (gate held by the vault)
- Gate evidence: `if (msg.sender != registry) revert NotRegistry(); (CauldronVault.sol:199)`
- Reads: none
- Writes: none
- Value: receives native into the registry from the dying vault at `close` (line 76)
- Reachability: Called once, inside a try/catch at `close` (line 76) at the top of `seedFunding` (line 74), so a vault that cannot pay out cannot block the rebirth. The vault marks itself closed and forwards its whole balance to the registry at `close` (CauldronVault.sol:104); the swept figure is returned as `vaultSwept` (line 1069) and later sizes the collection entitlement at `crystallizeCollection` (CauldronRegistry.sol:1094).
- Edges: none
- Observations: none


## `ICollectionOps (declared in PoolOps.sol)`

### `custodyTransfer/function` — PoolOps.sol:80

- Signature: `function custodyTransfer(address from, address to, uint256 tokenId) external`
- Authority: registry or collection deployer (gate held by the collection)
- Gate evidence: `if (msg.sender != deployer) revert OnlyVault(); (CauldronCollection.sol:454)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Moves the NFT in both directions of the collection floor: into the treasury at `custodyTransfer` (line 80) during `recycleCollection` (line 1576) and out to the buyer at `custodyTransfer` (line 80) during `buyCollection` (line 1628). Under delegatecall the caller is the registry, which is the `deployer` (CauldronCollection.sol:389) a brew collection accepts; the continuation collection enforces the equivalent check at `custodyTransfer` (MiFrensGenesis.sol:593).
- Edges: none
- Observations: none

### `ownerOf/function` — PoolOps.sol:81

- Signature: `function ownerOf(uint256 tokenId) external view returns (address)`
- Authority: anyone (ERC721 view)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: The ownership precondition of both collection paths: the recycler must own the NFT at `ownerOf` (line 81) and the buyer's target must be treasury-held at `ownerOf` (line 81). Both compare against values the registry supplies — `caller` (line 1391) is forwarded `msg.sender` and `address` (line 81) is the registry itself under delegatecall.
- Edges: none
- Observations: none


## `ILegacyHookOps (declared in PoolOps.sol)`

### `sweepLegacyReserve/function` — PoolOps.sol:85

- Signature: `function sweepLegacyReserve(address token, address to) external returns (uint256)`
- Authority: the hook's recorded legacy registry (gate held by the hook)
- Gate evidence: `if (msg.sender != legacyRegistry) revert OnlySelf(); (CauldronHook.sol:1336)`
- Reads: none
- Writes: none
- Value: ERC20 transfer of the live token to the registry at `sweepLegacyReserve` (line 85)
- Reachability: Called at `sweepLegacyReserve` (line 85) in `materializeLegacy` (line 1493), only after the identity pre-check at `legacyRegistry` (line 86) has confirmed the hook would accept this caller, so the gate at `legacyRegistry` (CauldronHook.sol:1203) is never hit as a revert. Both entry points — `materializeLegacy` (CauldronRegistry.sol:1562) and the permissionless `materializeLegacy` (RedemptionExt.sol:163) — pass the registry address as `registryAddr` (line 1494).
- Edges: none
- Observations: none

### `legacyRegistry/function` — PoolOps.sol:86

- Signature: `function legacyRegistry() external view returns (address)`
- Authority: anyone (public state-variable getter on the hook)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `legacyRegistry` (line 86) as the wiring check that turns `materializeLegacy` (line 1493) into a no-op when the hook points at a different registry; the state read is the hook's public slot `legacyRegistry` (CauldronHook.sol:362).
- Edges: none
- Observations: none


## `ICauldronBurn (declared in PoolOps.sol)`

### `burn/function` — PoolOps.sol:90

- Signature: `function burn(address from, uint256 amount) external`
- Authority: registry (gate held by the token)
- Gate evidence: `onlyRegistry (CauldronToken.sol:58)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Two call sites: the holder's old-generation balance at `burn` (line 90) in `migrateOne` (line 1409), reached from `claimByBurn` (CauldronRegistry.sol:1303), the `claimByBurnUpTo` (CauldronRegistry.sol:1348) forwarder stub, whose body is `claimByBurnUpTo` (RedemptionExt.sol:795) and `autoMigrateBatch` (CauldronRegistry.sol:1381); and the registry's own dead-token holding at `burn` (line 90) on the relaunch flush branch of `materializeLegacy` (line 1493). The token only accepts the registry, which is `address(this)` under delegatecall — see `onlyRegistry` (CauldronToken.sol:58).
- Edges: none
- Observations: none


## `IAutoFlag (declared in PoolOps.sol)`

### `autoMigrate/function` — PoolOps.sol:93

- Signature: `function autoMigrate(address who) external view returns (bool)`
- Authority: anyone (public mapping getter on the registry itself)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: A self-call: `autoMigrate` (line 93) casts `address(this)` — the registry under delegatecall — to this interface and reads the opt-in flag stored at `autoMigrate` (CauldronBase.sol:309), once per holder inside the keeper loop of `autoMigrateBatch` (line 1387). Reading it per iteration rather than snapshotting is what lets a wallet opt out mid-batch, as the registry comment says at `autoMigrateBatch` (CauldronRegistry.sol:1381).
- Edges: none
- Observations: none


## `IPermit2Ops (declared in PoolOps.sol)`

### `approve/function` — PoolOps.sol:106

- Signature: `function approve(address token, address spender, uint160 amount, uint48 expiration) external`
- Authority: anyone (the canonical Permit2 records an allowance per msg.sender)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called at `approve` (line 106) in `_approve` (line 204), always against the hard-coded `PERMIT2` (line 131) address, after the ERC20 allowance to Permit2 is set at `approve` (line 106). The allowance it records is the registry's, because the library is delegatecalled, and it expires 300 seconds out at `expiration` (line 106). Every mint and top-up in this library funnels through `_approve` (line 204): `_approve` (line 803), `_approve` (line 803), `_approve` (line 803) and `_approve` (line 1364).
- Edges: none
- Observations: none


## `PoolOps`

### `creatureFor/function` — PoolOps.sol:181

- Signature: `function creatureFor(uint256 gen) external pure returns (string memory name, string memory symbol)`
- Authority: anyone directly at the linked library address; in the protocol path, igniter or owner (the gate is on the registry side)
- Gate evidence: `if (msg.sender != owner() && msg.sender != igniter) revert NotAdmin(); (CauldronRegistry.sol:727)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure string table, delegatecalled once from `creatureFor` (CauldronRegistry.sol:738) inside `summon` (CauldronRegistry.sol:681), which only the owner or the igniter may fire. Generation 2 and later name themselves from the winning proposal instead, so the cycle at `idx` (line 182) is the gen-1 theme plus a fallback, as the header says at `creatureFor` (line 181). A direct call to the deployed library is harmless: nothing is read or written.
- Edges: none
- Observations: none

### `_approve/function` — PoolOps.sol:204

- Signature: `function _approve(address token, address pm, uint256 amount) private`
- Authority: internal (callers: _seedActive, _seedReserve, addToReserve)
- Gate evidence: `UNGATED`
- Reads: `PERMIT2 (line 205, constant)`
- Writes: none
- Value: NONE
- Reachability: Private helper reached from every mint path in this library — `_approve` (line 204) and `_approve` (line 204) in the active seed, `_approve` (line 204) in the reserve seed and `_approve` (line 204) in the reserve top-up. Because the library is delegatecalled the allowance granted is the REGISTRY's, to the canonical `PERMIT2` (line 205) and from there to the PositionManager, expiring 300 seconds out at `approve` (line 205). It is called with the iteration token and, on the non-native branch at `_approve` (line 204), with the quote asset — an arbitrary allowlisted ERC20.
- Edges: `IERC20.approve (PoolOps.sol:205), UNTRUSTED, out-of-cluster`; `IPermit2Ops.approve (PoolOps.sol:206), TRUSTED, out-of-cluster`
- Observations: none

### `_minQuoteFor/function` — PoolOps.sol:213

- Signature: `function _minQuoteFor(uint256 tokenAmount) private pure returns (uint256)`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_minQuoteFor` is declared at PoolOps.sol:213; internal (callers are paths that reference this function).
- Edges: none
- Observations: none

### `_sqrtPrice/function` — PoolOps.sol:227

- Signature: `function _sqrtPrice(uint256 tokenAmount, uint256 ethAmount) private pure returns (uint160)`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_sqrtPrice` is declared at PoolOps.sol:227; internal (callers are paths that reference this function).
- Edges: `PoolOps._minQuoteFor (PoolOps.sol:245), TRUSTED, in-cluster`; `FullMath.mulDiv (PoolOps.sol:247), TRUSTED, library`
- Observations: none

### `createAndSeed/function` — PoolOps.sol:262

- Signature: `function createAndSeed( IPoolManager poolManager, IPositionManagerOps pm, address hook, address token, uint256 activeTokens, uint256 ethAmount, uint256 reserveTokens, int24 tickSpacing, uint24 poolFee, int24 ceilingOffset, /// The asset this pool is PRICED IN (address(0) = native ETH). /// Always currency0: the token is deployed to sort above it. address quote ) external returns (SeedResult memory r)`
- Authority: anyone directly at the linked library address; NO in-protocol caller
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE directly; the quote leg is paid inside `_seedActive` (line 290)
- Reachability: The silent two-position seed: initialize at the contributed ratio, one full-range active position, then the out-of-range reserve. It is DEAD in the protocol path — the registry's only two seeding branches are the green candle at `_createPoolAndSeedWithBuy` (CauldronRegistry.sol:1737) and the progressive handoff at `createAndSeedProgressive` (CauldronRegistry.sol:1777) (DERIVED). Called directly at the library address it would run in the caller's own context, where the executing account holds neither the tokens nor the quote, so the mint inside `_seedActive` (line 290) fails on the transfer. Reserve placement is skipped entirely when `reserveTokens` (line 292) is zero.
- Edges: `PoolIdLibrary.toId (PoolOps.sol:284), TRUSTED, library`; `PoolOps._sqrtPrice (PoolOps.sol:286), TRUSTED, in-cluster`; `IPoolManager.initialize (PoolOps.sol:287), TRUSTED, out-of-cluster`; `TickMath.getTickAtSqrtPrice (PoolOps.sol:288), TRUSTED, library`; `PoolOps._seedActive (PoolOps.sol:290), TRUSTED, in-cluster`; `ReserveLib.reserveTicks (PoolOps.sol:294), TRUSTED, library`; `PoolOps._seedReserve (PoolOps.sol:296), TRUSTED, in-cluster`
- Observations: comment at `createAndSeed` (CauldronRegistry.sol:1728) says PoolOps still exposes `createAndSeed` for reference / external callers; no code in the repo calls it — DERIVED, grep for createAndSeed outside PoolOps.sol finds only that comment, while both seed paths go through `_createPoolAndSeedWithBuy` (CauldronRegistry.sol:1737) and `createAndSeedProgressive` (CauldronRegistry.sol:1777)

### `createAndSeedProgressive/function` — PoolOps.sol:317

- Signature: `function createAndSeedProgressive( IPoolManager poolManager, IPositionManagerOps pm, address hook, address token, uint256 activeTokens, uint256 ethAmount, uint256 reserveTokens, int24 tickSpacing, uint24 poolFee, int24 ceilingOffset, SeedParams calldata sp, /// The asset this pool is PRICED IN (address(0) = native ETH). /// Always currency0: the token is deployed to sort above it. address quote ) external returns (SeedResult memory r)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `SEED_BASE_WAD (line 400, constant)`; `SEED_BANDWIDTH (line 417, constant)`; `SEED_FLOOR_WAD (line 418, constant)`; `SEED_MINSTEP_WAD (line 418, constant)`
- Writes: none
- Value: receives native through `msg.value` (PoolOps.sol:344)
- Reachability: `createAndSeedProgressive` is declared at PoolOps.sol:317; anyone.
- Edges: `PoolIdLibrary.toId (PoolOps.sol:340), TRUSTED, library`; `PoolOps._sqrtPrice (PoolOps.sol:362), TRUSTED, in-cluster`; `IPoolManager.initialize (PoolOps.sol:363), TRUSTED, out-of-cluster`; `ReserveLib.reserveTicks (PoolOps.sol:365), TRUSTED, library`; `TickMath.getTickAtSqrtPrice (PoolOps.sol:366), TRUSTED, library`; `PoolOps._seedReserve (PoolOps.sol:368), TRUSTED, in-cluster`; `PoolOps._seedActive (PoolOps.sol:372), TRUSTED, in-cluster`; `PoolOps._greenCandle (PoolOps.sol:403), TRUSTED, in-cluster`; `IERC20.approve (PoolOps.sol:414), UNTRUSTED, out-of-cluster`; `ISeeder.startSeed (PoolOps.sol:415), UNTRUSTED, out-of-cluster`
- Observations: none

### `createAndSeedWithBuy/function` — PoolOps.sol:446

- Signature: `function createAndSeedWithBuy( IPoolManager poolManager, IPositionManagerOps pm, address hook, address token, uint256 activeTokens, uint256 ethAmount, uint256 reserveTokens, int24 tickSpacing, uint24 poolFee, int24 ceilingOffset, /// The asset this pool is PRICED IN (address(0) = native ETH). /// Always currency0: the token is deployed to sort above it. address quote ) external returns (SeedResult memory r)`
- Authority: anyone directly at the linked library address; in the protocol path, igniter/owner via summon and anyone via relaunch once the pool is dead
- Gate evidence: `if (!hook.isDead(oldPoolId)) revert TokenStillAlive(); (CauldronRegistry.sol:829)`
- Reads: none
- Writes: none
- Value: NONE directly; the whole quote tranche is spent inside `_greenCandle` (line 470)
- Reachability: The default seed for BOTH generation 1 and every rebirth: delegatecalled from `createAndSeedWithBuy` (CauldronRegistry.sol:1733) in `_createPoolAndSeedWithBuy` (CauldronRegistry.sol:1726), the else-branch at `_createPoolAndSeedWithBuy` (CauldronRegistry.sol:1737). It only builds the key and forwards to `_greenCandle` (line 470); the caller must already be tax-exempt on the hook and have armed `_seedBuyUnlocked` (CauldronRegistry.sol:1733), because the buy re-enters through `unlockCallback` (CauldronRegistry.sol:1782). The quote for the generation comes from `generationQuote` (CauldronRegistry.sol:1705).
- Edges: `PoolIdLibrary.toId (PoolOps.sol:468), TRUSTED, library`; `PoolOps._greenCandle (PoolOps.sol:470), TRUSTED, in-cluster`
- Observations: none

### `_greenCandle/function` — PoolOps.sol:519

- Signature: `function _greenCandle( IPoolManager poolManager, IPositionManagerOps pm, SeedResult memory r, address token, uint256 activeTok, uint256 ethAmt, uint256 reserveTok, int24 tickSpacing, int24 ceilingOffset, address quote ) private`
- Authority: internal (callers: createAndSeedProgressive, createAndSeedWithBuy)
- Gate evidence: `UNGATED`
- Reads: `BUY_SETTLE_BUFFER (line 534, constant)`
- Writes: none
- Value: pays the quote leg of the mint inside `_seedActive` (line 542); the exact-output buy settles from the registry inside `unlock` (line 548)
- Reachability: The shared candle body, reached from `_greenCandle` (line 519) on the hybrid path and `_greenCandle` (line 519) on the atomic one — so from `_seedGeneration` (CauldronRegistry.sol:773) under summon and `_seedGeneration` (CauldronRegistry.sol:1132) under relaunch. Sequence: fund the full-range position with `ethActive` (line 533) minus a fixed `BUY_SETTLE_BUFFER` (line 534), then buy exactly `reserveTok` (line 531) back out through the PoolManager unlock, which re-enters the registry's `unlockCallback` (CauldronRegistry.sol:1782) and lands in `executeBuy` (line 569). LIVE POOL STATE: the reserve band is placed off the POST-BUY tick read at `getSlot0` (line 553), not the launch tick, and it is sized from `bought` (line 549) — the amount the swap actually delivered. The reserve step is skipped when `reserveTok` (line 531) is zero.
- Edges: `FullMath.mulDiv (PoolOps.sol:533), TRUSTED, library`; `PoolOps._sqrtPrice (PoolOps.sol:537), TRUSTED, in-cluster`; `IPoolManager.initialize (PoolOps.sol:538), TRUSTED, out-of-cluster`; `PoolOps._seedActive (PoolOps.sol:542), TRUSTED, in-cluster`; `IPoolManager.unlock (PoolOps.sol:548), TRUSTED, out-of-cluster`; `StateLibrary.getSlot0 (PoolOps.sol:553), TRUSTED, library`; `ReserveLib.reserveTicks (PoolOps.sol:555), TRUSTED, library`; `PoolOps._seedReserve (PoolOps.sol:557), TRUSTED, in-cluster`
- Observations: none

### `executeBuy/function` — PoolOps.sol:569

- Signature: `function executeBuy(bytes calldata data) external returns (bytes memory)`
- Authority: the PoolManager, through the registry's armed unlock window (the gate is on the registry side)
- Gate evidence: `if (msg.sender != address(poolManager)) revert NotPoolManager(); (CauldronRegistry.sol:1824)`
- Reads: `MIN_SQRT_LIMIT (line 585, constant)`
- Writes: none
- Value: sends native to the PoolManager at `settle` (line 595); ERC20 transfer of the quote to the PoolManager at `transfer` (line 604); receives the bought token at `take` (line 639)
- Reachability: Delegatecalled from `executeBuy` (CauldronRegistry.sol:1827), which only runs when the caller is the PoolManager and the registry has armed the window at `_seedBuyUnlocked` (CauldronRegistry.sol:1787); the arming happens around the seed at `_seedBuyUnlocked` (CauldronRegistry.sol:1733) and is cleared at `_seedBuyUnlocked` (CauldronRegistry.sol:1745). It serves two callers with one encoding: exact output for the reserve reseed from `unlock` (line 597) and exact input for the owner-funded prime buy from `unlock` (line 597); the sign of `amtSpecified` (line 574) selects which, and `recipient` (line 572) decides whether the token stays in the registry or goes straight out. The swap is tagged with `address(this)` (line 578) so the hook waives fees and surtax. Settlement branches on the quote at `q` (line 608): native pays with value, an ERC20 goes sync -> checked low-level transfer -> settle, and the return value is verified at `require` (line 636).
- Edges: `IPoolManager.swap (PoolOps.sol:580), TRUSTED, out-of-cluster`; `BalanceDeltaLibrary.amount0 (PoolOps.sol:590), TRUSTED, library`; `BalanceDeltaLibrary.amount1 (PoolOps.sol:591), TRUSTED, library`; `IPoolManager.settle (PoolOps.sol:610), TRUSTED, out-of-cluster`; `IPoolManager.sync (PoolOps.sol:612), TRUSTED, out-of-cluster`; `IERC20.transfer (PoolOps.sol:635), UNTRUSTED, out-of-cluster`; `IPoolManager.settle (PoolOps.sol:637), TRUSTED, out-of-cluster`; `IPoolManager.take (PoolOps.sol:639), TRUSTED, out-of-cluster`
- Observations: none

### `primeBuy/function` — PoolOps.sol:652

- Signature: `function primeBuy(IPoolManager poolManager, PoolKey memory key, uint256 ethIn, address recipient) external returns (uint256 got)`
- Authority: anyone directly at the linked library address; in the protocol path, igniter or owner (the gate is on the registry side)
- Gate evidence: `if (msg.sender != owner() && msg.sender != igniter) revert NotAdmin(); (CauldronRegistry.sol:727)`
- Reads: none
- Writes: none
- Value: spends exactly `ethIn` of the registry's native balance inside the unlock at `unlock` (line 656); the bought token goes to `recipient` (line 652)
- Reachability: Delegatecalled from `primeBuy` (CauldronRegistry.sol:789) during `summon` (CauldronRegistry.sol:681), funded by the separately tracked `primeBuyEth` (CauldronBase.sol:297) that the prime funder deposited. It is a thin wrapper: the negative amount at `ethIn` (line 650) makes the unlock body an EXACT-INPUT swap, so `executeBuy` (line 569) spends precisely that much and sends the token to the wallet the registry names. The registry must have armed the unlock window first, as `_seedBuyUnlocked` (CauldronRegistry.sol:1787) refuses otherwise.
- Edges: `IPoolManager.unlock (PoolOps.sol:656), TRUSTED, out-of-cluster`
- Observations: none

### `deployTokenAbove/function` — PoolOps.sol:753

- Signature: `function deployTokenAbove( string memory name, string memory symbol, uint256 gen, uint256 totalSupply, address quote ) external returns (address token, address quoteUsed)`
- Authority: anyone directly at the linked library address; in the protocol path, igniter/owner via summon and anyone via relaunch once the pool is dead
- Gate evidence: `if (!hook.isDead(oldPoolId)) revert TokenStillAlive(); (CauldronRegistry.sol:829)`
- Reads: `QUOTE_WATERMARK (line 763, constant)`; `SALT_TRIES (line 772, constant)`
- Writes: none
- Value: NONE (the deployed token mints its whole fixed supply to the deployer, which is the registry under delegatecall, at `totalSupply` (line 768))
- Reachability: Delegatecalled from `_deployToken` (CauldronRegistry.sol:1692), which `summon` reaches at `_deployToken` (CauldronRegistry.sol:742) with a native quote and `relaunch` at `_deployToken` (CauldronRegistry.sol:967) with the quote the winning proposal named. It mines a CREATE2 salt until the predicted address sorts above `floor` (line 763) — the greater of the requested quote and the hard-coded watermark — and asserts the prediction at `require` (line 781). The search is bounded by `SALT_TRIES` (line 772); on exhaustion it does NOT revert but deploys unmined and returns `address(0)` at `CauldronToken` (line 767), so the caller must record the RETURNED quote rather than the requested one, which the registry does at `specQuote` (CauldronRegistry.sol:947). Because the library is delegatecalled, the CREATE2 deployer is the registry, so the address cannot be occupied by a third party.
- Edges: none
- Observations: none

### `_seedActive/function` — PoolOps.sol:793

- Signature: `function _seedActive( address quote, IPositionManagerOps pm, PoolKey memory key, uint160 sqrtPriceX96, uint256 ethAmount, uint256 tokenAmount, address token, int24 tickSpacing ) private returns (uint256 positionId)`
- Authority: internal (callers: createAndSeed, createAndSeedProgressive, _greenCandle, openOrAddPair)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native to the PositionManager with the mint at `modifyLiquidities` (line 832); on the ERC20 branch the quote is PULLED by the PositionManager after `_approve` (line 803)
- Reachability: The full-range mint used by every seed path and by the rotation's return leg: `_seedActive` (line 793), `_seedActive` (line 793), `_seedActive` (line 793) and `_seedActive` (line 793). The range is the whole curve, snapped to spacing at `minTick` (line 805) and `maxTick` (line 806); liquidity is sized from the price it is minted at via `getLiquidityForAmounts` (line 808), which is why `openOrAddPair` (line 905) re-reads the live price before calling here. The action list is MINT_POSITION, SETTLE_PAIR, SWEEP at `actions` (line 816), with the sweep returning excess quote to the registry at `params` (line 819). The native/ERC20 split at `quote` (line 794) decides whether value is forwarded or an allowance is granted; the header warns that sending value with an ERC20 quote would strand it at `PositionManager` (line 829).
- Edges: `PoolOps._approve (PoolOps.sol:803), TRUSTED, in-cluster`; `LiquidityAmounts.getLiquidityForAmounts (PoolOps.sol:808), TRUSTED, library`; `TickMath.getSqrtPriceAtTick (PoolOps.sol:810), TRUSTED, library`; `TickMath.getSqrtPriceAtTick (PoolOps.sol:811), TRUSTED, library`; `IPositionManagerOps.nextTokenId (PoolOps.sol:827), TRUSTED, out-of-cluster`; `IPositionManagerOps.modifyLiquidities (PoolOps.sol:832), TRUSTED, out-of-cluster`; `PoolOps._approve (PoolOps.sol:834), TRUSTED, in-cluster`; `IPositionManagerOps.modifyLiquidities (PoolOps.sol:835), TRUSTED, out-of-cluster`
- Observations: none

### `_seedReserve/function` — PoolOps.sol:841

- Signature: `function _seedReserve( address quote, IPositionManagerOps pm, PoolKey memory key, int24 tickLower, int24 tickUpper, uint256 tokenAmount, address token ) private returns (uint256 positionId)`
- Authority: internal (callers: createAndSeed, createAndSeedProgressive, _greenCandle)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: no native leg — the band is single-sided token; the token is PULLED by the PositionManager after `_approve` (line 865)
- Reachability: Mints the out-of-range reserve band that backs 1:1 migration and the genesis claim; reached from `_seedReserve` (line 841), `_seedReserve` (line 841) and `_seedReserve` (line 841). Sizing rounds DOWN in `liquidityForTokenOut` (line 850), so a dust tranche maps to zero liquidity and the function returns 0 at `liquidity` (line 850) instead of letting the PositionManager revert — leaving the generation with no reserve position, which `claimFromReserve` (line 860) and `addToReserve` (line 860) both treat as a no-op. Single-sided is expressed by max0 = 0 at `params` (line 870).
- Edges: `ReserveLib.liquidityForTokenOut (PoolOps.sol:850), TRUSTED, library`; `PoolOps._approve (PoolOps.sol:865), TRUSTED, in-cluster`; `IPositionManagerOps.nextTokenId (PoolOps.sol:879), TRUSTED, out-of-cluster`; `IPositionManagerOps.modifyLiquidities (PoolOps.sol:880), TRUSTED, out-of-cluster`
- Observations: none

### `openOrAddPair/function` — PoolOps.sol:905

- Signature: `function openOrAddPair( IPoolManager poolManager, IPositionManagerOps pm, address hook, address token, address quote, uint256 quoteAmount, uint256 tokenAmount, int24 tickSpacing, uint24 poolFee ) external returns (PoolId poolId, uint256 positionId)`
- Authority: anyone directly at the linked library address; in the protocol path, permissionless within the guild's approved envelope, or the owner on the completion path
- Gate evidence: `if (remaining == 0) revert NoRotationApproved(); (RedemptionExt.sol:343)`
- Reads: none
- Writes: none
- Value: the quote and token legs are paid inside `_seedActive` (line 944)
- Reachability: The return leg of a rotation, delegatecalled from `openOrAddPair` (RedemptionExt.sol:465) inside the permissionless-within-mandate `rotateSliceFrom` (RedemptionExt.sol:307) and from no other site: the owner-only `completeRotation` that used to hold a second call is deleted (RedemptionExt.sol:750). Two preconditions are asserted rather than assumed: non-zero amounts at `require` (line 916) and the watermark ordering at `require` (line 916). LIVE POOL STATE: `initialize` is attempted, and on failure the catch reads `getSlot0` (line 951) — a zero sqrt price means the pool genuinely does not exist, so the refusal is re-thrown at `PoolInitRefused` (line 952); otherwise the LIVE price replaces the contributed one at `sqrtPriceX96` (line 947) so the top-up is sized at the price it will actually mint at.
- Edges: `PoolIdLibrary.toId (PoolOps.sol:926), TRUSTED, library`; `PoolOps._sqrtPrice (PoolOps.sol:947), TRUSTED, in-cluster`; `IPoolManager.initialize (PoolOps.sol:948), TRUSTED, out-of-cluster`; `StateLibrary.getSlot0 (PoolOps.sol:951), TRUSTED, library`; `PoolOps._seedActive (PoolOps.sol:956), TRUSTED, in-cluster`
- Observations: none

### `removePartial/function` — PoolOps.sol:976

- Signature: `function removePartial( IPositionManagerOps pm, uint256 positionId, PoolKey memory key, address token, address quote, uint16 bps ) external returns (uint256 quoteRecovered, uint256 tokensRecovered)`
- Authority: anyone directly at the linked library address; in the protocol path, permissionless within the guild's approved envelope
- Gate evidence: `if (remaining == 0) revert NoRotationApproved(); (RedemptionExt.sol:343)`
- Reads: `MAX_ROTATION_BPS (line 984, constant)`
- Writes: none
- Value: TAKE_PAIR delivers both currencies to the registry at `modifyLiquidities` (line 1003)
- Reachability: Delegatecalled from `removePartial` (RedemptionExt.sol:384) in `rotateSliceFrom` (RedemptionExt.sol:307), the only caller. It withdraws a share of the CURRENT liquidity — read live at `getPositionLiquidity` (line 985) — capped by `MAX_ROTATION_BPS` (line 984) at 50%, and returns 0 rather than reverting when the position or the computed share is empty at `take` (line 988). No BURN_POSITION action is encoded at `actions` (line 996), so the source pair keeps trading. Both outputs are MEASURED as balance deltas around the call, quote through `_balance` (line 991) so an ERC20-quoted generation is accounted at all, and token through `balanceOf` (line 992).
- Edges: `IPositionManagerOps.getPositionLiquidity (PoolOps.sol:985), TRUSTED, out-of-cluster`; `PoolOps._balance (PoolOps.sol:991), TRUSTED, in-cluster`; `IERC20.balanceOf (PoolOps.sol:992), UNTRUSTED, out-of-cluster`; `IPositionManagerOps.modifyLiquidities (PoolOps.sol:1003), TRUSTED, out-of-cluster`; `PoolOps._balance (PoolOps.sol:1005), TRUSTED, in-cluster`; `IERC20.balanceOf (PoolOps.sol:1006), UNTRUSTED, out-of-cluster`
- Observations: none

### `seedFunding/function` — PoolOps.sol:1071

- Signature: `function seedFunding( address hookAddr, address wantQuote, address oldQuote, uint256 recovered, address oldVault ) external returns (address quoteUsed, uint256 amount, uint256 vaultSwept)`
- Authority: anyone in the linked library; protocol execution is reached only through the registry's relaunch lifecycle
- Gate evidence: `UNGATED`
- Reads: `MIN_SEED_UNITS (line 1198, constant)`
- Writes: none
- Value: NONE (best-effort calls may move vault native and hook reserves into the registry under delegatecall)
- Reachability: Delegatecalled by `relaunch` through `seedFunding` (CauldronRegistry.sol:999). It closes the old vault best-effort, then selects a fundable denomination without abandoning recovered value; every reserve release is caught so an optional pull cannot itself halt rebirth.
- Edges: `IVaultCloseOps.close (PoolOps.sol:1084), TRUSTED, out-of-cluster`; `PoolOps._pullAsset (PoolOps.sol:1197), TRUSTED, in-cluster`; `PoolOps._pullEth (PoolOps.sol:1204), TRUSTED, in-cluster`; `PoolOps._pullAsset (PoolOps.sol:1209), TRUSTED, in-cluster`
- Observations: none

### `_pullAsset/function` — PoolOps.sol:1224

- Signature: `function _pullAsset(address hookAddr, address asset, uint256 have) private returns (uint256 got)`
- Authority: internal (caller: PoolOps.seedFunding)
- Gate evidence: `UNGATED`
- Reads: `MIN_SEED_UNITS (line 1226, constant)`
- Writes: none
- Value: ERC20 reserve may move from the hook into the registry at `releaseRelaunchAsset` (PoolOps.sol:1227)
- Reachability: Reached from `seedFunding` at `_pullAsset` (PoolOps.sol:1197) and `_pullAsset` (PoolOps.sol:1209). It peeks before pulling and catches a failed release.
- Edges: `PoolOps._peek (PoolOps.sol:1225), TRUSTED, in-cluster`; `IHookReserves.releaseRelaunchAsset (PoolOps.sol:1227), TRUSTED, out-of-cluster`
- Observations: none

### `_peek/function` — PoolOps.sol:1235

- Signature: `function _peek(address hookAddr, bytes memory cd) private view returns (uint256 v)`
- Authority: internal (callers: PoolOps._pullAsset, PoolOps._pullEth)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Reached at `_peek` (PoolOps.sol:1225) and `_peek` (PoolOps.sol:1244). Malformed or reverting returndata is treated as zero rather than propagated.
- Edges: none
- Observations: none

### `_pullEth/function` — PoolOps.sol:1243

- Signature: `function _pullEth(address hookAddr, uint256 have) private returns (uint256 got)`
- Authority: internal (caller: PoolOps.seedFunding)
- Gate evidence: `UNGATED`
- Reads: `MIN_SEED_UNITS (line 1245, constant)`
- Writes: none
- Value: native reserve may move from the hook into the registry at `releaseRelaunchETH` (PoolOps.sol:1246)
- Reachability: Reached from `seedFunding` at `_pullEth` (PoolOps.sol:1204). It peeks before pulling and catches a failed release.
- Edges: `PoolOps._peek (PoolOps.sol:1244), TRUSTED, in-cluster`; `IHookReserves.releaseRelaunchETH (PoolOps.sol:1246), TRUSTED, out-of-cluster`
- Observations: none

### `sendAsset/function` — PoolOps.sol:1249

- Signature: `function sendAsset(address asset, address to, uint256 amount) external`
- Authority: anyone directly at the linked library address; in the protocol path, permissionless within the guild's approved envelope, or owner for the leg-proceeds sweep
- Gate evidence: `if (remaining == 0) revert NoRotationApproved(); (RedemptionExt.sol:343)`
- Reads: none
- Writes: none
- Value: sends native to an arbitrary recipient at `call` (line 1252); ERC20 transfer of an arbitrary asset to an arbitrary recipient at `transfer` (line 1256)
- Reachability: Two call sites, both on the facet: the rotation hands the withdrawn slice to the rotator at `sendAsset` (RedemptionExt.sol:458) inside `rotateSliceFrom` (RedemptionExt.sol:307), and the owner drains booked foreign proceeds at `sendAsset` (RedemptionExt.sol:1155) inside `sweepLegProceeds` (RedemptionExt.sol:973). Under delegatecall the value leaves the REGISTRY. Both branches check the outcome — native at `require` (line 1253) and the ERC20 return value at `require` (line 1253) — and a zero amount returns early at `amount` (line 1249). Neither the asset nor the recipient is constrained here; the constraint lives in the callers.
- Edges: `IERC20.transfer (PoolOps.sol:1256), UNTRUSTED, out-of-cluster`
- Observations: none

### `_balance/function` — PoolOps.sol:1261

- Signature: `function _balance(address asset) private view returns (uint256)`
- Authority: internal (callers: removePartial, removeAll)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: The one place the quote side is measured without assuming it is ether: `address(0)` reads the executing account's native balance and anything else reads an ERC20 balance, both at `balanceOf` (line 1262). Used as the before/after pair in `_balance` (line 1261) and `_balance` (line 1261) for a partial withdrawal and in `_balance` (line 1261) and `_balance` (line 1261) for a full one. Under delegatecall the balance read is the registry's.
- Edges: `IERC20.balanceOf (PoolOps.sol:1262), UNTRUSTED, out-of-cluster`
- Observations: none

### `removeAll/function` — PoolOps.sol:1280

- Signature: `function removeAll(IPositionManagerOps pm, uint256 positionId, PoolKey memory key, address token) external returns (uint256 quoteRecovered, uint256 tokensRecovered)`
- Authority: anyone directly at the linked library address; in the protocol path, anyone once the old pool is dead, or anyone at all through the facet's leg recovery
- Gate evidence: `if (!hook.isDead(oldPoolId)) revert TokenStillAlive(); (CauldronRegistry.sol:829)`
- Reads: none
- Writes: none
- Value: TAKE_PAIR delivers both currencies to the registry and BURN_POSITION destroys the position NFT at `modifyLiquidities` (line 1299)
- Reachability: The death path. The registry unwinds the active position at `removeAll` (CauldronRegistry.sol:1630) and the reserve at `removeAll` (CauldronRegistry.sol:1630) inside `_removeLiquidity` (CauldronRegistry.sol:1618), reached from `relaunch` (CauldronRegistry.sol:812); the facet unwinds every rotated leg at `removeAll` (RedemptionExt.sol:1089) inside the permissionless `recoverLegs` (RedemptionExt.sol:901), each leg inside its own try/catch. A zero-liquidity id returns (0,0) at `liquidity` (line 1284) rather than reverting. RECOVERY IS MEASURED, not assumed: the quote is whatever `currency0` (line 1287) is, read through `_balance` (line 1288) so an ERC20-quoted generation reports a real figure, and the token side through `balanceOf` (line 1289). The action list includes BURN_POSITION at `BURN_POSITION` (line 1292), so the NFT does not survive.
- Edges: `IPositionManagerOps.getPositionLiquidity (PoolOps.sol:1284), TRUSTED, out-of-cluster`; `PoolOps._balance (PoolOps.sol:1288), TRUSTED, in-cluster`; `IERC20.balanceOf (PoolOps.sol:1289), UNTRUSTED, out-of-cluster`; `IPositionManagerOps.modifyLiquidities (PoolOps.sol:1299), TRUSTED, out-of-cluster`; `PoolOps._balance (PoolOps.sol:1301), TRUSTED, in-cluster`; `IERC20.balanceOf (PoolOps.sol:1302), UNTRUSTED, out-of-cluster`
- Observations: none

### `claimFromReserve/function` — PoolOps.sol:1311

- Signature: `function claimFromReserve( IPositionManagerOps pm, uint256 positionId, PoolKey memory key, int24 tickLower, int24 tickUpper, uint256 amount, address recipient ) public returns (uint256 taken)`
- Authority: anyone directly at the linked library address; in the protocol path, the fren holder (facet), a migrating holder, or an NFT recycler — each gated by its own caller
- Gate evidence: `if (_redeemBlocked()) revert RedemptionPaused(); (RedemptionExt.sol:83)`
- Reads: none
- Writes: none
- Value: delivers exactly the claimed token amount to `recipient` (line 1327) at `modifyLiquidities` (line 1337); no quote leg, the band is out of range
- Reachability: The single exit from the out-of-range reserve, reached from the OG redemption at `claimFromReserve` (RedemptionExt.sol:102), from 1:1 migration at `claimFromReserve` (line 1311) and from the collection recycle at `claimFromReserve` (line 1311). The request is converted to liquidity units at `liquidityForTokenOut` (line 1320) and CLAMPED to what the position holds at `have` (line 1323), so it can deliver LESS than asked and returns the measured delta at `taken` (line 1309) — every caller that owes a full payout re-checks that itself. Zero liquidity, either requested or held, returns 0 at `liquidity` (line 1320) without touching the pool. The position survives for the next claimer.
- Edges: `ReserveLib.liquidityForTokenOut (PoolOps.sol:1320), TRUSTED, library`; `IPositionManagerOps.getPositionLiquidity (PoolOps.sol:1323), TRUSTED, out-of-cluster`; `IERC20.balanceOf (PoolOps.sol:1327), UNTRUSTED, out-of-cluster`; `IPositionManagerOps.modifyLiquidities (PoolOps.sol:1337), TRUSTED, out-of-cluster`; `IERC20.balanceOf (PoolOps.sol:1339), UNTRUSTED, out-of-cluster`
- Observations: none

### `addToReserve/function` — PoolOps.sol:1351

- Signature: `function addToReserve( IPositionManagerOps pm, uint256 positionId, PoolKey memory key, int24 tickLower, int24 tickUpper, uint256 amount ) public returns (uint256 added)`
- Authority: anyone directly at the linked library address; in the protocol path, any token holder growing the floor, or the relaunch/legacy paths
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: the token is PULLED from the registry into the position by SETTLE_PAIR at `modifyLiquidities` (line 1375), after `_approve` (line 1364)
- Reachability: The mirror of the claim: it grows the reserve that backs redemption, so the genesis floor ratchets. Callers are the facet's `addToReserve` (RedemptionExt.sol:195) in `_pullGrow` (RedemptionExt.sol:192) — the re-enchant and buy-back-a-fren paths — the legacy materialization at `addToReserve` (line 1351) and the collection buy at `addToReserve` (line 1351). The registry must already hold the tokens: SETTLE_PAIR pulls what `_approve` (line 1364) allowed under delegatecall. It returns 0 without reverting for a zero amount at `amount` (line 1349) or when the amount maps to zero liquidity at `liquidity` (line 1360), and the consumed figure is measured as a balance delta at `added` (line 1358), which is what the callers credit rather than the amount requested.
- Edges: `ReserveLib.liquidityForTokenOut (PoolOps.sol:1360), TRUSTED, library`; `PoolOps._approve (PoolOps.sol:1364), TRUSTED, in-cluster`; `IERC20.balanceOf (PoolOps.sol:1365), UNTRUSTED, out-of-cluster`; `IPositionManagerOps.modifyLiquidities (PoolOps.sol:1375), TRUSTED, out-of-cluster`; `IERC20.balanceOf (PoolOps.sol:1378), UNTRUSTED, out-of-cluster`
- Observations: none

### `migrateUpTo/function` — PoolOps.sol:1401

- Signature: `function migrateUpTo( IPositionManagerOps pm, address prevToken, address from, uint256 maxAmount, ReserveRef memory r ) external returns (uint256 got)`
- Authority: anyone directly at the linked library address; in the protocol path, any holder of a previous generation's token (vesting gate applies)
- Gate evidence: `if (fromGen == 0 || fromGen >= currentGeneration) revert CannotClaimCurrentGen(); (CauldronRegistry.sol:1306)`
- Reads: none
- Writes: none
- Value: burns the caller's old token and delivers the same amount of the live token, both inside `migrateOne` (line 1409)
- Reachability: Delegatecalled from `migrateUpTo` (RedemptionExt.sol:811) in `claimByBurnUpTo` (RedemptionExt.sol:795), which refuses the live generation at `CannotClaimCurrentGen` (RedemptionExt.sol:799) and routes ordinary holders through the escrow when one is set at `VestingEnforced` (RedemptionExt.sol:801); the registry-side entry is the forwarder stub `claimByBurnUpTo` (CauldronRegistry.sol:1348), so the gate is held on the extension side. CAPACITY-AWARE: it converts the reserve's live liquidity into a deliverable token amount at `tokenOutForLiquidity` (line 1404) and burns only the smaller of that and the request at `amt` (line 1407), returning 0 when the reserve is empty, so a thin reserve yields a smaller migration instead of a revert.
- Edges: `ReserveLib.tokenOutForLiquidity (PoolOps.sol:1404), TRUSTED, library`; `IPositionManagerOps.getPositionLiquidity (PoolOps.sol:1405), TRUSTED, out-of-cluster`; `PoolOps.migrateOne (PoolOps.sol:1409), TRUSTED, in-cluster`
- Observations: none

### `migrateOne/function` — PoolOps.sol:1412

- Signature: `function migrateOne( IPositionManagerOps pm, address prevToken, address from, uint256 amount, ReserveRef memory r ) public returns (uint256 got)`
- Authority: anyone directly at the linked library address; in the protocol path, any holder of a previous generation's token, or the keeper batch
- Gate evidence: `if (fromGen == 0 || fromGen >= currentGeneration) revert CannotClaimCurrentGen(); (CauldronRegistry.sol:1306)`
- Reads: `CLAIM_DUST (line 1421, constant)`
- Writes: none
- Value: burns `amount` of the previous generation's token from `from` at `burn` (line 1415) and delivers the live token to the same address at `claimFromReserve` (line 1416)
- Reachability: The 1:1 migration primitive. Reached from `migrateOne` (CauldronRegistry.sol:1322) in `claimByBurn` (CauldronRegistry.sol:1303), from the capacity-aware wrapper at `migrateOne` (line 1412) and from the keeper loop at `migrateOne` (line 1412). Order is burn-then-claim, so the reserve must cover what was destroyed: the shortfall check at `CLAIM_DUST` (line 1421) reverts the whole transaction — rolling the burn back — for anything beyond rounding dust, which exists because reserve sizing rounds down.
- Edges: `ICauldronBurn.burn (PoolOps.sol:1415), UNTRUSTED, out-of-cluster`; `PoolOps.claimFromReserve (PoolOps.sol:1416), TRUSTED, in-cluster`
- Observations: none

### `autoMigrateBatch/function` — PoolOps.sol:1438

- Signature: `function autoMigrateBatch( IPositionManagerOps pm, address prevToken, uint256 fromGen, address[] calldata holders, ReserveRef memory r ) external`
- Authority: anyone directly at the linked library address; in the protocol path, anyone acting as keeper, but only for wallets that opted in
- Gate evidence: `if (claimGate != address(0)) revert VestingEnforced(); (CauldronRegistry.sol:1413)`
- Reads: none
- Writes: none
- Value: per holder, burns their whole previous-generation balance and delivers the same amount of the live token inside `migrateOne` (line 1452)
- Reachability: Delegatecalled from `autoMigrateBatch` (CauldronRegistry.sol:1381), which is permissionless but disabled whenever the vesting escrow is armed at `VestingEnforced` (CauldronRegistry.sol:1414) and refuses the live generation at `CannotClaimCurrentGen` (CauldronRegistry.sol:1410). LOOP: one unbounded pass over the caller-supplied array at `holders` (line 1440) — the caller pays for its own length. Three skips keep it best-effort: not opted in at `autoMigrate` (line 1444), zero balance at `bal` (line 1445), and a reserve that cannot cover this holder IN FULL at `cap` (line 1448), the capacity being re-read every iteration because each migration drains it.
- Edges: `IAutoFlag.autoMigrate (PoolOps.sol:1444), TRUSTED, out-of-cluster`; `IERC20.balanceOf (PoolOps.sol:1445), UNTRUSTED, out-of-cluster`; `ReserveLib.tokenOutForLiquidity (PoolOps.sol:1448), TRUSTED, library`; `IPositionManagerOps.getPositionLiquidity (PoolOps.sol:1449), TRUSTED, out-of-cluster`; `PoolOps.migrateOne (PoolOps.sol:1452), TRUSTED, in-cluster`
- Observations: none

### `doLegacyNote/function` — PoolOps.sol:1462

- Signature: `function doLegacyNote( address ledger, address mifrens, uint256 ogCount, uint256 gen, address genCollection, uint256 tokensBought ) public returns (uint256 ogShare)`
- Authority: anyone directly at the linked library address; in the protocol path, internal to the legacy materialization
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Public in the library but reached in the protocol only from `doLegacyNote` (line 1462) at the end of `materializeLegacy` (line 1493). Two shapes: for a plain brew the whole buyback credits the collection ledger at `credit` (line 1473); for the iteration-2 continuation, where the generation's collection IS the MiFrens contract, the amount splits pro rata by fren count at `ogShare` (line 1465) and only the forged share reaches the ledger at `credit` (line 1473) — the OG share is RETURNED for the caller to fold into the genesis reserve. A zero population returns 0 at `total` (line 1469). The forged count is derived live from `totalMinted` (line 1467) minus the OG tranche.
- Edges: `IColMinted.totalMinted (PoolOps.sol:1467), TRUSTED, out-of-cluster`; `ILedgerOps.credit (PoolOps.sol:1475), TRUSTED, out-of-cluster`; `ILedgerOps.credit (PoolOps.sol:1477), TRUSTED, out-of-cluster`
- Observations: none

### `materializeLegacy/function` — PoolOps.sol:1493

- Signature: `function materializeLegacy( IPositionManagerOps pm, address hook, address registryAddr, address ledger, address mifrens, uint256 genesisShares, uint256 gen, address genColl, address token, ReserveRef memory r, bool toReserve ) external returns (uint256 credited, uint256 ogShare)`
- Authority: anyone directly at the linked library address; in the protocol path, anyone through the facet's permissionless materialization, or the relaunch flush
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: ERC20 transfer of the hook's held live-buyback tokens into the registry at `sweepLegacyReserve` (line 1501); on the relaunch branch those tokens are burned at `burn` (line 1508)
- Reachability: Two entries: the permissionless live path at `materializeLegacy` (RedemptionExt.sol:163) in `materializeLegacyReserve` (RedemptionExt.sol:159), which requires only that the machine is summoned, and the relaunch flush at `materializeLegacy` (CauldronRegistry.sol:1562) in `_flushLegacyAtRelaunch` (CauldronRegistry.sol:1560). It no-ops when the ledger is unwired at `ledger` (line 1492), when the hook points at a different registry at `legacyRegistry` (line 1500) or when nothing is pending at `amt` (line 1501). The `toReserve` (line 1503) flag selects the branch: live deposits into the reserve LP and credits only what the position actually absorbed at `credited` (line 1487), while the relaunch flush BURNS the dead token at `burn` (line 1508) and carries the same figure as a pure ledger number. The live caller credits the returned OG share straight to the genesis reserve (`genesisReserveOutstanding` RedemptionExt.sol:185); the relaunch caller parks it until the fold.
- Edges: `ILegacyHookOps.legacyRegistry (PoolOps.sol:1500), TRUSTED, out-of-cluster`; `ILegacyHookOps.sweepLegacyReserve (PoolOps.sol:1501), TRUSTED, out-of-cluster`; `PoolOps.addToReserve (PoolOps.sol:1504), TRUSTED, in-cluster`; `ICauldronBurn.burn (PoolOps.sol:1508), UNTRUSTED, out-of-cluster`; `PoolOps.doLegacyNote (PoolOps.sol:1510), TRUSTED, in-cluster`
- Observations: none

### `crystallizeCollection/function` — PoolOps.sol:1518

- Signature: `function crystallizeCollection( address ledger, address collection, address vault, uint256 gen, uint256 swept, uint256 activeBase, uint256 totalETH ) external returns (uint256 entitled)`
- Authority: anyone directly at the linked library address; in the protocol path, anyone once the old pool is dead (the gate is on the registry side)
- Gate evidence: `if (!hook.isDead(oldPoolId)) revert TokenStillAlive(); (CauldronRegistry.sol:829)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Delegatecalled once per death from `crystallizeCollection` (CauldronRegistry.sol:1094) inside `relaunch` (CauldronRegistry.sol:812). DENOMINATION: the dying vault's swept ETH is converted into the NEWBORN's token units at `mulDiv` (line 1524) using the new launch ratio activeBase/totalETH, so the entitlement is priced at the new pool's opening price, and the whole call no-ops when `totalETH` (line 1520) is zero, when the wiring is missing or when the generation already crystallized at `crystallized` (line 1516). The claimant base is frozen from the vault's own `outstanding` (line 1525), which already excludes the genesis tranche, and is zero when the generation has no vault.
- Edges: `ILedgerOps.crystallized (PoolOps.sol:1523), TRUSTED, out-of-cluster`; `FullMath.mulDiv (PoolOps.sol:1524), TRUSTED, library`; `IVaultRedeemedOps.outstanding (PoolOps.sol:1531), TRUSTED, out-of-cluster`; `ILedgerOps.crystallize (PoolOps.sol:1532), TRUSTED, out-of-cluster`
- Observations: none

### `_eligible/function` — PoolOps.sol:1564

- Signature: `function _eligible(address collection, uint256 ogCount) private view returns (uint256)`
- Authority: internal (callers: PoolOps.recycleCollection, PoolOps.buyCollection)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called at `_eligible` (PoolOps.sol:1616) and `_eligible` (PoolOps.sol:1655). It subtracts the non-claiming genesis tranche from the live minted count, flooring at zero.
- Edges: `IColMinted.totalMinted (PoolOps.sol:1565), TRUSTED, out-of-cluster`
- Observations: none

### `_ogCount/function` — PoolOps.sol:1570

- Signature: `function _ogCount(address collection) private view returns (uint256 n)`
- Authority: internal (caller: PoolOps.buyCollection)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called at `_ogCount` (PoolOps.sol:1653). A failed or non-32-byte `GENESIS_SUPPLY()` probe yields zero, which is the intended plain-collection default.
- Edges: `IMiFrensShares.GENESIS_SUPPLY (PoolOps.sol:1572), UNTRUSTED, out-of-cluster`
- Observations: none

### `recycleCollection/function` — PoolOps.sol:1576

- Signature: `function recycleCollection( IPositionManagerOps pm, address ledger, address collection, uint256 gen, uint256 tokenId, address caller, ReserveRef memory r ) external returns (uint256 amount)`
- Authority: internal to the registry via delegatecall (external library function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: moves the NFT into registry custody and releases live reserve tokens to `caller` at `custodyTransfer` (PoolOps.sol:1618) and `claimFromReserve` (PoolOps.sol:1619)
- Reachability: Delegatecalled by the registry's collection recycle. It proves ownership, refuses ids above the art count so liquidation badges cannot draw the art floor (`totalMinted` PoolOps.sol:1588), rejects the OG tranche (`ogCount` PoolOps.sol:1613), debits the ledger before the custody transfer, and reverts the entire sequence if reserve output is short beyond CLAIM_DUST (`payout` PoolOps.sol:1622).
- Edges: `ICollectionOps.ownerOf (PoolOps.sol:1585), UNTRUSTED, out-of-cluster`; `IColMinted.totalMinted (PoolOps.sol:1588), TRUSTED, out-of-cluster`; `IMiFrensShares.GENESIS_SUPPLY (PoolOps.sol:1609), UNTRUSTED, out-of-cluster`; `PoolOps._eligible (PoolOps.sol:1616), TRUSTED, in-cluster`; `ILedgerOps.redeem (PoolOps.sol:1617), TRUSTED, out-of-cluster`; `ICollectionOps.custodyTransfer (PoolOps.sol:1618), UNTRUSTED, out-of-cluster`; `PoolOps.claimFromReserve (PoolOps.sol:1619), TRUSTED, in-cluster`
- Observations: none

### `buyCollection/function` — PoolOps.sol:1628

- Signature: `function buyCollection( IPositionManagerOps pm, address ledger, address collection, address token, uint256 gen, uint256 tokenId, address caller, ReserveRef memory r ) external returns (uint256 added)`
- Authority: internal to the registry via delegatecall (external library function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: pulls payment tokens from `caller`, adds them to the reserve, and transfers the treasury NFT to `caller` (PoolOps.sol:1658)
- Reachability: Delegatecalled by the registry's collection buy-back. It requires treasury ownership and an art id, not a badge (`totalMinted` PoolOps.sol:1639), refuses the OG tranche (`ogCount` PoolOps.sol:1654), prices at twice the floor and requires it nonzero (`paid` PoolOps.sol:1657), credits the ledger with what the reserve measurably absorbed (`added` PoolOps.sol:1659), then releases the NFT.
- Edges: `ICollectionOps.ownerOf (PoolOps.sol:1638), UNTRUSTED, out-of-cluster`; `IColMinted.totalMinted (PoolOps.sol:1639), TRUSTED, out-of-cluster`; `PoolOps._ogCount (PoolOps.sol:1653), TRUSTED, in-cluster`; `PoolOps._eligible (PoolOps.sol:1655), TRUSTED, in-cluster`; `ILedgerOps.floorPerNFT (PoolOps.sol:1656), TRUSTED, out-of-cluster`; `IERC20.transferFrom (PoolOps.sol:1658), UNTRUSTED, out-of-cluster`; `PoolOps.addToReserve (PoolOps.sol:1659), TRUSTED, in-cluster`; `ILedgerOps.buyback (PoolOps.sol:1660), TRUSTED, out-of-cluster`; `ICollectionOps.custodyTransfer (PoolOps.sol:1661), UNTRUSTED, out-of-cluster`
- Observations: none
