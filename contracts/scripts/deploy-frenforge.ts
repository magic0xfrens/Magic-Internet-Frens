#!/usr/bin/env tsx

/**
 * FrenForge Deployment Script
 *
 * Deploys the on-chain SVG FrenForge contract and links it to the MiFrens NFT.
 * Reads the NFT contract address from deployments/<network>.json (created by deploy-cauldron.ts).
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-frenforge.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-frenforge.ts --network testnet
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
    await provider.broadcastTransaction(result.transaction[0], false);
    await new Promise((r) => setTimeout(r, 2000));
    await provider.broadcastTransaction(result.transaction[1], false);
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

    // Load existing deployment to get NFT address
    const deploymentsPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentsPath)) {
        console.error(`No deployment found at ${deploymentsPath}`);
        console.error('Deploy the NFT contract first: npx tsx contracts/scripts/deploy-cauldron.ts');
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentsPath, 'utf-8'));
    const nftAddress = deployment.contracts?.MIFRENS;
    if (!nftAddress) {
        console.error('MIFRENS address not found in deployment file');
        process.exit(1);
    }

    console.log('FrenForge Deployment');
    console.log(`Network: ${networkName}`);
    console.log(`RPC: ${netConfig.rpcUrl}`);
    console.log(`NFT Contract: ${nftAddress}\n`);

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer: ${wallet.p2tr}\n`);

    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });
    const factory = new TransactionFactory();

    const buildDir = join(__dirname, '../build');

    // --- Load compiled WASM ---
    const forgeWasm = new Uint8Array(fs.readFileSync(join(buildDir, 'frenforge.wasm')));
    console.log(`Loaded frenforge.wasm (${forgeWasm.length} bytes)\n`);

    // -----------------------------------------------------------------------
    // Deploy Renderer (no calldata -- NFT address set post-deploy via setNFTContract)
    // -----------------------------------------------------------------------
    console.log('Deploying FrenForge...');

    const utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
    console.log(`  Found ${utxos.length} UTXOs`);

    console.log('  Fetching challenge...');
    const challenge = await rpcProvider.getChallenge();
    console.log(`  Challenge epoch #${challenge.epochNumber}, difficulty ${challenge.difficulty}`);

    const forgeResult = await factory.signDeployment({
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        network: netConfig.network,
        from: wallet.p2tr,
        bytecode: forgeWasm,
        challenge,
        utxos,
        feeRate: 5,
        priorityFee: 10_000n,
        gasSatFee: 10_000n,
        revealMLDSAPublicKey: true,
        linkMLDSAPublicKeyToAddress: true,
    });

    await broadcastDeployment(limitedProvider, forgeResult);
    const forgeAddress = forgeResult.contractAddress;
    console.log(`  FrenForge deployed: ${forgeAddress}\n`);

    // -----------------------------------------------------------------------
    // Save deployment
    // -----------------------------------------------------------------------
    deployment.contracts.FRENFORGE = forgeAddress;
    deployment.FrenForgeDeployedAt = new Date().toISOString();
    fs.writeFileSync(deploymentsPath, JSON.stringify(deployment, null, 2));
    console.log(`Updated ${deploymentsPath}\n`);

    // --- Summary ---
    console.log('Deployment Complete!\n');
    console.log(`  Renderer:  ${forgeAddress}`);
    console.log(`  NFT:       ${nftAddress}`);
    console.log('\nNext Steps:');
    console.log('  1. Call FrenForge.setNFTContract(<nft-address>)');
    console.log('  2. Call FrenForge.setMerkleRoot(<root>)');
    console.log('  3. Call FrenForge.setPaletteHash(<hash>)');
    console.log('  4. Inscribe palette: FrenForge.inscribePalette(<data>)');
    console.log('  5. Inscribe traits: FrenForge.inscribeTrait(<key>, <proof>, <data>)');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Deployment failed:', err);
    process.exit(1);
});
