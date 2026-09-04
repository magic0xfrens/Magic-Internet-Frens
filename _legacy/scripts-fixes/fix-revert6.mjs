import { readFileSync, writeFileSync } from 'fs';

// Revert: #A83410 (was #795548) back to #795548 — but only the 218 that were staff handle
// Since we merged INTO #A83410 which already had 40 uses, we need to distinguish.
// Simplest: just restore from git for wiz-item-manifest.svg and re-apply rounds 1-5 merges

// Actually let me just re-apply rounds 1+3+4 to the git version
// Round 1 merges for wiz-item-manifest.svg:
//   #777454 → #6F8658, #6F8658 → #5D8F36, #9CCC65 → #7ADA54, #0D5302 → #2E461A
// Round 3:
//   #2E461A → #2B401A, #DD191D → #A83410, #7ADA54 → #5D8F36
// Round 4:
//   #03A9F4 → #000000, #FAF1C3 → #FFFFFF

let svg = readFileSync('public/frens/wiz-item-manifest.svg', 'utf-8');

// Currently all #A83410 includes both original (22) and converted from #795548 (218)
// We need #795548 back. The total #A83410 count should be 258, we need it to be 40.
// Let me just check: the original SVG has rect elements at specific positions.
// Easier approach: restore from the original and apply all merges except round 6.

console.log('Current #A83410 count:', (svg.match(/#A83410/gi) || []).length);
console.log('Reverting all #A83410 with count > original...');

// The cleanest approach: use git to restore, then replay merges
import { execSync } from 'child_process';
execSync('git checkout -- public/frens/wiz-item-manifest.svg');
console.log('Restored from git.');

svg = readFileSync('public/frens/wiz-item-manifest.svg', 'utf-8');
console.log('Original colors:');
const fills0 = {};
const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
let m;
while ((m = re.exec(svg)) !== null) { fills0[m[1].toUpperCase()] = (fills0[m[1].toUpperCase()] || 0) + 1; }
console.log('  ', Object.keys(fills0).length, 'colors');

// Replay round 1 merges
svg = svg.replace(/#777454/gi, '#6F8658');
svg = svg.replace(/#6F8658/gi, '#5D8F36');
svg = svg.replace(/#9CCC65/gi, '#7ADA54');
svg = svg.replace(/#0D5302/gi, '#2E461A');
console.log('Round 1 applied');

// Replay round 2 merges
svg = svg.replace(/#D9E4A3/gi, '#FAF1C3');
svg = svg.replace(/#B2AD7A/gi, '#FAF1C3');
console.log('Round 2 applied');

// Replay round 3 merges
svg = svg.replace(/#2E461A/gi, '#2B401A');
svg = svg.replace(/#DD191D/gi, '#A83410');
svg = svg.replace(/#7ADA54/gi, '#5D8F36');
console.log('Round 3 applied');

// Replay round 4 merges
svg = svg.replace(/#03A9F4/gi, '#000000');
svg = svg.replace(/#FAF1C3/gi, '#FFFFFF');
console.log('Round 4 applied');

// Do NOT apply round 6 (#795548 → #A83410)

writeFileSync('public/frens/wiz-item-manifest.svg', svg);

const fills = {};
const re2 = /fill="(#[0-9a-fA-F]{3,6})"/g;
while ((m = re2.exec(svg)) !== null) { fills[m[1].toUpperCase()] = (fills[m[1].toUpperCase()] || 0) + 1; }
console.log('Final colors:', Object.keys(fills).length);
for (const [h, c] of Object.entries(fills).sort((a, b) => b[1] - a[1])) {
    console.log('  ' + h + ' ' + c + 'px');
}
