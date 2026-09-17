/**
 * RARITY TIERS — one table, because two disagreed.
 *
 * `CauldronCollection.sol:99-101` is the authority:
 *     // Rarity tiers: 0=Common, 1=Rare, 2=Epic, 3=Ultra.
 *     uint16[4] public rarityCumBps = [uint16(7900), 9400, 9900, 10000];
 *
 * `ForgedCreatures.tsx` shipped `["Common","Uncommon","Rare","Epic","Legendary"]`,
 * which is off by one for every non-Common tier — an Ultra rendered as "Epic" —
 * while `CreatureModal.tsx` had the correct table. The SAME NFT got two different
 * rarity names in two places in the same app, which misprices a secondary sale
 * (audit A-02). Both now import from here.
 *
 * Index 4 ("Legendary") is not a tier the contract can emit — `rarityCumBps` has
 * four entries — but it is kept so an out-of-range value from a future contract
 * renders as something rather than `undefined`.
 */
export const RARITY_NAMES = ["Common", "Rare", "Epic", "Ultra", "Legendary"] as const;

/** Tier colours, aligned index-for-index with {RARITY_NAMES}. */
export const RARITY_COLORS = ["#8f83b8", "#5ac8fa", "#c07cff", "#f5c542", "#d5fd51"] as const;

/** Safe label for a tier that may be out of range. */
export function rarityName(tier: number | undefined | null): string {
  return RARITY_NAMES[Number(tier ?? 0)] ?? RARITY_NAMES[0];
}

/** Safe colour for a tier that may be out of range. */
export function rarityColor(tier: number | undefined | null): string {
  return RARITY_COLORS[Number(tier ?? 0)] ?? RARITY_COLORS[0];
}
