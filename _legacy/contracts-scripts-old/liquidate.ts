/**
 * liquidate.ts
 *
 * Liquidation bot example for the Cauldron CDP on the Magic Internet Frens
 * protocol (OP_NET).
 *
 * This script:
 *   1. Fetches the current BTC/USD price from the Oracle
 *   2. Iterates over all open Cauldron positions
 *   3. Identifies positions where LTV > 80% (liquidation threshold)
 *   4. Executes liquidation for each underwater position
 *   5. Reports profit earned from liquidation incentive
 *
 * The liquidator repays some or all of the borrower's MIF debt and receives
 * the borrower's BTC collateral at a discount (liquidation incentive).
 *
 * Usage:
 *   npx ts-node contracts/scripts/liquidate.ts
 *   npx ts-node contracts/scripts/liquidate.ts --network testnet
 *   npx ts-node contracts/scripts/liquidate.ts --dry-run
 *
 * Flags:
 *   --network  string   regtest | testnet | mainnet (default: regtest)
 *   --dry-run           Scan positions but do not execute liquidations
 *   --interval number   Polling interval in seconds (default: 30, 0 = once)
 *
 * Environment:
 *   LIQUIDATOR_PRIVATE_KEY  - BTC private key for the liquidator wallet
 */

// ---------------------------------------------------------------------------
// TODO: Replace placeholder imports with real OP_NET SDK packages.
// ---------------------------------------------------------------------------

// TODO: import { Provider, Wallet, Contract } from '@opnet/sdk';

// ---------------------------------------------------------------------------
// Deployed addresses -- TODO: load from deployments/<network>.json
// ---------------------------------------------------------------------------

const ADDRESSES = {
    Cauldron: 'bc1q_cauldron_placeholder',
    MIF:      'bc1q_mif_placeholder',
    Oracle:   'bc1q_oracle_placeholder',
};

// ---------------------------------------------------------------------------
// Protocol constants
// ---------------------------------------------------------------------------

const LIQUIDATION_LTV_BPS = 8000;           // 80.00%
const LIQUIDATION_INCENTIVE_BPS = 500;      // 5% discount on collateral for liquidator
const CLOSE_FACTOR_BPS = 5000;              // Max 50% of debt can be liquidated at once

// ---------------------------------------------------------------------------
// Network helpers
// ---------------------------------------------------------------------------

interface NetworkConfig {
    rpcUrl: string;
}

const NETWORKS: Record<string, NetworkConfig> = {
    regtest: { rpcUrl: 'http://localhost:9001' },
    testnet: { rpcUrl: 'https://testnet.opnet.org' },
    mainnet: { rpcUrl: 'https://mainnet.opnet.org' },
};

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

function parseArgs(): {
    network: string;
    dryRun: boolean;
    intervalSec: number;
} {
    const args = process.argv.slice(2);
    let network = 'regtest';
    let dryRun = false;
    let intervalSec = 30;

    for (let i = 0; i < args.length; i++) {
        switch (args[i]) {
            case '--network':
                network = args[++i];
                break;
            case '--dry-run':
                dryRun = true;
                break;
            case '--interval':
                intervalSec = parseInt(args[++i], 10);
                break;
        }
    }

    return { network, dryRun, intervalSec };
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface CauldronPosition {
    owner: string;
    collateralSats: bigint;
    debtMIF: bigint;
    nftId: number;
    lastAccrualTimestamp: number;
}

interface LiquidationCandidate {
    position: CauldronPosition;
    ltvBps: number;
    maxRepayMIF: bigint;
    collateralSeized: bigint;
    profitSats: bigint;
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

function formatSats(sats: bigint): string {
    return `${sats.toString()} sats (${(Number(sats) / 1e8).toFixed(8)} BTC)`;
}

function formatMIF(wei: bigint): string {
    return `${(Number(wei) / 1e18).toFixed(4)} MIF`;
}

function formatBps(bps: number): string {
    return `${(bps / 100).toFixed(2)}%`;
}

function timestamp(): string {
    return new Date().toISOString();
}

// ---------------------------------------------------------------------------
// Position scanning
// ---------------------------------------------------------------------------

async function fetchAllPositions(): Promise<CauldronPosition[]> {
    // TODO: Query the Cauldron contract for all open positions.
    //
    // Option A -- event-based indexing:
    //   Scan for Deposit / Borrow events, build a local position map,
    //   then filter for positions with debt > 0.
    //
    //   const filter = cauldron.filters.PositionOpened();
    //   const events = await cauldron.queryFilter(filter, 0, 'latest');
    //   const owners = [...new Set(events.map(e => e.args.owner))];
    //   const positions = await Promise.all(
    //       owners.map(o => cauldron.getPosition(o))
    //   );
    //
    // Option B -- enumerable getter (if contract supports it):
    //   const count = await cauldron.positionCount();
    //   for (let i = 0; i < count; i++) {
    //       positions.push(await cauldron.positionAt(i));
    //   }

    // Placeholder: return simulated positions for demonstration.
    const simulated: CauldronPosition[] = [
        {
            owner: 'bc1q_alice_placeholder',
            collateralSats: BigInt(50_000),
            debtMIF: BigInt('28000000000000000000'),  // 28 MIF -- healthy
            nftId: 1,
            lastAccrualTimestamp: Math.floor(Date.now() / 1000) - 3600,
        },
        {
            owner: 'bc1q_bob_placeholder',
            collateralSats: BigInt(30_000),
            debtMIF: BigInt('16000000000000000000'),  // 16 MIF -- underwater at $60k
            nftId: 7,
            lastAccrualTimestamp: Math.floor(Date.now() / 1000) - 7200,
        },
        {
            owner: 'bc1q_charlie_placeholder',
            collateralSats: BigInt(100_000),
            debtMIF: BigInt('49500000000000000000'),  // 49.5 MIF -- borderline
            nftId: 15,
            lastAccrualTimestamp: Math.floor(Date.now() / 1000) - 1800,
        },
    ];

    return simulated;
}

// ---------------------------------------------------------------------------
// Liquidation analysis
// ---------------------------------------------------------------------------

function analyseLiquidation(
    position: CauldronPosition,
    btcPriceUsd: number,
): LiquidationCandidate | null {
    const collateralUsd = (Number(position.collateralSats) / 1e8) * btcPriceUsd;
    const debtUsd = Number(position.debtMIF) / 1e18;

    if (collateralUsd === 0) return null;

    const ltvBps = Math.round((debtUsd / collateralUsd) * 10_000);

    if (ltvBps <= LIQUIDATION_LTV_BPS) {
        return null; // Position is healthy.
    }

    // Calculate maximum repayable debt (close factor).
    const maxRepayUsd = (debtUsd * CLOSE_FACTOR_BPS) / 10_000;
    const maxRepayMIF = BigInt(Math.floor(maxRepayUsd * 1e18));

    // Collateral seized = repayUsd * (1 + incentive) / btcPrice, in sats.
    const collateralSeizedBtc = (maxRepayUsd * (10_000 + LIQUIDATION_INCENTIVE_BPS)) / (10_000 * btcPriceUsd);
    const collateralSeizedSats = BigInt(Math.floor(collateralSeizedBtc * 1e8));

    // Cap at available collateral.
    const effectiveSeized = collateralSeizedSats > position.collateralSats
        ? position.collateralSats
        : collateralSeizedSats;

    // Liquidator profit = collateral value received - debt repaid.
    const seizedValueUsd = (Number(effectiveSeized) / 1e8) * btcPriceUsd;
    const profitUsd = seizedValueUsd - maxRepayUsd;
    const profitSats = BigInt(Math.floor((profitUsd / btcPriceUsd) * 1e8));

    return {
        position,
        ltvBps,
        maxRepayMIF,
        collateralSeized: effectiveSeized,
        profitSats: profitSats > BigInt(0) ? profitSats : BigInt(0),
    };
}

// ---------------------------------------------------------------------------
// Liquidation execution
// ---------------------------------------------------------------------------

async function executeLiquidation(
    candidate: LiquidationCandidate,
    dryRun: boolean,
): Promise<void> {
    const { position, ltvBps, maxRepayMIF, collateralSeized, profitSats } = candidate;

    console.log(`\n  [LIQUIDATE] ${position.owner}`);
    console.log(`    LTV              : ${formatBps(ltvBps)} (threshold: ${formatBps(LIQUIDATION_LTV_BPS)})`);
    console.log(`    Collateral       : ${formatSats(position.collateralSats)}`);
    console.log(`    Debt             : ${formatMIF(position.debtMIF)}`);
    console.log(`    Repay Amount     : ${formatMIF(maxRepayMIF)}`);
    console.log(`    Collateral Seized: ${formatSats(collateralSeized)}`);
    console.log(`    Estimated Profit : ${formatSats(profitSats)}`);

    if (dryRun) {
        console.log('    MODE: DRY RUN -- skipping execution.');
        return;
    }

    // TODO: Execute the liquidation on-chain.
    //
    //   Step 1: Ensure the liquidator has enough MIF to repay.
    //     const mifBalance = await mif.balanceOf(await signer.getAddress());
    //     if (mifBalance < maxRepayMIF) {
    //         console.log('    Insufficient MIF balance to liquidate.');
    //         return;
    //     }
    //
    //   Step 2: Approve the Cauldron to spend the liquidator's MIF.
    //     const approveTx = await mif.approve(ADDRESSES.Cauldron, maxRepayMIF);
    //     await approveTx.wait();
    //
    //   Step 3: Call the Cauldron's liquidate function.
    //     const liqTx = await cauldron.liquidate(
    //         position.owner,    // borrower to liquidate
    //         maxRepayMIF,       // amount of MIF debt to repay
    //         position.nftId,    // NFT collateral identifier
    //     );
    //     const receipt = await liqTx.wait();
    //     console.log(`    Tx Hash: ${receipt.transactionHash}`);
    //
    //   Step 4: Log received BTC.
    //     const newBalance = await provider.getBalance(await signer.getAddress());
    //     console.log(`    New BTC balance: ${newBalance} sats`);

    console.log('    Liquidation executed (placeholder).');
}

// ---------------------------------------------------------------------------
// Main scan loop
// ---------------------------------------------------------------------------

async function scanAndLiquidate(dryRun: boolean): Promise<number> {
    console.log(`\n[${timestamp()}] Scanning positions...`);

    // Fetch current BTC price.
    // TODO: const btcPriceRaw = await oracle.getPrice();
    //       const btcPriceUsd = Number(btcPriceRaw) / 1e8;
    const btcPriceUsd = 60_000; // placeholder

    console.log(`  BTC/USD: $${btcPriceUsd.toLocaleString()}`);

    // Fetch all positions.
    const positions = await fetchAllPositions();
    console.log(`  Total positions: ${positions.length}`);

    // Find underwater positions.
    const candidates: LiquidationCandidate[] = [];
    for (const pos of positions) {
        const candidate = analyseLiquidation(pos, btcPriceUsd);
        if (candidate) {
            candidates.push(candidate);
        }
    }

    console.log(`  Underwater positions: ${candidates.length}`);

    if (candidates.length === 0) {
        console.log('  All positions are healthy. Nothing to liquidate.');
        return 0;
    }

    // Sort by highest LTV first (most profitable / most urgent).
    candidates.sort((a, b) => b.ltvBps - a.ltvBps);

    // Display summary table.
    console.log('');
    console.log('  Owner                          | LTV      | Debt        | Profit');
    console.log('  ' + '-'.repeat(75));
    for (const c of candidates) {
        const owner = c.position.owner.slice(0, 30).padEnd(30);
        const ltv = formatBps(c.ltvBps).padEnd(8);
        const debt = formatMIF(c.position.debtMIF).padEnd(12);
        const profit = formatSats(c.profitSats);
        console.log(`  ${owner} | ${ltv} | ${debt} | ${profit}`);
    }

    // Execute liquidations.
    let liquidated = 0;
    for (const candidate of candidates) {
        try {
            await executeLiquidation(candidate, dryRun);
            liquidated++;
        } catch (err) {
            console.error(`  Failed to liquidate ${candidate.position.owner}:`, err);
        }
    }

    return liquidated;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const { network, dryRun, intervalSec } = parseArgs();
    const _config = NETWORKS[network];
    if (!_config) {
        console.error(`Unknown network "${network}".`);
        process.exit(1);
    }

    console.log('Cauldron Liquidation Bot');
    console.log('='.repeat(50));
    console.log(`Network  : ${network}`);
    console.log(`Dry run  : ${dryRun}`);
    console.log(`Interval : ${intervalSec === 0 ? 'once' : `${intervalSec}s`}`);
    console.log('='.repeat(50));

    // TODO: Initialise provider + wallet.
    // const provider = new Provider(config.rpcUrl);
    // const signer   = new Wallet(process.env.LIQUIDATOR_PRIVATE_KEY!, provider);
    // const cauldron = new Contract(ADDRESSES.Cauldron, cauldronAbi, signer);
    // const oracle   = new Contract(ADDRESSES.Oracle, oracleAbi, signer);
    // const mif      = new Contract(ADDRESSES.MIF, mifAbi, signer);
    // console.log(`Liquidator: ${await signer.getAddress()}`);

    if (intervalSec === 0) {
        // Single run.
        await scanAndLiquidate(dryRun);
    } else {
        // Continuous polling loop.
        console.log(`\nStarting continuous scan every ${intervalSec}s. Press Ctrl+C to stop.\n`);

        const runLoop = async () => {
            try {
                const count = await scanAndLiquidate(dryRun);
                if (count > 0) {
                    console.log(`\n  Liquidated ${count} position(s) this cycle.`);
                }
            } catch (err) {
                console.error('Scan cycle error:', err);
            }
        };

        // Initial run.
        await runLoop();

        // Schedule subsequent runs.
        setInterval(runLoop, intervalSec * 1000);

        // Keep process alive.
        await new Promise(() => {});
    }
}

main().catch((err) => {
    console.error('Liquidation bot failed:', err);
    process.exit(1);
});
