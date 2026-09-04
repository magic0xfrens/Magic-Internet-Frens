import type { FrenClass } from "./frens";

export interface ClassSpec {
  class: FrenClass;
  label: string;
  supplyPct: number;
  targetCount: number;
  taxPct: number;
  governance: number;
  color: string;
}

/** Actual SVG file sizes in bytes (measured from /public/frens/). */
export const SVG_SIZES: Record<string, number> = {
  "wizard-01.svg": 190008,
  "wizard-02.svg": 190008,
  "wizard-03.svg": 190008,
  "wizard-04.svg": 193076,
  "wizard-05.svg": 190008,
  "wizard-06.svg": 194610,
  "wizard-manifest.svg": 188061,
  "wizard-btc-01.svg": 190008,
  "king-cloth-black.svg": 133484,
  "king-cloth-blue.svg": 133484,
  "king-cloth-orange.svg": 133484,
  "king-cloth-red.svg": 133484,
  "king-cloth-white.svg": 133484,
  "knight-bronze.svg": 149171,
  "knight-gold.svg": 149171,
  "knight-orange.svg": 149171,
  "knight-silver.svg": 149171,
  "apprentice-01.svg": 161486,
  "apprentice-02.svg": 161486,
  "apprentice-02-orange.svg": 161486,
  "peasant-01.svg": 79002,
  "peasant-02.svg": 36735,
  "face-01.svg": 174995,
  "face-02.svg": 174995,
  "face-03.svg": 174995,
  "face-04.svg": 174995,
  "face-05.svg": 174995,
  "face-06.svg": 174995,
  "face-07.svg": 174287,
  "face-08.svg": 174287,
  "face-09.svg": 174995,
  "face-10.svg": 175054,
  "face-11.svg": 174995,
  "wiz-item-01.svg": 33170,
  "wiz-item-02.svg": 19768,
  "wiz-item-03.svg": 21006,
  "wiz-item-04.svg": 15765,
  "wiz-item-manifest.svg": 52465,
  "king-item-black.svg": 10138,
  "king-item-blue.svg": 10138,
  "king-item-red.svg": 10138,
  "king-item-white.svg": 10138,
  "knight-item-bronze.svg": 14492,
  "knight-item-gold.svg": 14492,
  "knight-item-orange.svg": 14492,
  "knight-item-silver.svg": 14492,
  "apprentice-item-01.svg": 18238,
  "peasant-item-01.svg": 18296,
  "peasant-item-02.svg": 12365,
  "peasant-item-03.svg": 13327,
  "gnome-01.svg": 141283,
  "gnome-face-01.svg": 61220,
  "gnome-face-02.svg": 61220,
  "gnome-face-03.svg": 61220,
  "gnome-face-04.svg": 61220,
  "gnome-face-05.svg": 61220,
  "gnome-face-06.svg": 61220,
  "gnome-face-07.svg": 60453,
  "gnome-face-08.svg": 61043,
  "gnome-face-09.svg": 61220,
  "gnome-face-10.svg": 61279,
  "gnome-face-11.svg": 61220,
  "gnome-item-01.svg": 5406,
  "gnome-02.svg": 117955,
  "gnome-item-02.svg": 6015,
  "gnome-item-03.svg": 4623,
  "elf-02.svg": 164368,
  "elf-03.svg": 164368,
  "elf-04.svg": 164368,
  "elf-face-01.svg": 171979,
  "elf-face-02.svg": 171979,
  "elf-face-03.svg": 171979,
  "elf-face-04.svg": 171979,
  "elf-face-05.svg": 171979,
  "elf-face-06.svg": 171979,
  "elf-face-07.svg": 171283,
  "elf-face-08.svg": 171283,
  "elf-face-09.svg": 171979,
  "elf-face-10.svg": 172037,
  "elf-face-11.svg": 171979,
  "elf-face-laser.svg": 171979,
  "elf-item-00.svg": 14718,
};

/** Sum the real SVG byte sizes of the 3 composited layers. */
export function compositeBytes(bodyFile: string, faceFile: string, itemFile: string): number {
  return (SVG_SIZES[bodyFile] ?? 0) + (SVG_SIZES[faceFile] ?? 0) + (SVG_SIZES[itemFile] ?? 0);
}

export const CLASS_SPECS: ClassSpec[] = [
  {
    class: "Wizard",
    label: "Wizard",
    supplyPct: 44,
    targetCount: 342,
    taxPct: 0,
    governance: 10,
    color: "#7F77DD",
  },
  {
    class: "King",
    label: "King",
    supplyPct: 22,
    targetCount: 171,
    taxPct: 0.5,
    governance: 5,
    color: "#EF9F27",
  },
  {
    class: "Knight",
    label: "Knight",
    supplyPct: 17.5,
    targetCount: 136,
    taxPct: 1,
    governance: 3,
    color: "#1D9E75",
  },
  {
    class: "Gnome",
    label: "Gnome",
    supplyPct: 6.6,
    targetCount: 51,
    taxPct: 0.5,
    governance: 4,
    color: "#E94848",
  },
  {
    class: "Elf",
    label: "Elf",
    supplyPct: 4.4,
    targetCount: 34,
    taxPct: 0.5,
    governance: 1,
    color: "#4ade80",
  },
  {
    class: "Apprentice",
    label: "Apprentice",
    supplyPct: 3.3,
    targetCount: 26,
    taxPct: 1,
    governance: 2,
    color: "#D85A30",
  },
  {
    class: "Peasant",
    label: "Peasant",
    supplyPct: 2.2,
    targetCount: 17,
    taxPct: 2,
    governance: 1,
    color: "#888780",
  },
];

export const TOTAL_SUPPLY = 777;
export const BLOCKS_PER_EPOCH = 5;
export const MINTS_PER_BLOCK: [number, number] = [1, 4];

export function calcFee(bytes: number): number {
  return Math.round(330 + bytes * 0.9 + Math.random() * 300);
}

export function specByClass(cls: FrenClass): ClassSpec {
  return CLASS_SPECS.find((s) => s.class === cls)!;
}
