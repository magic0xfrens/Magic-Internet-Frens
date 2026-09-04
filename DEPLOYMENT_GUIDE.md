# 🚀 MagicFrens Deployment Guide

Complete guide for deploying MagicFrens Presale and MagicFrensPeg contracts to testnet and mainnet.

---

## 📋 Prerequisites

### 1. Install Foundry
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. Setup Environment
```bash
cd contracts/solidity
cp .env.example .env
```

Edit `.env` with your values:
```bash
PRIVATE_KEY=0x...                    # Your deployer wallet private key
TREASURY_ADDRESS=0x...               # Treasury wallet for funds
ETHERSCAN_API_KEY=...               # For contract verification
BASESCAN_API_KEY=...                # For Base verification
BSCSCAN_API_KEY=...                 # For BSC verification
```

### 3. Get Testnet Funds

**Sepolia (Ethereum testnet)**
- Faucet: https://sepoliafaucet.com
- Alternative: https://www.alchemy.com/faucets/ethereum-sepolia

**Base Sepolia**
- Bridge from Sepolia: https://bridge.base.org/deposit
- Faucet: https://www.coinbase.com/faucets/base-ethereum-goerli-faucet

**BNB Testnet**
- Faucet: https://testnet.bnbchain.org/faucet-smart

---

## 🧪 Phase 1: Deploy to Testnets

### Deploy Presale Contract

**Sepolia (Ethereum testnet)**
```bash
cd contracts/solidity

forge script deploy/DeployPresale.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify
```

**Base Sepolia**
```bash
forge script deploy/DeployPresale.s.sol \
  --rpc-url base_sepolia \
  --broadcast \
  --verify
```

**BNB Testnet**
```bash
forge script deploy/DeployPresale.s.sol \
  --rpc-url bnb_testnet \
  --broadcast \
  --verify
```

### Save Contract Addresses

After deployment, you'll see output like:
```
=== MagicFrensPresale Deployment ===
Presale Contract: 0x1234567890abcdef...
Treasury: 0xabcdef1234567890...
```

**Copy these addresses!** You'll need them for the frontend.

---

## 📝 Phase 2: Update Frontend

### 1. Update Presale Contract Addresses

Edit `src/hooks/usePresale.ts`:
```typescript
const PRESALE_ADDRESSES: Record<number, string> = {
  11155111: "0x...", // Sepolia - paste your deployment address
  84532: "0x...",    // Base Sepolia
  97: "0x...",       // BNB Testnet
};
```

### 2. Update BTC Treasury Address

Edit `src/hooks/usePresale.ts`:
```typescript
export const BTC_TREASURY_ADDRESS = "bc1q..."; // Your BTC wallet
```

### 3. Update Contract Constants

Edit `src/constants/contracts.ts`:
```typescript
const CONTRACT_ADDRESSES: Record<number, ContractAddresses> = {
  11155111: { // Sepolia
    magicFrensPeg: "",
    treasury: "0x...", // Your treasury address
  },
  84532: { // Base Sepolia
    magicFrensPeg: "",
    treasury: "0x...",
  },
  97: { // BNB Testnet
    magicFrensPeg: "",
    treasury: "0x...",
  },
};
```

---

## 🧪 Phase 3: Test on Testnet

### 1. Start Dev Server
```bash
npm run dev
```

### 2. Connect MetaMask

**Add Testnet Networks to MetaMask:**

**Sepolia**
- Network Name: Sepolia
- RPC URL: https://rpc.sepolia.org
- Chain ID: 11155111
- Currency: ETH
- Explorer: https://sepolia.etherscan.io

**Base Sepolia**
- Network Name: Base Sepolia
- RPC URL: https://sepolia.base.org
- Chain ID: 84532
- Currency: ETH
- Explorer: https://sepolia.basescan.org

**BNB Testnet**
- Network Name: BNB Testnet
- RPC URL: https://data-seed-prebsc-1-s1.binance.org:8545
- Chain ID: 97
- Currency: tBNB
- Explorer: https://testnet.bscscan.com

### 3. Test Presale Flow

1. Open http://localhost:5173
2. Click "🚀 JOIN PRESALE"
3. Select ETH payment method
4. Connect MetaMask (should auto-switch to testnet)
5. Enter amount (e.g., 10 tokens = 0.1 ETH)
6. Click "Connect Wallet & Buy"
7. Confirm transaction in MetaMask
8. Wait for confirmation
9. Check transaction on block explorer

### 4. Verify on Block Explorer

**Sepolia Etherscan:**
https://sepolia.etherscan.io/address/YOUR_PRESALE_ADDRESS

Check:
- ✅ Contract is verified
- ✅ Transaction appears in history
- ✅ `contributions` mapping updated
- ✅ `totalRaised` increased
- ✅ `totalTokensSold` increased

---

## 🎯 Phase 4: Deploy MagicFrensPeg (Main Contract)

### Create Deployment Script

Create `contracts/solidity/deploy/DeployMagicFrensPeg.s.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../MagicFrensPeg.sol";

contract DeployMagicFrensPeg is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        MagicFrensPeg token = new MagicFrensPeg(treasury);

        vm.stopBroadcast();

        console.log("=== MagicFrensPeg Deployment ===");
        console.log("Token Contract:", address(token));
        console.log("Treasury:", treasury);
        console.log("Max Supply:", token.MAX_SUPPLY());
        console.log("Commit Fee:", token.COMMIT_FEE());
    }
}
```

### Deploy to Testnet
```bash
forge script deploy/DeployMagicFrensPeg.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify
```

### Link Presale to Token

After deploying MagicFrensPeg, link it to the presale:

```bash
cast send YOUR_PRESALE_ADDRESS \
  "setTokenAddress(address)" \
  YOUR_MAGICFRENSPEG_ADDRESS \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

---

## 🎉 Phase 5: End Presale & Enable Claims

### 1. End Presale (Owner Only)
```bash
cast send YOUR_PRESALE_ADDRESS \
  "endPresale()" \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

### 2. Transfer Tokens to Presale Contract

Calculate amount: `totalTokensSold * 1e18`

```bash
# Example: 100 tokens sold = 100000000000000000000
cast send YOUR_MAGICFRENSPEG_ADDRESS \
  "transfer(address,uint256)" \
  YOUR_PRESALE_ADDRESS \
  100000000000000000000 \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

### 3. Test Claiming

From frontend:
1. Click "Claim Tokens"
2. Confirm transaction
3. Check wallet balance

---

## 🚨 Security Checklist

Before mainnet deployment:

- [ ] Audit smart contracts (consider OpenZeppelin Defender)
- [ ] Test all functions on testnet
- [ ] Verify presale limits (max 100 tokens per address)
- [ ] Test commit mechanism
- [ ] Test NFT transfers after commit
- [ ] Verify treasury withdrawals work
- [ ] Check emergency pause works
- [ ] Test edge cases (sold out, double claims, etc.)
- [ ] Review all contract addresses in frontend
- [ ] Backup private keys securely
- [ ] Test with multiple wallets
- [ ] Verify on-chain data matches expected values

---

## 🌐 Phase 6: Mainnet Deployment

⚠️ **ONLY after thorough testnet testing and security audit!**

### Deploy Presale to Mainnet

**Ethereum**
```bash
forge script deploy/DeployPresale.s.sol \
  --rpc-url ethereum \
  --broadcast \
  --verify
```

**Base**
```bash
forge script deploy/DeployPresale.s.sol \
  --rpc-url base \
  --broadcast \
  --verify
```

**BNB Chain**
```bash
forge script deploy/DeployPresale.s.sol \
  --rpc-url bnb \
  --broadcast \
  --verify
```

### Update Frontend for Mainnet

Edit `src/hooks/usePresale.ts`:
```typescript
const PRESALE_ADDRESSES: Record<number, string> = {
  1: "0x...",    // Ethereum mainnet
  8453: "0x...", // Base mainnet
  56: "0x...",   // BNB Chain mainnet
};
```

### Deploy to Production

```bash
npm run build
# Deploy dist/ to your hosting (Vercel, Netlify, etc.)
```

---

## 🔧 Troubleshooting

### Issue: "Transfer failed" during withdrawal
**Solution:** Check contract has enough ETH balance

### Issue: "Presale contract not deployed on this chain yet"
**Solution:** Verify address in `usePresale.ts` matches deployment

### Issue: MetaMask shows "Out of Gas"
**Solution:** User needs more testnet ETH for gas fees

### Issue: "Already claimed" error
**Solution:** User already claimed tokens, check transaction history

### Issue: Transaction pending forever
**Solution:** Check gas price, increase if needed, or wait for network congestion to clear

---

## 📊 Post-Deployment Monitoring

### Check Presale Stats
```bash
cast call YOUR_PRESALE_ADDRESS \
  "getPresaleStats()" \
  --rpc-url sepolia
```

### Check User Contribution
```bash
cast call YOUR_PRESALE_ADDRESS \
  "getContribution(address)" \
  USER_ADDRESS \
  --rpc-url sepolia
```

### Monitor Events
```bash
cast logs \
  --address YOUR_PRESALE_ADDRESS \
  --rpc-url sepolia
```

---

## 💰 Payment Tracking

### ETH/BNB Payments
Automatically tracked on-chain via presale contract.

### BTC Payments
Manual verification required:
1. User sends BTC to treasury address
2. User emails/messages transaction ID
3. Verify on https://blockchair.com
4. Manually whitelist address or record for airdrop

**Future:** Consider BTCPay Server for automated BTC payment verification.

---

## 🎁 Airdrop for BTC Contributors

After presale ends:

1. Compile list of BTC contributors
2. Calculate token amounts (1 token per 0.01 BTC equivalent)
3. Call `transfer()` to send tokens

```bash
# For each BTC contributor:
cast send YOUR_MAGICFRENSPEG_ADDRESS \
  "transfer(address,uint256)" \
  CONTRIBUTOR_ADDRESS \
  AMOUNT_IN_WEI \
  --rpc-url ethereum \
  --private-key $PRIVATE_KEY
```

---

## 📞 Need Help?

- Foundry Docs: https://book.getfoundry.sh
- OpenZeppelin: https://docs.openzeppelin.com
- Ethers.js: https://docs.ethers.org

---

## ✅ Deployment Checklist

### Testnet
- [ ] Deploy MagicFrensPresale to Sepolia
- [ ] Deploy MagicFrensPresale to Base Sepolia
- [ ] Deploy MagicFrensPresale to BNB Testnet
- [ ] Verify all contracts on explorers
- [ ] Update frontend with testnet addresses
- [ ] Test presale contributions
- [ ] Deploy MagicFrensPeg to testnets
- [ ] Link presale to token contract
- [ ] Test token claims
- [ ] Test commit mechanism
- [ ] Test NFT transfers

### Mainnet
- [ ] Security audit completed
- [ ] All testnet tests passing
- [ ] Deploy MagicFrensPresale to Ethereum
- [ ] Deploy MagicFrensPresale to Base
- [ ] Deploy MagicFrensPresale to BNB Chain
- [ ] Verify all mainnet contracts
- [ ] Update frontend with mainnet addresses
- [ ] Deploy frontend to production
- [ ] Test live with small amount
- [ ] Announce presale launch
- [ ] Monitor contract events
- [ ] Prepare for MagicFrensPeg deployment
- [ ] Setup liquidity on DEXs

---

**Good luck with your deployment! 🚀**
