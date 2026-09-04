#!/usr/bin/env tsx

/**
 * inscribe-traits.ts — Batch-inscribe ALL trait images on-chain
 *
 * Reads every trait from compressed-traits and calls FrenForge.inscribeTrait()
 * for each one that isn't already inscribed. Must be run by the deployer
 * (art authority).
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/inscribe-traits.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/inscribe-traits.ts --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/inscribe-traits.ts --network testnet --batch 5
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/inscribe-traits.ts --network testnet --dry-run
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
import {
    COMPRESSED_TRAITS,
    type CompressedTrait,
} from '../../compressed-traits/compressed-traits';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const MERKLE_PROOF_DEPTH = 8;

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function hexToBytes(hex: string): Uint8Array {
    const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
    const bytes = new Uint8Array(clean.length / 2);
    for (let i = 0; i < clean.length; i += 2) {
        bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
    }
    return bytes;
}

/**
 * Pack trait data into the BYTES blob expected by FrenForge.inscribeTrait().
 * Format: leafIndex(u32) + proofLen(u32) + proof[7](7×32 bytes) + dataLen(u32) + data[N]
 */
function packTraitData(trait: CompressedTrait): Uint8Array {
    const traitBlob = hexToBytes(trait.blob);
    const totalSize = 4 + 4 + 32 * MERKLE_PROOF_DEPTH + 4 + traitBlob.length;
    const buf = new Uint8Array(totalSize);
    const view = new DataView(buf.buffer);
    let offset = 0;

    // leafIndex (u32 big-endian)
    view.setUint32(offset, trait.leafIndex, false);
    offset += 4;

    // proofLen (u32 big-endian)
    view.setUint32(offset, MERKLE_PROOF_DEPTH, false);
    offset += 4;

    // proof elements (7 × 32 bytes)
    for (let i = 0; i < MERKLE_PROOF_DEPTH; i++) {
        const hash = hexToBytes(trait.proof[i]);
        buf.set(hash, offset);
        offset += 32;
    }

    // data length (u32 big-endian) + data
    view.setUint32(offset, traitBlob.length, false);
    offset += 4;
    buf.set(traitBlob, offset);

    return buf;
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

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const networkName = getArg('--network') ?? 'regtest';
    const batchSize = parseInt(getArg('--batch') ?? '10', 10);
    const dryRun = hasFlag('--dry-run');
    const startFrom = parseInt(getArg('--start') ?? '0', 10);

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

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — Batch Inscribe All Traits');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:       ${networkName}`);
    console.log(`  FrenForge:     ${forgeAddress}`);
    console.log(`  Total traits:  ${COMPRESSED_TRAITS.length}`);
    console.log(`  Batch size:    ${batchSize}`);
    console.log(`  Start from:    ${startFrom}`);
    console.log(`  Dry run:       ${dryRun}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer: ${wallet.p2tr}\n`);

    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    const txParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 500_000n,
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

    // Check current inscription stats
    console.log('Checking inscription status...');
    const statsResult = await method(forgeContract, 'getInscriptionStats')();
    const totalInscribed = Number(statsResult.properties?.totalInscribed ?? statsResult.decoded?.[0] ?? 0);
    console.log(`  Already inscribed: ${totalInscribed} / ${COMPRESSED_TRAITS.length}\n`);

    if (totalInscribed >= COMPRESSED_TRAITS.length) {
        console.log('All traits already inscribed! Nothing to do.');
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
        return;
    }

    // Find which traits still need inscription
    const traitsToInscribe: CompressedTrait[] = [];

    console.log('Checking individual trait status...');
    for (let i = startFrom; i < COMPRESSED_TRAITS.length; i++) {
        const trait = COMPRESSED_TRAITS[i];
        try {
            const result = await method(forgeContract, 'isTraitInscribed')(BigInt(trait.traitKey));
            const inscribed = result.properties?.inscribed ?? result.decoded?.[0] ?? false;
            if (!inscribed) {
                traitsToInscribe.push(trait);
                console.log(`  [${i}] traitKey=${trait.traitKey} (${trait.label}) — NEEDS INSCRIPTION`);
            } else {
                console.log(`  [${i}] traitKey=${trait.traitKey} (${trait.label}) — already inscribed`);
            }
        } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            console.log(`  [${i}] traitKey=${trait.traitKey} — check failed: ${msg.slice(0, 80)}`);
            traitsToInscribe.push(trait);
        }
    }

    console.log(`\n${traitsToInscribe.length} traits need inscription.\n`);

    if (traitsToInscribe.length === 0) {
        console.log('Nothing to inscribe!');
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
        return;
    }

    if (dryRun) {
        console.log('DRY RUN — would inscribe:');
        for (const t of traitsToInscribe) {
            const blobBytes = t.blob.length / 2;
            console.log(`  traitKey=${t.traitKey} label="${t.label}" blob=${blobBytes} bytes`);
        }
        console.log(`\nTotal data: ${traitsToInscribe.reduce((s, t) => s + t.blob.length / 2, 0)} bytes`);
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
        return;
    }

    // Inscribe in batches
    let successCount = 0;
    let failCount = 0;
    const txHashes: string[] = [];

    for (let i = 0; i < traitsToInscribe.length; i++) {
        const trait = traitsToInscribe[i];
        const blobBytes = trait.blob.length / 2;

        console.log(`\n[${i + 1}/${traitsToInscribe.length}] Inscribing traitKey=${trait.traitKey} (${trait.label}, ${blobBytes} bytes)...`);

        try {
            const packedData = packTraitData(trait);

            const sim = await method(forgeContract, 'inscribeTrait')(
                BigInt(trait.traitKey),
                packedData,
            );

            if (sim.revert) {
                console.error(`  REVERT: ${sim.revert}`);
                failCount++;
                continue;
            }

            const receipt = await sim.sendTransaction(txParams);
            console.log(`  TX: ${receipt.transactionId}`);
            txHashes.push(receipt.transactionId);
            successCount++;

            // Wait between transactions to let UTXOs settle
            if (i < traitsToInscribe.length - 1) {
                // After each batch, wait longer
                if ((i + 1) % batchSize === 0) {
                    console.log(`\n  --- Batch ${Math.floor((i + 1) / batchSize)} complete. Waiting 30s for UTXO settlement... ---\n`);
                    await sleep(30_000);
                } else {
                    // Short delay between individual inscriptions
                    await sleep(3_000);
                }
            }
        } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            console.error(`  ERROR: ${msg.slice(0, 200)}`);
            failCount++;

            // If we get a UTXO error, wait longer and retry
            if (msg.includes('UTXO') || msg.includes('insufficient') || msg.includes('not found')) {
                console.log('  Waiting 60s for UTXO availability...');
                await sleep(60_000);
                // Retry once
                try {
                    console.log('  Retrying...');
                    const packedData = packTraitData(trait);
                    const sim = await method(forgeContract, 'inscribeTrait')(
                        BigInt(trait.traitKey),
                        packedData,
                    );
                    if (sim.revert) {
                        console.error(`  REVERT on retry: ${sim.revert}`);
                    } else {
                        const receipt = await sim.sendTransaction(txParams);
                        console.log(`  Retry TX: ${receipt.transactionId}`);
                        txHashes.push(receipt.transactionId);
                        successCount++;
                        failCount--; // undo the fail count
                    }
                } catch (retryErr: unknown) {
                    const retryMsg = retryErr instanceof Error ? retryErr.message : String(retryErr);
                    console.error(`  Retry failed: ${retryMsg.slice(0, 200)}`);
                }
            }
        }
    }

    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Batch Inscription Complete');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Succeeded: ${successCount}`);
    console.log(`  Failed:    ${failCount}`);
    console.log(`  Total TXs: ${txHashes.length}`);
    console.log('═══════════════════════════════════════════════════════════');

    if (txHashes.length > 0) {
        console.log('\nTransaction hashes:');
        for (const tx of txHashes) {
            console.log(`  ${tx}`);
        }
    }

    if (failCount > 0) {
        console.log(`\n${failCount} traits failed. Re-run the script to retry them.`);
    }

    console.log('\n═══════════════════════════════════════════════════════════\n');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Batch inscription failed:', err);
    process.exit(1);
});
