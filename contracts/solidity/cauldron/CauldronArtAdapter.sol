// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev The FIVE-argument entrypoint the deployed `render/FrenRenderer` exposes.
///      Verified against the source: `render/FrenRenderer.sol:40-46`
///      `tokenURI(uint256,uint8,uint8,uint8,uint8)`.
interface IFrenRendererFive {
    function tokenURI(uint256 tokenId, uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx)
        external
        view
        returns (string memory);
}

/// @dev What a Cauldron collection exposes about a revealed token.
///      `CauldronCollection.sol:104` (`rarityOf`) and `:115` (`revealed`).
interface IRevealedArtSource {
    function rarityOf(uint256 tokenId) external view returns (uint8);
    function revealed(uint256 tokenId) external view returns (bool);
}

/**
 * @title CauldronArtAdapter
 * @notice Bridges the collection's ONE-argument renderer interface to the art
 *         renderer's FIVE-argument one.
 *
 *  THE BUG THIS CLOSES. `CauldronCollection.tokenURI` (`CauldronCollection.sol:412`)
 *  calls `ICollectionRenderer(renderer).tokenURI(tokenId)` — selector 0xc87b56dd.
 *  `FrenRenderer.tokenURI` is `tokenURI(uint256,uint8,uint8,uint8,uint8)` —
 *  selector 0xc1efba8b. Different selectors, and neither contract has a
 *  fallback, so pointing a collection straight at a FrenRenderer makes the
 *  REVEALED branch of `tokenURI` revert for every token, forever.
 *
 *  WHY AN ADAPTER RATHER THAN A 1-ARG OVERLOAD ON FrenRenderer.
 *  `FrenRenderer` is trait-indexed and collection-agnostic: it holds no token
 *  bookkeeping at all and is shared by every consumer of the art set (the peg
 *  wires it via `IPegRenderer.setRenderer`, `deploy/DeployRenderer.s.sol:9`).
 *  A 1-arg entrypoint there would have to know WHICH collection a tokenId
 *  belongs to, and the Cauldron mints a NEW collection every relaunch
 *  (`CauldronRegistry.sol:1183`), so any single collection address baked into
 *  the renderer is wrong one iteration later. The adapter takes the collection
 *  from `msg.sender` — the collection calls it — so ONE deployment serves every
 *  present and future iteration and the art contract stays untouched.
 *
 *  WHERE THE TRAITS COME FROM. A Cauldron collection stores NO trait indices:
 *  its only per-token art state is `rarityOf` and `revealed`
 *  (`CauldronCollection.sol:104,115`); `_reveal` writes nothing else
 *  (`CauldronCollection.sol:247-273`). So there is no pre-existing trait
 *  assignment to read, and this contract DEFINES the one canonical derivation:
 *
 *      seed = keccak256(abi.encodePacked(collection, tokenId, rarity))
 *
 *  which is
 *    - reproducible on-chain FOREVER (unlike the reveal seed, which is
 *      `blockhash(mintBlockOf[id])` and is unreachable on-chain after 256
 *      blocks — `CauldronCollection.sol:250-252`),
 *    - reproducible off-chain by the BaseURI art route from two public reads,
 *      so a collection switched between Renderer and BaseURI mode shows a
 *      holder the SAME creature, and
 *    - unknowable before the reveal, because `rarity` is the gacha roll and
 *      nothing else in the seed changes when it lands.
 *
 *  `api/cauldron/creature.ts` implements the identical formula; the two must be
 *  changed together or they will disagree.
 */
contract CauldronArtAdapter {
    /// @notice An unrevealed token has no art; its rarity is not rolled yet.
    error NotRevealed(uint256 tokenId);
    /// @notice `tokenURI` must be called BY a collection (it reads msg.sender).
    error NotACollection(address caller);

    /// @notice The 5-arg pixel-art renderer this adapter feeds.
    IFrenRendererFive public immutable frenRenderer;

    /// @dev Number of layers present per class in the uploaded art set, taken
    ///      from `compressed-traits/upload-manifest.json` (layerType 0 = body,
    ///      1 = face, 2 = item; classes 0..6). Faces exist only for the
    ///      universal set (0), Gnome (5) and Elf (6) — 12 each — which is why
    ///      {_faceClass} below mirrors `FrenRenderer._faceClass`
    ///      (`render/FrenRenderer.sol:257-261`).
    uint8 private constant CLASSES = 7;
    uint8 private constant FACES_PER_SET = 12;

    constructor(IFrenRendererFive renderer_) {
        frenRenderer = renderer_;
    }

    /// @notice ERC-721 metadata for `tokenId` of the CALLING collection.
    /// @dev Matches `ICollectionRenderer.tokenURI(uint256)` — selector
    ///      0xc87b56dd — which is what `CauldronCollection.sol:413` calls.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address collection = msg.sender;
        if (collection.code.length == 0) revert NotACollection(collection);
        (uint8 c, uint8 b, uint8 f, uint8 i) = traitsOf(collection, tokenId);
        return frenRenderer.tokenURI(tokenId, c, b, f, i);
    }

    /// @notice The canonical traits of `tokenId` in `collection`. Public so the
    ///         off-chain art route and the frontend can read the SAME answer the
    ///         renderer draws, instead of each guessing.
    function traitsOf(address collection, uint256 tokenId)
        public
        view
        returns (uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx)
    {
        if (!IRevealedArtSource(collection).revealed(tokenId)) revert NotRevealed(tokenId);
        uint8 rarity = IRevealedArtSource(collection).rarityOf(tokenId);
        uint256 s = uint256(keccak256(abi.encodePacked(collection, tokenId, rarity)));

        classIdx = uint8(s % CLASSES);
        bodyIdx = uint8((s >> 32) % _bodyCount(classIdx));
        faceIdx = uint8((s >> 64) % FACES_PER_SET);
        itemIdx = uint8((s >> 96) % _itemCount(classIdx));
    }

    /// @dev Bodies per class: Wizard 8, King 5, Knight 4, Apprentice 3,
    ///      Peasant 2, Gnome 2, Elf 3 (upload-manifest.json, layerType 0).
    function _bodyCount(uint8 classIdx) private pure returns (uint8) {
        if (classIdx == 0) return 8;
        if (classIdx == 1) return 5;
        if (classIdx == 2) return 4;
        if (classIdx == 3) return 3;
        if (classIdx == 6) return 3;
        return 2; // 4 (Peasant), 5 (Gnome)
    }

    /// @dev Items per class: Wizard 5, King 4, Knight 4, Apprentice 1,
    ///      Peasant 3, Gnome 4, Elf 1 (upload-manifest.json, layerType 2).
    function _itemCount(uint8 classIdx) private pure returns (uint8) {
        if (classIdx == 0) return 5;
        if (classIdx == 1) return 4;
        if (classIdx == 2) return 4;
        if (classIdx == 4) return 3;
        if (classIdx == 5) return 4;
        return 1; // 3 (Apprentice), 6 (Elf)
    }
}
