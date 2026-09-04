// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Interface for the NFT contract that provides tiered tax rates
interface INFTContract {
    /// @notice Returns the tax rate in BPS for a given holder
    /// @dev Wizard=0, King/Gnome=50, Knight/Apprentice=100, Peasant=200, Non-holder=300
    function getHolderTaxRate(address holder) external view returns (uint256);

    /// @notice Returns the balance of NFTs for a given holder
    function balanceOf(address holder) external view returns (uint256);
}
