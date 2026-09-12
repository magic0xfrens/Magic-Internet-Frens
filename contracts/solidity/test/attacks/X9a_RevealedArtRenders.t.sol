// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";
import {CauldronArtAdapter, IFrenRendererFive} from "../../cauldron/CauldronArtAdapter.sol";

/**
 * X9a — REVEALED ART MUST ACTUALLY RENDER.
 *
 *  THE BUG. `CauldronCollection.tokenURI` resolves a revealed token through
 *  `ICollectionRenderer(renderer).tokenURI(tokenId)` — ONE argument, selector
 *  0xc87b56dd (`cauldron/CauldronCollection.sol:412-414`). The art renderer,
 *  `render/FrenRenderer.tokenURI`, is `tokenURI(uint256,uint8,uint8,uint8,uint8)`
 *  — selector 0xc1efba8b (`render/FrenRenderer.sol:40-46`). Neither contract has
 *  a fallback, so a collection pointed at a FrenRenderer REVERTS on every
 *  revealed token. `test_RevealedTokenURI_RevertsAgainstAFiveArgRenderer` pins
 *  that mechanism; the other two tests are the fix, in both metadata modes.
 *
 *  The renderer used here is a FAITHFUL 5-ARG STAND-IN rather than the real
 *  `render/FrenRenderer`: `render/**` is excluded from the `cauldron` foundry
 *  profile (`foundry.toml:85`), so this suite cannot compile it. What is under
 *  test is the SELECTOR BRIDGE and the trait derivation, both of which are
 *  independent of how the pixels are painted — and the stand-in asserts it was
 *  handed the exact traits {CauldronArtAdapter.traitsOf} promises.
 */

/// @dev Answers the SAME selector the real renderer does and nothing else.
contract FiveArgRendererStub {
    function tokenURI(uint256 tokenId, uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx)
        external
        view
        returns (string memory)
    {
        // A base64 data-URI is what the real renderer returns; this returns the
        // JSON in the clear so the test can assert on its contents directly.
        return string.concat(
            '{"name":"MagicFren #', _u(tokenId),
            '","attributes":[{"trait_type":"Class","value":"', _u(classIdx),
            '"},{"trait_type":"Body","value":"', _u(bodyIdx),
            '"},{"trait_type":"Face","value":"', _u(faceIdx),
            '"},{"trait_type":"Item","value":"', _u(itemIdx),
            '"}],"image":"data:image/svg+xml;base64,PHN2Zz48L3N2Zz4="}'
        );
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v != 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}

contract X9aRevealedArtRenders is Test {
    CauldronCollection col;
    FiveArgRendererStub five;
    CauldronArtAdapter adapter;

    address constant MINTER = address(0xB0B); // the volume hook
    address constant HOLDER = address(0xB01D);

    function setUp() public {
        five = new FiveArgRendererStub();
        adapter = new CauldronArtAdapter(IFrenRendererFive(address(five)));
    }

    function _deploy(MetadataMode mode_, string memory baseURI_, address renderer_)
        internal
        returns (CauldronCollection c)
    {
        c = new CauldronCollection(
            "GnomeLand", "GNOME", MINTER, address(this), 1000, mode_, baseURI_, renderer_, address(0), 0
        );
    }

    function _mintAndReveal(CauldronCollection c) internal returns (uint256 id) {
        vm.prank(MINTER);
        id = c.mint(HOLDER);
        vm.roll(block.number + 1); // the reveal seed is the mint block's hash
        vm.prank(HOLDER);
        c.reveal(id);
        assertTrue(c.revealed(id), "precondition: the token must be revealed");
    }

    // ------------------------------------------------------------------
    // The bug, pinned.
    // ------------------------------------------------------------------

    function test_RevealedTokenURI_RevertsAgainstAFiveArgRenderer() public {
        // The 5-arg renderer IS a contract, so the collection's BadConfig code
        // check accepts it at construction — the mismatch only bites at read
        // time, which is why it shipped.
        CauldronCollection c = _deploy(MetadataMode.Renderer, "", address(five));
        uint256 id = _mintAndReveal(c);

        vm.expectRevert(); // no matching selector, no fallback
        c.tokenURI(id);
        console2.log("VERIFIED: a 5-arg renderer bricks tokenURI for every revealed token");
    }

    // ------------------------------------------------------------------
    // MODE 1: on-chain renderer, through the adapter.
    // ------------------------------------------------------------------

    function test_RendererMode_ArtRendersThroughTheAdapter() public {
        col = _deploy(MetadataMode.Renderer, "", address(adapter));
        uint256 id = _mintAndReveal(col);

        string memory uri = col.tokenURI(id);
        assertGt(bytes(uri).length, 0, "tokenURI returned an empty string");
        assertTrue(_contains(uri, '"image":"data:image/svg+xml;base64,'), "no image in the metadata JSON");
        assertTrue(_contains(uri, '"name":"MagicFren #1"'), "metadata is not for this token");

        // The adapter handed the renderer the traits it publishes, not zeros.
        (uint8 cIdx, uint8 bIdx, uint8 fIdx, uint8 iIdx) = adapter.traitsOf(address(col), id);
        assertLt(cIdx, 7, "classIdx out of the uploaded art set");
        assertLt(fIdx, 12, "faceIdx out of the uploaded face set");
        assertTrue(_contains(uri, string.concat('{"trait_type":"Class","value":"', _u(cIdx), '"}')), "class not passed through");
        assertTrue(_contains(uri, string.concat('{"trait_type":"Body","value":"', _u(bIdx), '"}')), "body not passed through");
        assertTrue(_contains(uri, string.concat('{"trait_type":"Item","value":"', _u(iIdx), '"}')), "item not passed through");
        console2.log("VERIFIED renderer mode: traits", cIdx, bIdx, iIdx);
        console2.log(uri);
    }

    /// @notice Unrevealed tokens must not leak a creature (their rarity is not
    ///         rolled yet, so any art drawn now would be the wrong one).
    function test_Adapter_RefusesAnUnrevealedToken() public {
        col = _deploy(MetadataMode.Renderer, "", address(adapter));
        vm.prank(MINTER);
        uint256 id = col.mint(HOLDER);
        vm.expectRevert(abi.encodeWithSelector(CauldronArtAdapter.NotRevealed.selector, id));
        adapter.traitsOf(address(col), id);
        // The collection short-circuits to the placeholder, so this still works.
        assertEq(col.tokenURI(id), col.unrevealedURI(), "unrevealed must show the placeholder");
    }

    // ------------------------------------------------------------------
    // MODE 2: BaseURI, the hosted art route.
    // ------------------------------------------------------------------

    function test_BaseUriMode_ResolvesToTheArtRouteWithRarityAndId() public {
        col = _deploy(MetadataMode.BaseURI, "https://www.mifrens.xyz/api/cauldron/creature/", address(0));
        uint256 id = _mintAndReveal(col);

        string memory uri = col.tokenURI(id);
        assertGt(bytes(uri).length, 0, "tokenURI returned an empty string");
        string memory want = string.concat(
            "https://www.mifrens.xyz/api/cauldron/creature/", _u(col.rarityOf(id)), "/", _u(id)
        );
        assertEq(uri, want, "BaseURI path shape changed");
        console2.log("VERIFIED baseURI mode:", uri);
    }

    // ------------------------------------------------------------------
    // The repair path: a live collection can be moved between the two.
    // ------------------------------------------------------------------

    function test_SetMetadata_RepointsALiveCollectionBothWays() public {
        // `deployer` is this test (it stands in for the registry), which is the
        // gate `CauldronRegistry.setCollectionMetadata` now calls through.
        col = _deploy(MetadataMode.Renderer, "", address(five)); // BROKEN on purpose
        uint256 id = _mintAndReveal(col);

        vm.expectRevert();
        col.tokenURI(id);

        // Repair 1: to the adapter.
        col.setMetadata(MetadataMode.Renderer, address(adapter), "");
        assertTrue(_contains(col.tokenURI(id), '"image":"'), "adapter repair did not render");

        // Repair 2: to the hosted route.
        col.setMetadata(MetadataMode.BaseURI, address(0), "https://www.mifrens.xyz/api/cauldron/creature/");
        assertTrue(
            _contains(col.tokenURI(id), "https://www.mifrens.xyz/api/cauldron/creature/"),
            "baseURI repair did not take"
        );

        // The gate is intact: a stranger cannot repoint the art.
        vm.prank(HOLDER);
        vm.expectRevert(CauldronCollection.OnlyMinter.selector);
        col.setMetadata(MetadataMode.BaseURI, address(0), "https://evil.example/");
        console2.log("VERIFIED: setMetadata repairs art in both modes and still refuses a stranger");
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    function _contains(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i = 0; i + n.length <= h.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) { ok = false; break; }
            }
            if (ok) return true;
        }
        return false;
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v != 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
