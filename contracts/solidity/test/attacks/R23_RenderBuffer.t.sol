// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {TraitStorage} from "../../render/TraitStorage.sol";
import {FrenRenderer} from "../../render/FrenRenderer.sol";

contract R23RenderBuffer is Test {
    function test_denseValidUploadedLayerRendersCompleteSVG() public {
        TraitStorage store = new TraitStorage();
        FrenRenderer renderer = new FrenRenderer(store);
        store.storePalette(hex"ffffff000000");
        // Valid 120x120 canvas, two alternating palette indices: 14,400 runs.
        bytes memory blob = new bytes(10 + 7200);
        blob[5] = bytes1(uint8(120)); blob[6] = bytes1(uint8(120));
        blob[7] = bytes1(uint8(2)); blob[8] = 0; blob[9] = bytes1(uint8(1));
        for (uint256 i = 10; i < blob.length; ++i) blob[i] = 0x12;
        store.storeTrait(0, blob);
        bytes memory svg = bytes(renderer.renderSVG(0, 0, 0, 0));
        assertGt(svg.length, 700_000);
        assertEq(svg[svg.length-6], bytes1('<'));
        assertEq(svg[svg.length-1], bytes1('>'));
    }
}
