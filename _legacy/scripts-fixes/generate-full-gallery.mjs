#!/usr/bin/env node
/**
 * generate-full-gallery.mjs — Render EVERY combo for all 7 classes at 64x64.
 * Shows all body×face×item combinations as a grid per class.
 */
import { readFileSync, readdirSync, writeFileSync } from 'fs';
import { join } from 'path';
import { deflateRawSync, constants as zlibConstants } from 'zlib';

const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');
const CS = 64, CX = 28, LIMIT = 2048;
const NAMES = ['Wizard','King','Knight','Apprentice','Peasant','Gnome','Elf'];
function fci(ci) { return ci === 5 ? 5 : ci === 6 ? 6 : 0; }

const pb = readFileSync(join(TRAITS_DIR, 'palette.bin'));
const pc = pb.readUInt16BE(0);
const pr = new Uint8Array(pc * 3);
for (let i = 0; i < pc * 3; i++) pr[i] = pb[2 + i];

const traits = {};
for (const f of readdirSync(TRAITS_DIR).filter(f => f.startsWith('trait-') && f.endsWith('.bin'))) {
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
function quantize(canvas,palette,w,h,maxC){const cs=new Set();for(let i=0;i<w*h;i++)cs.add(canvas[i]);const uv=Array.from(cs);if(uv.length<=maxC)return;const colors=uv.map(v=>{if(v===0)return{v,r:0,g:0,b:0};const po=(v-1)*3;return po+2<palette.length?{v,r:palette[po],g:palette[po+1],b:palette[po+2]}:{v,r:0,g:0,b:0};});while(colors.length>maxC){let md=Infinity,mi=-1,mj=-1;for(let i=0;i<colors.length;i++)for(let j=i+1;j<colors.length;j++){const d=(colors[i].r-colors[j].r)**2+(colors[i].g-colors[j].g)**2+(colors[i].b-colors[j].b)**2;if(d<md){md=d;mi=i;mj=j;}}const rv=colors[mj].v,kv=colors[mi].v;colors[mi].r=Math.round((colors[mi].r+colors[mj].r)/2);colors[mi].g=Math.round((colors[mi].g+colors[mj].g)/2);colors[mi].b=Math.round((colors[mi].b+colors[mj].b)/2);colors.splice(mj,1);for(let i=0;i<w*h;i++)if(canvas[i]===rv)canvas[i]=kv;}}
function enc4(canvas,palette,w,h){const used=new Uint8Array(256);for(let i=0;i<w*h;i++)used[canvas[i]]=1;const g2l=new Uint8Array(256);const lr=new Uint8Array(16),lg=new Uint8Array(16),lb=new Uint8Array(16);let lc=0;for(let i=0;i<256;i++){if(!used[i])continue;if(lc>=16)break;g2l[i]=lc;const po=i===0?-1:(i-1)*3;if(po>=0&&po+2<palette.length){lr[lc]=palette[po];lg[lc]=palette[po+1];lb[lc]=palette[po+2];}lc++;}const dw=Math.ceil(w/2),frl=1+dw;const filt=Buffer.alloc(frl*h);const prev=new Uint8Array(dw),cur=new Uint8Array(dw);for(let y=0;y<h;y++){for(let x=0;x<dw;x++){const p0=x*2<w?g2l[canvas[y*w+x*2]]:0;const p1=x*2+1<w?g2l[canvas[y*w+x*2+1]]:0;cur[x]=(p0<<4)|p1;}let bf=0,bs=Infinity;for(let f=0;f<=4;f++){let s=0;for(let x=0;x<dw;x++){const v=(cur[x]-pngP(f,x>0?cur[x-1]:0,prev[x],x>0?prev[x-1]:0))&0xFF;s+=v<128?v:256-v;}if(s<bs){bs=s;bf=f;}}filt[y*frl]=bf;for(let x=0;x<dw;x++)filt[y*frl+1+x]=(cur[x]-pngP(bf,x>0?cur[x-1]:0,prev[x],x>0?prev[x-1]:0))&0xFF;cur.forEach((v,i)=>{prev[i]=v;});}const defl=deflateRawSync(filt,{level:6,strategy:zlibConstants.Z_FIXED});const adl=adler32(filt);const zl=2+defl.length+4;const zb=Buffer.alloc(zl);zb[0]=0x78;zb[1]=0x01;defl.copy(zb,2);zb.writeUInt32BE(adl,2+defl.length);const ps=8+25+(12+lc*3)+(12+zl)+12;const png=Buffer.alloc(ps);let off=0;Buffer.from([137,80,78,71,13,10,26,10]).copy(png,off);off+=8;const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=4;ih[9]=3;off=wc(png,off,'IHDR',ih);const pl=Buffer.alloc(lc*3);for(let i=0;i<lc;i++){pl[i*3]=lr[i];pl[i*3+1]=lg[i];pl[i*3+2]=lb[i];}off=wc(png,off,'PLTE',pl);off=wc(png,off,'IDAT',zb);off=wc(png,off,'IEND',Buffer.alloc(0));return png.subarray(0,off);}
function receipt(cn,buf){const b64=buf.toString('base64');const json=`{"name":"${cn} #777","image":"data:image/png;base64,${b64}"}`;let uj='';for(let i=0;i<json.length;i++){const c=json.charCodeAt(i);if(c===0x22)uj+='%22';else if(c===0x7B)uj+='%7B';else if(c===0x7D)uj+='%7D';else if(c===0x23)uj+='%23';else if(c===0x20)uj+='%20';else uj+=json[i];}return 4+('data:application/json,'+uj).length;}

const bgR=0xF7,bgG=0x93,bgB=0x1A;let bgVal=0;
for(let i=0;i<pc;i++){if(pr[i*3]===bgR&&pr[i*3+1]===bgG&&pr[i*3+2]===bgB){bgVal=i+1;break;}}
let usePal=pr;if(bgVal===0){usePal=new Uint8Array(pr.length+3);usePal.set(pr);usePal[pr.length]=bgR;usePal[pr.length+1]=bgG;usePal[pr.length+2]=bgB;bgVal=Math.floor(pr.length/3)+1;}

const FACE_LABELS = ['Classic','Happy','Angry','Feels Bad','Grinding','Chill','Grumpy','Giga Happy','Cooked','Comfy','Retard','Laser'];

const BODY_LABELS = {
    0: ['Wizard I','Wizard II','Wizard III','Wizard IV','Wizard V','Wizard VI','Wizard Manifest','Wizard BTC'],
    1: ['King Black','King Blue','King Orange','King Red','King White'],
    2: ['Knight Bronze','Knight Gold','Knight Orange','Knight Silver'],
    3: ['Apprentice I','Apprentice II','Apprentice Orange'],
    4: ['Peasant I','Peasant II'],
    5: ['Gnome I','Gnome II'],
    6: ['Elf I','Elf II','Elf III'],
};

const ITEM_LABELS = {
    0: ['Staff I','Staff II','Staff III','Staff IV','Staff Manifest'],
    1: ['Scepter Black','Scepter Blue','Scepter Red','Scepter White'],
    2: ['Shield Bronze','Shield Gold','Shield Orange','Shield Silver'],
    3: ['Apprentice Tool'],
    4: ['Pitchfork','Shovel','Hoe'],
    5: ['Gnome Tool I','Gnome Tool II','Gnome Tool III','BTC Pickaxe'],
    6: ['Elf Tool'],
};

let html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Full Gallery — All Combos 64x64</title>
<style>
* { box-sizing: border-box; }
body { background:#111; color:#eee; font-family:monospace; padding:12px; margin:0; }
h1 { color:#f7931a; margin:0 0 8px; font-size:20px; }
h2 { color:#4fc3f7; margin:24px 0 4px; font-size:16px; border-bottom:1px solid #333; padding-bottom:4px; }
h3 { color:#81c784; margin:12px 0 4px; font-size:13px; }
.class-section { margin-bottom:32px; }
.body-section { margin-bottom:16px; }
.face-row { display:flex; flex-wrap:wrap; gap:4px; margin-bottom:2px; }
.cell { text-align:center; width:80px; }
.cell img { width:64px; height:64px; image-rendering:pixelated; display:block; margin:0 auto; }
.cell .info { font-size:9px; color:#999; line-height:1.1; }
.cell .info.warn { color:#ffeb3b; }
.cell .info.fail { color:#f44336; }
.item-header { display:flex; gap:4px; margin-bottom:2px; }
.item-label { width:80px; text-align:center; font-size:9px; color:#666; }
.face-label { font-size:10px; color:#aaa; margin-right:4px; min-width:70px; display:flex; align-items:center; }
.row-wrap { display:flex; align-items:flex-start; margin-bottom:2px; }
.stats { background:#1a1a2e; padding:8px 12px; border-radius:6px; margin:4px 0; font-size:12px; }
</style></head><body>
<h1>Full Gallery — All 1,152 Combos at 64x64</h1>
<div class="stats">Format: 64x64, 4-bit indexed PNG, 16-color quantization | Limit: 2048 bytes</div>
`;

let totalCombos = 0, totalFails = 0;

for (let ci = 0; ci < 7; ci++) {
    const fciV = fci(ci);
    const bodies = traits[0]?.[ci] || {};
    const faces = traits[1]?.[fciV] || {};
    const items = traits[2]?.[ci] || {};
    const subs = traits[3]?.[ci === 4 ? 4 : 0] || {};

    const bodyKeys = Object.keys(bodies).sort((a,b) => +a - +b);
    const faceKeys = Object.keys(faces).sort((a,b) => +a - +b);
    const itemKeys = Object.keys(items).sort((a,b) => +a - +b);

    const classTotal = bodyKeys.length * faceKeys.length * itemKeys.length;

    html += `<div class="class-section">`;
    html += `<h2>${NAMES[ci]} — ${bodyKeys.length} bodies × ${faceKeys.length} faces × ${itemKeys.length} items = ${classTotal} combos</h2>`;

    let classFails = 0;

    for (const bi of bodyKeys) {
        html += `<div class="body-section">`;
        html += `<h3>${BODY_LABELS[ci]?.[+bi] || `Body ${bi}`}</h3>`;

        // Item headers
        if (itemKeys.length > 1) {
            html += `<div class="row-wrap"><div class="face-label"></div><div class="item-header">`;
            for (const ii of itemKeys) {
                html += `<div class="item-label">${ITEM_LABELS[ci]?.[+ii] || `Item ${ii}`}</div>`;
            }
            html += `</div></div>`;
        }

        // Face rows
        for (const fi of faceKeys) {
            html += `<div class="row-wrap">`;
            html += `<div class="face-label">${FACE_LABELS[+fi] || `F${fi}`}</div>`;
            html += `<div class="face-row">`;

            for (const ii of itemKeys) {
                const c = new Uint8Array(120 * 120);
                comp(c, faces[fi], 120);
                comp(c, bodies[bi], 120);
                comp(c, items[ii], 120);
                const sk = Object.keys(subs); if (sk.length > 0) comp(c, subs[sk[0]], 120);

                const crop = new Uint8Array(CS * CS);
                for (let dy = 0; dy < CS; dy++) for (let dx = 0; dx < CS; dx++) {
                    const v = c[(CX + dy) * 120 + (CX + dx)];
                    crop[dy * CS + dx] = v === 0 ? bgVal : v;
                }

                quantize(crop, usePal, CS, CS, 16);
                const png = enc4(crop, usePal, CS, CS);
                const r = receipt(NAMES[ci], png);
                const margin = LIMIT - r;
                const ok = r <= LIMIT;
                if (!ok) { classFails++; totalFails++; }
                totalCombos++;

                const b64 = png.toString('base64');
                const infoClass = !ok ? 'fail' : margin < 30 ? 'warn' : '';

                html += `<div class="cell">`;
                html += `<img src="data:image/png;base64,${b64}">`;
                html += `<div class="info ${infoClass}">${r}B ${ok ? '+' : ''}${margin}</div>`;
                html += `</div>`;
            }

            html += `</div></div>`;
        }
        html += `</div>`; // body-section
    }

    html += `<div class="stats">${NAMES[ci]}: ${classFails}/${classTotal} fails | worst margin: check above</div>`;
    html += `</div>`; // class-section
}

html += `<div class="stats" style="font-size:14px;margin-top:20px;">TOTAL: ${totalFails}/${totalCombos} fails</div>`;
html += `</body></html>`;

const outPath = join(import.meta.dirname, '..', 'full-gallery-64.html');
writeFileSync(outPath, html);
console.log(`Full gallery: ${outPath}`);
console.log(`${totalCombos} combos rendered, ${totalFails} fails`);
