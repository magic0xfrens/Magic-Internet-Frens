import { readFileSync, writeFileSync } from 'fs';

let svg = readFileSync('public/frens/wiz-item-manifest.svg', 'utf-8');

// #03A9F4 → #000000 (5px bright blue accent → black, trivial visual change)
let c1 = (svg.match(/#03A9F4/gi) || []).length;
svg = svg.replace(/#03A9F4/gi, '#000000');
console.log('#03A9F4 → #000000:', c1, 'replacements (tiny blue accent)');

// #FAF1C3 → #FFFFFF (292px cream → white, parchment becomes white)
let c2 = (svg.match(/#FAF1C3/gi) || []).length;
svg = svg.replace(/#FAF1C3/gi, '#FFFFFF');
console.log('#FAF1C3 → #FFFFFF:', c2, 'replacements (cream → white)');

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
