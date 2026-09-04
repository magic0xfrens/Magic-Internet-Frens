#!/usr/bin/env tsx

/**
 * Quick test: call FrenForge.renderTokenURI DIRECTLY (not via MiFrens)
 * to isolate whether the ReentrancyGuard issue is cross-contract or internal.
 */

import * as fs from 'fs';
import { join } from 'path';
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
    const deploymentPath = join(__dirname, '../deployments/testnet.json');
    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const forgeAddress: string = deployment.contracts.FRENFORGE;

    const rpc = new JSONRpcProvider({ url: 'https://testnet.opnet.org', network: networks.opnetTestnet });

    console.log(`FrenForge: ${forgeAddress}`);
    const forgeAddr = await rpc.getPublicKeyInfo(forgeAddress, true);
    if (!forgeAddr) {
        console.error('Could not resolve FrenForge');
        process.exit(1);
    }

    const forge = getContract<IContract>(forgeAddr, FrenForgeAbi, rpc, networks.opnetTestnet);

    // Test 1: Call renderTokenURI directly on FrenForge
    // Token #7 traits: class=5(Gnome), body=0, face=0, item=0, subitem=0
    console.log('\n--- Test 1: FrenForge.renderTokenURI(7, 5, 0, 0, 0, 0) ---');
    try {
        const res = await view(forge, 'renderTokenURI')(7n, 5n, 0n, 0n, 0n, 0n);
        if (res.revert) {
            console.log('REVERT:', res.revert);
        } else {
            const uri = res.properties?.uri?.toString() ?? res.decoded?.[0]?.toString() ?? '';
            console.log('SUCCESS! URI length:', uri.length);
            console.log('URI preview:', uri.slice(0, 300));
        }
    } catch (e: any) {
        console.log('ERROR:', e.message);
    }

    // Test 2: Call getBaseURI on FrenForge
    console.log('\n--- Test 2: FrenForge.getBaseURI() ---');
    try {
        const res = await view(forge, 'getBaseURI')();
        if (res.revert) {
            console.log('REVERT:', res.revert);
        } else {
            console.log('baseURI:', res.properties?.uri?.toString() ?? res.decoded?.[0]?.toString());
        }
    } catch (e: any) {
        console.log('ERROR:', e.message);
    }

    // Test 3: Call getInscriptionStats
    console.log('\n--- Test 3: FrenForge.getInscriptionStats() ---');
    try {
        const res = await view(forge, 'getInscriptionStats')();
        if (res.revert) {
            console.log('REVERT:', res.revert);
        } else {
            console.log('totalInscribed:', res.properties?.totalInscribed?.toString() ?? res.decoded?.[0]);
        }
    } catch (e: any) {
        console.log('ERROR:', e.message);
    }

    // Test 4: Call tokenURI on FrenForge directly (uses _buildTokenURI which DOES callback)
    console.log('\n--- Test 4: FrenForge.tokenURI(7) [has callback — should fail] ---');
    try {
        const res = await view(forge, 'tokenURI')(7n);
        if (res.revert) {
            console.log('REVERT:', res.revert);
        } else {
            const uri = res.properties?.uri?.toString() ?? res.decoded?.[0]?.toString() ?? '';
            console.log('SUCCESS! URI:', uri.slice(0, 300));
        }
    } catch (e: any) {
        console.log('ERROR:', e.message);
    }

    await rpc.close();
}

main().catch((err) => {
    console.error('Test failed:', err);
    process.exit(1);
});
