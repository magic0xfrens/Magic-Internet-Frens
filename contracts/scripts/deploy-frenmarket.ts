#!/usr/bin/env tsx

/**
 * FrenMarket Deployment & Configuration Script
 *
 * Deploys the NFT marketplace contract, then auto-configures it:
 *   1. setNFTContract(nft-address)
 *   2. setFeeRecipient(treasury-address)
 *   3. setFeeRecipientHash(sha256(treasury-bech32-string))
 *
 * Reads the NFT contract address from deployments/<network>.json.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-frenmarket.ts --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-frenmarket.ts --network testnet --configure-only
 */

import * as fs from 'fs';
import { createHash } from 'crypto';
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
import { getContract, JSONRpcProvider, ABIDataTypes, BitcoinAbiTypes } from 'opnet';
import type { IContract, TransactionParameters } from 'opnet';

// ---------------------------------------------------------------------------
// FrenMarket ABI (admin methods only — enough for configuration)
// ---------------------------------------------------------------------------

const FrenMarketConfigAbi = [
    {
        name: 'setNFTContract',
        inputs: [{ name: 'nftContract', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setFeeRecipient',
        inputs: [{ name: 'recipient', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setFeeRecipientHash',
        inputs: [{ name: 'hash', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setFeeBps',
        inputs: [{ name: 'bps', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getFeeBps',
        inputs: [],
        outputs: [{ name: 'bps', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
];

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Delay between transactions */
const TX_DELAY_MS = 5_000;

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
    await provider.broadcastTransaction(result.transaction[0], false);
    await sleep(2_000);
    await provider.broadcastTransaction(result.transaction[1], false);
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
// Deploy
// ---------------------------------------------------------------------------

async function deploy(
    wallet: { p2tr: string; keypair: unknown; mldsaKeypair: unknown },
    limitedProvider: OPNetLimitedProvider,
    rpcProvider: JSONRpcProvider,
    netConfig: NetworkConfig,
): Promise<string> {
    const factory = new TransactionFactory();
    const buildDir = join(__dirname, '../build');

    const wasmPath = join(buildDir, 'frenmarket.wasm');
    if (!fs.existsSync(wasmPath)) {
        console.error(`WASM not found: ${wasmPath}`);
        console.error('Compile first: cd contracts && npm run build:market');
        process.exit(1);
    }
    const marketWasm = new Uint8Array(fs.readFileSync(wasmPath));
    console.log(`Loaded frenmarket.wasm (${marketWasm.length} bytes)\n`);

    console.log('Deploying FrenMarket...');
    const utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
    console.log(`  Found ${utxos.length} UTXOs`);

    console.log('  Fetching challenge...');
    const challenge = await rpcProvider.getChallenge();
    console.log(`  Challenge epoch #${challenge.epochNumber}, difficulty ${challenge.difficulty}`);

    const result = await factory.signDeployment({
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        network: netConfig.network,
        from: wallet.p2tr,
        bytecode: marketWasm,
        challenge,
        utxos,
        feeRate: 5,
        priorityFee: 10_000n,
        gasSatFee: 10_000n,
        revealMLDSAPublicKey: true,
        linkMLDSAPublicKeyToAddress: true,
    });

    await broadcastDeployment(limitedProvider, result);
    return result.contractAddress;
}

// ---------------------------------------------------------------------------
// Configure
// ---------------------------------------------------------------------------

async function configure(
    wallet: { p2tr: string; keypair: unknown; mldsaKeypair: unknown; address: unknown },
    rpcProvider: JSONRpcProvider,
    netConfig: NetworkConfig,
    marketAddress: string,
    nftAddress: string,
): Promise<void> {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Configuring FrenMarket');
    console.log('═══════════════════════════════════════════════════════════\n');

    const txParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 500_000n,
        feeRate: 5,
        network: netConfig.network,
    };

    // Resolve on-chain addresses
    console.log('Resolving contract public keys...');
    const marketAddr = await rpcProvider.getPublicKeyInfo(marketAddress, true);
    if (!marketAddr) {
        console.error(`Could not resolve marketplace address: ${marketAddress}`);
        console.error('Is the contract confirmed? Wait a few blocks and retry with --configure-only');
        process.exit(1);
    }
    console.log('  Marketplace resolved');

    const nftAddr = await rpcProvider.getPublicKeyInfo(nftAddress, true);
    if (!nftAddr) {
        console.error(`Could not resolve NFT address: ${nftAddress}`);
        process.exit(1);
    }
    console.log('  NFT resolved');

    const treasuryBech32 = wallet.p2tr;
    const treasuryAddr = await rpcProvider.getPublicKeyInfo(treasuryBech32, true);
    if (!treasuryAddr) {
        console.error(`Could not resolve treasury address: ${treasuryBech32}`);
        process.exit(1);
    }
    console.log('  Treasury resolved\n');

    const marketContract = getContract<IContract>(
        marketAddr,
        FrenMarketConfigAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // STEP 1: setNFTContract
    console.log('STEP 1: setNFTContract...');
    const step1 = await method(marketContract, 'setNFTContract')(nftAddr);
    if (step1.revert) {
        console.error(`  Reverted: ${step1.revert}`);
        process.exit(1);
    }
    const tx1 = await step1.sendTransaction(txParams);
    console.log(`  TX: ${tx1.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);

    // STEP 2: setFeeRecipient (treasury = deployer wallet)
    console.log('\nSTEP 2: setFeeRecipient...');
    const step2 = await method(marketContract, 'setFeeRecipient')(treasuryAddr);
    if (step2.revert) {
        console.error(`  Reverted: ${step2.revert}`);
        process.exit(1);
    }
    const tx2 = await step2.sendTransaction(txParams);
    console.log(`  TX: ${tx2.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);

    // STEP 3: setFeeRecipientHash (sha256 of treasury bech32 string)
    console.log('\nSTEP 3: setFeeRecipientHash...');
    const hashBytes = createHash('sha256').update(Buffer.from(treasuryBech32, 'utf8')).digest();
    const hashBigInt = BigInt('0x' + hashBytes.toString('hex'));
    console.log(`  Treasury: ${treasuryBech32}`);
    console.log(`  Hash:     0x${hashBytes.toString('hex').slice(0, 16)}...`);

    const step3 = await method(marketContract, 'setFeeRecipientHash')(hashBigInt);
    if (step3.revert) {
        console.error(`  Reverted: ${step3.revert}`);
        process.exit(1);
    }
    const tx3 = await step3.sendTransaction(txParams);
    console.log(`  TX: ${tx3.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);

    console.log('\n  Configuration complete!');
}

// ---------------------------------------------------------------------------
// Auto-update frontend contract addresses
// ---------------------------------------------------------------------------

function updateFrontendMarketAddress(networkName: string, marketAddress: string): void {
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
    if (!marker) return;

    let content = fs.readFileSync(contractsPath, 'utf-8');
    const sectionStart = content.indexOf(marker);
    if (sectionStart === -1) return;

    const sectionEnd = content.indexOf('},', sectionStart);
    if (sectionEnd === -1) return;

    let section = content.substring(sectionStart, sectionEnd);
    section = section.replace(/frenMarket: ".*?"/, `frenMarket: "${marketAddress}"`);

    content = content.substring(0, sectionStart) + section + content.substring(sectionEnd);
    fs.writeFileSync(contractsPath, content);
    console.log(`  Updated src/constants/contracts.ts frenMarket (${networkName})`);
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

    const configureOnly = hasFlag('--configure-only');

    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (!mnemonicPhrase) {
        console.error('DEPLOYER_MNEMONIC environment variable is required');
        process.exit(1);
    }

    // Load existing deployment to get NFT address
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
    console.log('  FrenMarket — Deploy & Configure');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:    ${networkName}`);
    console.log(`  RPC:        ${netConfig.rpcUrl}`);
    console.log(`  NFT:        ${nftAddress}`);
    console.log(`  Mode:       ${configureOnly ? 'configure-only' : 'deploy + configure'}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer: ${wallet.p2tr}\n`);

    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    let marketAddress: string;

    if (configureOnly) {
        // --configure-only: skip deployment, use existing address
        marketAddress = deployment.contracts?.FRENMARKET;
        if (!marketAddress) {
            console.error('FRENMARKET address not found in deployment file');
            console.error('Deploy first (without --configure-only)');
            process.exit(1);
        }
        console.log(`Using existing marketplace: ${marketAddress}\n`);
    } else {
        // Deploy
        marketAddress = await deploy(wallet, limitedProvider, rpcProvider, netConfig);
        console.log(`  FrenMarket deployed: ${marketAddress}\n`);

        // Save deployment address
        deployment.contracts.FRENMARKET = marketAddress;
        deployment.FrenMarketDeployedAt = new Date().toISOString();
        fs.writeFileSync(deploymentsPath, JSON.stringify(deployment, null, 2));
        console.log(`Updated ${deploymentsPath}\n`);

        // Wait for confirmation before configuring
        console.log('Waiting for deployment to confirm...');
        await sleep(15_000);
    }

    // Configure
    await configure(wallet, rpcProvider, netConfig, marketAddress, nftAddress);

    // Mark as configured
    deployment.FrenMarketConfigured = true;
    deployment.FrenMarketConfiguredAt = new Date().toISOString();
    fs.writeFileSync(deploymentsPath, JSON.stringify(deployment, null, 2));

    // --- Auto-update frontend ---
    updateFrontendMarketAddress(networkName, marketAddress);

    // --- Summary ---
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Deployment & Configuration Complete!');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Marketplace:  ${marketAddress}`);
    console.log(`  NFT:          ${nftAddress}`);
    console.log(`  Treasury:     ${wallet.p2tr}`);
    console.log(`  Fee:          6.9% (690 BPS)`);
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
