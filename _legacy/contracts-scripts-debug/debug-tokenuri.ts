#!/usr/bin/env tsx

/**
 * debug-tokenuri.ts — Diagnose why tokenURI(1) reverts.
 */

import * as fs from 'fs';
import { join } from 'path';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';

import { MiFrensAbi } from '../abis/MiFrens.abi';
import { FrenForgeAbi } from '../abis/FrenForge.abi';

const NETWORKS: Record<string, { rpcUrl: string; network: typeof networks.regtest }> = {
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet },
};

type ViewCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    properties?: Record<string, unknown>;
}>;

function view(contract: IContract, name: string): ViewCall {
    return (contract as unknown as Record<string, ViewCall>)[name];
}

async function main(): Promise<void> {
    const netConfig = NETWORKS.testnet;
    const deployment = JSON.parse(
        fs.readFileSync(join(__dirname, '../deployments/testnet.json'), 'utf-8'),
    );

    const rpc = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });
    const nftAddr = await rpc.getPublicKeyInfo(deployment.contracts.MIFRENS, true);
    const forgeAddr = await rpc.getPublicKeyInfo(deployment.contracts.FRENFORGE, true);
    if (!nftAddr || !forgeAddr) throw new Error('Could not resolve addresses');

    const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpc, netConfig.network);
    const forge = getContract<IContract>(forgeAddr, FrenForgeAbi, rpc, netConfig.network);

    console.log('=== Token #1 Traits ===');
    const traits = await view(nft, 'getTokenTraits')(1n);
    const classIdx = Number(traits.properties?.classIdx ?? 0);
    const bodyIdx = Number(traits.properties?.bodyIdx ?? 0);
    const faceIdx = Number(traits.properties?.faceIdx ?? 0);
    const itemIdx = Number(traits.properties?.itemIdx ?? 0);
    const tier = Number(traits.properties?.tier ?? 0);
    console.log(`  class=${classIdx} body=${bodyIdx} face=${faceIdx} item=${itemIdx} tier=${tier}`);

    // Compute trait keys (same as FrenForge.tokenURI)
    const bodyKey = classIdx * 256 + bodyIdx;
    const faceClassIdx = (classIdx === 5) ? 5 : (classIdx === 6) ? 6 : 0;
    const faceKey = 65536 + faceClassIdx * 256 + faceIdx;
    const itemKey = 131072 + classIdx * 256 + itemIdx;
    console.log(`  bodyKey=${bodyKey} faceKey=${faceKey} itemKey=${itemKey}`);

    console.log('\n=== Trait Inscription Status ===');
    for (const [name, key] of [['body', bodyKey], ['face', faceKey], ['item', itemKey]] as const) {
        try {
            const res = await view(forge, 'isTraitInscribed')(BigInt(key));
            const inscribed = res.properties?.inscribed;
            console.log(`  ${name} (key=${key}): ${res.revert ? 'REVERT: ' + res.revert : inscribed}`);
        } catch (e: any) {
            console.log(`  ${name} (key=${key}): ERROR: ${e.message}`);
        }
    }

    console.log('\n=== Palette Status ===');
    try {
        const stats = await view(forge, 'getInscriptionStats')();
        console.log(`  totalInscribed=${stats.properties?.totalInscribed}`);
        console.log(`  paletteInscribed=${stats.properties?.paletteInscribed}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    console.log('\n=== FrenForge.tokenURI(1) directly ===');
    try {
        const res = await view(forge, 'tokenURI')(1n);
        if (res.revert) {
            console.log(`  REVERT: ${res.revert}`);
        } else {
            const uri = res.properties?.uri?.toString() ?? '';
            console.log(`  SUCCESS! URI length: ${uri.length}`);
            if (uri.startsWith('data:application/json;base64,')) {
                const json = Buffer.from(uri.replace('data:application/json;base64,', ''), 'base64').toString('utf-8');
                try {
                    const parsed = JSON.parse(json);
                    console.log(`  name: ${parsed.name}`);
                    console.log(`  description: ${parsed.description}`);
                    console.log(`  image length: ${parsed.image?.length ?? 0}`);
                } catch {
                    console.log(`  raw JSON: ${json.slice(0, 300)}`);
                }
            } else {
                console.log(`  URI: ${uri.slice(0, 200)}`);
            }
        }
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    console.log('\n=== MiFrens.tokenURI(1) via NFT contract ===');
    try {
        const res = await view(nft, 'tokenURI')(1n);
        if (res.revert) {
            console.log(`  REVERT: ${res.revert}`);
        } else {
            const uri = res.properties?.uri?.toString() ?? '';
            console.log(`  SUCCESS! URI length: ${uri.length}`);
        }
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    await rpc.close();
}

main().catch((err) => {
    console.error('Debug failed:', err);
    process.exit(1);
});
