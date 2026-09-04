#!/usr/bin/env node
/**
 * test-png-4bit.mjs — Test 4-bit (16-color) PNG encoding for ALL classes.
 *
 * 4-bit PNG halves the raw pixel data size. With color quantization
 * (merge closest colors to ≤16), this should dramatically reduce PNG size.
 *
 * Also tests various crop sizes with 8-bit encoding for comparison.
 */

import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { deflateRawSync, constants as zlibConstants } from 'zlib';

const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');
const CANVAS_SIDE = 120;
const RECEIPT_LIMIT = 2048;

const CLASS_NAMES = ['Wizard', 'King', 'Knight', 'Apprentice', 'Peasant', 'Gnome', 'Elf'];

function faceClassIdx(ci) { return ci === 5 ? 5 : ci === 6 ? 6 : 0; }

// Read palette
const palBin = readFileSync(join(TRAITS_DIR, 'palette.bin'));
const palCount = palBin.readUInt16BE(0);
const palRGB = new Uint8Array(palCount * 3);
for (let i = 0; i < palCount * 3; i++) palRGB[i] = palBin[2 + i];

// Read traits
const traits = {};
for (const f of readdirSync(TRAITS_DIR).filter(f => f.startsWith('trait-') && f.endsWith('.bin'))) {
    const d = readFileSync(join(TRAITS_DIR, f));
    const [lt, ci, li] = [d[0], d[1], d[2]];
    if (!traits[lt]) traits[lt] = {};
    if (!traits[lt][ci]) traits[lt][ci] = {};
    traits[lt][ci][li] = d;
}

function compositeLayer(canvas, ld, cs) {
    if (!ld || ld.length < 10) return;
    const [, , , mx, my, bw, bh, lps] = ld;
    if (!lps || !bw || !bh) return;
    const ps = 8, pds = ps + lps;
    if (pds >= ld.length) return;
    for (let p = 0; p < bw * bh; p++) {
        const bo = pds + (p >> 1);
        if (bo >= ld.length) break;
        const nb = ((p & 1) === 0) ? (ld[bo] >> 4) & 0xF : ld[bo] & 0xF;
        if (nb === 0) continue;
        const li = nb - 1;
        if (li >= lps) continue;
        const gi = ld[ps + li];
        const ax = mx + (p % bw), ay = my + Math.floor(p / bw);
        if (ax < cs && ay < cs) canvas[ay * cs + ax] = gi + 1;
    }
}

function pngPredict(f, a, b, c) {
    if (f <= 0) return 0;
    if (f === 1) return a;
    if (f === 2) return b;
    if (f === 3) return (a + b) >> 1;
    const p = a + b - c;
    if (Math.abs(p - a) <= Math.abs(p - b) && Math.abs(p - a) <= Math.abs(p - c)) return a;
    if (Math.abs(p - b) <= Math.abs(p - c)) return b;
    return c;
}

function adler32(d) {
    let a = 1, b = 0;
    for (let i = 0; i < d.length; i++) { a = (a + d[i]) % 65521; b = (b + a) % 65521; }
    return ((b << 16) | a) >>> 0;
}

function crc32(buf) {
    const T = new Uint32Array(256);
    for (let i = 0; i < 256; i++) {
        let c = i;
        for (let j = 0; j < 8; j++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        T[i] = c;
    }
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < buf.length; i++) crc = T[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
}

function writeChunk(png, off, type, data) {
    png.writeUInt32BE(data.length, off); off += 4;
    png.write(type, off, 4, 'ascii'); off += 4;
    data.copy(png, off); off += data.length;
    const crcData = png.subarray(off - data.length - 4, off);
    png.writeUInt32BE(crc32(crcData), off); off += 4;
    return off;
}

// ── Color quantization: merge closest colors until ≤ maxColors ───────────────
function quantizeColors(canvas, palette, width, height, maxColors) {
    // Find unique colors in canvas (canvas values 1-255 → palette index i-1)
    const colorSet = new Set();
    for (let i = 0; i < width * height; i++) {
        colorSet.add(canvas[i]);
    }
    const uniqueValues = Array.from(colorSet).sort((a, b) => a - b);

    if (uniqueValues.length <= maxColors) {
        return { canvas: canvas.slice(), palette, remapped: false, uniqueColors: uniqueValues.length };
    }

    // Build RGB array for each unique canvas value
    const colors = uniqueValues.map(v => {
        if (v === 0) return { v, r: 0, g: 0, b: 0 };
        const palOff = (v - 1) * 3;
        if (palOff + 2 < palette.length) {
            return { v, r: palette[palOff], g: palette[palOff + 1], b: palette[palOff + 2] };
        }
        return { v, r: 0, g: 0, b: 0 };
    });

    // Merge closest pairs until ≤ maxColors
    while (colors.length > maxColors) {
        let minDist = Infinity, mi = -1, mj = -1;
        for (let i = 0; i < colors.length; i++) {
            for (let j = i + 1; j < colors.length; j++) {
                const dr = colors[i].r - colors[j].r;
                const dg = colors[i].g - colors[j].g;
                const db = colors[i].b - colors[j].b;
                const dist = dr * dr + dg * dg + db * db;
                if (dist < minDist) {
                    minDist = dist;
                    mi = i;
                    mj = j;
                }
            }
        }
        // Merge mj into mi (keep mi's canvas value, remap mj's)
        const mergedV = colors[mi].v;
        const removedV = colors[mj].v;
        // Average the colors
        colors[mi].r = Math.round((colors[mi].r + colors[mj].r) / 2);
        colors[mi].g = Math.round((colors[mi].g + colors[mj].g) / 2);
        colors[mi].b = Math.round((colors[mi].b + colors[mj].b) / 2);
        colors.splice(mj, 1);

        // Remap canvas pixels
        for (let i = 0; i < width * height; i++) {
            if (canvas[i] === removedV) canvas[i] = mergedV;
        }
    }

    return { canvas, palette, remapped: true, uniqueColors: colors.length };
}

// ── Encode 4-bit PNG ─────────────────────────────────────────────────────────
function encode4bitPNG(canvas, palette, width, height) {
    // Scan for unique values
    const used = new Uint8Array(256);
    for (let i = 0; i < width * height; i++) used[canvas[i]] = 1;

    const globalToLocal = new Uint8Array(256);
    const localR = new Uint8Array(16);
    const localG = new Uint8Array(16);
    const localB = new Uint8Array(16);
    let localCount = 0;

    for (let i = 0; i < 256; i++) {
        if (used[i] === 0) continue;
        if (localCount >= 16) break; // 4-bit max
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

    // 4-bit row: 1 filter byte + ceil(width/2) data bytes
    const dataWidth = Math.ceil(width / 2);
    const filteredRowLen = 1 + dataWidth;
    const filtered = Buffer.alloc(filteredRowLen * height);
    const prevRow = new Uint8Array(dataWidth);
    const curRow = new Uint8Array(dataWidth);

    for (let y = 0; y < height; y++) {
        const rowStart = y * filteredRowLen;

        // Pack pixels into 4-bit nibbles (high nibble first)
        for (let x = 0; x < dataWidth; x++) {
            const px0 = x * 2 < width ? globalToLocal[canvas[y * width + x * 2]] : 0;
            const px1 = x * 2 + 1 < width ? globalToLocal[canvas[y * width + x * 2 + 1]] : 0;
            curRow[x] = (px0 << 4) | px1;
        }

        // Adaptive filter on packed bytes
        let bestFilter = 0, bestSum = Infinity;
        for (let f = 0; f <= 4; f++) {
            let sum = 0;
            for (let x = 0; x < dataWidth; x++) {
                const raw = curRow[x];
                const a = x > 0 ? curRow[x - 1] : 0;
                const b = prevRow[x];
                const c = x > 0 ? prevRow[x - 1] : 0;
                const pred = pngPredict(f, a, b, c);
                const v = (raw - pred) & 0xFF;
                sum += v < 128 ? v : 256 - v;
            }
            if (sum < bestSum) { bestSum = sum; bestFilter = f; }
        }

        filtered[rowStart] = bestFilter;
        for (let x = 0; x < dataWidth; x++) {
            const raw = curRow[x];
            const a = x > 0 ? curRow[x - 1] : 0;
            const b = prevRow[x];
            const c = x > 0 ? prevRow[x - 1] : 0;
            filtered[rowStart + 1 + x] = (raw - pngPredict(bestFilter, a, b, c)) & 0xFF;
        }
        curRow.forEach((v, i) => { prevRow[i] = v; });
    }

    // DEFLATE
    const deflated = deflateRawSync(filtered, { level: 6, strategy: zlibConstants.Z_FIXED });
    const adler = adler32(filtered);
    const zlibLen = 2 + deflated.length + 4;
    const zlibBuf = Buffer.alloc(zlibLen);
    zlibBuf[0] = 0x78; zlibBuf[1] = 0x01;
    deflated.copy(zlibBuf, 2);
    zlibBuf.writeUInt32BE(adler, 2 + deflated.length);

    // Assemble PNG
    const pngSize = 8 + 25 + (12 + paletteSize * 3) + (12 + zlibLen) + 12;
    const png = Buffer.alloc(pngSize);
    let off = 0;

    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(png, off); off += 8;

    // IHDR with bit depth = 4
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(width, 0);
    ihdr.writeUInt32BE(height, 4);
    ihdr[8] = 4; // bit depth = 4 (16 colors)
    ihdr[9] = 3; // indexed
    off = writeChunk(png, off, 'IHDR', ihdr);

    const plte = Buffer.alloc(paletteSize * 3);
    for (let i = 0; i < paletteSize; i++) {
        plte[i * 3] = localR[i];
        plte[i * 3 + 1] = localG[i];
        plte[i * 3 + 2] = localB[i];
    }
    off = writeChunk(png, off, 'PLTE', plte);
    off = writeChunk(png, off, 'IDAT', zlibBuf);
    off = writeChunk(png, off, 'IEND', Buffer.alloc(0));

    return { png: png.subarray(0, off), localColors: paletteSize };
}

// ── 8-bit PNG encoder (same as before) ───────────────────────────────────────
function encode8bitPNG(canvas, palette, width, height) {
    const used = new Uint8Array(256);
    for (let i = 0; i < width * height; i++) used[canvas[i]] = 1;

    const g2l = new Uint8Array(256);
    const lr = new Uint8Array(256), lg = new Uint8Array(256), lb = new Uint8Array(256);
    let lc = 0;
    for (let i = 0; i < 256; i++) {
        if (!used[i]) continue;
        g2l[i] = lc;
        const po = i === 0 ? -1 : (i - 1) * 3;
        if (po >= 0 && po + 2 < palette.length) { lr[lc] = palette[po]; lg[lc] = palette[po + 1]; lb[lc] = palette[po + 2]; }
        lc++;
    }

    const frl = 1 + width;
    const filt = Buffer.alloc(frl * height);
    const prev = new Uint8Array(width), cur = new Uint8Array(width);

    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) cur[x] = g2l[canvas[y * width + x]];
        let bf = 0, bs = Infinity;
        for (let f = 0; f <= 4; f++) {
            let s = 0;
            for (let x = 0; x < width; x++) {
                const v = (cur[x] - pngPredict(f, x > 0 ? cur[x-1] : 0, prev[x], x > 0 ? prev[x-1] : 0)) & 0xFF;
                s += v < 128 ? v : 256 - v;
            }
            if (s < bs) { bs = s; bf = f; }
        }
        filt[y * frl] = bf;
        for (let x = 0; x < width; x++)
            filt[y * frl + 1 + x] = (cur[x] - pngPredict(bf, x > 0 ? cur[x-1] : 0, prev[x], x > 0 ? prev[x-1] : 0)) & 0xFF;
        cur.forEach((v, i) => { prev[i] = v; });
    }

    const defl = deflateRawSync(filt, { level: 6, strategy: zlibConstants.Z_FIXED });
    const adl = adler32(filt);
    const zl = 2 + defl.length + 4;
    const zb = Buffer.alloc(zl);
    zb[0] = 0x78; zb[1] = 0x01;
    defl.copy(zb, 2);
    zb.writeUInt32BE(adl, 2 + defl.length);

    const ps = 8 + 25 + (12 + lc * 3) + (12 + zl) + 12;
    const png = Buffer.alloc(ps);
    let off = 0;
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(png, off); off += 8;
    const ih = Buffer.alloc(13); ih.writeUInt32BE(width, 0); ih.writeUInt32BE(height, 4); ih[8] = 8; ih[9] = 3;
    off = writeChunk(png, off, 'IHDR', ih);
    const pl = Buffer.alloc(lc * 3);
    for (let i = 0; i < lc; i++) { pl[i*3] = lr[i]; pl[i*3+1] = lg[i]; pl[i*3+2] = lb[i]; }
    off = writeChunk(png, off, 'PLTE', pl);
    off = writeChunk(png, off, 'IDAT', zb);
    off = writeChunk(png, off, 'IEND', Buffer.alloc(0));
    return { png: png.subarray(0, off), localColors: lc };
}

function buildDataUri(cn, tid, pngBytes) {
    const b64 = pngBytes.toString('base64');
    const json = `{"name":"${cn} #${tid}","image":"data:image/png;base64,${b64}"}`;
    let uj = '';
    for (let i = 0; i < json.length; i++) {
        const c = json.charCodeAt(i);
        if (c === 0x22) uj += '%22';
        else if (c === 0x7B) uj += '%7B';
        else if (c === 0x7D) uj += '%7D';
        else if (c === 0x23) uj += '%23';
        else if (c === 0x20) uj += '%20';
        else uj += json[i];
    }
    return 4 + ('data:application/json,' + uj).length;
}

// ── Main ─────────────────────────────────────────────────────────────────────
const bgR = 0xF7, bgG = 0x93, bgB = 0x1A;
let bgVal = 0;
for (let i = 0; i < palCount; i++) {
    if (palRGB[i*3] === bgR && palRGB[i*3+1] === bgG && palRGB[i*3+2] === bgB) { bgVal = i + 1; break; }
}
let usePal = palRGB;
if (bgVal === 0) {
    usePal = new Uint8Array(palRGB.length + 3);
    usePal.set(palRGB);
    usePal[palRGB.length] = bgR; usePal[palRGB.length + 1] = bgG; usePal[palRGB.length + 2] = bgB;
    bgVal = Math.floor(palRGB.length / 3) + 1;
}

// Build worst-case canvases for each class
function buildWorstCanvas(classIdx) {
    const fci = faceClassIdx(classIdx);
    const bodies = traits[0]?.[classIdx] || {};
    const faces = traits[1]?.[fci] || {};
    const items = traits[2]?.[classIdx] || {};
    const subs = traits[3]?.[classIdx === 4 ? 4 : 0] || {};

    let worstReceipt = 0, worstCanvas = null, worstCombo = '';

    for (const bi of Object.keys(bodies)) {
        for (const fi of Object.keys(faces)) {
            for (const ii of Object.keys(items)) {
                const canvas = new Uint8Array(CANVAS_SIDE * CANVAS_SIDE);
                compositeLayer(canvas, faces[fi], CANVAS_SIDE);
                compositeLayer(canvas, bodies[bi], CANVAS_SIDE);
                compositeLayer(canvas, items[ii], CANVAS_SIDE);
                const subKeys = Object.keys(subs);
                if (subKeys.length > 0) compositeLayer(canvas, subs[subKeys[0]], CANVAS_SIDE);

                // Quick 8-bit encode at 66 to find worst
                const crop = new Uint8Array(66 * 66);
                for (let dy = 0; dy < 66; dy++)
                    for (let dx = 0; dx < 66; dx++) {
                        const v = canvas[(27 + dy) * CANVAS_SIDE + (27 + dx)];
                        crop[dy * 66 + dx] = v === 0 ? bgVal : v;
                    }
                const { png } = encode8bitPNG(crop, usePal, 66, 66);
                const receipt = buildDataUri(CLASS_NAMES[classIdx], 777, png);
                if (receipt > worstReceipt) {
                    worstReceipt = receipt;
                    worstCanvas = canvas;
                    worstCombo = `body=${bi} face=${fi} item=${ii}`;
                }
            }
        }
    }
    return { canvas: worstCanvas, combo: worstCombo, receipt8bit66: worstReceipt };
}

console.log('╔═══════════════════════════════════════════════════════════════════════╗');
console.log('║  4-bit PNG + Quantization Test — Worst-Case Per Class                ║');
console.log('╚═══════════════════════════════════════════════════════════════════════╝\n');

console.log('Finding worst-case combo per class...\n');

const cropSizes = [66, 64, 60, 56, 52, 48];

console.log('Class       ', cropSizes.map(s => `  ${s}×${s} 8b`).join(''), cropSizes.map(s => `  ${s}×${s} 4b`).join(''));
console.log('─'.repeat(12 + cropSizes.length * 20));

for (let ci = 0; ci < CLASS_NAMES.length; ci++) {
    const { canvas, combo } = buildWorstCanvas(ci);
    if (!canvas) { console.log(`${CLASS_NAMES[ci].padEnd(12)} NO TRAITS`); continue; }

    const row = [CLASS_NAMES[ci].padEnd(12)];

    // Test 8-bit at each crop size
    for (const cs of cropSizes) {
        const cx = Math.floor((120 - cs) / 2);
        const crop = new Uint8Array(cs * cs);
        for (let dy = 0; dy < cs; dy++)
            for (let dx = 0; dx < cs; dx++) {
                const v = canvas[(cx + dy) * CANVAS_SIDE + (cx + dx)];
                crop[dy * cs + dx] = v === 0 ? bgVal : v;
            }
        const { png } = encode8bitPNG(crop, usePal, cs, cs);
        const receipt = buildDataUri(CLASS_NAMES[ci], 777, png);
        const ok = receipt <= RECEIPT_LIMIT;
        row.push(` ${ok ? ' ' : '!'}${String(receipt).padStart(5)}`);
    }

    // Test 4-bit with quantization at each crop size
    for (const cs of cropSizes) {
        const cx = Math.floor((120 - cs) / 2);
        const crop = new Uint8Array(cs * cs);
        for (let dy = 0; dy < cs; dy++)
            for (let dx = 0; dx < cs; dx++) {
                const v = canvas[(cx + dy) * CANVAS_SIDE + (cx + dx)];
                crop[dy * cs + dx] = v === 0 ? bgVal : v;
            }

        // Quantize to 16 colors
        const q = quantizeColors(crop, usePal, cs, cs, 16);
        const { png } = encode4bitPNG(q.canvas, usePal, cs, cs);
        const receipt = buildDataUri(CLASS_NAMES[ci], 777, png);
        const ok = receipt <= RECEIPT_LIMIT;
        row.push(` ${ok ? ' ' : '!'}${String(receipt).padStart(5)}`);
    }

    console.log(row.join(''));
}

console.log('\n! = exceeds 2048-byte limit\n');

// Also test the simplest approach: 8-bit with quantization to 16 colors (no 4-bit packing)
console.log('── 8-bit with 16-color quantization (no 4-bit packing) ──\n');
console.log('Class       ', cropSizes.map(s => `  ${s}×${s}`).join(''));
console.log('─'.repeat(12 + cropSizes.length * 8));

for (let ci = 0; ci < CLASS_NAMES.length; ci++) {
    const { canvas } = buildWorstCanvas(ci);
    if (!canvas) continue;

    const row = [CLASS_NAMES[ci].padEnd(12)];
    for (const cs of cropSizes) {
        const cx = Math.floor((120 - cs) / 2);
        const crop = new Uint8Array(cs * cs);
        for (let dy = 0; dy < cs; dy++)
            for (let dx = 0; dx < cs; dx++) {
                const v = canvas[(cx + dy) * CANVAS_SIDE + (cx + dx)];
                crop[dy * cs + dx] = v === 0 ? bgVal : v;
            }
        quantizeColors(crop, usePal, cs, cs, 16); // mutates crop
        const { png } = encode8bitPNG(crop, usePal, cs, cs);
        const receipt = buildDataUri(CLASS_NAMES[ci], 777, png);
        const ok = receipt <= RECEIPT_LIMIT;
        row.push(` ${ok ? ' ' : '!'}${String(receipt).padStart(5)}`);
    }
    console.log(row.join(''));
}
console.log('\n! = exceeds 2048-byte limit');
