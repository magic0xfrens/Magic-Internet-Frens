import { readFileSync, writeFileSync } from 'fs';

let svg = readFileSync('public/frens/wiz-item-manifest.svg', 'utf-8');

// #2E461A → #2B401A (dark greens, dist=6.7, #2B401A shared with face palette)
let c1 = (svg.match(/#2E461A/gi) || []).length;
svg = svg.replace(/#2E461A/gi, '#2B401A');
console.log('#2E461A → #2B401A:', c1, 'replacements');

// #DD191D → #A83410 (reds, dist=60.9, #A83410 shared with face palette)
let c2 = (svg.match(/#DD191D/gi) || []).length;
svg = svg.replace(/#DD191D/gi, '#A83410');
console.log('#DD191D → #A83410:', c2, 'replacements');

// #7ADA54 → #5D8F36 (greens, dist=85.8, #5D8F36 shared with face palette)
let c3 = (svg.match(/#7ADA54/gi) || []).length;
svg = svg.replace(/#7ADA54/gi, '#5D8F36');
console.log('#7ADA54 → #5D8F36:', c3, 'replacements');

writeFileSync('public/frens/wiz-item-manifest.svg', svg);

// Count remaining
const fills = {};
const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
let m;
while ((m = re.exec(svg)) !== null) {
    fills[m[1].toUpperCase()] = (fills[m[1].toUpperCase()] || 0) + 1;
}
console.log('Remaining colors:', Object.keys(fills).length);
for (const [h, c] of Object.entries(fills).sort((a, b) => b[1] - a[1])) {
    console.log('  ' + h + ' ' + c + 'px');
}
