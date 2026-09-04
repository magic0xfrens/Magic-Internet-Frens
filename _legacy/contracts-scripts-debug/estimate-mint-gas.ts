#!/usr/bin/env tsx

/**
 * estimate-mint-gas.ts — Simulate FrenForge.mint() on testnet to estimate gas costs.
 *
 * Runs simulation-only (NO transaction sent, NO BTC spent) for three trait sizes:
 *   - Smallest trait (color batch, ~12 bytes)
 *   - Medium trait (~2KB)
 *   - Largest trait (~3.5KB)
 *
 * Reports the calldata size and estimated transaction weight for each.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/estimate-mint-gas.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/estimate-mint-gas.ts --network testnet
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
import { getContract, JSONRpcProvider, TransactionOutputFlags } from 'opnet';
import type { IContract } from 'opnet';

import { FrenForgeAbi } from '../abis/FrenForge.abi';
import {
    COMPRESSED_TRAITS,
    type CompressedTrait,
} from '../../compressed-traits/compressed-traits';

const MERKLE_PROOF_DEPTH = 8;

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'https://regtest.opnet.org', network: networks.regtest },
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet },
};

function getArg(flag: string): string | undefined {
    const idx = process.argv.indexOf(flag);
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : undefined;
}

function hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
    }
    return bytes;
}

function packMintData(trait: CompressedTrait): Uint8Array {
    const proofLen = MERKLE_PROOF_DEPTH;
    const traitBlob = hexToBytes(trait.blob);

    const totalSize = 4 + 4 + 32 * proofLen + 4 + traitBlob.length;
    const buf = new Uint8Array(totalSize);
    const view = new DataView(buf.buffer);
    let offset = 0;

    view.setUint32(offset, trait.leafIndex, false);
    offset += 4;

    view.setUint32(offset, proofLen, false);
    offset += 4;

    for (let i = 0; i < proofLen; i++) {
        const hash = hexToBytes(trait.proof[i]);
        buf.set(hash, offset);
        offset += 32;
    }

    view.setUint32(offset, traitBlob.length, false);
    offset += 4;
    buf.set(traitBlob, offset);

    return buf;
}

type ContractCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    properties?: Record<string, unknown>;
    estimatedGas?: bigint;
    calldata?: Uint8Array;
}>;

function method(contract: IContract, name: string): ContractCall {
    return (contract as unknown as Record<string, ContractCall>)[name];
}

async function main(): Promise<void> {
    const networkName = getArg('--network') ?? 'testnet';
    const netConfig = NETWORKS[networkName];
    if (!netConfig) {
        console.error(`Unknown network "${networkName}".`);
        process.exit(1);
    }

    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (!mnemonicPhrase) {
        console.error('DEPLOYER_MNEMONIC environment variable is required');
        process.exit(1);
    }

    const deploymentPath = join(__dirname, `../deployments/${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment at ${deploymentPath}`);
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const forgeAddress: string = deployment.contracts.FRENFORGE;
    const treasuryAddress: string = deployment.deployer;

    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);

    const rpc = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    const forgeAddr = await rpc.getPublicKeyInfo(forgeAddress, true);
    if (!forgeAddr) {
        console.error('Could not resolve FrenForge');
        process.exit(1);
    }

    const forge = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpc,
        netConfig.network,
        wallet.address,
    );

    // Sort traits by blob size to pick smallest, medium, largest
    const sorted = [...COMPRESSED_TRAITS].sort((a, b) => a.blob.length - b.blob.length);
    const smallest = sorted[0];
    const medium = sorted[Math.floor(sorted.length / 2)];
    const largest = sorted[sorted.length - 1];

    const testCases = [
        { label: 'Smallest (color batch)', trait: smallest },
        { label: 'Medium trait', trait: medium },
        { label: 'Largest trait', trait: largest },
    ];

    console.log('═══════════════════════════════════════════════════════════════');
    console.log('  MiFrens — Mint Gas Estimation (Simulation Only)');
    console.log('═══════════════════════════════════════════════════════════════');
    console.log(`  Network:     ${networkName}`);
    console.log(`  FrenForge:   ${forgeAddress}`);
    console.log(`  Wallet:      ${wallet.p2tr}`);
    console.log('═══════════════════════════════════════════════════════════════\n');

    for (const tc of testCases) {
        const traitBytes = tc.trait.blob.length / 2;
        const packed = packMintData(tc.trait);

        // Calldata = 32 (traitKey u256) + 4 (BYTES prefix) + packed.length
        const calldataSize = 32 + 4 + packed.length;

        // Merkle proof overhead: 8 * 32 = 256 bytes
        const proofOverhead = MERKLE_PROOF_DEPTH * 32;

        console.log(`--- ${tc.label}: "${tc.trait.label}" ---`);
        console.log(`  Trait key:      ${tc.trait.traitKey}`);
        console.log(`  Trait data:     ${traitBytes} bytes`);
        console.log(`  Merkle proof:   ${proofOverhead} bytes (${MERKLE_PROOF_DEPTH} hashes)`);
        console.log(`  Packed blob:    ${packed.length} bytes`);
        console.log(`  Total calldata: ${calldataSize} bytes`);

        // Estimate witness weight:
        // Taproot witness = calldata goes into witness data (75% discount)
        // witness_weight = calldata_bytes * 1 (witness units)
        // non_witness_overhead ~ 200 bytes * 4 = 800 weight units (inputs, outputs, sigs)
        // extra_output (treasury payment) ~ 43 bytes * 4 = 172 weight units
        const witnessWeight = calldataSize;
        const nonWitnessWeight = 800 + 172; // inputs + outputs + sigs + treasury output
        const totalWeight = witnessWeight + nonWitnessWeight;
        const vSize = Math.ceil(totalWeight / 4);

        // Fee estimates at different rates
        const rates = [1, 3, 5, 10, 20, 50];
        console.log(`  Estimated vSize: ~${vSize} vB (witness discount applied)`);
        console.log(`  Fee estimates:`);
        for (const rate of rates) {
            const feeSats = vSize * rate;
            const feeBTC = (feeSats / 1e8).toFixed(8);
            console.log(`    ${rate.toString().padStart(2)} sat/vB: ${feeSats.toLocaleString().padStart(8)} sats (${feeBTC} BTC)`);
        }

        // Try simulation
        try {
            (forge as IContract & { setTransactionDetails: (d: unknown) => void }).setTransactionDetails({
                inputs: [],
                outputs: [
                    {
                        to: treasuryAddress,
                        value: 144_000n,
                        index: 1,
                        flags: TransactionOutputFlags.hasTo,
                    },
                ],
            });

            const sim = await method(forge, 'mint')(
                BigInt(tc.trait.traitKey),
                packed,
            );

            if (sim.revert) {
                console.log(`  Simulation:     REVERTED — ${sim.revert}`);
                // Revert on already-inscribed traits is expected on testnet
                if (sim.revert.includes('already inscribed')) {
                    console.log(`  (Expected — trait already inscribed on testnet)`);
                }
            } else {
                const tokenId = sim.properties?.tokenId ?? sim.decoded?.[0] ?? '?';
                console.log(`  Simulation:     OK (would mint token #${tokenId})`);
            }
        } catch (err) {
            console.log(`  Simulation:     ERROR — ${err instanceof Error ? err.message : String(err)}`);
        }

        console.log('');
    }

    // Summary table
    console.log('═══════════════════════════════════════════════════════════════');
    console.log('  Summary: Total cost per mint = mint_price + gas_fee');
    console.log('═══════════════════════════════════════════════════════════════');
    console.log('  Mint price:  144,000 sats (0.00144000 BTC)');
    console.log('');
    console.log('  Worst case (largest trait @ 50 sat/vB):');
    const worstPacked = packMintData(largest);
    const worstCalldata = 32 + 4 + worstPacked.length;
    const worstVsize = Math.ceil((worstCalldata + 972) / 4);
    const worstFee = worstVsize * 50;
    console.log(`    Gas: ~${worstFee.toLocaleString()} sats + Mint: 144,000 sats = ${(worstFee + 144_000).toLocaleString()} sats total`);
    console.log('');
    console.log('  Best case (smallest trait @ 3 sat/vB):');
    const bestPacked = packMintData(smallest);
    const bestCalldata = 32 + 4 + bestPacked.length;
    const bestVsize = Math.ceil((bestCalldata + 972) / 4);
    const bestFee = bestVsize * 3;
    console.log(`    Gas: ~${bestFee.toLocaleString()} sats + Mint: 144,000 sats = ${(bestFee + 144_000).toLocaleString()} sats total`);
    console.log('═══════════════════════════════════════════════════════════════\n');

    console.log('NOTE: These are estimates based on calldata size + witness discount.');
    console.log('Actual fees depend on mainnet mempool conditions at time of mint.');
    console.log('The 100,000 sat gas buffer in the frontend should cover up to ~50 sat/vB.\n');

    await rpc.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Failed:', err);
    process.exit(1);
});
