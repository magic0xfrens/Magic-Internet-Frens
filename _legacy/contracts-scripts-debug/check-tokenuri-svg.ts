#!/usr/bin/env tsx

import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';
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
    const forgeBech32 = 'opt1sqzu77u73wwl9sghujv3lz52ztry0wcassgs04zjc';
    const forgeAddr = await rpc.getPublicKeyInfo(forgeBech32, true);
    if (!forgeAddr) throw new Error('Could not resolve FrenForge');

    const forge = getContract<IContract>(forgeAddr, FrenForgeAbi, rpc, networks.opnetTestnet);

    // Check inscription stats
    console.log('=== Inscription Stats ===');
    const stats = await view(forge, 'getInscriptionStats')();
    console.log(`  totalInscribed: ${stats.properties?.totalInscribed ?? stats.decoded?.[0]}`);
    console.log(`  paletteInscribed: ${stats.properties?.paletteInscribed ?? stats.decoded?.[1]}`);

    // Get tokenURI for token 1
    console.log('\n=== tokenURI(1) via FrenForge ===');
    const t = await view(forge, 'tokenURI')(1n);
    if (t.revert) {
        console.log(`REVERT: ${t.revert}`);
    } else {
        const uri = (t.properties?.uri ?? '').toString();
        console.log(`URI length: ${uri.length}`);

        if (uri.startsWith('data:application/json;base64,')) {
            const json = Buffer.from(uri.replace('data:application/json;base64,', ''), 'base64').toString('utf-8');
            const parsed = JSON.parse(json);
            console.log(`\nJSON metadata:`);
            console.log(`  name: ${parsed.name}`);
            console.log(`  description: ${parsed.description}`);
            console.log(`  attributes: ${JSON.stringify(parsed.attributes)}`);

            const img: string = parsed.image ?? '';
            console.log(`\n  image URI prefix: ${img.substring(0, 40)}...`);
            console.log(`  image URI length: ${img.length}`);

            if (img.startsWith('data:image/svg+xml;base64,')) {
                const svg = Buffer.from(img.replace('data:image/svg+xml;base64,', ''), 'base64').toString('utf-8');
                console.log(`\n  SVG length: ${svg.length}`);
                console.log(`  SVG first 800 chars:\n${svg.slice(0, 800)}`);

                // Count <rect> elements to see if there are actual pixels
                const rectCount = (svg.match(/<rect /g) || []).length;
                console.log(`\n  Total <rect> elements (pixels): ${rectCount}`);

                if (rectCount <= 2) {
                    console.log('\n  *** SVG IS ESSENTIALLY EMPTY ***');
                    console.log('  Only background gradient rects — no pixel art rendered.');
                    console.log('  This is because required traits are not inscribed on-chain.');
                    console.log('  Run: DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/inscribe-traits.ts --network testnet');
                } else {
                    console.log('\n  SVG has pixel content — rendering should work.');
                }
            } else if (img.length === 0) {
                console.log('\n  *** IMAGE FIELD IS EMPTY ***');
            } else {
                console.log(`\n  Image is not inline SVG. First 100 chars: ${img.slice(0, 100)}`);
            }
        } else {
            console.log(`URI prefix: ${uri.slice(0, 100)}`);
        }
    }

    // Also check MiFrens.tokenURI(1) — what the wallet actually calls
    console.log('\n=== MiFrens.tokenURI(1) — what OP_WALLET calls ===');
    const nftBech32 = 'opt1sqqpdjn5gts3zyr8a0hurh5mw9fku8ra2cs50n396';
    const nftAddr = await rpc.getPublicKeyInfo(nftBech32, true);
    if (nftAddr) {
        const { MiFrensAbi } = await import('../abis/MiFrens.abi');
        const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpc, networks.opnetTestnet);
        const nftRes = await view(nft, 'tokenURI')(1n);
        if (nftRes.revert) {
            console.log(`  REVERT: ${nftRes.revert}`);
        } else {
            const nftUri = (nftRes.properties?.uri ?? '').toString();
            console.log(`  URI length: ${nftUri.length}`);
            if (nftUri.startsWith('data:application/json;base64,')) {
                const nftJson = Buffer.from(nftUri.replace('data:application/json;base64,', ''), 'base64').toString('utf-8');
                const nftParsed = JSON.parse(nftJson);
                console.log(`  name: ${nftParsed.name}`);
                const nftImg: string = nftParsed.image ?? '';
                console.log(`  image length: ${nftImg.length}`);
                if (nftImg.startsWith('data:image/svg+xml;base64,')) {
                    const nftSvg = Buffer.from(nftImg.replace('data:image/svg+xml;base64,', ''), 'base64').toString('utf-8');
                    const nftRects = (nftSvg.match(/<rect /g) || []).length;
                    console.log(`  SVG <rect> count: ${nftRects}`);
                    if (nftRects <= 2) {
                        console.log('  *** EMPTY SVG — traits not inscribed ***');
                    }
                }
            } else if (nftUri.length > 0) {
                console.log(`  URI: ${nftUri.slice(0, 200)}`);
            } else {
                console.log('  URI is empty');
            }
        }
    }

    await rpc.close();
}

main().catch((err) => { console.error(err); process.exit(1); });
