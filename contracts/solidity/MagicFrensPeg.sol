// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal interface to the on-chain art renderer.
interface IFrenRenderer {
    function tokenURI(
        uint256 tokenId,
        uint8 classIdx,
        uint8 bodyIdx,
        uint8 faceIdx,
        uint8 itemIdx
    ) external view returns (string memory);
}

/**
 * @title MagicFrensPeg
 * @notice UniPeg-style bonded token+NFT system with trait-based volume incentives
 *
 * Mechanics:
 * - Buy tokens → mint random-trait NFT (bound to tokens)
 * - Sell tokens → burn NFT (unless committed)
 * - Commit NFT → pay 0.5 tokens → NFT becomes permanent
 * - After commit: sell tokens independently, NFT stays in wallet
 *
 * Supply: 420 MagicFrens (from 1111 possible trait combinations)
 * Chains: Ethereum, Base, BNB
 * Fully on-chain traits from MagicFrens collection (7 classes, 1111 combos)
 *
 * Unlike uPEG where NFTs are always bound to tokens, MagicFrensPeg allows
 * committed NFTs to be traded independently on OpenSea while maintaining
 * the volume incentive for trait discovery.
 */
contract MagicFrensPeg is ERC20, ERC721Enumerable, Ownable, ReentrancyGuard {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Maximum supply of MagicFrens (10x less than uPEG's 10,000)
    uint256 public constant MAX_SUPPLY = 1111;

    /// @notice Commit fee in tokens (0.5 tokens = 5e17 with 18 decimals)
    uint256 public constant COMMIT_FEE = 5e17;

    /// @notice Each token (1e18 units) = 1 NFT
    uint256 public constant UNIT_PER_FREN = 1e18;

    /// @notice Current NFT ID counter (starts at 1)
    uint256 private _nextTokenId = 1;

    /// @notice Trait data: tokenId => packedTraits (classIdx, bodyIdx, faceIdx, itemIdx)
    mapping(uint256 => uint256) public traitData;

    /// @notice Committed NFTs: tokenId => bool (true = permanent, can't be burned)
    mapping(uint256 => bool) public committed;

    /// @notice Owner's token ID: address => tokenId (0 if none)
    mapping(address => uint256) public ownerToTokenId;

    /// @notice Token ID owner: tokenId => address
    mapping(uint256 => address) private _nftOwners;

    /// @notice Random nonce for trait generation
    uint256 private _randomNonce;

    /// @notice Treasury address for commit fees
    address public treasury;

    /// @notice On-chain art renderer. When unset, tokenURI falls back to the API.
    IFrenRenderer public renderer;

    // ═══════════════════════════════════════════════════════════════════════════
    // CLASS DEFINITIONS (7 classes from MagicFrens)
    // ═══════════════════════════════════════════════════════════════════════════

    struct ClassDef {
        uint8 numBodies;
        uint8 numFaces;
        uint8 numItems;
        uint16 weight; // Cumulative weight for weighted random (out of 10000)
    }

    ClassDef[7] public classes = [
        ClassDef(8, 12, 5, 4400),   // Wizard   (44%)
        ClassDef(5, 12, 4, 6600),   // King     (22%)
        ClassDef(4, 12, 4, 8350),   // Knight   (17.5%)
        ClassDef(3, 12, 1, 8680),   // Apprentice (3.3%)
        ClassDef(3, 12, 4, 8900),   // Peasant  (2.2%) — +Robin Hood body, +Longbow item
        ClassDef(2, 12, 3, 9560),   // Gnome    (6.6%)
        ClassDef(3, 12, 1, 10000)   // Elf      (4.4%)
    ];

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event FrenMinted(address indexed owner, uint256 indexed tokenId, uint256 packedTraits);
    event FrenBurned(address indexed owner, uint256 indexed tokenId);
    event FrenCommitted(address indexed owner, uint256 indexed tokenId);
    event FrenTransferred(address indexed from, address indexed to, uint256 indexed tokenId);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _treasury
    ) ERC20("Magic Frens Peg", "MFPEG") ERC721("Magic Frens NFT", "MFNFT") Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BUY / SELL MECHANICS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Buy MagicFren tokens + mint random NFT
     * @dev Mints 1 token (1e18 units) and 1 NFT with random traits
     */
    function buyFren() external payable nonReentrant {
        require(_nextTokenId <= MAX_SUPPLY, "Max supply reached");
        require(ownerToTokenId[msg.sender] == 0, "Already own a Fren");

        // Mint 1 ERC-20 token (1e18 units)
        _mint(msg.sender, UNIT_PER_FREN);

        // Mint NFT with random traits
        uint256 tokenId = _nextTokenId++;
        uint256 packedTraits = _generateRandomTraits();

        traitData[tokenId] = packedTraits;
        ownerToTokenId[msg.sender] = tokenId;
        _nftOwners[tokenId] = msg.sender;
        _safeMint(msg.sender, tokenId);

        emit FrenMinted(msg.sender, tokenId, packedTraits);
    }

    /**
     * @notice Sell MagicFren tokens → burn NFT (unless committed)
     * @dev Burns 1 token and NFT if not committed
     */
    function sellFren() external nonReentrant {
        uint256 tokenId = ownerToTokenId[msg.sender];
        require(tokenId != 0, "No Fren to sell");
        require(balanceOf(msg.sender) >= UNIT_PER_FREN, "Insufficient tokens");

        // Burn ERC-20 tokens
        _burn(msg.sender, UNIT_PER_FREN);

        // Burn NFT only if not committed
        if (!committed[tokenId]) {
            _burn(tokenId);
            delete traitData[tokenId];
            delete ownerToTokenId[msg.sender];
            delete _nftOwners[tokenId];
            emit FrenBurned(msg.sender, tokenId);
        } else {
            // Committed NFT: keep it, just unbind from tokens
            ownerToTokenId[msg.sender] = 0;
        }

        // Transfer ETH/BNB to seller
        (bool success, ) = msg.sender.call{value: msg.value}("");
        require(success, "Transfer failed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMMIT MECHANISM
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Commit your Fren NFT forever by paying 0.5 tokens
     * @dev Makes NFT permanent (can't be burned on sell)
     */
    function commitFren() external nonReentrant {
        uint256 tokenId = ownerToTokenId[msg.sender];
        require(tokenId != 0, "No Fren to commit");
        require(!committed[tokenId], "Already committed");
        require(balanceOf(msg.sender) >= COMMIT_FEE, "Insufficient tokens for commit fee");

        // Charge commit fee (0.5 tokens)
        _transfer(msg.sender, treasury, COMMIT_FEE);

        // Mark as committed
        committed[tokenId] = true;

        emit FrenCommitted(msg.sender, tokenId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMMITTED NFT TRANSFERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Transfer a committed NFT (ERC-721 transfer)
     * @dev Only committed NFTs can be transferred independently
     */
    function transferCommittedFren(address to, uint256 tokenId) external {
        require(committed[tokenId], "NFT not committed");
        require(_nftOwners[tokenId] == msg.sender, "Not owner");
        require(to != address(0), "Invalid recipient");

        _nftOwners[tokenId] = to;
        ownerToTokenId[msg.sender] = 0;
        ownerToTokenId[to] = tokenId;

        _safeTransfer(msg.sender, to, tokenId);

        emit FrenTransferred(msg.sender, to, tokenId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRAIT GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Generate random traits using weighted class selection
     * @return Packed traits: (classIdx << 0) | (bodyIdx << 8) | (faceIdx << 16) | (itemIdx << 24)
     */
    function _generateRandomTraits() private returns (uint256) {
        _randomNonce++;

        // Weighted random class selection
        uint256 roll = _random(10000);
        uint8 classIdx;
        for (uint8 i = 0; i < 7; i++) {
            if (roll < classes[i].weight) {
                classIdx = i;
                break;
            }
        }

        // Random traits within class bounds
        ClassDef memory classDef = classes[classIdx];
        uint8 bodyIdx = uint8(_random(classDef.numBodies));
        uint8 faceIdx = uint8(_random(classDef.numFaces));
        uint8 itemIdx = uint8(_random(classDef.numItems));

        // Pack traits into single uint256
        return uint256(classIdx) | (uint256(bodyIdx) << 8) | (uint256(faceIdx) << 16) | (uint256(itemIdx) << 24);
    }

    /**
     * @notice Generate pseudo-random number
     * @dev Uses block.prevrandao, block.timestamp, and nonce
     */
    function _random(uint256 max) private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            msg.sender,
            _randomNonce
        ))) % max;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get unpacked traits for a token
     * @return classIdx bodyIdx faceIdx itemIdx
     */
    function getTraits(uint256 tokenId) external view returns (uint8, uint8, uint8, uint8) {
        uint256 packed = traitData[tokenId];
        return (
            uint8(packed & 0xFF),
            uint8((packed >> 8) & 0xFF),
            uint8((packed >> 16) & 0xFF),
            uint8((packed >> 24) & 0xFF)
        );
    }

    /**
     * @notice Check if an address owns a Fren
     */
    function hasFren(address owner) external view returns (bool) {
        return ownerToTokenId[owner] != 0;
    }

    /**
     * @notice Get Fren token ID for an address
     */
    function getFrenId(address owner) external view returns (uint256) {
        return ownerToTokenId[owner];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════════

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC-20 / ERC-721 OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Override transferFrom to resolve ERC20/ERC721 conflict
     * For ERC20 transfers, use this function. For NFT transfers, use transferCommittedFren.
     */
    function transferFrom(address from, address to, uint256 value)
        public
        virtual
        override(ERC20, IERC721)
        returns (bool)
    {
        // Default to ERC20 transferFrom behavior
        return ERC20.transferFrom(from, to, value);
    }

    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function _update(address to, uint256 amount, address from)
        internal
        virtual
        override(ERC20)
        returns (address)
    {
        return super._update(to, amount, from);
    }

    /**
     * @dev Override required by Solidity for ERC721Enumerable
     */
    function _increaseBalance(address account, uint128 value)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    /**
     * @dev Override required by Solidity for ERC721Enumerable
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Set (or update) the on-chain art renderer. Owner only.
     * @dev Pass address(0) to disable and fall back to the API metadata.
     */
    function setRenderer(address _renderer) external onlyOwner {
        renderer = IFrenRenderer(_renderer);
    }

    /**
     * @dev Returns fully on-chain metadata (base64 JSON + SVG) when a renderer
     *      is configured; otherwise falls back to the hosted API endpoint.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(ownerOf(tokenId) != address(0), "Token does not exist");

        if (address(renderer) != address(0)) {
            uint256 packed = traitData[tokenId];
            return renderer.tokenURI(
                tokenId,
                uint8(packed & 0xFF),
                uint8((packed >> 8) & 0xFF),
                uint8((packed >> 16) & 0xFF),
                uint8((packed >> 24) & 0xFF)
            );
        }

        return string(abi.encodePacked(
            "https://magicfrens.xyz/api/metadata/",
            Strings.toString(tokenId)
        ));
    }
}
