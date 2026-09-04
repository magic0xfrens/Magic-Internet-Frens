#!/usr/bin/env node
/**
 * fix-wizard-colors.mjs — Analyze and merge close fill colors in Wizard SVGs.
 * Step 1: Analyze unique fill colors per SVG
 * Step 2: Find close pairs and plan merges
 * Step 3: Apply replacements
 */
import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

const FRENS_DIR = join(import.meta.dirname, '..', 'public', 'frens');

function hexToRgb(hex) {
    hex = hex.replace('#', '');
    if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
    return {
        r: parseInt(hex.substring(0, 2), 16),
        g: parseInt(hex.substring(2, 4), 16),
        b: parseInt(hex.substring(4, 6), 16),
    };
}

function rgbDist(a, b) {
    return Math.sqrt((a.r - b.r) ** 2 + (a.g - b.g) ** 2 + (a.b - b.b) ** 2);
}

function extractFillColors(svg) {
    const fills = {};
    // Match fill="#hex" patterns
    const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
    let m;
    while ((m = re.exec(svg)) !== null) {
        const hex = m[1].toUpperCase();
        fills[hex] = (fills[hex] || 0) + 1;
    }
    // Also match style="fill:#hex" patterns
    const re2 = /fill:\s*(#[0-9a-fA-F]{3,6})/g;
    while ((m = re2.exec(svg)) !== null) {
        const hex = m[1].toUpperCase();
        fills[hex] = (fills[hex] || 0) + 1;
    }
    return fills;
}

function analyzeFile(filename) {
    const path = join(FRENS_DIR, filename);
    const svg = readFileSync(path, 'utf-8');
    const fills = extractFillColors(svg);
    const colors = Object.entries(fills).map(([hex, count]) => ({
        hex, count, rgb: hexToRgb(hex),
    })).sort((a, b) => b.count - a.count);

    console.log(`\n=== ${filename} — ${colors.length} unique fill colors ===`);
    for (const c of colors) {
        console.log(`  ${c.hex.padEnd(8)} ${c.count.toString().padStart(5)} px  rgb(${c.rgb.r},${c.rgb.g},${c.rgb.b})`);
    }

    // Find close pairs
    const pairs = [];
    for (let i = 0; i < colors.length; i++) {
        for (let j = i + 1; j < colors.length; j++) {
            const d = rgbDist(colors[i].rgb, colors[j].rgb);
            if (d < 45) {
                pairs.push({ a: colors[i], b: colors[j], dist: d });
            }
        }
    }
    pairs.sort((a, b) => a.dist - b.dist);
    if (pairs.length > 0) {
        console.log(`  Close pairs (<45 dist):`);
        for (const p of pairs) {
            console.log(`    ${p.a.hex} (${p.a.count}px) ↔ ${p.b.hex} (${p.b.count}px)  dist=${p.dist.toFixed(1)}`);
        }
    }
    return { filename, colors, pairs, svg, path };
}

// Analyze all three problem files
const wiz03 = analyzeFile('wizard-03.svg');
const wiz05 = analyzeFile('wizard-05.svg');
const wizItem = analyzeFile('wiz-item-manifest.svg');

// ── Plan merges ──
console.log('\n\n========= MERGE PLAN =========\n');

function planMerges(analysis, targetReduction) {
    const { filename, colors, pairs } = analysis;
    const merges = [];
    const merged = new Set();

    // Greedy: merge closest pairs first, keep the one with more pixels
    for (const p of pairs) {
        if (merged.has(p.a.hex) || merged.has(p.b.hex)) continue;
        // Keep the one with more pixels, replace the other
        const [keep, replace] = p.a.count >= p.b.count ? [p.a, p.b] : [p.b, p.a];
        merges.push({ from: replace.hex, to: keep.hex, dist: p.dist, affectedPx: replace.count });
        merged.add(replace.hex);
        if (merges.length >= targetReduction) break;
    }

    console.log(`${filename}: ${merges.length} merges planned`);
    for (const m of merges) {
        console.log(`  ${m.from} → ${m.to}  (dist=${m.dist.toFixed(1)}, ${m.affectedPx} px)`);
    }
    return merges;
}

const merges03 = planMerges(wiz03, 4);  // Reduce 15 → ~11
const merges05 = planMerges(wiz05, 3);  // Reduce 8 → ~5
const mergesItem = planMerges(wizItem, 4); // Reduce 15 → ~11

// ── Apply merges ──
console.log('\n\n========= APPLYING MERGES =========\n');

function applyMerges(analysis, merges) {
    let svg = analysis.svg;
    for (const m of merges) {
        // Replace in fill="..." attributes (case insensitive)
        const fromLower = m.from.toLowerCase();
        const fromUpper = m.from.toUpperCase();
        const toLower = m.to.toLowerCase();

        // Count occurrences before
        const countBefore = (svg.match(new RegExp(m.from.replace('#', '#'), 'gi')) || []).length;

        // Replace all occurrences (case insensitive for hex)
        svg = svg.replace(new RegExp(m.from.replace('#', '#'), 'gi'), m.to);

        const countAfter = (svg.match(new RegExp(m.from.replace('#', '#'), 'gi')) || []).length;
        console.log(`  ${analysis.filename}: ${m.from} → ${m.to} (${countBefore} occurrences replaced)`);
    }

    // Verify new color count
    const newFills = extractFillColors(svg);
    const newCount = Object.keys(newFills).length;
    const oldCount = analysis.colors.length;
    console.log(`  ${analysis.filename}: ${oldCount} → ${newCount} unique colors`);

    writeFileSync(analysis.path, svg);
    console.log(`  Written: ${analysis.path}`);
    return newCount;
}

applyMerges(wiz03, merges03);
applyMerges(wiz05, merges05);
applyMerges(wizItem, mergesItem);

console.log('\nDone! Now run: node scripts/compress-traits.mjs');
