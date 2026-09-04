import { readFileSync } from 'fs';
const svg = readFileSync('public/frens/wizard-05.svg','utf-8');
const fills = {};
const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
let m;
while ((m = re.exec(svg)) !== null) { const h=m[1].toUpperCase(); fills[h]=(fills[h]||0)+1; }
const entries = Object.entries(fills).sort((a,b)=>b[1]-a[1]);
console.log('wizard-05.svg colors:', entries.length);
for (const [hex,cnt] of entries) console.log('  '+hex+' '+String(cnt).padStart(4)+' px');
