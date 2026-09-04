#!/usr/bin/env tsx

/**
 * setup-liquidity-test.ts
 *
 * Configures CauldronToken (MIF) for MotoSwap, adds liquidity, and runs
 * a test swap to verify tax collection works.
 *
 * Prerequisites:
 *   - MIF token deployed (address in deployments/<network>.json as MIF_TOKEN)
 *   - Deployer already holds MIF tokens (token is NOT mintable post-deploy)
 *   - Deployer already holds WBTC
 *
 * Steps:
 *   1. Configure CauldronToken (setRouter, setWbtc, setSwapThreshold)
 *   2. Approve MotoSwap Router for MIF
 *   3. Approve MotoSwap Router for WBTC
 *   4. Add MIF/WBTC liquidity on MotoSwap
 *   5. Test swap — sell MIF for WBTC (triggers tax)
 *   6. Verify accumulated tax > 0
 *
 * Usage:
 *   DEPLOYER_MNEMONIC="..." \
 *   MOTOSWAP_ROUTER="0x..." \
 *   WBTC_ADDRESS="0x..." \
 *   npx tsx contracts/scripts/setup-liquidity-test.ts --network testnet [--from-step N]
 *
 * Optional env vars:
 *   LP_MIF_AMOUNT    — MIF for liquidity pool (default: 10000e18)
 *   LP_WBTC_AMOUNT   — WBTC for liquidity pool (default: 1000000 = 0.01 WBTC at 8 decimals)
 *   SWAP_TEST_AMOUNT — MIF to swap in test (default: 1000e18)
 *   SWAP_THRESHOLD   — auto-swap threshold (default: 100e18)
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
import {
    getContract,
    JSONRpcProvider,
    OP_20_ABI,
    MOTOSWAP_ROUTER_ABI,
} from 'opnet';
import type {
    IOP20Contract,
    IMotoswapRouterContract,
    IContract,
    TransactionParameters,
} from 'opnet';

import { CauldronTokenAbi } from '../abis/CauldronToken.abi';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const TX_DELAY_MS = 5_000;

const E18 = 10n ** 18n;

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

function formatMIF(amount: bigint): string {
    const whole = amount / E18;
    const frac = amount % E18;
    if (frac === 0n) return `${whole} MIF`;
    return `${whole}.${frac.toString().padStart(18, '0').replace(/0+$/, '')} MIF`;
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

    const routerAddressRaw = process.env.MOTOSWAP_ROUTER;
    if (!routerAddressRaw) {
        console.error('MOTOSWAP_ROUTER environment variable is required');
        process.exit(1);
    }

    const wbtcAddressRaw = process.env.WBTC_ADDRESS;
    if (!wbtcAddressRaw) {
        console.error('WBTC_ADDRESS environment variable is required');
        process.exit(1);
    }

    // Load deployment data
    const deploymentPath = join(__dirname, '../deployments', `${networkName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        console.error(`No deployment found at ${deploymentPath}`);
        console.error('Deploy the MIF token first.');
        process.exit(1);
    }

    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
    const mifAddressRaw: string = deployment.contracts.MIF_TOKEN;
    if (!mifAddressRaw) {
        console.error('MIF_TOKEN address not found in deployment file');
        process.exit(1);
    }

    // Configurable amounts
    const LP_MIF_AMOUNT = process.env.LP_MIF_AMOUNT ? BigInt(process.env.LP_MIF_AMOUNT) : 10_000n * E18;
    const LP_WBTC_AMOUNT = process.env.LP_WBTC_AMOUNT ? BigInt(process.env.LP_WBTC_AMOUNT) : 1_000_000n;
    const SWAP_TEST_AMOUNT = process.env.SWAP_TEST_AMOUNT ? BigInt(process.env.SWAP_TEST_AMOUNT) : 1_000n * E18;
    const SWAP_THRESHOLD = process.env.SWAP_THRESHOLD ? BigInt(process.env.SWAP_THRESHOLD) : 100n * E18;

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  MIF — Setup Liquidity & Test Tax');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Network:        ${networkName}`);
    console.log(`  MIF Token:      ${mifAddressRaw}`);
    console.log(`  MotoSwap Router: ${routerAddressRaw}`);
    console.log(`  WBTC:           ${wbtcAddressRaw}`);
    console.log(`  LP MIF:         ${LP_MIF_AMOUNT / E18} MIF`);
    console.log(`  LP WBTC:        ${LP_WBTC_AMOUNT} (raw units)`);
    console.log(`  Swap test:      ${SWAP_TEST_AMOUNT / E18} MIF`);
    console.log(`  Swap threshold: ${SWAP_THRESHOLD / E18} MIF`);
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
    const mifAddr = await resolveContractAddress(rpcProvider, mifAddressRaw);
    console.log('  MIF resolved');
    const routerAddr = await resolveContractAddress(rpcProvider, routerAddressRaw);
    console.log('  MotoSwap Router resolved');
    const wbtcAddr = await resolveContractAddress(rpcProvider, wbtcAddressRaw);
    console.log('  WBTC resolved\n');

    // --- Contracts ---
    const mifContract = getContract<IContract>(
        mifAddr,
        CauldronTokenAbi,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const mifOp20 = getContract<IOP20Contract>(
        mifAddr,
        OP_20_ABI,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const wbtcOp20 = getContract<IOP20Contract>(
        wbtcAddr,
        OP_20_ABI,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const router = getContract<IMotoswapRouterContract>(
        routerAddr,
        MOTOSWAP_ROUTER_ABI,
        rpcProvider,
        netConfig.network,
        wallet.address,
    );

    const startStep = getStartStep();

    // ===================================================================
    // STEP 1: Configure CauldronToken (setRouter, setWbtc, setSwapThreshold)
    // ===================================================================
    if (startStep <= 1) {
        console.log('STEP 1: Configuring CauldronToken...');

        // 1a. setRouter
        console.log('  1a. setRouter...');
        const setRouterSim = await method(mifContract, 'setRouter')(routerAddr);
        if (setRouterSim.revert) {
            console.error(`  setRouter reverted: ${setRouterSim.revert}`);
            process.exit(1);
        }
        const setRouterReceipt = await setRouterSim.sendTransaction(txParams);
        console.log(`  TX: ${setRouterReceipt.transactionId.slice(0, 32)}...`);
        await sleep(TX_DELAY_MS);

        // 1b. setWbtc
        console.log('  1b. setWbtc...');
        const setWbtcSim = await method(mifContract, 'setWbtc')(wbtcAddr);
        if (setWbtcSim.revert) {
            console.error(`  setWbtc reverted: ${setWbtcSim.revert}`);
            process.exit(1);
        }
        const setWbtcReceipt = await setWbtcSim.sendTransaction(txParams);
        console.log(`  TX: ${setWbtcReceipt.transactionId.slice(0, 32)}...`);
        await sleep(TX_DELAY_MS);

        // 1c. setSwapThreshold
        console.log(`  1c. setSwapThreshold (${SWAP_THRESHOLD / E18} MIF)...`);
        const setThresholdSim = await method(mifContract, 'setSwapThreshold')(SWAP_THRESHOLD);
        if (setThresholdSim.revert) {
            console.error(`  setSwapThreshold reverted: ${setThresholdSim.revert}`);
            process.exit(1);
        }
        const setThresholdReceipt = await setThresholdSim.sendTransaction(txParams);
        console.log(`  TX: ${setThresholdReceipt.transactionId.slice(0, 32)}...`);
        await sleep(TX_DELAY_MS);
    } else {
        console.log('STEP 1: Skipped (--from-step)');
    }

    // ===================================================================
    // STEP 2: Approve Router for MIF
    // ===================================================================
    if (startStep <= 2) {
        console.log('\nSTEP 2: Approving MotoSwap Router for MIF...');

        // Check MIF balance first
        const mifBalResult = await mifOp20.balanceOf(wallet.address);
        const mifBalance = mifBalResult.properties.balance;
        console.log(`  MIF balance: ${formatMIF(mifBalance)}`);
        if (mifBalance === 0n) {
            console.error('  Deployer has no MIF tokens. Acquire MIF before running this script.');
            process.exit(1);
        }

        const approveAmount = LP_MIF_AMOUNT + SWAP_TEST_AMOUNT;
        const approveSim = await mifOp20.approve(routerAddr, approveAmount);
        if (approveSim.revert) {
            console.error(`  approve reverted: ${approveSim.revert}`);
            process.exit(1);
        }
        const approveReceipt = await approveSim.sendTransaction(txParams);
        console.log(`  Approved ${formatMIF(approveAmount)} for Router`);
        console.log(`  TX: ${approveReceipt.transactionId.slice(0, 32)}...`);
        await sleep(TX_DELAY_MS);
    } else {
        console.log('\nSTEP 2: Skipped (--from-step)');
    }

    // ===================================================================
    // STEP 3: Approve Router for WBTC
    // ===================================================================
    if (startStep <= 3) {
        console.log('\nSTEP 3: Approving MotoSwap Router for WBTC...');

        const wbtcBalResult = await wbtcOp20.balanceOf(wallet.address);
        const wbtcBalance = wbtcBalResult.properties.balance;
        console.log(`  WBTC balance: ${wbtcBalance}`);
        if (wbtcBalance === 0n) {
            console.error('  WARNING: Deployer has 0 WBTC. addLiquidity will fail.');
            console.error('  Acquire WBTC before running step 4.');
        }

        const approveSim = await wbtcOp20.approve(routerAddr, LP_WBTC_AMOUNT);
        if (approveSim.revert) {
            console.error(`  approve reverted: ${approveSim.revert}`);
            process.exit(1);
        }
        const approveReceipt = await approveSim.sendTransaction(txParams);
        console.log(`  Approved ${LP_WBTC_AMOUNT} WBTC (raw) for Router`);
        console.log(`  TX: ${approveReceipt.transactionId.slice(0, 32)}...`);
        await sleep(TX_DELAY_MS);
    } else {
        console.log('\nSTEP 3: Skipped (--from-step)');
    }

    // ===================================================================
    // STEP 4: Add Liquidity (MIF/WBTC)
    // ===================================================================
    if (startStep <= 4) {
        console.log('\nSTEP 4: Adding MIF/WBTC liquidity on MotoSwap...');
        console.log(`  MIF:  ${LP_MIF_AMOUNT / E18}`);
        console.log(`  WBTC: ${LP_WBTC_AMOUNT} (raw units)`);

        const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
        const walletAddr = wallet.address;

        const addLiqSim = await router.addLiquidity(
            mifAddr,
            wbtcAddr,
            LP_MIF_AMOUNT,
            LP_WBTC_AMOUNT,
            0n,         // amountAMin: accept any
            0n,         // amountBMin: accept any
            walletAddr,
            deadline,
        );
        if (addLiqSim.revert) {
            console.error(`  addLiquidity reverted: ${addLiqSim.revert}`);
            process.exit(1);
        }
        const addLiqReceipt = await addLiqSim.sendTransaction(txParams);
        console.log(`  TX: ${addLiqReceipt.transactionId.slice(0, 32)}...`);

        if (addLiqSim.properties) {
            const { amountA, amountB, liquidity } = addLiqSim.properties;
            console.log(`  Actual MIF deposited:  ${amountA}`);
            console.log(`  Actual WBTC deposited: ${amountB}`);
            console.log(`  LP tokens received:    ${liquidity}`);
        }
        await sleep(TX_DELAY_MS);
    } else {
        console.log('\nSTEP 4: Skipped (--from-step)');
    }

    // ===================================================================
    // STEP 5: Test swap — sell MIF for WBTC
    // ===================================================================
    if (startStep <= 5) {
        console.log('\nSTEP 5: Test swap — selling MIF for WBTC...');
        console.log(`  Swapping ${formatMIF(SWAP_TEST_AMOUNT)} → WBTC`);

        // Tax preview (3% default for non-holder, up to 0% for wizard)
        console.log('  Expected tax: up to 3% = ~' + formatMIF(SWAP_TEST_AMOUNT * 300n / 10000n));

        const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
        const walletAddr = wallet.address;

        const swapSim = await router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            SWAP_TEST_AMOUNT,
            0n,                         // amountOutMin: accept any
            [mifAddr, wbtcAddr],        // path: MIF → WBTC
            walletAddr,
            deadline,
        );
        if (swapSim.revert) {
            console.error(`  swap reverted: ${swapSim.revert}`);
            process.exit(1);
        }
        const swapReceipt = await swapSim.sendTransaction(txParams);
        console.log(`  Swap TX: ${swapReceipt.transactionId.slice(0, 32)}...`);
        await sleep(TX_DELAY_MS);
    } else {
        console.log('\nSTEP 5: Skipped (--from-step)');
    }

    // ===================================================================
    // STEP 6: Verify tax accumulation
    // ===================================================================
    if (startStep <= 6) {
        console.log('\nSTEP 6: Verifying accumulated tax...');

        const taxSim = await method(mifContract, 'getAccumulatedTax')();
        if (taxSim.revert) {
            console.error(`  getAccumulatedTax reverted: ${taxSim.revert}`);
        } else if (taxSim.decoded && taxSim.decoded.length > 0) {
            const accumulated = taxSim.decoded[0] as bigint;
            console.log(`  Accumulated tax: ${formatMIF(accumulated)}`);
            if (accumulated > 0n) {
                console.log('  Tax collection confirmed!');
                if (accumulated === 0n) {
                    console.log('  (Tax may have already been auto-swapped to WBTC if threshold was met)');
                }
            } else {
                console.log('  Tax is 0 — either:');
                console.log('    a) Auto-swap already triggered (threshold met → tax sent to treasury as WBTC)');
                console.log('    b) Sender was tax-exempt (Wizard-tier NFT holder → 0% tax)');
                console.log('    c) Swap did not go through the taxed _transfer path');
            }
        }
    } else {
        console.log('\nSTEP 6: Skipped (--from-step)');
    }

    // ===================================================================
    // Summary
    // ===================================================================
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('  Liquidity & Tax Test Complete');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  MIF Token:       ${mifAddressRaw}`);
    console.log(`  MotoSwap Router: ${routerAddressRaw}`);
    console.log(`  WBTC:            ${wbtcAddressRaw}`);
    console.log(`  Deployer:        ${wallet.p2tr}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // --- Cleanup ---
    await rpcProvider.close();
    mnemonic.zeroize();
    wallet.zeroize();
}

main().catch((err) => {
    console.error('Setup failed:', err);
    process.exit(1);
});
