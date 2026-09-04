#!/usr/bin/env tsx

/**
 * SVG Size Limit Tester
 *
 * Probes the deployed SVGSizeTest contract to find the maximum RPC response
 * size for each return method. Uses simulation (provider.call) — no on-chain
 * transactions needed.
 *
 * Usage:
 *   npx tsx contracts/scripts/test-svg-limits.ts --network testnet
 *   npx tsx contracts/scripts/test-svg-limits.ts --network testnet --address <contract>
 *
 * Options:
 *   --network <net>    regtest (default) | testnet | mainnet
 *   --address <addr>   Override contract address (otherwise reads from deployments/<net>.json)
 *   --phase <1|2|3>    Run only a specific phase (default: all)
 */

import * as fs from 'fs';
import { join } from 'path';

import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import type { IContract } from 'opnet';
import { SVGSizeTestAbi } from '../abis/SVGSizeTest.abi';

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

function getArg(flag: string): string | undefined {
    const idx = process.argv.indexOf(flag);
    return idx !== -1 && process.argv[idx + 1] ? process.argv[idx + 1] : undefined;
}

const NET_NAME = getArg('--network') ?? 'regtest';
const NET_CONFIG = NETWORKS[NET_NAME];
if (!NET_CONFIG) {
    console.error(`Unknown network "${NET_NAME}". Available: ${Object.keys(NETWORKS).join(', ')}`);
    process.exit(1);
}

// Test sizes to probe (bytes)
const TEST_SIZES: number[] = [
    100, 200, 500, 1000, 1500, 2000, 2048, 3000, 4000, 5000,
    8000, 10000, 15000, 20000, 30000, 50000, 75000, 100000,
];

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

/** Call a contract method by name (opnet proxy pattern) */
type ContractCallResult = {
    revert?: string;
    decoded?: unknown[];
};

type ContractCallFn = (...args: unknown[]) => Promise<ContractCallResult>;

function callMethod(contract: IContract, name: string): ContractCallFn {
    return (contract as unknown as Record<string, ContractCallFn>)[name];
}

interface TestResult {
    size: number;
    success: boolean;
    responseLen: number;
    durationMs: number;
    error?: string;
}

function printResultsTable(label: string, results: TestResult[]): void {
    console.log(`\n  ┌─────────────────────────────────────────────────────────────────┐`);
    console.log(`  │ ${label.padEnd(63)} │`);
    console.log(`  ├──────────────┬──────────┬──────────────────┬─────────────────────┤`);
    console.log(`  │ Input Size   │ Status   │ Response Length   │ Duration (ms)       │`);
    console.log(`  ├──────────────┼──────────┼──────────────────┼─────────────────────┤`);

    let lastSuccess: number = 0;
    for (const r of results) {
        const sizeStr = r.size.toLocaleString().padStart(10);
        const status = r.success ? '\x1b[32mOK\x1b[0m    ' : '\x1b[31mFAIL\x1b[0m  ';
        const respLen = r.success ? r.responseLen.toLocaleString().padStart(14) : (r.error ?? 'error').padStart(14);
        const dur = r.durationMs.toFixed(0).padStart(17);
        console.log(`  │ ${sizeStr}   │ ${status} │ ${respLen}   │ ${dur}   │`);
        if (r.success) lastSuccess = r.size;
    }

    console.log(`  └──────────────┴──────────┴──────────────────┴─────────────────────┘`);
    console.log(`  Max successful input size: ${lastSuccess.toLocaleString()} bytes\n`);
}

// ---------------------------------------------------------------------------
// Test Phases
// ---------------------------------------------------------------------------

async function phaseRawString(
    contract: IContract,
): Promise<TestResult[]> {
    console.log('\n═══ Phase 1: Raw String Return (testReturn) ═══\n');
    info('Testing raw string return of increasing sizes...');

    const results: TestResult[] = [];

    for (const size of TEST_SIZES) {
        const start = Date.now();
        try {
            const result = await callMethod(contract, 'testReturn')(BigInt(size));
            const duration = Date.now() - start;

            if (result.revert) {
                results.push({ size, success: false, responseLen: 0, durationMs: duration, error: String(result.revert).slice(0, 40) });
                fail(`${size.toLocaleString()} bytes → reverted: ${String(result.revert).slice(0, 60)}`);
            } else {
                const decoded = result.decoded?.[0] as string ?? '';
                results.push({ size, success: true, responseLen: decoded.length, durationMs: duration });
                ok(`${size.toLocaleString()} bytes → response ${decoded.length.toLocaleString()} chars (${duration}ms)`);
            }
        } catch (err: unknown) {
            const duration = Date.now() - start;
            const msg = err instanceof Error ? err.message : String(err);
            results.push({ size, success: false, responseLen: 0, durationMs: duration, error: msg.slice(0, 40) });
            fail(`${size.toLocaleString()} bytes → error: ${msg.slice(0, 80)}`);
        }

        // Brief pause between calls to avoid rate limiting
        await new Promise((r) => setTimeout(r, 500));
    }

    printResultsTable('Phase 1: Raw String (testReturn)', results);
    return results;
}

async function phaseDataURI(
    contract: IContract,
): Promise<TestResult[]> {
    console.log('\n═══ Phase 2: JSON+SVG Data URI (testDataURI) ═══\n');
    info('Testing full data:application/json;base64,... tokenURI...');
    info('Note: base64 encoding adds ~33% overhead to SVG size');

    const results: TestResult[] = [];

    for (const size of TEST_SIZES) {
        const start = Date.now();
        try {
            const result = await callMethod(contract, 'testDataURI')(BigInt(size));
            const duration = Date.now() - start;

            if (result.revert) {
                results.push({ size, success: false, responseLen: 0, durationMs: duration, error: String(result.revert).slice(0, 40) });
                fail(`SVG ${size.toLocaleString()} bytes → reverted: ${String(result.revert).slice(0, 60)}`);
            } else {
                const decoded = result.decoded?.[0] as string ?? '';
                results.push({ size, success: true, responseLen: decoded.length, durationMs: duration });
                ok(`SVG ${size.toLocaleString()} bytes → URI ${decoded.length.toLocaleString()} chars (${duration}ms)`);
            }
        } catch (err: unknown) {
            const duration = Date.now() - start;
            const msg = err instanceof Error ? err.message : String(err);
            results.push({ size, success: false, responseLen: 0, durationMs: duration, error: msg.slice(0, 40) });
            fail(`SVG ${size.toLocaleString()} bytes → error: ${msg.slice(0, 80)}`);
        }

        await new Promise((r) => setTimeout(r, 500));
    }

    printResultsTable('Phase 2: JSON+SVG Data URI (testDataURI)', results);
    return results;
}

async function phaseBase64URI(
    contract: IContract,
): Promise<TestResult[]> {
    console.log('\n═══ Phase 3: Base64 SVG Data URI (testBase64URI) ═══\n');
    info('Testing data:image/svg+xml;base64,... return...');

    const results: TestResult[] = [];

    for (const size of TEST_SIZES) {
        const start = Date.now();
        try {
            const result = await callMethod(contract, 'testBase64URI')(BigInt(size));
            const duration = Date.now() - start;

            if (result.revert) {
                results.push({ size, success: false, responseLen: 0, durationMs: duration, error: String(result.revert).slice(0, 40) });
                fail(`raw ${size.toLocaleString()} bytes → reverted: ${String(result.revert).slice(0, 60)}`);
            } else {
                const decoded = result.decoded?.[0] as string ?? '';
                results.push({ size, success: true, responseLen: decoded.length, durationMs: duration });
                ok(`raw ${size.toLocaleString()} bytes → URI ${decoded.length.toLocaleString()} chars (${duration}ms)`);
            }
        } catch (err: unknown) {
            const duration = Date.now() - start;
            const msg = err instanceof Error ? err.message : String(err);
            results.push({ size, success: false, responseLen: 0, durationMs: duration, error: msg.slice(0, 40) });
            fail(`raw ${size.toLocaleString()} bytes → error: ${msg.slice(0, 80)}`);
        }

        await new Promise((r) => setTimeout(r, 500));
    }

    printResultsTable('Phase 3: Base64 SVG Data URI (testBase64URI)', results);
    return results;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    console.log('╔══════════════════════════════════════════════╗');
    console.log('║   SVG Size Limit Tester for OPNet RPC       ║');
    console.log('╚══════════════════════════════════════════════╝\n');

    // Resolve contract address
    let contractAddress = getArg('--address');
    if (!contractAddress) {
        const deploymentsPath = join(__dirname, `../deployments/${NET_NAME}.json`);
        if (fs.existsSync(deploymentsPath)) {
            const deployment = JSON.parse(fs.readFileSync(deploymentsPath, 'utf-8'));
            contractAddress = deployment.contracts?.SVGTEST;
        }
    }

    if (!contractAddress) {
        console.error('No SVGSizeTest contract address found.');
        console.error('Either deploy first, or pass --address <contract>');
        process.exit(1);
    }

    const phase = getArg('--phase');

    console.log(`  Network:  ${NET_NAME} (${NET_CONFIG.rpcUrl})`);
    console.log(`  Contract: ${contractAddress}`);
    console.log(`  Phase:    ${phase ?? 'all'}`);
    console.log(`  Sizes:    ${TEST_SIZES.length} probes (${TEST_SIZES[0]}..${TEST_SIZES[TEST_SIZES.length - 1]} bytes)`);

    // Connect
    const rpcProvider = new JSONRpcProvider({ url: NET_CONFIG.rpcUrl, network: NET_CONFIG.network });

    // Resolve bech32 address to public key via RPC
    info('Resolving contract public key...');
    const resolvedAddress = await rpcProvider.getPublicKeyInfo(contractAddress, true);
    if (!resolvedAddress) {
        console.error(`Could not resolve public key for ${contractAddress}.`);
        console.error('Is the contract confirmed on-chain?');
        process.exit(1);
    }
    ok(`Resolved: ${resolvedAddress.toString()}`);

    const contract = getContract<IContract>(
        resolvedAddress,
        SVGSizeTestAbi,
        rpcProvider,
        NET_CONFIG.network,
    );

    // Verify contract is accessible
    info('Verifying contract is accessible...');
    try {
        const probe = await callMethod(contract, 'testReturn')(1n);
        if (probe.revert) {
            console.error(`Contract call reverted: ${probe.revert}`);
            console.error('Is the contract deployed and indexed?');
            process.exit(1);
        }
        ok('Contract accessible\n');
    } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`Cannot reach contract: ${msg}`);
        process.exit(1);
    }

    // Run phases
    const allResults: { phase: string; results: TestResult[] }[] = [];

    if (!phase || phase === '1') {
        const r = await phaseRawString(contract);
        allResults.push({ phase: 'Raw String', results: r });
    }

    if (!phase || phase === '2') {
        const r = await phaseDataURI(contract);
        allResults.push({ phase: 'JSON+SVG Data URI', results: r });
    }

    if (!phase || phase === '3') {
        const r = await phaseBase64URI(contract);
        allResults.push({ phase: 'Base64 SVG URI', results: r });
    }

    // Summary
    console.log('\n╔══════════════════════════════════════════════╗');
    console.log('║                   Summary                    ║');
    console.log('╚══════════════════════════════════════════════╝\n');

    for (const { phase: phaseName, results } of allResults) {
        const successResults = results.filter(r => r.success);
        const maxInput = successResults.length > 0
            ? Math.max(...successResults.map(r => r.size))
            : 0;
        const maxResponse = successResults.length > 0
            ? Math.max(...successResults.map(r => r.responseLen))
            : 0;
        const firstFail = results.find(r => !r.success);

        console.log(`  ${phaseName}:`);
        console.log(`    Max successful input:    ${maxInput.toLocaleString()} bytes`);
        console.log(`    Max response length:     ${maxResponse.toLocaleString()} chars`);
        if (firstFail) {
            console.log(`    First failure at input:  ${firstFail.size.toLocaleString()} bytes (${firstFail.error ?? 'unknown'})`);
        } else {
            console.log(`    No failures — all sizes succeeded`);
        }
        console.log();
    }

    // Save results to JSON
    const outputPath = join(__dirname, `../deployments/svg-limits-${NET_NAME}.json`);
    const outputData = {
        network: NET_NAME,
        contract: contractAddress,
        testedAt: new Date().toISOString(),
        results: Object.fromEntries(allResults.map(({ phase: p, results: r }) => [p, r])),
    };
    fs.writeFileSync(outputPath, JSON.stringify(outputData, null, 2));
    info(`Results saved to ${outputPath}`);

    await rpcProvider.close();
}

main().catch((err) => {
    console.error('\nTest failed:', err);
    process.exit(1);
});
