# 🎯 Rarity Tier System Implementation Guide

## Overview
The MagicFrens presale buyers get **LEGENDARY TIER** mints (rare classes only), while public minters get **COMMON TIER** (mostly plebs). This creates massive value for presale participants.

---

## 📊 Tier Breakdown

### 👑 LEGENDARY TIER (Presale Buyers Only)

**Distribution:**
- Wizard: 35% (most prestigious)
- King: 25% (royal)
- Knight: 20% (elite)
- Gnome: 10% (rare special)
- Elf: 10% (rare special)
- **Peasant: 0%** ❌ FORBIDDEN
- **Apprentice: 0%** ❌ FORBIDDEN

**Benefits:**
- Guaranteed rare class
- NO common "pleb" traits
- Higher resale value
- Exclusive early supporter reward

### 🌾 COMMON TIER (Public Mints)

**Distribution:**
- Peasant: 39% (most common pleb)
- Apprentice: 35% (common pleb)
- Gnome: 8% (uncommon)
- Elf: 8% (uncommon)
- Knight: 5% (rare)
- King: 3% (very rare)
- Wizard: 2% (ultra rare!)

**Reality:**
- 74% chance of getting a pleb (Peasant/Apprentice)
- Only 2% chance of Wizard (vs 35% for presale!)
- Makes presale NFTs 17.5x more likely to be Wizards

---

## 🛠️ Implementation Steps

### 1. Presale Token Contract (ERC-20)

Create `PresaleMFPEG.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PresaleMFPEG
 * @notice ERC-20 token representing presale allocation
 * @dev Each token = 1 guaranteed legendary-tier NFT mint
 */
contract PresaleMFPEG is ERC20, Ownable {
    uint256 public constant MAX_PRESALE_SUPPLY = 333; // 30% of 1111 total supply
    uint256 public constant PRICE_PER_TOKEN = 0.01 ether;

    address public nftContract;
    mapping(address => bool) public hasUsedPresaleToken;

    event PresalePurchase(address indexed buyer, uint256 amount, uint256 totalPaid);
    event PresaleTokenUsed(address indexed user, uint256 tokenId);

    constructor() ERC20("MagicFren Presale", "MFPEG") Ownable(msg.sender) {}

    /**
     * @notice Buy presale tokens with ETH/BNB
     */
    function buyPresale(uint256 amount) external payable {
        require(totalSupply() + amount <= MAX_PRESALE_SUPPLY, "Presale sold out");
        require(msg.value >= amount * PRICE_PER_TOKEN, "Insufficient payment");

        _mint(msg.sender, amount);
        emit PresalePurchase(msg.sender, amount, msg.value);
    }

    /**
     * @notice Set the NFT contract address (one-time)
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        require(nftContract == address(0), "Already set");
        nftContract = _nftContract;
    }

    /**
     * @notice Mark presale token as used (called by NFT contract)
     */
    function usePresaleToken(address user) external {
        require(msg.sender == nftContract, "Only NFT contract");
        require(balanceOf(user) > 0, "No presale tokens");

        _burn(user, 1);
    }

    /**
     * @notice Check if address has presale allocation
     */
    function isPresaleBuyer(address user) external view returns (bool) {
        return balanceOf(user) > 0;
    }

    /**
     * @notice Withdraw collected funds
     */
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
```

### 2. NFT Contract with Tier System

Update `MagicFrensNFT.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./PresaleMFPEG.sol";

contract MagicFrensNFT is ERC721 {
    PresaleMFPEG public presaleToken;

    enum FrenClass { Wizard, King, Knight, Gnome, Elf, Apprentice, Peasant }

    struct Fren {
        FrenClass class;
        uint8 bodyIndex;
        uint8 faceIndex;
        uint8 itemIndex;
        bool isPresaleMint;
    }

    mapping(uint256 => Fren) public frens;
    uint256 public nextTokenId = 1;

    // Legendary tier weights (presale only)
    uint8[7] private LEGENDARY_WEIGHTS = [35, 25, 20, 10, 10, 0, 0];

    // Common tier weights (public)
    uint8[7] private COMMON_WEIGHTS = [2, 3, 5, 8, 8, 35, 39];

    constructor(address _presaleToken) ERC721("MagicFrens", "MFREN") {
        presaleToken = PresaleMFPEG(_presaleToken);
    }

    /**
     * @notice Mint with tier-based rarity
     */
    function mint() external payable {
        bool isPresale = presaleToken.balanceOf(msg.sender) > 0;

        if (isPresale) {
            // Burn presale token
            presaleToken.usePresaleToken(msg.sender);
        } else {
            // Public mint - require payment
            require(msg.value >= 0.02 ether, "Insufficient payment");
        }

        uint256 tokenId = nextTokenId++;
        _safeMint(msg.sender, tokenId);

        // Generate traits based on tier
        Fren memory newFren = _generateFren(tokenId, isPresale);
        frens[tokenId] = newFren;
    }

    /**
     * @dev Generate fren traits based on tier
     */
    function _generateFren(uint256 tokenId, bool isPresale) private view returns (Fren memory) {
        // Pseudo-random seed from block data + tokenId
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            tokenId,
            msg.sender
        )));

        FrenClass class = _selectClass(seed, isPresale);

        return Fren({
            class: class,
            bodyIndex: uint8(seed % 6),        // 0-5 body variants per class
            faceIndex: uint8((seed >> 8) % 8), // 0-7 face variants
            itemIndex: uint8((seed >> 16) % 4), // 0-3 item variants
            isPresaleMint: isPresale
        });
    }

    /**
     * @dev Select class based on weighted probabilities
     */
    function _selectClass(uint256 seed, bool isPresale) private view returns (FrenClass) {
        uint8[7] memory weights = isPresale ? LEGENDARY_WEIGHTS : COMMON_WEIGHTS;
        uint8 totalWeight = 0;

        for (uint8 i = 0; i < 7; i++) {
            totalWeight += weights[i];
        }

        uint8 roll = uint8(seed % totalWeight);
        uint8 cumulative = 0;

        for (uint8 i = 0; i < 7; i++) {
            cumulative += weights[i];
            if (roll < cumulative) {
                return FrenClass(i);
            }
        }

        // Fallback (should never reach)
        return isPresale ? FrenClass.Wizard : FrenClass.Peasant;
    }

    /**
     * @notice Get human-readable class name
     */
    function getClassName(uint256 tokenId) external view returns (string memory) {
        FrenClass class = frens[tokenId].class;

        if (class == FrenClass.Wizard) return "Wizard";
        if (class == FrenClass.King) return "King";
        if (class == FrenClass.Knight) return "Knight";
        if (class == FrenClass.Gnome) return "Gnome";
        if (class == FrenClass.Elf) return "Elf";
        if (class == FrenClass.Apprentice) return "Apprentice";
        return "Peasant";
    }
}
```

### 3. Frontend Integration

Update `usePresale.ts`:

```typescript
export function usePresale() {
  const { provider, walletAddress } = useWallet();
  const [isPresaleBuyer, setIsPresaleBuyer] = useState(false);

  useEffect(() => {
    const checkPresaleStatus = async () => {
      if (!walletAddress) return;

      const presaleContract = new ethers.Contract(
        PRESALE_TOKEN_ADDRESS,
        PRESALE_ABI,
        provider
      );

      const balance = await presaleContract.balanceOf(walletAddress);
      setIsPresaleBuyer(balance > 0);
    };

    checkPresaleStatus();
  }, [walletAddress]);

  return { isPresaleBuyer };
}
```

Update `useMintNFT.ts`:

```typescript
const mint = async () => {
  const { isPresaleBuyer } = usePresale();

  const tier = isPresaleBuyer ? 'LEGENDARY' : 'COMMON';
  console.log(`Minting with ${tier} tier...`);

  // Presale mints are free (already paid via presale token)
  const value = isPresaleBuyer ? '0' : ethers.parseEther('0.02');

  const tx = await nftContract.mint({ value });
  await tx.wait();
};
```

---

## 📈 Economic Impact

### Presale Advantage:

| Class | Presale Chance | Public Chance | Presale Multiplier |
|-------|---------------|---------------|-------------------|
| Wizard | 35% | 2% | **17.5x** |
| King | 25% | 3% | **8.3x** |
| Knight | 20% | 5% | **4x** |
| Gnome | 10% | 8% | 1.25x |
| Elf | 10% | 8% | 1.25x |
| Apprentice | 0% | 35% | N/A (forbidden) |
| Peasant | 0% | 39% | N/A (forbidden) |

**Key Insight:** Presale buyers are **17.5x more likely** to mint a Wizard than public minters!

---

## 🎨 UI/UX Updates

### Presale Modal Changes:
- ✅ Added "Legendary Tier Benefits" section
- ✅ Explains guaranteed rare classes
- ✅ Highlights that presale buyers never get plebs
- ✅ Shows public mint disadvantage (74% pleb chance)

### Mint Page Changes:
```tsx
{isPresaleBuyer ? (
  <div className="tier-badge legendary">
    <span className="tier-icon">👑</span>
    <span className="tier-text">LEGENDARY TIER</span>
    <p className="tier-desc">Guaranteed: Wizard, King, Knight, Gnome, or Elf</p>
  </div>
) : (
  <div className="tier-badge common">
    <span className="tier-icon">🌾</span>
    <span className="tier-text">COMMON TIER</span>
    <p className="tier-desc">74% Peasant/Apprentice · 2% Wizard</p>
  </div>
)}
```

---

## 🚀 Deployment Steps

1. **Deploy Presale Token Contract**
   ```bash
   npx hardhat run scripts/deployPresale.ts --network sepolia
   ```

2. **Deploy NFT Contract** (with presale token address)
   ```bash
   npx hardhat run scripts/deployNFT.ts --network sepolia
   ```

3. **Set NFT Contract Address** in presale token
   ```bash
   npx hardhat run scripts/linkContracts.ts --network sepolia
   ```

4. **Update Frontend Constants**
   ```typescript
   export const PRESALE_TOKEN_ADDRESS = '0x...';
   export const NFT_CONTRACT_ADDRESS = '0x...';
   ```

5. **Test Presale Flow**
   - Buy presale token
   - Mint NFT (should burn presale token)
   - Verify legendary tier class

6. **Deploy to Mainnet** (Ethereum, Base, BNB)

---

## ✅ Testing Checklist

- [ ] Presale token purchase works
- [ ] Presale token balance updates correctly
- [ ] Minting burns presale token
- [ ] Presale mints ONLY get legendary classes
- [ ] Public mints get weighted common distribution
- [ ] No Peasants/Apprentices in presale mints
- [ ] Wizard is 35% presale, 2% public
- [ ] Frontend shows correct tier badge
- [ ] Metadata reflects isPresaleMint flag

---

## 💡 Marketing Points

**For Presale Buyers:**
- "Join presale for guaranteed rare classes"
- "Never mint a Peasant - presale exclusive"
- "17.5x more likely to get a Wizard"
- "Public minters get 74% plebs"
- "Early supporters get the best traits"

**For Public Minters:**
- "Try your luck - 2% Wizard chance!"
- "Presale buyers already locked in the rares"
- "Most mints will be Peasants/Apprentices"
- "Trade up to legendary classes on marketplace"

---

## 📝 Notes

- Presale allocation: 333 tokens (30% of 1111 supply)
- Public allocation: 778 NFTs (70% of supply)
- Price: 0.01 ETH presale, 0.02 ETH public
- Presale funds provide initial liquidity
- Contract addresses need to be updated after deployment

---

**Status:** ✅ Tier system designed, ready for contract implementation
**Next Steps:** Deploy presale contract, test on testnet, integrate frontend
