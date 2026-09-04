# Death Spiral Analysis — IRON/TITAN Failure Modes vs MIF Design

## What Happened to IRON/TITAN

Iron Finance launched on Polygon (June 2021) as a partially collateralized stablecoin:
- IRON stablecoin: 75% USDC + 25% TITAN
- Minting: deposit $0.75 USDC + $0.25 of TITAN → receive 1 IRON
- Redeeming: burn 1 IRON → receive $0.75 USDC + $0.25 of newly minted TITAN
- Peak TVL: ~$2 billion

### The Death Spiral Sequence

1. **Trigger**: Large TITAN holder sold position → TITAN price dropped
2. **Panic**: IRON lost peg slightly → arbitrageurs redeemed IRON
3. **Redemption loop**: Each IRON redemption minted new TITAN (to cover 25% non-USDC portion)
4. **Sell pressure**: Arbitrageurs immediately dumped minted TITAN → more price drop
5. **Oracle lag**: 10-minute TWAP reported higher TITAN price than reality → protocol minted fewer TITAN per redemption than it should have → each redemption was undercollateralized
6. **Cascade**: More IRON off-peg → more redemptions → more TITAN minted → more selling → TITAN → $0
7. **Result**: TITAN went to $0. IRON stabilized at $0.75 (the USDC floor). $2B TVL destroyed.

### Root Causes

| Cause | Details |
|-------|---------|
| Fast TCR adjustment | TCR dropped too quickly, increasing algorithmic exposure |
| Short TWAP (10 min) | Oracle lagged reality on Polygon's 2-second blocks |
| No mint cap | Unlimited TITAN minting during redemptions amplified spiral |
| No circuit breaker | Nothing to pause during extreme volatility |
| Unlimited positions | No cap on protocol size or redemption rate |
| Spot-sensitive design | Small price moves triggered large minting events |

## How MIF Prevents Each Failure Mode

### 1. Oracle: 30-min TWAP vs IRON's 10-min
- Bitcoin L1 has ~10-minute blocks (vs Polygon's 2 seconds)
- 30-minute TWAP = ~3 Bitcoin blocks of smoothing
- Much harder to manipulate than 10-min TWAP on fast chains
- Admin fallback prevents stale oracle disasters

### 2. TCR Adjustment: 0.5%/day vs IRON's fast adjustment
- IRON's TCR could change rapidly based on demand
- MIF limits TCR change to max 0.5% per day
- At maximum adjustment speed: 75% → 50% takes 50 days (impossible — floor is 75%)
- Gives market and governance time to react

### 3. TCR Floor: 75% vs IRON's race to zero
- IRON had no meaningful floor — CR dropped as confidence fell
- MIF enforces minimum 75% BTC backing at all times
- Even in worst case: MIF is still 75% BTC-backed (vs IRON's $0.75 USDC floor at 75%)
- BTC collateral cannot be diluted by minting

### 4. FREN Mint Cap: 2%/day vs IRON's unlimited TITAN minting
- IRON minted unlimited TITAN during redemptions — supply exploded exponentially
- MIF caps FREN minting to 2% of total supply per day
- This rate-limits the spiral: even if all redemptions happen, FREN dilution is bounded
- Creates a natural cooldown period

### 5. Circuit Breaker: 30% drop → pause
- IRON had no emergency stop
- MIF pauses redemptions if FREN drops >30% in 24 hours
- Pause lasts 6 blocks (~60 minutes on BTC L1)
- Allows market to stabilize before resuming

### 6. NFT Gate: 10K cap vs unlimited
- IRON had unlimited participants — anyone could mint/redeem at any scale
- MIF requires MiFREN NFT — capped at 10,000
- Natural limit on protocol size and redemption pressure
- Per-tier borrow caps further limit individual exposure

### 7. Phased Launch: 100% collateral first
- IRON launched with 75% USDC / 25% TITAN from day one
- MIF Phase 1: 100% BTC collateral, zero algorithmic component
- Seigniorage only introduced after TVL and trust are established
- Starts at 95% TCR (5% FREN) and decreases slowly

## Comparative Risk Matrix

| Risk Factor | IRON/TITAN | MIF Design | Risk Level |
|------------|-----------|-----------|-----------|
| Oracle manipulation | 10-min TWAP, fast chain | 30-min TWAP, slow chain | Low |
| Unlimited minting | Yes | 2%/day cap | Low |
| Fast CR adjustment | Yes | 0.5%/day max | Low |
| No circuit breaker | Correct | 30% drop → pause | Low |
| Unlimited exposure | Yes | 10K NFT cap | Low |
| Phase 1 seigniorage | Yes | No (100% BTC) | None |
| Minimum CR floor | No meaningful floor | 75% hard floor | Low |

## Residual Risks

Even with all mitigations, partial collateralization carries inherent risk:
1. Sustained BTC bear market erodes confidence regardless of mechanics
2. FREN token value ultimately depends on protocol fee generation
3. Circuit breaker can only pause, not prevent, fundamental insolvency
4. 75% floor means 25% algorithmic component still carries TITAN-style risk at scale

**Recommendation**: Keep Phase 1 (100% BTC collateral) running as long as possible. Only activate Phase 2 when protocol has significant TVL, proven revenue, and deep FREN liquidity.
