#!/usr/bin/env tsx

/**
 * mint-reserve.ts — Part 3: Mint 77 treasury reserve tokens at scattered IDs
 *
 * Optimized: 2 transactions total.
 *   reserveBatch(to, 50, ...50 packed traits) + reserveBatch(to, 27, ...27 packed traits)
 *
 * Reserve IDs are scattered across 1-777 (nice/memorable numbers like 21, 55, 111, 222, 333, etc.)
 * Traits are set in the same call — no separate setBatchTraits step needed.
 *
 * Dynamically queries existing on-chain combos to avoid "combo already taken" errors.
 * Gnomes get any available (body, face, item) combo; Wizard Manifestors get body=6, item=4.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-reserve.ts --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-reserve.ts --network testnet --dry-run
 */

import * as fs from 'fs';
import * as crypto from 'crypto';
import { join } from 'path';

import {
    Mnemonic,
    AddressTypes,
    MLDSASecurityLevel,
    Address,
    BinaryWriter,
} from '@btc-vision/transaction';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { CallResult, IContract, TransactionParameters } from 'opnet';

import { MiFrensAbi } from '../abis/MiFrens.abi';

// ---------------------------------------------------------------------------
// Class specs from contract registry
// ---------------------------------------------------------------------------

// _packClassDef(numBodies, numFaces, numItems, ...)
// Class 0 (Wizard):     8 bodies, 12 faces, 5 items
// Class 5 (Gnome):      2 bodies, 12 faces, 3 items
const GNOME_CLASS = 5;
const GNOME_BODIES = 2;
const GNOME_FACES = 12;
const GNOME_ITEMS = 3;  // items 0, 1, 2

const WIZARD_CLASS = 0;
const WIZARD_MANIFEST_BODY = 6;  // "Manifest" body
const WIZARD_MANIFEST_ITEM = 4;  // "Manifest" item
const WIZARD_FACES = 12;

const GNOME_TARGET = 65;
const WIZARD_TARGET = 12;
const TOTAL_RESERVE = GNOME_TARGET + WIZARD_TARGET; // 77

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/**
 * Max tokens per reserveBatch TX.
 * Each token ≈ 40-50M gas (8 storage writes + _mint + event).
 * WASM init ≈ 100-150M gas. With 5M sat budget (~3.3B gas), 50 tokens fits easily.
 */
const MAX_BATCH = 50;
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

function getResumeOffset(): number {
    const idx = process.argv.indexOf('--resume-from');
    return idx !== -1 && process.argv[idx + 1] ? parseInt(process.argv[idx + 1]) : 0;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
}

/**
 * Replicate the Contract proxy's gas-to-satoshi conversion.
 * Formula: (gasUnits × gasPerSat) / 1e12, then +15% buffer, min 297.
 */
function gasToSat(gas: bigint, gasPerSat: bigint): bigint {
    const exactGas = (gas * gasPerSat) / 1000000000000n;
    const finalGas = (exactGas * 100n) / (100n - 15n); // +15% buffer
    return finalGas > 297n ? finalGas : 297n;
}

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
    properties?: Record<string, unknown>;
}>;

function method(contract: IContract, name: string): ContractCall {
    return (contract as unknown as Record<string, ContractCall>)[name];
}

/** Combo key: "classIdx-bodyIdx-faceIdx-itemIdx" */
function comboStr(classIdx: number, bodyIdx: number, faceIdx: number, itemIdx: number): string {
    return `${classIdx}-${bodyIdx}-${faceIdx}-${itemIdx}`;
}

function packTraits(classIdx: number, bodyIdx: number, faceIdx: number, itemIdx: number): bigint {
    return BigInt(classIdx)
        + (BigInt(bodyIdx) << 64n)
        + (BigInt(faceIdx) << 128n)
        + (BigInt(itemIdx) << 192n);
}

/**
 * OPNet selector: SHA256(signature)[0:4] as big-endian u32.
 */
function computeSelector(signature: string): number {
    const hash = crypto.createHash('sha256').update(signature).digest();
    return ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]) >>> 0;
}

/**
 * Build raw calldata for reserveBatch(address, uint256) + N packed u256 values.
 * Selector matches the contract's @method(address, uint256) decorator.
 */
function buildReserveBatchCalldata(
    to: Address,
    count: bigint,
    packedTraits: bigint[],
): Uint8Array {
    const writer = new BinaryWriter();
    writer.writeSelector(computeSelector('reserveBatch(address,uint256)'));
    writer.writeAddress(to);
    writer.writeU256(count);
    for (const packed of packedTraits) {
        writer.writeU256(packed);
    }
    return writer.getBuffer();
}

// ---------------------------------------------------------------------------
// Query existing on-chain combos
// ---------------------------------------------------------------------------

async function fetchTakenCombos(
    nftContract: IContract,
): Promise<Set<string>> {
    const taken = new Set<string>();

    // Get total minted count
    const mintedResult = await method(nftContract, 'totalMinted')();
    if (mintedResult.revert) {
        throw new Error(`totalMinted reverted: ${mintedResult.revert}`);
    }
    const rawMinted = mintedResult.properties?.count ?? mintedResult.decoded?.[0] ?? 0;
    let count: number;
    try {
        count = Number(BigInt(rawMinted as string | bigint | number));
    } catch {
        count = Number(rawMinted) || 0;
    }

    console.log(`  totalMinted: ${count}`);
    if (count === 0) return taken;

    // Query getTokenTraits for each minted token (scan up to count + 100 for gaps)
    const maxId = Math.min(count + 100, 784);
    const BATCH = 10;
    let found = 0;

    for (let start = 1; start <= maxId && found < count; start += BATCH) {
        const ids: number[] = [];
        for (let id = start; id < start + BATCH && id <= maxId; id++) ids.push(id);

        const results = await Promise.allSettled(
            ids.map(async (tokenId) => {
                const r = await method(nftContract, 'getTokenTraits')(BigInt(tokenId));
                if (r.revert) return null;
                return {
                    classIdx: Number(r.properties?.classIdx ?? r.decoded?.[0] ?? 0),
                    bodyIdx: Number(r.properties?.bodyIdx ?? r.decoded?.[1] ?? 0),
                    faceIdx: Number(r.properties?.faceIdx ?? r.decoded?.[2] ?? 0),
                    itemIdx: Number(r.properties?.itemIdx ?? r.decoded?.[3] ?? 0),
                };
            }),
        );

        for (const settled of results) {
            if (settled.status !== 'fulfilled' || !settled.value) continue;
            const { classIdx, bodyIdx, faceIdx, itemIdx } = settled.value;
            taken.add(comboStr(classIdx, bodyIdx, faceIdx, itemIdx));
            found++;
        }

        if (found % 100 === 0 && found > 0) {
            console.log(`    scanned ${found}/${count} tokens...`);
        }
    }

    console.log(`  ${taken.size} unique combos already taken on-chain`);
    return taken;
}

// ---------------------------------------------------------------------------
// Generate non-conflicting reserve traits
// ---------------------------------------------------------------------------

function generateReserveTraits(taken: Set<string>): number[][] {
    const traits: number[][] = [];

    // 1. Gnomes: iterate all possible combos, pick first 65 that are free
    const gnomeCandidates: number[][] = [];
    for (let body = 0; body < GNOME_BODIES; body++) {
        for (let face = 0; face < GNOME_FACES; face++) {
            for (let item = 0; item < GNOME_ITEMS; item++) {
                gnomeCandidates.push([GNOME_CLASS, body, face, item]);
            }
        }
    }
    // Total possible: 2 × 12 × 3 = 72

    let gnomeCount = 0;
    for (const [cls, body, face, item] of gnomeCandidates) {
        if (gnomeCount >= GNOME_TARGET) break;
        const key = comboStr(cls, body, face, item);
        if (!taken.has(key)) {
            traits.push([cls, body, face, item]);
            taken.add(key); // claim it for dedup within reserve
            gnomeCount++;
        }
    }

    if (gnomeCount < GNOME_TARGET) {
        console.warn(`  WARNING: Only ${gnomeCount}/${GNOME_TARGET} free Gnome combos available!`);
    } else {
        console.log(`  Gnome: ${gnomeCount} free combos selected`);
    }

    // 2. Wizard Manifestors: body=6, item=4, all 12 faces
    let wizCount = 0;
    for (let face = 0; face < WIZARD_FACES; face++) {
        if (wizCount >= WIZARD_TARGET) break;
        const key = comboStr(WIZARD_CLASS, WIZARD_MANIFEST_BODY, face, WIZARD_MANIFEST_ITEM);
        if (!taken.has(key)) {
            traits.push([WIZARD_CLASS, WIZARD_MANIFEST_BODY, face, WIZARD_MANIFEST_ITEM]);
            taken.add(key);
            wizCount++;
        }
    }

    // If some Wizard Manifestor faces are taken, try other items with body=6
    if (wizCount < WIZARD_TARGET) {
        console.log(`  Wizard Manifestor: ${wizCount}/${WIZARD_TARGET} with item=4, trying item=3...`);
        for (let face = 0; face < WIZARD_FACES && wizCount < WIZARD_TARGET; face++) {
            const key = comboStr(WIZARD_CLASS, WIZARD_MANIFEST_BODY, face, 3);
            if (!taken.has(key)) {
                traits.push([WIZARD_CLASS, WIZARD_MANIFEST_BODY, face, 3]);
                taken.add(key);
                wizCount++;
            }
        }
    }

    if (wizCount < WIZARD_TARGET) {
        console.warn(`  WARNING: Only ${wizCount}/${WIZARD_TARGET} free Wizard Manifestor combos!`);
    } else {
        console.log(`  Wizard Manifestor: ${wizCount} free combos selected`);
    }

    return traits;
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

    const dryRun = hasFlag('--dry-run');
    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (!mnemonicPhrase) {
        console.error('DEPLOYER_MNEMONIC environment variable is required');
        process.exit(1);
    }

    const deploymentPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment found at ${deploymentPath}`);
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const nftAddress: string = deployment.contracts.MIFRENS;

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MiFrens — Mint Treasury Reserve (Scattered IDs)');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:  ${networkName}`);
    console.log(`  NFT:      ${nftAddress}`);
    console.log(`  Target:   ${GNOME_TARGET} Gnomes + ${WIZARD_TARGET} Wizard Manifestors = ${TOTAL_RESERVE}`);
    console.log(`  Dry run:  ${dryRun}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`Deployer/Treasury: ${wallet.p2tr}\n`);

    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    const txParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 5_000_000n,
        feeRate: 5,
        network: netConfig.network,
    };

    console.log('Resolving NFT contract...');
    const nftAddr = await resolveContractAddress(rpcProvider, nftAddress);
    console.log('  Resolved\n');

    // Create contract for read queries (totalMinted, getTokenTraits)
    const nftContract = getContract<IContract>(
        nftAddr,
        MiFrensAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    // ===================================================================
    // Step 0: Check reserve index (has a previous batch already been minted?)
    // ===================================================================
    try {
        const reserveInfo = await method(nftContract, 'getReserveInfo')();
        if (!reserveInfo.revert) {
            const nextIdx = Number(reserveInfo.properties?.nextReserveIndex ?? reserveInfo.decoded?.[0] ?? 0);
            const totalReserved = Number(reserveInfo.properties?.totalReserved ?? reserveInfo.decoded?.[1] ?? 77);
            console.log(`  Reserve index: ${nextIdx} / ${totalReserved} (${nextIdx} already minted)`);
            if (nextIdx > 0) {
                console.log(`  WARNING: ${nextIdx} reserve tokens already minted. Script will mint the remaining.`);
            }
        }
    } catch {
        console.log('  (getReserveInfo not available)');
    }

    // ===================================================================
    // Step 1: Query all existing on-chain trait combos
    // ===================================================================
    console.log('\nQuerying existing on-chain trait combos...');
    const takenCombos = await fetchTakenCombos(nftContract);

    // ===================================================================
    // Step 2: Generate non-conflicting reserve traits
    // ===================================================================
    console.log('\nGenerating reserve traits (avoiding taken combos)...');
    const reserveTraits = generateReserveTraits(takenCombos);
    const totalReserve = reserveTraits.length;

    console.log(`\n  Total reserve: ${totalReserve} tokens`);
    console.log(`  TXs needed:   ${Math.ceil(totalReserve / MAX_BATCH)}\n`);

    if (totalReserve === 0) {
        console.error('No free reserve combos available!');
        process.exit(1);
    }

    // Print trait summary
    const gnomes = reserveTraits.filter(t => t[0] === GNOME_CLASS);
    const wizards = reserveTraits.filter(t => t[0] === WIZARD_CLASS);
    console.log(`  Gnomes:  ${gnomes.length} (body 0: ${gnomes.filter(t => t[1] === 0).length}, body 1: ${gnomes.filter(t => t[1] === 1).length})`);
    console.log(`  Wizards: ${wizards.length} (body=${WIZARD_MANIFEST_BODY})\n`);

    if (dryRun) {
        console.log('  [DRY RUN] Would mint these traits:');
        for (let i = 0; i < reserveTraits.length; i++) {
            const [cls, body, face, item] = reserveTraits[i];
            console.log(`    #${i}: class=${cls} body=${body} face=${face} item=${item}`);
        }
        console.log('\n  Dry run complete — no transactions sent.');
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
        return;
    }

    // ===================================================================
    // Step 3: reserveBatch() with raw calldata
    // ===================================================================
    const selector = computeSelector('reserveBatch(address,uint256)');
    console.log(`  reserveBatch selector: 0x${selector.toString(16).padStart(8, '0')}`);
    console.log('Minting reserve tokens via reserveBatch(to, count, ...traits)...\n');

    let offset = getResumeOffset();
    let batchNum = 1;

    while (offset < totalReserve) {
        const batchSize = Math.min(totalReserve - offset, MAX_BATCH);

        const packedArgs: bigint[] = [];
        for (let i = 0; i < batchSize; i++) {
            const [classIdx, bodyIdx, faceIdx, itemIdx] = reserveTraits[offset + i];
            packedArgs.push(packTraits(classIdx, bodyIdx, faceIdx, itemIdx));
        }

        const calldata = buildReserveBatchCalldata(wallet.address, BigInt(batchSize), packedArgs);

        console.log(`  Batch ${batchNum}: ${batchSize} tokens (reserve indices ${offset}-${offset + batchSize - 1})`);
        console.log(`    Calldata: ${calldata.length} bytes`);

        const simResult = await rpcProvider.call(nftAddr, calldata, wallet.address);

        if ('error' in simResult && (simResult as { error?: unknown }).error) {
            const errObj = simResult as { error: string };
            console.error(`  RPC error: ${errObj.error}`);
            process.exit(1);
        }

        const callResult = simResult as CallResult;

        if (callResult.revert) {
            console.error(`  REVERTED: ${callResult.revert}`);
            process.exit(1);
        }

        callResult.setCalldata(calldata);
        callResult.to = nftAddress;
        callResult.address = nftAddr;

        // *** Critical: replicate the Contract proxy's gas estimation ***
        // Without this, estimatedSatGas = 0 and the TX has zero gas budget.
        const gasParams = await rpcProvider.gasParameters();
        const gasSat = gasToSat(callResult.estimatedGas || 0n, gasParams.gasPerSat);
        const refundSat = gasToSat(callResult.refundedGas || 0n, gasParams.gasPerSat);
        callResult.setGasEstimation(gasSat, refundSat);
        callResult.setBitcoinFee(gasParams.bitcoin);

        console.log('    Simulation OK');
        console.log(`    estimatedGas: ${callResult.estimatedGas}, satGas: ${gasSat}, gasPerSat: ${gasParams.gasPerSat}`);

        const receipt = await callResult.sendTransaction(txParams);
        console.log(`    TX: ${receipt.transactionId.slice(0, 32)}...`);

        offset += batchSize;
        batchNum++;

        if (offset < totalReserve) {
            console.log(`    Waiting ${TX_DELAY_MS / 1000}s before next batch...`);
            await sleep(TX_DELAY_MS);
        }
    }

    console.log(`\n  Minted ${totalReserve} reserve tokens.\n`);

    // ===================================================================
    // Mark as reserved
    // ===================================================================
    deployment.reserveMinted = true;
    deployment.reserveMintedAt = new Date().toISOString();
    deployment.reserveCount = totalReserve;
    fs.writeFileSync(deploymentPath, JSON.stringify(deployment, null, 2));

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Treasury Reserve Complete!');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Tokens:   ${totalReserve} scattered across 1-777`);
    console.log(`  Gnomes:   ${gnomes.length}`);
    console.log(`  Wizards:  ${wizards.length}`);
    console.log(`  Owner:    ${wallet.p2tr}`);
    console.log(`  TXs used: ${Math.ceil(totalReserve / MAX_BATCH)}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Reserve minting failed:', err);
    process.exit(1);
});
