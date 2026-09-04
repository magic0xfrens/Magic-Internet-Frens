#!/usr/bin/env tsx

/**
 * debug-opwallet.ts — Check what OPWallet sees when it tries to display the NFT.
 * Tests: metadata(), tokenURI(1), balanceOf(deployer), totalSupply(), ownerOf(1)
 */

import * as fs from 'fs';
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

function stringify(val: unknown): string {
    if (val === undefined) return 'undefined';
    if (val === null) return 'null';
    if (typeof val === 'bigint') return val.toString();
    if (typeof val === 'object') {
        return JSON.stringify(val, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2);
    }
    return String(val);
}

async function main(): Promise<void> {
    const deployment = JSON.parse(
        fs.readFileSync(join(__dirname, '../deployments/testnet.json'), 'utf-8'),
    );

    const rpc = new JSONRpcProvider({
        url: 'https://testnet.opnet.org',
        network: networks.opnetTestnet,
    });

    const nftBech32 = deployment.contracts.MIFRENS;
    const deployerBech32 = deployment.deployer;

    console.log(`NFT contract: ${nftBech32}`);
    console.log(`Deployer:     ${deployerBech32}`);

    const nftAddr = await rpc.getPublicKeyInfo(nftBech32, true);
    const deployerAddr = await rpc.getPublicKeyInfo(deployerBech32, true);

    if (!nftAddr) throw new Error('Could not resolve NFT address');
    if (!deployerAddr) throw new Error('Could not resolve deployer address');

    const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpc, networks.opnetTestnet);

    // 1. metadata()
    console.log('\n=== metadata() ===');
    try {
        const res = await view(nft, 'metadata')();
        console.log(`  revert: ${res.revert ?? 'none'}`);
        console.log(`  properties: ${stringify(res.properties)}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // 2. totalSupply()
    console.log('\n=== totalSupply() ===');
    try {
        const res = await view(nft, 'totalSupply')();
        console.log(`  revert: ${res.revert ?? 'none'}`);
        console.log(`  properties: ${stringify(res.properties)}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // 3. balanceOf(deployer)
    console.log('\n=== balanceOf(deployer) ===');
    try {
        const res = await view(nft, 'balanceOf')(deployerAddr);
        console.log(`  revert: ${res.revert ?? 'none'}`);
        console.log(`  properties: ${stringify(res.properties)}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // 4. ownerOf(1)
    console.log('\n=== ownerOf(1) ===');
    try {
        const res = await view(nft, 'ownerOf')(1n);
        console.log(`  revert: ${res.revert ?? 'none'}`);
        console.log(`  properties: ${stringify(res.properties)}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // 5. tokenURI(1)
    console.log('\n=== tokenURI(1) ===');
    try {
        const res = await view(nft, 'tokenURI')(1n);
        console.log(`  revert: ${res.revert ?? 'none'}`);
        if (res.properties?.uri) {
            const uri = String(res.properties.uri);
            console.log(`  uri length: ${uri.length}`);
            console.log(`  uri starts with: ${uri.substring(0, 80)}`);
            if (uri.startsWith('data:application/json')) {
                try {
                    const json = uri.startsWith('data:application/json;base64,')
                        ? Buffer.from(uri.replace('data:application/json;base64,', ''), 'base64').toString()
                        : uri.replace('data:application/json,', '');
                    const meta = JSON.parse(json);
                    console.log(`  parsed metadata:`);
                    console.log(`    name: ${meta.name}`);
                    console.log(`    description: ${meta.description}`);
                    console.log(`    image starts: ${String(meta.image).substring(0, 60)}`);
                } catch (parseErr: any) {
                    console.log(`  JSON parse failed: ${parseErr.message}`);
                }
            }
        }
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // 6. tokenOfOwnerByIndex(deployer, 0)
    console.log('\n=== tokenOfOwnerByIndex(deployer, 0) ===');
    try {
        const res = await view(nft, 'tokenOfOwnerByIndex')(deployerAddr, 0n);
        console.log(`  revert: ${res.revert ?? 'none'}`);
        console.log(`  properties: ${stringify(res.properties)}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // 7. getTokenTraits(1)
    console.log('\n=== getTokenTraits(1) ===');
    try {
        const res = await view(nft, 'getTokenTraits')(1n);
        console.log(`  revert: ${res.revert ?? 'none'}`);
        console.log(`  properties: ${stringify(res.properties)}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    await rpc.close();
}

main().catch((err) => {
    console.error('Debug failed:', err);
    process.exit(1);
});
