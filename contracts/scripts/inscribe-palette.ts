#!/usr/bin/env tsx

/**
 * inscribe-palette.ts — Inscribe the global color palette on-chain
 *
 * Reads the palette RGB data from compressed-traits and calls
 * FrenForge.inscribePalette(). Must be run by the deployer (art authority).
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/inscribe-palette.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/inscribe-palette.ts --network testnet
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

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'https://regtest.opnet.org', network: networks.regtest },
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet },
    mainnet: { rpcUrl: 'https://mainnet.opnet.org', network: networks.bitcoin },
};

function getNetworkName(): string {
    const idx = process.argv.indexOf('--network');
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : 'regtest';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
    }
    return bytes;
}

async function resolveContractAddress(
    provider: JSONRpcProvider,
    contractAddr: string,
): Promise<Address> {
    const addr = await provider.getPublicKeyInfo(contractAddr, true);
    if (!addr) {
        throw new Error(
            `Could not resolve public key for ${contractAddr}. ` +
            `Is the contract confirmed on-chain? Check OPScan.`,
        );
    }
    return addr;
}

type ContractCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    sendTransaction: (params: TransactionParameters) => Promise<{
        transactionId: string;
    }>;
}>;

function method(contract: IContract, name: string): ContractCall {
    return (contract as unknown as Record<string, ContractCall>)[name];
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const networkName = getNetworkName();
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

    // Load deployment data
    const deploymentPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment found at ${deploymentPath}`);
        console.error('Run deploy-all.ts first.');
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const forgeAddress: string = deployment.contracts.FRENFORGE;

    // Load palette RGB data (no 2-byte header — raw RGB triplets)
    const { PALETTE_RGB_HEX } = await import('../../compressed-traits/compressed-traits');
    const paletteBytes = hexToBytes(PALETTE_RGB_HEX);
    const paletteColorCount = paletteBytes.length / 3;

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — Inscribe Global Palette');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:      ${networkName}`);
    console.log(`  FrenForge:     ${forgeAddress}`);
    console.log(`  Palette size: ${paletteBytes.length} bytes (${paletteColorCount} colors)`);
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

    // Resolve FrenForge on-chain address
    console.log('Resolving FrenForge public key...');
    const forgeAddr = await resolveContractAddress(rpcProvider, forgeAddress);
    console.log('  FrenForge resolved\n');

    const forgeContract = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // Check if palette is already inscribed
    console.log('Checking inscription status...');
    const statsResult = await method(forgeContract, 'getInscriptionStats')();
    const paletteAlreadyInscribed = statsResult.decoded?.[1]
        ? Number(statsResult.decoded[1] as bigint) !== 0
        : false;

    if (paletteAlreadyInscribed) {
        console.log('  Palette is already inscribed on-chain. Nothing to do.');
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
        return;
    }
    console.log('  Palette not yet inscribed. Proceeding...\n');

    // Inscribe palette
    console.log('Inscribing global palette...');
    const sim = await method(forgeContract, 'inscribePalette')(paletteBytes);

    if (sim.revert) {
        console.error(`  inscribePalette reverted: ${sim.revert}`);
        process.exit(1);
    }

    const receipt = await sim.sendTransaction(txParams);
    console.log(`  TX: ${receipt.transactionId}`);

    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Palette Inscribed!');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  ${paletteColorCount} colors stored on-chain`);
    console.log(`  TX: ${receipt.transactionId}`);
    console.log('═══════════════════════════════════════════════════════════');
    console.log('\nNext: Mint via FrenForge.mint() — traits inscribe lazily during mint.');
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Palette inscription failed:', err);
    process.exit(1);
});
