/**
 * deposit-borrow.ts
 *
 * Demonstrates the full Cauldron CDP flow on the Magic Internet Frens
 * protocol (OP_NET):
 *
 *   1. Deposit BTC collateral into the Cauldron
 *   2. Borrow MIF stablecoin against that collateral
 *   3. Log the resulting position details (collateral, debt, LTV, health)
 *
 * Usage:
 *   npx ts-node contracts/scripts/deposit-borrow.ts \
 *       --nft-id 42 \
 *       --deposit 50000 \
 *       --borrow 25000000000000000000
 *
 * Flags:
 *   --nft-id   uint256  MiFrens NFT token ID (used for tier-based fee discount)
 *   --deposit  uint64   BTC collateral amount in satoshis
 *   --borrow   uint256  MIF stablecoin amount to borrow (18 decimals)
 *   --network  string   regtest | testnet | mainnet  (default: regtest)
 *
 * Environment:
 *   DEPLOYER_PRIVATE_KEY  - BTC private key (WIF or hex)
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
    MiFrens:   'bc1q_mifrennft_placeholder',
};

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
    nftId: number;
    depositSats: bigint;
    borrowAmount: bigint;
} {
    const args = process.argv.slice(2);
    let network = 'regtest';
    let nftId = 0;
    let depositSats = BigInt(50_000);                      // default 50 000 sats
    let borrowAmount = BigInt('25000000000000000000');      // default 25 MIF (18 dec)

    for (let i = 0; i < args.length; i++) {
        switch (args[i]) {
            case '--network':
                network = args[++i];
                break;
            case '--nft-id':
                nftId = parseInt(args[++i], 10);
                break;
            case '--deposit':
                depositSats = BigInt(args[++i]);
                break;
            case '--borrow':
                borrowAmount = BigInt(args[++i]);
                break;
        }
    }

    return { network, nftId, depositSats, borrowAmount };
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

function formatSats(sats: bigint): string {
    const btc = Number(sats) / 1e8;
    return `${sats.toString()} sats (${btc.toFixed(8)} BTC)`;
}

function formatMIF(wei: bigint): string {
    const mif = Number(wei) / 1e18;
    return `${mif.toFixed(4)} MIF`;
}

function formatBps(bps: number): string {
    return `${(bps / 100).toFixed(2)}%`;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const { network, nftId, depositSats, borrowAmount } = parseArgs();
    const _config = NETWORKS[network];
    if (!_config) {
        console.error(`Unknown network "${network}".`);
        process.exit(1);
    }

    console.log('\nCauldron: Deposit & Borrow');
    console.log('='.repeat(50));
    console.log(`Network      : ${network}`);
    console.log(`NFT ID       : #${nftId}`);
    console.log(`Deposit      : ${formatSats(depositSats)}`);
    console.log(`Borrow       : ${formatMIF(borrowAmount)}`);
    console.log('='.repeat(50));

    // TODO: Initialise provider + wallet from OP_NET SDK.
    // const provider = new Provider(config.rpcUrl);
    // const signer   = new Wallet(process.env.DEPLOYER_PRIVATE_KEY!, provider);

    // TODO: Instantiate contracts.
    // const cauldronAbi = [ ... ]; // load from build artifacts
    // const oracleAbi   = [ ... ];
    // const mifAbi      = [ ... ];
    // const cauldron = new Contract(ADDRESSES.Cauldron, cauldronAbi, signer);
    // const oracle   = new Contract(ADDRESSES.Oracle, oracleAbi, signer);
    // const mif      = new Contract(ADDRESSES.MIF, mifAbi, signer);

    // ----- Step 0: Fetch BTC price from Oracle ----------------------------

    console.log('\n[0] Fetching BTC/USD price from Oracle...');

    // TODO: const btcPriceUsd = await oracle.getPrice();
    const btcPriceUsd = BigInt(6_000_000_000_000); // placeholder: $60,000 (8 dec)
    const btcPriceFormatted = Number(btcPriceUsd) / 1e8;
    console.log(`    BTC/USD: $${btcPriceFormatted.toLocaleString()}`);

    // ----- Step 1: Deposit BTC collateral ---------------------------------

    console.log('\n[1] Depositing BTC collateral into Cauldron...');

    // TODO: Call the Cauldron's deposit function with BTC value attached.
    //   The deposit function locks the BTC and records collateral for the user.
    //
    //   const depositTx = await cauldron.deposit(nftId, {
    //       value: depositSats,
    //   });
    //   const depositReceipt = await depositTx.wait();
    //   console.log(`    Deposit tx: ${depositReceipt.transactionHash}`);

    console.log(`    Deposited ${formatSats(depositSats)} as collateral.`);

    // ----- Step 2: Borrow MIF stablecoin ----------------------------------

    console.log('\n[2] Borrowing MIF stablecoin against collateral...');

    // TODO: Call the Cauldron's borrow function.
    //   The borrow function mints MIF to the borrower and records the debt.
    //   It checks LTV to ensure the position is healthy.
    //
    //   const borrowTx = await cauldron.borrow(nftId, borrowAmount);
    //   const borrowReceipt = await borrowTx.wait();
    //   console.log(`    Borrow tx: ${borrowReceipt.transactionHash}`);

    console.log(`    Borrowed ${formatMIF(borrowAmount)}.`);

    // ----- Step 3: Read back position details -----------------------------

    console.log('\n[3] Reading position from Cauldron...');

    // TODO: Query the on-chain position struct.
    //   const position = await cauldron.getPosition(await signer.getAddress());
    //   const collateralSats = position.collateral;      // bigint
    //   const debtMIF        = position.debt;             // bigint
    //   const accruedFees    = position.accruedInterest;  // bigint
    //   const nftBoost       = position.tierBoostBps;     // uint16

    // Simulated position data.
    const collateralSats = depositSats;
    const debtMIF = borrowAmount;
    const borrowFeeBps = 50; // 0.50%
    const accruedFees = (borrowAmount * BigInt(borrowFeeBps)) / BigInt(10_000);
    const totalDebt = debtMIF + accruedFees;

    // Calculate LTV: (debtUSD / collateralUSD) * 10000
    const collateralUsd = (Number(collateralSats) / 1e8) * btcPriceFormatted;
    const debtUsd = Number(totalDebt) / 1e18; // MIF is pegged $1
    const ltvBps = Math.round((debtUsd / collateralUsd) * 10_000);
    const liquidationThresholdBps = 8000; // 80%
    const healthFactor = liquidationThresholdBps / ltvBps;

    // TODO: const classBoost = await miFren.getMaxBorrow(nftId);
    const classBoost = 2; // placeholder: class-based benefit

    // ----- Display position summary ----------------------------------------

    console.log('');
    console.log('='.repeat(50));
    console.log('  Position Summary');
    console.log('='.repeat(50));
    console.log(`  Collateral     : ${formatSats(collateralSats)}`);
    console.log(`  Collateral USD : $${collateralUsd.toFixed(2)}`);
    console.log(`  Debt (MIF)     : ${formatMIF(debtMIF)}`);
    console.log(`  Borrow Fee     : ${formatMIF(accruedFees)} (${formatBps(borrowFeeBps)})`);
    console.log(`  Total Debt     : ${formatMIF(totalDebt)}`);
    console.log(`  LTV            : ${formatBps(ltvBps)}`);
    console.log(`  Liquidation at : ${formatBps(liquidationThresholdBps)}`);
    console.log(`  Health Factor  : ${healthFactor.toFixed(4)}`);
    console.log(`  NFT Tier Boost : ${tierBoost}% fee reduction (NFT #${nftId})`);
    console.log('='.repeat(50));

    if (ltvBps >= liquidationThresholdBps) {
        console.log('\n  WARNING: Position is ABOVE liquidation threshold!');
    } else if (ltvBps >= liquidationThresholdBps - 500) {
        console.log('\n  CAUTION: Position is within 5% of liquidation threshold.');
    } else {
        console.log('\n  Position is healthy.');
    }

    // ----- Verify MIF balance received ------------------------------------

    console.log('\n[4] Verifying MIF balance...');

    // TODO: const mifBalance = await mif.balanceOf(await signer.getAddress());
    // console.log(`    MIF balance: ${formatMIF(mifBalance)}`);
    console.log(`    MIF balance: ${formatMIF(borrowAmount)} (expected)`);

    console.log('\nDeposit & Borrow complete.\n');
}

main().catch((err) => {
    console.error('Deposit-borrow failed:', err);
    process.exit(1);
});
