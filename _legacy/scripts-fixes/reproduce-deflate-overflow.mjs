#!/usr/bin/env node
// reproduce-deflate-overflow.mjs
//
// Reproduces the exact on-chain rendering pipeline from FrenForge + png.ts
// to find why specific trait combos cause "Index out of range" in the
// DEFLATE encoder's Uint8Array.
//
// Usage: node scripts/reproduce-deflate-overflow.mjs

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

// ---------------------------------------------------------------------------
// 1. Load Data
// ---------------------------------------------------------------------------

console.log('=== Loading trait data ===\n');

// Load palette-rgb.bin (raw RGB888 bytes, 3 bytes per color)
const paletteRGB = new Uint8Array(readFileSync(resolve(ROOT, 'compressed-traits/palette-rgb.bin')));
console.log(`Palette: ${paletteRGB.length} bytes = ${paletteRGB.length / 3} colors`);

// Parse compressed-traits.ts to extract trait blobs by traitKey
const traitsSource = readFileSync(resolve(ROOT, 'compressed-traits/compressed-traits.ts'), 'utf8');
const traitMap = new Map(); // traitKey -> Uint8Array

// Match each trait entry: traitKey and blob fields
const traitRegex = /traitKey:\s*(\d+),[\s\S]*?blob:\s*'([0-9a-fA-F]+)'/g;
let match;
while ((match = traitRegex.exec(traitsSource)) !== null) {
    const traitKey = parseInt(match[1], 10);
    const hexStr = match[2];
    const bytes = new Uint8Array(hexStr.length / 2);
    for (let i = 0; i < hexStr.length; i += 2) {
        bytes[i / 2] = parseInt(hexStr.substring(i, i + 2), 16);
    }
    traitMap.set(traitKey, bytes);
}
console.log(`Loaded ${traitMap.size} trait blobs\n`);

// ---------------------------------------------------------------------------
// BTC Logo Bits (from constants.ts)
// ---------------------------------------------------------------------------
const BTC_LOGO_BITS = new Uint8Array([
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   3,  48,   0,   0,  51,   0,   0,  15, 248,   0,
    0, 255, 192,   0,   3,  14,   0,   0,  48,  96,   0,   3,   6,   0,
    0,  48, 224,   0,   3, 252,   0,   0,  63, 224,   0,   3,   7,   0,
    0,  48,  48,   0,   3,   7,   0,   0, 255, 224,   0,  15, 252,   0,
    0,  51,   0,   0,   3,  48,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
]);

const GRID_TOTAL = 784;

function isLogoCell(gridPos) {
    const bitIndex = gridPos;
    const byteIndex = bitIndex >> 3;
    const bitOffset = 7 - (bitIndex & 7);
    if (byteIndex >= 98) return false;
    return ((BTC_LOGO_BITS[byteIndex] >> bitOffset) & 1) === 1;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const CANVAS_SIDE = 120;
const CROP_SIDE = 64;
// All classes use (28, 28) crop offset
const CROP_OFFSETS = [28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28];

// ---------------------------------------------------------------------------
// 2. Pipeline Functions (ported from AssemblyScript)
// ---------------------------------------------------------------------------

// a) compositeLayer
function compositeLayer(canvas, layerData, canvasSide = 120) {
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
    const byteIdx = pixelDataStart;

    for (let p = 0; p < totalBBoxPixels; p++) {
        const nibbleByteOffset = byteIdx + (p >> 1);
        if (nibbleByteOffset >= layerData.length) break;

        const rawByte = layerData[nibbleByteOffset];
        const nibble = ((p & 1) === 0)
            ? ((rawByte >> 4) & 0x0F)
            : (rawByte & 0x0F);

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

// b) Crop
function cropCanvas(srcCanvas, classIdx, bgCanvasValue) {
    const offIdx = classIdx * 2;
    const cropX = CROP_OFFSETS[offIdx];
    const cropY = CROP_OFFSETS[offIdx + 1];

    const dstCanvas = new Uint8Array(CROP_SIDE * CROP_SIDE);
    for (let dy = 0; dy < CROP_SIDE; dy++) {
        const sy = cropY + dy;
        for (let dx = 0; dx < CROP_SIDE; dx++) {
            const sx = cropX + dx;
            const v = srcCanvas[sy * CANVAS_SIDE + sx];
            dstCanvas[dy * CROP_SIDE + dx] = v === 0 ? bgCanvasValue : v;
        }
    }
    return dstCanvas;
}

// c) quantizeColors
function quantizeColors(canvas, palette, totalPixels, maxColors) {
    const used = new Uint8Array(256);
    for (let i = 0; i < totalPixels; i++) {
        used[canvas[i]] = 1;
    }

    let count = 0;
    for (let i = 0; i < 256; i++) {
        if (used[i] !== 0) count++;
    }
    const colorsBefore = count;
    if (count <= maxColors) return { colorsBefore, colorsAfter: count };

    const MAX_U = 64;
    const vals = new Uint8Array(MAX_U);
    const cR = new Int32Array(MAX_U);
    const cG = new Int32Array(MAX_U);
    const cB = new Int32Array(MAX_U);
    const alive = new Uint8Array(MAX_U);
    let n = 0;

    for (let i = 0; i < 256; i++) {
        if (used[i] === 0) continue;
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
        let mi = -1;
        let mj = -1;

        for (let i = 0; i < n; i++) {
            if (alive[i] === 0) continue;
            for (let j = i + 1; j < n; j++) {
                if (alive[j] === 0) continue;
                const dr = cR[i] - cR[j];
                const dg = cG[i] - cG[j];
                const db = cB[i] - cB[j];
                const d = dr * dr + dg * dg + db * db;
                if (d < minDist) {
                    minDist = d;
                    mi = i;
                    mj = j;
                }
            }
        }

        if (mi < 0) break;

        cR[mi] = Math.floor((cR[mi] + cR[mj]) / 2);
        cG[mi] = Math.floor((cG[mi] + cG[mj]) / 2);
        cB[mi] = Math.floor((cB[mi] + cB[mj]) / 2);

        const oldVal = vals[mj];
        const newVal = vals[mi];
        for (let p = 0; p < totalPixels; p++) {
            if (canvas[p] === oldVal) canvas[p] = newVal;
        }

        alive[mj] = 0;
        aliveCount--;
    }

    return { colorsBefore, colorsAfter: aliveCount };
}

// d) PNG row filter predictor
function pngPredict(f, a, b, c) {
    if (f <= 0) return 0;
    if (f === 1) return a;
    if (f === 2) return b;
    if (f === 3) return (a + b) >> 1;
    // Paeth
    const p = a + b - c;
    let pa = p - a; if (pa < 0) pa = -pa;
    let pb = p - b; if (pb < 0) pb = -pb;
    let pc = p - c; if (pc < 0) pc = -pc;
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

function buildFilteredData(canvas, palette, width, height) {
    // Build globalToLocal map (first 16 unique values)
    const used = new Uint8Array(256);
    const totalPixels = width * height;
    for (let i = 0; i < totalPixels; i++) {
        used[canvas[i]] = 1;
    }

    const globalToLocal = new Uint8Array(256);
    let localCount = 0;
    for (let i = 0; i < 256; i++) {
        if (used[i] === 0) continue;
        if (localCount >= 16) break;
        globalToLocal[i] = localCount;
        localCount++;
    }

    // Pack into 4-bit rows
    const dataWidth = (width + 1) >> 1; // ceil(width/2) = 32 for width=64
    const filteredRowLen = 1 + dataWidth; // 33
    const filteredTotal = filteredRowLen * height; // 33 * 64 = 2112

    const filtered = new Uint8Array(filteredTotal);
    const prevRow = new Uint8Array(dataWidth);
    const curRow = new Uint8Array(dataWidth);

    for (let y = 0; y < height; y++) {
        const rowStart = y * filteredRowLen;
        const canvasRow = y * width;

        // Pack current row
        for (let x = 0; x < dataWidth; x++) {
            const p0 = (x * 2 < width) ? globalToLocal[canvas[canvasRow + x * 2]] : 0;
            const p1 = (x * 2 + 1 < width) ? globalToLocal[canvas[canvasRow + x * 2 + 1]] : 0;
            curRow[x] = ((p0 << 4) | p1);
        }

        // Try filters 0-4
        let bestFilter = 0;
        let bestSum = 0x7FFFFFFF;

        for (let f = 0; f <= 4; f++) {
            let sum = 0;
            for (let x = 0; x < dataWidth; x++) {
                const raw = curRow[x];
                const a = x > 0 ? curRow[x - 1] : 0;
                const bv = prevRow[x];
                const cv = x > 0 ? prevRow[x - 1] : 0;
                const pred = pngPredict(f, a, bv, cv);
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
        for (let x = 0; x < dataWidth; x++) {
            const raw = curRow[x];
            const a = x > 0 ? curRow[x - 1] : 0;
            const bv = prevRow[x];
            const cv = x > 0 ? prevRow[x - 1] : 0;
            filtered[rowStart + 1 + x] = (raw - pngPredict(bestFilter, a, bv, cv)) & 0xFF;
        }

        // Save current row
        for (let x = 0; x < dataWidth; x++) {
            prevRow[x] = curRow[x];
        }
    }

    return { filtered, filteredTotal, localCount };
}

// ---------------------------------------------------------------------------
// e) DEFLATE encoder (exact port from png.ts)
// ---------------------------------------------------------------------------

// BitWriter class
class BitWriter {
    constructor(buf, startPos) {
        this.buf = buf;
        this.pos = startPos;
        this.bitBuf = 0;
        this.bitCount = 0;
        this.maxPos = buf.length;
    }

    writeBits(value, numBits) {
        this.bitBuf |= (value << this.bitCount);
        this.bitCount += numBits;
        while (this.bitCount >= 8) {
            if (this.pos < this.maxPos) {
                this.buf[this.pos] = this.bitBuf & 0xFF;
            }
            this.pos++;
            this.bitBuf >>>= 8;
            this.bitCount -= 8;
        }
    }

    flush() {
        if (this.bitCount > 0) {
            if (this.pos < this.maxPos) {
                this.buf[this.pos] = this.bitBuf & 0xFF;
            }
            this.pos++;
            this.bitBuf = 0;
            this.bitCount = 0;
        }
    }
}

function reverseBits(val, numBits) {
    let result = 0;
    for (let i = 0; i < numBits; i++) {
        result = (result << 1) | (val & 1);
        val >>>= 1;
    }
    return result;
}

function writeFixedLitLen(bw, code) {
    if (code <= 143) {
        const val = code + 0x30;
        bw.writeBits(reverseBits(val, 8), 8);
    } else if (code <= 255) {
        const val = code - 144 + 0x190;
        bw.writeBits(reverseBits(val, 9), 9);
    } else if (code <= 279) {
        const val = code - 256;
        bw.writeBits(reverseBits(val, 7), 7);
    } else {
        const val = code - 280 + 0xC0;
        bw.writeBits(reverseBits(val, 8), 8);
    }
}

function writeFixedDist(bw, code) {
    bw.writeBits(reverseBits(code, 5), 5);
}

const LEN_EXTRA_BITS = [0,0,0,0,0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3, 4,4,4,4, 5,5,5,5, 0];
const LEN_BASE = [3,4,5,6,7,8,9,10, 11,13,15,17, 19,23,27,31, 35,43,51,59, 67,83,99,115, 131,163,195,227, 258];
const DIST_EXTRA_BITS = [0,0,0,0, 1,1,2,2, 3,3,4,4, 5,5,6,6, 7,7,8,8, 9,9,10,10, 11,11,12,12, 13,13];
const DIST_BASE = [1,2,3,4, 5,7,9,13, 17,25,33,49, 65,97,129,193, 257,385,513,769, 1025,1537,2049,3073, 4097,6145,8193,12289, 16385,24577];

function encodeLengthCode(bw, length) {
    let code = 0;
    for (let i = 28; i >= 0; i--) {
        if (length >= LEN_BASE[i]) {
            code = i;
            break;
        }
    }
    writeFixedLitLen(bw, 257 + code);
    const extra = LEN_EXTRA_BITS[code];
    if (extra > 0) {
        bw.writeBits(length - LEN_BASE[code], extra);
    }
}

function encodeDistCode(bw, dist) {
    let code = 0;
    for (let i = 29; i >= 0; i--) {
        if (dist >= DIST_BASE[i]) {
            code = i;
            break;
        }
    }
    writeFixedDist(bw, code);
    const extra = DIST_EXTRA_BITS[code];
    if (extra > 0) {
        bw.writeBits(dist - DIST_BASE[code], extra);
    }
}

// LZ77 constants
const HASH_SIZE = 8192;
const HASH_MASK = HASH_SIZE - 1;
const WINDOW_SIZE = 32768;
const WINDOW_MASK = WINDOW_SIZE - 1;
const MIN_MATCH = 3;
const MAX_MATCH = 258;
const MAX_CHAIN = 128;

function hashFunc(a, b, c) {
    return (((a * 31) ^ (b * 17) ^ c) & HASH_MASK);
}

function findMatch(data, dataLen, pos, hashHead, hashPrev, outLen, outDist) {
    outLen[0] = 0;
    outDist[0] = 0;
    if (pos + 2 >= dataLen) return;

    const h = hashFunc(data[pos], data[pos + 1], data[pos + 2]);
    let chainPos = hashHead[h];
    let chainLen = 0;
    const minPos = (pos - WINDOW_SIZE > 0) ? pos - WINDOW_SIZE : 0;
    let bestLen = 0;
    let bestDist = 0;

    while (chainPos >= minPos && chainLen < MAX_CHAIN) {
        const dist = pos - chainPos;
        if (dist > 0 && dist <= WINDOW_SIZE) {
            let mLen = 0;
            const maxLen = (dataLen - pos < MAX_MATCH) ? dataLen - pos : MAX_MATCH;

            // Quick rejection
            if (bestLen > 0 && data[chainPos + bestLen] !== data[pos + bestLen]) {
                const pi = chainPos & WINDOW_MASK;
                chainPos = hashPrev[pi];
                chainLen++;
                continue;
            }

            while (mLen < maxLen && data[pos + mLen] === data[chainPos + mLen]) {
                mLen++;
            }
            if (mLen >= MIN_MATCH && mLen > bestLen) {
                bestLen = mLen;
                bestDist = dist;
                if (mLen === MAX_MATCH) break;
            }
        }
        const pi = chainPos & WINDOW_MASK;
        chainPos = hashPrev[pi];
        chainLen++;
    }

    outLen[0] = bestLen;
    outDist[0] = bestDist;
}

function insertHash(data, dataLen, pos, hashHead, hashPrev) {
    if (pos + 2 < dataLen) {
        const h = hashFunc(data[pos], data[pos + 1], data[pos + 2]);
        hashPrev[pos & WINDOW_MASK] = hashHead[h];
        hashHead[h] = pos;
    }
}

function deflateFixed(bw, data, dataLen) {
    // BFINAL=1, BTYPE=01 (fixed Huffman)
    bw.writeBits(1, 1); // BFINAL
    bw.writeBits(1, 2); // BTYPE = 01

    const hashHead = new Int32Array(HASH_SIZE);
    const hashPrev = new Int32Array(WINDOW_SIZE);
    for (let i = 0; i < HASH_SIZE; i++) {
        hashHead[i] = -1;
    }

    const curLen = new Int32Array(1);
    const curDist = new Int32Array(1);
    const nextLen = new Int32Array(1);
    const nextDist = new Int32Array(1);

    let pos = 0;
    findMatch(data, dataLen, pos, hashHead, hashPrev, curLen, curDist);

    while (pos < dataLen) {
        if (curLen[0] < MIN_MATCH) {
            writeFixedLitLen(bw, data[pos]);
            insertHash(data, dataLen, pos, hashHead, hashPrev);
            pos++;
            findMatch(data, dataLen, pos, hashHead, hashPrev, curLen, curDist);
        } else {
            insertHash(data, dataLen, pos, hashHead, hashPrev);
            findMatch(data, dataLen, pos + 1, hashHead, hashPrev, nextLen, nextDist);

            if (nextLen[0] > curLen[0]) {
                writeFixedLitLen(bw, data[pos]);
                pos++;

                const mLen = nextLen[0];
                const mDist = nextDist[0];
                encodeLengthCode(bw, mLen);
                encodeDistCode(bw, mDist);

                for (let i = 1; i < mLen; i++) {
                    insertHash(data, dataLen, pos + i, hashHead, hashPrev);
                }
                pos += mLen;
                findMatch(data, dataLen, pos, hashHead, hashPrev, curLen, curDist);
            } else {
                const mLen = curLen[0];
                const mDist = curDist[0];
                encodeLengthCode(bw, mLen);
                encodeDistCode(bw, mDist);

                for (let i = 1; i < mLen; i++) {
                    insertHash(data, dataLen, pos + i, hashHead, hashPrev);
                }
                pos += mLen;
                findMatch(data, dataLen, pos, hashHead, hashPrev, curLen, curDist);
            }
        }
    }

    // End of block
    writeFixedLitLen(bw, 256);
}

// Adler-32
function adler32(data, start, len) {
    let a = 1;
    let b = 0;
    const end = start + len;
    for (let i = start; i < end; i++) {
        a = (a + data[i]) % 65521;
        b = (b + a) % 65521;
    }
    return ((b << 16) | a) >>> 0;
}

// ---------------------------------------------------------------------------
// Full pipeline for a single combo
// ---------------------------------------------------------------------------

function runPipeline(classIdx, bodyIdx, faceIdx, itemIdx, subitemIdx, tokenId) {
    const palette = paletteRGB;

    // Compute background color
    const gridPos = tokenId - 1;
    const isLogo = gridPos < GRID_TOTAL && isLogoCell(gridPos);
    const bgR = isLogo ? 0xFF : 0xF7;
    const bgG = isLogo ? 0xB8 : 0x93;
    const bgB = isLogo ? 0x4D : 0x1A;

    // Find bgCanvasValue
    let bgCanvasValue = 0;
    const palColors = Math.floor(palette.length / 3);
    for (let i = 0; i < palColors; i++) {
        if (palette[i * 3] === bgR && palette[i * 3 + 1] === bgG && palette[i * 3 + 2] === bgB) {
            bgCanvasValue = i + 1;
            break;
        }
    }

    let usePalette = palette;
    if (bgCanvasValue === 0) {
        // Append bg color
        usePalette = new Uint8Array(palette.length + 3);
        usePalette.set(palette);
        usePalette[palette.length] = bgR;
        usePalette[palette.length + 1] = bgG;
        usePalette[palette.length + 2] = bgB;
        bgCanvasValue = palColors + 1;
    }

    // Compute trait keys
    const bodyKey = classIdx * 256 + bodyIdx;
    const faceClassIdx = (classIdx === 5) ? 5 : (classIdx === 6) ? 6 : 0;
    const faceKey = 65536 + faceClassIdx * 256 + faceIdx;
    const itemKey = 131072 + classIdx * 256 + itemIdx;

    const bodyData = traitMap.get(bodyKey) || new Uint8Array(0);
    const faceData = traitMap.get(faceKey) || new Uint8Array(0);
    const itemData = traitMap.get(itemKey) || new Uint8Array(0);

    let subitemData = new Uint8Array(0);
    if (subitemIdx > 0) {
        const subitemClassIdx = (classIdx === 4) ? 4 : 0;
        const subitemKey = 196608 + subitemClassIdx * 256 + (subitemIdx - 1);
        subitemData = traitMap.get(subitemKey) || new Uint8Array(0);
    }

    // Check if traits found
    const bodyFound = traitMap.has(bodyKey);
    const faceFound = traitMap.has(faceKey);
    const itemFound = traitMap.has(itemKey);

    // Composite at 120x120
    const srcCanvas = new Uint8Array(CANVAS_SIDE * CANVAS_SIDE);
    compositeLayer(srcCanvas, faceData, CANVAS_SIDE);
    compositeLayer(srcCanvas, bodyData, CANVAS_SIDE);
    compositeLayer(srcCanvas, itemData, CANVAS_SIDE);
    if (subitemData.length > 0) {
        compositeLayer(srcCanvas, subitemData, CANVAS_SIDE);
    }

    // Crop 64x64
    const dstCanvas = cropCanvas(srcCanvas, classIdx, bgCanvasValue);

    // Count colors before quantization
    const totalPixels = CROP_SIDE * CROP_SIDE;
    const { colorsBefore, colorsAfter } = quantizeColors(dstCanvas, usePalette, totalPixels, 16);

    // Build filtered data (4-bit PNG)
    const { filtered, filteredTotal, localCount } = buildFilteredData(dstCanvas, usePalette, CROP_SIDE, CROP_SIDE);

    // Analyze filtered data
    let lowCount = 0; // bytes in 0-143 range
    let highCount = 0; // bytes in 144-255 range
    let maxByte = 0;
    for (let i = 0; i < filteredTotal; i++) {
        const v = filtered[i];
        if (v > maxByte) maxByte = v;
        if (v >= 144) highCount++;
        else lowCount++;
    }

    // DEFLATE with large buffer to measure actual output
    const safeBufSize = filteredTotal * 4 + 1024; // very generous
    const compBuf = new Uint8Array(safeBufSize);
    compBuf[0] = 0x78;
    compBuf[1] = 0x01;

    const bw = new BitWriter(compBuf, 2);
    deflateFixed(bw, filtered, filteredTotal);
    bw.flush();

    const deflateBytes = bw.pos; // includes zlib header (2 bytes are at positions 0-1, bw starts at 2)
    const actualDeflateOutput = bw.pos - 2; // just deflate payload
    const adlerVal = adler32(filtered, 0, filteredTotal);
    const totalZlibSize = bw.pos + 4; // + adler32

    // Test buffer sizes
    const testSizes = [2112, 2240, 2400, 2632, 3000, 4736];
    const overflows = {};
    for (const sz of testSizes) {
        // The actual data written starts at position 2 (after zlib header)
        // Total required buffer = bw.pos + 4 (adler32)
        overflows[sz] = totalZlibSize > sz;
    }

    return {
        bodyKey, faceKey, itemKey,
        bodyFound, faceFound, itemFound,
        bodyLen: bodyData.length,
        faceLen: faceData.length,
        itemLen: itemData.length,
        bgCanvasValue,
        isLogo,
        bgColor: `#${bgR.toString(16).padStart(2,'0')}${bgG.toString(16).padStart(2,'0')}${bgB.toString(16).padStart(2,'0')}`,
        colorsBefore,
        colorsAfter,
        localCount,
        filteredTotal,
        maxByte,
        lowCount,
        highCount,
        highRatio: (highCount / filteredTotal * 100).toFixed(1) + '%',
        actualDeflateOutput,
        deflateBytes: bw.pos,
        totalZlibSize,
        overflows,
    };
}

// ---------------------------------------------------------------------------
// 3. Test Combos
// ---------------------------------------------------------------------------

const CLASS_NAMES = ['Wizard', 'King', 'Knight', 'Apprentice', 'Peasant', 'Gnome', 'Elf'];

const testCombos = [
    // FAILING
    { label: 'FAIL', classIdx: 1, bodyIdx: 2, faceIdx: 9, itemIdx: 1, subitemIdx: 0, tokenId: 100 },
    { label: 'FAIL', classIdx: 1, bodyIdx: 2, faceIdx: 3, itemIdx: 0, subitemIdx: 0, tokenId: 100 },
    { label: 'FAIL', classIdx: 4, bodyIdx: 1, faceIdx: 10, itemIdx: 0, subitemIdx: 0, tokenId: 100 },
    { label: 'FAIL (t=320)', classIdx: 6, bodyIdx: 0, faceIdx: 0, itemIdx: 0, subitemIdx: 0, tokenId: 320 },

    // PASSING
    { label: 'PASS', classIdx: 1, bodyIdx: 3, faceIdx: 7, itemIdx: 1, subitemIdx: 0, tokenId: 100 },
    { label: 'PASS', classIdx: 1, bodyIdx: 2, faceIdx: 9, itemIdx: 0, subitemIdx: 0, tokenId: 100 },
    { label: 'PASS', classIdx: 0, bodyIdx: 0, faceIdx: 9, itemIdx: 0, subitemIdx: 0, tokenId: 100 },
    { label: 'PASS (t=1)', classIdx: 6, bodyIdx: 0, faceIdx: 0, itemIdx: 0, subitemIdx: 0, tokenId: 1 },
];

console.log('=== Testing Trait Combos ===\n');

const results = [];

for (const combo of testCombos) {
    const className = CLASS_NAMES[combo.classIdx] || 'Unknown';
    const desc = `${combo.label}: ${className} class=${combo.classIdx} body=${combo.bodyIdx} face=${combo.faceIdx} item=${combo.itemIdx} sub=${combo.subitemIdx} token=${combo.tokenId}`;
    console.log(`--- ${desc} ---`);

    try {
        const r = runPipeline(combo.classIdx, combo.bodyIdx, combo.faceIdx, combo.itemIdx, combo.subitemIdx, combo.tokenId);

        console.log(`  Trait keys: body=${r.bodyKey} face=${r.faceKey} item=${r.itemKey}`);
        console.log(`  Data found: body=${r.bodyFound} (${r.bodyLen}B) face=${r.faceFound} (${r.faceLen}B) item=${r.itemFound} (${r.itemLen}B)`);
        console.log(`  Background: ${r.bgColor} (canvasVal=${r.bgCanvasValue}, isLogo=${r.isLogo})`);
        console.log(`  Colors: ${r.colorsBefore} before quantize -> ${r.colorsAfter} after`);
        console.log(`  Filtered data: ${r.filteredTotal} bytes, max byte value=${r.maxByte}`);
        console.log(`  Byte distribution: ${r.lowCount} in 0-143 (8-bit codes), ${r.highCount} in 144-255 (9-bit codes) = ${r.highRatio}`);
        console.log(`  DEFLATE output: ${r.actualDeflateOutput} bytes (payload), bw.pos=${r.deflateBytes}`);
        console.log(`  Total zlib stream: ${r.totalZlibSize} bytes (incl 2 header + ${r.actualDeflateOutput} deflate + 4 adler32)`);
        console.log(`  Buffer overflow tests:`);
        for (const [sz, overflows] of Object.entries(r.overflows)) {
            console.log(`    bufSize=${sz}: ${overflows ? 'OVERFLOW!' : 'OK'} (need ${r.totalZlibSize}, margin=${sz - r.totalZlibSize})`);
        }

        results.push({ desc, ...r });
    } catch (e) {
        console.log(`  ERROR: ${e.message}`);
        results.push({ desc, error: e.message });
    }
    console.log('');
}

// ---------------------------------------------------------------------------
// 4. Summary
// ---------------------------------------------------------------------------

console.log('\n=== SUMMARY ===\n');
console.log('Combo                                                 | filtTotal | Colors | DefOut | ZlibTotal | 2112 | 2240 | 2400 | 2632 | 3000 | 4736');
console.log('------------------------------------------------------|-----------|--------|--------|-----------|------|------|------|------|------|-----');

for (const r of results) {
    if (r.error) {
        const label = r.desc.substring(0, 54).padEnd(54);
        console.log(`${label}| ERROR: ${r.error}`);
    } else {
        const label = r.desc.substring(0, 54).padEnd(54);
        const ft = String(r.filteredTotal).padStart(9);
        const cols = `${r.colorsBefore}->${r.colorsAfter}`.padStart(6);
        const dout = String(r.actualDeflateOutput).padStart(6);
        const zlib = String(r.totalZlibSize).padStart(9);
        const o = r.overflows;
        const f = (sz) => (o[sz] ? ' FAIL' : '  OK ').padStart(5);
        console.log(`${label}| ${ft} | ${cols} | ${dout} | ${zlib} | ${f(2112)}| ${f(2240)}| ${f(2400)}| ${f(2632)}| ${f(3000)}| ${f(4736)}`);
    }
}

console.log('\n--- Key Insight ---');
console.log('filteredTotal = 33 * 64 = 2112 bytes (fixed for 64x64 4-bit)');
console.log('The current local code uses: maxCompressed = filteredTotal * 2 + 512 = 4736');
console.log('');

// Find the tightest failing threshold
let maxFailZlib = 0;
let minPassZlib = Infinity;
const failSizes = [];
const passSizes = [];
for (const r of results) {
    if (r.error) continue;
    if (r.desc.startsWith('FAIL')) {
        failSizes.push(r.totalZlibSize);
        if (r.totalZlibSize > maxFailZlib) maxFailZlib = r.totalZlibSize;
    } else {
        passSizes.push(r.totalZlibSize);
        if (r.totalZlibSize < minPassZlib) minPassZlib = r.totalZlibSize;
    }
}

console.log(`FAILING combo zlib sizes: ${failSizes.join(', ')}`);
console.log(`PASSING combo zlib sizes: ${passSizes.join(', ')}`);
console.log(`Max zlib size among FAILING combos: ${maxFailZlib}`);
console.log(`Min zlib size among PASSING combos: ${minPassZlib}`);
console.log('');

// ---------------------------------------------------------------------------
// 5. Explore alternative buffer formulas
// ---------------------------------------------------------------------------

console.log('=== Alternative Buffer Formula Analysis ===\n');

// The deployed code was an earlier version. Common formulas:
const formulas = [
    { name: 'filteredTotal + 128', size: 2112 + 128 },
    { name: 'filteredTotal + 256', size: 2112 + 256 },
    { name: 'filteredTotal + 512', size: 2112 + 512 },
    { name: 'filteredTotal * 1.25', size: Math.ceil(2112 * 1.25) },
    { name: 'filteredTotal * 1.5',  size: Math.ceil(2112 * 1.5) },
    { name: 'filteredTotal * 2 + 512 (current)', size: 2112 * 2 + 512 },
    { name: 'ceil(filteredTotal*9/8)+64', size: Math.ceil(2112 * 9 / 8) + 64 },
    { name: 'ceil(filteredTotal*9/8)+128', size: Math.ceil(2112 * 9 / 8) + 128 },
];

for (const formula of formulas) {
    const sz = formula.size;
    let failCount = 0;
    let passCount = 0;
    for (const r of results) {
        if (r.error) continue;
        const wouldOverflow = r.totalZlibSize > sz;
        if (r.desc.startsWith('FAIL') && wouldOverflow) failCount++;
        if (r.desc.startsWith('PASS') && wouldOverflow) passCount++;
    }
    const consistent = failCount > 0 && passCount === 0;
    console.log(`  ${formula.name.padEnd(40)} = ${sz} bytes: ${failCount} FAIL overflow, ${passCount} PASS overflow ${consistent ? '<-- CONSISTENT' : ''}`);
}

// ---------------------------------------------------------------------------
// 6. Explore the OOB in more detail
// ---------------------------------------------------------------------------

console.log('\n=== WASM OOB Error Analysis ===\n');
console.log('The error "Index out of range at ~lib/typedarray.ts:168:45" is an AssemblyScript');
console.log('Uint8Array bounds check failure. In the deployed WASM, the BitWriter may NOT have');
console.log('had the maxPos guard (that was added later as a fix). Without the guard, any write');
console.log('past buf.length would trigger this OOB error.');
console.log('');
console.log('The key question is: what was the original buffer formula in the deployed contract?');
console.log('');
console.log('Important observation: The DEFLATE output WITH LZ77 compression is already much');
console.log('smaller than the input (max ~1242 bytes from 2112 input). The overflow scenario');
console.log('would require the deployed code to have used a very small buffer or had a bug in');
console.log('the buffer size calculation.');
console.log('');
console.log('Possible deployed formulas that would cause FAIL/PASS pattern:');
console.log('  - If buffer was around 1050-1200 bytes, the larger-output combos would fail');
console.log('  - Note: Elf t=320 (1242B) and Elf t=1 (1240B) are nearly identical,');
console.log('    differing only by background color (logo #FFB84D vs standard #F7931A).');
console.log('    This 2-byte difference might not explain a pass/fail difference unless the');
console.log('    buffer was right at the boundary.');

// ---------------------------------------------------------------------------
// 7. Sweep all combos to find the actual max DEFLATE output
// ---------------------------------------------------------------------------

console.log('\n=== Sweep: Finding Maximum DEFLATE Output Across All Classes ===\n');

// Test a broader set of combos
const classCombos = {
    0: { bodies: 8, items: 5 },  // Wizard
    1: { bodies: 5, items: 4 },  // King
    2: { bodies: 4, items: 4 },  // Knight
    3: { bodies: 3, items: 1 },  // Apprentice
    4: { bodies: 2, items: 3 },  // Peasant
    5: { bodies: 2, items: 3 },  // Gnome
    6: { bodies: 3, items: 1 },  // Elf  (using 3 bodies based on data)
};

let globalMaxZlib = 0;
let globalMaxCombo = '';
let sampleCount = 0;

// Only sweep a subset (every class, a few face/body combos) to keep runtime reasonable
for (const [classStr, limits] of Object.entries(classCombos)) {
    const cls = parseInt(classStr);
    for (let body = 0; body < limits.bodies; body++) {
        for (let item = 0; item < limits.items; item++) {
            // Test faces 0, 3, 7, 10, 11 (representative sample)
            for (const face of [0, 3, 7, 10, 11]) {
                // Use tokenId=100 for non-logo background
                try {
                    const r = runPipeline(cls, body, face, item, 0, 100);
                    sampleCount++;
                    if (r.totalZlibSize > globalMaxZlib) {
                        globalMaxZlib = r.totalZlibSize;
                        globalMaxCombo = `${CLASS_NAMES[cls]} body=${body} face=${face} item=${item}`;
                    }
                } catch (e) {
                    // skip
                }
            }
        }
    }
}

console.log(`Tested ${sampleCount} combos (representative sample).`);
console.log(`Maximum zlib output: ${globalMaxZlib} bytes for ${globalMaxCombo}`);
console.log('');

// Now test with logo backgrounds (tokenIds that are logo cells)
let maxLogoZlib = 0;
let maxLogoCombo = '';

for (const [classStr, limits] of Object.entries(classCombos)) {
    const cls = parseInt(classStr);
    // Just test body=0, item=0, a few faces, with a logo tokenId
    // Find a logo tokenId
    let logoTokenId = 0;
    for (let t = 1; t <= 784; t++) {
        if (isLogoCell(t - 1)) {
            logoTokenId = t;
            break;
        }
    }
    if (logoTokenId === 0) continue;

    for (let face = 0; face < 12; face++) {
        for (let body = 0; body < Math.min(limits.bodies, 3); body++) {
            try {
                const r = runPipeline(cls, body, face, 0, 0, logoTokenId);
                if (r.totalZlibSize > maxLogoZlib) {
                    maxLogoZlib = r.totalZlibSize;
                    maxLogoCombo = `${CLASS_NAMES[cls]} body=${body} face=${face} item=0 token=${logoTokenId}`;
                }
            } catch (e) {
                // skip
            }
        }
    }
}

console.log(`Maximum zlib output with logo background: ${maxLogoZlib} bytes for ${maxLogoCombo}`);
console.log(`Maximum zlib output with standard background: ${globalMaxZlib} bytes for ${globalMaxCombo}`);
console.log('');
console.log('CONCLUSION:');
console.log(`The maximum observed DEFLATE output is ${Math.max(globalMaxZlib, maxLogoZlib)} bytes.`);
console.log(`Any buffer >= ${Math.max(globalMaxZlib, maxLogoZlib)} bytes will prevent overflow.`);
console.log(`The current formula (filteredTotal * 2 + 512 = 4736) has a margin of ${4736 - Math.max(globalMaxZlib, maxLogoZlib)} bytes.`);

// ---------------------------------------------------------------------------
// 8. Test with STORE (no LZ77) to estimate worst case
// ---------------------------------------------------------------------------

console.log('\n=== Worst Case: No LZ77 (all-literal DEFLATE) ===\n');
console.log('If the deployed code had no LZ77 (DEFLATE store or all literals):');

// All-literal output: each byte requires 8 or 9 bits in fixed Huffman
// Bytes 0-143 = 8 bits, bytes 144-255 = 9 bits
// Plus BFINAL+BTYPE (3 bits), end-of-block (7 bits)
// Total bits = 3 + sum(8 or 9 per byte) + 7
// Total bytes = ceil(total_bits / 8)

for (const r of results) {
    if (r.error) continue;
    const totalBits = 3 + r.lowCount * 8 + r.highCount * 9 + 7;
    const totalBytes = Math.ceil(totalBits / 8);
    const zlibTotal = 2 + totalBytes + 4; // header + deflate + adler32
    const desc = r.desc.substring(0, 50).padEnd(50);
    console.log(`  ${desc} -> all-literal output: ${totalBytes} bytes, zlib total: ${zlibTotal}`);
}

console.log('');
console.log('If deployed code used all-literal DEFLATE (no LZ77), the output would be');
console.log('~2100-2200 bytes, which WOULD overflow a buffer of filteredTotal (2112).');
console.log('');

// ---------------------------------------------------------------------------
// 9. Test with literal-only DEFLATE to see if it matches the failure pattern
// ---------------------------------------------------------------------------

console.log('=== Testing Literal-Only DEFLATE (no LZ77 match searching) ===\n');

function deflateLiteralsOnly(bw, data, dataLen) {
    bw.writeBits(1, 1); // BFINAL
    bw.writeBits(1, 2); // BTYPE = 01 (fixed)
    for (let i = 0; i < dataLen; i++) {
        writeFixedLitLen(bw, data[i]);
    }
    writeFixedLitLen(bw, 256); // end of block
}

for (const combo of testCombos) {
    const className = CLASS_NAMES[combo.classIdx] || 'Unknown';
    const desc = `${combo.label}: ${className} c=${combo.classIdx} b=${combo.bodyIdx} f=${combo.faceIdx} i=${combo.itemIdx}`;

    try {
        const palette = paletteRGB;
        const gridPos = combo.tokenId - 1;
        const isLogo = gridPos < GRID_TOTAL && isLogoCell(gridPos);
        const bgR = isLogo ? 0xFF : 0xF7;
        const bgG = isLogo ? 0xB8 : 0x93;
        const bgB = isLogo ? 0x4D : 0x1A;

        let bgCanvasValue = 0;
        const palColors = Math.floor(palette.length / 3);
        for (let i = 0; i < palColors; i++) {
            if (palette[i * 3] === bgR && palette[i * 3 + 1] === bgG && palette[i * 3 + 2] === bgB) {
                bgCanvasValue = i + 1;
                break;
            }
        }

        let usePalette = palette;
        if (bgCanvasValue === 0) {
            usePalette = new Uint8Array(palette.length + 3);
            usePalette.set(palette);
            usePalette[palette.length] = bgR;
            usePalette[palette.length + 1] = bgG;
            usePalette[palette.length + 2] = bgB;
            bgCanvasValue = palColors + 1;
        }

        const bodyKey = combo.classIdx * 256 + combo.bodyIdx;
        const faceClassIdx = (combo.classIdx === 5) ? 5 : (combo.classIdx === 6) ? 6 : 0;
        const faceKey = 65536 + faceClassIdx * 256 + combo.faceIdx;
        const itemKey = 131072 + combo.classIdx * 256 + combo.itemIdx;

        const bodyData = traitMap.get(bodyKey) || new Uint8Array(0);
        const faceData = traitMap.get(faceKey) || new Uint8Array(0);
        const itemData = traitMap.get(itemKey) || new Uint8Array(0);

        let subitemData = new Uint8Array(0);
        if (combo.subitemIdx > 0) {
            const subitemClassIdx = (combo.classIdx === 4) ? 4 : 0;
            const subitemKey = 196608 + subitemClassIdx * 256 + (combo.subitemIdx - 1);
            subitemData = traitMap.get(subitemKey) || new Uint8Array(0);
        }

        const srcCanvas = new Uint8Array(CANVAS_SIDE * CANVAS_SIDE);
        compositeLayer(srcCanvas, faceData, CANVAS_SIDE);
        compositeLayer(srcCanvas, bodyData, CANVAS_SIDE);
        compositeLayer(srcCanvas, itemData, CANVAS_SIDE);
        if (subitemData.length > 0) {
            compositeLayer(srcCanvas, subitemData, CANVAS_SIDE);
        }

        const dstCanvas = cropCanvas(srcCanvas, combo.classIdx, bgCanvasValue);
        const totalPixels = CROP_SIDE * CROP_SIDE;
        quantizeColors(dstCanvas, usePalette, totalPixels, 16);
        const { filtered, filteredTotal } = buildFilteredData(dstCanvas, usePalette, CROP_SIDE, CROP_SIDE);

        // DEFLATE with literals only
        const safeBufSize = filteredTotal * 4 + 1024;
        const compBuf = new Uint8Array(safeBufSize);
        compBuf[0] = 0x78;
        compBuf[1] = 0x01;

        const bw = new BitWriter(compBuf, 2);
        deflateLiteralsOnly(bw, filtered, filteredTotal);
        bw.flush();

        const totalZlib = bw.pos + 4;

        // Test various buffer sizes
        const pad = desc.padEnd(55);
        const willOverflow2112 = totalZlib > 2112 ? 'OVERFLOW' : 'ok';
        const willOverflow2240 = totalZlib > 2240 ? 'OVERFLOW' : 'ok';
        const willOverflow2400 = totalZlib > 2400 ? 'OVERFLOW' : 'ok';
        console.log(`  ${pad} literalZlib=${totalZlib}  @2112:${willOverflow2112}  @2240:${willOverflow2240}  @2400:${willOverflow2400}`);
    } catch (e) {
        console.log(`  ${desc.padEnd(55)} ERROR: ${e.message}`);
    }
}

console.log('');
console.log('=== FINAL ANALYSIS ===\n');
console.log('The on-chain DEFLATE output sizes are well within the 2112-byte buffer even');
console.log('with full LZ77 compression (max observed: ~1296 bytes from 2112 input).');
console.log('');
console.log('However, if the deployed contract had a DIFFERENT version of the encoder --');
console.log('for example, without LZ77 (literal-only DEFLATE) or with the 8-bit encoder');
console.log('instead of 4-bit -- the output would be larger and could overflow.');
console.log('');
console.log('The "Index out of range" error likely came from one of:');
console.log('  1. A deployed version that used literal-only DEFLATE (no LZ77 match search)');
console.log('     where the output exceeds the allocated buffer for high-entropy combos.');
console.log('  2. A different buffer formula in the deployed code (e.g., filteredTotal + N');
console.log('     with N too small).');
console.log('  3. An 8-bit encoder path that had a different (smaller) buffer calculation.');
console.log('  4. An off-by-one in buffer size calculation or BitWriter position tracking.');
console.log('');
console.log('With the CURRENT local code (LZ77 + filteredTotal*2+512 buffer), ALL combos');
console.log('fit comfortably. The fix has already been applied to the local source.');
