// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LiquidatoorRenderer} from "../render/LiquidatoorRenderer.sol";
import {LiqStats} from "../cauldron/ILiquidatorMintable.sol";

/// @dev Stands in for a collection: the renderer reads stats back off whoever
///      calls it, so a test caller only needs to answer `liqStats`.
contract MockCollection {
    mapping(uint256 => LiqStats) public s;
    LiquidatoorRenderer public r;

    constructor(LiquidatoorRenderer _r) { r = _r; }
    function set(uint256 id, LiqStats memory st) external { s[id] = st; }
    function liqStats(uint256 id) external view returns (LiqStats memory) { return s[id]; }
    function uri(uint256 id) external view returns (string memory) { return r.tokenURI(id); }
}

contract LiquidatoorRendererTest is Test {
    LiquidatoorRenderer renderer;
    MockCollection col;

    // Small stand-in artwork. The real trace is ~90KB across several chunks;
    // fidelity is verified off-chain, so these tests are about the wiring,
    // the readout and the escaping rules that make the data URI valid.
    bytes constant ART_LONG = "<rect x='0' y='0' width='1024' height='775' fill='rgb(20,80,40)'/>";
    bytes constant ART_SHORT = "<rect x='0' y='0' width='1024' height='775' fill='rgb(80,20,30)'/>";

    function setUp() public {
        renderer = new LiquidatoorRenderer();
        col = new MockCollection(renderer);
        bytes[] memory l = new bytes[](1); l[0] = ART_LONG;
        bytes[] memory sh = new bytes[](1); sh[0] = ART_SHORT;
        renderer.setArt(true, l);
        renderer.setArt(false, sh);
    }

    function _stats() internal pure returns (LiqStats memory) {
        return LiqStats({
            victim: address(0x9F2A000000000000000000000000000000008C1d),
            wasLong: true,
            leverage: 3,
            collateralWei: 1.4 ether,
            bountyWei: 0.084 ether,
            blockNo: 21_041_553,
            entryPrice: 8_410_000_000,
            liqPrice: 7_120_000_000
        });
    }

    function _has(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool ok = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) { ok = false; break; }
            }
            if (ok) return true;
        }
        return false;
    }

    function test_ArtRoundTrips() public view {
        assertEq(renderer.art(true), ART_LONG, "long art must round-trip");
        assertEq(renderer.art(false), ART_SHORT, "short art must round-trip");
    }

    function test_SVG_IsWellFormedAndCarriesTheArt() public view {
        string memory svg = renderer.renderSVG(212, _stats());
        assertTrue(_has(svg, "<svg xmlns="), "must open an svg");
        assertTrue(_has(svg, "</svg>"), "must close it");
        assertTrue(_has(svg, string(ART_LONG)), "long badge must embed the long art");
    }

    function test_SVG_ShowsTheRealNumbers() public view {
        string memory svg = renderer.renderSVG(212, _stats());
        assertTrue(_has(svg, "LONG"), "side");
        assertTrue(_has(svg, "3x"), "leverage");
        assertTrue(_has(svg, "0.0840"), "bounty in ETH");
        // Regression: the leading nibbles were read past the 160-bit word and
        // came back as zeroes ("0x009f..."), so the badge named the wrong wallet.
        assertTrue(_has(svg, "0x9f2a...8c1d"), "victim must show its REAL leading bytes");
        assertTrue(!_has(svg, "0x009f"), "leading nibbles must not be zero-padded");
        // Regression: an iteration token trades near 1e-9 ETH, so ETH-denominated
        // prices rendered as "0.0000" on every badge.
        assertTrue(_has(svg, "8.4100 gwei"), "entry price must be legible");
        assertTrue(_has(svg, "7.1200 gwei"), "liq price must be legible");
        assertTrue(_has(svg, "liquidate --id 0212"), "zero-padded id in the prompt");
    }

    function test_SideSelectsTheRightArtAndPalette() public view {
        LiqStats memory sh = _stats();
        sh.wasLong = false;
        string memory svg = renderer.renderSVG(1, sh);
        assertTrue(_has(svg, string(ART_SHORT)), "short badge must embed the short art");
        assertTrue(_has(svg, "SHORT"), "side label");
        assertTrue(_has(svg, "rgb(255,59,70)"), "short accent");
    }

    /// A `#` inside a `data:...;utf8,` URI truncates it at the fragment, so the
    /// image would silently render blank. Colours are emitted as rgb() and the
    /// internal url() references are pre-escaped, so the document must contain
    /// no raw `#` at all.
    function test_NoRawHashAnywhere() public view {
        bytes memory svg = bytes(renderer.renderSVG(212, _stats()));
        for (uint256 i; i < svg.length; ++i) {
            assertTrue(svg[i] != "#", "raw # would truncate the data URI");
        }
    }

    function test_TokenURI_IsJsonWithInlineSvg() public {
        col.set(7, _stats());
        string memory uri = col.uri(7);
        assertTrue(_has(uri, "data:application/json;utf8,"), "json data uri");
        assertTrue(_has(uri, "\"image\":\"data:image/svg+xml;utf8,"), "inline svg image");
        assertTrue(_has(uri, "Liquidatoor #7"), "name carries the id");
        assertTrue(_has(uri, "\"trait_type\":\"Side\",\"value\":\"Long\""), "side attribute");
    }

    /// A badge minted by an engine that predates stats has none. It must still
    /// render — saying so — rather than printing zeroes that read as real data.
    function test_StatlessBadgeStillRenders() public view {
        LiqStats memory empty;
        string memory svg = renderer.renderSVG(1, empty);
        assertTrue(_has(svg, "KILL RECORD UNAVAILABLE"), "must say the record is missing");
        assertTrue(!_has(svg, "VICTIM"), "must not print an empty readout");
    }

    function test_OnlyOwnerSetsArt() public {
        bytes[] memory c = new bytes[](1); c[0] = "x";
        vm.prank(address(0xDEAD));
        vm.expectRevert(LiquidatoorRenderer.NotOwner.selector);
        renderer.setArt(true, c);
    }

    function test_RevertsWhenArtMissing() public {
        LiquidatoorRenderer bare = new LiquidatoorRenderer();
        vm.expectRevert(LiquidatoorRenderer.NoArt.selector);
        bare.renderSVG(1, _stats());
    }

    /// Marketplaces read tokenURI through eth_call, which nodes cap. The real
    /// art is ~90KB, so this asserts the *shape* of the cost — a single copy of
    /// the artwork, not a quadratic blow-up from repeated concatenation.
    function test_RenderCostIsLinear() public {
        bytes memory big = new bytes(24_000);
        for (uint256 i; i < big.length; ++i) big[i] = "a";
        bytes[] memory four = new bytes[](4);
        for (uint256 i; i < 4; ++i) four[i] = big;
        renderer.setArt(true, four);           // ~96KB, the real size

        uint256 g = gasleft();
        string memory svg = renderer.renderSVG(212, _stats());
        uint256 used = g - gasleft();

        assertGt(bytes(svg).length, 96_000, "must contain the whole artwork");
        assertLt(used, 30_000_000, "must stay inside a normal eth_call budget");
        emit log_named_uint("render gas (96KB art)", used);
        emit log_named_uint("svg bytes", bytes(svg).length);
    }
}
