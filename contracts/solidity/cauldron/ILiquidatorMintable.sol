// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice The facts of the liquidation a badge commemorates, recorded ON-CHAIN
///         at mint so the trophy can be rendered from the chain alone.
///
///  Before this existed the only record was the `LiquidatoorAwarded` event, which
///  a contract cannot read — so `tokenURI` had to defer to an off-chain API and
///  the frontend matched badges to kills *by mint order*, which breaks the moment
///  two liquidations land in one block.
///
///  Packs into three slots:
///    1. victim (20) + wasLong (1) + leverage (1)
///    2. collateralWei (12) + bountyWei (12) + blockNo (8)
///    3. entryPrice (16) + liqPrice (16)
///
///  The two prices are ETH-per-token in wei. uint128 holds ~3.4e38, so even a
///  1e18-scaled price has ~20 orders of magnitude of headroom.
struct LiqStats {
    address victim;         // the trader who got liquidated
    bool    wasLong;        // their side
    uint8   leverage;       // their leverage multiple
    uint96  collateralWei;  // ETH they had staked
    uint96  bountyWei;      // ETH paid to the liquidator
    uint64  blockNo;        // block the kill landed in
    uint128 entryPrice;     // their entry, ETH per token (wei)
    uint128 liqPrice;       // the mark that killed them, ETH per token (wei)
}

/// @notice A Cauldron collection that can mint a **Liquidatoor** badge — an
///         uncapped, immediately-revealed trophy struck when a fren is
///         responsible for a perp liquidation. Badges live in a separate id
///         range from the art tranche, so awarding them never touches
///         `totalMinted`/`maxSupply`. Only the wired `liquidatorMinter` (the
///         PerpEngine) may call.
interface ILiquidatorMintable {
    /// @notice Mint a badge and record what it commemorates.
    function mintLiquidatorWithStats(address to, LiqStats calldata s)
        external
        returns (uint256 tokenId);

    /// @notice Stats-free mint. Kept so an engine deployed before stats existed
    ///         keeps working; the badge simply renders without a readout.
    function mintLiquidator(address to) external returns (uint256 tokenId);

    /// @notice What badge `tokenId` commemorates. Zeroed for a stats-free mint.
    function liqStats(uint256 tokenId) external view returns (LiqStats memory);
}
