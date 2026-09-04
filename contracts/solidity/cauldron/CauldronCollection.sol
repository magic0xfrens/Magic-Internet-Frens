// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MetadataMode, ICollectionRenderer, ICauldronCollection} from "./ICauldron.sol";
import {ICreatorToken, ITransferValidator} from "./ICreatorToken.sol";

/**
 * @title CauldronCollection
 * @notice The per-brew NFT collection minted purely from swap VOLUME by the
 *         Cauldron's V4 hook — no public mint, no owner mint. One brew, one
 *         collection; when the brew dies the collection stops minting forever.
 *
 *  METADATA IS THE PROPOSER'S CHOICE (immutable at deploy):
 *    - BaseURI  → tokenURI(id) = baseURI + id            (IPFS / off-chain)
 *    - Renderer → tokenURI(id) = renderer.tokenURI(id)   (fully on-chain art)
 *
 *  Only the `minter` (the volume hook) can mint, and only up to `maxSupply`.
 *  There is no admin surface at all after construction.
 */
contract CauldronCollection is ERC721, ERC2981, ICreatorToken, ICauldronCollection {
    using Strings for uint256;

    error OnlyMinter();
    error OnlyVault();
    error MintedOut();
    error BadConfig();
    error VaultSet();

    /// @notice The volume hook allowed to mint (set once, at deploy).
    address public immutable minter;

    /// @notice The deployer (registry) allowed to wire the vault.
    address public immutable deployer;

    /// @notice The vault allowed to burn on redeem (set once, after deploy).
    address public vault;

    /// @notice Hard cap on the collection.
    uint256 public immutable maxSupply;

    /// @notice Metadata resolution mode (immutable).
    MetadataMode public immutable mode;

    /// @notice On-chain renderer (mode == Renderer).
    address public immutable renderer;

    /// @notice Base URI (mode == BaseURI).
    string private _baseTokenURI;

    uint256 public totalMinted;

    // ── Gacha rarity + reveal ────────────────────────────────────────────
    // Rarity tiers: 0=Common, 1=Rare, 2=Epic, 3=Ultra. Rolled at mint from an
    // on-chain seed and stored. Cumulative odds in bps (last must be 10000).
    uint16[4] public rarityCumBps = [uint16(7900), 9400, 9900, 10000];

    /// @notice tokenId => rarity tier (0..3).
    mapping(uint256 => uint8) public rarityOf;

    /// @notice tokenId => revealed. Unrevealed tokens show the placeholder URI.
    mapping(uint256 => bool) public revealed;

    /// @notice Placeholder metadata shown before reveal.
    string public unrevealedURI = "https://magicfrens.xyz/api/cauldron/unrevealed";

    event Minted(address indexed to, uint256 indexed tokenId, uint8 rarity);
    event Revealed(uint256 indexed tokenId, uint8 rarity);

    /// @notice ERC-721C transfer validator. Every transfer is checked against it,
    ///         so a market that doesn't pay the royalty is BLOCKED — the fee to
    ///         the genesis dividend becomes unavoidable (OpenSea/Blur/etc. honor
    ///         this). Zero = unrestricted (EIP-2981 declared but not enforced).
    ///         Settable by the deployer/registry so enforcement can be flipped on.
    address public transferValidator;

    constructor(
        string memory name_,
        string memory symbol_,
        address minter_,
        uint256 maxSupply_,
        MetadataMode mode_,
        string memory baseURI_,
        address renderer_,
        address royaltyReceiver_,
        uint96 royaltyBps_
    ) ERC721(name_, symbol_) {
        if (minter_ == address(0) || maxSupply_ == 0) revert BadConfig();
        if (mode_ == MetadataMode.Renderer) {
            if (renderer_ == address(0) || renderer_.code.length == 0) revert BadConfig();
        } else {
            if (bytes(baseURI_).length == 0) revert BadConfig();
        }
        require(royaltyBps_ <= 1000, "royalty too high"); // <= 10%
        minter = minter_;
        deployer = msg.sender;
        maxSupply = maxSupply_;
        mode = mode_;
        renderer = renderer_;
        _baseTokenURI = baseURI_;
        if (royaltyReceiver_ != address(0)) _setDefaultRoyalty(royaltyReceiver_, royaltyBps_);
    }

    // ── ERC-721C creator token: enforced-royalty transfers ───────────────────

    /// @dev Every mint/transfer/burn passes through _update; the validator vets
    ///      the move before it settles. No validator set → trades freely.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address v = transferValidator;
        if (v != address(0)) {
            ITransferValidator(v).validateTransfer(_msgSender(), _ownerOf(tokenId), to, tokenId);
        }
        return super._update(to, tokenId, auth);
    }

    /// @inheritdoc ICreatorToken
    function getTransferValidator() external view returns (address) {
        return transferValidator;
    }

    /// @inheritdoc ICreatorToken
    function getTransferValidationFunction() external pure returns (bytes4 functionSignature, bool isViewFunction) {
        return (ITransferValidator.validateTransfer.selector, true);
    }

    /// @inheritdoc ICreatorToken
    function setTransferValidator(address validator) external {
        if (msg.sender != deployer) revert OnlyMinter();
        emit TransferValidatorUpdated(transferValidator, validator);
        transferValidator = validator;
    }

    /// @inheritdoc ERC721
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return interfaceId == type(ICreatorToken).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Mint the next token to `to`. Only the volume hook may call.
    ///         Rolls the token's gacha rarity on-chain; it mints unrevealed.
    function mint(address to) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert OnlyMinter();
        if (totalMinted >= maxSupply) revert MintedOut();
        tokenId = ++totalMinted; // 1-indexed

        uint256 seed = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1), block.prevrandao, to, tokenId, address(this)
        )));
        uint8 rarity = _rollRarity(seed);
        rarityOf[tokenId] = rarity;

        _mint(to, tokenId);
        emit Minted(to, tokenId, rarity);
    }

    /// @notice Reveal a token you own — flips its metadata from placeholder to
    ///         the rarity-based art.
    function reveal(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert OnlyMinter();
        if (!revealed[tokenId]) {
            revealed[tokenId] = true;
            emit Revealed(tokenId, rarityOf[tokenId]);
        }
    }

    function _rollRarity(uint256 seed) private view returns (uint8) {
        uint16 r = uint16(seed % 10_000);
        for (uint8 i = 0; i < 4; i++) {
            if (r < rarityCumBps[i]) return i;
        }
        return 0;
    }

    /// @notice One-time wiring of the floor vault (by the deployer/registry).
    function setVault(address _vault) external {
        if (msg.sender != deployer) revert OnlyMinter();
        if (vault != address(0)) revert VaultSet();
        vault = _vault;
    }

    /// @notice Burn a token on redemption. Only the vault may call.
    function burnFromVault(uint256 tokenId) external {
        if (msg.sender != vault) revert OnlyVault();
        _burn(tokenId);
    }

    /// @inheritdoc ERC721
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        // Unrevealed tokens show the placeholder.
        if (!revealed[tokenId]) return unrevealedURI;
        if (mode == MetadataMode.Renderer) {
            return ICollectionRenderer(renderer).tokenURI(tokenId);
        }
        // BaseURI mode: baseURI + rarity + "/" + id so rarity variants resolve.
        return string.concat(
            _baseTokenURI,
            uint256(rarityOf[tokenId]).toString(),
            "/",
            tokenId.toString()
        );
    }

    /// @notice Configure rarity odds (cumulative bps, ascending, last == 10000).
    ///         Only the deployer/registry, only before the first mint.
    function setRarityOdds(uint16[4] calldata cum) external {
        if (msg.sender != deployer) revert OnlyMinter();
        if (totalMinted != 0) revert VaultSet();
        require(cum[3] == 10_000 && cum[0] <= cum[1] && cum[1] <= cum[2] && cum[2] <= cum[3], "odds");
        rarityCumBps = cum;
    }
}
