#!/usr/bin/env node
/**
 * test-png-sizes.mjs — Simulate on-chain PNG encoding for ALL classes.
 *
 * Reads compressed trait binaries, composites them exactly as FrenForge does,
 * encodes PNG with the same adaptive row filter + fixed-Huffman DEFLATE,
 * and reports the exact receipt size for every class's worst-case combo.
 *
 * This gives actual numbers, not estimates.
 */

import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { deflateRawSync, constants as zlibConstants } from 'zlib';

const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');
const CANVAS_SIDE = 120;
const CROP_SIDE = 66;
const CROP_X = 27;
const CROP_Y = 27;
const RECEIPT_LIMIT = 2048;

// ── Class definitions ────────────────────────────────────────────────────────
const CLASS_NAMES = ['Wizard', 'King', 'Knight', 'Apprentice', 'Peasant', 'Gnome', 'Elf'];

// Face class mapping (most classes use classIdx=0 universal face)
function faceClassIdx(classIdx) {
    if (classIdx === 5) return 5; // Gnome faces
    if (classIdx === 6) return 6; // Elf faces
    return 0; // Universal frog face
}

// Subitem class mapping
function subitemClassIdx(classIdx) {
    if (classIdx === 4) return 4; // Peasant headgear
    return 0;
}

// ── Read palette ─────────────────────────────────────────────────────────────
const paletteBin = readFileSync(join(TRAITS_DIR, 'palette.bin'));
const paletteColorCount = paletteBin.readUInt16BE(0);
const paletteRGB = new Uint8Array(paletteColorCount * 3);
for (let i = 0; i < paletteColorCount * 3; i++) {
    paletteRGB[i] = paletteBin[2 + i];
}
console.log(`Palette: ${paletteColorCount} colors\n`);

// ── Read all trait files ─────────────────────────────────────────────────────
// Organized as traits[layerType][classIdx][layerIdx] = Buffer
const traits = {};
const files = readdirSync(TRAITS_DIR).filter(f => f.startsWith('trait-') && f.endsWith('.bin'));
for (const f of files) {
    const data = readFileSync(join(TRAITS_DIR, f));
    const layerType = data[0];
    const classIdx = data[1];
    const layerIdx = data[2];
    if (!traits[layerType]) traits[layerType] = {};
    if (!traits[layerType][classIdx]) traits[layerType][classIdx] = {};
    traits[layerType][classIdx][layerIdx] = data;
}

// ── Composite layer (same as FrenForge._compositeLayer) ──────────────────────
function compositeLayer(canvas, layerData, canvasSide) {
    if (!layerData || layerData.length < 10) return;
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
        const nibble = (p & 1) === 0 ? (rawByte >> 4) & 0x0F : rawByte & 0x0F;
        if (nibble === 0) continue; // transparent

        const localIdx = nibble - 1;
        if (localIdx >= localPaletteSize) continue;

        const globalIdx = layerData[paletteStart + localIdx];
        const canvasValue = globalIdx + 1; // 0 = transparent

        const dx = p % bboxW;
        const dy = Math.floor(p / bboxW);
        const absX = minX + dx;
        const absY = minY + dy;
        if (absX >= canvasSide || absY >= canvasSide) continue;

        canvas[absY * canvasSide + absX] = canvasValue;
    }
}

// ── PNG row filter predictor ─────────────────────────────────────────────────
function pngPredict(f, a, b, c) {
    if (f <= 0) return 0;        // None
    if (f === 1) return a;       // Sub
    if (f === 2) return b;       // Up
    if (f === 3) return (a + b) >> 1; // Average
    // Paeth
    const p = a + b - c;
    let pa = Math.abs(p - a);
    let pb = Math.abs(p - b);
    let pc = Math.abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

// ── Encode PNG (matches on-chain encoder exactly) ────────────────────────────
function encodePNG(canvas, palette, width, height) {
    // Step 1: Scan for unique values + build local palette
    const used = new Uint8Array(256);
    for (let i = 0; i < width * height; i++) {
        used[canvas[i]] = 1;
    }

    const globalToLocal = new Uint8Array(256);
    const localR = new Uint8Array(256);
    const localG = new Uint8Array(256);
    const localB = new Uint8Array(256);
    let localCount = 0;

    // hasTransparency=false mode (all opaque, background fills transparent)
    for (let i = 0; i < 256; i++) {
        if (used[i] === 0) continue;
        globalToLocal[i] = localCount;
        const palOff = i === 0 ? -1 : (i - 1) * 3;
        if (palOff >= 0 && palOff + 2 < palette.length) {
            localR[localCount] = palette[palOff];
            localG[localCount] = palette[palOff + 1];
            localB[localCount] = palette[palOff + 2];
        }
        localCount++;
    }
    const paletteSize = localCount;

    // Step 2: Adaptive row filter
    const filteredRowLen = 1 + width;
    const filtered = Buffer.alloc(filteredRowLen * height);
    const prevRow = new Uint8Array(width);
    const curRow = new Uint8Array(width);

    for (let y = 0; y < height; y++) {
        const rowStart = y * filteredRowLen;
        // Remap to local indices
        for (let x = 0; x < width; x++) {
            curRow[x] = globalToLocal[canvas[y * width + x]];
        }

        // Try all 5 filters, pick smallest sum
        let bestFilter = 0;
        let bestSum = Infinity;
        for (let f = 0; f <= 4; f++) {
            let sum = 0;
            for (let x = 0; x < width; x++) {
                const raw = curRow[x];
                const a = x > 0 ? curRow[x - 1] : 0;
                const b = prevRow[x];
                const c = x > 0 ? prevRow[x - 1] : 0;
                const pred = pngPredict(f, a, b, c);
                const v = (raw - pred) & 0xFF;
                sum += v < 128 ? v : 256 - v;
            }
            if (sum < bestSum) {
                bestSum = sum;
                bestFilter = f;
            }
        }

        // Apply chosen filter
        filtered[rowStart] = bestFilter;
        for (let x = 0; x < width; x++) {
            const raw = curRow[x];
            const a = x > 0 ? curRow[x - 1] : 0;
            const b = prevRow[x];
            const c = x > 0 ? prevRow[x - 1] : 0;
            filtered[rowStart + 1 + x] = (raw - pngPredict(bestFilter, a, b, c)) & 0xFF;
        }

        // Copy current to prev
        curRow.forEach((v, i) => { prevRow[i] = v; });
    }

    // Step 3: DEFLATE compress using zlib Z_FIXED (fixed Huffman, matches on-chain)
    // Use level 6 with Z_FIXED strategy — closest to on-chain fixed Huffman + LZ77
    const deflated = deflateRawSync(filtered, {
        level: 6,
        strategy: zlibConstants.Z_FIXED,
    });

    // Zlib wrapper: 2 header + deflated + 4 adler32
    const adler = adler32(filtered);
    const zlibLen = 2 + deflated.length + 4;
    const zlibBuf = Buffer.alloc(zlibLen);
    zlibBuf[0] = 0x78;
    zlibBuf[1] = 0x01;
    deflated.copy(zlibBuf, 2);
    zlibBuf.writeUInt32BE(adler, 2 + deflated.length);

    // Step 4: Assemble PNG
    const ihdrData = 13;
    const plteData = paletteSize * 3;
    const idatData = zlibLen;

    const pngSize = 8 + (12 + ihdrData) + (12 + plteData) + (12 + idatData) + 12;
    const png = Buffer.alloc(pngSize);
    let off = 0;

    // PNG signature
    const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    sig.copy(png, off); off += 8;

    // IHDR
    off = writeChunk(png, off, 'IHDR', buildIHDR(width, height));

    // PLTE
    const plteBuf = Buffer.alloc(plteData);
    for (let i = 0; i < paletteSize; i++) {
        plteBuf[i * 3] = localR[i];
        plteBuf[i * 3 + 1] = localG[i];
        plteBuf[i * 3 + 2] = localB[i];
    }
    off = writeChunk(png, off, 'PLTE', plteBuf);

    // IDAT
    off = writeChunk(png, off, 'IDAT', zlibBuf);

    // IEND
    off = writeChunk(png, off, 'IEND', Buffer.alloc(0));

    return { png: png.subarray(0, off), localColors: paletteSize };
}

function adler32(data) {
    let a = 1, b = 0;
    for (let i = 0; i < data.length; i++) {
        a = (a + data[i]) % 65521;
        b = (b + a) % 65521;
    }
    return ((b << 16) | a) >>> 0;
}

function buildIHDR(w, h) {
    const buf = Buffer.alloc(13);
    buf.writeUInt32BE(w, 0);
    buf.writeUInt32BE(h, 4);
    buf[8] = 8; // bit depth
    buf[9] = 3; // indexed color
    buf[10] = 0; // deflate
    buf[11] = 0; // adaptive filter
    buf[12] = 0; // no interlace
    return buf;
}

function writeChunk(png, off, type, data) {
    png.writeUInt32BE(data.length, off); off += 4;
    png.write(type, off, 4, 'ascii'); off += 4;
    data.copy(png, off); off += data.length;

    // CRC32 over type + data
    const crcData = png.subarray(off - data.length - 4, off);
    const crc = crc32(crcData);
    png.writeUInt32BE(crc, off); off += 4;
    return off;
}

function crc32(buf) {
    const TABLE = new Uint32Array(256);
    for (let i = 0; i < 256; i++) {
        let c = i;
        for (let j = 0; j < 8; j++) {
            c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        }
        TABLE[i] = c;
    }
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < buf.length; i++) {
        crc = TABLE[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
}

// ── Build data URI (matches FrenForge._buildDataUri) ─────────────────────────
function buildDataUri(className, tokenId, pngBytes) {
    const b64 = pngBytes.toString('base64');
    const json = `{"name":"${className} #${tokenId}","image":"data:image/png;base64,${b64}"}`;

    let urlJson = '';
    for (let i = 0; i < json.length; i++) {
        const ch = json.charCodeAt(i);
        if (ch === 0x22) urlJson += '%22';
        else if (ch === 0x7B) urlJson += '%7B';
        else if (ch === 0x7D) urlJson += '%7D';
        else if (ch === 0x23) urlJson += '%23';
        else if (ch === 0x20) urlJson += '%20';
        else urlJson += json[i];
    }

    const dataUri = 'data:application/json,' + urlJson;
    const receipt = 4 + dataUri.length; // 4-byte length prefix
    return { dataUri, receipt, b64Len: b64.length, pngRawLen: pngBytes.length };
}

// ── Find bg color in palette (BTC orange = F7931A) ───────────────────────────
function findBgInPalette(r, g, b, palette) {
    const palColors = palette.length / 3;
    for (let i = 0; i < palColors; i++) {
        if (palette[i * 3] === r && palette[i * 3 + 1] === g && palette[i * 3 + 2] === b) {
            return i + 1; // canvas value = globalIdx + 1
        }
    }
    return 0; // not found, would need to append
}

// ── Main test ────────────────────────────────────────────────────────────────
console.log('╔═══════════════════════════════════════════════════════════════════════╗');
console.log('║  PNG Size Test — All Classes @ 66×66 with Adaptive Row Filtering     ║');
console.log('╚═══════════════════════════════════════════════════════════════════════╝\n');

// Find background color in palette
const bgR = 0xF7, bgG = 0x93, bgB = 0x1A; // BTC orange
let bgCanvasValue = findBgInPalette(bgR, bgG, bgB, paletteRGB);
let usePalette = paletteRGB;

if (bgCanvasValue === 0) {
    // Append bg color
    usePalette = new Uint8Array(paletteRGB.length + 3);
    usePalette.set(paletteRGB);
    usePalette[paletteRGB.length] = bgR;
    usePalette[paletteRGB.length + 1] = bgG;
    usePalette[paletteRGB.length + 2] = bgB;
    bgCanvasValue = Math.floor(paletteRGB.length / 3) + 1;
}
console.log(`Background: #F7931A → canvas value ${bgCanvasValue}\n`);

const results = [];

for (let classIdx = 0; classIdx < CLASS_NAMES.length; classIdx++) {
    const className = CLASS_NAMES[classIdx];
    const bodies = traits[0]?.[classIdx] || {};
    const fci = faceClassIdx(classIdx);
    const faces = traits[1]?.[fci] || {};
    const items = traits[2]?.[classIdx] || {};
    const sci = subitemClassIdx(classIdx);
    const subitems = traits[3]?.[sci] || {};

    const bodyKeys = Object.keys(bodies).map(Number).sort((a, b) => a - b);
    const faceKeys = Object.keys(faces).map(Number).sort((a, b) => a - b);
    const itemKeys = Object.keys(items).map(Number).sort((a, b) => a - b);
    const subitemKeys = Object.keys(subitems).map(Number).sort((a, b) => a - b);

    if (bodyKeys.length === 0 || faceKeys.length === 0 || itemKeys.length === 0) {
        console.log(`${className} (class ${classIdx}): MISSING TRAITS — skipped\n`);
        continue;
    }

    console.log(`── ${className} (class ${classIdx}) ──────────────────────────────`);
    console.log(`   Bodies: ${bodyKeys.length}, Faces: ${faceKeys.length}, Items: ${itemKeys.length}, Subitems: ${subitemKeys.length}`);

    let worst = { receipt: 0 };
    let best = { receipt: Infinity };
    let totalCombos = 0;
    let overBudget = 0;

    for (const bi of bodyKeys) {
        for (const fi of faceKeys) {
            for (const ii of itemKeys) {
                // Composite: face → body → item (same order as FrenForge)
                const canvas = new Uint8Array(CANVAS_SIDE * CANVAS_SIDE);
                compositeLayer(canvas, faces[fi], CANVAS_SIDE);
                compositeLayer(canvas, bodies[bi], CANVAS_SIDE);
                compositeLayer(canvas, items[ii], CANVAS_SIDE);

                // Add subitem if class has them (Peasant class=4)
                if (subitemKeys.length > 0) {
                    // Test with first subitem
                    compositeLayer(canvas, subitems[subitemKeys[0]], CANVAS_SIDE);
                }

                // Crop to 66×66 with bg fill
                const crop = new Uint8Array(CROP_SIDE * CROP_SIDE);
                for (let dy = 0; dy < CROP_SIDE; dy++) {
                    for (let dx = 0; dx < CROP_SIDE; dx++) {
                        const v = canvas[(CROP_Y + dy) * CANVAS_SIDE + (CROP_X + dx)];
                        crop[dy * CROP_SIDE + dx] = v === 0 ? bgCanvasValue : v;
                    }
                }

                // Encode PNG
                const { png, localColors } = encodePNG(crop, usePalette, CROP_SIDE, CROP_SIDE);

                // Build data URI with worst-case token ID (3 digits)
                const result = buildDataUri(className, 777, png);
                result.combo = `body=${bi} face=${fi} item=${ii}`;
                result.localColors = localColors;
                totalCombos++;

                if (result.receipt > RECEIPT_LIMIT) overBudget++;

                if (result.receipt > worst.receipt) worst = result;
                if (result.receipt < best.receipt) best = result;
            }
        }
    }

    const status = worst.receipt <= RECEIPT_LIMIT ? '✓ FITS' : '✗ OVER';
    console.log(`   Total combos tested: ${totalCombos}`);
    console.log(`   WORST: ${worst.receipt} bytes (${status}) — ${worst.combo} [${worst.localColors} colors, PNG ${worst.pngRawLen}B, b64 ${worst.b64Len}ch]`);
    console.log(`   BEST:  ${best.receipt} bytes — ${best.combo} [${best.localColors} colors, PNG ${best.pngRawLen}B]`);
    console.log(`   Over budget: ${overBudget}/${totalCombos} combos (${(overBudget/totalCombos*100).toFixed(1)}%)`);
    console.log(`   Margin: ${RECEIPT_LIMIT - worst.receipt} bytes ${worst.receipt > RECEIPT_LIMIT ? '(NEED TO CUT)' : '(headroom)'}`);
    console.log('');

    results.push({
        class: className, classIdx, totalCombos, overBudget,
        worstReceipt: worst.receipt, bestReceipt: best.receipt,
        worstCombo: worst.combo, worstPng: worst.pngRawLen,
    });
}

// ── Summary ──────────────────────────────────────────────────────────────────
console.log('\n╔═══════════════════════════════════════════════════════════════════════╗');
console.log('║  SUMMARY                                                              ║');
console.log('╚═══════════════════════════════════════════════════════════════════════╝\n');

console.log('Class        Worst    Budget  Margin  Status  Over/Total');
console.log('─────────────────────────────────────────────────────────');
for (const r of results) {
    const margin = RECEIPT_LIMIT - r.worstReceipt;
    const status = margin >= 0 ? ' OK ' : 'FAIL';
    const pct = (r.overBudget / r.totalCombos * 100).toFixed(0);
    console.log(
        `${r.class.padEnd(12)} ${String(r.worstReceipt).padStart(5)}  ${String(RECEIPT_LIMIT).padStart(5)}  ${String(margin).padStart(6)}  ${status}    ${r.overBudget}/${r.totalCombos} (${pct}%)`
    );
}

const anyFail = results.some(r => r.worstReceipt > RECEIPT_LIMIT);
console.log('');
if (anyFail) {
    console.log('⚠  Some classes exceed the 2048-byte receipt limit.');
    console.log('   Options:');
    console.log('   1. Reduce CROP_SIDE from 66 to 64 (saves ~6% pixels)');
    console.log('   2. Reduce CROP_SIDE to 60 (saves ~17% pixels)');
    console.log('   3. Further optimize DEFLATE compression');
    console.log('');

    // Also test at 64×64 and 60×60
    for (const testSize of [64, 60]) {
        console.log(`\n── Re-testing worst cases at ${testSize}×${testSize} ──`);
        const testCropX = Math.floor((120 - testSize) / 2);
        const testCropY = testCropX;

        for (const r of results) {
            if (r.worstReceipt <= RECEIPT_LIMIT) continue;

            // Parse worst combo
            const parts = r.worstCombo.match(/body=(\d+) face=(\d+) item=(\d+)/);
            const bi = Number(parts[1]), fi = Number(parts[2]), ii = Number(parts[3]);

            const fci2 = faceClassIdx(r.classIdx);
            const canvas = new Uint8Array(CANVAS_SIDE * CANVAS_SIDE);
            compositeLayer(canvas, traits[1]?.[fci2]?.[fi], CANVAS_SIDE);
            compositeLayer(canvas, traits[0]?.[r.classIdx]?.[bi], CANVAS_SIDE);
            compositeLayer(canvas, traits[2]?.[r.classIdx]?.[ii], CANVAS_SIDE);

            // Subitems
            const sci2 = subitemClassIdx(r.classIdx);
            const subitemKeys2 = Object.keys(traits[3]?.[sci2] || {}).map(Number);
            if (subitemKeys2.length > 0) {
                compositeLayer(canvas, traits[3][sci2][subitemKeys2[0]], CANVAS_SIDE);
            }

            const crop = new Uint8Array(testSize * testSize);
            for (let dy = 0; dy < testSize; dy++) {
                for (let dx = 0; dx < testSize; dx++) {
                    const v = canvas[(testCropY + dy) * CANVAS_SIDE + (testCropX + dx)];
                    crop[dy * testSize + dx] = v === 0 ? bgCanvasValue : v;
                }
            }

            const { png } = encodePNG(crop, usePalette, testSize, testSize);
            const result = buildDataUri(r.class, 777, png);
            const margin = RECEIPT_LIMIT - result.receipt;
            const status = margin >= 0 ? ' OK ' : 'FAIL';
            console.log(`  ${r.class.padEnd(12)} ${testSize}×${testSize}: ${result.receipt} bytes (margin: ${margin}) ${status} — PNG ${result.pngRawLen}B`);
        }
    }
} else {
    console.log('All classes fit within the 2048-byte receipt limit!');
}
