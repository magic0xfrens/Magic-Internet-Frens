# Function graph — `nft`

Current source-derived semantic map: **173 nodes** across **10 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `cauldron/MiFrensGenesis.sol` | 986 |
| `cauldron/CauldronCollection.sol` | 492 |
| `cauldron/CollectionLedger.sol` | 222 |
| `cauldron/CauldronGachaRouter.sol` | 619 |
| `cauldron/GachaLib.sol` | 282 |
| `cauldron/MiFrensDividend.sol` | 622 |
| `cauldron/MintCurvePolicy.sol` | 138 |
| `cauldron/CauldronFactory.sol` | 111 |
| `cauldron/ICreatorToken.sol` | 19 |
| `interfaces/INFTContract.sol` | 12 |


## `CauldronCollection`

### `constructor/constructor` — CauldronCollection.sol:133

- Signature: `constructor( string memory name_, string memory symbol_, address minter_, address registry_, uint256 maxSupply_, MetadataMode mode_, string memory baseURI_, address renderer_, address royaltyReceiver_, uint96 royaltyBps_ ) ERC721(name_, symbol_)`
- Authority: deployer (the CauldronFactory, which becomes `configurator`)
- Gate evidence: `UNGATED`
- Reads: `LIQUIDATOR_ID_BASE (line 148, constant)`
- Writes: `minter (line 155, immutable)`; `deployer (line 156, immutable)`; `configurator (line 157, immutable)`; `maxSupply (line 158, immutable)`; `mode (line 159)`; `renderer (line 160)`; `_baseTokenURI (line 161)`
- Value: NONE
- Reachability: Deployment only, from the factory's `new CauldronCollection` (CauldronFactory.sol:71). Three distinct authorities are frozen here: the mint right in `minter` (CauldronCollection.sol:155), the controller in `deployer` (CauldronCollection.sol:156) - which is the registry passed in, not the caller - and the factory in `configurator` (CauldronCollection.sol:157). All four are immutable, so no gate in this file can ever be rotated or renounced. The art cap is forced below the badge range at `LIQUIDATOR_ID_BASE` (CauldronCollection.sol:148). The royalty default is installed through `_setDefaultRoyalty` (CauldronCollection.sol:162) only when a non-zero receiver is passed.
- Edges: none
- Observations: comment at `admin` (CauldronCollection.sol:22) says there is no admin surface at all after construction; code at `setMetadata` (CauldronCollection.sol:361), `setTransferValidator` (CauldronCollection.sol:192), `setRarityOdds` (CauldronCollection.sol:486) and `setLiquidatorURI` (CauldronCollection.sol:373) are post-construction setters held by the registry

### `_update/function` — CauldronCollection.sol:169

- Signature: `function _update(address to, uint256 tokenId, address auth) internal override returns (address)`
- Authority: internal (callers: ERC721 _mint, _burn, _transfer and the inherited public transfer entry points)
- Gate evidence: `UNGATED`
- Reads: `transferValidator (line 174)`
- Writes: none
- Value: NONE
- Reachability: The single chokepoint for every id movement: reached from `_mint` (CauldronCollection.sol:213), `_mint` (CauldronCollection.sol:416), `_burn` (CauldronCollection.sol:446), `_transfer` (CauldronCollection.sol:456) and the inherited transfer functions. When `transferValidator` (CauldronCollection.sol:174) is non-zero an arbitrary external contract is called before the state change, so a reverting validator freezes minting, burning and the registry recycle alike. Unlike the genesis collection there is no dividend ping and no everMoved bookkeeping here.
- Edges: `ITransferValidator.validateTransfer (CauldronCollection.sol:176), UNTRUSTED, out-of-cluster`; `ERC721._update (CauldronCollection.sol:178), TRUSTED, out-of-cluster`
- Observations: none

### `getTransferValidator/function` — CauldronCollection.sol:182

- Signature: `function getTransferValidator() external view returns (address)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `transferValidator (line 183)`
- Writes: none
- Value: NONE
- Reachability: View of the slot written at `transferValidator` (CauldronCollection.sol:195).
- Edges: none
- Observations: none

### `getTransferValidationFunction/function` — CauldronCollection.sol:187

- Signature: `function getTransferValidationFunction() external pure returns (bytes4 functionSignature, bool isViewFunction)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure constant pair; returns the selector of `validateTransfer` (CauldronCollection.sol:188) and reads no state.
- Edges: none
- Observations: none

### `setTransferValidator/function` — CauldronCollection.sol:192

- Signature: `function setTransferValidator(address validator) external`
- Authority: registry (held in the immutable `deployer` slot)
- Gate evidence: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:193)`
- Reads: `deployer (line 193, immutable)`; `transferValidator (line 194)`
- Writes: `transferValidator (line 195)`
- Value: NONE
- Reachability: Only the registry address frozen at `deployer` (CauldronCollection.sol:156) can reach it, and that address is immutable so the right cannot be moved. Setting a non-zero value routes every move through the external check at `validateTransfer` (CauldronCollection.sol:176).
- Edges: none
- Observations: none

### `supportsInterface/function` — CauldronCollection.sol:199

- Signature: `function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: View; adds the creator-token id to the inherited answer at `supportsInterface` (CauldronCollection.sol:200).
- Edges: `ERC2981.supportsInterface (CauldronCollection.sol:200), TRUSTED, out-of-cluster`
- Observations: none

### `mint/function` — CauldronCollection.sol:207

- Signature: `function mint(address to) external returns (uint256 tokenId)`
- Authority: minter (the volume hook, frozen at deploy)
- Gate evidence: `if (msg.sender != minter) revert OnlyMinter(); (CauldronCollection.sol:208)`
- Reads: `minter (line 208, immutable)`; `totalMinted (line 209)`; `maxSupply (line 209, immutable)`; `totalMinted (line 210)`
- Writes: `totalMinted (line 210)`; `mintBlockOf (line 212)`
- Value: NONE
- Reachability: The only art-mint path in the collection: no public mint exists, and the caller must be the immutable `minter` (CauldronCollection.sol:208). Ids are strictly increasing from the pre-incremented `totalMinted` (CauldronCollection.sol:210) and are capped by `maxSupply` (CauldronCollection.sol:209). The token is created at `_mint` (CauldronCollection.sol:213) through the `_update` override (CauldronCollection.sol:169). Only the mint block is committed at `mintBlockOf` (CauldronCollection.sol:212); no rarity is assigned yet, so a fresh token reads as unrevealed at `revealed` (CauldronCollection.sol:471).
- Edges: none
- Observations: comment at `Rarity` (CauldronCollection.sol:99) says the tier is rolled at mint from an on-chain seed and stored; code at `mintBlockOf` (CauldronCollection.sol:212) stores only the block and `rarityOf` (CauldronCollection.sol:315) is written later inside the reveal path

### `reveal/function` — CauldronCollection.sol:219

- Signature: `function reveal(uint256 tokenId) external`
- Authority: holder of token
- Gate evidence: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (CauldronCollection.sol:256)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Wrapper; the ownership gate is in the callee at `ownerOf` (CauldronCollection.sol:256).
- Edges: `CauldronCollection._reveal (CauldronCollection.sol:220), TRUSTED, in-cluster`
- Observations: none

### `revealBatch/function` — CauldronCollection.sol:239

- Signature: `function revealBatch(uint256[] calldata tokenIds) external`
- Authority: holder of token
- Gate evidence: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (CauldronCollection.sol:256)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Batch wrapper bounded at fifty ids by the check at `BadBatch` (CauldronCollection.sol:243); every element still passes the per-token ownership gate at `ownerOf` (CauldronCollection.sol:256), so a single id the caller does not own reverts the whole batch.
- Edges: `CauldronCollection._reveal (CauldronCollection.sol:244), TRUSTED, in-cluster`
- Observations: none

### `_reveal/function` — CauldronCollection.sol:255

- Signature: `function _reveal(uint256 tokenId) private`
- Authority: internal (callers: reveal and revealBatch); caller must own token
- Gate evidence: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (CauldronCollection.sol:256)`
- Reads: `revealed (line 257)`; `mintBlockOf (line 258)`; `reanchored (line 301)`
- Writes: `reanchored (line 302)`; `mintBlockOf (line 303)`; `rarityOf (line 309)`; `revealed (line 310)`
- Value: NONE
- Reachability: Reached from single and bounded batch reveal. It rejects non-owners at `ownerOf` (CauldronCollection.sol:256) and the mint block/current block at `NotReady` (CauldronCollection.sol:259). First expiry spends the one `reanchored` flag (CauldronCollection.sol:302), rewrites the anchor, and returns. Second expiry commits base rarity and marks revealed at `revealed` (CauldronCollection.sol:310), capping withholding at two draws. A live seed commits the hash-derived rarity at `_rollRarity` (CauldronCollection.sol:314).
- Edges: `ERC721.ownerOf (CauldronCollection.sol:256), TRUSTED, out-of-cluster`; `CauldronCollection._rollRarity (CauldronCollection.sol:314), TRUSTED, in-cluster`
- Observations: The comment says a holder or keeper can retry, but the `ownerOf` gate (CauldronCollection.sol:256) excludes keepers.

### `_rollRarity/function` — CauldronCollection.sol:321

- Signature: `function _rollRarity(uint256 seed) private view returns (uint8)`
- Authority: internal (callers: _reveal)
- Gate evidence: `UNGATED`
- Reads: `rarityCumBps (line 324)`
- Writes: none
- Value: NONE
- Reachability: Called only from the reveal path at `_rollRarity` (CauldronCollection.sol:314). Walks four cumulative buckets at `rarityCumBps` (CauldronCollection.sol:324) and falls through to tier zero.
- Edges: none
- Observations: none

### `setVault/function` — CauldronCollection.sol:331

- Signature: `function setVault(address _vault) external`
- Authority: configurator (the factory) or registry
- Gate evidence: `if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:332)`
- Reads: `configurator (line 332, immutable)`; `deployer (line 332, immutable)`; `vault (line 333)`
- Writes: `vault (line 334)`
- Value: NONE
- Reachability: Write-once: a second call reverts on the non-zero `vault` (CauldronCollection.sol:333) test. The factory calls it inside `setVault` (CauldronFactory.sol:76); the registry can do it instead if the factory has not. It confers the burn right checked at `vault` (CauldronCollection.sol:445), so the burn authority is permanent once set.
- Edges: none
- Observations: none

### `setRoyalty/function` — CauldronCollection.sol:341

- Signature: `function setRoyalty(address receiver, uint96 bps) external`
- Authority: configurator (the factory) or registry
- Gate evidence: `if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:342)`
- Reads: `configurator (line 342, immutable)`; `deployer (line 342, immutable)`
- Writes: none
- Value: NONE
- Reachability: Re-settable by either holder, capped at 10 percent by the require at `bps` (CauldronCollection.sol:343). The factory uses it to point royalties at the RoyaltyRouter it just deployed, at `setRoyalty` (CauldronFactory.sol:88). The receiver lands in inherited ERC2981 storage through `_setDefaultRoyalty` (CauldronCollection.sol:344) and is never read back in this file.
- Edges: none
- Observations: comment at `deployer` (CauldronCollection.sol:337) says the royalty receiver is re-pointable by the deployer only; code at `configurator` (CauldronCollection.sol:342) also accepts the factory

### `setLiquidatorMinter/function` — CauldronCollection.sol:351

- Signature: `function setLiquidatorMinter(address _minter) external`
- Authority: registry or minter (the volume hook)
- Gate evidence: `if (msg.sender != deployer && msg.sender != minter) revert OnlyMinter(); (CauldronCollection.sol:352)`
- Reads: `deployer (line 352, immutable)`; `minter (line 352, immutable)`
- Writes: `liquidatorMinter (line 353)`
- Value: NONE
- Reachability: Both holders are immutable, so this right can neither rotate nor be renounced. It confers the only authority accepted at `liquidatorMinter` (CauldronCollection.sol:410), and it is freely re-settable, including to zero, which silently disables badge minting.
- Edges: none
- Observations: none

### `setMetadata/function` — CauldronCollection.sol:361

- Signature: `function setMetadata(MetadataMode _mode, address _renderer, string calldata baseURI_) external`
- Authority: registry (held in the immutable `deployer` slot)
- Gate evidence: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:362)`
- Reads: `deployer (line 362, immutable)`
- Writes: `renderer (line 365)`; `_baseTokenURI (line 367)`; `mode (line 369)`
- Value: NONE
- Reachability: Registry-only. Renderer mode requires a contract with code at `_renderer` (CauldronCollection.sol:364), but the base-URI branch accepts an empty string, and only the branch that matches the new mode is written - switching to base-URI mode with an empty argument blanks `_baseTokenURI` (CauldronCollection.sol:367) for every token.
- Edges: none
- Observations: comment at `immutable` (CauldronCollection.sol:17) says the metadata choice is immutable at deploy; code at `mode` (CauldronCollection.sol:369) lets the registry change both the mode and its source at any time

### `setLiquidatorURI/function` — CauldronCollection.sol:373

- Signature: `function setLiquidatorURI(string calldata uri) external`
- Authority: registry (held in the immutable `deployer` slot)
- Gate evidence: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:374)`
- Reads: `deployer (line 374, immutable)`
- Writes: `liquidatorURI (line 375)`
- Value: NONE
- Reachability: Registry-only metadata base for the badge branch at `liquidatorURI` (CauldronCollection.sol:468).
- Edges: none
- Observations: none

### `setUnrevealedURI/function` — CauldronCollection.sol:388

- Signature: `function setUnrevealedURI(string calldata uri) external`
- Authority: deployer (registry controller)
- Gate evidence: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:389)`
- Reads: `deployer (line 389, immutable)`
- Writes: `unrevealedURI (line 390)`
- Value: NONE
- Reachability: Controller-only metadata setter. It can replace the placeholder for every unrevealed art token through `unrevealedURI` (CauldronCollection.sol:390); there is no freeze or content-address validation.
- Edges: none
- Observations: none

### `mintLiquidator/function` — CauldronCollection.sol:396

- Signature: `function mintLiquidator(address to) external returns (uint256 tokenId)`
- Authority: liquidatorMinter (the wired PerpEngine)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:410)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Wrapper; the gate is in the callee at `liquidatorMinter` (CauldronCollection.sol:410). The empty stats struct skips the `_liqStats` write (CauldronCollection.sol:415).
- Edges: `CauldronCollection._mintLiquidator (CauldronCollection.sol:397), TRUSTED, in-cluster`
- Observations: none

### `mintLiquidatorWithStats/function` — CauldronCollection.sol:402

- Signature: `function mintLiquidatorWithStats(address to, LiqStats calldata st) external returns (uint256 tokenId)`
- Authority: liquidatorMinter (the wired PerpEngine)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:410)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Same gate, in the callee at `liquidatorMinter` (CauldronCollection.sol:410); the caller's stats are stored verbatim at `_liqStats` (CauldronCollection.sol:415) with no validation.
- Edges: `CauldronCollection._mintLiquidator (CauldronCollection.sol:406), TRUSTED, in-cluster`
- Observations: none

### `_mintLiquidator/function` — CauldronCollection.sol:409

- Signature: `function _mintLiquidator(address to, LiqStats memory st) internal returns (uint256 tokenId)`
- Authority: internal (callers: mintLiquidator, mintLiquidatorWithStats)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:410)`
- Reads: `liquidatorMinter (line 410)`; `LIQUIDATOR_ID_BASE (line 411, constant)`; `liquidatorMinted (line 411)`
- Writes: `liquidatorMinted (line 411)`; `isLiquidatoor (line 412)`; `_liqStats (line 415)`
- Value: NONE
- Reachability: Badge ids are `LIQUIDATOR_ID_BASE` plus a counter (CauldronCollection.sol:411) and are uncapped: nothing here compares against `maxSupply` (CauldronCollection.sol:209), and the counter is separate from `totalMinted` (CauldronCollection.sol:210). Collision with art ids is impossible because the constructor refuses a cap at or above `LIQUIDATOR_ID_BASE` (CauldronCollection.sol:148). The token is created at `_mint` (CauldronCollection.sol:416).
- Edges: none
- Observations: none

### `liqStats/function` — CauldronCollection.sol:421

- Signature: `function liqStats(uint256 tokenId) external view returns (LiqStats memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_liqStats (line 422)`
- Writes: none
- Value: NONE
- Reachability: View of whatever the badge minter recorded at `_liqStats` (CauldronCollection.sol:415); a badge minted through the bare wrapper at `mintLiquidator` (CauldronCollection.sol:396) reads back as an all-zero struct.
- Edges: none
- Observations: none

### `setLiquidatorRenderer/function` — CauldronCollection.sol:433

- Signature: `function setLiquidatorRenderer(address r) external`
- Authority: configurator (the factory) or registry
- Gate evidence: `if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:434)`
- Reads: `configurator (line 434, immutable)`; `deployer (line 434, immutable)`
- Writes: `liquidatorRenderer (line 435)`
- Value: NONE
- Reachability: Called by the factory during deployment at `setLiquidatorRenderer` (CauldronFactory.sol:93) and thereafter by the registry. Points the badge branch of `tokenURI` (CauldronCollection.sol:466) at an arbitrary contract.
- Edges: none
- Observations: none

### `liquidatoorTrait/function` — CauldronCollection.sol:439

- Signature: `function liquidatoorTrait(uint256 tokenId) external view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `isLiquidatoor (line 440)`
- Writes: none
- Value: NONE
- Reachability: View over the flag written at `isLiquidatoor` (CauldronCollection.sol:412).
- Edges: none
- Observations: none

### `burnFromVault/function` — CauldronCollection.sol:444

- Signature: `function burnFromVault(uint256 tokenId) external`
- Authority: vault
- Gate evidence: `if (msg.sender != vault) revert OnlyVault(); (CauldronCollection.sol:445)`
- Reads: `vault (line 445)`
- Writes: none
- Value: NONE
- Reachability: Only the address wired once at `vault` (CauldronCollection.sol:334). The burn at `_burn` (CauldronCollection.sol:446) does not decrement `totalMinted` (CauldronCollection.sol:210), so the id counter is monotonic, a burned id is never re-issued, and the live ERC721 supply falls below the counter by exactly the number of burns. DERIVED: the counter is written on one line only.
- Edges: none
- Observations: none

### `custodyTransfer/function` — CauldronCollection.sol:454

- Signature: `function custodyTransfer(address from, address to, uint256 tokenId) external`
- Authority: registry (held in the immutable `deployer` slot)
- Gate evidence: `if (msg.sender != deployer) revert OnlyVault(); (CauldronCollection.sol:455)`
- Reads: `deployer (line 455, immutable)`
- Writes: none
- Value: NONE
- Reachability: Registry-only move with no owner approval: `_transfer` (CauldronCollection.sol:456) only requires that `from` is the current owner, and the ownership check the comment relies on is entirely on the registry side. It routes through the `_update` override (CauldronCollection.sol:169), so a set validator can block it. Nothing is burned, so the collection size is unchanged.
- Edges: none
- Observations: none

### `tokenURI/function` — CauldronCollection.sol:460

- Signature: `function tokenURI(uint256 tokenId) public view override returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `isLiquidatoor (line 463)`; `liquidatorRenderer (line 465)`; `liquidatorURI (line 468)`; `revealed (line 471)`; `unrevealedURI (line 471)`; `mode (line 472)`; `renderer (line 473)`; `_baseTokenURI (line 477)`; `rarityOf (line 478)`
- Writes: none
- Value: NONE
- Reachability: View that calls out to two registry-settable contracts. Reverts for an unminted id at `_requireOwned` (CauldronCollection.sol:461). The art branch at `renderer` (CauldronCollection.sol:473) has no zero-address guard, so Renderer mode with a cleared renderer reverts for every art token, while the badge branch at `liquidatorRenderer` (CauldronCollection.sol:465) does check. Base-URI output interpolates the tier at `rarityOf` (CauldronCollection.sol:478) through `toString` (CauldronCollection.sol:480).
- Edges: `ICollectionRenderer.tokenURI (CauldronCollection.sol:466), UNTRUSTED, out-of-cluster`; `ICollectionRenderer.tokenURI (CauldronCollection.sol:473), UNTRUSTED, out-of-cluster`
- Observations: none

### `setRarityOdds/function` — CauldronCollection.sol:486

- Signature: `function setRarityOdds(uint16[4] calldata cum) external`
- Authority: registry (held in the immutable `deployer` slot)
- Gate evidence: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:487)`
- Reads: `deployer (line 487, immutable)`; `totalMinted (line 488)`
- Writes: `rarityCumBps (line 490)`
- Value: NONE
- Reachability: Registry-only and only while `totalMinted` (CauldronCollection.sol:488) is zero, so unlike the genesis collection the odds are frozen before the first mint and cannot be changed under tokens that are already waiting to reveal. The require at `cum` (CauldronCollection.sol:489) enforces an ascending ladder ending at 10000.
- Edges: none
- Observations: none


## `CauldronFactory`

### `setLiquidatorRenderer/function` — CauldronFactory.sol:36

- Signature: `function setLiquidatorRenderer(address r) external`
- Authority: owner
- Gate evidence: `if (msg.sender != owner) revert NotOwner(); (CauldronFactory.sol:37)`
- Reads: `owner (line 37)`
- Writes: `liquidatorRenderer (line 38)`
- Value: NONE
- Reachability: Owner-only. The value is applied to every LATER collection the factory deploys at `liquidatorRenderer` (CauldronFactory.sol:92); collections already deployed keep whatever they were given, because the factory only holds the setter right during `deployBrew` (CauldronFactory.sol:63). DERIVED: the factory calls the collection setter only inside that function.
- Edges: none
- Observations: none

### `transferOwnership/function` — CauldronFactory.sol:42

- Signature: `function transferOwnership(address to) external`
- Authority: owner
- Gate evidence: `if (msg.sender != owner) revert NotOwner(); (CauldronFactory.sol:43)`
- Reads: `owner (line 43)`
- Writes: `owner (line 44)`
- Value: NONE
- Reachability: Owner-only, single-step, with no zero check: passing the zero address at `to` (CauldronFactory.sol:44) permanently dead-ends the badge-renderer setter, which is the only right this owner holds. The slot is initialised to the deploying address at `owner` (CauldronFactory.sol:21).
- Edges: none
- Observations: none

### `deployBrew/function` — CauldronFactory.sol:63

- Signature: `function deployBrew(Config calldata c) external returns (address collection, address vault)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `liquidatorRenderer (line 92)`; `liquidatorRenderer (line 93)`
- Writes: none
- Value: No funds move; the call deploys `CauldronCollection` (CauldronFactory.sol:71), `CauldronVault` (CauldronFactory.sol:75), and `RoyaltyRouter` (CauldronFactory.sol:87) from caller-supplied configuration.
- Reachability: Permissionless factory entry; only the registry wires returned addresses into protocol state. The collection controller is caller-supplied `registry` (CauldronFactory.sol:72), not msg.sender. This factory acquires and immediately spends collection configurator rights at `setVault` (CauldronFactory.sol:76), `setRoyalty` (CauldronFactory.sol:88), and optional renderer wiring. The royalty router freezes the caller-supplied hook plus `royaltyReceiver` (CauldronFactory.sol:87), making the latter the ERC20 royalty sink.
- Edges: `CauldronCollection.setVault (CauldronFactory.sol:76), TRUSTED, in-cluster`; `CauldronCollection.setRoyalty (CauldronFactory.sol:88), TRUSTED, in-cluster`; `CauldronCollection.setLiquidatorRenderer (CauldronFactory.sol:93), TRUSTED, in-cluster`
- Observations: none

### `deployVault/function` — CauldronFactory.sol:105

- Signature: `function deployVault(address collection, address registry, uint256 floorOffset) external returns (address vault)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: no native or token value moves; the call is a DEPLOYMENT - it runs the `CauldronVault` (CauldronFactory.sol:109) constructor with the collection, registry and floor offset the caller named, and funds it with nothing.
- Reachability: UNGATED and stateless: it returns a new vault bound to the collection and registry the caller names at `CauldronVault` (CauldronFactory.sol:109), so anyone can create an unwired vault for any collection - it confers nothing, because the collection only honours the vault its own `setVault` recorded. The protocol caller is the registry at `deployVault` (CauldronRegistry.sol:1267), which passes a non-zero floor offset for a continued collection.
- Edges: none
- Observations: none


## `ICauldronHookGacha (declared in CauldronGachaRouter.sol)`

### `commitCrystals/function` — CauldronGachaRouter.sol:15

- Signature: `function commitCrystals(address player, uint256 maxCount, uint256 playWei) external returns (uint256)`
- Authority: declaration only (no body); in-cluster callers are _play, openReady and playChurn, all reachable by anyone; the hook holds its own gate
- Gate evidence: `if (_locked != 1) revert Reentrancy(); (CauldronGachaRouter.sol:188)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called at `commitCrystals` (CauldronGachaRouter.sol:337), `commitCrystals` (CauldronGachaRouter.sol:371) and `commitCrystals` (CauldronGachaRouter.sol:407). The router always passes `msg.sender` as the player, so it cannot credit a third party, and the size argument is whatever the router computed - a raw notional on the swap paths and a curve-unit figure on the ready path. The implementation and its authority check are out of cluster.
- Edges: none
- Observations: none

### `resolveTickets/function` — CauldronGachaRouter.sol:16

- Signature: `function resolveTickets(uint256 maxCount) external returns (uint256, uint256)`
- Authority: declaration only (no body); in-cluster callers are _play, openReady and playChurn
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called immediately after each commit at `resolveTickets` (CauldronGachaRouter.sol:338), `resolveTickets` (CauldronGachaRouter.sol:372) and `resolveTickets` (CauldronGachaRouter.sol:408), always bounded by the constant at `MAX_MINTS_PER_CALL` (CauldronGachaRouter.sol:338). Its return value is discarded on every call site.
- Edges: none
- Observations: none

### `crystalsReady/function` — CauldronGachaRouter.sol:17

- Signature: `function crystalsReady(address player) external view returns (uint256)`
- Authority: declaration only (no body); in-cluster caller is openReady
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read once per call at `crystalsReady` (CauldronGachaRouter.sol:357) to size the batch, then clamped by the router.
- Edges: none
- Observations: none

### `costOfNextCrystals/function` — CauldronGachaRouter.sol:18

- Signature: `function costOfNextCrystals(uint256 count) external view returns (uint256)`
- Authority: declaration only (no body); in-cluster caller is openReady
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `costOfNextCrystals` (CauldronGachaRouter.sol:362); its result is treated as already being in the hook's curve unit and is divided by the buy weight to produce the play size at `playWei` (CauldronGachaRouter.sol:364).
- Edges: none
- Observations: none

### `buyWeightBps/function` — CauldronGachaRouter.sol:19

- Signature: `function buyWeightBps() external view returns (uint256)`
- Authority: declaration only (no body); in-cluster caller is openReady
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `buyWeightBps` (CauldronGachaRouter.sol:363); a zero answer makes the router pass the raw credit through unscaled at `creditToOpen` (CauldronGachaRouter.sol:364).
- Edges: none
- Observations: none


## `IRegistryCurrent (declared in CauldronGachaRouter.sol)`

### `currentToken/function` — CauldronGachaRouter.sol:23

- Signature: `function currentToken() external view returns (address)`
- Authority: declaration only (no body); in-cluster caller is _key
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read on every swap path through `currentToken` (CauldronGachaRouter.sol:229) to build currency1 of the pool key, so the router follows the live generation with no rewiring.
- Edges: none
- Observations: none

### `currentGeneration/function` — CauldronGachaRouter.sol:25

- Signature: `function currentGeneration() external view returns (uint256)`
- Authority: declaration only (no body); in-cluster caller is _quote
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `currentGeneration` (CauldronGachaRouter.sol:216) purely to index the quote lookup.
- Edges: none
- Observations: none

### `generationQuote/function` — CauldronGachaRouter.sol:29

- Signature: `function generationQuote(uint256 gen) external view returns (address)`
- Authority: declaration only (no body); in-cluster caller is _quote
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `generationQuote` (CauldronGachaRouter.sol:216). Its answer decides both the currency0 of the key at `_quote` (CauldronGachaRouter.sol:228) and, through the zero test, whether the router settles native or ERC20 at `isNative` (CauldronGachaRouter.sol:434).
- Edges: none
- Observations: none


## `IQuoteOracleView (declared in CauldronGachaRouter.sol)`

### `usdPerRawUnit/function` — CauldronGachaRouter.sol:37

- Signature: `function usdPerRawUnit(address quote) external view returns (uint256)`
- Authority: declaration only; implementation authority is outside this node
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: the router prices the generation's quote with it through a bounded call (`usdPerRawUnit` CauldronGachaRouter.sol:143); an unusable answer leaves the play size unchanged (`playWei` CauldronGachaRouter.sol:152).
- Edges: none
- Observations: none


## `CauldronGachaRouter`

### `setOracle/function` — CauldronGachaRouter.sol:99

- Signature: `function setOracle(address _oracle) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronGachaRouter.sol:99)`
- Reads: none
- Writes: `oracle (line 100)`
- Value: NONE
- Reachability: Owner-only, freely re-settable, no zero check and no code check: the address lands in `oracle` (CauldronGachaRouter.sol:100) and is then queried by a bounded STATICCALL on every swap-path play (`usdPerRawUnit` CauldronGachaRouter.sol:143); an unusable answer leaves play sizes unconverted rather than reverting. The owner slot is the OZ Ownable one, so it can also be transferred or renounced from outside this file.
- Edges: none
- Observations: none

### `playInCurveUnits/function` — CauldronGachaRouter.sol:120

- Signature: `function playInCurveUnits(uint256 playWei) external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: View wrapper so a frontend can display the same number the chain will roll at `_playInCurveUnits` (CauldronGachaRouter.sol:337).
- Edges: `CauldronGachaRouter._playInCurveUnits (CauldronGachaRouter.sol:121), TRUSTED, in-cluster`
- Observations: none

### `_playInCurveUnits/function` — CauldronGachaRouter.sol:136

- Signature: `function _playInCurveUnits(uint256 playWei) internal view returns (uint256)`
- Authority: internal (callers: playInCurveUnits, _play, playChurn)
- Gate evidence: `UNGATED`
- Reads: `oracle (line 137)`
- Writes: none
- Value: NONE
- Reachability: With `oracle` (CauldronGachaRouter.sol:137) unset the size passes through unchanged. Otherwise the generation's own quote is priced (`_quote` CauldronGachaRouter.sol:143) by a bounded one-word STATICCALL (`valid` CauldronGachaRouter.sol:148). A failed or short reply, a zero factor or a product that would overflow all leave the size unchanged (`playWei` CauldronGachaRouter.sol:152), so a broken oracle cannot revert play; otherwise the size is scaled by the factor over 1e18, rounding down.
- Edges: `IQuoteOracleView.usdPerRawUnit (CauldronGachaRouter.sol:143), UNTRUSTED, out-of-cluster`; `CauldronGachaRouter._quote (CauldronGachaRouter.sol:143), TRUSTED, in-cluster`
- Observations: none

### `nonReentrant/modifier` — CauldronGachaRouter.sol:188

- Signature: `modifier nonReentrant()`
- Authority: internal (callers: play, playLiq, openReady, playChurn)
- Gate evidence: `if (_locked != 1) revert Reentrancy(); (CauldronGachaRouter.sol:189)`
- Reads: `_locked (line 189)`
- Writes: `_locked (line 190)`; `_locked (line 192)`
- Value: NONE
- Reachability: Wraps all four external entry points. It is NOT applied to `unlockCallback` (CauldronGachaRouter.sol:418), which is reached re-entrantly from the pool manager while the flag is already set, so the guard admits that one nested frame by design.
- Edges: none
- Observations: none

### `constructor/constructor` — CauldronGachaRouter.sol:195

- Signature: `constructor(IPoolManager _poolManager, address _hook, address _registry, address _owner) Ownable(_owner)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `poolManager (line 198, immutable)`; `hook (line 199, immutable)`; `hookAddr (line 200, immutable)`; `registry (line 201, immutable)`
- Value: NONE
- Reachability: Deployment only, with no zero checks on any of the four wired addresses. All four are immutable, so the pool manager, hook and registry cannot be re-pointed; only `oracle` (CauldronGachaRouter.sol:100) and the OZ owner are mutable afterwards. The owner comes from the constructor argument at `Ownable` (CauldronGachaRouter.sol:196).
- Edges: none
- Observations: none

### `_quote/function` — CauldronGachaRouter.sol:215

- Signature: `function _quote() internal view returns (address)`
- Authority: internal (callers: _key, _playInCurveUnits, playChurn)
- Gate evidence: `UNGATED`
- Reads: `registry (line 216, immutable)`
- Writes: none
- Value: NONE
- Reachability: Two chained registry views on every call. The answer is re-read per call rather than cached, so a rotation that rewrites the generation's quote changes which asset `_pullQuote` (CauldronGachaRouter.sol:282) demands from the very next caller, and a play that is in flight in the same block can be pointed at a different pool than the sender expected. DERIVED: nothing in this file stores the quote.
- Edges: `IRegistryCurrent.generationQuote (CauldronGachaRouter.sol:216), TRUSTED, in-cluster`; `IRegistryCurrent.currentGeneration (CauldronGachaRouter.sol:216), TRUSTED, in-cluster`
- Observations: none

### `_key/function` — CauldronGachaRouter.sol:226

- Signature: `function _key() internal view returns (PoolKey memory)`
- Authority: internal (callers: _play, unlockCallback, _churn)
- Gate evidence: `UNGATED`
- Reads: `POOL_FEE (line 230, constant)`; `TICK_SPACING (line 231, constant)`; `hookAddr (line 232, immutable)`; `registry (line 229, immutable)`
- Writes: none
- Value: NONE
- Reachability: Rebuilds the pool key from live registry state on every entry. The quote is placed in currency0 at `_quote` (CauldronGachaRouter.sol:228) and the iteration token in currency1 at `currentToken` (CauldronGachaRouter.sol:229) with no comparison between the two addresses, so the ordering rests entirely on the registry's own admission rule.
- Edges: `CauldronGachaRouter._quote (CauldronGachaRouter.sol:228), TRUSTED, in-cluster`; `IRegistryCurrent.currentToken (CauldronGachaRouter.sol:229), TRUSTED, in-cluster`
- Observations: comment at `currency0` (CauldronGachaRouter.sol:221) states as an invariant that the quote always sorts into currency0; code at `Currency` (CauldronGachaRouter.sol:228) assigns the two currencies by role and never compares the addresses, so the property is enforced elsewhere, not here

### `play/function` — CauldronGachaRouter.sol:244

- Signature: `function play(uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax) external payable nonReentrant returns (uint256 opened)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native when the generation's quote is native - declared `payable` (line 246)
- Reachability: Permissionless entry point guarded by `nonReentrant` (CauldronGachaRouter.sol:247). Passes an empty hint array, so no perp liquidation is attempted at `_play` (CauldronGachaRouter.sol:250).
- Edges: `CauldronGachaRouter._play (CauldronGachaRouter.sol:250), TRUSTED, in-cluster`
- Observations: none

### `playLiq/function` — CauldronGachaRouter.sol:259

- Signature: `function playLiq( uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax, uint256[] calldata liqHints ) external payable nonReentrant returns (uint256 opened)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native when the generation's quote is native - declared `payable` (line 268)
- Reachability: Same permissionless path as the plain play, guarded by `nonReentrant` (CauldronGachaRouter.sol:269); the caller-supplied hint list is forwarded untouched into the swap's hookData at `liqHints` (CauldronGachaRouter.sol:428). The array is unbounded here - only the hook limits how many hints it will process. DERIVED: no length check exists in this file.
- Edges: `CauldronGachaRouter._play (CauldronGachaRouter.sol:272), TRUSTED, in-cluster`
- Observations: none

### `_pullQuote/function` — CauldronGachaRouter.sol:282

- Signature: `function _pullQuote(address q, uint256 quoteIn) private returns (uint256)`
- Authority: internal (callers: _play, playChurn)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native `msg.value` on the native branch (line 285); ERC20 pull of `q` from the caller into this router (line 288)
- Reachability: Enforces exactly one funding form: value with no `quoteIn` (CauldronGachaRouter.sol:284) when the quote is native, or an allowance pull with no value at `msg.value` (CauldronGachaRouter.sol:287) otherwise. It returns the REQUESTED amount at `quoteIn` (CauldronGachaRouter.sol:289) rather than a measured balance delta, so a fee-on-transfer quote would credit the player more than actually arrived. DERIVED: no balance is read before or after the pull.
- Edges: `CauldronGachaRouter._safeTransferFrom (CauldronGachaRouter.sol:288), TRUSTED, in-cluster`
- Observations: none

### `_play/function` — CauldronGachaRouter.sol:292

- Signature: `function _play( uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax, uint256[] memory liqHints ) internal returns (uint256 opened)`
- Authority: internal (callers: play, playLiq)
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 312, immutable)`; `hook (line 337, immutable)`; `MAX_MINTS_PER_CALL (line 338, constant)`
- Writes: none
- Value: ERC20 pull of the iteration token from the caller at `_safeTransferFrom` (line 309); ERC20 refund of the unused token to `msg.sender` (line 342); quote paid back to `msg.sender` (line 349)
- Reachability: Body of both public play paths. It pulls the two inputs, then enters the pool manager through `unlock` (CauldronGachaRouter.sol:312), which calls back into `unlockCallback` (CauldronGachaRouter.sol:418) where the swaps run. Slippage on the sell leg is checked only when something was sold, at `sellEthGross` (CauldronGachaRouter.sol:329); the buy leg's minimum is enforced inside the callback instead. The gacha commit and resolve happen before any payout, so the two token sends at `_safeTransfer` (CauldronGachaRouter.sol:342) and `_payQuote` (CauldronGachaRouter.sol:349) are the last actions and the hook cannot be re-entered through a hostile recipient while state is half-written. The play size reported to the hook is the ETH-equivalent notional `playWei` (CauldronGachaRouter.sol:333), converted for the curve, while the event reports the raw notional.
- Edges: `CauldronGachaRouter._key (CauldronGachaRouter.sol:303), TRUSTED, in-cluster`; `CauldronGachaRouter._pullQuote (CauldronGachaRouter.sol:305), TRUSTED, in-cluster`; `CauldronGachaRouter._safeTransferFrom (CauldronGachaRouter.sol:309), TRUSTED, in-cluster`; `IPoolManager.unlock (CauldronGachaRouter.sol:312), TRUSTED, out-of-cluster`; `ICauldronHookGacha.commitCrystals (CauldronGachaRouter.sol:337), UNTRUSTED, in-cluster`; `CauldronGachaRouter._playInCurveUnits (CauldronGachaRouter.sol:337), TRUSTED, in-cluster`; `ICauldronHookGacha.resolveTickets (CauldronGachaRouter.sol:338), UNTRUSTED, in-cluster`; `CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:342), TRUSTED, in-cluster`; `CauldronGachaRouter._payQuote (CauldronGachaRouter.sol:349), TRUSTED, in-cluster`
- Observations: none

### `openReady/function` — CauldronGachaRouter.sol:356

- Signature: `function openReady(uint256 maxCount) external nonReentrant returns (uint256 opened)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `hook (line 357, immutable)`; `MAX_MINTS_PER_CALL (line 358, constant)`
- Writes: none
- Value: NONE
- Reachability: Permissionless and payment-free: it opens crystals the caller already earned, clamped to the constant at `MAX_MINTS_PER_CALL` (CauldronGachaRouter.sol:358) and to the caller's own `maxCount` (CauldronGachaRouter.sol:359), and returns early when nothing is ready at `ready` (CauldronGachaRouter.sol:360). No value moves in this function at all; the size handed to the hook is derived from the hook's own curve at `creditToOpen` (CauldronGachaRouter.sol:364) and is deliberately not passed through the oracle conversion.
- Edges: `ICauldronHookGacha.crystalsReady (CauldronGachaRouter.sol:357), UNTRUSTED, in-cluster`; `ICauldronHookGacha.costOfNextCrystals (CauldronGachaRouter.sol:362), UNTRUSTED, in-cluster`; `ICauldronHookGacha.buyWeightBps (CauldronGachaRouter.sol:363), UNTRUSTED, in-cluster`; `ICauldronHookGacha.commitCrystals (CauldronGachaRouter.sol:371), UNTRUSTED, in-cluster`; `ICauldronHookGacha.resolveTickets (CauldronGachaRouter.sol:372), UNTRUSTED, in-cluster`
- Observations: none

### `playChurn/function` — CauldronGachaRouter.sol:388

- Signature: `function playChurn(uint256 quoteIn, uint256 loops, uint256 minTokenOut, uint256 openMax) external payable nonReentrant returns (uint256 opened)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MAX_LOOPS (line 397, constant)`; `poolManager (line 399, immutable)`; `hook (line 407, immutable)`; `MAX_MINTS_PER_CALL (line 408, constant)`
- Writes: none
- Value: receives native when native quote is selected; refunds residual quote through `_payQuote` (line 410)
- Reachability: Permissionless and nonReentrant. It pulls quote before enforcing the 1-to-10 loop bound, but any revert unwinds the pull. The pool-manager unlock carries player, spend, loop count, and `minTokenOut` at `unlock` (CauldronGachaRouter.sol:399). After callback settlement it converts aggregate notional for odds, commits/resolves, refunds residual quote, and emits. A zero `minTokenOut` deliberately disables final token slippage protection.
- Edges: `CauldronGachaRouter._quote (CauldronGachaRouter.sol:394), TRUSTED, in-cluster`; `CauldronGachaRouter._pullQuote (CauldronGachaRouter.sol:395), TRUSTED, in-cluster`; `IPoolManager.unlock (CauldronGachaRouter.sol:399), TRUSTED, out-of-cluster`; `ICauldronHookGacha.commitCrystals (CauldronGachaRouter.sol:407), UNTRUSTED, in-cluster`; `CauldronGachaRouter._playInCurveUnits (CauldronGachaRouter.sol:407), TRUSTED, in-cluster`; `ICauldronHookGacha.resolveTickets (CauldronGachaRouter.sol:408), UNTRUSTED, in-cluster`; `CauldronGachaRouter._payQuote (CauldronGachaRouter.sol:410), TRUSTED, in-cluster`
- Observations: none

### `unlockCallback/function` — CauldronGachaRouter.sol:418

- Signature: `function unlockCallback(bytes calldata raw) external returns (bytes memory)`
- Authority: poolManager (re-entered during unlock)
- Gate evidence: `if (msg.sender != address(poolManager)) revert NotPoolManager(); (CauldronGachaRouter.sol:419)`
- Reads: `poolManager (line 419, immutable)`; `poolManager (line 442, immutable)`; `poolManager (line 456, immutable)`
- Writes: none
- Value: the pool manager pays the swap output to the player at `_take` (line 451); the sell output is taken to this router at `_take` (line 464)
- Reachability: Only the pool manager can enter, and only while one of the four entry points holds the lock; the caller check at `poolManager` (CauldronGachaRouter.sol:419) is the whole gate, and the payload is trusted because the manager echoes back exactly what the router encoded. The key is rebuilt here at `_key` (CauldronGachaRouter.sol:424) rather than passed in, so a mid-transaction registry change would swap the pool between the outer call and this frame. Buy-leg slippage is enforced at `outAmount` (CauldronGachaRouter.sol:448); the sell leg has no minimum here and is checked by the caller instead. The swap's hookData carries the player and the hint list at `hookData` (CauldronGachaRouter.sol:428), so volume is credited to the player rather than to the router. Price limits come from the extreme constants at `_limit` (CauldronGachaRouter.sol:444), i.e. the pool bounds, not a price the caller chose.
- Edges: `CauldronGachaRouter._churn (CauldronGachaRouter.sol:421), TRUSTED, in-cluster`; `CauldronGachaRouter._key (CauldronGachaRouter.sol:424), TRUSTED, in-cluster`; `IPoolManager.swap (CauldronGachaRouter.sol:442), TRUSTED, out-of-cluster`; `CauldronGachaRouter._limit (CauldronGachaRouter.sol:444), TRUSTED, in-cluster`; `CauldronGachaRouter._settle (CauldronGachaRouter.sol:450), TRUSTED, in-cluster`; `CauldronGachaRouter._take (CauldronGachaRouter.sol:451), TRUSTED, in-cluster`; `IPoolManager.swap (CauldronGachaRouter.sol:456), TRUSTED, out-of-cluster`; `CauldronGachaRouter._settle (CauldronGachaRouter.sol:463), TRUSTED, in-cluster`; `CauldronGachaRouter._take (CauldronGachaRouter.sol:464), TRUSTED, in-cluster`
- Observations: none

### `_churn/function` — CauldronGachaRouter.sol:471

- Signature: `function _churn(ChurnData memory c) private returns (bytes memory)`
- Authority: private (single caller: unlockCallback tag 1)
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 487, immutable)`; `poolManager (line 513, immutable)`
- Writes: none
- Value: Each buy settles quote and takes token at `_settle` (line 494) and `_take` (line 495); each sell reverses those flows at `_settle` (line 520) and `_take` (line 521); final token is transferred to `player` (line 538)
- Reachability: Runs only during a pool-manager unlock dispatched by tag 1. The loop bound was checked by `playChurn`. Both exact-input legs debit actual consumed amounts at `ethBal` (CauldronGachaRouter.sol:510) and `tokBal` (CauldronGachaRouter.sol:528), preserving partial-fill remainders. The last iteration ends after a buy; final retained token is checked against `minTokenOut` (CauldronGachaRouter.sol:537) before transfer, and residual quote is returned to the caller as encoded `ethBal` (CauldronGachaRouter.sol:539).
- Edges: `CauldronGachaRouter._key (CauldronGachaRouter.sol:472), TRUSTED, in-cluster`; `IPoolManager.swap (CauldronGachaRouter.sol:487), TRUSTED, out-of-cluster`; `CauldronGachaRouter._limit (CauldronGachaRouter.sol:489), TRUSTED, in-cluster`; `CauldronGachaRouter._settle (CauldronGachaRouter.sol:494), TRUSTED, in-cluster`; `CauldronGachaRouter._take (CauldronGachaRouter.sol:495), TRUSTED, in-cluster`; `IPoolManager.swap (CauldronGachaRouter.sol:513), TRUSTED, out-of-cluster`; `CauldronGachaRouter._settle (CauldronGachaRouter.sol:520), TRUSTED, in-cluster`; `CauldronGachaRouter._take (CauldronGachaRouter.sol:521), TRUSTED, in-cluster`; `CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:538), TRUSTED, in-cluster`
- Observations: none

### `_limit/function` — CauldronGachaRouter.sol:542

- Signature: `function _limit(bool zeroForOne) private pure returns (uint160)`
- Authority: internal (callers: unlockCallback, _churn)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure constants returned at `zeroForOne` (CauldronGachaRouter.sol:543): the minimum and maximum usable square-root prices, i.e. no price limit at all. Every swap in the file uses them, so the callers rely on explicit minimum-output checks instead.
- Edges: none
- Observations: none

### `_settle/function` — CauldronGachaRouter.sol:546

- Signature: `function _settle(Currency currency, uint256 amount, bool isNative) private`
- Authority: internal (callers: unlockCallback, _churn)
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 548, immutable)`; `poolManager (line 550, immutable)`; `poolManager (line 551, immutable)`; `poolManager (line 552, immutable)`
- Writes: none
- Value: sends native to the pool manager at `settle` (line 548); on the ERC20 branch the manager's balance is synced at `sync` (line 550), the token is pushed to it at `_safeTransfer` (line 551) and the debt is closed at `settle` (line 552)
- Reachability: Two settlement shapes selected by the `isNative` flag the caller computed (CauldronGachaRouter.sol:547): value-bearing settle for native, or sync then transfer then settle for an ERC20 quote. The native branch spends this contract's balance, which includes anything the open `receive` (CauldronGachaRouter.sol:618) has accumulated, not only the current caller's value. DERIVED: the function takes an amount, not a per-caller accounting entry.
- Edges: `IPoolManager.settle (CauldronGachaRouter.sol:548), TRUSTED, out-of-cluster`; `IPoolManager.sync (CauldronGachaRouter.sol:550), TRUSTED, out-of-cluster`; `CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:551), TRUSTED, in-cluster`; `IPoolManager.settle (CauldronGachaRouter.sol:552), TRUSTED, out-of-cluster`
- Observations: none

### `_take/function` — CauldronGachaRouter.sol:556

- Signature: `function _take(Currency currency, address to, uint256 amount) private`
- Authority: internal (callers: unlockCallback, _churn)
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 557, immutable)`
- Writes: none
- Value: the pool manager pays `to` at `take` (line 557)
- Reachability: Zero-amount no-op at `amount` (CauldronGachaRouter.sol:557). The destination is either the player directly or this router, chosen by each call site.
- Edges: `IPoolManager.take (CauldronGachaRouter.sol:557), TRUSTED, out-of-cluster`
- Observations: none

### `_payQuote/function` — CauldronGachaRouter.sol:566

- Signature: `function _payQuote(address q, address to, uint256 amount) private`
- Authority: internal (callers: _play, playChurn)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: sends native to `to` (line 569); ERC20 sent to `to` at `_safeTransfer` (line 572)
- Reachability: Pays the player back in whatever the generation's quote is. The native branch forwards all remaining gas to an arbitrary recipient at `call` (CauldronGachaRouter.sol:569); it is only ever reached after the gacha state has already been committed, and every caller is wrapped by the guard at `_locked` (CauldronGachaRouter.sol:189). A rejecting recipient reverts the whole play at `RefundFailed` (CauldronGachaRouter.sol:570) rather than losing the refund.
- Edges: `CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:572), TRUSTED, in-cluster`
- Observations: none

### `_safeTransfer/function` — CauldronGachaRouter.sol:576

- Signature: `function _safeTransfer(address token, address to, uint256 amount) private`
- Authority: internal (callers: _play, _churn, _settle, _payQuote)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: ERC20 transfer of `token` to `to` (line 578)
- Reachability: Raw call with a decoded-boolean check at `data` (CauldronGachaRouter.sol:579), so both standard and non-standard ERC20s are handled. The token address always comes from the pool key or the generation quote, never directly from a caller argument. DERIVED: every call site passes a currency unwrapped from the key or the quote.
- Edges: none
- Observations: none

### `_safeTransferFrom/function` — CauldronGachaRouter.sol:582

- Signature: `function _safeTransferFrom(address token, address from, address to, uint256 amount) private`
- Authority: internal (callers: _pullQuote, _play)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: ERC20 transferFrom of `token` from `from` to `to` (line 584)
- Reachability: Pulls the caller's quote or token using the router's allowance; the same decoded-boolean check at `data` (CauldronGachaRouter.sol:585) applies. Both call sites pass `msg.sender` as the source, so the allowance cannot be spent on behalf of a third party. DERIVED: the two call sites are the pull at `_safeTransferFrom` (CauldronGachaRouter.sol:288) and the one at `_safeTransferFrom` (CauldronGachaRouter.sol:309).
- Edges: none
- Observations: none

### `rescueETH/function` — CauldronGachaRouter.sol:588

- Signature: `function rescueETH(address to, uint256 amount) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronGachaRouter.sol:588)`
- Reads: none
- Writes: none
- Value: sends native to `to` (line 589)
- Reachability: Owner-only sweep of the contract's native balance to any address, with no accounting and no cap: it can move value that arrived through the open `receive` (CauldronGachaRouter.sol:618) or any native dust left by a settlement. It has no reentrancy guard, but it holds no per-user accounting to corrupt. DERIVED: the router stores no per-player balances.
- Edges: none
- Observations: none

### `rescueToken/function` — CauldronGachaRouter.sol:601

- Signature: `function rescueToken(address token, address to, uint256 amount) external onlyOwner`
- Authority: owner
- Gate evidence: `external onlyOwner (CauldronGachaRouter.sol:601)`
- Reads: none
- Writes: none
- Value: sends `amount` of an arbitrary ERC20 to `to` (line 602)
- Reachability: Owner-gated ERC20 counterpart to `rescueETH` (CauldronGachaRouter.sol:588), added because recovery was one-sided: a native generation's stranded quote could be swept while an ERC20 generation's could not be moved at all. It routes through the checked `_safeTransfer` (CauldronGachaRouter.sol:602), so a token that returns false reverts rather than reporting a successful rescue. The router holds no balance between transactions by design - every leg sweeps to the player before the call returns, e.g. at `_safeTransfer` (CauldronGachaRouter.sol:538) - so what this can reach is dust and value stranded by a bug (DERIVED). There is no allowlist on `token`, and no accounting separating a player's in-flight funds from dust, so the owner may move any ERC20 balance the router holds at that instant (DERIVED).
- Edges: `CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:602), TRUSTED, in-cluster`
- Observations: none

### `renounceOwnership/function` — CauldronGachaRouter.sol:614

- Signature: `function renounceOwnership() public pure override`
- Authority: anyone by ABI - it always reverts
- Gate evidence: `function renounceOwnership() public pure override { (CauldronGachaRouter.sol:614)`
- Reads: none
- Writes: none
- Value: none - it reverts (DERIVED)
- Reachability: Disables OpenZeppelin's live renounce by reverting `OwnershipCannotBeRenounced` (CauldronGachaRouter.sol:615); `pure` and ungated, so any caller reaches it and it always reverts (DERIVED). The owner surface it protects is entirely recovery and repair: `rescueETH` (CauldronGachaRouter.sol:588), `rescueToken` (CauldronGachaRouter.sol:601) and the oracle re-point at `oracle` (CauldronGachaRouter.sol:94), so renouncing would permanently seal the only exits for stranded value (DERIVED).
- Edges: none
- Observations: none

### `receive/receive` — CauldronGachaRouter.sol:618

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native - declared `payable` (line 618)
- Reachability: Open and empty, so any address can push ETH in. Such a balance is indistinguishable from a player's value once inside, and it is spendable by the native settle branch at `settle` (CauldronGachaRouter.sol:548) and by the owner at `rescueETH` (CauldronGachaRouter.sol:588).
- Edges: none
- Observations: none


## `CollectionLedger`

### `constructor/constructor` — CollectionLedger.sol:78

- Signature: `constructor(address _registry)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `registry (line 80, immutable)`
- Value: NONE
- Reachability: Deployment only. `registry` (CollectionLedger.sol:80) is immutable and non-zero, so the single authority over this cap table is fixed at deploy and can never be rotated, renounced or dead-ended.
- Edges: none
- Observations: none

### `onlyRegistry/modifier` — CollectionLedger.sol:83

- Signature: `modifier onlyRegistry()`
- Authority: internal (callers: credit, redeem, buyback, crystallize)
- Gate evidence: `if (msg.sender != registry) revert OnlyRegistry(); (CollectionLedger.sol:84)`
- Reads: `registry (line 84, immutable)`
- Writes: none
- Value: NONE
- Reachability: The only gate in the file, applied to `credit` (CollectionLedger.sol:148), `redeem` (CollectionLedger.sol:163), `buyback` (CollectionLedger.sol:176) and `crystallize` (CollectionLedger.sol:189). Every number in this contract is therefore whatever the registry asserts; the ledger holds no tokens and verifies nothing against a balance.
- Edges: none
- Observations: none

### `outstanding/function` — CollectionLedger.sol:92

- Signature: `function outstanding(uint256 gen, uint256 mintedNow) public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `crystallized (line 93)`; `frozenSupply (line 93)`; `retired (line 94)`
- Writes: none
- Value: NONE
- Reachability: Pure view. Before death the supply term is the caller-supplied `mintedNow` argument (CollectionLedger.sol:93) rather than anything this contract can verify; after `crystallized` (CollectionLedger.sol:93) is set it switches to the snapshot in `frozenSupply` (CollectionLedger.sol:93). Saturates at zero at `supply` (CollectionLedger.sol:95) so retired can exceed supply without reverting.
- Edges: none
- Observations: none

### `floorPerNFT/function` — CollectionLedger.sol:100

- Signature: `function floorPerNFT(uint256 gen, uint256 mintedNow) public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `entitledTokens (line 103)`
- Writes: none
- Value: NONE
- Reachability: Pure view; integer division at `entitledTokens` (CollectionLedger.sol:103) rounds the per-NFT floor DOWN, and returns zero when `n` (CollectionLedger.sol:102) is zero instead of dividing by zero.
- Edges: `CollectionLedger.outstanding (CollectionLedger.sol:101), TRUSTED, in-cluster`
- Observations: none

### `isDeadEnd/function` — CollectionLedger.sol:122

- Signature: `function isDeadEnd(uint256 gen) public view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `crystallized (line 123)`; `frozenSupply (line 123)`; `retired (line 123)`
- Writes: none
- Value: NONE
- Reachability: Public view. It reports a permanent no-claimant state only after crystallization, when frozen supply is no greater than retired count at `frozenSupply` (CollectionLedger.sol:123). Alive zero-outstanding states are excluded because later mints can reopen them.
- Edges: none
- Observations: none

### `credit/function` — CollectionLedger.sol:148

- Signature: `function credit(uint256 gen, uint256 tokens) external onlyRegistry`
- Authority: registry
- Gate evidence: `external onlyRegistry (CollectionLedger.sol:148)`
- Reads: `entitledTokens (line 154)`
- Writes: `entitledTokens (line 154)`; `totalEntitled (line 155)`
- Value: NONE
- Reachability: Registry-only. Zero credit reverts. A permanently retired generation is detected at `isDeadEnd` (CollectionLedger.sol:150), emits rejection, and returns without increasing liabilities; the already-held token remains reserve surplus. Otherwise generation and global counters increase equally at `totalEntitled` (CollectionLedger.sol:155).
- Edges: `CollectionLedger.isDeadEnd (CollectionLedger.sol:150), TRUSTED, in-cluster`
- Observations: none

### `redeem/function` — CollectionLedger.sol:163

- Signature: `function redeem(uint256 gen, uint256 mintedNow) external onlyRegistry returns (uint256 payout)`
- Authority: registry
- Gate evidence: `external onlyRegistry (CollectionLedger.sol:163)`
- Reads: `entitledTokens (line 166)`; `retired (line 168)`
- Writes: `entitledTokens (line 167)`; `retired (line 168)`; `totalEntitled (line 169)`
- Value: NONE
- Reachability: Registry-only. Pays one NFT's share, computed by the same rounding-down division as the view at `payout` (CollectionLedger.sol:166), then debits both counters by exactly that amount at `entitledTokens` (CollectionLedger.sol:167) and `totalEntitled` (CollectionLedger.sol:169) and increments `retired` (CollectionLedger.sol:168). The rounding remainder stays in the pot, so the per-NFT floor of the survivors can only rise. Reverts when nothing is outstanding at `n` (CollectionLedger.sol:165). The caller-supplied `mintedNow` sizes the divisor, so a registry that passes a larger count pays less per NFT and one that passes a smaller count pays more. DERIVED: `mintedNow` is never validated in this file.
- Edges: `CollectionLedger.outstanding (CollectionLedger.sol:164), TRUSTED, in-cluster`; `CollectionLedger.floorPerNFT (CollectionLedger.sol:170), TRUSTED, in-cluster`
- Observations: none

### `buyback/function` — CollectionLedger.sol:176

- Signature: `function buyback(uint256 gen, uint256 mintedNow, uint256 paid) external onlyRegistry`
- Authority: registry
- Gate evidence: `external onlyRegistry (CollectionLedger.sol:176)`
- Reads: `retired (line 178)`
- Writes: `entitledTokens (line 179)`; `retired (line 180)`; `totalEntitled (line 181)`
- Value: NONE
- Reachability: Registry-only, and refused unless something is retired at `retired` (CollectionLedger.sol:178), so the un-retire at `retired` (CollectionLedger.sol:180) cannot underflow. Credits the full `paid` amount (CollectionLedger.sol:179) while returning one NFT to the outstanding set, which raises the floor whenever paid exceeds the current per-NFT share; the ledger itself never checks the two-times-floor rule the comment attributes to the registry.
- Edges: `CollectionLedger.floorPerNFT (CollectionLedger.sol:182), TRUSTED, in-cluster`
- Observations: none

### `crystallize/function` — CollectionLedger.sol:189

- Signature: `function crystallize(uint256 gen, uint256 mintedAtDeath, uint256 extraEntitled) external onlyRegistry`
- Authority: registry
- Gate evidence: `onlyRegistry (CollectionLedger.sol:191)`
- Reads: `crystallized (line 193)`; `retired (line 199)`; `entitledTokens (line 200)`; `retired (line 212)`; `entitledTokens (line 220)`
- Writes: `crystallized (line 194)`; `frozenSupply (line 195)`; `entitledTokens (line 202)`; `totalEntitled (line 203)`; `entitledTokens (line 217)`; `totalEntitled (line 218)`
- Value: NONE
- Reachability: Registry-only and one-time (`crystallized` CollectionLedger.sol:193). It freezes the death supply. When every frozen NFT is already retired (`retired` CollectionLedger.sol:199) no one can ever claim the generation's entitlement, so it is released from the global liability (`totalEntitled` CollectionLedger.sol:203) and new credit is rejected (`CreditRejected` CollectionLedger.sol:213) without reverting the relaunch. Otherwise accepted entitlement raises generation and global totals equally.
- Edges: none
- Observations: none


## `GachaLib`

### `_reanchored/function` — GachaLib.sol:80

- Signature: `function _reanchored(uint256 bi) private view returns (bool v)`
- Authority: internal (caller: GachaLib.resolveTickets)
- Gate evidence: `UNGATED`
- Reads: `REANCHORED_SLOT (line 81, constant)`
- Writes: none
- Value: NONE
- Reachability: Private helper deriving a batch-specific slot from `REANCHORED_SLOT` (GachaLib.sol:81) and reading it with `sload` (GachaLib.sol:82) in the delegating hook's storage namespace.
- Edges: none
- Observations: none

### `_markReanchored/function` — GachaLib.sol:85

- Signature: `function _markReanchored(uint256 bi) private`
- Authority: internal (caller: GachaLib.resolveTickets)
- Gate evidence: `UNGATED`
- Reads: `REANCHORED_SLOT (line 86, constant)`
- Writes: none
- Value: NONE
- Reachability: Private helper deriving the same namespaced slot and permanently marking it with `sstore` (GachaLib.sol:87). The write is intentionally outside declared sequential storage because this linked library executes by delegatecall.
- Edges: none
- Observations: none

### `_seed/function` — GachaLib.sol:132

- Signature: `function _seed(uint256 bi) private view returns (bytes32 v)`
- Authority: internal (callers: GachaLib._pinSeeds and GachaLib.resolveTickets)
- Gate evidence: `UNGATED`
- Reads: `SEED_SLOT (line 133, constant)`
- Writes: none
- Value: NONE
- Reachability: Private namespaced pinned-seed reader. It hashes batch index with `SEED_SLOT` (GachaLib.sol:133) then uses `sload` (GachaLib.sol:134) in hook storage.
- Edges: none
- Observations: none

### `_pinSeed/function` — GachaLib.sol:137

- Signature: `function _pinSeed(uint256 bi, bytes32 v) private`
- Authority: internal (caller: GachaLib._pinSeeds)
- Gate evidence: `UNGATED`
- Reads: `SEED_SLOT (line 138, constant)`
- Writes: none
- Value: NONE
- Reachability: Private namespaced pinned-seed writer using `sstore` (GachaLib.sol:139) in the delegating hook's storage.
- Edges: none
- Observations: none

### `_pinSeeds/function` — GachaLib.sol:147

- Signature: `function _pinSeeds(Batch[] storage batches, uint256 from, uint256 end) private`
- Authority: internal (caller: GachaLib.resolveTickets)
- Gate evidence: `UNGATED`
- Reads: `PIN_SPAN (line 148, constant)`
- Writes: none
- Value: NONE
- Reachability: Private bounded pin sweep. It scans no more than `PIN_SPAN` (GachaLib.sol:148) unresolved batches, stores only a non-zero historical blockhash at `_pinSeed` (GachaLib.sol:153), and therefore never pins the current or a future block's unknown hash as zero.
- Edges: `GachaLib._seed (GachaLib.sol:151), TRUSTED, in-cluster`; `GachaLib._pinSeed (GachaLib.sol:153), TRUSTED, in-cluster`
- Observations: none

### `resolveTickets/function` — GachaLib.sol:173

- Signature: `function resolveTickets( Batch[] storage batches, mapping(address => uint256) storage missStreak, mapping(address => uint256) storage pendingOf, mapping(address => uint256) storage outstandingOf, mapping(address => uint256) storage opened, State storage st, uint256 pityThreshold, uint256 maxCount ) external returns (uint256 processed, uint256 won)`
- Authority: anyone at linked library address; protocol reaches it by delegatecall from CauldronHook
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: The hook delegatecalls this external linked-library function with storage references. FIFO processing starts at `batchCursor` (GachaLib.sol:183) and stops at a current-block commit. It uses a pinned original seed first, otherwise the live blockhash; first expiry reanchors once (`commitBlock` GachaLib.sol:201), and a second expiry cannot win from the known zero seed. Pending counters are decremented before the mint (`outstandingCrystals` GachaLib.sol:226). A win snapshots the player's miss streak (`streak` GachaLib.sol:237), resets it and counts the open; if the mint then fails the catch restores both the streak and the open count (`streak` GachaLib.sol:256), so a failed mint neither burns earned pity nor counts as a win. Cursor advancement is monotonic and a bounded seed-pin sweep follows (`_pinSeeds` GachaLib.sol:280).
- Edges: `GachaLib._seed (GachaLib.sol:192), TRUSTED, in-cluster`; `GachaLib._reanchored (GachaLib.sol:199), TRUSTED, in-cluster`; `GachaLib._markReanchored (GachaLib.sol:200), TRUSTED, in-cluster`; `ICauldronCollection.totalMinted (GachaLib.sol:214), UNTRUSTED, out-of-cluster`; `ICauldronCollection.maxSupply (GachaLib.sol:215), UNTRUSTED, out-of-cluster`; `ICauldronCollection.mint (GachaLib.sol:247), UNTRUSTED, out-of-cluster`; `GachaLib._pinSeeds (GachaLib.sol:280), TRUSTED, in-cluster`
- Observations: none


## `ITransferValidator (declared in ICreatorToken.sol)`

### `validateTransfer/function` — ICreatorToken.sol:8

- Signature: `function validateTransfer(address caller, address from, address to, uint256 tokenId) external view`
- Authority: declaration only (no body); in-cluster callers are the two collections' _update overrides; the validator contract itself is chosen by the collection's admin
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called on every mint, transfer and burn of either collection, at `validateTransfer` (MiFrensGenesis.sol:889) and `validateTransfer` (CauldronCollection.sol:176), and only while the slot is non-zero. The address is set by the genesis deployer at `transferValidator` (MiFrensGenesis.sol:647) or by the registry at `transferValidator` (CauldronCollection.sol:195), so an admin-chosen contract sits in the path of every token movement and can halt all of them by reverting. Declared view, but Solidity's type system is the only thing enforcing that on the callee.
- Edges: none
- Observations: none


## `ICreatorToken`

### `getTransferValidator/function` — ICreatorToken.sol:16

- Signature: `function getTransferValidator() external view returns (address)`
- Authority: anyone (the implementations are public views)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Market-facing discovery surface implemented at `getTransferValidator` (MiFrensGenesis.sol:634) and `getTransferValidator` (CauldronCollection.sol:182); both just return the stored slot.
- Edges: none
- Observations: none

### `getTransferValidationFunction/function` — ICreatorToken.sol:17

- Signature: `function getTransferValidationFunction() external view returns (bytes4 functionSignature, bool isViewFunction)`
- Authority: anyone (the implementations are pure)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Implemented at `getTransferValidationFunction` (MiFrensGenesis.sol:639) and `getTransferValidationFunction` (CauldronCollection.sol:187); both report the same selector and the view flag without reading state.
- Edges: none
- Observations: none

### `setTransferValidator/function` — ICreatorToken.sol:18

- Signature: `function setTransferValidator(address validator) external`
- Authority: the collection's admin: the genesis deployer or the registry for the per-brew collection
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:645)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Implemented at `setTransferValidator` (MiFrensGenesis.sol:644) under the genesis deployer gate, and at `setTransferValidator` (CauldronCollection.sol:192) under the registry gate. Neither implementation validates the address, so the same call can enable or disable royalty enforcement and, with a hostile target, freeze transfers entirely.
- Edges: none
- Observations: none


## `IMiFrensShares (declared in MiFrensDividend.sol)`

### `ownerOf/function` — MiFrensDividend.sol:8

- Signature: `function ownerOf(uint256 tokenId) external view returns (address)`
- Authority: declaration only (no body); in-cluster callers are pending, pendingToken, isEnchanted, _castSpell and _claim
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: The ownership oracle for every gate in this contract: read at `ownerOf` (MiFrensDividend.sol:363), `ownerOf` (MiFrensDividend.sol:466) and `ownerOf` (MiFrensDividend.sol:610) to authorise a claim or a cast, and at `ownerOf` (MiFrensDividend.sol:262) to decide whether an enchantment is still live. The address it is called on is the immutable collection at `mifrens` (MiFrensDividend.sol:176).
- Edges: none
- Observations: none

### `GENESIS_SUPPLY/function` — MiFrensDividend.sol:9

- Signature: `function GENESIS_SUPPLY() external view returns (uint256)`
- Authority: declaration only (no body); in-cluster caller is the constructor
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read once at `GENESIS_SUPPLY` (MiFrensDividend.sol:177) to fix the free-enchant tranche size; the result must be non-zero at `s` (MiFrensDividend.sol:178).
- Edges: none
- Observations: none

### `MAX_SUPPLY/function` — MiFrensDividend.sol:10

- Signature: `function MAX_SUPPLY() external view returns (uint256)`
- Authority: declaration only (no body); in-cluster caller is the constructor
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read once at `MAX_SUPPLY` (MiFrensDividend.sol:181) to fix the eligibility cap, floored at the genesis size at `m` (MiFrensDividend.sol:182). Because it is captured at deploy, a collection whose cap later changed would not be followed - in the collection this cluster ships, the value is immutable.
- Edges: none
- Observations: none

### `everMoved/function` — MiFrensDividend.sol:12

- Signature: `function everMoved(uint256 tokenId) external view returns (bool)`
- Authority: declaration only (no body); in-cluster caller is _collectEnchantFee
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `everMoved` (MiFrensDividend.sol:528) and only for ids at or below the free tranche: a genesis fren that has never moved returns early and pays nothing, everything else falls through to the fee.
- Edges: none
- Observations: none


## `IReserveRegistry (declared in MiFrensDividend.sol)`

### `enchantFee/function` — MiFrensDividend.sol:18

- Signature: `function enchantFee() external view returns (uint256)`
- Authority: declaration only (no body); in-cluster caller is _collectEnchantFee
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `enchantFee` (MiFrensDividend.sol:529); a zero answer makes the enchant free at `fee` (MiFrensDividend.sol:530). The registry can therefore switch the fee on and off for every future caster without any call into this contract.
- Edges: none
- Observations: none

### `currentToken/function` — MiFrensDividend.sol:19

- Signature: `function currentToken() external view returns (address)`
- Authority: declaration only (no body); in-cluster caller is _collectEnchantFee
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Read at `currentToken` (MiFrensDividend.sol:531) to decide which asset the fee is charged in, so the fee follows the live generation's token and a zero answer makes the enchant free at `tok` (MiFrensDividend.sol:532).
- Edges: none
- Observations: none

### `donateToReserve/function` — MiFrensDividend.sol:20

- Signature: `function donateToReserve(uint256 amount) external`
- Authority: declaration only (no body); in-cluster caller is _collectEnchantFee
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called at `donateToReserve` (MiFrensDividend.sol:536) after an approve for the exact fee, so the fee leaves this contract in the same transaction it arrived. A registry that does not pull the approved amount would leave the tokens sitting here with no path out. DERIVED: no other function in the file moves an arbitrary asset balance that is not credited to an accumulator.
- Edges: none
- Observations: none


## `MiFrensDividend`

### `constructor/constructor` — MiFrensDividend.sol:175

- Signature: `constructor(address _mifrens, address _treasury)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `mifrens (line 176, immutable)`; `SHARES (line 180, immutable)`; `MAX_TOKEN (line 182, immutable)`; `treasury (line 183, immutable)`
- Value: NONE
- Reachability: Deployment only, and it calls straight into the collection address it is handed at `mifrens` (MiFrensDividend.sol:176) with no code check. Four immutables are fixed here; the only mutable authorities afterwards are `registry` (MiFrensDividend.sol:192) and `funder` (MiFrensDividend.sol:202), both one-time and both held by `treasury` (MiFrensDividend.sol:183). The treasury address is also the sweep destination when nobody is enchanted, so the same address that wires the contract receives undistributable fees.
- Edges: `IMiFrensShares.GENESIS_SUPPLY (MiFrensDividend.sol:177), TRUSTED, in-cluster`; `IMiFrensShares.MAX_SUPPLY (MiFrensDividend.sol:181), TRUSTED, in-cluster`
- Observations: none

### `setRegistry/function` — MiFrensDividend.sol:189

- Signature: `function setRegistry(address _registry) external`
- Authority: treasury
- Gate evidence: `if (msg.sender != treasury) revert NotOwner(); (MiFrensDividend.sol:190)`
- Reads: `treasury (line 190, immutable)`; `registry (line 191)`
- Writes: `registry (line 192)`
- Value: NONE
- Reachability: One-time: a second call reverts on the non-zero `registry` (MiFrensDividend.sol:191) test, so the fee route is fixed forever once wired, and it cannot be unwired if the registry later misbehaves. Until it is set, the fee path at `reg` (MiFrensDividend.sol:526) returns immediately and every enchant is free.
- Edges: none
- Observations: none

### `setFunder/function` — MiFrensDividend.sol:199

- Signature: `function setFunder(address _funder) external`
- Authority: treasury
- Gate evidence: `if (msg.sender != treasury) revert NotOwner(); (MiFrensDividend.sol:200)`
- Reads: `treasury (line 200, immutable)`; `funder (line 201)`
- Writes: `funder (line 202)`
- Value: NONE
- Reachability: One-time: the non-zero test at `funder` (MiFrensDividend.sol:201) makes it unrepeatable, so the single address allowed to append to the basket is permanent. Until set, the basket funder check at `funder` (MiFrensDividend.sol:283) rejects everyone, which means a non-ETH fee has no way in at all.
- Edges: none
- Observations: none

### `receive/receive` — MiFrensDividend.sol:235

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `residual (line 237)`; `activeShares (line 238)`; `treasury (line 240, immutable)`; `ACC (line 245, constant)`; `activeShares (line 245)`; `accPerShare (line 246)`; `activeShares (line 249)`; `ACC (line 250, constant)`
- Writes: `totalDeposited (line 236)`; `residual (line 239)`; `residual (line 241)`; `accPerShare (line 246)`; `residual (line 252)`
- Value: receives native - declared `payable` (line 235); sends native to `treasury` (line 240)
- Reachability: Open to any sender. With nobody enchanted the whole balance including carried `residual` (MiFrensDividend.sol:237) is pushed to the treasury, and a rejecting treasury re-banks it (`residual` MiFrensDividend.sol:241) rather than reverting the fee-paying swap. Otherwise the deposit raises the per-share accumulator (`accPerShare` MiFrensDividend.sol:246) and the amount committed to holders is rounded UP (`committedWei` MiFrensDividend.sol:251), so the carried dust never exceeds what the accumulator leaves uncommitted and the sum of claims cannot exceed the balance (`residual` MiFrensDividend.sol:252). `totalDeposited` (MiFrensDividend.sol:236) counts raw deposits only.
- Edges: none
- Observations: none

### `pending/function` — MiFrensDividend.sol:260

- Signature: `function pending(uint256 tokenId) public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MAX_TOKEN (line 261, immutable)`; `enchantedBy (line 262)`; `accPerShare (line 263)`; `debtOf (line 263)`; `ACC (line 263, constant)`
- Writes: none
- Value: NONE
- Reachability: View. Returns zero for an id outside the eligibility cap at `MAX_TOKEN` (MiFrensDividend.sol:261) and for any fren whose caster is no longer its owner at `enchantedBy` (MiFrensDividend.sol:262), which is the same liveness test the claim path uses. It reverts for a non-existent id because the collection's ownerOf does.
- Edges: `IMiFrensShares.ownerOf (MiFrensDividend.sol:262), TRUSTED, in-cluster`
- Observations: none

### `fundToken/function` — MiFrensDividend.sol:278

- Signature: `function fundToken(address asset, uint256 amount) external`
- Authority: funder (hook), wired once by treasury
- Gate evidence: `if (msg.sender != funder) revert NotOwner(); (MiFrensDividend.sol:283)`
- Reads: `funder (line 283)`; `activeShares (line 285)`; `knownAsset (line 286)`; `assets (line 287)`; `MAX_ASSETS (line 287, constant)`; `accountedOf (line 292)`; `ACC (line 293, constant)`
- Writes: `knownAsset (line 288)`; `assets (line 289)`; `accountedOf (line 292)`; `accPerShareOf (line 293)`
- Value: pulls requested ERC20 `amount` of `asset` from funder via `_pull` (line 291)
- Reachability: Funder-only basket funding. It refuses zero values and zero active shares, hard-caps first-time assets, then pulls before accounting. `accountedOf` (MiFrensDividend.sol:292) and per-share accumulator both increase by the requested amount, not a measured balance delta; fee-on-transfer assets can therefore create undercollateralized claims (DERIVED).
- Edges: `MiFrensDividend._pull (MiFrensDividend.sol:291), TRUSTED, in-cluster`
- Observations: none

### `adopt/function` — MiFrensDividend.sol:328

- Signature: `function adopt(address asset) external returns (uint256 delta)`
- Authority: anyone for known assets; funder or treasury for a new asset
- Gate evidence: `if (msg.sender != funder && msg.sender != treasury) revert NotOwner(); (MiFrensDividend.sol:332)`
- Reads: `activeShares (line 330)`; `knownAsset (line 331)`; `funder (line 332)`; `treasury (line 332, immutable)`; `assets (line 333)`; `MAX_ASSETS (line 333, constant)`; `accountedOf (line 338)`; `ACC (line 342, constant)`
- Writes: `knownAsset (line 334)`; `assets (line 335)`; `accountedOf (line 341)`; `accPerShareOf (line 342)`
- Value: books ERC20 balance already held by this contract; no transfer occurs
- Reachability: Public push-adoption path. Existing basket assets may be adopted by anyone; only funder or treasury can consume a new basket slot at `funder` (MiFrensDividend.sol:332). It compares actual held balance against `accountedOf` (MiFrensDividend.sol:338), credits only the positive delta, advances accounting before return, and distributes raw asset units without decimal normalization.
- Edges: `IERC20.balanceOf (MiFrensDividend.sol:337), UNTRUSTED, out-of-cluster`
- Observations: none

### `pendingToken/function` — MiFrensDividend.sol:347

- Signature: `function pendingToken(uint256 tokenId, address asset) public view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MAX_TOKEN (line 348, immutable)`; `enchantedBy (line 349)`; `accPerShareOf (line 350)`; `debtOfAsset (line 350)`; `ACC (line 350, constant)`
- Writes: none
- Value: NONE
- Reachability: View, mirroring the ETH one per asset. It will underflow and revert rather than return zero if a debt marker ever exceeded the accumulator at `accPerShareOf` (MiFrensDividend.sol:350); the code keeps markers at or below the accumulator everywhere they are written. DERIVED: every write of `debtOfAsset` assigns the current accumulator value.
- Edges: `IMiFrensShares.ownerOf (MiFrensDividend.sol:349), TRUSTED, in-cluster`
- Observations: none

### `assetCount/function` — MiFrensDividend.sol:354

- Signature: `function assetCount() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `assets (line 354)`
- Writes: none
- Value: NONE
- Reachability: View of the basket length, which is the bound of every loop over `assets` (MiFrensDividend.sol:354).
- Edges: none
- Observations: none

### `claimTokens/function` — MiFrensDividend.sol:362

- Signature: `function claimTokens(uint256 tokenId) external nonReentrant`
- Authority: holder of token who is also its caster
- Gate evidence: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:363)`
- Reads: `enchantedBy (line 364)`; `assets (line 373)`; `assets (line 375)`; `accPerShareOf (line 376)`; `debtOfAsset (line 376)`; `ACC (line 376, constant)`; `accPerShareOf (line 378)`
- Writes: `debtOfAsset (line 378)`; `owedAsset (line 381)`
- Value: ERC20 push of `a` to `msg.sender` (line 380)
- Reachability: Two gates: current ownership at `ownerOf` (MiFrensDividend.sol:363) and a live enchantment by that same caller at `enchantedBy` (MiFrensDividend.sol:364), so a buyer cannot claim what the previous owner accrued. The per-asset debt marker is advanced at `debtOfAsset` (MiFrensDividend.sol:378) BEFORE the push, and a failed push banks the amount at `owedAsset` (MiFrensDividend.sol:381) instead of reverting, so one hostile token cannot block the other legs and nothing is paid twice. The loop is bounded by the basket length at `n` (MiFrensDividend.sol:373), which only the funder can grow. This path does not touch `totalClaimed` (MiFrensDividend.sol:601), which counts ETH only.
- Edges: `IMiFrensShares.ownerOf (MiFrensDividend.sol:363), TRUSTED, in-cluster`; `MiFrensDividend._tryPush (MiFrensDividend.sol:380), TRUSTED, in-cluster`
- Observations: none

### `withdrawOwedToken/function` — MiFrensDividend.sol:388

- Signature: `function withdrawOwedToken(address asset) external nonReentrant returns (uint256 amount)`
- Authority: anyone (pays only the caller's own banked balance)
- Gate evidence: `UNGATED`
- Reads: `owedAsset (line 389)`
- Writes: `owedAsset (line 391)`
- Value: ERC20 push of `asset` to `msg.sender` (line 395)
- Reachability: Ungated because it can only pay out `owedAsset` (MiFrensDividend.sol:389) for the caller's own address, zeroed at `owedAsset` (MiFrensDividend.sol:391) before the push and guarded by nonReentrant on the declaration at `withdrawOwedToken` (MiFrensDividend.sol:388). Unlike the claim loop this one reverts on a failed transfer at `TransferFailed` (MiFrensDividend.sol:395), which rolls the zeroing back so the balance stays banked. A zero balance is a silent no-op.
- Edges: `MiFrensDividend._tryPush (MiFrensDividend.sol:395), TRUSTED, in-cluster`
- Observations: none

### `_pull/function` — MiFrensDividend.sol:402

- Signature: `function _pull(address asset, address from, uint256 amount) private`
- Authority: internal (callers: fundToken)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: ERC20 transferFrom into this contract, encoded at `transferFrom` (line 404)
- Reachability: Raw call so a non-standard token is handled, with the result checked at `ret` (MiFrensDividend.sol:406) and a revert on failure. The asset address comes from the funder's argument, so the funder chooses which contract this calls into; it is the same address that is then appended to the iterated basket at `assets` (MiFrensDividend.sol:289).
- Edges: `IERC20.transferFrom (MiFrensDividend.sol:404), UNTRUSTED, out-of-cluster`
- Observations: none

### `_tryPush/function` — MiFrensDividend.sol:411

- Signature: `function _tryPush(address asset, address to, uint256 amount) private returns (bool)`
- Authority: internal (callers: claimTokens and withdrawOwedToken)
- Gate evidence: `UNGATED`
- Reads: `accountedOf (line 421)`
- Writes: `accountedOf (line 422)`
- Value: attempts an ERC20 transfer of `asset` to `to` through the isolated self-call (line 415)
- Reachability: Private non-throwing push. The transfer runs in an external self-call wrapped in try/catch (`pushTokenIsolated` MiFrensDividend.sol:415), so a token that reverts, returns false, returns garbage or returns a malformed payload is contained as a failure instead of reverting the claim. Only success decrements the booked balance, saturating at zero (`accountedOf` MiFrensDividend.sol:422).
- Edges: `MiFrensDividend.pushTokenIsolated (MiFrensDividend.sol:415), TRUSTED, in-cluster`
- Observations: none

### `pushTokenIsolated/function` — MiFrensDividend.sol:429

- Signature: `function pushTokenIsolated(address asset, address to, uint256 amount) external`
- Authority: this contract only (self-call)
- Gate evidence: `if (msg.sender != address(this)) revert NotOwner(); (MiFrensDividend.sol:430)`
- Reads: none
- Writes: none
- Value: transfers `amount` of `asset` from the dividend to the recipient by a raw `call` (line 435)
- Reachability: Self-only transfer helper for `_tryPush`. Refuses codeless assets (`TransferFailed` MiFrensDividend.sol:431), then accepts only an empty return or a return whose first word is exactly 1 (`valid` MiFrensDividend.sol:437), copying at most one word of return data; anything else reverts inside the isolated frame.
- Edges: `IERC20.transfer (MiFrensDividend.sol:432), UNTRUSTED, out-of-cluster`
- Observations: none

### `isEnchanted/function` — MiFrensDividend.sol:444

- Signature: `function isEnchanted(uint256 tokenId) external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MAX_TOKEN (line 445, immutable)`; `enchantedBy (line 446)`
- Writes: none
- Value: NONE
- Reachability: View of the same liveness test the pay paths use at `enchantedBy` (MiFrensDividend.sol:446). It does not mean the fren is counted in `activeShares` (MiFrensDividend.sol:476): a fren whose transfer hook was skipped reads as not-enchanted here while still occupying a share.
- Edges: `IMiFrensShares.ownerOf (MiFrensDividend.sol:446), TRUSTED, in-cluster`
- Observations: none

### `castSpell/function` — MiFrensDividend.sol:454

- Signature: `function castSpell(uint256 tokenId) external`
- Authority: holder of token
- Gate evidence: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:466)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Wrapper; the whole gate is in the callee at `ownerOf` (MiFrensDividend.sol:466).
- Edges: `MiFrensDividend._castSpell (MiFrensDividend.sol:455), TRUSTED, in-cluster`
- Observations: none

### `castMany/function` — MiFrensDividend.sol:459

- Signature: `function castMany(uint256[] calldata tokenIds) external`
- Authority: holder of token
- Gate evidence: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:466)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Unbounded batch: the loop at `n` (MiFrensDividend.sol:460) is sized by the caller's own array, and every element re-runs the per-token gate, so the only cost of a long list is the caller's gas. Each element may pull an enchant fee, so one transaction can charge the caller several fees.
- Edges: `MiFrensDividend._castSpell (MiFrensDividend.sol:461), TRUSTED, in-cluster`
- Observations: none

### `_castSpell/function` — MiFrensDividend.sol:464

- Signature: `function _castSpell(uint256 tokenId) private`
- Authority: internal (callers: castSpell, castMany); the caller must own the token
- Gate evidence: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:466)`
- Reads: `MAX_TOKEN (line 465, immutable)`; `enchantedBy (line 467)`; `accPerShare (line 480)`; `debtOf (line 480)`; `ACC (line 480, constant)`; `accPerShare (line 482)`; `assets (line 506)`; `assets (line 508)`; `accPerShareOf (line 509)`; `debtOfAsset (line 511)`; `ACC (line 512, constant)`
- Writes: `activeShares (line 476)`; `owed (line 480)`; `debtOf (line 482)`; `owedAsset (line 512)`; `debtOfAsset (line 514)`; `enchantedBy (line 516)`
- Value: NONE
- Reachability: Reachable by any current owner of an id within the cap at `MAX_TOKEN` (MiFrensDividend.sol:465). Two branches: a fresh join pays the fee first and then increments `activeShares` (MiFrensDividend.sol:476); a stale one - a fren whose transfer hook did not run - settles the PREVIOUS caster's ETH into `owed` (MiFrensDividend.sol:480) and their basket into `owedAsset` (MiFrensDividend.sol:512) and re-points without changing the count, so the share count stays balanced either way. Re-casting for an id you already hold returns at `cur` (MiFrensDividend.sol:468) before any fee. The debt markers for ETH and for every basket asset are set to the current accumulators at `debtOf` (MiFrensDividend.sol:482) and `debtOfAsset` (MiFrensDividend.sol:514), so earning starts now with no back-pay - but only for assets in the list at the time of the cast. DERIVED: the marker loop is bounded by the same basket the funder controls.
- Edges: `IMiFrensShares.ownerOf (MiFrensDividend.sol:466), TRUSTED, in-cluster`; `MiFrensDividend._collectEnchantFee (MiFrensDividend.sol:475), TRUSTED, in-cluster`
- Observations: none

### `_collectEnchantFee/function` — MiFrensDividend.sol:524

- Signature: `function _collectEnchantFee(uint256 tokenId) private`
- Authority: internal (callers: _castSpell)
- Gate evidence: `UNGATED`
- Reads: `registry (line 525)`; `SHARES (line 528, immutable)`
- Writes: none
- Value: ERC20 transferFrom of `tok` from the caster into this contract (line 534); ERC20 approve of `reg` for the fee (line 535)
- Reachability: Four independent early exits make the fee optional: no registry at `reg` (MiFrensDividend.sol:526), an unmoved original genesis id at `SHARES` (MiFrensDividend.sol:528), a zero fee at `fee` (MiFrensDividend.sol:530), or no live token at `tok` (MiFrensDividend.sol:532). The pull at `transferFrom` (MiFrensDividend.sol:534) is a typed call whose boolean return is required, so a token that returns nothing reverts the enchant. The amount, the asset and the destination are all chosen by the registry between the read and the transfer, and the approve return value is not checked at `approve` (MiFrensDividend.sol:535). Whatever is pulled is immediately handed on at `donateToReserve` (MiFrensDividend.sol:536); if that call does not take the tokens they stay here uncredited to anyone.
- Edges: `IMiFrensShares.everMoved (MiFrensDividend.sol:528), TRUSTED, in-cluster`; `IReserveRegistry.enchantFee (MiFrensDividend.sol:529), UNTRUSTED, in-cluster`; `IReserveRegistry.currentToken (MiFrensDividend.sol:531), UNTRUSTED, in-cluster`; `IERC20.transferFrom (MiFrensDividend.sol:534), UNTRUSTED, out-of-cluster`; `IERC20.approve (MiFrensDividend.sol:535), UNTRUSTED, out-of-cluster`; `IReserveRegistry.donateToReserve (MiFrensDividend.sol:536), UNTRUSTED, in-cluster`
- Observations: none

### `onMiFrenTransfer/function` — MiFrensDividend.sol:543

- Signature: `function onMiFrenTransfer(uint256 tokenId, address /*from*/) external`
- Authority: the MiFrens collection
- Gate evidence: `if (msg.sender != address(mifrens)) revert NotCollection(); (MiFrensDividend.sol:544)`
- Reads: `mifrens (line 544, immutable)`; `enchantedBy (line 545)`; `accPerShare (line 547)`; `debtOf (line 547)`; `ACC (line 547, constant)`; `assets (line 561)`; `assets (line 563)`; `accPerShareOf (line 564)`; `debtOfAsset (line 565)`; `ACC (line 567, constant)`
- Writes: `owed (line 547)`; `owedAsset (line 567)`; `debtOfAsset (line 568)`; `activeShares (line 572)`; `enchantedBy (line 573)`; `debtOf (line 574)`
- Value: NONE
- Reachability: Only the collection can call it, and it is invoked from that contract's transfer chokepoint at `onMiFrenTransfer` (MiFrensGenesis.sol:963) inside a try/catch with a fixed gas stipend - so a revert or an out-of-gas here is swallowed by the caller and the transfer still settles, leaving the fren counted in `activeShares` (MiFrensDividend.sol:572) with a stale caster. A fren that was never enchanted returns at `cur` (MiFrensDividend.sol:546), which is why badge ids and un-cast frens are free no-ops. Both the ETH entitlement at `owed` (MiFrensDividend.sol:547) and each basket leg at `owedAsset` (MiFrensDividend.sol:567) are settled to the LEAVER before the share is released, because after the decrement the leaver's share can no longer be computed. There is no eligibility-cap check here, unlike the claim and cast paths.
- Edges: none
- Observations: comment at `MAX_ASSETS` (MiFrensDividend.sol:559) says the basket cap is four because this loop runs under the collection's forwarded gas budget; code at `MAX_ASSETS` (MiFrensDividend.sol:124) sets the cap to three

### `claim/function` — MiFrensDividend.sol:581

- Signature: `function claim(uint256 tokenId) public nonReentrant returns (uint256 amount)`
- Authority: holder of token who is also its caster
- Gate evidence: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:610)`
- Reads: none
- Writes: none
- Value: sends native to `msg.sender` (line 617)
- Reachability: Wrapper carrying the nonReentrant guard at `claim` (MiFrensDividend.sol:581); the gates are in the callee at `ownerOf` (MiFrensDividend.sol:610).
- Edges: `MiFrensDividend._claim (MiFrensDividend.sol:582), TRUSTED, in-cluster`
- Observations: none

### `claimMany/function` — MiFrensDividend.sol:586

- Signature: `function claimMany(uint256[] calldata tokenIds) external nonReentrant returns (uint256 total)`
- Authority: holder of token who is also its caster
- Gate evidence: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:610)`
- Reads: none
- Writes: none
- Value: sends native to `msg.sender` (line 617)
- Reachability: Unbounded batch sized by the caller's own array at `n` (MiFrensDividend.sol:591); every element re-checks ownership and enchantment, and each one performs its own native send inside the single nonReentrant frame declared at `nonReentrant` (MiFrensDividend.sol:588). One id the caller does not own reverts the whole batch.
- Edges: `MiFrensDividend._claim (MiFrensDividend.sol:592), TRUSTED, in-cluster`
- Observations: none

### `withdrawOwed/function` — MiFrensDividend.sol:597

- Signature: `function withdrawOwed() external nonReentrant returns (uint256 amount)`
- Authority: anyone (pays only the caller's own banked balance)
- Gate evidence: `UNGATED`
- Reads: `owed (line 598)`
- Writes: `owed (line 600)`; `totalClaimed (line 601)`
- Value: sends native to `msg.sender` (line 602)
- Reachability: Ungated but self-limited: it pays only `owed` (MiFrensDividend.sol:598) for the caller, zeroed at `owed` (MiFrensDividend.sol:600) before the send, and the send is wrapped by nonReentrant at `withdrawOwed` (MiFrensDividend.sol:597). A rejecting recipient reverts at `TransferFailed` (MiFrensDividend.sol:603), rolling back the zeroing so nothing is lost. This is the only other writer of `totalClaimed` (MiFrensDividend.sol:601).
- Edges: none
- Observations: none

### `_claim/function` — MiFrensDividend.sol:608

- Signature: `function _claim(uint256 tokenId) private returns (uint256 amount)`
- Authority: internal (callers: claim, claimMany); the caller must own the token and be its caster
- Gate evidence: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:610)`
- Reads: `MAX_TOKEN (line 609, immutable)`; `enchantedBy (line 611)`; `accPerShare (line 613)`; `debtOf (line 613)`; `ACC (line 613, constant)`; `accPerShare (line 614)`
- Writes: `debtOf (line 614)`; `totalClaimed (line 616)`
- Value: sends native to `msg.sender` (line 617)
- Reachability: Three gates - the cap at `MAX_TOKEN` (MiFrensDividend.sol:609), current ownership at `ownerOf` (MiFrensDividend.sol:610), and a live enchantment by the caller at `enchantedBy` (MiFrensDividend.sol:611) - so exactly one address can ever claim a given id and only for the window it was enchanted. The debt marker is advanced at `debtOf` (MiFrensDividend.sol:614) before the send, so a re-entering recipient would compute zero; both public wrappers also hold the nonReentrant guard. The payout is integer-divided by the scale at `ACC` (MiFrensDividend.sol:613), so sub-wei dust stays in the accumulator rather than being lost.
- Edges: `IMiFrensShares.ownerOf (MiFrensDividend.sol:610), TRUSTED, in-cluster`
- Observations: none


## `IRegistrySummon (declared in MiFrensGenesis.sol)`

### `summon/function` — MiFrensGenesis.sol:17

- Signature: `function summon() external payable returns (address token, bytes32 poolId)`
- Authority: declaration only (no body); the sole in-cluster caller is MiFrensGenesis.igniteCauldron, which holds the gate; the implementing registry is out of cluster
- Gate evidence: `if (minted < GENESIS_SUPPLY) revert NotSoldOut(); (MiFrensGenesis.sol:801)`
- Reads: none
- Writes: none
- Value: receives native - declared `payable` (line 17)
- Reachability: Reached only from `igniteCauldron` (MiFrensGenesis.sol:788), which forwards the contract's entire balance at `summon` (MiFrensGenesis.sol:808). The callee's own authority check is out of cluster; on this side the call is guarded by the sellout test at `NotSoldOut` (MiFrensGenesis.sol:801) and the one-shot `finalized` flag (MiFrensGenesis.sol:806).
- Edges: none
- Observations: none

### `summoned/function` — MiFrensGenesis.sol:18

- Signature: `function summoned() external view returns (bool)`
- Authority: declaration only (no body); no call site exists in this cluster
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declared but never invoked by any cluster file: the only non-comment occurrence of the selector's sibling is the call to `summon` (MiFrensGenesis.sol:808), and `summoned` (MiFrensGenesis.sol:18) itself appears only in this declaration. DERIVED (grep of every cluster file for the identifier).
- Edges: none
- Observations: none


## `IMiFrensDividendHook (declared in MiFrensGenesis.sol)`

### `onMiFrenTransfer/function` — MiFrensGenesis.sol:22

- Signature: `function onMiFrenTransfer(uint256 tokenId, address from) external`
- Authority: declaration only (no body); the only in-cluster caller is MiFrensGenesis._update, and the address it is called on is whatever `setDividend` wired
- Gate evidence: `if (from != address(0) && dividend != address(0)) (MiFrensGenesis.sol:961)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Invoked from the ERC721 `_update` override (MiFrensGenesis.sol:880) on every non-mint move, in a try/catch with a fixed gas stipend at `GAS_DIVIDEND_FWD` (MiFrensGenesis.sol:963). The in-cluster implementation is `onMiFrenTransfer` (MiFrensDividend.sol:543); it only acts for an enchanted id.
- Edges: none
- Observations: none


## `MiFrensGenesis`

### `constructor/constructor` — MiFrensGenesis.sol:313

- Signature: `constructor( string memory name_, string memory symbol_, uint256 genesisSupply_, uint256 maxSupply_, uint256 price_, uint256 maxPerWallet_, string memory baseURI_ ) ERC721(name_, symbol_) EIP712(name_, "1")`
- Authority: deployer (constructor)
- Gate evidence: `UNGATED`
- Reads: `LIQUIDATOR_ID_BASE (line 333, constant)`
- Writes: `GENESIS_SUPPLY (line 334, immutable)`; `MAX_SUPPLY (line 335, immutable)`; `PRICE (line 336, immutable)`; `DISCOUNT_PRICE (line 337, immutable)`; `MAX_PER_WALLET (line 338)`; `_base (line 339)`; `deployer (line 340, immutable)`
- Value: NONE
- Reachability: Deployment only. `deployer` (MiFrensGenesis.sol:340) is fixed to the deploying address and is immutable, so every deployer-gated setter in this file is permanently bound to it. The art cap is forced below the badge id range (`LIQUIDATOR_ID_BASE` MiFrensGenesis.sol:333), so MiFren ids and Liquidatoor ids cannot collide. The frenlist price is fixed at one tenth of the public price (`DISCOUNT_PRICE` MiFrensGenesis.sol:337). The per-wallet cap is storage, adjustable only downward once minting has begun.
- Edges: none
- Observations: none

### `setMaxPerWallet/function` — MiFrensGenesis.sol:356

- Signature: `function setMaxPerWallet(uint256 newCap) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:357)`
- Reads: `deployer (line 357, immutable)`; `GENESIS_SUPPLY (line 358, immutable)`; `minted (line 359)`; `MAX_PER_WALLET (line 359)`
- Writes: `MAX_PER_WALLET (line 360)`
- Value: NONE
- Reachability: Deployer-only cap correction. The new cap must be non-zero and strictly below genesis supply. Before any mint it may move either way; after `minted` (MiFrensGenesis.sol:359) becomes non-zero it may only decrease, so buyers cannot have the cap widened after participation.
- Edges: none
- Observations: `balanceOf` is the mint gate elsewhere, so non-genesis badges held by an address also consume this wallet cap (DERIVED).

### `setUnrevealedURI/function` — MiFrensGenesis.sol:372

- Signature: `function setUnrevealedURI(string calldata uri) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:373)`
- Reads: `deployer (line 373, immutable)`
- Writes: `unrevealedURI (line 374)`
- Value: NONE
- Reachability: Deployer-only setter replacing the shared placeholder at `unrevealedURI` (MiFrensGenesis.sol:374). There is no freeze or URI validation.
- Edges: none
- Observations: none

### `setRegistry/function` — MiFrensGenesis.sol:378

- Signature: `function setRegistry(address _registry) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert ZeroAddress(); (MiFrensGenesis.sol:379)`
- Reads: `deployer (line 379, immutable)`; `registry (line 380)`
- Writes: `registry (line 382)`
- Value: NONE
- Reachability: Open to the deployer exactly once: the second call reverts on the non-zero `registry` (MiFrensGenesis.sol:380) test, so the summon target is write-once. Until it runs, `custodyTransfer` (MiFrensGenesis.sol:593) and the registry half of the gate at `registry` (MiFrensGenesis.sol:505) are unreachable, and `igniteCauldron` (MiFrensGenesis.sol:788) reverts on the zero `registry` (MiFrensGenesis.sol:789) and refuses to ignite.
- Edges: none
- Observations: none

### `mint/function` — MiFrensGenesis.sol:391

- Signature: `function mint(uint256 quantity) external payable nonReentrant`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `PRICE (line 392, immutable)`
- Writes: none
- Value: receives native - exact `msg.value` of the public price times quantity, checked in `_mintGenesis` (line 392)
- Reachability: Public presale mint at the full price; every check lives in the shared body (`_mintGenesis` MiFrensGenesis.sol:392). Reentrancy-guarded.
- Edges: `MiFrensGenesis._mintGenesis (MiFrensGenesis.sol:392), TRUSTED, in-cluster`
- Observations: none

### `mintDiscounted/function` — MiFrensGenesis.sol:398

- Signature: `function mintDiscounted(uint256 quantity, uint256 allowance, bytes32[] calldata proof) external payable nonReentrant`
- Authority: frenlisted wallets, up to their allowance
- Gate evidence: `if (!MerkleProof.verifyCalldata(proof, discountRoot, leaf)) revert NoDiscount(); (MiFrensGenesis.sol:404)`
- Reads: `discountRoot (line 404)`; `discountMinted (line 405)`; `DISCOUNT_PRICE (line 409, immutable)`
- Writes: `discountMinted (line 407)`
- Value: receives native - exact `msg.value` of the discount price times quantity, checked in `_mintGenesis` (line 409)
- Reachability: Frenlist mint at one tenth of the price. The leaf binds the caller and an allowance (`leaf` MiFrensGenesis.sol:403) and must prove against the current root; cumulative discounted mints may not exceed the allowance (`allowance` MiFrensGenesis.sol:406) and are booked before minting (`discountMinted` MiFrensGenesis.sol:407). It then shares every presale check with the public mint, including the lifetime per-wallet cap (`_mintGenesis` MiFrensGenesis.sol:409). A root replacement keeps each wallet's used count, so a re-published list cannot re-grant already used discount. Reentrancy-guarded.
- Edges: `MiFrensGenesis._mintGenesis (MiFrensGenesis.sol:409), TRUSTED, in-cluster`
- Observations: none

### `setDiscountRoot/function` — MiFrensGenesis.sol:414

- Signature: `function setDiscountRoot(bytes32 root) external`
- Authority: deployer or the discount setter
- Gate evidence: `if (msg.sender != deployer && msg.sender != discountSetter) revert NotAuthorized(); (MiFrensGenesis.sol:415)`
- Reads: `deployer (line 415, immutable)`; `discountSetter (line 415)`
- Writes: `discountRoot (line 416)`
- Value: NONE
- Reachability: Publishes or replaces the frenlist Merkle root (`discountRoot` MiFrensGenesis.sol:416); setting zero disables the discount path because no proof verifies against it.
- Edges: none
- Observations: none

### `setDiscountSetter/function` — MiFrensGenesis.sol:421

- Signature: `function setDiscountSetter(address setter) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:422)`
- Reads: `deployer (line 422, immutable)`
- Writes: `discountSetter (line 423)`
- Value: NONE
- Reachability: Deployer-only delegation of root publishing to one hot address (`discountSetter` MiFrensGenesis.sol:423); zero revokes it.
- Edges: none
- Observations: none

### `_mintGenesis/function` — MiFrensGenesis.sol:429

- Signature: `function _mintGenesis(uint256 quantity, uint256 unitPrice) private`
- Authority: internal (callers: mint, mintDiscounted)
- Gate evidence: `UNGATED`
- Reads: `finalized (line 430)`; `cancelled (line 431)`; `minted (line 433)`; `GENESIS_SUPPLY (line 433, immutable)`; `genesisMintedBy (line 438)`; `MAX_PER_WALLET (line 439)`; `minted (line 446)`
- Writes: `genesisMintedBy (line 440)`; `paid (line 442)`; `revealed (line 450)`; `minted (line 454)`
- Value: the attached native must equal `unitPrice` times quantity (line 434), and is booked for a cancel refund at `paid` (line 442)
- Reachability: Shared presale body. Blocked once `finalized` (MiFrensGenesis.sol:430) or `cancelled` (MiFrensGenesis.sol:431). Supply is capped at `GENESIS_SUPPLY` (MiFrensGenesis.sol:433); the exact price is required (`WrongPrice` MiFrensGenesis.sol:434). The per-wallet cap counts LIFETIME presale mints by the caller (`genesisMintedBy` MiFrensGenesis.sol:438), so transferring frens away cannot reopen the allowance. Payment is recorded for a cancel refund (`paid` MiFrensGenesis.sol:442). Each id is marked revealed before it is minted (`revealed` MiFrensGenesis.sol:450), and `_mint` (MiFrensGenesis.sol:451) goes through the `_update` override with from zero.
- Edges: none
- Observations: none

### `remainingGenesisAllowance/function` — MiFrensGenesis.sol:460

- Signature: `function remainingGenesisAllowance(address a) external view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: `genesisMintedBy (line 461)`; `MAX_PER_WALLET (line 462)`
- Writes: none
- Value: NONE
- Reachability: How many more presale mints an address may make under the lifetime cap, floored at zero (`MAX_PER_WALLET` MiFrensGenesis.sol:462).
- Edges: none
- Observations: none

### `cancelPresale/function` — MiFrensGenesis.sol:468

- Signature: `function cancelPresale() external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:469)`
- Reads: `deployer (line 469, immutable)`; `finalized (line 470)`; `cancelled (line 471)`
- Writes: `cancelled (line 472)`
- Value: NONE
- Reachability: Deployer-only and one-way: nothing in the file clears `cancelled` (MiFrensGenesis.sol:472), so after this call `mint` (MiFrensGenesis.sol:391) is permanently dead and only `refund` (MiFrensGenesis.sol:479) runs. It is refused after ignition by the `finalized` test (MiFrensGenesis.sol:470). DERIVED: `cancelled` is written on exactly one line in the file.
- Edges: none
- Observations: none

### `refund/function` — MiFrensGenesis.sol:479

- Signature: `function refund() external nonReentrant returns (uint256 amount)`
- Authority: anyone (pays out only to a caller with a recorded balance)
- Gate evidence: `UNGATED`
- Reads: `cancelled (line 480)`; `paid (line 481)`
- Writes: `paid (line 483)`
- Value: sends native to `msg.sender` (line 484)
- Reachability: Only after the deployer sets `cancelled` (MiFrensGenesis.sol:480). Pays back exactly the caller's recorded `paid` (MiFrensGenesis.sol:481) balance, which is zeroed at `paid` (MiFrensGenesis.sol:483) before the external send, so a re-entering receiver finds nothing left; the OZ `nonReentrant` guard on the declaration (MiFrensGenesis.sol:479) blocks re-entry as well. The NFTs already minted are not burned, so the refunded ETH and the tokens both survive the cancel.
- Edges: none
- Observations: none

### `totalMinted/function` — MiFrensGenesis.sol:494

- Signature: `function totalMinted() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `minted (line 495)`
- Writes: none
- Value: NONE
- Reachability: View. Counts genesis mints written at `minted` (MiFrensGenesis.sol:454) plus volume mints written at `minted` (MiFrensGenesis.sol:657); Liquidatoor badges are not included because they increment `liquidatorMinted` (MiFrensGenesis.sol:558) instead. Burns via `burnFromVault` (MiFrensGenesis.sol:758) never decrement it. DERIVED: those are the only two writes to the counter in the file.
- Edges: none
- Observations: none

### `maxSupply/function` — MiFrensGenesis.sol:499

- Signature: `function maxSupply() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `MAX_SUPPLY (line 500, immutable)`
- Writes: none
- Value: NONE
- Reachability: View of the immutable art cap set in the constructor at `MAX_SUPPLY` (MiFrensGenesis.sol:335). It bounds only the volume tranche check at `MAX_SUPPLY` (MiFrensGenesis.sol:655).
- Edges: none
- Observations: none

### `onlyDeployerOrRegistry/modifier` — MiFrensGenesis.sol:504

- Signature: `modifier onlyDeployerOrRegistry()`
- Authority: internal (callers: setMinter, setVault, setDividend)
- Gate evidence: `if (msg.sender != deployer && msg.sender != address(registry)) revert NotAuthorized(); (MiFrensGenesis.sol:505)`
- Reads: `deployer (line 505, immutable)`; `registry (line 505)`
- Writes: none
- Value: NONE
- Reachability: Applied to `setMinter` (MiFrensGenesis.sol:512), `setVault` (MiFrensGenesis.sol:517) and `setDividend` (MiFrensGenesis.sol:522). Both holders are permanent: `deployer` (MiFrensGenesis.sol:340) is immutable and `registry` (MiFrensGenesis.sol:382) is write-once, so this gate cannot be rotated, renounced or dead-ended. DERIVED: no other function in the file writes either slot.
- Edges: none
- Observations: none

### `setMinter/function` — MiFrensGenesis.sol:512

- Signature: `function setMinter(address _minter) external onlyDeployerOrRegistry`
- Authority: deployer or registry
- Gate evidence: `external onlyDeployerOrRegistry (MiFrensGenesis.sol:512)`
- Reads: none
- Writes: `minter (line 513)`
- Value: NONE
- Reachability: Gate held by the modifier at `onlyDeployerOrRegistry` (MiFrensGenesis.sol:504). Re-settable with no zero check, so the volume-mint right at `minter` (MiFrensGenesis.sol:654) can be moved to any address at any time, including after ignition.
- Edges: none
- Observations: none

### `setVault/function` — MiFrensGenesis.sol:517

- Signature: `function setVault(address _vault) external onlyDeployerOrRegistry`
- Authority: deployer or registry
- Gate evidence: `external onlyDeployerOrRegistry (MiFrensGenesis.sol:517)`
- Reads: none
- Writes: `vault (line 518)`
- Value: NONE
- Reachability: Gate held by the modifier at `onlyDeployerOrRegistry` (MiFrensGenesis.sol:504). Grants the burn right checked at `vault` (MiFrensGenesis.sol:759); re-settable per iteration, again with no zero check.
- Edges: none
- Observations: none

### `setDividend/function` — MiFrensGenesis.sol:522

- Signature: `function setDividend(address _dividend) external onlyDeployerOrRegistry`
- Authority: deployer or registry
- Gate evidence: `external onlyDeployerOrRegistry (MiFrensGenesis.sol:522)`
- Reads: none
- Writes: `dividend (line 523)`
- Value: NONE
- Reachability: Gate held by the modifier at `onlyDeployerOrRegistry` (MiFrensGenesis.sol:504). Sets the address pinged on every non-mint transfer at `dividend` (MiFrensGenesis.sol:961); setting it to zero silently disables the enchantment break.
- Edges: none
- Observations: none

### `setLiquidatorMinter/function` — MiFrensGenesis.sol:530

- Signature: `function setLiquidatorMinter(address _minter) external`
- Authority: deployer, registry, or the wired minter (the volume hook)
- Gate evidence: `if (msg.sender != deployer && msg.sender != address(registry) && msg.sender != minter) revert NotAuthorized(); (MiFrensGenesis.sol:531)`
- Reads: `deployer (line 531, immutable)`; `registry (line 531)`; `minter (line 531)`
- Writes: `liquidatorMinter (line 532)`
- Value: NONE
- Reachability: Three holders, the third of which is itself settable: whoever holds `minter` (MiFrensGenesis.sol:531) can hand the badge-mint right on. Confers the only authority accepted at `liquidatorMinter` (MiFrensGenesis.sol:557).
- Edges: none
- Observations: none

### `setLiquidatorURI/function` — MiFrensGenesis.sol:536

- Signature: `function setLiquidatorURI(string calldata uri) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:537)`
- Reads: `deployer (line 537, immutable)`
- Writes: `liquidatorURI (line 538)`
- Value: NONE
- Reachability: Deployer-only metadata base used by the badge branch of `liquidatorURI` (MiFrensGenesis.sol:861).
- Edges: none
- Observations: none

### `mintLiquidator/function` — MiFrensGenesis.sol:544

- Signature: `function mintLiquidator(address to) external returns (uint256 tokenId)`
- Authority: liquidatorMinter (the wired PerpEngine)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (MiFrensGenesis.sol:557)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Thin wrapper; the authority check lives in the callee at `liquidatorMinter` (MiFrensGenesis.sol:557). Passes an empty stats struct so the `_liqStats` write (MiFrensGenesis.sol:561) is skipped.
- Edges: `MiFrensGenesis._mintLiquidator (MiFrensGenesis.sol:545), TRUSTED, in-cluster`
- Observations: none

### `mintLiquidatorWithStats/function` — MiFrensGenesis.sol:549

- Signature: `function mintLiquidatorWithStats(address to, LiqStats calldata st) external returns (uint256 tokenId)`
- Authority: liquidatorMinter (the wired PerpEngine)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (MiFrensGenesis.sol:557)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Same gate as the bare variant, in the callee at `liquidatorMinter` (MiFrensGenesis.sol:557); the caller-supplied stats are recorded verbatim at `_liqStats` (MiFrensGenesis.sol:561) with no validation of victim, size or price.
- Edges: `MiFrensGenesis._mintLiquidator (MiFrensGenesis.sol:553), TRUSTED, in-cluster`
- Observations: none

### `_mintLiquidator/function` — MiFrensGenesis.sol:556

- Signature: `function _mintLiquidator(address to, LiqStats memory st) internal returns (uint256 tokenId)`
- Authority: internal (callers: mintLiquidator, mintLiquidatorWithStats)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (MiFrensGenesis.sol:557)`
- Reads: `liquidatorMinter (line 557)`; `LIQUIDATOR_ID_BASE (line 558, constant)`; `liquidatorMinted (line 558)`
- Writes: `liquidatorMinted (line 558)`; `isLiquidatoor (line 559)`; `_liqStats (line 561)`
- Value: NONE
- Reachability: Badge ids are `LIQUIDATOR_ID_BASE` plus a counter (MiFrensGenesis.sol:558) and are uncapped - nothing here compares against `MAX_SUPPLY` (MiFrensGenesis.sol:655). Because the constructor refuses a cap at or above `LIQUIDATOR_ID_BASE` (MiFrensGenesis.sol:333), badge ids can never overlap art ids. Each badge is a full ERC721Votes token, so it carries a vote through the self-delegation at `_delegate` (MiFrensGenesis.sol:928). The ERC721 mint itself happens at `_mint` (MiFrensGenesis.sol:562), which re-enters the `_update` override (MiFrensGenesis.sol:880).
- Edges: none
- Observations: none

### `liqStats/function` — MiFrensGenesis.sol:567

- Signature: `function liqStats(uint256 tokenId) external view returns (LiqStats memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_liqStats (line 568)`
- Writes: none
- Value: NONE
- Reachability: View of whatever the badge minter recorded at `_liqStats` (MiFrensGenesis.sol:561); returns a zeroed struct for ids that were minted through the bare `mintLiquidator` (MiFrensGenesis.sol:544) path or that are not badges at all.
- Edges: none
- Observations: none

### `setLiquidatorRenderer/function` — MiFrensGenesis.sol:572

- Signature: `function setLiquidatorRenderer(address r) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:573)`
- Reads: `deployer (line 573, immutable)`
- Writes: `liquidatorRenderer (line 574)`
- Value: NONE
- Reachability: Deployer-only. Points the badge branch of `tokenURI` (MiFrensGenesis.sol:859) at an arbitrary contract whose code is called on every badge metadata read.
- Edges: none
- Observations: none

### `liquidatoorTrait/function` — MiFrensGenesis.sol:578

- Signature: `function liquidatoorTrait(uint256 tokenId) external view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `isLiquidatoor (line 579)`
- Writes: none
- Value: NONE
- Reachability: View over the flag written at `isLiquidatoor` (MiFrensGenesis.sol:559).
- Edges: none
- Observations: none

### `custodyTransfer/function` — MiFrensGenesis.sol:593

- Signature: `function custodyTransfer(address from, address to, uint256 tokenId) external`
- Authority: registry
- Gate evidence: `if (msg.sender != address(registry)) revert NotAuthorized(); (MiFrensGenesis.sol:594)`
- Reads: `registry (line 594)`
- Writes: none
- Value: NONE
- Reachability: Registry-only move with no owner approval: `_transfer` (MiFrensGenesis.sol:595) checks only that `from` is the current owner. It routes through the `_update` override (MiFrensGenesis.sol:880), so it breaks the enchantment, moves the vote and sets `everMoved` (MiFrensGenesis.sol:970) exactly like a market transfer. No burn happens here, so the collection count is unchanged.
- Edges: none
- Observations: none

### `setFinalizer/function` — MiFrensGenesis.sol:602

- Signature: `function setFinalizer(address _finalizer) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:603)`
- Reads: `deployer (line 603, immutable)`
- Writes: `finalizer (line 604)`
- Value: NONE
- Reachability: Deployer-only. Writing a non-zero `finalizer` (MiFrensGenesis.sol:604) converts ignition from permissionless to single-address, enforced at `finalizer` (MiFrensGenesis.sol:804); it can be set back to zero at any time before ignition.
- Edges: none
- Observations: none

### `setMetadata/function` — MiFrensGenesis.sol:608

- Signature: `function setMetadata(MetadataMode _mode, address _renderer, string calldata baseURI_) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:611)`
- Reads: `deployer (line 611, immutable)`
- Writes: `mode (line 612)`; `renderer (line 613)`; `_base (line 614)`
- Value: NONE
- Reachability: Deployer-only, unlimited re-settable. An empty string leaves `_base` (MiFrensGenesis.sol:614) untouched, but `mode` (MiFrensGenesis.sol:612) and `renderer` (MiFrensGenesis.sol:613) are always overwritten, so passing a zero renderer with Renderer mode falls back to the baseURI branch at `renderer` (MiFrensGenesis.sol:866).
- Edges: none
- Observations: none

### `setRarityOdds/function` — MiFrensGenesis.sol:618

- Signature: `function setRarityOdds(uint16[4] calldata cum) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:619)`
- Reads: `deployer (line 619, immutable)`
- Writes: `rarityCumBps (line 621)`
- Value: NONE
- Reachability: Deployer-only. The require at `cum` (MiFrensGenesis.sol:620) enforces ascending cumulative bps ending at 10000, but nothing pins the odds at reveal time: a token minted under one ladder is rolled against whatever `rarityCumBps` (MiFrensGenesis.sol:766) holds when `_reveal` runs.
- Edges: none
- Observations: none

### `setRoyalty/function` — MiFrensGenesis.sol:625

- Signature: `function setRoyalty(address receiver, uint96 bps) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:626)`
- Reads: `deployer (line 626, immutable)`
- Writes: none
- Value: NONE
- Reachability: Deployer-only, capped at 10 percent by the require at `bps` (MiFrensGenesis.sol:627). The receiver and rate land in the inherited ERC2981 storage through `_setDefaultRoyalty` (MiFrensGenesis.sol:628), which this file never reads back.
- Edges: none
- Observations: none

### `getTransferValidator/function` — MiFrensGenesis.sol:634

- Signature: `function getTransferValidator() external view returns (address)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `transferValidator (line 635)`
- Writes: none
- Value: NONE
- Reachability: View of the slot written at `transferValidator` (MiFrensGenesis.sol:647) and consulted on every move at `transferValidator` (MiFrensGenesis.sol:887).
- Edges: none
- Observations: none

### `getTransferValidationFunction/function` — MiFrensGenesis.sol:639

- Signature: `function getTransferValidationFunction() external pure returns (bytes4 functionSignature, bool isViewFunction)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Pure constant pair advertising the validator entry point; it returns the selector of `validateTransfer` (MiFrensGenesis.sol:640) and reads no state.
- Edges: none
- Observations: none

### `setTransferValidator/function` — MiFrensGenesis.sol:644

- Signature: `function setTransferValidator(address validator) external`
- Authority: deployer
- Gate evidence: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:645)`
- Reads: `transferValidator (line 646)`
- Writes: `transferValidator (line 647)`
- Value: NONE
- Reachability: Deployer-only and freely re-settable, including to zero. A non-zero value makes every mint, transfer and burn call out to that address first at `validateTransfer` (MiFrensGenesis.sol:889), so a validator that reverts halts the whole collection - including the vault burn at `_burn` (MiFrensGenesis.sol:760) and the registry move at `_transfer` (MiFrensGenesis.sol:595). DERIVED: `_update` is the single ERC721 chokepoint, and the validator call precedes the super call.
- Edges: none
- Observations: none

### `mint/function` — MiFrensGenesis.sol:653

- Signature: `function mint(address to) external returns (uint256 tokenId)`
- Authority: minter (the wired volume hook)
- Gate evidence: `if (msg.sender != minter) revert OnlyMinter(); (MiFrensGenesis.sol:654)`
- Reads: `minter (line 654)`; `minted (line 655)`; `MAX_SUPPLY (line 655, immutable)`; `minted (line 656)`
- Writes: `minted (line 657)`; `mintBlockOf (line 659)`
- Value: NONE
- Reachability: Only the address in `minter` (MiFrensGenesis.sol:654) reaches this, and only while `minted` is below `MAX_SUPPLY` (MiFrensGenesis.sol:655). The id is `minted` plus one (MiFrensGenesis.sol:656), so this tranche continues the same numbering the presale used and a never-sold-out genesis leaves ids that a volume mint will then occupy. Rarity is not rolled here: only the mint block is committed at `mintBlockOf` (MiFrensGenesis.sol:659). The token itself is created at `_mint` (MiFrensGenesis.sol:660).
- Edges: none
- Observations: none

### `reveal/function` — MiFrensGenesis.sol:666

- Signature: `function reveal(uint256 tokenId) external`
- Authority: holder of token
- Gate evidence: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (MiFrensGenesis.sol:700)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Wrapper; the ownership gate is in the callee at `ownerOf` (MiFrensGenesis.sol:700). A genesis id is already flagged at `revealed` (MiFrensGenesis.sol:450) so the call is a no-op for the OG tranche.
- Edges: `MiFrensGenesis._reveal (MiFrensGenesis.sol:667), TRUSTED, in-cluster`
- Observations: none

### `revealBatch/function` — MiFrensGenesis.sol:686

- Signature: `function revealBatch(uint256[] calldata tokenIds) external`
- Authority: holder of token
- Gate evidence: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (MiFrensGenesis.sol:700)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Batch wrapper bounded at fifty ids by the check at `BadBatch` (MiFrensGenesis.sol:690); every element still passes the per-token ownership gate at `ownerOf` (MiFrensGenesis.sol:700), so one id the caller does not own reverts the whole batch.
- Edges: `MiFrensGenesis._reveal (MiFrensGenesis.sol:691), TRUSTED, in-cluster`
- Observations: none

### `_reveal/function` — MiFrensGenesis.sol:699

- Signature: `function _reveal(uint256 tokenId) private`
- Authority: internal (callers: reveal and revealBatch); caller must own token
- Gate evidence: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (MiFrensGenesis.sol:700)`
- Reads: `revealed (line 701)`; `mintBlockOf (line 702)`; `reanchored (line 739)`
- Writes: `reanchored (line 740)`; `mintBlockOf (line 741)`; `rarityOf (line 745)`; `revealed (line 746)`
- Value: NONE
- Reachability: Owner-only internal reveal body. A first expired seed spends `reanchored` (MiFrensGenesis.sol:740), rewrites the commit block, and returns. A second expiry marks base rarity revealed at `revealed` (MiFrensGenesis.sol:746), preventing further rerolls. A live blockhash is mixed with token id and contract address before `_rollRarity` (MiFrensGenesis.sol:750).
- Edges: `ERC721.ownerOf (MiFrensGenesis.sol:700), TRUSTED, out-of-cluster`; `MiFrensGenesis._rollRarity (MiFrensGenesis.sol:750), TRUSTED, in-cluster`
- Observations: The comment says a holder or keeper can retry, but the `ownerOf` gate (MiFrensGenesis.sol:700) excludes keepers.

### `burnFromVault/function` — MiFrensGenesis.sol:758

- Signature: `function burnFromVault(uint256 tokenId) external`
- Authority: vault
- Gate evidence: `if (msg.sender != vault) revert OnlyVault(); (MiFrensGenesis.sol:759)`
- Reads: `vault (line 759)`
- Writes: none
- Value: NONE
- Reachability: Only the address wired at `vault` (MiFrensGenesis.sol:518). The burn does not touch `minted` (MiFrensGenesis.sol:657), so the counter that gates new mints is monotonic and a burned id is never re-issued; the ERC721 balance and the counter therefore diverge by exactly the number of burns. DERIVED: no line in the file decrements the counter.
- Edges: none
- Observations: none

### `_rollRarity/function` — MiFrensGenesis.sol:763

- Signature: `function _rollRarity(uint256 seed) private view returns (uint8)`
- Authority: internal (callers: _reveal)
- Gate evidence: `UNGATED`
- Reads: `rarityCumBps (line 766)`
- Writes: none
- Value: NONE
- Reachability: Called only from the reveal path at `_rollRarity` (MiFrensGenesis.sol:750). Walks the four cumulative buckets at `rarityCumBps` (MiFrensGenesis.sol:766) and falls through to tier zero, so a ladder whose last entry is below 10000 silently returns the common tier.
- Edges: none
- Observations: none

### `igniteCauldron/function` — MiFrensGenesis.sol:788

- Signature: `function igniteCauldron() external nonReentrant returns (address token)`
- Authority: anyone once sold out - unless a finalizer is set, and then only the finalizer
- Gate evidence: `if (finalizer != address(0) && msg.sender != finalizer) revert NotAuthorized(); (MiFrensGenesis.sol:804)`
- Reads: `registry (line 789)`; `finalized (line 790)`; `cancelled (line 800)`; `minted (line 801)`; `GENESIS_SUPPLY (line 801, immutable)`; `finalizer (line 804)`
- Writes: `finalized (line 806)`
- Value: forwards this contract's ENTIRE native balance to the registry's summon at `summon` (line 808)
- Reachability: Permissionless ignition, guarded by `nonReentrant` (MiFrensGenesis.sol:788) and by four state tests in order: the registry must be wired at `RegistryNotSet` (MiFrensGenesis.sol:789), ignition must not have happened at `AlreadyFinalized` (MiFrensGenesis.sol:790), the round must not be CANCELLED at `AlreadyCancelled` (MiFrensGenesis.sol:800), and the genesis tranche must be sold out at `NotSoldOut` (MiFrensGenesis.sol:801); a configured finalizer narrows the caller at `finalizer` (MiFrensGenesis.sol:804) so the team's atomic summon-plus-buy cannot be front-run. The cancelled check is the NEW one and it closes a drain: cancellation has no sell-out precondition, so 'cancelled AND sold out' is an ordinary state in which every other gate passed, and the whole un-refunded balance was forwarded at `summon` (MiFrensGenesis.sol:808) while the refund debt survived - `refund` being the only other native exit and there being no owner sweep. `finalized` (MiFrensGenesis.sol:806) is written before the external call, so the summon cannot re-enter this entry (DERIVED). The amount forwarded is the whole balance read at `bal` (MiFrensGenesis.sol:807), not a tracked total, so any ether pushed in by other means is summoned too (DERIVED).
- Edges: `IRegistrySummon.summon (MiFrensGenesis.sol:808), TRUSTED, out-of-cluster`
- Observations: none

### `soldOut/function` — MiFrensGenesis.sol:817

- Signature: `function soldOut() external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `minted (line 818)`; `GENESIS_SUPPLY (line 818, immutable)`
- Writes: none
- Value: NONE
- Reachability: View mirroring the ignition condition at `GENESIS_SUPPLY` (MiFrensGenesis.sol:801).
- Edges: none
- Observations: none

### `remaining/function` — MiFrensGenesis.sol:822

- Signature: `function remaining() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `minted (line 823)`; `GENESIS_SUPPLY (line 823, immutable)`
- Writes: none
- Value: NONE
- Reachability: View. Saturates at zero rather than underflowing when `minted` (MiFrensGenesis.sol:823) has passed the genesis cap via volume mints.
- Edges: none
- Observations: none

### `isGenesis/function` — MiFrensGenesis.sol:833

- Signature: `function isGenesis(uint256 tokenId) public view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `GENESIS_SUPPLY (line 834, immutable)`
- Writes: none
- Value: NONE
- Reachability: Pure id comparison against the immutable `GENESIS_SUPPLY` (MiFrensGenesis.sol:834); id zero is excluded. Badge ids start at `LIQUIDATOR_ID_BASE` (MiFrensGenesis.sol:558) and so are never genesis.
- Edges: none
- Observations: none

### `_getVotingUnits/function` — MiFrensGenesis.sol:843

- Signature: `function _getVotingUnits(address account) internal view override returns (uint256)`
- Authority: internal (called by inherited ERC721Votes delegation logic)
- Gate evidence: `UNGATED`
- Reads: `genesisBalanceOf (line 844)`
- Writes: none
- Value: NONE
- Reachability: Internal voting-unit override returning only `genesisBalanceOf` (MiFrensGenesis.sol:844), so delegation moves the same units that the custom update path checkpoints and excludes forged art plus badges.
- Edges: none
- Observations: none

### `ogTrait/function` — MiFrensGenesis.sol:850

- Signature: `function ogTrait(uint256 tokenId) external view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: View helper over `isGenesis` (MiFrensGenesis.sol:833).
- Edges: `MiFrensGenesis.isGenesis (MiFrensGenesis.sol:851), TRUSTED, in-cluster`
- Observations: comment at `rarity` (MiFrensGenesis.sol:848) says the non-genesis branch reports the rolled rarity tier; code at `isGenesis` (MiFrensGenesis.sol:851) returns a fixed string for every non-genesis id and never reads `rarityOf` (MiFrensGenesis.sol:751)

### `tokenURI/function` — MiFrensGenesis.sol:854

- Signature: `function tokenURI(uint256 tokenId) public view override returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `isLiquidatoor (line 857)`; `liquidatorRenderer (line 858)`; `liquidatorURI (line 861)`; `GENESIS_SUPPLY (line 865, immutable)`; `revealed (line 865)`; `unrevealedURI (line 865)`; `mode (line 866)`; `renderer (line 866)`; `_base (line 869)`
- Writes: none
- Value: NONE
- Reachability: View, but it calls out to two deployer-settable contracts: the badge renderer at `liquidatorRenderer` (MiFrensGenesis.sol:858) and the art renderer at `renderer` (MiFrensGenesis.sol:866). Reverts for an unowned id at `_requireOwned` (MiFrensGenesis.sol:855). Only ids above `GENESIS_SUPPLY` (MiFrensGenesis.sol:865) can show the placeholder, so an unrevealed genesis id is impossible by construction. Both string branches concatenate the id through `toString` (MiFrensGenesis.sol:861) and `toString` (MiFrensGenesis.sol:869).
- Edges: `ICollectionRenderer.tokenURI (MiFrensGenesis.sol:859), UNTRUSTED, out-of-cluster`; `ICollectionRenderer.tokenURI (MiFrensGenesis.sol:867), UNTRUSTED, out-of-cluster`
- Observations: none

### `_update/function` — MiFrensGenesis.sol:880

- Signature: `function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Votes) returns (address)`
- Authority: internal (all ERC721 mint, transfer, and burn paths)
- Gate evidence: `UNGATED`
- Reads: `transferValidator (line 887)`; `GENESIS_SUPPLY (line 912, immutable)`; `genesisBalanceOf (line 919)`; `dividend (line 961)`; `GAS_DIVIDEND_MIN (line 962, constant)`; `GAS_DIVIDEND_FWD (line 963, constant)`; `everMoved (line 969)`
- Writes: `genesisBalanceOf (line 919)`; `genesisBalanceOf (line 920)`; `everMoved (line 970)`
- Value: NONE
- Reachability: Movement chokepoint. A configured validator runs before state change at `validateTransfer` (MiFrensGenesis.sol:889). Genesis ids use the votes-aware update and adjust `genesisBalanceOf`; every other id bypasses ERC721Votes through `ERC721` (MiFrensGenesis.sol:925), excluding them from numerator and total-supply checkpoints. Recipients self-delegate if needed. Existing-token moves require a fixed dividend gas floor, call the dividend after ownership changed in caught try/catch, then permanently mark moved genesis ids at `everMoved` (MiFrensGenesis.sol:970).
- Edges: `ITransferValidator.validateTransfer (MiFrensGenesis.sol:889), UNTRUSTED, out-of-cluster`; `MiFrensGenesis._update (MiFrensGenesis.sol:915), TRUSTED, out-of-cluster`; `ERC721._update (MiFrensGenesis.sol:925), TRUSTED, out-of-cluster`; `IMiFrensDividendHook.onMiFrenTransfer (MiFrensGenesis.sol:963), UNTRUSTED, in-cluster`
- Observations: none

### `_increaseBalance/function` — MiFrensGenesis.sol:975

- Signature: `function _increaseBalance(address account, uint128 amount) internal override(ERC721, ERC721Votes)`
- Authority: internal (callers: ERC721 batch-mint plumbing)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Diamond resolution only; it forwards to the inherited implementation at `_increaseBalance` (MiFrensGenesis.sol:979) and no code in this file calls it directly. DERIVED: the identifier appears nowhere else in the file.
- Edges: `ERC721._increaseBalance (MiFrensGenesis.sol:979), TRUSTED, out-of-cluster`
- Observations: none

### `supportsInterface/function` — MiFrensGenesis.sol:983

- Signature: `function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: View. Adds the creator-token id to whatever the inherited chain answers at `supportsInterface` (MiFrensGenesis.sol:984).
- Edges: `ERC2981.supportsInterface (MiFrensGenesis.sol:984), TRUSTED, out-of-cluster`
- Observations: none


## `MintCurvePolicy`

### `constructor/constructor` — MintCurvePolicy.sol:71

- Signature: `constructor(uint256 _base, uint256 _spread, uint256 _knee, uint256 _supply)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `base (line 83, immutable)`; `spread (line 84, immutable)`; `knee (line 85, immutable)`; `supply (line 86, immutable)`
- Value: NONE
- Reachability: Deployment only; the launch script in the deploy directory is the only place in the tree that constructs it. The contract has no storage and no owner at all: all four parameters are immutable, so the ladder cannot be re-tuned after deploy and there is no gate to rotate or renounce. A zero `_knee` (MintCurvePolicy.sol:75) is refused because it would divide by zero at position zero, and a zero `_spread` (MintCurvePolicy.sol:82) is refused because a flat ladder breaks the rising-floor property the comment describes.
- Edges: none
- Observations: none

### `priceAt/function` — MintCurvePolicy.sol:119

- Signature: `function priceAt(uint256 k, uint256, uint256) external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `base (line 123, immutable)`; `spread (line 123, immutable)`; `knee (line 123, immutable)`
- Writes: none
- Value: NONE
- Reachability: Pure-by-effect view called by the hook's mint pricing through a bounded one-word STATICCALL (`priceAt` CauldronHook.sol:2459), with the hook's own base and step arguments ignored by this implementation. Integer division at `knee` (MintCurvePolicy.sol:123) rounds the cost DOWN, and the units are whatever the caller's credit is denominated in - this contract performs no conversion and knows nothing about decimals.
- Edges: none
- Observations: none

### `totalToMintOut/function` — MintCurvePolicy.sol:132

- Signature: `function totalToMintOut() external view returns (uint256 total)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `supply (line 133, immutable)`; `base (line 135, immutable)`; `spread (line 135, immutable)`; `knee (line 135, immutable)`
- Writes: none
- Value: NONE
- Reachability: Off-chain calibration helper: the loop at `n` (MintCurvePolicy.sol:134) runs `supply` times, a bound fixed at deploy and reachable by anyone, so on a large collection it can exceed a block's gas - it is never called from a mint path in this repo. The only caller in the tree is the launch script in the deploy directory. Each term rounds down exactly as the per-item view does, so the sum is the sum of the actual charges.
- Edges: none
- Observations: none


## `INFTContract`

### `getHolderTaxRate/function` — INFTContract.sol:8

- Signature: `function getHolderTaxRate(address holder) external view returns (uint256)`
- Authority: declaration only (no body); the only caller in the tree is the hook's private tax helper, which is out of cluster
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Called inside a try/catch at `getHolderTaxRate` (CauldronHook.sol:1913) on a hook-configured address, so a reverting or missing implementation degrades rather than blocking a swap. Neither collection in this cluster implements it - the two ERC721s expose no such function - so the address the hook points at is some other contract. DERIVED: the identifier appears nowhere else in the tree.
- Edges: none
- Observations: none

### `balanceOf/function` — INFTContract.sol:11

- Signature: `function balanceOf(address holder) external view returns (uint256)`
- Authority: declaration only (no body); no call site exists anywhere in the tree
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declared beside the tax-rate view but never invoked through this interface: the only use of the interface type is the single tax call at `INFTContract` (CauldronHook.sol:1913). DERIVED: grep of the non-library sources finds no call of this member on this interface.
- Edges: none
- Observations: none
