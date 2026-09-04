#!/usr/bin/env node
/**
 * elf-analysis.mjs — Analyze Elf color complexity and identify which combos fail at 64x64.
 * Also check if the stale trait-0-6-3.bin is the culprit.
 */
import { readFileSync, readdirSync, writeFileSync } from 'fs';
import { join } from 'path';
import { deflateRawSync, constants as zlibConstants } from 'zlib';

const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');
const CS = 64, CX = 28, LIMIT = 2048;

const pb = readFileSync(join(TRAITS_DIR, 'palette.bin'));
const pc = pb.readUInt16BE(0);
const pr = new Uint8Array(pc * 3);
for (let i = 0; i < pc * 3; i++) pr[i] = pb[2 + i];

const traits = {};
for (const f of readdirSync(TRAITS_DIR).filter(f => f.startsWith('trait-') && f.endsWith('.bin'))) {
    const d = readFileSync(join(TRAITS_DIR, f));
    if (!traits[d[0]]) traits[d[0]] = {};
    if (!traits[d[0]][d[1]]) traits[d[0]][d[1]] = {};
    traits[d[0]][d[1]][d[2]] = d;
}

function comp(c, ld, cs) {
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
        const ax = mx + (p % bw), ay = my + Math.floor(p / bw);
        if (ax < cs && ay < cs) c[ay * cs + ax] = ld[ps + li] + 1;
    }
}
function pngP(f, a, b, c) { if (f <= 0) return 0; if (f === 1) return a; if (f === 2) return b; if (f === 3) return (a + b) >> 1; const p = a + b - c; if (Math.abs(p - a) <= Math.abs(p - b) && Math.abs(p - a) <= Math.abs(p - c)) return a; if (Math.abs(p - b) <= Math.abs(p - c)) return b; return c; }
function adler32(d) { let a = 1, b = 0; for (let i = 0; i < d.length; i++) { a = (a + d[i]) % 65521; b = (b + a) % 65521; } return ((b << 16) | a) >>> 0; }
function crc32(buf) { const T = new Uint32Array(256); for (let i = 0; i < 256; i++) { let c = i; for (let j = 0; j < 8; j++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1); T[i] = c; } let crc = 0xFFFFFFFF; for (let i = 0; i < buf.length; i++) crc = T[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8); return (crc ^ 0xFFFFFFFF) >>> 0; }
function wc(png, off, type, data) { png.writeUInt32BE(data.length, off); off += 4; png.write(type, off, 4, 'ascii'); off += 4; data.copy(png, off); off += data.length; png.writeUInt32BE(crc32(png.subarray(off - data.length - 4, off)), off); off += 4; return off; }

function quantize(canvas, palette, w, h, maxC) {
    const cs = new Set(); for (let i = 0; i < w * h; i++) cs.add(canvas[i]); const uv = Array.from(cs);
    if (uv.length <= maxC) return uv.length;
    const colors = uv.map(v => { if (v === 0) return { v, r: 0, g: 0, b: 0 }; const po = (v - 1) * 3; return po + 2 < palette.length ? { v, r: palette[po], g: palette[po + 1], b: palette[po + 2] } : { v, r: 0, g: 0, b: 0 }; });
    while (colors.length > maxC) { let md = Infinity, mi = -1, mj = -1; for (let i = 0; i < colors.length; i++) for (let j = i + 1; j < colors.length; j++) { const d = (colors[i].r - colors[j].r) ** 2 + (colors[i].g - colors[j].g) ** 2 + (colors[i].b - colors[j].b) ** 2; if (d < md) { md = d; mi = i; mj = j; } }
    const rv = colors[mj].v, kv = colors[mi].v; colors[mi].r = Math.round((colors[mi].r + colors[mj].r) / 2); colors[mi].g = Math.round((colors[mi].g + colors[mj].g) / 2); colors[mi].b = Math.round((colors[mi].b + colors[mj].b) / 2); colors.splice(mj, 1); for (let i = 0; i < w * h; i++) if (canvas[i] === rv) canvas[i] = kv; }
    return colors.length;
}

function enc4(canvas, palette, w, h) {
    const used = new Uint8Array(256); for (let i = 0; i < w * h; i++) used[canvas[i]] = 1;
    const g2l = new Uint8Array(256); const lr = new Uint8Array(16), lg = new Uint8Array(16), lb = new Uint8Array(16); let lc = 0;
    for (let i = 0; i < 256; i++) { if (!used[i]) continue; if (lc >= 16) break; g2l[i] = lc; const po = i === 0 ? -1 : (i - 1) * 3; if (po >= 0 && po + 2 < palette.length) { lr[lc] = palette[po]; lg[lc] = palette[po + 1]; lb[lc] = palette[po + 2]; } lc++; }
    const dw = Math.ceil(w / 2), frl = 1 + dw; const filt = Buffer.alloc(frl * h); const prev = new Uint8Array(dw), cur = new Uint8Array(dw);
    for (let y = 0; y < h; y++) { for (let x = 0; x < dw; x++) { const p0 = x * 2 < w ? g2l[canvas[y * w + x * 2]] : 0; const p1 = x * 2 + 1 < w ? g2l[canvas[y * w + x * 2 + 1]] : 0; cur[x] = (p0 << 4) | p1; }
    let bf = 0, bs = Infinity; for (let f = 0; f <= 4; f++) { let s = 0; for (let x = 0; x < dw; x++) { const v = (cur[x] - pngP(f, x > 0 ? cur[x - 1] : 0, prev[x], x > 0 ? prev[x - 1] : 0)) & 0xFF; s += v < 128 ? v : 256 - v; } if (s < bs) { bs = s; bf = f; } }
    filt[y * frl] = bf; for (let x = 0; x < dw; x++) filt[y * frl + 1 + x] = (cur[x] - pngP(bf, x > 0 ? cur[x - 1] : 0, prev[x], x > 0 ? prev[x - 1] : 0)) & 0xFF; cur.forEach((v, i) => { prev[i] = v; }); }
    const defl = deflateRawSync(filt, { level: 6, strategy: zlibConstants.Z_FIXED }); const adl = adler32(filt); const zl = 2 + defl.length + 4; const zb = Buffer.alloc(zl); zb[0] = 0x78; zb[1] = 0x01; defl.copy(zb, 2); zb.writeUInt32BE(adl, 2 + defl.length);
    const ps = 8 + 25 + (12 + lc * 3) + (12 + zl) + 12; const png = Buffer.alloc(ps); let off = 0; Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(png, off); off += 8;
    const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 4; ih[9] = 3; off = wc(png, off, 'IHDR', ih);
    const pl = Buffer.alloc(lc * 3); for (let i = 0; i < lc; i++) { pl[i * 3] = lr[i]; pl[i * 3 + 1] = lg[i]; pl[i * 3 + 2] = lb[i]; } off = wc(png, off, 'PLTE', pl);
    off = wc(png, off, 'IDAT', zb); off = wc(png, off, 'IEND', Buffer.alloc(0)); return png.subarray(0, off);
}

function receipt(cn, buf) { const b64 = buf.toString('base64'); const json = `{"name":"${cn} #777","image":"data:image/png;base64,${b64}"}`; let uj = ''; for (let i = 0; i < json.length; i++) { const c = json.charCodeAt(i); if (c === 0x22) uj += '%22'; else if (c === 0x7B) uj += '%7B'; else if (c === 0x7D) uj += '%7D'; else if (c === 0x23) uj += '%23'; else if (c === 0x20) uj += '%20'; else uj += json[i]; } return 4 + ('data:application/json,' + uj).length; }

const bgR = 0xF7, bgG = 0x93, bgB = 0x1A; let bgVal = 0;
for (let i = 0; i < pc; i++) { if (pr[i * 3] === bgR && pr[i * 3 + 1] === bgG && pr[i * 3 + 2] === bgB) { bgVal = i + 1; break; } }
let usePal = pr; if (bgVal === 0) { usePal = new Uint8Array(pr.length + 3); usePal.set(pr); usePal[pr.length] = bgR; usePal[pr.length + 1] = bgG; usePal[pr.length + 2] = bgB; bgVal = Math.floor(pr.length / 3) + 1; }

// ── 1. Analyze Elf layer color complexity ──
console.log('=== Elf Layer Color Analysis ===\n');

const bodies = traits[0]?.[6] || {};
const faces = traits[1]?.[6] || {};
const items = traits[2]?.[6] || {};

function analyzeLayer(label, layerData) {
    if (!layerData || layerData.length < 10) return { label, colors: [] };
    const [lt, ci, li, mx, my, bw, bh, lps] = layerData;
    const colors = [];
    for (let i = 0; i < lps; i++) {
        const gIdx = layerData[8 + i];
        const r = pr[gIdx * 3], g = pr[gIdx * 3 + 1], b = pr[gIdx * 3 + 2];
        colors.push({ gIdx, r, g, b, hex: `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}` });
    }
    console.log(`  ${label}: ${bw}x${bh} at (${mx},${my}), ${lps} local colors`);
    for (const c of colors) {
        console.log(`    gIdx=${c.gIdx.toString().padStart(3)} ${c.hex}`);
    }
    // Find close pairs
    for (let i = 0; i < colors.length; i++) {
        for (let j = i + 1; j < colors.length; j++) {
            const d = Math.sqrt((colors[i].r - colors[j].r) ** 2 + (colors[i].g - colors[j].g) ** 2 + (colors[i].b - colors[j].b) ** 2);
            if (d < 30) {
                console.log(`    ⚠ CLOSE: ${colors[i].hex} ↔ ${colors[j].hex} dist=${d.toFixed(1)}`);
            }
        }
    }
    return { label, colors, bw, bh };
}

console.log('Bodies:');
for (const bi of Object.keys(bodies).sort()) {
    analyzeLayer(`body-${bi} (trait-0-6-${bi}.bin)`, bodies[bi]);
}

console.log('\nFaces:');
for (const fi of Object.keys(faces).sort()) {
    analyzeLayer(`face-${fi} (trait-1-6-${fi}.bin)`, faces[fi]);
}

console.log('\nItems:');
for (const ii of Object.keys(items).sort()) {
    analyzeLayer(`item-${ii} (trait-2-6-${ii}.bin)`, items[ii]);
}

// ── 2. Test ALL Elf combos at 64x64 with 16 colors ──
console.log('\n\n=== Elf Combos at 64x64 / 16 colors ===\n');

const FACE_LABELS = ['Classic','Happy','Angry','Feels Bad','Grinding','Chill','Grumpy','Giga Happy','Cooked','Comfy','Retard','Laser'];
const results = [];

for (const bi of Object.keys(bodies).sort()) {
    for (const fi of Object.keys(faces).sort()) {
        for (const ii of Object.keys(items).sort()) {
            const c = new Uint8Array(120 * 120);
            comp(c, faces[fi], 120);
            comp(c, bodies[bi], 120);
            comp(c, items[ii], 120);

            // Count unique colors before crop
            const uniquePre = new Set();
            for (let i = 0; i < 120 * 120; i++) if (c[i] !== 0) uniquePre.add(c[i]);

            const crop = new Uint8Array(CS * CS);
            for (let dy = 0; dy < CS; dy++) for (let dx = 0; dx < CS; dx++) {
                const v = c[(CX + dy) * 120 + (CX + dx)];
                crop[dy * CS + dx] = v === 0 ? bgVal : v;
            }

            const uniquePost = new Set();
            for (let i = 0; i < CS * CS; i++) uniquePost.add(crop[i]);

            quantize(crop, usePal, CS, CS, 16);
            const png = enc4(crop, usePal, CS, CS);
            const r = receipt('Elf', png);
            const ok = r <= LIMIT;

            results.push({ bi: +bi, fi: +fi, ii: +ii, receipt: r, ok, uniquePre: uniquePre.size, uniquePost: uniquePost.size });

            if (!ok) {
                console.log(`  FAIL: b${bi} f${fi}(${FACE_LABELS[fi] || fi}) i${ii} → ${r} bytes (margin ${LIMIT - r}), pre=${uniquePre.size} post=${uniquePost.size} unique colors`);
            }
        }
    }
}

const fails = results.filter(r => !r.ok);
const passes = results.filter(r => r.ok);
console.log(`\nTotal: ${results.length} combos, ${fails.length} fails, ${passes.length} pass`);
console.log(`Worst: ${Math.max(...results.map(r => r.receipt))} bytes`);

// ── 3. Check: without stale body 3, what happens? ──
console.log('\n\n=== Without stale body 3 (deleted elf-01.svg) ===');
const validResults = results.filter(r => r.bi <= 2);
const validFails = validResults.filter(r => !r.ok);
console.log(`Valid combos (body 0-2 only): ${validResults.length}, fails: ${validFails.length}`);
if (validFails.length > 0) {
    console.log('Still failing:');
    for (const f of validFails) {
        console.log(`  b${f.bi} f${f.fi}(${FACE_LABELS[f.fi] || f.fi}) i${f.ii} → ${f.receipt} bytes, ${f.uniquePost} colors`);
    }
} else {
    console.log('ALL VALID COMBOS PASS! The stale body 3 was the only problem.');
}

// ── 4. Show worst valid combos ──
console.log('\n=== Top 10 worst VALID combos (body 0-2) ===');
validResults.sort((a, b) => b.receipt - a.receipt);
for (let i = 0; i < Math.min(10, validResults.length); i++) {
    const r = validResults[i];
    console.log(`  b${r.bi} f${r.fi}(${FACE_LABELS[r.fi] || r.fi}) i${r.ii} → ${r.receipt} bytes (margin +${LIMIT - r.receipt}), ${r.uniquePost} colors`);
}
