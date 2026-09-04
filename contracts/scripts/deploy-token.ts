#!/usr/bin/env tsx

/**
 * CauldronToken (MIF OP20) Deployment Script
 *
 * Deploys the MIF fungible token with tiered tax based on MiFrens holdings.
 *
 * Constructor args:
 *   generation (u256), name (string), symbol (string),
 *   nftContract (Address), feeRecipient (Address)
 *
 * Reads MiFrens NFT address from deployments/<network>.json.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-token.ts --network testnet
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
} from '@btc-vision/transaction';
import type { UTXO, DeploymentResult } from '@btc-vision/transaction';
import { networks } from '@btc-vision/bitcoin';
import { JSONRpcProvider } from 'opnet';

// ---------------------------------------------------------------------------
// Token configuration
// ---------------------------------------------------------------------------

const TOKEN_GENERATION = 1n;
const TOKEN_NAME = 'Magic Internet Fren';
const TOKEN_SYMBOL = 'MIF';

// ---------------------------------------------------------------------------
// Network config
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

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
}

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
    const fundRes = await provider.broadcastTransaction(result.transaction[0], false);
    console.log(`  Funding TX: ${typeof fundRes === 'string' ? fundRes : JSON.stringify(fundRes)}`);

    await sleep(3_000);

    console.log('  Broadcasting deployment TX...');
    const deployRes = await provider.broadcastTransaction(result.transaction[1], false);
    console.log(`  Deploy TX:  ${typeof deployRes === 'string' ? deployRes : JSON.stringify(deployRes)}`);
}

function encodeTokenCalldata(
    generation: bigint,
    name: string,
    symbol: string,
    nftContractAddr: ReturnType<JSONRpcProvider['getPublicKeyInfo']> extends Promise<infer T> ? T : never,
    feeRecipientAddr: ReturnType<JSONRpcProvider['getPublicKeyInfo']> extends Promise<infer T> ? T : never,
): Uint8Array {
    const writer = new BinaryWriter();
    writer.writeU256(generation);
    writer.writeStringWithLength(name);
    writer.writeStringWithLength(symbol);
    writer.writeAddress(nftContractAddr!);
    writer.writeAddress(feeRecipientAddr!);
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

    // Load deployment data to get NFT address
    const deploymentsPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentsPath)) {
        console.error(`No deployment found at ${deploymentsPath}`);
        console.error('Deploy the NFT contract first.');
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentsPath, 'utf-8'));
    const nftAddress = deployment.contracts?.MIFRENS;
    if (!nftAddress) {
        console.error('MIFRENS address not found in deployment file');
        process.exit(1);
    }

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MIF Token — Deploy CauldronToken (OP20)');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:       ${networkName}`);
    console.log(`  RPC:           ${netConfig.rpcUrl}`);
    console.log(`  Token:         ${TOKEN_NAME} (${TOKEN_SYMBOL})`);
    console.log(`  Generation:    ${TOKEN_GENERATION}`);
    console.log(`  NFT contract:  ${nftAddress}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer (treasury): ${wallet.p2tr}\n`);

    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    try {
        // --- Resolve on-chain addresses ---
        console.log('Resolving on-chain addresses...');
        const nftAddr = await rpcProvider.getPublicKeyInfo(nftAddress, true);
        if (!nftAddr) {
            console.error(`Could not resolve NFT address: ${nftAddress}`);
            console.error('Is the NFT contract confirmed on-chain?');
            process.exit(1);
        }
        console.log('  NFT contract resolved');

        const treasuryAddr = await rpcProvider.getPublicKeyInfo(wallet.p2tr, true);
        if (!treasuryAddr) {
            console.error(`Could not resolve treasury address: ${wallet.p2tr}`);
            process.exit(1);
        }
        console.log('  Treasury resolved\n');

        // --- Load WASM ---
        const buildDir = join(__dirname, '../build');
        const wasmPath = join(buildDir, 'cauldron-token.wasm');
        if (!fs.existsSync(wasmPath)) {
            console.error(`WASM not found: ${wasmPath}`);
            console.error('Build first: cd contracts && npm run build:cauldron-token');
            process.exit(1);
        }
        const tokenWasm = new Uint8Array(fs.readFileSync(wasmPath));
        console.log(`Loaded cauldron-token.wasm (${(tokenWasm.length / 1024).toFixed(1)} KB)\n`);

        // --- Encode constructor calldata ---
        const calldata = encodeTokenCalldata(
            TOKEN_GENERATION,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            nftAddr,
            treasuryAddr,
        );
        console.log(`Calldata encoded (${calldata.length} bytes)\n`);

        // --- Deploy ---
        console.log('Deploying CauldronToken...');
        const utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
        console.log(`  Found ${utxos.length} UTXOs`);

        if (utxos.length === 0) {
            console.error('  No UTXOs available. Fund the deployer address first.');
            process.exit(1);
        }

        console.log('  Fetching challenge...');
        const challenge = await rpcProvider.getChallenge();
        console.log(`  Challenge epoch #${challenge.epochNumber}, difficulty ${challenge.difficulty}`);

        const factory = new TransactionFactory();
        const result = await factory.signDeployment({
            signer: wallet.keypair,
            mldsaSigner: wallet.mldsaKeypair,
            network: netConfig.network,
            from: wallet.p2tr,
            bytecode: tokenWasm,
            calldata,
            challenge,
            utxos,
            feeRate: 5,
            priorityFee: 10_000n,
            gasSatFee: 10_000n,
            revealMLDSAPublicKey: true,
            linkMLDSAPublicKeyToAddress: true,
        });

        await broadcastDeployment(limitedProvider, result);
        const tokenAddress = result.contractAddress;
        console.log(`\n  CauldronToken deployed: ${tokenAddress}\n`);

        // --- Save deployment address ---
        deployment.contracts.MIF_TOKEN = tokenAddress;
        deployment.MIFTokenDeployedAt = new Date().toISOString();
        fs.writeFileSync(deploymentsPath, JSON.stringify(deployment, null, 2));
        console.log(`Updated ${deploymentsPath}\n`);

        // --- Summary ---
        console.log('═══════════════════════════════════════════════════════════');
        console.log('  Deployment Complete!');
        console.log('═══════════════════════════════════════════════════════════');
        console.log(`  Token:      ${TOKEN_NAME} (${TOKEN_SYMBOL})`);
        console.log(`  Address:    ${tokenAddress}`);
        console.log(`  NFT:        ${nftAddress}`);
        console.log(`  Treasury:   ${wallet.p2tr}`);
        console.log(`  Generation: ${TOKEN_GENERATION}`);
        console.log('═══════════════════════════════════════════════════════════');
        console.log('\nUpdate src/constants/contracts.ts:');
        console.log(`  mifToken: "${tokenAddress}"`);
        console.log('═══════════════════════════════════════════════════════════');
        console.log('\nNext steps:');
        console.log('  1. Wait for confirmation on OPScan');
        console.log('  2. Mint initial supply (CauldronToken has unlimited max supply)');
        console.log('  3. Set router + WBTC addresses for auto-swap tax');
        console.log('  4. Add liquidity on MotoSwap');
        console.log('═══════════════════════════════════════════════════════════\n');

    } finally {
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
    }
}

main().catch((err) => {
    console.error('Deployment failed:', err);
    process.exit(1);
});
