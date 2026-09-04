#!/usr/bin/env node
/**
 * test-png4bit-validate.mjs — Validate the 4-bit PNG encoder matches contract logic.
 * Generates a PNG using the exact same algorithm as encodePNG4bit in contracts/src/lib/png.ts,
 * then saves it and tries to parse it with a PNG decoder to check validity.
 */
import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

// ---- CRC32 ----
const CRC32_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    CRC32_TABLE[n] = c >>> 0;
}

function crc32(data, start, len) {
    let crc = 0xFFFFFFFF;
    for (let i = start; i < start + len; i++) crc = CRC32_TABLE[(crc ^ data[i]) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
}

function adler32(data, start, len) {
    let a = 1, b = 0;
    for (let i = start; i < start + len; i++) { a = (a + data[i]) % 65521; b = (b + a) % 65521; }
    return ((b << 16) | a) >>> 0;
}

// ---- BitWriter ----
class BitWriter {
    constructor(buf, pos) { this.buf = buf; this.pos = pos; this.bitBuf = 0; this.bitCount = 0; }
    writeBits(value, numBits) {
        this.bitBuf |= value << this.bitCount;
        this.bitCount += numBits;
        while (this.bitCount >= 8) { this.buf[this.pos++] = this.bitBuf & 0xFF; this.bitBuf >>>= 8; this.bitCount -= 8; }
    }
    flush() { if (this.bitCount > 0) { this.buf[this.pos++] = this.bitBuf & 0xFF; this.bitBuf = 0; this.bitCount = 0; } }
}

// ---- Fixed Huffman (RFC 1951 §3.2.6) ----
const LEN_EXTRA = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
const LEN_BASE = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
const DIST_EXTRA = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];
const DIST_BASE = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];

function reverseBits(val, n) { let r = 0; for (let i = 0; i < n; i++) { r = (r << 1) | (val & 1); val >>>= 1; } return r; }

function writeFixedLitLen(bw, code) {
    if (code <= 143) bw.writeBits(reverseBits(code + 0x30, 8), 8);
    else if (code <= 255) bw.writeBits(reverseBits(code - 144 + 0x190, 9), 9);
    else if (code <= 279) bw.writeBits(reverseBits(code - 256, 7), 7);
    else bw.writeBits(reverseBits(code - 280 + 0xC0, 8), 8);
}
function writeFixedDist(bw, code) { bw.writeBits(reverseBits(code, 5), 5); }

function encodeLengthCode(bw, length) {
    let code = 0;
    for (let i = 28; i >= 0; i--) { if (length >= LEN_BASE[i]) { code = i; break; } }
    writeFixedLitLen(bw, 257 + code);
    if (LEN_EXTRA[code] > 0) bw.writeBits(length - LEN_BASE[code], LEN_EXTRA[code]);
}
function encodeDistCode(bw, dist) {
    let code = 0;
    for (let i = 29; i >= 0; i--) { if (dist >= DIST_BASE[i]) { code = i; break; } }
    writeFixedDist(bw, code);
    if (DIST_EXTRA[code] > 0) bw.writeBits(dist - DIST_BASE[code], DIST_EXTRA[code]);
}

function hashFunc(a, b, c) { return (((a * 31) ^ (b * 17) ^ c) & 0x1FFF); }

function findMatch(data, dataLen, pos, hashHead, hashPrev) {
    if (pos + 2 >= dataLen) return [0, 0];
    const h = hashFunc(data[pos], data[pos+1], data[pos+2]);
    let cp = hashHead[h], cl = 0, bestLen = 0, bestDist = 0;
    const minP = Math.max(0, pos - 32768);
    while (cp >= minP && cl < 128) {
        const dist = pos - cp;
        if (dist > 0 && dist <= 32768) {
            if (bestLen > 0 && data[cp + bestLen] !== data[pos + bestLen]) {
                cp = hashPrev[cp & 32767]; cl++; continue;
            }
            let ml = 0; const mx = Math.min(dataLen - pos, 258);
            while (ml < mx && data[pos+ml] === data[cp+ml]) ml++;
            if (ml >= 3 && ml > bestLen) { bestLen = ml; bestDist = dist; if (ml === 258) break; }
        }
        cp = hashPrev[cp & 32767]; cl++;
    }
    return [bestLen, bestDist];
}

function insertHash(data, dataLen, pos, hashHead, hashPrev) {
    if (pos + 2 < dataLen) {
        const h = hashFunc(data[pos], data[pos+1], data[pos+2]);
        hashPrev[pos & 32767] = hashHead[h]; hashHead[h] = pos;
    }
}

function deflateFixed(bw, data, dataLen) {
    bw.writeBits(1, 1); // BFINAL
    bw.writeBits(1, 2); // BTYPE=01 fixed
    const hashHead = new Int32Array(8192).fill(-1);
    const hashPrev = new Int32Array(32768);
    let pos = 0;
    let [curLen, curDist] = findMatch(data, dataLen, pos, hashHead, hashPrev);
    while (pos < dataLen) {
        if (curLen < 3) {
            writeFixedLitLen(bw, data[pos]);
            insertHash(data, dataLen, pos, hashHead, hashPrev);
            pos++;
            [curLen, curDist] = findMatch(data, dataLen, pos, hashHead, hashPrev);
        } else {
            insertHash(data, dataLen, pos, hashHead, hashPrev);
            const [nextLen, nextDist] = findMatch(data, dataLen, pos+1, hashHead, hashPrev);
            if (nextLen > curLen) {
                writeFixedLitLen(bw, data[pos]); pos++;
                encodeLengthCode(bw, nextLen); encodeDistCode(bw, nextDist);
                for (let i = 1; i < nextLen; i++) insertHash(data, dataLen, pos+i, hashHead, hashPrev);
                pos += nextLen;
                [curLen, curDist] = findMatch(data, dataLen, pos, hashHead, hashPrev);
            } else {
                encodeLengthCode(bw, curLen); encodeDistCode(bw, curDist);
                for (let i = 1; i < curLen; i++) insertHash(data, dataLen, pos+i, hashHead, hashPrev);
                pos += curLen;
                [curLen, curDist] = findMatch(data, dataLen, pos, hashHead, hashPrev);
            }
        }
    }
    writeFixedLitLen(bw, 256);
}

function writeBE32(buf, off, val) {
    buf[off] = (val >> 24) & 0xFF; buf[off+1] = (val >> 16) & 0xFF;
    buf[off+2] = (val >> 8) & 0xFF; buf[off+3] = val & 0xFF;
}

function writeChunk(png, off, type, data) {
    writeBE32(png, off, data.length); off += 4;
    const ts = off;
    png[off++] = (type >> 24) & 0xFF; png[off++] = (type >> 16) & 0xFF;
    png[off++] = (type >> 8) & 0xFF; png[off++] = type & 0xFF;
    for (let i = 0; i < data.length; i++) png[off++] = data[i];
    writeBE32(png, off, crc32(png, ts, 4 + data.length)); off += 4;
    return off;
}

function pngPredict(f, a, b, c) {
    if (f <= 0) return 0;
    if (f === 1) return a;
    if (f === 2) return b;
    if (f === 3) return (a + b) >> 1;
    const p = a + b - c;
    let pa = p - a; if (pa < 0) pa = -pa;
    let pb = p - b; if (pb < 0) pb = -pb;
    let pc = p - c; if (pc < 0) pc = -pc;
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

// ---- encodePNG4bit: exact mirror of contracts/src/lib/png.ts ----
function encodePNG4bit(canvas, palette, width, height) {
    const used = new Uint8Array(256);
    const totalPixels = width * height;
    for (let i = 0; i < totalPixels; i++) used[canvas[i]] = 1;

    const g2l = new Uint8Array(256);
    const lR = new Uint8Array(16), lG = new Uint8Array(16), lB = new Uint8Array(16);
    let lc = 0;
    for (let i = 0; i < 256; i++) {
        if (!used[i]) continue;
        if (lc >= 16) break;
        g2l[i] = lc;
        if (i > 0) {
            const po = (i - 1) * 3;
            if (po + 2 < palette.length) { lR[lc] = palette[po]; lG[lc] = palette[po+1]; lB[lc] = palette[po+2]; }
        }
        lc++;
    }

    const dataWidth = (width + 1) >> 1;
    const filteredRowLen = 1 + dataWidth;
    const filteredTotal = filteredRowLen * height;
    const filtered = new Uint8Array(filteredTotal);
    const prevRow = new Uint8Array(dataWidth);
    const curRow = new Uint8Array(dataWidth);

    for (let y = 0; y < height; y++) {
        const rowStart = y * filteredRowLen;
        const canvasRow = y * width;
        for (let x = 0; x < dataWidth; x++) {
            const p0 = (x * 2 < width) ? g2l[canvas[canvasRow + x * 2]] : 0;
            const p1 = (x * 2 + 1 < width) ? g2l[canvas[canvasRow + x * 2 + 1]] : 0;
            curRow[x] = ((p0 << 4) | p1);
        }
        let bestFilter = 0, bestSum = 0x7FFFFFFF;
        for (let f = 0; f <= 4; f++) {
            let sum = 0;
            for (let x = 0; x < dataWidth; x++) {
                const raw = curRow[x];
                const a = x > 0 ? curRow[x-1] : 0;
                const bv = prevRow[x];
                const cv = x > 0 ? prevRow[x-1] : 0;
                const pred = pngPredict(f, a, bv, cv);
                const v = (raw - pred) & 0xFF;
                sum += v < 128 ? v : 256 - v;
            }
            if (sum < bestSum) { bestSum = sum; bestFilter = f; }
        }
        filtered[rowStart] = bestFilter;
        for (let x = 0; x < dataWidth; x++) {
            const raw = curRow[x];
            const a = x > 0 ? curRow[x-1] : 0;
            const bv = prevRow[x];
            const cv = x > 0 ? prevRow[x-1] : 0;
            filtered[rowStart + 1 + x] = (raw - pngPredict(bestFilter, a, bv, cv)) & 0xFF;
        }
        prevRow.set(curRow);
    }

    // DEFLATE
    const maxComp = filteredTotal + (filteredTotal >> 3) + 256;
    const compBuf = new Uint8Array(maxComp);
    compBuf[0] = 0x78; compBuf[1] = 0x01;
    const bw = new BitWriter(compBuf, 2);
    deflateFixed(bw, filtered, filteredTotal);
    bw.flush();
    const adl = adler32(filtered, 0, filteredTotal);
    writeBE32(compBuf, bw.pos, adl);
    const zlibLen = bw.pos + 4;

    // Assemble PNG
    const plteLen = lc * 3;
    const pngSize = 8 + 25 + (12 + plteLen) + (12 + zlibLen) + 12;
    const png = new Uint8Array(pngSize);
    let off = 0;
    [137,80,78,71,13,10,26,10].forEach(b => png[off++] = b);

    const ihdr = new Uint8Array(13);
    writeBE32(ihdr, 0, width); writeBE32(ihdr, 4, height);
    ihdr[8] = 4; ihdr[9] = 3;
    off = writeChunk(png, off, 0x49484452, ihdr);

    const plte = new Uint8Array(plteLen);
    for (let i = 0; i < lc; i++) { plte[i*3] = lR[i]; plte[i*3+1] = lG[i]; plte[i*3+2] = lB[i]; }
    off = writeChunk(png, off, 0x504C5445, plte);

    off = writeChunk(png, off, 0x49444154, compBuf.subarray(0, zlibLen));
    off = writeChunk(png, off, 0x49454E44, new Uint8Array(0));

    return png.subarray(0, off);
}

// ---- Compositing (mirrors FrenForge._compositeLayer) ----
function compositeLayer(canvas, layerData, side) {
    if (layerData.length < 10) return;
    const minX = layerData[3], minY = layerData[4], bw = layerData[5], bh = layerData[6];
    const palSize = layerData[7];
    if (!palSize || !bw || !bh) return;
    const palStart = 8, pixStart = palStart + palSize;
    if (pixStart >= layerData.length) return;
    for (let p = 0; p < bw * bh; p++) {
        const byteOff = pixStart + (p >> 1);
        if (byteOff >= layerData.length) break;
        const nibble = (p & 1) === 0 ? (layerData[byteOff] >> 4) & 0x0F : layerData[byteOff] & 0x0F;
        if (nibble === 0) continue;
        const localIdx = nibble - 1;
        if (localIdx >= palSize) continue;
        const globalIdx = layerData[palStart + localIdx];
        const dx = p % bw, dy = (p / bw) | 0;
        const ax = minX + dx, ay = minY + dy;
        if (ax >= side || ay >= side) continue;
        canvas[ay * side + ax] = globalIdx + 1;
    }
}

// ---- Quantize (mirrors png.ts quantizeColors) ----
function quantizeColors(canvas, palette, totalPixels, maxColors) {
    const freq = new Uint32Array(256);
    for (let i = 0; i < totalPixels; i++) freq[canvas[i]]++;
    let uniqueCount = 0;
    for (let c = 0; c < 256; c++) if (freq[c] > 0) uniqueCount++;
    if (uniqueCount <= maxColors) return;

    const active = new Uint8Array(256);
    for (let c = 0; c < 256; c++) if (freq[c] > 0) active[c] = 1;

    while (uniqueCount > maxColors) {
        let bestA = -1, bestB = -1, bestDist = 0x7FFFFFFF;
        for (let a = 0; a < 256; a++) {
            if (!active[a]) continue;
            const aR = a > 0 ? palette[(a-1)*3] : 0;
            const aG = a > 0 ? palette[(a-1)*3+1] : 0;
            const aB = a > 0 ? palette[(a-1)*3+2] : 0;
            for (let b = a + 1; b < 256; b++) {
                if (!active[b]) continue;
                const bR = b > 0 ? palette[(b-1)*3] : 0;
                const bG = b > 0 ? palette[(b-1)*3+1] : 0;
                const bB = b > 0 ? palette[(b-1)*3+2] : 0;
                const dr = aR-bR, dg = aG-bG, db = aB-bB;
                const dist = 2*dr*dr + 4*dg*dg + 3*db*db;
                if (dist < bestDist) { bestDist = dist; bestA = a; bestB = b; }
            }
        }
        if (bestA < 0) break;
        for (let i = 0; i < totalPixels; i++) {
            if (canvas[i] === bestB) canvas[i] = bestA;
        }
        active[bestB] = 0;
        uniqueCount--;
    }
}

// ---- Main Test ----
async function main() {
    // Load palette
    const palette = new Uint8Array(readFileSync(join(ROOT, 'compressed-traits/palette-rgb.bin')));
    console.log(`Palette: ${palette.length} bytes (${palette.length/3} colors)`);

    // Find bg color index for King (class 1): #FFD700
    const bgR = 0xFF, bgG = 0xD7, bgB = 0x00;
    let bgVal = 0;
    for (let i = 0; i < palette.length / 3; i++) {
        if (palette[i*3] === bgR && palette[i*3+1] === bgG && palette[i*3+2] === bgB) {
            bgVal = i + 1;
            break;
        }
    }
    if (bgVal === 0) {
        // Append bg color
        const newPal = new Uint8Array(palette.length + 3);
        newPal.set(palette);
        const idx = palette.length / 3;
        newPal[idx*3] = bgR; newPal[idx*3+1] = bgG; newPal[idx*3+2] = bgB;
        bgVal = idx + 1;
        console.log(`BG color not in palette, appended at index ${idx}, bgVal=${bgVal}`);
    } else {
        console.log(`BG color found at palette index ${bgVal - 1}, bgVal=${bgVal}`);
    }

    // Load traits for King body=3, face=1, item=1 (matches test-tokenuri.ts token 368)
    function loadTrait(name) {
        try { return new Uint8Array(readFileSync(join(ROOT, `compressed-traits/${name}.bin`))); }
        catch { console.log(`  Missing: ${name}`); return new Uint8Array(0); }
    }

    const bodyData = loadTrait('trait-0-1-3');   // classIdx=1 (King), bodyIdx=3
    const faceData = loadTrait('trait-1-0-1');   // faceClassIdx=0 (default), faceIdx=1
    const itemData = loadTrait('trait-2-1-1');   // classIdx=1, itemIdx=1
    console.log(`Body: ${bodyData.length}B, Face: ${faceData.length}B, Item: ${itemData.length}B`);

    // Composite at 120x120
    const SIDE = 120;
    const srcCanvas = new Uint8Array(SIDE * SIDE);
    compositeLayer(srcCanvas, faceData, SIDE);
    compositeLayer(srcCanvas, bodyData, SIDE);
    compositeLayer(srcCanvas, itemData, SIDE);

    // Crop 64x64 from center (offset 28,28)
    const CROP = 64;
    const cropX = 28, cropY = 28;
    const dstCanvas = new Uint8Array(CROP * CROP);
    for (let dy = 0; dy < CROP; dy++) {
        for (let dx = 0; dx < CROP; dx++) {
            const v = srcCanvas[(cropY + dy) * SIDE + (cropX + dx)];
            dstCanvas[dy * CROP + dx] = v === 0 ? bgVal : v;
        }
    }

    // Count unique colors
    const uniqueSet = new Set();
    for (let i = 0; i < CROP * CROP; i++) uniqueSet.add(dstCanvas[i]);
    console.log(`Unique colors before quantize: ${uniqueSet.size}`);

    // Quantize to <=16
    quantizeColors(dstCanvas, palette, CROP * CROP, 16);
    const uniqueAfter = new Set();
    for (let i = 0; i < CROP * CROP; i++) uniqueAfter.add(dstCanvas[i]);
    console.log(`Unique colors after quantize: ${uniqueAfter.size}`);

    // Encode PNG (4-bit)
    const pngBytes = encodePNG4bit(dstCanvas, palette, CROP, CROP);
    console.log(`PNG size: ${pngBytes.length} bytes`);

    // Validate PNG structure
    console.log('\n=== PNG Structure Validation ===');
    let off = 0;

    // Check signature
    const sig = [137, 80, 78, 71, 13, 10, 26, 10];
    let sigOk = true;
    for (let i = 0; i < 8; i++) if (pngBytes[i] !== sig[i]) sigOk = false;
    console.log(`PNG signature: ${sigOk ? 'OK' : 'INVALID'}`);
    off = 8;

    // Parse chunks
    while (off < pngBytes.length) {
        const len = (pngBytes[off] << 24) | (pngBytes[off+1] << 16) | (pngBytes[off+2] << 8) | pngBytes[off+3];
        const type = String.fromCharCode(pngBytes[off+4], pngBytes[off+5], pngBytes[off+6], pngBytes[off+7]);
        const crcStart = off + 4;
        const crcComputed = crc32(pngBytes, crcStart, 4 + len);
        const crcStored = ((pngBytes[off+8+len] << 24) | (pngBytes[off+9+len] << 16) | (pngBytes[off+10+len] << 8) | pngBytes[off+11+len]) >>> 0;
        const crcOk = crcComputed === crcStored;
        console.log(`Chunk: ${type}  len=${len}  CRC: ${crcOk ? 'OK' : `MISMATCH computed=0x${crcComputed.toString(16)} stored=0x${crcStored.toString(16)}`}`);

        if (type === 'IHDR') {
            const w = (pngBytes[off+8] << 24) | (pngBytes[off+9] << 16) | (pngBytes[off+10] << 8) | pngBytes[off+11];
            const h = (pngBytes[off+12] << 24) | (pngBytes[off+13] << 16) | (pngBytes[off+14] << 8) | pngBytes[off+15];
            const bd = pngBytes[off+16];
            const ct = pngBytes[off+17];
            console.log(`  Width=${w} Height=${h} BitDepth=${bd} ColorType=${ct}`);
        }
        if (type === 'PLTE') {
            console.log(`  Palette entries: ${len / 3}`);
        }
        if (type === 'IDAT') {
            console.log(`  Compressed data: ${len} bytes`);
            // Verify zlib header
            console.log(`  Zlib header: 0x${pngBytes[off+8].toString(16).padStart(2,'0')} 0x${pngBytes[off+9].toString(16).padStart(2,'0')}`);
            const cmf = pngBytes[off+8], flg = pngBytes[off+9];
            console.log(`  Zlib check: (CMF*256+FLG)%31 = ${(cmf * 256 + flg) % 31} (must be 0)`);
        }
        off += 12 + len;
        if (type === 'IEND') break;
    }

    // Save PNG
    const outPath = join(ROOT, 'test-4bit-output.png');
    writeFileSync(outPath, pngBytes);
    console.log(`\nPNG saved to: ${outPath}`);

    // Try to decompress the zlib data manually
    const { inflateSync } = await import('zlib');
    // Find IDAT chunk
    off = 8;
    while (off < pngBytes.length) {
        const len = (pngBytes[off] << 24) | (pngBytes[off+1] << 16) | (pngBytes[off+2] << 8) | pngBytes[off+3];
        const type = String.fromCharCode(pngBytes[off+4], pngBytes[off+5], pngBytes[off+6], pngBytes[off+7]);
        if (type === 'IDAT') {
            const zlibData = pngBytes.slice(off + 8, off + 8 + len);
            try {
                const inflated = inflateSync(Buffer.from(zlibData));
                const expectedLen = (1 + (CROP + 1) / 2 | 0) * CROP; // Actually: (1 + ceil(64/2)) * 64 = 33 * 64 = 2112
                console.log(`\nzlib inflate: SUCCESS (${inflated.length} bytes, expected ${33 * CROP})`);
                if (inflated.length !== 33 * CROP) {
                    console.log(`  WARNING: inflated size mismatch!`);
                }
            } catch (e) {
                console.log(`\nzlib inflate: FAILED — ${e.message}`);
            }
            break;
        }
        off += 12 + len;
    }

    // Base64 encode and build data URI (like contract does)
    const b64 = Buffer.from(pngBytes).toString('base64');
    const json = JSON.stringify({ name: 'King #368', image: `data:image/png;base64,${b64}` });
    const urlJson = json.replace(/%/g,'%25').replace(/"/g,'%22').replace(/\{/g,'%7B').replace(/\}/g,'%7D').replace(/#/g,'%23').replace(/ /g,'%20');
    const dataUri = `data:application/json,${urlJson}`;

    console.log(`\nBase64 PNG: ${b64.length} chars`);
    console.log(`JSON: ${json.length} chars`);
    console.log(`URL-encoded: ${urlJson.length} chars`);
    console.log(`Data URI: ${dataUri.length} chars`);
    console.log(`BytesWriter total: ${4 + dataUri.length} bytes (limit: 2048)`);
    console.log(`Fits in 2048: ${4 + dataUri.length <= 2048 ? 'YES' : `NO — exceeds by ${4 + dataUri.length - 2048}`}`);

    // Save test HTML
    const html = `<!DOCTYPE html>
<html><head><title>4-bit PNG Test</title>
<style>body{background:#0a0a0a;color:#e0e0e0;font-family:monospace;padding:20px}
img{image-rendering:pixelated;border:1px solid #333}</style></head>
<body><h2>4-bit PNG Encoding Test</h2>
<p>If images below render, the encoding algorithm is correct.</p>
<div style="display:flex;gap:20px">
<div><p>64x64 (native)</p><img src="data:image/png;base64,${b64}" width="64" height="64"
  onerror="this.alt='BROKEN';this.parentElement.querySelector('span').textContent='BROKEN – onerror fired'">
<br><span style="color:#4caf50">OK</span></div>
<div><p>256x256 (scaled)</p><img src="data:image/png;base64,${b64}" width="256" height="256"
  onerror="this.alt='BROKEN';this.parentElement.querySelector('span').textContent='BROKEN – onerror fired'">
<br><span style="color:#4caf50">OK</span></div>
</div>
<h3>Data URI</h3>
<textarea style="width:100%;height:100px;background:#111;color:#4caf50;border:1px solid #333" readonly>${dataUri.slice(0,2000)}...</textarea>
</body></html>`;
    writeFileSync(join(ROOT, 'test-4bit-result.html'), html);
    console.log(`\nTest HTML saved to: test-4bit-result.html`);
    console.log('Open it in a browser to verify PNG rendering.');
}

main().catch(e => { console.error(e); process.exit(1); });
