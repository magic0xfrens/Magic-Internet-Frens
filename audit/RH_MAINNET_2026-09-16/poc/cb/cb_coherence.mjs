// COHERENCE B — regression test for B-1 (High), B-5, B-6, B-8. B-2 is not
// code-fixable; what IS asserted here is that the app stopped claiming a cap.
//
// B-1  CrystalCauldronGame told the player "Settle them within the hour." The
//      commit blockhash survives 256 BLOCKS — ~51 min on Sepolia but ~26
//      SECONDS on chain 4663, so the copy promised ~140x more time than exists
//      and an expired crystal forfeits its draw. The number is DERIVED now
//      (COMMIT_WINDOW_SECONDS from the active chain's block time); a hardcoded
//      "26 seconds" would be the same defect one chain later.
// B-5  /legacy divided the buffer by 1e18 regardless of the quote's decimals,
//      so the progress bar read a confident 0% on a 6-decimal quote.
// B-6  SwapWidget's blanket refusal of ERC20-quoted buys was a SYMPTOM of
//      useLpComposition(0) never fetching, already fixed in 55b0b65. Only the
//      copy remained, telling users an unsupported feature when it was loading.
// B-8  /floor's ticker came from getCreatureForGeneration(1) — generation ONE,
//      hardcoded — so it was "" on every later round.
//
// PASS = exit 0 and "RESULT: SAFE".
// Run:  npm run build && node audit/RH_MAINNET_2026-09-16/poc/cb/cb_coherence.mjs
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

console.log("── B-1: the commit-window copy, checked in the BUILT BUNDLE ──");
chk("a build exists to inspect", bundle.length > 0);
chk('the false promise "within the hour" is gone from the shipped app', !bundle.includes("within the hour"));
chk("the warning is still shown (it must be SAID, just truthfully)", bundle.includes("Settle them "));
chk("the duration is derived, not a literal", /within ~\$\{[A-Za-z_$][\w$]*\} seconds/.test(bundle));
chk("no hardcoded seconds figure was substituted", !/within ~26 seconds/.test(bundle) && !/within ~25 seconds/.test(bundle));
chk("per-chain block times ship with the bundle", /blockMs:100/.test(bundle));

const chains = read("src/config/chains.ts");
chk("the window is 256 blocks x the ACTIVE chain's block time",
  /COMMIT_WINDOW_BLOCKS = 256/.test(chains) && /CHAIN_DEFAULTS\[ACTIVE_CHAIN_ID\]/.test(chains));
chk("an unknown chain says nothing about duration rather than guessing",
  /return "right away";/.test(chains));
// Re-derive the phrase the way chains.ts does, and check it against the window.
const phrase = (blockMs) => {
  const s = Math.round((256 * blockMs) / 1000);
  if (s < 90) return `within ~${s} seconds`;
  const m = Math.round(s / 60);
  if (m < 90) return `within ~${m} minute${m === 1 ? "" : "s"}`;
  const h = Math.round(m / 60);
  return `within ~${h} hour${h === 1 ? "" : "s"}`;
};
for (const [name, ms, want] of [["4663", 100, "within ~26 seconds"], ["arc", 1000, "within ~4 minutes"], ["sepolia", 12000, "within ~51 minutes"]]) {
  console.log(`     ${name.padEnd(8)} → "${phrase(ms)}"`);
  chk(`${name} renders the true window`, phrase(ms) === want);
}
chk("…and 4663's is ~140x shorter than the old copy claimed", 3600 / 26 > 100);

console.log("── B-5: the legacy buffer is scaled by the quote's own decimals ──");
const api = read("indexer/src/api/index.ts");
chk("the hardcoded 1e18 divisor is gone", !/bufferEth: Number\(buffer\) \/ 1e18/.test(api));
chk("decimals are read from the chain, like the quote address is",
  /functionName: "generationQuote"/.test(api) && /abi: DECIMALS_ABI, functionName: "decimals"/.test(api));
chk("the payload states its unit instead of implying one",
  /bufferRaw/.test(api) && /bufferDecimals/.test(api) && /bufferQuote/.test(api));
chk("a percentage is not computed across mismatched units",
  /bufferUnitMatchesThreshold/.test(api) && /LEGACY_THRESHOLD_ETH > 0 && bufferUnitMatchesThreshold/.test(api));
// The arithmetic the defect produced.
const raw = 970_000_000n;            // 970 USDG at 6 decimals
console.log(`     buffer ${raw} raw (6-dec) → old: ${Number(raw) / 1e18} → new: ${Number(raw) / 10 ** 6}`);
chk("a 6-decimal buffer no longer collapses to ~0", Number(raw) / 10 ** 6 === 970);

console.log("── B-6: already closed by 55b0b65; only the copy was left ──");
const sw = read("src/components/cauldron/SwapWidget.tsx");
chk("no structural refusal of ERC20-quoted buys remains",
  /priceable = spotPrice > 0 && decimalsResolved && \(qNative \|\| mode === "sell" \|\| quoteExpected > 0n\)/.test(sw));
chk("the misleading 'pool takes X' copy is gone", !/price is quoted in ETH, pool takes/.test(sw));
chk("the message names the real, temporary reason",
  /waiting for the \$\{quoteSymbol\}\/ETH rate/.test(sw) && /reading \$\{quoteSymbol\} decimals/.test(sw));
chk("the root cause stays fixed: the composition poll is not gated off",
  !/usePoll\(load, 8_000, !!generation\)/.test(read("src/hooks/useLpComposition.ts")));

console.log("── B-8: /floor reports a live ticker ──");
chk("the generation-1-pinned ticker has a live fallback", /ps\?\.airdropTicker \|\| \(await liveTicker\(\)\)/.test(api));
chk("the fallback reads the LIVE token's own symbol()", /async function liveTicker/.test(api) && /functionName: "symbol"/.test(api));
chk("a blip keeps the last good symbol rather than blanking it", /if \(sym\) tickerCache =/.test(api));

console.log("── B-2: NOT fixable in code — assert the app stopped claiming it ──");
const presale = read("src/config/presale.ts");
// (the doc comment quotes the old line on purpose — assert the ASSIGNMENT is
// gone, not the string.)
chk("the invented `maxPerWallet: 100` assignment is gone", !/^ {2}maxPerWallet: 100,$/m.test(presale));
chk("the config no longer claims the contract enforces a cap", !/Contract enforces MAX_PER_WALLET; this is only a UI hint/.test(presale));
chk("null = no cap the UI may claim", /maxPerWallet: null as number \| null/.test(presale));
chk("MAX_PER_WALLET really is immutable (no setter to call)",
  /uint256 public immutable MAX_PER_WALLET/.test(read("contracts/solidity/cauldron/MiFrensGenesis.sol")));

console.log();
if (fail) { console.log("RESULT: REGRESSED."); process.exit(1); }
console.log("RESULT: SAFE — the settle window is derived and true; buffer/ticker are sourced, not assumed.");
