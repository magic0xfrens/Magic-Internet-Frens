// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SSTORE2} from "./SSTORE2.sol";
import {ILiquidatorMintable, LiqStats} from "../cauldron/ILiquidatorMintable.sol";

/**
 * @title LiquidatoorRenderer
 * @notice Draws a Liquidatoor badge entirely on-chain: the scope artwork plus a
 *         terminal readout of the liquidation it commemorates.
 *
 *  ONE instance serves EVERY collection. `tokenURI` reads the stats back off
 *  `msg.sender` — whichever collection is asking — so the per-iteration
 *  collections and the genesis MiFrens all share this deployment. That also
 *  means a badge minted by a future collection renders correctly with no
 *  redeploy here.
 *
 *  This is a SEPARATE renderer from {FrenRenderer}. That one composes pixel-art
 *  wizards out of trait blobs; a badge is different artwork with a different
 *  data source, so a collection wires them independently: `renderer` for the art
 *  tranche, `liquidatorRenderer` for the badge tranche.
 *
 *  ── Why no Base64 ──────────────────────────────────────────────────────────
 *  The artwork is ~70-95KB per side. Base64-encoding that in Solidity costs on
 *  the order of 10M gas and expands the payload by a third, which risks tripping
 *  the `eth_call` ceilings marketplaces read `tokenURI` through. A plain
 *  `data:...;utf8,` URI is a spec-compliant alternative that costs only the
 *  concatenation — so the art is stored PRE-ESCAPED (see {setArt}) and simply
 *  spliced in.
 */
contract LiquidatoorRenderer {
    error NotOwner();
    error NoArt();

    address public owner;

    /// @notice SSTORE2 chunks holding the pre-escaped SVG body for each side.
    ///         Split because a single contract cannot exceed the EIP-170 limit.
    address[] public longArt;
    address[] public shortArt;

    event ArtSet(bool isLong, uint256 chunks, uint256 bytesTotal);

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address to) external {
        if (msg.sender != owner) revert NotOwner();
        owner = to;
    }

    /**
     * @notice Store one side's artwork as SSTORE2 chunks.
     * @dev `chunks` are concatenated verbatim into the SVG, so they must ALREADY
     *      be URI-escaped for a utf8 data URI — in practice `#` written as `%23`
     *      (or `rgb()` colours used instead) and no raw `%`. Escaping here would
     *      mean re-scanning ~90KB on every read; doing it at write time makes
     *      `tokenURI` a straight copy.
     */
    function setArt(bool isLong, bytes[] calldata chunks) external {
        if (msg.sender != owner) revert NotOwner();
        address[] storage dst = isLong ? longArt : shortArt;
        while (dst.length != 0) dst.pop();
        _append(dst, isLong, chunks);
    }

    /**
     * @notice Add more chunks to a side WITHOUT clearing what is already there.
     * @dev The artwork is ~70-95KB per side, and SSTORE2 costs roughly 200 gas
     *      per byte — so uploading a whole side in one call is ~30M gas. That
     *      exceeds what most RPCs will accept for a single transaction and is
     *      above mainnet's block limit entirely, which made the deploy fail with
     *      "gas limit too high" rather than anything being wrong with the art.
     *
     *      Splitting across transactions needs an append that does not wipe the
     *      previous batch, which {setArt} does by design. Use setArt for the
     *      first batch and this for the rest.
     */
    function appendArt(bool isLong, bytes[] calldata chunks) external {
        if (msg.sender != owner) revert NotOwner();
        _append(isLong ? longArt : shortArt, isLong, chunks);
    }

    function _append(address[] storage dst, bool isLong, bytes[] calldata chunks) private {
        uint256 total;
        for (uint256 i; i < chunks.length; ++i) {
            dst.push(SSTORE2.write(chunks[i]));
            total += chunks[i].length;
        }
        emit ArtSet(isLong, dst.length, total);
    }

    /// @notice The stored artwork for one side, reassembled.
    function art(bool isLong) public view returns (bytes memory out) {
        address[] storage src = isLong ? longArt : shortArt;
        for (uint256 i; i < src.length; ++i) {
            out = bytes.concat(out, SSTORE2.read(src[i]));
        }
    }

    // -----------------------------------------------------------------------
    // Rendering
    // -----------------------------------------------------------------------

    /// @notice ERC-721 metadata for badge `tokenId` owned by the CALLING
    ///         collection. Returns a utf8 JSON data URI with the SVG inline.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        LiqStats memory s = ILiquidatorMintable(msg.sender).liqStats(tokenId);
        return string.concat(
            "data:application/json;utf8,",
            "{\"name\":\"Liquidatoor #", _u(tokenId),
            "\",\"description\":\"A trophy struck on-chain when this fren's trade liquidated a leveraged position on the Cauldron perp engine. Rendered entirely from chain state.\",",
            _attributes(s),
            ",\"image\":\"data:image/svg+xml;utf8,", renderSVG(tokenId, s), "\"}"
        );
    }

    /// @notice The badge SVG for an explicit stat set — lets a caller preview a
    ///         badge without owning one, and keeps the renderer testable.
    function renderSVG(uint256 tokenId, LiqStats memory s)
        public
        view
        returns (string memory)
    {
        bytes memory body = art(s.wasLong);
        if (body.length == 0) revert NoArt();

        // Side palette. Written as rgb() rather than hex so the whole document
        // is free of `#`, which would otherwise need escaping in a utf8 URI.
        string memory accent = s.wasLong ? "rgb(60,224,114)" : "rgb(255,59,70)";
        string memory glow   = s.wasLong ? "rgb(123,255,166)" : "rgb(255,107,115)";
        string memory ink    = s.wasLong ? "rgb(214,255,226)" : "rgb(255,217,220)";
        string memory tint   = s.wasLong ? "rgb(30,210,90)" : "rgb(255,40,55)";

        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='1000' height='1000' viewBox='0 0 1000 1000'>",
            "<defs>",
            "<linearGradient id='ts' x1='0' y1='0' x2='0' y2='1'>",
            "<stop offset='0' stop-color='rgb(5,7,10)' stop-opacity='0.92'/>",
            "<stop offset='1' stop-color='rgb(5,7,10)' stop-opacity='0'/></linearGradient>",
            "<radialGradient id='vg' cx='50%' cy='42%' r='66%'>",
            "<stop offset='0.5' stop-color='rgb(0,0,0)' stop-opacity='0'/>",
            "<stop offset='1' stop-color='rgb(0,0,0)' stop-opacity='0.7'/></radialGradient>",
            "<pattern id='sc' width='4' height='4' patternUnits='userSpaceOnUse'>",
            "<rect width='4' height='2' fill='rgb(0,0,0)' opacity='0.16'/></pattern>",
            "<clipPath id='fc'><rect x='24' y='24' width='952' height='952' rx='14'/></clipPath>",
            "</defs>",
            "<rect width='1000' height='1000' fill='rgb(5,7,10)'/>",
            "<g clip-path='url(%23fc)'>",
            "<rect x='24' y='24' width='952' height='724' fill='rgb(10,15,20)'/>",
            // 1024x775 source art scaled into the 952x724 slot
            "<g transform='translate(24,24) scale(0.9297,0.9342)'>", string(body), "</g>",
            "<rect x='24' y='24' width='952' height='724' fill='", tint, "' opacity='0.10'/>",
            "<rect x='24' y='24' width='952' height='724' fill='url(%23vg)'/>",
            "<rect x='24' y='24' width='952' height='724' fill='url(%23sc)'/>",
            "<rect x='24' y='24' width='952' height='150' fill='url(%23ts)'/>",
            _hud(tokenId, accent, glow),
            _readout(s, accent, ink),
            "</g>",
            "<rect x='24' y='24' width='952' height='952' rx='14' fill='none' stroke='",
            accent, "' stroke-width='3' opacity='0.55'/></svg>"
        );
    }

    // -----------------------------------------------------------------------
    // Pieces
    // -----------------------------------------------------------------------

    function _hud(uint256 tokenId, string memory accent, string memory glow)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "<text x='56' y='78' font-family='monospace' font-size='24' fill='rgb(196,214,205)'>",
            "root@cauldron:~$ <tspan fill='rgb(255,255,255)'>liquidate --id ", _pad4(tokenId),
            "</tspan></text>",
            "<text x='56' y='126' font-family='monospace' font-size='23' letter-spacing='3' fill='",
            glow, "'>&gt;&gt; TARGET LOCKED</text>",
            "<circle cx='884' cy='118' r='8' fill='", accent, "'/>",
            "<text x='968' y='126' font-family='monospace' font-size='23' fill='rgb(255,255,255)' text-anchor='end'>REC</text>"
        );
    }

    function _readout(LiqStats memory s, string memory accent, string memory ink)
        internal
        pure
        returns (string memory)
    {
        // A badge minted before stats existed has nothing to show; say so rather
        // than printing a wall of zeroes that reads like real data.
        if (s.victim == address(0)) {
            return string.concat(
                "<rect x='24' y='770' width='952' height='206' fill='rgb(7,11,16)'/>",
                "<text x='500' y='885' font-family='monospace' font-size='22' fill='",
                ink, "' text-anchor='middle'>KILL RECORD UNAVAILABLE</text>"
            );
        }
        return string.concat(
            "<rect x='24' y='770' width='952' height='206' fill='rgb(7,11,16)'/>",
            _line(812, "VICTIM",   _addr(s.victim),                accent, ink),
            _line(838, "SIDE",     s.wasLong ? "LONG" : "SHORT",   accent, ink),
            _line(864, "SIZE",     _eth(uint256(s.collateralWei) * s.leverage), accent, ink),
            _line(890, "LEVERAGE", string.concat(_u(s.leverage), "x"), accent, ink),
            _line(916, "ENTRY",    _gwei(s.entryPrice),            accent, ink),
            _line(942, "LIQ",      _gwei(s.liqPrice),              accent, ink),
            _line(968, "BOUNTY",   _eth(s.bountyWei),              accent, ink)
        );
    }

    function _line(
        uint256 y,
        string memory label,
        string memory value,
        string memory accent,
        string memory ink
    ) internal pure returns (string memory) {
        string memory ys = _u(y);
        return string.concat(
            "<text x='56' y='", ys, "' font-family='monospace' font-size='19' fill='", accent, "'>&gt;</text>",
            "<text x='88' y='", ys, "' font-family='monospace' font-size='19' fill='rgb(125,143,136)'>", label, "</text>",
            "<text x='944' y='", ys, "' font-family='monospace' font-size='19' fill='", ink, "' text-anchor='end'>", value, "</text>"
        );
    }

    function _attributes(LiqStats memory s) internal pure returns (string memory) {
        if (s.victim == address(0)) {
            return "\"attributes\":[{\"trait_type\":\"Kill record\",\"value\":\"Unavailable\"}]";
        }
        return string.concat(
            "\"attributes\":[",
            "{\"trait_type\":\"Side\",\"value\":\"", s.wasLong ? "Long" : "Short", "\"},",
            "{\"trait_type\":\"Leverage\",\"value\":", _u(s.leverage), "},",
            "{\"trait_type\":\"Victim\",\"value\":\"", _addr(s.victim), "\"},",
            "{\"trait_type\":\"Bounty ETH\",\"value\":\"", _eth(s.bountyWei), "\"},",
            "{\"trait_type\":\"Block\",\"value\":", _u(s.blockNo), "}]"
        );
    }

    // -----------------------------------------------------------------------
    // Formatting
    // -----------------------------------------------------------------------

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 n = v;
        uint256 len;
        while (n != 0) { len++; n /= 10; }
        bytes memory b = new bytes(len);
        while (v != 0) { b[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(b);
    }

    function _pad4(uint256 v) internal pure returns (string memory) {
        string memory s = _u(v);
        uint256 n = bytes(s).length;
        if (n >= 4) return s;
        if (n == 3) return string.concat("0", s);
        if (n == 2) return string.concat("00", s);
        return string.concat("000", s);
    }

    /// @dev "0x1234...abcd" — the shortened form used across the UI. The four
    ///      leading nibbles live at bits 159..144, so they are read down from
    ///      156; indexing up from 152 runs past the 160-bit word and returns
    ///      zeroes for the first two characters.
    function _addr(address a) internal pure returns (string memory) {
        bytes memory hexd = "0123456789abcdef";
        uint160 v = uint160(a);
        bytes memory top = new bytes(4);
        bytes memory tail = new bytes(4);
        for (uint256 i; i < 4; ++i) {
            top[i] = hexd[uint8(v >> (156 - 4 * i)) & 0xf];
            tail[3 - i] = hexd[uint8(v >> (4 * i)) & 0xf];
        }
        return string.concat("0x", string(top), "...", string(tail));
    }

    /// @dev Wei as gwei, 4dp. Token prices here are ~1e-9 ETH, so rendering them
    ///      in ETH gives "0.0000" for every badge; gwei is also the unit the app
    ///      quotes prices in, so the badge and the chart agree.
    function _gwei(uint256 wei_) internal pure returns (string memory) {
        uint256 whole = wei_ / 1e9;
        uint256 frac = (wei_ % 1e9) / 1e5; // 4 dp
        bytes memory f = new bytes(4);
        for (uint256 i; i < 4; ++i) {
            f[3 - i] = bytes1(uint8(48 + frac % 10));
            frac /= 10;
        }
        return string.concat(_u(whole), ".", string(f), " gwei");
    }

    /// @dev Wei as a fixed 4-decimal figure. Truncates rather than rounds, so a
    ///      displayed value can never overstate what actually moved.
    function _eth(uint256 wei_) internal pure returns (string memory) {
        uint256 whole = wei_ / 1e18;
        uint256 frac = (wei_ % 1e18) / 1e14; // 4 dp
        bytes memory f = new bytes(4);
        for (uint256 i; i < 4; ++i) {
            f[3 - i] = bytes1(uint8(48 + frac % 10));
            frac /= 10;
        }
        return string.concat(_u(whole), ".", string(f));
    }
}
