/**
 * Rarity Tier System for MagicFrens
 *
 * PRESALE TIER (Legendary):
 * - Guaranteed rare/legendary classes
 * - High probability of Wizard, King, Knight
 * - Special classes (Gnome, Elf) included
 * - NO Peasant or Apprentice
 *
 * PUBLIC TIER (Common):
 * - Majority Peasant and Apprentice (plebs)
 * - Very low chance of rare classes
 * - Makes presale NFTs highly valuable
 */

export enum MintTier {
  PRESALE = 'presale',
  PUBLIC = 'public',
}

export type FrenClass =
  | 'Wizard'
  | 'King'
  | 'Knight'
  | 'Gnome'
  | 'Elf'
  | 'Apprentice'
  | 'Peasant';

/**
 * Weighted probability pools for each tier
 * Numbers represent relative weights (not percentages)
 */
export const TIER_WEIGHTS: Record<MintTier, Record<FrenClass, number>> = {
  // PRESALE: Only rare/legendary classes
  [MintTier.PRESALE]: {
    Wizard: 35,      // 35% - Most prestigious
    King: 25,        // 25% - Royal
    Knight: 20,      // 20% - Elite
    Gnome: 10,       // 10% - Rare special
    Elf: 10,         // 10% - Rare special
    Apprentice: 0,   // FORBIDDEN in presale
    Peasant: 0,      // FORBIDDEN in presale
  },

  // PUBLIC: Mostly plebs, rare chance of good ones
  [MintTier.PUBLIC]: {
    Wizard: 2,       // 2% - Ultra rare
    King: 3,         // 3% - Very rare
    Knight: 5,       // 5% - Rare
    Gnome: 8,        // 8% - Uncommon
    Elf: 8,          // 8% - Uncommon
    Apprentice: 35,  // 35% - Common pleb
    Peasant: 39,     // 39% - Most common pleb
  },
};

/**
 * Convert weights to cumulative ranges for random selection
 */
export function getClassRanges(tier: MintTier): { class: FrenClass; range: [number, number] }[] {
  const weights = TIER_WEIGHTS[tier];
  const classes = Object.keys(weights) as FrenClass[];

  let cumulative = 0;
  const ranges: { class: FrenClass; range: [number, number] }[] = [];

  for (const cls of classes) {
    const weight = weights[cls];
    if (weight > 0) {
      ranges.push({
        class: cls,
        range: [cumulative, cumulative + weight],
      });
      cumulative += weight;
    }
  }

  return ranges;
}

/**
 * Select a random class based on tier weights
 */
export function selectRandomClass(tier: MintTier, randomValue: bigint): FrenClass {
  const ranges = getClassRanges(tier);
  const totalWeight = ranges[ranges.length - 1].range[1];

  // Convert bigint to number in range [0, totalWeight)
  const roll = Number(randomValue % BigInt(totalWeight));

  for (const { class: cls, range } of ranges) {
    if (roll >= range[0] && roll < range[1]) {
      return cls;
    }
  }

  // Fallback (should never happen)
  return tier === MintTier.PRESALE ? 'Wizard' : 'Peasant';
}

/**
 * Get display info for tier
 */
export function getTierInfo(tier: MintTier): {
  name: string;
  description: string;
  emoji: string;
} {
  return tier === MintTier.PRESALE
    ? {
        name: 'Legendary Presale',
        description: 'Guaranteed rare classes: Wizard, King, Knight, Gnome, or Elf',
        emoji: '👑',
      }
    : {
        name: 'Public Mint',
        description: 'Mostly Peasants and Apprentices. Rare chance of legendary classes.',
        emoji: '🌾',
      };
}

/**
 * Validate if an address is eligible for presale tier
 * (To be implemented with presale contract integration)
 */
export function isPresaleBuyer(_address: string): boolean {
  // TODO: Check presale contract for token balance
  // For now, return false (all public tier)
  return false;
}
