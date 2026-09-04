# 🚀 Cauldron Protocol - Testnet Deployment Guide

## Current Status

**Dependencies**: ✅ Installed
**Contracts**: ⚠️ Need import updates
**Deployment Scripts**: ✅ Ready
**Network Config**: ✅ OPNet Testnet configured

---

## 🔧 Required Fixes Before Deployment

### 1. Update Contract Imports

All contracts currently import `u256` from `@btc-vision/as-bignum/assembly` which no longer exists.

**Fix**: Update all contracts to import `u256` from `@btc-vision/btc-runtime`:

```typescript
// OLD (broken):
import { u256 } from '@btc-vision/as-bignum/assembly';

// NEW (working):
import { u256 } from '@btc-vision/btc-runtime/runtime/math/asm-u256';
```

**Files to update**:
- `/contracts/src/cauldron/VolumeOracle.ts`
- `/contracts/src/cauldron/CauldronRegistry.ts`
- `/contracts/src/cauldron/CauldronToken.ts`
- `/contracts/src/cauldron/CauldronVault.ts`
- `/contracts/src/cauldron/HolderSnapshot.ts`
- `/contracts/src/cauldron/MotoSwapIntegration.ts`
- `/contracts/src/nft/MiFRENNFT.ts`
- `/contracts/src/events/PhoenixEvents.ts` (rename to CauldronEvents.ts)
- `/contracts/src/lib/constants.ts`

### 2. Rename Phoenix → Cauldron (Optional for V1)

For clean branding, rename all Phoenix references to Cauldron:
- `PhoenixRegistry` → `CauldronRegistry`
- `PhoenixVault` → `CauldronVault`
- `PhoenixToken` → `CauldronToken`
- `PhoenixEvents` → `CauldronEvents`
- Update all imports and class names

### 3. Add AI Metadata Parameters (V2 Feature)

Current contracts have hardcoded 6-creature cycle. For AI-generated metadata:

**Update `CauldronRegistry.triggerRebirth()`:**

```typescript
// CURRENT (hardcoded):
public triggerRebirth(): BytesWriter {
    const metadata = this._getMetadataForGeneration(nextGen);
    // Uses mod 6 cycle
}

// FUTURE (AI-powered):
public triggerRebirth(
    newName: string,
    newSymbol: string,
    imageIPFS: string,
    lore: string
): BytesWriter {
    // Deploy with AI-generated metadata
    this._deployNextGeneration(nextGen, newName, newSymbol, imageIPFS, lore);
}
```

---

## 📦 Build Commands

Once imports are fixed:

```bash
cd /Users/0x0010110/Documents/GitHub/MagicFrens/contracts

# Build individual contracts
npm run build:volume-oracle
npm run build:cauldron-vault
npm run build:cauldron-registry
npm run build:cauldron-token
npm run build:nft

# Or build all at once
npm run build:cauldron
```

Expected output: `build/*.wasm` files

---

## 🌐 Testnet Deployment

### Network Configuration

**OPNet Testnet (Signet Fork)**:
- RPC URL: `https://testnet.opnet.org`
- Network: `networks.opnetTestnet` from `@btc-vision/bitcoin`
- Explorer: https://explorer.opnet.org (testnet)

**CRITICAL**: Do NOT use `networks.testnet` (that's Bitcoin Testnet4, which OPNet doesn't support)

```typescript
import { networks } from '@btc-vision/bitcoin';

// CORRECT:
const network = networks.opnetTestnet;

// WRONG (will fail):
const network = networks.testnet;
```

### Wallet Setup

Create `.env` file:

```bash
DEPLOYER_PRIVATE_KEY=your_private_key_here
DEPLOYER_ADDRESS=your_testnet_bitcoin_address
```

Get testnet BTC from faucet for gas fees.

### Deployment Order

```bash
# 1. Deploy VolumeOracle
npm run deploy -- --contract volume-oracle --network testnet

# 2. Deploy CauldronVault
npm run deploy -- --contract cauldron-vault --network testnet --oracle <ORACLE_ADDRESS>

# 3. Deploy CauldronRegistry
npm run deploy -- --contract cauldron-registry --network testnet --vault <VAULT_ADDRESS> --oracle <ORACLE_ADDRESS>

# 4. Deploy MiFRENNFT (777 supply)
npm run deploy -- --contract nft --network testnet --registry <REGISTRY_ADDRESS>

# 5. Link contracts
npm run configure -- --contract vault --method setRegistry --args <REGISTRY_ADDRESS>
npm run configure -- --contract registry --method setNFTContract --args <NFT_ADDRESS>
npm run configure -- --contract nft --method setPhoenixRegistry --args <REGISTRY_ADDRESS>
```

### Full Deployment Script

Create `/contracts/scripts/deploy-cauldron-testnet.ts`:

```typescript
#!/usr/bin/env tsx

import { TransactionFactory } from "@btc-vision/transaction";
import { JSONRpcProvider } from "opnet";
import { networks } from "@btc-vision/bitcoin";
import * as fs from "fs";
import * as path from "path";

async function deployToTestnet() {
    console.log("🔮 Deploying Cauldron Protocol to OPNet Testnet\n");

    const provider = new JSONRpcProvider(
        "https://testnet.opnet.org",
        networks.opnetTestnet // MUST use opnetTestnet!
    );

    const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
    if (!privateKey) {
        throw new Error("Set DEPLOYER_PRIVATE_KEY in .env");
    }

    // Load compiled WASMs
    const buildDir = path.join(__dirname, "../build");
    const volumeOracle = fs.readFileSync(path.join(buildDir, "volume-oracle.wasm"));
    const cauldronVault = fs.readFileSync(path.join(buildDir, "cauldron-vault.wasm"));
    const cauldronRegistry = fs.readFileSync(path.join(buildDir, "cauldron-registry.wasm"));
    const nft = fs.readFileSync(path.join(buildDir, "nft.wasm"));

    const factory = new TransactionFactory();

    // Step 1: Deploy VolumeOracle
    console.log("1️⃣  Deploying VolumeOracle...");
    const oracleTx = await factory.signDeployment({
        bytecode: volumeOracle,
        signer: wallet.keypair,
        mldsaSigner: wallet.mldsaKeypair,
        network: networks.opnetTestnet,
        feeRate: 10,
        priorityFee: 1000n,
        from: wallet.address,
    });
    const oracleReceipt = await provider.sendRawTransaction(oracleTx.serialize());
    const oracleAddress = oracleReceipt.contractAddress;
    console.log(`✅ VolumeOracle: ${oracleAddress}\n`);

    // Step 2: Deploy CauldronVault
    console.log("2️⃣  Deploying CauldronVault...");
    // ... (similar pattern)

    // Step 3: Deploy CauldronRegistry
    console.log("3️⃣  Deploying CauldronRegistry...");
    // ... (similar pattern)

    // Step 4: Deploy MiFRENNFT (777 supply)
    console.log("4️⃣  Deploying MiFRENNFT...");
    // ... (similar pattern)

    // Step 5: Link contracts
    console.log("5️⃣  Linking contracts...");
    // Call setRegistry, setNFTContract, setPhoenixRegistry

    console.log("\n🎉 Deployment Complete!\n");
    console.log("Contract Addresses:");
    console.log(`  VolumeOracle:    ${oracleAddress}`);
    console.log(`  CauldronVault:   ${vaultAddress}`);
    console.log(`  CauldronRegistry: ${registryAddress}`);
    console.log(`  MiFRENNFT:       ${nftAddress}`);

    // Save addresses to file
    fs.writeFileSync(
        "deployed-testnet.json",
        JSON.stringify({
            network: "opnet-testnet",
            volumeOracle: oracleAddress,
            cauldronVault: vaultAddress,
            cauldronRegistry: registryAddress,
            miFRENNFT: nftAddress,
            deployedAt: new Date().toISOString(),
        }, null, 2)
    );
}

deployToTestnet().catch(console.error);
```

---

## 🧪 Post-Deployment Testing

### 1. Mint 777 NFTs

```bash
# Mint NFTs to trigger first summoning
npm run interact -- mint-nft --count 777
```

When 777th NFT mints, `MiFRENNFT` automatically calls `CauldronRegistry.summonGenesis()`.

### 2. Verify First Generation

```bash
# Check current generation
npm run interact -- get-current-generation
# Expected: 1

# Check current token address
npm run interact -- get-current-token
# Expected: <GEN_1_TOKEN_ADDRESS>
```

### 3. Test Death Detection

```bash
# Check if token is dead (volume < 0.01 BTC/24h)
npm run interact -- is-dead
# Expected: false (initial state)

# Wait 24h or manually trigger rebirth after volume drops
npm run interact -- trigger-rebirth
# Expected: Deploys generation 2
```

### 4. Test Holder Claims

```bash
# If you held tokens in gen 1, claim in gen 2
npm run interact -- claim-tokens --generation 1
# Expected: Mints equivalent tokens in current generation
```

---

## 📊 Expected Contract Sizes

Compiled WASM files should be approximately:

| Contract | Size |
|----------|------|
| VolumeOracle | ~15 KB |
| CauldronVault | ~20 KB |
| CauldronRegistry | ~40 KB |
| CauldronToken | ~30 KB |
| MiFRENNFT | ~35 KB |

---

## 🐛 Common Issues

### Issue: `AssertionError: assertion failed`

**Cause**: Old import path for `u256`
**Fix**: Update all imports to use `@btc-vision/btc-runtime/runtime/math/asm-u256`

### Issue: `Network 'testnet' not supported`

**Cause**: Using wrong network constant
**Fix**: Use `networks.opnetTestnet` NOT `networks.testnet`

### Issue: `Transaction failed: insufficient funds`

**Cause**: Not enough testnet BTC for gas
**Fix**: Get testnet BTC from faucet

### Issue: `Contract deployment timeout`

**Cause**: Testnet might be slow
**Fix**: Increase timeout in provider config or retry

---

## 📝 Next Steps After Testnet Deployment

1. **Test Full Lifecycle**:
   - Summon generation 1
   - Trade until volume dies
   - Trigger rebirth to generation 2
   - Claim tokens from generation 1

2. **Build AI Oracle** (V2):
   - Create off-chain service
   - Integrate Claude API for identity generation
   - Integrate DALL-E for artwork
   - Add community voting system

3. **Deploy to Mainnet**:
   - Use same process but with `networks.bitcoin`
   - RPC: `https://mainnet.opnet.org`
   - Real BTC required for gas

4. **Update Frontend**:
   - Add deployed contract addresses to `/src/constants/`
   - Test NFT minting UI
   - Test rebirth monitoring
   - Add claim interface

---

## 🔗 Resources

- **OPNet Docs**: https://docs.opnet.org
- **OPNet GitHub**: https://github.com/btc-vision
- **Testnet Explorer**: https://explorer.opnet.org
- **Discord**: https://discord.gg/opnet

---

## ✅ Deployment Checklist

- [ ] Fix all contract imports (`u256` path)
- [ ] Compile all contracts to WASM
- [ ] Set up `.env` with deployer private key
- [ ] Get testnet BTC from faucet
- [ ] Deploy VolumeOracle
- [ ] Deploy CauldronVault
- [ ] Deploy CauldronRegistry
- [ ] Deploy MiFRENNFT
- [ ] Link all contracts together
- [ ] Save deployment addresses
- [ ] Mint 777 NFTs
- [ ] Verify first generation summoned
- [ ] Test death detection
- [ ] Test rebirth mechanism
- [ ] Test holder claims
- [ ] Document any issues
- [ ] Prepare for mainnet deployment

---

**Status**: Ready for deployment after contract import fixes.

**Estimated Time**: 2-3 hours (30min fixes + 1-2h deployment + testing)

**Cost**: ~0.01 BTC testnet (free from faucet)

---

Built by Magic Internet Frens 🔮
March 11, 2026
