#!/usr/bin/env tsx
/**
 * Validate CRC32 checksums in the on-chain tokenURI PNG.
 * Extracts the base64 PNG from MiFrens.tokenURI(368) and checks every chunk CRC.
 */

import * as fs from 'fs';
import * as zlib from 'zlib';
import { join } from 'path';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';
import { MiFrensAbi } from '../abis/MiFrens.abi';

type ViewCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    properties?: Record<string, unknown>;
}>;

function view(contract: IContract, name: string): ViewCall {
    return (contract as unknown as Record<string, ViewCall>)[name];
}

function readBE32(buf: Buffer, off: number): number {
    return ((buf[off] << 24) | (buf[off + 1] << 16) | (buf[off + 2] << 8) | buf[off + 3]) >>> 0;
}

function crc32(buf: Buffer): number {
    return zlib.crc32(buf) >>> 0;
}

async function main(): Promise<void> {
    const deploymentPath = join(__dirname, '../deployments/testnet.json');
    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const nftAddress: string = deployment.contracts.MIFRENS;

    const rpc = new JSONRpcProvider({ url: 'https://testnet.opnet.org', network: networks.opnetTestnet });
    const nftAddr = await rpc.getPublicKeyInfo(nftAddress, true);
    if (!nftAddr) { console.error('Could not resolve MiFrens'); process.exit(1); }
    const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpc, networks.opnetTestnet);

    const TOKEN_ID = BigInt(process.argv[2] ?? '1');
    console.log(`Fetching MiFrens.tokenURI(${TOKEN_ID})...\n`);

    const res = await view(nft, 'tokenURI')(TOKEN_ID);
    if (res.revert) { console.error('REVERT:', res.revert); process.exit(1); }

    const uri = res.properties?.uri?.toString() ?? res.decoded?.[0]?.toString() ?? '';
    console.log('URI length:', uri.length);

    // Decode the data URI to get JSON
    let jsonStr: string;
    if (uri.startsWith('data:application/json;base64,')) {
        jsonStr = Buffer.from(uri.slice('data:application/json;base64,'.length), 'base64').toString();
    } else if (uri.startsWith('data:application/json,')) {
        jsonStr = decodeURIComponent(uri.slice('data:application/json,'.length));
    } else {
        console.error('Unexpected URI format:', uri.slice(0, 100));
        process.exit(1);
    }

    const meta = JSON.parse(jsonStr);
    console.log('Name:', meta.name);
    console.log('Image type:', typeof meta.image === 'string' ? meta.image.slice(0, 30) : 'MISSING');

    if (!meta.image || !meta.image.startsWith('data:image/png;base64,')) {
        console.error('No base64 PNG found in image field');
        process.exit(1);
    }

    const b64 = meta.image.slice('data:image/png;base64,'.length);
    const png = Buffer.from(b64, 'base64');
    console.log('PNG bytes:', png.length);

    // Save to file for visual inspection
    const outPath = join(__dirname, '../../test-onchain-png.png');
    fs.writeFileSync(outPath, png);
    console.log(`Saved to ${outPath}\n`);

    // Validate PNG signature
    const expected = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    console.log('PNG signature:', png.slice(0, 8).equals(expected) ? 'VALID' : 'INVALID');

    // Parse chunks and validate CRC32
    let off = 8;
    let allOk = true;
    while (off < png.length) {
        const dataLen = readBE32(png, off);
        const typeStr = png.slice(off + 4, off + 8).toString('ascii');
        const chunkData = png.slice(off + 4, off + 8 + dataLen); // type + data
        const storedCrc = readBE32(png, off + 8 + dataLen);
        const computed = crc32(chunkData);
        const match = computed === storedCrc;

        if (!match) allOk = false;

        console.log(
            `${typeStr}: dataLen=${dataLen} ` +
            `computed=0x${computed.toString(16).padStart(8, '0')} ` +
            `stored=0x${storedCrc.toString(16).padStart(8, '0')} ` +
            (match ? 'OK ✓' : 'MISMATCH ✗')
        );

        off += 12 + dataLen;
    }

    // Inflate IDAT
    let idatOff = 8;
    while (idatOff < png.length) {
        const dLen = readBE32(png, idatOff);
        const t = png.slice(idatOff + 4, idatOff + 8).toString('ascii');
        if (t === 'IDAT') {
            const compressed = png.slice(idatOff + 8, idatOff + 8 + dLen);
            try {
                const inflated = zlib.inflateSync(compressed);
                console.log(`\nIDAT inflate: OK (${inflated.length} bytes)`);
            } catch (e: any) {
                console.log(`\nIDAT inflate: FAILED — ${e.message}`);
            }
            break;
        }
        idatOff += 12 + dLen;
    }

    console.log(`\n${allOk ? 'ALL CRCs VALID — PNG should render!' : 'CRC MISMATCHES — PNG will be rejected by browsers'}`);

    await rpc.close();
}

main().catch((err) => { console.error('Failed:', err); process.exit(1); });
