#!/usr/bin/env node
/**
 * create-btc-wizard.mjs
 *
 * Takes wizard-01.svg (purple robe, gold stars) and creates wizard-btc-01.svg:
 *   1. Purple robe → BTC orange robe
 *   2. Gold stars → white stars (keep shapes, just recolor)
 *   3. ONE BTC ₿ logo on the chest (most central body star, native 12x17)
 */

import { readFileSync, writeFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FRENS_DIR = join(__dirname, "..", "public", "frens");

// Purple → BTC orange
const COLOR_MAP = {
  "#655199": "#E8850F",
  "#4C3D72": "#B86A0C",
  "#544380": "#CC770E",
  "#403361": "#8B520A",
  "#2A223E": "#5C3607",
};

// Gold star colors → white
const STAR_COLORS = new Set(["#FBC02D", "#B08927", "#46360D", "#957011"]);
const STAR_RECOLOR = "#FFFFFF";

// BTC ₿ logo from btc_pixel_art.svg — native 12x17, no scaling
const BTC_LOGO = [
  [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0],
  [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  [0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0],
  [0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0],
  [0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0],
  [0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0],
  [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
  [0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1],
  [0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1],
  [0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0],
  [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0],
];

const LOGO_W = 12;
const LOGO_H = 17;

function parseSVG(content) {
  const lines = content.split("\n");
  const header = lines[0];
  const svgOpen = lines[1];
  const pixels = [];
  for (const line of lines) {
    const m = line.match(
      /x="(\d+)"\s+y="(\d+)"\s+width="1"\s+height="1"\s+fill="(#[0-9a-fA-F]{6})"/
    );
    if (m) pixels.push({ x: +m[1], y: +m[2], fill: m[3] });
  }
  return { header, svgOpen, pixels };
}

function findStarClusters(pixels) {
  const starPx = pixels.filter((p) => STAR_COLORS.has(p.fill));
  const visited = new Set();
  const clusters = [];
  const starMap = new Map();
  for (const p of starPx) starMap.set(`${p.x},${p.y}`, p);

  function bfs(start) {
    const cluster = [start];
    const queue = [start];
    visited.add(`${start.x},${start.y}`);
    while (queue.length) {
      const cur = queue.shift();
      for (let dx = -1; dx <= 1; dx++)
        for (let dy = -1; dy <= 1; dy++) {
          if (!dx && !dy) continue;
          const k = `${cur.x + dx},${cur.y + dy}`;
          if (!visited.has(k) && starMap.has(k)) {
            visited.add(k);
            const p = starMap.get(k);
            cluster.push(p);
            queue.push(p);
          }
        }
    }
    return cluster;
  }

  for (const p of starPx) {
    const k = `${p.x},${p.y}`;
    if (!visited.has(k)) {
      const c = bfs(p);
      if (c.length >= 3) clusters.push(c);
    }
  }
  return clusters;
}

function main() {
  const srcPath = join(FRENS_DIR, "wizard-01.svg");
  const dstPath = join(FRENS_DIR, "wizard-btc-01.svg");

  const content = readFileSync(srcPath, "utf-8");
  const { header, svgOpen, pixels } = parseSVG(content);

  // Find the most central star cluster in the BODY area (y > 60 = below the hat)
  const clusters = findStarClusters(pixels);

  // Get body bounds to find center of the robe
  const bodyPixels = pixels.filter((p) => p.y > 60);
  let bodyMinX = Infinity, bodyMaxX = -Infinity, bodyMinY = Infinity, bodyMaxY = -Infinity;
  for (const p of bodyPixels) {
    bodyMinX = Math.min(bodyMinX, p.x);
    bodyMaxX = Math.max(bodyMaxX, p.x);
    bodyMinY = Math.min(bodyMinY, p.y);
    bodyMaxY = Math.max(bodyMaxY, p.y);
  }
  const bodyCx = Math.round((bodyMinX + bodyMaxX) / 2);
  const bodyCy = Math.round((bodyMinY + bodyMaxY) / 2);
  console.log(`Body center: (${bodyCx},${bodyCy})`);

  // Filter clusters to body area only, then pick the one closest to body center
  const bodyClusters = clusters.filter((c) => {
    const avgY = c.reduce((s, p) => s + p.y, 0) / c.length;
    return avgY > 60;
  });

  let chestCluster = null;
  let bestDist = Infinity;
  for (const c of bodyClusters) {
    let cMinX = Infinity, cMinY = Infinity, cMaxX = -Infinity, cMaxY = -Infinity;
    for (const p of c) {
      cMinX = Math.min(cMinX, p.x); cMinY = Math.min(cMinY, p.y);
      cMaxX = Math.max(cMaxX, p.x); cMaxY = Math.max(cMaxY, p.y);
    }
    const ccx = Math.round((cMinX + cMaxX) / 2);
    const ccy = Math.round((cMinY + cMaxY) / 2);
    const dist = Math.hypot(ccx - bodyCx, ccy - bodyCy);
    if (dist < bestDist) {
      bestDist = dist;
      chestCluster = c;
    }
  }

  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const p of chestCluster) {
    minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
    maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y);
  }
  const cx = Math.round((minX + maxX) / 2);
  const cy = Math.round((minY + maxY) / 2);
  const chestCoords = new Set(chestCluster.map((p) => `${p.x},${p.y}`));

  console.log(`Chest star: ${chestCluster.length}px at center (${cx},${cy})`);

  // Logo placement — nudge right +3, down +3 per user request
  const logoX = cx - Math.floor(LOGO_W / 2) + 3;
  const logoY = cy - Math.floor(LOGO_H / 2) + 3;
  console.log(`BTC logo placed at (${logoX},${logoY}) — native ${LOGO_W}x${LOGO_H}`);

  // Remove specific star clusters: the chest star + the one directly below the logo
  // Target clusters by center proximity to known positions
  const clearCoords = new Set();
  for (const c of clusters) {
    let cMinX = Infinity, cMinY = Infinity, cMaxX = -Infinity, cMaxY = -Infinity;
    for (const p of c) {
      cMinX = Math.min(cMinX, p.x); cMinY = Math.min(cMinY, p.y);
      cMaxX = Math.max(cMaxX, p.x); cMaxY = Math.max(cMaxY, p.y);
    }
    const ccx = Math.round((cMinX + cMaxX) / 2);
    const ccy = Math.round((cMinY + cMaxY) / 2);
    // Only clear clusters that directly overlap the logo rect
    const logoRight = logoX + LOGO_W - 1;
    const logoBottom = logoY + LOGO_H - 1;
    const overlaps = cMaxX >= logoX && cMinX <= logoRight && cMaxY >= logoY && cMinY <= logoBottom;
    if (overlaps) {
      console.log(`  Clearing cluster: ${c.length}px at (${ccx},${ccy})`);
      for (const p of c) clearCoords.add(`${p.x},${p.y}`);
    }
  }

  // Collect coords of the star cluster at ~(73,92) to shift it right+3, up-3
  const shiftCoords = new Set();
  for (const c of clusters) {
    let cMinX = Infinity, cMinY = Infinity, cMaxX = -Infinity, cMaxY = -Infinity;
    for (const p of c) {
      cMinX = Math.min(cMinX, p.x); cMinY = Math.min(cMinY, p.y);
      cMaxX = Math.max(cMaxX, p.x); cMaxY = Math.max(cMaxY, p.y);
    }
    const ccx = Math.round((cMinX + cMaxX) / 2);
    const ccy = Math.round((cMinY + cMaxY) / 2);
    if (ccx === 73 && ccy === 92) {
      console.log(`  Shifting star at (${ccx},${ccy}) by (+3, -3)`);
      for (const p of c) shiftCoords.add(`${p.x},${p.y}`);
    }
  }

  const pixelMap = new Map();

  for (const p of pixels) {
    let fill = p.fill;

    // Remap purple → orange
    if (COLOR_MAP[fill]) fill = COLOR_MAP[fill];

    // Recolor stars → white (except stars near logo area which become orange robe)
    if (STAR_COLORS.has(p.fill)) {
      if (chestCoords.has(`${p.x},${p.y}`) || clearCoords.has(`${p.x},${p.y}`)) {
        fill = "#E8850F";
      } else if (shiftCoords.has(`${p.x},${p.y}`)) {
        // Replace original position with orange, we'll add shifted version after
        fill = "#E8850F";
      } else {
        fill = STAR_RECOLOR;
      }
    }

    pixelMap.set(`${p.x},${p.y}`, { x: p.x, y: p.y, fill });
  }

  // Add the shifted star pixels (right +3, up -3)
  for (const p of pixels) {
    if (STAR_COLORS.has(p.fill) && shiftCoords.has(`${p.x},${p.y}`)) {
      const nx = p.x + 3;
      const ny = p.y - 3;
      pixelMap.set(`${nx},${ny}`, { x: nx, y: ny, fill: STAR_RECOLOR });
    }
  }

  // Stamp ONE BTC logo on chest
  for (let row = 0; row < LOGO_H; row++) {
    for (let col = 0; col < LOGO_W; col++) {
      if (BTC_LOGO[row][col] === 1) {
        const px = logoX + col;
        const py = logoY + row;
        pixelMap.set(`${px},${py}`, { x: px, y: py, fill: "#FFFFFF" });
      }
    }
  }

  const sorted = [...pixelMap.values()].sort((a, b) => a.y - b.y || a.x - b.x);
  const lines = [header, svgOpen];
  for (const p of sorted) {
    lines.push(`<rect x="${p.x}" y="${p.y}" width="1" height="1" fill="${p.fill}" />`);
  }
  lines.push("</svg>");

  writeFileSync(dstPath, lines.join("\n"), "utf-8");
  console.log(`Written ${dstPath} (${sorted.length} pixels)`);
}

main();
