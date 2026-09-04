// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SSTORE2} from "./SSTORE2.sol";

/**
 * @title TraitStorage
 * @notice On-chain repository for the MagicFrens compressed pixel-art trait blobs
 *         and the shared 247-color RGB palette.
 *
 *  Each blob is stored verbatim (the exact bytes produced by
 *  `scripts/compress-traits.mjs`) as immutable contract bytecode via SSTORE2:
 *
 *    [layerType:u8][classIdx:u8][layerIdx:u8]   3-byte identity
 *    [minX:u8][minY:u8][width:u8][height:u8]    bounding box on the 120x120 canvas
 *    [localPaletteSize:u8]                       N
 *    [globalIdx x N]                             indices into the global palette
 *    [pixelData]                                 ceil(w*h/2) bytes, 4-bit nibbles
 *                                                 0 = transparent, 1..15 = localPalette[n-1]
 *
 *  Traits are keyed exactly like the compressor's `traitKey`:
 *      traitKey = layerType * 65536 + classIdx * 256 + layerIdx
 *
 *  The palette is the raw RGB stream (no length header): 3 bytes per color.
 */
contract TraitStorage is Ownable {
    error TraitMissing(uint256 traitKey);
    error PaletteMissing();
    error LengthMismatch();

    /// @notice traitKey => SSTORE2 pointer holding the raw blob.
    mapping(uint256 => address) public traitPointer;

    /// @notice SSTORE2 pointer holding the raw RGB palette (3 bytes/color).
    address public palettePointer;

    /// @notice Frozen once the full art set is uploaded; blocks further writes.
    bool public frozen;

    event TraitStored(uint256 indexed traitKey, address pointer, uint256 size);
    event PaletteStored(address pointer, uint256 colorCount);
    event Frozen();

    constructor() Ownable(msg.sender) {}

    // ---------------------------------------------------------------------
    // Writes (owner only, until frozen)
    // ---------------------------------------------------------------------

    modifier notFrozen() {
        require(!frozen, "frozen");
        _;
    }

    /// @notice Store the global RGB palette (raw, 3 bytes per color, no header).
    function storePalette(bytes calldata rgb) external onlyOwner notFrozen {
        if (rgb.length == 0 || rgb.length % 3 != 0) revert LengthMismatch();
        palettePointer = SSTORE2.write(rgb);
        emit PaletteStored(palettePointer, rgb.length / 3);
    }

    /// @notice Store a single trait blob under its canonical traitKey.
    function storeTrait(uint256 key, bytes calldata blob) public onlyOwner notFrozen {
        address ptr = SSTORE2.write(blob);
        traitPointer[key] = ptr;
        emit TraitStored(key, ptr, blob.length);
    }

    /// @notice Batch upload of trait blobs.
    function storeTraits(uint256[] calldata traitKeys, bytes[] calldata blobs)
        external
        onlyOwner
        notFrozen
    {
        if (traitKeys.length != blobs.length) revert LengthMismatch();
        for (uint256 i = 0; i < traitKeys.length; i++) {
            storeTrait(traitKeys[i], blobs[i]);
        }
    }

    /// @notice Permanently lock the trait set. Irreversible.
    function freeze() external onlyOwner {
        frozen = true;
        emit Frozen();
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function traitKey(uint8 layerType, uint8 classIdx, uint8 layerIdx)
        public
        pure
        returns (uint256)
    {
        return uint256(layerType) * 65536 + uint256(classIdx) * 256 + uint256(layerIdx);
    }

    /// @notice Read a trait blob by key. Reverts if not present.
    function getTrait(uint256 key) external view returns (bytes memory) {
        address ptr = traitPointer[key];
        if (ptr == address(0)) revert TraitMissing(key);
        return SSTORE2.read(ptr);
    }

    /// @notice Read a trait blob by layer coordinates. Empty if not present.
    function getTraitOrEmpty(uint8 layerType, uint8 classIdx, uint8 layerIdx)
        external
        view
        returns (bytes memory)
    {
        address ptr = traitPointer[traitKey(layerType, classIdx, layerIdx)];
        if (ptr == address(0)) return "";
        return SSTORE2.read(ptr);
    }

    /// @notice Read the raw RGB palette. Reverts if not present.
    function getPalette() external view returns (bytes memory) {
        if (palettePointer == address(0)) revert PaletteMissing();
        return SSTORE2.read(palettePointer);
    }

    function hasTrait(uint256 key) external view returns (bool) {
        return traitPointer[key] != address(0);
    }
}
