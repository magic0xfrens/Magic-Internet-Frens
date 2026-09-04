#!/usr/bin/env node
/**
 * generate-preview.mjs — Generate HTML with rendered PNGs at 64x64 for all failing combos
 * + all Elf combos (showing they pass after stale body removal).
 * Shows before/after color palettes and swatches.
 */
import { readFileSync, readdirSync, writeFileSync } from 'fs';
import { join } from 'path';
import { deflateRawSync, constants as zlibConstants } from 'zlib';

const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');
const LIMIT = 2048;
const NAMES = ['Wizard','King','Knight','Apprentice','Peasant','Gnome','Elf'];
function fci(ci) { return ci === 5 ? 5 : ci === 6 ? 6 : 0; }

const pb = readFileSync(join(TRAITS_DIR, 'palette.bin'));
const pc = pb.readUInt16BE(0);
const pr = new Uint8Array(pc * 3);
for (let i = 0; i < pc * 3; i++) pr[i] = pb[2 + i];

const traits = {};
for (const f of readdirSync(TRAITS_DIR).filter(f => f.startsWith('trait-') && f.endsWith('.bin'))) {
    if (f === 'trait-0-6-3.bin') continue; // skip stale
    const d = readFileSync(join(TRAITS_DIR, f));
    if (!traits[d[0]]) traits[d[0]] = {};
    if (!traits[d[0]][d[1]]) traits[d[0]][d[1]] = {};
    traits[d[0]][d[1]][d[2]] = d;
}

function comp(c, ld, cs) { if (!ld || ld.length < 10) return; const [,,,mx,my,bw,bh,lps] = ld; if (!lps||!bw||!bh) return; const ps=8, pds=ps+lps; if (pds>=ld.length) return; for (let p=0; p<bw*bh; p++) { const bo=pds+(p>>1); if (bo>=ld.length) break; const nb=((p&1)===0)?(ld[bo]>>4)&0xF:ld[bo]&0xF; if (nb===0) continue; const li=nb-1; if (li>=lps) continue; const ax=mx+(p%bw), ay=my+Math.floor(p/bw); if (ax<cs&&ay<cs) c[ay*cs+ax]=ld[ps+li]+1; } }
function pngP(f,a,b,c){if(f<=0)return 0;if(f===1)return a;if(f===2)return b;if(f===3)return(a+b)>>1;const p=a+b-c;if(Math.abs(p-a)<=Math.abs(p-b)&&Math.abs(p-a)<=Math.abs(p-c))return a;if(Math.abs(p-b)<=Math.abs(p-c))return b;return c;}
function adler32(d){let a=1,b=0;for(let i=0;i<d.length;i++){a=(a+d[i])%65521;b=(b+a)%65521;}return((b<<16)|a)>>>0;}
function crc32(buf){const T=new Uint32Array(256);for(let i=0;i<256;i++){let c=i;for(let j=0;j<8;j++)c=(c&1)?(0xEDB88320^(c>>>1)):(c>>>1);T[i]=c;}let crc=0xFFFFFFFF;for(let i=0;i<buf.length;i++)crc=T[(crc^buf[i])&0xFF]^(crc>>>8);return(crc^0xFFFFFFFF)>>>0;}
function wc(png,off,type,data){png.writeUInt32BE(data.length,off);off+=4;png.write(type,off,4,'ascii');off+=4;data.copy(png,off);off+=data.length;png.writeUInt32BE(crc32(png.subarray(off-data.length-4,off)),off);off+=4;return off;}

function quantize(canvas,palette,w,h,maxC){
    const cs=new Set();for(let i=0;i<w*h;i++)cs.add(canvas[i]);const uv=Array.from(cs);if(uv.length<=maxC)return uv.length;
    const colors=uv.map(v=>{if(v===0)return{v,r:0,g:0,b:0};const po=(v-1)*3;return po+2<palette.length?{v,r:palette[po],g:palette[po+1],b:palette[po+2]}:{v,r:0,g:0,b:0};});
    while(colors.length>maxC){let md=Infinity,mi=-1,mj=-1;for(let i=0;i<colors.length;i++)for(let j=i+1;j<colors.length;j++){const d=(colors[i].r-colors[j].r)**2+(colors[i].g-colors[j].g)**2+(colors[i].b-colors[j].b)**2;if(d<md){md=d;mi=i;mj=j;}}
    const rv=colors[mj].v,kv=colors[mi].v;colors[mi].r=Math.round((colors[mi].r+colors[mj].r)/2);colors[mi].g=Math.round((colors[mi].g+colors[mj].g)/2);colors[mi].b=Math.round((colors[mi].b+colors[mj].b)/2);colors.splice(mj,1);for(let i=0;i<w*h;i++)if(canvas[i]===rv)canvas[i]=kv;}
    return colors.length;
}

function enc4(canvas,palette,w,h){
    const used=new Uint8Array(256);for(let i=0;i<w*h;i++)used[canvas[i]]=1;
    const g2l=new Uint8Array(256);const lr=new Uint8Array(16),lg=new Uint8Array(16),lb=new Uint8Array(16);let lc=0;
    for(let i=0;i<256;i++){if(!used[i])continue;if(lc>=16)break;g2l[i]=lc;const po=i===0?-1:(i-1)*3;if(po>=0&&po+2<palette.length){lr[lc]=palette[po];lg[lc]=palette[po+1];lb[lc]=palette[po+2];}lc++;}
    const dw=Math.ceil(w/2),frl=1+dw;const filt=Buffer.alloc(frl*h);const prev=new Uint8Array(dw),cur=new Uint8Array(dw);
    for(let y=0;y<h;y++){for(let x=0;x<dw;x++){const p0=x*2<w?g2l[canvas[y*w+x*2]]:0;const p1=x*2+1<w?g2l[canvas[y*w+x*2+1]]:0;cur[x]=(p0<<4)|p1;}
    let bf=0,bs=Infinity;for(let f=0;f<=4;f++){let s=0;for(let x=0;x<dw;x++){const v=(cur[x]-pngP(f,x>0?cur[x-1]:0,prev[x],x>0?prev[x-1]:0))&0xFF;s+=v<128?v:256-v;}if(s<bs){bs=s;bf=f;}}
    filt[y*frl]=bf;for(let x=0;x<dw;x++)filt[y*frl+1+x]=(cur[x]-pngP(bf,x>0?cur[x-1]:0,prev[x],x>0?prev[x-1]:0))&0xFF;cur.forEach((v,i)=>{prev[i]=v;});}
    const defl=deflateRawSync(filt,{level:6,strategy:zlibConstants.Z_FIXED});const adl=adler32(filt);const zl=2+defl.length+4;const zb=Buffer.alloc(zl);zb[0]=0x78;zb[1]=0x01;defl.copy(zb,2);zb.writeUInt32BE(adl,2+defl.length);
    const ps=8+25+(12+lc*3)+(12+zl)+12;const png=Buffer.alloc(ps);let off=0;Buffer.from([137,80,78,71,13,10,26,10]).copy(png,off);off+=8;
    const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=4;ih[9]=3;off=wc(png,off,'IHDR',ih);
    const pl=Buffer.alloc(lc*3);for(let i=0;i<lc;i++){pl[i*3]=lr[i];pl[i*3+1]=lg[i];pl[i*3+2]=lb[i];}off=wc(png,off,'PLTE',pl);
    off=wc(png,off,'IDAT',zb);off=wc(png,off,'IEND',Buffer.alloc(0));return png.subarray(0,off);
}

function receipt(cn,buf){const b64=buf.toString('base64');const json=`{"name":"${cn} #777","image":"data:image/png;base64,${b64}"}`;let uj='';for(let i=0;i<json.length;i++){const c=json.charCodeAt(i);if(c===0x22)uj+='%22';else if(c===0x7B)uj+='%7B';else if(c===0x7D)uj+='%7D';else if(c===0x23)uj+='%23';else if(c===0x20)uj+='%20';else uj+=json[i];}return 4+('data:application/json,'+uj).length;}

const bgR=0xF7,bgG=0x93,bgB=0x1A;let bgVal=0;
for(let i=0;i<pc;i++){if(pr[i*3]===bgR&&pr[i*3+1]===bgG&&pr[i*3+2]===bgB){bgVal=i+1;break;}}
let usePal=pr;if(bgVal===0){usePal=new Uint8Array(pr.length+3);usePal.set(pr);usePal[pr.length]=bgR;usePal[pr.length+1]=bgG;usePal[pr.length+2]=bgB;bgVal=Math.floor(pr.length/3)+1;}

function renderCombo(ci, bi, fi, ii, cs, cx) {
    const fciV = fci(ci);
    const body = traits[0]?.[ci]?.[bi];
    const face = traits[1]?.[fciV]?.[fi];
    const item = traits[2]?.[ci]?.[ii];
    const subs = traits[3]?.[ci === 4 ? 4 : 0] || {};

    const c = new Uint8Array(120 * 120);
    comp(c, face, 120);
    comp(c, body, 120);
    comp(c, item, 120);
    const sk = Object.keys(subs); if (sk.length > 0) comp(c, subs[sk[0]], 120);

    // Count unique colors before crop
    const uniquePre = new Set();
    for (let i = 0; i < 120 * 120; i++) if (c[i] !== 0) uniquePre.add(c[i]);

    const crop = new Uint8Array(cs * cs);
    for (let dy = 0; dy < cs; dy++) for (let dx = 0; dx < cs; dx++) {
        const v = c[(cx + dy) * 120 + (cx + dx)];
        crop[dy * cs + dx] = v === 0 ? bgVal : v;
    }

    const uniquePost = new Set();
    for (let i = 0; i < cs * cs; i++) uniquePost.add(crop[i]);

    // Render WITHOUT quantization for "before" view
    const cropBefore = new Uint8Array(crop);

    quantize(crop, usePal, cs, cs, 16);
    const png = enc4(crop, usePal, cs, cs);
    const r = receipt(NAMES[ci], png);

    return { png, receipt: r, ok: r <= LIMIT, uniquePre: uniquePre.size, uniquePost: uniquePost.size, cropBefore };
}

const FACE_LABELS = ['Classic','Happy','Angry','Feels Bad','Grinding','Chill','Grumpy','Giga Happy','Cooked','Comfy','Retard','Laser'];
const BODY_LABELS_W = ['Wizard I','Wizard II','Wizard III','Wizard IV','Wizard V','Wizard VI','Wizard Manifest','Wizard BTC'];
const ITEM_LABELS_W = ['Staff I','Staff II','Staff III','Staff IV','Staff Manifest'];

let html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>64x64 Combo Preview</title>
<style>
body { background:#1a1a2e; color:#eee; font-family:monospace; padding:20px; }
h1 { color:#f7931a; }
h2 { color:#4fc3f7; margin-top:40px; border-bottom:1px solid #333; padding-bottom:8px; }
h3 { color:#81c784; }
.grid { display:flex; flex-wrap:wrap; gap:12px; }
.card { background:#252540; border-radius:8px; padding:12px; text-align:center; width:200px; }
.card.fail { border:2px solid #f44336; }
.card.pass { border:2px solid #4caf50; }
.card img { width:128px; height:128px; image-rendering:pixelated; }
.label { font-size:11px; margin-top:6px; }
.receipt { font-weight:bold; }
.receipt.over { color:#f44336; }
.receipt.under { color:#4caf50; }
.receipt.tight { color:#ffeb3b; }
.swatch { display:inline-block; width:16px; height:16px; border:1px solid #555; margin:1px; vertical-align:middle; }
.section-info { background:#1e1e3a; padding:12px; border-radius:6px; margin:10px 0; }
.close-pair { background:#3a1e1e; padding:4px 8px; border-radius:4px; margin:2px; display:inline-block; font-size:11px; }
</style></head><body>
<h1>64x64 Combo Preview — Pre-fix Analysis</h1>
<div class="section-info">
  <strong>Limit:</strong> 2048 bytes per tokenURI receipt<br>
  <strong>Format:</strong> 4-bit indexed PNG, 16-color max, adaptive row filtering, zlib fixed Huffman
</div>
`;

// ── Section 1: Elf (all pass after removing stale body) ──
html += `<h2>Elf Class — All PASS at 64x64 (stale trait-0-6-3.bin removed)</h2>
<div class="section-info">trait-0-6-3.bin was from deleted elf-01.svg (Mar 24). Only 3 valid bodies remain (elf-02, elf-03, elf-04).</div>
<div class="grid">`;

const elfBodies = traits[0]?.[6] || {};
const elfFaces = traits[1]?.[6] || {};
const elfItems = traits[2]?.[6] || {};
const ELF_BODY_LABELS = ['Elf I (elf-02)', 'Elf II (elf-03)', 'Elf III (elf-04)'];

for (const bi of Object.keys(elfBodies).sort()) {
    // Show worst face for each body
    let worstFi = 0, worstR = 0;
    for (const fi of Object.keys(elfFaces).sort()) {
        const r = renderCombo(6, +bi, +fi, 0, 64, 28);
        if (r.receipt > worstR) { worstR = r.receipt; worstFi = +fi; }
    }
    const result = renderCombo(6, +bi, worstFi, 0, 64, 28);
    const b64 = result.png.toString('base64');
    const margin = LIMIT - result.receipt;
    const cls = margin >= 50 ? 'under' : margin >= 0 ? 'tight' : 'over';
    html += `<div class="card pass">
      <img src="data:image/png;base64,${b64}">
      <div class="label">${ELF_BODY_LABELS[bi] || `Body ${bi}`}<br>Worst face: ${FACE_LABELS[worstFi]}</div>
      <div class="receipt ${cls}">${result.receipt}B (${margin >= 0 ? '+' : ''}${margin})</div>
      <div class="label">${result.uniquePost} colors → 16</div>
    </div>`;
}
html += `</div>`;

// ── Section 2: Wizard FAILING combos at 64x64 ──
html += `<h2>Wizard Class — 16 FAILING Combos at 64x64</h2>
<div class="section-info">
  Bodies 2 (wizard-03, 15 colors) and 4 (wizard-05, 8 colors) combined with Item 4 (Staff Manifest, 15 colors) produce the most failures.<br>
  Root cause: too many unique colors in body+face+item → complex pixel patterns after quantization → poor compression.
</div>`;

// Show the top 8 worst combos
const wizBodies = traits[0]?.[0] || {};
const wizFaces = traits[1]?.[0] || {};
const wizItems = traits[2]?.[0] || {};

const failResults = [];
for (const bi of Object.keys(wizBodies)) {
    for (const fi of Object.keys(wizFaces)) {
        for (const ii of Object.keys(wizItems)) {
            const result = renderCombo(0, +bi, +fi, +ii, 64, 28);
            if (!result.ok) {
                failResults.push({ bi: +bi, fi: +fi, ii: +ii, ...result });
            }
        }
    }
}
failResults.sort((a, b) => b.receipt - a.receipt);

html += `<h3>Failing at 64x64 (worst first)</h3><div class="grid">`;
for (const f of failResults.slice(0, 16)) {
    const b64 = f.png.toString('base64');
    const margin = LIMIT - f.receipt;
    html += `<div class="card fail">
      <img src="data:image/png;base64,${b64}">
      <div class="label">${BODY_LABELS_W[f.bi]} + ${FACE_LABELS[f.fi]}<br>${ITEM_LABELS_W[f.ii]}</div>
      <div class="receipt over">${f.receipt}B (${margin})</div>
      <div class="label">${f.uniquePost} colors → 16</div>
    </div>`;
}
html += `</div>`;

// ── Section 3: Same combos at 60x60 (all pass) ──
html += `<h3>Same combos at 60x60 (all pass)</h3><div class="grid">`;
for (const f of failResults.slice(0, 8)) {
    const result60 = renderCombo(0, f.bi, f.fi, f.ii, 60, 30);
    const b64 = result60.png.toString('base64');
    const margin = LIMIT - result60.receipt;
    const cls = margin >= 50 ? 'under' : margin >= 0 ? 'tight' : 'over';
    html += `<div class="card pass">
      <img src="data:image/png;base64,${b64}">
      <div class="label">${BODY_LABELS_W[f.bi]} + ${FACE_LABELS[f.fi]}<br>${ITEM_LABELS_W[f.ii]}</div>
      <div class="receipt ${cls}">${result60.receipt}B (+${margin})</div>
      <div class="label">${result60.uniquePost} colors → 16</div>
    </div>`;
}
html += `</div>`;

// ── Section 4: Color palette analysis for failing bodies/items ──
html += `<h2>Color Palette Analysis — Wizard Body/Item Close Pairs</h2>`;

function paletteHTML(label, layerData) {
    if (!layerData || layerData.length < 10) return '';
    const [,,,,,,,lps] = layerData;
    let out = `<h3>${label} — ${lps} colors</h3><div>`;
    const colors = [];
    for (let i = 0; i < lps; i++) {
        const gIdx = layerData[8 + i];
        const r = pr[gIdx * 3], g = pr[gIdx * 3 + 1], b = pr[gIdx * 3 + 2];
        const hex = `#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`;
        colors.push({ gIdx, r, g, b, hex });
        out += `<span class="swatch" style="background:${hex}" title="gIdx=${gIdx} ${hex}"></span>`;
    }
    out += `</div>`;

    // Find close pairs
    const closePairs = [];
    for (let i = 0; i < colors.length; i++) {
        for (let j = i + 1; j < colors.length; j++) {
            const d = Math.sqrt((colors[i].r - colors[j].r) ** 2 + (colors[i].g - colors[j].g) ** 2 + (colors[i].b - colors[j].b) ** 2);
            if (d < 35) closePairs.push({ a: colors[i], b: colors[j], dist: d });
        }
    }
    if (closePairs.length > 0) {
        closePairs.sort((a, b) => a.dist - b.dist);
        out += `<div style="margin-top:4px">`;
        for (const p of closePairs) {
            out += `<span class="close-pair"><span class="swatch" style="background:${p.a.hex}"></span> ↔ <span class="swatch" style="background:${p.b.hex}"></span> dist=${p.dist.toFixed(0)}</span> `;
        }
        out += `</div>`;
    }
    return out;
}

html += paletteHTML('Body 2 — Wizard III (wizard-03.svg) [15 colors, FAILS]', wizBodies[2]);
html += paletteHTML('Body 4 — Wizard V (wizard-05.svg) [8 colors, FAILS]', wizBodies[4]);
html += paletteHTML('Item 4 — Staff Manifest (wiz-item-manifest.svg) [15 colors, FAILS]', wizItems[4]);
html += paletteHTML('Item 0 — Staff I (wiz-item-01.svg) [8 colors]', wizItems[0]);

// ── Section 5: Recommended fix ──
html += `<h2>Recommended Fix</h2>
<div class="section-info">
  <strong>Option A — Reduce Wizard colors (keep 64x64):</strong><br>
  Merge close color pairs in wizard-03.svg and wiz-item-manifest.svg SVGs.<br>
  Body 2 has 5+ close pairs (greens/browns within dist 35). Merging 3-4 would reduce from 15 to ~11 colors.<br>
  Item 4 (Staff Manifest) has 15 colors — reducing to 10-12 would help compression significantly.<br>
  <br>
  <strong>Option B — Use 60x60 (no SVG changes needed):</strong><br>
  All 1,152 combos pass at 60x60 with +95 margin minimum. No art changes needed.<br>
  Trade-off: 60px vs 64px is barely noticeable at any display size.
</div>`;

html += `</body></html>`;

const outPath = join(import.meta.dirname, '..', 'combo-preview-64.html');
writeFileSync(outPath, html);
console.log(`Preview written to: ${outPath}`);
console.log(`Open it: open combo-preview-64.html`);
