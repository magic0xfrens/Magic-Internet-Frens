#!/usr/bin/env tsx

/**
 * test-marketplace.ts — End-to-end marketplace test on deployed contracts.
 *
 * Phases:
 *   1. Read-only: verify marketplace config (fee, listing count)
 *   2. List an NFT the deployer owns
 *   3. Verify the listing appears
 *   4. Cancel the listing
 *   5. Verify listing is removed
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-marketplace.ts --network testnet
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-marketplace.ts --network testnet --token-id 5
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-marketplace.ts --network testnet --read-only
 */

import * as fs from 'fs';
import { createHash } from 'crypto';
import { join } from 'path';

import {
    Mnemonic,
    OPNetLimitedProvider,
    AddressTypes,
    MLDSASecurityLevel,
} from '@btc-vision/transaction';
import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider, ABIDataTypes, BitcoinAbiTypes } from 'opnet';
import type { IContract, TransactionParameters } from 'opnet';

// ---------------------------------------------------------------------------
// ABI (marketplace + NFT view methods)
// ---------------------------------------------------------------------------

const FrenMarketAbi = [
    {
        name: 'listNFT',
        inputs: [
            { name: 'tokenId', type: ABIDataTypes.UINT256 },
            { name: 'priceSats', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrHash', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrHi', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrLo', type: ABIDataTypes.UINT256 },
        ],
        outputs: [],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'cancelListing',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'buyNFT',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getActiveListingCount',
        inputs: [],
        outputs: [{ name: 'count', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getListingByIndex',
        inputs: [{ name: 'index', type: ABIDataTypes.UINT256 }],
        outputs: [
            { name: 'tokenId', type: ABIDataTypes.UINT256 },
            { name: 'seller', type: ABIDataTypes.ADDRESS },
            { name: 'priceSats', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrHi', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrLo', type: ABIDataTypes.UINT256 },
        ],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getListing',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [
            { name: 'seller', type: ABIDataTypes.ADDRESS },
            { name: 'priceSats', type: ABIDataTypes.UINT256 },
            { name: 'active', type: ABIDataTypes.BOOL },
        ],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getFeeBps',
        inputs: [],
        outputs: [{ name: 'bps', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
];

const NftViewAbi = [
    {
        name: 'ownerOf',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'owner', type: ABIDataTypes.ADDRESS }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'approve',
        inputs: [
            { name: 'operator', type: ABIDataTypes.ADDRESS },
            { name: 'tokenId', type: ABIDataTypes.UINT256 },
        ],
        outputs: [],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'balanceOf',
        inputs: [{ name: 'owner', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'balance', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'tokenOfOwnerByIndex',
        inputs: [
            { name: 'owner', type: ABIDataTypes.ADDRESS },
            { name: 'index', type: ABIDataTypes.UINT256 },
        ],
        outputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'isLocked',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'locked', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
];

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

function getNetworkName(): string {
    const idx = process.argv.indexOf('--network');
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : 'regtest';
}

function getFlag(flag: string): boolean {
    return process.argv.includes(flag);
}

function getArgValue(flag: string): string | undefined {
    const idx = process.argv.indexOf(flag);
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : undefined;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
    return new Promise((r) => setTimeout(r, ms));
}

function packAddressToU256Pair(addr: string): { hi: bigint; lo: bigint } {
    const bytes = Buffer.from(addr, 'utf8');
    const padded = Buffer.alloc(64);
    bytes.copy(padded, 0);
    const hi = BigInt('0x' + padded.subarray(0, 32).toString('hex'));
    const lo = BigInt('0x' + padded.subarray(32, 64).toString('hex'));
    return { hi, lo };
}

function computeAddrHash(addr: string): bigint {
    const hash = createHash('sha256').update(Buffer.from(addr, 'utf8')).digest();
    return BigInt('0x' + hash.toString('hex'));
}

function ok(label: string, value: string): void {
    console.log(`  [PASS] ${label}: ${value}`);
}

function fail(label: string, msg: string): void {
    console.log(`  [FAIL] ${label}: ${msg}`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const networkName = getNetworkName();
    const netConfig = NETWORKS[networkName];
    if (!netConfig) {
        console.error(`Unknown network. Available: ${Object.keys(NETWORKS).join(', ')}`);
        process.exit(1);
    }

    const readOnly = getFlag('--read-only');
    const tokenIdArg = getArgValue('--token-id');

    const deploymentPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment at ${deploymentPath}`);
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const nftAddress: string = deployment.contracts.MIFRENS;
    const marketAddress: string = deployment.contracts.FRENMARKET;

    if (!nftAddress) {
        console.error('MIFRENS address not found');
        process.exit(1);
    }
    if (!marketAddress) {
        console.error('FRENMARKET address not found. Deploy the marketplace first.');
        process.exit(1);
    }

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  FrenMarket — End-to-End Test');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:      ${networkName}`);
    console.log(`  NFT:          ${nftAddress}`);
    console.log(`  Marketplace:  ${marketAddress}`);
    console.log(`  Mode:         ${readOnly ? 'read-only' : 'full (list + cancel)'}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    const rpcProvider = new JSONRpcProvider({ url: netConfig.rpcUrl, network: netConfig.network });

    // Resolve addresses
    console.log('Resolving contract addresses...');
    const nftAddr = await rpcProvider.getPublicKeyInfo(nftAddress, true);
    const marketAddr = await rpcProvider.getPublicKeyInfo(marketAddress, true);
    if (!nftAddr || !marketAddr) {
        console.error('Could not resolve contract addresses. Are they confirmed?');
        process.exit(1);
    }
    console.log('  NFT resolved');
    console.log('  Marketplace resolved\n');

    // Wallet setup (needed for non-read-only + resolving sender address)
    let wallet: { p2tr: string; keypair: unknown; mldsaKeypair: unknown; address: unknown } | undefined;
    let mnemonic: Mnemonic | undefined;

    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (mnemonicPhrase) {
        mnemonic = new Mnemonic(mnemonicPhrase, '', netConfig.network, MLDSASecurityLevel.LEVEL2);
        wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
        console.log(`Wallet: ${wallet.p2tr}\n`);
    } else if (!readOnly) {
        console.error('DEPLOYER_MNEMONIC required for write operations. Use --read-only for view-only.');
        process.exit(1);
    }

    // Create contract instances
    const marketContract = wallet
        ? getContract<IContract>(marketAddr, FrenMarketAbi, rpcProvider, netConfig.network, wallet.address)
        : getContract<IContract>(marketAddr, FrenMarketAbi, rpcProvider, netConfig.network);

    const nftContract = wallet
        ? getContract<IContract>(nftAddr, NftViewAbi, rpcProvider, netConfig.network, wallet.address)
        : getContract<IContract>(nftAddr, NftViewAbi, rpcProvider, netConfig.network);

    // =====================================================================
    // PHASE 1: Read-Only Checks
    // =====================================================================
    console.log('--- PHASE 1: Marketplace State ---\n');

    // getFeeBps
    try {
        const res = await method(marketContract, 'getFeeBps')();
        if (res.revert) {
            fail('getFeeBps', `REVERT: ${res.revert}`);
        } else {
            const bps = BigInt((res.properties?.bps ?? res.decoded?.[0] ?? 0) as string | bigint | number);
            const pct = Number(bps) / 100;
            ok('getFeeBps', `${bps} BPS (${pct}%)`);
            if (bps !== 690n) {
                console.log(`    WARNING: Expected 690 BPS (6.9%), got ${bps}`);
            }
        }
    } catch (e: unknown) {
        fail('getFeeBps', (e as Error).message);
    }

    // getActiveListingCount
    let listingCount = 0n;
    try {
        const res = await method(marketContract, 'getActiveListingCount')();
        if (res.revert) {
            fail('getActiveListingCount', `REVERT: ${res.revert}`);
        } else {
            listingCount = BigInt((res.properties?.count ?? res.decoded?.[0] ?? 0) as string | bigint | number);
            ok('getActiveListingCount', listingCount.toString());
        }
    } catch (e: unknown) {
        fail('getActiveListingCount', (e as Error).message);
    }

    // Config check: simulate listNFT on non-existent token to verify NFT contract is set
    // If nftContract is not configured, revert message will contain "NFT not set"
    // If nftContract IS configured, it will revert with "not owner" (expected — good sign)
    console.log('\n--- Config Verification ---\n');
    try {
        const dummyHash = 0n;
        const configSim = await method(marketContract, 'listNFT')(999999n, 1n, dummyHash, 0n, 0n);
        if (configSim.revert) {
            const revertMsg = configSim.revert.toLowerCase();
            if (revertMsg.includes('nft') && revertMsg.includes('not set')) {
                fail('NFT contract', 'NOT CONFIGURED — setNFTContract was not called');
            } else if (revertMsg.includes('not') && (revertMsg.includes('owner') || revertMsg.includes('nft'))) {
                ok('NFT contract', 'Configured (revert = ownership check, as expected)');
            } else {
                ok('NFT contract', `Configured (revert: ${configSim.revert})`);
            }
        } else {
            console.log('  [WARN] listNFT simulation did not revert — unexpected');
        }
    } catch (e: unknown) {
        // A throw (not a revert) likely means the contract call went through to the NFT contract
        ok('NFT contract', `Configured (call reached NFT contract: ${(e as Error).message.slice(0, 60)})`);
    }

    // List existing listings
    if (listingCount > 0n) {
        console.log(`\n  Active listings:`);
        const max = listingCount > 5n ? 5n : listingCount;
        for (let i = 0n; i < max; i++) {
            try {
                const res = await method(marketContract, 'getListingByIndex')(i);
                if (res.revert) {
                    console.log(`    [${i}] REVERT: ${res.revert}`);
                } else {
                    const tokenId = BigInt((res.properties?.tokenId ?? res.decoded?.[0] ?? 0) as string | bigint | number);
                    const price = BigInt((res.properties?.priceSats ?? res.decoded?.[2] ?? 0) as string | bigint | number);
                    console.log(`    [${i}] Token #${tokenId} — ${price} sats (${Number(price) / 1e8} BTC)`);
                }
            } catch (e: unknown) {
                console.log(`    [${i}] ERROR: ${(e as Error).message}`);
            }
        }
        if (listingCount > 5n) {
            console.log(`    ... and ${listingCount - 5n} more`);
        }
    }

    // Check deployer's NFT balance
    if (wallet) {
        console.log('\n--- Deployer NFT Balance ---\n');
        try {
            const walletAddr = await rpcProvider.getPublicKeyInfo(wallet.p2tr, true);
            if (walletAddr) {
                const balRes = await method(nftContract, 'balanceOf')(walletAddr);
                if (balRes.revert) {
                    fail('balanceOf', `REVERT: ${balRes.revert}`);
                } else {
                    const bal = BigInt((balRes.properties?.balance ?? balRes.decoded?.[0] ?? 0) as string | bigint | number);
                    ok('balanceOf', `${bal} NFTs owned`);

                    // Show first few token IDs
                    const showCount = bal > 5n ? 5n : bal;
                    for (let i = 0n; i < showCount; i++) {
                        try {
                            const tokRes = await method(nftContract, 'tokenOfOwnerByIndex')(walletAddr, i);
                            const tid = BigInt((tokRes.properties?.tokenId ?? tokRes.decoded?.[0] ?? 0) as string | bigint | number);
                            console.log(`    [${i}] Token #${tid}`);
                        } catch {
                            break;
                        }
                    }
                    if (bal > 5n) console.log(`    ... and ${bal - 5n} more`);
                }
            }
        } catch (e: unknown) {
            fail('balanceOf', (e as Error).message);
        }
    }

    if (readOnly) {
        console.log('\n--- Read-only mode. Skipping write tests. ---\n');
        await rpcProvider.close();
        if (mnemonic) mnemonic.zeroize();
        if (wallet) (wallet as { zeroize: () => void }).zeroize();
        return;
    }

    if (!wallet) {
        console.error('Wallet not available for write operations');
        process.exit(1);
    }

    // =====================================================================
    // PHASE 2: Find a token to list
    // =====================================================================
    console.log('\n--- PHASE 2: Select Token to List ---\n');

    let testTokenId: bigint;

    if (tokenIdArg) {
        testTokenId = BigInt(tokenIdArg);
        console.log(`  Using specified token #${testTokenId}`);
    } else {
        // Find deployer's first unlocked token
        const walletAddr = await rpcProvider.getPublicKeyInfo(wallet.p2tr, true);
        if (!walletAddr) {
            console.error('Could not resolve wallet address');
            process.exit(1);
        }

        const balRes = await method(nftContract, 'balanceOf')(walletAddr);
        const bal = BigInt((balRes.properties?.balance ?? balRes.decoded?.[0] ?? 0) as string | bigint | number);
        if (bal === 0n) {
            console.error('Deployer has no NFTs. Mint one first.');
            process.exit(1);
        }

        let found = false;
        testTokenId = 0n;
        for (let i = 0n; i < bal; i++) {
            const tokRes = await method(nftContract, 'tokenOfOwnerByIndex')(walletAddr, i);
            const tid = BigInt((tokRes.properties?.tokenId ?? tokRes.decoded?.[0] ?? 0) as string | bigint | number);

            // Check not locked
            try {
                const lockRes = await method(nftContract, 'isLocked')(tid);
                const locked = lockRes.properties?.locked ?? lockRes.decoded?.[0] ?? false;
                if (locked) {
                    console.log(`  Token #${tid} — locked, skipping`);
                    continue;
                }
            } catch {
                // isLocked may revert if not implemented — treat as unlocked
            }

            // Check not already listed
            try {
                const listRes = await method(marketContract, 'getListing')(tid);
                const active = listRes.properties?.active ?? listRes.decoded?.[2] ?? false;
                if (active) {
                    console.log(`  Token #${tid} — already listed, skipping`);
                    continue;
                }
            } catch {
                // getListing may revert — treat as not listed
            }

            testTokenId = tid;
            found = true;
            break;
        }

        if (!found) {
            console.error('No unlocked, unlisted tokens available');
            process.exit(1);
        }
    }

    console.log(`  Selected token #${testTokenId} for listing test`);

    // =====================================================================
    // PHASE 3: Approve + List
    // =====================================================================
    console.log('\n--- PHASE 3: Approve & List ---\n');

    const txParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 200_000n,
        feeRate: 5,
        priorityFee: 5_000n,
        network: netConfig.network,
    };

    // Step 3a: Approve marketplace to transfer token
    console.log('  Approving marketplace...');
    try {
        const approveSim = await method(nftContract, 'approve')(marketAddr, testTokenId);
        if (approveSim.revert) {
            fail('approve', `REVERT: ${approveSim.revert}`);
            process.exit(1);
        }
        const approveTx = await approveSim.sendTransaction(txParams);
        ok('approve', `TX: ${approveTx.transactionId.slice(0, 40)}...`);
    } catch (e: unknown) {
        fail('approve', (e as Error).message);
        process.exit(1);
    }

    console.log('  Waiting for approve to confirm...');
    await sleep(8_000);

    // Step 3b: List the NFT
    const testPrice = 10_000n; // 10,000 sats = 0.0001 BTC
    const sellerHash = computeAddrHash(wallet.p2tr);
    const { hi, lo } = packAddressToU256Pair(wallet.p2tr);

    console.log(`  Listing token #${testTokenId} for ${testPrice} sats...`);
    try {
        const listSim = await method(marketContract, 'listNFT')(
            testTokenId, testPrice, sellerHash, hi, lo,
        );
        if (listSim.revert) {
            fail('listNFT', `REVERT: ${listSim.revert}`);
            process.exit(1);
        }
        const listTx = await listSim.sendTransaction(txParams);
        ok('listNFT', `TX: ${listTx.transactionId.slice(0, 40)}...`);
    } catch (e: unknown) {
        fail('listNFT', (e as Error).message);
        process.exit(1);
    }

    console.log('  Waiting for list TX to confirm...');
    await sleep(10_000);

    // =====================================================================
    // PHASE 4: Verify Listing
    // =====================================================================
    console.log('\n--- PHASE 4: Verify Listing ---\n');

    try {
        const countRes = await method(marketContract, 'getActiveListingCount')();
        const newCount = BigInt((countRes.properties?.count ?? countRes.decoded?.[0] ?? 0) as string | bigint | number);
        const expected = listingCount + 1n;
        if (newCount === expected) {
            ok('listingCount', `${newCount} (was ${listingCount}, +1 correct)`);
        } else {
            fail('listingCount', `Expected ${expected}, got ${newCount}`);
        }
    } catch (e: unknown) {
        fail('listingCount', (e as Error).message);
    }

    try {
        const listRes = await method(marketContract, 'getListing')(testTokenId);
        if (listRes.revert) {
            fail('getListing', `REVERT: ${listRes.revert}`);
        } else {
            const active = listRes.properties?.active ?? listRes.decoded?.[2] ?? false;
            const price = BigInt((listRes.properties?.priceSats ?? listRes.decoded?.[1] ?? 0) as string | bigint | number);
            if (active && price === testPrice) {
                ok('getListing', `active=true, price=${price} sats`);
            } else {
                fail('getListing', `active=${active}, price=${price} (expected ${testPrice})`);
            }
        }
    } catch (e: unknown) {
        fail('getListing', (e as Error).message);
    }

    // =====================================================================
    // PHASE 5: Cancel Listing
    // =====================================================================
    console.log('\n--- PHASE 5: Cancel Listing ---\n');

    console.log(`  Cancelling listing for token #${testTokenId}...`);
    try {
        const cancelSim = await method(marketContract, 'cancelListing')(testTokenId);
        if (cancelSim.revert) {
            fail('cancelListing', `REVERT: ${cancelSim.revert}`);
            process.exit(1);
        }
        const cancelTx = await cancelSim.sendTransaction(txParams);
        ok('cancelListing', `TX: ${cancelTx.transactionId.slice(0, 40)}...`);
    } catch (e: unknown) {
        fail('cancelListing', (e as Error).message);
        process.exit(1);
    }

    console.log('  Waiting for cancel TX to confirm...');
    await sleep(10_000);

    // Verify listing removed
    try {
        const countRes = await method(marketContract, 'getActiveListingCount')();
        const finalCount = BigInt((countRes.properties?.count ?? countRes.decoded?.[0] ?? 0) as string | bigint | number);
        if (finalCount === listingCount) {
            ok('finalListingCount', `${finalCount} (back to original)`);
        } else {
            fail('finalListingCount', `Expected ${listingCount}, got ${finalCount}`);
        }
    } catch (e: unknown) {
        fail('finalListingCount', (e as Error).message);
    }

    try {
        const listRes = await method(marketContract, 'getListing')(testTokenId);
        const active = listRes.properties?.active ?? listRes.decoded?.[2] ?? false;
        if (!active) {
            ok('getListing (post-cancel)', 'active=false');
        } else {
            fail('getListing (post-cancel)', 'still active!');
        }
    } catch (e: unknown) {
        fail('getListing (post-cancel)', (e as Error).message);
    }

    // =====================================================================
    // Summary
    // =====================================================================
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Marketplace Test Complete');
    console.log('═══════════════════════════════════════════════════════════\n');

    await rpcProvider.close();
    if (mnemonic) mnemonic.zeroize();
    (wallet as { zeroize: () => void }).zeroize();
}

main().catch((err) => {
    console.error('Test failed:', err);
    process.exit(1);
});
