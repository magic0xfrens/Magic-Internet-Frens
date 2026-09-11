# Phoenix Token - NFT Holder Tax System

## Overview

The Phoenix token has a **tiered tax system** based on MiFREN NFT ownership:

- **NFT Holders (777 Frens)**: **0% tax** ✨
- **Non-Holders**: **3% tax** → Magic Internet Wallet

## How It Works

### On Every Transfer

```typescript
transfer(to, amount) {
  if (sender holds >= 1 MiFREN NFT) {
    // Full amount transferred
    to.balance += amount
  } else {
    // 3% tax deducted
    tax = amount * 3 / 100
    to.balance += (amount - tax)
    magicWallet.balance += tax
  }
}
```

### NFT Check

The contract calls `MiFRENNFT.balanceOf(sender)`:
- `balance > 0` → NFT holder → 0% tax
- `balance == 0` → Non-holder → 3% tax

This check happens **on every transfer**, so:
- Mint an NFT → immediately get 0% tax
- Sell your last NFT → immediately start paying 3% tax

## Examples

### Example 1: NFT Holder Trading
```
Alice holds 1 MiFREN NFT
Alice transfers 100 FLAME to Bob

Result:
- Alice: -100 FLAME
- Bob: +100 FLAME (0% tax)
- Magic Wallet: +0 FLAME
```

### Example 2: Non-Holder Trading
```
Charlie holds 0 MiFREN NFTs
Charlie transfers 100 FLAME to Diana

Result:
- Charlie: -100 FLAME
- Diana: +97 FLAME (3% tax applied)
- Magic Wallet: +3 FLAME
```

### Example 3: Buying an NFT Mid-Trade
```
Eve transfers 100 FLAME (pays 3% tax)
Eve mints MiFREN NFT
Eve transfers 100 FLAME (pays 0% tax)
```

## Implementation Details

### Contract Storage
```typescript
_nftContract: Address        // MiFREN NFT contract
_feeRecipient: Address       // Magic Internet wallet
_taxRate: u256              // 300 BPS (3%)
```

### Deployment Parameters
```typescript
deployPhoenix({
  generation: 1,
  name: "Flame Fren",
  symbol: "FLAME",
  nftContract: "0x...",      // MiFREN NFT address
  feeRecipient: "0x...",     // Magic Internet wallet
})
```

### Tax Calculation
```typescript
// 3% in basis points
taxAmount = (amount * 300) / 10000

// Amount received by recipient
afterTax = amount - taxAmount
```

## Magic Internet Wallet

All non-holder taxes go to a designated **Magic Internet Wallet**.

This wallet address is set on deployment and can be:
- Protocol treasury
- DAO multisig
- Reward distribution contract
- Or any other Bitcoin address

## Benefits

### For NFT Holders (777 Frens)
✅ **0% tax** on all trades
✅ Incentive to hold NFTs
✅ Better trading experience
✅ Exclusive perk for community

### For Protocol
✅ Revenue from non-holder trades
✅ Incentivizes NFT mints
✅ Sustainable funding model
✅ Rewards early supporters

### For Non-Holders
✅ Still can trade Phoenix
✅ Only 3% tax (reasonable)
✅ Can mint NFT anytime to remove tax

## Tax Exemptions

The following scenarios are **NOT taxed** (even for non-holders):
- ❌ Initial liquidity addition (during summon)
- ❌ Liquidity migration (during rebirth)
- ❌ Claims from previous generations
- ❌ Minting new tokens (registry-only)

All standard **user-to-user transfers** are taxed based on NFT holdings.

## Gas Costs

The NFT holder check adds minimal gas:
- One cross-contract call: `balanceOf(address)`
- Returns u256 balance
- Very cheap on OPNet

## Security Considerations

1. **NFT Contract Trust**: Must trust NFT contract's `balanceOf()` implementation
2. **Front-running**: Users could buy NFT, trade, sell NFT in same block
3. **Borrowed NFTs**: Users could temporarily hold NFT just for trade (acceptable)
4. **Multiple NFTs**: Holding > 1 NFT doesn't give extra benefits (still 0% tax)

## FAQ

### Q: If I hold 5 NFTs, do I get -5% tax (earn 5%)?
**A**: No. 1+ NFT = 0% tax. Holding multiple doesn't give negative tax.

### Q: Can I trade on behalf of someone who has an NFT?
**A**: No. Tax is checked on `from` address in `transferFrom()`. The spender's NFT holdings don't matter.

### Q: What if NFT contract is not set?
**A**: Everyone pays 3% tax until NFT contract address is configured.

### Q: Can tax rate be changed?
**A**: No. Tax rate is set on deployment and immutable (3% fixed).

### Q: What if I transfer to myself?
**A**: Still checked. If you don't hold NFT, you pay 3% tax to Magic Wallet.

## Code References

- **Tax Logic**: `PhoenixToken.ts:_transferWithTax()`
- **NFT Check**: `PhoenixToken.ts:_checkNFTHolder()`
- **Tax Constant**: `constants.ts:PHOENIX_TAX_RATE_BPS`

---

**Summary**: Hold a MiFREN NFT → Trade Phoenix for free 🔥
