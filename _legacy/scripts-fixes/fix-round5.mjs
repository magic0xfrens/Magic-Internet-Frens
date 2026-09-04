import { readFileSync, writeFileSync } from 'fs';

// wizard-05.svg: merge dark blue-grey → black (dist=53.8, makes dark body area more uniform)
let svg = readFileSync('public/frens/wizard-05.svg', 'utf-8');
let c1 = (svg.match(/#182024/gi) || []).length;
svg = svg.replace(/#182024/gi, '#000000');
console.log('wizard-05: #182024 → #000000:', c1, 'replacements');
writeFileSync('public/frens/wizard-05.svg', svg);

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
