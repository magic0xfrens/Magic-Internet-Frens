# Magic Internet Frens — Tokenomics

## Token Distribution: $FREN

| Allocation | Percentage | Amount | Vesting |
|-----------|-----------|--------|---------|
| Liquidity Mining | 50% | 500,000,000 | 3-year linear vest |
| Team | 20% | 200,000,000 | 4-year vest, 1-year cliff |
| Protocol Treasury | 15% | 150,000,000 | DAO-controlled |
| Initial Liquidity | 10% | 100,000,000 | DEX launch (MotoSwap) |
| NFT Holder Airdrop | 5% | 50,000,000 | At launch |

**Total Supply**: 1,000,000,000 FREN

### Airdrop Multipliers (by NFT tier)
- Diamond: 4x base allocation
- Gold: 2x base allocation
- Silver: 1.5x base allocation
- Bronze: 1x base allocation

## Revenue Flows

### Fee Sources
1. **Borrow Opening Fee**: 0.5% of each MIF borrow amount
2. **Interest Accrual**: Variable APR based on utilization curve
3. **Liquidation Penalty**: 5% of liquidated collateral
4. **NFT Mint Revenue**: BTC from MiFREN mints

### Fee Distribution
| Source | sFREN Stakers | Protocol Treasury | Liquidators |
|--------|--------------|-------------------|-------------|
| Borrow Fee | 100% | — | — |
| Interest | 100% | — | — |
| Liquidation Penalty | 10% | 40% | 50% |
| NFT Mint Revenue | 30% | 70% | — |

## sFREN Staking Mechanics

- **Model**: xSUSHI-style continuously compounding
- **Stake**: Deposit FREN → receive sFREN
- **Unstake**: Burn sFREN → receive FREN (24-hour timelock)
- **Value accrual**: Protocol fees are used to buy FREN and add to staking pool
- **sFREN/FREN ratio**: Increases over time as fees compound
- **Governance**: sFREN holders receive voting power

## Interest Rate Model

Utilization-based variable rate:

```
Utilization < 80%:  APR = 1% + (utilization / 80%) * 4%    [1% to 5% linear]
Utilization >= 80%: APR = 5% + ((utilization - 80%) / 20%)^2 * 45%  [5% to 50% exponential]
```

This discourages full utilization while keeping rates attractive at normal usage.

## Phase 2: Seigniorage Mechanics

When TCR < 100%:
- **Minting**: Users deposit (TCR%) BTC + (1-TCR%) FREN to mint MIF
- **Redeeming**: Users receive (ECR%) BTC + (1-ECR%) newly minted FREN for burning MIF
- **ECR** = Effective Collateral Ratio = actual BTC reserves / total MIF supply

### Safety Parameters
- TCR floor: 75% (always at least 75% BTC-backed)
- TCR adjustment speed: max 0.5% per day
- FREN daily mint cap: 2% of total supply during redemptions
- Circuit breaker: pause at 30% FREN price drop in 24h

## Flywheel Dynamics

**Bull cycle**:
BTC locked → MIF minted → liquidity grows → fees grow → FREN yield up → FREN price up → more NFT demand → more BTC locked

**Bear cycle mitigations**:
- Conservative 75% LTV limits liquidation cascades
- 10K NFT cap limits total protocol exposure
- Phase 1 runs with 100% BTC collateral (no seigniorage risk)
- Circuit breakers prevent runaway FREN dilution
