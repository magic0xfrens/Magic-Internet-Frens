#!/usr/bin/env tsx

/**
 * check-wallet-compat.ts — Tests all standard OP721 methods that OP_WALLET
 * uses when importing an NFT collection.
 */

import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider, OP_721_ABI } from 'opnet';
import type { IOP721Contract } from 'opnet';

async function main(): Promise<void> {
    const rpc = new JSONRpcProvider({ url: 'https://testnet.opnet.org', network: networks.opnetTestnet });

    const nftBech32 = 'opt1sqqpdjn5gts3zyr8a0hurh5mw9fku8ra2cs50n396';
    const ownerBech32 = 'opt1punql3mkrpaea2f7fzu0rrlxvxluk2jrxfav0yvyxnjaw9ssw8l9q63hnng';

    console.log('=== Resolving addresses ===');
    const nftAddr = await rpc.getPublicKeyInfo(nftBech32, true);
    if (nftAddr == null) throw new Error('Could not resolve NFT address');
    console.log('  NFT resolved');

    const ownerAddr = await rpc.getPublicKeyInfo(ownerBech32, true);
    console.log(`  Owner resolved: ${ownerAddr != null}`);

    // Use standard OP_721_ABI — same as what the wallet uses
    const nft = getContract<IOP721Contract>(nftAddr, OP_721_ABI, rpc, networks.opnetTestnet);

    // 1. name()
    console.log('\n=== name() ===');
    try {
        const res = await nft.name();
        console.log(`  ${(res as any).revert ? 'REVERT: ' + (res as any).revert : 'OK: ' + JSON.stringify((res as any).properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);
    } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }

    // 2. symbol()
    console.log('\n=== symbol() ===');
    try {
        const res = await nft.symbol();
        console.log(`  ${(res as any).revert ? 'REVERT: ' + (res as any).revert : 'OK: ' + JSON.stringify((res as any).properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);
    } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }

    // 3. totalSupply()
    console.log('\n=== totalSupply() ===');
    try {
        const res = await nft.totalSupply();
        console.log(`  ${(res as any).revert ? 'REVERT: ' + (res as any).revert : 'OK: ' + JSON.stringify((res as any).properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);
    } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }

    // 4. maxSupply()
    console.log('\n=== maxSupply() ===');
    try {
        const res = await nft.maxSupply();
        console.log(`  ${(res as any).revert ? 'REVERT: ' + (res as any).revert : 'OK: ' + JSON.stringify((res as any).properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);
    } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }

    // 5. metadata()
    console.log('\n=== metadata() ===');
    try {
        const res = await (nft as any).metadata();
        if (res.revert) {
            console.log(`  REVERT: ${res.revert}`);
        } else {
            const p = res.properties ?? {};
            for (const [k, v] of Object.entries(p)) {
                const val = typeof v === 'bigint' ? v.toString() : String(v);
                console.log(`  ${k}: ${val.slice(0, 100)}`);
            }
        }
    } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }

    // 6. ownerOf(1)
    console.log('\n=== ownerOf(1) ===');
    try {
        const res = await nft.ownerOf(1n);
        console.log(`  ${(res as any).revert ? 'REVERT: ' + (res as any).revert : 'OK: ' + JSON.stringify((res as any).properties, (_, v) => typeof v === 'bigint' ? v.toString() : String(v))}`);
    } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }

    // 7. balanceOf(owner)
    if (ownerAddr) {
        console.log('\n=== balanceOf(owner) ===');
        try {
            const res = await nft.balanceOf(ownerAddr);
            console.log(`  ${(res as any).revert ? 'REVERT: ' + (res as any).revert : 'OK: ' + JSON.stringify((res as any).properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);
        } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }

        // 8. tokenOfOwnerByIndex(owner, 0)
        console.log('\n=== tokenOfOwnerByIndex(owner, 0) ===');
        try {
            const res = await nft.tokenOfOwnerByIndex(ownerAddr, 0n);
            console.log(`  ${(res as any).revert ? 'REVERT: ' + (res as any).revert : 'OK: ' + JSON.stringify((res as any).properties, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);
        } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }
    }

    // 9. tokenURI(1)
    console.log('\n=== tokenURI(1) ===');
    try {
        const res = await nft.tokenURI(1n);
        if ((res as any).revert) {
            console.log(`  REVERT: ${(res as any).revert}`);
        } else {
            const uri = ((res as any).properties?.uri ?? '').toString();
            console.log(`  OK, URI length: ${uri.length}`);
            console.log(`  prefix: ${uri.slice(0, 80)}`);
        }
    } catch (e: any) { console.log(`  ERROR: ${e.message.slice(0, 120)}`); }

    // 10. tokenURI(0) — wallet might try this
    console.log('\n=== tokenURI(0) — should revert ===');
    try {
        const res = await nft.tokenURI(0n);
        console.log(`  ${(res as any).revert ? 'REVERT (expected): ' + (res as any).revert : 'OK (unexpected): length ' + ((res as any).properties?.uri ?? '').toString().length}`);
    } catch (e: any) { console.log(`  ERROR (expected): ${e.message.slice(0, 120)}`); }

    await rpc.close();
}

main().catch((err) => {
    console.error('Check failed:', err);
    process.exit(1);
});
