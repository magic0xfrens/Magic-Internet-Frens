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

    IBurnableCollection public immutable collection;

    /// @notice The registry that may close the vault on relaunch.
    address public immutable registry;

    /// @notice How many NFTs have redeemed their floor (shares retired).
    uint256 public redeemed;

    /// @notice Once the brew dies (relaunch), the vault closes: redemption stops
    ///         and remaining ETH sweeps into the next launch's liquidity.
    bool public closed;

    event Deposited(address indexed from, uint256 amount);
    event Redeemed(uint256 indexed tokenId, address indexed holder, uint256 amount);
    event VaultClosed(address indexed to, uint256 swept);

    constructor(address _collection, address _registry) {
        collection = IBurnableCollection(_collection);
        registry = _registry;
    }

    /// @notice Fees flow in here from the hook (and anyone topping up the floor).
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Current redeemable floor per outstanding NFT.
    function floorPerNFT() public view returns (uint256) {
        uint256 outstanding = collection.totalMinted() - redeemed;
        if (outstanding == 0) return 0;
        return address(this).balance / outstanding;
    }

    /// @notice Burn your NFT and claim its equal share of the vault floor.
    ///         Only redeemable during the brew's lifespan (before it dies).
    function redeem(uint256 tokenId) external nonReentrant returns (uint256 amount) {
        if (closed) revert Closed();
        if (collection.ownerOf(tokenId) != msg.sender) revert NotOwner();

        uint256 outstanding = collection.totalMinted() - redeemed;
        amount = address(this).balance / outstanding;
        if (amount == 0) revert NothingToRedeem();

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
