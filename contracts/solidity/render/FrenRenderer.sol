// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {TraitStorage} from "./TraitStorage.sol";

/**
 * @title FrenRenderer
 * @notice Fully on-chain renderer for MagicFrens NFTs. Reads the compressed
 *         pixel-art trait blobs from {TraitStorage}, decodes them, and composes
 *         a single layered SVG (deterministic gradient background + face + body +
 *         item), returned as a base64 data-URI in ERC-721 metadata.
 *
 *  Reproduces, on-chain and byte-faithfully, what the frontend `FrenSprite`
 *  component paints: 120x120 pixel canvas, gradient hashed from the traits, and
 *  the three trait layers painted face -> body -> item (item on top).
 */
contract FrenRenderer {
    using Strings for uint256;

    uint256 private constant CANVAS = 120;

    // Layer type ids used by the compressor's traitKey scheme.
    uint8 private constant LAYER_BODY = 0;
    uint8 private constant LAYER_FACE = 1;
    uint8 private constant LAYER_ITEM = 2;

    TraitStorage public immutable store;

    constructor(TraitStorage _store) {
        store = _store;
    }

    // ---------------------------------------------------------------------
    // Public API
    // ---------------------------------------------------------------------

    /// @notice ERC-721 metadata JSON (base64 data-URI) for a set of traits.
    function tokenURI(
        uint256 tokenId,
        uint8 classIdx,
        uint8 bodyIdx,
        uint8 faceIdx,
        uint8 itemIdx
    ) external view returns (string memory) {
        string memory svg = renderSVG(classIdx, bodyIdx, faceIdx, itemIdx);
        string memory image =
            string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)));

        bytes memory json = abi.encodePacked(
            '{"name":"MagicFren #',
            tokenId.toString(),
            '","description":"Fully on-chain MagicFrens. Art composed live from pixel data stored on-chain.",',
            '"attributes":[',
            _attributes(classIdx, bodyIdx, faceIdx, itemIdx),
            '],"image":"',
            image,
            '"}'
        );

        return string.concat(
            "data:application/json;base64,", Base64.encode(json)
        );
    }

    /// @notice The composed SVG string for a set of traits.
    function renderSVG(
        uint8 classIdx,
        uint8 bodyIdx,
        uint8 faceIdx,
        uint8 itemIdx
    ) public view returns (string memory) {
        bytes memory pal = store.getPalette();

        // Buffer sized for the worst realistic case (~three full layers of runs).
        Buf memory b = _newBuf(200_000);

        _appendHeader(b, bodyIdx, faceIdx, itemIdx);

        // z-order: face (bottom), body, item (top) — matches FrenSprite.
        _appendLayer(b, LAYER_FACE, _faceClass(classIdx), faceIdx, pal);
        _appendLayer(b, LAYER_BODY, classIdx, bodyIdx, pal);
        _appendLayer(b, LAYER_ITEM, classIdx, itemIdx, pal);

        _append(b, "</svg>");
        return string(_finalize(b));
    }

    // ---------------------------------------------------------------------
    // SVG assembly
    // ---------------------------------------------------------------------

    function _appendHeader(Buf memory b, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx)
        private
        pure
    {
        (string memory top, string memory bot) = _gradient(bodyIdx, faceIdx, itemIdx);
        _append(
            b,
            "<svg xmlns='http://www.w3.org/2000/svg' width='480' height='480' "
            "viewBox='0 0 120 120' shape-rendering='crispEdges'>"
            "<defs><linearGradient id='g' x1='0' y1='0' x2='0' y2='1'>"
            "<stop offset='0' stop-color='#"
        );
        _append(b, top);
        _append(b, "'/><stop offset='1' stop-color='#");
        _append(b, bot);
        _append(
            b,
            "'/></linearGradient></defs>"
            "<rect width='120' height='120' fill='url(#g)'/>"
        );
    }

    /// @dev Decoded trait layer, ready for row-by-row painting.
    struct Layer {
        bytes blob;
        uint256 pixOff; // byte offset of pixel data within blob
        uint256 minX;
        uint256 minY;
        uint256 w;
        uint256 h;
        string[] colors; // index 0 == transparent
    }

    /// @dev Decode one trait blob and append its pixels as row run-length <rect>s.
    function _appendLayer(
        Buf memory b,
        uint8 layerType,
        uint8 classIdx,
        uint8 layerIdx,
        bytes memory pal
    ) private view {
        bytes memory blob = store.getTraitOrEmpty(layerType, classIdx, layerIdx);
        if (blob.length < 8) return; // missing or malformed -> skip layer

        // Header (8 bytes): layerType, classIdx, layerIdx, minX, minY, w, h, localSize
        uint256 localSize = uint8(blob[7]);

        // Local palette -> precomputed "#rrggbb" colors (index 0 == transparent).
        string[] memory colors = new string[](localSize + 1);
        for (uint256 i = 0; i < localSize; i++) {
            colors[i + 1] = _colorAt(pal, uint8(blob[8 + i]));
        }

        Layer memory L = Layer({
            blob: blob,
            pixOff: 8 + localSize,
            minX: uint8(blob[3]),
            minY: uint8(blob[4]),
            w: uint8(blob[5]),
            h: uint8(blob[6]),
            colors: colors
        });

        for (uint256 row = 0; row < L.h; row++) {
            _appendRow(b, L, row);
        }
    }

    /// @dev Paint a single row of a layer as run-length-encoded <rect> elements.
    function _appendRow(Buf memory b, Layer memory L, uint256 row) private pure {
        uint256 w = L.w;
        uint256 base = row * w;
        uint256 col = 0;
        while (col < w) {
            uint256 nib = _nibble(L.blob, L.pixOff, base + col);
            if (nib == 0) {
                col++;
                continue;
            }
            // Extend the run while the same local color repeats.
            uint256 next = col + 1;
            while (next < w && _nibble(L.blob, L.pixOff, base + next) == nib) {
                next++;
            }

            _append(b, "<rect x='");
            _appendUint(b, L.minX + col);
            _append(b, "' y='");
            _appendUint(b, L.minY + row);
            _append(b, "' width='");
            _appendUint(b, next - col);
            _append(b, "' height='1' fill='");
            _append(b, L.colors[nib]);
            _append(b, "'/>");

            col = next;
        }
    }

    /// @dev Read the 4-bit nibble for pixel `idx` (high nibble first per byte).
    function _nibble(bytes memory blob, uint256 pixOff, uint256 idx)
        private
        pure
        returns (uint256)
    {
        uint256 byteVal = uint8(blob[pixOff + (idx >> 1)]);
        return (idx & 1 == 0) ? (byteVal >> 4) : (byteVal & 0x0F);
    }

    // ---------------------------------------------------------------------
    // Colors & gradient
    // ---------------------------------------------------------------------

    /// @dev "#rrggbb" for a global palette index.
    function _colorAt(bytes memory pal, uint256 gi) private pure returns (string memory) {
        uint256 p = gi * 3;
        if (p + 2 >= pal.length) return "#000000";
        bytes memory out = new bytes(7);
        out[0] = "#";
        _hexByte(out, 1, uint8(pal[p]));
        _hexByte(out, 3, uint8(pal[p + 1]));
        _hexByte(out, 5, uint8(pal[p + 2]));
        return string(out);
    }

    bytes16 private constant HEX = "0123456789ABCDEF";

    function _hexByte(bytes memory out, uint256 at, uint8 v) private pure {
        out[at] = HEX[v >> 4];
        out[at + 1] = HEX[v & 0x0F];
    }

    /// @dev Replicates FrenSprite.frenGradient / FrenForge._getTraitHash.
    function _gradient(uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx)
        private
        pure
        returns (string memory top, string memory bot)
    {
        uint256 hash =
            (uint256(bodyIdx) * 7919 + uint256(faceIdx) * 6271 + uint256(itemIdx) * 4813) & 0xFFFF;
        int256 n0 = int256((hash >> 0) & 0xF) - 8;
        int256 n4 = int256((hash >> 4) & 0xF) - 8;
        int256 n8 = int256((hash >> 8) & 0xF) - 8;

        top = _rgbHex(_clamp(0xF7 + n0), _clamp(0x93 + n4), _clamp(0x1A + n8));
        bot = _rgbHex(_clamp(0x3D + n0), _clamp(0x24 + n4), _clamp(0x07 + n8));
    }

    function _clamp(int256 v) private pure returns (uint8) {
        if (v < 0) return 0;
        if (v > 255) return 255;
        return uint8(uint256(v));
    }

    function _rgbHex(uint8 r, uint8 g, uint8 bl) private pure returns (string memory) {
        bytes memory out = new bytes(6);
        _hexByte(out, 0, r);
        _hexByte(out, 2, g);
        _hexByte(out, 4, bl);
        return string(out);
    }

    /// @dev Faces exist only for the universal set (0), Gnome (5), Elf (6).
    function _faceClass(uint8 classIdx) private pure returns (uint8) {
        if (classIdx == 5) return 5;
        if (classIdx == 6) return 6;
        return 0;
    }

    // ---------------------------------------------------------------------
    // Attributes
    // ---------------------------------------------------------------------

    function _attributes(uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            '{"trait_type":"Class","value":"', _className(classIdx), '"},',
            '{"trait_type":"Body","value":"', uint256(bodyIdx).toString(), '"},',
            '{"trait_type":"Face","value":"', uint256(faceIdx).toString(), '"},',
            '{"trait_type":"Item","value":"', uint256(itemIdx).toString(), '"}'
        );
    }

    function _className(uint8 classIdx) private pure returns (string memory) {
        if (classIdx == 0) return "Wizard";
        if (classIdx == 1) return "King";
        if (classIdx == 2) return "Knight";
        if (classIdx == 3) return "Apprentice";
        if (classIdx == 4) return "Peasant";
        if (classIdx == 5) return "Gnome";
        if (classIdx == 6) return "Elf";
        return "Unknown";
    }

    // ---------------------------------------------------------------------
    // Growable byte buffer (avoids O(n^2) string concat over many rects)
    // ---------------------------------------------------------------------

    struct Buf {
        bytes data;
        uint256 len;
    }

    function _newBuf(uint256 cap) private pure returns (Buf memory b) {
        b.data = new bytes(cap);
        b.len = 0;
    }

    function _append(Buf memory b, string memory s) private pure {
        bytes memory src = bytes(s);
        uint256 n = src.length;
        bytes memory dst = b.data;
        uint256 start = b.len;
        assembly {
            let d := add(add(dst, 0x20), start)
            let o := add(src, 0x20)
            mcopy(d, o, n)
        }
        b.len = start + n;
    }

    /// @dev Append a small unsigned integer (0..65535 range is enough here).
    function _appendUint(Buf memory b, uint256 v) private pure {
        if (v == 0) {
            _append(b, "0");
            return;
        }
        bytes memory tmp = new bytes(4);
        uint256 i = 4;
        while (v > 0) {
            i--;
            tmp[i] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        bytes memory dst = b.data;
        uint256 start = b.len;
        uint256 n = 4 - i;
        assembly {
            let d := add(add(dst, 0x20), start)
            let o := add(add(tmp, 0x20), i)
            mcopy(d, o, n)
        }
        b.len = start + n;
    }

    function _finalize(Buf memory b) private pure returns (bytes memory out) {
        out = b.data;
        uint256 len = b.len;
        assembly {
            mstore(out, len)
        }
    }
}
