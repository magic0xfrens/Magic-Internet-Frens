/**
 * SvgDecoder — Reconstructs SVG images from compact 4-bit indexed bitmaps.
 *
 * Binary format per trait blob:
 *   [layerType:u8][classIdx:u8][layerIdx:u8]
 *   [minX:u8][minY:u8][width:u8][height:u8]
 *   [paletteSize:u8][globalIndices × paletteSize]
 *   [4-bit nibble pixel data, high nibble first]
 *
 * Nibble values: 0 = transparent, 1..paletteSize = local palette index (1-based)
 * Actual color: globalPalette[globalIndices[nibble - 1]]
 */

const CANVAS_SIZE = 120;

export interface TraitHeader {
  layerType: number;
  classIdx: number;
  layerIdx: number;
  minX: number;
  minY: number;
  width: number;
  height: number;
  paletteSize: number;
  localPaletteIndices: number[];
}

/**
 * Convert a hex string to a Uint8Array.
 */
export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

/**
 * Parse the binary header from a trait blob.
 */
export function parseTraitHeader(data: Uint8Array): TraitHeader {
  const layerType = data[0];
  const classIdx = data[1];
  const layerIdx = data[2];
  const minX = data[3];
  const minY = data[4];
  const width = data[5];
  const height = data[6];
  const paletteSize = data[7];

  const localPaletteIndices: number[] = [];
  for (let i = 0; i < paletteSize; i++) {
    localPaletteIndices.push(data[8 + i]);
  }

  return {
    layerType,
    classIdx,
    layerIdx,
    minX,
    minY,
    width,
    height,
    paletteSize,
    localPaletteIndices,
  };
}

/**
 * Decode a single trait blob into an array of { x, y, color } pixels.
 */
export function decodeTraitPixels(
  blobHex: string,
  globalPalette: string[],
): { x: number; y: number; color: string }[] {
  const data = hexToBytes(blobHex);
  const header = parseTraitHeader(data);
  const pixelDataOffset = 8 + header.paletteSize;
  const pixels: { x: number; y: number; color: string }[] = [];

  const totalPixels = header.width * header.height;

  for (let i = 0; i < totalPixels; i++) {
    const byteIdx = pixelDataOffset + Math.floor(i / 2);
    const nibble =
      i % 2 === 0
        ? (data[byteIdx] >> 4) & 0x0f
        : data[byteIdx] & 0x0f;

    if (nibble === 0) continue; // transparent

    const globalIdx = header.localPaletteIndices[nibble - 1];
    const color = globalPalette[globalIdx];
    if (!color) continue;

    const x = header.minX + (i % header.width);
    const y = header.minY + Math.floor(i / header.width);

    pixels.push({ x, y, color });
  }

  return pixels;
}

/**
 * Render a single trait blob to an SVG string.
 */
export function traitBlobToSvg(
  blobHex: string,
  globalPalette: string[],
): string {
  const pixels = decodeTraitPixels(blobHex, globalPalette);
  return pixelsToSvg(pixels);
}

/**
 * Render multiple trait blobs as a stacked/composited SVG.
 * Layers are drawn in order (first = bottom, last = top).
 */
export function compositeTraitsToSvg(
  blobHexes: string[],
  globalPalette: string[],
): string {
  const allPixels: { x: number; y: number; color: string }[] = [];

  for (const blob of blobHexes) {
    const pixels = decodeTraitPixels(blob, globalPalette);
    allPixels.push(...pixels);
  }

  return pixelsToSvg(allPixels);
}

/**
 * Build an SVG string from pixel data, using run-length encoding
 * for consecutive same-color pixels in a row to reduce SVG size.
 */
function pixelsToSvg(
  pixels: { x: number; y: number; color: string }[],
): string {
  // Group by color to minimize fill attribute changes
  const byColor = new Map<string, { x: number; y: number }[]>();
  for (const p of pixels) {
    let arr = byColor.get(p.color);
    if (!arr) {
      arr = [];
      byColor.set(p.color, arr);
    }
    arr.push({ x: p.x, y: p.y });
  }

  const rects: string[] = [];
  for (const [color, positions] of byColor) {
    // Run-length encode horizontally within same row
    positions.sort((a, b) => a.y - b.y || a.x - b.x);

    let i = 0;
    while (i < positions.length) {
      const startX = positions[i].x;
      const y = positions[i].y;
      let width = 1;

      while (
        i + width < positions.length &&
        positions[i + width].y === y &&
        positions[i + width].x === startX + width
      ) {
        width++;
      }

      if (width === 1) {
        rects.push(`<rect x="${startX}" y="${y}" width="1" height="1" fill="${color}"/>`);
      } else {
        rects.push(
          `<rect x="${startX}" y="${y}" width="${width}" height="1" fill="${color}"/>`,
        );
      }

      i += width;
    }
  }

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CANVAS_SIZE} ${CANVAS_SIZE}" shape-rendering="crispEdges">`,
    ...rects,
    "</svg>",
  ].join("");
}

/**
 * Create a data URI from an SVG string, suitable for <img src>.
 */
export function svgToDataUri(svg: string): string {
  return `data:image/svg+xml;base64,${btoa(svg)}`;
}

/**
 * Render a token's full SVG by reading on-chain trait blobs.
 *
 * Usage:
 *   const contract = getContract(nftAddress, MiFrensAbi);
 *   const svg = await renderTokenFromChain(contract, tokenId, PALETTE_COLORS);
 *   document.querySelector('img').src = svgToDataUri(svg);
 *
 * This is the "simple browser can show it" path:
 *   1. Call getTokenTraitKeys(tokenId)  →  [bodyKey, faceKey, itemKey]
 *   2. For each key, call getTraitImage(layerType, classIdx, layerIdx) → blob
 *   3. Decode & composite all blobs into one SVG
 */
export async function renderTokenFromChain(
  contract: Record<string, (...args: unknown[]) => Promise<{ decoded?: unknown[] }>>,
  tokenId: bigint,
  globalPalette: string[],
): Promise<string> {
  // Step 1: Get the 3 traitKeys for this token
  const keysResult = await contract["getTokenTraitKeys"](tokenId);
  const bodyKey = keysResult.decoded?.[0] as bigint;
  const faceKey = keysResult.decoded?.[1] as bigint;
  const itemKey = keysResult.decoded?.[2] as bigint;

  // Step 2: Read each trait blob from on-chain storage
  const blobs: string[] = [];

  for (const traitKey of [bodyKey, faceKey, itemKey]) {
    const keyNum = Number(traitKey);
    const layerType = Math.floor(keyNum / 65536);
    const remainder = keyNum % 65536;
    const classIdx = Math.floor(remainder / 256);
    const layerIdx = remainder % 256;

    try {
      const result = await contract["getTraitImage"](
        BigInt(layerType),
        BigInt(classIdx),
        BigInt(layerIdx),
      );

      if (result.decoded?.[0]) {
        const data = result.decoded[0] as Uint8Array;
        // Convert Uint8Array to hex string for the decoder
        const hex = Array.from(data)
          .map((b) => b.toString(16).padStart(2, "0"))
          .join("");
        blobs.push(hex);
      }
    } catch {
      // Trait not yet inscribed — skip this layer
    }
  }

  // Step 3: Composite all layers into a single SVG
  if (blobs.length === 0) {
    // No traits inscribed yet — return a placeholder
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CANVAS_SIZE} ${CANVAS_SIZE}"><text x="60" y="65" text-anchor="middle" font-size="10" fill="#888">Awaiting inscription</text></svg>`;
  }

  return compositeTraitsToSvg(blobs, globalPalette);
}
