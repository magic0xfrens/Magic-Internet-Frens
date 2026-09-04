#!/usr/bin/env tsx

/**
 * set-metadata.ts — Set collection metadata on the deployed MiFrens NFT contract.
 *
 * Calls changeMetadata(icon, banner, description, website) on the deployed
 * MiFrens contract to set the collection image, banner, description and website
 * that OPWallet and other frontends display.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/set-metadata.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/set-metadata.ts --network testnet
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
// Collection metadata values
// ---------------------------------------------------------------------------

const COLLECTION_ICON = 'https://www.mifrens.xyz/mifrens-logo.svg';
const COLLECTION_BANNER = 'https://www.mifrens.xyz/mifrens-banner.svg';
const COLLECTION_DESCRIPTION = 'Magic Internet Frens — 777 Unique Frens living on Bitcoin L1. Collect, trade, and unlock DeFi powers through the Cauldron.';
const COLLECTION_WEBSITE = 'https://www.mifrens.xyz';

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
    const nftAddress: string = deployment.contracts.MIFRENS;

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — Set Collection Metadata');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:     ${networkName}`);
    console.log(`  NFT:         ${nftAddress}`);
    console.log(`  Icon:        ${COLLECTION_ICON}`);
    console.log(`  Banner:      ${COLLECTION_BANNER}`);
    console.log(`  Description: ${COLLECTION_DESCRIPTION.slice(0, 60)}...`);
    console.log(`  Website:     ${COLLECTION_WEBSITE}`);
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
    console.log('Resolving NFT contract public key...');
    const nftAddr = await resolveContractAddress(rpcProvider, nftAddress);
    console.log('  Resolved\n');

    const nftContract = getContract<IContract>(
        nftAddr,
        MiFrensAbiWithMetadata,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // Monkey-patch: the on-chain OP721 base class declares @method('changeMetadata')
    // with NO input types, so its selector is from "changeMetadata()" = 0x4b1dd8fb.
    // But the ABI correctly lists 4 string inputs for encoding. We override getSelector
    // to force the no-args selector string so the on-chain dispatch matches.
    const origGetSelector = (nftContract as any).getSelector.bind(nftContract);
    (nftContract as any).getSelector = (element: any) => {
        if (element.name === 'changeMetadata') return 'changeMetadata()';
        return origGetSelector(element);
    };

    // Call changeMetadata
    console.log('Calling changeMetadata...');
    const sim = await method(nftContract, 'changeMetadata')(
        COLLECTION_ICON,
        COLLECTION_BANNER,
        COLLECTION_DESCRIPTION,
        COLLECTION_WEBSITE,
    );

    if (sim.revert) {
        console.error(`  changeMetadata reverted: ${sim.revert}`);
        process.exit(1);
    }

    const receipt = await sim.sendTransaction(txParams);
    console.log(`  TX: ${receipt.transactionId}`);

    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Collection Metadata Updated!');
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  OPWallet should now display the collection icon/banner.');
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Set metadata failed:', err);
    process.exit(1);
});
