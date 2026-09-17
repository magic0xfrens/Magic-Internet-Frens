// RH1 follow-up — REGRESSION TEST for the `usePoll` stale-input class, in the
// two hooks that were flagged but not owned, plus the one the trace led to.
//
// THE SHAPE: `usePoll(fn, ms, enabled)`'s effect deps are [intervalMs, enabled]
// ONLY (src/hooks/usePoll.ts). When `enabled` is already true, a change in the
// input `fn` closes over never restarts the poll, so the hook keeps serving the
// PREVIOUS input's answer for a whole period. Having the shape is not the
// question; what a stale value CAUSES is.
//
//   useSwapTape      — FIXED. `load` closes over `generation`, and the tape is
//                      the app's live price source: TheCauldron:510 takes its
//                      last row as `livePerpPrice` -> SwapWidget `spotPrice` ->
//                      the SIGNED minOut. Across a relaunch the user signed a
//                      floor against the PREVIOUS generation's token price.
//   useLpComposition — no stale-per-generation value (its `load` closes over
//                      nothing generation-dependent). But `!!generation` gated
//                      the POLL, and the two signing call sites pass 0, so it
//                      never fetched: `prices` {} -> `quoteExpected` 0n -> every
//                      ERC20-quoted buy unpriceable. Fail-closed, permanently.
//   useActivityFeed  — NO CHANGE NEEDED. Its only consumer is
//                      TheCauldron.tsx:808 `<ActivityDrawer events={activity}>`.
//                      A stale drawer row cannot produce a signature or an
//                      amount; it shows the previous brew's trades for <=30 s.
//
// PASS = exit 0 and "RESULT: SAFE".
// Run:  npm run build && node audit/RH_MAINNET_2026-09-16/poc/rh1/rh1_stale_tape_generation.mjs
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

// ── 1. What the defect cost, simulated against the real minOut arithmetic ────
// SwapWidget.tsx: estTokensOut = netOfFee(pay)/spotPrice; minOut = that * (1-slip).
const FEE_BPS = 100n, SLIP_BPS = 200n;
const minOutFor = (payEth, spot) => {
  const net = (BigInt(Math.round(payEth * 1e18)) * (10_000n - FEE_BPS)) / 10_000n;
  const outWei = (net * BigInt(Math.round(1e18 / spot))) / (10n ** 18n);
  return (outWei * (10_000n - SLIP_BPS)) / 10_000n;
};
const GEN_N_PRICE = 0.0000004;      // the relaunched brew: a fresh, cheap token
const GEN_PREV_PRICE = 0.00004;     // the brew that just died, 100x richer
const stale = minOutFor(1, GEN_PREV_PRICE);
const honest = minOutFor(1, GEN_N_PRICE);
console.log("── what a stale tape costs, across a relaunch (1 ETH buy) ──");
console.log(`  floor off the PREVIOUS generation's price : ${stale} token-wei`);
console.log(`  floor off the LIVE generation's price     : ${honest} token-wei`);
console.log(`  ratio: 1 : ${Number(honest / stale)}  — the stale floor is ~100x too LOW,`);
console.log("  i.e. nonzero (so `minOut <= 0n` never fires) but effectively absent.\n");

// ── 2. The mechanism, in source ──────────────────────────────────────────────
const tape = read("src/hooks/useSwapTape.ts");
const lp = read("src/hooks/useLpComposition.ts");
const feed = read("src/hooks/useActivityFeed.ts");
const cauldron = read("src/components/cauldron/TheCauldron.tsx");

console.log("── useSwapTape: FIXED ──");
chk("the tape state is keyed by the generation it was read for",
  /useState<\{ gen: number; rows: Trade\[\] \}>/.test(tape));
chk("an unkeyed `setTrades(rows)` is gone", !/setTrades\(/.test(tape));
chk("an effect invalidates and re-reads on a generation change",
  /\}, \[load, generation\]\);/.test(tape));
chk("a generation it has not read returns nothing, not a stale row",
  /return state\.gen === generation \? state\.rows : EMPTY_TRADES;/.test(tape));
chk("…and TheCauldron then falls back to the machine's own spot price",
  /tradeTape\.length \? tradeTape\[tradeTape\.length - 1\]\.price : m\.spotPrice/.test(cauldron));

console.log("── useLpComposition: FIXED (a different defect from the one suspected) ──");
chk("the poll is no longer gated off by a 0 generation", !/usePoll\(load, 8_000, !!generation\)/.test(lp));
chk("generation is used as a re-fetch key instead", /\}, \[load, generation\]\);/.test(lp));
chk("(context) the two signing call sites do pass 0",
  /useLpComposition\(0\)/.test(read("src/components/cauldron/SwapWidget.tsx"))
  && /useLpComposition\(0\)/.test(read("src/components/cauldron/CrystalCauldronGame.tsx")));

console.log("── useActivityFeed: NO CHANGE NEEDED, asserted ──");
chk("it still has the shape (load closes over generation)", /\}, \[generation\]\);/.test(feed));
chk("but its ONLY consumer is the display drawer", /<ActivityDrawer events=\{activity\}/.test(cauldron));
chk("and nothing reads a field off it", !/\bactivity\.[a-z]/.test(cauldron));

console.log("── dist/ (emitted code, not source) ──");
chk("a build exists to inspect", bundle.length > 0);
//  Minified: useEffect(()=>{ n(a=>a.gen===<gen>?a:{gen:0,rows:[]}), <load>() },[<load>,<gen>])
const m = bundle.match(/useEffect\(\(\)=>\{[^}]*gen===([A-Za-z_$][\w$]*)\?[^}]*\{gen:0,rows:\[\]\}\)[^}]*\},\[([^\]]*)\]\)/);
chk("the tape's invalidate effect is in the bundle", !!m);
if (m) {
  const deps = m[2].split(",").map((d) => d.trim());
  console.log(`     compiled deps: [${deps.join(", ")}]   (generation identifier: ${m[1]})`);
  chk("the generation is one of its deps", deps.includes(m[1]));
}

console.log();
if (fail) { console.log("RESULT: REGRESSED."); process.exit(1); }
console.log("RESULT: SAFE — the price tape cannot outlive its generation; the composition poll runs; the feed is display-only.");
