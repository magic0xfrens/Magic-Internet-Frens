// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronCollection} from "../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../cauldron/ICauldron.sol";
import {LiquidatoorRenderer} from "../render/LiquidatoorRenderer.sol";
import {LiqStats} from "../cauldron/ILiquidatorMintable.sol";
import {ILiquidatorMintable} from "../cauldron/ILiquidatorMintable.sol";

/**
 * Unit coverage for the Liquidatoor badge tranche on a Cauldron collection
 * (OnChain Collectibles). Runs WITHOUT a fork — pure ERC721 behaviour:
 *   - only the wired liquidatorMinter may strike a badge;
 *   - badges land in the LIQUIDATOR_ID_BASE range, always revealed;
 *   - striking a badge never touches the art tranche's totalMinted;
 *   - isLiquidatoor + tokenURI resolve to the badge metadata.
 */
contract LiquidatoorBadgeTest is Test {
    CauldronCollection col;

    address deployer = address(this);      // the collection's deployer/registry
    address engine   = address(0xE11E);    // stands in for the PerpEngine
    address minter   = address(0x11117);   // the volume minter (art)
    address alice    = address(0xA11CE);

    function setUp() public {
        col = new CauldronCollection(
            "Test Brew", "TB",
            minter,                 // volume art minter
            address(this),          // registry / controller (audit H-01)
            100,                    // maxSupply (art cap)
            MetadataMode.BaseURI,
            "https://art.example/", // baseURI
            address(0),             // renderer (unused in BaseURI mode)
            address(0), 0           // royalty
        );
    }

    function test_MintLiquidator_OnlyWiredMinter() public {
        // Not wired yet → any caller is rejected.
        vm.expectRevert(CauldronCollection.OnlyLiquidatorMinter.selector);
        vm.prank(engine);
        col.mintLiquidator(alice);

        // Wire the engine as the liquidator minter (deployer only).
        col.setLiquidatorMinter(engine);

        // A random caller still can't.
        vm.expectRevert(CauldronCollection.OnlyLiquidatorMinter.selector);
        vm.prank(alice);
        col.mintLiquidator(alice);
    }

    function test_SetLiquidatorMinter_OnlyDeployer() public {
        vm.expectRevert(CauldronCollection.OnlyMinter.selector);
        vm.prank(alice);
        col.setLiquidatorMinter(engine);
    }

    function test_BadgeIds_AndTraits_AndArtCapUntouched() public {
        col.setLiquidatorMinter(engine);

        // Mint a piece of ART first so totalMinted is non-zero and we can prove
        // badges don't advance it.
        vm.prank(minter);
        col.mint(alice);
        uint256 artMintedBefore = col.totalMinted();
        assertEq(artMintedBefore, 1, "one art token");

        // Strike two badges.
        vm.startPrank(engine);
        uint256 b1 = col.mintLiquidator(alice);
        uint256 b2 = col.mintLiquidator(alice);
        vm.stopPrank();

        // Ids are in the dedicated high range, sequential.
        assertEq(b1, col.LIQUIDATOR_ID_BASE() + 1, "badge 1 id");
        assertEq(b2, col.LIQUIDATOR_ID_BASE() + 2, "badge 2 id");
        assertEq(col.liquidatorMinted(), 2, "two badges struck");

        // Flagged + owned + trait exposed.
        assertTrue(col.isLiquidatoor(b1), "b1 flagged");
        assertTrue(col.isLiquidatoor(b2), "b2 flagged");
        assertFalse(col.isLiquidatoor(1), "art token not flagged");
        assertEq(col.ownerOf(b1), alice, "alice owns b1");
        assertEq(col.liquidatoorTrait(b1), "true", "trait true");
        assertEq(col.liquidatoorTrait(1), "false", "art trait false");

        // The ART cap is completely untouched by badge minting.
        assertEq(col.totalMinted(), artMintedBefore, "art totalMinted unchanged");
    }

    function test_BadgeTokenURI_UsesLiquidatorBase() public {
        col.setLiquidatorMinter(engine);
        vm.prank(engine);
        uint256 b1 = col.mintLiquidator(alice);

        string memory expected = string.concat(
            "https://magicfrens.xyz/api/cauldron/liquidatoor?id=",
            vm.toString(b1)
        );
        assertEq(col.tokenURI(b1), expected, "badge uri = liquidatorURI + id");

        // A deployer can repoint the base.
        col.setLiquidatorURI("ipfs://badges/");
        assertEq(
            col.tokenURI(b1),
            string.concat("ipfs://badges/", vm.toString(b1)),
            "repointed badge uri"
        );
    }

    function test_Interface_Wired() public {
        // The collection satisfies ILiquidatorMintable (compile-time + runtime).
        col.setLiquidatorMinter(engine);
        vm.prank(engine);
        uint256 id = ILiquidatorMintable(address(col)).mintLiquidator(alice);
        assertTrue(col.isLiquidatoor(id), "minted via interface");
    }

    // -----------------------------------------------------------------------
    // On-chain badge metadata (end-to-end: mint with stats -> tokenURI)
    // -----------------------------------------------------------------------

    function _renderer() internal returns (LiquidatoorRenderer r) {
        r = new LiquidatoorRenderer();
        bytes[] memory one = new bytes[](1);
        one[0] = "<rect width='1024' height='775' fill='rgb(9,9,9)'/>";
        r.setArt(true, one);
        r.setArt(false, one);
    }

    function _stats() internal pure returns (LiqStats memory) {
        return LiqStats({
            victim: address(0x9F2A000000000000000000000000000000008C1d),
            wasLong: false,
            leverage: 3,
            collateralWei: 1.4 ether,
            bountyWei: 0.084 ether,
            blockNo: 100,
            entryPrice: 8_410_000_000,
            liqPrice: 9_900_000_000
        });
    }

    function _contains(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool ok = true;
            for (uint256 j; j < n.length; ++j) if (h[i + j] != n[j]) { ok = false; break; }
            if (ok) return true;
        }
        return false;
    }

    /// The whole point: a liquidation is minted WITH its stats, and tokenURI
    /// serves the trophy straight from chain state — no metadata server.
    function test_BadgeRendersFullyOnChain() public {
        LiquidatoorRenderer r = _renderer();
        col.setLiquidatorMinter(engine);
        col.setLiquidatorRenderer(address(r));

        vm.prank(engine);
        uint256 id = col.mintLiquidatorWithStats(alice, _stats());

        string memory uri = col.tokenURI(id);
        assertTrue(_contains(uri, "data:application/json;utf8,"), "served on-chain, not a URL");
        assertTrue(_contains(uri, "data:image/svg+xml;utf8,"), "image is inline SVG");
        assertTrue(_contains(uri, "0x9f2a...8c1d"), "the real victim");
        assertTrue(_contains(uri, "SHORT"), "the real side");
        assertTrue(_contains(uri, "8.4100 gwei"), "the real entry price");
    }

    /// The stats must survive the round-trip, since the renderer reads them back
    /// off the collection rather than being handed them.
    function test_StatsRoundTripThroughTheCollection() public {
        col.setLiquidatorMinter(engine);
        vm.prank(engine);
        uint256 id = col.mintLiquidatorWithStats(alice, _stats());

        LiqStats memory got = col.liqStats(id);
        assertEq(got.victim, _stats().victim, "victim");
        assertEq(got.leverage, 3, "leverage");
        assertEq(got.bountyWei, 0.084 ether, "bounty");
        assertEq(got.entryPrice, 8_410_000_000, "entry");
        assertTrue(!got.wasLong, "side");
    }

    /// Without a renderer wired, badges must still resolve — to the URI base —
    /// so an existing deployment keeps working until the renderer is set.
    function test_FallsBackToUriBaseWithoutRenderer() public {
        col.setLiquidatorMinter(engine);
        vm.prank(engine);
        uint256 id = col.mintLiquidator(alice);
        assertTrue(_contains(col.tokenURI(id), "http"), "must fall back to the URI base");
    }
}
