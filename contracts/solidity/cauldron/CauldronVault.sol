// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IBurnableCollection {
    function ownerOf(uint256 tokenId) external view returns (address);
    function totalMinted() external view returns (uint256);
    function burnFromVault(uint256 tokenId) external;
    /// @notice The volume hook — the only address allowed to mint, and the only
    ///         address that routes fee ether into this vault. Immutable on
    ///         {CauldronCollection}; wired at ignition on {MiFrensGenesis}, which
    ///         is why it is read live rather than cached in the constructor.
    function minter() external view returns (address);
}

/**
 * @title CauldronVault
 * @notice The per-brew NFT floor — modelled on Gnome's vault. A share of the
 *         hook's swap fees is deposited here; every minted collection NFT is
 *         backed by an EQUAL redeemable slice of the pooled ETH.
 *
 *  floor(perNFT) = address(this).balance / outstanding
 *      outstanding = totalMinted - redeemed
 *
 *  `redeem(tokenId)` burns the NFT and pays its floor share. As fees accrue the
 *  floor rises; as NFTs mint it dilutes; as holders redeem the remaining floor
 *  is unaffected (balance and outstanding both drop by one share). No NFT is
 *  ever unbacked: mints only add claims, fees only add ETH.
 */
contract CauldronVault is ReentrancyGuard {
    error NotOwner();
    error NothingToRedeem();
    error TransferFailed();
    error Closed();
    error NotRegistry();
    error UnifiedFloorActive();

    IBurnableCollection public immutable collection;

    /// @notice The registry that may close the vault on relaunch.
    address public immutable registry;

    /// @notice How many NFTs have redeemed their floor (shares retired).
    uint256 public redeemed;

    /// @notice The lowest tokenId this vault serves. 0 for a normal brew. For the
    ///         iteration-#2 MiFrens continuation it is GENESIS_SUPPLY, so the vault
    ///         backs ONLY the FORGED tranche (ids > offset) — the genesis OGs
    ///         (1..offset) have their own dividend + redemption floor and never draw
    ///         (or dilute) this one. Set at deploy (immutable).
    uint256 public immutable floorOffset;

    /// @notice Once the brew dies (relaunch), the vault closes: redemption stops
    ///         and remaining ETH sweeps into the next launch's liquidity.
    bool public closed;

    /// @notice NFTs currently backed by this vault = eligible minted − redeemed.
    ///         Eligible excludes the genesis tranche (ids <= floorOffset).
    function outstanding() public view returns (uint256) {
        uint256 minted = collection.totalMinted();
        uint256 eligible = minted > floorOffset ? minted - floorOffset : 0;
        return eligible > redeemed ? eligible - redeemed : 0;
    }

    /// @notice Ether this vault received FROM THE PROTOCOL (the collection's
    ///         `minter` — the volume hook — or the registry). Never decremented:
    ///         it is a high-water mark of protocol funding, and {close} clamps it
    ///         to the live balance, so redemptions are accounted for.
    ///
    ///  ── WHY THE ENTITLEMENT CANNOT BE SIZED FROM `address(this).balance`
    ///     (red-team Z-02) ────────────────────────────────────────────────────
    ///  {close}'s return is fed straight to `PoolOps.crystallizeCollection` as the
    ///  NUMERATOR of `entitled = swept * activeBase / totalETH`
    ///  (CauldronRegistry.sol:1080-1082), and in `seedFunding`'s native branch the
    ///  sweep is also INSIDE `totalETH` (PoolOps.sol:1082-1084). `receive()` is
    ///  open to anyone, so a stranger's donation `D` drives that ratio
    ///  `(V+D)/(L+D) -> 1`: the dead collection's crystallised entitlement walks up
    ///  toward the newborn's ENTIRE active tranche.
    ///
    ///  That damage is permanent. `CollectionLedger.crystallize` reverts
    ///  `AlreadyCrystallized` so it cannot be re-run with a corrected figure, and
    ///  nothing lowers `totalEntitled` except a holder choosing to redeem. The
    ///  registry subtracts `totalEntitled` from `newActive` at EVERY future
    ///  relaunch (CauldronRegistry.sol:1057-1063), so one donation at one death
    ///  caps every later generation at the `GEN1_ACTIVE_TOKENS` fallback and
    ///  over-claims the shared reserve that also backs migration and genesis
    ///  redemption.
    ///
    ///  Closing `receive()` would NOT be enough — `selfdestruct` and a coinbase
    ///  payment both move a balance with no code running — so the bound has to be
    ///  on what is COUNTED, not on what can arrive. Donations are still welcome and
    ///  still lift `floorPerNFT` for every redeemer; they just cannot buy a claim on
    ///  the next generation's supply.
    uint256 public accountedDeposits;

    event Deposited(address indexed from, uint256 amount);
    event Redeemed(uint256 indexed tokenId, address indexed holder, uint256 amount);
    event VaultClosed(address indexed to, uint256 swept);
    /// @notice Ether swept at close that the protocol never deposited — donations,
    ///         forced transfers, coinbase payments. It moves to the registry with
    ///         the rest, but it is NOT reported as `swept`, so it sizes no
    ///         entitlement. Emitted so the gap is observable rather than silent.
    event UnaccountedSweep(address indexed to, uint256 amount);

    constructor(address _collection, address _registry, uint256 _floorOffset) {
        collection = IBurnableCollection(_collection);
        registry = _registry;
        floorOffset = _floorOffset;
    }

    /// @notice Fees flow in here from the hook (and anyone topping up the floor).
    ///         DELIBERATELY OPEN: a top-up raises `floorPerNFT` for every holder and
    ///         refusing it would strand honest value. Only PROTOCOL deposits are
    ///         counted into {accountedDeposits} — see the note there for why the
    ///         difference is what stops a donation from minting an entitlement.
    receive() external payable {
        if (msg.sender == registry || msg.sender == _minter()) {
            accountedDeposits += msg.value;
        }
        emit Deposited(msg.sender, msg.value);
    }

    /// @dev The collection's current minter (the volume hook). Read live and
    ///      defensively: {MiFrensGenesis.minter} is a mutable slot wired at
    ///      ignition, so a vault deployed for the iteration-#2 continuation may be
    ///      constructed before it is set. A failed read yields `address(0)`, which
    ///      no `msg.sender` can equal, so the worst case is that a deposit is not
    ///      counted — never that one is counted that should not be.
    function _minter() private view returns (address m) {
        (bool ok, bytes memory r) = address(collection).staticcall(
            abi.encodeWithSelector(IBurnableCollection.minter.selector)
        );
        if (ok && r.length >= 32) m = abi.decode(r, (address));
    }

    /// @notice Current redeemable floor per outstanding (eligible) NFT.
    function floorPerNFT() public view returns (uint256) {
        uint256 n = outstanding();
        if (n == 0) return 0;
        return address(this).balance / n;
    }

    /// @notice Burn your NFT and claim its equal share of the vault floor.
    ///         Only redeemable during the brew's lifespan (before it dies).
    ///  UNIFIED-FLOOR NOTE (audit L-07): under the shipped configuration BOTH
    ///  collection-deployment paths wire `hook.setVault(0)`, so the fee floor-share
    ///  becomes token BUY PRESSURE and no ETH ever reaches this vault. Its balance
    ///  is therefore always zero and this function cannot succeed. It reverts with
    ///  an explicit `UnifiedFloorActive()` rather than a bare `NothingToRedeem`, so
    ///  a holder is pointed at `CauldronRegistry.recycleCollectionNFT` — the live
    ///  token-denominated floor — instead of concluding their NFT is unbacked.
    ///  The vault itself is still load-bearing: `crystallizeCollection` reads
    ///  `outstanding()` to size the collection's entitlement at death.
    function redeem(uint256 tokenId) external nonReentrant returns (uint256 amount) {
        if (closed) revert Closed();
        if (tokenId <= floorOffset) revert NotOwner(); // genesis tranche has its own floor
        if (collection.ownerOf(tokenId) != msg.sender) revert NotOwner();

        uint256 n = outstanding();
        amount = n == 0 ? 0 : address(this).balance / n;
        if (amount == 0) {
            if (address(this).balance == 0) revert UnifiedFloorActive();
            revert NothingToRedeem();
        }

        redeemed += 1;
        collection.burnFromVault(tokenId);

        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Redeemed(tokenId, msg.sender, amount);
    }

    /// @notice Close the vault on relaunch: stop redemption and sweep remaining
    ///         ETH to the registry for the next launch's liquidity. Registry-only.
    /// @dev The RETURN VALUE IS AN ACCOUNTING FIGURE, NOT A TRANSFER AMOUNT
    ///      (red-team Z-02). Every wei still leaves for the registry — nothing is
    ///      stranded in a closed vault, and a donation still ends up as protocol
    ///      liquidity. What is REPORTED is only the ether the protocol itself
    ///      deposited, clamped to the live balance so pre-death redemptions are
    ///      subtracted. That figure is the numerator of the dead collection's
    ///      permanent, one-shot entitlement; see {accountedDeposits}.
    function close() external nonReentrant returns (uint256 swept) {
        if (msg.sender != registry) revert NotRegistry();
        closed = true;
        uint256 bal = address(this).balance;
        uint256 acc = accountedDeposits;
        swept = bal < acc ? bal : acc;
        if (bal > 0) {
            (bool ok, ) = registry.call{value: bal}("");
            if (!ok) revert TransferFailed();
        }
        if (bal > swept) emit UnaccountedSweep(registry, bal - swept);
        emit VaultClosed(registry, swept);
    }
}
