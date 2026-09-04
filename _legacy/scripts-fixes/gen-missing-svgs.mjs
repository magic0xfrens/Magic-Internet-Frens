#!/usr/bin/env node
/**
 * gen-missing-svgs.mjs — Generate ONLY the missing SVGs for body indices
 * that the on-chain contract can produce but the original upload skipped.
 *
 * Missing combos:
 *   Wizard (0): bodies 3, 4   (on-chain numBodies=8, original upload had [0,1,2,5,6,7])
 *   King   (1): body 0        (on-chain numBodies=5, original upload had [1,2,3,4])
 *
 * Uses the same rendering pipeline as upload-collection-ipfs.ts.
 */

import * as fs from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const baseDir = join(__dirname, '..');

const svgDir = join(baseDir, 'svg-out');
const metaDir = join(baseDir, 'metadata-out');
const traitsDir = join(baseDir, 'compressed-traits');

// ── Missing combos to generate ──
const MISSING = [
  { classIdx: 0, bodyIdx: 3, name: 'Wizard', bodyName: 'Storm', faceClassIdx: 0, subitemClassIdx: 0, numFaces: 12, numItems: 5 },
  { classIdx: 0, bodyIdx: 4, name: 'Wizard', bodyName: 'Void',  faceClassIdx: 0, subitemClassIdx: 0, numFaces: 12, numItems: 5 },
  { classIdx: 1, bodyIdx: 0, name: 'King',   bodyName: 'Onyx',  faceClassIdx: 0, subitemClassIdx: 0, numFaces: 12, numItems: 4 },
];

const NUM_SUBITEMS = 3; // 0=none, 1=potion/mumu, 2=skull/bobo
const CANVAS_SIDE = 120;

// ── BTC Logo grid ──
const GRID_COLS = 28;
const GRID_ROWS = 28;
// prettier-ignore
const BTC_LOGO = [
  '0000000000000000000000000000',
  '0000000000000000000000000000',
  '0000000000000000000000000000',
  '0000000000000000000000000000',
  '0000000000000000000000000000',
  '0000000000110011000000000000',
  '0000000000110011000000000000',
  '0000000011111111100000000000',
  '0000000011111111110000000000',
  '0000000000110000111000000000',
  '0000000000110000011000000000',
  '0000000000110000011000000000',
  '0000000000110000111000000000',
  '0000000000111111110000000000',
  '0000000000111111111000000000',
  '0000000000110000011100000000',
  '0000000000110000001100000000',
  '0000000000110000011100000000',
  '0000000011111111111000000000',
  '0000000011111111110000000000',
  '0000000000110011000000000000',
  '0000000000110011000000000000',
  '0000000000000000000000000000',
  '0000000000000000000000000000',
  '0000000000000000000000000000',
  '0000000000000000000000000000',
  '0000000000000000000000000000',
  '0000000000000000000000000000',
];

function isLogoCell(gridPos) {
  const row = Math.floor(gridPos / GRID_COLS);
  const col = gridPos % GRID_COLS;
  if (row >= GRID_ROWS || col >= GRID_COLS) return false;
  return BTC_LOGO[row][col] === '1';
}

// ── Rendering (exact copy from upload-collection-ipfs.ts) ──

function compositeLayer(canvas, layerData, canvasSide) {
  if (layerData.length < 10) return;
  const minX = layerData[3];
  const minY = layerData[4];
  const bboxW = layerData[5];
  const bboxH = layerData[6];
  const localPaletteSize = layerData[7];
  if (localPaletteSize === 0 || bboxW === 0 || bboxH === 0) return;
  const paletteStart = 8;
  const pixelDataStart = paletteStart + localPaletteSize;
  if (pixelDataStart >= layerData.length) return;
  const totalBBoxPixels = bboxW * bboxH;
  for (let p = 0; p < totalBBoxPixels; p++) {
    const nibbleByteOffset = pixelDataStart + (p >> 1);
    if (nibbleByteOffset >= layerData.length) break;
    const rawByte = layerData[nibbleByteOffset];
    const nibble = (p & 1) === 0 ? (rawByte >> 4) & 0x0f : rawByte & 0x0f;
    if (nibble === 0) continue;
    const localIdx = nibble - 1;
    if (localIdx >= localPaletteSize) continue;
    const globalIdx = layerData[paletteStart + localIdx];
    const canvasValue = globalIdx + 1;
    const dx = p % bboxW;
    const dy = Math.floor(p / bboxW);
    const absX = minX + dx;
    const absY = minY + dy;
    if (absX >= canvasSide || absY >= canvasSide) continue;
    canvas[absY * canvasSide + absX] = canvasValue;
  }
}

function getTraitHash(bodyIdx, faceIdx, itemIdx) {
  const seed = bodyIdx * 7919 + faceIdx * 6271 + itemIdx * 4813;
  return seed & 0xffff;
}

function clampColor(v) {
  if (v < 0) return 0;
  if (v > 255) return 255;
  return v;
}

function toHex2(n) {
  return n.toString(16).padStart(2, '0');
}

function buildGradient(hash, logoBit) {
  const shift1R = ((hash >> 0) & 0xf) - 8;
  const shift1G = ((hash >> 4) & 0xf) - 8;
  const shift1B = ((hash >> 8) & 0x7) - 4;
  const shift2R = ((hash >> 3) & 0xf) - 8;
  const shift2G = ((hash >> 7) & 0xf) - 8;
  const shift2B = ((hash >> 11) & 0x7) - 4;

  let c1R, c1G, c1B, c2R, c2G, c2B;
  if (logoBit) {
    c1R = clampColor(252 + (shift1R >> 2));
    c1G = clampColor(194 + shift1G);
    c1B = clampColor(101 + shift1B);
    c2R = clampColor(250 + (shift2R >> 2));
    c2G = clampColor(186 + shift2G);
    c2B = clampColor(80 + shift2B);
  } else {
    c1R = clampColor(247 + shift1R);
    c1G = clampColor(147 + shift1G);
    c1B = clampColor(26 + shift1B);
    c2R = clampColor(237 + shift2R);
    c2G = clampColor(137 + shift2G);
    c2B = clampColor(20 + shift2B);
  }

  const color1 = toHex2(c1R) + toHex2(c1G) + toHex2(c1B);
  const color2 = toHex2(c2R) + toHex2(c2G) + toHex2(c2B);

  const gradType = (hash >> 12) % 10;
  const linearDirs = [
    [0,0,0,1],[0,1,0,0],[0,0,1,0],[1,0,0,0],
    [0,0,1,1],[1,1,0,0],[0,1,1,0],[1,0,0,1],
  ];

  let gradientDef;
  if (gradType < 8) {
    const [x1, y1, x2, y2] = linearDirs[gradType];
    gradientDef = `<linearGradient id="bg" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"><stop offset="0" stop-color="#${color1}"/><stop offset="1" stop-color="#${color2}"/></linearGradient>`;
  } else {
    const cx = gradType === 8 ? '50%' : '30%';
    const cy = gradType === 8 ? '50%' : '30%';
    gradientDef = `<radialGradient id="bg" cx="${cx}" cy="${cy}" r="70%"><stop offset="0" stop-color="#${color1}"/><stop offset="1" stop-color="#${color2}"/></radialGradient>`;
  }
  return { gradientDef };
}

function renderSVG(palette, bodyData, faceData, itemData, subitemData, _classIdx, bodyIdx, faceIdx, itemIdx, logoBit) {
  const side = CANVAS_SIDE;
  const canvas = new Uint8Array(side * side);
  compositeLayer(canvas, faceData, side);
  compositeLayer(canvas, bodyData, side);
  compositeLayer(canvas, itemData, side);
  if (subitemData.length > 0) compositeLayer(canvas, subitemData, side);

  const hash = getTraitHash(bodyIdx, faceIdx, itemIdx);
  const { gradientDef } = buildGradient(hash, logoBit);

  let svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" shape-rendering="crispEdges">'
    + `<defs>${gradientDef}</defs>`
    + '<rect width="120" height="120" fill="url(#bg)"/>';

  const runs = [];
  const usedColors = new Set();
  for (let y = 0; y < side; y++) {
    const rowBase = y * side;
    let x = 0;
    while (x < side) {
      const c = canvas[rowBase + x];
      if (c === 0) { x++; continue; }
      let w = 1;
      for (let rx = x + 1; rx < side; rx++) {
        if (canvas[rowBase + rx] !== c) break;
        w++;
      }
      runs.push({ colorIdx: c, x, y, w });
      usedColors.add(c);
      x += w;
    }
  }

  for (let c = 1; c < 256; c++) {
    if (!usedColors.has(c)) continue;
    const colorOffset = (c - 1) * 3;
    if (colorOffset + 2 >= palette.length) continue;
    const r = palette[colorOffset];
    const g = palette[colorOffset + 1];
    const b = palette[colorOffset + 2];
    const hex = toHex2(r) + toHex2(g) + toHex2(b);
    let d = '';
    for (const run of runs) {
      if (run.colorIdx !== c) continue;
      d += `M${run.x} ${run.y}h${run.w}v1h-${run.w}z`;
    }
    svg += `<path d="${d}" fill="#${hex}"/>`;
  }
  svg += '</svg>';
  return svg;
}

function readTraitBinary(layerType, classIdx, layerIdx) {
  const filename = `trait-${layerType}-${classIdx}-${layerIdx}.bin`;
  const filePath = join(traitsDir, filename);
  if (!fs.existsSync(filePath)) return new Uint8Array(0);
  return new Uint8Array(fs.readFileSync(filePath));
}

function readPalette() {
  const palettePath = join(traitsDir, 'palette-rgb.bin');
  if (fs.existsSync(palettePath)) return new Uint8Array(fs.readFileSync(palettePath));
  const fullPalettePath = join(traitsDir, 'palette.bin');
  const buf = fs.readFileSync(fullPalettePath);
  return new Uint8Array(buf.subarray(2));
}

function faceVariantName(faceIdx) {
  const names = { 0:'Classic', 1:'Happy', 2:'Angry', 3:'Feels Bad', 4:'Grinding', 5:'Chill', 6:'Grumpy', 7:'Giga Happy', 8:'Cooked', 9:'Comfy', 10:'Retard', 11:'Laser Eyes' };
  return names[faceIdx] ?? `Face ${faceIdx}`;
}

function itemVariantName(classIdx, itemIdx) {
  const map = {
    0: { 0:'Frost Staff', 1:'Solar Staff', 2:'Verdant Staff', 3:'Crimson Staff', 4:'Hermes Staff' },
    1: { 0:'Scepter Black', 1:'Scepter Blue', 2:'Scepter Red', 3:'Scepter White' },
  };
  const val = map[classIdx];
  if (typeof val === 'object') return val[itemIdx] ?? `Item ${itemIdx}`;
  return `Item ${itemIdx}`;
}

function subitemVariantName(classIdx, subitemIdx) {
  if (subitemIdx === 0) return 'None';
  if (classIdx === 4) {
    if (subitemIdx === 1) return 'MuMu Hat';
    if (subitemIdx === 2) return 'BoBo Hat';
  }
  if (subitemIdx === 1) return 'Potion';
  if (subitemIdx === 2) return 'Skull';
  return `Subitem ${subitemIdx}`;
}

// ── Main ──

const palette = readPalette();
console.log(`Palette: ${palette.length} bytes (${palette.length / 3} colors)`);

let svgCount = 0;
let metaCount = 0;
let totalBytes = 0;

for (const m of MISSING) {
  for (let faceIdx = 0; faceIdx < m.numFaces; faceIdx++) {
    for (let itemIdx = 0; itemIdx < m.numItems; itemIdx++) {
      for (let subitemIdx = 0; subitemIdx < NUM_SUBITEMS; subitemIdx++) {
        const comboKey = `${m.classIdx}-${m.bodyIdx}-${faceIdx}-${itemIdx}-${subitemIdx}`;

        const bodyData = readTraitBinary(0, m.classIdx, m.bodyIdx);
        const faceData = readTraitBinary(1, m.faceClassIdx, faceIdx);
        const itemData = readTraitBinary(2, m.classIdx, itemIdx);
        let subitemData = new Uint8Array(0);
        if (subitemIdx > 0) {
          subitemData = readTraitBinary(3, m.subitemClassIdx, subitemIdx - 1);
        }

        if (bodyData.length === 0) {
          console.warn(`  [${comboKey}] WARNING: Missing body binary, skipping`);
          continue;
        }

        // Generate both normal and -L (logo) variants
        for (const logoBit of [false, true]) {
          const suffix = logoBit ? '-L' : '';
          const svgFile = join(svgDir, `${comboKey}${suffix}.svg`);

          const svg = renderSVG(palette, bodyData, faceData, itemData, subitemData, m.classIdx, m.bodyIdx, faceIdx, itemIdx, logoBit);
          fs.writeFileSync(svgFile, svg);
          totalBytes += Buffer.byteLength(svg);
          svgCount++;
        }

        // Generate metadata (non-logo variant, same as original script)
        const faceName = faceVariantName(faceIdx);
        const itemName = itemVariantName(m.classIdx, itemIdx);
        const subitemName = subitemVariantName(m.classIdx, subitemIdx);
        const bgLabel = 'BTC Orange'; // default

        const attributes = [
          { trait_type: 'Class', value: m.name },
          { trait_type: 'Body', value: m.bodyName },
          { trait_type: 'Face', value: faceName },
          { trait_type: 'Item', value: itemName },
          { trait_type: 'Background', value: bgLabel },
        ];
        if (subitemName !== 'None') {
          attributes.push({ trait_type: 'Accessory', value: subitemName });
        }

        const metadata = {
          name: `MiFren — ${m.name} ${m.bodyName}`,
          description: `Magic Internet Fren — ${m.name} class, ${m.bodyName} body, ${faceName}, ${itemName}`,
          image: `ipfs://SVG_CID/${comboKey}.svg`,
          attributes,
        };

        fs.writeFileSync(join(metaDir, comboKey), JSON.stringify(metadata, null, 2));
        metaCount++;
      }
    }
  }

  console.log(`  ${m.name} body ${m.bodyIdx} (${m.bodyName}): ${m.numFaces * m.numItems * NUM_SUBITEMS} combos × 2 variants`);
}

console.log(`\nGenerated ${svgCount} SVGs (${(totalBytes / 1024 / 1024).toFixed(1)} MB)`);
console.log(`Generated ${metaCount} metadata files`);
console.log(`\nFiles written to:`);
console.log(`  SVGs:     ${svgDir}`);
console.log(`  Metadata: ${metaDir}`);
console.log(`\nNext: re-add svg-out to IPFS and pin the new CID.`);
