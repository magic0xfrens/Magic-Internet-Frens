#!/usr/bin/env node
/**
 * fix-wizard-round2.mjs — Second round of color merges for remaining 4 Wizard fails.
 * Remaining fails:
 *   b2 f3 i0 → 2049 (1 over)
 *   b4 f2 i4 → 2053 (5 over)
 *   b4 f3 i4 → 2077 (29 over, worst)
 *   b4 f11 i4 → 2053 (5 over)
 *
 * Strategy: merge more colors in wizard-05.svg and wiz-item-manifest.svg
 */
import { readFileSync, writeFileSync } from 'fs';
import { join, basename } from 'path';
import { readdirSync } from 'fs';

const FRENS_DIR = join(import.meta.dirname, '..', 'public', 'frens');
const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');

// Read the current palette to see post-compression colors
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
    console.log(`  ${label}: ${lps} local colors`);
    const colors = [];
    for (let i = 0; i < lps; i++) {
        const gIdx = layerData[8 + i];
        const r = pr[gIdx * 3], g = pr[gIdx * 3 + 1], b = pr[gIdx * 3 + 2];
        const hex = `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
        colors.push({ gIdx, r, g, b, hex });
        console.log(`    gIdx=${gIdx.toString().padStart(3)} ${hex}`);
    }
    for (let i = 0; i < colors.length; i++) {
        for (let j = i + 1; j < colors.length; j++) {
            const d = Math.sqrt((colors[i].r - colors[j].r) ** 2 + (colors[i].g - colors[j].g) ** 2 + (colors[i].b - colors[j].b) ** 2);
            if (d < 50) console.log(`      CLOSE: ${colors[i].hex} ↔ ${colors[j].hex} dist=${d.toFixed(1)}`);
        }
    }
}

console.log('=== Current state after round 1 ===\n');
console.log('Wizard Body 2 (wizard-03.svg):');
analyzeLayer('body-2', traits[0]?.[0]?.[2]);
console.log('\nWizard Body 4 (wizard-05.svg):');
analyzeLayer('body-4', traits[0]?.[0]?.[4]);
console.log('\nWizard Item 0 (wiz-item-01.svg):');
analyzeLayer('item-0', traits[2]?.[0]?.[0]);
console.log('\nWizard Item 4 (wiz-item-manifest.svg):');
analyzeLayer('item-4', traits[2]?.[0]?.[4]);
console.log('\nFace 3 (Feels Bad):');
analyzeLayer('face-3', traits[1]?.[0]?.[3]);

// ── Now do round 2 merges ──
function hexToRgb(hex) {
    hex = hex.replace('#', '');
    return { r: parseInt(hex.substring(0, 2), 16), g: parseInt(hex.substring(2, 4), 16), b: parseInt(hex.substring(4, 6), 16) };
}

function extractFillColors(svg) {
    const fills = {};
    const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
    let m;
    while ((m = re.exec(svg)) !== null) {
        const hex = m[1].toUpperCase();
        fills[hex] = (fills[hex] || 0) + 1;
    }
    const re2 = /fill:\s*(#[0-9a-fA-F]{3,6})/g;
    while ((m = re2.exec(svg)) !== null) {
        const hex = m[1].toUpperCase();
        fills[hex] = (fills[hex] || 0) + 1;
    }
    return fills;
}

function applyMerge(filePath, from, to) {
    let svg = readFileSync(filePath, 'utf-8');
    const count = (svg.match(new RegExp(from.replace('#', '#'), 'gi')) || []).length;
    svg = svg.replace(new RegExp(from.replace('#', '#'), 'gi'), to);
    writeFileSync(filePath, svg);
    console.log(`  ${basename(filePath)}: ${from} → ${to} (${count} occurrences)`);
}

console.log('\n\n=== ROUND 2 MERGES ===\n');

// Check what close pairs still exist in wizard-03.svg after round 1
const wiz03Path = join(FRENS_DIR, 'wizard-03.svg');
const wiz03Fills = extractFillColors(readFileSync(wiz03Path, 'utf-8'));
console.log('wizard-03.svg remaining colors:', Object.keys(wiz03Fills).length);
const wiz03Colors = Object.entries(wiz03Fills).map(([hex, count]) => ({ hex, count, rgb: hexToRgb(hex) }));
for (let i = 0; i < wiz03Colors.length; i++) {
    for (let j = i + 1; j < wiz03Colors.length; j++) {
        const d = Math.sqrt((wiz03Colors[i].rgb.r - wiz03Colors[j].rgb.r) ** 2 + (wiz03Colors[i].rgb.g - wiz03Colors[j].rgb.g) ** 2 + (wiz03Colors[i].rgb.b - wiz03Colors[j].rgb.b) ** 2);
        if (d < 50) console.log(`  ${wiz03Colors[i].hex}(${wiz03Colors[i].count}) ↔ ${wiz03Colors[j].hex}(${wiz03Colors[j].count}) dist=${d.toFixed(1)}`);
    }
}

// wizard-03.svg: merge 1 more close pair to help b2+f3+i0 get under 2048
// After round 1, remaining browns: #4E342E (505+57=562px), #6D4C41 (408px), #8D6E63 (1221px)
// #4E342E ↔ #6D4C41 dist=43.6 — aggressive but acceptable for 1-byte savings
applyMerge(wiz03Path, '#6D4C41', '#4E342E');

// wizard-05.svg: merge gold shades to reduce total colors in b4+i4 combos
const wiz05Path = join(FRENS_DIR, 'wizard-05.svg');
const wiz05Fills = extractFillColors(readFileSync(wiz05Path, 'utf-8'));
console.log('\nwizard-05.svg remaining colors:', Object.keys(wiz05Fills).length);
const wiz05Colors = Object.entries(wiz05Fills).map(([hex, count]) => ({ hex, count, rgb: hexToRgb(hex) }));
for (let i = 0; i < wiz05Colors.length; i++) {
    for (let j = i + 1; j < wiz05Colors.length; j++) {
        const d = Math.sqrt((wiz05Colors[i].rgb.r - wiz05Colors[j].rgb.r) ** 2 + (wiz05Colors[i].rgb.g - wiz05Colors[j].rgb.g) ** 2 + (wiz05Colors[i].rgb.b - wiz05Colors[j].rgb.b) ** 2);
        if (d < 55) console.log(`  ${wiz05Colors[i].hex}(${wiz05Colors[i].count}) ↔ ${wiz05Colors[j].hex}(${wiz05Colors[j].count}) dist=${d.toFixed(1)}`);
    }
}
// After round 1: 5 colors: #FFC107(1724), #6E4803(504+74=578), #182024(497+56+53=606), #BA7B06(251), #FFFFFF(52)
// #6E4803 ↔ #BA7B06 dist=~53 — somewhat aggressive but these are both gold-brown
// Let's merge the remaining dark shades: done in round 1
// Try: #BA7B06 → #6E4803 (dist ~53, merging medium gold into dark gold)
applyMerge(wiz05Path, '#BA7B06', '#6E4803');

// wiz-item-manifest.svg: merge more close pairs
const wizItemPath = join(FRENS_DIR, 'wiz-item-manifest.svg');
const wizItemFills = extractFillColors(readFileSync(wizItemPath, 'utf-8'));
console.log('\nwiz-item-manifest.svg remaining colors:', Object.keys(wizItemFills).length);
const wizItemColors = Object.entries(wizItemFills).map(([hex, count]) => ({ hex, count, rgb: hexToRgb(hex) }));
for (let i = 0; i < wizItemColors.length; i++) {
    for (let j = i + 1; j < wizItemColors.length; j++) {
        const d = Math.sqrt((wizItemColors[i].rgb.r - wizItemColors[j].rgb.r) ** 2 + (wizItemColors[i].rgb.g - wizItemColors[j].rgb.g) ** 2 + (wizItemColors[i].rgb.b - wizItemColors[j].rgb.b) ** 2);
        if (d < 60) console.log(`  ${wizItemColors[i].hex}(${wizItemColors[i].count}) ↔ ${wizItemColors[j].hex}(${wizItemColors[j].count}) dist=${d.toFixed(1)}`);
    }
}
// After round 1: 12 colors. Merge more:
// #B2AD7A(113) ↔ #FAF1C3(171) — both light/cream, dist ~56
// #D9E4A3(8) ↔ #FAF1C3(171) — both pale, merge small into big
applyMerge(wizItemPath, '#D9E4A3', '#FAF1C3');
// #795548(218) ↔ #5D8F36 — too far apart (different hue)
// Let's try #B2AD7A → #FAF1C3 if close enough
applyMerge(wizItemPath, '#B2AD7A', '#FAF1C3');

console.log('\nDone! Now recompress and re-verify.');
