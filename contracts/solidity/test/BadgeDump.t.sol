// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LiquidatoorRenderer} from "../render/LiquidatoorRenderer.sol";
import {LiqStats} from "../cauldron/ILiquidatorMintable.sol";

/// @dev Writes a real badge SVG — traced artwork and all — so the on-chain
///      output can be compared against the frontend design.
contract BadgeDump is Test {
    function test_DumpBadges() public {
        // Diagnostic, not an assertion: it needs the traced art on disk and the
        // `render` profile's fs permissions. Skip cleanly anywhere else so the
        // main suite is not held hostage to a local artefact.
        try vm.readFileBinary("render-out/art-long.txt") returns (bytes memory) {}
        catch { vm.skip(true); return; }

        LiquidatoorRenderer r = new LiquidatoorRenderer();
        for (uint256 side; side < 2; ++side) {
            bool isLong = side == 1;
            bytes memory body = vm.readFileBinary(
                isLong ? "render-out/art-long.txt" : "render-out/art-short.txt"
            );
            // Chunk to stay under EIP-170 per SSTORE2 pointer.
            uint256 n = (body.length + 23_999) / 24_000;
            bytes[] memory chunks = new bytes[](n);
            for (uint256 i; i < n; ++i) {
                uint256 off = i * 24_000;
                uint256 len = off + 24_000 > body.length ? body.length - off : 24_000;
                bytes memory c = new bytes(len);
                for (uint256 j; j < len; ++j) c[j] = body[off + j];
                chunks[i] = c;
            }
            r.setArt(isLong, chunks);

            LiqStats memory s = LiqStats({
                victim: address(0x9F2A000000000000000000000000000000008C1d),
                wasLong: isLong,
                leverage: 3,
                collateralWei: 1.4 ether,
                bountyWei: 0.084 ether,
                blockNo: 21_041_553,
                entryPrice: 8_410_000_000,
                liqPrice: 7_120_000_000
            });
            vm.writeFile(
                isLong ? "render-out/badge-long.svg" : "render-out/badge-short.svg",
                r.renderSVG(212, s)
            );
        }
    }
}
