#!/usr/bin/env tsx

/**
 * deploy-all.ts — Part 1: Deploy contracts only
 *
 * Deploys MiFrens NFT + FrenForge and saves addresses to deployments/<network>.json.
 * After both are confirmed on OPScan, run configure-contracts.ts (Part 2) to link them.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-all.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-all.ts --network testnet
 */

import * as fs from 'fs';
import { join } from 'path';
import { execSync } from 'child_process';

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

/** Mint price in sats — default 144,000 (0.00144 BTC). Override via MINT_PRICE_SATS env var. */
const MINT_PRICE_SATS = process.env.MINT_PRICE_SATS ? BigInt(process.env.MINT_PRICE_SATS) : 144_000n;

/** Delay after first deployment before second */
const DEPLOY_GAP_MS = 15_000;

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
        requestedAmount: 5_000_000n,
    });
}

async function broadcastDeployment(
    provider: OPNetLimitedProvider,
    result: DeploymentResult,
): Promise<void> {
    await provider.broadcastTransaction(result.transaction[0], false);
    await sleep(2_000);
    await provider.broadcastTransaction(result.transaction[1], false);
}

function encodeNftCalldata(treasury: Address, mintPriceSats: bigint): Uint8Array {
    const writer = new BinaryWriter();
    writer.writeAddress(treasury);
    writer.writeU256(mintPriceSats);
    return writer.getBuffer();
}

// ---------------------------------------------------------------------------
// Auto-update frontend contract addresses
// ---------------------------------------------------------------------------

function updateFrontendContracts(
    networkName: string,
    nftAddress: string,
    forgeAddress: string,
    treasuryAddress: string,
): void {
    const contractsPath = join(__dirname, '../../src/constants/contracts.ts');
    if (!fs.existsSync(contractsPath)) {
        console.log('  src/constants/contracts.ts not found, skipping auto-update');
        return;
    }

    const markers: Record<string, string> = {
        mainnet: '// Mainnet',
        testnet: '// OPNet Testnet',
        regtest: '// Regtest',
    };

    const marker = markers[networkName];
    if (!marker) {
        console.log(`  No frontend marker for "${networkName}", skipping auto-update`);
        return;
    }

    let content = fs.readFileSync(contractsPath, 'utf-8');

    const sectionStart = content.indexOf(marker);
    if (sectionStart === -1) {
        console.log(`  Could not find "${marker}" section, skipping auto-update`);
        return;
    }

    const sectionEnd = content.indexOf('},', sectionStart);
    if (sectionEnd === -1) {
        console.log('  Could not find section end, skipping auto-update');
        return;
    }

    let section = content.substring(sectionStart, sectionEnd);
    section = section.replace(/miFrens: ".*?"/, `miFrens: "${nftAddress}"`);
    section = section.replace(/frenForge: ".*?"/, `frenForge: "${forgeAddress}"`);
    section = section.replace(/treasury: ".*?"/, `treasury: "${treasuryAddress}"`);

    content = content.substring(0, sectionStart) + section + content.substring(sectionEnd);
    fs.writeFileSync(contractsPath, content);
    console.log(`  Updated src/constants/contracts.ts (${networkName} addresses)`);
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

    // ===================================================================
    // STEP 0: Recompile contracts from source
    // ===================================================================
    console.log('STEP 0: Recompiling contracts from source...');
    const contractsDir = join(__dirname, '..');
    try {
        execSync('npm run build:all', { cwd: contractsDir, stdio: 'inherit' });
        console.log('  Build complete.\n');
    } catch {
        console.error('  Contract build failed. Fix compilation errors before deploying.');
        process.exit(1);
    }

    // Load Merkle data (validate early so we don't deploy then fail)
    const merkleJsonPath = join(__dirname, '../../compressed-traits/merkle.json');
    if (!fs.existsSync(merkleJsonPath)) {
        console.error(`Merkle JSON not found at ${merkleJsonPath}`);
        console.error('Run: node scripts/compress-traits.mjs');
        process.exit(1);
    }
    const merkleData = JSON.parse(fs.readFileSync(merkleJsonPath, 'utf-8'));

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — Part 1: Deploy Contracts');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:      ${networkName}`);
    console.log(`  RPC:          ${netConfig.rpcUrl}`);
    console.log(`  Mint price:   ${MINT_PRICE_SATS} sats`);
    console.log(`  Merkle root:  ${merkleData.root}`);
    console.log(`  Leaf count:   ${merkleData.leafCount}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer: ${wallet.p2tr}\n`);

    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });
    const factory = new TransactionFactory();

    const buildDir = join(__dirname, '../build');

    // ===================================================================
    // STEP 1: Deploy MiFrens NFT
    // ===================================================================
    console.log('STEP 1: Deploying MiFrens NFT...');

    const nftWasm = new Uint8Array(fs.readFileSync(join(buildDir, 'nft.wasm')));
    console.log(`  Loaded nft.wasm (${nftWasm.length} bytes)`);

    let utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
    console.log(`  Found ${utxos.length} UTXOs`);

    let challenge = await rpcProvider.getChallenge();
    console.log(`  Challenge epoch #${challenge.epochNumber}`);

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
    console.log(`  MiFrens deployed: ${nftAddress}`);
    console.log(`  Waiting before deploying FrenForge...`);
    await sleep(DEPLOY_GAP_MS);

    // ===================================================================
    // STEP 2: Deploy FrenForge
    // ===================================================================
    console.log('\nSTEP 2: Deploying FrenForge...');

    const forgeWasm = new Uint8Array(fs.readFileSync(join(buildDir, 'frenforge.wasm')));
    console.log(`  Loaded frenforge.wasm (${forgeWasm.length} bytes)`);

    utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
    console.log(`  Found ${utxos.length} UTXOs`);

    challenge = await rpcProvider.getChallenge();
    console.log(`  Challenge epoch #${challenge.epochNumber}`);

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
    console.log(`  FrenForge deployed: ${forgeAddress}`);

    // ===================================================================
    // Save deployment data
    // ===================================================================
    const deploymentsDir = join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    const deploymentData = {
        network: networkName,
        deployedAt: new Date().toISOString(),
        deployer: wallet.p2tr,
        mintPriceSats: Number(MINT_PRICE_SATS),
        merkleRoot: merkleData.root,
        paletteHash: merkleData.paletteHash,
        leafCount: merkleData.leafCount,
        configured: false,
        contracts: {
            MIFRENS: nftAddress,
            FRENFORGE: forgeAddress,
        },
    };

    const outputPath = join(deploymentsDir, `${networkName}.json`);
    fs.writeFileSync(outputPath, JSON.stringify(deploymentData, null, 2));

    // ===================================================================
    // Auto-update frontend
    // ===================================================================
    console.log('\nUpdating frontend contract addresses...');
    updateFrontendContracts(networkName, nftAddress, forgeAddress, wallet.p2tr);

    // ===================================================================
    // Summary
    // ===================================================================
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Deployment Broadcast Complete');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  NFT:      ${nftAddress}`);
    console.log(`  FrenForge: ${forgeAddress}`);
    console.log(`  Saved:    ${outputPath}`);
    console.log('═══════════════════════════════════════════════════════════');
    console.log('\n  Next: confirm both contracts on OPScan, then run:');
    console.log(`  DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/configure-contracts.ts --network ${networkName}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Deployment failed:', err);
    process.exit(1);
});
