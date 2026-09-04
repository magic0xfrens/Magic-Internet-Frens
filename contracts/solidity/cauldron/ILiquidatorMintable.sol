// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice A Cauldron collection that can mint a **Liquidatoor** badge — an
///         uncapped, immediately-revealed trophy struck when a fren is
///         responsible for a perp liquidation. Badges live in a separate id
///         range from the art tranche, so awarding them never touches
///         `totalMinted`/`maxSupply`. Only the wired `liquidatorMinter` (the
///         PerpEngine) may call.
interface ILiquidatorMintable {
    function mintLiquidator(address to) external returns (uint256 tokenId);
}
