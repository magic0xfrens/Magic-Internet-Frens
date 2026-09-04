#!/usr/bin/env tsx

/**
 * mint-collection.ts — Mint the entire MiFrens collection (700 public NFTs)
 *
 * Generates 100 wallets from the deployer mnemonic (indices 1-100), funds each
 * with enough BTC, then each wallet mints 7 NFTs through FrenForge.mint() with
 * Merkle proofs and treasury payment.
 *
 * Phases:
 *   preflight — Check wallet balances, detect stale state, report funding needs
 *   generate  — Derive 100 wallets and display addresses + funding needs
 *   fund      — Send BTC from deployer (index 0) to each child wallet
 *   mint      — Each wallet mints 7 NFTs via FrenForge.mint()
 *   status    — Check overall minting progress
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-collection.ts --phase preflight --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-collection.ts --phase preflight --network testnet --auto-fund
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-collection.ts --phase generate
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-collection.ts --phase fund --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-collection.ts --phase mint --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/mint-collection.ts --phase status --network testnet
 *
 * Options:
 *   --network <n>         Network: regtest, testnet, mainnet (default: regtest)
 *   --phase <p>           Phase: preflight, generate, fund, mint, status
 *   --total <n>           Total NFTs to mint (default: 700). E.g. --total 144
 *   --start-wallet <n>    Resume from wallet index (default: 1)
 *   --concurrency <n>     Parallel minting wallets (default: 5)
 *   --fund-amount <sats>  Sats per wallet (default: auto-calculated)
 *   --auto-fund           (preflight) Auto-fund wallets that need BTC
 */

import * as fs from 'fs';
import { join } from 'path';

import {
    Mnemonic,
    TransactionFactory,
    OPNetLimitedProvider,
    AddressTypes,
    MLDSASecurityLevel,
} from '@btc-vision/transaction';
import type { UTXO } from '@btc-vision/transaction';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider, TransactionOutputFlags } from 'opnet';
import type { IContract } from 'opnet';

import { FrenForgeAbi } from '../abis/FrenForge.abi';
import { MiFrensAbi } from '../abis/MiFrens.abi';
import {
    COMPRESSED_TRAITS,
    type CompressedTrait,
} from '../../compressed-traits/compressed-traits';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_NFT_SUPPLY = 777;
const TREASURY_RESERVE = 77;
const PUBLIC_SUPPLY = MAX_NFT_SUPPLY - TREASURY_RESERVE; // 700
const MINTS_PER_WALLET = 7;
const MERKLE_PROOF_DEPTH = 8;

/** Total mints to target. Override with --total <n> (e.g. --total 144). Default: 700. */
const TOTAL_TARGET = (() => {
    const idx = process.argv.indexOf('--total');
    if (idx !== -1 && process.argv[idx + 1]) {
        return Math.max(1, Math.min(PUBLIC_SUPPLY, parseInt(process.argv[idx + 1], 10)));
    }
    return PUBLIC_SUPPLY;
})();

const TOTAL_WALLETS = Math.ceil(TOTAL_TARGET / MINTS_PER_WALLET);

/** Mint price per NFT in sats. Override via MINT_PRICE_SATS env var. Default: 144,000 (0.00144 BTC). */
const MINT_PRICE_SATS = process.env.MINT_PRICE_SATS ? BigInt(process.env.MINT_PRICE_SATS) : 144_000n;

/** Per-mint overhead for tx fees (actual ~5-10k sats, cap at 30k for safety) */
const FEE_OVERHEAD_PER_MINT = 30_000n;

/** Compute BTC needed per wallet given a mint price */
function calcFundPerWallet(mintPrice: bigint): bigint {
    return BigInt(MINTS_PER_WALLET) * (mintPrice + FEE_OVERHEAD_PER_MINT) + 30_000n;
}

/** State file for resuming */
const STATE_FILE = join(__dirname, '.mint-collection-state.json');

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

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

function getArg(flag: string): string | undefined {
    const idx = process.argv.indexOf(flag);
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : undefined;
}

function getNetworkName(): string {
    return getArg('--network') ?? 'regtest';
}

function getPhase(): string {
    return getArg('--phase') ?? 'status';
}

function getStartWallet(): number {
    const val = getArg('--start-wallet');
    return val ? Math.max(1, parseInt(val, 10)) : 1;
}

function getConcurrency(): number {
    const val = getArg('--concurrency');
    return val ? Math.max(1, Math.min(20, parseInt(val, 10))) : 5;
}

function getFundAmount(): bigint {
    const val = getArg('--fund-amount');
    return val ? BigInt(val) : calcFundPerWallet(MINT_PRICE_SATS);
}


// ---------------------------------------------------------------------------
// State management
// ---------------------------------------------------------------------------

interface MintState {
    network: string;
    funded: number[];          // wallet indices that have been funded
    minted: Record<number, number>;  // walletIndex → number of successful mints
    totalMinted: number;
    lastUpdated: string;
}

function loadState(networkName: string): MintState {
    if (fs.existsSync(STATE_FILE)) {
        const state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf-8')) as MintState;
        if (state.network === networkName) return state;
    }
    return {
        network: networkName,
        funded: [],
        minted: {},
        totalMinted: 0,
        lastUpdated: new Date().toISOString(),
    };
}

function saveState(state: MintState): void {
    state.lastUpdated = new Date().toISOString();
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

// ---------------------------------------------------------------------------
// Deployment data
// ---------------------------------------------------------------------------

interface DeploymentData {
    deployer: string;
    mintPriceSats?: number;
    contracts: {
        MIFRENS: string;
        FRENFORGE: string;
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
}

function hexToBytes(hex: string): Uint8Array {
    const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
    const bytes = new Uint8Array(clean.length / 2);
    for (let i = 0; i < clean.length; i += 2) {
        bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
    }
    return bytes;
}

/**
 * Pack trait data into the BYTES blob expected by FrenForge.mint().
 * Format: leafIndex(u32) + proofLen(u32) + proof[8](8×32 bytes) + dataLen(u32) + data[N]
 */
function packMintData(trait: CompressedTrait): Uint8Array {
    const traitBlob = hexToBytes(trait.blob);

    const totalSize = 4 + 4 + 32 * MERKLE_PROOF_DEPTH + 4 + traitBlob.length;
    const buf = new Uint8Array(totalSize);
    const view = new DataView(buf.buffer);
    let offset = 0;

    // leafIndex (u32 big-endian)
    view.setUint32(offset, trait.leafIndex, false);
    offset += 4;

    // proofLen (u32 big-endian)
    view.setUint32(offset, MERKLE_PROOF_DEPTH, false);
    offset += 4;

    // proof hashes (8 × 32 bytes)
    for (let i = 0; i < MERKLE_PROOF_DEPTH; i++) {
        const hash = hexToBytes(trait.proof[i]);
        buf.set(hash, offset);
        offset += 32;
    }

    // blobLen (u32 big-endian)
    view.setUint32(offset, traitBlob.length, false);
    offset += 4;

    // blob data
    buf.set(traitBlob, offset);

    return buf;
}

/**
 * Pick trait for a given mint index. Cycles through all traits to maximize
 * inscription coverage — with 140 traits and 700 mints, each trait gets
 * inscribed ~5 times (contract skips duplicates after first inscription).
 */
function pickTraitForIndex(mintIndex: number): CompressedTrait {
    return COMPRESSED_TRAITS[mintIndex % COMPRESSED_TRAITS.length];
}

async function fetchUtxos(
    provider: OPNetLimitedProvider,
    address: string,
    minAmount: bigint = 50_000n,
): Promise<UTXO[]> {
    return provider.fetchUTXO({
        address,
        minAmount,
        requestedAmount: 10_000_000n,
    });
}

// ---------------------------------------------------------------------------
// Phase: PREFLIGHT — Check all wallet balances, fund if needed, reset stale state
// ---------------------------------------------------------------------------

async function phasePreflight(
    mnemonic: Mnemonic,
    netConfig: NetworkConfig,
    networkName: string,
): Promise<void> {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Phase: PREFLIGHT — Wallet balance check & auto-fund');
    console.log('═══════════════════════════════════════════════════════════\n');

    const deployment = loadDeployment(networkName);
    const fundPerWallet = calcFundPerWallet(MINT_PRICE_SATS);
    // Minimum balance needed to mint remaining NFTs for a wallet
    const minUsableBalance = MINT_PRICE_SATS + FEE_OVERHEAD_PER_MINT;

    const deployer = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const rpcProvider = new JSONRpcProvider({
        url: netConfig.rpcUrl,
        network: netConfig.network,
    });

    // 1. Check on-chain minted count to detect stale state
    let onChainMinted = 0;
    try {
        const nftAddr = await rpcProvider.getPublicKeyInfo(deployment.contracts.MIFRENS, true);
        if (nftAddr) {
            const nftContract = getContract<IContract>(
                nftAddr,
                MiFrensAbi,
                rpcProvider,
                netConfig.network,
            );
            const result = await (nftContract as unknown as Record<string, () => Promise<{
                decoded?: unknown[];
            }>>)['totalMinted']();
            onChainMinted = Number(result.decoded?.[0] ?? 0n);
        }
    } catch { /* ignore */ }

    console.log(`  On-chain totalMinted: ${onChainMinted}`);
    console.log(`  Target: ${TOTAL_TARGET} mints (${TOTAL_WALLETS} wallets × ${MINTS_PER_WALLET})`);
    console.log(`  Mint price: ${MINT_PRICE_SATS} sats (${Number(MINT_PRICE_SATS) / 1e8} BTC)`);
    console.log(`  Fund per wallet: ${fundPerWallet} sats (${Number(fundPerWallet) / 1e8} BTC)\n`);

    // 2. Check if state file is stale (minted count doesn't match on-chain)
    const state = loadState(networkName);
    if (state.totalMinted > 0 && onChainMinted === 0) {
        console.log(`  ⚠ State file shows ${state.totalMinted} mints but on-chain is 0.`);
        console.log('  Contracts were redeployed — resetting state file.\n');
        state.funded = [];
        state.minted = {};
        state.totalMinted = 0;
        saveState(state);
    } else if (state.totalMinted > onChainMinted + 20) {
        console.log(`  ⚠ State file (${state.totalMinted}) far ahead of on-chain (${onChainMinted}).`);
        console.log('  Resetting state to match on-chain.\n');
        state.funded = [];
        state.minted = {};
        state.totalMinted = onChainMinted;
        saveState(state);
    }

    // 3. Check deployer balance
    console.log(`  Deployer: ${deployer.p2tr}`);
    const deployerUtxos = await fetchUtxos(limitedProvider, deployer.p2tr, 10_000n);
    const deployerBalance = deployerUtxos.reduce((sum, u) => sum + u.value, 0n);
    console.log(`  Deployer balance: ${deployerBalance} sats (${Number(deployerBalance) / 1e8} BTC)`);
    console.log(`  Deployer UTXOs: ${deployerUtxos.length}\n`);

    // 4. Check each child wallet
    console.log('  Wallet | Address (short)        | Balance (sats) | Status');
    console.log('  -------+------------------------+----------------+--------');

    let readyCount = 0;
    let needFundCount = 0;
    let totalShortfall = 0n;
    const walletsNeedFunding: number[] = [];

    for (let i = 1; i <= TOTAL_WALLETS; i++) {
        const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, i);
        let balance = 0n;
        try {
            const utxos = await fetchUtxos(limitedProvider, wallet.p2tr, 5_000n);
            balance = utxos.reduce((sum, u) => sum + u.value, 0n);
        } catch { /* no utxos */ }

        const addrShort = wallet.p2tr.slice(0, 22) + '...';
        const localMints = state.minted[i] ?? 0;
        const remainingMints = MINTS_PER_WALLET - localMints;
        const neededForRemaining = BigInt(remainingMints) * (MINT_PRICE_SATS + FEE_OVERHEAD_PER_MINT);

        let status: string;
        if (remainingMints <= 0) {
            status = 'DONE';
            readyCount++;
        } else if (balance >= neededForRemaining) {
            status = `READY (${remainingMints} mints)`;
            readyCount++;
        } else {
            const shortfall = fundPerWallet - balance;
            status = `NEED ${shortfall} sats`;
            needFundCount++;
            totalShortfall += shortfall > 0n ? shortfall : 0n;
            walletsNeedFunding.push(i);
        }

        console.log(`  ${String(i).padStart(6)} | ${addrShort.padEnd(22)} | ${String(balance).padStart(14)} | ${status}`);
        wallet.zeroize();
    }

    // 5. Summary
    console.log('\n───────────────────────────────────────────────────────────');
    console.log(`  Ready:     ${readyCount}/${TOTAL_WALLETS} wallets`);
    console.log(`  Need fund: ${needFundCount}/${TOTAL_WALLETS} wallets`);
    if (totalShortfall > 0n) {
        console.log(`  Total funding needed: ${totalShortfall} sats (${Number(totalShortfall) / 1e8} BTC)`);
        if (deployerBalance >= totalShortfall) {
            console.log(`  Deployer can cover it (${Number(deployerBalance) / 1e8} BTC available)`);
        } else {
            const deficit = totalShortfall - deployerBalance;
            console.log(`  ⚠ Deployer SHORT by ${deficit} sats (${Number(deficit) / 1e8} BTC)`);
            console.log(`  Send at least ${Number(deficit) / 1e8} BTC to deployer first.`);
        }
    }
    console.log('───────────────────────────────────────────────────────────');

    // 6. Auto-fund if --auto-fund flag
    const autoFund = process.argv.includes('--auto-fund');
    if (autoFund && walletsNeedFunding.length > 0) {
        if (deployerBalance < totalShortfall) {
            console.log('\n  Cannot auto-fund: deployer balance insufficient.');
        } else {
            console.log(`\n  Auto-funding ${walletsNeedFunding.length} wallets...`);
            const factory = new TransactionFactory();
            let currentUtxos = deployerUtxos;
            let funded = 0;

            for (const i of walletsNeedFunding) {
                const childWallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, i);
                process.stdout.write(`  [${i}/${TOTAL_WALLETS}] Funding ${childWallet.p2tr.slice(0, 20)}... → ${fundPerWallet} sats ... `);

                try {
                    if (currentUtxos.length === 0) {
                        console.log('WAITING for UTXOs...');
                        await sleep(10_000);
                        currentUtxos = await fetchUtxos(limitedProvider, deployer.p2tr);
                        if (currentUtxos.length === 0) {
                            console.error('  No UTXOs available.');
                            childWallet.zeroize();
                            break;
                        }
                    }

                    const response = await factory.createBTCTransfer({
                        signer: deployer.keypair,
                        mldsaSigner: deployer.mldsaKeypair,
                        network: netConfig.network,
                        from: deployer.p2tr,
                        to: childWallet.p2tr,
                        utxos: currentUtxos,
                        amount: fundPerWallet,
                        feeRate: 5,
                        priorityFee: 0n,
                        gasSatFee: 0n,
                    });

                    await limitedProvider.broadcastTransaction(response.tx, false);
                    currentUtxos = response.nextUTXOs;

                    if (!state.funded.includes(i)) {
                        state.funded.push(i);
                    }
                    saveState(state);
                    funded++;

                    console.log(`OK (fee: ${response.estimatedFees} sats)`);
                    if (funded < walletsNeedFunding.length) await sleep(2_000);
                } catch (err) {
                    console.log(`ERROR: ${err instanceof Error ? err.message : String(err)}`);
                    await sleep(5_000);
                    currentUtxos = await fetchUtxos(limitedProvider, deployer.p2tr);
                }

                childWallet.zeroize();
            }

            console.log(`\n  Funded ${funded} wallets.`);
        }
    } else if (walletsNeedFunding.length > 0) {
        console.log(`\n  To auto-fund, re-run with --auto-fund flag:`);
        console.log(`  DEPLOYER_MNEMONIC="..." npx tsx scripts/mint-collection.ts --phase preflight --network ${networkName} --total ${TOTAL_TARGET} --auto-fund\n`);
    }

    console.log(`\n  Next: npx tsx scripts/mint-collection.ts --phase mint --network ${networkName} --total ${TOTAL_TARGET}\n`);

    deployer.zeroize();
    await rpcProvider.close();
}

// ---------------------------------------------------------------------------
// Phase: GENERATE
// ---------------------------------------------------------------------------

function phaseGenerate(mnemonic: Mnemonic, _netConfig: NetworkConfig): void {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Phase: GENERATE — Deriving 100 minting wallets');
    console.log('═══════════════════════════════════════════════════════════\n');

    const deployer = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`  Deployer (index 0): ${deployer.p2tr}`);
    console.log(`  Mint price: ${MINT_PRICE_SATS} sats (${Number(MINT_PRICE_SATS) / 1e8} BTC)\n`);

    const fundPerWallet = calcFundPerWallet(MINT_PRICE_SATS);
    console.log(`  Funding per wallet: ${fundPerWallet} sats (${Number(fundPerWallet) / 1e8} BTC)`);
    console.log(`  Total funding needed: ${BigInt(TOTAL_WALLETS) * fundPerWallet} sats (${Number(BigInt(TOTAL_WALLETS) * fundPerWallet) / 1e8} BTC)\n`);

    console.log('  Index | Address');
    console.log('  ------+' + '-'.repeat(70));

    for (let i = 1; i <= TOTAL_WALLETS; i++) {
        const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, i);
        console.log(`  ${String(i).padStart(5)} | ${wallet.p2tr}`);
        wallet.zeroize();
    }

    console.log(`\n  Total: ${TOTAL_WALLETS} wallets × ${MINTS_PER_WALLET} mints = ${TOTAL_TARGET} NFTs`);
    console.log(`  Run --phase fund to send BTC to each wallet.\n`);

    deployer.zeroize();
}

// ---------------------------------------------------------------------------
// Phase: FUND
// ---------------------------------------------------------------------------

async function phaseFund(
    mnemonic: Mnemonic,
    netConfig: NetworkConfig,
    networkName: string,
): Promise<void> {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Phase: FUND — Check balances & top-up minting wallets');
    console.log('═══════════════════════════════════════════════════════════\n');

    const state = loadState(networkName);
    const startWallet = getStartWallet();
    const fundAmount = getFundAmount();

    const deployer = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`  Deployer: ${deployer.p2tr}`);
    console.log(`  Mint price: ${MINT_PRICE_SATS} sats (${Number(MINT_PRICE_SATS) / 1e8} BTC)`);
    console.log(`  Target fund per wallet: ${fundAmount} sats`);
    console.log(`  Starting from wallet: ${startWallet}\n`);

    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    const factory = new TransactionFactory();

    let currentUtxos = await fetchUtxos(limitedProvider, deployer.p2tr);
    console.log(`  Deployer UTXOs: ${currentUtxos.length}`);

    const totalBalance = currentUtxos.reduce((sum, u) => sum + u.value, 0n);
    console.log(`  Deployer balance: ${totalBalance} sats (${Number(totalBalance) / 1e8} BTC)\n`);

    let funded = 0;
    let skipped = 0;

    for (let i = startWallet; i <= TOTAL_WALLETS; i++) {
        const childWallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, i);

        // Check how many mints remain for this wallet
        const currentMints = state.minted[i] ?? 0;
        const remainingMints = MINTS_PER_WALLET - currentMints;
        if (remainingMints <= 0) {
            console.log(`  [${i}/${TOTAL_WALLETS}] All ${MINTS_PER_WALLET} mints done — skipping`);
            skipped++;
            childWallet.zeroize();
            continue;
        }

        // Check actual on-chain balance
        let walletBalance = 0n;
        try {
            const utxos = await fetchUtxos(limitedProvider, childWallet.p2tr, 5_000n);
            walletBalance = utxos.reduce((sum, u) => sum + u.value, 0n);
        } catch { /* no utxos = 0 balance */ }

        // Calculate how much this wallet needs for remaining mints
        const neededForRemaining = BigInt(remainingMints) * (MINT_PRICE_SATS + FEE_OVERHEAD_PER_MINT) + 30_000n;

        if (walletBalance >= neededForRemaining) {
            console.log(`  [${i}/${TOTAL_WALLETS}] Balance ${walletBalance} sats >= needed ${neededForRemaining} — OK`);
            if (!state.funded.includes(i)) {
                state.funded.push(i);
                saveState(state);
            }
            skipped++;
            childWallet.zeroize();
            continue;
        }

        // Need to fund: send the shortfall (or full fundAmount if wallet is empty)
        const sendAmount = walletBalance === 0n ? fundAmount : (neededForRemaining - walletBalance);
        process.stdout.write(`  [${i}/${TOTAL_WALLETS}] Balance ${walletBalance}, need ${neededForRemaining} → sending ${sendAmount} sats ... `);

        try {
            if (currentUtxos.length === 0) {
                console.log('WAITING for UTXOs...');
                await sleep(10_000);
                currentUtxos = await fetchUtxos(limitedProvider, deployer.p2tr);
                if (currentUtxos.length === 0) {
                    console.error('  No UTXOs available. Deployer needs more BTC.');
                    childWallet.zeroize();
                    break;
                }
            }

            const response = await factory.createBTCTransfer({
                signer: deployer.keypair,
                mldsaSigner: deployer.mldsaKeypair,
                network: netConfig.network,
                from: deployer.p2tr,
                to: childWallet.p2tr,
                utxos: currentUtxos,
                amount: sendAmount,
                feeRate: 5,
                priorityFee: 0n,
                gasSatFee: 0n,
            });

            await limitedProvider.broadcastTransaction(response.tx, false);
            currentUtxos = response.nextUTXOs;

            if (!state.funded.includes(i)) {
                state.funded.push(i);
            }
            saveState(state);
            funded++;

            console.log(`OK (fee: ${response.estimatedFees} sats)`);

            if (i < TOTAL_WALLETS) {
                await sleep(2_000);
            }
        } catch (err) {
            console.log(`ERROR: ${err instanceof Error ? err.message : String(err)}`);
            await sleep(5_000);
            currentUtxos = await fetchUtxos(limitedProvider, deployer.p2tr);
        }

        childWallet.zeroize();
    }

    console.log(`\n  Funded: ${funded} | Already OK: ${skipped} | Total: ${TOTAL_WALLETS}`);
    console.log(`  Run --phase mint to begin minting.\n`);

    deployer.zeroize();
}

// ---------------------------------------------------------------------------
// Phase: MINT
// ---------------------------------------------------------------------------

async function mintForWallet(
    walletIndex: number,
    mnemonic: Mnemonic,
    netConfig: NetworkConfig,
    deployment: DeploymentData,
    rpcProvider: JSONRpcProvider,
    state: MintState,
    globalMintCounter: { value: number },
): Promise<number> {
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, walletIndex);
    const currentMints = state.minted[walletIndex] ?? 0;
    const remaining = MINTS_PER_WALLET - currentMints;

    if (remaining <= 0) {
        wallet.zeroize();
        return 0;
    }

    // Check wallet balance before starting mints
    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);
    let walletBalance = 0n;
    try {
        const utxos = await fetchUtxos(limitedProvider, wallet.p2tr, 5_000n);
        walletBalance = utxos.reduce((sum, u) => sum + u.value, 0n);
    } catch { /* no utxos */ }

    const minNeeded = MINT_PRICE_SATS + FEE_OVERHEAD_PER_MINT;
    if (walletBalance < minNeeded) {
        console.log(`  [W${walletIndex}] Insufficient balance: ${walletBalance} sats (need ${minNeeded}) — skipping`);
        wallet.zeroize();
        return 0;
    }

    const forgeAddr = await rpcProvider.getPublicKeyInfo(deployment.contracts.FRENFORGE, true);
    if (!forgeAddr) {
        console.error(`  [W${walletIndex}] Could not resolve FrenForge address`);
        wallet.zeroize();
        return 0;
    }

    const forgeContract = getContract<IContract>(
        forgeAddr,
        FrenForgeAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const treasuryAddress = deployment.deployer;
    let minted = 0;

    for (let m = 0; m < remaining; m++) {
        const mintIndex = globalMintCounter.value;
        globalMintCounter.value++;
        const trait = pickTraitForIndex(mintIndex);
        const packedData = packMintData(trait);

        process.stdout.write(
            `  [W${String(walletIndex).padStart(3)}|M${currentMints + m + 1}/${MINTS_PER_WALLET}] ` +
            `trait=${trait.label.slice(0, 15).padEnd(15)} ... `
        );

        try {
            // Set treasury payment for simulation
            (forgeContract as IContract & { setTransactionDetails: (d: unknown) => void }).setTransactionDetails({
                inputs: [],
                outputs: [
                    {
                        to: treasuryAddress,
                        value: MINT_PRICE_SATS,
                        index: 1,
                        flags: TransactionOutputFlags.hasTo,
                    },
                ],
            });

            const sim = await (forgeContract as unknown as Record<string, (...args: unknown[]) => Promise<{
                revert?: string;
                decoded?: unknown[];
                properties?: Record<string, unknown>;
                sendTransaction: (params: Record<string, unknown>) => Promise<{
                    transactionId?: string;
                }>;
            }>>)['mint'](
                BigInt(trait.traitKey),
                packedData,
            );

            if (sim.revert) {
                console.log(`REVERT: ${sim.revert}`);
                if (sim.revert.includes('MAX_SUPPLY') || sim.revert.includes('SOLD_OUT')) {
                    console.log('  Collection fully minted!');
                    break;
                }
                await sleep(3_000);
                continue;
            }

            const receipt = await sim.sendTransaction({
                signer: wallet.keypair,
                mldsaSigner: wallet.mldsaKeypair,
                refundTo: wallet.p2tr,
                maximumAllowedSatToSpend: 50_000n,
                feeRate: 5,
                network: netConfig.network,
                extraOutputs: [
                    {
                        address: treasuryAddress,
                        value: MINT_PRICE_SATS,
                    },
                ],
            });

            const tokenId = sim.properties?.tokenId ?? sim.decoded?.[0];
            const tokenStr = tokenId != null ? `#${tokenId}` : '';
            const txShort = receipt.transactionId?.slice(0, 12) ?? '???';

            console.log(`Token ${tokenStr} — TX: ${txShort}...`);

            minted++;
            state.minted[walletIndex] = (state.minted[walletIndex] ?? 0) + 1;
            state.totalMinted++;
            saveState(state);

            // Delay between mints to avoid mempool congestion
            if (m < remaining - 1) {
                await sleep(4_000);
            }
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            console.log(`ERROR: ${msg.slice(0, 80)}`);

            // If the error suggests insufficient funds, stop this wallet
            if (msg.includes('Insufficient') || msg.includes('not enough') || msg.includes('UTXO')) {
                console.log(`  [W${walletIndex}] Wallet likely out of funds — stopping`);
                break;
            }
            await sleep(5_000);
        }
    }

    wallet.zeroize();
    return minted;
}

async function phaseMint(
    mnemonic: Mnemonic,
    netConfig: NetworkConfig,
    networkName: string,
): Promise<void> {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Phase: MINT — Minting NFTs via FrenForge');
    console.log('═══════════════════════════════════════════════════════════\n');

    const state = loadState(networkName);
    const deployment = loadDeployment(networkName);
    const startWallet = getStartWallet();
    const concurrency = getConcurrency();

    console.log(`  FrenForge: ${deployment.contracts.FRENFORGE}`);
    console.log(`  MiFrens:   ${deployment.contracts.MIFRENS}`);
    console.log(`  Treasury:  ${deployment.deployer}`);
    console.log(`  Mint price: ${MINT_PRICE_SATS} sats (${Number(MINT_PRICE_SATS) / 1e8} BTC)`);
    console.log(`  Concurrency: ${concurrency} wallets in parallel`);
    console.log(`  Starting from wallet: ${startWallet}`);
    console.log(`  Target: ${TOTAL_TARGET} mints (${TOTAL_WALLETS} wallets)\n`);

    const rpcProvider = new JSONRpcProvider({
        url: netConfig.rpcUrl,
        network: netConfig.network,
    });
    const limitedProvider = new OPNetLimitedProvider(netConfig.rpcUrl);

    // --- Auto-set mint price on-chain if it doesn't match ---
    const deployer = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    const nftAddr = await rpcProvider.getPublicKeyInfo(deployment.contracts.MIFRENS, true);
    if (!nftAddr) {
        console.error('  Could not resolve MiFrens address');
        process.exit(1);
    }

    const nftContract = getContract<IContract>(
        nftAddr,
        MiFrensAbi,
        rpcProvider,
        netConfig.network,
        deployer.address,
    );

    const callNft = (name: string) =>
        (nftContract as unknown as Record<string, (...args: unknown[]) => Promise<{
            revert?: string;
            decoded?: unknown[];
            sendTransaction: (params: Record<string, unknown>) => Promise<{ transactionId?: string }>;
        }>>)[name];

    // --- Detect stale state by comparing on-chain totalMinted ---
    let onChainMinted = 0;
    try {
        const result = await (nftContract as unknown as Record<string, () => Promise<{
            decoded?: unknown[];
        }>>)['totalMinted']();
        onChainMinted = Number(result.decoded?.[0] ?? 0n);
        console.log(`  On-chain total minted: ${onChainMinted}/${MAX_NFT_SUPPLY}`);
    } catch {
        console.log('  (Could not read on-chain total)');
    }

    if (state.totalMinted > 0 && onChainMinted === 0) {
        console.log(`  State file shows ${state.totalMinted} mints but on-chain is 0.`);
        console.log('  Contracts were redeployed — resetting state file.');
        state.funded = [];
        state.minted = {};
        state.totalMinted = 0;
        saveState(state);
    } else if (state.totalMinted > onChainMinted + 20) {
        console.log(`  State file (${state.totalMinted}) far ahead of on-chain (${onChainMinted}).`);
        console.log('  Resetting state to match on-chain.');
        state.funded = [];
        state.minted = {};
        state.totalMinted = onChainMinted;
        saveState(state);
    }

    console.log(`  Progress: ${state.totalMinted}/${TOTAL_TARGET} public mints\n`);

    try {
        const priceResult = await callNft('getMintPrice')();
        const onChainPrice = BigInt(priceResult.decoded?.[0]?.toString() ?? '0');
        console.log(`  On-chain mint price: ${onChainPrice} sats`);

        if (onChainPrice !== MINT_PRICE_SATS) {
            console.log(`  Updating on-chain price to ${MINT_PRICE_SATS} sats...`);
            const sim = await callNft('setMintPrice')(MINT_PRICE_SATS);
            if (sim.revert) {
                console.error(`  setMintPrice reverted: ${sim.revert}`);
                process.exit(1);
            }
            const receipt = await sim.sendTransaction({
                signer: deployer.keypair,
                mldsaSigner: deployer.mldsaKeypair,
                refundTo: deployer.p2tr,
                maximumAllowedSatToSpend: 300_000n,
                feeRate: 5,
                network: netConfig.network,
            });
            console.log(`  Price updated — TX: ${receipt.transactionId?.slice(0, 24)}...`);
            await sleep(5_000);
        } else {
            console.log('  Price matches — no update needed');
        }
    } catch (err) {
        console.log(`  Price check failed: ${err instanceof Error ? err.message : String(err)}`);
        console.log('  Continuing anyway...');
    }

    console.log('');

    // Build list of wallet indices that still need minting
    const walletsToMint: number[] = [];
    for (let i = startWallet; i <= TOTAL_WALLETS; i++) {
        const done = state.minted[i] ?? 0;
        if (done < MINTS_PER_WALLET) {
            walletsToMint.push(i);
        }
    }

    if (walletsToMint.length === 0) {
        console.log('  All wallets have completed their 7 mints!');
        deployer.zeroize();
        await rpcProvider.close();
        return;
    }

    console.log(`  Wallets remaining: ${walletsToMint.length}`);

    // --- Auto-fund wallets that need BTC before minting ---
    console.log('  Checking wallet balances...\n');
    const factory = new TransactionFactory();
    let deployerUtxos = await fetchUtxos(limitedProvider, deployer.p2tr, 10_000n);
    let fundedThisRun = 0;

    for (const walletIdx of walletsToMint) {
        const childWallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, walletIdx);
        const currentMints = state.minted[walletIdx] ?? 0;
        const remainingMints = MINTS_PER_WALLET - currentMints;
        const neededForRemaining = BigInt(remainingMints) * (MINT_PRICE_SATS + FEE_OVERHEAD_PER_MINT) + 30_000n;

        let walletBalance = 0n;
        try {
            const utxos = await fetchUtxos(limitedProvider, childWallet.p2tr, 5_000n);
            walletBalance = utxos.reduce((sum, u) => sum + u.value, 0n);
        } catch { /* no utxos */ }

        if (walletBalance >= neededForRemaining) {
            childWallet.zeroize();
            continue;
        }

        // Need to fund this wallet
        const sendAmount = walletBalance === 0n
            ? calcFundPerWallet(MINT_PRICE_SATS)
            : (neededForRemaining - walletBalance);

        process.stdout.write(`  [W${walletIdx}] Balance ${walletBalance}, need ${neededForRemaining} → sending ${sendAmount} sats ... `);

        try {
            if (deployerUtxos.length === 0) {
                console.log('WAITING for UTXOs...');
                await sleep(10_000);
                deployerUtxos = await fetchUtxos(limitedProvider, deployer.p2tr);
                if (deployerUtxos.length === 0) {
                    console.error('No deployer UTXOs available.');
                    childWallet.zeroize();
                    break;
                }
            }

            const response = await factory.createBTCTransfer({
                signer: deployer.keypair,
                mldsaSigner: deployer.mldsaKeypair,
                network: netConfig.network,
                from: deployer.p2tr,
                to: childWallet.p2tr,
                utxos: deployerUtxos,
                amount: sendAmount,
                feeRate: 5,
                priorityFee: 0n,
                gasSatFee: 0n,
            });

            await limitedProvider.broadcastTransaction(response.tx, false);
            deployerUtxos = response.nextUTXOs;

            if (!state.funded.includes(walletIdx)) {
                state.funded.push(walletIdx);
            }
            saveState(state);
            fundedThisRun++;

            console.log(`OK (fee: ${response.estimatedFees} sats)`);
            await sleep(2_000);
        } catch (err) {
            console.log(`ERROR: ${err instanceof Error ? err.message : String(err)}`);
            await sleep(5_000);
            deployerUtxos = await fetchUtxos(limitedProvider, deployer.p2tr);
        }

        childWallet.zeroize();
    }

    if (fundedThisRun > 0) {
        console.log(`\n  Auto-funded ${fundedThisRun} wallets. Waiting for confirmation...\n`);
        await sleep(10_000);
    }

    deployer.zeroize();

    // Global mint counter for trait cycling
    const globalMintCounter = { value: state.totalMinted };

    // Process in batches of `concurrency`
    let totalMinted = 0;
    for (let batch = 0; batch < walletsToMint.length; batch += concurrency) {
        const batchWallets = walletsToMint.slice(batch, batch + concurrency);
        const batchNum = Math.floor(batch / concurrency) + 1;
        const totalBatches = Math.ceil(walletsToMint.length / concurrency);

        console.log(`--- Batch ${batchNum}/${totalBatches} (wallets: ${batchWallets.join(', ')}) ---`);

        const promises = batchWallets.map((walletIdx) =>
            mintForWallet(
                walletIdx,
                mnemonic,
                netConfig,
                deployment,
                rpcProvider,
                state,
                globalMintCounter,
            ),
        );

        const results = await Promise.all(promises);
        const batchMinted = results.reduce((a, b) => a + b, 0);
        totalMinted += batchMinted;

        console.log(`--- Batch ${batchNum} done: ${batchMinted} minted ---\n`);

        // Brief pause between batches
        if (batch + concurrency < walletsToMint.length) {
            await sleep(3_000);
        }
    }

    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Minting complete: ${totalMinted} new mints this run`);
    console.log(`  Total progress: ${state.totalMinted}/${TOTAL_TARGET} public mints`);
    console.log('═══════════════════════════════════════════════════════════\n');

    await rpcProvider.close();
}

// ---------------------------------------------------------------------------
// Phase: STATUS
// ---------------------------------------------------------------------------

async function phaseStatus(
    mnemonic: Mnemonic,
    netConfig: NetworkConfig,
    networkName: string,
): Promise<void> {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Phase: STATUS — Collection mint progress');
    console.log('═══════════════════════════════════════════════════════════\n');

    const state = loadState(networkName);
    const deployment = loadDeployment(networkName);

    console.log(`  Network:    ${networkName}`);
    console.log(`  Mint price: ${MINT_PRICE_SATS} sats (${Number(MINT_PRICE_SATS) / 1e8} BTC)`);
    console.log(`  State file: ${STATE_FILE}`);
    console.log(`  Last saved: ${state.lastUpdated}\n`);

    // State file stats
    const fundedCount = state.funded.length;
    const mintsCompleted = state.totalMinted;
    const walletsFullyMinted = Object.values(state.minted).filter((n) => n >= MINTS_PER_WALLET).length;

    console.log(`  Wallets funded:       ${fundedCount}/${TOTAL_WALLETS}`);
    console.log(`  Wallets fully minted: ${walletsFullyMinted}/${TOTAL_WALLETS}`);
    console.log(`  Total mints (local):  ${mintsCompleted}/${TOTAL_TARGET}\n`);

    // Check on-chain
    const rpcProvider = new JSONRpcProvider({
        url: netConfig.rpcUrl,
        network: netConfig.network,
    });

    try {
        const nftAddr = await rpcProvider.getPublicKeyInfo(deployment.contracts.MIFRENS, true);
        const deployerAddr = await rpcProvider.getPublicKeyInfo(deployment.deployer, true);
        if (!nftAddr || !deployerAddr) {
            console.log('  Could not resolve contract/deployer address');
            await rpcProvider.close();
            return;
        }

        const nftContract = getContract<IContract>(
            nftAddr,
            [{ name: 'totalMinted', inputs: [], outputs: [{ name: 'count', type: 'UINT256' }], type: 'Function' }],
            rpcProvider,
            netConfig.network,
            deployerAddr,
        );

        const result = await (nftContract as unknown as Record<string, () => Promise<{
            decoded?: unknown[];
        }>>)['totalMinted']();
        const onChain = Number(result.decoded?.[0] ?? 0n);
        console.log(`  On-chain total:       ${onChain}/${MAX_NFT_SUPPLY}`);
        console.log(`  Remaining:            ${MAX_NFT_SUPPLY - onChain}`);

        if (onChain >= MAX_NFT_SUPPLY) {
            console.log('\n  ALL 777 NFTs MINTED! Collection complete.');
        }
    } catch (err) {
        console.log(`  On-chain check failed: ${err instanceof Error ? err.message : String(err)}`);
    }

    // Per-wallet breakdown
    console.log('\n  Wallet | Funded | Minted');
    console.log('  -------+--------+-------');
    for (let i = 1; i <= TOTAL_WALLETS; i++) {
        const funded = state.funded.includes(i) ? 'YES' : ' - ';
        const mints = state.minted[i] ?? 0;
        if (mints > 0 || state.funded.includes(i)) {
            console.log(`  ${String(i).padStart(6)} | ${funded.padStart(6)} | ${mints}/${MINTS_PER_WALLET}`);
        }
    }

    console.log('');
    await rpcProvider.close();
}


// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const phase = getPhase();
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

    console.log(`\nMiFrens Collection Minter — ${phase.toUpperCase()}`);
    console.log(`Network: ${networkName}\n`);

    const mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);

    try {
        switch (phase) {
            case 'generate':
                phaseGenerate(mnemonic, netConfig);
                break;
            case 'fund':
                await phaseFund(mnemonic, netConfig, networkName);
                break;
            case 'mint':
                await phaseMint(mnemonic, netConfig, networkName);
                break;
            case 'status':
                await phaseStatus(mnemonic, netConfig, networkName);
                break;
            case 'preflight':
                await phasePreflight(mnemonic, netConfig, networkName);
                break;
            default:
                console.error(`Unknown phase "${phase}". Available: preflight, generate, fund, mint, status`);
                process.exit(1);
        }
    } finally {
        mnemonic.zeroize();
    }
}

main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
});
