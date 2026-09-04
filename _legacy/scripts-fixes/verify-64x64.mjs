#!/usr/bin/env node
/**
 * verify-64x64.mjs — Exhaustive check: 64x64, 4-bit, 16-color, fixed Huffman
 * Tests EVERY body×face×item combination for all 7 classes.
 */
import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { deflateRawSync, constants as zlibConstants } from 'zlib';

const TRAITS_DIR = join(import.meta.dirname, '..', 'compressed-traits');
const CS = 64;
const CX = 28; // (120-64)/2
const LIMIT = 2048;
const NAMES = ['Wizard','King','Knight','Apprentice','Peasant','Gnome','Elf'];

function faceClassIdx(ci) { return ci === 5 ? 5 : ci === 6 ? 6 : 0; }

const palBin = readFileSync(join(TRAITS_DIR, 'palette.bin'));
const palCount = palBin.readUInt16BE(0);
const palRGB = new Uint8Array(palCount * 3);
for (let i = 0; i < palCount * 3; i++) palRGB[i] = palBin[2 + i];

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
    const T=new Uint32Array(256); for(let i=0;i<256;i++){let c=i;for(let j=0;j<8;j++)c=(c&1)?(0xEDB88320^(c>>>1)):(c>>>1);T[i]=c;}
    let crc=0xFFFFFFFF; for(let i=0;i<buf.length;i++)crc=T[(crc^buf[i])&0xFF]^(crc>>>8); return (crc^0xFFFFFFFF)>>>0;
}
function writeChunk(png, off, type, data) {
    png.writeUInt32BE(data.length,off);off+=4; png.write(type,off,4,'ascii');off+=4;
    data.copy(png,off);off+=data.length; png.writeUInt32BE(crc32(png.subarray(off-data.length-4,off)),off);off+=4; return off;
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

function encode4bitPNG(canvas, palette, w, h) {
    const used=new Uint8Array(256);
    for(let i=0;i<w*h;i++) used[canvas[i]]=1;
    const g2l=new Uint8Array(256);
    const lr=new Uint8Array(16),lg=new Uint8Array(16),lb=new Uint8Array(16);
    let lc=0;
    for(let i=0;i<256;i++){
        if(!used[i])continue; if(lc>=16)break; g2l[i]=lc;
        const po=i===0?-1:(i-1)*3;
        if(po>=0&&po+2<palette.length){lr[lc]=palette[po];lg[lc]=palette[po+1];lb[lc]=palette[po+2];}
        lc++;
    }
    const dw=Math.ceil(w/2), frl=1+dw;
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
    const zb=Buffer.alloc(zl);
    zb[0]=0x78;zb[1]=0x01;
    defl.copy(zb,2);zb.writeUInt32BE(adl,2+defl.length);
    const ps=8+25+(12+lc*3)+(12+zl)+12;
    const png=Buffer.alloc(ps);let off=0;
    Buffer.from([137,80,78,71,13,10,26,10]).copy(png,off);off+=8;
    const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=4;ih[9]=3;
    off=writeChunk(png,off,'IHDR',ih);
    const pl=Buffer.alloc(lc*3);
    for(let i=0;i<lc;i++){pl[i*3]=lr[i];pl[i*3+1]=lg[i];pl[i*3+2]=lb[i];}
    off=writeChunk(png,off,'PLTE',pl);
    off=writeChunk(png,off,'IDAT',zb);
    off=writeChunk(png,off,'IEND',Buffer.alloc(0));
    return png.subarray(0,off);
}

function buildReceipt(cn, pngBuf) {
    const b64=pngBuf.toString('base64');
    const json=`{"name":"${cn} #777","image":"data:image/png;base64,${b64}"}`;
    let uj='';
    for(let i=0;i<json.length;i++){
        const c=json.charCodeAt(i);
        if(c===0x22)uj+='%22';else if(c===0x7B)uj+='%7B';else if(c===0x7D)uj+='%7D';else if(c===0x23)uj+='%23';else if(c===0x20)uj+='%20';else uj+=json[i];
    }
    return 4+('data:application/json,'+uj).length;
}

// Find background
const bgR=0xF7,bgG=0x93,bgB=0x1A;
let bgVal=0;
for(let i=0;i<palCount;i++){if(palRGB[i*3]===bgR&&palRGB[i*3+1]===bgG&&palRGB[i*3+2]===bgB){bgVal=i+1;break;}}
let usePal=palRGB;
if(bgVal===0){usePal=new Uint8Array(palRGB.length+3);usePal.set(palRGB);usePal[palRGB.length]=bgR;usePal[palRGB.length+1]=bgG;usePal[palRGB.length+2]=bgB;bgVal=Math.floor(palRGB.length/3)+1;}

console.log('=== EXHAUSTIVE: 64x64, 4-bit, 16-color, fixed Huffman ===');
console.log(`Crop: ${CS}x${CS}, offset: (${CX},${CX}), limit: ${LIMIT} bytes\n`);

let allOk = true;
let grandTotal = 0, grandFails = 0;

for (let ci = 0; ci < NAMES.length; ci++) {
    const fci = faceClassIdx(ci);
    const bodies = traits[0]?.[ci] || {};
    const faces = traits[1]?.[fci] || {};
    const items = traits[2]?.[ci] || {};
    const subs = traits[3]?.[ci === 4 ? 4 : 0] || {};

    let worst = 0, total = 0, fails = 0, worstCombo = '';

    for (const bi of Object.keys(bodies)) {
        for (const fi of Object.keys(faces)) {
            for (const ii of Object.keys(items)) {
                const c = new Uint8Array(120 * 120);
                compositeLayer(c, faces[fi], 120);
                compositeLayer(c, bodies[bi], 120);
                compositeLayer(c, items[ii], 120);
                const sk = Object.keys(subs);
                if (sk.length > 0) compositeLayer(c, subs[sk[0]], 120);

                const crop = new Uint8Array(CS * CS);
                for (let dy = 0; dy < CS; dy++)
                    for (let dx = 0; dx < CS; dx++) {
                        const v = c[(CX + dy) * 120 + (CX + dx)];
                        crop[dy * CS + dx] = v === 0 ? bgVal : v;
                    }

                quantizeColors(crop, usePal, CS, CS, 16);
                const png = encode4bitPNG(crop, usePal, CS, CS);
                const r = buildReceipt(NAMES[ci], png);
                if (r > worst) { worst = r; worstCombo = `b${bi}f${fi}i${ii}`; }
                if (r > LIMIT) fails++;
                total++;
            }
        }
    }

    const ok = fails === 0;
    if (!ok) allOk = false;
    grandTotal += total;
    grandFails += fails;

    const margin = LIMIT - worst;
    const status = ok ? 'OK' : 'FAIL';
    console.log(`${NAMES[ci].padEnd(12)} worst=${worst} margin=${margin >= 0 ? '+' : ''}${margin}  combos=${total}  fails=${fails}  ${status}  [${worstCombo}]`);
}

console.log(`\nTotal: ${grandTotal} combos, ${grandFails} fails`);
console.log(allOk ? '\nALL 7 CLASSES FIT WITHIN 2048 BYTES' : '\nSOME CLASSES FAIL — NEEDS FIX');
