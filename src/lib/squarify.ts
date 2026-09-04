/**
 * Squarified treemap layout (Bruls-Huizing-van Wijk).
 * Pure function — no React dependency.
 */

export interface TreemapItem {
  id: number;
  weight: number;
}

export interface TreemapRect {
  id: number;
  x: number;
  y: number;
  w: number;
  h: number;
}

export function squarify(
  items: TreemapItem[],
  bounds: { x: number; y: number; w: number; h: number },
  gap = 1,
): TreemapRect[] {
  if (items.length === 0) return [];

  const sorted = [...items].sort((a, b) => b.weight - a.weight);
  const totalWeight = sorted.reduce((s, i) => s + i.weight, 0);

  if (totalWeight <= 0 || bounds.w <= 0 || bounds.h <= 0) return [];

  const rects: TreemapRect[] = [];
  layoutRec(sorted, bounds, totalWeight, rects, gap);
  return rects;
}

function layoutRec(
  items: TreemapItem[],
  bounds: { x: number; y: number; w: number; h: number },
  totalWeight: number,
  out: TreemapRect[],
  gap: number,
): void {
  if (items.length === 0) return;
  if (items.length === 1) {
    out.push({
      id: items[0].id,
      x: bounds.x + gap / 2,
      y: bounds.y + gap / 2,
      w: Math.max(0, bounds.w - gap),
      h: Math.max(0, bounds.h - gap),
    });
    return;
  }

  const area = bounds.w * bounds.h;
  const horizontal = bounds.w >= bounds.h;

  let bestRow: TreemapItem[] = [];
  let bestRatio = Infinity;
  let cumWeight = 0;

  for (let i = 0; i < items.length; i++) {
    const candidate = items.slice(0, i + 1);
    cumWeight += items[i].weight;
    const rowArea = (cumWeight / totalWeight) * area;
    const ratio = worstRatio(candidate, cumWeight, rowArea, horizontal ? bounds.h : bounds.w);

    if (ratio <= bestRatio) {
      bestRatio = ratio;
      bestRow = candidate;
    } else {
      break;
    }
  }

  const rowWeight = bestRow.reduce((s, i) => s + i.weight, 0);
  const rowFraction = rowWeight / totalWeight;

  if (horizontal) {
    const rowW = bounds.w * rowFraction;
    let y = bounds.y;

    for (const item of bestRow) {
      const itemH = (item.weight / rowWeight) * bounds.h;
      out.push({
        id: item.id,
        x: bounds.x + gap / 2,
        y: y + gap / 2,
        w: Math.max(0, rowW - gap),
        h: Math.max(0, itemH - gap),
      });
      y += itemH;
    }

    layoutRec(
      items.slice(bestRow.length),
      { x: bounds.x + rowW, y: bounds.y, w: bounds.w - rowW, h: bounds.h },
      totalWeight - rowWeight,
      out,
      gap,
    );
  } else {
    const rowH = bounds.h * rowFraction;
    let x = bounds.x;

    for (const item of bestRow) {
      const itemW = (item.weight / rowWeight) * bounds.w;
      out.push({
        id: item.id,
        x: x + gap / 2,
        y: bounds.y + gap / 2,
        w: Math.max(0, itemW - gap),
        h: Math.max(0, rowH - gap),
      });
      x += itemW;
    }

    layoutRec(
      items.slice(bestRow.length),
      { x: bounds.x, y: bounds.y + rowH, w: bounds.w, h: bounds.h - rowH },
      totalWeight - rowWeight,
      out,
      gap,
    );
  }
}

function worstRatio(
  row: TreemapItem[],
  rowWeight: number,
  rowArea: number,
  side: number,
): number {
  if (rowArea <= 0 || side <= 0) return Infinity;
  const s2 = (rowArea / side) * (rowArea / side);
  let worst = 0;

  for (const item of row) {
    const w = item.weight;
    const r1 = (s2 * rowWeight) / (w * rowArea);
    const r2 = (w * rowArea) / (s2 * rowWeight);
    worst = Math.max(worst, r1, r2);
  }

  return worst;
}
