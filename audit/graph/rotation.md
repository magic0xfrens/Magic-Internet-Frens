# Function graph — `rotation`

Current source-derived semantic map: **103 nodes** across **7 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `cauldron/QuoteRotator.sol` | 841 |
| `cauldron/QuoteOracle.sol` | 390 |
| `cauldron/RedemptionExt.sol` | 1165 |
| `cauldron/CauldronVault.sol` | 212 |
| `cauldron/NativeQuoteZap.sol` | 182 |
| `cauldron/MockAggregator.sol` | 94 |
| `cauldron/MockQuoteToken.sol` | 28 |


## `IBurnableCollection (declared in CauldronVault.sol)`

### `ownerOf/function` — CauldronVault.sol:7

- Signature: `function ownerOf(uint256 tokenId) external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `ownerOf` (CauldronVault.sol:7) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `totalMinted/function` — CauldronVault.sol:8

- Signature: `function totalMinted() external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `totalMinted` (CauldronVault.sol:8) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `burnFromVault/function` — CauldronVault.sol:9

- Signature: `function burnFromVault(uint256 tokenId) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `burnFromVault` (CauldronVault.sol:9) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `minter/function` — CauldronVault.sol:14

- Signature: `function minter() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `minter` (CauldronVault.sol:14) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `ILegacyFloorHook (declared in CauldronVault.sol)`

### `vault/function` — CauldronVault.sol:18

- Signature: `function vault() external view returns (address)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: the vault asks the collection's minter (the hook) which vault it funds, via a raw static call (`vault` CauldronVault.sol:186).
- Edges: none
- Observations: none


## `CauldronVault`

### `outstanding/function` — CauldronVault.sol:64

- Signature: `function outstanding() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `collection (line 65)`; `floorOffset (line 66)`; `redeemed (line 67)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `outstanding` (CauldronVault.sol:64) is a public node with 3 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `CauldronVault.outstanding (CauldronVault.sol:64), TRUSTED, in-cluster`; `IBurnableCollection.totalMinted (CauldronVault.sol:65), UNTRUSTED, in-cluster`
- Observations: none

### `constructor/constructor` — CauldronVault.sol:110

- Signature: `constructor(address _collection, address _registry, uint256 _floorOffset)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `collection (line 111)`; `floorOffset (line 113)`; `registry (line 112)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (CauldronVault.sol:110) is a constructor node with 0 direct storage/immutable reads, 3 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `receive/receive` — CauldronVault.sol:121

- Signature: `receive() external payable`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (msg.sender == registry || msg.sender == _minter()) { (CauldronVault.sol:122)`
- Reads: `registry (line 122)`
- Writes: none
- Value: receives or validates `msg.value` (line 123)
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `receive` (CauldronVault.sol:121) is a receive node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `CauldronVault._minter (CauldronVault.sol:122), TRUSTED, in-cluster`
- Observations: none

### `_minter/function` — CauldronVault.sol:134

- Signature: `function _minter() private view returns (address m)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `collection (line 135)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_minter` (CauldronVault.sol:134) is a private node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `CauldronVault._minter (CauldronVault.sol:134), TRUSTED, in-cluster`
- Observations: none

### `floorPerNFT/function` — CauldronVault.sol:142

- Signature: `function floorPerNFT() public view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `closed (line 143)`
- Writes: none
- Value: NONE
- Reachability: Floor per eligible NFT: zero once closed or while the unified floor is in force (`_legacyFloorActive` CauldronVault.sol:143), otherwise the vault balance divided by eligible outstanding NFTs (`n` CauldronVault.sol:146), floor-rounded.
- Edges: `CauldronVault._legacyFloorActive (CauldronVault.sol:143), TRUSTED, in-cluster`; `CauldronVault.outstanding (CauldronVault.sol:144), TRUSTED, in-cluster`
- Observations: none

### `redeem/function` — CauldronVault.sol:161

- Signature: `function redeem(uint256 tokenId) external nonReentrant returns (uint256 amount)`
- Authority: NFT owner of an eligible art id
- Gate evidence: `if (collection.ownerOf(tokenId) != msg.sender) revert NotOwner(); (CauldronVault.sol:164)`
- Reads: `closed (line 162)`; `floorOffset (line 163, immutable)`; `collection (line 164, immutable)`
- Writes: `redeemed (line 173)`
- Value: Burns the NFT through the collection (`burnFromVault` CauldronVault.sol:174) and sends one floor share of native to the caller (`call` CauldronVault.sol:176).
- Reachability: Legacy per-collection floor redemption. Refused once closed, for the genesis tranche (`floorOffset` CauldronVault.sol:163), for non-owners, for ids above the art count so liquidation badges cannot draw the art floor (`totalMinted` CauldronVault.sol:166), and while the unified floor is active (`UnifiedFloorActive` CauldronVault.sol:167). The redeemed counter moves before the burn and the payment (`redeemed` CauldronVault.sol:173); a failed burn or payment reverts everything. Reentrancy-guarded.
- Edges: `IBurnableCollection.ownerOf (CauldronVault.sol:164), TRUSTED, in-cluster`; `IBurnableCollection.totalMinted (CauldronVault.sol:166), TRUSTED, in-cluster`; `CauldronVault._legacyFloorActive (CauldronVault.sol:167), TRUSTED, in-cluster`; `CauldronVault.outstanding (CauldronVault.sol:169), TRUSTED, in-cluster`; `IBurnableCollection.burnFromVault (CauldronVault.sol:174), TRUSTED, in-cluster`
- Observations: none

### `_legacyFloorActive/function` — CauldronVault.sol:183

- Signature: `function _legacyFloorActive() private view returns (bool)`
- Authority: internal (callers: floorPerNFT, redeem)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: True only when the collection's minter answers `vault()` with exactly one word equal to this vault (`r` CauldronVault.sol:187); a wrong, short or reverting answer means the unified floor is active and legacy redemption is off.
- Edges: `CauldronVault._minter (CauldronVault.sol:186), TRUSTED, in-cluster`
- Observations: none

### `close/function` — CauldronVault.sol:199

- Signature: `function close() external nonReentrant returns (uint256 swept)`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (msg.sender != registry) revert NotRegistry(); (CauldronVault.sol:200)`
- Reads: `registry (line 200)`
- Writes: `closed (line 201)`
- Value: sends native through `value` (line 206)
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `close` (CauldronVault.sol:199) is a external node with 1 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `CauldronVault.close (CauldronVault.sol:199), TRUSTED, in-cluster`
- Observations: none


## `MockAggregator`

### `constructor/constructor` — MockAggregator.sol:54

- Signature: `constructor(string memory desc, int256 initialAnswer)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `_answer (line 57)`; `description (line 56)`; `owner (line 55)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (MockAggregator.sol:54) is a constructor node with 0 direct storage/immutable reads, 3 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `onlyOwner/modifier` — MockAggregator.sol:60

- Signature: `modifier onlyOwner()`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `owner (line 61)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `onlyOwner` (MockAggregator.sol:60) is a modifier node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `MockAggregator.onlyOwner (MockAggregator.sol:60), TRUSTED, in-cluster`
- Observations: none

### `transferOwnership/function` — MockAggregator.sol:65

- Signature: `function transferOwnership(address to) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (MockAggregator.sol:65)`
- Reads: none
- Writes: `owner (line 65)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `transferOwnership` (MockAggregator.sol:65) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `MockAggregator.transferOwnership (MockAggregator.sol:65), TRUSTED, in-cluster`
- Observations: none

### `peg/function` — MockAggregator.sol:68

- Signature: `function peg(int256 answer) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (MockAggregator.sol:68)`
- Reads: none
- Writes: `_answer (line 69)`; `_round (line 70)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `peg` (MockAggregator.sol:68) is a external node with 0 direct storage/immutable reads, 2 direct writes, and 1 resolved call edges.
- Edges: `MockAggregator.peg (MockAggregator.sol:68), TRUSTED, in-cluster`
- Observations: none

### `setStale/function` — MockAggregator.sol:76

- Signature: `function setStale(bool s) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (MockAggregator.sol:76)`
- Reads: none
- Writes: `stale (line 76)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setStale` (MockAggregator.sol:76) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `MockAggregator.setStale (MockAggregator.sol:76), TRUSTED, in-cluster`
- Observations: none

### `setDown/function` — MockAggregator.sol:82

- Signature: `function setDown(bool d) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (MockAggregator.sol:82)`
- Reads: none
- Writes: `down (line 82)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setDown` (MockAggregator.sol:82) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `MockAggregator.setDown (MockAggregator.sol:82), TRUSTED, in-cluster`
- Observations: none

### `latestRoundData/function` — MockAggregator.sol:84

- Signature: `function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_answer (line 92)`; `_round (line 92)`; `down (line 89)`; `stale (line 91)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `latestRoundData` (MockAggregator.sol:84) is a external node with 4 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `MockQuoteToken`

### `constructor/constructor` — MockQuoteToken.sol:20

- Signature: `constructor(string memory name_, string memory symbol_, uint8 dec_) ERC20(name_, symbol_)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `_decimals (line 21)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (MockQuoteToken.sol:20) is a constructor node with 0 direct storage/immutable reads, 1 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `decimals/function` — MockQuoteToken.sol:24

- Signature: `function decimals() public view override returns (uint8)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_decimals (line 24)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `decimals` (MockQuoteToken.sol:24) is a public node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `MockQuoteToken.decimals (MockQuoteToken.sol:24), TRUSTED, in-cluster`
- Observations: none

### `mint/function` — MockQuoteToken.sol:27

- Signature: `function mint(address to, uint256 amount) external`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `mint` (MockQuoteToken.sol:27) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `MockQuoteToken.mint (MockQuoteToken.sol:27), TRUSTED, in-cluster`
- Observations: none


## `NativeQuoteZap`

### `constructor/constructor` — NativeQuoteZap.sol:80

- Signature: `constructor(IPoolManager _poolManager)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `poolManager (line 81)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (NativeQuoteZap.sol:80) is a constructor node with 0 direct storage/immutable reads, 1 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `zap/function` — NativeQuoteZap.sol:101

- Signature: `function zap(PoolKey calldata key, uint256 minOut) external payable returns (uint256 out)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 107)`
- Writes: none
- Value: receives or validates `msg.value` (line 102)
- Reachability: DERIVED from the current body: anyone; `zap` (NativeQuoteZap.sol:101) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 3 resolved call edges.
- Edges: `NativeQuoteZap.zap (NativeQuoteZap.sol:101), TRUSTED, in-cluster`; `IPoolManager.unlock (NativeQuoteZap.sol:107), TRUSTED, out-of-cluster`; `IERC20.transfer (NativeQuoteZap.sol:118), UNTRUSTED, out-of-cluster`
- Observations: none

### `unlockCallback/function` — NativeQuoteZap.sol:123

- Signature: `function unlockCallback(bytes calldata raw) external returns (bytes memory)`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (msg.sender != address(poolManager)) revert NotPoolManager(); (NativeQuoteZap.sol:124)`
- Reads: `poolManager (line 124)`
- Writes: none
- Value: sends native through `value` (line 147)
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `unlockCallback` (NativeQuoteZap.sol:123) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `NativeQuoteZap.unlockCallback (NativeQuoteZap.sol:123), TRUSTED, in-cluster`; `IPoolManager.swap (NativeQuoteZap.sol:132), TRUSTED, out-of-cluster`; `IPoolManager.sync (NativeQuoteZap.sol:146), TRUSTED, out-of-cluster`; `IPoolManager.settle (NativeQuoteZap.sol:147), TRUSTED, out-of-cluster`; `IPoolManager.take (NativeQuoteZap.sol:148), TRUSTED, out-of-cluster`
- Observations: none


## `IAggregatorV3 (declared in QuoteOracle.sol)`

### `decimals/function` — QuoteOracle.sol:5

- Signature: `function decimals() external view returns (uint8)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `decimals` (QuoteOracle.sol:5) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `latestRoundData/function` — QuoteOracle.sol:6

- Signature: `function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `latestRoundData` (QuoteOracle.sol:6) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `IERC20Decimals (declared in QuoteOracle.sol)`

### `decimals/function` — QuoteOracle.sol:13

- Signature: `function decimals() external view returns (uint8)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `decimals` (QuoteOracle.sol:13) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `QuoteOracle`

### `constructor/constructor` — QuoteOracle.sol:110

- Signature: `constructor(address _owner)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `owner (line 111)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (QuoteOracle.sol:110) is a constructor node with 0 direct storage/immutable reads, 1 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `onlyOwner/modifier` — QuoteOracle.sol:114

- Signature: `modifier onlyOwner()`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `owner (line 115)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `onlyOwner` (QuoteOracle.sol:114) is a modifier node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `QuoteOracle.onlyOwner (QuoteOracle.sol:114), TRUSTED, in-cluster`
- Observations: none

### `transferOwnership/function` — QuoteOracle.sol:119

- Signature: `function transferOwnership(address to) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteOracle.sol:119)`
- Reads: none
- Writes: `owner (line 119)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `transferOwnership` (QuoteOracle.sol:119) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `QuoteOracle.transferOwnership (QuoteOracle.sol:119), TRUSTED, in-cluster`
- Observations: none

### `setFeed/function` — QuoteOracle.sol:131

- Signature: `function setFeed(address quote, address aggregator, uint32 heartbeat, uint8 quoteDecimals) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteOracle.sol:133)`
- Reads: none
- Writes: `feeds (line 140)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setFeed` (QuoteOracle.sol:131) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `setPegged/function` — QuoteOracle.sol:153

- Signature: `function setPegged(address quote, uint8 dec) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteOracle.sol:153)`
- Reads: none
- Writes: `feeds (line 158)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setPegged` (QuoteOracle.sol:153) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `QuoteOracle.setPegged (QuoteOracle.sol:153), TRUSTED, in-cluster`
- Observations: none

### `setBounds/function` — QuoteOracle.sol:175

- Signature: `function setBounds(address quote, uint128 minUsd, uint128 maxUsd) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteOracle.sol:175)`
- Reads: `feeds (line 177)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setBounds` (QuoteOracle.sol:175) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `QuoteOracle.setBounds (QuoteOracle.sol:175), TRUSTED, in-cluster`
- Observations: none

### `setSequencer/function` — QuoteOracle.sol:182

- Signature: `function setSequencer(address feed, uint32 grace) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteOracle.sol:182)`
- Reads: none
- Writes: `gracePeriod (line 184)`; `sequencerUptime (line 183)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setSequencer` (QuoteOracle.sol:182) is a external node with 0 direct storage/immutable reads, 2 direct writes, and 1 resolved call edges.
- Edges: `QuoteOracle.setSequencer (QuoteOracle.sol:182), TRUSTED, in-cluster`
- Observations: none

### `usdPerRawUnit/function` — QuoteOracle.sol:202

- Signature: `function usdPerRawUnit(address quote) external view returns (uint256 factor)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `feeds (line 203)`
- Writes: none
- Value: NONE
- Reachability: USD value of one raw unit of `quote`, scaled 1e18, or zero for cannot-judge. Pegged assets return one dollar per whole token (`pegged` QuoteOracle.sol:210), unset feeds and a down sequencer return zero (`_sequencerOk` QuoteOracle.sol:212). The round is read through a bounded fixed-width decoder (`_readRound` QuoteOracle.sol:232); non-positive, stale or future answers return zero (`heartbeat` QuoteOracle.sol:241), feed decimals are read the same bounded way (`_readWords` QuoteOracle.sol:243), and any scaling that cannot be represented returns zero instead of reverting (`perWhole` QuoteOracle.sol:277). Owner bounds filter out-of-band prices (`minUsd` QuoteOracle.sol:267).
- Edges: `QuoteOracle._sequencerOk (QuoteOracle.sol:212), TRUSTED, in-cluster`; `QuoteOracle._readRound (QuoteOracle.sol:232), TRUSTED, in-cluster`; `QuoteOracle._readWords (QuoteOracle.sol:243), TRUSTED, in-cluster`
- Observations: none

### `cachedUsdPerRawUnit/function` — QuoteOracle.sol:335

- Signature: `function cachedUsdPerRawUnit(address quote) external returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `TTL (line 337)`; `cache (line 336)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `cachedUsdPerRawUnit` (QuoteOracle.sol:335) is a external node with 2 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `QuoteOracle.cachedUsdPerRawUnit (QuoteOracle.sol:335), TRUSTED, in-cluster`; `QuoteOracle.usdPerRawUnit (QuoteOracle.sol:340), TRUSTED, in-cluster`
- Observations: none

### `priceable/function` — QuoteOracle.sol:347

- Signature: `function priceable(address quote) external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `priceable` (QuoteOracle.sol:347) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `QuoteOracle.priceable (QuoteOracle.sol:347), TRUSTED, in-cluster`; `QuoteOracle.usdPerRawUnit (QuoteOracle.sol:348), TRUSTED, in-cluster`
- Observations: none

### `_sequencerOk/function` — QuoteOracle.sol:351

- Signature: `function _sequencerOk() internal view returns (bool)`
- Authority: internal (callers: usdPerRawUnit)
- Gate evidence: `UNGATED`
- Reads: `sequencerUptime (line 352)`; `gracePeriod (line 362)`
- Writes: none
- Value: NONE
- Reachability: No sequencer feed means true (`s` QuoteOracle.sol:353). Otherwise the uptime round is read through the bounded decoder (`_readRound` QuoteOracle.sol:359); invalid data, a down flag, a zero or future start, or an unexpired grace period all return false (`gracePeriod` QuoteOracle.sol:362).
- Edges: `QuoteOracle._readRound (QuoteOracle.sol:359), TRUSTED, in-cluster`
- Observations: none

### `_readRound/function` — QuoteOracle.sol:367

- Signature: `function _readRound(address feed) private view returns (bool, int256, uint256, uint256)`
- Authority: internal (callers: usdPerRawUnit, _sequencerOk)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Reads latestRoundData as exactly five words (`_readWords` QuoteOracle.sol:368) and rejects round ids that do not fit uint80 (`answeredInRound` QuoteOracle.sol:372), so a malformed reply is reported invalid instead of reverting the caller.
- Edges: `QuoteOracle._readWords (QuoteOracle.sol:368), TRUSTED, in-cluster`
- Observations: none

### `_readWords/function` — QuoteOracle.sol:379

- Signature: `function _readWords(address target, bytes4 selector, uint256 words) private view returns (bool ok, bytes memory result)`
- Authority: internal (callers: _readRound, usdPerRawUnit)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Bounded STATICCALL: allocates exactly the expected number of words (`result` QuoteOracle.sol:383), copies at most that much return data and succeeds only if the target returned at least that many bytes (`ok` QuoteOracle.sol:386).
- Edges: none
- Observations: none


## `QuoteRotator`

### `constructor/constructor` — QuoteRotator.sol:99

- Signature: `constructor(address _registry, IPoolManager _poolManager)`
- Authority: deployer (constructor executes once)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `owner (line 102)`; `poolManager (line 101)`; `registry (line 100)`
- Value: NONE
- Reachability: DERIVED from the current body: deployer (constructor executes once); `constructor` (QuoteRotator.sol:99) is a constructor node with 0 direct storage/immutable reads, 3 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `onlyRegistry/modifier` — QuoteRotator.sol:134

- Signature: `modifier onlyRegistry()`
- Authority: the registry or the registry's live perp engine
- Gate evidence: `if (msg.sender != registry && msg.sender != _liveEngine()) revert NotOwner(); (QuoteRotator.sol:135)`
- Reads: `registry (line 135, immutable)`
- Writes: none
- Value: NONE
- Reachability: Admits the registry or whatever engine the registry's hook currently points to (`_liveEngine` QuoteRotator.sol:135); anyone else reverts.
- Edges: `QuoteRotator._liveEngine (QuoteRotator.sol:135), TRUSTED, in-cluster`
- Observations: none

### `_liveEngine/function` — QuoteRotator.sol:140

- Signature: `function _liveEngine() internal view returns (address e)`
- Authority: internal (callers: onlyRegistry, withdraw)
- Gate evidence: `UNGATED`
- Reads: `registry (line 141, immutable)`
- Writes: none
- Value: NONE
- Reachability: Resolves the live engine by two static reads, registry `hook()` then hook `perpEngine()` (`h` QuoteRotator.sol:145); a failed or short reply yields the zero address, which matches no caller.
- Edges: none
- Observations: none

### `onlyOwner/modifier` — QuoteRotator.sol:150

- Signature: `modifier onlyOwner()`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `owner (line 151)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `onlyOwner` (QuoteRotator.sol:150) is a modifier node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator.onlyOwner (QuoteRotator.sol:150), TRUSTED, in-cluster`
- Observations: none

### `transferOwnership/function` — QuoteRotator.sol:155

- Signature: `function transferOwnership(address to) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteRotator.sol:155)`
- Reads: none
- Writes: `owner (line 155)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `transferOwnership` (QuoteRotator.sol:155) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator.transferOwnership (QuoteRotator.sol:155), TRUSTED, in-cluster`
- Observations: none

### `setVenue/function` — QuoteRotator.sol:210

- Signature: `function setVenue(PoolKey calldata route, bool allowed) external onlyOwner`
- Authority: owner
- Gate evidence: `function setVenue(PoolKey calldata route, bool allowed) external onlyOwner { (QuoteRotator.sol:210)`
- Reads: `_pairVenue (line 219)`
- Writes: `allowedVenue (line 212)`; `_pairVenue (line 218)`; `_pairVenue (line 220)`
- Value: NONE
- Reachability: Owner curation of exact pool ids (`allowedVenue` QuoteRotator.sol:212) and of the one route kept per currency pair (`_pairVenue` QuoteRotator.sol:218); revoking the id that is the pair's route also clears the route (`_pairVenue` QuoteRotator.sol:220).
- Edges: `QuoteRotator._pairKey (QuoteRotator.sol:216), TRUSTED, in-cluster`
- Observations: none

### `_pairKey/function` — QuoteRotator.sol:227

- Signature: `function _pairKey(address a, address b) internal pure returns (bytes32)`
- Authority: internal (callers: setVenue, venueFor)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Order-independent pair identity: hash of the two addresses sorted ascending (`a` QuoteRotator.sol:228).
- Edges: none
- Observations: none

### `venueFor/function` — QuoteRotator.sol:235

- Signature: `function venueFor(address a, address b) external view returns (PoolKey memory route, bool ok)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `_pairVenue (line 236)`; `allowedVenue (line 239)`
- Writes: none
- Value: NONE
- Reachability: Returns the pair's curated route and whether it is usable: nonzero tick spacing, still allowlisted and exactly the requested currencies in either order (`ok` QuoteRotator.sol:239). Used by the perp requote to find its conversion venue.
- Edges: `QuoteRotator._pairKey (QuoteRotator.sol:236), TRUSTED, in-cluster`
- Observations: none

### `isVenueAllowed/function` — QuoteRotator.sol:244

- Signature: `function isVenueAllowed(PoolKey calldata route) external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `allowedVenue (line 245)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `isVenueAllowed` (QuoteRotator.sol:244) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator.isVenueAllowed (QuoteRotator.sol:244), TRUSTED, in-cluster`
- Observations: none

### `setPlan/function` — QuoteRotator.sol:263

- Signature: `function setPlan( address from, address to, uint128 totalIn, uint128 sliceIn, uint256 minRate, uint32 interval ) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteRotator.sol:270)`
- Reads: none
- Writes: `plan (line 278)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setPlan` (QuoteRotator.sol:263) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator._allowed (QuoteRotator.sol:276), TRUSTED, in-cluster`
- Observations: none

### `cancelPlan/function` — QuoteRotator.sol:295

- Signature: `function cancelPlan() external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteRotator.sol:295)`
- Reads: none
- Writes: `plan (line 296)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `cancelPlan` (QuoteRotator.sol:295) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator.cancelPlan (QuoteRotator.sol:295), TRUSTED, in-cluster`
- Observations: none

### `setKeeperBps/function` — QuoteRotator.sol:300

- Signature: `function setKeeperBps(uint16 bps) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteRotator.sol:300)`
- Reads: none
- Writes: `keeperBps (line 302)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setKeeperBps` (QuoteRotator.sol:300) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator.setKeeperBps (QuoteRotator.sol:300), TRUSTED, in-cluster`
- Observations: none

### `nextSliceSize/function` — QuoteRotator.sol:310

- Signature: `function nextSliceSize() public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `plan (line 311)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `nextSliceSize` (QuoteRotator.sol:310) is a public node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `QuoteRotator.nextSliceSize (QuoteRotator.sol:310), TRUSTED, in-cluster`; `QuoteRotator._balanceOf (QuoteRotator.sol:320), TRUSTED, in-cluster`
- Observations: none

### `rotateStep/function` — QuoteRotator.sol:331

- Signature: `function rotateStep(PoolKey calldata route) external returns (uint256 out)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `BPS (line 363)`; `WAD (line 357)`; `allowedVenue (line 346)`; `keeperBps (line 363)`; `plan (line 332)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `rotateStep` (QuoteRotator.sol:331) is a external node with 5 direct storage/immutable reads, 0 direct writes, and 6 resolved call edges.
- Edges: `QuoteRotator.rotateStep (QuoteRotator.sol:331), TRUSTED, in-cluster`; `QuoteRotator.nextSliceSize (QuoteRotator.sol:335), TRUSTED, in-cluster`; `QuoteRotator._allowed (QuoteRotator.sol:337), TRUSTED, in-cluster`; `QuoteRotator._routeMatches (QuoteRotator.sol:338), TRUSTED, in-cluster`; `QuoteRotator._swap (QuoteRotator.sol:354), TRUSTED, in-cluster`; `QuoteRotator._send (QuoteRotator.sol:364), TRUSTED, in-cluster`
- Observations: none

### `swapOnce/function` — QuoteRotator.sol:382

- Signature: `function swapOnce( PoolKey calldata route, address from, address to, uint256 amountIn, uint256 minOut ) external onlyRegistry returns (uint256 out)`
- Authority: the registry or the live perp engine
- Gate evidence: `) external onlyRegistry returns (uint256 out) { (QuoteRotator.sol:388)`
- Reads: `allowedVenue (line 406)`
- Writes: none
- Value: Swaps `amountIn` of `from` held by the rotator into `to` through the curated pool (`_swap` QuoteRotator.sol:438); proceeds stay in the rotator for the caller to withdraw.
- Reachability: Registry or live engine only (`onlyRegistry` QuoteRotator.sol:388). Requires a nonzero size, an allowlisted destination (`_allowed` QuoteRotator.sol:390), a route matching the pair (`_routeMatches` QuoteRotator.sol:391) and a curated pool id (`allowedVenue` QuoteRotator.sol:406). A live oracle floor is mandatory (`NotPriceable` QuoteRotator.sol:436) and the output must meet the larger of the caller's minimum and that floor (`SlippageTooHigh` QuoteRotator.sol:439).
- Edges: `QuoteRotator._allowed (QuoteRotator.sol:390), TRUSTED, in-cluster`; `QuoteRotator._routeMatches (QuoteRotator.sol:391), TRUSTED, in-cluster`; `QuoteRotator._oracleFloor (QuoteRotator.sol:419), TRUSTED, in-cluster`; `QuoteRotator._swap (QuoteRotator.sol:438), TRUSTED, in-cluster`
- Observations: none

### `setRotationSlipBps/function` — QuoteRotator.sol:451

- Signature: `function setRotationSlipBps(uint16 bps) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteRotator.sol:451)`
- Reads: none
- Writes: `rotationSlipBps (line 453)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setRotationSlipBps` (QuoteRotator.sol:451) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator.setRotationSlipBps (QuoteRotator.sol:451), TRUSTED, in-cluster`
- Observations: none

### `_oracleFloor/function` — QuoteRotator.sol:469

- Signature: `function _oracleFloor(address from, address to, uint256 amountIn) internal returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `BPS (line 488)`; `rotationSlipBps (line 488)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_oracleFloor` (QuoteRotator.sol:469) is a internal node with 2 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `QuoteRotator._usdLive (QuoteRotator.sol:483), TRUSTED, in-cluster`; `QuoteRotator._usdLive (QuoteRotator.sol:485), TRUSTED, in-cluster`
- Observations: none

### `setArbParams/function` — QuoteRotator.sol:529

- Signature: `function setArbParams(address oracle, uint16 keeperBps, uint256 minProfitUsd) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteRotator.sol:529)`
- Reads: `keeperBps (line 529)`
- Writes: `arbKeeperBps (line 532)`; `minArbProfitUsd (line 533)`; `quoteOracle (line 531)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setArbParams` (QuoteRotator.sol:529) is a external node with 1 direct storage/immutable reads, 3 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator.setArbParams (QuoteRotator.sol:529), TRUSTED, in-cluster`
- Observations: none

### `setMaxArbNotionalUsd/function` — QuoteRotator.sol:539

- Signature: `function setMaxArbNotionalUsd(uint256 maxNotionalUsd) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (QuoteRotator.sol:539)`
- Reads: none
- Writes: `maxArbNotionalUsd (line 540)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setMaxArbNotionalUsd` (QuoteRotator.sol:539) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator.setMaxArbNotionalUsd (QuoteRotator.sol:539), TRUSTED, in-cluster`
- Observations: none

### `arbStep/function` — QuoteRotator.sol:577

- Signature: `function arbStep(PoolKey calldata cheap, PoolKey calldata dear, uint256 amountIn) external returns (uint256 profitUsd)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `BPS (line 656)`; `allowedVenue (line 597)`; `arbKeeperBps (line 656)`; `maxArbNotionalUsd (line 642)`; `minArbProfitUsd (line 651)`; `poolManager (line 621)`
- Writes: `arbBlock (line 643)`; `arbUsdThisBlock (line 643)`
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `arbStep` (QuoteRotator.sol:577) is a external node with 6 direct storage/immutable reads, 2 direct writes, and 6 resolved call edges.
- Edges: `QuoteRotator._allowed (QuoteRotator.sol:604), TRUSTED, in-cluster`; `QuoteRotator._usdLive (QuoteRotator.sol:618), TRUSTED, in-cluster`; `IPoolManager.unlock (QuoteRotator.sol:621), TRUSTED, out-of-cluster`; `QuoteRotator._usdLive (QuoteRotator.sol:629), TRUSTED, in-cluster`; `QuoteRotator._usdLive (QuoteRotator.sol:630), TRUSTED, in-cluster`; `QuoteRotator._send (QuoteRotator.sol:657), TRUSTED, in-cluster`
- Observations: none

### `_usdLive/function` — QuoteRotator.sol:666

- Signature: `function _usdLive(address quote, uint256 raw) internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `quoteOracle (line 667)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_usdLive` (QuoteRotator.sol:666) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `QuoteRotator._usdLive (QuoteRotator.sol:666), TRUSTED, in-cluster`; `QuoteOracle.usdPerRawUnit (QuoteRotator.sol:670), TRUSTED, in-cluster`
- Observations: none

### `withdraw/function` — QuoteRotator.sol:697

- Signature: `function withdraw(address asset, address to, uint256 amount) external`
- Authority: registry or owner to any recipient; the live engine only to itself
- Gate evidence: `if (msg.sender != registry && msg.sender != owner) { (QuoteRotator.sol:700)`
- Reads: `registry (line 700, immutable)`; `owner (line 700)`
- Writes: none
- Value: Sends `amount` of `asset` from the rotator to `to` (`_send` QuoteRotator.sol:707).
- Reachability: Registry and owner may withdraw to any nonzero recipient (`to` QuoteRotator.sol:706); the live engine may withdraw only to itself (`_liveEngine` QuoteRotator.sol:704).
- Edges: `QuoteRotator._liveEngine (QuoteRotator.sol:704), TRUSTED, in-cluster`; `QuoteRotator._send (QuoteRotator.sol:707), TRUSTED, in-cluster`
- Observations: none

### `_swap/function` — QuoteRotator.sol:715

- Signature: `function _swap(PoolKey calldata route, address from, address to, uint256 size) internal returns (uint256 out)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 720)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_swap` (QuoteRotator.sol:715) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `IPoolManager.unlock (QuoteRotator.sol:720), TRUSTED, out-of-cluster`
- Observations: none

### `unlockCallback/function` — QuoteRotator.sol:724

- Signature: `function unlockCallback(bytes calldata data) external returns (bytes memory)`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (msg.sender != address(poolManager)) revert NotOwner(); (QuoteRotator.sol:725)`
- Reads: `poolManager (line 725)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `unlockCallback` (QuoteRotator.sol:724) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `QuoteRotator.unlockCallback (QuoteRotator.sol:724), TRUSTED, in-cluster`; `QuoteRotator._arbCallback (QuoteRotator.sol:730), TRUSTED, in-cluster`; `IPoolManager.swap (QuoteRotator.sol:735), TRUSTED, out-of-cluster`; `QuoteRotator._settle (QuoteRotator.sol:746), TRUSTED, in-cluster`; `IPoolManager.take (QuoteRotator.sol:747), TRUSTED, out-of-cluster`
- Observations: none

### `_arbCallback/function` — QuoteRotator.sol:756

- Signature: `function _arbCallback(bytes calldata data) internal returns (bytes memory)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 761)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_arbCallback` (QuoteRotator.sol:756) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `QuoteRotator._arbCallback (QuoteRotator.sol:756), TRUSTED, in-cluster`; `IPoolManager.swap (QuoteRotator.sol:761), TRUSTED, out-of-cluster`; `IPoolManager.swap (QuoteRotator.sol:771), TRUSTED, out-of-cluster`; `QuoteRotator._settle (QuoteRotator.sol:778), TRUSTED, in-cluster`; `IPoolManager.take (QuoteRotator.sol:779), TRUSTED, out-of-cluster`
- Observations: none

### `_settle/function` — QuoteRotator.sol:783

- Signature: `function _settle(address cur, uint256 amount) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 785)`
- Writes: none
- Value: sends native through `value` (line 785)
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_settle` (QuoteRotator.sol:783) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 5 resolved call edges.
- Edges: `QuoteRotator._settle (QuoteRotator.sol:783), TRUSTED, in-cluster`; `IPoolManager.settle (QuoteRotator.sol:785), TRUSTED, out-of-cluster`; `IPoolManager.sync (QuoteRotator.sol:787), TRUSTED, out-of-cluster`; `QuoteRotator._safeTransfer (QuoteRotator.sol:788), TRUSTED, in-cluster`; `IPoolManager.settle (QuoteRotator.sol:789), TRUSTED, out-of-cluster`
- Observations: none

### `_send/function` — QuoteRotator.sol:793

- Signature: `function _send(address cur, address to, uint256 amount) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native through `value` (line 796)
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_send` (QuoteRotator.sol:793) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `QuoteRotator._send (QuoteRotator.sol:793), TRUSTED, in-cluster`; `QuoteRotator._safeTransfer (QuoteRotator.sol:799), TRUSTED, in-cluster`
- Observations: none

### `_safeTransfer/function` — QuoteRotator.sol:806

- Signature: `function _safeTransfer(address token, address to, uint256 amount) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_safeTransfer` (QuoteRotator.sol:806) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `QuoteRotator._safeTransfer (QuoteRotator.sol:806), TRUSTED, in-cluster`; `IERC20.transfer (QuoteRotator.sol:815), UNTRUSTED, out-of-cluster`
- Observations: none

### `_routeMatches/function` — QuoteRotator.sol:819

- Signature: `function _routeMatches(PoolKey calldata route, address from, address to) internal pure returns (bool)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_routeMatches` (QuoteRotator.sol:819) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `_balanceOf/function` — QuoteRotator.sol:829

- Signature: `function _balanceOf(address asset) internal view returns (uint256)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_balanceOf` (QuoteRotator.sol:829) is a internal node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `QuoteRotator._balanceOf (QuoteRotator.sol:829), TRUSTED, in-cluster`
- Observations: none

### `_allowed/function` — QuoteRotator.sol:833

- Signature: `function _allowed(address quote) internal view returns (bool)`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `registry (line 836)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_allowed` (QuoteRotator.sol:833) is a internal node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `QuoteRotator._allowed (QuoteRotator.sol:833), TRUSTED, in-cluster`; `CauldronRegistry.allowedQuote (QuoteRotator.sol:836), TRUSTED, out-of-cluster`
- Observations: none

### `receive/receive` — QuoteRotator.sol:840

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `receive` (QuoteRotator.sol:840) is a receive node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `ITreasuryGovernor (declared in RedemptionExt.sol)`

### `allowance/function` — RedemptionExt.sol:46

- Signature: `function allowance() external view returns (address quote, uint16 remainingBps)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `allowance` (RedemptionExt.sol:46) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `consume/function` — RedemptionExt.sol:47

- Signature: `function consume(uint16 bps, bool fromPrimary) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `consume` (RedemptionExt.sol:47) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `migrationMandateSpent/function` — RedemptionExt.sol:50

- Signature: `function migrationMandateSpent() external view returns (bool)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `migrationMandateSpent` (RedemptionExt.sol:50) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `IQuoteRotator (declared in RedemptionExt.sol)`

### `swapOnce/function` — RedemptionExt.sol:54

- Signature: `function swapOnce(PoolKey calldata route, address from, address to, uint256 amountIn, uint256 minOut) external returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `swapOnce` (RedemptionExt.sol:54) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `withdraw/function` — RedemptionExt.sol:56

- Signature: `function withdraw(address asset, address to, uint256 amount) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `withdraw` (RedemptionExt.sol:56) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `IHookVolume (declared in RedemptionExt.sol)`

### `linkVolume/function` — RedemptionExt.sol:60

- Signature: `function linkVolume(PoolId primary, PoolId secondary) external`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: declaration only; implementation authority is outside this node; `linkVolume` (RedemptionExt.sol:60) is a declaration-only node with 0 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none


## `RedemptionExt`

### `redeemOgFren/function` — RedemptionExt.sol:81

- Signature: `function redeemOgFren(uint256 mifrenTokenId) external nonReentrant returns (uint256 amount)`
- Authority: anyone holding a genesis (OG) MiFren
- Gate evidence: `if (IERC721(mifrens).ownerOf(mifrenTokenId) != msg.sender) revert NotOwnerOf(); (RedemptionExt.sol:87)`
- Reads: `summoned (line 83)`; `genesisShares (line 86)`; `mifrens (line 87)`; `genesisReserveOutstanding (line 94)`; `currentGeneration (line 101)`; `generationReservePositionId (line 104)`
- Writes: `genesisReserveOutstanding (line 94)`; `treasuryHeldOg (line 98)`
- Value: Moves the OG NFT into registry custody (`custodyTransfer` RedemptionExt.sol:99) and pays the live floor from the reserve position to the caller (`claimFromReserve` RedemptionExt.sol:102).
- Reachability: Runs in the registry's storage by delegatecall. Blocked only by the emergency-aware pause (`_redeemBlocked` RedemptionExt.sol:82); OG ids only (`genesisShares` RedemptionExt.sol:86); caller must own the fren. Debits outstanding and counts the fren as treasury-held before custody and the reserve pull (`treasuryHeldOg` RedemptionExt.sol:98), so redemption is floor-neutral for remaining holders; a short reserve beyond the dust tolerance reverts everything (`NoBalance` RedemptionExt.sol:111). Reentrancy-guarded.
- Edges: `CauldronBase._redeemBlocked (RedemptionExt.sol:82), TRUSTED, out-of-cluster`; `CauldronBase.floorPerFren (RedemptionExt.sol:89), TRUSTED, out-of-cluster`; `IMiFrensContinuable.custodyTransfer (RedemptionExt.sol:99), TRUSTED, out-of-cluster`; `PoolOps.claimFromReserve (RedemptionExt.sol:102), TRUSTED, library`
- Observations: none

### `buyTreasuryOgFren/function` — RedemptionExt.sol:122

- Signature: `function buyTreasuryOgFren(uint256 mifrenTokenId) external nonReentrant returns (uint256 paid)`
- Authority: anyone (buyer)
- Gate evidence: `UNGATED`
- Reads: `summoned (line 123)`; `genesisShares (line 124)`; `mifrens (line 126)`; `treasuryHeldOg (line 135)`
- Writes: `treasuryHeldOg (line 135)`
- Value: Pulls twice the floor in the live token from the buyer into the reserve (`_pullGrow` RedemptionExt.sol:136) and releases the fren from registry custody to the buyer (`custodyTransfer` RedemptionExt.sol:137).
- Reachability: Only for a genesis fren the registry holds (`NotOwnerOf` RedemptionExt.sol:126). Prices at twice the live floor while the fren is still outside the divisor (`paid` RedemptionExt.sol:128), returns it to the active set, grows the reserve with the payment and releases custody. Reentrancy-guarded.
- Edges: `CauldronBase.floorPerFren (RedemptionExt.sol:128), TRUSTED, out-of-cluster`; `RedemptionExt._pullGrow (RedemptionExt.sol:136), TRUSTED, in-cluster`; `IMiFrensContinuable.custodyTransfer (RedemptionExt.sol:137), TRUSTED, out-of-cluster`
- Observations: none

### `donateToReserve/function` — RedemptionExt.sol:148

- Signature: `function donateToReserve(uint256 amount) external nonReentrant`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `summoned (line 149)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `donateToReserve` (RedemptionExt.sol:148) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `RedemptionExt.donateToReserve (RedemptionExt.sol:148), TRUSTED, in-cluster`; `RedemptionExt._pullGrow (RedemptionExt.sol:151), TRUSTED, in-cluster`
- Observations: none

### `materializeLegacyReserve/function` — RedemptionExt.sol:159

- Signature: `function materializeLegacyReserve() external nonReentrant returns (uint256 added)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `summoned (line 160)`; `currentGeneration (line 161)`; `positionManager (line 164)`; `hook (line 164)`; `collectionLedger (line 165)`; `mifrens (line 165)`; `genesisShares (line 165)`; `generationCollection (line 165)`; `generationToken (line 166)`
- Writes: `genesisReserveOutstanding (line 185)`
- Value: Sweeps the hook's held legacy-buyback tokens into the reserve position (`materializeLegacy` RedemptionExt.sol:163).
- Reachability: Permissionless keeper step: moves live buyback tokens into the reserve and credits the collection ledger by the measured amount, with the genesis share credited to OG holders at once (`genesisReserveOutstanding` RedemptionExt.sol:185). Reentrancy-guarded.
- Edges: `PoolOps.materializeLegacy (RedemptionExt.sol:163), TRUSTED, library`
- Observations: none

### `_pullGrow/function` — RedemptionExt.sol:192

- Signature: `function _pullGrow(address from, uint256 amount) private returns (uint256 added)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `currentGeneration (line 193)`; `generationPoolKey (line 197)`; `generationReservePositionId (line 197)`; `generationToken (line 194)`; `positionManager (line 196)`; `reserveTickLower (line 198)`; `reserveTickUpper (line 198)`
- Writes: `genesisReserveOutstanding (line 209)`
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_pullGrow` (RedemptionExt.sol:192) is a private node with 7 direct storage/immutable reads, 1 direct writes, and 3 resolved call edges.
- Edges: `RedemptionExt._pullGrow (RedemptionExt.sol:192), TRUSTED, in-cluster`; `PoolOps.addToReserve (RedemptionExt.sol:195), TRUSTED, out-of-cluster`; `RedemptionExt.floorPerFren (RedemptionExt.sol:210), TRUSTED, out-of-cluster`
- Observations: none

### `setRotationWiring/function` — RedemptionExt.sol:287

- Signature: `function setRotationWiring(address rotator, address governor) external onlyOwner`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (RedemptionExt.sol:287)`
- Reads: none
- Writes: `governor (line 287)`; `quoteRotator (line 289)`; `treasuryGovernor (line 290)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `setRotationWiring` (RedemptionExt.sol:287) is a external node with 0 direct storage/immutable reads, 3 direct writes, and 1 resolved call edges.
- Edges: `RedemptionExt.setRotationWiring (RedemptionExt.sol:287), TRUSTED, in-cluster`
- Observations: none

### `rotateSlice/function` — RedemptionExt.sol:296

- Signature: `function rotateSlice( uint16 sliceBps, uint256 minOut, PoolKey calldata route ) external returns (uint256 moved, uint256 positionId)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `rotateSlice` (RedemptionExt.sol:296) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `RedemptionExt.rotateSliceFrom (RedemptionExt.sol:301), TRUSTED, in-cluster`
- Observations: none

### `rotateSliceFrom/function` — RedemptionExt.sol:307

- Signature: `function rotateSliceFrom( uint8 fromLeg, uint16 sliceBps, uint256 minOut, PoolKey calldata route ) public returns (uint256 moved, uint256 positionId)`
- Authority: anyone, within the treasury governor's approved rotation envelope
- Gate evidence: `if (remaining == 0) revert NoRotationApproved(); (RedemptionExt.sol:344)`
- Reads: `quoteRotator (line 319)`; `treasuryGovernor (line 328)`; `allowedQuote (line 349)`; `currentGeneration (line 355)`; `generationToken (line 356)`; `generationPositionId (line 374)`; `generationPoolKey (line 375)`; `generationLegs (line 400)`; `generationQuote (line 439)`
- Writes: `generationQuote (line 659)`
- Value: Removes a slice of the source position (`removePartial` RedemptionExt.sol:446), sends the quote to the rotator and swaps it (`swapOnce` RedemptionExt.sol:459), withdraws the proceeds (`withdraw` RedemptionExt.sol:460) and mints them with the removed tokens into the destination pair (`openOrAddPair` RedemptionExt.sol:536).
- Reachability: Permissionless execution of a governance-approved rotation: rotator and governor must be wired (`RotationNotWired` RedemptionExt.sol:320), the envelope must have budget for the slice (`remaining` RedemptionExt.sol:345), the destination allowlisted (`allowedQuote` RedemptionExt.sol:349) and the slice within bounds (`MAX_SLICE_BPS` RedemptionExt.sol:353). The source is the primary position or a recorded leg (`fromLeg` RedemptionExt.sol:373). The swap is floored by the rotator's oracle. Existing destination liquidity and, when returning to the launch quote, the launch position are consolidated into one tracked position (`removeAll` RedemptionExt.sol:527). The governor budget is consumed after success (`consume` RedemptionExt.sol:591). When a primary-sourced slice spends the whole migration mandate the generation is redenominated: quote, hook live key and the perp book are carried to the new quote (`requoteBook` RedemptionExt.sol:702), sync best-effort. No reentrancy guard; every callback in the path is owner-curated.
- Edges: `ITreasuryGovernor.allowance (RedemptionExt.sol:330), TRUSTED, in-cluster`; `PoolOps.removePartial (RedemptionExt.sol:446), TRUSTED, library`; `PoolOps.sendAsset (RedemptionExt.sol:458), TRUSTED, library`; `IQuoteRotator.swapOnce (RedemptionExt.sol:459), UNTRUSTED, out-of-cluster`; `IQuoteRotator.withdraw (RedemptionExt.sol:460), UNTRUSTED, out-of-cluster`; `RedemptionExt._legPosition (RedemptionExt.sol:506), TRUSTED, in-cluster`; `PoolOps.removeAll (RedemptionExt.sol:512), TRUSTED, library`; `PoolOps.openOrAddPair (RedemptionExt.sol:536), TRUSTED, library`; `IHookVolume.linkVolume (RedemptionExt.sol:550), TRUSTED, out-of-cluster`; `RedemptionExt._recordLeg (RedemptionExt.sol:577), TRUSTED, in-cluster`; `ITreasuryGovernor.consume (RedemptionExt.sol:591), TRUSTED, in-cluster`; `ITreasuryGovernor.migrationMandateSpent (RedemptionExt.sol:658), TRUSTED, in-cluster`; `IPerpBook.requoteBook (RedemptionExt.sol:702), TRUSTED, out-of-cluster`
- Observations: none

### `floorClaimableNow/function` — RedemptionExt.sol:776

- Signature: `function floorClaimableNow() external view returns (bool claimable, uint256 perFren)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `currentGeneration (line 778)`; `generationPoolId (line 780)`; `poolManager (line 780)`; `reserveTickUpper (line 781)`; `summoned (line 779)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `floorClaimableNow` (RedemptionExt.sol:776) is a external node with 5 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `RedemptionExt.floorClaimableNow (RedemptionExt.sol:776), TRUSTED, in-cluster`; `RedemptionExt.floorPerFren (RedemptionExt.sol:777), TRUSTED, out-of-cluster`
- Observations: none

### `claimByBurnUpTo/function` — RedemptionExt.sol:795

- Signature: `function claimByBurnUpTo(uint256 fromGen, uint256 maxAmount) external returns (uint256 claimedAmount)`
- Authority: caller restricted by explicit msg.sender check
- Gate evidence: `if (claimGate != address(0) && msg.sender != claimGate && msg.sender != hook.perpEngine()) { (RedemptionExt.sol:800)`
- Reads: `claimGate (line 800)`; `currentGeneration (line 799)`; `generationPoolKey (line 813)`; `generationReservePositionId (line 813)`; `generationToken (line 803)`; `hook (line 800)`; `positionManager (line 812)`; `reserveTickLower (line 813)`; `reserveTickUpper (line 813)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: caller restricted by explicit msg.sender check; `claimByBurnUpTo` (RedemptionExt.sol:795) is a external node with 9 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `CauldronHook.perpEngine (RedemptionExt.sol:800), TRUSTED, out-of-cluster`; `PoolOps.migrateUpTo (RedemptionExt.sol:811), TRUSTED, out-of-cluster`
- Observations: none

### `legCount/function` — RedemptionExt.sol:819

- Signature: `function legCount(uint256 gen) external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `generationLegs (line 820)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `legCount` (RedemptionExt.sol:819) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `RedemptionExt.legCount (RedemptionExt.sol:819), TRUSTED, in-cluster`
- Observations: none

### `legAt/function` — RedemptionExt.sol:824

- Signature: `function legAt(uint256 gen, uint256 i) external view returns (address quote, uint256 positionId, PoolKey memory key)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `generationLegs (line 829)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `legAt` (RedemptionExt.sol:824) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `_legPosition/function` — RedemptionExt.sol:839

- Signature: `function _legPosition(uint256 gen, address quote) private view returns (uint256 positionId, PoolKey memory key)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `generationLegs (line 844)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_legPosition` (RedemptionExt.sol:839) is a private node with 1 direct storage/immutable reads, 0 direct writes, and 0 resolved call edges.
- Edges: none
- Observations: none

### `_recordLeg/function` — RedemptionExt.sol:852

- Signature: `function _recordLeg(uint256 gen, address quote, uint256 positionId, PoolKey memory key) private`
- Authority: internal (callers: rotateSliceFrom)
- Gate evidence: `UNGATED`
- Reads: `generationLegs (line 853)`; `generationPoolKey (line 855)`
- Writes: `generationPositionId (line 856)`
- Value: NONE
- Reachability: Upserts the leg for a quote. A leg in the launch quote replaces the primary position id and drops any duplicate leg (`generationPositionId` RedemptionExt.sol:856); an existing leg updates its id; otherwise a new leg is appended. Emits LegOpened on every write so indexers follow the replacement id.
- Edges: none
- Observations: none

### `recoverLegs/function` — RedemptionExt.sol:925

- Signature: `function recoverLegs(uint256 gen) public returns (uint256 quoteOut, uint256 tokenOut)`
- Authority: anyone (past generations; or the live generation after a successor handoff)
- Gate evidence: `if (gen == 0 || gen >= currentGeneration) revert CannotClaimCurrentGen(); (RedemptionExt.sol:930)`
- Reads: `currentGeneration (line 926)`
- Writes: none
- Value: Past generations: unwinds rotated legs into registry custody and books the proceeds (`_recoverLegs` RedemptionExt.sol:931). Handed-off live generation: transfers leg NFTs to the successor (`_handOffLegs` RedemptionExt.sol:927).
- Reachability: Forwarded by the registry stub. For the live generation it acts only when the primary custody has provably moved to the recorded successor (`_handedOff` RedemptionExt.sol:926), handing every leg NFT to that successor; otherwise the live generation is refused (`CannotClaimCurrentGen` RedemptionExt.sol:930). Past generations are retried leg by leg and the recovered assets booked for the owner's sweep (`_bookLegProceeds` RedemptionExt.sol:932).
- Edges: `RedemptionExt._handedOff (RedemptionExt.sol:926), TRUSTED, in-cluster`; `RedemptionExt._handOffLegs (RedemptionExt.sol:927), TRUSTED, in-cluster`; `RedemptionExt._recoverLegs (RedemptionExt.sol:931), TRUSTED, in-cluster`; `RedemptionExt._bookLegProceeds (RedemptionExt.sol:932), TRUSTED, in-cluster`
- Observations: none

### `_handedOff/function` — RedemptionExt.sol:938

- Signature: `function _handedOff(uint256 gen) private view returns (bool)`
- Authority: internal (callers: recoverLegs)
- Gate evidence: `UNGATED`
- Reads: `successor (line 939)`; `generationReservePositionId (line 940)`; `generationPositionId (line 941)`; `positionManager (line 942)`
- Writes: none
- Value: NONE
- Reachability: True when a successor is recorded and owns the generation's reserve NFT, or its active NFT if there is no reserve (`ownerOf` RedemptionExt.sol:942).
- Edges: `IERC721.ownerOf (RedemptionExt.sol:942), TRUSTED, out-of-cluster`
- Observations: none

### `_handOffLegs/function` — RedemptionExt.sol:948

- Signature: `function _handOffLegs(uint256 gen) private`
- Authority: internal (callers: recoverLegs)
- Gate evidence: `UNGATED`
- Reads: `successor (line 949)`; `generationLegs (line 950)`; `positionManager (line 956)`
- Writes: `generationLegs (line 950)`
- Value: Transfers every recorded leg position NFT from the registry to the successor (`transferFrom` RedemptionExt.sol:956); liquidity is not touched.
- Reachability: Pops each leg and transfers its NFT to the successor (`legs` RedemptionExt.sol:955); all-or-nothing, so one failed transfer leaves every leg recorded.
- Edges: `IERC721.transferFrom (RedemptionExt.sol:956), TRUSTED, out-of-cluster`
- Observations: none

### `_bookLegProceeds/function` — RedemptionExt.sol:984

- Signature: `function _bookLegProceeds(uint256 gen, uint256 quoteOut, uint256 tokenOut) internal`
- Authority: internal; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `generationPoolKey (line 986)`; `generationToken (line 991)`
- Writes: `legProceeds (line 987)`
- Value: NONE
- Reachability: DERIVED from the current body: internal; reachable only through Solidity callers; `_bookLegProceeds` (RedemptionExt.sol:984) is a internal node with 2 direct storage/immutable reads, 1 direct writes, and 1 resolved call edges.
- Edges: `RedemptionExt._bookLegProceeds (RedemptionExt.sol:984), TRUSTED, in-cluster`
- Observations: none

### `emergencyWithdrawLP/function` — RedemptionExt.sol:1020

- Signature: `function emergencyWithdrawLP(uint256 gen) external nonReentrant`
- Authority: the emergency admin (enforced by the registry stub before delegating)
- Gate evidence: `function emergencyWithdrawLP(uint256) external onlyEmergency timelocked { _forwardToExt(); } (CauldronRegistry.sol:481)`
- Reads: `generationPoolKey (line 1021)`; `generationToken (line 1022)`; `positionManager (line 1023)`; `generationPositionId (line 1026)`; `generationReservePositionId (line 1028)`; `seeder (line 1034)`
- Writes: none
- Value: Removes the generation's active and reserve LP, any live seeder campaign and rotated legs into registry custody, then pays the tokens and the recovered quote in the generation's own currency0 to the caller (`sendAsset` RedemptionExt.sol:1044).
- Reachability: Body of the registry's break-glass. Reachable only through the registry stub, which enforces the emergency admin and consumes the armed timelock before delegating, so `msg.sender` is the admin; called directly on the facet it acts on the facet's own empty storage. Tears down the same positions as relaunch (`removeAll` RedemptionExt.sol:1027; `withdrawAll` RedemptionExt.sol:1036; `_recoverLegs` RedemptionExt.sol:1040) and pays both assets out. Reentrancy-guarded.
- Edges: `PoolOps.removeAll (RedemptionExt.sol:1027), TRUSTED, library`; `PoolOps.removeAll (RedemptionExt.sol:1030), TRUSTED, library`; `ISeeder.seeding (RedemptionExt.sol:1035), TRUSTED, out-of-cluster`; `ISeeder.withdrawAll (RedemptionExt.sol:1036), TRUSTED, out-of-cluster`; `RedemptionExt._recoverLegs (RedemptionExt.sol:1040), TRUSTED, in-cluster`; `PoolOps.sendAsset (RedemptionExt.sol:1043), TRUSTED, library`; `PoolOps.sendAsset (RedemptionExt.sol:1044), TRUSTED, library`
- Observations: none

### `recoverLegsAtTeardown/function` — RedemptionExt.sol:1048

- Signature: `function recoverLegsAtTeardown(uint256 gen) external returns (uint256, uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `recoverLegsAtTeardown` (RedemptionExt.sol:1048) is a external node with 0 direct storage/immutable reads, 0 direct writes, and 2 resolved call edges.
- Edges: `RedemptionExt.recoverLegsAtTeardown (RedemptionExt.sol:1048), TRUSTED, in-cluster`; `RedemptionExt._recoverLegs (RedemptionExt.sol:1049), TRUSTED, in-cluster`
- Observations: none

### `_recoverLegs/function` — RedemptionExt.sol:1052

- Signature: `function _recoverLegs(uint256 gen) private returns (uint256 quoteOut, uint256 tokenOut)`
- Authority: private; reachable only through Solidity callers
- Gate evidence: `UNGATED`
- Reads: `generationLegs (line 1053)`; `generationPoolKey (line 1083)`; `generationToken (line 1054)`; `positionManager (line 1055)`
- Writes: `legProceeds (line 1096)`
- Value: NONE
- Reachability: DERIVED from the current body: private; reachable only through Solidity callers; `_recoverLegs` (RedemptionExt.sol:1052) is a private node with 4 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `RedemptionExt._recoverLegs (RedemptionExt.sol:1052), TRUSTED, in-cluster`; `PoolOps.removeAll (RedemptionExt.sol:1089), TRUSTED, out-of-cluster`
- Observations: none

### `legProceedsOf/function` — RedemptionExt.sol:1110

- Signature: `function legProceedsOf(address asset) external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `legProceeds (line 1111)`
- Writes: none
- Value: NONE
- Reachability: DERIVED from the current body: anyone; `legProceedsOf` (RedemptionExt.sol:1110) is a external node with 1 direct storage/immutable reads, 0 direct writes, and 1 resolved call edges.
- Edges: `RedemptionExt.legProceedsOf (RedemptionExt.sol:1110), TRUSTED, in-cluster`
- Observations: none

### `sweepLegProceeds/function` — RedemptionExt.sol:1147

- Signature: `function sweepLegProceeds(address asset, address to) external onlyOwner returns (uint256 amount)`
- Authority: owner via onlyOwner
- Gate evidence: `onlyOwner (RedemptionExt.sol:1147)`
- Reads: none
- Writes: `legProceeds (line 1149)`
- Value: NONE
- Reachability: DERIVED from the current body: owner via onlyOwner; `sweepLegProceeds` (RedemptionExt.sol:1147) is a external node with 0 direct storage/immutable reads, 1 direct writes, and 2 resolved call edges.
- Edges: `RedemptionExt.sweepLegProceeds (RedemptionExt.sol:1147), TRUSTED, in-cluster`; `PoolOps.sendAsset (RedemptionExt.sol:1155), TRUSTED, out-of-cluster`
- Observations: none
