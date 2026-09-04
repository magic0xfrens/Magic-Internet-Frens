#!/usr/bin/env tsx
/**
 * test-exact-combos.ts — Test exact failing trait combos with different tokenIds
 * to isolate whether the OOB error is trait-specific or tokenId-specific.
 */

import * as fs from 'fs';
import { join } from 'path';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';

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
    const forgeAddr = await rpc.getPublicKeyInfo(deployment.contracts.FRENFORGE, true);
    if (!forgeAddr) {
        console.error('Could not resolve FrenForge');
        process.exit(1);
    }
    const { FrenForgeAbi } = await import('../abis/FrenForge.abi');
    const forge = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpc,
        networks.opnetTestnet,
    );

    // renderTokenURI(tokenId, classIdx, bodyIdx, faceIdx, itemIdx, subitemIdx)
    //
    // PHASE 1: Isolate which trait layer causes King(b:2) to fail
    // King class=1, body=2, face=9, item=1 FAILS
    // King class=1, body=3, face=7, item=1 WORKS (from isolation test)
    // Strategy: swap one trait at a time from working→failing
    const tests: { label: string; args: bigint[] }[] = [
        // Working King baseline (from check-nft-state)
        { label: 'King WORKING     c1 b3 f7 i1', args: [1n, 1n, 3n, 7n, 1n, 0n] },

        // Swap body: 3→2 (keep face=7, item=1)
        { label: 'King swap body   c1 b2 f7 i1', args: [1n, 1n, 2n, 7n, 1n, 0n] },
        // Swap face: 7→9 (keep body=3, item=1)
        { label: 'King swap face   c1 b3 f9 i1', args: [1n, 1n, 3n, 9n, 1n, 0n] },
        // Swap item: 1→0 (keep body=3, face=7)
        { label: 'King swap item   c1 b3 f7 i0', args: [1n, 1n, 3n, 7n, 0n, 0n] },

        // Double swaps
        { label: 'King b2+f9       c1 b2 f9 i1', args: [1n, 1n, 2n, 9n, 1n, 0n] },
        { label: 'King b2+i0       c1 b2 f7 i0', args: [1n, 1n, 2n, 7n, 0n, 0n] },
        { label: 'King f9+i0       c1 b3 f9 i0', args: [1n, 1n, 3n, 9n, 0n, 0n] },

        // The full failing combo
        { label: 'King FAILING     c1 b2 f9 i1', args: [1n, 1n, 2n, 9n, 1n, 0n] },
        // Same but item=0
        { label: 'King b2 f9 i0    c1 b2 f9 i0', args: [1n, 1n, 2n, 9n, 0n, 0n] },
        // Token #45: King b2 f3 i0
        { label: 'King FAILING#45  c1 b2 f3 i0', args: [1n, 1n, 2n, 3n, 0n, 0n] },
        // King b2 f3 i1 (item swap from #45)
        { label: 'King b2 f3 i1    c1 b2 f3 i1', args: [1n, 1n, 2n, 3n, 1n, 0n] },

        // PHASE 2: Test all King bodies with fixed face/item
        { label: 'King body=0      c1 b0 f0 i0', args: [1n, 1n, 0n, 0n, 0n, 0n] },
        { label: 'King body=1      c1 b1 f0 i0', args: [1n, 1n, 1n, 0n, 0n, 0n] },
        { label: 'King body=2      c1 b2 f0 i0', args: [1n, 1n, 2n, 0n, 0n, 0n] },
        { label: 'King body=3      c1 b3 f0 i0', args: [1n, 1n, 3n, 0n, 0n, 0n] },
        { label: 'King body=4      c1 b4 f0 i0', args: [1n, 1n, 4n, 0n, 0n, 0n] },

        // PHASE 3: Test Peasant with different faces
        { label: 'Peas b1 f0       c4 b1 f0 i0', args: [1n, 4n, 1n, 0n, 0n, 0n] },
        { label: 'Peas b1 f5       c4 b1 f5 i0', args: [1n, 4n, 1n, 5n, 0n, 0n] },
        { label: 'Peas b1 f10 FAIL c4 b1 f10 i0', args: [1n, 4n, 1n, 10n, 0n, 0n] },
        { label: 'Peas b0 f10      c4 b0 f10 i0', args: [1n, 4n, 0n, 10n, 0n, 0n] },

        // PHASE 4: Elf tokenId test
        { label: 'Elf b0 f0 tid=1  ', args: [1n, 6n, 0n, 0n, 0n, 0n] },
        { label: 'Elf b0 f0 tid=320', args: [320n, 6n, 0n, 0n, 0n, 0n] },
        { label: 'Elf b0 f0 tid=784', args: [784n, 6n, 0n, 0n, 0n, 0n] },
        { label: 'Elf b0 f0 tid=785', args: [785n, 6n, 0n, 0n, 0n, 0n] },
    ];

    console.log('═══════════════════════════════════════════════════════════════════');
    console.log('  Exact Combo Isolation Test — FrenForge.renderTokenURI');
    console.log('═══════════════════════════════════════════════════════════════════\n');

    for (const t of tests) {
        try {
            const res = await view(forge, 'renderTokenURI')(...t.args);
            if (res.revert) {
                console.log(`  ${t.label}: REVERT: ${res.revert}`);
            } else {
                const uri = res.properties?.uri?.toString() ?? '';
                console.log(`  ${t.label}: OK (${uri.length} chars)`);
            }
        } catch (e: any) {
            const msg = e.message?.slice(0, 120) ?? String(e);
            console.log(`  ${t.label}: ERROR ${msg}`);
        }
    }

    console.log('\n═══════════════════════════════════════════════════════════════════\n');

    await rpc.close();
}

main().catch((err) => {
    console.error('Failed:', err);
    process.exit(1);
});
