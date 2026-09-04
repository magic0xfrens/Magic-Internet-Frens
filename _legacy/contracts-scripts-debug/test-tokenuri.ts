#!/usr/bin/env tsx

import * as fs from 'fs';
import { join } from 'path';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';
import { MiFrensAbi } from '../abis/MiFrens.abi';
import { FrenForgeAbi } from '../abis/FrenForge.abi';

type ViewCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    properties?: Record<string, unknown>;
}>;

function view(contract: IContract, name: string): ViewCall {
    return (contract as unknown as Record<string, ViewCall>)[name];
}

async function main(): Promise<void> {
    const deploymentPath = join(__dirname, '../deployments/testnet.json');
    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const nftAddress: string = deployment.contracts.MIFRENS;
    const forgeAddress: string = deployment.contracts.FRENFORGE;

    const rpc = new JSONRpcProvider({ url: 'https://testnet.opnet.org', network: networks.opnetTestnet });

    // Resolve MiFrens
    console.log(`MiFrens: ${nftAddress}`);
    const nftAddr = await rpc.getPublicKeyInfo(nftAddress, true);
    if (!nftAddr) { console.error('Could not resolve MiFrens'); process.exit(1); }
    const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpc, networks.opnetTestnet);

    // Resolve FrenForge
    console.log(`FrenForge: ${forgeAddress}`);
    const forgeAddr = await rpc.getPublicKeyInfo(forgeAddress, true);
    if (!forgeAddr) { console.error('Could not resolve FrenForge'); process.exit(1); }
    const forge = getContract<IContract>(forgeAddr, FrenForgeAbi, rpc, networks.opnetTestnet);

    const TOKEN_ID = 368n;

    // Test 1: MiFrens.getTokenTraits(368)
    console.log(`\n--- Test 1: MiFrens.getTokenTraits(${TOKEN_ID}) ---`);
    try {
        const res = await view(nft, 'getTokenTraits')(TOKEN_ID);
        if (res.revert) {
            console.log('REVERT:', res.revert);
        } else {
            console.log('classIdx:', res.properties?.classIdx?.toString());
            console.log('bodyIdx:', res.properties?.bodyIdx?.toString());
            console.log('faceIdx:', res.properties?.faceIdx?.toString());
            console.log('itemIdx:', res.properties?.itemIdx?.toString());
            console.log('subitemIdx:', res.properties?.subitemIdx?.toString());
        }
    } catch (e: any) { console.log('ERROR:', e.message); }

    // Test 2: MiFrens.tokenURI(368) — cross-contract to FrenForge
    console.log(`\n--- Test 2: MiFrens.tokenURI(${TOKEN_ID}) ---`);
    try {
        const res = await view(nft, 'tokenURI')(TOKEN_ID);
        if (res.revert) {
            console.log('REVERT:', res.revert);
        } else {
            const uri = res.properties?.uri?.toString() ?? res.decoded?.[0]?.toString() ?? '';
            console.log('URI length:', uri.length);
            console.log('URI prefix:', uri.slice(0, 120));
            if (uri.startsWith('data:application/json;base64,')) {
                const json = Buffer.from(uri.slice('data:application/json;base64,'.length), 'base64').toString();
                const meta = JSON.parse(json);
                console.log('  name:', meta.name);
                console.log('  image prefix:', typeof meta.image === 'string' ? meta.image.slice(0, 80) : 'NONE');
                console.log('  image length:', meta.image?.length ?? 0);
                if (meta.attributes) console.log('  attributes:', JSON.stringify(meta.attributes));
            } else if (uri.startsWith('data:application/json,')) {
                const json = decodeURIComponent(uri.slice('data:application/json,'.length));
                console.log('Decoded JSON:', json.slice(0, 500));
            } else {
                console.log('Raw URI (not data:):', uri.slice(0, 300));
            }
        }
    } catch (e: any) { console.log('ERROR:', e.message); }

    // Test 3: FrenForge.renderTokenURI for token 368 traits (King classIdx=1)
    console.log(`\n--- Test 3: FrenForge.renderTokenURI(${TOKEN_ID}, 1, 3, 1, 1, 0) ---`);
    try {
        const res = await view(forge, 'renderTokenURI')(TOKEN_ID, 1n, 3n, 1n, 1n, 0n);
        if (res.revert) {
            console.log('REVERT:', res.revert);
        } else {
            const uri = res.properties?.uri?.toString() ?? res.decoded?.[0]?.toString() ?? '';
            console.log('URI length:', uri.length);
            console.log('URI prefix:', uri.slice(0, 120));
        }
    } catch (e: any) { console.log('ERROR:', e.message); }

    // Test 4: FrenForge.getInscriptionStats
    console.log('\n--- Test 4: FrenForge.getInscriptionStats() ---');
    try {
        const res = await view(forge, 'getInscriptionStats')();
        if (res.revert) { console.log('REVERT:', res.revert); }
        else { console.log('totalInscribed:', res.properties?.totalInscribed?.toString() ?? res.decoded?.[0]); }
    } catch (e: any) { console.log('ERROR:', e.message); }

    await rpc.close();
}

main().catch((err) => { console.error('Failed:', err); process.exit(1); });
