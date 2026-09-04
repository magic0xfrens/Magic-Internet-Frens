/* ------------------------------------------------------------------ */
/*  Fren trait catalogue & combination generator                       */
/* ------------------------------------------------------------------ */

/** Character class (rarity tier). */
export type FrenClass =
  | "Wizard"
  | "King"
  | "Knight"
  | "Gnome"
  | "Elf"
  | "Apprentice"
  | "Peasant";

/** A single SVG layer file reference. */
export interface TraitLayer {
  /** File name inside /frens/ */
  file: string;
  /** Human label */
  label: string;
}

/** A fully-composed fren. */
export interface Fren {
  /** Unique sequential ID (1-based). */
  id: number;
  /** Class tier. */
  class: FrenClass;
  /** Body layer. */
  body: TraitLayer;
  /** Face layer. */
  face: TraitLayer;
  /** Item layer. */
  item: TraitLayer;
}

/* ------------------------------------------------------------------ */
/*  Trait definitions                                                   */
/* ------------------------------------------------------------------ */

export const BODIES: Record<FrenClass, TraitLayer[]> = {
  Wizard: [
    { file: "wizard-01.svg", label: "Wizard I" },
    { file: "wizard-02.svg", label: "Wizard II" },
    { file: "wizard-03.svg", label: "Wizard III" },
    { file: "wizard-04.svg", label: "Wizard IV" },
    { file: "wizard-05.svg", label: "Wizard V" },
    { file: "wizard-06.svg", label: "Wizard VI" },
    { file: "wizard-manifest.svg", label: "Wizard Manifest" },
    { file: "wizard-btc-01.svg", label: "Wizard BTC" },
  ],
  King: [
    { file: "king-cloth-black.svg", label: "King Black" },
    { file: "king-cloth-blue.svg", label: "King Blue" },
    { file: "king-cloth-orange.svg", label: "King Orange" },
    { file: "king-cloth-red.svg", label: "King Red" },
    { file: "king-cloth-white.svg", label: "King White" },
  ],
  Knight: [
    { file: "knight-bronze.svg", label: "Knight Bronze" },
    { file: "knight-gold.svg", label: "Knight Gold" },
    { file: "knight-orange.svg", label: "Knight Orange" },
    { file: "knight-silver.svg", label: "Knight Silver" },
  ],
  Gnome: [
    { file: "gnome-01.svg", label: "Gnome I" },
    { file: "gnome-02.svg", label: "Gnome Orange" },
  ],
  Elf: [
    { file: "elf-03.svg", label: "Elf Green" },
    { file: "elf-02.svg", label: "Elf Purple" },
    { file: "elf-04.svg", label: "Elf Orange" },
  ],
  Apprentice: [
    { file: "apprentice-01.svg", label: "Apprentice I" },
    { file: "apprentice-02.svg", label: "Apprentice II" },
    { file: "apprentice-02-orange.svg", label: "Apprentice Orange" },
  ],
  Peasant: [
    { file: "peasant-01.svg", label: "Peasant I" },
    { file: "peasant-02.svg", label: "Peasant II" },
    { file: "peasant-robinhood.svg", label: "Robin Hood" },
  ],
};

export const FACES: TraitLayer[] = [
  { file: "face-01.svg", label: "Classic" },
  { file: "face-02.svg", label: "Happy" },
  { file: "face-03.svg", label: "Angry" },
  { file: "face-04.svg", label: "Feels Bad" },
  { file: "face-05.svg", label: "Grinding" },
  { file: "face-06.svg", label: "Chill" },
  { file: "face-07.svg", label: "Grumpy" },
  { file: "face-08.svg", label: "Giga Happy" },
  { file: "face-09.svg", label: "Cooked" },
  { file: "face-10.svg", label: "Comfy" },
  { file: "face-11.svg", label: "Retard" },
  { file: "face-laser.svg", label: "Laser Eyes" },
];

/** Gnome-specific faces (cream skin variant). */
export const GNOME_FACES: TraitLayer[] = [
  { file: "gnome-face-01.svg", label: "Gnome Classic" },
  { file: "gnome-face-02.svg", label: "Gnome Happy" },
  { file: "gnome-face-03.svg", label: "Gnome Angry" },
  { file: "gnome-face-04.svg", label: "Gnome Feels Bad" },
  { file: "gnome-face-05.svg", label: "Gnome Grinding" },
  { file: "gnome-face-06.svg", label: "Gnome Chill" },
  { file: "gnome-face-07.svg", label: "Gnome Grumpy" },
  { file: "gnome-face-08.svg", label: "Gnome Giga Happy" },
  { file: "gnome-face-09.svg", label: "Gnome Cooked" },
  { file: "gnome-face-10.svg", label: "Gnome Comfy" },
  { file: "gnome-face-11.svg", label: "Gnome Retard" },
  { file: "gnome-face-laser.svg", label: "Gnome Laser Eyes" },
];

/** Elf-specific faces (beige skin variant). */
export const ELF_FACES: TraitLayer[] = [
  { file: "elf-face-01.svg", label: "Elf Classic" },
  { file: "elf-face-02.svg", label: "Elf Happy" },
  { file: "elf-face-03.svg", label: "Elf Angry" },
  { file: "elf-face-04.svg", label: "Elf Feels Bad" },
  { file: "elf-face-05.svg", label: "Elf Grinding" },
  { file: "elf-face-06.svg", label: "Elf Chill" },
  { file: "elf-face-07.svg", label: "Elf Grumpy" },
  { file: "elf-face-08.svg", label: "Elf Giga Happy" },
  { file: "elf-face-09.svg", label: "Elf Cooked" },
  { file: "elf-face-10.svg", label: "Elf Comfy" },
  { file: "elf-face-11.svg", label: "Elf Retard" },
  { file: "elf-face-laser.svg", label: "Elf Laser Eyes" },
];

export const ITEMS: Record<FrenClass, TraitLayer[]> = {
  Wizard: [
    { file: "wiz-item-01.svg", label: "Wand" },
    { file: "wiz-item-02.svg", label: "Staff" },
    { file: "wiz-item-03.svg", label: "Orb" },
    { file: "wiz-item-04.svg", label: "Tome" },
    { file: "wiz-item-manifest.svg", label: "Manifest" },
  ],
  King: [
    { file: "king-item-black.svg", label: "Scepter Black" },
    { file: "king-item-blue.svg", label: "Scepter Blue" },
    { file: "king-item-red.svg", label: "Scepter Red" },
    { file: "king-item-white.svg", label: "Scepter White" },
  ],
  Knight: [
    { file: "knight-item-bronze.svg", label: "Shield Bronze" },
    { file: "knight-item-gold.svg", label: "Shield Gold" },
    { file: "knight-item-orange.svg", label: "Shield Orange" },
    { file: "knight-item-silver.svg", label: "Shield Silver" },
  ],
  Gnome: [
    { file: "gnome-item-01.svg", label: "Flower" },
    { file: "gnome-item-02.svg", label: "Mushroom" },
    { file: "gnome-item-03.svg", label: "Wand" },
  ],
  Elf: [
    { file: "elf-item-00.svg", label: "Leaf Wreath" },
  ],
  Apprentice: [
    { file: "apprentice-item-01.svg", label: "Scroll" },
  ],
  Peasant: [
    { file: "peasant-item-01.svg", label: "Pitchfork" },
    { file: "peasant-item-02.svg", label: "Shovel" },
    { file: "peasant-item-03.svg", label: "Hoe" },
    { file: "peasant-item-bow.svg", label: "Longbow" },
  ],
};

/** Optional sub-item that can be added to any fren. */
export const SUB_ITEM: TraitLayer = {
  file: "subitem-01.svg",
  label: "Sub-item",
};

/* ------------------------------------------------------------------ */
/*  Genesis (OG Founder) frens                                         */
/* ------------------------------------------------------------------ */

/** Genesis tranche size — the OG rares minted in the presale (tokenIds 1..N). */
export const GENESIS_SUPPLY = 1111;

/**
 * A MiFren is a GENESIS Founder if it was minted in the presale — tokenIds
 * 1..GENESIS_SUPPLY. These are the only frens that earn a share of every
 * iteration's swap + sniper fees (the MiFrensDividend). Volume-minted frens
 * (ids > GENESIS_SUPPLY) are commons and do NOT earn fees.
 */
export function isGenesisFren(tokenId: bigint | number | string): boolean {
  try {
    const id = BigInt(tokenId);
    return id >= 1n && id <= BigInt(GENESIS_SUPPLY);
  } catch {
    return false;
  }
}

/** The special trait every Genesis MiFren carries. */
export const GENESIS_TRAIT = { category: "Edition", label: "Genesis Founder" };


/* ------------------------------------------------------------------ */
/*  Class ordering (rarity: rarest → most common)                      */
/* ------------------------------------------------------------------ */

export const CLASS_ORDER: FrenClass[] = [
  "Wizard",
  "King",
  "Knight",
  "Gnome",
  "Elf",
  "Apprentice",
  "Peasant",
];

export const CLASS_COLORS: Record<FrenClass, string> = {
  Wizard: "#7C5CFC",
  King: "#FFD700",
  Knight: "#75c9ee",
  Gnome: "#E94848",
  Elf: "#4ade80",
  Apprentice: "#d5fd51",
  Peasant: "#9ca3af",
};

/* ------------------------------------------------------------------ */
/*  Combination generator                                              */
/* ------------------------------------------------------------------ */

let _allFrens: Fren[] | null = null;

/** Generate every valid fren combination. Cached after first call. */
export function getAllFrens(): Fren[] {
  if (_allFrens) return _allFrens;

  const result: Fren[] = [];
  let id = 1;

  for (const cls of CLASS_ORDER) {
    const bodies = BODIES[cls];
    const items = ITEMS[cls];
    const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;

    for (const body of bodies) {
      for (const face of faces) {
        for (const item of items) {
          result.push({ id: id++, class: cls, body, face, item });
        }
      }
    }
  }

  _allFrens = result;
  return result;
}

/** Total number of unique frens. */
export function getTotalCount(): number {
  return getAllFrens().length;
}

/** Trait distribution: how many frens have each trait. */
export interface TraitStat {
  category: string;
  label: string;
  count: number;
}

export function getTraitStats(): TraitStat[] {
  const frens = getAllFrens();
  const stats: TraitStat[] = [];

  // Class counts
  for (const cls of CLASS_ORDER) {
    stats.push({
      category: "Class",
      label: cls,
      count: frens.filter((f) => f.class === cls).length,
    });
  }

  // Face counts
  for (const face of [...FACES, ...GNOME_FACES, ...ELF_FACES]) {
    const c = frens.filter((f) => f.face.file === face.file).length;
    if (c > 0) {
      stats.push({
        category: "Face",
        label: face.label,
        count: c,
      });
    }
  }

  // Body counts per class
  for (const cls of CLASS_ORDER) {
    for (const body of BODIES[cls]) {
      stats.push({
        category: "Body",
        label: body.label,
        count: frens.filter((f) => f.body.file === body.file).length,
      });
    }
  }

  // Item counts per class
  for (const cls of CLASS_ORDER) {
    for (const item of ITEMS[cls]) {
      stats.push({
        category: "Item",
        label: item.label,
        count: frens.filter((f) => f.item.file === item.file).length,
      });
    }
  }

  return stats;
}
