# Function graph — `seed`

Current source-derived semantic map: **69 nodes** across **5 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `cauldron/CauldronSeeder.sol` | 908 |
| `cauldron/SeedLib.sol` | 147 |
| `cauldron/ISeeder.sol` | 39 |
| `cauldron/MigrationVesting.sol` | 376 |
| `cauldron/LaunchSniper.sol` | 126 |

## `IRegistryOwner (declared in CauldronSeeder.sol)`

### `owner/function` — CauldronSeeder.sol:24

- Signature: `function owner() external view returns (address)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `owner` (CauldronSeeder.sol:24); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `CauldronSeeder`

### `lock/modifier` — CauldronSeeder.sol:204

- Signature: `modifier lock()`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `_locked (line 204)`
- Writes: `_locked (line 204)`
- Value: NONE
- Reachability: Internal body declared at `lock` (CauldronSeeder.sol:204); callers: no executable caller in this cluster.
- Edges: none
- Observations: none

### `onlyRegistry/modifier` — CauldronSeeder.sol:205

- Signature: `modifier onlyRegistry()`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `registry (line 205, immutable)`
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `onlyRegistry` (CauldronSeeder.sol:205); callers: no executable caller in this cluster.
- Edges: none
- Observations: none

### `constructor/constructor` — CauldronSeeder.sol:223

- Signature: `constructor(address _registry, address _positionManager, address _poolManager)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `registry (line 224, immutable)`; `deployer (line 225, immutable)`; `positionManager (line 226, immutable)`; `poolManager (line 227, immutable)`
- Value: NONE
- Reachability: Externally reachable at `constructor` (CauldronSeeder.sol:223); authority is deployer. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `receive/receive` — CauldronSeeder.sol:230

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native through `receive` (line 230)
- Reachability: Externally reachable at `receive` (CauldronSeeder.sol:230); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `startSeed/function` — CauldronSeeder.sol:239

- Signature: `function startSeed(SeederConfig calldata cfg) external payable onlyRegistry lock`
- Authority: registry
- Gate evidence: `onlyRegistry (CauldronSeeder.sol:239)`
- Reads: `seeding (line 240)`; `poolManager (line 294, immutable)`; `gen (line 296)`
- Writes: `_key (line 247)`; `token (line 248)`; `gen (line 249)`; `startTs (line 250)`; `window (line 251)`; `seedFloorWad (line 252)`; `ethTotal (line 253)`; `tokenTotal (line 254)`; `minStepWad (line 255)`; `baseWad (line 256)`; `_spacing (line 257)`; `_bandWidth (line 258)`; `seeding (line 259)`; `complete (line 265)`; `_basePlaced (line 266)`; `_lastEthOut (line 267)`; `_lastTokenOut (line 268)`; `ranges (line 274)`; `_lastAsk (line 276)`; `_lastBid (line 277)`; `_refBlock (line 280)`; `_refTick (line 281)`; `placedWad (line 295)`; `complete (line 296)`
- Value: receives native through `msg.value` (line 243) and pulls ERC20 through `transferFrom` (line 283)
- Reachability: Externally reachable at `startSeed` (CauldronSeeder.sol:239); authority is registry. Gate evidence is recorded separately.
- Edges: `IERC20.transferFrom (CauldronSeeder.sol:283), UNTRUSTED, out-of-cluster`; `CauldronSeeder._syncRef (CauldronSeeder.sol:287), TRUSTED, in-cluster`; `IPoolManager.unlock (CauldronSeeder.sol:294), TRUSTED, out-of-cluster`
- Observations: none

### `poke/function` — CauldronSeeder.sol:303

- Signature: `function poke() external lock`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 312, immutable)`; `poolManager (line 327, immutable)`; `gen (line 328)`; `_refTick (line 328)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `poke` (CauldronSeeder.sol:303); authority is anyone. Gate evidence is recorded separately.
- Edges: `CauldronSeeder._syncRef (CauldronSeeder.sol:308), TRUSTED, in-cluster`; `CauldronSeeder._pendingStep (CauldronSeeder.sol:310), TRUSTED, in-cluster`; `IPoolManager.unlock (CauldronSeeder.sol:312), TRUSTED, out-of-cluster`; `CauldronSeeder._advance (CauldronSeeder.sol:313), TRUSTED, in-cluster`; `CauldronSeeder.primePending (CauldronSeeder.sol:325), TRUSTED, in-cluster`; `IPoolManager.unlock (CauldronSeeder.sol:327), TRUSTED, out-of-cluster`
- Observations: none

### `fundPrime/function` — CauldronSeeder.sol:347

- Signature: `function fundPrime(address to) external payable`
- Authority: deployer or registry owner
- Gate evidence: `if (msg.sender != deployer && msg.sender != IRegistryOwner(registry).owner()) revert OnlyRegistry(); (CauldronSeeder.sol:348)`
- Reads: `deployer (line 348, immutable)`; `registry (line 348, immutable)`; `primeTo (line 361)`; `primeBudget (line 361)`; `primeSpent (line 361)`; `primeBudget (line 364)`
- Writes: `primeTo (line 362)`; `primeBudget (line 363)`
- Value: receives native through `msg.value` (line 363)
- Reachability: Externally reachable at `fundPrime` (CauldronSeeder.sol:347); authority is deployer or registry owner. Gate evidence is recorded separately.
- Edges: `IRegistryOwner.owner (CauldronSeeder.sol:348), TRUSTED, in-cluster`
- Observations: none

### `refundPrime/function` — CauldronSeeder.sol:379

- Signature: `function refundPrime(address to) external lock`
- Authority: deployer or registry owner
- Gate evidence: `if (msg.sender != deployer && msg.sender != IRegistryOwner(registry).owner()) revert OnlyRegistry(); (CauldronSeeder.sol:380)`
- Reads: `deployer (line 380, immutable)`; `registry (line 380, immutable)`; `seeding (line 382)`; `gen (line 382)`
- Writes: `primeBudget (line 383)`; `primeSpent (line 384)`; `primeTo (line 385)`
- Value: sends native to `to` through `call` (line 387)
- Reachability: Externally reachable at `refundPrime` (CauldronSeeder.sol:379); authority is deployer or registry owner. Gate evidence is recorded separately.
- Edges: `IRegistryOwner.owner (CauldronSeeder.sol:380), TRUSTED, in-cluster`; `to.call (CauldronSeeder.sol:387), UNTRUSTED, out-of-cluster`
- Observations: none

### `primePending/function` — CauldronSeeder.sol:397

- Signature: `function primePending() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `primeTo (line 398)`; `primeBudget (line 398)`; `seeding (line 398)`; `placedWad (line 399)`; `primeSpent (line 401)`; `primeBudget (line 404)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `primePending` (CauldronSeeder.sol:397); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `_primeStep/function` — CauldronSeeder.sol:418

- Signature: `function _primeStep(uint256 ethIn) private`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `_refTick (line 425)`; `poolManager (line 428, immutable)`; `_key (line 428)`; `primeTo (line 457)`; `primeSpent (line 458)`; `primeBudget (line 459)`
- Writes: `primeSpent (line 458)`
- Value: sends native through `settle` (line 456) and sends bought token through `take` (line 457)
- Reachability: Internal body declared at `_primeStep` (CauldronSeeder.sol:418); callers: unlockCallback.
- Edges: `TickMath.getSqrtPriceAtTick (CauldronSeeder.sol:427), TRUSTED, library`; `PoolIdLibrary.toId (CauldronSeeder.sol:428), TRUSTED, library`; `StateLibrary.getSlot0 (CauldronSeeder.sol:428), TRUSTED, library`; `IPoolManager.swap (CauldronSeeder.sol:434), TRUSTED, out-of-cluster`; `BalanceDeltaLibrary.amount0 (CauldronSeeder.sol:443), TRUSTED, library`; `BalanceDeltaLibrary.amount1 (CauldronSeeder.sol:444), TRUSTED, library`; `FullMath.mulDiv (CauldronSeeder.sol:452), TRUSTED, library`; `FullMath.mulDiv (CauldronSeeder.sol:453), TRUSTED, library`; `IPoolManager.settle (CauldronSeeder.sol:456), TRUSTED, out-of-cluster`; `IPoolManager.take (CauldronSeeder.sol:457), TRUSTED, out-of-cluster`
- Observations: none

### `pokeInSwap/function` — CauldronSeeder.sol:465

- Signature: `function pokeInSwap() external lock`
- Authority: configured pool hook
- Gate evidence: `if (msg.sender != address(_key.hooks)) revert OnlyHook(); (CauldronSeeder.sol:466)`
- Reads: `_key (line 466)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `pokeInSwap` (CauldronSeeder.sol:465); authority is configured pool hook. Gate evidence is recorded separately.
- Edges: `CauldronSeeder._syncRef (CauldronSeeder.sol:470), TRUSTED, in-cluster`; `CauldronSeeder._pendingStep (CauldronSeeder.sol:471), TRUSTED, in-cluster`; `CauldronSeeder._placeStep (CauldronSeeder.sol:473), TRUSTED, in-cluster`; `CauldronSeeder._advance (CauldronSeeder.sol:474), TRUSTED, in-cluster`
- Observations: none

### `_syncRef/function` — CauldronSeeder.sol:494

- Signature: `function _syncRef() private returns (bool, int24)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 495, immutable)`; `_key (line 495)`; `_refBlock (line 497)`; `_refTick (line 502)`
- Writes: `_refTick (line 498)`; `_refBlock (line 499)`; `_refBlock (line 505)`; `_refTick (line 507)`; `_refTick (line 510)`
- Value: NONE
- Reachability: Internal body declared at `_syncRef` (CauldronSeeder.sol:494); callers: poke, pokeInSwap, startSeed.
- Edges: `PoolIdLibrary.toId (CauldronSeeder.sol:495), TRUSTED, library`; `StateLibrary.getSlot0 (CauldronSeeder.sol:495), TRUSTED, library`
- Observations: none

### `_pendingStep/function` — CauldronSeeder.sol:515

- Signature: `function _pendingStep() private view returns (uint256)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `seeding (line 516)`; `complete (line 516)`; `startTs (line 517)`; `window (line 517)`; `seedFloorWad (line 517)`; `placedWad (line 518)`; `minStepWad (line 520)`
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_pendingStep` (CauldronSeeder.sol:515); callers: poke, pokeInSwap.
- Edges: `SeedLib.deployedTargetWad (CauldronSeeder.sol:517), TRUSTED, in-cluster`
- Observations: none

### `_advance/function` — CauldronSeeder.sol:526

- Signature: `function _advance(uint256 step) private`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `startTs (line 527)`; `window (line 527)`; `seedFloorWad (line 527)`; `placedWad (line 528)`; `poolManager (line 530, immutable)`; `_key (line 530)`; `gen (line 532)`
- Writes: `placedWad (line 529)`; `complete (line 532)`
- Value: NONE
- Reachability: Internal body declared at `_advance` (CauldronSeeder.sol:526); callers: poke, pokeInSwap.
- Edges: `SeedLib.deployedTargetWad (CauldronSeeder.sol:527), TRUSTED, in-cluster`; `PoolIdLibrary.toId (CauldronSeeder.sol:530), TRUSTED, library`; `StateLibrary.getSlot0 (CauldronSeeder.sol:530), TRUSTED, library`
- Observations: none

### `unlockCallback/function` — CauldronSeeder.sol:540

- Signature: `function unlockCallback(bytes calldata data) external returns (bytes memory)`
- Authority: poolManager
- Gate evidence: `if (msg.sender != address(poolManager)) revert OnlyPoolManager(); (CauldronSeeder.sol:541)`
- Reads: `poolManager (line 541, immutable)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `unlockCallback` (CauldronSeeder.sol:540); authority is poolManager. Gate evidence is recorded separately.
- Edges: `CauldronSeeder._placeStep (CauldronSeeder.sol:545), TRUSTED, in-cluster`; `CauldronSeeder._primeStep (CauldronSeeder.sol:548), TRUSTED, in-cluster`; `CauldronSeeder._teardown (CauldronSeeder.sol:551), TRUSTED, in-cluster`
- Observations: none

### `_placeStep/function` — CauldronSeeder.sol:562

- Signature: `function _placeStep(uint256 stepWad) private`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `_basePlaced (line 563)`; `baseWad (line 565)`; `poolManager (line 567, immutable)`; `_key (line 567)`; `tokenTotal (line 569)`; `ethTotal (line 570)`; `_refTick (line 588)`; `_spacing (line 592)`; `_bandWidth (line 592)`
- Writes: `_basePlaced (line 564)`
- Value: NONE
- Reachability: Internal body declared at `_placeStep` (CauldronSeeder.sol:562); callers: pokeInSwap, unlockCallback.
- Edges: `CauldronSeeder._placeBase (CauldronSeeder.sol:565), TRUSTED, in-cluster`; `PoolIdLibrary.toId (CauldronSeeder.sol:567), TRUSTED, library`; `StateLibrary.getSlot0 (CauldronSeeder.sol:567), TRUSTED, library`; `SeedLib.askBand (CauldronSeeder.sol:592), TRUSTED, in-cluster`; `SeedLib.bidBand (CauldronSeeder.sol:594), TRUSTED, in-cluster`; `CauldronSeeder._reserveRange (CauldronSeeder.sol:599), TRUSTED, in-cluster`; `CauldronSeeder._reserveRange (CauldronSeeder.sol:600), TRUSTED, in-cluster`; `LiquidityAmounts.getLiquidityForAmount1 (CauldronSeeder.sol:617), TRUSTED, library`; `TickMath.getSqrtPriceAtTick (CauldronSeeder.sol:618), TRUSTED, library`; `LiquidityAmounts.getLiquidityForAmount0 (CauldronSeeder.sol:622), TRUSTED, library`; `TickMath.getSqrtPriceAtTick (CauldronSeeder.sol:623), TRUSTED, library`; `IPoolManager.modifyLiquidity (CauldronSeeder.sol:629), TRUSTED, out-of-cluster`; `IPoolManager.modifyLiquidity (CauldronSeeder.sol:635), TRUSTED, out-of-cluster`; `CauldronSeeder._settle (CauldronSeeder.sol:640), TRUSTED, in-cluster`
- Observations: none

### `_teardown/function` — CauldronSeeder.sol:645

- Signature: `function _teardown(address to) private`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `ranges (line 646)`; `_key (line 648)`; `poolManager (line 651, immutable)`; `token (line 672)`
- Writes: `_lastEthOut (line 677)`; `_lastTokenOut (line 678)`; `primeBudget (line 688)`; `primeSpent (line 689)`
- Value: sends ERC20 through `transfer` (line 674) and native through `call` (line 676)
- Reachability: Internal body declared at `_teardown` (CauldronSeeder.sol:645); callers: unlockCallback.
- Edges: `PoolIdLibrary.toId (CauldronSeeder.sol:648), TRUSTED, library`; `StateLibrary.getPositionInfo (CauldronSeeder.sol:651), TRUSTED, library`; `IPoolManager.modifyLiquidity (CauldronSeeder.sol:653), TRUSTED, out-of-cluster`; `CauldronSeeder._settle (CauldronSeeder.sol:658), TRUSTED, in-cluster`; `IERC20.balanceOf (CauldronSeeder.sol:673), UNTRUSTED, out-of-cluster`; `IERC20.transfer (CauldronSeeder.sol:674), UNTRUSTED, out-of-cluster`; `to.call (CauldronSeeder.sol:676), UNTRUSTED, out-of-cluster`
- Observations: none

### `_placeBase/function` — CauldronSeeder.sol:701

- Signature: `function _placeBase() private`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 702, immutable)`; `_key (line 702)`; `_spacing (line 703)`; `ethTotal (line 705)`; `baseWad (line 705)`; `tokenTotal (line 706)`; `gen (line 720)`
- Writes: `ranges (line 715)`
- Value: NONE
- Reachability: Internal body declared at `_placeBase` (CauldronSeeder.sol:701); callers: _placeStep.
- Edges: `PoolIdLibrary.toId (CauldronSeeder.sol:702), TRUSTED, library`; `StateLibrary.getSlot0 (CauldronSeeder.sol:702), TRUSTED, library`; `LiquidityAmounts.getLiquidityForAmounts (CauldronSeeder.sol:707), TRUSTED, library`; `TickMath.getSqrtPriceAtTick (CauldronSeeder.sol:708), TRUSTED, library`; `TickMath.getSqrtPriceAtTick (CauldronSeeder.sol:708), TRUSTED, library`; `IPoolManager.modifyLiquidity (CauldronSeeder.sol:716), TRUSTED, out-of-cluster`; `CauldronSeeder._settle (CauldronSeeder.sol:719), TRUSTED, in-cluster`
- Observations: none

### `_settle/function` — CauldronSeeder.sol:727

- Signature: `function _settle(BalanceDelta d) private`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 730, immutable)`; `_key (line 730)`; `token (line 731)`
- Writes: none
- Value: moves ERC20 through `transfer` (line 731) and native through `settle` (line 738)
- Reachability: Internal body declared at `_settle` (CauldronSeeder.sol:727); callers: _placeBase, _placeStep, _reserveRange, _teardown.
- Edges: `BalanceDeltaLibrary.amount1 (CauldronSeeder.sol:728), TRUSTED, library`; `IPoolManager.sync (CauldronSeeder.sol:730), TRUSTED, out-of-cluster`; `IERC20.transfer (CauldronSeeder.sol:731), UNTRUSTED, out-of-cluster`; `IPoolManager.settle (CauldronSeeder.sol:732), TRUSTED, out-of-cluster`; `IPoolManager.take (CauldronSeeder.sol:734), TRUSTED, out-of-cluster`; `BalanceDeltaLibrary.amount0 (CauldronSeeder.sol:736), TRUSTED, library`; `IPoolManager.settle (CauldronSeeder.sol:738), TRUSTED, out-of-cluster`; `IPoolManager.take (CauldronSeeder.sol:740), TRUSTED, out-of-cluster`
- Observations: none

### `_reserveRange/function` — CauldronSeeder.sol:798

- Signature: `function _reserveRange(int24 lo, int24 hi, bool isAsk, int24 tick) private returns (int24, int24)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `ranges (line 799)`; `_spacing (line 800)`; `_lastAsk (line 820)`; `_lastBid (line 820)`
- Writes: `_lastAsk (line 806)`; `_lastBid (line 806)`; `ranges (line 838)`
- Value: NONE
- Reachability: Internal body declared at `_reserveRange` (CauldronSeeder.sol:798); callers: _placeStep.
- Edges: `PoolIdLibrary.toId (CauldronSeeder.sol:826), TRUSTED, library`; `StateLibrary.getPositionInfo (CauldronSeeder.sol:826), TRUSTED, library`; `IPoolManager.modifyLiquidity (CauldronSeeder.sol:828), TRUSTED, out-of-cluster`; `CauldronSeeder._settle (CauldronSeeder.sol:831), TRUSTED, in-cluster`
- Observations: none

### `withdrawAll/function` — CauldronSeeder.sol:850

- Signature: `function withdrawAll(address to) external onlyRegistry lock returns (uint256 ethOut, uint256 tokenOut)`
- Authority: registry
- Gate evidence: `onlyRegistry (CauldronSeeder.sol:850)`
- Reads: `poolManager (line 851, immutable)`; `_lastEthOut (line 853)`; `_lastTokenOut (line 854)`
- Writes: `ranges (line 855)`; `seeding (line 856)`; `complete (line 857)`
- Value: NONE
- Reachability: Externally reachable at `withdrawAll` (CauldronSeeder.sol:850); authority is registry. Gate evidence is recorded separately.
- Edges: `IPoolManager.unlock (CauldronSeeder.sol:851), TRUSTED, out-of-cluster`
- Observations: none

### `rescue/function` — CauldronSeeder.sol:888

- Signature: `function rescue(address to) external onlyRegistry lock`
- Authority: registry
- Gate evidence: `onlyRegistry (CauldronSeeder.sol:888)`
- Reads: `token (line 889)`
- Writes: none
- Value: sends loose ERC20 through `transfer` (line 891) and native through `call` (line 893)
- Reachability: Externally reachable at `rescue` (CauldronSeeder.sol:888); authority is registry. Gate evidence is recorded separately.
- Edges: `IERC20.balanceOf (CauldronSeeder.sol:890), UNTRUSTED, out-of-cluster`; `IERC20.transfer (CauldronSeeder.sol:891), UNTRUSTED, out-of-cluster`; `to.call (CauldronSeeder.sol:893), UNTRUSTED, out-of-cluster`
- Observations: none

### `deployedWad/function` — CauldronSeeder.sol:899

- Signature: `function deployedWad() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `placedWad (line 899)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `deployedWad` (CauldronSeeder.sol:899); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `rangeCount/function` — CauldronSeeder.sol:900

- Signature: `function rangeCount() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `ranges (line 900)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `rangeCount` (CauldronSeeder.sol:900); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `isComplete/function` — CauldronSeeder.sol:901

- Signature: `function isComplete() external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `complete (line 901)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `isComplete` (CauldronSeeder.sol:901); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `priceRef/function` — CauldronSeeder.sol:904

- Signature: `function priceRef() external view returns (int24 refTick, uint64 refBlock)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_refTick (line 905)`; `_refBlock (line 905)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `priceRef` (CauldronSeeder.sol:904); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none


## `ISeeder`

### `startSeed/function` — ISeeder.sol:30

- Signature: `function startSeed(SeederConfig calldata cfg) external payable`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `startSeed` (ISeeder.sol:30); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `poke/function` — ISeeder.sol:31

- Signature: `function poke() external`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `poke` (ISeeder.sol:31); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `withdrawAll/function` — ISeeder.sol:32

- Signature: `function withdrawAll(address to) external returns (uint256 ethOut, uint256 tokenOut)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `withdrawAll` (ISeeder.sol:32); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `rescue/function` — ISeeder.sol:35

- Signature: `function rescue(address to) external`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `rescue` (ISeeder.sol:35); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `isComplete/function` — ISeeder.sol:36

- Signature: `function isComplete() external view returns (bool)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `isComplete` (ISeeder.sol:36); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `seeding/function` — ISeeder.sol:37

- Signature: `function seeding() external view returns (bool)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `seeding` (ISeeder.sol:37); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `IMiFrensGenesisFinalize (declared in LaunchSniper.sol)`

### `igniteCauldron/function` — LaunchSniper.sol:8

- Signature: `function igniteCauldron() external returns (address token)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `igniteCauldron` (LaunchSniper.sol:8); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `soldOut/function` — LaunchSniper.sol:9

- Signature: `function soldOut() external view returns (bool)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `soldOut` (LaunchSniper.sol:9); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `IRegistryCurrent (declared in LaunchSniper.sol)`

### `currentToken/function` — LaunchSniper.sol:13

- Signature: `function currentToken() external view returns (address)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `currentToken` (LaunchSniper.sol:13); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `IGachaPlay (declared in LaunchSniper.sol)`

### `play/function` — LaunchSniper.sol:22

- Signature: `function play( uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax ) external payable returns (uint256)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `play` (LaunchSniper.sol:22); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `LaunchSniper`

### `constructor/constructor` — LaunchSniper.sol:58

- Signature: `constructor(address _owner) Ownable(_owner)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `constructor` (LaunchSniper.sol:58); authority is deployer. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `launch/function` — LaunchSniper.sol:69

- Signature: `function launch( address presale, address registry, address gachaRouter, address airdropWallet, uint256 minGnomeOut, uint256 openMax ) external payable onlyOwner returns (address token, uint256 gnomeBought)`
- Authority: owner
- Gate evidence: `onlyOwner (LaunchSniper.sol:76)`
- Reads: none
- Writes: none
- Value: forwards `msg.value` through `play` (line 92) and sends bought ERC20 through `transfer` (line 96)
- Reachability: Externally reachable at `launch` (LaunchSniper.sol:69); authority is owner. Gate evidence is recorded separately.
- Edges: `IMiFrensGenesisFinalize.soldOut (LaunchSniper.sol:78), UNTRUSTED, in-cluster`; `IMiFrensGenesisFinalize.igniteCauldron (LaunchSniper.sol:81), UNTRUSTED, in-cluster`; `IRegistryCurrent.currentToken (LaunchSniper.sol:82), UNTRUSTED, in-cluster`; `IGachaPlay.play (LaunchSniper.sol:92), UNTRUSTED, in-cluster`; `IERC20.balanceOf (LaunchSniper.sol:95), UNTRUSTED, out-of-cluster`; `IERC20.transfer (LaunchSniper.sol:96), UNTRUSTED, out-of-cluster`
- Observations: none

### `sweep/function` — LaunchSniper.sol:102

- Signature: `function sweep(address tokenAddr) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (LaunchSniper.sol:102)`
- Reads: none
- Writes: none
- Value: sends native through `call` (line 104) or ERC20 through `transfer` (line 107)
- Reachability: Externally reachable at `sweep` (LaunchSniper.sol:102); authority is owner. Gate evidence is recorded separately.
- Edges: `Ownable.owner (LaunchSniper.sol:104), TRUSTED, out-of-cluster`; `owner.call (LaunchSniper.sol:104), UNTRUSTED, out-of-cluster`; `IERC20.transfer (LaunchSniper.sol:107), UNTRUSTED, out-of-cluster`; `Ownable.owner (LaunchSniper.sol:107), TRUSTED, out-of-cluster`; `IERC20.balanceOf (LaunchSniper.sol:107), UNTRUSTED, out-of-cluster`
- Observations: none

### `renounceOwnership/function` — LaunchSniper.sol:120

- Signature: `function renounceOwnership() public pure override`
- Authority: anyone (always reverts)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `renounceOwnership` (LaunchSniper.sol:120); authority is anyone (always reverts). Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `receive/receive` — LaunchSniper.sol:124

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native through `receive` (line 124)
- Reachability: Externally reachable at `receive` (LaunchSniper.sol:124); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none


## `IVestingRegistry (declared in MigrationVesting.sol)`

### `currentGeneration/function` — MigrationVesting.sol:14

- Signature: `function currentGeneration() external view returns (uint256)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `currentGeneration` (MigrationVesting.sol:14); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `generationToken/function` — MigrationVesting.sol:15

- Signature: `function generationToken(uint256 gen) external view returns (address)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `generationToken` (MigrationVesting.sol:15); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `claimByBurn/function` — MigrationVesting.sol:16

- Signature: `function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256 claimedAmount)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `claimByBurn` (MigrationVesting.sol:16); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `IStakerOracle (declared in MigrationVesting.sol)`

### `isInstant/function` — MigrationVesting.sol:24

- Signature: `function isInstant(address who) external view returns (bool)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `isInstant` (MigrationVesting.sol:24); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `MigrationVesting`

### `constructor/constructor` — MigrationVesting.sol:147

- Signature: `constructor( address _registry, address _owner, uint64 _vestWindow, address _stakerOracle ) Ownable(_owner)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: `MIN_WINDOW (line 153, constant)`; `MAX_WINDOW (line 153, constant)`
- Writes: `registry (line 154, immutable)`; `vestWindow (line 155)`; `stakerOracle (line 156)`
- Value: NONE
- Reachability: Externally reachable at `constructor` (MigrationVesting.sol:147); authority is deployer. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `startVest/function` — MigrationVesting.sol:168

- Signature: `function startVest(uint256 fromGen, uint256 amount) external nonReentrant returns (uint256 escrowed)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `startVest` (MigrationVesting.sol:168); authority is anyone. Gate evidence is recorded separately.
- Edges: `MigrationVesting._pullAndVest (MigrationVesting.sol:174), TRUSTED, in-cluster`; `MigrationVesting._release (MigrationVesting.sol:177), TRUSTED, in-cluster`
- Observations: The return comment says `escrowed == amount`, while `_pullAndVest` clamps it to the observed live-token balance delta at `delta` (MigrationVesting.sol:229) (DERIVED).

### `vestBatch/function` — MigrationVesting.sol:191

- Signature: `function vestBatch(uint256 fromGen, address[] calldata holders) external nonReentrant`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `registry (line 194, immutable)`; `_grants (line 196)`; `MAX_BATCH_GRANTS (line 196, constant)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `vestBatch` (MigrationVesting.sol:191); authority is anyone. Gate evidence is recorded separately.
- Edges: `IVestingRegistry.generationToken (MigrationVesting.sol:194), TRUSTED, in-cluster`; `IERC20.balanceOf (MigrationVesting.sol:197), UNTRUSTED, out-of-cluster`; `IERC20.allowance (MigrationVesting.sol:198), UNTRUSTED, out-of-cluster`; `MigrationVesting._pullAndVest (MigrationVesting.sol:201), TRUSTED, in-cluster`
- Observations: none

### `_pullAndVest/function` — MigrationVesting.sol:208

- Signature: `function _pullAndVest(address holder, uint256 fromGen, uint256 amount) private returns (uint256 escrowed)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `registry (line 212, immutable)`; `_grants (line 217)`; `MAX_GRANTS (line 217, constant)`; `vestWindow (line 233)`
- Writes: `_grants (line 234)`
- Value: pulls dead-generation ERC20 through `transferFrom` (line 221) and receives replacement ERC20 through `claimByBurn` (line 227)
- Reachability: Internal body declared at `_pullAndVest` (MigrationVesting.sol:208); callers: startVest, vestBatch.
- Edges: `IVestingRegistry.generationToken (MigrationVesting.sol:212), TRUSTED, in-cluster`; `IERC20.transferFrom (MigrationVesting.sol:221), UNTRUSTED, out-of-cluster`; `IVestingRegistry.currentGeneration (MigrationVesting.sol:223), TRUSTED, in-cluster`; `IVestingRegistry.generationToken (MigrationVesting.sol:224), TRUSTED, in-cluster`; `IERC20.balanceOf (MigrationVesting.sol:226), UNTRUSTED, out-of-cluster`; `IVestingRegistry.claimByBurn (MigrationVesting.sol:227), TRUSTED, in-cluster`; `IERC20.balanceOf (MigrationVesting.sol:229), UNTRUSTED, out-of-cluster`; `MigrationVesting._isInstant (MigrationVesting.sol:233), TRUSTED, in-cluster`
- Observations: none

### `claim/function` — MigrationVesting.sol:249

- Signature: `function claim() external nonReentrant`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `claim` (MigrationVesting.sol:249); authority is anyone. Gate evidence is recorded separately.
- Edges: `MigrationVesting._release (MigrationVesting.sol:250), TRUSTED, in-cluster`
- Observations: none

### `claimFor/function` — MigrationVesting.sol:256

- Signature: `function claimFor(address holder) external nonReentrant`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `claimFor` (MigrationVesting.sol:256); authority is anyone. Gate evidence is recorded separately.
- Edges: `MigrationVesting._release (MigrationVesting.sol:257), TRUSTED, in-cluster`
- Observations: none

### `_release/function` — MigrationVesting.sol:264

- Signature: `function _release(address holder) private returns (uint256 totalMoved)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `_grants (line 265)`
- Writes: `_grants (line 265)`
- Value: sends vested ERC20 through `transfer` (line 286)
- Reachability: Internal body declared at `_release` (MigrationVesting.sol:264); callers: claim, claimFor, startVest.
- Edges: `MigrationVesting._vestedOf (MigrationVesting.sol:268), TRUSTED, in-cluster`; `IERC20.transfer (MigrationVesting.sol:286), UNTRUSTED, out-of-cluster`
- Observations: none

### `_vestedOf/function` — MigrationVesting.sol:301

- Signature: `function _vestedOf(Grant storage grt) private view returns (uint256)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_vestedOf` (MigrationVesting.sol:301); callers: _release, claimable, locked.
- Edges: none
- Observations: none

### `_isInstant/function` — MigrationVesting.sol:308

- Signature: `function _isInstant(address who) private view returns (bool)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `stakerOracle (line 309)`; `stakerOracle (line 312)`
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_isInstant` (MigrationVesting.sol:308); callers: _pullAndVest.
- Edges: `IStakerOracle.isInstant (MigrationVesting.sol:312), UNTRUSTED, in-cluster`
- Observations: none

### `claimable/function` — MigrationVesting.sol:321

- Signature: `function claimable(address holder) external view returns (uint256 total)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_grants (line 322)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `claimable` (MigrationVesting.sol:321); authority is anyone. Gate evidence is recorded separately.
- Edges: `MigrationVesting._vestedOf (MigrationVesting.sol:324), TRUSTED, in-cluster`
- Observations: none

### `locked/function` — MigrationVesting.sol:329

- Signature: `function locked(address holder) external view returns (uint256 total)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_grants (line 330)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `locked` (MigrationVesting.sol:329); authority is anyone. Gate evidence is recorded separately.
- Edges: `MigrationVesting._vestedOf (MigrationVesting.sol:332), TRUSTED, in-cluster`
- Observations: none

### `grantCount/function` — MigrationVesting.sol:337

- Signature: `function grantCount(address holder) external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_grants (line 338)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `grantCount` (MigrationVesting.sol:337); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `grantAt/function` — MigrationVesting.sol:342

- Signature: `function grantAt(address holder, uint256 i) external view returns (Grant memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_grants (line 343)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `grantAt` (MigrationVesting.sol:342); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `setVestWindow/function` — MigrationVesting.sol:352

- Signature: `function setVestWindow(uint64 _window) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (MigrationVesting.sol:352)`
- Reads: `MIN_WINDOW (line 353, constant)`; `MAX_WINDOW (line 353, constant)`
- Writes: `vestWindow (line 354)`
- Value: NONE
- Reachability: Externally reachable at `setVestWindow` (MigrationVesting.sol:352); authority is owner. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `setStakerOracle/function` — MigrationVesting.sol:359

- Signature: `function setStakerOracle(address _oracle) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (MigrationVesting.sol:359)`
- Reads: none
- Writes: `stakerOracle (line 360)`
- Value: NONE
- Reachability: Externally reachable at `setStakerOracle` (MigrationVesting.sol:359); authority is owner. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `renounceOwnership/function` — MigrationVesting.sol:372

- Signature: `function renounceOwnership() public pure override`
- Authority: anyone (always reverts)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `renounceOwnership` (MigrationVesting.sol:372); authority is anyone (always reverts). Gate evidence is recorded separately.
- Edges: none
- Observations: none


## `SeedLib`

### `_alignDown/function` — SeedLib.sol:40

- Signature: `function _alignDown(int24 tick, int24 spacing) internal pure returns (int24)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_alignDown` (SeedLib.sol:40); callers: _bandWidth, askBand, bidBand.
- Edges: none
- Observations: none

### `_alignUp/function` — SeedLib.sol:45

- Signature: `function _alignUp(int24 tick, int24 spacing) internal pure returns (int24)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_alignUp` (SeedLib.sol:45); callers: askBand.
- Edges: none
- Observations: none

### `deployedTargetWad/function` — SeedLib.sol:58

- Signature: `function deployedTargetWad(uint64 startTs, uint64 window, uint256 nowTs, uint256 seedFloorWad) internal pure returns (uint256 wad)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `WAD (line 64, constant)`
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `deployedTargetWad` (SeedLib.sol:58); callers: no executable caller in this cluster.
- Edges: none
- Observations: none

### `askBand/function` — SeedLib.sol:84

- Signature: `function askBand(uint256 i, uint256 n, int24 launchTick, int24 spacing, int24 ceilingOffset) internal pure returns (int24 lower, int24 upper)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `askBand` (SeedLib.sol:84); callers: no executable caller in this cluster.
- Edges: `SeedLib._alignDown (SeedLib.sol:89), TRUSTED, in-cluster`; `SeedLib._bandWidth (SeedLib.sol:90), TRUSTED, in-cluster`; `SeedLib._alignUp (SeedLib.sol:96), TRUSTED, in-cluster`
- Observations: none

### `bidBand/function` — SeedLib.sol:111

- Signature: `function bidBand(uint256 j, uint256 m, int24 launchTick, int24 spacing, int24 floorOffset) internal pure returns (int24 lower, int24 upper)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `bidBand` (SeedLib.sol:111); callers: no executable caller in this cluster.
- Edges: `SeedLib._alignDown (SeedLib.sol:116), TRUSTED, in-cluster`; `SeedLib._bandWidth (SeedLib.sol:117), TRUSTED, in-cluster`; `SeedLib._alignDown (SeedLib.sol:121), TRUSTED, in-cluster`
- Observations: none

### `_bandWidth/function` — SeedLib.sol:128

- Signature: `function _bandWidth(int24 offset, uint256 n, int24 spacing) internal pure returns (int24 w)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_bandWidth` (SeedLib.sol:128); callers: askBand, bidBand.
- Edges: `SeedLib._alignDown (SeedLib.sol:130), TRUSTED, in-cluster`
- Observations: none

### `taperWeightWad/function` — SeedLib.sol:140

- Signature: `function taperWeightWad(uint256 i, uint256 n) internal pure returns (uint256 wad)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `WAD (line 144, constant)`
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `taperWeightWad` (SeedLib.sol:140); callers: no executable caller in this cluster.
- Edges: none
- Observations: none
