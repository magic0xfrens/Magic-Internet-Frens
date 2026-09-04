#!/usr/bin/env tsx

/**
 * batch-inscribe-all.ts — Inscribe palette + all 83 traits in ONE transaction.
 *
 * Packs all data into a single blob using the FrenForge.batchInscribeAll() format:
 *   [paletteLen: u16 BE] [paletteData] [traitCount: u16 BE]
 *   For each trait: [traitKey: u32 BE] [dataLen: u16 BE] [data]
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/batch-inscribe-all.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/batch-inscribe-all.ts --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/batch-inscribe-all.ts --dry-run
 */

import * as fs from 'fs';
import { join } from 'path';

import {
    Mnemonic,
    AddressTypes,
    MLDSASecurityLevel,
    Address,
} from '@btc-vision/transaction';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract, TransactionParameters } from 'opnet';

import { FrenForgeAbi } from '../abis/FrenForge.abi';

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'https://regtest.opnet.org', network: networks.regtest },
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet },
    mainnet: { rpcUrl: 'https://mainnet.opnet.org', network: networks.bitcoin },
};

function getArg(flag: string): string | undefined {
    const idx = process.argv.indexOf(flag);
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : undefined;
}

function hasFlag(flag: string): boolean {
    return process.argv.includes(flag);
}

interface ManifestTrait {
    traitKey: number;
    binaryFile: string;
    label: string;
    compressedBytes: number;
}

interface Manifest {
    globalPalette: {
        file: string;
        bytes: number;
    };
    traits: ManifestTrait[];
    totals: {
        traitCount: number;
        compressedBytes: number;
        paletteBytes: number;
    };
}

type ContractCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    properties?: Record<string, unknown>;
    sendTransaction: (params: TransactionParameters) => Promise<{
        transactionId: string;
    }>;
}>;

function method(contract: IContract, name: string): ContractCall {
    return (contract as unknown as Record<string, ContractCall>)[name];
}

async function resolveContractAddress(
    provider: JSONRpcProvider,
    contractAddr: string,
): Promise<Address> {
    const addr = await provider.getPublicKeyInfo(contractAddr, true);
    if (!addr) {
        throw new Error(
            `Could not resolve public key for ${contractAddr}. ` +
            `Is the contract confirmed on-chain?`,
        );
    }
    return addr;
}

async function main(): Promise<void> {
    const networkName = getArg('--network') ?? 'regtest';
    const dryRun = hasFlag('--dry-run');

    const netConfig = NETWORKS[networkName];
    if (!netConfig) {
        console.error(`Unknown network "${networkName}". Available: ${Object.keys(NETWORKS).join(', ')}`);
        process.exit(1);
    }

    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (!mnemonicPhrase) {
        console.error('DEPLOYER_MNEMONIC environment variable is required');
        process.exit(1);
    }

    // Load deployment
    const deploymentPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment found at ${deploymentPath}`);
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const forgeAddress: string = deployment.contracts.FRENFORGE;

    // Load manifest
    const traitsDir = join(__dirname, '../../compressed-traits');
    const manifestPath = join(traitsDir, 'manifest.json');
    const manifest: Manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — Batch Inscribe ALL (One Transaction)');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:       ${networkName}`);
    console.log(`  FrenForge:     ${forgeAddress}`);
    console.log(`  Palette:       ${manifest.globalPalette.bytes} bytes`);
    console.log(`  Traits:        ${manifest.totals.traitCount}`);
    console.log(`  Trait data:    ${manifest.totals.compressedBytes} bytes`);
    console.log(`  Dry run:       ${dryRun}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // Read all trait binaries (manifest includes both regular traits and color batches)
    const traits: Array<{ traitKey: number; data: Uint8Array; label: string }> = [];
    let totalTraitBytes = 0;

    for (const trait of manifest.traits) {
        const traitPath = join(traitsDir, trait.binaryFile);
        const traitData = new Uint8Array(fs.readFileSync(traitPath));
        traits.push({ traitKey: trait.traitKey, data: traitData, label: trait.label });
        totalTraitBytes += traitData.length;
    }

    console.log(`Loaded ${traits.length} entries (${totalTraitBytes} bytes total)\n`);

    // Packed blob format: [count: u16 BE] per-trait: [traitKey: u32 BE] [dataLen: u16 BE] [data]
    let packedSize = 2; // count
    for (const t of traits) {
        packedSize += 4 + 2 + t.data.length;
    }

    console.log(`Packed blob size: ${packedSize} bytes (${(packedSize / 1024).toFixed(1)} KB)`);

    if (packedSize > 380_000) {
        console.error(`WARNING: Packed blob (${packedSize} bytes) may exceed witness limits (~400KB).`);
        console.error('Consider splitting into multiple transactions.');
    }

    // Build packed blob
    const packed = new Uint8Array(packedSize);
    const view = new DataView(packed.buffer);
    let off = 0;

    // Trait count (u16 BE)
    view.setUint16(off, traits.length, false);
    off += 2;

    // Per-trait entries
    for (const t of traits) {
        // traitKey (u32 BE)
        view.setUint32(off, t.traitKey, false);
        off += 4;

        // dataLen (u16 BE)
        view.setUint16(off, t.data.length, false);
        off += 2;

        // data
        packed.set(t.data, off);
        off += t.data.length;
    }

    console.log(`Packed blob built: ${off} bytes written\n`);

    if (dryRun) {
        console.log('DRY RUN — would send batchInscribeAll with:');
        console.log(`  Entries: ${traits.length}`);
        console.log(`  Total packed: ${off} bytes`);
        console.log('\nTrait list:');
        for (const t of traits) {
            console.log(`  traitKey=${t.traitKey} label="${t.label}" bytes=${t.data.length}`);
        }
        return;
    }

    // Setup wallet
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer: ${wallet.p2tr}\n`);

    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    const txParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 1_000_000n,
        feeRate: 5,
        network: netConfig.network,
    };

    // Resolve FrenForge
    console.log('Resolving FrenForge...');
    const forgeAddr = await resolveContractAddress(rpcProvider, forgeAddress);
    console.log('  Resolved\n');

    const forgeContract = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // Check current state
    console.log('Checking current inscription status...');
    const statsResult = await method(forgeContract, 'getInscriptionStats')();
    const totalBefore = Number(statsResult.properties?.totalInscribed ?? statsResult.decoded?.[0] ?? 0);
    const paletteBefore = Number(statsResult.properties?.paletteInscribed ?? statsResult.decoded?.[1] ?? 0);
    console.log(`  Traits inscribed: ${totalBefore}`);
    console.log(`  Palette inscribed: ${paletteBefore}\n`);

    // Call batchInscribeAll
    console.log('Calling batchInscribeAll...');
    console.log(`  Sending ${off} bytes of packed data...\n`);

    const sim = await method(forgeContract, 'batchInscribeAll')(packed);

    if (sim.revert) {
        console.error(`REVERT: ${sim.revert}`);
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
        process.exit(1);
    }

    const inscribedCount = Number(sim.properties?.count ?? sim.decoded?.[0] ?? 0);
    console.log(`Simulation success! ${inscribedCount} traits would be inscribed.`);

    console.log('Sending transaction...');
    const receipt = await sim.sendTransaction(txParams);
    console.log(`  TX: ${receipt.transactionId}\n`);

    // Verify
    console.log('Verifying inscription stats...');
    const statsAfter = await method(forgeContract, 'getInscriptionStats')();
    const totalAfter = Number(statsAfter.properties?.totalInscribed ?? statsAfter.decoded?.[0] ?? 0);
    const paletteAfter = Number(statsAfter.properties?.paletteInscribed ?? statsAfter.decoded?.[1] ?? 0);

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Batch Inscription Complete');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Traits inscribed: ${totalBefore} → ${totalAfter}`);
    console.log(`  Palette inscribed: ${paletteBefore} → ${paletteAfter}`);
    console.log(`  Transaction: ${receipt.transactionId}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    if (totalAfter >= traits.length && paletteAfter === 1) {
        console.log('All traits and palette inscribed successfully in ONE transaction!');
    } else {
        console.log(`Expected ${traits.length} traits inscribed, got ${totalAfter}.`);
        console.log('Some traits may have already been inscribed.');
    }

    // Cleanup
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err: unknown) => {
    console.error('Batch inscription failed:', err);
    process.exit(1);
});
