# Function graph — `perp`

Current source-derived semantic map: **261 nodes** across **5 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `cauldron/PerpEngine.sol` | 3057 |
| `cauldron/PerpVault.sol` | 973 |
| `cauldron/PerpSwapLib.sol` | 1198 |
| `cauldron/PerpMarkSource.sol` | 212 |
| `cauldron/PerpStakerOracle.sol` | 32 |


## `IPerpRegistry (declared in PerpEngine.sol)`

### `currentToken/function` — PerpEngine.sol:23

- Signature: `function currentToken() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `currentToken` (PerpEngine.sol:23) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `generationQuote/function` — PerpEngine.sol:27

- Signature: `function generationQuote(uint256 gen) external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `generationQuote` (PerpEngine.sol:27) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `currentGeneration/function` — PerpEngine.sol:28

- Signature: `function currentGeneration() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `currentGeneration` (PerpEngine.sol:28) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `lastSummonAt/function` — PerpEngine.sol:29

- Signature: `function lastSummonAt() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `lastSummonAt` (PerpEngine.sol:29) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `generationPoolId/function` — PerpEngine.sol:30

- Signature: `function generationPoolId(uint256) external view returns (PoolId)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `generationPoolId` (PerpEngine.sol:30) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `generationToken/function` — PerpEngine.sol:31

- Signature: `function generationToken(uint256) external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `generationToken` (PerpEngine.sol:31) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `claimByBurn/function` — PerpEngine.sol:32

- Signature: `function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `claimByBurn` (PerpEngine.sol:32) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `claimByBurnUpTo/function` — PerpEngine.sol:33

- Signature: `function claimByBurnUpTo(uint256 fromGen, uint256 maxAmount) external returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `claimByBurnUpTo` (PerpEngine.sol:33) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `IMarkSource (declared in PerpEngine.sol)`

### `weightedTick/function` — PerpEngine.sol:41

- Signature: `function weightedTick() external view returns (int24)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `weightedTick` (PerpEngine.sol:41) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `IPerpVaultStake (declared in PerpEngine.sol)`

### `hasStakers/function` — PerpEngine.sol:46

- Signature: `function hasStakers() external view returns (bool)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `hasStakers` (PerpEngine.sol:46) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `hasQuoteStake/function` — PerpEngine.sol:48

- Signature: `function hasQuoteStake() external view returns (bool)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `hasQuoteStake` (PerpEngine.sol:48) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `IPerpHook (declared in PerpEngine.sol)`

### `isDead/function` — PerpEngine.sol:52

- Signature: `function isDead(PoolId id) external view returns (bool)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `isDead` (PerpEngine.sol:52) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `collection/function` — PerpEngine.sol:54

- Signature: `function collection() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `collection` (PerpEngine.sol:54) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `PerpEngine`

### `_quoteIsNative/function` — PerpEngine.sol:255

- Signature: `function _quoteIsNative() internal view returns (bool)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `quote (line 252)`
- Writes: none
- Value: NONE
- Reachability: SOURCE-REVIEWED: `_quoteIsNative` (PerpEngine.sol:255) only reads quote and compares it to address(0); no writes or calls. Declaration/returns tokens were erroneous extracted edges, not recursion.
- Edges: none
- Observations: none

### `_pullQuote/function` — PerpEngine.sol:263

- Signature: `function _pullQuote(address from, uint256 amount) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `quote (line 274)`
- Writes: none
- Value: receives or validates `msg.value` (line 265)
- Reachability: SOURCE-REVIEWED: `_pullQuote` (PerpEngine.sol:263) requires exact msg.value on native books; ERC20 books reject attached native value then delegatecall the linked transfer library. It credits no counters itself; caller effects revert if the transfer reports failure or decoding reverts.
- Edges: `PerpEngine._quoteIsNative (PerpEngine.sol:264), TRUSTED, in-cluster`; `PerpSwapLib.tryTransferFrom (PerpEngine.sol:274), TRUSTED, delegatecall`
- Observations: External library execution preserves engine address(this)/token allowance context. Return-data validation is not a received-balance check; fee-on-transfer and dishonest tokens require explicit support-policy review.

### `_pushQuote/function` — PerpEngine.sol:281

- Signature: `function _pushQuote(address to, uint256 amount) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `quote (line 287)`
- Writes: none
- Value: sends native through `value` (line 284)
- Reachability: SOURCE-REVIEWED: `_pushQuote` (PerpEngine.sol:281) returns for zero amount, sends native value via recipient callback and reverts EthSend on failure, or uses the checked ERC20 helper. No direct accounting writes; caller state rolls back on failure.
- Edges: `PerpEngine._quoteIsNative (PerpEngine.sol:283), TRUSTED, in-cluster`; `PerpEngine._safeTransfer (PerpEngine.sol:287), TRUSTED, in-cluster`
- Observations: Recipient callback is untrusted. Safety depends on guards and effect ordering at each entrypoint; helper inspection alone is not a global reentrancy proof. Native rejecting-staker rollback is exercised in PerpVaultEngineWriteoffTest.

### `renounceOwnership/function` — PerpEngine.sol:522

- Signature: `function renounceOwnership() public pure override`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `renounceOwnership` (PerpEngine.sol:522) is a public node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.renounceOwnership (PerpEngine.sol:522), TRUSTED, in-cluster`
- Observations: none

### `constructor/constructor` — PerpEngine.sol:562

- Signature: `constructor( IPoolManager _poolManager, address _hook, address _registry, address _mifrens, address _dividend, address _treasury, address _owner ) Ownable(_owner)`
- Authority: deployer (constructor)
- Gate evidence: `UNGATED`
- Reads: `registry (line 582, immutable)`
- Writes: `hookAddr (line 566, immutable)`; `registry (line 566, immutable)`; `dividend (line 567)`; `treasury (line 567)`; `nftBeneficiary (line 568)`; `tierDepthWei (line 569)`; `tierLevPacked (line 570)`; `lastFundingAt (line 571)`; `ring (line 574)`; `observations (line 577)`; `syncedGeneration (line 582)`; `syncedToken (line 583)`
- Value: NONE
- Reachability: Deployment only. Fixes the manager, hook, registry and genesis collection as immutables (`hookAddr` PerpEngine.sol:566), sets the owner through Ownable, seeds default depth tiers (`tierDepthWei` PerpEngine.sol:569), starts the funding clock and the observation ring at the current tick (`_currentTick` PerpEngine.sol:576), and arms the token side for whatever generation is live (`syncedGeneration` PerpEngine.sol:582).
- Edges: `PerpEngine._currentTick (PerpEngine.sol:576), TRUSTED, in-cluster`; `IPerpRegistry.currentGeneration (PerpEngine.sol:582), TRUSTED, out-of-cluster`; `IPerpRegistry.currentToken (PerpEngine.sol:583), TRUSTED, out-of-cluster`
- Observations: none

### `notNested/modifier` — PerpEngine.sol:600

- Signature: `modifier notNested()`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED at current source line 602: invokes _notNested before the wrapped body. The modifier declaration is not a recursive call. One internal call, no direct storage access; historical node location/hash metadata still requires graph refresh.
- Edges: `PerpEngine._notNested (PerpEngine.sol:600), TRUSTED, in-cluster`
- Observations: none

### `onlyVault/modifier` — PerpEngine.sol:601

- Signature: `modifier onlyVault()`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED at current source line 603: invokes _onlyVault before the wrapped body. The modifier declaration is not a recursive call. One internal call, no direct storage access; historical node location/hash metadata still requires graph refresh.
- Edges: `PerpEngine._onlyVault (PerpEngine.sol:601), TRUSTED, in-cluster`
- Observations: none

### `_notNested/function` — PerpEngine.sol:602

- Signature: `function _notNested() internal view`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `_inLocked (line 602)`; `_liqReentry (line 602)`
- Writes: none
- Value: NONE
- Reachability: DERIVED at current source line 604: rejects if _inLocked or _liqReentry is true, with short-circuit evaluation. No calls or writes; Reentrant is a custom error, not an external interaction. Historical node location/hash metadata still requires graph refresh.
- Edges: none
- Observations: none

### `_onlyVault/function` — PerpEngine.sol:603

- Signature: `function _onlyVault() internal view`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `vault (line 603)`
- Writes: none
- Value: NONE
- Reachability: DERIVED at current source line 605: compares msg.sender with configured vault, reverting NotVault on mismatch. No calls or writes. Caller and configuration invariants need separate coverage; historical node location/hash metadata still requires graph refresh.
- Edges: none
- Observations: none

### `totalEth/function` — PerpEngine.sol:608

- Signature: `function totalEth() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `longOiEth (line 608)`; `plv (line 608)`
- Writes: none
- Value: NONE
- Reachability: SOURCE-REVIEWED: anyone can read `totalEth` (PerpEngine.sol:608), returning plv + longOiEth with checked arithmetic. Two reads, no writes, calls or value transfers. Does not include insurance.
- Edges: none
- Observations: none

### `freeEth/function` — PerpEngine.sol:610

- Signature: `function freeEth() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `plv (line 610)`
- Writes: none
- Value: NONE
- Reachability: SOURCE-REVIEWED: anyone can read `freeEth` (PerpEngine.sol:610), returning plv only. One read, no writes, calls or value transfers; lent long principal is excluded.
- Edges: none
- Observations: none

### `totalTokenAssets/function` — PerpEngine.sol:612

- Signature: `function totalTokenAssets() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `plvToken (line 612)`; `shortOiToken (line 612)`
- Writes: none
- Value: NONE
- Reachability: SOURCE-REVIEWED: anyone can read `totalTokenAssets` (PerpEngine.sol:612), returning plvToken + shortOiToken with checked arithmetic. Two reads, no writes, calls or value transfers.
- Edges: none
- Observations: none

### `freeToken/function` — PerpEngine.sol:614

- Signature: `function freeToken() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `plvToken (line 614)`
- Writes: none
- Value: NONE
- Reachability: SOURCE-REVIEWED: anyone can read `freeToken` (PerpEngine.sol:614), returning plvToken only. One read, no writes, calls or value transfers; lent short inventory is excluded.
- Edges: none
- Observations: none

### `_tok/function` — PerpEngine.sol:625

- Signature: `function _tok() internal view returns (address)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `registry (line 625)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_tok` (PerpEngine.sol:625) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `IPerpRegistry.currentToken (PerpEngine.sol:625), UNTRUSTED, in-cluster`; `PerpEngine._tok (PerpEngine.sol:625), TRUSTED, in-cluster`
- Observations: none

### `_gq/function` — PerpEngine.sol:626

- Signature: `function _gq(uint256 g) internal view returns (address)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `registry (line 626)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_gq` (PerpEngine.sol:626) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `IPerpRegistry.generationQuote (PerpEngine.sol:626), UNTRUSTED, in-cluster`; `PerpEngine._gq (PerpEngine.sol:626), TRUSTED, in-cluster`
- Observations: none

### `_bal/function` — PerpEngine.sol:629

- Signature: `function _bal(address t, address who) internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_bal` (PerpEngine.sol:629) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._bal (PerpEngine.sol:629), TRUSTED, in-cluster`
- Observations: none

### `_liq/function` — PerpEngine.sol:630

- Signature: `function _liq() internal view returns (uint128)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 630)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_liq` (PerpEngine.sol:630) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._liq (PerpEngine.sol:630), TRUSTED, in-cluster`; `PerpEngine._pid (PerpEngine.sol:630), TRUSTED, in-cluster`
- Observations: none

### `_col/function` — PerpEngine.sol:631

- Signature: `function _col() internal view returns (address)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `hookAddr (line 631)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_col` (PerpEngine.sol:631) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._col (PerpEngine.sol:631), TRUSTED, in-cluster`
- Observations: none

### `_gen/function` — PerpEngine.sol:632

- Signature: `function _gen() internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `registry (line 632)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_gen` (PerpEngine.sol:632) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `IPerpRegistry.currentGeneration (PerpEngine.sol:632), UNTRUSTED, in-cluster`; `PerpEngine._gen (PerpEngine.sol:632), TRUSTED, in-cluster`
- Observations: none

### `_key/function` — PerpEngine.sol:634

- Signature: `function _key() internal view returns (PoolKey memory)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `POOL_FEE (line 639)`; `TICK_SPACING (line 639)`; `hookAddr (line 639)`; `quote (line 635)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_key` (PerpEngine.sol:634) is a internal node with 4 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._key (PerpEngine.sol:634), TRUSTED, in-cluster`; `PerpEngine._tok (PerpEngine.sol:636), TRUSTED, in-cluster`
- Observations: none

### `_pid/function` — PerpEngine.sol:641

- Signature: `function _pid() internal view returns (PoolId)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_pid` (PerpEngine.sol:641) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._pid (PerpEngine.sol:641), TRUSTED, in-cluster`; `PerpEngine._key (PerpEngine.sol:641), TRUSTED, in-cluster`
- Observations: none

### `_slot0/function` — PerpEngine.sol:643

- Signature: `function _slot0() internal view returns (uint160 s, int24 t)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 643)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_slot0` (PerpEngine.sol:643) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._slot0 (PerpEngine.sol:643), TRUSTED, in-cluster`; `PerpEngine._pid (PerpEngine.sol:643), TRUSTED, in-cluster`
- Observations: none

### `_sqrtP/function` — PerpEngine.sol:644

- Signature: `function _sqrtP() internal view returns (uint160 s)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_sqrtP` (PerpEngine.sol:644) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._sqrtP (PerpEngine.sol:644), TRUSTED, in-cluster`; `PerpEngine._slot0 (PerpEngine.sol:644), TRUSTED, in-cluster`
- Observations: none

### `_q/function` — PerpEngine.sol:696

- Signature: `function _q(uint256 wei18) internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `quoteUnit (line 697)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_q` (PerpEngine.sol:696) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._q (PerpEngine.sol:696), TRUSTED, in-cluster`
- Observations: none

### `_currentTick/function` — PerpEngine.sol:734

- Signature: `function _currentTick() internal view returns (int24 t)`
- Authority: internal (callers: PerpEngine)
- Gate evidence: `UNGATED`
- Reads: `markSource (line 735)`
- Writes: none
- Value: NONE
- Reachability: Mark tick source. If a mark source is configured it is read with a one-word STATICCALL that must return exactly 32 bytes (`ok` PerpEngine.sol:746); the signed answer is accepted only inside the valid tick range before narrowing to int24 (`v` PerpEngine.sol:751). Any failure, short reply or out-of-range value falls back to the primary pool's slot0 tick (`_slot0` PerpEngine.sol:753).
- Edges: `PerpEngine._slot0 (PerpEngine.sol:753), TRUSTED, in-cluster`
- Observations: none

### `poke/function` — PerpEngine.sol:760

- Signature: `function poke() external`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `poke` (PerpEngine.sol:760) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.poke (PerpEngine.sol:760), TRUSTED, in-cluster`; `PerpEngine._pokeFunding (PerpEngine.sol:760), TRUSTED, in-cluster`
- Observations: none

### `_writeObs/function` — PerpEngine.sol:799

- Signature: `function _writeObs() internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `OBS_INTERVAL (line 803)`; `observations (line 803)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_writeObs` (PerpEngine.sol:799) is a internal node with 2 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._writeObs (PerpEngine.sol:799), TRUSTED, in-cluster`; `PerpSwapLib.writeObs (PerpEngine.sol:803), TRUSTED, in-cluster`; `PerpEngine._currentTick (PerpEngine.sol:803), TRUSTED, in-cluster`
- Observations: none

### `twapTick/function` — PerpEngine.sol:824

- Signature: `function twapTick() public view returns (int24 tick, bool ok)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `observations (line 827)`; `twapWindow (line 827)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `twapTick` (PerpEngine.sol:824) is a public node with 2 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.twapTick (PerpEngine.sol:824), TRUSTED, in-cluster`; `PerpSwapLib.twapTick (PerpEngine.sol:827), TRUSTED, in-cluster`
- Observations: none

### `blocksVolumeLink/function` — PerpEngine.sol:881

- Signature: `function blocksVolumeLink() external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `markSource (line 882)`
- Writes: `openCount (line 882)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `blocksVolumeLink` (PerpEngine.sol:881) is a external node with 1 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.blocksVolumeLink (PerpEngine.sol:881), TRUSTED, in-cluster`; `PerpEngine.twapTick (PerpEngine.sol:883), TRUSTED, in-cluster`
- Observations: none

### `markSqrtPriceX96/function` — PerpEngine.sol:887

- Signature: `function markSqrtPriceX96() public view returns (uint160)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `markSqrtPriceX96` (PerpEngine.sol:887) is a public node with 0 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpEngine.markSqrtPriceX96 (PerpEngine.sol:887), TRUSTED, in-cluster`; `PerpEngine.twapTick (PerpEngine.sol:888), TRUSTED, in-cluster`; `PerpSwapLib.sqrtPriceAtTick (PerpEngine.sol:889), TRUSTED, in-cluster`; `PerpEngine._sqrtP (PerpEngine.sol:889), TRUSTED, in-cluster`
- Observations: none

### `activeEthDepth/function` — PerpEngine.sol:892

- Signature: `function activeEthDepth() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `activeEthDepth` (PerpEngine.sol:892) is a public node with 0 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpEngine.activeEthDepth (PerpEngine.sol:892), TRUSTED, in-cluster`; `PerpEngine._sqrtP (PerpEngine.sol:893), TRUSTED, in-cluster`; `PerpSwapLib.ethDepth (PerpEngine.sol:895), TRUSTED, in-cluster`; `PerpEngine._liq (PerpEngine.sol:895), TRUSTED, in-cluster`
- Observations: none

### `maxLeverage/function` — PerpEngine.sol:898

- Signature: `function maxLeverage() public view returns (uint8 lev)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `maxLeverageCeiling (line 908)`; `tierDepthWei (line 903)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `maxLeverage` (PerpEngine.sol:898) is a public node with 2 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine.maxLeverage (PerpEngine.sol:898), TRUSTED, in-cluster`; `PerpEngine.activeEthDepth (PerpEngine.sol:899), TRUSTED, in-cluster`; `PerpEngine._q (PerpEngine.sol:905), TRUSTED, in-cluster`
- Observations: none

### `_quoteAt/function` — PerpEngine.sol:917

- Signature: `function _quoteAt(uint256 size, uint256 sp) internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_quoteAt` (PerpEngine.sol:917) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._quoteAt (PerpEngine.sol:917), TRUSTED, in-cluster`; `PerpSwapLib.quoteAt (PerpEngine.sol:918), TRUSTED, in-cluster`
- Observations: none

### `_quoteEth/function` — PerpEngine.sol:921

- Signature: `function _quoteEth(uint256 size) internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_quoteEth` (PerpEngine.sol:921) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._quoteEth (PerpEngine.sol:921), TRUSTED, in-cluster`; `PerpEngine._quoteAt (PerpEngine.sol:921), TRUSTED, in-cluster`; `PerpEngine._sqrtP (PerpEngine.sol:921), TRUSTED, in-cluster`
- Observations: none

### `_quoteMark/function` — PerpEngine.sol:923

- Signature: `function _quoteMark(uint256 size) internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_quoteMark` (PerpEngine.sol:923) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._quoteMark (PerpEngine.sol:923), TRUSTED, in-cluster`; `PerpEngine._quoteAt (PerpEngine.sol:923), TRUSTED, in-cluster`; `PerpEngine.markSqrtPriceX96 (PerpEngine.sol:923), TRUSTED, in-cluster`
- Observations: none

### `_pokeFunding/function` — PerpEngine.sol:926

- Signature: `function _pokeFunding() internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 941)`; `fundingRateBpsPerDay (line 940)`; `longOiEth (line 936)`; `shortOiToken (line 935)`
- Writes: `fundingIndex (line 942)`; `lastFundingAt (line 928)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_pokeFunding` (PerpEngine.sol:926) is a internal node with 4 direct storage/immutable reads, 2 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._pokeFunding (PerpEngine.sol:926), TRUSTED, in-cluster`; `PerpEngine._writeObs (PerpEngine.sol:927), TRUSTED, in-cluster`; `PerpEngine._quoteMark (PerpEngine.sol:935), TRUSTED, in-cluster`
- Observations: none

### `_fundingDelta/function` — PerpEngine.sol:951

- Signature: `function _fundingDelta(Position memory p) internal view returns (int256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 958)`; `fundingIndex (line 952)`; `maxFundingBps (line 958)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_fundingDelta` (PerpEngine.sol:951) is a internal node with 3 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._fundingDelta (PerpEngine.sol:951), TRUSTED, in-cluster`
- Observations: none

### `_pos/function` — PerpEngine.sol:981

- Signature: `function _pos(uint256 id) internal view returns (Position memory)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `positions (line 981)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_pos` (PerpEngine.sol:981) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._pos (PerpEngine.sol:981), TRUSTED, in-cluster`
- Observations: none

### `fundingDelta/function` — PerpEngine.sol:984

- Signature: `function fundingDelta(uint256 id) external view returns (int256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `fundingDelta` (PerpEngine.sol:984) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine.fundingDelta (PerpEngine.sol:984), TRUSTED, in-cluster`; `PerpEngine._pos (PerpEngine.sol:985), TRUSTED, in-cluster`; `PerpEngine._fundingDelta (PerpEngine.sol:987), TRUSTED, in-cluster`
- Observations: none

### `openLong/function` — PerpEngine.sol:1005

- Signature: `function openLong(uint8 leverage, uint256 minTokenOut, uint256 liqHint, uint256 amount) public payable nonReentrant notNested returns (uint256 id)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `BPS (line 1020)`; `maxOiBps (line 1020)`; `minCollateral (line 1011)`
- Writes: `longOiEth (line 1017)`; `plv (line 1013)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `openLong` (PerpEngine.sol:1005) is a public node with 3 direct storage/immutable reads, 2 direct writes, and 10 resolved call edges.
- Edges: `PerpEngine._openPrologue (PerpEngine.sol:1008), TRUSTED, in-cluster`; `PerpEngine._takeFee (PerpEngine.sol:1010), TRUSTED, in-cluster`; `PerpEngine._q (PerpEngine.sol:1011), TRUSTED, in-cluster`; `PerpEngine._utilGate (PerpEngine.sol:1017), TRUSTED, in-cluster`; `PerpEngine.totalEth (PerpEngine.sol:1017), TRUSTED, in-cluster`; `PerpEngine._checkNotional (PerpEngine.sol:1019), TRUSTED, in-cluster`; `PerpEngine.activeEthDepth (PerpEngine.sol:1020), TRUSTED, in-cluster`; `PerpEngine._swapExactIn (PerpEngine.sol:1023), TRUSTED, in-cluster`; `PerpEngine._book (PerpEngine.sol:1026), TRUSTED, in-cluster`; `PerpEngine._sweepAfterOpen (PerpEngine.sol:1028), TRUSTED, in-cluster`
- Observations: none

### `openShort/function` — PerpEngine.sol:1036

- Signature: `function openShort(uint8 leverage, uint256 minEthOut, uint256 liqHint, uint256 amount) public payable nonReentrant notNested returns (uint256 id)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `BPS (line 1050)`; `maxOiBps (line 1050)`; `minCollateral (line 1042)`
- Writes: `plvToken (line 1047)`; `shortOiToken (line 1049)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `openShort` (PerpEngine.sol:1036) is a public node with 3 direct storage/immutable reads, 2 direct writes, and 12 resolved call edges.
- Edges: `PerpEngine._openPrologue (PerpEngine.sol:1039), TRUSTED, in-cluster`; `PerpEngine._takeFee (PerpEngine.sol:1041), TRUSTED, in-cluster`; `PerpEngine._q (PerpEngine.sol:1042), TRUSTED, in-cluster`; `PerpEngine._checkNotional (PerpEngine.sol:1045), TRUSTED, in-cluster`; `PerpEngine._ethToToken (PerpEngine.sol:1046), TRUSTED, in-cluster`; `PerpEngine._utilGate (PerpEngine.sol:1049), TRUSTED, in-cluster`; `PerpEngine.totalTokenAssets (PerpEngine.sol:1049), TRUSTED, in-cluster`; `PerpEngine._ethToToken (PerpEngine.sol:1050), TRUSTED, in-cluster`; `PerpEngine.activeEthDepth (PerpEngine.sol:1050), TRUSTED, in-cluster`; `PerpEngine._swapExactIn (PerpEngine.sol:1053), TRUSTED, in-cluster`; `PerpEngine._book (PerpEngine.sol:1057), TRUSTED, in-cluster`; `PerpEngine._sweepAfterOpen (PerpEngine.sol:1059), TRUSTED, in-cluster`
- Observations: none

### `close/function` — PerpEngine.sol:1065

- Signature: `function close(uint256 id, uint256 minOut) external nonReentrant notNested`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (p.trader != msg.sender) revert NotTrader(); (PerpEngine.sol:1067)`
- Reads: `MODE_NORMAL (line 1069)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `close` (PerpEngine.sol:1065) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpEngine.close (PerpEngine.sol:1065), TRUSTED, in-cluster`; `PerpEngine._pos (PerpEngine.sol:1066), TRUSTED, in-cluster`; `PerpEngine._pokeFunding (PerpEngine.sol:1068), TRUSTED, in-cluster`; `PerpEngine._settle (PerpEngine.sol:1069), TRUSTED, in-cluster`
- Observations: none

### `liquidate/function` — PerpEngine.sol:1072

- Signature: `function liquidate(uint256 id) external nonReentrant notNested`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MODE_LIQUIDATION (line 1099)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `liquidate` (PerpEngine.sol:1072) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 6 resolved call edges.
- Edges: `PerpEngine.liquidate (PerpEngine.sol:1072), TRUSTED, in-cluster`; `PerpEngine._open (PerpEngine.sol:1073), TRUSTED, in-cluster`; `PerpEngine._pokeFunding (PerpEngine.sol:1074), TRUSTED, in-cluster`; `PerpEngine._liqTest (PerpEngine.sol:1076), TRUSTED, in-cluster`; `PerpEngine._throttle (PerpEngine.sol:1098), TRUSTED, in-cluster`; `PerpEngine._settle (PerpEngine.sol:1099), TRUSTED, in-cluster`
- Observations: none

### `sweepLiquidations/function` — PerpEngine.sol:1129

- Signature: `function sweepLiquidations(address liquidator, int256 spec, bool isBuy, uint160 limit) external returns (uint8 status)`
- Authority: the hook only
- Gate evidence: `if (msg.sender != hookAddr) revert OnlyHook(); (PerpEngine.sol:1133)`
- Reads: `hookAddr (line 1133, immutable)`
- Writes: none
- Value: NONE
- Reachability: Called by the hook before and after every tracked swap; only the hook may call it (`OnlyHook` PerpEngine.sol:1133). It runs the bounded sweep in-place inside the swap's unlock (`_doSweep` PerpEngine.sol:1134) and returns its completion status, which the hook uses to fail the trade closed.
- Edges: `PerpEngine._doSweep (PerpEngine.sol:1134), TRUSTED, in-cluster`
- Observations: none

### `_project/function` — PerpEngine.sol:1141

- Signature: `function _project(int256 spec, bool isBuy, uint160 limit) internal view returns (uint160)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_project` (PerpEngine.sol:1141) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `PerpEngine._project (PerpEngine.sol:1141), TRUSTED, in-cluster`; `PerpEngine.activeEthDepth (PerpEngine.sol:1142), TRUSTED, in-cluster`; `PerpEngine._ethToToken (PerpEngine.sol:1143), TRUSTED, in-cluster`; `PerpSwapLib.projectedSqrtPriceX96 (PerpEngine.sol:1144), TRUSTED, in-cluster`; `PerpEngine._sqrtP (PerpEngine.sol:1145), TRUSTED, in-cluster`
- Observations: none

### `selfSweep/function` — PerpEngine.sol:1153

- Signature: `function selfSweep(address liquidator) external`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (msg.sender != address(this)) revert OnlyHook(); (PerpEngine.sol:1154)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `selfSweep` (PerpEngine.sol:1153) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.selfSweep (PerpEngine.sol:1153), TRUSTED, in-cluster`; `PerpEngine._doSweep (PerpEngine.sol:1155), TRUSTED, in-cluster`
- Observations: none

### `_sweepAfterOpen/function` — PerpEngine.sol:1160

- Signature: `function _sweepAfterOpen(address liquidator) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `gas (line 1164)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_sweepAfterOpen` (PerpEngine.sol:1160) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._sweepAfterOpen (PerpEngine.sol:1160), TRUSTED, in-cluster`; `PerpEngine.selfSweep (PerpEngine.sol:1164), TRUSTED, in-cluster`
- Observations: none

### `_doSweep/function` — PerpEngine.sol:1176

- Signature: `function _doSweep(address liquidator, bool inLocked, int256 spec, bool isBuy, uint160 limit) internal returns (uint8 status)`
- Authority: internal (callers: sweepLiquidations, selfSweep)
- Gate evidence: `UNGATED`
- Reads: `_liqReentry (line 1181)`; `_openIds (line 1193)`; `sweepCursor (line 1201)`
- Writes: `_liqReentry (line 1199)`; `_inLocked (line 1200)`; `_projSqrtP (line 1310)`; `_projSqrtP (line 1384)`; `sweepCursor (line 1408)`; `_inLocked (line 1409)`; `_liqReentry (line 1410)`; `_projSqrtP (line 1411)`
- Value: NONE directly; liquidations it triggers settle positions through the pool (`_tryLiquidate` PerpEngine.sol:1320).
- Reachability: Re-entry guarded (`_liqReentry` PerpEngine.sol:1181); refreshes funding (`_pokeFunding` PerpEngine.sol:1192) and returns clean on an empty book (`len` PerpEngine.sol:1194). With a pending trade it snapshots the open ids (`pendingIds` PerpEngine.sol:1198), projects the post-trade price before each check (`_project` PerpEngine.sol:1310) and liquidates what that projection condemns (`_tryLiquidate` PerpEngine.sol:1320); without one it scans a rotating window from the stored cursor (`cursor` PerpEngine.sol:1301). The kill cap and a gas reserve bound the work (`SWEEP_KILL_RESERVE` PerpEngine.sol:1297); a trade that would condemn more than the cap reports trade-too-large (`SWEEP_TOO_LARGE` PerpEngine.sol:1315). For a pending trade up to four cascade passes re-read the book and kill what earlier kills condemned (`MAX_CASCADE_PASSES` PerpEngine.sol:1373); the trade is certified only when a pass finds nothing condemned remaining (`clean` PerpEngine.sol:1401), otherwise the status becomes trade-too-large (`status` PerpEngine.sol:1405). Flags and the projection are cleared at the end (`_projSqrtP` PerpEngine.sol:1411).
- Edges: `PerpEngine._pokeFunding (PerpEngine.sol:1192), TRUSTED, in-cluster`; `PerpEngine._project (PerpEngine.sol:1310), TRUSTED, in-cluster`; `PerpEngine._pos (PerpEngine.sol:1314), TRUSTED, in-cluster`; `PerpEngine._condemnedByThisTrade (PerpEngine.sol:1315), TRUSTED, in-cluster`; `PerpEngine._tryLiquidate (PerpEngine.sol:1320), TRUSTED, in-cluster`; `PerpEngine._pos (PerpEngine.sol:1381), TRUSTED, in-cluster`; `PerpEngine._condemnedByThisTrade (PerpEngine.sol:1382), TRUSTED, in-cluster`; `PerpEngine._project (PerpEngine.sol:1384), TRUSTED, in-cluster`; `PerpEngine._tryLiquidate (PerpEngine.sol:1385), TRUSTED, in-cluster`
- Observations: The loop comment states that only a pass finding nothing condemned is clean, while the exit at `clean` PerpEngine.sol:1401 also accepts a pass that killed positions and left none condemned, without re-checking survivors scanned earlier in that pass.

### `_condemnedByThisTrade/function` — PerpEngine.sol:1437

- Signature: `function _condemnedByThisTrade(Position memory p) private returns (bool)`
- Authority: internal (callers: _doSweep)
- Gate evidence: `UNGATED`
- Reads: `_projSqrtP (line 1440)`
- Writes: `_projSqrtP (line 1442)`; `_projSqrtP (line 1444)`
- Value: NONE
- Reachability: True only when the position trips at the projected post-trade price (`_liqTest` PerpEngine.sol:1438) but NOT at the price the trade found (`spotTrip` PerpEngine.sol:1443), so a pre-existing backlog never blocks a swap. It temporarily clears the projection to test spot and restores it (`_projSqrtP` PerpEngine.sol:1444); with no projection it returns false (`pj` PerpEngine.sol:1441).
- Edges: `PerpEngine._liqTest (PerpEngine.sol:1438), TRUSTED, in-cluster`; `PerpEngine._liqTest (PerpEngine.sol:1443), TRUSTED, in-cluster`
- Observations: none

### `_tryLiquidate/function` — PerpEngine.sol:1453

- Signature: `function _tryLiquidate(uint256 id, address liquidator) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `MODE_LIQUIDATION (line 1459)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_tryLiquidate` (PerpEngine.sol:1453) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `PerpEngine._tryLiquidate (PerpEngine.sol:1453), TRUSTED, in-cluster`; `PerpEngine._pos (PerpEngine.sol:1454), TRUSTED, in-cluster`; `PerpEngine._liqTest (PerpEngine.sol:1456), TRUSTED, in-cluster`; `PerpEngine._throttle (PerpEngine.sol:1458), TRUSTED, in-cluster`; `PerpEngine._settle (PerpEngine.sol:1459), TRUSTED, in-cluster`
- Observations: none

### `_deadPrep/function` — PerpEngine.sol:1472

- Signature: `function _deadPrep() private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_deadPrep` (PerpEngine.sol:1472) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._deadPrep (PerpEngine.sol:1472), TRUSTED, in-cluster`; `PerpEngine._isDead (PerpEngine.sol:1473), TRUSTED, in-cluster`; `PerpEngine._pokeFunding (PerpEngine.sol:1474), TRUSTED, in-cluster`
- Observations: none

### `_open/function` — PerpEngine.sol:1479

- Signature: `function _open(uint256 id) private view returns (Position memory p)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_open` (PerpEngine.sol:1479) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._open (PerpEngine.sol:1479), TRUSTED, in-cluster`; `PerpEngine._pos (PerpEngine.sol:1480), TRUSTED, in-cluster`
- Observations: none

### `forceCloseDead/function` — PerpEngine.sol:1484

- Signature: `function forceCloseDead(uint256 id) external nonReentrant notNested`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MODE_DEATH (line 1487)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `forceCloseDead` (PerpEngine.sol:1484) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpEngine.forceCloseDead (PerpEngine.sol:1484), TRUSTED, in-cluster`; `PerpEngine._open (PerpEngine.sol:1485), TRUSTED, in-cluster`; `PerpEngine._deadPrep (PerpEngine.sol:1486), TRUSTED, in-cluster`; `PerpEngine._settle (PerpEngine.sol:1487), TRUSTED, in-cluster`
- Observations: none

### `forceCloseAllDead/function` — PerpEngine.sol:1497

- Signature: `function forceCloseAllDead() external nonReentrant notNested`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `FORCE_CLOSE_MAX (line 1506)`; `MODE_DEATH (line 1508)`; `_openIds (line 1507)`; `openCount (line 1506)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `forceCloseAllDead` (PerpEngine.sol:1497) is a external node with 4 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpEngine.forceCloseAllDead (PerpEngine.sol:1497), TRUSTED, in-cluster`; `PerpEngine._deadPrep (PerpEngine.sol:1498), TRUSTED, in-cluster`; `PerpEngine._settle (PerpEngine.sol:1508), TRUSTED, in-cluster`; `PerpEngine._pos (PerpEngine.sol:1508), TRUSTED, in-cluster`
- Observations: none

### `_bookSlots/function` — PerpEngine.sol:1537

- Signature: `function _bookSlots() private pure returns (uint256 s)`
- Authority: internal (callers: requoteBook)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure: packs the compiler-assigned slot numbers and byte offsets of the six requote pots and the quote, mark-source and oracle pointers into one word (`quoteUnit` PerpEngine.sol:1542) for the requote library, which writes the engine's storage by these numbers.
- Edges: none
- Observations: none

### `requoteBook/function` — PerpEngine.sol:1552

- Signature: `function requoteBook(address rot) external nonReentrant`
- Authority: the registry (checked inside the delegatecalled library, against the engine's registry)
- Gate evidence: `if (msg.sender != address(reg)) revert RequoteNotRegistry(); (PerpSwapLib.sol:868)`
- Reads: none
- Writes: none
- Value: Through the library: converts the book's quote-side funds via the rotator (`requoteBookAt` PerpEngine.sol:1568).
- Reachability: Called by the registry during a quote rotation to carry the open book into the new quote. Reentrancy-guarded (`nonReentrant` PerpEngine.sol:1552); it passes the packed pot slots and the positions, open-id, observation and ring reference slots (`positions` PerpEngine.sol:1561) to the library by delegatecall (`requoteBookAt` PerpEngine.sol:1568) and bubbles any revert (`ret` PerpEngine.sol:1570).
- Edges: `PerpEngine._bookSlots (PerpEngine.sol:1558), TRUSTED, in-cluster`; `PerpSwapLib.requoteBookAt (PerpEngine.sol:1568), TRUSTED, delegatecall`
- Observations: none

### `syncGeneration/function` — PerpEngine.sol:1573

- Signature: `function syncGeneration() external nonReentrant notNested`
- Authority: anyone (quote-change write-off path differs for the owner, see the library)
- Gate evidence: `function syncGeneration() external nonReentrant notNested { (PerpEngine.sol:1573)`
- Reads: `syncedGeneration (line 1584)`; `quote (line 1584)`; `openCount (line 1585)`; `syncedToken (line 1593)`; `registry (line 1595, immutable)`; `plvToken (line 1618)`
- Writes: `strandedToken (line 1620)`; `plvToken (line 1623)`; `shortOiToken (line 1624)`; `longOiEth (line 1625)`; `observations (line 1628)`; `ring (line 1629)`; `quote (line 1684)`; `markSource (line 1686)`; `syncedGeneration (line 1688)`; `syncedToken (line 1689)`; `ringArmedAt (line 1699)`
- Value: Migrates the engine's dead-generation token inventory into the new token through the registry (`migrateInventory` PerpEngine.sol:1595); on a quote change the library converts or writes off the empty book's pots (`syncQuoteChangeAt` PerpEngine.sol:1680).
- Reachability: Permissionless re-arm after a relaunch or quote change; reverts when already synced to this generation and quote (`AlreadySynced` PerpEngine.sol:1584) or while any position is open (`PositionsOpen` PerpEngine.sol:1585). Migrates old inventory best-effort, books any shortfall as stranded (`strandedToken` PerpEngine.sol:1620), re-points token inventory at the engine's real balance (`plvToken` PerpEngine.sol:1623), resets open-interest counters and the TWAP ring (`observations` PerpEngine.sol:1628). A quote change delegates to the library, which carries the empty book through a remembered rotator or lets the owner write it off (`syncQuoteChangeAt` PerpEngine.sol:1680); then it adopts the quote, clears the mark source and re-seeds the ring (`ringArmedAt` PerpEngine.sol:1699).
- Edges: `PerpEngine._gen (PerpEngine.sol:1574), TRUSTED, in-cluster`; `PerpEngine._gq (PerpEngine.sol:1583), TRUSTED, in-cluster`; `PerpSwapLib.migrateInventory (PerpEngine.sol:1595), TRUSTED, library`; `PerpEngine._tok (PerpEngine.sol:1600), TRUSTED, in-cluster`; `PerpEngine._bal (PerpEngine.sol:1601), TRUSTED, in-cluster`; `PerpSwapLib.syncQuoteChangeAt (PerpEngine.sol:1680), TRUSTED, delegatecall`; `PerpEngine._bookSlots (PerpEngine.sol:1680), TRUSTED, in-cluster`; `PerpEngine._currentTick (PerpEngine.sol:1700), TRUSTED, in-cluster`
- Observations: none

### `isLiquidatable/function` — PerpEngine.sol:1707

- Signature: `function isLiquidatable(uint256 id) external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `isLiquidatable` (PerpEngine.sol:1707) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine.isLiquidatable (PerpEngine.sol:1707), TRUSTED, in-cluster`; `PerpEngine._pos (PerpEngine.sol:1708), TRUSTED, in-cluster`; `PerpEngine._underwater (PerpEngine.sol:1710), TRUSTED, in-cluster`
- Observations: none

### `_underwater/function` — PerpEngine.sol:1714

- Signature: `function _underwater(Position memory p) internal view returns (bool trip)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_underwater` (PerpEngine.sol:1714) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._underwater (PerpEngine.sol:1714), TRUSTED, in-cluster`; `PerpEngine._liqTest (PerpEngine.sol:1715), TRUSTED, in-cluster`
- Observations: none

### `_liqTest/function` — PerpEngine.sol:1760

- Signature: `function _liqTest(Position memory p) internal view returns (bool trip, bool insolvent, uint256 notional)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_liqTest` (PerpEngine.sol:1760) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 7 resolved call edges.
- Edges: `PerpEngine._liqTest (PerpEngine.sol:1760), TRUSTED, in-cluster`; `PerpEngine._quoteMark (PerpEngine.sol:1761), TRUSTED, in-cluster`; `PerpEngine._underwaterVal (PerpEngine.sol:1762), TRUSTED, in-cluster`; `PerpEngine._insolventVal (PerpEngine.sol:1763), TRUSTED, in-cluster`; `PerpEngine._sqrtP (PerpEngine.sol:1808), TRUSTED, in-cluster`; `PerpEngine._insolventVal (PerpEngine.sol:1809), TRUSTED, in-cluster`; `PerpEngine._quoteAt (PerpEngine.sol:1809), TRUSTED, in-cluster`
- Observations: none

### `_insolventVal/function` — PerpEngine.sol:1817

- Signature: `function _insolventVal(Position memory p, uint256 val) internal pure returns (bool)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_insolventVal` (PerpEngine.sol:1817) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._insolventVal (PerpEngine.sol:1817), TRUSTED, in-cluster`
- Observations: none

### `_throttle/function` — PerpEngine.sol:1843

- Signature: `function _throttle(bool insolvent, uint256 notional) internal returns (bool)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 1845)`; `maxLiqBps (line 1845)`
- Writes: `liqBlock (line 1844)`; `liqEthThisBlock (line 1844)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_throttle` (PerpEngine.sol:1843) is a internal node with 2 direct storage/immutable reads, 2 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._throttle (PerpEngine.sol:1843), TRUSTED, in-cluster`; `PerpEngine.activeEthDepth (PerpEngine.sol:1845), TRUSTED, in-cluster`
- Observations: none

### `_underwaterVal/function` — PerpEngine.sol:1856

- Signature: `function _underwaterVal(Position memory p, uint256 val) internal view returns (bool)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 1859)`; `maintenanceBps (line 1859)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_underwaterVal` (PerpEngine.sol:1856) is a internal node with 2 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._underwaterVal (PerpEngine.sol:1856), TRUSTED, in-cluster`
- Observations: none

### `_ownerFloor/function` — PerpEngine.sol:1870

- Signature: `function _ownerFloor(bool on, uint256 got, uint256 minOut) private pure`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_ownerFloor` (PerpEngine.sol:1870) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._ownerFloor (PerpEngine.sol:1870), TRUSTED, in-cluster`
- Observations: none

### `_settle/function` — PerpEngine.sol:1874

- Signature: `function _settle(uint256 id, Position memory p, uint256 minOut, uint8 mode, address keeper) internal`
- Authority: internal (callers: close, liquidate, forceCloseDead, forceCloseAllDead, _tryLiquidate)
- Gate evidence: `UNGATED`
- Reads: `positions (line 1875)`; `quote (line 1928)`; `syncedToken (line 1928)`; `longOiEth (line 1932)`; `insuranceEth (line 1985)`; `plv (line 1985)`; `liqPenaltyBps (line 2045)`; `keeperBps (line 2047)`
- Writes: `positions (line 1875)`; `openCount (line 1877)`; `longOiEth (line 1932)`; `plv (line 1954)`; `shortOiToken (line 1986)`; `plvToken (line 1987)`; `plv (line 2033)`; `insuranceEth (line 2037)`; `plv (line 2040)`
- Value: Longs: sells the position's tokens into the pool and repays principal to PLV (`_swapExactIn` PerpEngine.sol:1940). Shorts: buys tokens back with backing plus insurance plus PLV (`_buyUpTo` PerpEngine.sol:1985). Pays the keeper reward and the trader's residual (`_payOut` PerpEngine.sol:2050; `_payOut` PerpEngine.sol:2066).
- Reachability: Closes a position in every mode. The position is deleted and removed from the book before any swap (`positions` PerpEngine.sol:1875). Liquidation and death closes are limited to a band around the mark (`bandLimit` PerpEngine.sol:1928); only the trader's own close enforces minOut (`ownerSlippage` PerpEngine.sol:1879). A short that cannot be fully bought back outside death is re-booked under the same id with the unbought size, after the owner floor is checked (`_ownerFloor` PerpEngine.sol:1998; `_rebook` PerpEngine.sol:2007). Funding is then settled against the residual, a debit capped at the residual and a credit paid from insurance then PLV (`fd` PerpEngine.sol:2029); liquidation takes a penalty split to fees and the keeper and awards a badge (`_awardBadge` PerpEngine.sol:2060); death pays a keeper share; the trader receives what remains (`_payOut` PerpEngine.sol:2066).
- Edges: `PerpEngine._removeOpen (PerpEngine.sol:1876), TRUSTED, in-cluster`; `PerpSwapLib.bandLimit (PerpEngine.sol:1928), TRUSTED, library`; `PerpEngine.markSqrtPriceX96 (PerpEngine.sol:1928), TRUSTED, in-cluster`; `PerpEngine._sqrtP (PerpEngine.sol:1928), TRUSTED, in-cluster`; `PerpEngine._swapExactIn (PerpEngine.sol:1940), TRUSTED, in-cluster`; `PerpEngine._ownerFloor (PerpEngine.sol:1941), TRUSTED, in-cluster`; `PerpEngine._writeOffTok (PerpEngine.sol:1952), TRUSTED, in-cluster`; `PerpEngine._replenishPlv (PerpEngine.sol:1959), TRUSTED, in-cluster`; `PerpEngine._buyUpTo (PerpEngine.sol:1985), TRUSTED, in-cluster`; `PerpEngine._absorbPlvLoss (PerpEngine.sol:1992), TRUSTED, in-cluster`; `PerpEngine._ownerFloor (PerpEngine.sol:1998), TRUSTED, in-cluster`; `PerpEngine._rebook (PerpEngine.sol:2007), TRUSTED, in-cluster`; `PerpEngine._writeOffTok (PerpEngine.sol:2011), TRUSTED, in-cluster`; `PerpEngine._ownerFloor (PerpEngine.sol:2013), TRUSTED, in-cluster`; `PerpEngine._fundingDelta (PerpEngine.sol:2029), TRUSTED, in-cluster`; `PerpEngine._routeFee (PerpEngine.sol:2049), TRUSTED, in-cluster`; `PerpEngine._payOut (PerpEngine.sol:2050), TRUSTED, in-cluster`; `PerpEngine._awardBadge (PerpEngine.sol:2060), TRUSTED, in-cluster`; `PerpEngine._killStats (PerpEngine.sol:2060), TRUSTED, in-cluster`; `PerpEngine._payOut (PerpEngine.sol:2064), TRUSTED, in-cluster`; `PerpEngine._payOut (PerpEngine.sol:2066), TRUSTED, in-cluster`
- Observations: none

### `_run/function` — PerpEngine.sol:2084

- Signature: `function _run(SwapReq memory r) internal returns (uint256 spent, uint256 got)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `_inLocked (line 2085)`; `poolManager (line 2086)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_run` (PerpEngine.sol:2084) is a internal node with 2 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._run (PerpEngine.sol:2084), TRUSTED, in-cluster`; `PerpEngine._swapBody (PerpEngine.sol:2085), TRUSTED, in-cluster`; `IPoolManager.unlock (PerpEngine.sol:2086), TRUSTED, out-of-cluster`
- Observations: none

### `_swapExactIn/function` — PerpEngine.sol:2093

- Signature: `function _swapExactIn(bool buy, uint256 amount, uint160 lim) internal returns (uint256 inDone, uint256 out)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_swapExactIn` (PerpEngine.sol:2093) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._run (PerpEngine.sol:2097), TRUSTED, in-cluster`
- Observations: none

### `_buyUpTo/function` — PerpEngine.sol:2123

- Signature: `function _buyUpTo(uint256 tokenOut, uint256 budget, uint160 band) internal returns (uint256 spent, uint256 got)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `quote (line 2131)`; `syncedToken (line 2131)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_buyUpTo` (PerpEngine.sol:2123) is a internal node with 2 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpSwapLib.closeLimit (PerpEngine.sol:2130), TRUSTED, in-cluster`; `PerpEngine._sqrtP (PerpEngine.sol:2131), TRUSTED, in-cluster`; `PerpEngine._liq (PerpEngine.sol:2131), TRUSTED, in-cluster`; `PerpEngine._run (PerpEngine.sol:2133), TRUSTED, in-cluster`
- Observations: none

### `unlockCallback/function` — PerpEngine.sol:2136

- Signature: `function unlockCallback(bytes calldata raw) external returns (bytes memory)`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (msg.sender != address(poolManager)) revert NotTrader(); (PerpEngine.sol:2137)`
- Reads: `poolManager (line 2137)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `unlockCallback` (PerpEngine.sol:2136) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.unlockCallback (PerpEngine.sol:2136), TRUSTED, in-cluster`; `PerpEngine._swapBody (PerpEngine.sol:2138), TRUSTED, in-cluster`
- Observations: none

### `_swapBody/function` — PerpEngine.sol:2145

- Signature: `function _swapBody(SwapReq memory r) internal returns (uint256, uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `nftBeneficiary (line 2163)`; `poolManager (line 2159)`; `syncedToken (line 2154)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_swapBody` (PerpEngine.sol:2145) is a internal node with 3 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._swapBody (PerpEngine.sol:2145), TRUSTED, in-cluster`; `PerpEngine._key (PerpEngine.sol:2146), TRUSTED, in-cluster`; `PerpSwapLib.swapLeg (PerpEngine.sol:2158), TRUSTED, in-cluster`
- Observations: none

### `_openPrologue/function` — PerpEngine.sol:2175

- Signature: `function _openPrologue(uint8 leverage, uint256 amount) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_openPrologue` (PerpEngine.sol:2175) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpEngine._openPrologue (PerpEngine.sol:2175), TRUSTED, in-cluster`; `PerpEngine._pullQuote (PerpEngine.sol:2177), TRUSTED, in-cluster`; `PerpEngine._guardOpen (PerpEngine.sol:2178), TRUSTED, in-cluster`; `PerpEngine._pokeFunding (PerpEngine.sol:2179), TRUSTED, in-cluster`
- Observations: none

### `_guardOpen/function` — PerpEngine.sol:2182

- Signature: `function _guardOpen(uint8 leverage) internal view`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `registry (line 2189)`; `ringArmedAt (line 2190)`; `twapWindow (line 2190)`; `warmup (line 2189)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_guardOpen` (PerpEngine.sol:2182) is a internal node with 4 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpEngine._guardOpen (PerpEngine.sol:2182), TRUSTED, in-cluster`; `IPerpRegistry.lastSummonAt (PerpEngine.sol:2189), UNTRUSTED, in-cluster`; `PerpEngine._isDead (PerpEngine.sol:2192), TRUSTED, in-cluster`; `PerpEngine.maxLeverage (PerpEngine.sol:2193), TRUSTED, in-cluster`
- Observations: none

### `_isDead/function` — PerpEngine.sol:2239

- Signature: `function _isDead() internal view returns (bool)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `hookAddr (line 2254)`; `quote (line 2241)`; `registry (line 2251)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_isDead` (PerpEngine.sol:2239) is a internal node with 3 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `PerpEngine._isDead (PerpEngine.sol:2239), TRUSTED, in-cluster`; `PerpEngine._gen (PerpEngine.sol:2240), TRUSTED, in-cluster`; `PerpEngine._gq (PerpEngine.sol:2241), TRUSTED, in-cluster`; `PerpEngine._pid (PerpEngine.sol:2250), TRUSTED, in-cluster`; `IPerpRegistry.generationPoolId (PerpEngine.sol:2251), UNTRUSTED, in-cluster`
- Observations: none

### `_takeFee/function` — PerpEngine.sol:2256

- Signature: `function _takeFee(uint256 sent, bool longSide) internal returns (uint256 collateral)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 2257)`; `mifrens (line 2258)`; `ogDiscountBps (line 2258)`; `openFeeBps (line 2257)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_takeFee` (PerpEngine.sol:2256) is a internal node with 4 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._takeFee (PerpEngine.sol:2256), TRUSTED, in-cluster`; `PerpEngine._bal (PerpEngine.sol:2258), TRUSTED, in-cluster`; `PerpEngine._routeFee (PerpEngine.sol:2260), TRUSTED, in-cluster`
- Observations: none

### `_checkNotional/function` — PerpEngine.sol:2262

- Signature: `function _checkNotional(uint256 notionalEth) internal view`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 2263)`; `maxNotionalBps (line 2263)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_checkNotional` (PerpEngine.sol:2262) is a internal node with 2 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._checkNotional (PerpEngine.sol:2262), TRUSTED, in-cluster`; `PerpEngine.activeEthDepth (PerpEngine.sol:2263), TRUSTED, in-cluster`
- Observations: none

### `_book/function` — PerpEngine.sol:2265

- Signature: `function _book(address trader, bool isLong, uint256 collateral, uint256 size, uint256 principal, uint8 leverage) internal returns (uint256 id)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `MAX_OPEN_POSITIONS (line 2269)`; `fundingIndex (line 2272)`; `openCount (line 2269)`
- Writes: `nextId (line 2270)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_book` (PerpEngine.sol:2265) is a internal node with 3 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._addOpen (PerpEngine.sol:2271), TRUSTED, in-cluster`
- Observations: none

### `_addOpen/function` — PerpEngine.sol:2282

- Signature: `function _addOpen(uint256 id, Position memory p) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `_openIds (line 2285)`; `_openPos (line 2285)`; `openCount (line 2284)`; `positions (line 2283)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_addOpen` (PerpEngine.sol:2282) is a internal node with 0 direct storage/immutable reads, 4 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._addOpen (PerpEngine.sol:2282), TRUSTED, in-cluster`
- Observations: none

### `_rebook/function` — PerpEngine.sol:2303

- Signature: `function _rebook(uint256 id, Position memory p, uint256 newSize, uint256 newBacking) internal`
- Authority: internal (callers: _settle)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Re-books the unbought part of a partially closed short under the same id: new size, collateral kept but capped at the remaining backing (`collateral` PerpEngine.sol:2306), principal as the remainder (`principal` PerpEngine.sol:2308), and re-added to the open set (`_addOpen` PerpEngine.sol:2309). Funding snapshot is left unchanged, so funding and the liquidation penalty keep a nonzero collateral basis.
- Edges: `PerpEngine._addOpen (PerpEngine.sol:2309), TRUSTED, in-cluster`
- Observations: none

### `_insuranceNeed/function` — PerpEngine.sol:2320

- Signature: `function _insuranceNeed() internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 2321)`; `insuranceFloor (line 2322)`; `longOiEth (line 2321)`; `maintenanceBps (line 2321)`; `shortOiToken (line 2321)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_insuranceNeed` (PerpEngine.sol:2320) is a internal node with 5 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._insuranceNeed (PerpEngine.sol:2320), TRUSTED, in-cluster`; `PerpEngine._quoteEth (PerpEngine.sol:2321), TRUSTED, in-cluster`; `PerpEngine._q (PerpEngine.sol:2322), TRUSTED, in-cluster`
- Observations: none

### `_utilGate/function` — PerpEngine.sol:2326

- Signature: `function _utilGate(uint256 used, uint256 total) private view`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 2328)`; `insuranceEth (line 2354)`; `maxUtilBps (line 2328)`
- Writes: `vault (line 2327)`
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_utilGate` (PerpEngine.sol:2326) is a private node with 3 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._utilGate (PerpEngine.sol:2326), TRUSTED, in-cluster`; `PerpEngine._insuranceNeed (PerpEngine.sol:2353), TRUSTED, in-cluster`
- Observations: none

### `_removeOpen/function` — PerpEngine.sol:2358

- Signature: `function _removeOpen(uint256 id) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `_openIds (line 2361)`; `_openPos (line 2359)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_removeOpen` (PerpEngine.sol:2358) is a internal node with 0 direct storage/immutable reads, 2 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._removeOpen (PerpEngine.sol:2358), TRUSTED, in-cluster`
- Observations: none

### `_ethToToken/function` — PerpEngine.sol:2368

- Signature: `function _ethToToken(uint256 eth) internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_ethToToken` (PerpEngine.sol:2368) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._ethToToken (PerpEngine.sol:2368), TRUSTED, in-cluster`; `PerpSwapLib.ethToToken (PerpEngine.sol:2369), TRUSTED, in-cluster`; `PerpEngine._sqrtP (PerpEngine.sol:2369), TRUSTED, in-cluster`
- Observations: none

### `_routeFee/function` — PerpEngine.sol:2372

- Signature: `function _routeFee(uint256 amount, bool longSide) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 2378)`; `divShareBps (line 2395)`; `dividend (line 2397)`; `insuranceBps (line 2379)`; `treasury (line 2398)`; `vault (line 2377)`; `vaultYieldBps (line 2378)`
- Writes: `insuranceEth (line 2391)`; `plv (line 2386)`; `tokYieldCumulative (line 2389)`; `tokYieldEth (line 2388)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_routeFee` (PerpEngine.sol:2372) is a internal node with 7 direct storage/immutable reads, 4 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._routeFee (PerpEngine.sol:2372), TRUSTED, in-cluster`; `PerpEngine._payOut (PerpEngine.sol:2397), TRUSTED, in-cluster`; `PerpEngine._payOut (PerpEngine.sol:2398), TRUSTED, in-cluster`
- Observations: none

### `_sendEth/function` — PerpEngine.sol:2401

- Signature: `function _sendEth(address to, uint256 amount) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_sendEth` (PerpEngine.sol:2401) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._sendEth (PerpEngine.sol:2401), TRUSTED, in-cluster`; `PerpEngine._pushQuote (PerpEngine.sol:2401), TRUSTED, in-cluster`
- Observations: none

### `_payOut/function` — PerpEngine.sol:2413

- Signature: `function _payOut(address to, uint256 amount) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `payoutOwed (line 2416)`; `payoutOwedTotal (line 2416)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_payOut` (PerpEngine.sol:2413) is a internal node with 0 direct storage/immutable reads, 2 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._payOut (PerpEngine.sol:2413), TRUSTED, in-cluster`; `PerpEngine._tryPush (PerpEngine.sol:2415), TRUSTED, in-cluster`
- Observations: none

### `_tryPush/function` — PerpEngine.sol:2435

- Signature: `function _tryPush(address to, uint256 amount, bool capped) private returns (bool ok)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `gas (line 2437)`; `quote (line 2440)`
- Writes: none
- Value: sends native through `value` (line 2437)
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_tryPush` (PerpEngine.sol:2435) is a private node with 2 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._tryPush (PerpEngine.sol:2435), TRUSTED, in-cluster`; `PerpEngine._quoteIsNative (PerpEngine.sol:2436), TRUSTED, in-cluster`; `PerpSwapLib.tryTransfer (PerpEngine.sol:2440), TRUSTED, in-cluster`
- Observations: none

### `retirePayout/function` — PerpEngine.sol:2495

- Signature: `function retirePayout(address to) external`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `payoutOwed (line 2496)`; `payoutOwedTotal (line 2511)`; `quote (line 2508)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `retirePayout` (PerpEngine.sol:2495) is a external node with 0 direct storage/immutable reads, 3 direct writes, and 5 resolved call edges.
- Edges: `PerpEngine.retirePayout (PerpEngine.sol:2495), TRUSTED, in-cluster`; `PerpEngine.owner (PerpEngine.sol:2503), TRUSTED, out-of-cluster`; `PerpEngine._gq (PerpEngine.sol:2508), TRUSTED, in-cluster`; `PerpEngine._gen (PerpEngine.sol:2508), TRUSTED, in-cluster`; `PerpEngine._tryPush (PerpEngine.sol:2521), TRUSTED, in-cluster`
- Observations: none

### `claimPayout/function` — PerpEngine.sol:2530

- Signature: `function claimPayout() external nonReentrant returns (uint256 amount)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `payoutOwed (line 2531)`; `payoutOwedTotal (line 2534)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `claimPayout` (PerpEngine.sol:2530) is a external node with 0 direct storage/immutable reads, 2 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.claimPayout (PerpEngine.sol:2530), TRUSTED, in-cluster`; `PerpEngine._pushQuote (PerpEngine.sol:2535), TRUSTED, in-cluster`
- Observations: none

### `_bd/function` — PerpEngine.sol:2566

- Signature: `function _bd(uint256 amount, uint256 fromInsurance) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_bd` (PerpEngine.sol:2566) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._bd (PerpEngine.sol:2566), TRUSTED, in-cluster`
- Observations: none

### `_writeOffTok/function` — PerpEngine.sol:2576

- Signature: `function _writeOffTok(uint256 id, uint256 amount, bool isLong) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `plvToken (line 2578)`; `shortOiToken (line 2578)`
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_writeOffTok` (PerpEngine.sol:2576) is a private node with 0 direct storage/immutable reads, 2 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._writeOffTok (PerpEngine.sol:2576), TRUSTED, in-cluster`
- Observations: none

### `_vf/function` — PerpEngine.sol:2582

- Signature: `function _vf(bool ethSide, uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_vf` (PerpEngine.sol:2582) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._vf (PerpEngine.sol:2582), TRUSTED, in-cluster`
- Observations: none

### `_vw/function` — PerpEngine.sol:2583

- Signature: `function _vw(bool ethSide, uint256 amount, address to) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_vw` (PerpEngine.sol:2583) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._vw (PerpEngine.sol:2583), TRUSTED, in-cluster`
- Observations: none

### `_replenishPlv/function` — PerpEngine.sol:2587

- Signature: `function _replenishPlv(uint256 shortfall) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `insuranceEth (line 2588)`; `plv (line 2589)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_replenishPlv` (PerpEngine.sol:2587) is a internal node with 0 direct storage/immutable reads, 2 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._replenishPlv (PerpEngine.sol:2587), TRUSTED, in-cluster`; `PerpEngine._bd (PerpEngine.sol:2590), TRUSTED, in-cluster`
- Observations: none

### `_absorbPlvLoss/function` — PerpEngine.sol:2596

- Signature: `function _absorbPlvLoss(uint256 loss) internal`
- Authority: internal (callers: _settle and loss paths)
- Gate evidence: `UNGATED`
- Reads: `insuranceEth (line 2597)`; `plv (line 2618)`; `unabsorbedEth (line 2623)`
- Writes: `insuranceEth (line 2598)`; `plv (line 2619)`; `unabsorbedEth (line 2622)`
- Value: NONE
- Reachability: Absorbs a settlement loss from insurance first (`fromIns` PerpEngine.sol:2597), then PLV (`covered` PerpEngine.sol:2618); any part neither can cover is recorded as unabsorbed bad debt with an event instead of being silently dropped (`unabsorbedEth` PerpEngine.sol:2622).
- Edges: none
- Observations: none

### `_killStats/function` — PerpEngine.sol:2673

- Signature: `function _killStats(Position memory p, uint256 bounty) internal view returns (LiqStats memory st)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_killStats` (PerpEngine.sol:2673) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine._quoteMark (PerpEngine.sol:2679), TRUSTED, in-cluster`
- Observations: none

### `_awardBadge/function` — PerpEngine.sol:2694

- Signature: `function _awardBadge(uint256 id, address to, LiqStats memory st) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `badgesOwed (line 2708)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_awardBadge` (PerpEngine.sol:2694) is a internal node with 0 direct storage/immutable reads, 1 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._awardBadge (PerpEngine.sol:2694), TRUSTED, in-cluster`; `PerpSwapLib.tryMintBadge (PerpEngine.sol:2706), TRUSTED, in-cluster`; `PerpEngine._col (PerpEngine.sol:2706), TRUSTED, in-cluster`
- Observations: none

### `claimLiquidatorBadges/function` — PerpEngine.sol:2716

- Signature: `function claimLiquidatorBadges(uint256 n) external nonReentrant`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `badgesOwed (line 2717)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `claimLiquidatorBadges` (PerpEngine.sol:2716) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.claimLiquidatorBadges (PerpEngine.sol:2716), TRUSTED, in-cluster`; `PerpEngine._col (PerpEngine.sol:2719), TRUSTED, in-cluster`
- Observations: none

### `_safeTransfer/function` — PerpEngine.sol:2729

- Signature: `function _safeTransfer(address token, address to, uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_safeTransfer` (PerpEngine.sol:2729) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._safeTransfer (PerpEngine.sol:2729), TRUSTED, in-cluster`; `PerpSwapLib.tryTransfer (PerpEngine.sol:2730), TRUSTED, in-cluster`
- Observations: none

### `fundPlv/function` — PerpEngine.sol:2742

- Signature: `function fundPlv(uint256 amount) external payable onlyOwner notNested`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:2742)`
- Reads: none
- Writes: `plv (line 2744)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `fundPlv` (PerpEngine.sol:2742) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.fundPlv (PerpEngine.sol:2742), TRUSTED, in-cluster`; `PerpEngine._pullQuote (PerpEngine.sol:2743), TRUSTED, in-cluster`
- Observations: none

### `fundPlvToken/function` — PerpEngine.sol:2750

- Signature: `function fundPlvToken(uint256 amount) external onlyOwner notNested`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:2750)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `fundPlvToken` (PerpEngine.sol:2750) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.fundPlvToken (PerpEngine.sol:2750), TRUSTED, in-cluster`; `PerpEngine._pullTokenIn (PerpEngine.sol:2751), TRUSTED, in-cluster`
- Observations: none

### `_pullTokenIn/function` — PerpEngine.sol:2755

- Signature: `function _pullTokenIn(uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `plvToken (line 2757)`
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_pullTokenIn` (PerpEngine.sol:2755) is a private node with 0 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine._pullTokenIn (PerpEngine.sol:2755), TRUSTED, in-cluster`; `PerpEngine._tok (PerpEngine.sol:2756), TRUSTED, in-cluster`
- Observations: none

### `fundInsurance/function` — PerpEngine.sol:2761

- Signature: `function fundInsurance(uint256 amount) external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `insuranceEth (line 2763)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `fundInsurance` (PerpEngine.sol:2761) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.fundInsurance (PerpEngine.sol:2761), TRUSTED, in-cluster`; `PerpEngine._pullQuote (PerpEngine.sol:2762), TRUSTED, in-cluster`
- Observations: none

### `creditPerpFee/function` — PerpEngine.sol:2771

- Signature: `function creditPerpFee() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `creditPerpFee` (PerpEngine.sol:2771) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.creditPerpFee (PerpEngine.sol:2771), TRUSTED, in-cluster`; `PerpEngine._creditPerp (PerpEngine.sol:2771), TRUSTED, in-cluster`
- Observations: none

### `creditPerpFeeToken/function` — PerpEngine.sol:2776

- Signature: `function creditPerpFeeToken() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `creditPerpFeeToken` (PerpEngine.sol:2776) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.creditPerpFeeToken (PerpEngine.sol:2776), TRUSTED, in-cluster`; `PerpEngine._creditPerp (PerpEngine.sol:2776), TRUSTED, in-cluster`
- Observations: none

### `creditPerpFeeAsset/function` — PerpEngine.sol:2797

- Signature: `function creditPerpFeeAsset(address asset, uint256 amount) external`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (msg.sender != hookAddr) revert OnlyHook(); (PerpEngine.sol:2798)`
- Reads: `hookAddr (line 2798)`; `quote (line 2801)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `creditPerpFeeAsset` (PerpEngine.sol:2797) is a external node with 2 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.creditPerpFeeAsset (PerpEngine.sol:2797), TRUSTED, in-cluster`; `PerpEngine._pullIntoPlv (PerpEngine.sol:2802), TRUSTED, in-cluster`
- Observations: none

### `_pullIntoPlv/function` — PerpEngine.sol:2807

- Signature: `function _pullIntoPlv(uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `plv (line 2809)`
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_pullIntoPlv` (PerpEngine.sol:2807) is a private node with 0 direct storage/immutable reads, 1 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._pullIntoPlv (PerpEngine.sol:2807), TRUSTED, in-cluster`; `PerpEngine._pullQuote (PerpEngine.sol:2808), TRUSTED, in-cluster`; `PerpEngine._vf (PerpEngine.sol:2810), TRUSTED, in-cluster`
- Observations: none

### `_creditPerp/function` — PerpEngine.sol:2813

- Signature: `function _creditPerp(bool ethSide) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `hookAddr (line 2814)`
- Writes: `plv (line 2832)`; `tokYieldCumulative (line 2835)`; `tokYieldEth (line 2834)`
- Value: receives or validates `msg.value` (line 2817)
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_creditPerp` (PerpEngine.sol:2813) is a private node with 1 direct storage/immutable reads, 3 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._creditPerp (PerpEngine.sol:2813), TRUSTED, in-cluster`; `PerpEngine._quoteIsNative (PerpEngine.sol:2824), TRUSTED, in-cluster`; `PerpEngine._vf (PerpEngine.sol:2837), TRUSTED, in-cluster`
- Observations: none

### `fundFromVault/function` — PerpEngine.sol:2846

- Signature: `function fundFromVault(uint256 amount) external payable onlyVault`
- Authority: configured vault via onlyVault
- Gate evidence: `onlyVault (PerpEngine.sol:2846)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: configured vault via onlyVault; `fundFromVault` (PerpEngine.sol:2846) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.fundFromVault (PerpEngine.sol:2846), TRUSTED, in-cluster`; `PerpEngine._pullIntoPlv (PerpEngine.sol:2847), TRUSTED, in-cluster`
- Observations: none

### `withdrawPlvTo/function` — PerpEngine.sol:2852

- Signature: `function withdrawPlvTo(uint256 amount, address to) external onlyVault notNested nonReentrant`
- Authority: configured vault via onlyVault
- Gate evidence: `onlyVault (PerpEngine.sol:2852)`
- Reads: none
- Writes: `plv (line 2853)`
- Value: NONE
- Reachability: DERIVED from the current body: configured vault via onlyVault; `withdrawPlvTo` (PerpEngine.sol:2852) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.withdrawPlvTo (PerpEngine.sol:2852), TRUSTED, in-cluster`; `PerpEngine._vaultPaid (PerpEngine.sol:2854), TRUSTED, in-cluster`
- Observations: none

### `_vaultPaid/function` — PerpEngine.sol:2859

- Signature: `function _vaultPaid(uint256 amount, address to) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_vaultPaid` (PerpEngine.sol:2859) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._vaultPaid (PerpEngine.sol:2859), TRUSTED, in-cluster`; `PerpEngine._sendEth (PerpEngine.sol:2860), TRUSTED, in-cluster`; `PerpEngine._vw (PerpEngine.sol:2860), TRUSTED, in-cluster`
- Observations: none

### `withdrawTokYieldTo/function` — PerpEngine.sol:2864

- Signature: `function withdrawTokYieldTo(uint256 amount, address to) external onlyVault notNested nonReentrant`
- Authority: configured vault via onlyVault
- Gate evidence: `onlyVault (PerpEngine.sol:2864)`
- Reads: none
- Writes: `tokYieldEth (line 2865)`
- Value: NONE
- Reachability: DERIVED from the current body: configured vault via onlyVault; `withdrawTokYieldTo` (PerpEngine.sol:2864) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.withdrawTokYieldTo (PerpEngine.sol:2864), TRUSTED, in-cluster`; `PerpEngine._vaultPaid (PerpEngine.sol:2866), TRUSTED, in-cluster`
- Observations: none

### `fundTokenFromVault/function` — PerpEngine.sol:2869

- Signature: `function fundTokenFromVault(uint256 amount) external onlyVault`
- Authority: configured vault via onlyVault
- Gate evidence: `onlyVault (PerpEngine.sol:2869)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: configured vault via onlyVault; `fundTokenFromVault` (PerpEngine.sol:2869) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpEngine.fundTokenFromVault (PerpEngine.sol:2869), TRUSTED, in-cluster`; `PerpEngine._pullTokenIn (PerpEngine.sol:2870), TRUSTED, in-cluster`
- Observations: none

### `withdrawPlvTokenTo/function` — PerpEngine.sol:2874

- Signature: `function withdrawPlvTokenTo(uint256 amount, address to) external onlyVault notNested nonReentrant`
- Authority: configured vault via onlyVault
- Gate evidence: `onlyVault (PerpEngine.sol:2874)`
- Reads: none
- Writes: `plvToken (line 2875)`
- Value: NONE
- Reachability: DERIVED from the current body: configured vault via onlyVault; `withdrawPlvTokenTo` (PerpEngine.sol:2874) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 4 resolved call edges.
- Edges: `PerpEngine.withdrawPlvTokenTo (PerpEngine.sol:2874), TRUSTED, in-cluster`; `PerpEngine._safeTransfer (PerpEngine.sol:2877), TRUSTED, in-cluster`; `PerpEngine._tok (PerpEngine.sol:2877), TRUSTED, in-cluster`; `PerpEngine._vw (PerpEngine.sol:2878), TRUSTED, in-cluster`
- Observations: none

### `setFees/function` — PerpEngine.sol:2881

- Signature: `function setFees(uint256 _openBps, uint256 _ogDiscBps, uint256 _liqBps, uint256 _divShareBps, uint256 _keeperBps) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:2881)`
- Reads: `BPS (line 2882)`
- Writes: `divShareBps (line 2883)`; `keeperBps (line 2883)`; `liqPenaltyBps (line 2883)`; `ogDiscountBps (line 2883)`; `openFeeBps (line 2883)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setFees` (PerpEngine.sol:2881) is a external node with 1 direct storage/immutable reads, 5 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.setFees (PerpEngine.sol:2881), TRUSTED, in-cluster`
- Observations: none

### `setRisk/function` — PerpEngine.sol:2885

- Signature: `function setRisk(uint256 _warmup, uint256 _ceiling, uint256 _maintBps, uint256 _maxNotBps, uint256 _maxOiBps, uint256 _fundingBpsDay) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:2885)`
- Reads: `BPS (line 2906)`; `MIN_TWAP (line 2890)`
- Writes: `fundingRateBpsPerDay (line 2909)`; `maintenanceBps (line 2908)`; `maxLeverageCeiling (line 2908)`; `maxNotionalBps (line 2909)`; `maxOiBps (line 2909)`; `warmup (line 2908)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setRisk` (PerpEngine.sol:2885) is a external node with 2 direct storage/immutable reads, 6 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.setRisk (PerpEngine.sol:2885), TRUSTED, in-cluster`
- Observations: none

### `setTiers/function` — PerpEngine.sol:2922

- Signature: `function setTiers(uint256[] calldata depths, uint8[] calldata levs) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:2922)`
- Reads: none
- Writes: `tierDepthWei (line 2925)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setTiers` (PerpEngine.sol:2922) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.setTiers (PerpEngine.sol:2922), TRUSTED, in-cluster`
- Observations: none

### `setRouting/function` — PerpEngine.sol:2944

- Signature: `function setRouting( address _dividend, address _treasury, address _nftBeneficiary, address _markSource, address _quoteOracle ) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:2952)`
- Reads: none
- Writes: `dividend (line 2954)`; `markSource (line 2957)`; `nftBeneficiary (line 2956)`; `treasury (line 2955)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setRouting` (PerpEngine.sol:2944) is a external node with 0 direct storage/immutable reads, 4 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `setVaultSplit/function` — PerpEngine.sol:2963

- Signature: `function setVaultSplit(uint256 _yieldBps, uint256 _insBps) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:2963)`
- Reads: `BPS (line 2964)`
- Writes: `insuranceBps (line 2965)`; `vaultYieldBps (line 2965)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setVaultSplit` (PerpEngine.sol:2963) is a external node with 1 direct storage/immutable reads, 2 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.setVaultSplit (PerpEngine.sol:2963), TRUSTED, in-cluster`
- Observations: none

### `setGuards/function` — PerpEngine.sol:2968

- Signature: `function setGuards(uint32 _twapWindow, uint256 _maxLiqBps, uint256 _maxFundingBps) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:2968)`
- Reads: `BPS (line 2969)`; `MIN_TWAP (line 2969)`
- Writes: `maxFundingBps (line 2970)`; `maxLiqBps (line 2970)`; `twapWindow (line 2970)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setGuards` (PerpEngine.sol:2968) is a external node with 2 direct storage/immutable reads, 3 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.setGuards (PerpEngine.sol:2968), TRUSTED, in-cluster`
- Observations: none

### `setVault/function` — PerpEngine.sol:3002

- Signature: `function setVault(address _vault) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:3002)`
- Reads: none
- Writes: `vault (line 3003)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setVault` (PerpEngine.sol:3002) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.setVault (PerpEngine.sol:3002), TRUSTED, in-cluster`
- Observations: none

### `setVaultLimits/function` — PerpEngine.sol:3008

- Signature: `function setVaultLimits(uint256 _maxUtilBps, uint256 _insuranceFloor) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:3008)`
- Reads: `BPS (line 3009)`
- Writes: `insuranceFloor (line 3010)`; `maxUtilBps (line 3010)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setVaultLimits` (PerpEngine.sol:3008) is a external node with 1 direct storage/immutable reads, 2 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.setVaultLimits (PerpEngine.sol:3008), TRUSTED, in-cluster`
- Observations: none

### `setMinCollateral/function` — PerpEngine.sol:3013

- Signature: `function setMinCollateral(uint256 _minCollateral) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:3013)`
- Reads: none
- Writes: `minCollateral (line 3015)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setMinCollateral` (PerpEngine.sol:3013) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `PerpEngine.setMinCollateral (PerpEngine.sol:3013), TRUSTED, in-cluster`
- Observations: none

### `skimInsurance/function` — PerpEngine.sol:3029

- Signature: `function skimInsurance(uint256 amount, address to) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpEngine.sol:3029)`
- Reads: none
- Writes: `insuranceEth (line 3031)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `skimInsurance` (PerpEngine.sol:3029) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine.skimInsurance (PerpEngine.sol:3029), TRUSTED, in-cluster`; `PerpEngine._insuranceNeed (PerpEngine.sol:3031), TRUSTED, in-cluster`; `PerpEngine._sendEth (PerpEngine.sol:3033), TRUSTED, in-cluster`
- Observations: none

### `positionHealth/function` — PerpEngine.sol:3045

- Signature: `function positionHealth(uint256 id) external view returns ( bool isLong, uint256 markValueEth, uint256 debtOrBackingEth, bool liquidatable )`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `positionHealth` (PerpEngine.sol:3045) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpEngine._pos (PerpEngine.sol:3048), TRUSTED, in-cluster`; `PerpEngine._quoteMark (PerpEngine.sol:3051), TRUSTED, in-cluster`; `PerpEngine._underwater (PerpEngine.sol:3053), TRUSTED, in-cluster`
- Observations: none

### `receive/receive` — PerpEngine.sol:3056

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `receive` (PerpEngine.sol:3056) is a receive node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `PerpMarkSource`

### `renounceOwnership/function` — PerpMarkSource.sol:99

- Signature: `function renounceOwnership() public pure override`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `renounceOwnership` (PerpMarkSource.sol:99) is a public node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpMarkSource.renounceOwnership (PerpMarkSource.sol:99), TRUSTED, in-cluster`
- Observations: none

### `constructor/constructor` — PerpMarkSource.sol:108

- Signature: `constructor(IPoolManager _poolManager, address _owner) Ownable(_owner)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: `_owner (line 108)`
- Writes: `poolManager (line 109)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (PerpMarkSource.sol:108) is a constructor node with 1 direct storage/immutable reads, 1 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `setPrimary/function` — PerpMarkSource.sol:115

- Signature: `function setPrimary(PoolKey calldata key) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpMarkSource.sol:115)`
- Reads: none
- Writes: `armed (line 117)`; `pools (line 118)`; `primary (line 116)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setPrimary` (PerpMarkSource.sol:115) is a external node with 0 direct storage/immutable reads, 3 direct writes, and 1 resolved call edges.
- Edges: `PerpMarkSource.setPrimary (PerpMarkSource.sol:115), TRUSTED, in-cluster`
- Observations: none

### `addPool/function` — PerpMarkSource.sol:126

- Signature: `function addPool(PoolKey calldata key) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpMarkSource.sol:126)`
- Reads: `MAX_POOLS (line 128)`; `armed (line 127)`; `primary (line 130)`
- Writes: `pools (line 128)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `addPool` (PerpMarkSource.sol:126) is a external node with 3 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `PerpMarkSource.addPool (PerpMarkSource.sol:126), TRUSTED, in-cluster`
- Observations: none

### `removePool/function` — PerpMarkSource.sol:147

- Signature: `function removePool(PoolKey calldata key) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (PerpMarkSource.sol:147)`
- Reads: none
- Writes: `pools (line 149)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `removePool` (PerpMarkSource.sol:147) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `PerpMarkSource.removePool (PerpMarkSource.sol:147), TRUSTED, in-cluster`
- Observations: none

### `poolCount/function` — PerpMarkSource.sol:161

- Signature: `function poolCount() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `pools (line 161)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `poolCount` (PerpMarkSource.sol:161) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpMarkSource.poolCount (PerpMarkSource.sol:161), TRUSTED, in-cluster`
- Observations: none

### `weightedTick/function` — PerpMarkSource.sol:173

- Signature: `function weightedTick() external view returns (int24 tick)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `armed (line 183)`; `poolManager (line 186)`; `pools (line 188)`; `primary (line 184)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `weightedTick` (PerpMarkSource.sol:173) is a external node with 4 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpMarkSource.weightedTick (PerpMarkSource.sol:173), TRUSTED, in-cluster`
- Observations: none


## `IPerpShares (declared in PerpStakerOracle.sol)`

### `ethShareOf/function` — PerpStakerOracle.sol:8

- Signature: `function ethShareOf(address who) external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `ethShareOf` (PerpStakerOracle.sol:8) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `tokShareOf/function` — PerpStakerOracle.sol:9

- Signature: `function tokShareOf(address who) external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `tokShareOf` (PerpStakerOracle.sol:9) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `PerpStakerOracle`

### `constructor/constructor` — PerpStakerOracle.sol:24

- Signature: `constructor(address _perpVault)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `perpVault (line 25)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (PerpStakerOracle.sol:24) is a constructor node with 0 direct storage/immutable reads, 1 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `isInstant/function` — PerpStakerOracle.sol:29

- Signature: `function isInstant(address who) external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `perpVault (line 30)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `isInstant` (PerpStakerOracle.sol:29) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpStakerOracle.isInstant (PerpStakerOracle.sol:29), TRUSTED, in-cluster`; `IPerpShares.ethShareOf (PerpStakerOracle.sol:30), TRUSTED, in-cluster`; `IPerpShares.tokShareOf (PerpStakerOracle.sol:30), TRUSTED, in-cluster`
- Observations: none


## `IRequoteEngine (declared in PerpSwapLib.sol)`

### `quote/function` — PerpSwapLib.sol:33

- Signature: `function quote() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `quote` PerpSwapLib.sol:863, `quote` PerpSwapLib.sol:971.
- Edges: none
- Observations: none

### `vault/function` — PerpSwapLib.sol:34

- Signature: `function vault() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `vault` PerpSwapLib.sol:875, `vault` PerpSwapLib.sol:986.
- Edges: none
- Observations: none

### `registry/function` — PerpSwapLib.sol:35

- Signature: `function registry() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `registry` PerpSwapLib.sol:867, `registry` PerpSwapLib.sol:974.
- Edges: none
- Observations: none

### `syncedGeneration/function` — PerpSwapLib.sol:36

- Signature: `function syncedGeneration() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `syncedGeneration` PerpSwapLib.sol:871.
- Edges: none
- Observations: none

### `payoutOwedTotal/function` — PerpSwapLib.sol:37

- Signature: `function payoutOwedTotal() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `payoutOwedTotal` PerpSwapLib.sol:873, `payoutOwedTotal` PerpSwapLib.sol:970.
- Edges: none
- Observations: none

### `owner/function` — PerpSwapLib.sol:38

- Signature: `function owner() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `owner` PerpSwapLib.sol:980.
- Edges: none
- Observations: none

### `treasury/function` — PerpSwapLib.sol:39

- Signature: `function treasury() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `treasury` PerpSwapLib.sol:994.
- Edges: none
- Observations: none

### `poke/function` — PerpSwapLib.sol:40

- Signature: `function poke() external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `poke` PerpSwapLib.sol:877.
- Edges: none
- Observations: none


## `IVaultQuoteStake (declared in PerpSwapLib.sol)`

### `hasQuoteStake/function` — PerpSwapLib.sol:44

- Signature: `function hasQuoteStake() external view returns (bool)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `hasQuoteStake` PerpSwapLib.sol:987.
- Edges: none
- Observations: none


## `IRequoteRegistry (declared in PerpSwapLib.sol)`

### `currentGeneration/function` — PerpSwapLib.sol:48

- Signature: `function currentGeneration() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `currentGeneration` PerpSwapLib.sol:869, `currentGeneration` PerpSwapLib.sol:975.
- Edges: none
- Observations: none

### `generationQuote/function` — PerpSwapLib.sol:49

- Signature: `function generationQuote(uint256 gen) external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `generationQuote` PerpSwapLib.sol:870, `generationQuote` PerpSwapLib.sol:975.
- Edges: none
- Observations: none


## `IRequoteRotator (declared in PerpSwapLib.sol)`

### `quoteOracle/function` — PerpSwapLib.sol:54

- Signature: `function quoteOracle() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `quoteOracle` PerpSwapLib.sol:912.
- Edges: none
- Observations: none

### `venueFor/function` — PerpSwapLib.sol:55

- Signature: `function venueFor(address a, address b) external view returns (PoolKey memory route, bool ok)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `venueFor` PerpSwapLib.sol:1109.
- Edges: none
- Observations: none

### `swapOnce/function` — PerpSwapLib.sol:56

- Signature: `function swapOnce(PoolKey calldata route, address from, address to, uint256 amountIn, uint256 minOut) external returns (uint256 out)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `swapOnce` PerpSwapLib.sol:1120.
- Edges: none
- Observations: none

### `withdraw/function` — PerpSwapLib.sol:59

- Signature: `function withdraw(address asset, address to, uint256 amount) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; the requote path calls it at `withdraw` PerpSwapLib.sol:1121.
- Edges: none
- Observations: none


## `PerpSwapLib`

### `unitOf/function` — PerpSwapLib.sol:119

- Signature: `function unitOf(address q) external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `unitOf` (PerpSwapLib.sol:119) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpSwapLib.unitOf (PerpSwapLib.sol:119), TRUSTED, in-cluster`; `PerpSwapLib._unitOf (PerpSwapLib.sol:120), TRUSTED, in-cluster`
- Observations: none

### `_unitOf/function` — PerpSwapLib.sol:123

- Signature: `function _unitOf(address q) private view returns (uint256)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_unitOf` (PerpSwapLib.sol:123) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpSwapLib._unitOf (PerpSwapLib.sol:123), TRUSTED, in-cluster`; `IERC20.decimals (PerpSwapLib.sol:125), TRUSTED, out-of-cluster`; `IERC20Metadata.decimals (PerpSwapLib.sol:125), TRUSTED, out-of-cluster`
- Observations: none

### `quoteFactor/function` — PerpSwapLib.sol:156

- Signature: `function quoteFactor(address oracle, address q) external view returns (uint256 f)`
- Authority: anyone (external library function; engine reaches it by delegatecall)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Thin external wrapper over the private helper (`_quoteFactor` PerpSwapLib.sol:157); pure view, no storage.
- Edges: `PerpSwapLib._quoteFactor (PerpSwapLib.sol:157), TRUSTED, in-cluster`
- Observations: none

### `_quoteFactor/function` — PerpSwapLib.sol:160

- Signature: `function _quoteFactor(address oracle, address q) private view returns (uint256 f)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Native quote returns 1e18 at once (`q` PerpSwapLib.sol:161). With an oracle it returns the native-to-quote USD price ratio (`mulDiv` PerpSwapLib.sol:167) when both prices are nonzero; a zero price or zero ratio falls through to the decimals unit (`_unitOf` PerpSwapLib.sol:171), which is clamped to 1e18 below 1e6 (`f` PerpSwapLib.sol:172). Read-only.
- Edges: `PerpSwapLib._usdPerRawUnit (PerpSwapLib.sol:163), TRUSTED, in-cluster`; `PerpSwapLib._usdPerRawUnit (PerpSwapLib.sol:164), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpSwapLib.sol:167), TRUSTED, library`; `PerpSwapLib._unitOf (PerpSwapLib.sol:171), TRUSTED, in-cluster`
- Observations: none

### `_usdPerRawUnit/function` — PerpSwapLib.sol:175

- Signature: `function _usdPerRawUnit(address oracle, address q) private view returns (uint256)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_usdPerRawUnit` (PerpSwapLib.sol:175) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpSwapLib._usdPerRawUnit (PerpSwapLib.sol:175), TRUSTED, in-cluster`; `QuoteOracle.usdPerRawUnit (PerpSwapLib.sol:177), TRUSTED, out-of-cluster`
- Observations: none

### `projectedSqrtPriceX96/function` — PerpSwapLib.sol:227

- Signature: `function projectedSqrtPriceX96( uint160 sqrtP, uint256 reserveIn, uint256 reserveOut, int256 amountSpecified, bool isBuy, uint160 limit ) external pure returns (uint160)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `SLACK_BPS (line 264)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `projectedSqrtPriceX96` (PerpSwapLib.sol:227) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `FullMath.mulDiv (PerpSwapLib.sol:272), TRUSTED, library`; `FullMath.mulDiv (PerpSwapLib.sol:305), TRUSTED, library`
- Observations: none

### `twapTick/function` — PerpSwapLib.sol:334

- Signature: `function twapTick( Observation[OBS_CARDINALITY] storage observations, Ring storage r, uint32 twapWindow ) external view returns (int24 tick, bool ok)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MIN_TWAP (line 344)`; `OBS_CARDINALITY (line 350)`; `OBS_MASK (line 349)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `twapTick` (PerpSwapLib.sol:334) is a external node with 3 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `writeObs/function` — PerpSwapLib.sol:390

- Signature: `function writeObs( Observation[OBS_CARDINALITY] storage observations, Ring storage r, uint32 obsInterval, int24 currentTick ) external`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `OBS_MASK (line 405)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `writeObs` (PerpSwapLib.sol:390) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `sqrtPriceAtTick/function` — PerpSwapLib.sol:419

- Signature: `function sqrtPriceAtTick(int24 t) external pure returns (uint160)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `sqrtPriceAtTick` (PerpSwapLib.sol:419) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpSwapLib.sqrtPriceAtTick (PerpSwapLib.sol:419), TRUSTED, in-cluster`
- Observations: none

### `tryMintBadge/function` — PerpSwapLib.sol:437

- Signature: `function tryMintBadge(address col, address to, LiqStats memory st) external returns (bool ok)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `tryMintBadge` (PerpSwapLib.sol:437) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpSwapLib.tryMintBadge (PerpSwapLib.sol:437), TRUSTED, in-cluster`; `ILiquidatorMintable.mintLiquidatorWithStats (PerpSwapLib.sol:442), TRUSTED, out-of-cluster`; `ILiquidatorMintable.mintLiquidator (PerpSwapLib.sol:447), TRUSTED, out-of-cluster`
- Observations: none

### `quoteAt/function` — PerpSwapLib.sol:458

- Signature: `function quoteAt(uint256 size, uint256 sp) external pure returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `Q96X (line 459)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `quoteAt` (PerpSwapLib.sol:458) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpSwapLib.quoteAt (PerpSwapLib.sol:458), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpSwapLib.sol:459), TRUSTED, library`
- Observations: none

### `ethToToken/function` — PerpSwapLib.sol:463

- Signature: `function ethToToken(uint256 eth, uint256 sp) external pure returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `Q96X (line 464)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `ethToToken` (PerpSwapLib.sol:463) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpSwapLib.ethToToken (PerpSwapLib.sol:463), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpSwapLib.sol:464), TRUSTED, library`
- Observations: none

### `ethDepth/function` — PerpSwapLib.sol:469

- Signature: `function ethDepth(uint128 L, uint160 sp) external pure returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `Q96X (line 472)`; `SQRT_MAX (line 471)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `ethDepth` (PerpSwapLib.sol:469) is a external node with 2 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpSwapLib.ethDepth (PerpSwapLib.sol:469), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpSwapLib.sol:471), TRUSTED, library`; `FullMath.mulDiv (PerpSwapLib.sol:472), TRUSTED, library`
- Observations: none

### `tryTransferFrom/function` — PerpSwapLib.sol:490

- Signature: `function tryTransferFrom(address token, address from, uint256 amount) external returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `tryTransferFrom` (PerpSwapLib.sol:490) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpSwapLib.tryTransferFrom (PerpSwapLib.sol:490), TRUSTED, in-cluster`; `IERC20.transferFrom (PerpSwapLib.sol:492), UNTRUSTED, out-of-cluster`
- Observations: none

### `tryTransfer/function` — PerpSwapLib.sol:498

- Signature: `function tryTransfer(address token, address to, uint256 amount) external returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `tryTransfer` (PerpSwapLib.sol:498) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpSwapLib.tryTransfer (PerpSwapLib.sol:498), TRUSTED, in-cluster`; `IERC20.transfer (PerpSwapLib.sol:500), UNTRUSTED, out-of-cluster`
- Observations: none

### `swapLeg/function` — PerpSwapLib.sol:532

- Signature: `function swapLeg( IPoolManager poolManager, PoolKey memory key, Req memory r, bool quoteIsCurrency0, bytes memory hookData ) external returns (uint256 spent, uint256 got)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MIN_LIMIT (line 554)`; `SQRT_MAX (line 554)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `swapLeg` (PerpSwapLib.sol:532) is a external node with 2 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `IPoolManager.swap (PerpSwapLib.sol:564), TRUSTED, out-of-cluster`; `PerpSwapLib._settle (PerpSwapLib.sol:577), TRUSTED, in-cluster`; `IPoolManager.take (PerpSwapLib.sol:578), TRUSTED, out-of-cluster`; `PerpSwapLib._settle (PerpSwapLib.sol:582), TRUSTED, in-cluster`; `IPoolManager.take (PerpSwapLib.sol:583), TRUSTED, out-of-cluster`
- Observations: none

### `_settle/function` — PerpSwapLib.sol:589

- Signature: `function _settle(IPoolManager poolManager, Currency c, uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native through `value` (line 592)
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_settle` (PerpSwapLib.sol:589) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpSwapLib._settle (PerpSwapLib.sol:589), TRUSTED, in-cluster`; `IPoolManager.settle (PerpSwapLib.sol:592), TRUSTED, out-of-cluster`; `IPoolManager.sync (PerpSwapLib.sol:594), TRUSTED, out-of-cluster`; `IPoolManager.settle (PerpSwapLib.sol:603), TRUSTED, out-of-cluster`
- Observations: none

### `migrateInventory/function` — PerpSwapLib.sol:627

- Signature: `function migrateInventory(address registry, address oldToken, uint256 fromGen) external returns (uint256 migratedIn)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `migrateInventory` (PerpSwapLib.sol:627) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `CauldronRegistry.claimByBurnUpTo (PerpSwapLib.sol:634), TRUSTED, in-cluster`
- Observations: none

### `spendLimit/function` — PerpSwapLib.sol:676

- Signature: `function spendLimit(uint160 sp, uint128 L, uint256 budget, bool down) external pure returns (uint160)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `spendLimit` (PerpSwapLib.sol:676) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpSwapLib._spend (PerpSwapLib.sol:681), TRUSTED, in-cluster`
- Observations: none

### `bandLimit/function` — PerpSwapLib.sol:722

- Signature: `function bandLimit(uint160 mark, uint160 sp, bool buy, bool quoteIsCurrency0) external pure returns (uint160)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `bandLimit` (PerpSwapLib.sol:722) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpSwapLib._band (PerpSwapLib.sol:727), TRUSTED, in-cluster`
- Observations: none

### `closeLimit/function` — PerpSwapLib.sol:744

- Signature: `function closeLimit(uint160 sp, uint128 L, uint256 budget, bool down, uint160 band) external pure returns (uint160)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `closeLimit` (PerpSwapLib.sol:744) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpSwapLib._spend (PerpSwapLib.sol:749), TRUSTED, in-cluster`
- Observations: none

### `_band/function` — PerpSwapLib.sol:753

- Signature: `function _band(uint160 mark, uint160 sp, bool buy) private pure returns (uint160)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `MIN_LIMIT (line 759)`; `SQRT_MAX (line 763)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_band` (PerpSwapLib.sol:753) is a private node with 2 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpSwapLib._band (PerpSwapLib.sol:753), TRUSTED, in-cluster`
- Observations: none

### `_spend/function` — PerpSwapLib.sol:766

- Signature: `function _spend(uint160 sp, uint128 L, uint256 budget, bool down) private pure returns (uint160)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `MIN_LIMIT (line 771)`; `Q96X (line 774)`; `SQRT_MAX (line 771)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_spend` (PerpSwapLib.sol:766) is a private node with 3 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `FullMath.mulDiv (PerpSwapLib.sol:774), TRUSTED, library`; `FullMath.mulDiv (PerpSwapLib.sol:775), TRUSTED, library`; `FullMath.mulDiv (PerpSwapLib.sol:779), TRUSTED, library`
- Observations: none

### `_requoteBook/function` — PerpSwapLib.sol:854

- Signature: `function _requoteBook( mapping(uint256 => Position) storage positions, uint256[] storage openIds, Observation[OBS_CARDINALITY] storage observations, Ring storage ring, address rot, uint256 slots ) internal`
- Authority: the engine's registry (checked against the engine's own registry getter)
- Gate evidence: `if (msg.sender != address(reg)) revert RequoteNotRegistry(); (PerpSwapLib.sol:868)`
- Reads: `ROT_SLOT (line 897, constant)`
- Writes: none
- Value: Moves the book's quote-side funds through the rotator: sends the old quote to `rot` and withdraws the new quote back (via `_convert` PerpSwapLib.sol:883).
- Reachability: Entered only through `requoteBookAt` PerpSwapLib.sol:1032, which the engine delegatecalls. The caller must be the engine's registry (`RequoteNotRegistry` PerpSwapLib.sol:868). It returns without effect when the generation's quote already equals the engine's or the engine is not synced to the live generation (`syncedGeneration` PerpSwapLib.sol:871), and reverts while payouts are owed (`RequotePayoutsOwed` PerpSwapLib.sol:873). Otherwise it settles funding on the old pool (`poke` PerpSwapLib.sol:877), notifies the vault (`_vaultHook` PerpSwapLib.sol:879), converts PLV, insurance, token-yield ETH and short backing through the rotator (`_convert` PerpSwapLib.sol:883), restates positions and pots at the realised rate (`_restatePositions` PerpSwapLib.sol:885; `_restatePots` PerpSwapLib.sol:886), writes the new quote and clears the mark source (`_stAddr` PerpSwapLib.sol:891), shifts the TWAP ring (`_shiftRing` PerpSwapLib.sol:894), remembers the rotator (`ROT_SLOT` PerpSwapLib.sol:897) and reports old and new totals to the vault (`_vaultHook` PerpSwapLib.sol:899). Any failing step reverts the whole requote.
- Edges: `IRequoteEngine.quote (PerpSwapLib.sol:863), TRUSTED, in-cluster`; `IRequoteEngine.registry (PerpSwapLib.sol:867), TRUSTED, in-cluster`; `IRequoteRegistry.currentGeneration (PerpSwapLib.sol:869), TRUSTED, out-of-cluster`; `IRequoteRegistry.generationQuote (PerpSwapLib.sol:870), TRUSTED, out-of-cluster`; `IRequoteEngine.syncedGeneration (PerpSwapLib.sol:871), TRUSTED, in-cluster`; `IRequoteEngine.payoutOwedTotal (PerpSwapLib.sol:873), TRUSTED, in-cluster`; `PerpSwapLib._factors (PerpSwapLib.sol:874), TRUSTED, in-cluster`; `IRequoteEngine.vault (PerpSwapLib.sol:875), TRUSTED, in-cluster`; `IRequoteEngine.poke (PerpSwapLib.sol:877), TRUSTED, in-cluster`; `PerpSwapLib._vaultHook (PerpSwapLib.sol:879), TRUSTED, in-cluster`; `PerpSwapLib._ld (PerpSwapLib.sol:881), TRUSTED, in-cluster`; `PerpSwapLib._shortBacking (PerpSwapLib.sol:882), TRUSTED, in-cluster`; `PerpSwapLib._convert (PerpSwapLib.sol:883), TRUSTED, in-cluster`; `PerpSwapLib._restatePositions (PerpSwapLib.sol:885), TRUSTED, in-cluster`; `PerpSwapLib._restatePots (PerpSwapLib.sol:886), TRUSTED, in-cluster`; `PerpSwapLib._st (PerpSwapLib.sol:887), TRUSTED, in-cluster`; `PerpSwapLib._stAddr (PerpSwapLib.sol:891), TRUSTED, in-cluster`; `PerpSwapLib._shiftRing (PerpSwapLib.sol:894), TRUSTED, in-cluster`; `PerpSwapLib._vaultHook (PerpSwapLib.sol:899), TRUSTED, in-cluster`
- Observations: none

### `_factors/function` — PerpSwapLib.sol:911

- Signature: `function _factors(address rot, address oq, address nq) private view returns (uint256 fOld, uint256 fNew)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Reads the rotator's oracle (`quoteOracle` PerpSwapLib.sol:912) and returns strict factors for the old and new quote (`_factorStrict` PerpSwapLib.sol:913); either being unpriceable reverts.
- Edges: `IRequoteRotator.quoteOracle (PerpSwapLib.sol:912), UNTRUSTED, out-of-cluster`; `PerpSwapLib._factorStrict (PerpSwapLib.sol:913), TRUSTED, in-cluster`; `PerpSwapLib._factorStrict (PerpSwapLib.sol:914), TRUSTED, in-cluster`
- Observations: none

### `_restatePots/function` — PerpSwapLib.sol:921

- Signature: `function _restatePots(uint256 slots, uint256 got, uint256 spent, uint256 shortsNew, uint256 fOld, uint256 fNew) private returns (uint256 newPlv, uint256 kNum, uint256 kDen)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Splits the converted amount back into pots in proportion to what was spent: insurance and token-yield ETH scale by got/spent (`mulDiv` PerpSwapLib.sol:928), PLV takes the remainder after the restated shorts (`newPlv` PerpSwapLib.sol:931), and the cumulative token-yield figure and the quote unit are rescaled (`_st` PerpSwapLib.sol:938; `_st` PerpSwapLib.sol:939). With nothing spent it rescales by the oracle factors instead (`kNum` PerpSwapLib.sol:937). Writes engine slots by number, never by name.
- Edges: `PerpSwapLib._ld (PerpSwapLib.sol:928), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpSwapLib.sol:928), TRUSTED, library`; `PerpSwapLib._st (PerpSwapLib.sol:932), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpSwapLib.sol:938), TRUSTED, library`
- Observations: none

### `syncQuoteChangeAt/function` — PerpSwapLib.sol:968

- Signature: `function syncQuoteChangeAt(uint256 slots) external`
- Authority: anyone reaching it through the engine's generation sync; non-owners carry through the remembered rotator, the owner may write off
- Gate evidence: `UNGATED`
- Reads: `ROT_SLOT (line 978, constant)`
- Writes: none
- Value: Owner path: sends the old-quote PLV, insurance and token-yield balance to the engine's treasury, native with a 30,000 gas stipend or an ERC20 transfer, both best-effort (`tre` PerpSwapLib.sol:998; `transfer` PerpSwapLib.sol:1001). Carry path: converts through the rotator (`_carryEmpty` PerpSwapLib.sol:982).
- Reachability: The quote-change half of the engine's generation sync, run on an empty book. It reverts while payouts are owed (`VaultStaked` PerpSwapLib.sol:970). If a rotation was ever carried (`rot` PerpSwapLib.sol:979) and the caller is not the owner, the empty book's pots convert through that rotator and return (`_carryEmpty` PerpSwapLib.sol:982). Otherwise a non-owner is refused while the vault holds quote-side stake (`hasQuoteStake` PerpSwapLib.sol:987); the old-quote pots are zeroed (`_st` PerpSwapLib.sol:991), best-effort sent to the treasury (`tre` PerpSwapLib.sol:994) and the quote unit is re-derived for the new quote (`_quoteFactor` PerpSwapLib.sol:1005).
- Edges: `IRequoteEngine.payoutOwedTotal (PerpSwapLib.sol:970), TRUSTED, in-cluster`; `IRequoteEngine.quote (PerpSwapLib.sol:971), TRUSTED, in-cluster`; `IRequoteEngine.registry (PerpSwapLib.sol:974), TRUSTED, in-cluster`; `IRequoteRegistry.generationQuote (PerpSwapLib.sol:975), TRUSTED, out-of-cluster`; `IRequoteRegistry.currentGeneration (PerpSwapLib.sol:975), TRUSTED, out-of-cluster`; `IRequoteEngine.owner (PerpSwapLib.sol:980), TRUSTED, in-cluster`; `PerpSwapLib._carryEmpty (PerpSwapLib.sol:982), TRUSTED, in-cluster`; `IRequoteEngine.vault (PerpSwapLib.sol:982), TRUSTED, in-cluster`; `IRequoteEngine.vault (PerpSwapLib.sol:986), TRUSTED, in-cluster`; `IVaultQuoteStake.hasQuoteStake (PerpSwapLib.sol:987), UNTRUSTED, out-of-cluster`; `PerpSwapLib._ld (PerpSwapLib.sol:988), TRUSTED, in-cluster`; `PerpSwapLib._st (PerpSwapLib.sol:991), TRUSTED, in-cluster`; `IRequoteEngine.treasury (PerpSwapLib.sol:994), TRUSTED, in-cluster`; `PerpSwapLib._quoteFactor (PerpSwapLib.sol:1005), TRUSTED, in-cluster`; `PerpSwapLib._ldAddr (PerpSwapLib.sol:1005), TRUSTED, in-cluster`
- Observations: none

### `_carryEmpty/function` — PerpSwapLib.sol:1009

- Signature: `function _carryEmpty(address rot, address oq, address nq, uint256 slots, address vault) private`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: Converts the empty book's quote-side pots through the rotator (`_convert` PerpSwapLib.sol:1014).
- Reachability: Empty-book carry used by the sync when a rotation was remembered: strict factors (`_factors` PerpSwapLib.sol:1010), vault pre-hook (`_vaultHook` PerpSwapLib.sol:1011), convert PLV, insurance and token-yield ETH (`_convert` PerpSwapLib.sol:1014), restate pots with no shorts (`_restatePots` PerpSwapLib.sol:1015) and report totals to the vault (`_vaultHook` PerpSwapLib.sol:1016). All-or-nothing.
- Edges: `PerpSwapLib._factors (PerpSwapLib.sol:1010), TRUSTED, in-cluster`; `PerpSwapLib._vaultHook (PerpSwapLib.sol:1011), TRUSTED, in-cluster`; `PerpSwapLib._ld (PerpSwapLib.sol:1012), TRUSTED, in-cluster`; `PerpSwapLib._convert (PerpSwapLib.sol:1014), TRUSTED, in-cluster`; `PerpSwapLib._restatePots (PerpSwapLib.sol:1015), TRUSTED, in-cluster`; `PerpSwapLib._vaultHook (PerpSwapLib.sol:1016), TRUSTED, in-cluster`
- Observations: none

### `_ldAddr/function` — PerpSwapLib.sol:1025

- Signature: `function _ldAddr(uint256 slots, uint256 at) private view returns (address a)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Loads an address packed in an engine slot: slot number and byte offset come from the packed descriptor (`sh` PerpSwapLib.sol:1027), then a masked SLOAD (`a` PerpSwapLib.sol:1028). No named storage.
- Edges: none
- Observations: none

### `requoteBookAt/function` — PerpSwapLib.sol:1032

- Signature: `function requoteBookAt(address rot, uint256 slots, uint256 refs) external`
- Authority: anyone (external library function); effective gate is the registry check inside the requote body
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: External entry the engine delegatecalls with its packed slot and reference descriptors. It rebuilds storage pointers (`_posAt` PerpSwapLib.sol:1034; `_obsAt` PerpSwapLib.sol:1035) and runs the requote (`_requoteBook` PerpSwapLib.sol:1033), whose registry check is the real gate. Called on the library directly it would act on the library's own empty storage.
- Edges: `PerpSwapLib._requoteBook (PerpSwapLib.sol:1033), TRUSTED, in-cluster`; `PerpSwapLib._posAt (PerpSwapLib.sol:1034), TRUSTED, in-cluster`; `PerpSwapLib._idsAt (PerpSwapLib.sol:1034), TRUSTED, in-cluster`; `PerpSwapLib._obsAt (PerpSwapLib.sol:1035), TRUSTED, in-cluster`; `PerpSwapLib._ringAt (PerpSwapLib.sol:1035), TRUSTED, in-cluster`
- Observations: none

### `_posAt/function` — PerpSwapLib.sol:1039

- Signature: `function _posAt(uint256 s) private pure returns (mapping(uint256 => Position) storage m)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Returns a storage pointer at a caller-supplied slot (`_posAt` PerpSwapLib.sol:1039); pure, no read or write of its own.
- Edges: none
- Observations: none

### `_idsAt/function` — PerpSwapLib.sol:1042

- Signature: `function _idsAt(uint256 s) private pure returns (uint256[] storage a)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Returns a storage pointer at a caller-supplied slot (`_idsAt` PerpSwapLib.sol:1042); pure, no read or write of its own.
- Edges: none
- Observations: none

### `_obsAt/function` — PerpSwapLib.sol:1045

- Signature: `function _obsAt(uint256 s) private pure returns (Observation[OBS_CARDINALITY] storage o)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Returns a storage pointer at a caller-supplied slot (`_obsAt` PerpSwapLib.sol:1045); pure, no read or write of its own.
- Edges: none
- Observations: none

### `_ringAt/function` — PerpSwapLib.sol:1048

- Signature: `function _ringAt(uint256 s) private pure returns (Ring storage r)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Returns a storage pointer at a caller-supplied slot (`_ringAt` PerpSwapLib.sol:1048); pure, no read or write of its own.
- Edges: none
- Observations: none

### `_slot/function` — PerpSwapLib.sol:1053

- Signature: `function _slot(uint256 slots, uint256 i) private pure returns (uint256)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Extracts the i-th 16-bit slot number from the packed descriptor (`_slot` PerpSwapLib.sol:1053); pure.
- Edges: none
- Observations: none

### `_ld/function` — PerpSwapLib.sol:1057

- Signature: `function _ld(uint256 slots, uint256 i) private view returns (uint256 v)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: SLOADs the engine slot named by index i of the descriptor (`_slot` PerpSwapLib.sol:1058). No named storage.
- Edges: `PerpSwapLib._slot (PerpSwapLib.sol:1058), TRUSTED, in-cluster`
- Observations: none

### `_st/function` — PerpSwapLib.sol:1062

- Signature: `function _st(uint256 slots, uint256 i, uint256 v) private`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: SSTOREs a value into the engine slot named by index i of the descriptor (`_slot` PerpSwapLib.sol:1063). No named storage.
- Edges: `PerpSwapLib._slot (PerpSwapLib.sol:1063), TRUSTED, in-cluster`
- Observations: none

### `_stAddr/function` — PerpSwapLib.sol:1069

- Signature: `function _stAddr(uint256 slots, uint256 at, address a) private`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Writes an address into a packed engine slot, preserving the slot's other bytes (`m` PerpSwapLib.sol:1073). No named storage.
- Edges: none
- Observations: none

### `_factorStrict/function` — PerpSwapLib.sol:1080

- Signature: `function _factorStrict(address oracle, address q) private view returns (uint256)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Strict price factor: native is 1e18 (`q` PerpSwapLib.sol:1081); otherwise a missing oracle or a zero USD price reverts (`RequoteUnpriced` PerpSwapLib.sol:1085) instead of falling back, then returns the native/quote ratio (`mulDiv` PerpSwapLib.sol:1086).
- Edges: `PerpSwapLib._usdPerRawUnit (PerpSwapLib.sol:1083), TRUSTED, in-cluster`; `PerpSwapLib._usdPerRawUnit (PerpSwapLib.sol:1084), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpSwapLib.sol:1086), TRUSTED, library`
- Observations: none

### `_shortBacking/function` — PerpSwapLib.sol:1091

- Signature: `function _shortBacking(mapping(uint256 => Position) storage positions, uint256[] storage openIds) private view returns (uint256 backing)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: `positions (line 1098)`
- Writes: none
- Value: NONE
- Reachability: Sums collateral plus principal over open shorts (`backing` PerpSwapLib.sol:1099), bounded by the open-id list length (`n` PerpSwapLib.sol:1096).
- Edges: none
- Observations: none

### `_convert/function` — PerpSwapLib.sol:1106

- Signature: `function _convert(address rot, address oq, address nq, uint256 spent) private returns (uint256 got)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: Sends `spent` of the old quote to the rotator, native by call or ERC20 transfer with bool check (`rot` PerpSwapLib.sol:1112; `transfer` PerpSwapLib.sol:1116), then withdraws the swap output back (`withdraw` PerpSwapLib.sol:1121).
- Reachability: Requires a curated venue for the pair (`RequoteUnpriced` PerpSwapLib.sol:1110), pays the rotator, swaps with the rotator's own oracle floor as the minimum (`swapOnce` PerpSwapLib.sol:1120), withdraws the proceeds and requires the engine's balance of the new quote to have risen by at least the reported output (`RequoteShort` PerpSwapLib.sol:1122). A failed send or short receipt reverts.
- Edges: `IRequoteRotator.venueFor (PerpSwapLib.sol:1109), UNTRUSTED, out-of-cluster`; `PerpSwapLib._held (PerpSwapLib.sol:1119), TRUSTED, in-cluster`; `IRequoteRotator.swapOnce (PerpSwapLib.sol:1120), UNTRUSTED, out-of-cluster`; `IRequoteRotator.withdraw (PerpSwapLib.sol:1121), UNTRUSTED, out-of-cluster`; `PerpSwapLib._held (PerpSwapLib.sol:1122), TRUSTED, in-cluster`
- Observations: none

### `_held/function` — PerpSwapLib.sol:1125

- Signature: `function _held(address asset) private view returns (uint256)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Engine's own balance of an asset: native balance or ERC20 balanceOf (`asset` PerpSwapLib.sol:1126); read-only.
- Edges: none
- Observations: none

### `_restatePositions/function` — PerpSwapLib.sol:1131

- Signature: `function _restatePositions( mapping(uint256 => Position) storage positions, uint256[] storage openIds, uint256 fOld, uint256 fNew, uint256 got, uint256 spent ) private returns (uint256 longOi, uint256 shortsNew)`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: `positions (line 1141)`
- Writes: `positions (line 1141)`
- Value: NONE
- Reachability: Restates every open position in the new quote: longs at the oracle ratio with principal rounded up (`mulDivRoundingUp` PerpSwapLib.sol:1146), shorts at the realised got/spent rate (`mulDiv` PerpSwapLib.sol:1149). Collateral above uint128 reverts (`RequoteUnpriced` PerpSwapLib.sol:1153). Returns the new long open interest and the new short backing. Loop bounded by the open-id list.
- Edges: `FullMath.mulDiv (PerpSwapLib.sol:1145), TRUSTED, library`; `FullMath.mulDivRoundingUp (PerpSwapLib.sol:1146), TRUSTED, library`; `FullMath.mulDiv (PerpSwapLib.sol:1149), TRUSTED, library`
- Observations: none

### `_shiftRing/function` — PerpSwapLib.sol:1172

- Signature: `function _shiftRing(Observation[OBS_CARDINALITY] storage obs, Ring storage r, uint256 fOld, uint256 fNew) private`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Private; rebases the engine's TWAP state onto the new quote during a requote, through storage references to the engine's observation array and ring. The price ratio of old to new quote factor becomes a tick shift (`d` PerpSwapLib.sol:1177); a ratio outside the representable price range reverts the requote (`RequoteUnpriced` PerpSwapLib.sol:1176). Every recorded observation's cumulative tick is shifted by that tick times its own timestamp (`tickCumulative` PerpSwapLib.sol:1181), so TWAP differences taken across the change stay consistent, and the ring's running cumulative and last tick move the same way (`lastTick` PerpSwapLib.sol:1187); a shifted last tick outside the valid range reverts.
- Edges: `Math.sqrt (PerpSwapLib.sol:1175), TRUSTED, library`; `FullMath.mulDiv (PerpSwapLib.sol:1175), TRUSTED, library`; `TickMath.getTickAtSqrtPrice (PerpSwapLib.sol:1177), TRUSTED, library`
- Observations: none

### `_vaultHook/function` — PerpSwapLib.sol:1193

- Signature: `function _vaultHook(address vault, bytes memory data) private`
- Authority: internal (callers: PerpSwapLib)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Calls the configured vault with the given payload unless it is unset (`vault` PerpSwapLib.sol:1194); a failed call reverts the requote (`RequoteVault` PerpSwapLib.sol:1196).
- Edges: none
- Observations: none


## `IPerpEngineVault (declared in PerpVault.sol)`

### `fundFromVault/function` — PerpVault.sol:9

- Signature: `function fundFromVault(uint256 amount) external payable`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `fundFromVault` (PerpVault.sol:9) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `quote/function` — PerpVault.sol:10

- Signature: `function quote() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `quote` (PerpVault.sol:10) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `withdrawPlvTo/function` — PerpVault.sol:11

- Signature: `function withdrawPlvTo(uint256 amount, address to) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `withdrawPlvTo` (PerpVault.sol:11) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `fundTokenFromVault/function` — PerpVault.sol:12

- Signature: `function fundTokenFromVault(uint256 amount) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `fundTokenFromVault` (PerpVault.sol:12) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `withdrawPlvTokenTo/function` — PerpVault.sol:13

- Signature: `function withdrawPlvTokenTo(uint256 amount, address to) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `withdrawPlvTokenTo` (PerpVault.sol:13) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `totalEth/function` — PerpVault.sol:14

- Signature: `function totalEth() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `totalEth` (PerpVault.sol:14) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `freeEth/function` — PerpVault.sol:15

- Signature: `function freeEth() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `freeEth` (PerpVault.sol:15) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `totalTokenAssets/function` — PerpVault.sol:16

- Signature: `function totalTokenAssets() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `totalTokenAssets` (PerpVault.sol:16) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `freeToken/function` — PerpVault.sol:17

- Signature: `function freeToken() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `freeToken` (PerpVault.sol:17) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `tokYieldCumulative/function` — PerpVault.sol:19

- Signature: `function tokYieldCumulative() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `tokYieldCumulative` (PerpVault.sol:19) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `tokYieldEth/function` — PerpVault.sol:22

- Signature: `function tokYieldEth() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `tokYieldEth` (PerpVault.sol:22) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `withdrawTokYieldTo/function` — PerpVault.sol:23

- Signature: `function withdrawTokYieldTo(uint256 amount, address to) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `withdrawTokYieldTo` (PerpVault.sol:23) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `IVaultRegistry (declared in PerpVault.sol)`

### `currentToken/function` — PerpVault.sol:27

- Signature: `function currentToken() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `currentToken` (PerpVault.sol:27) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `PerpVault`

### `constructor/constructor` — PerpVault.sol:241

- Signature: `constructor(address _engine, address _registry)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: `QSCALE (line 244)`
- Writes: `engine (line 242)`; `registry (line 243)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (PerpVault.sol:241) is a constructor node with 1 direct storage/immutable reads, 2 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `hasStakers/function` — PerpVault.sol:267

- Signature: `function hasStakers() external view returns (bool)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `ethShares (line 268)`; `tokShares (line 268)`; `ethQueueUnits (line 268)`; `tokQueueUnits (line 268)`; `_settledTokYield (line 271)`; `engine (line 272, immutable)`; `totalTokYieldPulled (line 272)`
- Writes: none
- Value: NONE
- Reachability: The engine's vault-replacement guard. True while any share or queue unit exists (`tokQueueUnits` PerpVault.sol:268), or while settled, attributed token-side rewards are still owed (`_settledTokYield` PerpVault.sol:271) and no unrecognised engine write-off has forfeited them (`tokYieldCumulative` PerpVault.sol:272).
- Edges: `IPerpEngineVault.tokYieldCumulative (PerpVault.sol:272), TRUSTED, in-cluster`; `IPerpEngineVault.tokYieldEth (PerpVault.sol:272), TRUSTED, in-cluster`
- Observations: none

### `hasQuoteStake/function` — PerpVault.sol:294

- Signature: `function hasQuoteStake() external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `ethShares (line 295)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `hasQuoteStake` (PerpVault.sol:294) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpVault.hasQuoteStake (PerpVault.sol:294), TRUSTED, in-cluster`
- Observations: none

### `assetsEth/function` — PerpVault.sol:300

- Signature: `function assetsEth() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `engine (line 301)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `assetsEth` (PerpVault.sol:300) is a public node with 1 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpVault.assetsEth (PerpVault.sol:300), TRUSTED, in-cluster`; `IPerpEngineVault.totalEth (PerpVault.sol:301), TRUSTED, in-cluster`; `PerpVault.pendingEth (PerpVault.sol:302), TRUSTED, in-cluster`; `PerpVault.pendingEth (PerpVault.sol:302), TRUSTED, in-cluster`
- Observations: none

### `assetsTok/function` — PerpVault.sol:306

- Signature: `function assetsTok() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `engine (line 307)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `assetsTok` (PerpVault.sol:306) is a public node with 1 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpVault.assetsTok (PerpVault.sol:306), TRUSTED, in-cluster`; `IPerpEngineVault.totalTokenAssets (PerpVault.sol:307), TRUSTED, in-cluster`; `PerpVault.pendingTok (PerpVault.sol:308), TRUSTED, in-cluster`; `PerpVault.pendingTok (PerpVault.sol:308), TRUSTED, in-cluster`
- Observations: none

### `deposit/function` — PerpVault.sol:327

- Signature: `function deposit(uint256 amount) public payable nonReentrant returns (uint256 shares)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `engine (line 345, immutable)`; `ethShares (line 359)`
- Writes: `ethShares (line 361)`; `ethShareOf (line 362)`
- Value: Receives native (msg.value must equal amount) or pulls the ERC20 quote from the caller (`_pull` PerpVault.sol:355), then funds the engine's PLV (`fundFromVault` PerpVault.sol:363).
- Reachability: Quote-agnostic ETH-side stake. Recognises any queued loss before pricing (`_syncEthQueue` PerpVault.sol:329), refuses while the exit queue is owed more than the engine holds (`QueueInsolvent` PerpVault.sol:345), takes native or the ERC20 quote per the engine's quote (`_engineQuote` PerpVault.sol:350), mints shares at the pre-funding price with a virtual offset (`shares` PerpVault.sol:359), funds the engine and re-marks the backing (`_markEth` PerpVault.sol:364). Reentrancy-guarded.
- Edges: `PerpVault._syncEthQueue (PerpVault.sol:329), TRUSTED, in-cluster`; `PerpVault.pendingEth (PerpVault.sol:345), TRUSTED, in-cluster`; `IPerpEngineVault.totalEth (PerpVault.sol:345), TRUSTED, in-cluster`; `PerpVault._engineQuote (PerpVault.sol:350), TRUSTED, in-cluster`; `PerpVault._pull (PerpVault.sol:355), TRUSTED, in-cluster`; `PerpVault._approve (PerpVault.sol:356), TRUSTED, in-cluster`; `PerpVault.assetsEth (PerpVault.sol:359), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:359), TRUSTED, library`; `IPerpEngineVault.fundFromVault (PerpVault.sol:363), TRUSTED, in-cluster`; `PerpVault._markEth (PerpVault.sol:364), TRUSTED, in-cluster`
- Observations: none

### `depositEth/function` — PerpVault.sol:370

- Signature: `function depositEth() external payable returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives or validates `msg.value` (line 371)
- Reachability: DERIVED from the current body: anyone; `depositEth` (PerpVault.sol:370) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpVault.depositEth (PerpVault.sol:370), TRUSTED, in-cluster`; `PerpVault.deposit (PerpVault.sol:371), TRUSTED, in-cluster`
- Observations: none

### `_engineQuote/function` — PerpVault.sol:374

- Signature: `function _engineQuote() private view returns (address)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `engine (line 375)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_engineQuote` (PerpVault.sol:374) is a private node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpVault._engineQuote (PerpVault.sol:374), TRUSTED, in-cluster`; `PerpEngine.quote (PerpVault.sol:376), TRUSTED, in-cluster`
- Observations: none

### `_pull/function` — PerpVault.sol:384

- Signature: `function _pull(address token, address from, uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_pull` (PerpVault.sol:384) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpVault._pull (PerpVault.sol:384), TRUSTED, in-cluster`; `IERC20.transferFrom (PerpVault.sol:386), UNTRUSTED, out-of-cluster`; `IERC20.transferFrom (PerpVault.sol:386), TRUSTED, out-of-cluster`
- Observations: none

### `_approve/function` — PerpVault.sol:391

- Signature: `function _approve(address token, address spender, uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_approve` (PerpVault.sol:391) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpVault._approve (PerpVault.sol:391), TRUSTED, in-cluster`; `IERC20.approve (PerpVault.sol:392), UNTRUSTED, out-of-cluster`; `IERC20.approve (PerpVault.sol:392), TRUSTED, out-of-cluster`
- Observations: none

### `withdrawEth/function` — PerpVault.sol:398

- Signature: `function withdrawEth(uint256 shares) external nonReentrant returns (uint256 paid, uint256 queued)`
- Authority: share holder (own shares)
- Gate evidence: `UNGATED`
- Reads: `ethShareOf (line 400)`; `engine (line 405, immutable)`; `ethShares (line 404)`
- Writes: `ethShareOf (line 412)`; `ethShares (line 413)`
- Value: Pays the free part of the exit from the engine to the caller (`withdrawPlvTo` PerpVault.sol:415); the rest is queued.
- Reachability: Recognises queued losses before valuing the exit (`_syncEthQueue` PerpVault.sol:399), burns the shares, pays what the engine can free now and queues the remainder (`_queueEth` PerpVault.sol:414); payment is the last interaction (`withdrawPlvTo` PerpVault.sol:415), then the backing mark is refreshed (`_markEth` PerpVault.sol:416).
- Edges: `PerpVault._syncEthQueue (PerpVault.sol:399), TRUSTED, in-cluster`; `PerpVault.assetsEth (PerpVault.sol:404), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:404), TRUSTED, library`; `IPerpEngineVault.freeEth (PerpVault.sol:405), TRUSTED, in-cluster`; `PerpVault._queueEth (PerpVault.sol:414), TRUSTED, in-cluster`; `IPerpEngineVault.withdrawPlvTo (PerpVault.sol:415), TRUSTED, in-cluster`; `PerpVault._markEth (PerpVault.sol:416), TRUSTED, in-cluster`
- Observations: none

### `_haircut/function` — PerpVault.sol:437

- Signature: `function _haircut(uint256 owed, uint256 backing, uint256 claims) private pure returns (uint256)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_haircut` (PerpVault.sol:437) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `FullMath.mulDiv (PerpVault.sol:443), TRUSTED, library`
- Observations: none

### `pendingEth/function` — PerpVault.sol:449

- Signature: `function pendingEth() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `QSCALE (line 450)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `pendingEth` (PerpVault.sol:449) is a public node with 1 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpVault.pendingEth (PerpVault.sol:449), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:450), TRUSTED, library`; `PerpVault.pendingEth (PerpVault.sol:449), TRUSTED, in-cluster`
- Observations: none

### `pendingEthOf/function` — PerpVault.sol:453

- Signature: `function pendingEthOf(address user) public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `QSCALE (line 455)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `pendingEthOf` (PerpVault.sol:453) is a public node with 1 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpVault.pendingEthOf (PerpVault.sol:453), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:455), TRUSTED, library`; `PerpVault.pendingEthOf (PerpVault.sol:453), TRUSTED, in-cluster`
- Observations: none

### `_markEth/function` — PerpVault.sol:460

- Signature: `function _markEth() private`
- Authority: internal (callers: PerpVault)
- Gate evidence: `UNGATED`
- Reads: `engine (line 460, immutable)`
- Writes: `ethBackingMark (line 460)`
- Value: NONE
- Reachability: Records the engine's current ETH-side total as the backing mark the queue compares against (`ethBackingMark` PerpVault.sol:460).
- Edges: `IPerpEngineVault.totalEth (PerpVault.sol:460), TRUSTED, in-cluster`
- Observations: none

### `beforeBookRequote/function` — PerpVault.sol:468

- Signature: `function beforeBookRequote() external nonReentrant`
- Authority: the engine only
- Gate evidence: `if (msg.sender != address(engine)) revert NotEngine(); (PerpVault.sol:469)`
- Reads: `engine (line 469, immutable)`
- Writes: none
- Value: NONE
- Reachability: Pre-requote hook: the engine calls it before converting the book so queued exits and token-side yield are settled in the OLD quote (`_syncEthQueue` PerpVault.sol:470; `_syncTokYield` PerpVault.sol:471). Engine-only (`NotEngine` PerpVault.sol:469) and reentrancy-guarded.
- Edges: `PerpVault._syncEthQueue (PerpVault.sol:470), TRUSTED, in-cluster`; `PerpVault._syncTokYield (PerpVault.sol:471), TRUSTED, in-cluster`
- Observations: none

### `afterBookRequote/function` — PerpVault.sol:490

- Signature: `function afterBookRequote(uint256 oldTotal, uint256 newTotal, uint256 kNum, uint256 kDen) external nonReentrant`
- Authority: the engine only
- Gate evidence: `if (msg.sender != address(engine)) revert NotEngine(); (PerpVault.sol:494)`
- Reads: `engine (line 494, immutable)`; `ethQueueUnits (line 495)`; `ethQueueIndex (line 496)`; `lastTokYieldCum (line 506)`; `totalTokYieldPulled (line 507)`; `tokYieldScale (line 508)`
- Writes: `ethQueueIndex (line 499)`; `ethBackingMark (line 501)`; `lastTokYieldCum (line 506)`; `totalTokYieldPulled (line 507)`; `tokYieldScale (line 508)`
- Value: NONE
- Reachability: Post-requote hook from the engine (`NotEngine` PerpVault.sol:494). Rescales the ETH exit-queue index by new/old book totals, never to zero (`ethQueueIndex` PerpVault.sol:499), resets the backing mark (`ethBackingMark` PerpVault.sol:501), and rescales the token-yield trackers by the realised conversion kNum/kDen, rounding the pulled total up (`totalTokYieldPulled` PerpVault.sol:507). Emits the requote parameters.
- Edges: `FullMath.mulDiv (PerpVault.sol:496), TRUSTED, library`; `FullMath.mulDiv (PerpVault.sol:506), TRUSTED, library`; `FullMath.mulDivRoundingUp (PerpVault.sol:507), TRUSTED, library`; `FullMath.mulDiv (PerpVault.sol:508), TRUSTED, library`
- Observations: none

### `_toYieldUnit/function` — PerpVault.sol:514

- Signature: `function _toYieldUnit(uint256 v) private view returns (uint256)`
- Authority: internal (callers: PerpVault)
- Gate evidence: `UNGATED`
- Reads: `tokYieldScale (line 515)`
- Writes: none
- Value: NONE
- Reachability: Converts a quote-denominated yield figure into the vault's internal yield unit by the running scale (`tokYieldScale` PerpVault.sol:515); floor-rounded.
- Edges: `FullMath.mulDiv (PerpVault.sol:515), TRUSTED, library`
- Observations: none

### `_queueEth/function` — PerpVault.sol:519

- Signature: `function _queueEth(address user, uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `QSCALE (line 520)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_queueEth` (PerpVault.sol:519) is a private node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpVault._queueEth (PerpVault.sol:519), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:520), TRUSTED, library`
- Observations: none

### `_dropEthUnits/function` — PerpVault.sol:528

- Signature: `function _dropEthUnits(address user) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_dropEthUnits` (PerpVault.sol:528) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpVault._dropEthUnits (PerpVault.sol:528), TRUSTED, in-cluster`
- Observations: none

### `_syncEthQueue/function` — PerpVault.sol:575

- Signature: `function _syncEthQueue() private`
- Authority: internal (callers: deposit, withdrawEth, claimPendingEth, settlePendingEth, beforeBookRequote)
- Gate evidence: `UNGATED`
- Reads: `engine (line 576, immutable)`; `ethQueueUnits (line 577)`; `ethQueueIndex (line 579)`; `ethBackingMark (line 581)`
- Writes: `ethBackingMark (line 578)`; `ethBackingMark (line 589)`; `ethQueueUnits (line 595)`; `ethQueueIndex (line 596)`; `ethQueueEpoch (line 597)`; `ethQueueIndex (line 601)`
- Value: NONE
- Reachability: Recognises ETH-side losses for queued exits. A backing drop since the last mark scales the queue index pro rata (`newIdx` PerpVault.sol:583); if the queue is then still owed more than the backing it is haircut to the backing (`_haircut` PerpVault.sol:588). A queue written to zero opens a new epoch (`ethQueueEpoch` PerpVault.sol:597). The mark is refreshed on every call (`ethBackingMark` PerpVault.sol:589).
- Edges: `IPerpEngineVault.totalEth (PerpVault.sol:576), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:580), TRUSTED, library`; `FullMath.mulDiv (PerpVault.sol:584), TRUSTED, library`; `PerpVault._haircut (PerpVault.sol:588), TRUSTED, in-cluster`
- Observations: none

### `settlePendingEth/function` — PerpVault.sol:624

- Signature: `function settlePendingEth(address user) external nonReentrant returns (uint256 stillOwed)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `settlePendingEth` (PerpVault.sol:624) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `PerpVault.settlePendingEth (PerpVault.sol:624), TRUSTED, in-cluster`; `PerpVault._syncEthQueue (PerpVault.sol:625), TRUSTED, in-cluster`; `PerpVault.pendingEthOf (PerpVault.sol:626), TRUSTED, in-cluster`; `PerpVault._dropEthUnits (PerpVault.sol:627), TRUSTED, in-cluster`; `PerpVault.pendingEthOf (PerpVault.sol:626), TRUSTED, in-cluster`
- Observations: none

### `claimPendingEth/function` — PerpVault.sol:636

- Signature: `function claimPendingEth() external nonReentrant returns (uint256 paid)`
- Authority: queued claimant (own queue)
- Gate evidence: `UNGATED`
- Reads: `engine (line 641, immutable)`; `ethQueueIndex (line 647)`; `_ethUnitsOf (line 648)`
- Writes: `_ethUnitsOf (line 650)`; `ethQueueUnits (line 651)`
- Value: Pays the claimant's queued ETH, up to what the engine can free, from the engine (`withdrawPlvTo` PerpVault.sol:653).
- Reachability: Requires a nonzero queued claim (`ZeroAmount` PerpVault.sol:637), recognises losses first (`_syncEthQueue` PerpVault.sol:638), drops a claim written to zero, pays min(owed, free) and debits units proportionally for a partial payment (`du` PerpVault.sol:647), then pays last and re-marks the backing (`_markEth` PerpVault.sol:654). Reentrancy-guarded.
- Edges: `PerpVault.pendingEthOf (PerpVault.sol:637), TRUSTED, in-cluster`; `PerpVault._syncEthQueue (PerpVault.sol:638), TRUSTED, in-cluster`; `PerpVault.pendingEthOf (PerpVault.sol:639), TRUSTED, in-cluster`; `PerpVault._dropEthUnits (PerpVault.sol:640), TRUSTED, in-cluster`; `IPerpEngineVault.freeEth (PerpVault.sol:641), TRUSTED, in-cluster`; `PerpVault._dropEthUnits (PerpVault.sol:645), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:647), TRUSTED, library`; `IPerpEngineVault.withdrawPlvTo (PerpVault.sol:653), TRUSTED, in-cluster`; `PerpVault._markEth (PerpVault.sol:654), TRUSTED, in-cluster`
- Observations: none

### `_syncTokYield/function` — PerpVault.sol:679

- Signature: `function _syncTokYield() internal`
- Authority: internal (callers: token-side entrypoints, beforeBookRequote)
- Gate evidence: `UNGATED`
- Reads: `engine (line 680, immutable)`; `totalTokYieldPulled (line 681)`; `lastTokYieldCum (line 684)`; `tokShares (line 685)`; `accEthPerTokShare (line 712)`
- Writes: `lastTokYieldCum (line 687)`; `accEthPerTokShare (line 712)`; `epochAcc (line 713)`; `accEthPerTokShare (line 716)`; `epochAcc (line 720)`; `_settledTokYield (line 723)`; `totalTokYieldPulled (line 726)`; `yieldEpoch (line 727)`
- Value: NONE
- Reachability: Lazily credits new engine token-side yield to token shares in internal yield units (`_toYieldUnit` PerpVault.sol:716); with no shares it is logged as unattributed. A write-off detected as cumulative yield exceeding pot plus pulled (`lost` PerpVault.sol:683) splits accrual at the forfeit line (`epochAcc` PerpVault.sol:713), clears the settled-reward aggregate (`_settledTokYield` PerpVault.sol:723), books the loss as pulled and bumps the epoch (`yieldEpoch` PerpVault.sol:727).
- Edges: `IPerpEngineVault.tokYieldCumulative (PerpVault.sol:680), TRUSTED, in-cluster`; `IPerpEngineVault.tokYieldEth (PerpVault.sol:682), TRUSTED, in-cluster`; `PerpVault._toYieldUnit (PerpVault.sol:712), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:712), TRUSTED, library`
- Observations: none

### `_settleTok/function` — PerpVault.sol:733

- Signature: `function _settleTok(address user) internal`
- Authority: internal (callers: token-side entrypoints)
- Gate evidence: `UNGATED`
- Reads: `stakerEpoch (line 737)`; `yieldEpoch (line 737)`; `tokShareOf (line 742)`; `epochAcc (line 739)`; `accEthPerTokShare (line 744)`; `tokRewardDebt (line 745)`
- Writes: `tokRewardOwed (line 738)`; `tokRewardDebt (line 739)`; `stakerEpoch (line 740)`; `tokRewardOwed (line 747)`; `_settledTokYield (line 748)`
- Value: NONE
- Reachability: Settles a user's token-side reward. A stale epoch forfeits the old owed amount and rebases the debt to the forfeit line (`stakerEpoch` PerpVault.sol:737); earned accrual is added both to the user's owed amount and to the vault-wide settled aggregate that keeps replacement blocked (`_settledTokYield` PerpVault.sol:748).
- Edges: `FullMath.mulDiv (PerpVault.sol:739), TRUSTED, library`; `FullMath.mulDiv (PerpVault.sol:744), TRUSTED, library`
- Observations: none

### `_resetTokDebt/function` — PerpVault.sol:753

- Signature: `function _resetTokDebt(address user) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `ACC (line 754)`; `accEthPerTokShare (line 754)`; `tokShareOf (line 754)`
- Writes: `tokRewardDebt (line 754)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_resetTokDebt` (PerpVault.sol:753) is a internal node with 3 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `PerpVault._resetTokDebt (PerpVault.sol:753), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:754), TRUSTED, library`
- Observations: none

### `depositToken/function` — PerpVault.sol:761

- Signature: `function depositToken(uint256 amount) external nonReentrant returns (uint256 shares)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `OFFSET (line 775)`; `engine (line 772)`; `registry (line 773)`
- Writes: `tokShareOf (line 778)`; `tokShares (line 775)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `depositToken` (PerpVault.sol:761) is a external node with 3 direct storage/immutable reads, 2 direct writes, and 13 resolved call edges.
- Edges: `PerpVault.depositToken (PerpVault.sol:761), TRUSTED, in-cluster`; `IPerpEngineVault.totalTokenAssets (PerpVault.sol:772), TRUSTED, in-cluster`; `PerpVault.pendingTok (PerpVault.sol:772), TRUSTED, in-cluster`; `IVaultRegistry.currentToken (PerpVault.sol:773), UNTRUSTED, in-cluster`; `PerpVault._syncTokYield (PerpVault.sol:774), TRUSTED, in-cluster`; `PerpVault._settleTok (PerpVault.sol:774), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:775), TRUSTED, library`; `PerpVault.assetsTok (PerpVault.sol:775), TRUSTED, in-cluster`; `PerpVault._resetTokDebt (PerpVault.sol:779), TRUSTED, in-cluster`; `PerpVault._pull (PerpVault.sol:781), TRUSTED, in-cluster`; `PerpVault._approve (PerpVault.sol:782), TRUSTED, in-cluster`; `IPerpEngineVault.fundTokenFromVault (PerpVault.sol:783), TRUSTED, in-cluster`; `PerpVault.pendingTok (PerpVault.sol:772), TRUSTED, in-cluster`
- Observations: none

### `claimTokYield/function` — PerpVault.sol:789

- Signature: `function claimTokYield() external nonReentrant returns (uint256 paid)`
- Authority: token staker (own reward)
- Gate evidence: `UNGATED`
- Reads: `tokRewardOwed (line 791)`; `tokYieldScale (line 793)`
- Writes: `_settledTokYield (line 794)`; `tokRewardOwed (line 795)`; `totalTokYieldPulled (line 796)`
- Value: Pays the converted reward from the engine's segregated pot to the caller (`withdrawTokYieldTo` PerpVault.sol:797).
- Reachability: Syncs and settles, then requires positive owed internal units (`ZeroAmount` PerpVault.sol:792). Converts them to today's quote (`paid` PerpVault.sol:793), debits the settled aggregate and the user's claim before paying (`_settledTokYield` PerpVault.sol:794), and pays only a nonzero amount (`withdrawTokYieldTo` PerpVault.sol:797). A positive claim that rounds to zero is cleared with a zero payout. Reentrancy-guarded.
- Edges: `PerpVault._syncTokYield (PerpVault.sol:790), TRUSTED, in-cluster`; `PerpVault._settleTok (PerpVault.sol:790), TRUSTED, in-cluster`; `PerpVault._resetTokDebt (PerpVault.sol:790), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:793), TRUSTED, library`; `IPerpEngineVault.withdrawTokYieldTo (PerpVault.sol:797), TRUSTED, in-cluster`
- Observations: none

### `withdrawToken/function` — PerpVault.sol:803

- Signature: `function withdrawToken(uint256 shares) external nonReentrant returns (uint256 paid, uint256 queued)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `OFFSET (line 809)`; `engine (line 810)`
- Writes: `tokShareOf (line 804)`; `tokShares (line 809)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `withdrawToken` (PerpVault.sol:803) is a external node with 2 direct storage/immutable reads, 2 direct writes, and 9 resolved call edges.
- Edges: `PerpVault.withdrawToken (PerpVault.sol:803), TRUSTED, in-cluster`; `PerpVault._syncTokYield (PerpVault.sol:808), TRUSTED, in-cluster`; `PerpVault._settleTok (PerpVault.sol:808), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:809), TRUSTED, library`; `PerpVault.assetsTok (PerpVault.sol:809), TRUSTED, in-cluster`; `IPerpEngineVault.freeToken (PerpVault.sol:810), TRUSTED, in-cluster`; `PerpVault._resetTokDebt (PerpVault.sol:816), TRUSTED, in-cluster`; `PerpVault._queueTok (PerpVault.sol:817), TRUSTED, in-cluster`; `IPerpEngineVault.withdrawPlvTokenTo (PerpVault.sol:818), TRUSTED, in-cluster`
- Observations: none

### `pendingTok/function` — PerpVault.sol:823

- Signature: `function pendingTok() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `QSCALE (line 824)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `pendingTok` (PerpVault.sol:823) is a public node with 1 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpVault.pendingTok (PerpVault.sol:823), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:824), TRUSTED, library`; `PerpVault.pendingTok (PerpVault.sol:823), TRUSTED, in-cluster`
- Observations: none

### `pendingTokOf/function` — PerpVault.sol:827

- Signature: `function pendingTokOf(address user) public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `QSCALE (line 829)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `pendingTokOf` (PerpVault.sol:827) is a public node with 1 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `PerpVault.pendingTokOf (PerpVault.sol:827), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:829), TRUSTED, library`; `PerpVault.pendingTokOf (PerpVault.sol:827), TRUSTED, in-cluster`
- Observations: none

### `_queueTok/function` — PerpVault.sol:833

- Signature: `function _queueTok(address user, uint256 amount) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `QSCALE (line 834)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_queueTok` (PerpVault.sol:833) is a private node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `PerpVault._queueTok (PerpVault.sol:833), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:834), TRUSTED, library`
- Observations: none

### `_dropTokUnits/function` — PerpVault.sol:841

- Signature: `function _dropTokUnits(address user) private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_dropTokUnits` (PerpVault.sol:841) is a private node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `PerpVault._dropTokUnits (PerpVault.sol:841), TRUSTED, in-cluster`
- Observations: none

### `_syncTokQueue/function` — PerpVault.sol:850

- Signature: `function _syncTokQueue() private`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `QSCALE (line 854)`; `engine (line 855)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_syncTokQueue` (PerpVault.sol:850) is a private node with 2 direct storage/immutable reads, 0 direct writes, and 4 resolved call edges.
- Edges: `PerpVault._syncTokQueue (PerpVault.sol:850), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:854), TRUSTED, library`; `IPerpEngineVault.totalTokenAssets (PerpVault.sol:855), TRUSTED, in-cluster`; `PerpVault._haircut (PerpVault.sol:857), TRUSTED, in-cluster`
- Observations: none

### `settlePendingToken/function` — PerpVault.sol:870

- Signature: `function settlePendingToken(address user) external nonReentrant returns (uint256 stillOwed)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `settlePendingToken` (PerpVault.sol:870) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `PerpVault.settlePendingToken (PerpVault.sol:870), TRUSTED, in-cluster`; `PerpVault._syncTokQueue (PerpVault.sol:871), TRUSTED, in-cluster`; `PerpVault.pendingTokOf (PerpVault.sol:872), TRUSTED, in-cluster`; `PerpVault._dropTokUnits (PerpVault.sol:873), TRUSTED, in-cluster`; `PerpVault.pendingTokOf (PerpVault.sol:872), TRUSTED, in-cluster`
- Observations: none

### `claimPendingToken/function` — PerpVault.sol:885

- Signature: `function claimPendingToken() external nonReentrant returns (uint256 paid)`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (pendingTokOf(msg.sender) == 0) revert ZeroAmount(); (PerpVault.sol:886)`
- Reads: `QSCALE (line 896)`; `engine (line 890)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `claimPendingToken` (PerpVault.sol:885) is a external node with 2 direct storage/immutable reads, 0 direct writes, and 10 resolved call edges.
- Edges: `PerpVault.claimPendingToken (PerpVault.sol:885), TRUSTED, in-cluster`; `PerpVault.pendingTokOf (PerpVault.sol:886), TRUSTED, in-cluster`; `PerpVault._syncTokQueue (PerpVault.sol:887), TRUSTED, in-cluster`; `PerpVault.pendingTokOf (PerpVault.sol:888), TRUSTED, in-cluster`; `PerpVault._dropTokUnits (PerpVault.sol:889), TRUSTED, in-cluster`; `IPerpEngineVault.freeToken (PerpVault.sol:890), TRUSTED, in-cluster`; `PerpVault._dropTokUnits (PerpVault.sol:894), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:896), TRUSTED, library`; `IPerpEngineVault.withdrawPlvTokenTo (PerpVault.sol:902), TRUSTED, in-cluster`; `PerpVault.pendingTokOf (PerpVault.sol:886), TRUSTED, in-cluster`
- Observations: none

### `ethPosition/function` — PerpVault.sol:910

- Signature: `function ethPosition(address user) external view returns (uint256 redeemable, uint256 instant, uint256 pending)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `OFFSET (line 912)`; `engine (line 913)`; `ethShareOf (line 911)`; `ethShares (line 912)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `ethPosition` (PerpVault.sol:910) is a external node with 4 direct storage/immutable reads, 0 direct writes, and 6 resolved call edges.
- Edges: `PerpVault.ethPosition (PerpVault.sol:910), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:912), TRUSTED, library`; `PerpVault.assetsEth (PerpVault.sol:912), TRUSTED, in-cluster`; `IPerpEngineVault.freeEth (PerpVault.sol:913), TRUSTED, in-cluster`; `PerpVault.pendingEthOf (PerpVault.sol:915), TRUSTED, in-cluster`; `PerpVault.pendingEthOf (PerpVault.sol:915), TRUSTED, in-cluster`
- Observations: none

### `tokenPosition/function` — PerpVault.sol:918

- Signature: `function tokenPosition(address user) external view returns (uint256 redeemable, uint256 instant, uint256 pending)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `OFFSET (line 920)`; `engine (line 921)`; `tokShareOf (line 919)`; `tokShares (line 920)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `tokenPosition` (PerpVault.sol:918) is a external node with 4 direct storage/immutable reads, 0 direct writes, and 6 resolved call edges.
- Edges: `PerpVault.tokenPosition (PerpVault.sol:918), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:920), TRUSTED, library`; `PerpVault.assetsTok (PerpVault.sol:920), TRUSTED, in-cluster`; `IPerpEngineVault.freeToken (PerpVault.sol:921), TRUSTED, in-cluster`; `PerpVault.pendingTokOf (PerpVault.sol:923), TRUSTED, in-cluster`; `PerpVault.pendingTokOf (PerpVault.sol:923), TRUSTED, in-cluster`
- Observations: none

### `pendingTokYield/function` — PerpVault.sol:927

- Signature: `function pendingTokYield(address user) external view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `accEthPerTokShare (line 928)`; `epochAcc (line 929)`; `yieldEpoch (line 930)`; `engine (line 931, immutable)`; `totalTokYieldPulled (line 932)`; `lastTokYieldCum (line 936)`; `tokShares (line 937)`; `tokShareOf (line 962)`; `tokRewardOwed (line 963)`; `tokRewardDebt (line 964)`; `stakerEpoch (line 965)`
- Writes: none
- Value: NONE
- Reachability: Preview of a user's token-side reward: replays the lazy accrual and write-off split exactly as the sync does (`cut` PerpVault.sol:946), applies the epoch forfeit (`stakerEpoch` PerpVault.sol:965) and converts internal units to today's quote.
- Edges: `IPerpEngineVault.tokYieldCumulative (PerpVault.sol:931), TRUSTED, in-cluster`; `IPerpEngineVault.tokYieldEth (PerpVault.sol:934), TRUSTED, in-cluster`; `PerpVault._toYieldUnit (PerpVault.sol:950), TRUSTED, in-cluster`; `FullMath.mulDiv (PerpVault.sol:950), TRUSTED, library`
- Observations: none
