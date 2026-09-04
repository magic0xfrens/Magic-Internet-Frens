#!/usr/bin/env tsx

/**
 * debug-balance.ts — Check balanceOf and ownerOf on-chain to diagnose
 * why the frontend shows 0 frens.
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

    // Resolve addresses
    const nftAddr = await rpc.getPublicKeyInfo(nftBech32, true);
    const deployerAddr = await rpc.getPublicKeyInfo(deployerBech32, true);

    if (!nftAddr) throw new Error('Could not resolve NFT address');
    if (!deployerAddr) throw new Error('Could not resolve deployer address');

    console.log(`\nResolved deployer Address object:`);
    console.log(`  type: ${typeof deployerAddr}`);
    console.log(`  has equals: ${'equals' in deployerAddr}`);
    console.log(`  toString: ${deployerAddr.toString?.()}`);
    console.log(`  toHex: ${(deployerAddr as any).toHex?.()}`);

    const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpc, networks.opnetTestnet);

    // 1. Check totalMinted
    console.log('\n=== totalMinted ===');
    const mintedRes = await view(nft, 'totalMinted')();
    console.log(`  revert: ${mintedRes.revert ?? 'none'}`);
    console.log(`  decoded: ${JSON.stringify(mintedRes.decoded?.map(v => String(v)))}`);
    console.log(`  properties: ${JSON.stringify(mintedRes.properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);

    // 2. Check ownerOf(1)
    console.log('\n=== ownerOf(1) ===');
    try {
        const ownerRes = await view(nft, 'ownerOf')(1n);
        console.log(`  revert: ${ownerRes.revert ?? 'none'}`);
        console.log(`  decoded: ${JSON.stringify(ownerRes.decoded?.map(v => String(v)))}`);
        console.log(`  properties: ${JSON.stringify(ownerRes.properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);

        // Check if owner matches deployer
        const ownerAddr = ownerRes.properties?.owner;
        if (ownerAddr && typeof ownerAddr === 'object' && 'equals' in (ownerAddr as object)) {
            const matches = (ownerAddr as any).equals(deployerAddr);
            console.log(`  owner equals deployer: ${matches}`);
        }
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // 3. Check balanceOf(deployer)
    console.log('\n=== balanceOf(deployer) ===');
    try {
        const balRes = await view(nft, 'balanceOf')(deployerAddr);
        console.log(`  revert: ${balRes.revert ?? 'none'}`);
        console.log(`  decoded: ${JSON.stringify(balRes.decoded?.map(v => String(v)))}`);
        console.log(`  properties: ${JSON.stringify(balRes.properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // 4. Check totalSupply
    console.log('\n=== totalSupply ===');
    try {
        const supRes = await view(nft, 'totalSupply')();
        console.log(`  revert: ${supRes.revert ?? 'none'}`);
        console.log(`  decoded: ${JSON.stringify(supRes.decoded?.map(v => String(v)))}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    await rpc.close();
}

main().catch((err) => {
    console.error('Debug failed:', err);
    process.exit(1);
});
