import { readFileSync, writeFileSync } from 'fs';

// Try different merges for the last #795548 (brown, 218px)
// Option A: → #5D8F36 (green, shared with face) dist=88
// Option B: → #2B401A (dark green, shared with face) dist=93
// Option C: → #000000 (black) dist=165
// Option D: don't merge it, instead make wizard-05 simpler

// Let's try Option D: in wizard-05.svg, merge #6E4803 → #FFC107 (dark gold → bright gold)
// This reduces body to 3 very distinct colors (#000000, #FFC107, #FFFFFF)
// which should compress much better since there's less pixel variation

let svg = readFileSync('public/frens/wizard-05.svg', 'utf-8');

// Current wizard-05 colors: #FFC107(1724), #6E4803(829), #000000(606), #FFFFFF(52)
// #6E4803 (110,72,3) → #FFC107 (255,193,7): dist=195 — too aggressive, would lose all shadow detail

// Better idea: don't touch wizard-05 body. Instead look at this from a different angle.
// The failing combos are b4+f2+i4 and b4+f3+i4, both at exactly 2049 bytes.
// That's literally 1 byte over.
// What if we change the receipt format slightly? Or use a shorter class name?
// No — the contract is fixed.
// What if we encode with a slightly different zlib strategy?

// Actually, let me check: the on-chain DEFLATE uses fixed Huffman with LZ77.
// The verify script uses node's zlib with Z_FIXED strategy.
// But the deflateRawSync level=6 might find slightly different matches than the on-chain encoder.
// The on-chain encoder has windowBits=15, lazy matching with maxChain=128.
// Let me try level=9 (best compression) in the verify script to see if it helps.

// For now, let me try a completely different approach:
// Instead of merging item colors, REDUCE wizard-03.svg (body 2) even more.
// Body 2 has close pair: #96D41E ↔ #7FB615 dist=38.9
// These are both bright greens. If we merge: #96D41E → #7FB615

let svg03 = readFileSync('public/frens/wizard-03.svg', 'utf-8');
let c1 = (svg03.match(/#96D41E/gi) || []).length;
svg03 = svg03.replace(/#96D41E/gi, '#7FB615');
console.log('wizard-03: #96D41E → #7FB615:', c1, 'px (bright greens)');

// Also merge brown pair: #46360D → #4E342E dist=34.0
let c2 = (svg03.match(/#46360D/gi) || []).length;
svg03 = svg03.replace(/#46360D/gi, '#4E342E');
console.log('wizard-03: #46360D → #4E342E:', c2, 'px (dark browns)');

// And #2D1F1A → #4E342E dist=43.9
let c3 = (svg03.match(/#2D1F1A/gi) || []).length;
svg03 = svg03.replace(/#2D1F1A/gi, '#4E342E');
console.log('wizard-03: #2D1F1A → #4E342E:', c3, 'px (darker brown → brown)');

writeFileSync('public/frens/wizard-03.svg', svg03);

const fills03 = {};
const re = /fill="(#[0-9a-fA-F]{3,6})"/g;
let m;
while ((m = re.exec(svg03)) !== null) { fills03[m[1].toUpperCase()] = (fills03[m[1].toUpperCase()] || 0) + 1; }
console.log('wizard-03 remaining:', Object.keys(fills03).length, 'colors');
for (const [h, c] of Object.entries(fills03).sort((a, b) => b[1] - a[1])) {
    console.log('  ' + h + ' ' + c + 'px');
}

// Also check: #FFFFFF in wizard-05.svg (52px) — merge → #FFC107?
// No, that's too aggressive. But we can try: #6E4803 (829px) is a dark gold
// If we make it slightly closer to #FFC107 by using an intermediate...
// Actually let's not touch wizard-05 more, it's already at 4 colors.
console.log('\nNow recompress and verify...');
