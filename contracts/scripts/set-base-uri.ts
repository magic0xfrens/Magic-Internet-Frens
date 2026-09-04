#!/usr/bin/env tsx

/**
 * set-base-uri.ts — Update the base URI on the deployed FrenForge contract.
 *
 * FrenForge.setBaseURI(bytes uri) stores a new base URI in contract storage.
 * tokenURI then returns: baseURI + comboKey + suffix
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/set-base-uri.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/set-base-uri.ts --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/set-base-uri.ts --network testnet --dry-run
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
// New base URI — metadata CID v2 (includes all body indices)
// ---------------------------------------------------------------------------

const NEW_BASE_URI = 'ipfs://bafybeia4swngf7cfbazti2n6mcul5xyply3onjnkuxm2kpm7xgj3fxhqii/';

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

function hasFlag(flag: string): boolean {
    return process.argv.includes(flag);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

    const dryRun = hasFlag('--dry-run');
    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (!mnemonicPhrase) {
        console.error('DEPLOYER_MNEMONIC environment variable is required');
        process.exit(1);
    }

    // Load deployment data
    const deploymentPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment found at ${deploymentPath}`);
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const forgeAddress: string = deployment.contracts.FRENFORGE;
    if (!forgeAddress) {
        console.error('FRENFORGE not found in deployment file');
        process.exit(1);
    }

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  FrenForge — Set Base URI');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:  ${networkName}`);
    console.log(`  Forge:    ${forgeAddress}`);
    console.log(`  New URI:  ${NEW_BASE_URI}`);
    console.log(`  Dry run:  ${dryRun}`);
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

    // Resolve on-chain address
    console.log('Resolving FrenForge contract public key...');
    const forgeAddr = await resolveContractAddress(rpcProvider, forgeAddress);
    console.log('  Resolved\n');

    const forgeContract = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // Read current base URI first
    console.log('Reading current base URI...');
    try {
        const current = await method(forgeContract, 'getBaseURI')();
        const currentUri = current.decoded?.[0] as string ?? '(empty / hardcoded)';
        console.log(`  Current: ${currentUri}\n`);
    } catch {
        console.log('  Current: (hardcoded default — no storage override)\n');
    }

    // Encode new URI as bytes
    const uriBytes = new Uint8Array(Buffer.from(NEW_BASE_URI, 'utf-8'));
    console.log(`Setting base URI (${uriBytes.length} bytes)...`);

    const sim = await method(forgeContract, 'setBaseURI')(uriBytes);

    if (sim.revert) {
        console.error(`  setBaseURI reverted: ${sim.revert}`);
        process.exit(1);
    }

    console.log('  Simulation OK');

    if (dryRun) {
        console.log('  Dry run — skipping transaction\n');
    } else {
        const receipt = await sim.sendTransaction(txParams);
        console.log(`  TX: ${receipt.transactionId}\n`);
    }

    // Verify by reading back
    if (!dryRun) {
        console.log('Verifying...');
        try {
            const verify = await method(forgeContract, 'getBaseURI')();
            const verifyUri = verify.decoded?.[0] as string ?? '(empty)';
            console.log(`  Base URI: ${verifyUri}`);
        } catch {
            console.log('  (Verification will be available after tx confirms)');
        }
    }

    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Base URI Updated!');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  tokenURI will now resolve to:`);
    console.log(`    ${NEW_BASE_URI}<comboKey>[-L]`);
    console.log(`  Example: ${NEW_BASE_URI}0-3-8-1-0`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Set base URI failed:', err);
    process.exit(1);
});
