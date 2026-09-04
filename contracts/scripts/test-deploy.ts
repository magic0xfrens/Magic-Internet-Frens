#!/usr/bin/env tsx

/**
 * test-deploy.ts
 *
 * Deploy a TEST instance of MiFrens NFT, then run a full verification suite:
 * mint 1 NFT, read back all getters, verify tier/traits/tax/borrow/grace/lock.
 *
 * Defaults to testnet (free). Use --network mainnet for real BTC.
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-deploy.ts
 *   DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/test-deploy.ts --network mainnet
 *
 * Optional:
 *   --network <net>      testnet (default) | mainnet | regtest
 *   --skip-deploy        Use existing TEST_NFT_ADDRESS env var
 *   --mint-price <sats>  Override mint price (default: 144000)
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
import { getContract, JSONRpcProvider, TransactionOutputFlags } from 'opnet';
import { MiFrensAbi } from '../abis/MiFrens.abi';
import type { IOP721Contract, TransactionParameters } from 'opnet';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

interface NetworkConfig {
    rpcUrl: string;
    network: typeof networks.regtest;
    label: string;
}

const NETWORKS: Record<string, NetworkConfig> = {
    testnet: { rpcUrl: 'https://testnet.opnet.org', network: networks.opnetTestnet, label: 'Testnet' },
    mainnet: { rpcUrl: 'https://mainnet.opnet.org', network: networks.bitcoin, label: 'Mainnet' },
    regtest: { rpcUrl: 'https://regtest.opnet.org', network: networks.regtest, label: 'Regtest' },
};

function getNetworkName(): string {
    const idx = process.argv.indexOf('--network');
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : 'testnet';
}

const NET_NAME = getNetworkName();
const NET_CONFIG = NETWORKS[NET_NAME];
if (!NET_CONFIG) {
    console.error(`Unknown network "${NET_NAME}". Available: ${Object.keys(NETWORKS).join(', ')}`);
    process.exit(1);
}

const RPC_URL = NET_CONFIG.rpcUrl;
const NETWORK = NET_CONFIG.network;
const DEFAULT_MINT_PRICE = 144_000n;

const CLASS_NAMES: Record<number, string> = {
    0: 'Wizard',
    1: 'King',
    2: 'Knight',
    3: 'Apprentice',
    4: 'Peasant',
    5: 'Gnome',
    6: 'Elf',
};

const CLASS_NAMES: Record<number, string> = {
    0: 'Wizard',
    1: 'King',
    2: 'Knight',
    3: 'Apprentice',
    4: 'Peasant',
    5: 'Gnome',
};

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

function getMintPrice(): bigint {
    const idx = process.argv.indexOf('--mint-price');
    if (idx !== -1 && process.argv[idx + 1]) {
        return BigInt(process.argv[idx + 1]);
    }
    return DEFAULT_MINT_PRICE;
}

const SKIP_DEPLOY = process.argv.includes('--skip-deploy');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function ok(msg: string): void {
    console.log(`  \x1b[32m✓\x1b[0m ${msg}`);
}

function fail(msg: string): void {
    console.log(`  \x1b[31m✗\x1b[0m ${msg}`);
}

function info(msg: string): void {
    console.log(`  \x1b[36m→\x1b[0m ${msg}`);
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
    info('Broadcasting funding TX...');
    const fundingRes = await provider.broadcastTransaction(result.transaction[0], false);
    if (fundingRes && typeof fundingRes === 'object' && 'error' in fundingRes) {
        throw new Error(`Funding TX rejected: ${JSON.stringify(fundingRes)}`);
    }
    ok(`Funding TX broadcast: ${typeof fundingRes === 'string' ? fundingRes : JSON.stringify(fundingRes)}`);

    await new Promise((r) => setTimeout(r, 3000));

    info('Broadcasting deployment TX...');
    const deployRes = await provider.broadcastTransaction(result.transaction[1], false);
    if (deployRes && typeof deployRes === 'object' && 'error' in deployRes) {
        throw new Error(`Deploy TX rejected: ${JSON.stringify(deployRes)}`);
    }
    ok(`Deploy TX broadcast: ${typeof deployRes === 'string' ? deployRes : JSON.stringify(deployRes)}`);
}

function encodeNftCalldata(treasury: Address, mintPriceSats: bigint): Uint8Array {
    const writer = new BinaryWriter();
    writer.writeAddress(treasury);
    writer.writeU256(mintPriceSats);
    return writer.getBuffer();
}

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
}

// ---------------------------------------------------------------------------
// Phase 1: Deploy
// ---------------------------------------------------------------------------

async function deploy(
    wallet: ReturnType<Mnemonic['deriveOPWallet']>,
    limitedProvider: OPNetLimitedProvider,
    rpcProvider: JSONRpcProvider,
    mintPrice: bigint,
): Promise<string> {
    console.log('\n═══ Phase 1: Deploy Test NFT Contract ═══\n');

    const buildDir = join(__dirname, '../build');
    const wasmPath = join(buildDir, 'nft.wasm');
    if (!fs.existsSync(wasmPath)) {
        throw new Error(`nft.wasm not found at ${wasmPath}. Run: npm run build:nft`);
    }

    const nftWasm = new Uint8Array(fs.readFileSync(wasmPath));
    info(`Loaded nft.wasm (${(nftWasm.length / 1024).toFixed(1)} KB)`);
    info(`Treasury: ${wallet.p2tr}`);
    info(`Mint price: ${mintPrice} sats`);

    const utxos = await fetchUtxos(limitedProvider, wallet.p2tr);
    info(`Found ${utxos.length} UTXOs`);

    if (utxos.length === 0) {
        throw new Error('No UTXOs available. Fund the deployer address first.');
    }

    info('Fetching challenge from node...');
    const challenge = await rpcProvider.getChallenge();
    ok(`Challenge epoch #${challenge.epochNumber}, difficulty ${challenge.difficulty}`);

    const factory = new TransactionFactory();
    const nftResult = await factory.signDeployment({
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        network: NETWORK,
        from: wallet.p2tr,
        bytecode: nftWasm,
        calldata: new Uint8Array(0),  // no constructor args — contract hardcodes them
        challenge,
        utxos,
        feeRate: 10,
        priorityFee: 10_000n,
        gasSatFee: 10_000n,
        revealMLDSAPublicKey: true,
        linkMLDSAPublicKeyToAddress: true,
    });

    info('Broadcasting deployment...');
    await broadcastDeployment(limitedProvider, nftResult);

    const contractAddress = nftResult.contractAddress;
    ok(`Deployed: ${contractAddress}`);

    // Save to test deployment file
    const deploymentsDir = join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    const outputPath = join(deploymentsDir, `${NET_NAME}-test.json`);
    fs.writeFileSync(outputPath, JSON.stringify({
        network: `${NET_NAME}-test`,
        deployedAt: new Date().toISOString(),
        deployer: wallet.p2tr,
        mintPriceSats: Number(mintPrice),
        contracts: { MIFRENS_TEST: contractAddress },
    }, null, 2));
    info(`Saved to ${outputPath}`);

    return contractAddress;
}

// ---------------------------------------------------------------------------
// Phase 2: Wait for contract to be indexed
// ---------------------------------------------------------------------------

function createContract(
    rpcProvider: JSONRpcProvider,
    contractAddress: string,
    sender?: Address,
): ReturnType<typeof getContract<IOP721Contract>> {
    const args: Parameters<typeof getContract<IOP721Contract>> = [
        Address.fromString(contractAddress),
        MiFrensAbi,
        rpcProvider,
        NETWORK,
    ];
    if (sender) args.push(sender);
    return getContract<IOP721Contract>(...args);
}

async function waitForContract(
    rpcProvider: JSONRpcProvider,
    contractAddress: string,
): Promise<void> {
    console.log('\n═══ Phase 2: Wait for Contract Indexing ═══\n');

    const maxAttempts = 120;
    const pollInterval = 10000;
    for (let i = 1; i <= maxAttempts; i++) {
        try {
            // No sender needed for view-only polling
            const contract = createContract(rpcProvider, contractAddress);
            const result = await contract.execute('totalMinted', []);
            if (!result.revert) {
                ok(`Contract indexed after ${i} attempt(s) (~${(i * pollInterval / 1000).toFixed(0)}s)`);
                return;
            }
            if (i === 1 || i % 10 === 0) {
                info(`Poll attempt ${i}: call reverted — ${result.revert}`);
            }
        } catch (err: unknown) {
            if (i === 1 || i % 10 === 0) {
                const msg = err instanceof Error ? err.message : String(err);
                info(`Poll attempt ${i}: ${msg}`);
            }
        }

        const elapsed = i * pollInterval / 1000;
        process.stdout.write(`  Waiting for block confirmation... ${elapsed.toFixed(0)}s (${i}/${maxAttempts})\r`);
        await sleep(pollInterval);
    }

    throw new Error('Contract not indexed after max attempts');
}

// ---------------------------------------------------------------------------
// Phase 3: Read-only verification (pre-mint)
// ---------------------------------------------------------------------------

async function verifyPreMint(
    contract: ReturnType<typeof getContract<IOP721Contract>>,
    mintPrice: bigint,
    treasuryAddress: string,
): Promise<void> {
    console.log('\n═══ Phase 3: Pre-Mint Verification ═══\n');

    let passed = 0;
    let failed = 0;

    // totalMinted = 0
    const minted = await contract.execute('totalMinted', []);
    if (!minted.revert && (minted.decoded?.[0] as bigint) === 0n) {
        ok('totalMinted() = 0'); passed++;
    } else {
        fail(`totalMinted() unexpected: ${minted.revert ?? minted.decoded?.[0]}`); failed++;
    }

    // getMintPrice
    const price = await contract.execute('getMintPrice', []);
    if (!price.revert && (price.decoded?.[0] as bigint) === mintPrice) {
        ok(`getMintPrice() = ${mintPrice} sats`); passed++;
    } else {
        fail(`getMintPrice() unexpected: ${price.revert ?? price.decoded?.[0]}`); failed++;
    }

    // getTreasury
    const treasury = await contract.execute('getTreasury', []);
    if (!treasury.revert) {
        ok(`getTreasury() = ${treasury.decoded?.[0]}`); passed++;
    } else {
        fail(`getTreasury() reverted: ${treasury.revert}`); failed++;
    }

    // name / symbol
    const name = await contract.execute('name', []);
    if (!name.revert) {
        ok(`name() = "${name.decoded?.[0]}"`); passed++;
    } else {
        fail(`name() reverted: ${name.revert}`); failed++;
    }

    const symbol = await contract.execute('symbol', []);
    if (!symbol.revert) {
        ok(`symbol() = "${symbol.decoded?.[0]}"`); passed++;
    } else {
        fail(`symbol() reverted: ${symbol.revert}`); failed++;
    }

    // maxSupply
    const maxSupply = await contract.execute('maxSupply', []);
    if (!maxSupply.revert && (maxSupply.decoded?.[0] as bigint) === 777n) {
        ok('maxSupply() = 777'); passed++;
    } else {
        fail(`maxSupply() unexpected: ${maxSupply.revert ?? maxSupply.decoded?.[0]}`); failed++;
    }

    console.log(`\n  Results: ${passed} passed, ${failed} failed`);
    if (failed > 0) {
        throw new Error('Pre-mint verification failed');
    }
}

// ---------------------------------------------------------------------------
// Phase 4: Mint 1 test NFT
// ---------------------------------------------------------------------------

async function mintTestNFT(
    contract: ReturnType<typeof getContract<IOP721Contract>>,
    wallet: ReturnType<Mnemonic['deriveOPWallet']>,
    treasuryBech32: string,
    treasuryAddr: Address,
    mintPrice: bigint,
): Promise<bigint> {
    console.log('\n═══ Phase 4: Mint 1 Test NFT ═══\n');

    // Set transaction details for simulation
    contract.setTransactionDetails({
        inputs: [],
        outputs: [
            {
                to: treasuryBech32,
                value: mintPrice,
                index: 1,
                scriptPubKey: undefined,
                flags: TransactionOutputFlags.hasTo,
            },
        ],
    });

    info('Simulating mintNFT()...');
    const sim = await contract.execute('mintNFT', []);

    if (sim.revert) {
        throw new Error(`mintNFT simulation reverted: ${sim.revert}`);
    }

    ok(`Simulation OK (estimated gas: ${sim.estimatedSatGas})`);

    info('Broadcasting mint transaction...');
    const txParams: TransactionParameters = {
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        refundTo: wallet.p2tr,
        maximumAllowedSatToSpend: 300_000n,
        feeRate: 10,
        network: NETWORK,
        revealMLDSAPublicKey: true,
        linkMLDSAPublicKeyToAddress: true,
        extraOutputs: [
            {
                address: treasuryBech32,
                value: mintPrice,
            },
        ],
    };

    const receipt = await sim.sendTransaction(txParams);
    const tokenId = sim.decoded?.[0] as bigint ?? 0n;

    ok(`Minted token #${tokenId} — TX: ${receipt.transactionId}`);

    return tokenId;
}

// ---------------------------------------------------------------------------
// Phase 5: Post-mint verification
// ---------------------------------------------------------------------------

async function verifyPostMint(
    contract: ReturnType<typeof getContract<IOP721Contract>>,
    tokenId: bigint,
    minterAddr: Address,
): Promise<void> {
    console.log('\n═══ Phase 5: Post-Mint Verification ═══\n');

    // Wait for mint TX to be indexed
    info('Waiting for mint to be indexed...');
    await sleep(10000);

    let passed = 0;
    let failed = 0;

    // totalMinted = 1
    const minted = await contract.execute('totalMinted', []);
    const count = minted.decoded?.[0] as bigint ?? 0n;
    if (!minted.revert && count >= 1n) {
        ok(`totalMinted() = ${count}`); passed++;
    } else {
        fail(`totalMinted() expected >= 1, got: ${minted.revert ?? count}`); failed++;
    }

    // ownerOf(tokenId) = minter
    const owner = await contract.execute('ownerOf', [tokenId]);
    if (!owner.revert) {
        ok(`ownerOf(${tokenId}) = ${owner.decoded?.[0]}`); passed++;
    } else {
        fail(`ownerOf() reverted: ${owner.revert}`); failed++;
    }

    // balanceOf(minter) >= 1
    const balance = await contract.execute('balanceOf', [
        minterAddr,
    ]);
    if (!balance.revert && (balance.decoded?.[0] as bigint) >= 1n) {
        ok(`balanceOf(minter) = ${balance.decoded?.[0]}`); passed++;
    } else {
        fail(`balanceOf() unexpected: ${balance.revert ?? balance.decoded?.[0]}`); failed++;
    }

    // getTokenTraits(tokenId) — verify class assignment
    const traitsCheck = await contract.execute('getTokenTraits', [tokenId]);
    if (!traitsCheck.revert) {
        const classNum = Number(traitsCheck.decoded?.[0] as bigint);
        ok(`getTokenTraits(${tokenId}).class = ${classNum} (${CLASS_NAMES[classNum] ?? 'Unknown'})`); passed++;
    } else {
        fail(`getTokenTraits() reverted: ${traitsCheck.revert}`); failed++;
    }

    // getTaxRate(tokenId)
    const tax = await contract.execute('getTaxRate', [tokenId]);
    if (!tax.revert) {
        const bps = Number(tax.decoded?.[0] as bigint);
        ok(`getTaxRate(${tokenId}) = ${bps} bps (${(bps / 100).toFixed(2)}%)`); passed++;
    } else {
        fail(`getTaxRate() reverted: ${tax.revert}`); failed++;
    }

    // getMaxBorrow(tokenId)
    const borrow = await contract.execute('getMaxBorrow', [tokenId]);
    if (!borrow.revert) {
        ok(`getMaxBorrow(${tokenId}) = ${borrow.decoded?.[0]}`); passed++;
    } else {
        fail(`getMaxBorrow() reverted: ${borrow.revert}`); failed++;
    }

    // getLiquidationGrace(tokenId)
    const grace = await contract.execute('getLiquidationGrace', [tokenId]);
    if (!grace.revert) {
        ok(`getLiquidationGrace(${tokenId}) = ${grace.decoded?.[0]} blocks`); passed++;
    } else {
        fail(`getLiquidationGrace() reverted: ${grace.revert}`); failed++;
    }

    // getTokenTraits(tokenId)
    const traits = await contract.execute('getTokenTraits', [tokenId]);
    if (!traits.revert) {
        const classIdx = Number(traits.decoded?.[0] as bigint);
        const bodyIdx = Number(traits.decoded?.[1] as bigint);
        const faceIdx = Number(traits.decoded?.[2] as bigint);
        const itemIdx = Number(traits.decoded?.[3] as bigint);
        const tierFromTraits = Number(traits.decoded?.[4] as bigint);
        ok(`getTokenTraits(${tokenId}) → class=${classIdx} (${CLASS_NAMES[classIdx] ?? '?'}), body=${bodyIdx}, face=${faceIdx}, item=${itemIdx}, tier=${tierFromTraits}`);
        passed++;
    } else {
        fail(`getTokenTraits() reverted: ${traits.revert}`); failed++;
    }

    // isLocked(tokenId) = false
    const locked = await contract.execute('isLocked', [tokenId]);
    if (!locked.revert && (locked.decoded?.[0] as boolean) === false) {
        ok(`isLocked(${tokenId}) = false`); passed++;
    } else {
        fail(`isLocked() unexpected: ${locked.revert ?? locked.decoded?.[0]}`); failed++;
    }

    // getHolderTaxRate(minter)
    const holderTax = await contract.execute('getHolderTaxRate', [
        minterAddr,
    ]);
    if (!holderTax.revert) {
        const bps = Number(holderTax.decoded?.[0] as bigint);
        ok(`getHolderTaxRate(minter) = ${bps} bps (${(bps / 100).toFixed(2)}%)`); passed++;
    } else {
        fail(`getHolderTaxRate() reverted: ${holderTax.revert}`); failed++;
    }

    // getTokenTraitKeys(tokenId)
    const traitKeys = await contract.execute('getTokenTraitKeys', [tokenId]);
    if (!traitKeys.revert) {
        ok(`getTokenTraitKeys(${tokenId}) → body=${traitKeys.decoded?.[0]}, face=${traitKeys.decoded?.[1]}, item=${traitKeys.decoded?.[2]}`);
        passed++;
    } else {
        fail(`getTokenTraitKeys() reverted: ${traitKeys.revert}`); failed++;
    }

    // tokenURI(tokenId) — should return baseURI fallback (palette not inscribed)
    const uri = await contract.execute('tokenURI', [tokenId]);
    if (!uri.revert) {
        const uriStr = uri.decoded?.[0] as string;
        const preview = uriStr.length > 80 ? uriStr.slice(0, 80) + '...' : uriStr;
        ok(`tokenURI(${tokenId}) = ${preview}`); passed++;
    } else {
        fail(`tokenURI() reverted: ${uri.revert}`); failed++;
    }

    console.log(`\n  Results: ${passed} passed, ${failed} failed`);

    if (failed > 0) {
        console.log('\n  ⚠ Some checks failed — review output above.');
    } else {
        console.log('\n  All checks passed — contract is mainnet-ready.');
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    console.log('╔══════════════════════════════════════════╗');
    console.log(`║   MiFrens NFT — ${NET_CONFIG.label} Test Deploy${''.padEnd(Math.max(0, 8 - NET_CONFIG.label.length))}║`);
    console.log('╚══════════════════════════════════════════╝');

    const mnemonicPhrase = process.env.DEPLOYER_MNEMONIC;
    if (!mnemonicPhrase) {
        console.error('DEPLOYER_MNEMONIC environment variable is required');
        process.exit(1);
    }

    const mintPrice = getMintPrice();

    console.log(`\n  Network:    ${NET_CONFIG.label} (${RPC_URL})`);
    console.log(`  Mint price: ${mintPrice} sats`);
    console.log(`  Mode:       ${SKIP_DEPLOY ? 'verify only (--skip-deploy)' : 'deploy + verify'}`);

    // --- Setup wallet ---
    const mnemonic = new Mnemonic(mnemonicPhrase, '', NETWORK, MLDSASecurityLevel.LEVEL2);
    const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
    console.log(`  Deployer:   ${wallet.p2tr}`);

    const limitedProvider = new OPNetLimitedProvider(RPC_URL);
    const rpcProvider = new JSONRpcProvider({ url: RPC_URL, network: NETWORK });

    try {
        // --- Phase 1: Deploy ---
        let contractAddress: string;

        if (SKIP_DEPLOY) {
            contractAddress = process.env.TEST_NFT_ADDRESS ?? '';
            if (!contractAddress) {
                // Try loading from <network>-test.json
                const testDeployPath = join(__dirname, `../deployments/${NET_NAME}-test.json`);
                if (fs.existsSync(testDeployPath)) {
                    const data = JSON.parse(fs.readFileSync(testDeployPath, 'utf-8'));
                    contractAddress = data.contracts.MIFRENS_TEST;
                }
            }
            if (!contractAddress) {
                throw new Error(`--skip-deploy requires TEST_NFT_ADDRESS env var or deployments/${NET_NAME}-test.json`);
            }
            info(`Using existing test contract: ${contractAddress}`);
        } else {
            contractAddress = await deploy(wallet, limitedProvider, rpcProvider, mintPrice);
        }

        // --- Phase 2: Wait for indexing (no sender needed for view calls) ---
        await waitForContract(rpcProvider, contractAddress);

        // --- Phase 3: Pre-mint checks (view-only, no sender needed) ---
        const viewContract = createContract(rpcProvider, contractAddress);
        await verifyPreMint(viewContract, mintPrice, wallet.p2tr);

        // --- Phase 4: Mint (needs sender for simulation) ---
        const mintContract = createContract(rpcProvider, contractAddress, wallet.address);
        const tokenId = await mintTestNFT(mintContract, wallet, wallet.p2tr, wallet.address, mintPrice);

        // --- Phase 5: Post-mint checks (view-only) ---
        await verifyPostMint(viewContract, tokenId, wallet.address);

        // --- Summary ---
        console.log('\n╔══════════════════════════════════════════╗');
        console.log('║            Test Complete                  ║');
        console.log('╚══════════════════════════════════════════╝');
        console.log(`\n  Test contract: ${contractAddress}`);
        console.log(`  Minted token:  #${tokenId}`);
        console.log(`  Deployer:      ${wallet.p2tr}`);
        console.log('\n  This is a TEST deployment. When ready for the real one:');
        console.log('  DEPLOYER_MNEMONIC="..." npx tsx contracts/scripts/deploy-cauldron.ts --network mainnet\n');

    } finally {
        await rpcProvider.close();
        mnemonic.zeroize();
        wallet.zeroize();
    }
}

main().catch((err) => {
    console.error('\nTest deployment failed:', err);
    process.exit(1);
});
