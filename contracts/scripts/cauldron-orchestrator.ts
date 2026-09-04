#!/usr/bin/env tsx

/**
 * Cauldron Orchestrator
 *
 * Off-chain watcher that monitors MiFrens NFT minting. When all 777 NFTs
 * have been minted, it:
 *   1. Deploys CauldronToken WASM ("Magic Internet Token" / "MIT")
 *   2. Mints 777 MIT to the deployer
 *   3. Approves NativeSwap to spend MIT
 *   4. Creates a BTC/MIT pool on NativeSwap
 *   5. Calls registry.summonGenesis(mitAddress, poolAddress, name, symbol)
 *
 * This is necessary because cross-contract calls to NativeSwap fail on-chain
 * (see incident INC-mms0dz69). The orchestrator bridges the on-chain NFT
 * trigger to actual token deployment + pool creation off-chain.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/cauldron-orchestrator.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/cauldron-orchestrator.ts --network testnet
 *
 * Environment:
 *   DEPLOYER_MNEMONIC       - BIP39 mnemonic for the deployer wallet
 *   NFT_CONTRACT_ADDRESS    - Deployed MiFrens address (or load from deployments JSON)
 *   REGISTRY_ADDRESS        - Deployed CauldronRegistry address
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
    IOP721Contract,
    INativeSwapContract,
    TransactionParameters,
} from 'opnet';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const MAX_NFT_SUPPLY = 777n;
const MIT_INITIAL_SUPPLY = 777_000_000_000_000_000_000n; // 777 * 10^18
const MIT_FLOOR_PRICE = 100_000n; // Floor price in sats (0.001 BTC)
const POLL_INTERVAL_MS = 10_000; // 10 seconds

const NATIVE_SWAP_ADDRESS = '0xb056ba05448cf4a5468b3e1190b0928443981a93c3aff568467f101e94302422';

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'https://regtest.opnet.org', network: networks.regtest },
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet },
};

function getNetworkName(): string {
    const idx = process.argv.indexOf('--network');
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : 'regtest';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function loadDeploymentAddresses(networkName: string): Record<string, string> {
    const filePath = join(__dirname, `../deployments/${networkName}.json`);
    if (!fs.existsSync(filePath)) {
        console.error(`No deployment file found at ${filePath}`);
        console.error('Run "npm run cauldron:deploy" first.');
        process.exit(1);
    }
    const data = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
    return data.contracts;
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
    await new Promise((r) => setTimeout(r, 2000));
    await provider.broadcastTransaction(result.transaction[1], false);
}

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
}

function encodeCauldronTokenCalldata(
    generation: bigint,
    name: string,
    symbol: string,
    nftContract: string,
    feeRecipient: string,
): Uint8Array {
    const writer = new BinaryWriter();
    writer.writeU256(generation);
    writer.writeStringWithLength(name);
    writer.writeStringWithLength(symbol);
    writer.writeAddress(Address.fromString(nftContract));
    writer.writeAddress(Address.fromString(feeRecipient));
    return writer.getBuffer();
}

// ---------------------------------------------------------------------------
// Main orchestrator
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const networkName = getNetworkName();
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

    console.log('Cauldron Orchestrator');
    console.log(`Network: ${networkName}`);
    console.log(`RPC: ${netConfig.rpcUrl}`);
    console.log(`Polling interval: ${POLL_INTERVAL_MS / 1000}s\n`);

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer: ${wallet.p2tr}\n`);

    // --- Load deployment addresses ---
    const addresses = loadDeploymentAddresses(networkName);
    const nftAddress = process.env.NFT_CONTRACT_ADDRESS || addresses.MIFREN_NFT;
    const registryAddress = process.env.REGISTRY_ADDRESS || addresses.CAULDRON_REGISTRY;

    if (!nftAddress || !registryAddress) {
        console.error('Missing NFT or Registry address. Check deployments file or env vars.');
        process.exit(1);
    }

    console.log(`NFT Contract: ${nftAddress}`);
    console.log(`Registry: ${registryAddress}`);
    console.log(`NativeSwap: ${NATIVE_SWAP_ADDRESS}\n`);

    // --- Setup providers ---
    const rpcProvider = new JSONRpcProvider({
        url: netConfig.rpcUrl,
        network: netConfig.network,
    });
    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);

    // --- Poll totalMinted() ---
    console.log('Polling totalMinted()...\n');

    while (true) {
        try {
            const nftContract = getContract<IOP721Contract>(
                Address.fromString(nftAddress),
                OP_20_ABI, // OP721 extends OP20; totalMinted is custom but readable
                rpcProvider,
                netConfig.network,
                wallet.address,
            );

            const totalMintedResult = await nftContract.execute('totalMinted', []);

            if (totalMintedResult.revert) {
                console.log(`  totalMinted() reverted: ${totalMintedResult.revert}`);
                await sleep(POLL_INTERVAL_MS);
                continue;
            }

            const totalMinted = totalMintedResult.decoded?.[0] as bigint ?? 0n;
            console.log(`  totalMinted: ${totalMinted} / ${MAX_NFT_SUPPLY}`);

            if (totalMinted >= MAX_NFT_SUPPLY) {
                console.log('\n  777 NFTs minted! Initiating Cauldron summoning...\n');
                break;
            }
        } catch (err) {
            console.log(`  Poll error: ${err instanceof Error ? err.message : String(err)}`);
        }

        await sleep(POLL_INTERVAL_MS);
    }

    // =======================================================================
    // Phase 1: Deploy CauldronToken ("Magic Internet Token" / "MIT")
    // =======================================================================
    console.log('Phase 1: Deploying Magic Internet Token (MIT)...');

    const tokenWasmPath = join(__dirname, '../build/cauldron-token.wasm');
    if (!fs.existsSync(tokenWasmPath)) {
        console.error(`CauldronToken WASM not found at ${tokenWasmPath}`);
        console.error('Run "npm run cauldron:build" first.');
        process.exit(1);
    }

    const tokenWasm = new Uint8Array(fs.readFileSync(tokenWasmPath));
    const factory = new TransactionFactory();

    let utxos = await fetchUtxos(limitedProvider, wallet.p2tr);

    const tokenCalldata = encodeCauldronTokenCalldata(
        1n,                       // generation 1
        'Magic Internet Token',   // name
        'MIT',                    // symbol
        nftAddress,               // NFT contract
        wallet.p2tr,              // fee recipient = deployer
    );

    const deployResult = await factory.signDeployment({
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        network: netConfig.network,
        from: wallet.p2tr,
        bytecode: tokenWasm,
        calldata: tokenCalldata,
        utxos,
        feeRate: 5,
        priorityFee: 330n,
        gasSatFee: 330n,
    });

    await broadcastDeployment(limitedProvider, deployResult);
    const mitAddress = deployResult.contractAddress;
    console.log(`  MIT deployed: ${mitAddress}`);
    console.log(`  Funding TX: ${deployResult.transaction[0].slice(0, 20)}...`);
    console.log(`  Deploy TX: ${deployResult.transaction[1].slice(0, 20)}...`);

    // Wait for deployment to confirm
    console.log('  Waiting for deployment confirmation...');
    await sleep(15000);

    // =======================================================================
    // Phase 2: Mint 777 MIT to deployer
    // =======================================================================
    console.log('\nPhase 2: Minting 777 MIT to deployer...');

    const mitContract = getContract<IOP20Contract>(
        Address.fromString(mitAddress),
        OP_20_ABI,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const mintSim = await mitContract.execute('mint', [
        Address.fromString(wallet.p2tr),
        MIT_INITIAL_SUPPLY,
    ]);

    if (mintSim.revert) {
        console.error(`  Mint simulation failed: ${mintSim.revert}`);
        process.exit(1);
    }

    utxos = deployResult.utxos.length > 0
        ? deployResult.utxos
        : await fetchUtxos(limitedProvider, wallet.p2tr);

    const txParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 100_000n,
        feeRate: 5,
        network: netConfig.network,
    };

    const mintReceipt = await mintSim.sendTransaction(txParams);
    console.log(`  Mint TX: ${mintReceipt.transactionId}`);

    await sleep(10000);

    // =======================================================================
    // Phase 3: Approve NativeSwap for MIT
    // =======================================================================
    console.log('\nPhase 3: Approving NativeSwap for MIT...');

    // IMPORTANT: Approve and pool creation must be in separate blocks
    // (see OPNet troubleshooting: approve + pool in same block fails)
    const approveSim = await mitContract.approve(
        Address.fromString(NATIVE_SWAP_ADDRESS),
        MIT_INITIAL_SUPPLY,
    );

    if (approveSim.revert) {
        console.error(`  Approve simulation failed: ${approveSim.revert}`);
        process.exit(1);
    }

    const approveReceipt = await approveSim.sendTransaction(txParams);
    console.log(`  Approve TX: ${approveReceipt.transactionId}`);

    // Wait for approve to be in a confirmed block before creating pool
    console.log('  Waiting for approval confirmation (must be separate block from pool creation)...');
    await sleep(15000);

    // =======================================================================
    // Phase 4: Create NativeSwap BTC/MIT pool
    // =======================================================================
    console.log('\nPhase 4: Creating NativeSwap BTC/MIT pool...');

    const nativeSwap = getContract<INativeSwapContract>(
        Address.fromString(NATIVE_SWAP_ADDRESS),
        NativeSwapAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const createPoolSim = await nativeSwap.createPool(
        Address.fromString(mitAddress),      // token
        MIT_FLOOR_PRICE,                      // floorPrice (sats)
        MIT_INITIAL_SUPPLY,                   // initialLiquidity (tokens)
        wallet.publicKey,                     // receiver pubkey
        wallet.p2tr,                          // receiver address
        0n,                                   // antiBotEnabledFor (0 = disabled)
        0n,                                   // antiBotMaximumTokensPerReservation
        0n,                                   // maxReservesIn5BlocksPercent (0 = no limit)
        0n,                                   // poolType (0 = standard)
        0n,                                   // amplification
        0n,                                   // pegStalenessThreshold
    );

    if (createPoolSim.revert) {
        console.error(`  createPool simulation failed: ${createPoolSim.revert}`);
        process.exit(1);
    }

    console.log(`  Pool simulation gas: ${createPoolSim.estimatedSatGas}`);

    const poolReceipt = await createPoolSim.sendTransaction(txParams);
    console.log(`  createPool TX: ${poolReceipt.transactionId}`);

    await sleep(10000);

    // =======================================================================
    // Phase 5: Call registry.summonGenesis()
    // =======================================================================
    console.log('\nPhase 5: Calling summonGenesis on CauldronRegistry...');

    const registry = getContract<IOP20Contract>(
        Address.fromString(registryAddress),
        OP_20_ABI,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const summonSim = await registry.execute('summonGenesis', [
        Address.fromString(mitAddress),
        Address.fromString(NATIVE_SWAP_ADDRESS),
        'Magic Internet Token',
        'MIT',
    ]);

    if (summonSim.revert) {
        console.error(`  summonGenesis simulation failed: ${summonSim.revert}`);
        process.exit(1);
    }

    const summonReceipt = await summonSim.sendTransaction(txParams);
    console.log(`  summonGenesis TX: ${summonReceipt.transactionId}`);

    // =======================================================================
    // Summary
    // =======================================================================
    console.log('\n========================================');
    console.log('  Cauldron Summoning Complete!');
    console.log('========================================');
    console.log(`  Token: Magic Internet Token (MIT)`);
    console.log(`  MIT Address: ${mitAddress}`);
    console.log(`  NativeSwap Pool: ${NATIVE_SWAP_ADDRESS}`);
    console.log(`  Generation: 1`);
    console.log(`  Initial Supply: 777 MIT`);
    console.log(`  Floor Price: ${MIT_FLOOR_PRICE} sats`);
    console.log('========================================\n');

    // Save orchestrator results
    const resultsPath = join(__dirname, `../deployments/${getNetworkName()}-mit.json`);
    fs.writeFileSync(resultsPath, JSON.stringify({
        token: 'Magic Internet Token',
        symbol: 'MIT',
        generation: 1,
        mitAddress,
        nativeSwapPool: NATIVE_SWAP_ADDRESS,
        deployedAt: new Date().toISOString(),
        transactions: {
            deploy: deployResult.transaction[1].slice(0, 64),
            mint: mintReceipt.transactionId,
            approve: approveReceipt.transactionId,
            createPool: poolReceipt.transactionId,
            summonGenesis: summonReceipt.transactionId,
        },
    }, null, 2));
    console.log(`Results saved to ${resultsPath}`);

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Orchestrator failed:', err);
    process.exit(1);
});
