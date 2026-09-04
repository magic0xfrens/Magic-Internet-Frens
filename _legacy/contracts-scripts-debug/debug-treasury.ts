#!/usr/bin/env tsx

/**
 * debug-treasury.ts — Debug treasury address format mismatch
 *
 * Reads the treasury address stored in FrenForge and compares with
 * what Address.toString() produces vs what output.to would contain.
 */

import * as fs from 'fs';
import { join } from 'path';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';
import { Address } from '@btc-vision/transaction';
import { FrenForgeAbi } from '../abis/FrenForge.abi';
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
    const rpc = new JSONRpcProvider({
        url: 'https://testnet.opnet.org',
        network: networks.opnetTestnet,
    });

    // Use the addresses the frontend actually uses (from contracts.ts)
    const forgeBech32 = 'opt1sqq9p5p5mka3a5v8ay50lptt38uytnwct7vaggfeu';
    const nftBech32 = 'opt1sqrvkgz2ge3jnj66hy659y3xwqq7cgks2t5cqnafu';
    const deployerBech32 = 'opt1punql3mkrpaea2f7fzu0rrlxvxluk2jrxfav0yvyxnjaw9ssw8l9q63hnng';

    console.log(`FrenForge:  ${forgeBech32}`);
    console.log(`NFT:        ${nftBech32}`);
    console.log(`Deployer:   ${deployerBech32}`);

    // Resolve addresses
    const forgeAddr = await rpc.getPublicKeyInfo(forgeBech32, true);
    const nftAddr = await rpc.getPublicKeyInfo(nftBech32, true);
    const deployerAddr = await rpc.getPublicKeyInfo(deployerBech32, true);

    if (!forgeAddr) throw new Error('Could not resolve FrenForge address');
    if (!nftAddr) throw new Error('Could not resolve NFT address');
    if (!deployerAddr) throw new Error('Could not resolve deployer address');

    console.log('\n=== SDK Address Info ===');
    console.log(`  deployerAddr type:     ${deployerAddr.constructor.name}`);
    console.log(`  deployerAddr.toString: ${deployerAddr.toString()}`);
    if ('p2tr' in deployerAddr) {
        console.log(`  deployerAddr.p2tr:     ${(deployerAddr as any).p2tr()}`);
    }
    if ('tweakedPublicKey' in deployerAddr) {
        const tpk = (deployerAddr as any).tweakedPublicKey;
        console.log(`  tweakedPublicKey hex:  ${Buffer.from(tpk).toString('hex')}`);
    }
    // Raw bytes
    console.log(`  deployerAddr bytes:    ${Buffer.from(deployerAddr).toString('hex')}`);

    // Read FrenForge treasury via getArtAuthority (we don't have a getTreasury but let's check)
    const forge = getContract<IContract>(forgeAddr, FrenForgeAbi, rpc, networks.opnetTestnet);
    const nft = getContract<IContract>(nftAddr, MiFrensAbi, rpc, networks.opnetTestnet);

    // Try reading NFT treasury
    console.log('\n=== NFT.getTreasury() ===');
    try {
        const res = await view(nft, 'getTreasury')();
        console.log(`  revert: ${res.revert ?? 'none'}`);
        if (res.properties) {
            for (const [k, v] of Object.entries(res.properties)) {
                const val = v instanceof Address ? `Address(${v.toString()})` : String(v);
                console.log(`  ${k}: ${val}`);
            }
        }
        if (res.decoded) {
            for (let i = 0; i < res.decoded.length; i++) {
                const v = res.decoded[i];
                const val = v instanceof Address ? `Address(${v.toString()})` : String(v);
                console.log(`  decoded[${i}]: ${val}`);
            }
        }
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    // Try reading NFT mintPrice
    console.log('\n=== NFT.getMintPrice() ===');
    try {
        const res = await view(nft, 'getMintPrice')();
        console.log(`  revert: ${res.revert ?? 'none'}`);
        console.log(`  properties: ${JSON.stringify(res.properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);
    } catch (e: any) {
        console.log(`  ERROR: ${e.message}`);
    }

    console.log('\n=== Comparison ===');
    console.log(`  Frontend sends to:     "${deployerBech32}"`);
    console.log(`  Address.toString():    "${deployerAddr.toString()}"`);
    console.log(`  Match?                 ${deployerBech32 === deployerAddr.toString()}`);

    await rpc.close();
}

main().catch((err) => {
    console.error('Debug failed:', err);
    process.exit(1);
});
