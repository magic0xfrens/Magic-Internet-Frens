#!/usr/bin/env tsx

/**
 * mint-nft.ts
 *
 * Mint MiFrens NFTs on the Magic Internet Frens protocol (OPNet).
 * Each mint requires a BTC payment of 0.00144 BTC (144,000 sats) to the treasury.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-nft.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-nft.ts --count 10
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-nft.ts --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-nft.ts --all
 *
 * Options:
 *   --count <n>    Mint n NFTs (default: 1)
 *   --all          Mint all remaining NFTs up to 777
 *   --network <n>  Network to use (regtest, testnet)
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
import { getContract, JSONRpcProvider, OP_20_ABI, TransactionOutputFlags } from 'opnet';
import type { IOP721Contract, TransactionParameters } from 'opnet';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const MAX_NFT_SUPPLY = 777n;

/** Mint price in sats: 0.00144 BTC */
const MINT_PRICE_SATS = 144_000;

const RESET = '\x1b[0m';

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'https://regtest.opnet.org', network: networks.regtest },
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet },
};

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

function getNetworkName(): string {
    const idx = process.argv.indexOf('--network');
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : 'regtest';
}

function getMintCount(): number | 'all' {
    if (process.argv.includes('--all')) return 'all';
    const idx = process.argv.indexOf('--count');
    if (idx !== -1 && process.argv[idx + 1]) {
        return Math.max(1, parseInt(process.argv[idx + 1], 10));
    }
    return 1;
}

interface DeploymentData {
    deployer: string;
    mintPriceSats?: number;
    contracts: {
        MIFRENS: string;
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

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
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

    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (!mnemonicPhrase) {
        console.error('DEPLOYER_MNEMONIC environment variable is required');
        process.exit(1);
    }

    const deployment = loadDeployment(networkName);
    const nftAddress = process.env.NFT_CONTRACT_ADDRESS ?? deployment.contracts.MIFRENS;
    const treasuryAddress = deployment.deployer;
    const requestedCount = getMintCount();

    console.log('MiFrens NFT Minter');
    console.log(`Network : ${networkName}`);
    console.log(`Contract: ${nftAddress}`);
    console.log(`Treasury: ${treasuryAddress}`);
    console.log(`Mint price: ${MINT_PRICE_SATS} sats (${MINT_PRICE_SATS / 1e8} BTC)`);
    console.log(`Mint count: ${requestedCount === 'all' ? 'all remaining' : requestedCount}\n`);

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Minter: ${wallet.p2tr}\n`);

    // --- Setup provider ---
    const rpcProvider = new JSONRpcProvider({
        url: netConfig.rpcUrl,
        network: netConfig.network,
    });

    // --- Get NFT contract ---
    const nftContract = getContract<IOP721Contract>(
        Address.fromString(nftAddress),
        OP_20_ABI,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // --- Check current mint count ---
    const totalMintedResult = await nftContract.execute('totalMinted', []);
    const currentMinted = totalMintedResult.decoded?.[0] as bigint ?? 0n;
    console.log(`Currently minted: ${currentMinted} / ${MAX_NFT_SUPPLY}\n`);

    const remaining = Number(MAX_NFT_SUPPLY - currentMinted);
    if (remaining <= 0) {
        console.log('All 777 NFTs already minted!');
        await rpcProvider.close();
        return;
    }

    const count = requestedCount === 'all' ? remaining : Math.min(requestedCount, remaining);
    console.log(`Minting ${count} NFT(s)...\n`);

    let minted = 0;
    for (let i = 0; i < count; i++) {
        const mintNum = Number(currentMinted) + i + 1;
        process.stdout.write(`  [${mintNum}/${MAX_NFT_SUPPLY}] Minting... `);

        try {
            // Tell the contract about the BTC payment output (for simulation)
            nftContract.setTransactionDetails({
                inputs: [],
                outputs: [
                    {
                        to: treasuryAddress,
                        value: BigInt(MINT_PRICE_SATS),
                        index: 1,
                        scriptPubKey: undefined,
                        flags: TransactionOutputFlags.hasTo,
                    },
                ],
            });

            const sim = await nftContract.execute('mintNFT', []);

            if (sim.revert) {
                console.log(`REVERTED: ${sim.revert}`);
                break;
            }

            // Send with matching extraOutputs so the actual BTC tx includes the payment
            const txParams: TransactionParameters = {
                signer: wallet.keypair,
                mldsaSigner: wallet.mldsaKeypair,
                refundTo: wallet.p2tr,
                maximumAllowedSatToSpend: 300_000n,
                feeRate: 5,
                network: netConfig.network,
                extraOutputs: [
                    {
                        address: treasuryAddress,
                        value: BigInt(MINT_PRICE_SATS),
                    },
                ],
            };

            const receipt = await sim.sendTransaction(txParams);
            const tokenId = sim.decoded?.[0] as bigint ?? BigInt(mintNum - 1);

            console.log(
                `Token #${tokenId} minted — ` +
                `TX: ${receipt.transactionId.slice(0, 16)}...`
            );

            minted++;

            // Brief delay between mints to avoid mempool congestion
            if (i < count - 1) {
                await sleep(3000);
            }
        } catch (err) {
            console.log(`ERROR: ${err instanceof Error ? err.message : String(err)}`);
            // Wait and retry on next iteration
            await sleep(5000);
        }
    }

    const totalAfterMint = Number(currentMinted) + minted;
    console.log(`\nMinted ${minted} NFT(s). Total: ${totalAfterMint} / ${MAX_NFT_SUPPLY}`);
    console.log(`BTC sent to treasury: ${(minted * MINT_PRICE_SATS) / 1e8} BTC`);

    if (totalAfterMint >= Number(MAX_NFT_SUPPLY)) {
        console.log('\nAll 777 NFTs minted! CauldronSummonReady event emitted.');
        console.log('Run: npm run cauldron:add-liquidity to deploy MIT token + create MotoSwap pool');
    }

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Mint failed:', err);
    process.exit(1);
});
