import { BODIES, FACES, GNOME_FACES, ELF_FACES, ITEMS, type FrenClass } from "@/data/frens";

/**
 * Deterministic, COLLISION-FREE trait assignment for the Cauldron MiFrens.
 *
 * The on-chain collection stores rarity + a renderer URI, not the legacy
 * class/body/face/item traits — so we assign a look to each tokenId client-side.
 * A naive hash collides badly (1111 tokens over ~1200 combos → the birthday
 * problem), producing visually identical "repeated frens". Instead we enumerate
 * EVERY valid combo once, shuffle the list with a fixed seed, and map
 * `tokenId → combos[tokenId-1]`. Because the list has one entry per distinct
 * look, no two tokenIds in 1..COMBO_COUNT can ever share a combo — duplicates
 * are impossible by construction. The shuffle is fixed, so a token's look is
 * stable forever.
 */

// classIdx → FrenClass, matching the trait resolver's CLASS_IDX_MAP.
const CLASS_BY_IDX: Record<number, FrenClass> = {
  0: "Wizard", 1: "King", 2: "Knight", 3: "Apprentice", 4: "Peasant", 5: "Gnome", 6: "Elf",
};

export interface FrenTraitIdx { classIdx: number; bodyIdx: number; faceIdx: number; itemIdx: number; }

function facesFor(cls: FrenClass) {
  return cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
}

// Build the full ordered list of every distinct (class, body, face, item) combo.
function enumerateCombos(): FrenTraitIdx[] {
  const out: FrenTraitIdx[] = [];
  for (let classIdx = 0; classIdx < 7; classIdx++) {
    const cls = CLASS_BY_IDX[classIdx]!;
    const nb = BODIES[cls]?.length ?? 0;
    const nf = facesFor(cls).length;
    const ni = ITEMS[cls]?.length ?? 0;
    for (let b = 0; b < nb; b++)
      for (let f = 0; f < nf; f++)
        for (let i = 0; i < ni; i++)
          out.push({ classIdx, bodyIdx: b, faceIdx: f, itemIdx: i });
  }
  return out;
}

// Mulberry32 — small, fast, deterministic PRNG for the shuffle.
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Fixed seed → the assignment is identical across every client, forever.
const SHUFFLE_SEED = 0x4d69_4672; // "MiFr"

let _shuffled: FrenTraitIdx[] | null = null;
function shuffledCombos(): FrenTraitIdx[] {
  if (_shuffled) return _shuffled;
  const arr = enumerateCombos();
  const rand = mulberry32(SHUFFLE_SEED);
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [arr[i], arr[j]] = [arr[j]!, arr[i]!];
  }
  _shuffled = arr;
  return arr;
}

/** Total number of visually-distinct frens (the collision-free capacity). */
export const COMBO_COUNT = enumerateCombos().length;

/**
 * The unique trait combo for a tokenId. Ids 1..COMBO_COUNT each get a DISTINCT
 * look; beyond that it wraps (only relevant far past the 1111 genesis tranche).
 */
export function frenTraitsForToken(tokenId: bigint | number): FrenTraitIdx {
  const list = shuffledCombos();
  const n = list.length;
  const id = Number(BigInt(tokenId) % BigInt(n)); // 0-indexed slot; id 1 → slot 0
  const idx = ((id - 1) % n + n) % n;
  return list[idx]!;
}
