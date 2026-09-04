#!/usr/bin/env node
/**
 * fix-elf03-colors.mjs — Flatten elf-03.svg from 1,438 gradient colors → ~10 clean colors
 * Also flatten elf-04.svg if it has the same anti-aliasing problem.
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
    const targetRgb = targets.map(t => ({ hex: t.toUpperCase(), rgb: hexToRgb(t) }));

    const fills = {};
    const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
    let m;
    while ((m = re.exec(svg)) !== null) {
        const h = m[1].toUpperCase();
        fills[h] = (fills[h] || 0) + 1;
    }

    const before = Object.keys(fills).length;
    let changed = 0;

    const replaceMap = {};
    for (const hex of Object.keys(fills)) {
        const rgb = hexToRgb(hex);
        let best = null, bestDist = Infinity;
        for (const t of targetRgb) {
            const d = rgbDist(rgb, t.rgb);
            if (d < bestDist) { bestDist = d; best = t.hex; }
        }
        if (best !== hex) {
            replaceMap[hex] = best;
            changed += fills[hex];
        }
    }

    for (const [from, to] of Object.entries(replaceMap)) {
        const fromRe = new RegExp(from.replace('#', '#'), 'gi');
        svg = svg.replace(fromRe, to);
    }

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

// Count colors in elf-04 first
let svg04 = readFileSync('public/frens/elf-04.svg', 'utf-8');
const fills04 = {};
const re04 = /fill="(#[0-9a-fA-F]{3,6})"/g;
let m04;
while ((m04 = re04.exec(svg04)) !== null) {
    fills04[m04[1].toUpperCase()] = (fills04[m04[1].toUpperCase()] || 0) + 1;
}
console.log(`elf-04.svg has ${Object.keys(fills04).length} unique colors\n`);

// elf-03.svg: 1,438 colors → 10 clean targets
console.log('=== elf-03.svg (Green Elf Body) ===');
snapColors('public/frens/elf-03.svg', [
    '#375934',  // Medium green (main body)
    '#2CB729',  // Bright green (highlights)
    '#1A3218',  // Dark green (shadow)
    '#095407',  // Dark saturated green (body secondary)
    '#000000',  // Black outlines
    '#583A20',  // Dark brown (wood/staff)
    '#C9E0A1',  // Face highlight (shared)
    '#787B53',  // Face shadow olive (shared)
    '#B09A68',  // Tan/gold accent
    '#AEB97F',  // Muted green accent (shared)
]);

// elf-04.svg if needed
if (Object.keys(fills04).length > 20) {
    console.log('\n=== elf-04.svg (Brown/Orange Elf Body) ===');
    snapColors('public/frens/elf-04.svg', [
        '#A74C00',  // Brown-orange (main body)
        '#FF7D16',  // Bright orange (highlights)
        '#6D431E',  // Dark brown (shadow)
        '#000000',  // Black outlines
        '#C9E0A1',  // Face highlight (shared)
        '#787B53',  // Face shadow olive (shared)
        '#B09A68',  // Tan/gold accent
        '#AEB97F',  // Muted green accent (shared)
        '#DDC86B',  // Gold/yellow detail
        '#4A3A2D',  // Medium brown (wood)
    ]);
}

console.log('\nDone. Now recompress and verify.');
