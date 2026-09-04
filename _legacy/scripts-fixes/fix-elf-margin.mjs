#!/usr/bin/env node
/**
 * fix-elf-margin.mjs — Squeeze 2+ extra bytes from Elf combos
 * by removing 1 color from elf-02 and 1 from elf-item-00
 */
import { readFileSync, writeFileSync } from 'fs';

// elf-02: merge #AEB97F (8px muted green accent) → #787B53 (115px olive shadow)
// Both are olive/green tones. 8 pixels changing.
let svg02 = readFileSync('public/frens/elf-02.svg', 'utf-8');
const c1 = (svg02.match(/#AEB97F/gi) || []).length;
svg02 = svg02.replace(/#AEB97F/gi, '#787B53');
console.log('elf-02: #AEB97F → #787B53:', c1, 'px (muted green → olive)');
writeFileSync('public/frens/elf-02.svg', svg02);

// elf-item-00: merge #50742C (9px dark-mid green) → #273813 (156px dark green)
// Small accent, merging into the dominant dark green
let svgItem = readFileSync('public/frens/elf-item-00.svg', 'utf-8');
const c2 = (svgItem.match(/#50742C/gi) || []).length;
svgItem = svgItem.replace(/#50742C/gi, '#273813');
console.log('elf-item-00: #50742C → #273813:', c2, 'px (mid green → dark green)');
writeFileSync('public/frens/elf-item-00.svg', svgItem);

// Check remaining colors
for (const [name, path] of [['elf-02', 'public/frens/elf-02.svg'], ['elf-item-00', 'public/frens/elf-item-00.svg']]) {
    const svg = readFileSync(path, 'utf-8');
    const fills = {};
    const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
    let m;
    while ((m = re.exec(svg)) !== null) fills[m[1].toUpperCase()] = (fills[m[1].toUpperCase()] || 0) + 1;
    console.log(`\n${name}: ${Object.keys(fills).length} colors`);
    for (const [h, c] of Object.entries(fills).sort((a,b) => b[1] - a[1])) console.log(`  ${h} ${c}px`);
}
