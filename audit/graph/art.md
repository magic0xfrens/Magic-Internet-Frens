# Function graph — `art`

Current source-derived semantic map: **61 nodes** across **6 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `cauldron/CauldronArtAdapter.sol` | 137 |
| `render/FrenRenderer.sol` | 350 |
| `render/LiquidatoorRenderer.sol` | 307 |
| `render/SSTORE2.sol` | 61 |
| `render/TraitStorage.sol` | 128 |
| `deploy/BadgeArtLib.sol` | 85 |

## `IFrenRendererFive (declared in CauldronArtAdapter.sol)`

### `tokenURI/function` — CauldronArtAdapter.sol:8

- Signature: `function tokenURI(uint256 tokenId, uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx) external view returns (string memory)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `tokenURI` (CauldronArtAdapter.sol:8); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `IRevealedArtSource (declared in CauldronArtAdapter.sol)`

### `rarityOf/function` — CauldronArtAdapter.sol:17

- Signature: `function rarityOf(uint256 tokenId) external view returns (uint8)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `rarityOf` (CauldronArtAdapter.sol:17); authority and behavior are implementation-defined.
- Edges: none
- Observations: none

### `revealed/function` — CauldronArtAdapter.sol:18

- Signature: `function revealed(uint256 tokenId) external view returns (bool)`
- Authority: implementation-defined (declaration only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only at `revealed` (CauldronArtAdapter.sol:18); authority and behavior are implementation-defined.
- Edges: none
- Observations: none


## `CauldronArtAdapter`

### `constructor/constructor` — CauldronArtAdapter.sol:83

- Signature: `constructor(IFrenRendererFive renderer_)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `frenRenderer (line 84, immutable)`
- Value: NONE
- Reachability: Externally reachable at `constructor` (CauldronArtAdapter.sol:83); authority is deployer. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `tokenURI/function` — CauldronArtAdapter.sol:90

- Signature: `function tokenURI(uint256 tokenId) external view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `frenRenderer (line 94, immutable)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `tokenURI` (CauldronArtAdapter.sol:90); authority is anyone. Gate evidence is recorded separately.
- Edges: `CauldronArtAdapter.traitsOf (CauldronArtAdapter.sol:93), TRUSTED, in-cluster`; `IFrenRendererFive.tokenURI (CauldronArtAdapter.sol:94), UNTRUSTED, in-cluster`
- Observations: none

### `traitsOf/function` — CauldronArtAdapter.sol:100

- Signature: `function traitsOf(address collection, uint256 tokenId) public view returns (uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `CLASSES (line 109, constant)`; `FACES_PER_SET (line 111, constant)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `traitsOf` (CauldronArtAdapter.sol:100); authority is anyone. Gate evidence is recorded separately.
- Edges: `IRevealedArtSource.revealed (CauldronArtAdapter.sol:105), UNTRUSTED, in-cluster`; `IRevealedArtSource.rarityOf (CauldronArtAdapter.sol:106), UNTRUSTED, in-cluster`; `CauldronArtAdapter._bodyCount (CauldronArtAdapter.sol:110), TRUSTED, in-cluster`; `CauldronArtAdapter._itemCount (CauldronArtAdapter.sol:112), TRUSTED, in-cluster`
- Observations: none

### `_bodyCount/function` — CauldronArtAdapter.sol:117

- Signature: `function _bodyCount(uint8 classIdx) private pure returns (uint8)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_bodyCount` (CauldronArtAdapter.sol:117); callers: traitsOf.
- Edges: none
- Observations: none

### `_itemCount/function` — CauldronArtAdapter.sol:128

- Signature: `function _itemCount(uint8 classIdx) private pure returns (uint8)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_itemCount` (CauldronArtAdapter.sol:128); callers: traitsOf.
- Edges: none
- Observations: none


## `BadgeArtLib`

### `chunk/function` — BadgeArtLib.sol:27

- Signature: `function chunk(bytes memory body) internal pure returns (bytes[] memory out)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `chunk` (BadgeArtLib.sol:27); callers: upload.
- Edges: none
- Observations: none

### `upload/function` — BadgeArtLib.sol:45

- Signature: `function upload(LiquidatoorRenderer r, string memory longPath, string memory shortPath) internal`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `upload` (BadgeArtLib.sol:45); callers: no executable caller in this cluster.
- Edges: `Vm.readFileBinary (BadgeArtLib.sol:48), TRUSTED, out-of-cluster`; `Vm.readFileBinary (BadgeArtLib.sol:49), TRUSTED, out-of-cluster`; `BadgeArtLib._assertEscaped (BadgeArtLib.sol:52), TRUSTED, in-cluster`; `BadgeArtLib._assertEscaped (BadgeArtLib.sol:53), TRUSTED, in-cluster`; `BadgeArtLib.chunk (BadgeArtLib.sol:64), TRUSTED, in-cluster`; `BadgeArtLib._uploadSide (BadgeArtLib.sol:64), TRUSTED, in-cluster`; `BadgeArtLib.chunk (BadgeArtLib.sol:65), TRUSTED, in-cluster`; `BadgeArtLib._uploadSide (BadgeArtLib.sol:65), TRUSTED, in-cluster`
- Observations: none

### `_uploadSide/function` — BadgeArtLib.sol:68

- Signature: `function _uploadSide(LiquidatoorRenderer r, bool isLong, bytes[] memory chunks) private`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_uploadSide` (BadgeArtLib.sol:68); callers: upload.
- Edges: `LiquidatoorRenderer.setArt (BadgeArtLib.sol:72), UNTRUSTED, in-cluster`; `LiquidatoorRenderer.appendArt (BadgeArtLib.sol:73), UNTRUSTED, in-cluster`
- Observations: none

### `_assertEscaped/function` — BadgeArtLib.sol:79

- Signature: `function _assertEscaped(bytes memory art) private pure`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_assertEscaped` (BadgeArtLib.sol:79); callers: upload.
- Edges: none
- Observations: none


## `FrenRenderer`

### `constructor/constructor` — FrenRenderer.sol:31

- Signature: `constructor(TraitStorage _store)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `store (line 32, immutable)`
- Value: NONE
- Reachability: Externally reachable at `constructor` (FrenRenderer.sol:31); authority is deployer. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `tokenURI/function` — FrenRenderer.sol:40

- Signature: `function tokenURI( uint256 tokenId, uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx ) external view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `tokenURI` (FrenRenderer.sol:40); authority is anyone. Gate evidence is recorded separately.
- Edges: `FrenRenderer.renderSVG (FrenRenderer.sol:47), TRUSTED, in-cluster`; `Base64.encode (FrenRenderer.sol:49), TRUSTED, library`; `Strings.toString (FrenRenderer.sol:53), TRUSTED, library`; `FrenRenderer._attributes (FrenRenderer.sol:56), TRUSTED, in-cluster`; `Base64.encode (FrenRenderer.sol:63), TRUSTED, library`
- Observations: none

### `renderSVG/function` — FrenRenderer.sol:68

- Signature: `function renderSVG( uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx ) public view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `store (line 74, immutable)`; `LAYER_FACE (line 82, constant)`; `LAYER_BODY (line 83, constant)`; `LAYER_ITEM (line 84, constant)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `renderSVG` (FrenRenderer.sol:68); authority is anyone. Gate evidence is recorded separately.
- Edges: `TraitStorage.getPalette (FrenRenderer.sol:74), UNTRUSTED, in-cluster`; `FrenRenderer._newBuf (FrenRenderer.sol:77), TRUSTED, in-cluster`; `FrenRenderer._appendHeader (FrenRenderer.sol:79), TRUSTED, in-cluster`; `FrenRenderer._faceClass (FrenRenderer.sol:82), TRUSTED, in-cluster`; `FrenRenderer._appendLayer (FrenRenderer.sol:82), TRUSTED, in-cluster`; `FrenRenderer._appendLayer (FrenRenderer.sol:83), TRUSTED, in-cluster`; `FrenRenderer._appendLayer (FrenRenderer.sol:84), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:86), TRUSTED, in-cluster`; `FrenRenderer._finalize (FrenRenderer.sol:87), TRUSTED, in-cluster`
- Observations: none

### `_appendHeader/function` — FrenRenderer.sol:94

- Signature: `function _appendHeader(Buf memory b, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx) private pure`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_appendHeader` (FrenRenderer.sol:94); callers: renderSVG.
- Edges: `FrenRenderer._gradient (FrenRenderer.sol:98), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:99), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:106), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:107), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:108), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:109), TRUSTED, in-cluster`
- Observations: none

### `_appendLayer/function` — FrenRenderer.sol:128

- Signature: `function _appendLayer( Buf memory b, uint8 layerType, uint8 classIdx, uint8 layerIdx, bytes memory pal ) private view`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `store (line 135, immutable)`
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_appendLayer` (FrenRenderer.sol:128); callers: renderSVG.
- Edges: `TraitStorage.getTraitOrEmpty (FrenRenderer.sol:135), UNTRUSTED, in-cluster`; `FrenRenderer._colorAt (FrenRenderer.sol:144), TRUSTED, in-cluster`; `FrenRenderer._appendRow (FrenRenderer.sol:158), TRUSTED, in-cluster`
- Observations: none

### `_appendRow/function` — FrenRenderer.sol:163

- Signature: `function _appendRow(Buf memory b, Layer memory L, uint256 row) private pure`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_appendRow` (FrenRenderer.sol:163); callers: _appendLayer.
- Edges: `FrenRenderer._nibble (FrenRenderer.sol:168), TRUSTED, in-cluster`; `FrenRenderer._nibble (FrenRenderer.sol:175), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:179), TRUSTED, in-cluster`; `FrenRenderer._appendUint (FrenRenderer.sol:180), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:181), TRUSTED, in-cluster`; `FrenRenderer._appendUint (FrenRenderer.sol:182), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:183), TRUSTED, in-cluster`; `FrenRenderer._appendUint (FrenRenderer.sol:184), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:185), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:186), TRUSTED, in-cluster`; `FrenRenderer._append (FrenRenderer.sol:187), TRUSTED, in-cluster`
- Observations: none

### `_nibble/function` — FrenRenderer.sol:194

- Signature: `function _nibble(bytes memory blob, uint256 pixOff, uint256 idx) private pure returns (uint256)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_nibble` (FrenRenderer.sol:194); callers: _appendRow.
- Edges: none
- Observations: none

### `_colorAt/function` — FrenRenderer.sol:208

- Signature: `function _colorAt(bytes memory pal, uint256 gi) private pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_colorAt` (FrenRenderer.sol:208); callers: _appendLayer.
- Edges: `FrenRenderer._hexByte (FrenRenderer.sol:213), TRUSTED, in-cluster`; `FrenRenderer._hexByte (FrenRenderer.sol:214), TRUSTED, in-cluster`; `FrenRenderer._hexByte (FrenRenderer.sol:215), TRUSTED, in-cluster`
- Observations: none

### `_hexByte/function` — FrenRenderer.sol:221

- Signature: `function _hexByte(bytes memory out, uint256 at, uint8 v) private pure`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `HEX (line 222, constant)`; `HEX (line 223, constant)`
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_hexByte` (FrenRenderer.sol:221); callers: _colorAt, _rgbHex.
- Edges: none
- Observations: none

### `_gradient/function` — FrenRenderer.sol:227

- Signature: `function _gradient(uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx) private pure returns (string memory top, string memory bot)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_gradient` (FrenRenderer.sol:227); callers: _appendHeader.
- Edges: `FrenRenderer._rgbHex (FrenRenderer.sol:238), TRUSTED, in-cluster`; `FrenRenderer._clamp (FrenRenderer.sol:238), TRUSTED, in-cluster`; `FrenRenderer._clamp (FrenRenderer.sol:238), TRUSTED, in-cluster`; `FrenRenderer._clamp (FrenRenderer.sol:238), TRUSTED, in-cluster`; `FrenRenderer._rgbHex (FrenRenderer.sol:239), TRUSTED, in-cluster`; `FrenRenderer._clamp (FrenRenderer.sol:239), TRUSTED, in-cluster`; `FrenRenderer._clamp (FrenRenderer.sol:239), TRUSTED, in-cluster`; `FrenRenderer._clamp (FrenRenderer.sol:239), TRUSTED, in-cluster`
- Observations: none

### `_clamp/function` — FrenRenderer.sol:242

- Signature: `function _clamp(int256 v) private pure returns (uint8)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_clamp` (FrenRenderer.sol:242); callers: _gradient.
- Edges: none
- Observations: none

### `_rgbHex/function` — FrenRenderer.sol:248

- Signature: `function _rgbHex(uint8 r, uint8 g, uint8 bl) private pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_rgbHex` (FrenRenderer.sol:248); callers: _gradient.
- Edges: `FrenRenderer._hexByte (FrenRenderer.sol:250), TRUSTED, in-cluster`; `FrenRenderer._hexByte (FrenRenderer.sol:251), TRUSTED, in-cluster`; `FrenRenderer._hexByte (FrenRenderer.sol:252), TRUSTED, in-cluster`
- Observations: none

### `_faceClass/function` — FrenRenderer.sol:257

- Signature: `function _faceClass(uint8 classIdx) private pure returns (uint8)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_faceClass` (FrenRenderer.sol:257); callers: renderSVG.
- Edges: none
- Observations: none

### `_attributes/function` — FrenRenderer.sol:267

- Signature: `function _attributes(uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx) private pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_attributes` (FrenRenderer.sol:267); callers: tokenURI.
- Edges: `FrenRenderer._className (FrenRenderer.sol:273), TRUSTED, in-cluster`; `Strings.toString (FrenRenderer.sol:274), TRUSTED, library`; `Strings.toString (FrenRenderer.sol:275), TRUSTED, library`; `Strings.toString (FrenRenderer.sol:276), TRUSTED, library`
- Observations: none

### `_className/function` — FrenRenderer.sol:280

- Signature: `function _className(uint8 classIdx) private pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_className` (FrenRenderer.sol:280); callers: _attributes.
- Edges: none
- Observations: none

### `_newBuf/function` — FrenRenderer.sol:300

- Signature: `function _newBuf(uint256 cap) private pure returns (Buf memory b)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_newBuf` (FrenRenderer.sol:300); callers: renderSVG.
- Edges: none
- Observations: none

### `_append/function` — FrenRenderer.sol:305

- Signature: `function _append(Buf memory b, string memory s) private pure`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_append` (FrenRenderer.sol:305); callers: _appendHeader, _appendRow, _appendUint, renderSVG.
- Edges: none
- Observations: none

### `_appendUint/function` — FrenRenderer.sol:319

- Signature: `function _appendUint(Buf memory b, uint256 v) private pure`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_appendUint` (FrenRenderer.sol:319); callers: _appendRow.
- Edges: `FrenRenderer._append (FrenRenderer.sol:321), TRUSTED, in-cluster`
- Observations: none

### `_finalize/function` — FrenRenderer.sol:342

- Signature: `function _finalize(Buf memory b) private pure returns (bytes memory out)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_finalize` (FrenRenderer.sol:342); callers: renderSVG.
- Edges: none
- Observations: none


## `LiquidatoorRenderer`

### `constructor/constructor` — LiquidatoorRenderer.sol:44

- Signature: `constructor()`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `owner (line 45)`
- Value: NONE
- Reachability: Externally reachable at `constructor` (LiquidatoorRenderer.sol:44); authority is deployer. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `transferOwnership/function` — LiquidatoorRenderer.sol:48

- Signature: `function transferOwnership(address to) external`
- Authority: owner
- Gate evidence: `if (msg.sender != owner) revert NotOwner(); (LiquidatoorRenderer.sol:49)`
- Reads: `owner (line 49)`
- Writes: `owner (line 50)`
- Value: NONE
- Reachability: Externally reachable at `transferOwnership` (LiquidatoorRenderer.sol:48); authority is owner. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `setArt/function` — LiquidatoorRenderer.sol:61

- Signature: `function setArt(bool isLong, bytes[] calldata chunks) external`
- Authority: owner
- Gate evidence: `if (msg.sender != owner) revert NotOwner(); (LiquidatoorRenderer.sol:62)`
- Reads: `owner (line 62)`; `longArt (line 63)`; `shortArt (line 63)`
- Writes: `longArt (line 63)`; `shortArt (line 63)`
- Value: NONE
- Reachability: Externally reachable at `setArt` (LiquidatoorRenderer.sol:61); authority is owner. Gate evidence is recorded separately.
- Edges: `LiquidatoorRenderer._append (LiquidatoorRenderer.sol:65), TRUSTED, in-cluster`
- Observations: none

### `appendArt/function` — LiquidatoorRenderer.sol:80

- Signature: `function appendArt(bool isLong, bytes[] calldata chunks) external`
- Authority: owner
- Gate evidence: `if (msg.sender != owner) revert NotOwner(); (LiquidatoorRenderer.sol:81)`
- Reads: `owner (line 81)`; `longArt (line 82)`; `shortArt (line 82)`
- Writes: `longArt (line 82)`; `shortArt (line 82)`
- Value: NONE
- Reachability: Externally reachable at `appendArt` (LiquidatoorRenderer.sol:80); authority is owner. Gate evidence is recorded separately.
- Edges: `LiquidatoorRenderer._append (LiquidatoorRenderer.sol:82), TRUSTED, in-cluster`
- Observations: none

### `_append/function` — LiquidatoorRenderer.sol:85

- Signature: `function _append(address[] storage dst, bool isLong, bytes[] calldata chunks) private`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_append` (LiquidatoorRenderer.sol:85); callers: appendArt, setArt.
- Edges: `SSTORE2.write (LiquidatoorRenderer.sol:88), TRUSTED, in-cluster`
- Observations: none

### `art/function` — LiquidatoorRenderer.sol:95

- Signature: `function art(bool isLong) public view returns (bytes memory out)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `longArt (line 96)`; `shortArt (line 96)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `art` (LiquidatoorRenderer.sol:95); authority is anyone. Gate evidence is recorded separately.
- Edges: `SSTORE2.read (LiquidatoorRenderer.sol:98), TRUSTED, in-cluster`
- Observations: none

### `tokenURI/function` — LiquidatoorRenderer.sol:108

- Signature: `function tokenURI(uint256 tokenId) external view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `tokenURI` (LiquidatoorRenderer.sol:108); authority is anyone. Gate evidence is recorded separately.
- Edges: `ILiquidatorMintable.liqStats (LiquidatoorRenderer.sol:109), UNTRUSTED, out-of-cluster`; `LiquidatoorRenderer._u (LiquidatoorRenderer.sol:112), TRUSTED, in-cluster`; `LiquidatoorRenderer._attributes (LiquidatoorRenderer.sol:114), TRUSTED, in-cluster`; `LiquidatoorRenderer.renderSVG (LiquidatoorRenderer.sol:115), TRUSTED, in-cluster`
- Observations: none

### `renderSVG/function` — LiquidatoorRenderer.sol:121

- Signature: `function renderSVG(uint256 tokenId, LiqStats memory s) public view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `renderSVG` (LiquidatoorRenderer.sol:121); authority is anyone. Gate evidence is recorded separately.
- Edges: `LiquidatoorRenderer.art (LiquidatoorRenderer.sol:126), TRUSTED, in-cluster`; `LiquidatoorRenderer._hud (LiquidatoorRenderer.sol:158), TRUSTED, in-cluster`; `LiquidatoorRenderer._readout (LiquidatoorRenderer.sol:159), TRUSTED, in-cluster`
- Observations: none

### `_hud/function` — LiquidatoorRenderer.sol:170

- Signature: `function _hud(uint256 tokenId, string memory accent, string memory glow) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_hud` (LiquidatoorRenderer.sol:170); callers: renderSVG.
- Edges: `LiquidatoorRenderer._pad4 (LiquidatoorRenderer.sol:177), TRUSTED, in-cluster`
- Observations: none

### `_readout/function` — LiquidatoorRenderer.sol:186

- Signature: `function _readout(LiqStats memory s, string memory accent, string memory ink) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_readout` (LiquidatoorRenderer.sol:186); callers: renderSVG.
- Edges: `LiquidatoorRenderer._line (LiquidatoorRenderer.sol:202), TRUSTED, in-cluster`; `LiquidatoorRenderer._addr (LiquidatoorRenderer.sol:202), TRUSTED, in-cluster`; `LiquidatoorRenderer._line (LiquidatoorRenderer.sol:203), TRUSTED, in-cluster`; `LiquidatoorRenderer._line (LiquidatoorRenderer.sol:204), TRUSTED, in-cluster`; `LiquidatoorRenderer._eth (LiquidatoorRenderer.sol:204), TRUSTED, in-cluster`; `LiquidatoorRenderer._line (LiquidatoorRenderer.sol:205), TRUSTED, in-cluster`; `LiquidatoorRenderer._u (LiquidatoorRenderer.sol:205), TRUSTED, in-cluster`; `LiquidatoorRenderer._line (LiquidatoorRenderer.sol:206), TRUSTED, in-cluster`; `LiquidatoorRenderer._gwei (LiquidatoorRenderer.sol:206), TRUSTED, in-cluster`; `LiquidatoorRenderer._line (LiquidatoorRenderer.sol:207), TRUSTED, in-cluster`; `LiquidatoorRenderer._gwei (LiquidatoorRenderer.sol:207), TRUSTED, in-cluster`; `LiquidatoorRenderer._line (LiquidatoorRenderer.sol:208), TRUSTED, in-cluster`; `LiquidatoorRenderer._eth (LiquidatoorRenderer.sol:208), TRUSTED, in-cluster`
- Observations: none

### `_line/function` — LiquidatoorRenderer.sol:212

- Signature: `function _line( uint256 y, string memory label, string memory value, string memory accent, string memory ink ) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_line` (LiquidatoorRenderer.sol:212); callers: _readout.
- Edges: `LiquidatoorRenderer._u (LiquidatoorRenderer.sol:219), TRUSTED, in-cluster`
- Observations: none

### `_attributes/function` — LiquidatoorRenderer.sol:227

- Signature: `function _attributes(LiqStats memory s) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_attributes` (LiquidatoorRenderer.sol:227); callers: tokenURI.
- Edges: `LiquidatoorRenderer._u (LiquidatoorRenderer.sol:234), TRUSTED, in-cluster`; `LiquidatoorRenderer._addr (LiquidatoorRenderer.sol:235), TRUSTED, in-cluster`; `LiquidatoorRenderer._eth (LiquidatoorRenderer.sol:236), TRUSTED, in-cluster`; `LiquidatoorRenderer._u (LiquidatoorRenderer.sol:237), TRUSTED, in-cluster`
- Observations: none

### `_u/function` — LiquidatoorRenderer.sol:245

- Signature: `function _u(uint256 v) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_u` (LiquidatoorRenderer.sol:245); callers: _attributes, _eth, _gwei, _line, _pad4, _readout, tokenURI.
- Edges: none
- Observations: none

### `_pad4/function` — LiquidatoorRenderer.sol:255

- Signature: `function _pad4(uint256 v) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_pad4` (LiquidatoorRenderer.sol:255); callers: _hud.
- Edges: `LiquidatoorRenderer._u (LiquidatoorRenderer.sol:256), TRUSTED, in-cluster`
- Observations: none

### `_addr/function` — LiquidatoorRenderer.sol:268

- Signature: `function _addr(address a) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_addr` (LiquidatoorRenderer.sol:268); callers: _attributes, _readout.
- Edges: none
- Observations: none

### `_gwei/function` — LiquidatoorRenderer.sol:283

- Signature: `function _gwei(uint256 wei_) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_gwei` (LiquidatoorRenderer.sol:283); callers: _readout.
- Edges: `LiquidatoorRenderer._u (LiquidatoorRenderer.sol:291), TRUSTED, in-cluster`
- Observations: none

### `_eth/function` — LiquidatoorRenderer.sol:296

- Signature: `function _eth(uint256 wei_) internal pure returns (string memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `_eth` (LiquidatoorRenderer.sol:296); callers: _attributes, _readout.
- Edges: `LiquidatoorRenderer._u (LiquidatoorRenderer.sol:304), TRUSTED, in-cluster`
- Observations: none


## `SSTORE2`

### `write/function` — SSTORE2.sol:22

- Signature: `function write(bytes memory data) internal returns (address pointer)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `write` (SSTORE2.sol:22); callers: no executable caller in this cluster.
- Edges: none
- Observations: none

### `read/function` — SSTORE2.sol:49

- Signature: `function read(address pointer) internal view returns (bytes memory)`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `read` (SSTORE2.sol:49); callers: no executable caller in this cluster.
- Edges: none
- Observations: none


## `TraitStorage`

### `constructor/constructor` — TraitStorage.sol:45

- Signature: `constructor() Ownable(msg.sender)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `constructor` (TraitStorage.sol:45); authority is deployer. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `notFrozen/modifier` — TraitStorage.sol:51

- Signature: `modifier notFrozen()`
- Authority: internal
- Gate evidence: `UNGATED`
- Reads: `frozen (line 52)`
- Writes: none
- Value: NONE
- Reachability: Internal body declared at `notFrozen` (TraitStorage.sol:51); callers: no executable caller in this cluster.
- Edges: none
- Observations: none

### `storePalette/function` — TraitStorage.sol:57

- Signature: `function storePalette(bytes calldata rgb) external onlyOwner notFrozen`
- Authority: owner
- Gate evidence: `onlyOwner (TraitStorage.sol:57)`
- Reads: `palettePointer (line 60)`
- Writes: `palettePointer (line 59)`
- Value: NONE
- Reachability: Externally reachable at `storePalette` (TraitStorage.sol:57); authority is owner. Gate evidence is recorded separately.
- Edges: `SSTORE2.write (TraitStorage.sol:59), TRUSTED, in-cluster`
- Observations: none

### `storeTrait/function` — TraitStorage.sol:64

- Signature: `function storeTrait(uint256 key, bytes calldata blob) public onlyOwner notFrozen`
- Authority: owner
- Gate evidence: `onlyOwner (TraitStorage.sol:64)`
- Reads: none
- Writes: `traitPointer (line 66)`
- Value: NONE
- Reachability: Externally reachable at `storeTrait` (TraitStorage.sol:64); authority is owner. Gate evidence is recorded separately.
- Edges: `SSTORE2.write (TraitStorage.sol:65), TRUSTED, in-cluster`
- Observations: none

### `storeTraits/function` — TraitStorage.sol:71

- Signature: `function storeTraits(uint256[] calldata traitKeys, bytes[] calldata blobs) external onlyOwner notFrozen`
- Authority: owner
- Gate evidence: `onlyOwner (TraitStorage.sol:73)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `storeTraits` (TraitStorage.sol:71); authority is owner. Gate evidence is recorded separately.
- Edges: `TraitStorage.storeTrait (TraitStorage.sol:78), TRUSTED, in-cluster`
- Observations: none

### `freeze/function` — TraitStorage.sol:83

- Signature: `function freeze() external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (TraitStorage.sol:83)`
- Reads: none
- Writes: `frozen (line 84)`
- Value: NONE
- Reachability: Externally reachable at `freeze` (TraitStorage.sol:83); authority is owner. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `traitKey/function` — TraitStorage.sol:92

- Signature: `function traitKey(uint8 layerType, uint8 classIdx, uint8 layerIdx) public pure returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `traitKey` (TraitStorage.sol:92); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none

### `getTrait/function` — TraitStorage.sol:101

- Signature: `function getTrait(uint256 key) external view returns (bytes memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `traitPointer (line 102)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `getTrait` (TraitStorage.sol:101); authority is anyone. Gate evidence is recorded separately.
- Edges: `SSTORE2.read (TraitStorage.sol:104), TRUSTED, in-cluster`
- Observations: none

### `getTraitOrEmpty/function` — TraitStorage.sol:108

- Signature: `function getTraitOrEmpty(uint8 layerType, uint8 classIdx, uint8 layerIdx) external view returns (bytes memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `traitPointer (line 113)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `getTraitOrEmpty` (TraitStorage.sol:108); authority is anyone. Gate evidence is recorded separately.
- Edges: `TraitStorage.traitKey (TraitStorage.sol:113), TRUSTED, in-cluster`; `SSTORE2.read (TraitStorage.sol:115), TRUSTED, in-cluster`
- Observations: none

### `getPalette/function` — TraitStorage.sol:119

- Signature: `function getPalette() external view returns (bytes memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `palettePointer (line 120)`; `palettePointer (line 121)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `getPalette` (TraitStorage.sol:119); authority is anyone. Gate evidence is recorded separately.
- Edges: `SSTORE2.read (TraitStorage.sol:121), TRUSTED, in-cluster`
- Observations: none

### `hasTrait/function` — TraitStorage.sol:124

- Signature: `function hasTrait(uint256 key) external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `traitPointer (line 125)`
- Writes: none
- Value: NONE
- Reachability: Externally reachable at `hasTrait` (TraitStorage.sol:124); authority is anyone. Gate evidence is recorded separately.
- Edges: none
- Observations: none
