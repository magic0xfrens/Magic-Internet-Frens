#!/usr/bin/env tsx

/**
 * test-mint-all-traits.ts — Mint 83 NFTs through FrenForge (one per trait)
 *
 * Tests the full mint flow: FrenForge.mint(traitKey, packedData) which:
 *   1. Verifies the Merkle proof
 *   2. Lazily inscribes the trait on-chain (if not already stored)
 *   3. Cross-contract calls MiFrens.mintFor(sender) → returns tokenId
 *   4. Verifies BTC payment to treasury
 *
 * After all 83 mints, every trait should be inscribed on-chain and
 * tokenURI should render full SVGs (body + face + item).
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-mint-all-traits.ts --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-mint-all-traits.ts --network testnet --dry-run
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-mint-all-traits.ts --network testnet --start 10
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-mint-all-traits.ts --network testnet --delay 5000
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
import { getContract, JSONRpcProvider, TransactionOutputFlags } from 'opnet';
import type { IContract, TransactionParameters } from 'opnet';

import { FrenForgeAbi } from '../abis/FrenForge.abi';
import { MiFrensAbi } from '../abis/MiFrens.abi';
import {
    COMPRESSED_TRAITS,
    type CompressedTrait,
} from '../../compressed-traits/compressed-traits';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const MERKLE_PROOF_DEPTH = 7;
const MINT_PRICE_SATS = 144_000;

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'https://regtest.opnet.org', network: networks.regtest },
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet },
    mainnet: { rpcUrl: 'https://mainnet.opnet.org', network: networks.bitcoin },
};

function getArg(flag: string): string | undefined {
    const idx = process.argv.indexOf(flag);
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : undefined;
}

function hasFlag(flag: string): boolean {
    return process.argv.includes(flag);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function hexToBytes(hex: string): Uint8Array {
    const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
    const bytes = new Uint8Array(clean.length / 2);
    for (let i = 0; i < clean.length; i += 2) {
        bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
    }
    return bytes;
}

/**
 * Pack trait data for FrenForge.mint() — same format as inscribeTrait.
 * Format: leafIndex(u32) + proofLen(u32) + proof[7](7×32 bytes) + dataLen(u32) + data[N]
 */
function packMintData(trait: CompressedTrait): Uint8Array {
    const traitBlob = hexToBytes(trait.blob);
    const totalSize = 4 + 4 + 32 * MERKLE_PROOF_DEPTH + 4 + traitBlob.length;
    const buf = new Uint8Array(totalSize);
    const view = new DataView(buf.buffer);
    let offset = 0;

    view.setUint32(offset, trait.leafIndex, false);
    offset += 4;

    view.setUint32(offset, MERKLE_PROOF_DEPTH, false);
    offset += 4;

    for (let i = 0; i < MERKLE_PROOF_DEPTH; i++) {
        const hash = hexToBytes(trait.proof[i]);
        buf.set(hash, offset);
        offset += 32;
    }

    view.setUint32(offset, traitBlob.length, false);
    offset += 4;
    buf.set(traitBlob, offset);

    return buf;
}

async function resolveContractAddress(
    provider: JSONRpcProvider,
    contractAddr: string,
): Promise<Address> {
    const addr = await provider.getPublicKeyInfo(contractAddr, true);
    if (!addr) {
        throw new Error(`Could not resolve public key for ${contractAddr}`);
    }
    return addr;
}

type ContractCall = (...args: unknown[]) => Promise<{
    revert?: string;
    decoded?: unknown[];
    properties?: Record<string, unknown>;
    sendTransaction: (params: TransactionParameters) => Promise<{
        transactionId: string;
    }>;
}>;

function method(contract: IContract, name: string): ContractCall {
    return (contract as unknown as Record<string, ContractCall>)[name];
}

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const networkName = getArg('--network') ?? 'regtest';
    const dryRun = hasFlag('--dry-run');
    const startFrom = parseInt(getArg('--start') ?? '0', 10);
    const txDelay = parseInt(getArg('--delay') ?? '3000', 10);

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

    // Load deployment
    const deploymentPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment found at ${deploymentPath}. Run deploy-all.ts first.`);
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const forgeAddress: string = deployment.contracts.FRENFORGE;
    const nftAddress: string = deployment.contracts.MIFRENS;
    const treasuryAddress: string = deployment.deployer;

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — Test Mint All 83 Traits via FrenForge');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:       ${networkName}`);
    console.log(`  FrenForge:     ${forgeAddress}`);
    console.log(`  MiFrens:       ${nftAddress}`);
    console.log(`  Treasury:      ${treasuryAddress}`);
    console.log(`  Total traits:  ${COMPRESSED_TRAITS.length}`);
    console.log(`  Mint price:    ${MINT_PRICE_SATS} sats (${MINT_PRICE_SATS / 1e8} BTC)`);
    console.log(`  Start from:    ${startFrom}`);
    console.log(`  TX delay:      ${txDelay}ms`);
    console.log(`  Dry run:       ${dryRun}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Minter: ${wallet.p2tr}\n`);

    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    const txParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: BigInt(MINT_PRICE_SATS) + 300_000n,
        feeRate: 5,
        priorityFee: 200n,
        network: netConfig.network,
        extraOutputs: [
            {
                address: treasuryAddress,
                value: BigInt(MINT_PRICE_SATS),
            },
        ],
    };

    // Resolve contracts
    console.log('Resolving contracts...');
    const forgeAddr = await resolveContractAddress(rpcProvider, forgeAddress);
    const nftAddr = await resolveContractAddress(rpcProvider, nftAddress);
    console.log('  FrenForge resolved');
    console.log('  MiFrens resolved\n');

    const forgeContract = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const nftContract = getContract<IContract>(
        nftAddr,
        MiFrensAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // Check current state
    console.log('Checking current state...');
    const mintedResult = await method(nftContract, 'totalMinted')();
    const rawMinted = mintedResult.properties?.count ?? mintedResult.decoded?.[0] ?? 0;
    const nextTokenId = Number(BigInt(rawMinted as string | bigint | number));
    const totalMinted = Math.max(0, nextTokenId - 1);
    console.log(`  NFTs minted:     ${totalMinted}`);

    const statsResult = await method(forgeContract, 'getInscriptionStats')();
    const totalInscribed = Number(statsResult.properties?.totalInscribed ?? statsResult.decoded?.[0] ?? 0);
    const paletteInscribed = Number(statsResult.properties?.paletteInscribed ?? statsResult.decoded?.[1] ?? 0);
    console.log(`  Traits inscribed: ${totalInscribed} / ${COMPRESSED_TRAITS.length}`);
    console.log(`  Palette inscribed: ${paletteInscribed ? 'YES' : 'NO'}`);

    if (!paletteInscribed) {
        console.error('\n  ERROR: Palette not inscribed! Run inscribe-palette.ts first.');
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
        process.exit(1);
    }
    console.log('');

    // Build the list of traits to mint (one per trait, sequentially)
    const traitsToMint = COMPRESSED_TRAITS.slice(startFrom);

    if (dryRun) {
        console.log('DRY RUN — would mint:');
        for (let i = 0; i < traitsToMint.length; i++) {
            const t = traitsToMint[i];
            const blobBytes = t.blob.length / 2;
            console.log(`  [${i + 1}/${traitsToMint.length}] traitKey=${t.traitKey} label="${t.label}" (${blobBytes} bytes)`);
        }
        console.log(`\nTotal: ${traitsToMint.length} mints`);
        console.log(`Total BTC: ${(traitsToMint.length * MINT_PRICE_SATS) / 1e8} BTC`);
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
        return;
    }

    // Mint each trait
    let successCount = 0;
    let failCount = 0;
    const results: { traitKey: number; label: string; tokenId: string; txHash: string }[] = [];
    const failures: { traitKey: number; label: string; error: string }[] = [];

    for (let i = 0; i < traitsToMint.length; i++) {
        const trait = traitsToMint[i];
        const globalIdx = startFrom + i;
        const blobBytes = trait.blob.length / 2;

        console.log(`\n[${globalIdx + 1}/${COMPRESSED_TRAITS.length}] Minting trait "${trait.label}" (key=${trait.traitKey}, ${blobBytes} bytes)...`);

        try {
            const packedData = packMintData(trait);

            // Set treasury payment output for simulation
            (forgeContract as IContract & { setTransactionDetails: (d: unknown) => void }).setTransactionDetails({
                inputs: [],
                outputs: [
                    {
                        to: treasuryAddress,
                        value: BigInt(MINT_PRICE_SATS),
                        index: 1,
                        flags: TransactionOutputFlags.hasTo,
                    },
                ],
            });

            // Simulate FrenForge.mint(traitKey, packedData)
            const sim = await method(forgeContract, 'mint')(
                BigInt(trait.traitKey),
                packedData,
            );

            if (sim.revert) {
                console.error(`  REVERT: ${sim.revert}`);
                failCount++;
                failures.push({ traitKey: trait.traitKey, label: trait.label, error: sim.revert });
                continue;
            }

            const receipt = await sim.sendTransaction(txParams);

            // Simulation always returns the same tokenId because on-chain state
            // hasn't confirmed yet. Use sequential expected ID instead.
            const expectedTokenId = nextTokenId + successCount;
            console.log(`  Token #${expectedTokenId} minted — TX: ${receipt.transactionId.slice(0, 24)}...`);

            results.push({
                traitKey: trait.traitKey,
                label: trait.label,
                tokenId: expectedTokenId.toString(),
                txHash: receipt.transactionId,
            });
            successCount++;

            // Delay between mints
            if (i < traitsToMint.length - 1) {
                // Longer pause every 10 mints for UTXO settlement
                if ((i + 1) % 10 === 0) {
                    console.log(`\n  --- Batch ${Math.floor((i + 1) / 10)} complete. Waiting 30s for UTXO settlement... ---`);
                    await sleep(30_000);
                } else {
                    await sleep(txDelay);
                }
            }
        } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            console.error(`  ERROR: ${msg.slice(0, 200)}`);
            failCount++;
            failures.push({ traitKey: trait.traitKey, label: trait.label, error: msg.slice(0, 200) });

            // If UTXO error, wait longer
            if (msg.includes('UTXO') || msg.includes('insufficient') || msg.includes('not found')) {
                console.log('  Waiting 60s for UTXO availability...');
                await sleep(60_000);
            }
        }
    }

    // --- Final stats ---
    console.log('\n\n═══════════════════════════════════════════════════════════');
    console.log('  Test Mint Results');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Succeeded:  ${successCount} / ${traitsToMint.length}`);
    console.log(`  Failed:     ${failCount}`);
    console.log(`  BTC spent:  ${(successCount * MINT_PRICE_SATS) / 1e8} BTC`);

    // Verify inscription stats after minting
    console.log('\n  Post-mint verification...');
    const postStats = await method(forgeContract, 'getInscriptionStats')();
    const postInscribed = Number(postStats.properties?.totalInscribed ?? postStats.decoded?.[0] ?? 0);
    console.log(`  Traits inscribed: ${postInscribed} / ${COMPRESSED_TRAITS.length}`);

    if (postInscribed >= COMPRESSED_TRAITS.length) {
        console.log('\n  ALL TRAITS INSCRIBED — Collection complete!');
    } else {
        console.log(`\n  ${COMPRESSED_TRAITS.length - postInscribed} traits still missing.`);
    }

    // Show failures
    if (failures.length > 0) {
        console.log('\n  Failed mints:');
        for (const f of failures) {
            console.log(`    traitKey=${f.traitKey} (${f.label}): ${f.error}`);
        }
        console.log(`\n  Re-run with --start ${startFrom + successCount} to retry from where it left off.`);
    }

    console.log('\n═══════════════════════════════════════════════════════════\n');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Test mint failed:', err);
    process.exit(1);
});
