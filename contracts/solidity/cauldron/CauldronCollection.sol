// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MetadataMode, ICollectionRenderer, ICauldronCollection} from "./ICauldron.sol";
import {ICreatorToken, ITransferValidator} from "./ICreatorToken.sol";
import {ILiquidatorMintable, LiqStats} from "./ILiquidatorMintable.sol";

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
contract CauldronCollection is ERC721, ERC2981, ICreatorToken, ICauldronCollection, ILiquidatorMintable {
    using Strings for uint256;

    error OnlyMinter();
    error BadBatch();
    error OnlyVault();
    error MintedOut();
    error BadConfig();
    error VaultSet();
    error OnlyLiquidatorMinter();
    error NotReady();

    /// @notice The volume hook allowed to mint (set once, at deploy).
    address public immutable minter;

    /// @notice The CONTROLLER — the Cauldron registry. Holds custody + the governed
    ///         art/validator setters. Passed EXPLICITLY (audit H-01): inferring it
    ///         from `msg.sender` made it the FACTORY, so `custodyTransfer` (and thus
    ///         the whole legacy-floor recycle) plus every admin setter were
    ///         permanently unreachable — the factory exposes no forwarder.
    address public immutable deployer;

    /// @notice The FACTORY that deployed this collection. Keeps exactly the two
    ///         rights it needs during `deployBrew`: `setVault` and `setRoyalty`.
    address public immutable configurator;

    /// @notice The vault allowed to burn on redeem (set once, after deploy).
    address public vault;

    /// @notice Hard cap on the collection.
    uint256 public immutable maxSupply;

    /// @notice Metadata resolution mode. UPGRADABLE via `setMetadata` (deployer/
    ///         timelock) so a broken/reverting renderer can be repointed WITHOUT a
    ///         collection redeploy — art is fixable, not frozen at a bad choice.
    MetadataMode public mode;

    /// @notice On-chain renderer (mode == Renderer). Upgradable via setMetadata.
    address public renderer;

    /// @notice Base URI (mode == BaseURI). Upgradable via setMetadata.
    string private _baseTokenURI;

    uint256 public totalMinted;

    // ── Liquidatoor badges (OnChain Collectibles) ───────────────────────────
    // A trophy struck when a fren is responsible for a perp liquidation. Badges
    // are minted by the wired PerpEngine (`liquidatorMinter`) into a SEPARATE,
    // uncapped id range starting at LIQUIDATOR_ID_BASE, so awarding them never
    // touches the art tranche's `totalMinted`/`maxSupply`. Always revealed.
    uint256 public constant LIQUIDATOR_ID_BASE = 1_000_000;

    /// @notice The PerpEngine allowed to mint Liquidatoor badges (deployer-set).
    address public liquidatorMinter;

    /// @notice Count of badges struck (id = LIQUIDATOR_ID_BASE + this).
    uint256 public liquidatorMinted;

    /// @notice tokenId => whether it is a Liquidatoor badge (vs art).
    mapping(uint256 => bool) public isLiquidatoor;

    /// @notice What each badge commemorates, recorded at mint. Read by the badge
    ///         renderer so a trophy can be drawn from the chain with no server.
    mapping(uint256 => LiqStats) internal _liqStats;

    /// @notice Optional on-chain badge renderer. When set, badge tokenURI comes
    ///         from it instead of `liquidatorURI`, so badges need no API at all.
    address public liquidatorRenderer;

    /// @notice Metadata base for badges: tokenURI(badge) = liquidatorURI + id.
    string public liquidatorURI = "https://www.mifrens.xyz/api/cauldron/liquidatoor?id=";

    event LiquidatoorMinted(address indexed to, uint256 indexed tokenId);

    // ── Gacha rarity + reveal ────────────────────────────────────────────
    // Rarity tiers: 0=Common, 1=Rare, 2=Epic, 3=Ultra. Rolled at mint from an
    // on-chain seed and stored. Cumulative odds in bps (last must be 10000).
    uint16[4] public rarityCumBps = [uint16(7900), 9400, 9900, 10000];

    /// @notice tokenId => rarity tier (0..3). Set at reveal(), not mint (see below).
    mapping(uint256 => uint8) public rarityOf;

    /// @notice tokenId => the block it was minted in. The rarity is rolled at
    ///         reveal() from THIS block's hash (a value nobody can know at mint
    ///         time), so a minter can't grind rares by simulating the mint. Needed
    ///         because Arbitrum/Orbit `prevrandao` is a constant (1) — the old
    ///         mint-time seed was fully predictable there. Commit-reveal on a
    ///         future blockhash mirrors the crystal gacha's grind-resistant roll.
    mapping(uint256 => uint48) public mintBlockOf;

    /// @notice tokenId => revealed. Unrevealed tokens show the placeholder URI.
    mapping(uint256 => bool) public revealed;

    /// @notice Placeholder metadata shown before reveal.
    string public unrevealedURI = "https://www.mifrens.xyz/api/cauldron/unrevealed";

    event Minted(address indexed to, uint256 indexed tokenId, uint8 rarity);
    event Revealed(uint256 indexed tokenId, uint8 rarity);
    /// @notice The reveal seed expired (>256 blocks); re-anchored to a fresh block
    ///         rather than rolling from a predictable fallback (audit M-03).
    event ReAnchored(uint256 indexed tokenId, uint48 newMintBlock);

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
        address registry_,
        uint256 maxSupply_,
        MetadataMode mode_,
        string memory baseURI_,
        address renderer_,
        address royaltyReceiver_,
        uint96 royaltyBps_
    ) ERC721(name_, symbol_) {
        // maxSupply must stay below the badge id range so art and Liquidatoor
        // badge ids can never collide. (Audit L-01)
        if (minter_ == address(0) || registry_ == address(0)) revert BadConfig();
        if (maxSupply_ == 0 || maxSupply_ >= LIQUIDATOR_ID_BASE) revert BadConfig();
        if (mode_ == MetadataMode.Renderer) {
            if (renderer_ == address(0) || renderer_.code.length == 0) revert BadConfig();
        } else {
            if (bytes(baseURI_).length == 0) revert BadConfig();
        }
        require(royaltyBps_ <= 1000, "royalty too high"); // <= 10%
        minter = minter_;
        deployer = registry_;      // the CONTROLLER (audit H-01), not the factory
        configurator = msg.sender; // the factory, for its two deploy-time setters
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
    ///         Mints UNREVEALED and records the mint block; the gacha rarity is
    ///         rolled later in reveal() from that block's future hash, so it can't
    ///         be predicted (and grinded) at mint time.
    function mint(address to) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert OnlyMinter();
        if (totalMinted >= maxSupply) revert MintedOut();
        tokenId = ++totalMinted; // 1-indexed

        mintBlockOf[tokenId] = uint48(block.number); // commit; rarity rolled at reveal
        _mint(to, tokenId);
        emit Minted(to, tokenId, 0); // rarity provisional (0) until revealed
    }

    /// @notice Reveal a token you own — rolls its rarity from the mint block's
    ///         hash (unknowable at mint → grind-resistant) and flips the metadata.
    function reveal(uint256 tokenId) external {
        _reveal(tokenId);
    }

    /**
     * @notice Reveal many tokens in ONE transaction.
     * @dev Revealing was one token per transaction, so a holder with thirty
     *      crystals paid thirty base fees (21,000 gas each) to see what they
     *      already owned. The per-token work is identical either way; batching
     *      simply stops paying for a transaction over and over.
     *
     *      The RANDOMNESS IS UNCHANGED. Each token still rolls from its own
     *      mint block's hash, so a batch is exactly N independent draws — there
     *      is no shared seed to grind and no new way to influence an outcome.
     *
     *      Already-revealed ids are skipped rather than reverting, so a caller
     *      can pass their whole wallet without first filtering it. A token whose
     *      seed has expired re-anchors and the batch continues, matching the
     *      single-token behaviour (audit M-03).
     */
    function revealBatch(uint256[] calldata tokenIds) external {
        uint256 n = tokenIds.length;
        // Bounded so a caller cannot build a batch that runs out of gas midway
        // and wastes the whole fee.
        if (n == 0 || n > 50) revert BadBatch();
        for (uint256 i; i < n; ++i) _reveal(tokenIds[i]);
    }

    function _reveal(uint256 tokenId) private {
        if (ownerOf(tokenId) != msg.sender) revert OnlyMinter();
        if (!revealed[tokenId]) {
            uint256 mb = mintBlockOf[tokenId];
            if (block.number <= mb) revert NotReady(); // seed not known yet
            bytes32 bh = blockhash(mb);
            // EXPIRED SEED (audit M-03): `blockhash` only reaches back ~256 blocks.
            // Substituting a DETERMINISTIC fallback here handed the holder a SECOND,
            // fully-predictable draw — computable at mint time — so they could
            // simply wait out the window whenever the first roll was poor and take
            // the better of two. With the default tiers that lifts P(>= Rare) from
            // 21% to ~37.6% and roughly DOUBLES the top tier.
            // Instead we RE-ANCHOR to a fresh future block: the token stays
            // revealable forever, but there is always exactly ONE unknowable draw.
            // NOTE: we must NOT revert here — a revert would roll the re-anchor
            // back, leaving the token stuck. Return quietly instead; the holder
            // (or a keeper) calls reveal() again once the new block is mined.
            if (bh == 0) {
                mintBlockOf[tokenId] = uint48(block.number);
                emit ReAnchored(tokenId, uint48(block.number));
                return;
            }
            uint8 rarity = _rollRarity(uint256(keccak256(abi.encodePacked(bh, tokenId, address(this)))));
            rarityOf[tokenId] = rarity;
            revealed[tokenId] = true;
            emit Revealed(tokenId, rarity);
        }
    }

    function _rollRarity(uint256 seed) private view returns (uint8) {
        uint16 r = uint16(seed % 10_000);
        for (uint8 i = 0; i < 4; i++) {
            if (r < rarityCumBps[i]) return i;
        }
        return 0;
    }

    /// @notice One-time wiring of the floor vault. Callable by the FACTORY (which
    ///         does it inside `deployBrew`) or the registry.
    function setVault(address _vault) external {
        if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter();
        if (vault != address(0)) revert VaultSet();
        vault = _vault;
    }

    /// @notice Re-point the EIP-2981 royalty receiver (deployer only). The factory
    ///         calls this right after wiring the vault so a volume collection's
    ///         secondary-sale royalties flow to its OWN floor vault — its secondary
    ///         volume backs its own floor (and, at death, its legacy entitlement).
    function setRoyalty(address receiver, uint96 bps) external {
        if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter();
        require(bps <= 1000, "royalty too high"); // <= 10%
        _setDefaultRoyalty(receiver, bps);
    }

    /// @notice Wire (or re-point) the PerpEngine allowed to mint Liquidatoor
    ///         badges. Callable by the deployer OR the `minter` (the volume hook)
    ///         — so the hook can AUTO-WIRE badges on every summon/relaunch with
    ///         no manual step. Re-settable so a redeployed engine can swap in.
    function setLiquidatorMinter(address _minter) external {
        if (msg.sender != deployer && msg.sender != minter) revert OnlyMinter();
        liquidatorMinter = _minter;
    }

    /// @notice UPGRADE the art source (deployer/timelock only): switch mode and set
    ///         the renderer (Renderer mode) or base URI (BaseURI mode). Lets a
    ///         broken/reverting renderer be repointed to a working one — or to a
    ///         BaseURI art endpoint — WITHOUT redeploying the collection. Governed,
    ///         so it fixes art, it can't silently rug the proposer's choice.
    function setMetadata(MetadataMode _mode, address _renderer, string calldata baseURI_) external {
        if (msg.sender != deployer) revert OnlyMinter();
        if (_mode == MetadataMode.Renderer) {
            if (_renderer == address(0) || _renderer.code.length == 0) revert BadConfig();
            renderer = _renderer;
        } else {
            _baseTokenURI = baseURI_;
        }
        mode = _mode;
    }

    /// @notice Update the Liquidatoor metadata base (deployer only).
    function setLiquidatorURI(string calldata uri) external {
        if (msg.sender != deployer) revert OnlyMinter();
        liquidatorURI = uri;
    }

    /// @notice Mint a Liquidatoor badge to `to`. Only the wired PerpEngine.
    ///         Uncapped, always revealed, in the LIQUIDATOR_ID_BASE id range so
    ///         it never consumes the art supply.
    function mintLiquidator(address to) external returns (uint256 tokenId) {
        return _mintLiquidator(to, LiqStats(address(0), false, 0, 0, 0, 0, 0, 0));
    }

    /// @notice Mint a badge AND record the liquidation it commemorates, so the
    ///         renderer can draw the real numbers rather than a placeholder.
    function mintLiquidatorWithStats(address to, LiqStats calldata st)
        external
        returns (uint256 tokenId)
    {
        return _mintLiquidator(to, st);
    }

    function _mintLiquidator(address to, LiqStats memory st) internal returns (uint256 tokenId) {
        if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter();
        tokenId = LIQUIDATOR_ID_BASE + (++liquidatorMinted);
        isLiquidatoor[tokenId] = true;
        // Only pay for the write when there is something to record: a stats-free
        // mint from an older engine must stay as cheap as it was.
        if (st.victim != address(0)) _liqStats[tokenId] = st;
        _mint(to, tokenId);
        emit LiquidatoorMinted(to, tokenId);
    }

    /// @inheritdoc ILiquidatorMintable
    function liqStats(uint256 tokenId) external view returns (LiqStats memory) {
        return _liqStats[tokenId];
    }

    /// @notice Point badge metadata at an on-chain renderer (address(0) = use
    ///         `liquidatorURI`).
    /// @dev Accepts the CONFIGURATOR as well as the deployer, exactly like
    ///      {setRoyalty}. The factory is the configurator and is the only party
    ///      that can set this at the moment a collection is created — `deployer`
    ///      is the REGISTRY (audit H-01), not the factory, so a deployer-only
    ///      guard made the factory's call revert OnlyMinter and took the whole
    ///      summon down with it.
    function setLiquidatorRenderer(address r) external {
        if (msg.sender != configurator && msg.sender != deployer) revert OnlyMinter();
        liquidatorRenderer = r;
    }

    /// @notice Marketplace/API helper: the Liquidatoor trait for a token.
    function liquidatoorTrait(uint256 tokenId) external view returns (string memory) {
        return isLiquidatoor[tokenId] ? "true" : "false";
    }

    /// @notice Burn a token on redemption. Only the vault may call.
    function burnFromVault(uint256 tokenId) external {
        if (msg.sender != vault) revert OnlyVault();
        _burn(tokenId);
    }

    /// @notice Registry-gated transfer with NO approval — used by the legacy-floor
    ///         recycle: move a redeemed volume NFT into the treasury (the registry)
    ///         and later back out to a buyer. The registry (this contract's
    ///         `deployer`) verifies ownership before calling. Never burns — the
    ///         collection size is preserved; the NFT just recycles.
    function custodyTransfer(address from, address to, uint256 tokenId) external {
        if (msg.sender != deployer) revert OnlyVault();
        _transfer(from, to, tokenId);
    }

    /// @inheritdoc ERC721
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        // Liquidatoor badges resolve to their own metadata (always revealed).
        if (isLiquidatoor[tokenId]) {
            // Fully on-chain when a renderer is wired; otherwise the URI base.
            if (liquidatorRenderer != address(0)) {
                return ICollectionRenderer(liquidatorRenderer).tokenURI(tokenId);
            }
            return string.concat(liquidatorURI, tokenId.toString());
        }
        // Unrevealed art tokens show the placeholder.
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
