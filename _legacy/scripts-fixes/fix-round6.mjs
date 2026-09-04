import { readFileSync, writeFileSync } from 'fs';

// wiz-item-manifest.svg: merge brown → closest shared color
// #795548 (121,85,72) → #A83410 (168,52,16) — both warm tones, dist=80
// This eliminates the LAST item-only color, meaning b4+face+i4 has fewer unique colors
let svg = readFileSync('public/frens/wiz-item-manifest.svg', 'utf-8');
let c1 = (svg.match(/#795548/gi) || []).length;
svg = svg.replace(/#795548/gi, '#A83410');
console.log('#795548 → #A83410:', c1, 'replacements');
writeFileSync('public/frens/wiz-item-manifest.svg', svg);

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
