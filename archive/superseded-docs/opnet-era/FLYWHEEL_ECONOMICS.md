# Magic Internet Frens — Flywheel Economics

## The Virtuous Cycle

```
                  ┌─── NFT demand ◄──────────┐
                  │                           │
                  ▼                           │
         Buy MiFREN NFT                       │
                  │                           │
                  ▼                           │
         Deposit BTC ──► Borrow MIF           │
                  │           │               │
                  │           ▼               │
                  │    Provide MIF liquidity   │
                  │           │               │
                  │           ▼               │
                  │    Earn trading fees       │
                  │    + FREN farming rewards  │
                  │           │               │
                  │           ▼               │
                  │    Stake FREN → sFREN     │
                  │           │               │
                  │           ▼               │
                  │    Protocol revenue        │
                  │    accrues to sFREN ───────┘
                  │
                  ▼
         Leverage loop (cook)
         1 BTC → ~3-4x exposure
```

## Revenue Projections

### Conservative Case: $10M TVL

| Revenue Source | Annual Rate | Annual Revenue |
|---------------|-----------|---------------|
| Borrow Opening Fee (0.5%) | Assume 2x turnover | $100,000 |
| Interest (avg 3% APR) | 60% utilization | $180,000 |
| Liquidation Penalty (5%) | 5% of TVL liquidated | $25,000 |
| NFT Mints (0.001 BTC) | 5,000 mints at $85k BTC | $425,000 |
| **Total** | | **$730,000** |

### sFREN Staker Yield
- sFREN receives: 100% borrow fee + 100% interest + 10% liquidation + 30% NFT revenue
- At $10M TVL: ~$435,000/year to stakers
- If 30% of FREN supply staked ($30M worth at $0.10): **1.45% APR**

### Growth Case: $100M TVL

| Revenue Source | Annual Rate | Annual Revenue |
|---------------|-----------|---------------|
| Borrow Opening Fee | 3x turnover | $1,500,000 |
| Interest | 70% utilization | $2,100,000 |
| Liquidation Penalty | 3% liquidated | $150,000 |
| NFT Mints | All 10K minted | $850,000 (one-time) |
| **Total** | | **$4,600,000** |

### Breakeven Analysis
- Team cost assumption: $500K/year
- Infrastructure: $50K/year
- Protocol needs ~$600K/year minimum revenue to sustain
- **Breakeven TVL: ~$8M** (conservative assumptions)

## Leverage Loop Economics

### cook() Loop Math

Starting: 1 BTC as collateral, BTC at $85,000

| Loop | Collateral | Borrow (75% LTV) | Swap to BTC | Total Collateral |
|------|-----------|------------------|------------|-----------------|
| 0 | 1.000 BTC | $63,750 MIF | 0.750 BTC | 1.750 BTC |
| 1 | 1.750 BTC | $47,812 MIF | 0.563 BTC | 2.313 BTC |
| 2 | 2.313 BTC | $35,859 MIF | 0.422 BTC | 2.734 BTC |
| 3 | 2.734 BTC | $26,894 MIF | 0.316 BTC | 3.051 BTC |

**Result**: 1 BTC → ~3.05x BTC exposure after 4 loops
- Total debt: ~$174,315 MIF
- Effective leverage: ~3x
- Liquidation at: BTC dropping to ~$57,000 (33% decline)
- Opening fees paid: ~$872 MIF (0.5% each loop)

### Why Users Leverage
- **Bull market**: 3x BTC exposure without 3x capital
- **Fee comparison**: 0.5% opening fee vs perpetual futures funding rates (often 30-100% APR)
- **No expiration**: Unlike futures, leverage position stays open indefinitely
- **Self-custody**: Collateral stays on Bitcoin L1

## NFT Floor Price Economics

### Demand Drivers
- Required for protocol access (functional utility)
- 10K hard cap creates scarcity
- Higher tiers = higher borrow caps + lower fees
- Diamond (500 total) = 50% fee discount + 10 BTC borrow cap

### Estimated Floor Prices (at $100M TVL)
- Bronze: ~0.005 BTC ($425) — basic access
- Silver: ~0.02 BTC ($1,700) — 10% fee savings + higher cap
- Gold: ~0.1 BTC ($8,500) — 25% fee savings + 2 BTC cap
- Diamond: ~0.5 BTC ($42,500) — 50% fee savings + 10 BTC cap + governance

### Secondary Market Revenue
- 2.5% royalty on secondary sales (if OP_NET supports)
- Higher TVL → higher NFT demand → higher floor → more royalty revenue

## Sustainability Thresholds

| TVL | Protocol Revenue | sFREN APR | Self-Sustaining? |
|-----|-----------------|----------|-----------------|
| $1M | ~$73K | 0.24% | No |
| $5M | ~$365K | 1.22% | Marginal |
| $10M | ~$730K | 2.43% | Yes |
| $50M | ~$3.2M | 10.7% | Very sustainable |
| $100M | ~$4.6M | 15.3% | Highly sustainable |

**The flywheel becomes self-sustaining at approximately $8-10M TVL**, where protocol revenue covers all costs and sFREN yields become attractive enough to maintain FREN demand.
