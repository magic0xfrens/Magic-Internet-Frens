#!/usr/bin/env node
/**
 * Upload MiFrens SVG collection to IPFS via Pinata.
 *
 * Usage:
 *   1. Get a free API key at https://pinata.cloud
 *   2. Set env vars:
 *        export PINATA_JWT="your_jwt_token"
 *   3. Run:
 *        node scripts/upload-ipfs.mjs
 *
 * The script uploads every SVG in public/frens/ as a single IPFS directory.
 * Output: the root CID you can use as the baseURI for the NFT contract.
 */

import { readdir, readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const FRENS_DIR = resolve(import.meta.dirname, '..', 'public', 'frens');
const PINATA_API = 'https://api.pinata.cloud';

const JWT = process.env.PINATA_JWT;
if (!JWT) {
    console.error('Missing PINATA_JWT env var. Get one free at https://pinata.cloud');
    process.exit(1);
}

async function uploadDirectory() {
    const files = (await readdir(FRENS_DIR)).filter((f) => f.endsWith('.svg'));
    console.log(`Found ${files.length} SVG files in ${FRENS_DIR}`);

    // Build multipart form with all SVGs
    const form = new FormData();

    for (const fileName of files) {
        const filePath = join(FRENS_DIR, fileName);
        const content = await readFile(filePath);
        const blob = new Blob([content], { type: 'image/svg+xml' });
        // Pinata directory upload: file field name is 'file', path in pinataMetadata
        form.append('file', blob, `mifrens-svg/${fileName}`);
    }

    // Pinata options: wrap in directory, set name
    const pinataMetadata = JSON.stringify({ name: 'mifrens-svg-collection' });
    form.append('pinataMetadata', pinataMetadata);

    const pinataOptions = JSON.stringify({ wrapWithDirectory: false });
    form.append('pinataOptions', pinataOptions);

    console.log('Uploading to Pinata...');

    const res = await fetch(`${PINATA_API}/pinning/pinFileToIPFS`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${JWT}` },
        body: form,
    });

    if (!res.ok) {
        const text = await res.text();
        console.error(`Pinata upload failed (${res.status}): ${text}`);
        process.exit(1);
    }

    const data = await res.json();
    const cid = data.IpfsHash;

    console.log('\n=== UPLOAD COMPLETE ===');
    console.log(`CID:      ${cid}`);
    console.log(`Gateway:  https://gateway.pinata.cloud/ipfs/${cid}/`);
    console.log(`IPFS:     ipfs://${cid}/`);
    console.log(`\nExample file: https://gateway.pinata.cloud/ipfs/${cid}/wizard-01.svg`);
    console.log(`\nUse this as your NFT baseURI:`);
    console.log(`  ipfs://${cid}/`);
    console.log(`\nTo update the contract's baseURI, call setBaseURI with the new CID.`);

    // Write CID to file for reference
    const { writeFile } = await import('node:fs/promises');
    await writeFile(
        resolve(import.meta.dirname, '..', '.ipfs-cid'),
        `${cid}\n`,
    );
    console.log(`\nCID saved to .ipfs-cid`);
}

uploadDirectory().catch((err) => {
    console.error('Upload failed:', err);
    process.exit(1);
});
