#!/usr/bin/env node
// ---------------------------------------------------------------------------
// compare-tokenuri-sizes.mjs
//
// Simulates the FrenForge on-chain rendering pipeline offline to compare
// data URI sizes at different crop sizes (64x64, 56x56, 48x48).
//
// Usage: node scripts/compare-tokenuri-sizes.mjs
// ---------------------------------------------------------------------------

import fs from 'fs';
import path from 'path';
import zlib from 'zlib';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const CANVAS_SIDE = 120;
const BG_COLOR_HEX = '#F7931A'; // BTC orange

const CLASS_NAMES = ['Wizard', 'King', 'Knight', 'Apprentice', 'Peasant', 'Gnome', 'Elf'];

const CROP_CONFIGS = [
    { size: 64, offsetX: 28, offsetY: 28, label: '64x64' },
    { size: 56, offsetX: 32, offsetY: 32, label: '56x56' },
    { size: 48, offsetX: 36, offsetY: 36, label: '48x48' },
];

const DATA_URI_LIMIT = 2048;

// On-chain fixed Huffman is empirically ~1.20x worse than zlib default
const ON_CHAIN_DEFLATE_PENALTY = 1.20;

// ---------------------------------------------------------------------------
// Test Cases
// ---------------------------------------------------------------------------

const FAILING_TOKENS = [
    { tokenId: 15,  classIdx: 1, bodyIdx: 2, faceIdx: 9,  itemIdx: 1, subitemIdx: 0, label: 'King #15' },
    { tokenId: 45,  classIdx: 1, bodyIdx: 2, faceIdx: 3,  itemIdx: 0, subitemIdx: 0, label: 'King #45' },
    { tokenId: 112, classIdx: 1, bodyIdx: 1, faceIdx: 11, itemIdx: 0, subitemIdx: 0, label: 'King #112' },
    { tokenId: 17,  classIdx: 4, bodyIdx: 1, faceIdx: 10, itemIdx: 0, subitemIdx: 0, label: 'Peasant #17' },
    { tokenId: 70,  classIdx: 4, bodyIdx: 1, faceIdx: 3,  itemIdx: 0, subitemIdx: 0, label: 'Peasant #70' },
    { tokenId: 60,  classIdx: 0, bodyIdx: 0, faceIdx: 9,  itemIdx: 0, subitemIdx: 0, label: 'Wizard #60' },
    { tokenId: 158, classIdx: 0, bodyIdx: 7, faceIdx: 8,  itemIdx: 0, subitemIdx: 0, label: 'Wizard #158' },
    { tokenId: 207, classIdx: 0, bodyIdx: 4, faceIdx: 11, itemIdx: 0, subitemIdx: 0, label: 'Wizard #207' },
    { tokenId: 315, classIdx: 2, bodyIdx: 3, faceIdx: 9,  itemIdx: 0, subitemIdx: 0, label: 'Knight #315' },
    { tokenId: 320, classIdx: 6, bodyIdx: 0, faceIdx: 0,  itemIdx: 0, subitemIdx: 0, label: 'Elf #320' },
];

const WORKING_TOKENS = [
    { tokenId: 1,   classIdx: 0, bodyIdx: 0, faceIdx: 0,  itemIdx: 0, subitemIdx: 0, label: 'Wizard #1' },
    { tokenId: 100, classIdx: 1, bodyIdx: 0, faceIdx: 0,  itemIdx: 0, subitemIdx: 0, label: 'King #100' },
    { tokenId: 200, classIdx: 5, bodyIdx: 0, faceIdx: 0,  itemIdx: 0, subitemIdx: 0, label: 'Gnome #200' },
];

const ALL_TOKENS = [...FAILING_TOKENS, ...WORKING_TOKENS];

// ---------------------------------------------------------------------------
// Data Loading
// ---------------------------------------------------------------------------

function loadTraits() {
    console.log('Loading compressed traits...');
    const tsPath = path.join(ROOT, 'compressed-traits', 'compressed-traits.ts');
    const tsContent = fs.readFileSync(tsPath, 'utf-8');

    const traitMap = new Map();      // traitKey -> Buffer
    const traitLabelMap = new Map(); // traitKey -> label

    // Match each trait object: traitKey, label, blob
    const re = /\{\s*traitKey:\s*(\d+),[\s\S]*?label:\s*'([^']*)'[\s\S]*?blob:\s*'([0-9a-fA-F]+)'/g;
    let m;
    while ((m = re.exec(tsContent)) !== null) {
        const key = parseInt(m[1], 10);
        traitMap.set(key, Buffer.from(m[3], 'hex'));
        traitLabelMap.set(key, m[2]);
    }

    console.log(`  Loaded ${traitMap.size} traits`);
    return { traitMap, traitLabelMap };
}

function loadPalette() {
    console.log('Loading global palette...');
    const manifestPath = path.join(ROOT, 'compressed-traits', 'manifest.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
    const hexColors = manifest.globalPalette.colors; // 247 entries

    // Build flat RGB888 array (3 bytes per color)
    const palette = Buffer.alloc(hexColors.length * 3);
    for (let i = 0; i < hexColors.length; i++) {
        const hex = hexColors[i].replace('#', '');
        palette[i * 3]     = parseInt(hex.substring(0, 2), 16);
        palette[i * 3 + 1] = parseInt(hex.substring(2, 4), 16);
        palette[i * 3 + 2] = parseInt(hex.substring(4, 6), 16);
    }

    // Find BTC orange in palette
    const bgR = parseInt(BG_COLOR_HEX.substring(1, 3), 16);
    const bgG = parseInt(BG_COLOR_HEX.substring(3, 5), 16);
    const bgB = parseInt(BG_COLOR_HEX.substring(5, 7), 16);

    let bgGlobalIdx = -1;
    for (let i = 0; i < hexColors.length; i++) {
        if (palette[i * 3] === bgR && palette[i * 3 + 1] === bgG && palette[i * 3 + 2] === bgB) {
            bgGlobalIdx = i;
            break;
        }
    }
    if (bgGlobalIdx === -1) {
        console.error(`  WARNING: ${BG_COLOR_HEX} not in palette — appending at end`);
        bgGlobalIdx = hexColors.length;
    }

    // Canvas convention: 0 = transparent, K = globalPaletteIdx + 1
    const bgCanvasValue = bgGlobalIdx + 1;
    console.log(`  ${hexColors.length} colors | BG ${BG_COLOR_HEX} -> globalIdx ${bgGlobalIdx}, canvasVal ${bgCanvasValue}`);
    return { palette, bgCanvasValue, hexColors };
}

// ---------------------------------------------------------------------------
// Trait Key Computation
// ---------------------------------------------------------------------------

function computeTraitKeys(tc) {
    const { classIdx, bodyIdx, faceIdx, itemIdx, subitemIdx } = tc;
    const bodyKey = classIdx * 256 + bodyIdx;
    const faceClassIdx = classIdx === 5 ? 5 : classIdx === 6 ? 6 : 0;
    const faceKey = 65536 + faceClassIdx * 256 + faceIdx;
    const itemKey = 131072 + classIdx * 256 + itemIdx;
    let subitemKey = -1;
    if (subitemIdx > 0) {
        const subitemClassIdx = classIdx === 4 ? 4 : 0;
        subitemKey = 196608 + subitemClassIdx * 256 + (subitemIdx - 1);
    }
    return { bodyKey, faceKey, itemKey, subitemKey };
}

// ---------------------------------------------------------------------------
// Compositing (matches _compositeLayer in FrenForge.ts exactly)
// ---------------------------------------------------------------------------

function compositeLayer(canvas, layerData) {
    if (!layerData || layerData.length < 10) return;

    // Header bytes 3-7
    const minX  = layerData[3];
    const minY  = layerData[4];
    const bboxW = layerData[5];
    const bboxH = layerData[6];
    const localPaletteSize = layerData[7];
    if (localPaletteSize === 0 || bboxW === 0 || bboxH === 0) return;

    const paletteStart    = 8;
    const pixelDataStart  = paletteStart + localPaletteSize;
    if (pixelDataStart >= layerData.length) return;

    const totalBBoxPixels = bboxW * bboxH;

    for (let p = 0; p < totalBBoxPixels; p++) {
        const nibbleByteOffset = pixelDataStart + (p >> 1);
        if (nibbleByteOffset >= layerData.length) break;

        const rawByte = layerData[nibbleByteOffset];
        const nibble = (p & 1) === 0
            ? (rawByte >> 4) & 0x0F
            : rawByte & 0x0F;

        if (nibble === 0) continue; // transparent

        const localIdx = nibble - 1;
        if (localIdx >= localPaletteSize) continue;

        const globalIdx  = layerData[paletteStart + localIdx];
        const canvasValue = globalIdx + 1;

        const dx   = p % bboxW;
        const dy   = Math.floor(p / bboxW);
        const absX = minX + dx;
        const absY = minY + dy;
        if (absX >= CANVAS_SIDE || absY >= CANVAS_SIDE) continue;

        canvas[absY * CANVAS_SIDE + absX] = canvasValue;
    }
}

// ---------------------------------------------------------------------------
// Quantization — greedy closest-pair merge (matches quantizeColors in png.ts)
// ---------------------------------------------------------------------------

function quantizeColors(canvas, palette, totalPixels, maxColors) {
    const used = new Uint8Array(256);
    for (let i = 0; i < totalPixels; i++) used[canvas[i]] = 1;

    let count = 0;
    for (let i = 0; i < 256; i++) if (used[i]) count++;
    if (count <= maxColors) return;

    const MAX_U = 64;
    const vals   = new Uint8Array(MAX_U);
    const cR     = new Int32Array(MAX_U);
    const cG     = new Int32Array(MAX_U);
    const cB     = new Int32Array(MAX_U);
    const alive  = new Uint8Array(MAX_U);
    let n = 0;

    for (let i = 0; i < 256; i++) {
        if (!used[i]) continue;
        if (n >= MAX_U) break;
        vals[n] = i;
        if (i > 0) {
            const po = (i - 1) * 3;
            if (po + 2 < palette.length) {
                cR[n] = palette[po];
                cG[n] = palette[po + 1];
                cB[n] = palette[po + 2];
            }
        }
        alive[n] = 1;
        n++;
    }

    let aliveCount = n;

    while (aliveCount > maxColors) {
        let minDist = 0x7FFFFFFF;
        let mi = -1, mj = -1;

        for (let i = 0; i < n; i++) {
            if (!alive[i]) continue;
            for (let j = i + 1; j < n; j++) {
                if (!alive[j]) continue;
                const dr = cR[i] - cR[j];
                const dg = cG[i] - cG[j];
                const db = cB[i] - cB[j];
                const d = dr * dr + dg * dg + db * db;
                if (d < minDist) { minDist = d; mi = i; mj = j; }
            }
        }
        if (mi < 0) break;

        cR[mi] = (cR[mi] + cR[mj]) >> 1;
        cG[mi] = (cG[mi] + cG[mj]) >> 1;
        cB[mi] = (cB[mi] + cB[mj]) >> 1;

        const oldVal = vals[mj];
        const newVal = vals[mi];
        for (let p = 0; p < totalPixels; p++) {
            if (canvas[p] === oldVal) canvas[p] = newVal;
        }
        alive[mj] = 0;
        aliveCount--;
    }
}

// ---------------------------------------------------------------------------
// PNG helpers
// ---------------------------------------------------------------------------

function pngPredict(f, a, b, c) {
    if (f <= 0) return 0;
    if (f === 1) return a;
    if (f === 2) return b;
    if (f === 3) return (a + b) >> 1;
    // Paeth
    const p = a + b - c;
    const pa = Math.abs(p - a);
    const pb = Math.abs(p - b);
    const pc = Math.abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

function crc32(buf, start, len) {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) {
            c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        }
        table[n] = c >>> 0;
    }
    let crc = 0xFFFFFFFF;
    for (let i = start; i < start + len; i++) {
        crc = table[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
}

function writeBE32(buf, off, val) {
    buf[off]     = (val >> 24) & 0xFF;
    buf[off + 1] = (val >> 16) & 0xFF;
    buf[off + 2] = (val >>  8) & 0xFF;
    buf[off + 3] =  val        & 0xFF;
}

function writeChunk(png, off, chunkType, data) {
    writeBE32(png, off, data.length);
    off += 4;
    const typeStart = off;
    png[off++] = (chunkType >> 24) & 0xFF;
    png[off++] = (chunkType >> 16) & 0xFF;
    png[off++] = (chunkType >>  8) & 0xFF;
    png[off++] =  chunkType        & 0xFF;
    for (let i = 0; i < data.length; i++) png[off++] = data[i];
    const crc = crc32(png, typeStart, 4 + data.length);
    writeBE32(png, off, crc);
    off += 4;
    return off;
}

// ---------------------------------------------------------------------------
// 4-bit indexed PNG encoder (zlib for lower-bound measurement)
// ---------------------------------------------------------------------------

function encodePNG4bit(canvas, palette, width, height) {
    // Step 1: local palette
    const used = new Uint8Array(256);
    const total = width * height;
    for (let i = 0; i < total; i++) used[canvas[i]] = 1;

    const g2l = new Uint8Array(256);
    const lR = new Uint8Array(16);
    const lG = new Uint8Array(16);
    const lB = new Uint8Array(16);
    let lc = 0;

    for (let i = 0; i < 256; i++) {
        if (!used[i]) continue;
        if (lc >= 16) break;
        g2l[i] = lc;
        if (i > 0) {
            const po = (i - 1) * 3;
            if (po + 2 < palette.length) {
                lR[lc] = palette[po];
                lG[lc] = palette[po + 1];
                lB[lc] = palette[po + 2];
            }
        }
        lc++;
    }

    // Step 2: pack 4-bit rows + adaptive filter
    const dataWidth      = (width + 1) >> 1;
    const filteredRowLen = 1 + dataWidth;
    const filteredTotal  = filteredRowLen * height;

    const filtered = Buffer.alloc(filteredTotal);
    const prevRow  = new Uint8Array(dataWidth);
    const curRow   = new Uint8Array(dataWidth);

    for (let y = 0; y < height; y++) {
        const rowStart  = y * filteredRowLen;
        const canvasRow = y * width;

        for (let x = 0; x < dataWidth; x++) {
            const p0 = (x * 2     < width) ? g2l[canvas[canvasRow + x * 2]]     : 0;
            const p1 = (x * 2 + 1 < width) ? g2l[canvas[canvasRow + x * 2 + 1]] : 0;
            curRow[x] = (p0 << 4) | p1;
        }

        let bestFilter = 0;
        let bestSum    = 0x7FFFFFFF;
        for (let f = 0; f <= 4; f++) {
            let sum = 0;
            for (let x = 0; x < dataWidth; x++) {
                const raw = curRow[x];
                const a   = x > 0 ? curRow[x - 1]  : 0;
                const b   = prevRow[x];
                const c   = x > 0 ? prevRow[x - 1] : 0;
                const v   = (raw - pngPredict(f, a, b, c)) & 0xFF;
                sum += v < 128 ? v : 256 - v;
            }
            if (sum < bestSum) { bestSum = sum; bestFilter = f; }
        }

        filtered[rowStart] = bestFilter;
        for (let x = 0; x < dataWidth; x++) {
            const raw = curRow[x];
            const a   = x > 0 ? curRow[x - 1]  : 0;
            const b   = prevRow[x];
            const c   = x > 0 ? prevRow[x - 1] : 0;
            filtered[rowStart + 1 + x] = (raw - pngPredict(bestFilter, a, b, c)) & 0xFF;
        }

        for (let x = 0; x < dataWidth; x++) prevRow[x] = curRow[x];
    }

    // Step 3: DEFLATE
    const compressed = zlib.deflateSync(Buffer.from(filtered), {
        level: zlib.constants.Z_DEFAULT_COMPRESSION,
    });

    // Step 4: assemble PNG
    const plteLen = lc * 3;
    const zlibLen = compressed.length;
    const pngSize = 8 + (12 + 13) + (12 + plteLen) + (12 + zlibLen) + 12;
    const png     = Buffer.alloc(pngSize);
    let off = 0;

    const sig = [137, 80, 78, 71, 13, 10, 26, 10];
    for (let i = 0; i < 8; i++) png[off++] = sig[i];

    // IHDR
    const ihdr = Buffer.alloc(13);
    writeBE32(ihdr, 0, width);
    writeBE32(ihdr, 4, height);
    ihdr[8]  = 4; // bitDepth
    ihdr[9]  = 3; // colorType = indexed
    ihdr[10] = 0; // compression
    ihdr[11] = 0; // filter
    ihdr[12] = 0; // interlace
    off = writeChunk(png, off, 0x49484452, ihdr);

    // PLTE
    const plte = Buffer.alloc(plteLen);
    for (let i = 0; i < lc; i++) {
        plte[i * 3]     = lR[i];
        plte[i * 3 + 1] = lG[i];
        plte[i * 3 + 2] = lB[i];
    }
    off = writeChunk(png, off, 0x504C5445, plte);

    // IDAT
    off = writeChunk(png, off, 0x49444154, compressed);

    // IEND
    off = writeChunk(png, off, 0x49454E44, Buffer.alloc(0));

    return {
        pngBuf:           png.subarray(0, off),
        filteredDataSize: filteredTotal,
        localColorCount:  lc,
        zlibIdatSize:     zlibLen,
    };
}

// ---------------------------------------------------------------------------
// Data URI builder (matches FrenForge._buildDataUri)
// ---------------------------------------------------------------------------

function buildDataUri(tokenId, classIdx, pngBuf) {
    const b64 = pngBuf.toString('base64');
    const cls = CLASS_NAMES[classIdx] || 'Unknown';

    const json = `{"name":"${cls} #${tokenId}","image":"data:image/png;base64,${b64}"}`;

    let uri = '';
    for (let i = 0; i < json.length; i++) {
        const ch = json.charCodeAt(i);
        if      (ch === 0x22) uri += '%22';  // "
        else if (ch === 0x7B) uri += '%7B';  // {
        else if (ch === 0x7D) uri += '%7D';  // }
        else if (ch === 0x23) uri += '%23';  // #
        else if (ch === 0x20) uri += '%20';  // space
        else uri += json[i];
    }
    return 'data:application/json,' + uri;
}

// ---------------------------------------------------------------------------
// Estimate on-chain data URI size (fixed Huffman approximation)
// ---------------------------------------------------------------------------

function estimateOnChainDataUri(tokenId, classIdx, filteredDataSize, zlibIdatSize, plteLen) {
    // On-chain ratio: zlib IDAT * penalty
    const estIdat = Math.ceil(zlibIdatSize * ON_CHAIN_DEFLATE_PENALTY);
    // PNG envelope: sig(8) + IHDR chunk(25) + PLTE chunk(12+plteLen) + IDAT chunk(12+idat) + IEND(12)
    const estPng  = 8 + 25 + 12 + plteLen + 12 + estIdat + 12;
    const estB64  = Math.ceil(estPng * 4 / 3);

    // URI overhead (pre-computed from the format)
    const cls     = CLASS_NAMES[classIdx] || 'Unknown';
    const prefix  = 'data:application/json,%7B%22name%22:%22';
    const name    = `${cls} %23${tokenId}`;
    const mid     = '%22,%22image%22:%22data:image/png;base64,';
    const suffix  = '%22%7D';
    const fixed   = prefix.length + name.length + mid.length + suffix.length;

    return { estPng, estB64, estUri: fixed + estB64 };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
    const t0 = Date.now();
    console.log('='.repeat(90));
    console.log(' FrenForge Data URI Size Comparison');
    console.log(' Crop sizes: 64x64 (28,28) | 56x56 (32,32) | 48x48 (36,36)');
    console.log(' OPNet receipt limit: ' + DATA_URI_LIMIT + ' bytes');
    console.log('='.repeat(90));
    console.log();

    const { traitMap, traitLabelMap } = loadTraits();
    const { palette, bgCanvasValue }  = loadPalette();

    const outDir = '/tmp/fren-compare';
    fs.mkdirSync(outDir, { recursive: true });

    // -----------------------------------------------------------------------
    // Process each test case
    // -----------------------------------------------------------------------
    const results = [];

    for (const tc of ALL_TOKENS) {
        const keys     = computeTraitKeys(tc);
        const bodyData = traitMap.get(keys.bodyKey);
        const faceData = traitMap.get(keys.faceKey);
        const itemData = traitMap.get(keys.itemKey);
        const subData  = keys.subitemKey >= 0 ? traitMap.get(keys.subitemKey) : null;

        const missing = [];
        if (!bodyData) missing.push(`body(${keys.bodyKey})`);
        if (!faceData) missing.push(`face(${keys.faceKey})`);
        if (!itemData) missing.push(`item(${keys.itemKey})`);
        if (keys.subitemKey >= 0 && !subData) missing.push(`sub(${keys.subitemKey})`);
        if (missing.length) {
            console.error(`  SKIP ${tc.label}: missing traits [${missing.join(', ')}]`);
            continue;
        }

        const traitInfo = {
            body: traitLabelMap.get(keys.bodyKey) || `body-${tc.bodyIdx}`,
            face: traitLabelMap.get(keys.faceKey) || `face-${tc.faceIdx}`,
            item: traitLabelMap.get(keys.itemKey) || `item-${tc.itemIdx}`,
        };

        const isFailing = FAILING_TOKENS.some(f => f.tokenId === tc.tokenId);
        const crops = {};

        for (const crop of CROP_CONFIGS) {
            // 1. 120x120 canvas
            const src = new Uint8Array(CANVAS_SIDE * CANVAS_SIDE);

            // 2. Composite: face(bottom) -> body -> item -> subitem(top)
            compositeLayer(src, faceData);
            compositeLayer(src, bodyData);
            compositeLayer(src, itemData);
            if (subData) compositeLayer(src, subData);

            // 3. Crop
            const S  = crop.size;
            const oX = crop.offsetX;
            const oY = crop.offsetY;
            const dst = new Uint8Array(S * S);
            for (let dy = 0; dy < S; dy++) {
                for (let dx = 0; dx < S; dx++) {
                    const v = src[(oY + dy) * CANVAS_SIDE + (oX + dx)];
                    dst[dy * S + dx] = v === 0 ? bgCanvasValue : v;
                }
            }

            // Count unique colors before quantization
            const uniqueBefore = new Set(dst).size;

            // 4. Quantize
            quantizeColors(dst, palette, S * S, 16);
            const uniqueAfter = new Set(dst).size;

            // 5. Encode PNG (zlib — lower bound)
            const { pngBuf, filteredDataSize, localColorCount, zlibIdatSize } = encodePNG4bit(dst, palette, S, S);

            // 6. Data URI (zlib)
            const dataUri  = buildDataUri(tc.tokenId, tc.classIdx, pngBuf);
            const b64Len   = pngBuf.toString('base64').length;
            const fits     = dataUri.length <= DATA_URI_LIMIT;

            // 7. On-chain estimate
            const plteLen  = localColorCount * 3;
            const est      = estimateOnChainDataUri(tc.tokenId, tc.classIdx, filteredDataSize, zlibIdatSize, plteLen);

            // 8. Save PNG
            const pngPath = path.join(outDir, `token-${tc.tokenId}-${crop.label}.png`);
            fs.writeFileSync(pngPath, pngBuf);

            crops[crop.label] = {
                pngBytes:     pngBuf.length,
                b64Len,
                uriLen:       dataUri.length,
                fits,
                uniqueBefore,
                uniqueAfter,
                localColorCount,
                filteredDataSize,
                zlibIdatSize,
                estPng:       est.estPng,
                estUri:       est.estUri,
                estFits:      est.estUri <= DATA_URI_LIMIT,
                pngPath,
            };
        }

        results.push({ ...tc, traitInfo, isFailing, crops });
    }

    // -----------------------------------------------------------------------
    // Print comparison table
    // -----------------------------------------------------------------------

    console.log();
    console.log('='.repeat(130));
    console.log(' COMPARISON TABLE');
    console.log('='.repeat(130));
    console.log();
    console.log(' zlib = Node.js zlib (best-case / lower bound)');
    console.log(' est  = on-chain fixed Huffman approximation (zlib IDAT x ' + ON_CHAIN_DEFLATE_PENALTY.toFixed(2) + ')');
    console.log();

    const COL = {
        tok:  24,
        cls:  10,
        tr:   22,
        crop: 6,
        num:  6,
        fit:  6,
    };

    function pad(s, w) { return String(s).padStart(w); }
    function padL(s, w) { return String(s).padEnd(w); }

    const divider = '-'.repeat(130);

    // Sub-header per crop group
    for (const crop of CROP_CONFIGS) {
        console.log(`--- ${crop.label} (offset ${crop.offsetX},${crop.offsetY}) ---`);
        console.log(
            padL('Token', COL.tok) + ' ' +
            padL('Class', COL.cls) + ' ' +
            padL('Traits', COL.tr) + ' ' +
            pad('PNG', COL.num) + ' ' +
            pad('B64', COL.num) + ' ' +
            pad('URI', COL.num) + ' ' +
            pad('Fit?', COL.fit) + '  |' +
            pad('estPNG', 8) + ' ' +
            pad('estURI', 8) + ' ' +
            pad('estFit?', 8) + '  |' +
            pad('Colors', 8) + ' ' +
            pad('Filt.B', 8)
        );
        console.log(divider);

        for (const r of results) {
            const c = r.crops[crop.label];
            if (!c) continue;
            const tag    = r.isFailing ? ' *' : '  ';
            const fitStr = c.fits    ? '  OK' : 'FAIL';
            const eFit   = c.estFits ? '  OK' : 'FAIL';

            console.log(
                padL(r.label + tag, COL.tok) + ' ' +
                padL(CLASS_NAMES[r.classIdx], COL.cls) + ' ' +
                padL(`b:${r.bodyIdx} f:${r.faceIdx} i:${r.itemIdx}`, COL.tr) + ' ' +
                pad(c.pngBytes, COL.num) + ' ' +
                pad(c.b64Len, COL.num) + ' ' +
                pad(c.uriLen, COL.num) + ' ' +
                pad(fitStr, COL.fit) + '  |' +
                pad(c.estPng, 8) + ' ' +
                pad(c.estUri, 8) + ' ' +
                pad(eFit, 8) + '  |' +
                pad(`${c.uniqueBefore}->${c.uniqueAfter}`, 8) + ' ' +
                pad(c.filteredDataSize, 8)
            );
        }
        console.log();
    }

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------

    console.log('='.repeat(90));
    console.log(' SUMMARY');
    console.log('='.repeat(90));
    console.log();

    for (const crop of CROP_CONFIGS) {
        const all        = results.length;
        const failSet    = results.filter(r => r.isFailing);
        const zlibFitAll = results.filter(r => r.crops[crop.label]?.fits).length;
        const zlibFitF   = failSet.filter(r => r.crops[crop.label]?.fits).length;
        const estFitAll  = results.filter(r => r.crops[crop.label]?.estFits).length;
        const estFitF    = failSet.filter(r => r.crops[crop.label]?.estFits).length;

        const worstZlib  = Math.max(...results.map(r => r.crops[crop.label]?.uriLen  || 0));
        const worstEst   = Math.max(...results.map(r => r.crops[crop.label]?.estUri  || 0));

        console.log(`  ${crop.label}:`);
        console.log(`    zlib:     ${zlibFitAll}/${all} fit (${zlibFitF}/${failSet.length} failing)  worst URI: ${worstZlib}  margin: ${DATA_URI_LIMIT - worstZlib}`);
        console.log(`    on-chain: ${estFitAll}/${all} fit (${estFitF}/${failSet.length} failing)  worst URI: ${worstEst}  margin: ${DATA_URI_LIMIT - worstEst}`);
        console.log();
    }

    // -----------------------------------------------------------------------
    // Detailed failing-token breakdown
    // -----------------------------------------------------------------------

    console.log('='.repeat(90));
    console.log(' FAILING TOKENS — DETAILED');
    console.log('='.repeat(90));
    console.log();

    for (const r of results) {
        if (!r.isFailing) continue;

        console.log(`  ${r.label}  (${CLASS_NAMES[r.classIdx]}, body:${r.bodyIdx} face:${r.faceIdx} item:${r.itemIdx})`);
        console.log(`    body="${r.traitInfo.body}"  face="${r.traitInfo.face}"  item="${r.traitInfo.item}"`);

        for (const crop of CROP_CONFIGS) {
            const c = r.crops[crop.label];
            if (!c) continue;
            const over    = c.uriLen  > DATA_URI_LIMIT ? ` (+${c.uriLen  - DATA_URI_LIMIT})` : '';
            const estOver = c.estUri  > DATA_URI_LIMIT ? ` (+${c.estUri  - DATA_URI_LIMIT})` : '';
            console.log(`    ${crop.label}:  PNG=${c.pngBytes}B  B64=${c.b64Len}  URI=${c.uriLen}${over}`);
            console.log(`            est: PNG=${c.estPng}B  URI=${c.estUri}${estOver}   colors: ${c.uniqueBefore}->${c.uniqueAfter} (local:${c.localColorCount})  filtered: ${c.filteredDataSize}B`);
        }
        console.log();
    }

    // -----------------------------------------------------------------------
    // Generate HTML
    // -----------------------------------------------------------------------

    console.log('Generating comparison HTML...');
    const html = generateHTML(results);
    const htmlPath = path.join(outDir, 'comparison.html');
    fs.writeFileSync(htmlPath, html);

    // -----------------------------------------------------------------------
    // Recommendation
    // -----------------------------------------------------------------------

    console.log();
    console.log('='.repeat(90));
    console.log(' RECOMMENDATION');
    console.log('='.repeat(90));
    console.log();

    for (const crop of CROP_CONFIGS) {
        const allFitEst  = results.every(r => r.crops[crop.label]?.estFits);
        const allFitZlib = results.every(r => r.crops[crop.label]?.fits);
        const worstEst   = Math.max(...results.map(r => r.crops[crop.label]?.estUri || 0));
        const worstZlib  = Math.max(...results.map(r => r.crops[crop.label]?.uriLen || 0));
        const failEst    = results.filter(r => !r.crops[crop.label]?.estFits).length;

        if (allFitEst) {
            console.log(`  ${crop.label}: ALL tokens estimated to fit.  worst est URI = ${worstEst}  margin = ${DATA_URI_LIMIT - worstEst}B`);
        } else if (allFitZlib) {
            console.log(`  ${crop.label}: All fit with zlib, but ${failEst} estimated to FAIL on-chain.  worst est = ${worstEst} (+${worstEst - DATA_URI_LIMIT})`);
        } else {
            const failZlib = results.filter(r => !r.crops[crop.label]?.fits).length;
            console.log(`  ${crop.label}: ${failZlib} tokens exceed limit even with zlib.  worst = ${worstZlib} (+${worstZlib - DATA_URI_LIMIT})`);
        }
    }

    console.log();
    console.log('  NOTE: "est" uses a ' + ON_CHAIN_DEFLATE_PENALTY.toFixed(2) + 'x penalty on zlib IDAT size.');
    console.log('  The actual on-chain compressor may differ. Verify with a test deployment.');
    console.log();

    const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
    console.log(`  Output directory: ${outDir}/`);
    console.log(`  PNGs saved:       ${results.length * CROP_CONFIGS.length}`);
    console.log(`  HTML report:      ${htmlPath}`);
    console.log(`  Elapsed:          ${elapsed}s`);
    console.log('='.repeat(90));
}

// ---------------------------------------------------------------------------
// HTML Generator
// ---------------------------------------------------------------------------

function generateHTML(results) {
    const failIds = new Set(FAILING_TOKENS.map(t => t.tokenId));

    let h = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>FrenForge Crop Size Comparison</title>
<style>
*{box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#111;color:#ddd;padding:24px;max-width:1400px;margin:auto}
h1{color:#F7931A}
h2{color:#FFB74D;margin-top:40px}
h3{margin-top:32px}
table{border-collapse:collapse;width:100%;margin-top:12px;font-size:12px}
th,td{padding:5px 10px;border:1px solid #333;text-align:right}
th{background:#222;color:#F7931A}
td:first-child,td:nth-child(2),td:nth-child(3){text-align:left}
.ok{color:#4caf50;font-weight:bold}
.fail{color:#f44336;font-weight:bold}
.warn{color:#ff9800}
.token-row{display:flex;gap:16px;margin-bottom:24px;align-items:flex-start;border-bottom:1px solid #333;padding-bottom:16px}
.token-info{min-width:180px;font-size:12px}
.token-info .name{font-weight:bold;color:#F7931A;font-size:14px}
.token-info .traits{color:#999;margin-top:3px}
.crop-card{text-align:center}
.crop-card img{image-rendering:pixelated;border:2px solid #333}
.crop-card .label{font-weight:bold;margin-bottom:4px;font-size:13px}
.crop-card .stats{font-size:10px;color:#999;margin-top:4px;line-height:1.5}
.legend{font-size:12px;color:#888;margin-top:8px}
</style>
</head>
<body>
<h1>FrenForge Crop Size Comparison</h1>
<p>Comparing 64x64, 56x56, and 48x48 crop windows. Limit: <strong>${DATA_URI_LIMIT} bytes</strong>.</p>
<p class="legend">* = currently failing on-chain | zlib = lower bound (Node.js zlib) | est = on-chain approximation (x${ON_CHAIN_DEFLATE_PENALTY.toFixed(2)})</p>

<h2>Summary Table</h2>
<table>
<tr><th>Token</th><th>Class</th><th>Traits</th>`;

    for (const crop of CROP_CONFIGS) {
        h += `<th>${crop.label}<br>PNG</th><th>${crop.label}<br>URI</th><th>${crop.label}<br>zlib</th><th>${crop.label}<br>estURI</th><th>${crop.label}<br>est</th>`;
    }
    h += '</tr>\n';

    for (const r of results) {
        const star = r.isFailing ? ' *' : '';
        h += `<tr><td>${r.label}${star}</td><td>${CLASS_NAMES[r.classIdx]}</td><td>b:${r.bodyIdx} f:${r.faceIdx} i:${r.itemIdx}</td>`;
        for (const crop of CROP_CONFIGS) {
            const c = r.crops[crop.label];
            if (!c) { h += '<td>-</td>'.repeat(5); continue; }
            const fc  = c.fits    ? 'ok' : 'fail';
            const ec  = c.estFits ? 'ok' : 'fail';
            h += `<td>${c.pngBytes}</td><td>${c.uriLen}</td><td class="${fc}">${c.fits ? 'OK' : 'FAIL'}</td>`;
            h += `<td>${c.estUri}</td><td class="${ec}">${c.estFits ? 'OK' : 'FAIL'}</td>`;
        }
        h += '</tr>\n';
    }
    h += '</table>\n';

    // Visual comparison
    h += '<h2>Visual Comparison</h2>\n';

    h += '<h3 style="color:#f44336">Failing Tokens</h3>\n';
    for (const r of results) {
        if (!r.isFailing) continue;
        h += tokenRowHTML(r);
    }

    h += '<h3 style="color:#4caf50">Working Tokens</h3>\n';
    for (const r of results) {
        if (r.isFailing) continue;
        h += tokenRowHTML(r);
    }

    h += '</body></html>';
    return h;

    function tokenRowHTML(r) {
        let row = '<div class="token-row">\n';
        row += `<div class="token-info">
  <div class="name">${r.label}${r.isFailing ? ' *' : ''}</div>
  <div class="traits">${CLASS_NAMES[r.classIdx]}</div>
  <div class="traits">body: ${r.traitInfo.body}</div>
  <div class="traits">face: ${r.traitInfo.face}</div>
  <div class="traits">item: ${r.traitInfo.item}</div>
</div>\n`;

        for (const crop of CROP_CONFIGS) {
            const c = r.crops[crop.label];
            if (!c) continue;
            const imgData = fs.readFileSync(c.pngPath).toString('base64');
            const fc  = c.fits    ? 'ok' : 'fail';
            const ec  = c.estFits ? 'ok' : 'fail';
            row += `<div class="crop-card">
  <div class="label">${crop.label}</div>
  <img src="data:image/png;base64,${imgData}" width="128" height="128">
  <div class="stats">
    PNG: ${c.pngBytes}B | B64: ${c.b64Len}<br>
    URI: <span class="${fc}">${c.uriLen}</span> / ${DATA_URI_LIMIT}<br>
    est URI: <span class="${ec}">${c.estUri}</span><br>
    colors: ${c.uniqueBefore} -> ${c.uniqueAfter}
  </div>
</div>\n`;
        }
        row += '</div>\n';
        return row;
    }
}

// ---------------------------------------------------------------------------
main();
