// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TraitStorage} from "../render/TraitStorage.sol";
import {FrenRenderer} from "../render/FrenRenderer.sol";

/**
 * @notice End-to-end test using the REAL compressed art blobs produced by
 *         scripts/compress-traits.mjs. Loads the palette + a Wizard body/face/item
 *         from disk, stores them on-chain via SSTORE2, and renders the SVG/metadata.
 */
contract FrenRendererTest is Test {
    TraitStorage store;
    FrenRenderer renderer;

    string constant DIR = "../../compressed-traits/";

    function setUp() public {
        store = new TraitStorage();
        renderer = new FrenRenderer(store);

        // Palette (raw RGB, no header)
        store.storePalette(vm.readFileBinary(string.concat(DIR, "palette-rgb.bin")));

        // A full Wizard: body 0 (layerType 0, class 0, idx 0),
        // face 0 (layerType 1, class 0, idx 0), item 0 (layerType 2, class 0, idx 0)
        _store(0, 0, 0);
        _store(1, 0, 0);
        _store(2, 0, 0);
    }

    function _store(uint8 lt, uint8 ci, uint8 li) internal {
        bytes memory blob = vm.readFileBinary(
            string.concat(
                DIR,
                "trait-",
                vm.toString(lt),
                "-",
                vm.toString(ci),
                "-",
                vm.toString(li),
                ".bin"
            )
        );
        store.storeTrait(store.traitKey(lt, ci, li), blob);
    }

    function test_PaletteRoundTrips() public view {
        bytes memory pal = store.getPalette();
        assertEq(pal.length, 741, "palette should be 247 colors * 3 bytes");
    }

    function test_BlobHeaderMatches() public view {
        // trait-0-0-0 header: layerType0 class0 idx0 minX24 minY5 w66 h104 local12
        bytes memory blob = store.getTrait(store.traitKey(0, 0, 0));
        assertEq(uint8(blob[0]), 0);
        assertEq(uint8(blob[3]), 24, "minX");
        assertEq(uint8(blob[4]), 5, "minY");
        assertEq(uint8(blob[5]), 66, "width");
        assertEq(uint8(blob[6]), 104, "height");
        assertEq(uint8(blob[7]), 12, "local palette size");
    }

    function test_RenderSVG_WellFormed() public view {
        string memory svg = renderer.renderSVG(0, 0, 0, 0);
        bytes memory s = bytes(svg);
        assertGt(s.length, 1000, "svg should be substantial");

        // starts with <svg and ends with </svg>
        assertEq(s[0], "<");
        assertEq(s[1], "s");
        assertEq(s[s.length - 1], ">");

        // must contain a gradient rect and at least one pixel rect
        assertTrue(_contains(svg, "url(#g)"), "has gradient bg");
        assertTrue(_contains(svg, "<rect x='"), "has pixel rects");
    }

    function test_TokenURI_IsBase64Json() public view {
        string memory uri = renderer.tokenURI(42, 0, 0, 0, 0);
        assertTrue(
            _startsWith(uri, "data:application/json;base64,"),
            "tokenURI is a base64 json data-uri"
        );
    }

    function test_GradientDeterministic() public view {
        // Same traits -> identical SVG (pure function of trait indices + stored data)
        string memory a = renderer.renderSVG(0, 1, 2, 3);
        string memory b = renderer.renderSVG(0, 1, 2, 3);
        assertEq(keccak256(bytes(a)), keccak256(bytes(b)));
    }

    // --- helpers ---

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory pb = bytes(prefix);
        if (sb.length < pb.length) return false;
        for (uint256 i = 0; i < pb.length; i++) {
            if (sb[i] != pb[i]) return false;
        }
        return true;
    }

    function _contains(string memory s, string memory sub) internal pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory nb = bytes(sub);
        if (nb.length == 0 || sb.length < nb.length) return false;
        for (uint256 i = 0; i <= sb.length - nb.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < nb.length; j++) {
                if (sb[i + j] != nb[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }
}
