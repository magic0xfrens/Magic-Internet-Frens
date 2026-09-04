#!/usr/bin/env tsx

/**
 * SVGSizeTest Deployment Script
 *
 * Deploys a lightweight test contract to experimentally find OPNet's
 * maximum RPC response size for tokenURI-style returns.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-svg-test.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-svg-test.ts --network testnet
 */

import * as fs from 'fs';
import { join } from 'path';

import {
    Mnemonic,
    TransactionFactory,
    OPNetLimitedProvider,
    AddressTypes,
    MLDSASecurityLevel,
} from '@btc-vision/transaction';
import type { UTXO, DeploymentResult } from '@btc-vision/transaction';
import { networks } from '@btc-vision/bitcoin';
import { JSONRpcProvider } from 'opnet';

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

async function fetchUtxos(
    provider: OPNetLimitedProvider,
    address: string,
    minAmount: bigint = 100_000n,
): Promise<UTXO[]> {
    return provider.fetchUTXO({
        address,
        minAmount,
        requestedAmount: 1_000_000n,
    });
}

async function broadcastDeployment(
    provider: OPNetLimitedProvider,
    result: DeploymentResult,
): Promise<void> {
    console.log('  Broadcasting funding TX...');
    const fundingRes = await provider.broadcastTransaction(result.transaction[0], false);
    if (fundingRes && typeof fundingRes === 'object' && 'error' in fundingRes) {
        throw new Error(`Funding TX rejected: ${JSON.stringify(fundingRes)}`);
    }
    console.log(`  Funding TX broadcast: ${typeof fundingRes === 'string' ? fundingRes : JSON.stringify(fundingRes)}`);

    await new Promise((r) => setTimeout(r, 3000));

    console.log('  Broadcasting deployment TX...');
    const deployRes = await provider.broadcastTransaction(result.transaction[1], false);
    if (deployRes && typeof deployRes === 'object' && 'error' in deployRes) {
        throw new Error(`Deploy TX rejected: ${JSON.stringify(deployRes)}`);
    }
    console.log(`  Deploy TX broadcast: ${typeof deployRes === 'string' ? deployRes : JSON.stringify(deployRes)}`);
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

    console.log('SVGSizeTest Deployment');
    console.log(`Network: ${networkName}`);
    console.log(`RPC: ${netConfig.rpcUrl}\n`);

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer: ${wallet.p2tr}\n`);

    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });
    const factory = new TransactionFactory();

    const buildDir = join(__dirname, '../build');

    // --- Load compiled WASM ---
    const wasmPath = join(buildDir, 'svgtest.wasm');
    if (!fs.existsSync(wasmPath)) {
        console.error(`svgtest.wasm not found at ${wasmPath}`);
        console.error('Build it first: cd contracts && npm run build:svgtest');
        process.exit(1);
    }

    const svgtestWasm = new Uint8Array(fs.readFileSync(wasmPath));
    console.log(`Loaded svgtest.wasm (${svgtestWasm.length} bytes)\n`);

    // -----------------------------------------------------------------------
    // Deploy
    // -----------------------------------------------------------------------
    console.log('Deploying SVGSizeTest...');

    const utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
    console.log(`  Found ${utxos.length} UTXOs`);

    if (utxos.length === 0) {
        console.error('No UTXOs available. Fund the deployer address first.');
        process.exit(1);
    }

    console.log('  Fetching challenge...');
    const challenge = await rpcProvider.getChallenge();
    console.log(`  Challenge epoch #${challenge.epochNumber}, difficulty ${challenge.difficulty}`);

    const deployResult = await factory.signDeployment({
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        network: netConfig.network,
        from: wallet.p2tr,
        bytecode: svgtestWasm,
        challenge,
        utxos,
        feeRate: 5,
        priorityFee: 10_000n,
        gasSatFee: 10_000n,
        revealMLDSAPublicKey: true,
        linkMLDSAPublicKeyToAddress: true,
    });

    await broadcastDeployment(limitedProvider, deployResult);
    const contractAddress = deployResult.contractAddress;
    console.log(`\n  SVGSizeTest deployed: ${contractAddress}\n`);

    // -----------------------------------------------------------------------
    // Save deployment
    // -----------------------------------------------------------------------
    const deploymentsDir = join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    const deploymentsPath = join(deploymentsDir, `${networkName}.json`);
    let deployment: Record<string, unknown> = {};
    if (fs.existsSync(deploymentsPath)) {
        deployment = JSON.parse(fs.readFileSync(deploymentsPath, 'utf-8'));
    }

    if (!deployment.contracts || typeof deployment.contracts !== 'object') {
        deployment.contracts = {};
    }
    (deployment.contracts as Record<string, string>).SVGTEST = contractAddress;
    deployment.SVGTestDeployedAt = new Date().toISOString();
    fs.writeFileSync(deploymentsPath, JSON.stringify(deployment, null, 2));
    console.log(`Updated ${deploymentsPath}\n`);

    // --- Summary ---
    console.log('Deployment Complete!\n');
    console.log(`  Contract: ${contractAddress}`);
    console.log(`  Network:  ${networkName}`);
    console.log('\nNext step:');
    console.log('  DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-svg-limits.ts --network ' + networkName);

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Deployment failed:', err);
    process.exit(1);
});
