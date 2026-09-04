import { readFileSync, writeFileSync } from 'node:fs';

// Parse SVG pixel rects into a Map of "x,y" → color
function parseSVG(path) {
  const src = readFileSync(path, 'utf8');
  const map = new Map();
  const re = /<rect x="(\d+)" y="(\d+)" width="1" height="1" fill="(#[0-9A-Fa-f]{6})"\s*\/>/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    map.set(`${m[1]},${m[2]}`, m[3].toUpperCase());
  }
  return { map, src };
}

// Vibrant color remap for laser pixels
const VIBRANT_MAP = {
  '#A83410': '#FF2200',  // dark brown-red  → vivid red-orange
  '#800C0C': '#DD0000',  // very dark red   → bright dark red
  '#CC0000': '#FF0000',  // dull red        → pure red
  '#EF6C00': '#FF6600',  // orange          → brighter orange
  '#FFCC00': '#FFFF00',  // yellow          → pure yellow
  '#990000': '#EE0000',  // dark red        → bright red
  '#FF0000': '#FF1A1A',  // already red     → keep vivid
  '#771515': '#CC0000',  // dark burgundy   → medium red
  '#4F0000': '#990000',  // near-black red  → dark red (still visible)
  '#751B14': '#CC1100',  // dark red-brown  → vivid dark red
};

function processFile(basePath, laserPath) {
  const base = parseSVG(basePath);
  const laser = parseSVG(laserPath);

  // Find laser-only pixels: changed or added vs base
  const laserPixels = new Set();
  for (const [coord, color] of laser.map) {
    const baseColor = base.map.get(coord);
    if (!baseColor || baseColor !== color) {
      laserPixels.add(coord);
    }
  }

  console.log(`${laserPath}: ${laserPixels.size} laser pixels found`);

  // Count laser pixel colors before remap
  const colorCounts = {};
  for (const coord of laserPixels) {
    const c = laser.map.get(coord);
    colorCounts[c] = (colorCounts[c] || 0) + 1;
  }
  console.log('  Laser colors before:', colorCounts);

  // Remap only laser pixels in the SVG source
  let output = laser.src;
  let remapped = 0;

  for (const coord of laserPixels) {
    const [x, y] = coord.split(',');
    const oldColor = laser.map.get(coord);
    const newColor = VIBRANT_MAP[oldColor];
    if (newColor && newColor !== oldColor) {
      // Match this specific rect and replace its color
      const oldRect = `<rect x="${x}" y="${y}" width="1" height="1" fill="${oldColor}"`;
      const newRect = `<rect x="${x}" y="${y}" width="1" height="1" fill="${newColor}"`;
      if (output.includes(oldRect)) {
        output = output.replace(oldRect, newRect);
        remapped++;
      }
    }
  }

  // Count laser pixel colors after remap
  const afterCounts = {};
  for (const coord of laserPixels) {
    const c = laser.map.get(coord);
    const mapped = VIBRANT_MAP[c] || c;
    afterCounts[mapped] = (afterCounts[mapped] || 0) + 1;
  }
  console.log('  Laser colors after: ', afterCounts);
  console.log(`  Remapped ${remapped} pixels\n`);

  writeFileSync(laserPath, output, 'utf8');
}

const FRENS = 'public/frens';

processFile(`${FRENS}/face-01.svg`, `${FRENS}/face-laser.svg`);
processFile(`${FRENS}/gnome-face-01.svg`, `${FRENS}/gnome-face-laser.svg`);

console.log('Done! Laser eyes are now vibrant.');
