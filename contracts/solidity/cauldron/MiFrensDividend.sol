// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMiFrensShares {
    function ownerOf(uint256 tokenId) external view returns (address);
    function GENESIS_SUPPLY() external view returns (uint256);
    function MAX_SUPPLY() external view returns (uint256);
    /// @notice Whether a genesis fren has moved (→ paid re-enchant; OGs are free).
    function everMoved(uint256 tokenId) external view returns (bool);
}

/// @notice The bits of the registry the dividend needs to price + route the
///         reserve-growing re-enchant fee.
interface IReserveRegistry {
    function enchantFee() external view returns (uint256);
    function currentToken() external view returns (address);
    function donateToReserve(uint256 amount) external;
}

/**
 * @title MiFrensDividend
 * @notice The eternal reward for holding a GENESIS MiFren. A slice of every
 *         brew's ETH swap fees streams in here forever — iteration #1, #2, #3…
 *
 *  ── CAST THE SPELL ────────────────────────────────────────────────────────
 *  A genesis MiFren only draws fees once its owner **casts the spell**
 *  (`castSpell`). Fees are split ONLY among the currently-enchanted frens, so if
 *  not everyone casts, the ones who did earn MORE. The bond is to the caster:
 *  transferring the NFT breaks it (the MiFrens contract calls `onMiFrenTransfer`,
 *  settling the leaver and freeing its share), and the new owner must re-cast.
 *
 *  Accounting is a MasterChef accumulator over the LIVE active set:
 *    on deposit:  accPerShare += amount * ACC / activeShares
 *    pending(id): (accPerShare - debtOf[id]) / ACC          (0 if not enchanted)
 *    on claim:    pay pending, debtOf[id] = accPerShare
 *  Joining (cast) and leaving (transfer) settle first, then adjust activeShares —
 *  so a fren only earns for the exact window it was enchanted, never double.
 */
contract MiFrensDividend is ReentrancyGuard {
    uint256 private constant ACC = 1e18;

    /// @notice The MiFrens collection whose genesis tranche earns dividends.
    IMiFrensShares public immutable mifrens;

    /// @notice Genesis (OG) tranche size (e.g. 1111). Original never-moved OGs
    ///         (id <= SHARES) enchant FREE; everyone else pays the fee (see below).
    ///         NOT the eligibility cap — that's MAX_TOKEN.
    uint256 public immutable SHARES;

    /// @notice Eligibility cap = the collection's art supply (e.g. 2400). Any MiFren
    ///         up to this — OG (1..SHARES) OR forged (SHARES+1..MAX_TOKEN) — can
    ///         enchant to earn. Forged frens "pay to earn"; OGs earn free. The LIVE
    ///         divisor is `activeShares` (only those currently enchanted), so forged
    ///         joiners dilute per-share while their fee grows the floor to offset.
    uint256 public immutable MAX_TOKEN;

    /// @notice Where fees go when NOBODY has cast the spell (no active shares) —
    ///         the pot has no claimants, so it sweeps here instead of banking up
    ///         for whoever casts first.
    address public immutable treasury;

    /// @notice The Cauldron registry — priced + routes the reserve-growing paid
    ///         re-enchant fee (moved frens). Wired once post-deploy by `treasury`.
    ///         Zero (default) = re-enchant is free for everyone (fee sink off).
    IReserveRegistry public registry;

    /// @notice Cumulative ETH per ACTIVE share, scaled by ACC.
    uint256 public accPerShare;
    /// @notice Number of frens currently enchanted (the live divisor).
    uint256 public activeShares;
    /// @notice Undistributed wei carried forward (sub-share dust + fees that
    ///         arrived while nobody was enchanted).
    uint256 public residual;

    uint256 public totalDeposited;
    uint256 public totalClaimed;

    /// @notice Per genesis tokenId: accPerShare already accounted (the "debt").
    mapping(uint256 => uint256) public debtOf;
    /// @notice tokenId => the address that cast the spell. A fren earns only while
    ///         `enchantedBy == its owner`; a transfer clears it (see hook below).
    mapping(uint256 => address) public enchantedBy;
    /// @notice Settled-but-unclaimed ETH, pull-withdrawn (credited when a fren
    ///         leaves the active set on transfer).
    mapping(address => uint256) public owed;

    event Deposited(uint256 amount, uint256 accPerShare);
    event Claimed(uint256 indexed tokenId, address indexed to, uint256 amount);
    event SpellCast(uint256 indexed tokenId, address indexed fren);
    event SpellBroken(uint256 indexed tokenId, address indexed wasFren);
    event Withdrawn(address indexed to, uint256 amount);
    event TreasuryFunded(uint256 amount);

    error NotShare();
    error NotOwner();
    error TransferFailed();
    error NotEnchanted();
    error NotCollection();
    error EnchantFeeUnpaid();

    event RegistrySet(address registry);

    constructor(address _mifrens, address _treasury) {
        mifrens = IMiFrensShares(_mifrens);
        uint256 s = IMiFrensShares(_mifrens).GENESIS_SUPPLY();
        require(s > 0, "no shares");
        require(_treasury != address(0), "treasury");
        SHARES = s;
        uint256 m = IMiFrensShares(_mifrens).MAX_SUPPLY();
        MAX_TOKEN = m >= s ? m : s; // eligibility cap (art supply); never below OG
        treasury = _treasury;
    }

    /// @notice Wire the registry (one-time) so moved frens pay the reserve-growing
    ///         re-enchant fee. Gated to `treasury` (the deploy wirer). Until set,
    ///         re-enchant is free for everyone (unchanged legacy behavior).
    function setRegistry(address _registry) external {
        if (msg.sender != treasury) revert NotOwner();
        if (address(registry) != address(0)) revert NotOwner(); // one-time
        registry = IReserveRegistry(_registry);
        emit RegistrySet(_registry);
    }

    /// @notice Fees flow in from the hook (and anyone topping up the pot). Split
    ///         among the enchanted; if NONE are, the pot sweeps to the treasury
    ///         (no claimants) rather than banking up for the first caster.
    receive() external payable {
        totalDeposited += msg.value;
        uint256 amt = msg.value + residual;
        if (activeShares == 0) {
            residual = 0;
            (bool ok, ) = treasury.call{value: amt}("");
            if (!ok) { residual = amt; }         // treasury rejected → hold, retry next deposit
            else { emit TreasuryFunded(amt); }
            return;
        }
        uint256 inc = (amt * ACC) / activeShares;
        accPerShare += inc;
        residual = amt - (inc * activeShares) / ACC;
        emit Deposited(msg.value, accPerShare);
    }

    // ── Views ────────────────────────────────────────────────────────────────

    /// @notice ETH currently claimable for a genesis tokenId (0 unless enchanted
    ///         by its current owner).
    function pending(uint256 tokenId) public view returns (uint256) {
        if (tokenId == 0 || tokenId > MAX_TOKEN) return 0;
        if (enchantedBy[tokenId] != mifrens.ownerOf(tokenId)) return 0;
        return (accPerShare - debtOf[tokenId]) / ACC;
    }

    /// @notice Whether a fren is currently drawing fees (spell cast + still owned
    ///         by the caster).
    function isEnchanted(uint256 tokenId) external view returns (bool) {
        if (tokenId == 0 || tokenId > MAX_TOKEN) return false;
        return enchantedBy[tokenId] == mifrens.ownerOf(tokenId);
    }

    // ── Cast the spell ─────────────────────────────────────────────────────────

    /// @notice Cast the spell: enchant a genesis MiFren you own so it joins the
    ///         earning set. Earning starts NOW — no back-pay. Idempotent for a
    ///         fren you've already enchanted.
    function castSpell(uint256 tokenId) external {
        _castSpell(tokenId);
    }

    /// @notice Cast the spell on many frens at once (one tx for a whole bag).
    function castMany(uint256[] calldata tokenIds) external {
        uint256 n = tokenIds.length;
        for (uint256 i = 0; i < n;) { _castSpell(tokenIds[i]); unchecked { ++i; } }
    }

    function _castSpell(uint256 tokenId) private {
        if (tokenId == 0 || tokenId > MAX_TOKEN) revert NotShare();
        if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner();
        address cur = enchantedBy[tokenId];
        if (cur == msg.sender) return; // already active for you
        if (cur == address(0)) {
            // Fresh join. If this fren has MOVED (recycled/transferred) and the
            // registry is wired, the caster pays the reserve-growing re-enchant fee
            // FIRST → it compounds the genesis floor for everyone. Original
            // never-moved OGs pay nothing (everMoved == false). Fee collected
            // before any state change so a fren can never activate unpaid.
            _collectEnchantFee(tokenId);
            activeShares += 1;
        } else {
            // Stale (a transfer's hook was skipped): settle the prior caster and
            // re-point WITHOUT changing the count — net one active share either way.
            owed[cur] += (accPerShare - debtOf[tokenId]) / ACC;
        }
        debtOf[tokenId] = accPerShare;
        enchantedBy[tokenId] = msg.sender;
        emit SpellCast(tokenId, msg.sender);
    }

    /// @dev Collect the paid enchant fee and route it into the reserve (grows the
    ///      floor). FORGED frens (id > SHARES) ALWAYS pay — "pay to earn". OG frens
    ///      (id <= SHARES) pay only if they've MOVED; original never-moved OGs are
    ///      grandfathered FREE. No-op if the registry isn't wired or the fee is 0.
    function _collectEnchantFee(uint256 tokenId) private {
        IReserveRegistry reg = registry;
        if (address(reg) == address(0)) return;
        // Only original OGs (genesis id that never moved) enchant free.
        if (tokenId <= SHARES && !mifrens.everMoved(tokenId)) return;
        uint256 fee = reg.enchantFee();
        if (fee == 0) return;
        address tok = reg.currentToken();
        if (tok == address(0)) return;
        // Pull the fee in, then route it into the reserve via the registry.
        if (!IERC20(tok).transferFrom(msg.sender, address(this), fee)) revert EnchantFeeUnpaid();
        IERC20(tok).approve(address(reg), fee);
        reg.donateToReserve(fee);
    }

    /// @notice MiFrens-only hook: on any transfer of an enchanted genesis fren,
    ///         settle its accrued ETH to the leaver and free its active share, so
    ///         it stops earning exactly at the transfer and the new owner must
    ///         re-cast. Called from the collection's `_update`.
    function onMiFrenTransfer(uint256 tokenId, address /*from*/) external {
        if (msg.sender != address(mifrens)) revert NotCollection();
        address cur = enchantedBy[tokenId];
        if (cur == address(0)) return; // wasn't enchanted → nothing to do
        owed[cur] += (accPerShare - debtOf[tokenId]) / ACC; // settle up to the move
        unchecked { activeShares -= 1; }
        enchantedBy[tokenId] = address(0);
        debtOf[tokenId] = 0;
        emit SpellBroken(tokenId, cur);
    }

    // ── Claim ──────────────────────────────────────────────────────────────────

    /// @notice Claim the accrued ETH for an enchanted genesis MiFren you own.
    function claim(uint256 tokenId) public nonReentrant returns (uint256 amount) {
        amount = _claim(tokenId);
    }

    /// @notice Claim many at once.
    function claimMany(uint256[] calldata tokenIds)
        external
        nonReentrant
        returns (uint256 total)
    {
        uint256 n = tokenIds.length;
        for (uint256 i = 0; i < n;) { total += _claim(tokenIds[i]); unchecked { ++i; } }
    }

    /// @notice Withdraw ETH that was settled to you when a fren left the set
    ///         (e.g. fees earned right up to a transfer you made).
    function withdrawOwed() external nonReentrant returns (uint256 amount) {
        amount = owed[msg.sender];
        if (amount > 0) {
            owed[msg.sender] = 0;
            totalClaimed += amount;
            (bool ok, ) = msg.sender.call{value: amount}("");
            if (!ok) revert TransferFailed();
            emit Withdrawn(msg.sender, amount);
        }
    }

    function _claim(uint256 tokenId) private returns (uint256 amount) {
        if (tokenId == 0 || tokenId > MAX_TOKEN) revert NotShare();
        if (mifrens.ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (enchantedBy[tokenId] != msg.sender) revert NotEnchanted();

        amount = (accPerShare - debtOf[tokenId]) / ACC;
        debtOf[tokenId] = accPerShare; // effects before interaction
        if (amount > 0) {
            totalClaimed += amount;
            (bool ok, ) = msg.sender.call{value: amount}("");
            if (!ok) revert TransferFailed();
            emit Claimed(tokenId, msg.sender, amount);
        }
    }
}
