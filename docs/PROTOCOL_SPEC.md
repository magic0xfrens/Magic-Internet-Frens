# Magic Internet Frens — Protocol Specification

## Overview

Magic Internet Frens (MIF) is an algorithmic stablecoin protocol on OP_NET (Bitcoin L1) combining Abracadabra's MIM Cauldron lending mechanics, TITAN flywheel tokenomics, and NFT-gated access.

## Core Tokens

### $MIF — Magic Internet Frens Dollar (Stablecoin)
- **Standard**: OP_20
- **Peg**: $1.00 USD
- **Decimals**: 18
- **Minting**: Only by whitelisted Cauldron contracts
- **Burning**: Any holder can burn their own MIF
- **Peg mechanism**: Arbitrage-based (MIM model)
  - MIF < $1: buy cheap MIF → repay debt at face value → profit → price up
  - MIF > $1: mint from Cauldron → sell for > $1 → price down

### $FREN — Governance + Seigniorage Token
- **Standard**: OP_20
- **Decimals**: 18
- **Max Supply**: 1,000,000,000 (1B)
- **Staking**: FREN → sFREN (xSUSHI model, continuously compounding)
- **Revenue streams for sFREN holders**:
  - 0.5% borrow opening fee
  - Variable interest accrual
  - 10% of liquidation penalties
  - 30% of NFT mint revenue
- **24-hour unstaking timelock** (prevents flash-loan governance attacks)

### MiFREN NFT — Access Pass
- **Standard**: OP_721
- **Max Supply**: 10,000
- **Tiers**: Bronze (60%), Silver (25%), Gold (10%), Diamond (5%)
- **Gate**: Must hold MiFREN to access any Cauldron
- **One NFT = one active position** (NFT locked while debt open)
- **Transferable**: Yes (when no open position)

## Tier Benefits

| Tier | Distribution | Fee Discount | Liquidation Grace | Max Borrow |
|------|-------------|-------------|------------------|-----------|
| Bronze | 60% | 0% | 0 blocks | 0.1 BTC |
| Silver | 25% | 10% | 1 block | 0.5 BTC |
| Gold | 10% | 25% | 2 blocks | 2 BTC |
| Diamond | 5% | 50% | 3 blocks | 10 BTC |

## Cauldron — Core Lending Market

Isolated lending market forked from Abracadabra's Cauldron, adapted for OP_NET + BTC.

### Parameters
- **Collateral**: BTC (native satoshis)
- **Borrow asset**: $MIF
- **LTV**: 75%
- **Liquidation threshold**: 80%
- **Liquidation penalty**: 5%
- **Borrow opening fee**: 0.5% (flat)
- **Interest rate**: Variable (utilization curve)
  - 0-80% utilization: 1-5% APR (linear)
  - 80-100% utilization: 5-50% APR (exponential)

### Core Flow
1. `deposit(nftId, btcAmount)` — Verify NFT ownership + tier → lock BTC
2. `borrow(nftId, mifAmount)` — Check LTV → mint MIF → charge opening fee
3. `repay(nftId, mifAmount)` — Burn MIF → reduce debt
4. `withdraw(nftId, btcAmount)` — Check LTV still safe → return BTC
5. `liquidate(nftId)` — If LTV > 80% → repay debt, seize collateral minus penalty

### Leveraged Looping (cook function)
Batch multiple actions atomically:
1. Deposit BTC → 2. Borrow MIF → 3. Swap MIF for BTC → 4. Deposit more BTC → repeat

At 75% LTV: theoretical max ~4x leverage through looping.

**Security**: Solvency check ONLY at END of cook(), not between actions.

## Oracle
- **V1**: Admin-set price with timelock
- **V2**: 30-minute TWAP from OP_NET DEX
- **Fallback**: Admin override with governance timelock

## Phase 2: Partial Collateralization (CauldronV2)
- Target Collateral Ratio (TCR): starts at 100%, can lower via governance
- Mint 1 MIF = deposit (TCR%) BTC + (1-TCR%) FREN
- Redeem 1 MIF = receive (ECR%) BTC + (1-ECR%) newly minted FREN
- **Safety rails**: TCR floor 75%, max 0.5%/day adjustment, FREN mint cap 2%/day
- **Circuit breaker**: Pause redemptions if FREN drops >30% in 24h

## Launch Strategy
- **Phase 1 (months 1-3)**: 100% BTC collateral only. No seigniorage. Pure MIM fork.
- **Phase 2 (months 3-6)**: Introduce FREN at 95% TCR (5% FREN). Test with training wheels.
- **Phase 3 (months 6+)**: Lower TCR via governance. Never below 75%.
