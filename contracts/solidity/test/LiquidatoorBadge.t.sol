// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronCollection} from "../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../cauldron/ICauldron.sol";
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
}
