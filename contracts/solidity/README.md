# MagicFrens Smart Contracts

Presale and bonded token+NFT system for MagicFrens multichain deployment.

---

## 📁 Structure

```
contracts/solidity/
├── MagicFrensPresale.sol       # Presale contract (ETH/BNB payments)
├── MagicFrensPeg.sol           # Main token+NFT contract
├── deploy/
│   ├── DeployPresale.s.sol     # Presale deployment script
│   └── DeployMagicFrensPeg.s.sol # Token deployment script
└── test/
    └── MagicFrensPresale.t.sol # Presale tests
```

---

## 🚀 Quick Start

### 1. Setup
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install

# Create .env file
cp .env.example .env
# Edit .env with your values
```

### 2. Deploy Presale to Testnet
```bash
# Sepolia (Ethereum testnet)
forge script deploy/DeployPresale.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify

# Base Sepolia
forge script deploy/DeployPresale.s.sol \
  --rpc-url base_sepolia \
  --broadcast \
  --verify

# BNB Testnet
forge script deploy/DeployPresale.s.sol \
  --rpc-url bnb_testnet \
  --broadcast \
  --verify
```

### 3. Update Frontend
After deployment, update contract addresses in:
- `src/hooks/usePresale.ts` - Add presale addresses
- `src/constants/contracts.ts` - Add token addresses
- Update BTC_TREASURY_ADDRESS

### 4. Deploy Main Token
```bash
forge script deploy/DeployMagicFrensPeg.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify
```

### 5. Link Presale to Token
```bash
cast send YOUR_PRESALE_ADDRESS \
  "setTokenAddress(address)" \
  YOUR_MAGICFRENSPEG_ADDRESS \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

---

## 🧪 Testing

### Compile Contracts
```bash
forge build
```

### Run Tests
```bash
forge test
```

### Run Specific Test
```bash
forge test --match-contract MagicFrensPresaleTest -vv
```

### Gas Report
```bash
forge test --gas-report
```

---

## 📝 Contract Interactions

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

### End Presale
```bash
cast send YOUR_PRESALE_ADDRESS \
  "endPresale()" \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

### Withdraw Funds
```bash
cast send YOUR_PRESALE_ADDRESS \
  "withdraw()" \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

---

## 🔧 Troubleshooting

### Issue: "Encountered invalid solc version"
**Solution:** The OpenZeppelin library includes some files requiring 0.8.27. This doesn't affect our contracts. You can safely ignore these warnings for deployment purposes.

### Issue: "Module not found"
**Solution:** Run `forge install` to install dependencies

### Issue: "Missing environment variable"
**Solution:** Make sure .env file is properly configured with all required values

---

## 📚 Documentation

- Full deployment guide: `../../DEPLOYMENT_GUIDE.md`
- Frontend integration: `../../BUGS_FIXED.md`
- Foundry Book: https://book.getfoundry.sh

---

## 🔐 Security

- Audit smart contracts before mainnet deployment
- Use hardware wallet for deployment
- Test thoroughly on testnet first
- Never commit private keys to git

---

## ⚙️ Configuration

Edit `foundry.toml` to configure:
- Solc version
- Optimizer settings
- RPC endpoints
- Block explorer API keys

---

## 📦 Dependencies

- OpenZeppelin Contracts v5.x
- Forge Standard Library

---

## 🎯 Next Steps

1. ✅ Complete frontend setup
2. ⏳ Deploy to testnets
3. ⏳ Test presale flow
4. ⏳ Security audit
5. ⏳ Mainnet deployment

---

For detailed instructions, see `DEPLOYMENT_GUIDE.md` in the root directory.
