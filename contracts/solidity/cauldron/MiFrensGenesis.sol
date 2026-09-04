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
import {ILiquidatorMintable, LiqStats} from "./ILiquidatorMintable.sol";

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
contract MiFrensGenesis is ERC721, ERC721Votes, ERC2981, ICreatorToken, ILiquidatorMintable, ReentrancyGuard {
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
    error OnlyLiquidatorMinter();
    error NotAuthorized();
    error MintedOut();
    error NotReady();
    error NotCancelled();
    error AlreadyCancelled();
    error NothingToRefund();
    error RefundFailed();
    /// @notice The caller did not leave enough gas for the dividend enchantment hook
    ///         to run, so the transfer is refused rather than silently breaking the
    ///         fee accounting. See {_update} (audit F-09).
    error InsufficientGas();

    /// @dev Gas the dividend hook is forwarded, and the floor the caller must leave
    ///      before {_update} will attempt it. See {_update} (audit F-09).
    uint256 private constant GAS_DIVIDEND_FWD = 60_000;
    uint256 private constant GAS_DIVIDEND_MIN = 80_000;

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

    // ── Liquidatoor badges (OnChain Collectibles) ───────────────────────────
    // A trophy struck when a fren is responsible for a perp liquidation, minted
    // by the wired PerpEngine (`liquidatorMinter`) into a SEPARATE, uncapped id
    // range at LIQUIDATOR_ID_BASE — so it never consumes the art tranche's
    // supply. NOTE: this collection is ERC721Votes, so a badge carries ONE
    // governance vote, exactly like a volume-minted MiFren (badges are earned by
    // real, capital-at-risk liquidations, not cheaply farmable). It is never
    // "Genesis" (isGenesis is derived from id <= GENESIS_SUPPLY) and never draws
    // the genesis fee dividend.
    uint256 public constant LIQUIDATOR_ID_BASE = 1_000_000;

    /// @notice The PerpEngine allowed to mint Liquidatoor badges (deployer/registry).
    address public liquidatorMinter;

    /// @notice Count of badges struck (id = LIQUIDATOR_ID_BASE + this).
    uint256 public liquidatorMinted;

    /// @notice tokenId => whether it is a Liquidatoor badge (vs a MiFren).
    mapping(uint256 => bool) public isLiquidatoor;

    /// @notice What each badge commemorates, recorded at mint.
    mapping(uint256 => LiqStats) internal _liqStats;

    /// @notice Optional on-chain badge renderer. When set, badge tokenURI comes
    ///         from it instead of `liquidatorURI`. One renderer instance serves
    ///         every collection: it reads the stats back off its caller.
    address public liquidatorRenderer;

    /// @notice Metadata base for badges: tokenURI(badge) = liquidatorURI + id.
    ///         Shared endpoint — a Liquidatoor badge looks the same on every
    ///         collection (proof-of-kill), so both this and the per-brew
    ///         collections point at the one /api/cauldron/liquidatoor route.
    string public liquidatorURI = "https://www.mifrens.xyz/api/cauldron/liquidatoor?id=";

    event LiquidatoorMinted(address indexed to, uint256 indexed tokenId);

    // ── Gacha rarity + reveal (volume tranche only; genesis is always revealed)
    // Tiers: 0=Common,1=Rare,2=Epic,3=Ultra. Cumulative bps, last == 10000.
    uint16[4] public rarityCumBps = [uint16(7900), 9400, 9900, 10000];
    mapping(uint256 => uint8) public rarityOf;
    mapping(uint256 => bool) public revealed;
    /// @notice tokenId => mint block. Rarity is rolled at reveal() from this
    ///         block's future hash (unknowable at mint) so it can't be grinded —
    ///         essential on Arbitrum/Orbit where `prevrandao` is a constant.
    mapping(uint256 => uint48) public mintBlockOf;
    string public unrevealedURI = "https://www.mifrens.xyz/api/cauldron/unrevealed";

    event Bought(address indexed buyer, uint256 quantity, uint256 firstTokenId);
    event Finalized(address indexed caller, address token, uint256 seededETH);
    event VolumeMinted(address indexed to, uint256 indexed tokenId, uint8 rarity);
    event Revealed(uint256 indexed tokenId, uint8 rarity);
    /// @notice The reveal seed expired (>256 blocks); re-anchored to a fresh block
    ///         rather than rolling from a predictable fallback (audit M-03).
    event ReAnchored(uint256 indexed tokenId, uint48 newMintBlock);

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
        // maxSupply below the badge id range so art + Liquidatoor badge ids can
        // never collide. (Audit L-01)
        if (maxSupply_ < genesisSupply_ || maxSupply_ >= LIQUIDATOR_ID_BASE) revert ExceedsSupply();
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

        // Gas: cache `minted` in memory, increment locally, write back ONCE — the
        // loop touched storage every iteration (up to MAX_PER_WALLET times/mint).
        uint256 m = minted;
        uint256 first = m + 1;
        for (uint256 i = 0; i < quantity;) {
            uint256 id = first + i;
            revealed[id] = true; // OG tranche is revealed on mint
            _mint(msg.sender, id);
            unchecked { ++i; }
        }
        minted = m + quantity;
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

    /// @notice Wire (or re-point) the PerpEngine allowed to mint Liquidatoor
    ///         badges. Deployer/registry OR the `minter` (the volume hook, set on
    ///         iteration #2 continuation) — so the hook can auto-wire badges on
    ///         relaunch. Re-settable for engine redeploys.
    function setLiquidatorMinter(address _minter) external {
        if (msg.sender != deployer && msg.sender != address(registry) && msg.sender != minter) revert NotAuthorized();
        liquidatorMinter = _minter;
    }

    /// @notice Update the Liquidatoor metadata base (deployer only).
    function setLiquidatorURI(string calldata uri) external {
        if (msg.sender != deployer) revert NotAuthorized();
        liquidatorURI = uri;
    }

    /// @notice Mint a Liquidatoor badge to `to`. Only the wired PerpEngine.
    ///         Uncapped, always revealed, in the LIQUIDATOR_ID_BASE id range so
    ///         it never consumes the MiFren art supply.
    function mintLiquidator(address to) external returns (uint256 tokenId) {
        return _mintLiquidator(to, LiqStats(address(0), false, 0, 0, 0, 0, 0, 0));
    }

    /// @notice Mint a badge AND record the liquidation it commemorates.
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
        // Only pay for the write when there is something to record.
        if (st.victim != address(0)) _liqStats[tokenId] = st;
        _mint(to, tokenId);
        emit LiquidatoorMinted(to, tokenId);
    }

    /// @inheritdoc ILiquidatorMintable
    function liqStats(uint256 tokenId) external view returns (LiqStats memory) {
        return _liqStats[tokenId];
    }

    /// @notice Point badge metadata at an on-chain renderer (0 = liquidatorURI).
    function setLiquidatorRenderer(address r) external {
        if (msg.sender != deployer) revert NotAuthorized();
        liquidatorRenderer = r;
    }

    /// @notice Marketplace/API helper: the Liquidatoor trait for a token.
    function liquidatoorTrait(uint256 tokenId) external view returns (string memory) {
        return isLiquidatoor[tokenId] ? "true" : "false";
    }

    /// @notice tokenId => whether it has EVER moved (recycled or transferred). Set
    ///         once on the first non-mint transfer (see _update). Gates the paid
    ///         re-enchant: original never-moved OGs enchant FREE; a moved fren pays.
    mapping(uint256 => bool) public everMoved;

    /// @notice Registry-gated transfer with NO approval required — the registry
    ///         verifies ownership before calling. Used by the recycle-redemption:
    ///         move a redeemed fren into the treasury (the registry) and later back
    ///         out to a buyer. Routes through `_update`, which breaks the fee
    ///         dividend spell (the from!=0 ping), moves the ERC721Votes power, and
    ///         marks everMoved. The fren is NEVER burned — the collection stays 1111.
    function custodyTransfer(address from, address to, uint256 tokenId) external {
        if (msg.sender != address(registry)) revert NotAuthorized();
        _transfer(from, to, tokenId);
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
    ///         Mints UNREVEALED + records the mint block; rarity is rolled at
    ///         reveal() from that block's future hash (grind-resistant).
    function mint(address to) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert OnlyMinter();
        if (minted >= MAX_SUPPLY) revert MintedOut();
        tokenId = minted + 1;
        minted++;

        mintBlockOf[tokenId] = uint48(block.number); // commit; rarity rolled at reveal
        _mint(to, tokenId);
        emit VolumeMinted(to, tokenId, 0); // rarity provisional (0) until revealed
    }

    /// @notice Reveal a volume-tranche token you own — rolls its rarity from the
    ///         mint block's hash (unknowable at mint → grind-resistant).
    function reveal(uint256 tokenId) external {
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
        // Liquidatoor badges resolve to their own metadata (always revealed).
        if (isLiquidatoor[tokenId]) {
            if (liquidatorRenderer != address(0)) {
                return ICollectionRenderer(liquidatorRenderer).tokenURI(tokenId);
            }
            return string.concat(liquidatorURI, tokenId.toString());
        }
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
        // Any move of an ENCHANTED fren breaks its fee-enchantment (the dividend
        // settles the leaver + frees its active share). try/catch so the dividend
        // can never brick an NFT transfer.
        //
        // NOT gated on GENESIS_SUPPLY (audit M-06). The dividend's eligibility cap
        // is MAX_TOKEN, so FORGED frens (ids > GENESIS_SUPPLY, minted by volume on
        // the iteration-#2 continuation) can enchant and earn too. Skipping the ping
        // for them meant a sold forged fren kept its active share forever: it
        // diluted every honest holder, the new owner could not claim, and when they
        // finally re-cast, the accrual earned WHILE THEY OWNED IT was credited to
        // the SELLER — a repeatable backwards transfer of value.
        // The hook is a safe no-op for an un-enchanted id, so widening it is free.
        //
        // GAS-STARVATION GUARD (audit F-09). `try/catch` swallows an out-of-gas child
        // as readily as a genuine revert, and EIP-150 forwards only 63/64 of the
        // remaining gas — so a caller who sizes the transaction's gas precisely can
        // make THIS call OOG while the transfer itself still completes. The
        // consequences are exactly the ones M-06 was written to prevent, reachable at
        // will: `enchantedBy[tokenId]` keeps pointing at the SELLER, so the fren stays
        // counted in `activeShares` while earning for nobody (diluting every honest
        // holder), the accrual over the BUYER's ownership is later paid to the SELLER
        // through the stale branch of `_castSpell`, and — because that branch skips
        // `_collectEnchantFee` — the buyer re-enchants for free, dodging the
        // reserve-growing fee that a moved fren is supposed to pay.
        // The hook's work is a fixed, small set of storage writes (worst case ~39k:
        // one cold zero-to-nonzero `owed` SSTORE plus three cold nonzero updates), so
        // require a concrete budget before attempting it and REVERT if the caller did
        // not supply it. That keeps the "a broken dividend can never brick a transfer"
        // property — a genuine revert is still caught — while removing the caller's
        // ability to CHOOSE failure. Mints (`from == 0`) never reach this branch, so
        // the in-protocol badge/art mint paths are unaffected.
        if (from != address(0) && dividend != address(0)) {
            if (gasleft() < GAS_DIVIDEND_MIN) revert InsufficientGas();
            try IMiFrensDividendHook(dividend).onMiFrenTransfer{gas: GAS_DIVIDEND_FWD}(tokenId, from) {}
            catch {}
        }
        // Mark a genesis fren as MOVED on its first real transfer (mint from==0 is
        // NOT a move). Once moved, re-enchanting it costs the reserve-growing fee;
        // original never-moved OGs stay grandfathered free. SSTORE-once.
        if (from != address(0) && tokenId <= GENESIS_SUPPLY && !everMoved[tokenId]) {
            everMoved[tokenId] = true;
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
