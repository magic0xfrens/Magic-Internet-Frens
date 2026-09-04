#!/usr/bin/env tsx

/**
 * configure-contracts.ts — Part 2: Link & configure deployed contracts
 *
 * Reads addresses from deployments/<network>.json (written by deploy-all.ts),
 * resolves their on-chain public keys, then runs all configuration transactions:
 *
 *   1. NFT.addCauldron(forge)           — whitelist FrenForge for mintFor
 *   2. FrenForge.setNFTContract(nft)   — forge knows which NFT to query
 *   3. NFT.setFrenForge(forge)         — tokenURI delegates to FrenForge
 *   4. FrenForge.setMerkleRoot(root)   — trait Merkle root
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/configure-contracts.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/configure-contracts.ts --network testnet
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
import { getContract, JSONRpcProvider, ABIDataTypes, BitcoinAbiTypes } from 'opnet';
import type { IContract, TransactionParameters } from 'opnet';

import { MiFrensAbi } from '../abis/MiFrens.abi';
import { FrenForgeAbi } from '../abis/FrenForge.abi';

// changeMetadata is defined in the OP721 base class with @method() (no input types),
// but the actual calldata expects 4 strings. The build generates the ABI for OP721
// separately, so we must append it here for the proxy to create the method.
const MiFrensAbiWithMetadata = [
    ...MiFrensAbi,
    {
        name: 'changeMetadata',
        inputs: [
            { name: 'icon', type: ABIDataTypes.STRING },
            { name: 'banner', type: ABIDataTypes.STRING },
            { name: 'description', type: ABIDataTypes.STRING },
            { name: 'website', type: ABIDataTypes.STRING },
        ],
        outputs: [],
        type: BitcoinAbiTypes.Function,
    },
];

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Delay between transactions to let them propagate */
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

function getStartStep(): number {
    const idx = process.argv.indexOf('--from-step');
    return idx !== -1 && process.argv[idx + 1] ? parseInt(process.argv[idx + 1]) : 1;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
}

function hexToU256BigInt(hex: string): bigint {
    return BigInt(hex);
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

/** Typed helper — call a method on an opnet contract by name */
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
    const nftAddress: string = deployment.contracts.MIFRENS;
    const forgeAddress: string = deployment.contracts.FRENFORGE;
    const merkleRoot: string = deployment.merkleRoot;
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — Part 2: Configure Contracts');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:      ${networkName}`);
    console.log(`  NFT:          ${nftAddress}`);
    console.log(`  FrenForge:     ${forgeAddress}`);
    console.log(`  Merkle root:  ${merkleRoot}`);
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

    // ===================================================================
    // Resolve on-chain addresses
    // ===================================================================
    console.log('Resolving contract public keys...');
    const nftAddr = await resolveContractAddress(rpcProvider, nftAddress);
    console.log(`  NFT resolved`);
    const forgeAddr = await resolveContractAddress(rpcProvider, forgeAddress);
    console.log(`  FrenForge resolved\n`);

    const nftContract = getContract<IContract>(
        nftAddr,
        MiFrensAbiWithMetadata,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // Monkey-patch: on-chain OP721 declares @method('changeMetadata') with no input
    // types, so its selector is "changeMetadata()" = 0x4b1dd8fb. The ABI lists 4
    // string inputs for encoding. Override getSelector to force the no-args selector.
    const origGetSelector = (nftContract as any).getSelector.bind(nftContract);
    (nftContract as any).getSelector = (element: any) => {
        if (element.name === 'changeMetadata') return 'changeMetadata()';
        return origGetSelector(element);
    };

    const forgeContract = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const startStep = getStartStep();

    // ===================================================================
    // STEP 1: NFT.addCauldron(FrenForge)
    // ===================================================================
    if (startStep <= 1) {
    console.log('STEP 1: Whitelisting FrenForge on NFT (addCauldron)...');

    const addCauldronSim = await method(nftContract, 'addCauldron')(forgeAddr);
    if (addCauldronSim.revert) {
        console.error(`  addCauldron reverted: ${addCauldronSim.revert}`);
        process.exit(1);
    }
    const addCauldronReceipt = await addCauldronSim.sendTransaction(txParams);
    console.log(`  TX: ${addCauldronReceipt.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);
    } else { console.log('STEP 1: Skipped (--from-step)'); }

    // ===================================================================
    // STEP 2: FrenForge.setNFTContract(nft)
    // ===================================================================
    if (startStep <= 2) {
    console.log('\nSTEP 2: Setting NFT contract on FrenForge...');

    const setNftSim = await method(forgeContract, 'setNFTContract')(nftAddr);
    if (setNftSim.revert) {
        console.error(`  setNFTContract reverted: ${setNftSim.revert}`);
        process.exit(1);
    }
    const setNftReceipt = await setNftSim.sendTransaction(txParams);
    console.log(`  TX: ${setNftReceipt.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);
    } else { console.log('STEP 2: Skipped (--from-step)'); }

    // ===================================================================
    // STEP 3: NFT.setFrenForge(FrenForge)
    // ===================================================================
    if (startStep <= 3) {
    console.log('\nSTEP 3: Setting FrenForge on NFT (setFrenForge)...');

    const setFrenForgeSim = await method(nftContract, 'setFrenForge')(forgeAddr);
    if (setFrenForgeSim.revert) {
        console.error(`  setFrenForge reverted: ${setFrenForgeSim.revert}`);
        process.exit(1);
    }
    const setFrenForgeReceipt = await setFrenForgeSim.sendTransaction(txParams);
    console.log(`  TX: ${setFrenForgeReceipt.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);
    } else { console.log('STEP 3: Skipped (--from-step)'); }

    // ===================================================================
    // STEP 4: FrenForge.setMerkleRoot(root)
    // ===================================================================
    console.log('\nSTEP 4: Setting Merkle root on FrenForge...');

    const setRootSim = await method(forgeContract, 'setMerkleRoot')(
        hexToU256BigInt(merkleRoot),
    );
    if (setRootSim.revert) {
        console.error(`  setMerkleRoot reverted: ${setRootSim.revert}`);
        process.exit(1);
    }
    const setRootReceipt = await setRootSim.sendTransaction(txParams);
    console.log(`  TX: ${setRootReceipt.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);

    // ===================================================================
    // STEP 5: FrenForge.setTreasury(treasuryAddress)
    // ===================================================================
    console.log('\nSTEP 5: Setting treasury address on FrenForge...');

    // Resolve the deployer/treasury wallet address for on-chain storage.
    // _verifyMintPayment uses output.hasTo + output.to comparison.
    const treasuryAddr = wallet.p2tr;
    const treasuryResolved = await resolveContractAddress(rpcProvider, treasuryAddr);
    console.log(`  Treasury:     ${treasuryAddr}`);

    const setTreasurySim = await method(forgeContract, 'setTreasury')(
        treasuryResolved,
    );
    if (setTreasurySim.revert) {
        console.error(`  setTreasury reverted: ${setTreasurySim.revert}`);
        process.exit(1);
    }
    const setTreasuryReceipt = await setTreasurySim.sendTransaction(txParams);
    console.log(`  TX: ${setTreasuryReceipt.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);

    // ===================================================================
    // STEP 6: NFT.changeMetadata(icon, banner, description, website)
    // ===================================================================
    console.log('\nSTEP 6: Setting collection metadata (icon, banner, description, website)...');

    const COLLECTION_ICON = 'https://www.mifrens.xyz/mifrens-logo.svg';
    const COLLECTION_BANNER = 'https://www.mifrens.xyz/mifrens-banner.svg';
    const COLLECTION_DESC = 'Magic Internet Frens — 777 Unique Frens living on Bitcoin L1. Collect, trade, and unlock DeFi powers through the Cauldron.';
    const COLLECTION_WEBSITE = 'https://www.mifrens.xyz';

    const changeMetaSim = await method(nftContract, 'changeMetadata')(
        COLLECTION_ICON,
        COLLECTION_BANNER,
        COLLECTION_DESC,
        COLLECTION_WEBSITE,
    );
    if (changeMetaSim.revert) {
        console.error(`  changeMetadata reverted: ${changeMetaSim.revert}`);
        console.error('  (non-fatal — metadata can be set later via set-metadata.ts)');
    } else {
        const changeMetaReceipt = await changeMetaSim.sendTransaction(txParams);
        console.log(`  TX: ${changeMetaReceipt.transactionId.slice(0, 32)}...`);
    }

    // ===================================================================
    // STEP 7: FrenForge.setTreasuryScriptHash(sha256(bech32_address))
    // ===================================================================
    console.log('\nSTEP 7: Setting treasury address hash on FrenForge...');
    console.log('  (Contract compares sha256(output.to) against this hash during mint)');

    // Compute sha256 of the treasury bech32 address STRING.
    // During simulation, output.to = the bech32 string from setTransactionDetails.
    // The contract computes sha256(output.to) and compares against this stored hash.
    const { createHash } = await import('crypto');
    const scriptHashBytes = createHash('sha256').update(Buffer.from(treasuryAddr, 'utf8')).digest();
    const scriptHashBigInt = BigInt('0x' + scriptHashBytes.toString('hex'));
    console.log(`  Treasury bech32:      ${treasuryAddr}`);
    console.log(`  sha256(bech32):       0x${scriptHashBytes.toString('hex')}`);

    const setScriptHashSim = await method(forgeContract, 'setTreasuryScriptHash')(
        scriptHashBigInt,
    );
    if (setScriptHashSim.revert) {
        console.error(`  setTreasuryScriptHash reverted: ${setScriptHashSim.revert}`);
        process.exit(1);
    }
    const setScriptHashReceipt = await setScriptHashSim.sendTransaction(txParams);
    console.log(`  TX: ${setScriptHashReceipt.transactionId.slice(0, 32)}...`);
    await sleep(TX_DELAY_MS);

    // ===================================================================
    // Mark as configured
    // ===================================================================
    deployment.configured = true;
    deployment.configuredAt = new Date().toISOString();
    fs.writeFileSync(deploymentPath, JSON.stringify(deployment, null, 2));

    // ===================================================================
    // Summary
    // ===================================================================
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Configuration Complete!');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  NFT:          ${nftAddress}`);
    console.log(`  FrenForge:     ${forgeAddress}`);
    console.log(`  Treasury:     ${wallet.p2tr}`);
    console.log(`  Icon:         ${COLLECTION_ICON}`);
    console.log(`  Website:      ${COLLECTION_WEBSITE}`);
    console.log('═══════════════════════════════════════════════════════════');
    console.log('\nNext Steps:');
    console.log('  1. Mint collection (palette + traits inscribed during each mint)');
    console.log('  2. tokenURI returns on-chain data URI with embedded PNG');
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Configuration failed:', err);
    process.exit(1);
});
