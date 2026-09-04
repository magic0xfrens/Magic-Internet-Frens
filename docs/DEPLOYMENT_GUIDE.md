# Magic Internet Frens — Deployment Guide

## Prerequisites

- Node.js 18+
- OP_NET CLI tools installed
- Bitcoin testnet wallet with test BTC
- OP_NET testnet access

## Deployment Order

Contracts must be deployed in dependency order:

1. **Oracle** — No dependencies, deploy first
2. **MIF Token** — No dependencies (Cauldron address set after)
3. **FREN Token** — No dependencies (staking standalone)
4. **MiFREN NFT** — No dependencies
5. **Cauldron** — Depends on Oracle, MIF, FREN, MiFREN addresses

## Step-by-Step: Testnet Deployment

### 1. Compile Contracts

```bash
cd contracts
npm install
npm run build
```

### 2. Deploy Oracle

```bash
npx ts-node scripts/deploy.ts --contract Oracle --network testnet
```

Set initial BTC/USD price:
```bash
npx ts-node scripts/deploy.ts --action set-price --price 85000000000000000000000 --network testnet
# Price = $85,000 with 18 decimals
```

### 3. Deploy MIF Token

```bash
npx ts-node scripts/deploy.ts --contract MIFToken --network testnet
```

### 4. Deploy FREN Token

```bash
npx ts-node scripts/deploy.ts --contract FRENToken --network testnet
```

### 5. Deploy MiFREN NFT

```bash
npx ts-node scripts/deploy.ts --contract MiFRENNFT --network testnet
```

### 6. Deploy Cauldron

```bash
npx ts-node scripts/deploy.ts --contract Cauldron \
  --oracle <ORACLE_ADDRESS> \
  --mif <MIF_ADDRESS> \
  --fren <FREN_ADDRESS> \
  --nft <NFT_ADDRESS> \
  --network testnet
```

### 7. Configure Permissions

```bash
# Whitelist Cauldron as MIF minter
npx ts-node scripts/deploy.ts --action whitelist-minter \
  --token <MIF_ADDRESS> \
  --minter <CAULDRON_ADDRESS>

# Set Cauldron as FREN reward distributor
npx ts-node scripts/deploy.ts --action set-distributor \
  --token <FREN_ADDRESS> \
  --distributor <CAULDRON_ADDRESS>
```

## Verification

### Basic Flow Test

```bash
# 1. Mint a MiFREN NFT
npx ts-node scripts/mint-nft.ts --network testnet

# 2. Deposit BTC and borrow MIF
npx ts-node scripts/deposit-borrow.ts --network testnet \
  --nft-id 1 --deposit 0.01 --borrow 500

# 3. Stake FREN
npx ts-node scripts/stake-fren.ts --network testnet --amount 1000

# 4. Test leverage loop
npx ts-node scripts/leverage-loop.ts --network testnet \
  --nft-id 1 --initial 0.01 --loops 3
```

### Liquidation Test

```bash
# Update oracle to lower price (trigger liquidation threshold)
npx ts-node scripts/liquidate.ts --network testnet --nft-id 1
```

## Mainnet Deployment

### Pre-mainnet Checklist

- [ ] All testnet tests passing
- [ ] Security review completed
- [ ] Oracle price feed verified
- [ ] Admin multisig configured
- [ ] Emergency pause tested
- [ ] Frontend connected and functional
- [ ] Documentation updated with mainnet addresses

### Mainnet Steps

1. Deploy contracts in same order as testnet
2. Configure multisig as admin (not single key)
3. Set conservative initial parameters:
   - LTV: 75%
   - Liquidation threshold: 80%
   - Low borrow caps initially
4. Whitelist Cauldron addresses
5. Update frontend constants with mainnet addresses
6. Monitor first 24 hours closely

## Contract Addresses

### Testnet
```
Oracle:     TODO
MIF Token:  TODO
FREN Token: TODO
MiFREN NFT: TODO
Cauldron:   TODO
```

### Mainnet
```
Oracle:     TODO
MIF Token:  TODO
FREN Token: TODO
MiFREN NFT: TODO
Cauldron:   TODO
```

## Emergency Procedures

### Pause Protocol
```bash
npx ts-node scripts/deploy.ts --action pause --contract <CAULDRON_ADDRESS>
```

### Update Oracle Price (admin)
```bash
npx ts-node scripts/deploy.ts --action set-price --price <NEW_PRICE> --contract <ORACLE_ADDRESS>
```

### Circuit Breaker (automatic)
- Triggers automatically if FREN drops >30% in 24h
- Pauses redemptions for 6 blocks (~60 minutes)
- Resumes automatically after pause period
