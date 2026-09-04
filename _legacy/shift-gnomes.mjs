import { readFileSync, writeFileSync } from 'node:fs';

const OFFSET = 13;
const FRENS = 'public/frens';

const FILES = [
  // Bodies
  'gnome-01.svg',
  'gnome-02.svg',
  // Faces
  'gnome-face-01.svg',
  'gnome-face-02.svg',
  'gnome-face-03.svg',
  'gnome-face-04.svg',
  'gnome-face-05.svg',
  'gnome-face-06.svg',
  'gnome-face-07.svg',
  'gnome-face-08.svg',
  'gnome-face-09.svg',
  'gnome-face-10.svg',
  'gnome-face-11.svg',
  'gnome-face-laser.svg',
];

for (const file of FILES) {
  const path = `${FRENS}/${file}`;
  const src = readFileSync(path, 'utf8');

  const output = src.replace(
    /<rect x="(\d+)" y="(\d+)"/g,
    (match, x, y) => `<rect x="${x}" y="${Number(y) + OFFSET}"`
  );

  // Verify max y doesn't exceed 119 (120px canvas, 0-indexed)
  const maxY = [...output.matchAll(/y="(\d+)"/g)]
    .map(m => Number(m[1]))
    .reduce((a, b) => Math.max(a, b), 0);

  const minY = [...output.matchAll(/y="(\d+)"/g)]
    .map(m => Number(m[1]))
    .reduce((a, b) => Math.min(a, b), 999);

  writeFileSync(path, output, 'utf8');
  console.log(`${file}: shifted +${OFFSET}px → y=${minY}..${maxY}`);
}

console.log('\nDone! All gnome SVGs shifted down by 13px.');
