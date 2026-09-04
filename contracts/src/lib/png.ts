// ---------------------------------------------------------------------------
// png.ts — Indexed-color PNG encoder for OPNet smart contracts.
//
// Supports two modes:
//   1. encodePNG:     8-bit (256-color) indexed PNG with optional transparency
//   2. encodePNG4bit: 4-bit (16-color) indexed PNG for compact tokenURI
//
// Both use:
//   - Adaptive row filter (None/Sub/Up/Average/Paeth per row, min-sum heuristic)
//   - Fixed Huffman DEFLATE with LZ77 + lazy matching (RFC 1951)
//   - CRC32 checksums on all PNG chunks
//
// Also provides quantizeColors() for reducing unique canvas values to ≤N
// by greedy closest-pair RGB merging.
//
// Designed to fit within OPNet's 2,048-byte receipt limit at 60×60 resolution
// with 4-bit encoding + 16-color quantization + URL-encoded JSON tokenURI.
// ---------------------------------------------------------------------------

// ---- CRC32 Lookup Table (IEEE polynomial, computed at runtime) -----------
// Computed lazily to avoid @inline StaticArray<u32> miscompilation in WASM.
// The @inline decorator on large StaticArray<u32> causes incorrect memory
// access patterns in the OPNet WASM VM, producing wrong CRC values.

let _crc32Table: StaticArray<u32> | null = null;

function ensureCRC32Table(): StaticArray<u32> {
    if (_crc32Table !== null) return _crc32Table!;
    const t = new StaticArray<u32>(256);
    for (let n: i32 = 0; n < 256; n++) {
        let c: u32 = n as u32;
        for (let k: i32 = 0; k < 8; k++) {
            if (c & 1) {
                c = <u32>0xEDB88320 ^ (c >>> 1);
            } else {
                c = c >>> 1;
            }
        }
        t[n] = c;
    }
    _crc32Table = t;
    return t;
}

// ---- CRC32 computation ---------------------------------------------------

function crc32(data: Uint8Array, start: i32, len: i32): u32 {
    const table = ensureCRC32Table();
    let crc: u32 = 0xFFFFFFFF;
    const end: i32 = start + len;
    for (let i: i32 = start; i < end; i++) {
        crc = table[((crc ^ (data[i] as u32)) & 0xFF) as i32] ^ (crc >>> 8);
    }
    return crc ^ 0xFFFFFFFF;
}

// ---- Adler-32 checksum (zlib) --------------------------------------------

function adler32(data: Uint8Array, start: i32, len: i32): u32 {
    let a: u32 = 1;
    let b: u32 = 0;
    const end: i32 = start + len;
    for (let i: i32 = start; i < end; i++) {
        a = (a + (data[i] as u32)) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

// ---- BitWriter (LSB-first bit packer) ------------------------------------

class BitWriter {
    buf: Uint8Array;
    pos: i32;        // byte position in buf
    bitBuf: u32;     // accumulated bits (up to 25 bits)
    bitCount: i32;   // number of valid bits in bitBuf
    maxPos: i32;     // buffer length guard

    constructor(buf: Uint8Array, startPos: i32) {
        this.buf = buf;
        this.pos = startPos;
        this.bitBuf = 0;
        this.bitCount = 0;
        this.maxPos = buf.length;
    }

    writeBits(value: u32, numBits: i32): void {
        this.bitBuf |= value << this.bitCount;
        this.bitCount += numBits;
        while (this.bitCount >= 8) {
            if (this.pos < this.maxPos) {
                this.buf[this.pos] = (this.bitBuf & 0xFF) as u8;
            }
            this.pos++;
            this.bitBuf >>>= 8;
            this.bitCount -= 8;
        }
    }

    flush(): void {
        if (this.bitCount > 0) {
            if (this.pos < this.maxPos) {
                this.buf[this.pos] = (this.bitBuf & 0xFF) as u8;
            }
            this.pos++;
            this.bitBuf = 0;
            this.bitCount = 0;
        }
    }
}

// ---- Fixed Huffman tables (RFC 1951 section 3.2.6) -----------------------
// Lit/len 0-143: 8 bits, 144-255: 9 bits, 256-279: 7 bits, 280-287: 8 bits

// Length code extra bits (codes 257-285)
// @ts-ignore: decorator
@inline
const LEN_EXTRA_BITS: StaticArray<u8> = [
    0,0,0,0,0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3, 4,4,4,4, 5,5,5,5, 0,
];

// @ts-ignore: decorator
@inline
const LEN_BASE: StaticArray<u16> = [
    3,4,5,6,7,8,9,10, 11,13,15,17, 19,23,27,31, 35,43,51,59, 67,83,99,115, 131,163,195,227, 258,
];

// Distance code extra bits (codes 0-29)
// @ts-ignore: decorator
@inline
const DIST_EXTRA_BITS: StaticArray<u8> = [
    0,0,0,0, 1,1,2,2, 3,3,4,4, 5,5,6,6, 7,7,8,8, 9,9,10,10, 11,11,12,12, 13,13,
];

// @ts-ignore: decorator
@inline
const DIST_BASE: StaticArray<u16> = [
    1,2,3,4, 5,7,9,13, 17,25,33,49, 65,97,129,193, 257,385,513,769,
    1025,1537,2049,3073, 4097,6145,8193,12289, 16385,24577,
];

function writeFixedLitLen(bw: BitWriter, code: i32): void {
    if (code <= 143) {
        // 8-bit codes: 00110000 + code (reversed)
        const val: u32 = (code + 0x30) as u32;
        bw.writeBits(reverseBits(val, 8), 8);
    } else if (code <= 255) {
        // 9-bit codes: 110010000 + (code - 144) (reversed)
        const val: u32 = (code - 144 + 0x190) as u32;
        bw.writeBits(reverseBits(val, 9), 9);
    } else if (code <= 279) {
        // 7-bit codes: 0000000 + (code - 256) (reversed)
        const val: u32 = (code - 256) as u32;
        bw.writeBits(reverseBits(val, 7), 7);
    } else {
        // 8-bit codes: 11000000 + (code - 280) (reversed)
        const val: u32 = (code - 280 + 0xC0) as u32;
        bw.writeBits(reverseBits(val, 8), 8);
    }
}

function reverseBits(val: u32, numBits: i32): u32 {
    let result: u32 = 0;
    for (let i: i32 = 0; i < numBits; i++) {
        result = (result << 1) | (val & 1);
        val >>>= 1;
    }
    return result;
}

function writeFixedDist(bw: BitWriter, code: i32): void {
    // All distance codes are 5-bit, reversed
    bw.writeBits(reverseBits(code as u32, 5), 5);
}

function encodeLengthCode(bw: BitWriter, length: i32): void {
    // Find the length code (257-285)
    let code: i32 = 0;
    for (let i: i32 = 28; i >= 0; i--) {
        if (length >= (unchecked(LEN_BASE[i]) as i32)) {
            code = i;
            break;
        }
    }
    writeFixedLitLen(bw, 257 + code);
    const extra: i32 = unchecked(LEN_EXTRA_BITS[code]) as i32;
    if (extra > 0) {
        bw.writeBits((length - (unchecked(LEN_BASE[code]) as i32)) as u32, extra);
    }
}

function encodeDistCode(bw: BitWriter, dist: i32): void {
    let code: i32 = 0;
    for (let i: i32 = 29; i >= 0; i--) {
        if (dist >= (unchecked(DIST_BASE[i]) as i32)) {
            code = i;
            break;
        }
    }
    writeFixedDist(bw, code);
    const extra: i32 = unchecked(DIST_EXTRA_BITS[code]) as i32;
    if (extra > 0) {
        bw.writeBits((dist - (unchecked(DIST_BASE[code]) as i32)) as u32, extra);
    }
}

// ---- LZ77 with hash chain + lazy matching --------------------------------

const HASH_SIZE: i32 = 8192;
const HASH_MASK: i32 = HASH_SIZE - 1;
const WINDOW_SIZE: i32 = 32768; // Full DEFLATE window
const WINDOW_MASK: i32 = WINDOW_SIZE - 1;
const MIN_MATCH: i32 = 3;
const MAX_MATCH: i32 = 258;
const MAX_CHAIN: i32 = 128;

function findMatch(
    data: Uint8Array, dataLen: i32, pos: i32,
    hashHead: Int32Array, hashPrev: Int32Array,
    outLen: Int32Array, outDist: Int32Array,
): void {
    outLen[0] = 0;
    outDist[0] = 0;
    if (pos + 2 >= dataLen) return;

    const h: i32 = hashFunc(data[pos], data[pos + 1], data[pos + 2]);
    let chainPos: i32 = hashHead[h];
    let chainLen: i32 = 0;
    const minPos: i32 = (pos - WINDOW_SIZE > 0) ? pos - WINDOW_SIZE : 0;
    let bestLen: i32 = 0;
    let bestDist: i32 = 0;

    while (chainPos >= minPos && chainLen < MAX_CHAIN) {
        const dist: i32 = pos - chainPos;
        if (dist > 0 && dist <= WINDOW_SIZE) {
            let mLen: i32 = 0;
            const maxLen: i32 = (dataLen - pos < MAX_MATCH) ? dataLen - pos : MAX_MATCH;

            // Quick rejection: check last matched byte first
            // Guard: pos + bestLen must be < dataLen to avoid OOB when
            // a prior match reached the end of the buffer (bestLen == dataLen - pos).
            if (bestLen > 0 && pos + bestLen < dataLen && data[chainPos + bestLen] != data[pos + bestLen]) {
                const pi: i32 = chainPos & WINDOW_MASK;
                chainPos = hashPrev[pi];
                chainLen++;
                continue;
            }

            while (mLen < maxLen && data[pos + mLen] == data[chainPos + mLen]) {
                mLen++;
            }
            if (mLen >= MIN_MATCH && mLen > bestLen) {
                bestLen = mLen;
                bestDist = dist;
                if (mLen == MAX_MATCH) break;
            }
        }
        const pi: i32 = chainPos & WINDOW_MASK;
        chainPos = hashPrev[pi];
        chainLen++;
    }

    outLen[0] = bestLen;
    outDist[0] = bestDist;
}

function insertHash(
    data: Uint8Array, dataLen: i32, pos: i32,
    hashHead: Int32Array, hashPrev: Int32Array,
): void {
    if (pos + 2 < dataLen) {
        const h: i32 = hashFunc(data[pos], data[pos + 1], data[pos + 2]);
        hashPrev[pos & WINDOW_MASK] = hashHead[h];
        hashHead[h] = pos;
    }
}

function deflateFixed(bw: BitWriter, data: Uint8Array, dataLen: i32): void {
    // BFINAL=1, BTYPE=01 (fixed Huffman)
    bw.writeBits(1, 1); // BFINAL
    bw.writeBits(1, 2); // BTYPE = 01 (fixed)

    const hashHead: Int32Array = new Int32Array(HASH_SIZE);
    const hashPrev: Int32Array = new Int32Array(WINDOW_SIZE);
    for (let i: i32 = 0; i < HASH_SIZE; i++) {
        hashHead[i] = -1;
    }

    const curLen: Int32Array = new Int32Array(1);
    const curDist: Int32Array = new Int32Array(1);
    const nextLen: Int32Array = new Int32Array(1);
    const nextDist: Int32Array = new Int32Array(1);

    let pos: i32 = 0;
    // Find initial match
    findMatch(data, dataLen, pos, hashHead, hashPrev, curLen, curDist);

    while (pos < dataLen) {
        if (curLen[0] < MIN_MATCH) {
            // No match — emit literal
            writeFixedLitLen(bw, data[pos] as i32);
            insertHash(data, dataLen, pos, hashHead, hashPrev);
            pos++;
            findMatch(data, dataLen, pos, hashHead, hashPrev, curLen, curDist);
        } else {
            // Lazy matching: check if pos+1 yields a longer match
            insertHash(data, dataLen, pos, hashHead, hashPrev);
            findMatch(data, dataLen, pos + 1, hashHead, hashPrev, nextLen, nextDist);

            if (nextLen[0] > curLen[0]) {
                // Better match at pos+1 — emit current byte as literal, use next match
                writeFixedLitLen(bw, data[pos] as i32);
                pos++;

                // Emit the next match
                const mLen: i32 = nextLen[0];
                const mDist: i32 = nextDist[0];
                encodeLengthCode(bw, mLen);
                encodeDistCode(bw, mDist);

                // Insert all skipped positions into hash
                for (let i: i32 = 1; i < mLen; i++) {
                    insertHash(data, dataLen, pos + i, hashHead, hashPrev);
                }
                pos += mLen;
                findMatch(data, dataLen, pos, hashHead, hashPrev, curLen, curDist);
            } else {
                // Current match is good enough
                const mLen: i32 = curLen[0];
                const mDist: i32 = curDist[0];
                encodeLengthCode(bw, mLen);
                encodeDistCode(bw, mDist);

                for (let i: i32 = 1; i < mLen; i++) {
                    insertHash(data, dataLen, pos + i, hashHead, hashPrev);
                }
                pos += mLen;
                findMatch(data, dataLen, pos, hashHead, hashPrev, curLen, curDist);
            }
        }
    }

    // End of block
    writeFixedLitLen(bw, 256);
}

function hashFunc(a: u8, b: u8, c: u8): i32 {
    // Better hash distribution with multiplicative hash
    return ((((a as i32) * 31) ^ ((b as i32) * 17) ^ (c as i32)) & HASH_MASK);
}

// ---- PNG Chunk Helpers ---------------------------------------------------

function writeBE32(buf: Uint8Array, off: i32, val: u32): void {
    buf[off] = ((val >> 24) & 0xFF) as u8;
    buf[off + 1] = ((val >> 16) & 0xFF) as u8;
    buf[off + 2] = ((val >> 8) & 0xFF) as u8;
    buf[off + 3] = (val & 0xFF) as u8;
}

// PNG signature (8 bytes)
// @ts-ignore: decorator
@inline
const PNG_SIG: StaticArray<u8> = [137, 80, 78, 71, 13, 10, 26, 10];

// ---- PNG row filter predictor (types 0-4) --------------------------------

/**
 * Compute the PNG filter predictor value for a given filter type.
 *   0=None, 1=Sub(left), 2=Up(above), 3=Average, 4=Paeth
 * @param f - filter type 0-4
 * @param a - left pixel value
 * @param b - above pixel value
 * @param c - upper-left pixel value
 */
function pngPredict(f: i32, a: i32, b: i32, c: i32): i32 {
    if (f <= 0) return 0;        // None
    if (f == 1) return a;        // Sub
    if (f == 2) return b;        // Up
    if (f == 3) return (a + b) >> 1; // Average
    // Paeth predictor (RFC 2083)
    const p: i32 = a + b - c;
    let pa: i32 = p - a;
    let pb: i32 = p - b;
    let pc: i32 = p - c;
    if (pa < 0) pa = -pa;
    if (pb < 0) pb = -pb;
    if (pc < 0) pc = -pc;
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

// ---- Public API: encodePNG -----------------------------------------------

/**
 * Encode a canvas into an 8-bit indexed PNG.
 *
 * When hasTransparency=true: palette index 0 = transparent, up to 255 colors.
 * When hasTransparency=false: all palette indices are opaque, up to 256 colors.
 * Uses Up row filter + fixed Huffman DEFLATE with LZ77 compression.
 *
 * @param canvas  - width*height bytes. 0=transparent/bg, 1-255=globalPaletteIdx+1
 * @param palette - RGB888 global palette, 3 bytes per color
 * @param width   - canvas width
 * @param height  - canvas height
 * @param hasTransparency - if true, index 0 = transparent + tRNS chunk emitted
 * @returns Complete PNG file as Uint8Array
 */
export function encodePNG(
    canvas: Uint8Array,
    palette: Uint8Array,
    width: i32,
    height: i32,
    hasTransparency: bool = true,
): Uint8Array {
    // --- Step 1: Scan canvas for unique values ---
    const used: Uint8Array = new Uint8Array(256);
    const totalPixels: i32 = width * height;
    for (let i: i32 = 0; i < totalPixels; i++) {
        const v: u8 = canvas[i];
        if (hasTransparency) {
            if (v != 0) used[v as i32] = 1;
        } else {
            used[v as i32] = 1;
        }
    }

    // Build local palette remap
    const globalToLocal: Uint8Array = new Uint8Array(256);
    const localR: Uint8Array = new Uint8Array(256);
    const localG: Uint8Array = new Uint8Array(256);
    const localB: Uint8Array = new Uint8Array(256);
    let localCount: i32 = 0;

    if (hasTransparency) {
        // 0=transparent, 1..N=colors (up to 255)
        for (let i: i32 = 1; i < 256; i++) {
            if (used[i] == 0) continue;
            if (localCount >= 255) break;
            localCount++;
            globalToLocal[i] = localCount as u8;
            const palOff: i32 = (i - 1) * 3;
            if (palOff + 2 < palette.length) {
                localR[localCount] = palette[palOff];
                localG[localCount] = palette[palOff + 1];
                localB[localCount] = palette[palOff + 2];
            }
        }
    } else {
        // All indices opaque, 0..N-1 (up to 256)
        for (let i: i32 = 0; i < 256; i++) {
            if (used[i] == 0) continue;
            globalToLocal[i] = localCount as u8;
            const palOff: i32 = i == 0 ? -1 : (i - 1) * 3;
            if (palOff >= 0 && palOff + 2 < palette.length) {
                localR[localCount] = palette[palOff];
                localG[localCount] = palette[palOff + 1];
                localB[localCount] = palette[palOff + 2];
            }
            // index 0 with palOff=-1 gets (0,0,0) — caller sets bg via canvas value
            localCount++;
        }
    }

    const paletteSize: i32 = hasTransparency ? localCount + 1 : localCount;

    // --- Step 2: Remap canvas to local indices + adaptive row filter ---
    // Each row: 1 filter byte + width data bytes.
    // For each row, try all 5 PNG filter types and pick the one whose
    // output has the smallest sum-of-absolute-values (best DEFLATE hint).
    const filteredRowLen: i32 = 1 + width;
    const filteredTotal: i32 = filteredRowLen * height;

    const filtered: Uint8Array = new Uint8Array(filteredTotal);
    const prevRow: Uint8Array = new Uint8Array(width);
    const curRow: Uint8Array = new Uint8Array(width);

    for (let y: i32 = 0; y < height; y++) {
        const rowStart: i32 = y * filteredRowLen;
        const canvasRow: i32 = y * width;

        // Remap current row to local palette indices
        for (let x: i32 = 0; x < width; x++) {
            curRow[x] = globalToLocal[canvas[canvasRow + x] as i32];
        }

        // Try filters 0-4 (None, Sub, Up, Average, Paeth), pick smallest sum
        let bestFilter: i32 = 0;
        let bestSum: i32 = 0x7FFFFFFF;

        for (let f: i32 = 0; f <= 4; f++) {
            let sum: i32 = 0;
            for (let x: i32 = 0; x < width; x++) {
                const raw: i32 = curRow[x] as i32;
                const a: i32 = x > 0 ? (curRow[x - 1] as i32) : 0;
                const b: i32 = prevRow[x] as i32;
                const c: i32 = x > 0 ? (prevRow[x - 1] as i32) : 0;
                const pred: i32 = pngPredict(f, a, b, c);
                const v: i32 = (raw - pred) & 0xFF;
                sum += v < 128 ? v : 256 - v;
            }
            if (sum < bestSum) {
                bestSum = sum;
                bestFilter = f;
            }
        }

        // Apply the chosen filter
        filtered[rowStart] = bestFilter as u8;
        for (let x: i32 = 0; x < width; x++) {
            const raw: i32 = curRow[x] as i32;
            const a: i32 = x > 0 ? (curRow[x - 1] as i32) : 0;
            const b: i32 = prevRow[x] as i32;
            const c: i32 = x > 0 ? (prevRow[x - 1] as i32) : 0;
            filtered[rowStart + 1 + x] = ((raw - pngPredict(bestFilter, a, b, c)) & 0xFF) as u8;
        }

        // Save current row as previous for next iteration
        for (let x: i32 = 0; x < width; x++) {
            prevRow[x] = curRow[x];
        }
    }

    // --- Step 3: DEFLATE compress ---
    // Use 2× safety margin for pathological compression patterns
    const maxCompressed: i32 = filteredTotal * 2 + 512;
    const compBuf: Uint8Array = new Uint8Array(maxCompressed);

    // Zlib header: CMF=0x78, FLG=0x01
    compBuf[0] = 0x78;
    compBuf[1] = 0x01;

    const bw: BitWriter = new BitWriter(compBuf, 2);
    deflateFixed(bw, filtered, filteredTotal);
    bw.flush();

    const adler: u32 = adler32(filtered, 0, filteredTotal);
    let compEnd: i32 = bw.pos;
    // Clamp to buffer bounds to prevent OOB on adler32 write
    if (compEnd + 4 > maxCompressed) {
        compEnd = maxCompressed - 4;
    }
    writeBE32(compBuf, compEnd, adler);
    const zlibLen: i32 = compEnd + 4;

    // --- Step 4: Assemble PNG ---
    const ihdrDataLen: i32 = 13;
    const plteDataLen: i32 = paletteSize * 3;
    const trnsDataLen: i32 = hasTransparency ? 1 : 0;
    const idatDataLen: i32 = zlibLen;

    const pngSize: i32 = 8
        + (12 + ihdrDataLen)
        + (12 + plteDataLen)
        + (trnsDataLen > 0 ? (12 + trnsDataLen) : 0)
        + (12 + idatDataLen)
        + 12; // IEND

    const png: Uint8Array = new Uint8Array(pngSize);
    let off: i32 = 0;

    for (let i: i32 = 0; i < 8; i++) {
        png[off++] = unchecked(PNG_SIG[i]);
    }

    off = writeChunk(png, off, 0x49484452, buildIHDR(width, height));

    // PLTE chunk
    const plteData: Uint8Array = new Uint8Array(plteDataLen);
    for (let i: i32 = 0; i < paletteSize; i++) {
        plteData[i * 3] = localR[i];
        plteData[i * 3 + 1] = localG[i];
        plteData[i * 3 + 2] = localB[i];
    }
    off = writeChunk(png, off, 0x504C5445, plteData);

    // tRNS: 1 byte — index 0 is transparent (only when using transparency)
    if (hasTransparency) {
        const trnsData: Uint8Array = new Uint8Array(1);
        trnsData[0] = 0;
        off = writeChunk(png, off, 0x74524E53, trnsData);
    }

    // IDAT chunk
    off = writeChunk(png, off, 0x49444154, compBuf.subarray(0, zlibLen));

    // IEND chunk
    off = writeChunk(png, off, 0x49454E44, new Uint8Array(0));

    return png.subarray(0, off);
}

// ---- Color Quantization (greedy closest-pair merge) ----------------------

/**
 * Reduce the number of unique canvas values to at most maxColors by
 * merging closest RGB color pairs. Modifies canvas in-place.
 *
 * Canvas convention: 0 = unused (bg-filled before calling), 1-255 = globalPaletteIdx+1.
 * Palette format: flat RGB888 array, color at index i starts at byte (i*3).
 * For canvas value v≥1, palette offset = (v-1)*3.
 *
 * Uses running RGB averages for distance calculations to make better
 * subsequent merge decisions, but final PNG uses original palette RGB.
 */
export function quantizeColors(
    canvas: Uint8Array,
    palette: Uint8Array,
    totalPixels: i32,
    maxColors: i32,
): void {
    // Collect unique canvas values
    const used: Uint8Array = new Uint8Array(256);
    for (let i: i32 = 0; i < totalPixels; i++) {
        used[canvas[i] as i32] = 1;
    }

    // Count unique — early exit if already within budget
    let count: i32 = 0;
    for (let i: i32 = 0; i < 256; i++) {
        if (used[i] != 0) count++;
    }
    if (count <= maxColors) return;

    // Build compact list of unique values with RGB (max ~40 for our NFTs)
    const MAX_U: i32 = 64;
    const vals: Uint8Array = new Uint8Array(MAX_U);
    const cR: Int32Array = new Int32Array(MAX_U);
    const cG: Int32Array = new Int32Array(MAX_U);
    const cB: Int32Array = new Int32Array(MAX_U);
    const alive: Uint8Array = new Uint8Array(MAX_U);
    let n: i32 = 0;

    for (let i: i32 = 0; i < 256; i++) {
        if (used[i] == 0) continue;
        if (n >= MAX_U) break;
        vals[n] = i as u8;
        if (i > 0) {
            const po: i32 = (i - 1) * 3;
            if (po + 2 < palette.length) {
                cR[n] = palette[po] as i32;
                cG[n] = palette[po + 1] as i32;
                cB[n] = palette[po + 2] as i32;
            }
        }
        alive[n] = 1;
        n++;
    }

    let aliveCount: i32 = n;

    // Merge closest pairs until within budget
    while (aliveCount > maxColors) {
        let minDist: i32 = 0x7FFFFFFF;
        let mi: i32 = -1;
        let mj: i32 = -1;

        for (let i: i32 = 0; i < n; i++) {
            if (alive[i] == 0) continue;
            for (let j: i32 = i + 1; j < n; j++) {
                if (alive[j] == 0) continue;
                const dr: i32 = cR[i] - cR[j];
                const dg: i32 = cG[i] - cG[j];
                const db: i32 = cB[i] - cB[j];
                const d: i32 = dr * dr + dg * dg + db * db;
                if (d < minDist) {
                    minDist = d;
                    mi = i;
                    mj = j;
                }
            }
        }

        if (mi < 0) break;

        // Update survivor's RGB to average (for subsequent distance calculations)
        cR[mi] = (cR[mi] + cR[mj]) / 2;
        cG[mi] = (cG[mi] + cG[mj]) / 2;
        cB[mi] = (cB[mi] + cB[mj]) / 2;

        // Replace all canvas pixels with mj's value → mi's value
        const oldVal: u8 = vals[mj];
        const newVal: u8 = vals[mi];
        for (let p: i32 = 0; p < totalPixels; p++) {
            if (canvas[p] == oldVal) canvas[p] = newVal;
        }

        alive[mj] = 0;
        aliveCount--;
    }
}

// ---- 4-bit Indexed PNG Encoder -------------------------------------------

/**
 * Encode a canvas into a 4-bit indexed PNG (max 16 colors, no transparency).
 * Call quantizeColors() first to ensure ≤16 unique canvas values.
 *
 * 4-bit packing: each row byte holds 2 pixels (high nibble = even col,
 * low nibble = odd col). Row width = ceil(canvasWidth / 2) bytes.
 * Filtering operates on the packed bytes, not individual pixels.
 *
 * Canvas convention: 1-255 = globalPaletteIdx+1 (0 should not appear
 * after background fill, but is handled safely as black).
 */
export function encodePNG4bit(
    canvas: Uint8Array,
    palette: Uint8Array,
    width: i32,
    height: i32,
): Uint8Array {
    // --- Step 1: Build local palette from unique canvas values (max 16) ---
    const used: Uint8Array = new Uint8Array(256);
    const totalPixels: i32 = width * height;
    for (let i: i32 = 0; i < totalPixels; i++) {
        used[canvas[i] as i32] = 1;
    }

    const globalToLocal: Uint8Array = new Uint8Array(256);
    const localR: Uint8Array = new Uint8Array(16);
    const localG: Uint8Array = new Uint8Array(16);
    const localB: Uint8Array = new Uint8Array(16);
    let localCount: i32 = 0;

    for (let i: i32 = 0; i < 256; i++) {
        if (used[i] == 0) continue;
        if (localCount >= 16) break;
        globalToLocal[i] = localCount as u8;
        if (i > 0) {
            const palOff: i32 = (i - 1) * 3;
            if (palOff + 2 < palette.length) {
                localR[localCount] = palette[palOff];
                localG[localCount] = palette[palOff + 1];
                localB[localCount] = palette[palOff + 2];
            }
        }
        localCount++;
    }

    // --- Step 2: Pack into 4-bit rows + adaptive filter ---
    const dataWidth: i32 = (width + 1) >> 1; // ceil(width/2) bytes per row
    const filteredRowLen: i32 = 1 + dataWidth;
    const filteredTotal: i32 = filteredRowLen * height;

    const filtered: Uint8Array = new Uint8Array(filteredTotal);
    const prevRow: Uint8Array = new Uint8Array(dataWidth);
    const curRow: Uint8Array = new Uint8Array(dataWidth);

    for (let y: i32 = 0; y < height; y++) {
        const rowStart: i32 = y * filteredRowLen;
        const canvasRow: i32 = y * width;

        // Pack current row: two pixels per byte
        for (let x: i32 = 0; x < dataWidth; x++) {
            const p0: u8 = (x * 2 < width)
                ? globalToLocal[canvas[canvasRow + x * 2] as i32]
                : 0;
            const p1: u8 = (x * 2 + 1 < width)
                ? globalToLocal[canvas[canvasRow + x * 2 + 1] as i32]
                : 0;
            curRow[x] = ((p0 << 4) | p1) as u8;
        }

        // Try filters 0-4, pick smallest sum-of-absolute-values
        let bestFilter: i32 = 0;
        let bestSum: i32 = 0x7FFFFFFF;

        for (let f: i32 = 0; f <= 4; f++) {
            let sum: i32 = 0;
            for (let x: i32 = 0; x < dataWidth; x++) {
                const raw: i32 = curRow[x] as i32;
                const a: i32 = x > 0 ? (curRow[x - 1] as i32) : 0;
                const bv: i32 = prevRow[x] as i32;
                const cv: i32 = x > 0 ? (prevRow[x - 1] as i32) : 0;
                const pred: i32 = pngPredict(f, a, bv, cv);
                const v: i32 = (raw - pred) & 0xFF;
                sum += v < 128 ? v : 256 - v;
            }
            if (sum < bestSum) {
                bestSum = sum;
                bestFilter = f;
            }
        }

        // Apply chosen filter
        filtered[rowStart] = bestFilter as u8;
        for (let x: i32 = 0; x < dataWidth; x++) {
            const raw: i32 = curRow[x] as i32;
            const a: i32 = x > 0 ? (curRow[x - 1] as i32) : 0;
            const bv: i32 = prevRow[x] as i32;
            const cv: i32 = x > 0 ? (prevRow[x - 1] as i32) : 0;
            filtered[rowStart + 1 + x] = ((raw - pngPredict(bestFilter, a, bv, cv)) & 0xFF) as u8;
        }

        // Save current row for next iteration
        for (let x: i32 = 0; x < dataWidth; x++) {
            prevRow[x] = curRow[x];
        }
    }

    // --- Step 3: DEFLATE compress (fixed Huffman + LZ77) ---
    // Worst case: all 9-bit literals → ceil(filteredTotal * 9/8) + headers + adler32
    // Use 2× safety margin to guard against pathological compression patterns
    const maxCompressed: i32 = filteredTotal * 2 + 512;
    const compBuf: Uint8Array = new Uint8Array(maxCompressed);

    // Zlib header: CMF=0x78, FLG=0x01 (fixed Huffman)
    compBuf[0] = 0x78;
    compBuf[1] = 0x01;

    const bw: BitWriter = new BitWriter(compBuf, 2);
    deflateFixed(bw, filtered, filteredTotal);
    bw.flush();

    const adler: u32 = adler32(filtered, 0, filteredTotal);
    let compEnd: i32 = bw.pos;
    // Clamp to buffer bounds to prevent OOB on adler32 write
    if (compEnd + 4 > maxCompressed) {
        compEnd = maxCompressed - 4;
    }
    writeBE32(compBuf, compEnd, adler);
    const zlibLen: i32 = compEnd + 4;

    // --- Step 4: Assemble PNG ---
    const plteDataLen: i32 = localCount * 3;
    const pngSize: i32 = 8
        + (12 + 13)           // IHDR
        + (12 + plteDataLen)  // PLTE
        + (12 + zlibLen)      // IDAT
        + 12;                 // IEND

    const png: Uint8Array = new Uint8Array(pngSize);
    let off: i32 = 0;

    // PNG signature
    for (let i: i32 = 0; i < 8; i++) {
        png[off++] = unchecked(PNG_SIG[i]);
    }

    // IHDR (bit depth = 4, indexed color)
    const ihdr: Uint8Array = new Uint8Array(13);
    writeBE32(ihdr, 0, width as u32);
    writeBE32(ihdr, 4, height as u32);
    ihdr[8] = 4;   // bit depth = 4 (16 colors max)
    ihdr[9] = 3;   // color type = indexed
    ihdr[10] = 0;  // compression = deflate
    ihdr[11] = 0;  // filter = adaptive
    ihdr[12] = 0;  // interlace = none
    off = writeChunk(png, off, 0x49484452, ihdr);

    // PLTE chunk
    const plteData: Uint8Array = new Uint8Array(plteDataLen);
    for (let i: i32 = 0; i < localCount; i++) {
        plteData[i * 3] = localR[i];
        plteData[i * 3 + 1] = localG[i];
        plteData[i * 3 + 2] = localB[i];
    }
    off = writeChunk(png, off, 0x504C5445, plteData);

    // IDAT chunk
    off = writeChunk(png, off, 0x49444154, compBuf.subarray(0, zlibLen));

    // IEND chunk
    off = writeChunk(png, off, 0x49454E44, new Uint8Array(0));

    return png.subarray(0, off);
}

function buildIHDR(width: i32, height: i32): Uint8Array {
    const ihdr: Uint8Array = new Uint8Array(13);
    writeBE32(ihdr, 0, width as u32);
    writeBE32(ihdr, 4, height as u32);
    ihdr[8] = 8;   // bit depth = 8 (256-color)
    ihdr[9] = 3;   // color type = 3 (indexed)
    ihdr[10] = 0;  // compression = deflate
    ihdr[11] = 0;  // filter = adaptive
    ihdr[12] = 0;  // interlace = none
    return ihdr;
}

function writeChunk(png: Uint8Array, off: i32, chunkType: u32, data: Uint8Array): i32 {
    const dataLen: i32 = data.length;

    // Length (4 bytes, big-endian)
    writeBE32(png, off, dataLen as u32);
    off += 4;

    // Type (4 bytes)
    const typeStart: i32 = off;
    png[off++] = ((chunkType >> 24) & 0xFF) as u8;
    png[off++] = ((chunkType >> 16) & 0xFF) as u8;
    png[off++] = ((chunkType >> 8) & 0xFF) as u8;
    png[off++] = (chunkType & 0xFF) as u8;

    // Data
    for (let i: i32 = 0; i < dataLen; i++) {
        png[off++] = data[i];
    }

    // CRC over type + data
    const crcLen: i32 = 4 + dataLen;
    const crc: u32 = crc32(png, typeStart, crcLen);
    writeBE32(png, off, crc);
    off += 4;

    return off;
}
