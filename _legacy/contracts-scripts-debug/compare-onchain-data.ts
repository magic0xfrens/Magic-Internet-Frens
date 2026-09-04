#!/usr/bin/env tsx
/**
 * compare-onchain-data.ts — Fetch on-chain trait data from FrenForge and compare
 * with local compressed-traits blobs to detect data corruption.
 */

import * as fs from 'fs';
import { join } from 'path';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';

type ViewCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    properties?: Record<string, unknown>;
}>;

function view(contract: IContract, name: string): ViewCall {
    return (contract as unknown as Record<string, ViewCall>)[name];
}

function hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
    }
    return bytes;
}

async function main(): Promise<void> {
    const deployment = JSON.parse(
        fs.readFileSync(join(__dirname, '../deployments/testnet.json'), 'utf-8'),
    );
    const rpc = new JSONRpcProvider({
        url: 'https://testnet.opnet.org',
        network: networks.opnetTestnet,
    });
    const forgeAddr = await rpc.getPublicKeyInfo(deployment.contracts.FRENFORGE, true);
    if (!forgeAddr) {
        console.error('Could not resolve FrenForge');
        process.exit(1);
    }
    const { FrenForgeAbi } = await import('../abis/FrenForge.abi');
    const forge = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpc,
        networks.opnetTestnet,
    );

    // Load local trait blobs
    const traitsPath = join(__dirname, '../../compressed-traits/compressed-traits.ts');
    const traitsSource = fs.readFileSync(traitsPath, 'utf-8');
    const localTraits = new Map<number, { blob: string; label: string }>();
    const traitRegex = /traitKey:\s*(\d+),\s*blob:\s*'([0-9a-fA-F]+)',\s*label:\s*'([^']+)'/g;
    let m: RegExpExecArray | null;
    while ((m = traitRegex.exec(traitsSource)) !== null) {
        localTraits.set(parseInt(m[1]), { blob: m[2], label: m[3] });
    }
    console.log(`Loaded ${localTraits.size} local trait blobs\n`);

    // Trait keys for failing combos:
    // King(class=1): body=2 → key=258, face=9 → key=65545, item=1 → key=131329, item=0 → key=131328
    // King(class=1): body=2 → key=258, face=3 → key=65539
    // Peasant(class=4): body=1 → key=1025, face=10 → key=65546, item=0 → key=132096
    // Elf(class=6): body=0 → key=1536, face=0 → key=67072, item=0 → key=132608
    const traitKeysToCheck = [
        258, 65545, 131329, 131328, // King body=2, face=9, item=1, item=0
        65539, // King face=3
        1025, 65546, 132096, // Peasant body=1, face=10, item=0
        1536, 67072, 132608, // Elf body=0, face=0, item=0
        259, 65543, // King body=3, face=7 (passing combo)
    ];

    console.log('═══════════════════════════════════════════════════════════════════');
    console.log('  On-Chain vs Local Trait Data Comparison');
    console.log('═══════════════════════════════════════════════════════════════════\n');

    // First, fetch on-chain palette
    try {
        const palRes = await view(forge, 'getGlobalPalette')();
        if (palRes.revert) {
            console.log(`  Palette: REVERT ${palRes.revert}\n`);
        } else {
            const palData = palRes.properties?.data;
            let palBytes: Uint8Array | null = null;
            if (palData instanceof Uint8Array) {
                palBytes = palData;
            } else if (Buffer.isBuffer(palData)) {
                palBytes = new Uint8Array(palData);
            } else if (typeof palData === 'string') {
                // Might be hex
                palBytes = hexToBytes(palData.replace(/^0x/, ''));
            }
            if (palBytes) {
                const localPalette = fs.readFileSync(join(__dirname, '../../compressed-traits/palette-rgb.bin'));
                console.log(`  On-chain palette: ${palBytes.length} bytes`);
                console.log(`  Local palette:    ${localPalette.length} bytes`);
                if (palBytes.length === localPalette.length) {
                    let diff = 0;
                    for (let i = 0; i < palBytes.length; i++) {
                        if (palBytes[i] !== localPalette[i]) diff++;
                    }
                    console.log(`  Palette match:    ${diff === 0 ? 'IDENTICAL' : `${diff} bytes differ`}\n`);
                } else {
                    console.log(`  Palette match:    SIZE MISMATCH\n`);
                }
            } else {
                console.log(`  Palette: Could not decode (type=${typeof palData})\n`);
            }
        }
    } catch (e: any) {
        console.log(`  Palette: ERROR ${e.message?.slice(0, 100)}\n`);
    }

    // Compare each trait
    for (const key of traitKeysToCheck) {
        const local = localTraits.get(key);
        const label = local?.label ?? `key=${key}`;
        process.stdout.write(`  Trait ${String(key).padEnd(8)} (${label.padEnd(25)}): `);

        try {
            const res = await view(forge, 'getTraitImage')(BigInt(key));
            if (res.revert) {
                console.log(`REVERT: ${res.revert}`);
                continue;
            }

            let onChainData: Uint8Array | null = null;
            const rawData = res.properties?.data;
            if (rawData instanceof Uint8Array) {
                onChainData = rawData;
            } else if (Buffer.isBuffer(rawData)) {
                onChainData = new Uint8Array(rawData);
            } else if (typeof rawData === 'string') {
                onChainData = hexToBytes(rawData.replace(/^0x/, ''));
            }

            if (!onChainData) {
                console.log(`Could not decode (type=${typeof rawData})`);
                continue;
            }

            if (!local) {
                console.log(`on-chain=${onChainData.length}B, NO local blob`);
                continue;
            }

            const localBytes = hexToBytes(local.blob);
            const sizeMatch = onChainData.length === localBytes.length;

            if (!sizeMatch) {
                console.log(`SIZE MISMATCH! on-chain=${onChainData.length}B vs local=${localBytes.length}B`);
                // Show first differing byte
                const minLen = Math.min(onChainData.length, localBytes.length);
                for (let i = 0; i < minLen; i++) {
                    if (onChainData[i] !== localBytes[i]) {
                        console.log(`    First diff at byte ${i}: on-chain=0x${onChainData[i].toString(16).padStart(2, '0')} vs local=0x${localBytes[i].toString(16).padStart(2, '0')}`);
                        break;
                    }
                }
                continue;
            }

            let diffCount = 0;
            let firstDiff = -1;
            for (let i = 0; i < onChainData.length; i++) {
                if (onChainData[i] !== localBytes[i]) {
                    diffCount++;
                    if (firstDiff === -1) firstDiff = i;
                }
            }

            if (diffCount === 0) {
                console.log(`IDENTICAL (${onChainData.length}B)`);
            } else {
                console.log(`${diffCount} BYTES DIFFER! (${onChainData.length}B, first diff at byte ${firstDiff})`);
                // Show header comparison
                console.log(`    On-chain header: ${Array.from(onChainData.slice(0, 8)).map(b => b.toString(16).padStart(2, '0')).join(' ')}`);
                console.log(`    Local header:    ${Array.from(localBytes.slice(0, 8)).map(b => b.toString(16).padStart(2, '0')).join(' ')}`);
                if (firstDiff >= 0) {
                    const start = Math.max(0, firstDiff - 2);
                    const end = Math.min(onChainData.length, firstDiff + 5);
                    console.log(`    On-chain [${start}..${end}]: ${Array.from(onChainData.slice(start, end)).map(b => b.toString(16).padStart(2, '0')).join(' ')}`);
                    console.log(`    Local    [${start}..${end}]: ${Array.from(localBytes.slice(start, end)).map(b => b.toString(16).padStart(2, '0')).join(' ')}`);
                }
            }
        } catch (e: any) {
            console.log(`ERROR: ${e.message?.slice(0, 120)}`);
        }
    }

    console.log('\n═══════════════════════════════════════════════════════════════════\n');

    await rpc.close();
}

main().catch((err) => {
    console.error('Failed:', err);
    process.exit(1);
});
