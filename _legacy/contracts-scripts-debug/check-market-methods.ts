#!/usr/bin/env tsx

/**
 * Quick check: does the deployed FrenMarket have reserve methods?
 */

import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';

// Use the frontend ABI which has the reserve methods defined
import { FrenMarketAbi } from '../../src/constants/nftAbi';

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
    const marketAddress = 'opt1sqrmudvd53gzsz8xn3wvmqsl0pquaw2q5asn75y4a';

    console.log(`Checking FrenMarket: ${marketAddress}\n`);

    const addr = await rpc.getPublicKeyInfo(marketAddress, true);
    if (addr === null || addr === undefined) {
        console.log('Could not resolve address');
        process.exit(1);
    }

    const market = getContract<IContract>(addr, FrenMarketAbi, rpc, networks.opnetTestnet);

    // Test each method
    const tests: Array<{ name: string; args: unknown[] }> = [
        { name: 'getActiveListingCount', args: [] },
        { name: 'getListing', args: [1n] },
        { name: 'reserveBuy', args: [1n] },
        { name: 'claimReserved', args: [1n] },
        { name: 'cancelReservation', args: [1n] },
    ];

    for (const test of tests) {
        try {
            const fn = view(market, test.name);
            if (typeof fn !== 'function') {
                console.log(`${test.name}: NOT IN ABI`);
                continue;
            }

            const res = await fn(...test.args);
            if (res.revert) {
                // Method exists but reverted (expected for dummy args)
                console.log(`${test.name}: EXISTS (revert: ${res.revert.slice(0, 80)})`);
            } else {
                const decoded = res.decoded ?? [];
                const props = res.properties ?? {};
                console.log(`${test.name}: EXISTS (decoded=${decoded.length} fields, props=${JSON.stringify(props)})`);
            }
        } catch (e: unknown) {
            const msg = e instanceof Error ? e.message : String(e);
            if (msg.includes('Method not found')) {
                console.log(`${test.name}: *** NOT FOUND IN CONTRACT ***`);
            } else {
                console.log(`${test.name}: ERROR - ${msg.slice(0, 120)}`);
            }
        }
    }

    await rpc.close();
}

main().catch((err) => {
    console.error('Check failed:', err);
    process.exit(1);
});
