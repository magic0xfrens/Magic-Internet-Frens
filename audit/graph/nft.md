# Function graph — cluster `nft`

Generated from the current `contracts/solidity` tree on 2026-09-18. Machine source: [`nft.json`](./nft.json).

Validated coverage: **167/167 nodes, 0 failures** with a fresh compiler cache.

## Files

| file | lines |
|---|---:|
| `cauldron/MiFrensGenesis.sol` | 878 |
| `cauldron/CauldronCollection.sol` | 493 |
| `cauldron/CollectionLedger.sol` | 210 |
| `cauldron/CauldronGachaRouter.sol` | 611 |
| `cauldron/GachaLib.sol` | 275 |
| `cauldron/MiFrensDividend.sol` | 603 |
| `cauldron/MintCurvePolicy.sol` | 139 |
| `cauldron/CauldronFactory.sol` | 112 |
| `cauldron/ICreatorToken.sol` | 20 |
| `interfaces/INFTContract.sol` | 13 |

## Node inventory and semantic annotations

### CauldronCollection

#### L133 `constructor`

- Declaration: `constructor( string memory name_, string memory symbol_, address minter_, address registry_, uint256 maxSupply_, MetadataMode mode_, string memory baseURI_, address renderer_, address royaltyReceiver_, uint96 royaltyBps_ ) ERC721(name_, symbol_)`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `de57477d274e2c2d294a16012099649540203f8e`
- Authority: deployer (the CauldronFactory, which becomes `configurator`)
- Gate: `UNGATED`
- Reads: LIQUIDATOR_ID_BASE (line 148, constant)
- Writes: minter (line 155, immutable);deployer (line 156, immutable);configurator (line 157, immutable);maxSupply (line 158, immutable);mode (line 159);renderer (line 160);_baseTokenURI (line 161)
- Value: NONE
- Edges: -
- Reachability: Deployment only, from the factory's `new CauldronCollection` (CauldronFactory.sol:71). Three distinct authorities are frozen here: the mint right in `minter` (CauldronCollection.sol:155), the controller in `deployer` (CauldronCollection.sol:156) - which is the registry passed in, not the caller - and the factory in `configurator` (CauldronCollection.sol:157). All four are immutable, so no gate in this file can ever be rotated or renounced. The art cap is forced below the badge range at `LIQUIDATOR_ID_BASE` (CauldronCollection.sol:148). The royalty default is installed through `_setDefaultRoyalty` (CauldronCollection.sol:162) only when a non-zero receiver is passed.
- Observation: comment at `admin` (CauldronCollection.sol:22) says there is no admin surface at all after construction; code at `setMetadata` (CauldronCollection.sol:361), `setTransferValidator` (CauldronCollection.sol:192), `setRarityOdds` (CauldronCollection.sol:486) and `setLiquidatorURI` (CauldronCollection.sol:373) are post-construction setters held by the registry

#### L169 `_update`

- Declaration: `function _update(address to, uint256 tokenId, address auth) internal override returns (address)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `bb72805d9f210b8f24d1e6908badadcfa4bdf1c5`
- Authority: internal (callers: ERC721 _mint, _burn, _transfer and the inherited public transfer entry points)
- Gate: `UNGATED`
- Reads: transferValidator (line 174)
- Writes: -
- Value: NONE
- Edges: ITransferValidator.validateTransfer (CauldronCollection.sol:176), UNTRUSTED, out-of-cluster;ERC721._update (CauldronCollection.sol:178), TRUSTED, out-of-cluster
- Reachability: The single chokepoint for every id movement: reached from `_mint` (CauldronCollection.sol:213), `_mint` (CauldronCollection.sol:416), `_burn` (CauldronCollection.sol:446), `_transfer` (CauldronCollection.sol:456) and the inherited transfer functions. When `transferValidator` (CauldronCollection.sol:174) is non-zero an arbitrary external contract is called before the state change, so a reverting validator freezes minting, burning and the registry recycle alike. Unlike the genesis collection there is no dividend ping and no everMoved bookkeeping here.

#### L182 `getTransferValidator`

- Declaration: `function getTransferValidator() external view returns (address)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `2ede13e2759297ef93349ee16002dfa39d389648`
- Authority: anyone
- Gate: `UNGATED`
- Reads: transferValidator (line 183)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View of the slot written at `transferValidator` (CauldronCollection.sol:195).

#### L187 `getTransferValidationFunction`

- Declaration: `function getTransferValidationFunction() external pure returns (bytes4 functionSignature, bool isViewFunction)`
- Kind/visibility/mutability: `function` / `external` / `pure`
- Body SHA-1: `cbc44bdf3d419823449aebcfdcd45349b7f807fe`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure constant pair; returns the selector of `validateTransfer` (CauldronCollection.sol:188) and reads no state.

#### L192 `setTransferValidator`

- Declaration: `function setTransferValidator(address validator) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `fa01b6f3209235ccf967738ac9d6dae32cbd2082`
- Authority: registry (held in the immutable `deployer` slot)
- Gate: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:193)`
- Reads: deployer (line 193, immutable);transferValidator (line 194)
- Writes: transferValidator (line 195)
- Value: NONE
- Edges: -
- Reachability: Only the registry address frozen at `deployer` (CauldronCollection.sol:156) can reach it, and that address is immutable so the right cannot be moved. Setting a non-zero value routes every move through the external check at `validateTransfer` (CauldronCollection.sol:176).

#### L199 `supportsInterface`

- Declaration: `function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `60f0cb66b5e355a6739e4972daca8d494486aa4f`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: ERC2981.supportsInterface (CauldronCollection.sol:200), TRUSTED, out-of-cluster
- Reachability: View; adds the creator-token id to the inherited answer at `supportsInterface` (CauldronCollection.sol:200).

#### L207 `mint`

- Declaration: `function mint(address to) external returns (uint256 tokenId)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `3b718bab852ceea73d617af4032007a9cf6c80a3`
- Authority: minter (the volume hook, frozen at deploy)
- Gate: `if (msg.sender != minter) revert OnlyMinter(); (CauldronCollection.sol:208)`
- Reads: minter (line 208, immutable);totalMinted (line 209);maxSupply (line 209, immutable);totalMinted (line 210)
- Writes: totalMinted (line 210);mintBlockOf (line 212)
- Value: NONE
- Edges: -
- Reachability: The only art-mint path in the collection: no public mint exists, and the caller must be the immutable `minter` (CauldronCollection.sol:208). Ids are strictly increasing from the pre-incremented `totalMinted` (CauldronCollection.sol:210) and are capped by `maxSupply` (CauldronCollection.sol:209). The token is created at `_mint` (CauldronCollection.sol:213) through the `_update` override (CauldronCollection.sol:169). Only the mint block is committed at `mintBlockOf` (CauldronCollection.sol:212); no rarity is assigned yet, so a fresh token reads as unrevealed at `revealed` (CauldronCollection.sol:471).
- Observation: comment at `Rarity` (CauldronCollection.sol:99) says the tier is rolled at mint from an on-chain seed and stored; code at `mintBlockOf` (CauldronCollection.sol:212) stores only the block and `rarityOf` (CauldronCollection.sol:315) is written later inside the reveal path

#### L219 `reveal`

- Declaration: `function reveal(uint256 tokenId) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `222c01a55377f219fea925e5f095247ea4e904fa`
- Authority: holder of token
- Gate: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (CauldronCollection.sol:256)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: CauldronCollection._reveal (CauldronCollection.sol:220), TRUSTED, in-cluster
- Reachability: Wrapper; the ownership gate is in the callee at `ownerOf` (CauldronCollection.sol:256).

#### L239 `revealBatch`

- Declaration: `function revealBatch(uint256[] calldata tokenIds) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `94cf710cfcefafe6327404306db8063334dcf706`
- Authority: holder of token
- Gate: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (CauldronCollection.sol:256)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: CauldronCollection._reveal (CauldronCollection.sol:244), TRUSTED, in-cluster
- Reachability: Batch wrapper bounded at fifty ids by the check at `BadBatch` (CauldronCollection.sol:243); every element still passes the per-token ownership gate at `ownerOf` (CauldronCollection.sol:256), so a single id the caller does not own reverts the whole batch.

#### L255 `_reveal`

- Declaration: `function _reveal(uint256 tokenId) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `403ffd12b5eeeaa5e7a6642908f45b71d707163d`
- Authority: internal (callers: reveal and revealBatch); caller must own token
- Gate: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (CauldronCollection.sol:256)`
- Reads: revealed (line 257);mintBlockOf (line 258);reanchored (line 301)
- Writes: reanchored (line 302);mintBlockOf (line 303);rarityOf (line 309);revealed (line 310)
- Value: NONE
- Edges: ERC721.ownerOf (CauldronCollection.sol:256), TRUSTED, out-of-cluster;CauldronCollection._rollRarity (CauldronCollection.sol:314), TRUSTED, in-cluster
- Reachability: Reached from single and bounded batch reveal. It rejects non-owners at `ownerOf` (CauldronCollection.sol:256) and the mint block/current block at `NotReady` (CauldronCollection.sol:259). First expiry spends the one `reanchored` flag (CauldronCollection.sol:302), rewrites the anchor, and returns. Second expiry commits base rarity and marks revealed at `revealed` (CauldronCollection.sol:310), capping withholding at two draws. A live seed commits the hash-derived rarity at `_rollRarity` (CauldronCollection.sol:314).
- Observation: The comment says a holder or keeper can retry, but the `ownerOf` gate (CauldronCollection.sol:256) excludes keepers.

#### L321 `_rollRarity`

- Declaration: `function _rollRarity(uint256 seed) private view returns (uint8)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `c0ba744222e022708acb5f76dc6666eaa837e3ef`
- Authority: internal (callers: _reveal)
- Gate: `UNGATED`
- Reads: rarityCumBps (line 324)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Called only from the reveal path at `_rollRarity` (CauldronCollection.sol:314). Walks four cumulative buckets at `rarityCumBps` (CauldronCollection.sol:324) and falls through to tier zero.

#### L331 `setVault`

- Declaration: `function setVault(address _vault) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `8774598de4ece47b9037e6ef406bbdac9b280d12`
- Authority: configurator (the factory) or registry
- Gate: `if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:332)`
- Reads: configurator (line 332, immutable);deployer (line 332, immutable);vault (line 333)
- Writes: vault (line 334)
- Value: NONE
- Edges: -
- Reachability: Write-once: a second call reverts on the non-zero `vault` (CauldronCollection.sol:333) test. The factory calls it inside `setVault` (CauldronFactory.sol:76); the registry can do it instead if the factory has not. It confers the burn right checked at `vault` (CauldronCollection.sol:445), so the burn authority is permanent once set.

#### L341 `setRoyalty`

- Declaration: `function setRoyalty(address receiver, uint96 bps) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `cc0ca21d73adac5f5ad8e320176700159a4e9ba8`
- Authority: configurator (the factory) or registry
- Gate: `if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:342)`
- Reads: configurator (line 342, immutable);deployer (line 342, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Re-settable by either holder, capped at 10 percent by the require at `bps` (CauldronCollection.sol:343). The factory uses it to point royalties at the RoyaltyRouter it just deployed, at `setRoyalty` (CauldronFactory.sol:88). The receiver lands in inherited ERC2981 storage through `_setDefaultRoyalty` (CauldronCollection.sol:344) and is never read back in this file.
- Observation: comment at `deployer` (CauldronCollection.sol:337) says the royalty receiver is re-pointable by the deployer only; code at `configurator` (CauldronCollection.sol:342) also accepts the factory

#### L351 `setLiquidatorMinter`

- Declaration: `function setLiquidatorMinter(address _minter) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `5231360fecf00f2177e81b57be4885a4fa743557`
- Authority: registry or minter (the volume hook)
- Gate: `if (msg.sender != deployer && msg.sender != minter) revert OnlyMinter(); (CauldronCollection.sol:352)`
- Reads: deployer (line 352, immutable);minter (line 352, immutable)
- Writes: liquidatorMinter (line 353)
- Value: NONE
- Edges: -
- Reachability: Both holders are immutable, so this right can neither rotate nor be renounced. It confers the only authority accepted at `liquidatorMinter` (CauldronCollection.sol:410), and it is freely re-settable, including to zero, which silently disables badge minting.

#### L361 `setMetadata`

- Declaration: `function setMetadata(MetadataMode _mode, address _renderer, string calldata baseURI_) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `677c34a0fa5396961b22751308d8f4653580485d`
- Authority: registry (held in the immutable `deployer` slot)
- Gate: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:362)`
- Reads: deployer (line 362, immutable)
- Writes: renderer (line 365);_baseTokenURI (line 367);mode (line 369)
- Value: NONE
- Edges: -
- Reachability: Registry-only. Renderer mode requires a contract with code at `_renderer` (CauldronCollection.sol:364), but the base-URI branch accepts an empty string, and only the branch that matches the new mode is written - switching to base-URI mode with an empty argument blanks `_baseTokenURI` (CauldronCollection.sol:367) for every token.
- Observation: comment at `immutable` (CauldronCollection.sol:17) says the metadata choice is immutable at deploy; code at `mode` (CauldronCollection.sol:369) lets the registry change both the mode and its source at any time

#### L373 `setLiquidatorURI`

- Declaration: `function setLiquidatorURI(string calldata uri) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `1fda3f525a500c9d1d8f825fc88e3baa08913103`
- Authority: registry (held in the immutable `deployer` slot)
- Gate: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:374)`
- Reads: deployer (line 374, immutable)
- Writes: liquidatorURI (line 375)
- Value: NONE
- Edges: -
- Reachability: Registry-only metadata base for the badge branch at `liquidatorURI` (CauldronCollection.sol:468).

#### L388 `setUnrevealedURI`

- Declaration: `function setUnrevealedURI(string calldata uri) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `950668c9adfb81589cf033bd5a3a01a35c4ec5d6`
- Authority: deployer (registry controller)
- Gate: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:389)`
- Reads: deployer (line 389, immutable)
- Writes: unrevealedURI (line 390)
- Value: NONE
- Edges: -
- Reachability: Controller-only metadata setter. It can replace the placeholder for every unrevealed art token through `unrevealedURI` (CauldronCollection.sol:390); there is no freeze or content-address validation.

#### L396 `mintLiquidator`

- Declaration: `function mintLiquidator(address to) external returns (uint256 tokenId)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `4dfec9bd3900c001a3ec3e9053abd167454948ca`
- Authority: liquidatorMinter (the wired PerpEngine)
- Gate: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:410)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: CauldronCollection._mintLiquidator (CauldronCollection.sol:397), TRUSTED, in-cluster
- Reachability: Wrapper; the gate is in the callee at `liquidatorMinter` (CauldronCollection.sol:410). The empty stats struct skips the `_liqStats` write (CauldronCollection.sol:415).

#### L402 `mintLiquidatorWithStats`

- Declaration: `function mintLiquidatorWithStats(address to, LiqStats calldata st) external returns (uint256 tokenId)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `40696ee613a4f98dbcb0e7ba1402f0197386dd75`
- Authority: liquidatorMinter (the wired PerpEngine)
- Gate: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:410)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: CauldronCollection._mintLiquidator (CauldronCollection.sol:406), TRUSTED, in-cluster
- Reachability: Same gate, in the callee at `liquidatorMinter` (CauldronCollection.sol:410); the caller's stats are stored verbatim at `_liqStats` (CauldronCollection.sol:415) with no validation.

#### L409 `_mintLiquidator`

- Declaration: `function _mintLiquidator(address to, LiqStats memory st) internal returns (uint256 tokenId)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `5de6ad6637e65838a7830f861f2d1afefb4d64bd`
- Authority: internal (callers: mintLiquidator, mintLiquidatorWithStats)
- Gate: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:410)`
- Reads: liquidatorMinter (line 410);LIQUIDATOR_ID_BASE (line 411, constant);liquidatorMinted (line 411)
- Writes: liquidatorMinted (line 411);isLiquidatoor (line 412);_liqStats (line 415)
- Value: NONE
- Edges: -
- Reachability: Badge ids are `LIQUIDATOR_ID_BASE` plus a counter (CauldronCollection.sol:411) and are uncapped: nothing here compares against `maxSupply` (CauldronCollection.sol:209), and the counter is separate from `totalMinted` (CauldronCollection.sol:210). Collision with art ids is impossible because the constructor refuses a cap at or above `LIQUIDATOR_ID_BASE` (CauldronCollection.sol:148). The token is created at `_mint` (CauldronCollection.sol:416).

#### L421 `liqStats`

- Declaration: `function liqStats(uint256 tokenId) external view returns (LiqStats memory)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `63a0e684701fc12be5d71c5237150df74bf9a9a1`
- Authority: anyone
- Gate: `UNGATED`
- Reads: _liqStats (line 422)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View of whatever the badge minter recorded at `_liqStats` (CauldronCollection.sol:415); a badge minted through the bare wrapper at `mintLiquidator` (CauldronCollection.sol:396) reads back as an all-zero struct.

#### L433 `setLiquidatorRenderer`

- Declaration: `function setLiquidatorRenderer(address r) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `ca36223bd4546d7ad6d64f0f7c93b0f57e1e127e`
- Authority: configurator (the factory) or registry
- Gate: `if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:434)`
- Reads: configurator (line 434, immutable);deployer (line 434, immutable)
- Writes: liquidatorRenderer (line 435)
- Value: NONE
- Edges: -
- Reachability: Called by the factory during deployment at `setLiquidatorRenderer` (CauldronFactory.sol:93) and thereafter by the registry. Points the badge branch of `tokenURI` (CauldronCollection.sol:466) at an arbitrary contract.

#### L439 `liquidatoorTrait`

- Declaration: `function liquidatoorTrait(uint256 tokenId) external view returns (string memory)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `aaca80625688fe68f0f354432a64c130e5cd6d78`
- Authority: anyone
- Gate: `UNGATED`
- Reads: isLiquidatoor (line 440)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View over the flag written at `isLiquidatoor` (CauldronCollection.sol:412).

#### L444 `burnFromVault`

- Declaration: `function burnFromVault(uint256 tokenId) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `f2f5866c0548ff39cdb5c0d36aa4dbbac674fd8a`
- Authority: vault
- Gate: `if (msg.sender != vault) revert OnlyVault(); (CauldronCollection.sol:445)`
- Reads: vault (line 445)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Only the address wired once at `vault` (CauldronCollection.sol:334). The burn at `_burn` (CauldronCollection.sol:446) does not decrement `totalMinted` (CauldronCollection.sol:210), so the id counter is monotonic, a burned id is never re-issued, and the live ERC721 supply falls below the counter by exactly the number of burns. DERIVED: the counter is written on one line only.

#### L454 `custodyTransfer`

- Declaration: `function custodyTransfer(address from, address to, uint256 tokenId) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `2e2a77612653e1b4acf05f3a771dd5350e6600b8`
- Authority: registry (held in the immutable `deployer` slot)
- Gate: `if (msg.sender != deployer) revert OnlyVault(); (CauldronCollection.sol:455)`
- Reads: deployer (line 455, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Registry-only move with no owner approval: `_transfer` (CauldronCollection.sol:456) only requires that `from` is the current owner, and the ownership check the comment relies on is entirely on the registry side. It routes through the `_update` override (CauldronCollection.sol:169), so a set validator can block it. Nothing is burned, so the collection size is unchanged.

#### L460 `tokenURI`

- Declaration: `function tokenURI(uint256 tokenId) public view override returns (string memory)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `2dfb7c2bd82a12d46e39fe5d7a65380291c0dc6c`
- Authority: anyone
- Gate: `UNGATED`
- Reads: isLiquidatoor (line 463);liquidatorRenderer (line 465);liquidatorURI (line 468);revealed (line 471);unrevealedURI (line 471);mode (line 472);renderer (line 473);_baseTokenURI (line 477);rarityOf (line 478)
- Writes: -
- Value: NONE
- Edges: ICollectionRenderer.tokenURI (CauldronCollection.sol:466), UNTRUSTED, out-of-cluster;ICollectionRenderer.tokenURI (CauldronCollection.sol:473), UNTRUSTED, out-of-cluster
- Reachability: View that calls out to two registry-settable contracts. Reverts for an unminted id at `_requireOwned` (CauldronCollection.sol:461). The art branch at `renderer` (CauldronCollection.sol:473) has no zero-address guard, so Renderer mode with a cleared renderer reverts for every art token, while the badge branch at `liquidatorRenderer` (CauldronCollection.sol:465) does check. Base-URI output interpolates the tier at `rarityOf` (CauldronCollection.sol:478) through `toString` (CauldronCollection.sol:480).

#### L486 `setRarityOdds`

- Declaration: `function setRarityOdds(uint16[4] calldata cum) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `1278d3b5e2884bcb75fa2fb7488df2940edb430d`
- Authority: registry (held in the immutable `deployer` slot)
- Gate: `if (msg.sender != deployer) revert OnlyMinter(); (CauldronCollection.sol:487)`
- Reads: deployer (line 487, immutable);totalMinted (line 488)
- Writes: rarityCumBps (line 490)
- Value: NONE
- Edges: -
- Reachability: Registry-only and only while `totalMinted` (CauldronCollection.sol:488) is zero, so unlike the genesis collection the odds are frozen before the first mint and cannot be changed under tokens that are already waiting to reveal. The require at `cum` (CauldronCollection.sol:489) enforces an ascending ladder ending at 10000.

### CauldronFactory

#### L36 `setLiquidatorRenderer`

- Declaration: `function setLiquidatorRenderer(address r) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `84688586f8370581d4307a52d9d7613df19d78c7`
- Authority: owner
- Gate: `if (msg.sender != owner) revert NotOwner(); (CauldronFactory.sol:37)`
- Reads: owner (line 37)
- Writes: liquidatorRenderer (line 38)
- Value: NONE
- Edges: -
- Reachability: Owner-only. The value is applied to every LATER collection the factory deploys at `liquidatorRenderer` (CauldronFactory.sol:92); collections already deployed keep whatever they were given, because the factory only holds the setter right during `deployBrew` (CauldronFactory.sol:63). DERIVED: the factory calls the collection setter only inside that function.

#### L42 `transferOwnership`

- Declaration: `function transferOwnership(address to) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `cfa084da1ee935be1765fe38e10f2f09b8b8bb23`
- Authority: owner
- Gate: `if (msg.sender != owner) revert NotOwner(); (CauldronFactory.sol:43)`
- Reads: owner (line 43)
- Writes: owner (line 44)
- Value: NONE
- Edges: -
- Reachability: Owner-only, single-step, with no zero check: passing the zero address at `to` (CauldronFactory.sol:44) permanently dead-ends the badge-renderer setter, which is the only right this owner holds. The slot is initialised to the deploying address at `owner` (CauldronFactory.sol:21).

#### L63 `deployBrew`

- Declaration: `function deployBrew(Config calldata c) external returns (address collection, address vault)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `894cfdcc2d83938988eec97ae9b33c8f96083643`
- Authority: anyone
- Gate: `UNGATED`
- Reads: liquidatorRenderer (line 92);liquidatorRenderer (line 93)
- Writes: -
- Value: No funds move; the call deploys `CauldronCollection` (CauldronFactory.sol:71), `CauldronVault` (CauldronFactory.sol:75), and `RoyaltyRouter` (CauldronFactory.sol:87) from caller-supplied configuration.
- Edges: CauldronCollection.setVault (CauldronFactory.sol:76), TRUSTED, in-cluster;CauldronCollection.setRoyalty (CauldronFactory.sol:88), TRUSTED, in-cluster;CauldronCollection.setLiquidatorRenderer (CauldronFactory.sol:93), TRUSTED, in-cluster
- Reachability: Permissionless factory entry; only the registry wires returned addresses into protocol state. The collection controller is caller-supplied `registry` (CauldronFactory.sol:72), not msg.sender. This factory acquires and immediately spends collection configurator rights at `setVault` (CauldronFactory.sol:76), `setRoyalty` (CauldronFactory.sol:88), and optional renderer wiring. The royalty router freezes the caller-supplied hook plus `royaltyReceiver` (CauldronFactory.sol:87), making the latter the ERC20 royalty sink.

#### L105 `deployVault`

- Declaration: `function deployVault(address collection, address registry, uint256 floorOffset) external returns (address vault)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `8460a525d1413a8e24449a3d8854a1a97c4522b4`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: no native or token value moves; the call is a DEPLOYMENT - it runs the `CauldronVault` (CauldronFactory.sol:109) constructor with the collection, registry and floor offset the caller named, and funds it with nothing.
- Edges: -
- Reachability: UNGATED and stateless: it returns a new vault bound to the collection and registry the caller names at `CauldronVault` (CauldronFactory.sol:109), so anyone can create an unwired vault for any collection - it confers nothing, because the collection only honours the vault its own `setVault` recorded. The protocol caller is the registry at `deployVault` (CauldronRegistry.sol:1255), which passes a non-zero floor offset for a continued collection.

### ICauldronHookGacha (declared in CauldronGachaRouter.sol)

#### L15 `commitCrystals`

- Declaration: `function commitCrystals(address player, uint256 maxCount, uint256 playWei) external returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster callers are _play, openReady and playChurn, all reachable by anyone; the hook holds its own gate
- Gate: `if (_locked != 1) revert Reentrancy(); (CauldronGachaRouter.sol:179)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Called at `commitCrystals` (CauldronGachaRouter.sol:328), `commitCrystals` (CauldronGachaRouter.sol:362) and `commitCrystals` (CauldronGachaRouter.sol:398). The router always passes `msg.sender` as the player, so it cannot credit a third party, and the size argument is whatever the router computed - a raw notional on the swap paths and a curve-unit figure on the ready path. The implementation and its authority check are out of cluster.

#### L16 `resolveTickets`

- Declaration: `function resolveTickets(uint256 maxCount) external returns (uint256, uint256)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster callers are _play, openReady and playChurn
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Called immediately after each commit at `resolveTickets` (CauldronGachaRouter.sol:329), `resolveTickets` (CauldronGachaRouter.sol:363) and `resolveTickets` (CauldronGachaRouter.sol:399), always bounded by the constant at `MAX_MINTS_PER_CALL` (CauldronGachaRouter.sol:329). Its return value is discarded on every call site.

#### L17 `crystalsReady`

- Declaration: `function crystalsReady(address player) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is openReady
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read once per call at `crystalsReady` (CauldronGachaRouter.sol:348) to size the batch, then clamped by the router.

#### L18 `costOfNextCrystals`

- Declaration: `function costOfNextCrystals(uint256 count) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is openReady
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read at `costOfNextCrystals` (CauldronGachaRouter.sol:353); its result is treated as already being in the hook's curve unit and is divided by the buy weight to produce the play size at `playWei` (CauldronGachaRouter.sol:355).

#### L19 `buyWeightBps`

- Declaration: `function buyWeightBps() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is openReady
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read at `buyWeightBps` (CauldronGachaRouter.sol:354); a zero answer makes the router pass the raw credit through unscaled at `creditToOpen` (CauldronGachaRouter.sol:355).

### IRegistryCurrent (declared in CauldronGachaRouter.sol)

#### L23 `currentToken`

- Declaration: `function currentToken() external view returns (address)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is _key
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read on every swap path through `currentToken` (CauldronGachaRouter.sol:220) to build currency1 of the pool key, so the router follows the live generation with no rewiring.

#### L25 `currentGeneration`

- Declaration: `function currentGeneration() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is _quote
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read at `currentGeneration` (CauldronGachaRouter.sol:207) purely to index the quote lookup.

#### L29 `generationQuote`

- Declaration: `function generationQuote(uint256 gen) external view returns (address)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is _quote
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read at `generationQuote` (CauldronGachaRouter.sol:207). Its answer decides both the currency0 of the key at `_quote` (CauldronGachaRouter.sol:219) and, through the zero test, whether the router settles native or ERC20 at `isNative` (CauldronGachaRouter.sol:425).

### IQuoteOracleView (declared in CauldronGachaRouter.sol)

#### L37 `usdPerRawUnit`

- Declaration: `function usdPerRawUnit(address quote) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is _playInCurveUnits
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Called inside a try/catch at `usdPerRawUnit` (CauldronGachaRouter.sol:139) on an owner-settable address. A revert or a zero answer both fall back to the unconverted size at `playWei` (CauldronGachaRouter.sol:143), so the oracle can only ever reduce a player's odds, never block the play.

### CauldronGachaRouter

#### L99 `setOracle`

- Declaration: `function setOracle(address _oracle) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `8819c58ad7642f3df9464b79825c73c01194cfa3`
- Authority: owner
- Gate: `external onlyOwner (CauldronGachaRouter.sol:99)`
- Reads: -
- Writes: oracle (line 100)
- Value: NONE
- Edges: -
- Reachability: Owner-only, freely re-settable, no zero check and no code check: the address lands in `oracle` (CauldronGachaRouter.sol:100) and is then called on every swap-path play at `usdPerRawUnit` (CauldronGachaRouter.sol:139). The owner slot is the OZ Ownable one, so it can also be transferred or renounced from outside this file.

#### L120 `playInCurveUnits`

- Declaration: `function playInCurveUnits(uint256 playWei) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `f46ec74d7889a40dc730e9d9f6cc55e69e717ea8`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: CauldronGachaRouter._playInCurveUnits (CauldronGachaRouter.sol:121), TRUSTED, in-cluster
- Reachability: View wrapper so a frontend can display the same number the chain will roll at `_playInCurveUnits` (CauldronGachaRouter.sol:328).

#### L136 `_playInCurveUnits`

- Declaration: `function _playInCurveUnits(uint256 playWei) internal view returns (uint256)`
- Kind/visibility/mutability: `function` / `internal` / `view`
- Body SHA-1: `29fc2b9ef32530cfb670a5f8eb45b0989962d972`
- Authority: internal (callers: playInCurveUnits, _play, playChurn)
- Gate: `UNGATED`
- Reads: oracle (line 137)
- Writes: -
- Value: NONE
- Edges: IQuoteOracleView.usdPerRawUnit (CauldronGachaRouter.sol:139), UNTRUSTED, in-cluster;CauldronGachaRouter._quote (CauldronGachaRouter.sol:139), TRUSTED, in-cluster
- Reachability: With `oracle` (CauldronGachaRouter.sol:137) unset the size passes through unchanged. Otherwise the raw size is multiplied by the oracle's factor and divided by 1e18 at `f` (CauldronGachaRouter.sol:141), so the result is only in the hook's unit if the oracle's scaling matches; the quote asked for is the generation's own quote at `_quote` (CauldronGachaRouter.sol:139), not native ETH. Rounds down, and a zero factor is treated as `cannot judge` (CauldronGachaRouter.sol:140).

#### L179 `nonReentrant`

- Declaration: `modifier nonReentrant()`
- Kind/visibility/mutability: `modifier` / `-` / `nonpayable`
- Body SHA-1: `1c7a0e6192e769f914da806e29ee59776a85059f`
- Authority: internal (callers: play, playLiq, openReady, playChurn)
- Gate: `if (_locked != 1) revert Reentrancy(); (CauldronGachaRouter.sol:180)`
- Reads: _locked (line 180)
- Writes: _locked (line 181);_locked (line 183)
- Value: NONE
- Edges: -
- Reachability: Wraps all four external entry points. It is NOT applied to `unlockCallback` (CauldronGachaRouter.sol:409), which is reached re-entrantly from the pool manager while the flag is already set, so the guard admits that one nested frame by design.

#### L186 `constructor`

- Declaration: `constructor(IPoolManager _poolManager, address _hook, address _registry, address _owner) Ownable(_owner)`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `0e9f47de60f7453f83e4db67ea5538d141884e30`
- Authority: deployer
- Gate: `UNGATED`
- Reads: -
- Writes: poolManager (line 189, immutable);hook (line 190, immutable);hookAddr (line 191, immutable);registry (line 192, immutable)
- Value: NONE
- Edges: -
- Reachability: Deployment only, with no zero checks on any of the four wired addresses. All four are immutable, so the pool manager, hook and registry cannot be re-pointed; only `oracle` (CauldronGachaRouter.sol:100) and the OZ owner are mutable afterwards. The owner comes from the constructor argument at `Ownable` (CauldronGachaRouter.sol:187).

#### L206 `_quote`

- Declaration: `function _quote() internal view returns (address)`
- Kind/visibility/mutability: `function` / `internal` / `view`
- Body SHA-1: `9340051c881d052a412b6eb73a37000d74e3742c`
- Authority: internal (callers: _key, _playInCurveUnits, playChurn)
- Gate: `UNGATED`
- Reads: registry (line 207, immutable)
- Writes: -
- Value: NONE
- Edges: IRegistryCurrent.generationQuote (CauldronGachaRouter.sol:207), TRUSTED, in-cluster;IRegistryCurrent.currentGeneration (CauldronGachaRouter.sol:207), TRUSTED, in-cluster
- Reachability: Two chained registry views on every call. The answer is re-read per call rather than cached, so a rotation that rewrites the generation's quote changes which asset `_pullQuote` (CauldronGachaRouter.sol:273) demands from the very next caller, and a play that is in flight in the same block can be pointed at a different pool than the sender expected. DERIVED: nothing in this file stores the quote.

#### L217 `_key`

- Declaration: `function _key() internal view returns (PoolKey memory)`
- Kind/visibility/mutability: `function` / `internal` / `view`
- Body SHA-1: `48405c31fb76adcadb3b1bb9e39bab71b2583198`
- Authority: internal (callers: _play, unlockCallback, _churn)
- Gate: `UNGATED`
- Reads: POOL_FEE (line 221, constant);TICK_SPACING (line 222, constant);hookAddr (line 223, immutable);registry (line 220, immutable)
- Writes: -
- Value: NONE
- Edges: CauldronGachaRouter._quote (CauldronGachaRouter.sol:219), TRUSTED, in-cluster;IRegistryCurrent.currentToken (CauldronGachaRouter.sol:220), TRUSTED, in-cluster
- Reachability: Rebuilds the pool key from live registry state on every entry. The quote is placed in currency0 at `_quote` (CauldronGachaRouter.sol:219) and the iteration token in currency1 at `currentToken` (CauldronGachaRouter.sol:220) with no comparison between the two addresses, so the ordering rests entirely on the registry's own admission rule.
- Observation: comment at `currency0` (CauldronGachaRouter.sol:212) states as an invariant that the quote always sorts into currency0; code at `Currency` (CauldronGachaRouter.sol:219) assigns the two currencies by role and never compares the addresses, so the property is enforced elsewhere, not here

#### L235 `play`

- Declaration: `function play(uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax) external payable nonReentrant returns (uint256 opened)`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `a9bbaab569e7544f461b64b6da64869da376a09f`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: receives native when the generation's quote is native - declared `payable` (line 237)
- Edges: CauldronGachaRouter._play (CauldronGachaRouter.sol:241), TRUSTED, in-cluster
- Reachability: Permissionless entry point guarded by `nonReentrant` (CauldronGachaRouter.sol:238). Passes an empty hint array, so no perp liquidation is attempted at `_play` (CauldronGachaRouter.sol:241).

#### L250 `playLiq`

- Declaration: `function playLiq( uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax, uint256[] calldata liqHints ) external payable nonReentrant returns (uint256 opened)`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `953290286489315e6d2becae3ff659da49bb049a`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: receives native when the generation's quote is native - declared `payable` (line 259)
- Edges: CauldronGachaRouter._play (CauldronGachaRouter.sol:263), TRUSTED, in-cluster
- Reachability: Same permissionless path as the plain play, guarded by `nonReentrant` (CauldronGachaRouter.sol:260); the caller-supplied hint list is forwarded untouched into the swap's hookData at `liqHints` (CauldronGachaRouter.sol:419). The array is unbounded here - only the hook limits how many hints it will process. DERIVED: no length check exists in this file.

#### L273 `_pullQuote`

- Declaration: `function _pullQuote(address q, uint256 quoteIn) private returns (uint256)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `7ebdadd6bf7341ab85b52fa2dbbdaede66394aa1`
- Authority: internal (callers: _play, playChurn)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: receives native `msg.value` on the native branch (line 276); ERC20 pull of `q` from the caller into this router (line 279)
- Edges: CauldronGachaRouter._safeTransferFrom (CauldronGachaRouter.sol:279), TRUSTED, in-cluster
- Reachability: Enforces exactly one funding form: value with no `quoteIn` (CauldronGachaRouter.sol:275) when the quote is native, or an allowance pull with no value at `msg.value` (CauldronGachaRouter.sol:278) otherwise. It returns the REQUESTED amount at `quoteIn` (CauldronGachaRouter.sol:280) rather than a measured balance delta, so a fee-on-transfer quote would credit the player more than actually arrived. DERIVED: no balance is read before or after the pull.

#### L283 `_play`

- Declaration: `function _play( uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax, uint256[] memory liqHints ) internal returns (uint256 opened)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `a56944d67e9e13e8aee41237ee40f2edc28fdca5`
- Authority: internal (callers: play, playLiq)
- Gate: `UNGATED`
- Reads: poolManager (line 303, immutable);hook (line 328, immutable);MAX_MINTS_PER_CALL (line 329, constant)
- Writes: -
- Value: ERC20 pull of the iteration token from the caller at `_safeTransferFrom` (line 300); ERC20 refund of the unused token to `msg.sender` (line 333); quote paid back to `msg.sender` (line 340)
- Edges: CauldronGachaRouter._key (CauldronGachaRouter.sol:294), TRUSTED, in-cluster;CauldronGachaRouter._pullQuote (CauldronGachaRouter.sol:296), TRUSTED, in-cluster;CauldronGachaRouter._safeTransferFrom (CauldronGachaRouter.sol:300), TRUSTED, in-cluster;IPoolManager.unlock (CauldronGachaRouter.sol:303), TRUSTED, out-of-cluster;ICauldronHookGacha.commitCrystals (CauldronGachaRouter.sol:328), UNTRUSTED, in-cluster;CauldronGachaRouter._playInCurveUnits (CauldronGachaRouter.sol:328), TRUSTED, in-cluster;ICauldronHookGacha.resolveTickets (CauldronGachaRouter.sol:329), UNTRUSTED, in-cluster;CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:333), TRUSTED, in-cluster;CauldronGachaRouter._payQuote (CauldronGachaRouter.sol:340), TRUSTED, in-cluster
- Reachability: Body of both public play paths. It pulls the two inputs, then enters the pool manager through `unlock` (CauldronGachaRouter.sol:303), which calls back into `unlockCallback` (CauldronGachaRouter.sol:409) where the swaps run. Slippage on the sell leg is checked only when something was sold, at `sellEthGross` (CauldronGachaRouter.sol:320); the buy leg's minimum is enforced inside the callback instead. The gacha commit and resolve happen before any payout, so the two token sends at `_safeTransfer` (CauldronGachaRouter.sol:333) and `_payQuote` (CauldronGachaRouter.sol:340) are the last actions and the hook cannot be re-entered through a hostile recipient while state is half-written. The play size reported to the hook is the ETH-equivalent notional `playWei` (CauldronGachaRouter.sol:324), converted for the curve, while the event reports the raw notional.

#### L347 `openReady`

- Declaration: `function openReady(uint256 maxCount) external nonReentrant returns (uint256 opened)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `e491050c810f7fc7e45494393e403e448bb3e031`
- Authority: anyone
- Gate: `UNGATED`
- Reads: hook (line 348, immutable);MAX_MINTS_PER_CALL (line 349, constant)
- Writes: -
- Value: NONE
- Edges: ICauldronHookGacha.crystalsReady (CauldronGachaRouter.sol:348), UNTRUSTED, in-cluster;ICauldronHookGacha.costOfNextCrystals (CauldronGachaRouter.sol:353), UNTRUSTED, in-cluster;ICauldronHookGacha.buyWeightBps (CauldronGachaRouter.sol:354), UNTRUSTED, in-cluster;ICauldronHookGacha.commitCrystals (CauldronGachaRouter.sol:362), UNTRUSTED, in-cluster;ICauldronHookGacha.resolveTickets (CauldronGachaRouter.sol:363), UNTRUSTED, in-cluster
- Reachability: Permissionless and payment-free: it opens crystals the caller already earned, clamped to the constant at `MAX_MINTS_PER_CALL` (CauldronGachaRouter.sol:349) and to the caller's own `maxCount` (CauldronGachaRouter.sol:350), and returns early when nothing is ready at `ready` (CauldronGachaRouter.sol:351). No value moves in this function at all; the size handed to the hook is derived from the hook's own curve at `creditToOpen` (CauldronGachaRouter.sol:355) and is deliberately not passed through the oracle conversion.

#### L379 `playChurn`

- Declaration: `function playChurn(uint256 quoteIn, uint256 loops, uint256 minTokenOut, uint256 openMax) external payable nonReentrant returns (uint256 opened)`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `4eb80f226f2febe417ae29150f562fb3cbb2ca80`
- Authority: anyone
- Gate: `UNGATED`
- Reads: MAX_LOOPS (line 388, constant);poolManager (line 390, immutable);hook (line 398, immutable);MAX_MINTS_PER_CALL (line 399, constant)
- Writes: -
- Value: receives native when native quote is selected; refunds residual quote through `_payQuote` (line 401)
- Edges: CauldronGachaRouter._quote (CauldronGachaRouter.sol:385), TRUSTED, in-cluster;CauldronGachaRouter._pullQuote (CauldronGachaRouter.sol:386), TRUSTED, in-cluster;IPoolManager.unlock (CauldronGachaRouter.sol:390), TRUSTED, out-of-cluster;ICauldronHookGacha.commitCrystals (CauldronGachaRouter.sol:398), UNTRUSTED, in-cluster;CauldronGachaRouter._playInCurveUnits (CauldronGachaRouter.sol:398), TRUSTED, in-cluster;ICauldronHookGacha.resolveTickets (CauldronGachaRouter.sol:399), UNTRUSTED, in-cluster;CauldronGachaRouter._payQuote (CauldronGachaRouter.sol:401), TRUSTED, in-cluster
- Reachability: Permissionless and nonReentrant. It pulls quote before enforcing the 1-to-10 loop bound, but any revert unwinds the pull. The pool-manager unlock carries player, spend, loop count, and `minTokenOut` at `unlock` (CauldronGachaRouter.sol:390). After callback settlement it converts aggregate notional for odds, commits/resolves, refunds residual quote, and emits. A zero `minTokenOut` deliberately disables final token slippage protection.

#### L409 `unlockCallback`

- Declaration: `function unlockCallback(bytes calldata raw) external returns (bytes memory)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `f38629bcb6a78fb7a905fdc4c2021bed0ca3fdd5`
- Authority: poolManager (re-entered during unlock)
- Gate: `if (msg.sender != address(poolManager)) revert NotPoolManager(); (CauldronGachaRouter.sol:410)`
- Reads: poolManager (line 410, immutable);poolManager (line 433, immutable);poolManager (line 447, immutable)
- Writes: -
- Value: the pool manager pays the swap output to the player at `_take` (line 442); the sell output is taken to this router at `_take` (line 455)
- Edges: CauldronGachaRouter._churn (CauldronGachaRouter.sol:412), TRUSTED, in-cluster;CauldronGachaRouter._key (CauldronGachaRouter.sol:415), TRUSTED, in-cluster;IPoolManager.swap (CauldronGachaRouter.sol:433), TRUSTED, out-of-cluster;CauldronGachaRouter._limit (CauldronGachaRouter.sol:435), TRUSTED, in-cluster;CauldronGachaRouter._settle (CauldronGachaRouter.sol:441), TRUSTED, in-cluster;CauldronGachaRouter._take (CauldronGachaRouter.sol:442), TRUSTED, in-cluster;IPoolManager.swap (CauldronGachaRouter.sol:447), TRUSTED, out-of-cluster;CauldronGachaRouter._settle (CauldronGachaRouter.sol:454), TRUSTED, in-cluster;CauldronGachaRouter._take (CauldronGachaRouter.sol:455), TRUSTED, in-cluster
- Reachability: Only the pool manager can enter, and only while one of the four entry points holds the lock; the caller check at `poolManager` (CauldronGachaRouter.sol:410) is the whole gate, and the payload is trusted because the manager echoes back exactly what the router encoded. The key is rebuilt here at `_key` (CauldronGachaRouter.sol:415) rather than passed in, so a mid-transaction registry change would swap the pool between the outer call and this frame. Buy-leg slippage is enforced at `outAmount` (CauldronGachaRouter.sol:439); the sell leg has no minimum here and is checked by the caller instead. The swap's hookData carries the player and the hint list at `hookData` (CauldronGachaRouter.sol:419), so volume is credited to the player rather than to the router. Price limits come from the extreme constants at `_limit` (CauldronGachaRouter.sol:435), i.e. the pool bounds, not a price the caller chose.

#### L462 `_churn`

- Declaration: `function _churn(ChurnData memory c) private returns (bytes memory)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `285575947a31ef02e4713b53878d8fff5dc485df`
- Authority: private (single caller: unlockCallback tag 1)
- Gate: `UNGATED`
- Reads: poolManager (line 478, immutable);poolManager (line 504, immutable)
- Writes: -
- Value: Each buy settles quote and takes token at `_settle` (line 485) and `_take` (line 486); each sell reverses those flows at `_settle` (line 511) and `_take` (line 512); final token is transferred to `player` (line 529)
- Edges: CauldronGachaRouter._key (CauldronGachaRouter.sol:463), TRUSTED, in-cluster;IPoolManager.swap (CauldronGachaRouter.sol:478), TRUSTED, out-of-cluster;CauldronGachaRouter._limit (CauldronGachaRouter.sol:480), TRUSTED, in-cluster;CauldronGachaRouter._settle (CauldronGachaRouter.sol:485), TRUSTED, in-cluster;CauldronGachaRouter._take (CauldronGachaRouter.sol:486), TRUSTED, in-cluster;IPoolManager.swap (CauldronGachaRouter.sol:504), TRUSTED, out-of-cluster;CauldronGachaRouter._settle (CauldronGachaRouter.sol:511), TRUSTED, in-cluster;CauldronGachaRouter._take (CauldronGachaRouter.sol:512), TRUSTED, in-cluster;CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:529), TRUSTED, in-cluster
- Reachability: Runs only during a pool-manager unlock dispatched by tag 1. The loop bound was checked by `playChurn`. Both exact-input legs debit actual consumed amounts at `ethBal` (CauldronGachaRouter.sol:501) and `tokBal` (CauldronGachaRouter.sol:519), preserving partial-fill remainders. The last iteration ends after a buy; final retained token is checked against `minTokenOut` (CauldronGachaRouter.sol:528) before transfer, and residual quote is returned to the caller as encoded `ethBal` (CauldronGachaRouter.sol:530).

#### L533 `_limit`

- Declaration: `function _limit(bool zeroForOne) private pure returns (uint160)`
- Kind/visibility/mutability: `function` / `private` / `pure`
- Body SHA-1: `dc805e20c93fe65f7d2d721ee36478912fed8feb`
- Authority: internal (callers: unlockCallback, _churn)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure constants returned at `zeroForOne` (CauldronGachaRouter.sol:534): the minimum and maximum usable square-root prices, i.e. no price limit at all. Every swap in the file uses them, so the callers rely on explicit minimum-output checks instead.

#### L537 `_settle`

- Declaration: `function _settle(Currency currency, uint256 amount, bool isNative) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `148eacaece7452442349be0c958dd5e04aac7c7d`
- Authority: internal (callers: unlockCallback, _churn)
- Gate: `UNGATED`
- Reads: poolManager (line 539, immutable);poolManager (line 541, immutable);poolManager (line 542, immutable);poolManager (line 543, immutable)
- Writes: -
- Value: sends native to the pool manager at `settle` (line 539); on the ERC20 branch the manager's balance is synced at `sync` (line 541), the token is pushed to it at `_safeTransfer` (line 542) and the debt is closed at `settle` (line 543)
- Edges: IPoolManager.settle (CauldronGachaRouter.sol:539), TRUSTED, out-of-cluster;IPoolManager.sync (CauldronGachaRouter.sol:541), TRUSTED, out-of-cluster;CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:542), TRUSTED, in-cluster;IPoolManager.settle (CauldronGachaRouter.sol:543), TRUSTED, out-of-cluster
- Reachability: Two settlement shapes selected by the `isNative` flag the caller computed (CauldronGachaRouter.sol:538): value-bearing settle for native, or sync then transfer then settle for an ERC20 quote. The native branch spends this contract's balance, which includes anything the open `receive` (CauldronGachaRouter.sol:609) has accumulated, not only the current caller's value. DERIVED: the function takes an amount, not a per-caller accounting entry.

#### L547 `_take`

- Declaration: `function _take(Currency currency, address to, uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `110688771df6319f7fb550556051fbe582c8bee5`
- Authority: internal (callers: unlockCallback, _churn)
- Gate: `UNGATED`
- Reads: poolManager (line 548, immutable)
- Writes: -
- Value: the pool manager pays `to` at `take` (line 548)
- Edges: IPoolManager.take (CauldronGachaRouter.sol:548), TRUSTED, out-of-cluster
- Reachability: Zero-amount no-op at `amount` (CauldronGachaRouter.sol:548). The destination is either the player directly or this router, chosen by each call site.

#### L557 `_payQuote`

- Declaration: `function _payQuote(address q, address to, uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `ca2f7616c6576871eb6c40fc9712191605eacd9c`
- Authority: internal (callers: _play, playChurn)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: sends native to `to` (line 560); ERC20 sent to `to` at `_safeTransfer` (line 563)
- Edges: to.call (CauldronGachaRouter.sol:560), UNTRUSTED, out-of-cluster;CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:563), TRUSTED, in-cluster
- Reachability: Pays the player back in whatever the generation's quote is. The native branch forwards all remaining gas to an arbitrary recipient at `call` (CauldronGachaRouter.sol:560); it is only ever reached after the gacha state has already been committed, and every caller is wrapped by the guard at `_locked` (CauldronGachaRouter.sol:180). A rejecting recipient reverts the whole play at `RefundFailed` (CauldronGachaRouter.sol:561) rather than losing the refund.

#### L567 `_safeTransfer`

- Declaration: `function _safeTransfer(address token, address to, uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `e176d5f47c66e0115b9c20aae1600a4738364b70`
- Authority: internal (callers: _play, _churn, _settle, _payQuote)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: ERC20 transfer of `token` to `to` (line 569)
- Edges: token.call (CauldronGachaRouter.sol:569), UNTRUSTED, out-of-cluster
- Reachability: Raw call with a decoded-boolean check at `data` (CauldronGachaRouter.sol:570), so both standard and non-standard ERC20s are handled. The token address always comes from the pool key or the generation quote, never directly from a caller argument. DERIVED: every call site passes a currency unwrapped from the key or the quote.

#### L573 `_safeTransferFrom`

- Declaration: `function _safeTransferFrom(address token, address from, address to, uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `bce748b50cafac4d9bdc0d276488ca5afd5f3af4`
- Authority: internal (callers: _pullQuote, _play)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: ERC20 transferFrom of `token` from `from` to `to` (line 575)
- Edges: token.call (CauldronGachaRouter.sol:575), UNTRUSTED, out-of-cluster
- Reachability: Pulls the caller's quote or token using the router's allowance; the same decoded-boolean check at `data` (CauldronGachaRouter.sol:576) applies. Both call sites pass `msg.sender` as the source, so the allowance cannot be spent on behalf of a third party. DERIVED: the two call sites are the pull at `_safeTransferFrom` (CauldronGachaRouter.sol:279) and the one at `_safeTransferFrom` (CauldronGachaRouter.sol:300).

#### L579 `rescueETH`

- Declaration: `function rescueETH(address to, uint256 amount) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `cab006e3f0acb6d2e4ffe44268d5ebdc5ef60b26`
- Authority: owner
- Gate: `external onlyOwner (CauldronGachaRouter.sol:579)`
- Reads: -
- Writes: -
- Value: sends native to `to` (line 580)
- Edges: to.call (CauldronGachaRouter.sol:580), UNTRUSTED, out-of-cluster
- Reachability: Owner-only sweep of the contract's native balance to any address, with no accounting and no cap: it can move value that arrived through the open `receive` (CauldronGachaRouter.sol:609) or any native dust left by a settlement. It has no reentrancy guard, but it holds no per-user accounting to corrupt. DERIVED: the router stores no per-player balances.

#### L592 `rescueToken`

- Declaration: `function rescueToken(address token, address to, uint256 amount) external onlyOwner`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `41c782ae09d5aca899bc30acb09eb242325d9025`
- Authority: owner
- Gate: `external onlyOwner (CauldronGachaRouter.sol:592)`
- Reads: -
- Writes: -
- Value: sends `amount` of an arbitrary ERC20 to `to` (line 593)
- Edges: CauldronGachaRouter._safeTransfer (CauldronGachaRouter.sol:593), TRUSTED, in-cluster
- Reachability: Owner-gated ERC20 counterpart to `rescueETH` (CauldronGachaRouter.sol:579), added because recovery was one-sided: a native generation's stranded quote could be swept while an ERC20 generation's could not be moved at all. It routes through the checked `_safeTransfer` (CauldronGachaRouter.sol:593), so a token that returns false reverts rather than reporting a successful rescue. The router holds no balance between transactions by design - every leg sweeps to the player before the call returns, e.g. at `_safeTransfer` (CauldronGachaRouter.sol:529) - so what this can reach is dust and value stranded by a bug (DERIVED). There is no allowlist on `token`, and no accounting separating a player's in-flight funds from dust, so the owner may move any ERC20 balance the router holds at that instant (DERIVED).

#### L605 `renounceOwnership`

- Declaration: `function renounceOwnership() public pure override`
- Kind/visibility/mutability: `function` / `public` / `pure`
- Body SHA-1: `3811e82976dafcadd631a6a38b558f29702a2f65`
- Authority: anyone by ABI - it always reverts
- Gate: `function renounceOwnership() public pure override { (CauldronGachaRouter.sol:605)`
- Reads: -
- Writes: -
- Value: none - it reverts (DERIVED)
- Edges: -
- Reachability: Disables OpenZeppelin's live renounce by reverting `OwnershipCannotBeRenounced` (CauldronGachaRouter.sol:606); `pure` and ungated, so any caller reaches it and it always reverts (DERIVED). The owner surface it protects is entirely recovery and repair: `rescueETH` (CauldronGachaRouter.sol:579), `rescueToken` (CauldronGachaRouter.sol:592) and the oracle re-point at `oracle` (CauldronGachaRouter.sol:94), so renouncing would permanently seal the only exits for stranded value (DERIVED).

#### L609 `receive`

- Declaration: `receive() external payable`
- Kind/visibility/mutability: `receive` / `-` / `payable`
- Body SHA-1: `da39a3ee5e6b4b0d3255bfef95601890afd80709`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: receives native - declared `payable` (line 609)
- Edges: -
- Reachability: Open and empty, so any address can push ETH in. Such a balance is indistinguishable from a player's value once inside, and it is spendable by the native settle branch at `settle` (CauldronGachaRouter.sol:539) and by the owner at `rescueETH` (CauldronGachaRouter.sol:579).

### CollectionLedger

#### L76 `constructor`

- Declaration: `constructor(address _registry)`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `c910907f34fa15f1ae969dec196fa1327e0dd3e0`
- Authority: deployer
- Gate: `UNGATED`
- Reads: -
- Writes: registry (line 78, immutable)
- Value: NONE
- Edges: -
- Reachability: Deployment only. `registry` (CollectionLedger.sol:78) is immutable and non-zero, so the single authority over this cap table is fixed at deploy and can never be rotated, renounced or dead-ended.

#### L81 `onlyRegistry`

- Declaration: `modifier onlyRegistry()`
- Kind/visibility/mutability: `modifier` / `-` / `nonpayable`
- Body SHA-1: `9fc52a1474bebaa55e587b54813691f8e77da6c9`
- Authority: internal (callers: credit, redeem, buyback, crystallize)
- Gate: `if (msg.sender != registry) revert OnlyRegistry(); (CollectionLedger.sol:82)`
- Reads: registry (line 82, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: The only gate in the file, applied to `credit` (CollectionLedger.sol:146), `redeem` (CollectionLedger.sol:161), `buyback` (CollectionLedger.sol:174) and `crystallize` (CollectionLedger.sol:187). Every number in this contract is therefore whatever the registry asserts; the ledger holds no tokens and verifies nothing against a balance.

#### L90 `outstanding`

- Declaration: `function outstanding(uint256 gen, uint256 mintedNow) public view returns (uint256)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `4c00f3923544658e184c18951deefa470e51b6ff`
- Authority: anyone
- Gate: `UNGATED`
- Reads: crystallized (line 91);frozenSupply (line 91);retired (line 92)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure view. Before death the supply term is the caller-supplied `mintedNow` argument (CollectionLedger.sol:91) rather than anything this contract can verify; after `crystallized` (CollectionLedger.sol:91) is set it switches to the snapshot in `frozenSupply` (CollectionLedger.sol:91). Saturates at zero at `supply` (CollectionLedger.sol:93) so retired can exceed supply without reverting.

#### L98 `floorPerNFT`

- Declaration: `function floorPerNFT(uint256 gen, uint256 mintedNow) public view returns (uint256)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `74488ede4b41ffaa05671cadc83a6ae796d91e93`
- Authority: anyone
- Gate: `UNGATED`
- Reads: entitledTokens (line 101)
- Writes: -
- Value: NONE
- Edges: CollectionLedger.outstanding (CollectionLedger.sol:99), TRUSTED, in-cluster
- Reachability: Pure view; integer division at `entitledTokens` (CollectionLedger.sol:101) rounds the per-NFT floor DOWN, and returns zero when `n` (CollectionLedger.sol:100) is zero instead of dividing by zero.

#### L120 `isDeadEnd`

- Declaration: `function isDeadEnd(uint256 gen) public view returns (bool)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `eb3678b86196488b39e94bc910a569a974edc2d7`
- Authority: anyone
- Gate: `UNGATED`
- Reads: crystallized (line 121);frozenSupply (line 121);retired (line 121)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Public view. It reports a permanent no-claimant state only after crystallization, when frozen supply is no greater than retired count at `frozenSupply` (CollectionLedger.sol:121). Alive zero-outstanding states are excluded because later mints can reopen them.

#### L146 `credit`

- Declaration: `function credit(uint256 gen, uint256 tokens) external onlyRegistry`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `97ff903eedf0ac8828f614d364cfd814c6f5250e`
- Authority: registry
- Gate: `external onlyRegistry (CollectionLedger.sol:146)`
- Reads: entitledTokens (line 152)
- Writes: entitledTokens (line 152);totalEntitled (line 153)
- Value: NONE
- Edges: CollectionLedger.isDeadEnd (CollectionLedger.sol:148), TRUSTED, in-cluster
- Reachability: Registry-only. Zero credit reverts. A permanently retired generation is detected at `isDeadEnd` (CollectionLedger.sol:148), emits rejection, and returns without increasing liabilities; the already-held token remains reserve surplus. Otherwise generation and global counters increase equally at `totalEntitled` (CollectionLedger.sol:153).

#### L161 `redeem`

- Declaration: `function redeem(uint256 gen, uint256 mintedNow) external onlyRegistry returns (uint256 payout)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `53a40a3e8fe7a3e7e1941f0e7b1df4330504da40`
- Authority: registry
- Gate: `external onlyRegistry (CollectionLedger.sol:161)`
- Reads: entitledTokens (line 164);retired (line 166)
- Writes: entitledTokens (line 165);retired (line 166);totalEntitled (line 167)
- Value: NONE
- Edges: CollectionLedger.outstanding (CollectionLedger.sol:162), TRUSTED, in-cluster;CollectionLedger.floorPerNFT (CollectionLedger.sol:168), TRUSTED, in-cluster
- Reachability: Registry-only. Pays one NFT's share, computed by the same rounding-down division as the view at `payout` (CollectionLedger.sol:164), then debits both counters by exactly that amount at `entitledTokens` (CollectionLedger.sol:165) and `totalEntitled` (CollectionLedger.sol:167) and increments `retired` (CollectionLedger.sol:166). The rounding remainder stays in the pot, so the per-NFT floor of the survivors can only rise. Reverts when nothing is outstanding at `n` (CollectionLedger.sol:163). The caller-supplied `mintedNow` sizes the divisor, so a registry that passes a larger count pays less per NFT and one that passes a smaller count pays more. DERIVED: `mintedNow` is never validated in this file.

#### L174 `buyback`

- Declaration: `function buyback(uint256 gen, uint256 mintedNow, uint256 paid) external onlyRegistry`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `b5015a91a67516959ed6bf063feb7ff26c139554`
- Authority: registry
- Gate: `external onlyRegistry (CollectionLedger.sol:174)`
- Reads: retired (line 176)
- Writes: entitledTokens (line 177);retired (line 178);totalEntitled (line 179)
- Value: NONE
- Edges: CollectionLedger.floorPerNFT (CollectionLedger.sol:180), TRUSTED, in-cluster
- Reachability: Registry-only, and refused unless something is retired at `retired` (CollectionLedger.sol:176), so the un-retire at `retired` (CollectionLedger.sol:178) cannot underflow. Credits the full `paid` amount (CollectionLedger.sol:177) while returning one NFT to the outstanding set, which raises the floor whenever paid exceeds the current per-NFT share; the ledger itself never checks the two-times-floor rule the comment attributes to the registry.

#### L187 `crystallize`

- Declaration: `function crystallize(uint256 gen, uint256 mintedAtDeath, uint256 extraEntitled) external onlyRegistry`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `93bd28a1875627f823ff10ff308e0707816a3823`
- Authority: registry
- Gate: `onlyRegistry (CollectionLedger.sol:189)`
- Reads: crystallized (line 191);retired (line 199);entitledTokens (line 204)
- Writes: crystallized (line 192);frozenSupply (line 193);entitledTokens (line 204);totalEntitled (line 205)
- Value: NONE
- Edges: -
- Reachability: Registry-only and one-time at `crystallized` (CollectionLedger.sol:191). It freezes the death supply, then rejects optional entitlement when all frozen NFTs are already retired at `retired` (CollectionLedger.sol:199), avoiding an unclaimable global liability without reverting relaunch. Accepted entitlement increments generation and global totals equally.

### GachaLib

#### L80 `_reanchored`

- Declaration: `function _reanchored(uint256 bi) private view returns (bool v)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `e8bfa78ab53aed5005789b1b8378c75e4fcdde4a`
- Authority: internal (caller: GachaLib.resolveTickets)
- Gate: `UNGATED`
- Reads: REANCHORED_SLOT (line 81, constant)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Private helper deriving a batch-specific slot from `REANCHORED_SLOT` (GachaLib.sol:81) and reading it with `sload` (GachaLib.sol:82) in the delegating hook's storage namespace.

#### L85 `_markReanchored`

- Declaration: `function _markReanchored(uint256 bi) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `bb77c05a86c7b60ba948ca9c0a78dfcfd3260fa4`
- Authority: internal (caller: GachaLib.resolveTickets)
- Gate: `UNGATED`
- Reads: REANCHORED_SLOT (line 86, constant)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Private helper deriving the same namespaced slot and permanently marking it with `sstore` (GachaLib.sol:87). The write is intentionally outside declared sequential storage because this linked library executes by delegatecall.

#### L132 `_seed`

- Declaration: `function _seed(uint256 bi) private view returns (bytes32 v)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `860d809e235dd3b52796cfa5aac99708bfa18f86`
- Authority: internal (callers: GachaLib._pinSeeds and GachaLib.resolveTickets)
- Gate: `UNGATED`
- Reads: SEED_SLOT (line 133, constant)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Private namespaced pinned-seed reader. It hashes batch index with `SEED_SLOT` (GachaLib.sol:133) then uses `sload` (GachaLib.sol:134) in hook storage.

#### L137 `_pinSeed`

- Declaration: `function _pinSeed(uint256 bi, bytes32 v) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `3d01d10798182d6dff65439e9ceebebeb263c854`
- Authority: internal (caller: GachaLib._pinSeeds)
- Gate: `UNGATED`
- Reads: SEED_SLOT (line 138, constant)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Private namespaced pinned-seed writer using `sstore` (GachaLib.sol:139) in the delegating hook's storage.

#### L147 `_pinSeeds`

- Declaration: `function _pinSeeds(Batch[] storage batches, uint256 from, uint256 end) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `759228b542e56d787f05130e20f92066e45725c8`
- Authority: internal (caller: GachaLib.resolveTickets)
- Gate: `UNGATED`
- Reads: PIN_SPAN (line 148, constant)
- Writes: -
- Value: NONE
- Edges: GachaLib._seed (GachaLib.sol:151), TRUSTED, in-cluster;GachaLib._pinSeed (GachaLib.sol:153), TRUSTED, in-cluster
- Reachability: Private bounded pin sweep. It scans no more than `PIN_SPAN` (GachaLib.sol:148) unresolved batches, stores only a non-zero historical blockhash at `_pinSeed` (GachaLib.sol:153), and therefore never pins the current or a future block's unknown hash as zero.

#### L173 `resolveTickets`

- Declaration: `function resolveTickets( Batch[] storage batches, mapping(address => uint256) storage missStreak, mapping(address => uint256) storage pendingOf, mapping(address => uint256) storage outstandingOf, mapping(address => uint256) storage opened, State storage st, uint256 pityThreshold, uint256 maxCount ) external returns (uint256 processed, uint256 won)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `68af1ba449488bd1371c83514b94df0bc05f33e0`
- Authority: anyone at linked library address; protocol reaches it by delegatecall from CauldronHook
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: GachaLib._seed (GachaLib.sol:192), TRUSTED, in-cluster;GachaLib._reanchored (GachaLib.sol:199), TRUSTED, in-cluster;GachaLib._markReanchored (GachaLib.sol:200), TRUSTED, in-cluster;ICauldronCollection.totalMinted (GachaLib.sol:214), UNTRUSTED, out-of-cluster;ICauldronCollection.maxSupply (GachaLib.sol:215), UNTRUSTED, out-of-cluster;ICauldronCollection.mint (GachaLib.sol:246), UNTRUSTED, out-of-cluster;GachaLib._pinSeeds (GachaLib.sol:272), TRUSTED, in-cluster
- Reachability: The hook delegatecalls this external linked-library function with storage references. FIFO processing starts at `batchCursor` (GachaLib.sol:183) and stops at a current-block commit. It uses a pinned original seed first, otherwise the live blockhash. First expiry marks and reanchors once at `commitBlock` (GachaLib.sol:201); second expiry cannot win from the known zero seed, though already-earned pity still can. Before mint, pending/global/collection counters and batch resolved count are decremented at `outstandingCrystals` (GachaLib.sol:226). Mint failure is caught and logged as loss without growing pity. Cursor advancement is monotonic and a bounded seed-pin sweep follows at `_pinSeeds` (GachaLib.sol:272). Both loops are bounded by caller maxCount plus fixed PIN_SPAN.

### ITransferValidator (declared in ICreatorToken.sol)

#### L8 `validateTransfer`

- Declaration: `function validateTransfer(address caller, address from, address to, uint256 tokenId) external view`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster callers are the two collections' _update overrides; the validator contract itself is chosen by the collection's admin
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Called on every mint, transfer and burn of either collection, at `validateTransfer` (MiFrensGenesis.sol:780) and `validateTransfer` (CauldronCollection.sol:176), and only while the slot is non-zero. The address is set by the genesis deployer at `transferValidator` (MiFrensGenesis.sol:538) or by the registry at `transferValidator` (CauldronCollection.sol:195), so an admin-chosen contract sits in the path of every token movement and can halt all of them by reverting. Declared view, but Solidity's type system is the only thing enforcing that on the callee.

### ICreatorToken

#### L16 `getTransferValidator`

- Declaration: `function getTransferValidator() external view returns (address)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: anyone (the implementations are public views)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Market-facing discovery surface implemented at `getTransferValidator` (MiFrensGenesis.sol:525) and `getTransferValidator` (CauldronCollection.sol:182); both just return the stored slot.

#### L17 `getTransferValidationFunction`

- Declaration: `function getTransferValidationFunction() external view returns (bytes4 functionSignature, bool isViewFunction)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: anyone (the implementations are pure)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Implemented at `getTransferValidationFunction` (MiFrensGenesis.sol:530) and `getTransferValidationFunction` (CauldronCollection.sol:187); both report the same selector and the view flag without reading state.

#### L18 `setTransferValidator`

- Declaration: `function setTransferValidator(address validator) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: the collection's admin: the genesis deployer or the registry for the per-brew collection
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:536)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Implemented at `setTransferValidator` (MiFrensGenesis.sol:535) under the genesis deployer gate, and at `setTransferValidator` (CauldronCollection.sol:192) under the registry gate. Neither implementation validates the address, so the same call can enable or disable royalty enforcement and, with a hostile target, freeze transfers entirely.

### IMiFrensShares (declared in MiFrensDividend.sol)

#### L8 `ownerOf`

- Declaration: `function ownerOf(uint256 tokenId) external view returns (address)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster callers are pending, pendingToken, isEnchanted, _castSpell and _claim
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: The ownership oracle for every gate in this contract: read at `ownerOf` (MiFrensDividend.sol:358), `ownerOf` (MiFrensDividend.sol:446) and `ownerOf` (MiFrensDividend.sol:590) to authorise a claim or a cast, and at `ownerOf` (MiFrensDividend.sol:257) to decide whether an enchantment is still live. The address it is called on is the immutable collection at `mifrens` (MiFrensDividend.sol:176).

#### L9 `GENESIS_SUPPLY`

- Declaration: `function GENESIS_SUPPLY() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is the constructor
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read once at `GENESIS_SUPPLY` (MiFrensDividend.sol:177) to fix the free-enchant tranche size; the result must be non-zero at `s` (MiFrensDividend.sol:178).

#### L10 `MAX_SUPPLY`

- Declaration: `function MAX_SUPPLY() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is the constructor
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read once at `MAX_SUPPLY` (MiFrensDividend.sol:181) to fix the eligibility cap, floored at the genesis size at `m` (MiFrensDividend.sol:182). Because it is captured at deploy, a collection whose cap later changed would not be followed - in the collection this cluster ships, the value is immutable.

#### L12 `everMoved`

- Declaration: `function everMoved(uint256 tokenId) external view returns (bool)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is _collectEnchantFee
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read at `everMoved` (MiFrensDividend.sol:508) and only for ids at or below the free tranche: a genesis fren that has never moved returns early and pays nothing, everything else falls through to the fee.

### IReserveRegistry (declared in MiFrensDividend.sol)

#### L18 `enchantFee`

- Declaration: `function enchantFee() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is _collectEnchantFee
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read at `enchantFee` (MiFrensDividend.sol:509); a zero answer makes the enchant free at `fee` (MiFrensDividend.sol:510). The registry can therefore switch the fee on and off for every future caster without any call into this contract.

#### L19 `currentToken`

- Declaration: `function currentToken() external view returns (address)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is _collectEnchantFee
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Read at `currentToken` (MiFrensDividend.sol:511) to decide which asset the fee is charged in, so the fee follows the live generation's token and a zero answer makes the enchant free at `tok` (MiFrensDividend.sol:512).

#### L20 `donateToReserve`

- Declaration: `function donateToReserve(uint256 amount) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: declaration only (no body); in-cluster caller is _collectEnchantFee
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Called at `donateToReserve` (MiFrensDividend.sol:516) after an approve for the exact fee, so the fee leaves this contract in the same transaction it arrived. A registry that does not pull the approved amount would leave the tokens sitting here with no path out. DERIVED: no other function in the file moves an arbitrary asset balance that is not credited to an accumulator.

### MiFrensDividend

#### L175 `constructor`

- Declaration: `constructor(address _mifrens, address _treasury)`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `9467a7eccf529a98131a87604e5492b5f84767aa`
- Authority: deployer
- Gate: `UNGATED`
- Reads: -
- Writes: mifrens (line 176, immutable);SHARES (line 180, immutable);MAX_TOKEN (line 182, immutable);treasury (line 183, immutable)
- Value: NONE
- Edges: IMiFrensShares.GENESIS_SUPPLY (MiFrensDividend.sol:177), TRUSTED, in-cluster;IMiFrensShares.MAX_SUPPLY (MiFrensDividend.sol:181), TRUSTED, in-cluster
- Reachability: Deployment only, and it calls straight into the collection address it is handed at `mifrens` (MiFrensDividend.sol:176) with no code check. Four immutables are fixed here; the only mutable authorities afterwards are `registry` (MiFrensDividend.sol:192) and `funder` (MiFrensDividend.sol:202), both one-time and both held by `treasury` (MiFrensDividend.sol:183). The treasury address is also the sweep destination when nobody is enchanted, so the same address that wires the contract receives undistributable fees.

#### L189 `setRegistry`

- Declaration: `function setRegistry(address _registry) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `d022ce5407788e3c3581c96bb80741a76c5fff3a`
- Authority: treasury
- Gate: `if (msg.sender != treasury) revert NotOwner(); (MiFrensDividend.sol:190)`
- Reads: treasury (line 190, immutable);registry (line 191)
- Writes: registry (line 192)
- Value: NONE
- Edges: -
- Reachability: One-time: a second call reverts on the non-zero `registry` (MiFrensDividend.sol:191) test, so the fee route is fixed forever once wired, and it cannot be unwired if the registry later misbehaves. Until it is set, the fee path at `reg` (MiFrensDividend.sol:506) returns immediately and every enchant is free.

#### L199 `setFunder`

- Declaration: `function setFunder(address _funder) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `e7b956e07eef249d7a841c0e7208eb4fdb015abb`
- Authority: treasury
- Gate: `if (msg.sender != treasury) revert NotOwner(); (MiFrensDividend.sol:200)`
- Reads: treasury (line 200, immutable);funder (line 201)
- Writes: funder (line 202)
- Value: NONE
- Edges: -
- Reachability: One-time: the non-zero test at `funder` (MiFrensDividend.sol:201) makes it unrepeatable, so the single address allowed to append to the basket is permanent. Until set, the basket funder check at `funder` (MiFrensDividend.sol:278) rejects everyone, which means a non-ETH fee has no way in at all.

#### L235 `receive`

- Declaration: `receive() external payable`
- Kind/visibility/mutability: `receive` / `-` / `payable`
- Body SHA-1: `a50a66139c91a7008aad4a5327bea370e79701e1`
- Authority: anyone
- Gate: `UNGATED`
- Reads: residual (line 237);activeShares (line 238);treasury (line 240, immutable);ACC (line 245, constant);activeShares (line 245);accPerShare (line 246);activeShares (line 247);ACC (line 247, constant)
- Writes: totalDeposited (line 236);residual (line 239);residual (line 241);accPerShare (line 246);residual (line 247)
- Value: receives native - declared `payable` (line 235); sends native to `treasury` (line 240)
- Edges: treasury.call (MiFrensDividend.sol:240), UNTRUSTED, out-of-cluster
- Reachability: Open to any sender, so the ETH accumulator cannot be poisoned by an unexpected funder - every wei simply becomes everyone's. With nobody enchanted the whole balance including carried `residual` (MiFrensDividend.sol:237) is pushed to the treasury, and a rejecting treasury re-banks it at `residual` (MiFrensDividend.sol:241) rather than reverting the fee-paying swap. Otherwise the deposit is divided by the live `activeShares` (MiFrensDividend.sol:245) and the division dust is carried at `residual` (MiFrensDividend.sol:247). `totalDeposited` (MiFrensDividend.sol:236) counts the raw value only, so it is not reduced by a treasury sweep and does not track the claimable pot. The external call happens after `residual` is zeroed but before the accumulator branch returns, and this function has no reentrancy guard - a hostile treasury re-entering would find `residual` already zero. DERIVED: the sweep branch returns immediately after the call.

#### L255 `pending`

- Declaration: `function pending(uint256 tokenId) public view returns (uint256)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `8aa0a8979c2300ca757df584ffbc60605bc7bb15`
- Authority: anyone
- Gate: `UNGATED`
- Reads: MAX_TOKEN (line 256, immutable);enchantedBy (line 257);accPerShare (line 258);debtOf (line 258);ACC (line 258, constant)
- Writes: -
- Value: NONE
- Edges: IMiFrensShares.ownerOf (MiFrensDividend.sol:257), TRUSTED, in-cluster
- Reachability: View. Returns zero for an id outside the eligibility cap at `MAX_TOKEN` (MiFrensDividend.sol:256) and for any fren whose caster is no longer its owner at `enchantedBy` (MiFrensDividend.sol:257), which is the same liveness test the claim path uses. It reverts for a non-existent id because the collection's ownerOf does.

#### L273 `fundToken`

- Declaration: `function fundToken(address asset, uint256 amount) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `6170a0ee828ed9a7f3e431343df29c1afae1861b`
- Authority: funder (hook), wired once by treasury
- Gate: `if (msg.sender != funder) revert NotOwner(); (MiFrensDividend.sol:278)`
- Reads: funder (line 278);activeShares (line 280);knownAsset (line 281);assets (line 282);MAX_ASSETS (line 282, constant);accountedOf (line 287);ACC (line 288, constant)
- Writes: knownAsset (line 283);assets (line 284);accountedOf (line 287);accPerShareOf (line 288)
- Value: pulls requested ERC20 `amount` of `asset` from funder via `_pull` (line 286)
- Edges: MiFrensDividend._pull (MiFrensDividend.sol:286), TRUSTED, in-cluster
- Reachability: Funder-only basket funding. It refuses zero values and zero active shares, hard-caps first-time assets, then pulls before accounting. `accountedOf` (MiFrensDividend.sol:287) and per-share accumulator both increase by the requested amount, not a measured balance delta; fee-on-transfer assets can therefore create undercollateralized claims (DERIVED).

#### L323 `adopt`

- Declaration: `function adopt(address asset) external returns (uint256 delta)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `2e11366653d66d3172982be9fc754fd8e9205a98`
- Authority: anyone for known assets; funder or treasury for a new asset
- Gate: `if (msg.sender != funder && msg.sender != treasury) revert NotOwner(); (MiFrensDividend.sol:327)`
- Reads: activeShares (line 325);knownAsset (line 326);funder (line 327);treasury (line 327, immutable);assets (line 328);MAX_ASSETS (line 328, constant);accountedOf (line 333);ACC (line 337, constant)
- Writes: knownAsset (line 329);assets (line 330);accountedOf (line 336);accPerShareOf (line 337)
- Value: books ERC20 balance already held by this contract; no transfer occurs
- Edges: IERC20.balanceOf (MiFrensDividend.sol:332), UNTRUSTED, out-of-cluster
- Reachability: Public push-adoption path. Existing basket assets may be adopted by anyone; only funder or treasury can consume a new basket slot at `funder` (MiFrensDividend.sol:327). It compares actual held balance against `accountedOf` (MiFrensDividend.sol:333), credits only the positive delta, advances accounting before return, and distributes raw asset units without decimal normalization.

#### L342 `pendingToken`

- Declaration: `function pendingToken(uint256 tokenId, address asset) public view returns (uint256)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `535dd23375cf64119445a433d3694dfaa8c72635`
- Authority: anyone
- Gate: `UNGATED`
- Reads: MAX_TOKEN (line 343, immutable);enchantedBy (line 344);accPerShareOf (line 345);debtOfAsset (line 345);ACC (line 345, constant)
- Writes: -
- Value: NONE
- Edges: IMiFrensShares.ownerOf (MiFrensDividend.sol:344), TRUSTED, in-cluster
- Reachability: View, mirroring the ETH one per asset. It will underflow and revert rather than return zero if a debt marker ever exceeded the accumulator at `accPerShareOf` (MiFrensDividend.sol:345); the code keeps markers at or below the accumulator everywhere they are written. DERIVED: every write of `debtOfAsset` assigns the current accumulator value.

#### L349 `assetCount`

- Declaration: `function assetCount() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `332a19e195a1c27add6f21c61c0d8a5d8ac1d151`
- Authority: anyone
- Gate: `UNGATED`
- Reads: assets (line 349)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View of the basket length, which is the bound of every loop over `assets` (MiFrensDividend.sol:349).

#### L357 `claimTokens`

- Declaration: `function claimTokens(uint256 tokenId) external nonReentrant`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `5a284ccd0bd4de63acdd0b68c771e0849c5c363f`
- Authority: holder of token who is also its caster
- Gate: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:358)`
- Reads: enchantedBy (line 359);assets (line 368);assets (line 370);accPerShareOf (line 371);debtOfAsset (line 371);ACC (line 371, constant);accPerShareOf (line 373)
- Writes: debtOfAsset (line 373);owedAsset (line 376)
- Value: ERC20 push of `a` to `msg.sender` (line 375)
- Edges: IMiFrensShares.ownerOf (MiFrensDividend.sol:358), TRUSTED, in-cluster;MiFrensDividend._tryPush (MiFrensDividend.sol:375), TRUSTED, in-cluster
- Reachability: Two gates: current ownership at `ownerOf` (MiFrensDividend.sol:358) and a live enchantment by that same caller at `enchantedBy` (MiFrensDividend.sol:359), so a buyer cannot claim what the previous owner accrued. The per-asset debt marker is advanced at `debtOfAsset` (MiFrensDividend.sol:373) BEFORE the push, and a failed push banks the amount at `owedAsset` (MiFrensDividend.sol:376) instead of reverting, so one hostile token cannot block the other legs and nothing is paid twice. The loop is bounded by the basket length at `n` (MiFrensDividend.sol:368), which only the funder can grow. This path does not touch `totalClaimed` (MiFrensDividend.sol:581), which counts ETH only.

#### L383 `withdrawOwedToken`

- Declaration: `function withdrawOwedToken(address asset) external nonReentrant returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `7fdfa03a41edaec2247b6e7b96083fc21209cd37`
- Authority: anyone (pays only the caller's own banked balance)
- Gate: `UNGATED`
- Reads: owedAsset (line 384)
- Writes: owedAsset (line 386)
- Value: ERC20 push of `asset` to `msg.sender` (line 390)
- Edges: MiFrensDividend._tryPush (MiFrensDividend.sol:390), TRUSTED, in-cluster
- Reachability: Ungated because it can only pay out `owedAsset` (MiFrensDividend.sol:384) for the caller's own address, zeroed at `owedAsset` (MiFrensDividend.sol:386) before the push and guarded by nonReentrant on the declaration at `withdrawOwedToken` (MiFrensDividend.sol:383). Unlike the claim loop this one reverts on a failed transfer at `TransferFailed` (MiFrensDividend.sol:390), which rolls the zeroing back so the balance stays banked. A zero balance is a silent no-op.

#### L397 `_pull`

- Declaration: `function _pull(address asset, address from, uint256 amount) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `96d2d7401629647ded6130f4b216a6ea3677dba7`
- Authority: internal (callers: fundToken)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: ERC20 transferFrom into this contract, encoded at `transferFrom` (line 399)
- Edges: asset.call (MiFrensDividend.sol:398), UNTRUSTED, out-of-cluster
- Reachability: Raw call so a non-standard token is handled, with the result checked at `ret` (MiFrensDividend.sol:401) and a revert on failure. The asset address comes from the funder's argument, so the funder chooses which contract this calls into; it is the same address that is then appended to the iterated basket at `assets` (MiFrensDividend.sol:284).

#### L406 `_tryPush`

- Declaration: `function _tryPush(address asset, address to, uint256 amount) private returns (bool)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `ba4852e24e77dbb44a3441c77e58337d43df6001`
- Authority: internal (callers: claimTokens and withdrawOwedToken)
- Gate: `UNGATED`
- Reads: accountedOf (line 416)
- Writes: accountedOf (line 417)
- Value: attempts ERC20 transfer of `asset` to `to` (line 408)
- Edges: asset.call (MiFrensDividend.sol:407), UNTRUSTED, out-of-cluster
- Reachability: Private non-throwing push. It accepts empty return or true; only success decrements booked balance, saturating at zero at `accountedOf` (MiFrensDividend.sol:417). A hostile token can consume gas, but false/revert normally returns failure for the caller to bank or reject.

#### L424 `isEnchanted`

- Declaration: `function isEnchanted(uint256 tokenId) external view returns (bool)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `b58e71f8a517c6c47a664368e9c8efb0efa34dd8`
- Authority: anyone
- Gate: `UNGATED`
- Reads: MAX_TOKEN (line 425, immutable);enchantedBy (line 426)
- Writes: -
- Value: NONE
- Edges: IMiFrensShares.ownerOf (MiFrensDividend.sol:426), TRUSTED, in-cluster
- Reachability: View of the same liveness test the pay paths use at `enchantedBy` (MiFrensDividend.sol:426). It does not mean the fren is counted in `activeShares` (MiFrensDividend.sol:456): a fren whose transfer hook was skipped reads as not-enchanted here while still occupying a share.

#### L434 `castSpell`

- Declaration: `function castSpell(uint256 tokenId) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `6c16987c6ee297a7819035f52a66eef00b2e6f07`
- Authority: holder of token
- Gate: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:446)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: MiFrensDividend._castSpell (MiFrensDividend.sol:435), TRUSTED, in-cluster
- Reachability: Wrapper; the whole gate is in the callee at `ownerOf` (MiFrensDividend.sol:446).

#### L439 `castMany`

- Declaration: `function castMany(uint256[] calldata tokenIds) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `9d238f88cc138c8140eb3100f918ff2fc2ee3327`
- Authority: holder of token
- Gate: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:446)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: MiFrensDividend._castSpell (MiFrensDividend.sol:441), TRUSTED, in-cluster
- Reachability: Unbounded batch: the loop at `n` (MiFrensDividend.sol:440) is sized by the caller's own array, and every element re-runs the per-token gate, so the only cost of a long list is the caller's gas. Each element may pull an enchant fee, so one transaction can charge the caller several fees.

#### L444 `_castSpell`

- Declaration: `function _castSpell(uint256 tokenId) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `3c89a25da06ab3364cca1e5ef8e52d7cc67f0239`
- Authority: internal (callers: castSpell, castMany); the caller must own the token
- Gate: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:446)`
- Reads: MAX_TOKEN (line 445, immutable);enchantedBy (line 447);accPerShare (line 460);debtOf (line 460);ACC (line 460, constant);accPerShare (line 462);assets (line 486);assets (line 488);accPerShareOf (line 489);debtOfAsset (line 491);ACC (line 492, constant)
- Writes: activeShares (line 456);owed (line 460);debtOf (line 462);owedAsset (line 492);debtOfAsset (line 494);enchantedBy (line 496)
- Value: NONE
- Edges: IMiFrensShares.ownerOf (MiFrensDividend.sol:446), TRUSTED, in-cluster;MiFrensDividend._collectEnchantFee (MiFrensDividend.sol:455), TRUSTED, in-cluster
- Reachability: Reachable by any current owner of an id within the cap at `MAX_TOKEN` (MiFrensDividend.sol:445). Two branches: a fresh join pays the fee first and then increments `activeShares` (MiFrensDividend.sol:456); a stale one - a fren whose transfer hook did not run - settles the PREVIOUS caster's ETH into `owed` (MiFrensDividend.sol:460) and their basket into `owedAsset` (MiFrensDividend.sol:492) and re-points without changing the count, so the share count stays balanced either way. Re-casting for an id you already hold returns at `cur` (MiFrensDividend.sol:448) before any fee. The debt markers for ETH and for every basket asset are set to the current accumulators at `debtOf` (MiFrensDividend.sol:462) and `debtOfAsset` (MiFrensDividend.sol:494), so earning starts now with no back-pay - but only for assets in the list at the time of the cast. DERIVED: the marker loop is bounded by the same basket the funder controls.

#### L504 `_collectEnchantFee`

- Declaration: `function _collectEnchantFee(uint256 tokenId) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `45ca85e6deae67b886e4d698bee83658e8c1103b`
- Authority: internal (callers: _castSpell)
- Gate: `UNGATED`
- Reads: registry (line 505);SHARES (line 508, immutable)
- Writes: -
- Value: ERC20 transferFrom of `tok` from the caster into this contract (line 514); ERC20 approve of `reg` for the fee (line 515)
- Edges: IMiFrensShares.everMoved (MiFrensDividend.sol:508), TRUSTED, in-cluster;IReserveRegistry.enchantFee (MiFrensDividend.sol:509), UNTRUSTED, in-cluster;IReserveRegistry.currentToken (MiFrensDividend.sol:511), UNTRUSTED, in-cluster;IERC20.transferFrom (MiFrensDividend.sol:514), UNTRUSTED, out-of-cluster;IERC20.approve (MiFrensDividend.sol:515), UNTRUSTED, out-of-cluster;IReserveRegistry.donateToReserve (MiFrensDividend.sol:516), UNTRUSTED, in-cluster
- Reachability: Four independent early exits make the fee optional: no registry at `reg` (MiFrensDividend.sol:506), an unmoved original genesis id at `SHARES` (MiFrensDividend.sol:508), a zero fee at `fee` (MiFrensDividend.sol:510), or no live token at `tok` (MiFrensDividend.sol:512). The pull at `transferFrom` (MiFrensDividend.sol:514) is a typed call whose boolean return is required, so a token that returns nothing reverts the enchant. The amount, the asset and the destination are all chosen by the registry between the read and the transfer, and the approve return value is not checked at `approve` (MiFrensDividend.sol:515). Whatever is pulled is immediately handed on at `donateToReserve` (MiFrensDividend.sol:516); if that call does not take the tokens they stay here uncredited to anyone.

#### L523 `onMiFrenTransfer`

- Declaration: `function onMiFrenTransfer(uint256 tokenId, address /*from*/) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `b0193d4ed8581abb0e1ed590d52bcd2cc9ce552a`
- Authority: the MiFrens collection
- Gate: `if (msg.sender != address(mifrens)) revert NotCollection(); (MiFrensDividend.sol:524)`
- Reads: mifrens (line 524, immutable);enchantedBy (line 525);accPerShare (line 527);debtOf (line 527);ACC (line 527, constant);assets (line 541);assets (line 543);accPerShareOf (line 544);debtOfAsset (line 545);ACC (line 547, constant)
- Writes: owed (line 527);owedAsset (line 547);debtOfAsset (line 548);activeShares (line 552);enchantedBy (line 553);debtOf (line 554)
- Value: NONE
- Edges: -
- Reachability: Only the collection can call it, and it is invoked from that contract's transfer chokepoint at `onMiFrenTransfer` (MiFrensGenesis.sol:854) inside a try/catch with a fixed gas stipend - so a revert or an out-of-gas here is swallowed by the caller and the transfer still settles, leaving the fren counted in `activeShares` (MiFrensDividend.sol:552) with a stale caster. A fren that was never enchanted returns at `cur` (MiFrensDividend.sol:526), which is why badge ids and un-cast frens are free no-ops. Both the ETH entitlement at `owed` (MiFrensDividend.sol:527) and each basket leg at `owedAsset` (MiFrensDividend.sol:547) are settled to the LEAVER before the share is released, because after the decrement the leaver's share can no longer be computed. There is no eligibility-cap check here, unlike the claim and cast paths.
- Observation: comment at `MAX_ASSETS` (MiFrensDividend.sol:539) says the basket cap is four because this loop runs under the collection's forwarded gas budget; code at `MAX_ASSETS` (MiFrensDividend.sol:124) sets the cap to three

#### L561 `claim`

- Declaration: `function claim(uint256 tokenId) public nonReentrant returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `public` / `nonpayable`
- Body SHA-1: `3944e9f04c7501ab0c1c83a56b0c9f942b1eaf31`
- Authority: holder of token who is also its caster
- Gate: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:590)`
- Reads: -
- Writes: -
- Value: sends native to `msg.sender` (line 597)
- Edges: MiFrensDividend._claim (MiFrensDividend.sol:562), TRUSTED, in-cluster
- Reachability: Wrapper carrying the nonReentrant guard at `claim` (MiFrensDividend.sol:561); the gates are in the callee at `ownerOf` (MiFrensDividend.sol:590).

#### L566 `claimMany`

- Declaration: `function claimMany(uint256[] calldata tokenIds) external nonReentrant returns (uint256 total)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `7f8d9e302ee89818272527603444e060a8aa0b1c`
- Authority: holder of token who is also its caster
- Gate: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:590)`
- Reads: -
- Writes: -
- Value: sends native to `msg.sender` (line 597)
- Edges: MiFrensDividend._claim (MiFrensDividend.sol:572), TRUSTED, in-cluster
- Reachability: Unbounded batch sized by the caller's own array at `n` (MiFrensDividend.sol:571); every element re-checks ownership and enchantment, and each one performs its own native send inside the single nonReentrant frame declared at `nonReentrant` (MiFrensDividend.sol:568). One id the caller does not own reverts the whole batch.

#### L577 `withdrawOwed`

- Declaration: `function withdrawOwed() external nonReentrant returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `c7e20d9e7a6d8f3ec161e5d9e6aa04247cf55fab`
- Authority: anyone (pays only the caller's own banked balance)
- Gate: `UNGATED`
- Reads: owed (line 578)
- Writes: owed (line 580);totalClaimed (line 581)
- Value: sends native to `msg.sender` (line 582)
- Edges: msg.sender.call (MiFrensDividend.sol:582), UNTRUSTED, out-of-cluster
- Reachability: Ungated but self-limited: it pays only `owed` (MiFrensDividend.sol:578) for the caller, zeroed at `owed` (MiFrensDividend.sol:580) before the send, and the send is wrapped by nonReentrant at `withdrawOwed` (MiFrensDividend.sol:577). A rejecting recipient reverts at `TransferFailed` (MiFrensDividend.sol:583), rolling back the zeroing so nothing is lost. This is the only other writer of `totalClaimed` (MiFrensDividend.sol:581).

#### L588 `_claim`

- Declaration: `function _claim(uint256 tokenId) private returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `f7f80b0dd6f6ef6b503912056a590c36873e32d2`
- Authority: internal (callers: claim, claimMany); the caller must own the token and be its caster
- Gate: `if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner(); (MiFrensDividend.sol:590)`
- Reads: MAX_TOKEN (line 589, immutable);enchantedBy (line 591);accPerShare (line 593);debtOf (line 593);ACC (line 593, constant);accPerShare (line 594)
- Writes: debtOf (line 594);totalClaimed (line 596)
- Value: sends native to `msg.sender` (line 597)
- Edges: IMiFrensShares.ownerOf (MiFrensDividend.sol:590), TRUSTED, in-cluster;msg.sender.call (MiFrensDividend.sol:597), UNTRUSTED, out-of-cluster
- Reachability: Three gates - the cap at `MAX_TOKEN` (MiFrensDividend.sol:589), current ownership at `ownerOf` (MiFrensDividend.sol:590), and a live enchantment by the caller at `enchantedBy` (MiFrensDividend.sol:591) - so exactly one address can ever claim a given id and only for the window it was enchanted. The debt marker is advanced at `debtOf` (MiFrensDividend.sol:594) before the send, so a re-entering recipient would compute zero; both public wrappers also hold the nonReentrant guard. The payout is integer-divided by the scale at `ACC` (MiFrensDividend.sol:593), so sub-wei dust stays in the accumulator rather than being lost.

### IRegistrySummon (declared in MiFrensGenesis.sol)

#### L16 `summon`

- Declaration: `function summon() external payable returns (address token, bytes32 poolId)`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `-`
- Authority: declaration only (no body); the sole in-cluster caller is MiFrensGenesis.igniteCauldron, which holds the gate; the implementing registry is out of cluster
- Gate: `if (minted < GENESIS_SUPPLY) revert NotSoldOut(); (MiFrensGenesis.sol:692)`
- Reads: -
- Writes: -
- Value: receives native - declared `payable` (line 16)
- Edges: -
- Reachability: Reached only from `igniteCauldron` (MiFrensGenesis.sol:679), which forwards the contract's entire balance at `summon` (MiFrensGenesis.sol:699). The callee's own authority check is out of cluster; on this side the call is guarded by the sellout test at `NotSoldOut` (MiFrensGenesis.sol:692) and the one-shot `finalized` flag (MiFrensGenesis.sol:697).

#### L17 `summoned`

- Declaration: `function summoned() external view returns (bool)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); no call site exists in this cluster
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declared but never invoked by any cluster file: the only non-comment occurrence of the selector's sibling is the call to `summon` (MiFrensGenesis.sol:699), and `summoned` (MiFrensGenesis.sol:17) itself appears only in this declaration. DERIVED (grep of every cluster file for the identifier).

### IMiFrensDividendHook (declared in MiFrensGenesis.sol)

#### L21 `onMiFrenTransfer`

- Declaration: `function onMiFrenTransfer(uint256 tokenId, address from) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `-`
- Authority: declaration only (no body); the only in-cluster caller is MiFrensGenesis._update, and the address it is called on is whatever `setDividend` wired
- Gate: `if (from != address(0) && dividend != address(0)) (MiFrensGenesis.sol:852)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Invoked from the ERC721 `_update` override (MiFrensGenesis.sol:771) on every non-mint move, in a try/catch with a fixed gas stipend at `GAS_DIVIDEND_FWD` (MiFrensGenesis.sol:854). The in-cluster implementation is `onMiFrenTransfer` (MiFrensDividend.sol:523); it only acts for an enchanted id.

### MiFrensGenesis

#### L256 `constructor`

- Declaration: `constructor( string memory name_, string memory symbol_, uint256 genesisSupply_, uint256 maxSupply_, uint256 price_, uint256 maxPerWallet_, string memory baseURI_ ) ERC721(name_, symbol_) EIP712(name_, "1")`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `29b176430b015bd4a16a0f534ebce6f1164973c2`
- Authority: deployer
- Gate: `UNGATED`
- Reads: LIQUIDATOR_ID_BASE (line 276, constant)
- Writes: GENESIS_SUPPLY (line 277, immutable);MAX_SUPPLY (line 278, immutable);PRICE (line 279, immutable);MAX_PER_WALLET (line 280, immutable);_base (line 281);deployer (line 282, immutable)
- Value: NONE
- Edges: -
- Reachability: Deployment only. `deployer` (MiFrensGenesis.sol:282) is fixed to the deploying address and is immutable, so every deployer-gated setter in this file is permanently bound to it and can never be rotated or renounced. The art cap is forced below the badge id range by the check at `LIQUIDATOR_ID_BASE` (MiFrensGenesis.sol:276), so MiFren ids and Liquidatoor ids cannot collide. DERIVED: no function in the file writes `GENESIS_SUPPLY`, `MAX_SUPPLY`, `PRICE` or `MAX_PER_WALLET` after construction (they are immutable).

#### L297 `setMaxPerWallet`

- Declaration: `function setMaxPerWallet(uint256 newCap) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `86e45660438f291b967c6ef2fdbe76d68eb2b24a`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:298)`
- Reads: deployer (line 298, immutable);GENESIS_SUPPLY (line 299, immutable);minted (line 300);MAX_PER_WALLET (line 300)
- Writes: MAX_PER_WALLET (line 301)
- Value: NONE
- Edges: -
- Reachability: Deployer-only cap correction. The new cap must be non-zero and strictly below genesis supply. Before any mint it may move either way; after `minted` (MiFrensGenesis.sol:300) becomes non-zero it may only decrease, so buyers cannot have the cap widened after participation.
- Observation: `balanceOf` is the mint gate elsewhere, so non-genesis badges held by an address also consume this wallet cap (DERIVED).

#### L313 `setUnrevealedURI`

- Declaration: `function setUnrevealedURI(string calldata uri) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `7a234ea35dc3df17e37a8a44ac0b1808dbbfe8d0`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:314)`
- Reads: deployer (line 314, immutable)
- Writes: unrevealedURI (line 315)
- Value: NONE
- Edges: -
- Reachability: Deployer-only setter replacing the shared placeholder at `unrevealedURI` (MiFrensGenesis.sol:315). There is no freeze or URI validation.

#### L319 `setRegistry`

- Declaration: `function setRegistry(address _registry) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `372f83963e9c8d9f1a29cd53773538ecb416fd30`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert ZeroAddress(); (MiFrensGenesis.sol:320)`
- Reads: deployer (line 320, immutable);registry (line 321)
- Writes: registry (line 323)
- Value: NONE
- Edges: -
- Reachability: Open to the deployer exactly once: the second call reverts on the non-zero `registry` (MiFrensGenesis.sol:321) test, so the summon target is write-once. Until it runs, `custodyTransfer` (MiFrensGenesis.sol:484) and the registry half of the gate at `registry` (MiFrensGenesis.sol:396) are unreachable, and `igniteCauldron` (MiFrensGenesis.sol:679) reverts on the zero `registry` (MiFrensGenesis.sol:680) and refuses to ignite.

#### L332 `mint`

- Declaration: `function mint(uint256 quantity) external payable nonReentrant`
- Kind/visibility/mutability: `function` / `external` / `payable`
- Body SHA-1: `ed9fca0d25baf47ca1aad1b9ffd1f2a0477c5e2f`
- Authority: anyone
- Gate: `UNGATED`
- Reads: finalized (line 333);cancelled (line 334);minted (line 336);GENESIS_SUPPLY (line 336, immutable);PRICE (line 337, immutable);MAX_PER_WALLET (line 338, immutable);minted (line 344)
- Writes: paid (line 340);revealed (line 348);minted (line 352)
- Value: receives native - exact `msg.value` required (line 337)
- Edges: ERC721.balanceOf (MiFrensGenesis.sol:338), TRUSTED, out-of-cluster
- Reachability: Permissionless while the presale is open: blocked once `finalized` (MiFrensGenesis.sol:333) or `cancelled` (MiFrensGenesis.sol:334) is set. Supply is capped at `GENESIS_SUPPLY` (MiFrensGenesis.sol:336) - not MAX_SUPPLY - and per-caller at `MAX_PER_WALLET` (MiFrensGenesis.sol:338), measured on current `balanceOf` (MiFrensGenesis.sol:338) rather than on lifetime purchases. Each id is marked `revealed` (MiFrensGenesis.sol:348) before it is minted, so the OG tranche never rolls a rarity. `_mint` (MiFrensGenesis.sol:349) re-enters this contract's `_update` (MiFrensGenesis.sol:771) override, where the dividend ping is skipped because from is zero.

#### L359 `cancelPresale`

- Declaration: `function cancelPresale() external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `6caffc45b85e633eddd05b91eb778cd14cb2efb2`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:360)`
- Reads: deployer (line 360, immutable);finalized (line 361);cancelled (line 362)
- Writes: cancelled (line 363)
- Value: NONE
- Edges: -
- Reachability: Deployer-only and one-way: nothing in the file clears `cancelled` (MiFrensGenesis.sol:363), so after this call `mint` (MiFrensGenesis.sol:332) is permanently dead and only `refund` (MiFrensGenesis.sol:370) runs. It is refused after ignition by the `finalized` test (MiFrensGenesis.sol:361). DERIVED: `cancelled` is written on exactly one line in the file.

#### L370 `refund`

- Declaration: `function refund() external nonReentrant returns (uint256 amount)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `068cadbe38c88971d565195afed956c26de1c020`
- Authority: anyone (pays out only to a caller with a recorded balance)
- Gate: `UNGATED`
- Reads: cancelled (line 371);paid (line 372)
- Writes: paid (line 374)
- Value: sends native to `msg.sender` (line 375)
- Edges: msg.sender.call (MiFrensGenesis.sol:375), UNTRUSTED, out-of-cluster
- Reachability: Only after the deployer sets `cancelled` (MiFrensGenesis.sol:371). Pays back exactly the caller's recorded `paid` (MiFrensGenesis.sol:372) balance, which is zeroed at `paid` (MiFrensGenesis.sol:374) before the external send, so a re-entering receiver finds nothing left; the OZ `nonReentrant` guard on the declaration (MiFrensGenesis.sol:370) blocks re-entry as well. The NFTs already minted are not burned, so the refunded ETH and the tokens both survive the cancel.

#### L385 `totalMinted`

- Declaration: `function totalMinted() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `092deca3eb70eafc85e11e559449b4c8e7d2fc89`
- Authority: anyone
- Gate: `UNGATED`
- Reads: minted (line 386)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View. Counts genesis mints written at `minted` (MiFrensGenesis.sol:352) plus volume mints written at `minted` (MiFrensGenesis.sol:548); Liquidatoor badges are not included because they increment `liquidatorMinted` (MiFrensGenesis.sol:449) instead. Burns via `burnFromVault` (MiFrensGenesis.sol:649) never decrement it. DERIVED: those are the only two writes to the counter in the file.

#### L390 `maxSupply`

- Declaration: `function maxSupply() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `1856215aee9f1eabe19adf827986628e9781f053`
- Authority: anyone
- Gate: `UNGATED`
- Reads: MAX_SUPPLY (line 391, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View of the immutable art cap set in the constructor at `MAX_SUPPLY` (MiFrensGenesis.sol:278). It bounds only the volume tranche check at `MAX_SUPPLY` (MiFrensGenesis.sol:546).

#### L395 `onlyDeployerOrRegistry`

- Declaration: `modifier onlyDeployerOrRegistry()`
- Kind/visibility/mutability: `modifier` / `-` / `nonpayable`
- Body SHA-1: `c7fe4f36c80ae6d1246bfbc9a0d65df53a14bcfc`
- Authority: internal (callers: setMinter, setVault, setDividend)
- Gate: `if (msg.sender != deployer && msg.sender != address(registry)) revert NotAuthorized(); (MiFrensGenesis.sol:396)`
- Reads: deployer (line 396, immutable);registry (line 396)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Applied to `setMinter` (MiFrensGenesis.sol:403), `setVault` (MiFrensGenesis.sol:408) and `setDividend` (MiFrensGenesis.sol:413). Both holders are permanent: `deployer` (MiFrensGenesis.sol:282) is immutable and `registry` (MiFrensGenesis.sol:323) is write-once, so this gate cannot be rotated, renounced or dead-ended. DERIVED: no other function in the file writes either slot.

#### L403 `setMinter`

- Declaration: `function setMinter(address _minter) external onlyDeployerOrRegistry`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `7ade795db9a40b88e4d691015a78ce8d4d8d45de`
- Authority: deployer or registry
- Gate: `external onlyDeployerOrRegistry (MiFrensGenesis.sol:403)`
- Reads: -
- Writes: minter (line 404)
- Value: NONE
- Edges: -
- Reachability: Gate held by the modifier at `onlyDeployerOrRegistry` (MiFrensGenesis.sol:395). Re-settable with no zero check, so the volume-mint right at `minter` (MiFrensGenesis.sol:545) can be moved to any address at any time, including after ignition.

#### L408 `setVault`

- Declaration: `function setVault(address _vault) external onlyDeployerOrRegistry`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `f9999fd9c216bc6c5c5e60c76e73012b4cba0798`
- Authority: deployer or registry
- Gate: `external onlyDeployerOrRegistry (MiFrensGenesis.sol:408)`
- Reads: -
- Writes: vault (line 409)
- Value: NONE
- Edges: -
- Reachability: Gate held by the modifier at `onlyDeployerOrRegistry` (MiFrensGenesis.sol:395). Grants the burn right checked at `vault` (MiFrensGenesis.sol:650); re-settable per iteration, again with no zero check.

#### L413 `setDividend`

- Declaration: `function setDividend(address _dividend) external onlyDeployerOrRegistry`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `1fc1907060eba978aa552e55bb150556b80e89a4`
- Authority: deployer or registry
- Gate: `external onlyDeployerOrRegistry (MiFrensGenesis.sol:413)`
- Reads: -
- Writes: dividend (line 414)
- Value: NONE
- Edges: -
- Reachability: Gate held by the modifier at `onlyDeployerOrRegistry` (MiFrensGenesis.sol:395). Sets the address pinged on every non-mint transfer at `dividend` (MiFrensGenesis.sol:852); setting it to zero silently disables the enchantment break.

#### L421 `setLiquidatorMinter`

- Declaration: `function setLiquidatorMinter(address _minter) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `09c713d91e0d69ac5f7d335bc0ad3a4835894480`
- Authority: deployer, registry, or the wired minter (the volume hook)
- Gate: `if (msg.sender != deployer && msg.sender != address(registry) && msg.sender != minter) revert NotAuthorized(); (MiFrensGenesis.sol:422)`
- Reads: deployer (line 422, immutable);registry (line 422);minter (line 422)
- Writes: liquidatorMinter (line 423)
- Value: NONE
- Edges: -
- Reachability: Three holders, the third of which is itself settable: whoever holds `minter` (MiFrensGenesis.sol:422) can hand the badge-mint right on. Confers the only authority accepted at `liquidatorMinter` (MiFrensGenesis.sol:448).

#### L427 `setLiquidatorURI`

- Declaration: `function setLiquidatorURI(string calldata uri) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `0b7fb3ff241192471b8efdbf60b7e8fb1ab4eaa1`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:428)`
- Reads: deployer (line 428, immutable)
- Writes: liquidatorURI (line 429)
- Value: NONE
- Edges: -
- Reachability: Deployer-only metadata base used by the badge branch of `liquidatorURI` (MiFrensGenesis.sol:752).

#### L435 `mintLiquidator`

- Declaration: `function mintLiquidator(address to) external returns (uint256 tokenId)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `4dfec9bd3900c001a3ec3e9053abd167454948ca`
- Authority: liquidatorMinter (the wired PerpEngine)
- Gate: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (MiFrensGenesis.sol:448)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: MiFrensGenesis._mintLiquidator (MiFrensGenesis.sol:436), TRUSTED, in-cluster
- Reachability: Thin wrapper; the authority check lives in the callee at `liquidatorMinter` (MiFrensGenesis.sol:448). Passes an empty stats struct so the `_liqStats` write (MiFrensGenesis.sol:452) is skipped.

#### L440 `mintLiquidatorWithStats`

- Declaration: `function mintLiquidatorWithStats(address to, LiqStats calldata st) external returns (uint256 tokenId)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `40696ee613a4f98dbcb0e7ba1402f0197386dd75`
- Authority: liquidatorMinter (the wired PerpEngine)
- Gate: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (MiFrensGenesis.sol:448)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: MiFrensGenesis._mintLiquidator (MiFrensGenesis.sol:444), TRUSTED, in-cluster
- Reachability: Same gate as the bare variant, in the callee at `liquidatorMinter` (MiFrensGenesis.sol:448); the caller-supplied stats are recorded verbatim at `_liqStats` (MiFrensGenesis.sol:452) with no validation of victim, size or price.

#### L447 `_mintLiquidator`

- Declaration: `function _mintLiquidator(address to, LiqStats memory st) internal returns (uint256 tokenId)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `5de6ad6637e65838a7830f861f2d1afefb4d64bd`
- Authority: internal (callers: mintLiquidator, mintLiquidatorWithStats)
- Gate: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (MiFrensGenesis.sol:448)`
- Reads: liquidatorMinter (line 448);LIQUIDATOR_ID_BASE (line 449, constant);liquidatorMinted (line 449)
- Writes: liquidatorMinted (line 449);isLiquidatoor (line 450);_liqStats (line 452)
- Value: NONE
- Edges: -
- Reachability: Badge ids are `LIQUIDATOR_ID_BASE` plus a counter (MiFrensGenesis.sol:449) and are uncapped - nothing here compares against `MAX_SUPPLY` (MiFrensGenesis.sol:546). Because the constructor refuses a cap at or above `LIQUIDATOR_ID_BASE` (MiFrensGenesis.sol:276), badge ids can never overlap art ids. Each badge is a full ERC721Votes token, so it carries a vote through the self-delegation at `_delegate` (MiFrensGenesis.sol:819). The ERC721 mint itself happens at `_mint` (MiFrensGenesis.sol:453), which re-enters the `_update` override (MiFrensGenesis.sol:771).

#### L458 `liqStats`

- Declaration: `function liqStats(uint256 tokenId) external view returns (LiqStats memory)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `63a0e684701fc12be5d71c5237150df74bf9a9a1`
- Authority: anyone
- Gate: `UNGATED`
- Reads: _liqStats (line 459)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View of whatever the badge minter recorded at `_liqStats` (MiFrensGenesis.sol:452); returns a zeroed struct for ids that were minted through the bare `mintLiquidator` (MiFrensGenesis.sol:435) path or that are not badges at all.

#### L463 `setLiquidatorRenderer`

- Declaration: `function setLiquidatorRenderer(address r) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `3859965ce12c36afb48306df426bab3186c0ff5e`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:464)`
- Reads: deployer (line 464, immutable)
- Writes: liquidatorRenderer (line 465)
- Value: NONE
- Edges: -
- Reachability: Deployer-only. Points the badge branch of `tokenURI` (MiFrensGenesis.sol:750) at an arbitrary contract whose code is called on every badge metadata read.

#### L469 `liquidatoorTrait`

- Declaration: `function liquidatoorTrait(uint256 tokenId) external view returns (string memory)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `aaca80625688fe68f0f354432a64c130e5cd6d78`
- Authority: anyone
- Gate: `UNGATED`
- Reads: isLiquidatoor (line 470)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View over the flag written at `isLiquidatoor` (MiFrensGenesis.sol:450).

#### L484 `custodyTransfer`

- Declaration: `function custodyTransfer(address from, address to, uint256 tokenId) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `e634009683b6572968ace69e0368b4d0951c7f32`
- Authority: registry
- Gate: `if (msg.sender != address(registry)) revert NotAuthorized(); (MiFrensGenesis.sol:485)`
- Reads: registry (line 485)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Registry-only move with no owner approval: `_transfer` (MiFrensGenesis.sol:486) checks only that `from` is the current owner. It routes through the `_update` override (MiFrensGenesis.sol:771), so it breaks the enchantment, moves the vote and sets `everMoved` (MiFrensGenesis.sol:861) exactly like a market transfer. No burn happens here, so the collection count is unchanged.

#### L493 `setFinalizer`

- Declaration: `function setFinalizer(address _finalizer) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `a0cafca9f3ec838073afd1b3152c67a97d84a48f`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:494)`
- Reads: deployer (line 494, immutable)
- Writes: finalizer (line 495)
- Value: NONE
- Edges: -
- Reachability: Deployer-only. Writing a non-zero `finalizer` (MiFrensGenesis.sol:495) converts ignition from permissionless to single-address, enforced at `finalizer` (MiFrensGenesis.sol:695); it can be set back to zero at any time before ignition.

#### L499 `setMetadata`

- Declaration: `function setMetadata(MetadataMode _mode, address _renderer, string calldata baseURI_) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `f8fddd48c5b5f0b2d40fc79b95196fc7ad4a96d1`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:502)`
- Reads: deployer (line 502, immutable)
- Writes: mode (line 503);renderer (line 504);_base (line 505)
- Value: NONE
- Edges: -
- Reachability: Deployer-only, unlimited re-settable. An empty string leaves `_base` (MiFrensGenesis.sol:505) untouched, but `mode` (MiFrensGenesis.sol:503) and `renderer` (MiFrensGenesis.sol:504) are always overwritten, so passing a zero renderer with Renderer mode falls back to the baseURI branch at `renderer` (MiFrensGenesis.sol:757).

#### L509 `setRarityOdds`

- Declaration: `function setRarityOdds(uint16[4] calldata cum) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `32fa6ec97577ff57be3164e371db94a6c1aa86a9`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:510)`
- Reads: deployer (line 510, immutable)
- Writes: rarityCumBps (line 512)
- Value: NONE
- Edges: -
- Reachability: Deployer-only. The require at `cum` (MiFrensGenesis.sol:511) enforces ascending cumulative bps ending at 10000, but nothing pins the odds at reveal time: a token minted under one ladder is rolled against whatever `rarityCumBps` (MiFrensGenesis.sol:657) holds when `_reveal` runs.

#### L516 `setRoyalty`

- Declaration: `function setRoyalty(address receiver, uint96 bps) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `f95428fcbd3120ce2473feeb9be532156755339f`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:517)`
- Reads: deployer (line 517, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Deployer-only, capped at 10 percent by the require at `bps` (MiFrensGenesis.sol:518). The receiver and rate land in the inherited ERC2981 storage through `_setDefaultRoyalty` (MiFrensGenesis.sol:519), which this file never reads back.

#### L525 `getTransferValidator`

- Declaration: `function getTransferValidator() external view returns (address)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `2ede13e2759297ef93349ee16002dfa39d389648`
- Authority: anyone
- Gate: `UNGATED`
- Reads: transferValidator (line 526)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View of the slot written at `transferValidator` (MiFrensGenesis.sol:538) and consulted on every move at `transferValidator` (MiFrensGenesis.sol:778).

#### L530 `getTransferValidationFunction`

- Declaration: `function getTransferValidationFunction() external pure returns (bytes4 functionSignature, bool isViewFunction)`
- Kind/visibility/mutability: `function` / `external` / `pure`
- Body SHA-1: `cbc44bdf3d419823449aebcfdcd45349b7f807fe`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure constant pair advertising the validator entry point; it returns the selector of `validateTransfer` (MiFrensGenesis.sol:531) and reads no state.

#### L535 `setTransferValidator`

- Declaration: `function setTransferValidator(address validator) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `4dd5b3a0456258919b93992d20ab7c0346b01a3a`
- Authority: deployer
- Gate: `if (msg.sender != deployer) revert NotAuthorized(); (MiFrensGenesis.sol:536)`
- Reads: transferValidator (line 537)
- Writes: transferValidator (line 538)
- Value: NONE
- Edges: -
- Reachability: Deployer-only and freely re-settable, including to zero. A non-zero value makes every mint, transfer and burn call out to that address first at `validateTransfer` (MiFrensGenesis.sol:780), so a validator that reverts halts the whole collection - including the vault burn at `_burn` (MiFrensGenesis.sol:651) and the registry move at `_transfer` (MiFrensGenesis.sol:486). DERIVED: `_update` is the single ERC721 chokepoint, and the validator call precedes the super call.

#### L544 `mint`

- Declaration: `function mint(address to) external returns (uint256 tokenId)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `9d6e0353bd9dcedcb7fb487cccaf28a7a583b23d`
- Authority: minter (the wired volume hook)
- Gate: `if (msg.sender != minter) revert OnlyMinter(); (MiFrensGenesis.sol:545)`
- Reads: minter (line 545);minted (line 546);MAX_SUPPLY (line 546, immutable);minted (line 547)
- Writes: minted (line 548);mintBlockOf (line 550)
- Value: NONE
- Edges: -
- Reachability: Only the address in `minter` (MiFrensGenesis.sol:545) reaches this, and only while `minted` is below `MAX_SUPPLY` (MiFrensGenesis.sol:546). The id is `minted` plus one (MiFrensGenesis.sol:547), so this tranche continues the same numbering the presale used and a never-sold-out genesis leaves ids that a volume mint will then occupy. Rarity is not rolled here: only the mint block is committed at `mintBlockOf` (MiFrensGenesis.sol:550). The token itself is created at `_mint` (MiFrensGenesis.sol:551).

#### L557 `reveal`

- Declaration: `function reveal(uint256 tokenId) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `222c01a55377f219fea925e5f095247ea4e904fa`
- Authority: holder of token
- Gate: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (MiFrensGenesis.sol:591)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: MiFrensGenesis._reveal (MiFrensGenesis.sol:558), TRUSTED, in-cluster
- Reachability: Wrapper; the ownership gate is in the callee at `ownerOf` (MiFrensGenesis.sol:591). A genesis id is already flagged at `revealed` (MiFrensGenesis.sol:348) so the call is a no-op for the OG tranche.

#### L577 `revealBatch`

- Declaration: `function revealBatch(uint256[] calldata tokenIds) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `94cf710cfcefafe6327404306db8063334dcf706`
- Authority: holder of token
- Gate: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (MiFrensGenesis.sol:591)`
- Reads: -
- Writes: -
- Value: NONE
- Edges: MiFrensGenesis._reveal (MiFrensGenesis.sol:582), TRUSTED, in-cluster
- Reachability: Batch wrapper bounded at fifty ids by the check at `BadBatch` (MiFrensGenesis.sol:581); every element still passes the per-token ownership gate at `ownerOf` (MiFrensGenesis.sol:591), so one id the caller does not own reverts the whole batch.

#### L590 `_reveal`

- Declaration: `function _reveal(uint256 tokenId) private`
- Kind/visibility/mutability: `function` / `private` / `nonpayable`
- Body SHA-1: `403ffd12b5eeeaa5e7a6642908f45b71d707163d`
- Authority: internal (callers: reveal and revealBatch); caller must own token
- Gate: `if (ownerOf(tokenId) != msg.sender) revert OnlyMinter(); (MiFrensGenesis.sol:591)`
- Reads: revealed (line 592);mintBlockOf (line 593);reanchored (line 630)
- Writes: reanchored (line 631);mintBlockOf (line 632);rarityOf (line 636);revealed (line 637)
- Value: NONE
- Edges: ERC721.ownerOf (MiFrensGenesis.sol:591), TRUSTED, out-of-cluster;MiFrensGenesis._rollRarity (MiFrensGenesis.sol:641), TRUSTED, in-cluster
- Reachability: Owner-only internal reveal body. A first expired seed spends `reanchored` (MiFrensGenesis.sol:631), rewrites the commit block, and returns. A second expiry marks base rarity revealed at `revealed` (MiFrensGenesis.sol:637), preventing further rerolls. A live blockhash is mixed with token id and contract address before `_rollRarity` (MiFrensGenesis.sol:641).
- Observation: The comment says a holder or keeper can retry, but the `ownerOf` gate (MiFrensGenesis.sol:591) excludes keepers.

#### L649 `burnFromVault`

- Declaration: `function burnFromVault(uint256 tokenId) external`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `f2f5866c0548ff39cdb5c0d36aa4dbbac674fd8a`
- Authority: vault
- Gate: `if (msg.sender != vault) revert OnlyVault(); (MiFrensGenesis.sol:650)`
- Reads: vault (line 650)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Only the address wired at `vault` (MiFrensGenesis.sol:409). The burn does not touch `minted` (MiFrensGenesis.sol:548), so the counter that gates new mints is monotonic and a burned id is never re-issued; the ERC721 balance and the counter therefore diverge by exactly the number of burns. DERIVED: no line in the file decrements the counter.

#### L654 `_rollRarity`

- Declaration: `function _rollRarity(uint256 seed) private view returns (uint8)`
- Kind/visibility/mutability: `function` / `private` / `view`
- Body SHA-1: `c0ba744222e022708acb5f76dc6666eaa837e3ef`
- Authority: internal (callers: _reveal)
- Gate: `UNGATED`
- Reads: rarityCumBps (line 657)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Called only from the reveal path at `_rollRarity` (MiFrensGenesis.sol:641). Walks the four cumulative buckets at `rarityCumBps` (MiFrensGenesis.sol:657) and falls through to tier zero, so a ladder whose last entry is below 10000 silently returns the common tier.

#### L679 `igniteCauldron`

- Declaration: `function igniteCauldron() external nonReentrant returns (address token)`
- Kind/visibility/mutability: `function` / `external` / `nonpayable`
- Body SHA-1: `615aa0747cbdad54506f99feea34d2adbe20589b`
- Authority: anyone once sold out - unless a finalizer is set, and then only the finalizer
- Gate: `if (finalizer != address(0) && msg.sender != finalizer) revert NotAuthorized(); (MiFrensGenesis.sol:695)`
- Reads: registry (line 680);finalized (line 681);cancelled (line 691);minted (line 692);GENESIS_SUPPLY (line 692, immutable);finalizer (line 695)
- Writes: finalized (line 697)
- Value: forwards this contract's ENTIRE native balance to the registry's summon at `summon` (line 699)
- Edges: IRegistrySummon.summon (MiFrensGenesis.sol:699), TRUSTED, out-of-cluster
- Reachability: Permissionless ignition, guarded by `nonReentrant` (MiFrensGenesis.sol:679) and by four state tests in order: the registry must be wired at `RegistryNotSet` (MiFrensGenesis.sol:680), ignition must not have happened at `AlreadyFinalized` (MiFrensGenesis.sol:681), the round must not be CANCELLED at `AlreadyCancelled` (MiFrensGenesis.sol:691), and the genesis tranche must be sold out at `NotSoldOut` (MiFrensGenesis.sol:692); a configured finalizer narrows the caller at `finalizer` (MiFrensGenesis.sol:695) so the team's atomic summon-plus-buy cannot be front-run. The cancelled check is the NEW one and it closes a drain: cancellation has no sell-out precondition, so 'cancelled AND sold out' is an ordinary state in which every other gate passed, and the whole un-refunded balance was forwarded at `summon` (MiFrensGenesis.sol:699) while the refund debt survived - `refund` being the only other native exit and there being no owner sweep. `finalized` (MiFrensGenesis.sol:697) is written before the external call, so the summon cannot re-enter this entry (DERIVED). The amount forwarded is the whole balance read at `bal` (MiFrensGenesis.sol:698), not a tracked total, so any ether pushed in by other means is summoned too (DERIVED).

#### L708 `soldOut`

- Declaration: `function soldOut() external view returns (bool)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `b0d7a265180a5bf8b99e87a72bfccf6e128f661c`
- Authority: anyone
- Gate: `UNGATED`
- Reads: minted (line 709);GENESIS_SUPPLY (line 709, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View mirroring the ignition condition at `GENESIS_SUPPLY` (MiFrensGenesis.sol:692).

#### L713 `remaining`

- Declaration: `function remaining() external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `c3b457eae2b8eea35b33b130c74dc64ba62d1d47`
- Authority: anyone
- Gate: `UNGATED`
- Reads: minted (line 714);GENESIS_SUPPLY (line 714, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: View. Saturates at zero rather than underflowing when `minted` (MiFrensGenesis.sol:714) has passed the genesis cap via volume mints.

#### L724 `isGenesis`

- Declaration: `function isGenesis(uint256 tokenId) public view returns (bool)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `3a993b1378eb824f80435cc47f1d23d82c2f274f`
- Authority: anyone
- Gate: `UNGATED`
- Reads: GENESIS_SUPPLY (line 725, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure id comparison against the immutable `GENESIS_SUPPLY` (MiFrensGenesis.sol:725); id zero is excluded. Badge ids start at `LIQUIDATOR_ID_BASE` (MiFrensGenesis.sol:449) and so are never genesis.

#### L734 `_getVotingUnits`

- Declaration: `function _getVotingUnits(address account) internal view override returns (uint256)`
- Kind/visibility/mutability: `function` / `internal` / `view`
- Body SHA-1: `bb04ba778429803d95cc88d65de6bdaa2a59a08e`
- Authority: internal (called by inherited ERC721Votes delegation logic)
- Gate: `UNGATED`
- Reads: genesisBalanceOf (line 735)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Internal voting-unit override returning only `genesisBalanceOf` (MiFrensGenesis.sol:735), so delegation moves the same units that the custom update path checkpoints and excludes forged art plus badges.

#### L741 `ogTrait`

- Declaration: `function ogTrait(uint256 tokenId) external view returns (string memory)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `8a1cf83dc9df814e97b817f84c40857eb8f92266`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: MiFrensGenesis.isGenesis (MiFrensGenesis.sol:742), TRUSTED, in-cluster
- Reachability: View helper over `isGenesis` (MiFrensGenesis.sol:724).
- Observation: comment at `rarity` (MiFrensGenesis.sol:739) says the non-genesis branch reports the rolled rarity tier; code at `isGenesis` (MiFrensGenesis.sol:742) returns a fixed string for every non-genesis id and never reads `rarityOf` (MiFrensGenesis.sol:642)

#### L745 `tokenURI`

- Declaration: `function tokenURI(uint256 tokenId) public view override returns (string memory)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `8dcb8d6b27669ed4a27ac2e2b4978beddd5642d3`
- Authority: anyone
- Gate: `UNGATED`
- Reads: isLiquidatoor (line 748);liquidatorRenderer (line 749);liquidatorURI (line 752);GENESIS_SUPPLY (line 756, immutable);revealed (line 756);unrevealedURI (line 756);mode (line 757);renderer (line 757);_base (line 760)
- Writes: -
- Value: NONE
- Edges: ICollectionRenderer.tokenURI (MiFrensGenesis.sol:750), UNTRUSTED, out-of-cluster;ICollectionRenderer.tokenURI (MiFrensGenesis.sol:758), UNTRUSTED, out-of-cluster
- Reachability: View, but it calls out to two deployer-settable contracts: the badge renderer at `liquidatorRenderer` (MiFrensGenesis.sol:749) and the art renderer at `renderer` (MiFrensGenesis.sol:757). Reverts for an unowned id at `_requireOwned` (MiFrensGenesis.sol:746). Only ids above `GENESIS_SUPPLY` (MiFrensGenesis.sol:756) can show the placeholder, so an unrevealed genesis id is impossible by construction. Both string branches concatenate the id through `toString` (MiFrensGenesis.sol:752) and `toString` (MiFrensGenesis.sol:760).

#### L771 `_update`

- Declaration: `function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Votes) returns (address)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `976cda1042e56fbc23241aa8f40702a709af64e2`
- Authority: internal (all ERC721 mint, transfer, and burn paths)
- Gate: `UNGATED`
- Reads: transferValidator (line 778);GENESIS_SUPPLY (line 803, immutable);genesisBalanceOf (line 810);dividend (line 852);GAS_DIVIDEND_MIN (line 853, constant);GAS_DIVIDEND_FWD (line 854, constant);everMoved (line 860)
- Writes: genesisBalanceOf (line 810);genesisBalanceOf (line 811);everMoved (line 861)
- Value: NONE
- Edges: ITransferValidator.validateTransfer (MiFrensGenesis.sol:780), UNTRUSTED, out-of-cluster;ERC721Votes._update (MiFrensGenesis.sol:806), TRUSTED, out-of-cluster;ERC721._update (MiFrensGenesis.sol:816), TRUSTED, out-of-cluster;IMiFrensDividendHook.onMiFrenTransfer (MiFrensGenesis.sol:854), UNTRUSTED, in-cluster
- Reachability: Movement chokepoint. A configured validator runs before state change at `validateTransfer` (MiFrensGenesis.sol:780). Genesis ids use the votes-aware update and adjust `genesisBalanceOf`; every other id bypasses ERC721Votes through `ERC721` (MiFrensGenesis.sol:816), excluding them from numerator and total-supply checkpoints. Recipients self-delegate if needed. Existing-token moves require a fixed dividend gas floor, call the dividend after ownership changed in caught try/catch, then permanently mark moved genesis ids at `everMoved` (MiFrensGenesis.sol:861).

#### L866 `_increaseBalance`

- Declaration: `function _increaseBalance(address account, uint128 amount) internal override(ERC721, ERC721Votes)`
- Kind/visibility/mutability: `function` / `internal` / `nonpayable`
- Body SHA-1: `3e01bc4a66fbb1bfa296c714fa66f9d1c8e82b6f`
- Authority: internal (callers: ERC721 batch-mint plumbing)
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: ERC721._increaseBalance (MiFrensGenesis.sol:870), TRUSTED, out-of-cluster
- Reachability: Diamond resolution only; it forwards to the inherited implementation at `_increaseBalance` (MiFrensGenesis.sol:870) and no code in this file calls it directly. DERIVED: the identifier appears nowhere else in the file.

#### L874 `supportsInterface`

- Declaration: `function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool)`
- Kind/visibility/mutability: `function` / `public` / `view`
- Body SHA-1: `60f0cb66b5e355a6739e4972daca8d494486aa4f`
- Authority: anyone
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: ERC2981.supportsInterface (MiFrensGenesis.sol:875), TRUSTED, out-of-cluster
- Reachability: View. Adds the creator-token id to whatever the inherited chain answers at `supportsInterface` (MiFrensGenesis.sol:875).

### MintCurvePolicy

#### L71 `constructor`

- Declaration: `constructor(uint256 _base, uint256 _spread, uint256 _knee, uint256 _supply)`
- Kind/visibility/mutability: `constructor` / `-` / `nonpayable`
- Body SHA-1: `f7eeaebc6e7155bd6d7e937bd3f9f0975bf8a0ae`
- Authority: deployer
- Gate: `UNGATED`
- Reads: -
- Writes: base (line 83, immutable);spread (line 84, immutable);knee (line 85, immutable);supply (line 86, immutable)
- Value: NONE
- Edges: -
- Reachability: Deployment only; the launch script in the deploy directory is the only place in the tree that constructs it. The contract has no storage and no owner at all: all four parameters are immutable, so the ladder cannot be re-tuned after deploy and there is no gate to rotate or renounce. A zero `_knee` (MintCurvePolicy.sol:75) is refused because it would divide by zero at position zero, and a zero `_spread` (MintCurvePolicy.sol:82) is refused because a flat ladder breaks the rising-floor property the comment describes.

#### L119 `priceAt`

- Declaration: `function priceAt(uint256 k, uint256, uint256) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `b4ab07132921b3f2e4e3504d256dff3e6c2fbc46`
- Authority: anyone
- Gate: `UNGATED`
- Reads: base (line 123, immutable);spread (line 123, immutable);knee (line 123, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Pure-by-effect view called by the hook's mint pricing at `priceAt` (CauldronHook.sol:2318), inside a try/catch there, with the hook's own base and step arguments ignored by this implementation. Integer division at `knee` (MintCurvePolicy.sol:123) rounds the cost DOWN, and the units are whatever the caller's credit is denominated in - this contract performs no conversion and knows nothing about decimals.

#### L132 `totalToMintOut`

- Declaration: `function totalToMintOut() external view returns (uint256 total)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `04e0e7f5f840d5ccaef0ef41b7b24644669704de`
- Authority: anyone
- Gate: `UNGATED`
- Reads: supply (line 133, immutable);base (line 135, immutable);spread (line 135, immutable);knee (line 135, immutable)
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Off-chain calibration helper: the loop at `n` (MintCurvePolicy.sol:134) runs `supply` times, a bound fixed at deploy and reachable by anyone, so on a large collection it can exceed a block's gas - it is never called from a mint path in this repo. The only caller in the tree is the launch script in the deploy directory. Each term rounds down exactly as the per-item view does, so the sum is the sum of the actual charges.

### INFTContract

#### L8 `getHolderTaxRate`

- Declaration: `function getHolderTaxRate(address holder) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); the only caller in the tree is the hook's private tax helper, which is out of cluster
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Called inside a try/catch at `getHolderTaxRate` (CauldronHook.sol:1824) on a hook-configured address, so a reverting or missing implementation degrades rather than blocking a swap. Neither collection in this cluster implements it - the two ERC721s expose no such function - so the address the hook points at is some other contract. DERIVED: the identifier appears nowhere else in the tree.

#### L11 `balanceOf`

- Declaration: `function balanceOf(address holder) external view returns (uint256)`
- Kind/visibility/mutability: `function` / `external` / `view`
- Body SHA-1: `-`
- Authority: declaration only (no body); no call site exists anywhere in the tree
- Gate: `UNGATED`
- Reads: -
- Writes: -
- Value: NONE
- Edges: -
- Reachability: Declared beside the tax-rate view but never invoked through this interface: the only use of the interface type is the single tax call at `INFTContract` (CauldronHook.sol:1824). DERIVED: grep of the non-library sources finds no call of this member on this interface.
