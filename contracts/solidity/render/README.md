# Fully On-Chain Art (EVM)

Renders MagicFrens NFTs entirely on-chain — no IPFS, no API. Trait pixel data
lives in contract bytecode; `tokenURI` composes the SVG live.

## Contracts

| Contract | Role |
|----------|------|
| `SSTORE2.sol` | Store/read immutable blobs as contract bytecode (~200× cheaper reads than SLOAD). |
| `TraitStorage.sol` | Owner-uploaded repository of the 89 compressed trait blobs + 247-color RGB palette. `freeze()` locks it forever. |
| `FrenRenderer.sol` | Decodes blobs and composes the layered SVG (gradient bg → face → body → item) + base64 JSON metadata. |

`MagicFrensPeg.setRenderer(addr)` wires the renderer in; `tokenURI` falls back to
the hosted API when unset.

## Data format

Blobs are the exact output of `scripts/compress-traits.mjs`:

```
[layerType:u8][classIdx:u8][layerIdx:u8]   3-byte identity
[minX:u8][minY:u8][width:u8][height:u8]    bounding box on the 120×120 canvas
[localPaletteSize:u8]                        N
[globalIdx × N]                              indices into the global palette
[pixelData]                                  ceil(w*h/2) bytes, 4-bit nibbles
                                             0 = transparent, 1..15 = localPalette[n-1]
```

Palette is raw RGB (3 bytes/color, no header). `traitKey = layerType*65536 + classIdx*256 + layerIdx`.

The gradient background reproduces `FrenSprite.frenGradient` (the legacy
`FrenForge._getTraitHash`) so on-chain output matches the frontend byte-for-byte.

## Test

```bash
cd contracts/solidity
FOUNDRY_PROFILE=render forge test --match-contract FrenRendererTest -vv
```

Loads the real `compressed-traits/*.bin`, stores them, and renders — 5 passing
tests. Total on-chain art payload ≈ 151 KB across 89 blobs.

## Deploy + upload

```bash
cd contracts/solidity
export PRIVATE_KEY=0x...
export PEG=0x...        # optional: wire renderer into MagicFrensPeg
export FREEZE=true      # optional: lock the trait set after upload
FOUNDRY_PROFILE=render forge script deploy/DeployRenderer.s.sol \
  --rpc-url $ETH_RPC --broadcast \
  --verify --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvv
```

Uploads in batches of `BATCH` (default 12) blobs per tx. Verified end-to-end on a
local anvil: deploy → 89 blobs in 8 batches (~55M gas) → `tokenURI` returns valid
base64 JSON with an embedded SVG.

> Note: the `render` Foundry profile excludes the ERC404-style `MagicFrensPeg`
> (pre-existing OZ multiple-inheritance clash on `name`/`symbol`/`balanceOf`) and
> the V4 `Cauldron*` contracts (need `v4-core`/`v4-periphery` installed). The
> renderer is independent and wired to the Peg only through the `IFrenRenderer`
> interface.
