#!/usr/bin/env node
/**
 * test-png-visual.mjs — Generate 100 random NFT PNGs at 60×60 4-bit/16-color
 * and output them as data URIs in an HTML file for visual inspection.
 * Also generates 8-bit originals side-by-side for quality comparison.
 */
import { readFileSync, readdirSync, writeFileSync } from 'fs';
import { join } from 'path';
import { deflateRawSync, constants as zlibConstants } from 'zlib';

const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');
const CANVAS_SIDE = 120;
const RECEIPT_LIMIT = 2048;
const CLASS_NAMES = ['Wizard', 'King', 'Knight', 'Apprentice', 'Peasant', 'Gnome', 'Elf'];
// Class weights (cumulative BPS out of 10000) for random class selection
const CLASS_WEIGHTS = [4400, 6600, 8350, 8680, 8900, 9560, 10000];

function faceClassIdx(ci) { return ci === 5 ? 5 : ci === 6 ? 6 : 0; }

// Read palette
const palBin = readFileSync(join(TRAITS_DIR, 'palette.bin'));
const palCount = palBin.readUInt16BE(0);
const palRGB = new Uint8Array(palCount * 3);
for (let i = 0; i < palCount * 3; i++) palRGB[i] = palBin[2 + i];

// Read traits
const traits = {};
for (const f of readdirSync(TRAITS_DIR).filter(f => f.startsWith('trait-') && f.endsWith('.bin'))) {
    const d = readFileSync(join(TRAITS_DIR, f));
    if (!traits[d[0]]) traits[d[0]] = {};
    if (!traits[d[0]][d[1]]) traits[d[0]][d[1]] = {};
    traits[d[0]][d[1]][d[2]] = d;
}

function compositeLayer(canvas, ld, cs) {
    if (!ld || ld.length < 10) return;
    const [,,, mx, my, bw, bh, lps] = ld;
    if (!lps || !bw || !bh) return;
    const ps = 8, pds = ps + lps;
    if (pds >= ld.length) return;
    for (let p = 0; p < bw * bh; p++) {
        const bo = pds + (p >> 1);
        if (bo >= ld.length) break;
        const nb = ((p & 1) === 0) ? (ld[bo] >> 4) & 0xF : ld[bo] & 0xF;
        if (nb === 0) continue;
        const li = nb - 1;
        if (li >= lps) continue;
        const ax = mx + (p % bw), ay = my + Math.floor(p / bw);
        if (ax < cs && ay < cs) canvas[ay * cs + ax] = ld[ps + li] + 1;
    }
}

function pngPredict(f, a, b, c) {
    if (f <= 0) return 0;
    if (f === 1) return a;
    if (f === 2) return b;
    if (f === 3) return (a + b) >> 1;
    const p = a + b - c;
    if (Math.abs(p - a) <= Math.abs(p - b) && Math.abs(p - a) <= Math.abs(p - c)) return a;
    if (Math.abs(p - b) <= Math.abs(p - c)) return b;
    return c;
}

function adler32(d) { let a=1,b=0; for(let i=0;i<d.length;i++){a=(a+d[i])%65521;b=(b+a)%65521;} return ((b<<16)|a)>>>0; }
function crc32(buf) {
    const T=new Uint32Array(256);
    for(let i=0;i<256;i++){let c=i;for(let j=0;j<8;j++)c=(c&1)?(0xEDB88320^(c>>>1)):(c>>>1);T[i]=c;}
    let crc=0xFFFFFFFF;for(let i=0;i<buf.length;i++)crc=T[(crc^buf[i])&0xFF]^(crc>>>8);return (crc^0xFFFFFFFF)>>>0;
}
function writeChunk(png, off, type, data) {
    png.writeUInt32BE(data.length,off);off+=4;png.write(type,off,4,'ascii');off+=4;
    data.copy(png,off);off+=data.length;png.writeUInt32BE(crc32(png.subarray(off-data.length-4,off)),off);off+=4;return off;
}

function quantizeColors(canvas, palette, w, h, maxC) {
    const cs = new Set();
    for (let i = 0; i < w*h; i++) cs.add(canvas[i]);
    const uv = Array.from(cs);
    if (uv.length <= maxC) return uv.length;
    const colors = uv.map(v => {
        if (v===0) return {v,r:0,g:0,b:0};
        const po=(v-1)*3;
        return po+2<palette.length?{v,r:palette[po],g:palette[po+1],b:palette[po+2]}:{v,r:0,g:0,b:0};
    });
    while(colors.length>maxC){
        let md=Infinity,mi=-1,mj=-1;
        for(let i=0;i<colors.length;i++)for(let j=i+1;j<colors.length;j++){
            const d=(colors[i].r-colors[j].r)**2+(colors[i].g-colors[j].g)**2+(colors[i].b-colors[j].b)**2;
            if(d<md){md=d;mi=i;mj=j;}
        }
        const rv=colors[mj].v, kv=colors[mi].v;
        colors[mi].r=Math.round((colors[mi].r+colors[mj].r)/2);
        colors[mi].g=Math.round((colors[mi].g+colors[mj].g)/2);
        colors[mi].b=Math.round((colors[mi].b+colors[mj].b)/2);
        colors.splice(mj,1);
        for(let i=0;i<w*h;i++) if(canvas[i]===rv) canvas[i]=kv;
    }
    return colors.length;
}

// 4-bit PNG encoder
function encode4bitPNG(canvas, palette, w, h) {
    const used=new Uint8Array(256);
    for(let i=0;i<w*h;i++) used[canvas[i]]=1;
    const g2l=new Uint8Array(256);
    const lr=new Uint8Array(16),lg2=new Uint8Array(16),lb=new Uint8Array(16);
    let lc=0;
    for(let i=0;i<256;i++){
        if(!used[i])continue;if(lc>=16)break;g2l[i]=lc;
        const po=i===0?-1:(i-1)*3;
        if(po>=0&&po+2<palette.length){lr[lc]=palette[po];lg2[lc]=palette[po+1];lb[lc]=palette[po+2];}
        lc++;
    }
    const dw=Math.ceil(w/2),frl=1+dw;
    const filt=Buffer.alloc(frl*h);
    const prev=new Uint8Array(dw),cur=new Uint8Array(dw);
    for(let y=0;y<h;y++){
        for(let x=0;x<dw;x++){
            const p0=x*2<w?g2l[canvas[y*w+x*2]]:0;
            const p1=x*2+1<w?g2l[canvas[y*w+x*2+1]]:0;
            cur[x]=(p0<<4)|p1;
        }
        let bf=0,bs=Infinity;
        for(let f=0;f<=4;f++){
            let s=0;
            for(let x=0;x<dw;x++){
                const v=(cur[x]-pngPredict(f,x>0?cur[x-1]:0,prev[x],x>0?prev[x-1]:0))&0xFF;
                s+=v<128?v:256-v;
            }
            if(s<bs){bs=s;bf=f;}
        }
        filt[y*frl]=bf;
        for(let x=0;x<dw;x++)
            filt[y*frl+1+x]=(cur[x]-pngPredict(bf,x>0?cur[x-1]:0,prev[x],x>0?prev[x-1]:0))&0xFF;
        cur.forEach((v,i)=>{prev[i]=v;});
    }
    const defl=deflateRawSync(filt,{level:6,strategy:zlibConstants.Z_FIXED});
    const adl=adler32(filt);
    const zl=2+defl.length+4;
    const zb=Buffer.alloc(zl);zb[0]=0x78;zb[1]=0x01;defl.copy(zb,2);zb.writeUInt32BE(adl,2+defl.length);
    const ps2=8+25+(12+lc*3)+(12+zl)+12;
    const png=Buffer.alloc(ps2);let off=0;
    Buffer.from([137,80,78,71,13,10,26,10]).copy(png,off);off+=8;
    const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=4;ih[9]=3;
    off=writeChunk(png,off,'IHDR',ih);
    const pl=Buffer.alloc(lc*3);
    for(let i=0;i<lc;i++){pl[i*3]=lr[i];pl[i*3+1]=lg2[i];pl[i*3+2]=lb[i];}
    off=writeChunk(png,off,'PLTE',pl);
    off=writeChunk(png,off,'IDAT',zb);
    off=writeChunk(png,off,'IEND',Buffer.alloc(0));
    return png.subarray(0,off);
}

// 8-bit PNG encoder (full color, no quantization)
function encode8bitPNG(canvas, palette, w, h) {
    const used=new Uint8Array(256);
    for(let i=0;i<w*h;i++) used[canvas[i]]=1;
    const g2l=new Uint8Array(256);
    const lr=new Uint8Array(256),lg2=new Uint8Array(256),lb=new Uint8Array(256);
    let lc=0;
    for(let i=0;i<256;i++){
        if(!used[i])continue;g2l[i]=lc;
        const po=i===0?-1:(i-1)*3;
        if(po>=0&&po+2<palette.length){lr[lc]=palette[po];lg2[lc]=palette[po+1];lb[lc]=palette[po+2];}
        lc++;
    }
    const frl=1+w;
    const filt=Buffer.alloc(frl*h);
    const prev=new Uint8Array(w),cur=new Uint8Array(w);
    for(let y=0;y<h;y++){
        for(let x=0;x<w;x++) cur[x]=g2l[canvas[y*w+x]];
        let bf=0,bs=Infinity;
        for(let f=0;f<=4;f++){
            let s=0;
            for(let x=0;x<w;x++){
                const v=(cur[x]-pngPredict(f,x>0?cur[x-1]:0,prev[x],x>0?prev[x-1]:0))&0xFF;
                s+=v<128?v:256-v;
            }
            if(s<bs){bs=s;bf=f;}
        }
        filt[y*frl]=bf;
        for(let x=0;x<w;x++)
            filt[y*frl+1+x]=(cur[x]-pngPredict(bf,x>0?cur[x-1]:0,prev[x],x>0?prev[x-1]:0))&0xFF;
        cur.forEach((v,i)=>{prev[i]=v;});
    }
    const defl=deflateRawSync(filt,{level:6,strategy:zlibConstants.Z_FIXED});
    const adl=adler32(filt);
    const zl=2+defl.length+4;
    const zb=Buffer.alloc(zl);zb[0]=0x78;zb[1]=0x01;defl.copy(zb,2);zb.writeUInt32BE(adl,2+defl.length);
    const ps2=8+25+(12+lc*3)+(12+zl)+12;
    const png=Buffer.alloc(ps2);let off=0;
    Buffer.from([137,80,78,71,13,10,26,10]).copy(png,off);off+=8;
    const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=8;ih[9]=3;
    off=writeChunk(png,off,'IHDR',ih);
    const pl=Buffer.alloc(lc*3);
    for(let i=0;i<lc;i++){pl[i*3]=lr[i];pl[i*3+1]=lg2[i];pl[i*3+2]=lb[i];}
    off=writeChunk(png,off,'PLTE',pl);
    off=writeChunk(png,off,'IDAT',zb);
    off=writeChunk(png,off,'IEND',Buffer.alloc(0));
    return png.subarray(0,off);
}

function buildReceipt(cn, tid, pngBuf) {
    const b64=pngBuf.toString('base64');
    const json=`{"name":"${cn} #${tid}","image":"data:image/png;base64,${b64}"}`;
    let uj='';
    for(let i=0;i<json.length;i++){
        const c=json.charCodeAt(i);
        if(c===0x22)uj+='%22';else if(c===0x7B)uj+='%7B';else if(c===0x7D)uj+='%7D';else if(c===0x23)uj+='%23';else if(c===0x20)uj+='%20';else uj+=json[i];
    }
    return {
        receipt: 4+('data:application/json,'+uj).length,
        dataUri: 'data:application/json,'+uj,
        b64
    };
}

// Find background
const bgR=0xF7,bgG=0x93,bgB=0x1A;
let bgVal=0;
for(let i=0;i<palCount;i++){if(palRGB[i*3]===bgR&&palRGB[i*3+1]===bgG&&palRGB[i*3+2]===bgB){bgVal=i+1;break;}}
let usePal=palRGB;
if(bgVal===0){
    usePal=new Uint8Array(palRGB.length+3);usePal.set(palRGB);
    usePal[palRGB.length]=bgR;usePal[palRGB.length+1]=bgG;usePal[palRGB.length+2]=bgB;
    bgVal=Math.floor(palRGB.length/3)+1;
}

// ── Generate 100 random NFTs ─────────────────────────────────────────────────
function pickRandom(obj) {
    const keys = Object.keys(obj);
    return keys.length > 0 ? Number(keys[Math.floor(Math.random() * keys.length)]) : -1;
}

function randomClass() {
    const r = Math.floor(Math.random() * 10000);
    for (let i = 0; i < CLASS_WEIGHTS.length; i++) {
        if (r < CLASS_WEIGHTS[i]) return i;
    }
    return 6; // Elf
}

const CROP_SIZES = [60, 62, 64, 66];
const nfts = [];

for (let n = 0; n < 100; n++) {
    const ci = randomClass();
    const fci = faceClassIdx(ci);
    const bodies = traits[0]?.[ci] || {};
    const faces = traits[1]?.[fci] || {};
    const items = traits[2]?.[ci] || {};
    const subs = traits[3]?.[ci === 4 ? 4 : 0] || {};

    const bi = pickRandom(bodies);
    const fi = pickRandom(faces);
    const ii = pickRandom(items);
    if (bi < 0 || fi < 0 || ii < 0) continue;

    // Composite on 120×120
    const canvas = new Uint8Array(CANVAS_SIDE * CANVAS_SIDE);
    compositeLayer(canvas, faces[fi], CANVAS_SIDE);
    compositeLayer(canvas, bodies[bi], CANVAS_SIDE);
    compositeLayer(canvas, items[ii], CANVAS_SIDE);
    const sk = Object.keys(subs);
    if (sk.length > 0) compositeLayer(canvas, subs[sk[0]], CANVAS_SIDE);

    const tokenId = n + 1;
    const className = CLASS_NAMES[ci];
    const nft = { tokenId, className, ci, bi, fi, ii, versions: {} };

    for (const cs of CROP_SIZES) {
        const cx = Math.floor((120 - cs) / 2);

        // 8-bit original (full color)
        const crop8 = new Uint8Array(cs * cs);
        for (let dy = 0; dy < cs; dy++)
            for (let dx = 0; dx < cs; dx++) {
                const v = canvas[(cx + dy) * CANVAS_SIDE + (cx + dx)];
                crop8[dy * cs + dx] = v === 0 ? bgVal : v;
            }
        const origColors = new Set(crop8).size;
        const png8 = encode8bitPNG(crop8, usePal, cs, cs);
        const r8 = buildReceipt(className, tokenId, png8);

        // 4-bit with 16-color quantization
        const crop4 = crop8.slice();
        const qColors = quantizeColors(crop4, usePal, cs, cs, 16);
        const png4 = encode4bitPNG(crop4, usePal, cs, cs);
        const r4 = buildReceipt(className, tokenId, png4);

        nft.versions[cs] = {
            orig: { b64: 'data:image/png;base64,' + png8.toString('base64'), receipt: r8.receipt, colors: origColors },
            quant: { b64: 'data:image/png;base64,' + png4.toString('base64'), receipt: r4.receipt, colors: qColors },
            dataUri: r4.dataUri,
        };
    }

    nfts.push(nft);
}

// ── Build HTML ───────────────────────────────────────────────────────────────
let html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>MiFrens PNG Quality Comparison — 8-bit vs 4-bit/16-color</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: #111; color: #eee; font-family: 'JetBrains Mono', 'Fira Code', monospace; padding: 20px; }
h1 { text-align: center; margin-bottom: 10px; font-size: 20px; color: #F7931A; }
.subtitle { text-align: center; color: #888; margin-bottom: 20px; font-size: 13px; }
.controls { text-align: center; margin-bottom: 20px; }
.controls button { background: #222; border: 1px solid #444; color: #eee; padding: 6px 14px; cursor: pointer; border-radius: 4px; margin: 0 4px; font-family: inherit; }
.controls button.active { background: #F7931A; color: #000; border-color: #F7931A; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 12px; }
.card { background: #1a1a1a; border-radius: 8px; padding: 10px; border: 1px solid #333; }
.card .pair { display: flex; gap: 6px; justify-content: center; margin-bottom: 6px; }
.card .pair div { text-align: center; }
.card .pair img { width: 80px; height: 80px; image-rendering: pixelated; border: 1px solid #333; }
.card .pair .label { font-size: 9px; color: #888; margin-top: 2px; }
.card .info { font-size: 10px; color: #aaa; line-height: 1.5; }
.card .info .ok { color: #4CAF50; }
.card .info .fail { color: #f44336; }
.card .name { font-size: 12px; font-weight: bold; color: #F7931A; margin-bottom: 4px; }
.stats { background: #1a1a1a; border: 1px solid #333; border-radius: 8px; padding: 16px; margin-bottom: 20px; }
.stats table { width: 100%; border-collapse: collapse; font-size: 12px; }
.stats th { text-align: left; color: #F7931A; padding: 4px 8px; border-bottom: 1px solid #333; }
.stats td { padding: 4px 8px; }
.stats .ok { color: #4CAF50; }
.stats .fail { color: #f44336; font-weight: bold; }
.hidden { display: none; }
.metadata-box { background: #0a0a0a; border: 1px solid #333; border-radius: 4px; padding: 8px; margin-top: 6px; font-size: 9px; word-break: break-all; color: #666; max-height: 60px; overflow-y: auto; cursor: pointer; }
.metadata-box:hover { color: #aaa; }
</style>
</head>
<body>
<h1>MiFrens On-Chain PNG — Quality Comparison</h1>
<p class="subtitle">Left: 8-bit original (all colors) | Right: 4-bit / 16-color quantized | Receipt limit: 2048 bytes</p>

<div class="controls">
  <span style="color:#888;margin-right:8px;">Crop size:</span>
`;

for (const cs of CROP_SIZES) {
    html += `  <button onclick="showSize(${cs})" id="btn-${cs}" class="${cs===60?'active':''}">${cs}×${cs}</button>\n`;
}

html += `</div>\n`;

// Stats table
html += `<div class="stats">\n<table>\n<tr><th>Crop</th><th>8-bit Pass</th><th>8-bit Fail</th><th>4-bit/16c Pass</th><th>4-bit/16c Fail</th><th>4-bit Worst</th></tr>\n`;
for (const cs of CROP_SIZES) {
    let pass8 = 0, fail8 = 0, pass4 = 0, fail4 = 0, worst4 = 0;
    for (const nft of nfts) {
        const v = nft.versions[cs];
        if (v.orig.receipt <= RECEIPT_LIMIT) pass8++; else fail8++;
        if (v.quant.receipt <= RECEIPT_LIMIT) pass4++; else fail4++;
        if (v.quant.receipt > worst4) worst4 = v.quant.receipt;
    }
    html += `<tr><td>${cs}×${cs}</td><td class="ok">${pass8}</td><td class="${fail8?'fail':'ok'}">${fail8}</td><td class="ok">${pass4}</td><td class="${fail4?'fail':'ok'}">${fail4}</td><td class="${worst4>RECEIPT_LIMIT?'fail':'ok'}">${worst4}</td></tr>\n`;
}
html += `</table>\n</div>\n`;

// Cards for each crop size
for (const cs of CROP_SIZES) {
    html += `<div class="grid size-grid" id="grid-${cs}" ${cs!==60?'style="display:none"':''}>\n`;
    for (const nft of nfts) {
        const v = nft.versions[cs];
        const ok8 = v.orig.receipt <= RECEIPT_LIMIT;
        const ok4 = v.quant.receipt <= RECEIPT_LIMIT;
        html += `<div class="card">
  <div class="name">${nft.className} #${nft.tokenId}</div>
  <div class="pair">
    <div><img src="${v.orig.b64}" alt="8-bit"><div class="label">8-bit (${v.orig.colors}c)</div></div>
    <div><img src="${v.quant.b64}" alt="4-bit"><div class="label">4-bit (${v.quant.colors}c)</div></div>
  </div>
  <div class="info">
    8-bit: <span class="${ok8?'ok':'fail'}">${v.orig.receipt}B</span> |
    4-bit: <span class="${ok4?'ok':'fail'}">${v.quant.receipt}B</span>
  </div>
  <div class="metadata-box" onclick="this.style.maxHeight=this.style.maxHeight==='none'?'60px':'none'">${v.dataUri.substring(0, 200)}...</div>
</div>\n`;
    }
    html += `</div>\n`;
}

html += `
<script>
function showSize(cs) {
    document.querySelectorAll('.size-grid').forEach(g => g.style.display = 'none');
    document.querySelectorAll('.controls button').forEach(b => b.classList.remove('active'));
    document.getElementById('grid-' + cs).style.display = 'grid';
    document.getElementById('btn-' + cs).classList.add('active');
}
</script>
</body>
</html>`;

const outPath = join(import.meta.dirname, '..', 'png-quality-comparison.html');
writeFileSync(outPath, html);
console.log(`Generated ${nfts.length} NFTs across ${CROP_SIZES.length} crop sizes`);
console.log(`Output: ${outPath}`);
console.log(`Open in browser to compare quality.\n`);

// Print summary
for (const cs of CROP_SIZES) {
    let pass8=0,fail8=0,pass4=0,fail4=0,worst4=0,worst8=0;
    for (const nft of nfts) {
        const v = nft.versions[cs];
        if(v.orig.receipt<=RECEIPT_LIMIT)pass8++;else fail8++;
        if(v.quant.receipt<=RECEIPT_LIMIT)pass4++;else fail4++;
        if(v.quant.receipt>worst4)worst4=v.quant.receipt;
        if(v.orig.receipt>worst8)worst8=v.orig.receipt;
    }
    console.log(`${cs}×${cs}: 8-bit ${pass8}✓/${fail8}✗ (worst ${worst8}) | 4-bit/16c ${pass4}✓/${fail4}✗ (worst ${worst4})`);
}

// Print first 3 full data URIs as example metadata
console.log('\n── Example tokenURI metadata (first 3, 60×60 4-bit) ──\n');
for (let i = 0; i < 3 && i < nfts.length; i++) {
    const nft = nfts[i];
    const v = nft.versions[60];
    console.log(`#${nft.tokenId} ${nft.className} (${v.quant.receipt}B):`);
    console.log(v.dataUri);
    console.log('');
}
