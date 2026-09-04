#!/usr/bin/env tsx

/**
 * MiFrens NFT Deployment Script
 *
 * Deploys the MiFrens contract with BTC-paid minting:
 *   - Treasury address = deployer's P2TR address (receives mint payments)
 *   - Mint price = 144,000 sats (0.00144 BTC)
 *   - Saves deployed address to deployments/<network>.json
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-cauldron.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-cauldron.ts --network testnet
 */

import * as fs from 'fs';
import { join } from 'path';

import {
    Mnemonic,
    TransactionFactory,
    OPNetLimitedProvider,
    BinaryWriter,
    AddressTypes,
    MLDSASecurityLevel,
    Address,
} from '@btc-vision/transaction';
import type { UTXO, DeploymentResult } from '@btc-vision/transaction';
import { networks } from '@btc-vision/bitcoin';
import { JSONRpcProvider } from 'opnet';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Mint price in sats: 0.00144 BTC = 144,000 sats */
const MINT_PRICE_SATS = 144_000n;

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
    // Broadcast funding TX first, then deployment TX
    await provider.broadcastTransaction(result.transaction[0], false);
    // Small delay to let funding TX propagate
    await new Promise((r) => setTimeout(r, 2000));
    await provider.broadcastTransaction(result.transaction[1], false);
}

function encodeNftCalldata(treasury: Address, mintPriceSats: bigint): Uint8Array {
    const writer = new BinaryWriter();
    writer.writeAddress(treasury);
    writer.writeU256(mintPriceSats);
    return writer.getBuffer();
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

    console.log('MiFrens NFT Deployment');
    console.log(`Network: ${networkName}`);
    console.log(`RPC: ${netConfig.rpcUrl}`);
    console.log(`Mint price: ${MINT_PRICE_SATS} sats (${Number(MINT_PRICE_SATS) / 1e8} BTC)\n`);

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer (treasury): ${wallet.p2tr}\n`);

    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });
    const factory = new TransactionFactory();

    const buildDir = join(__dirname, '../build');

    // --- Load compiled WASM ---
    const nftWasm = new Uint8Array(fs.readFileSync(join(buildDir, 'nft.wasm')));
    console.log('Loaded nft.wasm\n');

    // -----------------------------------------------------------------------
    // Deploy MiFrens with treasury + mint price calldata
    // -----------------------------------------------------------------------
    console.log('Deploying MiFrens...');
    console.log(`  Treasury: ${wallet.p2tr}`);
    console.log(`  Mint price: ${MINT_PRICE_SATS} sats`);

    const utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
    console.log(`  Found ${utxos.length} UTXOs`);

    console.log('  Fetching challenge...');
    const challenge = await rpcProvider.getChallenge();
    console.log(`  Challenge epoch #${challenge.epochNumber}, difficulty ${challenge.difficulty}`);

    const nftResult = await factory.signDeployment({
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        network: netConfig.network,
        from: wallet.p2tr,
        bytecode: nftWasm,
        calldata: encodeNftCalldata(wallet.address, MINT_PRICE_SATS),
        challenge,
        utxos,
        feeRate: 5,
        priorityFee: 10_000n,
        gasSatFee: 10_000n,
        revealMLDSAPublicKey: true,
        linkMLDSAPublicKeyToAddress: true,
    });

    await broadcastDeployment(limitedProvider, nftResult);
    const nftAddress = nftResult.contractAddress;
    console.log(`  MiFrens deployed: ${nftAddress}\n`);

    // -----------------------------------------------------------------------
    // Save deployed addresses
    // -----------------------------------------------------------------------
    const deploymentsDir = join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    const deploymentData = {
        network: networkName,
        deployedAt: new Date().toISOString(),
        deployer: wallet.p2tr,
        mintPriceSats: Number(MINT_PRICE_SATS),
        contracts: {
            MIFRENS: nftAddress,
        },
    };

    const outputPath = join(deploymentsDir, `${networkName}.json`);
    fs.writeFileSync(outputPath, JSON.stringify(deploymentData, null, 2));
    console.log(`Addresses saved to ${outputPath}\n`);

    // --- Summary ---
    console.log('Deployment Complete!\n');
    console.log(`  MiFrens: ${nftAddress}`);
    console.log(`  Treasury:  ${wallet.p2tr}`);
    console.log(`  Mint Price: ${MINT_PRICE_SATS} sats (0.00144 BTC)\n`);
    console.log('Next Steps:');
    console.log('  1. Mint NFTs: npm run cauldron:mint-nft');
    console.log('  2. After 777 minted: npm run cauldron:add-liquidity');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Deployment failed:', err);
    process.exit(1);
});
