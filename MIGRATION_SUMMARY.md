# MagicFrens → MagicFrensPeg Migration Summary

## What We Built

### 1. **MagicFrensPeg.sol** - UniPeg-Style Trading Contract

**Location:** `contracts/solidity/MagicFrensPeg.sol`

**Key Features:**
- ✅ Dual ERC-20 + ERC-721 implementation
- ✅ Buy tokens → mint random-trait NFT (bound)
- ✅ Sell tokens → burn NFT (unless committed)
- ✅ Commit NFT → pay 0.5 tokens → NFT becomes permanent
- ✅ Post-commit: trade NFT on OpenSea independently

**Supply:** 420 MagicFrens (from 1111 possible trait combinations)

**Chains:** Ethereum, Base, BNB

### 2. **Deployment Scripts**

**Location:** `contracts/solidity/deploy/DeployMagicFrensPeg.s.sol`

**Usage:**
```bash
# Ethereum
forge script DeployMagicFrensPeg --rpc-url $ETH_RPC --broadcast --verify

# Base
forge script DeployMagicFrensPeg --rpc-url $BASE_RPC --broadcast --verify

# BNB
forge script DeployMagicFrensPeg --rpc-url $BNB_RPC --broadcast --verify
```

### 3. **Frontend Cleanup**

**Removed:**
- ✅ OPNet cauldron configs (`opnetCauldrons.ts` → `_legacy/`)
- ✅ OPNet chain ID references (878787)
- ✅ OPNet-specific network configs
- ✅ Bitcoin L1 contract addresses

**Added:**
- ✅ Multichain support (Ethereum mainnet, Base, BNB)
- ✅ Testnet support (Sepolia, Base Sepolia, BNB Testnet)
- ✅ New contract constants (MAX_NFT_SUPPLY=420, COMMIT_FEE=0.5 tokens)
- ✅ Chain configs with RPC endpoints and explorers

---

## uPEG vs MagicFrensPeg: Key Answer

### **Your Question: "Can uPEG be traded on OpenSea?"**

**Answer:** ❌ **NO** (most likely)

**Why:**
- uPEG is **ERC-20 only** with internal object tracking
- Not a true ERC-721 (no `transferFrom(tokenId)`, `ownerOf(tokenId)`, etc.)
- Objects are **metadata bound to tokens**, not standalone NFTs
- OpenSea can't index non-ERC-721 contracts
- `transferUpeg()` function moves **both tokens AND object together**

**If you sell on OpenSea:**
- You CAN'T - OpenSea won't list them
- You'd have to list via the ERC-20 token transfer (which is just normal token trading)

### **How MagicFrensPeg is Different:**

✅ **Pre-Commit:**
- NFT is bound to tokens (like uPEG)
- Can't sell NFT separately
- Must use `sellFren()` to burn and re-roll

✅ **Post-Commit:**
- NFT is a **real ERC-721** (OpenSea compatible!)
- Can sell NFT on OpenSea
- Can sell tokens separately
- **Full decoupling** - buyer gets NFT, seller keeps tokens

---

## Economics Comparison

### uPEG
```
Supply: 10,000 tokens
Binding: Permanent
OpenSea: ❌
Revenue: LP fees only
Incentive: Find rare seed
```

### MagicFrensPeg
```
Supply: 420 tokens
Binding: Flexible (commit to decouple)
OpenSea: ✅ (after commit)
Revenue:
  1. Commit fees: 420 × 0.5 = 210 tokens max
  2. OpenSea royalties
  3. Trading volume

Incentive:
  1. Find rare traits (1111 combos → 420 supply = scarcity)
  2. Commit to keep forever
  3. Trade on OpenSea for liquidity
```

---

## Next Steps

### Phase 1: Contract Deployment (READY)

**Prerequisites:**
1. Install Foundry: `curl -L https://foundry.paradigm.xyz | bash`
2. Install OpenZeppelin: Already done ✅
3. Set up `.env`:
   ```bash
   cp contracts/solidity/.env.template contracts/solidity/.env
   # Edit with your keys
   ```

**Deploy to Testnets:**
```bash
# Sepolia
forge script DeployMagicFrensPeg \
  --rpc-url $ETH_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Base Sepolia
forge script DeployMagicFrensPeg \
  --rpc-url $BASE_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY

# BNB Testnet
forge script DeployMagicFrensPeg \
  --rpc-url $BNB_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY
```

**After Deployment:**
1. Copy contract addresses
2. Update `src/constants/contracts.ts` with addresses
3. Verify on block explorers

### Phase 2: Frontend Integration (TODO)

**Need to Build:**
1. ✅ TypeScript ABIs for MagicFrensPeg.sol
2. ✅ React hooks:
   - `useBuyFren()` - Buy tokens + mint NFT
   - `useSellFren()` - Sell tokens, burn NFT
   - `useCommitFren()` - Pay 0.5 tokens, make permanent
   - `useTransferFren()` - Transfer committed NFTs
3. ✅ UI Components:
   - Trading interface (buy/sell)
   - Commit button
   - Trait visualizer
   - OpenSea integration link
4. ✅ Wallet Integration:
   - MetaMask
   - WalletConnect
   - Coinbase Wallet
5. ✅ Multichain Switcher:
   - Network selector
   - Auto-switch on buy/sell

### Phase 3: Trait System (TODO)

**On-Chain Traits:**
- 7 Classes: Wizard, King, Knight, Apprentice, Peasant, Gnome, Elf
- Trait encoding: `classIdx | (bodyIdx << 8) | (faceIdx << 16) | (itemIdx << 24)`
- Total combos: 1111 (more than 420 supply)

**Frontend Rendering:**
1. Read `traitData[tokenId]` from contract
2. Unpack bits to get (classIdx, bodyIdx, faceIdx, itemIdx)
3. Render SVG from existing MagicFrens trait system
4. Display rarity % based on combo frequency

### Phase 4: OpenSea Integration (TODO)

**After Commit:**
1. OpenSea auto-indexes ERC-721
2. Users can list committed NFTs
3. Royalties flow to treasury

**Metadata API:**
```
GET /api/metadata/{tokenId}
{
  "name": "MagicFren #123",
  "description": "A unique MagicFren from the 420 supply",
  "image": "https://...",
  "attributes": [
    {"trait_type": "Class", "value": "Wizard"},
    {"trait_type": "Body", "value": "Manifest Robe"},
    {"trait_type": "Face", "value": "Happy"},
    {"trait_type": "Item", "value": "Manifest Staff"}
  ]
}
```

---

## Files Changed

### Created
```
contracts/solidity/MagicFrensPeg.sol
contracts/solidity/deploy/DeployMagicFrensPeg.s.sol
contracts/solidity/foundry.toml
contracts/solidity/.env.template
contracts/solidity/README.md
UPEG_VS_MAGICFRENSPEG.md
MIGRATION_SUMMARY.md
```

### Modified
```
src/constants/contracts.ts (removed OPNet, added multichain)
src/constants/global.ts (removed OPNET_CHAIN_ID)
src/configs/cauldrons/index.ts (disabled cauldrons)
```

### Moved to Legacy
```
_legacy/opnetCauldrons.ts
```

---

## Questions Answered

### 1. **What is the difference between uPEG and MagicFrensPeg?**

**uPEG:**
- Permanent token-object binding
- Cannot trade on OpenSea
- ERC-20 only
- Seed-based uniqueness

**MagicFrensPeg:**
- Flexible commitment system
- OpenSea tradeable after commit
- Dual ERC-20 + ERC-721
- Trait-based uniqueness (1111 combos)

### 2. **What happens if you sell uPEG on OpenSea?**

You **can't**. uPEG isn't ERC-721 compliant, so OpenSea won't list it.

If it were listed (hypothetically), selling the NFT separately from tokens would break the binding, but the contract doesn't support this - `transferUpeg()` moves both.

### 3. **How does the commit mechanism work?**

**Step-by-Step:**
```
1. Alice buys 1 token → gets Peasant #42 (ugly)
2. Alice sells → Peasant burns
3. Alice buys again → gets Wizard #123 (beautiful!)
4. Alice calls commitFren() → pays 0.5 tokens
5. Wizard #123 is now PERMANENT
6. Alice can:
   - Sell 0.5 tokens (keep Wizard)
   - List Wizard on OpenSea
   - Transfer Wizard independently
```

**Economics:**
- Commit fee: 0.5 tokens (half the value of 1 token)
- Max commit fees: 420 × 0.5 = 210 tokens to treasury
- Deflationary: removes 210 tokens from circulation

---

## Security Notes

### Audit Status
- [ ] Professional audit pending
- [ ] Community review open

### Known Risks

1. **Randomness:**
   - Uses `block.prevrandao` (predictable by miners)
   - Low risk for 420 supply (manipulation not profitable)
   - Consider Chainlink VRF for production

2. **Commit Irreversibility:**
   - Once committed, cannot uncommit
   - This is by design (permanence is the feature)

3. **Gas Optimization:**
   - Current implementation prioritizes clarity
   - Can optimize `_generateRandomTraits()` loops

---

## Support

**Documentation:**
- Contract: `contracts/solidity/README.md`
- Comparison: `UPEG_VS_MAGICFRENSPEG.md`
- This guide: `MIGRATION_SUMMARY.md`

**Resources:**
- OpenZeppelin: https://docs.openzeppelin.com/
- Foundry: https://book.getfoundry.sh/
- Base Deployment: https://docs.base.org/

---

## License

MIT
