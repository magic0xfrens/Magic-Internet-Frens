// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {LiquidatoorRenderer} from "../render/LiquidatoorRenderer.sol";

/**
 * @title BadgeArtLib
 * @notice Deploys {LiquidatoorRenderer} and uploads the badge artwork, so both
 *         the one-shot launchpad deploy and a standalone re-upload share one
 *         implementation rather than two copies that drift.
 *
 *  The art files are the traced SVG BODY only — no <svg> wrapper — and must
 *  already be escaped for a utf8 data URI (`#` written `%23`). See
 *  {LiquidatoorRenderer.setArt} for why escaping happens at write time.
 *
 *  Sized to the EIP-170 limit: each SSTORE2 pointer is a contract, so a chunk
 *  above ~24,576 bytes cannot be deployed. 24,000 leaves headroom for the
 *  pointer's own prefix byte.
 */
library BadgeArtLib {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant CHUNK = 24_000;

    /// @notice Split `body` into SSTORE2-sized pieces.
    function chunk(bytes memory body) internal pure returns (bytes[] memory out) {
        uint256 n = (body.length + CHUNK - 1) / CHUNK;
        out = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            uint256 off = i * CHUNK;
            uint256 len = off + CHUNK > body.length ? body.length - off : CHUNK;
            bytes memory c = new bytes(len);
            for (uint256 j; j < len; ++j) c[j] = body[off + j];
            out[i] = c;
        }
    }

    /**
     * @notice Upload both sides' artwork into `r`.
     * @dev Reverts rather than half-uploading: a renderer holding one side would
     *      revert with NoArt for every badge on the other, which reads as a
     *      broken collection rather than an incomplete deploy.
     */
    function upload(LiquidatoorRenderer r, string memory longPath, string memory shortPath)
        internal
    {
        bytes memory longBody = vm.readFileBinary(longPath);
        bytes memory shortBody = vm.readFileBinary(shortPath);
        require(longBody.length != 0, "BadgeArt: empty long art");
        require(shortBody.length != 0, "BadgeArt: empty short art");
        _assertEscaped(longBody);
        _assertEscaped(shortBody);

        //  ONE CHUNK PER TRANSACTION. SSTORE2 costs ~200 gas per byte, so a
        //  24KB chunk is ~5M gas and a whole 94KB side in one call is ~30M —
        //  above what RPCs accept for a single transaction, and above mainnet's
        //  block limit outright. That is what made the deploy fail with "gas
        //  limit too high"; the art itself was never the problem.
        //
        //  The first chunk uses setArt, which CLEARS the side, so a re-run
        //  replaces the art rather than appending to it. Every later chunk uses
        //  appendArt, which would otherwise be wiped by the next setArt.
        _uploadSide(r, true, chunk(longBody));
        _uploadSide(r, false, chunk(shortBody));
    }

    function _uploadSide(LiquidatoorRenderer r, bool isLong, bytes[] memory chunks) private {
        for (uint256 i; i < chunks.length; ++i) {
            bytes[] memory one = new bytes[](1);
            one[0] = chunks[i];
            if (i == 0) r.setArt(isLong, one);
            else r.appendArt(isLong, one);
        }
    }

    /// @dev A raw '#' terminates a utf8 data URI at the fragment, so the image
    ///      silently renders blank. Catch it here, before it is immutable.
    function _assertEscaped(bytes memory art) private pure {
        for (uint256 i; i < art.length; ++i) {
            require(art[i] != "#", "BadgeArt: unescaped # (use %23)");
        }
    }
}
