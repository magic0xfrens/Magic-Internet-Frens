#!/usr/bin/env tsx

/**
 * add-liquidity.ts
 *
 * Post-777-mint script. Run ONCE after all 777 MiFrens NFTs have been minted.
 *
 * Steps:
 *   1. Deploy CauldronToken WASM ("Magic Internet Token" / "MIT")
 *   2. Mint initial MIT supply to deployer
 *   3. Approve NativeSwap for MIT
 *   4. Create NativeSwap pool for MIT (BTC <> MIT)
 *   5. List initial MIT liquidity on NativeSwap
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/add-liquidity.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/add-liquidity.ts --network testnet
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
import {
    getContract,
    JSONRpcProvider,
    OP_20_ABI,
    NativeSwapAbi,
} from 'opnet';
import type {
    IOP20Contract,
    INativeSwapContract,
    TransactionParameters,
} from 'opnet';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Initial MIT supply: 777,000 tokens with 18 decimals */
const INITIAL_MIT_SUPPLY = BigInt('777000') * BigInt('1000000000000000000');

/** Floor price for NativeSwap pool: 1 sat per 1 MIT (very low initial) */
const FLOOR_PRICE = 1n;

/** Anti-bot: enabled for 10 blocks */
const ANTI_BOT_BLOCKS = 10;

/** Anti-bot: max tokens per reservation (50,000 MIT with 18 decimals) */
const ANTI_BOT_MAX_TOKENS = BigInt('50000') * BigInt('1000000000000000000');

/** Max reserves in 5 blocks: 25% */
const MAX_RESERVES_5_BLOCKS_PERCENT = 25;

/** Pool type: 0 = standard AMM */
const POOL_TYPE = 0;

/** NativeSwap contract address (regtest) */
const NATIVE_SWAP_REGTEST = '0xb056ba05448cf4a5468b3e1190b0928443981a93c3aff568467f101e94302422';

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
    nativeSwapAddress: string;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: {
        rpcUrl: 'https://regtest.opnet.org',
        network: networks.regtest,
        nativeSwapAddress: NATIVE_SWAP_REGTEST,
    },
    // testnet NativeSwap address TBD -- check opnet contract addresses for testnet
    testnet: {
        rpcUrl: 'https://testnet.opnet.org',
        network: networks.opnetTestnet,
        nativeSwapAddress: '', // Set when available
    },
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

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
}

function encodeMitCalldata(
    generation: bigint,
    name: string,
    symbol: string,
    nftAddress: string,
    feeRecipient: string,
): Uint8Array {
    const writer = new BinaryWriter();
    writer.writeU256(generation);
    writer.writeStringWithLength(name);
    writer.writeStringWithLength(symbol);
    writer.writeAddress(Address.fromString(nftAddress));
    writer.writeAddress(Address.fromString(feeRecipient));
    return writer.getBuffer();
}

interface DeploymentData {
    deployer: string;
    contracts: {
        MIFREN_NFT: string;
        MIT_TOKEN?: string;
    };
}

function loadDeployment(networkName: string): DeploymentData {
    const filePath = join(__dirname, `../deployments/${networkName}.json`);
    if (!fs.existsSync(filePath)) {
        console.error(`No deployment file at ${filePath}. Run deploy first.`);
        process.exit(1);
    }
    return JSON.parse(fs.readFileSync(filePath, 'utf-8')) as DeploymentData;
}

function saveDeployment(networkName: string, data: DeploymentData): void {
    const filePath = join(__dirname, `../deployments/${networkName}.json`);
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const networkName = getNetworkName();
    const netConfig = NETWORKS[networkName];
    if (!netConfig) {
        console.error(`Unknown network "${networkName}".`);
        process.exit(1);
    }

    if (!netConfig.nativeSwapAddress) {
        console.error(`NativeSwap address not configured for ${networkName}`);
        process.exit(1);
    }

    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (!mnemonicPhrase) {
        console.error('DEPLOYER_MNEMONIC environment variable is required');
        process.exit(1);
    }

    const deployment = loadDeployment(networkName);
    const nftAddress = deployment.contracts.MIFREN_NFT;

    console.log('MIT Token Deployment + NativeSwap Liquidity');
    console.log(`Network: ${networkName}`);
    console.log(`NFT contract: ${nftAddress}\n`);

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer: ${wallet.p2tr}\n`);

    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const factory = new TransactionFactory();

    const rpcProvider = new JSONRpcProvider({
        url: netConfig.rpcUrl,
        network: netConfig.network,
    });

    const buildDir = join(__dirname, '../build');

    // -----------------------------------------------------------------------
    // Step 1: Deploy CauldronToken (MIT)
    // -----------------------------------------------------------------------
    console.log('Step 1: Deploying Magic Internet Token (MIT)...');

    const mitWasm = new Uint8Array(fs.readFileSync(join(buildDir, 'cauldron-token.wasm')));
    console.log('  Loaded cauldron-token.wasm');

    let utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
    console.log(`  Found ${utxos.length} UTXOs`);

    const mitCalldata = encodeMitCalldata(
        1n,                     // generation 1
        'Magic Internet Token', // name
        'MIT',                  // symbol
        nftAddress,             // NFT contract for tax exemption
        wallet.p2tr,            // fee recipient = deployer
    );

    const mitResult = await factory.signDeployment({
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        network: netConfig.network,
        from: wallet.p2tr,
        bytecode: mitWasm,
        calldata: mitCalldata,
        utxos,
        feeRate: 5,
        priorityFee: 330n,
        gasSatFee: 330n,
    });

    await broadcastDeployment(limitedProvider, mitResult);
    const mitAddress = mitResult.contractAddress;
    console.log(`  MIT deployed: ${mitAddress}\n`);

    // Save MIT address
    deployment.contracts.MIT_TOKEN = mitAddress;
    saveDeployment(networkName, deployment);

    // Wait for deployment to confirm
    console.log('  Waiting for confirmation...');
    await sleep(10_000);

    // -----------------------------------------------------------------------
    // Step 2: Mint initial MIT supply
    // -----------------------------------------------------------------------
    console.log('Step 2: Minting initial MIT supply...');
    console.log(`  Amount: ${INITIAL_MIT_SUPPLY / BigInt('1000000000000000000')} MIT`);

    const mitContract = getContract<IOP20Contract>(
        Address.fromString(mitAddress),
        OP_20_ABI,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const mintSim = await mitContract.execute('mint', [
        wallet.address,
        INITIAL_MIT_SUPPLY,
    ]);

    if (mintSim.revert) {
        console.error(`  Mint reverted: ${mintSim.revert}`);
        process.exit(1);
    }

    const mintTxParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 100_000n,
        feeRate: 5,
        network: netConfig.network,
    };

    const mintReceipt = await mintSim.sendTransaction(mintTxParams);
    console.log(`  Mint TX: ${mintReceipt.transactionId.slice(0, 16)}...\n`);

    await sleep(5_000);

    // -----------------------------------------------------------------------
    // Step 3: Approve NativeSwap for MIT
    // -----------------------------------------------------------------------
    console.log('Step 3: Approving NativeSwap for MIT...');

    const nativeSwapAddr = Address.fromString(netConfig.nativeSwapAddress);

    const approveSim = await mitContract.approve(nativeSwapAddr, INITIAL_MIT_SUPPLY);

    if (approveSim.revert) {
        console.error(`  Approve reverted: ${approveSim.revert}`);
        process.exit(1);
    }

    const approveReceipt = await approveSim.sendTransaction(mintTxParams);
    console.log(`  Approve TX: ${approveReceipt.transactionId.slice(0, 16)}...\n`);

    await sleep(5_000);

    // -----------------------------------------------------------------------
    // Step 4: Create NativeSwap pool for MIT
    // -----------------------------------------------------------------------
    console.log('Step 4: Creating NativeSwap pool...');

    const nativeSwap = getContract<INativeSwapContract>(
        nativeSwapAddr,
        NativeSwapAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // receiver = wallet's compressed public key (33 bytes)
    const receiverPubKey = Buffer.from(wallet.keypair.publicKey);
    const receiverAddress = wallet.p2tr;

    const createPoolSim = await nativeSwap.createPool(
        Address.fromString(mitAddress),
        FLOOR_PRICE,
        INITIAL_MIT_SUPPLY,
        receiverPubKey,
        receiverAddress,
        ANTI_BOT_BLOCKS,
        ANTI_BOT_MAX_TOKENS,
        MAX_RESERVES_5_BLOCKS_PERCENT,
        POOL_TYPE,
        0n,  // amplification (0 for standard AMM)
        0n,  // pegStalenessThreshold (0 for non-pegged)
    );

    if (createPoolSim.revert) {
        console.error(`  createPool reverted: ${createPoolSim.revert}`);
        process.exit(1);
    }

    const poolTxParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 200_000n,
        feeRate: 5,
        network: netConfig.network,
    };

    const poolReceipt = await createPoolSim.sendTransaction(poolTxParams);
    console.log(`  Pool created TX: ${poolReceipt.transactionId.slice(0, 16)}...\n`);

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    console.log('Liquidity Setup Complete!\n');
    console.log(`  MIT Token:    ${mitAddress}`);
    console.log(`  NFT Contract: ${nftAddress}`);
    console.log(`  NativeSwap:   ${netConfig.nativeSwapAddress}`);
    console.log(`  Initial MIT:  ${INITIAL_MIT_SUPPLY / BigInt('1000000000000000000')} MIT`);
    console.log(`  Pool Type:    Standard AMM`);
    console.log(`\nDeployment file updated at deployments/${networkName}.json`);

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Liquidity setup failed:', err);
    process.exit(1);
});
