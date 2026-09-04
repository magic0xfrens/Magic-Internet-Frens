# Phoenix Token System - Immortal Ever-Reborning Token

## Overview
The Phoenix is an immortal token summoned by 777 Magic Internet Wizard Frens. When trading volume dies, it automatically redeploys itself with new metadata and migrates all liquidity to a fresh MotoSwap pool.

## Key Features
- ✅ **0% Tax** - Pure trading, no fees
- 🔥 **Immortal** - Never truly dies, always reborn
- 🔄 **Auto-Migration** - Liquidity moves automatically when volume dies
- 🎨 **Evolving Metadata** - Each generation has unique name/symbol
- 📸 **Snapshot Claims** - Holders claim tokens on new generation
- 🔒 **Death-Based Locking** - Liquidity locked until volume dies

## Contract Architecture

### 1. PhoenixToken (OP20)
- 0% tax on transfers
- Generation tracking
- Alive/dead status
- Each generation = unique contract

### 2. PhoenixRegistry (Orchestrator)
- Manages rebirth process
- Snapshots holder balances
- Handles claims
- Cycles through metadata

### 3. PhoenixVault (Liquidity Locker)
- Holds LP tokens
- Unlocks only when oracle confirms death
- Migrates liquidity between generations

### 4. VolumeOracle
- Tracks 24h volume from MotoSwap
- Death threshold: <0.01 BTC in 24h
- Permissionless updates

### 5. MiFRENNFT (Modified)
- Max supply: 777 (changed from 10,000)
- Triggers Phoenix summoning when #777 minted

## Lifecycle

```
STEP 1: SUMMONING
Mint NFT #777 → PhoenixRegistry.summonGenesis()
→ Deploy "Flame Fren" (FLAME)
→ Create MotoSwap pool
→ Add initial liquidity (777 FLAME + 1 BTC)
→ Lock liquidity in vault

STEP 2: TRADING
Users trade FLAME on MotoSwap (0% tax)
VolumeOracle tracks 24h volume

STEP 3: DEATH
24h volume < 0.01 BTC
Oracle marks as dead

STEP 4: REBIRTH
Anyone calls PhoenixRegistry.triggerRebirth()
→ Snapshot all FLAME holders
→ Deploy "Ember Wizard" (EMBER)
→ Migrate exact liquidity to new pool
→ Lock new pool until next death

STEP 5: CLAIM
FLAME holders call claimTokens(generation=1)
→ Receive EMBER based on snapshot

STEP 6: REPEAT
EMBER dies → "Ash Conjurer" born
→ Forever cycling through generations
```

## Metadata Sequence

| Gen | Name | Symbol | Theme |
|-----|------|--------|-------|
| 1 | Flame Fren | FLAME | 🔥 |
| 2 | Ember Wizard | EMBER | ✨ |
| 3 | Ash Conjurer | ASH | 🌪️ |
| 4 | Inferno Sage | INFERNO | 🌋 |
| 5 | Cinder Mage | CINDER | 💫 |
| 6 | Blaze Sorcerer | BLAZE | ⚡ |
| 7+ | Cycles back... | | |

## Constants

```typescript
MAX_NFT_SUPPLY = 777
PHOENIX_DEATH_THRESHOLD_SATS = 1,000,000 (0.01 BTC)
PHOENIX_INITIAL_TOKENS = 777e18
PHOENIX_INITIAL_BTC_SATS = 100,000,000 (1 BTC)
BLOCKS_PER_24H = 144 (at 10 min/block)
```

## Deployment Order

1. Deploy VolumeOracle
2. Deploy PhoenixVault
3. Deploy PhoenixRegistry
4. Deploy MiFRENNFT (with Phoenix registry address)
5. Mint 777 NFTs → auto-summons Phoenix gen 1

## TODO / Missing Features

- [ ] MotoSwap pool creation integration
- [ ] Liquidity add/remove via router
- [ ] Cross-contract calls (NFT → Registry)
- [ ] Holder snapshot mechanism
- [ ] Claim minting on new generation
- [ ] Volume tracking from MotoSwap events
- [ ] Emergency pause mechanism
- [ ] Frontend components

## Security Considerations

1. **Reentrancy** - All liquidity operations need guards
2. **Oracle manipulation** - Use time-weighted volume
3. **Claim replay** - Single claim per generation per address
4. **Migration atomicity** - Remove old + add new in one tx
5. **Death threshold** - Configurable by deployer

## Testing Plan

- [ ] NFT mint triggers summoning at 777
- [ ] Genesis Phoenix deploys correctly
- [ ] Volume oracle tracks trades
- [ ] Death detection works
- [ ] Rebirth deploys new token
- [ ] Liquidity migrates exactly
- [ ] Holders can claim once per generation
- [ ] Metadata cycles correctly
- [ ] 0% tax verified on transfers

## Questions for User

1. Initial liquidity amounts? (Currently 777 tokens + 1 BTC)
2. Death threshold? (Currently 0.01 BTC/24h)
3. Who pays for rebirth gas?
4. Can deployer pause/unpause?
5. Max generations before stopping?
