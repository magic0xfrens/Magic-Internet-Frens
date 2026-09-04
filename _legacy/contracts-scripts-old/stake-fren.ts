/**
 * stake-fren.ts
 *
 * Stake FREN tokens to receive sFREN (staked FREN) on the Magic Internet
 * Frens protocol (OP_NET).
 *
 * sFREN is a rebasing / share-based wrapper around FREN. The exchange rate
 * between FREN and sFREN increases over time as protocol revenue accrues
 * to the staking pool (similar to xSUSHI or stETH models).
 *
 * This script:
 *   1. Shows current FREN and sFREN balances
 *   2. Displays the current staking ratio (FREN per sFREN)
 *   3. Stakes the specified FREN amount for sFREN
 *   4. Shows updated balances and pending rewards
 *
 * Usage:
 *   npx ts-node contracts/scripts/stake-fren.ts --amount 1000000000000000000000
 *   npx ts-node contracts/scripts/stake-fren.ts --amount 1000 --human
 *   npx ts-node contracts/scripts/stake-fren.ts --network testnet --amount 500 --human
 *
 * Flags:
 *   --amount   uint256  FREN amount to stake (in wei, or human-readable with --human)
 *   --human            Treat --amount as whole FREN tokens (auto-multiply by 1e18)
 *   --network  string  regtest | testnet | mainnet (default: regtest)
 *   --info             Only display staking info, do not stake
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
    FREN:  'bc1q_fren_placeholder',
    sFREN: 'bc1q_sfren_placeholder',
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
    amount: bigint;
    infoOnly: boolean;
} {
    const args = process.argv.slice(2);
    let network = 'regtest';
    let amountRaw = '1000000000000000000000'; // default: 1000 FREN
    let human = false;
    let infoOnly = false;

    for (let i = 0; i < args.length; i++) {
        switch (args[i]) {
            case '--network':
                network = args[++i];
                break;
            case '--amount':
                amountRaw = args[++i];
                break;
            case '--human':
                human = true;
                break;
            case '--info':
                infoOnly = true;
                break;
        }
    }

    let amount: bigint;
    if (human) {
        // Treat as whole tokens, multiply by 1e18.
        const wholeTokens = parseFloat(amountRaw);
        amount = BigInt(Math.floor(wholeTokens * 1e18));
    } else {
        amount = BigInt(amountRaw);
    }

    return { network, amount, infoOnly };
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

function formatTokens(wei: bigint, symbol: string): string {
    const whole = Number(wei) / 1e18;
    if (whole >= 1_000_000) {
        return `${(whole / 1_000_000).toFixed(2)}M ${symbol}`;
    }
    if (whole >= 1_000) {
        return `${(whole / 1_000).toFixed(2)}K ${symbol}`;
    }
    return `${whole.toFixed(4)} ${symbol}`;
}

function formatRatio(ratio: number): string {
    return ratio.toFixed(6);
}

// ---------------------------------------------------------------------------
// Staking info display
// ---------------------------------------------------------------------------

interface StakingInfo {
    frenBalance: bigint;
    sfrenBalance: bigint;
    totalFrenStaked: bigint;
    totalSfrenSupply: bigint;
    stakingRatio: number; // FREN per 1 sFREN
    pendingRewards: bigint;
    apr: number; // annualised percentage rate
}

async function fetchStakingInfo(): Promise<StakingInfo> {
    // TODO: Read on-chain state from the sFREN staking contract and FREN token.
    //
    //   const frenBalance    = await fren.balanceOf(await signer.getAddress());
    //   const sfrenBalance   = await sfren.balanceOf(await signer.getAddress());
    //   const totalFrenStaked = await fren.balanceOf(ADDRESSES.sFREN);
    //   const totalSfrenSupply = await sfren.totalSupply();
    //   const stakingRatio   = Number(totalFrenStaked) / Number(totalSfrenSupply);
    //   const pendingRewards = await sfren.pendingRewards(await signer.getAddress());
    //
    //   APR calculation:
    //     Track the ratio change over a known time period, or read from a
    //     rewards-per-second variable on the contract.
    //
    //   const rewardsPerSecond = await sfren.rewardsPerSecond();
    //   const annualRewards = Number(rewardsPerSecond) * 365.25 * 86400;
    //   const apr = (annualRewards / Number(totalFrenStaked)) * 100;

    // Placeholder values for demonstration.
    return {
        frenBalance: BigInt('5000000000000000000000'),     // 5000 FREN
        sfrenBalance: BigInt('2000000000000000000000'),     // 2000 sFREN
        totalFrenStaked: BigInt('10000000000000000000000000'), // 10M FREN
        totalSfrenSupply: BigInt('8500000000000000000000000'), // 8.5M sFREN
        stakingRatio: 10_000_000 / 8_500_000,                 // ~1.176 FREN per sFREN
        pendingRewards: BigInt('150000000000000000000'),       // 150 FREN
        apr: 12.5,
    };
}

function displayStakingInfo(info: StakingInfo): void {
    console.log('');
    console.log('='.repeat(55));
    console.log('  FREN Staking Overview');
    console.log('='.repeat(55));
    console.log(`  Your FREN balance   : ${formatTokens(info.frenBalance, 'FREN')}`);
    console.log(`  Your sFREN balance  : ${formatTokens(info.sfrenBalance, 'sFREN')}`);
    console.log(`  Pending Rewards     : ${formatTokens(info.pendingRewards, 'FREN')}`);
    console.log('-'.repeat(55));
    console.log(`  Total FREN Staked   : ${formatTokens(info.totalFrenStaked, 'FREN')}`);
    console.log(`  Total sFREN Supply  : ${formatTokens(info.totalSfrenSupply, 'sFREN')}`);
    console.log(`  Staking Ratio       : 1 sFREN = ${formatRatio(info.stakingRatio)} FREN`);
    console.log(`  Current APR         : ${info.apr.toFixed(2)}%`);
    console.log('='.repeat(55));

    // Show the value of the user's sFREN in FREN terms.
    const sfrenValueFren = Number(info.sfrenBalance) / 1e18 * info.stakingRatio;
    console.log(`  Your sFREN value    : ~${sfrenValueFren.toFixed(4)} FREN`);
    const unrealised = sfrenValueFren - (Number(info.sfrenBalance) / 1e18);
    if (unrealised > 0) {
        console.log(`  Unrealised gains    : ~${unrealised.toFixed(4)} FREN`);
    }
    console.log('');
}

// ---------------------------------------------------------------------------
// Stake execution
// ---------------------------------------------------------------------------

async function stakeFren(amount: bigint, info: StakingInfo): Promise<void> {
    if (amount <= BigInt(0)) {
        console.error('Stake amount must be greater than 0.');
        process.exit(1);
    }

    if (amount > info.frenBalance) {
        console.error(
            `Insufficient FREN balance. Have ${formatTokens(info.frenBalance, 'FREN')}, ` +
            `want to stake ${formatTokens(amount, 'FREN')}.`,
        );
        process.exit(1);
    }

    // Calculate expected sFREN received.
    const expectedSfren = Number(amount) / 1e18 / info.stakingRatio;

    console.log(`Staking ${formatTokens(amount, 'FREN')}...`);
    console.log(`  Expected sFREN: ~${expectedSfren.toFixed(4)} sFREN`);
    console.log(`  At ratio: 1 sFREN = ${formatRatio(info.stakingRatio)} FREN`);

    // TODO: Step 1 -- Approve sFREN contract to spend FREN.
    //
    //   const approveTx = await fren.approve(ADDRESSES.sFREN, amount);
    //   await approveTx.wait();
    //   console.log(`  Approve tx: ${approveTx.hash}`);

    console.log('  Approving FREN spend...');
    console.log('  Approved (placeholder).');

    // TODO: Step 2 -- Call stake / enter on the sFREN contract.
    //
    //   The sFREN contract follows a vault pattern:
    //     function stake(uint256 frenAmount) returns (uint256 sfrenMinted)
    //   or an ERC-4626 style deposit:
    //     function deposit(uint256 assets, address receiver) returns (uint256 shares)
    //
    //   const stakeTx = await sfren.stake(amount);
    //   const receipt = await stakeTx.wait();
    //   console.log(`  Stake tx: ${receipt.transactionHash}`);
    //
    //   Parse the event to get exact sFREN minted:
    //   const stakeEvent = receipt.events?.find((e: any) => e.name === 'Staked');
    //   const sfrenMinted = stakeEvent.args.shares;
    //   console.log(`  sFREN minted: ${sfrenMinted}`);

    console.log('  Staking FREN for sFREN...');
    console.log('  Staked (placeholder).');

    // ----- Post-stake balances ---------------------------------------------

    console.log('\n  Post-stake balances:');

    // TODO: Read updated balances.
    //   const newFrenBal  = await fren.balanceOf(await signer.getAddress());
    //   const newSfrenBal = await sfren.balanceOf(await signer.getAddress());
    //   console.log(`    FREN  : ${formatTokens(newFrenBal, 'FREN')}`);
    //   console.log(`    sFREN : ${formatTokens(newSfrenBal, 'sFREN')}`);

    const newFrenBalance = info.frenBalance - amount;
    const sfrenMinted = BigInt(Math.floor(expectedSfren * 1e18));
    const newSfrenBalance = info.sfrenBalance + sfrenMinted;

    console.log(`    FREN  : ${formatTokens(newFrenBalance, 'FREN')}`);
    console.log(`    sFREN : ${formatTokens(newSfrenBalance, 'sFREN')}`);
    console.log(`    sFREN value: ~${(Number(newSfrenBalance) / 1e18 * info.stakingRatio).toFixed(4)} FREN`);
}

// ---------------------------------------------------------------------------
// Claim rewards
// ---------------------------------------------------------------------------

async function claimRewards(info: StakingInfo): Promise<void> {
    if (info.pendingRewards <= BigInt(0)) {
        console.log('No pending rewards to claim.');
        return;
    }

    console.log(`\nClaiming ${formatTokens(info.pendingRewards, 'FREN')} in pending rewards...`);

    // TODO: Call the claim function on the sFREN contract.
    //   const claimTx = await sfren.claimRewards();
    //   const receipt = await claimTx.wait();
    //   console.log(`  Claim tx: ${receipt.transactionHash}`);

    console.log('  Rewards claimed (placeholder).');
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
    const { network, amount, infoOnly } = parseArgs();
    const _config = NETWORKS[network];
    if (!_config) {
        console.error(`Unknown network "${network}".`);
        process.exit(1);
    }

    console.log('FREN Staking');
    console.log('='.repeat(50));
    console.log(`Network : ${network}`);
    console.log(`sFREN   : ${ADDRESSES.sFREN}`);
    console.log(`FREN    : ${ADDRESSES.FREN}`);
    if (!infoOnly) {
        console.log(`Amount  : ${formatTokens(amount, 'FREN')}`);
    }
    console.log('='.repeat(50));

    // TODO: Initialise provider + wallet.
    // const provider = new Provider(config.rpcUrl);
    // const signer   = new Wallet(process.env.DEPLOYER_PRIVATE_KEY!, provider);
    // const fren  = new Contract(ADDRESSES.FREN, frenAbi, signer);
    // const sfren = new Contract(ADDRESSES.sFREN, sfrenAbi, signer);
    // console.log(`Wallet: ${await signer.getAddress()}`);

    // Fetch current staking info.
    const info = await fetchStakingInfo();
    displayStakingInfo(info);

    if (infoOnly) {
        console.log('Info-only mode. Exiting without staking.');
        return;
    }

    // Claim any pending rewards first.
    await claimRewards(info);

    // Execute the stake.
    await stakeFren(amount, info);

    // ----- Projected rewards -----------------------------------------------

    const totalStakedAfter = Number(info.totalFrenStaked + amount) / 1e18;
    const userStakeAfter = Number(amount) / 1e18;
    const userSharePct = (userStakeAfter / totalStakedAfter) * 100;

    console.log('\n  Projected Rewards:');
    console.log(`    Your share of pool : ${userSharePct.toFixed(4)}%`);

    const dailyRewards = (totalStakedAfter * (info.apr / 100)) / 365.25;
    const userDailyRewards = dailyRewards * (userStakeAfter / totalStakedAfter);

    console.log(`    Pool daily rewards : ~${dailyRewards.toFixed(4)} FREN`);
    console.log(`    Your daily rewards : ~${userDailyRewards.toFixed(4)} FREN`);
    console.log(`    Your monthly est.  : ~${(userDailyRewards * 30).toFixed(4)} FREN`);
    console.log(`    Your yearly est.   : ~${(userDailyRewards * 365.25).toFixed(4)} FREN`);
    console.log('');
}

main().catch((err) => {
    console.error('Staking failed:', err);
    process.exit(1);
});
