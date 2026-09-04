#!/usr/bin/env node
/**
 * fix-elf-colors.mjs — Flatten gradient anti-aliasing in elf-02.svg and elf-item-00.svg
 *
 * elf-02.svg: 490 unique colors → ~11 clean colors
 * elf-item-00.svg: 240 unique colors → ~4 clean colors
 *
 * Uses RGB-distance snapping: each fill color is replaced by the nearest target.
 */
import { readFileSync, writeFileSync } from 'fs';

function hexToRgb(hex) {
    hex = hex.replace('#', '');
    if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
    return [parseInt(hex.slice(0,2),16), parseInt(hex.slice(2,4),16), parseInt(hex.slice(4,6),16)];
}

function rgbDist(a, b) {
    return Math.sqrt((a[0]-b[0])**2 + (a[1]-b[1])**2 + (a[2]-b[2])**2);
}

function snapColors(svgPath, targets) {
    let svg = readFileSync(svgPath, 'utf-8');
    const targetRgb = targets.map(t => ({ hex: t, rgb: hexToRgb(t) }));

    // Find all unique fill colors
    const fills = {};
    const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
    let m;
    while ((m = re.exec(svg)) !== null) {
        const h = m[1].toUpperCase();
        fills[h] = (fills[h] || 0) + 1;
    }

    const before = Object.keys(fills).length;
    let changed = 0;

    // Build replacement map
    const replaceMap = {};
    for (const hex of Object.keys(fills)) {
        const rgb = hexToRgb(hex);
        let best = null, bestDist = Infinity;
        for (const t of targetRgb) {
            const d = rgbDist(rgb, t.rgb);
            if (d < bestDist) { bestDist = d; best = t.hex; }
        }
        if (best.toUpperCase() !== hex) {
            replaceMap[hex] = best.toUpperCase();
            changed += fills[hex];
        }
    }

    // Apply replacements (case-insensitive)
    for (const [from, to] of Object.entries(replaceMap)) {
        const fromRe = new RegExp(from.replace('#', '#'), 'gi');
        svg = svg.replace(fromRe, to);
    }

    // Verify final count
    const finalFills = {};
    const re2 = /fill="(#[0-9a-fA-F]{3,6})"/g;
    while ((m = re2.exec(svg)) !== null) {
        const h = m[1].toUpperCase();
        finalFills[h] = (finalFills[h] || 0) + 1;
    }
    const after = Object.keys(finalFills).length;

    console.log(`${svgPath}: ${before} → ${after} colors (${changed} pixels changed)`);
    for (const [h, c] of Object.entries(finalFills).sort((a,b) => b[1] - a[1])) {
        console.log(`  ${h} ${c}px`);
    }

    writeFileSync(svgPath, svg);
    return after;
}

// elf-02.svg: 490 colors → 11 targets
// 4 purple shades (robe), 1 outline, 2 browns, 1 olive, 1 gold, 1 eye green, 1 white
console.log('=== elf-02.svg (Purple Elf Body) ===');
snapColors('public/frens/elf-02.svg', [
    '#7A61A5',  // Mid purple (robe body)
    '#5C467F',  // Deep purple (robe shadow)
    '#B9ACCE',  // Pale purple (robe highlight)
    '#846EAC',  // Light purple (midtone)
    '#000000',  // Outlines (merge all near-blacks)
    '#583A20',  // Dark brown (wood/staff)
    '#C9E0A1',  // Green-yellow (eyes/skin)
    '#787B53',  // Olive (belt/accent)
    '#B09A68',  // Gold (staff metal)
    '#AEB97F',  // Muted green (face shadow shared)
    '#FFFFFF',  // White highlights
]);

console.log('\n=== elf-item-00.svg (Elf Item) ===');
// 240 colors → 4 greens (monochromatic item)
snapColors('public/frens/elf-item-00.svg', [
    '#273813',  // Deep dark forest green (shadows)
    '#50742C',  // Saturated dark-mid green
    '#718745',  // Medium leaf green
    '#88A45A',  // Bright sage green (highlights)
]);

console.log('\nDone. Now recompress and verify.');
