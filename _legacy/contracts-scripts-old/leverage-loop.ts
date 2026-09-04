/**
 * leverage-loop.ts
 *
 * Demonstrates the cook() leverage looping strategy on the Cauldron CDP:
 *
 *   Loop iteration:
 *     1. Deposit BTC collateral
 *     2. Borrow MIF stablecoin
 *     3. Swap MIF -> BTC (simulated here; real swap via DEX or AMM)
 *     4. Deposit the swapped BTC as additional collateral
 *     5. Repeat
 *
 * Each loop increases both collateral and debt, amplifying BTC exposure.
 * The cook() function on the Cauldron batches all of these into a single
 * atomic transaction.
 *
 * Usage:
 *   npx ts-node contracts/scripts/leverage-loop.ts \
 *       --nft-id 42 \
 *       --initial 100000 \
 *       --loops 3
 *
 * Flags:
 *   --nft-id    uint256  MiFrens NFT token ID
 *   --initial   uint64   Initial BTC deposit in satoshis
 *   --loops     uint8    Number of leverage loop iterations (default: 3)
 *   --network   string   regtest | testnet | mainnet  (default: regtest)
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
// Protocol constants
// ---------------------------------------------------------------------------

const LIQUIDATION_LTV_BPS = 8000; // 80%
const BORROW_FEE_BPS = 50;       // 0.50%
const MAX_LTV_BPS = 7500;        // 75% -- safe borrow ceiling per loop

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
    initialSats: bigint;
    loops: number;
} {
    const args = process.argv.slice(2);
    let network = 'regtest';
    let nftId = 0;
    let initialSats = BigInt(100_000); // default 100 000 sats
    let loops = 3;

    for (let i = 0; i < args.length; i++) {
        switch (args[i]) {
            case '--network':
                network = args[++i];
                break;
            case '--nft-id':
                nftId = parseInt(args[++i], 10);
                break;
            case '--initial':
                initialSats = BigInt(args[++i]);
                break;
            case '--loops':
                loops = parseInt(args[++i], 10);
                break;
        }
    }

    if (loops < 1 || loops > 10) {
        console.error('--loops must be between 1 and 10.');
        process.exit(1);
    }

    return { network, nftId, initialSats, loops };
}

// ---------------------------------------------------------------------------
// Formatting
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
// Cook action types
//
// The cook() function on the Cauldron takes an array of encoded actions.
// Each action is identified by a uint8 action code.
// ---------------------------------------------------------------------------

const COOK_ACTION = {
    DEPOSIT_COLLATERAL: 1,
    BORROW_MIF:         2,
    REPAY_MIF:          3,
    WITHDRAW_COLLATERAL: 4,
    SWAP_MIF_TO_BTC:    10,  // integration with on-chain DEX
    SWAP_BTC_TO_MIF:    11,
} as const;

// ---------------------------------------------------------------------------
// Build cook() calldata for a single leverage iteration
// ---------------------------------------------------------------------------

interface CookAction {
    actionCode: number;
    data: unknown; // TODO: encode per OP_NET ABI conventions
}

function buildLeverageActions(
    depositSats: bigint,
    borrowMIF: bigint,
): CookAction[] {
    return [
        {
            actionCode: COOK_ACTION.DEPOSIT_COLLATERAL,
            data: { amount: depositSats },
        },
        {
            actionCode: COOK_ACTION.BORROW_MIF,
            data: { amount: borrowMIF },
        },
        {
            actionCode: COOK_ACTION.SWAP_MIF_TO_BTC,
            data: {
                amountIn: borrowMIF,
                minAmountOut: BigInt(0), // TODO: set proper slippage
            },
        },
        // The swapped BTC automatically becomes the deposit for the next
        // iteration when submitted in a single cook() batch. The contract
        // carries forward the intermediate BTC balance.
    ];
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const { network, nftId, initialSats, loops } = parseArgs();
    const _config = NETWORKS[network];
    if (!_config) {
        console.error(`Unknown network "${network}".`);
        process.exit(1);
    }

    console.log('\nCauldron: Leverage Loop via cook()');
    console.log('='.repeat(60));
    console.log(`Network       : ${network}`);
    console.log(`NFT ID        : #${nftId}`);
    console.log(`Initial Deposit: ${formatSats(initialSats)}`);
    console.log(`Loop Count    : ${loops}`);
    console.log(`Max LTV/loop  : ${formatBps(MAX_LTV_BPS)}`);
    console.log(`Liquidation   : ${formatBps(LIQUIDATION_LTV_BPS)}`);
    console.log('='.repeat(60));

    // TODO: Initialise provider + wallet from OP_NET SDK.
    // const provider = new Provider(config.rpcUrl);
    // const signer   = new Wallet(process.env.DEPLOYER_PRIVATE_KEY!, provider);
    // const cauldron = new Contract(ADDRESSES.Cauldron, cauldronAbi, signer);
    // const oracle   = new Contract(ADDRESSES.Oracle, oracleAbi, signer);

    // Fetch BTC price.
    // TODO: const btcPriceRaw = await oracle.getPrice();
    const btcPriceUsd = 60_000; // placeholder: $60,000

    // ----- Build all cook actions across loop iterations -------------------

    let totalCollateralSats = BigInt(0);
    let totalDebtMIF = BigInt(0);
    const allActions: CookAction[] = [];

    // First deposit is the user's initial BTC.
    let currentDepositSats = initialSats;

    console.log('');

    for (let i = 0; i < loops; i++) {
        console.log(`--- Loop ${i + 1} of ${loops} ---`);

        // Calculate how much MIF we can borrow at MAX_LTV against this deposit.
        const collateralUsd = (Number(currentDepositSats) / 1e8) * btcPriceUsd;
        const maxBorrowUsd = (collateralUsd * MAX_LTV_BPS) / 10_000;
        const borrowMIF = BigInt(Math.floor(maxBorrowUsd * 1e18));
        const borrowFee = (borrowMIF * BigInt(BORROW_FEE_BPS)) / BigInt(10_000);

        totalCollateralSats += currentDepositSats;
        totalDebtMIF += borrowMIF + borrowFee;

        // Simulate swapping borrowed MIF back to BTC for next deposit.
        // Assume 1 MIF = $1 and deduct a 0.3% swap fee.
        const swapFeeRate = 0.003;
        const swapOutputBtc = maxBorrowUsd * (1 - swapFeeRate) / btcPriceUsd;
        const swapOutputSats = BigInt(Math.floor(swapOutputBtc * 1e8));

        const ltvBps = Math.round(
            (Number(totalDebtMIF) / 1e18 / ((Number(totalCollateralSats) / 1e8) * btcPriceUsd)) * 10_000,
        );

        console.log(`  Deposit      : ${formatSats(currentDepositSats)}`);
        console.log(`  Borrow       : ${formatMIF(borrowMIF)}`);
        console.log(`  Borrow Fee   : ${formatMIF(borrowFee)}`);
        console.log(`  Swap Out     : ${formatSats(swapOutputSats)} (after 0.3% swap fee)`);
        console.log(`  Cumulative   : collateral=${formatSats(totalCollateralSats)}, debt=${formatMIF(totalDebtMIF)}`);
        console.log(`  Current LTV  : ${formatBps(ltvBps)}`);
        console.log('');

        // Append actions for this iteration.
        const actions = buildLeverageActions(currentDepositSats, borrowMIF);
        allActions.push(...actions);

        // The swap output becomes the next loop's deposit.
        currentDepositSats = swapOutputSats;

        // Safety check: if swap output is too small, stop.
        if (currentDepositSats < BigInt(1_000)) {
            console.log('  Swap output too small, stopping leverage loop.');
            break;
        }
    }

    // After the last loop, deposit any remaining swapped BTC.
    if (currentDepositSats >= BigInt(1_000)) {
        totalCollateralSats += currentDepositSats;
        allActions.push({
            actionCode: COOK_ACTION.DEPOSIT_COLLATERAL,
            data: { amount: currentDepositSats },
        });
        console.log(`--- Final deposit of remaining BTC: ${formatSats(currentDepositSats)} ---\n`);
    }

    // ----- Execute the cook() transaction ---------------------------------

    console.log(`Total cook() actions: ${allActions.length}`);
    console.log('Submitting cook() transaction...\n');

    // TODO: Encode all actions into a single cook() call.
    //
    //   const encodedActions = allActions.map(a =>
    //       cauldron.interface.encodeCookAction(a.actionCode, a.data)
    //   );
    //   const cookTx = await cauldron.cook(
    //       nftId,
    //       encodedActions,
    //       { value: initialSats },
    //   );
    //   const receipt = await cookTx.wait();
    //   console.log(`  cook() tx: ${receipt.transactionHash}`);

    console.log('  cook() submitted (placeholder).');

    // ----- Final position summary ------------------------------------------

    const collateralUsd = (Number(totalCollateralSats) / 1e8) * btcPriceUsd;
    const debtUsd = Number(totalDebtMIF) / 1e18;
    const finalLtvBps = Math.round((debtUsd / collateralUsd) * 10_000);
    const healthFactor = LIQUIDATION_LTV_BPS / finalLtvBps;
    const leverageMultiple = collateralUsd / ((Number(initialSats) / 1e8) * btcPriceUsd);

    console.log('');
    console.log('='.repeat(60));
    console.log('  Final Leveraged Position');
    console.log('='.repeat(60));
    console.log(`  Initial Deposit   : ${formatSats(initialSats)}`);
    console.log(`  Total Collateral  : ${formatSats(totalCollateralSats)}`);
    console.log(`  Collateral USD    : $${collateralUsd.toFixed(2)}`);
    console.log(`  Total Debt (MIF)  : ${formatMIF(totalDebtMIF)}`);
    console.log(`  Debt USD          : $${debtUsd.toFixed(2)}`);
    console.log(`  Final LTV         : ${formatBps(finalLtvBps)}`);
    console.log(`  Liquidation at    : ${formatBps(LIQUIDATION_LTV_BPS)}`);
    console.log(`  Health Factor     : ${healthFactor.toFixed(4)}`);
    console.log(`  Effective Leverage: ${leverageMultiple.toFixed(2)}x`);
    console.log('='.repeat(60));

    if (finalLtvBps >= LIQUIDATION_LTV_BPS) {
        console.log('\n  WARNING: Position exceeds liquidation threshold!');
    } else if (finalLtvBps >= LIQUIDATION_LTV_BPS - 500) {
        console.log('\n  CAUTION: Position is within 5% of liquidation.');
    } else {
        console.log('\n  Position is healthy.');
    }

    // TODO: Read on-chain position for verification.
    //   const position = await cauldron.getPosition(await signer.getAddress());
    //   console.log(`  On-chain collateral: ${position.collateral}`);
    //   console.log(`  On-chain debt:       ${position.debt}`);

    console.log('');
}

main().catch((err) => {
    console.error('Leverage loop failed:', err);
    process.exit(1);
});
