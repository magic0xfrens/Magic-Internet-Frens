#!/usr/bin/env tsx

/**
 * upload-collection-ipfs.ts — Generate & upload IPFS metadata for MiFrens
 *
 * Two modes:
 *
 * 1. PRE-MINT (default): Generates combo-keyed metadata for all valid trait combos.
 *    Files named: classIdx-bodyIdx-faceIdx-itemIdx
 *    No chain access needed — everything from local trait binaries.
 *
 * 2. POST-MINT (--post-mint): Generates per-tokenId metadata with OG Inscriber trait.
 *    Queries chain for each token's traits and OG status.
 *    Files named: 1, 2, 3, ... (tokenId)
 *    Requires DEPLOYER_MNEMONIC or RPC access.
 *
 * Usage:
 *   npx tsx contracts/scripts/upload-collection-ipfs.ts
 *   npx tsx contracts/scripts/upload-collection-ipfs.ts --output ./metadata-out
 *   npx tsx contracts/scripts/upload-collection-ipfs.ts --dry-run
 *   npx tsx contracts/scripts/upload-collection-ipfs.ts --skip-upload
 *   npx tsx contracts/scripts/upload-collection-ipfs.ts --post-mint --network regtest
 */

import * as fs from 'fs';
import { join } from 'path';
import { execSync } from 'child_process';

// ---------------------------------------------------------------------------
// Class definitions — mirrors MiFrens.onDeployment registerClass calls
// ---------------------------------------------------------------------------

interface ClassDef {
    name: string;
    classIdx: number;
    /** Explicit body indices to include (allows skipping removed bodies) */
    bodyIndices: number[];
    numFaces: number;
    numItems: number;
    /** Face classIdx for trait binary lookup (gnome=5, elf=6, others=0) */
    faceClassIdx: number;
    /** classIdx used for subitem trait binary lookup (peasant=4, others=0) */
    subitemClassIdx: number;
}

const CLASS_DEFS: ClassDef[] = [
    { name: 'Wizard',     classIdx: 0, bodyIndices: [0, 1, 2, 3, 4, 5, 6, 7], numFaces: 12, numItems: 5, faceClassIdx: 0, subitemClassIdx: 0 },
    { name: 'King',       classIdx: 1, bodyIndices: [0, 1, 2, 3, 4],          numFaces: 12, numItems: 4, faceClassIdx: 0, subitemClassIdx: 0 },
    { name: 'Knight',     classIdx: 2, bodyIndices: [0, 1, 2, 3],       numFaces: 12, numItems: 4, faceClassIdx: 0, subitemClassIdx: 0 },
    { name: 'Apprentice', classIdx: 3, bodyIndices: [0, 1, 2],          numFaces: 12, numItems: 1, faceClassIdx: 0, subitemClassIdx: 0 },
    { name: 'Peasant',    classIdx: 4, bodyIndices: [0, 1],             numFaces: 12, numItems: 3, faceClassIdx: 0, subitemClassIdx: 4 },
    { name: 'Gnome',      classIdx: 5, bodyIndices: [0, 1],             numFaces: 12, numItems: 4, faceClassIdx: 5, subitemClassIdx: 0 },
    { name: 'Elf',        classIdx: 6, bodyIndices: [0, 1, 2],          numFaces: 12, numItems: 1, faceClassIdx: 6, subitemClassIdx: 0 },
];

// ---------------------------------------------------------------------------
// CLI helpers
// ---------------------------------------------------------------------------

function getArg(flag: string): string | undefined {
    const idx = process.argv.indexOf(flag);
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : undefined;
}

function hasFlag(flag: string): boolean {
    return process.argv.includes(flag);
}

// ---------------------------------------------------------------------------
// Local SVG Renderer (TypeScript port of FrenForge AssemblyScript)
// ---------------------------------------------------------------------------

const CANVAS_SIDE = 120;

function compositeLayer(canvas: Uint8Array, layerData: Uint8Array, canvasSide: number): void {
    if (layerData.length < 10) return;

    const minX = layerData[3];
    const minY = layerData[4];
    const bboxW = layerData[5];
    const bboxH = layerData[6];
    const localPaletteSize = layerData[7];

    if (localPaletteSize === 0 || bboxW === 0 || bboxH === 0) return;

    const paletteStart = 8;
    const pixelDataStart = paletteStart + localPaletteSize;
    if (pixelDataStart >= layerData.length) return;

    const totalBBoxPixels = bboxW * bboxH;

    for (let p = 0; p < totalBBoxPixels; p++) {
        const nibbleByteOffset = pixelDataStart + (p >> 1);
        if (nibbleByteOffset >= layerData.length) break;

        const rawByte = layerData[nibbleByteOffset];
        const nibble = (p & 1) === 0
            ? (rawByte >> 4) & 0x0F
            : rawByte & 0x0F;

        if (nibble === 0) continue;

        const localIdx = nibble - 1;
        if (localIdx >= localPaletteSize) continue;

        const globalIdx = layerData[paletteStart + localIdx];
        const canvasValue = globalIdx + 1;

        const dx = p % bboxW;
        const dy = Math.floor(p / bboxW);
        const absX = minX + dx;
        const absY = minY + dy;

        if (absX >= canvasSide || absY >= canvasSide) continue;

        canvas[absY * canvasSide + absX] = canvasValue;
    }
}

function getTraitHash(bodyIdx: number, faceIdx: number, itemIdx: number): number {
    const seed = bodyIdx * 7919 + faceIdx * 6271 + itemIdx * 4813;
    return seed & 0xFFFF;
}

function clampColor(v: number): number {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return v;
}

function toHex2(n: number): string {
    return n.toString(16).padStart(2, '0');
}

// ---------------------------------------------------------------------------
// 28×28 BTC ₿ pixel art — 1 = logo (bright cream), 0 = background (BTC orange)
// 28×28 = 784 cells. 777 frens + 7 filler.
// ---------------------------------------------------------------------------

const GRID_COLS = 28;
const GRID_ROWS = 28;

// prettier-ignore
// Logo: 17 rows tall (rows 5-21), 12 cols wide (cols 8-19), centered in 28×28
const BTC_LOGO: string[] = [
    '0000000000000000000000000000', //  0
    '0000000000000000000000000000', //  1
    '0000000000000000000000000000', //  2
    '0000000000000000000000000000', //  3
    '0000000000000000000000000000', //  4
    '0000000000110011000000000000', //  5  bars above
    '0000000000110011000000000000', //  6
    '0000000011111111100000000000', //  7  top serif
    '0000000011111111110000000000', //  8
    '0000000000110000111000000000', //  9  upper body
    '0000000000110000011000000000', // 10
    '0000000000110000011000000000', // 11
    '0000000000110000111000000000', // 12
    '0000000000111111110000000000', // 13  middle
    '0000000000111111111000000000', // 14
    '0000000000110000011100000000', // 15  lower body
    '0000000000110000001100000000', // 16
    '0000000000110000011100000000', // 17
    '0000000011111111111000000000', // 18  bottom serif
    '0000000011111111110000000000', // 19
    '0000000000110011000000000000', // 20  bars below
    '0000000000110011000000000000', // 21
    '0000000000000000000000000000', // 22
    '0000000000000000000000000000', // 23
    '0000000000000000000000000000', // 24
    '0000000000000000000000000000', // 25
    '0000000000000000000000000000', // 26
    '0000000000000000000000000000', // 27
];

function isLogoCell(gridPos: number): boolean {
    const row = Math.floor(gridPos / GRID_COLS);
    const col = gridPos % GRID_COLS;
    if (row >= GRID_ROWS || col >= GRID_COLS) return false;
    return BTC_LOGO[row][col] === '1';
}

// ---------------------------------------------------------------------------
// Gradient builder — logo cells get bright cream, background gets BTC orange
// ---------------------------------------------------------------------------

function buildGradient(hash: number, logoBit: boolean): { gradientDef: string; } {
    // Subtle per-cell variation from hash
    const shift1R = (((hash >> 0) & 0xF) - 8);    // -8..+7
    const shift1G = (((hash >> 4) & 0xF) - 8);
    const shift1B = (((hash >> 8) & 0x7) - 4);     // -4..+3
    const shift2R = (((hash >> 3) & 0xF) - 8);
    const shift2G = (((hash >> 7) & 0xF) - 8);
    const shift2B = (((hash >> 11) & 0x7) - 4);

    let c1R: number, c1G: number, c1B: number;
    let c2R: number, c2G: number, c2B: number;

    if (logoBit) {
        // Light BTC orange:  base ~#FCC265 / #FABA50 — lighter orange, still warm
        c1R = clampColor(252 + (shift1R >> 2));
        c1G = clampColor(194 + shift1G);
        c1B = clampColor(101 + shift1B);
        c2R = clampColor(250 + (shift2R >> 2));
        c2G = clampColor(186 + shift2G);
        c2B = clampColor(80  + shift2B);
    } else {
        // Standard BTC orange:  base ~#F7931A / #ED8914
        c1R = clampColor(247 + shift1R);
        c1G = clampColor(147 + shift1G);
        c1B = clampColor(26  + shift1B);
        c2R = clampColor(237 + shift2R);
        c2G = clampColor(137 + shift2G);
        c2B = clampColor(20  + shift2B);
    }

    const color1 = toHex2(c1R) + toHex2(c1G) + toHex2(c1B);
    const color2 = toHex2(c2R) + toHex2(c2G) + toHex2(c2B);

    // Pick gradient direction from hash (8 linear + 2 radial = 10 types)
    const gradType = (hash >> 12) % 10;

    const linearDirs: [number, number, number, number][] = [
        [0, 0, 0, 1],   // top → bottom
        [0, 1, 0, 0],   // bottom → top
        [0, 0, 1, 0],   // left → right
        [1, 0, 0, 0],   // right → left
        [0, 0, 1, 1],   // TL → BR
        [1, 1, 0, 0],   // BR → TL
        [0, 1, 1, 0],   // BL → TR
        [1, 0, 0, 1],   // TR → BL
    ];

    let gradientDef: string;
    if (gradType < 8) {
        const [x1, y1, x2, y2] = linearDirs[gradType];
        gradientDef = `<linearGradient id="bg" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">`
            + `<stop offset="0" stop-color="#${color1}"/>`
            + `<stop offset="1" stop-color="#${color2}"/>`
            + '</linearGradient>';
    } else {
        const cx = gradType === 8 ? '50%' : '30%';
        const cy = gradType === 8 ? '50%' : '30%';
        gradientDef = `<radialGradient id="bg" cx="${cx}" cy="${cy}" r="70%">`
            + `<stop offset="0" stop-color="#${color1}"/>`
            + `<stop offset="1" stop-color="#${color2}"/>`
            + '</radialGradient>';
    }

    return { gradientDef };
}

// ---------------------------------------------------------------------------
// SVG renderer
// ---------------------------------------------------------------------------

function renderSVG(
    palette: Uint8Array,
    bodyData: Uint8Array,
    faceData: Uint8Array,
    itemData: Uint8Array,
    subitemData: Uint8Array,
    _classIdx: number,
    bodyIdx: number,
    faceIdx: number,
    itemIdx: number,
    logoBit: boolean,
): string {
    const side = CANVAS_SIDE;
    const totalPixels = side * side;

    const canvas = new Uint8Array(totalPixels);
    compositeLayer(canvas, faceData, side);
    compositeLayer(canvas, bodyData, side);
    compositeLayer(canvas, itemData, side);
    if (subitemData.length > 0) {
        compositeLayer(canvas, subitemData, side);
    }

    const hash = getTraitHash(bodyIdx, faceIdx, itemIdx);
    const { gradientDef } = buildGradient(hash, logoBit);

    let svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" shape-rendering="crispEdges">'
        + `<defs>${gradientDef}</defs>`
        + '<rect width="120" height="120" fill="url(#bg)"/>';

    interface Run { colorIdx: number; x: number; y: number; w: number; }
    const runs: Run[] = [];
    const usedColors = new Set<number>();

    for (let y = 0; y < side; y++) {
        const rowBase = y * side;
        let x = 0;
        while (x < side) {
            const c = canvas[rowBase + x];
            if (c === 0) { x++; continue; }

            let w = 1;
            for (let rx = x + 1; rx < side; rx++) {
                if (canvas[rowBase + rx] !== c) break;
                w++;
            }

            runs.push({ colorIdx: c, x, y, w });
            usedColors.add(c);
            x += w;
        }
    }

    for (let c = 1; c < 256; c++) {
        if (!usedColors.has(c)) continue;

        const colorOffset = (c - 1) * 3;
        if (colorOffset + 2 >= palette.length) continue;

        const r = palette[colorOffset];
        const g = palette[colorOffset + 1];
        const b = palette[colorOffset + 2];
        const hex = toHex2(r) + toHex2(g) + toHex2(b);

        let d = '';
        for (const run of runs) {
            if (run.colorIdx !== c) continue;
            d += `M${run.x} ${run.y}h${run.w}v1h-${run.w}z`;
        }

        svg += `<path d="${d}" fill="#${hex}"/>`;
    }

    svg += '</svg>';
    return svg;
}

// ---------------------------------------------------------------------------
// Trait name lookup helpers
// ---------------------------------------------------------------------------

function bodyVariantName(classIdx: number, bodyIdx: number): string {
    const map: Record<number, Record<number, string>> = {
        0: { 0: 'Astral', 1: 'Fire', 2: 'Earth', 3: 'Storm', 4: 'Void', 5: 'Jester', 6: 'Manifest', 7: 'Satoshi' },
        1: { 0: 'Onyx', 1: 'Sapphire', 2: 'Bitcoin', 3: 'Crimson', 4: 'Ivory' },
        2: { 0: 'Bronze', 1: 'Gold', 2: 'Bitcoin', 3: 'Silver' },
        3: { 0: 'Novice', 1: 'Adept', 2: 'Bitcoin' },
        4: { 0: 'Farmer', 1: 'Miller' },
        5: { 0: 'Gnomeland', 1: 'Miner' },
        6: { 0: 'Woodland', 1: 'Twilight', 2: 'Indigo' },
    };
    return map[classIdx]?.[bodyIdx] ?? `Variant ${bodyIdx}`;
}

function faceVariantName(faceIdx: number): string {
    const names: Record<number, string> = {
        0: 'Classic',
        1: 'Happy',
        2: 'Angry',
        3: 'Feels Bad',
        4: 'Grinding',
        5: 'Chill',
        6: 'Grumpy',
        7: 'Giga Happy',
        8: 'Cooked',
        9: 'Comfy',
        10: 'Retard',
        11: 'Laser Eyes',
    };
    return names[faceIdx] ?? `Face ${faceIdx}`;
}

function itemVariantName(classIdx: number, itemIdx: number): string {
    const map: Record<number, Record<number, string> | string> = {
        0: { 0: 'Frost Staff', 1: 'Solar Staff', 2: 'Verdant Staff', 3: 'Crimson Staff', 4: 'Hermes Staff' },
        1: { 0: 'Scepter Black', 1: 'Scepter Blue', 2: 'Scepter Red', 3: 'Scepter White' },
        2: { 0: 'Shield Bronze', 1: 'Shield Gold', 2: 'Shield Orange', 3: 'Shield Silver' },
        3: 'Tome',
        4: { 0: 'Pitchfork', 1: 'Shovel', 2: 'Hoe' },
        5: { 0: 'Daisy Pick', 1: 'Toadstool', 2: 'Star Pick', 3: 'BTC Pickaxe' },
        6: 'Bow',
    };
    const val = map[classIdx];
    if (typeof val === 'string') return val;
    if (typeof val === 'object') return val[itemIdx] ?? `Item ${itemIdx}`;
    return `Item ${itemIdx}`;
}

// ---------------------------------------------------------------------------
// File helpers
// ---------------------------------------------------------------------------

function readTraitBinary(traitsDir: string, layerType: number, classIdx: number, layerIdx: number): Uint8Array {
    const filename = `trait-${layerType}-${classIdx}-${layerIdx}.bin`;
    const filePath = join(traitsDir, filename);
    if (!fs.existsSync(filePath)) {
        return new Uint8Array(0);
    }
    return new Uint8Array(fs.readFileSync(filePath));
}

function readPalette(traitsDir: string): Uint8Array {
    const palettePath = join(traitsDir, 'palette-rgb.bin');
    if (fs.existsSync(palettePath)) {
        return new Uint8Array(fs.readFileSync(palettePath));
    }
    const fullPalettePath = join(traitsDir, 'palette.bin');
    const buf = fs.readFileSync(fullPalettePath);
    return new Uint8Array(buf.subarray(2));
}

// ---------------------------------------------------------------------------
// Generate metadata for a single combo
// ---------------------------------------------------------------------------

function subitemVariantName(classIdx: number, subitemIdx: number): string {
    if (subitemIdx === 0) return 'None';
    if (classIdx === 4) {
        if (subitemIdx === 1) return 'MuMu Hat';
        if (subitemIdx === 2) return 'BoBo Hat';
    }
    if (subitemIdx === 1) return 'Potion';
    if (subitemIdx === 2) return 'Skull';
    return `Subitem ${subitemIdx}`;
}

function generateComboData(
    classDef: ClassDef,
    bodyIdx: number,
    faceIdx: number,
    itemIdx: number,
    subitemIdx: number,
    palette: Uint8Array,
    traitsDir: string,
    logoBit: boolean,
): { svg: string; svgSize: number; comboKey: string; bodyName: string; faceName: string; itemName: string; subitemName: string } {
    const comboKey = `${classDef.classIdx}-${bodyIdx}-${faceIdx}-${itemIdx}-${subitemIdx}`;

    const bodyData = readTraitBinary(traitsDir, 0, classDef.classIdx, bodyIdx);
    const faceData = readTraitBinary(traitsDir, 1, classDef.faceClassIdx, faceIdx);
    const itemData = readTraitBinary(traitsDir, 2, classDef.classIdx, itemIdx);

    // Read subitem binary (layerType=3, classIdx depends on class)
    let subitemData = new Uint8Array(0);
    if (subitemIdx > 0) {
        subitemData = readTraitBinary(traitsDir, 3, classDef.subitemClassIdx, subitemIdx - 1);
    }

    if (bodyData.length === 0) {
        console.warn(`  [${comboKey}] WARNING: Missing body file for class=${classDef.classIdx} body=${bodyIdx}`);
    }

    const svg = renderSVG(palette, bodyData, faceData, itemData, subitemData, classDef.classIdx, bodyIdx, faceIdx, itemIdx, logoBit);

    const bodyName = bodyVariantName(classDef.classIdx, bodyIdx);
    const faceName = faceVariantName(faceIdx);
    const itemName = itemVariantName(classDef.classIdx, itemIdx);
    const subitemName = subitemVariantName(classDef.classIdx, subitemIdx);

    return { svg, svgSize: Buffer.byteLength(svg), comboKey, bodyName, faceName, itemName, subitemName };
}

function buildMetadata(
    classDef: ClassDef,
    comboKey: string,
    bodyName: string,
    faceName: string,
    itemName: string,
    subitemName: string,
    svgImageURI: string,
    isLight: boolean,
): object {
    const bgLabel = isLight ? 'BTC Symbol' : 'BTC Orange';

    const attributes: Array<{ trait_type: string; value: string }> = [
        { trait_type: 'Class', value: classDef.name },
        { trait_type: 'Body', value: bodyName },
        { trait_type: 'Face', value: faceName },
        { trait_type: 'Item', value: itemName },
        { trait_type: 'Background', value: bgLabel },
    ];

    if (subitemName !== 'None') {
        attributes.push({ trait_type: 'Accessory', value: subitemName });
    }

    return {
        name: `MiFren — ${classDef.name} ${bodyName}`,
        description: `Magic Internet Fren — ${classDef.name} class, ${bodyName} body, ${faceName}, ${itemName}`,
        image: svgImageURI,
        attributes,
    };
}

// ---------------------------------------------------------------------------
// IPFS upload
// ---------------------------------------------------------------------------

function uploadToIPFS(dirPath: string): string | null {
    // Try `ipfs` CLI (kubo)
    try {
        const result = execSync(`ipfs add -r --cid-version=1 -Q "${dirPath}"`, {
            encoding: 'utf-8',
            timeout: 600_000,
        }).trim();
        return result;
    } catch {
        // ipfs CLI not available or daemon not running
    }

    // Try npx w3 CLI (web3.storage)
    try {
        const result = execSync(`npx w3 up "${dirPath}" --json`, {
            encoding: 'utf-8',
            timeout: 600_000,
        }).trim();
        const parsed = JSON.parse(result);
        return parsed.root?.toString() ?? parsed.cid ?? null;
    } catch {
        // w3 CLI not available
    }

    return null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function clearDir(dir: string): void {
    if (fs.existsSync(dir)) {
        const existing = fs.readdirSync(dir);
        for (const f of existing) fs.unlinkSync(join(dir, f));
    } else {
        fs.mkdirSync(dir, { recursive: true });
    }
}

function generateGridPreview(svgDir: string, comboKeys: string[], outputPath: string): void {
    let html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>MiFrens 28x28 BTC Grid</title>
<style>
body { margin: 0; padding: 20px; background: #111; }
h1 { color: #f7931a; font-family: monospace; text-align: center; }
.grid { display: grid; grid-template-columns: repeat(${GRID_COLS}, 1fr); gap: 0; max-width: 1400px; margin: 0 auto; }
.cell img { width: 100%; height: 100%; display: block; image-rendering: pixelated; }
.cell { aspect-ratio: 1; overflow: hidden; }
.filler { background: #f7931a; }
</style></head><body>
<h1>MiFrens Collection Grid — 28x28 BTC Logo</h1>
<div class="grid">`;

    const totalCells = GRID_ROWS * GRID_COLS;
    for (let i = 0; i < totalCells; i++) {
        if (i < comboKeys.length) {
            html += `<div class="cell"><img src="svg-out/${comboKeys[i]}.svg"/></div>`;
        } else {
            html += `<div class="cell filler"></div>`;
        }
    }

    html += '</div></body></html>';
    fs.writeFileSync(outputPath, html);
}

// ---------------------------------------------------------------------------
// Post-mint mode: per-tokenId metadata with OG Inscriber attribute
// ---------------------------------------------------------------------------

interface NetworkConfig {
    rpcUrl: string;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'https://regtest.opnet.org' },
    testnet: { rpcUrl: 'https://testnet.opnet.org' },
};

interface DeploymentData {
    contracts: {
        MIFRENS: string;
        FRENFORGE?: string;
    };
}

function loadDeployment(networkName: string): DeploymentData {
    const filePath = join(__dirname, `../deployments/${networkName}.json`);
    if (!fs.existsSync(filePath)) {
        console.error(`No deployment file at ${filePath}. Run deploy first.`);
        process.exit(1);
    }
    return JSON.parse(fs.readFileSync(filePath, 'utf-8')) as DeploymentData;
}

async function postMintGenerate(
    svgDir: string,
    metaDir: string,
    traitsDir: string,
    palette: Uint8Array,
    dryRun: boolean,
    skipUpload: boolean,
): Promise<void> {
    const { Address } = await import('@btc-vision/transaction');
    const { networks } = await import('@btc-vision/bitcoin');
    const { getContract, JSONRpcProvider, OP_20_ABI } = await import('opnet');

    const networkName = getArg('--network') ?? 'regtest';
    const netConfig = NETWORKS[networkName];
    if (!netConfig) {
        console.error(`Unknown network "${networkName}".`);
        process.exit(1);
    }

    const deployment = loadDeployment(networkName);
    const nftAddress = deployment.contracts.MIFRENS;
    const forgeAddress = deployment.contracts.FRENFORGE;
    if (!forgeAddress) {
        console.error('FRENFORGE address not found in deployment file.');
        process.exit(1);
    }

    const network = networkName === 'testnet' ? networks.opnetTestnet : networks.regtest;

    console.log(`\n  Post-mint mode: querying ${networkName}`);
    console.log(`  NFT contract:   ${nftAddress}`);
    console.log(`  Forge contract: ${forgeAddress}\n`);

    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network });

    const nftContract = getContract(
        Address.fromString(nftAddress),
        OP_20_ABI,
        rpcProvider,
        network,
    );

    const forgeContract = getContract(
        Address.fromString(forgeAddress),
        OP_20_ABI,
        rpcProvider,
        network,
    );

    // Get total minted
    const totalMintedResult = await nftContract.execute('totalMinted', []);
    const totalMinted = Number(totalMintedResult.decoded?.[0] as bigint ?? 0n);
    console.log(`  Total minted: ${totalMinted}\n`);

    if (totalMinted === 0) {
        console.log('  No tokens minted yet. Run in default mode first.');
        await rpcProvider.close();
        return;
    }

    if (!dryRun) {
        clearDir(svgDir);
        clearDir(metaDir);
    }

    // Map classIdx → ClassDef for name lookups
    const classMap = new Map<number, ClassDef>();
    for (const cd of CLASS_DEFS) classMap.set(cd.classIdx, cd);

    let svgCid: string | null = null;

    // Phase 1: Generate SVGs for each minted token
    console.log('Phase 1: Generating per-token SVGs...\n');
    let totalSvgBytes = 0;

    for (let tokenId = 1; tokenId <= totalMinted; tokenId++) {
        try {
            // Query token traits from NFT contract (5 values: class, body, face, item, subitem)
            const traitsResult = await nftContract.execute('getTokenTraits', [BigInt(tokenId)]);
            const decoded = traitsResult.decoded ?? [];
            const classIdx = Number(decoded[0] as bigint ?? 0n);
            const bodyIdx = Number(decoded[1] as bigint ?? 0n);
            const faceIdx = Number(decoded[2] as bigint ?? 0n);
            const itemIdx = Number(decoded[3] as bigint ?? 0n);
            const subitemIdx = Number(decoded[4] as bigint ?? 0n);

            const classDef = classMap.get(classIdx);
            if (!classDef) {
                console.warn(`  Token #${tokenId}: unknown classIdx ${classIdx}, skipping`);
                continue;
            }

            const comboKey = `${classIdx}-${bodyIdx}-${faceIdx}-${itemIdx}-${subitemIdx}`;
            const gridPos = tokenId - 1;
            const logoBit = isLogoCell(gridPos);

            // Query OG inscriber status from NFT contract (moved from FrenForge)
            const ogResult = await nftContract.execute('isOGInscriber', [BigInt(tokenId)]);
            const isOG = Boolean(ogResult.decoded?.[0]);

            // Generate SVG
            const bodyData = readTraitBinary(traitsDir, 0, classIdx, bodyIdx);
            const faceClassIdx = classDef.faceClassIdx;
            const faceData = readTraitBinary(traitsDir, 1, faceClassIdx, faceIdx);
            const itemData = readTraitBinary(traitsDir, 2, classIdx, itemIdx);

            // Read subitem binary
            let subitemData = new Uint8Array(0);
            if (subitemIdx > 0) {
                const subitemClassIdx = classDef.subitemClassIdx;
                subitemData = readTraitBinary(traitsDir, 3, subitemClassIdx, subitemIdx - 1);
            }

            const svg = renderSVG(palette, bodyData, faceData, itemData, subitemData, classIdx, bodyIdx, faceIdx, itemIdx, logoBit);

            if (!dryRun) {
                fs.writeFileSync(join(svgDir, `${tokenId}.svg`), svg);
            }

            totalSvgBytes += Buffer.byteLength(svg);

            const bodyName = bodyVariantName(classIdx, bodyIdx);
            const faceName = faceVariantName(faceIdx);
            const itemName = itemVariantName(classIdx, itemIdx);
            const subitemName = subitemVariantName(classIdx, subitemIdx);

            // Build metadata with OG + subitem attributes
            const attributes: Array<{ trait_type: string; value: string }> = [
                { trait_type: 'Class', value: classDef.name },
                { trait_type: 'Body', value: bodyName },
                { trait_type: 'Face', value: faceName },
                { trait_type: 'Item', value: itemName },
            ];
            if (subitemName !== 'None') {
                attributes.push({ trait_type: 'Accessory', value: subitemName });
            }
            if (isOG) {
                attributes.push({ trait_type: 'OG Inscriber', value: 'Yes' });
            }

            const metadata = {
                name: `MiFren #${tokenId}`,
                description: `Magic Internet Fren #${tokenId} — ${classDef.name} class, ${bodyName} body, ${faceName}, ${itemName}`,
                image: `SVG_CID_PLACEHOLDER/${tokenId}.svg`,
                attributes,
            };

            if (!dryRun) {
                fs.writeFileSync(join(metaDir, String(tokenId)), JSON.stringify(metadata, null, 2));
            }

            const ogStr = isOG ? ' [OG]' : '';
            process.stdout.write(`  #${tokenId} ${comboKey} ${classDef.name} ${bodyName}${ogStr}\n`);
        } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            console.error(`  #${tokenId} ERROR: ${msg.slice(0, 200)}`);
        }
    }

    console.log(`\n  Generated ${totalMinted} token SVGs (${(totalSvgBytes / 1024 / 1024).toFixed(1)} MB)\n`);

    // Phase 2: Upload SVGs
    if (!skipUpload && !dryRun) {
        console.log('Phase 2: Uploading SVGs to IPFS...');
        svgCid = uploadToIPFS(svgDir);
        if (svgCid) {
            console.log(`  SVG CID: ${svgCid}\n`);

            // Update metadata image URIs with actual CID
            for (let tokenId = 1; tokenId <= totalMinted; tokenId++) {
                const metaPath = join(metaDir, String(tokenId));
                if (fs.existsSync(metaPath)) {
                    const meta = JSON.parse(fs.readFileSync(metaPath, 'utf-8'));
                    meta.image = `ipfs://${svgCid}/${tokenId}.svg`;
                    fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
                }
            }
        }
    }

    // Phase 3: Upload metadata
    if (!skipUpload && !dryRun) {
        console.log('Phase 3: Uploading metadata to IPFS...');
        const metaCid = uploadToIPFS(metaDir);
        if (metaCid) {
            console.log(`\n  Metadata CID: ${metaCid}`);
            console.log(`  SVG CID:      ${svgCid}`);
            console.log(`  Gateway:      https://ipfs.io/ipfs/${metaCid}/1`);
            console.log(`\n  Base URI for setBaseURI: ipfs://${metaCid}/`);

            const uriStr = `ipfs://${metaCid}/`;
            const uriHex = Buffer.from(uriStr).toString('hex');
            console.log(`    URI string: ${uriStr}`);
            console.log(`    URI hex:    0x${uriHex}`);
            console.log('\n  NOTE: tokenURI must return baseURI + tokenId (not combo key).');
        }
    }

    await rpcProvider.close();
    console.log('\nPost-mint metadata generation complete.\n');
}

function main(): void {
    const baseDir = join(__dirname, '..', '..');
    const svgDir = getArg('--svg-output') ?? join(baseDir, 'svg-out');
    const metaDir = getArg('--output') ?? join(baseDir, 'metadata-out');
    const dryRun = hasFlag('--dry-run');
    const skipUpload = hasFlag('--skip-upload');
    const traitsDir = join(baseDir, 'compressed-traits');

    // ── Post-mint mode: per-tokenId metadata with OG Inscriber ────────
    if (hasFlag('--post-mint')) {
        console.log('Reading local palette...');
        const palette = readPalette(traitsDir);
        console.log(`  Palette: ${palette.length} bytes (${palette.length / 3} colors)\n`);
        postMintGenerate(svgDir, metaDir, traitsDir, palette, dryRun, skipUpload)
            .catch((err) => { console.error('Post-mint failed:', err); process.exit(1); });
        return;
    }

    const COLLECTION_SIZE = 777;
    const GRID_TOTAL = GRID_ROWS * GRID_COLS; // 784

    const NUM_SUBITEMS = 3; // 0=none, 1=potion/mumu, 2=skull/bobo
    let totalCombos = 0;
    for (const cd of CLASS_DEFS) {
        totalCombos += cd.bodyIndices.length * cd.numFaces * cd.numItems * NUM_SUBITEMS;
    }

    // Count logo pixels
    let logoCells = 0;
    for (let r = 0; r < GRID_ROWS; r++) {
        for (let c = 0; c < GRID_COLS; c++) {
            if (BTC_LOGO[r][c] === '1') logoCells++;
        }
    }

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — IPFS Metadata + SVG Generator');
    console.log('  28×28 BTC ₿ Grid Mode');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  SVG output:      ${svgDir}`);
    console.log(`  Metadata output: ${metaDir}`);
    console.log(`  Dry run:         ${dryRun}`);
    console.log(`  Total combos:    ${totalCombos}`);
    console.log(`  Collection size: ${COLLECTION_SIZE}`);
    console.log(`  Grid:            ${GRID_COLS}×${GRID_ROWS} = ${GRID_TOTAL} cells (${GRID_TOTAL - COLLECTION_SIZE} filler)`);
    console.log(`  BTC logo cells:  ${logoCells} bright / ${GRID_TOTAL - logoCells} orange`);
    console.log('');
    for (const cd of CLASS_DEFS) {
        const base = cd.bodyIndices.length * cd.numFaces * cd.numItems;
        const count = base * NUM_SUBITEMS;
        console.log(`    ${cd.name.padEnd(12)} ${cd.bodyIndices.length} bodies × ${cd.numFaces} faces × ${cd.numItems} items × ${NUM_SUBITEMS} subitems = ${count}`);
    }
    console.log('═══════════════════════════════════════════════════════════\n');

    console.log('Reading local palette...');
    const palette = readPalette(traitsDir);
    console.log(`  Palette: ${palette.length} bytes (${palette.length / 3} colors)\n`);

    // ── Build per-class combo lists, then interleave via round-robin ────
    // Base combos (subitemIdx=0) are interleaved first for grid positioning,
    // then subitem variants (1, 2) are appended after.
    interface ComboSpec { classDef: ClassDef; bodyIdx: number; faceIdx: number; itemIdx: number; subitemIdx: number; }

    // Step 1: Build base combos (subitemIdx=0) per class
    const basePerClass: ComboSpec[][] = [];
    for (const classDef of CLASS_DEFS) {
        const list: ComboSpec[] = [];
        for (const bodyIdx of classDef.bodyIndices) {
            for (let faceIdx = 0; faceIdx < classDef.numFaces; faceIdx++) {
                for (let itemIdx = 0; itemIdx < classDef.numItems; itemIdx++) {
                    list.push({ classDef, bodyIdx, faceIdx, itemIdx, subitemIdx: 0 });
                }
            }
        }
        basePerClass.push(list);
    }

    // Step 2: Round-robin interleave base combos (these fill the 28×28 grid)
    const interleaved: ComboSpec[] = [];
    const maxLen = Math.max(...basePerClass.map(c => c.length));
    for (let i = 0; i < maxLen; i++) {
        for (const classComboList of basePerClass) {
            if (i < classComboList.length) {
                interleaved.push(classComboList[i]);
            }
        }
    }
    const baseCombosCount = interleaved.length;

    // Step 3: Append subitem variants (subitemIdx=1,2) after all base combos
    for (const classComboList of basePerClass) {
        for (const combo of classComboList) {
            for (let si = 1; si < NUM_SUBITEMS; si++) {
                interleaved.push({ ...combo, subitemIdx: si });
            }
        }
    }

    console.log(`  Base combos:    ${baseCombosCount} (fill 28×28 grid)`);
    console.log(`  Subitem combos: ${interleaved.length - baseCombosCount} (potion/skull/mumu/bobo variants)`);
    console.log(`  Total:          ${interleaved.length} combos across ${CLASS_DEFS.length} classes\n`);

    // ── Phase 1: Generate SVG files — TWO variants per combo ───
    // Normal (BTC orange background) + Light (bright orange for BTC logo cells).
    // The contract picks which variant to serve based on tokenId grid position.
    console.log('Phase 1: Generating SVG files (normal + light variants)...\n');
    if (!dryRun) {
        clearDir(svgDir);
    }

    interface ComboInfo { classDef: ClassDef; comboKey: string; bodyName: string; faceName: string; itemName: string; subitemName: string; }
    const combos: ComboInfo[] = [];
    let successCount = 0;
    let failCount = 0;
    let totalSvgBytes = 0;

    for (const { classDef, bodyIdx, faceIdx, itemIdx, subitemIdx } of interleaved) {
        try {
            // Normal variant (standard BTC orange background)
            const normal = generateComboData(classDef, bodyIdx, faceIdx, itemIdx, subitemIdx, palette, traitsDir, false);
            // Light variant (bright orange for BTC logo cells)
            const light = generateComboData(classDef, bodyIdx, faceIdx, itemIdx, subitemIdx, palette, traitsDir, true);

            if (!dryRun) {
                fs.writeFileSync(join(svgDir, `${normal.comboKey}.svg`), normal.svg);
                fs.writeFileSync(join(svgDir, `${normal.comboKey}-L.svg`), light.svg);
            }

            combos.push({
                classDef, comboKey: normal.comboKey,
                bodyName: normal.bodyName, faceName: normal.faceName,
                itemName: normal.itemName, subitemName: normal.subitemName,
            });
            totalSvgBytes += normal.svgSize + light.svgSize;
            successCount++;
        } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            const comboKey = `${classDef.classIdx}-${bodyIdx}-${faceIdx}-${itemIdx}-${subitemIdx}`;
            console.error(`    [${comboKey}] ERROR: ${msg.slice(0, 200)}`);
            failCount++;
        }
    }

    console.log('\n═══════════════════════════════════════════════════════════');
    console.log(`  Phase 1 done: ${successCount}/${totalCombos} combos (${successCount * 2} SVG files)`);
    console.log(`  Failed:       ${failCount}`);
    console.log(`  Avg SVG:      ${successCount > 0 ? Math.round(totalSvgBytes / (successCount * 2)) : 0} bytes`);
    console.log(`  Total:        ${(totalSvgBytes / 1024 / 1024).toFixed(1)} MB`);
    console.log('═══════════════════════════════════════════════════════════\n');

    if (!dryRun) {
        // Generate grid preview HTML (uses base combos for grid, normal variant)
        const previewPath = join(baseDir, 'grid-preview.html');
        const comboKeys = combos.map(c => c.comboKey);
        generateGridPreview(svgDir, comboKeys, previewPath);
        console.log(`  Grid preview: ${previewPath}\n`);
    }

    if (dryRun) {
        console.log('Dry run complete — no files written.\n');
        return;
    }

    // ── Phase 2: Upload SVGs to IPFS ─────────────────────────────────────
    let svgCid: string | null = null;

    if (!skipUpload) {
        console.log('Phase 2: Uploading SVGs to IPFS...');
        svgCid = uploadToIPFS(svgDir);

        if (svgCid) {
            console.log(`  SVG CID: ${svgCid}`);
            console.log(`  Normal:  https://ipfs.io/ipfs/${svgCid}/0-0-0-0-0.svg`);
            console.log(`  Light:   https://ipfs.io/ipfs/${svgCid}/0-0-0-0-0-L.svg\n`);
        } else {
            console.log('\n  SVG IPFS upload failed. Make sure the IPFS daemon is running.');
            console.log('  Falling back to placeholder URI — re-run without --skip-upload.\n');
        }
    }

    const svgBaseURI = svgCid ? `ipfs://${svgCid}` : 'ipfs://SVG_CID_PLACEHOLDER';

    // ── Phase 3: Generate metadata JSON with IPFS image links ────────────
    // Two metadata files per combo: normal (comboKey) + light (comboKey-L)
    console.log('Phase 3: Generating metadata JSON (normal + light)...');
    clearDir(metaDir);

    for (const { classDef, comboKey, bodyName, faceName, itemName, subitemName } of combos) {
        // Normal background metadata
        const metaNormal = buildMetadata(
            classDef, comboKey, bodyName, faceName, itemName, subitemName,
            `${svgBaseURI}/${comboKey}.svg`, false,
        );
        fs.writeFileSync(join(metaDir, comboKey), JSON.stringify(metaNormal, null, 2));

        // Light background metadata (BTC symbol cell)
        const metaLight = buildMetadata(
            classDef, comboKey, bodyName, faceName, itemName, subitemName,
            `${svgBaseURI}/${comboKey}-L.svg`, true,
        );
        fs.writeFileSync(join(metaDir, `${comboKey}-L`), JSON.stringify(metaLight, null, 2));
    }
    console.log(`  Wrote ${combos.length * 2} metadata files (${combos.length} normal + ${combos.length} light).\n`);

    // ── Phase 4: Upload metadata to IPFS ─────────────────────────────────
    if (!skipUpload) {
        console.log('Phase 4: Uploading metadata to IPFS...');
        const metaCid = uploadToIPFS(metaDir);

        if (metaCid) {
            console.log(`\n  Metadata CID: ${metaCid}`);
            console.log(`  SVG CID:      ${svgCid}`);
            console.log(`  Normal:       https://ipfs.io/ipfs/${metaCid}/0-0-0-0-0`);
            console.log(`  Light:        https://ipfs.io/ipfs/${metaCid}/0-0-0-0-0-L`);
            console.log(`\n  Base URI for setBaseURI: ipfs://${metaCid}/`);
            console.log('\n  Next step: Call FrenForge.setBaseURI() with the URI bytes.');

            const uriStr = `ipfs://${metaCid}/`;
            const uriHex = Buffer.from(uriStr).toString('hex');
            console.log(`    URI string: ${uriStr}`);
            console.log(`    URI hex:    0x${uriHex}`);
        } else {
            console.log('\n  Metadata IPFS upload failed. Make sure the IPFS daemon is running:');
            console.log('    ipfs daemon &');
            console.log(`    ipfs add -r --cid-version=1 -Q "${metaDir}"`);
        }
    } else {
        console.log('Skipped IPFS upload (--skip-upload).');
        console.log(`\nTo upload manually:`);
        console.log(`  ipfs add -r --cid-version=1 -Q "${svgDir}"    # get SVG_CID`);
        console.log(`  # then update metadata image URIs with the SVG_CID`);
        console.log(`  ipfs add -r --cid-version=1 -Q "${metaDir}"   # get METADATA_CID`);
    }

    console.log('\n═══════════════════════════════════════════════════════════\n');
}

main();
