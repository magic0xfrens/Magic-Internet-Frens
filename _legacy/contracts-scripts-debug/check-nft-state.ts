#!/usr/bin/env tsx

/**
 * check-nft-state.ts — Query deployed MiFrens + FrenForge state on testnet.
 * Read-only — no wallet/mnemonic needed.
 */

import * as fs from 'fs';
import { join } from 'path';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';

import { MiFrensAbi } from '../abis/MiFrens.abi';
import { FrenForgeAbi } from '../abis/FrenForge.abi';

// ---------------------------------------------------------------------------

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'https://regtest.opnet.org', network: networks.regtest },
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet },
    mainnet: { rpcUrl: 'https://mainnet.opnet.org', network: networks.bitcoin },
};

function getNetworkName(): string {
    const idx = process.argv.indexOf('--network');
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : 'regtest';
}

type ViewCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    properties?: Record<string, unknown>;
}>;

function view(contract: IContract, name: string): ViewCall {
    return (contract as unknown as Record<string, ViewCall>)[name];
}

// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const networkName = getNetworkName();
    const netConfig = NETWORKS[networkName];
    if (!netConfig) {
        console.error(`Unknown network. Available: ${Object.keys(NETWORKS).join(', ')}`);
        process.exit(1);
    }

    const deploymentPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment at ${deploymentPath}`);
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const nftAddress: string = deployment.contracts.MIFRENS;
    const forgeAddress: string = deployment.contracts.FRENFORGE;

    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    console.log('Resolving contract addresses...');
    const nftAddr = await rpcProvider.getPublicKeyInfo(nftAddress, true);
    const forgeAddr = await rpcProvider.getPublicKeyInfo(forgeAddress, true);

    if (!nftAddr || !forgeAddr) {
        console.error('Could not resolve contract addresses');
        process.exit(1);
    }

    const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpcProvider, netConfig.network);
    const forge = getContract<IContract>(forgeAddr, FrenForgeAbi, rpcProvider, netConfig.network);

    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  MiFrens On-Chain State');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:    ${networkName}`);
    console.log(`  NFT:        ${nftAddress}`);
    console.log(`  FrenForge:  ${forgeAddress}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- totalMinted ---
    try {
        const res = await view(nft, 'totalMinted')();
        console.log('totalMinted:', res.revert ? `REVERT: ${res.revert}` : res.properties?.count?.toString() ?? res.decoded);
    } catch (e: any) {
        console.log('totalMinted: ERROR', e.message);
    }

    // --- getMintPrice ---
    try {
        const res = await view(nft, 'getMintPrice')();
        console.log('getMintPrice:', res.revert ? `REVERT: ${res.revert}` : res.properties?.price?.toString() ?? res.decoded);
    } catch (e: any) {
        console.log('getMintPrice: ERROR', e.message);
    }

    // --- getTreasury ---
    try {
        const res = await view(nft, 'getTreasury')();
        console.log('getTreasury:', res.revert ? `REVERT: ${res.revert}` : res.properties?.treasury?.toString() ?? res.decoded);
    } catch (e: any) {
        console.log('getTreasury: ERROR', e.message);
    }

    // --- getFrenForge ---
    try {
        const res = await view(nft, 'getFrenForge')();
        console.log('getFrenForge:', res.revert ? `REVERT: ${res.revert}` : res.properties?.forge?.toString() ?? res.decoded);
    } catch (e: any) {
        console.log('getFrenForge: ERROR', e.message);
    }

    // --- FrenForge: getInscriptionStats ---
    try {
        const res = await view(forge, 'getInscriptionStats')();
        if (res.revert) {
            console.log('getInscriptionStats: REVERT:', res.revert);
        } else {
            console.log('getInscriptionStats:', {
                totalInscribed: res.properties?.totalInscribed?.toString(),
                paletteInscribed: res.properties?.paletteInscribed?.toString(),
            });
        }
    } catch (e: any) {
        console.log('getInscriptionStats: ERROR', e.message);
    }

    // --- Trait Data Debug ---
    if (process.argv.includes('--debug-traits')) {
        console.log('\n--- Trait Data Debug ---');

        // Check palette
        try {
            const palRes = await view(forge, 'getGlobalPalette')();
            if (palRes.revert) {
                console.log('  palette: REVERT:', palRes.revert);
            } else {
                const palData = palRes.properties?.data as Uint8Array;
                console.log(`  palette: ${palData?.length ?? 0} bytes (${(palData?.length ?? 0) / 3} colors)`);
            }
        } catch (e: any) {
            console.log('  palette: ERROR', e.message?.slice(0, 100));
        }

        // Compare working vs failing trait keys
        const testKeys = [
            { key: 515n, label: 'Knight body=3 (works)' },
            { key: 0n, label: 'Wizard body=0 (fails)' },
            { key: 3n, label: 'Wizard body=3 (works from token#28)' },
            { key: 1n, label: 'Wizard body=1 (fails from token#2)' },
            { key: 65544n, label: 'Face idx=8 (works)' },
            { key: 65547n, label: 'Face idx=11 (fails)' },
            { key: 131584n, label: 'Knight item=0 (works)' },
            { key: 131072n, label: 'Wizard item=0 (fails)' },
        ];
        for (const { key, label } of testKeys) {
            try {
                const res = await view(forge, 'getTraitImage')(key);
                if (res.revert) {
                    console.log(`  traitKey ${key} (${label}): REVERT: ${res.revert}`);
                } else {
                    const data = res.properties?.data as Uint8Array;
                    if (!data || data.length === 0) {
                        console.log(`  traitKey ${key} (${label}): EMPTY`);
                    } else {
                        const header = Array.from(data.slice(0, 10)).map(b => b.toString(16).padStart(2, '0')).join(' ');
                        console.log(`  traitKey ${key} (${label}): ${data.length} bytes, header=[${header}]`);
                    }
                }
            } catch (e: any) {
                console.log(`  traitKey ${key} (${label}): ERROR ${e.message?.slice(0, 80)}`);
            }
        }
    }

    // --- Render Isolation Test ---
    if (process.argv.includes('--isolate')) {
        console.log('\n--- Render Isolation Tests ---');
        // Token #28 WORKS: class=0, body=3, face=4, item=1
        // Token #18 FAILS: class=0, body=0, face=1, item=0
        // Test different combos to isolate which trait breaks it
        const combos: [string, bigint[]][] = [
            ['WORKING BASELINE (c0 b3 f4 i1)',  [1n, 0n, 3n, 4n, 1n, 0n]],
            ['FAILING BASELINE (c0 b0 f1 i0)',  [1n, 0n, 0n, 1n, 0n, 0n]],
            ['body=0 only  (c0 b0 f4 i1)',      [1n, 0n, 0n, 4n, 1n, 0n]],
            ['face=1 only  (c0 b3 f1 i1)',      [1n, 0n, 3n, 1n, 1n, 0n]],
            ['item=0 only  (c0 b3 f4 i0)',      [1n, 0n, 3n, 4n, 0n, 0n]],
            ['Knight (c2 b3 f8 i0)',            [1n, 2n, 3n, 8n, 0n, 0n]],
            ['King (c1 b3 f7 i1)',              [1n, 1n, 3n, 7n, 1n, 0n]],
            ['Elf (c6 b1 f3 i0)',               [1n, 6n, 1n, 3n, 0n, 0n]],
            ['Peasant (c4 b1 f2 i0)',           [1n, 4n, 1n, 2n, 0n, 0n]],
            ['Gnome (c5 b1 f3 i0)',             [1n, 5n, 1n, 3n, 0n, 0n]],
            ['Apprentice (c3 b1 f3 i0)',        [1n, 3n, 1n, 3n, 0n, 0n]],
        ];
        for (const [label, args] of combos) {
            try {
                const res = await view(forge, 'renderTokenURI')(...args);
                if (res.revert) {
                    console.log(`  ${label}: REVERT: ${res.revert}`);
                } else {
                    const uri = res.properties?.uri?.toString() ?? '';
                    console.log(`  ${label}: OK (${uri.length} chars)`);
                }
            } catch (e: any) {
                const msg = e.message?.slice(0, 80) ?? '';
                console.log(`  ${label}: ERROR ${msg}`);
            }
        }
    }

    // --- Check tokens ---
    const checkIds: bigint[] = [];
    const idArg = process.argv.indexOf('--token');
    const rangeArg = process.argv.indexOf('--range');
    if (idArg !== -1 && process.argv[idArg + 1]) {
        checkIds.push(BigInt(process.argv[idArg + 1]));
    } else if (rangeArg !== -1 && process.argv[rangeArg + 1]) {
        const [s, e] = process.argv[rangeArg + 1].split('-').map(Number);
        for (let i = BigInt(s); i <= BigInt(e); i++) checkIds.push(i);
    } else {
        for (let i = 1n; i <= 20n; i++) checkIds.push(i);
    }
    console.log(`\n--- Token Checks (${checkIds.map(String).join(', ')}) ---`);
    const summary: { ok: number[]; fail: number[] } = { ok: [], fail: [] };
    for (const id of checkIds) {
        console.log(`\n  Token #${id}:`);

        // getTokenTraits
        try {
            const res = await view(nft, 'getTokenTraits')(id);
            if (res.revert) {
                console.log(`    traits: REVERT: ${res.revert}`);
            } else {
                console.log(`    traits: class=${res.properties?.classIdx?.toString()} body=${res.properties?.bodyIdx?.toString()} face=${res.properties?.faceIdx?.toString()} item=${res.properties?.itemIdx?.toString()}`);
            }
        } catch (e: any) {
            console.log(`    traits: ERROR ${e.message}`);
        }

        // Also try direct FrenForge.renderTokenURI to isolate cross-contract issues
        let traits: Record<string, any> = {};
        try {
            const tRes = await view(nft, 'getTokenTraits')(id);
            if (!tRes.revert && tRes.properties) {
                traits = tRes.properties;
                const classIdx = BigInt(traits.classIdx as string | bigint);
                const bodyIdx = BigInt(traits.bodyIdx as string | bigint);
                const faceIdx = BigInt(traits.faceIdx as string | bigint);
                const itemIdx = BigInt(traits.itemIdx as string | bigint);
                const subitemIdx = BigInt(traits.subitemIdx as string | bigint ?? 0);

                try {
                    const fRes = await view(forge, 'renderTokenURI')(id, classIdx, bodyIdx, faceIdx, itemIdx, subitemIdx);
                    if (fRes.revert) {
                        console.log(`    forge.renderTokenURI: REVERT: ${fRes.revert}`);
                    } else {
                        const fUri = fRes.properties?.uri?.toString() ?? '';
                        console.log(`    forge.renderTokenURI: OK (${fUri.length} chars)`);
                    }
                } catch (e: any) {
                    console.log(`    forge.renderTokenURI: ERROR ${e.message?.slice(0, 100)}`);
                }
            }
        } catch { /* already logged above */ }

        // tokenURI (via MiFrens cross-contract)
        try {
            const res = await view(nft, 'tokenURI')(id);
            if (res.revert) {
                console.log(`    tokenURI: REVERT: ${res.revert}`);
            } else {
                const uri = res.properties?.uri?.toString() ?? res.decoded?.[0]?.toString() ?? '';
                if (uri.startsWith('data:application/json;base64,')) {
                    const json = Buffer.from(uri.replace('data:application/json;base64,', ''), 'base64').toString('utf-8');
                    console.log(`    tokenURI: data URI (base64, decoded JSON):`);
                    try {
                        const parsed = JSON.parse(json);
                        console.log(`      name: ${parsed.name}`);
                        console.log(`      description: ${parsed.description}`);
                        console.log(`      image: ${parsed.image?.slice(0, 100)}...`);
                        console.log(`      attributes: ${JSON.stringify(parsed.attributes)}`);
                    } catch {
                        console.log(`      raw: ${json.slice(0, 300)}`);
                    }
                } else if (uri.startsWith('data:application/json,')) {
                    const encoded = uri.replace('data:application/json,', '');
                    const json = decodeURIComponent(encoded);
                    console.log(`    tokenURI: data URI (url-encoded, decoded JSON):`);
                    try {
                        const parsed = JSON.parse(json);
                        console.log(`      name: ${parsed.name}`);
                        console.log(`      description: ${parsed.description}`);
                        const img = parsed.image ?? '';
                        console.log(`      image: ${img.slice(0, 80)}... (${img.length} chars)`);
                        if (parsed.attributes) console.log(`      attributes: ${JSON.stringify(parsed.attributes)}`);
                    } catch {
                        console.log(`      raw: ${json.slice(0, 300)}`);
                    }
                } else {
                    console.log(`    tokenURI: ${uri.length > 200 ? uri.slice(0, 200) + '...' : uri}`);
                }
                summary.ok.push(Number(id));
            }
        } catch (e: any) {
            console.log(`    tokenURI: ERROR ${e.message?.slice(0, 100)}`);
            summary.fail.push(Number(id));
        }
    }

    console.log('\n--- Summary ---');
    console.log(`  tokenURI OK: [${summary.ok.join(', ')}] (${summary.ok.length})`);
    console.log(`  tokenURI FAIL: [${summary.fail.join(', ')}] (${summary.fail.length})`);
    console.log('\n═══════════════════════════════════════════════════════════\n');

    await rpcProvider.close();
}

main().catch((err) => {
    console.error('Check failed:', err);
    process.exit(1);
});
