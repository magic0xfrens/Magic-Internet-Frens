#!/usr/bin/env node
/**
 * Generate NFT metadata JSON files for MiFrens collection.
 *
 * Reads trait indices from the contract (or uses defaults) and generates
 * standard NFT metadata JSON files referencing IPFS-hosted SVG layers.
 *
 * Usage:
 *   node scripts/generate-metadata.mjs <ipfs-cid>
 *
 * Output: public/nft/0.json, public/nft/1.json, ... public/nft/776.json
 */

import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

// Trait definitions matching src/data/frens.ts
const CLASSES = ['Wizard', 'King', 'Knight', 'Apprentice', 'Peasant'];
const CLASS_COLORS = ['#a78bfa', '#FFD700', '#75c9ee', '#F7931A', '#9ca3af'];

const BODIES = {
    Wizard: ['wizard-01.svg', 'wizard-02.svg', 'wizard-03.svg', 'wizard-04.svg', 'wizard-05.svg', 'wizard-06.svg', 'wizard-manifest.svg'],
    King: ['king-cloth-black.svg', 'king-cloth-blue.svg', 'king-cloth-red.svg', 'king-cloth-white.svg'],
    Knight: ['knight-bronze.svg', 'knight-gold.svg', 'knight-silver.svg'],
    Apprentice: ['apprentice-01.svg', 'apprentice-02.svg'],
    Peasant: ['peasant-01.svg', 'peasant-02.svg'],
};

const FACES = [
    'face-01.svg', 'face-02.svg', 'face-03.svg', 'face-04.svg', 'face-05.svg',
    'face-06.svg', 'face-07.svg', 'face-08.svg', 'face-09.svg', 'face-10.svg', 'face-11.svg',
];

const ITEMS = {
    Wizard: ['wiz-item-01.svg', 'wiz-item-02.svg', 'wiz-item-03.svg', 'wiz-item-04.svg', 'wiz-item-manifest.svg'],
    King: ['king-item-black.svg', 'king-item-blue.svg', 'king-item-red.svg', 'king-item-white.svg'],
    Knight: ['knight-item-bronze.svg', 'knight-item-gold.svg', 'knight-item-silver.svg'],
    Apprentice: ['apprentice-item-01.svg'],
    Peasant: ['peasant-item-01.svg'],
};

const TIERS = ['Bronze', 'Silver', 'Gold', 'Diamond'];

const MAX_SUPPLY = 777;

async function main() {
    let ipfsCid = process.argv[2];

    if (!ipfsCid) {
        // Try reading from .ipfs-cid file
        try {
            ipfsCid = (await readFile(resolve(import.meta.dirname, '..', '.ipfs-cid'), 'utf8')).trim();
        } catch {
            console.error('Usage: node scripts/generate-metadata.mjs <ipfs-cid>');
            console.error('Or run upload-ipfs.mjs first to create .ipfs-cid');
            process.exit(1);
        }
    }

    const baseImageURI = `ipfs://${ipfsCid}`;
    const outDir = resolve(import.meta.dirname, '..', 'public', 'nft');
    await mkdir(outDir, { recursive: true });

    console.log(`Generating ${MAX_SUPPLY} metadata files...`);
    console.log(`Image base: ${baseImageURI}/`);

    // Generate metadata for each token
    // In production, read actual traits from contract via RPC.
    // This generates placeholder metadata using deterministic traits.
    for (let tokenId = 0; tokenId < MAX_SUPPLY; tokenId++) {
        // Deterministic pseudo-random based on tokenId (matches contract logic)
        const classIdx = tokenId % CLASSES.length;
        const className = CLASSES[classIdx];
        const bodies = BODIES[className];
        const items = ITEMS[className];

        const bodyIdx = tokenId % bodies.length;
        const faceIdx = tokenId % FACES.length;
        const itemIdx = tokenId % items.length;
        const tierIdx = tokenId < 466 ? 0 : tokenId < 660 ? 1 : tokenId < 738 ? 2 : 3;

        const bodyFile = bodies[bodyIdx];
        const faceFile = FACES[faceIdx];
        const itemFile = items[itemIdx];

        const metadata = {
            name: `MiFren #${tokenId}`,
            description: `Magic Internet Fren #${tokenId} - ${className} Class, ${TIERS[tierIdx]} Tier. A unique pixel-art character from the Magic Internet Frens collection on Bitcoin.`,
            image: `${baseImageURI}/${bodyFile}`,
            external_url: 'https://magicfrens.xyz',
            attributes: [
                { trait_type: 'Class', value: className },
                { trait_type: 'Tier', value: TIERS[tierIdx] },
                { trait_type: 'Body', value: bodyFile.replace('.svg', '') },
                { trait_type: 'Face', value: faceFile.replace('.svg', '') },
                { trait_type: 'Item', value: itemFile.replace('.svg', '') },
            ],
            properties: {
                layers: {
                    face: `${baseImageURI}/${faceFile}`,
                    body: `${baseImageURI}/${bodyFile}`,
                    item: `${baseImageURI}/${itemFile}`,
                },
                class_color: CLASS_COLORS[classIdx],
            },
        };

        await writeFile(
            resolve(outDir, `${tokenId}.json`),
            JSON.stringify(metadata, null, 2),
        );
    }

    console.log(`\nGenerated ${MAX_SUPPLY} metadata files in ${outDir}/`);
    console.log(`\nNext steps:`);
    console.log(`  1. Upload public/nft/ to IPFS (same Pinata process)`);
    console.log(`  2. Call setBaseURI("ipfs://<metadata-cid>/") on the NFT contract`);
    console.log(`  3. tokenURI(0) will resolve to ipfs://<metadata-cid>/0.json`);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
