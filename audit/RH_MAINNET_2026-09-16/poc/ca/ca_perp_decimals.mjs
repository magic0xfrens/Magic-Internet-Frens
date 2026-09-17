// COHERENCE A — regression test for CA-1 (High), CA-2, and the liquidation
// disclosure gap.
//
// CA-1  PerpEngine emits `collateral`, `payout` and `pnl` in the LIVE QUOTE's
//       raw units. The read layer divided by a hardcoded 1e18 (indexer ingest)
//       and formatEther'd OI/PLV/depth (indexer API), so after a rotation into a
//       6-decimal quote EVERY absolute number on the perp panel read ~0.
//       The trap: `roiPct` is a ratio of two equally wrong numbers, so the
//       PERCENTAGE stayed correct and the panel looked internally consistent —
//       a trader had nothing to notice while sizing against figures 1e12 off.
// CA-2  `Ξ` was a hardcoded literal, so a USDG book was labelled as ether.
// Disc. The in-swap liquidation sweep was disclosed only in the LiqGasStarved
//       error string, shown to the under-gassed swapper — never to the trader
//       being swept.
//
// PASS = exit 0 and "RESULT: SAFE".
// Run:  npm run build && node audit/RH_MAINNET_2026-09-16/poc/ca/ca_perp_decimals.mjs
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../../..");
const read = (p) => readFileSync(join(ROOT, p), "utf8");
let bundle = "";
try {
  const D = join(ROOT, "dist/assets");
  for (const f of readdirSync(D)) if (f.endsWith(".js")) bundle += readFileSync(join(D, f), "utf8");
} catch { /* no dist */ }

let fail = 0;
const chk = (d, ok) => { console.log(`  ${ok ? "ok  " : "FAIL"} — ${d}`); if (!ok) fail = 1; };

// ── 1. The defect, replayed against the exact expressions ───────────────────
console.log("── what the 1e18 assumption cost (6-decimal quote, $50,000) ──");
const collateral = 50_000n * 10n ** 6n;
const pnl = 5_000n * 10n ** 6n;
const oldVal = Number(collateral) / 1e18;
const newVal = Number(collateral) / 10 ** 6;
console.log(`  old  Number(collateral)/1e18  = ${oldVal}  → rendered "${oldVal.toFixed(4)} Ξ collateral"`);
console.log(`  new  Number(collateral)/1e6   = ${newVal}`);
console.log(`  roiPct is a RATIO, so it read correctly either way: ${((Number(pnl) / Number(collateral)) * 100).toFixed(2)}%`);
chk("the corrected scale recovers the real figure", newVal === 50000);
chk("the old scale really did render zero to 4dp", oldVal.toFixed(4) === "0.0000");
chk("…while the percentage stayed right, which is why nobody caught it",
  ((Number(pnl) / Number(collateral)) * 100).toFixed(2) === "10.00");

// ── 2. Indexer ingest ───────────────────────────────────────────────────────
console.log("── indexer/src/index.ts (ingest) ──");
const ing = read("indexer/src/index.ts");
chk("collateral is no longer divided by a hardcoded 1e18",
  !/const collateralEth = Number\(event\.args\.collateral\) \/ 1e18;/.test(ing));
chk("payout/pnl are no longer divided by a hardcoded 1e18",
  !/const payout = Number\(event\.args\.payout\) \/ 1e18;/.test(ing));
chk("all three use the generation's quote decimals",
  /collateral\) \/ 10 \*\* qDec/.test(ing) && /payout\) \/ 10 \*\* cDec/.test(ing) && /pnl\) \/ 10 \*\* cDec/.test(ing));
chk("`size` is deliberately still 18 — it is the brew's own token, not the quote",
  /const sizeTok = Number\(event\.args\.size\) \/ 1e18;/.test(ing));
chk("decimals are read from the chain and validated 0..36",
  /async function quoteDecimalsForGen/.test(ing) && /d >= 0 && d <= 36/.test(ing));
chk("a failed read is NOT cached (an RPC blip must not pin the wrong scale)",
  /catch \{ \/\* transient: leave uncached so the next event retries \*\/ \}/.test(ing));

// ── 3. Indexer API ──────────────────────────────────────────────────────────
console.log("── indexer/src/api/index.ts (read API) ──");
const api = read("indexer/src/api/index.ts");
// Scoped to liveStats: the vault helpers elsewhere in this file legitimately
// keep a formatEther `n` for the TOKEN side and unitless share counts, paired
// with a decimals-aware `q` for the quote side — that pattern is correct and
// must not be "fixed".
const liveStatsBody = api.slice(api.indexOf("async function liveStats()"), api.indexOf("/* \u2500\u2500 full BREW state"));
chk("liveStats no longer formatEthers quote-denominated values",
  !/const n = \(v: bigint\) => Number\(formatEther\(v\)\);/.test(liveStatsBody));
chk("(and the vault's correct quote/token split is untouched)",
  /const q = \(v: bigint\) => rawToQuoteAmount\(v, qd\);/.test(api));
chk("it scales by the live quote's decimals", /const n = \(v: bigint\) => Number\(v\) \/ 10 \*\* qm\.decimals;/.test(api));
chk("plvToken keeps the 18-decimal token scale", /const nTok = \(v: bigint\) => Number\(formatEther\(v\)\);/.test(api) && /plvToken: nTok\(/.test(api));
chk("the depth fallback re-inflates on the SAME base it deflated on",
  /statsCache\.v\.depthEth \* 10 \*\* qm\.decimals/.test(api));
chk("the payload STATES its unit instead of implying it from a field name",
  /quoteSymbol: live\?\.quoteSymbol \?\? "ETH"/.test(api) && /quoteDecimals: live\?\.quoteDecimals \?\? 18/.test(api));
chk("the LP quote side no longer assumes 1e18 either",
  !/return Number\(formatEther\(quoteWei\)\);/.test(api) && /rawToQuoteAmount\(quoteWei, await liveQuoteDecimals\(\)\)/.test(api));

// ── 4. Frontend + the BUILT BUNDLE ──────────────────────────────────────────
console.log("── frontend, verified in dist/ ──");
chk("a build exists to inspect", bundle.length > 0);
chk('the shipped string "Ξ collateral" is gone', !bundle.includes("Ξ collateral"));
chk("the glyph is a variable in the emitted code", /collateralEth\.toFixed\(4\),"\s*",[A-Za-z_$][\w$]*,"\s*collateral/.test(bundle));
const panel = read("src/components/cauldron/PerpPanel.tsx");
chk("the panel derives its glyph from the live quote", /const qGlyph = qNative \? "Ξ" : quoteSymbol;/.test(panel));
chk("the position card is given the glyph rather than defaulting to ether", /qGlyph=\{qGlyph\}/.test(panel));
const hook = read("src/hooks/usePerpEngine.ts");
chk("the stats hook carries quoteSymbol/quoteDecimals", /quoteSymbol: string;/.test(hook) && /quoteDecimals: number;/.test(hook));

console.log("── disclosure: who can close your position ──");
chk("the panel tells a trader a stranger's swap can liquidate them",
  /Another trader's swap can liquidate you inside their transaction/.test(panel));
chk("…and that the price is a projection, not the chart", /projects/.test(panel));
chk("it is shown where a position is OPENED, not only in an error string",
  panel.indexOf("Another trader's swap can liquidate you") < panel.indexOf("function PositionCard"));
chk("the QueueInsolvent remedy stays disclosed (already closed — do not regress)",
  /0x42b0b17a/.test(read("src/config/perp.ts")));

console.log();
if (fail) { console.log("RESULT: REGRESSED."); process.exit(1); }
console.log("RESULT: SAFE — perp figures are scaled and labelled by the live quote; the sweep is disclosed.");
