#!/usr/bin/env node
/**
 * wizard-analysis.mjs — Analyze Wizard layer colors, especially bodies 2,4 and items 0,4
 * which cause the 16 failing combos at 64x64.
 */
import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';

const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');
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

function analyzeLayer(label, layerData) {
    if (!layerData || layerData.length < 10) return;
    const [lt, ci, li, mx, my, bw, bh, lps] = layerData;
    const colors = [];
    for (let i = 0; i < lps; i++) {
        const gIdx = layerData[8 + i];
        const r = pr[gIdx * 3], g = pr[gIdx * 3 + 1], b = pr[gIdx * 3 + 2];
        colors.push({ gIdx, r, g, b, hex: `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}` });
    }
    console.log(`  ${label}: ${bw}x${bh} at (${mx},${my}), ${lps} local colors, ${layerData.length} bytes`);
    for (const c of colors) {
        console.log(`    gIdx=${c.gIdx.toString().padStart(3)} ${c.hex}`);
    }
    const closePairs = [];
    for (let i = 0; i < colors.length; i++) {
        for (let j = i + 1; j < colors.length; j++) {
            const d = Math.sqrt((colors[i].r - colors[j].r) ** 2 + (colors[i].g - colors[j].g) ** 2 + (colors[i].b - colors[j].b) ** 2);
            if (d < 40) {
                closePairs.push({ a: colors[i], b: colors[j], dist: d });
            }
        }
    }
    if (closePairs.length > 0) {
        console.log(`    Close pairs (<40 dist):`);
        closePairs.sort((a, b) => a.dist - b.dist);
        for (const p of closePairs) {
            console.log(`      ${p.a.hex} ↔ ${p.b.hex}  dist=${p.dist.toFixed(1)}`);
        }
    }
    return { label, colors, closePairs };
}

const BODY_LABELS = ['Wizard I','Wizard II','Wizard III','Wizard IV','Wizard V','Wizard VI','Wizard Manifest','Wizard BTC'];
const ITEM_LABELS = ['Staff I','Staff II','Staff III','Staff IV','Staff Manifest'];

console.log('=== Wizard Bodies (failing: body 2 = wizard-03, body 4 = wizard-05) ===\n');
const wizBodies = traits[0]?.[0] || {};
for (const bi of Object.keys(wizBodies).sort((a,b)=>a-b)) {
    const star = (bi == 2 || bi == 4) ? ' ★ FAILING' : '';
    analyzeLayer(`Body ${bi} (${BODY_LABELS[bi]})${star}`, wizBodies[bi]);
    console.log('');
}

console.log('\n=== Wizard Items (failing: item 0 = Staff I, item 4 = Staff Manifest) ===\n');
const wizItems = traits[2]?.[0] || {};
for (const ii of Object.keys(wizItems).sort((a,b)=>a-b)) {
    const star = (ii == 0 || ii == 4) ? ' ★ FAILING' : '';
    analyzeLayer(`Item ${ii} (${ITEM_LABELS[ii]})${star}`, wizItems[ii]);
    console.log('');
}

console.log('\n=== Wizard Faces (faces 2,3,4 appear most in fails) ===\n');
const wizFaces = traits[1]?.[0] || {};
const FACE_LABELS = ['Classic','Happy','Angry','Feels Bad','Grinding','Chill','Grumpy','Giga Happy','Cooked','Comfy','Retard','Laser'];
for (const fi of Object.keys(wizFaces).sort((a,b)=>a-b)) {
    const star = [2,3,4,5,7,8,11].includes(+fi) ? ' ★ FAILING' : '';
    analyzeLayer(`Face ${fi} (${FACE_LABELS[fi]})${star}`, wizFaces[fi]);
    console.log('');
}

// Count total unique colors in the worst combo: body2 + face3 + item4
console.log('\n=== Worst combo: body2 + face3(Feels Bad) + item4(Staff Manifest) ===');
const allGlobalIdxs = new Set();
const b2 = wizBodies[2], f3 = wizFaces[3], i4 = wizItems[4];
if (b2) for (let i = 0; i < b2[7]; i++) allGlobalIdxs.add(b2[8 + i]);
if (f3) for (let i = 0; i < f3[7]; i++) allGlobalIdxs.add(f3[8 + i]);
if (i4) for (let i = 0; i < i4[7]; i++) allGlobalIdxs.add(i4[8 + i]);
console.log(`Combined unique global palette indices: ${allGlobalIdxs.size}`);
console.log('Indices:', [...allGlobalIdxs].sort((a,b)=>a-b).map(i => {
    const r = pr[i*3], g = pr[i*3+1], b = pr[i*3+2];
    return `${i}=#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`;
}).join(', '));
