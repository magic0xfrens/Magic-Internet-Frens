import {
  BODIES,
  FACES,
  GNOME_FACES,
  ELF_FACES,
  ITEMS,
  CLASS_ORDER,
  type FrenClass,
} from "./frens";

/**
 * Map a class index (0-6) to its FrenClass name.
 * Order matches CLASS_ORDER in frens.ts.
 */
const CLASS_IDX_MAP: Record<number, FrenClass> = {
  0: "Wizard",
  1: "King",
  2: "Knight",
  3: "Apprentice",
  4: "Peasant",
  5: "Gnome",
  6: "Elf",
};

export interface ResolvedTraits {
  className: FrenClass | "Unknown";
  bodyLabel: string;
  faceLabel: string;
  itemLabel: string;
}

/**
 * Resolve raw trait indices into human-readable labels.
 *
 * @param classIdx  - Class index (0=Wizard, 1=King, ... 6=Elf)
 * @param bodyIdx   - Body variant index within the class
 * @param faceIdx   - Face variant index (class-aware: Gnome/Elf have own faces)
 * @param itemIdx   - Item variant index within the class
 */
export function resolveTraits(
  classIdx: number,
  bodyIdx: number,
  faceIdx: number,
  itemIdx: number,
): ResolvedTraits {
  const cls = CLASS_IDX_MAP[classIdx];
  if (!cls) {
    return {
      className: "Unknown",
      bodyLabel: `Body ${bodyIdx}`,
      faceLabel: `Face ${faceIdx}`,
      itemLabel: `Item ${itemIdx}`,
    };
  }

  const bodies = BODIES[cls];
  const faces =
    cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
  const items = ITEMS[cls];

  return {
    className: cls,
    bodyLabel: bodies[bodyIdx]?.label ?? `Body ${bodyIdx}`,
    faceLabel: faces[faceIdx]?.label ?? `Face ${faceIdx}`,
    itemLabel: items[itemIdx]?.label ?? `Item ${itemIdx}`,
  };
}

export interface ResolvedSprites {
  bodyFile: string;
  faceFile: string;
  itemFile: string;
}

/**
 * Resolve trait indices to SVG sprite filenames in /public/frens/.
 */
export function resolveSprites(
  classIdx: number,
  bodyIdx: number,
  faceIdx: number,
  itemIdx: number,
): ResolvedSprites {
  const cls = CLASS_IDX_MAP[classIdx];
  if (!cls) {
    return { bodyFile: "", faceFile: "", itemFile: "" };
  }

  const bodies = BODIES[cls];
  const faces =
    cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
  const items = ITEMS[cls];

  const body = bodies[bodyIdx] ?? bodies[0];
  const face = faces[faceIdx] ?? faces[0];
  const item = items[itemIdx] ?? items[0];

  return {
    bodyFile: body?.file ?? "",
    faceFile: face?.file ?? "",
    itemFile: item?.file ?? "",
  };
}

/**
 * Build a short trait summary string, e.g. "Wizard I · Classic · Wand"
 */
export function traitSummary(
  classIdx: number,
  bodyIdx: number,
  faceIdx: number,
  itemIdx: number,
): string {
  const t = resolveTraits(classIdx, bodyIdx, faceIdx, itemIdx);
  return `${t.bodyLabel} · ${t.faceLabel} · ${t.itemLabel}`;
}
