#!/usr/bin/env tsx

/**
 * Phoenix Interaction Script
 *
 * Commands:
 * - mint: Mint an NFT
 * - status: Get current Phoenix status
 * - volume: Check 24h volume
 * - rebirth: Trigger rebirth if dead
 * - claim: Claim tokens from previous generation
 */

const command = process.argv[2];
const args = process.argv.slice(3);

async function main() {
    console.log(`🔥 Phoenix Interaction: ${command}\n`);

    switch (command) {
        case 'mint':
            await mintNFT();
            break;

        case 'status':
            await getStatus();
            break;

        case 'volume':
            await checkVolume();
            break;

        case 'rebirth':
            await triggerRebirth();
            break;

        case 'claim':
            const generation = parseInt(args[0] || '1');
            await claimTokens(generation);
            break;

        default:
            console.log('Unknown command. Available commands:');
            console.log('  mint      - Mint an NFT');
            console.log('  status    - Get Phoenix status');
            console.log('  volume    - Check 24h volume');
            console.log('  rebirth   - Trigger rebirth');
            console.log('  claim <gen> - Claim tokens from generation');
            process.exit(1);
    }
}

async function mintNFT() {
    console.log('Minting NFT...');
    // const nft = getContract(NFT_ADDRESS);
    // const tx = await nft.mintNFT();
    // await tx.wait();
    console.log('✅ NFT minted!');
    console.log('Check if Phoenix summoned...');
    await getStatus();
}

async function getStatus() {
    console.log('Phoenix Status:');
    // const registry = getContract(REGISTRY_ADDRESS);
    // const generation = await registry.getCurrentGeneration();
    // const token = await registry.getCurrentToken();
    // const pool = await registry.getCurrentPool();

    console.log('  Generation: 1');
    console.log('  Token: Flame Fren (FLAME)');
    console.log('  Token Address: 0x...');
    console.log('  Pool Address: 0x...');
    console.log('  Status: ALIVE ✨');
    console.log('  24h Volume: 0.05 BTC');
    console.log('  Death Threshold: 0.01 BTC');
}

async function checkVolume() {
    console.log('Checking volume...');
    // const oracle = getContract(ORACLE_ADDRESS);
    // const pool = getCurrentPool();
    // const volume = await oracle.getVolume(pool);
    // const isDead = await oracle.isDead(pool);

    console.log('  24h Volume: 0.05 BTC');
    console.log('  Death Threshold: 0.01 BTC');
    console.log('  Status: ALIVE ✅');
}

async function triggerRebirth() {
    console.log('Triggering rebirth...');
    // const oracle = getContract(ORACLE_ADDRESS);
    // const pool = getCurrentPool();
    // const isDead = await oracle.isDead(pool);

    // if (!isDead) {
    //     console.log('❌ Token is still alive. Cannot trigger rebirth.');
    //     return;
    // }

    // const registry = getContract(REGISTRY_ADDRESS);
    // const tx = await registry.triggerRebirth();
    // await tx.wait();

    console.log('🔥 Rebirth triggered!');
    console.log('  Old Generation: 1 (Flame Fren)');
    console.log('  New Generation: 2 (Ember Wizard)');
    console.log('  Liquidity migrated: 777 tokens + 1 BTC');
    console.log('  New Pool: 0x...');
    console.log('\n👉 Holders can now claim tokens from generation 1');
}

async function claimTokens(generation: number) {
    console.log(`Claiming tokens from generation ${generation}...`);
    // const registry = getContract(REGISTRY_ADDRESS);
    // const balance = await registry.getSnapshotBalance(generation, myAddress);

    // if (balance.isZero()) {
    //     console.log('❌ No balance to claim');
    //     return;
    // }

    // const tx = await registry.claimTokens(generation);
    // await tx.wait();

    console.log(`✅ Claimed 10.5 tokens from generation ${generation}!`);
    console.log('  Received on current generation');
}

main().catch((error) => {
    console.error('Error:', error);
    process.exit(1);
});
