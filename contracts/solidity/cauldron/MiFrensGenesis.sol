// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {MetadataMode, ICollectionRenderer} from "./ICauldron.sol";
import {ICreatorToken, ITransferValidator} from "./ICreatorToken.sol";

interface IRegistrySummon {
    function summon() external payable returns (address token, bytes32 poolId);
    function summoned() external view returns (bool);
}

interface IMiFrensDividendHook {
    function onMiFrenTransfer(uint256 tokenId, address from) external;
}

/**
 * @title MiFrensGenesis
 * @notice The founding guild + autonomous ignition for the Cauldron.
 *
 *  Every mint is an ERC721 MiFren (the governance electorate). ETH accrues in
 *  this contract. The moment the guild mints out (`minted == MAX_SUPPLY`),
 *  `finalize()` becomes callable by ANYONE — it forwards the entire treasury to
 *  `registry.summon{value: balance}()`, which deploys the first eternal token
 *  and seeds its Uniswap V4 pool. There is NO owner withdraw path: the funds can
 *  only ever go one place — into the first brew's liquidity.
 *
 *  Autonomy wiring: after deploy, the CauldronRegistry's ownership is
 *  transferred to this contract, so `finalize()` (and only it) can summon.
 *
 *  ── CANONICAL MIFRENS COLLECTION ──────────────────────────────────────────
 *  This IS the Magic Internet Frens NFT collection, not just a fundraise.
 *  The presale mints the OG "rare" tranche (tokenIds 1..GENESIS_SUPPLY) for
 *  ETH. Later, ITERATION #2 of the Cauldron ($MIF) keeps minting the SAME
 *  collection from swap VOLUME — the registry wires the volume hook in as
 *  `minter`, and it mints tokenIds GENESIS_SUPPLY+1..MAX_SUPPLY (the rest of
 *  the art). Iterations #1 (Gnomeland) and #3+ each deploy their own separate
 *  collection; only iteration #2 continues this one. Volume mints roll a gacha
 *  rarity and mint unrevealed; the OG genesis tranche is always revealed.
 */
contract MiFrensGenesis is ERC721, ERC721Votes, ERC2981, ICreatorToken, ReentrancyGuard {
    using Strings for uint256;

    error PresaleOver();
    error WrongPrice();
    error ExceedsSupply();
    error PerWalletCap();
    error NotSoldOut();
    error AlreadyFinalized();
    error RegistryNotSet();
    error RegistryAlreadySet();
    error ZeroAddress();
    error OnlyMinter();
    error OnlyVault();
    error NotAuthorized();
    error MintedOut();
    error NotCancelled();
    error AlreadyCancelled();
    error NothingToRefund();
    error RefundFailed();

    // -----------------------------------------------------------------------
    // Config
    // -----------------------------------------------------------------------
    uint256 public immutable GENESIS_SUPPLY;  // OG rare tranche sold in presale (e.g. 1111)
    uint256 public immutable MAX_SUPPLY;      // total art cap incl. volume mints (e.g. 2400)
    uint256 public immutable PRICE;           // ETH per MiFren
    uint256 public immutable MAX_PER_WALLET;  // anti-whale cap

    /// @notice The registry this presale ignites on sellout (and which wires the
    ///         volume hook as `minter` when iteration #2 continues this brew).
    IRegistrySummon public registry;

    /// @notice Deployer, allowed ONLY to wire the registry once (no funds power).
    address public immutable deployer;

    /// @notice The volume hook allowed to mint the post-genesis tranche. Set by
    ///         the registry when iteration #2 continues this collection.
    address public minter;

    /// @notice The floor vault allowed to burn on redemption (per-iteration).
    address public vault;

    /// @notice The genesis fee dividend. Transferring a genesis fren pings it so
    ///         the fren's "cast the spell" enchantment breaks (see _update).
    address public dividend;

    uint256 public minted;
    bool public finalized;

    /// @notice If the genesis never sells out, the deployer can CANCEL it and
    ///         every minter reclaims their full ETH via refund(). Protects buyers
    ///         from funds being trapped in a stalled presale (finalize needs the
    ///         full sellout). Once cancelled, minting stops and only refunds run.
    bool public cancelled;
    /// @notice ETH each address paid in — the exact amount refundable on cancel.
    mapping(address => uint256) public paid;

    event PresaleCancelled();
    event Refunded(address indexed buyer, uint256 amount);

    /// @notice If set, ONLY this address may call the one-time genesis `finalize()`
    ///         (ignition of iteration #1). Lets the team guarantee they are the
    ///         one that summons + makes the atomic launch buy, so a bot can't
    ///         front-run the ignition. Zero = permissionless (default). This gates
    ///         ONLY genesis ignition; relaunches (gen 2+) stay permissionless.
    address public finalizer;
    string private _base;

    // ── Configurable metadata (on-chain renderer or off-chain baseURI) ───────
    MetadataMode public mode;   // BaseURI (default) or Renderer

    // ── EIP-2981 royalties (→ genesis dividend) + ERC-721C enforcement ──────
    /// @notice ERC-721C transfer validator. Secondary-sale royalties on this
    ///         collection (genesis + iter #2 MiFrens) go to the genesis dividend
    ///         via ERC2981; when a validator is set, a market that doesn't pay is
    ///         BLOCKED from transferring — enforcing the fee. Zero = unrestricted.
    address public transferValidator;
    address public renderer;    // used when mode == Renderer

    // ── Gacha rarity + reveal (volume tranche only; genesis is always revealed)
    // Tiers: 0=Common,1=Rare,2=Epic,3=Ultra. Cumulative bps, last == 10000.
    uint16[4] public rarityCumBps = [uint16(7900), 9400, 9900, 10000];
    mapping(uint256 => uint8) public rarityOf;
    mapping(uint256 => bool) public revealed;
    string public unrevealedURI = "https://magicfrens.xyz/api/mifren/unrevealed";

    event Bought(address indexed buyer, uint256 quantity, uint256 firstTokenId);
    event Finalized(address indexed caller, address token, uint256 seededETH);
    event VolumeMinted(address indexed to, uint256 indexed tokenId, uint8 rarity);
    event Revealed(uint256 indexed tokenId, uint8 rarity);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 genesisSupply_,
        uint256 maxSupply_,
        uint256 price_,
        uint256 maxPerWallet_,
        string memory baseURI_
    ) ERC721(name_, symbol_) EIP712(name_, "1") {
        if (genesisSupply_ == 0 || price_ == 0 || maxPerWallet_ == 0) revert ZeroAddress();
        if (maxSupply_ < genesisSupply_) revert ExceedsSupply();
        GENESIS_SUPPLY = genesisSupply_;
        MAX_SUPPLY = maxSupply_;
        PRICE = price_;
        MAX_PER_WALLET = maxPerWallet_;
        _base = baseURI_;
        deployer = msg.sender;
    }

    /// @notice One-time wiring of the registry (which this presale must own).
    function setRegistry(address _registry) external {
        if (msg.sender != deployer) revert ZeroAddress();
        if (address(registry) != address(0)) revert RegistryAlreadySet();
        if (_registry == address(0)) revert ZeroAddress();
        registry = IRegistrySummon(_registry);
    }

    // -----------------------------------------------------------------------
    // Presale
    // -----------------------------------------------------------------------

    /// @notice Mint `quantity` OG MiFrens from the genesis (rare) tranche.
    ///         Exact payment required. Genesis mints are revealed immediately.
    function mint(uint256 quantity) external payable nonReentrant {
        if (finalized) revert PresaleOver();
        if (cancelled) revert AlreadyCancelled();
        if (quantity == 0) revert ExceedsSupply();
        if (minted + quantity > GENESIS_SUPPLY) revert ExceedsSupply();
        if (msg.value != PRICE * quantity) revert WrongPrice();
        if (balanceOf(msg.sender) + quantity > MAX_PER_WALLET) revert PerWalletCap();

        paid[msg.sender] += msg.value; // track for a possible refund on cancel

        uint256 first = minted + 1;
        for (uint256 i = 0; i < quantity; i++) {
            uint256 id = minted + 1;
            revealed[id] = true; // OG tranche is revealed on mint
            _mint(msg.sender, id);
            minted++;
        }
        emit Bought(msg.sender, quantity, first);
    }

    /// @notice Deployer safety valve: cancel a stalled genesis so minters can be
    ///         made whole. Only pre-finalize (once summoned, ETH is in the LP and
    ///         this is moot). Irreversible; stops minting and opens refunds.
    function cancelPresale() external {
        if (msg.sender != deployer) revert NotAuthorized();
        if (finalized) revert PresaleOver();
        if (cancelled) revert AlreadyCancelled();
        cancelled = true;
        emit PresaleCancelled();
    }

    /// @notice After a cancel, reclaim 100% of the ETH you paid. Your genesis
    ///         NFTs are left in place (the collection never launches, so they are
    ///         orphaned art) — no double-spend: `paid` is zeroed before the send.
    function refund() external nonReentrant returns (uint256 amount) {
        if (!cancelled) revert NotCancelled();
        amount = paid[msg.sender];
        if (amount == 0) revert NothingToRefund();
        paid[msg.sender] = 0; // effects before interaction (CEI)
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert RefundFailed();
        emit Refunded(msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // Collection surface — iteration #2 mints the rest of the art by VOLUME
    // -----------------------------------------------------------------------

    /// @notice ICauldronCollection: total minted (genesis + volume).
    function totalMinted() external view returns (uint256) {
        return minted;
    }

    /// @notice ICauldronCollection: total art cap.
    function maxSupply() external view returns (uint256) {
        return MAX_SUPPLY;
    }

    /// @dev Only the deployer (pre-ignition) or the wired registry may configure.
    modifier onlyDeployerOrRegistry() {
        if (msg.sender != deployer && msg.sender != address(registry)) revert NotAuthorized();
        _;
    }

    /// @notice Wire the volume hook as the post-genesis minter (registry, on
    ///         iteration #2 continuation). Re-settable so a later brew can never
    ///         be minted by a stale hook — but only registry/deployer may set it.
    function setMinter(address _minter) external onlyDeployerOrRegistry {
        minter = _minter;
    }

    /// @notice Wire this iteration's floor vault (registry, per continuation).
    function setVault(address _vault) external onlyDeployerOrRegistry {
        vault = _vault;
    }

    /// @notice Wire the genesis fee dividend so genesis transfers break the spell.
    function setDividend(address _dividend) external onlyDeployerOrRegistry {
        dividend = _dividend;
    }

    /// @notice Restrict who may call the one-time `finalize()` (deployer only,
    ///         pre-ignition). Set to the LaunchSniper so ignition + the funding
    ///         buy happen atomically and no bot can front-run the summon. Once
    ///         finalized this is irrelevant. Zero = anyone (default).
    function setFinalizer(address _finalizer) external {
        if (msg.sender != deployer) revert NotAuthorized();
        finalizer = _finalizer;
    }

    /// @notice Configure metadata resolution: on-chain renderer or baseURI.
    function setMetadata(MetadataMode _mode, address _renderer, string calldata baseURI_)
        external
    {
        if (msg.sender != deployer) revert NotAuthorized();
        mode = _mode;
        renderer = _renderer;
        if (bytes(baseURI_).length != 0) _base = baseURI_;
    }

    /// @notice Configure the gacha odds (cumulative bps, ascending, last==10000).
    function setRarityOdds(uint16[4] calldata cum) external {
        if (msg.sender != deployer) revert NotAuthorized();
        require(cum[3] == 10_000 && cum[0] <= cum[1] && cum[1] <= cum[2] && cum[2] <= cum[3], "odds");
        rarityCumBps = cum;
    }

    /// @notice Wire the EIP-2981 royalty receiver (the genesis dividend) + rate.
    function setRoyalty(address receiver, uint96 bps) external {
        if (msg.sender != deployer) revert NotAuthorized();
        require(bps <= 1000, "royalty too high"); // <= 10%
        _setDefaultRoyalty(receiver, bps);
    }

    // ── ERC-721C creator token: enforced-royalty transfers ───────────────────

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
        if (msg.sender != deployer) revert NotAuthorized();
        emit TransferValidatorUpdated(transferValidator, validator);
        transferValidator = validator;
    }

    /// @notice Mint the next NFT to `to` from swap VOLUME. Only the wired hook.
    ///         Rolls gacha rarity on-chain; mints UNREVEALED.
    function mint(address to) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert OnlyMinter();
        if (minted >= MAX_SUPPLY) revert MintedOut();
        tokenId = minted + 1;
        minted++;

        uint256 seed = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1), block.prevrandao, to, tokenId, address(this)
        )));
        uint8 rarity = _rollRarity(seed);
        rarityOf[tokenId] = rarity;

        _mint(to, tokenId);
        emit VolumeMinted(to, tokenId, rarity);
    }

    /// @notice Reveal a volume-tranche token you own.
    function reveal(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert OnlyMinter();
        if (!revealed[tokenId]) {
            revealed[tokenId] = true;
            emit Revealed(tokenId, rarityOf[tokenId]);
        }
    }

    /// @notice Burn a token on floor redemption. Only the active vault.
    function burnFromVault(uint256 tokenId) external {
        if (msg.sender != vault) revert OnlyVault();
        _burn(tokenId);
    }

    function _rollRarity(uint256 seed) private view returns (uint8) {
        uint16 r = uint16(seed % 10_000);
        for (uint8 i = 0; i < 4; i++) {
            if (r < rarityCumBps[i]) return i;
        }
        return 0;
    }

    // -----------------------------------------------------------------------
    // Ignition — permissionless on sellout
    // -----------------------------------------------------------------------

    /**
     * @notice Once minted out, forward the whole treasury to summon the first
     *         eternal token. Callable by anyone; funds have no other exit.
     */
    function finalize() external nonReentrant returns (address token) {
        if (address(registry) == address(0)) revert RegistryNotSet();
        if (finalized) revert AlreadyFinalized();
        if (minted < GENESIS_SUPPLY) revert NotSoldOut();
        // If a finalizer is set, only it may ignite → guarantees the team's
        // atomic summon+buy can't be front-run by a bot calling finalize first.
        if (finalizer != address(0) && msg.sender != finalizer) revert NotAuthorized();

        finalized = true;
        uint256 bal = address(this).balance;
        (token, ) = registry.summon{value: bal}();
        emit Finalized(msg.sender, token, bal);
    }

    // -----------------------------------------------------------------------
    // Views
    // -----------------------------------------------------------------------

    /// @notice The presale (genesis tranche) is sold out — ignition is armed.
    function soldOut() external view returns (bool) {
        return minted >= GENESIS_SUPPLY;
    }

    /// @notice OG tranche remaining in the presale.
    function remaining() external view returns (uint256) {
        return minted >= GENESIS_SUPPLY ? 0 : GENESIS_SUPPLY - minted;
    }

    /// @notice The permanent OG mark. True for the founding genesis tranche
    ///         (tokenIds 1..GENESIS_SUPPLY). Immutable — derived from the id and
    ///         the immutable GENESIS_SUPPLY, so it can never be faked, moved, or
    ///         minted into later. Genesis MiFrens are the canonical OGs: they
    ///         carry the perpetual fee dividend + governance, and metadata
    ///         surfaces this as a "Genesis" trait. Later, volume-minted MiFrens
    ///         (ids > GENESIS_SUPPLY) are Standard.
    function isGenesis(uint256 tokenId) public view returns (bool) {
        return tokenId != 0 && tokenId <= GENESIS_SUPPLY;
    }

    /// @notice Human-readable tier for metadata / marketplaces: "Genesis" for the
    ///         OG 1111, else the rolled rarity tier. Lets the renderer or the
    ///         metadata API stamp the OG trait straight from on-chain truth.
    function ogTrait(uint256 tokenId) external view returns (string memory) {
        return isGenesis(tokenId) ? "Genesis" : "Standard";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        // Volume-tranche tokens show the placeholder until revealed; the OG
        // genesis tranche is always revealed.
        if (tokenId > GENESIS_SUPPLY && !revealed[tokenId]) return unrevealedURI;
        if (mode == MetadataMode.Renderer && renderer != address(0)) {
            return ICollectionRenderer(renderer).tokenURI(tokenId);
        }
        return bytes(_base).length == 0 ? "" : string.concat(_base, tokenId.toString());
    }

    // -----------------------------------------------------------------------
    // ERC721Votes plumbing
    // -----------------------------------------------------------------------

    /// @dev Resolve the ERC721 / ERC721Votes diamond and auto-delegate holders
    ///      to themselves on first receipt, so voting power is live without a
    ///      separate delegate() tx. Because votes are checkpointed, transferring
    ///      an NFT moves its voting power — it can never double-count.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Votes)
        returns (address)
    {
        // ERC-721C: a set validator vets every move (mint/transfer/burn), so a
        // non-paying market is blocked — enforcing the royalty. Zero = free.
        address v = transferValidator;
        if (v != address(0)) {
            ITransferValidator(v).validateTransfer(_msgSender(), _ownerOf(tokenId), to, tokenId);
        }
        address from = super._update(to, tokenId, auth);
        if (to != address(0) && delegates(to) == address(0)) {
            _delegate(to, to);
        }
        // Any move of a genesis fren breaks its fee-enchantment (the dividend
        // settles the leaver + frees its active share). try/catch so the dividend
        // can never brick an NFT transfer.
        if (from != address(0) && tokenId <= GENESIS_SUPPLY && dividend != address(0)) {
            try IMiFrensDividendHook(dividend).onMiFrenTransfer(tokenId, from) {} catch {}
        }
        return from;
    }

    function _increaseBalance(address account, uint128 amount)
        internal
        override(ERC721, ERC721Votes)
    {
        super._increaseBalance(account, amount);
    }

    /// @inheritdoc ERC721
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return interfaceId == type(ICreatorToken).interfaceId || super.supportsInterface(interfaceId);
    }
}
