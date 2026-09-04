// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LiquidatoorRenderer} from "../render/LiquidatoorRenderer.sol";
import {LiqStats} from "../cauldron/ILiquidatorMintable.sol";
import {BadgeArtLib} from "../deploy/BadgeArtLib.sol";

contract Holder {
    LiqStats internal s;
    constructor(LiqStats memory _s) { s = _s; }
    function liqStats(uint256) external view returns (LiqStats memory) { return s; }
    function uri(LiquidatoorRenderer r, uint256 id) external view returns (string memory) {
        return r.tokenURI(id);
    }
}

/// @dev Writes the EXACT tokenURI string a marketplace receives, so the on-chain
///      metadata can be inspected byte-for-byte outside the EVM.
contract UriDump is Test {
    function test_DumpTokenURI() public {
        try vm.readFileBinary("render/badge-art/liq-short.svgbody") returns (bytes memory) {}
        catch { vm.skip(true); return; }

        LiquidatoorRenderer r = new LiquidatoorRenderer();
        BadgeArtLib.upload(
            r, "render/badge-art/liq-long.svgbody", "render/badge-art/liq-short.svgbody"
        );

        LiqStats memory s = LiqStats({
            victim: address(0x9F2A000000000000000000000000000000008C1d),
            wasLong: false,
            leverage: 3,
            collateralWei: 1.4 ether,
            bountyWei: 0.084 ether,
            blockNo: 21_041_553,
            entryPrice: 8_410_000_000,
            liqPrice: 9_900_000_000
        });
        Holder h = new Holder(s);
        string memory uri = h.uri(r, 212);
        vm.writeFile("render-out/tokenURI.txt", uri);
        emit log_named_uint("tokenURI bytes", bytes(uri).length);
    }
}
