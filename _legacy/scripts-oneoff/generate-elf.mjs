#!/usr/bin/env node
/**
 * generate-elf.mjs
 *
 * Transforms gnome-01.svg into elf-01.svg and gnome-face-*.svg into elf-face-*.svg.
 *
 * - Recolors the hat from red palette to green palette
 * - Removes hat pixels with y < 27 (chops the tall pointy top)
 * - Adds a small droopy tip on the RIGHT side (classic elf cap)
 * - Adds pointed ears to both body and face layers
 * - Generates all elf-face-NN.svg files from gnome-face-NN.svg
 */

import { readFileSync, writeFileSync, readdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FRENS_DIR = join(__dirname, '..', 'public', 'frens');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Parse an SVG file that contains only <rect> elements.
 * Returns an array of { x, y, fill } objects.
 */
function parseRects(svgContent) {
  const rects = [];
  const regex = /x="(\d+)"\s+y="(\d+)"\s+width="1"\s+height="1"\s+fill="([^"]+)"/g;
  let m;
  while ((m = regex.exec(svgContent)) !== null) {
    rects.push({ x: parseInt(m[1], 10), y: parseInt(m[2], 10), fill: m[3] });
  }
  return rects;
}

/**
 * Build an SVG string from an array of { x, y, fill } pixels.
 * Pixels are sorted by y then x. Uses the gnome-01.svg header format.
 */
function buildSvg(pixels, headerStyle = 'body') {
  pixels.sort((a, b) => a.y - b.y || a.x - b.x);

  let header;
  if (headerStyle === 'body') {
    header =
      '<?xml version="1.0" encoding="UTF-8" ?>\n' +
      '<svg version="1.1" width="120" height="120" xmlns="http://www.w3.org/2000/svg" shape-rendering="crispEdges">\n';
  } else {
    // face files use a slightly different header (viewBox, no version/xml declaration)
    header =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" shape-rendering="crispEdges">\n';
  }

  let body = '';
  for (const p of pixels) {
    body += `<rect x="${p.x}" y="${p.y}" width="1" height="1" fill="${p.fill}"/>\n`;
  }

  return header + body + '</svg>\n';
}

/**
 * Create a key for a pixel position so we can look up conflicts.
 */
function posKey(x, y) {
  return `${x},${y}`;
}

/**
 * Build a Set of position keys from an array of pixels.
 */
function positionSet(pixels) {
  const s = new Set();
  for (const p of pixels) s.add(posKey(p.x, p.y));
  return s;
}

// ---------------------------------------------------------------------------
// Hat color mapping (red -> green)
// ---------------------------------------------------------------------------

const HAT_COLOR_MAP = {
  '#4F0000': '#0D2B0D', // dark outline
  '#B01616': '#2D6B2D', // mid red -> mid green
  '#E94848': '#4AA84A', // bright red -> bright green
  '#771515': '#1F5020', // dark red shadow -> shadow green
};

// Also handle lowercase variants just in case
const HAT_COLOR_MAP_LOWER = {};
for (const [k, v] of Object.entries(HAT_COLOR_MAP)) {
  HAT_COLOR_MAP_LOWER[k.toLowerCase()] = v;
}

function mapHatColor(fill) {
  return HAT_COLOR_MAP[fill] || HAT_COLOR_MAP_LOWER[fill.toLowerCase()] || fill;
}

// ---------------------------------------------------------------------------
// Generate elf-01.svg from gnome-01.svg
// ---------------------------------------------------------------------------

function generateElfBody() {
  const gnomeSvg = readFileSync(join(FRENS_DIR, 'gnome-01.svg'), 'utf8');
  const gnomePixels = parseRects(gnomeSvg);

  const elfPixels = [];

  for (const p of gnomePixels) {
    // Remove hat pixels with y < 27
    if (p.y < 27) continue;

    if (p.y < 55) {
      // Hat area: remap colors if they are in the red palette
      elfPixels.push({ x: p.x, y: p.y, fill: mapHatColor(p.fill) });
    } else {
      // Clothing area: keep as-is
      elfPixels.push({ ...p });
    }
  }

  // Build position set for conflict checking
  const posSet = positionSet(elfPixels);

  // Add the droopy elf cap tip on the RIGHT side
  // The gnome's droopy brim goes from ~y=35 down to y=42 on the right (x=85-87).
  // We add a small triangular point at around y=22-25, x=82-86, using green colors.
  const elfCapTip = [
    { x: 83, y: 22, fill: '#0D2B0D' },
    { x: 84, y: 22, fill: '#0D2B0D' },
    { x: 85, y: 22, fill: '#0D2B0D' },
    { x: 84, y: 23, fill: '#2D6B2D' },
    { x: 85, y: 23, fill: '#0D2B0D' },
    { x: 86, y: 23, fill: '#0D2B0D' },
    { x: 85, y: 24, fill: '#2D6B2D' },
    { x: 86, y: 24, fill: '#0D2B0D' },
    { x: 86, y: 25, fill: '#0D2B0D' },
  ];

  for (const p of elfCapTip) {
    const key = posKey(p.x, p.y);
    if (!posSet.has(key)) {
      elfPixels.push(p);
      posSet.add(key);
    }
  }

  // Add pointed ears to the body layer
  const leftEar = [
    { x: 38, y: 38, fill: '#E8D49A' },
    { x: 37, y: 39, fill: '#E8D49A' },
    { x: 38, y: 39, fill: '#8B7550' },
    { x: 36, y: 40, fill: '#E8D49A' },
    { x: 37, y: 40, fill: '#8B7550' },
    { x: 38, y: 40, fill: '#8B7550' },
  ];

  const rightEar = [
    { x: 83, y: 38, fill: '#E8D49A' },
    { x: 84, y: 39, fill: '#E8D49A' },
    { x: 83, y: 39, fill: '#8B7550' },
    { x: 85, y: 40, fill: '#E8D49A' },
    { x: 84, y: 40, fill: '#8B7550' },
    { x: 83, y: 40, fill: '#8B7550' },
  ];

  for (const p of [...leftEar, ...rightEar]) {
    const key = posKey(p.x, p.y);
    // Ear pixels overlay even if hat pixels exist there (they'll be on top)
    // But if a pixel already exists at that position, replace it with ear pixel
    const existing = elfPixels.findIndex(ep => ep.x === p.x && ep.y === p.y);
    if (existing !== -1) {
      elfPixels[existing] = p;
    } else {
      elfPixels.push(p);
    }
  }

  const svg = buildSvg(elfPixels, 'body');
  const outPath = join(FRENS_DIR, 'elf-01.svg');
  writeFileSync(outPath, svg, 'utf8');
  console.log(`Created: ${outPath}`);
}

// ---------------------------------------------------------------------------
// Generate elf-face-NN.svg from gnome-face-NN.svg
// ---------------------------------------------------------------------------

function generateElfFace(inputFilename) {
  const match = inputFilename.match(/gnome-face-(\d+)\.svg$/);
  if (!match) return null;

  const num = match[1];
  const gnomeSvg = readFileSync(join(FRENS_DIR, inputFilename), 'utf8');
  const facePixels = parseRects(gnomeSvg);

  // Build position set of existing pixels
  const posSet = positionSet(facePixels);

  // Pointed ear tip pixels for the face layer
  const leftEarFace = [
    { x: 38, y: 39, fill: '#E8D49A' },
    { x: 37, y: 40, fill: '#E8D49A' },
    { x: 38, y: 40, fill: '#8B7550' },
    { x: 36, y: 41, fill: '#E8D49A' },
    { x: 37, y: 41, fill: '#8B7550' },
  ];

  const rightEarFace = [
    { x: 84, y: 39, fill: '#E8D49A' },
    { x: 85, y: 40, fill: '#E8D49A' },
    { x: 84, y: 40, fill: '#8B7550' },
    { x: 86, y: 41, fill: '#E8D49A' },
    { x: 85, y: 41, fill: '#8B7550' },
  ];

  // Only add ear pixels that don't conflict with existing pixels
  for (const p of [...leftEarFace, ...rightEarFace]) {
    const key = posKey(p.x, p.y);
    if (!posSet.has(key)) {
      facePixels.push(p);
      posSet.add(key);
    }
  }

  const svg = buildSvg(facePixels, 'face');
  const outFilename = `elf-face-${num}.svg`;
  const outPath = join(FRENS_DIR, outFilename);
  writeFileSync(outPath, svg, 'utf8');
  console.log(`Created: ${outPath}`);
  return outFilename;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

console.log('Generating elf SVGs...\n');

// 1. Generate elf body
generateElfBody();

// 2. Generate all elf face files
const faceFiles = readdirSync(FRENS_DIR)
  .filter(f => /^gnome-face-\d+\.svg$/.test(f))
  .sort();

console.log(`\nFound ${faceFiles.length} gnome face files to convert.\n`);

for (const f of faceFiles) {
  generateElfFace(f);
}

console.log('\nDone! All elf SVG files generated.');
