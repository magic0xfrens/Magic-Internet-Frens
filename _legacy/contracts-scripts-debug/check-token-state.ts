#!/usr/bin/env tsx

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
    const rpc = new JSONRpcProvider({ url: 'https://testnet.opnet.org', network: networks.opnetTestnet });

    const nftBech32 = 'opt1sqqpdjn5gts3zyr8a0hurh5mw9fku8ra2cs50n396';
    const forgeBech32 = 'opt1sqzu77u73wwl9sghujv3lz52ztry0wcassgs04zjc';

    const nftAddr = await rpc.getPublicKeyInfo(nftBech32, true);
    const forgeAddr = await rpc.getPublicKeyInfo(forgeBech32, true);
    if (nftAddr == null || forgeAddr == null) throw new Error('Could not resolve addresses');

    const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpc, networks.opnetTestnet);
    const forge = getContract<IContract>(forgeAddr, FrenForgeAbi, rpc, networks.opnetTestnet);

    // 1. totalMinted
    console.log('=== totalMinted ===');
    const minted = await view(nft, 'totalMinted')();
    const count = Number(minted.properties?.count ?? 0);
    console.log('  count:', count);

    // 2. Try getTokenTraits for IDs 0..3
    console.log('\n=== getTokenTraits ===');
    for (let id = 0; id < 4; id++) {
        try {
            const t = await view(nft, 'getTokenTraits')(BigInt(id));
            if (t.revert) {
                console.log(`  token ${id}: REVERT: ${t.revert}`);
            } else {
                const p = t.properties ?? {};
                console.log(`  token ${id}: class=${p.classIdx} body=${p.bodyIdx} face=${p.faceIdx} item=${p.itemIdx}`);
            }
        } catch (e: any) {
            console.log(`  token ${id}: ERROR: ${e.message.slice(0, 100)}`);
        }
    }

    // 3. Inscription stats
    console.log('\n=== Inscription Stats ===');
    try {
        const stats = await view(forge, 'getInscriptionStats')();
        if (stats.revert) {
            console.log(`  REVERT: ${stats.revert}`);
        } else {
            console.log(`  totalInscribed: ${stats.properties?.totalInscribed}`);
            console.log(`  paletteInscribed: ${stats.properties?.paletteInscribed}`);
        }
    } catch (e: any) {
        console.log(`  ERROR: ${e.message.slice(0, 100)}`);
    }

    // 4. FrenForge.tokenURI(0)
    console.log('\n=== FrenForge.tokenURI(0) ===');
    try {
        const t = await view(forge, 'tokenURI')(0n);
        if (t.revert) {
            console.log(`  REVERT: ${t.revert}`);
        } else {
            const uri = (t.properties?.uri ?? '').toString();
            console.log(`  SUCCESS! URI length: ${uri.length}`);
            if (uri.startsWith('data:application/json;base64,')) {
                const json = Buffer.from(uri.replace('data:application/json;base64,', ''), 'base64').toString('utf-8');
                try {
                    const parsed = JSON.parse(json);
                    console.log(`  name: ${parsed.name}`);
                    console.log(`  description: ${parsed.description?.slice(0, 80)}`);
                    console.log(`  image length: ${parsed.image?.length ?? 0}`);
                    console.log(`  attributes: ${JSON.stringify(parsed.attributes)}`);
                } catch {
                    console.log(`  raw JSON (first 500): ${json.slice(0, 500)}`);
                }
            } else {
                console.log(`  URI (first 300): ${uri.slice(0, 300)}`);
            }
        }
    } catch (e: any) {
        console.log(`  ERROR: ${e.message.slice(0, 150)}`);
    }

    // 5. MiFrens.tokenURI(0)
    console.log('\n=== MiFrens.tokenURI(0) ===');
    try {
        const t = await view(nft, 'tokenURI')(0n);
        if (t.revert) {
            console.log(`  REVERT: ${t.revert}`);
        } else {
            const uri = (t.properties?.uri ?? '').toString();
            console.log(`  SUCCESS! URI length: ${uri.length}`);
            if (uri.startsWith('data:application/json;base64,')) {
                const json = Buffer.from(uri.replace('data:application/json;base64,', ''), 'base64').toString('utf-8');
                try {
                    const parsed = JSON.parse(json);
                    console.log(`  name: ${parsed.name}`);
                    console.log(`  description: ${parsed.description?.slice(0, 80)}`);
                    console.log(`  image length: ${parsed.image?.length ?? 0}`);
                } catch {
                    console.log(`  raw JSON (first 500): ${json.slice(0, 500)}`);
                }
            }
        }
    } catch (e: any) {
        console.log(`  ERROR: ${e.message.slice(0, 150)}`);
    }

    // 6. Check FrenForge config
    console.log('\n=== FrenForge Config ===');
    try {
        const auth = await view(forge, 'getArtAuthority')();
        console.log(`  artAuthority: ${auth.properties?.authority ?? auth.decoded?.[0] ?? 'unknown'}`);
    } catch (e: any) {
        console.log(`  artAuthority ERROR: ${e.message.slice(0, 80)}`);
    }

    await rpc.close();
}

main().catch((err) => {
    console.error('Check failed:', err);
    process.exit(1);
});
