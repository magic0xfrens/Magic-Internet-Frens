// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IBurnableCollection {
    function ownerOf(uint256 tokenId) external view returns (address);
    function totalMinted() external view returns (uint256);
    function burnFromVault(uint256 tokenId) external;
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

    event Deposited(address indexed from, uint256 amount);
    event Redeemed(uint256 indexed tokenId, address indexed holder, uint256 amount);
    event VaultClosed(address indexed to, uint256 swept);

    constructor(address _collection, address _registry, uint256 _floorOffset) {
        collection = IBurnableCollection(_collection);
        registry = _registry;
        floorOffset = _floorOffset;
    }

    /// @notice Fees flow in here from the hook (and anyone topping up the floor).
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
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
    function close() external nonReentrant returns (uint256 swept) {
        if (msg.sender != registry) revert NotRegistry();
        closed = true;
        swept = address(this).balance;
        if (swept > 0) {
            (bool ok, ) = registry.call{value: swept}("");
            if (!ok) revert TransferFailed();
        }
        emit VaultClosed(registry, swept);
    }
}
