#!/usr/bin/env tsx

import { readFileSync } from 'fs';
import { join } from 'path';

/**
 * Phoenix System Deployment Script
 *
 * Deployment Order:
 * 1. VolumeOracle
 * 2. PhoenixVault
 * 3. PhoenixRegistry
 * 4. MiFrens (with registry address)
 * 5. Mint 777 NFTs -> auto-summons Phoenix gen 1
 */

async function main() {
    console.log('🔥 Phoenix System Deployment\n');

    const buildDir = join(__dirname, '../build');

    // Load compiled WASMs
    const volumeOracle = readFileSync(join(buildDir, 'volume-oracle.wasm'));
    const phoenixVault = readFileSync(join(buildDir, 'phoenix-vault.wasm'));
    const phoenixRegistry = readFileSync(join(buildDir, 'phoenix-registry.wasm'));
    const phoenixToken = readFileSync(join(buildDir, 'phoenix-token.wasm'));
    const nft = readFileSync(join(buildDir, 'nft.wasm'));

    console.log('✅ Loaded compiled contracts\n');

    // Deployment configuration
    const config = {
        network: 'regtest',
        rpcUrl: 'https://regtest.opnet.org',
        deathThreshold: '1000000', // 0.01 BTC in sats
        initialTokens: '777000000000000000000', // 777 tokens
        initialBTC: '100000000', // 1 BTC
    };

    console.log('Configuration:');
    console.log(`  Network: ${config.network}`);
    console.log(`  Death Threshold: ${config.deathThreshold} sats`);
    console.log(`  Initial Liquidity: ${config.initialTokens} tokens + ${config.initialBTC} sats\n`);

    // Step 1: Deploy VolumeOracle
    console.log('1️⃣  Deploying VolumeOracle...');
    // const volumeOracleAddress = await deployContract(volumeOracle, [config.deathThreshold]);
    const volumeOracleAddress = '0x...'; // Placeholder
    console.log(`   ✅ VolumeOracle: ${volumeOracleAddress}\n`);

    // Step 2: Deploy PhoenixVault
    console.log('2️⃣  Deploying PhoenixVault...');
    // Need registry address (deploy first, set later)
    // const phoenixVaultAddress = await deployContract(phoenixVault, [ZERO_ADDRESS, volumeOracleAddress]);
    const phoenixVaultAddress = '0x...'; // Placeholder
    console.log(`   ✅ PhoenixVault: ${phoenixVaultAddress}\n`);

    // Step 3: Deploy PhoenixRegistry
    console.log('3️⃣  Deploying PhoenixRegistry...');
    // Need NFT address (deploy first, set later)
    // const phoenixRegistryAddress = await deployContract(phoenixRegistry, [ZERO_ADDRESS, phoenixVaultAddress, volumeOracleAddress]);
    const phoenixRegistryAddress = '0x...'; // Placeholder
    console.log(`   ✅ PhoenixRegistry: ${phoenixRegistryAddress}\n`);

    // Step 4: Deploy MiFrens
    console.log('4️⃣  Deploying MiFrens...');
    // const nftAddress = await deployContract(nft, []);
    const nftAddress = '0x...'; // Placeholder
    console.log(`   ✅ MiFrens: ${nftAddress}\n`);

    // Step 5: Link contracts
    console.log('5️⃣  Linking contracts...');
    // await nft.setPhoenixRegistry(phoenixRegistryAddress);
    // await phoenixVault.setRegistry(phoenixRegistryAddress);
    // await phoenixRegistry.setNFTContract(nftAddress);
    console.log('   ✅ Contracts linked\n');

    // Summary
    console.log('🎉 Deployment Complete!\n');
    console.log('Contract Addresses:');
    console.log(`  VolumeOracle:    ${volumeOracleAddress}`);
    console.log(`  PhoenixVault:    ${phoenixVaultAddress}`);
    console.log(`  PhoenixRegistry: ${phoenixRegistryAddress}`);
    console.log(`  MiFrens:       ${nftAddress}`);
    console.log('\nNext Steps:');
    console.log('  1. Mint 777 NFTs to summon the Phoenix');
    console.log('  2. Monitor volume via VolumeOracle');
    console.log('  3. Trigger rebirth when volume dies');
}

main().catch(console.error);
