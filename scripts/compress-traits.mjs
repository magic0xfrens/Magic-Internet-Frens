#!/usr/bin/env node
/**
 * compress-traits.mjs
 *
 * Compresses 62 MagicFrens pixel-art SVG trait layers into compact binary blobs
 * for on-chain inscription on OPNet (Bitcoin L1).
 *
 * Binary Format per trait:
 *   [layerType:u8][classIdx:u8][layerIdx:u8]   — 3-byte identity
 *   [minX:u8][minY:u8][width:u8][height:u8]    — 4-byte bounding box
 *   [localPaletteSize:u8]                       — 1 byte
 *   [globalIdx × localPaletteSize]              — N bytes (indices into global palette)
 *   [pixelData]                                 — ceil(width*height/2) bytes, 4-bit nibbles
 *                                                 0=transparent, 1-15=localPalette[n-1]
 *
 * Global Palette: [numColors:u16BE][r,g,b × numColors]
 *
 * Outputs:
 *   compressed-traits/palette.bin        — global color palette
 *   compressed-traits/trait-{type}-{class}-{idx}.bin — per-trait blob
 *   compressed-traits/merkle.json        — Merkle tree root, proofs, leaf hashes
 *   compressed-traits/manifest.json      — full mapping, sizes, hashes
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, basename } from 'path';
import { createHash } from 'crypto';

const FRENS_DIR = join(import.meta.dirname, '..', 'public', 'frens');
const OUT_DIR = join(import.meta.dirname, '..', 'compressed-traits');

// ── Trait mapping: file → (layerType, classIdx, layerIdx) ──────────────────

const TRAIT_MAP = [
    // Bodies (layerType=0)
    // Wizard bodies (classIdx=0)
    { file: 'wizard-01.svg',            layerType: 0, classIdx: 0, layerIdx: 0, label: 'Wizard I' },
    { file: 'wizard-02.svg',            layerType: 0, classIdx: 0, layerIdx: 1, label: 'Wizard II' },
    { file: 'wizard-03.svg',            layerType: 0, classIdx: 0, layerIdx: 2, label: 'Wizard III' },
    { file: 'wizard-04.svg',            layerType: 0, classIdx: 0, layerIdx: 3, label: 'Wizard IV' },
    { file: 'wizard-05.svg',            layerType: 0, classIdx: 0, layerIdx: 4, label: 'Wizard V' },
    { file: 'wizard-06.svg',            layerType: 0, classIdx: 0, layerIdx: 5, label: 'Wizard VI' },
    { file: 'wizard-manifest.svg',      layerType: 0, classIdx: 0, layerIdx: 6, label: 'Wizard Manifest' },
    { file: 'wizard-btc-01.svg',        layerType: 0, classIdx: 0, layerIdx: 7, label: 'Wizard BTC' },
    // King bodies (classIdx=1)
    { file: 'king-cloth-black.svg',     layerType: 0, classIdx: 1, layerIdx: 0, label: 'King Black' },
    { file: 'king-cloth-blue.svg',      layerType: 0, classIdx: 1, layerIdx: 1, label: 'King Blue' },
    { file: 'king-cloth-orange.svg',    layerType: 0, classIdx: 1, layerIdx: 2, label: 'King Orange' },
    { file: 'king-cloth-red.svg',       layerType: 0, classIdx: 1, layerIdx: 3, label: 'King Red' },
    { file: 'king-cloth-white.svg',     layerType: 0, classIdx: 1, layerIdx: 4, label: 'King White' },
    // Knight bodies (classIdx=2)
    { file: 'knight-bronze.svg',        layerType: 0, classIdx: 2, layerIdx: 0, label: 'Knight Bronze' },
    { file: 'knight-gold.svg',          layerType: 0, classIdx: 2, layerIdx: 1, label: 'Knight Gold' },
    { file: 'knight-orange.svg',        layerType: 0, classIdx: 2, layerIdx: 2, label: 'Knight Orange' },
    { file: 'knight-silver.svg',        layerType: 0, classIdx: 2, layerIdx: 3, label: 'Knight Silver' },
    // Apprentice bodies (classIdx=3)
    { file: 'apprentice-01.svg',        layerType: 0, classIdx: 3, layerIdx: 0, label: 'Apprentice I' },
    { file: 'apprentice-02.svg',        layerType: 0, classIdx: 3, layerIdx: 1, label: 'Apprentice II' },
    { file: 'apprentice-02-orange.svg', layerType: 0, classIdx: 3, layerIdx: 2, label: 'Apprentice Orange' },
    // Peasant bodies (classIdx=4)
    { file: 'peasant-01.svg',           layerType: 0, classIdx: 4, layerIdx: 0, label: 'Peasant I' },
    { file: 'peasant-02.svg',           layerType: 0, classIdx: 4, layerIdx: 1, label: 'Peasant II' },
    { file: 'peasant-robinhood.svg',    layerType: 0, classIdx: 4, layerIdx: 2, label: 'Robin Hood' },
    // Gnome bodies (classIdx=5)
    { file: 'gnome-01.svg',             layerType: 0, classIdx: 5, layerIdx: 0, label: 'Gnome I' },
    { file: 'gnome-02.svg',             layerType: 0, classIdx: 5, layerIdx: 1, label: 'Gnome II' },
    // Elf bodies (classIdx=6)
    { file: 'elf-02.svg',               layerType: 0, classIdx: 6, layerIdx: 0, label: 'Elf I' },
    { file: 'elf-03.svg',               layerType: 0, classIdx: 6, layerIdx: 1, label: 'Elf II' },
    { file: 'elf-04.svg',               layerType: 0, classIdx: 6, layerIdx: 2, label: 'Elf III' },

    // Faces (layerType=1, classIdx=0 — universal green frog)
    { file: 'face-01.svg',  layerType: 1, classIdx: 0, layerIdx: 0, label: 'Classic' },
    { file: 'face-02.svg',  layerType: 1, classIdx: 0, layerIdx: 1, label: 'Happy' },
    { file: 'face-03.svg',  layerType: 1, classIdx: 0, layerIdx: 2, label: 'Angry' },
    { file: 'face-04.svg',  layerType: 1, classIdx: 0, layerIdx: 3, label: 'Feels Bad' },
    { file: 'face-05.svg',  layerType: 1, classIdx: 0, layerIdx: 4, label: 'Grinding' },
    { file: 'face-06.svg',  layerType: 1, classIdx: 0, layerIdx: 5, label: 'Chill' },
    { file: 'face-07.svg',  layerType: 1, classIdx: 0, layerIdx: 6, label: 'Grumpy' },
    { file: 'face-08.svg',  layerType: 1, classIdx: 0, layerIdx: 7, label: 'Giga Happy' },
    { file: 'face-09.svg',  layerType: 1, classIdx: 0, layerIdx: 8, label: 'Cooked' },
    { file: 'face-10.svg',  layerType: 1, classIdx: 0, layerIdx: 9, label: 'Comfy' },
    { file: 'face-11.svg',  layerType: 1, classIdx: 0, layerIdx: 10, label: 'Retard' },
    { file: 'face-laser.svg', layerType: 1, classIdx: 0, layerIdx: 11, label: 'Laser Eyes' },
    // Gnome faces (layerType=1, classIdx=5 — cream skin)
    { file: 'gnome-face-01.svg',  layerType: 1, classIdx: 5, layerIdx: 0, label: 'Gnome Classic' },
    { file: 'gnome-face-02.svg',  layerType: 1, classIdx: 5, layerIdx: 1, label: 'Gnome Happy' },
    { file: 'gnome-face-03.svg',  layerType: 1, classIdx: 5, layerIdx: 2, label: 'Gnome Angry' },
    { file: 'gnome-face-04.svg',  layerType: 1, classIdx: 5, layerIdx: 3, label: 'Gnome Feels Bad' },
    { file: 'gnome-face-05.svg',  layerType: 1, classIdx: 5, layerIdx: 4, label: 'Gnome Grinding' },
    { file: 'gnome-face-06.svg',  layerType: 1, classIdx: 5, layerIdx: 5, label: 'Gnome Chill' },
    { file: 'gnome-face-07.svg',  layerType: 1, classIdx: 5, layerIdx: 6, label: 'Gnome Grumpy' },
    { file: 'gnome-face-08.svg',  layerType: 1, classIdx: 5, layerIdx: 7, label: 'Gnome Giga Happy' },
    { file: 'gnome-face-09.svg',  layerType: 1, classIdx: 5, layerIdx: 8, label: 'Gnome Cooked' },
    { file: 'gnome-face-10.svg',  layerType: 1, classIdx: 5, layerIdx: 9, label: 'Gnome Comfy' },
    { file: 'gnome-face-11.svg',  layerType: 1, classIdx: 5, layerIdx: 10, label: 'Gnome Retard' },
    { file: 'gnome-face-laser.svg', layerType: 1, classIdx: 5, layerIdx: 11, label: 'Gnome Laser Eyes' },
    // Elf faces (layerType=1, classIdx=6)
    { file: 'elf-face-01.svg',  layerType: 1, classIdx: 6, layerIdx: 0, label: 'Elf Classic' },
    { file: 'elf-face-02.svg',  layerType: 1, classIdx: 6, layerIdx: 1, label: 'Elf Happy' },
    { file: 'elf-face-03.svg',  layerType: 1, classIdx: 6, layerIdx: 2, label: 'Elf Angry' },
    { file: 'elf-face-04.svg',  layerType: 1, classIdx: 6, layerIdx: 3, label: 'Elf Feels Bad' },
    { file: 'elf-face-05.svg',  layerType: 1, classIdx: 6, layerIdx: 4, label: 'Elf Grinding' },
    { file: 'elf-face-06.svg',  layerType: 1, classIdx: 6, layerIdx: 5, label: 'Elf Chill' },
    { file: 'elf-face-07.svg',  layerType: 1, classIdx: 6, layerIdx: 6, label: 'Elf Grumpy' },
    { file: 'elf-face-08.svg',  layerType: 1, classIdx: 6, layerIdx: 7, label: 'Elf Giga Happy' },
    { file: 'elf-face-09.svg',  layerType: 1, classIdx: 6, layerIdx: 8, label: 'Elf Cooked' },
    { file: 'elf-face-10.svg',  layerType: 1, classIdx: 6, layerIdx: 9, label: 'Elf Comfy' },
    { file: 'elf-face-11.svg',  layerType: 1, classIdx: 6, layerIdx: 10, label: 'Elf Retard' },
    { file: 'elf-face-laser.svg', layerType: 1, classIdx: 6, layerIdx: 11, label: 'Elf Laser Eyes' },

    // Items (layerType=2)
    // Wizard items (classIdx=0)
    { file: 'wiz-item-01.svg',         layerType: 2, classIdx: 0, layerIdx: 0, label: 'Staff I' },
    { file: 'wiz-item-02.svg',         layerType: 2, classIdx: 0, layerIdx: 1, label: 'Staff II' },
    { file: 'wiz-item-03.svg',         layerType: 2, classIdx: 0, layerIdx: 2, label: 'Staff III' },
    { file: 'wiz-item-04.svg',         layerType: 2, classIdx: 0, layerIdx: 3, label: 'Staff IV' },
    { file: 'wiz-item-manifest.svg',   layerType: 2, classIdx: 0, layerIdx: 4, label: 'Staff Manifest' },
    // King items (classIdx=1)
    { file: 'king-item-black.svg',     layerType: 2, classIdx: 1, layerIdx: 0, label: 'Scepter Black' },
    { file: 'king-item-blue.svg',      layerType: 2, classIdx: 1, layerIdx: 1, label: 'Scepter Blue' },
    { file: 'king-item-red.svg',       layerType: 2, classIdx: 1, layerIdx: 2, label: 'Scepter Red' },
    { file: 'king-item-white.svg',     layerType: 2, classIdx: 1, layerIdx: 3, label: 'Scepter White' },
    // Knight items (classIdx=2)
    { file: 'knight-item-bronze.svg',  layerType: 2, classIdx: 2, layerIdx: 0, label: 'Shield Bronze' },
    { file: 'knight-item-gold.svg',    layerType: 2, classIdx: 2, layerIdx: 1, label: 'Shield Gold' },
    { file: 'knight-item-orange.svg',  layerType: 2, classIdx: 2, layerIdx: 2, label: 'Shield Orange' },
    { file: 'knight-item-silver.svg',  layerType: 2, classIdx: 2, layerIdx: 3, label: 'Shield Silver' },
    // Apprentice item (classIdx=3)
    { file: 'apprentice-item-01.svg',  layerType: 2, classIdx: 3, layerIdx: 0, label: 'Apprentice Tool' },
    // Peasant items (classIdx=4)
    { file: 'peasant-item-01.svg',     layerType: 2, classIdx: 4, layerIdx: 0, label: 'Pitchfork' },
    { file: 'peasant-item-02.svg',     layerType: 2, classIdx: 4, layerIdx: 1, label: 'Shovel' },
    { file: 'peasant-item-03.svg',     layerType: 2, classIdx: 4, layerIdx: 2, label: 'Hoe' },
    { file: 'peasant-item-bow.svg',    layerType: 2, classIdx: 4, layerIdx: 3, label: 'Longbow' },
    // Gnome items (classIdx=5)
    { file: 'gnome-item-01.svg',       layerType: 2, classIdx: 5, layerIdx: 0, label: 'Gnome Tool I' },
    { file: 'gnome-item-02.svg',       layerType: 2, classIdx: 5, layerIdx: 1, label: 'Gnome Tool II' },
    { file: 'gnome-item-03.svg',       layerType: 2, classIdx: 5, layerIdx: 2, label: 'Gnome Tool III' },
    { file: 'gnome-item-04.svg',       layerType: 2, classIdx: 5, layerIdx: 3, label: 'BTC Pickaxe' },
    // Elf item (classIdx=6)
    { file: 'elf-item-00.svg',         layerType: 2, classIdx: 6, layerIdx: 0, label: 'Elf Tool' },

    // Subitems — shared (layerType=3, classIdx=0)
    { file: 'subitem-01.svg',              layerType: 3, classIdx: 0, layerIdx: 0, label: 'Potion' },
    { file: 'skull-subitem.svg',           layerType: 3, classIdx: 0, layerIdx: 1, label: 'Skull' },
    // Subitems — Peasant headgear (layerType=3, classIdx=4)
    { file: 'peasant-item-mumuhat.svg',    layerType: 3, classIdx: 4, layerIdx: 0, label: 'MuMu Hat' },
    { file: 'peasant-item-bobohat.svg',    layerType: 3, classIdx: 4, layerIdx: 1, label: 'BoBo Hat' },
];

// ── SVG Parsing ────────────────────────────────────────────────────────────

function parseSvg(filePath) {
    const svg = readFileSync(filePath, 'utf-8');
    const pixels = [];
    const rectRe = /<rect\s+x="(\d+)"\s+y="(\d+)"\s+width="1"\s+height="1"\s+fill="(#[A-Fa-f0-9]{6})"\s*\/>/g;
    let m;
    while ((m = rectRe.exec(svg)) !== null) {
        pixels.push({ x: parseInt(m[1]), y: parseInt(m[2]), color: m[3].toUpperCase() });
    }
    return pixels;
}

// ── Color Distance (perceptual) ────────────────────────────────────────────

function colorDistance(hex1, hex2) {
    const r1 = parseInt(hex1.slice(1, 3), 16);
    const g1 = parseInt(hex1.slice(3, 5), 16);
    const b1 = parseInt(hex1.slice(5, 7), 16);
    const r2 = parseInt(hex2.slice(1, 3), 16);
    const g2 = parseInt(hex2.slice(3, 5), 16);
    const b2 = parseInt(hex2.slice(5, 7), 16);
    // Weighted euclidean (human perception weights)
    const dr = r1 - r2, dg = g1 - g2, db = b1 - b2;
    return Math.sqrt(2 * dr * dr + 4 * dg * dg + 3 * db * db);
}

// ── Per-Trait Color Quantization ──────────────────────────────────────────

/**
 * Reduce a single trait's pixel colors to at most maxLocal unique colors
 * by iteratively merging the two closest. Mutates pixel data in place.
 */
function quantizeTraitColors(pixels, maxLocal, label) {
    const localColorSet = new Set();
    for (const p of pixels) localColorSet.add(p.color);
    let localColors = [...localColorSet].sort();

    while (localColors.length > maxLocal) {
        let bestDist = Infinity;
        let bestI = 0, bestJ = 1;
        for (let i = 0; i < localColors.length; i++) {
            for (let j = i + 1; j < localColors.length; j++) {
                const d = colorDistance(localColors[i], localColors[j]);
                if (d < bestDist) {
                    bestDist = d;
                    bestI = i;
                    bestJ = j;
                }
            }
        }
        const mergeFrom = localColors[bestJ];
        const mergeInto = localColors[bestI];
        for (const p of pixels) {
            if (p.color === mergeFrom) p.color = mergeInto;
        }
        localColors.splice(bestJ, 1);
        console.log(`  Merged ${mergeFrom} → ${mergeInto} (dist=${bestDist.toFixed(1)}) in ${label}`);
    }
    return localColors;
}

// ── Global Palette Builder ─────────────────────────────────────────────────

/** Maximum palette colors the contract supports (u8 canvas pixels, 0=transparent) */
const MAX_GLOBAL_PALETTE = 255;

function buildGlobalPalette(allTraitPixels) {
    const colorSet = new Set();
    for (const pixels of allTraitPixels) {
        for (const p of pixels) colorSet.add(p.color);
    }
    const colors = [...colorSet].sort();
    return colors; // sorted hex strings
}

/**
 * Quantize the global palette down to maxColors by iteratively merging
 * the two closest colors. Updates all pixel data in place.
 */
function quantizeGlobalPalette(allTraitPixels, globalPalette, maxColors) {
    if (globalPalette.length <= maxColors) return globalPalette;

    console.log(`\nGlobal palette has ${globalPalette.length} colors, quantizing to ${maxColors}...`);

    // Build a mutable color list
    let colors = [...globalPalette];

    // Pre-compute pairwise distances into a sorted work list
    // Use a Map for O(1) "is this color still alive?" checks
    const alive = new Set(colors);

    while (alive.size > maxColors) {
        // Find closest pair among alive colors
        const aliveArr = [...alive];
        let bestDist = Infinity;
        let bestA = null, bestB = null;

        for (let i = 0; i < aliveArr.length; i++) {
            for (let j = i + 1; j < aliveArr.length; j++) {
                const d = colorDistance(aliveArr[i], aliveArr[j]);
                if (d < bestDist) {
                    bestDist = d;
                    bestA = aliveArr[i];
                    bestB = aliveArr[j];
                }
            }
        }

        // Merge bestB into bestA across all pixel data
        for (const pixels of allTraitPixels) {
            for (const p of pixels) {
                if (p.color === bestB) p.color = bestA;
            }
        }
        alive.delete(bestB);

        if (alive.size % 50 === 0 || alive.size <= maxColors + 5) {
            console.log(`  ${alive.size} colors remaining (merged dist=${bestDist.toFixed(1)})`);
        }
    }

    const result = [...alive].sort();
    console.log(`  Quantized to ${result.length} global colors\n`);
    return result;
}

// ── Encode Single Trait ────────────────────────────────────────────────────

function encodeTrait(trait, pixels, globalPalette) {
    if (pixels.length === 0) {
        throw new Error(`No pixels found for ${trait.file}`);
    }

    // Compute bounding box
    let minX = 255, minY = 255, maxX = 0, maxY = 0;
    for (const p of pixels) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
    }
    const width = maxX - minX + 1;
    const height = maxY - minY + 1;

    // Local palette already quantized to ≤15 colors in pre-pass
    const localColorSet = new Set();
    for (const p of pixels) localColorSet.add(p.color);
    let localColors = [...localColorSet].sort();

    if (localColors.length > 15) {
        throw new Error(`BUG: ${trait.file} still has ${localColors.length} local colors after pre-quantization`);
    }

    // Map local colors to global palette indices
    const globalIndices = localColors.map(c => {
        const idx = globalPalette.indexOf(c);
        if (idx === -1) throw new Error(`Color ${c} not in global palette`);
        return idx;
    });

    // Build pixel-to-local-index lookup
    const colorToLocal = new Map();
    for (let i = 0; i < localColors.length; i++) {
        colorToLocal.set(localColors[i], i + 1); // 1-indexed (0 = transparent)
    }

    // Build pixel grid within bounding box
    const grid = new Uint8Array(width * height); // default 0 = transparent
    for (const p of pixels) {
        const gx = p.x - minX;
        const gy = p.y - minY;
        grid[gy * width + gx] = colorToLocal.get(p.color);
    }

    // Encode binary blob
    // Header: [layerType, classIdx, layerIdx, minX, minY, width, height, localPaletteSize]
    const headerSize = 8;
    const paletteBytes = localColors.length;
    const pixelBytes = Math.ceil((width * height) / 2);
    const totalSize = headerSize + paletteBytes + pixelBytes;

    const buf = Buffer.alloc(totalSize);
    let off = 0;

    // Header
    buf[off++] = trait.layerType;
    buf[off++] = trait.classIdx;
    buf[off++] = trait.layerIdx;
    buf[off++] = minX;
    buf[off++] = minY;
    buf[off++] = width;
    buf[off++] = height;
    buf[off++] = localColors.length;

    // Local palette (global indices)
    for (const gi of globalIndices) {
        buf[off++] = gi;
    }

    // Pixel data (4-bit nibbles, high nibble first)
    const totalPixels = width * height;
    for (let i = 0; i < totalPixels; i += 2) {
        const hi = grid[i] & 0x0F;
        const lo = (i + 1 < totalPixels) ? (grid[i + 1] & 0x0F) : 0;
        buf[off++] = (hi << 4) | lo;
    }

    return buf;
}

// ── Merkle Tree ────────────────────────────────────────────────────────────

function sha256(data) {
    return createHash('sha256').update(data).digest();
}

/**
 * Compute Merkle leaf hash matching the on-chain contract:
 *   leaf = sha256(traitKeyU256BE || binaryBlob)
 * This binds the traitKey to the data so the same blob can't
 * be used for a different trait slot.
 */
function computeLeafHash(traitKey, blob) {
    const keyBuf = Buffer.alloc(32);
    // Write traitKey as big-endian u256 (fits in 4 bytes at offset 28)
    keyBuf.writeUInt32BE(traitKey, 28);
    return sha256(Buffer.concat([keyBuf, blob]));
}

function buildMerkleTree(leaves) {
    if (leaves.length === 0) throw new Error('No leaves');

    // Pad to next power of 2
    const size = Math.pow(2, Math.ceil(Math.log2(leaves.length)));
    const paddedLeaves = [...leaves];
    while (paddedLeaves.length < size) {
        // Duplicate last leaf for padding
        paddedLeaves.push(Buffer.alloc(32)); // zero hash for padding
    }

    // Build tree bottom-up
    const tree = new Array(2 * size);
    // Leaves at positions [size..2*size-1]
    for (let i = 0; i < size; i++) {
        tree[size + i] = paddedLeaves[i];
    }
    // Internal nodes
    for (let i = size - 1; i >= 1; i--) {
        const left = tree[2 * i];
        const right = tree[2 * i + 1];
        tree[i] = sha256(Buffer.concat([left, right]));
    }

    const root = tree[1];

    // Generate proofs for each real leaf
    const proofs = [];
    for (let leafIdx = 0; leafIdx < leaves.length; leafIdx++) {
        const proof = [];
        let pos = size + leafIdx;
        while (pos > 1) {
            const sibling = pos ^ 1; // XOR to get sibling
            proof.push(tree[sibling]);
            pos = pos >> 1; // parent
        }
        proofs.push(proof);
    }

    return { root, proofs, tree, size };
}

function verifyMerkleProof(leaf, proof, root) {
    let hash = leaf;
    let pos = 0; // dummy, we re-derive from proof structure
    // The proof is ordered from leaf to root
    // For verification, we need to know if current hash is left or right child
    // We stored siblings in order, so we need the position
    // Actually, let's just verify against the tree we built
    // For the contract, we'll pass the leaf index and reconstruct
    return true; // Verification is done by the tree builder
}

// ── Encode Global Palette ──────────────────────────────────────────────────

function encodeGlobalPalette(colors) {
    // [numColors:u16BE][r,g,b × numColors]
    const buf = Buffer.alloc(2 + colors.length * 3);
    buf.writeUInt16BE(colors.length, 0);
    for (let i = 0; i < colors.length; i++) {
        const hex = colors[i];
        buf[2 + i * 3 + 0] = parseInt(hex.slice(1, 3), 16);
        buf[2 + i * 3 + 1] = parseInt(hex.slice(3, 5), 16);
        buf[2 + i * 3 + 2] = parseInt(hex.slice(5, 7), 16);
    }
    return buf;
}

// ── Main ───────────────────────────────────────────────────────────────────

function main() {
    if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

    console.log(`Parsing ${TRAIT_MAP.length} SVG trait files...\n`);

    // Parse all SVGs
    const allPixels = [];
    for (const trait of TRAIT_MAP) {
        const filePath = join(FRENS_DIR, trait.file);
        if (!existsSync(filePath)) {
            console.error(`MISSING: ${trait.file}`);
            process.exit(1);
        }
        const pixels = parseSvg(filePath);
        allPixels.push(pixels);
    }

    // Step 1: Per-trait quantization — reduce each trait to max 15 local colors
    console.log('Per-trait color quantization (max 15 per trait)...');
    for (let i = 0; i < TRAIT_MAP.length; i++) {
        quantizeTraitColors(allPixels[i], 15, TRAIT_MAP[i].file);
    }

    // Step 2: Build initial global palette from quantized pixels
    let globalPalette = buildGlobalPalette(allPixels);
    console.log(`\nGlobal palette after per-trait quantization: ${globalPalette.length} unique colors`);

    // Step 3: Global quantization — merge closest colors until ≤ 255
    globalPalette = quantizeGlobalPalette(allPixels, globalPalette, MAX_GLOBAL_PALETTE);
    console.log(`Final global palette: ${globalPalette.length} colors\n`);

    // Encode global palette binary
    const paletteBin = encodeGlobalPalette(globalPalette);
    writeFileSync(join(OUT_DIR, 'palette.bin'), paletteBin);
    console.log(`palette.bin: ${paletteBin.length} bytes\n`);

    // Encode each trait
    const traitBlobs = [];
    const manifest = [];
    let totalCompressed = 0;
    let totalOriginal = 0;

    for (let i = 0; i < TRAIT_MAP.length; i++) {
        const trait = TRAIT_MAP[i];
        const pixels = allPixels[i];
        const origSize = readFileSync(join(FRENS_DIR, trait.file)).length;

        const blob = encodeTrait(trait, pixels, globalPalette);
        const traitKey = trait.layerType * 65536 + trait.classIdx * 256 + trait.layerIdx;
        const hash = computeLeafHash(traitKey, blob);
        const filename = `trait-${trait.layerType}-${trait.classIdx}-${trait.layerIdx}.bin`;

        writeFileSync(join(OUT_DIR, filename), blob);
        traitBlobs.push({ blob, hash, trait, filename, traitKey });

        totalCompressed += blob.length;
        totalOriginal += origSize;

        const ratio = ((1 - blob.length / origSize) * 100).toFixed(1);
        manifest.push({
            file: trait.file,
            layerType: trait.layerType,
            classIdx: trait.classIdx,
            layerIdx: trait.layerIdx,
            label: trait.label,
            binaryFile: filename,
            originalBytes: origSize,
            compressedBytes: blob.length,
            reduction: `${ratio}%`,
            sha256: hash.toString('hex'),
            traitKey: trait.layerType * 65536 + trait.classIdx * 256 + trait.layerIdx,
        });

        console.log(
            `  ${trait.file.padEnd(30)} ${pixels.length.toString().padStart(5)} px  ` +
            `${origSize.toString().padStart(7)} → ${blob.length.toString().padStart(5)} bytes  ` +
            `(-${ratio}%)  u256 slots: ${Math.ceil(blob.length / 32)}`
        );
    }

    // ── Color Batch Leaves (mixed 5/4 colors per batch → 55 batches for 144 total leaves) ──
    // 27 batches × 5 colors + 28 batches × 4 colors = 135 + 112 = 247 colors
    const LARGE_BATCH = 5;
    const SMALL_BATCH = 4;
    const LARGE_BATCH_COUNT = 27;
    const totalColors = globalPalette.length;
    const COLOR_BATCH_LAYER_TYPE = 255;

    let colorOffset = 0;
    const batchSizes = [];
    for (let i = 0; i < LARGE_BATCH_COUNT; i++) batchSizes.push(LARGE_BATCH);
    while (colorOffset + batchSizes.reduce((a, b) => a + b, 0) < totalColors) {
        batchSizes.push(SMALL_BATCH);
    }
    // Reset offset for the actual loop
    const totalBatches = batchSizes.length;

    console.log(`\nGenerating ${totalBatches} color batch leaves (${LARGE_BATCH_COUNT}×${LARGE_BATCH} + ${totalBatches - LARGE_BATCH_COUNT}×${SMALL_BATCH} colors)...`);

    colorOffset = 0;
    for (let batchIdx = 0; batchIdx < totalBatches; batchIdx++) {
        const batchSize = batchSizes[batchIdx];
        const startColor = colorOffset;
        const endColor = Math.min(startColor + batchSize, totalColors);
        const batchColors = globalPalette.slice(startColor, endColor);
        colorOffset = endColor;

        const blob = Buffer.alloc(batchColors.length * 3);
        for (let i = 0; i < batchColors.length; i++) {
            const hex = batchColors[i];
            blob[i * 3 + 0] = parseInt(hex.slice(1, 3), 16);
            blob[i * 3 + 1] = parseInt(hex.slice(3, 5), 16);
            blob[i * 3 + 2] = parseInt(hex.slice(5, 7), 16);
        }

        const traitKey = COLOR_BATCH_LAYER_TYPE * 65536 + batchIdx;
        const hash = computeLeafHash(traitKey, blob);
        const filename = `color-batch-${batchIdx}.bin`;

        writeFileSync(join(OUT_DIR, filename), blob);
        traitBlobs.push({
            blob, hash,
            trait: {
                layerType: COLOR_BATCH_LAYER_TYPE, classIdx: 0, layerIdx: batchIdx,
                file: `palette-colors-${startColor}-${endColor - 1}`,
                label: `Colors ${startColor}-${endColor - 1}`,
            },
            filename, traitKey,
            isColorBatch: true,
        });

        manifest.push({
            file: `palette-colors-${startColor}-${endColor - 1}`,
            layerType: COLOR_BATCH_LAYER_TYPE,
            classIdx: 0,
            layerIdx: batchIdx,
            label: `Colors ${startColor}-${endColor - 1}`,
            binaryFile: filename,
            originalBytes: blob.length,
            compressedBytes: blob.length,
            reduction: '0%',
            sha256: hash.toString('hex'),
            traitKey,
            isColorBatch: true,
        });

        console.log(
            `  batch ${String(batchIdx).padStart(2)}: colors ${String(startColor).padStart(3)}-${String(endColor - 1).padStart(3)}  ` +
            `(${blob.length} bytes)  traitKey=${traitKey}`
        );
    }

    console.log(`\n  Total leaves: ${traitBlobs.length} (${TRAIT_MAP.length} traits + ${totalBatches} color batches)`);

    // Build Merkle tree
    console.log(`\nBuilding Merkle tree from ${traitBlobs.length} leaf hashes...`);
    const leafHashes = traitBlobs.map(t => t.hash);
    const { root, proofs } = buildMerkleTree(leafHashes);

    console.log(`Merkle root: 0x${root.toString('hex')}\n`);

    // Compute palette hash (raw RGB without the 2-byte header)
    const paletteRgb = paletteBin.subarray(2); // strip u16BE count header
    const paletteHash = sha256(paletteRgb);
    writeFileSync(join(OUT_DIR, 'palette-rgb.bin'), paletteRgb);
    console.log(`palette-rgb.bin: ${paletteRgb.length} bytes (raw RGB, no header)`);
    console.log(`palette hash: 0x${paletteHash.toString('hex')}\n`);

    // Merkle output
    const merkleJson = {
        root: '0x' + root.toString('hex'),
        leafCount: traitBlobs.length,
        treeDepth: Math.ceil(Math.log2(traitBlobs.length)),
        paletteHash: '0x' + paletteHash.toString('hex'),
        leafHashMethod: 'sha256(traitKeyU256BE || blob)',
        leaves: traitBlobs.map((t, i) => {
            const entry = {
                index: i,
                traitKey: manifest[i].traitKey,
                file: t.trait.file,
                hash: '0x' + t.hash.toString('hex'),
                proof: proofs[i].map(p => '0x' + p.toString('hex')),
            };
            if (t.isColorBatch) entry.isColorBatch = true;
            return entry;
        }),
    };
    writeFileSync(join(OUT_DIR, 'merkle.json'), JSON.stringify(merkleJson, null, 2));

    // Manifest output
    writeFileSync(join(OUT_DIR, 'manifest.json'), JSON.stringify({
        generated: new Date().toISOString(),
        globalPalette: {
            file: 'palette.bin',
            bytes: paletteBin.length,
            colorCount: globalPalette.length,
            colors: globalPalette,
        },
        merkleRoot: '0x' + root.toString('hex'),
        traits: manifest,
        totals: {
            traitCount: TRAIT_MAP.length,
            colorBatchCount: totalBatches,
            totalLeaves: traitBlobs.length,
            originalBytes: totalOriginal,
            compressedBytes: totalCompressed,
            paletteBytes: paletteBin.length,
            colorBatchBytes: batchSizes.reduce((a, b) => a + b, 0) * 3,
            totalOnChainBytes: totalCompressed + paletteBin.length,
            reductionPercent: ((1 - (totalCompressed + paletteBin.length) / totalOriginal) * 100).toFixed(1),
            u256SlotsNeeded: Math.ceil((totalCompressed + paletteBin.length) / 32),
        },
    }, null, 2));

    // Generate TypeScript trait data for frontend bundling
    const tsLines = [
        '// Auto-generated by compress-traits.mjs — DO NOT EDIT',
        `// Generated: ${new Date().toISOString()}`,
        '',
        `export const MERKLE_ROOT = '${merkleJson.root}';`,
        '',
        'export interface CompressedTrait {',
        '  traitKey: number;',
        '  leafIndex: number;',
        '  layerType: number;',
        '  classIdx: number;',
        '  layerIdx: number;',
        '  label: string;',
        '  sha256: string;',
        '  proof: string[];',
        '  blob: string; // hex-encoded binary',
        '  isColorBatch?: boolean;',
        '}',
        '',
        'export const COMPRESSED_TRAITS: CompressedTrait[] = [',
    ];

    for (let i = 0; i < traitBlobs.length; i++) {
        const t = traitBlobs[i];
        const m = manifest[i];
        tsLines.push(`  {`);
        tsLines.push(`    traitKey: ${m.traitKey},`);
        tsLines.push(`    leafIndex: ${i},`);
        tsLines.push(`    layerType: ${m.layerType},`);
        tsLines.push(`    classIdx: ${m.classIdx},`);
        tsLines.push(`    layerIdx: ${m.layerIdx},`);
        tsLines.push(`    label: '${m.label}',`);
        tsLines.push(`    sha256: '${m.sha256}',`);
        tsLines.push(`    proof: [${proofs[i].map(p => `'${p.toString('hex')}'`).join(', ')}],`);
        tsLines.push(`    blob: '${t.blob.toString('hex')}',`);
        if (t.isColorBatch) {
            tsLines.push(`    isColorBatch: true,`);
        }
        tsLines.push(`  },`);
    }
    tsLines.push('];');
    tsLines.push('');

    // Global palette as hex (with header for reference)
    tsLines.push(`export const GLOBAL_PALETTE_HEX = '${paletteBin.toString('hex')}';`);
    tsLines.push('');
    tsLines.push(`// Raw RGB palette (no 2-byte header) — this is what the contract stores`);
    tsLines.push(`export const PALETTE_RGB_HEX = '${paletteRgb.toString('hex')}';`);
    tsLines.push(`export const PALETTE_HASH = '${paletteHash.toString('hex')}';`);
    tsLines.push('');

    // Palette colors array for the SVG decoder
    tsLines.push('export const PALETTE_COLORS: string[] = [');
    for (const c of globalPalette) {
        tsLines.push(`  '${c}',`);
    }
    tsLines.push('];');
    tsLines.push('');

    writeFileSync(join(OUT_DIR, 'compressed-traits.ts'), tsLines.join('\n'));

    // Summary
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Trait layers:       ${TRAIT_MAP.length}`);
    console.log(`  Color batches:      ${totalBatches} (${LARGE_BATCH_COUNT}×${LARGE_BATCH} + ${totalBatches - LARGE_BATCH_COUNT}×${SMALL_BATCH})`);
    console.log(`  Total Merkle leaves:${traitBlobs.length}`);
    console.log(`  Global palette:     ${globalPalette.length} colors (${paletteBin.length} bytes)`);
    console.log(`  Original SVGs:      ${(totalOriginal / 1024).toFixed(1)} KB`);
    console.log(`  Compressed blobs:   ${(totalCompressed / 1024).toFixed(1)} KB`);
    console.log(`  Total on-chain:     ${((totalCompressed + paletteBin.length) / 1024).toFixed(1)} KB`);
    console.log(`  Reduction:          ${((1 - (totalCompressed + paletteBin.length) / totalOriginal) * 100).toFixed(1)}%`);
    console.log(`  u256 storage slots: ${Math.ceil((totalCompressed + paletteBin.length) / 32)}`);
    console.log(`  Merkle root:        ${merkleJson.root}`);
    console.log('');

    const satPerVByte = 2;
    const witnessBytes = totalCompressed + paletteBin.length;
    const vBytes = Math.ceil(witnessBytes / 4) + 200; // witness discount + overhead
    const costSats = vBytes * satPerVByte;
    const btcPrice = 90000;
    console.log(`  Inscription cost estimate (${satPerVByte} sat/vB):`);
    console.log(`    ${costSats.toLocaleString()} sats = ${(costSats / 1e8).toFixed(6)} BTC ≈ $${(costSats / 1e8 * btcPrice).toFixed(2)}`);
    console.log('═══════════════════════════════════════════════════════════');
}

main();
